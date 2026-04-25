part of 'settings_view.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Builtin Tool Tile (list item in the tool catalog overview)
// ─────────────────────────────────────────────────────────────────────────────

class _BuiltinToolTile extends StatelessWidget {
  const _BuiltinToolTile({
    required this.config,
    required this.isFirst,
    required this.isLast,
    required this.onToggle,
    required this.onEdit,
    this.onMoveUp,
    this.onMoveDown,
    this.onDelete,
  });

  final AiBuiltinToolConfig config;
  final bool isFirst;
  final bool isLast;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onDelete;

  IconData _toolIcon(AiBuiltinToolKind kind) {
    return switch (kind) {
      AiBuiltinToolKind.task => Icons.task_alt_rounded,
      AiBuiltinToolKind.bash => Icons.terminal_rounded,
      AiBuiltinToolKind.glob => Icons.folder_copy_outlined,
      AiBuiltinToolKind.grep => Icons.search_rounded,
      AiBuiltinToolKind.ls => Icons.list_alt_rounded,
      AiBuiltinToolKind.exitPlanMode => Icons.exit_to_app_rounded,
      AiBuiltinToolKind.read => Icons.description_outlined,
      AiBuiltinToolKind.edit => Icons.edit_note_rounded,
      AiBuiltinToolKind.multiEdit => Icons.edit_attributes_rounded,
      AiBuiltinToolKind.write => Icons.save_outlined,
      AiBuiltinToolKind.notebookEdit => Icons.book_outlined,
      AiBuiltinToolKind.webFetch => Icons.language_rounded,
      AiBuiltinToolKind.todoWrite => Icons.checklist_rounded,
      AiBuiltinToolKind.webSearch => Icons.travel_explore_rounded,
      AiBuiltinToolKind.lsp => Icons.code_rounded,
      AiBuiltinToolKind.codebaseSearch => Icons.manage_search_rounded,
      AiBuiltinToolKind.git => Icons.merge_rounded,
      AiBuiltinToolKind.deleteFile => Icons.delete_outline_rounded,
      AiBuiltinToolKind.readLints => Icons.bug_report_outlined,
      AiBuiltinToolKind.askUserChoice => Icons.quiz_outlined,
      AiBuiltinToolKind.skillManager => Icons.auto_stories_rounded,
      AiBuiltinToolKind.memory => Icons.psychology_rounded,
    };
  }

