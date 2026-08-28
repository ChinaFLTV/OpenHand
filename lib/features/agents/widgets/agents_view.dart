import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../app/model/app_settings_snapshot.dart';
import '../../../app/model/dialog_animation_settings.dart';
import '../../../app/state/settings_controller.dart';
import '../../../app/support/openhand_paths.dart';
import '../../../app/support/silent_log.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/ui/animated_appearance.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/appear_once.dart';
import '../../../shared/ui/bounded_animation.dart';
import '../../../shared/ui/feature_page_shell.dart';
import '../../../shared/ui/feature_state_card.dart';
import '../../../shared/ui/image_editor_dialog.dart';
import '../../../shared/ui/list_removal_transition.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_form_fields.dart';
import '../../../shared/ui/openhand_model_selector_field.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_typography.dart';
import '../../../shared/util/bounded_json_conversion.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/localized_text.dart';
import '../../../shared/util/text_clip.dart';
import '../../../shared/util/text_normalization.dart';
import '../../../shared/util/timer_safety.dart';
import '../../../shared/util/user_failure_message.dart';
import '../../ai/index.dart'
    show
        AiAgentBuiltinToolGroup,
        AiBuiltinToolConfig,
        AiBuiltinToolKind,
        AiBuiltinToolKindAgentMetadata,
        AiResourceUsageKind,
        agentBuiltinToolCanonicalName,
        agentBuiltinToolGroupIcon,
        agentBuiltinToolGroupLabel,
        agentBuiltinToolLabel,
        agentBuiltinToolSummary,
        aiSessionMessageTruncatedPlaceholder,
        resourceUsageStatisticsButton,
        showResourceUsageStatisticsDialog;
import '../../crons/index.dart';
import '../../hooks/index.dart';
import '../../instructions/index.dart';
import '../../knowledge_base/index.dart';
import '../../mcp/index.dart';
import '../../memory/index.dart';
import '../../skills/index.dart';
import '../agents_controller.dart';
import '../model/agent_models.dart';
import '../service/agent_ordering.dart';
import '../service/agent_routing_metadata.dart';
import '../service/agent_runtime_availability.dart';
import '../service/agent_sensitive_metadata.dart';

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

const double _agentListCardSurfaceAlpha = 0.42;

/// 数字员工列表项 / 卡片的统一底色与描边；圆角由调用方按层级给定。
BoxDecoration _agentListCardDecoration(
  ColorScheme cs, {
  required BorderRadiusGeometry borderRadius,
}) {
  return BoxDecoration(
    color: cs.surfaceContainerHighest.withValues(
      alpha: _agentListCardSurfaceAlpha,
    ),
    borderRadius: borderRadius,
    border: Border.all(color: cs.outlineVariant),
  );
}

const EdgeInsets _agentDialogPadding = EdgeInsets.all(22);
const double _agentDialogTitleGap = 10;
const double _agentDialogSectionGap = 18;
const double _agentDialogScrollableFooterClearance = 28;
const EdgeInsets _agentDialogActionPadding = EdgeInsets.fromLTRB(16, 8, 16, 12);
const double _agentTaskDetailMaxWidthFraction = 0.96;
const double _agentTaskDetailMaxHeightFraction = 0.92;
const double _agentTaskDetailHorizontalMargin = 32;
const double _agentTaskDetailVerticalMargin = 72;
const double _agentTaskDetailMinAvailableWidth = 320;
const double _agentTaskDetailSectionGap = 14;
const double _agentTaskDetailGridGap = 12;
const double _agentTaskDetailGridBreakpoint = 640;
const double _agentTaskDetailHeroBreakpoint = 620;
const double _agentTaskDetailHeroRailWidth = 4;
const double _agentTaskDetailHeroIconExtent = 46;
const double _agentTaskDetailHeroIconSize = 25;
const double _agentTaskDetailHeroProgressWidth = 184;
const double _agentTaskDetailIconExtent = 30;
const double _agentTaskDetailFactMinHeight = 56;
const double _agentTaskDetailCardRadius = 8;
const double _agentTaskDetailCompactMinHeight = 74;
const EdgeInsets _agentTaskDetailHeroPadding = EdgeInsets.all(14);
const EdgeInsets _agentTaskDetailFactPanelPadding = EdgeInsets.all(12);
const EdgeInsets _agentTaskDetailCardPadding = EdgeInsets.fromLTRB(
  14,
  12,
  14,
  12,
);
const double _agentAuditSectionGridGap = 12;
const double _agentAuditSectionGridBreakpoint = 760;
const double _agentAuditEventIconExtent = 38;
const int _agentLogDetailMaxJsonDepth = 8;
const int _agentLogDetailMaxStringChars = 6000;
const int _agentLogDetailMaxJsonChars = 60000;
const int _agentLogDetailMaxCollectionItems = 500;
const Duration _agentResourceSampleInterval = Duration(milliseconds: 1400);
const Duration _agentResourceSampleTimeout = Duration(seconds: 8);
const String _agentResourceTelemetryExtraKey = '_openhand_resource_telemetry';
const String _agentResourceTelemetryHistoryKey = 'history';
const double _agentResourceOverviewBreakpoint = 720;
const double _agentResourceChartHeight = 152;
const double _agentResourceDonutSize = 148;
const double _agentResourcePanelRadius = 18;
const double _agentResourcePressureCardCompactBreakpoint = 560;
const double _agentResourcePressureBarHeight = 10;
const double _agentResourcePressureValueMinWidth = 72;
const double _agentResourcePressureValueMaxWidth = 240;
const double _agentResourcePressureValueCharWidth = 9.5;
const double _agentResourcePressureValuePadding = 24;
const double _agentDialogMetricGap = 12;
const double _agentDialogMetricWideBreakpoint = 760;
const double _agentDialogMetricMediumBreakpoint = 520;
const double _agentDialogMetricRadius = 14;
const double _agentActivityItemGap = 12;
const double _agentActivityIconExtent = 36;
const double _agentActivityIconRadius = 12;
const double _agentActivityCardRadius = 18;
const double _agentActivityListCacheExtent = 560;
const EdgeInsets _agentActivityListPadding = EdgeInsets.only(right: 4);
const EdgeInsets _agentActivityCardPadding = EdgeInsets.fromLTRB(
  14,
  12,
  14,
  12,
);
const int _agentRoutePreviewKeywordLimit = 10;
const int _agentStructuredFieldMaxItems = 256;
const int _agentStructuredFieldKeyMaxChars = 256;
const int _agentStructuredFieldValueMaxChars = 32768;
const int _agentStructuredFieldMaxDepth = 16;
const int _agentStructuredFieldMaxNodes = 4096;
const int _agentMetricInputMaxChars = 20;
const Set<String> _agentRouteReservedKeys = <String>{
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
const BoundedJsonConversionConfig _agentStructuredValueConversionConfig =
    BoundedJsonConversionConfig(
      maxDepth: _agentStructuredFieldMaxDepth,
      maxContainerItems: _agentStructuredFieldMaxItems,
      maxTotalNodes: _agentStructuredFieldMaxNodes,
      maxStringCodeUnits: _agentStructuredFieldValueMaxChars,
      maxDepthPlaceholder: '<层级过深>',
      cyclicMapPlaceholder: '<循环映射>',
      cyclicIterablePlaceholder: '<循环集合>',
      truncatedPlaceholder: aiSessionMessageTruncatedPlaceholder,
    );
const List<String> _agentImageExtensions = <String>[
  'jpg',
  'jpeg',
  'png',
  'webp',
  'gif',
  'bmp',
];
const double _agentChipSpacing = 8;
const double _agentChipDropSlotExtent = 28;
const double _agentCapabilityChipSpacing = 8;
const double _agentCapabilityChipMinHeight = 38;
const double _agentCapabilityChipMaxWidth = 320;
const double _agentCapabilityChipIconSlotWidth = 22;
const int _agentCapabilityChipStateDurationMs = 150;
const EdgeInsetsDirectional _agentCapabilityChipPadding =
    EdgeInsetsDirectional.fromSTEB(12, 7, 14, 7);
const double _agentNumberStepperFieldExtent = 64;
const double _agentNumberStepperControlTopInset = 8;
const double _agentNumberStepperControlRadius = 24;
const double _agentNumberStepperButtonExtent = 36;
const double _agentNumberStepperEditableHeight = 34;
const double _agentNumberStepperEditableMinWidth = 52;
const double _agentNumberStepperEditableDigitWidth = 15;
const double _agentNumberStepperTextFallbackSize = 22;
const double _agentNumberStepperTextLineHeight = 1.1;
const double _agentNumberStepperCursorHeightFactor = 0.92;
const double _agentNumberStepperIconSize = 20;
const int _agentNumberStepperStateDurationMs = 150;
const EdgeInsetsDirectional _agentNumberStepperContentPadding =
    EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10);
const EdgeInsetsDirectional _agentNumberStepperLabelPadding =
    EdgeInsetsDirectional.fromSTEB(8, 0, 8, 0);

void _showAgentInfoSnack(
  BuildContext context,
  String message, {
  Duration duration = kOpenHandSnackBarNormalDuration,
  SnackBarAction? action,
  int? maxLines,
}) {
  showOpenHandInfoSnack(
    context,
    message,
    duration: duration,
    action: action,
    maxLines: maxLines,
  );
}

void _showAgentErrorSnack(
  BuildContext context,
  String message, {
  Duration duration = kOpenHandSnackBarDetailedDuration,
  SnackBarAction? action,
  int? maxLines,
}) {
  showOpenHandErrorSnack(
    context,
    message,
    duration: duration,
    action: action,
    maxLines: maxLines,
  );
}

void _showAgentMutationError(
  BuildContext context,
  AgentsController controller, {
  required String zh,
  required String en,
}) {
  final summary = openHandLocalizedText(context, zh: zh, en: en);
  final detail = controller.errorMessage?.trim();
  _showAgentErrorSnack(
    context,
    detail == null || detail.isEmpty ? summary : '$summary\n$detail',
    maxLines: 4,
  );
}

int _normalizeAgentMaxWorkers(int value) {
  return value
      .clamp(agentScaleMaxWorkersMinimum, agentScaleWorkersMaximum)
      .toInt();
}

int _normalizeAgentMinWorkers(int value, int maxWorkers) {
  final normalizedMaxWorkers = _normalizeAgentMaxWorkers(maxWorkers);
  return value.clamp(agentScaleMinWorkersMinimum, normalizedMaxWorkers).toInt();
}

int _normalizeAgentMaxRetries(int value) {
  return value
      .clamp(agentScaleMaxRetriesMinimum, agentScaleMaxRetriesMaximum)
      .toInt();
}

double _normalizeAgentScaleRatio(double value) {
  return value.clamp(agentScaleRatioMinimum, agentScaleRatioMaximum).toDouble();
}

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
      actions: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          resourceUsageStatisticsButton(
            context,
            onPressed: () => showResourceUsageStatisticsDialog(
              context,
              kind: AiResourceUsageKind.agent,
              resourceLabels: <String, String>{
                for (final agent in snapshot.agents) agent.id: agent.name,
              },
            ),
          ),
          FilledButton.icon(
            onPressed: () => _handleCreateAgent(context, snapshot.runtime),
            icon: const Icon(Icons.add_rounded),
            label: Text(l10n.agentsCreateAgent),
          ),
        ],
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
    return OpenHandRemovableListScope(
      builder: (context, removal) => ListView.separated(
        key: const ValueKey<String>('agents-list'),
        padding: const EdgeInsets.fromLTRB(0, 2, 0, 12),
        cacheExtent: 700,
        itemCount: snapshot.agents.length,
        separatorBuilder: (_, _) => kOpenHandGap14,
        itemBuilder: (context, index) {
          final agent = snapshot.agents[index];
          return SettingsAwareAppearOnce(
            key: ValueKey<String>('agent-card-${agent.id}'),
            child: RepaintBoundary(
              child: OpenHandListRemovalTransition(
                collapsed: removal.isRemoving(agent.id),
                child: _AgentCard(
                  agent: agent,
                  onToggleEnabled: (enabled) =>
                      _handleToggleAgentEnabled(context, agent, enabled),
                  onAction: (action) =>
                      _handleAgentAction(context, agent, action, removal),
                ),
              ),
            ),
          );
        },
      ),
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
                kOpenHandHGap16,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(agent.name, style: theme.textTheme.headlineSmall),
                      kOpenHandGap6,
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
                        kOpenHandGap8,
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
                kOpenHandHGap12,
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
                        style: agent.enabled
                            ? OpenHandStatusColors.runningStopButtonStyle()
                                  .copyWith(
                                    shape: const WidgetStatePropertyAll(
                                      CircleBorder(),
                                    ),
                                  )
                            : null,
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
                    _AgentCardMoreMenu(agentId: agent.id, onAction: onAction),
                  ],
                ),
              ],
            ),
            kOpenHandGap16,
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OpenHandStatusPill(
                  icon: agent.isRunning
                      ? Icons.check_circle_outline_rounded
                      : Icons.pause_circle_outline_rounded,
                  label: _agentLifecycleStateLabel(l10n, agent.lifecycleState),
                  color: toneColor,
                ),
                OpenHandStatusPill(
                  icon: Icons.workspace_premium_outlined,
                  label: agent.level.trim().isEmpty ? 'L1' : agent.level,
                  color: cs.secondary,
                ),
                OpenHandStatusPill(
                  icon: Icons.security_rounded,
                  label: _agentExecutionModeLabel(l10n, agent.executionMode),
                  color: agent.executionMode == AgentExecutionMode.fullAccess
                      ? cs.tertiary
                      : cs.primary,
                ),
                OpenHandStatusPill(
                  icon: Icons.task_alt_rounded,
                  label: l10n.agentsTasksCount(
                    agent.runningTaskCount,
                    agent.tasks.length,
                  ),
                  color: cs.primary,
                ),
                OpenHandStatusPill(
                  icon: Icons.fact_check_rounded,
                  label: l10n.agentsApprovalsCount(agent.pendingApprovalCount),
                  color: cs.error,
                ),
                OpenHandStatusPill(
                  icon: Icons.memory_rounded,
                  label: l10n.agentsWorkersCount(
                    agent.workers.length,
                    agent.scaleSettings.maxWorkers,
                  ),
                  color: cs.secondary,
                ),
                if (modelLabel.isNotEmpty)
                  OpenHandStatusPill(
                    icon: Icons.auto_awesome_rounded,
                    label: modelLabel,
                    color: cs.primary,
                  ),
              ],
            ),
            kOpenHandGap14,
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
            borderRadius: kOpenHandBorderRadius18,
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

class _AgentCardMoreMenu extends StatelessWidget {
  const _AgentCardMoreMenu({required this.agentId, required this.onAction});

  final String agentId;
  final ValueChanged<_AgentCardAction> onAction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AnimatedPopupMenuButton<_AgentCardAction>(
      key: ValueKey<String>('agent-card-more-$agentId'),
      tooltip: l10n.agentsMore,
      onSelected: onAction,
      itemBuilder: (context) => [
        PopupMenuItem(
          key: ValueKey<String>('agent-card-edit-$agentId'),
          value: _AgentCardAction.edit,
          child: _AgentCardMenuItem(
            icon: Icons.edit_rounded,
            label: l10n.agentsEditAgent,
          ),
        ),
        PopupMenuItem(
          key: ValueKey<String>('agent-card-delete-$agentId'),
          value: _AgentCardAction.delete,
          child: _AgentCardMenuItem(
            icon: Icons.delete_outline_rounded,
            label: l10n.agentsDeleteAgent,
          ),
        ),
      ],
    );
  }
}

class _AgentCardMenuItem extends StatelessWidget {
  const _AgentCardMenuItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 19, color: theme.colorScheme.onSurfaceVariant),
        kOpenHandHGap10,
        Flexible(child: Text(label)),
      ],
    );
  }
}

class _AgentCapabilitySummary extends StatelessWidget {
  const _AgentCapabilitySummary({required this.agent});

  final AgentProfile agent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final visibleBuiltinTools = agentVisibleBuiltinToolNames(
      agent.builtinToolNames,
    );
    final rows = <String>[
      if (agent.skillNames.isNotEmpty)
        l10n.agentsCapabilitySkillsCount(agent.skillNames.length),
      if (agent.knowledgeSourceIds.isNotEmpty)
        l10n.agentsCapabilityKnowledgeCount(agent.knowledgeSourceIds.length),
      if (agent.memoryIds.isNotEmpty)
        l10n.agentsCapabilityMemoryCount(agent.memoryIds.length),
      if (agent.mcpServerNames.isNotEmpty) 'MCP ${agent.mcpServerNames.length}',
      if (visibleBuiltinTools.isNotEmpty)
        l10n.agentsCapabilityToolsCount(visibleBuiltinTools.length),
      if (agent.cronIds.isNotEmpty)
        l10n.agentsCapabilityCronsCount(agent.cronIds.length),
      if (agent.hookIds.isNotEmpty)
        l10n.agentsCapabilityHooksCount(agent.hookIds.length),
      if (agent.instructionIds.isNotEmpty)
        openHandLocalizedText(
          context,
          zh: '指令 ${agent.instructionIds.length}',
          en: 'Instructions ${agent.instructionIds.length}',
        ),
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
                if (index > 0) kOpenHandGap8,
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
      duration: settings.entranceDuration,
      reverseDuration: settings.exitDuration,
      transitionBuilder: (child, animation) => _agentDialogSwitchTransition(
        settings: settings,
        animation: animation,
        child: child,
      ),
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
    final progress = clampUnitInterval(item.progress);
    return DecoratedBox(
      decoration: _agentListCardDecoration(
        cs,
        borderRadius: kOpenHandBorderRadius8,
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
                borderRadius: kOpenHandBorderRadius8,
              ),
              alignment: Alignment.center,
              child: Icon(
                _agentKpiStatusIcon(item.status),
                size: 18,
                color: statusColor,
              ),
            ),
            kOpenHandHGap10,
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
                  kOpenHandGap6,
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (item.target.trim().isNotEmpty) ...[
                    kOpenHandGap3,
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
                  kOpenHandGap8,
                  ClipRRect(
                    borderRadius: kOpenHandPillBorderRadius,
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
            kOpenHandHGap8,
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
  _AgentCardAction action, [
  OpenHandListRemoval? removal,
]) async {
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
      await _confirmDeleteAgent(context, agent, removal);
  }
}

/// 打开跟随控制器实时刷新的数字员工弹窗。
///
/// 统一订阅 [AgentsController] 并解析最新快照——员工在弹窗打开期间被删除时
/// 回落到入参快照，避免弹窗内容突然清空。
Future<void> _showLiveAgentDialog(
  BuildContext context,
  AgentProfile agent, {
  required double maxWidth,
  required double maxHeight,
  required Widget Function(BuildContext context, AgentProfile currentAgent)
  builder,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => Consumer<AgentsController>(
      builder: (context, controller, _) => buildOpenHandDialog(
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        child: builder(context, controller.agentById(agent.id) ?? agent),
      ),
    ),
  );
}

Future<void> _showAgentActivitiesDialog(
  BuildContext context,
  AgentProfile agent,
) {
  final l10n = AppLocalizations.of(context)!;
  return _showLiveAgentDialog(
    context,
    agent,
    maxWidth: 820,
    maxHeight: 680,
    builder: (context, currentAgent) {
      final activities = currentAgent.activities;
      return _AgentDialogScaffold(
        icon: Icons.history_rounded,
        title: l10n.agentsDialogTitleWithName(
          l10n.agentsActivities,
          currentAgent.name,
        ),
        scrollable: activities.isEmpty,
        child: activities.isEmpty
            ? FeatureStateCard.inline(
                icon: Icons.history_rounded,
                title: l10n.agentsActivitiesEmptyTitle,
                body: l10n.agentsListEmptyBody,
              )
            : _AgentActivityStream(activities: activities),
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
      padding: _agentActivityListPadding,
      physics: openHandDialogAwareScrollPhysics(context),
      cacheExtent: _agentActivityListCacheExtent,
      itemCount: activities.length,
      separatorBuilder: (_, _) => const SizedBox(height: _agentActivityItemGap),
      itemBuilder: (context, index) {
        final event = activities[index];
        return SettingsAwareAppearOnce(
          key: ValueKey<String>('agent-activity-${event.id}'),
          child: RepaintBoundary(child: _AgentActivityBubble(event: event)),
        );
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
    final metadata = _agentActivityMetadataChips(context, event);
    final timeText = event.createdAt == null
        ? ''
        : formatMonthDayHmLocal(event.createdAt!);
    final cardRadius = BorderRadius.circular(_agentActivityCardRadius);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: _agentActivityIconExtent,
          height: _agentActivityIconExtent,
          decoration: BoxDecoration(
            color: tone.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(_agentActivityIconRadius),
            border: Border.all(color: tone.withValues(alpha: 0.34)),
          ),
          alignment: Alignment.center,
          child: Icon(_agentActivityIcon(type), color: tone, size: 19),
        ),
        const SizedBox(width: _agentActivityItemGap),
        Expanded(
          child: ClipRRect(
            borderRadius: cardRadius,
            child: DecoratedBox(
              decoration: _agentListCardDecoration(
                cs,
                borderRadius: cardRadius,
              ),
              child: Padding(
                padding: _agentActivityCardPadding,
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
                    kOpenHandGap8,
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (body.trim().isNotEmpty) ...[
                      kOpenHandGap7,
                      SelectableText(
                        body,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.42,
                        ),
                      ),
                    ],
                    if (metadata.isNotEmpty) ...[
                      kOpenHandGap10,
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: metadata
                            .map(
                              (item) => _AgentActivityMetadataChip(text: item),
                            )
                            .toList(growable: false),
                      ),
                    ],
                  ],
                ),
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
        borderRadius: kOpenHandPillBorderRadius,
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
        borderRadius: kOpenHandBorderRadius8,
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
  return _showLiveAgentDialog(
    context,
    agent,
    maxWidth: 860,
    maxHeight: 700,
    builder: (context, currentAgent) {
      final events = currentAgent.auditEvents;
      return _AgentDialogScaffold(
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
            : _AgentCapabilityLogBody(agent: currentAgent, events: events),
      );
    },
  );
}

class _AgentCapabilityLogBody extends StatelessWidget {
  const _AgentCapabilityLogBody({required this.agent, required this.events});

  final AgentProfile agent;
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
              label: _agentsViewRequestsLabel(context),
              value: '$requests',
            ),
            _MetricTile(label: 'Token', value: '$tokens'),
          ],
        ),
        kOpenHandGap14,
        ListView.separated(
          shrinkWrap: true,
          primary: false,
          itemCount: events.length,
          separatorBuilder: (_, _) => kOpenHandGap10,
          itemBuilder: (context, index) {
            return _AgentCapabilityLogTile(agent: agent, event: events[index]);
          },
        ),
      ],
    );
  }
}

class _AgentCapabilityLogTile extends StatelessWidget {
  const _AgentCapabilityLogTile({required this.agent, required this.event});

  final AgentProfile agent;
  final AgentAuditEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final type = _agentAuditCapabilityType(event);
    final color = _agentCapabilityLogColor(cs, type);
    final name = _agentAuditCapabilityName(context, event);
    final timeText = event.createdAt == null
        ? ''
        : formatMonthDayHmLocal(event.createdAt!);
    final metadata = _agentAuditMetadataChips(context, event);
    const radius = kOpenHandBorderRadius12;

    return Semantics(
      button: true,
      label: openHandLocalizedText(
        context,
        zh: '查看日志详情',
        en: 'View log details',
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          onTap: () =>
              _showAgentCapabilityLogDetailDialog(context, agent, event),
          child: Ink(
            decoration: _agentListCardDecoration(cs, borderRadius: radius),
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
                      borderRadius: kOpenHandBorderRadius10,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      _agentCapabilityLogIcon(type),
                      color: color,
                      size: 19,
                    ),
                  ),
                  kOpenHandHGap12,
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
                        kOpenHandGap8,
                        Text(
                          name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (event.summary.trim().isNotEmpty) ...[
                          kOpenHandGap5,
                          SelectableText(
                            _agentAuditSummaryText(context, event),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.35,
                            ),
                          ),
                        ],
                        kOpenHandGap8,
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
                  kOpenHandHGap10,
                  Icon(
                    Icons.chevron_right_rounded,
                    color: cs.onSurfaceVariant,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _showAgentCapabilityLogDetailDialog(
  BuildContext context,
  AgentProfile agent,
  AgentAuditEvent event,
) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) => Consumer<AgentsController>(
      builder: (context, controller, _) {
        final currentAgent = controller.agentById(agent.id) ?? agent;
        final currentEvent =
            _agentAuditEventById(currentAgent, event.id) ?? event;
        return buildOpenHandResponsiveDialogShell(
          context: context,
          maxWidth: kOpenHandDialogWidthPanel,
          maxHeight: kOpenHandDialogHeightTall,
          maxWidthFraction: _agentTaskDetailMaxWidthFraction,
          maxHeightFraction: _agentTaskDetailMaxHeightFraction,
          horizontalMargin: _agentTaskDetailHorizontalMargin,
          verticalMargin: _agentTaskDetailVerticalMargin,
          minAvailableWidth: _agentTaskDetailMinAvailableWidth,
          child: _AgentDialogScaffold(
            icon: Icons.receipt_long_rounded,
            title: openHandLocalizedText(
              context,
              zh: '日志详情',
              en: 'Log details',
            ),
            child: _AgentCapabilityLogDetailBody(
              agent: currentAgent,
              event: currentEvent,
            ),
          ),
        );
      },
    ),
  );
}

class _AgentCapabilityLogDetailBody extends StatelessWidget {
  const _AgentCapabilityLogDetailBody({
    required this.agent,
    required this.event,
  });

  final AgentProfile agent;
  final AgentAuditEvent event;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final type = _agentAuditCapabilityType(event);
    final color = _agentCapabilityLogColor(cs, type);
    final capabilityName = _agentAuditCapabilityName(context, event);
    final taskId = _agentLogMetadataText(event.metadata, 'task_id');
    final workerId = _agentLogMetadataText(event.metadata, 'worker_id');
    final task = _agentTaskById(agent, taskId);
    final worker = agent.workerById(workerId);

