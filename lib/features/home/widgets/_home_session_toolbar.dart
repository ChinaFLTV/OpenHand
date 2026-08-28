part of '../openhand_home_page.dart';

const double _kSessionToolbarPillHeight = 32;
const double _kSessionToolbarPillHorizontalPadding = 10;
const double _kSessionToolbarPillIconSize = 14;
const double _kSessionToolbarStatusDotSize = 8;
const Duration _kSessionToolbarPillTransition = kOpenHandMotion220;
const Duration _kSessionToolbarCompactSwitchDuration = Duration(
  milliseconds: 180,
);
const Duration _kSessionToolbarCenterScrollDuration = Duration(
  milliseconds: 520,
);

Future<void> _jumpToCacheHitTurn(
  BuildContext context, {
  required AiSession session,
  required SessionCacheHitTurnPoint point,
  required bool claudeStyle,
}) async {
  final controller = context.read<AiSessionController>();
  var targetMessageId = point.anchorMessageId.trim();
  targetMessageId = targetMessageId.isNotEmpty
      ? targetMessageId
      : point.starterMessageId.trim();
  if (targetMessageId.isEmpty) {
    // Older persisted trend points did not carry the round starter id. Do the
    // one-time full hydration only for that legacy shape, then rebuild the
    // trend to recover the same turn without guessing from list positions.
    final hydrated = await controller.ensureSessionMessagesHydrated(session.id);
    final source = hydrated ?? controller.sessionById(session.id) ?? session;
    final rebuiltTrend = SessionCacheHitTrend.fromSession(
      source,
      claudeStyle: claudeStyle,
    );
    final rebuiltPoint = rebuiltTrend.points
        .where((candidate) => candidate.turnIndex == point.turnIndex)
        .firstOrNull;
    targetMessageId = rebuiltPoint?.anchorMessageId.trim() ?? '';
    targetMessageId = targetMessageId.isNotEmpty
        ? targetMessageId
        : rebuiltPoint?.starterMessageId.trim() ?? '';
  }
  if (targetMessageId.isEmpty) {
    if (context.mounted) {
      showOpenHandInfoSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '该轮次暂时没有可定位的消息。',
          en: 'This round does not have a message to reveal yet.',
        ),
        duration: kOpenHandMotion2200,
      );
    }
    return;
  }
  final ok = await _TranscriptScrollDispatcher.instance.scrollToMessage(
    session.id,
    targetMessageId,
    highlight: true,
  );
  if (!ok && context.mounted) {
    showOpenHandInfoSnack(
      context,
      openHandLocalizedText(
        context,
        zh: '未能定位该轮次消息，消息可能已被删除或没有可展示内容。',
        en: 'Could not reveal this round; its message may be deleted or have no visible content.',
      ),
      duration: kOpenHandMotion2400,
    );
  }
}

