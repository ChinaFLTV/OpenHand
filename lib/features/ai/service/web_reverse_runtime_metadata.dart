bool webReverseRuntimeBoolTrue(Object? raw) {
  if (raw is bool) return raw;
  final normalized = '${raw ?? ''}'.trim().toLowerCase();
  return normalized == 'true' || normalized == '1' || normalized == 'yes';
}

bool webReverseRuntimeBoolFalse(Object? raw) {
  if (raw is bool) return !raw;
  final normalized = '${raw ?? ''}'.trim().toLowerCase();
  return normalized == 'false' || normalized == '0' || normalized == 'no';
}

bool webReverseCdpRuntimeHasLiveLocator(Map<Object?, Object?> value) {
  bool hasText(Object? raw) => raw is String && raw.trim().isNotEmpty;
  bool hasPort(Object? raw) {
    if (raw is num) return raw.toInt() > 0;
    final parsed = int.tryParse('${raw ?? ''}'.trim());
    return parsed != null && parsed > 0;
  }

  return hasPort(value['cdp_port']) ||
      hasText(value['cdp_http_endpoint']) ||
      hasText(value['json_version_url']) ||
      hasText(value['json_list_url']);
}

Map<String, Object?>? webReverseRuntimeObjectMap(Object? raw) {
  if (raw is Map<String, Object?>) return raw;
  if (raw is! Map) return null;
  return <String, Object?>{
    for (final entry in raw.entries) '${entry.key}': entry.value,
  };
}

bool webReverseCdpRuntimeIsLive(Object? raw) {
  final value = webReverseRuntimeObjectMap(raw);
  if (value == null) return false;
  return webReverseRuntimeBoolTrue(value['browser_alive']) &&
      webReverseCdpRuntimeHasLiveLocator(value);
}

int? webReverseRuntimeInt(Object? raw) {
  if (raw is num) return raw.toInt();
  final value = '${raw ?? ''}'.trim();
  if (value.isEmpty) return null;
  return int.tryParse(value);
}

class WebReverseCdpMcpRuntimeStatus {
  const WebReverseCdpMcpRuntimeStatus({
    required this.rawStatus,
    required this.toolCount,
    required this.liveActionsCallable,
    required this.browserAlive,
    this.port,
    this.serverName = '',
    this.message = '',
    this.errorMessage = '',
    this.warningMessage = '',
  });

  factory WebReverseCdpMcpRuntimeStatus.fromRuntime(
    Object? runtime, {
    bool? controllerBrowserAlive,
    int? controllerPort,
  }) {
    final runtimeMap = webReverseRuntimeObjectMap(runtime);
    final bridge = webReverseRuntimeObjectMap(runtimeMap?['cdp_mcp_bridge']);
    final controllerSaysOffline = controllerBrowserAlive == false;
    final bridgePort = webReverseRuntimeInt(bridge?['cdp_port']);
    final runtimePort = webReverseRuntimeInt(runtimeMap?['cdp_port']);
    final port = controllerSaysOffline
        ? null
        : bridgePort != null && bridgePort > 0
        ? bridgePort
        : runtimePort != null && runtimePort > 0
        ? runtimePort
        : controllerPort;
    final browserAlive =
        !controllerSaysOffline &&
        (controllerBrowserAlive == true ||
            webReverseRuntimeBoolTrue(bridge?['browser_alive']) ||
            webReverseCdpRuntimeIsLive(runtimeMap));

    return WebReverseCdpMcpRuntimeStatus(
      rawStatus: '${bridge?['status'] ?? ''}'.trim(),
      toolCount: webReverseRuntimeInt(bridge?['tool_count']) ?? 0,
      liveActionsCallable:
          !controllerSaysOffline &&
          webReverseRuntimeBoolTrue(bridge?['live_actions_callable']),
      browserAlive: browserAlive,
      port: port,
      serverName: '${bridge?['server_name'] ?? ''}'.trim(),
      message: '${bridge?['message'] ?? ''}'.trim(),
      errorMessage: '${bridge?['error_message'] ?? ''}'.trim(),
      warningMessage: '${bridge?['warning_message'] ?? ''}'.trim(),
    );
  }

  final String rawStatus;
  final int toolCount;
  final bool liveActionsCallable;
  final bool browserAlive;
  final int? port;
  final String serverName;
  final String message;
  final String errorMessage;
  final String warningMessage;

  bool get ready {
    return browserAlive &&
        toolCount > 0 &&
        (liveActionsCallable || rawStatus == 'ready');
  }
}

Object? webReverseCurrentCdpRuntimeMetadata(Map<Object?, Object?> metadata) {
  final currentRuntime = metadata['web_reverse_cdp_runtime'];
  if (currentRuntime != null) {
    return currentRuntime;
  }

  final runtime = metadata['web_reverse_runtime'];
  if (runtime is Map) {
    return runtime['cdp_runtime'];
  }
  return null;
}
