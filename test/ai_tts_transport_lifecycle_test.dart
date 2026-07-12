import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openhand/features/ai/model/ai_creation_mode.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_tts_settings.dart';
import 'package:openhand/features/ai/service/media/ai_image_generation_service.dart';
import 'package:openhand/features/ai/service/operations/ai_tts_playback_service.dart';
import 'package:openhand/features/ai/service/runtime/ai_transport_client.dart';

void main() {
  test(
    'direct audio responses reject declared overflow before buffering',
    () async {
      final cancelled = Completer<void>();
      final body = StreamController<List<int>>(
        onCancel: () {
          if (!cancelled.isCompleted) cancelled.complete();
        },
      );
      final client = _CallbackClient(
        (request) async => http.StreamedResponse(
          body.stream,
          200,
          request: request,
          contentLength: 64 * 1024 * 1024 + 1,
          headers: const <String, String>{'content-type': 'audio/mpeg'},
        ),
      );
      final service = _serviceWithClient(client);
      try {
        await expectLater(
          service.testProvider(
            settings: _settingsFor(
              AiTtsProvider.bing,
              apiKey: 'test-key',
              endpoint: 'https://tts.example.test/speech',
            ),
            provider: AiTtsProvider.bing,
          ),
          throwsA(isA<Exception>()),
        );
        await cancelled.future.timeout(const Duration(seconds: 1));
      } finally {
        await body.close();
        await service.dispose();
      }
    },
  );

  test('stop aborts a request waiting for response headers', () async {
    final requestStarted = Completer<void>();
    final aborted = Completer<void>();
    final headers = Completer<http.StreamedResponse>();
    final client = _CallbackClient((request) {
      if (request case http.Abortable(:final abortTrigger?)) {
        abortTrigger.whenComplete(() {
          if (!aborted.isCompleted) aborted.complete();
          if (!headers.isCompleted) {
            headers.completeError(
              http.ClientException('cancelled by TTS operation', request.url),
            );
          }
        });
      }
      if (!requestStarted.isCompleted) requestStarted.complete();
      return headers.future;
    });
    final service = _serviceWithClient(client);
    final playback = service.testProvider(
      settings: _settingsFor(
        AiTtsProvider.google,
        apiKey: 'test-key',
        endpoint: 'https://tts.example.test/speech',
      ),
      provider: AiTtsProvider.google,
    );

    try {
      await requestStarted.future.timeout(const Duration(seconds: 1));
      await service.stop().timeout(const Duration(seconds: 1));
      await playback.timeout(const Duration(seconds: 1));
      await aborted.future.timeout(const Duration(seconds: 1));
    } finally {
      await service.dispose();
    }
  });

  test('Doubao streaming parser preserves UTF-8 across chunks', () async {
    final payload = utf8.encode('{"code":1,"message":"跨块错误"}');
    final split = payload.indexOf(0xe8) + 1;
    final client = _CallbackClient(
      (request) async => http.StreamedResponse(
        Stream<List<int>>.fromIterable(<List<int>>[
          payload.sublist(0, split),
          payload.sublist(split),
        ]),
        200,
        request: request,
        headers: const <String, String>{'content-type': 'application/json'},
      ),
    );
    final service = _serviceWithClient(client);
    try {
      await expectLater(
        service.testProvider(
          settings: _settingsFor(
            AiTtsProvider.doubao,
            apiKey: 'test-key',
            endpoint: 'https://tts.example.test/stream',
          ),
          provider: AiTtsProvider.doubao,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('跨块错误'),
          ),
        ),
      );
    } finally {
      await service.dispose();
    }
  });

  test('Doubao rejects an incomplete streamed JSON object', () async {
    final client = _CallbackClient(
      (request) async => http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode('{"data":"AA=="')),
        200,
        request: request,
        headers: const <String, String>{'content-type': 'application/json'},
      ),
    );
    final service = _serviceWithClient(client);
    try {
      await expectLater(
        service.testProvider(
          settings: _settingsFor(
            AiTtsProvider.doubao,
            apiKey: 'test-key',
            endpoint: 'https://tts.example.test/stream',
          ),
          provider: AiTtsProvider.doubao,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('incomplete JSON'),
          ),
        ),
      );
    } finally {
      await service.dispose();
    }
  });

  test('Doubao trickle traffic cannot outlive the total deadline', () async {
    final cancelled = Completer<void>();
    final controller = StreamController<List<int>>(
      onCancel: () {
        if (!cancelled.isCompleted) cancelled.complete();
      },
    );
    final timer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => controller.add(const <int>[0x20]),
    );
    final client = _CallbackClient(
      (request) async => http.StreamedResponse(
        controller.stream,
        200,
        request: request,
        headers: const <String, String>{'content-type': 'application/json'},
      ),
    );
    final service = _serviceWithClient(client);
    try {
      await expectLater(
        service.testProvider(
          settings: _settingsFor(
            AiTtsProvider.doubao,
            apiKey: 'test-key',
            endpoint: 'https://tts.example.test/stream',
          ).copyWith(timeoutSeconds: AiTtsSettings.minTimeoutSeconds),
          provider: AiTtsProvider.doubao,
        ),
        throwsA(isA<TimeoutException>()),
      );
      await cancelled.future.timeout(const Duration(seconds: 1));
    } finally {
      timer.cancel();
      await controller.close();
      await service.dispose();
    }
  });

  test('Mimo rejects an oversized clone sample before HTTP', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'openhand_mimo_voice_sample_',
    );
    final sample = File('${tempDirectory.path}/sample.wav');
    final output = await sample.open(mode: FileMode.write);
    await output.setPosition(10 * 1024 * 1024);
    await output.writeByte(0);
    await output.close();
    var requests = 0;
    final service = _serviceWithClient(
      _CallbackClient((_) {
        requests += 1;
        throw StateError('Oversized samples must not reach HTTP.');
      }),
    );
    try {
      await expectLater(
        service.testProvider(
          settings: _settingsFor(
            AiTtsProvider.mimo,
            apiKey: 'test-key',
            endpoint: 'https://tts.example.test/speech',
            extra: <String, Object?>{
              'model': 'mimo-v2.5-tts-voiceclone',
              'voice_sample_path': sample.path,
              'format': 'wav',
            },
          ),
          provider: AiTtsProvider.mimo,
        ),
        throwsA(isA<IOException>()),
      );
      expect(requests, 0);
    } finally {
      await service.dispose();
      await tempDirectory.delete(recursive: true);
    }
  });

  test('HTTP TTS providers preserve their request contracts', () async {
    final cases = <_TtsRequestCase>[
      _TtsRequestCase(
        provider: AiTtsProvider.mimo,
        settings: _settingsFor(
          AiTtsProvider.mimo,
          apiKey: 'test-key',
          endpoint: 'https://tts.example.test/mimo',
        ),
        verify: (request) {
          expect(request.method, 'POST');
          expect(request.headers['api-key'], 'test-key');
          final body = jsonDecode(request.body) as Map;
          expect(body['model'], 'mimo-v2.5-tts');
          expect(body['messages'], isA<List>());
          expect(body['audio'], isA<Map>());
        },
      ),
      _TtsRequestCase(
        provider: AiTtsProvider.doubao,
        settings: _settingsFor(
          AiTtsProvider.doubao,
          apiKey: 'test-key',
          endpoint: 'https://tts.example.test/doubao',
        ),
        verify: (request) {
          expect(request.method, 'POST');
          expect(request.headers['x-api-key'], 'test-key');
          expect(request.headers['x-api-resource-id'], isNotEmpty);
          expect(request.headers['x-api-request-id'], isNotEmpty);
          expect((jsonDecode(request.body) as Map)['req_params'], isA<Map>());
        },
      ),
      _TtsRequestCase(
        provider: AiTtsProvider.baidu,
        settings: _settingsFor(
          AiTtsProvider.baidu,
          apiKey: '',
          endpoint: 'https://tts.example.test/baidu',
          accessToken: 'access-token',
        ),
        verify: (request) {
          expect(request.method, 'GET');
          expect(request.url.queryParameters['tok'], 'access-token');
          expect(
            request.url.queryParameters['tex'],
            AiTtsPlaybackService.settingsTestText,
          );
          expect(request.url.queryParameters['ctp'], '1');
        },
      ),
      _TtsRequestCase(
        provider: AiTtsProvider.google,
        settings: _settingsFor(
          AiTtsProvider.google,
          apiKey: 'test-key',
          endpoint: 'https://tts.example.test/google',
        ),
        verify: (request) {
          expect(request.method, 'POST');
          expect(request.url.queryParameters['key'], 'test-key');
          final body = jsonDecode(request.body) as Map;
          expect(body['input'], <String, Object?>{
            'text': AiTtsPlaybackService.settingsTestText,
          });
          expect(body['audioConfig'], isA<Map>());
        },
      ),
      _TtsRequestCase(
        provider: AiTtsProvider.bing,
        settings: _settingsFor(
          AiTtsProvider.bing,
          apiKey: 'test-key',
          endpoint: 'https://tts.example.test/bing',
        ),
        verify: (request) {
          expect(request.method, 'POST');
          expect(request.headers['ocp-apim-subscription-key'], 'test-key');
          expect(request.headers['x-microsoft-outputformat'], isNotEmpty);
          expect(request.headers['content-type'], contains('ssml+xml'));
          expect(request.body, contains('<speak'));
        },
      ),
      _TtsRequestCase(
        provider: AiTtsProvider.youdao,
        settings: _settingsFor(
          AiTtsProvider.youdao,
          apiKey: 'test-key',
          apiSecret: 'test-secret',
          endpoint: 'https://tts.example.test/youdao',
        ),
        verify: (request) {
          expect(request.method, 'POST');
          expect(request.headers['content-type'], contains('form-urlencoded'));
          expect(request.bodyFields['appKey'], 'test-key');
          expect(request.bodyFields['signType'], 'v3');
          expect(request.bodyFields['sign'], hasLength(64));
        },
      ),
    ];

    for (final providerCase in cases) {
      final service = _serviceWithClient(
        _CallbackClient((request) async {
          expect(request, isA<http.AbortableRequest>());
          providerCase.verify(request as http.Request);
          return http.StreamedResponse(
            Stream<List<int>>.value(utf8.encode('provider error')),
            401,
            request: request,
            headers: const <String, String>{'content-type': 'text/plain'},
          );
        }),
      );
      try {
        await expectLater(
          service.testProvider(
            settings: providerCase.settings,
            provider: providerCase.provider,
          ),
          throwsA(isA<Exception>()),
        );
      } finally {
        await service.dispose();
      }
    }
  });

  test('stopped AI generation never downloads a late audio URL', () async {
    final generation = _DelayedAudioGenerationService();
    var requests = 0;
    final service = AiTtsPlaybackService(
      mediaGenerationService: generation,
      transportFactory: () => AiTransportClient(
        client: _CallbackClient((_) {
          requests += 1;
          throw StateError('A stopped generation must not start a download.');
        }),
      ),
    );
    const modelId = 'test-audio-model';
    const model = AiModelConfig(
      id: 'test-audio-provider',
      baseUrl: 'https://ai.example.test/v1',
      authScheme: AiAuthScheme.bearer,
      token: 'test-token',
      modelId: modelId,
      protocolType: AiProtocolType.openai,
      modelProfiles: <String, AiModelProfile>{
        modelId: AiModelProfile(
          isMultimodal: true,
          supportedModalities: <AiModelModality>{
            AiModelModality.text,
            AiModelModality.audio,
          },
          capabilities: <AiModelCapability>{AiModelCapability.audioGeneration},
        ),
      },
    );
    final defaults = AiTtsSettings.defaults();
    final aiProvider = AiTtsProviderSettings.defaults(
      AiTtsProvider.ai,
    ).copyWith(enabled: true, modelConfigId: model.id, modelId: model.modelId);
    final settings = defaults.copyWith(
      enabled: true,
      providers: <AiTtsProvider, AiTtsProviderSettings>{
        ...defaults.providers,
        AiTtsProvider.ai: aiProvider,
      },
      providerPriority: const <AiTtsProvider>[AiTtsProvider.ai],
    );
    final playback = service.testProvider(
      settings: settings,
      provider: AiTtsProvider.ai,
      availableModels: const <AiModelConfig>[model],
    );
    try {
      await generation.started.future.timeout(const Duration(seconds: 1));
      await service.stop().timeout(const Duration(seconds: 1));
      generation.completeWithUrl('https://audio.example.test/result.mp3');
      await playback.timeout(const Duration(seconds: 1));
      expect(requests, 0);
    } finally {
      await service.dispose();
      generation.dispose();
    }
  });
}

