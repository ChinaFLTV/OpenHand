import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:openhand/shared/util/text_normalization.dart';

import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/text_clip.dart';

const int webGatewayOpsTrafficWindowMinutes = 12;
const int webGatewayRuntimeRecentErrorLimit = 16;
const int webGatewayRuntimeTopRouteLimit = 32;

/// Runtime types for the Web 通用消息平台 service.
///
/// 这些类从 [service/web_message_platform_service.dart] 抽出到独立模型文件，
/// 供服务、控制器与视图复用。service 仍会 re-export 这些类型，view 的现有
/// import 无需调整。

/// 主题快照——发往 Web 端用于让前端配色与 OpenHand 主色保持一致。
class WebGatewayThemeSnapshot {
  const WebGatewayThemeSnapshot({
    this.primary = '#6750A4',
    this.onPrimary = '#FFFFFF',
    this.primaryContainer = '#EADDFF',
    this.onPrimaryContainer = '#21005D',
    this.secondary = '#625B71',
    this.onSecondary = '#FFFFFF',
    this.secondaryContainer = '#E8DEF8',
    this.onSecondaryContainer = '#1D192B',
    this.tertiary = '#7D5260',
    this.onTertiary = '#FFFFFF',
    this.tertiaryContainer = '#FFD8E4',
    this.onTertiaryContainer = '#31111D',
    this.surface = '#FFFBFE',
    this.surfaceContainerLowest = '#FFFFFF',
    this.surfaceContainerLow = '#F7F2FA',
    this.surfaceContainer = '#F3EDF7',
    this.surfaceContainerHigh = '#ECE6F0',
    this.surfaceContainerHighest = '#E6E0E9',
    this.onSurface = '#1D1B20',
    this.onSurfaceVariant = '#49454F',
    this.outline = '#CAC4D0',
    this.outlineVariant = '#CAC4D0',
    this.inverseSurface = '#322F35',
    this.inverseOnSurface = '#F5EFF7',
    this.error = '#B3261E',
    this.errorContainer = '#F9DEDC',
    this.onErrorContainer = '#410E0B',
    this.brightness = 'light',
  });

  final String primary;
  final String onPrimary;
  final String primaryContainer;
  final String onPrimaryContainer;
  final String secondary;
  final String onSecondary;
  final String secondaryContainer;
  final String onSecondaryContainer;
  final String tertiary;
  final String onTertiary;
  final String tertiaryContainer;
  final String onTertiaryContainer;
  final String surface;
  final String surfaceContainerLowest;
  final String surfaceContainerLow;
  final String surfaceContainer;
  final String surfaceContainerHigh;
  final String surfaceContainerHighest;
  final String onSurface;
  final String onSurfaceVariant;
  final String outline;
  final String outlineVariant;
  final String inverseSurface;
  final String inverseOnSurface;
  final String error;
  final String errorContainer;
  final String onErrorContainer;
  final String brightness;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'primary': primary,
      'on_primary': onPrimary,
      'primary_container': primaryContainer,
      'on_primary_container': onPrimaryContainer,
      'secondary': secondary,
      'on_secondary': onSecondary,
      'secondary_container': secondaryContainer,
      'on_secondary_container': onSecondaryContainer,
      'tertiary': tertiary,
      'on_tertiary': onTertiary,
      'tertiary_container': tertiaryContainer,
      'on_tertiary_container': onTertiaryContainer,
      'surface': surface,
      'surface_container_lowest': surfaceContainerLowest,
      'surface_container_low': surfaceContainerLow,
      'surface_container': surfaceContainer,
      'surface_container_high': surfaceContainerHigh,
      'surface_container_highest': surfaceContainerHighest,
      'on_surface': onSurface,
      'on_surface_variant': onSurfaceVariant,
      'outline': outline,
      'outline_variant': outlineVariant,
      'inverse_surface': inverseSurface,
      'inverse_on_surface': inverseOnSurface,
      'error': error,
      'error_container': errorContainer,
      'on_error_container': onErrorContainer,
      'brightness': brightness,
    };
  }
}

/// Web 服务运行时状态机。
enum WebGatewayRuntimeState { stopped, starting, running, stopping, crashed }

WebGatewayRuntimeState webGatewayRuntimeStateFromValue(Object? value) {
  return enumByNameOr(
    WebGatewayRuntimeState.values,
    value,
    fallback: WebGatewayRuntimeState.stopped,
  );
}

/// 日志级别。`telemetry` 用于结构化遥测事件，与普通日志区分。
enum WebGatewayLogLevel { info, success, warn, error, debug, telemetry }

WebGatewayLogLevel webGatewayLogLevelFromValue(Object? value) {
  return enumByNameOr(
    WebGatewayLogLevel.values,
    value,
    fallback: WebGatewayLogLevel.info,
  );
}

/// 单条日志记录。`toLogLine()` 输出 NDJSON 行，方便文件持久化与流式回放。
class WebGatewayLogEntry {
  const WebGatewayLogEntry({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.data = const <String, Object?>{},
  });

