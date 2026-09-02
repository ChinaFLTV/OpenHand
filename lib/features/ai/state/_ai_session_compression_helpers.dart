part of '../ai_session_controller.dart';

const int _minRetainedCompressionTextMessages = 5;
const int _minCompressionPromptRetryMessages = 1;
const List<double> _compressionPromptTooLongDropRatios = <double>[
  0.20,
  0.35,
  0.50,
  0.65,
];
({
  List<AiSessionMessage> discardedMessages,
  List<AiSessionMessage> messagesToCompress,
})?
retryCompressionWindowAfterPromptTooLong(
  List<AiSessionMessage> messages, {
  int attempt = 0,
}) {
  if (messages.length <= _minCompressionPromptRetryMessages) {
    return null;
  }
  final dropRatio =
      _compressionPromptTooLongDropRatios[attempt
          .clamp(0, _compressionPromptTooLongDropRatios.length - 1)
          .toInt()];
  final groups = _buildCompressionMessageGroups(messages);
  if (groups.length > 1) {
    final dropGroupCount = math.min(
      groups.length - 1,
      math.max(1, (groups.length * dropRatio).ceil()),
    );
    return (
      discardedMessages: _flattenCompressionGroups(groups.take(dropGroupCount)),
      messagesToCompress: _flattenCompressionGroups(
        groups.skip(dropGroupCount),
      ),
    );
  }

  // 单个分组超限时优先避免上下文溢出，并保留最新消息作为恢复锚点。
  final dropMessageCount = math.min(
    messages.length - _minCompressionPromptRetryMessages,
    math.max(1, (messages.length * dropRatio).ceil()),
  );
  return (
    discardedMessages: messages.take(dropMessageCount).toList(growable: false),
    messagesToCompress: messages.skip(dropMessageCount).toList(growable: false),
  );
}

String normalizeCompressionCheckpointSummary(String summary) {
  final raw = summary.trim();
  if (raw.isEmpty) {
    return '';
  }
  var normalized = raw.replaceAll(
    RegExp(r'<analysis\b[^>]*>[\s\S]*?</analysis>', caseSensitive: false),
    '',
  );
  final summaryMatch = RegExp(
    r'<summary\b[^>]*>([\s\S]*?)</summary>',
    caseSensitive: false,
  ).firstMatch(normalized);
  if (summaryMatch != null) {
    normalized = (summaryMatch.group(1) ?? '').trim();
  } else {
    normalized = normalized.replaceAll(
      RegExp(r'</?summary\b[^>]*>', caseSensitive: false),
      '',
    );
  }
  normalized = normalized.replaceAll(kExcessiveNewlinesPattern, '\n\n').trim();
  return normalized.isEmpty ? raw : normalized;
}

List<_CompressionMessageGroup> _buildCompressionMessageGroups(
  List<AiSessionMessage> messages,
) {
  final groups = <_CompressionMessageGroup>[];
  var current = <AiSessionMessage>[];
  for (final message in messages) {
    final startsAssistantRound = _startsCompressionAssistantRound(
      message,
      current,
    );
    if (startsAssistantRound && current.isNotEmpty) {
      groups.add(_CompressionMessageGroup(messages: current));
      current = <AiSessionMessage>[message];
    } else {
      current.add(message);
    }
  }
  if (current.isNotEmpty) {
    groups.add(_CompressionMessageGroup(messages: current));
  }
  return groups;
}

bool _startsCompressionAssistantRound(
  AiSessionMessage message,
  List<AiSessionMessage> current,
) {
  if (message.kind == AiSessionMessageKind.assistant) {
    return true;
  }
  if (message.kind != AiSessionMessageKind.toolCall || current.isEmpty) {
    return false;
  }
  final previousKind = current.last.kind;
  return previousKind != AiSessionMessageKind.assistant &&
      previousKind != AiSessionMessageKind.reasoning &&
      previousKind != AiSessionMessageKind.toolCall;
}

List<AiSessionMessage> _flattenCompressionGroups(
  Iterable<_CompressionMessageGroup> groups,
) {
  return <AiSessionMessage>[for (final group in groups) ...group.messages];
}

List<_CompressionMessageGroup> _selectRetainedCompressionGroups(
  List<_CompressionMessageGroup> activeConversationGroups,
  int threshold,
) {
  final retainedGroups = <_CompressionMessageGroup>[];
  var retainedCharacterCount = 0;
  var retainedTextMessageCount = 0;
  final retainedHardCharacterLimit = math.max(threshold, threshold * 2);
  for (var index = activeConversationGroups.length - 1; index >= 0; index--) {
    final group = activeConversationGroups[index];
    final nextCharacterCount = retainedCharacterCount + group.characterCount;
    final needsMoreTextAnchors =
        retainedTextMessageCount < _minRetainedCompressionTextMessages;
    if (retainedGroups.isNotEmpty &&
        nextCharacterCount > threshold &&
        (!needsMoreTextAnchors ||
            nextCharacterCount > retainedHardCharacterLimit)) {
      break;
    }
    retainedGroups.insert(0, group);
    retainedCharacterCount = nextCharacterCount;
    retainedTextMessageCount += group.textMessageCount;
  }
  return retainedGroups;
}
