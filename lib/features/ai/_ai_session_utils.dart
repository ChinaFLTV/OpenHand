part of 'ai_session_controller.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Pure utility functions extracted from AiSessionController.
// These do not reference any instance state.
// ─────────────────────────────────────────────────────────────────────────────

bool _hasIncompleteTodoItems(List<AiSessionTodoItem> todoItems) {
  return todoItems.any(
    (item) => item.status.trim().toLowerCase() != 'completed',
  );
}

bool _hasPlanExecutionContext(AiSession session) {
  return session.todoItems.isNotEmpty ||
      (session.pendingPlan ?? '').trim().isNotEmpty ||
      session.latestActivePlanRecord != null;
}

String _normalizeToolName(String toolName) {
  return toolName.trim().toLowerCase();
}

bool _hasCompletedTodoItemsOnly(List<AiSessionTodoItem> todoItems) {
  return todoItems.isNotEmpty &&
      todoItems.every(
        (item) => item.status.trim().toLowerCase() == 'completed',
      );
}

bool _hasFailedTodoItems(List<AiSessionTodoItem> todoItems) {
  return todoItems.any((item) {
    final status = item.status.trim().toLowerCase();
    return status == 'failed' || status == 'blocked' || status == 'cancelled';
  });
}

bool _isFailureTrackedPlanToolStatus(String status) {
  return switch (status) {
    'failed' ||
    'cancelled' ||
    'denied' ||
    'rejected' ||
    'timed_out' ||
    'invalid_arguments' => true,
    _ => false,
  };
}

bool _isTrackedPlanRelevantErrorStage(String stage) {
  return switch (stage.trim().toLowerCase()) {
    'chat_request' ||
    'chat_continuation_request' ||
    'chat_stream' ||
    'follow_up_request' ||
    'tool_execution' ||
    'tool_loop' => true,
    _ => false,
  };
}

bool _isRetryableAutoTitleError(Object error) {
  final message = '$error';
  return message.contains('Request timed out.') ||
      message.contains('429') ||
      message.contains('rate limit') ||
      message.contains('Rate limit') ||
      message.contains('503') ||
      message.contains('502') ||
      message.contains('overloaded') ||
      message.contains('Overloaded') ||
      message.contains('temporarily') ||
      message.contains('RESOURCE_EXHAUSTED') ||
      message.contains('Too Many Requests') ||
      message.contains('Connection reset') ||
      message.contains('Connection closed') ||
      message.contains('Network error');
}

bool _environmentEquals(
  AiSessionEnvironment left,
  AiSessionEnvironment right,
) {
  return left.localeTag == right.localeTag &&
      left.platform == right.platform &&
      left.appVersion == right.appVersion &&
      left.appBuildNumber == right.appBuildNumber &&
      left.applicationDirectory == right.applicationDirectory &&
      left.homeDirectory == right.homeDirectory &&
      left.settingsFilePath == right.settingsFilePath &&
      left.skillsStoragePath == right.skillsStoragePath &&
      left.mcpServersFilePath == right.mcpServersFilePath &&
      left.userMemoryFilePath == right.userMemoryFilePath &&
      left.sessionsDirectoryPath == right.sessionsDirectoryPath &&
      left.compressionThresholdChars == right.compressionThresholdChars;
}

bool _stringListsEqual(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

String _toolCallLimitWarningMessage({
  required AiSessionRuntimeContext runtimeContext,
  required int toolCallCount,
  required int limit,
}) {
  if (_prefersChineseLocale(runtimeContext.localeTag)) {
    return '本轮对话中的工具调用次数已达到 $toolCallCount 次，超过当前设置的上限 $limit 次。OpenHand 已发送警告并安全终止本轮响应。';
  }
  return 'This response reached $toolCallCount tool calls, which exceeds the configured limit of $limit. OpenHand posted a warning and stopped the round for safety.';
}

bool _prefersChineseLocale(String localeTag) {
  return localeTag.trim().toLowerCase().startsWith('zh');
}

String _deriveSessionTitle(
  AiSession session,
  AiSessionMessage latestUserMessage,
) {
  final hasExistingUserMessages = session.messages.any(
    (message) =>
        !message.isDeleted && message.kind == AiSessionMessageKind.user,
  );
  if (hasExistingUserMessages &&
      session.title.trim().isNotEmpty &&
      session.title.trim() != session.templateName &&
      session.autoTitleSourceMessageId != latestUserMessage.id &&
      !session.isTitleManuallyEdited) {
    return session.title;
  }
  final derivedTitle = _deriveReadableTitleFromContent(
    latestUserMessage.content,
    maxCharacters: AiSessionController._fallbackTitleMaxCharacters,
  );
  return derivedTitle.isEmpty ? session.title : derivedTitle;
}

String _sanitizeGeneratedTitle(String value) {
  var normalized = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  normalized = normalized.replaceAll(RegExp(r'[\n]+'), ' ');
  normalized = normalized.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\([^)]+\)'),
    (match) => match.group(1) ?? '',
  );
  normalized = normalized.replaceFirst(RegExp(r'^\s*\d+[.)、:：-]\s*'), '');
  normalized = normalized.replaceFirst(RegExp(r'^\s*[-*+#>]+\s*'), '');
  normalized = _stripTitleWrappers(normalized);
  final collapsed = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.isEmpty) {
    return '';
  }
  return _trimTitleToMaxCharacters(
    _stripTitleWrappers(collapsed),
    AiSessionController._generatedTitleMaxCharacters,
  );
}

