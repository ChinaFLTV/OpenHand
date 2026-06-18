part of '../openhand_home_page.dart';

/// 阶段⑱：每个气泡的 BuildContext 注册到所属 transcript state 的局部
/// 映射中，避免使用 GlobalObjectKey。GlobalObjectKey 在被 retake 时会
/// 触发其 OverlayPortal 子节点（Tooltip）在 LayoutBuilder 重建期间向
/// RenderTheater 注册延迟子节点，跨布局子树的 mutation 会触发
/// `_RenderLayoutBuilder was mutated in performLayout` 断言。
/// 局部映射既保留了「按 messageId 反查 BuildContext」能力，又彻底
/// 规避了跨子树 GlobalKey retake 的副作用。
class _TranscriptBubbleRegistrar extends StatefulWidget {
  const _TranscriptBubbleRegistrar({
    required this.messageId,
    required this.registry,
    required this.child,
  });

  final String messageId;
  final _TranscriptBubbleRegistry registry;
  final Widget child;

  @override
  State<_TranscriptBubbleRegistrar> createState() =>
      _TranscriptBubbleRegistrarState();
}

class _TranscriptBubbleRegistrarState
    extends State<_TranscriptBubbleRegistrar> {
  @override
  void initState() {
    super.initState();
    widget.registry.bind(widget.messageId, context);
  }

  @override
  void didUpdateWidget(covariant _TranscriptBubbleRegistrar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messageId != widget.messageId ||
        oldWidget.registry != widget.registry) {
      oldWidget.registry.unbind(oldWidget.messageId, context);
      widget.registry.bind(widget.messageId, context);
    } else {
      // BuildContext 的同一 element 复用 → 无需重新绑定，但同步映射兜底。
      widget.registry.bind(widget.messageId, context);
    }
  }

  @override
  void dispose() {
    widget.registry.unbind(widget.messageId, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// transcript 内按 messageId 索引 BuildContext 的本地映射。
/// 仅在所属 `_SessionTranscriptState` 生命周期内存活，避免跨 transcript
/// 共享导致的脏状态。
class _TranscriptBubbleRegistry {
  final Map<String, BuildContext> _contexts = <String, BuildContext>{};

  void bind(String messageId, BuildContext context) {
    if (messageId.isEmpty) return;
    _contexts[messageId] = context;
  }

  void unbind(String messageId, BuildContext context) {
    if (messageId.isEmpty) return;
    final current = _contexts[messageId];
    if (identical(current, context)) {
      _contexts.remove(messageId);
    }
  }

  BuildContext? contextOf(String messageId) {
    final ctx = _contexts[messageId];
    if (ctx == null) return null;
    // 兜底：element 已被 deactivate 但还未 unbind 时，跳过返回。
    if (ctx is Element && !ctx.mounted) {
      _contexts.remove(messageId);
      return null;
    }
    return ctx;
  }

  void clear() => _contexts.clear();
}

class _TranscriptViewportAnchor {
  const _TranscriptViewportAnchor({
    required this.messageId,
    required this.viewportOffset,
  });

  final String messageId;
  final double viewportOffset;
}

/// 阶段⑰b：跨 widget 的「按 messageId 平滑滚动」分发器。
/// `_SessionTranscriptState` 在 init/dispose 时按 sessionId 注册自身；
/// 任意位置（汇总卡、跳转链接等）可调 `scrollToMessage(sessionId, msgId)`。
/// 若目标已离开视窗（`_windowStartIndex` 之前），会循环 reveal-older
/// 直到目标进入物化范围，再调 `Scrollable.ensureVisible` 丝滑落位。
class _TranscriptScrollDispatcher {
  _TranscriptScrollDispatcher._();
  static final _TranscriptScrollDispatcher instance =
      _TranscriptScrollDispatcher._();

  final Map<String, _SessionTranscriptState> _statesBySession =
      <String, _SessionTranscriptState>{};

  void register(String sessionId, _SessionTranscriptState state) {
    if (sessionId.isEmpty) return;
    _statesBySession[sessionId] = state;
  }

  void unregister(String sessionId, _SessionTranscriptState state) {
    if (_statesBySession[sessionId] == state) {
      _statesBySession.remove(sessionId);
    }
  }

  /// drip 串行 materialization 已下线，flushDripFor 无操作直接返回 false。
  bool flushDripFor(String sessionId) {
    return false;
  }

  void flushAllDrips() {
    // drip 串行 materialization 已下线，空实现。
  }

  Future<bool> scrollToMessage(
    String sessionId,
    String messageId, {
    bool highlight = false,
  }) async {
    // 等待目标会话的 transcript state 注册（最多 1 帧 + 250 ms）：
    // 防御性兜底，避免在 session 切换瞬间触发跳转时拿到 null state。
    var state = _statesBySession[sessionId];
    if (state == null) {
      await WidgetsBinding.instance.endOfFrame;
      state = _statesBySession[sessionId];
    }
    if (state == null) {
      final completer = Completer<void>();
      Timer? timeout;
      Timer? pollTimer;
      void check() {
        if (_statesBySession[sessionId] != null && !completer.isCompleted) {
          timeout?.cancel();
          pollTimer?.cancel();
          completer.complete();
        }
      }

      timeout = Timer(const Duration(milliseconds: 250), () {
        pollTimer?.cancel();
        if (!completer.isCompleted) completer.complete();
      });
      // 最多每帧探测一次直到超时 / 命中。
      pollTimer = startSafePeriodicTimer(
        kOpenHandFramePeriodicTimerInterval,
        (t) {
          if (completer.isCompleted) {
            t.cancel();
            return;
          }
          check();
        },
        min: kOpenHandFramePeriodicTimerInterval,
      );
      await completer.future;
      state = _statesBySession[sessionId];
    }
    if (state == null) return false;
    return state._scrollToMessageId(messageId, highlight: highlight);
  }
}

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
          activeProfile: activeProfile,
          claudeStyle: claudeStyle,
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
  const _TranscriptRenderEntry({required this.message});

  final AiSessionMessage message;
  final bool exiting = false;

  String get id => message.id;

  _TranscriptRenderEntry copyWith({AiSessionMessage? message}) {
    return _TranscriptRenderEntry(message: message ?? this.message);
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
    required this.onProgrammaticScrollCorrection,
    required this.onEditMessage,
    required this.onCopyMessage,
    required this.onDeleteMessage,
    required this.onDeleteMessageFromHere,
    required this.onForkMessage,
    required this.ttsPlaybackService,
    required this.translationService,
    required this.onDismissError,
    this.jumpToBottomOnInit = false,
    this.fileExplorerVisible = false,
    this.onFileExplorerToggled,
    this.activeProfile,
    this.claudeStyle = true,
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
  final void Function(VoidCallback correction) onProgrammaticScrollCorrection;
  final Future<void> Function(AiSessionMessage message) onEditMessage;
  final Future<void> Function(AiSessionMessage message) onCopyMessage;
  final Future<bool> Function(AiSessionMessage message) onDeleteMessage;
  final Future<bool> Function(AiSessionMessage message) onDeleteMessageFromHere;
  final Future<void> Function(AiSessionMessage message) onForkMessage;
  final AiTtsPlaybackService ttsPlaybackService;
  final AiTranslationService translationService;
  final Future<void> Function(AiSessionErrorRecord error) onDismissError;
  // When true, the list will jump to the very bottom on its first frame.
  // This eliminates the visible scroll-from-top animation that would otherwise
  // appear when a session is loaded and the parent schedules a forced scroll.
  final bool jumpToBottomOnInit;
  final bool fileExplorerVisible;
  final VoidCallback? onFileExplorerToggled;
  final AiModelProfile? activeProfile;
  final bool claudeStyle;

  @override
  State<_SessionTranscript> createState() => _SessionTranscriptState();
}

class _MessageTranslationEntry {
  const _MessageTranslationEntry({
    required this.sourceText,
    required this.settingsFingerprint,
    required this.translatedText,
    required this.provider,
  });

  final String sourceText;
  final String settingsFingerprint;
  final String translatedText;
  final AiTranslationProvider provider;
}

class _SessionTranscriptState extends State<_SessionTranscript> {
  String? _selectedMessageId;
  String? _highlightedMessageId;
  String? _visibleErrorId;
  String? _pendingPresentedErrorId;
  final Set<String> _dismissedErrorIds = <String>{};
  int _windowStartIndex = 0;
  bool _loadingOlderMessages = false;
  bool _initialMaterializationPending = false;
  bool _materializationTaskQueued = false;
  int _materializationGeneration = 0;
  List<_TranscriptRenderEntry> _renderEntries =
      const <_TranscriptRenderEntry>[];
  // F2 memoize: visibleMessages 的 id→index 映射在 build 路径上每帧重建一次，
  // 长会话下不便宜。displayMessages 是 AiSession 内部缓存（identity 稳定），
  // 因此可以用 (引用, windowStart, length) 作为缓存键。父级 watch 在流式
  // token 触发的 rebuild 中，若 displayMessages 引用未变（典型为非当前会话
  // 的旁路 rebuild），可直接复用上次映射。
  List<AiSessionMessage>? _cachedIndexMapSource;
  int _cachedIndexMapWindowStart = -1;
  Map<String, int>? _cachedVisibleIndexMap;
  // 2026-06-07：build 路径上的 _resolvePendingCreationPlaceholder 与
  // _resolveUserVisibleError 在长会话下分别会反向遍历 visibleMessages 与
  // recentErrors，O(N) per build。父级 watch 流式 token 触发的 rebuild
  // 中输入（visibleMessages、sendPhase、dismissedErrorIds 等）多数未
  // 变化时缓存命中可省掉两轮线性扫描。键由 (visibleMessages identity,
  // sendPhase, dismissedErrorIds size) 组成，identity 命中即复用。
  List<AiSessionMessage>? _cachedCreationRequestDisplaySource;
  int? _cachedCreationRequestWindowStart;
  AiSendPhase? _cachedCreationRequestSendPhase;
  bool? _cachedCreationRequestAllowWhenIdle;
  AiCreationRequest? _cachedCreationRequest;
  bool _cachedCreationRequestComputed = false;
  List<AiSessionErrorRecord>? _cachedUserVisibleErrorSource;
  int? _cachedUserVisibleErrorDismissedLength;
  String? _cachedUserVisibleErrorVisibleId;
  AiSessionErrorRecord? _cachedUserVisibleError;
  // 阶段⑱：transcript 内 messageId → BuildContext 反查映射，替代
  // GlobalObjectKey 防御 OverlayPortal/Tooltip 在 LayoutBuilder layout
  // 阶段被 retake 时跨子树 mutation RenderTheater 触发的断言失败。
  final _TranscriptBubbleRegistry _bubbleRegistry = _TranscriptBubbleRegistry();
  final Set<String> _animatedMessageIds = <String>{};
  int _messageActionPanelMotionKey = 0;
  int _consumedMessageActionPanelMotionKey = 0;
  // 2026-06-07: 保存每条消息的【显示原始】状态，避免 ListView.builder
  // 回收重建后状态丢失。
  final Map<String, bool> _rawContentVisibleByMessageId = <String, bool>{};
  final Map<String, _MessageTranslationEntry> _translationCacheByMessageId =
      <String, _MessageTranslationEntry>{};
  final Set<String> _translationVisibleMessageIds = <String>{};
  final Set<String> _translationLoadingMessageIds = <String>{};
  _TranscriptViewportAnchor? _pendingPrependAnchor;
  int _pendingPrependAnchorFrames = 0;
  bool _prependAnchorCorrectionQueued = false;
  TranscriptScrollActivity? _scrollActivity;
  _PendingRevealRestore? _pendingRevealRestore;

  ThemeData? _warmupTheme;
  SettingsController? _warmupSettings;
  bool _warmupDependenciesReady = false;
  final _FrameTaskScheduler _warmupScheduler = _FrameTaskScheduler(
    maxPerFrame: _transcriptWarmupMaxPerFrame,
  );
  int _warmupGeneration = 0;

  @override
  void initState() {
    super.initState();
    _syncWindowStartIndex(forceReset: true);
    _TranscriptScrollDispatcher.instance.register(widget.session.id, this);
    // First-open jank fix: when the user picks an existing thread for the
    // first time, the workspace pane and the transcript both mount in the
    // same frame. We materialise the visible window's render entries
    // immediately on this frame — they are pure data classes and the heavy
    // widget work (markdown parse / syntax highlight) is throttled to
    // ~1 task / frame by [_MarkdownFrameScheduler] + [_HighlightFrameScheduler].
    // Combined with `cacheExtent: 120` on the ListView (which only mounts
    // bubbles inside the actual viewport + ~120 px buffer), the heavy work
    // naturally spreads across post-mount frames without any drip wrapper.
    //
    // 首帧只取窗口底部几条消息，保证打开长会话时先落到最新内容；
    // 下一帧再补齐常规窗口，避免同步物化与外壳切换挤在同一帧。
    _replaceRenderEntries(
      _initialVisibleMessagesForFirstFrame(),
      animate: false,
    );
    _scheduleInitialMaterializationCompletionIfNeeded();
    _syncVisibleError();
    // Immediately jump to the bottom on the first rendered frame, before the
    // parent's postFrameCallback chain fires. This prevents the user from ever
    // seeing the list start at scroll-offset 0 while a forced scroll-to-bottom
    // is pending, which manifests as a jarring flash/jump animation.
    // 阶段㉓：单 shot jumpTo 在长会话首屏并不可靠 —— ListView.builder 在
    // markdown 异步解析期间会陆续完成 lazy layout，maxScrollExtent
    // 会在 mount 后 ~10 帧内持续增大；首帧 jump 之后视口虽然贴底，但
    // 第 N 个 bubble 解析完成、高度从纯文本占位扩张到富文本时，贴底
    // 状态会被打破而无法恢复（因为父级 settle 通常 8 帧内已耗尽）。
    // 线程会话窗口已下线所有 settle 循环（弹跳源头），首屏贴底由调用方
    // jumpToBottomOnInit 路径在 ListView 挂载后做单帧 jumpTo，不再走
    // 多帧 addPostFrameCallback 链 + lastAdjustedOffset 比较。
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _warmupTheme = Theme.of(context);
    _warmupSettings ??= context.read<SettingsController>();
    _warmupDependenciesReady = _warmupSettings != null;
    final activity = context.read<TranscriptScrollActivity>();
    if (identical(activity, _scrollActivity)) {
      _warmCurrentRenderEntriesIfReady();
      return;
    }
    _scrollActivity?.removeListener(_handleRevealScrollActivityChanged);
    _scrollActivity = activity;
    activity.addListener(_handleRevealScrollActivityChanged);
    _warmCurrentRenderEntriesIfReady();
  }

  @override
  void didUpdateWidget(covariant _SessionTranscript oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.id != widget.session.id) {
      _materializationGeneration += 1;
      _warmupGeneration += 1;
      _warmupScheduler.clear();
      _selectedMessageId = null;
      _translationCacheByMessageId.clear();
      _translationVisibleMessageIds.clear();
      _translationLoadingMessageIds.clear();
      _messageActionPanelMotionKey += 1;
      _consumedMessageActionPanelMotionKey = _messageActionPanelMotionKey;
      _TranscriptScrollDispatcher.instance.unregister(
        oldWidget.session.id,
        this,
      );
      _TranscriptScrollDispatcher.instance.register(widget.session.id, this);
      // Switching sessions used to rebuild the full transcript synchronously
      // inside `didUpdateWidget`, which on large sessions blocked the frame
      // that paints the new toolbar / shell. We reset to an empty list
      // immediately so the cross-fade can start, then materialise the
      // visible window on the next frame; the markdown / highlight work
      // is throttled by [_MarkdownFrameScheduler] / [_HighlightFrameScheduler]
      // and the ListView's `cacheExtent: 120` keeps off-viewport mounts cheap.
      // 切换会话时同样先绘制底部小窗口，再补齐常规窗口。
      _syncWindowStartIndex(forceReset: true);
      _renderEntries = const <_TranscriptRenderEntry>[];
      _initialMaterializationPending = false;
      _materializationTaskQueued = false;
      // 阶段㉓d：双兜底物化 — 在 mount 状态变化或父级帧抢占
      // `addPostFrameCallback` 时，仅 build 阶段 fallback 仍可能错过
      // 第一帧（同步赋值发生在 Element rebuild，但首帧是当前 frame
      // 之前已 schedule）。`endOfFrame` 在当前帧结束后再尝试一次，
      // 形成「post-frame → endOfFrame → build fallback」三重保险。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_renderEntries.isNotEmpty) return;
        setState(() {
          _replaceRenderEntries(
            _initialVisibleMessagesForFirstFrame(),
            animate: false,
          );
        });
        _scheduleInitialMaterializationCompletionIfNeeded();
      });
      WidgetsBinding.instance.endOfFrame.then((_) {
        if (!mounted) return;
        if (_renderEntries.isNotEmpty) return;
        setState(() {
          _replaceRenderEntries(
            _initialVisibleMessagesForFirstFrame(),
            animate: false,
          );
        });
        _scheduleInitialMaterializationCompletionIfNeeded();
      });
      // jumpToBottomOnInit 由父级 jumpTo 单独保证；这里不再做多帧 settle。
    } else if (oldWidget.session.messages != widget.session.messages ||
        oldWidget.session.updatedAt != widget.session.updatedAt) {
      final previousWindowStartIndex = _windowStartIndex;
      final prependedHistoricalMessages =
          oldWidget.session.messageLoadState ==
              AiSessionMessageLoadState.windowed &&
          widget.session.messageLoadState != AiSessionMessageLoadState.header &&
          widget.session.messageWindowStartIndex <
              oldWidget.session.messageWindowStartIndex;
      if (prependedHistoricalMessages) {
        final oldDisplayLength = oldWidget.session.displayMessages.length;
        final newDisplayLength = widget.session.displayMessages.length;
        final addedDisplayCount = math.max(
          0,
          newDisplayLength - oldDisplayLength,
        );
        _windowStartIndex = math.max(
          0,
          _windowStartIndex + addedDisplayCount - _transcriptWindowIncrement,
        );
      } else {
        _syncWindowStartIndex();
      }
      _syncRenderEntries(
        forceReset:
            previousWindowStartIndex != _windowStartIndex ||
            prependedHistoricalMessages,
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
    // 阶段⑧ — 避免为了“全量访问”多一份卷复制：窗口从 0 开始
    // 且无位限制时，直接返回底层 List 的不可变视图。
    if (clampedWindowStartIndex == 0) {
      return displayMessages;
    }
    return displayMessages.sublist(clampedWindowStartIndex);
  }

  List<AiSessionMessage> _initialVisibleMessagesForFirstFrame() {
    final visibleMessages = _visibleMessagesForWindow();
    final shouldStage =
        visibleMessages.length > _transcriptFirstFrameWindowSize &&
        widget.session.statistics.totalMessageCount >=
            _transcriptStagedMaterializationThreshold;
    _initialMaterializationPending = shouldStage;
    if (!shouldStage) {
      return visibleMessages;
    }
    return visibleMessages.sublist(
      visibleMessages.length - _transcriptFirstFrameWindowSize,
    );
  }

  void _scheduleInitialMaterializationCompletionIfNeeded() {
    if (!_initialMaterializationPending) {
      return;
    }
    _queueMaterializationCompletionStep();
  }

  void _queueMaterializationCompletionStep() {
    if (_materializationTaskQueued || !_initialMaterializationPending) {
      return;
    }
    _materializationTaskQueued = true;
    final generation = ++_materializationGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _materializationTaskQueued = false;
      if (!mounted ||
          !_initialMaterializationPending ||
          generation != _materializationGeneration) {
        return;
      }
      final allVisibleMessages = _visibleMessagesForWindow();
      if (allVisibleMessages.isEmpty) {
        setState(() {
          _initialMaterializationPending = false;
          _renderEntries = const <_TranscriptRenderEntry>[];
        });
        return;
      }
      final nextVisibleMessages = _nextMaterializedMessageBatch(
        allVisibleMessages,
      );
      if (nextVisibleMessages.length <= _renderEntries.length) {
        setState(() {
          _initialMaterializationPending = false;
          _replaceRenderEntries(allVisibleMessages, animate: false);
        });
        return;
      }
      setState(() {
        _initialMaterializationPending =
            nextVisibleMessages.length < allVisibleMessages.length;
        _replaceRenderEntries(nextVisibleMessages, animate: false);
      });
      if (_initialMaterializationPending) {
        _queueMaterializationCompletionStep();
      }
    });
  }

  List<AiSessionMessage> _nextMaterializedMessageBatch(
    List<AiSessionMessage> allVisibleMessages,
  ) {
    final currentCount = _renderEntries.length;
    if (currentCount <= 0) {
      return _initialVisibleMessagesForFirstFrame();
    }
    final targetCount = math.min(
      allVisibleMessages.length,
      currentCount + _transcriptWindowIncrement,
    );
    return allVisibleMessages.sublist(allVisibleMessages.length - targetCount);
  }

  void _replaceRenderEntries(
    List<AiSessionMessage> visibleMessages, {
    bool animate = true,
  }) {
    developer.Timeline.startSync(
      'openhand.session.materialize',
      arguments: <String, Object?>{'count': visibleMessages.length},
    );
    try {
      _scheduleWarmRichRenderEntries(visibleMessages);
      if (!animate) {
        _animatedMessageIds.addAll(
          visibleMessages.map((message) => message.id),
        );
      }
      _renderEntries = <_TranscriptRenderEntry>[
        for (final message in visibleMessages)
          _TranscriptRenderEntry(message: message),
      ];
    } finally {
      developer.Timeline.finishSync();
    }
  }

  void _warmCurrentRenderEntriesIfReady() {
    if (!_warmupDependenciesReady || _renderEntries.isEmpty) {
      return;
    }
    _scheduleWarmRichRenderEntries(
      _renderEntries.map((entry) => entry.message).toList(growable: false),
    );
  }

  void _scheduleWarmRichRenderEntries(List<AiSessionMessage> visibleMessages) {
    final theme = _warmupTheme;
    final settings = _warmupSettings;
    if (!_warmupDependenciesReady ||
        theme == null ||
        settings == null ||
        visibleMessages.isEmpty) {
      return;
    }
    final session = widget.session;
    final staged =
        _initialMaterializationPending &&
            visibleMessages.length <= _transcriptFirstFrameWindowSize
        ? _visibleMessagesForWindow()
        : visibleMessages;
    final warmCount = math.min(
      staged.length,
      math.max(_transcriptInitialWindowSize, _transcriptWindowIncrement),
    );
    final startIndex = math.max(0, staged.length - warmCount);
    final warmMessages = staged.sublist(startIndex);
    final generation = ++_warmupGeneration;
    _warmupScheduler.clear();
    for (final message in warmMessages) {
      _warmupScheduler.schedule(() {
        if (!mounted ||
            generation != _warmupGeneration ||
            widget.session.id != session.id) {
          return;
        }
        _warmRichRenderForMessage(
          session: session,
          message: message,
          theme: theme,
          settings: settings,
        );
      });
    }
  }

  void _warmRichRenderForMessage({
    required AiSession session,
    required AiSessionMessage message,
    required ThemeData theme,
    required SettingsController settings,
  }) {
    final kind = message.kind;
    final isUser = kind == AiSessionMessageKind.user;
    final isCompressionPoint = kind == AiSessionMessageKind.compressionPoint;
    final isReasoning = kind == AiSessionMessageKind.reasoning;
    final isStreamingReasoning = _isStreamingReasoningMessage(message);
    final isStreamingAssistant =
        kind == AiSessionMessageKind.assistant &&
        message.metadata[aiSessionMessageMetadataStreamingKey] == true;
    final isToolCall =
        kind == AiSessionMessageKind.toolCall ||
        kind == AiSessionMessageKind.hook;
    final isToolResult =
        kind == AiSessionMessageKind.tool ||
        kind == AiSessionMessageKind.mcp ||
        kind == AiSessionMessageKind.skill;
    final isStatus = kind == AiSessionMessageKind.status;
    final isSelfLearning = kind == AiSessionMessageKind.selfLearning;
    final isRoundFileMutationSummary =
        kind == AiSessionMessageKind.fileMutationSummary ||
        (isStatus && message.metadata['round_file_mutation_summary'] == true);
    if (isUser || isToolCall || isSelfLearning || isRoundFileMutationSummary) {
      return;
    }

    final colorScheme = theme.colorScheme;
    final backgroundColor = isCompressionPoint
        ? colorScheme.tertiaryContainer
        : isReasoning
        ? const Color(0xFF18181B)
        : isToolResult
        ? colorScheme.surfaceContainerHighest
        : isStatus
        ? colorScheme.surfaceContainer
        : colorScheme.surfaceContainerHigh;
    final textColor = isCompressionPoint
        ? colorScheme.onTertiaryContainer
        : isReasoning
        ? Colors.white
        : colorScheme.onSurface;
    final useDarkCodeSurface = isReasoning || isToolCall;
    final pathRoots = messageFilePathRoots(
      session.environment,
      workingDirectory: _toolExecutionWorkingDirectory(message),
    );
    final parseKey = pathRoots.join('|');
    final markdownThemeData = _MessageMarkdownThemeData.fromMessageBubble(
      theme: theme,
      backgroundColor: backgroundColor,
      textColor: textColor,
      useDarkCodeSurface: useDarkCodeSurface,
    );
    final inlineSyntaxes = <md.InlineSyntax>[
      _GeneratedMediaLinkSyntax.byExtension(pathRoots: pathRoots),
      _GeneratedMediaLinkSyntax.byGeneratedLabel(pathRoots: pathRoots),
      MessagePathCodeSyntax(candidateRoots: pathRoots),
      MessageFilePathSyntax(candidateRoots: pathRoots),
    ];
    final resolvedFormat = () {
      final storedKey = message.metadata[aiSessionMessageContentFormatKey];
      if (storedKey is String && storedKey.isNotEmpty) {
        return AiMessageContentFormat.fromStorageKey(storedKey);
      }
      return settings.aiMessageContentFormat;
    }();
    final heAnnotation = (!isCompressionPoint && !isToolResult && !isStatus)
        ? _parseHeAnnotation(message.content)
        : null;
    final effectiveContent = heAnnotation?.strippedContent ?? message.content;
    final normalizedContent = effectiveContent.isEmpty ? ' ' : effectiveContent;

    if (isCompressionPoint) {
      if (_messageShouldCollapse(
        normalizedContent,
        charThreshold: _messageMarkdownCollapseCharThreshold,
        lineThreshold: _messageMarkdownCollapseLineThreshold,
      )) {
        _warmMarkdownRenderPath(
          data: normalizedContent,
          parseKey: '$parseKey|compression-preview',
          inlineSyntaxes: inlineSyntaxes,
          theme: theme,
          textColor: textColor,
          useDarkCodeSurface: useDarkCodeSurface,
        );
      } else {
        _warmMarkdownRenderPath(
          data: normalizedContent,
          parseKey: parseKey,
          inlineSyntaxes: inlineSyntaxes,
          theme: theme,
          textColor: textColor,
          useDarkCodeSurface: useDarkCodeSurface,
        );
      }
      return;
    }

    if (isReasoning) {
      if (isStreamingReasoning) {
        return;
      }
      if (_shouldDefaultExpandReasoning(message)) {
        _warmMarkdownRenderPath(
          data: normalizedContent,
          parseKey: parseKey,
          inlineSyntaxes: inlineSyntaxes,
          theme: theme,
          textColor: textColor,
          useDarkCodeSurface: true,
        );
      } else {
        _warmMarkdownRenderPath(
          data: normalizedContent,
          parseKey: '$parseKey|reasoning-preview',
          inlineSyntaxes: inlineSyntaxes,
          theme: theme,
          textColor: textColor,
          useDarkCodeSurface: true,
        );
      }
      return;
    }

    if (isStreamingAssistant) {
      return;
    }

    final collapseCharThreshold = isToolResult
        ? _toolResultMarkdownCollapseCharThreshold
        : _messageMarkdownCollapseCharThreshold;
    final collapseLineThreshold = isToolResult
        ? _toolResultMarkdownCollapseLineThreshold
        : _messageMarkdownCollapseLineThreshold;
    final hasHtmlLikeTags = _looksLikeHtml(normalizedContent);
    final hasTagStructure =
        !hasHtmlLikeTags && _hasHtmlTagStructure(normalizedContent);
    final containsMarkdownFence =
        _startsWithFencedMermaidBlock(normalizedContent.trim()) ||
        _containsMarkdownCodeFence(normalizedContent.trim());

    void warmMarkdownBody() {
      final collapsed = _messageShouldCollapse(
        normalizedContent,
        charThreshold: collapseCharThreshold,
        lineThreshold: collapseLineThreshold,
      );
      _warmMarkdownRenderPath(
        data: normalizedContent,
        parseKey: collapsed ? '$parseKey|message-preview' : parseKey,
        inlineSyntaxes: inlineSyntaxes,
        theme: theme,
        textColor: textColor,
        useDarkCodeSurface: useDarkCodeSurface,
      );
    }

    switch (resolvedFormat) {
      case AiMessageContentFormat.plainText:
        return;
      case AiMessageContentFormat.html:
        if (hasHtmlLikeTags || hasTagStructure) {
          _warmHtmlBubbleMetrics(
            normalizedContent,
            markdownThemeData.styleSheet.p,
          );
          return;
        }
        if (settings.aiHtmlRenderFallback == AiHtmlRenderFallback.markdown) {
          warmMarkdownBody();
        }
        return;
      case AiMessageContentFormat.markdown:
        if (!containsMarkdownFence && (hasHtmlLikeTags || hasTagStructure)) {
          _warmHtmlBubbleMetrics(
            normalizedContent,
            markdownThemeData.styleSheet.p,
          );
          return;
        }
        warmMarkdownBody();
        return;
    }
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
      if (!hasExitingEntries && !hasAddedIds) {
        _renderEntries = <_TranscriptRenderEntry>[
          for (final entry in _renderEntries)
            entry.exiting
                ? entry
                : () {
                    final nextMessage = visibleMessagesById[entry.id];
                    if (nextMessage == null ||
                        identical(nextMessage, entry.message)) {
                      return entry;
                    }
                    return entry.copyWith(message: nextMessage);
                  }(),
        ];
        return;
      }
      if (!hasExitingEntries) {
        for (final message in visibleMessages) {
          if (!activeEntryIdSet.contains(message.id)) {
            _animatedMessageIds.remove(message.id);
          }
        }
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
      for (final message in visibleMessages) {
        if (!activeEntryIdSet.contains(message.id)) {
          _animatedMessageIds.remove(message.id);
        }
      }
      _replaceRenderEntries(visibleMessages);
      return;
    }
    _renderEntries = [
      for (final entry in _renderEntries)
        if (entry.exiting)
          entry
        else if (visibleMessagesById.containsKey(entry.id))
          entry.copyWith(message: visibleMessagesById[entry.id]),
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

  @override
  void dispose() {
    _scrollActivity?.removeListener(_handleRevealScrollActivityChanged);
    _scrollActivity = null;
    _materializationGeneration += 1;
    _warmupGeneration += 1;
    _warmupScheduler.clear();
    _TranscriptScrollDispatcher.instance.unregister(widget.session.id, this);
    _bubbleRegistry.clear();
    super.dispose();
  }

  /// 阶段⑰b：按 messageId 渐进式滚动到目标气泡。若已物化在视窗
  /// 或 cacheExtent 内则直接 `Scrollable.ensureVisible`；若目标
  /// 早于 `_windowStartIndex`（被「Load earlier」窗口剪掉），就
  /// 循环 reveal-older 一段一段把窗口往前推开，直到目标进入物化
  /// 范围再丝滑滚到 alignment=0.18。返回是否成功。
  ///
  /// 防抖：同一时刻只允许一次 in-flight 的滚动。重复点击在已有
  /// 任务进行时直接复用其 future，杜绝多次 reveal-older + ensureVisible
  /// 叠加导致的"上下抽搐"。
  Future<bool> _scrollToMessageId(String messageId, {bool highlight = false}) {
    final existing = _activeScrollFuture;
    if (existing != null && _activeScrollTargetId == messageId) {
      return existing;
    }
    final future = _runScrollToMessageId(messageId, highlight: highlight)
        .whenComplete(() {
          if (_activeScrollTargetId == messageId) {
            _activeScrollFuture = null;
            _activeScrollTargetId = null;
          }
        });
    _activeScrollFuture = future;
    _activeScrollTargetId = messageId;
    return future;
  }

  Future<bool> _runScrollToMessageId(
    String messageId, {
    bool highlight = false,
  }) async {
    if (!mounted) return false;
    void flashTarget() {
      if (!highlight || !mounted) return;
      setState(() => _highlightedMessageId = messageId);
    }

    Future<bool> tryEnsureVisible() async {
      final ctx = _bubbleRegistry.contextOf(messageId);
      if (ctx == null) return false;
      await Scrollable.ensureVisible(ctx, alignment: 0.18);
      flashTarget();
      return true;
    }

    // drip 串行 materialization 已下线，无需抑制并发 drip 冲突。
    if (await tryEnsureVisible()) return true;

    // 目标尚未物化。先看看它在 displayMessages 中是否存在 / 位置。
    final display = widget.session.displayMessages;
    final targetDisplayIndex = display.indexWhere((m) => m.id == messageId);
    if (targetDisplayIndex < 0) return false;

    // 反复 reveal-older 直到 _windowStartIndex 把目标囊括进来。
    var safety = math.max(
      32,
      (display.length / _transcriptWindowIncrement).ceil() + 2,
    );
    while (mounted && targetDisplayIndex < _windowStartIndex && safety-- > 0) {
      await _revealOlderMessages();
      await WidgetsBinding.instance.endOfFrame;
      if (await tryEnsureVisible()) return true;
    }
    if (await tryEnsureVisible()) return true;

    // 目标已落在 render entries 内，但 ListView.builder 因 cacheExtent 限制
    // 尚未构建对应 bubble（GlobalObjectKey.currentContext 为 null）。
    // 通过当前可见 bubble 估算平均高度 → 计算目标 index 的近似 offset →
    // 一次平滑 animateTo 把目标拉入 cacheExtent → 再 ensureVisible 精修。
    // 全程单段动画，杜绝多次 jumpTo / setState 引起的"上下抽搐"。
    final renderIndex = _renderEntries.indexWhere((e) => e.id == messageId);
    if (renderIndex < 0) return false;
    final scrollController = widget.controller;
    if (!scrollController.hasClients) return false;

    final approached = await _approachRenderIndexBySingleAnimation(
      renderIndex: renderIndex,
      duration: Duration.zero,
      curve: Curves.linear,
    );
    if (!mounted) return false;
    if (approached) {
      // animateTo 完成后等待一帧让 ListView.builder 物化新进入 cacheExtent
      // 的 bubble，注册其 GlobalObjectKey。
      await WidgetsBinding.instance.endOfFrame;
      if (await tryEnsureVisible()) return true;
      // 个别情况：估算偏差较大、目标仍未进入 cacheExtent。再做最多 3 次
      // 渐进逼近，每次步长减半。
      for (var attempt = 0; attempt < 3; attempt++) {
        if (!mounted || !scrollController.hasClients) return false;
        final stepped = await _approachRenderIndexBySingleAnimation(
          renderIndex: renderIndex,
          duration: Duration.zero,
          curve: Curves.linear,
        );
        if (!mounted) return false;
        if (!stepped) break;
        await WidgetsBinding.instance.endOfFrame;
        if (await tryEnsureVisible()) return true;
      }
    }
    return tryEnsureVisible();
  }

  /// 估算 [renderIndex] 对应 bubble 的近似滚动 offset，并一次性平滑
  /// `animateTo` 过去。使用当前已构建 bubble 的真实高度均值作为基准，
  /// 比硬编码"平均高度"更贴合实际内容。返回 true 表示有发起动画。
  Future<bool> _approachRenderIndexBySingleAnimation({
    required int renderIndex,
    required Duration duration,
    required Curve curve,
    double dampening = 1.0,
  }) async {
    final scrollController = widget.controller;
    if (!scrollController.hasClients) return false;
    final position = scrollController.position;
    final viewportExtent = position.viewportDimension;
    final maxExtent = position.maxScrollExtent;
    final currentOffset = position.pixels;

    // 收集已构建 bubble 的真实高度，估算每条平均高度，并取最近的
    // 一个已采样 bubble 作为锚点，计算目标 offset。
    var sampledTotalHeight = 0.0;
    var sampledCount = 0;
    int? anchorRenderIndex;
    double? anchorTopOffset;
    RenderBox? scrollableBox;
    for (var i = 0; i < _renderEntries.length; i++) {
      final id = _renderEntries[i].id;
      final bubbleContext = _bubbleRegistry.contextOf(id);
      if (bubbleContext == null) continue;
      final box = bubbleContext.findRenderObject() as RenderBox?;
      if (box == null || !box.attached || !box.hasSize) continue;
      sampledTotalHeight += box.size.height;
      sampledCount += 1;
      // 取 viewport 的 RenderBox（来自任一已渲染 bubble 的 Scrollable 祖先）。
      scrollableBox ??= () {
        final scrollable = Scrollable.maybeOf(bubbleContext);
        return scrollable?.context.findRenderObject() as RenderBox?;
      }();
      if (scrollableBox != null && scrollableBox.attached) {
        final localOffset = box.localToGlobal(
          Offset.zero,
          ancestor: scrollableBox,
        );
        final topOffset = currentOffset + localOffset.dy;
        // 选最接近 renderIndex 的锚点：误差最小，估算最准。
        if (anchorRenderIndex == null ||
            (i - renderIndex).abs() < (anchorRenderIndex - renderIndex).abs()) {
          anchorRenderIndex = i;
          anchorTopOffset = topOffset;
        }
      }
    }
    if (sampledCount == 0) return false;
    final avgHeight = sampledTotalHeight / sampledCount;
    const verticalGap = 14.0;
    final perEntry = avgHeight + verticalGap;

    double targetOffset;
    if (anchorRenderIndex != null && anchorTopOffset != null) {
      final delta = (renderIndex - anchorRenderIndex) * perEntry;
      targetOffset = anchorTopOffset + delta;
    } else {
      targetOffset = renderIndex * perEntry;
    }
    // 让目标位于视窗 18% 处，与 ensureVisible(alignment: 0.18) 对齐。
    targetOffset -= viewportExtent * 0.18;
    targetOffset = targetOffset.clamp(0.0, maxExtent);

    // dampening：渐进逼近时只走差距的一部分，避免一次性过冲。
    final rawDelta = targetOffset - currentOffset;
    if (rawDelta.abs() < 8.0) return false;
    final goal = (currentOffset + rawDelta * dampening).clamp(0.0, maxExtent);
    if ((goal - currentOffset).abs() < 8.0) return false;
    if (scrollController.positions.length > 1) return false;
    // 线程会话窗口已下线所有滚动动画（用户明确要求），统一用 jumpTo。
    scrollController.jumpTo(goal);
    return true;
  }

  Future<bool>? _activeScrollFuture;
  String? _activeScrollTargetId;

  /// 删除消息后无需回调 —— 顶层 _runDeleteAction 已直接从
  /// `widget.session.messages` 移除，watch 触发 _syncRenderEntries
  /// 重建本 list 时被自然剔除。保留空函数防止上游调用残留。

  int _initialWindowStartIndex(int messageCount) {
    if (messageCount <= _transcriptWindowingThreshold) {
      return 0;
    }
    return math.max(0, messageCount - _transcriptInitialWindowSize);
  }

  void _handleRevealScrollActivityChanged() {
    final activity = _scrollActivity;
    final pending = _pendingRevealRestore;
    if (!mounted || activity == null || pending == null || activity.value) {
      return;
    }
    if (!widget.controller.hasClients || widget.controller.positions.isEmpty) {
      return;
    }
    final position = widget.controller.positions.last;
    if (position.isScrollingNotifier.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _handleRevealScrollActivityChanged();
        }
      });
      return;
    }
    final target = pending.targetPixels.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _pendingRevealRestore = null;
    if ((target - position.pixels).abs() <
        _transcriptPrependAnchorMinCorrection) {
      return;
    }
    widget.onProgrammaticScrollCorrection(() => position.jumpTo(target));
  }

  Future<void> _toggleMessageTranslation(
    AiSessionMessage message,
    AiTranslationSettings settings,
  ) async {
    final sourceText = _translatableMessageText(message, settings);
    if (sourceText == null) return;
    if (_translationVisibleMessageIds.contains(message.id)) {
      setState(() {
        _translationVisibleMessageIds.remove(message.id);
      });
      return;
    }
    final cached = _translationCacheByMessageId[message.id];
    if (cached != null &&
        cached.sourceText == sourceText &&
        cached.settingsFingerprint == settings.cacheFingerprint) {
      setState(() {
        _translationVisibleMessageIds.add(message.id);
      });
      return;
    }
    if (_translationLoadingMessageIds.contains(message.id)) return;
    setState(() {
      _translationLoadingMessageIds.add(message.id);
    });
    try {
      final settingsController = context.read<SettingsController>();
      final result = await widget.translationService.translate(
        text: sourceText,
        settings: settings,
        availableModels: settingsController.aiModels,
        fallbackModel: _translationFallbackModel(settingsController),
      );
      if (!mounted) return;
      setState(() {
        _translationCacheByMessageId[message.id] = _MessageTranslationEntry(
          sourceText: sourceText,
          settingsFingerprint: settings.cacheFingerprint,
          translatedText: result.text,
          provider: result.provider,
        );
        _translationVisibleMessageIds.add(message.id);
      });
    } catch (error) {
      if (!mounted) return;
      _showHomeSnackBar(
        context,
        SnackBar(
          content: Text(
            _localizedText(
              context,
              zh: '翻译失败：${_friendlyTranslationUiError(error)}',
              en: 'Translation failed: ${_friendlyTranslationUiError(error)}',
            ),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _translationLoadingMessageIds.remove(message.id);
        });
      }
    }
  }

  AiModelConfig? _translationFallbackModel(SettingsController settings) {
    final storedProviderId = widget.session.lastUsedModelId?.trim();
    final storedModelId = widget.session.lastUsedModelLabel?.trim();
    if (storedProviderId != null &&
        storedProviderId.isNotEmpty &&
        storedModelId != null &&
        storedModelId.isNotEmpty) {
      for (final item in settings.aiModels) {
        if (item.id == storedProviderId &&
            item.allModelIds.contains(storedModelId)) {
          return item.copyWith(modelId: storedModelId);
        }
      }
    }
    return settings.selectedAiModel;
  }

  bool _isMessageTranslatable(
    AiSessionMessage message,
    SettingsController settings,
  ) {
    if (message.metadata[aiSessionMessageMetadataStreamingKey] == true) {
      return false;
    }
    if (_translatableMessageText(message, settings.aiTranslationSettings) ==
        null) {
      return false;
    }
    switch (message.kind) {
      case AiSessionMessageKind.user:
      case AiSessionMessageKind.reasoning:
        return true;
      case AiSessionMessageKind.assistant:
        return _messageContentFormat(message, settings) !=
            AiMessageContentFormat.html;
      case AiSessionMessageKind.toolCall:
      case AiSessionMessageKind.tool:
      case AiSessionMessageKind.compressionPoint:
      case AiSessionMessageKind.mcp:
      case AiSessionMessageKind.skill:
      case AiSessionMessageKind.hook:
      case AiSessionMessageKind.selfLearning:
      case AiSessionMessageKind.fileMutationSummary:
      case AiSessionMessageKind.status:
        return false;
    }
  }

  String? _translatableMessageText(
    AiSessionMessage message,
    AiTranslationSettings settings,
  ) {
    if (!settings.enabled) return null;
    final content = switch (message.kind) {
      AiSessionMessageKind.assistant =>
        _parseHeAnnotation(message.content)?.strippedContent ?? message.content,
      AiSessionMessageKind.user ||
      AiSessionMessageKind.reasoning => message.content,
      _ => '',
    }.trim();
    return content.isEmpty ? null : content;
  }

  AiMessageContentFormat _messageContentFormat(
    AiSessionMessage message,
    SettingsController settings,
  ) {
    final storedKey = message.metadata[aiSessionMessageContentFormatKey];
    if (storedKey is String && storedKey.isNotEmpty) {
      return AiMessageContentFormat.fromStorageKey(storedKey);
    }
    return settings.aiMessageContentFormat;
  }

  String _friendlyTranslationUiError(Object error) {
    final raw = error.toString().replaceFirst(RegExp(r'^[^:]+:\s*'), '');
    final normalized = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return 'unknown error';
    const maxLength = 140;
    if (normalized.length <= maxLength) return normalized;
    return '${normalized.substring(0, maxLength)}...';
  }

  Future<void> _revealOlderMessages() async {
    if (_loadingOlderMessages ||
        (_windowStartIndex <= 0 && !widget.session.hasMoreHistoricalMessages)) {
      return;
    }

    // Remember current scroll metrics so we can restore visual position later.
    final scrollController = widget.controller;
    final hadClients = scrollController.hasClients;
    final hiddenBefore =
        widget.session.hiddenHistoricalMessageCount + _windowStartIndex;
    final previousPixels = hadClients ? scrollController.position.pixels : 0.0;
    final currentMaxExtent = hadClients
        ? scrollController.position.maxScrollExtent
        : 0.0;
    final anchor = _capturePrependAnchor();
    final preserveTriggerOffset = hiddenBefore > 0;
    setState(() {
      _loadingOlderMessages = true;
    });

    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!mounted) {
      return;
    }

    if (_windowStartIndex > 0) {
      setState(() {
        _windowStartIndex = math.max(
          0,
          _windowStartIndex - _transcriptWindowIncrement,
        );
        _replaceRenderEntries(_visibleMessagesForWindow(), animate: false);
        _loadingOlderMessages = false;
      });
    } else {
      await context.read<AiSessionController>().loadOlderSessionMessages(
        widget.session.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingOlderMessages = false;
      });
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      return;
    }

    if (preserveTriggerOffset && hadClients) {
      final position = scrollController.positions.isNotEmpty
          ? scrollController.positions.last
          : null;
      final scrollActive = context.read<TranscriptScrollActivity>().value;
      if (position != null &&
          !scrollActive &&
          !position.isScrollingNotifier.value) {
        final target = previousPixels.clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        if ((target - position.pixels).abs() >=
            _transcriptPrependAnchorMinCorrection) {
          widget.onProgrammaticScrollCorrection(() => position.jumpTo(target));
        }
      } else {
        _pendingRevealRestore = position == null
            ? null
            : _PendingRevealRestore(targetPixels: previousPixels);
        if (_pendingRevealRestore != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _handleRevealScrollActivityChanged();
            }
          });
        }
      }
      return;
    }

    final restoredByAnchor = anchor != null && _restorePrependAnchor(anchor);
    if (anchor != null) {
      _startPrependAnchorStabilization(anchor);
    }

    // 锚点不可用时，用 maxScrollExtent 差值兜底保持旧视觉位置。
    if (!restoredByAnchor && hadClients) {
      final position = scrollController.positions.isNotEmpty
          ? scrollController.positions.last
          : null;
      if (position != null) {
        final newMaxExtent = position.maxScrollExtent;
        final delta = newMaxExtent - currentMaxExtent;
        if (delta > 0) {
          final target = (position.pixels + delta).clamp(
            position.minScrollExtent,
            newMaxExtent,
          );
          widget.onProgrammaticScrollCorrection(() => position.jumpTo(target));
        }
      }
    }
  }

  _TranscriptViewportAnchor? _capturePrependAnchor() {
    if (!widget.controller.hasClients) return null;
    final viewportExtent = widget.controller.position.viewportDimension;
    _TranscriptViewportAnchor? best;
    var bestRank = double.infinity;
    for (final entry in _renderEntries) {
      if (entry.exiting) continue;
      final offset = _viewportOffsetForMessage(entry.id);
      if (offset == null) continue;
      final ctx = _bubbleRegistry.contextOf(entry.id);
      final box = ctx?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached || !box.hasSize) continue;
      final bottom = offset + box.size.height;
      if (bottom <= 0 || offset >= viewportExtent) continue;
      final rank = offset >= 0 ? offset : viewportExtent + offset.abs();
      if (rank < bestRank) {
        bestRank = rank;
        best = _TranscriptViewportAnchor(
          messageId: entry.id,
          viewportOffset: offset,
        );
      }
    }
    return best;
  }

  double? _viewportOffsetForMessage(String messageId) {
    final ctx = _bubbleRegistry.contextOf(messageId);
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return null;
    final scrollable = Scrollable.maybeOf(ctx);
    final scrollableBox = scrollable?.context.findRenderObject() as RenderBox?;
    if (scrollableBox == null ||
        !scrollableBox.attached ||
        !scrollableBox.hasSize) {
      return null;
    }
    return box.localToGlobal(Offset.zero, ancestor: scrollableBox).dy;
  }

  bool _restorePrependAnchor(_TranscriptViewportAnchor anchor) {
    if (!widget.controller.hasClients) return false;
    final currentOffset = _viewportOffsetForMessage(anchor.messageId);
    if (currentOffset == null) return false;
    final delta = currentOffset - anchor.viewportOffset;
    if (delta.abs() < _transcriptPrependAnchorMinCorrection) {
      return false;
    }
    widget.onProgrammaticScrollCorrection(() {
      if (!mounted || !widget.controller.hasClients) return;
      final position = widget.controller.position;
      final target = (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((target - position.pixels).abs() <
          _transcriptPrependAnchorMinCorrection) {
        return;
      }
      position.jumpTo(target);
    });
    return true;
  }

  void _startPrependAnchorStabilization(_TranscriptViewportAnchor anchor) {
    _pendingPrependAnchor = anchor;
    _pendingPrependAnchorFrames = _transcriptPrependAnchorSettleFrameCount;
    _queuePrependAnchorCorrection();
  }

  void _queuePrependAnchorCorrection() {
    if (_prependAnchorCorrectionQueued ||
        _pendingPrependAnchor == null ||
        _pendingPrependAnchorFrames <= 0) {
      return;
    }
    _prependAnchorCorrectionQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prependAnchorCorrectionQueued = false;
      if (!mounted) return;
      final anchor = _pendingPrependAnchor;
      if (anchor == null || _pendingPrependAnchorFrames <= 0) {
        return;
      }
      if (context.read<TranscriptScrollActivity>().value) {
        _pendingPrependAnchor = null;
        _pendingPrependAnchorFrames = 0;
        return;
      }
      _restorePrependAnchor(anchor);
      _pendingPrependAnchorFrames -= 1;
      if (_pendingPrependAnchorFrames > 0) {
        _queuePrependAnchorCorrection();
      } else {
        _pendingPrependAnchor = null;
      }
    });
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

  /// 2026-06-07：build 路径上 memoize。按 (session.recentErrors 引用,
  /// _dismissedErrorIds 大小, _visibleErrorId) 命中复用：recentErrors 引用
  /// 未变（多数父级 rebuild 不会替换 recentErrors）+ dismissedErrorIds 大小
  /// 未变 + _visibleErrorId 未变即视为输入相同，避免每次 build 都对
  /// recentErrors 做两次线性扫描。
  AiSessionErrorRecord? _resolveUserVisibleErrorCached(AiSession session) {
    final errors = session.recentErrors;
    if (identical(_cachedUserVisibleErrorSource, errors) &&
        _cachedUserVisibleErrorDismissedLength == _dismissedErrorIds.length &&
        _cachedUserVisibleErrorVisibleId == _visibleErrorId &&
        _cachedUserVisibleError != null) {
      // 缓存可能持有「已被新增 dismiss 屏蔽」的 error —— 防御性兜底。
      final cached = _cachedUserVisibleError!;
      if (!_dismissedErrorIds.contains(cached.id)) {
        return cached;
      }
    }
    final result = _resolveUserVisibleError(session);
    _cachedUserVisibleErrorSource = errors;
    _cachedUserVisibleErrorDismissedLength = _dismissedErrorIds.length;
    _cachedUserVisibleErrorVisibleId = _visibleErrorId;
    _cachedUserVisibleError = result;
    return result;
  }

  /// 2026-06-07：build 路径上 memoize。visibleMessages 是 sublist 视图，
  /// 每次 build 都创建新 List 引用，单纯按引用比对无法命中。改用
  /// (displayMessages 引用, windowStart) 作 key 命中，sendPhase 与
  /// allowWhenIdle 作为旁路条件，避免每次 build 都反向遍历
  /// visibleMessages 找最新 user message + 检 assistant 是否已有内容。
  AiCreationRequest? _resolvePendingCreationPlaceholderCached({
    required AiSession session,
    required List<AiSessionMessage> displayMessages,
    required int windowStart,
    required AiSendPhase sendPhase,
    required bool allowWhenIdle,
  }) {
    if (_cachedCreationRequestComputed &&
        identical(_cachedCreationRequestDisplaySource, displayMessages) &&
        _cachedCreationRequestWindowStart == windowStart &&
        _cachedCreationRequestSendPhase == sendPhase &&
        _cachedCreationRequestAllowWhenIdle == allowWhenIdle) {
      return _cachedCreationRequest;
    }
    // 复用原函数的反向遍历逻辑，但传实际 visibleMessages 切片以保持
    // 语义不变（不会跨越 windowStart 之前的 hidden 消息）。
    final clampedWindowStart = windowStart
        .clamp(0, displayMessages.length)
        .toInt();
    final visibleMessages = displayMessages.sublist(clampedWindowStart);
    final result = _resolvePendingCreationPlaceholder(
      session: session,
      visibleMessages: visibleMessages,
      sendPhase: sendPhase,
      allowWhenIdle: allowWhenIdle,
    );
    _cachedCreationRequestDisplaySource = displayMessages;
    _cachedCreationRequestWindowStart = clampedWindowStart;
    _cachedCreationRequestSendPhase = sendPhase;
    _cachedCreationRequestAllowWhenIdle = allowWhenIdle;
    _cachedCreationRequest = result;
    _cachedCreationRequestComputed = true;
    return result;
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
    final ttsSettings = context.select<SettingsController, AiTtsSettings>(
      (settings) => settings.aiTtsSettings,
    );
    final translationSettings = context
        .select<SettingsController, AiTranslationSettings>(
          (settings) => settings.aiTranslationSettings,
        );
    final aiSessionController = context.read<AiSessionController>();
    final settingsController = context.read<SettingsController>();
    final clampedWindowStartIndex = _windowStartIndex
        .clamp(0, displayMessages.length)
        .toInt();
    final hiddenMessageCount =
        session.hiddenHistoricalMessageCount + clampedWindowStartIndex;
    final visibleMessages = displayMessages.sublist(clampedWindowStartIndex);
    // 阶段㉓d build-stage 同步首屏 fallback —
    // 当 didUpdateWidget 把 `_renderEntries` 重置为空、且 post-frame
    // callback 因 mount 抖动尚未触发时，直接同步物化首屏，避免
    // 「displayMessages 非空 → empty short-circuit」连续 K 帧白屏。
    // 注意：build 中不允许 setState，但 _replaceRenderEntries 仅做
    // 字段赋值（与 didUpdateWidget 内的同名调用一致），赋值后
    // 当前帧即拿到新 `_renderEntries` 用于绘制，不破坏 build 不变量。
    if (_renderEntries.isEmpty && visibleMessages.isNotEmpty) {
      _replaceRenderEntries(
        _initialVisibleMessagesForFirstFrame(),
        animate: false,
      );
      _scheduleInitialMaterializationCompletionIfNeeded();
    }
    if (_renderEntries.isEmpty && visibleMessages.isEmpty) {
      // Header-only 会话正在按需水合消息时，显示加载占位而非空会话。
      if (aiSessionController.isSessionMessagesHydrating(session.id)) {
        return _TranscriptHydratingPlaceholder(
          key: ValueKey<String>('hydrating-transcript-${session.id}'),
        );
      }
      return _WorkspaceEmptyState(
        key: ValueKey<String>('empty-session-transcript-${session.id}'),
        session: session,
      );
    }
    // F2 memoize: 同一 displayMessages 引用 + 同一 windowStart 复用上次结果，
    // 避免长会话每帧 O(N) 重建。
    Map<String, int> visibleMessageIndexById;
    if (identical(_cachedIndexMapSource, displayMessages) &&
        _cachedIndexMapWindowStart == clampedWindowStartIndex &&
        _cachedVisibleIndexMap != null &&
        _cachedVisibleIndexMap!.length == visibleMessages.length) {
      visibleMessageIndexById = _cachedVisibleIndexMap!;
    } else {
      visibleMessageIndexById = <String, int>{
        for (var index = 0; index < visibleMessages.length; index++)
          visibleMessages[index].id: index,
      };
      _cachedIndexMapSource = displayMessages;
      _cachedIndexMapWindowStart = clampedWindowStartIndex;
      _cachedVisibleIndexMap = visibleMessageIndexById;
    }
    final userVisibleError = _resolveUserVisibleErrorCached(session);
    if (_renderEntries.isEmpty &&
        visibleMessages.isEmpty &&
        userVisibleError == null) {
      if (aiSessionController.isMessagesHydrating) {
        return _TranscriptHydratingPlaceholder(
          key: ValueKey<String>('hydrating-transcript-${session.id}'),
        );
      }
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
    final pendingCreationRequest = _resolvePendingCreationPlaceholderCached(
      session: session,
      displayMessages: displayMessages,
      windowStart: clampedWindowStartIndex,
      sendPhase: widget.sendPhase,
      allowWhenIdle: false,
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
        ? _resolvePendingCreationPlaceholderCached(
            session: session,
            displayMessages: displayMessages,
            windowStart: clampedWindowStartIndex,
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
    final transcriptScrollActive = context
        .select<TranscriptScrollActivity, bool>((activity) => activity.value);
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
          activeProfile: widget.activeProfile,
          claudeStyle: widget.claudeStyle,
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ValueListenableBuilder<AiTtsPlaybackSnapshot>(
            valueListenable: widget.ttsPlaybackService.state,
            builder: (context, ttsSnapshot, _) {
              if (!ttsSettings.enabled && ttsSnapshot.playing) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  unawaited(widget.ttsPlaybackService.stop());
                });
              }
              return NotificationListener<ScrollNotification>(
                onNotification: widget.onScrollNotification,
                child: ListView.builder(
                  key: const ValueKey<String>('session-transcript-list'),
                  controller: widget.controller,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
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
                  // Keep the cache band narrow on first open. Extra cached
                  // bubbles still pay wrapper/layout cost even when markdown and
                  // highlighting are deferred, so the initial window should track
                  // the real viewport closely and expand as the user scrolls.
                  cacheExtent: _transcriptListCacheExtent,
                  physics: kOpenHandClampingPhysics,
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
                            unawaited(_revealOlderMessages());
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
                          child: TweenAnimationBuilder<double>(
                            tween: Tween<double>(begin: 0, end: 1),
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 360),
                            curve: Curves.easeOutBack,
                            builder: (_, t, child) {
                              final clamped = t.clamp(0.0, 1.0);
                              return Opacity(
                                opacity: clamped,
                                child: Transform.translate(
                                  offset: Offset(0, (1 - clamped) * -8),
                                  child: Transform.scale(
                                    scale: 0.94 + 0.06 * clamped,
                                    child: child,
                                  ),
                                ),
                              );
                            },
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
                            if (_pendingPresentedErrorId ==
                                userVisibleError.id) {
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
                    final visibleMessageIndex =
                        visibleMessageIndexById[message.id];
                    final isSelected =
                        !entry.exiting && _selectedMessageId == message.id;
                    final isLastVisibleMessage =
                        visibleMessageIndex != null &&
                        visibleMessageIndex == visibleMessages.length - 1;
                    final hasLaterVisibleMessages =
                        visibleMessageIndex != null &&
                        visibleMessageIndex < visibleMessages.length - 1;
                    final shouldAnimateAppearance =
                        !entry.exiting &&
                        widget.sendPhase != AiSendPhase.idle &&
                        isLastVisibleMessage &&
                        !_animatedMessageIds.contains(message.id);
                    final speechPlaying =
                        ttsSettings.enabled &&
                        ttsSnapshot.playing &&
                        ttsSnapshot.messageId == message.id;
                    final translationEntry =
                        _translationCacheByMessageId[message.id];
                    final translationVisible =
                        translationEntry != null &&
                        _translationVisibleMessageIds.contains(message.id) &&
                        translationEntry.sourceText ==
                            _translatableMessageText(
                              message,
                              translationSettings,
                            ) &&
                        translationEntry.settingsFingerprint ==
                            translationSettings.cacheFingerprint;
                    final translationLoading = _translationLoadingMessageIds
                        .contains(message.id);
                    final translationEnabled =
                        translationSettings.enabled &&
                        _isMessageTranslatable(message, settingsController);
                    final bubble = _TranscriptBubbleRegistrar(
                      messageId: message.id,
                      registry: _bubbleRegistry,
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
                        transcriptScrollActive: transcriptScrollActive,
                        isSelected: isSelected,
                        actionPanelEntranceMotionKey:
                            _messageActionPanelMotionKey,
                        animateActionPanelEntrance:
                            isSelected &&
                            _consumedMessageActionPanelMotionKey !=
                                _messageActionPanelMotionKey,
                        onActionPanelEntranceConsumed: (motionKey) {
                          if (!mounted ||
                              motionKey != _messageActionPanelMotionKey ||
                              _consumedMessageActionPanelMotionKey ==
                                  motionKey) {
                            return;
                          }
                          _consumedMessageActionPanelMotionKey = motionKey;
                        },
                        isScrollHighlighted:
                            _highlightedMessageId == message.id,
                        onSelect: () {
                          if (_selectedMessageId == message.id) {
                            return;
                          }
                          setState(() {
                            _selectedMessageId = message.id;
                            _messageActionPanelMotionKey += 1;
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
                        onFork: () => widget.onForkMessage(message),
                        speechEnabled: ttsSettings.enabled,
                        speechPlaying: speechPlaying,
                        onToggleSpeech: ttsSettings.enabled
                            ? () => widget.ttsPlaybackService.toggleMessage(
                                messageId: message.id,
                                text: message.content,
                                settings: ttsSettings,
                              )
                            : null,
                        translationEnabled: translationEnabled,
                        translationLoading: translationLoading,
                        translationVisible: translationVisible,
                        translatedContent: translationEntry?.translatedText,
                        onToggleTranslation: translationEnabled
                            ? () => _toggleMessageTranslation(
                                message,
                                translationSettings,
                              )
                            : null,
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
                                  claudeStyle: widget.claudeStyle,
                                );
                              }
                            : null,
                        initiallyShowRawContent:
                            _rawContentVisibleByMessageId[message.id] ?? false,
                        onShowRawContentChanged: (visible) {
                          _rawContentVisibleByMessageId[message.id] = visible;
                        },
                      ),
                    );
                    final content = shouldAnimateAppearance
                        ? SettingsAwareAppearOnce(
                            child: Builder(
                              builder: (context) {
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  _animatedMessageIds.add(message.id);
                                });
                                return bubble;
                              },
                            ),
                          )
                        : bubble;
                    final entrySizeDuration =
                        isSelected && !transcriptScrollActive
                        ? cardMotionDurationFor(context, expanding: true)
                        : Duration.zero;
                    return maybeAnimatedSize(
                      key: ValueKey<String>('transcript-entry-${message.id}'),
                      duration: entrySizeDuration,
                      curve: kCardMotionCurve,
                      alignment: isSelected
                          ? Alignment.topLeft
                          : Alignment.bottomLeft,
                      child: Padding(
                        padding: EdgeInsets.only(
                          bottom: messageIndex == _renderEntries.length - 1
                              ? 0
                              : 14,
                        ),
                        child: content,
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PendingRevealRestore {
  const _PendingRevealRestore({required this.targetPixels});

  final double targetPixels;
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

class _TranscriptHydratingPlaceholder extends StatelessWidget {
  const _TranscriptHydratingPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final label = _localizedText(
      context,
      zh: '加载消息中…',
      en: 'Loading messages…',
    );
    final body = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation<Color>(
                colorScheme.primary.withValues(alpha: 0.85),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
    if (reduceMotion) {
      return body;
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1.0 - value) * 6.0),
            child: child,
          ),
        );
      },
      child: body,
    );
  }
}

class _SessionErrorBanner extends StatefulWidget {
  const _SessionErrorBanner({required this.error, required this.onDismiss});

  final AiSessionErrorRecord error;
  final VoidCallback onDismiss;

  @override
  State<_SessionErrorBanner> createState() => _SessionErrorBannerState();
}

class _SessionErrorBannerState extends State<_SessionErrorBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  late final Animation<double> _scale;
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _fade = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.12),
      end: Offset.zero,
    ).animate(_fade);
    _scale = Tween<double>(begin: 0.96, end: 1).animate(_fade);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleDismiss() async {
    if (_exiting) return;
    _exiting = true;
    await _controller.reverse();
    if (!mounted) return;
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final presentation = _presentSessionError(context, widget.error);
    final rawMessage = widget.error.message.trim();
    final hasFullDetails = rawMessage.split('\n').length > 2;

    final banner = Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.error_outline_rounded,
                  size: 18,
                  color: colorScheme.onErrorContainer,
                ),
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
              const SizedBox(width: 4),
              GestureDetector(
                onTap: _handleDismiss,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: colorScheme.onErrorContainer.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ),
          if (hasFullDetails) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: GestureDetector(
                onTap: () => showFriendlyErrorDetailsDialog(
                  context,
                  fullText: rawMessage,
                ),
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 14,
                      color: colorScheme.onErrorContainer.withValues(
                        alpha: 0.8,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      l10n.commonViewDetails,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onErrorContainer.withValues(
                          alpha: 0.8,
                        ),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: ScaleTransition(scale: _scale, child: banner),
      ),
    );
  }
}

