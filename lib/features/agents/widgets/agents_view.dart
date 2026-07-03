import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/model/app_settings_snapshot.dart';
import '../../../app/state/settings_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/appear_once.dart';
import '../../../shared/ui/feature_page_shell.dart';
import '../../../shared/ui/feature_state_card.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_model_selector_field.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/localized_text.dart';
import '../../crons/index.dart';
import '../../hooks/index.dart';
import '../../knowledge_base/index.dart';
import '../../mcp/index.dart';
import '../../memory/index.dart';
import '../../skills/index.dart';
import '../agents_controller.dart';
import '../model/agent_models.dart';
import '../service/agent_runtime_availability.dart';

enum _AgentCardAction {
  edit,
  activities,
  logs,
  approvals,
  cluster,
  tasks,
  audit,
  kpi,
  resources,
  delete,
}

const double _agentCardRadius = 22;
const double _agentDialogMaxWidth = 1040;
const double _agentDialogMaxHeight = 780;

FeatureStateCard _agentRuntimeNotice(
  BuildContext context,
  AgentRuntimeAvailability runtime,
) {
  final title = runtime.isLoading
      ? openHandLocalizedText(
          context,
          zh: 'Hermes Agent 检查中',
          en: 'Checking Hermes Agent',
        )
      : openHandLocalizedText(
          context,
          zh: 'Hermes Agent 未就绪',
          en: 'Hermes Agent is not ready',
        );
  final body = runtime.isLoading
      ? openHandLocalizedText(
          context,
          zh: '插件服务仍在扫描运行时状态，完成后即可启动智能体工作循环。',
          en: 'Plugin service is still scanning the runtime. Agents can start once it finishes.',
        )
      : !runtime.isInstalled
      ? openHandLocalizedText(
          context,
          zh: '请先在插件板块安装 Hermes Agent，然后再启动智能体工作循环。',
          en: 'Install Hermes Agent from Plugins before starting an agent work loop.',
        )
      : openHandLocalizedText(
          context,
          zh: '请先在插件板块启用 Hermes Agent，然后再启动智能体工作循环。',
          en: 'Enable Hermes Agent from Plugins before starting an agent work loop.',
        );
  return FeatureStateCard.inline(
    icon: runtime.isLoading ? Icons.sync_rounded : Icons.extension_off_outlined,
    tone: runtime.isLoading ? FeatureStateTone.neutral : FeatureStateTone.error,
    title: title,
    body: body,
  );
}

class AgentsView extends StatelessWidget {
  const AgentsView({super.key});

  @override
  Widget build(BuildContext context) {
    final snapshot = context
        .select<
          AgentsController,
          ({
            bool isLoading,
            String? errorMessage,
            List<AgentProfile> agents,
            AgentRuntimeAvailability runtime,
          })
        >((controller) {
          return (
            isLoading: controller.isLoading,
            errorMessage: controller.errorMessage,
            agents: controller.agents,
            runtime: controller.runtimeAvailability,
          );
        });
    final controller = context.read<AgentsController>();
    final l10n = AppLocalizations.of(context)!;

    return FeaturePageShell(
      title: l10n.agentsTitle,
      subtitle: l10n.agentsSubtitle,
      actions: Wrap(
        spacing: 12,
        runSpacing: 12,
        alignment: WrapAlignment.end,
        children: [
          OutlinedButton.icon(
            onPressed: controller.openStorageDirectory,
            icon: const Icon(Icons.folder_open_rounded),
            label: Text(l10n.agentsOpenFolder),
          ),
          FilledButton.icon(
            onPressed: () => _showAgentEditor(context),
            icon: const Icon(Icons.add_rounded),
            label: Text(l10n.agentsCreateAgent),
          ),
        ],
      ),
      successSignal: controller.saveSuccessSignal,
      notices: [
        FeatureStateCard.inline(
          icon: Icons.info_outline_rounded,
          title: l10n.agentsWorkspaceTitle,
          body: l10n.agentsWorkspaceBody,
        ),
        if (snapshot.runtime.isLoading || !snapshot.runtime.canRun)
          _agentRuntimeNotice(context, snapshot.runtime),
      ],
      body: _AgentsBody(snapshot: snapshot),
    );
  }
}

class _AgentsBody extends StatelessWidget {
  const _AgentsBody({required this.snapshot});

  final ({
    bool isLoading,
    String? errorMessage,
    List<AgentProfile> agents,
    AgentRuntimeAvailability runtime,
  })
  snapshot;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (snapshot.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snapshot.errorMessage != null) {
      return FeatureStateCard.centered(
        icon: Icons.error_outline_rounded,
        tone: FeatureStateTone.error,
        title: l10n.agentsLoadFailed,
        body: snapshot.errorMessage!,
        action: OpenHandDialogActionButton.primary(
          onPressed: () => context.read<AgentsController>().refresh(),
          label: l10n.agentsRetry,
        ),
      );
    }
    if (snapshot.agents.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(0, 2, 0, 12),
        children: [
          FeatureStateCard.inline(
            icon: Icons.smart_toy_outlined,
            title: l10n.agentsEmptyTitle,
            body: l10n.agentsEmptyBody,
          ),
        ],
      );
    }
    return ListView.separated(
      key: const ValueKey<String>('agents-list'),
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 12),
      cacheExtent: 700,
      itemCount: snapshot.agents.length,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final agent = snapshot.agents[index];
        return SettingsAwareAppearOnce(
          key: ValueKey<String>('agent-card-${agent.id}'),
          child: RepaintBoundary(
            child: _AgentCard(
              agent: agent,
              onToggleEnabled: (enabled) => context
                  .read<AgentsController>()
                  .setAgentEnabled(agent.id, enabled: enabled),
              onAction: (action) => _handleAgentAction(context, agent, action),
            ),
          ),
        );
      },
    );
  }
}

class _AgentCard extends StatelessWidget {
  const _AgentCard({
    required this.agent,
    required this.onToggleEnabled,
    required this.onAction,
  });