  String _loadStrategyLabel(
    BuildContext context,
    AiBuiltinToolLoadStrategy strategy,
  ) {
    return switch (strategy) {
      AiBuiltinToolLoadStrategy.eager => _localizedText(
        context,
        zh: '立即',
        en: 'Eager',
      ),
      AiBuiltinToolLoadStrategy.lazy => _localizedText(
        context,
        zh: '懒加载',
        en: 'Lazy',
      ),
      AiBuiltinToolLoadStrategy.deferred => _localizedText(
        context,
        zh: '缓加载',
        en: 'Deferred',
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final displayName = config.displayName?.trim().isNotEmpty == true
        ? config.displayName!.trim()
        : config.kind.name;
    final summaryText = config.summary?.trim().isNotEmpty == true
        ? config.summary!.trim()
        : null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: config.enabled
            ? colorScheme.surfaceContainerLow
            : colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: config.enabled
              ? colorScheme.outlineVariant.withValues(alpha: 0.45)
              : colorScheme.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              _toolIcon(config.kind),
              size: 28,
              color: config.enabled
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          displayName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: config.enabled
                                ? colorScheme.onSurface
                                : colorScheme.onSurfaceVariant.withValues(
                                    alpha: 0.6,
                                  ),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (config.isCustom) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.tertiary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _localizedText(context, zh: '自定义', en: 'Custom'),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.tertiary,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer.withValues(
                            alpha: 0.6,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _loadStrategyLabel(context, config.loadStrategy),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.6,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'P${config.priority}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (summaryText != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      summaryText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (config.tags.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      children: config.tags
                          .map(
                            (tag) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer.withValues(
                                  alpha: 0.4,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                tag,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onPrimaryContainer,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onMoveUp != null)
                  IconButton(
                    icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                    tooltip: _localizedText(context, zh: '上移', en: 'Move Up'),
                    onPressed: onMoveUp,
                    visualDensity: VisualDensity.compact,
                  ),
                if (onMoveUp != null) const SizedBox(width: 8),
                if (onMoveDown != null)
                  IconButton(
                    icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                    tooltip: _localizedText(context, zh: '下移', en: 'Move Down'),
                    onPressed: onMoveDown,
                    visualDensity: VisualDensity.compact,
                  ),
                if (onMoveDown != null) const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: _localizedText(context, zh: '编辑', en: 'Edit'),
                  onPressed: onEdit,
                  visualDensity: VisualDensity.compact,
                ),
                if (onDelete != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: colorScheme.error,
                    ),
                    tooltip: _localizedText(context, zh: '删除', en: 'Delete'),
                    onPressed: onDelete,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
                const SizedBox(width: 8),
                Switch(value: config.enabled, onChanged: onToggle),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Builtin Tool Editor Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _BuiltinToolEditorDialog extends StatefulWidget {
  const _BuiltinToolEditorDialog({
    required this.initial,
    this.defaultName,
    this.defaultDescription,
    this.defaultParameters,
  });

  final AiBuiltinToolConfig initial;

  /// Default tool name from the built-in tool catalog (for hint / pre-fill).
  final String? defaultName;

  /// Default tool description from the built-in tool catalog.
  final String? defaultDescription;

  /// Default tool parameters schema from the built-in tool catalog.
  final Map<String, Object?>? defaultParameters;

  @override
  State<_BuiltinToolEditorDialog> createState() =>
      _BuiltinToolEditorDialogState();
}

class _BuiltinToolEditorDialogState extends State<_BuiltinToolEditorDialog> {
  late final TextEditingController _displayNameController;
  late final TextEditingController _summaryController;
  late final TextEditingController _promptOverrideController;
  late final TextEditingController _schemaOverrideController;
  late final TextEditingController _priorityController;
  late final TextEditingController _maxOutputCharsController;
  late final TextEditingController _timeoutSecondsController;
  late final TextEditingController _tagsController;

  late bool _enabled;
  late AiBuiltinToolLoadStrategy _loadStrategy;
  late bool? _requireConfirmation;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.initial;
    _displayNameController = TextEditingController(
      text: c.displayName ?? widget.defaultName ?? '',
    );
    _summaryController = TextEditingController(
      text: c.summary ?? widget.defaultDescription ?? '',
    );
    _promptOverrideController = TextEditingController(
      text: c.promptOverride ?? '',
    );
    final schemaMap = c.schemaOverride ?? widget.defaultParameters;
    _schemaOverrideController = TextEditingController(
      text: schemaMap != null
          ? const JsonEncoder.withIndent('  ').convert(schemaMap)
          : '',
    );
    _priorityController = TextEditingController(text: '${c.priority}');
    _maxOutputCharsController = TextEditingController(
      text: c.maxOutputChars != null ? '${c.maxOutputChars}' : '',
    );
    _timeoutSecondsController = TextEditingController(
      text: c.timeoutSeconds != null ? '${c.timeoutSeconds}' : '',
    );
    _tagsController = TextEditingController(text: c.tags.join(', '));
    _enabled = c.enabled;
    _loadStrategy = c.loadStrategy;
    _requireConfirmation = c.requireConfirmation;
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _summaryController.dispose();
    _promptOverrideController.dispose();
    _schemaOverrideController.dispose();
    _priorityController.dispose();
    _maxOutputCharsController.dispose();
    _timeoutSecondsController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  AiBuiltinToolConfig _buildConfig() {
    final displayName = _displayNameController.text.trim();
    final summary = _summaryController.text.trim();
    final promptOverride = _promptOverrideController.text.trim();
    final schemaText = _schemaOverrideController.text.trim();
    Map<String, Object?>? schemaOverride;
    if (schemaText.isNotEmpty) {
      try {
        final decoded = jsonDecode(schemaText);
        if (decoded is Map) {
          schemaOverride = Map<String, Object?>.from(decoded);
        }
      } catch (_) {
        // Invalid JSON — keep null.
      }
    }
    final priority = int.tryParse(_priorityController.text.trim()) ?? 100;
    final maxOutputChars = int.tryParse(_maxOutputCharsController.text.trim());
    final timeoutSeconds = int.tryParse(_timeoutSecondsController.text.trim());
    final rawTags = _tagsController.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList(growable: false);

    return widget.initial.copyWith(
      enabled: _enabled,
      displayName: displayName.isEmpty ? null : displayName,
      summary: summary.isEmpty ? null : summary,
      promptOverride: promptOverride.isEmpty ? null : promptOverride,
      schemaOverride: schemaOverride,
      priority: priority.clamp(0, 9999),
      loadStrategy: _loadStrategy,
      tags: rawTags,
      maxOutputChars: maxOutputChars,
      timeoutSeconds: timeoutSeconds,
      requireConfirmation: _requireConfirmation,
      clearDisplayName: displayName.isEmpty,
      clearSummary: summary.isEmpty,
      clearPromptOverride: promptOverride.isEmpty,
      clearSchemaOverride: schemaText.isEmpty,
      clearMaxOutputChars: _maxOutputCharsController.text.trim().isEmpty,
      clearTimeoutSeconds: _timeoutSecondsController.text.trim().isEmpty,
      clearRequireConfirmation: _requireConfirmation == null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopScope(
      canPop: !_isSaving,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 780),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──
                Row(
                  children: [
                    Icon(
                      Icons.build_circle_outlined,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _localizedText(
                          context,
                          zh: '编辑工具 — ${widget.initial.kind.name}',
                          en: 'Edit Tool — ${widget.initial.kind.name}',
                        ),
                        style: theme.textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Body (scrollable) ──
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Enabled toggle
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            _localizedText(
                              context,
                              zh: '启用工具',
                              en: 'Enable Tool',
                            ),
                          ),
                          subtitle: Text(
                            _localizedText(
                              context,
                              zh: '禁用后该工具不会出现在模型的工具目录中。',
                              en: 'When disabled, this tool will not appear in the model\'s tool catalog.',
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          value: _enabled,
                          onChanged: (value) =>
                              setState(() => _enabled = value),
                        ),
                        const SizedBox(height: 14),

                        // Display name
                        TextField(
                          controller: _displayNameController,
                          decoration: InputDecoration(
                            labelText: _localizedText(
                              context,
                              zh: '显示名称（可选）',
                              en: 'Display Name (optional)',
                            ),
                            hintText: widget.initial.kind.name,
                            helperText: _localizedText(
                              context,
                              zh: '覆盖默认工具名称，留空则使用内建默认名。',
                              en: 'Overrides the default tool name. Leave blank for the built-in default.',
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Summary
                        TextField(
                          controller: _summaryController,
                          decoration: InputDecoration(
                            labelText: _localizedText(
                              context,
                              zh: '简介（可选）',
                              en: 'Summary (optional)',
                            ),
                            helperText: _localizedText(
                              context,
                              zh: '用于在工具列表中快速了解工具用途。',
                              en: 'Shown in the tool list for quick reference.',
                            ),
                          ),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 14),

                        // Prompt override
                        TextField(
                          controller: _promptOverrideController,
                          decoration: InputDecoration(
                            labelText: _localizedText(
                              context,
                              zh: 'Prompt 追加覆盖（可选）',
                              en: 'Prompt Override (optional)',
                            ),
                            helperText: _localizedText(
                              context,
                              zh: '追加到工具 description 末尾，可用来微调模型对该工具的使用策略。',
                              en: 'Appended to the tool description. Use it to fine-tune how the model uses this tool.',
                            ),
                          ),
                          maxLines: 4,
                          minLines: 2,
                        ),
                        const SizedBox(height: 14),

                        // Schema override
                        TextField(
                          controller: _schemaOverrideController,
                          decoration: InputDecoration(
                            labelText: _localizedText(
                              context,
                              zh: 'Schema 覆盖（JSON，可选）',
                              en: 'Schema Override (JSON, optional)',
                            ),
                            helperText: _localizedText(
                              context,
                              zh: '完整的 JSON Schema 对象，覆盖工具的输入参数定义。留空使用默认。',
                              en: 'Full JSON Schema object to override the tool\'s input parameters. Leave blank for default.',
                            ),
                          ),
                          maxLines: 6,
                          minLines: 3,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Priority & Load Strategy row
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _priorityController,
                                keyboardType: TextInputType.number,
                                inputFormatters: <TextInputFormatter>[
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: InputDecoration(
                                  labelText: _localizedText(
                                    context,
                                    zh: '优先级 (0–9999)',
                                    en: 'Priority (0–9999)',
                                  ),
                                  helperText: _localizedText(
                                    context,
                                    zh: '越小越优先',
                                    en: 'Lower = higher priority',
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child:
                                  DropdownButtonFormField<
                                    AiBuiltinToolLoadStrategy
                                  >(
                                    initialValue: _loadStrategy,
                                    decoration: InputDecoration(
                                      labelText: _localizedText(
                                        context,
                                        zh: '加载策略',
                                        en: 'Load Strategy',
                                      ),
                                    ),
                                    items: AiBuiltinToolLoadStrategy.values
                                        .map(
                                          (s) => DropdownMenuItem(
                                            value: s,
                                            child: Text(
                                              _loadStrategyLabelStatic(
                                                context,
                                                s,
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(growable: false),
                                    onChanged: (value) {
                                      if (value != null) {
                                        setState(() => _loadStrategy = value);
                                      }
                                    },
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Max output chars & Timeout
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _maxOutputCharsController,
                                keyboardType: TextInputType.number,
                                inputFormatters: <TextInputFormatter>[
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: InputDecoration(
                                  labelText: _localizedText(
                                    context,
                                    zh: '输出上限（字符）',
                                    en: 'Max Output (chars)',
                                  ),
                                  hintText: _localizedText(
                                    context,
                                    zh: '使用全局默认',
                                    en: 'Global default',
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: TextField(
                                controller: _timeoutSecondsController,
                                keyboardType: TextInputType.number,
                                inputFormatters: <TextInputFormatter>[
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: InputDecoration(
                                  labelText: _localizedText(
                                    context,
                                    zh: '超时时间（秒）',
                                    en: 'Timeout (seconds)',
                                  ),
                                  hintText: _localizedText(
                                    context,
                                    zh: '使用全局默认',
                                    en: 'Global default',
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Require confirmation
                        _RequireConfirmationField(
                          value: _requireConfirmation,
                          onChanged: (v) =>
                              setState(() => _requireConfirmation = v),
                        ),
                        const SizedBox(height: 14),

                        // Tags
                        TextField(
                          controller: _tagsController,
                          decoration: InputDecoration(
                            labelText: _localizedText(
                              context,
                              zh: '标签（逗号分隔）',
                              en: 'Tags (comma-separated)',
                            ),
                            helperText: _localizedText(
                              context,
                              zh: '例如: io, file, dangerous',
                              en: 'e.g. io, file, dangerous',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Actions ──
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OpenHandDialogActionButton.secondary(
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.of(context).pop(),
                      label: _localizedText(context, zh: '取消', en: 'Cancel'),
                    ),
                    const SizedBox(width: 12),
                    OpenHandDialogActionButton.primary(
                      onPressed: _isSaving
                          ? null
                          : () {
                              setState(() => _isSaving = true);
                              Navigator.of(context).pop(_buildConfig());
                            },
                      label: _localizedText(context, zh: '保存', en: 'Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _loadStrategyLabelStatic(
    BuildContext context,
    AiBuiltinToolLoadStrategy strategy,
  ) {
    final languageCode = Localizations.localeOf(context).languageCode;
    final zh = languageCode.startsWith('zh');
    return switch (strategy) {
      AiBuiltinToolLoadStrategy.eager => zh ? '立即加载' : 'Eager',
      AiBuiltinToolLoadStrategy.lazy => zh ? '懒加载' : 'Lazy',
      AiBuiltinToolLoadStrategy.deferred => zh ? '缓加载' : 'Deferred',
    };
  }
}

class _RequireConfirmationField extends StatelessWidget {
  const _RequireConfirmationField({
    required this.value,
    required this.onChanged,
  });

  final bool? value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _localizedText(context, zh: '执行确认', en: 'Require Confirmation'),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        Text(
          _localizedText(
            context,
            zh: '是否在执行前弹窗让用户确认。选"默认"时使用工具自身的行为。',
            en:
                'Whether to prompt user confirmation before execution. '
                '"Default" uses the tool\'s built-in behavior.',
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<bool?>(
          segments: [
            ButtonSegment<bool?>(
              value: null,
              label: Text(
                _localizedText(context, zh: '默认', en: 'Default'),
                softWrap: false,
              ),
            ),
            ButtonSegment<bool?>(
              value: true,
              label: Text(
                _localizedText(context, zh: '需要确认', en: 'Yes'),
                softWrap: false,
              ),
            ),
            ButtonSegment<bool?>(
              value: false,
              label: Text(
                _localizedText(context, zh: '无需确认', en: 'No'),
                softWrap: false,
              ),
            ),
          ],
          selected: {value},
          onSelectionChanged: (selection) {
            if (selection.isNotEmpty) {
              onChanged(selection.first);
            }
          },
        ),
      ],
    );
  }
}
