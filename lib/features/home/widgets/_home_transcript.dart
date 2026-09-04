part of '../openhand_home_page.dart';

const Duration _kTranscriptCardEntranceDuration = kOpenHandMotion420;
const Duration _kCreationPlaceholderExitDuration = kOpenHandMotion260;
const Duration _kCreationFailureExitDuration = kOpenHandMotion240;
// 视口外预物化范围。含 HTML WebView 卡片的会话对 cacheExtent 极敏感——
// 过大时滚动会在视口外同步挂载多个平台视图，直接拖垮帧率。
// 280 约等于 2~3 条富文本气泡高度，兼顾预渲染与帧预算。
const double _kTranscriptListCacheExtent = 280;
const double _kTranscriptScrollbarThickness = 6;
const Radius _kTranscriptScrollbarRadius = kOpenHandPillRadius;
const double _kTranscriptEstimatedMessageSpacing = 14;
const int _kScrollToMessageMaterializeFrameLimit = 8;
const Duration _kTranscriptTargetScrollDuration = kOpenHandMotion520;
const Duration _kTranscriptTargetHighlightDuration = Duration(
  milliseconds: 1400,
);
const Curve _kTranscriptTargetScrollCurve = Cubic(0.22, 0.92, 0.28, 1);
const String _kTranscriptEntryKeyPrefix = 'transcript-entry-';
const String _kTranscriptLoadEarlierKey = 'transcript-load-earlier';
const String _kTranscriptReturnLatestKey = 'transcript-return-latest';
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

