part of '../openhand_home_page.dart';

/// 目标模式的可用性与运行控制。
class _GoalControls {
  const _GoalControls({
    required this.available,
    required this.suppressedForQueue,
    required this.onPause,
    required this.onResume,
    required this.onTerminate,
  });

  /// 当前线程模板是否允许目标模式。
  final bool available;

  /// 队列里还有待发送消息时暂时收起控制条，避免与排队派发互相打断。
  final bool suppressedForQueue;

  final Future<void> Function() onPause;
  final Future<void> Function() onResume;
  final Future<void> Function() onTerminate;
}

/// 输入区待发送附件的状态与操作。
class _ComposerAttachments {
  const _ComposerAttachments({
    required this.drafts,
    required this.enabled,
    required this.onPick,
    required this.onRemove,
    required this.onReorder,
  });

  final List<_ComposerAttachmentDraft> drafts;

  /// 当前模型是否支持附件；为 false 时入口置灰而不是隐藏，避免布局跳动。
  final bool enabled;

  final Future<void> Function() onPick;
  final ValueChanged<String> onRemove;
  final void Function(int oldIndex, int newIndex) onReorder;
}

/// 待发送队列的状态与操作。
class _QueuedMessagesPanel {
  const _QueuedMessagesPanel({
    required this.messages,
    required this.guidanceInProgress,
    required this.onRemove,
    required this.onMove,
    required this.onEdit,
    required this.onGuide,
  });

  final List<_QueuedMessage> messages;

  /// 正在派发某条排队消息；此时队列上的操作全部锁定，避免并发改动队列。
  final bool guidanceInProgress;

  final ValueChanged<int> onRemove;
  final void Function(int from, int to) onMove;
  final void Function(int index, String newText) onEdit;
  final ValueChanged<int> onGuide;
}

/// 单条消息上的操作回调集合。
class _MessageActions {
  const _MessageActions({
    required this.onEdit,
    required this.onCopy,
    required this.onDelete,
    required this.onDeleteFromHere,
    required this.onFork,
    required this.onSetFeedback,
    required this.onRegenerate,
    required this.onSelectResponseVariant,
  });

  final Future<void> Function(AiSessionMessage message) onEdit;
  final Future<void> Function(AiSessionMessage message) onCopy;

  /// 返回是否真的删除了（用户可能在确认弹窗里取消）。
  final Future<bool> Function(AiSessionMessage message) onDelete;
  final Future<bool> Function(AiSessionMessage message) onDeleteFromHere;

  final Future<void> Function(AiSessionMessage message) onFork;
  final Future<void> Function(
    AiSessionMessage message,
    AiSessionMessageFeedback? feedback,
  )
  onSetFeedback;
  final Future<void> Function(AiSessionMessage message) onRegenerate;
  final Future<void> Function(AiSessionMessage message, int index)
  onSelectResponseVariant;
}

class _WorkspaceView extends StatelessWidget {
  const _WorkspaceView({
    required this.draftController,
    required this.messageScrollController,
    required this.onMessageScrollNotification,
    required this.onMessagePointerSignal,
    required this.currentSession,
    required this.liveRuntimeToolPreview,
    required this.transcriptHydrating,
    required this.transcriptLoadError,
    required this.onRetryTranscriptLoad,
    required this.selectedModel,
    required this.availableModels,
    required this.recentModelSelections,
    required this.onModelSelected,
    required this.composerFocusNode,
    required this.composerHeight,
    required this.composerCollapsed,
    required this.onComposerHeightChanged,
    required this.onComposerCollapsedChanged,
    required this.onComposerLayoutChanged,
    required this.onTranscriptLayoutChanged,
    required this.onMessageExpansionChanged,
    required this.onRevealOlderMessages,
    required this.onProgrammaticScrollCorrection,
    required this.autoFollowEnabled,
    required this.autoFollowPaused,
    required this.onToggleAutoFollow,
    required this.sendPhase,
    required this.canStopSending,
    required this.planTimelineCollapsed,
    required this.onPlanTimelineCollapsedChanged,
    required this.sessionMode,
    required this.onSessionModeChanged,
    required this.goalControls,
    required this.attachments,
    required this.onSend,
    required this.onStop,
    required this.onCreateThreadRequested,
    required this.creationMode,
    required this.onCreationModeChanged,
    this.creationOptions = AiCreationOptions.empty,
    this.onCreationOptionsChanged,
    this.onEditOptionsRequested,
    required this.editingMessageId,
    required this.onCancelEditing,
    required this.messageActions,
    required this.ttsPlaybackService,
    required this.translationService,
    required this.onDismissError,
    required this.fullAccessPermission,
    required this.onToggleFullAccessPermission,
    required this.queuedPanel,
    this.jumpToBottomOnInit = false,
    this.fileExplorerVisible = false,
    this.onFileExplorerToggled,
    this.machineTerminalPanelVisible = false,
    this.onMachineTerminalPanelToggled,
    this.projectRoot,
    this.onComposerStateCreated,
    this.onComposerStateDisposed,
    this.skippedInstructionIds = const <String>{},
    this.onToggleInstructionSkip,
  });

