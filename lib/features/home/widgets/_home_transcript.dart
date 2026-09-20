part of '../openhand_home_page.dart';

const Duration _kTranscriptCardEntranceDuration = kOpenHandMotion420;
const Duration _kCreationPlaceholderExitDuration = kOpenHandMotion260;
const Duration _kCreationFailureExitDuration = kOpenHandMotion240;
// 视口外预物化范围。含 HTML WebView 卡片的会话对 cacheExtent 极敏感——
// 过大时滚动会在视口外同步挂载多个平台视图，直接拖垮帧率。
// 280 约等于 2~3 条富文本气泡高度，兼顾预渲染与帧预算。
const double _kTranscriptListCacheExtent = 280;
const int _kTranscriptViewportFillMessageLimit = 64;
const int _kTranscriptViewportFillPageLimit = 3;
const double _kTranscriptScrollbarThickness = 6;
const Radius _kTranscriptScrollbarRadius = kOpenHandPillRadius;
const double _kTranscriptEstimatedMessageSpacing = 14;
const int _kScrollToMessageMaterializeFrameLimit = 8;
const int _kAnimatedMessageIdCacheLimit = 256;
const Duration _kTranscriptTargetScrollDuration = kOpenHandMotion520;
const Duration _kTranscriptTargetHighlightDuration = Duration(
  milliseconds: 1400,
);
const Curve _kTranscriptTargetScrollCurve = Cubic(0.22, 0.92, 0.28, 1);
const String _kTranscriptEntryKeyPrefix = 'transcript-entry-';
const String _kTranscriptLoadEarlierKey = 'transcript-load-earlier';
const String _kTranscriptPendingCreationKey = 'transcript-pending-creation';
const String _kTranscriptRetiringCreationKey = 'transcript-retiring-creation';
const String _kTranscriptCreationFailureKey = 'transcript-creation-failure';
const String _kTranscriptErrorBannerKey = 'transcript-error-banner';

/// 多媒体判定要解析附件、递归遍历 metadata 并对整条正文跑两轮正则，而它对
/// 同一个消息对象恒定。会话消息不可变、流式更新会产生新实例，按对象缓存即可
/// 让每条消息只算一次，并随对象回收自动释放。
final Expando<bool> _transcriptMultimediaContentCache = Expando<bool>(
  'transcriptMultimediaContent',
);

/// 消息是否走 HTML WebView 渲染器的判定缓存。结果取决于正文与当前
/// 内容格式设置；按对象缓存，格式变化时丢弃该条。
class _HtmlRendererCacheEntry {
  const _HtmlRendererCacheEntry({required this.format, required this.usesHtml});

  final AiMessageContentFormat format;
  final bool usesHtml;
}

final Expando<_HtmlRendererCacheEntry> _transcriptHtmlRendererCache =
    Expando<_HtmlRendererCacheEntry>('transcriptHtmlRenderer');

/// 知识库元数据判定缓存。消息对象不可变，直接元数据结果恒定。
// 包装类：Expando 的值类型必须为 Object（非可空），用包装区分 null 与未缓存。
class _KnowledgeBaseMetadataCacheEntry {
  const _KnowledgeBaseMetadataCacheEntry(this.value);
  final Map<String, Object?>? value;
}

final Expando<_KnowledgeBaseMetadataCacheEntry>
_knowledgeBaseDirectMetadataCache = Expando<_KnowledgeBaseMetadataCacheEntry>(
  'knowledgeBaseDirectMetadata',
);

/// keepAlive 开关由参数驱动而非「换一个 widget 类型」。按类型切换会让
/// Element 类型不匹配，选中/取消选中一条 HTML 消息就整棵子树卸载重建——
/// 重新净化、重新解析、WebView 重挂，恰好把 keepAlive 想省的开销全付一遍。
class _TranscriptBubbleKeepAlive extends StatefulWidget {
  const _TranscriptBubbleKeepAlive({
    required this.enabled,
    required this.child,
  });

  final bool enabled;
  final Widget child;

  @override
  State<_TranscriptBubbleKeepAlive> createState() =>
      _TranscriptBubbleKeepAliveState();
}

class _TranscriptBubbleKeepAliveState extends State<_TranscriptBubbleKeepAlive>
    with AutomaticKeepAliveClientMixin<_TranscriptBubbleKeepAlive> {
  @override
  bool get wantKeepAlive => widget.enabled;

  @override
  void didUpdateWidget(covariant _TranscriptBubbleKeepAlive oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      updateKeepAlive();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// 每个气泡的 BuildContext 注册到所属 transcript state 的局部
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
    required this.onLayoutChanged,
    required this.child,
  });

  final String messageId;
  final _TranscriptBubbleRegistry registry;
  final VoidCallback onLayoutChanged;
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
    // 负向历史列表的尺寸变化不一定改变滚动范围，不能只依赖滚动指标通知。
    return _MeasureSize(
      onChange: (_) => widget.onLayoutChanged(),
      child: widget.child,
    );
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

/// 锚点恢复的三态结果：区分「已修正」「实测稳定」与「暂不可测量」，
/// 稳定循环只把前两者计入提前退出判定。
enum _AnchorRestoreOutcome { corrected, stable, unmeasurable }

/// 跨 widget 的「按 messageId 平滑滚动」分发器。
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

  Future<bool> scrollToMessage(
    String sessionId,
    String messageId, {
    bool highlight = false,
  }) async {
    // 最多等待 250 ms，避免帧调度暂停时 endOfFrame 永久不完成。
    var state = _statesBySession[sessionId];
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

      timeout = startSafeTimer(const Duration(milliseconds: 250), () {
        pollTimer?.cancel();
        if (!completer.isCompleted) completer.complete();
      });
      // 最多每帧探测一次直到超时 / 命中。
      pollTimer = startSafePeriodicTimer(kOpenHandFramePeriodicTimerInterval, (
        t,
      ) {
        if (completer.isCompleted) {
          t.cancel();
          return;
        }
        check();
      }, min: kOpenHandFramePeriodicTimerInterval);
      await completer.future;
      state = _statesBySession[sessionId];
    }
    if (state == null) return false;
    return state._scrollToMessageId(messageId, highlight: highlight);
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
    required this.sendPhase,
    required this.onLayoutChanged,
    required this.onMessageExpansionChanged,
    required this.preserveViewportAfterUserScroll,
    required this.onRevealOlderMessages,
    required this.onProgrammaticScrollCorrection,
    required this.messageActions,
    required this.ttsPlaybackService,
    required this.translationService,
    required this.onDismissError,
    this.claudeStyle = true,
  });

  final ScrollController controller;
  final bool Function(ScrollNotification notification) onScrollNotification;
  final AiSession session;
  final AiSendPhase sendPhase;
  final VoidCallback onLayoutChanged;
  final ValueChanged<bool> onMessageExpansionChanged;
  final bool preserveViewportAfterUserScroll;
  final VoidCallback onRevealOlderMessages;
  final void Function(VoidCallback correction) onProgrammaticScrollCorrection;
  final _MessageActions messageActions;
  final AiTtsPlaybackService ttsPlaybackService;
  final AiTranslationService translationService;
  final Future<void> Function(AiSessionErrorRecord error) onDismissError;
  final bool claudeStyle;

  @override
  State<_SessionTranscript> createState() => _SessionTranscriptState();
}

class _MessageTranslationEntry {
  const _MessageTranslationEntry({
    required this.sourceText,
    required this.settingsFingerprint,
    required this.translatedText,
  });

  final String sourceText;
  final String settingsFingerprint;
  final String translatedText;

  int get retainedCharacters =>
      sourceText.length + settingsFingerprint.length + translatedText.length;
}

const int _messageTranslationCacheMaxEntries = 128;
const int _messageTranslationCacheMaxCharacters = 4 * kBytesPerMiB;

enum _TranscriptInitialRevealPhase {
  preparing,
  dismissingPlaceholder,
  revealingContent,
  ready,
}

enum _TranscriptMultimediaKind { image, video, audio }

const Map<String, _TranscriptMultimediaKind?>
_transcriptMultimediaMetadataKeys = <String, _TranscriptMultimediaKind?>{
  'image_path': _TranscriptMultimediaKind.image,
  'image_paths': _TranscriptMultimediaKind.image,
  'generated_image_path': _TranscriptMultimediaKind.image,
  'generated_image_paths': _TranscriptMultimediaKind.image,
  'video_path': _TranscriptMultimediaKind.video,
  'video_paths': _TranscriptMultimediaKind.video,
  'generated_video_path': _TranscriptMultimediaKind.video,
  'generated_video_paths': _TranscriptMultimediaKind.video,
  'audio_path': _TranscriptMultimediaKind.audio,
  'audio_paths': _TranscriptMultimediaKind.audio,
  'generated_audio_path': _TranscriptMultimediaKind.audio,
  'generated_audio_paths': _TranscriptMultimediaKind.audio,
  'media_path': null,
  'media_paths': null,
};

const Set<String> _transcriptMultimediaAttachmentKindHints = <String>{
  'image',
  'img',
  'picture',
  'photo',
  'video',
  'movie',
  'audio',
  'sound',
  'voice',
};

final RegExp _transcriptMarkdownMediaLinkPattern = RegExp(
  r'(!?)\[([^\]\n]{0,240})\]\(([^)\r\n]+)\)',
  caseSensitive: false,
);

final RegExp _transcriptHtmlMediaSrcPattern = RegExp(
  r'''<(?:img|video|audio|source)\b[^>]*\bsrc\s*=\s*["']([^"']+)["'][^>]*>''',
  caseSensitive: false,
);

class _SessionTranscriptState extends State<_SessionTranscript> {
  String? _selectedMessageId;
  String? _highlightedMessageId;
  Timer? _targetHighlightTimer;
  String? _visibleErrorId;
  String? _pendingPresentedErrorId;
  final Set<String> _dismissedErrorIds = <String>{};
  int _windowStartIndex = 0;
  String? _listCenterMessageId;
  final _listHistoryKey = GlobalKey();
  final _listCenterKey = GlobalKey();
  double _listAnchor = 1;
  bool _loadingOlderMessages = false;
  List<_TranscriptRenderEntry> _renderEntries =
      const <_TranscriptRenderEntry>[];
  Map<String, int> _renderEntryIndexById = const <String, int>{};
  // F2 memoize: visibleMessages 的 id→index 映射在 build 路径上每帧重建一次，
  // 长会话下不便宜。displayMessages 是 AiSession 内部缓存（identity 稳定），
  // 因此可以用 (引用, windowStart, length) 作为缓存键。父级 watch 在流式
  // token 触发的 rebuild 中，若 displayMessages 引用未变（典型为非当前会话
  // 的旁路 rebuild），可直接复用上次映射。
  List<AiSessionMessage>? _cachedIndexMapSource;
  int _cachedIndexMapWindowStart = -1;
  Map<String, int>? _cachedVisibleIndexMap;
  List<AiSessionMessage>? _cachedVisibleMessages;
  int? _cachedVisibleMessagesWindowStart;
  // build 路径上的 _resolvePendingCreationPlaceholder 与 _resolveUserVisibleError
  // 在长会话下分别会反向遍历 visibleMessages 与 recentErrors，O(N) per build。
  // 父级 watch 流式 token 触发的 rebuild
  // 中输入（visibleMessages、sendPhase、dismissedErrorIds 等）多数未
  // 变化时缓存命中可省掉两轮线性扫描。键由 (visibleMessages identity,
  // sendPhase, dismissedErrorIds size) 组成，identity 命中即复用。
  List<AiSessionMessage>? _cachedCreationRequestDisplaySource;
  int? _cachedCreationRequestWindowStart;
  AiSendPhase? _cachedCreationRequestSendPhase;
  bool? _cachedCreationRequestAllowWhenIdle;
  AiCreationRequest? _cachedCreationRequest;
  bool _cachedCreationRequestComputed = false;
  AiCreationRequest? _lastActiveCreationPlaceholder;
  AiCreationRequest? _retiringCreationPlaceholder;
  Timer? _retiringCreationPlaceholderTimer;
  List<AiSessionErrorRecord>? _cachedUserVisibleErrorSource;
  int? _cachedUserVisibleErrorDismissedLength;
  String? _cachedUserVisibleErrorVisibleId;
  AiSessionErrorRecord? _cachedUserVisibleError;
  // transcript 内 messageId → BuildContext 反查映射，替代
  // GlobalObjectKey 防御 OverlayPortal/Tooltip 在 LayoutBuilder layout
  // 阶段被 retake 时跨子树 mutation RenderTheater 触发的断言失败。
  final _TranscriptBubbleRegistry _bubbleRegistry = _TranscriptBubbleRegistry();
  final Set<String> _animatedMessageIds = <String>{};
  int _messageActionPanelMotionKey = 0;
  int _consumedMessageActionPanelMotionKey = 0;
  // 保存每条消息的【显示原始】状态，避免会话窗口刷新后状态丢失。
  final Map<String, bool> _rawContentVisibleByMessageId = <String, bool>{};
  final LifecycleLruCache<_MessageTranslationEntry>
  _translationCacheByMessageId = LifecycleLruCache<_MessageTranslationEntry>(
    maxEntries: _messageTranslationCacheMaxEntries,
    maxCost: _messageTranslationCacheMaxCharacters,
    costOf: (entry) => entry.retainedCharacters,
  );
  final Set<String> _translationVisibleMessageIds = <String>{};
  final Set<String> _translationLoadingMessageIds = <String>{};
  int _translationGeneration = 0;
  _TranscriptViewportAnchor? _pendingPrependAnchor;
  int _pendingPrependAnchorFrames = 0;
  int _pendingPrependAnchorStableFrames = 0;
  bool _prependAnchorCorrectionQueued = false;
  TranscriptScrollActivity? _scrollActivity;
  Future<void>? _activeRevealOlderFuture;
  int _initialLayoutSettleGeneration = 0;
  _TranscriptInitialRevealPhase _initialRevealPhase =
      _TranscriptInitialRevealPhase.preparing;