  final AgentProfile agent;
  final ValueChanged<bool> onToggleEnabled;
  final ValueChanged<_AgentCardAction> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final toneColor = agent.isRunning ? cs.primary : cs.outline;
    final modelLabel = [
      agent.modelProviderConfigId,
      agent.modelId,
    ].where((item) => item != null && item.trim().isNotEmpty).join(' / ');

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_agentCardRadius),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AgentAvatar(agent: agent),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(agent.name, style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 6),
                      Text(
                        [
                          agent.position,
                          agent.department,
                          if (agent.mentor.trim().isNotEmpty)
                            '${l10n.agentsMentorLabel} ${agent.mentor}',
                        ].where((item) => item.trim().isNotEmpty).join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      if (agent.introduction.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          agent.introduction,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    Tooltip(
                      message: agent.enabled
                          ? l10n.agentsStopAgent
                          : l10n.agentsStartAgent,
                      child: IconButton.filledTonal(
                        onPressed: () => onToggleEnabled(!agent.enabled),
                        icon: Icon(
                          agent.enabled
                              ? Icons.stop_rounded
                              : Icons.play_arrow_rounded,
                        ),
                      ),
                    ),
                    _AgentIconAction(
                      icon: Icons.history_rounded,
                      tooltip: l10n.agentsActivities,
                      action: _AgentCardAction.activities,
                      onAction: onAction,
                    ),
                    _AgentIconAction(
                      icon: Icons.receipt_long_rounded,
                      tooltip: l10n.agentsLogs,
                      action: _AgentCardAction.logs,
                      onAction: onAction,
                    ),
                    _AgentIconAction(
                      icon: Icons.verified_user_rounded,
                      tooltip: l10n.agentsApprovals,
                      action: _AgentCardAction.approvals,
                      onAction: onAction,
                    ),
                    _AgentIconAction(
                      icon: Icons.account_tree_rounded,
                      tooltip: l10n.agentsCluster,
                      action: _AgentCardAction.cluster,
                      onAction: onAction,
                    ),
                    PopupMenuButton<_AgentCardAction>(
                      tooltip: l10n.agentsMore,
                      onSelected: onAction,
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: _AgentCardAction.tasks,
                          child: Text(l10n.agentsTaskDesk),
                        ),
                        PopupMenuItem(
                          value: _AgentCardAction.audit,
                          child: Text(l10n.agentsAuditReport),
                        ),
                        PopupMenuItem(
                          value: _AgentCardAction.kpi,
                          child: Text(l10n.agentsKpi),
                        ),
                        PopupMenuItem(
                          value: _AgentCardAction.resources,
                          child: Text(l10n.agentsResources),
                        ),
                        PopupMenuItem(
                          value: _AgentCardAction.edit,
                          child: Text(l10n.agentsEditConfig),
                        ),
                        PopupMenuItem(
                          value: _AgentCardAction.delete,
                          child: Text(l10n.agentsDeleteAgent),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _AgentPill(
                  icon: agent.isRunning
                      ? Icons.check_circle_outline_rounded
                      : Icons.pause_circle_outline_rounded,
                  label: _agentLifecycleStateLabel(l10n, agent.lifecycleState),
                  color: toneColor,
                ),
                _AgentPill(
                  icon: Icons.workspace_premium_outlined,
                  label: agent.level.trim().isEmpty ? 'L1' : agent.level,
                  color: cs.secondary,
                ),
                _AgentPill(
                  icon: Icons.security_rounded,
                  label: _agentExecutionModeLabel(l10n, agent.executionMode),
                  color: agent.executionMode == AgentExecutionMode.fullAccess
                      ? cs.tertiary
                      : cs.primary,
                ),
                _AgentPill(
                  icon: Icons.task_alt_rounded,
                  label: l10n.agentsTasksCount(
                    agent.runningTaskCount,
                    agent.tasks.length,
                  ),
                  color: cs.primary,
                ),
                _AgentPill(
                  icon: Icons.fact_check_rounded,
                  label: l10n.agentsApprovalsCount(agent.pendingApprovalCount),
                  color: cs.error,
                ),
                _AgentPill(
                  icon: Icons.memory_rounded,
                  label: l10n.agentsWorkersCount(
                    agent.workers.length,
                    agent.scaleSettings.maxWorkers,
                  ),
                  color: cs.secondary,
                ),
                if (modelLabel.isNotEmpty)
                  _AgentPill(
                    icon: Icons.auto_awesome_rounded,
                    label: modelLabel,
                    color: cs.primary,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _AgentCapabilitySummary(agent: agent),
          ],
        ),
      ),
    );
  }
}

class _AgentAvatar extends StatelessWidget {
  const _AgentAvatar({required this.agent});

  final AgentProfile agent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final avatar = agent.avatar.trim();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(18),
          ),
          alignment: Alignment.center,
          child: Text(
            avatar.isEmpty ? agent.initials : avatar,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: cs.onPrimaryContainer,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Positioned(
          right: -3,
          bottom: -3,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: cs.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.circle,
              color: agent.isRunning ? Colors.green : cs.outline,
              size: 18,
            ),
          ),
        ),
      ],
    );
  }
}

class _AgentIconAction extends StatelessWidget {
  const _AgentIconAction({
    required this.icon,
    required this.tooltip,
    required this.action,
    required this.onAction,
  });

  final IconData icon;
  final String tooltip;
  final _AgentCardAction action;
  final ValueChanged<_AgentCardAction> onAction;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton.filledTonal(
        onPressed: () => onAction(action),
        icon: Icon(icon),
      ),
    );
  }
}

