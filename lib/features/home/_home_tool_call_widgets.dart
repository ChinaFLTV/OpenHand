part of 'openhand_home_page.dart';

class _ToolCallBody extends StatefulWidget {
  const _ToolCallBody({required this.message, required this.selectable});

  final AiSessionMessage message;
  final bool selectable;

  @override
  State<_ToolCallBody> createState() => _ToolCallBodyState();
}

class _ToolCallBodyState extends State<_ToolCallBody> {
  bool? _argumentsExpandedOverride;
  bool? _resultExpandedOverride;
  _ToolCallViewData? _cachedViewData;
  int? _cachedViewDataSignature;

  @override
  void didUpdateWidget(covariant _ToolCallBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id) {
      _argumentsExpandedOverride = null;
      _resultExpandedOverride = null;
      _cachedViewData = null;
      _cachedViewDataSignature = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = widget.message;
    final defaultExpanded = _shouldDefaultExpandToolStatus(
      _toolExecutionStatus(message),
    );
    final argumentsExpanded = _argumentsExpandedOverride ?? defaultExpanded;
    final resultExpanded = _resultExpandedOverride ?? defaultExpanded;
    final toolCall = _resolveToolCallViewData(
      context,
      message,
      argumentsExpanded: argumentsExpanded,
      resultExpanded: resultExpanded,
    );
    // Construction state: tool call message has been created from a stream
    // delta but the executor has not yet picked it up — `status` is empty,
    // arguments are still streaming. Render a subtler gray-tinted card +
    // pulsing badge so the user sees the call is forming, not stuck.
    final isConstructing =
        toolCall.status.isEmpty && !toolCall.hasResultContent;
    final cs = theme.colorScheme;
    final borderColor = isConstructing
        ? cs.outline.withValues(alpha: 0.35)
        : Colors.transparent;
    final tintColor = isConstructing
        ? cs.surfaceContainerHighest.withValues(alpha: 0.35)
        : Colors.transparent;
    return SettingsAwareAppearOnce(
      child: ClipRect(
        child: AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topLeft,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            padding: isConstructing
                ? const EdgeInsets.fromLTRB(10, 8, 10, 10)
                : EdgeInsets.zero,
            decoration: BoxDecoration(
              color: tintColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor),
            ),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ToolExecutionChip(
                    icon: toolCall.presentation.icon,
                    label: toolCall.primaryChipLabel,
                  ),
                  if (isConstructing)
                    _ToolConstructingBadge(
                      label: AppLocalizations.of(
                        context,
                      )!.tlCallArgumentsConstructing,
                      hint: AppLocalizations.of(
                        context,
                      )!.tlCallArgumentsConstructingHint,
                    ),
            if (toolCall.workingDirectory.isNotEmpty)
              _ToolExecutionChip(
                icon: Icons.folder_outlined,
                label:
                    '${AppLocalizations.of(context)!.tlCallDir}: ${toolCall.workingDirectory}',
              ),
            if (toolCall.status.isNotEmpty)
              _ToolExecutionChip(
                icon: toolCall.statusIcon,
                label: toolCall.outcomeLabel,
              ),
            if (toolCall.durationMs > 0 || toolCall.status == 'running')
              _ToolExecutionChip(
                icon: Icons.timer_outlined,
                label:
                    '${AppLocalizations.of(context)!.tlCallElapsed}: ${_formatToolExecutionDuration(toolCall.durationMs)}',
              ),
            if (toolCall.exitCode != null)
              _ToolExecutionChip(
                icon: Icons.flag_outlined,
                label:
                    '${AppLocalizations.of(context)!.tlCallExit}: ${toolCall.exitCode}',
              ),
          ],
        ),
        if (isConstructing) ...[
          const SizedBox(height: 10),
          _ConstructingArgumentKeysRow(
            keys: toolCall.argumentKeys,
            collectedLabel: AppLocalizations.of(
              context,
            )!.tlCallCollectedParameters,
            emptyLabel: AppLocalizations.of(context)!.tlCallNoParametersYet,
          ),
        ] else ...[
          const SizedBox(height: 10),
          _ExpandableToolSection(
            title: AppLocalizations.of(context)!.tlCallToolInput,
            preview: toolCall.argumentsPreview,
            expanded: argumentsExpanded,
            onToggle: () {
              setState(() {
                _argumentsExpandedOverride = !argumentsExpanded;
              });
            },
            expandedBuilder: (context) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (toolCall.command.isNotEmpty)
                  _ToolOutputPanel(
                    label: AppLocalizations.of(context)!.tlCallCommand,
                    content: toolCall.formattedCommand,
                    theme: theme,
                    selectable: widget.selectable,
                  ),
                if (toolCall.command.isNotEmpty) const SizedBox(height: 10),
                _ToolOutputPanel(
                  label: AppLocalizations.of(context)!.tlCallArguments,
                  content: toolCall.formattedArguments,
                  theme: theme,
                  selectable: widget.selectable,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _ExpandableToolSection(
            title: AppLocalizations.of(context)!.tlCallToolOutput,
            preview: toolCall.hasResultContent
                ? toolCall.resultPreview
                : AppLocalizations.of(context)!.tlCallNoOutputYet,
            expanded: resultExpanded,
            onToggle: () {
              setState(() {
                _resultExpandedOverride = !resultExpanded;
              });
            },
            expandedBuilder: (context) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (toolCall.stdout.isNotEmpty)
                  _ToolOutputPanel(
                    label: AppLocalizations.of(context)!.tlCallStdout,
                    content: toolCall.formattedStdout,
                    theme: theme,
                    selectable: widget.selectable,
                    fullContentFile: toolCall.stdoutFile,
                  ),
                if (toolCall.stderr.isNotEmpty) ...[
                  if (toolCall.stdout.isNotEmpty) const SizedBox(height: 10),
                  _ToolOutputPanel(
                    label: AppLocalizations.of(context)!.tlCallStderr,
                    content: toolCall.formattedStderr,
                    theme: theme,
                    isError: true,
                    selectable: widget.selectable,
                    fullContentFile: toolCall.stderrFile,
                  ),
                ],
                if (toolCall.showResultText) ...[
                  if (toolCall.stdout.isNotEmpty || toolCall.stderr.isNotEmpty)
                    const SizedBox(height: 10),
                  _ToolOutputPanel(
                    label: AppLocalizations.of(context)!.tlCallResult,
                    content: toolCall.formattedResult,
                    theme: theme,
                    selectable: widget.selectable,
                  ),
                ],
                if (toolCall.stdout.isEmpty &&
                    toolCall.stderr.isEmpty &&
                    !toolCall.showResultText)
                  Text(
                    AppLocalizations.of(context)!.tlCallThereIsNoToolOutputYet,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
        // ── File mutation indicator (mirrors HE changed-files row) ──
        if (_fileMutationPath(message).isNotEmpty &&
            _toolExecutionStatus(message) == 'success') ...[
          const SizedBox(height: 10),
          _FileMutationRow(message: message),
        ],
      ],
            ),
          ),
          ),
        ),
    );
  }

  _ToolCallViewData _resolveToolCallViewData(
    BuildContext context,
    AiSessionMessage message, {
    required bool argumentsExpanded,
    required bool resultExpanded,
  }) {
    final signature = Object.hashAll(<Object?>[
      Localizations.localeOf(context).toLanguageTag(),
      message.id,
      '${message.metadata['tool_name'] ?? ''}',
      '${message.metadata['tool_source'] ?? ''}',
      '${message.metadata['mcp_server_name'] ?? ''}',
      '${message.metadata['mcp_tool_name'] ?? ''}',
      '${message.metadata['mcp_tool_id'] ?? ''}',
      '${message.metadata['skill_name'] ?? ''}',
      '${message.metadata['tool_execution_status'] ?? ''}',
      '${message.metadata['tool_execution_command'] ?? ''}',
      '${message.metadata['tool_execution_working_directory'] ?? ''}',
      '${message.metadata['tool_execution_stdout'] ?? ''}',
      '${message.metadata['tool_execution_stderr'] ?? ''}',
      '${message.metadata['tool_execution_result'] ?? ''}',
      '${message.metadata['tool_arguments'] ?? ''}',
      '${message.metadata['tool_execution_exit_code'] ?? ''}',
      '${message.metadata['tool_execution_elapsed_ms'] ?? message.metadata['tool_execution_duration_ms'] ?? ''}',
      argumentsExpanded,
      resultExpanded,
    ]);
    if (_cachedViewData != null && _cachedViewDataSignature == signature) {
      return _cachedViewData!;
    }
    final viewData = _ToolCallViewData.from(
      context,
      message,
      includeArgumentsContent: argumentsExpanded,
      includeResultContent: resultExpanded,
    );
    _cachedViewData = viewData;
    _cachedViewDataSignature = signature;
    return viewData;
  }
}

class _ExpandableToolSection extends StatelessWidget {
  const _ExpandableToolSection({
    required this.title,
    required this.preview,
    required this.expanded,
    required this.onToggle,
    required this.expandedBuilder,
  });

