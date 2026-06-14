import 'dart:async';

import '../../model/ai_api_family.dart';
import '../../model/ai_model_config.dart';
import '../runtime/ai_endpoint_router.dart';
import '../runtime/ai_transport_client.dart';
import 'ai_operation_http.dart';

class AiEmbeddingResult {
  const AiEmbeddingResult({required this.vectors, required this.rawResponse});

  final List<List<double>> vectors;
  final String rawResponse;
}

class AiEmbeddingsService {
  AiEmbeddingsService({AiEndpointRouter? router, AiTransportClient? transport})
    : _router = router ?? const AiEndpointRouter(),
      _transport = transport ?? AiTransportClient();

  final AiEndpointRouter _router;
  final AiTransportClient _transport;

  Future<AiEmbeddingResult> createEmbeddings({
    required AiModelConfig model,
    required List<String> input,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final endpoint = _router.resolve(
      model,
      AiApiFamily.embeddings,
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
        'model': model.resolveOperationModelId(AiApiFamily.embeddings),
        'input': input,
      },
      timeout: timeout,
    );
    AiOperationHttp.throwIfFailed(
      statusCode: response.statusCode,
      body: response.body,
      contextHint: 'embeddings',
    );
    final decoded = AiOperationHttp.decodeJsonResponse(
      response.body,
      contextHint: 'embeddings',
    );
    final data = decoded is Map<String, Object?> ? decoded['data'] : null;
    final vectors = <List<double>>[];
    if (data is List) {
      for (final item in data) {
        if (item is Map && item['embedding'] is List) {
          vectors.add(
            (item['embedding'] as List)
                .whereType<num>()
                .map((value) => value.toDouble())
                .toList(growable: false),
          );
        }
      }
    }
    return AiEmbeddingResult(vectors: vectors, rawResponse: response.body);
  }

  void dispose() {
    _transport.dispose();
  }
}