  final int id;
  final DateTime timestamp;
  final WebGatewayLogLevel level;
  final String tag;
  final String message;
  final Map<String, Object?> data;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'level': level.name,
      'tag': tag,
      'message': message,
      if (data.isNotEmpty) 'data': data,
    };
  }

  String toLogLine() => jsonEncode(toJson());

  static WebGatewayLogEntry fromJson(Object? raw) {
    final map = stringKeyedMapFromValue(raw);
    final timestamp =
        utcDateTimeFromValue(map['timestamp']) ?? DateTime.now().toUtc();
    return WebGatewayLogEntry(
      id: nonNegativeIntFromValue(map['id'], fallback: 0),
      timestamp: timestamp,
      level: webGatewayLogLevelFromValue(map['level']),
      tag: stringFromValue(map['tag'], fallback: 'OPS'),
      message: stringFromValue(map['message']),
      data: stringKeyedMapFromValue(map['data']),
    );
  }
}

/// 健康检查结果。
class WebGatewayHealthResult {
  const WebGatewayHealthResult({
    required this.ok,
    required this.statusCode,
    required this.durationMs,
    required this.summary,
    this.bodyPreview = '',
  });

  final bool ok;
  final int statusCode;
  final int durationMs;
  final String summary;
  final String bodyPreview;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'ok': ok,
      'status_code': statusCode,
      'duration_ms': durationMs,
      'summary': summary,
      'body_preview': bodyPreview,
    };
  }
}

/// 单个 Web 网关 URL 的连通性探测结果。
class WebGatewayConnectivityProbeResult {
  const WebGatewayConnectivityProbeResult({
    required this.baseUrl,
    required this.endpointUrl,
    required this.host,
    required this.port,
    required this.ok,
    required this.statusCode,
    required this.durationMs,
    this.errorMessage = '',
    this.bodyPreview = '',
  });

  final String baseUrl;
  final String endpointUrl;
  final String host;
  final int port;
  final bool ok;
  final int statusCode;
  final int durationMs;
  final String errorMessage;
  final String bodyPreview;

  String get hostPort => '$host:$port';

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'base_url': baseUrl,
      'endpoint_url': endpointUrl,
      'host': host,
      'port': port,
      'ok': ok,
      'status_code': statusCode,
      'duration_ms': durationMs,
      if (errorMessage.isNotEmpty) 'error_message': errorMessage,
      if (bodyPreview.isNotEmpty) 'body_preview': bodyPreview,
    };
  }
}

/// Web 网关当前全部可访问 URL 的连通性探测汇总。
class WebGatewayConnectivityTestResult {
  const WebGatewayConnectivityTestResult({
    required this.startedAt,
    required this.finishedAt,
    required this.targets,
    required this.logs,
  });

  final DateTime startedAt;
  final DateTime finishedAt;
  final List<WebGatewayConnectivityProbeResult> targets;
  final List<String> logs;

  bool get ok => targets.isNotEmpty && targets.every((item) => item.ok);
  int get successCount => targets.where((item) => item.ok).length;
  int get failureCount => targets.length - successCount;
  int get durationMs => finishedAt.difference(startedAt).inMilliseconds;
  String get summary {
    if (targets.isEmpty) return '没有可测试的 URL';
    return ok
        ? '全部 ${targets.length} 个入口连通'
        : '$failureCount 个入口不可达 / ${targets.length} 个入口';
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'ok': ok,
      'summary': summary,
      'started_at': startedAt.toUtc().toIso8601String(),
      'finished_at': finishedAt.toUtc().toIso8601String(),
      'duration_ms': durationMs,
      'success_count': successCount,
      'failure_count': failureCount,
      'targets': targets.map((item) => item.toJson()).toList(growable: false),
      'logs': logs,
    };
  }
}

/// 资源清理结果，用于 OpenHand 设置面板的"数据清理"统计。
class WebGatewayCleanupResult {
  const WebGatewayCleanupResult({
    required this.timestamp,
    required this.target,
    required this.expiredOnly,
    required this.deletedFiles,
    required this.deletedDirectories,
    required this.bytesFreed,
    required this.memoryLogEntriesCleared,
  });

  final DateTime timestamp;
  final String target;
  final bool expiredOnly;
  final int deletedFiles;
  final int deletedDirectories;
  final int bytesFreed;
  final int memoryLogEntriesCleared;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'timestamp': timestamp.toUtc().toIso8601String(),
      'target': target,
      'expired_only': expiredOnly,
      'deleted_files': deletedFiles,
      'deleted_directories': deletedDirectories,
      'bytes_freed': bytesFreed,
      'memory_log_entries_cleared': memoryLogEntriesCleared,
    };
  }

  static WebGatewayCleanupResult fromJson(Object? raw) {
    final map = stringKeyedMapFromValue(raw);
    return WebGatewayCleanupResult(
      timestamp:
          utcDateTimeFromValue(map['timestamp']) ?? DateTime.now().toUtc(),
      target: stringFromValue(map['target'], fallback: 'ops'),
      expiredOnly: boolFromValue(map['expired_only']),
      deletedFiles: nonNegativeIntFromValue(map['deleted_files'], fallback: 0),
      deletedDirectories: nonNegativeIntFromValue(
        map['deleted_directories'],
        fallback: 0,
      ),
      bytesFreed: nonNegativeIntFromValue(map['bytes_freed'], fallback: 0),
      memoryLogEntriesCleared: nonNegativeIntFromValue(
        map['memory_log_entries_cleared'],
        fallback: 0,
      ),
    );
  }
}

class WebGatewayTrafficSample {
  const WebGatewayTrafficSample({
    required this.minute,
    this.success = 0,
    this.blocked = 0,
    this.failed = 0,
    this.inboundBytes = 0,
    this.outboundBytes = 0,
    this.avgLatencyMs = 0,
    this.p95LatencyMs = 0,
  });

