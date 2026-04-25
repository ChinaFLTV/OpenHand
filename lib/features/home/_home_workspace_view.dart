part of 'openhand_home_page.dart';

class _WorkspaceView extends StatelessWidget {
  const _WorkspaceView({
    required this.draftController,
    required this.messageScrollController,
    required this.onMessageScrollNotification,
    required this.currentSession,
    required this.liveRuntimeToolPreview,
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
    this.composerPanelKey,
  });

  final TextEditingController draftController;
  final ScrollController messageScrollController;
  final bool Function(ScrollNotification notification)
  onMessageScrollNotification;
  final AiSession? currentSession;
  final AiRuntimeToolPreview? liveRuntimeToolPreview;
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
  final GlobalKey<_ComposerPanelState>? composerPanelKey;

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

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _WorkspacePrimarySwitcher(
                child: currentSession == null
                    ? const _WorkspaceEmptyState(
                        key: ValueKey<String>('no-session'),
                      )
                    : currentSession!.messages.isEmpty
                    ? Column(
                        key: ValueKey<String>('empty-${currentSession!.id}'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SessionToolbar(
                            session: currentSession!,
                            liveRuntimeToolPreview: liveRuntimeToolPreview,
                            sendPhase: sendPhase,
                            planTimelineCollapsed: planTimelineCollapsed,
                            onPlanTimelineCollapsedChanged:
                                onPlanTimelineCollapsedChanged,
                            fileExplorerVisible: fileExplorerVisible,
                            onFileExplorerToggled: onFileExplorerToggled,
                          ),
                          const SizedBox(height: 14),
                          Expanded(
                            child: _WorkspaceEmptyState(
                              key: ValueKey<String>(currentSession!.id),
                              session: currentSession,
                            ),
                          ),
                        ],
                      )
                    : KeyedSubtree(
                        key: ValueKey<String>('content-${currentSession!.id}'),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: AnimatedOpacity(
                                // 瞬间使其隐身以彻底遮盖背后的列表疯狂重排乱跳的现象
                                opacity: transcriptPreparing ? 0.0 : 1.0,
                                duration: transcriptPreparing
                                    ? Duration.zero
                                    : const Duration(milliseconds: 160),
                                curve: Curves.easeOutCubic,
                                child: _SessionTranscript(
                                  key: ValueKey<String>(
                                    'messages-${currentSession!.id}',
                                  ),
                                  controller: messageScrollController,
                                  onScrollNotification:
                                      onMessageScrollNotification,
                                  session: currentSession!,
                                  liveRuntimeToolPreview:
                                      liveRuntimeToolPreview,
                                  sendPhase: sendPhase,
                                  planTimelineCollapsed: planTimelineCollapsed,
                                  onPlanTimelineCollapsedChanged:
                                      onPlanTimelineCollapsedChanged,
                                  onLayoutChanged: onTranscriptLayoutChanged,
                                  onRevealOlderMessages: onRevealOlderMessages,
                                  onEditMessage: onEditMessage,
                                  onCopyMessage: onCopyMessage,
                                  onDeleteMessage: onDeleteMessage,
                                  onDeleteMessageFromHere:
                                      onDeleteMessageFromHere,
                                  onDismissError: onDismissError,
                                  // Jump to the very bottom on the first frame when the
                                  // session was just activated, so the user never sees a
                                  // flash from scroll-top to scroll-bottom.
                                  jumpToBottomOnInit: jumpToBottomOnInit,
                                  fileExplorerVisible: fileExplorerVisible,
                                  onFileExplorerToggled: onFileExplorerToggled,
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
                                      'session-transcript-loading-${currentSession!.id}',
                                    ),
                                    session: currentSession!,
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
              NotificationListener<SizeChangedLayoutNotification>(
                onNotification: (notification) {
                  onComposerLayoutChanged();
                  return false;
                },
                child: SizeChangedLayoutNotifier(
                  child: _ComposerPanel(
                    key: composerPanelKey,
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
                    onToggleFullAccessPermission: onToggleFullAccessPermission,
                    queuedMessages: queuedMessages,
                    onRemoveQueuedMessage: onRemoveQueuedMessage,
                    onMoveQueuedMessage: onMoveQueuedMessage,
                    onEditQueuedMessage: onEditQueuedMessage,
                    projectRoot: projectRoot,
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
    try {
      return context.read<SettingsController>().dialogAnimationSettings;
    } catch (_) {
      return const DialogAnimationSettings();
    }
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
  const _WorkspacePrimarySwitcher({required this.child});

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
    DialogAnimationSettings settings;
    try {
      settings = context.read<SettingsController>().pageAnimationSettings;
    } catch (_) {
      settings = const DialogAnimationSettings();
    }
    final curveData = settings.curve;
    return AnimatedSwitcher(
      duration: _effectiveSwitchDuration(settings),
      switchInCurve: curveData.curve,
      switchOutCurve: curveData.reverseCurve,
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
          child: _buildPanelTransition(
            child: animatedChild,
            animation: animation,
            entranceStyle: settings.entranceStyle,
            exitStyle: settings.exitStyle,
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
