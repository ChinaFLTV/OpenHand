import 'dart:convert';
import 'dart:io';

/// Runtime types for the Web 通用消息平台 service.
///
/// 这些类原先内联在 [service/web_message_platform_service.dart]，Stage 1 抽出
/// 到独立模型文件以便 Stage 2/3 拆分基础设施时复用，同时保持 view 的公共 API
/// 表面不变。service 仍会 re-export 这些类型，view 的现有 import 无需调整。

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

/// 日志级别。`telemetry` 用于结构化遥测事件，与普通日志区分。
enum WebGatewayLogLevel { info, success, warn, error, debug, telemetry }

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
    this.maxConcurrentRequests = 0,
    this.activeRequestRatio = 0,
    required this.totalRequests,
    required this.totalErrors,
    required this.totalBytesIn,
    required this.totalBytesOut,
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
    this.dartVersion = '',
    this.hostName = '',
    this.activeSseSubscriptions = 0,
    this.recentErrors = const <Map<String, Object?>>[],
    this.logLevelBreakdown = const <String, int>{},
    this.memoryLogCount = 0,
    this.sendPhaseBreakdown = const <String, int>{},
    this.allowedModelCount = 0,
    this.modelProviderCount = 0,
    this.templateCount = 0,
    this.cronEnabledCount = 0,
    this.cronTotalCount = 0,
    this.memoryEntryCount = 0,
    this.mcpServerEnabledCount = 0,
    this.mcpServerTotalCount = 0,
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
  final int maxConcurrentRequests;
  final double activeRequestRatio;
  final int totalRequests;
  final int totalErrors;
  final int totalBytesIn;
  final int totalBytesOut;
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

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'state': state.name,
      'started_at': startedAt?.toUtc().toIso8601String(),
      'uptime_ms': uptimeMs,
      'bound_url': boundUrl,
      'accessible_urls': accessibleUrls,
      'active_requests': activeRequests,
      'max_concurrent_requests': maxConcurrentRequests,
      'active_request_ratio': activeRequestRatio,
      'total_requests': totalRequests,
      'total_errors': totalErrors,
      'total_bytes_in': totalBytesIn,
      'total_bytes_out': totalBytesOut,
      'crash_count': crashCount,
      'restart_count': restartCount,
      'process': <String, Object?>{
        'pid': pid,
        'current_rss_bytes': currentRssBytes,
        'max_rss_bytes': maxRssBytes,
        'cpu_percent': cpuPercent,
        'thread_count': threadCount,
        'file_handle_count': fileHandleCount,
        'swap_bytes': swapBytes,
        'disk_log_bytes': logBytes,
        'platform': Platform.operatingSystem,
        'platform_version': Platform.operatingSystemVersion,
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
      'send_phase_breakdown': sendPhaseBreakdown,
      'allowed_model_count': allowedModelCount,
      'model_provider_count': modelProviderCount,
      'template_count': templateCount,
      'cron_enabled_count': cronEnabledCount,
      'cron_total_count': cronTotalCount,
      'memory_entry_count': memoryEntryCount,
      'mcp_server_enabled_count': mcpServerEnabledCount,
      'mcp_server_total_count': mcpServerTotalCount,
    };
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
}