  final DateTime minute;
  final int success;
  final int blocked;
  final int failed;
  final int inboundBytes;
  final int outboundBytes;
  final int avgLatencyMs;
  final int p95LatencyMs;

  int get total => success + blocked + failed;

  Map<String, Object?> toJson() => <String, Object?>{
    'minute': minute.toUtc().toIso8601String(),
    'success': success,
    'blocked': blocked,
    'failed': failed,
    'inbound_bytes': inboundBytes,
    'outbound_bytes': outboundBytes,
    'avg_latency_ms': avgLatencyMs,
    'p95_latency_ms': p95LatencyMs,
  };

  static WebGatewayTrafficSample fromJson(Object? raw) {
    final map = stringKeyedMapFromValue(raw);
    return WebGatewayTrafficSample(
      minute: utcDateTimeFromValue(map['minute']) ?? DateTime.now().toUtc(),
      success: nonNegativeIntFromValue(map['success'], fallback: 0),
      blocked: nonNegativeIntFromValue(map['blocked'], fallback: 0),
      failed: nonNegativeIntFromValue(map['failed'], fallback: 0),
      inboundBytes: nonNegativeIntFromValue(map['inbound_bytes'], fallback: 0),
      outboundBytes: nonNegativeIntFromValue(
        map['outbound_bytes'],
        fallback: 0,
      ),
      avgLatencyMs: nonNegativeIntFromValue(map['avg_latency_ms'], fallback: 0),
      p95LatencyMs: nonNegativeIntFromValue(map['p95_latency_ms'], fallback: 0),
    );
  }
}

/// 实时运行快照，作为 Ops 弹窗 / Web 端 ops API 的统一数据载体。
class WebGatewayRuntimeSnapshot {
  const WebGatewayRuntimeSnapshot({
    required this.state,
    required this.startedAt,
    required this.uptimeMs,
    required this.boundUrl,
    required this.accessibleUrls,
    required this.activeRequests,
    this.currentConnections = 0,
    this.maxConcurrentRequests = 0,
    this.activeRequestRatio = 0,
    required this.totalRequests,
    required this.totalErrors,
    this.blockedRequests = 0,
    required this.totalBytesIn,
    required this.totalBytesOut,
    this.fileMutationCount = 0,
    required this.crashCount,
    required this.restartCount,
    required this.currentRssBytes,
    required this.maxRssBytes,
    required this.cpuPercent,
    required this.threadCount,
    required this.fileHandleCount,
    required this.swapBytes,
    required this.logBytes,
    required this.openSessionCount,
    required this.lastError,
    // 扩展观测维度（默认空，老调用方零侵入）。
    this.statusCodeBreakdown = const <String, int>{},
    this.methodBreakdown = const <String, int>{},
    this.topRoutes = const <MapEntry<String, int>>[],
    this.latencyStats = const WebGatewayLatencyStats(),
    this.latencyBuckets = const <String, int>{},
    this.requestsPerMinute = 0,
    this.errorsPerMinute = 0,
    this.bytesInPerMinute = 0,
    this.bytesOutPerMinute = 0,
    this.slowestRecent,
    this.lastErrorAt,
    this.lastErrorPath = '',
    this.processId = 0,
    this.platform = '',
    this.platformVersion = '',
    this.dartVersion = '',
    this.hostName = '',
    this.activeSseSubscriptions = 0,
    this.recentErrors = const <Map<String, Object?>>[],
    this.logLevelBreakdown = const <String, int>{},
    this.memoryLogCount = 0,
    this.fileLogPendingWrites = 0,
    this.fileLogPendingBytes = 0,
    this.fileLogDroppedWrites = 0,
    this.sendPhaseBreakdown = const <String, int>{},
    this.allowedModelCount = 0,
    this.modelProviderCount = 0,
    this.templateCount = 0,
    this.cronEnabledCount = 0,
    this.cronTotalCount = 0,
    this.memoryEntryCount = 0,
    this.mcpServerEnabledCount = 0,
    this.mcpServerTotalCount = 0,
    this.ipDistribution = const <String, int>{},
    this.peerDistribution = const <String, int>{},
    this.clientDistribution = const <String, int>{},
    this.requestDistribution = const <String, int>{},
    this.protocolDistribution = const <String, int>{},
    this.trafficSeries = const <WebGatewayTrafficSample>[],
  });

  final WebGatewayRuntimeState state;
  final DateTime? startedAt;
  final int uptimeMs;
  final String boundUrl;

  /// 当前可访问该 Web 服务的 URL 列表。
  /// - 监听 `0.0.0.0` / `::` 时枚举：`localhost` + `127.0.0.1` + 所有非环回 IPv4
  /// - 监听具体 IP 时仅含 `boundUrl`
  /// - 未启动时为空列表
  final List<String> accessibleUrls;
  final int activeRequests;
  final int currentConnections;
  final int maxConcurrentRequests;
  final double activeRequestRatio;
  final int totalRequests;
  final int totalErrors;
  final int blockedRequests;
  final int totalBytesIn;
  final int totalBytesOut;
  final int fileMutationCount;
  final int crashCount;
  final int restartCount;
  final int currentRssBytes;
  final int maxRssBytes;
  final double? cpuPercent;
  final int? threadCount;
  final int? fileHandleCount;
  final int? swapBytes;
  final int logBytes;
  final int openSessionCount;
  final String lastError;

