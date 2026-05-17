part of '../openhand_home_page.dart';

class _SessionToolbar extends StatelessWidget {
  const _SessionToolbar({
    required this.session,
    this.liveRuntimeToolPreview,
    this.sendPhase = AiSendPhase.idle,
    this.planTimelineCollapsed = false,
    this.onPlanTimelineCollapsedChanged,
    this.fileExplorerVisible = false,
    this.onFileExplorerToggled,
    this.activeProfile,
    this.claudeStyle = true,
  });

  final AiSession session;
  final AiRuntimeToolPreview? liveRuntimeToolPreview;
  final AiSendPhase sendPhase;
  final bool planTimelineCollapsed;
  final ValueChanged<bool>? onPlanTimelineCollapsedChanged;
  final bool fileExplorerVisible;
  final VoidCallback? onFileExplorerToggled;
  final AiModelProfile? activeProfile;
  final bool claudeStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final runtimeStatus = _runtimeToolCatalogStatus(
      session,
      livePreview: liveRuntimeToolPreview,
    );
    final contextBudgetLabel = _contextBudgetToolbarLabel(
      context,
      session.lastPromptMetadata,
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
                            if (runtimeStatus.notices.isNotEmpty) ...[
                              ..._buildMcpLazyLoadingPills(
                                context,
                                runtimeStatus.notices,
                              ),
                              const SizedBox(width: 8),
                              _ToolbarPill(
                                icon: Icons.info_outline_rounded,
                                label: AppLocalizations.of(context)!
                                    .toolbarRuntimeNotices(
                                      runtimeStatus.notices.length,
                                    ),
                              ),
                            ],
                            const SizedBox(width: 8),
                            _ToolbarPill(
                              icon: Icons.layers_rounded,
                              label:
                                  '${session.templateName} · v${session.templateInternalVersion}',
                            ),
                            if (session.templateId == 'hermes_talker')
                              const _HermesSelfLearningWarningPill(),
                            if (session.templateId == 'web_reverse_expert')
                              _WebReverseDebugPill(sessionId: session.id),
                            const SizedBox(width: 8),
                            _ToolbarPill(
                              icon: Icons.data_object_rounded,
                              label: AppLocalizations.of(
                                context,
                              )!.toolbarSessionMetadata,
                              onTap: () {
                                _showSessionMetadataDialog(
                                  context,
                                  session,
                                  liveRuntimeToolPreview:
                                      liveRuntimeToolPreview,
                                  activeProfile: activeProfile,
                                  claudeStyle: claudeStyle,
                                );
                              },
                            ),
                            if (contextBudgetLabel != null) ...[
                              const SizedBox(width: 8),
                              _ToolbarPill(
                                icon: Icons.speed_rounded,
                                label: contextBudgetLabel,
                                onTap: () {
                                  _showContextStatsDialog(context, session);
                                },
                              ),
                            ],
                            const SizedBox(width: 8),
                            _StreamThrottlePill(sessionId: session.id),
                            if (_isInputCacheLocked(context, session)) ...[
                              const SizedBox(width: 8),
                              Tooltip(
                                message: AppLocalizations.of(
                                  context,
                                )!.toolbarProviderModelLocked,
                                child: _ToolbarPill(
                                  icon: Icons.lock_outline_rounded,
                                  label: AppLocalizations.of(
                                    context,
                                  )!.toolbarModelLocked,
                                ),
                              ),
                            ],
                            if (context
                                .watch<SettingsController>()
                                .telemetryDebugEnabled) ...[
                              const SizedBox(width: 8),
                              _ToolbarPill(
                                icon: Icons.fact_check_outlined,
                                label: AppLocalizations.of(
                                  context,
                                )!.toolbarSessionAudit,
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
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _ToolbarPill(
                    key: ValueKey<bool>(planTimelineCollapsed),
                    icon: planTimelineCollapsed
                        ? Icons.unfold_more_rounded
                        : Icons.unfold_less_rounded,
                    label: planTimelineCollapsed
                        ? AppLocalizations.of(context)!.toolbarShowPlan
                        : AppLocalizations.of(context)!.toolbarHidePlan,
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
                  label: _localizedFilesToggle(context, fileExplorerVisible),
                  onTap: onFileExplorerToggled,
                ),
                const SizedBox(width: 10),
              ],
              _TokenDial(
                statistics: session.statistics,
                activeProfile: activeProfile,
                claudeStyle: claudeStyle,
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
    return MicroPressFeedback(
      child: Material(
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
      ),
    );
  }
}

/// 当 Hermes Talker 自我学习 cron 被关闭时，在 Hermes Talker 线程会话顶部
/// 显示的警告胶囊。鼠标悬浮可看到详细说明，引导用户去 cron 面板重新启用。
///
/// 通过 `context.watch<CronsController>()` 实时跟随启停状态——一旦用户
/// 在 cron 面板里把开关打回去，警告会自动消失。
class _HermesSelfLearningWarningPill extends StatelessWidget {
  const _HermesSelfLearningWarningPill();

  @override
  Widget build(BuildContext context) {
    final crons = context.watch<CronsController>();
    final entry = crons.entries
        .where((e) => e.id == CronsController.selfLearningSystemEntryId)
        .firstOrNull;
    final enabled = entry?.enabled ?? false;
    if (enabled) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final tooltip = isZh
        ? '当前 Hermes Talker 自主学习能力已关闭。\n\n'
              '影响：AI 不会在后台周期性地把本会话沉淀的偏好、画像、'
              '通用记忆与可复用技能持久化到长期记忆库——下次新会话将无法'
              '基于这些信息做更贴心的回应。\n\n'
              '建议：前往「定时任务」面板，把 “Hermes Talker 自我学习” '
              '开关打开即可恢复。'
        : 'Hermes Talker self-learning is currently disabled.\n\n'
              'Impact: the agent will not periodically persist the '
              'preferences, profile, general memories or reusable skills '
              'absorbed from this conversation. Future sessions will lose '
              'this background context.\n\n'
              'Tip: open the Crons panel and re-enable '
              '"Hermes Talker 自我学习" to resume.';
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 200),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: colorScheme.errorContainer.withValues(alpha: 0.55),
            borderRadius: _borderRadius999,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 6),
              Text(
                isZh ? '自主学习已关闭' : 'Self-learning off',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onErrorContainer,
                ),
              ),
            ],
          ),
        ),
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

class _SessionPlanTimelineBar extends StatefulWidget {
  const _SessionPlanTimelineBar({required this.data, this.onVisibilityToggle});

  final _PlanTimelineData data;
  final VoidCallback? onVisibilityToggle;