/// 消息是否走 HTML WebView 渲染器的判定缓存。结果只取决于消息内容
///（不可变），按对象缓存避免每帧对每条可见消息重复正则扫描。
final Expando<bool> _transcriptHtmlRendererCache = Expando<bool>(
  'transcriptHtmlRenderer',
);

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
class _TranscriptHtmlKeepAlive extends StatefulWidget {
  const _TranscriptHtmlKeepAlive({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  State<_TranscriptHtmlKeepAlive> createState() =>
      _TranscriptHtmlKeepAliveState();
}

class _TranscriptHtmlKeepAliveState extends State<_TranscriptHtmlKeepAlive>
    with AutomaticKeepAliveClientMixin<_TranscriptHtmlKeepAlive> {
  @override
  bool get wantKeepAlive => widget.enabled;

  @override
  void didUpdateWidget(covariant _TranscriptHtmlKeepAlive oldWidget) {
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
    required this.liveRuntimeToolPreview,
    required this.sendPhase,
    required this.planTimelineCollapsed,
    required this.onPlanTimelineCollapsedChanged,
    required this.onLayoutChanged,
    required this.onMessageExpansionChanged,
    required this.preserveViewportAfterUserScroll,
    required this.onRevealOlderMessages,
    required this.onProgrammaticScrollCorrection,
    required this.messageActions,
    required this.ttsPlaybackService,
    required this.translationService,
    required this.onDismissError,
    this.jumpToBottomOnInit = false,
    this.fileExplorerVisible = false,
    this.onFileExplorerToggled,
    this.machineTerminalPanelVisible = false,
    this.onMachineTerminalPanelToggled,
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
  final ValueChanged<bool> onMessageExpansionChanged;
  final bool preserveViewportAfterUserScroll;
  final VoidCallback onRevealOlderMessages;
  final void Function(VoidCallback correction) onProgrammaticScrollCorrection;
  final _MessageActions messageActions;
  final AiTtsPlaybackService ttsPlaybackService;
  final AiTranslationService translationService;
  final Future<void> Function(AiSessionErrorRecord error) onDismissError;
  // 首帧直接跳到底部，避免加载会话时出现从顶部滚入的动画。
  final bool jumpToBottomOnInit;
  final bool fileExplorerVisible;
  final VoidCallback? onFileExplorerToggled;
  final bool machineTerminalPanelVisible;
  final VoidCallback? onMachineTerminalPanelToggled;
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
  _PendingRevealRestore? _pendingRevealRestore;
  Future<void>? _activeRevealOlderFuture;
  int _initialLayoutSettleGeneration = 0;
  _TranscriptInitialRevealPhase _initialRevealPhase =
      _TranscriptInitialRevealPhase.preparing;

  ThemeData? _warmupTheme;
  SettingsController? _warmupSettings;
  bool _warmupDependenciesReady = false;
  final _FrameTaskScheduler _warmupScheduler = _FrameTaskScheduler(
    maxPerFrame: _transcriptWarmupMaxPerFrame,
  );
  int _warmupGeneration = 0;
  int? _warmupContextSignature;
  final Set<int> _warmupSignatures = <int>{};
  final Queue<int> _warmupSignatureOrder = Queue<int>();
  bool _isHoldingOpenFirstPaint = true;
  int _windowExpandGeneration = 0;

  @override
  void initState() {
    super.initState();
    _syncWindowStartIndex(forceReset: true);
    _TranscriptScrollDispatcher.instance.register(widget.session.id, this);
    // 首帧仅渲染活动窗口尾部，其余行后续逐帧展开，避免同时挂载大量富文本卡片。
    _materializeOpenWindow(progressive: true);
    _syncVisibleError();
    _scheduleInitialLayoutSettle(pinToBottom: widget.jumpToBottomOnInit);
  }

  void _scheduleInitialLayoutSettle({required bool pinToBottom}) {
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
      if (framesRemaining <= 0 ||
          elapsed.elapsed >= _transcriptInitialRevealMaxDuration) {
        reveal();
        return;
      }
      framesRemaining -= 1;
      elapsedFrames += 1;
      final positions = widget.controller.positions.toList(growable: false);
      if (positions.length != 1) {
        stableFrames = 0;
        WidgetsBinding.instance.addPostFrameCallback(settle);
        return;
      }
      final position = positions.single;
      final target = position.maxScrollExtent
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      final distance = (target - position.pixels).abs();
      final extentChanged =
          previousMaxScrollExtent != null &&
          (position.maxScrollExtent - previousMaxScrollExtent!).abs() >
              _scrollToBottomSettleTolerance;
      previousMaxScrollExtent = position.maxScrollExtent;
      if (pinToBottom && distance > _scrollToBottomSettleTolerance) {
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
          stableFrames >= _scrollToBottomSettleStableFrameLimit;
      if (!ready && framesRemaining > 0) {
        WidgetsBinding.instance.addPostFrameCallback(settle);
      } else {
        reveal();
      }
    }

    WidgetsBinding.instance.addPostFrameCallback(settle);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _warmupTheme = Theme.of(context);
    _warmupSettings ??= context.read<SettingsController>();
    _warmupDependenciesReady = _warmupSettings != null;
    final activity = _maybeTranscriptScrollActivityOf(context);
    if (identical(activity, _scrollActivity)) {
      _warmCurrentRenderEntriesIfReady();
      return;
    }
    _scrollActivity?.removeListener(_handleRevealScrollActivityChanged);
    _scrollActivity = activity;
    activity?.addListener(_handleRevealScrollActivityChanged);
    _warmCurrentRenderEntriesIfReady();
  }

  @override
  void didUpdateWidget(covariant _SessionTranscript oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.id != widget.session.id) {
      _warmupGeneration += 1;
      _warmupContextSignature = null;
      _warmupScheduler.clear();
      _clearWarmupSignatures();
      _resetSessionScopedState();
      _messageActionPanelMotionKey += 1;
      _consumedMessageActionPanelMotionKey = _messageActionPanelMotionKey;
      _TranscriptScrollDispatcher.instance.unregister(
        oldWidget.session.id,
        this,
      );
      _TranscriptScrollDispatcher.instance.register(widget.session.id, this);
      _syncWindowStartIndex(forceReset: true);
      _renderEntries = const <_TranscriptRenderEntry>[];
      _renderEntryIndexById = const <String, int>{};
      _initialRevealPhase = _TranscriptInitialRevealPhase.preparing;
      _scheduleInitialLayoutSettle(pinToBottom: widget.jumpToBottomOnInit);
      // 双兜底物化：在 mount 状态变化或父级帧抢占
      // `addPostFrameCallback` 时，仅 build 阶段 fallback 仍可能错过
      // 第一帧（同步赋值发生在 Element rebuild，但首帧是当前 frame
      // 之前已 schedule）。`endOfFrame` 在当前帧结束后再尝试一次，
      // 形成「post-frame → endOfFrame → build fallback」三重保险。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_renderEntries.isNotEmpty) return;
        setState(() {
          _materializeOpenWindow(progressive: true);
        });
      });
      unawaited(
        _awaitEndOfFrameBounded().then((_) {
          if (!mounted || _renderEntries.isNotEmpty) return;
          setState(() {
            _materializeOpenWindow(progressive: true);
          });
        }),
      );
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
        // 展示更早切片时保留原尾部，并滑动有界实体化窗口以限制组件数量。
        _windowStartIndex = TranscriptListWindowing.clampWindowStart(
          TranscriptListWindowing.windowStartAfterHistoryPrepend(
            previousWindowStart: _windowStartIndex,
            addedDisplayCount: addedDisplayCount,
          ),
          newDisplayLength,
        );
      } else {
        final oldDisplayLength = oldWidget.session.displayMessages.length;
        final newDisplayLength = widget.session.displayMessages.length;
        if (newDisplayLength < oldDisplayLength) {
          final previousRange = TranscriptListWindowing.boundedRange(
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
            previousMessageCount: oldDisplayLength,
            messageCount: newDisplayLength,
          );
        }
      }
      final windowChanged = previousWindowStartIndex != _windowStartIndex;
      if (prependedHistoricalMessages) {
        _syncRenderEntriesAfterHistoryPrepend();
      } else {
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
    _isHoldingOpenFirstPaint = true;
    _windowExpandGeneration += 1;
  }

  void _setInitialRevealPhase(_TranscriptInitialRevealPhase next) {
    if (_initialRevealPhase == next) {
      return;
    }
    _initialRevealPhase = next;
    if (next == _TranscriptInitialRevealPhase.ready) {
      _scheduleProgressiveWindowExpansion();
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
    final preferred = forceReset
        ? TranscriptListWindowing.initialWindowStartIndex(
            displayMessages.length,
          )
        : TranscriptListWindowing.clampWindowStart(
            _windowStartIndex,
            displayMessages.length,
          );
    // 每次构建均限制实体化范围，使富文本渲染成本不随会话总消息数增长。
    final nextWindowStartIndex = forceReset
        ? TranscriptListWindowing.cappedWindowStart(
            preferredWindowStart: preferred,
            messageCount: displayMessages.length,
          )
        : preferred;
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
    final range = TranscriptListWindowing.boundedRange(
      preferredStart: _windowStartIndex,
      messageCount: displayMessages.length,
    );
    if (range.start == 0 && range.end == displayMessages.length) {
      return displayMessages;
    }
    return displayMessages.sublist(range.start, range.end);
  }

  int _activeRenderCount() {
    var count = 0;
    for (final entry in _renderEntries) {
      if (!entry.exiting) count += 1;
    }
    return count;
  }

  List<AiSessionMessage> _messagesToMaterialize() {
    final window = _visibleMessagesForWindow();
    if (!_isHoldingOpenFirstPaint) {
      return window;
    }
    final painted = _activeRenderCount();
    final cap = painted <= 0
        ? TranscriptListWindowing.openFirstPaintCount(window.length)
        : math.min(window.length, painted);
    return TranscriptListWindowing.tailSlice(window, cap);
  }

  bool _transcriptIsNearBottom() {
    if (!widget.controller.hasClients || widget.controller.positions.isEmpty) {
      return true;
    }
    final position = widget.controller.positions.last;
    return (position.maxScrollExtent - position.pixels).abs() <=
        _autoFollowResumeDistance;
  }

  void _releaseOpenFirstPaintHold() {
    _isHoldingOpenFirstPaint = false;
    _windowExpandGeneration += 1;
  }

  void _materializeOpenWindow({required bool progressive}) {
    final visibleMessages = _visibleMessagesForWindow();
    if (!progressive ||
        visibleMessages.length <= _transcriptOpenFirstPaintCap) {
      _isHoldingOpenFirstPaint = false;
      _replaceRenderEntries(visibleMessages, animate: false);
      return;
    }
    _isHoldingOpenFirstPaint = true;
    _replaceRenderEntries(
      TranscriptListWindowing.tailSlice(
        visibleMessages,
        TranscriptListWindowing.openFirstPaintCount(visibleMessages.length),
      ),
      animate: false,
    );
  }

  void _scheduleProgressiveWindowExpansion() {
    if (!_isHoldingOpenFirstPaint) {
      return;
    }
    final generation = ++_windowExpandGeneration;
    final sessionId = widget.session.id;
    var stepsRemaining = TranscriptListWindowing.defaultMaxMaterializedWindow;
    void expand() {
      if (!mounted ||
          generation != _windowExpandGeneration ||
          widget.session.id != sessionId ||
          !_isHoldingOpenFirstPaint ||
          _initialRevealPhase != _TranscriptInitialRevealPhase.ready) {
        return;
      }
      if (_isTranscriptScrollActive(context)) {
        return;
      }
      final fullWindow = _visibleMessagesForWindow();
      final currentCount = _activeRenderCount();
      if (fullWindow.length <= currentCount) {
        _isHoldingOpenFirstPaint = false;
        return;
      }
      if (stepsRemaining <= 0) {
        setState(() {
          _replaceRenderEntries(fullWindow, animate: false);
          _isHoldingOpenFirstPaint = false;
        });
        return;
      }
      stepsRemaining -= 1;
      final nextCount = TranscriptListWindowing.progressiveRenderCount(
        currentCount: currentCount,
        targetCount: fullWindow.length,
      );
      if (nextCount <= currentCount) {
        _isHoldingOpenFirstPaint = false;
        return;
      }
      final nextMessages = TranscriptListWindowing.tailSlice(
        fullWindow,
        nextCount,
      );
      final pinToBottom = _transcriptIsNearBottom();
      final anchor = pinToBottom ? null : _capturePrependAnchor();
      setState(() {
        _replaceRenderEntries(nextMessages, animate: false);
        if (nextCount >= fullWindow.length) {
          _isHoldingOpenFirstPaint = false;
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _windowExpandGeneration) {
          return;
        }
        if (pinToBottom &&
            widget.controller.hasClients &&
            widget.controller.positions.isNotEmpty) {
          final position = widget.controller.positions.last;
          widget.onProgrammaticScrollCorrection(
            () => position.jumpTo(position.maxScrollExtent),
          );
        } else if (anchor != null) {
          _restorePrependAnchor(anchor);
        }
        if (_isHoldingOpenFirstPaint) {
          expand();
        }
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => expand());
  }

  void _replaceRenderEntries(
    List<AiSessionMessage> visibleMessages, {
    bool animate = true,
  }) {
    _scheduleWarmRichRenderEntries(visibleMessages);
    if (!animate) {
      _animatedMessageIds.addAll(visibleMessages.map((message) => message.id));
    }
    _renderEntries = <_TranscriptRenderEntry>[
      for (final message in visibleMessages)
        _TranscriptRenderEntry(message: message),
    ];
    _syncRenderEntryIndex();
  }

  void _syncRenderEntriesAfterHistoryPrepend() {
    _releaseOpenFirstPaintHold();
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
    final addedMessages = <AiSessionMessage>[];
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
      _animatedMessageIds.add(message.id);
      addedMessages.add(message);
      nextEntries.add(_TranscriptRenderEntry(message: message));
    }

    if (nonPrefixAddition) {
      _replaceRenderEntries(visibleMessages, animate: false);
      return;
    }

    _scheduleWarmRichRenderEntries(addedMessages);
    _renderEntries = nextEntries;
    _syncRenderEntryIndex();
  }

  void _syncRenderEntryIndex() {
    _renderEntryIndexById = <String, int>{
      for (var index = 0; index < _renderEntries.length; index += 1)
        _renderEntries[index].id: index,
    };
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
    // 只有预热上下文（会话 / 主题 / HTML 降级策略）真的变了才作废已排队任务。
    // 渐进首屏会先排尾部、两帧后再排整窗；此前无条件 clear 会把尚未跑完的
    // 尾部预热直接丢掉，而签名去重又保证它们不会被重新排队——用户正在看的
    // 那几条反而永远失去预热，落到滚动时同步解析。
    // 判定必须在去重之前：否则「签名全部命中 → warmMessages 为空 → 早退」
    // 会让主题切换后的上下文签名永远更新不了，队列继续用旧主题预热。
    // 作废队列时必须一并清空签名集合，否则被丢弃的那批消息因签名仍在，
    // 永远不会被重新排队。
    final warmContext = Object.hash(
      session.id,
      theme.hashCode,
      settings.aiHtmlRenderFallback,
    );
    if (warmContext != _warmupContextSignature) {
      _warmupContextSignature = warmContext;
      _warmupGeneration += 1;
      _warmupScheduler.clear();
      _clearWarmupSignatures();
    }
    final generation = _warmupGeneration;
    final staged = visibleMessages;
    final warmCount = math.min(
      staged.length,
      TranscriptListWindowing.warmupMessageBudget(),
    );
    final warmMessages = <(AiSessionMessage, int)>[];
    var warmCharacters = 0;
    var htmlWarmups = 0;
    for (
      var index = staged.length - 1;
      index >= 0 && warmMessages.length < warmCount;
      index -= 1
    ) {
      final message = staged[index];
      if (message.metadata[aiSessionMessageContentPreviewMetadataKey] == true) {
        continue;
      }
      final usesHtml = _messageUsesHtmlRenderer(message, settings);
      if (usesHtml && htmlWarmups >= _transcriptHtmlWarmupMaxPerPass) {
        continue;
      }
      if (warmMessages.isNotEmpty &&
          warmCharacters >= _transcriptWarmupCharacterBudget) {
        break;
      }
      final signature = _warmupSignatureFor(message, settings);
      if (!_rememberWarmupSignature(signature)) {
        continue;
      }
      warmMessages.add((message, signature));
      warmCharacters += math.min(
        math.max(1, message.content.length),
        _transcriptWarmupCharacterBudget,
      );
      if (usesHtml) {
        htmlWarmups += 1;
      }
    }
    if (warmMessages.isEmpty) {
      return;
    }
    final orderedWarmMessages = warmMessages.reversed.toList(growable: false);
    for (final (message, signature) in orderedWarmMessages) {
      _warmupScheduler.schedule(() {
        if (!mounted ||
            generation != _warmupGeneration ||
            widget.session.id != session.id) {
          return;
        }
        // 队列不再被无条件裁剪，改为在执行时校验消息仍在当前物化窗口内，
        // 避免翻页/快速滚动后陈旧任务挤占帧预算、把刚进入视口的消息排到后面。
        // 丢弃时必须撤销签名，否则消息滚回视口后会被去重挡住，永远失去预热。
        if (!_renderEntryIndexById.containsKey(message.id)) {
          _forgetWarmupSignature(signature);
          return;
        }
        _warmRichRenderForMessage(
          session: session,
          message: message,
          theme: theme,
          settings: settings,
        );
      }, onDropped: () => _forgetWarmupSignature(signature));
    }
  }

  int _warmupSignatureFor(
    AiSessionMessage message,
    SettingsController settings,
  ) {
    return Object.hash(
      message.id,
      message.kind,
      message.content.length,
      boundedTextFingerprint(message.content),
      _messageContentFormat(message, settings),
      settings.aiHtmlRenderFallback,
    );
  }

  bool _rememberWarmupSignature(int signature) {
    if (_warmupSignatures.contains(signature)) {
      return false;
    }
    _warmupSignatures.add(signature);
    _warmupSignatureOrder.add(signature);
    while (_warmupSignatureOrder.length >
        _transcriptWarmupSignatureCacheLimit) {
      final oldest = _warmupSignatureOrder.removeFirst();
      _warmupSignatures.remove(oldest);
    }
    return true;
  }

  void _forgetWarmupSignature(int signature) {
    if (!_warmupSignatures.remove(signature)) return;
    _warmupSignatureOrder.remove(signature);
  }

  void _clearWarmupSignatures() {
    _warmupSignatures.clear();
    _warmupSignatureOrder.clear();
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
          data: TranscriptListWindowing.boundedContentPreview(
            normalizedContent,
            maxCharacters: _markdownCollapsedPreviewMaxChars,
          ),
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
          data: TranscriptListWindowing.boundedContentPreview(
            normalizedContent,
            maxCharacters: _markdownCollapsedPreviewMaxChars,
          ),
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

    final hasHtmlLikeTags = _looksLikeHtml(normalizedContent);
    final hasTagStructure =
        !hasHtmlLikeTags && _hasHtmlTagStructure(normalizedContent);
    final containsMarkdownFence =
        _startsWithFencedMermaidBlock(normalizedContent.trim()) ||
        _containsMarkdownCodeFence(normalizedContent.trim());

    void warmMarkdownBody() {
      final shouldWarmPreview = _messageShouldCollapse(
        normalizedContent,
        charThreshold: isToolResult
            ? _toolResultMarkdownCollapseCharThreshold
            : _messageMarkdownCollapseCharThreshold,
        lineThreshold: isToolResult
            ? _toolResultMarkdownCollapseLineThreshold
            : _messageMarkdownCollapseLineThreshold,
      );
      _warmMarkdownRenderPath(
        data: shouldWarmPreview
            ? TranscriptListWindowing.boundedContentPreview(
                normalizedContent,
                maxCharacters: _markdownCollapsedPreviewMaxChars,
              )
            : normalizedContent,
        parseKey: shouldWarmPreview ? '$parseKey|message-preview' : parseKey,
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
          // 预热 prepared LRU（嗅探 + 自愈 + 预览文本）；高度只能由
          // WebView 测高回调写入，预热阶段无事可做。
          _preparedHtmlRenderDataFor(normalizedContent);
          return;
        }
        if (settings.aiHtmlRenderFallback == AiHtmlRenderFallback.markdown) {
          warmMarkdownBody();
        }
        return;
      case AiMessageContentFormat.markdown:
        if (!containsMarkdownFence && (hasHtmlLikeTags || hasTagStructure)) {
          _preparedHtmlRenderDataFor(normalizedContent);
          return;
        }
        warmMarkdownBody();
        return;
    }
  }

  void _syncRenderEntries({bool forceReset = false}) {
    final visibleMessages = _messagesToMaterialize();
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
    _warmupGeneration += 1;
    _activeRevealOlderFuture = null;
    _warmupScheduler.clear();
    _windowExpandGeneration += 1;
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
      final currentRange = TranscriptListWindowing.boundedRange(
        preferredStart: _windowStartIndex,
        messageCount: display.length,
      );
      final targetNeedsOlderWindow =
          targetDisplayIndex >= 0 && targetDisplayIndex < currentRange.start;
      final targetNeedsNewerWindow =
          targetDisplayIndex >= currentRange.end &&
          targetDisplayIndex < display.length;
      final targetNeedsHydration =
          targetDisplayIndex < 0 && widget.session.hasMoreHistoricalMessages;
      if (targetNeedsNewerWindow) {
        final nextStart = math.min(
          targetDisplayIndex,
          TranscriptListWindowing.latestWindowStart(display.length),
        );
        if (nextStart != _windowStartIndex) {
          setState(() {
            _releaseOpenFirstPaintHold();
            _windowStartIndex = nextStart;
            _replaceRenderEntries(_visibleMessagesForWindow(), animate: false);
          });
        }
        await _awaitEndOfFrameBounded();
      } else if (targetNeedsOlderWindow || targetNeedsHydration) {
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
    if (maxExtent <= 0) return false;

    double? bestTarget;
    var bestDistance = 1 << 30;
    for (var index = 0; index < _renderEntries.length; index += 1) {
      final entry = _renderEntries[index];
      if (entry.exiting) continue;
      final viewportOffset = _viewportOffsetForMessage(entry.id);
      final ctx = _bubbleRegistry.contextOf(entry.id);
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
        maxExtent *
        (targetIndex / math.max(1, _renderEntries.length - 1)).clamp(0.0, 1.0);
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

  void _handleRevealScrollActivityChanged() {
    final activity = _scrollActivity;
    if (!mounted || activity == null) {
      return;
    }
    if (activity.value) {
      _cancelPendingViewportRestore();
      return;
    }
    if (_isHoldingOpenFirstPaint &&
        _initialRevealPhase == _TranscriptInitialRevealPhase.ready) {
      _scheduleProgressiveWindowExpansion();
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
    final pending = _pendingRevealRestore;
    if (pending == null) {
      if (!widget.preserveViewportAfterUserScroll) return;
      final anchor = _capturePrependAnchor();
      if (anchor != null) {
        _startPrependAnchorStabilization(
          anchor,
          settleFrameCount: _postScrollContentAnchorSettleFrameCount,
        );
      }
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

  void _cancelPendingViewportRestore() {
    _pendingRevealRestore = null;
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
    if (_messageHasMultimediaContent(message)) return;
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
            provider: result.provider,
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
    await _awaitEndOfFrameBounded();
    if (!mounted) return;
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

    final lower = trimmed.toLowerCase();
    if (lower.contains('<img') ||
        lower.contains('<video') ||
        lower.contains('<audio')) {
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
    if (message.metadata[aiSessionMessageMetadataStreamingKey] == true) {
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
    // 仅当消息自身存储了格式标记时缓存才安全，否则结果依赖全局设置。
    final hasStoredFormat =
        message.metadata[aiSessionMessageContentFormatKey] is String;
    if (hasStoredFormat) {
      final cached = _transcriptHtmlRendererCache[message];
      if (cached != null) return cached;
    }
    final result = _computeMessageUsesHtmlRenderer(message, settings);
    if (hasStoredFormat) {
      _transcriptHtmlRendererCache[message] = result;
    }
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

  Future<void> _revealOlderMessages() {
    final existing = _activeRevealOlderFuture;
    if (existing != null) {
      return existing;
    }
    late final Future<void> future;
    future = _runRevealOlderMessages().whenComplete(() {
      if (identical(_activeRevealOlderFuture, future)) {
        _activeRevealOlderFuture = null;
      }
    });
    _activeRevealOlderFuture = future;
    return future;
  }

  void _showLatestWindow() {
    final displayCount = widget.session.displayMessages.length;
    final nextStart = TranscriptListWindowing.latestWindowStart(displayCount);
    if (nextStart == _windowStartIndex) return;
    setState(() {
      _releaseOpenFirstPaintHold();
      _windowStartIndex = nextStart;
      _replaceRenderEntries(_visibleMessagesForWindow(), animate: false);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.controller.hasClients) return;
      final position = widget.controller.position;
      widget.onProgrammaticScrollCorrection(
        () => position.jumpTo(position.maxScrollExtent),
      );
    });
  }

  Future<void> _runRevealOlderMessages() async {
    if (_loadingOlderMessages ||
        (_windowStartIndex <= 0 && !widget.session.hasMoreHistoricalMessages)) {
      return;
    }
    widget.onRevealOlderMessages();

    // 保存滚动指标以便恢复视觉位置。
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
    var revealStarted = false;
    setState(() {
      _loadingOlderMessages = true;
    });
    revealStarted = true;

    try {
      await Future<void>.delayed(kOpenHandFramePeriodicTimerInterval);
      if (!mounted) {
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
        if (!mounted) {
          return;
        }
      }
      await _awaitEndOfFrameBounded();
      if (!mounted) {
        return;
      }
      if (preserveTriggerOffset && hadClients) {
        final position = scrollController.positions.isNotEmpty
            ? scrollController.positions.last
            : null;
        final scrollActive = _isTranscriptScrollActive(context);
        if (position != null &&
            !scrollActive &&
            !position.isScrollingNotifier.value) {
          final target = previousPixels.clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          );
          if ((target - position.pixels).abs() >=
              _transcriptPrependAnchorMinCorrection) {
            widget.onProgrammaticScrollCorrection(
              () => position.jumpTo(target),
            );
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
            widget.onProgrammaticScrollCorrection(
              () => position.jumpTo(target),
            );
          }
        }
      }
    } catch (error, stack) {
      silentLog('home_transcript', '显示更早消息', error, stack);
    } finally {
      if (revealStarted && mounted) {
        await _awaitEndOfFrameBounded();
        await Future<void>.delayed(_transcriptHistoryRevealCooldown);
        if (mounted) {
          setState(() {
            _loadingOlderMessages = false;
          });
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
      if (offset >= 0) {
        // 条目按视觉顺序排列：首个顶部落在视口内的气泡即最优锚点，
        // 其后偏移只会更大，无需继续对剩余窗口做 localToGlobal 测量。
        return _TranscriptViewportAnchor(
          messageId: entry.id,
          viewportOffset: offset,
        );
      }
      // 负偏移（顶部在视口上方）作兜底，取最靠近视口顶的一个。
      final rank = viewportExtent + offset.abs();
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
    required int returnLatestCount,
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
      if (afterMessagesIndex < returnLatestCount) {
        return Padding(
          key: const ValueKey<String>(_kTranscriptReturnLatestKey),
          padding: const EdgeInsets.only(bottom: 14),
          child: Center(
            child: FilledButton.tonalIcon(
              onPressed: _showLatestWindow,
              icon: const Icon(Icons.south_rounded, size: 18),
              label: Text(
                openHandLocalizedText(
                  context,
                  zh: '返回最新消息',
                  en: 'Return to latest',
                ),
              ),
            ),
          ),
        );
      }
      final afterWindowControlsIndex = afterMessagesIndex - returnLatestCount;
      if (afterWindowControlsIndex < pendingPlaceholderCount) {
        return Padding(
          key: const ValueKey<String>(_kTranscriptPendingCreationKey),
          padding: const EdgeInsets.only(bottom: 14),
          child: _PendingCreationPlaceholderCard(
            request: pendingCreationRequest!,
          ),
        );
      }
      if (afterWindowControlsIndex <
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
      if (afterWindowControlsIndex <
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
        (visibleMessageIndex < visibleMessages.length - 1 ||
            returnLatestCount > 0);
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
    final keepHtmlBubbleAlive =
        !entry.exiting &&
        isSelected &&
        _messageUsesHtmlRenderer(message, settingsController);
    final bubble = _TranscriptBubbleRegistrar(
      messageId: message.id,
      registry: _bubbleRegistry,
      child: _MessageBubble(
        key: ValueKey<String>(message.id),
        message: message,
        sessionId: session.id,
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
        onEdit: !entry.exiting && message.kind == AiSessionMessageKind.user
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
    final stableBubble = _TranscriptHtmlKeepAlive(
      enabled: keepHtmlBubbleAlive,
      child: bubble,
    );
    final content = shouldAnimateAppearance
        ? SettingsAwareAppearOnce(
            child: Builder(
              builder: (context) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _animatedMessageIds.add(message.id);
                });
                return stableBubble;
              },
            ),
          )
        : stableBubble;
    const entrySizeDuration = Duration.zero;
    return RepaintBoundary(
      child: maybeAnimatedSize(
        key: ValueKey<String>('$_kTranscriptEntryKeyPrefix${message.id}'),
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
    required int returnLatestCount,
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
    if (value == _kTranscriptReturnLatestKey) {
      return returnLatestCount > 0 ? afterMessagesStart : null;
    }
    final afterWindowControlsStart = afterMessagesStart + returnLatestCount;
    if (value == _kTranscriptPendingCreationKey) {
      return pendingPlaceholderCount > 0 ? afterWindowControlsStart : null;
    }
    if (value == _kTranscriptRetiringCreationKey) {
      return retiringPlaceholderCount > 0
          ? afterWindowControlsStart + pendingPlaceholderCount
          : null;
    }
    if (value == _kTranscriptCreationFailureKey) {
      return failureCardCount > 0
          ? afterWindowControlsStart +
                pendingPlaceholderCount +
                retiringPlaceholderCount
          : null;
    }
    if (value == _kTranscriptErrorBannerKey) {
      return errorBannerCount > 0
          ? afterWindowControlsStart +
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
    final range = TranscriptListWindowing.boundedRange(
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
    // build-stage 同步首屏 fallback：
    // 当 didUpdateWidget 把 `_renderEntries` 重置为空、且 post-frame
    // callback 因 mount 抖动尚未触发时，直接同步物化首屏，避免
    // 「displayMessages 非空 → empty short-circuit」连续 K 帧白屏。
    // 注意：build 中不允许 setState，但 _replaceRenderEntries 仅做
    // 字段赋值（与 didUpdateWidget 内的同名调用一致），赋值后
    // 当前帧即拿到新 `_renderEntries` 用于绘制，不破坏 build 不变量。
    if (_renderEntries.isEmpty && visibleMessages.isNotEmpty) {
      // 构建阶段仅同步实体化首帧尾部，其余有界窗口由渐进任务补齐。
      _materializeOpenWindow(progressive: true);
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
    final returnLatestCount = range.end < displayMessages.length ? 1 : 0;
    // 等待媒体生成结果时在用户消息下方展示微光占位卡片。
    final pendingCreationRequest = returnLatestCount == 0
        ? _resolvePendingCreationPlaceholderCached(
            session: session,
            displayMessages: displayMessages,
            windowStart: clampedWindowStartIndex,
            sendPhase: widget.sendPhase,
            allowWhenIdle: false,
          )
        : null;
    // 媒体生成未产出内容时用失败卡片替换微光占位，并紧邻原请求展示。
    final failedCreationRequest =
        (returnLatestCount == 0 &&
            pendingCreationRequest == null &&
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
        returnLatestCount +
        errorBannerCount +
        pendingPlaceholderCount +
        retiringPlaceholderCount +
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
          machineTerminalPanelVisible: widget.machineTerminalPanelVisible,
          onMachineTerminalPanelToggled: widget.onMachineTerminalPanelToggled,
          activeProfile: widget.activeProfile,
          claudeStyle: widget.claudeStyle,
        ),
        kOpenHandGap14,
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
              final transcriptList = OpenHandSafeScrollbar(
                controller: widget.controller,
                thickness: _kTranscriptScrollbarThickness,
                radius: _kTranscriptScrollbarRadius,
                stabilizeMetrics: true,
                child: NotificationListener<ScrollNotification>(
                  onNotification: widget.onScrollNotification,
                  child: ListView.builder(
                    scrollCacheExtent: const ScrollCacheExtent.pixels(
                      _kTranscriptListCacheExtent,
                    ),
                    key: const ValueKey<String>('session-transcript-list'),
                    controller: widget.controller,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.only(bottom: 12),
                    physics: kOpenHandClampingPhysics,
                    primary: false,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: false,
                    itemCount: listItemCount,
                    findChildIndexCallback: (key) =>
                        _findTranscriptListChildIndex(
                          key,
                          hiddenLoadMoreCount: hiddenLoadMoreCount,
                          returnLatestCount: returnLatestCount,
                          pendingPlaceholderCount: pendingPlaceholderCount,
                          retiringPlaceholderCount: retiringPlaceholderCount,
                          failureCardCount: failureCardCount,
                          errorBannerCount: errorBannerCount,
                        ),
                    itemBuilder: (context, index) => _buildTranscriptListItem(
                      context: context,
                      index: index,
                      session: session,
                      listItemCount: listItemCount,
                      hiddenLoadMoreCount: hiddenLoadMoreCount,
                      returnLatestCount: returnLatestCount,
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

class _PendingRevealRestore {
  const _PendingRevealRestore({required this.targetPixels});

  final double targetPixels;
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
  late final Animation<double> _fade;
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
    if (_entranceStarted) return;
    _entranceStarted = true;
    if (motionEnabled) {
      _controller.forward();
    } else {
      _controller.value = 1;
    }
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
        opacity: _fade,
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
  required AiSession session,
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
  late final Animation<double> _fade;
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
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleDismiss() async {
    if (_exiting) return;
    _exiting = true;
    if (openHandTickerMotionEnabled(context)) {
      await _controller.reverse();
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
        opacity: _fade,
        child: ScaleTransition(scale: _scale, child: card),
      ),
    );
  }
}