  // 扩展观测：HTTP 状态码 / method / 路由 / 延迟 / 速率 / 慢请求 / 错误上下文 / 进程身份。
  final Map<String, int> statusCodeBreakdown;
  final Map<String, int> methodBreakdown;
  final List<MapEntry<String, int>> topRoutes;
  final WebGatewayLatencyStats latencyStats;
  final Map<String, int> latencyBuckets;
  final double requestsPerMinute;
  final double errorsPerMinute;
  final double bytesInPerMinute;
  final double bytesOutPerMinute;
  final WebGatewayRecentSlowRequest? slowestRecent;
  final DateTime? lastErrorAt;
  final String lastErrorPath;
  final int processId;
  final String platform;
  final String platformVersion;
  final String dartVersion;
  final String hostName;

  /// 当前活跃的 SSE 长连接数（每个 `/api/sessions/<id>/events` 客户端 +1）。
  final int activeSseSubscriptions;

  /// 最近 N 条 4xx/5xx 请求环（限制 16 条，path/message 裁剪），按发生顺序追加。
  /// 每条含：`at`(ISO8601) `method` `path` `status` `duration_ms` 可选 `message`。
  final List<Map<String, Object?>> recentErrors;

  /// 进程内内存日志按级别统计，便于快速判断错误/警告是否在持续增长。
  final Map<String, int> logLevelBreakdown;
  final int memoryLogCount;
  final int fileLogPendingWrites;
  final int fileLogPendingBytes;
  final int fileLogDroppedWrites;

  /// 当前所有会话按发送阶段分布。
  final Map<String, int> sendPhaseBreakdown;

  /// Web 服务可见资源规模。
  final int allowedModelCount;
  final int modelProviderCount;
  final int templateCount;
  final int cronEnabledCount;
  final int cronTotalCount;
  final int memoryEntryCount;

  /// MCP 服务器已启用 / 总数，为 Ops 面板提供快速合规指示。
  final int mcpServerEnabledCount;
  final int mcpServerTotalCount;

  final Map<String, int> ipDistribution;

  /// 来源网络端点分布。IPv4 为 `IP:port`，IPv6 为 `[IP]:port`；历史记录端口为 `*`。
  final Map<String, int> peerDistribution;
  final Map<String, int> clientDistribution;
  final Map<String, int> requestDistribution;
  final Map<String, int> protocolDistribution;
  final List<WebGatewayTrafficSample> trafficSeries;

