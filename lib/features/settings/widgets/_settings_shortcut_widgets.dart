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
    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 680;
            final content = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            );
            // 2026-05-19 — 三件控件统一高度 40：原来 Container 自由撑高、
            // OutlinedButton.icon ≈40、IconButton ≈48，视觉错位。Wrap 每个
            // 子控件到 SizedBox(height: kCtrlHeight) 并把 IconButton 拉成
            // 正方形 40x40，整体协调。
            const double kCtrlHeight = 40;
            final controls = Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  height: kCtrlHeight,
                  child: Container(
                    key: ValueKey<String>('shortcut-value-$actionStorageKey'),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: Text(
                      value,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
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
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: onRecord,
                    icon: const Icon(Icons.keyboard_alt_rounded, size: 18),
                    label: Text(
                      Localizations.localeOf(
                            context,
                          ).languageCode.startsWith('zh')
                          ? '录制'
                          : 'Record',
                    ),
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
                        borderRadius: BorderRadius.circular(14),
                      ),
                      side: BorderSide(color: colorScheme.outlineVariant),
                    ),
                    tooltip:
                        Localizations.localeOf(
                          context,
                        ).languageCode.startsWith('zh')
                        ? '恢复默认'
                        : 'Reset to default',
                    icon: const Icon(Icons.restart_alt_rounded, size: 18),
                  ),
                ),
              ],
            );
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [content, const SizedBox(height: 14), controls],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: content),
                const SizedBox(width: 16),
                Flexible(child: controls),
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
        _errorText =
            Localizations.localeOf(context).languageCode.startsWith('zh')
            ? '最多支持同时按下 4 个按键。'
            : 'OpenHand supports up to four simultaneous keys.';
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
    final isChinese = Localizations.localeOf(
      context,
    ).languageCode.startsWith('zh');
    final canSave = isValidShortcutBinding(_currentKeyIds);
    return AlertDialog(
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
              Text(
                isChinese
                    ? '按下新的组合键即可更新绑定。最多支持同时按下 4 个按键。'
                    : 'Press the new key combination to update this binding. OpenHand supports up to four simultaneous keys.',
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  formatShortcutLabel(_currentKeyIds),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                isChinese
                    ? '提示：至少需要一个非修饰键，例如 Enter、P、方向键。'
                    : 'Tip: include at least one non-modifier key such as Enter, P, or an arrow key.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 10),
                Text(
                  _errorText!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          label: AppLocalizations.of(context)!.commonCancel,
        ),
        OpenHandDialogActionButton.primary(
          onPressed: canSave
              ? () => Navigator.of(
                  context,
                ).pop(normalizeShortcutKeyIds(_currentKeyIds))
              : null,
          label: AppLocalizations.of(context)!.commonSave,
        ),
      ],
    );
  }
}
