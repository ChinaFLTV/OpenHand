import 'dart:async';
import 'dart:convert';

import '../../model/ai_api_family.dart';
import '../../model/ai_model_config.dart';
import '../chat/ai_transport_diagnostic_messages.dart';
import '../runtime/ai_endpoint_router.dart';
import '../runtime/ai_transport_client.dart';

class AiRerankItem {
  const AiRerankItem({required this.index, required this.score});

  final int index;
  final double score;
}

class AiRerankResult {
  const AiRerankResult({required this.items, required this.rawResponse});

  final List<AiRerankItem> items;
  final String rawResponse;
}

class AiRerankService {
  AiRerankService({AiEndpointRouter? router, AiTransportClient? transport})
    : _router = router ?? const AiEndpointRouter(),
      _transport = transport ?? AiTransportClient();

  final AiEndpointRouter _router;
  final AiTransportClient _transport;

  Future<AiRerankResult> rerank({
    required AiModelConfig model,
    required String query,
    required List<String> documents,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final endpoint = _router.resolve(
      model,
      AiApiFamily.rerank,
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
        'model': model.resolveOperationModelId(AiApiFamily.rerank),
        'query': query,
        'documents': documents,
      },
      timeout: timeout,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        AiTransportDiagnosticMessages.httpStatus(
          response.statusCode,
          serverMessage: response.body,
          contextHint: 'rerank',
        ),
      );
    }
    final decoded = jsonDecode(response.body);
    final rawResults = decoded is Map<String, Object?> ? decoded['results'] : null;
    final items = <AiRerankItem>[];
    if (rawResults is List) {
      for (final item in rawResults) {
        if (item is Map) {
          final index = (item['index'] as num?)?.toInt();
          final score = (item['relevance_score'] as num?)?.toDouble() ??
              (item['score'] as num?)?.toDouble();
          if (index != null && score != null) {
            items.add(AiRerankItem(index: index, score: score));
          }
        }
      }
    }
    return AiRerankResult(items: items, rawResponse: response.body);
  }

  void dispose() {
    _transport.dispose();
  }
}
