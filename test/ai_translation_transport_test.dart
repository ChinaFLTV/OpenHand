import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openhand/features/ai/model/ai_translation_settings.dart';
import 'package:openhand/features/ai/service/operations/ai_translation_service.dart';

void main() {
  test('translation providers use abortable JSON transport', () async {
    final aborted = Completer<void>();
    final client = _CallbackClient((request) async {
      expect(request, isA<http.AbortableRequest>());
      if (request case http.Abortable(:final abortTrigger?)) {
        abortTrigger.whenComplete(() {
          if (!aborted.isCompleted) aborted.complete();
        });
      }
      final body = jsonDecode((request as http.Request).body);
      expect(body, <String, Object?>{
        'q': 'hello',
        'target': 'zh-CN',
        'format': 'text',
      });
      return http.StreamedResponse(
        Stream<List<int>>.value(
          utf8.encode('{"data":{"translations":[{"translatedText":"你好"}]}}'),
        ),
        200,
        request: request,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final service = AiTranslationService(client: client);
    try {
      final result = await service.translate(
        text: 'hello',
        settings: _googleSettings(),
        availableModels: const [],
      );

      expect(result.text, '你好');
      expect(result.provider, AiTranslationProvider.google);
      await aborted.future.timeout(const Duration(seconds: 1));
    } finally {
      service.dispose();
    }
  });

  test('translation rejects and cancels an oversized response', () async {
    final cancelled = Completer<void>();
    final controller = StreamController<List<int>>(
      onCancel: () {
        if (!cancelled.isCompleted) cancelled.complete();
      },
    );
    final client = _CallbackClient(
      (request) async => http.StreamedResponse(
        controller.stream,
        200,
        request: request,
        headers: const <String, String>{'content-type': 'application/json'},
      ),
    );
    final service = AiTranslationService(client: client);
    final translation = service.translate(
      text: 'oversized-translation-response',
      settings: _googleSettings(),
      availableModels: const [],
    );
    controller.add(List<int>.filled(1024 * 1024 + 1, 0x78));

    try {
      await expectLater(
        translation,
        throwsA(
          isA<AiTranslationException>().having(
            (error) => error.message,
            'message',
            contains('byte limit'),
          ),
        ),
      );
      await cancelled.future.timeout(const Duration(seconds: 1));
    } finally {
      await controller.close();
      service.dispose();
    }
  });

  test('all direct providers preserve their wire contracts', () async {
    final cases = <_TranslationProviderCase>[
      _TranslationProviderCase(
        provider: AiTranslationProvider.youdao,
        responseBody: '{"errorCode":"0","translation":["你好"]}',
        verify: (request) {
          expect(request.headers['content-type'], contains('form-urlencoded'));
          expect(request.bodyFields['q'], 'hello-youdao');
          expect(request.bodyFields['appKey'], 'api-key');
          expect(request.bodyFields['signType'], 'v3');
        },
      ),
      _TranslationProviderCase(
        provider: AiTranslationProvider.bing,
        responseBody: '[{"translations":[{"text":"你好"}]}]',
        verify: (request) {
          expect(request.headers['content-type'], contains('application/json'));
          expect(request.headers['ocp-apim-subscription-key'], 'api-key');
          expect(
            request.headers['ocp-apim-subscription-region'],
            'test-region',
          );
          expect(jsonDecode(request.body), <Object?>[
            <String, Object?>{'Text': 'hello-bing'},
          ]);
        },
      ),
      _TranslationProviderCase(
        provider: AiTranslationProvider.apple,
        responseBody: '{"translated_text":"你好"}',
        verify: (request) {
          expect(request.headers['x-api-key'], 'api-key');
          expect(request.headers['authorization'], 'Bearer access-token');
          expect(jsonDecode(request.body), <String, Object?>{
            'text': 'hello-apple',
            'source_language': 'auto',
            'target_language': 'zh-CN',
          });
        },
      ),
      _TranslationProviderCase(
        provider: AiTranslationProvider.baidu,
        responseBody: '{"trans_result":[{"dst":"你好"}]}',
        verify: (request) {
          expect(request.headers['content-type'], contains('form-urlencoded'));
          expect(request.bodyFields['q'], 'hello-baidu');
          expect(request.bodyFields['appid'], 'app-id');
          expect(request.bodyFields['sign'], hasLength(32));
        },
      ),
      _TranslationProviderCase(
        provider: AiTranslationProvider.doubao,
        responseBody:
            '{"code":20000000,"data":{"translation_list":[{"translation":"你好"}]}}',
        verify: (request) {
          expect(request.headers['x-api-key'], 'api-key');
          expect(request.headers['x-api-resource-id'], isNotEmpty);
          expect(request.headers['x-api-request-id'], isNotEmpty);
          expect(jsonDecode(request.body), <String, Object?>{
            'target_language': 'zh',
            'text_list': <Object?>['hello-doubao'],
          });
        },
      ),
    ];

    for (final providerCase in cases) {
      final client = _CallbackClient((request) async {
        expect(request, isA<http.AbortableRequest>());
        providerCase.verify(request as http.Request);
        return http.StreamedResponse(
          Stream<List<int>>.value(utf8.encode(providerCase.responseBody)),
          200,
          request: request,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      });
      final service = AiTranslationService(client: client);
      try {
        final result = await service.translate(
          text: 'hello-${providerCase.provider.storageKey}',
          settings: _settingsForProvider(providerCase.provider),
          availableModels: const [],
        );
        expect(result.text, '你好');
        expect(result.provider, providerCase.provider);
      } finally {
        service.dispose();
      }
    }
  });
}

AiTranslationSettings _googleSettings() {
  final defaults = AiTranslationSettings.defaults();
  return defaults.copyWith(
    enabled: true,
    providers: <AiTranslationProvider, AiTranslationProviderSettings>{
      ...defaults.providers,
      AiTranslationProvider.google: AiTranslationProviderSettings.defaults(
        AiTranslationProvider.google,
      ).copyWith(enabled: true, apiKey: 'test-key'),
    },
    providerPriority: const <AiTranslationProvider>[
      AiTranslationProvider.google,
    ],
  );
}

AiTranslationSettings _settingsForProvider(AiTranslationProvider provider) {
  final defaults = AiTranslationSettings.defaults();
  final providerSettings = AiTranslationProviderSettings.defaults(provider)
      .copyWith(
        enabled: true,
        endpoint: 'https://translation.example.test/${provider.storageKey}',
        appId: 'app-id',
        apiKey: 'api-key',
        apiSecret: 'api-secret',
        accessToken: 'access-token',
        region: 'test-region',
      );
  return defaults.copyWith(
    enabled: true,
    providers: <AiTranslationProvider, AiTranslationProviderSettings>{
      ...defaults.providers,
      provider: providerSettings,
    },
    providerPriority: <AiTranslationProvider>[provider],
  );
}

class _TranslationProviderCase {
  const _TranslationProviderCase({
    required this.provider,
    required this.responseBody,
    required this.verify,
  });

  final AiTranslationProvider provider;
  final String responseBody;
  final void Function(http.Request request) verify;
}

class _CallbackClient extends http.BaseClient {
  _CallbackClient(this.onSend);

  final Future<http.StreamedResponse> Function(http.BaseRequest request) onSend;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      onSend(request);
}
