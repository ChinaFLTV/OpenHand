import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../../shared/net/http_status_utils.dart';
import '../../../shared/util/async_concurrency.dart';
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
      final result = stringKeyedMapFromValue(decoded['result']);
      if (result.isNotEmpty) {
        final config = stringKeyedMapFromValue(result['config']);
        final params = stringKeyedMapFromValue(config['params']);
        final vectors = stringKeyedMapFromValue(params['vectors']);
        final size = vectors['size'];
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
    bool includeVector = false,
  }) async {
    if (limit <= 0 ||
        vector.isEmpty ||
        vector.any((value) => !value.isFinite)) {
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
        'with_vector': includeVector,
        'params': <String, Object?>{'hnsw_ef': settings.searchEf},
        if (safeScoreThreshold != null) 'score_threshold': safeScoreThreshold,
        if (filter != null && filter.isNotEmpty) 'filter': filter,
      },
    );
    final decoded = _decode(response.body);
    final result = decoded['result'];
    return stringKeyedMapListFromValue(result)
        .map((item) {
          return KnowledgeVectorSearchHit(
            id: '${item['id'] ?? ''}',
            score: doubleFromValue(item['score'], fallback: 0),
            payload: stringKeyedMapFromValue(item['payload']),
            vector: includeVector
                ? _vectorFromValue(item['vector'])
                : const <double>[],
          );
        })
        .where((hit) => hit.id.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<KnowledgeVectorSamplePage> sample({
    required String collectionName,
    required int limit,
    Object? offset,
    Map<String, Object?>? filter,
  }) async {
    if (limit <= 0) {
      return const KnowledgeVectorSamplePage(
        points: <KnowledgeVectorSamplePoint>[],
      );
    }
    final response = await _send(
      method: 'POST',
      uri: _uri('/collections/$collectionName/points/scroll'),
      body: <String, Object?>{
        'limit': limit,
        'with_payload': true,
        'with_vector': true,
        if (offset != null) 'offset': offset,
        if (filter != null && filter.isNotEmpty) 'filter': filter,
      },
    );
    final decoded = _decode(response.body);
    final result = stringKeyedMapFromValue(decoded['result']);
    final points = stringKeyedMapListFromValue(result['points'])
        .map((item) {
          return KnowledgeVectorSamplePoint(
            id: '${item['id'] ?? ''}',
            vector: _vectorFromValue(item['vector']),
            payload: stringKeyedMapFromValue(item['payload']),
          );
        })
        .where((point) => point.id.isNotEmpty && point.vector.isNotEmpty)
        .toList(growable: false);
    return KnowledgeVectorSamplePage(
      points: points,
      nextPageOffset: result['next_page_offset'],
    );
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
      if (isHttpFailureStatus(response.statusCode)) {
        throw HttpException('Qdrant ${response.statusCode}: $text', uri: uri);
      }
      return _QdrantResponse(response.statusCode, text);
    }

    final requestFuture = send().whenComplete(() => client.close(force: true));
    final result = await awaitWithCancelSignal(
      requestFuture,
      cancelSignal: cancelSignal,
    );
    if (result == null) {
      client.close(force: true);
      throw const KnowledgeIndexingCancelledException();
    }
    return result;
  }

  Map<String, Object?> _decode(String body) {
    final decoded = optionalStringKeyedMapFromJsonText(body);
    if (decoded != null) return decoded;
    throw const FormatException('Expected Qdrant JSON object response.');
  }

  String _qdrantDistance(String value) {
    return switch (KnowledgeDistanceMetric.normalize(value)) {
      KnowledgeDistanceMetric.dot => 'Dot',
      KnowledgeDistanceMetric.euclidean => 'Euclid',
      _ => 'Cosine',
    };
  }

  List<double> _vectorFromValue(Object? value) {
    if (value is List) {
      return value
          .map(optionalDoubleFromValue)
          .whereType<double>()
          .where((item) => item.isFinite)
          .toList(growable: false);
    }
    final map = stringKeyedMapFromValue(value);
    for (final item in map.values) {
      final vector = _vectorFromValue(item);
      if (vector.isNotEmpty) return vector;
    }
    return const <double>[];
  }
}

Object qdrantPointIdForStableId(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw const FormatException('Qdrant point id cannot be empty.');
  }
  if (Uuid.isValidUUID(fromString: normalized)) return normalized;
  final unsigned = optionalNonNegativeIntFromValue(normalized);
  if (unsigned != null) return unsigned;
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
