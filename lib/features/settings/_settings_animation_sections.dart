part of 'settings_view.dart';

/// Compact "Restore animation defaults" action row that resets all four
/// animation buckets (dialog / menu / page / panel) to the lively built-in
/// defaults defined in [AppSettingsSnapshot.defaults]. Useful when a user
/// has tweaked individual fields and wants to re-experience the curated
/// out-of-box motion design without manually replaying every dropdown.
class _AnimationRestoreDefaultsSection extends StatelessWidget {
  const _AnimationRestoreDefaultsSection({required this.settingsController});

  final SettingsController settingsController;

  @override
  Widget build(BuildContext context) {
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    return _ResponsiveSettingRow(
      title: isZh ? '恢复默认动画' : 'Restore Animation Defaults',
      subtitle: isZh
          ? '一键将弹窗、菜单、页面 / 模块、工作区面板这四组动画的进场 / 退场风格、时长、速率曲线全部重置为 OpenHand 推荐的默认值。'
          : 'Reset entrance/exit style, duration, and easing curve for dialog, menu, page/module, and workspace panel animations to OpenHand\'s recommended defaults in one click.',
      controlMaxWidth: 440,
      control: Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(isZh ? '恢复默认' : 'Restore Defaults'),
          onPressed: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(isZh ? '恢复默认动画？' : 'Restore default animations?'),
                content: Text(
                  isZh
                      ? '将把弹窗、菜单、页面 / 模块、工作区面板四组动画全部重置为默认值，已自定义的设置会被覆盖，此操作不可撤销。'
                      : 'Dialog, menu, page/module, and workspace panel animations will all be reset to defaults. Customized values will be overwritten and this cannot be undone.',
                ),
                actions: [
                  // Use FilledButton.tonal for Cancel so it visually balances
                  // the primary FilledButton (same height, padding, shape).
                  // Plain TextButton has different intrinsic height which
                  // makes the two action buttons look mismatched.
                  FilledButton.tonal(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: Text(isZh ? '取消' : 'Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: Text(isZh ? '恢复' : 'Restore'),
                  ),
                ],
              ),
            );
            if (confirmed != true || !context.mounted) {
              return;
            }
            final defaults = AppSettingsSnapshot.defaults();
            final results = await Future.wait([
              settingsController.updateDialogAnimationSettings(
                defaults.dialogAnimationSettings,
              ),
              settingsController.updateMenuAnimationSettings(
                defaults.menuAnimationSettings,
              ),
              settingsController.updatePageAnimationSettings(
                defaults.pageAnimationSettings,
              ),
              settingsController.updatePanelAnimationSettings(
                defaults.panelAnimationSettings,
              ),
            ]);
            if (!context.mounted) return;
            final allSaved = results.every((r) => r);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  allSaved
                      ? (isZh ? '已恢复默认动画设置' : 'Animation defaults restored')
                      : (isZh
                            ? '部分设置保存失败，请重试'
                            : 'Some settings failed to persist, please retry'),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DialogAnimationSettingsSection extends StatelessWidget {
  const _DialogAnimationSettingsSection({required this.settingsController});

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
  const _MenuAnimationSettingsSection({required this.settingsController});

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

class _PanelAnimationSettingsSection extends StatelessWidget {
  const _PanelAnimationSettingsSection({required this.settingsController});

  final SettingsController settingsController;

  @override
  Widget build(BuildContext context) {
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    final current = settingsController.panelAnimationSettings;
    return _ResponsiveSettingRow(
      title: isZh ? '工作区面板动画' : 'Workspace Panel Animation',
      subtitle: isZh
          ? '配置工作区左右面板切换的进场动画、退场动画、时长和速率曲线，例如左侧导航与文件浏览器切换、右侧会话与代码编辑器切换。Settings、MCP、记忆等右侧模块页面切换由“页面动画”控制。'
          : 'Configure entrance/exit animation style, duration, and easing curve for workspace panel transitions, such as left navigation/file explorer and right conversation/code editor switches. Settings, MCP, Memory, and other right-side module page switches are controlled by Page Animation.',
      controlMaxWidth: 440,
      control: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                    settingsController.updatePanelAnimationSettings(
                      current.copyWith(entranceStyle: value),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
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
                    settingsController.updatePanelAnimationSettings(
                      current.copyWith(exitStyle: value),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
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
                          settingsController.updatePanelAnimationSettings(
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
                    settingsController.updatePanelAnimationSettings(
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

class _PageAnimationSettingsSection extends StatelessWidget {
  const _PageAnimationSettingsSection({required this.settingsController});

  final SettingsController settingsController;

  @override
  Widget build(BuildContext context) {
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    final current = settingsController.pageAnimationSettings;
    return _ResponsiveSettingRow(
      title: isZh ? '页面 / 模块动画' : 'Page / Module Animation',
      subtitle: isZh
          ? '配置右侧主内容模块切换的进场动画、退场动画、时长和速率曲线，包括会话、设置、MCP、记忆、Hooks、Crons、技能、自动化等页面之间的切换。'
          : 'Configure entrance/exit animation style, duration, and easing curve for right-side main content module switches, including Workspace, Settings, MCP, Memory, Hooks, Crons, Skills, and Automations.',
      controlMaxWidth: 440,
      control: _AnimationSettingsControl(
        current: current,
        onChanged: (value) {
          settingsController.updatePageAnimationSettings(value);
        },
      ),
    );
  }
}

class _AnimationSettingsControl extends StatelessWidget {
  const _AnimationSettingsControl({
    required this.current,
    required this.onChanged,
  });

  final DialogAnimationSettings current;
  final ValueChanged<DialogAnimationSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 80,
              child: Text(isZh ? '进场' : 'Enter', style: textTheme.labelLarge),
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
                  onChanged(current.copyWith(entranceStyle: value));
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            SizedBox(
              width: 80,
              child: Text(isZh ? '退场' : 'Exit', style: textTheme.labelLarge),
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
                  onChanged(current.copyWith(exitStyle: value));
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            SizedBox(
              width: 80,
              child: Text(
                isZh ? '时长' : 'Duration',
                style: textTheme.labelLarge,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: current.durationMs.toDouble().clamp(100.0, 800.0),
                      min: 100,
                      max: 800,
                      divisions: 14,
                      label: '${current.durationMs}ms',
                      onChanged: (value) {
                        onChanged(current.copyWith(durationMs: value.round()));
                      },
                    ),
                  ),
                  SizedBox(
                    width: 54,
                    child: Text(
                      '${current.durationMs}ms',
                      style: textTheme.labelMedium,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            SizedBox(
              width: 80,
              child: Text(isZh ? '曲线' : 'Curve', style: textTheme.labelLarge),
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
                  onChanged(current.copyWith(curve: value));
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
