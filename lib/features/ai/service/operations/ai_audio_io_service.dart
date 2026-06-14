import 'dart:async';

import '../../model/ai_api_family.dart';
import '../../model/ai_model_config.dart';
import '../runtime/ai_endpoint_router.dart';
import '../runtime/ai_transport_client.dart';
import 'ai_operation_http.dart';

class AiAudioIoResult {
  const AiAudioIoResult({required this.text, required this.rawResponse});

  final String text;
  final String rawResponse;
}

class AiAudioIoService {
  AiAudioIoService({AiEndpointRouter? router, AiTransportClient? transport})
    : _router = router ?? const AiEndpointRouter(),
      _transport = transport ?? AiTransportClient();

  final AiEndpointRouter _router;
  final AiTransportClient _transport;

  Future<AiAudioIoResult> transcribe({
    required AiModelConfig model,
    required String filePath,
    Duration timeout = const Duration(seconds: 120),
  }) {
    return _sendAudioRequest(
      model: model,
      family: AiApiFamily.audioTranscription,
      filePath: filePath,
      timeout: timeout,
    );
  }

  Future<AiAudioIoResult> translate({
    required AiModelConfig model,
    required String filePath,
    Duration timeout = const Duration(seconds: 120),
  }) {
    return _sendAudioRequest(
      model: model,
      family: AiApiFamily.audioTranslation,
      filePath: filePath,
      timeout: timeout,
    );
  }

  Future<AiAudioIoResult> _sendAudioRequest({
    required AiModelConfig model,
    required AiApiFamily family,
    required String filePath,
    required Duration timeout,
  }) async {
    final endpoint = _router.resolve(
      model,
      family,
      method: model.requestMethod,
      transport: 'multipart',
    );
    final response = await _transport.sendMultipart(
      uri: Uri.parse(endpoint.url),
      method: endpoint.method,
      headers: AiOperationHttp.buildHeaders(
        model: model,
        endpointHeaders: endpoint.headers,
        includeJsonContentType: false,
        acceptJson: true,
      ),
      body: <String, Object?>{
        'model': model.resolveOperationModelId(family),
        'file': AiMultipartUploadFile(filePath: filePath),
      },
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
    final text = decoded is Map<String, Object?>
        ? '${decoded['text'] ?? decoded['output_text'] ?? ''}'.trim()
        : '';
    return AiAudioIoResult(text: text, rawResponse: response.body);
  }

  void dispose() {
    _transport.dispose();
  }
}