  final String title;
  final String preview;
  final bool expanded;
  final VoidCallback onToggle;
  final WidgetBuilder expandedBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.78),
      borderRadius: const BorderRadius.all(Radius.circular(16)),
      child: InkWell(
        onTap: onToggle,
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (!expanded && preview.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    height: 1.35,
                  ),
                ),
              ],
              if (expanded) ...[
                const SizedBox(height: 12),
                Builder(builder: expandedBuilder),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolOutputPanel extends StatefulWidget {
  const _ToolOutputPanel({
    required this.label,
    required this.content,
    required this.theme,
    required this.selectable,
    this.isError = false,
    this.fullContentFile,
  });

  final String label;
  final _FormattedToolContent content;
  final ThemeData theme;
  final bool selectable;
  final bool isError;

  /// Optional file path containing full (non-truncated) content.
  final String? fullContentFile;

  @override
  State<_ToolOutputPanel> createState() => _ToolOutputPanelState();
}

class _ToolOutputPanelState extends State<_ToolOutputPanel> {
  bool _isExpanded = false;
  bool _isWrapped = false;
  List<String>? _cachedLines;
  String? _cachedLinesKey;

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
  }

  void _toggleWrapped() {
    setState(() {
      _isWrapped = !_isWrapped;
    });
  }

  void _showFullContentDialog(BuildContext context) {
    showAnimatedDialog(
      context: context,
      builder: (_) => _ToolContentFullDialog(
        label: widget.label,
        content: widget.content,
        isError: widget.isError,
        fullContentFile: widget.fullContentFile,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Cache line splitting to avoid re-splitting large tool output on every build.
    if (_cachedLinesKey != widget.content.text) {
      _cachedLinesKey = widget.content.text;
      _cachedLines = const LineSplitter().convert(widget.content.text);
    }
    final lines = _cachedLines!;
    final bool isLong = widget.content.text.length > 800 || lines.length > 15;

    final displayContent = isLong && !_isExpanded
        ? '${lines.take(15).join('\n')}${lines.length > 15 || widget.content.text.length > 800 ? '\n\n... [已折叠以优化显示体验，请点击“查看完整内容”]' : ''}'
        : widget.content.text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                widget.label,
                style: widget.theme.textTheme.labelLarge?.copyWith(
                  color: widget.isError
                      ? widget.theme.colorScheme.error
                      : widget.theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton.icon(
                  onPressed: _toggleWrapped,
                  icon: Icon(
                    _isWrapped
                        ? Icons.wrap_text_rounded
                        : Icons.segment_rounded,
                    size: 14,
                  ),
                  label: Text(
                    (_isWrapped ? AppLocalizations.of(context)!.tlCallUnwrap : AppLocalizations.of(context)!.tlCallWrapLines),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 28),
                    foregroundColor: widget.theme.colorScheme.primary,
                    textStyle: widget.theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (isLong) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _toggleExpanded,
                    icon: Icon(
                      _isExpanded
                          ? Icons.close_fullscreen_rounded
                          : Icons.open_in_full_rounded,
                      size: 14,
                    ),
                    label: Text(
                      (_isExpanded ? AppLocalizations.of(context)!.tlCallViewCompressedContent : AppLocalizations.of(context)!.tlCallViewFullContent),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 28),
                      foregroundColor: widget.theme.colorScheme.primary,
                      textStyle: widget.theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (_isExpanded) ...[
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => _showFullContentDialog(context),
                      icon: const Icon(Icons.open_in_new_rounded, size: 14),
                      label: Text(
                        AppLocalizations.of(context)!.tlCallViewInDialog,
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size(0, 28),
                        foregroundColor: widget.theme.colorScheme.tertiary,
                        textStyle: widget.theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        _HighlightedCodePanel(
          content: displayContent,
          theme: widget.theme,
          language: widget.content.language,
          selectable: widget.selectable,
          baseColor: widget.isError
              ? widget.theme.colorScheme.onErrorContainer
              : widget.theme.colorScheme.onSurface,
          accentColor: widget.isError ? widget.theme.colorScheme.error : null,
          wrapLines: _isWrapped,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ToolContentFullDialog — full-screen dialog showing complete tool output
// ─────────────────────────────────────────────────────────────────────────────

class _ToolContentFullDialog extends StatefulWidget {
  const _ToolContentFullDialog({
    required this.label,
    required this.content,
    this.isError = false,
    this.fullContentFile,
  });

  final String label;
  final _FormattedToolContent content;
  final bool isError;

  /// Optional file path containing the full (non-truncated) output.
  final String? fullContentFile;

  @override
  State<_ToolContentFullDialog> createState() => _ToolContentFullDialogState();
}

class _ToolContentFullDialogState extends State<_ToolContentFullDialog> {
  bool _wrapLines = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final screenSize = MediaQuery.sizeOf(context);

    return Dialog(
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.min(screenSize.width - 48, 960),
          maxHeight: screenSize.height - 80,
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(24)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ──
              Container(
                padding: const EdgeInsets.fromLTRB(24, 16, 8, 16),
                color: colorScheme.surfaceContainerLow,
                child: Row(
                  children: [
                    Icon(
                      widget.isError
                          ? Icons.error_outline_rounded
                          : Icons.code_rounded,
                      color: widget.isError
                          ? colorScheme.error
                          : colorScheme.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.label,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: widget.isError
                              ? colorScheme.error
                              : colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _wrapLines = !_wrapLines;
                        });
                      },
                      icon: Icon(
                        _wrapLines
                            ? Icons.wrap_text_rounded
                            : Icons.segment_rounded,
                        size: 16,
                      ),
                      label: Text(
                        isZh
                            ? (_wrapLines ? '取消换行' : '自动换行')
                            : (_wrapLines ? 'Unwrap' : 'Wrap'),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: colorScheme.primary,
                        textStyle: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                      tooltip: isZh ? '关闭' : 'Close',
                    ),
                  ],
                ),
              ),

              // ── Body ──
              Expanded(
                child: _ToolContentFullDialogBody(
                  content: widget.content,
                  isError: widget.isError,
                  wrapLines: _wrapLines,
                  fullContentFile: widget.fullContentFile,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders full content inside the dialog. When [fullContentFile] is provided,
/// reads the file to get non-truncated content. Falls back to in-memory
/// [content] on any error. Handles empty, loading, and render-failure states.
class _ToolContentFullDialogBody extends StatefulWidget {
  const _ToolContentFullDialogBody({
    required this.content,
    required this.isError,
    required this.wrapLines,
    this.fullContentFile,
  });

  final _FormattedToolContent content;
  final bool isError;
  final bool wrapLines;
  final String? fullContentFile;

  @override
  State<_ToolContentFullDialogBody> createState() =>
      _ToolContentFullDialogBodyState();
}

class _ToolContentFullDialogBodyState
    extends State<_ToolContentFullDialogBody> {
  bool _renderFailed = false;
  bool _loadingFile = false;
  _FormattedToolContent? _fileContent;
  bool _fileLoadAttempted = false;

  @override
  void initState() {
    super.initState();
    _tryLoadFullContent();
  }

  @override
  void didUpdateWidget(covariant _ToolContentFullDialogBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fullContentFile != widget.fullContentFile) {
      _fileLoadAttempted = false;
      _fileContent = null;
      _tryLoadFullContent();
    }
  }

  Future<void> _tryLoadFullContent() async {
    final filePath = widget.fullContentFile;
    if (filePath == null || filePath.isEmpty) return;
    if (_fileLoadAttempted) return;
    _fileLoadAttempted = true;
    setState(() => _loadingFile = true);
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final raw = await file.readAsString();
        if (!mounted) return;
        final formatted = _formatToolContent(raw);
        setState(() {
          _fileContent = formatted;
          _loadingFile = false;
        });
      } else {
        if (!mounted) return;
        setState(() => _loadingFile = false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingFile = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final effectiveContent = _fileContent ?? widget.content;
    final text = effectiveContent.text;

    if (_loadingFile) {
      return const Center(child: CircularProgressIndicator());
    }

    if (text.trim().isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context)!.tlCallEmptyContent,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    if (_renderFailed) {
      // Graceful fallback: plain selectable text when highlighted panel fails.
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            height: 1.5,
            color: widget.isError
                ? colorScheme.onErrorContainer
                : colorScheme.onSurface,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: _ToolContentSafeRender(
        onRenderError: () {
          if (mounted) {
            // Schedule setState for next frame to avoid build-phase conflicts.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _renderFailed = true);
            });
          }
        },
        child: _HighlightedCodePanel(
          content: text,
          theme: theme,
          language: effectiveContent.language,
          selectable: true,
          baseColor: widget.isError
              ? colorScheme.onErrorContainer
              : colorScheme.onSurface,
          accentColor: widget.isError ? colorScheme.error : null,
          wrapLines: widget.wrapLines,
        ),
      ),
    );
  }
}

/// Error boundary widget: catches render errors in child and calls [onRenderError].
class _ToolContentSafeRender extends StatefulWidget {
  const _ToolContentSafeRender({
    required this.child,
    required this.onRenderError,
  });

  final Widget child;
  final VoidCallback onRenderError;

  @override
  State<_ToolContentSafeRender> createState() => _ToolContentSafeRenderState();
}

class _ToolContentSafeRenderState extends State<_ToolContentSafeRender> {
  bool _hasError = false;

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return const SizedBox.shrink();
    }
    return widget.child;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _hasError = false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _FileMutationRow — shows file-change indicator for write/edit/multiedit tools
// ─────────────────────────────────────────────────────────────────────────────

String _fileMutationPath(AiSessionMessage message) =>
    '${message.metadata['file_mutation_path'] ?? ''}'.trim();

String _fileMutationKind(AiSessionMessage message) =>
    '${message.metadata['file_mutation_kind'] ?? ''}'.trim();

class _FileMutationRow extends StatelessWidget {
  const _FileMutationRow({required this.message});

  final AiSessionMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mutPath = _fileMutationPath(message);
    final mutKind = _fileMutationKind(message);

    final editCount = message.metadata['file_mutation_edit_count'];

    // Determine icon & color based on mutation kind.
    final (
      IconData icon,
      Color iconColor,
      String kindLabel,
    ) = switch (mutKind) {
      'write' => (
        Icons.add_circle_outline_rounded,
        const Color(0xFF4CAF50),
        AppLocalizations.of(context)!.tlCallWrite,
      ),
      'edit' => (
        Icons.edit_outlined,
        colorScheme.primary,
        AppLocalizations.of(context)!.tlCallEdit,
      ),
      'multi_edit' => (
        Icons.edit_note_outlined,
        colorScheme.primary,
        editCount is int && editCount > 1
            ? AppLocalizations.of(context)!.tlCallMultiEditEditcount(editCount)
            : AppLocalizations.of(context)!.tlCallMultiEdit,
      ),
      'notebook_edit' => (
        Icons.menu_book_outlined,
        colorScheme.tertiary,
        AppLocalizations.of(context)!.tlCallNotebookEdit,
      ),
      'bash_write' => (
        Icons.terminal_rounded,
        const Color(0xFFF57F17),
        AppLocalizations.of(context)!.tlCallBashWrite,
      ),
      _ => (
        Icons.difference_rounded,
        colorScheme.onSurfaceVariant,
        AppLocalizations.of(context)!.tlCallFileChanged,
      ),
    };

    // Extract a shorter display path.
    final displayPath = _shortenFilePath(mutPath);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        onTap: mutPath.isNotEmpty
            ? () => _showFileDiffDialog(context, mutPath, mutKind)
            : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.surface.withValues(alpha: 0.78),
            borderRadius: const BorderRadius.all(Radius.circular(16)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.difference_rounded,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                AppLocalizations.of(context)!.tlCallChangedFile,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 12),
              Icon(icon, size: 14, color: iconColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  displayPath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: _borderRadius999,
                ),
                child: Text(
                  kindLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: iconColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFileDiffDialog(BuildContext context, String filePath, String kind) {
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    showAnimatedDialog(
      context: context,
      builder: (ctx) =>
          _FileDiffDialog(filePath: filePath, changeKind: kind, isZh: isZh),
    );
  }

  /// Shorten an absolute path to the last 3 segments for readability.
  static String _shortenFilePath(String filePath) {
    if (filePath.isEmpty) return filePath;
    // Normalise to forward slashes for splitting (handles Windows paths too).
    final normalised = filePath.replaceAll('\\', '/');
    final parts = normalised.split('/');
    if (parts.length <= 3) return normalised;
    return '.../${parts.sublist(parts.length - 3).join('/')}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _FileDiffDialog — displays file content diff when file change card is tapped
// ─────────────────────────────────────────────────────────────────────────────

class _FileDiffDialog extends StatefulWidget {
  const _FileDiffDialog({
    required this.filePath,
    required this.changeKind,
    required this.isZh,
  });

  final String filePath;
  final String changeKind;
  final bool isZh;

  @override
  State<_FileDiffDialog> createState() => _FileDiffDialogState();
}

class _FileDiffDialogState extends State<_FileDiffDialog> {
  bool _loading = true;
  String? _beforeContent;
  String? _afterContent;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDiff();
  }

  Future<void> _loadDiff() async {
    try {
      // Create a new instance since AiFileHistoryService is not a singleton.
      final historyService = AiFileHistoryService();
      final versions = await historyService.getVersionHistory(widget.filePath);

      if (versions.isEmpty) {
        // No history, try to read current file content as 'after'.
        final file = File(widget.filePath);
        if (await file.exists()) {
          final content = await file.readAsString();
          if (!mounted) return;
          setState(() {
            _beforeContent = null;
            _afterContent = content;
            _loading = false;
          });
        } else {
          if (!mounted) return;
          setState(() {
            _error = widget.isZh ? '没有保存的版本历史' : 'No saved version history';
            _loading = false;
          });
        }
        return;
      }

      // Get oldest version as "before" and read current file as "after".
      // This shows what changed from the saved snapshot to current state.
      final oldest = versions.last;

      final (beforeContent, _) = await historyService.readVersionContent(
        filePath: widget.filePath,
        versionId: oldest.versionId,
      );

      // Read current file content as "after"
      String? afterContent;
      final currentFile = File(widget.filePath);
      if (await currentFile.exists()) {
        afterContent = await currentFile.readAsString();
      }

      if (!mounted) return;
      setState(() {
        _beforeContent = beforeContent;
        _afterContent = afterContent;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyFileDiffError(e, isZh: widget.isZh);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840, maxHeight: 640),
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(24)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
                color: colorScheme.surfaceContainerLow,
                child: Row(
                  children: [
                    Icon(
                      Icons.difference_rounded,
                      color: colorScheme.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.isZh ? '文件变更对比' : 'File Diff',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _FileMutationRow._shortenFilePath(widget.filePath),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                      tooltip: widget.isZh ? '关闭' : 'Close',
                    ),
                  ],
                ),
              ),

              // Diff content
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _error!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.error,
                            ),
                          ),
                        ),
                      )
                    : _buildDiffView(theme, colorScheme),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDiffView(ThemeData theme, ColorScheme colorScheme) {
    // Compute line-by-line diff.
    final diff = _computeSimpleDiff(_beforeContent ?? '', _afterContent ?? '');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText.rich(
        TextSpan(
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            height: 1.6,
          ),
          children: diff.map((line) {
            Color? bgColor;
            Color? textColor;
            if (line.startsWith('+')) {
              bgColor = colorScheme.primaryContainer.withValues(alpha: 0.35);
              textColor = colorScheme.onPrimaryContainer;
            } else if (line.startsWith('-')) {
              bgColor = colorScheme.errorContainer.withValues(alpha: 0.35);
              textColor = colorScheme.onErrorContainer;
            } else if (line.startsWith('@@')) {
              textColor = colorScheme.primary;
            }
            return TextSpan(
              text: '$line\n',
              style: TextStyle(backgroundColor: bgColor, color: textColor),
            );
          }).toList(),
        ),
      ),
    );
  }

  /// Compute a simple unified diff from before/after content.
  List<String> _computeSimpleDiff(String before, String after) {
    final beforeLines = const LineSplitter().convert(before);
    final afterLines = const LineSplitter().convert(after);
    final result = <String>[];

    // Simple LCS-based diff (good enough for small files).
    final lcs = _longestCommonSubsequence(beforeLines, afterLines);

    int bi = 0, ai = 0, li = 0;
    while (bi < beforeLines.length || ai < afterLines.length) {
      if (li < lcs.length &&
          bi < beforeLines.length &&
          ai < afterLines.length &&
          beforeLines[bi] == lcs[li] &&
          afterLines[ai] == lcs[li]) {
        result.add('  ${lcs[li]}');
        bi++;
        ai++;
        li++;
      } else {
        // Removed lines from before
        while (bi < beforeLines.length &&
            (li >= lcs.length || beforeLines[bi] != lcs[li])) {
          result.add('- ${beforeLines[bi]}');
          bi++;
        }
        // Added lines in after
        while (ai < afterLines.length &&
            (li >= lcs.length || afterLines[ai] != lcs[li])) {
          result.add('+ ${afterLines[ai]}');
          ai++;
        }
      }
    }

    return result;
  }

  /// Compute LCS for line-by-line comparison.
  List<String> _longestCommonSubsequence(List<String> a, List<String> b) {
    final m = a.length, n = b.length;
    final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));

    for (int i = 1; i <= m; i++) {
      for (int j = 1; j <= n; j++) {
        if (a[i - 1] == b[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1] + 1;
        } else {
          dp[i][j] = dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1];
        }
      }
    }

    // Backtrack to find LCS
    final lcs = <String>[];
    int i = m, j = n;
    while (i > 0 && j > 0) {
      if (a[i - 1] == b[j - 1]) {
        lcs.insert(0, a[i - 1]);
        i--;
        j--;
      } else if (dp[i - 1][j] > dp[i][j - 1]) {
        i--;
      } else {
        j--;
      }
    }
    return lcs;
  }
}

class _ToolExecutionChip extends StatelessWidget {
  const _ToolExecutionChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: _borderRadius999,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

/// Pulsing gray pill shown next to the primary chip while a tool call is
/// still being constructed (arguments streaming in but executor not yet
/// running it). Signals "forming, not stuck".
class _ToolConstructingBadge extends StatefulWidget {
  const _ToolConstructingBadge({required this.label, required this.hint});

  final String label;
  final String hint;

  @override
  State<_ToolConstructingBadge> createState() => _ToolConstructingBadgeState();
}

class _ToolConstructingBadgeState extends State<_ToolConstructingBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Tooltip(
      message: widget.hint,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = _ctrl.value;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(
                alpha: 0.55 + 0.35 * t,
              ),
              borderRadius: _borderRadius999,
              border: Border.all(
                color: cs.outline.withValues(alpha: 0.3 + 0.25 * t),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      cs.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Inline row used while a tool call is still in its "constructing" phase:
/// shows the parameter keys parsed so far (e.g. `path, query`), or a muted
/// "no parameters yet" placeholder. Each key fades in via [AppearOnce] so
/// new arrivals feel alive without re-laying out neighbours.
class _ConstructingArgumentKeysRow extends StatelessWidget {
  const _ConstructingArgumentKeysRow({
    required this.keys,
    required this.collectedLabel,
    required this.emptyLabel,
  });

  final List<({String key, String? valuePreview})> keys;
  final String collectedLabel;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final mutedStyle = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
      fontStyle: FontStyle.italic,
    );
    if (keys.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Text(emptyLabel, style: mutedStyle),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 2, left: 2),
          child: Text(
            '$collectedLabel:',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        for (final entry in keys)
          AppearOnce(
            key: ValueKey<String>('arg-key-${entry.key}'),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh.withValues(alpha: 0.7),
                borderRadius: _borderRadius999,
                border: Border.all(
                  color: cs.outline.withValues(alpha: 0.25),
                ),
              ),
              child: RichText(
                text: TextSpan(
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurface,
                    fontFamily: 'JetBrainsMono',
                  ),
                  children: [
                    TextSpan(text: entry.key),
                    if (entry.valuePreview != null) ...[
                      TextSpan(
                        text: ': ',
                        style: TextStyle(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                        ),
                      ),
                      TextSpan(
                        text: entry.valuePreview,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ToolCallPresentation {
  const _ToolCallPresentation({
    required this.categoryLabel,
    required this.displayName,
    required this.icon,
    this.isCommandLike = false,
  });

  final String categoryLabel;
  final String displayName;
  final IconData icon;
  final bool isCommandLike;
}

class _ToolCallViewData {
  const _ToolCallViewData({
    required this.presentation,
    required this.status,
    required this.command,
    required this.workingDirectory,
    required this.stdout,
    required this.stderr,
    required this.resultText,
    required this.exitCode,
    required this.durationMs,
    required this.argumentsPreview,
    required this.argumentKeys,
    required this.formattedCommand,
    required this.formattedArguments,
    required this.formattedStdout,
    required this.formattedStderr,
    required this.formattedResult,
    required this.defaultExpanded,
    required this.showResultText,
    required this.hasResultContent,
    required this.shouldSweepBadge,
    required this.statusIcon,
    required this.primaryChipLabel,
    required this.statusLabel,
    required this.outcomeLabel,
    required this.resultPreview,
    this.stdoutFile,
    this.stderrFile,
  });

  factory _ToolCallViewData.from(
    BuildContext context,
    AiSessionMessage message, {
    bool includeArgumentsContent = true,
    bool includeResultContent = true,
  }) {
    final presentation = _toolCallPresentation(context, message);
    final isPreparing = message.metadata['tool_preparing'] == true;
    final effectivePresentation = isPreparing
        ? _ToolCallPresentation(
            categoryLabel: AppLocalizations.of(context)!.tlCallTool,
            displayName: AppLocalizations.of(context)!.tlCallPreparing,
            icon: Icons.hourglass_empty_rounded,
          )
        : presentation;
    final status = _toolExecutionStatus(message);
    final command = _toolExecutionCommand(message);
    final workingDirectory = _toolExecutionWorkingDirectory(message);
    final stdout = _toolExecutionStdout(message).trimRight();
    final stderr = _toolExecutionStderr(message).trimRight();
    final resultText = _toolExecutionResult(message).trimRight();
    final exitCode = _toolExecutionExitCode(message);
    final durationMs = _toolExecutionDurationMs(message);
    final argumentsPreview = _toolArgumentsPreview(message);
    final argumentKeys = _parseArgumentKeys(
      '${message.metadata['tool_arguments'] ?? ''}',
    );
    final formattedCommand = !includeArgumentsContent || command.isEmpty
        ? const _FormattedToolContent(text: '')
        : _FormattedToolContent(text: '\$ $command', language: 'bash');
    final formattedArguments = includeArgumentsContent
        ? _formatToolContent(
            '${message.metadata['tool_arguments'] ?? ''}',
            emptyFallback: '{}',
          )
        : const _FormattedToolContent(text: '{}');
    final formattedStdout = includeResultContent
        ? _formatToolContent(stdout)
        : const _FormattedToolContent(text: '');
    final formattedStderr = includeResultContent
        ? _formatToolContent(stderr)
        : const _FormattedToolContent(text: '');
    final formattedResult = includeResultContent
        ? _formatToolContent(resultText)
        : const _FormattedToolContent(text: '');
    final isStructuredWrapper =
        resultText.startsWith('status: ') &&
        resultText.contains('\ncommand: ') &&
        resultText.contains('\nduration_ms: ');
    final showResultText =
        resultText.isNotEmpty &&
        resultText != stdout.trim() &&
        resultText != stderr.trim() &&
        !isStructuredWrapper;
    final hasResultContent =
        stdout.isNotEmpty ||
        stderr.isNotEmpty ||
        resultText.isNotEmpty ||
        exitCode != null ||
        status.isNotEmpty;
    final stdoutFile = '${message.metadata['tool_execution_stdout_file'] ?? ''}'
        .trim();
    final stderrFile = '${message.metadata['tool_execution_stderr_file'] ?? ''}'
        .trim();
    final viewData = _ToolCallViewData(
      presentation: effectivePresentation,
      status: status,
      command: command,
      workingDirectory: workingDirectory,
      stdout: stdout,
      stderr: stderr,
      resultText: resultText,
      exitCode: exitCode,
      durationMs: durationMs,
      argumentsPreview: argumentsPreview,
      argumentKeys: argumentKeys,
      formattedCommand: formattedCommand,
      formattedArguments: formattedArguments,
      formattedStdout: formattedStdout,
      formattedStderr: formattedStderr,
      formattedResult: formattedResult,
      defaultExpanded: _shouldDefaultExpandToolStatus(status),
      showResultText: showResultText,
      hasResultContent: hasResultContent,
      stdoutFile: stdoutFile.isNotEmpty ? stdoutFile : null,
      stderrFile: stderrFile.isNotEmpty ? stderrFile : null,
      shouldSweepBadge: _shouldSweepToolStatus(status),
      statusIcon: _toolExecutionStatusIcon(status),
      primaryChipLabel: _buildPrimaryChipLabel(context, effectivePresentation),
      statusLabel: _toolCallStatusLabelForData(
        context,
        effectivePresentation,
        status,
        durationMs,
      ),
      outcomeLabel: _toolExecutionOutcomeLabel(context, status),
      resultPreview: _toolExecutionPreviewText(
        context,
        status: status,
        stdout: stdout,
        stderr: stderr,
        resultText: resultText,
      ),
    );
    return viewData;
  }

  final _ToolCallPresentation presentation;
  final String status;
  final String command;
  final String workingDirectory;
  final String stdout;
  final String stderr;
  final String resultText;
  final int? exitCode;
  final int durationMs;
  final String argumentsPreview;

  /// Argument names (top-level keys) that have been parsed so far. Useful
  /// during the streaming "constructing" state to surface a real-time
  /// preview of which parameters the model has already supplied.
  final List<({String key, String? valuePreview})> argumentKeys;
  final _FormattedToolContent formattedCommand;
  final _FormattedToolContent formattedArguments;
  final _FormattedToolContent formattedStdout;
  final _FormattedToolContent formattedStderr;
  final _FormattedToolContent formattedResult;
  final bool defaultExpanded;
  final bool showResultText;
  final bool hasResultContent;
  final bool shouldSweepBadge;
  final IconData statusIcon;
  final String primaryChipLabel;
  final String statusLabel;
  final String outcomeLabel;
  final String resultPreview;

  /// File path containing full stdout when it was truncated at collection time.
  final String? stdoutFile;

  /// File path containing full stderr when it was truncated at collection time.
  final String? stderrFile;
}

String _toolCallName(AiSessionMessage message) =>
    '${message.metadata['tool_name'] ?? ''}'.trim();

String _toolExecutionStatus(AiSessionMessage message) =>
    '${message.metadata['tool_execution_status'] ?? ''}'.trim();

bool _shouldSweepToolStatus(String status) {
  return status.isEmpty || status == 'running';
}

String _toolExecutionCommand(AiSessionMessage message) {
  final executionCommand = '${message.metadata['tool_execution_command'] ?? ''}'
      .trim();
  if (executionCommand.isNotEmpty) {
    return executionCommand;
  }
  final rawArguments = '${message.metadata['tool_arguments'] ?? ''}'.trim();
  if (rawArguments.isEmpty) {
    return '';
  }
  return parseBashToolCommandFromArguments(rawArguments);
}

String _toolExecutionWorkingDirectory(AiSessionMessage message) {
  final executionDirectory =
      '${message.metadata['tool_execution_working_directory'] ?? ''}'.trim();
  if (executionDirectory.isNotEmpty) {
    return executionDirectory;
  }
  final rawArguments = '${message.metadata['tool_arguments'] ?? ''}'.trim();
  if (rawArguments.isEmpty) {
    return '';
  }
  return parseBashToolWorkingDirectoryFromArguments(rawArguments);
}

String _toolExecutionStdout(AiSessionMessage message) =>
    '${message.metadata['tool_execution_stdout'] ?? ''}';

String _toolExecutionStderr(AiSessionMessage message) =>
    '${message.metadata['tool_execution_stderr'] ?? ''}';

String _toolExecutionResult(AiSessionMessage message) =>
    '${message.metadata['tool_execution_result'] ?? ''}';

bool _isStreamingReasoningMessage(AiSessionMessage message) {
  return message.kind == AiSessionMessageKind.reasoning &&
      message.metadata[aiSessionMessageMetadataStreamingKey] == true;
}

bool _shouldTrackMessageLayout({
  required AiSessionMessage message,
  required AiSendPhase sendPhase,
  required bool isLastVisibleMessage,
}) {
  if (_isStreamingReasoningMessage(message)) {
    return true;
  }
  if (message.kind == AiSessionMessageKind.toolCall) {
    final status = _toolExecutionStatus(message);
    if (status.isEmpty || status == 'running') {
      return true;
    }
  }
  if (sendPhase != AiSendPhase.idle && isLastVisibleMessage) {
    return switch (message.kind) {
      AiSessionMessageKind.assistant || AiSessionMessageKind.status => true,
      _ => false,
    };
  }
  return false;
}

bool _shouldDefaultExpandReasoning(AiSessionMessage message) {
  return _isStreamingReasoningMessage(message);
}

bool _shouldDefaultExpandToolStatus(String status) {
  return status.isEmpty;
}

int _reasoningElapsedMs(AiSessionMessage message) {
  final elapsed = DateTime.now()
      .toUtc()
      .difference(message.createdAt.toUtc())
      .inMilliseconds;
  return math.max(0, elapsed);
}

int? _toolExecutionExitCode(AiSessionMessage message) {
  final value = message.metadata['tool_execution_exit_code'];
  if (value is int) {
    return value;
  }
  return int.tryParse('${value ?? ''}'.trim());
}

IconData _toolExecutionStatusIcon(String status) {
  return switch (status) {
    'running' => Icons.play_circle_outline_rounded,
    'cancelled' => Icons.stop_circle_outlined,
    'success' => Icons.check_circle_outline_rounded,
    'denied' => Icons.block_rounded,
    'rejected' => Icons.cancel_outlined,
    'timed_out' => Icons.timer_off_outlined,
    'failed' => Icons.error_outline_rounded,
    'invalid_arguments' => Icons.warning_amber_rounded,
    _ => Icons.terminal_rounded,
  };
}

/// Builds a compact, non-redundant chip label for a tool call bubble.
///
/// - When [_ToolCallPresentation.categoryLabel] equals [_ToolCallPresentation.displayName]
///   (the common built-in tool case, e.g. both are "Bash"), render the label once
///   to avoid producing noisy strings such as "Bash: Bash".
/// - For the generic "Tool" / "工具" fallback (used when the model emits an
///   unrecognized tool name), drop the generic category prefix and surface only
///   the actual name so the chip does not bleed scaffolding like "Tool: Bash"
///   into the transcript.
/// - Otherwise keep the `Category: DisplayName` form so MCP/Skill/Hook chips
///   remain easy to scan.
String _buildPrimaryChipLabel(
  BuildContext context,
  _ToolCallPresentation presentation,
) {
  final category = presentation.categoryLabel.trim();
  final display = presentation.displayName.trim();
  if (category.isEmpty || category == display) {
    return display.isEmpty ? category : display;
  }
  final genericCategory = AppLocalizations.of(context)!.tlCallTool;
  if (category == genericCategory) {
    return display.isEmpty ? category : display;
  }
  return '$category: $display';
}

_ToolCallPresentation _toolCallPresentation(
  BuildContext context,
  AiSessionMessage message,
) {
  final rawToolName = _toolCallName(message);
  final normalizedToolName = rawToolName.trim().toLowerCase();
  final toolSource = '${message.metadata['tool_source'] ?? ''}'
      .trim()
      .toLowerCase();
  if (toolSource == 'skill' || normalizedToolName.startsWith('skill__')) {
    final skillName = '${message.metadata['skill_name'] ?? ''}'.trim();
    return _ToolCallPresentation(
      categoryLabel: AppLocalizations.of(context)!.tlCallSkill,
      displayName: skillName.isEmpty ? rawToolName : skillName,
      icon: Icons.extension_rounded,
    );
  }
  if (toolSource == 'hook' || normalizedToolName.startsWith('hook__')) {
    final hookName = '${message.metadata['hook_name'] ?? ''}'.trim();
    return _ToolCallPresentation(
      categoryLabel: 'Hook',
      displayName: hookName.isEmpty ? rawToolName : hookName,
      icon: Icons.webhook_rounded,
    );
  }
  if (toolSource == 'mcp' || normalizedToolName.startsWith('mcp__')) {
    final serverName = '${message.metadata['mcp_server_name'] ?? ''}'.trim();
    final toolName = '${message.metadata['mcp_tool_name'] ?? ''}'.trim();
    final toolId = '${message.metadata['mcp_tool_id'] ?? ''}'.trim();
    final displayName = <String>[
      if (serverName.isNotEmpty) serverName,
      if (toolName.isNotEmpty) toolName else if (toolId.isNotEmpty) toolId,
    ].join(' / ');
    return _ToolCallPresentation(
      categoryLabel: 'MCP',
      displayName: displayName.isEmpty ? rawToolName : displayName,
      icon: Icons.account_tree_outlined,
    );
  }
  return switch (normalizedToolName) {
    'bash' => const _ToolCallPresentation(
      categoryLabel: 'Bash',
      displayName: 'Bash',
      icon: Icons.terminal_rounded,
      isCommandLike: true,
    ),
    'grep' => const _ToolCallPresentation(
      categoryLabel: 'Grep',
      displayName: 'Grep',
      icon: Icons.manage_search_rounded,
    ),
    'ls' => const _ToolCallPresentation(
      categoryLabel: 'LS',
      displayName: 'LS',
      icon: Icons.folder_open_rounded,
    ),
    'read' => const _ToolCallPresentation(
      categoryLabel: 'Read',
      displayName: 'Read',
      icon: Icons.article_outlined,
    ),
    'write' => const _ToolCallPresentation(
      categoryLabel: 'Write',
      displayName: 'Write',
      icon: Icons.edit_note_rounded,
    ),
    'edit' => const _ToolCallPresentation(
      categoryLabel: 'Edit',
      displayName: 'Edit',
      icon: Icons.edit_outlined,
    ),
    'multiedit' => const _ToolCallPresentation(
      categoryLabel: 'MultiEdit',
      displayName: 'MultiEdit',
      icon: Icons.edit_note_outlined,
    ),
    'notebookedit' => const _ToolCallPresentation(
      categoryLabel: 'NotebookEdit',
      displayName: 'NotebookEdit',
      icon: Icons.menu_book_outlined,
    ),
    'webfetch' => const _ToolCallPresentation(
      categoryLabel: 'WebFetch',
      displayName: 'WebFetch',
      icon: Icons.language_rounded,
    ),
    'websearch' => const _ToolCallPresentation(
      categoryLabel: 'WebSearch',
      displayName: 'WebSearch',
      icon: Icons.travel_explore_rounded,
    ),
    'todowrite' => const _ToolCallPresentation(
      categoryLabel: 'TodoWrite',
      displayName: 'TodoWrite',
      icon: Icons.checklist_rounded,
    ),
    'task' => const _ToolCallPresentation(
      categoryLabel: 'Task',
      displayName: 'Task',
      icon: Icons.hub_outlined,
    ),
    'glob' => const _ToolCallPresentation(
      categoryLabel: 'Glob',
      displayName: 'Glob',
      icon: Icons.filter_alt_outlined,
    ),
    'exitplanmode' => const _ToolCallPresentation(
      categoryLabel: 'ExitPlanMode',
      displayName: 'ExitPlanMode',
      icon: Icons.assignment_turned_in_outlined,
    ),
    'askuserchoice' => const _ToolCallPresentation(
      categoryLabel: 'AskUserChoice',
      displayName: 'AskUserChoice',
      icon: Icons.quiz_outlined,
    ),
    _ => _ToolCallPresentation(
      categoryLabel: AppLocalizations.of(context)!.tlCallTool,
      displayName: rawToolName.isEmpty
          ? AppLocalizations.of(context)!.tlCallTool
          : rawToolName,
      icon: Icons.build_circle_outlined,
    ),
  };
}

class _FormattedToolContent {
  const _FormattedToolContent({required this.text, this.language});

  final String text;
  final String? language;
}

// Bounded memo for _formatToolContent. During AI streaming the parent rebuilds
// every ~72 ms and each tool-call bubble re-runs JSON/XML/YAML/TOML detection
// on identical stdout/stderr/result text; memoising by raw content + fallback
// avoids re-parsing and re-encoding on every frame. Capped to prevent
// unbounded growth from unique tool output.
const int _formatToolContentCacheCap = 128;
final Map<String, _FormattedToolContent> _formatToolContentCache =
    <String, _FormattedToolContent>{};

_FormattedToolContent _formatToolContent(
  String rawContent, {
  String emptyFallback = '',
}) {
  // Short-circuit: cheap to recompute for tiny strings, and the cache key
  // overhead would dominate.
  if (rawContent.length < 8 && emptyFallback.isEmpty) {
    return _formatToolContentImpl(rawContent, emptyFallback: emptyFallback);
  }
  final cacheKey = emptyFallback.isEmpty
      ? rawContent
      : '${rawContent.length}|$emptyFallback\u0000$rawContent';
  final cached = _formatToolContentCache[cacheKey];
  if (cached != null) {
    return cached;
  }
  final computed = _formatToolContentImpl(
    rawContent,
    emptyFallback: emptyFallback,
  );
  if (_formatToolContentCache.length >= _formatToolContentCacheCap) {
    // Drop an arbitrary entry. Unordered Map iteration is O(1) for first key,
    // and strict LRU isn't worth the bookkeeping here — streaming workloads
    // see the same few keys repeatedly within a short window.
    _formatToolContentCache.remove(_formatToolContentCache.keys.first);
  }
  _formatToolContentCache[cacheKey] = computed;
  return computed;
}

_FormattedToolContent _formatToolContentImpl(
  String rawContent, {
  String emptyFallback = '',
}) {
  final normalized = rawContent
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .trimRight();
  final trimmed = normalized.trim();
  if (trimmed.isEmpty) {
    return _FormattedToolContent(text: emptyFallback);
  }
  final jsonContent = _tryFormatJsonContent(trimmed);
  if (jsonContent != null) {
    return _FormattedToolContent(text: jsonContent, language: 'json');
  }
  final xmlContent = _tryFormatXmlContent(trimmed);
  if (xmlContent != null) {
    return _FormattedToolContent(text: xmlContent, language: 'xml');
  }
  final yamlContent = _tryFormatYamlContent(trimmed);
  if (yamlContent != null) {
    return _FormattedToolContent(text: yamlContent, language: 'yaml');
  }
  if (_looksLikeTomlContent(trimmed)) {
    return _FormattedToolContent(text: normalized, language: 'toml');
  }
  return _FormattedToolContent(text: normalized);
}

String? _tryFormatJsonContent(String content) {
  if (!_looksLikeJsonContent(content)) {
    return null;
  }
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(content));
  } catch (_) {
    return null;
  }
}

bool _looksLikeJsonContent(String content) {
  if (content.length < 2) {
    return false;
  }
  final startsWithObject = content.startsWith('{') && content.endsWith('}');
  final startsWithArray = content.startsWith('[') && content.endsWith(']');
  return startsWithObject || startsWithArray;
}

String? _tryFormatXmlContent(String content) {
  if (!_looksLikeXmlContent(content)) {
    return null;
  }
  try {
    return xml.XmlDocument.parse(
      content,
    ).toXmlString(pretty: true, indent: '  ');
  } catch (_) {
    try {
      return xml.XmlDocumentFragment.parse(
        content,
      ).toXmlString(pretty: true, indent: '  ');
    } catch (_) {
      return null;
    }
  }
}

bool _looksLikeXmlContent(String content) {
  return content.startsWith('<') &&
      content.endsWith('>') &&
      _xmlStartTagProbePattern.hasMatch(content);
}

String? _tryFormatYamlContent(String content) {
  if (!_looksLikeYamlContent(content)) {
    return null;
  }
  try {
    final decoded = loadYamlNode(content);
    final value = decoded.value;
    if (value is! YamlMap &&
        value is! YamlList &&
        !_isYamlMultilineScalar(value)) {
      return null;
    }
    return _renderYamlNode(value, 0);
  } catch (_) {
    return null;
  }
}

bool _looksLikeYamlContent(String content) {
  final lines = const LineSplitter()
      .convert(content)
      .map((line) => line.trimLeft())
      .where((line) => line.isNotEmpty)
      .take(12)
      .toList(growable: false);
  if (lines.isEmpty) {
    return false;
  }
  var structuredLineCount = 0;
  for (final line in lines) {
    if (line == '---' || line == '...') {
      structuredLineCount += 1;
      continue;
    }
    if (line.startsWith('- ') || _yamlKeyPrefixPattern.hasMatch(line)) {
      structuredLineCount += 1;
    }
  }
  return structuredLineCount > 0;
}

bool _looksLikeTomlContent(String content) {
  final lines = const LineSplitter()
      .convert(content)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('#'))
      .take(12)
      .toList(growable: false);
  if (lines.isEmpty) {
    return false;
  }
  return lines.every(
    (line) =>
        _tomlSectionPattern.hasMatch(line) ||
        _tomlKeyValuePattern.hasMatch(line),
  );
}

bool _isYamlMultilineScalar(Object? value) {
  return value is String && value.contains('\n');
}

String _renderYamlNode(Object? value, int indent) {
  final padding = ' ' * indent;
  if (value is YamlMap) {
    if (value.isEmpty) {
      return '$padding{}';
    }
    final buffer = StringBuffer();
    var isFirst = true;
    for (final entry in value.entries) {
      if (!isFirst) {
        buffer.writeln();
      }
      final key = _renderYamlKey(entry.key);
      final entryValue = entry.value;
      if (_isYamlInlineValue(entryValue)) {
        buffer.write('$padding$key: ${_renderYamlScalar(entryValue)}');
      } else {
        buffer.write(
          '$padding$key:\n${_renderYamlNode(entryValue, indent + 2)}',
        );
      }
      isFirst = false;
    }
    return buffer.toString();
  }
  if (value is YamlList) {
    if (value.isEmpty) {
      return '$padding[]';
    }
    final buffer = StringBuffer();
    for (var index = 0; index < value.length; index += 1) {
      if (index > 0) {
        buffer.writeln();
      }
      final item = value[index];
      if (_isYamlInlineValue(item)) {
        buffer.write('$padding- ${_renderYamlScalar(item)}');
      } else {
        buffer.write('$padding-\n${_renderYamlNode(item, indent + 2)}');
      }
    }
    return buffer.toString();
  }
  if (value is String && value.contains('\n')) {
    final childPadding = ' ' * (indent + 2);
    final lines = value.split('\n');
    return '$padding|\n${lines.map((line) => '$childPadding$line').join('\n')}';
  }
  return '$padding${_renderYamlScalar(value)}';
}

bool _isYamlInlineValue(Object? value) {
  return switch (value) {
    null => true,
    bool() => true,
    num() => true,
    String() => !value.contains('\n'),
    _ => false,
  };
}

String _renderYamlKey(Object? value) {
  final key = '${value ?? ''}';
  if (_tomlBareKeyPattern.hasMatch(key)) {
    return key;
  }
  return jsonEncode(key);
}

String _renderYamlScalar(Object? value) {
  return switch (value) {
    null => 'null',
    bool() => value ? 'true' : 'false',
    num() => '$value',
    String() => jsonEncode(value),
    DateTime() => jsonEncode(value.toIso8601String()),
    _ => jsonEncode('$value'),
  };
}

String _toolArgumentsPreview(AiSessionMessage message) {
  final command = _toolExecutionCommand(message);
  if (command.isNotEmpty) {
    return '\$ $command';
  }
  final rawArguments = '${message.metadata['tool_arguments'] ?? ''}'.trim();
  if (rawArguments.isNotEmpty) {
    try {
      final decoded = jsonDecode(rawArguments);
      if (decoded is Map) {
        final entries = Map<String, Object?>.from(decoded).entries.take(2);
        final summary = entries
            .map((entry) => '${entry.key}: ${entry.value}')
            .join(', ');
        if (summary.isNotEmpty) {
          return summary;
        }
      }
      if (decoded is List) {
        return '[${decoded.length} items]';
      }
    } catch (_) {
      // Fallback to the prettified text preview below.
    }
  }
  final preview = rawArguments.isEmpty ? '{}' : rawArguments;
  final firstLine = const LineSplitter()
      .convert(preview)
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '{}');
  return firstLine;
}

/// Best-effort parse of top-level argument key/value previews from a
/// JSON-encoded `tool_arguments` blob. Used to surface a real-time
/// preview of which parameters have been parsed during the streaming
/// "constructing" state. Each value is truncated to ~16 chars and
/// nested maps/lists are summarized as `{…}` / `[…]` so the row stays
/// compact.
List<({String key, String? valuePreview})> _parseArgumentKeys(
  String rawArguments,
) {
  final trimmed = rawArguments.trim();
  if (trimmed.isEmpty) {
    return const <({String key, String? valuePreview})>[];
  }
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map) {
      return decoded.entries
          .map(
            (e) => (
              key: '${e.key}',
              valuePreview: _summarizeArgumentValue(e.value),
            ),
          )
          .toList(growable: false);
    }
  } catch (_) {
    // Partial JSON mid-stream — expected; fall through.
  }
  return const <({String key, String? valuePreview})>[];
}

String? _summarizeArgumentValue(Object? value) {
  if (value == null) return null;
  if (value is Map) return '{…}';
  if (value is List) return value.isEmpty ? '[]' : '[${value.length}]';
  final raw = value is String ? value : '$value';
  final flat = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.isEmpty) return null;
  const maxLen = 16;
  if (flat.length <= maxLen) return flat;
  return '${flat.substring(0, maxLen)}…';
}

String _toolCallStatusLabelForData(
  BuildContext context,
  _ToolCallPresentation presentation,
  String status,
  int durationMs,
) {
  final suffix = durationMs <= 0
      ? ''
      : ' (${_formatToolExecutionDuration(durationMs)})';
  final toolLabel = presentation.displayName.trim().isEmpty
      ? presentation.categoryLabel
      : presentation.displayName.trim();
  final statusLabel = _toolCallStatusActionLabel(
    context,
    status,
    isCommandLike: presentation.isCommandLike,
  );
  return suffix.isEmpty
      ? '$toolLabel · $statusLabel'
      : '$toolLabel · $statusLabel$suffix';
}

String _toolCallStatusActionLabel(
  BuildContext context,
  String status, {
  required bool isCommandLike,
}) {
  return switch (status) {
    '' => (isCommandLike ? AppLocalizations.of(context)!.tlCallPreparing : AppLocalizations.of(context)!.tlCallPreparingAlt),
    'running' => (isCommandLike ? AppLocalizations.of(context)!.tlCallRunning : AppLocalizations.of(context)!.tlCallRunningAlt),
    'cancelled' => AppLocalizations.of(context)!.tlCallStopped,
    'success' => (isCommandLike ? AppLocalizations.of(context)!.tlCallCompleted : AppLocalizations.of(context)!.tlCallCompletedAlt),
    'denied' => AppLocalizations.of(context)!.tlCallBlocked,
    'rejected' => AppLocalizations.of(context)!.tlCallRejected,
    'timed_out' => (isCommandLike ? AppLocalizations.of(context)!.tlCallTimedOut : AppLocalizations.of(context)!.tlCallTimedOutAlt),
    'failed' => (isCommandLike ? AppLocalizations.of(context)!.tlCallFailed : AppLocalizations.of(context)!.tlCallFailedAlt),
    'invalid_arguments' => AppLocalizations.of(context)!.tlCallInvalid,
    _ => AppLocalizations.of(context)!.tlCallToolCall,
  };
}

String _toolExecutionOutcomeLabel(BuildContext context, String status) {
  return switch (status) {
    'running' => AppLocalizations.of(context)!.tlCallRunning,
    'cancelled' => AppLocalizations.of(context)!.tlCallStopped,
    'success' => AppLocalizations.of(context)!.tlCallSucceeded,
    'denied' => AppLocalizations.of(context)!.tlCallDenied,
    'rejected' => AppLocalizations.of(context)!.tlCallRejected,
    'timed_out' => AppLocalizations.of(context)!.tlCallTimedOut,
    'failed' => AppLocalizations.of(context)!.tlCallFailed,
    'invalid_arguments' => AppLocalizations.of(context)!.tlCallInvalid,
    _ => status,
  };
}

String _toolExecutionPreviewText(
  BuildContext context, {
  required String status,
  required String stdout,
  required String stderr,
  required String resultText,
}) {
  final stderrLine = _lastNonEmptyToolOutputLine(stderr);
  if (stderrLine.isNotEmpty) {
    return 'stderr · $stderrLine';
  }
  final stdoutLine = _lastNonEmptyToolOutputLine(stdout);
  if (stdoutLine.isNotEmpty) {
    return 'stdout · $stdoutLine';
  }
  final resultLine = _lastNonEmptyToolOutputLine(resultText);
  if (resultLine.isNotEmpty) {
    return 'result · $resultLine';
  }
  if (_shouldSweepToolStatus(status)) {
    return AppLocalizations.of(context)!.tlCallToolIsRunningWaitingForOutput;
  }
  return AppLocalizations.of(context)!.tlCallExpandToInspectToolOutput;
}

String _lastNonEmptyToolOutputLine(String content) {
  final lines = const LineSplitter()
      .convert(content)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  if (lines.isEmpty) {
    return '';
  }
  return lines.last;
}

int _toolExecutionDurationMs(AiSessionMessage message) {
  final rawValue =
      message.metadata['tool_execution_elapsed_ms'] ??
      message.metadata['tool_execution_duration_ms'] ??
      0;
  if (rawValue is int) {
    return rawValue;
  }
  return int.tryParse('$rawValue'.trim()) ?? 0;
}

String _formatToolExecutionDuration(int durationMs) {
  final totalSeconds = (durationMs / 1000).floor();
  if (totalSeconds < 60) {
    return '${totalSeconds}s';
  }
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes}m ${seconds}s';
}

Future<void> _openResolvedMessagePath(
  BuildContext context,
  MessageResolvedPath resolvedPath,
) async {
  try {
    final ProcessResult? result;
    if (Platform.isMacOS) {
      result = await runProcessWithTimeout(
        'open',
        resolvedPath.isDirectory
            ? <String>[resolvedPath.resolvedPath]
            : <String>['-R', resolvedPath.resolvedPath],
        timeout: const Duration(seconds: 6),
        tag: 'tool_call_widgets',
      );
    } else if (Platform.isWindows) {
      result = await runProcessWithTimeout(
        'explorer',
        resolvedPath.isDirectory
            ? <String>[resolvedPath.resolvedPath]
            : <String>['/select,${resolvedPath.resolvedPath}'],
        timeout: const Duration(seconds: 6),
        tag: 'tool_call_widgets',
      );
    } else if (Platform.isLinux) {
      result = await runProcessWithTimeout(
        'xdg-open',
        <String>[
          resolvedPath.isDirectory
              ? resolvedPath.resolvedPath
              : p.dirname(resolvedPath.resolvedPath),
        ],
        timeout: const Duration(seconds: 6),
        tag: 'tool_call_widgets',
      );
    } else {
      throw const FileSystemException('Unsupported platform.');
    }
    if (result != null && result.exitCode == 0) {
      return;
    }
    final message = result == null
        ? 'open command timed out'
        : '${result.stderr}'.trim();
    throw FileSystemException(
      message.isEmpty ? 'Unable to open file location.' : message,
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    _showMessageLinkOpenError(context, error);
  }
}

Future<void> _openMessageLinkUri(BuildContext context, Uri uri) async {
  // Restrict the schemes we will hand to the OS launcher. Without this an
  // adversarial markdown link such as `file:///etc/passwd` or
  // `vbscript:msgbox(...)` could be opened verbatim with the user's
  // default handler. Only the schemes that have a sensible “open this”
  // semantic in this product are allowed.
  const allowedSchemes = <String>{'http', 'https', 'mailto', 'file'};
  final scheme = uri.scheme.toLowerCase();
  if (!allowedSchemes.contains(scheme)) {
    if (context.mounted) {
      _showMessageLinkOpenError(
        context,
        FormatException('Unsupported link scheme: $scheme'),
      );
    }
    return;
  }
  try {
    late final ProcessResult result;
    final target = uri.toString();
    if (Platform.isMacOS) {
      result = await Process.run('open', <String>[target]);
    } else if (Platform.isWindows) {
      result = await Process.run('explorer', <String>[target]);
    } else if (Platform.isLinux) {
      result = await Process.run('xdg-open', <String>[target]);
    } else {
      throw const FileSystemException('Unsupported platform.');
    }
    if (result.exitCode == 0) {
      return;
    }
    final message = '${result.stderr}'.trim();
    throw FileSystemException(
      message.isEmpty ? 'Unable to open link.' : message,
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    _showMessageLinkOpenError(context, error);
  }
}

void _showMessageLinkOpenError(BuildContext context, Object error) {
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        AppLocalizations.of(context)!.tlCallFailedToOpenFileLocationError(error),
      ),
    ),
  );
}

class _FilePathMarkdownBuilder extends MarkdownElementBuilder {
  _FilePathMarkdownBuilder({required this.textColor, required this.onOpenPath});

  final Color textColor;
  final Future<void> Function(
    BuildContext context,
    MessageResolvedPath resolvedPath,
  )
  onOpenPath;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    if (element.tag == 'openhand-file-resolved') {
      final resolvedPath = (element.attributes['resolved_path'] ?? '').trim();
      final displayPath = element.textContent.trim();
      final isDirectory =
          (element.attributes['entity_type'] ?? '').trim() == 'directory';
      return Text.rich(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _buildChip(
              context,
              displayPath: displayPath,
              resolvedPath: resolvedPath,
              isDirectory: isDirectory,
            ),
          ),
        ),
      );
    }

    final normalizedPath = element.attributes['normalized_path'] ?? '';
    final candidateRoots = (element.attributes['candidate_roots'] ?? '').split(
      '\r',
    );
    final fullMatch = element.textContent;
    final trailing = element.attributes['trailing'] ?? '';
    final isCodeSpan = element.attributes['is_code_span'] == 'true';

    return Text.rich(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: _AsyncFilePathChip(
          normalizedPath: normalizedPath,
          candidateRoots: candidateRoots,
          fullMatch: fullMatch,
          trailing: trailing,
          isCodeSpan: isCodeSpan,
          parentStyle: parentStyle,
          builder: this,
        ),
      ),
    );
  }

  Widget _buildCodeSpan(
    BuildContext context,
    String text,
    TextStyle? parentStyle,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style:
            parentStyle?.copyWith(
              fontFamily: 'monospace',
              fontSize: (parentStyle.fontSize ?? 14) * 0.9,
              color: colorScheme.onSurface,
            ) ??
            theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
              color: colorScheme.onSurface,
            ),
      ),
    );
  }

  Widget _buildChip(
    BuildContext context, {
    required String displayPath,
    required String resolvedPath,
    required bool isDirectory,
    bool isUnresolved = false,
  }) {
    return _FilePathChip(
      displayPath: displayPath,
      resolvedPath: resolvedPath,
      isDirectory: isDirectory,
      isUnresolved: isUnresolved,
      textColor: textColor,
      onOpenPath: () => onOpenPath(
        context,
        MessageResolvedPath(
          displayPath: displayPath,
          resolvedPath: resolvedPath,
          isDirectory: isDirectory,
        ),
      ),
    );
  }
}

