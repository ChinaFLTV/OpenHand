part of 'openhand_home_page.dart';

class _SessionTranscriptLoadingPlaceholder extends StatelessWidget {
  const _SessionTranscriptLoadingPlaceholder({
    super.key,
    required this.session,
    required this.liveRuntimeToolPreview,
    required this.sendPhase,
    required this.planTimelineCollapsed,
    required this.onPlanTimelineCollapsedChanged,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SessionToolbar(
          session: session,
          liveRuntimeToolPreview: liveRuntimeToolPreview,
          sendPhase: sendPhase,
          planTimelineCollapsed: planTimelineCollapsed,
          onPlanTimelineCollapsedChanged: onPlanTimelineCollapsedChanged,
          fileExplorerVisible: fileExplorerVisible,
          onFileExplorerToggled: onFileExplorerToggled,
        ),
        const SizedBox(height: 14),
        // 2026-04-27 (UX): 移除会话加载占位中的 OpenHand 品牌 LOGO，避免在
        // 转录区中央突兀展示。保留 Expanded 占位以维持 Column 布局，使工具
        // 栏与底部输入框间距一致。
        const Expanded(child: SizedBox.shrink()),
      ],
    );
  }
}

class _TranscriptRenderEntry {
  const _TranscriptRenderEntry({
    required this.message,
    this.exiting = false,
    this.entering = false,
  });

  final AiSessionMessage message;
  final bool exiting;
  final bool entering;

  String get id => message.id;

  _TranscriptRenderEntry copyWith({
    AiSessionMessage? message,
    bool? exiting,
    bool? entering,
  }) {
    return _TranscriptRenderEntry(
      message: message ?? this.message,
      exiting: exiting ?? this.exiting,
      entering: entering ?? this.entering,
    );
  }
}

class _SessionTranscript extends StatefulWidget {
  const _SessionTranscript({
    super.key,
    required this.controller,
    required this.onScrollNotification,
    required this.session,
    required this.liveRuntimeToolPreview,
    required this.sendPhase,
    required this.planTimelineCollapsed,
    required this.onPlanTimelineCollapsedChanged,
    required this.onLayoutChanged,
    required this.onRevealOlderMessages,
    required this.onEditMessage,
    required this.onCopyMessage,
    required this.onDeleteMessage,
    required this.onDeleteMessageFromHere,
    required this.onDismissError,
    this.jumpToBottomOnInit = false,
    this.fileExplorerVisible = false,
    this.onFileExplorerToggled,
  });

  final ScrollController controller;
  final bool Function(ScrollNotification notification) onScrollNotification;
  final AiSession session;
  final AiRuntimeToolPreview? liveRuntimeToolPreview;
  final AiSendPhase sendPhase;
  final bool planTimelineCollapsed;
  final ValueChanged<bool>? onPlanTimelineCollapsedChanged;
  final VoidCallback onLayoutChanged;
  final VoidCallback onRevealOlderMessages;
  final Future<void> Function(AiSessionMessage message) onEditMessage;
  final Future<void> Function(AiSessionMessage message) onCopyMessage;
  final Future<bool> Function(AiSessionMessage message) onDeleteMessage;
  final Future<bool> Function(AiSessionMessage message) onDeleteMessageFromHere;
  final Future<void> Function(AiSessionErrorRecord error) onDismissError;
  // When true, the list will jump to the very bottom on its first frame.
  // This eliminates the visible scroll-from-top animation that would otherwise
  // appear when a session is loaded and the parent schedules a forced scroll.
  final bool jumpToBottomOnInit;
  final bool fileExplorerVisible;
  final VoidCallback? onFileExplorerToggled;

  @override
  State<_SessionTranscript> createState() => _SessionTranscriptState();
}

class _SessionTranscriptState extends State<_SessionTranscript> {
  String? _selectedMessageId;
  String? _visibleErrorId;
  String? _pendingPresentedErrorId;
  final Set<String> _dismissedErrorIds = <String>{};
  int _windowStartIndex = 0;
  bool _loadingOlderMessages = false;
  List<_TranscriptRenderEntry> _renderEntries =
      const <_TranscriptRenderEntry>[];
  bool _initialBuildDone = false;

