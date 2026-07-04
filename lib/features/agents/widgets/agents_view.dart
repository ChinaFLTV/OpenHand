import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../app/model/app_settings_snapshot.dart';
import '../../../app/model/dialog_animation_settings.dart';
import '../../../app/state/settings_controller.dart';
import '../../../app/support/openhand_paths.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/animated_appearance.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/appear_once.dart';
import '../../../shared/ui/feature_page_shell.dart';
import '../../../shared/ui/feature_state_card.dart';
import '../../../shared/ui/image_editor_dialog.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_model_selector_field.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/localized_text.dart';
import '../../ai/index.dart'
    show AiBuiltinToolConfig, AiBuiltinToolKind, AiBuiltinToolKindAgentMetadata;
import '../../crons/index.dart';
import '../../hooks/index.dart';
import '../../knowledge_base/index.dart';
import '../../mcp/index.dart';
import '../../memory/index.dart';
import '../../skills/index.dart';
import '../agents_controller.dart';
import '../model/agent_models.dart';
import '../service/agent_routing_metadata.dart';
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
const List<String> _agentSchedulerPolicyOptions = <String>[
  'least_busy',
  'priority_first',
  'round_robin',
];
const List<String> _agentWorkerRemovalPolicyOptions = <String>[
  'least_busy',
  'newest_first',
];
const List<String> _agentRetryPolicyOptions = <String>['bounded_retry', 'none'];
const List<String> _agentKpiStatusOptions = <String>[
  'tracking',
  'at_risk',
  'done',
  'paused',
];
const int _agentRoutePreviewKeywordLimit = 10;
const List<String> _agentImageExtensions = <String>[
  'jpg',
  'jpeg',
  'png',
  'webp',
  'gif',
  'bmp',
];
const double _agentChipStripHeight = 44;

bool _isAgentCoordinationBuiltinToolId(String id) {
  return AiBuiltinToolKind.values.any(
    (kind) => kind.isAgentCoordinationTool && kind.name == id,
  );
}

String _agentRuntimeBlockingText(
  BuildContext context,
  AgentRuntimeAvailability runtime,
) {
  if (runtime.canRun) return '';
  if (runtime.isLoading) {
    return openHandLocalizedText(
      context,
      zh: 'Hermes Agent 运行时仍在检查中，暂不能启动工作循环。',
      en: runtime.blockingReason,
    );
  }
  if (!runtime.isInstalled) {
    return openHandLocalizedText(
      context,
      zh: '请先安装 Hermes Agent 插件，再启动智能体工作循环。',
      en: runtime.blockingReason,
    );
  }
  if (!runtime.isEnabled) {
    return openHandLocalizedText(
      context,
      zh: '请先启用 Hermes Agent 插件，再启动智能体工作循环。',
      en: runtime.blockingReason,
    );
  }
  return runtime.errorMessage ?? runtime.blockingReason;
}

String _agentRuntimeCreateBlockingText(
  BuildContext context,
  AgentRuntimeAvailability runtime,
) {
  if (runtime.canRun) return '';
  final reason = runtime.isLoading
      ? openHandLocalizedText(
          context,
          zh: 'Hermes Agent 运行时仍在检查中，暂不能创建智能体。',
          en: 'Hermes Agent runtime is still being checked. Try creating an agent after it finishes.',
        )
      : !runtime.isInstalled
      ? openHandLocalizedText(
          context,
          zh: '请先在插件板块安装 Hermes Agent，再创建智能体。',
          en: 'Install Hermes Agent from Plugins before creating an agent.',
        )
      : !runtime.isEnabled
      ? openHandLocalizedText(
          context,
          zh: '请先在插件板块启用 Hermes Agent，再创建智能体。',
          en: 'Enable Hermes Agent from Plugins before creating an agent.',
        )
      : (runtime.errorMessage ?? runtime.blockingReason);
  return openHandLocalizedText(
    context,
    zh: 'Hermes Agent 未就绪：$reason',
    en: 'Hermes Agent is not ready: $reason',
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
      actions: FilledButton.icon(
        onPressed: () => _handleCreateAgent(context, snapshot.runtime),
        icon: const Icon(Icons.add_rounded),
        label: Text(l10n.agentsCreateAgent),
      ),
      successSignal: controller.saveSuccessSignal,
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
      return const SizedBox.expand(
        key: ValueKey<String>('agents-empty'),
        child: _AgentsEmptyState(),
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
              onToggleEnabled: (enabled) =>
                  _handleToggleAgentEnabled(context, agent, enabled),
              onAction: (action) => _handleAgentAction(context, agent, action),
            ),
          ),
        );
      },
    );
  }
}