class _AsyncFilePathChip extends StatefulWidget {
  const _AsyncFilePathChip({
    required this.normalizedPath,
    required this.candidateRoots,
    required this.fullMatch,
    required this.trailing,
    required this.isCodeSpan,
    required this.parentStyle,
    required this.builder,
  });

  final String normalizedPath;
  final List<String> candidateRoots;
  final String fullMatch;
  final String trailing;
  final bool isCodeSpan;
  final TextStyle? parentStyle;
  final _FilePathMarkdownBuilder builder;

  @override
  State<_AsyncFilePathChip> createState() => _AsyncFilePathChipState();
}

class _AsyncFilePathChipState extends State<_AsyncFilePathChip> {
  Future<MessageResolvedPath?>? _future;
  // When the resolution cache already has the answer for the current
  // `(normalizedPath, candidateRoots)` pair, we skip the FutureBuilder
  // entirely and render synchronously.  This avoids the extra "loading"
  // build frame that FutureBuilder always triggers (even when the future
  // is already completed), and more importantly spares the cascade of
  // 10+ setState pulses during the initial transcript paint when many
  // chips all resolve at once.
  bool _resolvedSync = false;
  MessageResolvedPath? _syncValue;

  void _primeFromCacheOrStartFuture() {
    final probe = lookupResolvedMessagePathFromCache(
      widget.normalizedPath,
      widget.candidateRoots,
    );
    if (probe.hit) {
      _resolvedSync = true;
      _syncValue = probe.value;
      _future = null;
      return;
    }
    _resolvedSync = false;
    _syncValue = null;
    _future = resolveExistingMessagePathAsync(
      widget.normalizedPath,
      widget.candidateRoots,
    );
  }