class _AgentPill extends StatelessWidget {
  const _AgentPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 7),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentCapabilitySummary extends StatelessWidget {
  const _AgentCapabilitySummary({required this.agent});

  final AgentProfile agent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final rows = <String>[
      if (agent.skillNames.isNotEmpty)
        l10n.agentsCapabilitySkillsCount(agent.skillNames.length),
      if (agent.knowledgeSourceIds.isNotEmpty)
        l10n.agentsCapabilityKnowledgeCount(agent.knowledgeSourceIds.length),
      if (agent.memoryIds.isNotEmpty)
        l10n.agentsCapabilityMemoryCount(agent.memoryIds.length),
      if (agent.mcpServerNames.isNotEmpty) 'MCP ${agent.mcpServerNames.length}',
      if (agent.builtinToolNames.isNotEmpty)
        l10n.agentsCapabilityToolsCount(agent.builtinToolNames.length),
      if (agent.cronIds.isNotEmpty)
        l10n.agentsCapabilityCronsCount(agent.cronIds.length),
      if (agent.hookIds.isNotEmpty)
        l10n.agentsCapabilityHooksCount(agent.hookIds.length),
      if (agent.selfLearningEnabled) l10n.agentsSelfLearningOn,
    ];
    final text = rows.isEmpty
        ? l10n.agentsNoCapabilityResources
        : rows.join(' · ');
    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

Future<void> _handleAgentAction(
  BuildContext context,
  AgentProfile agent,
  _AgentCardAction action,
) async {
  final l10n = AppLocalizations.of(context)!;
  switch (action) {
    case _AgentCardAction.edit:
      await _showAgentEditor(context, initialAgent: agent);
    case _AgentCardAction.activities:
      await _showAgentListDialog(
        context,
        agent: agent,
        title: l10n.agentsActivities,
        icon: Icons.history_rounded,
        emptyTitle: l10n.agentsActivitiesEmptyTitle,
        rows: agent.activities
            .map(
              (item) => _DialogRow(
                title: _agentActivityTitle(l10n, item),
                subtitle: _agentActivitySubtitle(l10n, item),
                trailing: item.createdAt == null
                    ? ''
                    : formatMonthDayHm(item.createdAt!.toLocal()),
              ),
            )
            .toList(),
      );
    case _AgentCardAction.logs:
      await _showAgentListDialog(
        context,
        agent: agent,
        title: l10n.agentsCapabilityLogs,
        icon: Icons.receipt_long_rounded,
        emptyTitle: l10n.agentsLogsEmptyTitle,
        rows: agent.auditEvents
            .map(
              (item) => _DialogRow(
                title: item.toolName.isEmpty ? item.kind : item.toolName,
                subtitle: item.summary,
                trailing: item.createdAt == null
                    ? ''
                    : formatMonthDayHm(item.createdAt!.toLocal()),
              ),
            )
            .toList(),
      );
    case _AgentCardAction.approvals:
      await _showAgentListDialog(
        context,
        agent: agent,
        title: l10n.agentsApprovals,
        icon: Icons.verified_user_rounded,
        emptyTitle: l10n.agentsApprovalsEmptyTitle,
        rows: agent.approvals
            .map(
              (item) => _DialogRow(
                title: item.title,
                subtitle: item.reason,
                trailing: _agentApprovalStatusLabel(l10n, item.status),
              ),
            )
            .toList(),
      );
    case _AgentCardAction.cluster:
      await _showAgentClusterDialog(context, agent);
    case _AgentCardAction.tasks:
      await _showAgentTasksDialog(context, agent);
    case _AgentCardAction.audit:
      await _showAgentAuditDialog(context, agent);
    case _AgentCardAction.kpi:
      await _showAgentKpiDialog(context, agent);
    case _AgentCardAction.resources:
      await _showAgentResourcesDialog(context, agent);
    case _AgentCardAction.delete:
      await _confirmDeleteAgent(context, agent);
  }
}

class _DialogRow {
  const _DialogRow({
    required this.title,
    this.subtitle = '',
    this.trailing = '',
  });

  final String title;
  final String subtitle;
  final String trailing;
}

Future<void> _showAgentListDialog(
  BuildContext context, {
  required AgentProfile agent,
  required String title,
  required IconData icon,
  required String emptyTitle,
  required List<_DialogRow> rows,
}) {
  final l10n = AppLocalizations.of(context)!;
  return showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) {
      return buildOpenHandDialog(
        maxWidth: 760,
        maxHeight: 640,
        child: _AgentDialogScaffold(
          icon: icon,
          title: l10n.agentsDialogTitleWithName(title, agent.name),
          child: rows.isEmpty
              ? FeatureStateCard.inline(
                  icon: icon,
                  title: emptyTitle,
                  body: l10n.agentsListEmptyBody,
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 18),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(row.title),
                      subtitle: row.subtitle.trim().isEmpty
                          ? null
                          : Text(row.subtitle),
                      trailing: row.trailing.trim().isEmpty
                          ? null
                          : Text(row.trailing),
                    );
                  },
                ),
        ),
      );
    },
  );
}

