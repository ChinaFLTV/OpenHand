import 'dart:async';

import '../../../../shared/util/input_value_parsing.dart';
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
    String? maskFilePath,
    Duration timeout = const Duration(seconds: 120),
    int? count,
    String? size,
    String? responseFormat,
    String? quality,
    String? user,
  }) async {
    const family = AiApiFamily.imageEdit;
    final maskPath = nullIfBlank(maskFilePath);
    final sizeValue = nullIfBlank(size);
    final responseFormatValue = nullIfBlank(responseFormat);
    final qualityValue = nullIfBlank(quality);
    final userValue = nullIfBlank(user);
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
        'prompt': prompt,
        'image': AiMultipartUploadFile(filePath: imageFilePath),
        if (maskPath != null) 'mask': AiMultipartUploadFile(filePath: maskPath),
        if (count != null && count > 0) 'n': count,
        if (sizeValue != null) 'size': sizeValue,
        if (responseFormatValue != null) 'response_format': responseFormatValue,
        if (qualityValue != null) 'quality': qualityValue,
        if (userValue != null) 'user': userValue,
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
