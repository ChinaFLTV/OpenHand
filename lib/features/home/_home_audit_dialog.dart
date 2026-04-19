part of 'openhand_home_page.dart';

/// Pretty-prints a JSON-ish value into a stable, human-readable string.
String _auditFormatJson(Object? value) {
  try {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(_auditSanitizeValue(value));
  } catch (_) {
    // Last-resort stringification keeps the dialog useful even for cyclic or
    // otherwise unencodable structures. This is intentionally permissive.
    return '${value ?? '—'}';
  }
}

Object? _auditSanitizeValue(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is DateTime) {
    return value.toIso8601String();
  }
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        '${entry.key}': _auditSanitizeValue(entry.value),
    };
  }
  if (value is Iterable) {
    return value.map(_auditSanitizeValue).toList(growable: false);
  }
  return value.toString();
}

String _auditFormatInstant(DateTime? value) {
  if (value == null) return '—';
  try {
    final local = value.toLocal();
    final iso = local.toIso8601String();
    return iso;
  } catch (_) {
    return '$value';
  }
}

String _auditFormatBool(bool? value) {
  if (value == null) return '—';
  return value ? 'true' : 'false';
}

String _auditFormatOrDash(Object? value) {
  if (value == null) return '—';
  final text = '$value'.trim();
  return text.isEmpty ? '—' : text;
}

/// Gemini-style greyscale sweep shimmer placeholder for audit fields that are
/// still being populated (e.g. while the AI response is streaming).
class _AuditShimmerPlaceholder extends StatefulWidget {
  const _AuditShimmerPlaceholder({this.width});

  final double? width;

  @override
  State<_AuditShimmerPlaceholder> createState() =>
      _AuditShimmerPlaceholderState();
}

class _AuditShimmerPlaceholderState extends State<_AuditShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final baseColor = cs.surfaceContainerHighest;
    final highlightColor = cs.surfaceContainerLow;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Container(
          width: widget.width ?? double.infinity,
          height: 14,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + 2.0 * _ctrl.value, 0),
              end: Alignment(-1.0 + 2.0 * _ctrl.value + 1.0, 0),
              colors: [baseColor, highlightColor, baseColor],
            ),
          ),
        );
      },
    );
  }
}

/// A stack of shimmer bars that gives the impression of loading text content.
Widget _auditShimmerBlock({int lines = 3, double spacing = 8}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: List<Widget>.generate(lines, (i) {
      return Padding(
        padding: EdgeInsets.only(bottom: i < lines - 1 ? spacing : 0),
        child: _AuditShimmerPlaceholder(
          // Last line shorter to look more natural.
          width: i == lines - 1 ? 180 : null,
        ),
      );
    }),
  );
}

/// Smoothly animates dialog shell size changes caused by expanding/collapsing
/// large audit sections.
class _AuditDialogSizeAnimator extends StatelessWidget {
  const _AuditDialogSizeAnimator({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeInOutCubic,
        alignment: Alignment.topCenter,
        child: child,
      ),
    );
  }
}

/// Shared section card used by both the message-level and session-level audit
/// dialogs. Follows Material You Expressive surfaces and the active theme.
///
/// When [collapsible] is true the card renders a toggle chevron so the user
/// can expand/collapse the content with a smooth [AnimatedSize] transition.
class _AuditSectionCard extends StatefulWidget {
  const _AuditSectionCard({
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.collapsible = false,
    this.initiallyExpanded = true,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget child;
  /// When true the body can be collapsed behind a chevron toggle.
  final bool collapsible;
  /// Only relevant when [collapsible] is true. Defaults to expanded.
  final bool initiallyExpanded;

  @override
  State<_AuditSectionCard> createState() => _AuditSectionCardState();
}

class _AuditSectionCardState extends State<_AuditSectionCard> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: widget.collapsible
                ? () => setState(() => _expanded = !_expanded)
                : null,
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    widget.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (widget.collapsible)
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOutCubic,
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: 20,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (widget.subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              widget.subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOutCubic,
              alignment: Alignment.topLeft,
              child: !widget.collapsible || _expanded
                  ? KeyedSubtree(
                      key: const ValueKey<String>('audit-section-expanded'),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: widget.child,
                      ),
                    )
                  : const KeyedSubtree(
                      key: ValueKey<String>('audit-section-collapsed'),
                      child: SizedBox(width: double.infinity, height: 0),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Key-value row used by audit dialogs. Keys are right-aligned, values are
/// selectable so operators can copy individual fields quickly.
class _AuditKvRow extends StatelessWidget {
  const _AuditKvRow({
    required this.label,
    this.value,
    this.valueWidget,
    this.mono = false,
  }) : assert(value != null || valueWidget != null);

  final String label;
  final String? value;
  /// Optional custom widget shown instead of [value]. Used for shimmer
  /// placeholders during streaming.
  final Widget? valueWidget;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final valueStyle = (mono
            ? theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')
            : theme.textTheme.bodyMedium)
        ?.copyWith(color: colorScheme.onSurface);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: valueWidget ??
                SelectableText(
                  (value ?? '').isEmpty ? '—' : value!,
                  style: valueStyle,
                ),
          ),
        ],
      ),
    );
  }
}