  @override
  void initState() {
    super.initState();
    _syncWindowStartIndex(forceReset: true);
    _replaceRenderEntries(_visibleMessagesForWindow());
    _syncVisibleError();
    // Immediately jump to the bottom on the first rendered frame, before the
    // parent's postFrameCallback chain fires. This prevents the user from ever
    // seeing the list start at scroll-offset 0 while a forced scroll-to-bottom
    // is pending, which manifests as a jarring flash/jump animation.
    if (widget.jumpToBottomOnInit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final controller = widget.controller;
        if (controller.hasClients) {
          final position = controller.positions.isNotEmpty
              ? controller.positions.last
              : null;
          if (position != null && position.maxScrollExtent > 0) {
            // Jump on the specific position rather than
            // `controller.jumpTo` so a transient second attached position
            // (session cross-fade) does not trigger the `Scrollbar` /
            // `RawScrollbar` single-position validation.
            position.jumpTo(position.maxScrollExtent);
          }
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant _SessionTranscript oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.id != widget.session.id) {
      // Switching sessions used to rebuild the full transcript synchronously
      // inside `didUpdateWidget`, which on large sessions blocked the frame
      // that paints the new toolbar / shell. We now reset to an empty list
      // immediately so the cross-fade can start, then materialise the
      // visible window on the next frame so the heavy bubble build does not
      // bottleneck the transition itself.
      _syncWindowStartIndex(forceReset: true);
      _renderEntries = const <_TranscriptRenderEntry>[];
      _initialBuildDone = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_renderEntries.isNotEmpty) return;
        setState(() {
          _replaceRenderEntries(_visibleMessagesForWindow(), animate: false);
        });
      });
    } else if (oldWidget.session.messages != widget.session.messages ||
        oldWidget.session.updatedAt != widget.session.updatedAt) {
      final previousWindowStartIndex = _windowStartIndex;
      _syncWindowStartIndex();
      _syncRenderEntries(
        forceReset: previousWindowStartIndex != _windowStartIndex,
      );
    }
    if (oldWidget.session.id != widget.session.id ||
        oldWidget.session.recentErrors != widget.session.recentErrors) {
      _syncVisibleError();
    }
  }

  void _syncWindowStartIndex({bool forceReset = false}) {
    final displayMessages = widget.session.displayMessages;
    final nextWindowStartIndex = forceReset
        ? _initialWindowStartIndex(displayMessages.length)
        : _windowStartIndex.clamp(0, displayMessages.length).toInt();
    if (forceReset) {
      _loadingOlderMessages = false;
    }
    if (nextWindowStartIndex == _windowStartIndex) {
      return;
    }
    _windowStartIndex = nextWindowStartIndex;
  }

  List<AiSessionMessage> _visibleMessagesForWindow() {
    final displayMessages = widget.session.displayMessages;
    final clampedWindowStartIndex = _windowStartIndex
        .clamp(0, displayMessages.length)
        .toInt();
    return displayMessages.sublist(clampedWindowStartIndex);
  }

  void _replaceRenderEntries(
    List<AiSessionMessage> visibleMessages, {
    bool animate = true,
  }) {
    final previousIds = animate && _initialBuildDone
        ? _renderEntries.where((e) => !e.exiting).map((e) => e.id).toSet()
        : null;
    _renderEntries = <_TranscriptRenderEntry>[
      for (final message in visibleMessages)
        _TranscriptRenderEntry(
          message: message,
          entering: previousIds != null && !previousIds.contains(message.id),
        ),
    ];
    _initialBuildDone = true;
  }

  void _syncRenderEntries({bool forceReset = false}) {
    final visibleMessages = _visibleMessagesForWindow();
    if (forceReset || _renderEntries.isEmpty) {
      _replaceRenderEntries(visibleMessages, animate: false);
      return;
    }
    final visibleMessageIds = visibleMessages
        .map((message) => message.id)
        .toList(growable: false);
    final visibleMessageIdSet = visibleMessageIds.toSet();
    final visibleMessagesById = <String, AiSessionMessage>{
      for (final message in visibleMessages) message.id: message,
    };
    final activeEntries = _renderEntries
        .where((entry) => !entry.exiting)
        .toList(growable: false);
    final activeEntryIds = activeEntries
        .map((entry) => entry.id)
        .toList(growable: false);
    final activeEntryIdSet = activeEntryIds.toSet();
    final removedIds = activeEntryIds
        .where((id) => !visibleMessageIdSet.contains(id))
        .toSet();
    final hasAddedIds = visibleMessages.any(
      (message) => !activeEntryIdSet.contains(message.id),
    );
    final hasExitingEntries = _renderEntries.any((entry) => entry.exiting);
    if (removedIds.isEmpty) {
      if (!hasExitingEntries) {
        _replaceRenderEntries(visibleMessages);
        return;
      }
      _renderEntries = <_TranscriptRenderEntry>[
        for (final entry in _renderEntries)
          entry.exiting
              ? entry
              : entry.copyWith(message: visibleMessagesById[entry.id]),
      ];
      return;
    }
    if (hasAddedIds ||
        !_isOrderedSubsequence(visibleMessageIds, activeEntryIds)) {
      _replaceRenderEntries(visibleMessages);
      return;
    }
    _renderEntries = <_TranscriptRenderEntry>[
      for (final entry in _renderEntries)
        if (entry.exiting)
          entry
        else if (visibleMessagesById.containsKey(entry.id))
          entry.copyWith(message: visibleMessagesById[entry.id])
        else
          entry.copyWith(exiting: true),
    ];
  }

  bool _isOrderedSubsequence(List<String> candidate, List<String> source) {
    if (candidate.length > source.length) {
      return false;
    }
    var sourceIndex = 0;
    for (final candidateId in candidate) {
      var matched = false;
      while (sourceIndex < source.length) {
        if (source[sourceIndex] == candidateId) {
          matched = true;
          sourceIndex++;
          break;
        }
        sourceIndex++;
      }
      if (!matched) {
        return false;
      }
    }
    return true;
  }

  void _handleRenderEntryExitCompleted(String messageId) {
    if (!mounted) {
      return;
    }
    final shouldRemove = _renderEntries.any(
      (entry) => entry.id == messageId && entry.exiting,
    );
    if (!shouldRemove) {
      return;
    }
    setState(() {
      _renderEntries = _renderEntries
          .where((entry) => !(entry.id == messageId && entry.exiting))
          .toList(growable: false);
    });
  }

  int _initialWindowStartIndex(int messageCount) {
    if (messageCount <= _transcriptWindowingThreshold) {
      return 0;
    }
    return math.max(0, messageCount - _transcriptInitialWindowSize);
  }

  Future<void> _revealOlderMessages(int totalMessageCount) async {
    if (_windowStartIndex <= 0 || _loadingOlderMessages) {
      return;
    }

    // Remember current scroll metrics so we can restore visual position later.
    final scrollController = widget.controller;
    final hadClients = scrollController.hasClients;
    final currentOffset = hadClients ? scrollController.offset : 0.0;
    final currentMaxExtent = hadClients
        ? scrollController.position.maxScrollExtent
        : 0.0;

    setState(() {
      _loadingOlderMessages = true;
    });

    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!mounted) {
      return;
    }

    setState(() {
      _windowStartIndex = math.max(
        0,
        _windowStartIndex - _transcriptWindowIncrement,
      );
      _replaceRenderEntries(_visibleMessagesForWindow(), animate: false);
      _loadingOlderMessages = false;
    });

    // After the frame rebuilds with new items at the top, adjust scroll offset
    // so the user sees the same content as before (the "Load earlier" button's
    // position just replaced by older messages, but the later messages stay
    // in view).
    if (hadClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !scrollController.hasClients) return;

        // New content was prepended. The maxScrollExtent has increased by the
        // total height of the new items. To keep the user viewing the same
        // messages, we need to jump forward by that delta.
        final newMaxExtent = scrollController.position.maxScrollExtent;
        final delta = newMaxExtent - currentMaxExtent;

        if (delta > 0) {
          final targetOffset = (currentOffset + delta).clamp(0.0, newMaxExtent);
          scrollController.jumpTo(targetOffset);
        }
      });
    }
  }

  Future<void> _runDeleteAction(
    AiSessionMessage message,
    Future<bool> Function(AiSessionMessage message) deleteAction,
  ) async {
    final deleted = await deleteAction(message);
    if (!mounted || !deleted || _selectedMessageId != message.id) {
      return;
    }
    setState(() {
      _selectedMessageId = null;
    });
  }

  void _syncVisibleError() {
    final visibleError = _resolveUserVisibleError(widget.session);
    final visibleErrorId = visibleError?.id;
    final hasCurrentVisibleError =
        _visibleErrorId != null &&
        widget.session.recentErrors.any((error) => error.id == _visibleErrorId);
    if (visibleError != null && visibleErrorId != null) {
      _visibleErrorId = visibleErrorId;
      _markErrorAsPresented(visibleError);
      return;
    }
    if (!hasCurrentVisibleError) {
      _visibleErrorId = null;
    }
  }

  void _markErrorAsPresented(AiSessionErrorRecord error) {
    if (error.hasBeenPresented || _pendingPresentedErrorId == error.id) {
      return;
    }
    _pendingPresentedErrorId = error.id;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      await context.read<AiSessionController>().markErrorAsPresented(
        sessionId: widget.session.id,
        errorId: error.id,
      );
      if (!mounted || _pendingPresentedErrorId != error.id) {
        return;
      }
      _pendingPresentedErrorId = null;
    });
  }

  AiSessionErrorRecord? _resolveUserVisibleError(AiSession session) {
    for (final error in session.recentErrors) {
      if (error.stage == 'title_generation') {
        continue;
      }
      if (_dismissedErrorIds.contains(error.id)) {
        continue;
      }
      if (!error.hasBeenPresented) {
        return error;
      }
    }
    final visibleErrorId = _visibleErrorId;
    if (visibleErrorId == null) {
      return null;
    }
    for (final error in session.recentErrors) {
      if (_dismissedErrorIds.contains(error.id)) {
        continue;
      }
      if (error.id == visibleErrorId && error.stage != 'title_generation') {
        return error;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final displayMessages = session.displayMessages;
    // Read these provider values once here, at the transcript scope, instead
    // of re-subscribing inside ListView.builder's itemBuilder.  Calling
    // `context.watch()` inside itemBuilder registers the ListView element
    // itself as a listener, causing the full visible message window to
    // rebuild on any unrelated SettingsController change (theme, language,
    // tool toggles, etc.).  `select` narrows the subscription to just the
    // telemetry flag so most settings changes no longer invalidate the
    // transcript at all.
    final telemetryDebugEnabled = context.select<SettingsController, bool>(
      (controller) => controller.telemetryDebugEnabled,
    );
    final showSelfLearningMessages = context.select<SettingsController, bool>(
      (controller) => controller.showSelfLearningMessages,
    );
    final aiSessionController = context.read<AiSessionController>();
    final clampedWindowStartIndex = _windowStartIndex
        .clamp(0, displayMessages.length)
        .toInt();
    final hiddenMessageCount = clampedWindowStartIndex;
    final visibleMessages = displayMessages.sublist(clampedWindowStartIndex);
    if (_renderEntries.isEmpty && visibleMessages.isEmpty) {
      return _WorkspaceEmptyState(
        key: ValueKey<String>('empty-session-transcript-${session.id}'),
        session: session,
      );
    }
    final visibleMessageIndexById = <String, int>{
      for (var index = 0; index < visibleMessages.length; index++)
        visibleMessages[index].id: index,
    };
    final userVisibleError = _resolveUserVisibleError(session);
    if (_renderEntries.isEmpty &&
        visibleMessages.isEmpty &&
        userVisibleError == null) {
      return _WorkspaceEmptyState(
        key: ValueKey<String>('empty-session-transcript-${session.id}'),
        session: session,
      );
    }
    final hiddenLoadMoreCount = hiddenMessageCount > 0 ? 1 : 0;
    // When the session is actively awaiting the assistant and the most
    // recent user message asked for a multimedia creation (image / video /
    // audio / deep research), we slot in a shimmering placeholder card
    // immediately below the user bubble so there is never a blank gap
    // between the request and the eventual result.
    final pendingCreationRequest = _resolvePendingCreationPlaceholder(
      session: session,
      visibleMessages: visibleMessages,
      sendPhase: widget.sendPhase,
    );
    // When the assistant bailed out before producing any content AND the
    // user had asked for a multimedia creation, we swap the shimmer for an
    // explicit failure card (carrying the same error message the generic
    // banner would have shown). This keeps the failed turn visually tied to
    // the user's request instead of floating as a disconnected banner.
    final failedCreationRequest =
        (pendingCreationRequest == null &&
            userVisibleError != null &&
            widget.sendPhase == AiSendPhase.idle)
        ? _resolvePendingCreationPlaceholder(
            session: session,
            visibleMessages: visibleMessages,
            sendPhase: widget.sendPhase,
            allowWhenIdle: true,
          )
        : null;
    // If we render a dedicated failure card for the creation turn, suppress
    // the redundant generic error banner that would otherwise carry the
    // exact same message.
    final suppressGenericErrorBanner = failedCreationRequest != null;
    final errorBannerCount =
        (userVisibleError == null || suppressGenericErrorBanner) ? 0 : 1;
    final pendingPlaceholderCount = pendingCreationRequest == null ? 0 : 1;
    final failureCardCount = failedCreationRequest == null ? 0 : 1;
    final listItemCount =
        _renderEntries.length +
        hiddenLoadMoreCount +
        errorBannerCount +
        pendingPlaceholderCount +
        failureCardCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SessionToolbar(
          session: session,
          liveRuntimeToolPreview: widget.liveRuntimeToolPreview,
          sendPhase: widget.sendPhase,
          planTimelineCollapsed: widget.planTimelineCollapsed,
          onPlanTimelineCollapsedChanged: widget.onPlanTimelineCollapsedChanged,
          fileExplorerVisible: widget.fileExplorerVisible,
          onFileExplorerToggled: widget.onFileExplorerToggled,
        ),
        const SizedBox(height: 14),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: widget.onScrollNotification,
            child: ListView.builder(
              key: const ValueKey<String>('session-transcript-list'),
              controller: widget.controller,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.only(bottom: 12),
              // `ListView.builder` keeps already-built bubbles alive when
              // they scroll just outside the viewport (framework default).
              // We previously disabled this to limit memory; the cost of
              // re-parsing markdown / re-tokenising large code blocks on
              // every fling turned out to dominate scroll jank for long
              // sessions, so we now rely on the default keep-alive.
              // Repaint boundaries are essential for a message list: without
              // them a single bubble's internal animation (e.g. streaming
              // reasoning shimmer, tool-call progress) dirties the entire
              // visible window and repaints every neighbour on every frame,
              // which is the dominant source of first-paint jank when a
              // session has many tool-call / code-block bubbles.
              // (Leaving this at the framework default, which is already
              // `true`, keeps the call site lint-clean and the intent
              // explicit via the comment above.)
              // Slightly larger cache so quick scrolls reuse already-laid
              // out bubbles instead of rebuilding them from scratch; tuned
              // alongside `addAutomaticKeepAlives: true` above.
              cacheExtent: 800,
              physics: const OpenHandBouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              itemCount: listItemCount,
              itemBuilder: (context, index) {
                if (hiddenLoadMoreCount > 0 && index == 0) {
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: listItemCount == 1 ? 0 : 14,
                    ),
                    child: _TranscriptLoadEarlierButton(
                      hiddenMessageCount: hiddenMessageCount,
                      loading: _loadingOlderMessages,
                      onPressed: () {
                        widget.onRevealOlderMessages();
                        unawaited(_revealOlderMessages(displayMessages.length));
                      },
                    ),
                  );
                }
                final messageIndex = index - hiddenLoadMoreCount;
                if (messageIndex >= _renderEntries.length) {
                  final afterMessagesIndex =
                      messageIndex - _renderEntries.length;
                  if (afterMessagesIndex < pendingPlaceholderCount) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _PendingCreationPlaceholderCard(
                        request: pendingCreationRequest!,
                      ),
                    );
                  }
                  if (afterMessagesIndex <
                      pendingPlaceholderCount + failureCardCount) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _CreationFailureCard(
                        request: failedCreationRequest!,
                        error: userVisibleError!,
                        onDismiss: () async {
                          _dismissedErrorIds.add(userVisibleError.id);
                          setState(() {
                            if (_visibleErrorId == userVisibleError.id) {
                              _visibleErrorId = null;
                            }
                            if (_pendingPresentedErrorId ==
                                userVisibleError.id) {
                              _pendingPresentedErrorId = null;
                            }
                          });
                          await widget.onDismissError(userVisibleError);
                        },
                      ),
                    );
                  }
                  return _SessionErrorBanner(
                    error: userVisibleError!,
                    onDismiss: () async {
                      _dismissedErrorIds.add(userVisibleError.id);
                      setState(() {
                        if (_visibleErrorId == userVisibleError.id) {
                          _visibleErrorId = null;
                        }
                        if (_pendingPresentedErrorId == userVisibleError.id) {
                          _pendingPresentedErrorId = null;
                        }
                      });
                      await widget.onDismissError(userVisibleError);
                    },
                  );
                }
                final entry = _renderEntries[messageIndex];
                final message = entry.message;
                // Optional UI filter (independent of background learning):
                // the 'Show self-learning messages' setting hides these cards
                // in the transcript while keeping them persisted for audit.
                if (!showSelfLearningMessages &&
                    message.kind == AiSessionMessageKind.selfLearning) {
                  return const SizedBox.shrink();
                }
                final visibleMessageIndex = visibleMessageIndexById[message.id];
                final isSelected =
                    !entry.exiting && _selectedMessageId == message.id;
                final isLastVisibleMessage =
                    visibleMessageIndex != null &&
                    visibleMessageIndex == visibleMessages.length - 1;
                final hasLaterVisibleMessages =
                    visibleMessageIndex != null &&
                    visibleMessageIndex < visibleMessages.length - 1;
                return _TranscriptAnimatedMessageEntry(
                  key: ValueKey<String>('transcript-entry-${message.id}'),
                  entering: entry.entering,
                  exiting: entry.exiting,
                  bottomSpacing: messageIndex == _renderEntries.length - 1
                      ? 0
                      : 14,
                  onExitCompleted: () =>
                      _handleRenderEntryExitCompleted(message.id),
                  child: IgnorePointer(
                    ignoring: entry.exiting,
                    child: RepaintBoundary(
                      child: _MessageBubble(
                        key: ValueKey<String>(message.id),
                        message: message,
                        sessionTitle: session.title,
                        sessionEnvironment: session.environment,
                        showReasoningSweep:
                            !entry.exiting &&
                            widget.sendPhase == AiSendPhase.responding &&
                            _isStreamingReasoningMessage(message),
                        trackLayoutChanges:
                            !entry.exiting &&
                            _shouldTrackMessageLayout(
                              message: message,
                              sendPhase: widget.sendPhase,
                              isLastVisibleMessage: isLastVisibleMessage,
                            ),
                        onLayoutChanged: widget.onLayoutChanged,
                        isSelected: isSelected,
                        onSelect: () {
                          if (_selectedMessageId == message.id) {
                            return;
                          }
                          setState(() {
                            _selectedMessageId = message.id;
                          });
                        },
                        onDeselect: () {
                          if (_selectedMessageId != message.id) {
                            return;
                          }
                          setState(() {
                            _selectedMessageId = null;
                          });
                        },
                        onEdit:
                            !entry.exiting &&
                                message.kind == AiSessionMessageKind.user
                            ? () => widget.onEditMessage(message)
                            : null,
                        onCopy: () => widget.onCopyMessage(message),
                        onDelete: () async {
                          if (entry.exiting) {
                            return;
                          }
                          await _runDeleteAction(
                            message,
                            widget.onDeleteMessage,
                          );
                        },
                        onDeleteFromHere:
                            !entry.exiting && hasLaterVisibleMessages
                            ? () => _runDeleteAction(
                                message,
                                widget.onDeleteMessageFromHere,
                              )
                            : null,
                        onAudit: telemetryDebugEnabled
                            ? () {
                                _showMessageAuditDialog(
                                  context,
                                  message: message,
                                  session: session,
                                  controller: aiSessionController,
                                );
                              }
                            : null,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _TranscriptAnimatedMessageEntry extends StatefulWidget {
  const _TranscriptAnimatedMessageEntry({
    super.key,
    required this.entering,
    required this.exiting,
    required this.bottomSpacing,
    required this.onExitCompleted,
    required this.child,
  });

  final bool entering;
  final bool exiting;
  final double bottomSpacing;
  final VoidCallback onExitCompleted;
  final Widget child;

  @override
  State<_TranscriptAnimatedMessageEntry> createState() =>
      _TranscriptAnimatedMessageEntryState();
}

class _TranscriptAnimatedMessageEntryState
    extends State<_TranscriptAnimatedMessageEntry>
    with SingleTickerProviderStateMixin {
  static const _entranceDuration = Duration(milliseconds: 420);

  AnimationController? _entranceCtrl;
  Animation<double>? _opacity;
  Animation<double>? _scale;
  Animation<Offset>? _slide;

  @override
  void initState() {
    super.initState();
    if (widget.entering) {
      _entranceCtrl = AnimationController(
        duration: _entranceDuration,
        vsync: this,
      );
      _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _entranceCtrl!,
          curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
        ),
      );
      _scale = Tween<double>(begin: 0.94, end: 1.0).animate(
        CurvedAnimation(parent: _entranceCtrl!, curve: Curves.easeOutBack),
      );
      _slide = Tween<Offset>(begin: const Offset(0.0, 0.04), end: Offset.zero)
          .animate(
            CurvedAnimation(parent: _entranceCtrl!, curve: Curves.easeOutCubic),
          );
      // Tear down the entrance animation as soon as it finishes so the
      // ticker stops driving rebuilds for every still-mounted entry.
      // With long sessions (1k+ messages) and a `cacheExtent` that keeps
      // the most recently scrolled tiles alive, leaving the controller
      // ticking after the one-shot 420ms reveal contributes a measurable
      // baseline cost to subsequent frames.
      _entranceCtrl!.addStatusListener(_onEntranceStatus);
      _entranceCtrl!.forward();
    }
  }

  void _onEntranceStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) {
      return;
    }
    final ctrl = _entranceCtrl;
    if (ctrl == null) {
      return;
    }
    ctrl.removeStatusListener(_onEntranceStatus);
    ctrl.dispose();
    _entranceCtrl = null;
    _opacity = null;
    _scale = null;
    _slide = null;
    if (mounted) {
      // Switch to the static fast-path build that does not wrap with
      // FadeTransition/ScaleTransition/SlideTransition.
      setState(() {});
    }
  }

  @override
  void dispose() {
    _entranceCtrl?.removeStatusListener(_onEntranceStatus);
    _entranceCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = Padding(
      padding: EdgeInsets.only(bottom: widget.bottomSpacing),
      child: widget.child,
    );

    // Exit animation takes priority.
    if (widget.exiting) {
      return TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 1, end: 0),
        duration: _transcriptMessageDeleteAnimationDuration,
        curve: Curves.easeInOutCubic,
        onEnd: widget.onExitCompleted,
        builder: (context, value, child) {
          final clampedValue = value.clamp(0.0, 1.0);
          final exitProgress = 1 - clampedValue;
          return ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: clampedValue,
              child: Opacity(
                opacity: clampedValue,
                child: Transform.translate(
                  offset: Offset(
                    0,
                    -8 * Curves.easeOutCubic.transform(exitProgress),
                  ),
                  child: child,
                ),
              ),
            ),
          );
        },
        child: child,
      );
    }

    // Entrance animation (plays once on mount for newly added messages).
    if (_entranceCtrl != null) {
      return FadeTransition(
        opacity: _opacity!,
        child: ScaleTransition(
          scale: _scale!,
          alignment: Alignment.topCenter,
          child: SlideTransition(position: _slide!, child: child),
        ),
      );
    }

    // Fast path: no animation.
    return child;
  }
}

