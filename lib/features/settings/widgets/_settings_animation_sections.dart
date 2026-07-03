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
    final l10n = AppLocalizations.of(context)!;
    return _ResponsiveSettingRow(
      title: l10n.settingsAnimationRestoreDefaultsTitle,
      subtitle: l10n.settingsAnimationRestoreDefaultsSubtitle,
      controlMaxWidth: 440,
      control: Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(l10n.settingsAnimationRestoreDefaultsButton),
          onPressed: () async {
            final confirmed = await showOpenHandConfirmDialog(
              context: context,
              title: l10n.settingsAnimationRestoreConfirmTitle,
              message: l10n.settingsAnimationRestoreConfirmMessage,
              cancelLabel: l10n.commonCancel,
              confirmLabel: l10n.settingsAnimationRestoreConfirm,
            );
            if (!confirmed || !context.mounted) {
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
              settingsController.updateChipAnimationSettings(
                defaults.chipAnimationSettings,
              ),
              settingsController.updateListItemAnimationSettings(
                defaults.listItemAnimationSettings,
              ),
            ]);
            if (!context.mounted) return;
            final allSaved = results.every((r) => r);
            final messenger = ScaffoldMessenger.of(context);
            OpenHandSnackBar.show(
              context,
              messenger,
              allSaved
                  ? OpenHandSnackBar.success(
                      context,
                      l10n.settingsAnimationRestoreSuccess,
                    )
                  : OpenHandSnackBar.error(
                      context,
                      l10n.settingsAnimationRestorePartialFailure,
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
    final l10n = AppLocalizations.of(context)!;
    final current = settingsController.dialogAnimationSettings;
    return _ResponsiveSettingRow(
      title: l10n.settingsDialogAnimationTitle,
      subtitle: l10n.settingsDialogAnimationSubtitle,
      controlMaxWidth: 440,
      control: _AnimationSettingsControl(
        current: current,
        onChanged: (value) {
          settingsController.updateDialogAnimationSettings(value);
        },
      ),
    );
  }
}

class _MenuAnimationSettingsSection extends StatelessWidget {
  const _MenuAnimationSettingsSection({required this.settingsController});

  final SettingsController settingsController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final current = settingsController.menuAnimationSettings;
    return _ResponsiveSettingRow(
      title: l10n.settingsMenuAnimationTitle,
      subtitle: l10n.settingsMenuAnimationSubtitle,
      controlMaxWidth: 440,
      control: _AnimationSettingsControl(
        current: current,
        onChanged: (value) {
          settingsController.updateMenuAnimationSettings(value);
        },
      ),
    );
  }
}

class _PanelAnimationSettingsSection extends StatelessWidget {
  const _PanelAnimationSettingsSection({required this.settingsController});

  final SettingsController settingsController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final current = settingsController.panelAnimationSettings;
    return _ResponsiveSettingRow(
      title: l10n.settingsPanelAnimationTitle,
      subtitle: l10n.settingsPanelAnimationSubtitle,
      controlMaxWidth: 440,
      control: _AnimationSettingsControl(
        current: current,
        onChanged: (value) {
          settingsController.updatePanelAnimationSettings(value);
        },
      ),
    );
  }
}

class _PageAnimationSettingsSection extends StatelessWidget {
  const _PageAnimationSettingsSection({required this.settingsController});

  final SettingsController settingsController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final current = settingsController.pageAnimationSettings;
    return _ResponsiveSettingRow(
      title: l10n.settingsPageAnimationTitle,
      subtitle: l10n.settingsPageAnimationSubtitle,
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

/// Animation settings for chip-shaped removable badges throughout the
/// app — selected skill chip, attachment chips, project reference
/// chips, queued message chips, editing pill, etc. Drives both the
/// entrance animation when a chip is added and the exit animation
/// when its X-button is tapped (the chip animates out, then collapses
/// its slot in the Wrap/Column before being removed from the data
/// model).
class _ChipAnimationSettingsSection extends StatelessWidget {
  const _ChipAnimationSettingsSection({required this.settingsController});

  final SettingsController settingsController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final current = settingsController.chipAnimationSettings;
    return _ResponsiveSettingRow(
      title: l10n.settingsChipAnimationTitle,
      subtitle: l10n.settingsChipAnimationSubtitle,
      controlMaxWidth: 440,
      control: _AnimationSettingsControl(
        current: current,
        onChanged: (value) {
          settingsController.updateChipAnimationSettings(value);
        },
      ),
    );
  }
}

/// Animation settings for list-item entrance throughout the app —
/// MCP servers, memory entries, instruction cards, sidebar threads,
/// and tool-call cards. Removals use their own confirmation dialog motion.
class _ListItemAnimationSettingsSection extends StatelessWidget {
  const _ListItemAnimationSettingsSection({required this.settingsController});

  final SettingsController settingsController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final current = settingsController.listItemAnimationSettings;
    return _ResponsiveSettingRow(
      title: l10n.settingsListItemAnimationTitle,
      subtitle: l10n.settingsListItemAnimationSubtitle,
      controlMaxWidth: 440,
      control: _AnimationSettingsControl(
        current: current,
        onChanged: (value) {
          settingsController.updateListItemAnimationSettings(value);
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
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 80,
              child: Text(
                l10n.settingsAnimationEnter,
                style: textTheme.labelLarge,
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
                          style.label(l10n),
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
              child: Text(
                l10n.settingsAnimationExit,
                style: textTheme.labelLarge,
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
                          style.label(l10n),
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
                l10n.settingsAnimationDuration,
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
              child: Text(
                l10n.settingsAnimationCurve,
                style: textTheme.labelLarge,
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
                          curve.label(l10n),
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
