part of '../ai_session_controller.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Pure utility functions extracted from AiSessionController.
// These do not reference any instance state.
// ─────────────────────────────────────────────────────────────────────────────

bool _hasIncompleteTodoItems(List<AiSessionTodoItem> todoItems) {
  return AiSessionTodoState.hasIncomplete(todoItems);
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
  return AiSessionTodoState.allCompleted(todoItems);
}

bool _hasFailedTodoItems(List<AiSessionTodoItem> todoItems) {
  return AiSessionTodoState.hasFailure(todoItems);
}

bool _environmentEquals(AiSessionEnvironment left, AiSessionEnvironment right) {
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
  // Strip all HTML tags so models that disregard the plain-text-only
  // instruction and still emit HTML wrappers produce a clean title.
  normalized = stripHtmlTags(normalized, replacement: '');
  final tagMatch = RegExp(
    r'<title[^>]*>([\s\S]*?)<\/title>',
    caseSensitive: false,
  ).firstMatch(normalized);
  if (tagMatch != null) {
    normalized = tagMatch.group(1) ?? '';
  }
  normalized = normalized.replaceAll(RegExp(r'[\n]+'), ' ');
  normalized = normalized.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\([^)]+\)'),
    (match) => match.group(1) ?? '',
  );
  normalized = normalized.replaceFirst(RegExp(r'^\s*\d+[.)、:：-]\s*'), '');
  normalized = normalized.replaceFirst(RegExp(r'^\s*[-*+#>]+\s*'), '');
  normalized = _stripTitleWrappers(normalized);
  final collapsed = collapseInlineWhitespace(normalized);
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
          _normalizeAutoTitleForComparison(
            AiSessionController._defaultNewSessionTitle,
          ) ||
      AiSessionController._genericAutoTitleCandidates.contains(normalized)) {
    return false;
  }
  final hasCjk = RegExp(r'[\u4E00-\u9FFF]').hasMatch(trimmed);
  if (hasCjk) {
    return normalized.characters.length >=
        AiSessionController._minimumMeaningfulTitleCharacters;
  }
  final words = splitTrimmedNonEmpty(trimmed, separator: kInlineWhitespacePattern).length;
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
  return collapseInlineWhitespace(normalized);
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
  final collapsed = collapseInlineWhitespace(value);
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
  String finalize(String content) => stripImageSummaryMarkup(
    _stripRawToolCallMarkup(sanitizeVisibleDsmlContent(content)),
  );

  final normalized = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normalized.split('\n');
  var cursor = 0;
  while (cursor < lines.length && lines[cursor].trim().isEmpty) {
    cursor += 1;
  }
  if (cursor >= lines.length ||
      !AiSessionController._internalPromptLeakHeaders.contains(
        lines[cursor].trim(),
      )) {
    return finalize(normalized);
  }
  while (cursor < lines.length) {
    final trimmed = lines[cursor].trim();
    if (trimmed.isEmpty ||
        AiSessionController._internalPromptLeakHeaders.contains(trimmed)) {
      cursor += 1;
      continue;
    }
    break;
  }
  final sanitized = lines.skip(cursor).join('\n').trimLeft();
  if (sanitized.length == normalized.length) {
    return finalize(normalized);
  }
  return finalize(sanitized);
}

/// Strip raw `<tool_call>…</tool_call>` and `<tool_result>…</tool_result>`
/// markup that some models echo verbatim in their text output alongside
/// native API tool-call events.  Without this filter the tags appear as ugly
/// raw XML in the chat bubble.
///
/// Also strips internal "Tool call: ToolName" labels that some
/// models output as reasoning artifacts. These are prompt-history notation
/// and should not appear in user-facing content.
String _stripRawToolCallMarkup(String value) {
  var stripped = value;

  // 1. Strip XML-style tool_call / tool_calls / tool_result / tool_use blocks.
  if (_rawToolCallPresencePattern.hasMatch(stripped)) {
    stripped = stripped
        .replaceAll(_rawToolCallsBlockPattern, '')
        .replaceAll(_rawToolCallBlockPattern, '')
        .replaceAll(_rawToolResultBlockPattern, '')
        .replaceAll(_rawToolUseBlockPattern, '')
        .replaceAll(_rawToolCallLooseTagPattern, '');
  }

  // 2. Strip "Tool call: ToolName" internal label lines.
  // This catches lines like "Tool call: Bash" or "[tool_call]" that
  // some models emit as reasoning artifacts.
  stripped = stripped.replaceAll(_internalToolCallLabelLinePattern, '');

  // Collapse excessive blank lines left behind after stripping.
  stripped = stripped
      .replaceAll(kExcessiveNewlinesPattern, '\n\n')
      .trim();
  return stripped;
}