    return _AgentTaskDetailSectionList(
      children: [
        _AgentCapabilityLogDetailHero(
          event: event,
          capabilityName: capabilityName,
          typeLabel: _agentCapabilityTypeLabel(context, type),
          color: color,
        ),
        _AgentDialogMetricGrid(
          children: [
            _AgentDialogMetricTile(
              icon: _agentCapabilityLogIcon(type),
              color: color,
              label: _agentsViewCapabilityLabel(context),
              value: _agentCapabilityTypeLabel(context, type),
            ),
            _AgentDialogMetricTile(
              icon: Icons.source_rounded,
              label: openHandSourceLabel(context),
              value: capabilityName,
            ),
            _AgentDialogMetricTile(
              icon: Icons.cloud_sync_rounded,
              label: _agentsViewRequestsLabel(context),
              value: '${event.requestCount}',
            ),
            _AgentDialogMetricTile(
              icon: Icons.generating_tokens_rounded,
              label: 'Token',
              value: '${event.tokenUsage}',
            ),
          ],
        ),
        _AgentLogDetailSection(
          icon: Icons.fact_check_outlined,
          title: openHandLocalizedText(context, zh: '日志概览', en: 'Log overview'),
          child: _AgentTaskDetailGrid(
            children: [
              _AgentTaskDetailBlock(
                icon: Icons.tag_rounded,
                title: openHandLocalizedText(
                  context,
                  zh: '日志 ID',
                  en: 'Log ID',
                ),
                body: event.id,
                compact: true,
              ),
              _AgentTaskDetailBlock(
                icon: Icons.schedule_rounded,
                title: openHandLocalizedText(
                  context,
                  zh: '发生时间',
                  en: 'Created',
                ),
                body: _agentDateTimeLabel(event.createdAt),
                compact: true,
              ),
              _AgentTaskDetailBlock(
                icon: Icons.category_outlined,
                title: openHandLocalizedText(
                  context,
                  zh: '事件类型',
                  en: 'Event type',
                ),
                body: _agentActivityKindLabel(l10n, event.kind),
                compact: true,
              ),
              _AgentTaskDetailBlock(
                icon: Icons.build_circle_outlined,
                title: openHandToolLabel(context),
                body: event.toolName.trim().isEmpty
                    ? capabilityName
                    : _agentAuditSourceLabel(context, event.toolName),
                compact: true,
              ),
              _AgentTaskDetailBlock(
                icon: Icons.short_text_rounded,
                title: openHandLocalizedText(context, zh: '摘要', en: 'Summary'),
                body: _agentAuditSummaryText(context, event),
              ),
            ],
          ),
        ),
        _AgentLogDetailSection(
          icon: Icons.task_alt_rounded,
          title: openHandLocalizedText(context, zh: '关联任务', en: 'Related task'),
          child: _buildTaskSection(context, l10n, taskId, task),
        ),
        _AgentLogDetailSection(
          icon: Icons.memory_rounded,
          title: openHandLocalizedText(
            context,
            zh: 'Worker 与执行上下文',
            en: 'Worker and execution context',
          ),
          child: _buildWorkerSection(context, l10n, workerId, worker),
        ),
        _AgentLogDetailSection(
          icon: Icons.developer_board_rounded,
          title: openHandEnvironmentLabel(context),
          child: _buildEnvironmentSection(context, l10n),
        ),
        _AgentLogDetailSection(
          icon: Icons.tune_rounded,
          title: openHandLocalizedText(context, zh: '参数信息', en: 'Parameters'),
          child: _AgentTaskDetailBlock(
            icon: Icons.data_object_rounded,
            title: 'metadata',
            body: _agentPrettyJsonForDisplay(event.metadata),
            monospace: true,
          ),
        ),
        _AgentLogDetailSection(
          icon: Icons.dataset_outlined,
          title: openHandLocalizedText(context, zh: '原始数据', en: 'Raw data'),
          child: _AgentTaskDetailGrid(
            children: [
              _AgentTaskDetailBlock(
                icon: Icons.receipt_long_rounded,
                title: openHandLocalizedText(
                  context,
                  zh: '审计事件快照',
                  en: 'Audit event snapshot',
                ),
                body: _agentPrettyJsonForDisplay(event.toJson()),
                monospace: true,
              ),
              if (task != null)
                _AgentTaskDetailBlock(
                  icon: Icons.task_alt_rounded,
                  title: openHandLocalizedText(
                    context,
                    zh: '任务快照',
                    en: 'Task snapshot',
                  ),
                  body: _agentPrettyJsonForDisplay(_agentLogTaskSnapshot(task)),
                  monospace: true,
                ),
              if (worker != null)
                _AgentTaskDetailBlock(
                  icon: Icons.memory_rounded,
                  title: openHandLocalizedText(
                    context,
                    zh: 'Worker 快照',
                    en: 'Worker snapshot',
                  ),
                  body: _agentPrettyJsonForDisplay(worker.toJson()),
                  monospace: true,
                ),
              _AgentTaskDetailBlock(
                icon: Icons.developer_board_rounded,
                title: openHandLocalizedText(
                  context,
                  zh: '环境快照',
                  en: 'Environment snapshot',
                ),
                body: _agentPrettyJsonForDisplay(
                  _agentLogEnvironmentSnapshot(agent),
                ),
                monospace: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTaskSection(
    BuildContext context,
    AppLocalizations l10n,
    String taskId,
    AgentTask? task,
  ) {
    if (task == null) {
      return _AgentTaskDetailBlock(
        icon: Icons.link_off_rounded,
        title: openHandLocalizedText(context, zh: '任务关联', en: 'Task reference'),
        body: taskId.isEmpty
            ? openHandLocalizedText(context, zh: '未记录任务 ID', en: 'No task ID')
            : openHandLocalizedText(
                context,
                zh: '当前智能体任务列表中未找到 $taskId',
                en: 'Task $taskId is not in the current agent task list',
              ),
      );
    }

    final workerLabel = _agentTaskAssignedWorkerLabel(l10n, task);
    return _AgentTaskDetailSectionList(
      children: [
        _AgentTaskDetailGrid(
          children: [
            _AgentTaskDetailBlock(
              icon: Icons.tag_rounded,
              title: 'ID',
              body: task.id,
              compact: true,
            ),
            _AgentTaskDetailBlock(
              icon: _agentTaskStatusIcon(task.status),
              title: openHandStatusLabel(context),
              body: _agentTaskStatusLabel(l10n, task.status),
              compact: true,
            ),
            _AgentTaskDetailBlock(
              icon: Icons.trending_up_rounded,
              title: _agentsViewProgressLabel(context),
              body: '${(clampUnitInterval(task.progress) * 100).round()}%',
              compact: true,
            ),
            _AgentTaskDetailBlock(
              icon: Icons.engineering_outlined,
              title: _agentsViewAssignedWorkerLabel(context),
              body: workerLabel,
              compact: true,
            ),
            _AgentTaskDetailBlock(
              icon: Icons.schedule_rounded,
              title: openHandCreatedLabel(context),
              body: _agentDateTimeLabel(task.createdAt),
              compact: true,
            ),
            _AgentTaskDetailBlock(
              icon: Icons.update_rounded,
              title: openHandUpdatedLabel(context),
              body: _agentDateTimeLabel(task.updatedAt),
              compact: true,
            ),
          ],
        ),
        _AgentTaskDetailBlock(
          icon: Icons.title_rounded,
          title: openHandTitleLabel(context),
          body: task.title,
        ),
        _AgentTaskDetailBlock(
          icon: Icons.short_text_rounded,
          title: l10n.agentsDescriptionLabel,
          body: task.description,
        ),
        _AgentTaskDetailBlock(
          icon: Icons.article_outlined,
          title: l10n.agentsContentLabel,
          body: task.content,
        ),
        _AgentTaskDetailBlock(
          icon: Icons.fact_check_outlined,
          title: _agentsViewTaskResultLabel(context),
          body: task.result,
        ),
        _AgentTaskDetailBlock(
          icon: Icons.sticky_note_2_outlined,
          title: l10n.agentsNoteLabel,
          body: task.note,
        ),
        _AgentTaskDetailBlock(
          icon: Icons.code_rounded,
          title: 'extra',
          body: _agentPrettyJsonForDisplay(
            _agentTaskExtraDisplayJson(task.extra),
          ),
          monospace: true,
        ),
      ],
    );
  }

  Widget _buildWorkerSection(
    BuildContext context,
    AppLocalizations l10n,
    String workerId,
    AgentWorker? worker,
  ) {
    if (worker == null) {
      return _AgentTaskDetailBlock(
        icon: Icons.person_off_outlined,
        title: openHandLocalizedText(
          context,
          zh: 'Worker 关联',
          en: 'Worker reference',
        ),
        body: workerId.isEmpty
            ? openHandLocalizedText(
                context,
                zh: '未记录 Worker ID',
                en: 'No worker ID',
              )
            : openHandLocalizedText(
                context,
                zh: '当前智能体 Worker 列表中未找到 $workerId',
                en: 'Worker $workerId is not in the current agent worker list',
              ),
      );
    }

    return _AgentTaskDetailSectionList(
      children: [
        _AgentTaskDetailGrid(
          children: [
            _AgentTaskDetailBlock(
              icon: Icons.tag_rounded,
              title: 'ID',
              body: worker.id,
              compact: true,
            ),
            _AgentTaskDetailBlock(
              icon: Icons.badge_outlined,
              title: openHandNameLabel(context),
              body: worker.name,
              compact: true,
            ),
            _AgentTaskDetailBlock(
              icon: Icons.monitor_heart_outlined,
              title: openHandStatusLabel(context),
              body: _agentWorkerStatusLabel(l10n, worker.status),
              compact: true,
            ),
            _AgentTaskDetailBlock(
              icon: Icons.speed_rounded,
              title: openHandLocalizedText(context, zh: '忙碌度', en: 'Busy'),
              body: '${(clampUnitInterval(worker.busyScore) * 100).round()}%',
              compact: true,
            ),
            _AgentTaskDetailBlock(
              icon: Icons.task_alt_rounded,
              title: openHandLocalizedText(
                context,
                zh: '当前任务',
                en: 'Current task',
              ),
              body: worker.currentTaskId,
              compact: true,
            ),
            _AgentTaskDetailBlock(
              icon: Icons.update_rounded,
              title: openHandUpdatedLabel(context),
              body: _agentDateTimeLabel(worker.updatedAt),
              compact: true,
            ),
            _AgentTaskDetailBlock(
              icon: Icons.format_list_numbered_rounded,
              title: openHandLocalizedText(
                context,
                zh: '已执行任务',
                en: 'Executed tasks',
              ),
              body: '${worker.executedTaskCount}',
              compact: true,
            ),
            _AgentTaskDetailBlock(
              icon: Icons.low_priority_rounded,
              title: _agentsViewPriorityLabel(context),
              body: '${worker.priority}',
              compact: true,
            ),
            _AgentTaskDetailBlock(
              icon: Icons.label_outline_rounded,
              title: openHandLocalizedText(context, zh: '标签', en: 'Labels'),
              body: _agentJoinedText(worker.labels),
              compact: true,
            ),
          ],
        ),
        _AgentTaskDetailBlock(
          icon: Icons.code_rounded,
          title: 'extra',
          body: _agentPrettyJsonForDisplay(worker.extra),
          monospace: true,
        ),
      ],
    );
  }

  Widget _buildEnvironmentSection(BuildContext context, AppLocalizations l10n) {
    return _AgentTaskDetailSectionList(
      children: [
        _AgentTaskDetailGrid(
          children: [
            _AgentTaskDetailBlock(
              icon: Icons.smart_toy_outlined,
              title: openHandAgentLabel(context),
              body: agent.name,
              compact: true,
            ),
            _AgentTaskDetailBlock(
              icon: Icons.tag_rounded,
              title: openHandLocalizedText(
                context,
                zh: '智能体 ID',
                en: 'Agent ID',
              ),
              body: agent.id,
              compact: true,
            ),
            _AgentTaskDetailBlock(
              icon: Icons.power_settings_new_rounded,
              title: _agentsViewLifecycleLabel(context),
              body: _agentLifecycleStateValueLabel(
                l10n,
                agent.lifecycleState.storageValue,
              ),
              compact: true,
            ),
            _AgentTaskDetailBlock(
              icon: Icons.verified_outlined,
              title: _agentsViewEnabledLabel(context),
              body: _agentBooleanLabel(context, 'enabled', agent.enabled),
              compact: true,
            ),
            _AgentTaskDetailBlock(
              icon: Icons.admin_panel_settings_outlined,
              title: openHandLocalizedText(context, zh: '执行模式', en: 'Mode'),
              body: _agentExecutionModeLabel(l10n, agent.executionMode),
              compact: true,
            ),
            _AgentTaskDetailBlock(
              icon: Icons.auto_awesome_rounded,
              title: openHandLocalizedText(
                context,
                zh: '自学习',
                en: 'Self-learning',
              ),
              body: _agentBooleanLabel(
                context,
                'enabled',
                agent.selfLearningEnabled,
              ),
              compact: true,
            ),
            _AgentTaskDetailBlock(
              icon: Icons.psychology_alt_outlined,
              title: openHandModelLabel(context),
              body: nullIfBlank(agent.modelId) ?? '-',
              compact: true,
            ),
            _AgentTaskDetailBlock(
              icon: Icons.settings_applications_outlined,
              title: _agentsViewModelConfigLabel(context),
              body: nullIfBlank(agent.modelProviderConfigId) ?? '-',
              compact: true,
            ),
            _AgentTaskDetailBlock(
              icon: Icons.folder_open_rounded,
              title: openHandWorkspaceLabel(context),
              body: agent.workspacePath,
              compact: true,
            ),
            _AgentTaskDetailBlock(
              icon: Icons.rule_folder_outlined,
              title: openHandLocalizedText(
                context,
                zh: '工作区范围',
                en: 'Workspace scope',
              ),
              body: agent.workspaceScopeText,
              compact: true,
            ),
          ],
        ),
        _AgentTaskDetailGrid(
          children: [
            _AgentTaskDetailBlock(
              icon: Icons.school_rounded,
              title: 'Skill',
              body: _agentJoinedText(agent.skillNames),
              compact: true,
            ),
            _AgentTaskDetailBlock(
              icon: Icons.hub_rounded,
              title: 'MCP',
              body: _agentJoinedText(agent.mcpServerNames),
              compact: true,
            ),
            _AgentTaskDetailBlock(
              icon: Icons.library_books_rounded,
              title: openHandKnowledgeLabel(context),
              body: _agentJoinedText(agent.knowledgeSourceIds),
              compact: true,
            ),
            _AgentTaskDetailBlock(
              icon: Icons.psychology_rounded,
              title: openHandMemoryLabel(context),
              body: _agentJoinedText(agent.memoryIds),
              compact: true,
            ),
            _AgentTaskDetailBlock(
              icon: Icons.extension_rounded,
              title: openHandLocalizedText(
                context,
                zh: '内建工具',
                en: 'Built-in tools',
              ),
              body: _agentJoinedText(
                agentVisibleBuiltinToolNames(agent.builtinToolNames),
              ),
              compact: true,
            ),
          ],
        ),
        _AgentTaskDetailGrid(
          children: [
            _AgentTaskDetailBlock(
              icon: Icons.speed_rounded,
              title: openHandLocalizedText(
                context,
                zh: '资源使用',
                en: 'Resources',
              ),
              body: _agentPrettyJsonForDisplay(
                agent.resourceUsage.toJson(includeInternalExtra: false),
              ),
              monospace: true,
            ),
            _AgentTaskDetailBlock(
              icon: Icons.account_tree_outlined,
              title: openHandLocalizedText(
                context,
                zh: '集群伸缩',
                en: 'Cluster scale',
              ),
              body: _agentPrettyJsonForDisplay(agent.scaleSettings.toJson()),
              monospace: true,
            ),
            _AgentTaskDetailBlock(
              icon: Icons.data_object_rounded,
              title: 'agent.metadata',
              body: _agentPrettyJsonForDisplay(agent.metadata),
              monospace: true,
            ),
          ],
        ),
      ],
    );
  }
}

class _AgentCapabilityLogDetailHero extends StatelessWidget {
  const _AgentCapabilityLogDetailHero({
    required this.event,
    required this.capabilityName,
    required this.typeLabel,
    required this.color,
  });

  final AgentAuditEvent event;
  final String capabilityName;
  final String typeLabel;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final summary = _agentAuditSummaryText(context, event);
    final created = _agentDateTimeLabel(event.createdAt);
    final taskId = _agentLogMetadataText(event.metadata, 'task_id');
    final workerId = _agentLogMetadataText(event.metadata, 'worker_id');
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            color.withValues(alpha: 0.16),
            cs.surfaceContainerHighest.withValues(alpha: 0.46),
          ],
        ),
        borderRadius: BorderRadius.circular(kOpenHandRadius20),
        border: Border.all(color: color.withValues(alpha: 0.26)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 620;
            final leading = Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(kOpenHandRadius17),
              ),
              alignment: Alignment.center,
              child: Icon(
                _agentCapabilityLogIcon(_agentAuditCapabilityType(event)),
                color: color,
                size: 28,
              ),
            );
            final content = Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _AgentActivityTypeChip(label: typeLabel, color: color),
                      if (created.isNotEmpty)
                        _AgentActivityMetadataChip(text: created),
                      if (taskId.isNotEmpty)
                        _AgentActivityMetadataChip(
                          text:
                              _agentMetadataChipText(
                                context,
                                'task_id',
                                taskId,
                              ) ??
                              taskId,
                        ),
                      if (workerId.isNotEmpty)
                        _AgentActivityMetadataChip(
                          text:
                              _agentMetadataChipText(
                                context,
                                'worker_id',
                                workerId,
                              ) ??
                              workerId,
                        ),
                    ],
                  ),
                  kOpenHandGap10,
                  Text(
                    nonBlankStringOr(capabilityName, '-'),
                    maxLines: compact ? 3 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      height: 1.18,
                    ),
                  ),
                  if (summary.trim().isNotEmpty) ...[
                    kOpenHandGap8,
                    SelectableText(
                      summary,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.42),
                    ),
                  ],
                ],
              ),
            );
            if (compact) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [leading, kOpenHandHGap12, content],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [leading, kOpenHandHGap14, content],
            );
          },
        ),
      ),
    );
  }
}

class _AgentLogDetailSection extends StatelessWidget {
  const _AgentLogDetailSection({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: cs.primary),
            kOpenHandHGap8,
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        kOpenHandGap10,
        child,
      ],
    );
  }
}

Future<void> _showAgentApprovalsDialog(
  BuildContext context,
  AgentProfile agent,
) {
  final l10n = AppLocalizations.of(context)!;
  return _showLiveAgentDialog(
    context,
    agent,
    maxWidth: 820,
    maxHeight: 680,
    builder: (context, currentAgent) {
      return _AgentDialogScaffold(
        icon: Icons.verified_user_rounded,
        title: l10n.agentsDialogTitleWithName(
          l10n.agentsApprovals,
          currentAgent.name,
        ),
        footer: _agentDialogPrimaryActionFooter(
          icon: Icons.add_moderator_outlined,
          onPressed: () =>
              _showAgentApprovalRequestDialog(context, currentAgent),
          label: _agentsViewRequestApprovalLabel(context),
        ),
        child: currentAgent.approvals.isEmpty
            ? FeatureStateCard.inline(
                icon: Icons.verified_user_outlined,
                title: l10n.agentsApprovalsEmptyTitle,
                body: l10n.agentsListEmptyBody,
              )
            : _AgentApprovalsBody(
                approvals: currentAgent.approvals,
                onApproved: (approval) => _resolveAgentApprovalFromDialog(
                  context,
                  currentAgent,
                  approval,
                  AgentApprovalStatus.approved,
                ),
                onRejected: (approval) => _resolveAgentApprovalFromDialog(
                  context,
                  currentAgent,
                  approval,
                  AgentApprovalStatus.rejected,
                ),
              ),
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
        .where((item) => _agentApprovalIsHighRisk(agentApprovalRiskLevel(item)))
        .length;
    final visibleApprovals = sortedAgentApprovalsForAttention(approvals);
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
              label: _agentsViewHighRiskLabel(context),
              value: '$highRisk',
            ),
          ],
        ),
        kOpenHandGap14,
        ListView.separated(
          shrinkWrap: true,
          primary: false,
          itemCount: visibleApprovals.length,
          separatorBuilder: (_, _) => kOpenHandGap10,
          itemBuilder: (context, index) {
            final approval = visibleApprovals[index];
            return _AgentApprovalRequestCard(
              approval: approval,
              onApproved: () => onApproved(approval),
              onRejected: () => onRejected(approval),
            );
          },
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
    final riskLevel = agentApprovalRiskLevel(approval);
    final riskColor = _agentApprovalRiskColor(cs, riskLevel);
    final metadata = _agentApprovalMetadataChips(context, approval);
    final timeText = _agentApprovalTimeLabel(context, approval);
    return DecoratedBox(
      decoration: _agentListCardDecoration(
        cs,
        borderRadius: kOpenHandBorderRadius12,
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
                borderRadius: kOpenHandBorderRadius10,
              ),
              alignment: Alignment.center,
              child: Icon(
                _agentApprovalStatusIcon(approval.status),
                color: statusColor,
                size: 19,
              ),
            ),
            kOpenHandHGap12,
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
                  kOpenHandGap8,
                  Text(
                    approval.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (approval.requestedAction.trim().isNotEmpty) ...[
                    kOpenHandGap6,
                    SelectableText(
                      approval.requestedAction,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (approval.reason.trim().isNotEmpty) ...[
                    kOpenHandGap5,
                    SelectableText(
                      approval.reason,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
                    ),
                  ],
                  if (metadata.isNotEmpty) ...[
                    kOpenHandGap8,
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: metadata
                          .map((item) => _AgentActivityMetadataChip(text: item))
                          .toList(growable: false),
                    ),
                  ],
                  if (approval.status == AgentApprovalStatus.pending) ...[
                    kOpenHandGap10,
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
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer<AgentsController>(
      builder: (dialogContext, controller, _) {
        final currentAgent =
            controller.agentById(widget.agent.id) ?? widget.agent;
        final settings = currentAgent.scaleSettings;
        return buildOpenHandDialog(
          maxWidth: kOpenHandDialogWidthWide,
          maxHeight: kOpenHandDialogHeightTall,
          child: _AgentDialogScaffold(
            icon: Icons.account_tree_rounded,
            title: l10n.agentsDialogTitleWithName(
              l10n.agentsCluster,
              currentAgent.name,
            ),
            footerAnimationKey: _editing ? 'cluster-edit' : 'cluster-status',
            footer: _editing
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OpenHandDialogBusyBar(busy: _saving, topGap: 0),
                      _agentDialogActionsFooter(
                        actions: [
                          OpenHandDialogActionButton.secondary(
                            onPressed: _saving
                                ? null
                                : () => setState(() => _editing = false),
                            label: l10n.commonCancel,
                          ),
                          OpenHandDialogActionButton.primary(
                            onPressed: _saving
                                ? null
                                : () => _saveClusterSettings(
                                    context,
                                    controller,
                                    currentAgent,
                                  ),
                            label: l10n.commonSave,
                          ),
                        ],
                      ),
                    ],
                  )
                : _agentDialogPrimaryActionFooter(
                    icon: Icons.tune_rounded,
                    onPressed: () => setState(() => _editing = true),
                    label: openHandLocalizedText(
                      context,
                      zh: '调整集群',
                      en: 'Tune cluster',
                    ),
                  ),
            child: Builder(
              builder: (context) {
                final motionSettings = _agentDialogAnimationSettings(context);
                return AnimatedSwitcher(
                  duration: motionSettings.entranceDuration,
                  reverseDuration: motionSettings.exitDuration,
                  transitionBuilder: (child, animation) =>
                      _agentDialogSwitchTransition(
                        settings: motionSettings,
                        animation: animation,
                        child: child,
                      ),
                  child: _editing
                      ? _AgentClusterSettingsEditor(
                          key: _clusterEditorKey,
                          initial: settings,
                        )
                      : _buildClusterStatus(dialogContext, currentAgent),
                );
              },
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
    if (_saving) return;
    FocusScope.of(context).unfocus();
    final updated = _clusterEditorKey.currentState?.buildSettings();
    if (updated == null) return;
    final failureMessage = openHandLocalizedText(
      context,
      zh: '集群设置保存失败，请稍后重试。',
      en: 'Failed to save cluster settings. Try again.',
    );
    setState(() => _saving = true);
    final saved = await controller.saveScaleSettings(currentAgent.id, updated);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (saved) _editing = false;
    });
    if (saved) {
      return;
    }
    _showAgentErrorSnack(this.context, failureMessage);
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
              label: _agentsViewQueuedLabel(context),
              value: '$queuedTasks',
            ),
            _MetricTile(
              label: _agentsViewRunningLabel(context),
              value: '${currentAgent.runningTaskCount}',
            ),
            _MetricTile(
              label: _agentsViewBlockedLabel(context),
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
        kOpenHandGap18,
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OpenHandStatusPill(
              icon: Icons.compress_rounded,
              label: l10n.agentsMinWorkersCount(settings.minWorkers),
              color: Theme.of(context).colorScheme.primary,
            ),
            OpenHandStatusPill(
              icon: Icons.unfold_more_rounded,
              label: l10n.agentsMaxWorkersCount(settings.maxWorkers),
              color: Theme.of(context).colorScheme.secondary,
            ),
            OpenHandStatusPill(
              icon: Icons.route_rounded,
              label: _agentPolicyOptionLabel(context, settings.schedulerPolicy),
              color: Theme.of(context).colorScheme.tertiary,
            ),
            OpenHandStatusPill(
              icon: Icons.repeat_rounded,
              label:
                  '${_agentPolicyOptionLabel(context, settings.retryPolicy)} · ${settings.maxRetries}',
              color: Theme.of(context).colorScheme.primary,
            ),
            OpenHandStatusPill(
              icon: Icons.compare_arrows_rounded,
              label:
                  '${(settings.scaleOutThreshold * 100).round()}% / ${(settings.scaleInThreshold * 100).round()}%',
              color: Theme.of(context).colorScheme.secondary,
            ),
            OpenHandStatusPill(
              icon: Icons.low_priority_rounded,
              label: _agentPolicyOptionLabel(
                context,
                settings.workerRemovalPolicy,
              ),
              color: Theme.of(context).colorScheme.tertiary,
            ),
            if (settings.tags.isNotEmpty)
              OpenHandStatusPill(
                icon: Icons.label_outline_rounded,
                label: settings.tags.join(', '),
                color: Theme.of(context).colorScheme.primary,
              ),
          ],
        ),
        kOpenHandGap18,
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
    final currentTaskProgress = _agentWorkerCurrentTaskProgress(agent, worker);
    final details = _agentWorkerDetailChips(context, agent, worker);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.42),
          borderRadius: kOpenHandBorderRadius8,
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
              kOpenHandHGap12,
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
                    kOpenHandGap6,
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _AgentActivityTypeChip(
                          label: _agentWorkerStatusLabel(l10n, worker.status),
                          color: statusColor,
                        ),
                        _AgentActivityMetadataChip(
                          text: l10n.agentsWorkerSubtitle(
                            _agentWorkerStatusLabel(l10n, worker.status),
                            worker.executedTaskCount,
                            worker.priority,
                          ),
                        ),
                        if (currentTask.isNotEmpty)
                          _AgentActivityMetadataChip(text: currentTask),
                        for (final detail in details)
                          _AgentActivityMetadataChip(text: detail),
                      ],
                    ),
                    kOpenHandGap8,
                    LinearProgressIndicator(
                      value: clampUnitInterval(worker.busyScore),
                      minHeight: 5,
                      borderRadius: kOpenHandPillBorderRadius,
                      color: statusColor,
                      backgroundColor: colors.surfaceContainerHighest,
                    ),
                    if (currentTaskProgress != null) ...[
                      kOpenHandGap6,
                      Text(
                        openHandLocalizedText(
                          context,
                          zh: '当前任务进度 ${(currentTaskProgress * 100).round()}%',
                          en: 'Current task ${(currentTaskProgress * 100).round()}%',
                        ),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
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
    _maxWorkers = _normalizeAgentMaxWorkers(initial.maxWorkers);
    _minWorkers = _normalizeAgentMinWorkers(initial.minWorkers, _maxWorkers);
    _maxRetries = _normalizeAgentMaxRetries(initial.maxRetries);
    _scaleOutThreshold = _normalizeAgentScaleRatio(initial.scaleOutThreshold);
    _scaleInThreshold = _normalizeAgentScaleRatio(initial.scaleInThreshold);
    _schedulerPolicy =
        agentSchedulerPolicyOptions.contains(initial.schedulerPolicy)
        ? initial.schedulerPolicy
        : agentSchedulerPolicyOptions.first;
    _workerRemovalPolicy =
        agentWorkerRemovalPolicyOptions.contains(initial.workerRemovalPolicy)
        ? initial.workerRemovalPolicy
        : agentWorkerRemovalPolicyOptions.first;
    _retryPolicy = agentRetryPolicyOptions.contains(initial.retryPolicy)
        ? initial.retryPolicy
        : agentRetryPolicyOptions.first;
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
              min: agentScaleMinWorkersMinimum,
              max: _maxWorkers,
              onChanged: (value) => setState(
                () =>
                    _minWorkers = _normalizeAgentMinWorkers(value, _maxWorkers),
              ),
            ),
            _clusterNumberStepper(
              l10n.agentsMaxWorkersLabel,
              _maxWorkers,
              min: agentScaleMaxWorkersMinimum,
              max: agentScaleWorkersMaximum,
              onChanged: (value) => setState(() {
                _maxWorkers = _normalizeAgentMaxWorkers(value);
                _minWorkers = _normalizeAgentMinWorkers(
                  _minWorkers,
                  _maxWorkers,
                );
              }),
            ),
            _clusterNumberStepper(
              l10n.agentsMaxRetriesLabel,
              _maxRetries,
              min: agentScaleMaxRetriesMinimum,
              max: agentScaleMaxRetriesMaximum,
              onChanged: (value) => setState(
                () => _maxRetries = _normalizeAgentMaxRetries(value),
              ),
            ),
            _FormGridItem(
              fullWidth: true,
              child: _clusterTagEditor(
                label: _agentsViewWorkerTagsLabel(context),
              ),
            ),
            _clusterRatioSlider(
              _agentsViewScaleOutThresholdLabel(context),
              _scaleOutThreshold,
              (value) => setState(() => _scaleOutThreshold = value),
            ),
            _clusterRatioSlider(
              _agentsViewScaleInThresholdLabel(context),
              _scaleInThreshold,
              (value) => setState(() => _scaleInThreshold = value),
            ),
            _clusterPolicyDropdown(
              label: l10n.agentsSchedulerPolicyLabel,
              value: _schedulerPolicy,
              values: agentSchedulerPolicyOptions,
              onChanged: (value) => setState(() => _schedulerPolicy = value),
            ),
            _clusterPolicyDropdown(
              label: _agentsViewWorkerRemovalPolicyLabel(context),
              value: _workerRemovalPolicy,
              values: agentWorkerRemovalPolicyOptions,
              onChanged: (value) =>
                  setState(() => _workerRemovalPolicy = value),
            ),
            _clusterPolicyDropdown(
              label: _agentsViewRetryPolicyLabel(context),
              value: _retryPolicy,
              values: agentRetryPolicyOptions,
              onChanged: (value) => setState(() => _retryPolicy = value),
            ),
          ],
        ),
      ],
    );
  }

  Widget _clusterNumberStepper(
    String label,
    int value, {
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return _FormGridItem(
      child: _AgentNumberStepperField(
        label: label,
        value: value,
        min: min,
        max: max,
        onChanged: onChanged,
      ),
    );
  }

  Widget _clusterRatioSlider(
    String label,
    double value,
    ValueChanged<double> onChanged,
  ) {
    final normalized = _normalizeAgentScaleRatio(value);
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
      child: AnimatedDropdownButtonFormField<String>(
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
    final maxWorkers = _normalizeAgentMaxWorkers(_maxWorkers);
    final minWorkers = _normalizeAgentMinWorkers(_minWorkers, maxWorkers);
    final maxRetries = _normalizeAgentMaxRetries(_maxRetries);
    return AgentScaleSettings(
      minWorkers: minWorkers,
      maxWorkers: maxWorkers,
      scaleOutThreshold: _normalizeAgentScaleRatio(_scaleOutThreshold),
      scaleInThreshold: _normalizeAgentScaleRatio(_scaleInThreshold),
      workerRemovalPolicy: _workerRemovalPolicy,
      retryPolicy: _retryPolicy,
      maxRetries: maxRetries,
      schedulerPolicy: _schedulerPolicy,
      tags: dedupeNonEmptyStrings(_tags),
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
                    hintText: _agentsViewEnterTextThenAddLabel(context),
                  ),
                  onSubmitted: (_) => _addClusterTag(),
                ),
              ),
              kOpenHandHGap10,
              FilledButton.tonalIcon(
                key: const ValueKey<String>('agent-cluster-tag-add'),
                onPressed: _addClusterTag,
                icon: const Icon(Icons.add_rounded),
                label: Text(openHandAddLabel(context)),
              ),
            ],
          ),
          kOpenHandGap10,
          _AnimatedReorderableChipStrip(
            values: _tags,
            emptyText: _agentsViewNoWorkerTagsYetLabel(context),
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
}

Future<void> _showAgentTasksDialog(BuildContext context, AgentProfile agent) {
  final l10n = AppLocalizations.of(context)!;
  return _showLiveAgentDialog(
    context,
    agent,
    maxWidth: 960,
    maxHeight: 720,
    builder: (context, currentAgent) {
      return _AgentDialogScaffold(
        icon: Icons.task_alt_rounded,
        title: l10n.agentsDialogTitleWithName(
          l10n.agentsTaskDesk,
          currentAgent.name,
        ),
        footer: _agentDialogPrimaryActionFooter(
          icon: Icons.add_task_rounded,
          onPressed: () => _showPublishTaskDialog(context, currentAgent),
          label: l10n.agentsPublishTask,
        ),
        child: currentAgent.tasks.isEmpty
            ? FeatureStateCard.inline(
                icon: Icons.task_alt_rounded,
                title: l10n.agentsNoTasksTitle,
                body: l10n.agentsNoTasksBody,
              )
            : _AgentTasksBody(agent: currentAgent, tasks: currentAgent.tasks),
      );
    },
  );
}

class _AgentTasksBody extends StatelessWidget {
  const _AgentTasksBody({required this.agent, required this.tasks});

  final AgentProfile agent;
  final List<AgentTask> tasks;

