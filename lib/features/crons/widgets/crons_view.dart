import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../app/model/cron_config.dart';
import '../../../app/support/openhand_notification_service.dart';
import '../../../app/support/silent_log.dart';
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
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_typography.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/platform_shell.dart';
import '../../../shared/util/text_clip.dart';
import '../../../shared/util/text_normalization.dart';
import '../../ai/index.dart';
import '../crons_controller.dart';
import '../model/cron_parser.dart';

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
                  onPressed: snapshot.isLoading || snapshot.errorMessage != null
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
                        separatorBuilder: (context, index) => kOpenHandGap12,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          return AppearOnce(
                            key: ValueKey<String>('cron-entry-${entry.id}'),
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
    showAnimatedDialog(
      context: context,
      builder: (_) => _CronEditorDialog(existing: existing),
    );
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final visibleTags = entry.tags
        .take(_cronTagPreviewLimit)
        .toList(growable: false);
    final hiddenTagCount = entry.tags.length - visibleTags.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _CronStatusDot(status: entry.status, enabled: entry.enabled),
                kOpenHandHGap12,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: entry.enabled
                              ? colorScheme.onSurface
                              : colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (entry.description.isNotEmpty) ...[
                        kOpenHandGap2,
                        Text(
                          entry.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                kOpenHandHGap12,
                Tooltip(
                  message: l10n.cronsCronExpressionTooltip,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.tertiaryContainer,
                      borderRadius: kOpenHandBorderRadius12,
                    ),
                    child: Text(
                      entry.cronExpression,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onTertiaryContainer,
                        fontFamily: kOpenHandMonospaceFontFamily,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
                kOpenHandHGap8,
                OpenHandMetricChip(
                  label: '${entry.timeoutSeconds}s',
                  tooltip: l10n.cronsTimeoutTooltip,
                ),
                kOpenHandHGap8,
                if (entry.retryCount > 0) ...[
                  Tooltip(
                    message: l10n.cronsRetryCountTooltip,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHigh,
                        borderRadius: kOpenHandBorderRadius12,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.replay_rounded,
                            size: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          kOpenHandHGap4,
                          Text(
                            '${entry.retryCount}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  kOpenHandHGap8,
                ],
                Builder(
                  builder: (context) {
                    final locked = entry.tags.contains(
                      CronsController.mcpKeywordIndexTag,
                    );
                    final toggle = Switch(
                      value: entry.enabled,
                      onChanged: locked ? null : onToggle,
                    );
                    if (!locked) return toggle;
                    return Tooltip(
                      message: l10n.cronsMcpKeywordIndexLockedTooltip,
                      child: toggle,
                    );
                  },
                ),
                kOpenHandHGap8,
                // 系统任务允许启停，但禁止编辑和删除以保持参数不可变。
                IconButton(
                  icon: const Icon(Icons.bolt_rounded, size: 20),
                  tooltip: l10n.cronsRunOnceNow,
                  onPressed: entry.enabled ? onRunNow : null,
                ),
                kOpenHandHGap4,
                IconButton(
                  icon: const Icon(Icons.history_rounded, size: 20),
                  tooltip: l10n.cronsHistory,
                  onPressed: onHistory,
                ),
                kOpenHandHGap4,
                IconButton(
                  icon: Icon(
                    Icons.edit_outlined,
                    size: 20,
                    color: entry.tags.contains('system')
                        ? colorScheme.onSurfaceVariant.withValues(alpha: 0.4)
                        : null,
                  ),
                  tooltip: l10n.commonEdit,
                  onPressed: entry.tags.contains('system') ? null : onEdit,
                ),
                kOpenHandHGap4,
                IconButton(
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: entry.tags.contains('system')
                        ? colorScheme.onSurfaceVariant.withValues(alpha: 0.4)
                        : colorScheme.error,
                  ),
                  tooltip: l10n.commonDelete,
                  onPressed: entry.tags.contains('system') ? null : onDelete,
                ),
              ],
            ),
            if (entry.tags.isNotEmpty || entry.lastRunAt != null) ...[
              kOpenHandGap8,
              Row(
                children: [
                  if (entry.tags.isNotEmpty)
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final tag in visibleTags)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.secondaryContainer,
                                borderRadius: kOpenHandBorderRadius10,
                              ),
                              child: Text(
                                tag,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSecondaryContainer,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          if (hiddenTagCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHigh,
                                borderRadius: kOpenHandBorderRadius10,
                              ),
                              child: Text(
                                '+$hiddenTagCount',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  _CronStatusChip(entry: entry),
                  if (entry.lastRunAt != null) ...[
                    kOpenHandHGap8,
                    Text(
                      l10n.cronsLastRunAt(formatMonthDayHms(entry.lastRunAt!)),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.7,
                        ),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CronStatusDot extends StatelessWidget {
  const _CronStatusDot({required this.status, required this.enabled});

  final CronJobStatus status;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = !enabled
        ? colorScheme.outlineVariant
        : switch (status) {
            CronJobStatus.running => _kCronRunningColor,
            CronJobStatus.idle => colorScheme.outline,
            CronJobStatus.paused => colorScheme.tertiary,
            CronJobStatus.failed => colorScheme.error,
            CronJobStatus.error => colorScheme.error,
          };

    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _CronStatusChip extends StatelessWidget {
  const _CronStatusChip({required this.entry});

  final CronEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final statusLabel = entry.status.label(l10n);
    final bgColor = switch (entry.status) {
      CronJobStatus.running => _kCronRunningColor.withValues(alpha: 0.15),
      CronJobStatus.idle => colorScheme.surfaceContainerHigh,
      CronJobStatus.paused => colorScheme.tertiaryContainer,
      CronJobStatus.failed => colorScheme.errorContainer,
      CronJobStatus.error => colorScheme.errorContainer,
    };
    final fgColor = switch (entry.status) {
      CronJobStatus.running => _kCronRunningColor,
      CronJobStatus.idle => colorScheme.onSurfaceVariant,
      CronJobStatus.paused => colorScheme.onTertiaryContainer,
      CronJobStatus.failed => colorScheme.onErrorContainer,
      CronJobStatus.error => colorScheme.onErrorContainer,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: kOpenHandBorderRadius10,
      ),
      child: Text(
        statusLabel,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fgColor,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CronEditorDialog extends StatefulWidget {
  const _CronEditorDialog({this.existing});

  final CronEntry? existing;

  @override
  State<_CronEditorDialog> createState() => _CronEditorDialogState();
}

enum _NotificationTestScenario { success, failure, timeout, all }

typedef _NotificationTestConfig = ({
  CronNotifyType type,
  CronNotifySeverity severity,
  bool soundEnabled,
  bool vibrationEnabled,
  String message,
  String label,
  String defaultBody,
});

class _CronEditorDialogState extends State<_CronEditorDialog> {
  static const Uuid _uuid = Uuid();

  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _scriptPathController;
  late final TextEditingController _scriptContentController;
  late final TextEditingController _timeoutController;
  late final TextEditingController _retryController;
  late final TextEditingController _tagsController;
  late final TextEditingController _workingDirController;
  late final TextEditingController _envController;
  late final TextEditingController _maxRetryDelayController;
  late final TextEditingController _onSuccessMsgController;
  late final TextEditingController _onFailureMsgController;
  late final TextEditingController _onTimeoutMsgController;

  // Cron 五段表达式：分、时、日、月、周。
  late final TextEditingController _cronMinController;
  late final TextEditingController _cronHourController;
  late final TextEditingController _cronDomController;
  late final TextEditingController _cronMonController;
  late final TextEditingController _cronDowController;

  late CronScriptType _scriptType;
  late bool _enabled;
  late String? _runAsUser;
  late CronNotifyType _onSuccessNotify;
  late CronNotifyType _onFailureNotify;
  late CronNotifyType _onTimeoutNotify;
  late CronNotifySeverity _onSuccessSeverity;
  late CronNotifySeverity _onFailureSeverity;
  late CronNotifySeverity _onTimeoutSeverity;
  late bool _onSuccessSound;
  late bool _onFailureSound;
  late bool _onTimeoutSound;
  late bool _onSuccessVibration;
  late bool _onFailureVibration;
  late bool _onTimeoutVibration;
  late bool _collectAppMetadata;
  late bool _collectHostMetadata;
  late bool _collectEnvironmentSnapshot;

  bool _saving = false;
  String? _cronError;
  String? _formError;
  int _notificationTestGeneration = 0;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: e?.name ?? '');
    _descriptionController = TextEditingController(text: e?.description ?? '');
    _scriptPathController = TextEditingController(text: e?.scriptPath ?? '');
    _scriptContentController = TextEditingController(
      text: e?.scriptContent ?? '',
    );
    _timeoutController = TextEditingController(
      text: '${e?.timeoutSeconds ?? kCronDefaultTimeoutSeconds}',
    );
    _retryController = TextEditingController(
      text: '${e?.retryCount ?? kCronDefaultRetryCount}',
    );
    _tagsController = TextEditingController(text: e?.tags.join(', ') ?? '');
    _workingDirController = TextEditingController(
      text: e?.workingDirectory ?? '',
    );
    _envController = TextEditingController(
      text:
          e?.environment.entries
              .map((en) => '${en.key}=${en.value}')
              .join('\n') ??
          '',
    );
    _maxRetryDelayController = TextEditingController(
      text: '${e?.maxRetryDelaySeconds ?? kCronDefaultRetryDelaySeconds}',
    );
    _onSuccessMsgController = TextEditingController(
      text: e?.onSuccessMessage ?? '',
    );
    _onFailureMsgController = TextEditingController(
      text: e?.onFailureMessage ?? '',
    );
    _onTimeoutMsgController = TextEditingController(
      text: e?.onTimeoutMessage ?? '',
    );

    final cronParts = (e?.cronExpression ?? '* * * * *').split(
      kInlineWhitespacePattern,
    );
    _cronMinController = TextEditingController(
      text: cronParts.isNotEmpty ? cronParts[0] : '*',
    );
    _cronHourController = TextEditingController(
      text: cronParts.length > 1 ? cronParts[1] : '*',
    );
    _cronDomController = TextEditingController(
      text: cronParts.length > 2 ? cronParts[2] : '*',
    );
    _cronMonController = TextEditingController(
      text: cronParts.length > 3 ? cronParts[3] : '*',
    );
    _cronDowController = TextEditingController(
      text: cronParts.length > 4 ? cronParts[4] : '*',
    );

    _scriptType = e?.scriptType ?? CronScriptType.command;
    _enabled = e?.enabled ?? true;
    _runAsUser = e?.runAsUser;
    _onSuccessNotify = e?.onSuccessNotify ?? CronNotifyType.log;
    _onFailureNotify = e?.onFailureNotify ?? CronNotifyType.system;
    _onTimeoutNotify = e?.onTimeoutNotify ?? CronNotifyType.system;
    _onSuccessSeverity = e?.onSuccessSeverity ?? CronNotifySeverity.success;
    _onFailureSeverity = e?.onFailureSeverity ?? CronNotifySeverity.error;
    _onTimeoutSeverity = e?.onTimeoutSeverity ?? CronNotifySeverity.warning;
    _onSuccessSound = e?.onSuccessPlaySound ?? false;
    _onFailureSound = e?.onFailurePlaySound ?? true;
    _onTimeoutSound = e?.onTimeoutPlaySound ?? true;
    _onSuccessVibration = e?.onSuccessVibrate ?? false;
    _onFailureVibration = e?.onFailureVibrate ?? true;
    _onTimeoutVibration = e?.onTimeoutVibrate ?? true;
    _collectAppMetadata = e?.collectAppMetadata ?? true;
    _collectHostMetadata = e?.collectHostMetadata ?? true;
    _collectEnvironmentSnapshot = e?.collectEnvironmentSnapshot ?? false;
  }

  @override
  void dispose() {
    _notificationTestGeneration++;
    _nameController.dispose();
    _descriptionController.dispose();
    _scriptPathController.dispose();
    _scriptContentController.dispose();
    _timeoutController.dispose();
    _retryController.dispose();
    _tagsController.dispose();
    _workingDirController.dispose();
    _envController.dispose();
    _maxRetryDelayController.dispose();
    _onSuccessMsgController.dispose();
    _onFailureMsgController.dispose();
    _onTimeoutMsgController.dispose();
    _cronMinController.dispose();
    _cronHourController.dispose();
    _cronDomController.dispose();
    _cronMonController.dispose();
    _cronDowController.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.existing != null;
  AppLocalizations get l10n => AppLocalizations.of(context)!;

  String get _cronExpression =>
      '${_cronMinController.text.trim()} '
      '${_cronHourController.text.trim()} '
      '${_cronDomController.text.trim()} '
      '${_cronMonController.text.trim()} '
      '${_cronDowController.text.trim()}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final systemUsers = context.select<CronsController, List<String>>(
      (controller) => controller.systemUsers,
    );

    return buildOpenHandAlertDialog(
      title: Text(_isEditing ? l10n.cronsEditCronJob : l10n.cronsNewCronJob),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildOpenHandDialogValidationMessage(
                context,
                message: _formError,
              ),
              if (_formError != null) kOpenHandGap12,
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: l10n.cronsFieldName,
                  hintText: l10n.cronsFieldNameHint,
                ),
              ),
              kOpenHandGap14,
              TextField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: l10n.cronsFieldDescription,
                  hintText: l10n.commonOptional,
                ),
              ),
              kOpenHandGap18,
              Text(l10n.cronsFieldType, style: theme.textTheme.titleSmall),
              kOpenHandGap8,
              SegmentedButton<CronScriptType>(
                segments: [
                  ButtonSegment(
                    value: CronScriptType.command,
                    icon: const Icon(Icons.terminal_rounded, size: 18),
                    label: Text(CronScriptType.command.label(l10n)),
                  ),
                  ButtonSegment(
                    value: CronScriptType.script,
                    icon: const Icon(Icons.description_outlined, size: 18),
                    label: Text(CronScriptType.script.label(l10n)),
                  ),
                ],
                selected: {_scriptType},
                onSelectionChanged: (selected) {
                  setState(() => _scriptType = selected.first);
                },
              ),
              kOpenHandGap14,
              if (_scriptType == CronScriptType.script) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _scriptPathController,
                        decoration: InputDecoration(
                          labelText: l10n.cronsFieldScriptFilePath,
                          hintText: l10n.cronsFieldScriptFilePathHint,
                        ),
                        readOnly: true,
                      ),
                    ),
                    kOpenHandHGap8,
                    FilledButton.tonal(
                      onPressed: _pickScriptFile,
                      child: Text(l10n.cronsBrowse),
                    ),
                  ],
                ),
              ] else ...[
                TextField(
                  controller: _scriptContentController,
                  maxLines: 6,
                  minLines: 3,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.all(12),
                    labelText: l10n.cronsFieldCommand,
                    hintText: Platform.isWindows
                        ? l10n.cronsFieldCommandHintWindows
                        : l10n.cronsFieldCommandHintShell,
                    hintStyle: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.5,
                      ),
                      fontFamily: kOpenHandMonospaceFontFamily,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
              kOpenHandGap18,
              Text(l10n.cronsCronSchedule, style: theme.textTheme.titleSmall),
              kOpenHandGap8,
              Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 10,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '0',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: kOpenHandMonospaceFontFamily,
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.4,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  kOpenHandHGap6,
                  _cronField(_cronMinController, l10n.cronParserFieldMinute),
                  kOpenHandHGap6,
                  _cronField(_cronHourController, l10n.cronParserFieldHour),
                  kOpenHandHGap6,
                  _cronField(
                    _cronDomController,
                    l10n.cronParserFieldDayOfMonthShort,
                  ),
                  kOpenHandHGap6,
                  _cronField(_cronMonController, l10n.cronParserFieldMonth),
                  kOpenHandHGap6,
                  _cronField(
                    _cronDowController,
                    l10n.cronParserFieldDayOfWeekShort,
                  ),
                ],
              ),
              if (_cronError != null) ...[
                kOpenHandGap4,
                Text(
                  _cronError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.error,
                  ),
                ),
              ],
              kOpenHandGap4,
              Text(
                l10n.cronsCronScheduleHelper,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  fontSize: 11,
                ),
              ),
              kOpenHandGap18,
              Row(
                children: [
                  Text(
                    l10n.cronsTimeoutSeconds,
                    style: theme.textTheme.titleSmall,
                  ),
                  kOpenHandHGap8,
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: _timeoutController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                  kOpenHandHGap24,
                  Text(l10n.cronsRetries, style: theme.textTheme.titleSmall),
                  kOpenHandHGap8,
                  SizedBox(
                    width: 60,
                    child: TextField(
                      controller: _retryController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                  kOpenHandHGap24,
                  Text(
                    l10n.cronsMaxRetryDelaySeconds,
                    style: theme.textTheme.titleSmall,
                  ),
                  kOpenHandHGap8,
                  SizedBox(
                    width: 60,
                    child: TextField(
                      controller: _maxRetryDelayController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              kOpenHandGap18,
              Text(l10n.cronsRunAsUser, style: theme.textTheme.titleSmall),
              kOpenHandGap8,
              AnimatedDropdownButtonFormField<String>(
                initialValue: _runAsUser,
                decoration: InputDecoration(
                  hintText: l10n.cronsDefaultCurrentUser,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                items: [
                  DropdownMenuItem<String>(child: Text(l10n.cronsDefault)),
                  ...systemUsers.map(
                    (u) => DropdownMenuItem<String>(value: u, child: Text(u)),
                  ),
                ],
                onChanged: (v) => setState(() => _runAsUser = v),
              ),
              kOpenHandGap18,
              TextField(
                controller: _tagsController,
                decoration: InputDecoration(
                  labelText: l10n.cronsTagsCommaSeparated,
                  hintText: l10n.cronsTagsHint,
                ),
              ),
              kOpenHandGap18,
              TextField(
                controller: _workingDirController,
                decoration: InputDecoration(
                  labelText: l10n.cronsWorkingDirectory,
                  hintText: l10n.cronsWorkingDirectoryHint,
                ),
              ),
              kOpenHandGap18,
              TextField(
                controller: _envController,
                maxLines: 3,
                minLines: 2,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: kOpenHandMonospaceFontFamily,
                  fontSize: 12,
                ),
                decoration: InputDecoration(
                  labelText: l10n.cronsEnvironmentVariables,
                  hintText: l10n.cronsEnvironmentVariablesHint,
                  contentPadding: const EdgeInsets.all(12),
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    fontFamily: kOpenHandMonospaceFontFamily,
                    fontSize: 12,
                  ),
                ),
              ),
              kOpenHandGap14,
              Text(
                l10n.cronsExecutionContextCollection,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              kOpenHandGap10,
              Container(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(kOpenHandRadius24),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                  ),
                ),
                child: Column(
                  children: [
                    _contextCollectTile(
                      icon: Icons.apps_rounded,
                      label: l10n.cronsCollectAppMetadata,
                      subtitle: l10n.cronsCollectAppMetadataSubtitle,
                      value: _collectAppMetadata,
                      onChanged: (value) =>
                          setState(() => _collectAppMetadata = value),
                    ),
                    _contextCollectTile(
                      icon: Icons.dns_rounded,
                      label: l10n.cronsCollectHostMetadata,
                      subtitle: l10n.cronsCollectHostMetadataSubtitle,
                      value: _collectHostMetadata,
                      onChanged: (value) =>
                          setState(() => _collectHostMetadata = value),
                    ),
                    _contextCollectTile(
                      icon: Icons.inventory_2_outlined,
                      label: l10n.cronsCollectEnvironmentSnapshot,
                      subtitle: l10n.cronsCollectEnvironmentSnapshotSubtitle,
                      value: _collectEnvironmentSnapshot,
                      isSensitive: true,
                      onChanged: (value) =>
                          setState(() => _collectEnvironmentSnapshot = value),
                    ),
                  ],
                ),
              ),
              kOpenHandGap18,
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.cronsNotificationSettings,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  AnimatedPopupMenuButton<_NotificationTestScenario>(
                    tooltip: l10n.cronsTestNotification,
                    onSelected: _testNotification,
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: _NotificationTestScenario.success,
                        child: Text(l10n.cronsTestSuccessNotification),
                      ),
                      PopupMenuItem(
                        value: _NotificationTestScenario.failure,
                        child: Text(l10n.cronsTestFailureNotification),
                      ),
                      PopupMenuItem(
                        value: _NotificationTestScenario.timeout,
                        child: Text(l10n.cronsTestTimeoutNotification),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: _NotificationTestScenario.all,
                        child: Text(l10n.cronsTestAllNotifications),
                      ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(kOpenHandRadius22),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.9,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.notifications_active_outlined,
                            size: 16,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          kOpenHandHGap6,
                          Text(
                            l10n.cronsTestNotification,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: colorScheme.onSurface,
                            ),
                          ),
                          kOpenHandHGap4,
                          Icon(
                            Icons.arrow_drop_down_rounded,
                            size: 18,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              kOpenHandGap4,
              Text(
                l10n.cronsNotificationSettingsHelper,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              kOpenHandGap8,
              _notifyRow(
                label: l10n.cronsOnSuccess,
                notifyType: _onSuccessNotify,
                severity: _onSuccessSeverity,
                soundEnabled: _onSuccessSound,
                vibrationEnabled: _onSuccessVibration,
                msgController: _onSuccessMsgController,
                onNotifyChanged: (v) => setState(() => _onSuccessNotify = v),
                onSeverityChanged: (v) =>
                    setState(() => _onSuccessSeverity = v),
                onSoundChanged: (v) => setState(() => _onSuccessSound = v),
                onVibrationChanged: (v) =>
                    setState(() => _onSuccessVibration = v),
              ),
              kOpenHandGap8,
              _notifyRow(
                label: l10n.cronsOnFailure,
                notifyType: _onFailureNotify,
                severity: _onFailureSeverity,
                soundEnabled: _onFailureSound,
                vibrationEnabled: _onFailureVibration,
                msgController: _onFailureMsgController,
                onNotifyChanged: (v) => setState(() => _onFailureNotify = v),
                onSeverityChanged: (v) =>
                    setState(() => _onFailureSeverity = v),
                onSoundChanged: (v) => setState(() => _onFailureSound = v),
                onVibrationChanged: (v) =>
                    setState(() => _onFailureVibration = v),
              ),
              kOpenHandGap8,
              _notifyRow(
                label: l10n.cronsOnTimeout,
                notifyType: _onTimeoutNotify,
                severity: _onTimeoutSeverity,
                soundEnabled: _onTimeoutSound,
                vibrationEnabled: _onTimeoutVibration,
                msgController: _onTimeoutMsgController,
                onNotifyChanged: (v) => setState(() => _onTimeoutNotify = v),
                onSeverityChanged: (v) =>
                    setState(() => _onTimeoutSeverity = v),
                onSoundChanged: (v) => setState(() => _onTimeoutSound = v),
                onVibrationChanged: (v) =>
                    setState(() => _onTimeoutVibration = v),
              ),
              kOpenHandGap14,
              Row(
                children: [
                  Text(l10n.cronsEnabled, style: theme.textTheme.titleSmall),
                  const Spacer(),
                  Switch(
                    value: _enabled,
                    onChanged: (value) => setState(() => _enabled = value),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          label: l10n.commonCancel,
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        OpenHandDialogActionButton.primary(
          label: l10n.commonSave,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }

  Widget _cronField(TextEditingController controller, String label) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          SizedBox(
            height: 42,
            child: TextField(
              controller: controller,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: kOpenHandMonospaceFontFamily,
              ),
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 8,
                ),
              ),
              onChanged: (_) => _validateCron(),
            ),
          ),
          kOpenHandGap2,
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _notifyRow({
    required String label,
    required CronNotifyType notifyType,
    required CronNotifySeverity severity,
    required bool soundEnabled,
    required bool vibrationEnabled,
    required TextEditingController msgController,
    required ValueChanged<CronNotifyType> onNotifyChanged,
    required ValueChanged<CronNotifySeverity> onSeverityChanged,
    required ValueChanged<bool> onSoundChanged,
    required ValueChanged<bool> onVibrationChanged,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final vibrationUnsupported =
        vibrationEnabled && !OpenHandNotificationService.supportsVibration;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kOpenHandRadius24),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            kOpenHandGap12,
            Row(
              children: [
                Flexible(
                  child: AnimatedDropdownButtonFormField<CronNotifyType>(
                    initialValue: notifyType,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                    items: CronNotifyType.values.map((n) {
                      return DropdownMenuItem(
                        value: n,
                        child: Text(n.label(l10n)),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) onNotifyChanged(v);
                    },
                  ),
                ),
                kOpenHandHGap8,
                Flexible(
                  child: AnimatedDropdownButtonFormField<CronNotifySeverity>(
                    initialValue: severity,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                    items: CronNotifySeverity.values.map((s) {
                      return DropdownMenuItem(
                        value: s,
                        child: Text(s.label(l10n)),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) onSeverityChanged(v);
                    },
                  ),
                ),
                kOpenHandHGap8,
                Tooltip(
                  message: _soundSupportTooltip(soundEnabled),
                  child: IconButton.filledTonal(
                    onPressed: () => onSoundChanged(!soundEnabled),
                    icon: Icon(
                      soundEnabled
                          ? Icons.volume_up_rounded
                          : Icons.volume_off_rounded,
                      size: 18,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                kOpenHandHGap4,
                Tooltip(
                  message: _vibrationSupportTooltip(vibrationEnabled),
                  child: IconButton.filledTonal(
                    onPressed: () => onVibrationChanged(!vibrationEnabled),
                    icon: Icon(
                      vibrationEnabled
                          ? Icons.vibration_rounded
                          : Icons.vibration_outlined,
                      size: 18,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            kOpenHandGap10,
            TextField(
              controller: msgController,
              decoration: InputDecoration(
                hintText: l10n.cronsCustomNotificationMessageHint,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
            ),
            if (vibrationUnsupported) ...[
              kOpenHandGap6,
              Text(
                l10n.cronsVibrationUnsupportedHint,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _validateCron() {
    final expr = _cronExpression;
    final err = CronParser.validate(expr, l10n: l10n);
    if (err != _cronError) {
      setState(() => _cronError = err);
    }
  }

  Future<void> _pickScriptFile() async {
    final List<XTypeGroup> typeGroups;
    if (Platform.isWindows) {
      typeGroups = [
        const XTypeGroup(label: 'Scripts', extensions: ['ps1', 'bat', 'cmd']),
      ];
    } else {
      typeGroups = [
        const XTypeGroup(label: 'Shell Scripts', extensions: ['sh']),
        const XTypeGroup(label: 'All Files', extensions: ['*']),
      ];
    }
    final file = await openFile(acceptedTypeGroups: typeGroups);
    if (!mounted) return;
    if (file != null) {
      setState(() {
        _scriptPathController.text = file.path;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameController.text.trim();
    final validationError = _validateForm(name);
    if (validationError != null) {
      setState(() => _formError = validationError);
      return;
    }

    // 校验 Cron 表达式。
    final cronExpr = _cronExpression;
    final cronErr = CronParser.validate(cronExpr, l10n: l10n);
    if (cronErr != null) {
      setState(() {
        _cronError = cronErr;
        _formError = null;
      });
      return;
    }

    final timeout = clampedIntFromText(
      _timeoutController.text,
      fallback: kCronDefaultTimeoutSeconds,
      min: kCronMinTimeoutSeconds,
      max: kCronMaxTimeoutSeconds,
    );
    final retryCount = clampedIntFromText(
      _retryController.text,
      fallback: kCronDefaultRetryCount,
      min: kCronMinRetryCount,
      max: kCronMaxRetryCount,
    );
    final maxRetryDelay = clampedIntFromText(
      _maxRetryDelayController.text,
      fallback: kCronDefaultRetryDelaySeconds,
      min: kCronMinRetryDelaySeconds,
      max: kCronMaxRetryDelaySeconds,
    );

    final tags = splitTrimmedNonEmpty(_tagsController.text);
    final env = keyValueMapFromValue(_envController.text);

    final entry = CronEntry(
      id: widget.existing?.id ?? _uuid.v4(),
      name: name,
      description: _descriptionController.text.trim(),
      scriptType: _scriptType,
      scriptPath: _scriptType == CronScriptType.script
          ? _scriptPathController.text.trim()
          : null,
      scriptContent: _scriptType == CronScriptType.command
          ? _scriptContentController.text
          : null,
      cronExpression: cronExpr,
      retryCount: retryCount,
      timeoutSeconds: timeout,
      runAsUser: _runAsUser,
      tags: tags,
      enabled: _enabled,
      status: widget.existing?.status ?? CronJobStatus.idle,
      onSuccessNotify: _onSuccessNotify,
      onFailureNotify: _onFailureNotify,
      onTimeoutNotify: _onTimeoutNotify,
      onSuccessSeverity: _onSuccessSeverity,
      onFailureSeverity: _onFailureSeverity,
      onTimeoutSeverity: _onTimeoutSeverity,
      onSuccessPlaySound: _onSuccessSound,
      onFailurePlaySound: _onFailureSound,
      onTimeoutPlaySound: _onTimeoutSound,
      onSuccessVibrate: _onSuccessVibration,
      onFailureVibrate: _onFailureVibration,
      onTimeoutVibrate: _onTimeoutVibration,
      onSuccessMessage: nullIfBlank(_onSuccessMsgController.text),
      onFailureMessage: nullIfBlank(_onFailureMsgController.text),
      onTimeoutMessage: nullIfBlank(_onTimeoutMsgController.text),
      collectAppMetadata: _collectAppMetadata,
      collectHostMetadata: _collectHostMetadata,
      collectEnvironmentSnapshot: _collectEnvironmentSnapshot,
      workingDirectory: nullIfBlank(_workingDirController.text),
      environment: env,
      maxRetryDelaySeconds: maxRetryDelay,
    );

    setState(() => _saving = true);
    try {
      final controller = context.read<CronsController>();
      final saved = _isEditing
          ? await controller.updateCron(entry)
          : await controller.addCron(entry);
      if (!mounted) return;
      if (saved) {
        Navigator.of(context).pop();
      } else {
        setState(() {
          _formError =
              controller.errorMessage ?? l10n.settingsPersistenceSaveFailedBody;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _validateForm(String name) {
    if (name.isEmpty) {
      return l10n.cronsValidationNameRequired;
    }
    if (_scriptType == CronScriptType.script &&
        nullIfBlank(_scriptPathController.text) == null) {
      return l10n.cronsValidationScriptRequired;
    }
    if (_scriptType == CronScriptType.command &&
        nullIfBlank(_scriptContentController.text) == null) {
      return l10n.cronsValidationCommandRequired;
    }
    final invalidEnvLines = invalidKeyValueLineNumbersFromText(
      _envController.text,
    );
    if (invalidEnvLines.isNotEmpty) {
      final lines = invalidEnvLines.join(', ');
      return l10n.cronsValidationInvalidEnvironment(lines);
    }
    return null;
  }

  Future<void> _testNotification(_NotificationTestScenario scenario) async {
    final generation = ++_notificationTestGeneration;
    final strings = l10n;
    if (scenario == _NotificationTestScenario.all) {
      await _testAllNotificationsSequentially(strings, generation);
      return;
    }
    await _testSingleNotification(scenario, strings, generation);
  }

  bool _isNotificationTestActive(int generation) =>
      mounted && generation == _notificationTestGeneration;

  Future<void> _testAllNotificationsSequentially(
    AppLocalizations strings,
    int generation,
  ) async {
    final scenarios = <_NotificationTestScenario>[
      _NotificationTestScenario.success,
      _NotificationTestScenario.failure,
      _NotificationTestScenario.timeout,
    ];
    final configs = <_NotificationTestConfig>[
      for (final scenario in scenarios)
        _resolveTestNotificationConfig(scenario, strings),
    ];

    final hasUnsupportedVibration =
        !OpenHandNotificationService.supportsVibration &&
        configs.any((config) => config.vibrationEnabled);

    await OpenHandNotificationService.showInApp(
      title: strings.cronsNotificationSequentialStartTitle,
      body: strings.cronsNotificationSequentialStartBody,
    );
    if (!_isNotificationTestActive(generation)) return;

    for (var i = 0; i < configs.length; i++) {
      await _emitTestNotification(
        configs[i],
        strings,
        generation,
        showVibrationFallbackHint: false,
      );
      if (!_isNotificationTestActive(generation)) return;
      if (i < configs.length - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 520));
        if (!_isNotificationTestActive(generation)) return;
      }
    }

    if (hasUnsupportedVibration) {
      await OpenHandNotificationService.showInApp(
        title: strings.cronsNotificationVibrationIgnoredTitle,
        body: strings.cronsNotificationSequentialVibrationIgnoredBody,
      );
      if (!_isNotificationTestActive(generation)) return;
    }

    await OpenHandNotificationService.showInApp(
      title: strings.cronsNotificationSequentialCompletedTitle,
      body: strings.cronsNotificationSequentialCompletedBody,
      level: OpenHandNotificationLevel.success,
    );
  }

  Future<void> _testSingleNotification(
    _NotificationTestScenario scenario,
    AppLocalizations strings,
    int generation,
  ) {
    return _emitTestNotification(
      _resolveTestNotificationConfig(scenario, strings),
      strings,
      generation,
    );
  }

  Future<void> _emitTestNotification(
    _NotificationTestConfig config,
    AppLocalizations strings,
    int generation, {
    bool showVibrationFallbackHint = true,
  }) async {
    if (!_isNotificationTestActive(generation)) return;
    final title = strings.cronsNotificationTestTitle(config.label);
    final body = nullIfBlank(config.message) ?? config.defaultBody;

    if (config.type == CronNotifyType.none ||
        config.type == CronNotifyType.log) {
      await OpenHandNotificationService.showInApp(
        title: title,
        body: strings.cronsNotificationNoEmitBody,
        level: OpenHandNotificationLevel.warning,
      );
      return;
    }

    final level = config.severity.notificationLevel;
    if (config.type == CronNotifyType.system) {
      final shown = await OpenHandNotificationService.showSystem(
        title: title,
        body: body,
        level: level,
        playSound: config.soundEnabled,
        vibrate: config.vibrationEnabled,
      );
      if (!_isNotificationTestActive(generation)) return;
      if (!shown) {
        await OpenHandNotificationService.showInApp(
          title: strings.cronsSystemNotificationUnavailableTitle,
          body: strings.cronsSystemNotificationFallbackBody,
          level: OpenHandNotificationLevel.warning,
          playSound: config.soundEnabled,
          vibrate: config.vibrationEnabled,
        );
      }
    } else {
      await OpenHandNotificationService.showInApp(
        title: title,
        body: body,
        level: level,
        playSound: config.soundEnabled,
        vibrate: config.vibrationEnabled,
      );
    }
    if (!_isNotificationTestActive(generation)) return;

    if (showVibrationFallbackHint &&
        config.vibrationEnabled &&
        !OpenHandNotificationService.supportsVibration) {
      await OpenHandNotificationService.showInApp(
        title: strings.cronsNotificationVibrationIgnoredTitle,
        body: strings.cronsNotificationVibrationIgnoredBody,
      );
    }
  }

  _NotificationTestConfig _resolveTestNotificationConfig(
    _NotificationTestScenario scenario,
    AppLocalizations strings,
  ) {
    return switch (scenario) {
      _NotificationTestScenario.success => (
        type: _onSuccessNotify,
        severity: _onSuccessSeverity,
        soundEnabled: _onSuccessSound,
        vibrationEnabled: _onSuccessVibration,
        message: _onSuccessMsgController.text,
        label: strings.cronsNotificationScenarioSuccess,
        defaultBody: strings.cronsNotificationTestDefaultBodySuccess,
      ),
      _NotificationTestScenario.failure => (
        type: _onFailureNotify,
        severity: _onFailureSeverity,
        soundEnabled: _onFailureSound,
        vibrationEnabled: _onFailureVibration,
        message: _onFailureMsgController.text,
        label: strings.cronsNotificationScenarioFailure,
        defaultBody: strings.cronsNotificationTestDefaultBodyFailure,
      ),
      _NotificationTestScenario.timeout => (
        type: _onTimeoutNotify,
        severity: _onTimeoutSeverity,
        soundEnabled: _onTimeoutSound,
        vibrationEnabled: _onTimeoutVibration,
        message: _onTimeoutMsgController.text,
        label: strings.cronsNotificationScenarioTimeout,
        defaultBody: strings.cronsNotificationTestDefaultBodyTimeout,
      ),
      _NotificationTestScenario.all => (
        type: _onFailureNotify,
        severity: _onFailureSeverity,
        soundEnabled: _onFailureSound,
        vibrationEnabled: _onFailureVibration,
        message: _onFailureMsgController.text,
        label: strings.cronsNotificationScenarioAll,
        defaultBody: strings.cronsNotificationTestDefaultBodyFailure,
      ),
    };
  }

  bool get _supportsSoundAlert {
    return Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isLinux ||
        Platform.isWindows;
  }

  String get _platformLabel {
    if (Platform.isMacOS) {
      return 'macOS';
    }
    if (Platform.isWindows) {
      return 'Windows';
    }
    if (Platform.isLinux) {
      return 'Linux';
    }
    if (Platform.isAndroid) {
      return 'Android';
    }
    if (Platform.isIOS) {
      return 'iOS';
    }
    return l10n.cronsUnknownPlatform;
  }

  String _soundSupportTooltip(bool enabled) {
    final state = enabled ? l10n.cronsToggleOn : l10n.cronsToggleOff;
    final support = _supportsSoundAlert;

    if (support) {
      final detail = isDesktopPlatform()
          ? l10n.cronsSupportBestEffortSystemSound
          : l10n.cronsSupportSupported;
      return _capabilityTooltip(
        label: l10n.cronsSoundLabel,
        state: state,
        platform: _platformLabel,
        support: detail,
      );
    }

    return _capabilityTooltip(
      label: l10n.cronsSoundLabel,
      state: state,
      platform: _platformLabel,
      support: l10n.cronsSupportNotSupportedOnPlatform,
    );
  }

  String _vibrationSupportTooltip(bool enabled) {
    final state = enabled ? l10n.cronsToggleOn : l10n.cronsToggleOff;
    final supported = OpenHandNotificationService.supportsVibration;

    return _capabilityTooltip(
      label: l10n.cronsVibrationLabel,
      state: state,
      platform: _platformLabel,
      support: supported
          ? l10n.cronsSupportSupported
          : l10n.cronsSupportNotSupportedWillBeIgnored,
    );
  }

  String _capabilityTooltip({
    required String label,
    required String state,
    required String platform,
    required String support,
  }) {
    return '$label: $state\n'
        '${l10n.cronsPlatformLabel}: $platform\n'
        '${l10n.cronsSupportLabel}: $support';
  }

  Widget _contextCollectTile({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool isSensitive = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final baseColor = value
        ? Color.alphaBlend(
            colorScheme.primary.withValues(alpha: 0.08),
            colorScheme.surfaceContainerHighest,
          )
        : colorScheme.surface;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(kOpenHandRadius20),
          onTap: () => onChanged(!value),
          child: AnimatedContainer(
            duration: openHandMotionDuration(context, kOpenHandMotion180),
            curve: kOpenHandSwitchInCurve,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: baseColor,
              borderRadius: BorderRadius.circular(kOpenHandRadius20),
              border: Border.all(
                color: value
                    ? colorScheme.primary.withValues(alpha: 0.6)
                    : colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: value
                        ? colorScheme.primaryContainer
                        : colorScheme.surfaceContainerHigh,
                    borderRadius: kOpenHandBorderRadius12,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    icon,
                    size: 18,
                    color: value
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                kOpenHandHGap10,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              label,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          if (isSensitive)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.tertiaryContainer,
                                borderRadius: kOpenHandPillBorderRadius,
                              ),
                              child: Text(
                                l10n.cronsSensitive,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onTertiaryContainer,
                                ),
                              ),
                            ),
                        ],
                      ),
                      kOpenHandGap2,
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                kOpenHandHGap6,
                Switch(
                  value: value,
                  onChanged: onChanged,
                  thumbIcon: WidgetStateProperty.resolveWith<Icon?>((states) {
                    if (states.contains(WidgetState.selected)) {
                      return const Icon(Icons.check_rounded, size: 14);
                    }
                    return null;
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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

    return buildOpenHandAlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(l10n.cronsExecutionHistoryTitle)),
          if (history.isNotEmpty)
            Tooltip(
              message: l10n.cronsClearAllExecutionHistory,
              child: IconButton(
                icon: Icon(
                  Icons.delete_sweep_outlined,
                  color: colorScheme.error,
                ),
                onPressed: () => _confirmClearAll(context, controller, l10n),
              ),
            ),
        ],
      ),
      content: OpenHandRemovableListScope(
        builder: (context, removal) => SizedBox(
          width: kOpenHandDialogWidthStandard,
          height: 480,
          child: history.isEmpty
              ? Center(
                  child: Text(
                    l10n.cronsNoExecutionRecords,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
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
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            decoration: BoxDecoration(
                              color: colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(
                                kOpenHandRadius16,
                              ),
                            ),
                            child: Icon(
                              Icons.delete_outline_rounded,
                              color: colorScheme.onErrorContainer,
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
      actions: [
        OpenHandDialogActionButton.secondary(
          label: l10n.commonClose,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
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
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    kOpenHandHGap10,
                    Text(
                      statusLabel,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    kOpenHandHGap12,
                    Text(
                      formatYearMonthDayHms(record.startedAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${record.elapsedMs}ms',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontFamily: kOpenHandMonospaceFontFamily,
                      ),
                    ),
                    kOpenHandHGap12,
                    if (record.exitCode != null)
                      Text(
                        'exit: ${record.exitCode}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontFamily: kOpenHandMonospaceFontFamily,
                        ),
                      ),
                    kOpenHandHGap8,
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: record.triggerType == 'manual'
                            ? colorScheme.tertiaryContainer
                            : colorScheme.surfaceContainerHigh,
                        borderRadius: kOpenHandBorderRadius8,
                      ),
                      child: Text(
                        record.triggerType == 'manual'
                            ? l10n.cronsTriggerManual
                            : l10n.cronsTriggerScheduled,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 9,
                          color: record.triggerType == 'manual'
                              ? colorScheme.onTertiaryContainer
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    kOpenHandHGap8,
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        size: 16,
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.6,
                        ),
                      ),
                      iconSize: 16,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      tooltip: l10n.cronsDeleteThisRecord,
                      onPressed: widget.onDelete,
                    ),
                    kOpenHandHGap4,
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0.0,
                      duration: _expanded
                          ? (_animController.duration ?? Duration.zero)
                          : (_animController.reverseDuration ?? Duration.zero),
                      curve: _expanded
                          ? _fadeAnimation.curve
                          : (_fadeAnimation.reverseCurve ??
                                _fadeAnimation.curve),
                      child: Icon(
                        Icons.expand_more_rounded,
                        size: 18,
                        color: colorScheme.onSurfaceVariant,
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
                        accentColor: statusColor,
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
    required Color accentColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor.withValues(alpha: 0.10),
            colorScheme.surfaceContainerLow.withValues(alpha: 0.66),
          ],
        ),
        borderRadius: kOpenHandBorderRadius14,
        border: Border.all(color: accentColor.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (record.retryAttempt > 0)
            _detailRow(
              l10n.cronsRetryAttempt,
              '${record.retryAttempt}',
              theme,
              colorScheme,
            ),
          if (record.pid != null)
            _detailRow('PID', '${record.pid}', theme, colorScheme),
          if (record.runAsUser != null)
            _detailRow(l10n.cronsRunAs, record.runAsUser!, theme, colorScheme),
          if (record.workingDirectory != null)
            _detailRow(
              l10n.cronsWorkingDir,
              record.workingDirectory!,
              theme,
              colorScheme,
            ),
          if (record.environment.isNotEmpty) ...[
            kOpenHandGap4,
            Text(
              l10n.cronsScriptEnvironmentOverrides,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            kOpenHandGap2,
            ...record.environment.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  '${e.key}=${e.value}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
          if (record.appContext.isNotEmpty) ...[
            // 结构化报告使用专用面板，并从原始上下文隐藏已消费字段。
            if (record.appContext.containsKey(
                  CronsController.hermesTalkerReportsKey,
                ) ||
                record.appContext.containsKey(
                  CronsController.hermesTalkerStatsKey,
                )) ...[
              kOpenHandGap8,
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
            kOpenHandGap8,
            _kvSection(
              title: l10n.cronsEnvironmentSnapshot,
              data: record.environmentSnapshot,
              theme: theme,
              colorScheme: colorScheme,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
          if (record.errorMessage != null &&
              record.errorMessage!.isNotEmpty) ...[
            kOpenHandGap8,
            Text(
              l10n.cronsErrorReason,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
            kOpenHandGap2,
            SelectableText(
              record.errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.error,
                fontFamily: kOpenHandMonospaceFontFamily,
                fontSize: 11,
              ),
            ),
          ],
          if (record.stdout.isNotEmpty) ...[
            kOpenHandGap8,
            Text(
              l10n.cronsStdout,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            kOpenHandGap2,
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 200),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.58),
                borderRadius: kOpenHandBorderRadius10,
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              child: SingleChildScrollView(
                child: ansiText(
                  record.stdout,
                  colorScheme: colorScheme,
                  base: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    fontSize: 11,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ],
          if (record.stderr.isNotEmpty) ...[
            kOpenHandGap8,
            Text(
              l10n.cronsStderr,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
            kOpenHandGap2,
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 200),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.22),
                borderRadius: kOpenHandBorderRadius10,
                border: Border.all(
                  color: colorScheme.error.withValues(alpha: 0.32),
                ),
              ),
              child: SingleChildScrollView(
                child: ansiText(
                  record.stderr,
                  colorScheme: colorScheme,
                  base: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    fontSize: 11,
                    color: colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detailRow(
    String label,
    String value,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: kOpenHandMonospaceFontFamily,
                fontSize: 11,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
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
      kOpenHandGap8,
      _kvSection(
        title: l10n.cronsExecutionContext,
        data: filtered,
        theme: theme,
        colorScheme: colorScheme,
        color: colorScheme.onSurfaceVariant,
      ),
    ];
  }

  Widget _kvSection({
    required String title,
    required Map<String, String> data,
    required ThemeData theme,
    required ColorScheme colorScheme,
    required Color color,
  }) {
    final sortedKeys = data.keys.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
        kOpenHandGap4,
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 160),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.surface.withValues(alpha: 0.55),
            borderRadius: kOpenHandBorderRadius10,
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: sortedKeys.map((k) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: SelectableText(
                    '$k=${data[k] ?? ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: kOpenHandMonospaceFontFamily,
                      fontSize: 11,
                      color: colorScheme.onSurface,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
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
      final parsed = jsonDecode(raw);
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
      final parsed = jsonDecode(raw);
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
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow.withValues(alpha: 0.85),
            borderRadius: kOpenHandBorderRadius14,
            border: Border.all(color: accent.withValues(alpha: 0.22)),
          ),
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
    final fallback = _jsonFallback(change);

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
    return _jsonFallback(value);
  }

  String _jsonFallback(Object? value) {
    try {
      return jsonEncode(value);
    } catch (_) {
      return '$value';
    }
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
