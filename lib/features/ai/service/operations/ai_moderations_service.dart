import 'dart:async';

import '../../model/ai_api_family.dart';
import '../../model/ai_model_config.dart';
import '../runtime/ai_endpoint_router.dart';
import '../runtime/ai_transport_client.dart';
import 'ai_operation_http.dart';

class AiModerationResult {
  const AiModerationResult({required this.rawResponse, required this.payload});

  final String rawResponse;
  final Map<String, Object?> payload;
}

class AiModerationsService {
  AiModerationsService({AiEndpointRouter? router, AiTransportClient? transport})
    : _router = router ?? const AiEndpointRouter(),
      _transport = transport ?? AiTransportClient();

  final AiEndpointRouter _router;
  final AiTransportClient _transport;

  Future<AiModerationResult> moderate({
    required AiModelConfig model,
    required String input,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final endpoint = _router.resolve(
      model,
      AiApiFamily.moderations,
      method: model.requestMethod,
    );
    final response = await _transport.sendJson(
      uri: Uri.parse(endpoint.url),
      method: endpoint.method,
      headers: AiOperationHttp.buildHeaders(
        model: model,
        endpointHeaders: endpoint.headers,
      ),
      body: <String, Object?>{
        'model': model.resolveOperationModelId(AiApiFamily.moderations),
        'input': input,
      },
      timeout: timeout,
    );
    AiOperationHttp.throwIfFailed(
      statusCode: response.statusCode,
      body: response.body,
      contextHint: 'moderations',
    );
    final decoded = AiOperationHttp.decodeJsonResponse(
      response.body,
      contextHint: 'moderations',
    );
    return AiModerationResult(
      rawResponse: response.body,
      payload: AiOperationHttp.jsonMapOrEmpty(decoded),
    );
  }

  void dispose() {
    _transport.dispose();
  }
}
