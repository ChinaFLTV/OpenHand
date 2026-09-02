part of '../ai_session_controller.dart';

class _CompressionWindowSelection {
  const _CompressionWindowSelection({
    required this.messagesToCompress,
    required this.discardedMessages,
    this.strategy = 'full',
    this.promptInputTokenLimit,
  });

  final List<AiSessionMessage> messagesToCompress;
  final List<AiSessionMessage> discardedMessages;
  final String strategy;
  final int? promptInputTokenLimit;
}

class _CompressionMessageGroup {
  const _CompressionMessageGroup({required this.messages});

  final List<AiSessionMessage> messages;

  int get characterCount =>
      messages.fold<int>(0, (sum, message) => sum + message.characterCount);

  int get textMessageCount => messages.where((message) {
    if (message.isDeleted || message.content.trim().isEmpty) {
      return false;
    }
    return message.role == AiSessionMessageRole.user ||
        message.role == AiSessionMessageRole.assistant;
  }).length;
}

class _RunningToolCallState {
  const _RunningToolCallState({
    required this.toolCall,
    required this.messageId,
    required this.executionSessionId,
    required this.startedAt,
  });

  final AiToolCall toolCall;
  final String messageId;
  final String executionSessionId;
  final DateTime startedAt;
}

class _ToolCallExecutionHeartbeat {
  _ToolCallExecutionHeartbeat({
    required this.interval,
    required this.elapsedMs,
    required this.onTick,
  });

  final Duration interval;
  final int Function() elapsedMs;
  final void Function(int elapsedMs) onTick;

  Timer? _timer;
  int? _lastEmittedBucket;

  void start() {
    if (_timer != null) {
      return;
    }
    _timer = startSafePeriodicTimer(interval, (_) => _emit());
  }

  void markExternalUpdate(int elapsedMs) {
    _lastEmittedBucket = _bucketFor(elapsedMs);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  void _emit() {
    final safeElapsedMs = math.max(0, elapsedMs());
    final bucket = _bucketFor(safeElapsedMs);
    if (_lastEmittedBucket == bucket) {
      return;
    }
    _lastEmittedBucket = bucket;
    onTick(safeElapsedMs);
  }

  int _bucketFor(int elapsedMs) {
    final intervalMs = math.max(1, interval.inMilliseconds);
    return elapsedMs ~/ intervalMs;
  }
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