  int get successTotal => math.max(0, totalRequests - effectiveErrorTotal);
  int get failedRequests =>
      math.max(0, effectiveErrorTotal - effectiveBlockedTotal);
  int get effectiveErrorTotal => math.min(totalRequests, totalErrors);
  int get effectiveBlockedTotal =>
      math.min(effectiveErrorTotal, blockedRequests);
  Map<String, int> get effectivePeerDistribution => peerDistribution.isEmpty
      ? _webGatewayLegacyPeerDistribution(ipDistribution)
      : peerDistribution;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'state': state.name,
      'started_at': startedAt?.toUtc().toIso8601String(),
      'uptime_ms': uptimeMs,
      'bound_url': boundUrl,
      'accessible_urls': accessibleUrls,
      'active_requests': activeRequests,
      'current_connections': currentConnections,
      'max_concurrent_requests': maxConcurrentRequests,
      'active_request_ratio': activeRequestRatio,
      'total_requests': totalRequests,
      'total_errors': totalErrors,
      'blocked_requests': blockedRequests,
      'total_bytes_in': totalBytesIn,
      'total_bytes_out': totalBytesOut,
      'file_mutation_count': fileMutationCount,
      'crash_count': crashCount,
      'restart_count': restartCount,
      'process': <String, Object?>{
        'pid': processId <= 0 ? pid : processId,
        'current_rss_bytes': currentRssBytes,
        'max_rss_bytes': maxRssBytes,
        'cpu_percent': cpuPercent,
        'thread_count': threadCount,
        'file_handle_count': fileHandleCount,
        'swap_bytes': swapBytes,
        'disk_log_bytes': logBytes,
        'platform': platform.isEmpty ? Platform.operatingSystem : platform,
        'platform_version': platformVersion.isEmpty
            ? Platform.operatingSystemVersion
            : platformVersion,
        'dart_version': dartVersion,
        'host_name': hostName,
      },
      'open_session_count': openSessionCount,
      'last_error': lastError,
      // 扩展观测：snake_case，便于 Web ops.ts 直接同名 destructure。
      'status_code_breakdown': statusCodeBreakdown,
      'method_breakdown': methodBreakdown,
      'top_routes': topRoutes
          .map((e) => <String, Object?>{'path': e.key, 'count': e.value})
          .toList(growable: false),
      'latency_stats': latencyStats.toJson(),
      'latency_buckets': latencyBuckets,
      'requests_per_minute': requestsPerMinute,
      'errors_per_minute': errorsPerMinute,
      'bytes_in_per_minute': bytesInPerMinute,
      'bytes_out_per_minute': bytesOutPerMinute,
      'slowest_recent': slowestRecent?.toJson(),
      'last_error_at': lastErrorAt?.toUtc().toIso8601String(),
      'last_error_path': lastErrorPath,
      'active_sse_subscriptions': activeSseSubscriptions,
      'recent_errors': recentErrors,
      'log_level_breakdown': logLevelBreakdown,
      'memory_log_count': memoryLogCount,
      'file_log_pending_writes': fileLogPendingWrites,
      'file_log_pending_bytes': fileLogPendingBytes,
      'file_log_dropped_writes': fileLogDroppedWrites,
      'send_phase_breakdown': sendPhaseBreakdown,
      'allowed_model_count': allowedModelCount,
      'model_provider_count': modelProviderCount,
      'template_count': templateCount,
      'cron_enabled_count': cronEnabledCount,
      'cron_total_count': cronTotalCount,
      'memory_entry_count': memoryEntryCount,
      'mcp_server_enabled_count': mcpServerEnabledCount,
      'mcp_server_total_count': mcpServerTotalCount,
      'ip_distribution': ipDistribution,
      'peer_distribution': peerDistribution,
      'client_distribution': clientDistribution,
      'request_distribution': requestDistribution,
      'protocol_distribution': protocolDistribution,
      'traffic_series': trafficSeries
          .map((item) => item.toJson())
          .toList(growable: false),
    };
  }

  static WebGatewayRuntimeSnapshot fromJson(Object? raw) {
    final map = stringKeyedMapFromValue(raw);
    final process = stringKeyedMapFromValue(map['process']);
    final ipDistribution = _webGatewayStringIntMapFromValue(
      map['ip_distribution'],
    );
    final peerDistribution = _webGatewayStringIntMapFromValue(
      map['peer_distribution'],
      maxKeys: 128,
    );
    return WebGatewayRuntimeSnapshot(
      state: webGatewayRuntimeStateFromValue(map['state']),
      startedAt: utcDateTimeFromValue(map['started_at']),
      uptimeMs: nonNegativeIntFromValue(map['uptime_ms'], fallback: 0),
      boundUrl: stringFromValue(map['bound_url']),
      accessibleUrls: stringListFromValue(map['accessible_urls']),
      activeRequests: nonNegativeIntFromValue(
        map['active_requests'],
        fallback: 0,
      ),
      currentConnections: nonNegativeIntFromValue(
        map['current_connections'],
        fallback:
            nonNegativeIntFromValue(map['active_requests'], fallback: 0) +
            nonNegativeIntFromValue(
              map['active_sse_subscriptions'],
              fallback: 0,
            ),
      ),
      maxConcurrentRequests: nonNegativeIntFromValue(
        map['max_concurrent_requests'],
        fallback: 0,
      ),
      activeRequestRatio: doubleFromValue(
        map['active_request_ratio'],
        fallback: 0,
      ),
      totalRequests: nonNegativeIntFromValue(
        map['total_requests'],
        fallback: 0,
      ),
      totalErrors: nonNegativeIntFromValue(map['total_errors'], fallback: 0),
      blockedRequests: nonNegativeIntFromValue(
        map['blocked_requests'],
        fallback: 0,
      ),
      totalBytesIn: nonNegativeIntFromValue(map['total_bytes_in'], fallback: 0),
      totalBytesOut: nonNegativeIntFromValue(
        map['total_bytes_out'],
        fallback: 0,
      ),
      fileMutationCount: nonNegativeIntFromValue(
        map['file_mutation_count'],
        fallback: 0,
      ),
      crashCount: nonNegativeIntFromValue(map['crash_count'], fallback: 0),
      restartCount: nonNegativeIntFromValue(map['restart_count'], fallback: 0),
      currentRssBytes: nonNegativeIntFromValue(
        process['current_rss_bytes'] ?? map['current_rss_bytes'],
        fallback: 0,
      ),
      maxRssBytes: nonNegativeIntFromValue(
        process['max_rss_bytes'] ?? map['max_rss_bytes'],
        fallback: 0,
      ),
      cpuPercent: optionalDoubleFromValue(process['cpu_percent']),
      threadCount: optionalIntFromValue(process['thread_count']),
      fileHandleCount: optionalIntFromValue(process['file_handle_count']),
      swapBytes: optionalIntFromValue(process['swap_bytes']),
      logBytes: nonNegativeIntFromValue(
        process['disk_log_bytes'] ?? map['log_bytes'],
        fallback: 0,
      ),
      openSessionCount: nonNegativeIntFromValue(
        map['open_session_count'],
        fallback: 0,
      ),
      lastError: stringFromValue(map['last_error']),
      statusCodeBreakdown: _webGatewayStringIntMapFromValue(
        map['status_code_breakdown'],
      ),
      methodBreakdown: _webGatewayStringIntMapFromValue(
        map['method_breakdown'],
      ),
      topRoutes: _webGatewayTopRoutesFromValue(map['top_routes']),
      latencyStats: WebGatewayLatencyStats.fromJson(map['latency_stats']),
      latencyBuckets: _webGatewayStringIntMapFromValue(map['latency_buckets']),
      requestsPerMinute: doubleFromValue(
        map['requests_per_minute'],
        fallback: 0,
      ),
      errorsPerMinute: doubleFromValue(map['errors_per_minute'], fallback: 0),
      bytesInPerMinute: doubleFromValue(
        map['bytes_in_per_minute'],
        fallback: 0,
      ),
      bytesOutPerMinute: doubleFromValue(
        map['bytes_out_per_minute'],
        fallback: 0,
      ),
      slowestRecent: stringKeyedMapFromValue(map['slowest_recent']).isEmpty
          ? null
          : WebGatewayRecentSlowRequest.fromJson(map['slowest_recent']),
      lastErrorAt: utcDateTimeFromValue(map['last_error_at']),
      lastErrorPath: stringFromValue(map['last_error_path']),
      processId: nonNegativeIntFromValue(process['pid'], fallback: 0),
      platform: stringFromValue(process['platform']),
      platformVersion: stringFromValue(process['platform_version']),
      dartVersion: stringFromValue(process['dart_version']),
      hostName: stringFromValue(process['host_name']),
      activeSseSubscriptions: nonNegativeIntFromValue(
        map['active_sse_subscriptions'],
        fallback: 0,
      ),
      recentErrors: stringKeyedMapListFromValue(
        map['recent_errors'],
        limit: webGatewayRuntimeRecentErrorLimit,
        fromEnd: true,
      ),
      logLevelBreakdown: _webGatewayStringIntMapFromValue(
        map['log_level_breakdown'],
      ),
      memoryLogCount: nonNegativeIntFromValue(
        map['memory_log_count'],
        fallback: 0,
      ),
      fileLogPendingWrites: nonNegativeIntFromValue(
        map['file_log_pending_writes'],
        fallback: 0,
      ),
      fileLogPendingBytes: nonNegativeIntFromValue(
        map['file_log_pending_bytes'],
        fallback: 0,
      ),
      fileLogDroppedWrites: nonNegativeIntFromValue(
        map['file_log_dropped_writes'],
        fallback: 0,
      ),
      sendPhaseBreakdown: _webGatewayStringIntMapFromValue(
        map['send_phase_breakdown'],
      ),
      allowedModelCount: nonNegativeIntFromValue(
        map['allowed_model_count'],
        fallback: 0,
      ),
      modelProviderCount: nonNegativeIntFromValue(
        map['model_provider_count'],
        fallback: 0,
      ),
      templateCount: nonNegativeIntFromValue(
        map['template_count'],
        fallback: 0,
      ),
      cronEnabledCount: nonNegativeIntFromValue(
        map['cron_enabled_count'],
        fallback: 0,
      ),
      cronTotalCount: nonNegativeIntFromValue(
        map['cron_total_count'],
        fallback: 0,
      ),
      memoryEntryCount: nonNegativeIntFromValue(
        map['memory_entry_count'],
        fallback: 0,
      ),
      mcpServerEnabledCount: nonNegativeIntFromValue(
        map['mcp_server_enabled_count'],
        fallback: 0,
      ),
      mcpServerTotalCount: nonNegativeIntFromValue(
        map['mcp_server_total_count'],
        fallback: 0,
      ),
      ipDistribution: ipDistribution,
      peerDistribution: peerDistribution.isEmpty
          ? _webGatewayLegacyPeerDistribution(ipDistribution)
          : peerDistribution,
      clientDistribution: _webGatewayStringIntMapFromValue(
        map['client_distribution'],
      ),
      requestDistribution: _webGatewayStringIntMapFromValue(
        map['request_distribution'],
      ),
      protocolDistribution: _webGatewayStringIntMapFromValue(
        map['protocol_distribution'],
      ),
      trafficSeries: _webGatewayTrafficSeriesFromValue(map['traffic_series']),
    );
  }
}

