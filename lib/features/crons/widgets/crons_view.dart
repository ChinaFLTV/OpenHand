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
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../crons_controller.dart';
import '../model/cron_parser.dart';

const int _cronTagPreviewLimit = 6;

class CronsView extends StatelessWidget {
  const CronsView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final entries = context.select<CronsController, List<CronEntry>>(
      (controller) => controller.entries,
    );
    final isLoading = context.select<CronsController, bool>(
      (controller) => controller.isLoading,
    );
    final controller = context.read<CronsController>();
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.settingsCrons, style: theme.textTheme.displaySmall),
                  const SizedBox(height: 8),
                  Text(
                    l10n.cronsViewDescription,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            FilledButton.icon(
              onPressed: () => _showCronEditorDialog(context, null),
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.cronsNewCronJob),
            ),
          ],
        ),
        const SizedBox(height: 24),
        // Content — three states fade across smoothly so the list does not
        // pop when entries arrive or are removed.
        Expanded(
          child: AnimatedSwitcher(
            duration: openHandMotionDuration(
              context,
              const Duration(milliseconds: 220),
            ),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: (isLoading && entries.isEmpty)
                ? const Center(
                    key: ValueKey<String>('loading'),
                    child: CircularProgressIndicator(),
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
                    child: ListView.separated(
                      // 顶部 2px 缓冲，避免滚动到顶时第一张卡的描边被视口剪掉。
                      padding: const EdgeInsets.only(top: 2),
                      itemCount: entries.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return AppearOnce(
                          key: ValueKey<String>('cron-entry-${entry.id}'),
                          child: _CronEntryCard(
                            entry: entry,
                            onEdit: () => _showCronEditorDialog(context, entry),
                            onToggle: (enabled) {
                              controller.toggleCronEnabled(
                                entry.id,
                                enabled: enabled,
                              );
                            },
                            onDelete: () => _confirmDelete(context, entry),
                            onHistory: () => _showHistoryDialog(context, entry),
                            onRunNow: () => controller.runNow(entry.id),
                          ),
                        );
                      },
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

  Future<void> _confirmDelete(BuildContext context, CronEntry entry) async {
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
    context.read<CronsController>().deleteCron(entry.id);
  }
}

// Empty state
class _CronEmptyState extends StatelessWidget {
  const _CronEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Expanded(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.schedule_outlined,
              size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.cronsEmptyTitle,
              style: theme.textTheme.titleLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.cronsEmptyBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Cron entry card
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
                // Status dot
                _CronStatusDot(status: entry.status, enabled: entry.enabled),
                const SizedBox(width: 12),
                // Name & description
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
                        const SizedBox(height: 2),
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
                const SizedBox(width: 12),
                // Cron expression badge
                Tooltip(
                  message: l10n.cronsCronExpressionTooltip,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      entry.cronExpression,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onTertiaryContainer,
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Timeout badge
                Tooltip(
                  message: l10n.cronsTimeoutTooltip,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${entry.timeoutSeconds}s',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Retry badge
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
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.replay_rounded,
                            size: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
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
                  const SizedBox(width: 8),
                ],
                // Toggle switch
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
                const SizedBox(width: 8),
                // 2026-04-25 — system entries (e.g. Hermes Talker self-
                // learning) no longer show a lock icon. Toggle stays
                // enabled, but edit/delete remain disabled below to keep
                // the cron parameters immutable.
                // Actions
                IconButton(
                  icon: const Icon(Icons.bolt_rounded, size: 20),
                  tooltip: l10n.cronsRunOnceNow,
                  onPressed: entry.enabled ? onRunNow : null,
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.history_rounded, size: 20),
                  tooltip: l10n.cronsHistory,
                  onPressed: onHistory,
                ),
                const SizedBox(width: 4),
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
                const SizedBox(width: 4),
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
            // Tags & status row
            if (entry.tags.isNotEmpty || entry.lastRunAt != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  // Tags
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
                                borderRadius: BorderRadius.circular(10),
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
                                borderRadius: BorderRadius.circular(10),
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
                  // Status chip
                  _CronStatusChip(entry: entry),
                  if (entry.lastRunAt != null) ...[
                    const SizedBox(width: 8),
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

// Status dot (like MCP health dot)
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
            CronJobStatus.running => const Color(0xFF56C271),
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

// Status chip
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
      CronJobStatus.running => const Color(0xFF56C271).withValues(alpha: 0.15),
      CronJobStatus.idle => colorScheme.surfaceContainerHigh,
      CronJobStatus.paused => colorScheme.tertiaryContainer,
      CronJobStatus.failed => colorScheme.errorContainer,
      CronJobStatus.error => colorScheme.errorContainer,
    };
    final fgColor = switch (entry.status) {
      CronJobStatus.running => const Color(0xFF56C271),
      CronJobStatus.idle => colorScheme.onSurfaceVariant,
      CronJobStatus.paused => colorScheme.onTertiaryContainer,
      CronJobStatus.failed => colorScheme.onErrorContainer,
      CronJobStatus.error => colorScheme.onErrorContainer,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
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

// Cron editor dialog
class _CronEditorDialog extends StatefulWidget {
  const _CronEditorDialog({this.existing});

  final CronEntry? existing;

  @override
  State<_CronEditorDialog> createState() => _CronEditorDialogState();
}

enum _NotificationTestScenario { success, failure, timeout, all }

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

  // Cron expression fields (5 fields: min hour dom mon dow)
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

  String? _cronError;
  String? _formError;

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

    final cronParts = (e?.cronExpression ?? '* * * * *').split(RegExp(r'\s+'));
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
              if (_formError != null) const SizedBox(height: 12),
              // Name
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: l10n.cronsFieldName,
                  hintText: l10n.cronsFieldNameHint,
                ),
              ),
              const SizedBox(height: 14),
              // Description
              TextField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: l10n.cronsFieldDescription,
                  hintText: l10n.commonOptional,
                ),
              ),
              const SizedBox(height: 18),
              // Script type toggle
              Text(l10n.cronsFieldType, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
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
              const SizedBox(height: 14),
              // Script source
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
                    const SizedBox(width: 8),
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
                    fontFamily: 'monospace',
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
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              // Cron expression
              Text(l10n.cronsCronSchedule, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
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
                            fontFamily: 'monospace',
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.4,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _cronField(_cronMinController, l10n.cronParserFieldMinute),
                  const SizedBox(width: 6),
                  _cronField(_cronHourController, l10n.cronParserFieldHour),
                  const SizedBox(width: 6),
                  _cronField(
                    _cronDomController,
                    l10n.cronParserFieldDayOfMonthShort,
                  ),
                  const SizedBox(width: 6),
                  _cronField(_cronMonController, l10n.cronParserFieldMonth),
                  const SizedBox(width: 6),
                  _cronField(
                    _cronDowController,
                    l10n.cronParserFieldDayOfWeekShort,
                  ),
                ],
              ),
              if (_cronError != null) ...[
                const SizedBox(height: 4),
                Text(
                  _cronError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                l10n.cronsCronScheduleHelper,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 18),
              // Timeout & Retry row
              Row(
                children: [
                  Text(
                    l10n.cronsTimeoutSeconds,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(width: 8),
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
                  const SizedBox(width: 24),
                  Text(l10n.cronsRetries, style: theme.textTheme.titleSmall),
                  const SizedBox(width: 8),
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
                  const SizedBox(width: 24),
                  Text(
                    l10n.cronsMaxRetryDelaySeconds,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(width: 8),
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
              const SizedBox(height: 18),
              // Run as user
              Text(l10n.cronsRunAsUser, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
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
              const SizedBox(height: 18),
              // Tags
              TextField(
                controller: _tagsController,
                decoration: InputDecoration(
                  labelText: l10n.cronsTagsCommaSeparated,
                  hintText: l10n.cronsTagsHint,
                ),
              ),
              const SizedBox(height: 18),
              // Working directory
              TextField(
                controller: _workingDirController,
                decoration: InputDecoration(
                  labelText: l10n.cronsWorkingDirectory,
                  hintText: l10n.cronsWorkingDirectoryHint,
                ),
              ),
              const SizedBox(height: 18),
              // Environment variables
              TextField(
                controller: _envController,
                maxLines: 3,
                minLines: 2,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
                decoration: InputDecoration(
                  labelText: l10n.cronsEnvironmentVariables,
                  hintText: l10n.cronsEnvironmentVariablesHint,
                  contentPadding: const EdgeInsets.all(12),
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                l10n.cronsExecutionContextCollection,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(24),
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
              const SizedBox(height: 18),
              // Notification settings
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
                        borderRadius: BorderRadius.circular(22),
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
                          const SizedBox(width: 6),
                          Text(
                            l10n.cronsTestNotification,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 4),
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
              const SizedBox(height: 4),
              Text(
                l10n.cronsNotificationSettingsHelper,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
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
              const SizedBox(height: 8),
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
              const SizedBox(height: 8),
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
              const SizedBox(height: 14),
              // Enabled switch
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
          onPressed: () => Navigator.of(context).pop(),
        ),
        OpenHandDialogActionButton.primary(
          label: l10n.commonSave,
          onPressed: _save,
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
                fontFamily: 'monospace',
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
          const SizedBox(height: 2),
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
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Event label
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            // Channel + severity dropdowns + sound/vibration toggles
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
                const SizedBox(width: 8),
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
                const SizedBox(width: 8),
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
                const SizedBox(width: 4),
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
            const SizedBox(height: 10),
            // Custom message
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
              const SizedBox(height: 6),
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

  void _save() {
    final name = _nameController.text.trim();
    final validationError = _validateForm(name);
    if (validationError != null) {
      setState(() => _formError = validationError);
      return;
    }

    // Validate cron expression.
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

    final controller = context.read<CronsController>();
    if (_isEditing) {
      controller.updateCron(entry);
    } else {
      controller.addCron(entry);
    }
    Navigator.of(context).pop();
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
    if (scenario == _NotificationTestScenario.all) {
      await _testAllNotificationsSequentially();
      return;
    }
    await _testSingleNotification(scenario);
  }

  Future<void> _testAllNotificationsSequentially() async {
    final scenarios = <_NotificationTestScenario>[
      _NotificationTestScenario.success,
      _NotificationTestScenario.failure,
      _NotificationTestScenario.timeout,
    ];

    final hasUnsupportedVibration =
        !OpenHandNotificationService.supportsVibration &&
        scenarios
            .map(_resolveTestNotificationConfig)
            .any((cfg) => cfg.vibrationEnabled);

    await OpenHandNotificationService.showInApp(
      title: l10n.cronsNotificationSequentialStartTitle,
      body: l10n.cronsNotificationSequentialStartBody,
    );

    for (var i = 0; i < scenarios.length; i++) {
      await _testSingleNotification(
        scenarios[i],
        showVibrationFallbackHint: false,
      );
      if (i < scenarios.length - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 520));
      }
    }

    if (hasUnsupportedVibration) {
      await OpenHandNotificationService.showInApp(
        title: l10n.cronsNotificationVibrationIgnoredTitle,
        body: l10n.cronsNotificationSequentialVibrationIgnoredBody,
      );
    }

    await OpenHandNotificationService.showInApp(
      title: l10n.cronsNotificationSequentialCompletedTitle,
      body: l10n.cronsNotificationSequentialCompletedBody,
      level: OpenHandNotificationLevel.success,
    );
  }

  Future<void> _testSingleNotification(
    _NotificationTestScenario scenario, {
    bool showVibrationFallbackHint = true,
  }) async {
    final config = _resolveTestNotificationConfig(scenario);
    final title = l10n.cronsNotificationTestTitle(config.label);
    final defaultBody = config.defaultBody;
    final body = nullIfBlank(config.messageController.text) ?? defaultBody;

    if (config.type == CronNotifyType.none ||
        config.type == CronNotifyType.log) {
      await OpenHandNotificationService.showInApp(
        title: title,
        body: l10n.cronsNotificationNoEmitBody,
        level: OpenHandNotificationLevel.warning,
      );
      return;
    }

    final level = _mapSeverity(config.severity);
    if (config.type == CronNotifyType.system) {
      final shown = await OpenHandNotificationService.showSystem(
        title: title,
        body: body,
        level: level,
        playSound: config.soundEnabled,
        vibrate: config.vibrationEnabled,
      );
      if (!shown) {
        await OpenHandNotificationService.showInApp(
          title: l10n.cronsSystemNotificationUnavailableTitle,
          body: l10n.cronsSystemNotificationFallbackBody,
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

    if (showVibrationFallbackHint &&
        config.vibrationEnabled &&
        !OpenHandNotificationService.supportsVibration) {
      await OpenHandNotificationService.showInApp(
        title: l10n.cronsNotificationVibrationIgnoredTitle,
        body: l10n.cronsNotificationVibrationIgnoredBody,
      );
    }
  }

  ({
    CronNotifyType type,
    CronNotifySeverity severity,
    bool soundEnabled,
    bool vibrationEnabled,
    TextEditingController messageController,
    String label,
    String defaultBody,
  })
  _resolveTestNotificationConfig(_NotificationTestScenario scenario) {
    return switch (scenario) {
      _NotificationTestScenario.success => (
        type: _onSuccessNotify,
        severity: _onSuccessSeverity,
        soundEnabled: _onSuccessSound,
        vibrationEnabled: _onSuccessVibration,
        messageController: _onSuccessMsgController,
        label: l10n.cronsNotificationScenarioSuccess,
        defaultBody: l10n.cronsNotificationTestDefaultBodySuccess,
      ),
      _NotificationTestScenario.failure => (
        type: _onFailureNotify,
        severity: _onFailureSeverity,
        soundEnabled: _onFailureSound,
        vibrationEnabled: _onFailureVibration,
        messageController: _onFailureMsgController,
        label: l10n.cronsNotificationScenarioFailure,
        defaultBody: l10n.cronsNotificationTestDefaultBodyFailure,
      ),
      _NotificationTestScenario.timeout => (
        type: _onTimeoutNotify,
        severity: _onTimeoutSeverity,
        soundEnabled: _onTimeoutSound,
        vibrationEnabled: _onTimeoutVibration,
        messageController: _onTimeoutMsgController,
        label: l10n.cronsNotificationScenarioTimeout,
        defaultBody: l10n.cronsNotificationTestDefaultBodyTimeout,
      ),
      _NotificationTestScenario.all => (
        type: _onFailureNotify,
        severity: _onFailureSeverity,
        soundEnabled: _onFailureSound,
        vibrationEnabled: _onFailureVibration,
        messageController: _onFailureMsgController,
        label: l10n.cronsNotificationScenarioAll,
        defaultBody: l10n.cronsNotificationTestDefaultBodyFailure,
      ),
    };
  }

  OpenHandNotificationLevel _mapSeverity(CronNotifySeverity severity) {
    return switch (severity) {
      CronNotifySeverity.info => OpenHandNotificationLevel.info,
      CronNotifySeverity.success => OpenHandNotificationLevel.success,
      CronNotifySeverity.warning => OpenHandNotificationLevel.warning,
      CronNotifySeverity.error => OpenHandNotificationLevel.error,
      CronNotifySeverity.critical => OpenHandNotificationLevel.critical,
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
      final detail =
          (Platform.isMacOS || Platform.isLinux || Platform.isWindows)
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
          borderRadius: BorderRadius.circular(20),
          onTap: () => onChanged(!value),
          child: AnimatedContainer(
            duration: openHandMotionDuration(
              context,
              const Duration(milliseconds: 180),
            ),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: baseColor,
              borderRadius: BorderRadius.circular(20),
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
                    borderRadius: BorderRadius.circular(12),
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
                const SizedBox(width: 10),
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
                                borderRadius: BorderRadius.circular(999),
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
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
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

// Execution history dialog
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
      content: SizedBox(
        width: 720,
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
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                itemCount: history.length,
                itemBuilder: (context, index) {
                  final record = history[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Dismissible(
                      key: ValueKey(record.id),
                      direction: DismissDirection.endToStart,
                      confirmDismiss: (_) =>
                          _confirmDeleteRecord(context, l10n),
                      onDismissed: (_) {
                        controller.deleteHistoryRecord(entry.id, record.id);
                      },
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          color: colorScheme.onErrorContainer,
                        ),
                      ),
                      child: _HistoryRecordTile(
                        record: record,
                        onDelete: () {
                          controller.deleteHistoryRecord(entry.id, record.id);
                        },
                      ),
                    ),
                  );
                },
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
    controller.clearHistoryForCron(entry.id);
  }

  Future<bool> _confirmDeleteRecord(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    return showOpenHandConfirmDialog(
      context: context,
      title: l10n.cronsDeleteExecutionRecordTitle,
      message: l10n.cronsDeleteExecutionRecordMessage,
      cancelLabel: l10n.commonCancel,
      confirmLabel: l10n.commonDelete,
      destructive: true,
    );
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
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
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
      'success' => const Color(0xFF56C271),
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tileBorderColor),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _toggle,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Status dot
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Status label
                    Text(
                      statusLabel,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Time
                    Text(
                      formatYearMonthDayHms(record.startedAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    // Duration
                    Text(
                      '${record.elapsedMs}ms',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (record.exitCode != null)
                      Text(
                        'exit: ${record.exitCode}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontFamily: 'monospace',
                        ),
                      ),
                    const SizedBox(width: 8),
                    // Trigger type badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: record.triggerType == 'manual'
                            ? colorScheme.tertiaryContainer
                            : colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
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
                    const SizedBox(width: 8),
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
                    const SizedBox(width: 4),
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
                  axisAlignment: -1.0,
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
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Retry attempt
          if (record.retryAttempt > 0)
            _detailRow(
              l10n.cronsRetryAttempt,
              '${record.retryAttempt}',
              theme,
              colorScheme,
            ),
          // PID
          if (record.pid != null)
            _detailRow('PID', '${record.pid}', theme, colorScheme),
          // Run-as user
          if (record.runAsUser != null)
            _detailRow(l10n.cronsRunAs, record.runAsUser!, theme, colorScheme),
          // Working directory
          if (record.workingDirectory != null)
            _detailRow(
              l10n.cronsWorkingDir,
              record.workingDirectory!,
              theme,
              colorScheme,
            ),
          // Script environment overrides
          if (record.environment.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              l10n.cronsScriptEnvironmentOverrides,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            ...record.environment.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  '${e.key}=${e.value}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
          if (record.appContext.isNotEmpty) ...[
            // 2026-04-25: Prefer the Hermes Talker rich panel for structured
            // reports and hide the consumed JSON keys from the raw context
            // list, avoiding duplicate noisy payloads in the UI.
            if (record.appContext.containsKey(
                  CronsController.hermesTalkerReportsKey,
                ) ||
                record.appContext.containsKey(
                  CronsController.hermesTalkerStatsKey,
                )) ...[
              const SizedBox(height: 8),
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
            const SizedBox(height: 8),
            _kvSection(
              title: l10n.cronsEnvironmentSnapshot,
              data: record.environmentSnapshot,
              theme: theme,
              colorScheme: colorScheme,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
          // Error message
          if (record.errorMessage != null &&
              record.errorMessage!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              l10n.cronsErrorReason,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            SelectableText(
              record.errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.error,
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
          ],
          // Stdout
          if (record.stdout.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              l10n.cronsStdout,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 200),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.58),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              child: SingleChildScrollView(
                child: ansiText(
                  record.stdout,
                  colorScheme: colorScheme,
                  base: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ],
          // Stderr
          if (record.stderr.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              l10n.cronsStderr,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 200),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: colorScheme.error.withValues(alpha: 0.32),
                ),
              ),
              child: SingleChildScrollView(
                child: ansiText(
                  record.stderr,
                  colorScheme: colorScheme,
                  base: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
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
                fontFamily: 'monospace',
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
      const SizedBox(height: 8),
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
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 160),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.surface.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(10),
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
                      fontFamily: 'monospace',
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
/// 解析后的单个会话报告（与 SelfLearningSessionReport.toJson() 对齐）。
class _HermesTalkerSessionReport {
  const _HermesTalkerSessionReport({
    required this.sessionId,
    required this.sessionTitle,
    required this.status,
    required this.summary,
    required this.mutations,
    this.aiResponse,
    this.aiReasoning,
    this.error,
  });

  factory _HermesTalkerSessionReport.fromJson(Map<String, Object?> json) {
    Map<String, Object?> readMap(Object? value) {
      if (value is Map<String, Object?>) return value;
      if (value is Map) {
        return value.map((k, v) => MapEntry('$k', v));
      }
      return const <String, Object?>{};
    }

    return _HermesTalkerSessionReport(
      sessionId: '${json['session_id'] ?? ''}',
      sessionTitle: '${json['session_title'] ?? ''}',
      status: '${json['status'] ?? 'ok'}',
      summary: '${json['summary'] ?? ''}',
      mutations: readMap(json['mutations']),
      aiResponse: json['ai_response'] as String?,
      aiReasoning: json['ai_reasoning'] as String?,
      error: json['error'] as String?,
    );
  }

  final String sessionId;
  final String sessionTitle;
  final String status;
  final String summary;
  final Map<String, Object?> mutations;
  final String? aiResponse;
  final String? aiReasoning;
  final String? error;

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
        borderRadius: BorderRadius.circular(18),
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
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.auto_awesome,
                  size: 18,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 10),
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
            const SizedBox(height: 10),
            Text(
              l10n.cronsHermesAffectedSessions(reports.length),
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
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

  List<_HermesTalkerSessionReport> _decodeReports() {
    final raw = appContext[CronsController.hermesTalkerReportsKey];
    if (raw == null || raw.isEmpty) return const <_HermesTalkerSessionReport>[];
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! List) return const <_HermesTalkerSessionReport>[];
      final out = <_HermesTalkerSessionReport>[];
      for (final item in parsed) {
        if (item is Map) {
          out.add(
            _HermesTalkerSessionReport.fromJson(stringKeyedMapFromValue(item)),
          );
        }
      }
      return out;
    } catch (error, stack) {
      silentLog('crons_view', 'decode hermes talker reports', error, stack);
      return const <_HermesTalkerSessionReport>[];
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
      silentLog('crons_view', 'decode hermes talker stats', error, stack);
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

  final _HermesTalkerSessionReport report;

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
              fontFamily: 'monospace',
            ),
          ),
        ),
    ];

    final hasExpandableBody = children.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Theme(
        // ExpansionTile 默认会插入 Divider，关闭它以贴合 Material You 视感。
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(14),
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
        break;
      case 'skipped':
        bg = colorScheme.surfaceContainerHighest;
        fg = colorScheme.onSurfaceVariant;
        icon = Icons.skip_next_rounded;
        label = l10n.cronsHermesStatusSkipped;
        break;
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
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: foreground),
          const SizedBox(width: 4),
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
          borderRadius: BorderRadius.circular(14),
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
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    size: 14,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$title (${changes.length})',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
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
          borderRadius: BorderRadius.circular(12),
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
              const SizedBox(height: 6),
              _hermesInlineMarkdown(
                data: heading,
                theme: theme,
                colorScheme: colorScheme,
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ],
            if (details.isNotEmpty) ...[
              const SizedBox(height: 6),
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
              const SizedBox(height: 6),
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
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: foreground),
          const SizedBox(width: 4),
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

  /// Bodies larger than this fall back to a plain selectable text view to
  /// keep the timeline list snappy — markdown parsing is O(n) and would
  /// otherwise stutter the UI when many history items are expanded.
  static const int _markdownByteLimit = 120 * 1024;

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
        : '${body.substring(0, _CollapsibleLongText._previewChars)}…';
    final l10n = AppLocalizations.of(context)!;

    final bodyTextColor = widget.subdued
        ? colorScheme.onSurfaceVariant
        : colorScheme.onSurface;
    final fallbackTextStyle = theme.textTheme.bodySmall?.copyWith(
      color: bodyTextColor,
      height: 1.4,
      fontStyle: widget.subdued ? FontStyle.italic : FontStyle.normal,
    );

    // Performance guard: oversized bodies skip markdown parsing entirely.
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
          borderRadius: BorderRadius.circular(12),
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
                const SizedBox(width: 6),
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
            const SizedBox(height: 4),
            bodyWidget,
          ],
        ),
      ),
    );
  }
}

/// Lightweight markdown stylesheet for cron history collapsible bodies.
/// Tuned for compact, in-card rendering: smaller fonts, dim accents, no
/// heavy block decorations that would fight the surrounding card.
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
    fontFamily: 'monospace',
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
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: colorScheme.outlineVariant.withValues(alpha: 0.35),
      ),
    ),
    blockquoteDecoration: BoxDecoration(
      color: colorScheme.surfaceContainer.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(6),
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

/// Inline markdown helper used for short Hermes Talker fields (summary,
/// change row heading, change detail lines). Falls back to a plain selectable
/// text on oversized payloads to keep the history list snappy.
Widget _hermesInlineMarkdown({
  required String data,
  required ThemeData theme,
  required ColorScheme colorScheme,
  required Color color,
  FontWeight? fontWeight,
  FontStyle? fontStyle,
  double height = 1.35,
}) {
  // Inline payloads are expected to be short (one line ~ a paragraph). Skip
  // markdown parsing entirely once they cross a few KB.
  const inlineByteLimit = 4 * 1024;
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
  final mono = base?.copyWith(fontFamily: 'monospace', fontSize: 11);
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
      borderRadius: BorderRadius.circular(6),
    ),
    blockquoteDecoration: BoxDecoration(
      color: colorScheme.surfaceContainer.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(6),
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
