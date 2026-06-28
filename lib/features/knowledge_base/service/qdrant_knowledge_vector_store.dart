import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../../shared/util/input_value_parsing.dart';
import '../model/knowledge_base_settings.dart';
import 'knowledge_indexing_control.dart';
import 'knowledge_vector_store.dart';

const Uuid _qdrantPointUuid = Uuid();

class QdrantKnowledgeVectorStore implements KnowledgeVectorStore {
  QdrantKnowledgeVectorStore({required this.settings});

  final KnowledgeBaseSettings settings;

  Uri _uri(String path, {Map<String, String>? queryParameters}) {
    final base = settings.qdrantBaseUri;
    return base.replace(
      path: path.startsWith('/') ? path : '/$path',
      queryParameters: queryParameters?.isEmpty == false
          ? queryParameters
          : null,
    );
  }

  @override
  Future<void> ensureCollection({
    required String collectionName,
    required int dimensions,
    required String distance,
    Future<void>? cancelSignal,
  }) async {
    final existing = await _send(
      method: 'GET',
      uri: _uri('/collections/$collectionName'),
      tolerateNotFound: true,
      cancelSignal: cancelSignal,
    );
    if (existing.statusCode == 200) {
      final decoded = _decode(existing.body);
      final result = decoded['result'];
      if (result is Map) {
        final config = result['config'];
        final params = config is Map ? config['params'] : null;
        final vectors = params is Map ? params['vectors'] : null;
        final size = vectors is Map ? vectors['size'] : null;
        final vectorSize = optionalPositiveIntFromValue(size);
        if (vectorSize != null && vectorSize != dimensions) {
          throw StateError(
            'Qdrant collection $collectionName vector size is $vectorSize, expected $dimensions. Rebuild the index after changing embedding dimensions.',
          );
        }
      }
      return;
    }
    await _send(
      method: 'PUT',
      uri: _uri('/collections/$collectionName'),
      cancelSignal: cancelSignal,
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
    Future<void>? cancelSignal,
  }) async {
    if (points.isEmpty) return;
    await _send(
      method: 'PUT',
      uri: _uri(
        '/collections/$collectionName/points',
        queryParameters: const <String, String>{'wait': 'true'},
      ),
      cancelSignal: cancelSignal,
      body: <String, Object?>{
        'points': points
            .map(
              (point) => <String, Object?>{
                'id': qdrantPointIdForStableId(point.id),
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
    if (vector.isEmpty || vector.any((value) => !value.isFinite)) {
      return const <KnowledgeVectorSearchHit>[];
    }
    final safeScoreThreshold = optionalDoubleFromValue(scoreThreshold);
    final response = await _send(
      method: 'POST',
      uri: _uri('/collections/$collectionName/points/search'),
      body: <String, Object?>{
        'vector': vector,
        'limit': limit,
        'with_payload': true,
        'params': <String, Object?>{'hnsw_ef': settings.searchEf},
        if (safeScoreThreshold != null) 'score_threshold': safeScoreThreshold,
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
            score: doubleFromValue(item['score'], fallback: 0),
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
      uri: _uri(
        '/collections/$collectionName/points/delete',
        queryParameters: const <String, String>{'wait': 'true'},
      ),
      tolerateNotFound: true,
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
    Future<void>? cancelSignal,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    Future<_QdrantResponse> send() async {
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
    }

    final requestFuture = send().whenComplete(() => client.close(force: true));
    if (cancelSignal == null) return requestFuture;
    final cancelled = Object();
    final result = await Future.any<Object?>([
      requestFuture.then<Object?>((value) => value),
      cancelSignal.then<Object?>((_) => cancelled),
    ]);
    if (identical(result, cancelled)) {
      client.close(force: true);
      unawaited(
        requestFuture.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
      throw const KnowledgeIndexingCancelledException();
    }
    return result! as _QdrantResponse;
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

Object qdrantPointIdForStableId(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw const FormatException('Qdrant point id cannot be empty.');
  }
  if (Uuid.isValidUUID(fromString: normalized)) return normalized;
  final unsigned = int.tryParse(normalized);
  if (unsigned != null && unsigned >= 0) return unsigned;
  return _qdrantPointUuid.v5(
    Namespace.url.value,
    'openhand:qdrant-point:$normalized',
  );
}

class _QdrantResponse {
  const _QdrantResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;
}