/// 请求延迟分位数快照，由近 256 次请求推导。
class WebGatewayLatencyStats {
  const WebGatewayLatencyStats({
    this.sampleCount = 0,
    this.avgMs = 0,
    this.p50Ms = 0,
    this.p95Ms = 0,
    this.p99Ms = 0,
    this.maxMs = 0,
  });

  final int sampleCount;
  final int avgMs;
  final int p50Ms;
  final int p95Ms;
  final int p99Ms;
  final int maxMs;

  Map<String, Object?> toJson() => <String, Object?>{
    'sample_count': sampleCount,
    'avg_ms': avgMs,
    'p50_ms': p50Ms,
    'p95_ms': p95Ms,
    'p99_ms': p99Ms,
    'max_ms': maxMs,
  };

  static WebGatewayLatencyStats fromJson(Object? raw) {
    final map = stringKeyedMapFromValue(raw);
    return WebGatewayLatencyStats(
      sampleCount: nonNegativeIntFromValue(map['sample_count'], fallback: 0),
      avgMs: nonNegativeIntFromValue(map['avg_ms'], fallback: 0),
      p50Ms: nonNegativeIntFromValue(map['p50_ms'], fallback: 0),
      p95Ms: nonNegativeIntFromValue(map['p95_ms'], fallback: 0),
      p99Ms: nonNegativeIntFromValue(map['p99_ms'], fallback: 0),
      maxMs: nonNegativeIntFromValue(map['max_ms'], fallback: 0),
    );
  }
}

/// 近期最慢一次请求的元信息。仅作为面板上的"故障线索"，不代表历史最慢。
class WebGatewayRecentSlowRequest {
  const WebGatewayRecentSlowRequest({
    required this.path,
    required this.method,
    required this.statusCode,
    required this.durationMs,
    required this.at,
  });

  final String path;
  final String method;
  final int statusCode;
  final int durationMs;
  final DateTime? at;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'method': method,
    'status_code': statusCode,
    'duration_ms': durationMs,
    'at': at?.toUtc().toIso8601String(),
  };

  static WebGatewayRecentSlowRequest fromJson(Object? raw) {
    final map = stringKeyedMapFromValue(raw);
    return WebGatewayRecentSlowRequest(
      path: stringFromValue(map['path']),
      method: stringFromValue(map['method'], fallback: 'GET'),
      statusCode: nonNegativeIntFromValue(map['status_code'], fallback: 0),
      durationMs: nonNegativeIntFromValue(map['duration_ms'], fallback: 0),
      at: utcDateTimeFromValue(map['at']),
    );
  }
}

