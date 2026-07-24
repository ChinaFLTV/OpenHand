const String kMcpStdioSessionClosingMessage =
    'Tool scan stopped because the stdio MCP session is closing.';

bool isExpectedMcpToolDiscoveryLifecycleError(Object error) {
  return error is McpToolDiscoveryException &&
      error.isExpectedLifecycleCancellation;
}

class McpToolDiscoveryException implements Exception {
  const McpToolDiscoveryException(
    this.message, {
    this.isExpectedLifecycleCancellation = false,
  });

  final String message;
  final bool isExpectedLifecycleCancellation;

  @override
  String toString() => message;
}
