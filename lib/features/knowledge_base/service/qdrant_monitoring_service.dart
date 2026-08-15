import 'dart:convert';

import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../data/knowledge_base_store.dart';
import '../model/knowledge_base_settings.dart';
import 'qdrant_http_client.dart';

const Duration _qdrantMonitoringConnectionTimeout = Duration(seconds: 3);
const Duration _qdrantMonitoringRequestTimeout = Duration(seconds: 8);
const Duration _qdrantMonitoringResponseIdleTimeout = Duration(seconds: 3);
const int _qdrantMonitoringMaxResponseBytes = 8 * kBytesPerMiB;

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
    final collectionPath = '/collections/${settings.effectiveCollectionName}';
    final statsFuture = _store.loadStats();
    final rootFuture = _get(settings, '/');
    final collectionsFuture = _get(settings, '/collections');
    final collectionInfoFuture = _get(settings, collectionPath);
    final countFuture = _post(
      settings,
      '$collectionPath/points/count',
      const <String, Object?>{'exact': false},
    );
    final clusterInfoFuture = _get(settings, '$collectionPath/cluster');
    final telemetryFuture = _get(settings, '/telemetry');

    final stats = await statsFuture;
    final root = await rootFuture;
    final collections = await collectionsFuture;
    final collectionInfo = await collectionInfoFuture;
    final countResult = await countFuture;
    final clusterInfo = await clusterInfoFuture;
    final telemetry = await telemetryFuture;
    final collectionsResult = collections['result'];
    final collectionList = collectionsResult is Map
        ? collectionsResult['collections']
        : null;
    final collectionResult =
        optionalStringKeyedMapFromValue(collectionInfo['result']) ??
        const <String, Object?>{};
    final payloadSchema = optionalStringKeyedMapFromValue(
      collectionResult['payload_schema'],
    );
    final config = optionalStringKeyedMapFromValue(collectionResult['config']);
    final params = optionalStringKeyedMapFromValue(config?['params']);
    final vectors = optionalStringKeyedMapFromValue(params?['vectors']);
    final optimizerConfig = optionalStringKeyedMapFromValue(
      config?['optimizer_config'],
    );
    final hnswConfig = optionalStringKeyedMapFromValue(config?['hnsw_config']);
    final walConfig = optionalStringKeyedMapFromValue(config?['wal_config']);
    final quantizationConfig = optionalStringKeyedMapFromValue(
      config?['quantization_config'],
    );
    final strictModeConfig = optionalStringKeyedMapFromValue(
      config?['strict_mode_config'],
    );
    final telemetryResult = optionalStringKeyedMapFromValue(
      telemetry['result'],
    );
    final telemetryCollections = optionalStringKeyedMapFromValue(
      telemetryResult?['collections'],
    );
    final telemetryRequests = optionalStringKeyedMapFromValue(
      telemetryResult?['requests'],
    );
    final telemetryApp = optionalStringKeyedMapFromValue(
      telemetryResult?['app'],
    );
    final payloadFieldNames = payloadSchema?.keys.toList(growable: false);
    final countValue =
        optionalStringKeyedMapFromValue(countResult['result'])?['count'] ??
        collectionResult['points_count'];
    final collectedAt = DateTime.now().toUtc();
    return QdrantMonitoringSnapshot(
      collectedAt: collectedAt,
      sections: <String, Map<String, Object?>>{
        'overview': <String, Object?>{
          'service_status': root.isEmpty ? 'unknown' : 'healthy',
          'rest_endpoint': settings.qdrantBaseUri.toString(),
          'grpc_endpoint': '${settings.qdrantHost}:${settings.qdrantGrpcPort}',
          'qdrant_version': root['version'] ?? '',
          'current_collection': settings.effectiveCollectionName,
          'collection_status': collectionResult['status'] ?? 'unknown',
          'optimizer_status': collectionResult['optimizer_status'] ?? 'unknown',
          'last_health_check_at': collectedAt.toIso8601String(),
        },
        'docker_container': <String, Object?>{
          'docker_daemon': 'plugin_service_scan',
          'container_cpu': 'plugin_runtime_metric',
          'container_memory': 'plugin_runtime_metric',
          'network_io': 'plugin_runtime_metric',
          'block_io': 'plugin_runtime_metric',
          'restart_count': 'plugin_runtime_metric',
          'latest_log_summary': 'plugin_details_logs',
        },
        'qdrant_api': <String, Object?>{
          'collections_total': collectionList is List
              ? collectionList.length
              : 0,
          'points_total': countValue ?? 0,
          'vectors_total': collectionResult['vectors_count'] ?? 0,
          'indexed_vectors_total':
              collectionResult['indexed_vectors_count'] ?? 0,
          'segments_total': collectionResult['segments_count'] ?? 0,
          'payload_schema_fields': payloadSchema?.length ?? 0,
          'payload_schema_names': payloadFieldNames?.join(', ') ?? '-',
          'vector_size': vectors?['size'] ?? settings.dimensions,
          'distance': vectors?['distance'] ?? settings.distanceMetric,
          'single_node_mode': true,
          'payload_index_status': payloadSchema?.isEmpty == false
              ? 'payload_schema_configured'
              : 'payload_schema_missing',
          'cluster_status': clusterInfo.isEmpty
              ? 'local_single_node_or_unavailable'
              : 'cluster_info_available',
        },
        'collection_config': <String, Object?>{
          'hnsw_m': hnswConfig?['m'] ?? settings.hnswM,
          'hnsw_ef_construct':
              hnswConfig?['ef_construct'] ?? settings.hnswEfConstruct,
          'hnsw_full_scan_threshold': hnswConfig?['full_scan_threshold'] ?? '-',
          'hnsw_max_indexing_threads':
              hnswConfig?['max_indexing_threads'] ?? '-',
          'on_disk_payload': params?['on_disk_payload'] ?? '-',
          'shard_number': params?['shard_number'] ?? '-',
          'replication_factor': params?['replication_factor'] ?? '-',
          'write_consistency_factor':
              params?['write_consistency_factor'] ?? '-',
          'read_fan_out_factor': params?['read_fan_out_factor'] ?? '-',
        },
        'storage_optimizer': <String, Object?>{
          'optimizer_deleted_threshold':
              optimizerConfig?['deleted_threshold'] ?? '-',
          'optimizer_vacuum_min_vector_number':
              optimizerConfig?['vacuum_min_vector_number'] ?? '-',
          'optimizer_default_segment_number':
              optimizerConfig?['default_segment_number'] ?? '-',
          'optimizer_max_segment_size':
              optimizerConfig?['max_segment_size'] ?? '-',
          'optimizer_indexing_threshold':
              optimizerConfig?['indexing_threshold'] ?? '-',
          'optimizer_flush_interval_sec':
              optimizerConfig?['flush_interval_sec'] ?? '-',
          'wal_capacity_mb': walConfig?['wal_capacity_mb'] ?? '-',
          'wal_segments_ahead': walConfig?['wal_segments_ahead'] ?? '-',
          'quantization': quantizationConfig?.isEmpty == false
              ? jsonEncode(quantizationConfig)
              : '-',
          'strict_mode': strictModeConfig?.isEmpty == false
              ? jsonEncode(strictModeConfig)
              : '-',
        },
        'telemetry': <String, Object?>{
          'telemetry_status': telemetry.isEmpty ? 'unavailable' : 'available',
          'app_version': telemetryApp?['version'] ?? root['version'] ?? '-',
          'app_name': telemetryApp?['name'] ?? 'qdrant',
          'telemetry_collections': telemetryCollections?.isEmpty == false
              ? telemetryCollections
              : '-',
          'telemetry_requests': telemetryRequests?.isEmpty == false
              ? telemetryRequests
              : '-',
        },
        'openhand_knowledge': <String, Object?>{
          'source_count': stats.sourceCount,
          'chunk_count': stats.chunkCount,
          'pending_embedding_jobs': stats.pendingJobs,
          'failed_embedding_jobs': stats.failedJobs,
          'embedding_model': settings.modelId,
          'embedding_dimensions': settings.dimensions,
          'retrieval_top_n': settings.topN,
          'retrieval_top_k': settings.topK,
          'min_similarity': settings.minSimilarity,
          'prompt_chunk_budget': settings.maxPromptChunks,
          'prompt_token_budget': settings.maxPromptTokens,
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

  Future<Map<String, Object?>> _get(
    KnowledgeBaseSettings settings,
    String path,
  ) async {
    return _request(settings, 'GET', path);
  }

  Future<Map<String, Object?>> _post(
    KnowledgeBaseSettings settings,
    String path,
    Map<String, Object?> body,
  ) async {
    return _request(settings, 'POST', path, body: body);
  }

  Future<Map<String, Object?>> _request(
    KnowledgeBaseSettings settings,
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    try {
      final uri = settings.qdrantBaseUri.replace(path: path);
      final response = await sendQdrantJsonRequest(
        method: method,
        uri: uri,
        connectionTimeout: _qdrantMonitoringConnectionTimeout,
        openTimeout: _qdrantMonitoringConnectionTimeout,
        responseTimeout: _qdrantMonitoringRequestTimeout,
        responseIdleTimeout: _qdrantMonitoringResponseIdleTimeout,
        maxResponseBytes: _qdrantMonitoringMaxResponseBytes,
        body: body,
      );
      return stringKeyedMapFromJsonText(response.body);
    } catch (_) {
      return const <String, Object?>{};
    }
  }
}
