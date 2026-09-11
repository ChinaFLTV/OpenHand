import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';

import '../../../app/model/cron_config.dart';
import '../../../app/support/silent_log.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/ansi_text.dart';
import '../../../shared/ui/appear_once.dart';
import '../../../shared/ui/feature_state_card.dart';
import '../../../shared/ui/list_removal_transition.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_form_fields.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_typography.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/localized_text.dart';
import '../../../shared/util/text_clip.dart';
import '../../ai/index.dart';
import '../crons_controller.dart';
import 'cron_editor_dialog.dart';

const int _cronTagPreviewLimit = 6;

const Color _kCronRunningColor = Color(0xFF56C271);

class CronsView extends StatelessWidget {
  const CronsView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final snapshot = context
        .select<
          CronsController,
          ({bool isLoading, String? errorMessage, List<CronEntry> entries})
        >(
          (controller) => (
            isLoading: controller.isLoading,
            errorMessage: controller.errorMessage,
            entries: controller.entries,
          ),
        );
    final entries = snapshot.entries;
    final userEntryCount = entries
        .where((entry) => entry.scriptType != CronScriptType.managed)
        .length;
    final controller = context.read<CronsController>();
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.settingsCrons, style: theme.textTheme.displaySmall),
                  kOpenHandGap8,
                  Text(
                    l10n.cronsViewDescription,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            kOpenHandHGap16,
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (snapshot.errorMessage != null)
                  FilledButton.tonalIcon(
                    onPressed: snapshot.isLoading ? null : controller.refresh,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(l10n.commonRetry),
                  ),
                FilledButton.icon(
                  onPressed:
                      snapshot.isLoading ||
                          snapshot.errorMessage != null ||
                          userEntryCount >= kCronMaxUserEntryCount
                      ? null
                      : () => _showCronEditorDialog(context, null),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(l10n.cronsNewCronJob),
                ),
              ],
            ),
          ],
        ),
        if (snapshot.errorMessage != null && entries.isNotEmpty) ...[
          kOpenHandGap16,
          FeatureStateCard.inline(
            icon: Icons.error_outline_rounded,
            tone: FeatureStateTone.error,
            title: l10n.settingsPersistenceLoadFailedTitle,
            body: snapshot.errorMessage!,
          ),
        ],
        kOpenHandGap24,
        // 三种状态平滑切换，避免列表增删时跳变。
        Expanded(
          child: AnimatedSwitcher(
            duration: openHandMotionDuration(context, kOpenHandMotion220),
            switchInCurve: kOpenHandSwitchInCurve,
            switchOutCurve: kOpenHandSwitchOutCurve,
            child: (snapshot.isLoading && entries.isEmpty)
                ? const Center(
                    key: ValueKey<String>('loading'),
                    child: CircularProgressIndicator(),
                  )
                : snapshot.errorMessage != null && entries.isEmpty
                ? FeatureStateCard.centered(
                    key: const ValueKey<String>('error'),
                    icon: Icons.error_outline_rounded,
                    tone: FeatureStateTone.error,
                    title: l10n.settingsPersistenceLoadFailedTitle,
                    body: snapshot.errorMessage!,
                  )
                : entries.isEmpty
                ? const KeyedSubtree(
                    key: ValueKey<String>('empty'),
                    child: _CronEmptyState(),
                  )
                : ScrollConfiguration(
                    key: const ValueKey<String>('list'),
                    behavior: ScrollConfiguration.of(
                      context,
                    ).copyWith(scrollbars: false),
                    child: OpenHandRemovableListScope(
                      builder: (context, removal) => ListView.separated(
                        // 顶部 2px 缓冲，避免滚动到顶时第一张卡的描边被剪掉。
                        padding: const EdgeInsets.only(top: 2),
                        itemCount: entries.length,
                        separatorBuilder: (context, index) => kOpenHandGap14,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          return SettingsAwareAppearOnce(
                            key: ValueKey<String>('cron-entry-${entry.id}'),
                            child: RepaintBoundary(
                              child: OpenHandListRemovalTransition(
                                collapsed: removal.isRemoving(entry.id),
                                child: _CronEntryCard(
                                  entry: entry,
                                  onEdit: () =>
                                      _showCronEditorDialog(context, entry),
                                  onToggle: (enabled) {
                                    controller.toggleCronEnabled(
                                      entry.id,
                                      enabled: enabled,
                                    );
                                  },
                                  onDelete: () =>
                                      _confirmDelete(context, removal, entry),
                                  onHistory: () =>
                                      _showHistoryDialog(context, entry),
                                  onRunNow: () => controller.runNow(entry.id),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  void _showCronEditorDialog(BuildContext context, CronEntry? existing) {
    showCronEditorDialog(context, existing: existing);
  }

  void _showHistoryDialog(BuildContext context, CronEntry entry) {
    final controller = context.read<CronsController>();
    controller.loadHistory(entry.id);
    showAnimatedDialog(
      context: context,
      builder: (_) => _CronHistoryDialog(entry: entry),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    OpenHandListRemoval removal,
    CronEntry entry,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: l10n.cronsDeleteCronJobTitle,
      message: l10n.cronsDeleteCronJobMessage(entry.name),
      cancelLabel: l10n.commonCancel,
      confirmLabel: l10n.commonDelete,
      destructive: true,
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    final cronsController = context.read<CronsController>();
    await removal.run(entry.id, () => cronsController.deleteCron(entry.id));
  }
}

class _CronEmptyState extends StatelessWidget {
  const _CronEmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // 与 Hooks / 记忆等页面统一走页面级空态卡；不能是 Expanded：本 widget
    // 挂在 AnimatedSwitcher 下，其默认 layoutBuilder 会把 child 放进 Stack 并包
    // 一层 FadeTransition，Expanded.applyParentData 会把 RenderAnimatedOpacity
    // 的 parentData 强转成 FlexParentData 而断言失败。
    return FeatureStateCard.centered(
      icon: Icons.schedule_outlined,
      tone: FeatureStateTone.neutral,
      title: l10n.cronsEmptyTitle,
      body: l10n.cronsEmptyBody,
    );
  }
}

enum _CronCardAction { edit, delete }

class _CronEntryCard extends StatelessWidget {
  const _CronEntryCard({
    required this.entry,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
    required this.onHistory,
    required this.onRunNow,
  });

  final CronEntry entry;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;
  final VoidCallback onHistory;
  final VoidCallback onRunNow;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final isSystem = entry.tags.contains('system');
    final toggleLocked = entry.tags.contains(
      CronsController.mcpKeywordIndexTag,
    );
    final visibleTags = entry.tags
        .take(_cronTagPreviewLimit)
        .toList(growable: false);
    final hiddenTagCount = entry.tags.length - visibleTags.length;
    final statusColor = _cronStatusAccent(entry, colorScheme);
    final description = entry.description.trim();
    final lastRunLabel = entry.lastRunAt == null
        ? '—'
        : formatMonthDayHms(entry.lastRunAt!);

    final toggle = Switch(
      value: entry.enabled,
      onChanged: toggleLocked ? null : onToggle,
    );

    return OpenHandFeatureListCard(
      onTap: isSystem ? onHistory : onEdit,
      identity: OpenHandListIdentity(
        title: entry.name,
        description: description.isEmpty ? null : description,
        descriptionMaxLines: 2,
      ),
      actions: [
        if (toggleLocked)
          Tooltip(
            message: l10n.cronsMcpKeywordIndexLockedTooltip,
            child: toggle,
          )
        else
          toggle,
        OpenHandFeatureIconButton(
          icon: Icons.bolt_rounded,
          tooltip: l10n.cronsRunOnceNow,
          onPressed: onRunNow,
          enabled: entry.enabled,
        ),
        OpenHandFeatureIconButton(
          icon: Icons.history_rounded,
          tooltip: l10n.cronsHistory,
          onPressed: onHistory,
        ),
        AnimatedPopupMenuButton<_CronCardAction>(
          tooltip: openHandMoreActionsLabel(context),
          style: openHandFeatureCircleIconButtonStyle(colorScheme),
          onSelected: (action) {
            switch (action) {
              case _CronCardAction.edit:
                onEdit();
              case _CronCardAction.delete:
                onDelete();
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem<_CronCardAction>(
              enabled: !isSystem,
              value: _CronCardAction.edit,
              child: Text(l10n.commonEdit),
            ),
            PopupMenuItem<_CronCardAction>(
              enabled: !isSystem,
              value: _CronCardAction.delete,
              child: Text(
                l10n.commonDelete,
                style: TextStyle(
                  color: isSystem ? null : colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
      statusPills: [
        OpenHandStatusPill(
          icon: _cronStatusIcon(entry),
          label: entry.status.label(l10n),
          color: statusColor,
        ),
        OpenHandStatusPill(
          icon: entry.scriptType == CronScriptType.script
              ? Icons.description_outlined
              : entry.scriptType == CronScriptType.managed
              ? Icons.verified_outlined
              : Icons.terminal_rounded,
          label: entry.scriptType.label(l10n),
          color: colorScheme.secondary,
        ),
        if (entry.lastRunAt != null)
          OpenHandStatusPill(
            icon: Icons.schedule_rounded,
            label: lastRunLabel,
            color: OpenHandStatusColors.warning,
          ),
      ],
      factChips: [
        OpenHandFactChip(
          icon: Icons.event_repeat_outlined,
          label: entry.cronExpression,
          color: colorScheme.tertiary,
        ),
        OpenHandFactChip(
          icon: Icons.timer_outlined,
          label: '${entry.timeoutSeconds}s',
          color: colorScheme.primary,
        ),
        if (entry.retryCount > 0)
          OpenHandFactChip(
            icon: Icons.replay_rounded,
            label: '${entry.retryCount}',
            color: OpenHandStatusColors.info,
          ),
        for (final tag in visibleTags)
          OpenHandFactChip(
            icon: Icons.sell_outlined,
            label: tag,
            color: colorScheme.secondary,
          ),
        if (hiddenTagCount > 0)
          OpenHandFactChip(
            icon: Icons.more_horiz_rounded,
            label: '+$hiddenTagCount',
            color: colorScheme.onSurfaceVariant,
          ),
      ],
      metrics: [
        (
          label: l10n.listCardMetricStatus,
          value: entry.status.label(l10n),
          accent: statusColor,
        ),
        (
          label: l10n.cronsExpressionPreview,
          value: entry.cronExpression,
          accent: colorScheme.tertiary,
        ),
        (
          label: l10n.cronsTimeoutTooltip,
          value: '${entry.timeoutSeconds}s',
          accent: colorScheme.primary,
        ),
        (
          label: l10n.cronsRetries,
          value: '${entry.retryCount}',
          accent: OpenHandStatusColors.info,
        ),
      ],
    );
  }
}

Color _cronStatusAccent(CronEntry entry, ColorScheme colorScheme) {
  if (!entry.enabled) return colorScheme.outline;
  return switch (entry.status) {
    CronJobStatus.running => _kCronRunningColor,
    CronJobStatus.idle => OpenHandStatusColors.success,
    CronJobStatus.paused => colorScheme.tertiary,
    CronJobStatus.failed || CronJobStatus.error => colorScheme.error,
  };
}

IconData _cronStatusIcon(CronEntry entry) {
  if (!entry.enabled) return Icons.pause_circle_outline_rounded;
  return switch (entry.status) {
    CronJobStatus.running => Icons.play_circle_outline_rounded,
    CronJobStatus.idle => Icons.check_circle_outline_rounded,
    CronJobStatus.paused => Icons.pause_circle_outline_rounded,
    CronJobStatus.failed || CronJobStatus.error => Icons.error_outline_rounded,
  };
}

class _CronHistoryDialog extends StatelessWidget {
  const _CronHistoryDialog({required this.entry});

  final CronEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final history = context.select<CronsController, List<CronExecutionRecord>>(
      (controller) => controller.historyFor(entry.id),
    );
    final controller = context.read<CronsController>();

    return buildOpenHandResponsiveDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthStandard,
      maxHeight: kOpenHandDialogHeightStandard,
      safeAreaMinimum: kOpenHandDialogDefaultInsetPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.history_rounded,
            iconColor: colorScheme.tertiary,
            title: l10n.cronsExecutionHistoryTitle,
            subtitle: entry.name,
            actions: [
              if (history.isNotEmpty)
                IconButton(
                  tooltip: l10n.cronsClearAllExecutionHistory,
                  style: openHandFeatureCircleIconButtonStyle(colorScheme),
                  onPressed: () => _confirmClearAll(context, controller, l10n),
                  icon: Icon(
                    Icons.delete_sweep_outlined,
                    color: colorScheme.error,
                  ),
                ),
            ],
          ),
          Expanded(
            child: OpenHandRemovableListScope(
              builder: (context, removal) => history.isEmpty
                  ? FeatureStateCard.centered(
                      icon: Icons.inbox_outlined,
                      tone: FeatureStateTone.neutral,
                      title: l10n.cronsNoExecutionRecords,
                      body: entry.description.isNotEmpty
                          ? entry.description
                          : entry.cronExpression,
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      itemCount: history.length,
                      itemBuilder: (context, index) {
                        final record = history[index];
                        return OpenHandListRemovalTransition(
                          key: ValueKey<String>('cron-history-${record.id}'),
                          collapsed: removal.isRemoving(record.id),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Dismissible(
                              key: ValueKey(record.id),
                              direction: DismissDirection.endToStart,
                              confirmDismiss: (_) async {
                                await _confirmDeleteRecord(
                                  context,
                                  controller,
                                  removal,
                                  record,
                                  l10n,
                                );
                                return false;
                              },
                              background: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: colorScheme.errorContainer,
                                  borderRadius: kOpenHandBorderRadius16,
                                ),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 20),
                                    child: Icon(
                                      Icons.delete_outline_rounded,
                                      color: colorScheme.onErrorContainer,
                                    ),
                                  ),
                                ),
                              ),
                              child: _HistoryRecordTile(
                                record: record,
                                onDelete: () => _confirmDeleteRecord(
                                  context,
                                  controller,
                                  removal,
                                  record,
                                  l10n,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.94),
              border: Border(
                top: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.55),
                ),
              ),
            ),
            child: buildOpenHandDialogActionsBar(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              actions: [
                OpenHandDialogActionButton.secondary(
                  label: l10n.commonClose,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearAll(
    BuildContext context,
    CronsController controller,
    AppLocalizations l10n,
  ) async {
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: l10n.cronsClearExecutionHistoryTitle,
      message: l10n.cronsClearExecutionHistoryMessage(entry.name),
      cancelLabel: l10n.commonCancel,
      confirmLabel: l10n.cronsClear,
      destructive: true,
    );
    if (!confirmed) {
      return;
    }
    await controller.clearHistoryForCron(entry.id);
  }

  Future<void> _confirmDeleteRecord(
    BuildContext context,
    CronsController controller,
    OpenHandListRemoval removal,
    CronExecutionRecord record,
    AppLocalizations l10n,
  ) async {
    if (removal.isRemoving(record.id)) return;
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: l10n.cronsDeleteExecutionRecordTitle,
      message: l10n.cronsDeleteExecutionRecordMessage,
      cancelLabel: l10n.commonCancel,
      confirmLabel: l10n.commonDelete,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    await removal.run(record.id, () async {
      await controller.deleteHistoryRecord(entry.id, record.id);
    });
  }
}

class _HistoryRecordTile extends StatefulWidget {
  const _HistoryRecordTile({required this.record, required this.onDelete});

  final CronExecutionRecord record;
  final VoidCallback onDelete;

  @override
  State<_HistoryRecordTile> createState() => _HistoryRecordTileState();
}

class _HistoryRecordTileState extends State<_HistoryRecordTile>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _animController;
  late final CurvedAnimation _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: Duration.zero,
      reverseDuration: Duration.zero,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: kOpenHandSwitchInCurve,
      reverseCurve: kOpenHandSwitchOutCurve,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
    final durationChanged =
        _animController.duration != settings.entranceDuration ||
        _animController.reverseDuration != settings.exitDuration;
    _animController
      ..duration = settings.entranceDuration
      ..reverseDuration = settings.exitDuration;
    _fadeAnimation
      ..curve = settings.curve.curve
      ..reverseCurve = settings.curve.reverseCurve;
    if (durationChanged && _animController.isAnimating) {
      _expanded ? _animController.forward() : _animController.reverse();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _animController.forward();
      } else {
        _animController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final record = widget.record;
    final l10n = AppLocalizations.of(context)!;

    final statusColor = switch (record.status) {
      'success' => _kCronRunningColor,
      'failed' => colorScheme.error,
      'timed_out' => colorScheme.tertiary,
      'running' => colorScheme.primary,
      'killed' => colorScheme.error,
      _ => colorScheme.onSurfaceVariant,
    };

    final statusLabel = switch (record.status) {
      'success' => l10n.cronsExecutionStatusSuccess,
      'failed' => l10n.cronsExecutionStatusFailed,
      'timed_out' => l10n.cronsExecutionStatusTimedOut,
      'running' => l10n.cronsExecutionStatusRunning,
      'killed' => l10n.cronsExecutionStatusKilled,
      _ => record.status,
    };

    final tileBackground = _expanded
        ? Color.alphaBlend(
            statusColor.withValues(alpha: 0.08),
            colorScheme.surfaceContainerLow,
          )
        : colorScheme.surface.withValues(alpha: 0.48);
    final tileBorderColor = _expanded
        ? statusColor.withValues(alpha: 0.24)
        : colorScheme.outlineVariant.withValues(alpha: 0.22);

    return AnimatedContainer(
      duration: _expanded
          ? (_animController.duration ?? Duration.zero)
          : (_animController.reverseDuration ?? Duration.zero),
      curve: _expanded
          ? _fadeAnimation.curve
          : (_fadeAnimation.reverseCurve ?? _fadeAnimation.curve),
      decoration: BoxDecoration(
        color: tileBackground,
        borderRadius: BorderRadius.circular(kOpenHandRadius16),
        border: Border.all(color: tileBorderColor),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _toggle,
          borderRadius: BorderRadius.circular(kOpenHandRadius16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: kOpenHandBorderRadius12,
                      child: ColoredBox(
                        color: statusColor.withValues(alpha: 0.16),
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: Icon(
                            switch (record.status) {
                              'success' => Icons.check_rounded,
                              'failed' || 'killed' => Icons.close_rounded,
                              'timed_out' => Icons.timer_off_outlined,
                              'running' => Icons.play_arrow_rounded,
                              _ => Icons.circle_outlined,
                            },
                            size: 20,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ),
                    kOpenHandHGap12,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              OpenHandFactChip(
                                icon: switch (record.status) {
                                  'success' =>
                                    Icons.check_circle_outline_rounded,
                                  'failed' ||
                                  'killed' => Icons.error_outline_rounded,
                                  'timed_out' => Icons.timer_outlined,
                                  'running' =>
                                    Icons.play_circle_outline_rounded,
                                  _ => Icons.info_outline_rounded,
                                },
                                label: statusLabel,
                                color: statusColor,
                              ),
                              OpenHandFactChip(
                                icon: record.triggerType == 'manual'
                                    ? Icons.touch_app_outlined
                                    : Icons.schedule_rounded,
                                label: record.triggerType == 'manual'
                                    ? l10n.cronsTriggerManual
                                    : l10n.cronsTriggerScheduled,
                                color: record.triggerType == 'manual'
                                    ? colorScheme.tertiary
                                    : colorScheme.secondary,
                              ),
                              OpenHandFactChip(
                                icon: Icons.speed_rounded,
                                label: '${record.elapsedMs}ms',
                                color: OpenHandStatusColors.info,
                              ),
                            ],
                          ),
                          kOpenHandGap6,
                          Text(
                            formatYearMonthDayHms(record.startedAt),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    kOpenHandHGap8,
                    IconButton(
                      tooltip: l10n.cronsDeleteThisRecord,
                      style: openHandFeatureCircleIconButtonStyle(colorScheme),
                      onPressed: widget.onDelete,
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        color: colorScheme.error,
                      ),
                    ),
                    kOpenHandHGap8,
                    IconButton(
                      tooltip: _expanded
                          ? l10n.cronsCollapse
                          : l10n.cronsExpand,
                      style: openHandFeatureCircleIconButtonStyle(colorScheme),
                      onPressed: _toggle,
                      icon: AnimatedRotation(
                        turns: _expanded ? 0.5 : 0.0,
                        duration: _expanded
                            ? (_animController.duration ?? Duration.zero)
                            : (_animController.reverseDuration ??
                                  Duration.zero),
                        curve: _expanded
                            ? _fadeAnimation.curve
                            : (_fadeAnimation.reverseCurve ??
                                  _fadeAnimation.curve),
                        child: const Icon(Icons.expand_more_rounded),
                      ),
                    ),
                  ],
                ),
                SizeTransition(
                  sizeFactor: _fadeAnimation,
                  alignment: AlignmentDirectional.topStart,
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: _detailSection(
                        theme,
                        colorScheme,
                        l10n: l10n,
                        record: record,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailSection(
    ThemeData theme,
    ColorScheme colorScheme, {
    required AppLocalizations l10n,
    required CronExecutionRecord record,
  }) {
    final metaChips = <Widget>[
      if (record.retryAttempt > 0)
        OpenHandFactChip(
          icon: Icons.replay_rounded,
          label: '${l10n.cronsRetryAttempt} ${record.retryAttempt}',
          color: colorScheme.tertiary,
        ),
      if (record.pid != null)
        OpenHandFactChip(
          icon: Icons.memory_rounded,
          label: 'PID ${record.pid}',
          color: colorScheme.secondary,
        ),
      if (record.runAsUser != null)
        OpenHandFactChip(
          icon: Icons.person_outline_rounded,
          label: '${l10n.cronsRunAs} ${record.runAsUser}',
          color: colorScheme.primary,
        ),
      if (record.workingDirectory != null)
        OpenHandFactChip(
          icon: Icons.folder_outlined,
          label: record.workingDirectory!,
          color: OpenHandStatusColors.info,
        ),
    ];
    final hasHermes =
        record.appContext.containsKey(CronsController.hermesTalkerReportsKey) ||
        record.appContext.containsKey(CronsController.hermesTalkerStatsKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (metaChips.isNotEmpty)
          Wrap(spacing: 8, runSpacing: 8, children: metaChips),
        if (record.environment.isNotEmpty) ...[
          if (metaChips.isNotEmpty) kOpenHandGap10,
          OpenHandTintedPanel(
            accent: colorScheme.secondary,
            icon: Icons.tune_rounded,
            title: l10n.cronsScriptEnvironmentOverrides,
            child: SelectableText(
              record.environment.entries
                  .map((e) => '${e.key}=${e.value}')
                  .join('\n'),
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: kOpenHandMonospaceFontFamily,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
        ],
        if (record.appContext.isNotEmpty) ...[
          if (hasHermes) ...[
            kOpenHandGap10,
            _HermesTalkerHistoryPanel(appContext: record.appContext),
          ],
          ..._buildPlainAppContextSection(
            theme: theme,
            colorScheme: colorScheme,
            l10n: l10n,
            record: record,
          ),
        ],
        if (record.environmentSnapshot.isNotEmpty) ...[
          kOpenHandGap10,
          _kvSection(
            title: l10n.cronsEnvironmentSnapshot,
            data: record.environmentSnapshot,
            theme: theme,
            colorScheme: colorScheme,
            accent: colorScheme.secondary,
          ),
        ],
        if (record.errorMessage != null && record.errorMessage!.isNotEmpty) ...[
          kOpenHandGap10,
          OpenHandTintedPanel(
            accent: colorScheme.error,
            icon: Icons.error_outline_rounded,
            title: l10n.cronsErrorReason,
            child: SelectableText(
              record.errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.error,
                fontFamily: kOpenHandMonospaceFontFamily,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
        ],
        if (record.stdout.isNotEmpty) ...[
          kOpenHandGap10,
          _scrollableLogPanel(
            theme: theme,
            colorScheme: colorScheme,
            accent: colorScheme.primary,
            icon: Icons.terminal_rounded,
            title: l10n.cronsStdout,
            text: record.stdout,
            textColor: colorScheme.onSurface,
          ),
        ],
        if (record.stderr.isNotEmpty) ...[
          kOpenHandGap10,
          _scrollableLogPanel(
            theme: theme,
            colorScheme: colorScheme,
            accent: colorScheme.error,
            icon: Icons.bug_report_outlined,
            title: l10n.cronsStderr,
            text: record.stderr,
            textColor: colorScheme.onErrorContainer,
          ),
        ],
      ],
    );
  }

  Widget _scrollableLogPanel({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required Color accent,
    required IconData icon,
    required String title,
    required String text,
    required Color textColor,
  }) {
    return OpenHandTintedPanel(
      accent: accent,
      icon: icon,
      title: title,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 200),
        child: SingleChildScrollView(
          child: ansiText(
            text,
            colorScheme: colorScheme,
            base: theme.textTheme.bodySmall?.copyWith(
              fontFamily: kOpenHandMonospaceFontFamily,
              fontSize: 11,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }

  /// 渲染 `appContext` 中除 Hermes Talker 富面板已消费键以外的纯文本
  /// 键值对。当过滤后无剩余项时返回空列表，避免出现空标题块。
  List<Widget> _buildPlainAppContextSection({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required AppLocalizations l10n,
    required CronExecutionRecord record,
  }) {
    final filtered = <String, String>{
      for (final entry in record.appContext.entries)
        if (entry.key != CronsController.hermesTalkerReportsKey &&
            entry.key != CronsController.hermesTalkerStatsKey)
          entry.key: entry.value,
    };
    if (filtered.isEmpty) return const <Widget>[];
    return <Widget>[
      kOpenHandGap10,
      _kvSection(
        title: l10n.cronsExecutionContext,
        data: filtered,
        theme: theme,
        colorScheme: colorScheme,
        accent: colorScheme.tertiary,
      ),
    ];
  }

  Widget _kvSection({
    required String title,
    required Map<String, String> data,
    required ThemeData theme,
    required ColorScheme colorScheme,
    required Color accent,
  }) {
    final sortedKeys = data.keys.toList()..sort();
    return OpenHandTintedPanel(
      accent: accent,
      title: title,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 160),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final key in sortedKeys)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: SelectableText(
                    '$key=${data[key] ?? ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: kOpenHandMonospaceFontFamily,
                      fontSize: 11,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// Hermes Talker 历史富展示面板
/// Hermes Talker 历史卡片读取 [SelfLearningSessionReport.mutations] 的取值口径。
/// 报告结构由 runner 定义，这里只补 UI 需要的派生字段，避免再抄一份模型
/// 导致两处字段口径悄悄漂移。
extension _HermesTalkerSessionReportView on SelfLearningSessionReport {
  int get memoryUpdates =>
      intFromValue(mutations['memory_updates'], fallback: 0);
  int get memoryErrors => intFromValue(mutations['memory_errors'], fallback: 0);
  int get skillUpdates => intFromValue(mutations['skill_updates'], fallback: 0);
  int get skillErrors => intFromValue(mutations['skill_errors'], fallback: 0);
  int get toolCallRounds =>
      intFromValue(mutations['tool_call_rounds'], fallback: 0);

  List<Map<String, Object?>> get memoryChanges =>
      stringKeyedMapListFromValue(mutations['memory_changes']);
  List<Map<String, Object?>> get profileChanges =>
      stringKeyedMapListFromValue(mutations['profile_changes']);
  List<Map<String, Object?>> get skillChanges =>
      stringKeyedMapListFromValue(mutations['skill_changes']);

  String? get modelId =>
      mutations['model_id'] is String ? mutations['model_id'] as String : null;
  String? get providerId => mutations['provider_id'] is String
      ? mutations['provider_id'] as String
      : null;
  String? get terminatedReason => mutations['terminated_reason'] is String
      ? mutations['terminated_reason'] as String
      : null;
}

class _HermesTalkerHistoryPanel extends StatelessWidget {
  const _HermesTalkerHistoryPanel({required this.appContext});

  final Map<String, String> appContext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    final reports = _decodeReports();
    final stats = _decodeStats();

    if (reports.isEmpty && stats.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(kOpenHandRadius18),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: kOpenHandBorderRadius10,
                ),
                child: Icon(
                  Icons.auto_awesome,
                  size: 18,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              kOpenHandHGap10,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.cronsHermesTalkerReportTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (stats.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          _formatStatsLine(stats, l10n),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (reports.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                l10n.cronsHermesNoEligibleSessions,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else ...[
            kOpenHandGap10,
            Text(
              l10n.cronsHermesAffectedSessions(reports.length),
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            kOpenHandGap6,
            ...reports.map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _HermesTalkerSessionCard(report: r),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<SelfLearningSessionReport> _decodeReports() {
    final raw = appContext[CronsController.hermesTalkerReportsKey];
    if (raw == null || raw.isEmpty) return const <SelfLearningSessionReport>[];
    try {
      final parsed = tryDecodeJson(raw);
      if (parsed is! List) return const <SelfLearningSessionReport>[];
      final out = <SelfLearningSessionReport>[];
      for (final item in parsed) {
        if (item is Map) {
          out.add(
            SelfLearningSessionReport.fromJson(stringKeyedMapFromValue(item)),
          );
        }
      }
      return out;
    } catch (error, stack) {
      silentLog('crons_view', '解码 Hermes Talker 报告', error, stack);
      return const <SelfLearningSessionReport>[];
    }
  }

  Map<String, int> _decodeStats() {
    final raw = appContext[CronsController.hermesTalkerStatsKey];
    if (raw == null || raw.isEmpty) return const <String, int>{};
    try {
      final parsed = tryDecodeJson(raw);
      if (parsed is! Map) return const <String, int>{};
      final out = <String, int>{};
      stringKeyedMapFromValue(parsed).forEach((key, value) {
        out[key] = intFromValue(value, fallback: 0);
      });
      return out;
    } catch (error, stack) {
      silentLog('crons_view', '解码 Hermes Talker 统计', error, stack);
      return const <String, int>{};
    }
  }

  String _formatStatsLine(Map<String, int> stats, AppLocalizations l10n) {
    int v(String k) => stats[k] ?? 0;
    return l10n.cronsHermesStatsLine(
      v('scanned'),
      v('triggered'),
      v('skipped'),
      v('errors'),
    );
  }
}

class _HermesTalkerSessionCard extends StatelessWidget {
  const _HermesTalkerSessionCard({required this.report});

  final SelfLearningSessionReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final isError = report.status == 'error';
    final accent = isError ? colorScheme.error : colorScheme.primary;
    final title = report.sessionTitle.trim().isEmpty
        ? l10n.cronsHermesUntitledSession
        : report.sessionTitle.trim();

    final chips = <Widget>[
      _statusChip(theme, colorScheme, report.status, l10n),
      if (report.memoryUpdates > 0)
        _metaChip(
          theme,
          colorScheme,
          icon: Icons.memory,
          label: l10n.cronsHermesMemoryUpdates(report.memoryUpdates),
        ),
      if (report.memoryErrors > 0)
        _metaChip(
          theme,
          colorScheme,
          icon: Icons.error_outline,
          label: l10n.cronsHermesMemoryErrors(report.memoryErrors),
          tone: colorScheme.error,
        ),
      if (report.skillUpdates > 0)
        _metaChip(
          theme,
          colorScheme,
          icon: Icons.psychology_alt_outlined,
          label: l10n.cronsHermesSkillUpdates(report.skillUpdates),
        ),
      if (report.skillErrors > 0)
        _metaChip(
          theme,
          colorScheme,
          icon: Icons.error_outline,
          label: l10n.cronsHermesSkillErrors(report.skillErrors),
          tone: colorScheme.error,
        ),
      if (report.profileChanges.isNotEmpty)
        _metaChip(
          theme,
          colorScheme,
          icon: Icons.account_circle_outlined,
          label: l10n.cronsHermesProfileChanges(report.profileChanges.length),
        ),
      if (report.toolCallRounds > 0)
        _metaChip(
          theme,
          colorScheme,
          icon: Icons.repeat_rounded,
          label: l10n.cronsHermesToolRounds(report.toolCallRounds),
        ),
    ];

    final children = <Widget>[
      if (report.summary.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: _hermesInlineMarkdown(
            data: report.summary,
            theme: theme,
            colorScheme: colorScheme,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      if (report.modelId != null || report.terminatedReason != null)
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 6),
          child: Text(
            [
              if (report.modelId != null)
                '${l10n.cronsHermesModelLabel}: ${report.modelId}',
              if (report.providerId != null)
                '${l10n.cronsHermesProviderLabel}: ${report.providerId}',
              if (report.terminatedReason != null)
                '${l10n.cronsHermesTerminatedLabel}: ${report.terminatedReason}',
            ].join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ),
      if (report.profileChanges.isNotEmpty)
        _changeGroup(
          theme: theme,
          colorScheme: colorScheme,
          title: l10n.cronsHermesUserProfileChanges,
          icon: Icons.account_circle_outlined,
          changes: report.profileChanges,
          l10n: l10n,
        ),
      if (report.memoryChanges.isNotEmpty)
        _changeGroup(
          theme: theme,
          colorScheme: colorScheme,
          title: l10n.cronsHermesMemoryChanges,
          icon: Icons.memory,
          changes: report.memoryChanges,
          l10n: l10n,
        ),
      if (report.skillChanges.isNotEmpty)
        _changeGroup(
          theme: theme,
          colorScheme: colorScheme,
          title: l10n.cronsHermesSkillChanges,
          icon: Icons.psychology_alt_outlined,
          changes: report.skillChanges,
          l10n: l10n,
        ),
      if (report.aiReasoning != null && report.aiReasoning!.isNotEmpty)
        _CollapsibleLongText(
          title: l10n.cronsHermesAiReasoningOnScene,
          icon: Icons.tips_and_updates_outlined,
          body: report.aiReasoning!,
          subdued: true,
        ),
      if (report.aiResponse != null && report.aiResponse!.isNotEmpty)
        _CollapsibleLongText(
          title: l10n.cronsHermesAiResponseOnScene,
          icon: Icons.chat_bubble_outline,
          body: report.aiResponse!,
        ),
      if (report.error != null && report.error!.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: SelectableText(
            report.error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.error,
              fontFamily: kOpenHandMonospaceFontFamily,
            ),
          ),
        ),
    ];

    final hasExpandableBody = children.isNotEmpty;

    return ClipRRect(
      borderRadius: kOpenHandBorderRadius14,
      child: Theme(
        // ExpansionTile 默认会插入 Divider，关闭它以贴合 Material You 视感。
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: Material(
          color: colorScheme.surfaceContainerLow.withValues(alpha: 0.85),
          shape: RoundedRectangleBorder(
            borderRadius: kOpenHandBorderRadius14,
            side: BorderSide(color: accent.withValues(alpha: 0.22)),
          ),
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 4,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            title: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(spacing: 6, runSpacing: 6, children: chips),
            ),
            children: hasExpandableBody
                ? children
                : <Widget>[
                    Text(
                      l10n.cronsHermesNoFurtherDetails,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
          ),
        ),
      ),
    );
  }

  Widget _statusChip(
    ThemeData theme,
    ColorScheme colorScheme,
    String status,
    AppLocalizations l10n,
  ) {
    Color bg;
    Color fg;
    String label;
    IconData icon;
    switch (status) {
      case 'error':
        bg = colorScheme.errorContainer;
        fg = colorScheme.onErrorContainer;
        icon = Icons.error_outline;
        label = l10n.cronsHermesStatusError;
      case 'skipped':
        bg = colorScheme.surfaceContainerHighest;
        fg = colorScheme.onSurfaceVariant;
        icon = Icons.skip_next_rounded;
        label = l10n.cronsHermesStatusSkipped;
      default:
        bg = colorScheme.primaryContainer;
        fg = colorScheme.onPrimaryContainer;
        icon = Icons.check_circle_outline;
        label = l10n.cronsHermesStatusOk;
    }
    return _metaChip(
      theme,
      colorScheme,
      icon: icon,
      label: label,
      bg: bg,
      tone: fg,
    );
  }

  Widget _metaChip(
    ThemeData theme,
    ColorScheme colorScheme, {
    required IconData icon,
    required String label,
    Color? bg,
    Color? tone,
  }) {
    final background =
        bg ?? colorScheme.secondaryContainer.withValues(alpha: 0.65);
    final foreground = tone ?? colorScheme.onSecondaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: kOpenHandPillBorderRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: foreground),
          kOpenHandHGap4,
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _changeGroup({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required String title,
    required IconData icon,
    required List<Map<String, Object?>> changes,
    required AppLocalizations l10n,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer.withValues(alpha: 0.5),
          borderRadius: kOpenHandBorderRadius14,
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.32),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: kOpenHandBorderRadius8,
                  ),
                  child: Icon(
                    icon,
                    size: 14,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                kOpenHandHGap8,
                Text(
                  '$title (${changes.length})',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            kOpenHandGap8,
            ...changes.map(
              (m) => _changeRow(
                theme: theme,
                colorScheme: colorScheme,
                change: m,
                l10n: l10n,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _changeRow({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required Map<String, Object?> change,
    required AppLocalizations l10n,
  }) {
    final action = _firstText(change, const ['action', 'type', 'operation']);
    final heading = _firstText(change, const [
      'summary',
      'description',
      'content',
      'name',
      'title',
    ]);
    final id = _firstText(change, const ['id', 'key', 'path', 'target']);
    final details = _detailEntries(change)
        .map((entry) => '**${_labelFor(entry.key, l10n)}**: ${entry.value}')
        .toList(growable: false);
    final fallback = jsonEncodeOrString(change);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.62),
          borderRadius: kOpenHandBorderRadius12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (action != null)
                  _miniPill(
                    theme,
                    colorScheme,
                    label: action,
                    icon: Icons.bolt_rounded,
                  ),
                if (id != null)
                  _miniPill(
                    theme,
                    colorScheme,
                    label: id,
                    icon: Icons.tag_rounded,
                    subdued: true,
                  ),
              ],
            ),
            if (heading != null) ...[
              kOpenHandGap6,
              _hermesInlineMarkdown(
                data: heading,
                theme: theme,
                colorScheme: colorScheme,
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ],
            if (details.isNotEmpty) ...[
              kOpenHandGap6,
              ...details.map(
                (line) => Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: _hermesInlineMarkdown(
                    data: line,
                    theme: theme,
                    colorScheme: colorScheme,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.32,
                  ),
                ),
              ),
            ] else if (heading == null) ...[
              kOpenHandGap6,
              SelectableText(
                fallback,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.32,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _miniPill(
    ThemeData theme,
    ColorScheme colorScheme, {
    required String label,
    required IconData icon,
    bool subdued = false,
  }) {
    final background = subdued
        ? colorScheme.surfaceContainerHighest
        : colorScheme.secondaryContainer;
    final foreground = subdued
        ? colorScheme.onSurfaceVariant
        : colorScheme.onSecondaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: kOpenHandPillBorderRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: foreground),
          kOpenHandHGap4,
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  String? _firstText(Map<String, Object?> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
      if (value is num || value is bool) {
        return '$value';
      }
    }
    return null;
  }

  List<MapEntry<String, String>> _detailEntries(Map<String, Object?> map) {
    const skip = <String>{
      'action',
      'type',
      'operation',
      'summary',
      'description',
      'content',
      'name',
      'title',
      'id',
      'key',
      'path',
      'target',
    };
    final out = <MapEntry<String, String>>[];
    for (final entry in map.entries) {
      if (skip.contains(entry.key)) continue;
      final value = _formatValue(entry.value);
      if (value.isNotEmpty) out.add(MapEntry(entry.key, value));
    }
    return out.take(6).toList(growable: false);
  }

  String _labelFor(String key, AppLocalizations l10n) {
    return switch (key) {
      'before' => l10n.cronsHermesChangeBefore,
      'after' => l10n.cronsHermesChangeAfter,
      'value' => l10n.cronsHermesChangeValue,
      'source' => l10n.cronsHermesChangeSource,
      'reason' => l10n.cronsHermesChangeReason,
      'metadata' => l10n.cronsHermesChangeMetadata,
      'error' => l10n.cronsHermesChangeError,
      _ => key,
    };
  }

  String _formatValue(Object? value) {
    if (value == null) return '';
    if (value is String) return value.trim();
    if (value is num || value is bool) return '$value';
    return jsonEncodeOrString(value);
  }
}

/// 折叠展开的长文本块；超过阈值时默认折叠预览，点击切换全文。
class _CollapsibleLongText extends StatefulWidget {
  const _CollapsibleLongText({
    required this.title,
    required this.icon,
    required this.body,
    this.subdued = false,
  });

  static const int _previewChars = 320;

  /// 超出此长度时回退纯文本，避免批量展开历史项时卡顿。
  static const int _markdownByteLimit = 120 * kBytesPerKiB;

  final String title;
  final IconData icon;
  final String body;
  final bool subdued;

  @override
  State<_CollapsibleLongText> createState() => _CollapsibleLongTextState();
}

class _CollapsibleLongTextState extends State<_CollapsibleLongText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final body = widget.body.trim();
    final exceeds = body.length > _CollapsibleLongText._previewChars;
    final shown = (_expanded || !exceeds)
        ? body
        : clipTextByCodeUnits(
            body,
            _CollapsibleLongText._previewChars,
            suffix: '…',
          );
    final l10n = AppLocalizations.of(context)!;

    final bodyTextColor = widget.subdued
        ? colorScheme.onSurfaceVariant
        : colorScheme.onSurface;
    final fallbackTextStyle = theme.textTheme.bodySmall?.copyWith(
      color: bodyTextColor,
      height: 1.4,
      fontStyle: widget.subdued ? FontStyle.italic : FontStyle.normal,
    );

    // 超长正文跳过 Markdown 解析。
    final useMarkdown = shown.length <= _CollapsibleLongText._markdownByteLimit;

    final Widget bodyWidget = useMarkdown
        ? MarkdownBody(
            data: shown,
            selectable: true,
            softLineBreak: true,
            styleSheet: _buildCollapsibleMarkdownStyleSheet(
              theme: theme,
              colorScheme: colorScheme,
              baseColor: bodyTextColor,
              subdued: widget.subdued,
            ),
          )
        : SelectableText(shown, style: fallbackTextStyle);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: widget.subdued
              ? colorScheme.surfaceContainer.withValues(alpha: 0.55)
              : colorScheme.surfaceContainerHigh.withValues(alpha: 0.65),
          borderRadius: kOpenHandBorderRadius12,
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  widget.icon,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
                kOpenHandHGap6,
                Text(
                  widget.title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (exceeds)
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => setState(() => _expanded = !_expanded),
                    child: Text(
                      _expanded ? l10n.cronsCollapse : l10n.cronsExpand,
                    ),
                  ),
              ],
            ),
            kOpenHandGap4,
            bodyWidget,
          ],
        ),
      ),
    );
  }
}

/// Cron 历史卡片使用的紧凑 Markdown 样式。
MarkdownStyleSheet _buildCollapsibleMarkdownStyleSheet({
  required ThemeData theme,
  required ColorScheme colorScheme,
  required Color baseColor,
  required bool subdued,
}) {
  final base = theme.textTheme.bodySmall?.copyWith(
    color: baseColor,
    height: 1.4,
    fontStyle: subdued ? FontStyle.italic : FontStyle.normal,
  );
  final mono = base?.copyWith(
    fontFamily: kOpenHandMonospaceFontFamily,
    fontSize: 11,
    fontStyle: FontStyle.normal,
  );
  final codeBg = colorScheme.surfaceContainerHighest.withValues(alpha: 0.55);
  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    p: base,
    a: base?.copyWith(
      color: colorScheme.primary,
      decoration: TextDecoration.underline,
    ),
    code: mono?.copyWith(backgroundColor: codeBg),
    codeblockPadding: const EdgeInsets.all(8),
    codeblockDecoration: BoxDecoration(
      color: codeBg,
      borderRadius: kOpenHandBorderRadius8,
      border: Border.all(
        color: colorScheme.outlineVariant.withValues(alpha: 0.35),
      ),
    ),
    blockquoteDecoration: BoxDecoration(
      color: colorScheme.surfaceContainer.withValues(alpha: 0.45),
      borderRadius: kOpenHandBorderRadius6,
      border: Border(
        left: BorderSide(
          color: colorScheme.primary.withValues(alpha: 0.55),
          width: 3,
        ),
      ),
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
    h1: theme.textTheme.titleMedium?.copyWith(
      color: baseColor,
      fontWeight: FontWeight.w700,
    ),
    h2: theme.textTheme.titleSmall?.copyWith(
      color: baseColor,
      fontWeight: FontWeight.w700,
    ),
    h3: theme.textTheme.bodyMedium?.copyWith(
      color: baseColor,
      fontWeight: FontWeight.w700,
    ),
    h4: theme.textTheme.bodyMedium?.copyWith(
      color: baseColor,
      fontWeight: FontWeight.w600,
    ),
    h5: theme.textTheme.bodySmall?.copyWith(
      color: baseColor,
      fontWeight: FontWeight.w600,
    ),
    h6: theme.textTheme.bodySmall?.copyWith(
      color: baseColor,
      fontWeight: FontWeight.w600,
    ),
    listBullet: base,
    tableHead: base?.copyWith(fontWeight: FontWeight.w600),
    tableBody: base,
    tableBorder: TableBorder.all(
      color: colorScheme.outlineVariant.withValues(alpha: 0.35),
      width: 0.6,
    ),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(
        top: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
    ),
  );
}

/// Hermes Talker 短字段使用的内联 Markdown 组件。
Widget _hermesInlineMarkdown({
  required String data,
  required ThemeData theme,
  required ColorScheme colorScheme,
  required Color color,
  FontWeight? fontWeight,
  FontStyle? fontStyle,
  double height = 1.35,
}) {
  // 超长内联内容使用纯文本。
  const inlineByteLimit = 4 * kBytesPerKiB;
  final base = theme.textTheme.bodySmall?.copyWith(
    color: color,
    fontWeight: fontWeight,
    fontStyle: fontStyle,
    height: height,
  );
  if (data.length > inlineByteLimit) {
    return SelectableText(data, style: base);
  }
  return MarkdownBody(
    data: data,
    selectable: true,
    softLineBreak: true,
    styleSheet: _buildHermesInlineMarkdownStyleSheet(
      theme: theme,
      colorScheme: colorScheme,
      base: base,
    ),
  );
}

MarkdownStyleSheet _buildHermesInlineMarkdownStyleSheet({
  required ThemeData theme,
  required ColorScheme colorScheme,
  required TextStyle? base,
}) {
  final mono = base?.copyWith(
    fontFamily: kOpenHandMonospaceFontFamily,
    fontSize: 11,
  );
  final codeBg = colorScheme.surfaceContainerHighest.withValues(alpha: 0.55);
  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    p: base,
    a: base?.copyWith(
      color: colorScheme.primary,
      decoration: TextDecoration.underline,
    ),
    code: mono?.copyWith(backgroundColor: codeBg),
    codeblockPadding: const EdgeInsets.all(6),
    codeblockDecoration: BoxDecoration(
      color: codeBg,
      borderRadius: kOpenHandBorderRadius6,
    ),
    blockquoteDecoration: BoxDecoration(
      color: colorScheme.surfaceContainer.withValues(alpha: 0.45),
      borderRadius: kOpenHandBorderRadius6,
      border: Border(
        left: BorderSide(
          color: colorScheme.primary.withValues(alpha: 0.55),
          width: 3,
        ),
      ),
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
    listBullet: base,
    h1: base?.copyWith(fontWeight: FontWeight.w700),
    h2: base?.copyWith(fontWeight: FontWeight.w700),
    h3: base?.copyWith(fontWeight: FontWeight.w700),
    h4: base?.copyWith(fontWeight: FontWeight.w600),
    h5: base?.copyWith(fontWeight: FontWeight.w600),
    h6: base?.copyWith(fontWeight: FontWeight.w600),
    tableHead: base?.copyWith(fontWeight: FontWeight.w600),
    tableBody: base,
    tableBorder: TableBorder.all(
      color: colorScheme.outlineVariant.withValues(alpha: 0.35),
      width: 0.6,
    ),
  );
}