  final TextEditingController draftController;
  final ScrollController messageScrollController;
  final bool Function(ScrollNotification notification)
  onMessageScrollNotification;
  final ValueChanged<PointerSignalEvent> onMessagePointerSignal;
  final AiSession? currentSession;
  final AiRuntimeToolPreview? liveRuntimeToolPreview;
  final bool transcriptHydrating;
  final String? transcriptLoadError;
  final Future<void> Function() onRetryTranscriptLoad;
  final AiModelConfig? selectedModel;
  final List<AiModelConfig> availableModels;
  final List<RecentModelSelection> recentModelSelections;
  final void Function(String providerConfigId, String modelId) onModelSelected;
  final FocusNode composerFocusNode;
  final double composerHeight;
  final bool composerCollapsed;
  final ValueChanged<double> onComposerHeightChanged;
  final ValueChanged<bool> onComposerCollapsedChanged;
  final VoidCallback onComposerLayoutChanged;
  final VoidCallback onTranscriptLayoutChanged;
  final ValueChanged<bool> onMessageExpansionChanged;
  final VoidCallback onRevealOlderMessages;
  final void Function(VoidCallback correction) onProgrammaticScrollCorrection;
  final bool autoFollowEnabled;
  final bool autoFollowPaused;
  final VoidCallback onToggleAutoFollow;
  final AiSendPhase sendPhase;
  final bool canStopSending;
  final bool planTimelineCollapsed;
  final ValueChanged<bool>? onPlanTimelineCollapsedChanged;
  final AiSessionMode sessionMode;
  final ValueChanged<AiSessionMode> onSessionModeChanged;
  final _GoalControls goalControls;
  final _ComposerAttachments attachments;
  final Future<void> Function() onSend;
  final Future<void> Function() onStop;
  final Future<void> Function() onCreateThreadRequested;
  final _CreationMode creationMode;
  final ValueChanged<_CreationMode> onCreationModeChanged;
  final AiCreationOptions creationOptions;
  final ValueChanged<AiCreationOptions>? onCreationOptionsChanged;
  final Future<void> Function()? onEditOptionsRequested;
  final String? editingMessageId;
  final Future<void> Function() onCancelEditing;
  final _MessageActions messageActions;
  final AiTtsPlaybackService ttsPlaybackService;
  final AiTranslationService translationService;
  final Future<void> Function(AiSessionErrorRecord error) onDismissError;
  final bool fullAccessPermission;
  final ValueChanged<bool> onToggleFullAccessPermission;
  final _QueuedMessagesPanel queuedPanel;
  // 首帧直接跳到底部，避免依赖父级滚动调度。
  final bool jumpToBottomOnInit;
  final bool fileExplorerVisible;
  final VoidCallback? onFileExplorerToggled;
  final bool machineTerminalPanelVisible;
  final VoidCallback? onMachineTerminalPanelToggled;
  final String? projectRoot;
  final ValueChanged<_ComposerPanelState>? onComposerStateCreated;
  final ValueChanged<_ComposerPanelState>? onComposerStateDisposed;

