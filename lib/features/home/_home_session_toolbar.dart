part of 'openhand_home_page.dart';

class _SessionToolbar extends StatelessWidget {
  const _SessionToolbar({
    required this.session,
    this.liveRuntimeToolPreview,
    this.sendPhase = AiSendPhase.idle,
    this.planTimelineCollapsed = false,
    this.onPlanTimelineCollapsedChanged,
    this.fileExplorerVisible = false,
    this.onFileExplorerToggled,
  });

  final AiSession session;
  final AiRuntimeToolPreview? liveRuntimeToolPreview;
  final AiSendPhase sendPhase;
  final bool planTimelineCollapsed;
  final ValueChanged<bool>? onPlanTimelineCollapsedChanged;
  final bool fileExplorerVisible;
  final VoidCallback? onFileExplorerToggled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final runtimeStatus = _runtimeToolCatalogStatus(
      session,
      livePreview: liveRuntimeToolPreview,
    );
    final planTimeline = _buildPlanTimelineData(
      context,
      session,
      sendPhase,
      requiresReview: runtimeStatus.planRecoveryRequired,
    );
    final showPlanTimelineToggle =
        planTimeline != null && onPlanTimelineCollapsedChanged != null;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _AnimatedSessionTitleText(
                        text: session.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const ClampingScrollPhysics(),
                        child: Row(
                          children: [
                            _ToolbarPill(
                              icon: _runtimeModeIcon(runtimeStatus),
                              label: _runtimeModeLabel(
                                context,
                                runtimeStatus,
                                compact: true,
                              ),
                            ),
                            if (runtimeStatus.notices.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              _ToolbarPill(
                                icon: Icons.info_outline_rounded,
                                label: _localizedText(
                                  context,
                                  zh: '运行时 Notice ${runtimeStatus.notices.length}',
                                  en: 'Runtime Notices ${runtimeStatus.notices.length}',
                                ),
                                onTap: () {
                                  _showSessionMetadataDialog(
                                    context,
                                    session,
                                    liveRuntimeToolPreview:
                                        liveRuntimeToolPreview,
                                  );
                                },
                              ),
                            ],
                            const SizedBox(width: 8),
                            _ToolbarPill(
                              icon: Icons.layers_rounded,
                              label:
                                  '${session.templateName} · v${session.templateInternalVersion}',
                            ),
                            const SizedBox(width: 8),
                            _ToolbarPill(
                              icon: Icons.data_object_rounded,
                              label: _localizedText(
                                context,
                                zh: '会话元数据',
                                en: 'Session Metadata',
                              ),
                              onTap: () {
                                _showSessionMetadataDialog(
                                  context,
                                  session,
                                  liveRuntimeToolPreview:
                                      liveRuntimeToolPreview,
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            _ToolbarPill(
                              icon: Icons.update_rounded,
                              label: _formatDateTime(session.updatedAt),
                            ),
                            if (context
                                .watch<SettingsController>()
                                .telemetryDebugEnabled) ...[
                              const SizedBox(width: 8),
                              _ToolbarPill(
                                icon: Icons.fact_check_outlined,
                                label: _localizedText(
                                  context,
                                  zh: '会话审计',
                                  en: 'Session Audit',
                                ),
                                onTap: () {
                                  _showSessionAuditDialog(
                                    context,
                                    session: session,
                                    controller: context
                                        .read<AiSessionController>(),
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (showPlanTimelineToggle && planTimelineCollapsed) ...[
                const SizedBox(width: 10),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _ToolbarPill(
                    key: ValueKey<bool>(planTimelineCollapsed),
                    icon: planTimelineCollapsed
                        ? Icons.unfold_more_rounded
                        : Icons.unfold_less_rounded,
                    label: planTimelineCollapsed
                        ? _localizedText(context, zh: '展开计划', en: 'Show Plan')
                        : _localizedText(context, zh: '收起计划', en: 'Hide Plan'),
                    onTap: () {
                      onPlanTimelineCollapsedChanged?.call(
                        !planTimelineCollapsed,
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(width: 10),
              if (onFileExplorerToggled != null) ...[
                _ToolbarPill(
                  icon: fileExplorerVisible
                      ? Icons.folder_open_rounded
                      : Icons.folder_outlined,
                  label: _localizedText(
                    context,
                    zh: fileExplorerVisible ? '收起项目' : '项目文件',
                    en: fileExplorerVisible ? 'Hide Files' : 'Project Files',
                  ),
                  onTap: onFileExplorerToggled,
                ),
                const SizedBox(width: 10),
              ],
              _TokenDial(
                totalTokens: session.statistics.totalTokens ?? 0,
                cacheReadTokens: session.statistics.cacheReadTokens,
                cacheCreationTokens: session.statistics.cacheCreationTokens,
              ),
            ],
          ),
          AnimatedSwitcher(
            duration: _planTimelineRevealAnimationDuration,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (currentChild, previousChildren) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...previousChildren,
                  currentChild ?? const SizedBox.shrink(),
                ],
              );
            },
            transitionBuilder: (child, animation) {
              final fade = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              );
              return ClipRect(
                child: FadeTransition(
                  opacity: fade,
                  child: SizeTransition(
                    sizeFactor: fade,
                    axisAlignment: -1,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, -0.04),
                        end: Offset.zero,
                      ).animate(fade),
                      child: child,
                    ),
                  ),
                ),
              );
            },
            child: planTimeline == null || planTimelineCollapsed
                ? const SizedBox(key: ValueKey<String>('plan-timeline-hidden'))
                : Padding(
                    key: ValueKey<String>(
                      'plan-timeline-visible-${planTimeline.awaitingApproval}-${planTimeline.requiresReview}-${planTimeline.steps.length}',
                    ),
                    padding: const EdgeInsets.only(top: 12),
                    child: _SessionPlanTimelineBar(
                      data: planTimeline,
                      onVisibilityToggle: showPlanTimelineToggle
                          ? () {
                              onPlanTimelineCollapsedChanged?.call(true);
                            }
                          : null,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ToolbarPill extends StatelessWidget {
  const _ToolbarPill({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final child = Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: _borderRadius999,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) {
      return child;
    }
    return Material(
      color: Colors.transparent,
      borderRadius: _borderRadius999,
      child: InkWell(
        onTap: onTap,
        borderRadius: _borderRadius999,
        overlayColor: WidgetStatePropertyAll<Color>(
          theme.colorScheme.primary.withValues(alpha: 0.08),
        ),
        child: child,
      ),
    );
  }
}

enum _PlanTimelineStepState { completed, current, pending, failed }

class _PlanTimelineStep {
  const _PlanTimelineStep({
    required this.id,
    required this.label,
    required this.state,
  });

  final String id;
  final String label;
  final _PlanTimelineStepState state;
}

class _PlanTimelineData {
  const _PlanTimelineData({
    required this.awaitingApproval,
    required this.requiresReview,
    required this.steps,
  });

  final bool awaitingApproval;
  final bool requiresReview;
  final List<_PlanTimelineStep> steps;

  int get completedStepCount {
    return steps
        .where((item) => item.state == _PlanTimelineStepState.completed)
        .length;
  }

  bool get isComplete {
    return steps.isNotEmpty &&
        steps.every((item) => item.state == _PlanTimelineStepState.completed);
  }

  bool get hasFailedStep {
    return steps.any((item) => item.state == _PlanTimelineStepState.failed);
  }
}

class _SessionPlanTimelineBar extends StatelessWidget {
  const _SessionPlanTimelineBar({required this.data, this.onVisibilityToggle});

  final _PlanTimelineData data;
  final VoidCallback? onVisibilityToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColor = data.awaitingApproval
        ? colorScheme.secondary
        : data.requiresReview
        ? colorScheme.tertiary
        : data.hasFailedStep
        ? colorScheme.error
        : data.isComplete
        ? colorScheme.primary
        : colorScheme.tertiary;
    final headline = data.awaitingApproval
        ? _localizedText(context, zh: '计划待确认', en: 'Plan Awaiting Approval')
        : data.requiresReview
        ? _localizedText(context, zh: '计划待复核', en: 'Plan Needs Review')
        : data.hasFailedStep
        ? _localizedText(context, zh: '计划需要处理', en: 'Plan Needs Attention')
        : data.isComplete
        ? _localizedText(context, zh: '计划已完成', en: 'Plan Completed')
        : _localizedText(context, zh: '计划推进中', en: 'Plan In Progress');
    final subtitle = data.awaitingApproval
        ? _localizedText(
            context,
            zh: '请确认后开始执行',
            en: 'Confirm to begin execution',
          )
        : data.requiresReview
        ? _localizedText(
            context,
            zh: '继续前先检查已完成步骤、产物和 Todo',
            en: 'Inspect completed steps, artifacts, and todos before resuming',
          )
        : data.hasFailedStep
        ? _localizedText(
            context,
            zh: '当前步骤执行失败，请检查后继续',
            en: 'A step failed. Review it and continue.',
          )
        : _localizedText(
            context,
            zh: '已完成 ${data.completedStepCount}/${data.steps.length} 项',
            en: '${data.completedStepCount}/${data.steps.length} steps completed',
          );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: _borderRadius18,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            statusColor.withValues(alpha: 0.08),
            colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
          ],
        ),
        border: Border.all(color: statusColor.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  data.awaitingApproval
                      ? Icons.fact_check_outlined
                      : data.requiresReview
                      ? Icons.manage_search_rounded
                      : data.isComplete
                      ? Icons.task_alt_rounded
                      : Icons.timeline_rounded,
                  size: 16,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
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
              if (onVisibilityToggle != null) ...[
                _PlanTimelineVisibilityButton(
                  label: _localizedText(context, zh: '收起计划', en: 'Hide Plan'),
                  icon: Icons.unfold_less_rounded,
                  color: statusColor,
                  onTap: onVisibilityToggle!,
                ),
                const SizedBox(width: 12),
              ],
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Text(
                  data.awaitingApproval
                      ? _localizedText(context, zh: '等待确认', en: 'Pending')
                      : data.requiresReview
                      ? _localizedText(context, zh: '待复核', en: 'Review')
                      : '${data.completedStepCount}/${data.steps.length}',
                  key: ValueKey<String>(
                    '${data.awaitingApproval}-${data.requiresReview}-${data.completedStepCount}-${data.steps.length}',
                  ),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: Row(
              children: [
                for (var index = 0; index < data.steps.length; index++)
                  _SessionPlanTimelineStepChip(
                    index: index,
                    step: data.steps[index],
                    isLast: index == data.steps.length - 1,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanTimelineVisibilityButton extends StatelessWidget {
  const _PlanTimelineVisibilityButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      borderRadius: _borderRadius999,
      child: InkWell(
        onTap: onTap,
        borderRadius: _borderRadius999,
        overlayColor: WidgetStatePropertyAll<Color>(
          color.withValues(alpha: 0.08),
        ),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: _borderRadius999,
            border: Border.all(color: color.withValues(alpha: 0.20)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionPlanTimelineStepChip extends StatelessWidget {
  const _SessionPlanTimelineStepChip({
    required this.index,
    required this.step,
    required this.isLast,
  });

  final int index;
  final _PlanTimelineStep step;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final state = step.state;
    final accentColor = switch (state) {
      _PlanTimelineStepState.completed => colorScheme.primary,
      _PlanTimelineStepState.current => colorScheme.tertiary,
      _PlanTimelineStepState.failed => colorScheme.error,
      _PlanTimelineStepState.pending => colorScheme.outline,
    };
    final backgroundColor = switch (state) {
      _PlanTimelineStepState.completed => colorScheme.primaryContainer,
      _PlanTimelineStepState.current => colorScheme.tertiaryContainer,
      _PlanTimelineStepState.failed => colorScheme.errorContainer,
      _PlanTimelineStepState.pending => colorScheme.surface,
    };
    final foregroundColor = switch (state) {
      _PlanTimelineStepState.completed => colorScheme.onPrimaryContainer,
      _PlanTimelineStepState.current => colorScheme.onTertiaryContainer,
      _PlanTimelineStepState.failed => colorScheme.onErrorContainer,
      _PlanTimelineStepState.pending => colorScheme.onSurfaceVariant,
    };
    final marker = switch (state) {
      _PlanTimelineStepState.completed => Icon(
        Icons.check_rounded,
        size: 13,
        color: accentColor,
      ),
      _PlanTimelineStepState.current => Icon(
        Icons.play_arrow_rounded,
        size: 13,
        color: accentColor,
      ),
      _PlanTimelineStepState.failed => Icon(
        Icons.close_rounded,
        size: 13,
        color: accentColor,
      ),
      _PlanTimelineStepState.pending => Text(
        '${index + 1}',
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: accentColor,
        ),
      ),
    };
    final chipContent = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.12),
            borderRadius: _borderRadius999,
          ),
          alignment: Alignment.center,
          child: marker,
        ),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(
            step.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: foregroundColor,
            ),
          ),
        ),
      ],
    );
    final chipDecoration = BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: accentColor.withValues(alpha: 0.22)),
      boxShadow: state == _PlanTimelineStepState.current
          ? <BoxShadow>[
              BoxShadow(
                color: accentColor.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ]
          : const <BoxShadow>[],
    );
    final chip = state == _PlanTimelineStepState.current
        ? DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: chipDecoration.boxShadow,
            ),
            child: _SweepBadge(
              backgroundColor: backgroundColor,
              borderColor: accentColor.withValues(alpha: 0.22),
              sweepColor: Colors.white.withValues(alpha: 0.20),
              child: chipContent,
            ),
          )
        : AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: chipDecoration,
            child: chipContent,
          );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        chip,
        if (!isLast)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Container(
              width: 18,
              height: 2,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.28),
                borderRadius: _borderRadius999,
              ),
            ),
          ),
      ],
    );
  }
}

