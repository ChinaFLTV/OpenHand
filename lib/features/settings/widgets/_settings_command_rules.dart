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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isChinese = Localizations.localeOf(
      context,
    ).languageCode.startsWith('zh');
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
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.block_rounded,
                color: colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(rule.pattern, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Text(
                    rule.matchMode == AiDenyCommandMatchMode.regex
                        ? (isChinese ? '正则匹配' : 'Regex Match')
                        : (isChinese ? '简单匹配' : 'Simple Match'),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                  if (rule.note.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      rule.note.trim(),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isChinese = Localizations.localeOf(
      context,
    ).languageCode.startsWith('zh');
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
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.verified_outlined,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(rule.pattern, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Text(
                    rule.matchMode == AiDenyCommandMatchMode.regex
                        ? (isChinese ? '正则匹配' : 'Regex Match')
                        : (isChinese ? '简单匹配' : 'Simple Match'),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                  if (rule.note.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      rule.note.trim(),
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

class _DenyCommandRuleDialog extends StatefulWidget {
  const _DenyCommandRuleDialog({required this.draftRuleId, this.initialRule});

  final AiDenyCommandRule? initialRule;
  final String draftRuleId;

  @override
  State<_DenyCommandRuleDialog> createState() => _DenyCommandRuleDialogState();
}

class _DenyCommandRuleDialogState extends State<_DenyCommandRuleDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _patternController;
  late final TextEditingController _noteController;
  late AiDenyCommandMatchMode _matchMode;
  final ValueNotifier<int> _errorPulse = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _patternController = TextEditingController(
      text: widget.initialRule?.pattern ?? '',
    );
    _noteController = TextEditingController(
      text: widget.initialRule?.note ?? '',
    );
    _matchMode = widget.initialRule?.matchMode ?? AiDenyCommandMatchMode.simple;
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
    final isChinese = Localizations.localeOf(
      context,
    ).languageCode.startsWith('zh');
    return AlertDialog(
      title: Text(
        isChinese
            ? (widget.initialRule == null ? '新增禁止命令规则' : '编辑禁止命令规则')
            : (widget.initialRule == null
                  ? 'Add Deny Command Rule'
                  : 'Edit Deny Command Rule'),
      ),
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
                      hintText: isChinese
                          ? '例如：rm * 或 ^rm\\s+'
                          : 'For example: rm * or ^rm\\s+',
                    ),
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return isChinese
                            ? '请输入要拦截的命令表达式。'
                            : 'Enter the command pattern to block.';
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
                      hintText: isChinese
                          ? '可选，用于说明这条规则的用途'
                          : 'Optional description for this rule',
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
                  color: const Color(0xFFEF4444),
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
            Navigator.of(context).pop(
              AiDenyCommandRule(
                id: widget.initialRule?.id ?? widget.draftRuleId,
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

class _AllowCommandRuleDialog extends StatefulWidget {
  const _AllowCommandRuleDialog({required this.draftRuleId, this.initialRule});

  final AiAllowCommandRule? initialRule;
  final String draftRuleId;

  @override
  State<_AllowCommandRuleDialog> createState() =>
      _AllowCommandRuleDialogState();
}

class _AllowCommandRuleDialogState extends State<_AllowCommandRuleDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _patternController;
  late final TextEditingController _noteController;
  late AiDenyCommandMatchMode _matchMode;
  final ValueNotifier<int> _errorPulse = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _patternController = TextEditingController(
      text: widget.initialRule?.pattern ?? '',
    );
    _noteController = TextEditingController(
      text: widget.initialRule?.note ?? '',
    );
    _matchMode = widget.initialRule?.matchMode ?? AiDenyCommandMatchMode.simple;
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
    final isChinese = Localizations.localeOf(
      context,
    ).languageCode.startsWith('zh');
    return AlertDialog(
      title: Text(
        isChinese
            ? (widget.initialRule == null ? '新增允许命令规则' : '编辑允许命令规则')
            : (widget.initialRule == null
                  ? 'Add Allow Command Rule'
                  : 'Edit Allow Command Rule'),
      ),
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
                      hintText: isChinese
                          ? '例如：flutter test * 或 ^git\\s+commit'
                          : 'For example: flutter test * or ^git\\s+commit',
                    ),
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return isChinese
                            ? '请输入要放行的命令表达式。'
                            : 'Enter the command pattern to allow.';
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
                      hintText: isChinese
                          ? '可选，用于说明为什么允许这条命令'
                          : 'Optional description for why this command is allowed',
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
                  color: const Color(0xFFEF4444),
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
            Navigator.of(context).pop(
              AiAllowCommandRule(
                id: widget.initialRule?.id ?? widget.draftRuleId,
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
