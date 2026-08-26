part of 'settings_view.dart';

class _ShortcutBindingTile extends StatelessWidget {
  const _ShortcutBindingTile({
    required this.actionStorageKey,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onRecord,
    required this.onReset,
  });

  final String actionStorageKey;
  final String title;
  final String subtitle;
  final String value;
  final VoidCallback onRecord;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(kOpenHandRadius20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 680;
            final content = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                kOpenHandGap6,
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            );
            const double kCtrlHeight = 40;
            const double kValueMinWidth = 136;
            const double kValueMaxWidth = 260;
            final controls = Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: stacked ? WrapAlignment.start : WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: kValueMinWidth,
                    maxWidth: kValueMaxWidth,
                  ),
                  child: SizedBox(
                    height: kCtrlHeight,
                    child: DecoratedBox(
                      key: ValueKey<String>('shortcut-value-$actionStorageKey'),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(kOpenHandRadius14),
                        border: Border.all(color: colorScheme.outlineVariant),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Align(
                          widthFactor: 1,
                          child: Tooltip(
                            message: value,
                            child: Text(
                              value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: kCtrlHeight,
                  child: OutlinedButton.icon(
                    key: ValueKey<String>('shortcut-record-$actionStorageKey'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, kCtrlHeight),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(kOpenHandRadius14),
                      ),
                    ),
                    onPressed: onRecord,
                    icon: const Icon(Icons.keyboard_alt_rounded, size: 18),
                    label: Text(l10n.settingsShortcutRecord),
                  ),
                ),
                SizedBox(
                  height: kCtrlHeight,
                  width: kCtrlHeight,
                  child: IconButton(
                    key: ValueKey<String>('shortcut-reset-$actionStorageKey'),
                    onPressed: onReset,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(kOpenHandRadius14),
                      ),
                      side: BorderSide(color: colorScheme.outlineVariant),
                    ),
                    tooltip: l10n.settingsShortcutResetToDefault,
                    icon: const Icon(Icons.restart_alt_rounded, size: 18),
                  ),
                ),
              ],
            );
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [content, kOpenHandGap14, controls],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: content),
                kOpenHandHGap16,
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.topEnd,
                    child: controls,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ShortcutRecorderDialog extends StatefulWidget {
  const _ShortcutRecorderDialog({
    required this.title,
    required this.initialKeyIds,
  });

  final String title;
  final List<int> initialKeyIds;

  @override
  State<_ShortcutRecorderDialog> createState() =>
      _ShortcutRecorderDialogState();
}

class _ShortcutRecorderDialogState extends State<_ShortcutRecorderDialog> {
  late final FocusNode _focusNode;
  late List<int> _currentKeyIds;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _currentKeyIds = normalizeShortcutKeyIds(widget.initialKeyIds);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_focusNode.hasFocus) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.handled;
    }
    final nextKeyIds = normalizeShortcutKeyIds(
      HardwareKeyboard.instance.logicalKeysPressed.map((key) => key.keyId),
    );
    if (nextKeyIds.length > openHandShortcutMaxKeyCount) {
      setState(() {
        _errorText = AppLocalizations.of(context)!.settingsShortcutMaxKeysError;
      });
      return KeyEventResult.handled;
    }
    setState(() {
      _currentKeyIds = nextKeyIds;
      _errorText = null;
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final canSave = isValidShortcutBinding(_currentKeyIds);
    return buildOpenHandAlertDialog(
      title: Text(widget.title),
      content: Focus(
        focusNode: _focusNode,
        onKeyEvent: _handleKeyEvent,
        autofocus: true,
        child: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.settingsShortcutRecorderBody),
              kOpenHandGap14,
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(kOpenHandRadius16),
                ),
                child: Text(
                  formatShortcutLabel(_currentKeyIds),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              kOpenHandGap10,
              Text(
                l10n.settingsShortcutRecorderTip,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              OpenHandDialogErrorText(
                message: _errorText,
                topGap: 10,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          label: l10n.commonCancel,
        ),
        OpenHandDialogActionButton.primary(
          onPressed: canSave
              ? () => Navigator.of(
                  context,
                ).pop(normalizeShortcutKeyIds(_currentKeyIds))
              : null,
          label: l10n.commonSave,
        ),
      ],
    );
  }
}