  /// 【指令】胶囊：本轮被临时取消的指令 ID 集合。
  final Set<String> skippedInstructionIds;
  final ValueChanged<String>? onToggleInstructionSkip;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxComposerHeight = (constraints.maxHeight - 96)
            .clamp(_composerMinHeight, _composerMaxHeight)
            .toDouble();
        final effectiveComposerHeight = composerHeight
            .clamp(_composerMinHeight, maxComposerHeight)
            .toDouble();
        final session = currentSession;
        final hasLoadedMessages = session?.messages.isNotEmpty == true;
        final shouldShowTranscriptHydrating =
            session != null && !hasLoadedMessages && transcriptHydrating;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _WorkspacePrimarySwitcher(
                key: const ValueKey<String>('workspace-primary-switcher'),
                child: session == null
                    ? const _WorkspaceEmptyState(
                        key: ValueKey<String>('no-session'),
                      )
                    : KeyedSubtree(
                        key: ValueKey<String>('session-${session.id}'),
                        child: !hasLoadedMessages
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _SessionToolbar(
                                    session: session,
                                    liveRuntimeToolPreview:
                                        liveRuntimeToolPreview,
                                    sendPhase: sendPhase,
                                    planTimelineCollapsed:
                                        planTimelineCollapsed,
                                    onPlanTimelineCollapsedChanged:
                                        onPlanTimelineCollapsedChanged,
                                    fileExplorerVisible: fileExplorerVisible,
                                    onFileExplorerToggled:
                                        onFileExplorerToggled,
                                    machineTerminalPanelVisible:
                                        machineTerminalPanelVisible,
                                    onMachineTerminalPanelToggled:
                                        onMachineTerminalPanelToggled,
                                    activeProfile: selectedModel
                                        ?.modelProfiles[selectedModel!.modelId],
                                    claudeStyle:
                                        selectedModel?.protocolType ==
                                        AiProtocolType.claude,
                                  ),
                                  kOpenHandGap14,
                                  Expanded(
                                    child: shouldShowTranscriptHydrating
                                        ? _TranscriptHydratingPlaceholder(
                                            key: ValueKey<String>(
                                              'hydrating-${session.id}',
                                            ),
                                          )
                                        : transcriptLoadError != null
                                        ? _TranscriptLoadFailure(
                                            key: ValueKey<String>(
                                              'load-failed-${session.id}',
                                            ),
                                            message: transcriptLoadError!,
                                            onRetry: onRetryTranscriptLoad,
                                          )
                                        : _WorkspaceEmptyState(
                                            key: ValueKey<String>(session.id),
                                            session: session,
                                          ),
                                  ),
                                ],
                              )
                            : Listener(
                                behavior: HitTestBehavior.translucent,
                                onPointerSignal: onMessagePointerSignal,
                                child: _SessionTranscript(
                                  key: ValueKey<String>(
                                    'messages-${session.id}',
                                  ),
                                  controller: messageScrollController,
                                  onScrollNotification:
                                      onMessageScrollNotification,
                                  session: session,
                                  liveRuntimeToolPreview:
                                      liveRuntimeToolPreview,
                                  sendPhase: sendPhase,
                                  planTimelineCollapsed: planTimelineCollapsed,
                                  onPlanTimelineCollapsedChanged:
                                      onPlanTimelineCollapsedChanged,
                                  onLayoutChanged: onTranscriptLayoutChanged,
                                  onMessageExpansionChanged:
                                      onMessageExpansionChanged,
                                  preserveViewportAfterUserScroll:
                                      !autoFollowEnabled || autoFollowPaused,
                                  onRevealOlderMessages: onRevealOlderMessages,
                                  onProgrammaticScrollCorrection:
                                      onProgrammaticScrollCorrection,
                                  messageActions: messageActions,
                                  ttsPlaybackService: ttsPlaybackService,
                                  translationService: translationService,
                                  onDismissError: onDismissError,
                                  jumpToBottomOnInit: jumpToBottomOnInit,
                                  fileExplorerVisible: fileExplorerVisible,
                                  onFileExplorerToggled: onFileExplorerToggled,
                                  machineTerminalPanelVisible:
                                      machineTerminalPanelVisible,
                                  onMachineTerminalPanelToggled:
                                      onMachineTerminalPanelToggled,
                                  activeProfile: selectedModel
                                      ?.modelProfiles[selectedModel!.modelId],
                                  claudeStyle:
                                      selectedModel?.protocolType ==
                                      AiProtocolType.claude,
                                ),
                              ),
                      ),
              ),
            ),
            if (currentSession != null) ...[
              kOpenHandGap16,
              _ComposerInstructionsStrip(
                skippedIds: skippedInstructionIds,
                onToggle: onToggleInstructionSkip,
              ),
              NotificationListener<SizeChangedLayoutNotification>(
                onNotification: (notification) {
                  onComposerLayoutChanged();
                  return false;
                },
                child: SizeChangedLayoutNotifier(
                  child: RepaintBoundary(
                    child: _ComposerPanel(
                      onStateCreated: onComposerStateCreated,
                      onStateDisposed: onComposerStateDisposed,
                      currentSession: currentSession,
                      liveRuntimeToolPreview: liveRuntimeToolPreview,
                      controller: draftController,
                      selectedModel: selectedModel,
                      availableModels: availableModels,
                      recentModelSelections: recentModelSelections,
                      onModelSelected: onModelSelected,
                      focusNode: composerFocusNode,
                      composerHeight: effectiveComposerHeight,
                      isCollapsed: composerCollapsed,
                      onCollapsedChanged: onComposerCollapsedChanged,
                      autoFollowEnabled: autoFollowEnabled,
                      autoFollowPaused: autoFollowPaused,
                      onToggleAutoFollow: onToggleAutoFollow,
                      sendPhase: sendPhase,
                      canStopSending: canStopSending,
                      sessionMode: sessionMode,
                      onSessionModeChanged: onSessionModeChanged,
                      goalControls: goalControls,
                      attachments: attachments,
                      onSend: onSend,
                      onStop: onStop,
                      creationMode: creationMode,
                      onCreationModeChanged: onCreationModeChanged,
                      creationOptions: creationOptions,
                      onCreationOptionsChanged: onCreationOptionsChanged,
                      onEditOptionsRequested: onEditOptionsRequested,
                      editingMessageId: editingMessageId,
                      onCancelEditing: onCancelEditing,
                      fullAccessPermission: fullAccessPermission,
                      onToggleFullAccessPermission:
                          onToggleFullAccessPermission,
                      queuedPanel: queuedPanel,
                      projectRoot: projectRoot,
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _TranscriptLoadFailure extends StatelessWidget {
  const _TranscriptLoadFailure({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.errorContainer.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(kOpenHandRadius24),
            border: Border.all(color: colors.error.withValues(alpha: 0.28)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.history_toggle_off_rounded,
                  size: 38,
                  color: colors.onErrorContainer,
                ),
                kOpenHandGap14,
                Text(
                  openHandLocalizedText(
                    context,
                    zh: '无法加载此会话',
                    en: 'Unable to load this conversation',
                  ),
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: colors.onErrorContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                kOpenHandGap8,
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onErrorContainer.withValues(alpha: 0.82),
                  ),
                ),
                kOpenHandGap18,
                FilledButton.icon(
                  onPressed: () => unawaited(onRetry()),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(openHandRetryLabel(context)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceEmptyState extends StatefulWidget {
  const _WorkspaceEmptyState({super.key, this.session});

  final AiSession? session;

  @override
  State<_WorkspaceEmptyState> createState() => _WorkspaceEmptyStateState();
}

class _WorkspaceEmptyStateState extends State<_WorkspaceEmptyState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _curved;
  late Animation<double> _fade;
  late Animation<double> _scale;
  late Animation<Offset> _slide;
  bool _entranceStarted = false;

  DialogAnimationSettings _resolveSettings() {
    return openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: Duration.zero);
    _curved = CurvedAnimation(
      parent: _controller,
      curve: kOpenHandSwitchInCurve,
      reverseCurve: kOpenHandSwitchOutCurve,
    );
    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(_curved);
    _scale = Tween<double>(begin: 0.92, end: 1.0).animate(_curved);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(_curved);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = _resolveSettings();
    final baseMs = settings.entranceDuration.inMilliseconds;
    final durationMs = baseMs == 0 ? 0 : baseMs.clamp(240, 520).toInt();
    final duration = Duration(milliseconds: durationMs);
    final durationChanged = _controller.duration != duration;
    _controller.duration = duration;
    _curved
      ..curve = settings.curve.curve
      ..reverseCurve = settings.curve.reverseCurve;
    if (durationMs == 0) {
      _controller.value = 1;
      _entranceStarted = true;
    } else if (!_entranceStarted) {
      _entranceStarted = true;
      _controller.forward();
    } else if (durationChanged && _controller.isAnimating) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final session = widget.session;
    final title = session?.title ?? l10n.newThread;
    final subtitle = session?.templateName ?? l10n.appTitle;
    final emptyStateContent = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: kOpenHandBorderRadius32,
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 42,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          kOpenHandGap20,
          Text(title, style: theme.textTheme.headlineMedium),
          kOpenHandGap10,
          Text(
            subtitle,
            style: theme.textTheme.titleLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          kOpenHandGap12,
          Text(
            l10n.appTagline,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    final animatedContent = FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: ScaleTransition(scale: _scale, child: emptyStateContent),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
            child: Center(child: animatedContent),
          ),
        );
      },
    );
  }
}

/// 使用全局页面动画切换工作区内容，但不保留旧会话叠层。
class _WorkspacePrimarySwitcher extends StatelessWidget {
  const _WorkspacePrimarySwitcher({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final settings = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.page,
    );
    final entranceDuration = _effectiveSwitchDuration(
      settings.entranceDuration,
      minimumAnimatedDurationMs: 180,
      maximumAnimatedDurationMs: _sessionSwitchMaxDurationMs,
    );
    final exitDuration = _effectiveSwitchDuration(
      settings.exitDuration,
      minimumAnimatedDurationMs: 180,
      maximumAnimatedDurationMs: _sessionSwitchMaxDurationMs,
    );
    return AnimatedSwitcher(
      duration: entranceDuration,
      reverseDuration: exitDuration,
      layoutBuilder: (currentChild, _) =>
          currentChild ?? const SizedBox.shrink(),
      transitionBuilder: (animatedChild, animation) {
        final visibleAnimation = Tween<double>(
          begin: _sessionSwitchInitialProgress,
          end: 1,
        ).animate(animation);
        return _buildWorkspaceContentTransition(
          child: animatedChild,
          animation: visibleAnimation,
          settings: settings,
        );
      },
      child: child,
    );
  }
}

/// 输入框上方的【指令】胶囊条。
///
/// 显示 InstructionsController 中所有 enabled 的指令，每条以 chip 呈现：
///   - 未跳过：trailing X 图标，点击 → 本轮临时取消（chip 留在原位但变灰）。
///   - 已跳过：trailing + 图标，点击 → 重新加入本轮 prompt。
class _ComposerInstructionsStrip extends StatelessWidget {
  const _ComposerInstructionsStrip({
    required this.skippedIds,
    required this.onToggle,
  });

  final Set<String> skippedIds;
  final ValueChanged<String>? onToggle;

  @override
  Widget build(BuildContext context) {
    final entries = context
        .select<InstructionsController, List<UserInstructionEntry>>(
          (c) => c.enabledEntries,
        );
    if (entries.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: <Widget>[
          for (final entry in entries)
            _ComposerInstructionChip(
              entry: entry,
              skipped: skippedIds.contains(entry.id),
              onPressed: onToggle == null ? null : () => onToggle!(entry.id),
              theme: theme,
            ),
        ],
      ),
    );
  }
}

class _ComposerInstructionChip extends StatelessWidget {
  const _ComposerInstructionChip({
    required this.entry,
    required this.skipped,
    required this.onPressed,
    required this.theme,
  });

  final UserInstructionEntry entry;
  final bool skipped;
  final VoidCallback? onPressed;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final baseColor = skipped
        ? theme.colorScheme.surfaceContainerHigh
        : theme.colorScheme.primaryContainer;
    final fg = skipped
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onPrimaryContainer;
    return Material(
      color: baseColor,
      shape: StadiumBorder(
        side: BorderSide(color: theme.colorScheme.outlineVariant, width: 0.5),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.tips_and_updates_outlined, size: 14, color: fg),
              kOpenHandHGap4,
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: fg,
                    decoration: skipped
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
                ),
              ),
              kOpenHandHGap4,
              Icon(
                skipped ? Icons.add_rounded : Icons.close_rounded,
                size: 14,
                color: fg,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