  @override
  State<_SessionPlanTimelineBar> createState() =>
      _SessionPlanTimelineBarState();
}

class _SessionPlanTimelineBarState extends State<_SessionPlanTimelineBar> {
  final ScrollController _stepsScrollController = ScrollController();
  // Per-step keys so we can locate the "current" chip's RenderBox after
  // layout and animate it into the horizontal centre of the strip.
  final Map<int, GlobalKey> _stepKeys = <int, GlobalKey>{};
  int? _lastCenteredCurrentIndex;

  GlobalKey _stepKeyAt(int index) =>
      _stepKeys.putIfAbsent(index, () => GlobalKey());

  int? _resolveCurrentStepIndex() {
    for (var i = 0; i < widget.data.steps.length; i += 1) {
      if (widget.data.steps[i].state == _PlanTimelineStepState.current) {
        return i;
      }
    }
    return null;
  }

  void _scheduleCenterCurrentStep({required bool animated}) {
    final currentIndex = _resolveCurrentStepIndex();
    if (currentIndex == null) {
      _lastCenteredCurrentIndex = null;
      return;
    }
    if (_lastCenteredCurrentIndex == currentIndex) {
      return;
    }
    _lastCenteredCurrentIndex = currentIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = _stepKeys[currentIndex];
      final chipContext = key?.currentContext;
      if (chipContext == null) return;
      // Prefer Scrollable.ensureVisible with alignment=0.5 so the
      // horizontal scroller settles with the chip centred. The Q-elastic
      // feel comes from the elasticOut curve (overshoot + settle).
      Scrollable.ensureVisible(
        chipContext,
        alignment: 0.5,
        duration: animated ? const Duration(milliseconds: 520) : Duration.zero,
        curve: animated ? Curves.easeOutCubic : Curves.linear,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _scheduleCenterCurrentStep(animated: false);
  }

  @override
  void didUpdateWidget(covariant _SessionPlanTimelineBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleCenterCurrentStep(animated: true);
  }

  @override
  void dispose() {
    _stepsScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final onVisibilityToggle = widget.onVisibilityToggle;
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
        ? AppLocalizations.of(context)!.toolbarPlanAwaitingApproval
        : data.requiresReview
        ? AppLocalizations.of(context)!.toolbarPlanNeedsReview
        : data.hasFailedStep
        ? AppLocalizations.of(context)!.toolbarPlanNeedsAttention
        : data.isComplete
        ? AppLocalizations.of(context)!.toolbarPlanCompleted
        : AppLocalizations.of(context)!.toolbarPlanInProgress;
    final subtitle = data.awaitingApproval
        ? AppLocalizations.of(context)!.toolbarPlanConfirmToBegin
        : data.requiresReview
        ? AppLocalizations.of(context)!.toolbarPlanInspectBeforeResume
        : data.hasFailedStep
        ? AppLocalizations.of(context)!.toolbarPlanStepFailed
        : AppLocalizations.of(context)!.toolbarPlanStepsCompleted(
            data.completedStepCount,
            data.steps.length,
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
                  label: AppLocalizations.of(context)!.toolbarHidePlan,
                  icon: Icons.unfold_less_rounded,
                  color: statusColor,
                  onTap: onVisibilityToggle,
                ),
                const SizedBox(width: 12),
              ],
              AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                child: Text(
                  data.awaitingApproval
                      ? AppLocalizations.of(context)!.toolbarPlanPending
                      : data.requiresReview
                      ? AppLocalizations.of(context)!.toolbarPlanReview
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
            controller: _stepsScrollController,
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: Row(
              children: [
                for (var index = 0; index < data.steps.length; index++)
                  KeyedSubtree(
                    key: _stepKeyAt(index),
                    child: _SessionPlanTimelineStepChip(
                      index: index,
                      step: data.steps[index],
                      isLast: index == data.steps.length - 1,
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
    return MicroPressFeedback(
      child: Material(
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
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 220),
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
  // 2026-04-28: 单一真相 = `session.awaitingPlanApproval`。
  // 历史上出现过 planRecord.status 滞留在 `pendingApproval`、但
  // session 已经清掉 awaiting 标志、且模型已经在跑 todo 的 case，导致
  // 计划面板被卡在“计划待确认”、用户看不出已经在执行了。这里在面板侧
  // 做一次显式校正：若 session 已经进入执行（awaitingPlanApproval=false
  // 且 todo / 进行中状态存在），则把展示态从 pendingApproval 降级。
  final sessionAwaitingApproval = session.awaitingPlanApproval;
  final hasExecutionEvidence =
      session.todoItems.isNotEmpty ||
      sendPhase != AiSendPhase.idle ||
      sendPhase == AiSendPhase.responding ||
      sendPhase == AiSendPhase.sendingMessage;
  final treatAsPendingApproval =
      planRecord.status == AiSessionPlanStatus.pendingApproval &&
      sessionAwaitingApproval &&
      !hasExecutionEvidence;
  if (treatAsPendingApproval) {
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
    } catch (error, stack) {
      silentLog(
        'session_toolbar',
        'parse plan timeline edited_at',
        error,
        stack,
      );
    }
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
  AiModelProfile? activeProfile,
  bool claudeStyle = true,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) => _SessionMetadataDialog(
      session: session,
      liveRuntimeToolPreview: liveRuntimeToolPreview,
      activeProfile: activeProfile,
      claudeStyle: claudeStyle,
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
  final l10n = AppLocalizations.of(context)!;
  if (mode != AiSessionMode.plan) {
    return compact
        ? l10n.toolbarRuntimeModeChatCompact
        : l10n.toolbarRuntimeModeChat;
  }
  if (status != null && status.sessionMode == AiSessionMode.plan) {
    if (status.awaitingPlanApproval) {
      return compact
          ? l10n.toolbarRuntimeModePlanAwaitingCompact
          : l10n.toolbarRuntimeModePlanAwaiting;
    }
    if (status.planRecoveryRequired) {
      return compact
          ? l10n.toolbarRuntimeModePlanReviewCompact
          : l10n.toolbarRuntimeModePlanReview;
    }
    if (status.planExecutionApproved) {
      return compact
          ? l10n.toolbarRuntimeModePlanExecutionCompact
          : l10n.toolbarRuntimeModePlanExecution;
    }
    if (status.hasActivePlanState) {
      return compact
          ? l10n.toolbarRuntimeModePlanDraftCompact
          : l10n.toolbarRuntimeModePlanDrafting;
    }
  }
  return compact
      ? l10n.toolbarRuntimeModePlanCompact
      : l10n.toolbarRuntimeModePlan;
}

String? _contextBudgetToolbarLabel(
  BuildContext context,
  Map<String, Object?> metadata,
) {
  final estimatedTokens = _metadataInt(
    metadata['context_budget_estimated_prompt_tokens'],
  );
  if (estimatedTokens <= 0) {
    return null;
  }
  final percentLeft = _metadataInt(metadata['context_budget_percent_left']);
  final status = '${metadata['context_budget_status'] ?? ''}'.trim();
  final statusLabel = switch (status) {
    'critical' => _localizedText(context, zh: '危险', en: 'critical'),
    'auto_compact' => _localizedText(context, zh: '压缩', en: 'compact'),
    'warning' => _localizedText(context, zh: '偏高', en: 'high'),
    'ok' => _localizedText(context, zh: '正常', en: 'ok'),
    _ => _localizedText(context, zh: '未知', en: 'unknown'),
  };
  return _localizedText(
    context,
    zh: '上下文 $percentLeft% · $statusLabel',
    en: 'Ctx $percentLeft% · $statusLabel',
  );
}

String _localizedFilesToggle(BuildContext context, bool visible) {
  final l10n = AppLocalizations.of(context)!;
  return visible ? l10n.toolbarFilesHide : l10n.toolbarFilesShow;
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
    return AppLocalizations.of(context)!.toolbarToolsProtocolUnsupported;
  }
  if (!status.hasSnapshot) {
    return AppLocalizations.of(context)!.toolbarRuntimeNoSnapshot;
  }
  if (status.stale) {
    return AppLocalizations.of(context)!.toolbarToolsCatalogStale;
  }
  return AppLocalizations.of(context)!.toolbarRuntimeCatalogSynced;
}

String _runtimeToolGateReasonLabel(BuildContext context, String gateReason) {
  return switch (gateReason.trim()) {
    'awaiting_plan_approval' => AppLocalizations.of(
      context,
    )!.toolbarPlanAwaitingNoExecTools,
    'plan_mode_recovery_inspection' => AppLocalizations.of(
      context,
    )!.toolbarPlanReviewBeforeResume,
    'plan_mode_execution' => AppLocalizations.of(
      context,
    )!.toolbarPlanApprovedExecOpen,
    'plan_mode_planning_with_exit_allowed' => AppLocalizations.of(
      context,
    )!.toolbarPlanOnlyPlanningExitAllowed,
    'plan_mode_planning_only' => AppLocalizations.of(
      context,
    )!.toolbarPlanOnlyPlanningOnly,
    'mode_switch_requires_refresh' => AppLocalizations.of(
      context,
    )!.toolbarModeJustSwitched,
    'chat_mode_no_tools' => AppLocalizations.of(
      context,
    )!.toolbarChatModeNoTools,
    'chat_mode' => AppLocalizations.of(context)!.toolbarChatModeAllTools,
    'model_no_tool_support' => AppLocalizations.of(
      context,
    )!.toolbarToolsProtocolUnsupported,
    'no_runtime_snapshot' => AppLocalizations.of(
      context,
    )!.toolbarRuntimeNoSnapshotPrompt,
    _ =>
      gateReason.isEmpty
          ? AppLocalizations.of(context)!.toolbarGateNoReason
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
      return AppLocalizations.of(
        context,
      )!.toolbarGateProtocolUnsupportedSwitchPlan;
    }
    return AppLocalizations.of(context)!.toolbarGateChatActiveSwitchPlan;
  }
  if (status == null) {
    return AppLocalizations.of(context)!.toolbarGatePlanActiveSwitchChat;
  }
  if (!status.supportsToolCalls) {
    return AppLocalizations.of(
      context,
    )!.toolbarGateProtocolUnsupportedSwitchChat;
  }
  if (status.stale) {
    return AppLocalizations.of(context)!.toolbarGatePlanJustSwitchedToChat;
  }
  if (status.awaitingPlanApproval) {
    return AppLocalizations.of(context)!.toolbarGatePlanAwaitingSwitchChat;
  }
  if (status.planRecoveryRequired) {
    return AppLocalizations.of(context)!.toolbarGatePlanReviewSwitchChat;
  }
  if (status.planExecutionApproved) {
    return AppLocalizations.of(context)!.toolbarGatePlanExecutingSwitchChat;
  }
  return AppLocalizations.of(context)!.toolbarGatePlanModeSwitchChat;
}

/// 2026-05-01 — 输入缓存锁定判断。
///
/// 当全局设置中『启用输入缓存』开启，且当前 session 已经至少完成 1 轮
/// assistant 回复（保证缓存已经被服务端写入），即认为本轮起服务商/模型不应
/// 再被切换，否则会让 cache_control 锁定的前缀失效。
bool _isInputCacheLocked(BuildContext context, AiSession session) {
  final settings = context.watch<SettingsController>();
  if (!settings.aiInputCacheEnabled) return false;
  return session.statistics.assistantMessageCount > 0;
}

/// Parses the MCP lazy-loading notice (format produced by
/// `McpLazyLoadingApplier`) and renders a compact pill showing how many MCP
/// tools are currently loaded vs total. Returns an empty list when the
/// notice is absent (i.e. lazy loading is disabled or no MCP tools exist).
final RegExp _mcpLazyLoadingNoticePattern = RegExp(
  r'MCP tool lazy loading active.*?(\d+)\s+of\s+(\d+)\s+MCP tool',
);

List<Widget> _buildMcpLazyLoadingPills(
  BuildContext context,
  List<String> notices,
) {
  for (final notice in notices) {
    final match = _mcpLazyLoadingNoticePattern.firstMatch(notice);
    if (match == null) continue;
    final deferred = int.tryParse(match.group(1) ?? '');
    final total = int.tryParse(match.group(2) ?? '');
    if (deferred == null || total == null || total <= 0) continue;
    final loaded = (total - deferred).clamp(0, total);
    return <Widget>[
      const SizedBox(width: 8),
      Tooltip(
        message: notice,
        child: _ToolbarPill(
          icon: Icons.search_rounded,
          label: AppLocalizations.of(
            context,
          )!.toolbarMcpLazyLoading(loaded, total),
        ),
      ),
    ];
  }
  return const <Widget>[];
}

// ---------------------------------------------------------------------------
// 上下文统计弹窗 + 主动压缩
// ---------------------------------------------------------------------------

Future<void> _showContextStatsDialog(BuildContext context, AiSession session) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) => _ContextStatsDialog(sessionId: session.id),
  );
}

class _ContextStatsDialog extends StatefulWidget {
  const _ContextStatsDialog({required this.sessionId});

  final String sessionId;

  @override
  State<_ContextStatsDialog> createState() => _ContextStatsDialogState();
}

class _ContextStatsDialogState extends State<_ContextStatsDialog> {
  bool _busy = false;
  String? _resultMessage;
  bool _resultIsError = false;

  Future<void> _handleCompactPressed() async {
    if (_busy) return;
    final home = _OpenHandHomePageState._activeHomeState;
    if (home == null || !home.mounted) {
      _showResult(
        _localizedText(
          context,
          zh: '压缩入口暂不可用，请稍后再试。',
          en: 'Compaction is unavailable right now.',
        ),
        isError: true,
      );
      return;
    }
    final settingsController = context.read<SettingsController>();
    final controller = context.read<AiSessionController>();
    final selectedModel = settingsController.selectedAiModel;
    if (selectedModel == null) {
      _showResult(
        _localizedText(
          context,
          zh: '请先选择有效的 AI 模型。',
          en: 'Pick an AI model first.',
        ),
        isError: true,
      );
      return;
    }
    setState(() {
      _busy = true;
      _resultMessage = null;
      _resultIsError = false;
    });
    try {
      final runtimeContext = await home._buildRuntimeContext();
      final result = await controller.requestManualCompaction(
        sessionId: widget.sessionId,
        model: selectedModel,
        runtimeContext: runtimeContext,
      );
      if (!mounted) return;
      switch (result.status) {
        case AiManualCompactionStatus.success:
          _showResult(
            _localizedText(
              context,
              zh: '已生成压缩检查点。',
              en: 'Compaction checkpoint added.',
            ),
            isError: false,
          );
          break;
        case AiManualCompactionStatus.cooldown:
          final secs = result.retryAfter?.inSeconds ?? 30;
          _showResult(
            _localizedText(
              context,
              zh: '刚刚已经压缩过，约 $secs 秒后再试。',
              en: 'Just compacted; retry in about $secs s.',
            ),
            isError: true,
          );
          break;
        case AiManualCompactionStatus.notNeeded:
          _showResult(
            _localizedText(
              context,
              zh: '当前占用过低或没有可压缩的历史。',
              en: 'Usage too low — nothing meaningful to compact.',
            ),
            isError: true,
          );
          break;
        case AiManualCompactionStatus.inflight:
          _showResult(
            _localizedText(
              context,
              zh: '已有压缩任务在进行中。',
              en: 'A compaction is already in flight.',
            ),
            isError: true,
          );
          break;
        case AiManualCompactionStatus.sessionBusy:
          _showResult(
            _localizedText(
              context,
              zh: '当前会话正在响应，请等回复结束后再压缩。',
              en: 'Session is busy. Wait for the current response to finish.',
            ),
            isError: true,
          );
          break;
        case AiManualCompactionStatus.circuitBreaker:
          _showResult(
            _localizedText(
              context,
              zh: '连续压缩失败已熔断，稍后再试。',
              en: 'Compaction circuit breaker tripped; retry later.',
            ),
            isError: true,
          );
          break;
        case AiManualCompactionStatus.failed:
          _showResult(
            _localizedText(
              context,
              zh: '压缩未生效，请稍后重试。',
              en: 'Compaction did not apply; please retry.',
            ),
            isError: true,
          );
          break;
        case AiManualCompactionStatus.noSession:
          _showResult(
            _localizedText(
              context,
              zh: '会话不存在或已被删除。',
              en: 'Session no longer exists.',
            ),
            isError: true,
          );
          break;
      }
    } catch (error, stack) {
      silentLog('context_stats', '_handleCompactPressed', error, stack);
      if (!mounted) return;
      _showResult(
        _localizedText(
          context,
          zh: '压缩失败：$error',
          en: 'Compaction failed: $error',
        ),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _showResult(String message, {required bool isError}) {
    setState(() {
      _resultMessage = message;
      _resultIsError = isError;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final session = context.select<AiSessionController, AiSession?>((ctrl) {
      for (final s in ctrl.sessions) {
        if (s.id == widget.sessionId) return s;
      }
      return null;
    });
    if (session == null) {
      return AlertDialog(
        title: Text(
          _localizedText(context, zh: '上下文使用情况', en: 'Context usage'),
        ),
        content: Text(
          _localizedText(context, zh: '会话不存在或已被删除。', en: 'Session is gone.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text(_localizedText(context, zh: '关闭', en: 'Close')),
          ),
        ],
      );
    }
    final meta = session.lastPromptMetadata;
    final estimatedTokens = _metadataInt(
      meta['context_budget_estimated_prompt_tokens'],
    );
    final percentLeftRaw = meta['context_budget_percent_left'];
    final percentLeft = percentLeftRaw is num ? percentLeftRaw.toDouble() : -1;
    final usagePercent = _metadataInt(meta['context_budget_usage_percent']);
    final effectiveWindow = _metadataInt(
      meta['context_budget_effective_window_tokens'],
    );
    final remainingTokens = _metadataInt(
      meta['context_budget_remaining_tokens'],
    );
    final inferred = meta['context_budget_window_inferred'] == true;
    final status = '${meta['context_budget_status'] ?? ''}'.trim();

    final breakdown = _computeMessageCharBreakdown(session);
    final totalChars = breakdown.totalChars;
    final stats = session.statistics;
    final cumulativePromptTokens = stats.totalPromptTokens ?? 0;
    final cumulativeCompletionTokens = stats.totalCompletionTokens ?? 0;
    final cumulativeTokens =
        stats.totalTokens ??
        (cumulativePromptTokens + cumulativeCompletionTokens);

    final disableCompact =
        estimatedTokens <= 0 ||
        (percentLeft >= 0 && percentLeft > 85) ||
        usagePercent < 10;

    Color statusColor;
    switch (status) {
      case 'critical':
        statusColor = colorScheme.error;
        break;
      case 'auto_compact':
        statusColor = colorScheme.tertiary;
        break;
      case 'warning':
        statusColor = Colors.orange;
        break;
      case 'ok':
        statusColor = colorScheme.primary;
        break;
      default:
        statusColor = colorScheme.outline;
    }

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.speed_rounded, color: statusColor),
          const SizedBox(width: 8),
          Text(_localizedText(context, zh: '上下文使用情况', en: 'Context usage')),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _ContextStatsRow(
                label: _localizedText(
                  context,
                  zh: '估算 prompt tokens',
                  en: 'Estimated prompt tokens',
                ),
                value: estimatedTokens > 0
                    ? estimatedTokens.toString()
                    : _localizedText(context, zh: '暂无', en: 'n/a'),
              ),
              _ContextStatsRow(
                label: _localizedText(
                  context,
                  zh: '占用 / 剩余',
                  en: 'Used / left',
                ),
                value: estimatedTokens > 0 && percentLeft >= 0
                    ? '$usagePercent% · ${percentLeft.toStringAsFixed(0)}%'
                    : _localizedText(context, zh: '暂无', en: 'n/a'),
                valueColor: statusColor,
              ),
              _ContextStatsRow(
                label: _localizedText(
                  context,
                  zh: '有效窗口 tokens',
                  en: 'Effective window',
                ),
                value: effectiveWindow > 0
                    ? '$effectiveWindow${inferred ? '*' : ''}'
                    : _localizedText(context, zh: '暂无', en: 'n/a'),
              ),
              _ContextStatsRow(
                label: _localizedText(
                  context,
                  zh: '剩余 tokens',
                  en: 'Remaining tokens',
                ),
                value: remainingTokens > 0
                    ? remainingTokens.toString()
                    : _localizedText(context, zh: '暂无', en: 'n/a'),
              ),
              const Divider(height: 24),
              Text(
                _localizedText(
                  context,
                  zh: '会话历史字符占比',
                  en: 'Session history breakdown',
                ),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              if (totalChars <= 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    _localizedText(context, zh: '暂无历史。', en: 'No history yet.'),
                    style: theme.textTheme.bodySmall,
                  ),
                )
              else ...[
                _ContextBreakdownBar(
                  label: _localizedText(context, zh: '用户', en: 'User'),
                  chars: breakdown.userChars,
                  totalChars: totalChars,
                  color: colorScheme.primary,
                ),
                _ContextBreakdownBar(
                  label: _localizedText(context, zh: 'AI 回复', en: 'Assistant'),
                  chars: breakdown.assistantChars,
                  totalChars: totalChars,
                  color: colorScheme.secondary,
                ),
                _ContextBreakdownBar(
                  label: _localizedText(context, zh: '工具', en: 'Tools'),
                  chars: breakdown.toolChars,
                  totalChars: totalChars,
                  color: colorScheme.tertiary,
                ),
                _ContextBreakdownBar(
                  label: _localizedText(context, zh: '附件 / 其他', en: 'Other'),
                  chars: breakdown.otherChars,
                  totalChars: totalChars,
                  color: colorScheme.outline,
                ),
              ],
              const Divider(height: 24),
              _ContextStatsRow(
                label: _localizedText(
                  context,
                  zh: '历史累计 prompt tokens',
                  en: 'Cumulative prompt tokens',
                ),
                value: cumulativePromptTokens > 0
                    ? cumulativePromptTokens.toString()
                    : '0',
              ),
              _ContextStatsRow(
                label: _localizedText(
                  context,
                  zh: '历史累计输出 tokens',
                  en: 'Cumulative completion tokens',
                ),
                value: cumulativeCompletionTokens > 0
                    ? cumulativeCompletionTokens.toString()
                    : '0',
              ),
              _ContextStatsRow(
                label: _localizedText(
                  context,
                  zh: '历史总 tokens',
                  en: 'Cumulative total',
                ),
                value: cumulativeTokens > 0 ? cumulativeTokens.toString() : '0',
                emphasize: true,
              ),
              if (_resultMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _resultIsError
                        ? colorScheme.errorContainer.withValues(alpha: 0.5)
                        : colorScheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _resultMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _resultIsError
                          ? colorScheme.onErrorContainer
                          : colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
              if (inferred) ...[
                const SizedBox(height: 8),
                Text(
                  _localizedText(
                    context,
                    zh: '* 模型未声明 maxContextTokens，按 128000 估算。',
                    en:
                        '* Model declared no maxContextTokens; window inferred '
                        'as 128000.',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton.tonalIcon(
          onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.close_rounded),
          label: Text(_localizedText(context, zh: '关闭', en: 'Close')),
        ),
        FilledButton.icon(
          onPressed: (_busy || disableCompact) ? null : _handleCompactPressed,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.compress_rounded),
          label: Text(
            _busy
                ? _localizedText(context, zh: '正在压缩…', en: 'Compacting…')
                : _localizedText(context, zh: '立即压缩', en: 'Compact now'),
          ),
        ),
      ],
    );
  }
}

class _ContextStatsRow extends StatelessWidget {
  const _ContextStatsRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueStyle =
        (emphasize ? theme.textTheme.bodyLarge : theme.textTheme.bodyMedium)
            ?.copyWith(
              color: valueColor,
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(value, style: valueStyle),
        ],
      ),
    );
  }
}

class _ContextBreakdownBar extends StatelessWidget {
  const _ContextBreakdownBar({
    required this.label,
    required this.chars,
    required this.totalChars,
    required this.color,
  });

  final String label;
  final int chars;
  final int totalChars;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = totalChars <= 0 ? 0.0 : chars / totalChars;
    final percent = (ratio * 100).clamp(0, 100).toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                '$chars · $percent%',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContextStatsBreakdown {
  const _ContextStatsBreakdown({
    required this.userChars,
    required this.assistantChars,
    required this.toolChars,
    required this.otherChars,
  });

  final int userChars;
  final int assistantChars;
  final int toolChars;
  final int otherChars;

  int get totalChars => userChars + assistantChars + toolChars + otherChars;
}

_ContextStatsBreakdown _computeMessageCharBreakdown(AiSession session) {
  int userChars = 0;
  int assistantChars = 0;
  int toolChars = 0;
  int otherChars = 0;
  for (final message in session.messages) {
    if (message.isDeleted) continue;
    final chars = message.characterCount;
    switch (message.kind) {
      case AiSessionMessageKind.user:
        userChars += chars;
        break;
      case AiSessionMessageKind.assistant:
      case AiSessionMessageKind.reasoning:
        assistantChars += chars;
        break;
      case AiSessionMessageKind.toolCall:
      case AiSessionMessageKind.tool:
      case AiSessionMessageKind.mcp:
      case AiSessionMessageKind.skill:
      case AiSessionMessageKind.hook:
        toolChars += chars;
        break;
      default:
        otherChars += chars;
    }
  }
  return _ContextStatsBreakdown(
    userChars: userChars,
    assistantChars: assistantChars,
    toolChars: toolChars,
    otherChars: otherChars,
  );
}


/// Web 逆向专家会话的调试胶囊：实时显示「请求数 · 错误数 · 浏览器连接状态」，
/// 点击打开 CDP 仪表盘弹窗。
///
/// Controller 的获取走 `_OpenhandHomePageState` 提供的查询方法，
/// 避免在 part 文件里持有可见 controller 字段。
class _WebReverseDebugPill extends StatefulWidget {
  const _WebReverseDebugPill({required this.sessionId});
  final String sessionId;

  @override
  State<_WebReverseDebugPill> createState() => _WebReverseDebugPillState();
}

class _WebReverseDebugPillState extends State<_WebReverseDebugPill> {
  WebReverseSessionController? _controller;
  bool _restoring = false;

  void _attachIfNeeded() {
    final state = context.findAncestorStateOfType<_OpenHandHomePageState>();
    final ctrl = state?.webReverseControllerFor(widget.sessionId);
    if (identical(ctrl, _controller)) return;
    _controller?.removeListener(_onChanged);
    _controller = ctrl;
    _controller?.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _onPillTap() async {
    final state = context.findAncestorStateOfType<_OpenHandHomePageState>();
    if (state == null) return;
    final ctrl = state.webReverseControllerFor(widget.sessionId);
    if (ctrl != null) {
      await showWebReverseDashboardDialog(context, controller: ctrl);
      return;
    }
    // 应用重启 / 切回旧会话：尝试根据 metadata 重启 controller。
    final session = context
        .read<AiSessionController>()
        .sessions
        .firstWhere(
          (s) => s.id == widget.sessionId,
          orElse: () =>
              throw StateError('session ${widget.sessionId} not found'),
        );
    setState(() => _restoring = true);
    try {
      final restored = await state.restoreWebReverseSession(session);
      if (restored != null && mounted) {
        await showWebReverseDashboardDialog(context, controller: restored);
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _attachIfNeeded();
    final ctrl = _controller;
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final running = ctrl?.isRunning ?? false;
    final reqs = ctrl?.networkRequests.length ?? 0;
    final errs = ctrl?.errorCount ?? 0;
    final dotColor = !running
        ? cs.outline
        : (errs > 0 ? cs.error : cs.primary);
    final label = _restoring
        ? (isZh ? '启动中…' : 'starting…')
        : running
            ? '$reqs · ${isZh ? "$errs 错" : "$errs err"}'
            : (isZh ? '点击连接' : 'click to connect');

    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: !running
                ? cs.outlineVariant
                : (errs > 0 ? cs.error : cs.primary).withValues(alpha: 0.4),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: _restoring ? null : _onPillTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                      boxShadow: running && errs == 0
                          ? [
                              BoxShadow(
                                color: dotColor.withValues(alpha: 0.55),
                                blurRadius: 6,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.bug_report_rounded,
                    size: 13,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
                    child: Text(
                      label,
                      key: ValueKey<String>(label),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
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


/// 顶栏「流式节流」状态指示胶囊。
///
/// 2026-05-17 — 颜色一目了然：
///   * 绿色 = 字符/卡片限速都开着，输出会被均匀放出；
///   * 灰色 = 任一限速被关闭（值为 0），即将看到"全速"输出；
/// 点击打开对话框可临时调整本会话的字符/卡片速率（仅本进程生效，不
/// 持久化），关闭对话框时若用户保留覆盖即生效，点"恢复"则清除。
class _StreamThrottlePill extends StatelessWidget {
  const _StreamThrottlePill({required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context) {
    final sessionController = context.watch<AiSessionController>();
    final settingsController = context.watch<SettingsController>();
    // 监听临时覆盖变更信号，确保拨快慢即时反映在颜色与文案上。
    return ValueListenableBuilder<int>(
      valueListenable: sessionController.streamThrottleOverrideSignal,
      builder: (context, _, _) {
        final session = sessionController.sessions.firstWhere(
          (s) => s.id == sessionId,
          orElse: () => sessionController.sessions.first,
        );
        final templateId = session.templateId;
        final override = sessionController.sessionStreamThrottleOverride(
          sessionId,
        );
        final effChars = override?.charsPerSecond ??
            settingsController.effectiveStreamMaxCharsPerSecond(templateId);
        final effCards = override?.cardsPerSecond ??
            settingsController.effectiveStreamMaxMessageCardsPerSecond(
              templateId,
            );
        final disabled = effChars <= 0 || effCards <= 0;
        // 2026-05-17 — 节流时长已耗尽：胶囊渲染为灰色并改文案，向用户
        // 暗示「剩余流式响应正以 AI 真实速率追加」。
        final durationExpired = sessionController
            .sessionStreamThrottleDurationExpired(sessionId);
        final showAsGray = disabled || durationExpired;
        final backlog = sessionController.sessionStreamCardBacklog(sessionId);
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final pillColor = showAsGray
            ? scheme.surfaceContainerHighest
            : scheme.tertiaryContainer.withValues(alpha: 0.78);
        final iconColor = showAsGray
            ? scheme.outline
            : scheme.onTertiaryContainer;
        final isZh =
            Localizations.localeOf(context).languageCode.startsWith('zh');
        final label = disabled
            ? (isZh ? '节流·关' : 'Throttle·off')
            : durationExpired
                ? (isZh ? '节流·已耗尽' : 'Throttle·expired')
                : (isZh ? '字$effChars·卡$effCards' : 'Ch$effChars·Cd$effCards');
        return MicroPressFeedback(
          child: Material(
            color: Colors.transparent,
            borderRadius: _borderRadius999,
            child: InkWell(
              borderRadius: _borderRadius999,
              onTap: () => _showStreamThrottleDialog(
                context,
                sessionId: sessionId,
                templateId: templateId,
              ),
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: pillColor,
                  borderRadius: _borderRadius999,
                  border: Border.all(
                    color: showAsGray
                        ? scheme.outlineVariant
                        : scheme.tertiary.withValues(alpha: 0.32),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      showAsGray
                          ? Icons.flash_off_rounded
                          : Icons.bolt_rounded,
                      size: 14,
                      color: iconColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: iconColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (backlog > 0) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.tertiary.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '+$backlog',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: iconColor,
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                    if (override != null) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.history_rounded,
                        size: 13,
                        color: iconColor,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

Future<void> _showStreamThrottleDialog(
  BuildContext context, {
  required String sessionId,
  required String templateId,
}) async {
  await showAnimatedDialog<void>(
    context: context,
    builder: (_) => _StreamThrottleSessionDialog(
      sessionId: sessionId,
      templateId: templateId,
    ),
  );
}

class _StreamThrottleSessionDialog extends StatefulWidget {
  const _StreamThrottleSessionDialog({
    required this.sessionId,
    required this.templateId,
  });

  final String sessionId;
  final String templateId;

  @override
  State<_StreamThrottleSessionDialog> createState() =>
      _StreamThrottleSessionDialogState();
}

class _StreamThrottleSessionDialogState
    extends State<_StreamThrottleSessionDialog> {
  late final TextEditingController _charsCtrl;
  late final TextEditingController _cardsCtrl;

  @override
  void initState() {
    super.initState();
    final session = context.read<AiSessionController>();
    final override = session.sessionStreamThrottleOverride(widget.sessionId);
    _charsCtrl = TextEditingController(
      text: override?.charsPerSecond?.toString() ?? '',
    );
    _cardsCtrl = TextEditingController(
      text: override?.cardsPerSecond?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _charsCtrl.dispose();
    _cardsCtrl.dispose();
    super.dispose();
  }

  int? _parse(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    return int.tryParse(t);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    final settings = context.watch<SettingsController>();
    final session = context.read<AiSessionController>();
    final globalChars = settings.effectiveStreamMaxCharsPerSecond(
      widget.templateId,
    );
    final globalCards = settings.effectiveStreamMaxMessageCardsPerSecond(
      widget.templateId,
    );
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isZh ? '本会话流式节流（临时）' : 'Session Throttle (Temporary)',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                isZh
                    ? '仅在本进程内生效，重启即恢复。留空 = 沿用模板/全局值。'
                    : 'In-memory only; resets on restart. Empty = use template/global.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              // 2026-05-18 — 实时字符吞吐 mini 仪表盘：30s 滑窗，每秒
              // 一个柱；柱高 = chars/sec / max。流式过程中持续刷新。
              _StreamThroughputMiniGauge(
                sessionId: widget.sessionId,
                maxRate: globalChars <= 0 ? 1 : globalChars,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _charsCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: InputDecoration(
                  labelText: isZh
                      ? '字符 / 秒（当前生效：$globalChars）'
                      : 'Chars / Sec (current: $globalChars)',
                  hintText:
                      '${AppSettingsSnapshot.defaultAiStreamMaxCharsPerSecond}',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _cardsCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: InputDecoration(
                  labelText: isZh
                      ? '卡片 / 秒（当前生效：$globalCards）'
                      : 'Cards / Sec (current: $globalCards)',
                  hintText:
                      '${AppSettingsSnapshot.defaultAiStreamMaxMessageCardsPerSecond}',
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      session.clearSessionStreamThrottleOverride(
                        widget.sessionId,
                      );
                      Navigator.of(context).pop();
                    },
                    child: Text(isZh ? '恢复默认' : 'Reset'),
                  ),
                  const SizedBox(width: 8),
                  OpenHandDialogActionButton.secondary(
                    onPressed: () => Navigator.of(context).pop(),
                    label: isZh ? '取消' : 'Cancel',
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      session.setSessionStreamCharsOverride(
                        widget.sessionId,
                        _parse(_charsCtrl.text),
                      );
                      session.setSessionStreamCardsOverride(
                        widget.sessionId,
                        _parse(_cardsCtrl.text),
                      );
                      Navigator.of(context).pop();
                    },
                    child: Text(isZh ? '应用' : 'Apply'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// 节流 mini 仪表盘：30 秒滑动窗口的字符吞吐柱状图。
///
/// 2026-05-18 — 让用户在节流弹窗里直接看到 AI 当前正以多快的速度流出
/// 字符；柱越高越接近设定速率上限，柱越低则说明令牌桶已经消耗完毕。
/// 200ms 节奏轮询 controller 即可，自带 reduceMotion 跳过动画。
class _StreamThroughputMiniGauge extends StatefulWidget {
  const _StreamThroughputMiniGauge({
    required this.sessionId,
    required this.maxRate,
  });

  final String sessionId;
  final int maxRate;

  @override
  State<_StreamThroughputMiniGauge> createState() =>
      _StreamThroughputMiniGaugeState();
}

class _StreamThroughputMiniGaugeState
    extends State<_StreamThroughputMiniGauge> {
  Timer? _ticker;
  List<int> _samples = const <int>[];
  // 2026-05-18 — 鼠标悬停 / 触屏长按时高亮的桶索引；null = 不高亮。
  int? _hoveredIndex;
  Offset? _hoverLocal;

  @override
  void initState() {
    super.initState();
    _refresh();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _refresh() {
    final controller = context.read<AiSessionController>();
    final next = controller.sessionStreamCharThroughputSnapshot(
      widget.sessionId,
    );
    if (!_listsEqual(next, _samples)) {
      setState(() => _samples = next);
    }
  }

  bool _listsEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    final samples = _samples;
    final peak = samples.isEmpty ? 0 : samples.reduce(math.max);
    final current = samples.isEmpty ? 0 : samples.first;
    final cap = math.max(widget.maxRate, peak == 0 ? 1 : peak);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.show_chart_rounded,
                size: 14,
                color: scheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                isZh ? '字符吞吐 (30s)' : 'Chars Throughput (30s)',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                isZh
                    ? '当前 $current/s · 峰 $peak/s · 上限 ${widget.maxRate}/s'
                    : 'now $current/s · peak $peak/s · cap ${widget.maxRate}/s',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 56,
            // 2026-05-18 — 鼠标悬停 / 触屏拖动时高亮当前桶并展示
            // tooltip：根据指针 X 计算 bucketIndex，setState 重绘
            // painter 让对应柱子 stroke 一圈高亮 + 头顶气泡显示
            // "Ns 前 · X/s"。
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                int? indexAt(Offset local) {
                  if (samples.isEmpty || width <= 0) return null;
                  if (local.dx < 0 || local.dx > width) return null;
                  final n = samples.length;
                  const gap = 1.5;
                  final totalGap = gap * (n - 1);
                  final barW = (width - totalGap) / n;
                  // bucket 0 在最右；指针 X = (n-1-i) * (barW+gap)..+barW
                  final visualSlot =
                      (local.dx / (barW + gap)).floor().clamp(0, n - 1);
                  return n - 1 - visualSlot;
                }

                return MouseRegion(
                  onHover: (event) {
                    final i = indexAt(event.localPosition);
                    if (i != _hoveredIndex || event.localPosition != _hoverLocal) {
                      setState(() {
                        _hoveredIndex = i;
                        _hoverLocal = event.localPosition;
                      });
                    }
                  },
                  onExit: (_) {
                    if (_hoveredIndex != null) {
                      setState(() {
                        _hoveredIndex = null;
                        _hoverLocal = null;
                      });
                    }
                  },
                  child: GestureDetector(
                    onTapDown: (d) {
                      final i = indexAt(d.localPosition);
                      setState(() {
                        _hoveredIndex = i;
                        _hoverLocal = d.localPosition;
                      });
                    },
                    onPanUpdate: (d) {
                      final i = indexAt(d.localPosition);
                      setState(() {
                        _hoveredIndex = i;
                        _hoverLocal = d.localPosition;
                      });
                    },
                    onPanEnd: (_) => setState(() {
                      _hoveredIndex = null;
                      _hoverLocal = null;
                    }),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _ThroughputBarsPainter(
                              samples: samples,
                              cap: cap,
                              color: scheme.primary,
                              gridColor: scheme.outlineVariant
                                  .withValues(alpha: 0.6),
                              limitColor:
                                  scheme.tertiary.withValues(alpha: 0.45),
                              limitValue: widget.maxRate,
                              overLimitColor: scheme.error,
                              hoveredIndex: _hoveredIndex,
                              hoverHighlightColor: scheme.onSurface,
                            ),
                          ),
                        ),
                        if (_hoveredIndex != null && _hoverLocal != null)
                          _ThroughputTooltip(
                            samples: samples,
                            hoveredIndex: _hoveredIndex!,
                            anchor: _hoverLocal!,
                            limitValue: widget.maxRate,
                            isZh: isZh,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ThroughputBarsPainter extends CustomPainter {
  _ThroughputBarsPainter({
    required this.samples,
    required this.cap,
    required this.color,
    required this.gridColor,
    required this.limitColor,
    required this.limitValue,
    required this.overLimitColor,
    this.hoveredIndex,
    this.hoverHighlightColor,
  });

  final List<int> samples;
  final int cap;
  final Color color;
  final Color gridColor;
  final Color limitColor;
  final int limitValue;
  final Color overLimitColor;
  final int? hoveredIndex;
  final Color? hoverHighlightColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty || cap <= 0) {
      _drawEmpty(canvas, size);
      return;
    }
    // 网格底线：底部 1px
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      gridPaint,
    );
    // 上限参考线
    final hasLimit = limitValue > 0 && limitValue <= cap;
    if (hasLimit) {
      final y = size.height - (limitValue / cap) * size.height;
      final dashPaint = Paint()
        ..color = limitColor
        ..strokeWidth = 1.0;
      const dashWidth = 4.0;
      const dashGap = 3.0;
      var x = 0.0;
      while (x < size.width) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + dashWidth, size.width), y),
          dashPaint,
        );
        x += dashWidth + dashGap;
      }
    }
    // 柱子：bucket 0 = 当前秒（最右侧），bucket N-1 = 30s 前（最左）
    final n = samples.length;
    const gap = 1.5;
    final totalGap = gap * (n - 1);
    final barW = (size.width - totalGap) / n;
    for (var i = 0; i < n; i++) {
      final v = samples[i];
      final x = (n - 1 - i) * (barW + gap);
      final h = cap == 0 ? 0.0 : (v / cap) * size.height;
      final clamped = h.clamp(0.0, size.height);
      final rect = Rect.fromLTWH(
        x,
        size.height - clamped,
        barW,
        clamped,
      );
      // 2026-05-18 — 柱状渐变：底部满色 → 顶部柔和透明，让"高度=吞
      // 吐量"的视觉一眼就读得出来；超过 limitValue 的样本切换到红
      // 色 overLimitColor，提示用户当前秒有超阈值释放。
      final overLimit = hasLimit && limitValue > 0 && v > limitValue;
      final baseColor = overLimit ? overLimitColor : color;
      final isCurrent = i == 0;
      final topAlpha = isCurrent ? 1.0 : 0.55;
      final bottomAlpha = isCurrent ? 0.55 : 0.18;
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            baseColor.withValues(alpha: topAlpha),
            baseColor.withValues(alpha: bottomAlpha),
          ],
        ).createShader(rect);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(2));
      canvas.drawRRect(rrect, paint);
      // 超阈值柱子加一道高亮顶边，让用户更明显感知"溢出令牌桶"。
      if (overLimit && clamped > 1) {
        final highlight = Paint()
          ..color = overLimitColor
          ..strokeWidth = 1.4
          ..style = PaintingStyle.stroke;
        canvas.drawLine(
          Offset(rect.left, rect.top + 0.7),
          Offset(rect.right, rect.top + 0.7),
          highlight,
        );
      }
      // 鼠标悬停 / 触屏选中时给当前柱描一圈：让交互即时被感知。
      if (hoveredIndex == i &&
          hoverHighlightColor != null &&
          clamped > 0) {
        final ring = Paint()
          ..color = hoverHighlightColor!
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke;
        canvas.drawRRect(rrect.deflate(0.4), ring);
      }
    }
  }

  void _drawEmpty(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ThroughputBarsPainter old) {
    if (old.cap != cap || old.limitValue != limitValue) return true;
    if (old.samples.length != samples.length) return true;
    for (var i = 0; i < samples.length; i++) {
      if (old.samples[i] != samples[i]) return true;
    }
    return old.color != color ||
        old.gridColor != gridColor ||
        old.limitColor != limitColor ||
        old.overLimitColor != overLimitColor ||
        old.hoveredIndex != hoveredIndex ||
        old.hoverHighlightColor != hoverHighlightColor;
  }
}


/// 仪表盘 hover tooltip 气泡：固定 anchor.x ± 56 偏移，避免触屏点击
/// 时手指挡住读数；超出右边界自动翻转到左侧。
class _ThroughputTooltip extends StatelessWidget {
  const _ThroughputTooltip({
    required this.samples,
    required this.hoveredIndex,
    required this.anchor,
    required this.limitValue,
    required this.isZh,
  });

  final List<int> samples;
  final int hoveredIndex;
  final Offset anchor;
  final int limitValue;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    if (hoveredIndex < 0 || hoveredIndex >= samples.length) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final value = samples[hoveredIndex];
    final ago = hoveredIndex; // bucket 0 = 当前秒，i = i 秒前
    final overLimit = limitValue > 0 && value > limitValue;
    final color = overLimit ? scheme.error : scheme.primary;
    final bg = overLimit ? scheme.errorContainer : scheme.primaryContainer;
    final fg = overLimit ? scheme.onErrorContainer : scheme.onPrimaryContainer;
    final timeLabel = ago == 0
        ? (isZh ? '当前秒' : 'now')
        : (isZh ? '${ago}s 前' : '${ago}s ago');
    return Positioned(
      left: anchor.dx,
      top: 0,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -1.05),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: bg.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.46)),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: 0.16),
                  blurRadius: 6,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  overLimit
                      ? Icons.priority_high_rounded
                      : Icons.bolt_rounded,
                  size: 12,
                  color: color,
                ),
                const SizedBox(width: 4),
                Text(
                  isZh
                      ? '$timeLabel · $value/s'
                      : '$timeLabel · $value/s',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
