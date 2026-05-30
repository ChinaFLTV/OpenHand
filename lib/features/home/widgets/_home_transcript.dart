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

  /// 立即把 [sessionId] 对应 transcript 的「分批 drip」全部落地，等价于
  /// 取消 timer + 把 `_materializedTailLimit` 置 null + 一次性物化全部
  /// tail 消息。用于：(1) 应用从后台切回前台后，避免 drip 残留导致
  /// auto-follow 跳到的是被截断的尾部；(2) 用户主动点击「跳到最新」时
  /// 也应立刻看到所有消息而非按 400 ms 步长漫长展开。
  bool flushDripFor(String sessionId) {
    final state = _statesBySession[sessionId];
    if (state == null) return false;
    return state.flushIncrementalDrip();
  }

  void flushAllDrips() {
    for (final state in _statesBySession.values) {
      state.flushIncrementalDrip();
    }
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
      void check() {
        if (_statesBySession[sessionId] != null && !completer.isCompleted) {
          timeout?.cancel();
          completer.complete();
        }
      }

      timeout = Timer(const Duration(milliseconds: 250), () {
        if (!completer.isCompleted) completer.complete();
      });
      // 最多每 16ms 探测一次直到超时 / 命中。
      Timer.periodic(const Duration(milliseconds: 16), (t) {
        if (completer.isCompleted) {
          t.cancel();
          return;
        }
        check();
      });
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
  const _TranscriptRenderEntry({
    required this.message,
    this.exiting = false,
    this.entering = false,
    this.entranceDelay = Duration.zero,
  });

  final AiSessionMessage message;
  final bool exiting;
  final bool entering;
  // 2026-05-02: When several new bubbles arrive in the same frame
  // (e.g. multi-tool plan dispatch streaming back several tool_call /
  // tool_result / reasoning messages at once), running every entrance
  // animation in parallel made the transcript feel chaotic and dropped
  // frames. Each new entering entry now carries an incremental delay
  // so neighbours visibly stagger in instead of erupting simultaneously.
  final Duration entranceDelay;

  String get id => message.id;

  _TranscriptRenderEntry copyWith({
    AiSessionMessage? message,
    bool? exiting,
    bool? entering,
    Duration? entranceDelay,
  }) {
    return _TranscriptRenderEntry(
      message: message ?? this.message,
      exiting: exiting ?? this.exiting,
      entering: entering ?? this.entering,
      entranceDelay: entranceDelay ?? this.entranceDelay,
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
  final AiModelProfile? activeProfile;
  final bool claudeStyle;

  @override
  State<_SessionTranscript> createState() => _SessionTranscriptState();
}

class _SessionTranscriptState extends State<_SessionTranscript> {
  String? _selectedMessageId;
  String? _highlightedMessageId;
  Timer? _highlightTimer;
  String? _visibleErrorId;
  String? _pendingPresentedErrorId;
  final Set<String> _dismissedErrorIds = <String>{};
  int _windowStartIndex = 0;
  bool _loadingOlderMessages = false;
  List<_TranscriptRenderEntry> _renderEntries =
      const <_TranscriptRenderEntry>[];
  bool _initialBuildDone = false;
  // F2 memoize: visibleMessages 的 id→index 映射在 build 路径上每帧重建一次，
  // 长会话下不便宜。displayMessages 是 AiSession 内部缓存（identity 稳定），
  // 因此可以用 (引用, windowStart, length) 作为缓存键。父级 watch 在流式
  // token 触发的 rebuild 中，若 displayMessages 引用未变（典型为非当前会话
  // 的旁路 rebuild），可直接复用上次映射。
  List<AiSessionMessage>? _cachedIndexMapSource;
  int _cachedIndexMapWindowStart = -1;
  Map<String, int>? _cachedVisibleIndexMap;
  // 阶段⑱：transcript 内 messageId → BuildContext 反查映射，替代
  // GlobalObjectKey 防御 OverlayPortal/Tooltip 在 LayoutBuilder layout
  // 阶段被 retake 时跨子树 mutation RenderTheater 触发的断言失败。
  final _TranscriptBubbleRegistry _bubbleRegistry = _TranscriptBubbleRegistry();

  // 2026-05-04: Incremental tail materialization.
  //
  // When several new tail messages arrive in the same frame (typical for
  // multi-tool plans where 5–15 cards stream in within ~100 ms) building
  // every `_MessageBubble` synchronously inside one frame is the dominant
  // ANR source: each card may parse markdown, code-highlight, attach
  // image previews, etc. Spreading materialization over multiple frames
  // breaks that single-frame budget into bite-sized chunks the raster
  // thread can absorb without dropping past the 60 fps line.
  //
  // Mechanics: `_materializedTailLimit` caps how many display messages
  // (counted from `_windowStartIndex`) `_visibleMessagesForWindow` will
  // expose. `_dripTimer` ticks every `_dripStepInterval`, increments
  // the limit by 1 and re-syncs render entries. Once the limit reaches
  // the visible tail's true length the limit clears and the timer
  // stops. New messages that arrive mid-drip are picked up
  // automatically because each tick re-reads
  // `widget.session.displayMessages.length`.
  int? _materializedTailLimit;
  Timer? _dripTimer;
  // 2026-05-04 → 2026-05-08 节奏校准：阈值锁定 2（任何"同帧 ≥2 张
  // 新卡片"都进入串行 materialization，覆盖并行工具调用、AI 一次性
  // 吐多张混合卡、撤销恢复批量回灌等所有"同时填装"场景）；
  // 首批 chunk = 1 让首张卡片即刻到位避免"先空 400ms 再开始漏"
  // 的迟滞感，剩余按 step 串行登场；步长 70→120→150→**400 ms** 再
  // 放慢一大档：用户明确要求"绝不允许同帧塞多张消息卡片"，并以
  // 400 ms 作为感官上"一张一张缓缓落子"的最小可感知间隔。配合
  // 110 ms 入场 stagger（drip 模式下每 tick 仅 1 张 entering，
  // stagger 自然失活），呈现"卡片→稳定→下一张"的 Q 弹节拍。
  static const int _dripStartChunkSize = 1;
  static const int _dripActivationThreshold = 2;
  static const Duration _dripStepInterval = Duration(milliseconds: 400);

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
    // 阶段㉒c (回滚 drip)：首屏「按 1/帧 drip」会把 _visibleMessagesForWindow
    // 截断成「window 开头若干条」，导致用户看到的是最近窗口的「最旧」一条
    // 而不是最新一条 — 与 transcript 默认应当落底的语义直接冲突。回滚到
    // 「render entries 一次性物化、ListView 自然懒挂载」的策略。
    _replaceRenderEntries(_visibleMessagesForWindow(), animate: false);
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
    // 改为「多帧滚动停留循环」：每一帧都重新 read maxScrollExtent
    // 并 jumpTo，命中真正稳定的底部之后立即终止。期间任何一次距离 ≤ 0.5 px
    // 即视为已稳定，提前退出循环避免无意义重排。
    if (widget.jumpToBottomOnInit) {
      _settleJumpToBottom(maxFrames: _transcriptInitialBottomSettleFrameCount);
    }
  }

  /// 通过逐帧重读 `maxScrollExtent + jumpTo` 的方式贴底，覆盖 ListView 在
  /// markdown 异步解析、图片解码等导致后续帧布局抖动场景。最长 [maxFrames]
  /// 帧内寻底；若连续两帧 maxScrollExtent 与当前 pixels 距离 < 0.5 px，
  /// 视为已稳定提前结束。
  /// 阶段㉓b：循环对「用户主动滚动」让位 —— 若上一次循环 jumpTo 后下一帧
  /// 读到 pixels 已被外力（用户拖拽）改变，立即中止后续 jumpTo，避免与
  /// 用户操作互相打架。
  ///
  /// 2026-05-26：主线循环结束后追加一次 350ms 延迟 settle，捕获 HTML
  /// WebView 延迟高度测量（JS setTimeout 100ms/300ms）引发的 maxScrollExtent
  /// 变化，避免 settle 提前收工后视口被 HTML 气泡的 AnimatedSize 撑开而
  /// 悬在"假底部"上方。
  void _settleJumpToBottom({required int maxFrames}) {
    if (maxFrames <= 0) return;
    var stableFrames = 0;
    var mainLoopFinished = false;

    void scheduleLateSettle() {
      if (mainLoopFinished) return;
      mainLoopFinished = true;
      // 两段延迟 settle：600ms 覆盖 JS 100ms+300ms 测量 → AnimatedSize 280ms
      // 动画的完整链路；1000ms 作为二次兜底，捕获更晚的异步排版（图片加载等）。
      for (final delayMs in [600, 1000]) {
        Future.delayed(Duration(milliseconds: delayMs), () {
          if (!mounted) return;
          final controller = widget.controller;
          if (!controller.hasClients) return;
          final position = controller.positions.isNotEmpty
              ? controller.positions.last
              : null;
          if (position == null) return;
          if (position.userScrollDirection != ScrollDirection.idle) return;
          final target = position.maxScrollExtent;
          if (target <= 0) return;
          final distance = (target - position.pixels).abs();
          if (distance >= 0.5 && distance < 1200) {
            position.jumpTo(target);
          }
        });
      }
    }

    void scheduleNext(int remaining) {
      if (remaining <= 0) {
        scheduleLateSettle();
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final controller = widget.controller;
        if (!controller.hasClients) {
          scheduleNext(remaining - 1);
          return;
        }
        final position = controller.positions.isNotEmpty
            ? controller.positions.last
            : null;
        if (position == null) {
          scheduleNext(remaining - 1);
          return;
        }
        if (position.userScrollDirection != ScrollDirection.idle) {
          scheduleLateSettle();
          return;
        }
        // 不再因 pixels 偏离上次 jumpTo 目标而中止循环。
        // maxScrollExtent 收缩时 _StableMaxExtentScrollPosition 会按比例
        // 修正 pixels，修正后的 pixels 必然偏离 lastJumpedTo；若因此退出
        // 循环，后续 HTML 高度变化就无法被跟踪贴底。
        // 用户手势已由 userScrollDirection 检查覆盖，无需此二次校验。
        if (position.pixels > position.maxScrollExtent + 0.5) {
          scheduleNext(remaining - 1);
          return;
        }
        final target = position.maxScrollExtent;
        if (target <= 0) {
          scheduleNext(remaining - 1);
          return;
        }
        final distance = (target - position.pixels).abs();
        if (distance < 0.5) {
          stableFrames += 1;
          if (stableFrames >= 2) {
            scheduleLateSettle();
            return;
          }
        } else {
          stableFrames = 0;
          if (controller.positions.length > 1) {
            scheduleNext(remaining - 1);
            return;
          }
          position.jumpTo(target);
        }
        scheduleNext(remaining - 1);
      });
    }

    scheduleNext(maxFrames);
  }

  @override
  void didUpdateWidget(covariant _SessionTranscript oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.id != widget.session.id) {
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
      // 阶段㉒c (回滚 drip)：drip-based first-open materialisation 会在
      // `_visibleMessagesForWindow()` 处把窗口截断成「头部若干条」，
      // 与 transcript 应当落底到最新一条的语义直接冲突。回滚到「next
      // frame 全量物化 + ListView 自然懒挂载」策略。
      _syncWindowStartIndex(forceReset: true);
      _renderEntries = const <_TranscriptRenderEntry>[];
      _initialBuildDone = false;
      _stopIncrementalDrip();
      // 阶段㉓d：双兜底物化 — 在 mount 状态变化或父级帧抢占
      // `addPostFrameCallback` 时，仅 build 阶段 fallback 仍可能错过
      // 第一帧（同步赋值发生在 Element rebuild，但首帧是当前 frame
      // 之前已 schedule）。`endOfFrame` 在当前帧结束后再尝试一次，
      // 形成「post-frame → endOfFrame → build fallback」三重保险。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_renderEntries.isNotEmpty) return;
        setState(() {
          _replaceRenderEntries(_visibleMessagesForWindow(), animate: false);
        });
      });
      WidgetsBinding.instance.endOfFrame.then((_) {
        if (!mounted) return;
        if (_renderEntries.isNotEmpty) return;
        setState(() {
          _replaceRenderEntries(_visibleMessagesForWindow(), animate: false);
        });
      });
      // 阶段㉓c：edge case 兜底 —— 极少数情况下 widget 实例会在不重建 key
      // 的前提下被赋予新 session（例如父级 KeyedSubtree 被复用），此时
      // initState 不会重跑，而 jumpToBottomOnInit 也不会再读到 true。
      // 显式驱动一次 settle 循环把视口拉到底部，避免与「session 切换默认
      // 应贴底」语义冲突。
      if (widget.jumpToBottomOnInit) {
        _settleJumpToBottom(
          maxFrames: _transcriptInitialBottomSettleFrameCount,
        );
      }
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
    // 阶段⑧ — 避免为了“全量访问”多一份卷复制：窗口从 0 开始
    // 且无位限制时，直接返回底层 List 的不可变视图。
    final cap = _materializedTailLimit;
    if (clampedWindowStartIndex == 0 &&
        (cap == null || cap >= displayMessages.length)) {
      return displayMessages;
    }
    final tail = displayMessages.sublist(clampedWindowStartIndex);
    if (cap != null && cap < tail.length) {
      return tail.sublist(0, cap);
    }
    return tail;
  }

  int _fullVisibleTailCount() {
    final displayMessages = widget.session.displayMessages;
    final clampedWindowStartIndex = _windowStartIndex
        .clamp(0, displayMessages.length)
        .toInt();
    return displayMessages.length - clampedWindowStartIndex;
  }

  /// Begins (or refreshes) an incremental drip that grows
  /// `_materializedTailLimit` from [initialLimit] one step at a time
  /// every [_dripStepInterval] until it reaches the full visible tail
  /// length. Safe to call repeatedly — re-arms the timer rather than
  /// stacking timers.
  void _beginIncrementalDrip(int initialLimit) {
    final fullCount = _fullVisibleTailCount();
    if (initialLimit >= fullCount) {
      _stopIncrementalDrip();
      return;
    }
    _materializedTailLimit = math.max(0, initialLimit);
    _dripTimer?.cancel();
    _dripTimer = Timer.periodic(_dripStepInterval, (timer) {
      if (!mounted) {
        timer.cancel();
        _dripTimer = null;
        _materializedTailLimit = null;
        return;
      }
      final latestFull = _fullVisibleTailCount();
      final current = _materializedTailLimit ?? latestFull;
      final next = current + 1;
      if (next >= latestFull) {
        _materializedTailLimit = null;
        timer.cancel();
        _dripTimer = null;
      } else {
        _materializedTailLimit = next;
      }
      setState(() {
        _replaceRenderEntries(_visibleMessagesForWindow());
      });
    });
  }

  void _stopIncrementalDrip() {
    _dripTimer?.cancel();
    _dripTimer = null;
    _materializedTailLimit = null;
  }

  /// 立即把 drip 截断的尾部一次性物化为完整 tail。返回 true 表示当前
  /// 确实存在一个进行中的 drip 并已被冲刷；false 表示无需操作。安全在
  /// 任意帧阶段调用：若处于 layout / paint / persistent callbacks 中，
  /// `setState` 会被推迟到 post-frame，避免触发 build-during-frame 断言。
  bool flushIncrementalDrip() {
    if (!mounted) return false;
    final wasDripping = _dripTimer != null || _materializedTailLimit != null;
    if (!wasDripping) return false;
    _stopIncrementalDrip();
    final phase = SchedulerBinding.instance.schedulerPhase;
    final inFrame =
        phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks ||
        phase == SchedulerPhase.transientCallbacks;
    void apply() {
      if (!mounted) return;
      setState(() {
        _replaceRenderEntries(_visibleMessagesForWindow(), animate: false);
      });
    }

    if (inFrame) {
      WidgetsBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
    return true;
  }

  void _replaceRenderEntries(
    List<AiSessionMessage> visibleMessages, {
    bool animate = true,
  }) {
    developer.Timeline.startSync(
      'openhand.session.materialize',
      arguments: <String, Object?>{'count': visibleMessages.length},
    );
    final previousIds = animate && _initialBuildDone
        ? _renderEntries.where((e) => !e.exiting).map((e) => e.id).toSet()
        : null;
    // Per-batch stagger: when multiple new entries appear in a single
    // frame, drip them in 110 ms apart (capped at 1650 ms total) so the
    // entrance animations cascade rather than explode in parallel.
    // 2026-05-04: 80→110 ms / 360→1650 ms — user feedback that batches
    // of >5 new messages (typical for tool-call chains) still piled up
    // visually under the previous 360 ms cap. With the new cap up to
    // ~15 sibling entries each get a distinct entrance slot, matching
    // the "一条一条地有序添加" expectation.
    const staggerStep = Duration(milliseconds: 110);
    const staggerCap = Duration(milliseconds: 1650);
    var newEntryOrdinal = 0;
    _renderEntries = <_TranscriptRenderEntry>[
      for (final message in visibleMessages)
        () {
          final entering =
              previousIds != null && !previousIds.contains(message.id);
          final delay = entering
              ? Duration(
                  milliseconds: math.min(
                    staggerCap.inMilliseconds,
                    staggerStep.inMilliseconds * newEntryOrdinal++,
                  ),
                )
              : Duration.zero;
          return _TranscriptRenderEntry(
            message: message,
            entering: entering,
            entranceDelay: delay,
          );
        }(),
    ];
    _initialBuildDone = true;
    developer.Timeline.finishSync();
  }

  void _syncRenderEntries({bool forceReset = false}) {
    // 2026-05-04: Bulk-arrival drip — when the diff is about to materialize
    // many new bubbles in one shot (typical for tool-call plans where
    // 5–15 cards stream back within a single frame) we shrink
    // `_visibleMessagesForWindow` via `_materializedTailLimit` and let
    // a 70 ms-per-step periodic timer grow the cap one message at a
    // time. Each tick re-invokes `_replaceRenderEntries`, so new
    // entries flow in one-by-one and the markdown / code-highlight /
    // image-decode work is spread across frames instead of piling up
    // in one synchronous build pass.
    if (!forceReset && _renderEntries.isNotEmpty) {
      final fullDisplayMessages = widget.session.displayMessages;
      final clampedStart = _windowStartIndex
          .clamp(0, fullDisplayMessages.length)
          .toInt();
      final fullTailLength = fullDisplayMessages.length - clampedStart;
      final activeIdSet = <String>{
        for (final entry in _renderEntries)
          if (!entry.exiting) entry.id,
      };
      var newAdditions = 0;
      for (var i = clampedStart; i < fullDisplayMessages.length; i++) {
        if (!activeIdSet.contains(fullDisplayMessages[i].id)) {
          newAdditions++;
        }
      }
      final dripInProgress =
          _dripTimer != null && _materializedTailLimit != null;
      // 2026-05-23 (修复)：应用进入后台 / 非 resumed 生命周期时，drip 的
      // 「分帧动效」毫无意义（UI 根本没在绘制），反而会让消息持续被截断；
      // 一旦回到前台，截断的尾部会让 auto-follow 把视口拉到「假底部」，
      // 之后还要逐 400ms 漫长展开。此处直接放弃 drip 改为同步全量物化，
      // 让后续 lifecycle-resume 钩子拿到真实的 maxScrollExtent。
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      final lifecycleSuspended =
          lifecycle != null && lifecycle != AppLifecycleState.resumed;
      final shouldDrip =
          !lifecycleSuspended &&
          (newAdditions >= _dripActivationThreshold ||
              (dripInProgress && newAdditions > 0));
      if (lifecycleSuspended && dripInProgress) {
        _stopIncrementalDrip();
      }
      if (shouldDrip) {
        // Drip 进行中时不要重启 timer：流式 token 更新会高频触发
        // _syncRenderEntries，若每次都取消并重建 400 ms timer，后续卡片
        // 会在模型持续输出时被无限延后。现有 timer 每拍都会重读 tail 长度，
        // 新到的消息自然会被下一拍吸收。
        if (!dripInProgress) {
          final initialLimit = math.min(
            activeIdSet.length + _dripStartChunkSize,
            fullTailLength,
          );
          _beginIncrementalDrip(initialLimit);
        }
      } else {
        _stopIncrementalDrip();
      }
    } else {
      _stopIncrementalDrip();
    }
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

  @override
  void dispose() {
    _TranscriptScrollDispatcher.instance.unregister(widget.session.id, this);
    _dripTimer?.cancel();
    _dripTimer = null;
    _highlightTimer?.cancel();
    _highlightTimer = null;
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
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    // Q 弹滚动：680 ms + easeOutQuint。前段快速给出"已响应"反馈，
    // 末段长尾减速形成"落子"质感；reduce-motion 退化为瞬移。
    final smoothDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 680);
    const smoothCurve = Curves.easeOutQuint;
    // 中长距离逼近：使用 emphasized 曲线（M3 推荐）让大跨度滚动既快又柔。
    final approachDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 480);
    const approachCurve = Curves.easeInOutCubicEmphasized;

    void flashTarget() {
      if (!highlight || !mounted) return;
      _highlightTimer?.cancel();
      setState(() => _highlightedMessageId = messageId);
      _highlightTimer = Timer(const Duration(milliseconds: 1400), () {
        if (!mounted || _highlightedMessageId != messageId) return;
        setState(() => _highlightedMessageId = null);
      });
    }

    Future<bool> tryEnsureVisible() async {
      final ctx = _bubbleRegistry.contextOf(messageId);
      if (ctx == null) return false;
      await Scrollable.ensureVisible(
        ctx,
        alignment: 0.18,
        duration: smoothDuration,
        curve: smoothCurve,
      );
      flashTarget();
      return true;
    }

    // 抑制并发 drip → setState 与滚动动画互相打架是"上下抽搐"的根因；
    // 一次性停掉 drip，并让 render entries 与最新可见集对齐，但仅在
    // 当前 entries 与最新可见集**不一致**时才 setState，避免无意义
    // 重建带来的二次重排。
    if (_dripTimer != null || _materializedTailLimit != null) {
      _stopIncrementalDrip();
      final fullVisible = _visibleMessagesForWindow();
      final activeEntryIds = _renderEntries
          .where((entry) => !entry.exiting)
          .map((entry) => entry.id)
          .toList(growable: false);
      final fullIds = fullVisible.map((m) => m.id).toList(growable: false);
      var needsRebuild = activeEntryIds.length != fullIds.length;
      if (!needsRebuild) {
        for (var i = 0; i < fullIds.length; i++) {
          if (activeEntryIds[i] != fullIds[i]) {
            needsRebuild = true;
            break;
          }
        }
      }
      if (needsRebuild) {
        setState(() {
          _replaceRenderEntries(fullVisible, animate: false);
        });
        await WidgetsBinding.instance.endOfFrame;
      }
    }
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
      await _revealOlderMessages(display.length);
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
      duration: approachDuration,
      curve: approachCurve,
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
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          dampening: 0.5,
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
    if (duration == Duration.zero) {
      scrollController.jumpTo(goal);
      return true;
    }
    await scrollController.animateTo(goal, duration: duration, curve: curve);
    return true;
  }

  Future<bool>? _activeScrollFuture;
  String? _activeScrollTargetId;

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
      _stopIncrementalDrip();
      _replaceRenderEntries(_visibleMessagesForWindow(), animate: false);
      _loadingOlderMessages = false;
    });

    // After the frame rebuilds with new items at the top, adjust scroll offset
    // so the user sees the same content as before (the "Load earlier" button's
    // position just replaced by older messages, but the later messages stay
    // in view). Deferred markdown/code highlighting can keep increasing the
    // prepended content height for a few frames, so settle repeatedly and stop
    // as soon as an external scroll (usually the user) takes over.
    if (hadClients) {
      var previousMaxExtent = currentMaxExtent;
      double? lastAdjustedOffset;
      var stableFrames = 0;
      void settlePrependedHeight(int remainingFrames) {
        if (remainingFrames <= 0) {
          return;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !scrollController.hasClients) return;
          final position = scrollController.positions.isNotEmpty
              ? scrollController.positions.last
              : null;
          if (position == null) return;
          // 用户手势硬阻断：settle 期间如果检测到用户正在拖拽 / 滚动，
          // 立即放弃后续 jumpTo，避免与 BouncingScrollPhysics 弹簧共振
          // 造成贴底抽搐。
          if (position.userScrollDirection != ScrollDirection.idle) {
            return;
          }
          if (lastAdjustedOffset != null &&
              (position.pixels - lastAdjustedOffset!).abs() > 1) {
            return;
          }

          final newMaxExtent = position.maxScrollExtent;
          final delta = newMaxExtent - previousMaxExtent;
          previousMaxExtent = newMaxExtent;
          if (delta.abs() <= 0.5) {
            stableFrames += 1;
            if (stableFrames >= 2) return;
          } else {
            stableFrames = 0;
            if (scrollController.positions.length > 1) {
              settlePrependedHeight(remainingFrames - 1);
              return;
            }
            // 弹簧让步：若上一帧 jumpTo 后 maxExtent 萎缩导致像素越界，
            // BouncingScrollPhysics 弹簧正在回拉，此时不抢 jumpTo，
            // 让弹簧自然沉降后再做下一帧调整，避免 settle 循环与弹簧共振。
            if (position.pixels > position.maxScrollExtent + 0.5) {
              lastAdjustedOffset = position.pixels;
              settlePrependedHeight(remainingFrames - 1);
              return;
            }
            final targetOffset = (position.pixels + delta).clamp(
              position.minScrollExtent,
              newMaxExtent,
            );
            position.jumpTo(targetOffset);
            lastAdjustedOffset = targetOffset;
          }
          settlePrependedHeight(remainingFrames - 1);
        });
      }

      settlePrependedHeight(10);
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
    // 阶段㉓d build-stage 同步首屏 fallback —
    // 当 didUpdateWidget 把 `_renderEntries` 重置为空、且 post-frame
    // callback 因 mount 抖动尚未触发时，直接同步物化首屏，避免
    // 「displayMessages 非空 → empty short-circuit」连续 K 帧白屏。
    // 注意：build 中不允许 setState，但 _replaceRenderEntries 仅做
    // 字段赋值（与 didUpdateWidget 内的同名调用一致），赋值后
    // 当前帧即拿到新 `_renderEntries` 用于绘制，不破坏 build 不变量。
    if (_renderEntries.isEmpty && visibleMessages.isNotEmpty) {
      _replaceRenderEntries(visibleMessages, animate: false);
    }
    if (_renderEntries.isEmpty && visibleMessages.isEmpty) {
      // 2026-05-25 — 两阶段加载窗口期（header 已注入 / full 未到）若用户
      // 选中的会话当前 messages 为空，渲染丝滑加载占位卡而非 empty state，
      // 避免「打开历史线程瞬间白屏」。
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
    final userVisibleError = _resolveUserVisibleError(session);
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
          activeProfile: widget.activeProfile,
          claudeStyle: widget.claudeStyle,
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
              // Lowered from 800 → 320: the previous value pre-built ~5
              // extra bubble subtrees beyond the viewport on every session
              // open, each running a synchronous markdown parse on its
              // first frame and dominating first-open frame budgets on
              // large sessions. 320 still covers small fling overshoots
              // without re-laying-out neighbours.
              // 阶段㉒ — 320 → 120：用户反馈首次打开 60+ 条会话仍 ANR。
              // 主因是 cacheExtent 320 px 在首屏 mount 时就开始构建 1-2
              // 个 viewport 之外的气泡，叠加 visible 视窗的 3-5 个气泡，
              // 一次性 8+ 个 _MessageBubble 同帧 mount + 各自调度
              // markdown 解析。把 cacheExtent 收缩到 120 px 让 ListView
              // 首屏严格只构建可见气泡，越界滚动时再 lazy 构建；牺牲
              // 一点 fling 期的 buffer 换取首屏帧预算。
              //
              // 2026-05-17 进一步提升到 1800：600 px 仍偶尔有 bubble 进出
              // cacheExtent 边界 → dispose/rebuild 后重新解析的 markdown
              // 几何与原值偏差几像素，触发 SliverList correctPixels。
              //
              // 注意：不能走 AutomaticKeepAliveClientMixin 路径——该 mixin
              // 会把离屏 bubble 放进 Offstage 容器，使其 render object 不被
              // layout（hasSize=false），但 SelectableRegion 仍会枚举它们
              // 的 Selectable 并读 paintBounds 排序，触发
              // "RenderBox was not laid out" 断言崩溃（已实测）。
              //
              // 改用「大缓冲 cacheExtent」实现同样的几何稳定性：
              // cacheExtent 内的 bubble 是 *完整 laid out* 的，几何一旦
              // 稳定便不再变，SelectableRegion 排序访问 paintBounds 不会
              // 出错。3 个 viewport（3×600≈1800）足以覆盖绝大多数会话的
              // 全部气泡，边界穿越现象几乎不再发生；首屏 ANR 由
              // _MarkdownFrameScheduler + drip 物化 + _SafeMarkdownBody
              // 阈值联同缓解。
              cacheExtent: 1800,
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
                  entranceDelay: entry.entranceDelay,
                  bottomSpacing: messageIndex == _renderEntries.length - 1
                      ? 0
                      : 14,
                  onExitCompleted: () =>
                      _handleRenderEntryExitCompleted(message.id),
                  child: IgnorePointer(
                    ignoring: entry.exiting,
                    child: RepaintBoundary(
                      child: _TranscriptBubbleRegistrar(
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
                          isSelected: isSelected,
                          isScrollHighlighted:
                              _highlightedMessageId == message.id,
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
                                    claudeStyle: widget.claudeStyle,
                                  );
                                }
                              : null,
                        ),
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
    this.entranceDelay = Duration.zero,
  });

  final bool entering;
  final bool exiting;
  final double bottomSpacing;
  final VoidCallback onExitCompleted;
  final Widget child;
  final Duration entranceDelay;

  @override
  State<_TranscriptAnimatedMessageEntry> createState() =>
      _TranscriptAnimatedMessageEntryState();
}