class _TranscriptLoadEarlierButton extends StatelessWidget {
  const _TranscriptLoadEarlierButton({
    required this.hiddenMessageCount,
    required this.loading,
    required this.onPressed,
  });

  final int hiddenMessageCount;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final label = _localizedText(
      context,
      zh: loading ? '加载更早消息中...' : '加载更早消息（$hiddenMessageCount）',
      en: loading
          ? 'Loading earlier messages...'
          : 'Load earlier messages ($hiddenMessageCount)',
    );
    return Center(
      child: OutlinedButton.icon(
        onPressed: loading ? null : onPressed,
        icon: loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.history_rounded, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.onSurface,
          side: BorderSide(color: colorScheme.outlineVariant),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }
}

class _SessionErrorBanner extends StatelessWidget {
  const _SessionErrorBanner({required this.error, required this.onDismiss});

  final AiSessionErrorRecord error;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final presentation = _presentSessionError(context, error);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  presentation.title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  presentation.message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onErrorContainer,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            key: ValueKey<String>('session-error-dismiss-${error.id}'),
            onPressed: onDismiss,
            tooltip: _localizedText(context, zh: '关闭提示', en: 'Dismiss'),
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: colorScheme.onErrorContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedSessionTitleText extends StatefulWidget {
  const _AnimatedSessionTitleText({required this.text, required this.style});

  final String text;
  final TextStyle? style;

  @override
  State<_AnimatedSessionTitleText> createState() =>
      _AnimatedSessionTitleTextState();
}

/// Pool of glyphs sampled during the scramble phase. Mixes Latin / digit /
/// CJK fragments so a Chinese title still looks like it is "decoding" rather
/// than briefly turning into a row of `XYZ`.
const String _kSessionTitleScramblePool =
    '①②③◆◇◎◉☆★✦✧✪✺❖✿❃❀❄❅❆⌘⌥⌦⏣⌬⎔⏃⏄⏅⏆⏇⏈⏉⏊⏋⏌⏍⏎⏏⏐⏑⏒⏓⏔⏕⏖⏗⏘⏙⏚⏛⏜⏝⏞⏟⏠⏡⏢';
const String _kSessionTitleScrambleAscii =
    'abcdefghijklmnopqrstuvwxyz0123456789#@*+~?<>/\\|';

class _AnimatedSessionTitleTextState extends State<_AnimatedSessionTitleText>
    with SingleTickerProviderStateMixin {
  // On initial mount we render a plain [Text] to avoid spinning up an
  // AnimationController for every sidebar tile when the list first paints.
  // Real animation only engages after the title actually changes (auto-title
  // generation, explicit rename, etc.), which is the scenario the user wants
  // to feel "magical".
  bool _animatedOnce = false;
  AnimationController? _controller;
  // Keeps the final settled glyphs so each repaint stays cheap once the
  // scramble phase has completed (no more setState ticks needed).
  String? _settledText;
  // Stable random salt per animation run so glyph noise doesn't visibly
  // flicker between adjacent frames in the same reveal.
  int _scrambleSalt = 0;

  @override
  void didUpdateWidget(covariant _AnimatedSessionTitleText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _animatedOnce = true;
      _settledText = null;
      _scrambleSalt = DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
      _controller ??= AnimationController(
        vsync: this,
        duration: _sessionTitleRevealAnimationDuration,
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() {
            _settledText = widget.text;
          });
        }
      });
      _controller!
        ..stop()
        ..forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_animatedOnce || _controller == null) {
      return Text(
        widget.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: widget.style,
      );
    }
    return AnimatedBuilder(
      animation: _controller!,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(
          _controller!.value.clamp(0.0, 1.0),
        );
        final settled = _settledText;
        final displayText = settled ?? _composeScrambledText(t);
        // Light scale + fade for a Q-bouncy reveal. ElasticOut overshoot
        // is intentionally gentle (1.04 → 1.0) to avoid layout jitter on
        // narrow sidebar tiles.
        final scale = 1.0 + (1.0 - t) * 0.06;
        final fade = (0.55 + 0.45 * t).clamp(0.0, 1.0);
        return Opacity(
          opacity: fade,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.centerLeft,
            child: Text(
              displayText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: widget.style,
            ),
          ),
        );
      },
    );
  }

  /// Builds an interpolated string where each codepoint of [widget.text] is
  /// either revealed (target glyph) or replaced by a random glyph from the
  /// scramble pool. Reveal order is left-to-right, lock-in time per index
  /// = `index / length` of the target, so longer titles still settle by the
  /// end of the animation while short ones snap quickly.
  String _composeScrambledText(double t) {
    final target = widget.text;
    if (target.isEmpty) {
      return '';
    }
    final runes = target.runes.toList(growable: false);
    final length = runes.length;
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      final revealAt = (i + 1) / length;
      // Each position locks in slightly before its proportional slot so the
      // last char doesn't dangle scrambled at t=0.99.
      if (t >= revealAt - 0.05) {
        buffer.writeCharCode(runes[i]);
        continue;
      }
      buffer.write(_glyphForScramble(i, t, runes[i]));
    }
    return buffer.toString();
  }

  String _glyphForScramble(int index, double t, int targetRune) {
    // Choose pool by target rune category so a CJK title scrambles with
    // CJK-compatible glyphs (avoid jarring Latin during a Chinese reveal).
    final pool = (targetRune >= 0x4E00 && targetRune <= 0x9FFF)
        ? _kSessionTitleScramblePool
        : _kSessionTitleScrambleAscii;
    // Cheap deterministic shuffle keyed by salt + index + frame band so the
    // glyph changes ~10 times per second without expensive Random.
    final frameBand = (t * 18).floor();
    final hash = (_scrambleSalt ^ (index * 2654435761) ^ (frameBand * 40503)) &
        0x7fffffff;
    final pick = hash % pool.length;
    return pool[pick];
  }
}

