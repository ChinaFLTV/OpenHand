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
      _transport = transport ?? AiTransportClient(),
      _ownsTransport = transport == null;

  final AiEndpointRouter _router;
  final AiTransportClient _transport;
  final bool _ownsTransport;

  Future<AiModerationResult> moderate({
    required AiModelConfig model,
    required Object input,
    Duration timeout = AiOperationHttp.defaultRequestTimeout,
  }) async {
    const family = AiApiFamily.moderations;
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
      },
    );
    final response = await AiOperationHttp.sendJsonForFamily(
      transport: _transport,
      endpoint: endpoint,
      model: model,
      family: family,
      body: body,
      timeout: timeout,
    );
    final payload = AiOperationHttp.decodeSuccessfulJsonMap(
      statusCode: response.statusCode,
      body: response.body,
      contextHint: 'moderations',
    );
    return AiModerationResult(rawResponse: response.body, payload: payload);
  }

  void dispose() {
    if (_ownsTransport) {
      _transport.dispose();
    }
  }
}
