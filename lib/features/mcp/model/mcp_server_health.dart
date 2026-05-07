enum McpServerHealthStatus { idle, checking, healthy, unhealthy }

/// 单次探测的最简记录，用于服务卡片侧抽屉展示「最近探测历史」。
class McpHealthProbeRecord {
  const McpHealthProbeRecord({
    required this.status,
    required this.timestamp,
    this.latencyMs,
    this.errorMessage,
  });

  final McpServerHealthStatus status;
  final DateTime timestamp;
  final int? latencyMs;
  final String? errorMessage;
}

class McpServerHealth {
  const McpServerHealth({
    this.status = McpServerHealthStatus.idle,
    this.errorMessage,
    this.lastCheckedAt,
    this.latencyMs,
    this.consecutiveFailures = 0,
    this.lastSuccessAt,
    this.recentProbes = const <McpHealthProbeRecord>[],
  });

  final McpServerHealthStatus status;
  final String? errorMessage;
  final DateTime? lastCheckedAt;

  /// 最近一次健康探测的 RTT，单位毫秒；仅在 [status] 为 [McpServerHealthStatus.healthy] 时有意义。
  final int? latencyMs;

  /// 连续失败次数；探测成功立即归零。≥3 时 UI 会显示「需要处理」警告胶囊。
  final int consecutiveFailures;

  /// 最近一次探测成功的时间（UTC）。
  final DateTime? lastSuccessAt;

  /// 最近若干次探测记录（按时间倒序，最多保留 30 条），驱动「最近探测历史」抽屉与趋势迷你图。
  final List<McpHealthProbeRecord> recentProbes;

  bool get isChecking => status == McpServerHealthStatus.checking;
  bool get isHealthy => status == McpServerHealthStatus.healthy;
  bool get hasError =>
      status == McpServerHealthStatus.unhealthy &&
      (errorMessage?.trim().isNotEmpty ?? false);

  /// 是否需要在 UI 上显眼地提醒用户介入处理（连续失败 >= 3 次）。
  bool get needsAttention => consecutiveFailures >= 3;

  McpServerHealth copyWith({
    McpServerHealthStatus? status,
    String? errorMessage,
    bool clearErrorMessage = false,
    DateTime? lastCheckedAt,
    int? latencyMs,
    bool clearLatency = false,
    int? consecutiveFailures,
    DateTime? lastSuccessAt,
    List<McpHealthProbeRecord>? recentProbes,
  }) {
    return McpServerHealth(
      status: status ?? this.status,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      latencyMs: clearLatency ? null : latencyMs ?? this.latencyMs,
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
      lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
      recentProbes: recentProbes ?? this.recentProbes,
    );
  }
}