AiTtsPlaybackService _serviceWithClient(http.Client client) {
  return AiTtsPlaybackService(
    transportFactory: () => AiTransportClient(client: client),
  );
}

AiTtsSettings _settingsFor(
  AiTtsProvider provider, {
  required String apiKey,
  required String endpoint,
  String apiSecret = '',
  String accessToken = '',
  Map<String, Object?> extra = const <String, Object?>{},
}) {
  final defaults = AiTtsSettings.defaults();
  final providerDefaults = AiTtsProviderSettings.defaults(provider);
  final providerSettings = providerDefaults.copyWith(
    enabled: true,
    apiKey: apiKey,
    apiSecret: apiSecret,
    accessToken: accessToken,
    endpoint: endpoint,
    extra: <String, Object?>{...providerDefaults.extra, ...extra},
  );
  return defaults.copyWith(
    enabled: true,
    providers: <AiTtsProvider, AiTtsProviderSettings>{
      ...defaults.providers,
      provider: providerSettings,
    },
    providerPriority: <AiTtsProvider>[provider],
  );
}

class _TtsRequestCase {
  const _TtsRequestCase({
    required this.provider,
    required this.settings,
    required this.verify,
  });

  final AiTtsProvider provider;
  final AiTtsSettings settings;
  final void Function(http.Request request) verify;
}