bool webGatewayIsBlockedStatusCode(int statusCode) =>
    statusCode == HttpStatus.unauthorized ||
    statusCode == HttpStatus.forbidden ||
    statusCode == HttpStatus.tooManyRequests;

enum WebGatewayRequestOutcome { success, blocked, failed }

WebGatewayRequestOutcome webGatewayRequestOutcomeForStatus(int statusCode) {
  if (webGatewayIsBlockedStatusCode(statusCode)) {
    return WebGatewayRequestOutcome.blocked;
  }
  if (statusCode <= 0 || statusCode >= 400) {
    return WebGatewayRequestOutcome.failed;
  }
  return WebGatewayRequestOutcome.success;
}

bool webGatewayIsOpsSnapshotRequest(String method, String path) =>
    method.toUpperCase() == 'GET' && path == '/api/ops';

bool webGatewayShouldCollectRequestMetrics({
  required String method,
  required String path,
  required int statusCode,
}) =>
    !webGatewayIsOpsSnapshotRequest(method, path) ||
    statusCode != HttpStatus.ok;

String webGatewayFormatRemoteEndpoint(String address, int? port) {
  final host = address.trim();
  if (host.isEmpty) return 'unknown';
  if (!isValidPort(port)) return host;
  return '${_webGatewayFormatRemoteHost(host)}:$port';
}

String webGatewaySummarizeClientUserAgent({
  required String userAgent,
  String browserName = '',
  String browserVersion = '',
  String osName = '',
  String osVersion = '',
  String platform = '',
  String source = '',
}) {
  final ua = _webGatewayCompactMetricText(userAgent, maxCharacters: 512);
  var browser = _webGatewayMatchUaComponent(ua, _webGatewayBrowserUaRules);
  if (browser.isEmpty) {
    final name = _webGatewayCompactMetricText(browserName);
    final version = _webGatewayCompactMetricText(browserVersion);
    browser = <String>[
      name,
      version,
    ].where((item) => item.isNotEmpty).join(' ');
  }

  var os = _webGatewayMatchUaComponent(ua, _webGatewayOperatingSystemUaRules);
  os = os.replaceAll('_', '.');
  if (os.isEmpty) {
    final name = _webGatewayCompactMetricText(osName);
    final version = _webGatewayCompactMetricText(osVersion);
    os = <String>[name, version].where((item) => item.isNotEmpty).join(' ');
  }

  final fallback = _webGatewayCompactMetricText(
    platform.isNotEmpty ? platform : source,
  );
  final parts = <String>[
    if (browser.isNotEmpty) browser,
    if (os.isNotEmpty) os,
    if (browser.isEmpty && os.isEmpty && fallback.isNotEmpty) fallback,
  ];
  if (parts.isNotEmpty) return parts.join(' · ');
  return ua.isEmpty ? 'unknown' : ua;
}

String _webGatewayCompactMetricText(String value, {int maxCharacters = 48}) {
  final compact = value.trim().replaceAll(kInlineWhitespacePattern, ' ');
  return clipTextByCodeUnits(compact, maxCharacters, suffix: '');
}

Map<String, int> _webGatewayLegacyPeerDistribution(Map<String, int> values) {
  if (values.isEmpty) return const <String, int>{};
  return _webGatewayStringIntMapFromValue(<String, int>{
    for (final entry in values.entries)
      (entry.key == 'other'
              ? entry.key
              : '${_webGatewayFormatRemoteHost(entry.key)}:*'):
          entry.value,
  }, maxKeys: 128);
}

String _webGatewayFormatRemoteHost(String host) =>
    host.contains(':') && !host.startsWith('[') ? '[$host]' : host;

String _webGatewayMatchUaComponent(
  String userAgent,
  List<(String, RegExp)> rules,
) {
  for (final (name, pattern) in rules) {
    final match = pattern.firstMatch(userAgent);
    if (match == null) continue;
    final version = match.groupCount == 0
        ? ''
        : _webGatewayCompactMetricText(match.group(1) ?? '');
    return version.isEmpty ? name : '$name $version';
  }
  return '';
}

final List<(String, RegExp)> _webGatewayBrowserUaRules = <(String, RegExp)>[
  ('Edge', RegExp(r'(?:Edg|EdgA|EdgiOS)/([\d.]+)', caseSensitive: false)),
  ('Opera', RegExp(r'(?:OPR|Opera)/([\d.]+)', caseSensitive: false)),
  (
    'Samsung Internet',
    RegExp(r'SamsungBrowser/([\d.]+)', caseSensitive: false),
  ),
  ('Electron', RegExp(r'Electron/([\d.]+)', caseSensitive: false)),
  ('Headless Chrome', RegExp(r'HeadlessChrome/([\d.]+)', caseSensitive: false)),
  (
    'Chrome',
    RegExp(r'(?:Chrome|Chromium|CriOS)/([\d.]+)', caseSensitive: false),
  ),
  ('Firefox', RegExp(r'(?:Firefox|FxiOS)/([\d.]+)', caseSensitive: false)),
  ('Safari', RegExp(r'Version/([\d.]+).*Safari/', caseSensitive: false)),
  ('Postman', RegExp(r'PostmanRuntime/([\d.]+)', caseSensitive: false)),
  ('curl', RegExp(r'curl/([\d.]+)', caseSensitive: false)),
  ('Dart', RegExp(r'Dart/([\d.]+)', caseSensitive: false)),
  ('okhttp', RegExp(r'okhttp/([\d.]+)', caseSensitive: false)),
];
final List<(String, RegExp)> _webGatewayOperatingSystemUaRules =
    <(String, RegExp)>[
      (
        'iOS',
        RegExp(r'(?:iPhone|iPad|iPod).*OS ([\d_]+)', caseSensitive: false),
      ),
      ('Android', RegExp(r'Android[ /]([\d.]+)', caseSensitive: false)),
      ('macOS', RegExp(r'Mac OS X[ /]([\d_]+)', caseSensitive: false)),
      ('Windows NT', RegExp(r'Windows NT[ /]([\d.]+)', caseSensitive: false)),
      ('ChromeOS', RegExp(r'CrOS [^; )]+[ /]([\d.]+)', caseSensitive: false)),
      ('Linux', RegExp(r'(?:X11; )?Linux(?: [^;)]+)?', caseSensitive: false)),
    ];

