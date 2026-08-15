import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../model/knowledge_base_settings.dart';
import 'qdrant_http_client.dart';

const Duration _qdrantAdminConnectionTimeout = Duration(seconds: 5);
const Duration _qdrantAdminRequestTimeout = Duration(seconds: 15);
const Duration _qdrantAdminResponseIdleTimeout = Duration(seconds: 5);
const int _qdrantAdminMaxResponseBytes = 16 * kBytesPerMiB;

List<Map<String, Object?>> qdrantCollectionsFromResponse(Object? response) {
  final root = stringKeyedMapFromValue(response);
  final result = stringKeyedMapFromValue(root['result']);
  return stringKeyedMapListFromValue(result['collections']);
}

class QdrantAdminOperationLog {
  const QdrantAdminOperationLog({
    required this.action,
    required this.createdAt,
    required this.detail,
  });

  final String action;
  final DateTime createdAt;
  final String detail;
}

class QdrantAdminService {
  final List<QdrantAdminOperationLog> _logs = <QdrantAdminOperationLog>[];

  List<QdrantAdminOperationLog> get logs => List.unmodifiable(_logs);

  void trimLogs(int maxEntries) {
    final limit = KnowledgeBaseSettingRanges.qdrantLogRetainLines.normalize(
      maxEntries,
    );
    final overflow = _logs.length - limit;
    if (overflow > 0) _logs.removeRange(0, overflow);
  }

  Future<List<Map<String, Object?>>> listCollections(
    KnowledgeBaseSettings settings,
  ) async {
    final json = await _request(settings, 'GET', '/collections');
    return qdrantCollectionsFromResponse(json);
  }

  Future<Map<String, Object?>> collectionInfo(
    KnowledgeBaseSettings settings,
    String collection,
  ) {
    return _request(settings, 'GET', '/collections/$collection');
  }

  Future<Map<String, Object?>> scroll(
    KnowledgeBaseSettings settings, {
    required String collection,
    Map<String, Object?>? filter,
    int limit = 20,
  }) {
    return _request(
      settings,
      'POST',
      '/collections/$collection/points/scroll',
      body: <String, Object?>{
        'limit': limit,
        'with_payload': true,
        if (filter != null) 'filter': filter,
      },
      action: 'scroll',
    );
  }

  Future<Map<String, Object?>> pointsByIds(
    KnowledgeBaseSettings settings, {
    required String collection,
    required List<String> ids,
  }) {
    return _request(
      settings,
      'POST',
      '/collections/$collection/points',
      body: <String, Object?>{
        'ids': ids,
        'with_payload': true,
        'with_vector': false,
      },
      action: 'points_by_ids',
    );
  }

  Future<Map<String, Object?>> searchRawVector(
    KnowledgeBaseSettings settings, {
    required String collection,
    required List<double> vector,
    int limit = 10,
    Map<String, Object?>? filter,
  }) {
    return _request(
      settings,
      'POST',
      '/collections/$collection/points/search',
      body: <String, Object?>{
        'vector': vector,
        'limit': limit,
        'with_payload': true,
        'with_vector': false,
        if (filter != null) 'filter': filter,
      },
      action: 'raw_vector_search',
    );
  }

  Future<Map<String, Object?>> createPayloadIndex(
    KnowledgeBaseSettings settings, {
    required String collection,
    required String fieldName,
    required String fieldSchema,
  }) {
    return _request(
      settings,
      'PUT',
      '/collections/$collection/index',
      body: <String, Object?>{
        'field_name': fieldName,
        'field_schema': fieldSchema,
      },
      action: 'create_payload_index',
    );
  }

  Future<Map<String, Object?>> createDefaultPayloadIndexes(
    KnowledgeBaseSettings settings, {
    required String collection,
  }) async {
    const fields = <String, String>{
      'source_id': 'keyword',
      'chunk_id': 'keyword',
      'source_kind': 'keyword',
      'tags': 'keyword',
      'document_time': 'datetime',
      'updated_at': 'datetime',
    };
    final results = <String, Object?>{};
    for (final entry in fields.entries) {
      results[entry.key] = await createPayloadIndex(
        settings,
        collection: collection,
        fieldName: entry.key,
        fieldSchema: entry.value,
      );
    }
    return results;
  }

  Future<void> deletePoints(
    KnowledgeBaseSettings settings, {
    required String collection,
    required List<String> ids,
  }) async {
    await _request(
      settings,
      'POST',
      '/collections/$collection/points/delete',
      body: <String, Object?>{'points': ids},
      action: 'delete_points',
    );
  }

  Future<void> deleteCollection(
    KnowledgeBaseSettings settings,
    String collection,
  ) async {
    await _request(
      settings,
      'DELETE',
      '/collections/$collection',
      action: 'delete_collection',
    );
  }

  Future<Map<String, Object?>> _request(
    KnowledgeBaseSettings settings,
    String method,
    String path, {
    Map<String, Object?>? body,
    String? action,
  }) async {
    final response = await sendQdrantJsonRequest(
      method: method,
      uri: settings.qdrantBaseUri.replace(path: path),
      connectionTimeout: _qdrantAdminConnectionTimeout,
      openTimeout: _qdrantAdminConnectionTimeout,
      responseTimeout: _qdrantAdminRequestTimeout,
      responseIdleTimeout: _qdrantAdminResponseIdleTimeout,
      maxResponseBytes: _qdrantAdminMaxResponseBytes,
      body: body,
    );
    if (action != null) {
      final retention = KnowledgeBaseSettingRanges.qdrantLogRetainLines
          .normalize(settings.qdrantLogRetainLines);
      final overflow = _logs.length - retention + 1;
      if (overflow > 0) _logs.removeRange(0, overflow);
      _logs.add(
        QdrantAdminOperationLog(
          action: action,
          createdAt: DateTime.now().toUtc(),
          detail: '$method $path',
        ),
      );
    }
    if (response.body.trim().isEmpty) return const <String, Object?>{};
    return stringKeyedMapFromJsonText(response.body);
  }
}