_PlanTimelineData? _buildPlanTimelineData(
  BuildContext context,
  AiSession session,
  AiSendPhase sendPhase, {
  bool requiresReview = false,
}) {
  if (session.mode != AiSessionMode.plan) {
    return null;
  }
  final activePlanRecord = _activePlanRecordForTimeline(session);
  if (activePlanRecord != null) {
    final planRecordTimeline = _buildPlanTimelineDataFromPlanRecord(
      session,
      activePlanRecord,
      sendPhase,
    );
    if (planRecordTimeline != null) {
      return planRecordTimeline;
    }
  }
  if (_shouldSuppressInactivePlanTimeline(session)) {
    return null;
  }
  final reflectRunningStepFailure = _shouldReflectCurrentPlanStepFailure(
    session,
    sendPhase,
  );
  final todoSteps = _planTimelineTodoSteps(
    session.todoItems,
    reflectRunningStepFailure: reflectRunningStepFailure,
    reviewCompletedPlan: _shouldReviewCompletedPlan(session),
    allowTerminalFailureStates: sendPhase == AiSendPhase.idle,
  );
  if (todoSteps.isNotEmpty) {
    return _PlanTimelineData(
      awaitingApproval: session.awaitingPlanApproval,
      requiresReview: requiresReview,
      steps: todoSteps,
    );
  }
  final pendingPlanSteps = _planTimelineStepsFromPendingPlan(
    session.pendingPlan,
  );
  if (pendingPlanSteps.isNotEmpty) {
    return _PlanTimelineData(
      awaitingApproval: session.awaitingPlanApproval,
      requiresReview: false,
      steps: _planTimelinePendingSteps(
        pendingPlanSteps,
        awaitingApproval: session.awaitingPlanApproval,
        idPrefix: 'plan-step',
      ),
    );
  }
  return null;
}

