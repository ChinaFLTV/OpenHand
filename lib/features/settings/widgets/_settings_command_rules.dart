part of 'settings_view.dart';

String _commandRuleMatchModeLabel(
  BuildContext context,
  AiCommandMatchMode matchMode,
) {
  return switch (matchMode) {
    AiCommandMatchMode.simple => openHandLocalizedText(
      context,
      zh: '简单匹配',
      zhHant: '簡單匹配',
      en: 'Simple Match',
      fr: 'Correspondance simple',
      de: 'Einfache Übereinstimmung',
      ja: '単純一致',
    ),
    AiCommandMatchMode.regex => openHandLocalizedText(
      context,
      zh: '正则匹配',
      zhHant: '正則匹配',
      en: 'Regex Match',
      fr: 'Expression régulière',
      de: 'Regex-Übereinstimmung',
      ja: '正規表現一致',
    ),
  };
}

class _CommandRuleTile extends StatelessWidget {
  const _CommandRuleTile.allow({
    required this.rule,
    required this.onEdit,
    required this.onDelete,
  }) : _tone = _CommandRuleTone.allow;

  const _CommandRuleTile.deny({
    required this.rule,
    required this.onEdit,
    required this.onDelete,
  }) : _tone = _CommandRuleTone.deny;

  final AiCommandRule rule;
  final _CommandRuleTone _tone;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final (icon, iconBackgroundColor, iconColor) = switch (_tone) {
      _CommandRuleTone.allow => (
        Icons.verified_outlined,
        colorScheme.primaryContainer,
        colorScheme.onPrimaryContainer,
      ),
      _CommandRuleTone.deny => (
        Icons.block_rounded,
        colorScheme.errorContainer,
        colorScheme.onErrorContainer,
      ),
    };
    final trimmedNote = rule.note.trim();
    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(kOpenHandRadius20),
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
                borderRadius: BorderRadius.circular(kOpenHandRadius14),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: iconColor),
            ),
            kOpenHandHGap14,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(rule.pattern, style: theme.textTheme.titleSmall),
                  kOpenHandGap6,
                  Text(
                    _commandRuleMatchModeLabel(context, rule.matchMode),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                  if (trimmedNote.isNotEmpty) ...[
                    kOpenHandGap8,
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
            kOpenHandHGap12,
            OpenHandRowEditDeleteActions(
              editTooltip: AppLocalizations.of(context)!.commonEdit,
              deleteTooltip: AppLocalizations.of(context)!.commonDelete,
              onEdit: onEdit,
              onDelete: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

enum _CommandRuleTone { allow, deny }

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
          zhHant: '新增禁止命令規則',
          fr: 'Ajouter une règle de commande interdite',
          de: 'Regel für verbotene Befehle hinzufügen',
          ja: '禁止コマンドルールを追加',
        ),
        editTitle: _LocalizedCommandRuleText(
          '编辑禁止命令规则',
          'Edit Deny Command Rule',
          zhHant: '編輯禁止命令規則',
          fr: 'Modifier la règle de commande interdite',
          de: 'Regel für verbotene Befehle bearbeiten',
          ja: '禁止コマンドルールを編集',
        ),
        patternHint: _LocalizedCommandRuleText(
          '例如：rm * 或 ^rm\\s+',
          'For example: rm * or ^rm\\s+',
          zhHant: '例如：rm * 或 ^rm\\s+',
          fr: 'Par exemple : rm * ou ^rm\\s+',
          de: 'Zum Beispiel: rm * oder ^rm\\s+',
          ja: '例: rm * または ^rm\\s+',
        ),
        patternRequired: _LocalizedCommandRuleText(
          '请输入要拦截的命令表达式。',
          'Enter the command pattern to block.',
          zhHant: '請輸入要攔截的命令表達式。',
          fr: 'Saisissez le motif de commande à bloquer.',
          de: 'Geben Sie das zu blockierende Befehlsmuster ein.',
          ja: 'ブロックするコマンドパターンを入力してください。',
        ),
        noteHint: _LocalizedCommandRuleText(
          '可选，用于说明这条规则的用途',
          'Optional description for this rule',
          zhHant: '可選，用於說明這條規則的用途',
          fr: 'Description facultative de cette règle',
          de: 'Optionale Beschreibung dieser Regel',
          ja: 'このルールの用途を説明する任意メモ',
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
          zhHant: '新增允許命令規則',
          fr: 'Ajouter une règle de commande autorisée',
          de: 'Regel für erlaubte Befehle hinzufügen',
          ja: '許可コマンドルールを追加',
        ),
        editTitle: _LocalizedCommandRuleText(
          '编辑允许命令规则',
          'Edit Allow Command Rule',
          zhHant: '編輯允許命令規則',
          fr: 'Modifier la règle de commande autorisée',
          de: 'Regel für erlaubte Befehle bearbeiten',
          ja: '許可コマンドルールを編集',
        ),
        patternHint: _LocalizedCommandRuleText(
          '例如：flutter test * 或 ^git\\s+commit',
          'For example: flutter test * or ^git\\s+commit',
          zhHant: '例如：flutter test * 或 ^git\\s+commit',
          fr: 'Par exemple : flutter test * ou ^git\\s+commit',
          de: 'Zum Beispiel: flutter test * oder ^git\\s+commit',
          ja: '例: flutter test * または ^git\\s+commit',
        ),
        patternRequired: _LocalizedCommandRuleText(
          '请输入要放行的命令表达式。',
          'Enter the command pattern to allow.',
          zhHant: '請輸入要放行的命令表達式。',
          fr: 'Saisissez le motif de commande à autoriser.',
          de: 'Geben Sie das zu erlaubende Befehlsmuster ein.',
          ja: '許可するコマンドパターンを入力してください。',
        ),
        noteHint: _LocalizedCommandRuleText(
          '可选，用于说明为什么允许这条命令',
          'Optional description for why this command is allowed',
          zhHant: '可選，用於說明為什麼允許這條命令',
          fr: 'Description facultative expliquant pourquoi cette commande est autorisée',
          de: 'Optionale Beschreibung, warum dieser Befehl erlaubt ist',
          ja: 'このコマンドを許可する理由を説明する任意メモ',
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
      required AiCommandMatchMode matchMode,
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
  final AiCommandMatchMode Function(T rule) matchModeOf;
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
  late AiCommandMatchMode _matchMode;
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
        ? AiCommandMatchMode.simple
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
    final isEditing = widget.initialRule != null;
    return buildOpenHandAlertDialog(
      title: Text(widget.copy.title(context, isEditing)),
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
                      labelText: openHandLocalizedText(
                        context,
                        zh: '匹配表达式',
                        zhHant: '匹配表達式',
                        en: 'Pattern',
                        fr: 'Motif',
                        de: 'Muster',
                        ja: 'パターン',
                      ),
                      hintText: widget.copy.patternHint.resolve(context),
                    ),
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return widget.copy.patternRequired.resolve(context);
                      }
                      return null;
                    },
                  ),
                  kOpenHandGap16,
                  AnimatedDropdownButtonFormField<AiCommandMatchMode>(
                    initialValue: _matchMode,
                    decoration: InputDecoration(
                      labelText: openHandMatchModeLabel(context),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: AiCommandMatchMode.simple,
                        child: Text(
                          _commandRuleMatchModeLabel(
                            context,
                            AiCommandMatchMode.simple,
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: AiCommandMatchMode.regex,
                        child: Text(
                          _commandRuleMatchModeLabel(
                            context,
                            AiCommandMatchMode.regex,
                          ),
                        ),
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
                  kOpenHandGap16,
                  TextFormField(
                    controller: _noteController,
                    decoration: InputDecoration(
                      labelText: openHandNoteLabel(context),
                      hintText: widget.copy.noteHint.resolve(context),
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

  String title(BuildContext context, bool isEditing) {
    return (isEditing ? editTitle : addTitle).resolve(context);
  }
}

class _LocalizedCommandRuleText {
  const _LocalizedCommandRuleText(
    this.zh,
    this.en, {
    this.zhHant,
    this.fr,
    this.de,
    this.ja,
  });

  final String zh;
  final String en;
  final String? zhHant;
  final String? fr;
  final String? de;
  final String? ja;

  String resolve(BuildContext context) {
    return openHandLocalizedText(
      context,
      zh: zh,
      zhHant: zhHant,
      en: en,
      fr: fr,
      de: de,
      ja: ja,
    );
  }
}