/// A collapsible JSON block with copy-to-clipboard support.
/// Uses [AnimatedSize] + [ClipRect] for smooth expand/collapse transitions
/// consistent with the reasoning message card animation style.
class _AuditJsonBlock extends StatefulWidget {
  const _AuditJsonBlock({
    required this.label,
    required this.json,
    this.initiallyExpanded = false,
    this.emptyHint,
  });

  final String label;
  final Object? json;
  final bool initiallyExpanded;
  final String? emptyHint;

  @override
  State<_AuditJsonBlock> createState() => _AuditJsonBlockState();
}

class _AuditJsonBlockState extends State<_AuditJsonBlock> {
  late bool _expanded = widget.initiallyExpanded;

  bool get _isEmpty {
    final value = widget.json;
    if (value == null) return true;
    if (value is Map && value.isEmpty) return true;
    if (value is Iterable && value.isEmpty) return true;
    if (value is String && value.trim().isEmpty) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final rendered = _isEmpty ? '' : _auditFormatJson(widget.json);
    final emptyHint = widget.emptyHint ??
        _localizedText(context, zh: '无数据', en: 'No data');
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: _isEmpty ? null : () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOutCubic,
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (!_isEmpty)
                    IconButton(
                      tooltip: _localizedText(
                        context,
                        zh: '复制 JSON',
                        en: 'Copy JSON',
                      ),
                      icon: const Icon(Icons.copy_all_rounded, size: 18),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: rendered));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              _localizedText(
                                context,
                                zh: '已复制到剪贴板',
                                en: 'Copied to clipboard',
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
          if (_isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Text(
                emptyHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            ClipRect(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOutCubic,
                alignment: Alignment.topLeft,
                child: _expanded
                    ? KeyedSubtree(
                        key: const ValueKey<String>('audit-json-expanded'),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                          child: SelectableText(
                            rendered,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                      )
                    : const KeyedSubtree(
                        key: ValueKey<String>('audit-json-collapsed'),
                        child: SizedBox.shrink(),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Message-level audit dialog. Shows raw response, parameters, timing,
/// error information and all other telemetry gleaned from the message model.
class _MessageAuditDialog extends StatefulWidget {
  const _MessageAuditDialog({
    required this.message,
    required this.session,
    required this.controller,
  });

  final AiSessionMessage message;
  final AiSession session;
  final AiSessionController controller;

  @override
  State<_MessageAuditDialog> createState() => _MessageAuditDialogState();
}

class _MessageAuditDialogState extends State<_MessageAuditDialog> {
  bool _rebuildScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    if (_rebuildScheduled) {
      return;
    }
    _rebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rebuildScheduled = false;
      if (!mounted) return;
      setState(() {});
    });
  }

  AiSession get _liveSession {
    for (final session in widget.controller.sessions) {
      if (session.id == widget.session.id) {
        return session;
      }
    }
    return widget.session;
  }

  AiSessionMessage get _liveMessage {
    final session = _liveSession;
    for (final message in session.messages) {
      if (message.id == widget.message.id) {
        return message;
      }
    }
    return widget.message;
  }

  @override
  Widget build(BuildContext context) {
    final session = _liveSession;
    final message = _liveMessage;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final size = MediaQuery.sizeOf(context);
    final maxWidth = size.width * 0.88;
    final maxHeight = size.height * 0.88;
    final metadata = Map<String, Object?>.from(message.metadata);
    // Pull well-known telemetry shape if present.
    final telemetry = metadata['telemetry'];
    final durationMs = _auditFirstInt([
      metadata['duration_ms'],
      if (telemetry is Map) telemetry['duration_ms'],
    ]);
    final startedAt = _auditFirstDate([
      metadata['started_at'],
      if (telemetry is Map) telemetry['started_at'],
    ]);
    final endedAt = _auditFirstDate([
      metadata['ended_at'],
      metadata['completed_at'],
      if (telemetry is Map) telemetry['ended_at'],
    ]);
    final error = _auditFirstString([
      metadata['error'],
      metadata['error_message'],
      if (telemetry is Map) telemetry['error'],
    ]);
    final requestUrl = _auditFirstString([
      metadata['request_url'],
      if (telemetry is Map) telemetry['request_url'],
    ]);
    final requestMethod = _auditFirstString([
      metadata['request_method'],
      if (telemetry is Map) telemetry['request_method'],
    ]);
    final requestHeaders = _auditFirstMap([
      metadata['request_headers'],
      if (telemetry is Map) telemetry['request_headers'],
    ]);
    final requestPayload = _auditFirstAny([
      metadata['request_payload'],
      metadata['request_body'],
      if (telemetry is Map) telemetry['request_payload'],
    ]);
    final responseRaw = _auditFirstAny([
      metadata['response_raw'],
      metadata['raw_response'],
      if (telemetry is Map) telemetry['response_raw'],
    ]);
    final envSnapshot = _auditFirstMap([
      metadata['environment'],
      if (telemetry is Map) telemetry['environment'],
    ]);
    final attachments = _auditFirstList([
      metadata['attachments'],
      if (telemetry is Map) telemetry['attachments'],
    ]);
    final streaming = metadata[aiSessionMessageMetadataStreamingKey] == true;
    // The composed prompt body that was actually sent to the AI. Stored on
    // user messages by the session controller when telemetry debug is on.
    final composedPromptText = _auditFirstString([
      metadata['composed_prompt_text'],
    ]);
    final composedPromptTurns = _auditFirstList([
      metadata['composed_prompt_turns'],
    ]);
    final promptMetadataFromMsg = _auditFirstMap([
      metadata['prompt_metadata'],
    ]);

    return _AuditDialogSizeAnimator(
      child: AlertDialog(
        backgroundColor: colorScheme.surfaceContainerHighest,
        surfaceTintColor: Colors.transparent,
        titlePadding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        title: Row(
        children: [
          Icon(Icons.fact_check_outlined, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _localizedText(context, zh: '消息审计', en: 'Message Audit'),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            tooltip: _localizedText(context, zh: '关闭', en: 'Close'),
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
        content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _AuditSectionCard(
                icon: Icons.info_outline_rounded,
                title: _localizedText(context, zh: '基本信息', en: 'Overview'),
                child: Column(
                  children: [
                    _AuditKvRow(
                      label: _localizedText(context, zh: '消息 ID', en: 'Message ID'),
                      value: message.id,
                      mono: true,
                    ),
                    _AuditKvRow(
                      label: _localizedText(context, zh: '会话 ID', en: 'Session ID'),
                      value: session.id,
                      mono: true,
                    ),
                    _AuditKvRow(
                      label: _localizedText(context, zh: '角色', en: 'Role'),
                      value: message.role.storageValue,
                    ),
                    _AuditKvRow(
                      label: _localizedText(context, zh: '类型', en: 'Kind'),
                      value: message.kind.storageValue,
                    ),
                    _AuditKvRow(
                      label: _localizedText(context, zh: '字符数', en: 'Character Count'),
                      value: '${message.characterCount}',
                    ),
                    _AuditKvRow(
                      label: _localizedText(context, zh: '是否流式', en: 'Streaming'),
                      value: _auditFormatBool(streaming),
                    ),
                    _AuditKvRow(
                      label: _localizedText(context, zh: '是否已删除', en: 'Deleted'),
                      value: _auditFormatBool(message.isDeleted),
                    ),
                    _AuditKvRow(
                      label: _localizedText(context, zh: '是否报错', en: 'Has Error'),
                      value: _auditFormatBool(error != null && error.isNotEmpty),
                    ),
                  ],
                ),
              ),
              _AuditSectionCard(
                icon: Icons.schedule_outlined,
                title: _localizedText(context, zh: '时间与耗时', en: 'Timing'),
                child: Column(
                  children: [
                    _AuditKvRow(
                      label: _localizedText(
                        context,
                        zh: '开始/创建时间',
                        en: 'Started / Created',
                      ),
                      value: _auditFormatInstant(startedAt ?? message.createdAt),
                    ),
                    if (streaming && endedAt == null)
                      _AuditKvRow(
                        label: _localizedText(context, zh: '结束时间', en: 'Ended'),
                        valueWidget: const _AuditShimmerPlaceholder(width: 200),
                      )
                    else
                      _AuditKvRow(
                        label: _localizedText(context, zh: '结束时间', en: 'Ended'),
                        value: _auditFormatInstant(endedAt),
                      ),
                    if (streaming && durationMs == null)
                      _AuditKvRow(
                        label: _localizedText(context, zh: '耗时 (ms)', en: 'Duration (ms)'),
                        valueWidget: const _AuditShimmerPlaceholder(width: 120),
                      )
                    else
                      _AuditKvRow(
                        label: _localizedText(context, zh: '耗时 (ms)', en: 'Duration (ms)'),
                        value: durationMs == null ? '—' : '$durationMs',
                      ),
                  ],
                ),
              ),
              _AuditSectionCard(
                icon: Icons.memory_outlined,
                title: _localizedText(context, zh: '模型与 Token', en: 'Model & Tokens'),
                child: Column(
                  children: [
                    _AuditKvRow(
                      label: _localizedText(context, zh: '模型 ID', en: 'Model ID'),
                      value: _auditFormatOrDash(message.modelId),
                    ),
                    _AuditKvRow(
                      label: _localizedText(context, zh: '模型标签', en: 'Model Label'),
                      value: _auditFormatOrDash(message.modelLabel),
                    ),
                    if (streaming && message.usage == null) ...
                      [
                        _AuditKvRow(
                          label: _localizedText(context, zh: '总 Token', en: 'Total Tokens'),
                          valueWidget: const _AuditShimmerPlaceholder(width: 100),
                        ),
                        _AuditKvRow(
                          label: _localizedText(context, zh: '输入 Token', en: 'Prompt Tokens'),
                          valueWidget: const _AuditShimmerPlaceholder(width: 100),
                        ),
                        _AuditKvRow(
                          label: _localizedText(context, zh: '输出 Token', en: 'Completion Tokens'),
                          valueWidget: const _AuditShimmerPlaceholder(width: 100),
                        ),
                      ]
                    else ...
                      [
                        _AuditKvRow(
                          label: _localizedText(context, zh: '总 Token', en: 'Total Tokens'),
                          value: '${message.usage?.totalTokens ?? '—'}',
                        ),
                        _AuditKvRow(
                          label: _localizedText(context, zh: '输入 Token', en: 'Prompt Tokens'),
                          value: '${message.usage?.promptTokens ?? '—'}',
                        ),
                        _AuditKvRow(
                          label: _localizedText(context, zh: '输出 Token', en: 'Completion Tokens'),
                          value: '${message.usage?.completionTokens ?? '—'}',
                        ),
                      ],
                    if (message.usage != null)
                      _AuditJsonBlock(
                        label: _localizedText(context, zh: 'Token 明细', en: 'Token Breakdown'),
                        json: message.usage!.toJson(),
                      ),
                  ],
                ),
              ),
              if (error != null && error.isNotEmpty)
                _AuditSectionCard(
                  icon: Icons.error_outline_rounded,
                  title: _localizedText(context, zh: '错误信息', en: 'Error'),
                  child: SelectableText(
                    error,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.error,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              _AuditSectionCard(
                icon: Icons.article_outlined,
                collapsible: true,
                initiallyExpanded: false,
                title: _localizedText(context, zh: '消息内容', en: 'Content'),
                subtitle: composedPromptText != null
                    ? _localizedText(
                        context,
                        zh:
                            '以下为该轮用户消息触发时，程序自动拼装后最终发送给 AI 的 prompt 完全体（含系统指令 / 工具目录 / 用户记忆 / 历史上下文 / 用户输入等）。',
                        en:
                            'Full composed prompt that was actually sent to the AI for this round (system instructions, tool catalog, memory, history and user input).',
                      )
                    : streaming
                    ? _localizedText(
                        context,
                        zh: '正在等待本轮最终组合 Prompt 注入（发送中会自动刷新）',
                        en:
                            'Waiting for composed prompt injection (auto-refreshes during streaming).',
                      )
                    : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child:
                          streaming &&
                              (composedPromptText == null ||
                                  composedPromptText.isEmpty)
                          ? _auditShimmerBlock(lines: 6)
                          : SelectableText(
                              composedPromptText != null &&
                                      composedPromptText.isNotEmpty
                                  ? composedPromptText
                                  : (message.content.isEmpty
                                        ? '—'
                                        : message.content),
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                              ),
                            ),
                    ),
                    if (composedPromptText != null) ...[
                      const SizedBox(height: 10),
                      _AuditKvRow(
                        label: _localizedText(
                          context,
                          zh: '用户原始输入',
                          en: 'User Raw Input',
                        ),
                        value: message.content.isEmpty ? '—' : message.content,
                        mono: true,
                      ),
                      if (composedPromptTurns != null &&
                          composedPromptTurns.isNotEmpty)
                        _AuditJsonBlock(
                          label: _localizedText(
                            context,
                            zh: '结构化 Prompt Turns',
                            en: 'Structured Prompt Turns',
                          ),
                          json: composedPromptTurns,
                          emptyHint: _localizedText(
                            context,
                            zh: '无',
                            en: 'None',
                          ),
                        ),
                      if (promptMetadataFromMsg != null &&
                          promptMetadataFromMsg.isNotEmpty)
                        _AuditJsonBlock(
                          label: _localizedText(
                            context,
                            zh: 'Prompt Metadata',
                            en: 'Prompt Metadata',
                          ),
                          json: promptMetadataFromMsg,
                        ),
                    ],
                  ],
                ),
              ),
              _AuditSectionCard(
                icon: Icons.cloud_outlined,
                collapsible: true,
                initiallyExpanded: false,
                title: _localizedText(context, zh: '请求参数', en: 'Request'),
                child: Column(
                  children: [
                    _AuditKvRow(
                      label: 'URL',
                      value: _auditFormatOrDash(requestUrl),
                      mono: true,
                    ),
                    _AuditKvRow(
                      label: _localizedText(context, zh: '方法', en: 'Method'),
                      value: _auditFormatOrDash(requestMethod),
                    ),
                    _AuditJsonBlock(
                      label: _localizedText(context, zh: '请求头', en: 'Headers'),
                      json: requestHeaders,
                      emptyHint: _localizedText(
                        context,
                        zh: '未捕获（请在设置 → AI → 遥测 中开启调试）',
                        en: 'Not captured (enable Settings → AI → Telemetry Debug)',
                      ),
                    ),
                    _AuditJsonBlock(
                      label: _localizedText(
                        context,
                        zh: '请求体 / Query / Path',
                        en: 'Body / Query / Path',
                      ),
                      json: requestPayload,
                      emptyHint: _localizedText(
                        context,
                        zh: '未捕获（请在设置 → AI → 遥测 中开启调试）',
                        en: 'Not captured (enable Settings → AI → Telemetry Debug)',
                      ),
                    ),
                  ],
                ),
              ),
              _AuditSectionCard(
                icon: Icons.receipt_long_outlined,
                collapsible: true,
                initiallyExpanded: false,
                title: _localizedText(context, zh: '原始 AI 响应', en: 'Raw AI Response'),
                child: streaming && responseRaw == null
                    ? _auditShimmerBlock(lines: 4)
                    : _AuditJsonBlock(
                        label: _localizedText(
                          context,
                          zh: '展开查看原始响应',
                          en: 'Expand raw response',
                        ),
                        json: responseRaw,
                        emptyHint: _localizedText(
                          context,
                          zh: '未捕获：调试未开启或模型未提供原始响应',
                          en: 'Not captured: debug disabled or response unavailable',
                        ),
                      ),
              ),
              _AuditSectionCard(
                icon: Icons.attach_file_outlined,
                title: _localizedText(context, zh: '附件', en: 'Attachments'),
                child: _AuditJsonBlock(
                  label: _localizedText(
                    context,
                    zh: '附件列表',
                    en: 'Attachment list',
                  ),
                  json: attachments,
                  emptyHint: _localizedText(context, zh: '无附件', en: 'No attachments'),
                ),
              ),
              _AuditSectionCard(
                icon: Icons.data_object_rounded,
                collapsible: true,
                initiallyExpanded: false,
                title: _localizedText(
                  context,
                  zh: '完整元数据 (metadata)',
                  en: 'Full Metadata',
                ),
                child: _AuditJsonBlock(
                  label: _localizedText(context, zh: '消息元数据', en: 'Message metadata'),
                  json: metadata,
                  initiallyExpanded: true,
                ),
              ),
              _AuditSectionCard(
                icon: Icons.public_outlined,
                collapsible: true,
                initiallyExpanded: false,
                title: _localizedText(context, zh: '会话环境', en: 'Session Environment'),
                child: _AuditJsonBlock(
                  label: _localizedText(
                    context,
                    zh: '环境快照',
                    en: 'Environment snapshot',
                  ),
                  json: envSnapshot ?? _auditSafeMap(session.environment.toJson),
                ),
              ),
            ],
          ),
        ),
      ),
        actions: [
        FilledButton.tonalIcon(
          onPressed: () async {
            final payload = <String, Object?>{
              'message': message.toJson(),
              'session_id': session.id,
              'session_title': session.title,
              'environment': _auditSafeMap(session.environment.toJson),
            };
            await Clipboard.setData(
              ClipboardData(text: _auditFormatJson(payload)),
            );
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  _localizedText(context, zh: '审计快照已复制', en: 'Audit snapshot copied'),
                ),
              ),
            );
          },
          icon: const Icon(Icons.copy_all_rounded, size: 18),
          label: Text(
            _localizedText(context, zh: '复制审计快照', en: 'Copy Audit Snapshot'),
          ),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_localizedText(context, zh: '关闭', en: 'Close')),
        ),
        ],
      ),
    );
  }
}

