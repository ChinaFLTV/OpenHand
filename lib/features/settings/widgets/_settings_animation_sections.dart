part of 'settings_view.dart';

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
        alignment: AlignmentDirectional.centerEnd,
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
            final saved = await settingsController
                .restoreDefaultAnimationSettings();
            if (!context.mounted) return;
            if (saved) {
              showOpenHandSuccessSnack(
                context,
                l10n.settingsAnimationRestoreSuccess,
              );
            } else {
              showOpenHandErrorSnack(
                context,
                l10n.settingsPersistenceSaveFailedTitle,
              );
            }
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
        onChanged: settingsController.updateDialogAnimationSettings,
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
        onChanged: settingsController.updateMenuAnimationSettings,
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
        onChanged: settingsController.updatePanelAnimationSettings,
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
        onChanged: settingsController.updatePageAnimationSettings,
      ),
    );
  }
}

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
        onChanged: settingsController.updateChipAnimationSettings,
      ),
    );
  }
}

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
        onChanged: settingsController.updateListItemAnimationSettings,
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
        _buildStyleRow(
          label: l10n.settingsAnimationEnter,
          value: current.entranceStyle,
          textTheme: textTheme,
          l10n: l10n,
          onStyleChanged: (value) {
            onChanged(current.copyWith(entranceStyle: value));
          },
        ),
        kOpenHandGap10,
        _buildStyleRow(
          label: l10n.settingsAnimationExit,
          value: current.exitStyle,
          textTheme: textTheme,
          l10n: l10n,
          onStyleChanged: (value) {
            onChanged(current.copyWith(exitStyle: value));
          },
        ),
        kOpenHandGap10,
        Row(
          children: [
            SizedBox(
              width: 80,
              child: Text(
                l10n.settingsAnimationDuration,
                style: textTheme.labelLarge,
              ),
            ),
            kOpenHandHGap8,
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: OpenHandDeferredSlider(
                      value: current.configuredDurationMs.toDouble(),
                      min: DialogAnimationSettings.minAnimatedDurationMs
                          .toDouble(),
                      max: DialogAnimationSettings.maxDurationMs.toDouble(),
                      divisions:
                          (DialogAnimationSettings.maxDurationMs -
                              DialogAnimationSettings.minAnimatedDurationMs) ~/
                          40,
                      labelBuilder: (value) => '${value.round()}ms',
                      onCommit: (value) {
                        onChanged(current.copyWith(durationMs: value.round()));
                      },
                    ),
                  ),
                  SizedBox(
                    width: 54,
                    child: Text(
                      '${current.configuredDurationMs}ms',
                      style: textTheme.labelMedium,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        kOpenHandGap10,
        Row(
          children: [
            SizedBox(
              width: 80,
              child: Text(
                l10n.settingsAnimationCurve,
                style: textTheme.labelLarge,
              ),
            ),
            kOpenHandHGap8,
            Expanded(
              child: AnimatedDropdownButtonFormField<DialogAnimationCurve>(
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

  Widget _buildStyleRow({
    required String label,
    required DialogAnimationStyle value,
    required TextTheme textTheme,
    required AppLocalizations l10n,
    required ValueChanged<DialogAnimationStyle> onStyleChanged,
  }) {
    return Row(
      children: [
        SizedBox(width: 80, child: Text(label, style: textTheme.labelLarge)),
        kOpenHandHGap8,
        Expanded(
          child: AnimatedDropdownButtonFormField<DialogAnimationStyle>(
            initialValue: value,
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
            onChanged: (next) {
              if (next != null) onStyleChanged(next);
            },
          ),
        ),
      ],
    );
  }
}
