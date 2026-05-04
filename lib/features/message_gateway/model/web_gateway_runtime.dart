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
    this.surface = '#FFFBFE',
    this.surfaceContainer = '#F3EDF7',
    this.onSurface = '#1D1B20',
    this.onSurfaceVariant = '#49454F',
    this.outline = '#CAC4D0',
    this.error = '#B3261E',
    this.brightness = 'light',
  });

  final String primary;
  final String onPrimary;
  final String surface;
  final String surfaceContainer;
  final String onSurface;
  final String onSurfaceVariant;
  final String outline;
  final String error;
  final String brightness;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'primary': primary,
      'on_primary': onPrimary,
      'surface': surface,
      'surface_container': surfaceContainer,
      'on_surface': onSurface,
      'on_surface_variant': onSurfaceVariant,
      'outline': outline,
      'error': error,
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

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'state': state.name,
      'started_at': startedAt?.toUtc().toIso8601String(),
      'uptime_ms': uptimeMs,
      'bound_url': boundUrl,
      'accessible_urls': accessibleUrls,
      'active_requests': activeRequests,
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
      },
      'open_session_count': openSessionCount,
      'last_error': lastError,
    };
  }
}