_PlanTimelineData? _buildPlanTimelineDataFromPlanRecord(
  AiSession session,
  AiSessionPlanRecord planRecord,
  AiSendPhase sendPhase,
) {
  if (planRecord.status == AiSessionPlanStatus.cancelled ||
      planRecord.status == AiSessionPlanStatus.completed) {
    return null;
  }
  if (planRecord.status == AiSessionPlanStatus.pendingApproval) {
    final pendingPlanSteps = _planTimelineStepsFromPlanRecord(planRecord);
    if (pendingPlanSteps.isEmpty) {
      return null;
    }
    return _PlanTimelineData(
      awaitingApproval: true,
      requiresReview: false,
      steps: _planTimelinePendingSteps(
        pendingPlanSteps,
        awaitingApproval: true,
        idPrefix: 'plan-step-${planRecord.id}',
      ),
    );
  }
  final effectivePlanRecordFailed =
      planRecord.status == AiSessionPlanStatus.failed &&
      sendPhase == AiSendPhase.idle;
  final todoSteps = _planTimelineTodoSteps(
    planRecord.steps,
    reflectRunningStepFailure:
        effectivePlanRecordFailed ||
        _shouldReflectCurrentPlanStepFailure(session, sendPhase),
    reviewCompletedPlan: false,
    allowTerminalFailureStates: sendPhase == AiSendPhase.idle,
  );
  if (todoSteps.isEmpty) {
    final pendingPlanSteps = _planTimelineStepsFromPlanRecord(planRecord);
    if (pendingPlanSteps.isEmpty) {
      return null;
    }
    return _PlanTimelineData(
      awaitingApproval: false,
      requiresReview: false,
      steps: _planTimelinePendingSteps(
        pendingPlanSteps,
        awaitingApproval: false,
        idPrefix: 'plan-step-${planRecord.id}',
        markCurrentStepFailed: effectivePlanRecordFailed,
      ),
    );
  }
  return _PlanTimelineData(
    awaitingApproval: false,
    requiresReview: false,
    steps: todoSteps,
  );
}

