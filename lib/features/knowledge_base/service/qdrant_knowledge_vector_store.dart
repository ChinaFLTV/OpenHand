import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../model/knowledge_base_settings.dart';
import 'knowledge_vector_store.dart';

class QdrantKnowledgeVectorStore implements KnowledgeVectorStore {
  QdrantKnowledgeVectorStore({required this.settings});

  final KnowledgeBaseSettings settings;

  Uri _uri(String path) {
    final base = settings.qdrantBaseUri;
    return base.replace(path: path.startsWith('/') ? path : '/$path');
  }

  @override
  Future<void> ensureCollection({
    required String collectionName,
    required int dimensions,
    required String distance,
  }) async {
    final existing = await _send(
      method: 'GET',
      uri: _uri('/collections/$collectionName'),
      tolerateNotFound: true,
    );
    if (existing.statusCode == 200) {
      final decoded = _decode(existing.body);
      final result = decoded['result'];
      if (result is Map) {
        final config = result['config'];
        final params = config is Map ? config['params'] : null;
        final vectors = params is Map ? params['vectors'] : null;
        final size = vectors is Map ? vectors['size'] : null;
        if (size is num && size.toInt() != dimensions) {
          throw StateError(
            'Qdrant collection $collectionName vector size is ${size.toInt()}, expected $dimensions. Rebuild the index after changing embedding dimensions.',
          );
        }
      }
      return;
    }
    await _send(
      method: 'PUT',
      uri: _uri('/collections/$collectionName'),
      body: <String, Object?>{
        'vectors': <String, Object?>{
          'size': dimensions,
          'distance': _qdrantDistance(distance),
        },
        'hnsw_config': <String, Object?>{
          'm': settings.hnswM,
          'ef_construct': settings.hnswEfConstruct,
        },
      },
    );
  }

  @override
  Future<void> upsert({
    required String collectionName,
    required List<KnowledgeVectorPoint> points,
  }) async {
    if (points.isEmpty) return;
    await _send(
      method: 'PUT',
      uri: _uri('/collections/$collectionName/points?wait=true'),
      body: <String, Object?>{
        'points': points
            .map(
              (point) => <String, Object?>{
                'id': point.id,
                'vector': point.vector,
                'payload': point.payload,
              },
            )
            .toList(growable: false),
      },
    );
  }

  @override
  Future<List<KnowledgeVectorSearchHit>> search({
    required String collectionName,
    required List<double> vector,
    required int limit,
    double? scoreThreshold,
    Map<String, Object?>? filter,
  }) async {
    final response = await _send(
      method: 'POST',
      uri: _uri('/collections/$collectionName/points/search'),
      body: <String, Object?>{
        'vector': vector,
        'limit': limit,
        'with_payload': true,
        'params': <String, Object?>{'hnsw_ef': settings.searchEf},
        if (scoreThreshold != null) 'score_threshold': scoreThreshold,
        if (filter != null && filter.isNotEmpty) 'filter': filter,
      },
    );
    final decoded = _decode(response.body);
    final result = decoded['result'];
    if (result is! List) return const <KnowledgeVectorSearchHit>[];
    return result
        .whereType<Map>()
        .map((item) {
          final payload = item['payload'];
          return KnowledgeVectorSearchHit(
            id: '${item['id'] ?? ''}',
            score: (item['score'] as num?)?.toDouble() ?? 0,
            payload: payload is Map
                ? Map<String, Object?>.from(payload)
                : const <String, Object?>{},
          );
        })
        .where((hit) => hit.id.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<void> deleteBySource({
    required String collectionName,
    required String sourceId,
  }) async {
    await _send(
      method: 'POST',
      uri: _uri('/collections/$collectionName/points/delete?wait=true'),
      body: <String, Object?>{
        'filter': <String, Object?>{
          'must': <Object?>[
            <String, Object?>{
              'key': 'source_id',
              'match': <String, Object?>{'value': sourceId},
            },
          ],
        },
      },
    );
  }

  Future<_QdrantResponse> _send({
    required String method,
    required Uri uri,
    Map<String, Object?>? body,
    bool tolerateNotFound = false,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client
          .openUrl(method, uri)
          .timeout(const Duration(seconds: 12));
      request.headers.contentType = ContentType.json;
      if (body != null) {
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(
        Duration(seconds: settings.requestTimeoutSeconds),
      );
      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode == 404 && tolerateNotFound) {
        return _QdrantResponse(response.statusCode, text);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Qdrant ${response.statusCode}: $text', uri: uri);
      }
      return _QdrantResponse(response.statusCode, text);
    } finally {
      client.close(force: true);
    }
  }

  Map<String, Object?> _decode(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map) return Map<String, Object?>.from(decoded);
    return const <String, Object?>{};
  }

  String _qdrantDistance(String value) {
    return switch (value.trim().toLowerCase()) {
      'dot' => 'Dot',
      'euclidean' => 'Euclid',
      _ => 'Cosine',
    };
  }
}

class _QdrantResponse {
  const _QdrantResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;
}
