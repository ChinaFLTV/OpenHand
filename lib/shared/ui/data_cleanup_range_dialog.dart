import 'package:flutter/material.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';

import '../util/date_time_format.dart';
import '../util/localized_text.dart';
import 'animated_dialog.dart';
import 'motion_durations.dart';
import 'motion_preference.dart';
import 'oh_pill.dart';
import 'openhand_dialog_action_button.dart';

enum OpenHandCleanupRangePreset { all, today, last24Hours, last7Days, custom }

class OpenHandCleanupDateRange {
  const OpenHandCleanupDateRange({
    required this.preset,
    required this.startUtc,
    required this.endUtc,
  });

  final OpenHandCleanupRangePreset preset;
  final DateTime? startUtc;
  final DateTime? endUtc;

  bool get clearsAll => startUtc == null && endUtc == null;
}

Future<OpenHandCleanupDateRange?> showOpenHandDataCleanupRangeDialog({
  required BuildContext context,
  required String title,
  required String description,
  String? confirmLabel,
}) {
  return showAnimatedDialog<OpenHandCleanupDateRange>(
    context: context,
    builder: (_) => _OpenHandCleanupRangeDialog(
      title: title,
      description: description,
      confirmLabel: confirmLabel,
    ),
  );
}

class _OpenHandCleanupRangeDialog extends StatefulWidget {
  const _OpenHandCleanupRangeDialog({
    required this.title,
    required this.description,
    this.confirmLabel,
  });

  final String title;
  final String description;
  final String? confirmLabel;

  @override
  State<_OpenHandCleanupRangeDialog> createState() =>
      _OpenHandCleanupRangeDialogState();
}