List<_PlanTimelineStep> _planTimelinePendingSteps(
  List<String> stepLabels, {
  required bool awaitingApproval,
  required String idPrefix,
  bool markCurrentStepFailed = false,
}) {
  final normalizedLabels = stepLabels
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  if (normalizedLabels.isEmpty) {
    return const <_PlanTimelineStep>[];
  }
  return normalizedLabels
      .asMap()
      .entries
      .map((entry) {
        final isFirstStep = entry.key == 0;
        return _PlanTimelineStep(
          id: '$idPrefix-${entry.key}',
          label: entry.value,
          state: awaitingApproval
              ? _PlanTimelineStepState.pending
              : isFirstStep
              ? markCurrentStepFailed
                    ? _PlanTimelineStepState.failed
                    : _PlanTimelineStepState.current
              : _PlanTimelineStepState.pending,
        );
      })
      .toList(growable: false);
}

List<_PlanTimelineStep> _planTimelineTodoSteps(
  List<AiSessionTodoItem> todoItems, {
  required bool reflectRunningStepFailure,
  required bool reviewCompletedPlan,
  required bool allowTerminalFailureStates,
}) {
  final todoSteps = <_PlanTimelineStep>[];
  var hasInProgressStep = false;
  var hasFailedStep = false;
  for (final item in todoItems) {
    final label = item.content.trim();
    if (label.isEmpty) {
      continue;
    }
    final state = switch (item.status.trim().toLowerCase()) {
      'completed' => _PlanTimelineStepState.completed,
      'in_progress' when reflectRunningStepFailure =>
        _PlanTimelineStepState.failed,
      'in_progress' => _PlanTimelineStepState.current,
      'failed' || 'blocked' || 'cancelled' when allowTerminalFailureStates =>
        _PlanTimelineStepState.failed,
      'failed' || 'blocked' || 'cancelled' => _PlanTimelineStepState.pending,
      _ => _PlanTimelineStepState.pending,
    };
    if (state == _PlanTimelineStepState.current) {
      hasInProgressStep = true;
    }
    if (state == _PlanTimelineStepState.failed) {
      hasFailedStep = true;
    }
    todoSteps.add(
      _PlanTimelineStep(id: item.id.trim(), label: label, state: state),
    );
  }
  if (todoSteps.isEmpty) {
    return const <_PlanTimelineStep>[];
  }
  if (!hasInProgressStep && !hasFailedStep) {
    final firstPendingIndex = todoSteps.indexWhere(
      (item) => item.state == _PlanTimelineStepState.pending,
    );
    if (firstPendingIndex >= 0) {
      todoSteps[firstPendingIndex] = _PlanTimelineStep(
        id: todoSteps[firstPendingIndex].id,
        label: todoSteps[firstPendingIndex].label,
        state: reflectRunningStepFailure
            ? _PlanTimelineStepState.failed
            : _PlanTimelineStepState.current,
      );
    } else if (reviewCompletedPlan) {
      final lastCompletedIndex = todoSteps.lastIndexWhere(
        (item) => item.state == _PlanTimelineStepState.completed,
      );
      if (lastCompletedIndex >= 0) {
        todoSteps[lastCompletedIndex] = _PlanTimelineStep(
          id: todoSteps[lastCompletedIndex].id,
          label: todoSteps[lastCompletedIndex].label,
          state: _PlanTimelineStepState.current,
        );
      }
    }
  }
  return todoSteps;
}

