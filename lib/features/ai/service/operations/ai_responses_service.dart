import 'dart:async';
import 'dart:convert';

import '../../model/ai_api_family.dart';
import '../../model/ai_model_config.dart';
import '../chat/ai_transport_diagnostic_messages.dart';
import '../runtime/ai_endpoint_router.dart';
import '../runtime/ai_transport_client.dart';

class AiResponsesResult {
  const AiResponsesResult({
    required this.text,
    required this.rawResponse,
    this.reasoning,
  });

  final String text;
  final String rawResponse;
  final String? reasoning;
}

class AiResponsesService {
  AiResponsesService({AiEndpointRouter? router, AiTransportClient? transport})
    : _router = router ?? const AiEndpointRouter(),
      _transport = transport ?? AiTransportClient();

  final AiEndpointRouter _router;
  final AiTransportClient _transport;

  Future<AiResponsesResult> createResponse({
    required AiModelConfig model,
    required String input,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final endpoint = _router.resolve(
      model,
      AiApiFamily.responses,
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
        'model': model.resolveOperationModelId(AiApiFamily.responses),
        'input': input,
      },
      timeout: timeout,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        AiTransportDiagnosticMessages.httpStatus(
          response.statusCode,
          serverMessage: response.body,
          contextHint: 'responses',
        ),
      );
    }
    final decoded = jsonDecode(response.body);
    var text = '';
    String? reasoning;
    if (decoded is Map<String, Object?>) {
      final output = decoded['output'];
      if (output is List) {
        final buffer = StringBuffer();
        final reasoningBuffer = StringBuffer();
        for (final item in output) {
          if (item is! Map) continue;
          final content = item['content'];
          if (content is! List) continue;
          for (final part in content) {
            if (part is! Map) continue;
            final type = '${part['type'] ?? ''}'.trim();
            if (type == 'output_text') {
              final partText = '${part['text'] ?? ''}'.trim();
              if (partText.isNotEmpty) {
                if (buffer.isNotEmpty) buffer.writeln();
                buffer.write(partText);
              }
            }
            if (type == 'reasoning') {
              final partText = '${part['summary'] ?? part['text'] ?? ''}'.trim();
              if (partText.isNotEmpty) {
                if (reasoningBuffer.isNotEmpty) reasoningBuffer.writeln();
                reasoningBuffer.write(partText);
              }
            }
          }
        }
        text = buffer.toString().trim();
        final normalizedReasoning = reasoningBuffer.toString().trim();
        reasoning = normalizedReasoning.isEmpty ? null : normalizedReasoning;
      }
    }
    return AiResponsesResult(
      text: text,
      rawResponse: response.body,
      reasoning: reasoning,
    );
  }

  void dispose() {
    _transport.dispose();
  }
}