/// Resolves the creation request that should be shown as a pending placeholder
/// directly beneath the latest user message while the assistant works, or
/// surfaced as a failure card when generation finished with an error and the
/// assistant never managed to produce any visible content.
///
/// Returns null when no placeholder / failure card is needed: the latest user
/// message either was not a creation request, or the assistant has already
/// begun producing a visible response for the turn.
AiCreationRequest? _resolvePendingCreationPlaceholder({
  required AiSession session,
  required List<AiSessionMessage> visibleMessages,
  required AiSendPhase sendPhase,
  bool allowWhenIdle = false,
}) {
  if (sendPhase == AiSendPhase.idle && !allowWhenIdle) return null;
  if (visibleMessages.isEmpty) return null;
  // Walk backwards to find the most recent turn-opening user message.
  AiSessionMessage? latestUser;
  var assistantContentSeenAfterLatestUser = false;
  for (var i = visibleMessages.length - 1; i >= 0; i--) {
    final m = visibleMessages[i];
    if (m.kind == AiSessionMessageKind.user) {
      latestUser = m;
      break;
    }
    if (m.kind == AiSessionMessageKind.assistant &&
        m.content.trim().isNotEmpty) {
      assistantContentSeenAfterLatestUser = true;
    }
  }
  if (latestUser == null) return null;
  if (assistantContentSeenAfterLatestUser) return null;
  final request = AiCreationRequest.fromMetadata(
    latestUser.metadata[AiCreationRequest.metadataKey],
  );
  if (!request.isActive) return null;
  // Only show the animated placeholder for modes that produce visual/audio
  // artefacts; deep research replies as regular streamed text.
  if (request.mode == AiCreationMode.deepResearch) return null;
  return request;
}

