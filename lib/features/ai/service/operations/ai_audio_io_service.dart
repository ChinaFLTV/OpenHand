import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../../shared/util/bounded_file_io.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../model/ai_api_family.dart';
import '../../model/ai_model_config.dart';
import '../runtime/ai_endpoint_router.dart';
import '../runtime/ai_transport_client.dart';
import 'ai_operation_http.dart';
import 'ai_stepfun_audio_policy.dart';

class AiAudioIoResult {
  const AiAudioIoResult({
    required this.text,
    required this.rawResponse,
    this.payload = const <String, Object?>{},
  });

  final String text;
  final String rawResponse;
  final Map<String, Object?> payload;
}

class AiSpeechResult {
  const AiSpeechResult({
    required this.bytes,
    required this.rawResponse,
    required this.contentType,
    this.payload = const <String, Object?>{},
  });

  final List<int> bytes;
  final String rawResponse;
  final String contentType;
  final Map<String, Object?> payload;
}

class AiMimoSpeechStreamResult {
  const AiMimoSpeechStreamResult({
    required this.pcm16Bytes,
    required this.chunkCount,
    this.finalTextPreview,
    this.sampleRate = 24000,
  });

  final Uint8List pcm16Bytes;
  final int chunkCount;
  final String? finalTextPreview;
  final int sampleRate;
}

class AiAudioIoService {
  AiAudioIoService({AiEndpointRouter? router, AiTransportClient? transport})
    : _router = router ?? const AiEndpointRouter(),
      _transport = transport ?? AiTransportClient(),
      _ownsTransport = transport == null;

  final AiEndpointRouter _router;
  final AiTransportClient _transport;
  final bool _ownsTransport;

  static const int _maxSpeechResponseBytes = 64 * kBytesPerMiB;
  static const int _mimoMaxAsrBase64Bytes = 10 * kBytesPerMiB;
  static const int _mimoMaxVoiceSampleBase64Bytes = 10 * kBytesPerMiB;
  static const int _mimoMaxVoiceSampleRawBytes =
      (_mimoMaxVoiceSampleBase64Bytes ~/ 4) * 3;
  static const int _mimoMaxPcmResponseBytes = 64 * kBytesPerMiB;
  static const int _mimoMaxSseResponseBytes = 96 * kBytesPerMiB;
  static const Set<String> _mimoTtsModelIds = <String>{
    'mimo-v2.5-tts',
    'mimo-v2.5-tts-voicedesign',
    'mimo-v2.5-tts-voiceclone',
  };
  static const Set<String> _mimoAsrLanguages = <String>{'auto', 'zh', 'en'};