class _CallbackClient extends http.BaseClient {
  _CallbackClient(this.onSend);

  final Future<http.StreamedResponse> Function(http.BaseRequest request) onSend;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      onSend(request);
}

class _DelayedAudioGenerationService extends AiImageGenerationService {
  _DelayedAudioGenerationService()
    : super(
        client: _CallbackClient(
          (_) => throw StateError('The overridden generator owns no HTTP.'),
        ),
      );

  final Completer<void> started = Completer<void>();
  final Completer<AiMediaGenerationResult> _result =
      Completer<AiMediaGenerationResult>();

  @override
  Future<AiMediaGenerationResult> generateAudio({
    required AiModelConfig model,
    required String prompt,
    AiCreationOptions options = AiCreationOptions.empty,
    Duration timeout = const Duration(minutes: 3),
  }) {
    if (!started.isCompleted) started.complete();
    return _result.future;
  }

  void completeWithUrl(String url) {
    final now = DateTime.now().toUtc();
    _result.complete(
      AiMediaGenerationResult(
        markdown: '[audio]($url)',
        rawResponseBody: '',
        requestUrl: '',
        requestBody: const <String, Object?>{},
        requestHeaders: const <String, String>{},
        startedAt: now,
        endedAt: now,
      ),
    );
  }
}
