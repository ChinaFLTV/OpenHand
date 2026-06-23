import 'dart:async';

import '../../model/ai_api_family.dart';
import '../../model/ai_model_config.dart';
import '../runtime/ai_endpoint_router.dart';
import '../runtime/ai_transport_client.dart';
import 'ai_operation_http.dart';

class AiEmbeddingResult {
  const AiEmbeddingResult({
    required this.vectors,
    required this.rawResponse,
    this.payload = const <String, Object?>{},
  });

  final List<List<double>> vectors;
  final String rawResponse;
  final Map<String, Object?> payload;
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
    int? dimensions,
    String? encodingFormat,
    String? user,
  }) async {
    return createEmbedding(
      model: model,
      input: input,
      timeout: timeout,
      dimensions: dimensions,
      encodingFormat: encodingFormat,
      user: user,
    );
  }

  Future<AiEmbeddingResult> createEmbedding({
    required AiModelConfig model,
    required Object input,
    Duration timeout = const Duration(seconds: 60),
    int? dimensions,
    String? encodingFormat,
    String? user,
  }) async {
    final endpoint = _router.resolve(
      model,
      AiApiFamily.embeddings,
      method: model.requestMethod,
    );
    const family = AiApiFamily.embeddings;
    final body =
        AiOperationHttp.mergeBodyExtras(model, family, <String, Object?>{
          'model': model.resolveOperationModelId(family),
          'input': input,
          if (dimensions != null && dimensions > 0) 'dimensions': dimensions,
          if (encodingFormat?.trim().isNotEmpty == true)
            'encoding_format': encodingFormat!.trim(),
          if (user?.trim().isNotEmpty == true) 'user': user!.trim(),
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
      contextHint: 'embeddings',
    );
    final decoded = AiOperationHttp.decodeJsonResponse(
      response.body,
      contextHint: 'embeddings',
    );
    final payload = AiOperationHttp.jsonMapOrEmpty(decoded);
    return AiEmbeddingResult(
      vectors: _parseVectors(payload),
      rawResponse: response.body,
      payload: payload,
    );
  }

  Future<AiEmbeddingResult> createEngineEmbedding({
    required AiModelConfig model,
    required Object content,
    Duration timeout = const Duration(seconds: 60),
    String taskType = '',
    String title = '',
  }) async {
    const family = AiApiFamily.embeddings;
    final endpoint = _router.resolve(
      model,
      family,
      fallbackPath: 'v1beta/models/{model_id}:embedContent',
      method: model.requestMethod,
    );
    final contentPayload = _geminiContentPayload(content);
    final body =
        AiOperationHttp.mergeBodyExtras(model, family, <String, Object?>{
          'model': 'models/${model.resolveOperationModelId(family)}',
          'content': contentPayload,
          if (taskType.trim().isNotEmpty) 'taskType': taskType.trim(),
          if (title.trim().isNotEmpty) 'title': title.trim(),
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
      contextHint: 'embeddings/gemini',
    );
    final decoded = AiOperationHttp.decodeJsonResponse(
      response.body,
      contextHint: 'embeddings/gemini',
    );
    final payload = AiOperationHttp.jsonMapOrEmpty(decoded);
    return AiEmbeddingResult(
      vectors: _parseVectors(payload),
      rawResponse: response.body,
      payload: payload,
    );
  }

  Map<String, Object?> _geminiContentPayload(Object content) {
    if (content is Map<String, Object?>) return content;
    if (content is Map) return Map<String, Object?>.from(content);
    if (content is List) {
      return <String, Object?>{'parts': content};
    }
    return <String, Object?>{
      'parts': <Map<String, Object?>>[
        <String, Object?>{'text': '$content'},
      ],
    };
  }

  List<List<double>> _parseVectors(Map<String, Object?> payload) {
    final vectors = <List<double>>[];
    void collect(Object? value) {
      if (value == null) return;
      if (value is List && value.every((item) => item is num)) {
        vectors.add(
          value
              .whereType<num>()
              .map((item) => item.toDouble())
              .toList(growable: false),
        );
        return;
      }
      if (value is List) {
        for (final item in value) {
          collect(item);
        }
        return;
      }
      if (value is! Map) return;
      final map = Map<String, Object?>.from(value);
      for (final key in const <String>['embedding', 'values']) {
        final candidate = map[key];
        if (candidate is List) {
          collect(candidate);
        }
      }
      for (final key in const <String>['data', 'embeddings', 'embedding']) {
        final nested = map[key];
        if (nested != null && !identical(nested, value)) {
          collect(nested);
        }
      }
    }

    collect(payload);
    return vectors;
  }

  void dispose() {
    _transport.dispose();
  }
}