  @override
  Widget build(BuildContext context) {
    final active = tasks.where((task) => !task.status.isTerminal).length;
    final completed = tasks
        .where((task) => task.status == AgentTaskStatus.completed)
        .length;
    final averageProgress = tasks.isEmpty
        ? 0
        : (tasks.fold<double>(0, (sum, task) => sum + task.progress) /
                  tasks.length *
                  100)
              .round();
    final visibleTasks = sortedAgentTasksForAttention(tasks);
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
            _MetricTile(label: openHandActiveLabel(context), value: '$active'),
            _MetricTile(
              label: openHandCompletedLabel(context),
              value: '$completed',
            ),
            _MetricTile(
              label: _agentsViewAvgProgressLabel(context),
              value: '$averageProgress%',
            ),
          ],
        ),
        kOpenHandGap14,
        ListView.separated(
          shrinkWrap: true,
          primary: false,
          itemCount: visibleTasks.length,
          separatorBuilder: (_, _) => kOpenHandGap10,
          itemBuilder: (context, index) {
            return _AgentTaskCard(agent: agent, task: visibleTasks[index]);
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
        : formatMonthDayHmLocal(task.createdAt!);
    final tracking = _agentTaskTrackingChips(context, agent, task);
    final metadata = _agentTaskMetadataChips(context, task);
    final progress = clampUnitInterval(task.progress);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: kOpenHandBorderRadius12,
        onTap: () => _showAgentTaskDetailDialog(context, agent, task),
        child: DecoratedBox(
          decoration: _agentListCardDecoration(
            cs,
            borderRadius: kOpenHandBorderRadius12,
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
                    borderRadius: kOpenHandBorderRadius10,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    _agentTaskStatusIcon(task.status),
                    color: statusColor,
                    size: 19,
                  ),
                ),
                kOpenHandHGap12,
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
                      kOpenHandGap8,
                      Text(
                        task.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (task.description.trim().isNotEmpty) ...[
                        kOpenHandGap5,
                        Text(
                          task.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.35,
                          ),
                        ),
                      ],
                      kOpenHandGap10,
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: kOpenHandPillBorderRadius,
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 7,
                                color: statusColor,
                                backgroundColor: cs.surfaceContainerHighest,
                              ),
                            ),
                          ),
                          kOpenHandHGap10,
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
                          tracking.isNotEmpty ||
                          metadata.isNotEmpty) ...[
                        kOpenHandGap9,
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final item in tracking)
                              _AgentActivityMetadataChip(text: item),
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
                kOpenHandHGap12,
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
  final trackingSummary = _agentTaskTrackingSummary(context, agent, task);
  final extraText = prettyPrintJson(_agentTaskExtraDisplayJson(task.extra));
  return showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) => buildOpenHandResponsiveDialogShell(
      context: dialogContext,
      maxWidth: kOpenHandDialogWidthExtraWide,
      maxHeight: kOpenHandDialogHeightTall,
      maxWidthFraction: _agentTaskDetailMaxWidthFraction,
      maxHeightFraction: _agentTaskDetailMaxHeightFraction,
      horizontalMargin: _agentTaskDetailHorizontalMargin,
      verticalMargin: _agentTaskDetailVerticalMargin,
      minAvailableWidth: _agentTaskDetailMinAvailableWidth,
      child: _AgentDialogScaffold(
        icon: Icons.task_alt_rounded,
        title: openHandLocalizedText(
          context,
          zh: '任务详情',
          zhHant: '任務詳情',
          en: 'Task details',
          fr: 'Détails de la tâche',
          de: 'Aufgabendetails',
          ja: 'タスク詳細',
        ),
        child: _AgentTaskDetailSectionList(
          children: [
            _AgentTaskDetailHero(
              task: task,
              statusLabel: _agentTaskStatusLabel(l10n, task.status),
              statusColor: _agentTaskStatusColor(
                Theme.of(context).colorScheme,
                task.status,
              ),
              assignedWorker: assignedWorker,
              nextAction: trackingSummary.nextAction,
            ),
            _AgentTaskDetailFactPanel(
              children: [
                _AgentTaskDetailFact(
                  icon: Icons.tag_rounded,
                  title: 'ID',
                  value: task.id,
                ),
                _AgentTaskDetailFact(
                  icon: Icons.schedule_rounded,
                  title: openHandCreatedLabel(context),
                  value: _agentDateTimeLabel(task.createdAt),
                ),
                _AgentTaskDetailFact(
                  icon: Icons.update_rounded,
                  title: openHandUpdatedLabel(context),
                  value: _agentDateTimeLabel(task.updatedAt),
                ),
                _AgentTaskDetailFact(
                  icon: Icons.handshake_outlined,
                  title: openHandLocalizedText(
                    context,
                    zh: '交接状态',
                    en: 'Handoff',
                  ),
                  value: trackingSummary.handoff,
                ),
                _AgentTaskDetailFact(
                  icon: Icons.build_circle_outlined,
                  title: openHandLocalizedText(
                    context,
                    zh: '推荐工具',
                    en: 'Recommended tool',
                  ),
                  value: trackingSummary.recommendedTool,
                ),
                _AgentTaskDetailFact(
                  icon: Icons.engineering_outlined,
                  title: _agentsViewAssignedWorkerLabel(context),
                  value: assignedWorker,
                ),
              ],
            ),
            _AgentTaskDetailBlock(
              icon: Icons.short_text_rounded,
              title: l10n.agentsDescriptionLabel,
              body: task.description,
            ),
            _AgentTaskDetailBlock(
              icon: Icons.article_outlined,
              title: l10n.agentsContentLabel,
              body: task.content,
            ),
            _AgentTaskDetailBlock(
              icon: Icons.fact_check_outlined,
              title: _agentsViewTaskResultLabel(context),
              body: task.result,
            ),
            _AgentTaskDetailBlock(
              icon: Icons.sticky_note_2_outlined,
              title: l10n.agentsNoteLabel,
              body: task.note,
            ),
            _AgentTaskDetailBlock(
              icon: Icons.code_rounded,
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
    final canPauseOrComplete = task.status.isPendingExecution;
    final canStop = !task.status.isTerminal;
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
        kOpenHandHGap6,
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
        else if (canPauseOrComplete)
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
        if (canPauseOrComplete) ...[
          kOpenHandHGap6,
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
          kOpenHandHGap6,
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
          kOpenHandHGap6,
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
              extra: const <String, Object?>{'tool_action': 'task_terminated'},
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

List<String> _agentTaskMetadataChips(BuildContext context, AgentTask task) {
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
    final text = _agentMetadataChipText(context, key, task.extra[key]);
    if (text != null) chips.add(text);
    if (chips.length >= 4) break;
  }
  return chips;
}

List<String> _agentTaskTrackingChips(
  BuildContext context,
  AgentProfile agent,
  AgentTask task,
) {
  final summary = _agentTaskTrackingSummary(context, agent, task);
  final chips = <String>[
    openHandLocalizedText(
      context,
      zh: '下一步: ${summary.nextAction}',
      en: 'Next: ${summary.nextAction}',
    ),
  ];
  if (_agentTaskNeedsPolling(task.status)) {
    chips.add(
      openHandLocalizedText(
        context,
        zh: '轮询: ${summary.recommendedTool}',
        en: 'Poll: ${summary.recommendedTool}',
      ),
    );
  } else if (task.hasResult) {
    chips.add(
      openHandLocalizedText(
        context,
        zh: '结果可读: ${summary.recommendedTool}',
        en: 'Result: ${summary.recommendedTool}',
      ),
    );
  } else if (task.status == AgentTaskStatus.waitingApproval) {
    chips.add(openHandLocalizedText(context, zh: '需审批', en: 'Approval'));
  } else if (task.status == AgentTaskStatus.paused) {
    chips.add(_agentsViewPausedLabel(context));
  }
  final retryCount = nonNegativeIntFromValue(
    task.extra['retry_count'],
    fallback: 0,
  );
  if (retryCount > 0) {
    chips.add(
      openHandLocalizedText(
        context,
        zh: '重试: $retryCount',
        en: 'Retry: $retryCount',
      ),
    );
  }
  return chips;
}

_AgentTaskTrackingSummary _agentTaskTrackingSummary(
  BuildContext context,
  AgentProfile agent,
  AgentTask task,
) {
  final canPoll = _agentTaskCanPoll(agent);
  final nextAction = switch (task.status) {
    AgentTaskStatus.backlog ||
    AgentTaskStatus.ready ||
    AgentTaskStatus.running =>
      canPoll
          ? openHandLocalizedText(context, zh: '轮询进度', en: 'Poll progress')
          : openHandLocalizedText(
              context,
              zh: '开启轮询工具',
              en: 'Enable polling tool',
            ),
    AgentTaskStatus.waitingApproval => openHandLocalizedText(
      context,
      zh: '处理审批',
      en: 'Review approval',
    ),
    AgentTaskStatus.paused => openHandLocalizedText(
      context,
      zh: '恢复或取消',
      en: 'Resume or cancel',
    ),
    AgentTaskStatus.completed =>
      task.hasResult
          ? openHandLocalizedText(context, zh: '读取结果', en: 'Read result')
          : openHandLocalizedText(context, zh: '结果缺失', en: 'Result missing'),
    AgentTaskStatus.failed =>
      _agentTaskTerminalReason(task) == 'terminated'
          ? openHandLocalizedText(context, zh: '已终止', en: 'Terminated')
          : openHandLocalizedText(context, zh: '检查失败', en: 'Inspect failure'),
    AgentTaskStatus.canceled => openHandLocalizedText(
      context,
      zh: '已取消',
      en: 'Canceled',
    ),
  };
  final handoff = switch (task.status) {
    AgentTaskStatus.waitingApproval => openHandLocalizedText(
      context,
      zh: '等待审批后继续执行',
      en: 'Waiting for approval before continuing',
    ),
    AgentTaskStatus.paused => openHandLocalizedText(
      context,
      zh: '任务已暂停，需要恢复或取消',
      en: 'Task is paused; resume or cancel it',
    ),
    AgentTaskStatus.completed =>
      task.hasResult
          ? openHandLocalizedText(context, zh: '结果已就绪', en: 'Result ready')
          : openHandLocalizedText(
              context,
              zh: '已完成但缺少结果',
              en: 'Completed without result',
            ),
    AgentTaskStatus.failed =>
      _agentTaskTerminalReason(task) == 'terminated'
          ? openHandLocalizedText(context, zh: '任务已终止', en: 'Task terminated')
          : openHandLocalizedText(context, zh: '任务失败待排查', en: 'Task failed'),
    AgentTaskStatus.canceled => openHandLocalizedText(
      context,
      zh: '任务已取消',
      en: 'Task canceled',
    ),
    AgentTaskStatus.backlog ||
    AgentTaskStatus.ready ||
    AgentTaskStatus.running =>
      canPoll
          ? openHandLocalizedText(
              context,
              zh: '结果未就绪，建议定时轮询',
              en: 'Result is not ready; poll periodically',
            )
          : openHandLocalizedText(
              context,
              zh: '结果未就绪，请先为该智能体开启轮询工具',
              en: 'Result is not ready; enable a polling tool for this agent',
            ),
  };
  final recommendedTool = _agentTaskRecommendedTool(context, agent, task);
  return _AgentTaskTrackingSummary(
    nextAction: nextAction,
    handoff: handoff,
    recommendedTool: recommendedTool,
  );
}

bool _agentTaskNeedsPolling(AgentTaskStatus status) {
  return status.isPendingExecution;
}

String _agentTaskRecommendedTool(
  BuildContext context,
  AgentProfile agent,
  AgentTask task,
) {
  if (_agentTaskNeedsPolling(task.status)) {
    if (_agentTaskToolAvailable(agent, agentTaskProgressToolName)) {
      return '$agentTaskProgressToolName · ${agentTaskRecommendedPollMs}ms';
    }
    if (_agentTaskToolAvailable(agent, agentTaskResultToolName)) {
      return '$agentTaskResultToolName · ${agentTaskRecommendedPollMs}ms';
    }
    return openHandLocalizedText(
      context,
      zh: '需开启 AgentTaskProgress 或 AgentTaskResult',
      en: 'Enable AgentTaskProgress or AgentTaskResult',
    );
  }
  if (task.hasResult &&
      _agentTaskToolAvailable(agent, agentTaskResultToolName)) {
    return agentTaskResultToolName;
  } else if (task.hasResult) {
    return openHandLocalizedText(
      context,
      zh: '需开启 AgentTaskResult',
      en: 'Enable AgentTaskResult',
    );
  }
  return switch (task.status) {
    AgentTaskStatus.waitingApproval => 'AgentApprovalRequest',
    AgentTaskStatus.paused => 'AgentTaskResume',
    AgentTaskStatus.completed =>
      _agentTaskToolAvailable(agent, agentTaskTrackToolName)
          ? agentTaskTrackToolName
          : _agentsViewEnableAgenttasktrackLabel(context),
    AgentTaskStatus.failed || AgentTaskStatus.canceled =>
      _agentTaskToolAvailable(agent, agentTaskTrackToolName)
          ? agentTaskTrackToolName
          : _agentsViewEnableAgenttasktrackLabel(context),
    AgentTaskStatus.backlog ||
    AgentTaskStatus.ready ||
    AgentTaskStatus.running =>
      _agentTaskToolAvailable(agent, agentTaskProgressToolName)
          ? agentTaskProgressToolName
          : openHandLocalizedText(
              context,
              zh: '需开启 AgentTaskProgress',
              en: 'Enable AgentTaskProgress',
            ),
  };
}

bool _agentTaskCanPoll(AgentProfile agent) {
  return _agentTaskToolAvailable(agent, agentTaskProgressToolName) ||
      _agentTaskToolAvailable(agent, agentTaskResultToolName);
}

bool _agentTaskToolAvailable(AgentProfile agent, String toolName) {
  final configured = normalizeAgentBuiltinToolNames(agent.builtinToolNames);
  if (configured.isEmpty) return true;
  if (agentHasNoCoordinationToolsBinding(configured)) return false;
  final normalizedTool = _normalizeAgentTaskToolName(toolName);
  return agentVisibleBuiltinToolNames(
    configured,
  ).any((name) => _normalizeAgentTaskToolName(name) == normalizedTool);
}

String _normalizeAgentTaskToolName(String value) {
  return normalizeAsciiLookupKey(value);
}

String? _agentTaskTerminalReason(AgentTask task) {
  if (task.status == AgentTaskStatus.completed) return 'completed';
  if (task.status == AgentTaskStatus.canceled) return 'canceled';
  if (task.status != AgentTaskStatus.failed) return null;
  return '${task.extra['tool_action'] ?? ''}'.trim() == 'task_terminated'
      ? 'terminated'
      : 'failed';
}

class _AgentTaskTrackingSummary {
  const _AgentTaskTrackingSummary({
    required this.nextAction,
    required this.handoff,
    required this.recommendedTool,
  });

  final String nextAction;
  final String handoff;
  final String recommendedTool;
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
  Map<String, Object?>? extra,
}) async {
  final updated = await context.read<AgentsController>().updateTaskState(
    agent.id,
    task.id,
    status: status,
    note: note.trim().isEmpty ? null : note.trim(),
    result: result.trim().isEmpty ? null : result.trim(),
    extra: extra,
    activityKind: activityKind,
    activityTitle: activityTitle,
  );
  if (updated == null && context.mounted) {
    _showAgentErrorSnack(
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
  Map<String, Object?>? extra,
}) async {
  final confirmed = await showOpenHandConfirmDialog(
    context: context,
    title: openHandLocalizedText(context, zh: titleZh, en: titleEn),
    message: openHandLocalizedText(context, zh: messageZh, en: messageEn),
    confirmLabel: openHandConfirmLabel(context),
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
      extra: extra,
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
        maxWidth: kOpenHandDialogWidthStandard,
        child: _AgentDialogScaffold(
          icon: Icons.done_all_rounded,
          title: openHandLocalizedText(
            context,
            zh: '完成任务',
            en: 'Complete task',
          ),
          footer: _agentDialogActionsFooter(
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
              kOpenHandGap12,
              TextField(
                controller: result,
                minLines: 4,
                maxLines: 8,
                decoration: InputDecoration(
                  labelText: _agentsViewTaskResultLabel(context),
                ),
              ),
              kOpenHandGap12,
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
        _showAgentInfoSnack(
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
    builder: (dialogContext) => buildOpenHandResponsiveDialogShell(
      context: dialogContext,
      maxWidth: kOpenHandDialogWidthExtraWide,
      maxHeight: kOpenHandDialogHeightTall,
      maxWidthFraction: _agentTaskDetailMaxWidthFraction,
      maxHeightFraction: _agentTaskDetailMaxHeightFraction,
      horizontalMargin: _agentTaskDetailHorizontalMargin,
      verticalMargin: _agentTaskDetailVerticalMargin,
      minAvailableWidth: _agentTaskDetailMinAvailableWidth,
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
  return _showLiveAgentDialog(
    context,
    agent,
    maxWidth: 860,
    maxHeight: 680,
    builder: (context, currentAgent) {
      return _AgentDialogScaffold(
        icon: Icons.flag_rounded,
        title: l10n.agentsDialogTitleWithName(
          l10n.agentsKpi,
          currentAgent.name,
        ),
        footer: _agentDialogPrimaryActionFooter(
          icon: Icons.add_rounded,
          onPressed: () async {
            final draft = await _showAgentKpiEditorDialog(context);
            if (draft == null || !context.mounted) return;
            final controller = context.read<AgentsController>();
            final saved = await controller.saveKpi(currentAgent.id, draft);
            if (saved == null && context.mounted) {
              _showAgentMutationError(
                context,
                controller,
                zh: 'KPI 保存失败，请重试。',
                en: 'Failed to save KPI. Try again.',
              );
            }
          },
          label: _agentsViewAddKpiLabel(context),
        ),
        child: currentAgent.kpis.isEmpty
            ? FeatureStateCard.inline(
                icon: Icons.flag_outlined,
                title: l10n.agentsNoKpiTitle,
                body: l10n.agentsNoKpiBody,
              )
            : _AgentKpiBody(agent: currentAgent, kpis: currentAgent.kpis),
      );
    },
  );
}

class _AgentKpiBody extends StatelessWidget {
  const _AgentKpiBody({required this.agent, required this.kpis});

  final AgentProfile agent;
  final List<AgentKpiItem> kpis;

  @override
  Widget build(BuildContext context) {
    final tracking = kpis
        .where(
          (item) => item.status.trim().toLowerCase() == agentKpiStatusTracking,
        )
        .length;
    final atRisk = kpis
        .where(
          (item) => item.status.trim().toLowerCase() == agentKpiStatusAtRisk,
        )
        .length;
    final done = kpis
        .where((item) => item.status.trim().toLowerCase() == agentKpiStatusDone)
        .length;
    final averageProgress = kpis.isEmpty
        ? 0
        : (kpis.fold<double>(0, (sum, item) => sum + item.progress) /
                  kpis.length *
                  100)
              .round();
    final visibleKpis = sortedAgentKpisForAttention(kpis);
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
              label: _agentsViewTrackingLabel(context),
              value: '$tracking',
            ),
            _MetricTile(
              label: _agentsViewAtRiskLabel(context),
              value: '$atRisk',
            ),
            _MetricTile(label: _agentsViewDoneLabel(context), value: '$done'),
            _MetricTile(
              label: _agentsViewAvgProgressLabel(context),
              value: '$averageProgress%',
            ),
          ],
        ),
        kOpenHandGap14,
        ListView.separated(
          shrinkWrap: true,
          primary: false,
          itemCount: visibleKpis.length,
          separatorBuilder: (_, _) => kOpenHandGap10,
          itemBuilder: (context, index) {
            return _AgentKpiCard(agent: agent, item: visibleKpis[index]);
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
        : formatMonthDayHmLocal(item.updatedAt!);
    final metadata = _agentKpiMetadataChips(context, item);
    final progress = clampUnitInterval(item.progress);

    return DecoratedBox(
      decoration: _agentListCardDecoration(
        cs,
        borderRadius: kOpenHandBorderRadius12,
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
                borderRadius: kOpenHandBorderRadius10,
              ),
              alignment: Alignment.center,
              child: Icon(
                _agentKpiStatusIcon(item.status),
                color: statusColor,
                size: 19,
              ),
            ),
            kOpenHandHGap12,
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
                  kOpenHandGap8,
                  Text(
                    item.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (item.target.trim().isNotEmpty) ...[
                    kOpenHandGap5,
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
                    kOpenHandGap5,
                    Text(
                      item.plan,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
                    ),
                  ],
                  kOpenHandGap10,
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: kOpenHandPillBorderRadius,
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 7,
                            color: statusColor,
                            backgroundColor: cs.surfaceContainerHighest,
                          ),
                        ),
                      ),
                      kOpenHandHGap10,
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
                    kOpenHandGap9,
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
            kOpenHandHGap12,
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AgentSmallIconButton(
                  icon: Icons.edit_rounded,
                  tooltip: _agentsViewEditKpiLabel(context),
                  onPressed: () => _editAgentKpi(context, agent, item),
                ),
                kOpenHandHGap6,
                _AgentSmallIconButton(
                  icon: Icons.delete_outline_rounded,
                  tooltip: _agentsViewDeleteKpiLabel(context),
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
  final controller = context.read<AgentsController>();
  final saved = await controller.saveKpi(agent.id, draft);
  if (saved == null && context.mounted) {
    _showAgentMutationError(
      context,
      controller,
      zh: 'KPI 保存失败，请重试。',
      en: 'Failed to save KPI. Try again.',
    );
  }
}

Future<void> _deleteAgentKpi(
  BuildContext context,
  AgentProfile agent,
  AgentKpiItem item,
) async {
  final confirmed = await showOpenHandConfirmDialog(
    context: context,
    title: _agentsViewDeleteKpiLabel(context),
    message: openHandLocalizedText(
      context,
      zh: '确认删除「${item.name}」吗？',
      en: 'Delete "${item.name}"?',
    ),
    confirmLabel: openHandDeleteLabel(context),
    destructive: true,
  );
  if (confirmed && context.mounted) {
    final controller = context.read<AgentsController>();
    final deleted = await controller.deleteKpi(agent.id, item.id);
    if (!deleted && context.mounted) {
      _showAgentMutationError(
        context,
        controller,
        zh: 'KPI 删除失败，请刷新后重试。',
        en: 'Failed to delete KPI. Refresh and try again.',
      );
    }
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
    _progress = clampUnitInterval(initial?.progress ?? 0);
    _status = agentKpiStatusOptions.contains(initial?.status)
        ? initial!.status
        : agentKpiStatusOptions.first;
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
      maxWidth: kOpenHandDialogWidthStandard,
      child: _AgentDialogScaffold(
        icon: Icons.flag_rounded,
        title: widget.initial == null
            ? _agentsViewAddKpiLabel(context)
            : _agentsViewEditKpiLabel(context),
        footer: _agentDialogActionsFooter(
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
              maxLength: _agentStructuredFieldKeyMaxChars,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              buildCounter: openHandHiddenTextFieldCounter,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: l10n.agentsFieldName),
            ),
            kOpenHandGap12,
            TextField(
              controller: _target,
              maxLength: _agentStructuredFieldValueMaxChars,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              buildCounter: openHandHiddenTextFieldCounter,
              decoration: InputDecoration(labelText: l10n.agentsFieldTarget),
            ),
            kOpenHandGap12,
            TextField(
              controller: _plan,
              maxLength: _agentStructuredFieldValueMaxChars,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              buildCounter: openHandHiddenTextFieldCounter,
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
            kOpenHandGap12,
            AnimatedDropdownButtonFormField<String>(
              initialValue: _status,
              decoration: InputDecoration(
                labelText: openHandStatusLabel(context),
              ),
              items: [
                for (final value in agentKpiStatusOptions)
                  DropdownMenuItem(
                    value: value,
                    child: Text(_agentKpiStatusLabel(context, value)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _status = value);
              },
            ),
            kOpenHandGap12,
            InputDecorator(
              decoration: InputDecoration(
                labelText: _agentsViewProgressLabel(context),
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
            kOpenHandGap12,
            _AgentKeyValueEditor(
              title: openHandLocalizedText(
                context,
                zh: 'KPI 元数据',
                en: 'KPI metadata',
              ),
              entries: _extraEntries,
              keyLabel: _agentsViewKeyLabel(context),
              valueLabel: _agentsViewValueLabel(context),
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
    if (_name.text.length > _agentStructuredFieldKeyMaxChars ||
        _target.text.length > _agentStructuredFieldValueMaxChars ||
        _plan.text.length > _agentStructuredFieldValueMaxChars) {
      _showAgentErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: 'KPI 文本超过长度限制。',
          en: 'KPI text exceeds the length limit.',
        ),
      );
      return;
    }
    final duplicate = _agentFirstDuplicateKey(_extraEntries);
    if (duplicate != null) {
      _showAgentErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: 'KPI 元数据字段重复：$duplicate',
          en: 'Duplicate KPI metadata field: $duplicate',
        ),
      );
      return;
    }
    if (!_agentStructuredFieldsWithinLimits(_extraEntries)) {
      _showAgentErrorSnack(
        context,
        _agentStructuredFieldsLimitMessage(
          context,
          zhSubject: 'KPI 元数据',
          enSubject: 'KPI metadata',
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
      progress: clampUnitInterval(_progress),
      status: _status,
      createdAt: initial?.createdAt,
      extra: _agentKeyValueDraftMapFromEntries(_extraEntries),
    );
  }
}

String _agentKpiStatusLabel(BuildContext context, String status) {
  return switch (status.trim().toLowerCase()) {
    agentKpiStatusDone => _agentsViewDoneLabel(context),
    agentKpiStatusAtRisk => _agentsViewAtRiskLabel(context),
    agentKpiStatusPaused => _agentsViewPausedLabel(context),
    _ => _agentsViewTrackingLabel(context),
  };
}

IconData _agentKpiStatusIcon(String status) {
  return switch (status.trim().toLowerCase()) {
    agentKpiStatusDone => Icons.check_circle_rounded,
    agentKpiStatusAtRisk => Icons.warning_amber_rounded,
    agentKpiStatusPaused => Icons.pause_circle_outline_rounded,
    _ => Icons.flag_rounded,
  };
}

Color _agentKpiStatusColor(ColorScheme cs, String status) {
  return switch (status.trim().toLowerCase()) {
    agentKpiStatusDone => cs.tertiary,
    agentKpiStatusAtRisk => cs.error,
    agentKpiStatusPaused => cs.onSurfaceVariant,
    _ => cs.primary,
  };
}

List<String> _agentKpiMetadataChips(BuildContext context, AgentKpiItem item) {
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
    final text = _agentMetadataChipText(context, key, item.extra[key]);
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
        return buildOpenHandResponsiveDialogShell(
          context: context,
          maxWidth: kOpenHandDialogWidthPanel,
          maxHeight: kOpenHandDialogHeightTall,
          maxWidthFraction: _agentTaskDetailMaxWidthFraction,
          maxHeightFraction: _agentTaskDetailMaxHeightFraction,
          horizontalMargin: _agentTaskDetailHorizontalMargin,
          verticalMargin: 56,
          minAvailableWidth: _agentTaskDetailMinAvailableWidth,
          child: _AgentDialogScaffold(
            icon: Icons.storage_rounded,
            title: l10n.agentsDialogTitleWithName(
              l10n.agentsResources,
              currentAgent.name,
            ),
            footer: _agentDialogActionsFooter(
              actions: [
                OpenHandDialogActionButton.secondary(
                  icon: Icons.sync_rounded,
                  onPressed: () {
                    unawaited(
                      context.read<AgentsController>().sampleResourceUsage(
                        currentAgent.id,
                      ),
                    );
                  },
                  label: openHandLocalizedText(
                    context,
                    zh: '立即采样',
                    en: 'Sample now',
                  ),
                ),
                OpenHandDialogActionButton.primary(
                  icon: Icons.edit_rounded,
                  onPressed: () async {
                    final updated = await _showAgentResourceEditorDialog(
                      context,
                      resource,
                    );
                    if (updated == null || !context.mounted) return;
                    final controller = context.read<AgentsController>();
                    final saved = await controller.saveResourceUsage(
                      currentAgent.id,
                      updated,
                    );
                    if (!saved && context.mounted) {
                      _showAgentMutationError(
                        context,
                        controller,
                        zh: '资源数据保存失败，请重试。',
                        en: 'Failed to save resource data. Try again.',
                      );
                    }
                  },
                  label: _agentsViewEditResourcesLabel(context),
                ),
              ],
            ),
            child: _AgentResourceLiveBody(agent: currentAgent),
          ),
        );
      },
    ),
  );
}

class _AgentResourceLiveBody extends StatefulWidget {
  const _AgentResourceLiveBody({required this.agent});

  final AgentProfile agent;

  @override
  State<_AgentResourceLiveBody> createState() => _AgentResourceLiveBodyState();
}

class _AgentResourceLiveBodyState extends State<_AgentResourceLiveBody> {
  Timer? _sampleTimer;
  bool _sampleInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_sampleNow()),
    );
    _sampleTimer = startNonOverlappingPeriodicTimer(
      _agentResourceSampleInterval,
      (_) => _sampleNow(),
      onError: (error, stack) => silentLog('agents', '采样资源用量定时器', error, stack),
    );
  }

  @override
  void dispose() {
    _sampleTimer?.cancel();
    super.dispose();
  }

  Future<void> _sampleNow() async {
    if (!mounted || _sampleInFlight) return;
    _sampleInFlight = true;
    try {
      await context
          .read<AgentsController>()
          .sampleResourceUsage(widget.agent.id)
          .timeout(_agentResourceSampleTimeout);
    } catch (error, stack) {
      silentLog('agents', '采样资源用量', error, stack);
    } finally {
      _sampleInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _AgentResourceLiveData.fromAgent(widget.agent);
    return _AgentTaskDetailSectionList(
      children: [
        _AgentResourceLiveSummary(data: data),
        _AgentResourceCharts(data: data),
        _AgentResourceBody(resource: data.resource),
      ],
    );
  }
}

class _AgentResourceLiveData {
  _AgentResourceLiveData({
    required this.resource,
    required this.samples,
    required this.sampledAt,
    required this.cpu,
    required this.tokenPressure,
    required this.persistedPressure,
    required this.handlePressure,
    required this.maxPressure,
    required this.taskCount,
    required this.activeTasks,
    required this.busyWorkers,
    required this.pendingApprovals,
    required this.workerCount,
  });

  factory _AgentResourceLiveData.fromAgent(AgentProfile agent) {
    final resource = agent.resourceUsage;
    final telemetry = _agentResourceTelemetry(resource);
    final samples = _agentResourceSamples(resource);
    final cpu = clampUnitInterval(resource.cpuPercent);
    final token = unitRatio(resource.tokenUsed, resource.tokenBudget);
    final persisted = unitRatio(resource.persistedBytes, resource.diskBytes);
    final handles = unitRatio(
      resource.openHandles,
      agentResourceOpenHandlePressureLimit,
    );
    return _AgentResourceLiveData(
      resource: resource,
      samples: samples,
      sampledAt:
          _agentResourceDateTime(telemetry['sampled_at']) ??
          (samples.isEmpty ? null : samples.last.sampledAt),
      cpu: cpu,
      tokenPressure: token,
      persistedPressure: persisted,
      handlePressure: handles,
      maxPressure: [cpu, token, persisted, handles].reduce(math.max),
      taskCount: nonNegativeIntFromValue(
        resource.extra['task_count'],
        fallback: agent.tasks.length,
      ),
      activeTasks: nonNegativeIntFromValue(
        resource.extra['active_task_count'],
        fallback: agent.tasks
            .where(
              (task) =>
                  task.status != AgentTaskStatus.completed &&
                  task.status != AgentTaskStatus.failed &&
                  task.status != AgentTaskStatus.canceled,
            )
            .length,
      ),
      busyWorkers: nonNegativeIntFromValue(
        resource.extra['busy_workers'],
        fallback: agent.workers
            .where((worker) => worker.status == AgentWorkerStatus.busy)
            .length,
      ),
      pendingApprovals: nonNegativeIntFromValue(
        resource.extra['pending_approvals'],
        fallback: agent.approvals
            .where((item) => item.status == AgentApprovalStatus.pending)
            .length,
      ),
      workerCount: agent.workers.length,
    );
  }

  final AgentResourceUsage resource;
  final List<_AgentResourceSample> samples;
  final DateTime? sampledAt;
  final double cpu;
  final double tokenPressure;
  final double persistedPressure;
  final double handlePressure;
  final double maxPressure;
  final int taskCount;
  final int activeTasks;
  final int busyWorkers;
  final int pendingApprovals;
  final int workerCount;
}

class _AgentResourceSample {
  const _AgentResourceSample({
    required this.sampledAt,
    required this.cpu,
    required this.tokenPressure,
    required this.persistedPressure,
    required this.handlePressure,
  });

  final DateTime sampledAt;
  final double cpu;
  final double tokenPressure;
  final double persistedPressure;
  final double handlePressure;
}

class _AgentResourceLiveSummary extends StatelessWidget {
  const _AgentResourceLiveSummary({required this.data});

  final _AgentResourceLiveData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final settings = _agentDialogAnimationSettings(context);
    final color = _agentResourcePressureColor(cs, data.maxPressure);
    final sampled = data.sampledAt == null
        ? openHandLocalizedText(context, zh: '等待采样', en: 'Waiting')
        : formatMonthDayHmsLocal(data.sampledAt!);
    final pressureText = _agentResourcePercentLabel(data.maxPressure);
    final inlineSummary = _agentResourceInlineSummary(context, data);
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _AgentActivityTypeChip(
              label: _agentResourcePressureLabel(context, data.maxPressure),
              color: color,
            ),
            _AgentActivityMetadataChip(text: sampled),
            _AgentActivityMetadataChip(
              text: openHandLocalizedText(
                context,
                zh: '${data.samples.length} 个趋势点',
                en: '${data.samples.length} trend points',
              ),
            ),
          ],
        ),
        kOpenHandGap10,
        Text(
          openHandLocalizedText(context, zh: '资源运行态势', en: 'Resource posture'),
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        kOpenHandGap7,
        AnimatedSwitcher(
          duration: settings.entranceDuration,
          reverseDuration: settings.exitDuration,
          transitionBuilder: (child, animation) => _agentDialogSwitchTransition(
            settings: settings,
            animation: animation,
            child: child,
          ),
          child: Text(
            inlineSummary,
            key: ValueKey<String>(inlineSummary),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.35,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
    final dial = SizedBox.square(
      dimension: 116,
      child: Stack(
        fit: StackFit.expand,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween<double>(end: data.maxPressure),
            duration: settings.duration,
            curve: settings.curve.curve,
            builder: (context, value, _) {
              return CircularProgressIndicator(
                value: value,
                strokeWidth: 10,
                color: color,
                backgroundColor: cs.surfaceContainerHighest,
                strokeCap: StrokeCap.round,
              );
            },
          ),
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: settings.entranceDuration,
              reverseDuration: settings.exitDuration,
              layoutBuilder: (currentChild, previousChildren) => Stack(
                alignment: Alignment.center,
                children: [
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              ),
              transitionBuilder: (child, animation) =>
                  buildAnimationStyleTransition(
                    animation: animation,
                    settings: settings,
                    child: child,
                  ),
              child: Center(
                key: ValueKey<String>(pressureText),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    pressureText,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w900,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return AnimatedContainer(
      duration: settings.duration,
      curve: settings.curve.curve,
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: 0.08),
          cs.surfaceContainerHighest.withValues(alpha: 0.46),
        ),
        borderRadius: BorderRadius.circular(kOpenHandRadius20),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxWidth < _agentResourceOverviewBreakpoint;
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: dial),
                  kOpenHandGap14,
                  details,
                ],
              );
            }
            return Row(
              children: [
                dial,
                kOpenHandHGap16,
                Expanded(child: details),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AgentResourceCharts extends StatelessWidget {
  const _AgentResourceCharts({required this.data});

  final _AgentResourceLiveData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final settings = _agentDialogAnimationSettings(context);
    final values = _agentResourceRenderablePressures(
      data.samples,
      data.maxPressure,
    );
    final peak = values.reduce(math.max);
    final average = _agentResourceAverage(values);
    final cpuColor = _agentResourcePressureColor(cs, data.cpu);
    final tokenColor = cs.secondary;
    final storageColor = _agentResourcePressureColor(
      cs,
      data.persistedPressure,
    );
    final handleColor = cs.tertiary;
    final segments = <_AgentResourceBreakdownSegment>[
      _AgentResourceBreakdownSegment(
        label: 'CPU',
        value: data.cpu,
        color: cpuColor,
        icon: Icons.memory_rounded,
      ),
      _AgentResourceBreakdownSegment(
        label: 'Token',
        value: data.tokenPressure,
        color: tokenColor,
        icon: Icons.auto_awesome_rounded,
      ),
      _AgentResourceBreakdownSegment(
        label: openHandLocalizedText(context, zh: '持久化', en: 'Storage'),
        value: data.persistedPressure,
        color: storageColor,
        icon: Icons.inventory_2_rounded,
      ),
      _AgentResourceBreakdownSegment(
        label: openHandLocalizedText(context, zh: '句柄', en: 'Handles'),
        value: data.handlePressure,
        color: handleColor,
        icon: Icons.hub_outlined,
      ),
    ];
    final trendPanel = _AgentResourceChartPanel(
      title: openHandLocalizedText(context, zh: '压力趋势', en: 'Pressure trend'),
      icon: Icons.show_chart_rounded,
      trailing: _AgentActivityMetadataChip(
        text: openHandLocalizedText(
          context,
          zh: '${values.length} 点',
          en: '${values.length} points',
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: _agentResourceChartHeight,
            child: CustomPaint(
              painter: _AgentResourcePressureTrendPainter(
                values: values,
                color: cs.primary,
                gridColor: cs.outlineVariant.withValues(alpha: 0.62),
                fillColor: cs.primary.withValues(alpha: 0.10),
              ),
            ),
          ),
          kOpenHandGap10,
          DefaultTextStyle.merge(
            style: theme.textTheme.labelMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    openHandLocalizedText(
                      context,
                      zh: '峰值 ${_agentResourcePercentLabel(peak)}',
                      en: 'Peak ${_agentResourcePercentLabel(peak)}',
                    ),
                  ),
                ),
                Text(
                  openHandLocalizedText(
                    context,
                    zh: '均值 ${_agentResourcePercentLabel(average)}',
                    en: 'Avg ${_agentResourcePercentLabel(average)}',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    final donutPanel = _AgentResourceChartPanel(
      title: openHandLocalizedText(context, zh: '压力占比', en: 'Pressure mix'),
      icon: Icons.donut_large_rounded,
      trailing: _AgentActivityTypeChip(
        label: _agentResourcePressureLabel(context, data.maxPressure),
        color: _agentResourcePressureColor(cs, data.maxPressure),
      ),
      child: Column(
        children: [
          SizedBox.square(
            dimension: _agentResourceDonutSize,
            child: Stack(
              fit: StackFit.expand,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: 1),
                  duration: settings.duration,
                  curve: settings.curve.curve,
                  builder: (context, value, _) {
                    return CustomPaint(
                      painter: _AgentResourcePressureDonutPainter(
                        segments: segments,
                        trackColor: cs.surfaceContainerHighest,
                        progress: value,
                      ),
                    );
                  },
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _agentResourcePercentLabel(data.maxPressure),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        openHandLocalizedText(context, zh: '峰值', en: 'Peak'),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          kOpenHandGap12,
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              for (final segment in segments)
                _AgentResourceLegendItem(segment: segment),
            ],
          ),
        ],
      ),
    );
    return AnimatedContainer(
      duration: settings.duration,
      curve: settings.curve.curve,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(_agentResourcePanelRadius),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.86)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final wide =
                    constraints.maxWidth >= _agentResourceOverviewBreakpoint;
                if (!wide) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      trendPanel,
                      const SizedBox(height: _agentDialogMetricGap),
                      donutPanel,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: trendPanel),
                    const SizedBox(width: _agentDialogMetricGap),
                    SizedBox(width: 252, child: donutPanel),
                  ],
                );
              },
            ),
            kOpenHandGap14,
            _AgentDialogMetricGrid(
              children: [
                _AgentDialogMetricTile(
                  icon: Icons.memory_rounded,
                  label: 'CPU',
                  value: _agentResourcePercentLabel(data.cpu),
                  color: cpuColor,
                  progress: data.cpu,
                ),
                _AgentDialogMetricTile(
                  icon: Icons.auto_awesome_rounded,
                  label: openHandLocalizedText(
                    context,
                    zh: 'Token 压力',
                    en: 'Token pressure',
                  ),
                  value: data.resource.tokenBudget <= 0
                      ? openHandLocalizedText(
                          context,
                          zh: '${data.resource.tokenUsed} / 未设',
                          en: '${data.resource.tokenUsed} / unset',
                        )
                      : '${data.resource.tokenUsed}/${data.resource.tokenBudget}',
                  color: tokenColor,
                  progress: data.tokenPressure,
                ),
                _AgentDialogMetricTile(
                  icon: Icons.inventory_2_rounded,
                  label: openHandLocalizedText(
                    context,
                    zh: '持久化压力',
                    en: 'Storage pressure',
                  ),
                  value: data.resource.diskBytes <= 0
                      ? _agentsViewUnsetLabel(context)
                      : '${formatByteSize(data.resource.persistedBytes)} / ${formatByteSize(data.resource.diskBytes)}',
                  color: storageColor,
                  progress: data.persistedPressure,
                ),
                _AgentDialogMetricTile(
                  icon: Icons.hub_outlined,
                  label: openHandLocalizedText(
                    context,
                    zh: '句柄压力',
                    en: 'Handle pressure',
                  ),
                  value:
                      '${data.resource.openHandles}/$agentResourceOpenHandlePressureLimit',
                  color: handleColor,
                  progress: data.handlePressure,
                ),
                _AgentDialogMetricTile(
                  icon: Icons.task_alt_rounded,
                  label: openHandLocalizedText(
                    context,
                    zh: '活动任务',
                    en: 'Active tasks',
                  ),
                  value: '${data.activeTasks}/${data.taskCount}',
                ),
                _AgentDialogMetricTile(
                  icon: Icons.precision_manufacturing_rounded,
                  label: _agentsViewBusyWorkersLabel(context),
                  value: '${data.busyWorkers}/${data.workerCount}',
                ),
                _AgentDialogMetricTile(
                  icon: Icons.verified_user_outlined,
                  label: openHandLocalizedText(
                    context,
                    zh: '待审批',
                    en: 'Pending approvals',
                  ),
                  value: '${data.pendingApprovals}',
                ),
                _AgentDialogMetricTile(
                  icon: Icons.history_rounded,
                  label: openHandLocalizedText(
                    context,
                    zh: '采样点',
                    en: 'Samples',
                  ),
                  value: '${data.samples.length}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentResourceChartPanel extends StatelessWidget {
  const _AgentResourceChartPanel({
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
    final cs = theme.colorScheme;
    final settings = _agentDialogAnimationSettings(context);
    return AnimatedContainer(
      duration: settings.duration,
      curve: settings.curve.curve,
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(_agentResourcePanelRadius),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.72)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: cs.primary),
              kOpenHandHGap8,
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (trailing != null) ...[kOpenHandHGap8, trailing!],
            ],
          ),
          kOpenHandGap12,
          child,
        ],
      ),
    );
  }
}

class _AgentResourceLegendItem extends StatelessWidget {
  const _AgentResourceLegendItem({required this.segment});

  final _AgentResourceBreakdownSegment segment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 112, maxWidth: 132),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(segment.icon, size: 16, color: segment.color),
          kOpenHandHGap6,
          Expanded(
            child: Text(
              segment.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          kOpenHandHGap6,
          Text(
            _agentResourcePercentLabel(segment.value),
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentResourceBreakdownSegment {
  const _AgentResourceBreakdownSegment({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final double value;
  final Color color;
  final IconData icon;
}

class _AgentResourceBody extends StatelessWidget {
  const _AgentResourceBody({required this.resource});

  final AgentResourceUsage resource;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cpu = clampUnitInterval(resource.cpuPercent);
    final tokenPressure = unitRatio(resource.tokenUsed, resource.tokenBudget);
    final persistedPressure = unitRatio(
      resource.persistedBytes,
      resource.diskBytes,
    );
    final handlePressure = unitRatio(
      resource.openHandles,
      agentResourceOpenHandlePressureLimit,
    );
    final maxPressure = [
      cpu,
      tokenPressure,
      persistedPressure,
      handlePressure,
    ].reduce(math.max);
    final metadata = _agentResourceMetadataChips(context, resource);
    final remainingTokens = nonNegativeRemaining(
      resource.tokenBudget,
      resource.tokenUsed,
    );
    final remainingPersistedBytes = nonNegativeRemaining(
      resource.diskBytes,
      resource.persistedBytes,
    );
    final persistedCapacityLabel = resource.diskBytes <= 0
        ? _agentsViewUnsetLabel(context)
        : formatByteSize(resource.diskBytes);
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
            if (resource.tokenBudget > 0)
              _MetricTile(
                label: openHandLocalizedText(
                  context,
                  zh: '剩余 Token',
                  en: 'Token left',
                ),
                value: '$remainingTokens',
              ),
            _MetricTile(
              label: l10n.agentsMetricHandles,
              value: '${resource.openHandles}',
            ),
            if (resource.diskBytes > 0)
              _MetricTile(
                label: openHandLocalizedText(
                  context,
                  zh: '剩余空间',
                  en: 'Storage left',
                ),
                value: formatByteSize(remainingPersistedBytes),
              ),
          ],
        ),
        kOpenHandGap14,
        _AgentResourcePressureCard(
          icon: Icons.memory_rounded,
          label: 'CPU',
          valueLabel: '${(cpu * 100).round()}%',
          pressure: cpu,
        ),
        kOpenHandGap10,
        _AgentResourcePressureCard(
          icon: Icons.auto_awesome_rounded,
          label: openHandTokenBudgetLabel(context),
          valueLabel: resource.tokenBudget <= 0
              ? openHandLocalizedText(
                  context,
                  zh: '${resource.tokenUsed} / 未设置',
                  en: '${resource.tokenUsed} / unset',
                )
              : '${resource.tokenUsed} / ${resource.tokenBudget}',
          pressure: tokenPressure,
        ),
        kOpenHandGap10,
        _AgentResourcePressureCard(
          icon: Icons.inventory_2_rounded,
          label: _agentsViewPersistedStorageLabel(context),
          valueLabel:
              '${formatByteSize(resource.persistedBytes)} / $persistedCapacityLabel',
          pressure: persistedPressure,
        ),
        kOpenHandGap10,
        _AgentResourcePressureCard(
          icon: Icons.hub_outlined,
          label: l10n.agentsMetricHandles,
          valueLabel:
              '${resource.openHandles} / $agentResourceOpenHandlePressureLimit',
          pressure: handlePressure,
        ),
        kOpenHandGap14,
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
          kOpenHandGap14,
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
    final normalized = clampUnitInterval(pressure);
    final color = _agentResourcePressureColor(cs, normalized);
    final settings = _agentDialogAnimationSettings(context);
    return AnimatedContainer(
      duration: settings.duration,
      curve: settings.curve.curve,
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: 0.045),
          cs.surfaceContainerHighest.withValues(alpha: 0.42),
        ),
        borderRadius: kOpenHandBorderRadius12,
        border: Border.all(color: color.withValues(alpha: 0.20)),
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
                borderRadius: kOpenHandBorderRadius10,
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: color, size: 19),
            ),
            kOpenHandHGap12,
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
                  kOpenHandGap8,
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final availableWidth = constraints.maxWidth.isFinite
                          ? constraints.maxWidth
                          : _agentResourcePressureCardCompactBreakpoint;
                      final compact =
                          availableWidth <
                          _agentResourcePressureCardCompactBreakpoint;
                      final progressBar = ClipRRect(
                        borderRadius: kOpenHandPillBorderRadius,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: normalized),
                          duration: settings.duration,
                          curve: settings.curve.curve,
                          builder: (context, value, _) {
                            return LinearProgressIndicator(
                              value: value,
                              minHeight: _agentResourcePressureBarHeight,
                              color: color,
                              backgroundColor: cs.outlineVariant.withValues(
                                alpha: 0.42,
                              ),
                            );
                          },
                        ),
                      );
                      final valueText = AnimatedSwitcher(
                        duration: settings.entranceDuration,
                        reverseDuration: settings.exitDuration,
                        transitionBuilder: (child, animation) =>
                            _agentDialogSwitchTransition(
                              settings: settings,
                              animation: animation,
                              child: child,
                            ),
                        child: Align(
                          key: ValueKey<String>(valueLabel),
                          alignment: AlignmentDirectional.centerEnd,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerEnd,
                            child: Text(
                              valueLabel,
                              maxLines: 1,
                              softWrap: false,
                              textAlign: TextAlign.end,
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                      if (compact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [progressBar, kOpenHandGap7, valueText],
                        );
                      }
                      final valueWidth = _agentResourcePressureValueWidth(
                        valueLabel,
                        maxWidth: availableWidth * 0.42,
                      );
                      return Row(
                        children: [
                          Expanded(child: progressBar),
                          kOpenHandHGap14,
                          SizedBox(width: valueWidth, child: valueText),
                        ],
                      );
                    },
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

class _AgentResourcePressureTrendPainter extends CustomPainter {
  const _AgentResourcePressureTrendPainter({
    required this.values,
    required this.color,
    required this.gridColor,
    required this.fillColor,
  });

  final List<double> values;
  final Color color;
  final Color gridColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || values.isEmpty) return;
    final chart = Rect.fromLTWH(2, 2, size.width - 4, size.height - 4);
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = chart.top + chart.height * i / 4;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
    }

    final points = <Offset>[
      for (var i = 0; i < values.length; i++)
        Offset(
          values.length == 1
              ? chart.center.dx
              : chart.left + chart.width * i / (values.length - 1),
          chart.bottom - chart.height * clampUnitInterval(values[i]),
        ),
    ];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final current = points[i];
      final controlX = (previous.dx + current.dx) / 2;
      path.cubicTo(
        controlX,
        previous.dy,
        controlX,
        current.dy,
        current.dx,
        current.dy,
      );
    }

    final fillPath = Path.from(path)
      ..lineTo(points.last.dx, chart.bottom)
      ..lineTo(points.first.dx, chart.bottom)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 3,
    );
    canvas.drawCircle(points.last, 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _AgentResourcePressureTrendPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.color != color ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.fillColor != fillColor;
  }
}

