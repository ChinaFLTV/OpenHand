import 'dart:async';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../../app/support/silent_log.dart';
import '../../../shared/util/async_concurrency.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../model/knowledge_base_settings.dart';
import 'knowledge_indexing_control.dart';
import 'knowledge_vector_store.dart';
import 'qdrant_http_client.dart';

const Uuid _qdrantPointUuid = Uuid();
const int _qdrantVectorMaxResponseBytes = 32 * kBytesPerMiB;
const int _qdrantHealthMaxResponseBytes = 64 * kBytesPerKiB;
const Duration _qdrantHealthMaxTimeout = Duration(seconds: 2);

class QdrantKnowledgeVectorStore implements KnowledgeVectorStore {
  QdrantKnowledgeVectorStore({required this.settings});

  final KnowledgeBaseSettings settings;

  Future<bool> isAvailable({Future<void>? cancelSignal}) async {
    final configuredTimeout = Duration(seconds: settings.requestTimeoutSeconds);
    final totalTimeout = configuredTimeout < _qdrantHealthMaxTimeout
        ? configuredTimeout
        : _qdrantHealthMaxTimeout;
    final deadline = MonotonicDeadline(
      totalTimeout,
      timeoutMessage: 'Qdrant 健康检查超时。',
    );

    bool continueAfterTransientFailure(
      String action,
      Object error,
      StackTrace stack,
    ) {
      final shouldRetry = settings.retryCount > 0;
      silentLog(
        'qdrant_vector_store',
        shouldRetry ? '$action，继续按配置重试向量检索' : '$action，降级为本地检索',
        error,
        stack,
      );
      return shouldRetry;
    }

    try {
      final readyTimeout = deadline.remaining();
      final ready = await sendQdrantJsonRequest(
        method: 'GET',
        uri: _uri('/readyz'),
        connectionTimeout: readyTimeout,
        openTimeout: readyTimeout,
        responseTimeout: readyTimeout,
        responseIdleTimeout: readyTimeout,
        maxResponseBytes: _qdrantHealthMaxResponseBytes,
        toleratedFailureStatuses: const <int>{HttpStatus.notFound},
        cancelSignal: cancelSignal,
      );
      if (ready.statusCode != HttpStatus.ok &&
          ready.statusCode != HttpStatus.notFound) {
        throw FormatException('Qdrant 就绪检查返回异常状态：${ready.statusCode}。');
      }

      final rootTimeout = deadline.remaining();
      final root = await sendQdrantJsonRequest(
        method: 'GET',
        uri: _uri('/'),
        connectionTimeout: rootTimeout,
        openTimeout: rootTimeout,
        responseTimeout: rootTimeout,
        responseIdleTimeout: rootTimeout,
        maxResponseBytes: _qdrantHealthMaxResponseBytes,
        cancelSignal: cancelSignal,
      );
      final decoded = optionalStringKeyedMapFromJsonText(root.body);
      final title = '${decoded?['title'] ?? ''}'.toLowerCase();
      if (!title.contains('qdrant')) {
        throw const FormatException('Qdrant 健康检查响应无效。');
      }
      return true;
    } on QdrantHttpException catch (error, stack) {
      if (!error.isRetryable) rethrow;
      return continueAfterTransientFailure('健康检查失败', error, stack);
    } on TimeoutException catch (error, stack) {
      silentLog('qdrant_vector_store', '健康检查超时，继续尝试向量检索', error, stack);
      return true;
    } on SocketException catch (error, stack) {
      return continueAfterTransientFailure('健康检查连接失败', error, stack);
    } finally {
      deadline.stop();
    }
  }

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
      retrySafe: true,
    );
    if (existing.statusCode == 200) {
      _validateCollectionConfig(existing, collectionName, dimensions, distance);
      return;
    }
    try {
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
    } catch (error, stack) {
      if (!_isAmbiguousWriteFailure(error)) {
        Error.throwWithStackTrace(error, stack);
      }
      try {
        final verified = await _send(
          method: 'GET',
          uri: _uri('/collections/$collectionName'),
          tolerateNotFound: true,
          cancelSignal: cancelSignal,
          retrySafe: true,
        );
        if (verified.statusCode == HttpStatus.ok) {
          _validateCollectionConfig(
            verified,
            collectionName,
            dimensions,
            distance,
          );
          return;
        }
      } catch (verificationError, verificationStack) {
        if (!_isAmbiguousWriteFailure(verificationError)) {
          Error.throwWithStackTrace(verificationError, verificationStack);
        }
      }
      Error.throwWithStackTrace(error, stack);
    }
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
      retrySafe: true,
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
    Future<void>? cancelSignal,
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
      cancelSignal: cancelSignal,
      retrySafe: true,
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
      retrySafe: true,
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
    Future<void>? cancelSignal,
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
      cancelSignal: cancelSignal,
      retrySafe: true,
    );
  }

  Future<_QdrantResponse> _send({
    required String method,
    required Uri uri,
    Map<String, Object?>? body,
    bool tolerateNotFound = false,
    Future<void>? cancelSignal,
    bool retrySafe = false,
  }) async {
    final requestTimeout = Duration(seconds: settings.requestTimeoutSeconds);
    try {
      final response = await sendQdrantJsonRequest(
        method: method,
        uri: uri,
        connectionTimeout: const Duration(seconds: 8),
        openTimeout: const Duration(seconds: 12),
        responseTimeout: requestTimeout,
        responseIdleTimeout: requestTimeout,
        maxResponseBytes: _qdrantVectorMaxResponseBytes,
        body: body,
        toleratedFailureStatuses: tolerateNotFound
            ? const <int>{HttpStatus.notFound}
            : const <int>{},
        cancelSignal: cancelSignal,
        retryCount: retrySafe ? settings.retryCount : 0,
        retryBackoff: Duration(milliseconds: settings.retryBackoffMs),
      );
      return _QdrantResponse(response.statusCode, response.body);
    } on QdrantRequestCancelledException {
      throw const KnowledgeIndexingCancelledException();
    }
  }

  void _validateCollectionConfig(
    _QdrantResponse response,
    String collectionName,
    int dimensions,
    String distance,
  ) {
    final decoded = _decode(response.body);
    final result = stringKeyedMapFromValue(decoded['result']);
    final config = stringKeyedMapFromValue(result['config']);
    final params = stringKeyedMapFromValue(config['params']);
    final vectors = stringKeyedMapFromValue(params['vectors']);
    final vectorSize = optionalPositiveIntFromValue(vectors['size']);
    final actualDistance = optionalStringFromValue(
      vectors['distance'],
    )?.toLowerCase();
    if (vectorSize == null || actualDistance == null) {
      throw const FormatException('Qdrant 集合配置响应缺少向量维度或距离。');
    }
    if (vectorSize != dimensions) {
      throw StateError(
        'Qdrant 集合 $collectionName 的向量维度为 $vectorSize，'
        '预期为 $dimensions。修改嵌入维度后请重建索引。',
      );
    }
    final expectedDistance = _qdrantDistance(distance).toLowerCase();
    if (actualDistance != expectedDistance) {
      throw StateError(
        'Qdrant 集合 $collectionName 的距离算法为 $actualDistance，'
        '预期为 $expectedDistance。修改距离算法后请重建索引。',
      );
    }
  }

  bool _isAmbiguousWriteFailure(Object error) {
    if (error is QdrantHttpException) {
      return error.isRetryable ||
          error.statusCode == HttpStatus.badRequest ||
          error.statusCode == HttpStatus.conflict;
    }
    return error is TimeoutException ||
        error is SocketException ||
        error is HttpException;
  }

  Map<String, Object?> _decode(String body) {
    final decoded = optionalStringKeyedMapFromJsonText(body);
    if (decoded != null) return decoded;
    throw const FormatException('Qdrant 未返回有效的 JSON 对象。');
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
    throw const FormatException('Qdrant 点 ID 不能为空。');
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