/// Shimmering placeholder card shown beneath the user message while an image
/// (or video / audio) is being generated. Picks colours from the active theme
/// so it looks at home in both dark and light palettes.
class _PendingCreationPlaceholderCard extends StatefulWidget {
  const _PendingCreationPlaceholderCard({required this.request});

  final AiCreationRequest request;

  @override
  State<_PendingCreationPlaceholderCard> createState() =>
      _PendingCreationPlaceholderCardState();
}

class _PendingCreationPlaceholderCardState
    extends State<_PendingCreationPlaceholderCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    // Tune tones to the current theme so the sweep reads well everywhere.
    final baseColor = isDark
        ? cs.surfaceContainer
        : cs.surfaceContainerHighest.withValues(alpha: 0.6);
    final highlightColor = isDark ? cs.surfaceContainerHighest : cs.surface;
    final borderColor = cs.outlineVariant.withValues(
      alpha: isDark ? 0.25 : 0.18,
    );
    final (icon, labelZh, labelEn) = switch (widget.request.mode) {
      AiCreationMode.image => (
        Icons.image_outlined,
        '正在生成图片…',
        'Generating image…',
      ),
      AiCreationMode.video => (
        Icons.videocam_outlined,
        '正在生成视频…',
        'Generating video…',
      ),
      AiCreationMode.audio => (
        Icons.audiotrack_outlined,
        '正在生成音频…',
        'Generating audio…',
      ),
      AiCreationMode.deepResearch => (
        Icons.travel_explore_rounded,
        '正在深度研究…',
        'Researching…',
      ),
      AiCreationMode.none => (Icons.hourglass_bottom_rounded, '', ''),
    };
    final label = _localizedText(context, zh: labelZh, en: labelEn);
    return Align(
      alignment: Alignment.centerLeft,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          final t = _ctrl.value;
          return Container(
            width: 280,
            height: 220,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: borderColor),
              gradient: LinearGradient(
                begin: Alignment(-1.0 + 2.0 * t, -0.4),
                end: Alignment(-1.0 + 2.0 * t + 0.9, 0.4),
                colors: [baseColor, highlightColor, baseColor],
              ),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 40,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.55),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Failure card shown in place of the shimmer when a multimedia creation
