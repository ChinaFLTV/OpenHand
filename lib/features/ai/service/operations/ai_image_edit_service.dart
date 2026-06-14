import 'dart:async';

import '../../model/ai_api_family.dart';
import '../../model/ai_model_config.dart';
import '../runtime/ai_endpoint_router.dart';
import '../runtime/ai_transport_client.dart';
import 'ai_operation_http.dart';

class AiImageEditResult {
  const AiImageEditResult({required this.rawResponse, required this.payload});

  final String rawResponse;
  final Map<String, Object?> payload;
}

class AiImageEditService {
  AiImageEditService({AiEndpointRouter? router, AiTransportClient? transport})
    : _router = router ?? const AiEndpointRouter(),
      _transport = transport ?? AiTransportClient();

  final AiEndpointRouter _router;
  final AiTransportClient _transport;

  Future<AiImageEditResult> editImage({
    required AiModelConfig model,
    required String prompt,
    required String imageFilePath,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final endpoint = _router.resolve(
      model,
      AiApiFamily.imageEdit,
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
        'model': model.resolveOperationModelId(AiApiFamily.imageEdit),
        'prompt': prompt,
        'image': AiMultipartUploadFile(filePath: imageFilePath),
      },
      timeout: timeout,
    );
    AiOperationHttp.throwIfFailed(
      statusCode: response.statusCode,
      body: response.body,
      contextHint: 'images/edits',
    );
    final decoded = AiOperationHttp.decodeJsonResponse(
      response.body,
      contextHint: 'images/edits',
    );
    return AiImageEditResult(
      rawResponse: response.body,
      payload: AiOperationHttp.jsonMapOrEmpty(decoded),
    );
  }

  void dispose() {
    _transport.dispose();
  }
}
