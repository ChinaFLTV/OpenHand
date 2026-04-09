part of 'ai_session_controller.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helper data classes extracted from ai_session_controller.dart.
// ─────────────────────────────────────────────────────────────────────────────

class _CompressionWindowSelection {
  const _CompressionWindowSelection({
    required this.messagesToCompress,
    required this.discardedMessages,
  });

  final List<AiSessionMessage> messagesToCompress;
  final List<AiSessionMessage> discardedMessages;
}

class _ClaudeCodeDocsTarget {
  const _ClaudeCodeDocsTarget({required this.url, required this.label});

  final String url;
  final String label;
}

class _ScoredClaudeCodeDocsRoute {
  const _ScoredClaudeCodeDocsRoute({
    required this.route,
    required this.score,
    required this.priority,
  });

  final String route;
  final int score;
  final int priority;
}

class _RunningToolCallState {
  const _RunningToolCallState({
    required this.toolCall,
    required this.messageId,
    required this.executionSessionId,
  });

  final AiToolCall toolCall;
  final String messageId;
  final String executionSessionId;
}

class _PreparedUserTurn {
  const _PreparedUserTurn({
    required this.session,
    required this.userMessage,
    required this.shouldGenerateTitle,
    required this.importedAttachments,
  });

  final AiSession session;
  final AiSessionMessage userMessage;
  final bool shouldGenerateTitle;
  final bool importedAttachments;
}
