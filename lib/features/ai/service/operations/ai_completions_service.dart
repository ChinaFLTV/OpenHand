import 'dart:async';
import 'dart:convert';

import '../../model/ai_api_family.dart';
import '../../model/ai_model_config.dart';
import '../chat/ai_transport_diagnostic_messages.dart';
import '../runtime/ai_endpoint_router.dart';
import '../runtime/ai_transport_client.dart';

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
        'model': model.resolveOperationModelId(AiApiFamily.completions),
        'prompt': prompt,
        if (model.maxTokens != null) 'max_tokens': model.maxTokens,
        if (model.temperature != null) 'temperature': model.temperature,
      },
      timeout: timeout,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        AiTransportDiagnosticMessages.httpStatus(
          response.statusCode,
          serverMessage: response.body,
          contextHint: 'completions',
        ),
      );
    }
    final decoded = jsonDecode(response.body);
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
