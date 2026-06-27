import 'dart:convert';
import 'dart:io';

import '../data/knowledge_base_store.dart';
import '../model/knowledge_base_settings.dart';

class QdrantMonitoringSnapshot {
  const QdrantMonitoringSnapshot({
    required this.sections,
    required this.raw,
    required this.collectedAt,
  });

  final Map<String, Map<String, Object?>> sections;
  final Map<String, Object?> raw;
  final DateTime collectedAt;
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
    final collectionPath = '/collections/${settings.effectiveCollectionName}';
    final collectionInfo = await _get(settings, collectionPath);
    final collectionResult =
        _object(collectionInfo['result']) ?? const <String, Object?>{};
    final countResult = await _post(
      settings,
      '$collectionPath/points/count',
      const <String, Object?>{'exact': false},
    );
    final clusterInfo = await _get(settings, '$collectionPath/cluster');
    final telemetry = await _get(settings, '/telemetry');
    final payloadSchema =
        _object(collectionResult['payload_schema']) ??
        _object(collectionResult['payload_schema'.toString()]);
    final config = _object(collectionResult['config']);
    final params = _object(config?['params']);
    final vectors = _object(params?['vectors']);
    final optimizerConfig = _object(config?['optimizer_config']);
    final hnswConfig = _object(config?['hnsw_config']);
    final countValue =
        _object(countResult['result'])?['count'] ??
        collectionResult['points_count'];
    final collectedAt = DateTime.now().toUtc();
    return QdrantMonitoringSnapshot(
      collectedAt: collectedAt,
      sections: <String, Map<String, Object?>>{
        '总览': <String, Object?>{
          '服务状态': root.isEmpty ? 'unknown' : 'healthy',
          'REST endpoint': settings.qdrantBaseUri.toString(),
          'gRPC endpoint': '${settings.qdrantHost}:${settings.qdrantGrpcPort}',
          'Qdrant version': root['version'] ?? '',
          '当前 collection': settings.effectiveCollectionName,
          'collection 状态': collectionResult['status'] ?? 'unknown',
          'optimizer 状态': collectionResult['optimizer_status'] ?? 'unknown',
          '最近健康检查时间': collectedAt.toIso8601String(),
        },
        'Docker/容器指标': <String, Object?>{
          'Docker daemon': '由插件服务扫描',
          '容器 CPU': '插件运行时提供',
          '容器内存': '插件运行时提供',
          '网络收发': '插件运行时提供',
          'Block I/O': '插件运行时提供',
          'restart count': '插件运行时提供',
          '最近日志摘要': '可在插件详情查看',
        },
        'Qdrant API 指标': <String, Object?>{
          'collections 总数': collectionList is List ? collectionList.length : 0,
          'points 总数': countValue ?? 0,
          'vectors 总数': collectionResult['vectors_count'] ?? 0,
          'indexed vectors 总数': collectionResult['indexed_vectors_count'] ?? 0,
          'segments 数': collectionResult['segments_count'] ?? 0,
          'payload schema 字段数': payloadSchema?.length ?? 0,
          'vector size': vectors?['size'] ?? settings.dimensions,
          'distance': vectors?['distance'] ?? settings.distanceMetric,
          'HNSW m': hnswConfig?['m'] ?? settings.hnswM,
          'optimizer indexing threshold':
              optimizerConfig?['indexing_threshold'] ?? '-',
          '单机模式': true,
          'payload index 状态': payloadSchema?.isEmpty == false
              ? '已配置 payload schema'
              : '未发现 payload schema',
          'cluster 状态': clusterInfo.isEmpty ? '本地单机/不可用' : '已返回 cluster 信息',
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
      raw: <String, Object?>{
        'root': root,
        'collections': collections,
        'collection_info': collectionInfo,
        'point_count': countResult,
        'cluster': clusterInfo,
        'telemetry': telemetry,
      },
    );
  }

  static Map<String, Object?>? _object(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) return Map<String, Object?>.from(value);
    return null;
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

  Future<Map<String, Object?>> _post(
    KnowledgeBaseSettings settings,
    String path,
    Map<String, Object?> body,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client.postUrl(
        settings.qdrantBaseUri.replace(path: path),
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
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
