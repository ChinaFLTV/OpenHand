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
  String? _visibleErrorId;
  String? _pendingPresentedErrorId;
  final Set<String> _dismissedErrorIds = <String>{};
  int _windowStartIndex = 0;
  bool _loadingOlderMessages = false;
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
  // 阶段⑱：transcript 内 messageId → BuildContext 反查映射，替代
  // GlobalObjectKey 防御 OverlayPortal/Tooltip 在 LayoutBuilder layout
  // 阶段被 retake 时跨子树 mutation RenderTheater 触发的断言失败。
  final _TranscriptBubbleRegistry _bubbleRegistry = _TranscriptBubbleRegistry();

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
    // 线程会话窗口已下线所有 settle 循环（弹跳源头），首屏贴底由调用方
    // jumpToBottomOnInit 路径在 ListView 挂载后做单帧 jumpTo，不再走
    // 多帧 addPostFrameCallback 链 + lastAdjustedOffset 比较。
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
      // 全量物化首屏的可见窗口：drip 串行 materialization 已下线，
      // ListView 自身的 cacheExtent: 1800 + 懒挂载足以平滑首屏渲染。
      _syncWindowStartIndex(forceReset: true);
      _renderEntries = const <_TranscriptRenderEntry>[];
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
      // jumpToBottomOnInit 由父级 jumpTo 单独保证；这里不再做多帧 settle。
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
    if (clampedWindowStartIndex == 0) {
      return displayMessages;
    }
    return displayMessages.sublist(clampedWindowStartIndex);
  }

  void _replaceRenderEntries(
    List<AiSessionMessage> visibleMessages, {
    bool animate = true,
  }) {
    developer.Timeline.startSync(
      'openhand.session.materialize',
      arguments: <String, Object?>{'count': visibleMessages.length},
    );
    _renderEntries = <_TranscriptRenderEntry>[
      for (final message in visibleMessages) _TranscriptRenderEntry(message: message),
    ];
    developer.Timeline.finishSync();
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
      setState(() => _highlightedMessageId = messageId);
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
      _replaceRenderEntries(_visibleMessagesForWindow(), animate: false);
      _loadingOlderMessages = false;
    });

    // 单帧 jumpTo 一次性把视口拉到"插入前内容"位置。线程会话窗口
    // 不再走多帧 settle 循环（弹跳源头），scroll physics 已改为
    // ClampingScrollPhysics（无 overscroll 弹簧共振），单次 jumpTo
    // 足以保证"加载更早后用户视觉锚点不漂移"。
    if (hadClients) {
      final position =
          scrollController.positions.isNotEmpty ? scrollController.positions.last : null;
      if (position != null) {
        final newMaxExtent = position.maxScrollExtent;
        final delta = newMaxExtent - currentMaxExtent;
        if (delta > 0) {
          final target = (position.pixels + delta).clamp(
            position.minScrollExtent,
            newMaxExtent,
          );
          position.jumpTo(target);
        }
      }
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
              physics: const ClampingScrollPhysics(
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
                return Padding(
                  key: ValueKey<String>('transcript-entry-${message.id}'),
                  padding: EdgeInsets.only(
                    bottom: messageIndex == _renderEntries.length - 1 ? 0 : 14,
                  ),
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
                );
              },
            ),
          ),
        ),
      ],
    );
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

class _SessionErrorBanner extends StatelessWidget {
  const _SessionErrorBanner({required this.error, required this.onDismiss});

  final AiSessionErrorRecord error;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final presentation = _presentSessionError(context, error);
    final rawMessage = error.message.trim();
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
                onTap: onDismiss,
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
    return banner;
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

class _PendingCreationPlaceholderCard extends StatelessWidget {
  const _PendingCreationPlaceholderCard({required this.request});

  final AiCreationRequest request;

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
    final (icon, labelZh, labelEn) = switch (request.mode) {
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
      child: Container(
        width: 280,
        height: 220,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: borderColor),
          color: baseColor,
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