  @override
  void initState() {
    super.initState();
    _primeFromCacheOrStartFuture();
  }

  @override
  void didUpdateWidget(_AsyncFilePathChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.normalizedPath != widget.normalizedPath ||
        oldWidget.candidateRoots.join('|') != widget.candidateRoots.join('|')) {
      _primeFromCacheOrStartFuture();
    }
  }

  Widget _renderResolved(
    BuildContext context,
    MessageResolvedPath? resolvedPath,
  ) {
    if (resolvedPath == null) {
      if (widget.isCodeSpan) {
        return widget.builder._buildCodeSpan(
          context,
          widget.fullMatch,
          widget.parentStyle,
        );
      }
      final isExplicitPath =
          widget.normalizedPath.startsWith('~/') ||
          widget.normalizedPath.startsWith('./') ||
          widget.normalizedPath.startsWith('../') ||
          looksLikeAbsoluteMessagePath(widget.normalizedPath);
      if (isExplicitPath) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: widget.builder._buildChip(
                  context,
                  displayPath: widget.normalizedPath,
                  resolvedPath: widget.normalizedPath,
                  isDirectory: widget.trailing.contains('/'),
                  isUnresolved: true,
                ),
              ),
            ),
            if (widget.trailing.isNotEmpty)
              Text(widget.trailing, style: widget.parentStyle),
          ],
        );
      }
      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Text(widget.fullMatch, style: widget.parentStyle),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: widget.builder._buildChip(
              context,
              displayPath: resolvedPath.displayPath,
              resolvedPath: resolvedPath.resolvedPath,
              isDirectory: resolvedPath.isDirectory,
            ),
          ),
        ),
        if (widget.trailing.isNotEmpty)
          Text(widget.trailing, style: widget.parentStyle),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_resolvedSync) {
      return _renderResolved(context, _syncValue);
    }
    return FutureBuilder<MessageResolvedPath?>(
      future: _future,
      builder: (context, snapshot) {
        return _renderResolved(context, snapshot.data);
      },
    );
  }
}