class _AgentsEmptyState extends StatelessWidget {
  const _AgentsEmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return FeatureStateCard.centered(
      icon: Icons.smart_toy_outlined,
      tone: FeatureStateTone.neutral,
      title: l10n.agentsEmptyTitle,
      body: l10n.agentsEmptyBody,
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
                      icon: Icons.edit_rounded,
                      tooltip: l10n.agentsEditConfig,
                      action: _AgentCardAction.edit,
                      onAction: onAction,
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
                    _AgentIconAction(
                      icon: Icons.task_alt_rounded,
                      tooltip: l10n.agentsTaskDesk,
                      action: _AgentCardAction.tasks,
                      onAction: onAction,
                    ),
                    _AgentIconAction(
                      icon: Icons.analytics_rounded,
                      tooltip: l10n.agentsAuditReport,
                      action: _AgentCardAction.audit,
                      onAction: onAction,
                    ),
                    _AgentIconAction(
                      icon: Icons.flag_rounded,
                      tooltip: l10n.agentsKpi,
                      action: _AgentCardAction.kpi,
                      onAction: onAction,
                    ),
                    _AgentIconAction(
                      icon: Icons.storage_rounded,
                      tooltip: l10n.agentsResources,
                      action: _AgentCardAction.resources,
                      onAction: onAction,
                    ),
                    PopupMenuButton<_AgentCardAction>(
                      key: ValueKey<String>('agent-card-more-${agent.id}'),
                      tooltip: l10n.agentsMore,
                      onSelected: onAction,
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          key: ValueKey<String>(
                            'agent-card-delete-${agent.id}',
                          ),
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
          clipBehavior: Clip.antiAlias,
          child: _AgentAvatarContent(
            avatar: avatar,
            fallback: agent.initials,
            size: 64,
            textStyle: theme.textTheme.headlineSmall?.copyWith(
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

class _AgentDraftKpiList extends StatelessWidget {
  const _AgentDraftKpiList({required this.items, required this.onRemove});

  final List<AgentKpiItem> items;
  final ValueChanged<AgentKpiItem> onRemove;

  @override
  Widget build(BuildContext context) {
    final settings = _agentChipAnimationSettings(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final child = items.isEmpty
        ? Text(
            key: const ValueKey<String>('agent-draft-kpi-empty'),
            openHandLocalizedText(
              context,
              zh: '暂无 KPI。添加后会随智能体档案保存。',
              en: 'No KPI yet. Added KPIs are saved with this agent.',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          )
        : Column(
            key: ValueKey<String>('agent-draft-kpi-list-${items.length}'),
            children: [
              for (var index = 0; index < items.length; index++) ...[
                if (index > 0) const SizedBox(height: 8),
                _AgentDraftKpiTile(
                  key: ValueKey<String>(
                    'agent-draft-kpi-${items[index].id}-${items[index].name}',
                  ),
                  item: items[index],
                  onRemove: () => onRemove(items[index]),
                ),
              ],
            ],
          );
    return AnimatedSwitcher(
      duration: settings.duration,
      reverseDuration: settings.duration,
      switchInCurve: settings.curve.curve,
      switchOutCurve: settings.curve.reverseCurve,
      transitionBuilder: (child, animation) {
        return SizeTransition(
          axisAlignment: -1,
          sizeFactor: animation,
          child: buildAnimationStyleTransition(
            animation: animation,
            settings: settings,
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _AgentDraftKpiTile extends StatelessWidget {
  const _AgentDraftKpiTile({
    super.key,
    required this.item,
    required this.onRemove,
  });

  final AgentKpiItem item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final statusColor = _agentKpiStatusColor(cs, item.status);
    final progress = item.progress.clamp(0, 1).toDouble();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(
                _agentKpiStatusIcon(item.status),
                size: 18,
                color: statusColor,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _AgentActivityTypeChip(
                        label: _agentKpiStatusLabel(context, item.status),
                        color: statusColor,
                      ),
                      Text(
                        '${(progress * 100).round()}%',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (item.target.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      item.target,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      color: statusColor,
                      backgroundColor: cs.surfaceContainerHighest,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: openHandLocalizedText(
                context,
                zh: '删除 KPI',
                en: 'Remove KPI',
              ),
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _handleAgentAction(
  BuildContext context,
  AgentProfile agent,
  _AgentCardAction action,
) async {
  switch (action) {
    case _AgentCardAction.edit:
      await _showAgentEditor(context, initialAgent: agent);
    case _AgentCardAction.activities:
      await _showAgentActivitiesDialog(context, agent);
    case _AgentCardAction.logs:
      await _showAgentCapabilityLogsDialog(context, agent);
    case _AgentCardAction.approvals:
      await _showAgentApprovalsDialog(context, agent);
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

Future<void> _showAgentActivitiesDialog(
  BuildContext context,
  AgentProfile agent,
) {
  final l10n = AppLocalizations.of(context)!;
  return showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) {
      return Consumer<AgentsController>(
        builder: (context, controller, _) {
          final currentAgent = controller.agentById(agent.id) ?? agent;
          final activities = currentAgent.activities;
          return buildOpenHandDialog(
            maxWidth: 820,
            maxHeight: 680,
            child: _AgentDialogScaffold(
              icon: Icons.history_rounded,
              title: l10n.agentsDialogTitleWithName(
                l10n.agentsActivities,
                currentAgent.name,
              ),
              child: activities.isEmpty
                  ? FeatureStateCard.inline(
                      icon: Icons.history_rounded,
                      title: l10n.agentsActivitiesEmptyTitle,
                      body: l10n.agentsListEmptyBody,
                    )
                  : _AgentActivityStream(activities: activities),
            ),
          );
        },
      );
    },
  );
}

class _AgentActivityStream extends StatelessWidget {
  const _AgentActivityStream({required this.activities});

  final List<AgentActivityEvent> activities;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.only(right: 4),
      itemCount: activities.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return _AgentActivityBubble(event: activities[index]);
      },
    );
  }
}

class _AgentActivityBubble extends StatelessWidget {
  const _AgentActivityBubble({required this.event});

  final AgentActivityEvent event;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final type = event.effectiveMessageType;
    final tone = _agentActivityToneColor(cs, type);
    final title = _agentActivityTitle(l10n, event);
    final body = _agentActivitySubtitle(l10n, event);
    final metadata = _agentActivityMetadataChips(event);
    final timeText = event.createdAt == null
        ? ''
        : formatMonthDayHm(event.createdAt!.toLocal());

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: tone.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: tone.withValues(alpha: 0.34)),
          ),
          alignment: Alignment.center,
          child: Icon(_agentActivityIcon(type), color: tone, size: 19),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _AgentActivityTypeChip(
                        label: _agentActivityMessageTypeLabel(l10n, type),
                        color: tone,
                      ),
                      if (timeText.isNotEmpty)
                        Text(
                          timeText,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (body.trim().isNotEmpty) ...[
                    const SizedBox(height: 7),
                    SelectableText(
                      body,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.42),
                    ),
                  ],
                  if (metadata.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: metadata
                          .map((item) => _AgentActivityMetadataChip(text: item))
                          .toList(growable: false),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AgentActivityTypeChip extends StatelessWidget {
  const _AgentActivityTypeChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _AgentActivityMetadataChip extends StatelessWidget {
  const _AgentActivityMetadataChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

Future<void> _showAgentCapabilityLogsDialog(
  BuildContext context,
  AgentProfile agent,
) {
  final l10n = AppLocalizations.of(context)!;
  return showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) {
      return Consumer<AgentsController>(
        builder: (context, controller, _) {
          final currentAgent = controller.agentById(agent.id) ?? agent;
          final events = currentAgent.auditEvents;
          return buildOpenHandDialog(
            maxWidth: 860,
            maxHeight: 700,
            child: _AgentDialogScaffold(
              icon: Icons.receipt_long_rounded,
              title: l10n.agentsDialogTitleWithName(
                l10n.agentsCapabilityLogs,
                currentAgent.name,
              ),
              child: events.isEmpty
                  ? FeatureStateCard.inline(
                      icon: Icons.receipt_long_rounded,
                      title: l10n.agentsLogsEmptyTitle,
                      body: l10n.agentsListEmptyBody,
                    )
                  : _AgentCapabilityLogBody(events: events),
            ),
          );
        },
      );
    },
  );
}

class _AgentCapabilityLogBody extends StatelessWidget {
  const _AgentCapabilityLogBody({required this.events});

  final List<AgentAuditEvent> events;

  @override
  Widget build(BuildContext context) {
    final requests = events.fold<int>(
      0,
      (sum, event) => sum + event.requestCount,
    );
    final tokens = events.fold<int>(0, (sum, event) => sum + event.tokenUsage);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _MetricTile(
              label: openHandLocalizedText(context, zh: '事件', en: 'Events'),
              value: '${events.length}',
            ),
            _MetricTile(
              label: openHandLocalizedText(context, zh: '请求量', en: 'Requests'),
              value: '$requests',
            ),
            _MetricTile(label: 'Token', value: '$tokens'),
          ],
        ),
        const SizedBox(height: 14),
        ListView.separated(
          shrinkWrap: true,
          primary: false,
          itemCount: events.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            return _AgentCapabilityLogTile(event: events[index]);
          },
        ),
      ],
    );
  }
}

class _AgentCapabilityLogTile extends StatelessWidget {
  const _AgentCapabilityLogTile({required this.event});

  final AgentAuditEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final type = _agentAuditCapabilityType(event);
    final color = _agentCapabilityLogColor(cs, type);
    final name = _agentAuditCapabilityName(event);
    final timeText = event.createdAt == null
        ? ''
        : formatMonthDayHm(event.createdAt!.toLocal());
    final metadata = _agentAuditMetadataChips(event);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(
                _agentCapabilityLogIcon(type),
                color: color,
                size: 19,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _AgentActivityTypeChip(
                        label: _agentCapabilityTypeLabel(context, type),
                        color: color,
                      ),
                      if (timeText.isNotEmpty)
                        Text(
                          timeText,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (event.summary.trim().isNotEmpty) ...[
                    const SizedBox(height: 5),
                    SelectableText(
                      event.summary,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (event.requestCount > 0)
                        _AgentActivityMetadataChip(
                          text: openHandLocalizedText(
                            context,
                            zh: '${event.requestCount} 请求',
                            en: '${event.requestCount} requests',
                          ),
                        ),
                      if (event.tokenUsage > 0)
                        _AgentActivityMetadataChip(
                          text: '${event.tokenUsage} Token',
                        ),
                      for (final item in metadata)
                        _AgentActivityMetadataChip(text: item),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showAgentApprovalsDialog(
  BuildContext context,
  AgentProfile agent,
) {
  final l10n = AppLocalizations.of(context)!;
  return showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) {
      return Consumer<AgentsController>(
        builder: (context, controller, _) {
          final currentAgent = controller.agentById(agent.id) ?? agent;
          return buildOpenHandDialog(
            maxWidth: 820,
            maxHeight: 680,
            child: _AgentDialogScaffold(
              icon: Icons.verified_user_rounded,
              title: l10n.agentsDialogTitleWithName(
                l10n.agentsApprovals,
                currentAgent.name,
              ),
              actions: [
                FilledButton.icon(
                  onPressed: () =>
                      _showAgentApprovalRequestDialog(context, currentAgent),
                  icon: const Icon(Icons.add_moderator_outlined),
                  label: Text(
                    openHandLocalizedText(
                      context,
                      zh: '发起审批',
                      en: 'Request approval',
                    ),
                  ),
                ),
              ],
              child: currentAgent.approvals.isEmpty
                  ? FeatureStateCard.inline(
                      icon: Icons.verified_user_outlined,
                      title: l10n.agentsApprovalsEmptyTitle,
                      body: l10n.agentsListEmptyBody,
                    )
                  : _AgentApprovalsBody(
                      approvals: currentAgent.approvals,
                      onApproved: (approval) => _resolveAgentApprovalFromDialog(
                        dialogContext,
                        currentAgent,
                        approval,
                        AgentApprovalStatus.approved,
                      ),
                      onRejected: (approval) => _resolveAgentApprovalFromDialog(
                        dialogContext,
                        currentAgent,
                        approval,
                        AgentApprovalStatus.rejected,
                      ),
                    ),
            ),
          );
        },
      );
    },
  );
}

class _AgentApprovalsBody extends StatelessWidget {
  const _AgentApprovalsBody({
    required this.approvals,
    required this.onApproved,
    required this.onRejected,
  });

  final List<AgentApprovalRequest> approvals;
  final ValueChanged<AgentApprovalRequest> onApproved;
  final ValueChanged<AgentApprovalRequest> onRejected;

  @override
  Widget build(BuildContext context) {
    final pending = approvals
        .where((item) => item.status == AgentApprovalStatus.pending)
        .length;
    final resolved = approvals.length - pending;
    final highRisk = approvals
        .where(
          (item) => _agentApprovalIsHighRisk(_agentApprovalRiskLevel(item)),
        )
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _MetricTile(
              label: openHandLocalizedText(context, zh: '待审批', en: 'Pending'),
              value: '$pending',
            ),
            _MetricTile(
              label: openHandLocalizedText(context, zh: '已处理', en: 'Resolved'),
              value: '$resolved',
            ),
            _MetricTile(
              label: openHandLocalizedText(context, zh: '高风险', en: 'High risk'),
              value: '$highRisk',
            ),
          ],
        ),
        const SizedBox(height: 14),
        ListView.separated(
          shrinkWrap: true,
          primary: false,
          itemCount: approvals.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) => _AgentApprovalRequestCard(
            approval: approvals[index],
            onApproved: () => onApproved(approvals[index]),
            onRejected: () => onRejected(approvals[index]),
          ),
        ),
      ],
    );
  }
}

class _AgentApprovalRequestCard extends StatelessWidget {
  const _AgentApprovalRequestCard({
    required this.approval,
    required this.onApproved,
    required this.onRejected,
  });

  final AgentApprovalRequest approval;
  final VoidCallback onApproved;
  final VoidCallback onRejected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final statusColor = _agentApprovalStatusColor(cs, approval.status);
    final riskLevel = _agentApprovalRiskLevel(approval);
    final riskColor = _agentApprovalRiskColor(cs, riskLevel);
    final metadata = _agentApprovalMetadataChips(approval);
    final timeText = _agentApprovalTimeLabel(context, approval);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(
                _agentApprovalStatusIcon(approval.status),
                color: statusColor,
                size: 19,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _AgentActivityTypeChip(
                        label: _agentApprovalStatusLabel(l10n, approval.status),
                        color: statusColor,
                      ),
                      _AgentActivityTypeChip(
                        label: _agentApprovalRiskLabel(context, riskLevel),
                        color: riskColor,
                      ),
                      if (timeText.isNotEmpty)
                        Text(
                          timeText,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    approval.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (approval.requestedAction.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    SelectableText(
                      approval.requestedAction,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (approval.reason.trim().isNotEmpty) ...[
                    const SizedBox(height: 5),
                    SelectableText(
                      approval.reason,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
                    ),
                  ],
                  if (metadata.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: metadata
                          .map((item) => _AgentActivityMetadataChip(text: item))
                          .toList(growable: false),
                    ),
                  ],
                  if (approval.status == AgentApprovalStatus.pending) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: _AgentApprovalActions(
                        onApproved: onApproved,
                        onRejected: onRejected,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showAgentClusterDialog(BuildContext context, AgentProfile agent) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _AgentClusterDialogContent(agent: agent),
  );
}

class _AgentClusterDialogContent extends StatefulWidget {
  const _AgentClusterDialogContent({required this.agent});

  final AgentProfile agent;

  @override
  State<_AgentClusterDialogContent> createState() =>
      _AgentClusterDialogContentState();
}

class _AgentClusterDialogContentState
    extends State<_AgentClusterDialogContent> {
  final GlobalKey<_AgentClusterSettingsEditorState> _clusterEditorKey =
      GlobalKey<_AgentClusterSettingsEditorState>();
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer<AgentsController>(
      builder: (dialogContext, controller, _) {
        final currentAgent =
            controller.agentById(widget.agent.id) ?? widget.agent;
        final settings = currentAgent.scaleSettings;
        return buildOpenHandDialog(
          maxWidth: 880,
          maxHeight: 700,
          child: _AgentDialogScaffold(
            icon: Icons.account_tree_rounded,
            title: l10n.agentsDialogTitleWithName(
              l10n.agentsCluster,
              currentAgent.name,
            ),
            actions: [
              if (_editing)
                TextButton.icon(
                  onPressed: () => setState(() => _editing = false),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: Text(
                    openHandLocalizedText(
                      context,
                      zh: '返回状态',
                      en: 'Back to status',
                    ),
                  ),
                )
              else
                FilledButton.icon(
                  onPressed: () => setState(() => _editing = true),
                  icon: const Icon(Icons.tune_rounded),
                  label: Text(
                    openHandLocalizedText(
                      context,
                      zh: '调整集群',
                      en: 'Tune cluster',
                    ),
                  ),
                ),
            ],
            footer: _editing
                ? buildOpenHandDialogActionsBar(
                    actions: [
                      OpenHandDialogActionButton.secondary(
                        onPressed: () => setState(() => _editing = false),
                        label: l10n.commonCancel,
                      ),
                      OpenHandDialogActionButton.primary(
                        onPressed: () => _saveClusterSettings(
                          context,
                          controller,
                          currentAgent,
                        ),
                        label: l10n.commonSave,
                      ),
                    ],
                  )
                : null,
            child: AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _editing
                  ? _AgentClusterSettingsEditor(
                      key: _clusterEditorKey,
                      initial: settings,
                    )
                  : _buildClusterStatus(dialogContext, currentAgent),
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveClusterSettings(
    BuildContext context,
    AgentsController controller,
    AgentProfile currentAgent,
  ) async {
    final updated = _clusterEditorKey.currentState?.buildSettings();
    if (updated == null) return;
    final failureMessage = openHandLocalizedText(
      context,
      zh: '集群设置保存失败，请稍后重试。',
      en: 'Failed to save cluster settings. Try again.',
    );
    final saved = await controller.saveScaleSettings(currentAgent.id, updated);
    if (!mounted) return;
    if (saved) {
      setState(() => _editing = false);
    } else {
      OpenHandSnackBar.showError(this.context, failureMessage);
    }
  }

  Widget _buildClusterStatus(BuildContext context, AgentProfile currentAgent) {
    final l10n = AppLocalizations.of(context)!;
    final settings = currentAgent.scaleSettings;
    final idleWorkers = _agentWorkerStatusCount(
      currentAgent,
      AgentWorkerStatus.idle,
    );
    final busyWorkers = _agentWorkerStatusCount(
      currentAgent,
      AgentWorkerStatus.busy,
    );
    final queuedTasks =
        _agentTasksByStatusCount(currentAgent, AgentTaskStatus.backlog) +
        _agentTasksByStatusCount(currentAgent, AgentTaskStatus.ready);
    final blockedTasks =
        _agentTasksByStatusCount(
          currentAgent,
          AgentTaskStatus.waitingApproval,
        ) +
        _agentTasksByStatusCount(currentAgent, AgentTaskStatus.paused);
    return Column(
      key: const ValueKey<String>('cluster-status'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _MetricTile(
              label: openHandLocalizedText(
                context,
                zh: 'Worker',
                en: 'Workers',
              ),
              value: '${currentAgent.workers.length}/${settings.maxWorkers}',
            ),
            _MetricTile(
              label: openHandLocalizedText(
                context,
                zh: '空闲 / 忙碌',
                en: 'Idle / busy',
              ),
              value: '$idleWorkers / $busyWorkers',
            ),
            _MetricTile(
              label: openHandLocalizedText(context, zh: '待执行', en: 'Queued'),
              value: '$queuedTasks',
            ),
            _MetricTile(
              label: openHandLocalizedText(context, zh: '执行中', en: 'Running'),
              value: '${currentAgent.runningTaskCount}',
            ),
            _MetricTile(
              label: openHandLocalizedText(context, zh: '待处理', en: 'Blocked'),
              value: '$blockedTasks',
            ),
            _MetricTile(
              label: openHandLocalizedText(
                context,
                zh: '利用率',
                en: 'Utilization',
              ),
              value: '${(currentAgent.workerUtilization * 100).round()}%',
            ),
          ],
        ),
        const SizedBox(height: 18),
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
              label: _agentPolicyOptionLabel(context, settings.schedulerPolicy),
              color: Theme.of(context).colorScheme.tertiary,
            ),
            _AgentPill(
              icon: Icons.repeat_rounded,
              label:
                  '${_agentPolicyOptionLabel(context, settings.retryPolicy)} · ${settings.maxRetries}',
              color: Theme.of(context).colorScheme.primary,
            ),
            _AgentPill(
              icon: Icons.compare_arrows_rounded,
              label:
                  '${(settings.scaleOutThreshold * 100).round()}% / ${(settings.scaleInThreshold * 100).round()}%',
              color: Theme.of(context).colorScheme.secondary,
            ),
            _AgentPill(
              icon: Icons.low_priority_rounded,
              label: settings.workerRemovalPolicy,
              color: Theme.of(context).colorScheme.tertiary,
            ),
            if (settings.tags.isNotEmpty)
              _AgentPill(
                icon: Icons.label_outline_rounded,
                label: settings.tags.join(', '),
                color: Theme.of(context).colorScheme.primary,
              ),
          ],
        ),
        const SizedBox(height: 18),
        if (currentAgent.workers.isEmpty)
          FeatureStateCard.inline(
            icon: Icons.memory_rounded,
            title: l10n.agentsNoWorkersTitle,
            body: l10n.agentsNoWorkersBody,
          )
        else
          ...currentAgent.workers.map(
            (worker) =>
                _AgentWorkerStatusTile(agent: currentAgent, worker: worker),
          ),
      ],
    );
  }
}

class _AgentWorkerStatusTile extends StatelessWidget {
  const _AgentWorkerStatusTile({required this.agent, required this.worker});

  final AgentProfile agent;
  final AgentWorker worker;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final statusColor = switch (worker.status) {
      AgentWorkerStatus.idle => colors.primary,
      AgentWorkerStatus.busy => colors.tertiary,
      AgentWorkerStatus.draining => colors.secondary,
      AgentWorkerStatus.offline => colors.outline,
    };
    final currentTask = _agentWorkerCurrentTaskLabel(l10n, agent, worker);
    final labelLine = [
      l10n.agentsWorkerSubtitle(
        _agentWorkerStatusLabel(l10n, worker.status),
        worker.executedTaskCount,
        worker.priority,
      ),
      if (currentTask.isNotEmpty) currentTask,
      if (worker.labels.isNotEmpty) worker.labels.join(', '),
    ].where((item) => item.trim().isNotEmpty).join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                worker.status == AgentWorkerStatus.busy
                    ? Icons.sync_rounded
                    : Icons.check_circle_outline_rounded,
                color: statusColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            worker.name.isEmpty ? worker.id : worker.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          '${(worker.busyScore * 100).round()}%',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      labelLine,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: worker.busyScore.clamp(0, 1).toDouble(),
                      minHeight: 5,
                      borderRadius: BorderRadius.circular(999),
                      color: statusColor,
                      backgroundColor: colors.surfaceContainerHighest,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentClusterSettingsEditor extends StatefulWidget {
  const _AgentClusterSettingsEditor({super.key, required this.initial});

  final AgentScaleSettings initial;

  @override
  State<_AgentClusterSettingsEditor> createState() =>
      _AgentClusterSettingsEditorState();
}

class _AgentClusterSettingsEditorState
    extends State<_AgentClusterSettingsEditor> {
  late final TextEditingController _tagInput;
  late int _minWorkers;
  late int _maxWorkers;
  late int _maxRetries;
  late double _scaleOutThreshold;
  late double _scaleInThreshold;
  late String _schedulerPolicy;
  late String _workerRemovalPolicy;
  late String _retryPolicy;
  late List<String> _tags;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _minWorkers = initial.minWorkers;
    _maxWorkers = initial.maxWorkers;
    _maxRetries = initial.maxRetries;
    _scaleOutThreshold = initial.scaleOutThreshold.clamp(0, 1).toDouble();
    _scaleInThreshold = initial.scaleInThreshold.clamp(0, 1).toDouble();
    _schedulerPolicy =
        _agentSchedulerPolicyOptions.contains(initial.schedulerPolicy)
        ? initial.schedulerPolicy
        : _agentSchedulerPolicyOptions.first;
    _workerRemovalPolicy =
        _agentWorkerRemovalPolicyOptions.contains(initial.workerRemovalPolicy)
        ? initial.workerRemovalPolicy
        : _agentWorkerRemovalPolicyOptions.first;
    _retryPolicy = _agentRetryPolicyOptions.contains(initial.retryPolicy)
        ? initial.retryPolicy
        : _agentRetryPolicyOptions.first;
    _tagInput = TextEditingController();
    _tags = List<String>.from(initial.tags);
  }

  @override
  void dispose() {
    _tagInput.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      key: const ValueKey<String>('cluster-editor'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FormGrid(
          children: [
            _clusterNumberStepper(
              l10n.agentsMinWorkersLabel,
              _minWorkers,
              (value) =>
                  setState(() => _minWorkers = value.clamp(0, _maxWorkers)),
            ),
            _clusterNumberStepper(
              l10n.agentsMaxWorkersLabel,
              _maxWorkers,
              (value) => setState(() {
                _maxWorkers = value.clamp(1, 999);
                if (_minWorkers > _maxWorkers) _minWorkers = _maxWorkers;
              }),
            ),
            _clusterNumberStepper(
              l10n.agentsMaxRetriesLabel,
              _maxRetries,
              (value) => setState(() => _maxRetries = value.clamp(0, 20)),
            ),
            _FormGridItem(
              fullWidth: true,
              child: _clusterTagEditor(
                label: openHandLocalizedText(
                  context,
                  zh: 'Worker 标签',
                  en: 'Worker tags',
                ),
              ),
            ),
            _clusterRatioSlider(
              openHandLocalizedText(
                context,
                zh: '扩容阈值',
                en: 'Scale-out threshold',
              ),
              _scaleOutThreshold,
              (value) => setState(() => _scaleOutThreshold = value),
            ),
            _clusterRatioSlider(
              openHandLocalizedText(
                context,
                zh: '缩容阈值',
                en: 'Scale-in threshold',
              ),
              _scaleInThreshold,
              (value) => setState(() => _scaleInThreshold = value),
            ),
            _clusterPolicyDropdown(
              label: l10n.agentsSchedulerPolicyLabel,
              value: _schedulerPolicy,
              values: _agentSchedulerPolicyOptions,
              onChanged: (value) => setState(() => _schedulerPolicy = value),
            ),
            _clusterPolicyDropdown(
              label: openHandLocalizedText(
                context,
                zh: 'Worker 移出策略',
                en: 'Worker removal policy',
              ),
              value: _workerRemovalPolicy,
              values: _agentWorkerRemovalPolicyOptions,
              onChanged: (value) =>
                  setState(() => _workerRemovalPolicy = value),
            ),
            _clusterPolicyDropdown(
              label: openHandLocalizedText(
                context,
                zh: '重试策略',
                en: 'Retry policy',
              ),
              value: _retryPolicy,
              values: _agentRetryPolicyOptions,
              onChanged: (value) => setState(() => _retryPolicy = value),
            ),
          ],
        ),
      ],
    );
  }

  Widget _clusterNumberStepper(
    String label,
    int value,
    ValueChanged<int> onChanged,
  ) {
    return _FormGridItem(
      child: InputDecorator(
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
      ),
    );
  }

  Widget _clusterRatioSlider(
    String label,
    double value,
    ValueChanged<double> onChanged,
  ) {
    final normalized = value.clamp(0, 1).toDouble();
    return _FormGridItem(
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Row(
          children: [
            Expanded(
              child: Slider(
                value: normalized,
                divisions: 20,
                label: '${(normalized * 100).round()}%',
                onChanged: onChanged,
              ),
            ),
            SizedBox(
              width: 44,
              child: Text(
                '${(normalized * 100).round()}%',
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _clusterPolicyDropdown({
    required String label,
    required String value,
    required List<String> values,
    required ValueChanged<String> onChanged,
  }) {
    final effectiveValue = values.contains(value) ? value : values.first;
    return _FormGridItem(
      child: DropdownButtonFormField<String>(
        initialValue: effectiveValue,
        decoration: InputDecoration(labelText: label),
        items: values
            .map(
              (item) => DropdownMenuItem(
                value: item,
                child: Text(_agentPolicyOptionLabel(context, item)),
              ),
            )
            .toList(),
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
      ),
    );
  }

  AgentScaleSettings buildSettings() {
    return AgentScaleSettings(
      minWorkers: _minWorkers,
      maxWorkers: _maxWorkers,
      scaleOutThreshold: _scaleOutThreshold,
      scaleInThreshold: _scaleInThreshold,
      workerRemovalPolicy: _workerRemovalPolicy,
      retryPolicy: _retryPolicy,
      maxRetries: _maxRetries,
      schedulerPolicy: _schedulerPolicy,
      tags: _dedupeClusterTags(_tags),
    );
  }

  Widget _clusterTagEditor({required String label}) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _tagInput,
                  decoration: InputDecoration(
                    hintText: openHandLocalizedText(
                      context,
                      zh: '输入后点击添加',
                      en: 'Enter text, then add',
                    ),
                  ),
                  onSubmitted: (_) => _addClusterTag(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.tonalIcon(
                key: const ValueKey<String>('agent-cluster-tag-add'),
                onPressed: _addClusterTag,
                icon: const Icon(Icons.add_rounded),
                label: Text(
                  openHandLocalizedText(context, zh: '添加', en: 'Add'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _AnimatedReorderableChipStrip(
            values: _tags,
            emptyText: openHandLocalizedText(
              context,
              zh: '暂无 Worker 标签。',
              en: 'No worker tags yet.',
            ),
            keyPrefix: 'cluster-tag',
            onRemove: (tag) => setState(() => _tags.remove(tag)),
            onReorder: (oldIndex, newIndex) =>
                setState(() => _reorderClusterTag(oldIndex, newIndex)),
          ),
        ],
      ),
    );
  }

  void _addClusterTag() {
    final value = _tagInput.text.trim();
    if (value.isEmpty) return;
    setState(() {
      if (!_tags.any((tag) => tag.toLowerCase() == value.toLowerCase())) {
        _tags.add(value);
      }
      _tagInput.clear();
    });
  }

  void _reorderClusterTag(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _tags.length) return;
    final targetIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    if (targetIndex < 0 || targetIndex >= _tags.length) return;
    final item = _tags.removeAt(oldIndex);
    _tags.insert(targetIndex, item);
  }

  List<String> _dedupeClusterTags(List<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final raw in values) {
      final value = raw.trim();
      if (value.isEmpty) continue;
      if (seen.add(value.toLowerCase())) result.add(value);
    }
    return result;
  }
}

Future<void> _showAgentTasksDialog(BuildContext context, AgentProfile agent) {
  final l10n = AppLocalizations.of(context)!;
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => Consumer<AgentsController>(
      builder: (context, controller, _) {
        final currentAgent = controller.agentById(agent.id) ?? agent;
        return buildOpenHandDialog(
          maxWidth: 960,
          maxHeight: 720,
          child: _AgentDialogScaffold(
            icon: Icons.task_alt_rounded,
            title: l10n.agentsDialogTitleWithName(
              l10n.agentsTaskDesk,
              currentAgent.name,
            ),
            actions: [
              FilledButton.icon(
                onPressed: () => _showPublishTaskDialog(context, currentAgent),
                icon: const Icon(Icons.add_task_rounded),
                label: Text(l10n.agentsPublishTask),
              ),
            ],
            child: currentAgent.tasks.isEmpty
                ? FeatureStateCard.inline(
                    icon: Icons.task_alt_rounded,
                    title: l10n.agentsNoTasksTitle,
                    body: l10n.agentsNoTasksBody,
                  )
                : _AgentTasksBody(
                    agent: currentAgent,
                    tasks: currentAgent.tasks,
                  ),
          ),
        );
      },
    ),
  );
}

class _AgentTasksBody extends StatelessWidget {
  const _AgentTasksBody({required this.agent, required this.tasks});

  final AgentProfile agent;
  final List<AgentTask> tasks;

  @override
  Widget build(BuildContext context) {
    final active = tasks
        .where((task) => _agentTaskIsActive(task.status))
        .length;
    final completed = tasks
        .where((task) => task.status == AgentTaskStatus.completed)
        .length;
    final averageProgress = tasks.isEmpty
        ? 0
        : (tasks.fold<double>(0, (sum, task) => sum + task.progress) /
                  tasks.length *
                  100)
              .round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _MetricTile(
              label: openHandLocalizedText(context, zh: '任务', en: 'Tasks'),
              value: '${tasks.length}',
            ),
            _MetricTile(
              label: openHandLocalizedText(context, zh: '进行中', en: 'Active'),
              value: '$active',
            ),
            _MetricTile(
              label: openHandLocalizedText(context, zh: '已完成', en: 'Completed'),
              value: '$completed',
            ),
            _MetricTile(
              label: openHandLocalizedText(
                context,
                zh: '平均进度',
                en: 'Avg. progress',
              ),
              value: '$averageProgress%',
            ),
          ],
        ),
        const SizedBox(height: 14),
        ListView.separated(
          shrinkWrap: true,
          primary: false,
          itemCount: tasks.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            return _AgentTaskCard(agent: agent, task: tasks[index]);
          },
        ),
      ],
    );
  }
}

class _AgentTaskCard extends StatelessWidget {
  const _AgentTaskCard({required this.agent, required this.task});

  final AgentProfile agent;
  final AgentTask task;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final statusColor = _agentTaskStatusColor(cs, task.status);
    final worker = _agentTaskAssignedWorkerLabel(l10n, task);
    final created = task.createdAt == null
        ? ''
        : formatMonthDayHm(task.createdAt!.toLocal());
    final metadata = _agentTaskMetadataChips(task);
    final progress = task.progress.clamp(0, 1).toDouble();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showAgentTaskDetailDialog(context, agent, task),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    _agentTaskStatusIcon(task.status),
                    color: statusColor,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _AgentActivityTypeChip(
                            label: _agentTaskStatusLabel(l10n, task.status),
                            color: statusColor,
                          ),
                          if (worker.isNotEmpty)
                            _AgentActivityMetadataChip(text: worker),
                          if (created.isNotEmpty)
                            Text(
                              created,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        task.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (task.description.trim().isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          task.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.35,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 7,
                                color: statusColor,
                                backgroundColor: cs.surfaceContainerHighest,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 46,
                            child: Text(
                              '${(progress * 100).round()}%',
                              textAlign: TextAlign.end,
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (task.result.trim().isNotEmpty ||
                          task.note.trim().isNotEmpty ||
                          metadata.isNotEmpty) ...[
                        const SizedBox(height: 9),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (task.result.trim().isNotEmpty)
                              _AgentActivityMetadataChip(
                                text: openHandLocalizedText(
                                  context,
                                  zh: '结果: ${task.result.trim()}',
                                  en: 'Result: ${task.result.trim()}',
                                ),
                              ),
                            if (task.note.trim().isNotEmpty)
                              _AgentActivityMetadataChip(
                                text: openHandLocalizedText(
                                  context,
                                  zh: '备注: ${task.note.trim()}',
                                  en: 'Note: ${task.note.trim()}',
                                ),
                              ),
                            for (final item in metadata)
                              _AgentActivityMetadataChip(text: item),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _AgentTaskActions(agent: agent, task: task),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _showAgentTaskDetailDialog(
  BuildContext context,
  AgentProfile agent,
  AgentTask task,
) {
  final l10n = AppLocalizations.of(context)!;
  final assignedWorker = _agentTaskAssignedWorkerLabel(l10n, task);
  final extraText = const JsonEncoder.withIndent(
    '  ',
  ).convert(_agentTaskExtraDisplayJson(task.extra));
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => buildOpenHandDialog(
      maxWidth: 880,
      maxHeight: 720,
      child: _AgentDialogScaffold(
        icon: Icons.task_alt_rounded,
        title: openHandLocalizedText(context, zh: '任务详情', en: 'Task details'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MetricTile(
                  label: openHandLocalizedText(context, zh: '状态', en: 'Status'),
                  value: _agentTaskStatusLabel(l10n, task.status),
                ),
                _MetricTile(
                  label: openHandLocalizedText(
                    context,
                    zh: '进度',
                    en: 'Progress',
                  ),
                  value: '${(task.progress * 100).round()}%',
                ),
                _MetricTile(
                  label: openHandLocalizedText(
                    context,
                    zh: 'Worker',
                    en: 'Worker',
                  ),
                  value: assignedWorker.isEmpty ? '-' : assignedWorker,
                ),
              ],
            ),
            const SizedBox(height: 18),
            _AgentTaskDetailBlock(
              title: openHandLocalizedText(context, zh: '标题', en: 'Title'),
              body: task.title,
            ),
            _AgentTaskDetailGrid(
              children: [
                _AgentTaskDetailBlock(
                  title: 'ID',
                  body: task.id,
                  compact: true,
                ),
                _AgentTaskDetailBlock(
                  title: openHandLocalizedText(
                    context,
                    zh: '创建时间',
                    en: 'Created',
                  ),
                  body: _agentDateTimeLabel(task.createdAt),
                  compact: true,
                ),
                _AgentTaskDetailBlock(
                  title: openHandLocalizedText(
                    context,
                    zh: '更新时间',
                    en: 'Updated',
                  ),
                  body: _agentDateTimeLabel(task.updatedAt),
                  compact: true,
                ),
                _AgentTaskDetailBlock(
                  title: openHandLocalizedText(
                    context,
                    zh: '分配 Worker',
                    en: 'Assigned worker',
                  ),
                  body: assignedWorker,
                  compact: true,
                ),
              ],
            ),
            _AgentTaskDetailBlock(
              title: l10n.agentsDescriptionLabel,
              body: task.description,
            ),
            _AgentTaskDetailBlock(
              title: l10n.agentsContentLabel,
              body: task.content,
            ),
            _AgentTaskDetailBlock(
              title: openHandLocalizedText(
                context,
                zh: '任务结果',
                en: 'Task result',
              ),
              body: task.result,
            ),
            _AgentTaskDetailBlock(title: l10n.agentsNoteLabel, body: task.note),
            _AgentTaskDetailBlock(
              title: 'extra',
              body: extraText,
              monospace: true,
            ),
          ],
        ),
      ),
    ),
  );
}

class _AgentTaskActions extends StatelessWidget {
  const _AgentTaskActions({required this.agent, required this.task});

  final AgentProfile agent;
  final AgentTask task;

  @override
  Widget build(BuildContext context) {
    final canPause = _agentTaskCanPause(task.status);
    final canComplete = _agentTaskCanComplete(task.status);
    final canStop = _agentTaskCanStop(task.status);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _AgentSmallIconButton(
          icon: Icons.info_outline_rounded,
          tooltip: openHandLocalizedText(
            context,
            zh: '查看任务详情',
            en: 'View task details',
          ),
          onPressed: () => _showAgentTaskDetailDialog(context, agent, task),
        ),
        const SizedBox(width: 6),
        if (task.status == AgentTaskStatus.paused)
          _AgentSmallIconButton(
            icon: Icons.play_arrow_rounded,
            tooltip: openHandLocalizedText(
              context,
              zh: '恢复任务',
              en: 'Resume task',
            ),
            onPressed: () => _updateAgentTaskFromDesk(
              context,
              agent,
              task,
              status: AgentTaskStatus.ready,
              activityKind: 'task_resumed',
              activityTitle: 'task_resumed',
            ),
          )
        else if (canPause)
          _AgentSmallIconButton(
            icon: Icons.pause_rounded,
            tooltip: openHandLocalizedText(
              context,
              zh: '暂停任务',
              en: 'Pause task',
            ),
            onPressed: () => _updateAgentTaskFromDesk(
              context,
              agent,
              task,
              status: AgentTaskStatus.paused,
              activityKind: 'task_paused',
              activityTitle: 'task_paused',
            ),
          ),
        if (canComplete) ...[
          const SizedBox(width: 6),
          _AgentSmallIconButton(
            icon: Icons.done_rounded,
            tooltip: openHandLocalizedText(
              context,
              zh: '完成并回填结果',
              en: 'Complete with result',
            ),
            onPressed: () => _showCompleteTaskDialog(context, agent, task),
          ),
        ],
        if (canStop) ...[
          const SizedBox(width: 6),
          _AgentSmallIconButton(
            icon: Icons.cancel_outlined,
            tooltip: openHandLocalizedText(
              context,
              zh: '取消任务',
              en: 'Cancel task',
            ),
            onPressed: () => _confirmAgentTaskStatus(
              context,
              agent,
              task,
              status: AgentTaskStatus.canceled,
              activityKind: 'task_canceled',
              activityTitle: 'task_canceled',
              titleZh: '取消任务',
              titleEn: 'Cancel task',
              messageZh: '确认取消「${task.title}」吗？',
              messageEn: 'Cancel "${task.title}"?',
            ),
          ),
          const SizedBox(width: 6),
          _AgentSmallIconButton(
            icon: Icons.gpp_bad_outlined,
            tooltip: openHandLocalizedText(
              context,
              zh: '终止任务',
              en: 'Terminate task',
            ),
            onPressed: () => _confirmAgentTaskStatus(
              context,
              agent,
              task,
              status: AgentTaskStatus.failed,
              activityKind: 'task_terminated',
              activityTitle: 'task_terminated',
              titleZh: '终止任务',
              titleEn: 'Terminate task',
              messageZh: '确认将「${task.title}」标记为异常终止吗？',
              messageEn: 'Mark "${task.title}" as terminated?',
            ),
          ),
        ],
      ],
    );
  }
}

class _AgentSmallIconButton extends StatelessWidget {
  const _AgentSmallIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 34,
        height: 34,
        child: IconButton.filledTonal(
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          iconSize: 18,
          icon: Icon(icon),
        ),
      ),
    );
  }
}

bool _agentTaskCanPause(AgentTaskStatus status) {
  return switch (status) {
    AgentTaskStatus.backlog ||
    AgentTaskStatus.ready ||
    AgentTaskStatus.running => true,
    AgentTaskStatus.waitingApproval ||
    AgentTaskStatus.paused ||
    AgentTaskStatus.completed ||
    AgentTaskStatus.failed ||
    AgentTaskStatus.canceled => false,
  };
}

bool _agentTaskCanComplete(AgentTaskStatus status) {
  return switch (status) {
    AgentTaskStatus.backlog ||
    AgentTaskStatus.ready ||
    AgentTaskStatus.running => true,
    AgentTaskStatus.waitingApproval ||
    AgentTaskStatus.paused ||
    AgentTaskStatus.completed ||
    AgentTaskStatus.failed ||
    AgentTaskStatus.canceled => false,
  };
}

bool _agentTaskCanStop(AgentTaskStatus status) {
  return switch (status) {
    AgentTaskStatus.backlog ||
    AgentTaskStatus.ready ||
    AgentTaskStatus.running ||
    AgentTaskStatus.waitingApproval ||
    AgentTaskStatus.paused => true,
    AgentTaskStatus.completed ||
    AgentTaskStatus.failed ||
    AgentTaskStatus.canceled => false,
  };
}

bool _agentTaskIsActive(AgentTaskStatus status) {
  return switch (status) {
    AgentTaskStatus.backlog ||
    AgentTaskStatus.ready ||
    AgentTaskStatus.running ||
    AgentTaskStatus.waitingApproval ||
    AgentTaskStatus.paused => true,
    AgentTaskStatus.completed ||
    AgentTaskStatus.failed ||
    AgentTaskStatus.canceled => false,
  };
}

IconData _agentTaskStatusIcon(AgentTaskStatus status) {
  return switch (status) {
    AgentTaskStatus.backlog => Icons.inbox_rounded,
    AgentTaskStatus.ready => Icons.playlist_add_check_rounded,
    AgentTaskStatus.running => Icons.bolt_rounded,
    AgentTaskStatus.waitingApproval => Icons.verified_user_outlined,
    AgentTaskStatus.paused => Icons.pause_circle_outline_rounded,
    AgentTaskStatus.completed => Icons.check_circle_rounded,
    AgentTaskStatus.failed => Icons.error_outline_rounded,
    AgentTaskStatus.canceled => Icons.cancel_outlined,
  };
}

Color _agentTaskStatusColor(ColorScheme cs, AgentTaskStatus status) {
  return switch (status) {
    AgentTaskStatus.running => cs.primary,
    AgentTaskStatus.ready || AgentTaskStatus.backlog => cs.secondary,
    AgentTaskStatus.waitingApproval => cs.tertiary,
    AgentTaskStatus.paused => cs.onSurfaceVariant,
    AgentTaskStatus.completed => cs.tertiary,
    AgentTaskStatus.failed || AgentTaskStatus.canceled => cs.error,
  };
}

List<String> _agentTaskMetadataChips(AgentTask task) {
  const keys = <String>[
    'assigned_worker_id',
    'priority',
    'schedule',
    'retryable',
    'deadline',
    'source',
  ];
  final chips = <String>[];
  for (final key in keys) {
    final text = _agentMetadataChipText(key, task.extra[key]);
    if (text != null) chips.add(text);
    if (chips.length >= 4) break;
  }
  return chips;
}

Future<void> _updateAgentTaskFromDesk(
  BuildContext context,
  AgentProfile agent,
  AgentTask task, {
  required AgentTaskStatus status,
  required String activityKind,
  required String activityTitle,
  String note = '',
  String result = '',
}) async {
  final updated = await context.read<AgentsController>().updateTaskState(
    agent.id,
    task.id,
    status: status,
    note: note.trim().isEmpty ? null : note.trim(),
    result: result.trim().isEmpty ? null : result.trim(),
    activityKind: activityKind,
    activityTitle: activityTitle,
  );
  if (updated == null && context.mounted) {
    OpenHandSnackBar.showError(
      context,
      openHandLocalizedText(
        context,
        zh: '任务状态已变化，请刷新后再试。',
        en: 'Task state changed. Refresh and try again.',
      ),
    );
  }
}

Future<void> _confirmAgentTaskStatus(
  BuildContext context,
  AgentProfile agent,
  AgentTask task, {
  required AgentTaskStatus status,
  required String activityKind,
  required String activityTitle,
  required String titleZh,
  required String titleEn,
  required String messageZh,
  required String messageEn,
}) async {
  final confirmed = await showOpenHandConfirmDialog(
    context: context,
    title: openHandLocalizedText(context, zh: titleZh, en: titleEn),
    message: openHandLocalizedText(context, zh: messageZh, en: messageEn),
    confirmLabel: openHandLocalizedText(context, zh: '确认', en: 'Confirm'),
    destructive:
        status == AgentTaskStatus.failed || status == AgentTaskStatus.canceled,
  );
  if (confirmed && context.mounted) {
    await _updateAgentTaskFromDesk(
      context,
      agent,
      task,
      status: status,
      activityKind: activityKind,
      activityTitle: activityTitle,
    );
  }
}

Future<void> _showCompleteTaskDialog(
  BuildContext context,
  AgentProfile agent,
  AgentTask task,
) async {
  final l10n = AppLocalizations.of(context)!;
  final result = TextEditingController(text: task.result);
  final note = TextEditingController(text: task.note);
  try {
    final submitted = await showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) => buildOpenHandDialog(
        maxWidth: 680,
        child: _AgentDialogScaffold(
          icon: Icons.done_all_rounded,
          title: openHandLocalizedText(
            context,
            zh: '完成任务',
            en: 'Complete task',
          ),
          footer: buildOpenHandDialogActionsBar(
            actions: [
              OpenHandDialogActionButton.secondary(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                label: l10n.commonCancel,
              ),
              OpenHandDialogActionButton.primary(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                label: openHandLocalizedText(context, zh: '完成', en: 'Complete'),
              ),
            ],
          ),
          child: Column(
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  task.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: result,
                minLines: 4,
                maxLines: 8,
                decoration: InputDecoration(
                  labelText: openHandLocalizedText(
                    context,
                    zh: '任务结果',
                    en: 'Task result',
                  ),
                ),
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
      final resultText = result.text.trim();
      if (resultText.isEmpty) {
        OpenHandSnackBar.showInfo(
          context,
          openHandLocalizedText(
            context,
            zh: '请先填写任务结果。',
            en: 'Enter a task result first.',
          ),
        );
        return;
      }
      await _updateAgentTaskFromDesk(
        context,
        agent,
        task,
        status: AgentTaskStatus.completed,
        note: note.text,
        result: resultText,
        activityKind: 'task_completed',
        activityTitle: 'task_completed',
      );
    }
  } finally {
    result.dispose();
    note.dispose();
  }
}

Future<void> _showAgentAuditDialog(BuildContext context, AgentProfile agent) {
  final l10n = AppLocalizations.of(context)!;
  final report = _AgentAuditReportSummary.fromAgent(agent);
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => buildOpenHandDialog(
      maxWidth: 860,
      maxHeight: 700,
      child: _AgentDialogScaffold(
        icon: Icons.analytics_rounded,
        title: l10n.agentsDialogTitleWithName(
          l10n.agentsAuditReport,
          agent.name,
        ),
        child: _AgentAuditReportBody(agent: agent, report: report),
      ),
    ),
  );
}

Future<void> _showAgentKpiDialog(BuildContext context, AgentProfile agent) {
  final l10n = AppLocalizations.of(context)!;
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => Consumer<AgentsController>(
      builder: (context, controller, _) {
        final currentAgent = controller.agentById(agent.id) ?? agent;
        return buildOpenHandDialog(
          maxWidth: 860,
          maxHeight: 680,
          child: _AgentDialogScaffold(
            icon: Icons.flag_rounded,
            title: l10n.agentsDialogTitleWithName(
              l10n.agentsKpi,
              currentAgent.name,
            ),
            actions: [
              FilledButton.icon(
                onPressed: () async {
                  final draft = await _showAgentKpiEditorDialog(context);
                  if (draft == null || !context.mounted) return;
                  await context.read<AgentsController>().saveKpi(
                    currentAgent.id,
                    draft,
                  );
                },
                icon: const Icon(Icons.add_rounded),
                label: Text(
                  openHandLocalizedText(context, zh: '新增 KPI', en: 'Add KPI'),
                ),
              ),
            ],
            child: currentAgent.kpis.isEmpty
                ? FeatureStateCard.inline(
                    icon: Icons.flag_outlined,
                    title: l10n.agentsNoKpiTitle,
                    body: l10n.agentsNoKpiBody,
                  )
                : _AgentKpiBody(agent: currentAgent, kpis: currentAgent.kpis),
          ),
        );
      },
    ),
  );
}

class _AgentKpiBody extends StatelessWidget {
  const _AgentKpiBody({required this.agent, required this.kpis});