class _AgentResourcePressureDonutPainter extends CustomPainter {
  const _AgentResourcePressureDonutPainter({
    required this.segments,
    required this.trackColor,
    required this.progress,
  });

  final List<_AgentResourceBreakdownSegment> segments;
  final Color trackColor;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final strokeWidth = math.max<double>(
      10,
      math.min<double>(size.shortestSide * 0.09, 16),
    );
    final arcRect = (Offset.zero & size).deflate(strokeWidth / 2);
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arcRect, -math.pi / 2, math.pi * 2, false, trackPaint);

    final total = segments.fold<double>(
      0,
      (sum, segment) => sum + clampUnitInterval(segment.value),
    );
    if (total <= 0) return;

    final animatedProgress = clampUnitInterval(progress);
    final gap = segments.length > 1 ? 0.028 : 0.0;
    var start = -math.pi / 2;
    for (final segment in segments) {
      final value = clampUnitInterval(segment.value);
      if (value <= 0) continue;
      final rawSweep = math.pi * 2 * value / total * animatedProgress;
      final sweep = math.max<double>(0, rawSweep - gap);
      canvas.drawArc(
        arcRect,
        start,
        sweep,
        false,
        Paint()
          ..color = segment.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );
      start += rawSweep;
    }
  }

  @override
  bool shouldRepaint(covariant _AgentResourcePressureDonutPainter oldDelegate) {
    return oldDelegate.segments != segments ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.progress != progress;
  }
}

Map<String, Object?> _agentResourceTelemetry(AgentResourceUsage resource) {
  return stringKeyedMapFromValue(
    resource.extra[_agentResourceTelemetryExtraKey],
  );
}

List<_AgentResourceSample> _agentResourceSamples(AgentResourceUsage resource) {
  final now = DateTime.now();
  final telemetry = _agentResourceTelemetry(resource);
  final history = stringKeyedMapListFromValue(
    telemetry[_agentResourceTelemetryHistoryKey],
  );
  final samples = <_AgentResourceSample>[
    for (final item in history)
      _AgentResourceSample(
        sampledAt: _agentResourceDateTime(item['sampled_at']) ?? now,
        cpu: clampUnitInterval(
          optionalDoubleFromValue(item['cpu_percent']) ?? 0,
        ),
        tokenPressure: unitRatio(
          nonNegativeIntFromValue(item['token_used'], fallback: 0),
          nonNegativeIntFromValue(item['token_budget'], fallback: 0),
        ),
        persistedPressure: unitRatio(
          nonNegativeIntFromValue(item['persisted_bytes'], fallback: 0),
          nonNegativeIntFromValue(item['disk_bytes'], fallback: 0),
        ),
        handlePressure: unitRatio(
          nonNegativeIntFromValue(item['open_handles'], fallback: 0),
          agentResourceOpenHandlePressureLimit,
        ),
      ),
  ];
  final currentSampledAt =
      _agentResourceDateTime(telemetry['sampled_at']) ?? now;
  final current = _AgentResourceSample(
    sampledAt: currentSampledAt,
    cpu: clampUnitInterval(resource.cpuPercent),
    tokenPressure: unitRatio(resource.tokenUsed, resource.tokenBudget),
    persistedPressure: unitRatio(resource.persistedBytes, resource.diskBytes),
    handlePressure: unitRatio(
      resource.openHandles,
      agentResourceOpenHandlePressureLimit,
    ),
  );
  if (samples.isEmpty || samples.last.sampledAt != current.sampledAt) {
    samples.add(current);
  }
  return samples;
}

DateTime? _agentResourceDateTime(Object? value) {
  final text = optionalStringFromValue(value);
  return text == null ? null : DateTime.tryParse(text);
}

List<double> _agentResourceRenderablePressures(
  List<_AgentResourceSample> samples,
  double fallback,
) {
  final values = samples
      .map(
        (sample) => [
          sample.cpu,
          sample.tokenPressure,
          sample.persistedPressure,
          sample.handlePressure,
        ].reduce(math.max),
      )
      .toList(growable: false);
  if (values.length >= 2) return values;
  final value = values.isEmpty ? fallback : values.first;
  return [value, value];
}

String _agentResourceInlineSummary(
  BuildContext context,
  _AgentResourceLiveData data,
) {
  final cpu = _agentResourcePercentLabel(data.cpu);
  final token = _agentResourcePercentLabel(data.tokenPressure);
  final storage = _agentResourcePercentLabel(data.persistedPressure);
  final handles = _agentResourcePercentLabel(data.handlePressure);
  return openHandLocalizedText(
    context,
    zh: 'CPU $cpu · Token $token · 持久化 $storage · 句柄 $handles · 活动任务 ${data.activeTasks}/${data.taskCount}',
    en: 'CPU $cpu · Token $token · Storage $storage · Handles $handles · Active tasks ${data.activeTasks}/${data.taskCount}',
  );
}

String _agentResourcePercentLabel(double value) {
  return '${(clampUnitInterval(value) * 100).round()}%';
}

double _agentResourceAverage(List<double> values) {
  if (values.isEmpty) return 0;
  return values.fold<double>(0, (sum, value) => sum + value) / values.length;
}

double _agentResourcePressureValueWidth(
  String value, {
  required double maxWidth,
}) {
  final estimated =
      value.length * _agentResourcePressureValueCharWidth +
      _agentResourcePressureValuePadding;
  final upperBound = math.max(
    _agentResourcePressureValueMinWidth,
    math.min(_agentResourcePressureValueMaxWidth, maxWidth),
  );
  return estimated
      .clamp(_agentResourcePressureValueMinWidth, upperBound)
      .toDouble();
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

List<String> _agentResourceMetadataChips(
  BuildContext context,
  AgentResourceUsage resource,
) {
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
    final text = _agentMetadataChipText(context, key, resource.extra[key]);
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
    _cpuPercent = clampUnitInterval(initial.cpuPercent);
    _memoryBytes = TextEditingController(text: '${initial.memoryBytes}');
    _diskBytes = TextEditingController(text: '${initial.diskBytes}');
    _persistedBytes = TextEditingController(text: '${initial.persistedBytes}');
    _tokenBudget = TextEditingController(text: '${initial.tokenBudget}');
    _tokenUsed = TextEditingController(text: '${initial.tokenUsed}');
    _openHandles = TextEditingController(text: '${initial.openHandles}');
    _extraEntries = _keyValueEntriesFromMap(initial.publicExtra);
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
      maxWidth: kOpenHandDialogWidthStandard,
      child: _AgentDialogScaffold(
        icon: Icons.storage_rounded,
        title: _agentsViewEditResourcesLabel(context),
        footer: _agentDialogActionsFooter(
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
            _resourceField(_tokenBudget, openHandTokenBudgetLabel(context)),
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
                keyLabel: _agentsViewKeyLabel(context),
                valueLabel: _agentsViewValueLabel(context),
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
        maxLength: _agentMetricInputMaxChars,
        maxLengthEnforcement: MaxLengthEnforcement.enforced,
        buildCounter: openHandHiddenTextFieldCounter,
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
      _showAgentErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '资源元数据字段重复：$duplicate',
          en: 'Duplicate resource metadata field: $duplicate',
        ),
      );
      return;
    }
    if (!_agentStructuredFieldsWithinLimits(_extraEntries)) {
      _showAgentErrorSnack(
        context,
        _agentStructuredFieldsLimitMessage(
          context,
          zhSubject: '资源元数据',
          enSubject: 'Resource metadata',
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
    final settings = _agentDialogAnimationSettings(context);
    return SizedBox(
      width: 160,
      child: AnimatedContainer(
        duration: settings.duration,
        curve: settings.curve.curve,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
          borderRadius: kOpenHandBorderRadius8,
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelMedium),
              kOpenHandGap8,
              AnimatedSwitcher(
                duration: settings.entranceDuration,
                reverseDuration: settings.exitDuration,
                transitionBuilder: (child, animation) =>
                    _agentDialogSwitchTransition(
                      settings: settings,
                      animation: animation,
                      child: child,
                    ),
                child: Text(
                  value,
                  key: ValueKey<String>(value),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge,
                ),
              ),
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
    final cs = Theme.of(context).colorScheme;
    final workerTotal = agent.workers.length;
    final utilization = clampUnitInterval(agent.workerUtilization);
    return _AgentTaskDetailSectionList(
      children: [
        _AgentDialogMetricGrid(
          children: [
            _AgentDialogMetricTile(
              icon: Icons.sync_alt_rounded,
              color: cs.primary,
              label: l10n.agentsAuditRequests,
              value: '${report.requests}',
            ),
            _AgentDialogMetricTile(
              icon: Icons.analytics_outlined,
              color: cs.secondary,
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
            _AgentDialogMetricTile(
              icon: Icons.task_alt_rounded,
              color: cs.tertiary,
              label: l10n.agentsAuditCompleted,
              value: '${agent.completedTaskCount}',
            ),
            _AgentDialogMetricTile(
              icon: Icons.speed_rounded,
              color: _agentPressureColor(cs, utilization),
              label: l10n.agentsAuditUtilization,
              value: '${(agent.workerUtilization * 100).round()}%',
              progress: utilization,
            ),
            _AgentDialogMetricTile(
              icon: Icons.extension_rounded,
              color: cs.primary,
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
            _AgentDialogMetricTile(
              icon: Icons.memory_rounded,
              color: workerTotal == 0 ? cs.outline : cs.secondary,
              label: _agentsViewBusyWorkersLabel(context),
              value: '${report.busyWorkers}/$workerTotal',
            ),
          ],
        ),
        _AgentAuditSectionGrid(
          children: [
            _AgentAuditSection(
              icon: Icons.playlist_add_check_rounded,
              color: cs.primary,
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
            _AgentAuditSection(
              icon: Icons.extension_rounded,
              color: cs.secondary,
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
                    title: _agentAuditSourceLabel(context, item.name),
                    subtitle: [
                      _agentCapabilityTypeLabel(context, item.type),
                      openHandLocalizedText(
                        context,
                        zh: '${item.requests} 请求',
                        en: '${item.requests} requests',
                      ),
                      '${item.tokens} Token',
                    ].join(' · '),
                    trailing: '${item.events}',
                    color: cs.secondary,
                  ),
              ],
            ),
            _AgentAuditSection(
              icon: Icons.memory_rounded,
              color: cs.tertiary,
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
                    color: cs.tertiary,
                  ),
              ],
            ),
            _AgentAuditSection(
              icon: Icons.monitor_heart_outlined,
              color: _agentPressureColor(cs, report.cpuPressure),
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
                  label: openHandTokenBudgetLabel(context),
                  value: report.tokenPressure,
                ),
                _AgentAuditPressureRow(
                  label: _agentsViewPersistedStorageLabel(context),
                  value: report.persistedPressure,
                ),
              ],
            ),
          ],
        ),
        _AgentAuditSection(
          icon: Icons.history_rounded,
          color: cs.primary,
          title: l10n.agentsRecentAuditEvents,
          emptyText: l10n.agentsNoAuditData,
          children: [
            for (final event in recentAgentAuditEvents(
              agent.auditEvents,
              limit: 8,
            ))
              _AgentAuditEventRow(event: event),
          ],
        ),
      ],
    );
  }
}

Color _agentPressureColor(ColorScheme cs, double value) {
  final ratio = clampUnitInterval(value);
  if (ratio >= 0.85) return cs.error;
  if (ratio >= 0.62) return cs.tertiary;
  return cs.primary;
}

Color _agentAuditEventToneColor(ColorScheme cs, AgentAuditEvent event) {
  final kind = event.kind.trim().toLowerCase();
  if (kind.contains('failed') ||
      kind.contains('canceled') ||
      kind.contains('terminated')) {
    return cs.error;
  }
  if (kind.contains('completed') || kind.contains('finished')) {
    return cs.tertiary;
  }
  if (kind.contains('worker') || kind.contains('cluster')) {
    return cs.secondary;
  }
  if (kind.contains('approval')) {
    return cs.tertiary;
  }
  return cs.primary;
}

IconData _agentAuditEventIcon(AgentAuditEvent event) {
  final kind = event.kind.trim().toLowerCase();
  if (kind.contains('failed')) return Icons.error_outline_rounded;
  if (kind.contains('canceled') || kind.contains('terminated')) {
    return Icons.cancel_outlined;
  }
  if (kind.contains('completed') || kind.contains('finished')) {
    return Icons.check_circle_outline_rounded;
  }
  if (kind.contains('worker')) return Icons.engineering_outlined;
  if (kind.contains('cluster')) return Icons.account_tree_rounded;
  if (kind.contains('approval')) return Icons.verified_user_outlined;
  if (kind.contains('task')) return Icons.task_alt_rounded;
  return Icons.bolt_outlined;
}

class _AgentAuditSectionGrid extends StatelessWidget {
  const _AgentAuditSectionGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        if (!maxWidth.isFinite) {
          return _AgentTaskDetailSectionList(children: children);
        }
        final twoColumns = maxWidth >= _agentAuditSectionGridBreakpoint;
        final itemWidth = twoColumns
            ? (maxWidth - _agentAuditSectionGridGap) / 2
            : maxWidth;
        return SizedBox(
          width: double.infinity,
          child: Wrap(
            spacing: _agentAuditSectionGridGap,
            runSpacing: _agentAuditSectionGridGap,
            children: [
              for (final child in children)
                SizedBox(width: math.max(0, itemWidth), child: child),
            ],
          ),
        );
      },
    );
  }
}

class _AgentAuditSection extends StatelessWidget {
  const _AgentAuditSection({
    required this.icon,
    required this.color,
    required this.title,
    required this.emptyText,
    required this.children,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String emptyText;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final settings = _agentDialogAnimationSettings(context);
    return AnimatedContainer(
      duration: settings.duration,
      curve: settings.curve.curve,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(_agentTaskDetailCardRadius),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(kOpenHandRadius11),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 18, color: color),
              ),
              kOpenHandHGap10,
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          kOpenHandGap12,
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
    );
  }
}

class _AgentAuditInsightRow extends StatelessWidget {
  const _AgentAuditInsightRow({
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.color,
  });

  final String title;
  final String subtitle;
  final String trailing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.55),
              borderRadius: kOpenHandPillBorderRadius,
            ),
          ),
          kOpenHandHGap10,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                kOpenHandGap3,
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          kOpenHandHGap10,
          DecoratedBox(
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: kOpenHandPillBorderRadius,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Text(
                trailing,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentAuditEventRow extends StatelessWidget {
  const _AgentAuditEventRow({required this.event});

  final AgentAuditEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final color = _agentAuditEventToneColor(cs, event);
    final source = event.toolName.isEmpty
        ? _agentActivityKindLabel(l10n, event.kind)
        : _agentAuditSourceLabel(context, event.toolName);
    final created = event.createdAt == null
        ? ''
        : formatMonthDayHmLocal(event.createdAt!);
    final metadata = <String>[
      source,
      if (event.requestCount > 0)
        openHandLocalizedText(
          context,
          zh: '${event.requestCount} 请求',
          en: '${event.requestCount} requests',
        ),
      if (event.tokenUsage > 0) '${event.tokenUsage} Token',
      if (created.isNotEmpty) created,
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surface.withValues(alpha: 0.48),
          borderRadius: BorderRadius.circular(kOpenHandRadius14),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: _agentAuditEventIconExtent,
                height: _agentAuditEventIconExtent,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13),
                  borderRadius: kOpenHandBorderRadius12,
                ),
                alignment: Alignment.center,
                child: Icon(
                  _agentAuditEventIcon(event),
                  color: color,
                  size: 20,
                ),
              ),
              kOpenHandHGap12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _agentAuditSummaryText(context, event),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    kOpenHandGap7,
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
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
    final normalized = clampUnitInterval(ratio);
    final percent = (normalized * 100).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '$count · $percent%',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          kOpenHandGap7,
          LinearProgressIndicator(
            value: normalized,
            minHeight: 8,
            borderRadius: kOpenHandPillBorderRadius,
            backgroundColor: cs.surfaceContainerHighest,
            color: cs.primary,
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
    final ratio = clampUnitInterval(value);
    final color = _agentPressureColor(cs, ratio);
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              borderRadius: kOpenHandPillBorderRadius,
              color: color,
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ),
          kOpenHandHGap10,
          SizedBox(
            width: 44,
            child: Text(
              '${(ratio * 100).round()}%',
              textAlign: TextAlign.end,
              style: theme.textTheme.labelLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentTaskDetailSectionList extends StatelessWidget {
  const _AgentTaskDetailSectionList({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) const SizedBox(height: _agentTaskDetailSectionGap),
          children[index],
        ],
      ],
    );
  }
}

class _AgentTaskDetailHero extends StatelessWidget {
  const _AgentTaskDetailHero({
    required this.task,
    required this.statusLabel,
    required this.statusColor,
    required this.assignedWorker,
    required this.nextAction,
  });

  final AgentTask task;
  final String statusLabel;
  final Color statusColor;
  final String assignedWorker;
  final String nextAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final settings = _agentDialogAnimationSettings(context);
    final progress = clampUnitInterval(task.progress);
    final progressPercent = (progress * 100).round();
    final title = nonBlankStringOr(task.title, '-');
    final worker = assignedWorker.trim();
    final next = nextAction.trim();
    final borderRadius = BorderRadius.circular(_agentTaskDetailCardRadius);
    final heroColor = Color.alphaBlend(
      statusColor.withValues(alpha: 0.055),
      cs.surfaceContainerHighest.withValues(alpha: 0.30),
    );

    return ClipRRect(
      borderRadius: borderRadius,
      child: AnimatedContainer(
        duration: settings.duration,
        curve: settings.curve.curve,
        decoration: BoxDecoration(
          color: heroColor,
          borderRadius: borderRadius,
          border: Border.all(color: statusColor.withValues(alpha: 0.24)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedContainer(
              duration: settings.duration,
              curve: settings.curve.curve,
              width: _agentTaskDetailHeroRailWidth,
              color: statusColor,
            ),
            Expanded(
              child: Padding(
                padding: _agentTaskDetailHeroPadding,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact =
                        constraints.maxWidth < _agentTaskDetailHeroBreakpoint;
                    final leading = Container(
                      width: _agentTaskDetailHeroIconExtent,
                      height: _agentTaskDetailHeroIconExtent,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(
                          _agentTaskDetailCardRadius,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        _agentTaskStatusIcon(task.status),
                        color: statusColor,
                        size: _agentTaskDetailHeroIconSize,
                      ),
                    );
                    final titleBlock = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _AgentActivityTypeChip(
                              label: statusLabel,
                              color: statusColor,
                            ),
                            if (worker.isNotEmpty)
                              _AgentActivityMetadataChip(text: worker),
                            if (next.isNotEmpty)
                              _AgentActivityMetadataChip(text: next),
                          ],
                        ),
                        kOpenHandGap9,
                        Text(
                          title,
                          maxLines: compact ? 3 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.18,
                          ),
                        ),
                      ],
                    );
                    final progressBlock = SizedBox(
                      width: compact
                          ? double.infinity
                          : _agentTaskDetailHeroProgressWidth,
                      child: Column(
                        crossAxisAlignment: compact
                            ? CrossAxisAlignment.stretch
                            : CrossAxisAlignment.end,
                        children: [
                          Text(
                            openHandLocalizedText(
                              context,
                              zh: '任务进度',
                              en: 'Progress',
                            ),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          kOpenHandGap3,
                          AnimatedSwitcher(
                            duration: settings.entranceDuration,
                            reverseDuration: settings.exitDuration,
                            transitionBuilder: (child, animation) =>
                                _agentDialogSwitchTransition(
                                  settings: settings,
                                  animation: animation,
                                  child: child,
                                ),
                            child: Text(
                              '$progressPercent%',
                              key: ValueKey<int>(progressPercent),
                              textAlign: compact
                                  ? TextAlign.start
                                  : TextAlign.end,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w900,
                                height: 1.08,
                              ),
                            ),
                          ),
                          kOpenHandGap9,
                          TweenAnimationBuilder<double>(
                            tween: Tween<double>(begin: 0, end: progress),
                            duration: settings.duration,
                            curve: settings.curve.curve,
                            builder: (context, value, _) {
                              return LinearProgressIndicator(
                                value: value,
                                minHeight: 6,
                                borderRadius: kOpenHandPillBorderRadius,
                                color: statusColor,
                                backgroundColor: cs.surfaceContainerHighest,
                              );
                            },
                          ),
                        ],
                      ),
                    );
                    if (compact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              leading,
                              kOpenHandHGap12,
                              Expanded(child: titleBlock),
                            ],
                          ),
                          kOpenHandGap14,
                          progressBlock,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        leading,
                        kOpenHandHGap12,
                        Expanded(child: titleBlock),
                        kOpenHandHGap16,
                        progressBlock,
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentTaskDetailFactPanel extends StatelessWidget {
  const _AgentTaskDetailFactPanel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final settings = _agentDialogAnimationSettings(context);
    return AnimatedContainer(
      duration: settings.duration,
      curve: settings.curve.curve,
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          cs.primary.withValues(alpha: 0.025),
          cs.surfaceContainerHighest.withValues(alpha: 0.20),
        ),
        borderRadius: BorderRadius.circular(_agentTaskDetailCardRadius),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.46)),
      ),
      padding: _agentTaskDetailFactPanelPadding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          if (!maxWidth.isFinite) {
            return Wrap(
              spacing: _agentTaskDetailGridGap,
              runSpacing: _agentTaskDetailGridGap,
              children: children,
            );
          }
          final columns = maxWidth >= _agentDialogMetricWideBreakpoint
              ? 3
              : maxWidth >= _agentDialogMetricMediumBreakpoint
              ? 2
              : 1;
          final itemWidth =
              (maxWidth - _agentTaskDetailGridGap * (columns - 1)) / columns;
          return Wrap(
            spacing: _agentTaskDetailGridGap,
            runSpacing: _agentTaskDetailGridGap,
            children: [
              for (final child in children)
                SizedBox(width: math.max(0, itemWidth), child: child),
            ],
          );
        },
      ),
    );
  }
}

class _AgentTaskDetailFact extends StatelessWidget {
  const _AgentTaskDetailFact({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final normalizedValue = nonBlankStringOr(value, '-');
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: _agentTaskDetailFactMinHeight,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: _agentTaskDetailIconExtent,
            height: _agentTaskDetailIconExtent,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(_agentTaskDetailCardRadius),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 17, color: cs.primary),
          ),
          kOpenHandHGap10,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                kOpenHandGap4,
                SelectableText(
                  normalizedValue,
                  maxLines: 2,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700,
                    height: 1.28,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentDialogMetricGrid extends StatelessWidget {
  const _AgentDialogMetricGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        if (!maxWidth.isFinite) {
          return Wrap(
            spacing: _agentDialogMetricGap,
            runSpacing: _agentDialogMetricGap,
            children: children,
          );
        }

        final columns = maxWidth >= _agentDialogMetricWideBreakpoint
            ? 4
            : maxWidth >= _agentDialogMetricMediumBreakpoint
            ? 2
            : 1;
        final tileWidth =
            (maxWidth - _agentDialogMetricGap * (columns - 1)) / columns;
        return SizedBox(
          width: double.infinity,
          child: Wrap(
            spacing: _agentDialogMetricGap,
            runSpacing: _agentDialogMetricGap,
            children: [
              for (final child in children)
                SizedBox(width: math.max(0, tileWidth), child: child),
            ],
          ),
        );
      },
    );
  }
}

class _AgentDialogMetricTile extends StatelessWidget {
  const _AgentDialogMetricTile({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
    this.progress,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? color;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final settings = _agentDialogAnimationSettings(context);
    final tone = color ?? cs.primary;
    final normalizedValue = nonBlankStringOr(value, '-');
    final progressValue = progress;
    final normalizedProgress = progressValue == null
        ? null
        : clampUnitInterval(progressValue);
    return SizedBox(
      width: double.infinity,
      child: AnimatedContainer(
        duration: settings.duration,
        curve: settings.curve.curve,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.54),
          borderRadius: BorderRadius.circular(_agentDialogMetricRadius),
          border: Border.all(color: tone.withValues(alpha: 0.22)),
        ),
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: tone),
                kOpenHandHGap8,
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            kOpenHandGap9,
            AnimatedSwitcher(
              duration: settings.entranceDuration,
              reverseDuration: settings.exitDuration,
              transitionBuilder: (child, animation) =>
                  _agentDialogSwitchTransition(
                    settings: settings,
                    animation: animation,
                    child: child,
                  ),
              child: Text(
                normalizedValue,
                key: ValueKey<String>(normalizedValue),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  height: 1.12,
                ),
              ),
            ),
            if (normalizedProgress != null) ...[
              kOpenHandGap10,
              LinearProgressIndicator(
                value: normalizedProgress,
                minHeight: 7,
                borderRadius: kOpenHandPillBorderRadius,
                color: tone,
                backgroundColor: cs.surfaceContainerHighest,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AgentTaskDetailGrid extends StatelessWidget {
  const _AgentTaskDetailGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        if (!maxWidth.isFinite) {
          return _AgentTaskDetailSectionList(children: children);
        }

        final twoColumns = maxWidth >= _agentTaskDetailGridBreakpoint;
        final cellWidth = twoColumns
            ? (maxWidth - _agentTaskDetailGridGap) / 2
            : maxWidth;
        return SizedBox(
          width: double.infinity,
          child: Wrap(
            spacing: _agentTaskDetailGridGap,
            runSpacing: _agentTaskDetailGridGap,
            children: [
              for (final child in children)
                SizedBox(width: math.max(0, cellWidth), child: child),
            ],
          ),
        );
      },
    );
  }
}

class _AgentTaskDetailBlock extends StatelessWidget {
  const _AgentTaskDetailBlock({
    required this.title,
    required this.body,
    this.icon,
    this.compact = false,
    this.monospace = false,
  });

  final String title;
  final String body;
  final IconData? icon;
  final bool compact;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final value = nonBlankStringOr(body, '-');
    final textStyle =
        (compact ? theme.textTheme.bodyMedium : theme.textTheme.bodyLarge)
            ?.copyWith(
              color: cs.onSurface,
              fontFamily: monospace ? kOpenHandMonospaceFontFamily : null,
              height: compact ? 1.35 : 1.45,
            );
    final settings = _agentDialogAnimationSettings(context);
    final tone = cs.primary;
    return SizedBox(
      width: double.infinity,
      child: AnimatedContainer(
        duration: settings.duration,
        curve: settings.curve.curve,
        constraints: BoxConstraints(
          minHeight: compact ? _agentTaskDetailCompactMinHeight : 0,
        ),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(
            alpha: compact ? 0.24 : 0.28,
          ),
          borderRadius: BorderRadius.circular(_agentTaskDetailCardRadius),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.72)),
        ),
        padding: _agentTaskDetailCardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Container(
                    width: _agentTaskDetailIconExtent,
                    height: _agentTaskDetailIconExtent,
                    decoration: BoxDecoration(
                      color: tone.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(
                        _agentTaskDetailCardRadius,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, size: 17, color: tone),
                  ),
                  kOpenHandHGap10,
                ],
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? 8 : 10),
            SelectableText(value, style: textStyle),
          ],
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
        kOpenHandHGap8,
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
  final draft = await showAnimatedDialog<_AgentApprovalRequestDraft>(
    context: context,
    builder: (_) => const _AgentApprovalRequestDialog(),
  );
  if (draft != null && context.mounted) {
    final controller = context.read<AgentsController>();
    final approval = await controller.requestApproval(
      agent.id,
      title: draft.title,
      reason: draft.reason,
      requestedAction: draft.requestedAction,
      extra: draft.extra,
    );
    if (approval == null && context.mounted) {
      _showAgentMutationError(
        context,
        controller,
        zh: '审批请求保存失败，请重试。',
        en: 'Failed to save the approval request. Try again.',
      );
    }
  }
}