  /// 动画标记只服务于当前窗口的首次入场。历史消息不断前插时若无限累积，
  /// 会把整条会话的 ID 长期留在 State 中，增加内存和集合查找成本。
  void _markMessageAnimated(String messageId) {
    if (messageId.isEmpty) return;
    _animatedMessageIds
      ..remove(messageId)
      ..add(messageId);
    while (_animatedMessageIds.length > _kAnimatedMessageIdCacheLimit) {
      _animatedMessageIds.remove(_animatedMessageIds.first);
    }
  }

  final RichContentFrameScheduler _windowFillScheduler =
      RichContentFrameScheduler(isPaused: _transcriptRenderPaused);
  int _staggerFillGeneration = 0;
  bool _staggerFillActive = false;
  bool _viewportFillQueued = false;
  int _viewportFillMessagesRemaining = _kTranscriptViewportFillMessageLimit;
  int _viewportFillPagesRemaining = _kTranscriptViewportFillPageLimit;
  int? _lastViewportFillHistoryStart;

  @override
  void initState() {
    super.initState();
    _syncWindowStartIndex(forceReset: true);
    _TranscriptScrollDispatcher.instance.register(widget.session.id, this);
    // 首帧只挂最新两条；其余消息按帧补齐，正文由可见卡片申请渲染额度。
    _materializeOpenWindow();
    _syncVisibleError();
    _scheduleInitialLayoutSettle();
  }

  void _scheduleInitialLayoutSettle() {
    final generation = ++_initialLayoutSettleGeneration;
    final sessionId = widget.session.id;
    // 单调时钟：DateTime.now() 会被 NTP 校时/时区变更跳变，向前跳会提前揭示
    // 未收敛的内容，向后跳会让上限彻底失效。
    final elapsed = Stopwatch()..start();
    var framesRemaining = _transcriptInitialRevealMaxFrameCount;
    var elapsedFrames = 0;
    var stableFrames = 0;
    double? previousMaxScrollExtent;

    void reveal() {
      if (!mounted ||
          generation != _initialLayoutSettleGeneration ||
          widget.session.id != sessionId ||
          _initialRevealPhase != _TranscriptInitialRevealPhase.preparing) {
        return;
      }
      final motionSettings = openHandMotionSettingsOf(
        context,
        OpenHandMotionSettingsScope.page,
      );
      setState(() {
        if (motionSettings.exitDuration <= Duration.zero) {
          _setInitialRevealPhase(
            motionSettings.entranceDuration <= Duration.zero
                ? _TranscriptInitialRevealPhase.ready
                : _TranscriptInitialRevealPhase.revealingContent,
          );
        } else {
          _setInitialRevealPhase(
            _TranscriptInitialRevealPhase.dismissingPlaceholder,
          );
        }
      });
    }

    void settle(Duration _) {
      if (!mounted ||
          generation != _initialLayoutSettleGeneration ||
          widget.session.id != sessionId) {
        return;
      }
      if (framesRemaining <= 0) {
        reveal();
        return;
      }
      // 时长上限只结束占位等待；慢首帧仍须完成有界的尾部定位。
      if (elapsed.elapsed >= _transcriptInitialRevealMaxDuration) {
        reveal();
      }
      if (_initialRevealPhase == _TranscriptInitialRevealPhase.ready &&
          _isTranscriptScrollActive(context)) {
        return;
      }
      framesRemaining -= 1;
      elapsedFrames += 1;
      final positions = widget.controller.positions.toList(growable: false);
      if (positions.length != 1) {
        // 等待当前列表接管滚动位置，仍由帧数和时长上限约束。
        stableFrames = 0;
        WidgetsBinding.instance.addPostFrameCallback(settle);
        WidgetsBinding.instance.scheduleFrame();
        return;
      }
      final position = positions.single;
      final target = position.maxScrollExtent.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      final distance = (target - position.pixels).abs();
      final extentChanged =
          previousMaxScrollExtent != null &&
          (position.maxScrollExtent - previousMaxScrollExtent!).abs() >
              _scrollToBottomSettleTolerance;
      previousMaxScrollExtent = position.maxScrollExtent;
      // 首次定位独立于后续自动跟随开关，底部锚点不能停在消息之前。
      if (distance > _scrollToBottomSettleTolerance) {
        stableFrames = 0;
        widget.onProgrammaticScrollCorrection(() => position.jumpTo(target));
      } else if (extentChanged &&
          elapsedFrames <= _transcriptInitialRevealExtentGraceFrameCount) {
        stableFrames = 0;
      } else {
        stableFrames += 1;
      }
      final ready =
          elapsedFrames >= _transcriptInitialRevealMinimumFrameCount &&
          stableFrames >= _scrollToBottomSettleStableFrameLimit &&
          !_staggerFillActive &&
          !_viewportFillQueued;
      if (!ready && framesRemaining > 0) {
        WidgetsBinding.instance.addPostFrameCallback(settle);
        WidgetsBinding.instance.scheduleFrame();
      } else {
        reveal();
      }
    }

    WidgetsBinding.instance.addPostFrameCallback(settle);
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final activity = _maybeTranscriptScrollActivityOf(context);
    if (identical(activity, _scrollActivity)) {
      return;
    }
    _scrollActivity?.removeListener(_handleRevealScrollActivityChanged);
    _scrollActivity = activity;
    activity?.addListener(_handleRevealScrollActivityChanged);
  }