  final AgentProfile agent;
  final List<AgentKpiItem> kpis;

  @override
  Widget build(BuildContext context) {
    final tracking = kpis
        .where((item) => item.status.trim().toLowerCase() == 'tracking')
        .length;
    final atRisk = kpis
        .where((item) => item.status.trim().toLowerCase() == 'at_risk')
        .length;
    final done = kpis
        .where((item) => item.status.trim().toLowerCase() == 'done')
        .length;
    final averageProgress = kpis.isEmpty
        ? 0
        : (kpis.fold<double>(0, (sum, item) => sum + item.progress) /
                  kpis.length *
                  100)
              .round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _MetricTile(
              label: openHandLocalizedText(context, zh: 'KPI', en: 'KPI'),
              value: '${kpis.length}',
            ),
            _MetricTile(
              label: openHandLocalizedText(context, zh: '跟进中', en: 'Tracking'),
              value: '$tracking',
            ),
            _MetricTile(
              label: openHandLocalizedText(context, zh: '有风险', en: 'At risk'),
              value: '$atRisk',
            ),
            _MetricTile(
              label: openHandLocalizedText(context, zh: '已完成', en: 'Done'),
              value: '$done',
            ),
            _MetricTile(
              label: openHandLocalizedText(
                context,
                zh: '平均进度',
                en: 'Avg. progress',
              ),
              value: '$averageProgress%',
            ),
          ],
        ),
        const SizedBox(height: 14),
        ListView.separated(
          shrinkWrap: true,
          primary: false,
          itemCount: kpis.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            return _AgentKpiCard(agent: agent, item: kpis[index]);
          },
        ),
      ],
    );
  }
}

class _AgentKpiCard extends StatelessWidget {
  const _AgentKpiCard({required this.agent, required this.item});

  final AgentProfile agent;
  final AgentKpiItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final statusColor = _agentKpiStatusColor(cs, item.status);
    final updated = item.updatedAt == null
        ? ''
        : formatMonthDayHm(item.updatedAt!.toLocal());
    final metadata = _agentKpiMetadataChips(item);
    final progress = item.progress.clamp(0, 1).toDouble();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(
                _agentKpiStatusIcon(item.status),
                color: statusColor,
                size: 19,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _AgentActivityTypeChip(
                        label: _agentKpiStatusLabel(context, item.status),
                        color: statusColor,
                      ),
                      if (updated.isNotEmpty)
                        Text(
                          updated,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (item.target.trim().isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      item.target,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ],
                  if (item.plan.trim().isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      item.plan,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 7,
                            color: statusColor,
                            backgroundColor: cs.surfaceContainerHighest,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 46,
                        child: Text(
                          '${(progress * 100).round()}%',
                          textAlign: TextAlign.end,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (metadata.isNotEmpty) ...[
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final chip in metadata)
                          _AgentActivityMetadataChip(text: chip),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AgentSmallIconButton(
                  icon: Icons.edit_rounded,
                  tooltip: openHandLocalizedText(
                    context,
                    zh: '编辑 KPI',
                    en: 'Edit KPI',
                  ),
                  onPressed: () => _editAgentKpi(context, agent, item),
                ),
                const SizedBox(width: 6),
                _AgentSmallIconButton(
                  icon: Icons.delete_outline_rounded,
                  tooltip: openHandLocalizedText(
                    context,
                    zh: '删除 KPI',
                    en: 'Delete KPI',
                  ),
                  onPressed: () => _deleteAgentKpi(context, agent, item),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<AgentKpiItem?> _showAgentKpiEditorDialog(
  BuildContext context, {
  AgentKpiItem? initial,
}) {
  return showAnimatedDialog<AgentKpiItem>(
    context: context,
    builder: (_) => _AgentKpiEditorDialog(initial: initial),
  );
}

Future<void> _editAgentKpi(
  BuildContext context,
  AgentProfile agent,
  AgentKpiItem item,
) async {
  final draft = await _showAgentKpiEditorDialog(context, initial: item);
  if (draft == null || !context.mounted) return;
  await context.read<AgentsController>().saveKpi(agent.id, draft);
}

Future<void> _deleteAgentKpi(
  BuildContext context,
  AgentProfile agent,
  AgentKpiItem item,
) async {
  final confirmed = await showOpenHandConfirmDialog(
    context: context,
    title: openHandLocalizedText(context, zh: '删除 KPI', en: 'Delete KPI'),
    message: openHandLocalizedText(
      context,
      zh: '确认删除「${item.name}」吗？',
      en: 'Delete "${item.name}"?',
    ),
    confirmLabel: openHandLocalizedText(context, zh: '删除', en: 'Delete'),
    destructive: true,
  );
  if (confirmed && context.mounted) {
    await context.read<AgentsController>().deleteKpi(agent.id, item.id);
  }
}

class _AgentKpiEditorDialog extends StatefulWidget {
  const _AgentKpiEditorDialog({this.initial});

  final AgentKpiItem? initial;

  @override
  State<_AgentKpiEditorDialog> createState() => _AgentKpiEditorDialogState();
}

class _AgentKpiEditorDialogState extends State<_AgentKpiEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _target;
  late final TextEditingController _plan;
  late final List<_KeyValueDraft> _extraEntries;
  late double _progress;
  late String _status;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(text: initial?.name ?? '');
    _target = TextEditingController(text: initial?.target ?? '');
    _plan = TextEditingController(text: initial?.plan ?? '');
    _extraEntries = _keyValueEntriesFromMap(initial?.extra);
    _progress = (initial?.progress ?? 0).clamp(0, 1).toDouble();
    _status = _agentKpiStatusOptions.contains(initial?.status)
        ? initial!.status
        : _agentKpiStatusOptions.first;
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _plan.dispose();
    for (final entry in _extraEntries) {
      entry.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return buildOpenHandDialog(
      maxWidth: 680,
      child: _AgentDialogScaffold(
        icon: Icons.flag_rounded,
        title: widget.initial == null
            ? openHandLocalizedText(context, zh: '新增 KPI', en: 'Add KPI')
            : openHandLocalizedText(context, zh: '编辑 KPI', en: 'Edit KPI'),
        footer: buildOpenHandDialogActionsBar(
          actions: [
            OpenHandDialogActionButton.secondary(
              onPressed: () => Navigator.of(context).pop(),
              label: l10n.commonCancel,
            ),
            OpenHandDialogActionButton.primary(
              onPressed: _name.text.trim().isEmpty ? null : _submitKpi,
              label: l10n.commonSave,
            ),
          ],
        ),
        child: Column(
          children: [
            TextField(
              controller: _name,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: l10n.agentsFieldName),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _target,
              decoration: InputDecoration(labelText: l10n.agentsFieldTarget),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _plan,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: openHandLocalizedText(
                  context,
                  zh: '推进计划',
                  en: 'Plan',
                ),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: InputDecoration(
                labelText: openHandLocalizedText(
                  context,
                  zh: '状态',
                  en: 'Status',
                ),
              ),
              items: [
                for (final value in _agentKpiStatusOptions)
                  DropdownMenuItem(
                    value: value,
                    child: Text(_agentKpiStatusLabel(context, value)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _status = value);
              },
            ),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: InputDecoration(
                labelText: openHandLocalizedText(
                  context,
                  zh: '进度',
                  en: 'Progress',
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _progress,
                      divisions: 20,
                      label: '${(_progress * 100).round()}%',
                      onChanged: (value) => setState(() => _progress = value),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text(
                      '${(_progress * 100).round()}%',
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _AgentKeyValueEditor(
              title: openHandLocalizedText(
                context,
                zh: 'KPI 元数据',
                en: 'KPI metadata',
              ),
              entries: _extraEntries,
              keyLabel: openHandLocalizedText(context, zh: '键', en: 'Key'),
              valueLabel: openHandLocalizedText(context, zh: '值', en: 'Value'),
              emptyText: openHandLocalizedText(
                context,
                zh: '暂无 KPI 元数据。可补充负责人、周期、截止日期、证据来源等字段。',
                en: 'No KPI metadata yet. Add owner, cadence, deadline, evidence, or source fields.',
              ),
              onAdd: () => setState(() => _extraEntries.add(_KeyValueDraft())),
              onRemove: _removeExtraEntry,
              framed: false,
            ),
          ],
        ),
      ),
    );
  }

  void _removeExtraEntry(_KeyValueDraft entry) {
    setState(() {
      _extraEntries.remove(entry);
      entry.dispose();
    });
  }

  void _submitKpi() {
    final duplicate = _agentFirstDuplicateKey(_extraEntries);
    if (duplicate != null) {
      OpenHandSnackBar.showError(
        context,
        openHandLocalizedText(
          context,
          zh: 'KPI 元数据字段重复：$duplicate',
          en: 'Duplicate KPI metadata field: $duplicate',
        ),
      );
      return;
    }
    Navigator.of(context).pop(_buildKpi());
  }

  AgentKpiItem _buildKpi() {
    final initial = widget.initial;
    return AgentKpiItem(
      id: initial?.id ?? '',
      name: _name.text.trim(),
      target: _target.text.trim(),
      plan: _plan.text.trim(),
      progress: _progress.clamp(0, 1).toDouble(),
      status: _status,
      createdAt: initial?.createdAt,
      extra: _agentKeyValueDraftMapFromEntries(_extraEntries),
    );
  }
}

String _agentKpiStatusLabel(BuildContext context, String status) {
  return switch (status.trim().toLowerCase()) {
    'done' => openHandLocalizedText(context, zh: '已完成', en: 'Done'),
    'at_risk' => openHandLocalizedText(context, zh: '有风险', en: 'At risk'),
    'paused' => openHandLocalizedText(context, zh: '已暂停', en: 'Paused'),
    _ => openHandLocalizedText(context, zh: '跟进中', en: 'Tracking'),
  };
}

IconData _agentKpiStatusIcon(String status) {
  return switch (status.trim().toLowerCase()) {
    'done' => Icons.check_circle_rounded,
    'at_risk' => Icons.warning_amber_rounded,
    'paused' => Icons.pause_circle_outline_rounded,
    _ => Icons.flag_rounded,
  };
}

Color _agentKpiStatusColor(ColorScheme cs, String status) {
  return switch (status.trim().toLowerCase()) {
    'done' => cs.tertiary,
    'at_risk' => cs.error,
    'paused' => cs.onSurfaceVariant,
    _ => cs.primary,
  };
}

List<String> _agentKpiMetadataChips(AgentKpiItem item) {
  const keys = <String>[
    'owner',
    'cadence',
    'deadline',
    'task_id',
    'evidence',
    'source',
  ];
  final chips = <String>[];
  for (final key in keys) {
    final text = _agentMetadataChipText(key, item.extra[key]);
    if (text != null) chips.add(text);
    if (chips.length >= 4) break;
  }
  return chips;
}

Future<void> _showAgentResourcesDialog(
  BuildContext context,
  AgentProfile agent,
) {
  final l10n = AppLocalizations.of(context)!;
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => Consumer<AgentsController>(
      builder: (context, controller, _) {
        final currentAgent = controller.agentById(agent.id) ?? agent;
        final resource = currentAgent.resourceUsage;
        return buildOpenHandDialog(
          maxWidth: 780,
          maxHeight: 620,
          child: _AgentDialogScaffold(
            icon: Icons.storage_rounded,
            title: l10n.agentsDialogTitleWithName(
              l10n.agentsResources,
              currentAgent.name,
            ),
            actions: [
              FilledButton.icon(
                onPressed: () async {
                  final updated = await _showAgentResourceEditorDialog(
                    context,
                    resource,
                  );
                  if (updated == null || !context.mounted) return;
                  await context.read<AgentsController>().saveResourceUsage(
                    currentAgent.id,
                    updated,
                  );
                },
                icon: const Icon(Icons.edit_rounded),
                label: Text(
                  openHandLocalizedText(
                    context,
                    zh: '校准资源',
                    en: 'Edit resources',
                  ),
                ),
              ),
            ],
            child: _AgentResourceBody(resource: resource),
          ),
        );
      },
    ),
  );
}

class _AgentResourceBody extends StatelessWidget {
  const _AgentResourceBody({required this.resource});

  final AgentResourceUsage resource;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cpu = resource.cpuPercent.clamp(0, 1).toDouble();
    final tokenPressure = _agentResourceRatio(
      resource.tokenUsed,
      resource.tokenBudget,
    );
    final persistedPressure = _agentResourceRatio(
      resource.persistedBytes,
      resource.diskBytes,
    );
    final maxPressure = [
      cpu,
      tokenPressure,
      persistedPressure,
    ].reduce(math.max);
    final metadata = _agentResourceMetadataChips(resource);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _MetricTile(
              label: openHandLocalizedText(context, zh: '资源压力', en: 'Pressure'),
              value: _agentResourcePressureLabel(context, maxPressure),
            ),
            _MetricTile(label: 'CPU', value: '${(cpu * 100).round()}%'),
            _MetricTile(
              label: 'Token',
              value: resource.tokenBudget <= 0
                  ? '${resource.tokenUsed}/-'
                  : '${resource.tokenUsed}/${resource.tokenBudget}',
            ),
            _MetricTile(
              label: l10n.agentsMetricHandles,
              value: '${resource.openHandles}',
            ),
          ],
        ),
        const SizedBox(height: 14),
        _AgentResourcePressureCard(
          icon: Icons.memory_rounded,
          label: 'CPU',
          valueLabel: '${(cpu * 100).round()}%',
          pressure: cpu,
        ),
        const SizedBox(height: 10),
        _AgentResourcePressureCard(
          icon: Icons.auto_awesome_rounded,
          label: openHandLocalizedText(
            context,
            zh: 'Token 预算',
            en: 'Token budget',
          ),
          valueLabel: resource.tokenBudget <= 0
              ? openHandLocalizedText(
                  context,
                  zh: '${resource.tokenUsed} / 未设置',
                  en: '${resource.tokenUsed} / unset',
                )
              : '${resource.tokenUsed} / ${resource.tokenBudget}',
          pressure: tokenPressure,
        ),
        const SizedBox(height: 10),
        _AgentResourcePressureCard(
          icon: Icons.inventory_2_rounded,
          label: openHandLocalizedText(
            context,
            zh: '持久化占用',
            en: 'Persisted storage',
          ),
          valueLabel:
              '${formatByteSize(resource.persistedBytes)} / ${formatByteSize(resource.diskBytes)}',
          pressure: persistedPressure,
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
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
          ],
        ),
        if (metadata.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final chip in metadata)
                _AgentActivityMetadataChip(text: chip),
            ],
          ),
        ],
      ],
    );
  }
}