class _AgentApprovalRequestDraft {
  const _AgentApprovalRequestDraft({
    required this.title,
    required this.reason,
    required this.requestedAction,
    required this.extra,
  });

  final String title;
  final String reason;
  final String requestedAction;
  final Map<String, Object?> extra;
}

class _AgentApprovalRequestDialog extends StatefulWidget {
  const _AgentApprovalRequestDialog();

  @override
  State<_AgentApprovalRequestDialog> createState() =>
      _AgentApprovalRequestDialogState();
}

class _AgentApprovalRequestDialogState
    extends State<_AgentApprovalRequestDialog> {
  late final TextEditingController _title;
  late final TextEditingController _reason;
  late final TextEditingController _requestedAction;
  final List<_KeyValueDraft> _extraEntries = <_KeyValueDraft>[];

  @override
  void initState() {
    super.initState();
    _title = TextEditingController();
    _reason = TextEditingController();
    _requestedAction = TextEditingController();
  }

  @override
  void dispose() {
    _title.dispose();
    _reason.dispose();
    _requestedAction.dispose();
    for (final entry in _extraEntries) {
      entry.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return buildOpenHandDialog(
      maxWidth: kOpenHandDialogWidthStandard,
      child: _AgentDialogScaffold(
        icon: Icons.add_moderator_outlined,
        title: _agentsViewRequestApprovalLabel(context),
        footer: _agentDialogActionsFooter(
          actions: [
            OpenHandDialogActionButton.secondary(
              onPressed: () => Navigator.of(context).pop(),
              label: l10n.commonCancel,
            ),
            OpenHandDialogActionButton.primary(
              onPressed: _submit,
              label: openHandLocalizedText(context, zh: '提交', en: 'Submit'),
            ),
          ],
        ),
        child: Column(
          children: [
            TextField(
              controller: _title,
              maxLength: _agentStructuredFieldKeyMaxChars,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              buildCounter: openHandHiddenTextFieldCounter,
              decoration: InputDecoration(labelText: l10n.agentsFieldName),
            ),
            kOpenHandGap12,
            TextField(
              controller: _reason,
              maxLength: _agentStructuredFieldValueMaxChars,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              buildCounter: openHandHiddenTextFieldCounter,
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
            kOpenHandGap12,
            TextField(
              controller: _requestedAction,
              maxLength: _agentStructuredFieldValueMaxChars,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              buildCounter: openHandHiddenTextFieldCounter,
              decoration: InputDecoration(
                labelText: openHandLocalizedText(
                  context,
                  zh: '请求动作',
                  en: 'Requested action',
                ),
              ),
            ),
            kOpenHandGap12,
            _AgentKeyValueEditor(
              title: openHandLocalizedText(
                context,
                zh: '审批元数据',
                en: 'Approval metadata',
              ),
              entries: _extraEntries,
              keyLabel: _agentsViewKeyLabel(context),
              valueLabel: _agentsViewValueLabel(context),
              emptyText: openHandLocalizedText(
                context,
                zh: '暂无审批元数据。可补充风险等级、权限、范围、任务 ID 等字段。',
                en: 'No approval metadata yet. Add risk level, permissions, scope, task ID, or evidence fields.',
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

  void _submit() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      _showAgentInfoSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '请先填写审批标题。',
          en: 'Enter an approval title first.',
        ),
      );
      return;
    }
    if (_title.text.length > _agentStructuredFieldKeyMaxChars ||
        _reason.text.length > _agentStructuredFieldValueMaxChars ||
        _requestedAction.text.length > _agentStructuredFieldValueMaxChars) {
      _showAgentErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '审批文本超过长度限制。',
          en: 'Approval text exceeds the length limit.',
        ),
      );
      return;
    }
    final duplicate = _agentFirstDuplicateKey(_extraEntries);
    if (duplicate != null) {
      _showAgentErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '审批元数据字段重复：$duplicate',
          en: 'Duplicate approval metadata field: $duplicate',
        ),
      );
      return;
    }
    if (!_agentStructuredFieldsWithinLimits(_extraEntries)) {
      _showAgentErrorSnack(
        context,
        _agentStructuredFieldsLimitMessage(
          context,
          zhSubject: '审批元数据',
          enSubject: 'Approval metadata',
        ),
      );
      return;
    }
    Navigator.of(context).pop(
      _AgentApprovalRequestDraft(
        title: title,
        reason: _reason.text.trim(),
        requestedAction: _requestedAction.text.trim(),
        extra: _agentKeyValueDraftMapFromEntries(_extraEntries),
      ),
    );
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
    _showAgentErrorSnack(
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
  return '$prefix ${formatMonthDayHmLocal(time)}';
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
    'high' => _agentsViewHighRiskLabel(context),
    'medium' => openHandLocalizedText(context, zh: '中风险', en: 'Medium risk'),
    'low' => openHandLocalizedText(context, zh: '低风险', en: 'Low risk'),
    _ => openHandLocalizedText(context, zh: '常规', en: 'Standard'),
  };
}

List<String> _agentApprovalMetadataChips(
  BuildContext context,
  AgentApprovalRequest approval,
) {
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
    final text = _agentMetadataChipText(context, key, approval.extra[key]);
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
    final published = await context.read<AgentsController>().publishTask(
      agent.id,
      title: draft.title,
      description: draft.description,
      content: draft.content,
      note: draft.note,
      extra: draft.extra,
    );
    if (!published && context.mounted) {
      _showAgentErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '任务未发布，请先启用智能体并确认 Hermes Agent 可运行。',
          en: 'Task was not published. Enable the agent and confirm Hermes Agent can run first.',
        ),
      );
    }
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
  late final TextEditingController _labelInput;
  final List<String> _labels = <String>[];
  final List<_KeyValueDraft> _extraEntries = <_KeyValueDraft>[];

  @override
  void initState() {
    super.initState();
    _title = TextEditingController();
    _description = TextEditingController();
    _content = TextEditingController();
    _note = TextEditingController();
    _labelInput = TextEditingController();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _content.dispose();
    _note.dispose();
    _labelInput.dispose();
    for (final entry in _extraEntries) {
      entry.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return buildOpenHandDialog(
      maxWidth: kOpenHandDialogWidthStandard,
      child: _AgentDialogScaffold(
        icon: Icons.add_task_rounded,
        title: l10n.agentsDialogTitleWithName(
          l10n.agentsPublishTask,
          widget.agent.name,
        ),
        footer: _agentDialogActionsFooter(
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
              maxLength: _agentStructuredFieldKeyMaxChars,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              buildCounter: openHandHiddenTextFieldCounter,
              decoration: InputDecoration(labelText: l10n.agentsTaskTitleLabel),
            ),
            kOpenHandGap12,
            TextField(
              controller: _description,
              maxLength: _agentStructuredFieldValueMaxChars,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              buildCounter: openHandHiddenTextFieldCounter,
              decoration: InputDecoration(
                labelText: l10n.agentsDescriptionLabel,
              ),
            ),
            kOpenHandGap12,
            TextField(
              controller: _content,
              maxLength: _agentStructuredFieldValueMaxChars,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              buildCounter: openHandHiddenTextFieldCounter,
              minLines: 4,
              maxLines: 8,
              decoration: InputDecoration(labelText: l10n.agentsContentLabel),
            ),
            kOpenHandGap12,
            TextField(
              controller: _note,
              maxLength: _agentStructuredFieldValueMaxChars,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              buildCounter: openHandHiddenTextFieldCounter,
              decoration: InputDecoration(labelText: l10n.agentsNoteLabel),
            ),
            kOpenHandGap12,
            _taskLabelEditor(l10n),
            kOpenHandGap12,
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
              keyLabel: _agentsViewKeyLabel(context),
              valueLabel: _agentsViewValueLabel(context),
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

  Widget _taskLabelEditor(AppLocalizations l10n) {
    return InputDecorator(
      decoration: InputDecoration(labelText: l10n.agentsTaskLabelsLabel),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _labelInput,
                  maxLength: _agentStructuredFieldKeyMaxChars,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  buildCounter: openHandHiddenTextFieldCounter,
                  decoration: InputDecoration(
                    hintText: openHandLocalizedText(
                      context,
                      zh: '输入任务标签后添加',
                      en: 'Enter a task label, then add',
                    ),
                  ),
                  onSubmitted: (_) => _addLabel(),
                ),
              ),
              kOpenHandHGap10,
              IconButton.filledTonal(
                key: const ValueKey<String>('agent-publish-task-label-add'),
                tooltip: openHandAddLabel(context),
                onPressed: _labels.length >= _agentStructuredFieldMaxItems
                    ? null
                    : _addLabel,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          kOpenHandGap10,
          _AnimatedReorderableChipStrip(
            values: _labels,
            emptyText: _agentsViewNoTaskLabelsYetLabel(context),
            onRemove: (value) => setState(() => _labels.remove(value)),
            onReorder: (oldIndex, newIndex) =>
                setState(() => _reorderLabels(oldIndex, newIndex)),
            keyPrefix: 'agent-publish-task-label',
          ),
        ],
      ),
    );
  }

  void _addLabel() {
    final value = _labelInput.text.trim();
    if (value.isEmpty || _labels.length >= _agentStructuredFieldMaxItems) {
      return;
    }
    setState(() {
      if (!_labels.any((item) => item.toLowerCase() == value.toLowerCase())) {
        _labels.add(value);
      }
      _labelInput.clear();
    });
  }

  void _reorderLabels(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _labels.length) return;
    final targetIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    if (targetIndex < 0 || targetIndex >= _labels.length) return;
    final item = _labels.removeAt(oldIndex);
    _labels.insert(targetIndex, item);
  }

  void _removeExtraEntry(_KeyValueDraft entry) {
    setState(() {
      _extraEntries.remove(entry);
      entry.dispose();
    });
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    if (_title.text.trim().isEmpty) {
      _showAgentInfoSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '请先填写任务标题。',
          en: 'Enter a task title first.',
        ),
      );
      return;
    }
    if (_title.text.length > _agentStructuredFieldKeyMaxChars ||
        <TextEditingController>[_description, _content, _note].any(
          (field) => field.text.length > _agentStructuredFieldValueMaxChars,
        ) ||
        _labels.length > _agentStructuredFieldMaxItems ||
        _labels.any(
          (label) => label.length > _agentStructuredFieldKeyMaxChars,
        )) {
      _showAgentErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '任务文本或标签超过长度限制。',
          en: 'Task text or labels exceed the length limits.',
        ),
      );
      return;
    }
    final duplicate = _agentFirstDuplicateKey(_extraEntries);
    if (duplicate != null) {
      _showAgentErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '扩展字段重复：$duplicate',
          en: 'Duplicate extra field: $duplicate',
        ),
      );
      return;
    }
    final labelsConflict = _labels.isEmpty
        ? null
        : _agentFirstReservedKey(_extraEntries, const <String>{'labels'});
    if (labelsConflict != null) {
      _showAgentErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '扩展字段 $labelsConflict 与任务标签冲突。',
          en: 'Extra field $labelsConflict conflicts with task labels.',
        ),
      );
      return;
    }
    if (!_agentStructuredFieldsWithinLimits(_extraEntries)) {
      _showAgentErrorSnack(
        context,
        _agentStructuredFieldsLimitMessage(
          context,
          zhSubject: '任务扩展字段',
          enSubject: 'Task extra fields',
        ),
      );
      return;
    }
    final extra = _agentKeyValueDraftMapFromEntries(_extraEntries);
    if (_labels.isNotEmpty) {
      extra['labels'] = List<String>.unmodifiable(_labels);
    }
    Navigator.of(context).pop(
      _AgentPublishTaskDraft(
        title: _title.text,
        description: _description.text,
        content: _content.text,
        note: _note.text,
        extra: extra,
      ),
    );
  }
}

Future<void> _confirmDeleteAgent(
  BuildContext context,
  AgentProfile agent, [
  OpenHandListRemoval? removal,
]) async {
  final l10n = AppLocalizations.of(context)!;
  final confirmed = await showOpenHandConfirmDialog(
    context: context,
    title: l10n.agentsDeleteConfirmTitle,
    message: l10n.agentsDeleteConfirmMessage(agent.name),
    confirmLabel: l10n.commonDelete,
    destructive: true,
  );
  if (confirmed && context.mounted) {
    final controller = context.read<AgentsController>();
    var deleted = false;
    Future<void> delete() async {
      deleted = await controller.deleteAgent(agent.id);
    }

    // 从列表卡片触发时先播收起动效；从弹窗等入口触发时没有列表可收，直接删。
    await (removal == null ? delete() : removal.run(agent.id, delete));
    if (!deleted && context.mounted) {
      _showAgentMutationError(
        context,
        controller,
        zh: '智能体删除失败，请刷新后重试。',
        en: 'Failed to delete the agent. Refresh and try again.',
      );
    }
  }
}

class _AgentDialogScaffold extends StatelessWidget {
  const _AgentDialogScaffold({
    required this.icon,
    required this.title,
    required this.child,
    this.footer,
    this.footerAnimationKey,
    this.scrollable = true,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? footer;
  final Object? footerAnimationKey;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final motionSettings = _agentDialogAnimationSettings(context);
    final scrollChild = footer == null
        ? child
        : Padding(
            padding: const EdgeInsets.only(
              bottom: _agentDialogScrollableFooterClearance,
            ),
            child: child,
          );
    return Padding(
      padding: _agentDialogPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: _agentDialogTitleGap),
              Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: _agentDialogSectionGap),
          Flexible(
            child: scrollable
                ? SingleChildScrollView(
                    physics: openHandDialogAwareScrollPhysics(context),
                    child: scrollChild,
                  )
                : child,
          ),
          _AgentDialogFooterSlot(
            footer: footer,
            animationKey: footerAnimationKey,
            settings: motionSettings,
          ),
        ],
      ),
    );
  }
}

class _AgentDialogFooterSlot extends StatelessWidget {
  const _AgentDialogFooterSlot({
    required this.footer,
    required this.animationKey,
    required this.settings,
  });

  final Widget? footer;
  final Object? animationKey;
  final DialogAnimationSettings settings;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: settings.entranceDuration,
      reverseDuration: settings.exitDuration,
      transitionBuilder: (child, animation) => _agentDialogSwitchTransition(
        settings: settings,
        animation: animation,
        child: child,
      ),
      child: footer == null
          ? const SizedBox.shrink(
              key: ValueKey<String>('agent-dialog-footer-empty'),
            )
          : Padding(
              key: ValueKey<Object?>(
                animationKey ?? 'agent-dialog-footer-content',
              ),
              padding: const EdgeInsets.only(top: _agentDialogSectionGap),
              child: footer,
            ),
    );
  }
}

Widget _agentDialogPrimaryActionFooter({
  required IconData icon,
  required VoidCallback? onPressed,
  required String label,
}) {
  return _agentDialogActionsFooter(
    actions: [
      OpenHandDialogActionButton.primary(
        icon: icon,
        onPressed: onPressed,
        label: label,
      ),
    ],
  );
}

Widget _agentDialogActionsFooter({required List<Widget> actions}) {
  return Padding(
    padding: _agentDialogActionPadding,
    child: SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: kOpenHandDialogActionSpacing,
        runSpacing: kOpenHandDialogActionSpacing,
        children: actions,
      ),
    ),
  );
}

DialogAnimationSettings _agentDialogAnimationSettings(BuildContext context) {
  if (!openHandTickerMotionEnabled(context)) {
    return OpenHandMotionDefaults.disabled;
  }
  return openHandMotionSettingsOf(context, OpenHandMotionSettingsScope.dialog);
}

Widget _agentDialogSwitchTransition({
  required DialogAnimationSettings settings,
  required Animation<double> animation,
  required Widget child,
}) {
  final sizeAnimation = openHandBoundedCurveAnimation(
    parent: animation,
    curve: settings.curve.curve,
    reverseCurve: settings.curve.reverseCurve,
  );
  return SizeTransition(
    axisAlignment: -1,
    sizeFactor: sizeAnimation,
    child: buildAnimationStyleTransition(
      animation: animation,
      settings: settings,
      child: child,
    ),
  );
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
  if (result == null || !context.mounted) return;
  final saved = await controller.saveAgent(result);
  if (!saved && context.mounted) {
    _showAgentMutationError(
      context,
      controller,
      zh: '智能体保存失败，请重试。',
      en: 'Failed to save the agent. Try again.',
    );
  }
}

void _handleCreateAgent(
  BuildContext context,
  AgentRuntimeAvailability runtime,
) {
  if (!runtime.canRun) {
    _showAgentErrorSnack(
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
  _showAgentErrorSnack(
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
  late Set<String> _instructionIds;
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
    _instructionIds = {...?agent?.instructionIds};
    _maxWorkers = _normalizeAgentMaxWorkers(
      agent?.scaleSettings.maxWorkers ?? agentScaleDefaultMaxWorkers,
    );
    _minWorkers = _normalizeAgentMinWorkers(
      agent?.scaleSettings.minWorkers ?? agentScaleDefaultMinWorkers,
      _maxWorkers,
    );
    _maxRetries = _normalizeAgentMaxRetries(
      agent?.scaleSettings.maxRetries ?? agentScaleDefaultMaxRetries,
    );
    _scaleOutThreshold = _normalizeAgentScaleRatio(
      agent?.scaleSettings.scaleOutThreshold ??
          agentScaleDefaultScaleOutThreshold,
    );
    _scaleInThreshold = _normalizeAgentScaleRatio(
      agent?.scaleSettings.scaleInThreshold ??
          agentScaleDefaultScaleInThreshold,
    );
    _schedulerPolicy =
        agent?.scaleSettings.schedulerPolicy ?? agentSchedulerPolicyLeastBusy;
    _workerRemovalPolicy =
        agent?.scaleSettings.workerRemovalPolicy ??
        agentWorkerRemovalPolicyLeastBusy;
    _retryPolicy =
        agent?.scaleSettings.retryPolicy ?? agentRetryPolicyBoundedRetry;
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
    final instructionsController = context.watch<InstructionsController>();
    final skills = skillsController.skills;
    final knowledgeSources = knowledgeBaseController.sources;
    final memories = memoryController.entries;
    final mcpServers = mcpController.servers;
    final crons = cronsController.entries;
    final hooks = hooksController.entries;
    final instructions = instructionsController.entries;
    final runtime = context.watch<AgentsController>().runtimeAvailability;
    final builtinTools = _builtinToolOptions(settings.builtinToolConfigs);
    final selectedBuiltinTools = _normalizedBuiltinToolSelection(
      settings.builtinToolConfigs,
    );

    return buildOpenHandDialog(
      maxWidth: kOpenHandDialogWidthPanel,
      maxHeight: kOpenHandDialogHeightTall,
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
                      kOpenHandHGap10,
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
                  kOpenHandGap14,
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
                  kOpenHandGap14,
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
                            hooks: hooks
                                .map(
                                  (h) => _Option(
                                    h.id,
                                    h.label,
                                    h.event.label(l10n),
                                    enabled: h.enabled && h.hasScript,
                                  ),
                                )
                                .toList(),
                            instructions: instructions
                                .map(
                                  (entry) => _Option(
                                    entry.id,
                                    entry.name,
                                    _agentInstructionOptionSubtitle(
                                      context,
                                      entry,
                                    ),
                                    enabled: entry.enabled,
                                  ),
                                )
                                .toList(),
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
                          ),
                        ),
                        _tabScroll(_metadataTab(l10n)),
                      ],
                    ),
                  ),
                  kOpenHandGap16,
                  _agentDialogActionsFooter(
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
    required List<_Option> hooks,
    required List<_Option> instructions,
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
        kOpenHandGap12,
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
                  child: _AgentToolCapabilityPanel(
                    title: openHandLocalizedText(
                      context,
                      zh: 'Agent 协同工具',
                      en: 'Agent coordination tools',
                    ),
                    icon: Icons.account_tree_rounded,
                    options: agentTools,
                    selected: selectedBuiltinTools,
                    onChanged: (v) => setState(
                      () => _builtinToolNames = _mergeAgentToolSelection(
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
                    title: 'Hooks',
                    icon: Icons.bolt_rounded,
                    options: hooks,
                    selected: _hookIds,
                    onChanged: (v) => setState(() => _hookIds = v),
                  ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: _CapabilityPanel(
                    title: openHandInstructionsLabel(context),
                    icon: Icons.rule_rounded,
                    options: instructions,
                    selected: _instructionIds,
                    onChanged: (v) => setState(() => _instructionIds = v),
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
                        current: _selectedBuiltinToolsWithInternalBindings(
                          selectedBuiltinTools,
                        ),
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
        kOpenHandGap14,
        SegmentedButton<AgentExecutionMode>(
          segments: [
            for (final mode in AgentExecutionMode.values)
              ButtonSegment(
                value: mode,
                label: Text(_agentExecutionModeLabel(l10n, mode)),
              ),
          ],
          selected: {_executionMode},
          onSelectionChanged: (value) {
            _handleExecutionModeChanged(value.first);
          },
        ),
        kOpenHandGap10,
        _executionModePolicyCard(l10n),
        kOpenHandGap14,
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
        kOpenHandGap12,
        _directoryPickerField(
          label: l10n.agentsFieldWorkspacePath,
          value: _workspacePath.text,
          onPick: _pickWorkspacePath,
          onClear: () => setState(_workspacePath.clear),
        ),
        kOpenHandGap12,
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

  Widget _executionModePolicyCard(AppLocalizations l10n) {
    final fullAccess = _executionMode == AgentExecutionMode.fullAccess;
    return FeatureStateCard.inline(
      icon: fullAccess
          ? Icons.warning_amber_rounded
          : Icons.verified_user_outlined,
      tone: fullAccess ? FeatureStateTone.error : FeatureStateTone.neutral,
      title: openHandLocalizedText(context, zh: '审批策略', en: 'Approval policy'),
      body: fullAccess
          ? openHandLocalizedText(
              context,
              zh: '常规文件与命令操作可自动执行；越权目录、凭据或密钥访问、不可逆外部副作用、缺少证据的生产变更仍需审批。',
              en: 'Routine file and command actions can run automatically; scope violations, credential or secret access, irreversible external side effects, and production changes without evidence still require approval.',
            )
          : openHandLocalizedText(
              context,
              zh: '特权能力、外部副作用、破坏性或不可逆操作、敏感数据访问、职责边界不清时都需要先审批。',
              en: 'Privileged capability use, external side effects, destructive or irreversible actions, sensitive data access, and unclear scope boundaries require approval first.',
            ),
      trailing: Text(
        _agentExecutionModeLabel(l10n, _executionMode),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _governanceTab({
    required AppLocalizations l10n,
    required List<_Option> crons,
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
        kOpenHandGap8,
        Text(
          l10n.agentsClusterScaling,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        kOpenHandGap8,
        Row(
          children: [
            Expanded(
              child: _numberStepper(
                l10n.agentsMinWorkersLabel,
                _minWorkers,
                min: agentScaleMinWorkersMinimum,
                max: _maxWorkers,
                onChanged: (v) => setState(
                  () => _minWorkers = _normalizeAgentMinWorkers(v, _maxWorkers),
                ),
              ),
            ),
            kOpenHandHGap12,
            Expanded(
              child: _numberStepper(
                l10n.agentsMaxWorkersLabel,
                _maxWorkers,
                min: agentScaleMaxWorkersMinimum,
                max: agentScaleWorkersMaximum,
                onChanged: (v) => setState(() {
                  _maxWorkers = _normalizeAgentMaxWorkers(v);
                  _minWorkers = _normalizeAgentMinWorkers(
                    _minWorkers,
                    _maxWorkers,
                  );
                }),
              ),
            ),
            kOpenHandHGap12,
            Expanded(
              child: _numberStepper(
                l10n.agentsMaxRetriesLabel,
                _maxRetries,
                min: agentScaleMaxRetriesMinimum,
                max: agentScaleMaxRetriesMaximum,
                onChanged: (v) =>
                    setState(() => _maxRetries = _normalizeAgentMaxRetries(v)),
              ),
            ),
          ],
        ),
        kOpenHandGap12,
        Row(
          children: [
            Expanded(
              child: _ratioSlider(
                _agentsViewScaleOutThresholdLabel(context),
                _scaleOutThreshold,
                (value) => setState(() => _scaleOutThreshold = value),
              ),
            ),
            kOpenHandHGap12,
            Expanded(
              child: _ratioSlider(
                _agentsViewScaleInThresholdLabel(context),
                _scaleInThreshold,
                (value) => setState(() => _scaleInThreshold = value),
              ),
            ),
          ],
        ),
        kOpenHandGap12,
        Row(
          children: [
            Expanded(
              child: _policyDropdown(
                label: l10n.agentsSchedulerPolicyLabel,
                value: _schedulerPolicy,
                values: agentSchedulerPolicyOptions,
                onChanged: (value) => setState(() => _schedulerPolicy = value),
              ),
            ),
            kOpenHandHGap12,
            Expanded(
              child: _policyDropdown(
                label: _agentsViewWorkerRemovalPolicyLabel(context),
                value: _workerRemovalPolicy,
                values: agentWorkerRemovalPolicyOptions,
                onChanged: (value) =>
                    setState(() => _workerRemovalPolicy = value),
              ),
            ),
            kOpenHandHGap12,
            Expanded(
              child: _policyDropdown(
                label: _agentsViewRetryPolicyLabel(context),
                value: _retryPolicy,
                values: agentRetryPolicyOptions,
                onChanged: (value) => setState(() => _retryPolicy = value),
              ),
            ),
          ],
        ),
        kOpenHandGap14,
        _editableStringChips(
          label: _agentsViewWorkerTagsLabel(context),
          inputController: _workerTagInput,
          values: _workerTagValues,
          emptyText: _agentsViewNoWorkerTagsYetLabel(context),
          onAdd: _addWorkerTag,
          onSubmitted: (_) => _addWorkerTag(),
          onRemove: (value) => setState(() => _workerTagValues.remove(value)),
          onReorder: (oldIndex, newIndex) => setState(
            () => _reorderStringList(_workerTagValues, oldIndex, newIndex),
          ),
          keyPrefix: 'agent-worker-tag',
        ),
        kOpenHandGap14,
        _editableStringChips(
          label: l10n.agentsTaskLabelsLabel,
          inputController: _taskLabelInput,
          values: _taskLabelValues,
          emptyText: _agentsViewNoTaskLabelsYetLabel(context),
          onAdd: _addTaskLabel,
          onSubmitted: (_) => _addTaskLabel(),
          onRemove: (value) => setState(() => _taskLabelValues.remove(value)),
          onReorder: (oldIndex, newIndex) => setState(
            () => _reorderStringList(_taskLabelValues, oldIndex, newIndex),
          ),
          keyPrefix: 'agent-task-label',
        ),
        kOpenHandGap14,
        Text(l10n.agentsKpi, style: Theme.of(context).textTheme.titleMedium),
        kOpenHandGap8,
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _kpiName,
                maxLength: _agentStructuredFieldKeyMaxChars,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                buildCounter: openHandHiddenTextFieldCounter,
                decoration: InputDecoration(labelText: l10n.agentsFieldName),
              ),
            ),
            kOpenHandHGap12,
            Expanded(
              child: TextField(
                controller: _kpiTarget,
                maxLength: _agentStructuredFieldValueMaxChars,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                buildCounter: openHandHiddenTextFieldCounter,
                decoration: InputDecoration(labelText: l10n.agentsFieldTarget),
              ),
            ),
            kOpenHandHGap12,
            IconButton.filledTonal(
              onPressed: _kpis.length >= _agentStructuredFieldMaxItems
                  ? null
                  : _addKpi,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        kOpenHandGap10,
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
          keyLabel: _agentsViewKeyLabel(context),
          valueLabel: _agentsViewValueLabel(context),
          emptyText: openHandLocalizedText(
            context,
            zh: '暂无元数据。添加键值后会随智能体档案保存。',
            en: 'No metadata yet. Add key-value pairs to save with this agent.',
          ),
          onAdd: _addMetadataEntry,
          onRemove: _removeMetadataEntry,
        ),
        kOpenHandGap12,
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
              borderRadius: BorderRadius.circular(kOpenHandRadius16),
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
          kOpenHandHGap12,
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
          kOpenHandHGap8,
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
            kOpenHandHGap6,
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
                _agentsViewPriorityLabel(context),
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
          kOpenHandGap12,
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
            maxItems: agentRouteKeywordMaxItems,
            keyPrefix: 'agent-route-keyword',
          ),
          kOpenHandGap12,
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
            maxItems: agentRouteKeywordMaxItems,
            keyPrefix: 'agent-route-domain',
          ),
          kOpenHandGap12,
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
            maxItems: agentRouteKeywordMaxItems,
            keyPrefix: 'agent-route-intent',
          ),
          kOpenHandGap12,
          _keyValueEditor(
            title: openHandLocalizedText(
              context,
              zh: '扩展路由字段',
              en: 'Extra routing fields',
            ),
            entries: _routeExtraFields,
            keyLabel: openHandLocalizedText(context, zh: '字段', en: 'Field'),
            valueLabel: _agentsViewValueLabel(context),
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
          kOpenHandHGap10,
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
          kOpenHandHGap8,
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
            kOpenHandHGap6,
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
              label: Text(_agentsViewPickDirectoryLabel(context)),
            ),
          ),
          kOpenHandGap10,
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
    int maxItems = _agentStructuredFieldMaxItems,
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
                  maxLength: _agentStructuredFieldKeyMaxChars,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  buildCounter: openHandHiddenTextFieldCounter,
                  decoration: InputDecoration(
                    hintText: _agentsViewEnterTextThenAddLabel(context),
                  ),
                  onSubmitted: onSubmitted,
                ),
              ),
              kOpenHandHGap10,
              IconButton.filledTonal(
                tooltip: openHandAddLabel(context),
                onPressed: values.length >= maxItems ? null : onAdd,
                icon: Icon(addIcon),
              ),
            ],
          ),
          kOpenHandGap10,
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
    int? maxLength,
  }) {
    return _FormGridItem(
      fullWidth: fullWidth,
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        maxLength:
            maxLength ??
            (maxLines == 1
                ? _agentStructuredFieldKeyMaxChars
                : _agentStructuredFieldValueMaxChars),
        maxLengthEnforcement: MaxLengthEnforcement.enforced,
        buildCounter: openHandHiddenTextFieldCounter,
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
    return AnimatedDropdownButtonFormField<String>(
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
    final normalized = _normalizeAgentScaleRatio(value);
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

  Widget _numberStepper(
    String label,
    int value, {
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return _AgentNumberStepperField(
      label: label,
      value: value,
      min: min,
      max: max,
      onChanged: onChanged,
    );
  }

  Future<void> _pickAvatarImage() async {
    try {
      final picked = await pickAndEditImage(
        context,
        acceptedExtensions: _agentImageExtensions,
        imageSizeLimitBytes: 512 * kBytesPerKiB,
      );
      if (picked == null || !mounted) return;
      final path = await _persistAvatarImage(
        sourceName: picked.sourceFile.name,
        bytes: picked.editedImage.bytes,
        format: picked.editedImage.format,
      );
      if (!mounted) return;
      setState(() => _avatar.text = path);
    } catch (error, stack) {
      silentLog('agents', '选择头像图片', error, stack);
      if (!mounted) return;
      _showAgentErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '无法处理所选头像，请确认图片有效且未超过大小限制。',
          en: 'Could not process the selected avatar. Check that the image is valid and within the size limit.',
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
    await writeBytesFileAtomically(file, bytes);
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
      confirmButtonText: _agentsViewPickDirectoryLabel(context),
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
        context.read<InstructionsController>().refresh(),
      ]);
      if (!mounted) return;
      _showAgentInfoSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '能力配置已刷新。',
          en: 'Capabilities refreshed.',
        ),
      );
    } catch (error, stack) {
      silentLog('agents', '刷新能力配置', error, stack);
      if (!mounted) return;
      _showAgentErrorSnack(
        context,
        userFailureMessage(
          error,
          fallback: openHandLocalizedText(
            context,
            zh: '能力配置刷新失败，请稍后重试。',
            en: 'Failed to refresh capabilities. Try again later.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _refreshingCapabilities = false);
    }
  }

  Future<void> _handleExecutionModeChanged(AgentExecutionMode next) async {
    if (next == _executionMode) return;
    if (next == AgentExecutionMode.fullAccess) {
      final confirmed = await showOpenHandConfirmDialog(
        context: context,
        title: openHandLocalizedText(
          context,
          zh: '启用完全访问模式？',
          en: 'Enable full access mode?',
        ),
        message: openHandLocalizedText(
          context,
          zh: '完全访问模式会让智能体在工作循环中自动执行常规文件与命令操作，减少审批打断。\n\n越权目录、凭据或密钥访问、不可逆外部副作用、缺少证据的生产变更仍需审批。启用前请确认该智能体的职责边界与工作目录范围已配置清楚。',
          en: 'Full access lets the agent automatically run routine file and command actions during its work loop, reducing approval interruptions.\n\nScope violations, credential or secret access, irreversible external side effects, and production changes without evidence still require approval. Confirm the agent boundary and workspace scope before enabling it.',
        ),
        cancelLabel: openHandCancelLabel(context),
        confirmLabel: openHandLocalizedText(
          context,
          zh: '是，仍然继续',
          en: 'Yes, continue',
        ),
        destructive: true,
      );
      if (!confirmed || !mounted) return;
    }
    if (!mounted) return;
    setState(() => _executionMode = next);
  }

  void _addRouteKeyword() {
    _addStringFromController(
      _routeKeywords,
      _routeKeywordInput,
      maxItems: agentRouteKeywordMaxItems,
    );
  }

  void _addRouteDomain() {
    _addStringFromController(
      _routeDomains,
      _routeDomainInput,
      maxItems: agentRouteKeywordMaxItems,
    );
  }

  void _addRouteIntent() {
    _addStringFromController(
      _routeIntents,
      _routeIntentInput,
      maxItems: agentRouteKeywordMaxItems,
    );
  }

  void _addTaskLabel() {
    _addStringFromController(_taskLabelValues, _taskLabelInput);
  }

  void _addWorkerTag() {
    _addStringFromController(_workerTagValues, _workerTagInput);
  }

  void _addStringFromController(
    List<String> values,
    TextEditingController controller, {
    int maxItems = _agentStructuredFieldMaxItems,
  }) {
    final value = controller.text.trim();
    if (value.isEmpty || values.length >= maxItems) return;
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
    if (name.isEmpty || _kpis.length >= _agentStructuredFieldMaxItems) return;
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
    FocusScope.of(dialogContext).unfocus();
    final routeFrontMatter = _buildRouteFrontMatter();
    final validationError = _validateDraft(routeFrontMatter);
    if (validationError != null) {
      _showAgentErrorSnack(context, validationError);
      return;
    }
    final metadata = _metadataMapFromEntries();
    Navigator.of(dialogContext, rootNavigator: true).pop(
      _buildAgent(
        builtinToolConfigs: builtinToolConfigs,
        metadata: metadata,
        routeFrontMatter: routeFrontMatter,
      ),
    );
  }

  String? _validateDraft(String routeFrontMatter) {
    final shortFields = <TextEditingController>[
      _name,
      _position,
      _department,
      _mentor,
      _level,
      _routeName,
      _routePriority,
    ];
    if (shortFields.any(
      (field) => field.text.length > _agentStructuredFieldKeyMaxChars,
    )) {
      return openHandLocalizedText(
        context,
        zh:
            '名称、职位、部门、导师、级别和路由短字段不能超过 '
            '$_agentStructuredFieldKeyMaxChars 个字符。',
        en:
            'Name, position, department, mentor, level, and short routing fields '
            'cannot exceed $_agentStructuredFieldKeyMaxChars characters.',
      );
    }
    final longFields = <TextEditingController>[
      _introduction,
      _archive,
      _routeDescription,
      _welcomeMessage,
      _persona,
      _boundary,
    ];
    if (longFields.any(
      (field) => field.text.length > _agentStructuredFieldValueMaxChars,
    )) {
      return openHandLocalizedText(
        context,
        zh: '智能体长文本字段不能超过 $_agentStructuredFieldValueMaxChars 个字符。',
        en:
            'Agent long-text fields cannot exceed '
            '$_agentStructuredFieldValueMaxChars characters.',
      );
    }
    for (final values in <List<String>>[_taskLabelValues, _workerTagValues]) {
      if (values.length > _agentStructuredFieldMaxItems ||
          values.any(
            (value) => value.length > _agentStructuredFieldKeyMaxChars,
          )) {
        return openHandLocalizedText(
          context,
          zh:
              '任务标签和 Worker 标签最多 $_agentStructuredFieldMaxItems 项，'
              '每项不超过 $_agentStructuredFieldKeyMaxChars 个字符。',
          en:
              'Task and worker labels are limited to '
              '$_agentStructuredFieldMaxItems items and '
              '$_agentStructuredFieldKeyMaxChars characters per item.',
        );
      }
    }
    if (_kpis.length > _agentStructuredFieldMaxItems ||
        _kpis.any(
          (item) =>
              item.name.length > _agentStructuredFieldKeyMaxChars ||
              item.target.length > _agentStructuredFieldValueMaxChars ||
              item.plan.length > _agentStructuredFieldValueMaxChars,
        )) {
      return openHandLocalizedText(
        context,
        zh: 'KPI 最多 $_agentStructuredFieldMaxItems 项，且文本不能超过长度限制。',
        en:
            'KPI items are limited to $_agentStructuredFieldMaxItems and their text '
            'must remain within the length limits.',
      );
    }
    if (!_agentJsonValueWithinLimits(
      _kpis.map((item) => item.extra).toList(growable: false),
      maxDepth: _agentStructuredFieldMaxDepth + 1,
    )) {
      return _agentStructuredFieldsLimitMessage(
        context,
        zhSubject: 'KPI 元数据',
        enSubject: 'KPI metadata',
      );
    }
    if (!_agentStructuredTextWithinLimits(_routePriority.text)) {
      return _agentStructuredFieldsLimitMessage(
        context,
        zhSubject: '路由优先级',
        enSubject: 'Routing priority',
      );
    }
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
    final reservedRoute = _agentFirstReservedKey(
      _routeExtraFields,
      _agentRouteReservedKeys,
    );
    if (reservedRoute != null) {
      return openHandLocalizedText(
        context,
        zh: '路由扩展字段 $reservedRoute 与内置路由字段冲突。',
        en: 'Routing field $reservedRoute conflicts with a built-in routing field.',
      );
    }
    if (!_agentStructuredFieldsWithinLimits(_metadataEntries)) {
      return _agentStructuredFieldsLimitMessage(
        context,
        zhSubject: '智能体元数据',
        enSubject: 'Agent metadata',
      );
    }
    if (!_agentStructuredFieldsWithinLimits(_routeExtraFields)) {
      return _agentStructuredFieldsLimitMessage(
        context,
        zhSubject: '路由扩展字段',
        enSubject: 'Routing fields',
      );
    }
    if (routeFrontMatter.length > agentRouteFrontMatterMaxChars) {
      return openHandLocalizedText(
        context,
        zh: '路由配置不能超过 $agentRouteFrontMatterMaxChars 个字符。',
        en: 'Routing configuration cannot exceed $agentRouteFrontMatterMaxChars characters.',
      );
    }
    for (final values in <List<String>>[
      _routeKeywords,
      _routeDomains,
      _routeIntents,
    ]) {
      if (values.length > agentRouteKeywordMaxItems) {
        return openHandLocalizedText(
          context,
          zh: '关键词、领域和意图每组最多 $agentRouteKeywordMaxItems 项。',
          en: 'Keywords, domains, and intents are limited to $agentRouteKeywordMaxItems items per group.',
        );
      }
      if (values.any((value) => value.length > agentRouteKeywordMaxChars)) {
        return openHandLocalizedText(
          context,
          zh: '单个关键词、领域或意图不能超过 $agentRouteKeywordMaxChars 个字符。',
          en: 'Each keyword, domain, or intent cannot exceed $agentRouteKeywordMaxChars characters.',
        );
      }
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
    required String routeFrontMatter,
  }) {
    final now = DateTime.now().toUtc();
    final previous = widget.initialAgent;
    final maxWorkers = _normalizeAgentMaxWorkers(_maxWorkers);
    final minWorkers = _normalizeAgentMinWorkers(_minWorkers, maxWorkers);
    final maxRetries = _normalizeAgentMaxRetries(_maxRetries);
    final taskLabels = dedupeNonEmptyStrings(_taskLabelValues);
    final workerTags = dedupeNonEmptyStrings(_workerTagValues);
    final workspacePath = _normalizedWorkspacePath();
    final workspaceScopePaths = _normalizedWorkspaceScopePaths(workspacePath);
    final builtinToolNames = _normalizedBuiltinToolSelection(
      builtinToolConfigs,
    ).toSet();
    final hasAgentToolSelection = builtinToolNames.any(
      _isAgentCoordinationBuiltinToolId,
    );
    final explicitlyNoAgentTools = _builtinToolNames.contains(
      agentNoCoordinationToolsBinding,
    );
    if (!hasAgentToolSelection && explicitlyNoAgentTools) {
      builtinToolNames.add(agentNoCoordinationToolsBinding);
    }
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
      routeFrontMatter: routeFrontMatter,
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
      builtinToolNames: builtinToolNames.toList(growable: false),
      workspacePath: workspacePath,
      workspaceScope: workspaceScopePaths.join('\n'),
      workspaceScopePaths: workspaceScopePaths,
      cronIds: _cronIds.toList(),
      hookIds: _hookIds.toList(),
      instructionIds: _instructionIds.toList(),
      selfLearningEnabled: _selfLearningEnabled,
      enabled: _enabled,
      executionMode: _executionMode,
      lifecycleState: _enabled
          ? AgentLifecycleState.running
          : AgentLifecycleState.stopped,
      scaleSettings: AgentScaleSettings(
        minWorkers: minWorkers,
        maxWorkers: maxWorkers,
        scaleOutThreshold: _normalizeAgentScaleRatio(_scaleOutThreshold),
        scaleInThreshold: _normalizeAgentScaleRatio(_scaleInThreshold),
        workerRemovalPolicy: _workerRemovalPolicy,
        retryPolicy: _retryPolicy,
        maxRetries: maxRetries,
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
    final keywords = dedupeNonEmptyStrings(_routeKeywords);
    final domains = dedupeNonEmptyStrings(_routeDomains);
    final intents = dedupeNonEmptyStrings(_routeIntents);
    if (keywords.isNotEmpty) data['keywords'] = keywords;
    if (domains.isNotEmpty) data['domains'] = domains;
    if (intents.isNotEmpty) data['intents'] = intents;
    data.addAll(_mapFromEntries(_routeExtraFields));
    if (data.isEmpty) return '';
    return '---\n${prettyPrintJson(data)}\n---';
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
    final entries = <_KeyValueDraft>[];
    for (final entry in route.entries) {
      if (_agentRouteReservedKeys.contains(entry.key.toLowerCase())) continue;
      entries.add(_KeyValueDraft(key: entry.key, value: entry.value));
    }
    return entries;
  }

  String _stringFromRouteValue(Object? value, String fallback) {
    final text = value == null ? '' : '$value'.trim();
    return text.isEmpty ? fallback : text;
  }

  List<String> _routeStringsFromValues(Iterable<Object?> values) {
    return dedupeNonEmptyStrings(values.expand(_stringsFromStructuredValue))
        .where((value) => value.length <= agentRouteKeywordMaxChars)
        .take(agentRouteKeywordMaxItems)
        .toList(growable: false);
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
      if (config.kind.isAgentCoordinationTool) {
        agentTools.add(
          _agentToolOption(context, id, config.kind, enabled: config.enabled),
        );
      } else {
        regularTools.add(
          _Option(
            id,
            config.effectiveName,
            config.kind.name,
            enabled: config.enabled,
          ),
        );
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
    final availableAgentToolIds = <String>{};
    final disabledAgentToolIds = <String>{};
    final disabledToolIds = <String>{};
    for (final config in configs) {
      final id = _builtinToolOptionId(config);
      if (!config.enabled) {
        disabledToolIds.add(id);
      }
      if (config.kind.isAgentCoordinationTool) {
        if (config.enabled) {
          availableAgentToolIds.add(id);
        } else {
          disabledAgentToolIds.add(id);
        }
      }
      aliases[config.kind.name.toLowerCase()] = id;
      aliases[config.effectiveName.toLowerCase()] = id;
      if (config.customToolName != null) {
        aliases[config.customToolName!.trim().toLowerCase()] = id;
      }
    }
    if (_builtinToolNames.isEmpty) {
      return availableAgentToolIds;
    }
    final normalized = <String>{};
    for (final raw in _builtinToolNames) {
      final value = raw.trim();
      if (value.isEmpty || value == agentNoCoordinationToolsBinding) {
        continue;
      }
      final resolved = aliases[value.toLowerCase()] ?? value;
      if (disabledAgentToolIds.contains(resolved) ||
          disabledToolIds.contains(resolved)) {
        continue;
      }
      normalized.add(resolved);
    }
    return normalized;
  }

  Set<String> _selectedBuiltinToolsWithInternalBindings(Set<String> selected) {
    return <String>{
      ...selected,
      if (_builtinToolNames.contains(agentNoCoordinationToolsBinding))
        agentNoCoordinationToolsBinding,
    };
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
      // 限定解码尺寸：头像最大只渲染到 size 逻辑像素，不加这一层就会把原图
      // 按全分辨率解进内存——一张手机照片够占几十 MB，而这里只画几十像素。
      final decodeExtent = (size * MediaQuery.devicePixelRatioOf(context))
          .round();
      return Image.file(
        File(avatar),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: decodeExtent,
        cacheHeight: decodeExtent,
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
      onPressed: entries.length >= _agentStructuredFieldMaxItems ? null : onAdd,
      icon: const Icon(Icons.add_rounded),
    );
    final animationSettings = _agentChipAnimationSettings(context);
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
                AnimatedRemovableChip(
                  key: ObjectKey(entry),
                  settings: animationSettings,
                  collapseAxis: Axis.vertical,
                  onRemove: () => onRemove(entry),
                  builder: (context, requestRemove) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 5,
                            child: TextField(
                              controller: entry.key,
                              maxLength: _agentStructuredFieldKeyMaxChars,
                              maxLengthEnforcement:
                                  MaxLengthEnforcement.enforced,
                              buildCounter: openHandHiddenTextFieldCounter,
                              decoration: InputDecoration(labelText: keyLabel),
                              onChanged: (_) => onChanged?.call(),
                            ),
                          ),
                          kOpenHandHGap10,
                          Expanded(
                            flex: 7,
                            child: TextField(
                              controller: entry.value,
                              maxLength: _agentStructuredFieldValueMaxChars,
                              maxLengthEnforcement:
                                  MaxLengthEnforcement.enforced,
                              buildCounter: openHandHiddenTextFieldCounter,
                              decoration: InputDecoration(
                                labelText: valueLabel,
                              ),
                              onChanged: (_) => onChanged?.call(),
                            ),
                          ),
                          kOpenHandHGap6,
                          IconButton(
                            tooltip: openHandLocalizedText(
                              context,
                              zh: '删除字段',
                              en: 'Remove field',
                            ),
                            onPressed: requestRemove,
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    );
                  },
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
        kOpenHandGap8,
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
      duration: openHandMotionDuration(context, kThemeAnimationDuration),
      curve: kOpenHandSwitchInCurve,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.34),
        borderRadius: kOpenHandBorderRadius8,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: colors.primary),
              kOpenHandHGap8,
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
          kOpenHandGap12,
          child,
        ],
      ),
    );
  }
}

