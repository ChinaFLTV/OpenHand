import 'dart:convert';
import 'dart:io';

import '../data/knowledge_base_store.dart';
import '../model/knowledge_base_settings.dart';

class QdrantMonitoringSnapshot {
  const QdrantMonitoringSnapshot({required this.sections});

  final Map<String, Map<String, Object?>> sections;
}

class QdrantMonitoringService {
  QdrantMonitoringService({required KnowledgeBaseStore store}) : _store = store;

  final KnowledgeBaseStore _store;

  Future<QdrantMonitoringSnapshot> load(KnowledgeBaseSettings settings) async {
    final stats = await _store.loadStats();
    final root = await _get(settings, '/');
    final collections = await _get(settings, '/collections');
    final collectionsResult = collections['result'];
    final collectionList = collectionsResult is Map
        ? collectionsResult['collections']
        : null;
    return QdrantMonitoringSnapshot(
      sections: <String, Map<String, Object?>>{
        '总览': <String, Object?>{
          '服务状态': root.isEmpty ? 'unknown' : 'healthy',
          'REST endpoint': settings.qdrantBaseUri.toString(),
          'gRPC endpoint': '${settings.qdrantHost}:${settings.qdrantGrpcPort}',
          'Qdrant version': root['version'] ?? '',
          '当前 collection': settings.effectiveCollectionName,
          '最近健康检查时间': DateTime.now().toUtc().toIso8601String(),
        },
        'Qdrant API 指标': <String, Object?>{
          'collections 总数': collectionList is List ? collectionList.length : 0,
          '单机模式': true,
          'payload index 状态': '可在管理弹窗检查/重建',
        },
        'OpenHand 知识库指标': <String, Object?>{
          'source 数': stats.sourceCount,
          'chunk 数': stats.chunkCount,
          '待 embedding job 数': stats.pendingJobs,
          '失败 job 数': stats.failedJobs,
          '当前 embedding model': settings.modelId,
          '当前 dimensions': settings.dimensions,
        },
      },
    );
  }

  Future<Map<String, Object?>> _get(
    KnowledgeBaseSettings settings,
    String path,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final uri = settings.qdrantBaseUri.replace(path: path);
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const <String, Object?>{};
      }
      final text = await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(text);
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } catch (_) {
      return const <String, Object?>{};
    } finally {
      client.close(force: true);
    }
    return const <String, Object?>{};
  }
}
