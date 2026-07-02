part of 'settings_view.dart';

class _DenyCommandRuleTile extends StatelessWidget {
  const _DenyCommandRuleTile({
    required this.rule,
    required this.onEdit,
    required this.onDelete,
  });

  final AiDenyCommandRule rule;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return _CommandRuleTile(
      pattern: rule.pattern,
      note: rule.note,
      matchMode: rule.matchMode,
      icon: Icons.block_rounded,
      iconBackgroundColor: colorScheme.errorContainer,
      iconColor: colorScheme.onErrorContainer,
      onEdit: onEdit,
      onDelete: onDelete,
    );
  }
}

class _AllowCommandRuleTile extends StatelessWidget {
  const _AllowCommandRuleTile({
    required this.rule,
    required this.onEdit,
    required this.onDelete,
  });

  final AiAllowCommandRule rule;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return _CommandRuleTile(
      pattern: rule.pattern,
      note: rule.note,
      matchMode: rule.matchMode,
      icon: Icons.verified_outlined,
      iconBackgroundColor: colorScheme.primaryContainer,
      iconColor: colorScheme.onPrimaryContainer,
      onEdit: onEdit,
      onDelete: onDelete,
    );
  }
}

class _CommandRuleTile extends StatelessWidget {
  const _CommandRuleTile({
    required this.pattern,
    required this.note,
    required this.matchMode,
    required this.icon,
    required this.iconBackgroundColor,
    required this.iconColor,
    required this.onEdit,
    required this.onDelete,
  });

