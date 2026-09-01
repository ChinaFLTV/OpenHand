part of '../openhand_home_page.dart';

/// 专家请求卡按不可变消息对象缓存，可空结果用哨兵区分未缓存状态。
const Object _kExpertRequestCardNullSentinel = Object();
final Expando<Object> _machineExpertRequestCardCache = Expando<Object>(
  'machineExpertRequestCard',
);
final Expando<Object> _webReverseRequestCardCache = Expando<Object>(
  'webReverseRequestCard',
);
final Expando<Object> _androidReverseRequestCardCache = Expando<Object>(
  'androidReverseRequestCard',
);

T? _cachedExpertRequestCard<T extends Object>(
  Expando<Object> cache,
  AiSessionMessage message,
  T? Function() compute,
) {
  final existing = cache[message];
  if (existing != null) {
    return identical(existing, _kExpertRequestCardNullSentinel)
        ? null
        : existing as T;
  }
  final computed = compute();
  cache[message] = computed ?? _kExpertRequestCardNullSentinel;
  return computed;
}

AiMachineExpertRequestCard? _machineExpertRequestCardFor(
  AiSessionMessage message,
) {
  if (message.kind != AiSessionMessageKind.user) return null;
  return _cachedExpertRequestCard(
    _machineExpertRequestCardCache,
    message,
    () =>
        AiMachineExpertRequestCard.fromMetadata(
          message.metadata[aiSessionMachineExpertRequestCardMetadataKey],
        ) ??
        AiMachineExpertRequestCard.fromPrompt(message.content),
  );
}

AiWebReverseRequestCard? _webReverseRequestCardFor(AiSessionMessage message) {
  if (message.kind != AiSessionMessageKind.user) return null;
  return _cachedExpertRequestCard(
    _webReverseRequestCardCache,
    message,
    () =>
        AiWebReverseRequestCard.fromMetadata(
          message.metadata[aiSessionWebReverseRequestCardMetadataKey],
        ) ??
        AiWebReverseRequestCard.fromPrompt(message.content),
  );
}

AiAndroidReverseRequestCard? _androidReverseRequestCardFor(
  AiSessionMessage message,
) {
  if (message.kind != AiSessionMessageKind.user) return null;
  return _cachedExpertRequestCard(
    _androidReverseRequestCardCache,
    message,
    () =>
        AiAndroidReverseRequestCard.fromMetadata(
          message.metadata[aiSessionAndroidReverseRequestCardMetadataKey],
        ) ??
        AiAndroidReverseRequestCard.fromPrompt(message.content),
  );
}

/// 附件解析结果缓存（按消息对象）。解析会复制条目 map 并构造附件对象，
/// 带附件的用户消息每次 build 重复解析既费时又让下游 identity 比较失效。
final Expando<List<AiMessageAttachment>> _messageAttachmentsCache =
    Expando<List<AiMessageAttachment>>('messageAttachments');

List<AiMessageAttachment> _cachedMessageAttachments(AiSessionMessage message) {
  final raw = message.metadata[aiSessionMessageAttachmentsMetadataKey];
  if (raw == null) return const <AiMessageAttachment>[];
  final cached = _messageAttachmentsCache[message];
  if (cached != null) return cached;
  final parsed = AiMessageAttachment.listFromMetadata(raw);
  _messageAttachmentsCache[message] = parsed;
  return parsed;
}

enum _MessageBubbleWidthKind { user, assistant }

const double _kMessageBubbleBaseMaxWidth = 760;
const double _kMessageBubbleWidthFactor = 0.60;
const double _kUserMessageBubbleMaxWidth = 1040;
const double _kAssistantMessageBubbleMaxWidth = 1360;

class _ResponsiveMessageWidth extends StatelessWidget {
  const _ResponsiveMessageWidth({
    required this.kind,
    required this.alignment,
    required this.child,
  });

  final _MessageBubbleWidthKind kind;
  final AlignmentGeometry alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isUser = kind == _MessageBubbleWidthKind.user;
        final absoluteMaxWidth = isUser
            ? _kUserMessageBubbleMaxWidth
            : _kAssistantMessageBubbleMaxWidth;
        final responsiveMaxWidth = math.min(
          constraints.maxWidth,
          math.min(
            absoluteMaxWidth,
            math.max(
              _kMessageBubbleBaseMaxWidth,
              constraints.maxWidth * _kMessageBubbleWidthFactor,
            ),
          ),
        );
        return Align(
          alignment: alignment,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: responsiveMaxWidth),
            child: child,
          ),
        );
      },
    );
  }
}

class _MessageBubble extends StatefulWidget {
  const _MessageBubble({
    super.key,
    required this.message,
    required this.sessionId,
    required this.sessionTitle,
    required this.sessionEnvironment,
    required this.showReasoningSweep,
    required this.trackLayoutChanges,
    required this.onLayoutChanged,
    required this.isSelected,
    required this.actionPanelEntranceMotionKey,
    required this.animateActionPanelEntrance,
    required this.onActionPanelEntranceConsumed,
    required this.isScrollHighlighted,
    required this.onSelect,
    required this.onDeselect,
    required this.onCopy,
    required this.onDelete,
    required this.onFork,
    required this.onUserExpansionChanged,
    this.associatedKnowledgeBaseMetadata,
    this.onDeleteFromHere,
    this.onEdit,
    this.onAudit,
    this.onSetFeedback,
    this.onRegenerateResponse,
    this.onSelectResponseVariant,
    this.onToggleSpeech,
    this.onToggleTranslation,
    this.speechPlaying = false,
    this.speechEnabled = false,
    this.translationEnabled = false,
    this.translationLoading = false,
    this.translationVisible = false,
    this.translatedContent,
    this.initiallyShowRawContent = false,
    this.onShowRawContentChanged,
  });

  final AiSessionMessage message;
  final String sessionId;
  final String sessionTitle;
  final AiSessionEnvironment sessionEnvironment;
  final bool showReasoningSweep;
  final bool trackLayoutChanges;
  final VoidCallback onLayoutChanged;
  final bool isSelected;
  final int actionPanelEntranceMotionKey;
  final bool animateActionPanelEntrance;
  final ValueChanged<int> onActionPanelEntranceConsumed;
  final bool isScrollHighlighted;
  final VoidCallback onSelect;
  final VoidCallback onDeselect;
  final Future<void> Function() onCopy;
  final Future<void> Function() onDelete;
  final Future<void> Function() onFork;
  final ValueChanged<bool> onUserExpansionChanged;
  final Map<String, Object?>? associatedKnowledgeBaseMetadata;
  final Future<void> Function()? onDeleteFromHere;
  final Future<void> Function()? onEdit;
  final VoidCallback? onAudit;
  final Future<void> Function(AiSessionMessageFeedback? feedback)?
  onSetFeedback;
  final Future<void> Function()? onRegenerateResponse;
  final Future<void> Function(int index)? onSelectResponseVariant;
  final Future<void> Function()? onToggleSpeech;
  final Future<void> Function()? onToggleTranslation;
  final bool speechPlaying;
  final bool speechEnabled;
  final bool translationEnabled;
  final bool translationLoading;
  final bool translationVisible;
  final String? translatedContent;
  final bool initiallyShowRawContent;
  final ValueChanged<bool>? onShowRawContentChanged;

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble>
    with AutomaticKeepAliveClientMixin<_MessageBubble> {
  static const int _messageExpansionStateCacheLimit = 500;
  static const double _selectionTapMaxDistance = 8;
  static const double _htmlSelectionDragStartDistance = 4;
  static const Duration _selectionTapMaxDuration = Duration(milliseconds: 350);
  static const Duration _htmlTapMaxDuration = Duration(milliseconds: 600);
  static const Duration _selectionToggleDelay = Duration(milliseconds: 80);
  static const Duration _responseVariantSizeMotionResetDelay = Duration(
    milliseconds: 360,
  );
  static final Map<String, bool> _reasoningExpansionOverridesByMessageId =
      <String, bool>{};
  static final Map<String, bool> _assistantExpansionOverridesByMessageId =
      <String, bool>{};

  bool _compressionExpanded = false;
  bool? _reasoningExpandedOverride;
  bool? _assistantResponseExpandedOverride;
  late bool _showRawContent = widget.initiallyShowRawContent;
  bool _responseVariantSizeMotionActive = false;
  bool _responseVariantSizeMotionExpanding = true;
  bool _expansionSizeMotionActive = false;
  bool _expansionSizeMotionExpanding = true;
  bool _uncontrolledBodyExpanded = false;
  bool _loadingFullContent = false;
  String? _fullContentLoadError;

  // 启用文本 selectable 后外层 GestureDetector 的 onTap
  // 会被子节点的文本选择手势抢占，导致点击气泡后
  // 接不到 onSelect（动作按钮不出现）。改用 Listener 直接
  // 跨越手势仲裁判定点击，如果指针按下与抬起间隔、位移均落在
  // `_selectionTapMaxDuration` / `_selectionTapMaxDistance` 内，视为一次选中点击。
  Offset? _pointerDownPosition;
  DateTime? _pointerDownAt;
  // 左上方胶囊（思考 / 工具调用 / 工具结果）有自己的
  // 折叠/展开语义。指针落在胶囊内部时不应触发外层 Listener 的"选中
  // 卡片"，否则会同时切换胶囊折叠和功能按钮。
  final GlobalKey _bubbleInteractionKey = GlobalKey();
  final GlobalKey _metaCapsuleKey = GlobalKey();
  final GlobalKey _actionPanelKey = GlobalKey();

  // 外层 Listener.onPointerUp 在 Flutter gesture arena
  // 解析子节点 onTap 之前就会触发，无法事先得知本次点击是否会被
  // Markdown 链接 / 图片附件 / 代码块工具栏等子交互组件处理。改为
  // 延迟 80ms 调度选中切换：子交互回调命中时调用 markInteractiveTap()
  // 取消调度，避免点完链接还顺带把功能按钮条切出来。空白处点击
  // 仍然几乎瞬时（80ms 几乎不可察）。
  Timer? _pendingSelectionToggleTimer;
  // 旧版 HTML WebView 渲染器的兼容兜底：当前线程内 HTML 主路径已改为
  // WebView 高保真渲染；命中区域时跳过气泡选中切换，并把 tap / drag
  // 转交给对应 state 合成 DOM 点击或文本选择。
  final Map<GlobalKey, _HtmlBubbleWebViewState> _htmlInteractiveRegionStates =
      <GlobalKey, _HtmlBubbleWebViewState>{};
  final Set<GlobalKey> _embeddedInteractiveRegions = <GlobalKey>{};
  _HtmlBubbleWebViewState? _htmlPointerDownState;
  bool _htmlSelectionDragActive = false;
  // 限制 AnimatedSize 期间每帧触发的外层 layout-change 通知频率，
  // 避免逐帧 jumpTo 底部导致上下抽搐。
  Timer? _layoutChangeThrottleTimer;
  Timer? _responseVariantSizeMotionResetTimer;
  Timer? _expansionSizeMotionResetTimer;

  String get _expansionCacheKey => '${widget.sessionId}:${widget.message.id}';

  @override
  bool get wantKeepAlive =>
      _compressionExpanded ||
      _reasoningExpandedOverride == true ||
      _assistantResponseExpandedOverride == true ||
      _uncontrolledBodyExpanded;

  void registerHtmlInteractiveRegion(
    GlobalKey key,
    _HtmlBubbleWebViewState state,
  ) {
    _htmlInteractiveRegionStates[key] = state;
  }

  void unregisterHtmlInteractiveRegion(GlobalKey key) {
    _htmlInteractiveRegionStates.remove(key);
  }

  _HtmlBubbleWebViewState? _htmlInteractiveStateAt(Offset globalPosition) {
    if (_htmlInteractiveRegionStates.isEmpty) return null;
    for (final entry in _htmlInteractiveRegionStates.entries) {
      final box = entry.key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final topLeft = box.localToGlobal(Offset.zero);
      final rect = topLeft & box.size;
      if (rect.contains(globalPosition)) return entry.value;
    }
    return null;
  }

  void registerEmbeddedInteractiveRegion(GlobalKey key) {
    _embeddedInteractiveRegions.add(key);
  }

  void unregisterEmbeddedInteractiveRegion(GlobalKey key) {
    _embeddedInteractiveRegions.remove(key);
  }

  bool _isPointerInsideEmbeddedInteractiveRegion(Offset globalPosition) {
    for (final key in _embeddedInteractiveRegions) {
      final box = key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final topLeft = box.localToGlobal(Offset.zero);
      final rect = topLeft & box.size;
      if (rect.contains(globalPosition)) return true;
    }
    return false;
  }

  // 缓存高成本对象，避免每次构建重复分配。
  List<md.InlineSyntax>? _cachedInlineSyntaxes;
  Map<String, MarkdownElementBuilder>? _cachedBuilders;
  _MessageMarkdownThemeData? _cachedMarkdownThemeData;
  String? _cachedFilePathParseKey;
  List<String>? _cachedFilePathRoots;

  // 三套「专家请求卡」的解析结果按消息缓存：每套 fromPrompt 都要对整条正文做
  // 分行 + 多次正则字段提取，而结果只取决于不可变的用户消息，逐帧重算纯属浪费。
  // 随 _invalidateCache（消息 id 变化时触发）一并失效。
  bool _expertRequestCardsComputed = false;
  AiMachineExpertRequestCard? _machineExpertRequestCard;
  AiWebReverseRequestCard? _webReverseRequestCard;
  AiAndroidReverseRequestCard? _androidReverseRequestCard;
  String? _lastCacheMessageId;
  String? _lastCacheEnvironmentKey;
  int? _lastCacheThemeSignature;

  @override
  void initState() {
    super.initState();
    _loadExpansionOverridesForMessage();
  }

  @override
  void didUpdateWidget(covariant _MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id ||
        oldWidget.sessionId != widget.sessionId) {
      _compressionExpanded = false;
      _uncontrolledBodyExpanded = false;
      _loadExpansionOverridesForMessage();
      _showRawContent = widget.initiallyShowRawContent;
      _responseVariantSizeMotionResetTimer?.cancel();
      _responseVariantSizeMotionResetTimer = null;
      _responseVariantSizeMotionActive = false;
      _expansionSizeMotionResetTimer?.cancel();
      _expansionSizeMotionResetTimer = null;
      _expansionSizeMotionActive = false;
      _loadingFullContent = false;
      _fullContentLoadError = null;
      _invalidateCache();
      updateKeepAlive();
      return;
    }
    if (_isResponseVariantContentChange(oldWidget.message, widget.message)) {
      _armResponseVariantSizeMotion(oldWidget.message, widget.message);
    }
  }

  bool _isResponseVariantContentChange(
    AiSessionMessage previous,
    AiSessionMessage next,
  ) {
    if (next.kind != AiSessionMessageKind.assistant) return false;
    final previousVariants = previous.responseVariants;
    final nextVariants = next.responseVariants;
    if (previousVariants.length <= 1 || nextVariants.length <= 1) {
      return false;
    }
    return previous.responseVariantIndex != next.responseVariantIndex ||
        previous.content != next.content;
  }

