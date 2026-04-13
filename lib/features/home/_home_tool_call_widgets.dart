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
    return Column(
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
            if (toolCall.workingDirectory.isNotEmpty)
              _ToolExecutionChip(
                icon: Icons.folder_outlined,
                label:
                    '${_localizedText(context, zh: '目录', en: 'Dir')}: ${toolCall.workingDirectory}',
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
                    '${_localizedText(context, zh: '耗时', en: 'Elapsed')}: ${_formatToolExecutionDuration(toolCall.durationMs)}',
              ),
            if (toolCall.exitCode != null)
              _ToolExecutionChip(
                icon: Icons.flag_outlined,
                label:
                    '${_localizedText(context, zh: '退出码', en: 'Exit')}: ${toolCall.exitCode}',
              ),
          ],
        ),
        const SizedBox(height: 10),
        _ExpandableToolSection(
          title: _localizedText(context, zh: '工具入参', en: 'Tool Input'),
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
                  label: _localizedText(context, zh: 'command', en: 'command'),
                  content: toolCall.formattedCommand,
                  theme: theme,
                  selectable: widget.selectable,
                ),
              if (toolCall.command.isNotEmpty) const SizedBox(height: 10),
              _ToolOutputPanel(
                label: _localizedText(
                  context,
                  zh: 'arguments',
                  en: 'arguments',
                ),
                content: toolCall.formattedArguments,
                theme: theme,
                selectable: widget.selectable,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _ExpandableToolSection(
          title: _localizedText(context, zh: '结果输出', en: 'Tool Output'),
          preview: toolCall.hasResultContent
              ? toolCall.resultPreview
              : _localizedText(context, zh: '暂无输出', en: 'No output yet'),
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
                  label: 'stdout',
                  content: toolCall.formattedStdout,
                  theme: theme,
                  selectable: widget.selectable,
                ),
              if (toolCall.stderr.isNotEmpty) ...[
                if (toolCall.stdout.isNotEmpty) const SizedBox(height: 10),
                _ToolOutputPanel(
                  label: 'stderr',
                  content: toolCall.formattedStderr,
                  theme: theme,
                  isError: true,
                  selectable: widget.selectable,
                ),
              ],
              if (toolCall.showResultText) ...[
                if (toolCall.stdout.isNotEmpty || toolCall.stderr.isNotEmpty)
                  const SizedBox(height: 10),
                _ToolOutputPanel(
                  label: _localizedText(context, zh: 'result', en: 'result'),
                  content: toolCall.formattedResult,
                  theme: theme,
                  selectable: widget.selectable,
                ),
              ],
              if (toolCall.stdout.isEmpty &&
                  toolCall.stderr.isEmpty &&
                  !toolCall.showResultText)
                Text(
                  _localizedText(
                    context,
                    zh: '当前还没有工具输出。',
                    en: 'There is no tool output yet.',
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        // ── File mutation indicator (mirrors HE changed-files row) ──
        if (_fileMutationPath(message).isNotEmpty &&
            _toolExecutionStatus(message) == 'success') ...[
          const SizedBox(height: 10),
          _FileMutationRow(message: message),
        ],
      ],
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
  });

  final String label;
  final _FormattedToolContent content;
  final ThemeData theme;
  final bool selectable;
  final bool isError;

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
                    _localizedText(
                      context,
                      zh: _isWrapped ? '取消换行' : '自动换行',
                      en: _isWrapped ? 'Unwrap' : 'Wrap Lines',
                    ),
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
                      _localizedText(
                        context,
                        zh: _isExpanded ? '查看压缩内容' : '查看完整内容',
                        en: _isExpanded
                            ? 'View Compressed Content'
                            : 'View Full Content',
                      ),
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
        _localizedText(context, zh: '写入', en: 'Write'),
      ),
      'edit' => (
        Icons.edit_outlined,
        colorScheme.primary,
        _localizedText(context, zh: '编辑', en: 'Edit'),
      ),
      'multi_edit' => (
        Icons.edit_note_outlined,
        colorScheme.primary,
        editCount is int && editCount > 1
            ? _localizedText(
                context,
                zh: '多处编辑 ×$editCount',
                en: 'Multi-edit ×$editCount',
              )
            : _localizedText(context, zh: '多处编辑', en: 'Multi-edit'),
      ),
      'notebook_edit' => (
        Icons.menu_book_outlined,
        colorScheme.tertiary,
        _localizedText(context, zh: 'Notebook 编辑', en: 'Notebook Edit'),
      ),
      'bash_write' => (
        Icons.terminal_rounded,
        const Color(0xFFF57F17),
        _localizedText(context, zh: '命令写入', en: 'Bash Write'),
      ),
      _ => (
        Icons.difference_rounded,
        colorScheme.onSurfaceVariant,
        _localizedText(context, zh: '文件变更', en: 'File Changed'),
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
                _localizedText(context, zh: '文件变动', en: 'Changed File'),
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
      builder: (ctx) => _FileDiffDialog(
        filePath: filePath,
        changeKind: kind,
        isZh: isZh,
      ),
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
        _error = e.toString();
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
              style: TextStyle(
                backgroundColor: bgColor,
                color: textColor,
              ),
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
  List<String> _longestCommonSubsequence(
      List<String> a, List<String> b) {
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
  });

  factory _ToolCallViewData.from(
    BuildContext context,
    AiSessionMessage message, {
    bool includeArgumentsContent = true,
    bool includeResultContent = true,
  }) {
    final presentation = _toolCallPresentation(context, message);
    final status = _toolExecutionStatus(message);
    final command = _toolExecutionCommand(message);
    final workingDirectory = _toolExecutionWorkingDirectory(message);
    final stdout = _toolExecutionStdout(message).trimRight();
    final stderr = _toolExecutionStderr(message).trimRight();
    final resultText = _toolExecutionResult(message).trimRight();
    final exitCode = _toolExecutionExitCode(message);
    final durationMs = _toolExecutionDurationMs(message);
    final argumentsPreview = _toolArgumentsPreview(message);
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
    final viewData = _ToolCallViewData(
      presentation: presentation,
      status: status,
      command: command,
      workingDirectory: workingDirectory,
      stdout: stdout,
      stderr: stderr,
      resultText: resultText,
      exitCode: exitCode,
      durationMs: durationMs,
      argumentsPreview: argumentsPreview,
      formattedCommand: formattedCommand,
      formattedArguments: formattedArguments,
      formattedStdout: formattedStdout,
      formattedStderr: formattedStderr,
      formattedResult: formattedResult,
      defaultExpanded: _shouldDefaultExpandToolStatus(status),
      showResultText: showResultText,
      hasResultContent: hasResultContent,
      shouldSweepBadge: _shouldSweepToolStatus(status),
      statusIcon: _toolExecutionStatusIcon(status),
      primaryChipLabel: presentation.displayName == presentation.categoryLabel
          ? presentation.categoryLabel
          : '${presentation.categoryLabel}: ${presentation.displayName}',
      statusLabel: _toolCallStatusLabelForData(
        context,
        presentation,
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
      categoryLabel: _localizedText(context, zh: '技能', en: 'Skill'),
      displayName: skillName.isEmpty ? rawToolName : skillName,
      icon: Icons.extension_rounded,
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
    _ => _ToolCallPresentation(
      categoryLabel: _localizedText(context, zh: '工具', en: 'Tool'),
      displayName: rawToolName.isEmpty
          ? _localizedText(context, zh: '工具', en: 'Tool')
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

_FormattedToolContent _formatToolContent(
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
    '' => _localizedText(
      context,
      zh: isCommandLike ? '准备执行' : '准备调用',
      en: 'Preparing',
    ),
    'running' => _localizedText(
      context,
      zh: isCommandLike ? '执行中' : '调用中',
      en: 'Running',
    ),
    'cancelled' => _localizedText(context, zh: '已停止', en: 'Stopped'),
    'success' => _localizedText(
      context,
      zh: isCommandLike ? '执行完成' : '调用完成',
      en: 'Completed',
    ),
    'denied' => _localizedText(context, zh: '已拦截', en: 'Blocked'),
    'rejected' => _localizedText(context, zh: '已拒绝', en: 'Rejected'),
    'timed_out' => _localizedText(
      context,
      zh: isCommandLike ? '执行超时' : '调用超时',
      en: 'Timed Out',
    ),
    'failed' => _localizedText(
      context,
      zh: isCommandLike ? '执行失败' : '调用失败',
      en: 'Failed',
    ),
    'invalid_arguments' => _localizedText(context, zh: '参数无效', en: 'Invalid'),
    _ => _localizedText(context, zh: '工具调用', en: 'Tool Call'),
  };
}

String _toolExecutionOutcomeLabel(BuildContext context, String status) {
  return switch (status) {
    'running' => _localizedText(context, zh: '运行中', en: 'Running'),
    'cancelled' => _localizedText(context, zh: '已停止', en: 'Stopped'),
    'success' => _localizedText(context, zh: '执行成功', en: 'Succeeded'),
    'denied' => _localizedText(context, zh: '已被禁止', en: 'Denied'),
    'rejected' => _localizedText(context, zh: '用户拒绝', en: 'Rejected'),
    'timed_out' => _localizedText(context, zh: '执行超时', en: 'Timed Out'),
    'failed' => _localizedText(context, zh: '执行失败', en: 'Failed'),
    'invalid_arguments' => _localizedText(context, zh: '参数无效', en: 'Invalid'),
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
    return _localizedText(
      context,
      zh: '工具运行中，等待新的输出...',
      en: 'Tool is running. Waiting for output...',
    );
  }
  return _localizedText(
    context,
    zh: '点击展开查看工具输出',
    en: 'Expand to inspect tool output',
  );
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
    late final ProcessResult result;
    if (Platform.isMacOS) {
      result = await Process.run(
        'open',
        resolvedPath.isDirectory
            ? <String>[resolvedPath.resolvedPath]
            : <String>['-R', resolvedPath.resolvedPath],
      );
    } else if (Platform.isWindows) {
      result = await Process.run(
        'explorer',
        resolvedPath.isDirectory
            ? <String>[resolvedPath.resolvedPath]
            : <String>['/select,${resolvedPath.resolvedPath}'],
      );
    } else if (Platform.isLinux) {
      result = await Process.run('xdg-open', <String>[
        resolvedPath.isDirectory
            ? resolvedPath.resolvedPath
            : p.dirname(resolvedPath.resolvedPath),
      ]);
    } else {
      throw const FileSystemException('Unsupported platform.');
    }
    if (result.exitCode == 0) {
      return;
    }
    final message = '${result.stderr}'.trim();
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
        _localizedText(
          context,
          zh: '打开文件位置失败：$error',
          en: 'Failed to open file location: $error',
        ),
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

  @override
  void initState() {
    super.initState();
    _future = resolveExistingMessagePathAsync(
      widget.normalizedPath,
      widget.candidateRoots,
    );
  }

  @override
  void didUpdateWidget(_AsyncFilePathChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.normalizedPath != widget.normalizedPath ||
        oldWidget.candidateRoots.join('|') != widget.candidateRoots.join('|')) {
      _future = resolveExistingMessagePathAsync(
        widget.normalizedPath,
        widget.candidateRoots,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MessageResolvedPath?>(
      future: _future,
      builder: (context, snapshot) {
        final resolvedPath = snapshot.data;
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
                          _localizedText(context, zh: '类型', en: 'Type'),
                          stat.type.toString(),
                        ),
                        _StatRow(
                          _localizedText(context, zh: '大小', en: 'Size'),
                          '${stat.size} bytes',
                        ),
                        _StatRow(
                          _localizedText(context, zh: '修改于', en: 'Modified'),
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

