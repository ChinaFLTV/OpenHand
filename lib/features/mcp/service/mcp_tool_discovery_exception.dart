const String kMcpStdioSessionClosingMessage = 'stdio MCP 会话正在关闭，工具扫描已停止。';

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