bool _isMeaningfulAutoTitle(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  final normalized = _normalizeAutoTitleForComparison(trimmed);
  if (normalized.isEmpty ||
      normalized ==
          _normalizeAutoTitleForComparison(AiSessionController._defaultNewSessionTitle) ||
      AiSessionController._genericAutoTitleCandidates.contains(normalized)) {
    return false;
  }
  final hasCjk = RegExp(r'[\u4E00-\u9FFF]').hasMatch(trimmed);
  if (hasCjk) {
    return normalized.characters.length >= AiSessionController._minimumMeaningfulTitleCharacters;
  }
  final words = trimmed
      .split(RegExp(r'\s+'))
      .where((item) => item.trim().isNotEmpty)
      .length;
  if (words >= AiSessionController._minimumMeaningfulLatinTitleWords) {
    return true;
  }
  final latinOrDigitCount = normalized.replaceAll(RegExp(r'[^a-z0-9]'), '');
  return latinOrDigitCount.length >= 6;
}

String _deriveReadableTitleFromContent(
  String value, {
  required int maxCharacters,
}) {
  final normalized = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normalized
      .split('\n')
      .map(_sanitizeTitleSourceLine)
      .where((item) => item.isNotEmpty)
      .take(3)
      .toList(growable: false);
  if (lines.isEmpty) {
    return '';
  }
  final candidates = <String>[
    for (final line in lines) ..._splitTitleSourceLine(line),
    lines.join(' '),
    lines.first,
  ];
  for (final candidate in candidates) {
    final trimmed = _trimTitleToMaxCharacters(candidate, maxCharacters);
    if (_isMeaningfulAutoTitle(trimmed)) {
      return trimmed;
    }
  }
  return _trimTitleToMaxCharacters(lines.first, maxCharacters);
}

String _sanitizeTitleSourceLine(String value) {
  var normalized = value.trim();
  if (normalized.isEmpty) {
    return '';
  }
  normalized = normalized.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\([^)]+\)'),
    (match) => match.group(1) ?? '',
  );
  normalized = normalized.replaceAll(RegExp(r'`{1,3}'), '');
  normalized = normalized.replaceAll(RegExp(r'[*_~]'), '');
  normalized = normalized.replaceFirst(RegExp(r'^\s*[#>]+\s*'), '');
  normalized = normalized.replaceFirst(RegExp(r'^\s*[-+*]\s+'), '');
  normalized = normalized.replaceFirst(RegExp(r'^\s*\d+[.)、]\s*'), '');
  normalized = normalized.replaceFirst(
    RegExp(r'^\s*(第一|第二|第三|第四|第五|首先|其次|然后|最后)[，,:：\s-]*'),
    '',
  );
  normalized = normalized.replaceFirst(
    RegExp(r'^\s*(有几处地方需要改进优化|有几个地方需要改进优化)[，,:：\s-]*'),
    '',
  );
  normalized = _stripTitleLeadIn(normalized);
  normalized = _stripTitleWrappers(normalized);
  return normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _stripTitleLeadIn(String value) {
  var normalized = value.trim();
  const chinesePrefixes = <String>[
    '请帮我',
    '帮我',
    '请你',
    '麻烦你',
    '麻烦帮我',
    '请问',
    '需要你',
    '我想请你',
    '我想',
    '我需要',
    '帮忙',
    '求助',
  ];
  for (final prefix in chinesePrefixes) {
    if (normalized.startsWith(prefix) &&
        normalized.characters.length > prefix.characters.length) {
      normalized = normalized.substring(prefix.length).trimLeft();
      break;
    }
  }
  final englishPrefixes = <RegExp>[
    RegExp(r'^(please|plz)\s+', caseSensitive: false),
    RegExp(r'^(can|could|would)\s+you\s+', caseSensitive: false),
    RegExp(r'^(help\s+me)\s+', caseSensitive: false),
    RegExp(r'^(i\s+need\s+to)\s+', caseSensitive: false),
    RegExp(r'^(i\s+want\s+to)\s+', caseSensitive: false),
    RegExp(r'^(need\s+to)\s+', caseSensitive: false),
  ];
  for (final pattern in englishPrefixes) {
    normalized = normalized.replaceFirst(pattern, '').trimLeft();
  }
  return normalized;
}