class _FilePathChip extends StatelessWidget {
  const _FilePathChip({
    required this.displayPath,
    required this.resolvedPath,
    required this.isDirectory,
    this.isUnresolved = false,
    required this.textColor,
    required this.onOpenPath,
  });

  final String displayPath;
  final String resolvedPath;
  final bool isDirectory;
  final bool isUnresolved;
  final Color textColor;
  final VoidCallback onOpenPath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chipColor = theme.colorScheme.surface.withValues(alpha: 0.68);
    final borderColor = textColor.withValues(alpha: 0.24);
    final labelStyle =
        theme.textTheme.labelMedium?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w700,
        ) ??
        TextStyle(color: textColor, fontWeight: FontWeight.w700);

    return _FileHoverPopup(
      resolvedPath: resolvedPath,
      isUnresolved: isUnresolved,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: _borderRadius999,
          onTap: isUnresolved ? null : onOpenPath,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isUnresolved
                  ? chipColor.withValues(alpha: 0.3)
                  : chipColor,
              borderRadius: _borderRadius999,
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isUnresolved
                      ? Icons.help_outline
                      : isDirectory
                      ? Icons.folder_outlined
                      : Icons.insert_drive_file_outlined,
                  size: 14,
                  color: isUnresolved
                      ? textColor.withValues(alpha: 0.5)
                      : textColor.withValues(alpha: 0.9),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: Text(
                      displayPath,
                      overflow: TextOverflow.ellipsis,
                      style: isUnresolved
                          ? labelStyle.copyWith(
                              color: textColor.withValues(alpha: 0.5),
                            )
                          : labelStyle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FileHoverPopup extends StatefulWidget {
  const _FileHoverPopup({
    required this.resolvedPath,
    required this.child,
    this.isUnresolved = false,
  });
  final String resolvedPath;
  final Widget child;
  final bool isUnresolved;

  @override
  State<_FileHoverPopup> createState() => _FileHoverPopupState();
}

class _FileHoverPopupState extends State<_FileHoverPopup> {
  OverlayEntry? _overlayEntry;
  bool _isHovered = false;
  bool _showScheduled = false;
  bool _hideScheduled = false;

  /// Returns true if any Ctrl or Meta (Cmd on macOS) modifier key is currently
  /// held down. Uses [physicalKeysPressed] which reflects raw hardware state
  /// and is unaffected by logical-key remapping or keyboard guard filtering.
  bool get _isModifierPressed {
    final pressed = HardwareKeyboard.instance.physicalKeysPressed;
    return pressed.contains(PhysicalKeyboardKey.controlLeft) ||
        pressed.contains(PhysicalKeyboardKey.controlRight) ||
        pressed.contains(PhysicalKeyboardKey.metaLeft) ||
        pressed.contains(PhysicalKeyboardKey.metaRight);
  }

  void _showOverlay() {
    if (widget.isUnresolved || _overlayEntry != null || _showScheduled) return;
    // Defer overlay insertion to avoid mutating the widget tree during
    // MouseTracker._deviceUpdatePhase, which triggers the
    // !_debugDuringDeviceUpdate re-entrancy assertion.
    _showScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showScheduled = false;
      if (!mounted || !_isHovered || _overlayEntry != null) return;
      _showOverlayNow();
    });
  }

  void _showOverlayNow() {
    if (widget.isUnresolved || _overlayEntry != null) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;
    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);
    final screenSize = MediaQuery.sizeOf(context);

    var targetLeft = offset.dx;
    if (targetLeft + 320 > screenSize.width - 16) {
      targetLeft = screenSize.width - 320 - 16;
      if (targetLeft < 8) targetLeft = 8;
    }

    var targetTop = offset.dy + size.height + 6;
    const estimatedHeight = 140.0;
    if (targetTop + estimatedHeight > screenSize.height - 16) {
      targetTop = offset.dy - estimatedHeight - 6;
    }

    // Capture the path at the time of showing to avoid stale closure issues.
    final resolvedPath = widget.resolvedPath;

    _overlayEntry = OverlayEntry(
      builder: (overlayContext) => Positioned(
        left: targetLeft,
        top: targetTop,
        // IgnorePointer: the popup is read-only metadata; it must not consume
        // pointer events so that the chip and underlying widgets remain
        // interactive (e.g. clicking the chip still opens Finder).
        child: IgnorePointer(
          child: FadeInOverlayContent(
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(
                    overlayContext,
                  ).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(overlayContext).dividerColor,
                  ),
                ),
                width: 320,
                child: FutureBuilder<FileStat>(
                  future: FileStat.stat(resolvedPath),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const SizedBox(
                        height: 40,
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }
                    final stat = snapshot.data!;
                    final theme = Theme.of(context);
                    final colorScheme = theme.colorScheme;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          resolvedPath,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _StatRow(
                          AppLocalizations.of(context)!.tlCallType,
                          stat.type.toString(),
                        ),
                        _StatRow(
                          AppLocalizations.of(context)!.tlCallSize,
                          '${stat.size} bytes',
                        ),
                        _StatRow(
                          AppLocalizations.of(context)!.tlCallModified,
                          '${stat.modified}',
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    try {
      Overlay.of(context).insert(_overlayEntry!);
    } catch (_) {
      _overlayEntry = null;
    }
  }

  void _hideOverlay() {
    if (_overlayEntry == null && !_showScheduled) return;
    _showScheduled = false;
    final entry = _overlayEntry;
    _overlayEntry = null;
    if (entry == null) return;
    // Defer overlay removal to avoid mutating the widget tree during
    // MouseTracker._deviceUpdatePhase.
    if (_hideScheduled) return;
    _hideScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hideScheduled = false;
      entry.remove();
    });
  }

  @override
  void didUpdateWidget(_FileHoverPopup oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the resolved path changed while the overlay was visible, dismiss it
    // so it doesn't show stale metadata from the previous path.
    if (oldWidget.resolvedPath != widget.resolvedPath ||
        oldWidget.isUnresolved != widget.isUnresolved) {
      _hideOverlay();
    }
  }

  @override
  void deactivate() {
    // Synchronous removal is safe when the widget is leaving the tree.
    _showScheduled = false;
    _hideScheduled = false;
    _overlayEntry?.remove();
    _overlayEntry = null;
    _isHovered = false;
    super.deactivate();
  }

  bool _handleKey(KeyEvent event) {
    if (!mounted || !_isHovered || widget.isUnresolved) {
      return false;
    }
    if (_isModifierPressed) {
      _showOverlay();
    } else {
      _hideOverlay();
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void dispose() {
    // Synchronous cleanup—widget is being permanently destroyed.
    _showScheduled = false;
    _hideScheduled = false;
    _overlayEntry?.remove();
    _overlayEntry = null;
    HardwareKeyboard.instance.removeHandler(_handleKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        _isHovered = true;
        if (!widget.isUnresolved && _isModifierPressed) {
          _showOverlay();
        }
      },
      onHover: (_) {
        if (!widget.isUnresolved) {
          if (_isModifierPressed) {
            _showOverlay();
          } else {
            _hideOverlay();
          }
        }
      },
      onExit: (_) {
        _isHovered = false;
        _hideOverlay();
      },
      child: widget.child,
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Self-learning card: rendered for AiSessionMessageKind.selfLearning.
//
// Shows a compact summary of what the self-learning worker updated during an
// autonomous review pass: which memories changed, which skills changed, and
// an optional profile diff paragraph. Mirrors the visual idiom of the tool
// call card (chip row + expandable sections) so the transcript reads
// uniformly, but uses the tertiary colour slot to distinguish "the agent
// learnt something" from "the agent ran a tool".
// ─────────────────────────────────────────────────────────────────────────────

class _SelfLearningCard extends StatefulWidget {
  const _SelfLearningCard({required this.message});

  final AiSessionMessage message;

  @override
  State<_SelfLearningCard> createState() => _SelfLearningCardState();
}

class _SelfLearningCardState extends State<_SelfLearningCard> {
  bool _profileChangesExpanded = false;
  bool _memoriesExpanded = false;
  bool _skillsExpanded = false;
  bool _profileExpanded = false;
  bool _responseExpanded = false;
  bool _reasoningExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final metadata = widget.message.metadata;
    final memoryItems = _extractChangeItems(metadata['memory_changes']);
    final skillItems = _extractChangeItems(metadata['skill_changes']);
    final profileItems = _extractChangeItems(metadata['profile_changes']);
    final profileDiff = _extractProfileDiff(metadata['profile_diff']);
    final aiResponse = _extractProfileDiff(metadata['ai_response']);
    final aiReasoning = _extractProfileDiff(metadata['ai_reasoning']);
    final status = metadata['status']?.toString() ?? '';
    final isStreaming = metadata['streaming'] == true;
    final elapsedLabel = _formatSelfLearningElapsed(
      context,
      widget.message.createdAt,
    );
    final memoryCountLabel = AppLocalizations.of(context)!.tlCallMemoryitemsLengthMemoriesUpdated(memoryItems.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SelfLearningHeaderRow(
          icon: Icons.psychology_alt_rounded,
          label: AppLocalizations.of(context)!.tlCallSelfLearning,
          color: colorScheme.tertiary,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (profileItems.isNotEmpty)
              _ToolExecutionChip(
                icon: Icons.account_circle_outlined,
                label: AppLocalizations.of(context)!.tlCallProfileitemsLengthProfileChanges(profileItems.length),
              ),
            _ToolExecutionChip(
              icon: Icons.memory_rounded,
              label: memoryCountLabel,
            ),
            if (skillItems.isNotEmpty)
              _ToolExecutionChip(
                icon: Icons.extension_rounded,
                label: AppLocalizations.of(context)!.tlCallSkillitemsLengthSkillsUpdated(skillItems.length),
              ),
            _ToolExecutionChip(
              icon: Icons.schedule_rounded,
              label: elapsedLabel,
            ),
            if (metadata['nudge_recovered'] == true)
              _ToolExecutionChip(
                icon: Icons.refresh_rounded,
                label: AppLocalizations.of(context)!.tlCallNudgeRecovered,
              ),
          ],
        ),
        const SizedBox(height: 10),
        _ExpandableToolSection(
          title: AppLocalizations.of(context)!.tlCallProfileChanges,
          preview: _changeItemsPreview(context, profileItems),
          expanded: _profileChangesExpanded,
          onToggle: () {
            setState(() {
              _profileChangesExpanded = !_profileChangesExpanded;
            });
          },
          expandedBuilder: (context) =>
              _SelfLearningChangeList(items: profileItems),
        ),
        const SizedBox(height: 10),
        _ExpandableToolSection(
          title: AppLocalizations.of(context)!.tlCallMemoryChanges,
          preview: _changeItemsPreview(context, memoryItems),
          expanded: _memoriesExpanded,
          onToggle: () {
            setState(() {
              _memoriesExpanded = !_memoriesExpanded;
            });
          },
          expandedBuilder: (context) =>
              _SelfLearningChangeList(items: memoryItems),
        ),
        const SizedBox(height: 10),
        _ExpandableToolSection(
          title: AppLocalizations.of(context)!.tlCallSkillChanges,
          preview: _changeItemsPreview(context, skillItems),
          expanded: _skillsExpanded,
          onToggle: () {
            setState(() {
              _skillsExpanded = !_skillsExpanded;
            });
          },
          expandedBuilder: (context) =>
              _SelfLearningChangeList(items: skillItems),
        ),
        if (profileDiff.isNotEmpty) ...[
          const SizedBox(height: 10),
          _ExpandableToolSection(
            title: AppLocalizations.of(context)!.tlCallProfileDiff,
            preview: profileDiff,
            expanded: _profileExpanded,
            onToggle: () {
              setState(() {
                _profileExpanded = !_profileExpanded;
              });
            },
            expandedBuilder: (context) => Text(
              profileDiff,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
          ),
        ],
        if (aiReasoning.isNotEmpty) ...[
          const SizedBox(height: 10),
          _ExpandableToolSection(
            title: (isStreaming ? AppLocalizations.of(context)!.tlCallAiThinkingStreaming : AppLocalizations.of(context)!.tlCallAiThinking),
            preview: _previewText(aiReasoning),
            expanded: _reasoningExpanded,
            onToggle: () {
              setState(() {
                _reasoningExpanded = !_reasoningExpanded;
              });
            },
            expandedBuilder: (context) =>
                _SelfLearningMarkdown(data: aiReasoning, muted: true),
          ),
        ],
        if (aiResponse.isNotEmpty) ...[
          const SizedBox(height: 10),
          _ExpandableToolSection(
            title: (isStreaming ? AppLocalizations.of(context)!.tlCallAiResponseStreaming : AppLocalizations.of(context)!.tlCallAiResponse),
            preview: _previewText(aiResponse),
            expanded: _responseExpanded,
            onToggle: () {
              setState(() {
                _responseExpanded = !_responseExpanded;
              });
            },
            expandedBuilder: (context) =>
                _SelfLearningMarkdown(data: aiResponse, muted: false),
          ),
        ],
        if (status == 'error' && aiResponse.isEmpty) ...[
          const SizedBox(height: 10),
          Text(
            widget.message.content,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.error,
              height: 1.45,
            ),
          ),
        ] else if (status != 'error' &&
            !isStreaming &&
            aiResponse.isEmpty &&
            aiReasoning.isEmpty &&
            profileItems.isEmpty &&
            memoryItems.isEmpty &&
            skillItems.isEmpty &&
            widget.message.content.trim().isNotEmpty) ...[
          // 2026-04-25 — 兜底说明：当本轮成功结束（status != 'error'）但模型
          // 既没有调用任何工具，也没有产生 AI 文本/思考输出时，避免卡片只剩
          // "无变更" 三连而让用户误以为是 BUG。把 message.content 作为简要
          // 说明展示出来（通常是 dispatcher 给出的 "模型本轮未调用任何工具…"
          // 这类文案，或后端返回的 finish_reason 提示）。
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.message.content,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Renders self-learning AI 思考 / AI 响应 with Markdown — reuses the same
/// `_SafeMarkdownBody` engine the main message bubble uses, so code fences,
/// lists and emphasis get full syntax-highlighted treatment instead of the
/// previous plain `SelectableText`.
///
/// Wrapped in [AnimatedSize] so as the dispatcher streams token-deltas in
/// (and the parent's metadata grows), the card height eases out with a
/// gentle Q-bouncy easeOutCubicEmphasized curve instead of jumping.
class _SelfLearningMarkdown extends StatelessWidget {
  const _SelfLearningMarkdown({required this.data, required this.muted});

  final String data;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = MarkdownStyleSheet.fromTheme(theme);
    final styleSheet = muted
        ? base.copyWith(
            p: theme.textTheme.bodySmall?.copyWith(
              height: 1.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        : base.copyWith(p: theme.textTheme.bodyMedium?.copyWith(height: 1.5));
    return ClipRect(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topLeft,
        child: _SafeMarkdownBody(
          data: data.isEmpty ? ' ' : data,
          styleSheet: styleSheet,
          selectable: true,
        ),
      ),
    );
  }
}

/// Returns a compact single-line preview of [text] suitable for a card
/// collapsed header — trims whitespace, collapses newlines and truncates
/// past 120 characters.
String _previewText(String text) {
  final collapsed = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.length <= 120) return collapsed;
  return '${collapsed.substring(0, 117)}…';
}

/// Header row for the self-learning card. Intentionally matches the visual
/// weight of [_MessageMetaRow] but uses a tinted capsule so the colour slot
/// used by the card (tertiary) is clearly differentiated from tool calls
/// (secondary).
class _SelfLearningHeaderRow extends StatelessWidget {
  const _SelfLearningHeaderRow({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: _borderRadius999,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders a list of self-learning change entries. Each entry is either a
/// bare id string or a map with `id` / `summary` keys; the summary — when
/// present — is shown in a muted style beneath the id.
class _SelfLearningChangeList extends StatelessWidget {
  const _SelfLearningChangeList({required this.items});

  final List<_SelfLearningChangeItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (items.isEmpty) {
      return Text(
        AppLocalizations.of(context)!.tlCallNoChanges,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _SelfLearningChangeTile(item: items[i]),
        ],
      ],
    );
  }
}

class _SelfLearningChangeTile extends StatelessWidget {
  const _SelfLearningChangeTile({required this.item});

  final _SelfLearningChangeItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, right: 8),
          child: Icon(
            Icons.chevron_right_rounded,
            size: 16,
            color: theme.colorScheme.tertiary,
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.id.isEmpty
                    ? AppLocalizations.of(context)!.tlCallUnnamed
                    : item.id,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
              ),
              if (item.summary.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  item.summary,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SelfLearningChangeItem {
  const _SelfLearningChangeItem({required this.id, required this.summary});

  final String id;
  final String summary;
}

/// Coerces `memory_changes` / `skill_changes` metadata into a list of
/// [_SelfLearningChangeItem]. Accepts any of the following shapes:
///
///   - `List<String>` → each becomes an id-only item.
///   - `List<Map>`    → reads `id` and `summary` defensively.
///   - `int`          → returns that many placeholder items so the header
///                      count matches the list length (ids unknown).
///   - any other type → empty list.
List<_SelfLearningChangeItem> _extractChangeItems(Object? raw) {
  if (raw is List) {
    final items = <_SelfLearningChangeItem>[];
    for (final entry in raw) {
      if (entry is String) {
        items.add(_SelfLearningChangeItem(id: entry.trim(), summary: ''));
      } else if (entry is Map) {
        final id = '${entry['id'] ?? ''}'.trim();
        final summary = '${entry['summary'] ?? ''}'.trim();
        items.add(_SelfLearningChangeItem(id: id, summary: summary));
      }
    }
    return items;
  }
  if (raw is int && raw > 0) {
    return List<_SelfLearningChangeItem>.generate(
      raw,
      (_) => const _SelfLearningChangeItem(id: '', summary: ''),
    );
  }
  return const <_SelfLearningChangeItem>[];
}

String _extractProfileDiff(Object? raw) {
  if (raw is String) {
    return raw.trim();
  }
  if (raw is Map) {
    final summary = '${raw['summary'] ?? ''}'.trim();
    if (summary.isNotEmpty) return summary;
    // Fallback: render a compact "key: value" preview if the map has
    // primitive entries. Keeps the UI useful when the agent emits a
    // structured diff instead of a pre-written paragraph.
    final parts = <String>[];
    raw.forEach((key, value) {
      if (value is String || value is num || value is bool) {
        parts.add('$key: $value');
      }
    });
    return parts.join(' · ');
  }
  return '';
}

String _changeItemsPreview(
  BuildContext context,
  List<_SelfLearningChangeItem> items,
) {
  if (items.isEmpty) {
    return AppLocalizations.of(context)!.tlCallNoChanges;
  }
  final names = items
      .map((item) => item.id.isEmpty ? '—' : item.id)
      .take(3)
      .join(', ');
  final suffix = items.length > 3
      ? AppLocalizations.of(context)!.tlCallAndItemsLength3More(items.length - 3, items.length)
      : '';
  return '$names$suffix';
}

/// Formats the elapsed time since [createdAt] into a short relative label.
/// Mirrors the bilingual convention used elsewhere in the home feature
/// (e.g. the reasoning meta row) instead of the absolute timestamp used in
/// the message footer, because the spec calls for a relative elapsed hint.
String _formatSelfLearningElapsed(BuildContext context, DateTime createdAt) {
  final now = DateTime.now().toUtc();
  final diff = now.difference(createdAt.toUtc());
  if (diff.isNegative || diff.inSeconds < 5) {
    return AppLocalizations.of(context)!.tlCallJustNow;
  }
  if (diff.inMinutes < 1) {
    final seconds = diff.inSeconds;
    return AppLocalizations.of(context)!.tlCallSecondsSAgo(seconds);
  }
  if (diff.inHours < 1) {
    final minutes = diff.inMinutes;
    return AppLocalizations.of(context)!.tlCallMinutesMAgo(minutes);
  }
  if (diff.inDays < 1) {
    final hours = diff.inHours;
    return AppLocalizations.of(context)!.tlCallHoursHAgo(hours);
  }
  final days = diff.inDays;
  return AppLocalizations.of(context)!.tlCallDaysDAgo(days);
}

/// 把文件差异预览加载失败的常见 dart:io 异常翻译成中英双语简短文案，
/// 替代直接 `e.toString()` 把 `FileSystemException(...)` 暴露给用户。
String _friendlyFileDiffError(Object error, {required bool isZh}) {
  final raw = error.toString();
  if (raw.startsWith('PathNotFoundException') ||
      raw.contains('No such file or directory')) {
    return isZh
        ? '文件已不存在或路径已被移动。\n原始错误：$raw'
        : 'File no longer exists or has been moved.\nRaw: $raw';
  }
  if (raw.startsWith('FileSystemException')) {
    return isZh
        ? '文件系统操作失败 (可能是权限不足 / 磁盘已满 / 路径被占用)。\n原始错误：$raw'
        : 'Filesystem operation failed (permission, disk space, or lock).\nRaw: $raw';
  }
  return raw;
}