class _OpenHandCleanupRangeDialogState
    extends State<_OpenHandCleanupRangeDialog> {
  OpenHandCleanupRangePreset _preset = OpenHandCleanupRangePreset.all;
  late final TextEditingController _startController;
  late final TextEditingController _endController;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startController = TextEditingController(
      text: _formatInput(now.subtract(const Duration(days: 1))),
    );
    _endController = TextEditingController(text: _formatInput(now));
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return buildOpenHandResponsiveDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthCompact,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cs.errorContainer.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(kOpenHandRadius12),
                    border: Border.all(color: cs.error.withValues(alpha: 0.24)),
                  ),
                  child: Icon(
                    Icons.cleaning_services_outlined,
                    color: cs.error,
                  ),
                ),
                kOpenHandHGap12,
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            kOpenHandGap12,
            Text(
              widget.description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            kOpenHandGap16,
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in OpenHandCleanupRangePreset.values)
                  _OpenHandCleanupRangePresetPill(
                    key: ValueKey<OpenHandCleanupRangePreset>(preset),
                    selected: _preset == preset,
                    icon: _presetIcon(preset),
                    label: Text(_presetLabel(context, preset)),
                    onPressed: () => setState(() {
                      _preset = preset;
                      _errorText = null;
                    }),
                  ),
              ],
            ),
            AnimatedSwitcher(
              duration: openHandMotionDuration(context, kOpenHandMotion180),
              child: _preset == OpenHandCleanupRangePreset.custom
                  ? Padding(
                      key: const ValueKey<String>('custom-range-fields'),
                      padding: const EdgeInsets.only(top: 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _startController,
                              decoration: InputDecoration(
                                labelText: openHandLocalizedText(
                                  context,
                                  zh: '开始时间',
                                  en: 'Start time',
                                ),
                                prefixIcon: const Icon(Icons.event_outlined),
                                hintText: '2026-07-08 09:30',
                              ),
                            ),
                          ),
                          kOpenHandHGap10,
                          Expanded(
                            child: TextField(
                              controller: _endController,
                              decoration: InputDecoration(
                                labelText: openHandLocalizedText(
                                  context,
                                  zh: '结束时间',
                                  en: 'End time',
                                ),
                                prefixIcon: const Icon(Icons.event_available),
                                hintText: '2026-07-08 18:00',
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey<String>('no-custom')),
            ),
            OpenHandDialogErrorText(
              message: _errorText,
              topGap: 10,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.error,
                fontWeight: FontWeight.w700,
              ),
            ),
            kOpenHandGap18,
            buildOpenHandDialogActionsBar(
              padding: EdgeInsets.zero,
              actions: [
                OpenHandDialogActionButton.secondary(
                  label: MaterialLocalizations.of(context).cancelButtonLabel,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                OpenHandDialogActionButton.destructive(
                  label:
                      widget.confirmLabel ??
                      openHandLocalizedText(context, zh: '确认清理', en: 'Clean'),
                  icon: Icons.delete_sweep_outlined,
                  onPressed: _submit,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    final range = _buildRange();
    if (range == null) return;
    Navigator.of(context).pop(range);
  }

  OpenHandCleanupDateRange? _buildRange() {
    final now = DateTime.now();
    switch (_preset) {
      case OpenHandCleanupRangePreset.all:
        return const OpenHandCleanupDateRange(
          preset: OpenHandCleanupRangePreset.all,
          startUtc: null,
          endUtc: null,
        );
      case OpenHandCleanupRangePreset.today:
        final start = DateTime(now.year, now.month, now.day);
        return OpenHandCleanupDateRange(
          preset: _preset,
          startUtc: start.toUtc(),
          endUtc: now.toUtc(),
        );
      case OpenHandCleanupRangePreset.last24Hours:
        return OpenHandCleanupDateRange(
          preset: _preset,
          startUtc: now.subtract(const Duration(hours: 24)).toUtc(),
          endUtc: now.toUtc(),
        );
      case OpenHandCleanupRangePreset.last7Days:
        return OpenHandCleanupDateRange(
          preset: _preset,
          startUtc: now.subtract(const Duration(days: 7)).toUtc(),
          endUtc: now.toUtc(),
        );
      case OpenHandCleanupRangePreset.custom:
        final start = _parseInput(_startController.text, endOfDay: false);
        final end = _parseInput(_endController.text, endOfDay: true);
        if (start == null || end == null || end.isBefore(start)) {
          setState(() {
            _errorText = openHandLocalizedText(
              context,
              zh: '请输入有效的本地时间范围，例如 2026-07-08 09:30。',
              en: 'Enter a valid local time range, for example 2026-07-08 09:30.',
            );
          });
          return null;
        }
        return OpenHandCleanupDateRange(
          preset: _preset,
          startUtc: start.toUtc(),
          endUtc: end.toUtc(),
        );
    }
  }
}

class _OpenHandCleanupRangePresetPill extends StatelessWidget {
  const _OpenHandCleanupRangePresetPill({
    super.key,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final bool selected;
  final IconData icon;
  final Widget label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final foreground = selected ? cs.onPrimaryContainer : cs.onSurfaceVariant;
    final background = selected
        ? cs.primaryContainer.withValues(alpha: 0.78)
        : cs.surfaceContainerHighest.withValues(alpha: 0.52);
    final borderColor = selected
        ? cs.primary.withValues(alpha: 0.42)
        : cs.outlineVariant.withValues(alpha: 0.78);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: kOpenHandPillBorderRadius,
        hoverColor: cs.primary.withValues(alpha: 0.08),
        splashColor: cs.primary.withValues(alpha: 0.10),
        highlightColor: cs.primary.withValues(alpha: 0.05),
        onTap: onPressed,
        child: AnimatedContainer(
          duration: openHandMotionDuration(context, kOpenHandMotion180),
          curve: kOpenHandSwitchInCurve,
          constraints: const BoxConstraints(minHeight: 42),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: background,
            borderRadius: kOpenHandPillBorderRadius,
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: foreground),
              kOpenHandHGap8,
              DefaultTextStyle.merge(
                style: theme.textTheme.labelLarge?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w900,
                ),
                child: label,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _presetIcon(OpenHandCleanupRangePreset preset) {
  return switch (preset) {
    OpenHandCleanupRangePreset.all => Icons.all_inclusive_rounded,
    OpenHandCleanupRangePreset.today => Icons.today_outlined,
    OpenHandCleanupRangePreset.last24Hours => Icons.schedule_rounded,
    OpenHandCleanupRangePreset.last7Days => Icons.date_range_rounded,
    OpenHandCleanupRangePreset.custom => Icons.tune_rounded,
  };
}

String _presetLabel(BuildContext context, OpenHandCleanupRangePreset preset) {
  return switch (preset) {
    OpenHandCleanupRangePreset.all => openHandAllLabel(context),
    OpenHandCleanupRangePreset.today => openHandTodayLabel(context),
    OpenHandCleanupRangePreset.last24Hours => openHandLocalizedText(
      context,
      zh: '近 24 小时',
      en: 'Last 24h',
    ),
    OpenHandCleanupRangePreset.last7Days => openHandLocalizedText(
      context,
      zh: '近 7 天',
      en: 'Last 7d',
    ),
    OpenHandCleanupRangePreset.custom => openHandCustomLabel(context),
  };
}

String _formatInput(DateTime value) {
  return formatYearMonthDayHm(value);
}

DateTime? _parseInput(String value, {required bool endOfDay}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final dateOnly = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  if (dateOnly.hasMatch(trimmed)) {
    final parsed = DateTime.tryParse(trimmed);
    if (parsed == null) return null;
    return endOfDay
        ? DateTime(parsed.year, parsed.month, parsed.day, 23, 59, 59, 999)
        : DateTime(parsed.year, parsed.month, parsed.day);
  }
  return DateTime.tryParse(trimmed.replaceFirst(' ', 'T'));
}
