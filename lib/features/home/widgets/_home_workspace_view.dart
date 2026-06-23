part of '../openhand_home_page.dart';

class _WorkspaceView extends StatelessWidget {
  const _WorkspaceView({
    required this.draftController,
    required this.messageScrollController,
    required this.onMessageScrollNotification,
    required this.onMessagePointerSignal,
    required this.currentSession,
    required this.liveRuntimeToolPreview,
    required this.transcriptHydrating,
    required this.transcriptPreparing,
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
    required this.pendingAttachments,
    required this.attachmentsEnabled,
    required this.onPickAttachments,
    required this.onRemoveAttachment,
    required this.onReorderAttachments,
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
    required this.onEditMessage,
    required this.onCopyMessage,
    required this.onDeleteMessage,
    required this.onDeleteMessageFromHere,
    required this.onForkMessage,
    required this.onSetMessageFeedback,
    required this.onRegenerateMessage,
    required this.onSelectMessageResponseVariant,
    required this.ttsPlaybackService,
    required this.translationService,
    required this.onDismissError,
    required this.fullAccessPermission,
    required this.onToggleFullAccessPermission,
    required this.queuedMessages,
    required this.onRemoveQueuedMessage,
    required this.onMoveQueuedMessage,
    required this.onEditQueuedMessage,
    this.jumpToBottomOnInit = false,
    this.fileExplorerVisible = false,
    this.onFileExplorerToggled,
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
  final bool transcriptPreparing;
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
  final List<_ComposerAttachmentDraft> pendingAttachments;
  final bool attachmentsEnabled;
  final Future<void> Function() onPickAttachments;
  final ValueChanged<String> onRemoveAttachment;
  final void Function(int oldIndex, int newIndex) onReorderAttachments;
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
  final Future<void> Function(AiSessionMessage message) onEditMessage;
  final Future<void> Function(AiSessionMessage message) onCopyMessage;
  final Future<bool> Function(AiSessionMessage message) onDeleteMessage;
  final Future<bool> Function(AiSessionMessage message) onDeleteMessageFromHere;
  final Future<void> Function(AiSessionMessage message) onForkMessage;
  final Future<void> Function(
    AiSessionMessage message,
    AiSessionMessageFeedback? feedback,
  )
  onSetMessageFeedback;
  final Future<void> Function(AiSessionMessage message) onRegenerateMessage;
  final Future<void> Function(AiSessionMessage message, int index)
  onSelectMessageResponseVariant;
  final AiTtsPlaybackService ttsPlaybackService;
  final AiTranslationService translationService;
  final Future<void> Function(AiSessionErrorRecord error) onDismissError;
  final bool fullAccessPermission;
  final ValueChanged<bool> onToggleFullAccessPermission;
  final List<_QueuedMessage> queuedMessages;
  final ValueChanged<int> onRemoveQueuedMessage;
  final void Function(int from, int to) onMoveQueuedMessage;
  final void Function(int index, String newText) onEditQueuedMessage;
  // When true, the message list widget will immediately jump to the bottom
  // on its first frame instead of relying on the parent's scroll scheduler.
  final bool jumpToBottomOnInit;
  final bool fileExplorerVisible;
  final VoidCallback? onFileExplorerToggled;
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
                    : !hasLoadedMessages
                    ? Column(
                        key: ValueKey<String>('empty-${session.id}'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SessionToolbar(
                            session: session,
                            liveRuntimeToolPreview: liveRuntimeToolPreview,
                            sendPhase: sendPhase,
                            planTimelineCollapsed: planTimelineCollapsed,
                            onPlanTimelineCollapsedChanged:
                                onPlanTimelineCollapsedChanged,
                            fileExplorerVisible: fileExplorerVisible,
                            onFileExplorerToggled: onFileExplorerToggled,
                            activeProfile: selectedModel
                                ?.modelProfiles[selectedModel!.modelId],
                            claudeStyle:
                                selectedModel?.protocolType ==
                                AiProtocolType.claude,
                          ),
                          const SizedBox(height: 14),
                          Expanded(
                            child: shouldShowTranscriptHydrating
                                ? _TranscriptHydratingPlaceholder(
                                    key: ValueKey<String>(
                                      'hydrating-${session.id}',
                                    ),
                                  )
                                : _WorkspaceEmptyState(
                                    key: ValueKey<String>(session.id),
                                    session: session,
                                  ),
                          ),
                        ],
                      )
                    : KeyedSubtree(
                        key: ValueKey<String>('content-${session.id}'),
                        child: Stack(
                          children: [
                            // placeholder 阶段直接 SizedBox 占位，不
                            // 把 _SessionTranscript 树挂进 widget tree。之前
                            // 用 AnimatedOpacity(0) 隐身但保留 mount 的写法，
                            // initState/build/markdown 解析照常跑，等于 ANR
                            // 隐藏在 placeholder 背后。现在严格延后到
                            // transcriptPreparing 反向之后才 mount，让
                            // placeholder 阶段主线程完全空出来给首帧布局。
                            Positioned.fill(
                              child: AnimatedOpacity(
                                opacity: transcriptPreparing ? 0.0 : 1.0,
                                duration: transcriptPreparing
                                    ? Duration.zero
                                    : const Duration(milliseconds: 160),
                                curve: Curves.easeOutCubic,
                                child: transcriptPreparing
                                    ? const SizedBox.expand()
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
                                          planTimelineCollapsed:
                                              planTimelineCollapsed,
                                          onPlanTimelineCollapsedChanged:
                                              onPlanTimelineCollapsedChanged,
                                          onLayoutChanged:
                                              onTranscriptLayoutChanged,
                                          onRevealOlderMessages:
                                              onRevealOlderMessages,
                                          onProgrammaticScrollCorrection:
                                              onProgrammaticScrollCorrection,
                                          onEditMessage: onEditMessage,
                                          onCopyMessage: onCopyMessage,
                                          onDeleteMessage: onDeleteMessage,
                                          onDeleteMessageFromHere:
                                              onDeleteMessageFromHere,
                                          onForkMessage: onForkMessage,
                                          onSetMessageFeedback:
                                              onSetMessageFeedback,
                                          onRegenerateMessage:
                                              onRegenerateMessage,
                                          onSelectMessageResponseVariant:
                                              onSelectMessageResponseVariant,
                                          ttsPlaybackService:
                                              ttsPlaybackService,
                                          translationService:
                                              translationService,
                                          onDismissError: onDismissError,
                                          // Jump to the very bottom on the first
                                          // frame when the session was just
                                          // activated, so the user never sees a
                                          // flash from scroll-top to
                                          // scroll-bottom.
                                          jumpToBottomOnInit:
                                              jumpToBottomOnInit,
                                          fileExplorerVisible:
                                              fileExplorerVisible,
                                          onFileExplorerToggled:
                                              onFileExplorerToggled,
                                          activeProfile:
                                              selectedModel
                                                  ?.modelProfiles[selectedModel!
                                                  .modelId],
                                          claudeStyle:
                                              selectedModel?.protocolType ==
                                              AiProtocolType.claude,
                                        ),
                                      ),
                              ),
                            ),
                            // Overlay mask that visually hides the initial rendering
                            // and scroll-to-bottom operations of the transcript list.
                            Positioned.fill(
                              child: IgnorePointer(
                                ignoring: !transcriptPreparing,
                                child: AnimatedOpacity(
                                  opacity: transcriptPreparing ? 1.0 : 0.0,
                                  // 进场需提前快过底部列表跳跃，退场再慢慢淡出
                                  duration: transcriptPreparing
                                      ? const Duration(milliseconds: 80)
                                      : const Duration(milliseconds: 160),
                                  curve: Curves.easeOutCubic,
                                  child: _SessionTranscriptLoadingPlaceholder(
                                    key: ValueKey<String>(
                                      'session-transcript-loading-${session.id}',
                                    ),
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
                                    activeProfile: selectedModel
                                        ?.modelProfiles[selectedModel!.modelId],
                                    claudeStyle:
                                        selectedModel?.protocolType ==
                                        AiProtocolType.claude,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
            if (currentSession != null) ...[
              const SizedBox(height: 16),
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
                      pendingAttachments: pendingAttachments,
                      attachmentsEnabled: attachmentsEnabled,
                      onPickAttachments: onPickAttachments,
                      onRemoveAttachment: onRemoveAttachment,
                      onReorderAttachments: onReorderAttachments,
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
                      queuedMessages: queuedMessages,
                      onRemoveQueuedMessage: onRemoveQueuedMessage,
                      onMoveQueuedMessage: onMoveQueuedMessage,
                      onEditQueuedMessage: onEditQueuedMessage,
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

class _WorkspaceEmptyState extends StatefulWidget {
  const _WorkspaceEmptyState({super.key, this.session});

  final AiSession? session;

  @override
  State<_WorkspaceEmptyState> createState() => _WorkspaceEmptyStateState();
}

class _WorkspaceEmptyStateState extends State<_WorkspaceEmptyState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _fade;
  late Animation<double> _scale;
  late Animation<Offset> _slide;

  DialogAnimationSettings _resolveSettings() {
    return openHandMotionSettingsFallbackOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
  }

  @override
  void initState() {
    super.initState();
    final settings = _resolveSettings();
    // Use the user-configured dialog duration but clamp to a range that
    // looks graceful for an inline hero placeholder rather than a modal
    // dialog (which can afford longer transitions).
    final baseMs = settings.duration.inMilliseconds;
    final durationMs = baseMs == 0 ? 0 : baseMs.clamp(240, 520).toInt();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: durationMs),
    );
    final curveData = settings.curve;
    final curved = CurvedAnimation(
      parent: _controller,
      curve: curveData.curve,
      reverseCurve: curveData.reverseCurve,
    );
    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
    _scale = Tween<double>(begin: 0.92, end: 1.0).animate(curved);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(curved);
    _controller.forward();
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
              borderRadius: BorderRadius.circular(32),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 42,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 20),
          Text(title, style: theme.textTheme.headlineMedium),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: theme.textTheme.titleLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
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

/// Animates the workspace primary content (empty-state / transcript) across
/// session/template changes using the global page animation settings.
///
/// The transcript reuses a long-lived [ScrollController] owned by the home
/// page. Keeping an outgoing transcript mounted during an [AnimatedSwitcher]
/// cross-fade attaches that controller to two [ScrollPosition]s at once,
/// which trips desktop [RawScrollbar] validation. We therefore allow only the
/// empty-state placeholders to overlap during the transition; transcript
/// content always swaps atomically.
class _WorkspacePrimarySwitcher extends StatelessWidget {
  const _WorkspacePrimarySwitcher({super.key, required this.child});

  final Widget child;

  static bool _allowsOutgoingOverlap(Widget child) {
    if (child is KeyedSubtree) {
      return _allowsOutgoingOverlap(child.child);
    }
    final key = child.key;
    if (key is! ValueKey<String>) {
      return false;
    }
    return key.value == 'no-session' || key.value.startsWith('empty-');
  }

  static bool _transitionAllowsOutgoingOverlap(Widget child) {
    if (child is _WorkspacePrimarySwitchTransition) {
      return child.allowOutgoingOverlap;
    }
    if (child is KeyedSubtree) {
      return _transitionAllowsOutgoingOverlap(child.child);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final settings = openHandMotionSettingsFallbackOf(
      context,
      OpenHandMotionSettingsScope.page,
    );
    final baseDuration = _effectiveSwitchDuration(settings);
    return AnimatedSwitcher(
      duration: Duration(
        milliseconds: math.max(baseDuration.inMilliseconds, 280),
      ),
      layoutBuilder: (currentChild, previousChildren) {
        final safePreviousChildren = previousChildren.where((previousChild) {
          return _transitionAllowsOutgoingOverlap(previousChild);
        });
        return Stack(
          alignment: Alignment.topCenter,
          children: <Widget>[
            ...safePreviousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (animatedChild, animation) {
        return _WorkspacePrimarySwitchTransition(
          allowOutgoingOverlap: _allowsOutgoingOverlap(animatedChild),
          child: _buildWorkspaceContentTransition(
            child: animatedChild,
            animation: animation,
          ),
        );
      },
      child: child,
    );
  }
}

class _WorkspacePrimarySwitchTransition extends StatelessWidget {
  const _WorkspacePrimarySwitchTransition({
    required this.allowOutgoingOverlap,
    required this.child,
  });

  final bool allowOutgoingOverlap;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
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
              const SizedBox(width: 4),
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
              const SizedBox(width: 4),
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