  Widget _withLayoutChangeTracking({
    required Widget child,
    required bool enabled,
  }) {
    if (!enabled) return child;
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (notification) {
        if (_layoutChangeThrottleTimer?.isActive ?? false) {
          return false;
        }
        _layoutChangeThrottleTimer = startSafeTimer(kOpenHandMotion200, () {});
        widget.onLayoutChanged();
        return false;
      },
      child: SizeChangedLayoutNotifier(child: child),
    );
  }

  void _armResponseVariantSizeMotion(
    AiSessionMessage previous,
    AiSessionMessage next,
  ) {
    _responseVariantSizeMotionResetTimer?.cancel();
    _responseVariantSizeMotionActive = true;
    _responseVariantSizeMotionExpanding =
        next.content.length >= previous.content.length;
    _responseVariantSizeMotionResetTimer = startSafeTimer(
      _responseVariantSizeMotionResetDelay,
      () {
        _responseVariantSizeMotionResetTimer = null;
        if (!mounted || !_responseVariantSizeMotionActive) return;
        setState(() {
          _responseVariantSizeMotionActive = false;
        });
      },
    );
  }

  void _loadExpansionOverridesForMessage() {
    _reasoningExpandedOverride =
        _reasoningExpansionOverridesByMessageId[_expansionCacheKey];
    _assistantResponseExpandedOverride =
        _assistantExpansionOverridesByMessageId[_expansionCacheKey];
  }

  static void _rememberExpansionOverride(
    Map<String, bool> cache,
    String messageId,
    bool value,
  ) {
    if (messageId.isEmpty) return;
    cache.remove(messageId);
    cache[messageId] = value;
    while (cache.length > _messageExpansionStateCacheLimit) {
      cache.remove(cache.keys.first);
    }
  }

  void _setReasoningExpandedOverride(bool value) {
    _armExpansionSizeMotion(expanding: value);
    _rememberExpansionOverride(
      _reasoningExpansionOverridesByMessageId,
      _expansionCacheKey,
      value,
    );
    setState(() {
      _reasoningExpandedOverride = value;
    });
    updateKeepAlive();
    widget.onUserExpansionChanged(value);
  }

  void _setAssistantResponseExpandedOverride(bool value) {
    _armExpansionSizeMotion(expanding: value);
    _rememberExpansionOverride(
      _assistantExpansionOverridesByMessageId,
      _expansionCacheKey,
      value,
    );
    setState(() {
      _assistantResponseExpandedOverride = value;
    });
    updateKeepAlive();
    widget.onUserExpansionChanged(value);
  }

  void _handleUncontrolledBodyCollapsedChanged(bool collapsed) {
    _uncontrolledBodyExpanded = !collapsed;
    updateKeepAlive();
    widget.onUserExpansionChanged(!collapsed);
  }

  void _armExpansionSizeMotion({required bool expanding}) {
    _expansionSizeMotionResetTimer?.cancel();
    _expansionSizeMotionResetTimer = null;
    final duration = cardMotionDurationFor(context, expanding: expanding);
    _expansionSizeMotionActive = duration > Duration.zero;
    _expansionSizeMotionExpanding = expanding;
    if (!_expansionSizeMotionActive) return;
    _expansionSizeMotionResetTimer = startSafeTimer(
      duration + kOpenHandFramePeriodicTimerInterval * 2,
      () {
        _expansionSizeMotionResetTimer = null;
        if (!mounted || !_expansionSizeMotionActive) return;
        setState(() => _expansionSizeMotionActive = false);
      },
    );
  }

  /// 解析（并缓存）三套专家请求卡。非用户消息一律为空。解析结果由进程级
  /// Expando 按消息对象缓存，State 只做本地引用同步。
  void _ensureExpertRequestCards(
    AiSessionMessage message, {
    required bool isUser,
  }) {
    if (_expertRequestCardsComputed) return;
    _expertRequestCardsComputed = true;
    if (!isUser) {
      _machineExpertRequestCard = null;
      _webReverseRequestCard = null;
      _androidReverseRequestCard = null;
      return;
    }
    _machineExpertRequestCard = _machineExpertRequestCardFor(message);
    _webReverseRequestCard = _webReverseRequestCardFor(message);
    _androidReverseRequestCard = _androidReverseRequestCardFor(message);
  }

  void _invalidateCache() {
    _cachedInlineSyntaxes = null;
    _cachedBuilders = null;
    _cachedMarkdownThemeData = null;
    _cachedFilePathParseKey = null;
    _cachedFilePathRoots = null;
    _expertRequestCardsComputed = false;
    _machineExpertRequestCard = null;
    _webReverseRequestCard = null;
    _androidReverseRequestCard = null;
    _lastCacheMessageId = null;
    _lastCacheEnvironmentKey = null;
    _lastCacheThemeSignature = null;
  }

  /// 解析单条消息的渲染格式：消息自带格式优先，缺失时回落到全局设置。
  ///
  /// 只允许在 [build] 同步链路内调用——回落分支用 `select` 订阅全局格式，
  /// 让历史消息（无 metadata 格式）在用户切换设置后立即重渲染；带格式的消息
  /// 不进入该分支，也就不会被无关设置变更牵连重建。
  AiMessageContentFormat _resolveMessageContentFormat(
    BuildContext context,
    AiSessionMessage message,
  ) {
    final storedKey = message.metadata[aiSessionMessageContentFormatKey];
    if (storedKey is String && storedKey.isNotEmpty) {
      return AiMessageContentFormat.fromStorageKey(storedKey);
    }
    return context.select<SettingsController, AiMessageContentFormat>(
      (settings) => settings.aiMessageContentFormat,
    );
  }

  /// 判断全局坐标是否落在左上方折叠胶囊的范围内。
  /// 命中时点击仅用于切换胶囊本身的折叠态，不再驱动卡片选中。
  bool _isPointerInsideMetaCapsule(Offset globalPosition) {
    final box = _metaCapsuleKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return false;
    final topLeft = box.localToGlobal(Offset.zero);
    final rect = topLeft & box.size;
    return rect.contains(globalPosition);
  }

  bool _isPointerInsideBubbleInteraction(Offset globalPosition) {
    final box = _bubbleInteractionKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return false;
    final topLeft = box.localToGlobal(Offset.zero);
    return (topLeft & box.size).contains(globalPosition);
  }

  /// 选中后的功能胶囊只承载消息操作，不参与消息卡片聚焦/失焦切换。
  bool _isPointerInsideActionPanel(Offset globalPosition) {
    final box = _actionPanelKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return false;
    final topLeft = box.localToGlobal(Offset.zero);
    final rect = topLeft & box.size;
    return rect.contains(globalPosition);
  }

  /// 子交互回调（Markdown 链接、图片附件、代码块工具栏按钮等）在
  /// 触发自身动作之前调用此方法，告知气泡"本次点击已被消费"，从而
  /// 取消即将到来的延迟选中切换，避免点击交互后顺带切出/收起功能按钮。
  void markInteractiveTap() {
    _pendingSelectionToggleTimer?.cancel();
    _pendingSelectionToggleTimer = null;
  }

  void _scheduleSelectionToggle() {
    _pendingSelectionToggleTimer?.cancel();
    _pendingSelectionToggleTimer = startSafeTimer(_selectionToggleDelay, () {
      _pendingSelectionToggleTimer = null;
      if (!mounted) return;
      if (widget.isSelected) {
        widget.onDeselect();
      } else {
        widget.onSelect();
      }
    });
  }

  @override
  void dispose() {
    _pendingSelectionToggleTimer?.cancel();
    _pendingSelectionToggleTimer = null;
    _layoutChangeThrottleTimer?.cancel();
    _layoutChangeThrottleTimer = null;
    _responseVariantSizeMotionResetTimer?.cancel();
    _responseVariantSizeMotionResetTimer = null;
    _expansionSizeMotionResetTimer?.cancel();
    _expansionSizeMotionResetTimer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (kDebugMode) {
      developer.Timeline.startSync(
        'openhand.bubble.build',
        arguments: <String, Object?>{
          'kind': widget.message.kind.storageValue,
          'chars': widget.message.content.length,
        },
      );
      try {
        return _buildInner(context);
      } finally {
        developer.Timeline.finishSync();
      }
    }
    return _buildInner(context);
  }

  Widget _buildInner(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final message = widget.message;
    final isUser = message.kind == AiSessionMessageKind.user;
    final goalEvaluationType =
        '${message.metadata[aiSessionGoalEvaluationMessageTypeMetadataKey] ?? ''}'
            .trim();
    final isGoalEvaluationRequest =
        message.metadata[aiSessionGoalEvaluationMessageMetadataKey] == true &&
        goalEvaluationType == aiSessionGoalEvaluationMessageTypeRequest;
    final isGoalEvaluationResponse =
        message.metadata[aiSessionGoalEvaluationMessageMetadataKey] == true &&
        goalEvaluationType == aiSessionGoalEvaluationMessageTypeResponse;
    final isGoalEvaluationMessage =
        isGoalEvaluationRequest || isGoalEvaluationResponse;
    final goalMessageView = _GoalMessageViewData.fromMessage(message);
    final isGoalRuntimeMessage = goalMessageView != null;
    _ensureExpertRequestCards(message, isUser: isUser);
    final machineExpertRequestCard = _machineExpertRequestCard;
    final webReverseRequestCard = _webReverseRequestCard;
    final androidReverseRequestCard = _androidReverseRequestCard;
    final isCompressionPoint =
        message.kind == AiSessionMessageKind.compressionPoint;
    final isReasoning = message.kind == AiSessionMessageKind.reasoning;
    final isStreamingReasoning = _isStreamingReasoningMessage(message);
    final isStreamingAssistant =
        message.kind == AiSessionMessageKind.assistant &&
        message.metadata[aiSessionMessageMetadataStreamingKey] == true;
    final isToolCall =
        message.kind == AiSessionMessageKind.toolCall ||
        message.kind == AiSessionMessageKind.hook;
    final isToolResult =
        message.kind == AiSessionMessageKind.tool ||
        message.kind == AiSessionMessageKind.mcp ||
        message.kind == AiSessionMessageKind.skill;
    final isStatus = message.kind == AiSessionMessageKind.status;
    final isSelfLearning = message.kind == AiSessionMessageKind.selfLearning;
    final isRoundFileMutationSummary =
        message.kind == AiSessionMessageKind.fileMutationSummary ||
        (isStatus && message.metadata['round_file_mutation_summary'] == true);
    // 「本轮文件变动汇总」状态卡走专属 Widget，跳过通用 bubble 流。
    if (isRoundFileMutationSummary) {
      return _withLayoutChangeTracking(
        enabled: widget.trackLayoutChanges,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: _ResponsiveMessageWidth(
            kind: _MessageBubbleWidthKind.assistant,
            alignment: Alignment.centerLeft,
            child: _RoundFileMutationSummaryCard(message: message),
          ),
        ),
      );
    }
    final attachments = _cachedMessageAttachments(message);
    // 优先使用消息元数据中的格式；旧数据回退到全局设置。
    final resolvedMessageContentFormat = _resolveMessageContentFormat(
      context,
      message,
    );
    // provider 的 `select`/`watch` 断言「调用点必须处于本元素的 build 阶段」。
    // 消息体由下方 `Builder` 闭包延迟构建，闭包捕获的是外层 context——真正执行
    // 时外层元素早已结束 build，在闭包里直接 select 必然命中断言并红屏。
    // 因此在此处一次性取值：既保留「只订阅真正用到的设置项」的窄依赖
    //（避免主题/TTS/模型等无关设置把窗口内所有气泡全量重建），
    // 又保证订阅动作发生在合法的 build 阶段。
    final htmlRenderFallback = context
        .select<SettingsController, AiHtmlRenderFallback>(
          (settings) => settings.aiHtmlRenderFallback,
        );
    final reasoningExpanded =
        _reasoningExpandedOverride ?? _shouldDefaultExpandReasoning(message);

    final alignment = isCompressionPoint
        ? Alignment.center
        : isUser
        ? Alignment.centerRight
        : Alignment.centerLeft;
    final borderRadius = BorderRadius.circular(kOpenHandRadius18);
    final backgroundColor = isCompressionPoint
        ? colorScheme.tertiaryContainer
        : isUser
        ? colorScheme.primaryContainer
        : isReasoning
        ? OpenHandConsolePalette.terminalSurface
        : isToolCall
        ? colorScheme.secondaryContainer
        : isToolResult
        ? colorScheme.surfaceContainerHighest
        : isSelfLearning
        ? colorScheme.tertiaryContainer
        : isStatus
        ? colorScheme.surfaceContainer
        : colorScheme.surfaceContainerHigh;
    final textColor = isCompressionPoint
        ? colorScheme.onTertiaryContainer
        : isUser
        ? colorScheme.onPrimaryContainer
        : isReasoning
        ? Colors.white
        : isToolCall
        ? colorScheme.onSecondaryContainer
        : isSelfLearning
        ? colorScheme.onTertiaryContainer
        : colorScheme.onSurface;
    final useDarkCodeSurface = isReasoning || isToolCall;
    // 快速路径：消息 id 未变时先算轻量签名，避免每帧重复解析 bash 参数。
    final messageIdUnchanged = _lastCacheMessageId == message.id;
    final themeSignature = Object.hash(
      theme.brightness.index,
      colorScheme.primary.toARGB32(),
      colorScheme.primaryContainer.toARGB32(),
      colorScheme.surface.toARGB32(),
      colorScheme.onSurface.toARGB32(),
      theme.textTheme.bodyLarge?.fontSize,
      theme.textTheme.bodyMedium?.fontSize,
      backgroundColor.toARGB32(),
      textColor.toARGB32(),
      useDarkCodeSurface,
    );
    final environmentKey =
        messageIdUnchanged &&
            _lastCacheThemeSignature == themeSignature &&
            _lastCacheEnvironmentKey != null
        ? _lastCacheEnvironmentKey!
        : '${widget.sessionEnvironment.applicationDirectory}|${_toolExecutionWorkingDirectory(message)}';
    final needsCacheRefresh =
        !messageIdUnchanged ||
        _lastCacheEnvironmentKey != environmentKey ||
        _lastCacheThemeSignature != themeSignature;
    if (needsCacheRefresh) {
      _lastCacheMessageId = message.id;
      _lastCacheEnvironmentKey = environmentKey;
      _lastCacheThemeSignature = themeSignature;
      _cachedMarkdownThemeData = _MessageMarkdownThemeData.fromMessageBubble(
        theme: theme,
        backgroundColor: backgroundColor,
        textColor: textColor,
        useDarkCodeSurface: useDarkCodeSurface,
      );
      _cachedFilePathRoots = messageFilePathRoots(
        widget.sessionEnvironment,
        workingDirectory: _toolExecutionWorkingDirectory(message),
      );
      _cachedFilePathParseKey = _cachedFilePathRoots!.join('|');
      _cachedBuilders = <String, MarkdownElementBuilder>{
        'code': _cachedMarkdownThemeData!.inlineCodeBuilder,
        'pre': _HighlightedCodeBlockBuilder(
          theme: theme,
          baseColor: textColor,
          darkSurface: useDarkCodeSurface,
          // 始终允许文本选择/复制，便于用户随时复制响应内容。
          // “选中模式”依然控制 action buttons 的可见性，
          // 但选择/复制不再需要预先点击进入选中态。
          selectable: true,
        ),
        messageResolvedPathElementTag: _FilePathMarkdownBuilder(
          textColor: textColor,
          inlineCodeBuilder: _cachedMarkdownThemeData!.inlineCodeBuilder,
          onOpenPath: _openResolvedMessagePath,
        ),
        messagePendingPathElementTag: _FilePathMarkdownBuilder(
          textColor: textColor,
          inlineCodeBuilder: _cachedMarkdownThemeData!.inlineCodeBuilder,
          onOpenPath: _openResolvedMessagePath,
        ),
        'openhand-generated-media': _GeneratedMediaLinkMarkdownBuilder(
          textColor: textColor,
          backgroundColor: backgroundColor,
          pathRoots: _cachedFilePathRoots!,
        ),
      };
      _cachedInlineSyntaxes = <md.InlineSyntax>[
        _GeneratedMediaLinkSyntax.byExtension(pathRoots: _cachedFilePathRoots!),
        _GeneratedMediaLinkSyntax.byGeneratedLabel(
          pathRoots: _cachedFilePathRoots!,
        ),
        MessagePathCodeSyntax(candidateRoots: _cachedFilePathRoots!),
        MessageFilePathSyntax(candidateRoots: _cachedFilePathRoots!),
      ];
    }
    final markdownStyleSheet = _cachedMarkdownThemeData!;
    final filePathRoots = _cachedFilePathRoots!;
    final filePathParseKey = _cachedFilePathParseKey!;
    final markdownBuilders = _cachedBuilders!;
    final inlineSyntaxes = _cachedInlineSyntaxes!;

    // 仅从助手消息解析 Harness 工程代理和阶段标记。
    final translatedContent = widget.translatedContent?.trim();
    final showingTranslation =
        widget.translationVisible &&
        translatedContent != null &&
        translatedContent.isNotEmpty;
    final displayContent = showingTranslation
        ? translatedContent
        : message.content;
    final heAnnotation =
        (!isUser &&
            !isCompressionPoint &&
            !isToolCall &&
            !isToolResult &&
            !isStatus &&
            !isSelfLearning)
        ? _parseHeAnnotation(message.content)
        : null;
    final effectiveContent = showingTranslation
        ? displayContent
        : heAnnotation?.strippedContent ?? message.content;
    final isAssistantResponse =
        !isGoalEvaluationMessage &&
        !isUser &&
        !isCompressionPoint &&
        !isReasoning &&
        !isToolCall &&
        !isToolResult &&
        !isStatus &&
        !isSelfLearning;
    // 转录层已按消息对象缓存了「直接元数据 + 回合工具消息」两条链路的
    // used-references 结果（含全文引用匹配），这里直接采用，避免每次
    // build 对整条回答重复跑 O(答案长度 × 词条数) 的归一化与匹配。
    final associatedKnowledgeBaseMetadata =
        (isAssistantResponse && !isStreamingAssistant)
        ? widget.associatedKnowledgeBaseMetadata
        : null;
    final isAiSideMessage =
        message.isAiSideConversationMessage && !isGoalEvaluationMessage;
    final selectedFeedback = message.feedback;
    final assistantResponseExceedsCollapseThreshold =
        isAssistantResponse &&
        !_showRawContent &&
        resolvedMessageContentFormat != AiMessageContentFormat.html &&
        _messageShouldCollapse(
          effectiveContent,
          charThreshold: _messageMarkdownCollapseCharThreshold,
          lineThreshold: _messageMarkdownCollapseLineThreshold,
        );
    final streamingAssistantShouldCollapse =
        isStreamingAssistant && assistantResponseExceedsCollapseThreshold;
    final canCollapseAssistantResponse =
        !isStreamingAssistant && assistantResponseExceedsCollapseThreshold;
    final assistantResponseExpanded =
        canCollapseAssistantResponse &&
        (_assistantResponseExpandedOverride ?? false);
    final assistantResponseCollapsed =
        canCollapseAssistantResponse && !assistantResponseExpanded;
    final showAssistantResponseMetaRow =
        isAssistantResponse &&
        (streamingAssistantShouldCollapse || canCollapseAssistantResponse);
    final bodyContentSignature =
        '${effectiveContent.length}:${boundedTextFingerprint(effectiveContent)}';
    final assistantBodyContentScrollKey = isStreamingAssistant
        ? 'streaming'
        : 'content:$bodyContentSignature';
    final reasoningBodyContentScrollKey = isStreamingReasoning
        ? 'streaming'
        : 'content:$bodyContentSignature';
    final assistantBodyScrollStateKey =
        '${message.id}|assistant|variant:${message.responseVariantIndex}|fmt:${resolvedMessageContentFormat.storageKey}|translated:${showingTranslation ? 1 : 0}|raw:${_showRawContent ? 1 : 0}|$assistantBodyContentScrollKey';
    final reasoningBodyScrollStateKey =
        '${message.id}|reasoning|raw:${_showRawContent ? 1 : 0}|stream:${isStreamingReasoning ? 1 : 0}|$reasoningBodyContentScrollKey';
    final compressionBodyScrollStateKey =
        '${message.id}|compression|content:${message.content.length}:${boundedTextFingerprint(message.content)}';
    final userBodyScrollStateKey =
        '${message.id}|user|translated:${showingTranslation ? 1 : 0}|content:$bodyContentSignature';
    void warmAssistantResponseMarkdownRenderPath() {
      if (!isAssistantResponse || isStreamingAssistant || _showRawContent) {
        return;
      }
      if (resolvedMessageContentFormat == AiMessageContentFormat.plainText) {
        return;
      }
      final normalizedContent = effectiveContent.isEmpty
          ? ' '
          : effectiveContent;
      final trimmedContent = normalizedContent.trim();
      final containsMarkdownFence =
          _startsWithFencedMermaidBlock(trimmedContent) ||
          _containsMarkdownCodeFence(trimmedContent);
      final hasHtmlLikeTags = _looksLikeHtml(normalizedContent);
      final hasTagStructure =
          !hasHtmlLikeTags && _hasHtmlTagStructure(normalizedContent);
      if (resolvedMessageContentFormat == AiMessageContentFormat.html &&
          (hasHtmlLikeTags || hasTagStructure)) {
        return;
      }
      if (resolvedMessageContentFormat == AiMessageContentFormat.html &&
          htmlRenderFallback == AiHtmlRenderFallback.plainText) {
        return;
      }
      if (resolvedMessageContentFormat == AiMessageContentFormat.markdown &&
          !containsMarkdownFence &&
          (hasHtmlLikeTags || hasTagStructure)) {
        return;
      }
      _warmMarkdownRenderPath(
        data: normalizedContent,
        parseKey: filePathParseKey,
        inlineSyntaxes: inlineSyntaxes,
        theme: theme,
        textColor: textColor,
        useDarkCodeSurface: useDarkCodeSurface,
      );
    }

    void toggleAssistantResponseExpansion() {
      if (!canCollapseAssistantResponse) return;
      if (assistantResponseExpanded) {
        _CollapsedBodyScrollOffsetCache.reset(
          '$assistantBodyScrollStateKey|markdown',
        );
        _CollapsedBodyScrollOffsetCache.reset(
          '$assistantBodyScrollStateKey|plain',
        );
      } else {
        warmAssistantResponseMarkdownRenderPath();
      }
      _setAssistantResponseExpandedOverride(!assistantResponseExpanded);
    }

    Future<void> loadFullContent() async {
      if (_loadingFullContent) return;
      setState(() {
        _loadingFullContent = true;
        _fullContentLoadError = null;
      });
      try {
        final loaded = await context
            .read<AiSessionController>()
            .loadFullSessionMessageContent(widget.sessionId, message.id);
        if (mounted && loaded == null) {
          setState(() {
            _fullContentLoadError = openHandLocalizedText(
              context,
              zh: '完整内容加载失败，请重试。',
              en: 'Unable to load the full content. Please retry.',
            );
          });
        }
      } finally {
        if (mounted) setState(() => _loadingFullContent = false);
      }
    }

    Widget buildAssistantBodyDispatcher({
      required String data,
      required AiMessageContentFormat format,
      bool isStreaming = false,
      bool? collapsedOverride,
      ValueChanged<bool>? onCollapsedChanged,
      bool showCollapseToggle = true,
      Object? contentMotionKey,
      bool forceMotionWhenScrolling = false,
      String? scrollStateKey,
    }) {
      return _AssistantMessageBodyDispatcher(
        data: data.isEmpty ? ' ' : data,
        format: format,
        // 取 build 阶段已订阅好的值，闭包内不再触碰 provider（见上方说明）。
        htmlFallback: htmlRenderFallback,
        textColor: textColor,
        backgroundColor: backgroundColor,
        markdownBuilders: markdownBuilders,
        markdownStyleSheet: markdownStyleSheet.styleSheet,
        inlineSyntaxes: inlineSyntaxes,
        filePathRoots: filePathRoots,
        filePathParseKey: filePathParseKey,
        collapseCharThreshold: isToolResult
            ? _toolResultMarkdownCollapseCharThreshold
            : _messageMarkdownCollapseCharThreshold,
        collapseLineThreshold: isToolResult
            ? _toolResultMarkdownCollapseLineThreshold
            : _messageMarkdownCollapseLineThreshold,
        previewMaxHeight: isToolResult
            ? _toolResultPreviewMaxHeight
            : _messageResponsePreviewMaxHeight,
        wrapInSelectionArea: !isToolResult,
        isStreaming: isStreaming,
        collapsedOverride: collapsedOverride,
        onCollapsedChanged: onCollapsedChanged,
        showCollapseToggle: showCollapseToggle,
        contentMotionKey: contentMotionKey,
        forceMotionWhenScrolling: forceMotionWhenScrolling,
        scrollStateKey: scrollStateKey,
      );
    }

    Widget buildStreamingMarkdownBody(String data) {
      return SelectionArea(
        child: _MarkdownSelectionContainer(
          child: _SafeMarkdownBody(
            data: data.isEmpty ? ' ' : data,
            streaming: true,
            builders: markdownBuilders,
            styleSheet: markdownStyleSheet.styleSheet,
            inlineSyntaxes: inlineSyntaxes,
            pathRoots: filePathRoots,
            parseKey: filePathParseKey,
          ),
        ),
      );
    }

    final isContentPreview =
        message.metadata[aiSessionMessageContentPreviewMetadataKey] == true;
    final contentPreviewText =
        isContentPreview &&
            resolvedMessageContentFormat == AiMessageContentFormat.html
        ? _preparedHtmlRenderDataFor(effectiveContent).previewText
        : effectiveContent;
    final responseVariantBodyMotionKey =
        isAssistantResponse && message.responseVariants.length > 1
        ? Object.hash(
            message.id,
            message.responseVariantIndex,
            effectiveContent.length,
            boundedTextFingerprint(effectiveContent),
          )
        : null;
    final isScrollHighlighted = widget.isScrollHighlighted;
    final highlightBorderColor = colorScheme.primary.withValues(alpha: 0.78);
    final bubbleCard = AnimatedContainer(
      duration: openHandMotionDuration(context, kOpenHandMotion260),
      curve: kCardDecorationMotionCurve,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: borderRadius,
        border: isScrollHighlighted
            ? Border.all(color: highlightBorderColor, width: 1.8)
            : isToolCall
            ? Border.all(color: colorScheme.secondary, width: 1.2)
            : widget.isSelected
            ? Border.all(
                color: colorScheme.primary.withValues(alpha: 0.38),
                width: 1.5,
              )
            : Border.all(
                color: colorScheme.outlineVariant.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.18 : 0.10,
                ),
              ),
        boxShadow: [
          if (isScrollHighlighted)
            BoxShadow(
              color: colorScheme.primary.withValues(alpha: 0.22),
              blurRadius: 24,
              spreadRadius: 1,
              offset: const Offset(0, 4),
            ),
          BoxShadow(
            color: colorScheme.shadow.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.06 : 0.04,
            ),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        // 消息卡片的单一外层尺寸动画壳：只承接“有明确语义边界”的高度变化
        //（如展开/收起、body 模式切换、action row 显隐），而不是对每个
        // streaming chunk 做逐帧高度插值。时长/曲线统一复用
        // `_home_motion_tokens.dart`，避免多层尺寸动画再次互相竞争。
        child: Builder(
          builder: (context) {
            final bubbleContent = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isCompressionPoint)
                  _MessageMetaRow(
                    key: _metaCapsuleKey,
                    icon: Icons.summarize_rounded,
                    label: AppLocalizations.of(
                      context,
                    )!.threadCompressionCheckpointLabel,
                    color: textColor,
                  )
                else if (isReasoning)
                  _ReasoningMetaRow(
                    key: _metaCapsuleKey,
                    message: message,
                    color: textColor,
                    showSweep: widget.showReasoningSweep,
                    expanded: reasoningExpanded,
                    onTap: () {
                      if (reasoningExpanded) {
                        _CollapsedBodyScrollOffsetCache.reset(
                          '$reasoningBodyScrollStateKey|preview',
                        );
                        _CollapsedBodyScrollOffsetCache.reset(
                          '$reasoningBodyScrollStateKey|streaming-preview',
                        );
                      }
                      _setReasoningExpandedOverride(!reasoningExpanded);
                    },
                  )
                else if (isToolCall)
                  _ToolCallMetaRow(
                    key: _metaCapsuleKey,
                    message: message,
                    color: textColor,
                  )
                else if (isToolResult)
                  _MessageMetaRow(
                    key: _metaCapsuleKey,
                    icon: Icons.inventory_2_outlined,
                    label: openHandToolResultLabel(context),
                    color: textColor,
                  )
                else if (showAssistantResponseMetaRow)
                  _ResponseMetaRow(
                    key: _metaCapsuleKey,
                    message: message,
                    color: textColor,
                    showSweep: isStreamingAssistant,
                    expanded: assistantResponseExpanded,
                    onTap: canCollapseAssistantResponse
                        ? toggleAssistantResponseExpansion
                        : null,
                  ),
                if (isCompressionPoint ||
                    isReasoning ||
                    isToolCall ||
                    isToolResult ||
                    showAssistantResponseMetaRow)
                  kOpenHandGap10,
                if (isContentPreview)
                  _PlainTextMessageBody(
                    data: contentPreviewText.isEmpty ? ' ' : contentPreviewText,
                    textColor: textColor,
                    backgroundColor: backgroundColor,
                    style: markdownStyleSheet.styleSheet.p,
                    onCollapsedChanged: _handleUncontrolledBodyCollapsedChanged,
                    scrollStateKey: '${message.id}|content-preview',
                  )
                else if (isCompressionPoint)
                  _CompressionCheckpointBody(
                    content: message.content,
                    expanded: _compressionExpanded,
                    onToggle: () {
                      if (_compressionExpanded) {
                        _CollapsedBodyScrollOffsetCache.reset(
                          '$compressionBodyScrollStateKey|preview',
                        );
                      }
                      final expanded = !_compressionExpanded;
                      _armExpansionSizeMotion(expanding: expanded);
                      setState(() => _compressionExpanded = expanded);
                      updateKeepAlive();
                      widget.onUserExpansionChanged(expanded);
                    },
                    selectable: true,
                    textColor: textColor,
                    fadeColor: backgroundColor,
                    styleSheet: markdownStyleSheet.styleSheet,
                    builders: markdownBuilders,
                    inlineSyntaxes: inlineSyntaxes,
                    pathRoots: filePathRoots,
                    parseKey: filePathParseKey,
                    scrollStateKey: compressionBodyScrollStateKey,
                  )
                else if (isReasoning)
                  _showRawContent
                      ? SelectableText(
                          effectiveContent.isEmpty ? ' ' : effectiveContent,
                          style: markdownStyleSheet.styleSheet.p?.copyWith(
                            color: textColor,
                          ),
                        )
                      : _ReasoningBody(
                          content: effectiveContent,
                          expanded: reasoningExpanded,
                          streaming: isStreamingReasoning,
                          selectable: true,
                          textColor: textColor,
                          fadeColor: backgroundColor,
                          styleSheet: markdownStyleSheet.styleSheet,
                          builders: markdownBuilders,
                          inlineSyntaxes: inlineSyntaxes,
                          pathRoots: filePathRoots,
                          parseKey: filePathParseKey,
                          scrollStateKey: reasoningBodyScrollStateKey,
                        )
                else if (isToolCall)
                  _ToolCallBody(
                    message: message,
                    sessionId: widget.sessionId,
                    selectable: true,
                  )
                else if (isSelfLearning)
                  ClipRect(child: _SelfLearningCard(message: message))
                else if (goalMessageView != null)
                  _GoalMessageStructuredBody(
                    data: goalMessageView,
                    textColor: textColor,
                  )
                else if (machineExpertRequestCard != null)
                  _MachineExpertRequestStructuredBody(
                    data: machineExpertRequestCard,
                    textColor: textColor,
                  )
                else if (webReverseRequestCard != null)
                  _WebReverseRequestStructuredBody(
                    data: webReverseRequestCard,
                    textColor: textColor,
                  )
                else if (androidReverseRequestCard != null)
                  _AndroidReverseRequestStructuredBody(
                    data: androidReverseRequestCard,
                    textColor: textColor,
                  )
                else if (isUser)
                  _PlainTextMessageBody(
                    data: effectiveContent.isEmpty ? ' ' : effectiveContent,
                    textColor: textColor,
                    backgroundColor: backgroundColor,
                    style: markdownStyleSheet.styleSheet.p,
                    onCollapsedChanged: _handleUncontrolledBodyCollapsedChanged,
                    scrollStateKey: userBodyScrollStateKey,
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 撤回 IndexedStack 改回 ternary。
                      // IndexedStack 的 StackFit.loose 让容器高度始终
                      // 等于最大子项（WebView 的 estimatedHeight ~ 800px），
                      // raw 模式下 SelectableText（~100px）只占顶部一
                      // 小块，下方留出 700px 空白，且整张卡片无法响应
                      // "原始↔渲染"的高度切换——卡死在最大子项高度。
                      // 切回 ternary 后，raw 模式仅 SelectableText 占
                      // 高度、渲染模式仅 dispatcher 占高度，AnimatedSize
                      // 在两者间平滑过渡；切换的 250ms 防抖是用户可
                      // 接受的代价（与 WebView 加载本身的耗时同一数量级）。
                      if (_showRawContent)
                        SelectableText(
                          effectiveContent.isEmpty ? ' ' : effectiveContent,
                          style: markdownStyleSheet.styleSheet.p?.copyWith(
                            color: textColor,
                          ),
                        )
                      else if (isStreamingAssistant &&
                          resolvedMessageContentFormat ==
                              AiMessageContentFormat.html)
                        // HTML 格式：流式阶段不暴露原始 `<div>...` 字符，
                        // 改为渲染 `_AssistantMessageBodyDispatcher`
                        // 内部的骨架屏占位；流式结束后直接切到稳定
                        // WebView 渲染，避免平台视图被 fade/scale 合成层包裹。
                        buildAssistantBodyDispatcher(
                          data: effectiveContent,
                          format: resolvedMessageContentFormat,
                          isStreaming: true,
                          scrollStateKey: assistantBodyScrollStateKey,
                        )
                      else if (isStreamingAssistant)
                        streamingAssistantShouldCollapse
                            ? buildAssistantBodyDispatcher(
                                data: effectiveContent,
                                format: resolvedMessageContentFormat,
                                isStreaming: true,
                                collapsedOverride: true,
                                showCollapseToggle: false,
                                scrollStateKey: assistantBodyScrollStateKey,
                              )
                            : TweenAnimationBuilder<double>(
                                tween: Tween<double>(begin: 0.992, end: 1.0),
                                duration: cardMotionDurationFor(
                                  context,
                                  expanding: true,
                                ),
                                curve: kCardMotionCurve,
                                child:
                                    resolvedMessageContentFormat ==
                                        AiMessageContentFormat.markdown
                                    ? StreamingTextRevealText(
                                        text: effectiveContent.isEmpty
                                            ? ' '
                                            : effectiveContent,
                                        streaming: true,
                                        animateSize: false,
                                        builder: (context, visibleContent) =>
                                            buildStreamingMarkdownBody(
                                              visibleContent,
                                            ),
                                      )
                                    : StreamingTextRevealText(
                                        text: effectiveContent.isEmpty
                                            ? ' '
                                            : effectiveContent,
                                        streaming: true,
                                        animateSize: false,
                                        builder: (context, visibleContent) =>
                                            _StreamingAssistantTextBody(
                                              data: visibleContent.isEmpty
                                                  ? ' '
                                                  : visibleContent,
                                              textColor: textColor,
                                              backgroundColor: backgroundColor,
                                              style: markdownStyleSheet
                                                  .styleSheet
                                                  .p,
                                              scrollStateKey:
                                                  assistantBodyScrollStateKey,
                                            ),
                                      ),
                                builder: (context, value, child) {
                                  return Transform.scale(
                                    scale: value,
                                    alignment: Alignment.topLeft,
                                    child: child,
                                  );
                                },
                              )
                      else
                        buildAssistantBodyDispatcher(
                          data: effectiveContent,
                          format: resolvedMessageContentFormat,
                          collapsedOverride: canCollapseAssistantResponse
                              ? assistantResponseCollapsed
                              : null,
                          onCollapsedChanged: (collapsed) {
                            if (canCollapseAssistantResponse) {
                              _setAssistantResponseExpandedOverride(!collapsed);
                            } else {
                              _handleUncontrolledBodyCollapsedChanged(
                                collapsed,
                              );
                            }
                          },
                          showCollapseToggle: !canCollapseAssistantResponse,
                          contentMotionKey: responseVariantBodyMotionKey,
                          forceMotionWhenScrolling:
                              _responseVariantSizeMotionActive,
                          scrollStateKey: assistantBodyScrollStateKey,
                        ),
                      if (associatedKnowledgeBaseMetadata != null) ...[
                        kOpenHandGap10,
                        _AssistantKnowledgeCitationRail(
                          metadata: associatedKnowledgeBaseMetadata,
                          textColor: textColor,
                        ),
                      ],
                      if (isStreamingAssistant &&
                          resolvedMessageContentFormat !=
                              AiMessageContentFormat.html) ...[
                        kOpenHandGap6,
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _TypewriterCaret(color: textColor),
                            kOpenHandHGap6,
                            Text(
                              openHandLocalizedText(
                                context,
                                zh: '生成中',
                                en: 'Streaming',
                              ),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: textColor.withValues(alpha: 0.72),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                if (isContentPreview) ...[
                  kOpenHandGap12,
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _loadingFullContent
                            ? null
                            : () => unawaited(loadFullContent()),
                        icon: _loadingFullContent
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.unfold_more_rounded),
                        label: Text(
                          openHandLocalizedText(
                            context,
                            zh: _loadingFullContent ? '加载中' : '加载完整内容',
                            en: _loadingFullContent
                                ? 'Loading'
                                : 'Load full content',
                          ),
                        ),
                      ),
                      if (_fullContentLoadError != null)
                        ConstrainedBox(
                          constraints: kOpenHandContentMaxWidth360,
                          child: Text(
                            _fullContentLoadError!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            );
            final transcriptScrollActive = _isTranscriptScrollActive(context);
            final allowBubbleSizeMotion =
                (!transcriptScrollActive || _responseVariantSizeMotionActive) &&
                (_expansionSizeMotionActive ||
                    _responseVariantSizeMotionActive);
            final bubbleSizeDuration = allowBubbleSizeMotion
                ? cardMotionDurationFor(
                    context,
                    expanding: _expansionSizeMotionActive
                        ? _expansionSizeMotionExpanding
                        : _responseVariantSizeMotionExpanding,
                  )
                : Duration.zero;
            return ClipRect(
              child: maybeAnimatedSize(
                duration: bubbleSizeDuration,
                curve: kCardMotionCurve,
                alignment: Alignment.topLeft,
                child: bubbleContent,
              ),
            );
          },
        ),
      ),
    );
    final selectedActionPanel = _SelectedMessageActionPanelSlot(
      key: _actionPanelKey,
      visible: widget.isSelected,
      alignEnd: isUser,
      motionKey: widget.actionPanelEntranceMotionKey,
      animateEntrance: widget.animateActionPanelEntrance,
      onEntranceConsumed: widget.onActionPanelEntranceConsumed,
      message: message,
      harnessAnnotation: heAnnotation,
      textColor: textColor,
      showModelLabel: !isUser,
      associatedKnowledgeBaseMetadata: associatedKnowledgeBaseMetadata,
      onSelectResponseVariant: widget.onSelectResponseVariant,
      actions: [
        _MessageActionSpec(
          id: 'copy',
          onPressed: widget.onCopy,
          icon: Icons.content_copy_outlined,
          label: openHandCopyLabel(context),
        ),
        if (!isGoalRuntimeMessage &&
            widget.speechEnabled &&
            widget.onToggleSpeech != null)
          _MessageActionSpec(
            id: 'speech',
            onPressed: widget.onToggleSpeech,
            icon: widget.speechPlaying
                ? Icons.stop_circle_outlined
                : Icons.record_voice_over_outlined,
            label: widget.speechPlaying
                ? openHandStopLabel(context)
                : openHandLocalizedText(context, zh: '朗读', en: 'Read'),
          ),
        if (!isGoalRuntimeMessage &&
            widget.translationEnabled &&
            widget.onToggleTranslation != null)
          _MessageActionSpec(
            id: 'translation-toggle',
            onPressed: widget.translationLoading
                ? null
                : widget.onToggleTranslation,
            icon: widget.translationLoading
                ? Icons.hourglass_top_rounded
                : widget.translationVisible
                ? Icons.visibility_outlined
                : Icons.translate_rounded,
            label: widget.translationLoading
                ? openHandLocalizedText(context, zh: '翻译中', en: 'Translating')
                : widget.translationVisible
                ? openHandLocalizedText(context, zh: '查看原始', en: 'Original')
                : openHandTranslateLabel(context),
          ),
        if (isAiSideMessage && widget.onSetFeedback != null)
          _MessageActionSpec(
            id: 'feedback-like',
            onPressed: () => widget.onSetFeedback!(
              selectedFeedback == AiSessionMessageFeedback.liked
                  ? null
                  : AiSessionMessageFeedback.liked,
            ),
            icon: selectedFeedback == AiSessionMessageFeedback.liked
                ? Icons.thumb_up_alt_rounded
                : Icons.thumb_up_alt_outlined,
            label: openHandLocalizedText(context, zh: '点赞', en: 'Like'),
            selected: selectedFeedback == AiSessionMessageFeedback.liked,
          ),
        if (isAiSideMessage && widget.onSetFeedback != null)
          _MessageActionSpec(
            id: 'feedback-improve',
            onPressed: () => widget.onSetFeedback!(
              selectedFeedback == AiSessionMessageFeedback.needsImprovement
                  ? null
                  : AiSessionMessageFeedback.needsImprovement,
            ),
            icon: selectedFeedback == AiSessionMessageFeedback.needsImprovement
                ? Icons.thumb_down_alt_rounded
                : Icons.thumb_down_alt_outlined,
            label: openHandLocalizedText(context, zh: '需要改进', en: 'Improve'),
            selected:
                selectedFeedback == AiSessionMessageFeedback.needsImprovement,
          ),
        if (!isGoalRuntimeMessage &&
            isAssistantResponse &&
            !isStreamingAssistant &&
            widget.onRegenerateResponse != null)
          _MessageActionSpec(
            id: 'regenerate',
            onPressed: widget.onRegenerateResponse,
            icon: Icons.refresh_rounded,
            label: openHandRegenerateLabel(context),
          ),
        if (widget.onEdit != null)
          _MessageActionSpec(
            id: 'edit',
            onPressed: widget.onEdit,
            icon: Icons.edit_outlined,
            label: AppLocalizations.of(context)!.commonEdit,
          ),
        _MessageActionSpec(
          id: 'fork',
          onPressed: widget.onFork,
          icon: Icons.call_merge_rounded,
          label: _homeForkLabel(context),
        ),
        _MessageActionSpec(
          id: 'delete',
          onPressed: widget.onDelete,
          icon: Icons.delete_outline_rounded,
          label: AppLocalizations.of(context)!.commonDelete,
        ),
        if (widget.onDeleteFromHere != null)
          _MessageActionSpec(
            id: 'delete-from-here',
            onPressed: widget.onDeleteFromHere,
            icon: Icons.delete_sweep_outlined,
            label: openHandLocalizedText(
              context,
              zh: '删除此条及后续',
              en: 'Delete From Here',
            ),
          ),
        if (widget.onAudit != null)
          _MessageActionSpec(
            id: 'audit',
            onPressed: () async => widget.onAudit!.call(),
            icon: Icons.fact_check_outlined,
            label: openHandLocalizedText(context, zh: '审计', en: 'Audit'),
          ),
        if (!isUser &&
            !isToolCall &&
            !isSelfLearning &&
            !isCompressionPoint &&
            !isStatus &&
            !isGoalRuntimeMessage &&
            resolvedMessageContentFormat != AiMessageContentFormat.plainText)
          _MessageActionSpec(
            id: 'raw-toggle',
            onPressed: () async {
              final showRawContent = !_showRawContent;
              _armExpansionSizeMotion(expanding: showRawContent);
              setState(() => _showRawContent = showRawContent);
              widget.onShowRawContentChanged?.call(_showRawContent);
            },
            icon: _showRawContent
                ? Icons.code_off_outlined
                : Icons.code_outlined,
            label: _showRawContent
                ? openHandLocalizedText(
                    context,
                    zh: '显示渲染',
                    en: 'Show Rendered',
                  )
                : openHandLocalizedText(context, zh: '显示原始', en: 'Show Raw'),
          ),
        if (!isUser &&
            !isToolCall &&
            !isSelfLearning &&
            !isCompressionPoint &&
            !isStatus &&
            !isGoalRuntimeMessage &&
            resolvedMessageContentFormat == AiMessageContentFormat.html &&
            // 流式内容每帧变化会击穿 prepared LRU，保留直接探测；
            // 稳定内容改读缓存结果，避免每次 build 重扫全文。
            (isStreamingAssistant
                ? _looksLikeHtml(effectiveContent)
                : _preparedHtmlRenderDataFor(effectiveContent).looksLikeHtml))
          _MessageActionSpec(
            id: 'open-html',
            onPressed: () async {
              await showAnimatedDialog<void>(
                context: context,
                builder: (dialogContext) => _HtmlPreviewDialog(
                  htmlContent: effectiveContent,
                  theme: Theme.of(context),
                ),
              );
            },
            icon: Icons.open_in_browser_rounded,
            label: openHandLocalizedText(
              context,
              zh: '浏览器打开',
              en: 'Open in Browser',
            ),
          ),
      ],
    );
    final shouldTrackLayoutChanges =
        widget.trackLayoutChanges && !isGoalRuntimeMessage;
    final bubbleShell = _ResponsiveMessageWidth(
      kind: isUser
          ? _MessageBubbleWidthKind.user
          : _MessageBubbleWidthKind.assistant,
      alignment: alignment,
      child: Listener(
        key: _bubbleInteractionKey,
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          _pointerDownPosition = event.position;
          _pointerDownAt = DateTime.now();
          _htmlPointerDownState = _htmlInteractiveStateAt(event.position);
          _htmlSelectionDragActive = false;
        },
        onPointerMove: (event) {
          final htmlState = _htmlPointerDownState;
          final downPos = _pointerDownPosition;
          if (htmlState == null || downPos == null) return;
          if (_htmlInteractiveStateAt(event.position) == null) return;
          final movement = (event.position - downPos).distance;
          if (movement <= _htmlSelectionDragStartDistance) return;
          if (!_htmlSelectionDragActive) {
            _htmlSelectionDragActive = true;
            htmlState.beginSelectionAtGlobal(downPos);
          }
          htmlState.updateSelectionAtGlobal(event.position);
        },
        onPointerCancel: (event) {
          _pointerDownPosition = null;
          _pointerDownAt = null;
          _htmlPointerDownState = null;
          _htmlSelectionDragActive = false;
        },
        onPointerUp: (event) {
          final downPos = _pointerDownPosition;
          final downAt = _pointerDownAt;
          final htmlStateFromDown = _htmlPointerDownState;
          final htmlSelectionActive = _htmlSelectionDragActive;
          _pointerDownPosition = null;
          _pointerDownAt = null;
          _htmlPointerDownState = null;
          _htmlSelectionDragActive = false;
          if (downPos == null || downAt == null) return;
          // 命中消息卡片内的元数据胶囊时，只执行胶囊自身的折叠操作。
          if (_isPointerInsideMetaCapsule(event.position)) return;
          if (_isPointerInsideActionPanel(event.position) ||
              _isPointerInsideActionPanel(downPos)) {
            return;
          }
          // HTML 内嵌交互区域自行处理点击与文本选择。
          final htmlStateUp = _htmlInteractiveStateAt(event.position);
          final htmlStateDown =
              htmlStateFromDown ?? _htmlInteractiveStateAt(downPos);
          if (_isPointerInsideEmbeddedInteractiveRegion(event.position) ||
              _isPointerInsideEmbeddedInteractiveRegion(downPos)) {
            return;
          }
          if (htmlStateUp != null || htmlStateDown != null) {
            if (htmlSelectionActive) {
              (htmlStateUp ?? htmlStateDown)?.finishSelectionAtGlobal(
                event.position,
              );
              return;
            }
            final movement = (event.position - downPos).distance;
            final elapsed = DateTime.now().difference(downAt);
            if (movement <= _selectionTapMaxDistance &&
                elapsed <= _htmlTapMaxDuration) {
              (htmlStateUp ?? htmlStateDown)?.simulateTapAtGlobal(
                event.position,
              );
            }
            return;
          }
          final movement = (event.position - downPos).distance;
          final elapsed = DateTime.now().difference(downAt);
          if (movement <= _selectionTapMaxDistance &&
              elapsed <= _selectionTapMaxDuration) {
            if (!_isPointerInsideBubbleInteraction(event.position)) return;
            // 延迟切换，给卡片内部按钮一个取消切换的时间窗口。
            _scheduleSelectionToggle();
          }
        },
        child: bubbleCard,
      ),
    );
    final messageLayout = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _withLayoutChangeTracking(
          enabled: shouldTrackLayoutChanges,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isUser && attachments.isNotEmpty)
                _UserMessageAttachmentRail(attachments: attachments),
              bubbleShell,
            ],
          ),
        ),
        selectedActionPanel,
      ],
    );

    return _BubbleHtmlInteractiveScope(state: this, child: messageLayout);
  }
}

