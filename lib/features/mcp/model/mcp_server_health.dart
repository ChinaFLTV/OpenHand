enum McpServerHealthStatus { idle, checking, healthy, unhealthy }

class McpServerHealth {
  const McpServerHealth({
    this.status = McpServerHealthStatus.idle,
    this.errorMessage,
    this.lastCheckedAt,
  });

  final McpServerHealthStatus status;
  final String? errorMessage;
  final DateTime? lastCheckedAt;

  bool get isChecking => status == McpServerHealthStatus.checking;
  bool get isHealthy => status == McpServerHealthStatus.healthy;
  bool get hasError =>
      status == McpServerHealthStatus.unhealthy &&
      (errorMessage?.trim().isNotEmpty ?? false);

  McpServerHealth copyWith({
    McpServerHealthStatus? status,
    String? errorMessage,
    bool clearErrorMessage = false,
    DateTime? lastCheckedAt,
  }) {
    return McpServerHealth(
      status: status ?? this.status,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
    );
  }
}
