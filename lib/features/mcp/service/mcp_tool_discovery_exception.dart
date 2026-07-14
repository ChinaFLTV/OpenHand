const String kMcpStdioSessionClosingMessage =
    'Tool scan stopped because the stdio MCP session is closing.';

bool isExpectedMcpToolDiscoveryLifecycleError(Object error) {
  if (error is McpToolDiscoveryException) {
    return error.isExpectedLifecycleCancellation;
  }
  final message = error.toString();
  return message.contains(kMcpStdioSessionClosingMessage) ||
      (message.contains('Stdio MCP server "') &&
          message.contains(' is stopping.'));
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
