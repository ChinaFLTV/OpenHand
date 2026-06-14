import 'dart:async';

import '../../model/ai_api_family.dart';
import '../../model/ai_model_config.dart';
import '../runtime/ai_endpoint_router.dart';
import '../runtime/ai_transport_client.dart';
import 'ai_operation_http.dart';

class AiCompletionResult {
  const AiCompletionResult({required this.text, required this.rawResponse});

  final String text;
  final String rawResponse;
}

class AiCompletionsService {
  AiCompletionsService({AiEndpointRouter? router, AiTransportClient? transport})
    : _router = router ?? const AiEndpointRouter(),
      _transport = transport ?? AiTransportClient();

  final AiEndpointRouter _router;
  final AiTransportClient _transport;

  Future<AiCompletionResult> complete({
    required AiModelConfig model,
    required String prompt,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final endpoint = _router.resolve(
      model,
      AiApiFamily.completions,
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
        'model': model.resolveOperationModelId(AiApiFamily.completions),
        'prompt': prompt,
        if (model.maxTokens != null) 'max_tokens': model.maxTokens,
        if (model.temperature != null) 'temperature': model.temperature,
      },
      timeout: timeout,
    );
    AiOperationHttp.throwIfFailed(
      statusCode: response.statusCode,
      body: response.body,
      contextHint: 'completions',
    );
    final decoded = AiOperationHttp.decodeJsonResponse(
      response.body,
      contextHint: 'completions',
    );
    final choices = decoded is Map<String, Object?> ? decoded['choices'] : null;
    String text = '';
    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      text = '${(choices.first as Map)['text'] ?? ''}'.trim();
    }
    return AiCompletionResult(text: text, rawResponse: response.body);
  }

  void dispose() {
    _transport.dispose();
  }
}