String _stripTitleWrappers(String value) {
  var normalized = value.trim();
  while (normalized.isNotEmpty) {
    final stripped = normalized
        .replaceFirst(RegExp(r'^[`*_#~>"“”‘’《》〈〉【】\[\]\(\)\-:：]+'), '')
        .replaceFirst(RegExp(r'[`*_#~<>"“”‘’《》〈〉【】\[\]\(\)\-:：]+$'), '')
        .trim();
    if (stripped == normalized) {
      return stripped;
    }
    normalized = stripped;
  }
  return normalized;
}

String _trimTitleToMaxCharacters(String value, int maxCharacters) {
  final collapsed = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.isEmpty) {
    return '';
  }
  final characters = collapsed.characters;
  if (characters.length <= maxCharacters) {
    return collapsed;
  }
  final trimmed = characters.take(maxCharacters).toString().trimRight();
  return trimmed.replaceFirst(RegExp(r'[\s,:：，。；、-]+$'), '').trimRight();
}

String _normalizeAutoTitleForComparison(String value) {
  return _stripTitleWrappers(value).trim().toLowerCase().replaceAll(
    RegExp("[\\s\\.,!?\\-_:;'\"“”‘’《》〈〉【】\\[\\]\\(\\)，。！？：；、]+"),
    '',
  );
}

String _sanitizeVisibleModelContent(String value) {
  final normalized = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normalized.split('\n');
  var cursor = 0;
  while (cursor < lines.length && lines[cursor].trim().isEmpty) {
    cursor += 1;
  }
  if (cursor >= lines.length ||
      !AiSessionController._internalPromptLeakHeaders.contains(lines[cursor].trim())) {
    return sanitizeVisibleDsmlContent(normalized);
  }
  while (cursor < lines.length) {
    final trimmed = lines[cursor].trim();
    if (trimmed.isEmpty || AiSessionController._internalPromptLeakHeaders.contains(trimmed)) {
      cursor += 1;
      continue;
    }
    break;
  }
  final sanitized = lines.skip(cursor).join('\n').trimLeft();
  if (sanitized.length == normalized.length) {
    return sanitizeVisibleDsmlContent(normalized);
  }
  return sanitizeVisibleDsmlContent(sanitized);
}

String _renderToolCallContent({
  required String name,
  required String arguments,
}) {
  final normalizedName = name.trim().isEmpty ? 'tool' : name.trim();
  final prettyArguments = _prettyToolArguments(arguments);
  return '**$normalizedName**\n\n```json\n$prettyArguments\n```';
}

String _prettyToolArguments(String arguments) {
  final trimmed = arguments.trim();
  if (trimmed.isEmpty) {
    return '{}';
  }
  try {
    final decoded = jsonDecode(trimmed);
    return const JsonEncoder.withIndent('  ').convert(decoded);
  } catch (_) {
    return trimmed;
  }
}

bool _isTerminalToolExecutionStatus(String status) {
  return switch (status) {
    'success' ||
    'failed' ||
    'cancelled' ||
    'denied' ||
    'rejected' ||
    'timed_out' ||
    'invalid_arguments' => true,
    _ => false,
  };
}

String _cancelledToolExecutionResultText({
  required String command,
  required String workingDirectory,
  required int elapsedMs,
  required bool hadStarted,
}) {
  final resolvedCommand = command.isEmpty ? 'tool_call' : command;
  final buffer = StringBuffer()
    ..writeln('status: cancelled')
    ..writeln('command: $resolvedCommand')
    ..writeln('working_directory: $workingDirectory')
    ..writeln('duration_ms: $elapsedMs')
    ..write(
      hadStarted
          ? 'detail: The tool execution was cancelled by the user.'
          : 'detail: The tool call was cancelled before execution started.',
    );
  return buffer.toString();
}

String _failedToolExecutionResultText({
  required String command,
  required String workingDirectory,
  required int elapsedMs,
  required String detail,
}) {
  final resolvedCommand = command.isEmpty ? 'tool_call' : command;
  final buffer = StringBuffer()
    ..writeln('status: failed')
    ..writeln('command: $resolvedCommand')
    ..writeln('working_directory: $workingDirectory')
    ..writeln('duration_ms: $elapsedMs')
    ..write('detail: $detail');
  return buffer.toString();
}

List<String> _splitTitleSourceLine(String value) {
  return value
      .split(RegExp(r'[。！？!?；;]'))
      .map(_sanitizeTitleSourceLine)
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