  Future<AiSpeechResult> createSpeech({
    required AiModelConfig model,
    required String input,
    String? voice,
    String? responseFormat,
    String? speed,
    Object? instructions,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    const family = AiApiFamily.audioSpeech;
    final endpoint = _router.resolve(
      model,
      family,
      method: model.requestMethod,
    );
    final modelId = model.resolveOperationModelId(family);
    final stepFunSpeech = AiStepFunAudioPolicy.isStepFunSpeech(
      protocol: model.protocolType,
      modelId: modelId,
    );
    final resolvedVoice =
        nullIfBlank(voice) ??
        nullIfBlank(model.operationRouting.defaultVoice) ??
        (stepFunSpeech ? AiStepFunAudioPolicy.defaultVoice : null);
    final responseFormatValue = nullIfBlank(responseFormat);
    final speedValue = nullIfBlank(speed);
    final validationError = AiStepFunAudioPolicy.inputValidationError(
      protocol: model.protocolType,
      modelId: modelId,
      input: input,
    );
    if (validationError != null) {
      throw ArgumentError.value(input, 'input', validationError);
    }
    final instructionKey = stepFunSpeech ? 'instruction' : 'instructions';
    final baseBody = <String, Object?>{
      'model': modelId,
      'input': input,
      if (resolvedVoice != null) 'voice': resolvedVoice,
      if (responseFormatValue != null) 'response_format': responseFormatValue,
      if (speedValue != null) 'speed': speedValue,
      if (instructions != null) instructionKey: instructions,
    };
    final mergedBody = AiOperationHttp.mergeBodyExtras(model, family, baseBody);
    final body = AiStepFunAudioPolicy.normalizeSpeechBody(
      body: mergedBody,
      protocol: model.protocolType,
      modelId: modelId,
    );
    final response = await AiOperationHttp.sendJsonForFamily(
      transport: _transport,
      endpoint: endpoint,
      model: model,
      family: family,
      body: body,
      timeout: timeout,
      acceptJson: true,
      maxResponseBytes: _maxSpeechResponseBytes,
    );
    AiOperationHttp.throwIfFailed(
      statusCode: response.statusCode,
      body: response.body,
      contextHint: 'audio/speech',
    );
    final contentType = stringFromValue(response.headers['content-type']);
    final isJson = contentType.toLowerCase().contains('json');
    final payload = isJson
        ? AiOperationHttp.jsonMapOrEmpty(
            AiOperationHttp.decodeJsonResponse(
              response.body,
              contextHint: 'audio/speech',
            ),
          )
        : const <String, Object?>{};
    return AiSpeechResult(
      bytes: response.bodyBytes,
      rawResponse: response.body,
      contentType: contentType,
      payload: payload,
    );
  }

  Future<AiAudioIoResult> transcribe({
    required AiModelConfig model,
    required String filePath,
    Duration timeout = const Duration(seconds: 120),
    String? language,
    String? prompt,
    String? responseFormat,
    double? temperature,
    Object? timestampGranularities,
    bool stream = false,
    FutureOr<void> Function(String delta)? onTextDelta,
  }) {
    if (model.protocolType == AiProtocolType.mimo) {
      return _transcribeMimo(
        model: model,
        filePath: filePath,
        timeout: timeout,
        language: language,
        stream: stream,
        onTextDelta: onTextDelta,
      );
    }
    if (stream) {
      throw ArgumentError.value(
        stream,
        'stream',
        'Streaming transcription is currently implemented for MiMo ASR only.',
      );
    }
    return _sendAudioRequest(
      model: model,
      family: AiApiFamily.audioTranscription,
      filePath: filePath,
      timeout: timeout,
      language: language,
      prompt: prompt,
      responseFormat: responseFormat,
      temperature: temperature,
      timestampGranularities: timestampGranularities,
    );
  }

  Future<AiAudioIoResult> _transcribeMimo({
    required AiModelConfig model,
    required String filePath,
    required Duration timeout,
    String? language,
    required bool stream,
    FutureOr<void> Function(String delta)? onTextDelta,
  }) async {
    const family = AiApiFamily.audioTranscription;
    final normalizedLanguage = lowercaseStringFromValue(
      language,
      fallback: 'auto',
    );
    if (!_mimoAsrLanguages.contains(normalizedLanguage)) {
      throw ArgumentError.value(
        language,
        'language',
        'MiMo ASR language must be auto, zh, or en.',
      );
    }
    final extension = File(filePath).uri.pathSegments.last.toLowerCase();
    final mimeType = extension.endsWith('.mp3')
        ? 'audio/mpeg'
        : extension.endsWith('.wav')
        ? 'audio/wav'
        : null;
    if (mimeType == null) {
      throw ArgumentError.value(
        filePath,
        'filePath',
        'MiMo ASR only supports MP3 and WAV files.',
      );
    }
    final file = File(filePath);
    final stat = await file.stat().timeout(timeout);
    if (stat.type != FileSystemEntityType.file || stat.size <= 0) {
      throw ArgumentError.value(filePath, 'filePath', 'Audio file is empty.');
    }
    const maxRawBytes = (_mimoMaxAsrBase64Bytes ~/ 4) * 3;
    if (stat.size > maxRawBytes) {
      throw ArgumentError.value(
        filePath,
        'filePath',
        'MiMo ASR Base64 payload exceeds ${formatByteSize(_mimoMaxAsrBase64Bytes)}.',
      );
    }
    final bytes = await file.readAsBytes().timeout(timeout);
    final endpoint = _router.resolveProviderPath(
      model,
      family,
      path: 'v1/chat/completions',
    );
    final configuredModel = model.resolveOperationModelId(family);
    final asrModel = lowercaseStringFromValue(configuredModel).contains('asr')
        ? configuredModel
        : 'mimo-v2.5-asr';
    final body = AiOperationHttp.mergeBodyExtras(
      model,
      family,
      <String, Object?>{
        'model': asrModel,
        'messages': <Map<String, Object?>>[
          <String, Object?>{
            'role': 'user',
            'content': <Map<String, Object?>>[
              <String, Object?>{
                'type': 'input_audio',
                'input_audio': <String, Object?>{
                  'data': 'data:$mimeType;base64,${base64Encode(bytes)}',
                },
              },
            ],
          },
        ],
        'asr_options': <String, Object?>{'language': normalizedLanguage},
      },
    );
    if (stream) {
      body['stream'] = true;
      return _consumeMimoAsrStream(
        endpoint: endpoint,
        model: model,
        family: family,
        body: body,
        timeout: timeout,
        onTextDelta: onTextDelta,
      );
    }
    final response = await AiOperationHttp.sendJsonForFamily(
      transport: _transport,
      endpoint: endpoint,
      model: model,
      family: family,
      body: body,
      timeout: timeout,
      acceptJson: true,
    );
    final payload = AiOperationHttp.decodeSuccessfulJsonMap(
      statusCode: response.statusCode,
      body: response.body,
      contextHint: 'mimo/asr',
    );
    final choices = payload['choices'];
    final first = choices is List && choices.isNotEmpty ? choices.first : null;
    final message = first is Map ? first['message'] : null;
    final text = message is Map
        ? optionalStringFromValue(message['content']) ?? ''
        : '';
    if (text.isEmpty) {
      throw const FormatException('MiMo ASR returned no transcription text.');
    }
    return AiAudioIoResult(
      text: text,
      rawResponse: response.body,
      payload: payload,
    );
  }

  Future<AiAudioIoResult> _consumeMimoAsrStream({
    required AiResolvedEndpoint endpoint,
    required AiModelConfig model,
    required AiApiFamily family,
    required Map<String, Object?> body,
    required Duration timeout,
    FutureOr<void> Function(String delta)? onTextDelta,
  }) {
    return _transport.consumeJsonStream(
      uri: AiOperationHttp.uriWithExtraQuery(endpoint.url, model, family),
      method: endpoint.method,
      headers: AiOperationHttp.buildHeaders(
        model: model,
        endpointHeaders: endpoint.headers,
        family: family,
        acceptJson: true,
      ),
      body: body,
      timeout: timeout,
      maxResponseBytes: _mimoMaxSseResponseBytes,
      consume: (_, stream) async {
        final text = StringBuffer();
        final rawResponse = StringBuffer();
        var lastPayload = const <String, Object?>{};
        await _forEachMimoSseData(stream, (data) async {
          if (data == '[DONE]') return;
          if (rawResponse.isNotEmpty) rawResponse.writeln();
          rawResponse.write(data);
          final payload = _mimoSsePayload(data, context: 'MiMo ASR');
          _throwIfMimoStreamFailed(payload, context: 'MiMo ASR');
          lastPayload = payload;
          final choice = _firstMimoChoice(payload);
          final delta = choice?['delta'];
          final message = choice?['message'];
          final candidate = delta is Map
              ? optionalStringFromValue(delta['content'])
              : message is Map
              ? optionalStringFromValue(message['content'])
              : null;
          if (candidate == null) return;
          text.write(candidate);
          await onTextDelta?.call(candidate);
        });
        final transcript = text.toString();
        if (transcript.isEmpty) {
          throw const FormatException(
            'MiMo ASR stream returned no transcription text.',
          );
        }
        return AiAudioIoResult(
          text: transcript,
          rawResponse: rawResponse.toString(),
          payload: lastPayload,
        );
      },
    );
  }

  Future<AiMimoSpeechStreamResult> synthesizeMimoSpeechStream({
    required AiModelConfig model,
    required String text,
    String ttsModelId = 'mimo-v2.5-tts',
    String stylePrompt = '',
    String voice = 'mimo_default',
    bool optimizeTextPreview = false,
    String? voiceSamplePath,
    Duration timeout = const Duration(seconds: 120),
    FutureOr<void> Function(Uint8List chunk)? onAudioChunk,
  }) async {
    if (model.protocolType != AiProtocolType.mimo) {
      throw ArgumentError.value(
        model.protocolType.storageValue,
        'model',
        'MiMo speech streaming requires a MiMo provider configuration.',
      );
    }
    final normalizedModelId = lowercaseStringFromValue(ttsModelId);
    if (!_mimoTtsModelIds.contains(normalizedModelId)) {
      throw ArgumentError.value(
        ttsModelId,
        'ttsModelId',
        'Unsupported MiMo V2.5 TTS model.',
      );
    }
    final targetText = text.trim();
    final style = stylePrompt.trim();
    final voiceDesign = normalizedModelId.endsWith('-voicedesign');
    final voiceClone = normalizedModelId.endsWith('-voiceclone');
    if (targetText.isEmpty && !(voiceDesign && optimizeTextPreview)) {
      throw ArgumentError.value(
        text,
        'text',
        'MiMo TTS requires target text in an assistant message.',
      );
    }
    if (voiceDesign && style.isEmpty) {
      throw ArgumentError.value(
        stylePrompt,
        'stylePrompt',
        'MiMo Voice Design requires a user voice description.',
      );
    }

    final audio = <String, Object?>{
      'format': 'pcm16',
      if (!voiceDesign && !voiceClone)
        'voice': nullIfBlank(voice) ?? 'mimo_default',
      if (voiceDesign && optimizeTextPreview) 'optimize_text_preview': true,
      if (voiceClone)
        'voice': await _mimoVoiceSampleDataUrl(
          voiceSamplePath,
          timeout: timeout,
        ),
    };
    final messages = <Map<String, Object?>>[
      if (style.isNotEmpty) <String, Object?>{'role': 'user', 'content': style},
      if (targetText.isNotEmpty)
        <String, Object?>{'role': 'assistant', 'content': targetText},
    ];
    final endpoint = _router.resolveProviderPath(
      model,
      AiApiFamily.audioSpeech,
      path: 'v1/chat/completions',
    );
    final body = <String, Object?>{
      'model': normalizedModelId,
      'messages': messages,
      'audio': audio,
      'stream': true,
    };
    return _transport.consumeJsonStream(
      uri: AiOperationHttp.uriWithExtraQuery(
        endpoint.url,
        model,
        AiApiFamily.audioSpeech,
      ),
      method: endpoint.method,
      headers: AiOperationHttp.buildHeaders(
        model: model,
        endpointHeaders: endpoint.headers,
        family: AiApiFamily.audioSpeech,
        acceptJson: true,
      ),
      body: body,
      timeout: timeout,
      maxResponseBytes: _mimoMaxSseResponseBytes,
      consume: (_, stream) async {
        final pcm = BytesBuilder(copy: false);
        var chunkCount = 0;
        String? finalTextPreview;
        await _forEachMimoSseData(stream, (data) async {
          if (data == '[DONE]') return;
          final payload = _mimoSsePayload(data, context: 'MiMo TTS');
          _throwIfMimoStreamFailed(payload, context: 'MiMo TTS');
          final choice = _firstMimoChoice(payload);
          final delta = choice?['delta'];
          final message = choice?['message'];
          final content = delta is Map
              ? delta
              : message is Map
              ? message
              : const <Object?, Object?>{};
          finalTextPreview ??= optionalStringFromValue(
            content['final_text_preview'],
          );
          final rawAudio = content['audio'];
          if (rawAudio is! Map) return;
          final encoded = optionalStringFromValue(rawAudio['data']);
          if (encoded == null) return;
          final Uint8List chunk;
          try {
            chunk = base64Decode(encoded);
          } on FormatException {
            throw const FormatException(
              'MiMo TTS stream returned invalid Base64 audio.',
            );
          }
          if (chunk.isEmpty) return;
          if (chunk.length.isOdd) {
            throw const FormatException(
              'MiMo TTS stream returned malformed PCM16 audio.',
            );
          }
          if (pcm.length + chunk.length > _mimoMaxPcmResponseBytes) {
            throw const FormatException(
              'MiMo TTS stream exceeded the bounded PCM audio limit.',
            );
          }
          pcm.add(chunk);
          chunkCount += 1;
          await onAudioChunk?.call(chunk);
        });
        final bytes = pcm.takeBytes();
        if (bytes.isEmpty) {
          throw const FormatException('MiMo TTS stream returned no audio.');
        }
        return AiMimoSpeechStreamResult(
          pcm16Bytes: bytes,
          chunkCount: chunkCount,
          finalTextPreview: finalTextPreview,
        );
      },
    );
  }

  Future<String> _mimoVoiceSampleDataUrl(
    String? rawPath, {
    required Duration timeout,
  }) async {
    final path = nullIfBlank(rawPath);
    if (path == null) {
      throw ArgumentError.value(
        rawPath,
        'voiceSamplePath',
        'MiMo Voice Clone requires a sample path.',
      );
    }
    final extension = File(path).uri.pathSegments.last.toLowerCase();
    final mimeType = extension.endsWith('.mp3')
        ? 'audio/mpeg'
        : extension.endsWith('.wav')
        ? 'audio/wav'
        : null;
    if (mimeType == null) {
      throw ArgumentError.value(
        rawPath,
        'voiceSamplePath',
        'MiMo Voice Clone only supports MP3 and WAV samples.',
      );
    }
    final bytes = await readBoundedFileBytes(
      File(path),
      maxBytes: _mimoMaxVoiceSampleRawBytes,
      idleTimeout: timeout,
      totalTimeout: timeout,
    );
    if (bytes.isEmpty) {
      throw ArgumentError.value(
        rawPath,
        'voiceSamplePath',
        'MiMo Voice Clone sample is empty.',
      );
    }
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  }

  static Future<void> _forEachMimoSseData(
    Stream<List<int>> stream,
    FutureOr<void> Function(String data) onData,
  ) async {
    final data = StringBuffer();
    Future<void> flush() async {
      if (data.isEmpty) return;
      final value = data.toString();
      data.clear();
      await onData(value);
    }

    await for (final line
        in stream
            .transform(const Utf8Decoder(allowMalformed: true))
            .transform(const LineSplitter())) {
      if (line.isEmpty) {
        await flush();
        continue;
      }
      if (!line.startsWith('data:')) continue;
      if (data.isNotEmpty) data.writeln();
      data.write(line.substring(5).trimLeft());
    }
    await flush();
  }

  static Map<String, Object?> _mimoSsePayload(
    String data, {
    required String context,
  }) {
    final decoded = AiOperationHttp.decodeJsonResponse(
      data,
      contextHint: context,
    );
    if (decoded is! Map) {
      throw FormatException('$context stream returned a non-object event.');
    }
    return stringKeyedMapFromValue(decoded);
  }

  static Map<String, Object?>? _firstMimoChoice(Map<String, Object?> payload) {
    final choices = payload['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      return null;
    }
    return stringKeyedMapFromValue(choices.first);
  }

  static void _throwIfMimoStreamFailed(
    Map<String, Object?> payload, {
    required String context,
  }) {
    final error = payload['error'];
    if (error == null) return;
    final message = error is Map
        ? optionalStringFromValue(error['message']) ?? '$error'
        : '$error';
    throw FormatException('$context failed: $message');
  }

  Future<AiAudioIoResult> translate({
    required AiModelConfig model,
    required String filePath,
    Duration timeout = const Duration(seconds: 120),
    String? prompt,
    String? responseFormat,
    double? temperature,
  }) {
    return _sendAudioRequest(
      model: model,
      family: AiApiFamily.audioTranslation,
      filePath: filePath,
      timeout: timeout,
      prompt: prompt,
      responseFormat: responseFormat,
      temperature: temperature,
    );
  }

  Future<AiAudioIoResult> _sendAudioRequest({
    required AiModelConfig model,
    required AiApiFamily family,
    required String filePath,
    required Duration timeout,
    String? language,
    String? prompt,
    String? responseFormat,
    double? temperature,
    Object? timestampGranularities,
  }) async {
    final languageValue = nullIfBlank(language);
    final promptValue = nullIfBlank(prompt);
    final responseFormatValue = nullIfBlank(responseFormat);
    final endpoint = _router.resolve(
      model,
      family,
      method: model.requestMethod,
      transport: 'multipart',
    );
    final body = AiOperationHttp.mergeBodyExtras(
      model,
      family,
      <String, Object?>{
        'model': model.resolveOperationModelId(family),
        'file': AiMultipartUploadFile(filePath: filePath),
        if (languageValue != null) 'language': languageValue,
        if (promptValue != null) 'prompt': promptValue,
        if (responseFormatValue != null) 'response_format': responseFormatValue,
        if (temperature != null && temperature.isFinite)
          'temperature': temperature,
        if (timestampGranularities != null)
          'timestamp_granularities': timestampGranularities,
      },
    );
    final response = await _transport.sendMultipart(
      uri: AiOperationHttp.uriWithExtraQuery(endpoint.url, model, family),
      method: endpoint.method,
      headers: AiOperationHttp.buildHeaders(
        model: model,
        endpointHeaders: endpoint.headers,
        family: family,
        includeJsonContentType: false,
        acceptJson: true,
      ),
      body: body,
      timeout: timeout,
    );
    AiOperationHttp.throwIfFailed(
      statusCode: response.statusCode,
      body: response.body,
      contextHint: family.storageValue,
    );
    final decoded = AiOperationHttp.decodeJsonResponse(
      response.body,
      contextHint: family.storageValue,
    );
    final payload = AiOperationHttp.jsonMapOrEmpty(decoded);
    final text =
        optionalStringFromValue(payload['text']) ??
        optionalStringFromValue(payload['output_text']) ??
        '';
    return AiAudioIoResult(
      text: text,
      rawResponse: response.body,
      payload: payload,
    );
  }

  void dispose() {
    if (_ownsTransport) {
      _transport.dispose();
    }
  }
}