class _AnimatedSessionTitleText extends StatelessWidget {
  const _AnimatedSessionTitleText({required this.text, required this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final body = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return body;
    }
    return Tooltip(
      message: trimmed,
      waitDuration: const Duration(milliseconds: 380),
      child: body,
    );
  }
}

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
  static const Duration _sweepDuration = Duration(milliseconds: 2600);

  late final AnimationController _sweepController = AnimationController(
    vsync: this,
    duration: _sweepDuration,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotionPreference();
  }

  @override
  void dispose() {
    _sweepController.dispose();
    super.dispose();
  }

  void _syncMotionPreference() {
    final disabled = MediaQuery.disableAnimationsOf(context);
    if (disabled) {
      _sweepController.stop();
      _sweepController.value = 0;
    } else if (!_sweepController.isAnimating) {
      _sweepController.repeat();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final baseColor = isDark
        ? cs.surfaceContainer
        : cs.surfaceContainerHighest.withValues(alpha: 0.6);
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
    final disabledMotion = MediaQuery.disableAnimationsOf(context);
    final cardRadius = BorderRadius.circular(26);
    final content = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _sweepController,
            builder: (context, child) {
              final scale = disabledMotion
                  ? 1.0
                  : 1.0 + math.sin(_sweepController.value * math.pi * 2) * 0.02;
              final opacity = disabledMotion
                  ? 0.55
                  : 0.54 +
                        (math.sin(_sweepController.value * math.pi * 2) + 1) *
                            0.045;
              return Transform.scale(
                scale: scale,
                child: Icon(
                  icon,
                  size: 40,
                  color: cs.onSurfaceVariant.withValues(alpha: opacity),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: ClipRRect(
        borderRadius: cardRadius,
        child: AnimatedBuilder(
          animation: _sweepController,
          child: content,
          builder: (context, child) {
            final phase = Curves.easeInOutCubicEmphasized.transform(
              _sweepController.value,
            );
            final sweepOffset = disabledMotion ? -64.0 : -250.0 + phase * 560;
            final sweepOpacity = disabledMotion
                ? 0.0
                : math
                      .sin(_sweepController.value * math.pi)
                      .clamp(0.0, 1.0)
                      .toDouble();
            return DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: cardRadius,
                border: Border.all(color: borderColor),
                color: baseColor,
                boxShadow: [
                  BoxShadow(
                    color: cs.shadow.withValues(alpha: isDark ? 0.10 : 0.05),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: SizedBox(
                width: 280,
                height: 220,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(
                              alpha: disabledMotion ? 0.035 : 0.055,
                            ),
                            Colors.transparent,
                            cs.onSurfaceVariant.withValues(
                              alpha: disabledMotion ? 0.018 : 0.03,
                            ),
                          ],
                          stops: const [0.0, 0.48, 1.0],
                        ),
                      ),
                    ),
                    if (!disabledMotion)
                      Opacity(
                        opacity: sweepOpacity,
                        child: Transform.translate(
                          offset: Offset(sweepOffset, 0),
                          child: Transform.rotate(
                            angle: -0.24,
                            child: Center(
                              child: SizedBox(
                                width: 126,
                                height: 340,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.transparent,
                                        Colors.white.withValues(alpha: 0.018),
                                        Colors.white.withValues(alpha: 0.115),
                                        Colors.white.withValues(alpha: 0.022),
                                        Colors.transparent,
                                      ],
                                      stops: const [0.0, 0.28, 0.52, 0.74, 1.0],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    child ?? const SizedBox.shrink(),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Failure card shown in place of the shimmer when a multimedia creation
/// request ended with an error without producing any assistant content.
/// Mirrors the user's chosen creation mode (image / video / audio) so the
/// failed turn stays visually coupled to the request, and surfaces the
/// underlying error message with a dismiss button.
class _CreationFailureCard extends StatefulWidget {
  const _CreationFailureCard({
    required this.request,
    required this.error,
    required this.onDismiss,
  });

  final AiCreationRequest request;
  final AiSessionErrorRecord error;
  final Future<void> Function() onDismiss;

  @override
  State<_CreationFailureCard> createState() => _CreationFailureCardState();
}

class _CreationFailureCardState extends State<_CreationFailureCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  late final Animation<double> _scale;
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
      reverseDuration: const Duration(milliseconds: 240),
    );
    _fade = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.08),
      end: Offset.zero,
    ).animate(_fade);
    _scale = Tween<double>(begin: 0.94, end: 1).animate(_fade);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleDismiss() async {
    if (_exiting) return;
    _exiting = true;
    await _controller.reverse();
    if (!mounted) return;
    await widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final presentation = _presentSessionError(context, widget.error);
    final (icon, titleZh, titleEn) = switch (widget.request.mode) {
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
    final card = Align(
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
                key: ValueKey<String>(
                  'creation-failure-dismiss-${widget.error.id}',
                ),
                onPressed: _handleDismiss,
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
    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: ScaleTransition(scale: _scale, child: card),
      ),
    );
  }
}
