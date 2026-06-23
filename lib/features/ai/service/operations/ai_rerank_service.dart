import 'dart:async';

import '../../model/ai_api_family.dart';
import '../../model/ai_model_config.dart';
import '../runtime/ai_endpoint_router.dart';
import '../runtime/ai_transport_client.dart';
import 'ai_operation_http.dart';

class AiRerankItem {
  const AiRerankItem({
    required this.index,
    required this.score,
    this.document,
    this.payload = const <String, Object?>{},
  });

  final int index;
  final double score;
  final Object? document;
  final Map<String, Object?> payload;
}

class AiRerankResult {
  const AiRerankResult({
    required this.items,
    required this.rawResponse,
    this.payload = const <String, Object?>{},
  });

  final List<AiRerankItem> items;
  final String rawResponse;
  final Map<String, Object?> payload;
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
    required List<Object> documents,
    Duration timeout = const Duration(seconds: 60),
    int? topN,
    bool? returnDocuments,
    int? maxChunksPerDoc,
  }) async {
    const family = AiApiFamily.rerank;
    final endpoint = _router.resolve(
      model,
      family,
      method: model.requestMethod,
    );
    final body =
        AiOperationHttp.mergeBodyExtras(model, family, <String, Object?>{
          'model': model.resolveOperationModelId(family),
          'query': query,
          'documents': documents,
          if (topN != null && topN > 0) 'top_n': topN,
          if (returnDocuments != null) 'return_documents': returnDocuments,
          if (maxChunksPerDoc != null && maxChunksPerDoc > 0)
            'max_chunks_per_doc': maxChunksPerDoc,
        });
    final response = await _transport.sendJson(
      uri: AiOperationHttp.uriWithExtraQuery(endpoint.url, model, family),
      method: endpoint.method,
      headers: AiOperationHttp.buildHeaders(
        model: model,
        endpointHeaders: endpoint.headers,
        family: family,
      ),
      body: body,
      timeout: timeout,
    );
    AiOperationHttp.throwIfFailed(
      statusCode: response.statusCode,
      body: response.body,
      contextHint: 'rerank',
    );
    final decoded = AiOperationHttp.decodeJsonResponse(
      response.body,
      contextHint: 'rerank',
    );
    final payload = AiOperationHttp.jsonMapOrEmpty(decoded);
    final rawResults = payload['results'] ?? payload['data'];
    final items = <AiRerankItem>[];
    if (rawResults is List) {
      for (final item in rawResults) {
        if (item is Map) {
          final itemPayload = Map<String, Object?>.from(item);
          final index =
              (itemPayload['index'] as num?)?.toInt() ??
              (itemPayload['document_index'] as num?)?.toInt();
          final score =
              (itemPayload['relevance_score'] as num?)?.toDouble() ??
              (itemPayload['score'] as num?)?.toDouble();
          if (index != null && score != null) {
            items.add(
              AiRerankItem(
                index: index,
                score: score,
                document: itemPayload['document'],
                payload: itemPayload,
              ),
            );
          }
        }
      }
    }
    return AiRerankResult(
      items: items,
      rawResponse: response.body,
      payload: payload,
    );
  }

  void dispose() {
    _transport.dispose();
  }
}
