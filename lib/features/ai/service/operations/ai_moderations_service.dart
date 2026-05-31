import 'dart:async';
import 'dart:convert';

import '../../model/ai_api_family.dart';
import '../../model/ai_model_config.dart';
import '../chat/ai_transport_diagnostic_messages.dart';
import '../runtime/ai_endpoint_router.dart';
import '../runtime/ai_transport_client.dart';

class AiModerationResult {
  const AiModerationResult({required this.rawResponse, required this.payload});

  final String rawResponse;
  final Map<String, Object?> payload;
}

class AiModerationsService {
  AiModerationsService({
    AiEndpointRouter? router,
    AiTransportClient? transport,
  }) : _router = router ?? const AiEndpointRouter(),
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
    final headers = <String, String>{
      'content-type': 'application/json',
      ...model.customHeaders,
      ...endpoint.headers,
    };
    final token = model.token.trim();
    if (token.isNotEmpty && model.authScheme != AiAuthScheme.none) {
      if (model.authScheme == AiAuthScheme.apiKey) {
        headers['x-api-key'] = model.authScheme.apply(token);
      } else {
        headers['authorization'] = model.authScheme.apply(token);
      }
    }
    final response = await _transport.sendJson(
      uri: Uri.parse(endpoint.url),
      method: endpoint.method,
      headers: headers,
      body: <String, Object?>{
        'model': model.resolveOperationModelId(AiApiFamily.moderations),
        'input': input,
      },
      timeout: timeout,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        AiTransportDiagnosticMessages.httpStatus(
          response.statusCode,
          serverMessage: response.body,
          contextHint: 'moderations',
        ),
      );
    }
    final decoded = jsonDecode(response.body);
    return AiModerationResult(
      rawResponse: response.body,
      payload: decoded is Map<String, Object?>
          ? decoded
          : const <String, Object?>{},
    );
  }

  void dispose() {
    _transport.dispose();
  }
}