final RegExp _rawToolCallPresencePattern = RegExp(
  r'<\s*/?\s*tool_(?:calls?|result|use)\b',
  caseSensitive: false,
);
final RegExp _rawToolCallBlockPattern = RegExp(
  r'<\s*tool_call\b[^>]*>[\s\S]*?<\s*/\s*tool_call\s*>',
  caseSensitive: false,
);
// Also strip the plural `<tool_calls>…</tool_calls>` wrapper that
// some reasoning models echo as a scaffold (e.g. DeepSeek Reasoner) — this
// previously leaked into the visible reasoning bubble because the stripper
// only recognized the singular `<tool_call>` variant.
final RegExp _rawToolCallsBlockPattern = RegExp(
  r'<\s*tool_calls\b[^>]*>[\s\S]*?<\s*/\s*tool_calls\s*>',
  caseSensitive: false,
);
final RegExp _rawToolResultBlockPattern = RegExp(
  r'<\s*tool_result\b[^>]*>[\s\S]*?<\s*/\s*tool_result\s*>',
  caseSensitive: false,
);
final RegExp _rawToolUseBlockPattern = RegExp(
  r'<\s*tool_use\b[^>]*>[\s\S]*?<\s*/\s*tool_use\s*>',
  caseSensitive: false,
);
final RegExp _rawToolCallLooseTagPattern = RegExp(
  r'<\s*/?\s*tool_(?:calls?|result|use)\b[^>]*>',
  caseSensitive: false,
);

/// Pattern to match internal "Tool call: ToolName" label lines.
/// Matches lines like:
///   - "Tool call: Bash"
///   - "Tool call: Read -> /path/file"
///   - "Tool call: Write (payload omitted from prompt history)"
///   - "[tool_call]"
///
/// These are prompt-history notation that some models echo back in text output.
final RegExp _internalToolCallLabelLinePattern = RegExp(
  r'^[ \t]*(?:Tool call:\s+\w+.*|\[tool_call\])[ \t]*$',
  multiLine: true,
  caseSensitive: false,
);

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
    return prettyPrintJson(decoded);
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

