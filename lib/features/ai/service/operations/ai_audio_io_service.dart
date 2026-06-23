import 'dart:async';

import '../../model/ai_api_family.dart';
import '../../model/ai_model_config.dart';
import '../runtime/ai_endpoint_router.dart';
import '../runtime/ai_transport_client.dart';
import 'ai_operation_http.dart';

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
      _transport = transport ?? AiTransportClient();

  final AiEndpointRouter _router;
  final AiTransportClient _transport;

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
    final body = AiOperationHttp.mergeBodyExtras(
      model,
      family,
      <String, Object?>{
        'model': model.resolveOperationModelId(family),
        'input': input,
        if (voice?.trim().isNotEmpty == true)
          'voice': voice!.trim()
        else if (model.operationRouting.defaultVoice?.trim().isNotEmpty == true)
          'voice': model.operationRouting.defaultVoice!.trim(),
        if (responseFormat?.trim().isNotEmpty == true)
          'response_format': responseFormat!.trim(),
        if (speed?.trim().isNotEmpty == true) 'speed': speed!.trim(),
        if (instructions != null) 'instructions': instructions,
      },
    );
    final response = await _transport.sendJson(
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
    );
    AiOperationHttp.throwIfFailed(
      statusCode: response.statusCode,
      body: response.body,
      contextHint: 'audio/speech',
    );
    final contentType = (response.headers['content-type'] ?? '').trim();
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
    final endpoint = _router.resolve(
      model,
      family,
      method: model.requestMethod,
      transport: 'multipart',
    );
    final body =
        AiOperationHttp.mergeBodyExtras(model, family, <String, Object?>{
          'model': model.resolveOperationModelId(family),
          'file': AiMultipartUploadFile(filePath: filePath),
          if (language?.trim().isNotEmpty == true) 'language': language!.trim(),
          if (prompt?.trim().isNotEmpty == true) 'prompt': prompt!.trim(),
          if (responseFormat?.trim().isNotEmpty == true)
            'response_format': responseFormat!.trim(),
          if (temperature != null && temperature.isFinite)
            'temperature': temperature,
          if (timestampGranularities != null)
            'timestamp_granularities': timestampGranularities,
        });
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
    final text = '${payload['text'] ?? payload['output_text'] ?? ''}'.trim();
    return AiAudioIoResult(
      text: text,
      rawResponse: response.body,
      payload: payload,
    );
  }

  void dispose() {
    _transport.dispose();
  }
}