class _TranscriptAnimatedMessageEntryState
    extends State<_TranscriptAnimatedMessageEntry>
    with SingleTickerProviderStateMixin {
  // 2026-05-01: Bumped 420→520 ms so the entrance has room to breathe;
  // pairs with a softer overshoot curve below for a more "Q弹" feel
  // without straying into wobble territory.
  // 2026-05-03: 520→620 ms to give Curves.elasticOut the runway it needs
  // to settle without feeling rushed; pairs with the wider stagger.
  static const _entranceDuration = Duration(milliseconds: 620);

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
      // Opacity: front-loaded so the bubble materializes ~halfway through
      // the entrance, then dwells fully visible while the elastic scale
      // settles. easeOutQuint lands the alpha sooner than easeOut, which
      // makes the subsequent overshoot feel like polish rather than
      // "still arriving".
      _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _entranceCtrl!,
          curve: const Interval(0.0, 0.45, curve: Curves.easeOutQuint),
        ),
      );
      // Scale: Curves.elasticOut for the most pronounced Q弹 spring —
      // explicitly user-requested ("最拉风格"). Starting at 0.92 (was
      // 0.96) makes the contraction more visible before the elastic
      // recoil. Alignment is set to .topCenter at the consumer site so
      // the bounce reads as growth from the top edge rather than a
      // recentre.
      _scale = Tween<double>(begin: 0.92, end: 1.0).animate(
        CurvedAnimation(parent: _entranceCtrl!, curve: Curves.elasticOut),
      );
      // Slide: a touch deeper (0.04 → 0.06 fractional height) and uses
      // `easeInOutCubicEmphasized` (the Material 3 emphasized curve) so the
      // upward glide decelerates with the same characteristic feel as
      // panel transitions elsewhere in OpenHand.
      _slide = Tween<Offset>(begin: const Offset(0.0, 0.10), end: Offset.zero)
          .animate(
            CurvedAnimation(
              parent: _entranceCtrl!,
              curve: Curves.easeInOutCubicEmphasized,
            ),
          );
      // Tear down the entrance animation as soon as it finishes so the
      // ticker stops driving rebuilds for every still-mounted entry.
      // With long sessions (1k+ messages) and a `cacheExtent` that keeps
      // the most recently scrolled tiles alive, leaving the controller
      // ticking after the one-shot reveal contributes a measurable
      // baseline cost to subsequent frames.
      _entranceCtrl!.addStatusListener(_onEntranceStatus);
      if (widget.entranceDelay == Duration.zero) {
        _entranceCtrl!.forward();
      } else {
        // Fire-and-forget: by the time the delay elapses we may already
        // have been disposed (rapid scroll / session switch), so guard
        // both the controller and `mounted`.
        Future<void>.delayed(widget.entranceDelay, () {
          if (!mounted) return;
          _entranceCtrl?.forward();
        });
      }
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
      if (MediaQuery.disableAnimationsOf(context)) {
        // Reduce-motion: skip the elastic exit, fire onExitCompleted on
        // the next microtask so the parent prunes us as if the animation
        // had finished instantly.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onExitCompleted();
        });
        return const SizedBox.shrink();
      }
      return TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 1, end: 0),
        duration: _transcriptMessageDeleteAnimationDuration,
        // 2026-05-04: Q弹退场 — 前 18% 阶段保留 1.0 高度并轻微"鼓"出
        // (1.0 → 1.06)，其后 82% 才真正开始 height/opacity 折叠 +
        // 收缩到 0.86。这种 "anticipation → release" 的两段式节奏让
        // 退场读起来像气球泄气而非生硬截断。曲线在 builder 内部
        // 分阶段计算，TweenAnimationBuilder 走线性即可。
        onEnd: widget.onExitCompleted,
        builder: (context, value, child) {
          final clampedValue = value.clamp(0.0, 1.0);
          final exitProgress = 1 - clampedValue;
          // Anticipation 阶段（前 18%）：高度保持，仅放大 1.0 → 1.06；
          // Collapse 阶段（后 82%）：高度从 1 → 0、缩放从 1.06 → 0.86、
          // 透明度从 1 → 0。
          const anticipateEnd = 0.18;
          double heightFactor;
          double opacity;
          double scale;
          double translateY;
          if (exitProgress < anticipateEnd) {
            final t = exitProgress / anticipateEnd; // 0 → 1
            final eased = Curves.easeOutCubic.transform(t);
            heightFactor = 1.0;
            opacity = 1.0;
            scale = 1.0 + 0.06 * eased;
            translateY = -3 * eased;
          } else {
            final t = (exitProgress - anticipateEnd) / (1 - anticipateEnd);
            final easedFold = Curves.easeInOutCubicEmphasized.transform(
              t.clamp(0.0, 1.0),
            );
            heightFactor = (1.0 - easedFold).clamp(0.0, 1.0);
            opacity = (1.0 - easedFold).clamp(0.0, 1.0);
            scale = 1.06 - 0.20 * easedFold;
            translateY = -3 - 14 * Curves.easeOutCubic.transform(t);
          }
          return ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: heightFactor,
              child: Opacity(
                opacity: opacity,
                child: Transform.translate(
                  offset: Offset(0, translateY),
                  child: Transform.scale(
                    scale: scale,
                    alignment: Alignment.topCenter,
                    child: child,
                  ),
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
      if (MediaQuery.disableAnimationsOf(context)) {
        // Reduce-motion: snap to the resting state. Settling the
        // controller to value=1.0 lets _onEntranceStatus run on the next
        // tick which disposes it and switches us to the fast path.
        _entranceCtrl!.value = 1.0;
        return child;
      }
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

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      reverseDuration: const Duration(milliseconds: 250),
    );
    final entry = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );
    _fade = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.15),
      end: Offset.zero,
    ).animate(entry);
    _scale = Tween<double>(begin: 0.92, end: 1.0).animate(entry);
  }

  bool _hasPlayedEntrance = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasPlayedEntrance) {
      _hasPlayedEntrance = true;
      if (!MediaQuery.disableAnimationsOf(context)) {
        _controller.forward();
      } else {
        _controller.value = 1.0;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleDismiss() async {
    if (!MediaQuery.disableAnimationsOf(context)) {
      await _controller.reverse();
    }
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
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
                      '查看详情 / View details',
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

    if (MediaQuery.disableAnimationsOf(context)) return banner;
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: ScaleTransition(scale: _scale, child: banner),
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
      _controller ??=
          AnimationController(
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
    final Widget body;
    if (!_animatedOnce || _controller == null) {
      body = Text(
        widget.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: widget.style,
      );
    } else {
      body = AnimatedBuilder(
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
    // Hover-tooltip exposes the full title when it's truncated by ellipsis.
    // We always wrap (even short titles) — Flutter's Tooltip suppresses the
    // popup when the trigger has no overflow only on web; on desktop we
    // accept the rare no-op tooltip on short titles in exchange for never
    // hiding a long title behind ellipsis.
    final trimmed = widget.text.trim();
    if (trimmed.isEmpty) {
      return body;
    }
    return Tooltip(
      message: trimmed,
      waitDuration: const Duration(milliseconds: 380),
      child: body,
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
    final hash =
        (_scrambleSalt ^ (index * 2654435761) ^ (frameBand * 40503)) &
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
    Widget buildCard(double t) {
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
    }

    final animationsEnabled =
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    if (!animationsEnabled) {
      _ctrl.stop();
      return Align(alignment: Alignment.centerLeft, child: buildCard(0.5));
    }
    if (!_ctrl.isAnimating) {
      _ctrl.repeat();
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          return buildCard(_ctrl.value);
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
