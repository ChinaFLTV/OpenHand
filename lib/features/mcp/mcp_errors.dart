import 'dart:io';

import '../../shared/util/user_failure_message.dart';
import 'service/mcp_tool_discovery_exception.dart';

String mcpFailureMessage(Object error, {required String fallback}) {
  return userFailureMessage(
    error,
    fallback: fallback,
    detailResolver: (error) => switch (error) {
      McpToolDiscoveryException(:final message) => message,
      ProcessException(:final message) => message,
      _ => null,
    },
  );
}