class _AnimatedReorderableChipStrip extends StatefulWidget {
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
  State<_AnimatedReorderableChipStrip> createState() =>
      _AnimatedReorderableChipStripState();
}

class _AnimatedReorderableChipStripState
    extends State<_AnimatedReorderableChipStrip> {
  String? _activeDragValue;
  int? _hoverInsertIndex;
  String? _lastMoveSignature;
  final Map<String, GlobalKey> _chipKeys = <String, GlobalKey>{};

  @override
  void didUpdateWidget(covariant _AnimatedReorderableChipStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    final activeValues = widget.values.toSet();
    _chipKeys.removeWhere((value, _) => !activeValues.contains(value));
  }

  GlobalKey _keyForValue(String value) {
    return _chipKeys.putIfAbsent(value, GlobalKey.new);
  }

  void _startDrag(String value) {
    setState(() {
      _activeDragValue = value;
      _hoverInsertIndex = null;
      _lastMoveSignature = null;
    });
  }

  void _finishDrag() {
    if (_activeDragValue == null &&
        _hoverInsertIndex == null &&
        _lastMoveSignature == null) {
      return;
    }
    setState(() {
      _activeDragValue = null;
      _hoverInsertIndex = null;
      _lastMoveSignature = null;
    });
  }

  void _handleDragMove(DragTargetDetails<_AgentChipDragPayload> details) {
    if (widget.values.length < 2) return;
    final insertIndex = _insertIndexForDragOffset(
      details.data.value,
      details.offset,
    );
    if (_hoverInsertIndex == insertIndex) return;
    setState(() => _hoverInsertIndex = insertIndex);
  }

  void _handleDragAccept(DragTargetDetails<_AgentChipDragPayload> details) {
    final insertIndex = _insertIndexForDragOffset(
      details.data.value,
      details.offset,
    );
    _reorderToSlot(details.data, insertIndex);
    _finishDrag();
  }

  void _handleDragEnd(String value, Offset feedbackTopLeft) {
    if (_activeDragValue != value) return;
    final rect = _globalRectFor(_keyForValue(value));
    final dropOffset = rect == null
        ? feedbackTopLeft
        : feedbackTopLeft + Offset(rect.width / 2, rect.height / 2);
    _reorderToSlot(
      _AgentChipDragPayload(value: value),
      _insertIndexForDragOffset(value, dropOffset),
    );
    _finishDrag();
  }

  void _handleDragLeave(_AgentChipDragPayload? _) {
    if (_hoverInsertIndex == null) return;
    setState(() => _hoverInsertIndex = null);
  }

  void _reorderToSlot(_AgentChipDragPayload payload, int insertIndex) {
    if (_activeDragValue != payload.value) {
      _activeDragValue = payload.value;
    }
    final oldIndex = widget.values.indexOf(payload.value);
    if (oldIndex < 0) return;
    final boundedInsertIndex = insertIndex
        .clamp(0, widget.values.length)
        .toInt();
    final targetIndex = boundedInsertIndex > oldIndex
        ? boundedInsertIndex - 1
        : boundedInsertIndex;
    if (targetIndex == oldIndex ||
        targetIndex < 0 ||
        targetIndex >= widget.values.length) {
      return;
    }
    final moveSignature = '${payload.value}:$targetIndex';
    if (_lastMoveSignature == moveSignature) return;
    _lastMoveSignature = moveSignature;
    widget.onReorder(oldIndex, boundedInsertIndex);
  }

  int _insertIndexForDragOffset(String value, Offset globalOffset) {
    final preciseIndex = _insertIndexForOffset(globalOffset);
    final oldIndex = widget.values.indexOf(value);
    final rect = _globalRectFor(_keyForValue(value));
    if (oldIndex < 0 || rect == null) return preciseIndex;
    if (globalOffset.dx < rect.left - _agentChipSpacing &&
        preciseIndex >= oldIndex) {
      return (oldIndex - 1).clamp(0, widget.values.length).toInt();
    }
    if (globalOffset.dx > rect.right + _agentChipSpacing &&
        preciseIndex <= oldIndex) {
      return (oldIndex + 2).clamp(0, widget.values.length).toInt();
    }
    return preciseIndex;
  }

  int _insertIndexForOffset(Offset globalOffset) {
    final slots = <({int index, Rect rect})>[];
    for (final entry in widget.values.indexed) {
      final rect = _globalRectFor(_keyForValue(entry.$2));
      if (rect == null) continue;
      slots.add((index: entry.$1, rect: rect));
    }
    if (slots.isEmpty) return widget.values.length;

    ({int index, Rect rect}) nearestRowAnchor = slots.first;
    var nearestDistance = _verticalDistanceToRect(
      globalOffset.dy,
      nearestRowAnchor.rect,
    );
    for (final slot in slots.skip(1)) {
      final distance = _verticalDistanceToRect(globalOffset.dy, slot.rect);
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestRowAnchor = slot;
      }
    }

    final anchorCenterY = nearestRowAnchor.rect.center.dy;
    final row =
        slots
            .where(
              (slot) =>
                  (slot.rect.center.dy - anchorCenterY).abs() <=
                  slot.rect.height + _agentChipSpacing,
            )
            .toList()
          ..sort((left, right) => left.rect.left.compareTo(right.rect.left));

    for (final slot in row) {
      if (globalOffset.dx < slot.rect.center.dx) return slot.index;
    }
    return (row.isEmpty ? slots.last.index : row.last.index) + 1;
  }

  Rect? _globalRectFor(GlobalKey key) {
    final renderObject = key.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    final topLeft = renderObject.localToGlobal(Offset.zero);
    return topLeft & renderObject.size;
  }

  double _verticalDistanceToRect(double y, Rect rect) {
    if (y < rect.top) return rect.top - y;
    if (y > rect.bottom) return y - rect.bottom;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final animationSettings = _agentChipAnimationSettings(context);
    if (widget.values.isEmpty) {
      return _AgentChipStripSwitcher(
        settings: animationSettings,
        child: Text(
          key: const ValueKey<String>('agent-chip-strip-empty'),
          widget.emptyText,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return _AgentChipStripSwitcher(
      settings: animationSettings,
      child: DragTarget<_AgentChipDragPayload>(
        onWillAcceptWithDetails: (details) =>
            widget.values.contains(details.data.value),
        onMove: _handleDragMove,
        onAcceptWithDetails: _handleDragAccept,
        onLeave: _handleDragLeave,
        builder: (context, candidateData, rejectedData) {
          final targeted = candidateData.isNotEmpty;
          return AnimatedSize(
            key: const ValueKey<String>('agent-chip-strip-list'),
            duration: animationSettings.duration,
            curve: animationSettings.curve.curve,
            alignment: AlignmentDirectional.topStart,
            child: Wrap(
              spacing: _agentChipSpacing,
              runSpacing: _agentChipSpacing,
              children: [
                for (final entry in widget.values.indexed) ...[
                  if (targeted && _hoverInsertIndex == entry.$1)
                    _AgentChipInsertionIndicator(settings: animationSettings),
                  _AgentReorderableChip(
                    key: ValueKey<String>('${widget.keyPrefix}-${entry.$2}'),
                    bodyGlobalKey: _keyForValue(entry.$2),
                    value: entry.$2,
                    label: widget.labelBuilder?.call(entry.$2) ?? entry.$2,
                    settings: animationSettings,
                    onRemove: widget.onRemove,
                    onDragStarted: _startDrag,
                    onDragEnded: _handleDragEnd,
                    keyPrefix: widget.keyPrefix,
                  ),
                ],
                if (targeted && _hoverInsertIndex == widget.values.length)
                  _AgentChipInsertionIndicator(settings: animationSettings)
                else
                  const SizedBox(
                    width: _agentChipSpacing,
                    height: _agentChipDropSlotExtent,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AgentChipInsertionIndicator extends StatelessWidget {
  const _AgentChipInsertionIndicator({required this.settings});

  final DialogAnimationSettings settings;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: settings.duration,
      curve: settings.curve.curve,
      width: _agentChipDropSlotExtent,
      height: _agentChipDropSlotExtent,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.14),
        borderRadius: kOpenHandPillBorderRadius,
      ),
      child: Icon(
        Icons.keyboard_double_arrow_right_rounded,
        size: 16,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

class _AgentReorderableChip extends StatelessWidget {
  const _AgentReorderableChip({
    super.key,
    required this.bodyGlobalKey,
    required this.value,
    required this.label,
    required this.settings,
    required this.onRemove,
    required this.onDragStarted,
    required this.onDragEnded,
    required this.keyPrefix,
  });

  final GlobalKey bodyGlobalKey;
  final String value;
  final String label;
  final DialogAnimationSettings settings;
  final ValueChanged<String> onRemove;
  final ValueChanged<String> onDragStarted;
  final void Function(String value, Offset feedbackTopLeft) onDragEnded;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return AnimatedRemovableChip(
      settings: settings,
      onRemove: () => onRemove(value),
      builder: (context, requestRemove) {
        return KeyedSubtree(
          key: bodyGlobalKey,
          child: _AgentDraggableChip(
            key: ValueKey<String>('$keyPrefix-drag-$value'),
            label: label,
            value: value,
            onDeleted: requestRemove,
            onDragStarted: onDragStarted,
            onDragEnded: onDragEnded,
            bodyKey: ValueKey<String>('$keyPrefix-body-$value'),
          ),
        );
      },
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
      duration: settings.entranceDuration,
      reverseDuration: settings.exitDuration,
      transitionBuilder: (child, animation) => _agentDialogSwitchTransition(
        settings: settings,
        animation: animation,
        child: child,
      ),
      child: child,
    );
  }
}

class _AgentChipDragPayload {
  const _AgentChipDragPayload({required this.value});

  final String value;
}

class _AgentDraggableChip extends StatelessWidget {
  const _AgentDraggableChip({
    super.key,
    required this.label,
    required this.value,
    required this.onDeleted,
    required this.onDragStarted,
    required this.onDragEnded,
    required this.bodyKey,
  });

  final String label;
  final String value;
  final VoidCallback onDeleted;
  final ValueChanged<String> onDragStarted;
  final void Function(String value, Offset feedbackTopLeft) onDragEnded;
  final Key bodyKey;

  @override
  Widget build(BuildContext context) {
    final body = _AgentDraggableChipBody(
      key: bodyKey,
      label: label,
      onDeleted: onDeleted,
      dragging: false,
    );
    return Draggable<_AgentChipDragPayload>(
      data: _AgentChipDragPayload(value: value),
      hitTestBehavior: HitTestBehavior.translucent,
      onDragStarted: () => onDragStarted(value),
      onDragEnd: (details) => onDragEnded(value, details.offset),
      rootOverlay: true,
      feedback: _AgentDraggableChipFeedback(
        child: _AgentDraggableChipBody(
          label: label,
          onDeleted: () {},
          dragging: true,
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.46, child: body),
      child: body,
    );
  }
}

class _AgentDraggableChipFeedback extends StatelessWidget {
  const _AgentDraggableChipFeedback({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Transform.scale(
        scale: 1.04,
        child: Material(
          color: Colors.transparent,
          elevation: 6,
          borderRadius: kOpenHandPillBorderRadius,
          child: child,
        ),
      ),
    );
  }
}

class _AgentDraggableChipBody extends StatelessWidget {
  const _AgentDraggableChipBody({
    super.key,
    required this.label,
    required this.onDeleted,
    required this.dragging,
  });

  final String label;
  final VoidCallback onDeleted;
  final bool dragging;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return MouseRegion(
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
          child: Stack(
            clipBehavior: Clip.none,
            alignment: AlignmentDirectional.centerEnd,
            children: [
              AnimatedContainer(
                duration: openHandMotionDuration(
                  context,
                  kThemeAnimationDuration,
                ),
                curve: kOpenHandSwitchInCurve,
                decoration: BoxDecoration(
                  color: dragging
                      ? colors.surfaceContainerHighest
                      : colors.surfaceContainerHighest.withValues(alpha: 0.46),
                  borderRadius: kOpenHandPillBorderRadius,
                  border: Border.all(
                    color: dragging ? colors.primary : colors.outlineVariant,
                  ),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: 28,
                    maxWidth: 304,
                  ),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: 8,
                      end: 40,
                      top: 6,
                      bottom: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.drag_indicator_rounded,
                          size: 18,
                          color: colors.onSurfaceVariant,
                        ),
                        kOpenHandHGap6,
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
              PositionedDirectional(
                end: 4,
                child: IconButton(
                  tooltip: openHandLocalizedText(
                    context,
                    zh: '删除',
                    en: 'Remove',
                  ),
                  onPressed: dragging ? null : onDeleted,
                  icon: const Icon(Icons.close_rounded),
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
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

DialogAnimationSettings _agentChipAnimationSettings(BuildContext context) {
  if (!openHandTickerMotionEnabled(context)) {
    return OpenHandMotionDefaults.disabled;
  }
  return openHandMotionSettingsOf(context, OpenHandMotionSettingsScope.chip);
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final optionIds = options
        .where((option) => option.enabled)
        .map((option) => option.id)
        .toSet();
    final selectedCount = selected.intersection(optionIds).length;
    final disabledCount = options.where((option) => !option.enabled).length;
    return _AgentEditorPanel(
      title: title,
      icon: icon,
      child: options.isEmpty
          ? Text(
              l10n.agentsNoOptionsAvailable,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 152),
              child: SingleChildScrollView(
                physics: openHandDialogAwareScrollPhysics(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            openHandLocalizedText(
                              context,
                              zh: disabledCount == 0
                                  ? '已选 $selectedCount/${options.length}'
                                  : '已选 $selectedCount/${options.length} · 全局关闭 $disabledCount',
                              en: disabledCount == 0
                                  ? 'Selected $selectedCount/${options.length}'
                                  : 'Selected $selectedCount/${options.length} · Global off $disabledCount',
                            ),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: selectedCount == optionIds.length
                              ? null
                              : () => onChanged({...selected, ...optionIds}),
                          child: Text(
                            openHandLocalizedText(context, zh: '全选', en: 'All'),
                          ),
                        ),
                        TextButton(
                          onPressed: selectedCount == 0
                              ? null
                              : () => onChanged(selected.difference(optionIds)),
                          child: Text(openHandClearLabel(context)),
                        ),
                      ],
                    ),
                    kOpenHandGap8,
                    _AgentCapabilityChipGrid(
                      options: options,
                      selected: selected,
                      onChanged: onChanged,
                      semanticHintBuilder: _agentCapabilityChipSemanticHint,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _AgentToolCapabilityPanel extends StatelessWidget {
  const _AgentToolCapabilityPanel({
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
    final grouped = <AiAgentBuiltinToolGroup, List<_Option>>{
      for (final group in AiAgentBuiltinToolGroup.values) group: <_Option>[],
    };
    final fallback = <_Option>[];
    for (final option in options) {
      final group = _agentToolKindForOption(option)?.agentToolGroup;
      if (group == null) {
        fallback.add(option);
      } else {
        grouped[group]!.add(option);
      }
    }
    final sections = <Widget>[
      for (final group in AiAgentBuiltinToolGroup.values)
        if (grouped[group]!.isNotEmpty)
          _AgentToolGroupSection(
            group: group,
            options: grouped[group]!,
            selected: selected,
            onChanged: onChanged,
          ),
      if (fallback.isNotEmpty)
        _AgentToolGroupSection(
          group: null,
          options: fallback,
          selected: selected,
          onChanged: onChanged,
        ),
    ];

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
              constraints: const BoxConstraints(maxHeight: 252),
              child: SingleChildScrollView(
                physics: openHandDialogAwareScrollPhysics(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < sections.length; i++) ...[
                      if (i > 0) kOpenHandGap12,
                      sections[i],
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

class _AgentToolGroupSection extends StatelessWidget {
  const _AgentToolGroupSection({
    required this.group,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final AiAgentBuiltinToolGroup? group;
  final List<_Option> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final enabled = options
        .where((option) => selected.contains(option.id))
        .length;
    final globallyDisabledCount = options
        .where((option) => !option.enabled)
        .length;
    final mutationCount = options
        .where(
          (option) =>
              _agentToolKindForOption(option)?.isAgentMutationTool ?? false,
        )
        .length;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.46),
        borderRadius: kOpenHandBorderRadius8,
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.72),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  agentBuiltinToolGroupIcon(group),
                  size: 17,
                  color: colors.primary,
                ),
                kOpenHandHGap7,
                Expanded(
                  child: Text(
                    agentBuiltinToolGroupLabel(context, group),
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  globallyDisabledCount == 0
                      ? openHandLocalizedText(
                          context,
                          zh: '启用 $enabled/${options.length} · 变更 $mutationCount',
                          en: 'Enabled $enabled/${options.length} · Mutating $mutationCount',
                        )
                      : openHandLocalizedText(
                          context,
                          zh: '启用 $enabled/${options.length} · 全局关闭 $globallyDisabledCount',
                          en: 'Enabled $enabled/${options.length} · Global off $globallyDisabledCount',
                        ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            kOpenHandGap8,
            _AgentCapabilityChipGrid(
              options: options,
              selected: selected,
              onChanged: onChanged,
              leadingIconBuilder: (option, _) {
                final kind = _agentToolKindForOption(option);
                final isMutation = kind?.isAgentMutationTool ?? false;
                return isMutation
                    ? Icons.edit_note_rounded
                    : Icons.visibility_outlined;
              },
              semanticHintBuilder: (option) =>
                  _agentToolChipSemanticHint(context, option),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentCapabilityChipGrid extends StatelessWidget {
  const _AgentCapabilityChipGrid({
    required this.options,
    required this.selected,
    required this.onChanged,
    this.leadingIconBuilder,
    this.semanticHintBuilder,
  });

  final List<_Option> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final IconData? Function(_Option option, bool selected)? leadingIconBuilder;
  final String? Function(_Option option)? semanticHintBuilder;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: _agentCapabilityChipSpacing,
      runSpacing: _agentCapabilityChipSpacing,
      children: [
        for (final option in options)
          Builder(
            builder: (context) {
              final isSelected = option.enabled && selected.contains(option.id);
              return _AgentCapabilityChoiceChip(
                key: ValueKey<String>('agent-capability-chip-${option.id}'),
                label: option.label,
                selected: isSelected,
                enabled: option.enabled,
                leadingIcon: leadingIconBuilder?.call(option, isSelected),
                semanticHint: semanticHintBuilder?.call(option),
                onSelected: option.enabled
                    ? (value) {
                        final next = {...selected};
                        value ? next.add(option.id) : next.remove(option.id);
                        onChanged(next);
                      }
                    : null,
              );
            },
          ),
      ],
    );
  }
}

class _AgentCapabilityChoiceChip extends StatefulWidget {
  const _AgentCapabilityChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onSelected,
    this.leadingIcon,
    this.semanticHint,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final ValueChanged<bool>? onSelected;
  final IconData? leadingIcon;
  final String? semanticHint;

  @override
  State<_AgentCapabilityChoiceChip> createState() =>
      _AgentCapabilityChoiceChipState();
}

class _AgentCapabilityChoiceChipState
    extends State<_AgentCapabilityChoiceChip> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  bool get _interactive => widget.enabled && widget.onSelected != null;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  void _setFocused(bool value) {
    if (_focused == value) return;
    setState(() => _focused = value);
  }

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  void didUpdateWidget(covariant _AgentCapabilityChoiceChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_interactive) return;
    if (_hovered || _focused || _pressed) {
      _hovered = false;
      _focused = false;
      _pressed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final duration = openHandMotionDurationMs(
      context,
      _agentCapabilityChipStateDurationMs,
    );
    final activeVisual = _interactive && (_hovered || _focused);
    final scale = !_interactive
        ? 1.0
        : _pressed
        ? 0.985
        : activeVisual
        ? 1.012
        : 1.0;
    final foreground = _agentCapabilityChipForeground(colors);
    final background = _agentCapabilityChipBackground(colors, activeVisual);
    final border = _agentCapabilityChipBorder(colors, activeVisual);
    final shadow = _interactive && activeVisual
        ? [
            BoxShadow(
              color: colors.primary.withValues(alpha: 0.10),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ]
        : const <BoxShadow>[];

    final chip = AnimatedScale(
      duration: duration,
      curve: kOpenHandSwitchInCurve,
      scale: scale,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: _agentCapabilityChipMinHeight,
          maxWidth: _agentCapabilityChipMaxWidth,
        ),
        child: AnimatedContainer(
          duration: duration,
          curve: kOpenHandSwitchInCurve,
          padding: _agentCapabilityChipPadding,
          decoration: BoxDecoration(
            color: background,
            borderRadius: kOpenHandPillBorderRadius,
            border: Border.all(color: border, width: widget.selected ? 1.5 : 1),
            boxShadow: shadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.leadingIcon != null)
                _AgentCapabilityChipIconSlot(
                  icon: widget.leadingIcon,
                  color: foreground,
                  duration: duration,
                ),
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      selected: widget.selected,
      enabled: _interactive,
      label: widget.label,
      hint: widget.semanticHint,
      child: MouseRegion(
        cursor: _interactive
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: Material(
          type: MaterialType.transparency,
          borderRadius: kOpenHandPillBorderRadius,
          child: InkWell(
            borderRadius: kOpenHandPillBorderRadius,
            canRequestFocus: _interactive,
            onTap: _interactive
                ? () => widget.onSelected?.call(!widget.selected)
                : null,
            onHover: _interactive ? _setHovered : null,
            onFocusChange: _interactive ? _setFocused : null,
            onHighlightChanged: _interactive ? _setPressed : null,
            child: chip,
          ),
        ),
      ),
    );
  }

  Color _agentCapabilityChipForeground(ColorScheme colors) {
    if (!widget.enabled) {
      return colors.onSurfaceVariant.withValues(alpha: 0.46);
    }
    if (widget.selected) return colors.onPrimaryContainer;
    return colors.onSurface;
  }

  Color _agentCapabilityChipBackground(ColorScheme colors, bool activeVisual) {
    if (!widget.enabled) {
      return colors.surfaceContainerHighest.withValues(alpha: 0.30);
    }
    if (widget.selected) {
      return activeVisual
          ? colors.primaryContainer.withValues(alpha: 0.98)
          : colors.primaryContainer.withValues(alpha: 0.88);
    }
    return activeVisual
        ? colors.surfaceContainerHighest.withValues(alpha: 0.76)
        : colors.surfaceContainerHighest.withValues(alpha: 0.48);
  }

  Color _agentCapabilityChipBorder(ColorScheme colors, bool activeVisual) {
    if (!widget.enabled) {
      return colors.outlineVariant.withValues(alpha: 0.54);
    }
    if (widget.selected) {
      return colors.primary.withValues(alpha: activeVisual ? 0.74 : 0.56);
    }
    return colors.outlineVariant.withValues(alpha: activeVisual ? 0.92 : 0.72);
  }
}

class _AgentCapabilityChipIconSlot extends StatelessWidget {
  const _AgentCapabilityChipIconSlot({
    required this.icon,
    required this.color,
    required this.duration,
  });

  final IconData? icon;
  final Color color;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _agentCapabilityChipIconSlotWidth,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: AnimatedOpacity(
          duration: duration,
          curve: kOpenHandSwitchInCurve,
          opacity: icon == null ? 0 : 1,
          child: Icon(icon ?? Icons.check_rounded, size: 17, color: color),
        ),
      ),
    );
  }
}

class _AgentNumberStepperField extends StatefulWidget {
  const _AgentNumberStepperField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  State<_AgentNumberStepperField> createState() =>
      _AgentNumberStepperFieldState();
}

class _AgentNumberStepperFieldState extends State<_AgentNumberStepperField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  int get _lowerBound => math.min(widget.min, widget.max);
  int get _upperBound => math.max(widget.min, widget.max);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${_normalized(widget.value)}');
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _AgentNumberStepperField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final boundsChanged =
        oldWidget.min != widget.min || oldWidget.max != widget.max;
    final valueChanged = oldWidget.value != widget.value;
    final normalized = _normalized(widget.value);
    final parsedText = _parsedText(_controller.text);
    final shouldSync =
        !_focusNode.hasFocus ||
        (boundsChanged && !_isTextValueWithinBounds(parsedText)) ||
        (valueChanged && parsedText != normalized);
    if (shouldSync) {
      _setControllerText(normalized);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) {
      _commitText();
    }
    if (mounted) {
      setState(() {});
    }
  }

  int _normalized(int value) {
    return value.clamp(_lowerBound, _upperBound).toInt();
  }

  int? _parsedText(String raw) {
    return int.tryParse(raw.trim());
  }

  bool _isTextValueWithinBounds(int? value) {
    return value != null && value >= _lowerBound && value <= _upperBound;
  }

  int _currentValue() {
    final parsed = _parsedText(_controller.text);
    return _normalized(parsed ?? widget.value);
  }

  void _setControllerText(int value) {
    final text = '$value';
    if (_controller.text == text) return;
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _commitValue(int value) {
    final normalized = _normalized(value);
    _setControllerText(normalized);
    if (normalized != widget.value) {
      widget.onChanged(normalized);
    }
  }

  void _commitText() {
    _commitValue(_currentValue());
  }

  void _handleTextChanged(String raw) {
    final parsed = _parsedText(raw);
    if (_isTextValueWithinBounds(parsed) && parsed != widget.value) {
      widget.onChanged(parsed!);
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _stepBy(int delta) {
    _commitValue(_currentValue() + delta);
  }

  @override
  Widget build(BuildContext context) {
    final value = _currentValue();
    final canDecrease = value > _lowerBound;
    final canIncrease = value < _upperBound;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final settings = _agentDialogAnimationSettings(context);
    final focused = _focusNode.hasFocus;
    final maxDigits = math.max(1, _upperBound.toString().length);
    final editableWidth = math.max(
      _agentNumberStepperEditableMinWidth,
      maxDigits * _agentNumberStepperEditableDigitWidth + 18,
    );
    final numberTextStyle =
        (theme.textTheme.titleLarge ??
                const TextStyle(fontSize: _agentNumberStepperTextFallbackSize))
            .copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
              height: _agentNumberStepperTextLineHeight,
            );
    final numberFontSize =
        numberTextStyle.fontSize ?? _agentNumberStepperTextFallbackSize;
    final editableLineHeight = math.min(
      _agentNumberStepperEditableHeight,
      MediaQuery.textScalerOf(context).scale(numberFontSize) *
          _agentNumberStepperTextLineHeight,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final labelMaxWidth = math.max(0.0, constraints.maxWidth - 32);
        return SizedBox(
          height: _agentNumberStepperFieldExtent,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                top: _agentNumberStepperControlTopInset,
                child: AnimatedContainer(
                  duration: settings.duration,
                  curve: settings.curve.curve,
                  decoration: BoxDecoration(
                    color: focused
                        ? cs.primaryContainer.withValues(alpha: 0.08)
                        : cs.surfaceContainerHighest.withValues(alpha: 0.34),
                    borderRadius: BorderRadius.circular(
                      _agentNumberStepperControlRadius,
                    ),
                    border: Border.all(
                      color: focused
                          ? cs.primary.withValues(alpha: 0.76)
                          : cs.outlineVariant.withValues(alpha: 0.88),
                      width: focused ? 1.35 : 1,
                    ),
                    boxShadow: focused
                        ? [
                            BoxShadow(
                              color: cs.primary.withValues(alpha: 0.10),
                              blurRadius: 16,
                              offset: const Offset(0, 5),
                            ),
                          ]
                        : const <BoxShadow>[],
                  ),
                ),
              ),
              PositionedDirectional(
                top: 0,
                start: 16,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: labelMaxWidth),
                  child: AnimatedContainer(
                    duration: settings.duration,
                    curve: settings.curve.curve,
                    padding: _agentNumberStepperLabelPadding,
                    decoration: BoxDecoration(
                      color: focused
                          ? cs.primaryContainer.withValues(alpha: 0.54)
                          : cs.surface.withValues(alpha: 0.92),
                      borderRadius: kOpenHandPillBorderRadius,
                    ),
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: focused ? cs.primary : cs.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                top: _agentNumberStepperControlTopInset,
                child: Padding(
                  padding: _agentNumberStepperContentPadding,
                  child: Row(
                    children: [
                      _AgentNumberStepperButton(
                        icon: Icons.remove_rounded,
                        enabled: canDecrease,
                        tooltip: openHandLocalizedText(
                          context,
                          zh: '减少',
                          en: 'Decrease',
                        ),
                        onPressed: () => _stepBy(-1),
                      ),
                      Expanded(
                        child: Center(
                          child: SizedBox(
                            width: editableWidth,
                            height: _agentNumberStepperEditableHeight,
                            child: Center(
                              child: SizedBox(
                                height: editableLineHeight,
                                child: EditableText(
                                  controller: _controller,
                                  focusNode: _focusNode,
                                  textAlign: TextAlign.center,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.done,
                                  inputFormatters: <TextInputFormatter>[
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(maxDigits),
                                  ],
                                  style: numberTextStyle,
                                  strutStyle: StrutStyle(
                                    fontSize: numberFontSize,
                                    height: _agentNumberStepperTextLineHeight,
                                    leading: 0,
                                    forceStrutHeight: true,
                                  ),
                                  cursorColor: cs.primary,
                                  cursorHeight:
                                      editableLineHeight *
                                      _agentNumberStepperCursorHeightFactor,
                                  backgroundCursorColor: cs.outlineVariant,
                                  selectionColor: cs.primary.withValues(
                                    alpha: 0.22,
                                  ),
                                  onChanged: _handleTextChanged,
                                  onSubmitted: (_) => _commitText(),
                                  onEditingComplete: _commitText,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      _AgentNumberStepperButton(
                        icon: Icons.add_rounded,
                        enabled: canIncrease,
                        tooltip: openHandLocalizedText(
                          context,
                          zh: '增加',
                          en: 'Increase',
                        ),
                        onPressed: () => _stepBy(1),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AgentNumberStepperButton extends StatefulWidget {
  const _AgentNumberStepperButton({
    required this.icon,
    required this.enabled,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final bool enabled;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  State<_AgentNumberStepperButton> createState() =>
      _AgentNumberStepperButtonState();
}

class _AgentNumberStepperButtonState extends State<_AgentNumberStepperButton> {
  bool _hovered = false;
  bool _pressed = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  void didUpdateWidget(covariant _AgentNumberStepperButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && (_hovered || _pressed)) {
      _hovered = false;
      _pressed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final duration = openHandMotionDurationMs(
      context,
      _agentNumberStepperStateDurationMs,
    );
    final active = widget.enabled && (_hovered || _pressed);
    final scale = !widget.enabled
        ? 1.0
        : _pressed
        ? 0.90
        : _hovered
        ? 1.05
        : 1.0;
    final foreground = widget.enabled
        ? cs.onSurface
        : cs.onSurfaceVariant.withValues(alpha: 0.46);
    final background = !widget.enabled
        ? cs.surfaceContainerHighest.withValues(alpha: 0.18)
        : active
        ? cs.primaryContainer.withValues(alpha: 0.68)
        : cs.surface.withValues(alpha: 0.72);
    final border = !widget.enabled
        ? cs.outlineVariant.withValues(alpha: 0.28)
        : active
        ? cs.primary.withValues(alpha: 0.42)
        : cs.outlineVariant.withValues(alpha: 0.60);
    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: widget.enabled ? (_) => _setHovered(true) : null,
      onExit: (_) {
        _setHovered(false);
        _setPressed(false);
      },
      child: Listener(
        onPointerDown: widget.enabled ? (_) => _setPressed(true) : null,
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: Tooltip(
          message: widget.tooltip,
          child: Semantics(
            button: true,
            enabled: widget.enabled,
            child: AnimatedScale(
              duration: duration,
              curve: kOpenHandSwitchInCurve,
              scale: scale,
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: widget.enabled ? widget.onPressed : null,
                  child: AnimatedContainer(
                    duration: duration,
                    curve: kOpenHandSwitchInCurve,
                    width: _agentNumberStepperButtonExtent,
                    height: _agentNumberStepperButtonExtent,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: background,
                      border: Border.all(color: border),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      widget.icon,
                      size: _agentNumberStepperIconSize,
                      color: foreground,
                    ),
                  ),
                ),
              ),
            ),
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
      if (value.trim().toLowerCase() == 'null') return '';
      return clipTextByCodeUnits(
        value,
        _agentStructuredFieldValueMaxChars,
        suffix: '...[已截断]',
      );
    }
    return jsonEncode(
      convertToJsonSafeValue(
        value,
        config: _agentStructuredValueConversionConfig,
      ),
    );
  }
}

List<_KeyValueDraft> _keyValueEntriesFromMap(Map<String, Object?>? map) {
  if (map == null || map.isEmpty) return <_KeyValueDraft>[];
  return map.entries
      .take(_agentStructuredFieldMaxItems)
      .map(
        (entry) => _KeyValueDraft(
          key: clipTextByCodeUnits(entry.key, _agentStructuredFieldKeyMaxChars),
          value: entry.value,
        ),
      )
      .toList();
}

Map<String, Object?> _agentKeyValueDraftMapFromEntries(
  Iterable<_KeyValueDraft> entries,
) {
  final result = <String, Object?>{};
  for (final entry in entries) {
    if (result.length >= _agentStructuredFieldMaxItems) break;
    final key = clipTextByCodeUnits(
      entry.key.text.trim(),
      _agentStructuredFieldKeyMaxChars,
    );
    if (key.isEmpty) continue;
    result[key] = _agentParseStructuredValue(entry.value.text);
  }
  return result;
}

String? _agentFirstDuplicateKey(Iterable<_KeyValueDraft> entries) {
  final seen = <String>{};
  for (final entry in entries) {
    final key = clipTextByCodeUnits(
      entry.key.text.trim(),
      _agentStructuredFieldKeyMaxChars,
    );
    if (key.isEmpty) continue;
    final normalized = key.toLowerCase();
    if (!seen.add(normalized)) return key;
  }
  return null;
}

String? _agentFirstReservedKey(
  Iterable<_KeyValueDraft> entries,
  Set<String> reservedKeys,
) {
  for (final entry in entries) {
    final key = entry.key.text.trim();
    if (reservedKeys.contains(key.toLowerCase())) return key;
  }
  return null;
}

bool _agentStructuredFieldsWithinLimits(Iterable<_KeyValueDraft> entries) {
  final values = <String, Object?>{};
  for (final entry in entries) {
    final key = entry.key.text.trim();
    if (key.isEmpty) continue;
    final raw = entry.value.text.trim();
    if (key.length > _agentStructuredFieldKeyMaxChars ||
        raw.length > _agentStructuredFieldValueMaxChars) {
      return false;
    }
    Object? value = raw;
    if (raw.isEmpty || raw.toLowerCase() == 'null') {
      value = '';
    } else {
      try {
        value = jsonDecode(raw);
      } on FormatException {
        value = raw;
      }
    }
    values[key] = value;
  }
  return _agentJsonValueWithinLimits(
    values,
    maxDepth: _agentStructuredFieldMaxDepth + 1,
  );
}

bool _agentStructuredTextWithinLimits(String raw) {
  final text = raw.trim();
  if (text.isEmpty || text.toLowerCase() == 'null') return true;
  Object? value;
  try {
    value = jsonDecode(text);
  } on FormatException {
    return true;
  }
  return _agentJsonValueWithinLimits(value);
}

bool _agentJsonValueWithinLimits(
  Object? value, {
  int maxDepth = _agentStructuredFieldMaxDepth,
}) {
  try {
    validateCanonicalJsonSubset(
      value,
      value,
      maxDepth: maxDepth,
      maxContainerItems: _agentStructuredFieldMaxItems,
      maxTotalNodes: _agentStructuredFieldMaxNodes,
    );
    return true;
  } on FormatException {
    return false;
  }
}

String _agentStructuredFieldsLimitMessage(
  BuildContext context, {
  required String zhSubject,
  required String enSubject,
}) {
  return openHandLocalizedText(
    context,
    zh:
        '$zhSubject 超过限制：键最多 $_agentStructuredFieldKeyMaxChars 个字符、'
        '值最多 $_agentStructuredFieldValueMaxChars 个字符，结构最多 '
        '$_agentStructuredFieldMaxDepth 层、$_agentStructuredFieldMaxItems 个集合项和 '
        '$_agentStructuredFieldMaxNodes 个节点。',
    en:
        '$enSubject exceeds the limits: keys $_agentStructuredFieldKeyMaxChars characters, '
        'values $_agentStructuredFieldValueMaxChars characters, and structures '
        '$_agentStructuredFieldMaxDepth levels, $_agentStructuredFieldMaxItems collection items, '
        'and $_agentStructuredFieldMaxNodes nodes.',
  );
}

Object? _agentParseStructuredValue(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '';
  if (value.toLowerCase() == 'null') return '';
  if (value.length > _agentStructuredFieldValueMaxChars) {
    return clipTextByCodeUnits(
      value,
      _agentStructuredFieldValueMaxChars,
      suffix: '...[已截断]',
    );
  }
  try {
    return convertToJsonSafeValue(
      jsonDecode(value),
      config: _agentStructuredValueConversionConfig,
    );
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

AiBuiltinToolKind? _agentToolKindForOption(_Option option) {
  final normalized = option.id.trim().toLowerCase();
  for (final kind in AiBuiltinToolKind.values) {
    if (kind.name.toLowerCase() == normalized) return kind;
  }
  return null;
}

_Option _agentToolOption(
  BuildContext context,
  String id,
  AiBuiltinToolKind kind, {
  bool enabled = true,
}) {
  final toolName = agentBuiltinToolCanonicalName(kind);
  final summary = agentBuiltinToolSummary(context, kind);
  return _Option(
    id,
    agentBuiltinToolLabel(context, kind),
    '$toolName · $summary',
    enabled: enabled,
  );
}

String? _agentCapabilityChipSemanticHint(_Option option) {
  final subtitle = option.subtitle.trim();
  return subtitle.isEmpty ? null : subtitle;
}

String _agentToolChipSemanticHint(BuildContext context, _Option option) {
  final kind = _agentToolKindForOption(option);
  final isMutation = kind?.isAgentMutationTool ?? false;
  if (!option.enabled) {
    return openHandLocalizedText(
      context,
      zh: '${option.label} 已在全局内建工具设置中关闭，需先全局启用后才能绑定。',
      en: '${option.label} is disabled in global built-in tool settings. Enable it globally before binding.',
    );
  }
  if (isMutation) {
    return openHandLocalizedText(
      context,
      zh: '${option.label} 会变更智能体任务、审批、KPI、资源或集群状态。',
      en: '${option.label} can mutate agent tasks, approvals, KPI, resources, or cluster state.',
    );
  }
  return openHandLocalizedText(
    context,
    zh: '${option.label} 仅查询智能体上下文或进度。',
    en: '${option.label} only reads agent context or progress.',
  );
}

String _agentInstructionOptionSubtitle(
  BuildContext context,
  UserInstructionEntry entry,
) {
  final parts = <String>[
    if (entry.description.trim().isNotEmpty) entry.description.trim(),
    if (entry.applyTo.trim().isNotEmpty)
      openHandLocalizedText(
        context,
        zh: '适用：${entry.applyTo.trim()}',
        en: 'Applies to: ${entry.applyTo.trim()}',
      ),
    if (entry.taskTypes.isNotEmpty)
      openHandLocalizedText(
        context,
        zh: '任务：${entry.taskTypes.take(3).join(', ')}',
        en: 'Tasks: ${entry.taskTypes.take(3).join(', ')}',
      ),
  ];
  return parts.isEmpty
      ? openHandLocalizedText(
          context,
          zh: '绑定后会注入智能体运行提示词',
          en: 'Injected into the agent runtime prompt when bound',
        )
      : parts.take(2).join(' · ');
}

String _agentPolicyOptionLabel(BuildContext context, String value) {
  return switch (value) {
    agentSchedulerPolicyLeastBusy => openHandLocalizedText(
      context,
      zh: '空闲优先',
      en: 'Least busy',
      zhHant: '空閒優先',
      fr: 'Moins occupé',
      de: 'Am wenigsten beschäftigt',
      ja: '空き優先',
    ),
    agentSchedulerPolicyPriorityFirst => openHandLocalizedText(
      context,
      zh: '优先级优先',
      en: 'Priority first',
      zhHant: '優先級優先',
      fr: 'Priorité d’abord',
      de: 'Priorität zuerst',
      ja: '優先度優先',
    ),
    agentSchedulerPolicyRoundRobin => openHandLocalizedText(
      context,
      zh: '轮询分配',
      en: 'Round robin',
      zhHant: '輪詢分配',
      fr: 'Tourniquet',
      de: 'Round Robin',
      ja: 'ラウンドロビン',
    ),
    agentWorkerRemovalPolicyNewestFirst => openHandLocalizedText(
      context,
      zh: '最新优先',
      en: 'Newest first',
      zhHant: '最新優先',
      fr: 'Plus récent d’abord',
      de: 'Neueste zuerst',
      ja: '新しい順',
    ),
    agentRetryPolicyBoundedRetry => openHandLocalizedText(
      context,
      zh: '有限重试',
      en: 'Bounded retry',
      zhHant: '有限重試',
      fr: 'Relance limitée',
      de: 'Begrenzte Wiederholung',
      ja: '制限付き再試行',
    ),
    agentRetryPolicyNone => openHandLocalizedText(
      context,
      zh: '不重试',
      en: 'No retry',
      zhHant: '不重試',
      fr: 'Aucune relance',
      de: 'Keine Wiederholung',
      ja: '再試行なし',
    ),
    _ => _agentHumanizedMachineLabel(value),
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
      duration: openHandMotionDuration(context, kThemeAnimationDuration),
      curve: kOpenHandSwitchInCurve,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isActive
            ? colors.primaryContainer.withValues(alpha: 0.34)
            : colors.surfaceContainerHighest.withValues(alpha: 0.66),
        borderRadius: kOpenHandBorderRadius18,
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
          kOpenHandHGap12,
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
                kOpenHandGap4,
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isActive
                        ? colors.onPrimaryContainer
                        : colors.onSurfaceVariant,
                  ),
                ),
                if (keywords.isNotEmpty) ...[
                  kOpenHandGap10,
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
  const _Option(this.id, this.label, this.subtitle, {this.enabled = true});

  final String id;
  final String label;
  final String subtitle;
  final bool enabled;
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

Set<String> _mergeAgentToolSelection({
  required Set<String> current,
  required Set<String> groupSelection,
  required List<_Option> groupOptions,
}) {
  final groupIds = groupOptions.map((option) => option.id).toSet();
  final merged = _mergeOptionGroupSelection(
    current: current,
    groupSelection: groupSelection,
    groupOptions: groupOptions,
  )..remove(agentNoCoordinationToolsBinding);
  if (groupOptions.isNotEmpty &&
      groupSelection.intersection(groupIds).isEmpty) {
    merged.add(agentNoCoordinationToolsBinding);
  }
  return merged;
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
          kOpenHandGap8,
          if (options.isEmpty)
            Text(l10n.agentsNoOptionsAvailable)
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: SingleChildScrollView(
                physics: openHandDialogAwareScrollPhysics(context),
                child: _AgentCapabilityChipGrid(
                  options: options,
                  selected: selected,
                  onChanged: onChanged,
                  semanticHintBuilder: _agentCapabilityChipSemanticHint,
                ),
              ),
            ),
          kOpenHandGap10,
          Text(
            openHandLocalizedText(context, zh: '已选顺序', en: 'Selected order'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          kOpenHandGap6,
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
    final tokenPressure = unitRatio(resource.tokenUsed, resource.tokenBudget);
    final persistedPressure = unitRatio(
      resource.persistedBytes,
      resource.diskBytes,
    );
    return _AgentAuditReportSummary(
      eventCount: agent.auditEvents.length,
      requests: requests,
      tokens: tokens,
      busyWorkers: _agentWorkerStatusCount(agent, AgentWorkerStatus.busy),
      tasks: _agentAuditTaskStats(agent.tasks),
      capabilities: capabilities,
      workers: workers,
      cpuPressure: clampUnitInterval(resource.cpuPercent),
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
    'completed' => openHandCompletedLabel(context),
    'running' => _agentsViewRunningLabel(context),
    'queued' => _agentsViewQueuedLabel(context),
    'blocked' => _agentsViewBlockedLabel(context),
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

double? _agentWorkerCurrentTaskProgress(
  AgentProfile agent,
  AgentWorker worker,
) {
  final taskId = worker.currentTaskId.trim();
  if (taskId.isEmpty) return null;
  final task = _agentTaskById(agent, taskId);
  if (task == null) return null;
  return clampUnitInterval(task.progress);
}

List<String> _agentWorkerDetailChips(
  BuildContext context,
  AgentProfile agent,
  AgentWorker worker,
) {
  final l10n = AppLocalizations.of(context)!;
  final chips = <String>[];
  if (worker.labels.isNotEmpty) {
    chips.add(
      openHandLocalizedText(
        context,
        zh: '标签: ${worker.labels.join(', ')}',
        en: 'Labels: ${worker.labels.join(', ')}',
        zhHant: '標籤: ${worker.labels.join(', ')}',
        fr: 'Libellés: ${worker.labels.join(', ')}',
        de: 'Labels: ${worker.labels.join(', ')}',
        ja: 'ラベル: ${worker.labels.join(', ')}',
      ),
    );
  }
  if (worker.updatedAt != null) {
    final updated = formatMonthDayHmLocal(worker.updatedAt!);
    chips.add(
      openHandLocalizedText(
        context,
        zh: '更新: $updated',
        en: 'Updated: $updated',
        zhHant: '更新: $updated',
        fr: 'Mis à jour: $updated',
        de: 'Aktualisiert: $updated',
        ja: '更新: $updated',
      ),
    );
  }
  final lastAssignedTaskId = '${worker.extra['last_assigned_task_id'] ?? ''}'
      .trim();
  if (lastAssignedTaskId.isNotEmpty) {
    final task = _agentTaskById(agent, lastAssignedTaskId);
    chips.add(
      openHandLocalizedText(
        context,
        zh: '上次分配: ${task?.title ?? lastAssignedTaskId}',
        en: 'Last assigned: ${task?.title ?? lastAssignedTaskId}',
        zhHant: '上次分配: ${task?.title ?? lastAssignedTaskId}',
        fr: 'Dernière attribution: ${task?.title ?? lastAssignedTaskId}',
        de: 'Zuletzt zugewiesen: ${task?.title ?? lastAssignedTaskId}',
        ja: '前回割り当て: ${task?.title ?? lastAssignedTaskId}',
      ),
    );
  }
  final lastFinishedTaskId = '${worker.extra['last_finished_task_id'] ?? ''}'
      .trim();
  if (lastFinishedTaskId.isNotEmpty) {
    final task = _agentTaskById(agent, lastFinishedTaskId);
    chips.add(
      openHandLocalizedText(
        context,
        zh: '上次完成: ${task?.title ?? lastFinishedTaskId}',
        en: 'Last finished: ${task?.title ?? lastFinishedTaskId}',
        zhHant: '上次完成: ${task?.title ?? lastFinishedTaskId}',
        fr: 'Dernière fin: ${task?.title ?? lastFinishedTaskId}',
        de: 'Zuletzt abgeschlossen: ${task?.title ?? lastFinishedTaskId}',
        ja: '前回完了: ${task?.title ?? lastFinishedTaskId}',
      ),
    );
  }
  final lastFinishedStatus = '${worker.extra['last_finished_status'] ?? ''}'
      .trim();
  if (lastFinishedStatus.isNotEmpty) {
    final statusLabel =
        _agentStatusTokenLabel(l10n, lastFinishedStatus) ??
        _agentHumanizedMachineLabel(lastFinishedStatus);
    chips.add(
      openHandLocalizedText(
        context,
        zh: '完成状态: $statusLabel',
        en: 'Finished: $statusLabel',
        zhHant: '完成狀態: $statusLabel',
        fr: 'État final: $statusLabel',
        de: 'Abschlussstatus: $statusLabel',
        ja: '完了状態: $statusLabel',
      ),
    );
  }
  return chips.take(5).toList(growable: false);
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
    final rawName = _agentAuditCapabilityRawName(event);
    final name = rawName.isEmpty
        ? _agentHumanizedMachineLabel(event.kind)
        : rawName;
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
        final worker = agent.workerById(workerId);
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

String _agentAuditCapabilityRawName(AgentAuditEvent event) {
  for (final raw in <Object?>[
    event.toolName,
    event.metadata['tool_name'],
    event.metadata['tool'],
    event.metadata['capability_name'],
  ]) {
    final text = '$raw'.trim();
    if (text.isNotEmpty) return text;
  }
  return '';
}

String _agentAuditCapabilityName(BuildContext context, AgentAuditEvent event) {
  final raw = _agentAuditCapabilityRawName(event);
  if (raw.isNotEmpty) return _agentAuditSourceLabel(context, raw);
  if (event.kind.trim().isNotEmpty) {
    return _agentActivityKindLabel(AppLocalizations.of(context)!, event.kind);
  }
  return openHandLocalizedText(
    context,
    zh: '未知能力',
    en: 'Unknown capability',
    fr: 'Capacité inconnue',
    de: 'Unbekannte Fähigkeit',
    ja: '不明な能力',
  );
}

String _agentAuditSourceLabel(BuildContext context, String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return trimmed;
  final key = _agentAuditSourceLookupKey(trimmed);
  for (final kind in AiBuiltinToolKind.values) {
    if (!kind.isAgentCoordinationTool) continue;
    if (_agentAuditSourceLookupKey(agentBuiltinToolCanonicalName(kind)) ==
            key ||
        _agentAuditSourceLookupKey(kind.name) == key) {
      return agentBuiltinToolLabel(context, kind);
    }
  }
  final l10n = AppLocalizations.of(context)!;
  return switch (key) {
    'agenttaskdesk' => l10n.agentsTaskDesk,
    'agenttaskdialog' => openHandLocalizedText(
      context,
      zh: '任务详情',
      en: 'Task details',
      zhHant: '任務詳情',
      fr: 'Détails de la tâche',
      de: 'Aufgabendetails',
      ja: 'タスク詳細',
    ),
    'agentpublishtaskdialog' => l10n.agentsPublishTask,
    'agentclusterdialog' => l10n.agentsCluster,
    'agentapprovalsdialog' ||
    'agentapprovalrequestdialog' => l10n.agentsApprovals,
    'agentkpidialog' => l10n.agentsKpi,
    'agentresourcesdialog' || 'agentresourcedialog' => l10n.agentsResources,
    'agentauditdialog' => l10n.agentsAuditReport,
    'agentactivitiesdialog' || 'agentactivitydialog' => l10n.agentsActivities,
    'agentcapabilitylogsdialog' || 'agentlogs' => l10n.agentsCapabilityLogs,
    'agenteditordialog' => l10n.agentsEditAgent,
    'agentscontroller' => openHandLocalizedText(
      context,
      zh: '智能体控制器',
      en: 'Agent controller',
      zhHant: '智慧體控制器',
      fr: 'Contrôleur agent',
      de: 'Agent-Controller',
      ja: 'エージェント制御',
    ),
    'agentworker' => _agentsViewWorkerExecutionLabel(context),
    'workerexecution' || 'workerexecutionstatus' => _agentActivityKindLabel(
      l10n,
      'worker_execution',
    ),
    'workerscaledout' => _agentActivityKindLabel(l10n, 'worker_scaled_out'),
    'workerscaledin' => _agentActivityKindLabel(l10n, 'worker_scaled_in'),
    'clusterupdated' => _agentActivityKindLabel(l10n, 'cluster_updated'),
    'auditrecorded' => _agentActivityKindLabel(l10n, 'audit_recorded'),
    _ => trimmed,
  };
}

String _agentAuditSourceLookupKey(String value) {
  return normalizeAsciiLookupKey(value);
}

String _agentAuditSummaryText(BuildContext context, AgentAuditEvent event) {
  final l10n = AppLocalizations.of(context)!;
  final summary = event.summary.trim();
  if (summary.isEmpty ||
      summary == event.kind ||
      _agentLooksLikeMachineToken(summary)) {
    return _agentActivityKindLabel(l10n, event.kind);
  }
  return _agentLocalizedPrefixedMessage(l10n, summary);
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
    'memory' => openHandLocalizedText(
      context,
      zh: '记忆',
      en: 'Memory',
      zhHant: '記憶',
      fr: 'Mémoire',
      de: 'Speicher',
      ja: 'メモリ',
    ),
    'knowledge' => openHandKnowledgeLabel(context),
    'builtin_tool' => openHandLocalizedText(
      context,
      zh: '内建工具',
      en: 'Built-in tool',
      zhHant: '內建工具',
      fr: 'Outil intégré',
      de: 'Integriertes Tool',
      ja: '組み込みツール',
    ),
    'model_request' => openHandLocalizedText(
      context,
      zh: '模型请求',
      en: 'Model request',
      zhHant: '模型請求',
      fr: 'Requête modèle',
      de: 'Modellanfrage',
      ja: 'モデルリクエスト',
    ),
    'resource' => _agentsViewResourceLabel(context),
    'approval' => openHandLocalizedText(
      context,
      zh: '审批',
      en: 'Approval',
      zhHant: '審批',
      fr: 'Approbation',
      de: 'Genehmigung',
      ja: '承認',
    ),
    'kpi' => 'KPI',
    'worker_execution' => _agentsViewWorkerExecutionLabel(context),
    _ => openHandLocalizedText(
      context,
      zh: '其他',
      en: 'Other',
      zhHant: '其他',
      fr: 'Autre',
      de: 'Andere',
      ja: 'その他',
    ),
  };
}

List<String> _agentAuditMetadataChips(
  BuildContext context,
  AgentAuditEvent event,
) {
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
    final text = _agentMetadataChipText(context, key, value);
    if (text != null) chips.add(text);
    if (chips.length >= 4) break;
  }
  return chips;
}

AgentAuditEvent? _agentAuditEventById(AgentProfile agent, String id) {
  final normalized = id.trim();
  if (normalized.isEmpty) return null;
  for (final event in agent.auditEvents) {
    if (event.id == normalized) return event;
  }
  return null;
}

String _agentLogMetadataText(Map<String, Object?> metadata, String key) {
  return '${metadata[key] ?? ''}'.trim();
}

String _agentJoinedText(Iterable<String> values) {
  final normalized = values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
  return normalized.isEmpty ? '-' : normalized.join('\n');
}

Map<String, Object?> _agentLogTaskSnapshot(AgentTask task) {
  return <String, Object?>{
    ...task.toJson(),
    'extra': _agentTaskExtraDisplayJson(task.extra),
  };
}

Map<String, Object?> _agentLogEnvironmentSnapshot(AgentProfile agent) {
  return <String, Object?>{
    'agent': <String, Object?>{
      'id': agent.id,
      'name': agent.name,
      'position': agent.position,
      'department': agent.department,
      'level': agent.level,
      'enabled': agent.enabled,
      'execution_mode': agent.executionMode.storageValue,
      'lifecycle_state': agent.lifecycleState.storageValue,
      'self_learning_enabled': agent.selfLearningEnabled,
      'created_at': agent.createdAt?.toUtc().toIso8601String(),
      'updated_at': agent.updatedAt?.toUtc().toIso8601String(),
    },
    'model': <String, Object?>{
      'model_provider_config_id': agent.modelProviderConfigId,
      'model_id': agent.modelId,
    },
    'workspace': <String, Object?>{
      'path': agent.workspacePath,
      'scope': agent.workspaceScopeText,
      'scope_paths': agent.normalizedWorkspaceScopePaths,
    },
    'bindings': <String, Object?>{
      'skills': agent.skillNames,
      'knowledge_sources': agent.knowledgeSourceIds,
      'memories': agent.memoryIds,
      'mcp_servers': agent.mcpServerNames,
      'builtin_tools': agentVisibleBuiltinToolNames(agent.builtinToolNames),
      'crons': agent.cronIds,
      'hooks': agent.hookIds,
      'instructions': agent.instructionIds,
    },
    'scale_settings': agent.scaleSettings.toJson(),
    'resource_usage': agent.resourceUsage.toJson(includeInternalExtra: false),
    'metadata': agent.metadata,
  };
}

String _agentPrettyJsonForDisplay(Object? value) {
  final encoded = prettyPrintJson(_agentJsonDisplayValue(value));
  return clipTextWithOmissionMarker(
    encoded,
    maxCodeUnits: _agentLogDetailMaxJsonChars,
    marker: 'truncated',
  ).text;
}

Object? _agentJsonDisplayValue(Object? value, {int depth = 0}) {
  if (value == null || value is bool || value is int || value is String) {
    return value is String ? _agentJsonDisplayString(value) : value;
  }
  if (value is double) return value.isFinite ? value : '$value';
  if (value is num) return value;
  if (value is DateTime) return value.toUtc().toIso8601String();
  if (depth >= _agentLogDetailMaxJsonDepth) {
    return '<depth limit>';
  }
  if (value is Map) {
    final entries =
        value.entries
            .take(_agentLogDetailMaxCollectionItems + 1)
            .toList(growable: false)
          ..sort((left, right) => '${left.key}'.compareTo('${right.key}'));
    final result = <String, Object?>{};
    for (final entry in entries.take(_agentLogDetailMaxCollectionItems)) {
      result['${entry.key}'] = _agentJsonDisplayValue(
        entry.value,
        depth: depth + 1,
      );
    }
    if (entries.length > _agentLogDetailMaxCollectionItems) {
      result['_omitted_entries'] = true;
    }
    return result;
  }
  if (value is Iterable) {
    final result = <Object?>[];
    var index = 0;
    for (final item in value) {
      if (index >= _agentLogDetailMaxCollectionItems) {
        result.add(<String, Object?>{'_omitted_items': true});
        break;
      }
      result.add(_agentJsonDisplayValue(item, depth: depth + 1));
      index++;
    }
    return result;
  }
  return '$value';
}

Object _agentJsonDisplayString(String value) {
  if (value.length <= _agentLogDetailMaxStringChars) return value;
  return <String, Object?>{
    'preview': clipTextByCodeUnits(
      value,
      _agentLogDetailMaxStringChars,
      suffix: '...[已截断]',
    ),
    'chars': value.length,
  };
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
  return omitAgentSystemPromptMetadata(extra);
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
  String? zhHant,
  String? fr,
  String? de,
  String? ja,
}) {
  return openHandLocalizedTextForLocaleName(
    l10n.localeName,
    zh: zh,
    en: en,
    zhHant: zhHant,
    fr: fr,
    de: de,
    ja: ja,
  );
}

String _agentActivityKindLabel(AppLocalizations l10n, String kind) {
  final normalized = kind.trim().toLowerCase();
  return switch (normalized) {
    'agent_started' => l10n.agentsActivityAgentStarted,
    'agent_stopped' => l10n.agentsActivityAgentStopped,
    'task_published' => l10n.agentsActivityTaskPublished,
    'task_assigned' => _agentInlineText(
      l10n,
      zh: '任务已分配',
      en: 'Task assigned',
      zhHant: '任務已分配',
      fr: 'Tâche attribuée',
      de: 'Aufgabe zugewiesen',
      ja: 'タスクを割り当てました',
    ),
    'task_updated' => l10n.agentsActivityTaskUpdated,
    'task_canceled' => l10n.agentsActivityTaskCanceled,
    'task_paused' => l10n.agentsActivityTaskPaused,
    'task_terminated' => l10n.agentsActivityTaskTerminated,
    'task_resumed' => l10n.agentsActivityTaskResumed,
    'task_completed' => _agentInlineText(
      l10n,
      zh: '任务已完成',
      en: 'Task completed',
      zhHant: '任務已完成',
      fr: 'Tâche terminée',
      de: 'Aufgabe abgeschlossen',
      ja: 'タスク完了',
    ),
    'task_failed' => _agentInlineText(
      l10n,
      zh: '任务失败',
      en: 'Task failed',
      zhHant: '任務失敗',
      fr: 'Échec de la tâche',
      de: 'Aufgabe fehlgeschlagen',
      ja: 'タスク失敗',
    ),
    'task_retry_scheduled' => _agentInlineText(
      l10n,
      zh: '已安排任务重试',
      en: 'Task retry scheduled',
      zhHant: '已安排任務重試',
      fr: 'Nouvelle tentative planifiée',
      de: 'Aufgabenwiederholung geplant',
      ja: 'タスク再試行を予約しました',
    ),
    'approval_requested' => _agentInlineText(
      l10n,
      zh: '审批已发起',
      en: 'Approval requested',
      zhHant: '審批已發起',
      fr: 'Approbation demandée',
      de: 'Genehmigung angefordert',
      ja: '承認をリクエストしました',
    ),
    'approval_approved' => _agentInlineText(
      l10n,
      zh: '审批已批准',
      en: 'Approval approved',
      zhHant: '審批已批准',
      fr: 'Approbation accordée',
      de: 'Genehmigung erteilt',
      ja: '承認済み',
    ),
    'approval_rejected' => _agentInlineText(
      l10n,
      zh: '审批已拒绝',
      en: 'Approval rejected',
      zhHant: '審批已拒絕',
      fr: 'Approbation refusée',
      de: 'Genehmigung abgelehnt',
      ja: '承認を却下しました',
    ),
    'approval_expired' => _agentInlineText(
      l10n,
      zh: '审批已过期',
      en: 'Approval expired',
      zhHant: '審批已過期',
      fr: 'Approbation expirée',
      de: 'Genehmigung abgelaufen',
      ja: '承認期限切れ',
    ),
    'kpi_upserted' => _agentInlineText(
      l10n,
      zh: 'KPI 已保存',
      en: 'KPI saved',
      zhHant: 'KPI 已儲存',
      fr: 'KPI enregistré',
      de: 'KPI gespeichert',
      ja: 'KPI を保存しました',
    ),
    'kpi_deleted' => _agentInlineText(
      l10n,
      zh: 'KPI 已删除',
      en: 'KPI deleted',
      zhHant: 'KPI 已刪除',
      fr: 'KPI supprimé',
      de: 'KPI gelöscht',
      ja: 'KPI を削除しました',
    ),
    'resource_updated' => _agentInlineText(
      l10n,
      zh: '资源已更新',
      en: 'Resources updated',
      zhHant: '資源已更新',
      fr: 'Ressources mises à jour',
      de: 'Ressourcen aktualisiert',
      ja: 'リソースを更新しました',
    ),
    'audit_recorded' => _agentInlineText(
      l10n,
      zh: '审计已记录',
      en: 'Audit recorded',
      zhHant: '稽核已記錄',
      fr: 'Audit enregistré',
      de: 'Audit aufgezeichnet',
      ja: '監査を記録しました',
    ),
    'cluster_updated' => _agentInlineText(
      l10n,
      zh: '集群已更新',
      en: 'Cluster updated',
      zhHant: '叢集已更新',
      fr: 'Cluster mis à jour',
      de: 'Cluster aktualisiert',
      ja: 'クラスターを更新しました',
    ),
    'worker_scaled_out' => _agentInlineText(
      l10n,
      zh: 'Worker 已扩容',
      en: 'Worker scaled out',
      zhHant: 'Worker 已擴容',
      fr: 'Worker ajouté',
      de: 'Worker hochskaliert',
      ja: 'Worker をスケールアウトしました',
    ),
    'worker_scaled_in' => _agentInlineText(
      l10n,
      zh: 'Worker 已缩容',
      en: 'Worker scaled in',
      zhHant: 'Worker 已縮容',
      fr: 'Worker retiré',
      de: 'Worker herunterskaliert',
      ja: 'Worker をスケールインしました',
    ),
    'worker_execution' => _agentInlineText(
      l10n,
      zh: 'Worker 执行',
      en: 'Worker execution',
      zhHant: 'Worker 執行',
      fr: 'Exécution worker',
      de: 'Worker-Ausführung',
      ja: 'Worker 実行',
    ),
    _ => _agentHumanizedMachineLabel(kind),
  };
}

String _agentActivityTitle(AppLocalizations l10n, AgentActivityEvent event) {
  final title = event.title.trim();
  if (title.isEmpty ||
      title == event.kind ||
      _agentLooksLikeMachineToken(title)) {
    return _agentActivityKindLabel(l10n, event.kind);
  }
  return _agentLocalizedPrefixedMessage(l10n, title);
}

String _agentActivitySubtitle(AppLocalizations l10n, AgentActivityEvent event) {
  final content = event.content.trim();
  if (content.isNotEmpty) {
    if (content == event.kind ||
        content == event.title ||
        _agentLooksLikeMachineToken(content)) {
      return '';
    }
    return _agentLocalizedPrefixedMessage(l10n, content);
  }
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
    _ => _agentActivityMetadataFallback(l10n, event),
  };
}

String _agentLocalizedPrefixedMessage(AppLocalizations l10n, String raw) {
  final match = RegExp(
    r'^([a-z][a-z0-9_]*):\s*(.+)$',
    caseSensitive: false,
  ).firstMatch(raw);
  if (match == null) return _agentLocalizeTerminalStatus(l10n, raw);
  final prefix = match.group(1) ?? '';
  final body = match.group(2) ?? '';
  return '${_agentActivityKindLabel(l10n, prefix)}: '
      '${_agentLocalizeTerminalStatus(l10n, body)}';
}

String _agentLocalizeTerminalStatus(AppLocalizations l10n, String raw) {
  final match = RegExp(r'\(([A-Za-z][A-Za-z0-9_-]*)\)$').firstMatch(raw);
  if (match == null) return raw;
  final localized = _agentStatusTokenLabel(l10n, match.group(1) ?? '');
  if (localized == null) return raw;
  return raw.replaceRange(match.start + 1, match.end - 1, localized);
}

String? _agentStatusTokenLabel(AppLocalizations l10n, String value) {
  return switch (value.trim().toLowerCase()) {
    'queued' || 'backlog' => l10n.agentTaskStatusBacklog,
    'ready' => l10n.agentTaskStatusReady,
    'running' => l10n.agentTaskStatusRunning,
    'waiting_approval' ||
    'pending_approval' => l10n.agentTaskStatusWaitingApproval,
    'paused' => l10n.agentTaskStatusPaused,
    'completed' ||
    'complete' ||
    'success' ||
    'succeeded' => l10n.agentTaskStatusCompleted,
    'failed' || 'failure' || 'error' => l10n.agentTaskStatusFailed,
    'canceled' || 'cancelled' => l10n.agentTaskStatusCanceled,
    'terminated' => _agentInlineText(
      l10n,
      zh: '已终止',
      en: 'Terminated',
      zhHant: '已終止',
      fr: 'Terminé',
      de: 'Beendet',
      ja: '終了済み',
    ),
    'timeout' || 'timed_out' => _agentInlineText(
      l10n,
      zh: '超时',
      en: 'Timed out',
      zhHant: '逾時',
      fr: 'Expiré',
      de: 'Zeitüberschreitung',
      ja: 'タイムアウト',
    ),
    'approved' => _agentInlineText(
      l10n,
      zh: '已批准',
      en: 'Approved',
      zhHant: '已批准',
      fr: 'Approuvé',
      de: 'Genehmigt',
      ja: '承認済み',
    ),
    'rejected' => _agentInlineText(
      l10n,
      zh: '已拒绝',
      en: 'Rejected',
      zhHant: '已拒絕',
      fr: 'Refusé',
      de: 'Abgelehnt',
      ja: '却下済み',
    ),
    'expired' => _agentInlineText(
      l10n,
      zh: '已过期',
      en: 'Expired',
      zhHant: '已過期',
      fr: 'Expiré',
      de: 'Abgelaufen',
      ja: '期限切れ',
    ),
    _ => null,
  };
}

bool _agentLooksLikeMachineToken(String value) {
  return RegExp(
    r'^[a-z][a-z0-9]*(?:_[a-z0-9]+)+$',
  ).hasMatch(value.trim().toLowerCase());
}

String _agentHumanizedMachineLabel(String value) {
  final normalized = value.trim().replaceAll(RegExp(r'[_\s-]+'), ' ');
  if (normalized.isEmpty) return value;
  return normalized
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join(' ');
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
      zhHant: '思考',
      fr: 'Réflexion',
      de: 'Gedanke',
      ja: '思考',
    ),
    AgentActivityMessageType.toolCall => _agentInlineText(
      l10n,
      zh: '工具',
      en: 'Tool',
      zhHant: '工具',
      fr: 'Outil',
      de: 'Tool',
      ja: 'ツール',
    ),
    AgentActivityMessageType.response => _agentInlineText(
      l10n,
      zh: '响应',
      en: 'Response',
      zhHant: '回應',
      fr: 'Réponse',
      de: 'Antwort',
      ja: '応答',
    ),
    AgentActivityMessageType.multimedia => _agentInlineText(
      l10n,
      zh: '多媒体',
      en: 'Media',
      zhHant: '多媒體',
      fr: 'Média',
      de: 'Medien',
      ja: 'メディア',
    ),
    AgentActivityMessageType.task => _agentInlineText(
      l10n,
      zh: '任务',
      en: 'Task',
      zhHant: '任務',
      fr: 'Tâche',
      de: 'Aufgabe',
      ja: 'タスク',
    ),
    AgentActivityMessageType.approval => _agentInlineText(
      l10n,
      zh: '审批',
      en: 'Approval',
      zhHant: '審批',
      fr: 'Approbation',
      de: 'Genehmigung',
      ja: '承認',
    ),
    AgentActivityMessageType.lifecycle => _agentInlineText(
      l10n,
      zh: '生命周期',
      en: 'Lifecycle',
      zhHant: '生命週期',
      fr: 'Cycle de vie',
      de: 'Lebenszyklus',
      ja: 'ライフサイクル',
    ),
    AgentActivityMessageType.system => _agentInlineText(
      l10n,
      zh: '系统',
      en: 'System',
      zhHant: '系統',
      fr: 'Système',
      de: 'System',
      ja: 'システム',
    ),
    AgentActivityMessageType.event => _agentInlineText(
      l10n,
      zh: '事件',
      en: 'Event',
      zhHant: '事件',
      fr: 'Événement',
      de: 'Ereignis',
      ja: 'イベント',
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

List<String> _agentActivityMetadataChips(
  BuildContext context,
  AgentActivityEvent event,
) {
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
    final text = _agentMetadataChipText(context, key, value);
    if (text != null) chips.add(text);
    if (chips.length >= 4) break;
  }
  return chips;
}

String? _agentMetadataChipText(
  BuildContext context,
  String key,
  Object? value,
) {
  final raw = _agentMetadataValueText(context, key, value);
  if (raw.isEmpty) return null;
  final compact = clipText(raw, 61);
  return '${_agentMetadataKeyLabel(context, key)}: $compact';
}

String _agentMetadataValueText(
  BuildContext context,
  String key,
  Object? value,
) {
  if (value == null) return '';
  if (value is bool) return _agentBooleanLabel(context, key, value);
  if (value is DateTime) return formatMonthDayHmLocal(value);
  if (value is Iterable<Object?>) {
    return value
        .map((item) => _agentMetadataValueText(context, key, item))
        .where((item) => item.isNotEmpty)
        .take(3)
        .join(', ');
  }
  if (value is Map<Object?, Object?>) {
    return value.entries
        .map((entry) {
          final entryKey = '${entry.key}'.trim();
          final entryValue = _agentMetadataValueText(
            context,
            entryKey,
            entry.value,
          );
          if (entryKey.isEmpty || entryValue.isEmpty) return '';
          return '${_agentMetadataKeyLabel(context, entryKey)}: $entryValue';
        })
        .where((item) => item.isNotEmpty)
        .take(2)
        .join(', ');
  }
  final raw = '$value'.trim();
  if (raw.isEmpty) return '';
  final parsedBool = optionalBoolFromValue(raw);
  if (parsedBool != null && _agentMetadataBooleanKey(key)) {
    return _agentBooleanLabel(context, key, parsedBool);
  }
  return _agentMetadataDateValue(key, raw) ??
      _agentKnownMetadataValueLabel(context, key, raw) ??
      raw;
}

String _agentMetadataKeyLabel(BuildContext context, String key) {
  return switch (_agentMetadataKey(key)) {
    'assigned_worker_id' => _agentsViewAssignedWorkerLabel(context),
    'worker_id' || 'removed_worker_ids' => openHandLocalizedText(
      context,
      zh: 'Worker ID',
      en: 'Worker ID',
      fr: 'ID worker',
      de: 'Worker-ID',
      ja: 'Worker ID',
    ),
    'task_id' => openHandLocalizedText(
      context,
      zh: '任务 ID',
      en: 'Task ID',
      fr: 'ID de tâche',
      de: 'Aufgaben-ID',
      ja: 'タスク ID',
    ),
    'audit_id' => openHandLocalizedText(
      context,
      zh: '审计 ID',
      en: 'Audit ID',
      fr: 'ID audit',
      de: 'Audit-ID',
      ja: '監査 ID',
    ),
    'kpi_id' => openHandLocalizedText(
      context,
      zh: 'KPI ID',
      en: 'KPI ID',
      fr: 'ID KPI',
      de: 'KPI-ID',
      ja: 'KPI ID',
    ),
    'priority' => _agentsViewPriorityLabel(context),
    'schedule' => openHandLocalizedText(
      context,
      zh: '调度',
      en: 'Schedule',
      fr: 'Planification',
      de: 'Zeitplan',
      ja: 'スケジュール',
    ),
    'retryable' => openHandLocalizedText(
      context,
      zh: '重试',
      zhHant: '重試',
      en: 'Retry',
      fr: 'Réessayer',
      de: 'Erneut versuchen',
      ja: '再試行',
    ),
    'retry_count' => openHandLocalizedText(
      context,
      zh: '重试次数',
      en: 'Retries',
      fr: 'Tentatives',
      de: 'Wiederholungen',
      ja: '再試行回数',
    ),
    'deadline' => openHandLocalizedText(
      context,
      zh: '截止时间',
      en: 'Deadline',
      fr: 'Échéance',
      de: 'Frist',
      ja: '期限',
    ),
    'source' => openHandSourceLabel(context),
    'owner' => openHandLocalizedText(
      context,
      zh: '负责人',
      en: 'Owner',
      fr: 'Responsable',
      de: 'Verantwortlich',
      ja: '所有者',
    ),
    'cadence' => openHandLocalizedText(
      context,
      zh: '节奏',
      en: 'Cadence',
      fr: 'Cadence',
      de: 'Rhythmus',
      ja: '周期',
    ),
    'evidence' => openHandEvidenceLabel(context),
    'workspace_path' || 'resource_path' => openHandPathLabel(context),
    'artifact_count' => openHandLocalizedText(
      context,
      zh: '产物数',
      en: 'Artifacts',
      fr: 'Artefacts',
      de: 'Artefakte',
      ja: '成果物',
    ),
    'cache_bytes' => openHandCacheLabel(context),
    'last_gc_at' => openHandLocalizedText(
      context,
      zh: '上次清理',
      en: 'Last cleanup',
      fr: 'Dernier nettoyage',
      de: 'Letzte Bereinigung',
      ja: '最終クリーンアップ',
    ),
    'quota' => openHandLocalizedText(
      context,
      zh: '配额',
      en: 'Quota',
      fr: 'Quota',
      de: 'Kontingent',
      ja: 'クォータ',
    ),
    'permissions' || 'permission' => openHandLocalizedText(
      context,
      zh: '权限',
      en: 'Permission',
      fr: 'Autorisation',
      de: 'Berechtigung',
      ja: '権限',
    ),
    'scope' => openHandLocalizedText(
      context,
      zh: '范围',
      en: 'Scope',
      fr: 'Périmètre',
      de: 'Umfang',
      ja: '範囲',
    ),
    'resource' => _agentsViewResourceLabel(context),
    'tool_name' || 'tool' => openHandToolLabel(context),
    'mcp_server' => 'MCP',
    'skill_name' => 'Skill',
    'memory_id' => openHandLocalizedText(
      context,
      zh: '记忆 ID',
      en: 'Memory ID',
      fr: 'ID mémoire',
      de: 'Speicher-ID',
      ja: 'メモリ ID',
    ),
    'capability_type' => _agentsViewCapabilityLabel(context),
    'audit_kind' => openHandLocalizedText(
      context,
      zh: '审计类型',
      en: 'Audit type',
      fr: 'Type d’audit',
      de: 'Audit-Typ',
      ja: '監査タイプ',
    ),
    'status' ||
    'task_status' ||
    'kpi_status' ||
    'worker_execution_status' => openHandStatusLabel(context),
    'enabled' => _agentsViewEnabledLabel(context),
    'lifecycle_state' => _agentsViewLifecycleLabel(context),
    'paused_task_count' => openHandLocalizedText(
      context,
      zh: '暂停任务',
      en: 'Paused tasks',
      fr: 'Tâches en pause',
      de: 'Pausierte Aufgaben',
      ja: '一時停止タスク',
    ),
    'released_worker_count' => openHandLocalizedText(
      context,
      zh: '释放 Worker',
      en: 'Released workers',
      fr: 'Workers libérés',
      de: 'Freigegebene Worker',
      ja: '解放 Worker',
    ),
    'delta' => openHandLocalizedText(
      context,
      zh: '变化',
      en: 'Delta',
      fr: 'Variation',
      de: 'Änderung',
      ja: '差分',
    ),
    'worker_count' => openHandLocalizedText(
      context,
      zh: 'Worker 数',
      en: 'Workers',
      fr: 'Workers',
      de: 'Worker',
      ja: 'Worker 数',
    ),
    'ready_task_count' => openHandLocalizedText(
      context,
      zh: '就绪任务',
      en: 'Ready tasks',
      fr: 'Tâches prêtes',
      de: 'Bereite Aufgaben',
      ja: '準備済みタスク',
    ),
    'scale_out_threshold' => _agentsViewScaleOutThresholdLabel(context),
    'scale_in_threshold' => _agentsViewScaleInThresholdLabel(context),
    'worker_removal_policy' => openHandLocalizedText(
      context,
      zh: '缩容策略',
      en: 'Removal policy',
      fr: 'Stratégie de retrait',
      de: 'Entfernungsrichtlinie',
      ja: '削除ポリシー',
    ),
    'expires_at' => openHandLocalizedText(
      context,
      zh: '过期时间',
      en: 'Expires',
      fr: 'Expiration',
      de: 'Läuft ab',
      ja: '有効期限',
    ),
    'duration_ms' => openHandDurationLabel(context),
    'rounds' => openHandLocalizedText(
      context,
      zh: '轮次',
      en: 'Rounds',
      fr: 'Tours',
      de: 'Runden',
      ja: 'ラウンド',
    ),
    'tool_call_count' => openHandLocalizedText(
      context,
      zh: '工具调用',
      en: 'Tool calls',
      fr: 'Appels d’outil',
      de: 'Tool-Aufrufe',
      ja: 'ツール呼び出し',
    ),
    'model_config_id' => _agentsViewModelConfigLabel(context),
    'model_id' => openHandModelLabel(context),
    'error' => openHandErrorLabel(context),
    'task_progress' || 'kpi_progress' => _agentsViewProgressLabel(context),
    'updated_by_session_id' => openHandSessionLabel(context),
    _ => _agentHumanizedMachineLabel(key),
  };
}

String? _agentKnownMetadataValueLabel(
  BuildContext context,
  String key,
  String raw,
) {
  final normalizedKey = _agentMetadataKey(key);
  final normalizedValue = raw.trim().toLowerCase();
  final l10n = AppLocalizations.of(context)!;
  if (normalizedKey.endsWith('_threshold') ||
      normalizedKey.endsWith('_progress')) {
    final numeric = double.tryParse(raw);
    if (numeric != null && numeric >= 0 && numeric <= 1) {
      return '${(numeric * 100).round()}%';
    }
  }
  if (normalizedKey == 'duration_ms') {
    final millis = int.tryParse(raw);
    if (millis != null) return '${millis}ms';
  }
  if (normalizedKey == 'worker_removal_policy' ||
      normalizedKey == 'scheduler_policy' ||
      normalizedKey == 'retry_policy') {
    return _agentPolicyOptionLabel(context, raw);
  }
  if (normalizedKey == 'tool_name' ||
      normalizedKey == 'tool' ||
      normalizedKey == 'capability_name' ||
      normalizedKey == 'recorded_by') {
    return _agentAuditSourceLabel(context, raw);
  }
  if (normalizedKey == 'capability_type') {
    return _agentCapabilityTypeLabel(context, normalizedValue);
  }
  if (normalizedKey == 'audit_kind') {
    return _agentActivityKindLabel(l10n, raw);
  }
  if (normalizedKey == 'kpi_status') {
    return _agentKpiStatusLabel(context, raw);
  }
  if (normalizedKey == 'lifecycle_state') {
    return _agentLifecycleStateValueLabel(l10n, raw);
  }
  return _agentStatusTokenLabel(l10n, raw);
}

String? _agentMetadataDateValue(String key, String raw) {
  final normalizedKey = _agentMetadataKey(key);
  if (!normalizedKey.endsWith('_at') && normalizedKey != 'deadline') {
    return null;
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw;
  return formatMonthDayHmLocal(parsed);
}

String _agentBooleanLabel(BuildContext context, String key, bool value) {
  final normalizedKey = _agentMetadataKey(key);
  if (normalizedKey == 'retryable') {
    return value
        ? openHandLocalizedText(
            context,
            zh: '可重试',
            en: 'Retryable',
            fr: 'Réessayable',
            de: 'Wiederholbar',
            ja: '再試行可',
          )
        : openHandLocalizedText(
            context,
            zh: '不可重试',
            en: 'Not retryable',
            fr: 'Non réessayable',
            de: 'Nicht wiederholbar',
            ja: '再試行不可',
          );
  }
  if (normalizedKey == 'enabled') {
    return value
        ? openHandEnabledLabel(context)
        : openHandLocalizedText(
            context,
            zh: '已停用',
            en: 'Disabled',
            fr: 'Désactivé',
            de: 'Deaktiviert',
            ja: '無効',
          );
  }
  return value ? openHandYesLabel(context) : openHandNoLabel(context);
}

bool _agentMetadataBooleanKey(String key) {
  final normalizedKey = _agentMetadataKey(key);
  return normalizedKey == 'retryable' ||
      normalizedKey == 'enabled' ||
      normalizedKey.endsWith('_enabled') ||
      normalizedKey.endsWith('_required') ||
      normalizedKey.startsWith('allow_');
}

String _agentMetadataKey(String key) {
  return normalizeSnakeStorageKey(key);
}

String _agentLifecycleStateValueLabel(AppLocalizations l10n, String value) {
  return switch (value.trim().toLowerCase()) {
    'running' => _agentInlineText(
      l10n,
      zh: '运行中',
      en: 'Running',
      zhHant: '執行中',
      fr: 'En cours',
      de: 'Läuft',
      ja: '実行中',
    ),
    'paused' => _agentInlineText(
      l10n,
      zh: '已暂停',
      en: 'Paused',
      zhHant: '已暫停',
      fr: 'En pause',
      de: 'Pausiert',
      ja: '一時停止',
    ),
    'degraded' => _agentInlineText(
      l10n,
      zh: '降级',
      en: 'Degraded',
      zhHant: '降級',
      fr: 'Dégradé',
      de: 'Beeinträchtigt',
      ja: '縮退',
    ),
    _ => _agentInlineText(
      l10n,
      zh: '已停止',
      en: 'Stopped',
      zhHant: '已停止',
      fr: 'Arrêté',
      de: 'Gestoppt',
      ja: '停止済み',
    ),
  };
}

String _agentActivityMetadataFallback(
  AppLocalizations l10n,
  AgentActivityEvent event,
) {
  final taskId = event.metadata['task_id'];
  if (taskId != null && '$taskId'.trim().isNotEmpty) {
    final id = '$taskId'.trim();
    return _agentInlineText(
      l10n,
      zh: '任务 ID: $id',
      en: 'Task ID: $id',
      zhHant: '任務 ID: $id',
      fr: 'ID de tâche: $id',
      de: 'Aufgaben-ID: $id',
      ja: 'タスク ID: $id',
    );
  }
  final title = event.title.trim();
  if (title.isEmpty ||
      title == event.kind ||
      _agentLooksLikeMachineToken(title)) {
    return '';
  }
  return _agentLocalizedPrefixedMessage(l10n, title);
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

String _agentsViewAddKpiLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '新增 KPI', en: 'Add KPI');
}

String _agentsViewAssignedWorkerLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '分配 Worker',
    en: 'Assigned worker',
    fr: 'Worker attribué',
    de: 'Zugewiesener Worker',
    ja: '割り当て Worker',
  );
}

String _agentsViewAtRiskLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '有风险', en: 'At risk');
}

String _agentsViewAvgProgressLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '平均进度', en: 'Avg. progress');
}

String _agentsViewBlockedLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '待处理',
    en: 'Blocked',
    fr: 'Bloquées',
    de: 'Blockiert',
    ja: '保留中',
  );
}

String _agentsViewBusyWorkersLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '忙碌 Worker',
    en: 'Busy workers',
    fr: 'Workers occupés',
    de: 'Beschäftigte Worker',
    ja: '稼働中の Worker',
  );
}

String _agentsViewCapabilityLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '能力类型',
    en: 'Capability',
    fr: 'Capacité',
    de: 'Fähigkeit',
    ja: '能力',
  );
}

String _agentsViewDeleteKpiLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '删除 KPI', en: 'Delete KPI');
}

String _agentsViewDoneLabel(BuildContext context) {
  return openHandDoneLabel(context);
}

String _agentsViewEditKpiLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '编辑 KPI', en: 'Edit KPI');
}

String _agentsViewEditResourcesLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '校准资源', en: 'Edit resources');
}

String _agentsViewEnableAgenttasktrackLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '需开启 AgentTaskTrack',
    en: 'Enable AgentTaskTrack',
  );
}

String _agentsViewEnabledLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '启用状态',
    en: 'Enabled',
    fr: 'Activé',
    de: 'Aktiviert',
    ja: '有効',
  );
}

String _agentsViewEnterTextThenAddLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '输入后点击添加',
    en: 'Enter text, then add',
  );
}

String _agentsViewHighRiskLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '高风险', en: 'High risk');
}

String _agentsViewKeyLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '键',
    en: 'Key',
    fr: 'Clé',
    de: 'Schlüssel',
    ja: 'キー',
  );
}

String _agentsViewLifecycleLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '生命周期',
    en: 'Lifecycle',
    fr: 'Cycle de vie',
    de: 'Lebenszyklus',
    ja: 'ライフサイクル',
  );
}

String _agentsViewModelConfigLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '模型配置',
    en: 'Model config',
    fr: 'Config modèle',
    de: 'Modellkonfiguration',
    ja: 'モデル設定',
  );
}

String _agentsViewNoTaskLabelsYetLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '暂无任务标签。',
    en: 'No task labels yet.',
  );
}

String _agentsViewNoWorkerTagsYetLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '暂无 Worker 标签。',
    en: 'No worker tags yet.',
  );
}

String _agentsViewPausedLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '已暂停', en: 'Paused');
}

String _agentsViewPersistedStorageLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '持久化占用',
    en: 'Persisted storage',
    fr: 'Stockage persistant',
    de: 'Persistenter Speicher',
    ja: '永続化ストレージ',
  );
}

String _agentsViewPickDirectoryLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '选择目录', en: 'Pick directory');
}

