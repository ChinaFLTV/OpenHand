part of 'settings_view.dart';

class _DialogAnimationSettingsSection extends StatelessWidget {
  const _DialogAnimationSettingsSection({
    required this.settingsController,
  });

  final SettingsController settingsController;

  @override
  Widget build(BuildContext context) {
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    final current = settingsController.dialogAnimationSettings;
    return _ResponsiveSettingRow(
      title: isZh ? '弹窗动画' : 'Dialog Animation',
      subtitle: isZh
          ? '配置全局弹窗的进场动画、退场动画、时长和速率曲线。'
          : 'Configure entrance/exit animation style, duration, and easing curve for all dialogs.',

      controlMaxWidth: 440,
      control: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Entrance style
          Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  isZh ? '进场' : 'Enter',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<DialogAnimationStyle>(
                  initialValue: current.entranceStyle,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(),
                  ),
                  items: DialogAnimationStyle.values
                      .map(
                        (style) => DropdownMenuItem(
                          value: style,
                          child: Text(
                            style.label(isZh),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    settingsController.updateDialogAnimationSettings(
                      current.copyWith(entranceStyle: value),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Exit style
          Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  isZh ? '退场' : 'Exit',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<DialogAnimationStyle>(
                  initialValue: current.exitStyle,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(),
                  ),
                  items: DialogAnimationStyle.values
                      .map(
                        (style) => DropdownMenuItem(
                          value: style,
                          child: Text(
                            style.label(isZh),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    settingsController.updateDialogAnimationSettings(
                      current.copyWith(exitStyle: value),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Duration
          Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  isZh ? '时长' : 'Duration',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: current.durationMs.toDouble(),
                        min: 100,
                        max: 800,
                        divisions: 14,
                        label: '${current.durationMs}ms',
                        onChanged: (value) {
                          settingsController.updateDialogAnimationSettings(
                            current.copyWith(durationMs: value.round()),
                          );
                        },
                      ),
                    ),
                    SizedBox(
                      width: 54,
                      child: Text(
                        '${current.durationMs}ms',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Curve
          Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  isZh ? '曲线' : 'Curve',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<DialogAnimationCurve>(
                  initialValue: current.curve,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(),
                  ),
                  items: DialogAnimationCurve.values
                      .map(
                        (curve) => DropdownMenuItem(
                          value: curve,
                          child: Text(
                            curve.label(isZh),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    settingsController.updateDialogAnimationSettings(
                      current.copyWith(curve: value),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MenuAnimationSettingsSection extends StatelessWidget {
  const _MenuAnimationSettingsSection({
    required this.settingsController,
  });

  final SettingsController settingsController;

  @override
  Widget build(BuildContext context) {
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    final current = settingsController.menuAnimationSettings;
    return _ResponsiveSettingRow(
      title: isZh ? '菜单动画' : 'Menu Animation',
      subtitle: isZh
          ? '配置弹出菜单、右键菜单和下拉菜单的进场动画、退场动画、时长和速率曲线。'
          : 'Configure entrance/exit animation style, duration, and easing curve for popup menus and context menus.',
      controlMaxWidth: 440,
      control: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Entrance style
          Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  isZh ? '进场' : 'Enter',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<DialogAnimationStyle>(
                  initialValue: current.entranceStyle,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(),
                  ),
                  items: DialogAnimationStyle.values
                      .map(
                        (style) => DropdownMenuItem(
                          value: style,
                          child: Text(
                            style.label(isZh),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    settingsController.updateMenuAnimationSettings(
                      current.copyWith(entranceStyle: value),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Exit style
          Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  isZh ? '退场' : 'Exit',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<DialogAnimationStyle>(
                  initialValue: current.exitStyle,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(),
                  ),
                  items: DialogAnimationStyle.values
                      .map(
                        (style) => DropdownMenuItem(
                          value: style,
                          child: Text(
                            style.label(isZh),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    settingsController.updateMenuAnimationSettings(
                      current.copyWith(exitStyle: value),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Duration
          Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  isZh ? '时长' : 'Duration',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: current.durationMs.toDouble(),
                        min: 100,
                        max: 800,
                        divisions: 14,
                        label: '${current.durationMs}ms',
                        onChanged: (value) {
                          settingsController.updateMenuAnimationSettings(
                            current.copyWith(durationMs: value.round()),
                          );
                        },
                      ),
                    ),
                    SizedBox(
                      width: 54,
                      child: Text(
                        '${current.durationMs}ms',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Curve
          Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  isZh ? '曲线' : 'Curve',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<DialogAnimationCurve>(
                  initialValue: current.curve,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(),
                  ),
                  items: DialogAnimationCurve.values
                      .map(
                        (curve) => DropdownMenuItem(
                          value: curve,
                          child: Text(
                            curve.label(isZh),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    settingsController.updateMenuAnimationSettings(
                      current.copyWith(curve: value),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
