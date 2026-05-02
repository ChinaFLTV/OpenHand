import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../app/model/cron_config.dart';
import '../../app/state/settings_controller.dart';
import '../../app/support/openhand_notification_service.dart';
import '../../app/support/silent_log.dart';
import '../../shared/widgets/animated_dialog.dart';
import '../../shared/widgets/ansi_text.dart';
import '../../shared/widgets/appear_once.dart';
import '../../shared/widgets/openhand_dialog_action_button.dart';
import 'cron_parser.dart';
import 'crons_controller.dart';

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
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');

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
                  Text('Crons', style: theme.textTheme.displaySmall),
                  const SizedBox(height: 8),
                  Text(
                    isZh
                        ? '配置和管理定时任务。支持 Cron 表达式调度、超时控制、自动重试和执行历史查看。'
                        : 'Configure and manage scheduled tasks. Supports cron expression scheduling, timeout control, auto-retry, and execution history.',
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
              label: Text(isZh ? '新增定时任务' : 'New Cron Job'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        // Content — three states fade across smoothly so the list does not
        // pop when entries arrive or are removed.
        Expanded(
          child: AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: (isLoading && entries.isEmpty)
                ? const Center(
                    key: ValueKey<String>('loading'),
                    child: CircularProgressIndicator(),
                  )
                : entries.isEmpty
                ? KeyedSubtree(
                    key: const ValueKey<String>('empty'),
                    child: _CronEmptyState(isZh: isZh),
                  )
                : ScrollConfiguration(
                    key: const ValueKey<String>('list'),
                    behavior: ScrollConfiguration.of(
                      context,
                    ).copyWith(scrollbars: false),
                    child: ListView.separated(
                      itemCount: entries.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return AppearOnce(
                          key: ValueKey<String>('cron-entry-${entry.id}'),
                          child: _CronEntryCard(
                            entry: entry,
                            isZh: isZh,
                            onEdit: () =>
                                _showCronEditorDialog(context, entry),
                            onToggle: (enabled) {
                              controller.toggleCronEnabled(
                                entry.id,
                                enabled: enabled,
                              );
                            },
                            onDelete: () => _confirmDelete(context, entry),
                            onHistory: () =>
                                _showHistoryDialog(context, entry),
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

  void _confirmDelete(BuildContext context, CronEntry entry) {
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    showAnimatedDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isZh ? '删除定时任务' : 'Delete Cron Job'),
        content: Text(
          isZh
              ? '确定删除 "${entry.name}" 吗？此操作不可撤销，执行历史也将一并删除。'
              : 'Delete "${entry.name}"? This cannot be undone. Execution history will also be removed.',
        ),
        actions: [
          OpenHandDialogActionButton.secondary(
            label: isZh ? '取消' : 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
          ),
          OpenHandDialogActionButton.primary(
            label: isZh ? '删除' : 'Delete',
            onPressed: () {
              context.read<CronsController>().deleteCron(entry.id);
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _CronEmptyState extends StatelessWidget {
  const _CronEmptyState({required this.isZh});

  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
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
              isZh ? '暂无定时任务' : 'No cron jobs configured yet',
              style: theme.textTheme.titleLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isZh
                  ? '点击右上角「新增定时任务」按钮开始配置。'
                  : 'Click "New Cron Job" above to get started.',
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

// ---------------------------------------------------------------------------
// Cron entry card
// ---------------------------------------------------------------------------

class _CronEntryCard extends StatelessWidget {
  const _CronEntryCard({
    required this.entry,
    required this.isZh,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
    required this.onHistory,
    required this.onRunNow,
  });

  final CronEntry entry;
  final bool isZh;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;
  final VoidCallback onHistory;
  final VoidCallback onRunNow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
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
                  message: isZh ? 'Cron 表达式' : 'Cron expression',
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
                  message: isZh ? '超时时间' : 'Timeout',
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
                    message: isZh ? '重试次数' : 'Retry count',
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
                Switch(value: entry.enabled, onChanged: onToggle),
                const SizedBox(width: 8),
                // 2026-04-25 — system entries (e.g. Hermes Talker self-
                // learning) no longer show a lock icon. Toggle stays
                // enabled, but edit/delete remain disabled below to keep
                // the cron parameters immutable.
                // Actions
                IconButton(
                  icon: const Icon(Icons.bolt_rounded, size: 20),
                  tooltip: isZh ? '立即执行一次' : 'Run once now',
                  onPressed: entry.enabled ? onRunNow : null,
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.history_rounded, size: 20),
                  tooltip: isZh ? '执行历史' : 'History',
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
                  tooltip: isZh ? '编辑' : 'Edit',
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
                  tooltip: isZh ? '删除' : 'Delete',
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
                  _CronStatusChip(entry: entry, isZh: isZh),
                  if (entry.lastRunAt != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      isZh
                          ? '上次: ${_formatTime(entry.lastRunAt!)}'
                          : 'Last: ${_formatTime(entry.lastRunAt!)}',
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

  String _formatTime(DateTime dt) {
    return '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }
}

// ---------------------------------------------------------------------------
// Status dot (like MCP health dot)
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Status chip
// ---------------------------------------------------------------------------

class _CronStatusChip extends StatelessWidget {
  const _CronStatusChip({required this.entry, required this.isZh});

  final CronEntry entry;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusLabel = entry.status.label(isZh);
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

// ---------------------------------------------------------------------------
// Cron editor dialog
// ---------------------------------------------------------------------------

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
      text: '${e?.timeoutSeconds ?? 60}',
    );
    _retryController = TextEditingController(text: '${e?.retryCount ?? 0}');
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
      text: '${e?.maxRetryDelaySeconds ?? 30}',
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
  bool get isZh =>
      Localizations.localeOf(context).languageCode.startsWith('zh');

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

    return AlertDialog(
      title: Text(
        _isEditing
            ? (isZh ? '编辑定时任务' : 'Edit Cron Job')
            : (isZh ? '新增定时任务' : 'New Cron Job'),
      ),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Name
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: isZh ? '任务名称' : 'Name',
                  hintText: isZh ? '例如: 每日备份' : 'e.g. Daily Backup',
                ),
              ),
              const SizedBox(height: 14),
              // Description
              TextField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: isZh ? '简介' : 'Description',
                  hintText: isZh ? '可选' : 'Optional',
                ),
              ),
              const SizedBox(height: 18),
              // Script type toggle
              Text(isZh ? '类型' : 'Type', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<CronScriptType>(
                segments: [
                  ButtonSegment(
                    value: CronScriptType.command,
                    icon: const Icon(Icons.terminal_rounded, size: 18),
                    label: Text(CronScriptType.command.label(isZh)),
                  ),
                  ButtonSegment(
                    value: CronScriptType.script,
                    icon: const Icon(Icons.description_outlined, size: 18),
                    label: Text(CronScriptType.script.label(isZh)),
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
                          labelText: isZh ? '脚本文件路径' : 'Script File Path',
                          hintText: isZh
                              ? '选择 .sh / .ps1 / .bat 文件'
                              : 'Select a .sh / .ps1 / .bat file',
                        ),
                        readOnly: true,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: _pickScriptFile,
                      child: Text(isZh ? '浏览' : 'Browse'),
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
                    labelText: isZh ? '命令内容' : 'Command',
                    hintText: Platform.isWindows
                        ? (isZh
                              ? '输入 PowerShell / BAT 命令'
                              : 'Enter PowerShell / BAT command')
                        : (isZh ? '输入 Shell 命令' : 'Enter shell command'),
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
              Text(
                isZh ? 'Cron 时间表达式' : 'Cron Schedule',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  // Frozen seconds field
                  SizedBox(
                    width: 56,
                    child: TextField(
                      readOnly: true,
                      enabled: false,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 8,
                        ),
                        hintText: '0',
                      ),
                      controller: TextEditingController(text: '0'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFamily: 'monospace',
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _cronField(_cronMinController, isZh ? '分' : 'Min'),
                  const SizedBox(width: 6),
                  _cronField(_cronHourController, isZh ? '时' : 'Hour'),
                  const SizedBox(width: 6),
                  _cronField(_cronDomController, isZh ? '日' : 'DoM'),
                  const SizedBox(width: 6),
                  _cronField(_cronMonController, isZh ? '月' : 'Mon'),
                  const SizedBox(width: 6),
                  _cronField(_cronDowController, isZh ? '周' : 'DoW'),
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
                isZh
                    ? '秒字段已冻结为 0，最小粒度为分钟。格式: 分 时 日 月 周'
                    : 'Seconds field frozen at 0. Min granularity: minute. Format: min hour dom mon dow',
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
                    isZh ? '超时（秒）' : 'Timeout (s)',
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
                  Text(
                    isZh ? '重试次数' : 'Retries',
                    style: theme.textTheme.titleSmall,
                  ),
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
                    isZh ? '重试间隔上限（秒）' : 'Max retry delay (s)',
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
              Text(
                isZh ? '执行用户' : 'Run As User',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _runAsUser,
                decoration: InputDecoration(
                  hintText: isZh ? '默认（当前用户）' : 'Default (current user)',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                items: [
                  DropdownMenuItem<String>(
                    child: Text(isZh ? '默认' : 'Default'),
                  ),
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
                  labelText: isZh ? '标签（逗号分隔）' : 'Tags (comma-separated)',
                  hintText: isZh ? '例如: 备份, 清理' : 'e.g. backup, cleanup',
                ),
              ),
              const SizedBox(height: 18),
              // Working directory
              TextField(
                controller: _workingDirController,
                decoration: InputDecoration(
                  labelText: isZh ? '工作目录' : 'Working Directory',
                  hintText: isZh
                      ? '可选，默认为应用目录'
                      : 'Optional, defaults to app dir',
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
                  labelText: isZh ? '环境变量' : 'Environment Variables',
                  hintText: isZh
                      ? '每行一个，格式: KEY=VALUE'
                      : 'One per line, format: KEY=VALUE',
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
                isZh ? '执行上下文采集' : 'Execution Context Collection',
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
                      label: isZh ? '采集应用信息' : 'Capture app metadata',
                      subtitle: isZh
                          ? '记录应用版本、PID、可执行文件路径等信息'
                          : 'Capture app version, PID, executable path, etc.',
                      value: _collectAppMetadata,
                      onChanged: (value) =>
                          setState(() => _collectAppMetadata = value),
                    ),
                    _contextCollectTile(
                      icon: Icons.dns_rounded,
                      label: isZh ? '采集主机信息' : 'Capture host metadata',
                      subtitle: isZh
                          ? '记录系统版本、主机名、CPU 核心数等信息'
                          : 'Capture OS version, host name, CPU cores, etc.',
                      value: _collectHostMetadata,
                      onChanged: (value) =>
                          setState(() => _collectHostMetadata = value),
                    ),
                    _contextCollectTile(
                      icon: Icons.inventory_2_outlined,
                      label: isZh ? '采集环境快照' : 'Capture environment snapshot',
                      subtitle: isZh
                          ? '记录执行时有效环境变量快照（可能包含敏感信息）'
                          : 'Capture effective runtime environment variables (may include sensitive data).',
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
                      isZh ? '通知配置' : 'Notification Settings',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  PopupMenuButton<_NotificationTestScenario>(
                    tooltip: isZh ? '测试通知' : 'Test notification',
                    onSelected: _testNotification,
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: _NotificationTestScenario.success,
                        child: Text(
                          isZh ? '测试成功通知' : 'Test success notification',
                        ),
                      ),
                      PopupMenuItem(
                        value: _NotificationTestScenario.failure,
                        child: Text(
                          isZh ? '测试失败通知' : 'Test failure notification',
                        ),
                      ),
                      PopupMenuItem(
                        value: _NotificationTestScenario.timeout,
                        child: Text(
                          isZh ? '测试超时通知' : 'Test timeout notification',
                        ),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: _NotificationTestScenario.all,
                        child: Text(
                          isZh ? '测试全部（顺序）' : 'Test all (sequential)',
                        ),
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
                            isZh ? '测试通知' : 'Test Notification',
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
                isZh
                    ? '每个事件可分别配置通知渠道、严重程度、声音和震动。'
                    : 'Each event can be configured independently for channel, severity, sound, and vibration.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              _notifyRow(
                label: isZh ? '执行成功' : 'On Success',
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
                label: isZh ? '执行失败' : 'On Failure',
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
                label: isZh ? '执行超时' : 'On Timeout',
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
                  Text(
                    isZh ? '启用' : 'Enabled',
                    style: theme.textTheme.titleSmall,
                  ),
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
          label: isZh ? '取消' : 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        OpenHandDialogActionButton.primary(
          label: isZh ? '保存' : 'Save',
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
                  child: DropdownButtonFormField<CronNotifyType>(
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
                        child: Text(n.label(isZh)),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) onNotifyChanged(v);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: DropdownButtonFormField<CronNotifySeverity>(
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
                        child: Text(s.label(isZh)),
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
                hintText: isZh ? '自定义通知内容（可选）' : 'Custom message (optional)',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
            ),
            if (vibrationUnsupported) ...[
              const SizedBox(height: 6),
              Text(
                isZh
                    ? '当前平台不支持震动，开启后会自动忽略。'
                    : 'Vibration is not supported on this platform and will be ignored.',
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
    final err = CronParser.validate(expr, isZh: isZh);
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
    if (file != null) {
      setState(() {
        _scriptPathController.text = file.path;
      });
    }
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    // Validate cron expression.
    final cronExpr = _cronExpression;
    final cronErr = CronParser.validate(cronExpr, isZh: isZh);
    if (cronErr != null) {
      setState(() => _cronError = cronErr);
      return;
    }

    final timeout = int.tryParse(_timeoutController.text.trim()) ?? 60;
    final retryCount = int.tryParse(_retryController.text.trim()) ?? 0;
    final maxRetryDelay =
        int.tryParse(_maxRetryDelayController.text.trim()) ?? 30;

    final tags = _tagsController.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    final env = <String, String>{};
    for (final line in _envController.text.split('\n')) {
      final idx = line.indexOf('=');
      if (idx > 0) {
        env[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
      }
    }

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
      retryCount: retryCount.clamp(0, 10),
      timeoutSeconds: timeout.clamp(1, 3600),
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
      onSuccessMessage: _nullIfEmpty(_onSuccessMsgController.text),
      onFailureMessage: _nullIfEmpty(_onFailureMsgController.text),
      onTimeoutMessage: _nullIfEmpty(_onTimeoutMsgController.text),
      collectAppMetadata: _collectAppMetadata,
      collectHostMetadata: _collectHostMetadata,
      collectEnvironmentSnapshot: _collectEnvironmentSnapshot,
      workingDirectory: _nullIfEmpty(_workingDirController.text),
      environment: env,
      maxRetryDelaySeconds: maxRetryDelay.clamp(1, 300),
    );

    final controller = context.read<CronsController>();
    if (_isEditing) {
      controller.updateCron(entry);
    } else {
      controller.addCron(entry);
    }
    Navigator.of(context).pop();
  }

  String? _nullIfEmpty(String text) {
    final trimmed = text.trim();
    return trimmed.isEmpty ? null : trimmed;
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
      title: isZh ? '开始顺序测试' : 'Starting Sequential Test',
      body: isZh
          ? '将按顺序测试成功、失败、超时通知。'
          : 'Running success, failure, and timeout notification tests in sequence.',
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
        title: isZh ? '震动已忽略' : 'Vibration Ignored',
        body: isZh
            ? '当前平台不支持震动，顺序测试中已自动忽略震动设置。'
            : 'Vibration is not supported on this platform and was ignored during sequential test.',
      );
    }

    await OpenHandNotificationService.showInApp(
      title: isZh ? '顺序测试完成' : 'Sequential Test Completed',
      body: isZh
          ? '已完成成功、失败、超时三种通知测试。'
          : 'Completed success, failure, and timeout notification tests.',
      level: OpenHandNotificationLevel.success,
    );
  }

  Future<void> _testSingleNotification(
    _NotificationTestScenario scenario, {
    bool showVibrationFallbackHint = true,
  }) async {
    final config = _resolveTestNotificationConfig(scenario);
    final title = isZh
        ? '定时任务通知测试 · ${config.labelZh}'
        : 'Cron Notification Test - ${config.labelEn}';
    final defaultBody = isZh
        ? '${config.labelZh}场景通知测试消息。'
        : 'Notification test message for ${config.labelEn.toLowerCase()}.';
    final body = _nullIfEmpty(config.messageController.text) ?? defaultBody;

    if (config.type == CronNotifyType.none ||
        config.type == CronNotifyType.log) {
      await OpenHandNotificationService.showInApp(
        title: title,
        body: isZh
            ? '当前配置为“无”或“仅日志”，不会触发通知。'
            : 'Current setting is None or Log Only, so no notification is emitted.',
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
          title: isZh ? '系统通知不可用' : 'System Notification Unavailable',
          body: isZh
              ? '系统通知发送失败，已回退为应用内通知。'
              : 'System notification failed; fallback to in-app notification.',
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
        title: isZh ? '震动已忽略' : 'Vibration Ignored',
        body: isZh
            ? '当前平台不支持震动，已自动忽略该配置。'
            : 'Vibration is not supported on this platform and was ignored.',
      );
    }
  }

  ({
    CronNotifyType type,
    CronNotifySeverity severity,
    bool soundEnabled,
    bool vibrationEnabled,
    TextEditingController messageController,
    String labelZh,
    String labelEn,
  })
  _resolveTestNotificationConfig(_NotificationTestScenario scenario) {
    return switch (scenario) {
      _NotificationTestScenario.success => (
        type: _onSuccessNotify,
        severity: _onSuccessSeverity,
        soundEnabled: _onSuccessSound,
        vibrationEnabled: _onSuccessVibration,
        messageController: _onSuccessMsgController,
        labelZh: '成功',
        labelEn: 'Success',
      ),
      _NotificationTestScenario.failure => (
        type: _onFailureNotify,
        severity: _onFailureSeverity,
        soundEnabled: _onFailureSound,
        vibrationEnabled: _onFailureVibration,
        messageController: _onFailureMsgController,
        labelZh: '失败',
        labelEn: 'Failure',
      ),
      _NotificationTestScenario.timeout => (
        type: _onTimeoutNotify,
        severity: _onTimeoutSeverity,
        soundEnabled: _onTimeoutSound,
        vibrationEnabled: _onTimeoutVibration,
        messageController: _onTimeoutMsgController,
        labelZh: '超时',
        labelEn: 'Timeout',
      ),
      _NotificationTestScenario.all => (
        type: _onFailureNotify,
        severity: _onFailureSeverity,
        soundEnabled: _onFailureSound,
        vibrationEnabled: _onFailureVibration,
        messageController: _onFailureMsgController,
        labelZh: '全部',
        labelEn: 'All',
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
    return isZh ? '未知平台' : 'Unknown platform';
  }

  String _soundSupportTooltip(bool enabled) {
    final state = enabled ? (isZh ? '已开启' : 'On') : (isZh ? '已关闭' : 'Off');
    final support = _supportsSoundAlert;

    if (support) {
      final detail =
          (Platform.isMacOS || Platform.isLinux || Platform.isWindows)
          ? (isZh ? '支持（尽力触发系统声音）' : 'Supported (best effort via system sound)')
          : (isZh ? '支持' : 'Supported');
      return isZh
          ? '声音：$state\n平台：$_platformLabel\n状态：$detail'
          : 'Sound: $state\nPlatform: $_platformLabel\nSupport: $detail';
    }

    return isZh
        ? '声音：$state\n平台：$_platformLabel\n状态：当前平台不支持'
        : 'Sound: $state\nPlatform: $_platformLabel\nSupport: Not supported on this platform';
  }

  String _vibrationSupportTooltip(bool enabled) {
    final state = enabled ? (isZh ? '已开启' : 'On') : (isZh ? '已关闭' : 'Off');
    final supported = OpenHandNotificationService.supportsVibration;

    return supported
        ? (isZh
              ? '震动：$state\n平台：$_platformLabel\n状态：支持'
              : 'Vibration: $state\nPlatform: $_platformLabel\nSupport: Supported')
        : (isZh
              ? '震动：$state\n平台：$_platformLabel\n状态：不支持（开启后将自动忽略）'
              : 'Vibration: $state\nPlatform: $_platformLabel\nSupport: Not supported (will be ignored)');
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
            duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
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
                                isZh ? '敏感' : 'Sensitive',
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

// ---------------------------------------------------------------------------
// Execution history dialog
// ---------------------------------------------------------------------------

class _CronHistoryDialog extends StatelessWidget {
  const _CronHistoryDialog({required this.entry});

  final CronEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    final history = context.select<CronsController, List<CronExecutionRecord>>(
      (controller) => controller.historyFor(entry.id),
    );
    final controller = context.read<CronsController>();

    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(isZh ? '定时任务执行历史' : 'Scheduled Task Execution History'),
          ),
          if (history.isNotEmpty)
            Tooltip(
              message: isZh ? '清空全部执行历史' : 'Clear all execution history',
              child: IconButton(
                icon: Icon(
                  Icons.delete_sweep_outlined,
                  color: colorScheme.error,
                ),
                onPressed: () => _confirmClearAll(context, controller, isZh),
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
                  isZh ? '暂无执行记录' : 'No execution records yet',
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
                          _confirmDeleteRecord(context, isZh),
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
                        isZh: isZh,
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
          label: isZh ? '关闭' : 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  void _confirmClearAll(
    BuildContext context,
    CronsController controller,
    bool isZh,
  ) {
    showAnimatedDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isZh ? '清空执行历史' : 'Clear Execution History'),
        content: Text(
          isZh
              ? '确定清空「${entry.name}」的全部执行历史吗？此操作不可撤销。'
              : 'Clear all execution history for "${entry.name}"? This cannot be undone.',
        ),
        actions: [
          OpenHandDialogActionButton.secondary(
            label: isZh ? '取消' : 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
          ),
          OpenHandDialogActionButton.primary(
            label: isZh ? '清空' : 'Clear',
            onPressed: () {
              controller.clearHistoryForCron(entry.id);
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmDeleteRecord(BuildContext context, bool isZh) async {
    final result = await showAnimatedDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isZh ? '删除执行记录' : 'Delete Execution Record'),
        content: Text(isZh ? '确定删除这条执行记录吗？' : 'Delete this execution record?'),
        actions: [
          OpenHandDialogActionButton.secondary(
            label: isZh ? '取消' : 'Cancel',
            onPressed: () => Navigator.of(context).pop(false),
          ),
          OpenHandDialogActionButton.primary(
            label: isZh ? '删除' : 'Delete',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

class _HistoryRecordTile extends StatefulWidget {
  const _HistoryRecordTile({
    required this.record,
    required this.isZh,
    required this.onDelete,
  });

  final CronExecutionRecord record;
  final bool isZh;
  final VoidCallback onDelete;

  @override
  State<_HistoryRecordTile> createState() => _HistoryRecordTileState();
}

class _HistoryRecordTileState extends State<_HistoryRecordTile>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _animController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsController>().dialogAnimationSettings;
    final isNone = settings.entranceStyle.name == 'none';
    final duration = isNone
        ? Duration.zero
        : Duration(milliseconds: (settings.durationMs * 0.8).round());
    _animController = AnimationController(
      vsync: this,
      duration: duration,
      reverseDuration: Duration(
        milliseconds: (duration.inMilliseconds * 0.6).round(),
      ),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: settings.curve.curve,
      reverseCurve: settings.curve.reverseCurve,
    );
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
    final isZh = widget.isZh;

    final statusColor = switch (record.status) {
      'success' => const Color(0xFF56C271),
      'failed' => colorScheme.error,
      'timed_out' => colorScheme.tertiary,
      'running' => colorScheme.primary,
      'killed' => colorScheme.error,
      _ => colorScheme.onSurfaceVariant,
    };

    final statusLabel = switch (record.status) {
      'success' => isZh ? '成功' : 'Success',
      'failed' => isZh ? '失败' : 'Failed',
      'timed_out' => isZh ? '超时' : 'Timed Out',
      'running' => isZh ? '运行中' : 'Running',
      'killed' => isZh ? '已终止' : 'Killed',
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
      duration: _animController.duration ?? const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
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
                      _formatDateTime(record.startedAt),
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
                            ? (isZh ? '手动' : 'Manual')
                            : (isZh ? '调度' : 'Scheduled'),
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
                      tooltip: isZh ? '删除此条记录' : 'Delete this record',
                      onPressed: widget.onDelete,
                    ),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0.0,
                      duration:
                          _animController.duration ??
                          const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
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
                        isZh: isZh,
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
    required bool isZh,
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
              isZh ? '重试次数' : 'Retry Attempt',
              '${record.retryAttempt}',
              theme,
              colorScheme,
            ),
          // PID
          if (record.pid != null)
            _detailRow('PID', '${record.pid}', theme, colorScheme),
          // Run-as user
          if (record.runAsUser != null)
            _detailRow(
              isZh ? '执行用户' : 'Run As',
              record.runAsUser!,
              theme,
              colorScheme,
            ),
          // Working directory
          if (record.workingDirectory != null)
            _detailRow(
              isZh ? '工作目录' : 'Working Dir',
              record.workingDirectory!,
              theme,
              colorScheme,
            ),
          // Script environment overrides
          if (record.environment.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              isZh ? '脚本环境覆盖:' : 'Script Environment Overrides:',
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
            // 2026-04-25 — Hermes Talker 专属富面板：检测到结构化报告
            // 时优先展开，并把对应的 JSON 键从下方"执行上下文"原始 KV
            // 列表中过滤掉，避免重复且避免一坨 JSON 文本污染界面。
            if (record.appContext.containsKey(
                  CronsController.hermesTalkerReportsKey,
                ) ||
                record.appContext.containsKey(
                  CronsController.hermesTalkerStatsKey,
                )) ...[
              const SizedBox(height: 8),
              _HermesTalkerHistoryPanel(
                isZh: isZh,
                appContext: record.appContext,
              ),
            ],
            ..._buildPlainAppContextSection(
              theme: theme,
              colorScheme: colorScheme,
              isZh: isZh,
              record: record,
            ),
          ],
          if (record.environmentSnapshot.isNotEmpty) ...[
            const SizedBox(height: 8),
            _kvSection(
              title: isZh ? '环境快照:' : 'Environment Snapshot:',
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
              isZh ? '错误原因:' : 'Error:',
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
              isZh ? '标准输出 (stdout):' : 'stdout:',
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
              isZh ? '标准错误 (stderr):' : 'stderr:',
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
    required bool isZh,
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
        title: isZh ? '执行上下文:' : 'Execution Context:',
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

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }
}

// ---------------------------------------------------------------------------
// Hermes Talker 历史富展示面板
// ---------------------------------------------------------------------------

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

  int get memoryUpdates => _readInt(mutations['memory_updates']);
  int get memoryErrors => _readInt(mutations['memory_errors']);
  int get skillUpdates => _readInt(mutations['skill_updates']);
  int get skillErrors => _readInt(mutations['skill_errors']);
  int get toolCallRounds => _readInt(mutations['tool_call_rounds']);

  List<Map<String, Object?>> get memoryChanges =>
      _readListOfMap(mutations['memory_changes']);
  List<Map<String, Object?>> get profileChanges =>
      _readListOfMap(mutations['profile_changes']);
  List<Map<String, Object?>> get skillChanges =>
      _readListOfMap(mutations['skill_changes']);

  String? get modelId =>
      mutations['model_id'] is String ? mutations['model_id'] as String : null;
  String? get providerId => mutations['provider_id'] is String
      ? mutations['provider_id'] as String
      : null;
  String? get terminatedReason => mutations['terminated_reason'] is String
      ? mutations['terminated_reason'] as String
      : null;

  static int _readInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static List<Map<String, Object?>> _readListOfMap(Object? v) {
    if (v is! List) return const <Map<String, Object?>>[];
    final out = <Map<String, Object?>>[];
    for (final item in v) {
      if (item is Map<String, Object?>) {
        out.add(item);
      } else if (item is Map) {
        out.add(item.map((k, val) => MapEntry('$k', val)));
      }
    }
    return out;
  }
}

class _HermesTalkerHistoryPanel extends StatelessWidget {
  const _HermesTalkerHistoryPanel({
    required this.isZh,
    required this.appContext,
  });

  final bool isZh;
  final Map<String, String> appContext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
                      isZh ? 'Hermes Talker 自我学习报告' : 'Hermes Talker Report',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (stats.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          _formatStatsLine(stats, isZh),
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
                isZh
                    ? '本轮无符合条件的会话被实际学习。'
                    : 'No eligible sessions were actually learned this tick.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else ...[
            const SizedBox(height: 10),
            Text(
              isZh
                  ? '受影响的会话 (${reports.length})'
                  : 'Affected Sessions (${reports.length})',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            ...reports.map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _HermesTalkerSessionCard(report: r, isZh: isZh),
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
        if (item is Map<String, Object?>) {
          out.add(_HermesTalkerSessionReport.fromJson(item));
        } else if (item is Map) {
          out.add(
            _HermesTalkerSessionReport.fromJson(
              item.map((k, v) => MapEntry('$k', v)),
            ),
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
      parsed.forEach((k, v) {
        final n = v is int
            ? v
            : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
        out['$k'] = n;
      });
      return out;
    } catch (error, stack) {
      silentLog('crons_view', 'decode hermes talker stats', error, stack);
      return const <String, int>{};
    }
  }

  String _formatStatsLine(Map<String, int> stats, bool isZh) {
    int v(String k) => stats[k] ?? 0;
    if (isZh) {
      return '扫描 ${v('scanned')} · 触发 ${v('triggered')} · '
          '跳过 ${v('skipped')} · 异常 ${v('errors')}';
    }
    return 'scanned ${v('scanned')} · triggered ${v('triggered')} · '
        'skipped ${v('skipped')} · errors ${v('errors')}';
  }
}

class _HermesTalkerSessionCard extends StatelessWidget {
  const _HermesTalkerSessionCard({required this.report, required this.isZh});

  final _HermesTalkerSessionReport report;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isError = report.status == 'error';
    final accent = isError ? colorScheme.error : colorScheme.primary;
    final title = report.sessionTitle.trim().isEmpty
        ? (isZh ? '(未命名会话)' : '(untitled session)')
        : report.sessionTitle.trim();

    final chips = <Widget>[
      _statusChip(theme, colorScheme, report.status, isZh),
      if (report.memoryUpdates > 0)
        _metaChip(
          theme,
          colorScheme,
          icon: Icons.memory,
          label: isZh
              ? '记忆 +${report.memoryUpdates}'
              : 'memory +${report.memoryUpdates}',
        ),
      if (report.memoryErrors > 0)
        _metaChip(
          theme,
          colorScheme,
          icon: Icons.error_outline,
          label: isZh
              ? '记忆错误 ${report.memoryErrors}'
              : 'memory err ${report.memoryErrors}',
          tone: colorScheme.error,
        ),
      if (report.skillUpdates > 0)
        _metaChip(
          theme,
          colorScheme,
          icon: Icons.psychology_alt_outlined,
          label: isZh
              ? '技能 +${report.skillUpdates}'
              : 'skill +${report.skillUpdates}',
        ),
      if (report.skillErrors > 0)
        _metaChip(
          theme,
          colorScheme,
          icon: Icons.error_outline,
          label: isZh
              ? '技能错误 ${report.skillErrors}'
              : 'skill err ${report.skillErrors}',
          tone: colorScheme.error,
        ),
      if (report.profileChanges.isNotEmpty)
        _metaChip(
          theme,
          colorScheme,
          icon: Icons.account_circle_outlined,
          label: isZh
              ? '用户轮廓 ${report.profileChanges.length}'
              : 'profile ${report.profileChanges.length}',
        ),
      if (report.toolCallRounds > 0)
        _metaChip(
          theme,
          colorScheme,
          icon: Icons.repeat_rounded,
          label: isZh
              ? '工具轮次 ${report.toolCallRounds}'
              : 'rounds ${report.toolCallRounds}',
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
                '${isZh ? '模型' : 'model'}: ${report.modelId}',
              if (report.providerId != null)
                '${isZh ? '渠道' : 'provider'}: ${report.providerId}',
              if (report.terminatedReason != null)
                '${isZh ? '结束原因' : 'terminated'}: ${report.terminatedReason}',
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
          title: isZh ? '用户轮廓变动' : 'User profile changes',
          icon: Icons.account_circle_outlined,
          changes: report.profileChanges,
          isZh: isZh,
        ),
      if (report.memoryChanges.isNotEmpty)
        _changeGroup(
          theme: theme,
          colorScheme: colorScheme,
          title: isZh ? '记忆变动' : 'Memory changes',
          icon: Icons.memory,
          changes: report.memoryChanges,
          isZh: isZh,
        ),
      if (report.skillChanges.isNotEmpty)
        _changeGroup(
          theme: theme,
          colorScheme: colorScheme,
          title: isZh ? '技能变动' : 'Skill changes',
          icon: Icons.psychology_alt_outlined,
          changes: report.skillChanges,
          isZh: isZh,
        ),
      if (report.aiReasoning != null && report.aiReasoning!.isNotEmpty)
        _CollapsibleLongText(
          title: isZh ? '当时现场的 AI 思考' : 'AI reasoning on scene',
          icon: Icons.tips_and_updates_outlined,
          body: report.aiReasoning!,
          subdued: true,
        ),
      if (report.aiResponse != null && report.aiResponse!.isNotEmpty)
        _CollapsibleLongText(
          title: isZh ? '当时现场的 AI 响应' : 'AI response on scene',
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
                      isZh ? '本会话无更多详情。' : 'No further details.',
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
    bool isZh,
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
        label = isZh ? '失败' : 'error';
        break;
      case 'skipped':
        bg = colorScheme.surfaceContainerHighest;
        fg = colorScheme.onSurfaceVariant;
        icon = Icons.skip_next_rounded;
        label = isZh ? '跳过' : 'skipped';
        break;
      default:
        bg = colorScheme.primaryContainer;
        fg = colorScheme.onPrimaryContainer;
        icon = Icons.check_circle_outline;
        label = isZh ? '完成' : 'ok';
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
    required bool isZh,
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
                isZh: isZh,
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
    required bool isZh,
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
        .map((entry) => '**${_labelFor(entry.key, isZh)}**: ${entry.value}')
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

  String _labelFor(String key, bool isZh) {
    if (!isZh) return key;
    return switch (key) {
      'before' => '变更前',
      'after' => '变更后',
      'value' => '值',
      'source' => '来源',
      'reason' => '原因',
      'metadata' => '元数据',
      'error' => '错误',
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
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');

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
                      _expanded
                          ? (isZh ? '折叠' : 'Collapse')
                          : (isZh ? '展开' : 'Expand'),
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