String _agentsViewPriorityLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '优先级',
    en: 'Priority',
    fr: 'Priorité',
    de: 'Priorität',
    ja: '優先度',
  );
}

String _agentsViewProgressLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '进度',
    en: 'Progress',
    fr: 'Progression',
    de: 'Fortschritt',
    ja: '進捗',
  );
}

String _agentsViewQueuedLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '待执行',
    en: 'Queued',
    fr: 'En attente',
    de: 'In Warteschlange',
    ja: '待機中',
  );
}

String _agentsViewRequestApprovalLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '发起审批', en: 'Request approval');
}

String _agentsViewRequestsLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '请求量', en: 'Requests');
}

String _agentsViewResourceLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '资源',
    en: 'Resource',
    fr: 'Ressource',
    de: 'Ressource',
    ja: 'リソース',
  );
}

String _agentsViewRetryPolicyLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '重试策略', en: 'Retry policy');
}

String _agentsViewRunningLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '执行中',
    zhHant: '執行中',
    en: 'Running',
    fr: 'Exécution',
    de: 'Wird ausgeführt',
    ja: '実行中',
  );
}

String _agentsViewScaleInThresholdLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '缩容阈值',
    en: 'Scale-in threshold',
    fr: 'Seuil de réduction',
    de: 'Herunterskalierungsschwelle',
    ja: 'スケールインしきい値',
  );
}

String _agentsViewScaleOutThresholdLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '扩容阈值',
    en: 'Scale-out threshold',
    fr: 'Seuil de montée',
    de: 'Skalierungsschwelle',
    ja: 'スケールアウトしきい値',
  );
}

String _agentsViewTaskResultLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '任务结果', en: 'Task result');
}

String _agentsViewTrackingLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '跟进中', en: 'Tracking');
}

String _agentsViewUnsetLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '未设置', en: 'unset');
}

String _agentsViewValueLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '值',
    en: 'Value',
    fr: 'Valeur',
    de: 'Wert',
    ja: '値',
  );
}

String _agentsViewWorkerExecutionLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: 'Worker 执行',
    en: 'Worker execution',
    zhHant: 'Worker 執行',
    fr: 'Exécution worker',
    de: 'Worker-Ausführung',
    ja: 'Worker 実行',
  );
}

String _agentsViewWorkerRemovalPolicyLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: 'Worker 移出策略',
    en: 'Worker removal policy',
  );
}

String _agentsViewWorkerTagsLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: 'Worker 标签', en: 'Worker tags');
}