class _AgentResourcePressureCard extends StatelessWidget {
  const _AgentResourcePressureCard({
    required this.icon,
    required this.label,
    required this.valueLabel,
    required this.pressure,
  });

  final IconData icon;
  final String label;
  final String valueLabel;
  final double pressure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final normalized = pressure.clamp(0, 1).toDouble();
    final color = _agentResourcePressureColor(cs, normalized);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: color, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      _AgentActivityTypeChip(
                        label: _agentResourcePressureLabel(context, normalized),
                        color: color,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: normalized,
                            minHeight: 7,
                            color: color,
                            backgroundColor: cs.surfaceContainerHighest,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 92,
                        child: Text(
                          valueLabel,
                          textAlign: TextAlign.end,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

double _agentResourceRatio(int used, int budget) {
  if (budget <= 0) return 0;
  return (used / budget).clamp(0, 1).toDouble();
}

Color _agentResourcePressureColor(ColorScheme cs, double pressure) {
  if (pressure >= 0.85) return cs.error;
  if (pressure >= 0.65) return cs.tertiary;
  return cs.primary;
}

String _agentResourcePressureLabel(BuildContext context, double pressure) {
  if (pressure >= 0.85) {
    return openHandLocalizedText(context, zh: '高压力', en: 'High');
  }
  if (pressure >= 0.65) {
    return openHandLocalizedText(context, zh: '预警', en: 'Watch');
  }
  return openHandLocalizedText(context, zh: '正常', en: 'Normal');
}

List<String> _agentResourceMetadataChips(AgentResourceUsage resource) {
  const keys = <String>[
    'workspace_path',
    'artifact_count',
    'cache_bytes',
    'last_gc_at',
    'quota',
    'owner',
  ];
  final chips = <String>[];
  for (final key in keys) {
    final text = _agentMetadataChipText(key, resource.extra[key]);
    if (text != null) chips.add(text);
    if (chips.length >= 4) break;
  }
  return chips;
}

Future<AgentResourceUsage?> _showAgentResourceEditorDialog(
  BuildContext context,
  AgentResourceUsage initial,
) {
  return showAnimatedDialog<AgentResourceUsage>(
    context: context,
    builder: (_) => _AgentResourceEditorDialog(initial: initial),
  );
}

class _AgentResourceEditorDialog extends StatefulWidget {
  const _AgentResourceEditorDialog({required this.initial});

  final AgentResourceUsage initial;

  @override
  State<_AgentResourceEditorDialog> createState() =>
      _AgentResourceEditorDialogState();
}

class _AgentResourceEditorDialogState
    extends State<_AgentResourceEditorDialog> {
  late final TextEditingController _memoryBytes;
  late final TextEditingController _diskBytes;
  late final TextEditingController _persistedBytes;
  late final TextEditingController _tokenBudget;
  late final TextEditingController _tokenUsed;
  late final TextEditingController _openHandles;
  late final List<_KeyValueDraft> _extraEntries;
  late double _cpuPercent;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _cpuPercent = initial.cpuPercent.clamp(0, 1).toDouble();
    _memoryBytes = TextEditingController(text: '${initial.memoryBytes}');
    _diskBytes = TextEditingController(text: '${initial.diskBytes}');
    _persistedBytes = TextEditingController(text: '${initial.persistedBytes}');
    _tokenBudget = TextEditingController(text: '${initial.tokenBudget}');
    _tokenUsed = TextEditingController(text: '${initial.tokenUsed}');
    _openHandles = TextEditingController(text: '${initial.openHandles}');
    _extraEntries = _keyValueEntriesFromMap(initial.extra);
  }

  @override
  void dispose() {
    for (final controller in [
      _memoryBytes,
      _diskBytes,
      _persistedBytes,
      _tokenBudget,
      _tokenUsed,
      _openHandles,
    ]) {
      controller.dispose();
    }
    for (final entry in _extraEntries) {
      entry.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return buildOpenHandDialog(
      maxWidth: 720,
      child: _AgentDialogScaffold(
        icon: Icons.storage_rounded,
        title: openHandLocalizedText(context, zh: '校准资源', en: 'Edit resources'),
        footer: buildOpenHandDialogActionsBar(
          actions: [
            OpenHandDialogActionButton.secondary(
              onPressed: () => Navigator.of(context).pop(),
              label: l10n.commonCancel,
            ),
            OpenHandDialogActionButton.primary(
              onPressed: _submitUsage,
              label: l10n.commonSave,
            ),
          ],
        ),
        child: _FormGrid(
          children: [
            _FormGridItem(
              fullWidth: true,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'CPU'),
                child: Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: _cpuPercent,
                        divisions: 20,
                        label: '${(_cpuPercent * 100).round()}%',
                        onChanged: (value) =>
                            setState(() => _cpuPercent = value),
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Text(
                        '${(_cpuPercent * 100).round()}%',
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _resourceField(_memoryBytes, l10n.agentsMetricMemory),
            _resourceField(_diskBytes, l10n.agentsMetricDisk),
            _resourceField(_persistedBytes, l10n.agentsMetricPersisted),
            _resourceField(
              _tokenUsed,
              openHandLocalizedText(
                context,
                zh: '已用 Token',
                en: 'Token used',
                fr: 'Tokens utilisés',
                de: 'Verbrauchte Tokens',
                ja: '使用済みトークン',
              ),
            ),
            _resourceField(
              _tokenBudget,
              openHandLocalizedText(
                context,
                zh: 'Token 预算',
                en: 'Token budget',
                fr: 'Budget de tokens',
                de: 'Token-Budget',
                ja: 'トークン予算',
              ),
            ),
            _resourceField(_openHandles, l10n.agentsMetricHandles),
            _FormGridItem(
              fullWidth: true,
              child: _AgentKeyValueEditor(
                title: openHandLocalizedText(
                  context,
                  zh: '资源元数据',
                  en: 'Resource metadata',
                ),
                entries: _extraEntries,
                keyLabel: openHandLocalizedText(context, zh: '键', en: 'Key'),
                valueLabel: openHandLocalizedText(
                  context,
                  zh: '值',
                  en: 'Value',
                ),
                emptyText: openHandLocalizedText(
                  context,
                  zh: '暂无资源元数据。可补充工作目录、产物数量、缓存占用、配额等字段。',
                  en: 'No resource metadata yet. Add workspace, artifact count, cache usage, quota, or owner fields.',
                ),
                onAdd: () =>
                    setState(() => _extraEntries.add(_KeyValueDraft())),
                onRemove: _removeExtraEntry,
                framed: false,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resourceField(TextEditingController controller, String label) {
    return _FormGridItem(
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  void _removeExtraEntry(_KeyValueDraft entry) {
    setState(() {
      _extraEntries.remove(entry);
      entry.dispose();
    });
  }

  void _submitUsage() {
    final duplicate = _agentFirstDuplicateKey(_extraEntries);
    if (duplicate != null) {
      OpenHandSnackBar.showError(
        context,
        openHandLocalizedText(
          context,
          zh: '资源元数据字段重复：$duplicate',
          en: 'Duplicate resource metadata field: $duplicate',
        ),
      );
      return;
    }
    Navigator.of(context).pop(_buildUsage());
  }

  AgentResourceUsage _buildUsage() {
    return widget.initial.copyWith(
      cpuPercent: _cpuPercent,
      memoryBytes: _nonNegativeIntFromText(_memoryBytes.text),
      diskBytes: _nonNegativeIntFromText(_diskBytes.text),
      persistedBytes: _nonNegativeIntFromText(_persistedBytes.text),
      tokenBudget: _nonNegativeIntFromText(_tokenBudget.text),
      tokenUsed: _nonNegativeIntFromText(_tokenUsed.text),
      openHandles: _nonNegativeIntFromText(_openHandles.text),
      extra: _agentKeyValueDraftMapFromEntries(_extraEntries),
    );
  }
}

int _nonNegativeIntFromText(String value) {
  return nonNegativeIntFromValue(value, fallback: 0);
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
          borderRadius: BorderRadius.circular(8),
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

class _AgentAuditReportBody extends StatelessWidget {
  const _AgentAuditReportBody({required this.agent, required this.report});

  final AgentProfile agent;
  final _AgentAuditReportSummary report;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _MetricTile(
              label: l10n.agentsAuditRequests,
              value: '${report.requests}',
            ),
            _MetricTile(
              label: openHandLocalizedText(
                context,
                zh: 'Token',
                en: 'Tokens',
                fr: 'Tokens',
                de: 'Tokens',
                ja: 'トークン',
              ),
              value: '${report.tokens}',
            ),
            _MetricTile(
              label: l10n.agentsAuditCompleted,
              value: '${agent.completedTaskCount}',
            ),
            _MetricTile(
              label: l10n.agentsAuditUtilization,
              value: '${(agent.workerUtilization * 100).round()}%',
            ),
            _MetricTile(
              label: openHandLocalizedText(
                context,
                zh: '能力事件',
                en: 'Capability events',
                fr: 'Événements de capacité',
                de: 'Fähigkeitsereignisse',
                ja: '能力イベント',
              ),
              value: '${report.eventCount}',
            ),
            _MetricTile(
              label: openHandLocalizedText(
                context,
                zh: '忙碌 Worker',
                en: 'Busy workers',
                fr: 'Workers occupés',
                de: 'Beschäftigte Worker',
                ja: '稼働中の Worker',
              ),
              value: '${report.busyWorkers}/${agent.workers.length}',
            ),
          ],
        ),
        const SizedBox(height: 18),
        _AgentAuditSection(
          icon: Icons.playlist_add_check_rounded,
          title: openHandLocalizedText(
            context,
            zh: '任务完成画像',
            en: 'Task completion',
            fr: 'Avancement des tâches',
            de: 'Aufgabenabschluss',
            ja: 'タスク完了状況',
          ),
          emptyText: l10n.agentsNoTasksTitle,
          children: [
            for (final item in report.tasks)
              _AgentAuditTaskStatusRow(
                label: _agentAuditTaskBucketLabel(context, item.bucket),
                count: item.count,
                ratio: item.ratio,
              ),
          ],
        ),
        const SizedBox(height: 12),
        _AgentAuditSection(
          icon: Icons.extension_rounded,
          title: openHandLocalizedText(
            context,
            zh: '能力使用画像',
            en: 'Capability usage',
            fr: 'Usage des capacités',
            de: 'Fähigkeitsnutzung',
            ja: '能力使用',
          ),
          emptyText: l10n.agentsNoAuditData,
          children: [
            for (final item in report.capabilities.take(5))
              _AgentAuditInsightRow(
                title: item.name,
                subtitle: [
                  item.type,
                  openHandLocalizedText(
                    context,
                    zh: '${item.requests} 请求',
                    en: '${item.requests} requests',
                  ),
                  '${item.tokens} Token',
                ].join(' · '),
                trailing: '${item.events}',
              ),
          ],
        ),
        const SizedBox(height: 12),
        _AgentAuditSection(
          icon: Icons.memory_rounded,
          title: openHandLocalizedText(
            context,
            zh: 'Worker 执行画像',
            en: 'Worker execution',
            fr: 'Exécution des workers',
            de: 'Worker-Ausführung',
            ja: 'Worker 実行',
          ),
          emptyText: openHandLocalizedText(
            context,
            zh: '暂无 Worker 执行数据。',
            en: 'No worker execution data yet.',
            fr: 'Aucune donnée d’exécution worker.',
            de: 'Noch keine Worker-Ausführungsdaten.',
            ja: 'Worker 実行データはまだありません。',
          ),
          children: [
            for (final item in report.workers.take(6))
              _AgentAuditInsightRow(
                title: item.name,
                subtitle: [
                  _agentWorkerStatusLabel(l10n, item.status),
                  openHandLocalizedText(
                    context,
                    zh: '${item.assignedTasks} 任务',
                    en: '${item.assignedTasks} tasks',
                  ),
                  '${item.tokens} Token',
                  '${(item.busyScore * 100).round()}%',
                ].join(' · '),
                trailing: '${item.executedTasks}',
              ),
          ],
        ),
        const SizedBox(height: 12),
        _AgentAuditSection(
          icon: Icons.speed_rounded,
          title: openHandLocalizedText(
            context,
            zh: '负载与资源压力',
            en: 'Load and resource pressure',
            fr: 'Charge et pression des ressources',
            de: 'Last und Ressourcendruck',
            ja: '負荷とリソース圧力',
          ),
          emptyText: '',
          children: [
            _AgentAuditPressureRow(
              label: openHandLocalizedText(context, zh: 'CPU', en: 'CPU'),
              value: report.cpuPressure,
            ),
            _AgentAuditPressureRow(
              label: openHandLocalizedText(
                context,
                zh: 'Token 预算',
                en: 'Token budget',
                fr: 'Budget de tokens',
                de: 'Token-Budget',
                ja: 'トークン予算',
              ),
              value: report.tokenPressure,
            ),
            _AgentAuditPressureRow(
              label: openHandLocalizedText(
                context,
                zh: '持久化占用',
                en: 'Persisted storage',
                fr: 'Stockage persistant',
                de: 'Persistenter Speicher',
                ja: '永続化ストレージ',
              ),
              value: report.persistedPressure,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(l10n.agentsRecentAuditEvents, style: theme.textTheme.titleMedium),
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
                    [
                      event.toolName.isEmpty ? event.kind : event.toolName,
                      if (event.requestCount > 0)
                        openHandLocalizedText(
                          context,
                          zh: '${event.requestCount} 请求',
                          en: '${event.requestCount} requests',
                        ),
                      if (event.tokenUsage > 0) '${event.tokenUsage} Token',
                    ].join(' · '),
                  ),
                ),
              ),
      ],
    );
  }
}

class _AgentAuditSection extends StatelessWidget {
  const _AgentAuditSection({
    required this.icon,
    required this.title,
    required this.emptyText,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String emptyText;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
              ],
            ),
            const SizedBox(height: 10),
            if (children.isEmpty)
              Text(
                emptyText,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              )
            else
              ...children,
          ],
        ),
      ),
    );
  }
}

class _AgentAuditInsightRow extends StatelessWidget {
  const _AgentAuditInsightRow({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final String title;
  final String subtitle;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            trailing,
            style: theme.textTheme.titleSmall?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentAuditTaskStatusRow extends StatelessWidget {
  const _AgentAuditTaskStatusRow({
    required this.label,
    required this.count,
    required this.ratio,
  });

  final String label;
  final int count;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final percent = (ratio.clamp(0, 1) * 100).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '$count · $percent%',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio.clamp(0, 1).toDouble(),
              minHeight: 7,
              backgroundColor: cs.surfaceContainerHighest,
              color: cs.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentAuditPressureRow extends StatelessWidget {
  const _AgentAuditPressureRow({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ratio = value.clamp(0, 1).toDouble();
    final color = ratio >= 0.85 ? cs.error : cs.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 112,
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          Expanded(
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              borderRadius: BorderRadius.circular(999),
              color: color,
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 44,
            child: Text(
              '${(ratio * 100).round()}%',
              textAlign: TextAlign.end,
              style: theme.textTheme.labelLarge?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentTaskDetailGrid extends StatelessWidget {
  const _AgentTaskDetailGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 620;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final child in children)
              SizedBox(
                width: twoColumns
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth,
                child: child,
              ),
          ],
        );
      },
    );
  }
}

class _AgentTaskDetailBlock extends StatelessWidget {
  const _AgentTaskDetailBlock({
    required this.title,
    required this.body,
    this.compact = false,
    this.monospace = false,
  });

  final String title;
  final String body;
  final bool compact;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final value = body.trim().isEmpty ? '-' : body.trim();
    final textStyle =
        (compact ? theme.textTheme.bodyMedium : theme.textTheme.bodyLarge)
            ?.copyWith(
              color: cs.onSurface,
              fontFamily: monospace ? 'monospace' : null,
            );
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 0 : 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              SelectableText(value, style: textStyle),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentApprovalActions extends StatelessWidget {
  const _AgentApprovalActions({
    required this.onApproved,
    required this.onRejected,
  });

  final VoidCallback onApproved;
  final VoidCallback onRejected;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: openHandLocalizedText(context, zh: '批准', en: 'Approve'),
          child: IconButton.filledTonal(
            onPressed: onApproved,
            icon: const Icon(Icons.check_rounded),
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: openHandLocalizedText(context, zh: '拒绝', en: 'Reject'),
          child: IconButton.filledTonal(
            onPressed: onRejected,
            icon: const Icon(Icons.close_rounded),
          ),
        ),
      ],
    );
  }
}

Future<void> _showAgentApprovalRequestDialog(
  BuildContext context,
  AgentProfile agent,
) async {
  final l10n = AppLocalizations.of(context)!;
  final title = TextEditingController();
  final reason = TextEditingController();
  final requestedAction = TextEditingController();
  try {
    final submitted = await showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) => buildOpenHandDialog(
        maxWidth: 680,
        child: _AgentDialogScaffold(
          icon: Icons.add_moderator_outlined,
          title: openHandLocalizedText(
            context,
            zh: '发起审批',
            en: 'Request approval',
          ),
          footer: buildOpenHandDialogActionsBar(
            actions: [
              OpenHandDialogActionButton.secondary(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                label: l10n.commonCancel,
              ),
              OpenHandDialogActionButton.primary(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                label: openHandLocalizedText(context, zh: '提交', en: 'Submit'),
              ),
            ],
          ),
          child: Column(
            children: [
              TextField(
                controller: title,
                decoration: InputDecoration(labelText: l10n.agentsFieldName),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reason,
                minLines: 3,
                maxLines: 6,
                decoration: InputDecoration(
                  labelText: openHandLocalizedText(
                    context,
                    zh: '审批原因',
                    en: 'Reason',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: requestedAction,
                decoration: InputDecoration(
                  labelText: openHandLocalizedText(
                    context,
                    zh: '请求动作',
                    en: 'Requested action',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (submitted == true && context.mounted) {
      final titleText = title.text.trim();
      if (titleText.isEmpty) {
        OpenHandSnackBar.showInfo(
          context,
          openHandLocalizedText(
            context,
            zh: '请先填写审批标题。',
            en: 'Enter an approval title first.',
          ),
        );
        return;
      }
      await context.read<AgentsController>().requestApproval(
        agent.id,
        title: titleText,
        reason: reason.text,
        requestedAction: requestedAction.text,
      );
    }
  } finally {
    title.dispose();
    reason.dispose();
    requestedAction.dispose();
  }
}

Future<void> _resolveAgentApprovalFromDialog(
  BuildContext context,
  AgentProfile agent,
  AgentApprovalRequest approval,
  AgentApprovalStatus status,
) async {
  final resolved = await context.read<AgentsController>().resolveApproval(
    agent.id,
    approval.id,
    status,
  );
  if (resolved == null && context.mounted) {
    OpenHandSnackBar.showError(
      context,
      openHandLocalizedText(
        context,
        zh: '审批状态已变化，请刷新后再试。',
        en: 'Approval state changed. Refresh and try again.',
      ),
    );
  }
}

String _agentApprovalTimeLabel(
  BuildContext context,
  AgentApprovalRequest approval,
) {
  final time = approval.resolvedAt ?? approval.createdAt;
  if (time == null) return '';
  final prefix = approval.resolvedAt == null
      ? openHandLocalizedText(context, zh: '创建', en: 'Created')
      : openHandLocalizedText(context, zh: '处理', en: 'Resolved');
  return '$prefix ${formatMonthDayHm(time.toLocal())}';
}

IconData _agentApprovalStatusIcon(AgentApprovalStatus status) {
  return switch (status) {
    AgentApprovalStatus.pending => Icons.hourglass_top_rounded,
    AgentApprovalStatus.approved => Icons.check_circle_rounded,
    AgentApprovalStatus.rejected => Icons.cancel_rounded,
    AgentApprovalStatus.expired => Icons.schedule_rounded,
  };
}

Color _agentApprovalStatusColor(ColorScheme cs, AgentApprovalStatus status) {
  return switch (status) {
    AgentApprovalStatus.pending => cs.primary,
    AgentApprovalStatus.approved => cs.tertiary,
    AgentApprovalStatus.rejected => cs.error,
    AgentApprovalStatus.expired => cs.onSurfaceVariant,
  };
}

String _agentApprovalRiskLevel(AgentApprovalRequest approval) {
  final raw =
      approval.extra['risk_level'] ??
      approval.extra['riskLevel'] ??
      approval.extra['risk'];
  return '$raw'.trim().toLowerCase();
}

bool _agentApprovalIsHighRisk(String riskLevel) {
  return riskLevel == 'high' ||
      riskLevel == 'critical' ||
      riskLevel == 'destructive';
}

Color _agentApprovalRiskColor(ColorScheme cs, String riskLevel) {
  return switch (riskLevel) {
    'critical' || 'destructive' || 'high' => cs.error,
    'medium' => cs.tertiary,
    'low' => cs.primary,
    _ => cs.onSurfaceVariant,
  };
}

String _agentApprovalRiskLabel(BuildContext context, String riskLevel) {
  return switch (riskLevel) {
    'critical' ||
    'destructive' => openHandLocalizedText(context, zh: '高危', en: 'Critical'),
    'high' => openHandLocalizedText(context, zh: '高风险', en: 'High risk'),
    'medium' => openHandLocalizedText(context, zh: '中风险', en: 'Medium risk'),
    'low' => openHandLocalizedText(context, zh: '低风险', en: 'Low risk'),
    _ => openHandLocalizedText(context, zh: '常规', en: 'Standard'),
  };
}

List<String> _agentApprovalMetadataChips(AgentApprovalRequest approval) {
  const keys = <String>[
    'permissions',
    'permission',
    'scope',
    'resource',
    'resource_path',
    'tool_name',
    'mcp_server',
    'task_id',
    'worker_id',
    'expires_at',
  ];
  final chips = <String>[];
  for (final key in keys) {
    final text = _agentMetadataChipText(key, approval.extra[key]);
    if (text != null) chips.add(text);
    if (chips.length >= 5) break;
  }
  return chips;
}

Future<void> _showPublishTaskDialog(
  BuildContext context,
  AgentProfile agent,
) async {
  final draft = await showAnimatedDialog<_AgentPublishTaskDraft>(
    context: context,
    builder: (_) => _AgentPublishTaskDialog(agent: agent),
  );
  if (draft != null && context.mounted) {
    await context.read<AgentsController>().publishTask(
      agent.id,
      title: draft.title,
      description: draft.description,
      content: draft.content,
      note: draft.note,
      extra: draft.extra,
    );
  }
}

class _AgentPublishTaskDraft {
  const _AgentPublishTaskDraft({
    required this.title,
    required this.description,
    required this.content,
    required this.note,
    required this.extra,
  });

  final String title;
  final String description;
  final String content;
  final String note;
  final Map<String, Object?> extra;
}

class _AgentPublishTaskDialog extends StatefulWidget {
  const _AgentPublishTaskDialog({required this.agent});

  final AgentProfile agent;

  @override
  State<_AgentPublishTaskDialog> createState() =>
      _AgentPublishTaskDialogState();
}

class _AgentPublishTaskDialogState extends State<_AgentPublishTaskDialog> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _content;
  late final TextEditingController _note;
  final List<_KeyValueDraft> _extraEntries = <_KeyValueDraft>[];

  @override
  void initState() {
    super.initState();
    _title = TextEditingController();
    _description = TextEditingController();
    _content = TextEditingController();
    _note = TextEditingController();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _content.dispose();
    _note.dispose();
    for (final entry in _extraEntries) {
      entry.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return buildOpenHandDialog(
      maxWidth: 680,
      child: _AgentDialogScaffold(
        icon: Icons.add_task_rounded,
        title: l10n.agentsDialogTitleWithName(
          l10n.agentsPublishTask,
          widget.agent.name,
        ),
        footer: buildOpenHandDialogActionsBar(
          actions: [
            OpenHandDialogActionButton.secondary(
              onPressed: () => Navigator.of(context).pop(),
              label: l10n.commonCancel,
            ),
            OpenHandDialogActionButton.primary(
              onPressed: _submit,
              label: l10n.agentsPublish,
            ),
          ],
        ),
        child: Column(
          children: [
            TextField(
              controller: _title,
              decoration: InputDecoration(labelText: l10n.agentsTaskTitleLabel),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              decoration: InputDecoration(
                labelText: l10n.agentsDescriptionLabel,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _content,
              minLines: 4,
              maxLines: 8,
              decoration: InputDecoration(labelText: l10n.agentsContentLabel),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: InputDecoration(labelText: l10n.agentsNoteLabel),
            ),
            const SizedBox(height: 12),
            _AgentKeyValueEditor(
              title: openHandLocalizedText(
                context,
                zh: '扩展字段',
                en: 'Extra fields',
                fr: 'Champs supplémentaires',
                de: 'Zusatzfelder',
                ja: '追加フィールド',
              ),
              entries: _extraEntries,
              keyLabel: openHandLocalizedText(
                context,
                zh: '键',
                en: 'Key',
                fr: 'Clé',
                de: 'Schlüssel',
                ja: 'キー',
              ),
              valueLabel: openHandLocalizedText(
                context,
                zh: '值',
                en: 'Value',
                fr: 'Valeur',
                de: 'Wert',
                ja: '値',
              ),
              emptyText: openHandLocalizedText(
                context,
                zh: '暂无扩展字段。数值、布尔值、数组和对象会自动结构化保存。',
                en: 'No extra fields yet. Numbers, booleans, arrays, and objects are saved structurally.',
                fr: 'Aucun champ supplémentaire. Les nombres, booléens, tableaux et objets sont enregistrés de manière structurée.',
                de: 'Noch keine Zusatzfelder. Zahlen, Boolesche Werte, Arrays und Objekte werden strukturiert gespeichert.',
                ja: '追加フィールドはまだありません。数値、真偽値、配列、オブジェクトは構造化して保存されます。',
              ),
              onAdd: () => setState(() => _extraEntries.add(_KeyValueDraft())),
              onRemove: _removeExtraEntry,
            ),
          ],
        ),
      ),
    );
  }

  void _removeExtraEntry(_KeyValueDraft entry) {
    setState(() {
      _extraEntries.remove(entry);
      entry.dispose();
    });
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(
      _AgentPublishTaskDraft(
        title: _title.text,
        description: _description.text,
        content: _content.text,
        note: _note.text,
        extra: _agentKeyValueDraftMapFromEntries(_extraEntries),
      ),
    );
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
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded),
              ),
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
  final controller = context.read<AgentsController>();
  final result = await showAnimatedDialog<AgentProfile>(
    context: context,
    builder: (dialogContext) => _AgentEditorDialog(initialAgent: initialAgent),
  );
  if (result != null) {
    await controller.saveAgent(result);
  }
}

void _handleCreateAgent(
  BuildContext context,
  AgentRuntimeAvailability runtime,
) {
  if (!runtime.canRun) {
    OpenHandSnackBar.showError(
      context,
      _agentRuntimeCreateBlockingText(context, runtime),
    );
    return;
  }
  _showAgentEditor(context);
}

Future<void> _handleToggleAgentEnabled(
  BuildContext context,
  AgentProfile agent,
  bool enabled,
) async {
  final controller = context.read<AgentsController>();
  final updated = await controller.setAgentEnabled(agent.id, enabled: enabled);
  if (updated || !enabled || !context.mounted) return;
  OpenHandSnackBar.showError(
    context,
    _agentRuntimeBlockingText(context, controller.runtimeAvailability),
  );
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
  late final TextEditingController _routeName;
  late final TextEditingController _routePriority;
  late final TextEditingController _routeDescription;
  late final TextEditingController _routeKeywordInput;
  late final TextEditingController _routeDomainInput;
  late final TextEditingController _routeIntentInput;
  late final TextEditingController _welcomeMessage;
  late final TextEditingController _persona;
  late final TextEditingController _boundary;
  late final TextEditingController _workspacePath;
  late final TextEditingController _taskLabelInput;
  late final TextEditingController _workerTagInput;
  late final TextEditingController _kpiName;
  late final TextEditingController _kpiTarget;
  late AgentExecutionMode _executionMode;
  late bool _enabled;
  late bool _selfLearningEnabled;
  late int _minWorkers;
  late int _maxWorkers;
  late int _maxRetries;
  late double _scaleOutThreshold;
  late double _scaleInThreshold;
  late String _schedulerPolicy;
  late String _workerRemovalPolicy;
  late String _retryPolicy;
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
  late List<String> _routeKeywords;
  late List<String> _routeDomains;
  late List<String> _routeIntents;
  late List<_KeyValueDraft> _routeExtraFields;
  late List<String> _workspaceScopePaths;
  late List<String> _taskLabelValues;
  late List<String> _workerTagValues;
  late List<_KeyValueDraft> _metadataEntries;
  bool _refreshingCapabilities = false;

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
    final route = parseAgentRouteFrontMatter(agent?.routeFrontMatter ?? '');
    _routeName = TextEditingController(
      text: _stringFromRouteValue(route['route'] ?? route['routes'], 'default'),
    );
    _routePriority = TextEditingController(
      text: _stringFromRouteValue(route['priority'], '100'),
    );
    _routeDescription = TextEditingController(
      text: _stringFromRouteValue(route['description'], ''),
    );
    _routeKeywordInput = TextEditingController();
    _routeDomainInput = TextEditingController();
    _routeIntentInput = TextEditingController();
    _routeKeywords = _routeStringsFromValues(<Object?>[
      route['keywords'],
      route['keyword'],
      route['triggers'],
      route['trigger'],
    ]);
    _routeDomains = _routeStringsFromValues(<Object?>[
      route['domains'],
      route['domain'],
    ]);
    _routeIntents = _routeStringsFromValues(<Object?>[
      route['intents'],
      route['intent'],
    ]);
    _routeExtraFields = _routeExtraEntries(route);
    _welcomeMessage = TextEditingController(text: agent?.welcomeMessage ?? '');
    _persona = TextEditingController(text: agent?.persona ?? '');
    _boundary = TextEditingController(
      text: agent?.responsibilityBoundary ?? '',
    );
    _workspacePath = TextEditingController(text: agent?.workspacePath ?? '');
    _taskLabelInput = TextEditingController();
    _workerTagInput = TextEditingController();
    _workspaceScopePaths = List<String>.from(
      agent?.normalizedWorkspaceScopePaths ?? const <String>[],
    );
    _taskLabelValues = List<String>.from(agent?.taskLabels ?? const <String>[]);
    _workerTagValues = List<String>.from(
      agent?.scaleSettings.tags ?? const <String>[],
    );
    _metadataEntries = _metadataEntriesFromMap(agent?.metadata);
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
    _scaleOutThreshold = agent?.scaleSettings.scaleOutThreshold ?? 0.75;
    _scaleInThreshold = agent?.scaleSettings.scaleInThreshold ?? 0.25;
    _schedulerPolicy = agent?.scaleSettings.schedulerPolicy ?? 'least_busy';
    _workerRemovalPolicy =
        agent?.scaleSettings.workerRemovalPolicy ?? 'least_busy';
    _retryPolicy = agent?.scaleSettings.retryPolicy ?? 'bounded_retry';
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
      _routeName,
      _routePriority,
      _routeDescription,
      _routeKeywordInput,
      _routeDomainInput,
      _routeIntentInput,
      _welcomeMessage,
      _persona,
      _boundary,
      _workspacePath,
      _taskLabelInput,
      _workerTagInput,
      _kpiName,
      _kpiTarget,
    ]) {
      controller.dispose();
    }
    for (final entry in [..._routeExtraFields, ..._metadataEntries]) {
      entry.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsController>();
    final skillsController = context.watch<SkillsController>();
    final knowledgeBaseController = context.watch<KnowledgeBaseController>();
    final memoryController = context.watch<MemoryController>();
    final mcpController = context.watch<McpController>();
    final cronsController = context.watch<CronsController>();
    final hooksController = context.watch<HooksController>();
    final skills = skillsController.skills;
    final knowledgeSources = knowledgeBaseController.sources;
    final memories = memoryController.entries;
    final mcpServers = mcpController.servers;
    final crons = cronsController.entries;
    final hooks = hooksController.entries;
    final runtime = context.watch<AgentsController>().runtimeAvailability;
    final builtinTools = _builtinToolOptions(settings.builtinToolConfigs);
    final selectedBuiltinTools = _normalizedBuiltinToolSelection(
      settings.builtinToolConfigs,
    );

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
                    labelPadding: const EdgeInsets.symmetric(horizontal: 6),
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
                            builtinTools: builtinTools,
                            selectedBuiltinTools: selectedBuiltinTools,
                            onRefresh: _refreshCapabilities,
                            refreshing: _refreshingCapabilities,
                          ),
                        ),
                        _tabScroll(
                          _runtimeTab(
                            l10n: l10n,
                            runtime: runtime,
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
                        onPressed: () => Navigator.of(
                          dialogContext,
                          rootNavigator: true,
                        ).pop(),
                        label: l10n.commonCancel,
                      ),
                      OpenHandDialogActionButton.primary(
                        onPressed: _name.text.trim().isEmpty
                            ? null
                            : () => _submitAgent(
                                dialogContext: dialogContext,
                                builtinToolConfigs: settings.builtinToolConfigs,
                              ),
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
        _FormGridItem(child: _avatarPicker(l10n)),
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
        _FormGridItem(fullWidth: true, child: _routeEditor(l10n)),
        _FormGridItem(
          fullWidth: true,
          child: _AgentRoutePreviewCard(metadata: _routePreview()),
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
    required Set<String> selectedBuiltinTools,
    required VoidCallback onRefresh,
    required bool refreshing,
  }) {
    final agentTools = builtinTools
        .where((option) => _isAgentCoordinationBuiltinToolId(option.id))
        .toList(growable: false);
    final regularTools = builtinTools
        .where((option) => !_isAgentCoordinationBuiltinToolId(option.id))
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                openHandLocalizedText(
                  context,
                  zh: '外置能力',
                  en: 'External capabilities',
                ),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton.filledTonal(
              tooltip: openHandLocalizedText(
                context,
                zh: '刷新能力配置',
                en: 'Refresh capabilities',
              ),
              onPressed: refreshing ? null : onRefresh,
              icon: refreshing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 780;
            final itemWidth = twoColumns
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: itemWidth,
                  child: _CapabilityPanel(
                    title: l10n.skills,
                    icon: Icons.school_rounded,
                    options: skills,
                    selected: _skillNames,
                    onChanged: (v) => setState(() => _skillNames = v),
                  ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: _CapabilityPanel(
                    title: l10n.agentsKnowledgeBase,
                    icon: Icons.library_books_rounded,
                    options: knowledgeSources,
                    selected: _knowledgeSourceIds,
                    onChanged: (v) => setState(() => _knowledgeSourceIds = v),
                  ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: _CapabilityPanel(
                    title: l10n.memory,
                    icon: Icons.psychology_rounded,
                    options: memories,
                    selected: _memoryIds,
                    onChanged: (v) => setState(() => _memoryIds = v),
                  ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: _CapabilityPanel(
                    title: 'MCP',
                    icon: Icons.hub_rounded,
                    options: mcpServers,
                    selected: _mcpServerNames,
                    onChanged: (v) => setState(() => _mcpServerNames = v),
                  ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: _CapabilityPanel(
                    title: openHandLocalizedText(
                      context,
                      zh: 'Agent 协同工具',
                      en: 'Agent coordination tools',
                    ),
                    icon: Icons.account_tree_rounded,
                    options: agentTools,
                    selected: selectedBuiltinTools,
                    onChanged: (v) => setState(
                      () => _builtinToolNames = _mergeOptionGroupSelection(
                        current: selectedBuiltinTools,
                        groupSelection: v,
                        groupOptions: agentTools,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: _CapabilityPanel(
                    title: l10n.agentsBuiltInTools,
                    icon: Icons.extension_rounded,
                    options: regularTools,
                    selected: selectedBuiltinTools,
                    onChanged: (v) => setState(
                      () => _builtinToolNames = _mergeOptionGroupSelection(
                        current: selectedBuiltinTools,
                        groupSelection: v,
                        groupOptions: regularTools,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _runtimeTab({
    required AppLocalizations l10n,
    required AgentRuntimeAvailability runtime,
    required SettingsController settings,
    required List<RecentModelSelection> recentSelections,
  }) {
    final canEnable = runtime.canRun;
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
          value: canEnable && _enabled,
          onChanged: canEnable
              ? (value) => setState(() => _enabled = value)
              : null,
          title: Text(l10n.agentsEnableAgentTitle),
          subtitle: Text(
            canEnable
                ? l10n.agentsEnableAgentBody
                : _agentRuntimeBlockingText(context, runtime),
          ),
        ),
        SwitchListTile(
          value: _selfLearningEnabled,
          onChanged: (value) => setState(() => _selfLearningEnabled = value),
          title: Text(l10n.agentsSelfLearningTitle),
          subtitle: Text(l10n.agentsSelfLearningBody),
        ),
        const SizedBox(height: 12),
        _directoryPickerField(
          label: l10n.agentsFieldWorkspacePath,
          value: _workspacePath.text,
          onPick: _pickWorkspacePath,
          onClear: () => setState(_workspacePath.clear),
        ),
        const SizedBox(height: 12),
        _directoryListPicker(
          label: l10n.agentsFieldWorkspaceScope,
          values: _workspaceScopePaths,
          emptyText: openHandLocalizedText(
            context,
            zh: '尚未限定目录范围。留空时仅使用工作目录。',
            en: 'No scoped directories yet. Leave empty to use only the workspace.',
          ),
          onAdd: _pickWorkspaceScopePath,
          onRemove: (value) =>
              setState(() => _workspaceScopePaths.remove(value)),
          onReorder: (oldIndex, newIndex) => setState(
            () => _reorderStringList(_workspaceScopePaths, oldIndex, newIndex),
          ),
          keyPrefix: 'agent-workspace-scope',
        ),
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
          keyPrefix: 'agent-cron',
        ),
        _OptionChips(
          title: 'Hooks',
          options: hooks,
          selected: _hookIds,
          onChanged: (v) => setState(() => _hookIds = v),
          keyPrefix: 'agent-hook',
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
                (v) => setState(() {
                  _maxWorkers = v.clamp(1, 999);
                  if (_minWorkers > _maxWorkers) _minWorkers = _maxWorkers;
                }),
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
        Row(
          children: [
            Expanded(
              child: _ratioSlider(
                openHandLocalizedText(
                  context,
                  zh: '扩容阈值',
                  en: 'Scale-out threshold',
                ),
                _scaleOutThreshold,
                (value) => setState(() => _scaleOutThreshold = value),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ratioSlider(
                openHandLocalizedText(
                  context,
                  zh: '缩容阈值',
                  en: 'Scale-in threshold',
                ),
                _scaleInThreshold,
                (value) => setState(() => _scaleInThreshold = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _policyDropdown(
                label: l10n.agentsSchedulerPolicyLabel,
                value: _schedulerPolicy,
                values: _agentSchedulerPolicyOptions,
                onChanged: (value) => setState(() => _schedulerPolicy = value),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _policyDropdown(
                label: openHandLocalizedText(
                  context,
                  zh: 'Worker 移出策略',
                  en: 'Worker removal policy',
                ),
                value: _workerRemovalPolicy,
                values: _agentWorkerRemovalPolicyOptions,
                onChanged: (value) =>
                    setState(() => _workerRemovalPolicy = value),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _policyDropdown(
                label: openHandLocalizedText(
                  context,
                  zh: '重试策略',
                  en: 'Retry policy',
                ),
                value: _retryPolicy,
                values: _agentRetryPolicyOptions,
                onChanged: (value) => setState(() => _retryPolicy = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _editableStringChips(
          label: openHandLocalizedText(
            context,
            zh: 'Worker 标签',
            en: 'Worker tags',
          ),
          inputController: _workerTagInput,
          values: _workerTagValues,
          emptyText: openHandLocalizedText(
            context,
            zh: '暂无 Worker 标签。',
            en: 'No worker tags yet.',
          ),
          onAdd: _addWorkerTag,
          onSubmitted: (_) => _addWorkerTag(),
          onRemove: (value) => setState(() => _workerTagValues.remove(value)),
          onReorder: (oldIndex, newIndex) => setState(
            () => _reorderStringList(_workerTagValues, oldIndex, newIndex),
          ),
          keyPrefix: 'agent-worker-tag',
        ),
        const SizedBox(height: 14),
        _editableStringChips(
          label: l10n.agentsTaskLabelsLabel,
          inputController: _taskLabelInput,
          values: _taskLabelValues,
          emptyText: openHandLocalizedText(
            context,
            zh: '暂无任务标签。',
            en: 'No task labels yet.',
          ),
          onAdd: _addTaskLabel,
          onSubmitted: (_) => _addTaskLabel(),
          onRemove: (value) => setState(() => _taskLabelValues.remove(value)),
          onReorder: (oldIndex, newIndex) => setState(
            () => _reorderStringList(_taskLabelValues, oldIndex, newIndex),
          ),
          keyPrefix: 'agent-task-label',
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
        const SizedBox(height: 10),
        _AgentDraftKpiList(
          items: _kpis,
          onRemove: (item) => setState(() => _kpis.remove(item)),
        ),
      ],
    );
  }

  Widget _metadataTab(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _keyValueEditor(
          title: openHandLocalizedText(
            context,
            zh: '元数据键值',
            en: 'Metadata fields',
          ),
          entries: _metadataEntries,
          keyLabel: openHandLocalizedText(context, zh: '键', en: 'Key'),
          valueLabel: openHandLocalizedText(context, zh: '值', en: 'Value'),
          emptyText: openHandLocalizedText(
            context,
            zh: '暂无元数据。添加键值后会随智能体档案保存。',
            en: 'No metadata yet. Add key-value pairs to save with this agent.',
          ),
          onAdd: _addMetadataEntry,
          onRemove: _removeMetadataEntry,
        ),
        const SizedBox(height: 12),
        FeatureStateCard.inline(
          icon: Icons.schema_rounded,
          title: l10n.agentsMetadataInfoTitle,
          body: openHandLocalizedText(
            context,
            zh: '这里保存扩展字段。值会自动识别数字、布尔值、数组和对象；无法解析时按文本保存。',
            en: 'Extension fields live here. Values are parsed as numbers, booleans, arrays, or objects when possible; otherwise they are saved as text.',
          ),
        ),
      ],
    );
  }

  Widget _avatarPicker(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final avatar = _avatar.text.trim();
    final isImage = _agentAvatarLooksLikeImagePath(avatar);
    final displayText = avatar.isEmpty
        ? l10n.agentsFieldAvatarHint
        : isImage
        ? OpenHandPaths.shortenHomePath(avatar)
        : avatar;
    return InputDecorator(
      decoration: InputDecoration(labelText: l10n.agentsFieldAvatar),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: _AgentAvatarContent(
              avatar: avatar,
              fallback: _name.text.trim().isEmpty
                  ? (widget.initialAgent?.initials ?? 'A')
                  : _name.text.trim().characters.first.toUpperCase(),
              size: 52,
              textStyle: theme.textTheme.titleLarge?.copyWith(
                color: colors.onPrimaryContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              displayText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: avatar.isEmpty
                    ? colors.onSurfaceVariant
                    : colors.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: openHandLocalizedText(
              context,
              zh: avatar.isEmpty ? '选择图片' : '更换图片',
              en: avatar.isEmpty ? 'Choose image' : 'Change image',
            ),
            onPressed: _pickAvatarImage,
            icon: const Icon(Icons.image_search_rounded),
          ),
          if (avatar.isNotEmpty) ...[
            const SizedBox(width: 6),
            IconButton(
              tooltip: openHandLocalizedText(
                context,
                zh: '清除头像',
                en: 'Clear avatar',
              ),
              onPressed: () => setState(_avatar.clear),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ],
      ),
    );
  }

  Widget _routeEditor(AppLocalizations l10n) {
    return _AgentEditorPanel(
      title: l10n.agentsFieldRouteFrontMatter,
      icon: Icons.route_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FormGrid(
            children: [
              _field(
                _routeName,
                openHandLocalizedText(context, zh: '路由名称', en: 'Route name'),
                onChanged: (_) => setState(() {}),
              ),
              _field(
                _routePriority,
                openHandLocalizedText(context, zh: '优先级', en: 'Priority'),
                onChanged: (_) => setState(() {}),
              ),
              _field(
                _routeDescription,
                openHandLocalizedText(
                  context,
                  zh: '路由说明',
                  en: 'Route description',
                ),
                maxLines: 2,
                fullWidth: true,
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _editableStringChips(
            label: openHandLocalizedText(
              context,
              zh: '关键词 / 触发词',
              en: 'Keywords / triggers',
            ),
            inputController: _routeKeywordInput,
            values: _routeKeywords,
            emptyText: openHandLocalizedText(
              context,
              zh: '暂无关键词。',
              en: 'No keywords yet.',
            ),
            onAdd: _addRouteKeyword,
            onSubmitted: (_) => _addRouteKeyword(),
            onRemove: (value) => setState(() => _routeKeywords.remove(value)),
            onReorder: (oldIndex, newIndex) => setState(
              () => _reorderStringList(_routeKeywords, oldIndex, newIndex),
            ),
            keyPrefix: 'agent-route-keyword',
          ),
          const SizedBox(height: 12),
          _editableStringChips(
            label: openHandLocalizedText(context, zh: '领域', en: 'Domains'),
            inputController: _routeDomainInput,
            values: _routeDomains,
            emptyText: openHandLocalizedText(
              context,
              zh: '暂无领域。',
              en: 'No domains yet.',
            ),
            onAdd: _addRouteDomain,
            onSubmitted: (_) => _addRouteDomain(),
            onRemove: (value) => setState(() => _routeDomains.remove(value)),
            onReorder: (oldIndex, newIndex) => setState(
              () => _reorderStringList(_routeDomains, oldIndex, newIndex),
            ),
            keyPrefix: 'agent-route-domain',
          ),
          const SizedBox(height: 12),
          _editableStringChips(
            label: openHandLocalizedText(context, zh: '意图', en: 'Intents'),
            inputController: _routeIntentInput,
            values: _routeIntents,
            emptyText: openHandLocalizedText(
              context,
              zh: '暂无意图。',
              en: 'No intents yet.',
            ),
            onAdd: _addRouteIntent,
            onSubmitted: (_) => _addRouteIntent(),
            onRemove: (value) => setState(() => _routeIntents.remove(value)),
            onReorder: (oldIndex, newIndex) => setState(
              () => _reorderStringList(_routeIntents, oldIndex, newIndex),
            ),
            keyPrefix: 'agent-route-intent',
          ),
          const SizedBox(height: 12),
          _keyValueEditor(
            title: openHandLocalizedText(
              context,
              zh: '扩展路由字段',
              en: 'Extra routing fields',
            ),
            entries: _routeExtraFields,
            keyLabel: openHandLocalizedText(context, zh: '字段', en: 'Field'),
            valueLabel: openHandLocalizedText(context, zh: '值', en: 'Value'),
            emptyText: openHandLocalizedText(
              context,
              zh: '无需扩展字段时可留空。',
              en: 'Leave empty when no extra routing fields are needed.',
            ),
            onAdd: _addRouteExtraEntry,
            onRemove: _removeRouteExtraEntry,
            onChanged: () => setState(() {}),
            framed: false,
          ),
        ],
      ),
    );
  }

  Widget _directoryPickerField({
    required String label,
    required String value,
    required VoidCallback onPick,
    required VoidCallback onClear,
  }) {
    final colors = Theme.of(context).colorScheme;
    final hasValue = value.trim().isNotEmpty;
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Row(
        children: [
          Icon(
            hasValue ? Icons.folder_rounded : Icons.folder_open_rounded,
            color: hasValue ? colors.primary : colors.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hasValue
                  ? OpenHandPaths.shortenHomePath(value)
                  : openHandLocalizedText(
                      context,
                      zh: '请选择目录',
                      en: 'Pick a directory',
                    ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: hasValue ? colors.onSurface : colors.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: openHandLocalizedText(
              context,
              zh: hasValue ? '更换目录' : '选择目录',
              en: hasValue ? 'Change directory' : 'Pick directory',
            ),
            onPressed: onPick,
            icon: const Icon(Icons.drive_folder_upload_rounded),
          ),
          if (hasValue) ...[
            const SizedBox(width: 6),
            IconButton(
              tooltip: openHandLocalizedText(
                context,
                zh: '清除目录',
                en: 'Clear directory',
              ),
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ],
      ),
    );
  }

  Widget _directoryListPicker({
    required String label,
    required List<String> values,
    required String emptyText,
    required VoidCallback onAdd,
    required ValueChanged<String> onRemove,
    required void Function(int oldIndex, int newIndex) onReorder,
    String keyPrefix = 'agent-directory',
  }) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: onAdd,
              icon: const Icon(Icons.create_new_folder_rounded),
              label: Text(
                openHandLocalizedText(
                  context,
                  zh: '选择目录',
                  en: 'Pick directory',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _reorderableChips(
            values: values,
            emptyText: emptyText,
            onRemove: onRemove,
            onReorder: onReorder,
            labelBuilder: OpenHandPaths.shortenHomePath,
            keyPrefix: keyPrefix,
          ),
        ],
      ),
    );
  }

  Widget _editableStringChips({
    required String label,
    required TextEditingController inputController,
    required List<String> values,
    required String emptyText,
    required VoidCallback onAdd,
    required ValueChanged<String> onSubmitted,
    required ValueChanged<String> onRemove,
    required void Function(int oldIndex, int newIndex) onReorder,
    IconData addIcon = Icons.add_rounded,
    String keyPrefix = 'agent-chip',
  }) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: inputController,
                  decoration: InputDecoration(
                    hintText: openHandLocalizedText(
                      context,
                      zh: '输入后点击添加',
                      en: 'Enter text, then add',
                    ),
                  ),
                  onSubmitted: onSubmitted,
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                tooltip: openHandLocalizedText(context, zh: '添加', en: 'Add'),
                onPressed: onAdd,
                icon: Icon(addIcon),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _reorderableChips(
            values: values,
            emptyText: emptyText,
            onRemove: onRemove,
            onReorder: onReorder,
            keyPrefix: keyPrefix,
          ),
        ],
      ),
    );
  }

  Widget _reorderableChips({
    required List<String> values,
    required String emptyText,
    required ValueChanged<String> onRemove,
    required void Function(int oldIndex, int newIndex) onReorder,
    String Function(String value)? labelBuilder,
    String keyPrefix = 'agent-chip',
  }) {
    return _AnimatedReorderableChipStrip(
      values: values,
      emptyText: emptyText,
      onRemove: onRemove,
      onReorder: onReorder,
      labelBuilder: labelBuilder,
      keyPrefix: keyPrefix,
    );
  }

  Widget _keyValueEditor({
    required String title,
    required List<_KeyValueDraft> entries,
    required String keyLabel,
    required String valueLabel,
    required String emptyText,
    required VoidCallback onAdd,
    required ValueChanged<_KeyValueDraft> onRemove,
    VoidCallback? onChanged,
    bool framed = true,
  }) {
    return _AgentKeyValueEditor(
      title: title,
      entries: entries,
      keyLabel: keyLabel,
      valueLabel: valueLabel,
      emptyText: emptyText,
      onAdd: onAdd,
      onRemove: onRemove,
      onChanged: onChanged,
      framed: framed,
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

  Widget _policyDropdown({
    required String label,
    required String value,
    required List<String> values,
    required ValueChanged<String> onChanged,
  }) {
    final effectiveValue = values.contains(value) ? value : values.first;
    return DropdownButtonFormField<String>(
      initialValue: effectiveValue,
      decoration: InputDecoration(labelText: label),
      items: values
          .map(
            (item) => DropdownMenuItem(
              value: item,
              child: Text(_agentPolicyOptionLabel(context, item)),
            ),
          )
          .toList(),
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    );
  }

  Widget _ratioSlider(
    String label,
    double value,
    ValueChanged<double> onChanged,
  ) {
    final normalized = value.clamp(0, 1).toDouble();
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Row(
        children: [
          Expanded(
            child: Slider(
              value: normalized,
              divisions: 20,
              label: '${(normalized * 100).round()}%',
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              '${(normalized * 100).round()}%',
              textAlign: TextAlign.end,
            ),
          ),
        ],
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

  Future<void> _pickAvatarImage() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const <XTypeGroup>[
          XTypeGroup(label: 'Images', extensions: _agentImageExtensions),
        ],
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      final edited = await showImageEditorDialog(
        context,
        imageBytes: bytes,
        imageSizeLimitBytes: 512 * 1024,
      );
      if (edited == null || !mounted) return;
      final path = await _persistAvatarImage(
        sourceName: file.name,
        bytes: edited.bytes,
        format: edited.format,
      );
      if (!mounted) return;
      setState(() => _avatar.text = path);
    } catch (error) {
      if (!mounted) return;
      OpenHandSnackBar.showError(
        context,
        openHandLocalizedText(
          context,
          zh: '无法处理所选头像：$error',
          en: 'Could not process the selected avatar: $error',
        ),
      );
    }
  }

  Future<String> _persistAvatarImage({
    required String sourceName,
    required List<int> bytes,
    required String format,
  }) async {
    final directory = Directory(
      p.join(OpenHandPaths.defaultRootDirectoryPath(), 'agents', 'avatars'),
    );
    await directory.create(recursive: true);
    final rawBase = p.basenameWithoutExtension(sourceName).trim();
    final safeBase = rawBase
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final baseName = safeBase.isEmpty ? 'agent-avatar' : safeBase;
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final extension = format == 'png' ? 'png' : 'jpg';
    final file = File(
      p.join(directory.path, '$baseName-$timestamp.$extension'),
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> _pickWorkspacePath() async {
    final path = await _pickDirectory();
    if (path == null || !mounted) return;
    final normalized = OpenHandPaths.normalizeOptionalPath(path);
    setState(() {
      _workspacePath.text = normalized;
      if (normalized.isNotEmpty) {
        final workspaceKey = normalized.toLowerCase();
        _workspaceScopePaths.removeWhere(
          (value) =>
              OpenHandPaths.normalizeOptionalPath(value).toLowerCase() ==
              workspaceKey,
        );
      }
    });
  }

  Future<void> _pickWorkspaceScopePath() async {
    final path = await _pickDirectory();
    if (path == null || !mounted) return;
    final normalized = OpenHandPaths.normalizeOptionalPath(path);
    if (normalized.isEmpty) return;
    setState(() {
      _addUniqueString(_workspaceScopePaths, normalized);
    });
  }

  Future<String?> _pickDirectory() {
    return getDirectoryPath(
      confirmButtonText: openHandLocalizedText(
        context,
        zh: '选择目录',
        en: 'Pick directory',
      ),
    );
  }

  Future<void> _refreshCapabilities() async {
    if (_refreshingCapabilities) return;
    setState(() => _refreshingCapabilities = true);
    try {
      await Future.wait(<Future<void>>[
        context.read<SkillsController>().refresh(),
        context.read<KnowledgeBaseController>().initialize(),
        context.read<MemoryController>().refresh(),
        context.read<McpController>().refresh(),
        context.read<CronsController>().refresh(),
        context.read<HooksController>().refresh(),
      ]);
      if (!mounted) return;
      OpenHandSnackBar.showInfo(
        context,
        openHandLocalizedText(
          context,
          zh: '能力配置已刷新。',
          en: 'Capabilities refreshed.',
        ),
      );
    } catch (error) {
      if (!mounted) return;
      OpenHandSnackBar.showError(
        context,
        openHandLocalizedText(
          context,
          zh: '刷新能力配置失败：$error',
          en: 'Failed to refresh capabilities: $error',
        ),
      );
    } finally {
      if (mounted) setState(() => _refreshingCapabilities = false);
    }
  }

  void _addRouteKeyword() {
    _addStringFromController(_routeKeywords, _routeKeywordInput);
  }

  void _addRouteDomain() {
    _addStringFromController(_routeDomains, _routeDomainInput);
  }

  void _addRouteIntent() {
    _addStringFromController(_routeIntents, _routeIntentInput);
  }

  void _addTaskLabel() {
    _addStringFromController(_taskLabelValues, _taskLabelInput);
  }

  void _addWorkerTag() {
    _addStringFromController(_workerTagValues, _workerTagInput);
  }

  void _addStringFromController(
    List<String> values,
    TextEditingController controller,
  ) {
    final value = controller.text.trim();
    if (value.isEmpty) return;
    setState(() {
      _addUniqueString(values, value);
      controller.clear();
    });
  }

  void _addRouteExtraEntry() {
    setState(() => _routeExtraFields.add(_KeyValueDraft()));
  }

  void _removeRouteExtraEntry(_KeyValueDraft entry) {
    setState(() {
      _routeExtraFields.remove(entry);
      entry.dispose();
    });
  }

  void _addMetadataEntry() {
    setState(() => _metadataEntries.add(_KeyValueDraft()));
  }

  void _removeMetadataEntry(_KeyValueDraft entry) {
    setState(() {
      _metadataEntries.remove(entry);
      entry.dispose();
    });
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

  void _submitAgent({
    required BuildContext dialogContext,
    required List<AiBuiltinToolConfig> builtinToolConfigs,
  }) {
    final validationError = _validateDraft();
    if (validationError != null) {
      OpenHandSnackBar.showError(context, validationError);
      return;
    }
    final metadata = _metadataMapFromEntries();
    Navigator.of(dialogContext, rootNavigator: true).pop(
      _buildAgent(builtinToolConfigs: builtinToolConfigs, metadata: metadata),
    );
  }

  String? _validateDraft() {
    final duplicateMetadata = _firstDuplicateKey(_metadataEntries);
    if (duplicateMetadata != null) {
      return openHandLocalizedText(
        context,
        zh: '元数据字段重复：$duplicateMetadata',
        en: 'Duplicate metadata field: $duplicateMetadata',
      );
    }
    final duplicateRoute = _firstDuplicateKey(_routeExtraFields);
    if (duplicateRoute != null) {
      return openHandLocalizedText(
        context,
        zh: '路由扩展字段重复：$duplicateRoute',
        en: 'Duplicate routing field: $duplicateRoute',
      );
    }
    return null;
  }

  AgentRoutingMetadata _routePreview() {
    return AgentRoutingMetadata.fromAgent(
      AgentProfile(
        id: widget.initialAgent?.id ?? 'route-preview',
        name: _name.text.trim().isEmpty ? 'Route Preview' : _name.text.trim(),
        routeFrontMatter: _buildRouteFrontMatter(),
        taskLabels: _taskLabelValues,
        skillNames: _skillNames.toList(growable: false),
      ),
    );
  }

  AgentProfile _buildAgent({
    required List<AiBuiltinToolConfig> builtinToolConfigs,
    required Map<String, Object?> metadata,
  }) {
    final now = DateTime.now().toUtc();
    final previous = widget.initialAgent;
    final maxWorkers = _maxWorkers.clamp(1, 999);
    final minWorkers = _minWorkers.clamp(0, maxWorkers);
    final taskLabels = _dedupeStrings(_taskLabelValues);
    final workerTags = _dedupeStrings(_workerTagValues);
    final workspacePath = _normalizedWorkspacePath();
    final workspaceScopePaths = _normalizedWorkspaceScopePaths(workspacePath);
    final builtinToolNames = _normalizedBuiltinToolSelection(
      builtinToolConfigs,
    ).toList();
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
      routeFrontMatter: _buildRouteFrontMatter(),
      welcomeMessage: _welcomeMessage.text.trim(),
      modelProviderConfigId: _modelProviderConfigId,
      modelId: _modelId,
      persona: _persona.text.trim(),
      responsibilityBoundary: _boundary.text.trim(),
      skillNames: _skillNames.toList(),
      knowledgeSourceIds: _knowledgeSourceIds.toList(),
      memoryIds: _memoryIds.toList(),
      taskLabels: taskLabels,
      mcpServerNames: _mcpServerNames.toList(),
      builtinToolNames: builtinToolNames,
      workspacePath: workspacePath,
      workspaceScope: workspaceScopePaths.join('\n'),
      workspaceScopePaths: workspaceScopePaths,
      cronIds: _cronIds.toList(),
      hookIds: _hookIds.toList(),
      selfLearningEnabled: _selfLearningEnabled,
      enabled: _enabled,
      executionMode: _executionMode,
      lifecycleState: _enabled
          ? AgentLifecycleState.running
          : AgentLifecycleState.stopped,
      scaleSettings: AgentScaleSettings(
        minWorkers: minWorkers,
        maxWorkers: maxWorkers,
        scaleOutThreshold: _scaleOutThreshold.clamp(0, 1).toDouble(),
        scaleInThreshold: _scaleInThreshold.clamp(0, 1).toDouble(),
        workerRemovalPolicy: _workerRemovalPolicy,
        retryPolicy: _retryPolicy,
        maxRetries: _maxRetries,
        schedulerPolicy: _schedulerPolicy,
        tags: workerTags,
      ),
      tasks: previous?.tasks ?? const <AgentTask>[],
      approvals: previous?.approvals ?? const <AgentApprovalRequest>[],
      activities: previous?.activities ?? const <AgentActivityEvent>[],
      auditEvents: previous?.auditEvents ?? const <AgentAuditEvent>[],
      kpis: _kpis,
      workers: previous?.workers ?? const <AgentWorker>[],
      resourceUsage: previous?.resourceUsage ?? const AgentResourceUsage(),
      metadata: metadata,
      createdAt: previous?.createdAt ?? now,
      updatedAt: now,
    );
  }

  String _buildRouteFrontMatter() {
    final data = <String, Object?>{};
    final route = _routeName.text.trim();
    if (route.isNotEmpty) data['route'] = route;
    final priority = _parseStructuredValue(_routePriority.text);
    if (priority != null && '$priority'.trim().isNotEmpty) {
      data['priority'] = priority;
    }
    final description = _routeDescription.text.trim();
    if (description.isNotEmpty) data['description'] = description;
    final keywords = _dedupeStrings(_routeKeywords);
    final domains = _dedupeStrings(_routeDomains);
    final intents = _dedupeStrings(_routeIntents);
    if (keywords.isNotEmpty) data['keywords'] = keywords;
    if (domains.isNotEmpty) data['domains'] = domains;
    if (intents.isNotEmpty) data['intents'] = intents;
    data.addAll(_mapFromEntries(_routeExtraFields));
    if (data.isEmpty) return '';
    return '---\n${const JsonEncoder.withIndent('  ').convert(data)}\n---';
  }

  Map<String, Object?> _metadataMapFromEntries() {
    return _mapFromEntries(_metadataEntries);
  }

  Map<String, Object?> _mapFromEntries(List<_KeyValueDraft> entries) {
    return _agentKeyValueDraftMapFromEntries(entries);
  }

  String? _firstDuplicateKey(List<_KeyValueDraft> entries) {
    return _agentFirstDuplicateKey(entries);
  }

  String _normalizedWorkspacePath() {
    return OpenHandPaths.normalizeOptionalPath(_workspacePath.text);
  }

  List<String> _normalizedWorkspaceScopePaths(String workspacePath) {
    final workspaceKey = workspacePath.trim().toLowerCase();
    final seen = <String>{};
    final result = <String>[];
    for (final raw in _workspaceScopePaths) {
      final value = OpenHandPaths.normalizeOptionalPath(raw);
      if (value.isEmpty) continue;
      final key = value.toLowerCase();
      if (workspaceKey.isNotEmpty && key == workspaceKey) continue;
      if (seen.add(key)) result.add(value);
    }
    return result;
  }

  Object? _parseStructuredValue(String raw) {
    return _agentParseStructuredValue(raw);
  }

  List<_KeyValueDraft> _metadataEntriesFromMap(Map<String, Object?>? map) {
    return _keyValueEntriesFromMap(map);
  }

  List<_KeyValueDraft> _routeExtraEntries(Map<String, Object?> route) {
    const reserved = <String>{
      'route',
      'routes',
      'priority',
      'description',
      'keywords',
      'keyword',
      'triggers',
      'trigger',
      'domains',
      'domain',
      'intents',
      'intent',
    };
    final entries = <_KeyValueDraft>[];
    for (final entry in route.entries) {
      if (reserved.contains(entry.key.toLowerCase())) continue;
      entries.add(_KeyValueDraft(key: entry.key, value: entry.value));
    }
    return entries;
  }

  String _stringFromRouteValue(Object? value, String fallback) {
    final text = value == null ? '' : '$value'.trim();
    return text.isEmpty ? fallback : text;
  }

  List<String> _routeStringsFromValues(Iterable<Object?> values) {
    return _dedupeStrings(values.expand(_stringsFromStructuredValue));
  }

  List<String> _stringsFromStructuredValue(Object? raw) {
    if (raw == null) return const <String>[];
    if (raw is Iterable) {
      return raw.expand(_stringsFromStructuredValue).toList(growable: false);
    }
    return _splitStructuredText('$raw');
  }

  List<String> _splitStructuredText(String value) {
    return value
        .split(RegExp(r'[\r\n,，;；]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  List<String> _dedupeStrings(Iterable<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final raw in values) {
      final value = raw.trim();
      if (value.isEmpty) continue;
      if (seen.add(value.toLowerCase())) result.add(value);
    }
    return result;
  }

  void _addUniqueString(List<String> values, String raw) {
    final value = raw.trim();
    if (value.isEmpty) return;
    final exists = values.any(
      (item) => item.toLowerCase() == value.toLowerCase(),
    );
    if (!exists) values.add(value);
  }

  void _reorderStringList(List<String> values, int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= values.length) return;
    final targetIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    if (targetIndex < 0 || targetIndex >= values.length) return;
    final item = values.removeAt(oldIndex);
    values.insert(targetIndex, item);
  }

  List<_Option> _builtinToolOptions(List<AiBuiltinToolConfig> configs) {
    final agentTools = <_Option>[];
    final regularTools = <_Option>[];
    for (final config in configs) {
      final id = _builtinToolOptionId(config);
      final option = _Option(id, config.effectiveName, config.kind.name);
      if (config.kind.isAgentCoordinationTool) {
        agentTools.add(option);
      } else {
        regularTools.add(option);
      }
    }
    return <_Option>[...regularTools, ...agentTools];
  }

  String _builtinToolOptionId(AiBuiltinToolConfig config) {
    if (config.kind.isAgentCoordinationTool) {
      return config.kind.name;
    }
    return config.isCustom ? config.effectiveName : config.kind.name;
  }

  Set<String> _normalizedBuiltinToolSelection(
    List<AiBuiltinToolConfig> configs,
  ) {
    final aliases = <String, String>{};
    for (final config in configs) {
      final id = _builtinToolOptionId(config);
      aliases[config.kind.name.toLowerCase()] = id;
      aliases[config.effectiveName.toLowerCase()] = id;
      if (config.customToolName != null) {
        aliases[config.customToolName!.trim().toLowerCase()] = id;
      }
    }
    final normalized = <String>{};
    for (final raw in _builtinToolNames) {
      final value = raw.trim();
      if (value.isEmpty) continue;
      normalized.add(aliases[value.toLowerCase()] ?? value);
    }
    return normalized;
  }
}

class _AgentAvatarContent extends StatelessWidget {
  const _AgentAvatarContent({
    required this.avatar,
    required this.fallback,
    required this.size,
    this.textStyle,
  });

  final String avatar;
  final String fallback;
  final double size;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    if (_agentAvatarLooksLikeImagePath(avatar)) {
      return Image.file(
        File(avatar),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _fallbackText(),
      );
    }
    return _fallbackText();
  }

  Widget _fallbackText() {
    final label = avatar.trim().isEmpty ? fallback : avatar.trim();
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.clip,
      style: textStyle,
    );
  }
}

class _AgentKeyValueEditor extends StatelessWidget {
  const _AgentKeyValueEditor({
    required this.title,
    required this.entries,
    required this.keyLabel,
    required this.valueLabel,
    required this.emptyText,
    required this.onAdd,
    required this.onRemove,
    this.onChanged,
    this.framed = true,
  });

  final String title;
  final List<_KeyValueDraft> entries;
  final String keyLabel;
  final String valueLabel;
  final String emptyText;
  final VoidCallback onAdd;
  final ValueChanged<_KeyValueDraft> onRemove;
  final VoidCallback? onChanged;
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final addButton = IconButton.filledTonal(
      tooltip: openHandLocalizedText(context, zh: '添加字段', en: 'Add field'),
      onPressed: onAdd,
      icon: const Icon(Icons.add_rounded),
    );
    final content = entries.isEmpty
        ? Text(
            emptyText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        : Column(
            children: [
              for (final entry in entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: TextField(
                          controller: entry.key,
                          decoration: InputDecoration(labelText: keyLabel),
                          onChanged: (_) => onChanged?.call(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 7,
                        child: TextField(
                          controller: entry.value,
                          decoration: InputDecoration(labelText: valueLabel),
                          onChanged: (_) => onChanged?.call(),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: openHandLocalizedText(
                          context,
                          zh: '删除字段',
                          en: 'Remove field',
                        ),
                        onPressed: () => onRemove(entry),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
            ],
          );
    if (framed) {
      return _AgentEditorPanel(
        title: title,
        icon: Icons.schema_rounded,
        trailing: addButton,
        child: content,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            addButton,
          ],
        ),
        const SizedBox(height: 8),
        content,
      ],
    );
  }
}

class _AgentEditorPanel extends StatelessWidget {
  const _AgentEditorPanel({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return AnimatedContainer(
      duration: kThemeAnimationDuration,
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _AnimatedReorderableChipStrip extends StatelessWidget {
  const _AnimatedReorderableChipStrip({
    required this.values,
    required this.emptyText,
    required this.onRemove,
    required this.onReorder,
    this.labelBuilder,
    this.keyPrefix = 'agent-chip',
  });

  final List<String> values;
  final String emptyText;
  final ValueChanged<String> onRemove;
  final void Function(int oldIndex, int newIndex) onReorder;
  final String Function(String value)? labelBuilder;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final animationSettings = _agentChipAnimationSettings(context);
    if (values.isEmpty) {
      return _AgentChipStripSwitcher(
        settings: animationSettings,
        child: Text(
          key: const ValueKey<String>('agent-chip-strip-empty'),
          emptyText,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return _AgentChipStripSwitcher(
      settings: animationSettings,
      child: SizedBox(
        key: const ValueKey<String>('agent-chip-strip-list'),
        height: _agentChipStripHeight,
        child: ReorderableListView.builder(
          scrollDirection: Axis.horizontal,
          primary: false,
          buildDefaultDragHandles: false,
          physics: openHandDialogAwareScrollPhysics(context),
          proxyDecorator: (child, index, animation) {
            return AnimatedBuilder(
              animation: animation,
              child: child,
              builder: (context, child) {
                final lift = Curves.easeOutCubic.transform(animation.value);
                return Transform.scale(
                  scale: 1 + (0.05 * lift),
                  child: Material(
                    color: Colors.transparent,
                    elevation: 4 * lift,
                    borderRadius: BorderRadius.circular(999),
                    child: child,
                  ),
                );
              },
            );
          },
          itemCount: values.length,
          onReorder: onReorder,
          itemBuilder: (context, index) {
            final value = values[index];
            return Padding(
              key: ValueKey<String>('$keyPrefix-$value'),
              padding: const EdgeInsets.only(right: 8),
              child: AnimatedRemovableChip(
                settings: animationSettings,
                onRemove: () => onRemove(value),
                builder: (context, requestRemove) {
                  return _AgentDraggableChip(
                    label: labelBuilder?.call(value) ?? value,
                    onDeleted: requestRemove,
                    dragIndex: index,
                    dragKey: ValueKey<String>('$keyPrefix-drag-$value'),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AgentChipStripSwitcher extends StatelessWidget {
  const _AgentChipStripSwitcher({required this.settings, required this.child});

  final DialogAnimationSettings settings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: settings.duration,
      reverseDuration: settings.duration,
      switchInCurve: settings.curve.curve,
      switchOutCurve: settings.curve.reverseCurve,
      transitionBuilder: (child, animation) {
        return SizeTransition(
          axisAlignment: -1,
          sizeFactor: animation,
          child: buildAnimationStyleTransition(
            animation: animation,
            settings: settings,
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _AgentDraggableChip extends StatelessWidget {
  const _AgentDraggableChip({
    required this.label,
    required this.onDeleted,
    required this.dragIndex,
    required this.dragKey,
  });

  final String label;
  final VoidCallback onDeleted;
  final int dragIndex;
  final Key dragKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(
          start: 8,
          end: 4,
          top: 6,
          bottom: 6,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReorderableDragStartListener(
              key: dragKey,
              index: dragIndex,
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Tooltip(
                  message: openHandLocalizedText(
                    context,
                    zh: '拖拽排序',
                    en: 'Drag to reorder',
                  ),
                  child: Semantics(
                    label: openHandLocalizedText(
                      context,
                      zh: '拖拽排序 $label',
                      en: 'Drag to reorder $label',
                    ),
                    button: true,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: 28,
                        maxWidth: 304,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.drag_indicator_rounded,
                            size: 18,
                            color: colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: colors.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: openHandLocalizedText(context, zh: '删除', en: 'Remove'),
              onPressed: onDeleted,
              icon: const Icon(Icons.close_rounded),
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            ),
          ],
        ),
      ),
    );
  }
}

DialogAnimationSettings _agentChipAnimationSettings(BuildContext context) {
  try {
    return context.select<SettingsController, DialogAnimationSettings>(
      (controller) => controller.chipAnimationSettings,
    );
  } catch (_) {
    return OpenHandMotionDefaults.listItem;
  }
}

class _CapabilityPanel extends StatelessWidget {
  const _CapabilityPanel({
    required this.title,
    required this.icon,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final String title;
  final IconData icon;
  final List<_Option> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _AgentEditorPanel(
      title: title,
      icon: icon,
      child: options.isEmpty
          ? Text(
              l10n.agentsNoOptionsAvailable,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 152),
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
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _KeyValueDraft {
  _KeyValueDraft({String key = '', Object? value})
    : key = TextEditingController(text: key),
      value = TextEditingController(text: _valueText(value));

  final TextEditingController key;
  final TextEditingController value;

  void dispose() {
    key.dispose();
    value.dispose();
  }

  static String _valueText(Object? value) {
    if (value == null) return '';
    if (value is String) {
      return value.trim().toLowerCase() == 'null' ? '' : value;
    }
    try {
      return jsonEncode(value);
    } catch (_) {
      return '$value';
    }
  }
}

List<_KeyValueDraft> _keyValueEntriesFromMap(Map<String, Object?>? map) {
  if (map == null || map.isEmpty) return <_KeyValueDraft>[];
  return map.entries
      .map((entry) => _KeyValueDraft(key: entry.key, value: entry.value))
      .toList();
}

Map<String, Object?> _agentKeyValueDraftMapFromEntries(
  Iterable<_KeyValueDraft> entries,
) {
  final result = <String, Object?>{};
  for (final entry in entries) {
    final key = entry.key.text.trim();
    if (key.isEmpty) continue;
    result[key] = _agentParseStructuredValue(entry.value.text);
  }
  return result;
}

String? _agentFirstDuplicateKey(Iterable<_KeyValueDraft> entries) {
  final seen = <String>{};
  for (final entry in entries) {
    final key = entry.key.text.trim();
    if (key.isEmpty) continue;
    final normalized = key.toLowerCase();
    if (!seen.add(normalized)) return key;
  }
  return null;
}

Object? _agentParseStructuredValue(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '';
  try {
    return jsonDecode(value);
  } on FormatException {
    return value;
  }
}

bool _agentAvatarLooksLikeImagePath(String value) {
  final extension = p
      .extension(value.trim())
      .toLowerCase()
      .replaceFirst('.', '');
  return extension.isNotEmpty && _agentImageExtensions.contains(extension);
}

String _agentPolicyOptionLabel(BuildContext context, String value) {
  return switch (value) {
    'least_busy' => openHandLocalizedText(
      context,
      zh: '空闲优先',
      en: 'Least busy',
    ),
    'priority_first' => openHandLocalizedText(
      context,
      zh: '优先级优先',
      en: 'Priority first',
    ),
    'round_robin' => openHandLocalizedText(
      context,
      zh: '轮询分配',
      en: 'Round robin',
    ),
    'newest_first' => openHandLocalizedText(
      context,
      zh: '最新优先',
      en: 'Newest first',
    ),
    'bounded_retry' => openHandLocalizedText(
      context,
      zh: '有限重试',
      en: 'Bounded retry',
    ),
    'none' => openHandLocalizedText(context, zh: '不重试', en: 'No retry'),
    _ => value,
  };
}

class _AgentRoutePreviewCard extends StatelessWidget {
  const _AgentRoutePreviewCard({required this.metadata});

  final AgentRoutingMetadata metadata;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasStructuredRoute = metadata.frontMatter.isNotEmpty;
    final hasRawRoute = metadata.preview.isNotEmpty;
    final keywords = metadata.keywords
        .take(_agentRoutePreviewKeywordLimit)
        .toList(growable: false);
    final hasKeywordSignals = keywords.isNotEmpty;
    final isActive = hasStructuredRoute || hasKeywordSignals;
    final title = hasStructuredRoute
        ? openHandLocalizedText(
            context,
            zh: '路由预览已解析',
            en: 'Route preview parsed',
          )
        : hasRawRoute
        ? openHandLocalizedText(
            context,
            zh: '路由规则待完善',
            en: 'Route rule needs refinement',
          )
        : hasKeywordSignals
        ? openHandLocalizedText(
            context,
            zh: '已读取路由线索',
            en: 'Routing signals detected',
          )
        : openHandLocalizedText(context, zh: '暂无路由规则', en: 'No route rule yet');
    final subtitle = hasStructuredRoute
        ? openHandLocalizedText(
            context,
            zh: '字段 ${metadata.frontMatter.length} 个 · 关键词 ${metadata.keywords.length} 个',
            en: '${metadata.frontMatter.length} field(s) · ${metadata.keywords.length} keyword(s)',
          )
        : hasRawRoute
        ? openHandLocalizedText(
            context,
            zh: '未识别到有效字段，请完善上方结构化路由信息。',
            en: 'No valid fields were detected. Complete the structured routing fields above.',
          )
        : hasKeywordSignals
        ? openHandLocalizedText(
            context,
            zh: '技能与任务标签会参与基础分流；补充结构化路由可提升命中精度。',
            en: 'Skills and task labels can guide routing. Add structured routing fields for better precision.',
          )
        : openHandLocalizedText(
            context,
            zh: '填写结构化路由信息后，智能体会据此参与任务分流。',
            en: 'Add structured routing fields so this agent can join task routing.',
          );
    return AnimatedContainer(
      duration: kThemeAnimationDuration,
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isActive
            ? colors.primaryContainer.withValues(alpha: 0.34)
            : colors.surfaceContainerHighest.withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isActive
              ? colors.primary.withValues(alpha: 0.28)
              : colors.outlineVariant,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isActive ? Icons.route_rounded : Icons.route_outlined,
            color: isActive ? colors.primary : colors.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isActive ? colors.onPrimaryContainer : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isActive
                        ? colors.onPrimaryContainer
                        : colors.onSurfaceVariant,
                  ),
                ),
                if (keywords.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final keyword in keywords)
                        Chip(
                          label: Text(keyword),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Option {
  const _Option(this.id, this.label, this.subtitle);

  final String id;
  final String label;
  final String subtitle;
}

Set<String> _mergeOptionGroupSelection({
  required Set<String> current,
  required Set<String> groupSelection,
  required List<_Option> groupOptions,
}) {
  final groupIds = groupOptions.map((option) => option.id).toSet();
  return <String>{
    for (final value in current)
      if (!groupIds.contains(value)) value,
    ...groupSelection,
  };
}

class _OptionChips extends StatelessWidget {
  const _OptionChips({
    required this.title,
    required this.options,
    required this.selected,
    required this.onChanged,
    required this.keyPrefix,
  });

  final String title;
  final List<_Option> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final optionById = {for (final option in options) option.id: option};
    final selectedIds = selected.toList(growable: false);
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
          const SizedBox(height: 10),
          Text(
            openHandLocalizedText(context, zh: '已选顺序', en: 'Selected order'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 6),
          _AnimatedReorderableChipStrip(
            values: selectedIds,
            emptyText: openHandLocalizedText(
              context,
              zh: '尚未选择$title。',
              en: 'No $title selected yet.',
            ),
            onRemove: (id) => onChanged({...selected}..remove(id)),
            onReorder: (oldIndex, newIndex) {
              final ordered = selected.toList();
              if (oldIndex < 0 || oldIndex >= ordered.length) return;
              final targetIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
              if (targetIndex < 0 || targetIndex >= ordered.length) return;
              final item = ordered.removeAt(oldIndex);
              ordered.insert(targetIndex, item);
              onChanged(ordered.toSet());
            },
            labelBuilder: (id) => _optionChipLabel(optionById[id], id),
            keyPrefix: keyPrefix,
          ),
        ],
      ),
    );
  }
}

String _optionChipLabel(_Option? option, String fallback) {
  if (option == null) return fallback;
  final subtitle = option.subtitle.trim();
  if (subtitle.isEmpty || subtitle == option.label) return option.label;
  return '${option.label} - $subtitle';
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

class _AgentAuditReportSummary {
  _AgentAuditReportSummary({
    required this.eventCount,
    required this.requests,
    required this.tokens,
    required this.busyWorkers,
    required this.tasks,
    required this.capabilities,
    required this.workers,
    required this.cpuPressure,
    required this.tokenPressure,
    required this.persistedPressure,
  });

  factory _AgentAuditReportSummary.fromAgent(AgentProfile agent) {
    final capabilities = _agentAuditCapabilityStats(agent.auditEvents);
    final workers = _agentAuditWorkerStats(agent);
    final requests = agent.auditEvents.fold<int>(
      0,
      (sum, event) => sum + event.requestCount,
    );
    final tokens = agent.auditEvents.fold<int>(
      0,
      (sum, event) => sum + event.tokenUsage,
    );
    final resource = agent.resourceUsage;
    final tokenPressure = resource.tokenBudget <= 0
        ? 0.0
        : (resource.tokenUsed / resource.tokenBudget).clamp(0, 1).toDouble();
    final persistedPressure = resource.diskBytes <= 0
        ? 0.0
        : (resource.persistedBytes / resource.diskBytes).clamp(0, 1).toDouble();
    return _AgentAuditReportSummary(
      eventCount: agent.auditEvents.length,
      requests: requests,
      tokens: tokens,
      busyWorkers: _agentWorkerStatusCount(agent, AgentWorkerStatus.busy),
      tasks: _agentAuditTaskStats(agent.tasks),
      capabilities: capabilities,
      workers: workers,
      cpuPressure: resource.cpuPercent.clamp(0, 1).toDouble(),
      tokenPressure: tokenPressure,
      persistedPressure: persistedPressure,
    );
  }

  final int eventCount;
  final int requests;
  final int tokens;
  final int busyWorkers;
  final List<_AgentAuditTaskStat> tasks;
  final List<_AgentAuditCapabilityStat> capabilities;
  final List<_AgentAuditWorkerStat> workers;
  final double cpuPressure;
  final double tokenPressure;
  final double persistedPressure;
}

class _AgentAuditTaskStat {
  const _AgentAuditTaskStat({
    required this.bucket,
    required this.count,
    required this.ratio,
  });

  final String bucket;
  final int count;
  final double ratio;
}

class _AgentAuditCapabilityStat {
  const _AgentAuditCapabilityStat({
    required this.type,
    required this.name,
    required this.events,
    required this.requests,
    required this.tokens,
  });

  final String type;
  final String name;
  final int events;
  final int requests;
  final int tokens;
}

class _AgentAuditWorkerStat {
  const _AgentAuditWorkerStat({
    required this.id,
    required this.name,
    required this.status,
    required this.assignedTasks,
    required this.executedTasks,
    required this.requests,
    required this.tokens,
    required this.busyScore,
  });

  final String id;
  final String name;
  final AgentWorkerStatus status;
  final int assignedTasks;
  final int executedTasks;
  final int requests;
  final int tokens;
  final double busyScore;
}

List<_AgentAuditTaskStat> _agentAuditTaskStats(List<AgentTask> tasks) {
  if (tasks.isEmpty) return const <_AgentAuditTaskStat>[];
  final buckets = <String, int>{
    'completed': 0,
    'running': 0,
    'queued': 0,
    'blocked': 0,
    'terminal': 0,
  };
  for (final task in tasks) {
    final bucket = switch (task.status) {
      AgentTaskStatus.completed => 'completed',
      AgentTaskStatus.running => 'running',
      AgentTaskStatus.backlog || AgentTaskStatus.ready => 'queued',
      AgentTaskStatus.waitingApproval || AgentTaskStatus.paused => 'blocked',
      AgentTaskStatus.failed || AgentTaskStatus.canceled => 'terminal',
    };
    buckets[bucket] = (buckets[bucket] ?? 0) + 1;
  }
  final total = tasks.length;
  return buckets.entries
      .where((entry) => entry.value > 0)
      .map(
        (entry) => _AgentAuditTaskStat(
          bucket: entry.key,
          count: entry.value,
          ratio: entry.value / total,
        ),
      )
      .toList(growable: false);
}

String _agentAuditTaskBucketLabel(BuildContext context, String bucket) {
  return switch (bucket) {
    'completed' => openHandLocalizedText(
      context,
      zh: '已完成',
      en: 'Completed',
      fr: 'Terminées',
      de: 'Abgeschlossen',
      ja: '完了',
    ),
    'running' => openHandLocalizedText(
      context,
      zh: '执行中',
      en: 'Running',
      fr: 'En cours',
      de: 'Läuft',
      ja: '実行中',
    ),
    'queued' => openHandLocalizedText(
      context,
      zh: '待执行',
      en: 'Queued',
      fr: 'En attente',
      de: 'In Warteschlange',
      ja: '待機中',
    ),
    'blocked' => openHandLocalizedText(
      context,
      zh: '待处理',
      en: 'Blocked',
      fr: 'Bloquées',
      de: 'Blockiert',
      ja: '保留中',
    ),
    'terminal' => openHandLocalizedText(
      context,
      zh: '异常终止',
      en: 'Terminal',
      fr: 'Terminales',
      de: 'Beendet',
      ja: '終了',
    ),
    _ => bucket,
  };
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

String _agentWorkerCurrentTaskLabel(
  AppLocalizations l10n,
  AgentProfile agent,
  AgentWorker worker,
) {
  final taskId = worker.currentTaskId.trim();
  if (taskId.isEmpty) return '';
  final task = _agentTaskById(agent, taskId);
  final title = task?.title.trim().isNotEmpty == true ? task!.title : taskId;
  return _agentInlineText(l10n, zh: '当前任务 $title', en: 'Current task $title');
}

int _agentWorkerStatusCount(AgentProfile agent, AgentWorkerStatus status) {
  return agent.workers.where((worker) => worker.status == status).length;
}

int _agentTasksByStatusCount(AgentProfile agent, AgentTaskStatus status) {
  return agent.tasks.where((task) => task.status == status).length;
}

List<_AgentAuditCapabilityStat> _agentAuditCapabilityStats(
  List<AgentAuditEvent> events,
) {
  final buckets =
      <
        String,
        ({String type, String name, int events, int requests, int tokens})
      >{};
  for (final event in events) {
    final type = _agentAuditCapabilityType(event);
    final name = _agentAuditCapabilityName(event);
    final key = '$type::$name';
    final current =
        buckets[key] ??
        (type: type, name: name, events: 0, requests: 0, tokens: 0);
    buckets[key] = (
      type: current.type,
      name: current.name,
      events: current.events + 1,
      requests: current.requests + event.requestCount,
      tokens: current.tokens + event.tokenUsage,
    );
  }
  final rows = buckets.values
      .map(
        (item) => _AgentAuditCapabilityStat(
          type: item.type,
          name: item.name,
          events: item.events,
          requests: item.requests,
          tokens: item.tokens,
        ),
      )
      .toList(growable: false);
  rows.sort((a, b) {
    final tokenCompare = b.tokens.compareTo(a.tokens);
    if (tokenCompare != 0) return tokenCompare;
    final requestCompare = b.requests.compareTo(a.requests);
    if (requestCompare != 0) return requestCompare;
    final eventCompare = b.events.compareTo(a.events);
    if (eventCompare != 0) return eventCompare;
    return a.name.compareTo(b.name);
  });
  return rows;
}

List<_AgentAuditWorkerStat> _agentAuditWorkerStats(AgentProfile agent) {
  final workerIds = <String>{};
  for (final worker in agent.workers) {
    workerIds.add(worker.id);
  }
  for (final task in agent.tasks) {
    final workerId = '${task.extra['assigned_worker_id'] ?? ''}'.trim();
    if (workerId.isNotEmpty) workerIds.add(workerId);
  }
  for (final event in agent.auditEvents) {
    final workerId = '${event.metadata['worker_id'] ?? ''}'.trim();
    if (workerId.isNotEmpty) workerIds.add(workerId);
  }
  final rows = workerIds
      .map((workerId) {
        final worker = _agentWorkerById(agent, workerId);
        final assignedTasks = agent.tasks
            .where((task) => _agentTaskAssignedToWorker(task, workerId))
            .length;
        final workerEvents = agent.auditEvents.where(
          (event) => '${event.metadata['worker_id'] ?? ''}'.trim() == workerId,
        );
        final requests = workerEvents.fold<int>(
          0,
          (sum, event) => sum + event.requestCount,
        );
        final tokens = workerEvents.fold<int>(
          0,
          (sum, event) => sum + event.tokenUsage,
        );
        final name = worker?.name.trim().isNotEmpty == true
            ? worker!.name.trim()
            : workerId;
        return _AgentAuditWorkerStat(
          id: workerId,
          name: name,
          status: worker?.status ?? AgentWorkerStatus.offline,
          assignedTasks: assignedTasks,
          executedTasks: worker?.executedTaskCount ?? 0,
          requests: requests,
          tokens: tokens,
          busyScore: worker?.busyScore ?? 0,
        );
      })
      .toList(growable: false);
  rows.sort((a, b) {
    final tokenCompare = b.tokens.compareTo(a.tokens);
    if (tokenCompare != 0) return tokenCompare;
    final requestCompare = b.requests.compareTo(a.requests);
    if (requestCompare != 0) return requestCompare;
    final taskCompare = b.assignedTasks.compareTo(a.assignedTasks);
    if (taskCompare != 0) return taskCompare;
    return a.id.compareTo(b.id);
  });
  return rows;
}

String _agentAuditCapabilityType(AgentAuditEvent event) {
  final text = [
    event.kind,
    event.toolName,
    '${event.metadata['capability_type'] ?? ''}',
    '${event.metadata['type'] ?? ''}',
  ].join(' ').toLowerCase();
  if (text.contains('skill')) return 'skill';
  if (text.contains('mcp')) return 'mcp';
  if (text.contains('memory')) return 'memory';
  if (text.contains('knowledge')) return 'knowledge';
  if (text.contains('builtin')) return 'builtin_tool';
  if (text.contains('model')) return 'model_request';
  if (text.contains('resource')) return 'resource';
  if (text.contains('approval')) return 'approval';
  if (text.contains('kpi')) return 'kpi';
  if (text.contains('worker') || text.contains('task')) {
    return 'worker_execution';
  }
  return 'other';
}

String _agentAuditCapabilityName(AgentAuditEvent event) {
  for (final raw in <Object?>[
    event.toolName,
    event.metadata['tool_name'],
    event.metadata['tool'],
    event.metadata['capability_name'],
    event.kind,
  ]) {
    final text = '$raw'.trim();
    if (text.isNotEmpty) return text;
  }
  return 'unknown';
}

IconData _agentCapabilityLogIcon(String type) {
  return switch (type) {
    'skill' => Icons.school_rounded,
    'mcp' => Icons.hub_rounded,
    'memory' => Icons.psychology_rounded,
    'knowledge' => Icons.library_books_rounded,
    'builtin_tool' => Icons.extension_rounded,
    'model_request' => Icons.auto_awesome_rounded,
    'resource' => Icons.speed_rounded,
    'approval' => Icons.verified_user_outlined,
    'kpi' => Icons.flag_outlined,
    'worker_execution' => Icons.memory_rounded,
    _ => Icons.receipt_long_rounded,
  };
}

Color _agentCapabilityLogColor(ColorScheme cs, String type) {
  return switch (type) {
    'skill' => cs.primary,
    'mcp' => cs.secondary,
    'memory' => cs.tertiary,
    'knowledge' => cs.primary,
    'builtin_tool' => cs.secondary,
    'model_request' => cs.primary,
    'resource' => cs.tertiary,
    'approval' => cs.error,
    'kpi' => cs.primary,
    'worker_execution' => cs.secondary,
    _ => cs.onSurfaceVariant,
  };
}

String _agentCapabilityTypeLabel(BuildContext context, String type) {
  return switch (type) {
    'skill' => 'Skill',
    'mcp' => 'MCP',
    'memory' => openHandLocalizedText(context, zh: '记忆', en: 'Memory'),
    'knowledge' => openHandLocalizedText(context, zh: '知识库', en: 'Knowledge'),
    'builtin_tool' => openHandLocalizedText(
      context,
      zh: '内建工具',
      en: 'Built-in tool',
    ),
    'model_request' => openHandLocalizedText(
      context,
      zh: '模型请求',
      en: 'Model request',
    ),
    'resource' => openHandLocalizedText(context, zh: '资源', en: 'Resource'),
    'approval' => openHandLocalizedText(context, zh: '审批', en: 'Approval'),
    'kpi' => 'KPI',
    'worker_execution' => openHandLocalizedText(
      context,
      zh: 'Worker 执行',
      en: 'Worker execution',
    ),
    _ => openHandLocalizedText(context, zh: '其他', en: 'Other'),
  };
}

List<String> _agentAuditMetadataChips(AgentAuditEvent event) {
  const keys = <String>[
    'task_id',
    'worker_id',
    'tool_name',
    'mcp_server',
    'skill_name',
    'memory_id',
    'capability_type',
    'status',
  ];
  final chips = <String>[];
  for (final key in keys) {
    final value = event.metadata[key];
    final text = _agentMetadataChipText(key, value);
    if (text != null) chips.add(text);
    if (chips.length >= 4) break;
  }
  return chips;
}

AgentWorker? _agentWorkerById(AgentProfile agent, String workerId) {
  for (final worker in agent.workers) {
    if (worker.id == workerId) return worker;
  }
  return null;
}

bool _agentTaskAssignedToWorker(AgentTask task, String workerId) {
  return '${task.extra['assigned_worker_id'] ?? ''}'.trim() == workerId;
}

String _agentTaskAssignedWorkerLabel(AppLocalizations l10n, AgentTask task) {
  final workerName = '${task.extra['assigned_worker_name'] ?? ''}'.trim();
  final workerId = '${task.extra['assigned_worker_id'] ?? ''}'.trim();
  final label = workerName.isNotEmpty ? workerName : workerId;
  if (label.isEmpty) return '';
  return _agentInlineText(l10n, zh: 'Worker $label', en: 'Worker $label');
}

String _agentDateTimeLabel(DateTime? value) {
  if (value == null) return '';
  final local = value.toLocal();
  return '${formatMonthDayHm(local)} · ${local.toIso8601String()}';
}

Map<String, Object?> _agentTaskExtraDisplayJson(Map<String, Object?> extra) {
  if (extra.isEmpty) return const <String, Object?>{};
  final sanitized = Map<String, Object?>.from(extra);
  final prompt = sanitized.remove('agent_system_prompt');
  if (prompt is String && prompt.isNotEmpty) {
    sanitized['agent_system_prompt'] = <String, Object?>{
      'omitted': true,
      'chars': prompt.length,
    };
  }
  return sanitized;
}

AgentTask? _agentTaskById(AgentProfile agent, String taskId) {
  for (final task in agent.tasks) {
    if (task.id == taskId) return task;
  }
  return null;
}

String _agentInlineText(
  AppLocalizations l10n, {
  required String zh,
  required String en,
}) {
  return l10n.localeName.toLowerCase().startsWith('zh') ? zh : en;
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
    'task_completed' => _agentInlineText(
      l10n,
      zh: '任务已完成',
      en: 'Task completed',
    ),
    'approval_requested' => _agentInlineText(
      l10n,
      zh: '审批已发起',
      en: 'Approval requested',
    ),
    'approval_approved' => _agentInlineText(
      l10n,
      zh: '审批已批准',
      en: 'Approval approved',
    ),
    'approval_rejected' => _agentInlineText(
      l10n,
      zh: '审批已拒绝',
      en: 'Approval rejected',
    ),
    'approval_expired' => _agentInlineText(
      l10n,
      zh: '审批已过期',
      en: 'Approval expired',
    ),
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
    'task_resumed' ||
    'task_completed' ||
    'approval_requested' ||
    'approval_approved' ||
    'approval_rejected' ||
    'approval_expired' => '',
    _ => _agentActivityMetadataFallback(event),
  };
}

String _agentActivityMessageTypeLabel(
  AppLocalizations l10n,
  AgentActivityMessageType type,
) {
  return switch (type) {
    AgentActivityMessageType.thought => _agentInlineText(
      l10n,
      zh: '思考',
      en: 'Thought',
    ),
    AgentActivityMessageType.toolCall => _agentInlineText(
      l10n,
      zh: '工具',
      en: 'Tool',
    ),
    AgentActivityMessageType.response => _agentInlineText(
      l10n,
      zh: '响应',
      en: 'Response',
    ),
    AgentActivityMessageType.multimedia => _agentInlineText(
      l10n,
      zh: '多媒体',
      en: 'Media',
    ),
    AgentActivityMessageType.task => _agentInlineText(
      l10n,
      zh: '任务',
      en: 'Task',
    ),
    AgentActivityMessageType.approval => _agentInlineText(
      l10n,
      zh: '审批',
      en: 'Approval',
    ),
    AgentActivityMessageType.lifecycle => _agentInlineText(
      l10n,
      zh: '生命周期',
      en: 'Lifecycle',
    ),
    AgentActivityMessageType.system => _agentInlineText(
      l10n,
      zh: '系统',
      en: 'System',
    ),
    AgentActivityMessageType.event => _agentInlineText(
      l10n,
      zh: '事件',
      en: 'Event',
    ),
  };
}

IconData _agentActivityIcon(AgentActivityMessageType type) {
  return switch (type) {
    AgentActivityMessageType.thought => Icons.psychology_alt_outlined,
    AgentActivityMessageType.toolCall => Icons.construction_rounded,
    AgentActivityMessageType.response => Icons.chat_bubble_outline_rounded,
    AgentActivityMessageType.multimedia => Icons.perm_media_outlined,
    AgentActivityMessageType.task => Icons.task_alt_rounded,
    AgentActivityMessageType.approval => Icons.verified_user_outlined,
    AgentActivityMessageType.lifecycle => Icons.power_settings_new_rounded,
    AgentActivityMessageType.system => Icons.settings_suggest_outlined,
    AgentActivityMessageType.event => Icons.bolt_outlined,
  };
}

Color _agentActivityToneColor(ColorScheme cs, AgentActivityMessageType type) {
  return switch (type) {
    AgentActivityMessageType.thought => cs.tertiary,
    AgentActivityMessageType.toolCall => cs.secondary,
    AgentActivityMessageType.response => cs.primary,
    AgentActivityMessageType.multimedia => cs.secondary,
    AgentActivityMessageType.task => cs.primary,
    AgentActivityMessageType.approval => cs.error,
    AgentActivityMessageType.lifecycle => cs.outline,
    AgentActivityMessageType.system => cs.onSurfaceVariant,
    AgentActivityMessageType.event => cs.primary,
  };
}

List<String> _agentActivityMetadataChips(AgentActivityEvent event) {
  const keys = <String>[
    'task_id',
    'worker_id',
    'tool_name',
    'mcp_server',
    'skill_name',
    'memory_id',
    'status',
  ];
  final chips = <String>[];
  for (final key in keys) {
    final value = event.metadata[key];
    final text = _agentMetadataChipText(key, value);
    if (text != null) chips.add(text);
    if (chips.length >= 4) break;
  }
  return chips;
}

String? _agentMetadataChipText(String key, Object? value) {
  final raw = switch (value) {
    null => '',
    Iterable<Object?> values =>
      values
          .map((item) => '$item'.trim())
          .where((item) => item.isNotEmpty)
          .take(3)
          .join(', '),
    _ => '$value'.trim(),
  };
  if (raw.isEmpty) return null;
  final compact = raw.length > 64 ? '${raw.substring(0, 61)}...' : raw;
  return '$key: $compact';
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