class _SessionToolbar extends StatelessWidget {
  const _SessionToolbar({
    required this.session,
    this.liveRuntimeToolPreview,
    this.sendPhase = AiSendPhase.idle,
    this.planTimelineCollapsed = false,
    this.onPlanTimelineCollapsedChanged,
    this.fileExplorerVisible = false,
    this.onFileExplorerToggled,
    this.machineTerminalPanelVisible = false,
    this.onMachineTerminalPanelToggled,
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
  final bool machineTerminalPanelVisible;
  final VoidCallback? onMachineTerminalPanelToggled;
  final AiModelProfile? activeProfile;
  final bool claudeStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
    final goalRecord = _toolbarGoalRecord(session);
    final toolbarItems = <Widget>[
      if (runtimeStatus.notices.isNotEmpty) ...[
        ..._buildMcpLazyLoadingPills(context, runtimeStatus.notices),
        OhPill(
          icon: Icons.info_outline_rounded,
          label: AppLocalizations.of(
            context,
          )!.toolbarRuntimeNotices(runtimeStatus.notices.length),
        ),
      ],
      OhPill(
        icon: Icons.layers_rounded,
        label: '${session.templateName} · v${session.templateInternalVersion}',
      ),
      if (goalRecord != null)
        OhPill(
          icon: Icons.flag_outlined,
          label: _goalToolbarLabel(context, goalRecord),
          onTap: () => _showGoalDetailsDialog(context, session),
        ),
      if (session.templateId == 'hermes_talker')
        const _HermesSelfLearningWarningPill(),
      if (session.templateId == 'web_reverse_expert')
        _WebReverseDebugPill(sessionId: session.id),
      if (session.templateId == 'android_reverse_expert')
        _AndroidReverseDebugPill(session: session),
      OhPill(
        icon: Icons.data_object_rounded,
        label: AppLocalizations.of(context)!.toolbarSessionMetadata,
        onTap: () {
          _showSessionMetadataDialog(
            context,
            session,
            liveRuntimeToolPreview: liveRuntimeToolPreview,
            activeProfile: activeProfile,
            claudeStyle: claudeStyle,
          );
        },
      ),
      _StreamThrottlePill(sessionId: session.id),
      if (showPlanTimelineToggle && planTimelineCollapsed)
        AnimatedSwitcher(
          duration: openHandMotionDuration(
            context,
            _kSessionToolbarCompactSwitchDuration,
          ),
          switchInCurve: kOpenHandSwitchInCurve,
          switchOutCurve: kOpenHandSwitchOutCurve,
          child: OhPill(
            key: ValueKey<bool>(planTimelineCollapsed),
            icon: Icons.unfold_more_rounded,
            label: AppLocalizations.of(context)!.toolbarShowPlan,
            onTap: () => onPlanTimelineCollapsedChanged?.call(false),
          ),
        ),
      if (onFileExplorerToggled != null)
        OhPill(
          icon: fileExplorerVisible
              ? Icons.folder_open_rounded
              : Icons.folder_outlined,
          label: _localizedFilesToggle(context, fileExplorerVisible),
          onTap: onFileExplorerToggled,
        ),
      if (onMachineTerminalPanelToggled != null)
        AnimatedSwitcher(
          duration: openHandMotionDuration(
            context,
            _kSessionToolbarCompactSwitchDuration,
          ),
          switchInCurve: kOpenHandSwitchInCurve,
          switchOutCurve: kOpenHandSwitchOutCurve,
          child: OhPill(
            key: ValueKey<bool>(machineTerminalPanelVisible),
            icon: machineTerminalPanelVisible
                ? Icons.terminal_rounded
                : Icons.terminal_outlined,
            label: _localizedMachineTerminalToggle(
              context,
              machineTerminalPanelVisible,
            ),
            onTap: onMachineTerminalPanelToggled,
          ),
        ),
      OpenHandSessionTokenUsageDial(
        session: session,
        statistics: session.statistics,
        activeProfile: activeProfile,
        claudeStyle: claudeStyle,
        onCacheHitTrendPointSelected: (point) {
          unawaited(
            _jumpToCacheHitTurn(
              context,
              session: session,
              point: point,
              claudeStyle: claudeStyle,
            ),
          );
        },
      ),
    ];
    return OpenHandSessionHeaderBar(
      toolbarItems: toolbarItems,
      title: OpenHandAnimatedTitleText(
        text: session.title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
      below: AnimatedSwitcher(
        duration: cardMotionDurationFor(
          context,
          expanding: !planTimelineCollapsed,
        ),
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
          final fade = openHandBoundedCurveAnimation(
            parent: animation,
            curve: kOpenHandSwitchInCurve,
            reverseCurve: kOpenHandSwitchOutCurve,
          );
          final slide = openHandCurveAnimation(
            parent: animation,
            curve: kCardMotionCurve,
            reverseCurve: kOpenHandSwitchOutCurve,
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
                  ).animate(slide),
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
    );
  }
}

class _SessionToolbarStatusPill extends StatelessWidget {
  const _SessionToolbarStatusPill({
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.dotColor,
    required this.onTap,
    this.reduceMotion = false,
    this.glowingDot = false,
    this.maxLabelWidth,
    this.tabularLabel = false,
  });

  final String tooltip;
  final IconData icon;
  final String label;
  final Color dotColor;
  final VoidCallback? onTap;
  final bool reduceMotion;
  final bool glowingDot;
  final double? maxLabelWidth;
  final bool tabularLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final duration = reduceMotion
        ? Duration.zero
        : openHandMotionDuration(context, _kSessionToolbarPillTransition);
    final labelText = AnimatedSwitcher(
      duration: duration,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: Text(
        label,
        key: ValueKey<String>(label),
        maxLines: 1,
        overflow: maxLabelWidth == null
            ? TextOverflow.fade
            : TextOverflow.ellipsis,
        softWrap: false,
        style: theme.textTheme.labelMedium?.copyWith(
          fontFeatures: tabularLabel
              ? const <FontFeature>[FontFeature.tabularFigures()]
              : null,
          color: cs.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    final pill = AnimatedContainer(
      duration: duration,
      curve: kOpenHandSwitchInCurve,
      height: _kSessionToolbarPillHeight,
      padding: const EdgeInsets.symmetric(
        horizontal: _kSessionToolbarPillHorizontalPadding,
      ),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: kOpenHandPillBorderRadius,
        border: Border.all(color: dotColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: duration,
            curve: kOpenHandSwitchInCurve,
            width: _kSessionToolbarStatusDotSize,
            height: _kSessionToolbarStatusDotSize,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
              boxShadow: glowingDot
                  ? [
                      BoxShadow(
                        color: dotColor.withValues(alpha: 0.55),
                        blurRadius: 6,
                      ),
                    ]
                  : null,
            ),
          ),
          kOpenHandHGap6,
          Icon(
            icon,
            size: _kSessionToolbarPillIconSize,
            color: cs.onSurfaceVariant,
          ),
          kOpenHandHGap4,
          if (maxLabelWidth == null)
            labelText
          else
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxLabelWidth!),
              child: labelText,
            ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Tooltip(
        message: tooltip,
        waitDuration: kOpenHandTooltipWait,
        child: MicroPressFeedback(
          enabled: onTap != null,
          child: Material(
            color: Colors.transparent,
            borderRadius: kOpenHandPillBorderRadius,
            child: InkWell(
              borderRadius: kOpenHandPillBorderRadius,
              onTap: onTap,
              overlayColor: WidgetStatePropertyAll<Color>(
                cs.primary.withValues(alpha: 0.08),
              ),
              child: pill,
            ),
          ),
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
    final tooltip = openHandLocalizedText(
      context,
      zh:
          '当前 Hermes Talker 自主学习能力已关闭。\n\n'
          '影响：AI 不会在后台周期性地把本会话沉淀的偏好、画像、'
          '通用记忆与可复用技能持久化到长期记忆库——下次新会话将无法'
          '基于这些信息做更贴心的回应。\n\n'
          '建议：前往「定时任务」面板，把 “Hermes Talker 自我学习” '
          '开关打开即可恢复。',
      zhHant:
          '目前 Hermes Talker 自主學習能力已關閉。\n\n'
          '影響：AI 不會在背景週期性地把本會話沉澱的偏好、画像、'
          '通用記憶與可複用技能持久化到長期記憶庫；下次新會話將無法'
          '基於這些資訊做更貼心的回應。\n\n'
          '建議：前往「定時任務」面板，開啟 “Hermes Talker 自我學習” '
          '即可恢復。',
      en:
          'Hermes Talker self-learning is currently disabled.\n\n'
          'Impact: the agent will not periodically persist the preferences, '
          'profile, general memories or reusable skills absorbed from this '
          'conversation. Future sessions will lose this background context.\n\n'
          'Tip: open the Crons panel and re-enable '
          '"Hermes Talker self-learning" to resume.',
      fr:
          'L’auto-apprentissage de Hermes Talker est désactivé.\n\n'
          'Impact : l’agent ne persistera pas périodiquement les préférences, '
          'le profil, les souvenirs généraux ou les compétences réutilisables '
          'issus de cette conversation. Les futures sessions perdront ce contexte.\n\n'
          'Conseil : ouvrez le panneau Crons et réactivez '
          '"Hermes Talker self-learning".',
      de:
          'Hermes Talker Self-Learning ist derzeit deaktiviert.\n\n'
          'Auswirkung: Der Agent speichert Präferenzen, Profil, allgemeine '
          'Erinnerungen und wiederverwendbare Skills aus dieser Unterhaltung '
          'nicht regelmäßig dauerhaft. Künftige Sitzungen verlieren diesen Kontext.\n\n'
          'Tipp: Öffne das Crons-Panel und aktiviere '
          '"Hermes Talker self-learning" erneut.',
      ja:
          'Hermes Talker の自己学習は現在オフです。\n\n'
          '影響: エージェントはこの会話から得た設定、プロフィール、'
          '一般的な記憶、再利用可能なスキルを定期的に長期記憶へ保存しません。'
          '今後のセッションではこの背景コンテキストが失われます。\n\n'
          'ヒント: Crons パネルで "Hermes Talker self-learning" を再度有効にしてください。',
    );
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Tooltip(
        message: tooltip,
        waitDuration: kOpenHandTooltipWait,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: colorScheme.errorContainer.withValues(alpha: 0.55),
            borderRadius: kOpenHandPillBorderRadius,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: colorScheme.onErrorContainer,
              ),
              kOpenHandHGap6,
              Text(
                openHandLocalizedText(
                  context,
                  zh: '自主学习已关闭',
                  zhHant: '自主學習已關閉',
                  en: 'Self-learning off',
                  fr: 'Auto-apprentissage désactivé',
                  de: 'Self-Learning aus',
                  ja: '自己学習オフ',
                ),
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
        duration: animated
            ? openHandMotionDuration(
                context,
                _kSessionToolbarCenterScrollDuration,
              )
            : Duration.zero,
        curve: animated ? kOpenHandSwitchInCurve : Curves.linear,
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
        borderRadius: kOpenHandBorderRadius18,
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
                  borderRadius: kOpenHandBorderRadius10,
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
              kOpenHandHGap10,
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
              if (onVisibilityToggle != null) ...[
                _PlanTimelineVisibilityButton(
                  label: AppLocalizations.of(context)!.toolbarHidePlan,
                  icon: Icons.unfold_less_rounded,
                  color: statusColor,
                  onTap: onVisibilityToggle,
                ),
                kOpenHandHGap12,
              ],
              AnimatedSwitcher(
                duration: openHandMotionDuration(
                  context,
                  _kSessionToolbarCompactSwitchDuration,
                ),
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
          kOpenHandGap12,
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
        borderRadius: kOpenHandPillBorderRadius,
        child: InkWell(
          onTap: onTap,
          borderRadius: kOpenHandPillBorderRadius,
          overlayColor: WidgetStatePropertyAll<Color>(
            color.withValues(alpha: 0.08),
          ),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: kOpenHandPillBorderRadius,
              border: Border.all(color: color.withValues(alpha: 0.20)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: color),
                kOpenHandHGap6,
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
            borderRadius: kOpenHandPillBorderRadius,
          ),
          alignment: Alignment.center,
          child: marker,
        ),
        kOpenHandHGap8,
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
      borderRadius: kOpenHandBorderRadius16,
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
              borderRadius: kOpenHandBorderRadius16,
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
            duration: openHandMotionDuration(
              context,
              _kSessionToolbarPillTransition,
            ),
            curve: kOpenHandSwitchInCurve,
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
                borderRadius: kOpenHandPillBorderRadius,
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
  // 单一真相 = `session.awaitingPlanApproval`。
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
  final normalizedLabels = trimmedNonEmptyStrings(stepLabels);
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
  return trimmedNonEmptyStrings(planRecord.steps.map((item) => item.content));
}

bool _shouldReflectCurrentPlanStepFailure(
  AiSession session,
  AiSendPhase sendPhase,
) {
  if (sendPhase != AiSendPhase.idle) {
    return false;
  }
  final latestRecoveryMessage = _latestPlanRecoveryTimelineMessage(session);
  if (shouldReflectAiPlanFailureAfter(
    latestAiPlanErrorFailureAt(session),
    latestRecoveryMessage,
  )) {
    return true;
  }
  return shouldReflectAiPlanFailureAfter(
    latestAiPlanToolFailureAt(session),
    latestRecoveryMessage,
  );
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
      silentLog('session_toolbar', '解析计划时间线 edited_at', error, stack);
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
  final controller = context.read<AiSessionController>();
  return showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) => _LiveSessionMetadataDialog(
      session: session,
      controller: controller,
      liveRuntimeToolPreview: liveRuntimeToolPreview,
      activeProfile: activeProfile,
      claudeStyle: claudeStyle,
    ),
  );
}

AiSessionGoalRecord? _toolbarGoalRecord(AiSession session) {
  final active = session.activeGoal;
  if (active != null) {
    return active;
  }
  if (session.mode != AiSessionMode.goal || session.goalState.history.isEmpty) {
    return null;
  }
  return session.goalState.history.last;
}

String _goalToolbarLabel(BuildContext context, AiSessionGoalRecord goal) {
  final status = _goalStatusLabel(context, goal.status);
  final maxTurns = goal.maxTurns ?? aiSessionGoalDefaultMaxAutoTurns;
  final turnText = '${goal.turnCount}/$maxTurns';
  final budgetText = goal.tokenBudget == null
      ? ''
      : ' · ${goal.tokensUsed}/${goal.tokenBudget} tok';
  return openHandLocalizedText(
    context,
    zh: '目标 $status · $turnText$budgetText',
    en: 'Goal $status · $turnText$budgetText',
  );
}

String _goalStatusLabel(BuildContext context, AiSessionGoalStatus status) {
  return switch (status) {
    AiSessionGoalStatus.running => openHandLocalizedText(
      context,
      zh: '运行中',
      en: 'running',
    ),
    AiSessionGoalStatus.paused => openHandLocalizedText(
      context,
      zh: '已暂停',
      en: 'paused',
    ),
    AiSessionGoalStatus.completed => openHandLocalizedText(
      context,
      zh: '已完成',
      en: 'completed',
    ),
    AiSessionGoalStatus.terminated => openHandLocalizedText(
      context,
      zh: '已终止',
      en: 'terminated',
    ),
    AiSessionGoalStatus.failed => openHandLocalizedText(
      context,
      zh: '失败',
      zhHant: '失敗',
      en: 'failed',
      fr: 'échec',
      de: 'fehlgeschlagen',
      ja: '失敗',
    ),
    AiSessionGoalStatus.roundLimitReached => openHandLocalizedText(
      context,
      zh: '轮次耗尽',
      en: 'turn limit',
    ),
    AiSessionGoalStatus.tokenBudgetReached => openHandLocalizedText(
      context,
      zh: '预算耗尽',
      en: 'budget limit',
    ),
  };
}

String _goalStatusReasonLabel(BuildContext context, String reason) {
  final normalized = reason.trim();
  return switch (normalized) {
    'Paused by user.' => openHandLocalizedText(
      context,
      zh: '用户已暂停目标。',
      en: 'Paused by user.',
    ),
    aiSessionGoalPausedForQueueStatusReason => openHandLocalizedText(
      context,
      zh: '已让出给等待队列中的消息。',
      en: aiSessionGoalPausedForQueueStatusReason,
    ),
    'Terminated by user.' => openHandLocalizedText(
      context,
      zh: '用户已终止目标。',
      en: 'Terminated by user.',
    ),
    'Resumed by goal runtime.' => openHandLocalizedText(
      context,
      zh: '目标运行时已恢复执行。',
      en: 'Resumed by goal runtime.',
    ),
    'Token budget reached before evaluation.' => openHandLocalizedText(
      context,
      zh: '评估前已达到 token 预算。',
      en: 'Token budget reached before evaluation.',
    ),
    'No evaluator model is configured.' => openHandLocalizedText(
      context,
      zh: '未配置可用评估模型。',
      en: 'No evaluator model is configured.',
    ),
    'Round limit reached before evidence was sufficient.' =>
      openHandLocalizedText(
        context,
        zh: '证据充分前已达到轮次限制。',
        en: 'Round limit reached before evidence was sufficient.',
      ),
    'Token budget reached before evidence was sufficient.' =>
      openHandLocalizedText(
        context,
        zh: '证据充分前已达到 token 预算。',
        en: 'Token budget reached before evidence was sufficient.',
      ),
    _ => normalized,
  };
}

String _goalEvaluationSummaryLabel(BuildContext context, String summary) {
  final normalized = summary.trim();
  return switch (normalized) {
    'Evaluator failed.' => openHandLocalizedText(
      context,
      zh: '评估模型调用失败。',
      en: 'Evaluator failed.',
    ),
    'Evaluator returned invalid JSON.' => openHandLocalizedText(
      context,
      zh: '评估模型返回了无效 JSON。',
      en: 'Evaluator returned invalid JSON.',
    ),
    'Goal is complete.' => openHandLocalizedText(
      context,
      zh: '目标已完成。',
      en: 'Goal is complete.',
    ),
    'Goal is not complete yet.' => openHandLocalizedText(
      context,
      zh: '目标尚未完成。',
      en: 'Goal is not complete yet.',
    ),
    _ => normalized,
  };
}

String _formatGoalDateTime(BuildContext context, DateTime? value) {
  if (value == null) {
    return '-';
  }
  final local = value.toLocal();
  final material = MaterialLocalizations.of(context);
  final time = TimeOfDay.fromDateTime(local);
  return '${material.formatShortDate(local)} ${material.formatTimeOfDay(time, alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}';
}

Future<void> _showGoalDetailsDialog(BuildContext context, AiSession session) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) => _GoalDetailsDialog(session: session),
  );
}

class _GoalDetailsDialog extends StatelessWidget {
  const _GoalDetailsDialog({required this.session});

  final AiSession session;

  @override
  Widget build(BuildContext context) {
    final state = session.goalState;
    final current = state.current;
    final recentHistory = state.history.reversed
        .take(8)
        .toList(growable: false);
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;
    return buildOpenHandAlertDialog(
      title: Text(
        openHandLocalizedText(context, zh: '目标执行详情', en: 'Goal Details'),
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
      content: buildOpenHandDialogConstrainedContent(
        width: 680,
        maxHeight: maxHeight,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (current != null)
                _GoalRecordSection(
                  title: openHandLocalizedText(
                    context,
                    zh: '当前目标',
                    en: 'Current Goal',
                  ),
                  goal: current,
                )
              else
                Text(
                  openHandLocalizedText(
                    context,
                    zh: '当前没有正在执行的目标。',
                    en: 'No goal is currently active.',
                  ),
                ),
              kOpenHandGap16,
              _GoalEnvironmentSection(session: session),
              if (recentHistory.isNotEmpty) ...[
                kOpenHandGap16,
                Text(
                  openHandLocalizedText(
                    context,
                    zh: '历史目标',
                    en: 'Goal History',
                  ),
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                kOpenHandGap8,
                ...recentHistory.map(
                  (goal) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _GoalRecordSection(
                      title: _goalStatusLabel(context, goal.status),
                      goal: goal,
                      compact: true,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        OpenHandDialogActionButton.primary(
          onPressed: () => Navigator.of(context).pop(),
          label: openHandCloseLabel(context),
        ),
      ],
    );
  }
}

class _GoalRecordSection extends StatelessWidget {
  const _GoalRecordSection({
    required this.title,
    required this.goal,
    this.compact = false,
  });

  final String title;
  final AiSessionGoalRecord goal;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final evaluations = compact
        ? goal.evaluations.reversed.take(2).toList(growable: false)
        : goal.evaluations.reversed.take(6).toList(growable: false);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kOpenHandRadius18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            kOpenHandGap8,
            Text(goal.objective, style: theme.textTheme.bodyMedium),
            kOpenHandGap10,
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _GoalMiniChip(
                  label: _goalStatusLabel(context, goal.status),
                  icon: Icons.flag_outlined,
                ),
                _GoalMiniChip(
                  label:
                      '${goal.turnCount}/${goal.maxTurns ?? aiSessionGoalDefaultMaxAutoTurns}',
                  icon: Icons.repeat_rounded,
                ),
                if (goal.tokenBudget != null)
                  _GoalMiniChip(
                    label: '${goal.tokensUsed}/${goal.tokenBudget} tok',
                    icon: Icons.speed_rounded,
                  ),
                _GoalMiniChip(
                  label: goal.evaluatorModelLabel,
                  icon: Icons.psychology_alt_outlined,
                ),
              ],
            ),
            kOpenHandGap12,
            _GoalKeyValue(
              openHandCreatedLabel(context),
              _formatGoalDateTime(context, goal.createdAt),
            ),
            _GoalKeyValue(
              openHandUpdatedLabel(context),
              _formatGoalDateTime(context, goal.updatedAt),
            ),
            if (goal.completedAt != null)
              _GoalKeyValue(
                openHandLocalizedText(context, zh: '完成时间', en: 'Completed'),
                _formatGoalDateTime(context, goal.completedAt),
              ),
            if (goal.terminatedAt != null)
              _GoalKeyValue(
                openHandLocalizedText(context, zh: '终止时间', en: 'Terminated'),
                _formatGoalDateTime(context, goal.terminatedAt),
              ),
            if ((goal.statusReason ?? '').trim().isNotEmpty) ...[
              kOpenHandGap10,
              Text(
                _goalStatusReasonLabel(context, goal.statusReason!),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (evaluations.isNotEmpty) ...[
              kOpenHandGap12,
              ...evaluations.map(
                (evaluation) => Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _GoalEvaluationRow(evaluation: evaluation),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GoalMiniChip extends StatelessWidget {
  const _GoalMiniChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: kOpenHandPillBorderRadius,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.primary),
          kOpenHandHGap6,
          Text(label, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _GoalEvaluationRow extends StatelessWidget {
  const _GoalEvaluationRow({required this.evaluation});

  final AiSessionGoalEvaluationRecord evaluation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = evaluation.passed
        ? OpenHandStatusColors.success
        : theme.colorScheme.tertiary;
    final statusLabel = evaluation.passed
        ? openHandLocalizedText(context, zh: '证据通过', en: 'Evidence Passed')
        : openHandLocalizedText(context, zh: '继续推进', en: 'Continue Goal');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: kOpenHandBorderRadius12,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  evaluation.passed
                      ? Icons.verified_outlined
                      : Icons.manage_search_rounded,
                  size: 16,
                  color: color,
                ),
                kOpenHandHGap6,
                Expanded(
                  child: Text(
                    statusLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
                Text(
                  '#${evaluation.roundIndex} · ${_formatGoalDateTime(context, evaluation.createdAt)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            if (_goalEvaluationSummaryLabel(
              context,
              evaluation.summary,
            ).isNotEmpty) ...[
              kOpenHandGap6,
              Text(
                _goalEvaluationSummaryLabel(context, evaluation.summary),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
            if (evaluation.evidence.isNotEmpty) ...[
              kOpenHandGap8,
              _GoalInlineList(
                label: _homeEvidenceLabel(context),
                values: evaluation.evidence,
                color: OpenHandStatusColors.success,
              ),
            ],
            if (evaluation.missing.isNotEmpty) ...[
              kOpenHandGap8,
              _GoalInlineList(
                label: _homeMissingLabel(context),
                values: evaluation.missing,
                color: theme.colorScheme.tertiary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GoalInlineList extends StatelessWidget {
  const _GoalInlineList({
    required this.label,
    required this.values,
    required this.color,
  });

  final String label;
  final List<String> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
        kOpenHandGap6,
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final value in values.take(4))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: kOpenHandPillBorderRadius,
                  border: Border.all(color: color.withValues(alpha: 0.18)),
                ),
                child: Text(
                  value,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _GoalEnvironmentSection extends StatelessWidget {
  const _GoalEnvironmentSection({required this.session});

  final AiSession session;

  @override
  Widget build(BuildContext context) {
    final environment = session.environment;
    return _GoalRecordShell(
      title: openHandEnvironmentLabel(context),
      children: [
        _GoalKeyValue(
          openHandLocalizedText(context, zh: '线程', en: 'Session'),
          session.id,
        ),
        _GoalKeyValue(openHandTemplateLabel(context), session.templateName),
        _GoalKeyValue(
          openHandLocalizedText(context, zh: '当前模式', en: 'Mode'),
          _runtimeModeLabel(context, null, explicitMode: session.mode),
        ),
        _GoalKeyValue(
          openHandLocalizedText(context, zh: '消息数', en: 'Messages'),
          '${session.messages.length}',
        ),
        _GoalKeyValue(_homePlatformLabel(context), environment.platform),
        _GoalKeyValue(
          _homeWorkingDirectoryLabel(context),
          environment.applicationDirectory,
        ),
        _GoalKeyValue(
          _homeSessionsDirectoryLabel(context),
          environment.sessionsDirectoryPath,
        ),
      ],
    );
  }
}

class _GoalRecordShell extends StatelessWidget {
  const _GoalRecordShell({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kOpenHandRadius18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            kOpenHandGap8,
            ...children,
          ],
        ),
      ),
    );
  }
}

class _GoalKeyValue extends StatelessWidget {
  const _GoalKeyValue(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              nonBlankStringOr(value, '-'),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

int _metadataInt(Object? rawValue) {
  return intFromValue(
    rawValue is int ? rawValue : stringFromValue(rawValue),
    fallback: 0,
  );
}

List<Map<String, Object?>> _metadataObjectList(Object? rawValue) {
  return stringKeyedMapListFromValue(rawValue);
}

List<String> _metadataStringList(Object? rawValue) {
  return rawValue is List ? stringListFromValue(rawValue) : const <String>[];
}

class _RuntimeToolCatalogStatus {
  const _RuntimeToolCatalogStatus({
    required this.sessionMode,
    required this.fullAccessPermission,
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
  final bool fullAccessPermission;
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
      fullAccessPermission: livePreview.fullAccessPermission,
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
    fullAccessPermission: session.fullAccessPermission,
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
  if (mode == AiSessionMode.goal) {
    return openHandLocalizedText(context, zh: '目标模式', en: 'Goal Mode');
  }
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

String _localizedFilesToggle(BuildContext context, bool visible) {
  final l10n = AppLocalizations.of(context)!;
  return visible ? l10n.toolbarFilesHide : l10n.toolbarFilesShow;
}

String _localizedMachineTerminalToggle(BuildContext context, bool visible) {
  return openHandLocalizedText(
    context,
    zh: visible ? '关闭终端' : '打开终端',
    zhHant: visible ? '關閉終端' : '打開終端',
    en: visible ? 'Hide Terminal' : 'Open Terminal',
    fr: visible ? 'Masquer le terminal' : 'Ouvrir le terminal',
    de: visible ? 'Terminal ausblenden' : 'Terminal öffnen',
    ja: visible ? 'ターミナルを閉じる' : 'ターミナルを開く',
  );
}

IconData _runtimeModeIcon(
  _RuntimeToolCatalogStatus? status, {
  AiSessionMode? explicitMode,
}) {
  final mode = explicitMode ?? status?.sessionMode ?? AiSessionMode.chat;
  if (mode == AiSessionMode.goal) {
    return Icons.flag_outlined;
  }
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
  if (mode == AiSessionMode.goal) {
    return openHandLocalizedText(
      context,
      zh: '目标模式已启用 · 点击切换到聊天模式',
      en: 'Goal mode active · switch to chat mode',
    );
  }
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

/// 解析 MCP 懒加载通知并生成已加载工具数量胶囊。
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
    final deferred = optionalNonNegativeIntFromValue(match.group(1));
    final total = optionalPositiveIntFromValue(match.group(2));
    if (deferred == null || total == null) continue;
    final loaded = (total - deferred).clamp(0, total);
    return <Widget>[
      Tooltip(
        message: notice,
        child: OhPill(
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

Future<AiManualCompactionResult> _requestSessionManualCompaction(
  BuildContext context,
  String sessionId,
) async {
  final home = _OpenHandHomePageState._activeHomeState;
  if (home == null || !home.mounted) {
    throw StateError(
      openHandLocalizedText(
        context,
        zh: '压缩入口暂不可用，请稍后再试。',
        en: 'Compaction is unavailable right now.',
      ),
    );
  }
  final selectedModel = context.read<SettingsController>().selectedAiModel;
  if (selectedModel == null) {
    throw StateError(
      openHandLocalizedText(
        context,
        zh: '请先选择有效的 AI 模型。',
        en: 'Pick an AI model first.',
      ),
    );
  }
  return context.read<AiSessionController>().requestManualCompaction(
    sessionId: sessionId,
    model: selectedModel,
    runtimeContext: await home._buildRuntimeContext(),
  );
}

({String message, bool isError}) _manualCompactionFeedback(
  BuildContext context,
  AiManualCompactionResult result,
) {
  return switch (result.status) {
    AiManualCompactionStatus.success => (
      message: openHandLocalizedText(
        context,
        zh: '已生成压缩检查点。',
        en: 'Compaction checkpoint added.',
      ),
      isError: false,
    ),
    AiManualCompactionStatus.cooldown => (
      message: openHandLocalizedText(
        context,
        zh: '刚刚已经压缩过，约 ${result.retryAfter?.inSeconds ?? 30} 秒后再试。',
        en:
            'Just compacted; retry in about '
            '${result.retryAfter?.inSeconds ?? 30} s.',
      ),
      isError: true,
    ),
    AiManualCompactionStatus.notNeeded => (
      message: openHandLocalizedText(
        context,
        zh: '当前占用过低或没有可压缩的历史。',
        en: 'Usage too low — nothing meaningful to compact.',
      ),
      isError: true,
    ),
    AiManualCompactionStatus.inflight => (
      message: openHandLocalizedText(
        context,
        zh: '已有压缩任务在进行中。',
        en: 'A compaction is already in flight.',
      ),
      isError: true,
    ),
    AiManualCompactionStatus.sessionBusy => (
      message: openHandLocalizedText(
        context,
        zh: '当前会话正在响应，请等回复结束后再压缩。',
        en: 'Session is busy. Wait for the current response to finish.',
      ),
      isError: true,
    ),
    AiManualCompactionStatus.circuitBreaker => (
      message: openHandLocalizedText(
        context,
        zh: '连续压缩失败已熔断，稍后再试。',
        en: 'Compaction circuit breaker tripped; retry later.',
      ),
      isError: true,
    ),
    AiManualCompactionStatus.failed => (
      message: openHandLocalizedText(
        context,
        zh: '压缩未生效，请稍后重试。',
        en: 'Compaction did not apply; please retry.',
      ),
      isError: true,
    ),
    AiManualCompactionStatus.noSession => (
      message: openHandLocalizedText(
        context,
        zh: '会话不存在或已被删除。',
        en: 'Session no longer exists.',
      ),
      isError: true,
    ),
  };
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
      await showWebReverseDashboardDialog(
        context,
        controller: ctrl,
        sessionId: widget.sessionId,
        onCdpMcpEnabledChanged: (enabled) => state.setWebReverseCdpMcpEnabled(
          widget.sessionId,
          enabled: enabled,
        ),
        onRestartBrowser: () =>
            state.restartWebReverseBrowser(widget.sessionId, ctrl),
      );
      return;
    }
    // 应用重启 / 切回旧会话：尝试根据 metadata 重启 controller。
    // 这里不能用会抛异常的 orElse：本方法是挂在点击回调上的 Future<void>，
    // 抛出的 StateError 没有任何 catch 接住，只会落到 zone。Web 网关删掉当前
    // 会话后本帧胶囊尚未卸载，用户点一下就会产生未捕获异步异常。
    final session = context
        .read<AiSessionController>()
        .sessions
        .cast<AiSession?>()
        .firstWhere((s) => s?.id == widget.sessionId, orElse: () => null);
    if (session == null) return;
    setState(() => _restoring = true);
    try {
      final restored = await state.restoreWebReverseSession(session);
      if (restored != null && mounted) {
        await showWebReverseDashboardDialog(
          context,
          controller: restored,
          sessionId: widget.sessionId,
          onCdpMcpEnabledChanged: (enabled) => state.setWebReverseCdpMcpEnabled(
            widget.sessionId,
            enabled: enabled,
          ),
          onRestartBrowser: () =>
              state.restartWebReverseBrowser(widget.sessionId, restored),
        );
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final reduceMotion = !openHandTickerMotionEnabled(context);
    final text = openHandTextResolver(context);

    final cdpRuntimeMeta = context.select<AiSessionController, Object?>((
      controller,
    ) {
      for (final session in controller.sessions) {
        if (session.id != widget.sessionId) continue;
        return webReverseCurrentCdpRuntimeMetadata(session.metadata);
      }
      return null;
    });

    final running = ctrl?.isRunning ?? false;
    final reqs = ctrl?.networkRequests.length ?? 0;
    final errs = ctrl?.errorCount ?? 0;
    final cdpStatus = _WebReverseDebugCdpStatus.fromRuntime(
      cdpRuntimeMeta,
      controller: ctrl,
      context: context,
    );
    final dotColor = !running
        ? cs.outline
        : errs > 0 || cdpStatus.tone == _WebReverseDebugCdpTone.failed
        ? cs.error
        : cdpStatus.tone == _WebReverseDebugCdpTone.disabled
        ? cs.onSurfaceVariant
        : cdpStatus.tone == _WebReverseDebugCdpTone.ready
        ? cs.primary
        : cs.tertiary;
    final label = _restoring
        ? text(
            zh: '启动中…',
            zhHant: '啟動中…',
            en: 'starting…',
            fr: 'démarrage…',
            de: 'startet…',
            ja: '起動中…',
          )
        : running
        ? text(
            zh: '$reqs · $errs 错 · ${cdpStatus.label}',
            zhHant: '$reqs · $errs 錯 · ${cdpStatus.label}',
            en: '$reqs · $errs err · ${cdpStatus.label}',
            fr: '$reqs · $errs err · ${cdpStatus.label}',
            de: '$reqs · $errs Fehler · ${cdpStatus.label}',
            ja: '$reqs · $errs 件のエラー · ${cdpStatus.label}',
          )
        : text(
            zh: '点击连接',
            zhHant: '點擊連線',
            en: 'click to connect',
            fr: 'cliquer pour connecter',
            de: 'zum Verbinden klicken',
            ja: 'クリックして接続',
          );
    final tooltip = <String>[
      text(
        zh: 'Web 逆向调试面板',
        zhHant: 'Web 逆向除錯面板',
        en: 'Web Reverse Debugger',
        fr: 'Débogueur Web Reverse',
        de: 'Web-Reverse-Debugger',
        ja: 'Web Reverse デバッガ',
      ),
      text(
        zh: '浏览器: ${running ? "运行中" : "未连接"}',
        zhHant: '瀏覽器: ${running ? "執行中" : "未連線"}',
        en: 'Browser: ${running ? "running" : "not connected"}',
        fr: 'Navigateur : ${running ? "actif" : "non connecté"}',
        de: 'Browser: ${running ? "läuft" : "nicht verbunden"}',
        ja: 'ブラウザ: ${running ? "実行中" : "未接続"}',
      ),
      text(
        zh: '请求数: $reqs',
        zhHant: '請求數: $reqs',
        en: 'Requests: $reqs',
        fr: 'Requêtes : $reqs',
        de: 'Anfragen: $reqs',
        ja: 'リクエスト数: $reqs',
      ),
      text(
        zh: '错误数: $errs',
        zhHant: '錯誤數: $errs',
        en: 'Errors: $errs',
        fr: 'Erreurs : $errs',
        de: 'Fehler: $errs',
        ja: 'エラー数: $errs',
      ),
      cdpStatus.tooltip,
    ].join('\n');

    return _SessionToolbarStatusPill(
      tooltip: tooltip,
      icon: Icons.bug_report_rounded,
      label: label,
      dotColor: dotColor,
      onTap: _restoring ? null : _onPillTap,
      reduceMotion: reduceMotion,
      glowingDot: running && errs == 0,
      maxLabelWidth: 136,
      tabularLabel: true,
    );
  }
}

enum _WebReverseDebugCdpTone { disabled, ready, preparing, failed, unavailable }

class _WebReverseDebugCdpStatus {
  const _WebReverseDebugCdpStatus({
    required this.tone,
    required this.label,
    required this.tooltip,
  });

  final _WebReverseDebugCdpTone tone;
  final String label;
  final String tooltip;

  static _WebReverseDebugCdpStatus fromRuntime(
    Object? runtime, {
    required WebReverseSessionController? controller,
    required BuildContext context,
  }) {
    final runtimeStatus = WebReverseCdpMcpRuntimeStatus.fromRuntime(
      runtime,
      controllerBrowserAlive: controller?.isBrowserAlive,
      controllerPort: controller?.cdpPort,
    );

    late final _WebReverseDebugCdpTone tone;
    late final String label;
    if (runtimeStatus.rawStatus == 'disabled') {
      tone = _WebReverseDebugCdpTone.disabled;
      label = openHandLocalizedText(
        context,
        zh: 'MCP未启用',
        zhHant: 'MCP未啟用',
        en: 'MCP off',
        fr: 'MCP désactivé',
        de: 'MCP aus',
        ja: 'MCP オフ',
      );
    } else if (runtimeStatus.ready) {
      tone = _WebReverseDebugCdpTone.ready;
      label = 'CDP ${runtimeStatus.toolCount}';
    } else if (!runtimeStatus.browserAlive) {
      tone = _WebReverseDebugCdpTone.unavailable;
      label = openHandLocalizedText(
        context,
        zh: 'CDP离线',
        zhHant: 'CDP離線',
        en: 'CDP off',
        fr: 'CDP hors ligne',
        de: 'CDP offline',
        ja: 'CDP オフライン',
      );
    } else if (runtimeStatus.rawStatus == 'preparing') {
      tone = _WebReverseDebugCdpTone.preparing;
      label = 'CDP…';
    } else if (runtimeStatus.rawStatus == 'failed') {
      tone = _WebReverseDebugCdpTone.failed;
      label = 'CDP!';
    } else {
      tone = _WebReverseDebugCdpTone.unavailable;
      label = openHandLocalizedText(
        context,
        zh: 'CDP待同步',
        zhHant: 'CDP待同步',
        en: 'CDP pending',
        fr: 'CDP en attente',
        de: 'CDP ausstehend',
        ja: 'CDP 同期待ち',
      );
    }

    final tooltipLines = <String>[
      openHandLocalizedText(
        context,
        zh: 'AI 侧 CDP MCP',
        zhHant: 'AI 側 CDP MCP',
        en: 'AI-side CDP MCP',
        fr: 'CDP MCP côté IA',
        de: 'KI-seitiges CDP MCP',
        ja: 'AI 側 CDP MCP',
      ),
      openHandLocalizedText(
        context,
        zh: '状态: ${runtimeStatus.rawStatus.isEmpty ? 'unknown' : runtimeStatus.rawStatus}',
        zhHant:
            '狀態: ${runtimeStatus.rawStatus.isEmpty ? 'unknown' : runtimeStatus.rawStatus}',
        en: 'Status: ${runtimeStatus.rawStatus.isEmpty ? 'unknown' : runtimeStatus.rawStatus}',
        fr: 'État : ${runtimeStatus.rawStatus.isEmpty ? 'unknown' : runtimeStatus.rawStatus}',
        de: 'Status: ${runtimeStatus.rawStatus.isEmpty ? 'unknown' : runtimeStatus.rawStatus}',
        ja: '状態: ${runtimeStatus.rawStatus.isEmpty ? 'unknown' : runtimeStatus.rawStatus}',
      ),
      openHandLocalizedText(
        context,
        zh: '可调用工具: ${runtimeStatus.toolCount}',
        zhHant: '可呼叫工具: ${runtimeStatus.toolCount}',
        en: 'Callable tools: ${runtimeStatus.toolCount}',
        fr: 'Outils appelables : ${runtimeStatus.toolCount}',
        de: 'Aufrufbare Tools: ${runtimeStatus.toolCount}',
        ja: '呼び出し可能ツール: ${runtimeStatus.toolCount}',
      ),
      if (runtimeStatus.port != null && runtimeStatus.port! > 0)
        openHandLocalizedText(
          context,
          zh: 'CDP 端口: ${runtimeStatus.port}',
          zhHant: 'CDP 連接埠: ${runtimeStatus.port}',
          en: 'CDP port: ${runtimeStatus.port}',
          fr: 'Port CDP : ${runtimeStatus.port}',
          de: 'CDP-Port: ${runtimeStatus.port}',
          ja: 'CDP ポート: ${runtimeStatus.port}',
        ),
      if (runtimeStatus.message.isNotEmpty) runtimeStatus.message,
      if (runtimeStatus.warningMessage.isNotEmpty)
        openHandLocalizedText(
          context,
          zh: '提示: ${runtimeStatus.warningMessage}',
          zhHant: '提示: ${runtimeStatus.warningMessage}',
          en: 'Warning: ${runtimeStatus.warningMessage}',
          fr: 'Avertissement : ${runtimeStatus.warningMessage}',
          de: 'Warnung: ${runtimeStatus.warningMessage}',
          ja: '警告: ${runtimeStatus.warningMessage}',
        ),
      if (runtimeStatus.errorMessage.isNotEmpty)
        openHandLocalizedText(
          context,
          zh: '错误: ${runtimeStatus.errorMessage}',
          zhHant: '錯誤: ${runtimeStatus.errorMessage}',
          en: 'Error: ${runtimeStatus.errorMessage}',
          fr: 'Erreur : ${runtimeStatus.errorMessage}',
          de: 'Fehler: ${runtimeStatus.errorMessage}',
          ja: 'エラー: ${runtimeStatus.errorMessage}',
        ),
    ];
    return _WebReverseDebugCdpStatus(
      tone: tone,
      label: label,
      tooltip: tooltipLines.join('\n'),
    );
  }
}

/// 顶栏「流式节流」状态指示胶囊。
///
/// 颜色一目了然：
///   * 绿色 = 字符/卡片限速都开着，输出会被均匀放出；
///   * 灰色 = 任一限速被关闭（值为 0），即将看到"全速"输出；
/// 点击打开对话框可调整本会话的字符/卡片速率；覆盖会随会话 metadata
/// 持久化，点"恢复"则清除覆盖并回到全局设置。
class _StreamThrottlePill extends StatelessWidget {
  const _StreamThrottlePill({required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context) {
    // 窄订阅代替整控制器 watch：流式期间控制器每次全量 notify（~14Hz）
    // 都会重建整个胶囊子树；胶囊真正依赖的只有下面三个易变量与覆盖信号。
    final (wasInitiallyThrottled, durationExpired, backlog) = context
        .select<AiSessionController, (bool, bool, int)>(
          (controller) => (
            controller.sessionWasInitiallyThrottled(sessionId),
            controller.sessionStreamThrottleDurationExpired(sessionId),
            controller.sessionStreamCardBacklog(sessionId),
          ),
        );
    final sessionController = context.read<AiSessionController>();
    final settingsController = context.watch<SettingsController>();
    // 监听会话覆盖变更信号，确保拨快慢即时反映在颜色与文案上。
    return ValueListenableBuilder<int>(
      valueListenable: sessionController.streamThrottleOverrideSignal,
      builder: (context, _, _) {
        final override = sessionController.sessionStreamThrottleOverride(
          sessionId,
        );
        final globalEnabled = settingsController.aiStreamThrottleEnabled;
        final effEnabled = override?.enabled ?? globalEnabled;
        final effChars =
            override?.charsPerSecond ??
            settingsController.effectiveStreamMaxCharsPerSecond();
        final effCards =
            override?.cardsPerSecond ??
            settingsController.effectiveStreamMaxMessageCardsPerSecond();
        // 胶囊可见性：
        //   * 任何时候只要本会话有运行时覆盖（rate/enabled）→ 显示；
        //   * 否则全局节流处于「开启 + 任一速率 > 0」时也显示；
        //   * 否则该会话从未进入节流态 → 不显示。
        //   * `sessionWasInitiallyThrottled` 兜底持久化关闭场景。
        final hasOverride = override != null;
        final globalActive = globalEnabled && (effChars > 0 || effCards > 0);
        if (!hasOverride && !wasInitiallyThrottled && !globalActive) {
          return const SizedBox.shrink();
        }
        // 关闭状态（全局或会话级覆盖关闭）以及任一速率为 0 都视作灰态。
        final disabled = !effEnabled || effChars <= 0 || effCards <= 0;
        // 节流时长已耗尽（select 订阅）：胶囊渲染为灰色并改文案，向用户
        // 暗示「剩余流式响应正以 AI 真实速率追加」。
        final showAsGray = disabled || durationExpired;
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final pillColor = showAsGray
            ? scheme.surfaceContainerHighest
            : scheme.tertiaryContainer.withValues(alpha: 0.78);
        final iconColor = showAsGray
            ? scheme.outline
            : scheme.onTertiaryContainer;
        final label = !effEnabled
            ? _homeSessionTooThrottleOffLabel(context)
            : disabled
            ? _homeSessionTooThrottleOffLabel(context)
            : durationExpired
            ? openHandLocalizedText(
                context,
                zh: '节流·已耗尽',
                zhHant: '節流·已耗盡',
                en: 'Throttle·expired',
                fr: 'Limite·expirée',
                de: 'Drossel·abgelaufen',
                ja: 'スロットル·期限切れ',
              )
            : openHandLocalizedText(
                context,
                zh: '字$effChars·卡$effCards',
                zhHant: '字$effChars·卡$effCards',
                en: 'Ch$effChars·Cd$effCards',
                fr: 'Car$effChars·Cart$effCards',
                de: 'Z$effChars·K$effCards',
                ja: '字$effChars·カード$effCards',
              );
        return MicroPressFeedback(
          child: Material(
            color: Colors.transparent,
            borderRadius: kOpenHandPillBorderRadius,
            child: InkWell(
              borderRadius: kOpenHandPillBorderRadius,
              onTap: () =>
                  _showStreamThrottleDialog(context, sessionId: sessionId),
              child: Container(
                height: _kSessionToolbarPillHeight,
                padding: const EdgeInsets.symmetric(
                  horizontal: _kSessionToolbarPillHorizontalPadding,
                ),
                decoration: BoxDecoration(
                  color: pillColor,
                  borderRadius: kOpenHandPillBorderRadius,
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
                      showAsGray ? Icons.flash_off_rounded : Icons.bolt_rounded,
                      size: _kSessionToolbarPillIconSize,
                      color: iconColor,
                    ),
                    kOpenHandHGap6,
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
                      kOpenHandHGap4,
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.tertiary.withValues(alpha: 0.16),
                          borderRadius: kOpenHandPillBorderRadius,
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
                      kOpenHandHGap4,
                      Icon(Icons.history_rounded, size: 13, color: iconColor),
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
}) async {
  await showAnimatedDialog<void>(
    context: context,
    builder: (_) => _StreamThrottleSessionDialog(sessionId: sessionId),
  );
}

class _StreamThrottleSessionDialog extends StatefulWidget {
  const _StreamThrottleSessionDialog({required this.sessionId});

  final String sessionId;

  @override
  State<_StreamThrottleSessionDialog> createState() =>
      _StreamThrottleSessionDialogState();
}

class _StreamThrottleSessionDialogState
    extends State<_StreamThrottleSessionDialog> {
  late final TextEditingController _charsCtrl;
  late final TextEditingController _cardsCtrl;
  // 弹窗内的「启用流式输出节流」开关。null = 沿用全局；
  // true/false = 会话级强制。Apply 时 setSessionStreamEnabledOverride
  // 立即生效；当前 Switch.value 用 effectiveEnabled 推断展示态。
  bool? _enabledOverride;

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
    _enabledOverride = override?.enabled;
  }

  @override
  void dispose() {
    _charsCtrl.dispose();
    _cardsCtrl.dispose();
    super.dispose();
  }

  int? _parse(String raw) {
    return optionalIntFromValue(raw);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsController>();
    // 只订阅本会话覆盖对象（按实例比较）：流式期间控制器全量 notify 高达
    // 每秒十余次，整控制器 watch 会让弹窗表单全程跟着重建。
    final session = context.read<AiSessionController>();
    final sessionOverride = context
        .select<AiSessionController, AiStreamThrottleOverride?>(
          (controller) =>
              controller.sessionStreamThrottleOverride(widget.sessionId),
        );
    final text = openHandTextResolver(context);

    final globalChars = settings.effectiveStreamMaxCharsPerSecond();
    final globalCards = settings.effectiveStreamMaxMessageCardsPerSecond();
    // 当前会话「真正生效」的速率：会话级覆盖 > 全局。
    // 弹窗的 "当前生效" 标签和 mini 仪表盘上限都按这个值显示，避免
    // 用户已在文本框里输入了新数字、但标签仍停留在全局值导致的
    // 「我设置了为什么没生效」错觉。
    final effectiveChars = sessionOverride?.charsPerSecond ?? globalChars;
    final effectiveCards = sessionOverride?.cardsPerSecond ?? globalCards;
    // 当前生效的启用态：会话级 > 全局。
    final globalEnabled = settings.aiStreamThrottleEnabled;
    final effectiveEnabled = _enabledOverride ?? globalEnabled;
    final globalStateLabel = globalEnabled
        ? text(
            zh: '已开启',
            zhHant: '已開啟',
            en: 'on',
            fr: 'activé',
            de: 'ein',
            ja: 'オン',
          )
        : text(
            zh: '已关闭',
            zhHant: '已關閉',
            en: 'off',
            fr: 'désactivé',
            de: 'aus',
            ja: 'オフ',
          );
    final forcedStateLabel = (_enabledOverride ?? false)
        ? text(
            zh: '开启',
            zhHant: '開啟',
            en: 'on',
            fr: 'activé',
            de: 'ein',
            ja: 'オン',
          )
        : text(
            zh: '关闭',
            zhHant: '關閉',
            en: 'off',
            fr: 'désactivé',
            de: 'aus',
            ja: 'オフ',
          );
    return buildOpenHandResponsiveDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthWide,
      maxHeight: kOpenHandDialogHeightTall,
      minAvailableWidth: 360,
      minAvailableHeight: 420,
      horizontalMargin: 48,
      verticalMargin: 48,
      safeAreaMinimum: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text(
                zh: '本会话流式节流',
                zhHant: '本會話串流節流',
                en: 'Session Throttle',
                fr: 'Limitation de session',
                de: 'Sitzungsdrosselung',
                ja: 'セッションスロットル',
              ),
              style: theme.textTheme.titleLarge,
            ),
            kOpenHandGap8,
            Text(
              text(
                zh: '调整后随会话持久保存，重启后仍保留。留空 = 沿用全局值。',
                zhHant: '調整後會隨會話持久保存，重啟後仍保留。留空 = 沿用全域值。',
                en: 'Saved with this session and restored after restart. Empty = use global.',
                fr: 'Enregistré avec cette session et restauré au redémarrage. Vide = valeur globale.',
                de: 'Wird mit dieser Sitzung gespeichert und nach Neustart wiederhergestellt. Leer = globaler Wert.',
                ja: 'このセッションに保存され、再起動後も復元されます。空欄 = グローバル値。',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            kOpenHandGap12,
            // 会话级启用开关：关闭后从现在起不再对 AI
            // 流式响应做任何节流；立即推送给活跃 throttle，正在输出
            // 的字符也会立刻全速放出。
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.55,
                ),
                borderRadius: kOpenHandBorderRadius10,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          text(
                            zh: '启用流式输出节流（本会话）',
                            zhHant: '啟用串流輸出節流（本會話）',
                            en: 'Enable stream throttle (this session)',
                            fr: 'Activer la limitation du flux (cette session)',
                            de: 'Stream-Drosselung aktivieren (diese Sitzung)',
                            ja: 'ストリーム出力スロットルを有効化（このセッション）',
                          ),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        kOpenHandGap2,
                        Text(
                          _enabledOverride == null
                              ? text(
                                  zh: '当前沿用全局：$globalStateLabel',
                                  zhHant: '目前沿用全域：$globalStateLabel',
                                  en: 'Following global: $globalStateLabel',
                                  fr: 'Suit le global : $globalStateLabel',
                                  de: 'Folgt global: $globalStateLabel',
                                  ja: 'グローバルに従う: $globalStateLabel',
                                )
                              : text(
                                  zh: '已会话级强制$forcedStateLabel',
                                  zhHant: '已於會話級強制$forcedStateLabel',
                                  en: 'Session-level forced $forcedStateLabel',
                                  fr: 'Forcé au niveau session : $forcedStateLabel',
                                  de: 'Auf Sitzungsebene erzwungen: $forcedStateLabel',
                                  ja: 'セッション単位で $forcedStateLabel に固定',
                                ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    // Material 3 Expressive 风格：原 Switch.adaptive
                    // 在 macOS/iOS 走 Cupertino 渲染（与 M3 设计语言不一致），
                    // 显式 Switch 强制走 M3 thumb/track。
                    value: effectiveEnabled,
                    thumbIcon: WidgetStateProperty.resolveWith<Icon?>((states) {
                      if (states.contains(WidgetState.selected)) {
                        return const Icon(Icons.check_rounded, size: 16);
                      }
                      return const Icon(Icons.close_rounded, size: 16);
                    }),
                    onChanged: (v) {
                      // 立即应用：会话级覆盖 + 推到活跃 throttle。
                      setState(() => _enabledOverride = v);
                      session.setSessionStreamEnabledOverride(
                        widget.sessionId,
                        v,
                      );
                    },
                  ),
                ],
              ),
            ),
            kOpenHandGap12,
            // 实时字符吞吐仪表盘：长窗口按秒采样，绘制前
            // 降采样；主曲线使用节流后的展示吞吐。
            _StreamThroughputMiniGauge(
              sessionId: widget.sessionId,
              maxRate: effectiveChars <= 0 ? 1 : effectiveChars,
            ),
            kOpenHandGap16,
            TextField(
              controller: _charsCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: InputDecoration(
                labelText: text(
                  zh: '字符 / 秒（当前生效：$effectiveChars）',
                  zhHant: '字元 / 秒（目前生效：$effectiveChars）',
                  en: 'Chars / Sec (current: $effectiveChars)',
                  fr: 'Caractères / s (actuel : $effectiveChars)',
                  de: 'Zeichen / Sek. (aktuell: $effectiveChars)',
                  ja: '文字 / 秒（現在: $effectiveChars）',
                ),
                hintText:
                    '${AppSettingsSnapshot.defaultAiStreamMaxCharsPerSecond}',
              ),
              // 不再在输入时实时推送覆盖；仅在点击”应用”后
              // 才正式生效。输入过程中仅刷新 UI 标签展示。
              onChanged: (_) {
                if (mounted) setState(() {});
              },
            ),
            kOpenHandGap12,
            TextField(
              controller: _cardsCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: InputDecoration(
                labelText: text(
                  zh: '卡片 / 秒（当前生效：$effectiveCards）',
                  zhHant: '卡片 / 秒（目前生效：$effectiveCards）',
                  en: 'Cards / Sec (current: $effectiveCards)',
                  fr: 'Cartes / s (actuel : $effectiveCards)',
                  de: 'Karten / Sek. (aktuell: $effectiveCards)',
                  ja: 'カード / 秒（現在: $effectiveCards）',
                ),
                hintText:
                    '${AppSettingsSnapshot.defaultAiStreamMaxMessageCardsPerSecond}',
              ),
              onChanged: (_) {
                if (mounted) setState(() {});
              },
            ),
            kOpenHandGap20,
            // 三枚操作按钮明确居中聚集：丢到 SizedBox(double.infinity)
            // 里以推翻外层 Column.crossAxisAlignment.start 带来的隱性左贴边；
            // Wrap 仍用来兼顾窄幅对话框的软换行。
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  OpenHandDialogActionButton.secondary(
                    onPressed: () {
                      session.clearSessionStreamThrottleOverride(
                        widget.sessionId,
                      );
                      Navigator.of(context).pop();
                    },
                    label: text(
                      zh: '恢复默认',
                      zhHant: '恢復預設',
                      en: 'Reset',
                      fr: 'Réinitialiser',
                      de: 'Zurücksetzen',
                      ja: '既定に戻す',
                    ),
                  ),
                  OpenHandDialogActionButton.secondary(
                    onPressed: () => Navigator.of(context).pop(),
                    label: openHandCancelLabel(context),
                  ),
                  OpenHandDialogActionButton.primary(
                    onPressed: () {
                      session.setSessionStreamCharsOverride(
                        widget.sessionId,
                        _parse(_charsCtrl.text),
                      );
                      session.setSessionStreamCardsOverride(
                        widget.sessionId,
                        _parse(_cardsCtrl.text),
                      );
                      // Switch 已即时下发；Apply 再确认一次最终状态。
                      session.setSessionStreamEnabledOverride(
                        widget.sessionId,
                        _enabledOverride,
                      );
                      Navigator.of(context).pop();
                    },
                    label: text(
                      zh: '应用',
                      zhHant: '套用',
                      en: 'Apply',
                      fr: 'Appliquer',
                      de: 'Anwenden',
                      ja: '適用',
                    ),
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

/// 节流仪表盘：展示侧字符吞吐曲线图。
///
/// 主曲线使用节流器真正放给 UI 的 grapheme 数，原始模型流入只作为辅助
/// 统计展示。这样阈值 30/s 时，模型瞬时回吐 300+/s 不会被误读成节流
/// 失效；长窗口按秒保留 1h，绘制前降采样到固定点数，避免大窗口卡顿。
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

class _StreamThroughputMiniGaugeState extends State<_StreamThroughputMiniGauge>
    with SingleTickerProviderStateMixin {
  Timer? _ticker;
  List<int> _displaySamples = const <int>[];
  List<int> _rawSamples = const <int>[];
  _ThroughputChartData _chartData = const _ThroughputChartData(
    samples: <int>[],
    bucketSeconds: 1,
  );
  // 平滑过渡：高频拉取新 snapshot，painter 读取的
  // 是 `_displaySamples`，由 AnimationController 把 `_fromSamples →
  // _toSamples` 跨 200ms 用 easeOutCubic 插值，曲线随展示吞吐 Q 弹
  // 流畅滑动而不再跳变。
  List<double> _fromSamples = const <double>[];
  List<double> _toSamples = const <double>[];
  late final AnimationController _morph;
  // 鼠标悬停 / 触屏长按时高亮的桶索引；null = 不高亮。
  int? _hoveredIndex;
  Offset? _hoverLocal;
  bool _hoverScheduled = false;
  bool _windowScheduled = false;
  double _pendingZoom = 1.0;
  int _rangeSeconds = 5 * 60;
  int _bucketSeconds = 1;
  double _zoom = 1.0;
  double _zoomBase = 1.0;
  static const double _kMinZoom = 1.0;
  static const int _kMinWindowSeconds = 30;
  static const int _kMaxPaintSamples = 420;
  static const Duration _kRefreshInterval = Duration(milliseconds: 200);
  static const List<int> _kRangeOptions = <int>[
    5 * 60,
    10 * 60,
    30 * 60,
    60 * 60,
  ];
  static const List<int> _kGranularityOptions = <int>[
    1,
    2,
    5,
    10,
    15,
    30,
    60,
    120,
    300,
  ];

  @override
  void initState() {
    super.initState();
    _morph = AnimationController(vsync: this, duration: _kRefreshInterval)
      ..addListener(_handleMorphTick);
    // 直接 seed 第一帧 snapshot：initState 内禁止调用
    // 共享动效偏好读取依赖 MediaQuery（它会触发
    // dependOnInheritedWidgetOfExactType<MediaQuery>() 断言），所以
    // 首次同步走 _morph.value=1.0 的"无动画跳变"路径；后续 Timer 触发的
    // _refresh 已在 build 帧之后，可安全读取共享动效偏好。
    final controller = context.read<AiSessionController>();
    final snapshot = controller.sessionStreamThroughputSnapshot(
      widget.sessionId,
      windowSeconds: _rangeSeconds,
    );
    _displaySamples = snapshot.displaySamples;
    _rawSamples = snapshot.rawSamples;
    _chartData = _buildChartData(_displaySamples);
    _toSamples = <double>[for (final v in _chartData.samples) v.toDouble()];
    _fromSamples = List<double>.from(_toSamples);
    _morph.value = 1.0;
    _ticker = startSafePeriodicTimer(_kRefreshInterval, (_) {
      if (mounted) _refresh();
    }, min: _kRefreshInterval);
  }

  void _handleMorphTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _morph
      ..removeListener(_handleMorphTick)
      ..dispose();
    super.dispose();
  }

  void _refresh() {
    final controller = context.read<AiSessionController>();
    final next = controller.sessionStreamThroughputSnapshot(
      widget.sessionId,
      windowSeconds: _rangeSeconds,
    );
    if (listEquals(next.displaySamples, _displaySamples) &&
        listEquals(next.rawSamples, _rawSamples)) {
      return;
    }
    // 把上一帧已渲染的插值结果作为起点，向新 snapshot 平滑过渡。
    final reduceMotion = !openHandTickerMotionEnabled(context);
    final prevDisplay = _currentDisplaySamples();
    final chartData = _buildChartData(next.displaySamples);
    final target = <double>[for (final v in chartData.samples) v.toDouble()];
    setState(() {
      _displaySamples = next.displaySamples;
      _rawSamples = next.rawSamples;
      _chartData = chartData;
      _toSamples = target;
      _fromSamples = _alignLength(prevDisplay, target.length);
    });
    if (reduceMotion) {
      _morph.value = 1.0;
    } else {
      _morph
        ..stop()
        ..value = 0.0
        ..forward();
    }
  }

  void _updateWindow({
    int? rangeSeconds,
    double? zoom,
    int? bucketSeconds,
    bool animate = true,
  }) {
    final nextRange = rangeSeconds ?? _rangeSeconds;
    final maxZoom = _maxZoomForRange(nextRange);
    final nextZoom = (zoom ?? _zoom).clamp(_kMinZoom, maxZoom).toDouble();
    final nextWindow = _visibleWindowSeconds(
      rangeSeconds: nextRange,
      zoom: nextZoom,
    );
    final nextBucket = _normalizedBucketSeconds(
      bucketSeconds ?? _bucketSeconds,
      nextWindow,
    );
    if (nextRange == _rangeSeconds &&
        (nextZoom - _zoom).abs() <= 0.001 &&
        nextBucket == _bucketSeconds) {
      return;
    }
    final reduceMotion = !openHandTickerMotionEnabled(context);
    final prevDisplay = _currentDisplaySamples();
    var sourceDisplay = _displaySamples;
    var sourceRaw = _rawSamples;
    if (nextRange > sourceDisplay.length || nextRange != _rangeSeconds) {
      final snapshot = context
          .read<AiSessionController>()
          .sessionStreamThroughputSnapshot(
            widget.sessionId,
            windowSeconds: nextRange,
          );
      sourceDisplay = snapshot.displaySamples;
      sourceRaw = snapshot.rawSamples;
    }
    final chartData = _buildChartData(
      sourceDisplay,
      rangeSeconds: nextRange,
      zoom: nextZoom,
      bucketSeconds: nextBucket,
    );
    final target = <double>[for (final v in chartData.samples) v.toDouble()];
    setState(() {
      _rangeSeconds = nextRange;
      _zoom = nextZoom;
      _zoomBase = nextZoom;
      _bucketSeconds = nextBucket;
      _displaySamples = sourceDisplay;
      _rawSamples = sourceRaw;
      _hoveredIndex = null;
      _hoverLocal = null;
      _chartData = chartData;
      _toSamples = target;
      _fromSamples = _alignLength(prevDisplay, target.length);
    });
    if (!animate || reduceMotion) {
      _morph.value = 1.0;
    } else {
      _morph
        ..stop()
        ..value = 0.0
        ..forward();
    }
  }

  double _maxZoomForRange(int rangeSeconds) =>
      math.max(_kMinZoom, rangeSeconds / _kMinWindowSeconds);

  int _visibleWindowSeconds({int? rangeSeconds, double? zoom}) {
    final range = rangeSeconds ?? _rangeSeconds;
    final z = (zoom ?? _zoom)
        .clamp(_kMinZoom, _maxZoomForRange(range))
        .toDouble();
    return (range / z).round().clamp(_kMinWindowSeconds, range).toInt();
  }

  List<int> _granularityOptionsForWindow(int windowSeconds) {
    final maxBucket = math.max(1, windowSeconds ~/ 2);
    final options = <int>[
      for (final seconds in _kGranularityOptions)
        if (seconds <= maxBucket) seconds,
    ];
    return options.isEmpty ? const <int>[1] : List<int>.unmodifiable(options);
  }

  int _normalizedBucketSeconds(int seconds, int windowSeconds) {
    final options = _granularityOptionsForWindow(windowSeconds);
    var selected = options.first;
    for (final option in options) {
      if (option > seconds) {
        break;
      }
      selected = option;
    }
    return selected;
  }

  _ThroughputChartData _buildChartData(
    List<int> source, {
    int? rangeSeconds,
    double? zoom,
    int? bucketSeconds,
  }) {
    final window = _visibleWindowSeconds(
      rangeSeconds: rangeSeconds,
      zoom: zoom,
    );
    final visible = source
        .take(math.min(window, source.length))
        .toList(growable: false);
    final requestedBucket = _normalizedBucketSeconds(
      bucketSeconds ?? _bucketSeconds,
      window,
    );
    final autoBucket = visible.length <= _kMaxPaintSamples
        ? 1
        : (visible.length / _kMaxPaintSamples).ceil();
    final effectiveBucket = math.max(requestedBucket, autoBucket);
    if (effectiveBucket <= 1) {
      return _ThroughputChartData(samples: visible, bucketSeconds: 1);
    }
    final downsampled = <int>[];
    for (var i = 0; i < visible.length; i += effectiveBucket) {
      var bucketPeak = 0;
      final end = math.min(i + effectiveBucket, visible.length);
      for (var j = i; j < end; j++) {
        if (visible[j] > bucketPeak) bucketPeak = visible[j];
      }
      downsampled.add(bucketPeak);
    }
    return _ThroughputChartData(
      samples: List<int>.unmodifiable(downsampled),
      bucketSeconds: effectiveBucket,
    );
  }

  String _formatRangeLabel(BuildContext context, int seconds) {
    if (seconds < 60) {
      return openHandLocalizedText(
        context,
        zh: '$seconds秒',
        zhHant: '$seconds秒',
        en: '${seconds}s',
        fr: '$seconds s',
        de: '$seconds s',
        ja: '$seconds秒',
      );
    }
    final minutes = seconds ~/ 60;
    if (seconds % 60 != 0 && seconds < 60 * 60) {
      final value = (seconds / 60).toStringAsFixed(1);
      return openHandLocalizedText(
        context,
        zh: '$value分',
        zhHant: '$value分',
        en: '${value}m',
        fr: '$value min',
        de: '$value Min.',
        ja: '$value分',
      );
    }
    if (minutes < 60) {
      return openHandLocalizedText(
        context,
        zh: '$minutes分',
        zhHant: '$minutes分',
        en: '${minutes}m',
        fr: '$minutes min',
        de: '$minutes Min.',
        ja: '$minutes分',
      );
    }
    final hours = minutes ~/ 60;
    return openHandLocalizedText(
      context,
      zh: '$hours小时',
      zhHant: '$hours小時',
      en: '${hours}h',
      fr: '$hours h',
      de: '$hours Std.',
      ja: '$hours時間',
    );
  }

  String _formatGranularityLabel(BuildContext context, int seconds) {
    final unit = _formatRangeLabel(context, seconds);
    return openHandLocalizedText(
      context,
      zh: '$unit/点',
      zhHant: '$unit/點',
      en: '$unit/pt',
      fr: '$unit/pt',
      de: '$unit/Pkt.',
      ja: '$unit/点',
    );
  }

  int _peak(List<int> values) {
    var peak = 0;
    for (final value in values) {
      if (value > peak) peak = value;
    }
    return peak;
  }

  int _average(List<int> values) {
    if (values.isEmpty) return 0;
    var sum = 0;
    for (final value in values) {
      sum += value;
    }
    return (sum / values.length).round();
  }

  List<double> _currentDisplaySamples() {
    if (_toSamples.isEmpty) return const <double>[];
    if (_fromSamples.isEmpty) return List<double>.from(_toSamples);
    final t = kOpenHandSwitchInCurve.transform(_morph.value.clamp(0.0, 1.0));
    final n = _toSamples.length;
    final from = _alignLength(_fromSamples, n);
    return <double>[
      for (var i = 0; i < n; i++) from[i] + (_toSamples[i] - from[i]) * t,
    ];
  }

  List<double> _alignLength(List<double> source, int targetLen) {
    if (source.length == targetLen) return source;
    if (source.length > targetLen) {
      return source.sublist(0, targetLen);
    }
    return <double>[
      ...source,
      for (var i = 0; i < targetLen - source.length; i++) 0.0,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final windowSeconds = _visibleWindowSeconds();
    final displayWindow = _displaySamples
        .take(math.min(windowSeconds, _displaySamples.length))
        .toList(growable: false);
    final rawWindow = _rawSamples
        .take(math.min(windowSeconds, _rawSamples.length))
        .toList(growable: false);
    final samples = _chartData.samples;
    final displaySamples = _currentDisplaySamples();
    final visibleDisplay = displaySamples.isEmpty
        ? const <double>[]
        : displaySamples;
    final peak = _peak(displayWindow);
    final current = displayWindow.isEmpty ? 0 : displayWindow.first;
    final average = _average(displayWindow);
    final rawPeak = _peak(rawWindow);
    final rawCurrent = rawWindow.isEmpty ? 0 : rawWindow.first;
    final cap = math.max(widget.maxRate, peak == 0 ? 1 : peak);
    final headerWindow = _formatRangeLabel(context, windowSeconds);
    final maxZoom = _maxZoomForRange(_rangeSeconds);
    final zoomValue = _zoom.clamp(_kMinZoom, maxZoom).toDouble();
    final granularityOptions = _granularityOptionsForWindow(windowSeconds);
    final effectiveGranularity = _normalizedBucketSeconds(
      _bucketSeconds,
      windowSeconds,
    );
    final granularityIndex = math.max(
      0,
      granularityOptions.indexOf(effectiveGranularity),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: kOpenHandBorderRadius14,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.show_chart_rounded, size: 14, color: scheme.primary),
              kOpenHandHGap6,
              Expanded(
                child: Text(
                  openHandLocalizedText(
                    context,
                    zh: '节流后字符吞吐 · $headerWindow',
                    zhHant: '節流後字元吞吐 · $headerWindow',
                    en: 'Throttled Chars · $headerWindow',
                    fr: 'Caractères limités · $headerWindow',
                    de: 'Gedrosselte Zeichen · $headerWindow',
                    ja: 'スロットル後の文字 · $headerWindow',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              kOpenHandHGap6,
              Tooltip(
                message: openHandLocalizedText(
                  context,
                  zh: '触控板双指捏合或 Ctrl+滚轮放缩时间区间',
                  zhHant: '觸控板雙指捏合或 Ctrl+滾輪縮放時間區間',
                  en: 'Pinch or Ctrl+wheel to zoom the time range',
                  fr: 'Pincez ou utilisez Ctrl+molette pour zoomer la période',
                  de: 'Zum Zoomen des Zeitbereichs kneifen oder Strg+Mausrad nutzen',
                  ja: 'ピンチまたは Ctrl+ホイールで時間範囲をズーム',
                ),
                child: Icon(
                  Icons.pinch_rounded,
                  size: 12,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
              kOpenHandHGap8,
              Flexible(
                child: Text(
                  openHandLocalizedText(
                    context,
                    zh: '当前 $current/s · 峰 $peak/s · 均 $average/s · 上限 ${widget.maxRate}/s',
                    zhHant:
                        '目前 $current/s · 峰 $peak/s · 均 $average/s · 上限 ${widget.maxRate}/s',
                    en: 'now $current/s · peak $peak/s · avg $average/s · cap ${widget.maxRate}/s',
                    fr: 'actuel $current/s · pic $peak/s · moy $average/s · limite ${widget.maxRate}/s',
                    de: 'jetzt $current/s · Spitze $peak/s · Ø $average/s · Limit ${widget.maxRate}/s',
                    ja: '現在 $current/s · 最大 $peak/s · 平均 $average/s · 上限 ${widget.maxRate}/s',
                  ),
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          kOpenHandGap8,
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: <ButtonSegment<int>>[
                for (final seconds in _kRangeOptions)
                  ButtonSegment<int>(
                    value: seconds,
                    label: Text(_formatRangeLabel(context, seconds)),
                  ),
              ],
              selected: <int>{_rangeSeconds},
              onSelectionChanged: (selection) {
                final next = selection.isEmpty ? null : selection.first;
                if (next != null) {
                  _updateWindow(rangeSeconds: next, zoom: 1.0);
                }
              },
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                textStyle: WidgetStatePropertyAll<TextStyle?>(
                  theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          kOpenHandGap6,
          Row(
            children: [
              Icon(
                Icons.zoom_in_map_rounded,
                size: 14,
                color: scheme.onSurfaceVariant,
              ),
              Expanded(
                child: Slider(
                  min: _kMinZoom,
                  max: maxZoom,
                  value: zoomValue,
                  label: headerWindow,
                  onChanged: (value) =>
                      _updateWindow(zoom: value, animate: false),
                ),
              ),
              SizedBox(
                width: 52,
                child: Text(
                  headerWindow,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          kOpenHandGap4,
          Row(
            children: [
              Icon(
                Icons.tune_rounded,
                size: 14,
                color: scheme.onSurfaceVariant,
              ),
              Expanded(
                child: Slider(
                  max: (granularityOptions.length - 1).toDouble(),
                  divisions: math.max(1, granularityOptions.length - 1),
                  value: granularityIndex.toDouble(),
                  label: _formatGranularityLabel(context, effectiveGranularity),
                  onChanged: (value) {
                    final index = value
                        .round()
                        .clamp(0, granularityOptions.length - 1)
                        .toInt();
                    _updateWindow(
                      bucketSeconds: granularityOptions[index],
                      animate: false,
                    );
                  },
                ),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  _formatGranularityLabel(context, effectiveGranularity),
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          kOpenHandGap8,
          SizedBox(
            height: 96,
            // 鼠标悬停 / 触屏拖动时高亮当前桶并展示
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
                  if (n <= 1) return 0;
                  // 曲线模式：将 X 均匀分桶（n 段，n+1 个 anchor）。
                  final slotW = width / n;
                  final visualSlot = (local.dx / slotW).floor().clamp(0, n - 1);
                  // 视觉上 X=0 = 最老（samples[n-1]），X=width = 当前（samples[0]）
                  return n - 1 - visualSlot;
                }

                return Listener(
                  onPointerPanZoomStart: (_) {
                    _zoomBase = _zoom;
                  },
                  onPointerPanZoomUpdate: (event) {
                    if (_displaySamples.isEmpty) return;
                    _pendingZoom = (_zoomBase * event.scale)
                        .clamp(_kMinZoom, _maxZoomForRange(_rangeSeconds))
                        .toDouble();
                    if (!_windowScheduled) {
                      _windowScheduled = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _windowScheduled = false;
                        if (mounted) {
                          _updateWindow(zoom: _pendingZoom, animate: false);
                        }
                      });
                    }
                  },
                  onPointerPanZoomEnd: (_) {
                    _zoomBase = _zoom;
                  },
                  onPointerSignal: (signal) {
                    if (signal is PointerScrollEvent &&
                        HardwareKeyboard.instance.isControlPressed) {
                      final delta = -signal.scrollDelta.dy / 200.0;
                      _pendingZoom = (_zoom * (1.0 + delta))
                          .clamp(_kMinZoom, _maxZoomForRange(_rangeSeconds))
                          .toDouble();
                      if (!_windowScheduled) {
                        _windowScheduled = true;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _windowScheduled = false;
                          if (mounted) {
                            _updateWindow(zoom: _pendingZoom, animate: false);
                          }
                        });
                      }
                    }
                  },
                  child: MouseRegion(
                    onHover: (event) {
                      final i = indexAt(event.localPosition);
                      if (i != _hoveredIndex ||
                          event.localPosition != _hoverLocal) {
                        _hoveredIndex = i;
                        _hoverLocal = event.localPosition;
                        if (!_hoverScheduled) {
                          _hoverScheduled = true;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _hoverScheduled = false;
                            if (mounted) setState(() {});
                          });
                        }
                      }
                    },
                    onExit: (_) {
                      if (_hoveredIndex != null) {
                        _hoveredIndex = null;
                        _hoverLocal = null;
                        if (!_hoverScheduled) {
                          _hoverScheduled = true;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _hoverScheduled = false;
                            if (mounted) setState(() {});
                          });
                        }
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
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _ThroughputBarsPainter(
                                samples: visibleDisplay,
                                cap: cap,
                                color: scheme.primary,
                                gridColor: scheme.outlineVariant.withValues(
                                  alpha: 0.6,
                                ),
                                limitColor: scheme.tertiary.withValues(
                                  alpha: 0.45,
                                ),
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
                              cap: cap,
                              bucketSeconds: _chartData.bucketSeconds,
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          kOpenHandGap8,
          Text(
            openHandLocalizedText(
              context,
              zh: '模型原始流入 当前 $rawCurrent/s · 峰 $rawPeak/s',
              zhHant: '模型原始流入 目前 $rawCurrent/s · 峰 $rawPeak/s',
              en: 'Raw ingress now $rawCurrent/s · peak $rawPeak/s',
              fr: 'Entrée brute actuelle $rawCurrent/s · pic $rawPeak/s',
              de: 'Roheingang jetzt $rawCurrent/s · Spitze $rawPeak/s',
              ja: 'モデル原始流入 現在 $rawCurrent/s · 最大 $rawPeak/s',
            ),
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThroughputChartData {
  const _ThroughputChartData({
    required this.samples,
    required this.bucketSeconds,
  });

  final List<int> samples;
  final int bucketSeconds;
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

  final List<double> samples;
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
    // 柱状渲染已升级为平滑曲线 + 渐变填充：bucket 0 = 当前秒（最右），
    // bucket N-1 = 最老（最左）。Catmull-Rom → 三次贝塞尔，端点
    // strokeCap.round 让曲线两端柔和；填充区域顶到曲线下方，alpha
    // 渐弱到 0.04 形成「面积图」视觉，符合用户对吞吐曲线的预期。
    final n = samples.length;
    final stepX = n <= 1 ? size.width : size.width / (n - 1);
    final points = <Offset>[
      for (var i = 0; i < n; i++)
        Offset(
          (n - 1 - i) * stepX,
          size.height - (samples[i].clamp(0, cap) / cap) * size.height,
        ),
    ]..sort((a, b) => a.dx.compareTo(b.dx));
    if (points.length == 1) {
      final p = points.first;
      final dot = Paint()..color = color;
      canvas.drawCircle(Offset(size.width / 2, p.dy), 2.4, dot);
      return;
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = i == 0 ? points[i] : points[i - 1];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = (i + 2 < points.length) ? points[i + 2] : points[i + 1];
      // Catmull-Rom 张力 1/6
      final c1 = Offset(
        p1.dx + (p2.dx - p0.dx) / 6.0,
        p1.dy + (p2.dy - p0.dy) / 6.0,
      );
      final c2 = Offset(
        p2.dx - (p3.dx - p1.dx) / 6.0,
        p2.dy - (p3.dy - p1.dy) / 6.0,
      );
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    // 渐变面积填充
    final fillPath = Path.from(path)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          color.withValues(alpha: 0.38),
          color.withValues(alpha: 0.04),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fillPath, fillPaint);
    // 主曲线描边
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = color
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawPath(path, strokePaint);
    // 超阈值的点：红色小圆点
    if (hasLimit) {
      final dotPaint = Paint()..color = overLimitColor;
      for (var i = 0; i < n; i++) {
        if (samples[i] > limitValue) {
          final p = Offset(
            (n - 1 - i) * stepX,
            size.height - (samples[i].clamp(0, cap) / cap) * size.height,
          );
          canvas.drawCircle(p, 2.0, dotPaint);
        }
      }
    }
    // 当前秒突出标记：右端实心圆
    final lastPoint = Offset(
      (n - 1) * stepX,
      size.height - (samples[0].clamp(0, cap) / cap) * size.height,
    );
    final currentDot = Paint()..color = color;
    canvas.drawCircle(lastPoint, 2.8, currentDot);
    canvas.drawCircle(
      lastPoint,
      4.6,
      Paint()
        ..color = color.withValues(alpha: 0.22)
        ..style = PaintingStyle.fill,
    );
    // 悬停指示：垂直虚线 + dot
    if (hoveredIndex != null &&
        hoveredIndex! >= 0 &&
        hoveredIndex! < n &&
        hoverHighlightColor != null) {
      final hoverX = (n - 1 - hoveredIndex!) * stepX;
      final hoverY =
          size.height -
          (samples[hoveredIndex!].clamp(0, cap) / cap) * size.height;
      final dashPaint = Paint()
        ..color = hoverHighlightColor!.withValues(alpha: 0.4)
        ..strokeWidth = 1.0;
      var y = 0.0;
      while (y < size.height) {
        canvas.drawLine(
          Offset(hoverX, y),
          Offset(hoverX, math.min(y + 3, size.height)),
          dashPaint,
        );
        y += 6;
      }
      canvas.drawCircle(
        Offset(hoverX, hoverY),
        3.4,
        Paint()..color = hoverHighlightColor!,
      );
      canvas.drawCircle(Offset(hoverX, hoverY), 2.0, Paint()..color = color);
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

/// 仪表盘 hover tooltip 气泡：始终约束在图表内部，避免边缘点、高点
/// 或对话框窄屏时被 Stack / Dialog 裁切到看不见。
class _ThroughputTooltip extends StatelessWidget {
  const _ThroughputTooltip({
    required this.samples,
    required this.hoveredIndex,
    required this.anchor,
    required this.limitValue,
    required this.cap,
    required this.bucketSeconds,
  });

  final List<int> samples;
  final int hoveredIndex;
  final Offset anchor;
  final int limitValue;
  final int cap;
  final int bucketSeconds;

  @override
  Widget build(BuildContext context) {
    if (hoveredIndex < 0 || hoveredIndex >= samples.length) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final value = samples[hoveredIndex];
    final agoStart = hoveredIndex * bucketSeconds;
    final agoEnd = agoStart + bucketSeconds - 1;
    final overLimit = limitValue > 0 && value > limitValue;
    final color = overLimit ? scheme.error : scheme.primary;
    final bg = overLimit ? scheme.errorContainer : scheme.primaryContainer;
    final fg = overLimit ? scheme.onErrorContainer : scheme.onPrimaryContainer;
    final timeLabel = agoStart == 0 && bucketSeconds == 1
        ? openHandLocalizedText(
            context,
            zh: '当前秒',
            zhHant: '目前秒',
            en: 'now',
            fr: 'maintenant',
            de: 'jetzt',
            ja: '現在',
          )
        : bucketSeconds <= 1
        ? openHandLocalizedText(
            context,
            zh: '${agoStart}s 前',
            zhHant: '${agoStart}s 前',
            en: '${agoStart}s ago',
            fr: 'il y a ${agoStart}s',
            de: 'vor ${agoStart}s',
            ja: '$agoStart秒前',
          )
        : openHandLocalizedText(
            context,
            zh: '$agoStart-${agoEnd}s 前',
            zhHant: '$agoStart-${agoEnd}s 前',
            en: '$agoStart-${agoEnd}s ago',
            fr: 'il y a $agoStart-${agoEnd}s',
            de: 'vor $agoStart-${agoEnd}s',
            ja: '$agoStart-$agoEnd秒前',
          );
    final valueLabel = bucketSeconds <= 1
        ? '$value/s'
        : openHandLocalizedText(
            context,
            zh: '峰 $value/s',
            zhHant: '峰 $value/s',
            en: 'peak $value/s',
            fr: 'pic $value/s',
            de: 'Spitze $value/s',
            ja: '最大 $value/s',
          );
    return Positioned.fill(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            const margin = 4.0;
            const bubbleHeight = 28.0;
            final chartWidth = constraints.maxWidth;
            final chartHeight = constraints.maxHeight;
            final bubbleWidth = math.min(
              158.0,
              math.max(104.0, chartWidth - margin * 2),
            );
            final maxLeft = math.max(margin, chartWidth - bubbleWidth - margin);
            final left = (anchor.dx - bubbleWidth / 2)
                .clamp(margin, maxLeft)
                .toDouble();
            final chartCap = math.max(1, cap);
            final pointY =
                chartHeight -
                (value.clamp(0, chartCap) / chartCap) * chartHeight;
            final maxTop = math.max(
              margin,
              chartHeight - bubbleHeight - margin,
            );
            final aboveTop = pointY - bubbleHeight - 8;
            final belowTop = pointY + 8;
            final top = (aboveTop >= margin ? aboveTop : belowTop)
                .clamp(margin, maxTop)
                .toDouble();
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: left,
                  top: top,
                  width: bubbleWidth,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: bg.withValues(alpha: 0.96),
                        borderRadius: kOpenHandBorderRadius8,
                        border: Border.all(
                          color: color.withValues(alpha: 0.46),
                        ),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: scheme.shadow.withValues(alpha: 0.16),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            overLimit
                                ? Icons.priority_high_rounded
                                : Icons.bolt_rounded,
                            size: 12,
                            color: color,
                          ),
                          kOpenHandHGap4,
                          Flexible(
                            child: Text(
                              '$timeLabel · $valueLabel',
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: fg,
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Android Reverse Debug Pill ────────────────────────────────────────────────

class _AndroidReverseDebugPill extends StatefulWidget {
  const _AndroidReverseDebugPill({required this.session});

  final AiSession session;

  @override
  State<_AndroidReverseDebugPill> createState() =>
      _AndroidReverseDebugPillState();
}

class _AndroidReverseDebugPillState extends State<_AndroidReverseDebugPill> {
  AndroidReverseSessionController? _controller;

  void _attachIfNeeded() {
    final state = context.findAncestorStateOfType<_OpenHandHomePageState>();
    final ctrl = state?.androidReverseControllerFor(widget.session.id);
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
    await state.openAndroidReverseDashboardFor(context, widget.session);
    if (!mounted) return;
    _attachIfNeeded();
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final reduceMotion = !openHandTickerMotionEnabled(context);
    final text = openHandTextResolver(context);

    final running = ctrl?.isRunning ?? false;
    final deviceOnline = ctrl?.connectedDevice != null;
    final processCount = ctrl?.processes.length ?? 0;
    final processLabel = text(
      zh: '$processCount 进程',
      zhHant: '$processCount 進程',
      en: '$processCount proc',
      fr: '$processCount proc.',
      de: '$processCount Proz.',
      ja: '$processCount プロセス',
    );
    final dotColor = !running
        ? cs.outline
        : !deviceOnline
        ? cs.error
        : cs.primary;
    final deviceLabel =
        ctrl?.connectedDevice?.model ??
        ctrl?.connectedDevice?.serial ??
        (running
            ? text(
                zh: '无设备',
                zhHant: '無設備',
                en: 'no device',
                fr: 'aucun appareil',
                de: 'kein Gerät',
                ja: 'デバイスなし',
              )
            : text(
                zh: '点击连接',
                zhHant: '點擊連線',
                en: 'click',
                fr: 'cliquer',
                de: 'klicken',
                ja: 'クリック',
              ));
    final label = running
        ? '${deviceOnline ? deviceLabel : text(zh: '无设备', zhHant: '無設備', en: 'no device', fr: 'aucun appareil', de: 'kein Gerät', ja: 'デバイスなし')} · $processLabel'
        : text(
            zh: '点击打开',
            zhHant: '點擊開啟',
            en: 'open',
            fr: 'ouvrir',
            de: 'öffnen',
            ja: '開く',
          );
    final tooltip = <String>[
      text(
        zh: 'Android 逆向调试面板',
        zhHant: 'Android 逆向除錯面板',
        en: 'Android Reverse Debugger',
        fr: 'Débogueur Android Reverse',
        de: 'Android-Reverse-Debugger',
        ja: 'Android Reverse デバッガ',
      ),
      text(
        zh: '设备: ${running ? (deviceOnline ? deviceLabel : '无设备') : '未运行'}',
        zhHant: '設備: ${running ? (deviceOnline ? deviceLabel : '無設備') : '未執行'}',
        en: 'Device: ${running ? (deviceOnline ? deviceLabel : 'no device') : 'stopped'}',
        fr: 'Appareil : ${running ? (deviceOnline ? deviceLabel : 'aucun appareil') : 'arrêté'}',
        de: 'Gerät: ${running ? (deviceOnline ? deviceLabel : 'kein Gerät') : 'gestoppt'}',
        ja: 'デバイス: ${running ? (deviceOnline ? deviceLabel : 'デバイスなし') : '停止中'}',
      ),
      text(
        zh: '进程: $processCount',
        zhHant: '進程: $processCount',
        en: 'Processes: $processCount',
        fr: 'Processus : $processCount',
        de: 'Prozesse: $processCount',
        ja: 'プロセス: $processCount',
      ),
    ].join('\n');

    return _SessionToolbarStatusPill(
      tooltip: tooltip,
      icon: Icons.android_rounded,
      label: label,
      dotColor: dotColor,
      onTap: _onPillTap,
      reduceMotion: reduceMotion,
      maxLabelWidth: 168,
    );
  }
}

String _homeSessionTooThrottleOffLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '节流·关',
    zhHant: '節流·關',
    en: 'Throttle·off',
    fr: 'Limite·off',
    de: 'Drossel·aus',
    ja: 'スロットル·オフ',
  );
}
