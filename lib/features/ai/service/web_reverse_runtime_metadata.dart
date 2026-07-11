import '../../../shared/util/input_value_parsing.dart';

bool webReverseRuntimeBoolTrue(Object? raw) {
  return boolFromValue(raw);
}

bool webReverseRuntimeBoolFalse(Object? raw) {
  return !boolFromValue(raw, defaultValue: true);
}

bool webReverseCdpRuntimeHasLiveLocator(Map<Object?, Object?> value) {
  bool hasText(Object? raw) => raw is String && nullIfBlank(raw) != null;
  bool hasPort(Object? raw) => optionalPositiveIntFromValue(raw) != null;

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
    final bridgePort = optionalPositiveIntFromValue(bridge?['cdp_port']);
    final runtimePort = optionalPositiveIntFromValue(runtimeMap?['cdp_port']);
    final controllerPositivePort = controllerPort != null && controllerPort > 0
        ? controllerPort
        : null;
    final port = controllerSaysOffline
        ? null
        : bridgePort ?? runtimePort ?? controllerPositivePort;
    final browserAlive =
        !controllerSaysOffline &&
        (controllerBrowserAlive == true ||
            webReverseRuntimeBoolTrue(bridge?['browser_alive']) ||
            webReverseCdpRuntimeIsLive(runtimeMap));

    return WebReverseCdpMcpRuntimeStatus(
      rawStatus: '${bridge?['status'] ?? ''}'.trim(),
      toolCount: nonNegativeIntFromValue(bridge?['tool_count'], fallback: 0),
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