/// 把 [_MessageBubbleState] 沿着 widget 树暴露给 HTML 子组件，
/// 后者据此注册/注销内部 WebView 的 GlobalKey，便于外层 pointer 监听
/// 在命中 HTML 区域时跳过"选中卡片"切换。
class _BubbleHtmlInteractiveScope extends InheritedWidget {
  const _BubbleHtmlInteractiveScope({
    required this.state,
    required super.child,
  });

  final _MessageBubbleState state;

  static _MessageBubbleState? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_BubbleHtmlInteractiveScope>()
        ?.state;
  }

  @override
  bool updateShouldNotify(_BubbleHtmlInteractiveScope oldWidget) =>
      oldWidget.state != state;
}

const double _responseVariantChipHeight = 26;
const double _responseVariantArrowWidth = 20;
const double _responseVariantLabelMinWidth = 28;
const double _userAttachmentThumbnailExtent = 156;
const double _userAttachmentGap = 8;
const double _userAttachmentBottomSpacing = 10;
const double _userAttachmentPillMaxWidth = 340;

class _MessageActionSpec {
  const _MessageActionSpec({
    required this.id,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.selected = false,
  });

  final String id;
  final Future<void> Function()? onPressed;
  final IconData icon;
  final String label;
  final bool selected;
}

class _SelectedMessageActionPanelSlot extends StatefulWidget {
  const _SelectedMessageActionPanelSlot({
    super.key,
    required this.visible,
    required this.alignEnd,
    required this.motionKey,
    required this.animateEntrance,
    required this.onEntranceConsumed,
    required this.actions,
    required this.message,
    required this.harnessAnnotation,
    required this.textColor,
    required this.showModelLabel,
    this.associatedKnowledgeBaseMetadata,
    this.onSelectResponseVariant,
  });

  final bool visible;
  final bool alignEnd;
  final int motionKey;
  final bool animateEntrance;
  final ValueChanged<int> onEntranceConsumed;
  final List<_MessageActionSpec> actions;
  final AiSessionMessage message;
  final _HeAnnotation? harnessAnnotation;
  final Color textColor;
  final bool showModelLabel;
  final Map<String, Object?>? associatedKnowledgeBaseMetadata;
  final Future<void> Function(int index)? onSelectResponseVariant;

  @override
  State<_SelectedMessageActionPanelSlot> createState() =>
      _SelectedMessageActionPanelSlotState();
}

class _SelectedMessageActionPanelSlotState
    extends State<_SelectedMessageActionPanelSlot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this)
    ..addStatusListener(_handleStatusChanged);
  late final Animation<double> _motion = openHandBoundedCurveAnimation(
    parent: _controller,
    curve: kCardMotionCurve,
    reverseCurve: kOpenHandSwitchOutCurve,
  );
  int? _consumedMotionKey;

  bool get _shouldBuildPanel =>
      widget.visible ||
      _controller.value > 0 ||
      _controller.status != AnimationStatus.dismissed;

  @override
  void initState() {
    super.initState();
    _controller.value = widget.visible ? 1.0 : 0.0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotionDuration();
    if (widget.visible && _controller.value == 0.0) {
      _showPanel(restart: widget.animateEntrance);
    }
  }

  @override
  void didUpdateWidget(covariant _SelectedMessageActionPanelSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotionDuration();
    if (!widget.visible) {
      if (oldWidget.visible) {
        _hidePanel();
      }
      return;
    }
    final shouldRestart =
        !oldWidget.visible || oldWidget.motionKey != widget.motionKey;
    if (shouldRestart) {
      _showPanel(restart: widget.animateEntrance);
    } else if (_controller.status == AnimationStatus.dismissed) {
      _showPanel(restart: false);
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_handleStatusChanged);
    _controller.dispose();
    super.dispose();
  }

  void _syncMotionDuration() {
    final duration = cardMotionDurationFor(context, expanding: true);
    final reverseDuration = cardMotionDurationFor(context, expanding: false);
    if (_controller.duration != duration) {
      _controller.duration = duration;
    }
    if (_controller.reverseDuration != reverseDuration) {
      _controller.reverseDuration = reverseDuration;
    }
  }

  void _handleStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted) {
      setState(() {});
    }
  }

  void _consumeEntranceMotion() {
    if (!widget.animateEntrance || _consumedMotionKey == widget.motionKey) {
      return;
    }
    _consumedMotionKey = widget.motionKey;
    widget.onEntranceConsumed(widget.motionKey);
  }

  void _showPanel({required bool restart}) {
    _consumeEntranceMotion();
    if (_controller.duration == Duration.zero) {
      _controller.value = 1.0;
      return;
    }
    if (restart) {
      _controller.forward(from: 0.0);
      return;
    }
    _controller.forward();
  }

  void _hidePanel() {
    if (_controller.reverseDuration == Duration.zero) {
      _controller.value = 0.0;
      if (mounted) {
        setState(() {});
      }
      return;
    }
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldBuildPanel) {
      return const SizedBox.shrink();
    }
    final alignment = widget.alignEnd ? Alignment.topRight : Alignment.topLeft;
    final panel = Padding(
      padding: const EdgeInsets.only(top: 8),
      child: _SelectedMessageActionPanel(
        alignEnd: widget.alignEnd,
        actions: widget.actions,
        message: widget.message,
        harnessAnnotation: widget.harnessAnnotation,
        textColor: widget.textColor,
        showModelLabel: widget.showModelLabel,
        associatedKnowledgeBaseMetadata: widget.associatedKnowledgeBaseMetadata,
        onSelectResponseVariant: widget.onSelectResponseVariant,
      ),
    );
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _motion,
        child: panel,
        builder: (context, child) {
          final t = _motion.value.clamp(0.0, 1.0);
          return IgnorePointer(
            ignoring: !widget.visible || t < 0.96,
            child: Opacity(
              opacity: t,
              child: Transform.scale(
                scale: 0.97 + 0.03 * t,
                alignment: alignment,
                child: Transform.translate(
                  offset: Offset(0, 5 * (1 - t)),
                  child: child,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SelectedMessageActionPanel extends StatelessWidget {
  const _SelectedMessageActionPanel({
    required this.alignEnd,
    required this.actions,
    required this.message,
    required this.harnessAnnotation,
    required this.textColor,
    required this.showModelLabel,
    this.associatedKnowledgeBaseMetadata,
    this.onSelectResponseVariant,
  });

  final bool alignEnd;
  final List<_MessageActionSpec> actions;
  final AiSessionMessage message;
  final _HeAnnotation? harnessAnnotation;
  final Color textColor;
  final bool showModelLabel;
  final Map<String, Object?>? associatedKnowledgeBaseMetadata;
  final Future<void> Function(int index)? onSelectResponseVariant;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: alignEnd
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: alignEnd ? WrapAlignment.end : WrapAlignment.start,
            children: [
              for (final action in actions)
                _MessageActionButton(
                  key: ValueKey<String>(action.id),
                  onPressed: action.onPressed,
                  icon: action.icon,
                  label: action.label,
                  selected: action.selected,
                ),
            ],
          ),
          kOpenHandGap6,
          _SelectedMessageContextRow(
            message: message,
            harnessAnnotation: harnessAnnotation,
            textColor: textColor,
            alignEnd: alignEnd,
            showModelLabel: showModelLabel,
            associatedKnowledgeBaseMetadata: associatedKnowledgeBaseMetadata,
            onSelectResponseVariant: onSelectResponseVariant,
          ),
        ],
      ),
    );
  }
}

class _MessageActionButton extends StatelessWidget {
  const _MessageActionButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.selected = false,
  });

  final Future<void> Function()? onPressed;
  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return OpenHandMessageActionChip(
      onPressed: onPressed == null
          ? null
          : () {
              _BubbleHtmlInteractiveScope.maybeOf(
                context,
              )?.markInteractiveTap();
              unawaited(onPressed!());
            },
      icon: icon,
      label: label,
      selected: selected,
    );
  }
}

const Duration _mediaClipboardOperationTimeout = Duration(seconds: 15);
const Duration _mediaClipboardNetworkTimeout = Duration(seconds: 25);
const Duration _remoteMediaOpenTimeout = Duration(seconds: 20);
const Duration _remoteMediaHeaderTimeout = Duration(seconds: 30);
const Duration _remoteMediaChunkTimeout = Duration(seconds: 30);
const Duration _remoteMediaFileIoTimeout = Duration(seconds: 30);
const Duration _mediaPreviewTempMaxAge = Duration(days: 1);
const Duration _mediaPreviewTempCleanupTimeout = Duration(seconds: 2);
const int _mediaPreviewTempMaxFiles = 8;
const String _mediaPreviewTempFilePrefix = '.openhand_media_player_';
const String _fullscreenVideoTempFilePrefix = '.openhand_fullscreen_';
int _mediaPreviewTempSerial = 0;
const BoundedDeletePolicy _mediaPreviewTempDeletePolicy = BoundedDeletePolicy(
  maxEntries: 1,
  maxDepth: 0,
  operationTimeout: Duration(seconds: 3),
  totalTimeout: Duration(seconds: 5),
);
const Duration _remoteImageDownloadTimeout = Duration(minutes: 5);
const Duration _remoteAudioDownloadTimeout = Duration(minutes: 5);
const Duration _remoteVideoDownloadTimeout = Duration(minutes: 20);
const int _imageClipboardMaxBytes = 64 * kBytesPerMiB;
const int _remoteImageDownloadMaxBytes = 256 * kBytesPerMiB;
const int _remoteAudioDownloadMaxBytes = 256 * kBytesPerMiB;
const int _remoteVideoDownloadMaxBytes = 2 * kBytesPerGiB;

Future<void> _copyMessageMediaFileForSave({
  required String sourcePath,
  required String destinationPath,
  required int maxBytes,
}) {
  return copyFileAtomically(
    File(sourcePath),
    File(destinationPath),
    maxBytes: maxBytes,
  );
}

Future<void> _deleteMediaPreviewTempFile(String path, String action) async {
  final absolutePath = p.absolute(path);
  unregisterActiveTemporaryFile(File(absolutePath));
  try {
    await deletePathBounded(
      absolutePath,
      policy: _mediaPreviewTempDeletePolicy,
      allowedRoot: p.dirname(absolutePath),
    );
  } catch (error, stack) {
    silentLog('home_message_bubble', action, error, stack);
  }
}

Future<File> _writeMediaPreviewTempPage({
  required String mediaPath,
  required String fileNamePrefix,
  required String html,
  required String action,
}) async {
  final directory = Directory(p.dirname(mediaPath));
  await pruneTemporaryFilesBounded(
    directory,
    fileNamePrefix: fileNamePrefix,
    fileNameSuffix: '.html',
    maxRetainedFiles: _mediaPreviewTempMaxFiles - 1,
    maxAge: _mediaPreviewTempMaxAge,
    timeout: _mediaPreviewTempCleanupTimeout,
    onError: (error, stack) =>
        silentLog('home_message_bubble', '$action：清理残留临时页面', error, stack),
  );
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final serial = _mediaPreviewTempSerial++;
  final file = File(
    p.join(directory.path, '$fileNamePrefix${stamp}_${pid}_$serial.html'),
  );
  registerActiveTemporaryFile(file);
  try {
    await writeTemporaryFileTextBounded(
      file,
      html,
      timeout: _remoteMediaFileIoTimeout,
      onSecondaryError: (error, stack) =>
          silentLog('home_message_bubble', '$action：清理临时页面', error, stack),
    );
    return file;
  } catch (_) {
    unregisterActiveTemporaryFile(file);
    rethrow;
  }
}

void _showMediaClipboardSnack(
  BuildContext context, {
  required String zh,
  required String en,
  bool isError = false,
}) {
  final message = openHandLocalizedText(context, zh: zh, en: en);
  if (isError) {
    showOpenHandErrorSnack(context, message, maxLines: 2);
    return;
  }
  showOpenHandSuccessSnack(context, message);
}

Future<bool> _copyLocalFileToPasteboard(String filePath) async {
  var ok = false;
  try {
    ok = await writeOpenHandClipboardFiles(<String>[filePath]);
  } catch (_) {
    ok = false;
  } finally {
    await setOpenHandClipboardText(
      filePath,
      timeout: _mediaClipboardOperationTimeout,
    );
  }
  return ok;
}

Future<Uint8List> _readLocalClipboardBytes(
  String filePath, {
  required int maxBytes,
}) async {
  final file = File(filePath);
  return readBoundedFileBytes(
    file,
    maxBytes: maxBytes,
    idleTimeout: _mediaClipboardOperationTimeout,
    totalTimeout: _mediaClipboardOperationTimeout,
  );
}

Future<Uint8List> _downloadClipboardBytes(
  Uri uri, {
  required int maxBytes,
  String? expectedPrimaryType,
}) async {
  final client = SystemProxyResolver.instance.createRawHttpClient(
    connectionTimeout: _mediaClipboardNetworkTimeout,
  );
  try {
    return await fetchBoundedHttpBytes(
      client: client,
      uri: uri,
      maxBytes: maxBytes,
      openTimeout: _mediaClipboardNetworkTimeout,
      idleTimeout: _mediaClipboardNetworkTimeout,
      totalTimeout: _mediaClipboardNetworkTimeout,
      expectedPrimaryType: expectedPrimaryType,
    );
  } finally {
    client.close(force: true);
  }
}

Future<void> _downloadRemoteUriToFile({
  required Uri uri,
  required String destination,
  required Duration totalTimeout,
  required int maxBytes,
  String? expectedPrimaryType,
  bool allowOctetStream = true,
  Future<void>? cancelSignal,
}) async {
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    throw FileSystemException('不支持的媒体地址协议：${uri.scheme}', uri.toString());
  }

  final deadline = MonotonicDeadline(
    totalTimeout,
    timeoutMessage: '远程媒体下载超过总时限。',
  );
  final client = SystemProxyResolver.instance.createRawHttpClient(
    connectionTimeout: deadline.limit(_remoteMediaOpenTimeout),
  );
  var cancelled = false;
  if (cancelSignal != null) {
    unawaited(
      cancelSignal
          .then<void>(
            (_) {},
            onError: (Object error, StackTrace stack) {
              silentLog('home_message_bubble', '远程媒体取消信号', error, stack);
            },
          )
          .whenComplete(() {
            cancelled = true;
            client.close(force: true);
          }),
    );
  }

  try {
    final request = await openHttpClientRequestBounded(
      () => client.getUrl(uri),
      timeout: deadline.limit(_remoteMediaOpenTimeout),
      timeoutMessage: '远程媒体请求打开超时。',
    );
    if (cancelled) {
      throw const _MediaDownloadCancelled();
    }
    final response = await closeHttpClientRequestBounded(
      request,
      timeout: deadline.limit(_remoteMediaHeaderTimeout),
      timeoutMessage: '远程媒体响应头获取超时。',
    );
    if (isHttpFailureStatus(response.statusCode)) {
      throw HttpException('媒体下载失败：HTTP ${response.statusCode}。', uri: uri);
    }
    final contentType = response.headers.contentType;
    if (expectedPrimaryType != null &&
        !matchesExpectedContentType(
          contentType,
          expectedPrimaryType: expectedPrimaryType,
          allowOctetStream: allowOctetStream,
        )) {
      throw HttpException(
        '媒体响应类型不符合预期：${contentType?.mimeType ?? '未知'}',
        uri: uri,
      );
    }
    if (response.contentLength > maxBytes) {
      throw FileSystemException('媒体下载超过容量上限。', destination);
    }

    Stream<List<int>> responseChunks() async* {
      await for (final chunk in response) {
        if (cancelled) {
          throw const _MediaDownloadCancelled();
        }
        yield chunk;
      }
      if (cancelled) {
        throw const _MediaDownloadCancelled();
      }
    }

    final remainingBodyTime = deadline.remaining();
    final boundedResponse = limitByteStream(
      responseChunks(),
      maxBytes: maxBytes,
      idleTimeout: deadline.limit(_remoteMediaChunkTimeout),
      totalTimeout: remainingBodyTime,
    );
    await writeByteStreamFileAtomically(
      File(destination),
      boundedResponse,
      maxBytes: maxBytes,
      idleTimeout: deadline.limit(_remoteMediaChunkTimeout),
      totalTimeout: deadline.remaining(),
    );
  } catch (error, stack) {
    if (cancelled && error is! _MediaDownloadCancelled) {
      Error.throwWithStackTrace(const _MediaDownloadCancelled(), stack);
    }
    rethrow;
  } finally {
    deadline.stop();
    client.close(force: true);
  }
}

/// 在应用内预览消息附件。
Future<void> _openAttachment(
  BuildContext context,
  AiMessageAttachment attachment,
) async {
  final storagePath = attachment.storagePath.trim();
  if (storagePath.isEmpty) {
    return;
  }
  if (!await isRegularFilePath(storagePath)) {
    if (!context.mounted) return;
    showOpenHandErrorSnack(
      context,
      openHandLocalizedText(
        context,
        zh: '附件文件不存在或已被移动。',
        en: 'Attachment file not found or has been moved.',
      ),
    );
    return;
  }

  if (attachment.isImage) {
    if (!context.mounted) return;
    await showAnimatedDialog<void>(
      context: context,
      builder: (dialogContext) => _ImagePreviewDialog.file(
        filePath: storagePath,
        title: attachment.name,
      ),
    );
    return;
  }

  if (attachment.isVideo) {
    if (!context.mounted) return;
    await showAnimatedDialog<void>(
      context: context,
      builder: (dialogContext) => MediaPreviewDialog.file(
        filePath: storagePath,
        title: attachment.name,
        mimeType: attachment.mimeType,
        kind: MediaPreviewKind.video,
      ),
    );
    return;
  }

  if (attachment.isAudio) {
    if (!context.mounted) return;
    await showAnimatedDialog<void>(
      context: context,
      builder: (dialogContext) => MediaPreviewDialog.file(
        filePath: storagePath,
        title: attachment.name,
        mimeType: attachment.mimeType,
        kind: MediaPreviewKind.audio,
      ),
    );
    return;
  }

  if (!context.mounted) return;
  await showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) => _FilePreviewDialog(
      filePath: storagePath,
      title: attachment.name,
      sizeBytes: attachment.sizeBytes,
      kind: attachment.kind,
    ),
  );
}

final RegExp _uriSchemePattern = RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*:');
final RegExp _windowsDrivePathPattern = RegExp(r'^[A-Za-z]:([\\/]|$)');

Future<void> _openLocalPathWithSystemApp(
  BuildContext context,
  String path,
) async {
  if (!context.mounted) {
    return;
  }
  final normalizedPath = path.trim();
  if (normalizedPath.isEmpty) {
    return;
  }
  // 拒绝非本地文件路径：URI scheme 或 `-` 开头的选项标志
  // 会被 open / xdg-open 当作 URL / flag 处理。
  final looksLikeUri = _uriSchemePattern.hasMatch(normalizedPath);
  final isWindowsDrivePath =
      Platform.isWindows && _windowsDrivePathPattern.hasMatch(normalizedPath);
  final hasLeadingDash = normalizedPath.startsWith('-');
  if ((looksLikeUri && !isWindowsDrivePath) || hasLeadingDash) {
    if (context.mounted) {
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '拒绝打开不安全的路径：$normalizedPath',
          en: 'Refused unsafe path: $normalizedPath',
        ),
        maxLines: 2,
      );
    }
    return;
  }
  try {
    final launched = await openLocalPathWithSystemApp(
      normalizedPath,
      tag: 'home_message_bubble',
    );
    if (launched) {
      return;
    }
    throw FileSystemException(
      isDesktopPlatform() ? 'Failed to open file.' : 'Unsupported platform.',
      normalizedPath,
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    showOpenHandErrorSnack(
      context,
      openHandLocalizedText(
        context,
        zh: '打开文件失败：$error',
        en: 'Failed to open file: $error',
      ),
      maxLines: 2,
    );
  }
}

Future<void> _openComposerAttachment(
  BuildContext context,
  _ComposerAttachmentDraft draft,
) async {
  await _openAttachment(
    context,
    AiMessageAttachment(
      id: draft.filePath,
      storagePath: draft.filePath,
      kind: draft.kind,
      name: draft.name,
      mimeType: aiMimeTypeForPath(draft.filePath),
      sizeBytes: draft.sizeBytes,
    ),
  );
}

class _FilePreviewDialog extends StatefulWidget {
  const _FilePreviewDialog({
    required this.filePath,
    required this.title,
    required this.sizeBytes,
    required this.kind,
  });

  final String filePath;
  final String title;
  final int sizeBytes;
  final AiAttachmentKind kind;

  @override
  State<_FilePreviewDialog> createState() => _FilePreviewDialogState();
}