/// 把会话持久化阶段 (load / delete / save) 抛出的底层异常翻译成
/// 「现象 / 原因 / 建议」三段式中英双语文案，避免直接把 sqflite
/// `DatabaseException` 或 `FileSystemException.toString()` 透传给用户。
///
/// 调用方按操作语义传入 [operation]：
///   · 'load'   → 加载会话历史
///   · 'delete' → 删除会话
///   · 'save'   → 保存会话变更
String _friendlyAiSessionPersistenceError(
  Object error, {
  required String operation,
}) {
  final raw = error.toString();
  final operationZh = switch (operation) {
    'load' => '加载会话历史',
    'delete' => '删除会话',
    'save' => '保存会话',
    _ => operation,
  };
  final operationEn = switch (operation) {
    'load' => 'load conversation history',
    'delete' => 'delete conversation',
    'save' => 'save conversation',
    _ => operation,
  };
  // sqflite DatabaseException / SqfliteFfiException 都会把 SQL 与参数拼进
  // toString；不要把完整原文塞进 Snackbar，否则超长消息体会直接泄露到 UI。
  final isDb =
      raw.startsWith('DatabaseException') ||
      raw.startsWith('SqfliteFfiException') ||
      raw.contains('sqlite_error:') ||
      raw.contains('UNIQUE constraint failed') ||
      raw.contains('FOREIGN KEY constraint failed');
  final isFs =
      raw.startsWith('FileSystemException') ||
      raw.startsWith('PathExistsException') ||
      raw.startsWith('PathNotFoundException');
  if (!isDb && !isFs) {
    return raw;
  }
  final reasonZh = isDb
      ? '本地 sqlite 数据库拒绝执行该操作。常见诱因：\n'
            '  · 数据库文件被其他 OpenHand 实例 / 工具占用 (database is locked)\n'
            '  · 磁盘已满 / 空间不足\n'
            '  · 数据库文件损坏或 schema 与当前版本不兼容\n'
            '  · 唯一约束 / 外键冲突 (sort_order, primary key)'
      : '本地文件系统拒绝执行该操作。常见诱因：\n'
            '  · 路径不存在或父目录被删除\n'
            '  · 当前进程对该路径无读写权限\n'
            '  · 路径被其他进程独占 / 加锁\n'
            '  · 磁盘已满';
  final tryZh = isDb
      ? '· 关闭其他 OpenHand 进程后重试 (sqlite 单写)\n'
            '· 检查 Application Support 目录磁盘空间\n'
            '· 必要时备份并删除 openhand.db 让程序重建\n'
            '· 重启应用后再执行该操作'
      : '· 检查路径是否存在并可写\n'
            '· 检查磁盘剩余空间\n'
            '· 关闭可能占用该文件的外部程序\n'
            '· 重启应用后再次尝试';
  return StructuredErrorText.format(
    title: StructuredErrorText.pick(
      zh: '$operationZh失败',
      en: 'Failed to $operationEn',
    ),
    reason: StructuredErrorText.pick(
      zh: reasonZh,
      en: isDb
          ? 'The local sqlite database refused the operation. Common causes:\n'
                '  · The database file is locked by another OpenHand instance or tool\n'
                '  · The disk is full or out of space\n'
                '  · The database file is corrupted, or the schema is incompatible with the current version\n'
                '  · A unique or foreign-key constraint was violated'
          : 'The local file system refused the operation. Common causes:\n'
                '  · The path does not exist or its parent directory was removed\n'
                '  · The current process lacks read/write permission for the path\n'
                '  · Another process holds the path exclusively or locked it\n'
                '  · The disk is full',
    ),
    try_: StructuredErrorText.pick(
      zh: tryZh,
      en: isDb
          ? '· Close other OpenHand processes and try again\n'
                '· Check free space in the Application Support directory\n'
                '· If needed, back up and remove openhand.db so the app can rebuild it\n'
                '· Restart the app and retry the operation'
          : '· Verify that the path exists and is writable\n'
                '· Check remaining disk space\n'
                '· Close external programs that may be holding the file\n'
                '· Restart the app and try again',
    ),
    raw: _compactPersistenceRawDetail(raw),
  );
}

String? _compactPersistenceRawDetail(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    return null;
  }
  final sqliteError = RegExp(r'sqlite_error:\s*\d+').firstMatch(text);
  final unique = RegExp(
    r'UNIQUE constraint failed:\s*[^,\)]+',
  ).firstMatch(text);
  final foreignKey = RegExp(r'FOREIGN KEY constraint failed').firstMatch(text);
  final parts = <String>[
    if (sqliteError != null) sqliteError.group(0)!,
    if (unique != null) unique.group(0)!,
    if (foreignKey != null) foreignKey.group(0)!,
  ];
  if (parts.isNotEmpty) {
    return parts.join('；');
  }
  const maxRawCharacters = 600;
  return clipTextByCodeUnits(text, maxRawCharacters);
}

/// 工具调用消息的公共元数据：单条工具调用的标识、名称与入参。
///
/// `tool_*` 三个平铺键供旧版渲染与检索路径读取，`tool_calls` 数组是新版
/// 结构；两者必须同源，否则同一条消息在不同读取路径下会出现不一致。
Map<String, Object?> _toolCallMessageMetadata(AiToolCall toolCall) {
  return <String, Object?>{
    aiSessionMessageToolCallIdMetadataKey: toolCall.id,
    'tool_name': toolCall.name,
    'tool_arguments': toolCall.arguments,
    'tool_calls': <Map<String, Object?>>[
      <String, Object?>{
        'id': toolCall.id,
        'name': toolCall.name,
        'arguments': toolCall.arguments,
      },
    ],
  };
}

/// 把消息标记为隐藏，并记录隐藏来源。
///
/// 「隐藏」在落库上就是 isDeleted 叠加一个来源标记键。重新生成与响应变体两条
/// 路径必须写成同一形态，否则恢复时认不出这条消息是被哪条路径隐藏的。
AiSessionMessage _hiddenMessage(
  AiSessionMessage message,
  Map<String, Object?> hiddenMarkers,
) {
  return message.copyWith(
    isDeleted: true,
    metadata: <String, Object?>{...message.metadata, ...hiddenMarkers},
  );
}