Future<void> _showAgentClusterDialog(BuildContext context, AgentProfile agent) {
  final l10n = AppLocalizations.of(context)!;
  final settings = agent.scaleSettings;
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => buildOpenHandDialog(
      maxWidth: 840,
      maxHeight: 680,
      child: _AgentDialogScaffold(
        icon: Icons.account_tree_rounded,
        title: l10n.agentsDialogTitleWithName(l10n.agentsCluster, agent.name),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _AgentPill(
                  icon: Icons.compress_rounded,
                  label: l10n.agentsMinWorkersCount(settings.minWorkers),
                  color: Theme.of(context).colorScheme.primary,
                ),
                _AgentPill(
                  icon: Icons.unfold_more_rounded,
                  label: l10n.agentsMaxWorkersCount(settings.maxWorkers),
                  color: Theme.of(context).colorScheme.secondary,
                ),
                _AgentPill(
                  icon: Icons.route_rounded,
                  label: settings.schedulerPolicy,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
                _AgentPill(
                  icon: Icons.repeat_rounded,
                  label: '${settings.retryPolicy} · ${settings.maxRetries}',
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (agent.workers.isEmpty)
              FeatureStateCard.inline(
                icon: Icons.memory_rounded,
                title: l10n.agentsNoWorkersTitle,
                body: l10n.agentsNoWorkersBody,
              )
            else
              ...agent.workers.map(
                (worker) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    worker.status == AgentWorkerStatus.busy
                        ? Icons.sync_rounded
                        : Icons.check_circle_outline_rounded,
                  ),
                  title: Text(worker.name.isEmpty ? worker.id : worker.name),
                  subtitle: Text(
                    l10n.agentsWorkerSubtitle(
                      _agentWorkerStatusLabel(l10n, worker.status),
                      worker.executedTaskCount,
                      worker.priority,
                    ),
                  ),
                  trailing: Text('${(worker.busyScore * 100).round()}%'),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _showAgentTasksDialog(BuildContext context, AgentProfile agent) {
  final l10n = AppLocalizations.of(context)!;
  return showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) => buildOpenHandDialog(
      maxWidth: 900,
      maxHeight: 720,
      child: _AgentDialogScaffold(
        icon: Icons.task_alt_rounded,
        title: l10n.agentsDialogTitleWithName(l10n.agentsTaskDesk, agent.name),
        actions: [
          FilledButton.icon(
            onPressed: () async {
              await _showPublishTaskDialog(context, agent);
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            icon: const Icon(Icons.add_task_rounded),
            label: Text(l10n.agentsPublishTask),
          ),
        ],
        child: agent.tasks.isEmpty
            ? FeatureStateCard.inline(
                icon: Icons.task_alt_rounded,
                title: l10n.agentsNoTasksTitle,
                body: l10n.agentsNoTasksBody,
              )
            : Column(
                children: [
                  for (final task in agent.tasks)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(task.title),
                      subtitle: Text(
                        [
                          _agentTaskStatusLabel(l10n, task.status),
                          '${(task.progress * 100).round()}%',
                          task.description,
                        ].where((item) => item.trim().isNotEmpty).join(' · '),
                      ),
                      trailing: task.createdAt == null
                          ? null
                          : Text(formatMonthDayHm(task.createdAt!.toLocal())),
                    ),
                ],
              ),
      ),
    ),
  );
}

Future<void> _showAgentAuditDialog(BuildContext context, AgentProfile agent) {
  final l10n = AppLocalizations.of(context)!;
  final tokenUsage = agent.auditEvents.fold<int>(
    0,
    (sum, event) => sum + event.tokenUsage,
  );
  final requests = agent.auditEvents.fold<int>(
    0,
    (sum, event) => sum + event.requestCount,
  );
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => buildOpenHandDialog(
      maxWidth: 780,
      maxHeight: 640,
      child: _AgentDialogScaffold(
        icon: Icons.analytics_rounded,
        title: l10n.agentsDialogTitleWithName(
          l10n.agentsAuditReport,
          agent.name,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MetricTile(
                  label: l10n.agentsAuditRequests,
                  value: '$requests',
                ),
                _MetricTile(label: 'Token', value: '$tokenUsage'),
                _MetricTile(
                  label: l10n.agentsAuditCompleted,
                  value: '${agent.completedTaskCount}',
                ),
                _MetricTile(
                  label: l10n.agentsAuditUtilization,
                  value: '${(agent.workerUtilization * 100).round()}%',
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              l10n.agentsRecentAuditEvents,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (agent.auditEvents.isEmpty)
              Text(l10n.agentsNoAuditData)
            else
              ...agent.auditEvents
                  .take(8)
                  .map(
                    (event) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(event.summary),
                      subtitle: Text(
                        event.toolName.isEmpty ? event.kind : event.toolName,
                      ),
                    ),
                  ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _showAgentKpiDialog(BuildContext context, AgentProfile agent) {
  final l10n = AppLocalizations.of(context)!;
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => buildOpenHandDialog(
      maxWidth: 820,
      maxHeight: 680,
      child: _AgentDialogScaffold(
        icon: Icons.flag_rounded,
        title: l10n.agentsDialogTitleWithName(l10n.agentsKpi, agent.name),
        child: agent.kpis.isEmpty
            ? FeatureStateCard.inline(
                icon: Icons.flag_outlined,
                title: l10n.agentsNoKpiTitle,
                body: l10n.agentsNoKpiBody,
              )
            : Column(
                children: [
                  for (final item in agent.kpis)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(item.name),
                      subtitle: Text(
                        [
                          item.target,
                          item.plan,
                        ].where((v) => v.isNotEmpty).join(' · '),
                      ),
                      trailing: Text('${(item.progress * 100).round()}%'),
                    ),
                ],
              ),
      ),
    ),
  );
}

Future<void> _showAgentResourcesDialog(
  BuildContext context,
  AgentProfile agent,
) {
  final l10n = AppLocalizations.of(context)!;
  final resource = agent.resourceUsage;
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => buildOpenHandDialog(
      maxWidth: 760,
      maxHeight: 620,
      child: _AgentDialogScaffold(
        icon: Icons.storage_rounded,
        title: l10n.agentsDialogTitleWithName(l10n.agentsResources, agent.name),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _MetricTile(
              label: 'CPU',
              value: '${(resource.cpuPercent * 100).round()}%',
            ),
            _MetricTile(
              label: l10n.agentsMetricMemory,
              value: formatByteSize(resource.memoryBytes),
            ),
            _MetricTile(
              label: l10n.agentsMetricDisk,
              value: formatByteSize(resource.diskBytes),
            ),
            _MetricTile(
              label: l10n.agentsMetricPersisted,
              value: formatByteSize(resource.persistedBytes),
            ),
            _MetricTile(
              label: 'Token',
              value: '${resource.tokenUsed}/${resource.tokenBudget}',
            ),
            _MetricTile(
              label: l10n.agentsMetricHandles,
              value: '${resource.openHandles}',
            ),
          ],
        ),
      ),
    ),
  );
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SizedBox(
      width: 160,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelMedium),
              const SizedBox(height: 8),
              Text(value, style: theme.textTheme.titleLarge),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showPublishTaskDialog(
  BuildContext context,
  AgentProfile agent,
) async {
  final l10n = AppLocalizations.of(context)!;
  final title = TextEditingController();
  final description = TextEditingController();
  final content = TextEditingController();
  final note = TextEditingController();
  try {
    final submitted = await showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) => buildOpenHandDialog(
        maxWidth: 680,
        child: _AgentDialogScaffold(
          icon: Icons.add_task_rounded,
          title: l10n.agentsDialogTitleWithName(
            l10n.agentsPublishTask,
            agent.name,
          ),
          footer: buildOpenHandDialogActionsBar(
            actions: [
              OpenHandDialogActionButton.secondary(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                label: l10n.commonCancel,
              ),
              OpenHandDialogActionButton.primary(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                label: l10n.agentsPublish,
              ),
            ],
          ),
          child: Column(
            children: [
              TextField(
                controller: title,
                decoration: InputDecoration(
                  labelText: l10n.agentsTaskTitleLabel,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: description,
                decoration: InputDecoration(
                  labelText: l10n.agentsDescriptionLabel,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: content,
                minLines: 4,
                maxLines: 8,
                decoration: InputDecoration(labelText: l10n.agentsContentLabel),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                decoration: InputDecoration(labelText: l10n.agentsNoteLabel),
              ),
            ],
          ),
        ),
      ),
    );
    if (submitted == true && context.mounted) {
      await context.read<AgentsController>().publishTask(
        agent.id,
        title: title.text,
        description: description.text,
        content: content.text,
        note: note.text,
      );
    }
  } finally {
    title.dispose();
    description.dispose();
    content.dispose();
    note.dispose();
  }
}

Future<void> _confirmDeleteAgent(
  BuildContext context,
  AgentProfile agent,
) async {
  final l10n = AppLocalizations.of(context)!;
  final confirmed = await showOpenHandConfirmDialog(
    context: context,
    title: l10n.agentsDeleteConfirmTitle,
    message: l10n.agentsDeleteConfirmMessage(agent.name),
    confirmLabel: l10n.commonDelete,
    destructive: true,
  );
  if (confirmed && context.mounted) {
    await context.read<AgentsController>().deleteAgent(agent.id);
  }
}

class _AgentDialogScaffold extends StatelessWidget {
  const _AgentDialogScaffold({
    required this.icon,
    required this.title,
    required this.child,
    this.actions = const <Widget>[],
    this.footer,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final List<Widget> actions;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
              ...actions,
            ],
          ),
          const SizedBox(height: 18),
          Flexible(
            child: SingleChildScrollView(
              physics: openHandDialogAwareScrollPhysics(context),
              child: child,
            ),
          ),
          if (footer != null) ...[const SizedBox(height: 18), footer!],
        ],
      ),
    );
  }
}