String webGatewayNormalizeMetricRoute(String path) {
  if (path.isEmpty || path == '/') return '/';
  final segments = path.split('/').where((item) => item.isNotEmpty).toList();
  if (segments.isEmpty) return '/';
  if (segments.first == 'chunks' || segments.first == 'assets') {
    return '/${segments.first}/:asset';
  }
  if (segments.first == 'threads') {
    if (segments.length > 1 &&
        (segments[1] == 'chunks' || segments[1] == 'assets')) {
      return '/threads/${segments[1]}/:asset';
    }
    if (segments.length > 1 &&
        !const <String>{
          'app.js',
          'app.css',
          'favicon.ico',
          'manifest.webmanifest',
          'openhand_logo.png',
          'sw.js',
        }.contains(segments[1])) {
      return '/threads/:threadId';
    }
  }
  if (segments.length > 2 &&
      segments[0] == 'api' &&
      segments[1] == 'sessions') {
    segments[2] = ':sessionId';
    if (segments.length > 4 && segments[3] == 'messages') {
      segments[4] = ':messageId';
    } else if (segments.length > 4 && segments[3] == 'write-approvals') {
      segments[4] = ':approvalId';
    }
  }
  return '/${segments.join('/')}';
}

List<MapEntry<String, int>> webGatewayCompactDistribution(
  Map<String, int> values, {
  required String otherLabel,
  int limit = 5,
}) {
  if (limit <= 0) return const <MapEntry<String, int>>[];
  var overflow = 0;
  final sorted = values.entries.where((entry) {
    if (entry.value <= 0) return false;
    if (entry.key.trim().toLowerCase() == 'other' || entry.key == otherLabel) {
      overflow += entry.value;
      return false;
    }
    return true;
  }).toList()..sort((a, b) => b.value.compareTo(a.value));
  if (sorted.length + (overflow > 0 ? 1 : 0) <= limit) {
    return List<MapEntry<String, int>>.unmodifiable(<MapEntry<String, int>>[
      ...sorted,
      if (overflow > 0) MapEntry<String, int>(otherLabel, overflow),
    ]);
  }
  final visibleCount = math.max(0, limit - 1);
  return List<MapEntry<String, int>>.unmodifiable(<MapEntry<String, int>>[
    ...sorted.take(visibleCount),
    MapEntry<String, int>(
      otherLabel,
      overflow +
          sorted
              .skip(visibleCount)
              .fold<int>(0, (sum, entry) => sum + entry.value),
    ),
  ]);
}

Map<String, int> _webGatewayStringIntMapFromValue(
  Object? raw, {
  int maxKeys = 256,
}) {
  const maxKeyCharacters = 96;
  if (maxKeys < 2) return const <String, int>{};
  final source = stringKeyedMapFromValue(raw);
  if (source.isEmpty) return const <String, int>{};
  final result = <String, int>{};
  var overflow = 0;
  for (final entry in source.entries) {
    var key = entry.key.trim().replaceAll(kInlineWhitespacePattern, ' ');
    if (key.isEmpty) continue;
    final value = nonNegativeIntFromValue(entry.value, fallback: 0);
    if (key.length > maxKeyCharacters) {
      key = clipTextByCodeUnits(key, maxKeyCharacters, suffix: '');
    }
    if (result.containsKey(key) || result.length < maxKeys - 1) {
      result[key] = (result[key] ?? 0) + value;
    } else {
      overflow += value;
    }
  }
  if (overflow > 0) result['other'] = (result['other'] ?? 0) + overflow;
  return Map<String, int>.unmodifiable(result);
}

List<MapEntry<String, int>> _webGatewayTopRoutesFromValue(Object? raw) {
  final rows = stringKeyedMapListFromValue(
    raw,
    limit: webGatewayRuntimeTopRouteLimit,
  );
  if (rows.isEmpty) return const <MapEntry<String, int>>[];
  final routes = <MapEntry<String, int>>[];
  for (final row in rows) {
    final path = stringFromValue(row['path']);
    if (path.isEmpty) continue;
    routes.add(
      MapEntry(path, nonNegativeIntFromValue(row['count'], fallback: 0)),
    );
  }
  return List<MapEntry<String, int>>.unmodifiable(routes);
}

List<WebGatewayTrafficSample> _webGatewayTrafficSeriesFromValue(Object? raw) {
  final rows = stringKeyedMapListFromValue(
    raw,
    limit: webGatewayOpsTrafficWindowMinutes,
    fromEnd: true,
  );
  return List<WebGatewayTrafficSample>.unmodifiable(
    rows.map(WebGatewayTrafficSample.fromJson),
  );
}
