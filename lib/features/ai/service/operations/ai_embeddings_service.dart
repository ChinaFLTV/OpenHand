import 'dart:async';
import 'dart:convert';

import '../../model/ai_api_family.dart';
import '../../model/ai_model_config.dart';
import '../chat/ai_transport_diagnostic_messages.dart';
import '../runtime/ai_endpoint_router.dart';
import '../runtime/ai_transport_client.dart';

class AiEmbeddingResult {
  const AiEmbeddingResult({required this.vectors, required this.rawResponse});

  final List<List<double>> vectors;
  final String rawResponse;
}

class AiEmbeddingsService {
  AiEmbeddingsService({
    AiEndpointRouter? router,
    AiTransportClient? transport,
  }) : _router = router ?? const AiEndpointRouter(),
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
        'model': model.resolveOperationModelId(AiApiFamily.embeddings),
        'input': input,
      },
      timeout: timeout,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        AiTransportDiagnosticMessages.httpStatus(
          response.statusCode,
          serverMessage: response.body,
          contextHint: 'embeddings',
        ),
      );
    }
    final decoded = jsonDecode(response.body);
    final data = decoded is Map<String, Object?> ? decoded['data'] : null;
    final vectors = <List<double>>[];
    if (data is List) {
      for (final item in data) {
        if (item is Map && item['embedding'] is List) {
          vectors.add(
            (item['embedding'] as List)
                .map((value) => (value as num).toDouble())
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