class _FilePreviewDialogState extends State<_FilePreviewDialog> {
  bool _copying = false;
  bool _opening = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fileName = widget.title.trim().isEmpty
        ? p.basename(widget.filePath)
        : widget.title.trim();
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).pop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: buildOpenHandResponsiveDialogShell(
        context: context,
        maxWidth: kOpenHandDialogWidthCompact,
        maxHeight: double.infinity,
        maxWidthFraction: 0.92,
        maxHeightFraction: 0.82,
        horizontalMargin: 48,
        safeAreaMinimum: const EdgeInsets.all(24),
        backgroundColor: colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: kOpenHandBorderRadius16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
              child: Row(
                children: [
                  Icon(
                    _iconForAttachmentKind(widget.kind),
                    color: colorScheme.primary,
                  ),
                  kOpenHandHGap10,
                  Expanded(
                    child: Text(
                      fileName,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  MicroPressFeedback(
                    child: IconButton(
                      icon: Icon(
                        Icons.content_copy_outlined,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      tooltip: openHandLocalizedText(
                        context,
                        zh: '复制文件',
                        en: 'Copy File',
                      ),
                      onPressed: _copying ? null : () => _copyFile(context),
                    ),
                  ),
                  kOpenHandHGap4,
                  MicroPressFeedback(
                    child: IconButton(
                      icon: Icon(
                        Icons.open_in_new_rounded,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      tooltip: _homeMessageBubOpenWithSystemAppLabel(context),
                      onPressed: _opening ? null : () => _openFile(context),
                    ),
                  ),
                  kOpenHandHGap4,
                  MicroPressFeedback(
                    child: IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.52,
                        ),
                        borderRadius: kOpenHandBorderRadius14,
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.52,
                          ),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: kOpenHandBorderRadius14,
                            ),
                            child: Icon(
                              _iconForAttachmentKind(widget.kind),
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                          kOpenHandHGap14,
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  fileName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                kOpenHandGap8,
                                Text(
                                  formatByteSize(widget.sizeBytes),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                kOpenHandGap8,
                                SelectableText(
                                  widget.filePath,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    kOpenHandGap16,
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _copying ? null : () => _copyFile(context),
                          icon: const Icon(
                            Icons.content_copy_outlined,
                            size: 18,
                          ),
                          label: Text(
                            _copying
                                ? openHandLocalizedText(
                                    context,
                                    zh: '复制中…',
                                    en: 'Copying…',
                                  )
                                : openHandCopyLabel(context),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _opening ? null : () => _openFile(context),
                          icon: const Icon(Icons.open_in_new_rounded, size: 18),
                          label: Text(_homeOpenLabel(context)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyFile(BuildContext context) async {
    if (_copying) return;
    setState(() => _copying = true);
    try {
      final file = File(widget.filePath);
      if (!await file.exists().timeout(_mediaClipboardOperationTimeout)) {
        throw FileSystemException('File not found.', widget.filePath);
      }
      final ok = await _copyLocalFileToPasteboard(widget.filePath);
      if (!context.mounted) return;
      _showMediaClipboardSnack(
        context,
        zh: ok ? '已复制文件到剪贴板。' : '当前平台不支持直接复制文件，已复制文件路径。',
        en: ok
            ? 'Copied file to clipboard.'
            : 'Direct file copy is unavailable on this platform. Copied the file path.',
      );
    } catch (error) {
      if (!context.mounted) return;
      _showMediaClipboardSnack(
        context,
        zh: '复制失败：$error',
        en: 'Copy failed: $error',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  Future<void> _openFile(BuildContext context) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await _openLocalPathWithSystemApp(context, widget.filePath);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }
}

const BorderRadius _imageShimmerRadius = BorderRadius.all(
  Radius.circular(kOpenHandRadius12),
);
const double _imageShimmerIconSize = 48;

/// 图片帧解码期间的骨架占位。
class _ImageShimmerPlaceholder extends StatelessWidget {
  const _ImageShimmerPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return OpenHandSkeletonShimmer(
      expand: true,
      borderRadius: _imageShimmerRadius,
      period: kOpenHandMotion1200,
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: _imageShimmerIconSize,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
        ),
      ),
    );
  }
}

class _AdaptivePreviewDialogMetrics {
  const _AdaptivePreviewDialogMetrics({
    required this.maxDialogWidth,
    required this.maxDialogHeight,
    required this.dialogWidth,
    required this.contentWidth,
    required this.contentHeight,
  });

  final double maxDialogWidth;
  final double maxDialogHeight;
  final double dialogWidth;
  final double contentWidth;
  final double contentHeight;

  static _AdaptivePreviewDialogMetrics fromAspectRatio({
    required Size viewport,
    required double insetPadding,
    required double chromeHeight,
    required double contentPadding,
    required double minDialogWidth,
    required Size fallbackContentSize,
    double? aspectRatio,
    double minViewportHeight = 200,
  }) {
    final maxDialogWidth = math.max(
      minDialogWidth,
      viewport.width - insetPadding * 2,
    );
    final maxDialogHeight = math.max(
      minViewportHeight,
      viewport.height - insetPadding * 2,
    );
    final maxContentWidth = math.max(0.0, maxDialogWidth - contentPadding * 2);
    final maxContentHeight = math.max(
      0.0,
      maxDialogHeight - chromeHeight - contentPadding * 2,
    );

    double contentWidth;
    double contentHeight;
    final ratio = aspectRatio;
    if (ratio != null && ratio.isFinite && ratio > 0) {
      contentWidth = maxContentWidth;
      contentHeight = contentWidth / ratio;
      if (contentHeight > maxContentHeight) {
        contentHeight = maxContentHeight;
        contentWidth = contentHeight * ratio;
      }
    } else {
      final scale = math.min(
        maxContentWidth / math.max(1.0, fallbackContentSize.width),
        maxContentHeight / math.max(1.0, fallbackContentSize.height),
      );
      final safeScale = scale.isFinite ? math.min(1.0, scale) : 1.0;
      contentWidth = fallbackContentSize.width * safeScale;
      contentHeight = fallbackContentSize.height * safeScale;
    }

    final dialogWidth = (contentWidth + contentPadding * 2)
        .clamp(minDialogWidth, maxDialogWidth)
        .toDouble();
    return _AdaptivePreviewDialogMetrics(
      maxDialogWidth: maxDialogWidth,
      maxDialogHeight: maxDialogHeight,
      dialogWidth: dialogWidth,
      contentWidth: math.max(0.0, contentWidth),
      contentHeight: math.max(0.0, contentHeight),
    );
  }

  static _AdaptivePreviewDialogMetrics fixedContent({
    required Size viewport,
    required double insetPadding,
    required double chromeHeight,
    required double contentPadding,
    required double minDialogWidth,
    required Size contentSize,
    double minViewportHeight = 200,
  }) {
    final maxDialogWidth = math.max(
      minDialogWidth,
      viewport.width - insetPadding * 2,
    );
    final maxDialogHeight = math.max(
      minViewportHeight,
      viewport.height - insetPadding * 2,
    );
    final maxContentWidth = math.max(0.0, maxDialogWidth - contentPadding * 2);
    final maxContentHeight = math.max(
      0.0,
      maxDialogHeight - chromeHeight - contentPadding * 2,
    );
    final contentWidth = contentSize.width
        .clamp(0.0, maxContentWidth)
        .toDouble();
    final contentHeight = contentSize.height
        .clamp(0.0, maxContentHeight)
        .toDouble();
    final dialogWidth = (contentWidth + contentPadding * 2)
        .clamp(minDialogWidth, maxDialogWidth)
        .toDouble();
    return _AdaptivePreviewDialogMetrics(
      maxDialogWidth: maxDialogWidth,
      maxDialogHeight: maxDialogHeight,
      dialogWidth: dialogWidth,
      contentWidth: contentWidth,
      contentHeight: contentHeight,
    );
  }
}

Size _adaptivePreviewDialogViewport(BuildContext context) {
  final viewport = MediaQuery.sizeOf(context);
  return Size(
    viewport.width * kOpenHandDialogViewportFraction,
    viewport.height * kOpenHandDialogViewportFraction,
  );
}

/// 支持缩放和平移的自适应图片预览弹窗。
///
/// 弹窗体积根据图片自身的宽高比动态贴合, 四周保留统一的 [_kPadding]
/// 留白, 与 WEB 端 `MediaPreviewDialog` (clients/web/.../MessageMedia.tsx)
/// 视觉对齐: 不再因 `BoxFit.contain` 在固定容器中产生不均的上下/左右白边。
class _ImagePreviewDialog extends StatefulWidget {
  const _ImagePreviewDialog.file({required this.filePath, required this.title})
    : imageUri = null;

  const _ImagePreviewDialog.network({
    required this.imageUri,
    required this.title,
  }) : filePath = null;

  final String? filePath;
  final Uri? imageUri;
  final String title;

  @override
  State<_ImagePreviewDialog> createState() => _ImagePreviewDialogState();
}

/// 头部实测高度：布局稳定后回填真实高度，供预览弹窗的占位高度估算使用。
///
/// 使用方在头部挂 [headerMeasureKey]，并在内容可能改变高度时调用
/// [scheduleHeaderHeightSync]；抖动小于 [_kHeaderHeightEpsilon] 时不触发重建。
mixin _MeasuredHeaderHeight<T extends StatefulWidget> on State<T> {
  static const double _kHeaderHeightEpsilon = 0.5;

  final GlobalKey headerMeasureKey = GlobalKey();
  double? measuredHeaderHeight;

  void scheduleHeaderHeightSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final renderObject = headerMeasureKey.currentContext?.findRenderObject();
      if (renderObject is! RenderBox) return;
      final height = renderObject.size.height;
      if (height <= 0) return;
      final previous = measuredHeaderHeight;
      if (previous != null &&
          (previous - height).abs() < _kHeaderHeightEpsilon) {
        return;
      }
      setState(() => measuredHeaderHeight = height);
    });
  }
}

class _ImagePreviewDialogState extends State<_ImagePreviewDialog>
    with _MeasuredHeaderHeight<_ImagePreviewDialog> {
  /// 图片四周统一的内边距 (与 WEB 端 12px 保持一致)。
  static const double _kPadding = 12.0;

  /// 弹窗到视口边缘的距离。
  static const double _kInsetPadding = 24.0;

  /// 头部区域高度估算 (Padding 14+8 + IconButton 48), 预留几像素冗余以保证
  /// body 的最大高度不会越界, 避免抖动溢出。
  static const double _kHeaderEstimate = 70.0;

  /// 头部下方分隔线高度。
  static const double _kDividerH = 1.0;

  /// 弹窗最小宽度, 确保头部图标按钮 + 标题省略号始终能够放下。
  static const double _kMinDialogW = 324.0;

  /// 加载中 / 解析失败 / 来源缺失时的方形占位边长。
  static const double _kFallbackSide = 320.0;

  late final NaturalImageSizeResolver _imageSize = NaturalImageSizeResolver(
    onResolved: () {
      if (mounted) setState(() {});
    },
  );
  // 三个互不相干的忙位：与媒体预览弹窗保持同一套并发口径，避免连点在同一
  // 目标路径上并发写入（后一次的清理会删掉前一次已写好的文件）。
  bool _isCopying = false;
  bool _isSaving = false;
  bool _isOpeningExternal = false;

  @override
  void initState() {
    super.initState();
    final filePath = widget.filePath;
    final imageUri = widget.imageUri;
    _imageSize.resolve(
      filePath != null
          ? FileImage(File(filePath))
          : imageUri != null
          ? NetworkImage(imageUri.toString())
          : null,
    );
  }

  @override
  void dispose() {
    _imageSize.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final motionSettings = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
    final viewport = _adaptivePreviewDialogViewport(context);
    scheduleHeaderHeightSync();

    final natural = _imageSize.size;
    final metrics = _AdaptivePreviewDialogMetrics.fromAspectRatio(
      viewport: viewport,
      insetPadding: _kInsetPadding,
      chromeHeight:
          math.max(_kHeaderEstimate, measuredHeaderHeight ?? 0) + _kDividerH,
      contentPadding: _kPadding,
      minDialogWidth: _kMinDialogW,
      fallbackContentSize: const Size.square(_kFallbackSide),
      aspectRatio: natural != null && natural.width > 0 && natural.height > 0
          ? natural.width / natural.height
          : null,
    );

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).pop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: buildOpenHandDialog(
        insetPadding: const EdgeInsets.all(_kInsetPadding),
        width: metrics.dialogWidth,
        maxHeight: metrics.maxDialogHeight,
        backgroundColor: colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: kOpenHandBorderRadius16,
        ),
        child: maybeAnimatedSize(
          duration: motionSettings.entranceDuration,
          curve: motionSettings.curve.curve,
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: metrics.maxDialogWidth,
              maxHeight: metrics.maxDialogHeight,
            ),
            child: SizedBox(
              width: metrics.dialogWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 头部标题栏。
                  Padding(
                    key: headerMeasureKey,
                    padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        MicroPressFeedback(
                          child: IconButton(
                            icon: Icon(
                              Icons.open_in_new_rounded,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            tooltip: _homeMessageBubOpenWithSystemAppLabel(
                              context,
                            ),
                            onPressed: _isOpeningExternal
                                ? null
                                : () => _openInSystemApp(context),
                          ),
                        ),
                        kOpenHandHGap4,
                        MicroPressFeedback(
                          child: IconButton(
                            icon: Icon(
                              Icons.content_copy_outlined,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            tooltip: openHandLocalizedText(
                              context,
                              zh: '复制图片',
                              en: 'Copy Image',
                            ),
                            onPressed: _isCopying
                                ? null
                                : () => _copyImageToClipboard(context),
                          ),
                        ),
                        kOpenHandHGap4,
                        MicroPressFeedback(
                          child: IconButton(
                            icon: Icon(
                              Icons.download_rounded,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            tooltip: _homeMessageBubSaveToDiskLabel(context),
                            onPressed: _isSaving
                                ? null
                                : () => _saveImageAs(context),
                          ),
                        ),
                        kOpenHandHGap4,
                        MicroPressFeedback(
                          child: IconButton(
                            icon: Icon(
                              Icons.close_rounded,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // 图片主体: 四周统一 _kPadding 留白, 与 WEB 端一致。
                  // SizedBox 尺寸等于媒体实际显示尺寸, Image 内部不会再产生
                  // 固定容器导致的左右或上下 letterbox 留白。
                  Padding(
                    padding: const EdgeInsets.all(_kPadding),
                    child: SizedBox(
                      width: metrics.contentWidth,
                      height: metrics.contentHeight,
                      child: OpenHandInteractiveImagePreview(
                        child: KeyedSubtree(
                          key: ValueKey<String>(_imageSourceSignature),
                          child: _buildPreviewImage(
                            context,
                            Size(metrics.contentWidth, metrics.contentHeight),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _imageSourceSignature {
    final filePath = widget.filePath;
    if (filePath != null) return 'file:$filePath';
    final imageUri = widget.imageUri;
    if (imageUri != null) return 'network:$imageUri';
    return 'empty:${widget.title}';
  }

  Future<void> _copyImageToClipboard(BuildContext context) async {
    if (_isCopying) return;
    setState(() => _isCopying = true);
    try {
      final sourceFilePath = widget.filePath;
      if (sourceFilePath != null) {
        final bytes = await _readLocalClipboardBytes(
          sourceFilePath,
          maxBytes: _imageClipboardMaxBytes,
        );
        try {
          await writeOpenHandClipboardImage(bytes);
          if (!context.mounted) return;
          _showMediaClipboardSnack(
            context,
            zh: '已复制图片到剪贴板。',
            en: 'Copied image to clipboard.',
          );
          return;
        } catch (_) {
          final ok = await _copyLocalFileToPasteboard(sourceFilePath);
          if (!context.mounted) return;
          _showMediaClipboardSnack(
            context,
            zh: ok ? '已复制图片文件到剪贴板。' : '当前平台不支持直接复制图片文件，已复制文件路径。',
            en: ok
                ? 'Copied image file to clipboard.'
                : 'Direct image file copy is unavailable on this platform. Copied the file path.',
          );
          return;
        }
      }

      final sourceUri = widget.imageUri;
      if (sourceUri == null) {
        throw const FileSystemException('Image source is unavailable.');
      }
      try {
        final bytes = await _downloadClipboardBytes(
          sourceUri,
          maxBytes: _imageClipboardMaxBytes,
          expectedPrimaryType: 'image',
        );
        await writeOpenHandClipboardImage(bytes);
        if (!context.mounted) return;
        _showMediaClipboardSnack(
          context,
          zh: '已复制图片到剪贴板。',
          en: 'Copied image to clipboard.',
        );
      } catch (_) {
        await copyOpenHandTextToClipboard(
          logTag: 'home',
          context: context,
          text: sourceUri.toString(),
          timeout: _mediaClipboardOperationTimeout,
          logAction: '复制远程图片地址兜底值',
          successMessage: openHandLocalizedText(
            context,
            zh: '无法复制图片数据，已复制图片地址。',
            en: 'Unable to copy image data. Copied the image URL.',
          ),
        );
      }
    } catch (error) {
      if (!context.mounted) return;
      _showMediaClipboardSnack(
        context,
        zh: '复制失败：$error',
        en: 'Copy failed: $error',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isCopying = false);
    }
  }

  /// 解码宽度：把原图较长边等比映射到「展示区较长边 × 缩放余量」，绝不放大。
  ///
  /// 缩放余量保证弹窗内放大查看细节时仍然清晰——放大看细节正是这个弹窗的
  /// 存在意义，按未缩放尺寸钉死解码会直接变糊。结果量化到 256px 桶：
  /// `cacheWidth` 进入 ImageProvider 的缓存键，测量抖动（首帧占位尺寸 →
  /// 真实宽高比 → 头部测高）与窗口拖拽会让它连续变化，每变一次就是一次
  /// 全量重解码外加一条新的 ImageCache 记录。
  ///
  /// 返回 null 表示按原分辨率解码（原图本就不大于目标尺寸，或尺寸未知）。
  int? _previewDecodeWidth(BuildContext context, Size displaySize) {
    const zoomHeadroom = 2.0;
    const bucketPx = 256;
    final natural = _imageSize.size;
    if (natural == null || natural.width <= 0 || natural.height <= 0) {
      return null;
    }
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final targetSide =
        math.max(displaySize.width, displaySize.height) * dpr * zoomHeadroom;
    if (!targetSide.isFinite || targetSide <= 0) return null;
    final naturalSide = math.max(natural.width, natural.height);
    if (targetSide >= naturalSide) return null;
    final bucketed =
        (natural.width * targetSide / naturalSide / bucketPx).ceil() * bucketPx;
    if (bucketed <= 0 || bucketed >= natural.width) return null;
    return bucketed;
  }

  Widget _buildPreviewImage(BuildContext context, Size displaySize) {
    // 原图尺寸已知且明显大于展示区时按比例降采样。不限制时，一张 8000×6000
    // 的生成图会解出 ~192MB 位图，直接把 ImageCache 打爆甚至 OOM。
    // 只给 cacheWidth：同时指定宽高会按精确尺寸缩放，破坏原图宽高比。
    final decodeWidth = _previewDecodeWidth(context, displaySize);
    final sourceFilePath = widget.filePath;
    if (sourceFilePath != null) {
      return Image.file(
        File(sourceFilePath),
        width: displaySize.width,
        height: displaySize.height,
        cacheWidth: decodeWidth,
        fit: BoxFit.contain,
        frameBuilder: _SafeMarkdownBodyState._fadeInImageFrameBuilder,
        errorBuilder: (context, error, stackTrace) =>
            _buildImageLoadError(context),
      );
    }

    final sourceUri = widget.imageUri;
    if (sourceUri == null) {
      return _buildImageLoadError(context);
    }

    final urlString = sourceUri.toString();
    return Image.network(
      urlString,
      width: displaySize.width,
      height: displaySize.height,
      cacheWidth: decodeWidth,
      fit: BoxFit.contain,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        // 网络图片帧解码完成 → 触发后台缓存, 下次可直接走本地文件。
        if (frame != null) {
          MediaCacheService.instance.cacheInBackground(
            urlString,
            kind: MediaCacheKind.image,
          );
        }
        return _SafeMarkdownBodyState._fadeInImageFrameBuilder(
          context,
          child,
          frame,
          wasSynchronouslyLoaded,
        );
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          return child;
        }
        final expected = loadingProgress.expectedTotalBytes;
        final progress = expected != null && expected > 0
            ? loadingProgress.cumulativeBytesLoaded / expected
            : null;
        final colorScheme = Theme.of(context).colorScheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return SizedBox.expand(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isDark
                  ? colorScheme.surfaceContainer
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: kOpenHandBorderRadius12,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 3,
                      color: colorScheme.primary,
                    ),
                  ),
                  if (progress != null) ...[
                    kOpenHandGap12,
                    Text(
                      '${(progress * 100).toStringAsFixed(0)}%',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) =>
          _buildImageLoadError(context),
    );
  }

  Widget _buildImageLoadError(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return SizedBox.expand(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.errorContainer.withValues(alpha: 0.3),
          borderRadius: kOpenHandBorderRadius12,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.broken_image_outlined,
                size: 48,
                color: colorScheme.error,
              ),
              kOpenHandGap12,
              Text(
                openHandLocalizedText(
                  context,
                  zh: '无法加载图片',
                  en: 'Failed to load image',
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.error,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openInSystemApp(BuildContext context) async {
    if (_isOpeningExternal) return;
    _isOpeningExternal = true;
    try {
      final sourceFilePath = widget.filePath;
      if (sourceFilePath != null) {
        await _openLocalPathWithSystemApp(context, sourceFilePath);
        return;
      }
      final sourceUri = widget.imageUri;
      if (sourceUri == null) {
        return;
      }
      await _openMessageLinkUri(context, sourceUri);
    } finally {
      if (mounted) setState(() => _isOpeningExternal = false);
    }
  }

  Future<void> _saveImageAs(BuildContext context) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    final basename = _suggestedSaveName();
    final ext = _normalizeSaveExtension(p.extension(basename).toLowerCase());
    final mimeType = aiMimeTypeForPath(basename);
    final extensionWithoutDot = ext.replaceFirst('.', '');
    try {
      final location = await getSaveLocation(
        suggestedName: basename,
        acceptedTypeGroups: <XTypeGroup>[
          XTypeGroup(
            label: 'Images',
            mimeTypes: <String>[mimeType],
            extensions: <String>[extensionWithoutDot],
          ),
        ],
      );
      if (location == null) return;
      final sourceFilePath = widget.filePath;
      if (sourceFilePath != null) {
        if (!await isRegularFilePath(sourceFilePath)) {
          throw FileSystemException(
            'Image source file is missing.',
            sourceFilePath,
          );
        }
        await _copyMessageMediaFileForSave(
          sourcePath: sourceFilePath,
          destinationPath: location.path,
          maxBytes: _remoteImageDownloadMaxBytes,
        );
        return;
      }

      final sourceUri = widget.imageUri;
      if (sourceUri == null) {
        throw const FileSystemException('Image source is unavailable.');
      }
      await _downloadRemoteImage(sourceUri, location.path);
    } catch (e) {
      if (!context.mounted) return;
      showFriendlyErrorSnackBar(
        context,
        message: '$e',
        fallback: openHandSaveFailedLabel(context),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _suggestedSaveName() {
    final sourceFilePath = widget.filePath;
    if (sourceFilePath != null) {
      final basename = p.basename(sourceFilePath).trim();
      if (basename.isNotEmpty) {
        return basename;
      }
    }

    final sourceUri = widget.imageUri;
    if (sourceUri != null) {
      final decodedPath = decodeUriFullOrOriginal(sourceUri.path);
      final basename = p.basename(decodedPath).trim();
      if (basename.isNotEmpty && basename != '/' && basename != '.') {
        return basename;
      }
    }
    return 'image-${DateTime.now().millisecondsSinceEpoch}.png';
  }

  String _normalizeSaveExtension(String extension) {
    if (extension.isNotEmpty) {
      return extension;
    }
    final sourceUri = widget.imageUri;
    if (sourceUri != null) {
      final format = sourceUri.queryParameters['format']?.trim().toLowerCase();
      if (format != null &&
          (format == 'png' ||
              format == 'jpg' ||
              format == 'jpeg' ||
              format == 'webp' ||
              format == 'gif' ||
              format == 'bmp')) {
        return '.$format';
      }
    }
    return '.png';
  }

  Future<void> _downloadRemoteImage(Uri sourceUri, String destination) async {
    await _downloadRemoteUriToFile(
      uri: sourceUri,
      destination: destination,
      totalTimeout: _remoteImageDownloadTimeout,
      maxBytes: _remoteImageDownloadMaxBytes,
      expectedPrimaryType: 'image',
      allowOctetStream: false,
    );
  }
}

enum _GeneratedMessageMediaKind { video, audio }

int _maxBytesForGeneratedMediaKind(_GeneratedMessageMediaKind kind) {
  return switch (kind) {
    _GeneratedMessageMediaKind.video => _remoteVideoDownloadMaxBytes,
    _GeneratedMessageMediaKind.audio => _remoteAudioDownloadMaxBytes,
  };
}

class _GeneratedMediaSource {
  const _GeneratedMediaSource({
    required this.kind,
    required this.uri,
    this.filePath,
    this.originalUri,
  });

  final _GeneratedMessageMediaKind kind;
  final Uri uri;
  final String? filePath;
  final Uri? originalUri;

  Uri get displayUri => originalUri ?? uri;
}

class _GeneratedMediaLinkSyntax extends md.InlineSyntax {
  _GeneratedMediaLinkSyntax.byExtension({required this.pathRoots})
    : super(_byExtensionPattern, caseSensitive: false);

  _GeneratedMediaLinkSyntax.byGeneratedLabel({required this.pathRoots})
    : super(_byGeneratedLabelPattern, caseSensitive: false);

  static const String _mediaExtensionAlternation =
      r'mp4|webm|mov|m4v|mkv|mp3|wav|m4a|aac|ogg|opus|flac';
  static const String _byExtensionPattern =
      r'\[([^\]\n]{0,240})\]\(([^)\s]*\.(?:' +
      _mediaExtensionAlternation +
      r')(?:[?#][^)\s]*)?)\)';
  static const String _byGeneratedLabelPattern =
      r'\[((?:AI\s+Generated\s+(?:Video|Audio)|AI\s+Audio\s+Response)[^\]\n]{0,240})\]\(([^)\s]+)\)';

  final List<String> pathRoots;

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final fullMatch = match[0] ?? '';
    final label = (match[1] ?? '').trim();
    final href = (match[2] ?? '').trim();
    final kindHint = _generatedMediaKindForLabel(label);
    final source = _resolveGeneratedMediaSource(
      href,
      pathRoots,
      kindHint: kindHint,
    );
    if (source == null) {
      parser.addNode(
        md.Element.text('a', label.isEmpty ? fullMatch : label)
          ..attributes['href'] = href,
      );
      return true;
    }
    parser.addNode(
      md.Element.text(
          'openhand-generated-media',
          label.isEmpty ? _generatedMediaFallbackTitle(source) : label,
        )
        ..attributes['href'] = href
        ..attributes['media_kind'] = source.kind.name
        ..attributes['file_path'] = source.filePath ?? '',
    );
    return true;
  }
}

class _GeneratedMediaLinkMarkdownBuilder extends MarkdownElementBuilder {
  _GeneratedMediaLinkMarkdownBuilder({
    required this.textColor,
    required this.backgroundColor,
    required this.pathRoots,
  });

  final Color textColor;
  final Color backgroundColor;
  final List<String> pathRoots;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final href = (element.attributes['href'] ?? '').trim();
    if (href.isEmpty) return null;
    final kindHint = _generatedMediaKindFromStorage(
      element.attributes['media_kind'],
    );
    final filePath = (element.attributes['file_path'] ?? '').trim();
    final source = filePath.isNotEmpty && kindHint != null
        ? _GeneratedMediaSource(
            kind: kindHint,
            uri: Uri.file(filePath),
            filePath: filePath,
          )
        : _resolveGeneratedMediaSource(href, pathRoots, kindHint: kindHint);
    if (source == null) return null;
    final label = element.textContent.trim().isEmpty
        ? _generatedMediaFallbackTitle(source)
        : element.textContent.trim();
    return Text.rich(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.only(top: 4, right: 4, bottom: 4),
          child: _GeneratedMediaLinkCard(
            source: source,
            title: label,
            textColor: textColor,
            backgroundColor: backgroundColor,
          ),
        ),
      ),
    );
  }
}

class _GeneratedMediaLinkCard extends StatefulWidget {
  const _GeneratedMediaLinkCard({
    required this.source,
    required this.title,
    required this.textColor,
    required this.backgroundColor,
  });

  final _GeneratedMediaSource source;
  final String title;
  final Color textColor;
  final Color backgroundColor;

  @override
  State<_GeneratedMediaLinkCard> createState() =>
      _GeneratedMediaLinkCardState();
}

class _GeneratedMediaLinkCardState extends State<_GeneratedMediaLinkCard> {
  // 防止快速双击重复打开预览弹窗，避免重复创建 WebView。
  bool _dialogOpen = false;
  _GeneratedMediaSource? _cachedSource;
  int _cacheRequestSerial = 0;
  final Completer<void> _disposeSignal = Completer<void>();

  _GeneratedMediaSource get _effectiveSource => _cachedSource ?? widget.source;

  @override
  void initState() {
    super.initState();
    _syncCachedSource();
  }

  @override
  void dispose() {
    _disposeSignal.complete();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _GeneratedMediaLinkCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source.filePath != widget.source.filePath ||
        oldWidget.source.uri != widget.source.uri ||
        oldWidget.source.kind != widget.source.kind) {
      _cacheRequestSerial++;
      _cachedSource = null;
      _syncCachedSource();
    }
  }

  void _syncCachedSource() {
    final source = widget.source;
    if (source.filePath != null) return;
    final url = source.uri.toString();
    final cacheKind = _mediaCacheKindForGeneratedMedia(source.kind);
    final cachedPath = MediaCacheService.instance.cachedPathForUrl(
      url,
      kind: cacheKind,
    );
    if (cachedPath != null) {
      _cachedSource = _cachedGeneratedMediaSource(source, cachedPath);
      return;
    }
    final serial = ++_cacheRequestSerial;
    unawaited(
      MediaCacheService.instance
          .ensureCached(
            url,
            kind: cacheKind,
            cancelSignal: _disposeSignal.future,
          )
          .then((cachedPath) {
            if (!mounted ||
                serial != _cacheRequestSerial ||
                cachedPath == null) {
              return;
            }
            setState(() {
              _cachedSource = _cachedGeneratedMediaSource(source, cachedPath);
            });
          }),
    );
  }

  Future<void> _openPreview() async {
    _BubbleHtmlInteractiveScope.maybeOf(context)?.markInteractiveTap();
    if (_dialogOpen) return;
    _dialogOpen = true;
    try {
      final previewSource = await _resolvePreviewSourceForDialog();
      if (!mounted) return;
      await showAnimatedDialog<void>(
        context: context,
        builder: (dialogContext) =>
            _MediaPreviewDialog(source: previewSource, title: widget.title),
      );
    } finally {
      if (mounted) _dialogOpen = false;
    }
  }

  Future<_GeneratedMediaSource> _resolvePreviewSourceForDialog() async {
    final source = _effectiveSource;
    if (source.filePath != null ||
        source.kind != _GeneratedMessageMediaKind.audio) {
      return source;
    }
    final url = source.uri.toString();
    final cacheKind = _mediaCacheKindForGeneratedMedia(source.kind);
    final cachedPath =
        MediaCacheService.instance.cachedPathForUrl(url, kind: cacheKind) ??
        await MediaCacheService.instance.ensureCached(
          url,
          kind: cacheKind,
          cancelSignal: _disposeSignal.future,
        );
    if (cachedPath == null || !mounted) return source;
    final cachedSource = _cachedGeneratedMediaSource(source, cachedPath);
    if (mounted) {
      setState(() => _cachedSource = cachedSource);
    }
    return cachedSource;
  }

  @override
  Widget build(BuildContext context) {
    final source = _effectiveSource;
    final detail = _generatedMediaSourceDetail(source);
    return GeneratedMediaResultCard(
      kind: source.kind == _GeneratedMessageMediaKind.video
          ? GeneratedMediaResultKind.video
          : GeneratedMediaResultKind.audio,
      title: widget.title,
      detail: detail,
      identity: source.filePath ?? source.displayUri.toString(),
      textColor: widget.textColor,
      backgroundColor: widget.backgroundColor,
      videoPath: source.kind == _GeneratedMessageMediaKind.video
          ? source.filePath
          : null,
      videoMimeType: source.kind == _GeneratedMessageMediaKind.video
          ? _mimeTypeForGeneratedMedia(source)
          : null,
      audioMeta: source.kind == _GeneratedMessageMediaKind.audio
          ? generatedMediaAudioVisualMeta(
              title: widget.title,
              detail: detail,
              identity: source.displayUri.toString(),
              fallbackTitle: _generatedMediaFallbackTitle(source),
            )
          : null,
      onTap: _openPreview,
    );
  }
}

NativeAudioPreviewSource _nativeAudioPreviewSourceFor(
  _GeneratedMediaSource source,
) {
  final mimeType = _mimeTypeForGeneratedMedia(source);
  final filePath = source.filePath;
  if (filePath != null) {
    return NativeAudioPreviewSource.file(
      filePath: filePath,
      mimeType: mimeType,
      detail: _generatedMediaSourceDetail(source),
    );
  }
  return NativeAudioPreviewSource.network(
    url: source.uri.toString(),
    mimeType: mimeType,
    detail: _generatedMediaSourceDetail(source),
  );
}

NativeAudioVisualMeta _nativeAudioVisualMetaForGenerated(
  _GeneratedMediaSource source,
  String title,
) {
  return generatedMediaAudioVisualMeta(
    title: title,
    detail: _generatedMediaSourceDetail(source),
    identity: source.displayUri.toString(),
    fallbackTitle: _generatedMediaFallbackTitle(source),
  );
}

class _MediaPreviewDialog extends StatefulWidget {
  const _MediaPreviewDialog({required this.source, required this.title});

  final _GeneratedMediaSource source;
  final String title;

  @override
  State<_MediaPreviewDialog> createState() => _MediaPreviewDialogState();
}

const int _kMediaPreviewControlAutoHideMs = 900;
const int _kMediaPreviewPointerLeaveHideMs = 80;

class _MediaPreviewDialogState extends State<_MediaPreviewDialog>
    with _MeasuredHeaderHeight<_MediaPreviewDialog> {
  static const Duration _mediaLoadTimeout = Duration(seconds: 18);
  static const double _kInsetPadding = 24.0;
  static const double _kContentPadding = 12.0;
  static const double _kHeaderEstimate = 74.0;
  static const double _kDividerH = 1.0;
  static const double _kMinDialogW = 360.0;
  static const double _kFallbackVideoAspectRatio = 16 / 9;

  WebViewController? _controller;
  final NativeAudioPreviewController _audioController =
      NativeAudioPreviewController();
  Timer? _loadTimeoutTimer;
  bool _pageLoaded = false;
  bool _mediaReady = false;
  String? _loadError;
  Size? _naturalMediaSize;
  // 防重入：系统播放器和保存按钮的快速双击不得启动重复任务。
  bool _isSaving = false;
  bool _isOpeningExternal = false;
  bool _isCopyingMedia = false;
  bool _isEnteringFullscreen = false;
  bool _disposed = false;
  bool _mediaBootstrapStarted = false;
  DialogAnimationSettings _playerMotionSettings = OpenHandMotionDefaults.dialog;
  // 下载中关闭弹窗时触发取消信号并清理部分文件。
  Completer<void>? _saveCancel;
  // 本地媒体旁的临时 HTML 路径，供 WKWebView 加载 file 资源。
  String? _tempHtmlPath;
  // 内嵌视频最近播放位置，用于全屏切换时无重叠地续播。
  double _currentTime = 0;
  // 主动持有键盘焦点，使空格和 Esc 无需点击 WebView 即可生效。
  final FocusNode _dialogFocus = FocusNode(debugLabel: 'media-preview');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _dialogFocus.requestFocus();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_mediaBootstrapStarted) return;
    _mediaBootstrapStarted = true;
    _playerMotionSettings = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
    if (_isVideoPreview) {
      unawaited(_bootstrapMediaPage());
      _loadTimeoutTimer = startSafeTimer(_mediaLoadTimeout, () {
        if (!mounted || _mediaReady) return;
        setState(() {
          _loadError = openHandLocalizedText(
            context,
            zh: '载入超时，可使用系统播放器打开。',
            en: 'Loading timed out. Open with the system player instead.',
          );
        });
      });
    } else {
      _pageLoaded = true;
      _mediaReady = true;
    }
  }

  Future<void> _togglePlayPause() async {
    if (!_isVideoPreview) {
      await _audioController.togglePlayPause();
      return;
    }
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.runJavaScript(
        "try{var m=window.media||document.getElementById('media');if(m){if(m.paused){var p=m.play();if(p&&p.catch)p.catch(function(){});}else{m.pause();}}}catch(_){}",
      );
    } catch (error, stack) {
      silentLog('home_message_bubble', '媒体预览：切换播放状态失败', error, stack);
    }
  }

  // 本地媒体需把 HTML 写到同目录，确保 WKWebView 获得父目录读取权限。
  Future<void> _bootstrapMediaPage() async {
    try {
      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.addJavaScriptChannel(
        'OpenHandMedia',
        onMessageReceived: _handleMediaMessage,
      );
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() => _pageLoaded = true);
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            setState(() => _loadError = error.description);
          },
        ),
      );
      if (openHandCanSetWebViewBackgroundColor(defaultTargetPlatform)) {
        await controller.setBackgroundColor(Colors.transparent);
      }
      if (!mounted) return;
      setState(() => _controller = controller);

      final localPath = widget.source.filePath;
      if (localPath != null && await isRegularFilePath(localPath)) {
        String? tempPath;
        try {
          final tempFile = await _writeMediaPreviewTempPage(
            mediaPath: localPath,
            fileNamePrefix: _mediaPreviewTempFilePrefix,
            html: _buildMediaHtml(localOverride: localPath),
            action: '媒体预览',
          );
          tempPath = tempFile.path;
          if (!mounted) {
            await _deleteMediaPreviewTempFile(tempFile.path, '媒体预览：清理未挂载的临时页面');
            return;
          }
          _tempHtmlPath = tempFile.path;
          await controller.loadFile(tempFile.path);
          return;
        } catch (error, stack) {
          final failedPath = tempPath;
          if (failedPath != null) {
            if (_tempHtmlPath == failedPath) _tempHtmlPath = null;
            await _deleteMediaPreviewTempFile(failedPath, '媒体预览：清理加载失败的临时页面');
          }
          silentLog(
            'home_message_bubble',
            '媒体预览：本地文件加载失败，回退内嵌页面',
            error,
            stack,
          );
        }
      }
      if (!mounted) return;
      await controller.loadHtmlString(_buildMediaHtml());
    } catch (error, stack) {
      silentLog('home_message_bubble', '初始化媒体预览', error, stack);
      if (!mounted) return;
      _loadTimeoutTimer?.cancel();
      setState(() {
        _loadError = openHandLocalizedText(
          context,
          zh: '媒体预览初始化失败，可使用系统播放器打开。',
          en: 'Failed to initialize the media preview. Open it with the system player instead.',
        );
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _loadTimeoutTimer?.cancel();
    final pending = _saveCancel;
    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }
    _saveCancel = null;
    final controller = _controller;
    if (controller != null) {
      // 关闭弹窗前停止播放并释放媒体资源。
      unawaited(
        controller
            .runJavaScript(openHandVideoPlayerReleaseJavaScript)
            .catchError((_) {}),
      );
    }
    _dialogFocus.dispose();
    final tempPath = _tempHtmlPath;
    if (tempPath != null) {
      unawaited(_deleteMediaPreviewTempFile(tempPath, '媒体预览：清理临时页面'));
    }
    super.dispose();
  }

  bool get _isVideoPreview =>
      widget.source.kind == _GeneratedMessageMediaKind.video;

  void _handleMediaMessage(JavaScriptMessage message) {
    if (!mounted) return;
    final value = message.message.trim();
    if (value == 'close') {
      _requestClose();
      return;
    }
    if (value == 'fullscreen') {
      if (widget.source.kind == _GeneratedMessageMediaKind.video) {
        unawaited(_enterFullscreen(context));
      }
      return;
    }
    if (value == 'ready' || value == 'canplay' || value == 'loadedmetadata') {
      _loadTimeoutTimer?.cancel();
      setState(() {
        _mediaReady = true;
        _loadError = null;
      });
      return;
    }
    if (value.startsWith('error')) {
      setState(() {
        _loadError = value.length > 6 ? value.substring(6) : value;
      });
      return;
    }
    if (value.startsWith('time:')) {
      final raw = value.substring(5);
      final parsed = optionalNonNegativeDoubleFromValue(raw);
      if (parsed != null) {
        _currentTime = parsed;
      }
      return;
    }
    if (value.startsWith('size:')) {
      final parts = value.substring(5).split(':');
      if (parts.length == 2) {
        final width = optionalPositiveDoubleFromValue(parts[0]);
        final height = optionalPositiveDoubleFromValue(parts[1]);
        if (width != null && height != null) {
          final previous = _naturalMediaSize;
          if (previous == null ||
              previous.width != width ||
              previous.height != height) {
            setState(() => _naturalMediaSize = Size(width, height));
          }
        }
      }
      return;
    }
  }

  void _requestClose() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    unawaited(Navigator.of(context).maybePop());
  }

  String _buildMediaHtml({String? localOverride}) {
    final rawSource = localOverride != null
        ? Uri.file(localOverride).toString()
        : widget.source.uri.toString();
    final source = const HtmlEscape(
      HtmlEscapeMode.attribute,
    ).convert(rawSource);
    final mimeType = _mimeTypeForGeneratedMedia(widget.source);
    final escapedMime = const HtmlEscape(
      HtmlEscapeMode.attribute,
    ).convert(mimeType);
    final durationMs = _playerMotionSettings.duration.inMilliseconds;
    final motionCurve = openHandDialogAnimationCurveCss(
      _playerMotionSettings.curve,
    );
    final motionClass = durationMs == 0 ? ' no-motion' : '';
    return '''
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
:root{--oh-motion-duration:${durationMs}ms;--oh-motion-curve:$motionCurve;--oh-control-bg:rgba(26,22,20,.76);--oh-control-border:rgba(255,255,255,.16);--oh-control-text:#fff;--oh-track:rgba(255,255,255,.20);--oh-track-fill:#fff}
html,body{margin:0;padding:0;width:100%;height:100%;background:transparent;overflow:hidden;color:#fff;font:13px/1.4 -apple-system,BlinkMacSystemFont,"PingFang SC","Microsoft YaHei","Noto Sans CJK SC","Segoe UI",Roboto,sans-serif}
button,input{font:inherit}
.media-shell{position:relative;width:100%;height:100%;display:flex;align-items:center;justify-content:center;background:#050505;user-select:none;overflow:hidden;isolation:isolate}
${openHandVideoPlayerControlsCss(compactBreakpointPx: 460, compactHorizontalInsetPx: 18)}
</style>
</head>
<body>
<div id="shell" class="media-shell controls-visible$motionClass" tabindex="0">
  <video id="media" playsinline preload="metadata" disableRemotePlayback><source src="$source" type="$escapedMime"></video>
${openHandVideoPlayerControlsHtml(trailingActionId: 'fullscreen', trailingActionLabel: 'Fullscreen')}
</div>
<script>
(function() {
  const AUTO_HIDE_MS = $_kMediaPreviewControlAutoHideMs;
  const POINTER_LEAVE_HIDE_MS = $_kMediaPreviewPointerLeaveHideMs;
  $openHandVideoPlayerElementBindingsJavaScript
  const fullscreen = document.getElementById('fullscreen');
  window.media = media;
  const post = (value) => {
    if (window.OpenHandMedia && window.OpenHandMedia.postMessage) {
      window.OpenHandMedia.postMessage(value);
    }
  };
  if (!media || !play || !rewind || !forward || !progress || !current || !duration || !volume || !mute || !volumeGroup || !playMode || !fullscreen) {
    post('error:missing_controls');
    return;
  }
  let hideTimer = 0;
  let dragging = false;
  let volumeActive = false;
  let pointerInsideShell = true;
  let looping = false;
  let lastSent = -1;
  ${openHandVideoPlayerIconsJavaScript()}
  rewind.innerHTML = icon.rewind;
  forward.innerHTML = icon.forward;
  fullscreen.innerHTML = icon.fullscreen;
  $openHandVideoPlayerScriptUtilities
  $openHandVideoPlayerVisibilityJavaScript
  $openHandVideoPlayerPointerLeaveHideJavaScript
  $openHandVideoPlayerStateSyncJavaScript
  function sendTime() {
    const t = media.currentTime || 0;
    if (Math.abs(t - lastSent) >= 0.2) {
      lastSent = t;
      post('time:' + t.toFixed(3));
    }
  }
  function reportSize() {
    const w = media.videoWidth || 0;
    const h = media.videoHeight || 0;
    if (w > 0 && h > 0) post('size:' + w + ':' + h);
  }
  ['loadedmetadata', 'canplay', 'playing'].forEach((eventName) => {
    media.addEventListener(eventName, () => {
      post(eventName);
      updateTime();
      updatePlayState();
      reportSize();
    });
  });
  media.addEventListener('error', () => post('error:' + (media.error ? String(media.error.code) : 'unknown')));
  media.addEventListener('timeupdate', sendTime);
  media.addEventListener('timeupdate', updateTime);
  media.addEventListener('pause', sendTime);
  media.addEventListener('pause', updatePlayState);
  media.addEventListener('play', updatePlayState);
  media.addEventListener('seeked', sendTime);
  media.addEventListener('seeked', updateTime);
  media.addEventListener('ended', () => { sendTime(); updatePlayState(); showControls(true); });
  media.addEventListener('volumechange', updateVolume);
  play.addEventListener('click', () => {
    if (media.paused) media.play().catch(() => showControls(true)); else media.pause();
    showControls(true);
  });
  rewind.addEventListener('click', () => seekBy(-15));
  forward.addEventListener('click', () => seekBy(15));
  progress.addEventListener('pointerdown', beginProgressDrag);
  progress.addEventListener('pointerup', endProgressDrag);
  progress.addEventListener('pointercancel', endProgressDrag);
  progress.addEventListener('input', () => {
    const dur = Number.isFinite(media.duration) ? media.duration : 0;
    if (dur > 0) media.currentTime = (Number(progress.value) / 1000) * dur;
    updateTime();
    showControls(true);
  });
  volumeGroup.addEventListener('pointerenter', () => setVolumeActive(true));
  volumeGroup.addEventListener('pointerleave', () => setVolumeActive(false));
  volumeGroup.addEventListener('pointerdown', () => setVolumeActive(true));
  volumeGroup.addEventListener('pointerup', () => setVolumeActive(false));
  volumeGroup.addEventListener('pointercancel', () => setVolumeActive(false));
  volumeGroup.addEventListener('focusin', () => setVolumeActive(true));
  volumeGroup.addEventListener('focusout', (event) => {
    if (!event.relatedTarget || !volumeGroup.contains(event.relatedTarget)) setVolumeActive(false);
  });
  volume.addEventListener('input', () => {
    const next = Math.max(0, Math.min(1, Number(volume.value)));
    media.volume = Number.isFinite(next) ? next : 1;
    media.muted = media.volume <= 0;
    updateVolume();
    setVolumeActive(true);
  });
  mute.addEventListener('click', () => {
    media.muted = !media.muted;
    if (!media.muted && media.volume <= 0) media.volume = 0.6;
    updateVolume();
    setVolumeActive(true);
  });
  playMode.addEventListener('click', () => {
    looping = !looping;
    updatePlayMode();
    showControls(true);
  });
  fullscreen.addEventListener('click', () => { post('fullscreen'); showControls(true); });
  shell.addEventListener('pointerenter', () => { pointerInsideShell = true; });
  shell.addEventListener('pointermove', () => { pointerInsideShell = true; showControls(false); });
  shell.addEventListener('pointerdown', () => showControls(false));
  shell.addEventListener('pointerleave', () => { pointerInsideShell = false; hideControlsAfterPointerLeave(); });
  shell.addEventListener('focusin', (event) => showControls(event.target !== shell));
  shell.addEventListener('focusout', hideControlsAfterPointerLeave);
  shell.addEventListener('keydown', (event) => {
    if (event.defaultPrevented) return;
    if (event.key === ' ' || event.key === 'Enter') { event.preventDefault(); play.click(); }
    else if (event.key === 'ArrowLeft') { event.preventDefault(); seekBy(-5); }
    else if (event.key === 'ArrowRight') { event.preventDefault(); seekBy(5); }
    else if (event.key.toLowerCase() === 'm') { event.preventDefault(); mute.click(); }
  });
  document.addEventListener('keydown', (event) => {
    if (event.defaultPrevented || event.key !== 'Escape') return;
    event.preventDefault();
    post('close');
  }, true);
  window.addEventListener('beforeunload', () => clearHideTimer());
  updatePlayMode();
  updatePlayState();
  updateTime();
  updateVolume();
  setTimeout(() => { if (!media || media.readyState === 0) post('error:timeout'); }, ${_mediaLoadTimeout.inMilliseconds});
})();
</script>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isVideo = widget.source.kind == _GeneratedMessageMediaKind.video;
    final viewport = _adaptivePreviewDialogViewport(context);
    final metrics = isVideo
        ? _AdaptivePreviewDialogMetrics.fromAspectRatio(
            viewport: viewport,
            insetPadding: _kInsetPadding,
            chromeHeight:
                math.max(_kHeaderEstimate, measuredHeaderHeight ?? 0) +
                _kDividerH,
            contentPadding: _kContentPadding,
            minDialogWidth: _kMinDialogW,
            fallbackContentSize: const Size(960, 540),
            aspectRatio:
                _naturalMediaSize != null &&
                    _naturalMediaSize!.width > 0 &&
                    _naturalMediaSize!.height > 0
                ? _naturalMediaSize!.width / _naturalMediaSize!.height
                : _kFallbackVideoAspectRatio,
          )
        : _AdaptivePreviewDialogMetrics.fixedContent(
            viewport: viewport,
            insetPadding: _kInsetPadding,
            chromeHeight: 0,
            contentPadding: 0,
            minDialogWidth: _kMinDialogW,
            contentSize: kNativeAudioPreviewPreferredSize,
          );
    if (isVideo) scheduleHeaderHeightSync();
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.space): _MediaPlayPauseIntent(),
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _MediaPlayPauseIntent: CallbackAction<_MediaPlayPauseIntent>(
            onInvoke: (_) {
              _togglePlayPause();
              return null;
            },
          ),
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              Navigator.of(context).pop();
              return null;
            },
          ),
        },
        child: Focus(
          focusNode: _dialogFocus,
          autofocus: true,
          child: buildOpenHandDialog(
            insetPadding: const EdgeInsets.all(_kInsetPadding),
            width: metrics.dialogWidth,
            maxHeight: metrics.maxDialogHeight,
            backgroundColor: isVideo ? colorScheme.surface : Colors.transparent,
            elevation: isVideo ? null : 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kOpenHandRadius22),
            ),
            child: isVideo
                ? _buildVideoDialogBody(context, theme, colorScheme, metrics)
                : _buildAudioDialogBody(context, metrics),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoDialogBody(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    _AdaptivePreviewDialogMetrics metrics,
  ) {
    final motionSettings = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
    return maybeAnimatedSize(
      duration: motionSettings.entranceDuration,
      curve: motionSettings.curve.curve,
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: metrics.maxDialogWidth,
          maxHeight: metrics.maxDialogHeight,
        ),
        child: SizedBox(
          width: metrics.dialogWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                key: headerMeasureKey,
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.videocam_outlined,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    kOpenHandHGap10,
                    Expanded(
                      child: Text(
                        widget.title,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    MicroPressFeedback(
                      child: IconButton(
                        icon: Icon(
                          Icons.open_in_new_rounded,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        tooltip: _homeMessageBubOpenWithSystemPlayerLabel(
                          context,
                        ),
                        onPressed: () => _openInSystemPlayer(context),
                      ),
                    ),
                    kOpenHandHGap4,
                    MicroPressFeedback(
                      child: IconButton(
                        icon: Icon(
                          Icons.content_copy_outlined,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        tooltip: _homeMessageBubCopyMediaLabel(context),
                        onPressed: _isCopyingMedia
                            ? null
                            : () => _copyMediaToClipboard(context),
                      ),
                    ),
                    kOpenHandHGap4,
                    MicroPressFeedback(
                      child: IconButton(
                        icon: Icon(
                          Icons.fullscreen_rounded,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        tooltip: openHandLocalizedText(
                          context,
                          zh: '全屏沉浸播放',
                          en: 'Fullscreen playback',
                        ),
                        onPressed: () => _enterFullscreen(context),
                      ),
                    ),
                    kOpenHandHGap4,
                    MicroPressFeedback(
                      child: IconButton(
                        icon: Icon(
                          Icons.download_rounded,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        tooltip: _homeMessageBubSaveToDiskLabel(context),
                        onPressed: () => _saveMediaAs(context),
                      ),
                    ),
                    kOpenHandHGap4,
                    MicroPressFeedback(
                      child: IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(_kContentPadding),
                child: ClipRRect(
                  borderRadius: kOpenHandBorderRadius12,
                  child: SizedBox(
                    width: metrics.contentWidth,
                    height: metrics.contentHeight,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (_controller != null)
                          Positioned.fill(
                            child: WebViewWidget(controller: _controller!),
                          ),
                        if (!_pageLoaded ||
                            (!_mediaReady && _loadError == null))
                          const Center(
                            child: CircularProgressIndicator(strokeWidth: 2.6),
                          ),
                        if (_loadError != null)
                          _MediaLoadFallback(
                            message: _loadError!,
                            onOpenExternal: () => _openInSystemPlayer(context),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAudioDialogBody(
    BuildContext context,
    _AdaptivePreviewDialogMetrics metrics,
  ) {
    final audioMotionDuration = openHandMotionDuration(
      context,
      _playerMotionSettings.duration,
    );
    return SizedBox(
      width: metrics.dialogWidth,
      height: metrics.contentHeight > 0 ? metrics.contentHeight : 560,
      child: Stack(
        children: [
          Positioned.fill(
            child: NativeAudioPreview(
              title: widget.title,
              source: _nativeAudioPreviewSourceFor(widget.source),
              meta: _nativeAudioVisualMetaForGenerated(
                widget.source,
                widget.title,
              ),
              controller: _audioController,
              onOpenExternal: () => _openInSystemPlayer(context),
              motionDuration: audioMotionDuration,
              motionCurve: _playerMotionSettings.curve.curve,
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildAudioOverlayBar(context),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioOverlayBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colorScheme.surface.withValues(alpha: 0.14),
            colorScheme.surface.withValues(alpha: 0.04),
            Colors.transparent,
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 28),
      child: Row(
        children: [
          const Spacer(),
          _AudioOverlayIconButton(
            icon: Icons.open_in_new_rounded,
            tooltip: _homeMessageBubOpenWithSystemPlayerLabel(context),
            onPressed: () => _openInSystemPlayer(context),
          ),
          kOpenHandHGap10,
          _AudioOverlayIconButton(
            icon: Icons.content_copy_outlined,
            tooltip: _homeMessageBubCopyMediaLabel(context),
            onPressed: _isCopyingMedia
                ? null
                : () => _copyMediaToClipboard(context),
          ),
          kOpenHandHGap10,
          _AudioOverlayIconButton(
            icon: Icons.download_rounded,
            tooltip: _homeMessageBubSaveToDiskLabel(context),
            onPressed: () => _saveMediaAs(context),
          ),
          kOpenHandHGap10,
          _AudioOverlayIconButton(
            icon: Icons.close_rounded,
            tooltip: openHandCloseLabel(context),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Future<void> _openInSystemPlayer(BuildContext context) async {
    if (_isOpeningExternal) return;
    _isOpeningExternal = true;
    try {
      final filePath = widget.source.filePath;
      if (filePath != null) {
        await _openLocalPathWithSystemApp(context, filePath);
        return;
      }
      await _openMessageLinkUri(context, widget.source.uri);
    } finally {
      if (!_disposed) _isOpeningExternal = false;
    }
  }

  Future<void> _copyMediaToClipboard(BuildContext context) async {
    if (_isCopyingMedia) return;
    setState(() => _isCopyingMedia = true);
    try {
      final filePath = widget.source.filePath;
      if (filePath != null) {
        final file = File(filePath);
        if (!await file.exists().timeout(_mediaClipboardOperationTimeout)) {
          throw FileSystemException('Media source file is missing.', filePath);
        }
        final ok = await _copyLocalFileToPasteboard(filePath);
        if (!context.mounted) return;
        _showMediaClipboardSnack(
          context,
          zh: ok ? '已复制媒体文件到剪贴板。' : '当前平台不支持直接复制媒体文件，已复制文件路径。',
          en: ok
              ? 'Copied media file to clipboard.'
              : 'Direct media file copy is unavailable on this platform. Copied the file path.',
        );
        return;
      }
      await copyOpenHandTextToClipboard(
        logTag: 'home',
        context: context,
        text: widget.source.uri.toString(),
        timeout: _mediaClipboardOperationTimeout,
        logAction: '复制生成媒体地址',
        successMessage: openHandLocalizedText(
          context,
          zh: '已复制媒体地址。',
          en: 'Copied media URL.',
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      _showMediaClipboardSnack(
        context,
        zh: '复制失败：$error',
        en: 'Copy failed: $error',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isCopyingMedia = false);
    }
  }

  Future<void> _enterFullscreen(BuildContext context) async {
    final controller = _controller;
    if (!_isVideoPreview || controller == null) return;
    if (_isEnteringFullscreen) return;
    _isEnteringFullscreen = true;
    // 异步暂停前先获取导航器，避免等待后再从失效上下文读取。
    final navigator = Navigator.of(context, rootNavigator: true);
    final settings = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
    try {
      // 进入全屏前暂停底层预览，避免两个音轨同时播放。
      try {
        await controller.runJavaScript(
          'try{if(window.media){window.media.pause();}}catch(_){}',
        );
      } catch (error, stack) {
        silentLog('home_message_bubble', '媒体预览：进入全屏前暂停失败', error, stack);
      }
      if (!mounted) return;
      if (!context.mounted) return;
      final returnedTime = await pushOpenHandTransitionRoute<double>(
        navigator,
        PageRouteBuilder<double>(
          fullscreenDialog: true,
          transitionDuration: settings.entranceDuration,
          reverseTransitionDuration: settings.exitDuration,
          pageBuilder: (context, animation, secondaryAnimation) =>
              _FullscreenVideoPage(
                source: widget.source,
                title: widget.title,
                initialTime: _currentTime,
                motionSettings: settings,
              ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return buildAnimationStyleTransition(
              animation: animation,
              settings: settings,
              child: child,
            );
          },
        ),
        sourceContext: context,
      );
      if (!mounted) return;
      if (returnedTime != null && returnedTime >= 0) {
        _currentTime = returnedTime;
        try {
          // 同步全屏退出进度，但不自动续播。
          await controller.runJavaScript(
            'try{if(window.media){window.media.currentTime=${returnedTime.toStringAsFixed(3)};}}catch(_){}',
          );
        } catch (error, stack) {
          silentLog('home_message_bubble', '媒体预览：全屏返回后恢复进度失败', error, stack);
        }
      }
    } finally {
      if (!_disposed) _isEnteringFullscreen = false;
    }
  }

  Future<void> _saveMediaAs(BuildContext context) async {
    if (_isSaving) return;
    _isSaving = true;
    void showSnack(
      String zh,
      String en, {
      OpenHandSnackKind kind = OpenHandSnackKind.info,
    }) {
      if (!context.mounted) return;
      final message = openHandLocalizedText(context, zh: zh, en: en);
      OpenHandGlobalSnackBarHost.hideCurrent();
      switch (kind) {
        case OpenHandSnackKind.success:
          showOpenHandSuccessSnack(context, message, maxLines: 2);
        case OpenHandSnackKind.error:
          showOpenHandErrorSnack(context, message, maxLines: 2);
        case OpenHandSnackKind.info:
          showOpenHandInfoSnack(context, message, maxLines: 2);
      }
    }

    try {
      final basename = _suggestedSaveName();
      final ext = _normalizeMediaSaveExtension(
        p.extension(basename).toLowerCase(),
        widget.source.kind,
      );
      final location = await getSaveLocation(
        suggestedName: _replaceExtensionIfNeeded(basename, ext),
        acceptedTypeGroups: <XTypeGroup>[
          XTypeGroup(
            label: widget.source.kind == _GeneratedMessageMediaKind.video
                ? 'Videos'
                : 'Audio',
            mimeTypes: <String>[_mimeTypeForExtension(ext)],
            extensions: <String>[ext.replaceFirst('.', '')],
          ),
        ],
      );
      if (location == null) return;
      showSnack('正在保存…', 'Saving…');
      final filePath = widget.source.filePath;
      if (filePath != null) {
        if (!await isRegularFilePath(filePath)) {
          throw FileSystemException('Media source file is missing.', filePath);
        }
        await _copyMessageMediaFileForSave(
          sourcePath: filePath,
          destinationPath: location.path,
          maxBytes: _maxBytesForGeneratedMediaKind(widget.source.kind),
        );
        showSnack(
          '已保存到：${location.path}',
          'Saved to: ${location.path}',
          kind: OpenHandSnackKind.success,
        );
        return;
      }
      final cancel = Completer<void>();
      _saveCancel = cancel;
      try {
        final cacheKind = _mediaCacheKindForGeneratedMedia(widget.source.kind);
        final cachedPath = MediaCacheService.instance.cachedPathForUrl(
          widget.source.uri.toString(),
          kind: cacheKind,
        );
        if (cachedPath != null && await isRegularFilePath(cachedPath)) {
          await _copyMessageMediaFileForSave(
            sourcePath: cachedPath,
            destinationPath: location.path,
            maxBytes: _maxBytesForGeneratedMediaKind(widget.source.kind),
          );
          showSnack(
            '已保存到：${location.path}',
            'Saved to: ${location.path}',
            kind: OpenHandSnackKind.success,
          );
          return;
        }
        await _downloadRemoteMedia(
          widget.source,
          location.path,
          cancelSignal: cancel.future,
        );
        unawaited(
          MediaCacheService.instance.importFile(
            widget.source.uri.toString(),
            location.path,
            kind: cacheKind,
            mimeType: _mimeTypeForGeneratedMedia(widget.source),
          ),
        );
        showSnack(
          '已保存到：${location.path}',
          'Saved to: ${location.path}',
          kind: OpenHandSnackKind.success,
        );
      } finally {
        if (identical(_saveCancel, cancel)) _saveCancel = null;
      }
    } on _MediaDownloadCancelled {
      showSnack('已取消保存。', 'Save cancelled.');
    } on TimeoutException catch (error) {
      showSnack(
        '保存超时：${error.message ?? ''}',
        'Save timed out: ${error.message ?? ''}',
        kind: OpenHandSnackKind.error,
      );
    } catch (error) {
      showSnack(
        '保存失败：$error',
        'Save failed: $error',
        kind: OpenHandSnackKind.error,
      );
    } finally {
      if (!_disposed) _isSaving = false;
    }
  }

  String _suggestedSaveName() {
    final originalUri = widget.source.originalUri;
    if (originalUri != null) {
      final basename = _basenameFromMediaUri(originalUri);
      if (basename != null) return basename;
    }
    final filePath = widget.source.filePath;
    if (filePath != null) {
      final basename = p.basename(filePath).trim();
      if (basename.isNotEmpty) return basename;
    }
    final basename = _basenameFromMediaUri(widget.source.uri);
    if (basename != null) return basename;
    final prefix = widget.source.kind == _GeneratedMessageMediaKind.video
        ? 'video'
        : 'audio';
    final ext = widget.source.kind == _GeneratedMessageMediaKind.video
        ? '.mp4'
        : '.mp3';
    return '$prefix-${DateTime.now().millisecondsSinceEpoch}$ext';
  }
}

String? _basenameFromMediaUri(Uri uri) {
  final decodedPath = decodeUriFullOrOriginal(uri.path);
  final basename = p.basename(decodedPath).trim();
  if (basename.isNotEmpty && basename != '/' && basename != '.') {
    return basename;
  }
  return null;
}

class _MediaLoadFallback extends StatelessWidget {
  const _MediaLoadFallback({
    required this.message,
    required this.onOpenExternal,
  });

  final String message;
  final VoidCallback onOpenExternal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.96),
        borderRadius: kOpenHandBorderRadius12,
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: colorScheme.error),
            kOpenHandGap10,
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            kOpenHandGap12,
            OutlinedButton.icon(
              onPressed: onOpenExternal,
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(
                openHandLocalizedText(
                  context,
                  zh: '系统播放器',
                  en: 'System Player',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioOverlayIconButton extends StatelessWidget {
  const _AudioOverlayIconButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: 38,
        child: IconButton(
          padding: EdgeInsets.zero,
          icon: Icon(icon, size: 20),
          style: IconButton.styleFrom(
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white.withValues(alpha: 0.34),
            backgroundColor: Colors.white.withValues(alpha: 0.10),
            shape: const CircleBorder(),
          ),
          onPressed: onPressed,
        ),
      ),
    );
  }
}

_GeneratedMediaSource? _resolveGeneratedMediaSource(
  String href,
  List<String> pathRoots, {
  _GeneratedMessageMediaKind? kindHint,
}) {
  final decodedHref = decodeUriFullOrOriginal(href);
  final parsed = Uri.tryParse(href);
  if (parsed != null && (parsed.scheme == 'http' || parsed.scheme == 'https')) {
    final kind =
        _generatedMediaKindForText(parsed.path.isEmpty ? href : parsed.path) ??
        kindHint;
    if (kind == null) return null;
    return _GeneratedMediaSource(kind: kind, uri: parsed);
  }
  if (parsed != null && parsed.scheme == 'file') {
    try {
      final filePath = parsed.toFilePath();
      final kind = _generatedMediaKindForText(filePath) ?? kindHint;
      if (kind == null) return null;
      return _GeneratedMediaSource(
        kind: kind,
        uri: Uri.file(filePath),
        filePath: filePath,
      );
    } catch (_) {
      return null;
    }
  }
  if (decodedHref.startsWith('/')) {
    final kind = _generatedMediaKindForText(decodedHref) ?? kindHint;
    if (kind != null) {
      return _GeneratedMediaSource(
        kind: kind,
        uri: Uri.file(decodedHref),
        filePath: decodedHref,
      );
    }
  }
  final resolvedPath = resolveMarkdownMessageLinkPath(decodedHref, pathRoots);
  if (resolvedPath?.isDirectory == true) return null;
  final localPath =
      resolvedPath?.resolvedPath ??
      firstMessagePathCandidate(decodedHref, pathRoots);
  if (localPath == null) return null;
  final kind = _generatedMediaKindForText(localPath) ?? kindHint;
  if (kind == null) return null;
  return _GeneratedMediaSource(
    kind: kind,
    uri: Uri.file(localPath),
    filePath: localPath,
  );
}

_GeneratedMessageMediaKind? _generatedMediaKindForText(String value) {
  final extension = p
      .extension(Uri.tryParse(value)?.path ?? value)
      .toLowerCase();
  if (_videoMediaExtensions.contains(extension)) {
    return _GeneratedMessageMediaKind.video;
  }
  if (_audioMediaExtensions.contains(extension)) {
    return _GeneratedMessageMediaKind.audio;
  }
  return null;
}

_GeneratedMessageMediaKind? _generatedMediaKindForLabel(String label) {
  final normalized = label.toLowerCase();
  if (normalized.contains('video')) {
    return _GeneratedMessageMediaKind.video;
  }
  if (normalized.contains('audio') || normalized.contains('speech')) {
    return _GeneratedMessageMediaKind.audio;
  }
  return null;
}

_GeneratedMessageMediaKind? _generatedMediaKindFromStorage(String? value) {
  return switch (value) {
    'video' => _GeneratedMessageMediaKind.video,
    'audio' => _GeneratedMessageMediaKind.audio,
    _ => null,
  };
}

String _generatedMediaFallbackTitle(_GeneratedMediaSource source) {
  final filePath = source.filePath;
  if (filePath != null && source.originalUri == null) {
    return p.basename(filePath);
  }
  final displayUri = source.displayUri;
  final basename = p.basename(displayUri.path).trim();
  if (basename.isNotEmpty && basename != '/' && basename != '.') {
    return basename;
  }
  return source.kind == _GeneratedMessageMediaKind.video
      ? 'AI Generated Video'
      : 'AI Generated Audio';
}

String _generatedMediaSourceDetail(_GeneratedMediaSource source) {
  final originalUri = source.originalUri;
  if (originalUri != null) {
    return originalUri.host.isEmpty ? originalUri.toString() : originalUri.host;
  }
  final filePath = source.filePath;
  if (filePath != null) return p.basename(filePath);
  return source.uri.host.isEmpty ? source.uri.toString() : source.uri.host;
}

_GeneratedMediaSource _cachedGeneratedMediaSource(
  _GeneratedMediaSource source,
  String cachedPath,
) {
  return _GeneratedMediaSource(
    kind: source.kind,
    uri: Uri.file(cachedPath),
    filePath: cachedPath,
    originalUri: source.originalUri ?? source.uri,
  );
}

MediaCacheKind _mediaCacheKindForGeneratedMedia(
  _GeneratedMessageMediaKind kind,
) {
  return switch (kind) {
    _GeneratedMessageMediaKind.video => MediaCacheKind.video,
    _GeneratedMessageMediaKind.audio => MediaCacheKind.audio,
  };
}

String _mimeTypeForGeneratedMedia(_GeneratedMediaSource source) {
  return _mimeTypeForExtension(
    p.extension(source.filePath ?? source.uri.path).toLowerCase(),
  );
}

String _mimeTypeForExtension(String extension) {
  return switch (extension) {
    '.mp4' || '.m4v' => kVideoMp4MimeType,
    '.webm' => kVideoWebmMimeType,
    '.mov' => kVideoQuickTimeMimeType,
    '.mkv' => kVideoMatroskaMimeType,
    '.mp3' => kAudioMpegMimeType,
    '.wav' => kAudioWavMimeType,
    '.m4a' => kAudioMp4MimeType,
    '.aac' => kAudioAacMimeType,
    '.ogg' || '.opus' => kAudioOggMimeType,
    '.flac' => kAudioFlacMimeType,
    _ => kApplicationOctetStreamMimeType,
  };
}

String _normalizeMediaSaveExtension(
  String extension,
  _GeneratedMessageMediaKind kind,
) {
  if (kind == _GeneratedMessageMediaKind.video &&
      _videoMediaExtensions.contains(extension)) {
    return extension;
  }
  if (kind == _GeneratedMessageMediaKind.audio &&
      _audioMediaExtensions.contains(extension)) {
    return extension;
  }
  return kind == _GeneratedMessageMediaKind.video ? '.mp4' : '.mp3';
}

String _replaceExtensionIfNeeded(String basename, String extension) {
  final current = p.extension(basename);
  if (current.toLowerCase() == extension) return basename;
  if (current.isEmpty) return '$basename$extension';
  return '${basename.substring(0, basename.length - current.length)}$extension';
}

Future<void> _downloadRemoteMedia(
  _GeneratedMediaSource source,
  String destination, {
  Future<void>? cancelSignal,
}) async {
  final isVideo = source.kind == _GeneratedMessageMediaKind.video;
  await _downloadRemoteUriToFile(
    uri: source.uri,
    destination: destination,
    totalTimeout: isVideo
        ? _remoteVideoDownloadTimeout
        : _remoteAudioDownloadTimeout,
    maxBytes: _maxBytesForGeneratedMediaKind(source.kind),
    expectedPrimaryType: isVideo ? 'video' : 'audio',
    cancelSignal: cancelSignal,
  );
}

const Set<String> _videoMediaExtensions = <String>{
  '.mp4',
  '.webm',
  '.mov',
  '.m4v',
  '.mkv',
};

class _MediaDownloadCancelled implements Exception {
  const _MediaDownloadCancelled();
  @override
  String toString() => '媒体下载已取消。';
}

const Set<String> _audioMediaExtensions = <String>{
  '.mp3',
  '.wav',
  '.m4a',
  '.aac',
  '.ogg',
  '.opus',
  '.flac',
};

enum _GoalMessageViewKind {
  autoFollowUp,
  evaluationRequest,
  evaluationResponse,
}

final RegExp _goalAutoFollowUpMarkerPattern = RegExp(
  r'\n\s*Goal:\s*',
  caseSensitive: false,
);

class _GoalMessageViewData {
  const _GoalMessageViewData({
    required this.kind,
    this.goalId,
    this.evaluationId,
    this.objective,
    this.summary,
    this.followUpPrompt,
    this.status,
    this.roundIndex,
    this.turnCount,
    this.maxTurns,
    this.tokensUsed,
    this.tokenBudget,
    this.recentMessageCount,
    this.passed,
    this.confidence,
    this.totalTokens,
    this.elapsedMs,
    this.evidence = const <String>[],
    this.missing = const <String>[],
  });

  final _GoalMessageViewKind kind;
  final String? goalId;
  final String? evaluationId;
  final String? objective;
  final String? summary;
  final String? followUpPrompt;
  final String? status;
  final int? roundIndex;
  final int? turnCount;
  final int? maxTurns;
  final int? tokensUsed;
  final int? tokenBudget;
  final int? recentMessageCount;
  final bool? passed;
  final double? confidence;
  final int? totalTokens;
  final int? elapsedMs;
  final List<String> evidence;
  final List<String> missing;

  /// 解析结果按消息对象缓存：goal 评估消息的正文是完整 JSON 载荷，
  /// 每次 build 重复 jsonDecode 是 O(content) 的纯浪费；非 goal 消息
  /// 走 metadata 快速短路，缓存 null 哨兵后连短路检查也省掉。
  static final Expando<Object> _viewDataCache = Expando<Object>(
    'goalMessageViewData',
  );
  static const Object _nullViewDataSentinel = Object();

  static _GoalMessageViewData? fromMessage(AiSessionMessage message) {
    final cached = _viewDataCache[message];
    if (cached != null) {
      return identical(cached, _nullViewDataSentinel)
          ? null
          : cached as _GoalMessageViewData;
    }
    final computed = _computeFromMessage(message);
    _viewDataCache[message] = computed ?? _nullViewDataSentinel;
    return computed;
  }

  static _GoalMessageViewData? _computeFromMessage(AiSessionMessage message) {
    final metadata = message.metadata;
    final goalId = _readString(metadata[aiSessionGoalIdMetadataKey]);
    final evaluationId = _readString(
      metadata[aiSessionGoalEvaluationIdMetadataKey],
    );
    if (metadata[aiSessionGoalAutoFollowUpMetadataKey] == true) {
      final parsed = _parseAutoFollowUp(message.content);
      return _GoalMessageViewData(
        kind: _GoalMessageViewKind.autoFollowUp,
        goalId: goalId,
        evaluationId: evaluationId,
        objective: _readString(
          metadata[aiSessionGoalObjectiveMetadataKey],
        ).ifEmpty(parsed.objective),
        followUpPrompt: parsed.prompt,
      );
    }
    if (metadata[aiSessionGoalEvaluationMessageMetadataKey] != true) {
      return null;
    }
    final type = _readString(
      metadata[aiSessionGoalEvaluationMessageTypeMetadataKey],
    );
    if (type == aiSessionGoalEvaluationMessageTypeRequest) {
      final payload = _decodeJsonObject(message.content, marker: '{"goal":');
      final goal = _object(payload?['goal']);
      final recentMessages = payload?['recent_messages'];
      return _GoalMessageViewData(
        kind: _GoalMessageViewKind.evaluationRequest,
        goalId: goalId.ifEmpty(_readString(goal?['id'])),
        evaluationId: evaluationId,
        objective: _readString(goal?['objective']),
        status: _readString(goal?['status']),
        roundIndex: _readInt(
          metadata[aiSessionGoalEvaluationRoundIndexMetadataKey],
        ),
        turnCount: _readInt(goal?['turn_count']),
        maxTurns: _readInt(goal?['max_turns']),
        tokensUsed: _readInt(goal?['tokens_used']),
        tokenBudget: _readInt(goal?['token_budget']),
        recentMessageCount: recentMessages is List
            ? recentMessages.length
            : null,
      );
    }
    if (type == aiSessionGoalEvaluationMessageTypeResponse) {
      final decoded = _decodeJsonObject(message.content);
      return _GoalMessageViewData(
        kind: _GoalMessageViewKind.evaluationResponse,
        goalId: goalId,
        evaluationId: evaluationId,
        summary: _readString(decoded?['summary']),
        followUpPrompt: _readString(decoded?['follow_up_prompt']),
        roundIndex: _readInt(
          metadata[aiSessionGoalEvaluationRoundIndexMetadataKey],
        ),
        passed:
            decoded?['passed'] == true ||
            metadata[aiSessionGoalEvaluationPassedMetadataKey] == true,
        confidence: _readDouble(decoded?['confidence']),
        totalTokens: _readInt(metadata[aiSessionGoalTotalTokensMetadataKey]),
        elapsedMs: _readInt(metadata[aiSessionGoalElapsedMsMetadataKey]),
        evidence: _readStringList(decoded?['evidence']),
        missing: _readStringList(decoded?['missing']),
      );
    }
    return null;
  }

  static ({String? prompt, String? objective}) _parseAutoFollowUp(
    String content,
  ) {
    final trimmed = content.trim();
    final marker = _goalAutoFollowUpMarkerPattern.firstMatch(trimmed);
    if (marker == null) {
      return (prompt: trimmed.ifEmpty(null), objective: null);
    }
    final prompt = trimmed.substring(0, marker.start).trim();
    final objective = trimmed.substring(marker.end).trim();
    return (prompt: prompt.ifEmpty(null), objective: objective.ifEmpty(null));
  }

  static Map<String, Object?>? _decodeJsonObject(
    String content, {
    String? marker,
  }) {
    final start = marker == null
        ? content.indexOf('{')
        : content.indexOf(marker);
    if (start < 0) {
      return null;
    }
    try {
      final decoded = jsonDecode(content.substring(start).trim());
      return _object(decoded);
    } catch (_) {
      return null;
    }
  }

  static Map<String, Object?>? _object(Object? value) {
    if (value is! Map) {
      return null;
    }
    return stringKeyedMapFromValue(value);
  }

  static String _readString(Object? value) {
    final text = stringFromValue(value);
    return text == 'null' ? '' : text;
  }

  static int? _readInt(Object? value) {
    return optionalRoundedIntFromValue(value);
  }

  static double? _readDouble(Object? value) {
    return optionalDoubleFromValue(value);
  }

  static List<String> _readStringList(Object? value) {
    return stringListFromValue(
      value,
      ignoreLiteralNull: true,
    ).take(aiSessionGoalEvaluationMaxEvidenceItems).toList(growable: false);
  }

  String chipLabel(BuildContext context) {
    final round = roundIndex == null ? '' : ' · #$roundIndex';
    return switch (kind) {
      _GoalMessageViewKind.autoFollowUp => openHandLocalizedText(
        context,
        zh: '目标自动推进',
        en: 'Goal Auto Follow-up',
      ),
      _GoalMessageViewKind.evaluationRequest =>
        openHandLocalizedText(
              context,
              zh: '目标评估请求',
              en: 'Goal Evaluation Request',
            ) +
            round,
      _GoalMessageViewKind.evaluationResponse =>
        openHandLocalizedText(
              context,
              zh: '目标评估响应',
              en: 'Goal Evaluation Response',
            ) +
            round,
    };
  }

  IconData get icon => switch (kind) {
    _GoalMessageViewKind.autoFollowUp => Icons.flag_outlined,
    _GoalMessageViewKind.evaluationRequest => Icons.fact_check_outlined,
    _GoalMessageViewKind.evaluationResponse => Icons.verified_outlined,
  };

  Color accentColor(ThemeData theme) => switch (kind) {
    _GoalMessageViewKind.autoFollowUp => theme.colorScheme.primary,
    _GoalMessageViewKind.evaluationRequest => theme.colorScheme.secondary,
    _GoalMessageViewKind.evaluationResponse =>
      passed == true
          ? OpenHandStatusColors.success
          : theme.colorScheme.tertiary,
  };
}

extension _GoalNullableString on String {
  String? ifEmpty(String? fallback) => isEmpty ? fallback : this;
}

class _MachineExpertRequestStructuredBody extends StatelessWidget {
  const _MachineExpertRequestStructuredBody({
    required this.data,
    required this.textColor,
  });

  final AiMachineExpertRequestCard data;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return _ExpertRequestStructuredBody(
      icon: Icons.terminal_rounded,
      title: openHandLocalizedText(
        context,
        zh: '机器专家执行请求',
        en: 'Machine Expert Request',
      ),
      description: openHandLocalizedText(
        context,
        zh: '已绑定目标终端，会在指定会话中执行任务。',
        en: 'The target terminal is bound for this task.',
      ),
      textColor: textColor,
      chips: [
        const _ExpertRequestChipData(
          icon: Icons.looks_one_rounded,
          label: '#1',
        ),
        _ExpertRequestChipData(
          icon: Icons.memory_rounded,
          label: openHandLocalizedText(
            context,
            zh: '机器专家',
            en: 'Machine Expert',
          ),
        ),
        if ((data.appleScriptTarget ?? '').trim().isNotEmpty)
          _ExpertRequestChipData(
            icon: Icons.my_location_rounded,
            label: _homeMessageBubPreciseTargetLabel(context),
          ),
      ],
      fields: [
        if (data.terminalApplication.trim().isNotEmpty)
          _ExpertRequestFieldData(
            label: openHandLocalizedText(context, zh: '终端应用', en: 'Terminal'),
            value: data.terminalApplication.trim(),
          ),
        if (data.terminalLocation.trim().isNotEmpty)
          _ExpertRequestFieldData(
            label: openHandLocalizedText(context, zh: '打开位置', en: 'Location'),
            value: data.terminalLocation.trim(),
          ),
        if ((data.appleScriptTarget ?? '').trim().isNotEmpty)
          _ExpertRequestFieldData(
            label: _homeMessageBubPreciseTargetLabel(context),
            value: data.appleScriptTarget!.trim(),
          ),
        if (data.taskRequirement.trim().isNotEmpty)
          _ExpertRequestFieldData(
            label: openHandLocalizedText(context, zh: '需求', en: 'Request'),
            value: data.taskRequirement.trim(),
          ),
      ],
      truncated: data.truncated,
    );
  }
}

class _WebReverseRequestStructuredBody extends StatelessWidget {
  const _WebReverseRequestStructuredBody({
    required this.data,
    required this.textColor,
  });

  final AiWebReverseRequestCard data;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return _ExpertRequestStructuredBody(
      icon: Icons.language_rounded,
      title: _homeMessageBubWebReverseRequestLabel(context),
      description: openHandLocalizedText(
        context,
        zh: '已绑定目标页面与 CDP 环境，按浏览器取证流程推进。',
        en: 'The target page and CDP environment are bound for this task.',
      ),
      textColor: textColor,
      chips: [
        const _ExpertRequestChipData(
          icon: Icons.looks_one_rounded,
          label: '#1',
        ),
        _ExpertRequestChipData(
          icon: Icons.travel_explore_rounded,
          label: openHandLocalizedText(
            context,
            zh: 'Web 逆向',
            en: 'Web Reverse',
          ),
        ),
        if (data.cdpPort.trim().isNotEmpty)
          _ExpertRequestChipData(
            icon: Icons.settings_ethernet_rounded,
            label: 'CDP ${data.cdpPort.trim()}',
          ),
        if (data.loginState.trim().isNotEmpty)
          _ExpertRequestChipData(
            icon: Icons.verified_user_outlined,
            label: data.loginState.trim(),
          ),
      ],
      fields: [
        if (data.targetUrl.trim().isNotEmpty)
          _ExpertRequestFieldData(
            label: openHandTargetUrlLabel(context),
            value: data.targetUrl.trim(),
          ),
        if (data.reverseTarget.trim().isNotEmpty)
          _ExpertRequestFieldData(
            label: openHandObjectiveLabel(context),
            value: data.reverseTarget.trim(),
          ),
        if ((data.triggerActions ?? '').trim().isNotEmpty)
          _ExpertRequestFieldData(
            label: openHandTriggerActionsLabel(context),
            value: data.triggerActions!.trim(),
          ),
        if (data.browser.trim().isNotEmpty)
          _ExpertRequestFieldData(
            label: openHandBrowserLabel(context),
            value: data.browser.trim(),
          ),
        if (data.cdpMcp.trim().isNotEmpty)
          _ExpertRequestFieldData(
            label: openHandLocalizedText(
              context,
              zh: 'AI 侧 CDP MCP',
              en: 'CDP MCP',
            ),
            value: data.cdpMcp.trim(),
          ),
        if ((data.proxy ?? '').trim().isNotEmpty)
          _ExpertRequestFieldData(
            label: openHandProxyLabel(context),
            value: data.proxy!.trim(),
          ),
        if ((data.keywords ?? '').trim().isNotEmpty)
          _ExpertRequestFieldData(
            label: openHandKeywordsLabel(context),
            value: data.keywords!.trim(),
          ),
        if (data.evidenceDiscipline.trim().isNotEmpty)
          _ExpertRequestFieldData(
            label: _homeMessageBubEvidenceRulesLabel(context),
            value: data.evidenceDiscipline.trim(),
          ),
        if (data.deliverables.trim().isNotEmpty)
          _ExpertRequestFieldData(
            label: openHandLocalizedText(
              context,
              zh: '任务产物',
              en: 'Deliverables',
            ),
            value: data.deliverables.trim(),
          ),
        if (data.acceptanceCriteria.trim().isNotEmpty)
          _ExpertRequestFieldData(
            label: _homeMessageBubAcceptanceLabel(context),
            value: data.acceptanceCriteria.trim(),
          ),
      ],
      truncated: data.truncated,
    );
  }
}

class _AndroidReverseRequestStructuredBody extends StatelessWidget {
  const _AndroidReverseRequestStructuredBody({
    required this.data,
    required this.textColor,
  });

  final AiAndroidReverseRequestCard data;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return _ExpertRequestStructuredBody(
      icon: Icons.android_rounded,
      title: _homeMessageBubAndroidReverseRequestLabel(context),
      description: openHandLocalizedText(
        context,
        zh: '已绑定目标应用与分析边界，按静态优先取证流程推进。',
        en: 'The target app and analysis boundary are bound for this task.',
      ),
      textColor: textColor,
      chips: [
        const _ExpertRequestChipData(
          icon: Icons.looks_one_rounded,
          label: '#1',
        ),
        _ExpertRequestChipData(
          icon: Icons.android_rounded,
          label: openHandLocalizedText(
            context,
            zh: 'Android 逆向',
            en: 'Android Reverse',
          ),
        ),
        if ((data.packageName ?? '').trim().isNotEmpty)
          _ExpertRequestChipData(
            icon: Icons.apps_rounded,
            label: data.packageName!.trim(),
          ),
        if ((data.apkPath ?? '').trim().isNotEmpty)
          _ExpertRequestChipData(
            icon: Icons.inventory_2_outlined,
            label: openHandLocalizedText(context, zh: 'APK', en: 'APK'),
          ),
      ],
      fields: [
        if (data.reverseTarget.trim().isNotEmpty)
          _ExpertRequestFieldData(
            label: openHandObjectiveLabel(context),
            value: data.reverseTarget.trim(),
          ),
        if ((data.packageName ?? '').trim().isNotEmpty)
          _ExpertRequestFieldData(
            label: openHandLocalizedText(context, zh: '目标包名', en: 'Package'),
            value: data.packageName!.trim(),
          ),
        if ((data.apkPath ?? '').trim().isNotEmpty)
          _ExpertRequestFieldData(
            label: openHandLocalizedText(context, zh: 'APK 路径', en: 'APK Path'),
            value: data.apkPath!.trim(),
          ),
        if (data.deviceDisplay.trim().isNotEmpty)
          _ExpertRequestFieldData(
            label: openHandDeviceLabel(context),
            value: data.deviceDisplay.trim(),
          ),
        if (data.analysisMode.trim().isNotEmpty)
          _ExpertRequestFieldData(
            label: openHandLocalizedText(
              context,
              zh: '分析模式',
              en: 'Analysis Mode',
            ),
            value: data.analysisMode.trim(),
          ),
        if (data.authorizationScope.trim().isNotEmpty)
          _ExpertRequestFieldData(
            label: openHandLocalizedText(
              context,
              zh: '授权范围',
              en: 'Authorization Scope',
            ),
            value: data.authorizationScope.trim(),
          ),
        if (data.adbMcp.trim().isNotEmpty)
          _ExpertRequestFieldData(
            label: openHandLocalizedText(context, zh: 'ADB MCP', en: 'ADB MCP'),
            value: data.adbMcp.trim(),
          ),
        if (data.fridaMcp.trim().isNotEmpty)
          _ExpertRequestFieldData(
            label: openHandLocalizedText(
              context,
              zh: 'Frida MCP',
              en: 'Frida MCP',
            ),
            value: data.fridaMcp.trim(),
          ),
        if ((data.keywords ?? '').trim().isNotEmpty)
          _ExpertRequestFieldData(
            label: openHandKeywordsLabel(context),
            value: data.keywords!.trim(),
          ),
        if ((data.notes ?? '').trim().isNotEmpty)
          _ExpertRequestFieldData(
            label: openHandNotesLabel(context),
            value: data.notes!.trim(),
          ),
        if (data.evidenceDiscipline.trim().isNotEmpty)
          _ExpertRequestFieldData(
            label: _homeMessageBubEvidenceRulesLabel(context),
            value: data.evidenceDiscipline.trim(),
          ),
        if (data.acceptanceCriteria.trim().isNotEmpty)
          _ExpertRequestFieldData(
            label: _homeMessageBubAcceptanceLabel(context),
            value: data.acceptanceCriteria.trim(),
          ),
      ],
      truncated: data.truncated,
    );
  }
}

class _ExpertRequestStructuredBody extends StatelessWidget {
  const _ExpertRequestStructuredBody({
    required this.icon,
    required this.title,
    required this.description,
    required this.textColor,
    required this.chips,
    required this.fields,
    required this.truncated,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color textColor;
  final List<_ExpertRequestChipData> chips;
  final List<_ExpertRequestFieldData> fields;
  final bool truncated;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: accent),
            kOpenHandHGap8,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  kOpenHandGap4,
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: textColor.withValues(alpha: 0.78),
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (chips.isNotEmpty) ...[
          kOpenHandGap12,
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final chip in chips)
                _GoalMessageMetricChip(icon: chip.icon, label: chip.label),
            ],
          ),
        ],
        for (final field in fields) ...[
          kOpenHandGap12,
          _GoalMessageField(
            label: field.label,
            value: field.value,
            textColor: textColor,
          ),
        ],
        if (truncated) ...[
          kOpenHandGap10,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 15,
                color: textColor.withValues(alpha: 0.70),
              ),
              kOpenHandHGap6,
              Expanded(
                child: Text(
                  openHandLocalizedText(
                    context,
                    zh: '卡片内容已截断，完整原文仍保留在消息审计与复制内容中。',
                    en: 'Card content is shortened; the full source remains available for audit and copy.',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: textColor.withValues(alpha: 0.70),
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ExpertRequestChipData {
  const _ExpertRequestChipData({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class _ExpertRequestFieldData {
  const _ExpertRequestFieldData({required this.label, required this.value});

  final String label;
  final String value;
}

class _GoalMessageStructuredBody extends StatelessWidget {
  const _GoalMessageStructuredBody({
    required this.data,
    required this.textColor,
  });

  final _GoalMessageViewData data;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = data.accentColor(theme);
    final title = switch (data.kind) {
      _GoalMessageViewKind.autoFollowUp => openHandLocalizedText(
        context,
        zh: '继续推进当前目标',
        en: 'Continue Current Goal',
      ),
      _GoalMessageViewKind.evaluationRequest => openHandLocalizedText(
        context,
        zh: '验证目标完成证据',
        en: 'Verify Goal Evidence',
      ),
      _GoalMessageViewKind.evaluationResponse =>
        data.passed == true
            ? openHandLocalizedText(
                context,
                zh: '目标证据已通过',
                en: 'Goal Evidence Passed',
              )
            : openHandLocalizedText(
                context,
                zh: '目标仍需推进',
                en: 'Goal Still Needs Work',
              ),
    };
    final description = switch (data.kind) {
      _GoalMessageViewKind.autoFollowUp => openHandLocalizedText(
        context,
        zh: 'Agent Runtime 自动发送，用于在上一轮评估未通过后继续收敛目标。',
        en: 'Agent Runtime sent this automatically after evaluation required more evidence.',
      ),
      _GoalMessageViewKind.evaluationRequest => openHandLocalizedText(
        context,
        zh: '评估模型会基于当前目标和最近对话判断完成证据是否充分。',
        en: 'The evaluator checks the current goal and recent transcript for completion evidence.',
      ),
      _GoalMessageViewKind.evaluationResponse =>
        data.passed == true
            ? openHandLocalizedText(
                context,
                zh: '评估模型认为当前证据足以完成目标。',
                en: 'The evaluator found enough evidence to complete the goal.',
              )
            : openHandLocalizedText(
                context,
                zh: '评估模型认为证据仍不足，需要继续推进。',
                en: 'The evaluator found the evidence insufficient and requested more work.',
              ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(data.icon, size: 18, color: accent),
            kOpenHandHGap8,
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
        kOpenHandGap8,
        Text(
          description,
          style: theme.textTheme.bodySmall?.copyWith(
            color: textColor.withValues(alpha: 0.78),
            height: 1.45,
          ),
        ),
        if ((data.objective ?? '').trim().isNotEmpty) ...[
          kOpenHandGap12,
          _GoalMessageField(
            label: _homeMessageBubGoalLabel(context),
            value: data.objective!.trim(),
            textColor: textColor,
          ),
        ],
        if ((data.summary ?? '').trim().isNotEmpty) ...[
          kOpenHandGap12,
          _GoalMessageField(
            label: openHandLocalizedText(
              context,
              zh: '评估摘要',
              en: 'Evaluation Summary',
            ),
            value: data.summary!.trim(),
            textColor: textColor,
          ),
        ],
        if ((data.followUpPrompt ?? '').trim().isNotEmpty &&
            data.kind != _GoalMessageViewKind.autoFollowUp) ...[
          kOpenHandGap12,
          _GoalMessageField(
            label: openHandLocalizedText(context, zh: '下一步', en: 'Next Step'),
            value: data.followUpPrompt!.trim(),
            textColor: textColor,
          ),
        ],
        if (data.evidence.isNotEmpty) ...[
          kOpenHandGap12,
          _GoalMessageBulletList(
            label: _homeEvidenceLabel(context),
            values: data.evidence,
            textColor: textColor,
            accent: OpenHandStatusColors.success,
          ),
        ],
        if (data.missing.isNotEmpty) ...[
          kOpenHandGap12,
          _GoalMessageBulletList(
            label: _homeMissingLabel(context),
            values: data.missing,
            textColor: textColor,
            accent: theme.colorScheme.tertiary,
          ),
        ],
        if (_metricChips(context).isNotEmpty) ...[
          kOpenHandGap12,
          Wrap(spacing: 6, runSpacing: 6, children: _metricChips(context)),
        ],
      ],
    );
  }

  List<Widget> _metricChips(BuildContext context) {
    final chips = <Widget>[];
    void add(IconData icon, String label) {
      if (label.trim().isEmpty) return;
      chips.add(_GoalMessageMetricChip(icon: icon, label: label));
    }

    if (data.roundIndex != null) {
      add(Icons.repeat_rounded, '#${data.roundIndex}');
    }
    if (data.turnCount != null || data.maxTurns != null) {
      add(
        Icons.route_outlined,
        '${data.turnCount ?? 0}/${data.maxTurns ?? aiSessionGoalDefaultMaxAutoTurns}',
      );
    }
    if (data.tokensUsed != null) {
      final budget = data.tokenBudget == null ? '' : '/${data.tokenBudget}';
      add(
        Icons.speed_rounded,
        '${data.tokensUsed}$budget ${openHandLocalizedText(context, zh: '令牌', en: 'tokens')}',
      );
    }
    if (data.recentMessageCount != null) {
      add(
        Icons.chat_bubble_outline_rounded,
        openHandLocalizedText(
          context,
          zh: '最近 ${data.recentMessageCount} 条',
          en: '${data.recentMessageCount} recent',
        ),
      );
    }
    if (data.confidence != null) {
      add(
        Icons.query_stats_rounded,
        '${(data.confidence!.clamp(0, 1) * 100).round()}%',
      );
    }
    if (data.passed == true && data.elapsedMs != null) {
      add(
        Icons.timer_outlined,
        '${openHandTotalTimeLabel(context)} ${formatCompactDurationMs(data.elapsedMs!)}',
      );
    }
    if (data.passed == true && data.totalTokens != null) {
      add(
        Icons.speed_rounded,
        '${openHandLocalizedText(context, zh: '总令牌', en: 'Total tokens')} ${data.totalTokens}',
      );
    }
    return chips;
  }
}

class _GoalMessageField extends StatelessWidget {
  const _GoalMessageField({
    required this.label,
    required this.value,
    required this.textColor,
  });

  final String label;
  final String value;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: textColor.withValues(alpha: 0.62),
            fontWeight: FontWeight.w800,
          ),
        ),
        kOpenHandGap4,
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: textColor,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _GoalMessageBulletList extends StatelessWidget {
  const _GoalMessageBulletList({
    required this.label,
    required this.values,
    required this.textColor,
    required this.accent,
  });

  final String label;
  final List<String> values;
  final Color textColor;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: accent,
            fontWeight: FontWeight.w800,
          ),
        ),
        kOpenHandGap6,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final value in values)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '•',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: accent,
                        height: 1.45,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    kOpenHandHGap8,
                    Expanded(
                      child: Text(
                        value,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: textColor,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _GoalMessageMetricChip extends StatelessWidget {
  const _GoalMessageMetricChip({required this.label, this.icon});

  static const double _fallbackMaxWidth = 520;
  static const double _viewportWidthFactor = 0.72;
  static const double _minReadableWidth = 120;
  static const int _maxLabelLines = 3;

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = MediaQuery.sizeOf(context).width;
        final fallbackWidth = math.min(
          _fallbackMaxWidth,
          viewportWidth * _viewportWidthFactor,
        );
        final maxWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : math.max(_minReadableWidth, fallbackWidth);
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: kOpenHandPillBorderRadius,
              border: Border.all(color: color.withValues(alpha: 0.18)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 13, color: color),
                  kOpenHandHGap4,
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: _maxLabelLines,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _KnowledgeBaseCitationSource {
  const _KnowledgeBaseCitationSource({required this.key, required this.label});

  final String key;
  final String label;
}

Map<String, Object?> _knowledgeBaseMetadataEnvelope(
  Map<String, Object?> metadata,
) {
  return <String, Object?>{knowledgeBaseMessageMetadataKey: metadata};
}

List<Map<String, Object?>> _knowledgeBaseResultMaps(
  Map<String, Object?> metadata,
) {
  return stringKeyedMapListFromValue(metadata['results']);
}

Map<String, Object?>? _knowledgeBaseMetadataUsedByAnswer(
  Map<String, Object?>? metadata,
  String answerText,
) {
  return KnowledgeMessageMetadata.usedReferencesByAnswer(metadata, answerText);
}

Map<String, Object?>? _knowledgeBaseMetadataFromRoundToolMessages(
  List<AiSessionMessage> messages,
  String answerText,
) {
  return KnowledgeMessageMetadata.usedReferencesFromToolMetadata(
    toolMessages: messages
        .where(
          (message) =>
              message.kind == AiSessionMessageKind.toolCall ||
              message.kind == AiSessionMessageKind.tool,
        )
        .map((message) => message.metadata),
    answerText: answerText,
  );
}

List<_KnowledgeBaseCitationSource> _knowledgeBaseCitationSources(
  Map<String, Object?> metadata, {
  int limit = 1 << 30,
}) {
  final sources = <_KnowledgeBaseCitationSource>[];
  final seen = <String>{};
  for (final hit in _knowledgeBaseResultMaps(metadata)) {
    final label = _knowledgeBaseCitationLabel(hit);
    if (label.isEmpty) continue;
    final key = _knowledgeBaseCitationKey(hit, label);
    if (!seen.add(key)) continue;
    sources.add(_KnowledgeBaseCitationSource(key: key, label: label));
    if (sources.length >= limit) break;
  }
  return sources;
}

bool _knowledgeBaseMetadataWasEnabled(Map<String, Object?>? metadata) {
  return metadata != null &&
      metadata['enabled'] == true &&
      (metadata.containsKey('results') ||
          metadata.containsKey('prompt_append') ||
          metadata.containsKey('embedding'));
}

String _knowledgeBaseMessageCapsuleLabel(
  BuildContext context,
  Map<String, Object?> metadata,
) {
  final results = metadata['results'];
  final hitCount = results is List ? results.length : 0;
  final promptAppend = KnowledgeMessageMetadata.promptAppendInfo(metadata);
  final tokens = promptAppend?['token_estimate'] is num
      ? (promptAppend!['token_estimate'] as num).round()
      : null;
  final status = '${metadata['status'] ?? ''}'.trim();
  if (status == 'failed') {
    return openHandLocalizedText(context, zh: '知识库失败', en: 'KB failed');
  }
  if (hitCount <= 0) {
    return openHandLocalizedText(context, zh: '知识库无命中', en: 'KB no hits');
  }
  if (tokens == null) {
    return openHandLocalizedText(
      context,
      zh: '知识库 $hitCount 条',
      en: 'KB $hitCount hits',
    );
  }
  return openHandLocalizedText(
    context,
    zh: '知识库 · $hitCount 条 · $tokens tokens',
    en: 'KB · $hitCount hits · $tokens tokens',
  );
}

String _knowledgeBaseCitationKey(Map<String, Object?> hit, String label) {
  final sourceId = '${hit['source_id'] ?? ''}'.trim();
  if (sourceId.isNotEmpty) return 'source:$sourceId';
  final path = '${hit['path'] ?? ''}'.trim();
  if (path.isNotEmpty) return 'path:$path';
  return 'label:$label';
}

String _knowledgeBaseCitationLabel(Map<String, Object?> hit) {
  final title = '${hit['source_title'] ?? hit['title'] ?? ''}'.trim();
  if (title.isNotEmpty) return title;
  final path = '${hit['path'] ?? ''}'.trim();
  if (path.isNotEmpty) {
    final normalized = path.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    return slash >= 0 ? normalized.substring(slash + 1) : normalized;
  }
  return '${hit['chunk_id'] ?? ''}'.trim();
}

class _AssistantKnowledgeCitationRail extends StatelessWidget {
  const _AssistantKnowledgeCitationRail({
    required this.metadata,
    required this.textColor,
  });

  final Map<String, Object?> metadata;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final sources = _knowledgeBaseCitationSources(metadata, limit: 6);
    if (sources.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final source in sources)
          _KnowledgeCitationChip(
            source: source,
            onPressed: () {
              unawaited(
                showKnowledgeRetrievalDetailDialog(
                  context,
                  _knowledgeBaseMetadataEnvelope(metadata),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _KnowledgeCitationChip extends StatelessWidget {
  const _KnowledgeCitationChip({required this.source, required this.onPressed});

  final _KnowledgeBaseCitationSource source;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Material(
        color: Colors.transparent,
        borderRadius: kOpenHandPillBorderRadius,
        child: InkWell(
          borderRadius: kOpenHandPillBorderRadius,
          onTap: () {
            _BubbleHtmlInteractiveScope.maybeOf(context)?.markInteractiveTap();
            onPressed();
          },
          child: Ink(
            height: 28,
            padding: const EdgeInsetsDirectional.only(start: 6, end: 10),
            decoration: BoxDecoration(
              borderRadius: kOpenHandPillBorderRadius,
              color: colorScheme.primaryContainer.withValues(alpha: 0.58),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.24),
              ),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.08),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 19,
                  height: 19,
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(alpha: 0.62),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.auto_stories_rounded,
                    size: 12,
                    color: colorScheme.primary,
                  ),
                ),
                kOpenHandHGap6,
                Flexible(
                  child: Text(
                    source.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
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

/// 聚焦消息操作面板第二行的模式、技能、附件、模型和时间胶囊。
class _SelectedMessageContextRow extends StatelessWidget {
  const _SelectedMessageContextRow({
    required this.message,
    required this.harnessAnnotation,
    required this.textColor,
    required this.alignEnd,
    required this.showModelLabel,
    this.associatedKnowledgeBaseMetadata,
    this.onSelectResponseVariant,
  });

  final AiSessionMessage message;
  final _HeAnnotation? harnessAnnotation;
  final Color textColor;
  final bool alignEnd;
  final bool showModelLabel;
  final Map<String, Object?>? associatedKnowledgeBaseMetadata;
  final Future<void> Function(int index)? onSelectResponseVariant;

  /// 消息自带知识库元数据的 used-references 结果缓存（按消息对象）。
  /// 面板可见期间每次 build 重跑全文引用匹配是 O(答案长度 × 词条数) 的
  /// 纯浪费；消息不可变，一次计算终身有效。
  static final Expando<_KnowledgeBaseMetadataCacheEntry>
  _selfUsedMetadataCache = Expando<_KnowledgeBaseMetadataCacheEntry>(
    'selfKnowledgeBaseUsed',
  );

  static Map<String, Object?>? _selfUsedKnowledgeBaseMetadata(
    AiSessionMessage message,
  ) {
    final cached = _selfUsedMetadataCache[message];
    if (cached != null) return cached.value;
    final computed = _knowledgeBaseMetadataUsedByAnswer(
      KnowledgeMessageMetadata.fromMessageMetadata(message.metadata),
      message.content,
    );
    _selfUsedMetadataCache[message] = _KnowledgeBaseMetadataCacheEntry(
      computed,
    );
    return computed;
  }

  @override
  Widget build(BuildContext context) {
    final creationRequest = AiCreationRequest.fromMetadata(
      message.metadata[AiCreationRequest.metadataKey],
    );
    final skillMetadata = message.metadata[aiUserSkillSelectionMetadataKey];
    final knowledgeBaseMetadata = _selfUsedKnowledgeBaseMetadata(message);
    final associatedKnowledgeBaseSourceCount =
        associatedKnowledgeBaseMetadata == null
        ? 0
        : _knowledgeBaseCitationSources(
            associatedKnowledgeBaseMetadata!,
          ).length;
    final responseVariants = message.responseVariants;
    final responseVariantIndex = message.responseVariantIndex;
    final capsules = <Widget>[
      if (responseVariants.length > 1)
        _ResponseVariantSwitcher(
          currentIndex: responseVariantIndex,
          count: responseVariants.length,
          textColor: textColor,
          onSelect: onSelectResponseVariant,
        ),
      ..._MachineExpertRequestContextCapsules.build(
        context,
        message: message,
        textColor: textColor,
      ),
      ..._ReverseExpertRequestContextCapsules.build(
        context,
        message: message,
        textColor: textColor,
      ),
      ..._GoalMessageContextCapsules.build(
        context,
        message: message,
        textColor: textColor,
      ),
      ..._GoalObjectiveContextCapsules.build(
        context,
        message: message,
        textColor: textColor,
      ),
      if (_knowledgeBaseMetadataWasEnabled(knowledgeBaseMetadata))
        _KnowledgeBaseContextCapsule(
          label: _knowledgeBaseMessageCapsuleLabel(
            context,
            knowledgeBaseMetadata!,
          ),
          textColor: textColor,
          onPressed: () {
            unawaited(
              showKnowledgeRetrievalDetailDialog(
                context,
                _knowledgeBaseMetadataEnvelope(knowledgeBaseMetadata),
              ),
            );
          },
        ),
      if (knowledgeBaseMetadata == null &&
          associatedKnowledgeBaseMetadata != null &&
          associatedKnowledgeBaseSourceCount > 0)
        _KnowledgeBaseContextCapsule(
          label: openHandLocalizedText(
            context,
            zh: '引用 $associatedKnowledgeBaseSourceCount 篇知识库',
            en: '$associatedKnowledgeBaseSourceCount KB sources',
          ),
          textColor: textColor,
          onPressed: () {
            unawaited(
              showKnowledgeRetrievalDetailDialog(
                context,
                _knowledgeBaseMetadataEnvelope(
                  associatedKnowledgeBaseMetadata!,
                ),
              ),
            );
          },
        ),
      if (creationRequest.isActive)
        _CreationModeChip(request: creationRequest, textColor: textColor),
      if (_UserSkillSelectionChip.nameFromMetadata(skillMetadata).isNotEmpty)
        _UserSkillSelectionChip(metadata: skillMetadata, textColor: textColor),
      if (harnessAnnotation != null && harnessAnnotation!.hasAnnotations)
        ..._HarnessAnnotationContextCapsules.build(
          context,
          annotation: harnessAnnotation!,
          textColor: textColor,
        ),
      if (showModelLabel &&
          message.modelLabel != null &&
          message.modelLabel!.trim().isNotEmpty)
        _MessageContextCapsule(
          icon: Icons.memory_rounded,
          label: message.modelLabel!.trim(),
          textColor: textColor,
        ),
      _MessageContextCapsule(
        icon: Icons.schedule_rounded,
        label: formatYearMonthDayHmLocal(message.createdAt),
        textColor: textColor,
      ),
    ];
    if (capsules.isEmpty) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: Wrap(spacing: 6, runSpacing: 4, children: capsules),
    );
  }
}

class _HarnessAnnotationContextCapsules {
  const _HarnessAnnotationContextCapsules._();

  static List<Widget> build(
    BuildContext context, {
    required _HeAnnotation annotation,
    required Color textColor,
  }) {
    return <Widget>[
      if (annotation.agentRole != null)
        _MessageContextCapsule(
          icon: Icons.person_pin_rounded,
          label: openHandLocalizedText(
            context,
            zh: '角色 · ${_roleLabel(annotation, isZh: true)}${_agentSuffix(annotation)}',
            en: 'Role · ${_roleLabel(annotation, isZh: false)}${_agentSuffix(annotation)}',
          ),
          textColor: textColor,
        ),
      if (annotation.phase != null)
        _MessageContextCapsule(
          icon: _hePhaseIcons[annotation.phase] ?? Icons.timelapse_rounded,
          label: openHandLocalizedText(
            context,
            zh: '阶段 · ${_phaseLabel(annotation, isZh: true)}',
            en: 'Phase · ${_phaseLabel(annotation, isZh: false)}',
          ),
          textColor: textColor,
        ),
    ];
  }

  static String _roleLabel(_HeAnnotation annotation, {required bool isZh}) {
    final role = annotation.agentRole;
    if (role == null) return '';
    return isZh
        ? (_heRoleDisplayZh[role] ?? role)
        : (_heRoleDisplayEn[role] ?? role);
  }

  static String _phaseLabel(_HeAnnotation annotation, {required bool isZh}) {
    final phase = annotation.phase;
    if (phase == null) return '';
    return isZh
        ? (_hePhaseDisplayZh[phase] ?? phase)
        : (_hePhaseDisplayEn[phase] ?? phase);
  }

  static String _agentSuffix(_HeAnnotation annotation) {
    final agentId = annotation.agentId;
    if (agentId == null || agentId.trim().isEmpty) return '';
    return ' · ${agentId.trim()}';
  }
}

class _GoalMessageContextCapsules {
  const _GoalMessageContextCapsules._();

  static List<Widget> build(
    BuildContext context, {
    required AiSessionMessage message,
    required Color textColor,
  }) {
    final data = _GoalMessageViewData.fromMessage(message);
    if (data == null) {
      return const <Widget>[];
    }
    final label = data.passed == null
        ? data.chipLabel(context)
        : data.passed == true
        ? '${data.chipLabel(context)} · ${openHandLocalizedText(context, zh: '通过', en: 'Passed')}'
        : '${data.chipLabel(context)} · ${openHandContinueLabel(context)}';
    return <Widget>[
      _MessageContextCapsule(
        icon: data.icon,
        label: label,
        textColor: textColor,
      ),
    ];
  }
}

class _GoalObjectiveContextCapsules {
  const _GoalObjectiveContextCapsules._();

  static List<Widget> build(
    BuildContext context, {
    required AiSessionMessage message,
    required Color textColor,
  }) {
    if (message.kind != AiSessionMessageKind.user) {
      return const <Widget>[];
    }
    final metadata = message.metadata;
    if (metadata[aiSessionGoalAutoFollowUpMetadataKey] == true ||
        metadata[aiSessionGoalEvaluationMessageMetadataKey] == true) {
      return const <Widget>[];
    }
    final senderOrigin =
        '${metadata[aiSessionMessageSenderOriginJsonKey] ?? ''}'.trim();
    if (senderOrigin.isNotEmpty &&
        senderOrigin != aiSessionMessageSenderOriginExplicitUser) {
      return const <Widget>[];
    }
    final goalId = _readString(metadata[aiSessionGoalIdMetadataKey]);
    final goalObjective = metadata[aiSessionGoalObjectiveMetadataKey];
    final hasGoalObjective =
        goalObjective == true || _readString(goalObjective).isNotEmpty;
    if (goalId.isEmpty || !hasGoalObjective) {
      return const <Widget>[];
    }
    return <Widget>[
      _MessageContextCapsule(
        icon: Icons.flag_rounded,
        label: '${_homeMessageBubGoalLabel(context)} · ${_shortGoalId(goalId)}',
        textColor: textColor,
        maxLabelWidth: 180,
      ),
    ];
  }

  static String _shortGoalId(String goalId) {
    return goalId.length <= 8 ? goalId : goalId.substring(0, 8);
  }

  static String _readString(Object? value) {
    return value is String ? value.trim() : '';
  }
}

class _MachineExpertRequestContextCapsules {
  const _MachineExpertRequestContextCapsules._();

  static List<Widget> build(
    BuildContext context, {
    required AiSessionMessage message,
    required Color textColor,
  }) {
    final data = _machineExpertRequestCardFor(message);
    if (data == null) {
      return const <Widget>[];
    }
    return <Widget>[
      _MessageContextCapsule(
        icon: Icons.terminal_rounded,
        label: openHandLocalizedText(
          context,
          zh: '机器专家请求',
          en: 'Machine Expert Request',
        ),
        textColor: textColor,
      ),
      if ((data.appleScriptTarget ?? '').trim().isNotEmpty)
        _MessageContextCapsule(
          icon: Icons.my_location_rounded,
          label: _homeMessageBubPreciseTargetLabel(context),
          textColor: textColor,
        ),
    ];
  }
}

class _ReverseExpertRequestContextCapsules {
  const _ReverseExpertRequestContextCapsules._();

  static List<Widget> build(
    BuildContext context, {
    required AiSessionMessage message,
    required Color textColor,
  }) {
    final webData = _webReverseRequestCardFor(message);
    if (webData != null) {
      return <Widget>[
        _MessageContextCapsule(
          icon: Icons.travel_explore_rounded,
          label: _homeMessageBubWebReverseRequestLabel(context),
          textColor: textColor,
        ),
        if (webData.cdpPort.trim().isNotEmpty)
          _MessageContextCapsule(
            icon: Icons.settings_ethernet_rounded,
            label: 'CDP ${webData.cdpPort.trim()}',
            textColor: textColor,
          ),
      ];
    }
    final androidData = _androidReverseRequestCardFor(message);
    if (androidData == null) {
      return const <Widget>[];
    }
    return <Widget>[
      _MessageContextCapsule(
        icon: Icons.android_rounded,
        label: _homeMessageBubAndroidReverseRequestLabel(context),
        textColor: textColor,
      ),
      if ((androidData.packageName ?? '').trim().isNotEmpty)
        _MessageContextCapsule(
          icon: Icons.apps_rounded,
          label: androidData.packageName!.trim(),
          textColor: textColor,
        ),
    ];
  }
}

class _ResponseVariantSwitcher extends StatefulWidget {
  const _ResponseVariantSwitcher({
    required this.currentIndex,
    required this.count,
    required this.textColor,
    required this.onSelect,
  });

  final int currentIndex;
  final int count;
  final Color textColor;
  final Future<void> Function(int index)? onSelect;

  @override
  State<_ResponseVariantSwitcher> createState() =>
      _ResponseVariantSwitcherState();
}

class _ResponseVariantSwitcherState extends State<_ResponseVariantSwitcher> {
  bool _selecting = false;

  Future<void> _select(int index) async {
    if (_selecting || widget.onSelect == null) return;
    if (index < 0 || index >= widget.count) return;
    setState(() => _selecting = true);
    try {
      await widget.onSelect!(index);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'openhand_home_page',
          context: ErrorDescription('while selecting a response variant'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _selecting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = openHandMessageActionChipStyle(context);
    const states = <WidgetState>{};
    final side =
        style.side?.resolve(states) ??
        BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.70));
    final foreground =
        style.foregroundColor?.resolve(states) ?? widget.textColor;
    final previousEnabled =
        !_selecting && widget.onSelect != null && widget.currentIndex > 0;
    final nextEnabled =
        !_selecting &&
        widget.onSelect != null &&
        widget.currentIndex < widget.count - 1;
    final label = '${widget.currentIndex + 1}/${widget.count}';
    return Material(
      color: Colors.transparent,
      shape: StadiumBorder(side: side),
      clipBehavior: Clip.antiAlias,
      textStyle: theme.textTheme.labelMedium?.copyWith(
        color: foreground,
        fontWeight: FontWeight.w800,
      ),
      child: SizedBox(
        height: _responseVariantChipHeight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ResponseVariantArrowButton(
              icon: Icons.chevron_left_rounded,
              enabled: previousEnabled,
              color: foreground,
              onTap: () => unawaited(_select(widget.currentIndex - 1)),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: _responseVariantLabelMinWidth,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: AnimatedSwitcher(
                  duration: cardMotionDurationFor(context, expanding: true),
                  switchInCurve: kCardMotionCurve,
                  switchOutCurve: kOpenHandSwitchOutCurve,
                  transitionBuilder: (child, animation) {
                    final curved = openHandBoundedCurveAnimation(
                      parent: animation,
                      curve: kCardMotionCurve,
                      reverseCurve: kOpenHandSwitchOutCurve,
                    );
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(
                          begin: 0.92,
                          end: 1,
                        ).animate(curved),
                        child: child,
                      ),
                    );
                  },
                  child: Text(
                    label,
                    key: ValueKey<String>(label),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
            _ResponseVariantArrowButton(
              icon: Icons.chevron_right_rounded,
              enabled: nextEnabled,
              color: foreground,
              onTap: () => unawaited(_select(widget.currentIndex + 1)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResponseVariantArrowButton extends StatelessWidget {
  const _ResponseVariantArrowButton({
    required this.icon,
    required this.enabled,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color.withValues(alpha: enabled ? 0.92 : 0.28);
    return InkWell(
      borderRadius: BorderRadius.circular(_responseVariantChipHeight / 2),
      onTap: enabled
          ? () {
              _BubbleHtmlInteractiveScope.maybeOf(
                context,
              )?.markInteractiveTap();
              onTap();
            }
          : null,
      child: SizedBox(
        width: _responseVariantArrowWidth,
        height: _responseVariantChipHeight,
        child: Icon(
          icon,
          size: kOpenHandMessageActionIconSize,
          color: effectiveColor,
        ),
      ),
    );
  }
}

class _MessageContextCapsule extends StatelessWidget {
  const _MessageContextCapsule({
    required this.icon,
    required this.label,
    required this.textColor,
    this.leading,
    this.maxLabelWidth,
    this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color textColor;
  final Widget? leading;
  final double? maxLabelWidth;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final style = openHandMessageActionChipStyle(context);
    final iconColor = style.iconColor?.resolve(const <WidgetState>{});
    final labelWidget = maxLabelWidth == null
        ? Text(label, maxLines: 1, softWrap: false, overflow: TextOverflow.fade)
        : ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxLabelWidth!),
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
          );
    final button = OutlinedButton.icon(
      onPressed: () {
        _BubbleHtmlInteractiveScope.maybeOf(context)?.markInteractiveTap();
        onPressed?.call();
      },
      style: style,
      icon:
          leading ??
          Icon(icon, size: kOpenHandMessageActionIconSize, color: iconColor),
      label: labelWidget,
    );
    if (onPressed != null) {
      return button;
    }
    return IgnorePointer(child: button);
  }
}

class _UserMessageAttachmentRail extends StatelessWidget {
  const _UserMessageAttachmentRail({required this.attachments});

  final List<AiMessageAttachment> attachments;

  @override
  Widget build(BuildContext context) {
    return _ResponsiveMessageWidth(
      kind: _MessageBubbleWidthKind.user,
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(bottom: _userAttachmentBottomSpacing),
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: _userAttachmentGap,
          runSpacing: _userAttachmentGap,
          children: [
            for (final attachment in attachments)
              _UserMessageAttachmentTile(attachment: attachment),
          ],
        ),
      ),
    );
  }
}

class _UserMessageAttachmentTile extends StatelessWidget {
  const _UserMessageAttachmentTile({required this.attachment});

  final AiMessageAttachment attachment;

  void _open(BuildContext context) {
    _BubbleHtmlInteractiveScope.maybeOf(context)?.markInteractiveTap();
    unawaited(_openAttachment(context, attachment));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final rawName = attachment.name.trim();
    final name = rawName.isEmpty
        ? openHandLocalizedText(context, zh: '附件', en: 'Attachment')
        : rawName;
    final tooltip = '$name · ${formatByteSize(attachment.sizeBytes)}';
    final borderRadius = BorderRadius.circular(attachment.isImage ? 16 : 999);

    final child = attachment.isImage
        ? SizedBox.square(
            dimension: _userAttachmentThumbnailExtent,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: colorScheme.surfaceContainerHighest,
                  child: Center(
                    child: Icon(
                      Icons.image_outlined,
                      size: 30,
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.72,
                      ),
                    ),
                  ),
                ),
                Image.file(
                  File(attachment.storagePath),
                  cacheWidth: 320,
                  cacheHeight: 320,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  excludeFromSemantics: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _open(context),
                    splashColor: colorScheme.primary.withValues(alpha: 0.12),
                    highlightColor: colorScheme.primary.withValues(alpha: 0.08),
                  ),
                ),
              ],
            ),
          )
        : ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: _userAttachmentPillMaxWidth,
              minHeight: 38,
            ),
            child: Material(
              color: colorScheme.surfaceContainerHighest,
              child: InkWell(
                onTap: () => _open(context),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: colorScheme.onSurface.withValues(alpha: 0.08),
                          borderRadius: kOpenHandBorderRadius8,
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          _iconForAttachmentKind(attachment.kind),
                          size: 16,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      kOpenHandHGap8,
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );

    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Semantics(
          button: true,
          label: name,
          child: MicroPressFeedback(
            scale: 0.96,
            child: Material(
              color: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: borderRadius,
                side: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.72),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _KnowledgeBaseContextCapsule extends StatelessWidget {
  const _KnowledgeBaseContextCapsule({
    required this.label,
    required this.textColor,
    required this.onPressed,
  });

  final String label;
  final Color textColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _MessageContextCapsule(
      icon: Icons.auto_stories_rounded,
      label: label,
      textColor: textColor,
      maxLabelWidth: 280,
      onPressed: onPressed,
    );
  }
}

class _CreationModeChip extends StatelessWidget {
  const _CreationModeChip({required this.request, required this.textColor});

  final AiCreationRequest request;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    if (!request.isActive) return const SizedBox.shrink();
    final (icon, labelZh, labelEn) = switch (request.mode) {
      AiCreationMode.image => (
        Icons.image_outlined,
        '图片生成',
        'Image generation',
      ),
      AiCreationMode.video => (
        Icons.videocam_outlined,
        '视频生成',
        'Video generation',
      ),
      AiCreationMode.audio => (
        Icons.audiotrack_outlined,
        '音频生成',
        'Audio generation',
      ),
      AiCreationMode.deepResearch => (
        Icons.travel_explore_rounded,
        '深度研究',
        'Deep Research',
      ),
      AiCreationMode.none => (Icons.circle_outlined, '', ''),
    };
    final options = request.options;
    final detailParts = <String>[
      if (options.aspectRatio != null) options.aspectRatio!,
      if (options.size != null && options.aspectRatio == null) options.size!,
      if (options.durationSeconds != null) '${options.durationSeconds}s',
      if (options.resolution != null) options.resolution!,
      if (options.frameRate != null) '${options.frameRate}fps',
      if (options.numFrames != null) '${options.numFrames}f',
      if (options.quality != null) options.quality!,
      if (options.style != null) options.style!,
      if (options.outputFormat != null) options.outputFormat!,
      if (options.background != null) options.background!,
      if (options.mode != null) options.mode!,
      if (options.voice != null) options.voice!,
      if (options.omitVoice)
        openHandLocalizedText(context, zh: '不指定音色', en: 'No voice'),
      if (options.speed != null) '${options.speed}x',
      if (options.sampleRate != null) '${options.sampleRate}Hz',
      if (options.bitrate != null) '${options.bitrate! ~/ 1000}kbps',
      if (options.seed != null) 'seed ${options.seed}',
      if (options.promptEnhance != null)
        options.promptEnhance! ? 'prompt+' : 'prompt-',
      if (options.watermark != null) options.watermark! ? 'watermark' : 'no wm',
      if (options.negativePrompt != null) 'negative',
      if (options.count != 1) 'x${options.count}',
    ];
    final label = openHandLocalizedText(
      context,
      zh: '模式 · $labelZh',
      en: 'Mode · $labelEn',
    );
    final detail = detailParts.isEmpty ? '' : ' · ${detailParts.join(' · ')}';
    return _MessageContextCapsule(
      icon: icon,
      label: '$label$detail',
      textColor: textColor,
    );
  }
}

/// 消息显式选择本地技能时展示的上下文胶囊。
class _UserSkillSelectionChip extends StatelessWidget {
  const _UserSkillSelectionChip({
    required this.metadata,
    required this.textColor,
  });

  final Object? metadata;
  final Color textColor;

  static String nameFromMetadata(Object? metadata) {
    final map = stringKeyedMapFromValue(metadata);
    return _nameFromMap(map);
  }

  static String _nameFromMap(Map<String, Object?> map) {
    return (map['name'] as String?)?.trim() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final map = stringKeyedMapFromValue(metadata);
    if (map.isEmpty) return const SizedBox.shrink();
    final name = _nameFromMap(map);
    if (name.isEmpty) return const SizedBox.shrink();
    final emoji = (map['emoji'] as String?)?.trim();
    final iconPath = (map['icon_path'] as String?)?.trim();
    final iconKind = (map['icon_kind'] as String?)?.trim();
    final leading = _buildLeading(emoji, iconPath, iconKind);
    final label = openHandLocalizedText(
      context,
      zh: '技能 · $name',
      en: 'Skill · $name',
    );
    return _MessageContextCapsule(
      icon: Icons.extension_rounded,
      label: label,
      textColor: textColor,
      leading: leading,
    );
  }

  Widget? _buildLeading(String? emoji, String? iconPath, String? iconKind) {
    if (emoji != null && emoji.isNotEmpty) {
      return Text(emoji, style: const TextStyle(fontSize: 12, height: 1.0));
    }
    if (iconPath != null && iconPath.isNotEmpty && iconKind == 'raster') {
      return SizedBox(
        width: 14,
        height: 14,
        child: Image.file(
          File(iconPath),
          width: 14,
          height: 14,
          // 按约三倍像素比缓存 14 逻辑像素的图标。
          cacheWidth: 42,
          cacheHeight: 42,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      );
    }
    return null;
  }
}

/// 沉浸式视频页面；关闭时返回当前播放秒数以同步预览进度。
class _FullscreenVideoPage extends StatefulWidget {
  const _FullscreenVideoPage({
    required this.source,
    required this.title,
    required this.motionSettings,
    this.initialTime = 0,
  });

  final _GeneratedMediaSource source;
  final String title;
  final DialogAnimationSettings motionSettings;
  final double initialTime;

  @override
  State<_FullscreenVideoPage> createState() => _FullscreenVideoPageState();
}

class _FullscreenVideoPageState extends State<_FullscreenVideoPage> {
  late final WebViewController _controller;
  String? _tempHtmlPath;
  bool _ready = false;
  String? _loadError;
  double _currentTime = 0;
  bool _exiting = false;
  // 主动持有键盘焦点，使 Esc 无需点击 WebView 即可退出全屏。
  final FocusNode _focusNode = FocusNode(debugLabel: 'fullscreen-video');

  @override
  void initState() {
    super.initState();
    _currentTime = widget.initialTime;
    _controller = WebViewController();
    unawaited(_bootstrap());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _onJsMessage(JavaScriptMessage message) {
    final value = message.message.trim();
    if (value == 'close') {
      _exit();
    } else if (value.startsWith('time:')) {
      final parsed = optionalNonNegativeDoubleFromValue(value.substring(5));
      if (parsed != null) {
        _currentTime = parsed;
      }
    } else if (value.startsWith('error')) {
      if (!mounted) return;
      setState(
        () => _loadError = value.length > 6 ? value.substring(6) : value,
      );
    }
  }

  Future<void> _bootstrap() async {
    try {
      await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await _controller.addJavaScriptChannel(
        'OpenHandFs',
        onMessageReceived: _onJsMessage,
      );
      await _controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() => _ready = true);
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            setState(() => _loadError = error.description);
          },
        ),
      );
      if (openHandCanSetWebViewBackgroundColor(defaultTargetPlatform)) {
        await _controller.setBackgroundColor(Colors.black);
      }
      if (!mounted) return;

      final localPath = widget.source.filePath;
      if (localPath != null && await isRegularFilePath(localPath)) {
        String? tempPath;
        try {
          final tempFile = await _writeMediaPreviewTempPage(
            mediaPath: localPath,
            fileNamePrefix: _fullscreenVideoTempFilePrefix,
            html: _buildHtml(localOverride: localPath),
            action: '全屏视频',
          );
          tempPath = tempFile.path;
          if (!mounted) {
            await _deleteMediaPreviewTempFile(tempFile.path, '全屏视频：清理未挂载的临时页面');
            return;
          }
          _tempHtmlPath = tempFile.path;
          await _controller.loadFile(tempFile.path);
          return;
        } catch (error, stack) {
          final failedPath = tempPath;
          if (failedPath != null) {
            if (_tempHtmlPath == failedPath) _tempHtmlPath = null;
            await _deleteMediaPreviewTempFile(failedPath, '全屏视频：清理加载失败的临时页面');
          }
          silentLog(
            'home_message_bubble',
            '全屏视频：本地文件加载失败，回退内嵌页面',
            error,
            stack,
          );
        }
      }
      if (!mounted) return;
      await _controller.loadHtmlString(_buildHtml());
    } catch (error, stack) {
      silentLog('home_message_bubble', '初始化全屏视频', error, stack);
      if (!mounted) return;
      setState(() {
        _loadError = openHandLocalizedText(
          context,
          zh: '全屏视频初始化失败，请返回后重试。',
          en: 'Failed to initialize fullscreen video. Go back and try again.',
        );
      });
    }
  }

  String _buildHtml({String? localOverride}) {
    final raw = localOverride != null
        ? Uri.file(localOverride).toString()
        : widget.source.uri.toString();
    final src = const HtmlEscape(HtmlEscapeMode.attribute).convert(raw);
    final mime = const HtmlEscape(
      HtmlEscapeMode.attribute,
    ).convert(_mimeTypeForGeneratedMedia(widget.source));
    final initial = widget.initialTime > 0
        ? widget.initialTime.toStringAsFixed(3)
        : '0';
    final durationMs = widget.motionSettings.duration.inMilliseconds;
    final motionCurve = openHandDialogAnimationCurveCss(
      widget.motionSettings.curve,
    );
    final motionClass = durationMs == 0 ? ' no-motion' : '';
    return '''
<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1.0"><style>
:root{--oh-motion-duration:${durationMs}ms;--oh-motion-curve:$motionCurve;--oh-control-bg:rgba(18,18,20,.76);--oh-control-border:rgba(255,255,255,.14);--oh-control-text:#fff;--oh-track:rgba(255,255,255,.22);--oh-track-fill:#fff}
html,body{margin:0;background:#000;width:100%;height:100%;overflow:hidden;color:#fff;font:13px/1.4 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
button,input{font:inherit}
.media-shell{position:relative;width:100%;height:100%;display:flex;align-items:center;justify-content:center;background:#000;user-select:none;overflow:hidden;isolation:isolate}
${openHandVideoPlayerControlsCss(compactBreakpointPx: 460, compactHorizontalInsetPx: 18, fullscreen: true)}
</style></head><body>
<div id="shell" class="media-shell controls-visible$motionClass" tabindex="0">
  <video id="media" autoplay playsinline preload="auto" disableRemotePlayback><source src="$src" type="$mime"></video>
${openHandVideoPlayerControlsHtml(trailingActionId: 'exit', trailingActionLabel: 'Exit fullscreen')}
</div>
<script>(function(){
const AUTO_HIDE_MS=$_kMediaPreviewControlAutoHideMs;
const POINTER_LEAVE_HIDE_MS=$_kMediaPreviewPointerLeaveHideMs;
$openHandVideoPlayerElementBindingsJavaScript
const exit=document.getElementById('exit');
window.media=media;
function post(m){try{if(window.OpenHandFs&&window.OpenHandFs.postMessage){window.OpenHandFs.postMessage(String(m));}}catch(_){}}
if(!media){post('error:missing_video');return;}
let hideTimer=0;
let dragging=false;
let volumeActive=false;
let pointerInsideShell=true;
let looping=false;
${openHandVideoPlayerIconsJavaScript(exitFullscreen: true)}
rewind.innerHTML=icon.rewind;
forward.innerHTML=icon.forward;
exit.innerHTML=icon.exit;
$openHandVideoPlayerScriptUtilities
$openHandVideoPlayerVisibilityJavaScript
$openHandVideoPlayerPointerLeaveHideJavaScript
$openHandVideoPlayerStateSyncJavaScript
let resumed=false;
function resume(){if(resumed)return;resumed=true;try{var t=parseFloat('$initial');if(!isNaN(t)&&t>0&&t<(media.duration||Infinity)){media.currentTime=t;}}catch(_){}updateTime();var p=media.play();if(p&&p.catch)p.catch(function(){updatePlayState();});}
media.addEventListener('loadedmetadata',resume);
media.addEventListener('canplay',resume);
media.addEventListener('error',function(){post('error:video_load');});
var lastSent=-1;
function sendTime(){var t=media.currentTime||0;if(Math.abs(t-lastSent)>=0.2){lastSent=t;post('time:'+t.toFixed(3));}}
play.addEventListener('click',()=>{if(media.paused){media.play().catch(()=>showControls(true));}else{media.pause();}showControls(true);});
rewind.addEventListener('click',()=>seekBy(-15));
forward.addEventListener('click',()=>seekBy(15));
progress.addEventListener('pointerdown',beginProgressDrag);
progress.addEventListener('pointerup',endProgressDrag);
progress.addEventListener('pointercancel',endProgressDrag);
progress.addEventListener('input',()=>{const dur=Number.isFinite(media.duration)?media.duration:0;if(dur>0)media.currentTime=(Number(progress.value)/1000)*dur;updateTime();showControls(true);});
volumeGroup.addEventListener('pointerenter',()=>setVolumeActive(true));
volumeGroup.addEventListener('pointerleave',()=>setVolumeActive(false));
volumeGroup.addEventListener('pointerdown',()=>setVolumeActive(true));
volumeGroup.addEventListener('pointerup',()=>setVolumeActive(false));
volumeGroup.addEventListener('pointercancel',()=>setVolumeActive(false));
volumeGroup.addEventListener('focusin',()=>setVolumeActive(true));
volumeGroup.addEventListener('focusout',(event)=>{if(!event.relatedTarget||!volumeGroup.contains(event.relatedTarget)){setVolumeActive(false);}});
volume.addEventListener('input',()=>{const next=Math.max(0,Math.min(1,Number(volume.value)));media.volume=Number.isFinite(next)?next:1;media.muted=media.volume<=0;updateVolume();setVolumeActive(true);});
mute.addEventListener('click',()=>{media.muted=!media.muted;if(!media.muted&&media.volume<=0)media.volume=0.6;updateVolume();setVolumeActive(true);});
playMode.addEventListener('click',()=>{looping=!looping;updatePlayMode();showControls(true);});
exit.addEventListener('click',()=>post('close'));
shell.addEventListener('pointerenter',()=>{pointerInsideShell=true;});
shell.addEventListener('pointermove',()=>{pointerInsideShell=true;showControls(false);});
shell.addEventListener('pointerdown',()=>showControls(false));
shell.addEventListener('pointerleave',()=>{pointerInsideShell=false;hideControlsAfterPointerLeave();});
shell.addEventListener('keydown',(event)=>{if(event.defaultPrevented)return;if(event.key===' '||event.key==='Enter'){event.preventDefault();play.click();}else if(event.key==='ArrowLeft'){event.preventDefault();seekBy(-5);}else if(event.key==='ArrowRight'){event.preventDefault();seekBy(5);}else if(event.key.toLowerCase()==='m'){event.preventDefault();mute.click();}});
document.addEventListener('keydown',(event)=>{if(event.defaultPrevented||event.key!=='Escape')return;event.preventDefault();post('close');},true);
media.addEventListener('timeupdate',sendTime);
media.addEventListener('timeupdate',updateTime);
media.addEventListener('pause',sendTime);
media.addEventListener('pause',updatePlayState);
media.addEventListener('play',updatePlayState);
media.addEventListener('seeked',sendTime);
media.addEventListener('seeked',updateTime);
media.addEventListener('ended',()=>{sendTime();updatePlayState();showControls(true);});
media.addEventListener('volumechange',updateVolume);
window.addEventListener('beforeunload',clearHideTimer);
updatePlayMode();
updatePlayState();
updateTime();
updateVolume();
})();</script>
</body></html>
''';
  }

  void _exit() {
    if (!mounted) return;
    if (_exiting) return;
    _exiting = true;
    // 路由退出前先停止播放，避免残留音频。
    unawaited(_stopPlaybackBestEffort());
    Navigator.of(context).maybePop<double>(_currentTime);
  }

  Future<void> _togglePlayPause() async {
    try {
      await _controller.runJavaScript(
        "try{var m=document.getElementById('media');if(m){if(m.paused){var p=m.play();if(p&&p.catch)p.catch(function(){});}else{m.pause();}}}catch(_){}",
      );
    } catch (error, stack) {
      silentLog('home_message_bubble', '全屏视频：切换播放状态失败', error, stack);
    }
  }

  Future<void> _stopPlaybackBestEffort() async {
    try {
      // 暂停并清空媒体源，强制 WKWebView 释放解码器。
      await _controller.runJavaScript(openHandVideoPlayerReleaseJavaScript);
    } catch (error, stack) {
      silentLog('home_message_bubble', '全屏视频：停止播放失败', error, stack);
    }
  }

  @override
  void dispose() {
    // 兜底释放系统手势等非标准退出路径遗留的媒体资源。
    unawaited(_stopPlaybackBestEffort());
    _focusNode.dispose();
    final tmp = _tempHtmlPath;
    if (tmp != null) {
      unawaited(_deleteMediaPreviewTempFile(tmp, '全屏视频：清理临时页面'));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        SingleActivator(LogicalKeyboardKey.space): _MediaPlayPauseIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              _exit();
              return null;
            },
          ),
          _MediaPlayPauseIntent: CallbackAction<_MediaPlayPauseIntent>(
            onInvoke: (_) {
              _togglePlayPause();
              return null;
            },
          ),
        },
        child: Focus(
          focusNode: _focusNode,
          autofocus: true,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: SafeArea(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: WebViewWidget(controller: _controller),
                  ),
                  if (!_ready && _loadError == null)
                    const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2.6,
                        color: Colors.white70,
                      ),
                    ),
                  if (_loadError != null)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _loadError!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: _FullscreenChromeButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: openHandLocalizedText(
                        context,
                        zh: '返回（Esc）',
                        en: 'Back (Esc)',
                      ),
                      onPressed: _exit,
                    ),
                  ),
                  if (widget.title.isNotEmpty)
                    Positioned(
                      top: 18,
                      left: 64,
                      right: 64,
                      child: IgnorePointer(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            shadows: [
                              Shadow(
                                color: Colors.black54,
                                blurRadius: 8,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FullscreenChromeButton extends StatefulWidget {
  const _FullscreenChromeButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  State<_FullscreenChromeButton> createState() =>
      _FullscreenChromeButtonState();
}

class _FullscreenChromeButtonState extends State<_FullscreenChromeButton>
    with OpenHandHoverState {
  @override
  Widget build(BuildContext context) {
    final bg = openHandHovered
        ? Colors.white.withValues(alpha: 0.22)
        : Colors.white.withValues(alpha: 0.12);
    return Tooltip(
      message: widget.tooltip,
      waitDuration: kOpenHandTooltipWait,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setOpenHandHovered(true),
        onExit: (_) => setOpenHandHovered(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: kOpenHandBorderRadius12,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.28),
                width: 0.8,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black38,
                  blurRadius: 12,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Icon(widget.icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}

/// 空格键切换媒体播放状态。
class _MediaPlayPauseIntent extends Intent {
  const _MediaPlayPauseIntent();
}

/// 流式助手消息尾部的「打字机」光标。
///
/// 配合 [_StreamCharThrottle] 的 60fps 节流，给低速率字符
/// 流式输出场景一个明确的"AI 仍在打字"视觉信号；停流时该 widget 直接
/// 不再插入，光标随之消失。脉动节奏 1Hz、振幅 0.3↔1.0，整体克制，
/// 不会喧宾夺主。
class _TypewriterCaret extends StatefulWidget {
  const _TypewriterCaret({required this.color});

  final Color color;

  @override
  State<_TypewriterCaret> createState() => _TypewriterCaretState();
}

class _TypewriterCaretState extends State<_TypewriterCaret>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: kOpenHandMotion950,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!openHandTickerMotionEnabled(context)) {
      _ctrl.stop();
      return _buildBlock(1);
    }
    if (!_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    }
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        // 0.3..1 区间脉冲，节奏温和不喧宾夺主。
        final t = Curves.easeInOutSine.transform(_ctrl.value);
        return _buildBlock(0.3 + 0.7 * t);
      },
    );
  }

  Widget _buildBlock(double opacity) {
    return Container(
      width: 8,
      height: 16,
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(kOpenHandRadius2),
      ),
    );
  }
}

String _homeMessageBubAcceptanceLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '验收标准', en: 'Acceptance');
}

String _homeMessageBubAndroidReverseRequestLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: 'Android 逆向请求',
    en: 'Android Reverse Request',
  );
}

String _homeMessageBubCopyMediaLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '复制媒体', en: 'Copy Media');
}

String _homeMessageBubEvidenceRulesLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '取证纪律', en: 'Evidence Rules');
}

String _homeMessageBubGoalLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '目标', en: 'Goal');
}

String _homeMessageBubOpenWithSystemAppLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '使用系统应用打开',
    en: 'Open with System App',
  );
}

String _homeMessageBubOpenWithSystemPlayerLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '使用系统播放器打开',
    en: 'Open with System Player',
  );
}

String _homeMessageBubPreciseTargetLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '精确定位', en: 'Precise Target');
}

String _homeMessageBubSaveToDiskLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '保存到本地', en: 'Save to disk');
}

String _homeMessageBubWebReverseRequestLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: 'Web 逆向请求',
    en: 'Web Reverse Request',
  );
}