Future<void> _showAgentEditor(
  BuildContext context, {
  AgentProfile? initialAgent,
}) async {
  final result = await showAnimatedDialog<AgentProfile>(
    context: context,
    builder: (dialogContext) => _AgentEditorDialog(initialAgent: initialAgent),
  );
  if (result != null && context.mounted) {
    await context.read<AgentsController>().saveAgent(result);
  }
}

class _AgentEditorDialog extends StatefulWidget {
  const _AgentEditorDialog({this.initialAgent});

  final AgentProfile? initialAgent;

  @override
  State<_AgentEditorDialog> createState() => _AgentEditorDialogState();
}

class _AgentEditorDialogState extends State<_AgentEditorDialog> {
  late final TextEditingController _avatar;
  late final TextEditingController _name;
  late final TextEditingController _position;
  late final TextEditingController _department;
  late final TextEditingController _mentor;
  late final TextEditingController _level;
  late final TextEditingController _introduction;
  late final TextEditingController _archive;
  late final TextEditingController _routeFrontMatter;
  late final TextEditingController _welcomeMessage;
  late final TextEditingController _persona;
  late final TextEditingController _boundary;
  late final TextEditingController _workspacePath;
  late final TextEditingController _workspaceScope;
  late final TextEditingController _taskLabels;
  late final TextEditingController _metadata;
  late final TextEditingController _kpiName;
  late final TextEditingController _kpiTarget;
  late AgentExecutionMode _executionMode;
  late bool _enabled;
  late bool _selfLearningEnabled;
  late int _minWorkers;
  late int _maxWorkers;
  late int _maxRetries;
  late String _schedulerPolicy;
  String? _modelProviderConfigId;
  String? _modelId;
  late Set<String> _skillNames;
  late Set<String> _knowledgeSourceIds;
  late Set<String> _memoryIds;
  late Set<String> _mcpServerNames;
  late Set<String> _builtinToolNames;
  late Set<String> _cronIds;
  late Set<String> _hookIds;
  late List<AgentKpiItem> _kpis;

  @override
  void initState() {
    super.initState();
    final agent = widget.initialAgent;
    _avatar = TextEditingController(text: agent?.avatar ?? '');
    _name = TextEditingController(text: agent?.name ?? '');
    _position = TextEditingController(text: agent?.position ?? '');
    _department = TextEditingController(text: agent?.department ?? '');
    _mentor = TextEditingController(text: agent?.mentor ?? '');
    _level = TextEditingController(text: agent?.level ?? 'L1');
    _introduction = TextEditingController(text: agent?.introduction ?? '');
    _archive = TextEditingController(text: agent?.archive ?? '');
    _routeFrontMatter = TextEditingController(
      text:
          agent?.routeFrontMatter ?? '---\nroute: default\npriority: 100\n---',
    );
    _welcomeMessage = TextEditingController(text: agent?.welcomeMessage ?? '');
    _persona = TextEditingController(text: agent?.persona ?? '');
    _boundary = TextEditingController(
      text: agent?.responsibilityBoundary ?? '',
    );
    _workspacePath = TextEditingController(text: agent?.workspacePath ?? '');
    _workspaceScope = TextEditingController(text: agent?.workspaceScope ?? '');
    _taskLabels = TextEditingController(
      text: agent?.taskLabels.join(', ') ?? '',
    );
    _metadata = TextEditingController(
      text: agent == null || agent.metadata.isEmpty
          ? '{}'
          : const JsonEncoder.withIndent('  ').convert(agent.metadata),
    );
    _kpiName = TextEditingController();
    _kpiTarget = TextEditingController();
    _executionMode = agent?.executionMode ?? AgentExecutionMode.normal;
    _enabled = agent?.enabled ?? false;
    _selfLearningEnabled = agent?.selfLearningEnabled ?? true;
    _modelProviderConfigId = agent?.modelProviderConfigId;
    _modelId = agent?.modelId;
    _skillNames = {...?agent?.skillNames};
    _knowledgeSourceIds = {...?agent?.knowledgeSourceIds};
    _memoryIds = {...?agent?.memoryIds};
    _mcpServerNames = {...?agent?.mcpServerNames};
    _builtinToolNames = {...?agent?.builtinToolNames};
    _cronIds = {...?agent?.cronIds};
    _hookIds = {...?agent?.hookIds};
    _minWorkers = agent?.scaleSettings.minWorkers ?? 1;
    _maxWorkers = agent?.scaleSettings.maxWorkers ?? 1;
    _maxRetries = agent?.scaleSettings.maxRetries ?? 2;
    _schedulerPolicy = agent?.scaleSettings.schedulerPolicy ?? 'least_busy';
    _kpis = List<AgentKpiItem>.from(agent?.kpis ?? const <AgentKpiItem>[]);
  }