  @override
  void didUpdateWidget(covariant _SessionTranscript oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.id != widget.session.id) {
      _windowFillScheduler.clear();
      _resetSessionScopedState();
      _messageActionPanelMotionKey += 1;
      _consumedMessageActionPanelMotionKey = _messageActionPanelMotionKey;
      _TranscriptScrollDispatcher.instance.unregister(
        oldWidget.session.id,
        this,
      );
      _TranscriptScrollDispatcher.instance.register(widget.session.id, this);
      _syncWindowStartIndex(forceReset: true);
      _initialRevealPhase = _TranscriptInitialRevealPhase.preparing;
      _materializeOpenWindow();
      _scheduleInitialLayoutSettle();
    } else if (oldWidget.session.messages != widget.session.messages ||
        oldWidget.session.updatedAt != widget.session.updatedAt) {
      final previousDisplayMessages = oldWidget.session.displayMessages;
      final nextDisplayMessages = widget.session.displayMessages;
      final displayChange = widget.session.displayMessageChangeFrom(
        oldWidget.session,
      );
      final previousWindowStartIndex = _windowStartIndex;
      final prependedHistoricalMessages =
          oldWidget.session.messageLoadState ==
              AiSessionMessageLoadState.windowed &&
          widget.session.messageLoadState != AiSessionMessageLoadState.header &&
          widget.session.messageWindowStartIndex <
              oldWidget.session.messageWindowStartIndex;
      if (prependedHistoricalMessages) {
        final oldDisplayLength = previousDisplayMessages.length;
        final newDisplayLength = nextDisplayMessages.length;
        final addedDisplayCount = math.max(
          0,
          newDisplayLength - oldDisplayLength,
        );
        // 只向前展开历史，已展示的尾部始终保留。
        _windowStartIndex = TranscriptListWindowing.clampWindowStart(
          TranscriptListWindowing.windowStartAfterHistoryPrepend(
            previousWindowStart: _windowStartIndex,
            addedDisplayCount: addedDisplayCount,
          ),
          newDisplayLength,
        );
      } else {
        final oldDisplayLength = previousDisplayMessages.length;
        final newDisplayLength = nextDisplayMessages.length;
        if (newDisplayLength < oldDisplayLength) {
          final previousRange = TranscriptListWindowing.visibleRange(
            preferredStart: previousWindowStartIndex,
            messageCount: oldDisplayLength,
          );
          final previousWindowLength = math.max(
            1,
            previousRange.end - previousRange.start,
          );
          _windowStartIndex = math.max(
            0,
            newDisplayLength - previousWindowLength,
          );
        } else {
          _windowStartIndex = TranscriptListWindowing.windowStartAfterAppend(
            previousWindowStart: previousWindowStartIndex,
            messageCount: newDisplayLength,
          );
        }
      }
      final windowChanged = previousWindowStartIndex != _windowStartIndex;
      if (prependedHistoricalMessages) {
        _syncRenderEntriesAfterHistoryPrepend();
      } else if (windowChanged ||
          !_syncRenderEntriesAfterTailChange(
            displayChange,
            previousDisplayMessages,
            nextDisplayMessages,
          )) {
        _syncRenderEntries(forceReset: windowChanged);
      }
    }
    if (oldWidget.session.id != widget.session.id ||
        oldWidget.session.recentErrors != widget.session.recentErrors) {
      _syncVisibleError();
    }
  }

  void _resetSessionScopedState() {
    _initialLayoutSettleGeneration += 1;
    _selectedMessageId = null;
    _listCenterMessageId = null;
    _listAnchor = 1;
    _highlightedMessageId = null;
    _targetHighlightTimer?.cancel();
    _targetHighlightTimer = null;
    _visibleErrorId = null;
    _pendingPresentedErrorId = null;
    _dismissedErrorIds.clear();
    _cachedIndexMapSource = null;
    _cachedIndexMapWindowStart = -1;
    _cachedVisibleIndexMap = null;
    _cachedVisibleMessages = null;
    _cachedVisibleMessagesWindowStart = null;
    _cachedCreationRequestDisplaySource = null;
    _cachedCreationRequestWindowStart = null;
    _cachedCreationRequestSendPhase = null;
    _cachedCreationRequestAllowWhenIdle = null;
    _cachedCreationRequest = null;
    _cachedCreationRequestComputed = false;
    _cachedUserVisibleErrorSource = null;
    _cachedUserVisibleErrorDismissedLength = null;
    _cachedUserVisibleErrorVisibleId = null;
    _cachedUserVisibleError = null;
    _lastActiveCreationPlaceholder = null;
    _retiringCreationPlaceholder = null;
    _retiringCreationPlaceholderTimer?.cancel();
    _retiringCreationPlaceholderTimer = null;
    _bubbleRegistry.clear();
    _animatedMessageIds.clear();
    _rawContentVisibleByMessageId.clear();
    _translationCacheByMessageId.clear();
    _translationVisibleMessageIds.clear();
    _translationLoadingMessageIds.clear();
    _translationGeneration += 1;
    _cancelPendingViewportRestore();
    _prependAnchorCorrectionQueued = false;
    _activeRevealOlderFuture = null;
    _scrollRequestGeneration += 1;
    _activeScrollFuture = null;
    _activeScrollTargetId = null;
    _staggerFillGeneration += 1;
    _staggerFillActive = false;
    _viewportFillMessagesRemaining = _kTranscriptViewportFillMessageLimit;
    _viewportFillPagesRemaining = _kTranscriptViewportFillPageLimit;
    _lastViewportFillHistoryStart = null;
  }

  void _setInitialRevealPhase(_TranscriptInitialRevealPhase next) {
    if (_initialRevealPhase == next) {
      return;
    }
    final wasHidden =
        _initialRevealPhase != _TranscriptInitialRevealPhase.revealingContent &&
        _initialRevealPhase != _TranscriptInitialRevealPhase.ready;
    final nowVisible =
        next == _TranscriptInitialRevealPhase.revealingContent ||
        next == _TranscriptInitialRevealPhase.ready;
    _initialRevealPhase = next;
    if (wasHidden && nowVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pinTranscriptToLatestIfOpening();
      });
    }
  }

  void _handleInitialPlaceholderDismissed() {
    if (!mounted ||
        _initialRevealPhase !=
            _TranscriptInitialRevealPhase.dismissingPlaceholder) {
      return;
    }
    final motionSettings = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.page,
    );
    setState(() {
      _setInitialRevealPhase(
        motionSettings.entranceDuration <= Duration.zero
            ? _TranscriptInitialRevealPhase.ready
            : _TranscriptInitialRevealPhase.revealingContent,
      );
    });
  }

  void _handleInitialContentRevealed() {
    if (!mounted ||
        _initialRevealPhase != _TranscriptInitialRevealPhase.revealingContent) {
      return;
    }
    setState(() {
      _setInitialRevealPhase(_TranscriptInitialRevealPhase.ready);
    });
  }

  void _syncWindowStartIndex({bool forceReset = false}) {
    final displayMessages = widget.session.displayMessages;
    final nextWindowStartIndex = forceReset
        ? TranscriptListWindowing.initialWindowStartIndex(
            displayMessages.length,
          )
        : TranscriptListWindowing.clampWindowStart(
            _windowStartIndex,
            displayMessages.length,
          );
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
    final range = TranscriptListWindowing.visibleRange(
      preferredStart: _windowStartIndex,
      messageCount: displayMessages.length,
    );
    if (range.start == 0 && range.end == displayMessages.length) {
      return displayMessages;
    }
    return displayMessages.sublist(range.start, range.end);
  }

  void _materializeOpenWindow() {
    final visibleMessages = _visibleMessagesForWindow();
    final firstPaint = TranscriptListWindowing.initialPaintSlice(
      visibleMessages,
    );
    _replaceRenderEntries(firstPaint, animate: false);
    _listCenterMessageId ??= firstPaint.firstOrNull?.id;
    final needsFill = firstPaint.length < visibleMessages.length;
    _staggerFillActive = needsFill;
    if (needsFill) {
      _scheduleStaggeredWindowFill();
    }
    _scheduleViewportFill();
  }

  void _scheduleViewportFill() {
    if (!mounted || _viewportFillQueued) return;
    _viewportFillQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportFillQueued = false;
      if (!mounted || widget.controller.positions.length != 1) return;
      final position = widget.controller.position;
      if (!position.hasContentDimensions || position.viewportDimension <= 0) {
        return;
      }
      final history =
          _listHistoryKey.currentContext?.findRenderObject() as RenderSliver?;
      final center =
          _listCenterKey.currentContext?.findRenderObject() as RenderSliver?;
      if (center?.geometry == null) return;
      final historyExtent = history?.geometry?.scrollExtent ?? 0;
      final centerExtent = center!.geometry!.scrollExtent;
      final contentExtent = historyExtent + centerExtent;
      final underfilled = contentExtent < position.viewportDimension;
      // 没有前置历史时使用普通单向列表，锚点固定为零，避免短会话产生
      // 负向滚动范围；存在历史段时才按内容高度调整双向列表锚点。
      final hasPrecedingContent = historyExtent > precisionErrorTolerance;
      final anchor = !hasPrecedingContent
          ? 0.0
          : underfilled
          ? historyExtent / position.viewportDimension
          : 1.0;
      if ((_listAnchor - anchor).abs() > precisionErrorTolerance) {
        final correction = (anchor - _listAnchor) * position.viewportDimension;
        final nextMin = math.min(
          0.0,
          anchor * position.viewportDimension - historyExtent,
        );
        final nextMax = math.max(
          0.0,
          centerExtent - (1 - anchor) * position.viewportDimension,
        );
        // 锚点变动只重定基准，避免旧滚动坐标把长记录推离当前视口。
        final nextPixels = (position.pixels + correction).clamp(
          nextMin,
          nextMax,
        );
        position.correctPixels(nextPixels);
        setState(() => _listAnchor = anchor);
        _scheduleViewportFill();
        return;
      }
      if (_staggerFillActive ||
          _loadingOlderMessages ||
          _viewportFillMessagesRemaining <= 0 ||
          _isTranscriptScrollActive(context) ||
          position.isScrollingNotifier.value ||
          position.extentAfter > _scrollToBottomSettleTolerance) {
        return;
      }
      if (!underfilled) {
        final showSelfLearning = context
            .read<SettingsController>()
            .showSelfLearningMessages;
        final firstMessage = _renderEntries
            .where(
              (entry) =>
                  !entry.exiting &&
                  (showSelfLearning ||
                      entry.message.kind != AiSessionMessageKind.selfLearning),
            )
            .firstOrNull;
        if (firstMessage != null) {
          final top = _viewportOffsetForMessage(firstMessage.id);
          if (top == null || top <= _scrollToBottomSettleTolerance) return;
        }
      }
      if (_windowStartIndex > 0) {
        _viewportFillMessagesRemaining -= 1;
        setState(() {
          _windowStartIndex -= 1;
          _staggerFillActive = true;
        });
        _scheduleStaggeredWindowFill();
        return;
      }
      final historyStart = widget.session.messageWindowStartIndex;
      if (!widget.session.hasMoreHistoricalMessages ||
          _viewportFillPagesRemaining <= 0 ||
          (_lastViewportFillHistoryStart != null &&
              historyStart >= _lastViewportFillHistoryStart!)) {
        return;
      }
      // 自动补屏不暂停追底；失败或分页无进展时不自动重试。
      _lastViewportFillHistoryStart = historyStart;
      _viewportFillPagesRemaining -= 1;
      unawaited(_revealOlderMessages(fillViewport: true));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _scheduleStaggeredWindowFill() {
    if (!_staggerFillActive) return;
    final generation = ++_staggerFillGeneration;
    _windowFillScheduler.schedule(
      () => _staggerFillNext(generation),
      priority: true,
      isValid: () =>
          mounted && generation == _staggerFillGeneration && _staggerFillActive,
    );
  }

  void _staggerFillNext(int generation) {
    if (!mounted ||
        generation != _staggerFillGeneration ||
        !_staggerFillActive) {
      return;
    }
    final visibleMessages = _visibleMessagesForWindow();
    if (visibleMessages.isEmpty) {
      _staggerFillActive = false;
      return;
    }
    var firstPaintedIndex = -1;
    for (var index = 0; index < visibleMessages.length; index += 1) {
      if (_renderEntryIndexById.containsKey(visibleMessages[index].id)) {
        firstPaintedIndex = index;
        break;
      }
    }
    if (firstPaintedIndex <= 0) {
      _staggerFillActive = false;
      if (firstPaintedIndex < 0) {
        setState(() {
          _replaceRenderEntries(visibleMessages, animate: false);
        });
      }
      _scheduleViewportFill();
      return;
    }
    final message = visibleMessages[firstPaintedIndex - 1];
    final pinToBottom =
        _initialRevealPhase != _TranscriptInitialRevealPhase.ready;
    final anchor = pinToBottom ? null : _capturePrependAnchor();
    setState(() {
      _markMessageAnimated(message.id);
      _renderEntries = <_TranscriptRenderEntry>[
        _TranscriptRenderEntry(message: message),
        ..._renderEntries,
      ];
      _syncRenderEntryIndex();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _staggerFillGeneration) return;
      if (anchor != null) {
        _restorePrependAnchor(anchor);
      } else {
        _pinTranscriptToLatestIfOpening();
      }
    });
    if (firstPaintedIndex - 1 > 0) {
      _windowFillScheduler.schedule(
        () => _staggerFillNext(generation),
        priority: true,
        isValid: () =>
            mounted &&
            generation == _staggerFillGeneration &&
            _staggerFillActive,
      );
    } else {
      _staggerFillActive = false;
    }
    _scheduleViewportFill();
  }

  void _reconcileStaggeredRenderEntries(
    List<AiSessionMessage> visibleMessages,
  ) {
    if (visibleMessages.isEmpty) {
      _staggerFillActive = false;
      _renderEntries = const <_TranscriptRenderEntry>[];
      _syncRenderEntryIndex();
      return;
    }
    final visibleById = <String, AiSessionMessage>{
      for (final message in visibleMessages) message.id: message,
    };
    final retained = <_TranscriptRenderEntry>[
      for (final entry in _renderEntries)
        if (visibleById.containsKey(entry.id))
          identical(entry.message, visibleById[entry.id])
              ? entry
              : entry.copyWith(message: visibleById[entry.id]),
    ];
    if (retained.isEmpty) {
      _materializeOpenWindow();
      return;
    }
    final lastId = retained.last.id;
    final lastVisibleIndex = visibleMessages.indexWhere(
      (message) => message.id == lastId,
    );
    if (lastVisibleIndex >= 0) {
      for (
        var index = lastVisibleIndex + 1;
        index < visibleMessages.length;
        index += 1
      ) {
        final message = visibleMessages[index];
        _markMessageAnimated(message.id);
        retained.add(_TranscriptRenderEntry(message: message));
      }
    }
    _renderEntries = retained;
    _syncRenderEntryIndex();
  }

  void _pinTranscriptToLatestIfOpening() {
    if (!mounted || widget.controller.positions.length != 1) return;
    if (_isTranscriptScrollActive(context)) return;
    if (_initialRevealPhase == _TranscriptInitialRevealPhase.ready &&
        !_staggerFillActive) {
      return;
    }
    final position = widget.controller.position;
    widget.onProgrammaticScrollCorrection(
      () => position.jumpTo(position.maxScrollExtent),
    );
  }

  void _replaceRenderEntries(
    List<AiSessionMessage> visibleMessages, {
    bool animate = true,
  }) {
    _staggerFillGeneration += 1;
    _staggerFillActive = false;
    if (!animate) {
      for (final message in visibleMessages) {
        _markMessageAnimated(message.id);
      }
    }
    _renderEntries = <_TranscriptRenderEntry>[
      for (final message in visibleMessages)
        _TranscriptRenderEntry(message: message),
    ];
    _syncRenderEntryIndex();
  }

  void _syncRenderEntriesAfterHistoryPrepend() {
    _staggerFillGeneration += 1;
    _staggerFillActive = false;
    final visibleMessages = _visibleMessagesForWindow();
    if (_renderEntries.isEmpty || visibleMessages.isEmpty) {
      _replaceRenderEntries(visibleMessages, animate: false);
      return;
    }

    final activeEntriesById = <String, _TranscriptRenderEntry>{
      for (final entry in _renderEntries)
        if (!entry.exiting) entry.id: entry,
    };
    final nextEntries = <_TranscriptRenderEntry>[];
    var sawExistingEntry = false;
    var nonPrefixAddition = false;

    for (final message in visibleMessages) {
      final existingEntry = activeEntriesById[message.id];
      if (existingEntry != null) {
        sawExistingEntry = true;
        nextEntries.add(
          identical(existingEntry.message, message)
              ? existingEntry
              : existingEntry.copyWith(message: message),
        );
        continue;
      }
      if (sawExistingEntry) {
        nonPrefixAddition = true;
        break;
      }
      _markMessageAnimated(message.id);
      nextEntries.add(_TranscriptRenderEntry(message: message));
    }

    if (nonPrefixAddition) {
      _replaceRenderEntries(visibleMessages, animate: false);
      return;
    }

    _renderEntries = nextEntries;
    _syncRenderEntryIndex();
  }

  void _syncRenderEntryIndex() {
    _renderEntryIndexById = <String, int>{
      for (var index = 0; index < _renderEntries.length; index += 1)
        _renderEntries[index].id: index,
    };
  }

  bool _syncRenderEntriesAfterTailChange(
    AiSessionDisplayMessageChange? change,
    List<AiSessionMessage> previousMessages,
    List<AiSessionMessage> nextMessages,
  ) {
    if (change == AiSessionDisplayMessageChange.unchanged) return true;
    if (change == null ||
        _staggerFillActive ||
        _renderEntries.isEmpty ||
        previousMessages.isEmpty ||
        nextMessages.isEmpty) {
      return false;
    }
    final previousRange = TranscriptListWindowing.visibleRange(
      preferredStart: _windowStartIndex,
      messageCount: previousMessages.length,
    );
    final nextRange = TranscriptListWindowing.visibleRange(
      preferredStart: _windowStartIndex,
      messageCount: nextMessages.length,
    );
    if (previousRange.start != nextRange.start ||
        _renderEntries.length != previousRange.end - previousRange.start ||
        _renderEntries.last.exiting ||
        _renderEntries.last.id != previousMessages.last.id) {
      return false;
    }

    final nextTail = nextMessages.last;
    if (change == AiSessionDisplayMessageChange.tailReplaced) {
      if (previousMessages.length != nextMessages.length ||
          previousMessages.last.id != nextTail.id) {
        return false;
      }
      _renderEntries[_renderEntries.length - 1] = _renderEntries.last.copyWith(
        message: nextTail,
      );
    } else {
      if (nextMessages.length != previousMessages.length + 1 ||
          _renderEntryIndexById.containsKey(nextTail.id)) {
        return false;
      }
      _animatedMessageIds.remove(nextTail.id);
      _renderEntryIndexById[nextTail.id] = _renderEntries.length;
      _renderEntries.add(_TranscriptRenderEntry(message: nextTail));
    }
    _retargetTailDisplayCaches(previousMessages, nextMessages, change);
    return true;
  }

  void _retargetTailDisplayCaches(
    List<AiSessionMessage> previousMessages,
    List<AiSessionMessage> nextMessages,
    AiSessionDisplayMessageChange change,
  ) {
    if (!identical(_cachedIndexMapSource, previousMessages) ||
        _cachedIndexMapWindowStart != _windowStartIndex ||
        _cachedVisibleIndexMap == null) {
      return;
    }
    final previousVisibleLength = previousMessages.length - _windowStartIndex;
    if (_cachedVisibleIndexMap!.length != previousVisibleLength) return;

    final nextTail = nextMessages.last;
    final cachedVisibleMessages = _cachedVisibleMessages;
    final canRetargetVisibleMessages =
        _cachedVisibleMessagesWindowStart == _windowStartIndex &&
        cachedVisibleMessages != null &&
        cachedVisibleMessages.length == previousVisibleLength;
    if (change == AiSessionDisplayMessageChange.tailAppended) {
      _cachedVisibleIndexMap![nextTail.id] = previousVisibleLength;
      if (canRetargetVisibleMessages) cachedVisibleMessages.add(nextTail);
    } else if (canRetargetVisibleMessages) {
      cachedVisibleMessages[cachedVisibleMessages.length - 1] = nextTail;
    }
    _cachedIndexMapSource = nextMessages;
  }

  void _syncRenderEntries({bool forceReset = false}) {
    final visibleMessages = _visibleMessagesForWindow();
    if (_renderEntries.isEmpty) {
      _materializeOpenWindow();
      return;
    }
    if (_staggerFillActive) {
      _reconcileStaggeredRenderEntries(visibleMessages);
      return;
    }
    if (forceReset) {
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
        _syncRenderEntryIndex();
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
      _syncRenderEntryIndex();
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
    _syncRenderEntryIndex();
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
    _initialLayoutSettleGeneration += 1;
    _retiringCreationPlaceholderTimer?.cancel();
    _targetHighlightTimer?.cancel();
    _scrollActivity?.removeListener(_handleRevealScrollActivityChanged);
    _scrollActivity = null;
    _staggerFillGeneration += 1;
    _staggerFillActive = false;
    _activeRevealOlderFuture = null;
    _windowFillScheduler.clear();
    _TranscriptScrollDispatcher.instance.unregister(widget.session.id, this);
    _bubbleRegistry.clear();
    super.dispose();
  }

  /// 按 messageId 滚动到目标气泡。若目标早于 `_windowStartIndex`
  /// （被「Load earlier」窗口剪掉），就循环 reveal-older 一段一段
  /// 把窗口往前推开，直到目标进入当前布局窗口再精确滚到 alignment=0.18。
  /// 返回是否成功。
  ///
  /// 防抖：同一时刻只允许一次 in-flight 的滚动。重复点击在已有
  /// 任务进行时直接复用其 future，杜绝多次 reveal-older + ensureVisible
  /// 叠加导致的"上下抽搐"。
  Future<bool> _scrollToMessageId(String messageId, {bool highlight = false}) {
    final existing = _activeScrollFuture;
    if (existing != null && _activeScrollTargetId == messageId) {
      return existing;
    }
    final generation = ++_scrollRequestGeneration;
    final future =
        _runScrollToMessageId(
          messageId,
          highlight: highlight,
          generation: generation,
        ).whenComplete(() {
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
    required int generation,
  }) async {
    bool requestIsCurrent() =>
        mounted && generation == _scrollRequestGeneration;
    if (!requestIsCurrent()) return false;
    void flashTarget(String anchorMessageId) {
      if (!highlight || !mounted) return;
      _targetHighlightTimer?.cancel();
      setState(() => _highlightedMessageId = anchorMessageId);
      _targetHighlightTimer = startSafeTimer(
        _kTranscriptTargetHighlightDuration,
        () {
          _targetHighlightTimer = null;
          if (!mounted || _highlightedMessageId != anchorMessageId) return;
          setState(() => _highlightedMessageId = null);
        },
      );
    }

    Future<bool> tryEnsureVisible(String? anchorMessageId) async {
      if (anchorMessageId == null) return false;
      if (!requestIsCurrent()) return false;
      final ctx = _bubbleRegistry.contextOf(anchorMessageId);
      if (ctx == null) return false;
      await Scrollable.ensureVisible(
        ctx,
        alignment: 0.18,
        duration: openHandMotionDuration(
          context,
          _kTranscriptTargetScrollDuration,
        ),
        curve: _kTranscriptTargetScrollCurve,
      );
      if (!requestIsCurrent()) return false;
      flashTarget(anchorMessageId);
      return true;
    }

    String? resolveAnchor() =>
        widget.session.transcriptAnchorForRoundStarter(messageId)?.id;

    var anchorMessageId = resolveAnchor();
    if (await tryEnsureVisible(anchorMessageId)) return true;
    if (!requestIsCurrent()) return false;

    // 目标可能尚未从持久层载入，也可能只是在当前渲染窗口之前。统一通过
    // reveal-older 有界推进：先加载缺失的历史批次，再把目标纳入物化窗口。
    var display = widget.session.displayMessages;
    var targetDisplayIndex = anchorMessageId == null
        ? -1
        : display.indexWhere((m) => m.id == anchorMessageId);
    var safety = math.max(
      32,
      (math.max(widget.session.messageTotalCount, display.length) /
                      _transcriptWindowIncrement)
                  .ceil() *
              2 +
          8,
    );
    while (requestIsCurrent() && safety-- > 0) {
      final currentRange = TranscriptListWindowing.visibleRange(
        preferredStart: _windowStartIndex,
        messageCount: display.length,
      );
      final targetNeedsOlderWindow =
          targetDisplayIndex >= 0 && targetDisplayIndex < currentRange.start;
      final targetNeedsHydration =
          targetDisplayIndex < 0 && widget.session.hasMoreHistoricalMessages;
      if (targetNeedsOlderWindow || targetNeedsHydration) {
        await _revealOlderMessages();
        await _awaitEndOfFrameBounded();
      } else {
        break;
      }
      anchorMessageId = resolveAnchor();
      if (await tryEnsureVisible(anchorMessageId)) return true;
      if (!requestIsCurrent()) return false;
      display = widget.session.displayMessages;
      targetDisplayIndex = anchorMessageId == null
          ? -1
          : display.indexWhere((m) => m.id == anchorMessageId);
    }
    if (targetDisplayIndex < 0 || anchorMessageId == null) return false;
    if (await tryEnsureVisible(anchorMessageId)) return true;

    if (!_renderEntryIndexById.containsKey(anchorMessageId)) {
      final visible = _visibleMessagesForWindow();
      if (visible.any((message) => message.id == anchorMessageId)) {
        setState(() {
          _replaceRenderEntries(visible, animate: false);
        });
        await _awaitEndOfFrameBounded();
        if (await tryEnsureVisible(anchorMessageId)) return true;
        if (!requestIsCurrent()) return false;
      }
    }

    final renderIndex = _renderEntryIndexById[anchorMessageId] ?? -1;
    if (renderIndex < 0) return false;
    // 惰性列表中，目标虽然已进入 render entries，但离视口较远时尚未
    // mount，因此先按 index + 已挂载气泡高度估算滚到附近，再由
    // ensureVisible 做最后的精确落位。
    _scrollNearRenderEntryIndex(renderIndex);
    for (
      var attempt = 0;
      attempt < _kScrollToMessageMaterializeFrameLimit;
      attempt += 1
    ) {
      await _awaitEndOfFrameBounded();
      if (await tryEnsureVisible(anchorMessageId)) return true;
      if (!mounted) return false;
      if (attempt == 2) {
        _scrollNearRenderEntryIndex(renderIndex);
      }
    }
    return false;
  }

  bool _scrollNearRenderEntryIndex(int targetIndex) {
    if (!mounted ||
        targetIndex < 0 ||
        targetIndex >= _renderEntries.length ||
        !widget.controller.hasClients) {
      return false;
    }
    final position = widget.controller.position;
    final maxExtent = position.maxScrollExtent;
    final scrollExtent = maxExtent - position.minScrollExtent;
    if (scrollExtent <= 0) return false;

    double? bestTarget;
    var bestDistance = 1 << 30;
    for (final messageId in _bubbleRegistry._contexts.keys.toList(
      growable: false,
    )) {
      final index = _renderEntryIndexById[messageId];
      if (index == null) continue;
      final viewportOffset = _viewportOffsetForMessage(messageId);
      final ctx = _bubbleRegistry.contextOf(messageId);
      final box = ctx?.findRenderObject() as RenderBox?;
      if (viewportOffset == null ||
          box == null ||
          !box.attached ||
          !box.hasSize) {
        continue;
      }
      final distance = (targetIndex - index).abs();
      if (distance >= bestDistance) continue;
      final estimatedExtent = math.max(
        1.0,
        box.size.height + _kTranscriptEstimatedMessageSpacing,
      );
      bestDistance = distance;
      bestTarget =
          position.pixels +
          viewportOffset +
          (targetIndex - index) * estimatedExtent -
          position.viewportDimension * 0.18;
    }

    bestTarget ??=
        position.minScrollExtent +
        scrollExtent *
            (targetIndex / math.max(1, _renderEntries.length - 1)).clamp(
              0.0,
              1.0,
            );
    final target = bestTarget.clamp(position.minScrollExtent, maxExtent);
    if ((target - position.pixels).abs() < 1) {
      return false;
    }
    widget.onProgrammaticScrollCorrection(() {
      if (!mounted || !widget.controller.hasClients) return;
      widget.controller.position.jumpTo(target);
    });
    return true;
  }

  Future<bool>? _activeScrollFuture;
  String? _activeScrollTargetId;
  int _scrollRequestGeneration = 0;
  int _viewportRestoreGeneration = 0;

  void _handleRevealScrollActivityChanged() {
    final activity = _scrollActivity;
    if (!mounted || activity == null) {
      return;
    }
    if (activity.value) {
      _cancelPendingViewportRestore();
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
    _scheduleViewportFill();
    if (!widget.preserveViewportAfterUserScroll) return;
    final anchor = _capturePrependAnchor();
    if (anchor != null) {
      _startPrependAnchorStabilization(
        anchor,
        settleFrameCount: _postScrollContentAnchorSettleFrameCount,
      );
    }
  }

  void _cancelPendingViewportRestore() {
    _viewportRestoreGeneration += 1;
    _pendingPrependAnchor = null;
    _pendingPrependAnchorFrames = 0;
    _pendingPrependAnchorStableFrames = 0;
  }

  void _handleMessageExpansionChanged(bool expanded) {
    _cancelPendingViewportRestore();
    widget.onMessageExpansionChanged(expanded);
  }

  Future<void> _toggleMessageSpeech(
    AiSessionMessage message,
    AiTtsSettings settings,
  ) async {
    if (message.isToolMessage) return;
    final settingsController = context.read<SettingsController>();
    try {
      await widget.ttsPlaybackService.toggleMessage(
        messageId: message.id,
        text: message.content,
        settings: settings,
        availableModels: settingsController.aiModels,
        fallbackModel: _translationFallbackModel(settingsController),
      );
    } catch (error, stack) {
      silentLog('home_transcript', '切换消息播放状态', error, stack);
      if (!mounted) return;
      flashOpenHandSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '朗读失败：${_friendlyMessageActionUiError(error)}',
          en: 'Read aloud failed: ${_friendlyMessageActionUiError(error)}',
        ),
        kind: OpenHandSnackKind.error,
      );
    }
  }

  Future<void> _toggleMessageTranslation(
    AiSessionMessage message,
    AiTranslationSettings settings,
  ) async {
    if (message.isToolMessage || _messageHasMultimediaContent(message)) return;
    final sourceText = _translatableMessageText(message, settings);
    if (sourceText == null) return;
    final settingsController = context.read<SettingsController>();
    final translationGeneration = _translationGeneration;
    final fallbackModel = _translationFallbackModel(settingsController);
    final requestFingerprint = aiTranslationRequestFingerprint(
      settings,
      fallbackModel,
    );
    if (_translationVisibleMessageIds.contains(message.id)) {
      setState(() {
        _translationVisibleMessageIds.remove(message.id);
      });
      return;
    }
    final cached = _translationCacheByMessageId.get(message.id);
    if (cached != null &&
        cached.sourceText == sourceText &&
        cached.settingsFingerprint == requestFingerprint) {
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
      final result = await widget.translationService.translate(
        text: sourceText,
        settings: settings,
        availableModels: settingsController.aiModels,
        fallbackModel: fallbackModel,
      );
      if (!mounted || translationGeneration != _translationGeneration) return;
      setState(() {
        _translationCacheByMessageId.put(
          message.id,
          _MessageTranslationEntry(
            sourceText: sourceText,
            settingsFingerprint: requestFingerprint,
            translatedText: result.text,
          ),
        );
        _translationVisibleMessageIds.removeWhere(
          (id) => !_translationCacheByMessageId.containsKey(id),
        );
        _translationVisibleMessageIds.add(message.id);
      });
    } catch (error) {
      if (!mounted || translationGeneration != _translationGeneration) return;
      flashOpenHandSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '翻译失败：${_friendlyMessageActionUiError(error)}',
          en: 'Translation failed: ${_friendlyMessageActionUiError(error)}',
        ),
        kind: OpenHandSnackKind.error,
        duration: kOpenHandSnackBarNormalDuration,
      );
    } finally {
      if (mounted && translationGeneration == _translationGeneration) {
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

  Future<void> _setMessageFeedbackAnchored(
    AiSessionMessage message,
    AiSessionMessageFeedback? feedback,
  ) async {
    final anchor = _captureMessageAnchor(message.id);
    await widget.messageActions.onSetFeedback(message, feedback);
    await _restoreMessageAnchorAfterLayout(anchor);
  }

  Future<void> _selectMessageResponseVariantAnchored(
    AiSessionMessage message,
    int index,
  ) async {
    final anchor = _captureMessageAnchor(message.id);
    await widget.messageActions.onSelectResponseVariant(message, index);
    await _restoreMessageAnchorAfterLayout(
      anchor,
      stabilizeAlways: true,
      settleFrameCount: _responseVariantAnchorSettleFrameCount,
    );
  }

  _TranscriptViewportAnchor? _captureMessageAnchor(String messageId) {
    final offset = _viewportOffsetForMessage(messageId);
    if (offset == null) return null;
    return _TranscriptViewportAnchor(
      messageId: messageId,
      viewportOffset: offset,
    );
  }

  Future<void> _restoreMessageAnchorAfterLayout(
    _TranscriptViewportAnchor? anchor, {
    bool stabilizeAlways = false,
    int settleFrameCount = _transcriptPrependAnchorSettleFrameCount,
  }) async {
    if (!mounted || anchor == null) return;
    final generation = _viewportRestoreGeneration;
    final sessionId = widget.session.id;
    await _awaitEndOfFrameBounded();
    if (!mounted ||
        generation != _viewportRestoreGeneration ||
        sessionId != widget.session.id) {
      return;
    }
    final restored = _restorePrependAnchor(anchor);
    if (restored || stabilizeAlways) {
      _startPrependAnchorStabilization(
        anchor,
        settleFrameCount: settleFrameCount,
      );
    }
  }

  bool _messageHasMultimediaContent(AiSessionMessage message) {
    // 流式尾消息每次更新都是新对象，Expando 必然 miss；而流式阶段生成
    // 媒体尚未落地（TTS/翻译按钮此时也不可用），直接按 false 处理，
    // 等流结束后的稳定实例再真正计算，避免每帧对全文跑两轮正则。
    if (message.metadata[aiSessionMessageMetadataStreamingKey] == true) {
      return false;
    }
    final cached = _transcriptMultimediaContentCache[message];
    if (cached != null) return cached;
    final result = _computeMessageHasMultimediaContent(message);
    _transcriptMultimediaContentCache[message] = result;
    return result;
  }

  bool _computeMessageHasMultimediaContent(AiSessionMessage message) {
    final metadata = message.metadata;
    final attachments = AiMessageAttachment.listFromMetadata(
      metadata[aiSessionMessageAttachmentsMetadataKey],
    );
    for (final attachment in attachments) {
      if (_attachmentIsMultimedia(attachment)) {
        return true;
      }
    }

    for (final entry in _transcriptMultimediaMetadataKeys.entries) {
      if (_metadataValueHasMultimediaContent(
        metadata[entry.key],
        kindHint: entry.value,
      )) {
        return true;
      }
    }

    return _messageContentHasMultimediaLink(message.content);
  }

  /// 按 id 取消息走会话级缓存索引，TTS 播放期间每次 rebuild 不再对全部
  /// 已加载消息做线性查找。
  AiSessionMessage? _sessionMessageById(String? messageId) {
    if (messageId == null || messageId.isEmpty) return null;
    final index = widget.session.messageIndexOf(messageId);
    return index < 0 ? null : widget.session.messages[index];
  }

  bool _messageIdTargetsMultimediaContent(String? messageId) {
    final message = _sessionMessageById(messageId);
    return message != null && _messageHasMultimediaContent(message);
  }

  bool _attachmentIsMultimedia(AiMessageAttachment attachment) {
    if (attachment.kind == AiAttachmentKind.image) {
      return true;
    }
    if (_mimeTypeIsMultimedia(attachment.mimeType)) {
      return true;
    }
    return _pathIsMultimedia(attachment.storagePath) ||
        _pathIsMultimedia(attachment.originalSourcePath) ||
        _pathIsMultimedia(attachment.name);
  }

  bool _metadataValueHasMultimediaContent(
    Object? value, {
    _TranscriptMultimediaKind? kindHint,
  }) {
    if (value == null) return false;
    if (value is String) {
      return _pathIsMultimedia(value, kindHint: kindHint);
    }
    if (value is Iterable) {
      for (final item in value) {
        if (_metadataValueHasMultimediaContent(item, kindHint: kindHint)) {
          return true;
        }
      }
      return false;
    }
    if (value is Map) {
      final kind = _multimediaKindFromHint(value['kind'] ?? value['type']);
      final mime = value['mime_type'] ?? value['mime'] ?? value['content_type'];
      if (kind != null || _mimeTypeIsMultimedia(mime)) {
        return true;
      }
      for (final key in const <String>[
        'storage_path',
        'path',
        'file_path',
        'original_source_path',
        'url',
        'uri',
        'name',
        'file_name',
        'filename',
      ]) {
        if (_pathIsMultimedia(value[key], kindHint: kindHint)) {
          return true;
        }
      }
    }
    return false;
  }

  bool _messageContentHasMultimediaLink(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return false;

    if (trimmed.contains('<')) {
      for (final match in _transcriptHtmlMediaSrcPattern.allMatches(trimmed)) {
        if ((match.group(1) ?? '').trim().isNotEmpty) {
          return true;
        }
      }
    }

    if (!trimmed.contains('](') && !trimmed.contains('![')) {
      return false;
    }
    for (final match in _transcriptMarkdownMediaLinkPattern.allMatches(
      trimmed,
    )) {
      final usesImageSyntax = (match.group(1) ?? '').isNotEmpty;
      final label = (match.group(2) ?? '').trim();
      final destination = _normalizeMarkdownDestination(match.group(3) ?? '');
      if (destination.isEmpty) continue;
      if (usesImageSyntax ||
          _multimediaKindFromHint(label) != null ||
          _pathIsMultimedia(destination)) {
        return true;
      }
    }
    return false;
  }

  bool _pathIsMultimedia(Object? value, {_TranscriptMultimediaKind? kindHint}) {
    if (kindHint != null) {
      return _stringValue(value).isNotEmpty;
    }
    final text = _stringValue(value);
    if (text.isEmpty) return false;
    final parsed = Uri.tryParse(text);
    final path = parsed?.path.isNotEmpty == true ? parsed!.path : text;
    final extension = p.extension(path).toLowerCase();
    if (extension.isEmpty) {
      return false;
    }
    return aiAttachmentKindForPath(path) == AiAttachmentKind.image ||
        openHandVideoMediaExtensions.contains(extension) ||
        openHandAudioMediaExtensions.contains(extension);
  }

  bool _mimeTypeIsMultimedia(Object? value) {
    final normalized = _stringValue(value).toLowerCase();
    return isImageMimeType(normalized) ||
        isVideoMimeType(normalized) ||
        isAudioMimeType(normalized);
  }

  _TranscriptMultimediaKind? _multimediaKindFromHint(Object? value) {
    final normalized = _stringValue(value).toLowerCase();
    if (normalized.isEmpty) return null;
    if (isImageMimeType(normalized) ||
        normalized.startsWith('img/') ||
        normalized.contains('image') ||
        normalized.contains('picture') ||
        normalized.contains('photo')) {
      return _TranscriptMultimediaKind.image;
    }
    if (isVideoMimeType(normalized) ||
        normalized.contains('video') ||
        normalized.contains('movie')) {
      return _TranscriptMultimediaKind.video;
    }
    if (isAudioMimeType(normalized) ||
        normalized.contains('audio') ||
        normalized.contains('sound') ||
        normalized.contains('speech') ||
        normalized.contains('voice')) {
      return _TranscriptMultimediaKind.audio;
    }
    return _transcriptMultimediaAttachmentKindHints.contains(normalized)
        ? _TranscriptMultimediaKind.image
        : null;
  }

  String _normalizeMarkdownDestination(String value) {
    var text = value.trim();
    if (text.isEmpty) return '';
    final titleMatch = RegExp(r'''\s+["']''').firstMatch(text);
    if (titleMatch != null && titleMatch.start > 0) {
      text = text.substring(0, titleMatch.start).trim();
    }
    if ((text.startsWith('<') && text.endsWith('>')) ||
        (text.startsWith('"') && text.endsWith('"')) ||
        (text.startsWith("'") && text.endsWith("'"))) {
      text = text.substring(1, text.length - 1).trim();
    }
    return decodeUriFullOrOriginal(text);
  }

  String _stringValue(Object? value) {
    return value == null ? '' : '$value'.trim();
  }

  bool _isMessageTranslatable(
    AiSessionMessage message,
    SettingsController settings,
  ) {
    if (message.isToolMessage ||
        message.metadata[aiSessionMessageMetadataStreamingKey] == true) {
      return false;
    }
    if (_messageHasMultimediaContent(message)) {
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

  bool _messageUsesHtmlRenderer(
    AiSessionMessage message,
    SettingsController settings,
  ) {
    if (message.kind != AiSessionMessageKind.assistant) {
      return false;
    }
    final format = _messageContentFormat(message, settings);
    final cached = _transcriptHtmlRendererCache[message];
    if (cached != null && cached.format == format) {
      return cached.usesHtml;
    }
    final result = _computeMessageUsesHtmlRenderer(message, settings);
    _transcriptHtmlRendererCache[message] = _HtmlRendererCacheEntry(
      format: format,
      usesHtml: result,
    );
    return result;
  }

  bool _computeMessageUsesHtmlRenderer(
    AiSessionMessage message,
    SettingsController settings,
  ) {
    final format = _messageContentFormat(message, settings);
    if (format == AiMessageContentFormat.plainText) {
      return false;
    }
    final content =
        _parseHeAnnotation(message.content)?.strippedContent ?? message.content;
    final normalized = content.trim();
    if (normalized.isEmpty) {
      return false;
    }
    final hasHtmlLikeTags = _looksLikeHtml(normalized);
    final hasTagStructure =
        !hasHtmlLikeTags && _hasHtmlTagStructure(normalized);
    if (!hasHtmlLikeTags && !hasTagStructure) {
      return false;
    }
    if (format == AiMessageContentFormat.html) {
      return true;
    }
    return !_startsWithFencedMermaidBlock(normalized) &&
        !_containsMarkdownCodeFence(normalized);
  }

  bool _messageSupportsSpeech(
    AiSessionMessage message,
    SettingsController settings,
  ) {
    if (message.isToolMessage) return false;
    return switch (message.kind) {
      AiSessionMessageKind.user || AiSessionMessageKind.reasoning => true,
      AiSessionMessageKind.assistant =>
        _messageContentFormat(message, settings) !=
                AiMessageContentFormat.html &&
            !_messageUsesHtmlRenderer(message, settings),
      _ =>
        _messageContentFormat(message, settings) != AiMessageContentFormat.html,
    };
  }

  bool _messageIdTargetsUnsupportedSpeechContent(
    String? messageId,
    SettingsController settings,
  ) {
    final message = _sessionMessageById(messageId);
    return message != null && !_messageSupportsSpeech(message, settings);
  }

  String _friendlyMessageActionUiError(Object error) {
    final raw = error.toString().replaceFirst(RegExp(r'^[^:]+:\s*'), '');
    final normalized = collapseInlineWhitespace(raw);
    if (normalized.isEmpty) return 'unknown error';
    const maxLength = 140;
    return clipText(normalized, maxLength);
  }

  Future<void> _revealOlderMessages({bool fillViewport = false}) {
    final existing = _activeRevealOlderFuture;
    if (existing != null) {
      return existing;
    }
    late final Future<void> future;
    future = _runRevealOlderMessages(fillViewport: fillViewport).whenComplete(
      () {
        if (identical(_activeRevealOlderFuture, future)) {
          _activeRevealOlderFuture = null;
        }
      },
    );
    _activeRevealOlderFuture = future;
    return future;
  }

  Future<void> _runRevealOlderMessages({required bool fillViewport}) async {
    if (_loadingOlderMessages ||
        (_windowStartIndex <= 0 && !widget.session.hasMoreHistoricalMessages)) {
      return;
    }
    if (!fillViewport) widget.onRevealOlderMessages();

    final anchor = _capturePrependAnchor();
    final restoreGeneration = _viewportRestoreGeneration;
    final restoreSessionId = widget.session.id;
    setState(() {
      _loadingOlderMessages = true;
    });

    try {
      await Future<void>.delayed(kOpenHandFramePeriodicTimerInterval);
      if (!mounted || widget.session.id != restoreSessionId) {
        return;
      }

      if (_windowStartIndex > 0) {
        setState(() {
          _windowStartIndex = TranscriptListWindowing.clampWindowStart(
            TranscriptListWindowing.revealOlderWindowStart(_windowStartIndex),
            widget.session.displayMessages.length,
          );
          _syncRenderEntriesAfterHistoryPrepend();
        });
      } else {
        await context.read<AiSessionController>().loadOlderSessionMessages(
          widget.session.id,
        );
        if (!mounted || widget.session.id != restoreSessionId) {
          return;
        }
      }
      await _awaitEndOfFrameBounded();
      if (!mounted || widget.session.id != restoreSessionId) {
        return;
      }
      // 异步加载期间发生手动滚动或切换会话后，不再恢复旧位置。
      if (restoreGeneration != _viewportRestoreGeneration ||
          restoreSessionId != widget.session.id ||
          _isTranscriptScrollActive(context)) {
        return;
      }
      if (anchor != null) {
        _restorePrependAnchor(anchor);
        _startPrependAnchorStabilization(anchor);
      }
    } catch (error, stack) {
      silentLog('home_transcript', '显示更早消息', error, stack);
    } finally {
      if (mounted && widget.session.id == restoreSessionId) {
        await _awaitEndOfFrameBounded();
        await Future<void>.delayed(_transcriptHistoryRevealCooldown);
        if (mounted && widget.session.id == restoreSessionId) {
          setState(() {
            _loadingOlderMessages = false;
          });
          _scheduleViewportFill();
        }
      }
    }
  }

  _TranscriptViewportAnchor? _capturePrependAnchor() {
    if (!widget.controller.hasClients) return null;
    final viewportExtent = widget.controller.position.viewportDimension;
    _TranscriptViewportAnchor? best;
    var bestRank = double.infinity;
    for (final messageId in _bubbleRegistry._contexts.keys.toList(
      growable: false,
    )) {
      final offset = _viewportOffsetForMessage(messageId);
      if (offset == null) continue;
      final ctx = _bubbleRegistry.contextOf(messageId);
      final box = ctx?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached || !box.hasSize) continue;
      final bottom = offset + box.size.height;
      if (bottom <= 0 || offset >= viewportExtent) continue;
      // 仅测量已挂载卡片，优先选择视口内最靠上的完整消息。
      final rank = offset >= 0 ? offset : viewportExtent + offset.abs();
      if (rank < bestRank) {
        bestRank = rank;
        best = _TranscriptViewportAnchor(
          messageId: messageId,
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
    return _restorePrependAnchorOutcome(anchor) ==
        _AnchorRestoreOutcome.corrected;
  }

  _AnchorRestoreOutcome _restorePrependAnchorOutcome(
    _TranscriptViewportAnchor anchor,
  ) {
    if (!widget.controller.hasClients || _isTranscriptScrollActive(context)) {
      return _AnchorRestoreOutcome.unmeasurable;
    }
    final currentOffset = _viewportOffsetForMessage(anchor.messageId);
    if (currentOffset == null) {
      return _AnchorRestoreOutcome.unmeasurable;
    }
    final delta = currentOffset - anchor.viewportOffset;
    if (delta.abs() < _transcriptPrependAnchorMinCorrection) {
      return _AnchorRestoreOutcome.stable;
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
    return _AnchorRestoreOutcome.corrected;
  }

  void _startPrependAnchorStabilization(
    _TranscriptViewportAnchor anchor, {
    int settleFrameCount = _transcriptPrependAnchorSettleFrameCount,
  }) {
    _pendingPrependAnchor = anchor;
    _pendingPrependAnchorFrames = math.max(1, settleFrameCount);
    _pendingPrependAnchorStableFrames = 0;
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
      if (_isTranscriptScrollActive(context)) {
        _cancelPendingViewportRestore();
        return;
      }
      // 静默提前退出：连续多帧「实测且无需修正」说明内容高度已收敛，
      // 剩余帧预算不必再逐帧做 localToGlobal + 潜在 jumpTo。锚点暂不可
      // 测量（变体切换换体 / 气泡尚未布局 / 注册表迟到）既不算稳定也不
      // 算修正——那正是 18 帧结算窗要等待的 WebView 测高 / 图片解码
      // 场景，误计稳定会把窗口在开局两帧就掐灭。
      switch (_restorePrependAnchorOutcome(anchor)) {
        case _AnchorRestoreOutcome.corrected:
          _pendingPrependAnchorStableFrames = 0;
        case _AnchorRestoreOutcome.stable:
          _pendingPrependAnchorStableFrames += 1;
          if (_pendingPrependAnchorStableFrames >=
              _transcriptPrependAnchorStableFrameLimit) {
            _cancelPendingViewportRestore();
            return;
          }
        case _AnchorRestoreOutcome.unmeasurable:
          break;
      }
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

  /// build 路径上 memoize。按 (session.recentErrors 引用,
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

  /// build 路径上 memoize。visibleMessages 是 sublist 视图，
  /// 每次 build 都创建新 List 引用，单纯按引用比对无法命中。改用
  /// (displayMessages 引用, windowStart) 作 key 命中，sendPhase 与
  /// allowWhenIdle 作为旁路条件，避免每次 build 都反向遍历
  /// visibleMessages 找最新 user message + 检 assistant 是否已有内容。
  AiCreationRequest? _resolvePendingCreationPlaceholderCached({
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
    final clampedWindowStart = windowStart.clamp(0, displayMessages.length);
    final visibleMessages = displayMessages.sublist(clampedWindowStart);
    final result = _resolvePendingCreationPlaceholder(
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

  AiCreationRequest? _syncRetiringCreationPlaceholder({
    required AiCreationRequest? pendingRequest,
    required AiCreationRequest? failedRequest,
  }) {
    if (pendingRequest != null) {
      _lastActiveCreationPlaceholder = pendingRequest;
      _retiringCreationPlaceholder = null;
      _retiringCreationPlaceholderTimer?.cancel();
      _retiringCreationPlaceholderTimer = null;
      return null;
    }
    if (failedRequest != null) {
      _lastActiveCreationPlaceholder = null;
      _retiringCreationPlaceholder = null;
      _retiringCreationPlaceholderTimer?.cancel();
      _retiringCreationPlaceholderTimer = null;
      return null;
    }
    final last = _lastActiveCreationPlaceholder;
    if (last == null) return _retiringCreationPlaceholder;
    _lastActiveCreationPlaceholder = null;
    _retiringCreationPlaceholder = last;
    _retiringCreationPlaceholderTimer?.cancel();
    _retiringCreationPlaceholderTimer = startSafeTimer(
      _kCreationPlaceholderExitDuration,
      () {
        if (!mounted || !identical(_retiringCreationPlaceholder, last)) {
          return;
        }
        setState(() => _retiringCreationPlaceholder = null);
      },
    );
    return last;
  }

  Widget _buildTranscriptListItem({
    required BuildContext context,
    required int index,
    required AiSession session,
    required int listItemCount,
    required int hiddenLoadMoreCount,
    required int hiddenMessageCount,
    required int pendingPlaceholderCount,
    required int retiringPlaceholderCount,
    required int failureCardCount,
    required AiCreationRequest? pendingCreationRequest,
    required AiCreationRequest? retiringCreationRequest,
    required AiCreationRequest? failedCreationRequest,
    required AiSessionErrorRecord? userVisibleError,
    required bool showSelfLearningMessages,
    required List<AiSessionMessage> visibleMessages,
    required Map<String, int> visibleMessageIndexById,
    required AiTtsPlaybackSnapshot ttsSnapshot,
    required AiTtsSettings ttsSettings,
    required AiTranslationSettings translationSettings,
    required SettingsController settingsController,
    required bool telemetryDebugEnabled,
    required AiSessionController aiSessionController,
  }) {
    if (hiddenLoadMoreCount > 0 && index == 0) {
      return Padding(
        key: const ValueKey<String>(_kTranscriptLoadEarlierKey),
        padding: EdgeInsets.only(bottom: listItemCount == 1 ? 0 : 14),
        child: _TranscriptLoadEarlierButton(
          hiddenMessageCount: hiddenMessageCount,
          loading: _loadingOlderMessages,
          onPressed: _revealOlderMessages,
        ),
      );
    }
    final messageIndex = index - hiddenLoadMoreCount;
    if (messageIndex >= _renderEntries.length) {
      final afterMessagesIndex = messageIndex - _renderEntries.length;
      if (afterMessagesIndex < pendingPlaceholderCount) {
        return Padding(
          key: const ValueKey<String>(_kTranscriptPendingCreationKey),
          padding: const EdgeInsets.only(bottom: 14),
          child: _PendingCreationPlaceholderCard(
            request: pendingCreationRequest!,
          ),
        );
      }
      if (afterMessagesIndex <
          pendingPlaceholderCount + retiringPlaceholderCount) {
        return Padding(
          key: const ValueKey<String>(_kTranscriptRetiringCreationKey),
          padding: const EdgeInsets.only(bottom: 14),
          child: _PendingCreationPlaceholderCard(
            request: retiringCreationRequest!,
            exiting: true,
          ),
        );
      }
      if (afterMessagesIndex <
          pendingPlaceholderCount +
              retiringPlaceholderCount +
              failureCardCount) {
        return Padding(
          key: const ValueKey<String>(_kTranscriptCreationFailureKey),
          padding: const EdgeInsets.only(bottom: 14),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: openHandMotionDuration(
              context,
              _kTranscriptCardEntranceDuration,
            ),
            curve: kOpenHandEntranceCurve,
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
                  if (_pendingPresentedErrorId == userVisibleError.id) {
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
        key: const ValueKey<String>(_kTranscriptErrorBannerKey),
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
    if (!showSelfLearningMessages &&
        message.kind == AiSessionMessageKind.selfLearning) {
      return const SizedBox.shrink();
    }
    final visibleMessageIndex = visibleMessageIndexById[message.id];
    final isSelected = !entry.exiting && _selectedMessageId == message.id;
    final isLastVisibleMessage =
        visibleMessageIndex != null &&
        visibleMessageIndex == visibleMessages.length - 1;
    final hasLaterDisplayMessages =
        visibleMessageIndex != null &&
        visibleMessageIndex < visibleMessages.length - 1;
    final shouldAnimateAppearance =
        !entry.exiting &&
        widget.sendPhase != AiSendPhase.idle &&
        isLastVisibleMessage &&
        !_animatedMessageIds.contains(message.id);
    final hasMultimediaContent = _messageHasMultimediaContent(message);
    final speechEnabled =
        ttsSettings.enabled &&
        !hasMultimediaContent &&
        _messageSupportsSpeech(message, settingsController);
    final speechPlaying =
        speechEnabled &&
        ttsSnapshot.playing &&
        ttsSnapshot.messageId == message.id;
    final translationEntry = _translationCacheByMessageId.get(message.id);
    // 指纹计算含 JSON 编码 + SHA256 且 _translationFallbackModel 需遍历模型列表，
    // 但仅在该消息确实存在译文缓存并处于可见集合时才需要比对。放到 && 链末尾
    // 借短路求值惰性化，长会话每帧省掉每条消息一次哈希，绝大多数消息直接跳过。
    final translationVisible =
        !hasMultimediaContent &&
        translationEntry != null &&
        _translationVisibleMessageIds.contains(message.id) &&
        translationEntry.sourceText ==
            _translatableMessageText(message, translationSettings) &&
        translationEntry.settingsFingerprint ==
            aiTranslationRequestFingerprint(
              translationSettings,
              _translationFallbackModel(settingsController),
            );
    final translationLoading =
        !hasMultimediaContent &&
        _translationLoadingMessageIds.contains(message.id);
    final translationEnabled =
        translationSettings.enabled &&
        !hasMultimediaContent &&
        _isMessageTranslatable(message, settingsController);
    final isLocalSubmissionPreview =
        message.metadata[_localSubmissionPreviewMetadataKey] == true;
    final bubble = _TranscriptBubbleRegistrar(
      messageId: message.id,
      registry: _bubbleRegistry,
      onLayoutChanged: _scheduleViewportFill,
      child: _MessageBubble(
        key: ValueKey<String>(message.id),
        message: message,
        galleryImages: _galleryImages,
        sessionId: session.id,
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
        actionPanelEntranceMotionKey: _messageActionPanelMotionKey,
        animateActionPanelEntrance:
            isSelected &&
            _consumedMessageActionPanelMotionKey !=
                _messageActionPanelMotionKey,
        onActionPanelEntranceConsumed: (motionKey) {
          if (!mounted ||
              motionKey != _messageActionPanelMotionKey ||
              _consumedMessageActionPanelMotionKey == motionKey) {
            return;
          }
          _consumedMessageActionPanelMotionKey = motionKey;
        },
        isScrollHighlighted: _highlightedMessageId == message.id,
        onSelect: isLocalSubmissionPreview
            ? () {}
            : () {
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
            !isLocalSubmissionPreview &&
                !entry.exiting &&
                message.kind == AiSessionMessageKind.user
            ? () => widget.messageActions.onEdit(message)
            : null,
        onCopy: () => widget.messageActions.onCopy(message),
        onFork: () => widget.messageActions.onFork(message),
        onUserExpansionChanged: _handleMessageExpansionChanged,
        associatedKnowledgeBaseMetadata: _cachedKnowledgeBaseMetadataForMessage(
          visibleMessages: visibleMessages,
          currentIndex: visibleMessageIndex,
          message: message,
        ),
        onSetFeedback: (feedback) =>
            _setMessageFeedbackAnchored(message, feedback),
        onRegenerateResponse: () => widget.messageActions.onRegenerate(message),
        onSelectResponseVariant: (index) =>
            _selectMessageResponseVariantAnchored(message, index),
        speechEnabled: speechEnabled,
        speechPlaying: speechPlaying,
        onToggleSpeech: speechEnabled
            ? () => _toggleMessageSpeech(message, ttsSettings)
            : null,
        translationEnabled: translationEnabled,
        translationLoading: translationLoading,
        translationVisible: translationVisible,
        translatedContent: translationEntry?.translatedText,
        onToggleTranslation: translationEnabled
            ? () => _toggleMessageTranslation(message, translationSettings)
            : null,
        onDelete: () async {
          if (entry.exiting) {
            return;
          }
          await _runDeleteAction(message, widget.messageActions.onDelete);
        },
        onDeleteFromHere: !entry.exiting && hasLaterDisplayMessages
            ? () => _runDeleteAction(
                message,
                widget.messageActions.onDeleteFromHere,
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
    // 仅交互中的卡片保活，历史正文离开缓存区后交给列表回收。
    final stableBubble = _TranscriptBubbleKeepAlive(
      enabled: isSelected || speechPlaying || translationLoading,
      child: bubble,
    );
    final content = shouldAnimateAppearance
        ? SettingsAwareAppearOnce(
            child: Builder(
              builder: (context) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _markMessageAnimated(message.id);
                });
                return stableBubble;
              },
            ),
          )
        : stableBubble;
    const entrySizeDuration = Duration.zero;
    return RepaintBoundary(
      key: ValueKey<String>('$_kTranscriptEntryKeyPrefix${message.id}'),
      child: maybeAnimatedSize(
        duration: entrySizeDuration,
        curve: kCardMotionCurve,
        alignment: isSelected ? Alignment.topLeft : Alignment.bottomLeft,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: messageIndex == _renderEntries.length - 1 ? 0 : 14,
          ),
          child: content,
        ),
      ),
    );
  }

  int? _findTranscriptListChildIndex(
    Key key, {
    required int hiddenLoadMoreCount,
    required int pendingPlaceholderCount,
    required int retiringPlaceholderCount,
    required int failureCardCount,
    required int errorBannerCount,
  }) {
    if (key is! ValueKey<String>) return null;
    final value = key.value;
    if (value == _kTranscriptLoadEarlierKey) {
      return hiddenLoadMoreCount > 0 ? 0 : null;
    }

    final messageStart = hiddenLoadMoreCount;
    if (value.startsWith(_kTranscriptEntryKeyPrefix)) {
      final messageId = value.substring(_kTranscriptEntryKeyPrefix.length);
      final messageIndex = _renderEntryIndexById[messageId] ?? -1;
      return messageIndex < 0 ? null : messageStart + messageIndex;
    }

    final afterMessagesStart = messageStart + _renderEntries.length;
    if (value == _kTranscriptPendingCreationKey) {
      return pendingPlaceholderCount > 0 ? afterMessagesStart : null;
    }
    if (value == _kTranscriptRetiringCreationKey) {
      return retiringPlaceholderCount > 0
          ? afterMessagesStart + pendingPlaceholderCount
          : null;
    }
    if (value == _kTranscriptCreationFailureKey) {
      return failureCardCount > 0
          ? afterMessagesStart +
                pendingPlaceholderCount +
                retiringPlaceholderCount
          : null;
    }
    if (value == _kTranscriptErrorBannerKey) {
      return errorBannerCount > 0
          ? afterMessagesStart +
                pendingPlaceholderCount +
                retiringPlaceholderCount +
                failureCardCount
          : null;
    }
    return null;
  }

  List<AiSessionMessage> _resolveVisibleMessages(
    List<AiSessionMessage> displayMessages,
    int rangeStart,
    int rangeEnd,
  ) {
    if (rangeStart == 0 && rangeEnd == displayMessages.length) {
      return displayMessages;
    }
    if (identical(_cachedIndexMapSource, displayMessages) &&
        _cachedVisibleMessagesWindowStart == rangeStart &&
        _cachedVisibleMessages != null &&
        _cachedVisibleMessages!.length == rangeEnd - rangeStart) {
      return _cachedVisibleMessages!;
    }
    final sublist = displayMessages.sublist(rangeStart, rangeEnd);
    _cachedVisibleMessages = sublist;
    _cachedVisibleMessagesWindowStart = rangeStart;
    return sublist;
  }

  Iterable<OpenHandGalleryImage> _galleryImages() sync* {
    final session = widget.session;
    final showSelfLearning = context
        .read<SettingsController>()
        .showSelfLearningMessages;
    for (final message in session.displayMessages) {
      if (!showSelfLearning &&
          message.kind == AiSessionMessageKind.selfLearning) {
        continue;
      }
      final roots = messageFilePathRoots(
        session.environment,
        workingDirectory: _toolExecutionWorkingDirectory(message),
      );
      yield* collectOpenHandMessageImages(
        content: stripImageSummaryMarkup(message.content),
        messageId: message.id,
        onLocate: () async {
          if (!mounted || widget.session.id != session.id) return;
          await _TranscriptScrollDispatcher.instance.scrollToMessage(
            session.id,
            message.id,
            highlight: true,
          );
        },
        resolveFilePath: (uri) => _resolveGalleryImageFilePath(uri, roots),
        attachments: _cachedMessageAttachments(message)
            .where((item) => item.isImage && item.storagePath.trim().isNotEmpty)
            .map(
              (item) => OpenHandGalleryImage(
                uri: Uri.file(item.storagePath.trim()),
                title: item.name,
              ),
            ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final displayMessages = session.displayMessages;
    // 在对话范围统一订阅所需字段，避免每条消息因无关设置变化而重建。
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
    final range = TranscriptListWindowing.visibleRange(
      preferredStart: _windowStartIndex,
      messageCount: displayMessages.length,
    );
    final clampedWindowStartIndex = range.start;
    final hiddenMessageCount =
        session.hiddenHistoricalMessageCount + clampedWindowStartIndex;
    final visibleMessages = _resolveVisibleMessages(
      displayMessages,
      range.start,
      range.end,
    );
    // 数据刚完成水合时，同步建立首帧，避免空列表闪烁。
    if (_renderEntries.isEmpty && visibleMessages.isNotEmpty) {
      _materializeOpenWindow();
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
      return _WorkspaceEmptyState(
        key: ValueKey<String>('empty-session-transcript-${session.id}'),
        session: session,
      );
    }
    final hiddenLoadMoreCount = hiddenMessageCount > 0 ? 1 : 0;
    // 等待媒体生成结果时在用户消息下方展示微光占位卡片。
    final pendingCreationRequest = _resolvePendingCreationPlaceholderCached(
      displayMessages: displayMessages,
      windowStart: clampedWindowStartIndex,
      sendPhase: widget.sendPhase,
      allowWhenIdle: false,
    );
    // 媒体生成未产出内容时用失败卡片替换微光占位，并紧邻原请求展示。
    final failedCreationRequest =
        (pendingCreationRequest == null &&
            userVisibleError != null &&
            widget.sendPhase == AiSendPhase.idle)
        ? _resolvePendingCreationPlaceholderCached(
            displayMessages: displayMessages,
            windowStart: clampedWindowStartIndex,
            sendPhase: widget.sendPhase,
            allowWhenIdle: true,
          )
        : null;
    // 已展示专用失败卡片时隐藏内容相同的通用错误横幅。
    final suppressGenericErrorBanner = failedCreationRequest != null;
    final errorBannerCount =
        (userVisibleError == null || suppressGenericErrorBanner) ? 0 : 1;
    final retiringCreationRequest = _syncRetiringCreationPlaceholder(
      pendingRequest: pendingCreationRequest,
      failedRequest: failedCreationRequest,
    );
    final pendingPlaceholderCount = pendingCreationRequest == null ? 0 : 1;
    final retiringPlaceholderCount = retiringCreationRequest == null ? 0 : 1;
    final failureCardCount = failedCreationRequest == null ? 0 : 1;
    final listItemCount =
        _renderEntries.length +
        hiddenLoadMoreCount +
        errorBannerCount +
        pendingPlaceholderCount +
        retiringPlaceholderCount +
        failureCardCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ValueListenableBuilder<AiTtsPlaybackSnapshot>(
            valueListenable: widget.ttsPlaybackService.state,
            builder: (context, ttsSnapshot, _) {
              final motionSettings = openHandMotionSettingsOf(
                context,
                OpenHandMotionSettingsScope.page,
              );
              final activeTtsUnsupported =
                  ttsSnapshot.playing &&
                  (_messageIdTargetsMultimediaContent(ttsSnapshot.messageId) ||
                      _messageIdTargetsUnsupportedSpeechContent(
                        ttsSnapshot.messageId,
                        settingsController,
                      ));
              if (ttsSnapshot.playing &&
                  (!ttsSettings.enabled || activeTtsUnsupported)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  unawaited(widget.ttsPlaybackService.stop());
                });
              }
              final centerIndex =
                  _renderEntryIndexById[_listCenterMessageId] ?? 0;
              _listCenterMessageId = _renderEntries[centerIndex].id;
              final beforeCenterCount = hiddenLoadMoreCount + centerIndex;
              final hasPrecedingContent = beforeCenterCount > 0;
              int? findIndex(Key key) => _findTranscriptListChildIndex(
                key,
                hiddenLoadMoreCount: hiddenLoadMoreCount,
                pendingPlaceholderCount: pendingPlaceholderCount,
                retiringPlaceholderCount: retiringPlaceholderCount,
                failureCardCount: failureCardCount,
                errorBannerCount: errorBannerCount,
              );
              Widget buildItem(BuildContext context, int index) =>
                  _buildTranscriptListItem(
                    context: context,
                    index: index,
                    session: session,
                    listItemCount: listItemCount,
                    hiddenLoadMoreCount: hiddenLoadMoreCount,
                    hiddenMessageCount: hiddenMessageCount,
                    pendingPlaceholderCount: pendingPlaceholderCount,
                    retiringPlaceholderCount: retiringPlaceholderCount,
                    failureCardCount: failureCardCount,
                    pendingCreationRequest: pendingCreationRequest,
                    retiringCreationRequest: retiringCreationRequest,
                    failedCreationRequest: failedCreationRequest,
                    userVisibleError: userVisibleError,
                    showSelfLearningMessages: showSelfLearningMessages,
                    visibleMessages: visibleMessages,
                    visibleMessageIndexById: visibleMessageIndexById,
                    ttsSnapshot: ttsSnapshot,
                    ttsSettings: ttsSettings,
                    translationSettings: translationSettings,
                    settingsController: settingsController,
                    telemetryDebugEnabled: telemetryDebugEnabled,
                    aiSessionController: aiSessionController,
                  );
              final transcriptList = OpenHandSafeScrollbar(
                controller: widget.controller,
                thickness: _kTranscriptScrollbarThickness,
                radius: _kTranscriptScrollbarRadius,
                stabilizeMetrics: true,
                child: NotificationListener<ScrollMetricsNotification>(
                  onNotification: (notification) {
                    if (notification.depth != 0) return false;
                    // 历史正文延迟就绪也会增高；沿用首页的用户滚动保护。
                    widget.onLayoutChanged();
                    _scheduleViewportFill();
                    return false;
                  },
                  child: NotificationListener<ScrollNotification>(
                    onNotification: widget.onScrollNotification,
                    child: CustomScrollView(
                      scrollCacheExtent: const ScrollCacheExtent.pixels(
                        _kTranscriptListCacheExtent,
                      ),
                      key: const ValueKey<String>('session-transcript-list'),
                      controller: widget.controller,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      physics: kOpenHandClampingPhysics,
                      primary: false,
                      center: hasPrecedingContent ? _listCenterKey : null,
                      anchor: hasPrecedingContent ? _listAnchor : 0,
                      slivers: [
                        // 历史向负方向增长，不改动当前消息的布局坐标。
                        if (beforeCenterCount > 0)
                          SliverList(
                            key: _listHistoryKey,
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => buildItem(
                                context,
                                beforeCenterCount - index - 1,
                              ),
                              childCount: beforeCenterCount,
                              addRepaintBoundaries: false,
                              findChildIndexCallback: (key) {
                                final index = findIndex(key);
                                return index != null &&
                                        index < beforeCenterCount
                                    ? beforeCenterCount - index - 1
                                    : null;
                              },
                            ),
                          ),
                        SliverPadding(
                          key: _listCenterKey,
                          padding: const EdgeInsets.only(bottom: 12),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) =>
                                  buildItem(context, beforeCenterCount + index),
                              childCount: listItemCount - beforeCenterCount,
                              addRepaintBoundaries: false,
                              findChildIndexCallback: (key) {
                                final index = findIndex(key);
                                return index != null &&
                                        index >= beforeCenterCount
                                    ? index - beforeCenterCount
                                    : null;
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
              final revealPhase = _initialRevealPhase;
              final contentVisible =
                  revealPhase ==
                      _TranscriptInitialRevealPhase.revealingContent ||
                  revealPhase == _TranscriptInitialRevealPhase.ready;
              final placeholderMounted =
                  revealPhase == _TranscriptInitialRevealPhase.preparing ||
                  revealPhase ==
                      _TranscriptInitialRevealPhase.dismissingPlaceholder;
              return Stack(
                fit: StackFit.expand,
                children: [
                  IgnorePointer(
                    ignoring:
                        revealPhase != _TranscriptInitialRevealPhase.ready,
                    child: ExcludeSemantics(
                      excluding:
                          revealPhase != _TranscriptInitialRevealPhase.ready,
                      child: AnimatedOpacity(
                        opacity: contentVisible ? 1 : 0,
                        duration: motionSettings.entranceDuration,
                        curve: motionSettings.curve.curve,
                        onEnd: _handleInitialContentRevealed,
                        child: transcriptList,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: placeholderMounted
                          ? AnimatedOpacity(
                              opacity:
                                  revealPhase ==
                                      _TranscriptInitialRevealPhase.preparing
                                  ? 1
                                  : 0,
                              duration: motionSettings.exitDuration,
                              curve: motionSettings.curve.reverseCurve,
                              onEnd: _handleInitialPlaceholderDismissed,
                              child: _TranscriptHydratingPlaceholder(
                                key: ValueKey<String>(
                                  'preparing-transcript-${widget.session.id}',
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TranscriptLoadEarlierButton extends StatefulWidget {
  const _TranscriptLoadEarlierButton({
    required this.hiddenMessageCount,
    required this.loading,
    required this.onPressed,
  });

  final int hiddenMessageCount;
  final bool loading;
  final Future<void> Function() onPressed;

  @override
  State<_TranscriptLoadEarlierButton> createState() =>
      _TranscriptLoadEarlierButtonState();
}

class _TranscriptLoadEarlierButtonState
    extends State<_TranscriptLoadEarlierButton> {
  bool _pressing = false;

  Future<void> _handlePressed() async {
    if (_pressing || widget.loading) return;
    setState(() => _pressing = true);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) {
        setState(() => _pressing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final loading = widget.loading || _pressing;
    final label = openHandLocalizedText(
      context,
      zh: loading ? '加载更早消息中...' : '加载更早消息（${widget.hiddenMessageCount}）',
      en: loading
          ? 'Loading earlier messages...'
          : 'Load earlier messages (${widget.hiddenMessageCount})',
    );
    return Center(
      child: OutlinedButton.icon(
        onPressed: loading ? null : () => unawaited(_handlePressed()),
        icon: OpenHandBusyStatusIcon(
          busy: loading,
          icon: Icons.history_rounded,
        ),
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
    final label = openHandLocalizedText(
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
          kOpenHandGap14,
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
    if (!openHandTickerMotionEnabled(context)) {
      return body;
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: openHandMotionDuration(context, kOpenHandMotion220),
      curve: kOpenHandSwitchInCurve,
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
  const _SessionErrorBanner({
    super.key,
    required this.error,
    required this.onDismiss,
  });

  final AiSessionErrorRecord error;
  final VoidCallback onDismiss;

  @override
  State<_SessionErrorBanner> createState() => _SessionErrorBannerState();
}

class _SessionErrorBannerState extends State<_SessionErrorBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _fade;
  late final Animation<Offset> _slide;
  late final Animation<double> _scale;
  bool _exiting = false;
  bool _entranceStarted = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: kOpenHandMotion340,
      reverseDuration: kOpenHandMotion220,
    );
    _fade = CurvedAnimation(
      parent: _controller,
      curve: kOpenHandSwitchInCurve,
      reverseCurve: kOpenHandSwitchOutCurve,
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.12),
      end: Offset.zero,
    ).animate(_fade);
    _scale = Tween<double>(begin: 0.96, end: 1).animate(_fade);
  }

  /// 进出场时长跟随全局动效设置：关闭动效时直接置零，横幅瞬时出现/消失。
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motionEnabled = openHandTickerMotionEnabled(context);
    _controller.duration = motionEnabled ? kOpenHandMotion340 : Duration.zero;
    _controller.reverseDuration = motionEnabled
        ? kOpenHandMotion220
        : Duration.zero;
    if (!motionEnabled) {
      _controller.value = _exiting ? 0 : 1;
      _entranceStarted = true;
    } else if (!_entranceStarted) {
      _entranceStarted = true;
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleDismiss() async {
    if (_exiting) return;
    _exiting = true;
    try {
      await _controller.reverse().orCancel;
    } on TickerCanceled {
      // 卸载或禁用动效会取消 Ticker；只在组件仍存在时提交关闭。
    }
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
        borderRadius: kOpenHandBorderRadius16,
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
              kOpenHandHGap10,
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
                    kOpenHandGap4,
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
              kOpenHandHGap4,
              OpenHandTapRegion(
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
            kOpenHandGap8,
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: OpenHandTapRegion(
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
                    kOpenHandHGap5,
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
        opacity: OpenHandBoundedDoubleAnimation(_fade),
        child: ScaleTransition(scale: _scale, child: banner),
      ),
    );
  }
}

Map<String, Object?>? _cachedKnowledgeBaseMetadataForMessage({
  required List<AiSessionMessage> visibleMessages,
  required int? currentIndex,
  required AiSessionMessage message,
}) {
  if (message.kind != AiSessionMessageKind.assistant) return null;
  // 流式尾消息每次更新都是新对象且气泡在流式期间不展示知识库引用，
  // 直接短路，避免每帧全文引用匹配 + 无效缓存写入。
  if (message.metadata[aiSessionMessageMetadataStreamingKey] == true) {
    return null;
  }
  // 直接元数据结果对同一消息恒定，按对象缓存。
  final cached = _knowledgeBaseDirectMetadataCache[message];
  if (cached != null) return cached.value;
  final result = _associatedKnowledgeBaseMetadataForMessage(
    visibleMessages: visibleMessages,
    currentIndex: currentIndex,
    message: message,
  );
  // 仅缓存非 null 结果，避免 null 与未缓存歧义。
  _knowledgeBaseDirectMetadataCache[message] = _KnowledgeBaseMetadataCacheEntry(
    result,
  );
  return result;
}

Map<String, Object?>? _associatedKnowledgeBaseMetadataForMessage({
  required List<AiSessionMessage> visibleMessages,
  required int? currentIndex,
  required AiSessionMessage message,
}) {
  if (message.kind != AiSessionMessageKind.assistant) return null;
  final directMetadata = KnowledgeMessageMetadata.fromMessageMetadata(
    message.metadata,
  );
  final directUsedMetadata = _knowledgeBaseMetadataUsedByAnswer(
    directMetadata,
    message.content,
  );
  if (directUsedMetadata != null) {
    return directUsedMetadata;
  }
  if (currentIndex == null || currentIndex <= 0) return null;
  final roundMessages = <AiSessionMessage>[];
  for (var index = currentIndex - 1; index >= 0; index--) {
    final candidate = visibleMessages[index];
    if (candidate.kind == AiSessionMessageKind.user) {
      final metadata = KnowledgeMessageMetadata.fromMessageMetadata(
        candidate.metadata,
      );
      final usedMetadata = _knowledgeBaseMetadataUsedByAnswer(
        metadata,
        message.content,
      );
      if (usedMetadata != null) return usedMetadata;
      break;
    }
    if (candidate.kind == AiSessionMessageKind.assistant &&
        candidate.content.trim().isNotEmpty) {
      break;
    }
    roundMessages.insert(0, candidate);
  }
  return _knowledgeBaseMetadataFromRoundToolMessages(
    roundMessages,
    message.content,
  );
}

AiCreationRequest? _resolvePendingCreationPlaceholder({
  required List<AiSessionMessage> visibleMessages,
  required AiSendPhase sendPhase,
  bool allowWhenIdle = false,
}) {
  if (sendPhase == AiSendPhase.idle && !allowWhenIdle) return null;
  if (visibleMessages.isEmpty) return null;
  // 反向查找最近一条开启新轮次的用户消息。
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
  // 仅图片、视频和音频模式展示动画占位；深度研究使用普通流式文本。
  if (request.mode == AiCreationMode.deepResearch) return null;
  return request;
}

class _PendingCreationPlaceholderCard extends StatefulWidget {
  const _PendingCreationPlaceholderCard({
    required this.request,
    this.exiting = false,
  });

  final AiCreationRequest request;
  final bool exiting;

  @override
  State<_PendingCreationPlaceholderCard> createState() =>
      _PendingCreationPlaceholderCardState();
}

class _PendingCreationPlaceholderCardState
    extends State<_PendingCreationPlaceholderCard>
    with SingleTickerProviderStateMixin {
  static const Duration _motionDuration = kOpenHandMotion1400;

  late final AnimationController _motionController = AnimationController(
    vsync: this,
    duration: _motionDuration,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotionPreference();
  }

  @override
  void dispose() {
    _motionController.dispose();
    super.dispose();
  }

  void _syncMotionPreference() {
    if (!openHandTickerMotionEnabled(context)) {
      _motionController.stop();
      _motionController.value = 0;
    } else if (!_motionController.isAnimating) {
      _motionController.repeat();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final baseColor = isDark
        ? cs.surfaceContainerHigh
        : Color.alphaBlend(
            cs.onSurfaceVariant.withValues(alpha: 0.045),
            cs.surfaceContainerHighest,
          );
    final borderColor = cs.outlineVariant.withValues(
      alpha: isDark ? 0.32 : 0.22,
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
    final label = openHandLocalizedText(context, zh: labelZh, en: labelEn);
    final motionEnabled = openHandTickerMotionEnabled(context);
    const cardRadius = kOpenHandBorderRadius26;
    final content = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _motionController,
            builder: (context, child) {
              final scale = !motionEnabled
                  ? 1.0
                  : 1.0 +
                        math.sin(_motionController.value * math.pi * 2) * 0.018;
              final opacity = !motionEnabled
                  ? 0.68
                  : 0.62 +
                        (math.sin(_motionController.value * math.pi * 2) + 1) *
                            0.07;
              return Transform.scale(
                scale: scale,
                child: _GeneratingMediaIndicator(
                  icon: icon,
                  progress: !motionEnabled ? 0 : _motionController.value,
                  color: cs.onSurfaceVariant,
                  surfaceColor: baseColor,
                  isDark: isDark,
                  iconOpacity: opacity,
                  animate: motionEnabled,
                ),
              );
            },
          ),
          kOpenHandGap12,
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
    // 静态层（外壳阴影 / 首尾渐变 / 光斑本体）提前构建一次：等待期可达
    // 分钟级，逐帧重建这些装饰对象只产生 GC 压力。每帧真正变化的只有
    // 漂移光晕的圆心与光斑的位移缩放。
    final shellDecoration = BoxDecoration(
      borderRadius: cardRadius,
      border: Border.all(color: borderColor),
      color: baseColor,
      boxShadow: [
        BoxShadow(
          color: Colors.white.withValues(alpha: isDark ? 0.025 : 0.20),
          offset: const Offset(0, 1),
          spreadRadius: -1,
        ),
        BoxShadow(
          color: cs.shadow.withValues(alpha: isDark ? 0.12 : 0.06),
          blurRadius: 30,
          offset: const Offset(0, 12),
        ),
      ],
    );
    final topGradientLayer = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: !motionEnabled ? 0.055 : 0.12),
            Colors.white.withValues(alpha: !motionEnabled ? 0.018 : 0.04),
            cs.onSurfaceVariant.withValues(
              alpha: !motionEnabled ? 0.024 : 0.065,
            ),
          ],
          stops: const [0.0, 0.44, 1.0],
        ),
      ),
    );
    final glowOrb = DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0.18, 0.18),
          radius: 0.52,
          colors: [
            Colors.white.withValues(alpha: isDark ? 0.035 : 0.085),
            cs.onSurfaceVariant.withValues(alpha: isDark ? 0.018 : 0.026),
            Colors.transparent,
          ],
          stops: const [0.0, 0.46, 1.0],
        ),
      ),
    );
    final bottomGradientLayer = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomRight,
          end: Alignment.topLeft,
          colors: [
            cs.onSurfaceVariant.withValues(
              alpha: !motionEnabled
                  ? (isDark ? 0.02 : 0.026)
                  : (isDark ? 0.034 : 0.045),
            ),
            Colors.transparent,
          ],
          stops: const [0.0, 0.62],
        ),
      ),
    );
    // RepaintBoundary 把每帧重绘限制在本卡片图层内，避免与相邻列表项
    // 合并重绘。
    final card = Align(
      alignment: Alignment.centerLeft,
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: cardRadius,
          child: DecoratedBox(
            decoration: shellDecoration,
            child: SizedBox(
              width: 280,
              height: 220,
              child: AnimatedBuilder(
                animation: _motionController,
                child: content,
                builder: (context, child) {
                  final phase = !motionEnabled ? 0.0 : _motionController.value;
                  final drift = math.sin(phase * math.pi * 2);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      topGradientLayer,
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: Alignment(
                              !motionEnabled ? -0.42 : -0.42 + drift * 0.08,
                              !motionEnabled ? -0.52 : -0.52 + drift * 0.04,
                            ),
                            radius: 0.82,
                            colors: [
                              Colors.white.withValues(
                                alpha: !motionEnabled
                                    ? (isDark ? 0.035 : 0.075)
                                    : (isDark ? 0.052 : 0.11),
                              ),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 1.0],
                          ),
                        ),
                      ),
                      Transform.translate(
                        offset: !motionEnabled
                            ? Offset.zero
                            : Offset(drift * 7, -drift * 4),
                        child: Transform.scale(
                          scale: !motionEnabled ? 1 : 1.0 + drift.abs() * 0.035,
                          child: glowOrb,
                        ),
                      ),
                      bottomGradientLayer,
                      child ?? const SizedBox.shrink(),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    if (!motionEnabled) return card;
    return TweenAnimationBuilder<double>(
      key: ValueKey<String>(
        'pending-creation-${widget.request.mode.name}-${widget.exiting ? 'exit' : 'enter'}',
      ),
      tween: Tween<double>(begin: 0, end: 1),
      duration: widget.exiting
          ? _kCreationPlaceholderExitDuration
          : _kTranscriptCardEntranceDuration,
      curve: widget.exiting ? kOpenHandSwitchOutCurve : kOpenHandEntranceCurve,
      builder: (context, raw, child) {
        final t = raw.clamp(0.0, 1.0);
        final visible = widget.exiting ? 1 - t : t;
        final dy = widget.exiting ? -8.0 * t : 10.0 * (1 - t);
        final scale = widget.exiting ? 1.0 - 0.035 * t : 0.965 + 0.035 * t;
        return ClipRect(
          child: Align(
            alignment: Alignment.topLeft,
            heightFactor: visible,
            child: Opacity(
              opacity: visible,
              child: Transform.translate(
                offset: Offset(0, dy),
                child: Transform.scale(
                  alignment: Alignment.centerLeft,
                  scale: scale,
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
      child: card,
    );
  }
}

class _GeneratingMediaIndicator extends StatelessWidget {
  const _GeneratingMediaIndicator({
    required this.icon,
    required this.progress,
    required this.color,
    required this.surfaceColor,
    required this.isDark,
    required this.iconOpacity,
    required this.animate,
  });

  final IconData icon;
  final double progress;
  final Color color;
  final Color surfaceColor;
  final bool isDark;
  final double iconOpacity;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 70,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(0, -0.12),
                  radius: 0.82,
                  colors: [
                    Colors.white.withValues(alpha: isDark ? 0.08 : 0.44),
                    surfaceColor.withValues(alpha: 0.58),
                    color.withValues(alpha: isDark ? 0.05 : 0.035),
                  ],
                  stops: const [0.0, 0.64, 1.0],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: isDark ? 0.03 : 0.32),
                    offset: const Offset(0, 1),
                    spreadRadius: -1,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: isDark ? 0.16 : 0.045,
                    ),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _GeneratingMediaRingPainter(
                progress: progress,
                color: color,
                isDark: isDark,
                animate: animate,
              ),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: color.withValues(alpha: isDark ? 0.11 : 0.08),
                  ),
                ),
              ),
            ),
          ),
          Icon(icon, size: 34, color: color.withValues(alpha: iconOpacity)),
        ],
      ),
    );
  }
}

class _GeneratingMediaRingPainter extends CustomPainter {
  const _GeneratingMediaRingPainter({
    required this.progress,
    required this.color,
    required this.isDark,
    required this.animate,
  });

  final double progress;
  final Color color;
  final bool isDark;
  final bool animate;

  /// 渐变着色器按 (尺寸, 颜色, 亮暗) 缓存：渐变本体与进度无关，旋转由
  /// canvas 变换承担，避免生成等待期间每帧 createShader 的引擎对象churn。
  static final Map<int, Shader> _sweepShaderCache = <int, Shader>{};
  static const int _sweepShaderCacheLimit = 8;

  Shader _sweepShaderFor(Rect rect) {
    final key = Object.hash(rect.width, rect.height, color.toARGB32(), isDark);
    final cached = _sweepShaderCache[key];
    if (cached != null) return cached;
    final shader = SweepGradient(
      startAngle: -math.pi / 2,
      endAngle: math.pi * 1.5,
      colors: [
        Colors.transparent,
        color.withValues(alpha: isDark ? 0.12 : 0.10),
        color.withValues(alpha: isDark ? 0.46 : 0.52),
        Colors.white.withValues(alpha: isDark ? 0.36 : 0.70),
        color.withValues(alpha: isDark ? 0.18 : 0.16),
        Colors.transparent,
      ],
      stops: const [0.0, 0.24, 0.46, 0.56, 0.72, 1.0],
    ).createShader(rect);
    if (_sweepShaderCache.length >= _sweepShaderCacheLimit) {
      _sweepShaderCache.remove(_sweepShaderCache.keys.first);
    }
    _sweepShaderCache[key] = shader;
    return shader;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 2.2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: isDark ? 0.17 : 0.13);
    canvas.drawCircle(center, radius, basePaint);

    final rotation = animate ? progress * math.pi * 2 : 0.0;
    final activePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round
      ..shader = _sweepShaderFor(rect);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawCircle(center, radius, activePaint);
    canvas.restore();

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: isDark ? 0.18 : 0.42);
    canvas.drawArc(
      rect,
      rotation - math.pi / 2,
      math.pi * 0.42,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GeneratingMediaRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.isDark != isDark ||
        oldDelegate.animate != animate;
  }
}

/// 多媒体生成失败且没有助手正文时展示的错误卡片。
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
  late final CurvedAnimation _fade;
  late final Animation<Offset> _slide;
  late final Animation<double> _scale;
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _kTranscriptCardEntranceDuration,
      reverseDuration: _kCreationFailureExitDuration,
    );
    _fade = CurvedAnimation(
      parent: _controller,
      curve: kOpenHandEntranceCurve,
      reverseCurve: kOpenHandSwitchOutCurve,
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.08),
      end: Offset.zero,
    ).animate(_fade);
    _scale = Tween<double>(begin: 0.94, end: 1).animate(_fade);
    _controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!openHandTickerMotionEnabled(context)) {
      _controller.value = _exiting ? 0 : 1;
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleDismiss() async {
    if (_exiting) return;
    _exiting = true;
    if (openHandTickerMotionEnabled(context)) {
      try {
        await _controller.reverse().orCancel;
      } on TickerCanceled {
        // 卸载或禁用动效时结束等待。
      }
    }
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
    final title = openHandLocalizedText(context, zh: titleZh, en: titleEn);
    final card = Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
          decoration: BoxDecoration(
            color: cs.errorContainer.withValues(alpha: 0.55),
            borderRadius: kOpenHandBorderRadius20,
            border: Border.all(color: cs.error.withValues(alpha: 0.35)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 22, color: cs.onErrorContainer),
              kOpenHandHGap12,
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
                    kOpenHandGap4,
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
              kOpenHandHGap8,
              IconButton(
                key: ValueKey<String>(
                  'creation-failure-dismiss-${widget.error.id}',
                ),
                onPressed: _handleDismiss,
                tooltip: openHandDismissLabel(context),
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
    if (!openHandTickerMotionEnabled(context)) {
      return card;
    }
    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: OpenHandBoundedDoubleAnimation(_fade),
        child: ScaleTransition(scale: _scale, child: card),
      ),
    );
  }
}