/// request ended with an error without producing any assistant content.
/// Mirrors the user's chosen creation mode (image / video / audio) so the
/// failed turn stays visually coupled to the request, and surfaces the
/// underlying error message with a dismiss button.
class _CreationFailureCard extends StatelessWidget {
  const _CreationFailureCard({
    required this.request,
    required this.error,
    required this.onDismiss,
  });

  final AiCreationRequest request;
  final AiSessionErrorRecord error;
  final Future<void> Function() onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final presentation = _presentSessionError(context, error);
    final (icon, titleZh, titleEn) = switch (request.mode) {
      AiCreationMode.image => (
        Icons.broken_image_outlined,
        '图片生成失败',
        'Image generation failed',
      ),
      AiCreationMode.video => (
        Icons.videocam_off_outlined,
        '视频生成失败',
        'Video generation failed',
      ),
      AiCreationMode.audio => (
        Icons.music_off_outlined,
        '音频生成失败',
        'Audio generation failed',
      ),
      AiCreationMode.deepResearch => (
        Icons.travel_explore_rounded,
        '深度研究失败',
        'Deep research failed',
      ),
      AiCreationMode.none => (
        Icons.error_outline_rounded,
        '生成失败',
        'Generation failed',
      ),
    };
    final title = _localizedText(context, zh: titleZh, en: titleEn);
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
          decoration: BoxDecoration(
            color: cs.errorContainer.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: cs.error.withValues(alpha: 0.35)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 22, color: cs.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: cs.onErrorContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      presentation.message,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onErrorContainer,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                key: ValueKey<String>('creation-failure-dismiss-${error.id}'),
                onPressed: () => onDismiss(),
                tooltip: _localizedText(context, zh: '关闭', en: 'Dismiss'),
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: cs.onErrorContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