  @override
  void dispose() {
    for (final controller in [
      _avatar,
      _name,
      _position,
      _department,
      _mentor,
      _level,
      _introduction,
      _archive,
      _routeFrontMatter,
      _welcomeMessage,
      _persona,
      _boundary,
      _workspacePath,
      _workspaceScope,
      _taskLabels,
      _metadata,
      _kpiName,
      _kpiTarget,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsController>();
    final skills = context.watch<SkillsController>().skills;
    final knowledgeSources = context.watch<KnowledgeBaseController>().sources;
    final memories = context.watch<MemoryController>().entries;
    final mcpServers = context.watch<McpController>().servers;
    final crons = context.watch<CronsController>().entries;
    final hooks = context.watch<HooksController>().entries;
    final builtinTools = settings.builtinToolConfigs;

    return buildOpenHandDialog(
      maxWidth: _agentDialogMaxWidth,
      maxHeight: _agentDialogMaxHeight,
      child: DefaultTabController(
        length: 5,
        child: Builder(
          builder: (dialogContext) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.smart_toy_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.initialAgent == null
                              ? l10n.agentsCreateAgent
                              : l10n.agentsEditAgent,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TabBar(
                    isScrollable: true,
                    tabs: [
                      Tab(text: l10n.agentsTabProfile),
                      Tab(text: l10n.agentsTabCapabilities),
                      Tab(text: l10n.agentsTabRuntime),
                      Tab(text: l10n.agentsTabGovernance),
                      Tab(text: l10n.agentsTabMetadata),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _tabScroll(_profileTab(l10n)),
                        _tabScroll(
                          _capabilitiesTab(
                            l10n: l10n,
                            skills: skills
                                .map(
                                  (s) => _Option(s.name, s.name, s.description),
                                )
                                .toList(),
                            knowledgeSources: knowledgeSources
                                .map((s) => _Option(s.id, s.title, s.status))
                                .toList(),
                            memories: memories
                                .map(
                                  (m) => _Option(m.id, m.displayTitle, m.type),
                                )
                                .toList(),
                            mcpServers: mcpServers
                                .map((m) => _Option(m.name, m.name, m.summary))
                                .toList(),
                            builtinTools: builtinTools
                                .map(
                                  (t) => _Option(
                                    t.effectiveName,
                                    t.effectiveName,
                                    t.kind.name,
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                        _tabScroll(
                          _runtimeTab(
                            l10n: l10n,
                            settings: settings,
                            recentSelections: settings.recentModelSelections,
                          ),
                        ),
                        _tabScroll(
                          _governanceTab(
                            l10n: l10n,
                            crons: crons
                                .map(
                                  (c) =>
                                      _Option(c.id, c.name, c.cronExpression),
                                )
                                .toList(),
                            hooks: hooks
                                .map(
                                  (h) => _Option(
                                    h.id,
                                    h.label,
                                    _hookEventLabel(l10n, h.event),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                        _tabScroll(_metadataTab(l10n)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  buildOpenHandDialogActionsBar(
                    actions: [
                      OpenHandDialogActionButton.secondary(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        label: l10n.commonCancel,
                      ),
                      OpenHandDialogActionButton.primary(
                        onPressed: _name.text.trim().isEmpty
                            ? null
                            : () => Navigator.of(
                                dialogContext,
                              ).pop(_buildAgent()),
                        label: l10n.commonSave,
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _tabScroll(Widget child) {
    return SingleChildScrollView(
      physics: openHandDialogAwareScrollPhysics(context),
      child: child,
    );
  }

  Widget _profileTab(AppLocalizations l10n) {
    return _FormGrid(
      children: [
        _field(
          _avatar,
          l10n.agentsFieldAvatar,
          hint: l10n.agentsFieldAvatarHint,
        ),
        _field(
          _name,
          l10n.agentsFieldNameRequired,
          onChanged: (_) => setState(() {}),
        ),
        _field(_position, l10n.agentsFieldPosition),
        _field(_department, l10n.agentsFieldDepartment),
        _field(_mentor, l10n.agentsMentorLabel),
        _field(_level, l10n.agentsFieldLevel),
        _field(
          _introduction,
          l10n.agentsFieldIntroduction,
          maxLines: 3,
          fullWidth: true,
        ),
        _field(_archive, l10n.agentsFieldArchive, maxLines: 5, fullWidth: true),
        _field(
          _routeFrontMatter,
          l10n.agentsFieldRouteFrontMatter,
          maxLines: 5,
          fullWidth: true,
        ),
        _field(
          _welcomeMessage,
          l10n.agentsFieldWelcomeMessage,
          maxLines: 3,
          fullWidth: true,
        ),
        _field(_persona, l10n.agentsFieldPersona, maxLines: 5, fullWidth: true),
        _field(
          _boundary,
          l10n.agentsFieldResponsibilityBoundary,
          maxLines: 5,
          fullWidth: true,
        ),
      ],
    );
  }

  Widget _capabilitiesTab({
    required AppLocalizations l10n,
    required List<_Option> skills,
    required List<_Option> knowledgeSources,
    required List<_Option> memories,
    required List<_Option> mcpServers,
    required List<_Option> builtinTools,
  }) {
    return Column(
      children: [
        _OptionChips(
          title: l10n.skills,
          options: skills,
          selected: _skillNames,
          onChanged: (v) => setState(() => _skillNames = v),
        ),
        _OptionChips(
          title: l10n.agentsKnowledgeBase,
          options: knowledgeSources,
          selected: _knowledgeSourceIds,
          onChanged: (v) => setState(() => _knowledgeSourceIds = v),
        ),
        _OptionChips(
          title: l10n.memory,
          options: memories,
          selected: _memoryIds,
          onChanged: (v) => setState(() => _memoryIds = v),
        ),
        _OptionChips(
          title: 'MCP',
          options: mcpServers,
          selected: _mcpServerNames,
          onChanged: (v) => setState(() => _mcpServerNames = v),
        ),
        _OptionChips(
          title: l10n.agentsBuiltInTools,
          options: builtinTools,
          selected: _builtinToolNames,
          onChanged: (v) => setState(() => _builtinToolNames = v),
        ),
      ],
    );
  }

  Widget _runtimeTab({
    required AppLocalizations l10n,
    required SettingsController settings,
    required List<RecentModelSelection> recentSelections,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OpenHandModelSelectorField(
          models: settings.aiModels,
          recentSelections: recentSelections,
          selectedConfigId: _modelProviderConfigId,
          selectedModelId: _modelId,
          onSelected: (value) => setState(() {
            _modelProviderConfigId = value.$1;
            _modelId = value.$2;
          }),
          labelZh: l10n.agentsModelLabel,
          labelEn: l10n.agentsModelLabel,
        ),
        const SizedBox(height: 14),
        SegmentedButton<AgentExecutionMode>(
          segments: [
            for (final mode in AgentExecutionMode.values)
              ButtonSegment(
                value: mode,
                label: Text(_agentExecutionModeLabel(l10n, mode)),
              ),
          ],
          selected: {_executionMode},
          onSelectionChanged: (value) =>
              setState(() => _executionMode = value.first),
        ),
        const SizedBox(height: 14),
        SwitchListTile(
          value: _enabled,
          onChanged: (value) => setState(() => _enabled = value),
          title: Text(l10n.agentsEnableAgentTitle),
          subtitle: Text(l10n.agentsEnableAgentBody),
        ),
        SwitchListTile(
          value: _selfLearningEnabled,
          onChanged: (value) => setState(() => _selfLearningEnabled = value),
          title: Text(l10n.agentsSelfLearningTitle),
          subtitle: Text(l10n.agentsSelfLearningBody),
        ),
        _field(_workspacePath, l10n.agentsFieldWorkspacePath),
        const SizedBox(height: 12),
        _field(_workspaceScope, l10n.agentsFieldWorkspaceScope, maxLines: 3),
      ],
    );
  }

  Widget _governanceTab({
    required AppLocalizations l10n,
    required List<_Option> crons,
    required List<_Option> hooks,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OptionChips(
          title: l10n.agentsCrons,
          options: crons,
          selected: _cronIds,
          onChanged: (v) => setState(() => _cronIds = v),
        ),
        _OptionChips(
          title: 'Hooks',
          options: hooks,
          selected: _hookIds,
          onChanged: (v) => setState(() => _hookIds = v),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.agentsClusterScaling,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _numberStepper(
                l10n.agentsMinWorkersLabel,
                _minWorkers,
                (v) => setState(() => _minWorkers = v.clamp(0, _maxWorkers)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _numberStepper(
                l10n.agentsMaxWorkersLabel,
                _maxWorkers,
                (v) => setState(() => _maxWorkers = v.clamp(1, 999)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _numberStepper(
                l10n.agentsMaxRetriesLabel,
                _maxRetries,
                (v) => setState(() => _maxRetries = v.clamp(0, 20)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _schedulerPolicy,
          decoration: InputDecoration(
            labelText: l10n.agentsSchedulerPolicyLabel,
          ),
          items: const ['least_busy', 'priority_first', 'round_robin']
              .map(
                (value) => DropdownMenuItem(value: value, child: Text(value)),
              )
              .toList(),
          onChanged: (value) =>
              setState(() => _schedulerPolicy = value ?? _schedulerPolicy),
        ),
        const SizedBox(height: 14),
        _field(
          _taskLabels,
          l10n.agentsTaskLabelsLabel,
          hint: l10n.agentsCommaSeparatedHint,
        ),
        const SizedBox(height: 14),
        Text(l10n.agentsKpi, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _kpiName,
                decoration: InputDecoration(labelText: l10n.agentsFieldName),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _kpiTarget,
                decoration: InputDecoration(labelText: l10n.agentsFieldTarget),
              ),
            ),
            const SizedBox(width: 12),
            IconButton.filledTonal(
              onPressed: _addKpi,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        for (final item in _kpis)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(item.name),
            subtitle: Text(item.target),
            trailing: IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => setState(() => _kpis.remove(item)),
            ),
          ),
      ],
    );
  }

  Widget _metadataTab(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _field(_metadata, l10n.agentsMetadataJsonLabel, maxLines: 14),
        const SizedBox(height: 12),
        FeatureStateCard.inline(
          icon: Icons.schema_rounded,
          title: l10n.agentsMetadataInfoTitle,
          body: l10n.agentsMetadataInfoBody,
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    int maxLines = 1,
    bool fullWidth = false,
    ValueChanged<String>? onChanged,
  }) {
    return _FormGridItem(
      fullWidth: fullWidth,
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        onChanged: onChanged,
        decoration: InputDecoration(labelText: label, hintText: hint),
      ),
    );
  }

  Widget _numberStepper(String label, int value, ValueChanged<int> onChanged) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Row(
        children: [
          IconButton(
            onPressed: () => onChanged(value - 1),
            icon: const Icon(Icons.remove_rounded),
          ),
          Expanded(child: Text('$value', textAlign: TextAlign.center)),
          IconButton(
            onPressed: () => onChanged(value + 1),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }

  void _addKpi() {
    final name = _kpiName.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _kpis.add(
        AgentKpiItem(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: name,
          target: _kpiTarget.text.trim(),
          createdAt: DateTime.now().toUtc(),
        ),
      );
      _kpiName.clear();
      _kpiTarget.clear();
    });
  }

  AgentProfile _buildAgent() {
    final now = DateTime.now().toUtc();
    final previous = widget.initialAgent;
    return AgentProfile(
      id: previous?.id ?? '',
      name: _name.text.trim(),
      avatar: _avatar.text.trim(),
      position: _position.text.trim(),
      department: _department.text.trim(),
      mentor: _mentor.text.trim(),
      level: _level.text.trim(),
      introduction: _introduction.text.trim(),
      archive: _archive.text.trim(),
      routeFrontMatter: _routeFrontMatter.text.trim(),
      welcomeMessage: _welcomeMessage.text.trim(),
      modelProviderConfigId: _modelProviderConfigId,
      modelId: _modelId,
      persona: _persona.text.trim(),
      responsibilityBoundary: _boundary.text.trim(),
      skillNames: _skillNames.toList(),
      knowledgeSourceIds: _knowledgeSourceIds.toList(),
      memoryIds: _memoryIds.toList(),
      taskLabels: _taskLabels.text
          .split(',')
          .map((v) => v.trim())
          .where((v) => v.isNotEmpty)
          .toList(),
      mcpServerNames: _mcpServerNames.toList(),
      builtinToolNames: _builtinToolNames.toList(),
      workspacePath: _workspacePath.text.trim(),
      workspaceScope: _workspaceScope.text.trim(),
      cronIds: _cronIds.toList(),
      hookIds: _hookIds.toList(),
      selfLearningEnabled: _selfLearningEnabled,
      enabled: _enabled,
      executionMode: _executionMode,
      lifecycleState: _enabled
          ? AgentLifecycleState.running
          : AgentLifecycleState.stopped,
      scaleSettings: AgentScaleSettings(
        minWorkers: _minWorkers,
        maxWorkers: _maxWorkers,
        maxRetries: _maxRetries,
        schedulerPolicy: _schedulerPolicy,
        tags: _taskLabels.text
            .split(',')
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty)
            .toList(),
      ),
      tasks: previous?.tasks ?? const <AgentTask>[],
      approvals: previous?.approvals ?? const <AgentApprovalRequest>[],
      activities: previous?.activities ?? const <AgentActivityEvent>[],
      auditEvents: previous?.auditEvents ?? const <AgentAuditEvent>[],
      kpis: _kpis,
      workers: previous?.workers ?? const <AgentWorker>[],
      resourceUsage: previous?.resourceUsage ?? const AgentResourceUsage(),
      metadata: _metadataJson(),
      createdAt: previous?.createdAt ?? now,
      updatedAt: now,
    );
  }

  Map<String, Object?> _metadataJson() {
    try {
      final decoded = jsonDecode(
        _metadata.text.trim().isEmpty ? '{}' : _metadata.text,
      );
      return decoded is Map<String, Object?>
          ? decoded
          : const <String, Object?>{};
    } catch (_) {
      return const <String, Object?>{};
    }
  }
}

class _Option {
  const _Option(this.id, this.label, this.subtitle);

  final String id;
  final String label;
  final String subtitle;
}

class _OptionChips extends StatelessWidget {
  const _OptionChips({
    required this.title,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final String title;
  final List<_Option> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (options.isEmpty)
            Text(l10n.agentsNoOptionsAvailable)
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: SingleChildScrollView(
                physics: openHandDialogAwareScrollPhysics(context),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in options)
                      FilterChip(
                        label: Text(
                          option.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                        selected: selected.contains(option.id),
                        onSelected: (value) {
                          final next = {...selected};
                          value ? next.add(option.id) : next.remove(option.id);
                          onChanged(next);
                        },
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FormGrid extends StatelessWidget {
  const _FormGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 720;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final child in children)
              SizedBox(
                width: child is _FormGridItem && child.fullWidth || !twoColumns
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 12) / 2,
                child: child is _FormGridItem ? child.child : child,
              ),
          ],
        );
      },
    );
  }
}

class _FormGridItem extends StatelessWidget {
  const _FormGridItem({required this.child, this.fullWidth = false});

  final Widget child;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) => child;
}

String _agentLifecycleStateLabel(
  AppLocalizations l10n,
  AgentLifecycleState state,
) {
  return switch (state) {
    AgentLifecycleState.stopped => l10n.agentLifecycleStopped,
    AgentLifecycleState.running => l10n.agentLifecycleRunning,
    AgentLifecycleState.paused => l10n.agentLifecyclePaused,
    AgentLifecycleState.degraded => l10n.agentLifecycleDegraded,
  };
}

String _agentExecutionModeLabel(
  AppLocalizations l10n,
  AgentExecutionMode mode,
) {
  return switch (mode) {
    AgentExecutionMode.normal => l10n.agentExecutionModeNormal,
    AgentExecutionMode.fullAccess => l10n.agentExecutionModeFullAccess,
  };
}

String _agentActivityTitle(AppLocalizations l10n, AgentActivityEvent event) {
  return switch (event.kind) {
    'agent_started' => l10n.agentsActivityAgentStarted,
    'agent_stopped' => l10n.agentsActivityAgentStopped,
    'task_published' => l10n.agentsActivityTaskPublished,
    'task_assigned' =>
      l10n.localeName.toLowerCase().startsWith('zh')
          ? '任务已分配'
          : 'Task assigned',
    'task_updated' => l10n.agentsActivityTaskUpdated,
    'task_canceled' => l10n.agentsActivityTaskCanceled,
    'task_paused' => l10n.agentsActivityTaskPaused,
    'task_terminated' => l10n.agentsActivityTaskTerminated,
    'task_resumed' => l10n.agentsActivityTaskResumed,
    _ => event.title.trim().isEmpty ? event.kind : event.title,
  };
}

String _agentActivitySubtitle(AppLocalizations l10n, AgentActivityEvent event) {
  final content = event.content.trim();
  if (content.isNotEmpty) return content;
  return switch (event.kind) {
    'agent_started' ||
    'agent_stopped' ||
    'task_assigned' ||
    'task_updated' ||
    'task_canceled' ||
    'task_paused' ||
    'task_terminated' ||
    'task_resumed' => '',
    _ => _agentActivityMetadataFallback(event),
  };
}

String _agentActivityMetadataFallback(AgentActivityEvent event) {
  final taskId = event.metadata['task_id'];
  if (taskId != null && '$taskId'.trim().isNotEmpty) {
    return 'task_id: ${'$taskId'.trim()}';
  }
  return event.title.trim();
}

String _agentTaskStatusLabel(AppLocalizations l10n, AgentTaskStatus status) {
  return switch (status) {
    AgentTaskStatus.backlog => l10n.agentTaskStatusBacklog,
    AgentTaskStatus.ready => l10n.agentTaskStatusReady,
    AgentTaskStatus.running => l10n.agentTaskStatusRunning,
    AgentTaskStatus.waitingApproval => l10n.agentTaskStatusWaitingApproval,
    AgentTaskStatus.paused => l10n.agentTaskStatusPaused,
    AgentTaskStatus.completed => l10n.agentTaskStatusCompleted,
    AgentTaskStatus.failed => l10n.agentTaskStatusFailed,
    AgentTaskStatus.canceled => l10n.agentTaskStatusCanceled,
  };
}

String _agentApprovalStatusLabel(
  AppLocalizations l10n,
  AgentApprovalStatus status,
) {
  return switch (status) {
    AgentApprovalStatus.pending => l10n.agentApprovalStatusPending,
    AgentApprovalStatus.approved => l10n.agentApprovalStatusApproved,
    AgentApprovalStatus.rejected => l10n.agentApprovalStatusRejected,
    AgentApprovalStatus.expired => l10n.agentApprovalStatusExpired,
  };
}

String _agentWorkerStatusLabel(
  AppLocalizations l10n,
  AgentWorkerStatus status,
) {
  return switch (status) {
    AgentWorkerStatus.idle => l10n.agentWorkerStatusIdle,
    AgentWorkerStatus.busy => l10n.agentWorkerStatusBusy,
    AgentWorkerStatus.draining => l10n.agentWorkerStatusDraining,
    AgentWorkerStatus.offline => l10n.agentWorkerStatusOffline,
  };
}

String _hookEventLabel(AppLocalizations l10n, HookEvent event) {
  return switch (event) {
    HookEvent.sessionStart => l10n.hookEventSessionStart,
    HookEvent.userPromptSubmit => l10n.hookEventUserPromptSubmit,
    HookEvent.preToolUse => l10n.hookEventPreToolUse,
    HookEvent.postToolUse => l10n.hookEventPostToolUse,
    HookEvent.subagentStart => l10n.hookEventSubagentStart,
    HookEvent.subagentStop => l10n.hookEventSubagentStop,
    HookEvent.stop => l10n.hookEventStop,
    HookEvent.preCompact => l10n.hookEventPreCompact,
    HookEvent.sessionEnd => l10n.hookEventSessionEnd,
    HookEvent.errorOccurred => l10n.hookEventErrorOccurred,
  };
}