bool _shouldSuppressInactivePlanTimeline(AiSession session) {
  final latestPlanRecord = session.latestPlanRecord;
  if (latestPlanRecord == null || latestPlanRecord.status.isActive) {
    return false;
  }
  return true;
}

AiSessionPlanRecord? _activePlanRecordForTimeline(AiSession session) {
  final activePlanRecord = session.latestActivePlanRecord;
  if (activePlanRecord == null || _hasTransientPlanState(session)) {
    return activePlanRecord;
  }
  final latestUserMessage = _latestActiveUserMessage(session);
  if (latestUserMessage == null) {
    return activePlanRecord;
  }
  return _planTimelineMessageActivityAt(
        latestUserMessage,
      ).isAfter(activePlanRecord.updatedAt)
      ? null
      : activePlanRecord;
}

bool _hasTransientPlanState(AiSession session) {
  return session.awaitingPlanApproval ||
      session.todoItems.isNotEmpty ||
      (session.pendingPlan ?? '').trim().isNotEmpty;
}

List<String> _planTimelineStepsFromPlanRecord(AiSessionPlanRecord planRecord) {
  final planSteps = _planTimelineStepsFromPendingPlan(planRecord.plan);
  if (planSteps.isNotEmpty) {
    return planSteps;
  }
  return planRecord.steps
      .map((item) => item.content.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

bool _shouldReflectCurrentPlanStepFailure(
  AiSession session,
  AiSendPhase sendPhase,
) {
  if (sendPhase != AiSendPhase.idle) {
    return false;
  }
  final latestRecoveryMessage = _latestPlanRecoveryTimelineMessage(session);
  if (_shouldReflectPlanTimelineFailureAfter(
    _latestPlanErrorFailureAt(session),
    latestRecoveryMessage,
  )) {
    return true;
  }
  return _shouldReflectPlanTimelineFailureAfter(
    _latestPlanToolFailureAt(session),
    latestRecoveryMessage,
  );
}

bool _shouldReflectPlanTimelineFailureAfter(
  DateTime? latestFailureAt,
  AiSessionMessage? latestRecoveryMessage,
) {
  if (latestFailureAt == null) {
    return false;
  }
  if (latestRecoveryMessage == null) {
    return true;
  }
  return !latestRecoveryMessage.createdAt.isAfter(latestFailureAt);
}

DateTime? _latestPlanToolFailureAt(AiSession session) {
  for (var index = session.messages.length - 1; index >= 0; index -= 1) {
    final message = session.messages[index];
    if (message.isDeleted || message.kind != AiSessionMessageKind.toolCall) {
      continue;
    }
    final status = _toolExecutionStatus(message);
    if (status.isEmpty || status == 'running') {
      continue;
    }
    if (!_isFailurePlanTimelineToolStatus(status)) {
      return null;
    }
    return _readToolExecutionFinishedAt(message) ?? message.createdAt;
  }
  return null;
}

DateTime? _latestPlanErrorFailureAt(AiSession session) {
  for (final error in session.recentErrors) {
    if (_isPlanTimelineRelevantErrorStage(error.stage)) {
      return error.createdAt;
    }
  }
  return null;
}

bool _isFailurePlanTimelineToolStatus(String status) {
  return switch (status) {
    'failed' ||
    'cancelled' ||
    'denied' ||
    'rejected' ||
    'timed_out' ||
    'invalid_arguments' => true,
    _ => false,
  };
}

bool _isPlanTimelineRelevantErrorStage(String stage) {
  return switch (stage.trim().toLowerCase()) {
    'chat_request' ||
    'chat_continuation_request' ||
    'chat_stream' ||
    'follow_up_request' ||
    'tool_execution' ||
    'tool_loop' => true,
    _ => false,
  };
}

DateTime? _readToolExecutionFinishedAt(AiSessionMessage message) {
  final rawValue = '${message.metadata['tool_execution_finished_at'] ?? ''}'
      .trim();
  if (rawValue.isEmpty) {
    return null;
  }
  try {
    return DateTime.parse(rawValue).toUtc();
  } catch (_) {
    return null;
  }
}

AiSessionMessage? _latestPlanRecoveryTimelineMessage(AiSession session) {
  final latestUserMessage = _latestActiveUserMessage(session);
  if (latestUserMessage == null) {
    return null;
  }
  return _looksLikePlanRecoveryTimelineMessage(latestUserMessage.content)
      ? latestUserMessage
      : null;
}

bool _shouldReviewCompletedPlan(AiSession session) {
  if (session.mode != AiSessionMode.plan || session.awaitingPlanApproval) {
    return false;
  }
  if (!_hasOnlyCompletedPlanTodoItems(session.todoItems)) {
    return false;
  }
  final latestUserMessage = _latestActiveUserMessage(session);
  if (latestUserMessage == null) {
    return false;
  }
  return _looksLikePlanRecoveryTimelineMessage(latestUserMessage.content);
}

bool _hasOnlyCompletedPlanTodoItems(List<AiSessionTodoItem> todoItems) {
  return todoItems.isNotEmpty &&
      todoItems.every(
        (item) => item.status.trim().toLowerCase() == 'completed',
      );
}

AiSessionMessage? _latestActiveUserMessage(AiSession session) {
  for (var index = session.messages.length - 1; index >= 0; index -= 1) {
    final message = session.messages[index];
    if (!message.isDeleted && message.kind == AiSessionMessageKind.user) {
      return message;
    }
  }
  return null;
}

DateTime _planTimelineMessageActivityAt(AiSessionMessage message) {
  final editedAt = '${message.metadata['edited_at'] ?? ''}'.trim();
  if (editedAt.isNotEmpty) {
    try {
      return DateTime.parse(editedAt).toUtc();
    } catch (_) {}
  }
  return message.createdAt;
}

bool _looksLikePlanRecoveryTimelineMessage(String content) {
  final normalized = content.trim().toLowerCase();
  if (normalized.isEmpty) {
    return false;
  }
  const recoveryPhrases = <String>[
    'continue',
    'continue.',
    'go on',
    'keep going',
    'continue implementation',
    'finish it',
    'retry',
    'retry it',
    'retry the step',
    'retry the failed step',
    'resume',
    '继续',
    '继续吧',
    '继续做',
    '继续完成',
    '继续实施',
    '继续执行',
    '接着',
    '接着做',
    '重试',
    '重试一下',
    '重新执行',
    '重新试',
    '恢复执行',
  ];
  return recoveryPhrases.any((phrase) => normalized.contains(phrase));
}

List<String> _planTimelineStepsFromPendingPlan(String? pendingPlan) {
  final normalizedPlan = (pendingPlan ?? '').trim();
  if (normalizedPlan.isEmpty) {
    return const <String>[];
  }
  return normalizedPlan
      .split('\n')
      .map(_structuredPlanTimelineStepLabel)
      .whereType<String>()
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
}

String? _structuredPlanTimelineStepLabel(String rawLine) {
  final normalizedLine = rawLine.trim();
  if (normalizedLine.isEmpty) {
    return null;
  }
  final match = _planTimelineStepPrefixPattern.firstMatch(normalizedLine);
  if (match == null) {
    return null;
  }
  final label = normalizedLine.substring(match.end).trim();
  return label.isEmpty ? null : label;
}

Future<void> _showSessionMetadataDialog(
  BuildContext context,
  AiSession session, {
  AiRuntimeToolPreview? liveRuntimeToolPreview,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) => _SessionMetadataDialog(
      session: session,
      liveRuntimeToolPreview: liveRuntimeToolPreview,
    ),
  );
}

int _metadataInt(Object? rawValue) {
  if (rawValue is int) {
    return rawValue;
  }
  return int.tryParse('${rawValue ?? ''}'.trim()) ?? 0;
}

List<Map<String, Object?>> _metadataObjectList(Object? rawValue) {
  if (rawValue is! List) {
    return const <Map<String, Object?>>[];
  }
  return rawValue
      .whereType<Map>()
      .map((item) => Map<String, Object?>.from(item))
      .toList(growable: false);
}

List<String> _metadataStringList(Object? rawValue) {
  if (rawValue is! List) {
    return const <String>[];
  }
  return rawValue
      .map((item) => '$item'.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

class _RuntimeToolCatalogStatus {
  const _RuntimeToolCatalogStatus({
    required this.sessionMode,
    required this.hasSnapshot,
    required this.stale,
    required this.isLivePreview,
    required this.awaitingPlanApproval,
    required this.planRecoveryRequired,
    required this.planExecutionApproved,
    required this.hasActiveTodoItems,
    required this.hasPendingPlan,
    required this.toolCount,
    required this.toolNames,
    required this.notices,
    required this.gateReason,
    required this.supportsToolCalls,
  });

  final AiSessionMode sessionMode;
  final bool hasSnapshot;
  final bool stale;
  final bool isLivePreview;
  final bool awaitingPlanApproval;
  final bool planRecoveryRequired;
  final bool planExecutionApproved;
  final bool hasActiveTodoItems;
  final bool hasPendingPlan;
  final int toolCount;
  final List<String> toolNames;
  final List<String> notices;
  final String gateReason;
  final bool supportsToolCalls;

  bool get hasActivePlanState => hasActiveTodoItems || hasPendingPlan;
}

_RuntimeToolCatalogStatus _runtimeToolCatalogStatus(
  AiSession session, {
  AiRuntimeToolPreview? livePreview,
}) {
  if (livePreview != null) {
    return _RuntimeToolCatalogStatus(
      sessionMode: livePreview.sessionMode,
      hasSnapshot: true,
      stale: false,
      isLivePreview: true,
      awaitingPlanApproval: livePreview.awaitingPlanApproval,
      planRecoveryRequired: livePreview.planRecoveryInspectionRequired,
      planExecutionApproved: livePreview.planExecutionApproved,
      hasActiveTodoItems: session.todoItems.isNotEmpty,
      hasPendingPlan: (session.pendingPlan ?? '').trim().isNotEmpty,
      toolCount: livePreview.toolCount,
      toolNames: livePreview.toolNames,
      notices: livePreview.notices,
      gateReason: livePreview.gateReason,
      supportsToolCalls: livePreview.supportsToolCalls,
    );
  }
  final metadata = session.lastPromptMetadata;
  final toolNames = _metadataStringList(metadata['current_tool_names']);
  final notices = _metadataStringList(metadata['runtime_tool_catalog_notices']);
  final rawToolCount = _metadataInt(metadata['current_tool_count']);
  final awaitingPlanApproval =
      metadata['awaiting_plan_approval'] == true ||
      session.awaitingPlanApproval;
  final planRecoveryRequired =
      metadata['plan_mode_recovery_inspection_required'] == true ||
      metadata['plan_recovery_required'] == true;
  final planExecutionApproved =
      metadata['plan_mode_execution_approved_for_send'] == true;
  final hasActiveTodoItems = session.todoItems.isNotEmpty;
  final hasPendingPlan = (session.pendingPlan ?? '').trim().isNotEmpty;
  var gateReason = '${metadata['runtime_tool_gate_reason'] ?? ''}'.trim();
  if (gateReason.isEmpty) {
    if (awaitingPlanApproval) {
      gateReason = 'awaiting_plan_approval';
    } else if (session.mode != AiSessionMode.plan) {
      gateReason = metadata.isEmpty ? 'no_runtime_snapshot' : 'chat_mode';
    } else if (planRecoveryRequired) {
      gateReason = 'plan_mode_recovery_inspection';
    } else if (planExecutionApproved) {
      gateReason = 'plan_mode_execution';
    } else if (hasActiveTodoItems) {
      gateReason = 'plan_mode_planning_with_exit_allowed';
    } else {
      gateReason = 'plan_mode_planning_only';
    }
  }
  return _RuntimeToolCatalogStatus(
    sessionMode: session.mode,
    hasSnapshot: metadata.isNotEmpty,
    stale: metadata['runtime_tool_catalog_stale'] == true,
    isLivePreview: false,
    awaitingPlanApproval: awaitingPlanApproval,
    planRecoveryRequired: planRecoveryRequired,
    planExecutionApproved: planExecutionApproved,
    hasActiveTodoItems: hasActiveTodoItems,
    hasPendingPlan: hasPendingPlan,
    toolCount: rawToolCount > 0 ? rawToolCount : toolNames.length,
    toolNames: toolNames,
    notices: notices,
    gateReason: gateReason,
    supportsToolCalls: true,
  );
}

String _runtimeModeLabel(
  BuildContext context,
  _RuntimeToolCatalogStatus? status, {
  bool compact = false,
  AiSessionMode? explicitMode,
}) {
  final mode = explicitMode ?? status?.sessionMode ?? AiSessionMode.chat;
  if (mode != AiSessionMode.plan) {
    return _localizedText(
      context,
      zh: '聊天模式',
      en: compact ? 'Chat Mode' : 'Chat Mode',
    );
  }
  if (status != null && status.sessionMode == AiSessionMode.plan) {
    if (status.awaitingPlanApproval) {
      return _localizedText(
        context,
        zh: '计划待确认',
        en: compact ? 'Plan Awaiting' : 'Plan Awaiting Approval',
      );
    }
    if (status.planRecoveryRequired) {
      return _localizedText(
        context,
        zh: '计划待复核',
        en: compact ? 'Plan Review' : 'Plan Needs Review',
      );
    }
    if (status.planExecutionApproved) {
      return _localizedText(
        context,
        zh: '执行计划',
        en: compact ? 'Plan Execute' : 'Plan Execution',
      );
    }
    if (status.hasActivePlanState) {
      return _localizedText(
        context,
        zh: '计划规划中',
        en: compact ? 'Plan Draft' : 'Plan Drafting',
      );
    }
  }
  return _localizedText(
    context,
    zh: '计划模式',
    en: compact ? 'Plan Mode' : 'Plan Mode',
  );
}

IconData _runtimeModeIcon(
  _RuntimeToolCatalogStatus? status, {
  AiSessionMode? explicitMode,
}) {
  final mode = explicitMode ?? status?.sessionMode ?? AiSessionMode.chat;
  if (mode != AiSessionMode.plan) {
    return Icons.forum_outlined;
  }
  if (status != null && status.sessionMode == AiSessionMode.plan) {
    if (status.awaitingPlanApproval) {
      return Icons.fact_check_outlined;
    }
    if (status.planRecoveryRequired) {
      return Icons.manage_search_rounded;
    }
    if (status.planExecutionApproved) {
      return Icons.playlist_play_rounded;
    }
  }
  return Icons.alt_route_rounded;
}

String _runtimeToolCatalogStatusLabel(
  BuildContext context,
  _RuntimeToolCatalogStatus status,
) {
  if (!status.supportsToolCalls) {
    return _localizedText(
      context,
      zh: '当前模型协议不支持工具调用',
      en: 'The current model protocol does not support tool calls',
    );
  }
  if (!status.hasSnapshot) {
    return _localizedText(
      context,
      zh: '尚未生成运行时工具快照',
      en: 'No runtime tool snapshot yet',
    );
  }
  if (status.stale) {
    return _localizedText(
      context,
      zh: '工具目录已过期，等待下一轮刷新',
      en: 'The tool catalog is stale and will refresh next round',
    );
  }
  return _localizedText(
    context,
    zh: '运行时工具目录已同步',
    en: 'The runtime tool catalog is synchronized',
  );
}

String _runtimeToolGateReasonLabel(BuildContext context, String gateReason) {
  return switch (gateReason.trim()) {
    'awaiting_plan_approval' => _localizedText(
      context,
      zh: '计划待确认，当前轮不开放执行工具',
      en: 'The plan is awaiting approval, so execution tools stay hidden',
    ),
    'plan_mode_recovery_inspection' => _localizedText(
      context,
      zh: '需要先复核已有步骤、产物和 Todo',
      en: 'Review completed steps, artifacts, and todos before resuming',
    ),
    'plan_mode_execution' => _localizedText(
      context,
      zh: '计划已获准执行，当前轮开放执行工具',
      en: 'The plan is approved and execution tools are available',
    ),
    'plan_mode_planning_with_exit_allowed' => _localizedText(
      context,
      zh: '当前仅开放规划工具，可在准备好后提交执行计划',
      en: 'Only planning tools are available until the execution plan is ready',
    ),
    'plan_mode_planning_only' => _localizedText(
      context,
      zh: '当前仅开放规划工具',
      en: 'Only planning tools are available right now',
    ),
    'mode_switch_requires_refresh' => _localizedText(
      context,
      zh: '模式刚切换，等待下一轮重新计算工具目录',
      en: 'The mode just changed, so the tool catalog will refresh next round',
    ),
    'chat_mode_no_tools' => _localizedText(
      context,
      zh: '聊天模式当前没有可用工具',
      en: 'No tools are available in chat mode right now',
    ),
    'chat_mode' => _localizedText(
      context,
      zh: '聊天模式当前开放完整运行时工具目录',
      en: 'Chat mode currently exposes the full runtime catalog',
    ),
    'model_no_tool_support' => _localizedText(
      context,
      zh: '当前模型协议不支持工具调用',
      en: 'The current model protocol does not support tool calls',
    ),
    'no_runtime_snapshot' => _localizedText(
      context,
      zh: '当前还没有运行时快照，请先发起一轮请求',
      en: 'No runtime snapshot is available yet; send a request first',
    ),
    _ =>
      gateReason.isEmpty
          ? _localizedText(
              context,
              zh: '暂无门控说明',
              en: 'No gate reason available',
            )
          : gateReason,
  };
}

String _composerModeTooltip(
  BuildContext context,
  AiSessionMode mode,
  _RuntimeToolCatalogStatus? status,
) {
  if (mode != AiSessionMode.plan) {
    if (status != null && !status.supportsToolCalls) {
      return _localizedText(
        context,
        zh: '当前模型协议不支持工具调用。点击切换到计划模式。',
        en: 'The current model protocol does not support tool calls. Click to switch to plan mode.',
      );
    }
    return _localizedText(
      context,
      zh: '当前为聊天模式，点击切换到计划模式',
      en: 'Chat mode is active. Click to switch to plan mode.',
    );
  }
  if (status == null) {
    return _localizedText(
      context,
      zh: '当前为计划模式，点击切换到聊天模式',
      en: 'Plan mode is active. Click to switch to chat mode.',
    );
  }
  if (!status.supportsToolCalls) {
    return _localizedText(
      context,
      zh: '当前模型协议不支持工具调用。计划模式仍可组织步骤，但不会开放工具执行。点击切换到聊天模式。',
      en: 'The current model protocol does not support tool calls. Plan mode can still organize steps, but tool execution stays unavailable. Click to switch to chat mode.',
    );
  }
  if (status.stale) {
    return _localizedText(
      context,
      zh: '计划模式刚切换完成，运行时工具会在下一轮自动刷新。点击切换到聊天模式。',
      en: 'Plan mode just changed. Runtime tools will refresh on the next round. Click to switch to chat mode.',
    );
  }
  if (status.awaitingPlanApproval) {
    return _localizedText(
      context,
      zh: '计划待确认。当前轮不会暴露执行工具，请先确认计划。点击切换到聊天模式。',
      en: 'The plan is awaiting approval. Execution tools stay hidden until approval. Click to switch to chat mode.',
    );
  }
  if (status.planRecoveryRequired) {
    return _localizedText(
      context,
      zh: '计划待复核。继续执行前应先检查已完成步骤、产物与 Todo。点击切换到聊天模式。',
      en: 'The plan needs review. Inspect completed steps, artifacts, and todos before continuing. Click to switch to chat mode.',
    );
  }
  if (status.planExecutionApproved) {
    return _localizedText(
      context,
      zh: '计划执行中。当前轮会按运行时目录暴露执行工具。点击切换到聊天模式。',
      en: 'The plan is executing. Runtime tools are exposed according to the current catalog. Click to switch to chat mode.',
    );
  }
  return _localizedText(
    context,
    zh: '当前为计划模式，会先规划，再在获得确认后执行。点击切换到聊天模式。',
    en: 'Plan mode is active. It plans first, then executes after approval. Click to switch to chat mode.',
  );
}