  final String pattern;
  final String note;
  final AiDenyCommandMatchMode matchMode;
  final IconData icon;
  final Color iconBackgroundColor;
  final Color iconColor;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isChinese = openHandIsChineseLocale(context);
    final trimmedNote = note.trim();
    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBackgroundColor,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pattern, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Text(
                    matchMode == AiDenyCommandMatchMode.regex
                        ? (isChinese ? '正则匹配' : 'Regex Match')
                        : (isChinese ? '简单匹配' : 'Simple Match'),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                  if (trimmedNote.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      trimmedNote,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              onPressed: onEdit,
              tooltip: AppLocalizations.of(context)!.commonEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              onPressed: onDelete,
              tooltip: AppLocalizations.of(context)!.commonDelete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _DenyCommandRuleDialog extends StatelessWidget {
  const _DenyCommandRuleDialog({required this.draftRuleId, this.initialRule});

  final AiDenyCommandRule? initialRule;
  final String draftRuleId;

  @override
  Widget build(BuildContext context) {
    return _CommandRuleEditorDialog<AiDenyCommandRule>(
      initialRule: initialRule,
      draftRuleId: draftRuleId,
      copy: const _CommandRuleEditorCopy(
        addTitle: _LocalizedCommandRuleText(
          '新增禁止命令规则',
          'Add Deny Command Rule',
        ),
        editTitle: _LocalizedCommandRuleText(
          '编辑禁止命令规则',
          'Edit Deny Command Rule',
        ),
        patternHint: _LocalizedCommandRuleText(
          '例如：rm * 或 ^rm\\s+',
          'For example: rm * or ^rm\\s+',
        ),
        patternRequired: _LocalizedCommandRuleText(
          '请输入要拦截的命令表达式。',
          'Enter the command pattern to block.',
        ),
        noteHint: _LocalizedCommandRuleText(
          '可选，用于说明这条规则的用途',
          'Optional description for this rule',
        ),
      ),
      idOf: (rule) => rule.id,
      patternOf: (rule) => rule.pattern,
      matchModeOf: (rule) => rule.matchMode,
      noteOf: (rule) => rule.note,
      buildRule:
          ({
            required id,
            required pattern,
            required matchMode,
            required note,
          }) => AiDenyCommandRule(
            id: id,
            pattern: pattern,
            matchMode: matchMode,
            note: note,
          ),
    );
  }
}

class _AllowCommandRuleDialog extends StatelessWidget {
  const _AllowCommandRuleDialog({required this.draftRuleId, this.initialRule});

  final AiAllowCommandRule? initialRule;
  final String draftRuleId;

  @override
  Widget build(BuildContext context) {
    return _CommandRuleEditorDialog<AiAllowCommandRule>(
      initialRule: initialRule,
      draftRuleId: draftRuleId,
      copy: const _CommandRuleEditorCopy(
        addTitle: _LocalizedCommandRuleText(
          '新增允许命令规则',
          'Add Allow Command Rule',
        ),
        editTitle: _LocalizedCommandRuleText(
          '编辑允许命令规则',
          'Edit Allow Command Rule',
        ),
        patternHint: _LocalizedCommandRuleText(
          '例如：flutter test * 或 ^git\\s+commit',
          'For example: flutter test * or ^git\\s+commit',
        ),
        patternRequired: _LocalizedCommandRuleText(
          '请输入要放行的命令表达式。',
          'Enter the command pattern to allow.',
        ),
        noteHint: _LocalizedCommandRuleText(
          '可选，用于说明为什么允许这条命令',
          'Optional description for why this command is allowed',
        ),
      ),
      idOf: (rule) => rule.id,
      patternOf: (rule) => rule.pattern,
      matchModeOf: (rule) => rule.matchMode,
      noteOf: (rule) => rule.note,
      buildRule:
          ({
            required id,
            required pattern,
            required matchMode,
            required note,
          }) => AiAllowCommandRule(
            id: id,
            pattern: pattern,
            matchMode: matchMode,
            note: note,
          ),
    );
  }
}

typedef _CommandRuleBuilder<T> =
    T Function({
      required String id,
      required String pattern,
      required AiDenyCommandMatchMode matchMode,
      required String note,
    });

class _CommandRuleEditorDialog<T> extends StatefulWidget {
  const _CommandRuleEditorDialog({
    required this.initialRule,
    required this.draftRuleId,
    required this.copy,
    required this.idOf,
    required this.patternOf,
    required this.matchModeOf,
    required this.noteOf,
    required this.buildRule,
  });

  final T? initialRule;
  final String draftRuleId;
  final _CommandRuleEditorCopy copy;
  final String Function(T rule) idOf;
  final String Function(T rule) patternOf;
  final AiDenyCommandMatchMode Function(T rule) matchModeOf;
  final String Function(T rule) noteOf;
  final _CommandRuleBuilder<T> buildRule;

  @override
  State<_CommandRuleEditorDialog<T>> createState() =>
      _CommandRuleEditorDialogState<T>();
}

class _CommandRuleEditorDialogState<T>
    extends State<_CommandRuleEditorDialog<T>> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _patternController;
  late final TextEditingController _noteController;
  late AiDenyCommandMatchMode _matchMode;
  final ValueNotifier<int> _errorPulse = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    final initialRule = widget.initialRule;
    _patternController = TextEditingController(
      text: initialRule == null ? '' : widget.patternOf(initialRule),
    );
    _noteController = TextEditingController(
      text: initialRule == null ? '' : widget.noteOf(initialRule),
    );
    _matchMode = initialRule == null
        ? AiDenyCommandMatchMode.simple
        : widget.matchModeOf(initialRule);
  }

  @override
  void dispose() {
    _patternController.dispose();
    _noteController.dispose();
    _errorPulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isChinese = openHandIsChineseLocale(context);
    final isEditing = widget.initialRule != null;
    return buildOpenHandAlertDialog(
      title: Text(widget.copy.title(isChinese, isEditing)),
      content: SizedBox(
        width: 560,
        child: Stack(
          children: [
            Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _patternController,
                    decoration: InputDecoration(
                      labelText: isChinese ? '匹配表达式' : 'Pattern',
                      hintText: widget.copy.patternHint.resolve(isChinese),
                    ),
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return widget.copy.patternRequired.resolve(isChinese);
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<AiDenyCommandMatchMode>(
                    initialValue: _matchMode,
                    decoration: InputDecoration(
                      labelText: isChinese ? '匹配模式' : 'Match Mode',
                    ),
                    items: [
                      DropdownMenuItem(
                        value: AiDenyCommandMatchMode.simple,
                        child: Text(isChinese ? '简单匹配' : 'Simple Match'),
                      ),
                      DropdownMenuItem(
                        value: AiDenyCommandMatchMode.regex,
                        child: Text(isChinese ? '正则匹配' : 'Regex Match'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _matchMode = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _noteController,
                    decoration: InputDecoration(
                      labelText: isChinese ? '备注' : 'Note',
                      hintText: widget.copy.noteHint.resolve(isChinese),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: HighlightPulse(
                  signal: _errorPulse,
                  color: OpenHandStatusColors.error,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          label: l10n.commonCancel,
        ),
        OpenHandDialogActionButton.primary(
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              _errorPulse.value++;
              return;
            }
            final initialRule = widget.initialRule;
            Navigator.of(context).pop(
              widget.buildRule(
                id: initialRule == null
                    ? widget.draftRuleId
                    : widget.idOf(initialRule),
                pattern: _patternController.text.trim(),
                matchMode: _matchMode,
                note: _noteController.text.trim(),
              ),
            );
          },
          label: l10n.commonSave,
        ),
      ],
    );
  }
}

class _CommandRuleEditorCopy {
  const _CommandRuleEditorCopy({
    required this.addTitle,
    required this.editTitle,
    required this.patternHint,
    required this.patternRequired,
    required this.noteHint,
  });

  final _LocalizedCommandRuleText addTitle;
  final _LocalizedCommandRuleText editTitle;
  final _LocalizedCommandRuleText patternHint;
  final _LocalizedCommandRuleText patternRequired;
  final _LocalizedCommandRuleText noteHint;

  String title(bool isChinese, bool isEditing) {
    return (isEditing ? editTitle : addTitle).resolve(isChinese);
  }
}

class _LocalizedCommandRuleText {
  const _LocalizedCommandRuleText(this.zh, this.en);

  final String zh;
  final String en;

  String resolve(bool isChinese) => isChinese ? zh : en;
}
