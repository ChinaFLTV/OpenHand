import 'dart:convert';
import 'dart:io';

import '../model/knowledge_base_settings.dart';

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

  Future<List<Map<String, Object?>>> listCollections(
    KnowledgeBaseSettings settings,
  ) async {
    final json = await _request(settings, 'GET', '/collections');
    final result = json['result'];
    final collections = result is Map ? result['collections'] : null;
    if (collections is! List) return const <Map<String, Object?>>[];
    return collections
        .whereType<Map>()
        .map((item) => Map<String, Object?>.from(item))
        .toList(growable: false);
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
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.openUrl(
        method,
        settings.qdrantBaseUri.replace(path: path),
      );
      request.headers.contentType = ContentType.json;
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close();
      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Qdrant ${response.statusCode}: $text');
      }
      if (action != null) {
        _logs.add(
          QdrantAdminOperationLog(
            action: action,
            createdAt: DateTime.now().toUtc(),
            detail: '$method $path',
          ),
        );
      }
      if (text.trim().isEmpty) return const <String, Object?>{};
      final decoded = jsonDecode(text);
      return decoded is Map
          ? Map<String, Object?>.from(decoded)
          : const <String, Object?>{};
    } finally {
      client.close(force: true);
    }
  }
}
