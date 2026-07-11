import 'dart:async';

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

class AiAudioIoService {
  AiAudioIoService({AiEndpointRouter? router, AiTransportClient? transport})
    : _router = router ?? const AiEndpointRouter(),
      _transport = transport ?? AiTransportClient(),
      _ownsTransport = transport == null;

  final AiEndpointRouter _router;
  final AiTransportClient _transport;
  final bool _ownsTransport;

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
  }) {
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