/// Session-level audit dialog. Shows structured overview of the session and
/// exposes CRUD controls for the title, metadata JSON and individual messages.
class _SessionAuditDialog extends StatefulWidget {
  const _SessionAuditDialog({
    required this.session,
    required this.controller,
  });

  final AiSession session;
  final AiSessionController controller;

  @override
  State<_SessionAuditDialog> createState() => _SessionAuditDialogState();
}

class _SessionAuditDialogState extends State<_SessionAuditDialog> {
  late TextEditingController _titleController;
  late TextEditingController _metadataController;
  late FocusNode _titleFocusNode;
  late FocusNode _metadataFocusNode;
  bool _liveSyncScheduled = false;
  String? _metadataError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.session.title);
    _metadataController = TextEditingController(
      text: _auditFormatJson(widget.session.metadata),
    );
    _titleFocusNode = FocusNode();
    _metadataFocusNode = FocusNode();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _titleController.dispose();
    _metadataController.dispose();
    _titleFocusNode.dispose();
    _metadataFocusNode.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    if (_liveSyncScheduled) {
      return;
    }
    _liveSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _liveSyncScheduled = false;
      if (!mounted) return;
      _syncLiveFieldsAndRebuild();
    });
  }

  void _syncLiveFieldsAndRebuild() {
    final session = _liveSession;
    if (!_titleFocusNode.hasFocus && _titleController.text != session.title) {
      _titleController.text = session.title;
    }
    final metadataJson = _auditFormatJson(session.metadata);
    if (!_metadataFocusNode.hasFocus &&
        _metadataController.text != metadataJson) {
      _metadataController.text = metadataJson;
    }
    // Force rebuild so newly persisted changes reflect instantly.
    setState(() {});
  }

  AiSession get _liveSession {
    final sessions = widget.controller.sessions;
    for (final item in sessions) {
      if (item.id == widget.session.id) return item;
    }
    return widget.session;
  }

  Future<void> _saveTitle() async {
    final trimmed = _titleController.text.trim();
    if (trimmed.isEmpty || trimmed == _liveSession.title) return;
    setState(() => _busy = true);
    try {
      await widget.controller.renameSession(_liveSession.id, trimmed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveMetadata() async {
    setState(() {
      _metadataError = null;
      _busy = true;
    });
    try {
      final raw = _metadataController.text.trim();
      Map<String, Object?> parsed;
      if (raw.isEmpty) {
        parsed = const <String, Object?>{};
      } else {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          throw const FormatException('Metadata root must be a JSON object.');
        }
        parsed = Map<String, Object?>.from(decoded);
      }
      // Build a diff payload that resets existing keys that were removed by
      // overlaying `null` onto them; updateSessionMetadata skips equal values
      // automatically.
      final currentKeys = _liveSession.metadata.keys.toSet();
      final nextKeys = parsed.keys.toSet();
      final payload = <String, Object?>{};
      for (final key in nextKeys) {
        payload[key] = parsed[key];
      }
      for (final key in currentKeys.difference(nextKeys)) {
        payload[key] = null;
      }
      await widget.controller.updateSessionMetadata(_liveSession.id, payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _localizedText(context, zh: '会话元数据已更新', en: 'Session metadata saved'),
          ),
        ),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _metadataError = _localizedText(
          context,
          zh: 'JSON 解析失败：${error.message}',
          en: 'Invalid JSON: ${error.message}',
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _metadataError = _localizedText(
          context,
          zh: '保存失败：$error',
          en: 'Save failed: $error',
        );
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteMessage(AiSessionMessage message) async {
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          _localizedText(dialogContext, zh: '删除消息', en: 'Delete Message'),
        ),
        content: Text(
          _localizedText(
            dialogContext,
            zh: '确认删除该消息？此操作不可撤销。',
            en: 'Delete this message? This cannot be undone.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              _localizedText(dialogContext, zh: '取消', en: 'Cancel'),
            ),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              _localizedText(dialogContext, zh: '删除', en: 'Delete'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await widget.controller.deleteMessages(
        <String>[message.id],
        sessionId: _liveSession.id,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final size = MediaQuery.sizeOf(context);
    final maxWidth = size.width * 0.9;
    final maxHeight = size.height * 0.9;
    final session = _liveSession;
    final statistics = session.statistics;

    return _AuditDialogSizeAnimator(
      child: AlertDialog(
        backgroundColor: colorScheme.surfaceContainerHighest,
        surfaceTintColor: Colors.transparent,
        titlePadding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        title: Row(
        children: [
          Icon(Icons.assignment_outlined, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _localizedText(context, zh: '会话审计', en: 'Session Audit'),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            ),
          IconButton(
            tooltip: _localizedText(context, zh: '关闭', en: 'Close'),
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
        content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _AuditSectionCard(
                icon: Icons.info_outline_rounded,
                title: _localizedText(context, zh: '基本信息', en: 'Overview'),
                child: Column(
                  children: [
                    _AuditKvRow(
                      label: _localizedText(context, zh: '会话 ID', en: 'Session ID'),
                      value: session.id,
                      mono: true,
                    ),
                    _AuditKvRow(
                      label: _localizedText(context, zh: '模板', en: 'Template'),
                      value:
                          '${session.templateName} (${session.templateId}) · v${session.templateInternalVersion}',
                    ),
                    _AuditKvRow(
                      label: _localizedText(context, zh: '创建时间', en: 'Created At'),
                      value: _auditFormatInstant(session.createdAt),
                    ),
                    _AuditKvRow(
                      label: _localizedText(context, zh: '更新时间', en: 'Updated At'),
                      value: _auditFormatInstant(session.updatedAt),
                    ),
                    _AuditKvRow(
                      label: _localizedText(context, zh: '消息数', en: 'Messages'),
                      value: '${statistics.totalMessageCount}',
                    ),
                    _AuditKvRow(
                      label: _localizedText(context, zh: '总 Token', en: 'Total Tokens'),
                      value: '${statistics.totalTokens ?? 0}',
                    ),
                    _AuditKvRow(
                      label: _localizedText(context, zh: '最近模型', en: 'Last Model'),
                      value: _auditFormatOrDash(
                        session.lastUsedModelLabel ?? session.lastUsedModelId,
                      ),
                    ),
                  ],
                ),
              ),
              _AuditSectionCard(
                icon: Icons.edit_note_rounded,
                title: _localizedText(context, zh: '标题编辑', en: 'Title (Editable)'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _titleController,
                      focusNode: _titleFocusNode,
                      decoration: InputDecoration(
                        labelText: _localizedText(
                          context,
                          zh: '会话标题',
                          en: 'Session title',
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _saveTitle,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(
                          _localizedText(context, zh: '保存标题', en: 'Save Title'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _AuditSectionCard(
                icon: Icons.data_object_rounded,
                title: _localizedText(
                  context,
                  zh: '会话元数据 (可编辑 JSON)',
                  en: 'Session Metadata (Editable JSON)',
                ),
                subtitle: _localizedText(
                  context,
                  zh: '修改后点击保存将通过会话控制器写回数据库并实时刷新 UI。删除的 key 会被清除。',
                  en:
                      'Save writes back through the session controller with live UI diff; removed keys are cleared.',
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _metadataController,
                      focusNode: _metadataFocusNode,
                      minLines: 6,
                      maxLines: 16,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                      decoration: InputDecoration(
                        labelText: 'JSON',
                        errorText: _metadataError,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _saveMetadata,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(
                          _localizedText(context, zh: '保存元数据', en: 'Save Metadata'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _AuditSectionCard(
                icon: Icons.route_outlined,
                collapsible: true,
                initiallyExpanded: false,
                title: _localizedText(
                  context,
                  zh: '运行时 Prompt 元数据 (只读)',
                  en: 'Runtime Prompt Metadata (Read-only)',
                ),
                subtitle: _localizedText(
                  context,
                  zh: '用于排查本轮消息拼装上下文；自动由系统写入。',
                  en:
                      'Useful for prompt-construction troubleshooting; auto-updated by runtime.',
                ),
                child: _AuditJsonBlock(
                  label: _localizedText(
                    context,
                    zh: 'last_prompt_metadata',
                    en: 'last_prompt_metadata',
                  ),
                  json: session.lastPromptMetadata,
                  emptyHint: _localizedText(
                    context,
                    zh: '暂无运行时 Prompt 元数据',
                    en: 'No runtime prompt metadata yet',
                  ),
                ),
              ),
              _AuditSectionCard(
                icon: Icons.public_outlined,
                title: _localizedText(context, zh: '会话环境', en: 'Environment'),
                child: _AuditJsonBlock(
                  label: _localizedText(
                    context,
                    zh: '环境快照',
                    en: 'Environment snapshot',
                  ),
                  json: _auditSafeMap(session.environment.toJson),
                  initiallyExpanded: true,
                ),
              ),
              _AuditSectionCard(
                icon: Icons.history_rounded,
                title: _localizedText(
                  context,
                  zh: '最近错误 (${session.recentErrors.length})',
                  en: 'Recent Errors (${session.recentErrors.length})',
                ),
                child: _AuditJsonBlock(
                  label: _localizedText(
                    context,
                    zh: '错误列表',
                    en: 'Error list',
                  ),
                  json: session.recentErrors
                      .map((error) => _auditSafeMap(error.toJson))
                      .toList(growable: false),
                  emptyHint: _localizedText(context, zh: '暂无错误', en: 'No errors recorded'),
                ),
              ),
              _AuditSectionCard(
                icon: Icons.chat_bubble_outline_rounded,
                title: _localizedText(
                  context,
                  zh: '消息列表 (${session.messages.length})',
                  en: 'Messages (${session.messages.length})',
                ),
                subtitle: _localizedText(
                  context,
                  zh: '点击单条可打开消息审计弹窗；支持删除单条消息。',
                  en: 'Tap a row to inspect a message; delete removes it from storage.',
                ),
                child: Column(
                  children: session.messages.isEmpty
                      ? <Widget>[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              _localizedText(
                                context,
                                zh: '暂无消息',
                                en: 'No messages',
                              ),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ]
                      : session.messages
                          .map(
                            (message) => _AuditMessageRow(
                              message: message,
                              onInspect: () async {
                                await _showMessageAuditDialog(
                                  context,
                                  message: message,
                                  session: session,
                                  controller: widget.controller,
                                );
                              },
                              onDelete: _busy
                                  ? null
                                  : () => _deleteMessage(message),
                            ),
                          )
                          .toList(growable: false),
                ),
              ),
            ],
          ),
        ),
      ),
        actions: [
        FilledButton.tonal(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_localizedText(context, zh: '关闭', en: 'Close')),
        ),
        ],
      ),
    );
  }
}

class _AuditMessageRow extends StatelessWidget {
  const _AuditMessageRow({
    required this.message,
    required this.onInspect,
    required this.onDelete,
  });

  final AiSessionMessage message;
  final VoidCallback onInspect;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final snippet = message.content.trim();
    final preview = snippet.length > 140
        ? '${snippet.substring(0, 140)}…'
        : (snippet.isEmpty ? '—' : snippet);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              message.kind.storageValue,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.id,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  preview,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  _auditFormatInstant(message.createdAt),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: _localizedText(context, zh: '审计', en: 'Audit'),
            icon: const Icon(Icons.fact_check_outlined, size: 20),
            onPressed: onInspect,
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: _localizedText(context, zh: '删除', en: 'Delete'),
            icon: Icon(
              Icons.delete_outline_rounded,
              size: 20,
              color: onDelete == null
                  ? colorScheme.onSurfaceVariant
                  : colorScheme.error,
            ),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

int? _auditFirstInt(Iterable<Object?> candidates) {
  for (final value in candidates) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
  }
  return null;
}

DateTime? _auditFirstDate(Iterable<Object?> candidates) {
  for (final value in candidates) {
    if (value is DateTime) return value;
    if (value is String && value.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
    if (value is int) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
      } catch (_) {}
    }
  }
  return null;
}

String? _auditFirstString(Iterable<Object?> candidates) {
  for (final value in candidates) {
    if (value == null) continue;
    final text = '$value'.trim();
    if (text.isNotEmpty && text != 'null') return text;
  }
  return null;
}

Map<String, Object?>? _auditFirstMap(Iterable<Object?> candidates) {
  for (final value in candidates) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) return Map<String, Object?>.from(value);
  }
  return null;
}

List<Object?>? _auditFirstList(Iterable<Object?> candidates) {
  for (final value in candidates) {
    if (value is List) return List<Object?>.from(value);
  }
  return null;
}

Object? _auditFirstAny(Iterable<Object?> candidates) {
  for (final value in candidates) {
    if (value != null) return value;
  }
  return null;
}

/// Safely invokes a toJson-like getter and falls back to an empty map on
/// failure. Keeps the audit dialog resilient against model-side serialization
/// regressions.
Map<String, Object?> _auditSafeMap(Map<String, Object?> Function() builder) {
  try {
    return builder();
  } catch (_) {
    return const <String, Object?>{};
  }
}

/// Opens the message-level audit dialog using the app's configured dialog
/// animations so entrance/exit behavior matches the rest of the product.
Future<void> _showMessageAuditDialog(
  BuildContext context, {
  required AiSessionMessage message,
  required AiSession session,
  required AiSessionController controller,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) => _MessageAuditDialog(
      message: message,
      session: session,
      controller: controller,
    ),
  );
}

/// Opens the session-level audit dialog with full CRUD capability wired to
/// the provided [controller].
Future<void> _showSessionAuditDialog(
  BuildContext context, {
  required AiSession session,
  required AiSessionController controller,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) => _SessionAuditDialog(
      session: session,
      controller: controller,
    ),
  );
}
