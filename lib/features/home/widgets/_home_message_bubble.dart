part of '../openhand_home_page.dart';

class _MessageBubble extends StatefulWidget {
  const _MessageBubble({
    super.key,
    required this.message,
    required this.sessionTitle,
    required this.sessionEnvironment,
    required this.showReasoningSweep,
    required this.trackLayoutChanges,
    required this.onLayoutChanged,
    required this.transcriptScrollActive,
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
  final String sessionTitle;
  final AiSessionEnvironment sessionEnvironment;
  final bool showReasoningSweep;
  final bool trackLayoutChanges;
  final VoidCallback onLayoutChanged;
  final bool transcriptScrollActive;
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

class _MessageBubbleState extends State<_MessageBubble> {
  static const int _messageExpansionStateCacheLimit = 500;
  static const double _messageBubbleMaxWidth = 760;
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

  // Cached expensive objects to avoid re-allocation on every build.
  List<md.InlineSyntax>? _cachedInlineSyntaxes;
  Map<String, MarkdownElementBuilder>? _cachedBuilders;
  _MessageMarkdownThemeData? _cachedMarkdownThemeData;
  String? _cachedFilePathParseKey;
  List<String>? _cachedFilePathRoots;
  String? _lastCacheMessageId;
  String? _lastCacheEnvironmentKey;
  int? _lastCacheThemeBrightness;
  bool? _lastCacheDarkCodeSurface;

  @override
  void initState() {
    super.initState();
    _loadExpansionOverridesForMessage(widget.message.id);
  }

  @override
  void didUpdateWidget(covariant _MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id) {
      _compressionExpanded = false;
      _loadExpansionOverridesForMessage(widget.message.id);
      _showRawContent = widget.initiallyShowRawContent;
      _responseVariantSizeMotionResetTimer?.cancel();
      _responseVariantSizeMotionResetTimer = null;
      _responseVariantSizeMotionActive = false;
      _invalidateCache();
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

  void _loadExpansionOverridesForMessage(String messageId) {
    _reasoningExpandedOverride =
        _reasoningExpansionOverridesByMessageId[messageId];
    _assistantResponseExpandedOverride =
        _assistantExpansionOverridesByMessageId[messageId];
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
    _rememberExpansionOverride(
      _reasoningExpansionOverridesByMessageId,
      widget.message.id,
      value,
    );
    setState(() {
      _reasoningExpandedOverride = value;
    });
  }

  void _setAssistantResponseExpandedOverride(bool value) {
    _rememberExpansionOverride(
      _assistantExpansionOverridesByMessageId,
      widget.message.id,
      value,
    );
    setState(() {
      _assistantResponseExpandedOverride = value;
    });
  }

  void _invalidateCache() {
    _cachedInlineSyntaxes = null;
    _cachedBuilders = null;
    _cachedMarkdownThemeData = null;
    _cachedFilePathParseKey = null;
    _cachedFilePathRoots = null;
    _lastCacheMessageId = null;
    _lastCacheEnvironmentKey = null;
    _lastCacheThemeBrightness = null;
    _lastCacheDarkCodeSurface = null;
  }

  AiMessageContentFormat _resolveMessageContentFormat(
    BuildContext context,
    AiSessionMessage message,
  ) {
    final storedKey = message.metadata[aiSessionMessageContentFormatKey];
    if (storedKey is String && storedKey.isNotEmpty) {
      return AiMessageContentFormat.fromStorageKey(storedKey);
    }
    return context.read<SettingsController>().aiMessageContentFormat;
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _messageBubbleMaxWidth),
            child: _RoundFileMutationSummaryCard(message: message),
          ),
        ),
      );
    }
    final attachments = AiMessageAttachment.listFromMetadata(
      message.metadata[aiSessionMessageAttachmentsMetadataKey],
    );
    // Resolve content format per message — messages store their own format
    // in metadata when created; fall back to global setting for legacy data.
    final resolvedMessageContentFormat = _resolveMessageContentFormat(
      context,
      message,
    );
    final reasoningExpanded =
        _reasoningExpandedOverride ?? _shouldDefaultExpandReasoning(message);

    final alignment = isCompressionPoint
        ? Alignment.center
        : isUser
        ? Alignment.centerRight
        : Alignment.centerLeft;
    final borderRadius = BorderRadius.circular(18);
    final backgroundColor = isCompressionPoint
        ? colorScheme.tertiaryContainer
        : isUser
        ? colorScheme.primaryContainer
        : isReasoning
        ? const Color(0xFF18181B)
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
    final environmentKey =
        '${widget.sessionEnvironment.applicationDirectory}|${_toolExecutionWorkingDirectory(message)}';
    final themeBrightness = theme.brightness.index;
    final needsCacheRefresh =
        _lastCacheMessageId != message.id ||
        _lastCacheEnvironmentKey != environmentKey ||
        _lastCacheThemeBrightness != themeBrightness ||
        _lastCacheDarkCodeSurface != useDarkCodeSurface;
    if (needsCacheRefresh) {
      _lastCacheMessageId = message.id;
      _lastCacheEnvironmentKey = environmentKey;
      _lastCacheThemeBrightness = themeBrightness;
      _lastCacheDarkCodeSurface = useDarkCodeSurface;
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
        'pre': _HighlightedCodeBlockBuilder(
          theme: theme,
          baseColor: textColor,
          darkSurface: useDarkCodeSurface,
          // 始终允许文本选择/复制，便于用户随时复制响应内容。
          // “选中模式”依然控制 action buttons 的可见性，
          // 但选择/复制不再需要预先点击进入选中态。
          selectable: true,
        ),
        'openhand-file-resolved': _FilePathMarkdownBuilder(
          textColor: textColor,
          onOpenPath: _openResolvedMessagePath,
        ),
        'openhand-file-pending': _FilePathMarkdownBuilder(
          textColor: textColor,
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

    // Parse Harness Engineering agent/phase annotations from message content.
    // Only assistant-role messages can carry these markers.
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
    final isAiSideMessage =
        message.isAiSideConversationMessage && !isGoalEvaluationMessage;
    final selectedFeedback = message.feedback;
    final canCollapseAssistantResponse =
        isAssistantResponse &&
        !isStreamingAssistant &&
        !_showRawContent &&
        resolvedMessageContentFormat != AiMessageContentFormat.html &&
        _messageShouldCollapse(
          effectiveContent,
          charThreshold: _messageMarkdownCollapseCharThreshold,
          lineThreshold: _messageMarkdownCollapseLineThreshold,
        );
    final assistantResponseExpanded =
        canCollapseAssistantResponse &&
        (_assistantResponseExpandedOverride ?? false);
    final assistantResponseCollapsed =
        canCollapseAssistantResponse && !assistantResponseExpanded;
    final showAssistantResponseMetaRow =
        isAssistantResponse &&
        (isStreamingAssistant || canCollapseAssistantResponse);
    final bodyContentSignature =
        '${effectiveContent.length}:${effectiveContent.hashCode}';
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
        '${message.id}|compression|content:${message.content.length}:${message.content.hashCode}';
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
          context.read<SettingsController>().aiHtmlRenderFallback ==
              AiHtmlRenderFallback.plainText) {
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
        htmlFallback: context.watch<SettingsController>().aiHtmlRenderFallback,
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
        child: _SafeMarkdownBody(
          data: data.isEmpty ? ' ' : data,
          streaming: true,
          builders: markdownBuilders,
          styleSheet: markdownStyleSheet.styleSheet,
          inlineSyntaxes: inlineSyntaxes,
          pathRoots: filePathRoots,
          parseKey: filePathParseKey,
        ),
      );
    }

    final responseVariantBodyMotionKey =
        isAssistantResponse && message.responseVariants.length > 1
        ? Object.hash(
            message.id,
            message.responseVariantIndex,
            effectiveContent.length,
            effectiveContent.hashCode,
          )
        : null;
    final streamingPlainAssistantShouldCollapse =
        isStreamingAssistant &&
        resolvedMessageContentFormat == AiMessageContentFormat.plainText &&
        _messageShouldCollapse(
          effectiveContent,
          charThreshold: _messageMarkdownCollapseCharThreshold,
          lineThreshold: _messageMarkdownCollapseLineThreshold,
        );
    final isScrollHighlighted = widget.isScrollHighlighted;
    final highlightBorderColor = colorScheme.primary.withValues(alpha: 0.78);
    final bubbleCard = Container(
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
                    data: _ToolCallStatusViewData.from(context, message),
                    color: textColor,
                  )
                else if (isToolResult)
                  _MessageMetaRow(
                    key: _metaCapsuleKey,
                    icon: Icons.inventory_2_outlined,
                    label: _localizedText(
                      context,
                      zh: '工具结果',
                      en: 'Tool Result',
                    ),
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
                  const SizedBox(height: 10),
                if (isCompressionPoint)
                  _CompressionCheckpointBody(
                    content: message.content,
                    expanded: _compressionExpanded,
                    onToggle: () {
                      if (_compressionExpanded) {
                        _CollapsedBodyScrollOffsetCache.reset(
                          '$compressionBodyScrollStateKey|preview',
                        );
                      }
                      setState(() {
                        _compressionExpanded = !_compressionExpanded;
                      });
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
                  _ToolCallBody(message: message, selectable: true)
                else if (isSelfLearning)
                  ClipRect(child: _SelfLearningCard(message: message))
                else if (goalMessageView != null)
                  _GoalMessageStructuredBody(
                    data: goalMessageView,
                    textColor: textColor,
                  )
                else if (isUser)
                  _PlainTextMessageBody(
                    data: effectiveContent.isEmpty ? ' ' : effectiveContent,
                    textColor: textColor,
                    backgroundColor: backgroundColor,
                    style: markdownStyleSheet.styleSheet.p,
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
                        streamingPlainAssistantShouldCollapse
                            ? _StreamingAssistantTextBody(
                                data: effectiveContent.isEmpty
                                    ? ' '
                                    : effectiveContent,
                                textColor: textColor,
                                backgroundColor: backgroundColor,
                                style: markdownStyleSheet.styleSheet.p,
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
                          onCollapsedChanged: canCollapseAssistantResponse
                              ? (collapsed) {
                                  _setAssistantResponseExpandedOverride(
                                    !collapsed,
                                  );
                                }
                              : null,
                          showCollapseToggle: !canCollapseAssistantResponse,
                          contentMotionKey: responseVariantBodyMotionKey,
                          forceMotionWhenScrolling:
                              _responseVariantSizeMotionActive,
                          scrollStateKey: assistantBodyScrollStateKey,
                        ),
                      if (isStreamingAssistant &&
                          resolvedMessageContentFormat !=
                              AiMessageContentFormat.html) ...[
                        const SizedBox(height: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _TypewriterCaret(color: textColor),
                            const SizedBox(width: 6),
                            Text(
                              _localizedText(
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
              ],
            );
            final allowBubbleSizeMotion =
                (!widget.transcriptScrollActive ||
                    _responseVariantSizeMotionActive) &&
                ((isReasoning && !isStreamingReasoning) ||
                    _reasoningExpandedOverride != null ||
                    _assistantResponseExpandedOverride != null ||
                    _responseVariantSizeMotionActive ||
                    _showRawContent != widget.initiallyShowRawContent);
            final bubbleSizeDuration = allowBubbleSizeMotion
                ? cardMotionDurationFor(
                    context,
                    expanding:
                        (_reasoningExpandedOverride != null &&
                            reasoningExpanded) ||
                        (_assistantResponseExpandedOverride != null &&
                            assistantResponseExpanded) ||
                        (_responseVariantSizeMotionActive &&
                            _responseVariantSizeMotionExpanding) ||
                        _showRawContent,
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
      attachments: attachments,
      hardnessAnnotation: heAnnotation,
      textColor: textColor,
      showModelLabel: !isUser,
      onSelectResponseVariant: widget.onSelectResponseVariant,
      actions: [
        _MessageActionSpec(
          id: 'copy',
          onPressed: widget.onCopy,
          icon: Icons.content_copy_outlined,
          label: _localizedText(context, zh: '复制', en: 'Copy'),
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
                ? _localizedText(context, zh: '停止', en: 'Stop')
                : _localizedText(context, zh: '朗读', en: 'Read'),
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
                ? _localizedText(context, zh: '翻译中', en: 'Translating')
                : widget.translationVisible
                ? _localizedText(context, zh: '查看原始', en: 'Original')
                : _localizedText(context, zh: '翻译', en: 'Translate'),
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
            label: _localizedText(context, zh: '点赞', en: 'Like'),
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
            label: _localizedText(context, zh: '需要改进', en: 'Improve'),
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
            label: _localizedText(context, zh: '重新生成', en: 'Regenerate'),
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
          label: _localizedText(context, zh: '派生', en: 'Fork'),
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
            label: _localizedText(
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
            label: _localizedText(context, zh: '审计', en: 'Audit'),
          ),
        if (!isUser &&
            !isToolCall &&
            !isSelfLearning &&
            !isCompressionPoint &&
            !isStatus &&
            !isGoalEvaluationMessage &&
            resolvedMessageContentFormat != AiMessageContentFormat.plainText)
          _MessageActionSpec(
            id: 'raw-toggle',
            onPressed: () async {
              setState(() => _showRawContent = !_showRawContent);
              widget.onShowRawContentChanged?.call(_showRawContent);
            },
            icon: _showRawContent
                ? Icons.code_off_outlined
                : Icons.code_outlined,
            label: _showRawContent
                ? _localizedText(context, zh: '显示渲染', en: 'Show Rendered')
                : _localizedText(context, zh: '显示原始', en: 'Show Raw'),
          ),
        if (!isUser &&
            !isToolCall &&
            !isSelfLearning &&
            !isCompressionPoint &&
            !isStatus &&
            resolvedMessageContentFormat == AiMessageContentFormat.html &&
            _looksLikeHtml(effectiveContent))
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
            label: _localizedText(context, zh: '浏览器打开', en: 'Open in Browser'),
          ),
      ],
    );
    final messageLayout = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: alignment,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _messageBubbleMaxWidth),
            child: bubbleCard,
          ),
        ),
        selectedActionPanel,
      ],
    );
    final messageContent = widget.trackLayoutChanges
        ? NotificationListener<SizeChangedLayoutNotification>(
            onNotification: (notification) {
              if (_layoutChangeThrottleTimer?.isActive ?? false) {
                return false;
              }
              _layoutChangeThrottleTimer = startSafeTimer(
                const Duration(milliseconds: 200),
                () {},
              );
              widget.onLayoutChanged();
              return false;
            },
            child: SizeChangedLayoutNotifier(child: messageLayout),
          )
        : messageLayout;

    return Listener(
      behavior: HitTestBehavior.translucent,
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
        if (downPos == null || downAt == null) {
          return;
        }
        // 左上方"思考 / 工具调用 / 工具结果"胶囊有自己的
        // 折叠/展开手势，不应顺带触发整张消息卡的"选中"。这里取胶囊
        // 全局矩形与抬起点比较，命中即直接 swallow 不切换 selection。
        if (_isPointerInsideMetaCapsule(event.position)) {
          return;
        }
        if (_isPointerInsideActionPanel(event.position) ||
            _isPointerInsideActionPanel(downPos)) {
          return;
        }
        // HTML 消息中 WebView 内部按钮/链接/表单的点击不能被气泡
        // 选中切换吞掉，否则点了没反应、还多了一条功能按钮条。
        // 同时——macOS Flutter embedder 不会把鼠标事件转发给嵌入的
        // WKWebView 平台视图，所以这里在 tap-like 抬起时主动把坐标
        // 喂给对应 WebView 的 simulateTapAtGlobal()，用 JS 合成点击。
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
            (htmlStateUp ?? htmlStateDown)?.simulateTapAtGlobal(event.position);
          }
          return;
        }
        final movement = (event.position - downPos).distance;
        final elapsed = DateTime.now().difference(downAt);
        if (movement <= _selectionTapMaxDistance &&
            elapsed <= _selectionTapMaxDuration) {
          // Toggle: 已选中时再次点击隐藏功能按钮，未选中时显示。
          // 延迟 80ms，给气泡内的子交互回调（链接 / 图片 / 工具栏按钮）
          // 一个调用 markInteractiveTap() 取消切换的窗口期。
          _scheduleSelectionToggle();
        }
      },
      child: _BubbleHtmlInteractiveScope(state: this, child: messageContent),
    );
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

const double _messageActionChipHeight = 34;
const double _messageActionChipHorizontalPadding = 10;
const double _messageActionChipVerticalPadding = 6;
const double _responseVariantChipHeight = 26;
const double _responseVariantArrowWidth = 20;
const double _responseVariantLabelMinWidth = 28;
const double _messageActionIconSize = 16;

ButtonStyle _messageActionChipStyle(BuildContext context) {
  final theme = Theme.of(context);
  return OutlinedButton.styleFrom(
    minimumSize: const Size(0, _messageActionChipHeight),
    padding: const EdgeInsets.symmetric(
      horizontal: _messageActionChipHorizontalPadding,
      vertical: _messageActionChipVerticalPadding,
    ),
    textStyle: theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w700,
    ),
    visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}

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

class _SelectedMessageActionPanelSlot extends StatelessWidget {
  const _SelectedMessageActionPanelSlot({
    super.key,
    required this.visible,
    required this.alignEnd,
    required this.motionKey,
    required this.animateEntrance,
    required this.onEntranceConsumed,
    required this.actions,
    required this.message,
    required this.attachments,
    required this.hardnessAnnotation,
    required this.textColor,
    required this.showModelLabel,
    this.onSelectResponseVariant,
  });

  final bool visible;
  final bool alignEnd;
  final int motionKey;
  final bool animateEntrance;
  final ValueChanged<int> onEntranceConsumed;
  final List<_MessageActionSpec> actions;
  final AiSessionMessage message;
  final List<AiMessageAttachment> attachments;
  final _HeAnnotation? hardnessAnnotation;
  final Color textColor;
  final bool showModelLabel;
  final Future<void> Function(int index)? onSelectResponseVariant;

  @override
  Widget build(BuildContext context) {
    final duration = cardMotionDurationFor(context, expanding: visible);
    return ClipRect(
      child: AnimatedSwitcher(
        duration: duration,
        switchInCurve: kCardMotionCurve,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (currentChild, previousChildren) => Stack(
          alignment: alignEnd ? Alignment.topRight : Alignment.topLeft,
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        ),
        transitionBuilder: (child, animation) =>
            _SelectedMessageActionPanelPresenceTransition(
              animation: animation,
              alignEnd: alignEnd,
              child: child,
            ),
        child: visible
            ? Padding(
                key: const ValueKey<String>('message-action-panel-visible'),
                padding: const EdgeInsets.only(top: 8),
                child: _SelectedMessageActionPanel(
                  alignEnd: alignEnd,
                  motionKey: motionKey,
                  animateEntrance: animateEntrance,
                  onEntranceConsumed: onEntranceConsumed,
                  actions: actions,
                  message: message,
                  attachments: attachments,
                  hardnessAnnotation: hardnessAnnotation,
                  textColor: textColor,
                  showModelLabel: showModelLabel,
                  onSelectResponseVariant: onSelectResponseVariant,
                ),
              )
            : const SizedBox.shrink(
                key: ValueKey<String>('message-action-panel-hidden'),
              ),
      ),
    );
  }
}

class _SelectedMessageActionPanelPresenceTransition extends StatelessWidget {
  const _SelectedMessageActionPanelPresenceTransition({
    required this.animation,
    required this.alignEnd,
    required this.child,
  });

  final Animation<double> animation;
  final bool alignEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = openHandBoundedCurveAnimation(
      parent: animation,
      curve: kCardMotionCurve,
      reverseCurve: kCardMotionCurve,
    );
    final alignment = alignEnd ? Alignment.topRight : Alignment.topLeft;
    return SizeTransition(
      sizeFactor: size,
      axisAlignment: -1,
      child: AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) {
          final isExiting =
              animation.status == AnimationStatus.reverse ||
              animation.status == AnimationStatus.dismissed;
          if (!isExiting) {
            return child!;
          }
          final t = size.value.clamp(0.0, 1.0);
          return IgnorePointer(
            child: Opacity(
              opacity: Curves.easeInCubic.transform(t),
              child: Transform.scale(
                scale: 0.96 + 0.04 * t,
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

class _SelectedMessageActionPanel extends StatefulWidget {
  const _SelectedMessageActionPanel({
    required this.alignEnd,
    required this.motionKey,
    required this.animateEntrance,
    required this.onEntranceConsumed,
    required this.actions,
    required this.message,
    required this.attachments,
    required this.hardnessAnnotation,
    required this.textColor,
    required this.showModelLabel,
    this.onSelectResponseVariant,
  });

  final bool alignEnd;
  final int motionKey;
  final bool animateEntrance;
  final ValueChanged<int> onEntranceConsumed;
  final List<_MessageActionSpec> actions;
  final AiSessionMessage message;
  final List<AiMessageAttachment> attachments;
  final _HeAnnotation? hardnessAnnotation;
  final Color textColor;
  final bool showModelLabel;
  final Future<void> Function(int index)? onSelectResponseVariant;

  @override
  State<_SelectedMessageActionPanel> createState() =>
      _SelectedMessageActionPanelState();
}

class _SelectedMessageActionPanelState
    extends State<_SelectedMessageActionPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _motion;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _motion = CurvedAnimation(parent: _controller, curve: kCardMotionCurve);
    _prepareEntrance();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotionDuration();
  }

  @override
  void didUpdateWidget(covariant _SelectedMessageActionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotionDuration();
    if (oldWidget.motionKey != widget.motionKey) {
      _prepareEntrance();
    }
  }

  void _prepareEntrance() {
    if (widget.animateEntrance) {
      _controller.value = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!widget.animateEntrance) return;
        widget.onEntranceConsumed(widget.motionKey);
        _controller.forward(from: 0);
      });
      return;
    }
    _controller.value = 1;
  }

  void _syncMotionDuration() {
    final duration = cardMotionDurationFor(context, expanding: true);
    if (_controller.duration != duration) {
      _controller.duration = duration;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _motion,
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: widget.alignEnd
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: widget.alignEnd
                  ? WrapAlignment.end
                  : WrapAlignment.start,
              children: [
                for (final action in widget.actions)
                  _MessageActionButton(
                    key: ValueKey<String>(action.id),
                    onPressed: action.onPressed,
                    icon: action.icon,
                    label: action.label,
                    selected: action.selected,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            _SelectedMessageContextRow(
              message: widget.message,
              attachments: widget.attachments,
              hardnessAnnotation: widget.hardnessAnnotation,
              textColor: widget.textColor,
              alignEnd: widget.alignEnd,
              showModelLabel: widget.showModelLabel,
              onSelectResponseVariant: widget.onSelectResponseVariant,
            ),
          ],
        ),
      ),
      builder: (context, child) {
        final t = _motion.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: t,
          child: Transform.scale(
            scale: 0.88 + 0.12 * t,
            alignment: widget.alignEnd ? Alignment.topRight : Alignment.topLeft,
            child: Transform.translate(
              offset: Offset(0, 5 * (1 - t)),
              child: child,
            ),
          ),
        );
      },
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
    final colorScheme = Theme.of(context).colorScheme;
    final baseStyle = _messageActionChipStyle(context);
    final effectiveStyle = selected
        ? baseStyle.copyWith(
            backgroundColor: WidgetStatePropertyAll(
              colorScheme.primaryContainer.withValues(alpha: 0.72),
            ),
            foregroundColor: WidgetStatePropertyAll(
              colorScheme.onPrimaryContainer,
            ),
            iconColor: WidgetStatePropertyAll(colorScheme.onPrimaryContainer),
            side: WidgetStatePropertyAll(
              BorderSide(color: colorScheme.primary.withValues(alpha: 0.62)),
            ),
          )
        : baseStyle;
    return OutlinedButton.icon(
      onPressed: onPressed == null
          ? null
          : () {
              _BubbleHtmlInteractiveScope.maybeOf(
                context,
              )?.markInteractiveTap();
              unawaited(onPressed!());
            },
      style: effectiveStyle,
      icon: Icon(icon, size: _messageActionIconSize),
      label: Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
      ),
    );
  }
}

const Duration _mediaClipboardOperationTimeout = Duration(seconds: 15);
const Duration _mediaClipboardNetworkTimeout = Duration(seconds: 25);
const Duration _remoteMediaOpenTimeout = Duration(seconds: 20);
const Duration _remoteMediaHeaderTimeout = Duration(seconds: 30);
const Duration _remoteMediaChunkTimeout = Duration(seconds: 30);
const Duration _remoteImageDownloadTimeout = Duration(minutes: 5);
const Duration _remoteAudioDownloadTimeout = Duration(minutes: 5);
const Duration _remoteVideoDownloadTimeout = Duration(minutes: 20);
const int _imageClipboardMaxBytes = 64 * kBytesPerMiB;
const int _remoteImageDownloadMaxBytes = 256 * kBytesPerMiB;
const int _remoteAudioDownloadMaxBytes = 256 * kBytesPerMiB;
const int _remoteVideoDownloadMaxBytes = 2 * kBytesPerGiB;

void _showMediaClipboardSnack(
  BuildContext context, {
  required String zh,
  required String en,
  bool isError = false,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final message = _localizedText(context, zh: zh, en: en);
  OpenHandSnackBar.show(
    context,
    messenger,
    isError
        ? OpenHandSnackBar.error(context, message, maxLines: 2)
        : OpenHandSnackBar.success(context, message),
  );
}

Future<bool> _copyLocalFileToPasteboard(String filePath) async {
  var ok = false;
  try {
    ok = await Pasteboard.writeFiles(<String>[
      filePath,
    ]).timeout(_mediaClipboardOperationTimeout);
  } catch (_) {
    ok = false;
  } finally {
    await Clipboard.setData(
      ClipboardData(text: filePath),
    ).timeout(_mediaClipboardOperationTimeout);
  }
  return ok;
}

Future<Uint8List> _readLocalClipboardBytes(
  String filePath, {
  required int maxBytes,
}) async {
  final file = File(filePath);
  final stat = await file.stat().timeout(_mediaClipboardOperationTimeout);
  if (stat.size > maxBytes) {
    throw FileSystemException('File is too large for clipboard.', filePath);
  }
  return file.readAsBytes().timeout(_mediaClipboardOperationTimeout);
}

Future<Uint8List> _downloadClipboardBytes(
  Uri uri, {
  required int maxBytes,
  String? expectedPrimaryType,
}) async {
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    throw FileSystemException('Unsupported URI scheme: ${uri.scheme}', '$uri');
  }
  final client = SystemProxyResolver.instance.createRawHttpClient(
    connectionTimeout: _mediaClipboardNetworkTimeout,
  );
  try {
    final request = await client
        .getUrl(uri)
        .timeout(_mediaClipboardNetworkTimeout);
    final response = await request.close().timeout(
      _mediaClipboardNetworkTimeout,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    final contentType = response.headers.contentType;
    if (expectedPrimaryType != null &&
        contentType != null &&
        contentType.primaryType != expectedPrimaryType &&
        contentType.mimeType != 'application/octet-stream') {
      throw HttpException(
        'Unexpected content type: ${contentType.mimeType}',
        uri: uri,
      );
    }
    final contentLength = response.contentLength;
    if (contentLength > maxBytes) {
      throw HttpException('Response is too large for clipboard.', uri: uri);
    }
    final bytes = BytesBuilder(copy: false);
    var received = 0;
    await for (final chunk in response.timeout(_mediaClipboardNetworkTimeout)) {
      received += chunk.length;
      if (received > maxBytes) {
        throw HttpException('Response is too large for clipboard.', uri: uri);
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  } finally {
    client.close(force: true);
  }
}

Future<void> _downloadRemoteUriToFile({
  required Uri uri,
  required String destination,
  required String resourceLabel,
  required Duration totalTimeout,
  required int maxBytes,
  String? expectedPrimaryType,
  bool allowOctetStream = true,
  Future<void>? cancelSignal,
}) async {
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    throw FileSystemException(
      'Unsupported $resourceLabel URI scheme: ${uri.scheme}',
      uri.toString(),
    );
  }

  final client = SystemProxyResolver.instance.createRawHttpClient(
    connectionTimeout: _remoteMediaOpenTimeout,
  );
  var cancelled = false;
  if (cancelSignal != null) {
    unawaited(
      cancelSignal
          .then<void>(
            (_) {},
            onError: (Object error, StackTrace stack) {
              silentLog(
                'home_message_bubble',
                'remote media cancel signal',
                error,
                stack,
              );
            },
          )
          .whenComplete(() {
            cancelled = true;
            client.close(force: true);
          }),
    );
  }

  try {
    final request = await client.getUrl(uri).timeout(_remoteMediaOpenTimeout);
    if (cancelled) {
      throw const _MediaDownloadCancelled();
    }
    final response = await request.close().timeout(_remoteMediaHeaderTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'HTTP ${response.statusCode} while downloading $resourceLabel.',
        uri: uri,
      );
    }
    final contentType = response.headers.contentType;
    if (expectedPrimaryType != null &&
        contentType != null &&
        contentType.primaryType != expectedPrimaryType &&
        (!allowOctetStream ||
            contentType.mimeType != 'application/octet-stream')) {
      throw HttpException(
        'Unexpected content type: ${contentType.mimeType}',
        uri: uri,
      );
    }
    if (response.contentLength > maxBytes) {
      throw FileSystemException(
        '$resourceLabel download exceeded size limit.',
        destination,
      );
    }

    final outputFile = File(destination);
    final output = outputFile.openWrite();
    final deadline = DateTime.now().add(totalTimeout);
    var receivedBytes = 0;
    var outputClosed = false;

    Future<void> closeOutput() async {
      if (outputClosed) return;
      outputClosed = true;
      await output.close();
    }

    try {
      await for (final chunk in response.timeout(_remoteMediaChunkTimeout)) {
        if (cancelled) {
          throw const _MediaDownloadCancelled();
        }
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException(
            '$resourceLabel download exceeded time limit.',
          );
        }
        receivedBytes += chunk.length;
        if (receivedBytes > maxBytes) {
          throw FileSystemException(
            '$resourceLabel download exceeded size limit.',
            destination,
          );
        }
        output.add(chunk);
      }
      await output.flush();
    } catch (error, stack) {
      try {
        await closeOutput();
      } catch (closeError, closeStack) {
        silentLog(
          'home_message_bubble',
          'close failed $resourceLabel download stream',
          closeError,
          closeStack,
        );
      }
      try {
        if (await outputFile.exists()) {
          await outputFile.delete();
        }
      } on FileSystemException catch (cleanupError, cleanupStack) {
        silentLog(
          'home_message_bubble',
          'delete partial $resourceLabel download',
          cleanupError,
          cleanupStack,
        );
      }
      Error.throwWithStackTrace(error, stack);
    } finally {
      if (!outputClosed) {
        await output.close();
      }
    }
  } finally {
    client.close(force: true);
  }
}

/// Opens a message attachment inside the app preview surface. Images render
/// directly; other files show a lightweight file preview with copy/open actions.
Future<void> _openAttachment(
  BuildContext context,
  AiMessageAttachment attachment,
) async {
  final storagePath = attachment.storagePath.trim();
  if (storagePath.isEmpty) {
    return;
  }
  final file = File(storagePath);
  if (!file.existsSync()) {
    if (!context.mounted) return;
    _showHomeSnackBar(
      context,
      SnackBar(
        content: Text(
          _localizedText(
            context,
            zh: '附件文件不存在或已被移动。',
            en: 'Attachment file not found or has been moved.',
          ),
        ),
      ),
    );
    return;
  }

  if (attachment.isImage) {
    if (!context.mounted) return;
    showAnimatedDialog<void>(
      context: context,
      builder: (dialogContext) => _ImagePreviewDialog.file(
        filePath: storagePath,
        title: attachment.name,
      ),
    );
    return;
  }

  if (!context.mounted) return;
  showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) => _FilePreviewDialog(
      filePath: storagePath,
      title: attachment.name,
      sizeBytes: attachment.sizeBytes,
      kind: attachment.kind,
    ),
  );
}

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
  // Refuse anything that doesn't look like a local file path. Without this
  // a string such as `https://evil.invalid` or a leading `-flag` could be
  // forwarded directly to `open` / `xdg-open`, which both happily treat
  // those inputs as URLs / option flags.
  final looksLikeUri = RegExp(
    r'^[A-Za-z][A-Za-z0-9+.-]*:',
  ).hasMatch(normalizedPath);
  final isWindowsDrivePath =
      Platform.isWindows &&
      RegExp(r'^[A-Za-z]:([\\/]|$)').hasMatch(normalizedPath);
  final hasLeadingDash = normalizedPath.startsWith('-');
  if ((looksLikeUri && !isWindowsDrivePath) || hasLeadingDash) {
    if (context.mounted) {
      _showHomeSnackBar(
        context,
        SnackBar(
          content: Text(
            _localizedText(
              context,
              zh: '拒绝打开不安全的路径：$normalizedPath',
              en: 'Refused unsafe path: $normalizedPath',
            ),
          ),
        ),
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
      Platform.isMacOS || Platform.isWindows || Platform.isLinux
          ? 'Failed to open file.'
          : 'Unsupported platform.',
      normalizedPath,
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    _showHomeSnackBar(
      context,
      SnackBar(
        content: Text(
          _localizedText(
            context,
            zh: '打开文件失败：$error',
            en: 'Failed to open file: $error',
          ),
        ),
      ),
    );
  }
}

/// Opens a composer attachment draft through the same in-app preview path as
/// persisted message attachments.
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
      mimeType: '',
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
      child: Dialog(
        insetPadding: const EdgeInsets.all(24),
        backgroundColor: colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: math.min(MediaQuery.sizeOf(context).width * 0.92, 560),
            maxHeight: MediaQuery.sizeOf(context).height * 0.82,
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
                    const SizedBox(width: 10),
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
                        tooltip: _localizedText(
                          context,
                          zh: '复制文件',
                          en: 'Copy File',
                        ),
                        onPressed: _copying ? null : () => _copyFile(context),
                      ),
                    ),
                    const SizedBox(width: 4),
                    MicroPressFeedback(
                      child: IconButton(
                        icon: Icon(
                          Icons.open_in_new_rounded,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        tooltip: _localizedText(
                          context,
                          zh: '使用系统应用打开',
                          en: 'Open with System App',
                        ),
                        onPressed: _opening ? null : () => _openFile(context),
                      ),
                    ),
                    const SizedBox(width: 4),
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
                          borderRadius: BorderRadius.circular(14),
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
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                _iconForAttachmentKind(widget.kind),
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                            const SizedBox(width: 14),
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
                                  const SizedBox(height: 8),
                                  Text(
                                    aiFormatBytes(widget.sizeBytes),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
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
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        alignment: WrapAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _copying
                                ? null
                                : () => _copyFile(context),
                            icon: const Icon(
                              Icons.content_copy_outlined,
                              size: 18,
                            ),
                            label: Text(
                              _copying
                                  ? _localizedText(
                                      context,
                                      zh: '复制中…',
                                      en: 'Copying…',
                                    )
                                  : _localizedText(
                                      context,
                                      zh: '复制',
                                      en: 'Copy',
                                    ),
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: _opening
                                ? null
                                : () => _openFile(context),
                            icon: const Icon(
                              Icons.open_in_new_rounded,
                              size: 18,
                            ),
                            label: Text(
                              _localizedText(context, zh: '打开', en: 'Open'),
                            ),
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

/// Shimmer / skeleton placeholder shown while an image frame is loading.
class _ImageShimmerPlaceholder extends StatefulWidget {
  const _ImageShimmerPlaceholder();

  @override
  State<_ImageShimmerPlaceholder> createState() =>
      _ImageShimmerPlaceholderState();
}

class _ImageShimmerPlaceholderState extends State<_ImageShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final baseColor = cs.surfaceContainerHighest;
    final highlightColor = cs.surfaceContainerLow;
    final animationsEnabled =
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    if (!animationsEnabled) {
      _ctrl.stop();
      return _buildPlaceholder(cs, baseColor, highlightColor, 0.5);
    }
    if (!_ctrl.isAnimating) {
      _ctrl.repeat();
    }
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return _buildPlaceholder(cs, baseColor, highlightColor, _ctrl.value);
      },
    );
  }

  Widget _buildPlaceholder(
    ColorScheme cs,
    Color baseColor,
    Color highlightColor,
    double progress,
  ) {
    return SizedBox.expand(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment(-1.0 + 2.0 * progress, 0),
            end: Alignment(-1.0 + 2.0 * progress + 1.0, 0),
            colors: [baseColor, highlightColor, baseColor],
          ),
        ),
        child: Center(
          child: Icon(
            Icons.image_outlined,
            size: 48,
            color: cs.onSurfaceVariant.withValues(alpha: 0.3),
          ),
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

/// Adaptive image preview dialog with zoom and pan support.
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

class _ImagePreviewDialogState extends State<_ImagePreviewDialog> {
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

  ImageStream? _imageStream;
  ImageStreamListener? _imageStreamListener;
  Size? _naturalSize;
  final GlobalKey _headerKey = GlobalKey();
  double? _measuredHeaderHeight;
  bool _isCopying = false;

  @override
  void initState() {
    super.initState();
    _resolveImageDimensions();
  }

  /// 提前订阅 ImageProvider 流, 拿到图片自身的宽高用于尺寸计算。
  /// `Image.file` / `Image.network` 内部仍走自己的解码/缓存通道,
  /// 这里只是借用 Flutter ImageCache 命中 (二次解析不会重复下载)。
  void _resolveImageDimensions() {
    ImageProvider? provider;
    final filePath = widget.filePath;
    final imageUri = widget.imageUri;
    if (filePath != null) {
      provider = FileImage(File(filePath));
    } else if (imageUri != null) {
      provider = NetworkImage(imageUri.toString());
    }
    if (provider == null) {
      return;
    }
    final stream = provider.resolve(const ImageConfiguration());
    final listener = ImageStreamListener(
      (ImageInfo info, bool synchronousCall) {
        final w = info.image.width.toDouble();
        final h = info.image.height.toDouble();
        if (w <= 0 || h <= 0) return;
        // 同步回调 (来自缓存) 发生在 initState 中, 此时还未首次 build,
        // 直接给字段赋值即可, 不需要 setState; 否则按常规通过 setState 触发重建。
        if (synchronousCall) {
          _naturalSize = Size(w, h);
          return;
        }
        if (!mounted) return;
        final prev = _naturalSize;
        if (prev != null && prev.width == w && prev.height == h) return;
        setState(() {
          _naturalSize = Size(w, h);
        });
      },
      onError: (Object _, StackTrace? _) {
        // 错误状态下保持 _naturalSize 为 null, 走占位尺寸分支;
        // _buildPreviewImage 内部 Image 控件自己会渲染 errorBuilder。
      },
    );
    stream.addListener(listener);
    _imageStream = stream;
    _imageStreamListener = listener;
  }

  @override
  void dispose() {
    final stream = _imageStream;
    final listener = _imageStreamListener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final viewport = _adaptivePreviewDialogViewport(context);
    _scheduleHeaderHeightSync();

    final natural = _naturalSize;
    final metrics = _AdaptivePreviewDialogMetrics.fromAspectRatio(
      viewport: viewport,
      insetPadding: _kInsetPadding,
      chromeHeight:
          math.max(_kHeaderEstimate, _measuredHeaderHeight ?? 0) + _kDividerH,
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
      child: Dialog(
        insetPadding: const EdgeInsets.all(_kInsetPadding),
        constraints: BoxConstraints(
          minWidth: metrics.dialogWidth,
          maxWidth: metrics.dialogWidth,
          maxHeight: metrics.maxDialogHeight,
        ),
        backgroundColor: colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: AnimatedSize(
          duration: cardMotionDurationFor(context, expanding: true),
          curve: kCardMotionCurve,
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
                    key: _headerKey,
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
                            tooltip: _localizedText(
                              context,
                              zh: '使用系统应用打开',
                              en: 'Open with System App',
                            ),
                            onPressed: () => _openInSystemApp(context),
                          ),
                        ),
                        const SizedBox(width: 4),
                        MicroPressFeedback(
                          child: IconButton(
                            icon: Icon(
                              Icons.content_copy_outlined,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            tooltip: _localizedText(
                              context,
                              zh: '复制图片',
                              en: 'Copy Image',
                            ),
                            onPressed: _isCopying
                                ? null
                                : () => _copyImageToClipboard(context),
                          ),
                        ),
                        const SizedBox(width: 4),
                        MicroPressFeedback(
                          child: IconButton(
                            icon: Icon(
                              Icons.download_rounded,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            tooltip: _localizedText(
                              context,
                              zh: '保存到本地',
                              en: 'Save to disk',
                            ),
                            onPressed: () => _saveImageAs(context),
                          ),
                        ),
                        const SizedBox(width: 4),
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

  void _scheduleHeaderHeightSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final renderObject = _headerKey.currentContext?.findRenderObject();
      if (renderObject is! RenderBox) return;
      final height = renderObject.size.height;
      if (height <= 0) return;
      final previous = _measuredHeaderHeight;
      if (previous != null && (previous - height).abs() < 0.5) return;
      setState(() => _measuredHeaderHeight = height);
    });
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
          await Pasteboard.writeImage(
            bytes,
          ).timeout(_mediaClipboardOperationTimeout);
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
        await Pasteboard.writeImage(
          bytes,
        ).timeout(_mediaClipboardOperationTimeout);
        if (!context.mounted) return;
        _showMediaClipboardSnack(
          context,
          zh: '已复制图片到剪贴板。',
          en: 'Copied image to clipboard.',
        );
      } catch (_) {
        await Clipboard.setData(
          ClipboardData(text: sourceUri.toString()),
        ).timeout(_mediaClipboardOperationTimeout);
        if (!context.mounted) return;
        _showMediaClipboardSnack(
          context,
          zh: '无法复制图片数据，已复制图片地址。',
          en: 'Unable to copy image data. Copied the image URL.',
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

  Widget _buildPreviewImage(BuildContext context, Size displaySize) {
    final sourceFilePath = widget.filePath;
    if (sourceFilePath != null) {
      return Image.file(
        File(sourceFilePath),
        width: displaySize.width,
        height: displaySize.height,
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
              borderRadius: BorderRadius.circular(12),
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
                    const SizedBox(height: 12),
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
          borderRadius: BorderRadius.circular(12),
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
              const SizedBox(height: 12),
              Text(
                _localizedText(
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
  }

  Future<void> _saveImageAs(BuildContext context) async {
    final basename = _suggestedSaveName();
    final ext = _normalizeSaveExtension(p.extension(basename).toLowerCase());
    // Map common image extensions to MIME types for the save dialog.
    final mimeType = switch (ext) {
      '.png' => 'image/png',
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.webp' => 'image/webp',
      '.gif' => 'image/gif',
      '.bmp' => 'image/bmp',
      _ => 'image/png',
    };
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
        final source = File(sourceFilePath);
        if (!source.existsSync()) {
          throw FileSystemException(
            'Image source file is missing.',
            source.path,
          );
        }
        await source.copy(location.path);
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
        fallback: _localizedText(context, zh: '保存失败', en: 'Save failed'),
      );
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
      final decodedPath = () {
        try {
          return Uri.decodeFull(sourceUri.path);
        } catch (_) {
          return sourceUri.path;
        }
      }();
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
      resourceLabel: 'image',
      totalTimeout: _remoteImageDownloadTimeout,
      maxBytes: _remoteImageDownloadMaxBytes,
      expectedPrimaryType: 'image',
      allowOctetStream: false,
    );
  }
}

enum _GeneratedMessageMediaKind { video, audio }

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

  bool get isLocalFile => filePath != null;
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

class _GeneratedMediaLinkCardState extends State<_GeneratedMediaLinkCard>
    with SingleTickerProviderStateMixin {
  static const int _revealCacheLimit = 600;
  static final LinkedHashSet<String> _revealedMediaKeys =
      LinkedHashSet<String>();

  late final AnimationController _revealController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final Animation<double> _revealAnimation = CurvedAnimation(
    parent: _revealController,
    curve: Curves.easeOutBack,
  );

  // Without this guard, rapid double-clicks on the inline card stacked two
  // identical preview dialogs (each spinning up its own WebView), which
  // pinned the UI thread and leaked event handlers.
  bool _dialogOpen = false;
  // Cached sidecar PNG path for local video previews. `null` while the
  // capture is pending or when the source is remote / not a video.
  String? _videoThumbPath;
  bool _videoCaptureRequested = false;
  _GeneratedMediaSource? _cachedSource;
  int _cacheRequestSerial = 0;

  _GeneratedMediaSource get _effectiveSource => _cachedSource ?? widget.source;

  @override
  void initState() {
    super.initState();
    _syncRevealAnimation();
    _syncCachedSource();
    _initVideoThumbnail();
  }

  @override
  void dispose() {
    _revealController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _GeneratedMediaLinkCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source.filePath != widget.source.filePath ||
        oldWidget.source.uri != widget.source.uri ||
        oldWidget.source.kind != widget.source.kind ||
        oldWidget.title != widget.title) {
      _syncRevealAnimation();
    }
    if (oldWidget.source.filePath != widget.source.filePath ||
        oldWidget.source.uri != widget.source.uri ||
        oldWidget.source.kind != widget.source.kind) {
      _cacheRequestSerial++;
      _cachedSource = null;
      _videoThumbPath = null;
      _videoCaptureRequested = false;
      _syncCachedSource();
      _initVideoThumbnail();
    }
  }

  void _syncRevealAnimation() {
    final disableAnimations = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    final revealKey = _generatedMediaRevealKey(widget.source, widget.title);
    final hasPlayedReveal = _revealedMediaKeys.contains(revealKey);
    _rememberRevealedMediaKey(revealKey);
    if (disableAnimations || hasPlayedReveal) {
      _revealController.value = 1;
      return;
    }
    _revealController.forward(from: 0);
  }

  static void _rememberRevealedMediaKey(String key) {
    if (key.isEmpty) return;
    _revealedMediaKeys.remove(key);
    _revealedMediaKeys.add(key);
    while (_revealedMediaKeys.length > _revealCacheLimit) {
      _revealedMediaKeys.remove(_revealedMediaKeys.first);
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
      MediaCacheService.instance.ensureCached(url, kind: cacheKind).then((
        cachedPath,
      ) {
        if (!mounted || serial != _cacheRequestSerial || cachedPath == null) {
          return;
        }
        setState(() {
          _cachedSource = _cachedGeneratedMediaSource(source, cachedPath);
          _videoThumbPath = null;
          _videoCaptureRequested = false;
        });
        _initVideoThumbnail();
      }),
    );
  }

  Future<void> _initVideoThumbnail() async {
    final source = _effectiveSource;
    if (source.kind != _GeneratedMessageMediaKind.video) return;
    final path = source.filePath;
    if (path == null) return;
    final cached = _VideoThumbnailManager.thumbnailPathFor(path);
    try {
      if (await File(cached).exists()) {
        if (!mounted) return;
        setState(() => _videoThumbPath = cached);
        return;
      }
    } catch (error, stack) {
      silentLog(
        'home_message_bubble',
        'video thumbnail: cache probe failed',
        error,
        stack,
      );
    }
    if (!mounted) return;
    if (_VideoThumbnailManager.isMarkedFailed(path)) return;
    setState(() => _videoCaptureRequested = true);
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
        await MediaCacheService.instance.ensureCached(url, kind: cacheKind);
    if (cachedPath == null || !mounted) return source;
    final cachedSource = _cachedGeneratedMediaSource(source, cachedPath);
    if (mounted) {
      setState(() {
        _cachedSource = cachedSource;
        _videoThumbPath = null;
        _videoCaptureRequested = false;
      });
    }
    return cachedSource;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = _effectiveSource;
    final title = widget.title;
    final textColor = widget.textColor;
    final backgroundColor = widget.backgroundColor;
    final isVideo = source.kind == _GeneratedMessageMediaKind.video;
    if (isVideo) {
      return _buildResultReveal(
        _buildVideoCard(theme, source, title, textColor, backgroundColor),
      );
    }
    final detail = _generatedMediaSourceDetail(source);
    final meta = _GeneratedAudioVisualMeta.fromSource(
      source: source,
      title: title,
      detail: detail,
    );
    return _buildResultReveal(
      _GeneratedAudioCard(
        meta: meta,
        title: title,
        textColor: textColor,
        backgroundColor: backgroundColor,
        onTap: _openPreview,
      ),
    );
  }

  Widget _buildResultReveal(Widget child) {
    if (MediaQuery.disableAnimationsOf(context) ||
        _revealController.isCompleted) {
      return child;
    }
    return AnimatedBuilder(
      animation: _revealAnimation,
      child: child,
      builder: (context, child) {
        final raw = _revealAnimation.value;
        final t = raw.clamp(0.0, 1.0);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 10),
            child: Transform.scale(
              alignment: Alignment.centerLeft,
              scale: 0.965 + 0.035 * raw,
              child: child,
            ),
          ),
        );
      },
    );
  }

  Widget _buildVideoCard(
    ThemeData theme,
    _GeneratedMediaSource source,
    String title,
    Color textColor,
    Color backgroundColor,
  ) {
    final detail = _generatedMediaSourceDetail(source);
    final cardColor = Color.alphaBlend(
      textColor.withValues(alpha: 0.08),
      backgroundColor,
    );
    final thumbPath = _videoThumbPath;
    final showCapture =
        _videoCaptureRequested && thumbPath == null && source.isLocalFile;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Semantics(
        button: true,
        label: title,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _openPreview,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420, minWidth: 240),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: textColor.withValues(alpha: 0.16)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (thumbPath != null)
                          Image.file(
                            File(thumbPath),
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            // Inline 16:9 thumbnail in maxWidth=420 box.
                            // Decode at ~840px wide (covers 2x DPR) to
                            // avoid keeping full-resolution raster in memory.
                            cacheWidth: 840,
                            errorBuilder: (_, _, _) =>
                                Container(color: Colors.black87),
                          )
                        else
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.black.withValues(alpha: 0.78),
                                  Colors.black.withValues(alpha: 0.92),
                                ],
                              ),
                            ),
                          ),
                        // Subtle scrim so the play icon stays legible on
                        // bright thumbnails.
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.0),
                                Colors.black.withValues(alpha: 0.35),
                              ],
                            ),
                          ),
                        ),
                        Center(
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.85),
                                width: 1.4,
                              ),
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.videocam_outlined,
                                  size: 13,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'VIDEO',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (showCapture)
                          Positioned(
                            left: 0,
                            top: 0,
                            child: _VideoThumbnailCaptureHost(
                              videoPath: source.filePath!,
                              mimeType: _mimeTypeForGeneratedMedia(source),
                              onResult: (path) {
                                if (!mounted) return;
                                setState(() {
                                  _videoCaptureRequested = false;
                                  _videoThumbPath = path;
                                });
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.start,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: textColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.start,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: textColor.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
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

String _generatedMediaRevealKey(_GeneratedMediaSource source, String title) {
  final path = source.filePath?.trim();
  final sourceId = path != null && path.isNotEmpty
      ? path
      : source.displayUri.toString();
  return '${source.kind.name}|$sourceId|${title.trim()}';
}

class _GeneratedAudioVisualMeta {
  const _GeneratedAudioVisualMeta({
    required this.title,
    required this.artist,
    required this.album,
    required this.detail,
    required this.seed,
    required this.primaryColor,
    required this.secondaryColor,
    required this.accentColor,
    required this.coverGlyph,
  });

  factory _GeneratedAudioVisualMeta.fromSource({
    required _GeneratedMediaSource source,
    required String title,
    required String detail,
  }) {
    final cleanTitle = _normalizeAudioDisplayText(
      title,
      fallback: _generatedMediaFallbackTitle(source),
    );
    final cleanDetail = _normalizeAudioDisplayText(
      detail,
      fallback: 'OpenHand',
    );
    final seedText = '$cleanTitle|$cleanDetail|${source.displayUri}';
    final seed = seedText.hashCode & 0x7fffffff;
    final palette =
        _kGeneratedAudioPalettes[seed % _kGeneratedAudioPalettes.length];
    return _GeneratedAudioVisualMeta(
      title: cleanTitle,
      artist: _deriveGeneratedAudioArtist(cleanDetail),
      album: _deriveGeneratedAudioAlbum(cleanDetail),
      detail: cleanDetail,
      seed: seed,
      primaryColor: palette.$1,
      secondaryColor: palette.$2,
      accentColor: palette.$3,
      coverGlyph: '♪',
    );
  }

  final String title;
  final String artist;
  final String album;
  final String detail;
  final int seed;
  final Color primaryColor;
  final Color secondaryColor;
  final Color accentColor;
  final String coverGlyph;
}

const List<(Color, Color, Color)> _kGeneratedAudioPalettes =
    <(Color, Color, Color)>[
      (Color(0xFF65734F), Color(0xFF96A878), Color(0xFFE5EBD7)),
      (Color(0xFF4F6B70), Color(0xFF7FA3A1), Color(0xFFE0ECEA)),
      (Color(0xFF536D82), Color(0xFF89A7B8), Color(0xFFE2ECF1)),
      (Color(0xFF6A7258), Color(0xFFA8B086), Color(0xFFECE9D6)),
      (Color(0xFF51705F), Color(0xFF84A783), Color(0xFFE3EEE6)),
    ];

String _normalizeAudioDisplayText(String value, {required String fallback}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return fallback;
  return trimmed
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(
        RegExp(r'\.(mp3|wav|m4a|aac|ogg|opus|flac)$', caseSensitive: false),
        '',
      )
      .trim();
}

String _deriveGeneratedAudioArtist(String detail) {
  final basename = p.basename(detail).trim();
  if (basename.isEmpty || basename == '/' || basename == '.') {
    return 'OpenHand 音频';
  }
  final leaf = _prettyGeneratedAudioLeaf(basename);
  final segments = leaf
      .split(RegExp(r'[-_]+'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (segments.length >= 2 && segments.first.length <= 28) {
    return segments.first;
  }
  return _looksLikeGeneratedAudioName(leaf) ? 'AI 音频' : 'OpenHand 音频';
}

String _deriveGeneratedAudioAlbum(String detail) {
  final basename = p.basename(detail).trim();
  final leaf = _prettyGeneratedAudioLeaf(basename.isEmpty ? detail : basename);
  if (_looksLikeGeneratedAudioName(leaf)) return '生成音频';
  if (leaf.length <= 32) return leaf;
  return '音频专辑';
}

String _prettyGeneratedAudioLeaf(String detail) {
  final normalized = _normalizeAudioDisplayText(detail, fallback: detail);
  if (_looksLikeGeneratedAudioName(normalized)) {
    return '生成音频';
  }
  return normalized;
}

bool _looksLikeGeneratedAudioName(String value) {
  final normalized = value.trim().toLowerCase();
  return RegExp(r'^audio[_-]?\d+$').hasMatch(normalized) ||
      RegExp(r'^audio[_-]').hasMatch(normalized);
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
  final meta = _GeneratedAudioVisualMeta.fromSource(
    source: source,
    title: title,
    detail: _generatedMediaSourceDetail(source),
  );
  return NativeAudioVisualMeta(
    title: meta.title,
    artist: meta.artist,
    album: meta.album,
    detail: meta.detail,
    primaryColor: meta.primaryColor,
    secondaryColor: meta.secondaryColor,
    accentColor: meta.accentColor,
    coverGlyph: meta.coverGlyph,
    seed: meta.seed,
  );
}

const double _kGeneratedAudioCardMinWidth = 260;
const double _kGeneratedAudioCardMaxWidth = 360;
const double _kGeneratedAudioCardRadius = 18;
const double _kGeneratedAudioBannerAspectRatio = 16 / 9;
const double _kGeneratedAudioCoverSize = 74;
const double _kGeneratedAudioPlayButtonSize = 38;
const double _kGeneratedAudioHoverScaleDelta = 0.010;
const double _kGeneratedAudioHoverLift = 2.0;
const double _kGeneratedAudioCardBorderWidth = 1.2;

class _GeneratedAudioCardStyle {
  const _GeneratedAudioCardStyle({
    required this.surface,
    required this.border,
    required this.borderHover,
    required this.bannerStart,
    required this.bannerMid,
    required this.bannerEnd,
    required this.bannerStroke,
    required this.bannerPattern,
    required this.coverForeground,
    required this.playBackground,
    required this.playBorder,
    required this.playIcon,
    required this.titleColor,
    required this.subtitleColor,
    required this.metaIconColor,
  });

  factory _GeneratedAudioCardStyle.resolve({
    required ThemeData theme,
    required _GeneratedAudioVisualMeta meta,
    required Color bubbleBackground,
    required Color bubbleTextColor,
  }) {
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final quietSurface = Color.alphaBlend(
      cs.primary.withValues(alpha: isDark ? 0.07 : 0.035),
      cs.surfaceContainerHighest,
    );
    final surface = Color.alphaBlend(
      bubbleTextColor.withValues(alpha: isDark ? 0.025 : 0.014),
      Color.alphaBlend(
        bubbleBackground.withValues(alpha: isDark ? 0.08 : 0.12),
        quietSurface,
      ),
    );
    final bannerStart = Color.alphaBlend(
      meta.primaryColor.withValues(alpha: isDark ? 0.18 : 0.12),
      cs.surfaceContainerHighest,
    );
    final bannerMid = Color.alphaBlend(
      meta.accentColor.withValues(alpha: isDark ? 0.13 : 0.10),
      cs.surfaceContainerHigh,
    );
    final bannerEnd = Color.alphaBlend(
      cs.primary.withValues(alpha: isDark ? 0.08 : 0.045),
      cs.surfaceContainerHigh,
    );
    return _GeneratedAudioCardStyle(
      surface: surface,
      border: cs.outlineVariant.withValues(alpha: isDark ? 0.36 : 0.62),
      borderHover: cs.primary.withValues(alpha: isDark ? 0.54 : 0.42),
      bannerStart: bannerStart,
      bannerMid: bannerMid,
      bannerEnd: bannerEnd,
      bannerStroke: cs.outlineVariant.withValues(alpha: isDark ? 0.38 : 0.55),
      bannerPattern: cs.onSurfaceVariant.withValues(
        alpha: isDark ? 0.16 : 0.20,
      ),
      coverForeground: cs.onSurface.withValues(alpha: 0.94),
      playBackground: cs.surface.withValues(alpha: isDark ? 0.56 : 0.62),
      playBorder: cs.outlineVariant.withValues(alpha: isDark ? 0.58 : 0.72),
      playIcon: cs.primary,
      titleColor: cs.onSurface,
      subtitleColor: cs.onSurfaceVariant,
      metaIconColor: cs.primary.withValues(alpha: isDark ? 0.86 : 0.78),
    );
  }

  final Color surface;
  final Color border;
  final Color borderHover;
  final Color bannerStart;
  final Color bannerMid;
  final Color bannerEnd;
  final Color bannerStroke;
  final Color bannerPattern;
  final Color coverForeground;
  final Color playBackground;
  final Color playBorder;
  final Color playIcon;
  final Color titleColor;
  final Color subtitleColor;
  final Color metaIconColor;

  Color borderFor(double t) => Color.lerp(border, borderHover, t) ?? border;
}

class _GeneratedAudioCard extends StatefulWidget {
  const _GeneratedAudioCard({
    required this.meta,
    required this.title,
    required this.textColor,
    required this.backgroundColor,
    required this.onTap,
  });

  final _GeneratedAudioVisualMeta meta;
  final String title;
  final Color textColor;
  final Color backgroundColor;
  final VoidCallback onTap;

  @override
  State<_GeneratedAudioCard> createState() => _GeneratedAudioCardState();
}

class _GeneratedAudioCardState extends State<_GeneratedAudioCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hoverController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  bool _hovered = false;

  @override
  void dispose() {
    _hoverController.dispose();
    super.dispose();
  }

  void _onHoverChanged(bool hovered) {
    if (_hovered == hovered) return;
    _hovered = hovered;
    if (hovered) {
      _hoverController.forward();
    } else {
      _hoverController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = widget.meta;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final style = _GeneratedAudioCardStyle.resolve(
      theme: Theme.of(context),
      meta: meta,
      bubbleBackground: widget.backgroundColor,
      bubbleTextColor: widget.textColor,
    );
    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: disableAnimations ? null : (_) => _onHoverChanged(true),
        onExit: disableAnimations ? null : (_) => _onHoverChanged(false),
        child: Semantics(
          button: true,
          label: openHandLocalizedText(
            context,
            zh: '打开音频预览：${widget.title}',
            en: 'Open audio preview: ${widget.title}',
          ),
          child: AnimatedBuilder(
            animation: _hoverController,
            builder: (context, _) {
              final t = disableAnimations ? 0.0 : _hoverController.value;
              final scale = 1.0 + t * _kGeneratedAudioHoverScaleDelta;
              final lift = -_kGeneratedAudioHoverLift * t;
              final radius = BorderRadius.circular(_kGeneratedAudioCardRadius);
              return Transform.translate(
                offset: Offset(0, lift),
                child: Transform.scale(
                  alignment: Alignment.centerLeft,
                  scale: scale,
                  child: MicroPressFeedback(
                    scale: 0.985,
                    child: GestureDetector(
                      onTap: widget.onTap,
                      child: Container(
                        constraints: const BoxConstraints(
                          maxWidth: _kGeneratedAudioCardMaxWidth,
                          minWidth: _kGeneratedAudioCardMinWidth,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: radius,
                          color: style.surface,
                        ),
                        foregroundDecoration: BoxDecoration(
                          borderRadius: radius,
                          border: Border.all(
                            color: style.borderFor(t),
                            width: _kGeneratedAudioCardBorderWidth,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: radius,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildCoverBanner(meta, style),
                              _buildInfoRow(context, meta, style),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCoverBanner(
    _GeneratedAudioVisualMeta meta,
    _GeneratedAudioCardStyle style,
  ) {
    return AspectRatio(
      aspectRatio: _kGeneratedAudioBannerAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [style.bannerStart, style.bannerMid, style.bannerEnd],
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: style.bannerStroke)),
              ),
            ),
          ),
          Positioned(
            left: 18,
            bottom: 16,
            child: Icon(
              Icons.graphic_eq_rounded,
              size: 34,
              color: style.bannerPattern,
            ),
          ),
          Positioned(
            right: -18,
            bottom: -24,
            child: Icon(
              Icons.album_rounded,
              size: 108,
              color: style.bannerPattern.withValues(alpha: 0.70),
            ),
          ),
          Center(
            child: _GeneratedAudioAlbumCover(
              meta: meta,
              size: _kGeneratedAudioCoverSize,
              foregroundColor: style.coverForeground,
              compact: true,
            ),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              width: _kGeneratedAudioPlayButtonSize,
              height: _kGeneratedAudioPlayButtonSize,
              decoration: BoxDecoration(
                color: style.playBackground,
                shape: BoxShape.circle,
                border: Border.all(color: style.playBorder),
              ),
              child: Icon(
                Icons.play_arrow_rounded,
                color: style.playIcon,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    _GeneratedAudioVisualMeta meta,
    _GeneratedAudioCardStyle style,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 13),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            meta.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              color: style.titleColor,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.graphic_eq_rounded,
                size: 14,
                color: style.metaIconColor,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  '${meta.artist} · ${meta.album}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: style.subtitleColor,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GeneratedAudioAlbumCover extends StatelessWidget {
  const _GeneratedAudioAlbumCover({
    required this.meta,
    required this.size,
    required this.foregroundColor,
    this.compact = false,
  });

  final _GeneratedAudioVisualMeta meta;
  final double size;
  final Color foregroundColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(compact ? 16 : 22);
    final coverBase = Color.alphaBlend(
      meta.primaryColor.withValues(alpha: 0.12),
      colorScheme.surfaceContainerHighest,
    );
    final coverMid = Color.alphaBlend(
      meta.accentColor.withValues(alpha: 0.10),
      colorScheme.surfaceContainerHighest,
    );
    final coverEnd = Color.alphaBlend(
      colorScheme.primary.withValues(alpha: 0.045),
      colorScheme.surfaceContainerHigh,
    );
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: radius,
        child: Container(
          foregroundDecoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(
                alpha: compact ? 0.58 : 0.48,
              ),
            ),
          ),
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [coverBase, coverMid, coverEnd],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -size * 0.16,
                bottom: -size * 0.22,
                child: Icon(
                  Icons.album_rounded,
                  size: size * 0.86,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.16),
                ),
              ),
              Positioned(
                left: size * 0.10,
                bottom: size * 0.10,
                child: Icon(
                  Icons.graphic_eq_rounded,
                  size: size * 0.18,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.38),
                ),
              ),
              Center(
                child: Container(
                  width: size * 0.30,
                  height: size * 0.30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.surface.withValues(alpha: 0.40),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.68),
                    ),
                  ),
                ),
              ),
              Center(
                child: Text(
                  meta.coverGlyph,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    color: foregroundColor,
                    fontWeight: FontWeight.w900,
                    fontSize: size * (compact ? 0.38 : 0.32),
                    height: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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

class _MediaPreviewDialogState extends State<_MediaPreviewDialog> {
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
  // Reentrancy guards: rapid double-taps on the system-player / save buttons
  // were spawning duplicate downloads to the same destination, corrupting
  // the output file and pinning the WebView event loop.
  bool _isSaving = false;
  bool _isOpeningExternal = false;
  bool _isCopyingMedia = false;
  bool _isEnteringFullscreen = false;
  bool _disposed = false;
  bool _mediaBootstrapStarted = false;
  DialogAnimationSettings _playerMotionSettings =
      DialogAnimationSettings.defaults;
  final GlobalKey _headerKey = GlobalKey();
  double? _measuredHeaderHeight;
  // Cancel signal for the in-flight save. Completed when the user dismisses
  // the dialog mid-download so we stop pulling bytes and clean up the
  // partial file instead of writing into a destination the user is no
  // longer watching.
  Completer<void>? _saveCancel;
  // Path to a temp HTML wrapper written next to a local media file so
  // WKWebView can load `file://` resources (it refuses to do so when the
  // page itself was loaded via `loadHtmlString`/`about:blank`).
  String? _tempHtmlPath;
  // Last reported playback time from the embedded video. Used to hand
  // off the resume position when the user enters / exits fullscreen so
  // both views never play simultaneously and the audio never overlaps.
  double _currentTime = 0;
  // Owns the keyboard focus so spacebar / Esc keystrokes hit the dialog
  // even before the user clicks into the WebView surface.
  final FocusNode _dialogFocus = FocusNode(debugLabel: 'media-preview');

  @override
  void initState() {
    super.initState();
    if (_isVideoPreview) {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel(
          'OpenHandMedia',
          onMessageReceived: _handleMediaMessage,
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (_) {
              if (!mounted) return;
              setState(() => _pageLoaded = true);
            },
            onWebResourceError: (error) {
              if (!mounted) return;
              setState(() {
                _loadError = error.description;
              });
            },
          ),
        );
      // `setBackgroundColor` on macOS bridges to `WKWebView.setOpaque`, which
      // is unimplemented in the wkwebview plugin and throws
      // `UnimplementedError: opaque is not implemented on macOS`. Skip the
      // call there — the dialog already uses a transparent overlay so the
      // default WKWebView background is acceptable.
      if (!Platform.isMacOS) {
        controller.setBackgroundColor(Colors.transparent);
      }
      _controller = controller;
    }
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
      _bootstrapMediaPage();
      _loadTimeoutTimer = startSafeTimer(_mediaLoadTimeout, () {
        if (!mounted || _mediaReady) return;
        setState(() {
          _loadError = _localizedText(
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
      silentLog(
        'home_message_bubble',
        'media preview: toggle play/pause failed',
        error,
        stack,
      );
    }
  }

  // For local `file://` media we must write the HTML wrapper next to the
  // video so WKWebView can grant `file://` read access to the parent
  // directory via `loadFileURL:allowingReadAccessToURL:`. Loading the same
  // HTML via `loadHtmlString` works on Android/iOS Safari but WKWebView on
  // macOS silently refuses to fetch the `<source src="file://...">` entry,
  // resulting in the existing 18s timeout fallback.
  Future<void> _bootstrapMediaPage() async {
    final controller = _controller;
    if (controller == null) return;
    final localPath = widget.source.filePath;
    if (localPath != null && File(localPath).existsSync()) {
      try {
        final dir = p.dirname(localPath);
        final tempName =
            '.openhand_media_player_${DateTime.now().microsecondsSinceEpoch}_${identityHashCode(this)}.html';
        final tempFile = File(p.join(dir, tempName));
        await tempFile.writeAsString(_buildMediaHtml(localOverride: localPath));
        if (!mounted) {
          await tempFile.delete().catchError((_) => tempFile);
          return;
        }
        _tempHtmlPath = tempFile.path;
        await controller.loadFile(tempFile.path);
        return;
      } catch (error, stack) {
        silentLog(
          'home_message_bubble',
          'media preview: loadFile fallback failed',
          error,
          stack,
        );
        // Fall through to loadHtmlString — worst case the user still sees
        // the timeout fallback and can use the system player button.
      }
    }
    if (!mounted) return;
    await controller.loadHtmlString(_buildMediaHtml());
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
      // Stop video playback so closing the dialog never leaves residual
      // media while the WebView tears down.
      unawaited(
        controller
            .runJavaScript(
              "try{var m=document.getElementById('media');if(m){try{m.pause();}catch(_){};try{m.muted=true;}catch(_){};try{m.removeAttribute('src');}catch(_){};try{while(m.firstChild)m.removeChild(m.firstChild);}catch(_){};try{m.load();}catch(_){};}}catch(_){}",
            )
            .catchError((_) {}),
      );
    }
    _dialogFocus.dispose();
    final tempPath = _tempHtmlPath;
    if (tempPath != null) {
      // Best-effort cleanup; ignore failures (file may already be gone).
      Future<void>(() async {
        try {
          final f = File(tempPath);
          if (await f.exists()) await f.delete();
        } catch (error, stack) {
          silentLog(
            'home_message_bubble',
            'media preview: temp html cleanup failed',
            error,
            stack,
          );
        }
      });
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
      final parsed = double.tryParse(raw);
      if (parsed != null && parsed >= 0) {
        _currentTime = parsed;
      }
      return;
    }
    if (value.startsWith('size:')) {
      final parts = value.substring(5).split(':');
      if (parts.length == 2) {
        final width = double.tryParse(parts[0]);
        final height = double.tryParse(parts[1]);
        if (width != null && height != null && width > 0 && height > 0) {
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
.media-shell video{width:100%;height:100%;object-fit:contain;background:#000;border-radius:10px}
.scrim{position:absolute;inset:auto 0 0;height:38%;background:linear-gradient(to top,rgba(0,0,0,.48),transparent);opacity:1;transition:opacity var(--oh-motion-duration) var(--oh-motion-curve);pointer-events:none}
.media-shell:not(.controls-visible) .scrim{opacity:0}
.control-bar{position:absolute;left:50%;bottom:12px;z-index:5;display:flex;align-items:center;gap:10px;width:calc(100% - 40px);max-width:820px;min-height:48px;padding:8px 14px;box-sizing:border-box;border:1px solid var(--oh-control-border);border-radius:999px;background:var(--oh-control-bg);color:var(--oh-control-text);box-shadow:0 18px 42px rgba(0,0,0,.36);backdrop-filter:blur(22px) saturate(1.24);-webkit-backdrop-filter:blur(22px) saturate(1.24);transform-origin:bottom center;transform:translateX(-50%) translateY(0) scale(1);opacity:1;filter:blur(0);transition:opacity var(--oh-motion-duration) var(--oh-motion-curve),transform var(--oh-motion-duration) var(--oh-motion-curve),filter var(--oh-motion-duration) var(--oh-motion-curve)}
.media-shell:not(.controls-visible) .control-bar{opacity:0;pointer-events:none;transform:translateX(-50%) translateY(24px) scale(.94);filter:blur(4px)}
.control-button{width:28px;height:28px;border:0;border-radius:999px;display:inline-flex;align-items:center;justify-content:center;background:transparent;color:#fff;cursor:pointer;transition:transform 160ms var(--oh-motion-curve),background-color 160ms ease-out,opacity 160ms ease-out}
.control-button:hover,.control-button:focus-visible{background:rgba(255,255,255,.14);transform:translateY(-1px) scale(1.06);outline:none}
.control-button.is-active{background:rgba(255,255,255,.20)}
.control-button:active{transform:scale(.92)}
.control-button svg{width:18px;height:18px;display:block;fill:currentColor}
.seek-button svg{width:21px;height:21px}
.time{min-width:48px;text-align:center;font-weight:700;font-variant-numeric:tabular-nums;color:rgba(255,255,255,.92);white-space:nowrap}
.progress{flex:1 1 180px;min-width:96px}
.volume-group{position:relative;display:inline-flex;align-items:center;justify-content:center}
.volume-popover{position:absolute;left:50%;bottom:38px;width:46px;height:136px;display:flex;align-items:center;justify-content:center;border:1px solid var(--oh-control-border);border-radius:999px;background:var(--oh-control-bg);box-shadow:0 18px 42px rgba(0,0,0,.34);backdrop-filter:blur(22px) saturate(1.24);-webkit-backdrop-filter:blur(22px) saturate(1.24);transform-origin:bottom center;transform:translateX(-50%) translateY(10px) scale(.88);opacity:0;pointer-events:none;filter:blur(3px);transition:opacity var(--oh-motion-duration) var(--oh-motion-curve),transform var(--oh-motion-duration) var(--oh-motion-curve),filter var(--oh-motion-duration) var(--oh-motion-curve)}
.volume-open .volume-popover,.volume-group:focus-within .volume-popover{opacity:1;pointer-events:auto;transform:translateX(-50%) translateY(0) scale(1);filter:blur(0)}
.volume.vertical{position:absolute;left:50%;top:50%;width:112px;transform:translate(-50%,-50%) rotate(-90deg);transform-origin:center}
input[type=range]{height:22px;margin:0;accent-color:#fff;cursor:pointer}
input[type=range]::-webkit-slider-runnable-track{height:7px;border-radius:999px;background:linear-gradient(to right,var(--oh-track-fill) 0%,var(--oh-track-fill) var(--value,0%),var(--oh-track) var(--value,0%),var(--oh-track) 100%)}
input[type=range]::-webkit-slider-thumb{-webkit-appearance:none;width:18px;height:18px;margin-top:-5.5px;border-radius:50%;background:#fff;box-shadow:0 2px 10px rgba(0,0,0,.35);transition:transform 160ms var(--oh-motion-curve)}
input[type=range]:hover::-webkit-slider-thumb,input[type=range]:focus-visible::-webkit-slider-thumb{transform:scale(1.12)}
.no-motion *{transition-duration:0ms!important;animation:none!important}
@media (max-width:720px){.control-bar{gap:6px;padding:7px 10px;width:calc(100% - 28px)}.progress{min-width:72px}.time{min-width:42px}.volume-popover{height:116px}.volume.vertical{width:94px}}
@media (max-width:460px){.seek-button{display:none}.control-bar{width:calc(100% - 18px)}.time{min-width:40px}.progress{min-width:64px}.volume-popover{height:104px}.volume.vertical{width:84px}}
</style>
</head>
<body>
<div id="shell" class="media-shell controls-visible$motionClass" tabindex="0">
  <video id="media" playsinline preload="metadata" disableRemotePlayback><source src="$source" type="$escapedMime"></video>
  <div class="scrim"></div>
  <div class="control-bar" id="controls">
    <button id="rewind" class="control-button seek-button" type="button" aria-label="Back 15 seconds" title="Back 15 seconds"></button>
    <button id="play" class="control-button" type="button" aria-label="Play" title="Play"></button>
    <button id="forward" class="control-button seek-button" type="button" aria-label="Forward 15 seconds" title="Forward 15 seconds"></button>
    <span id="current" class="time">00:00</span>
    <input id="progress" class="progress" type="range" min="0" max="1000" step="1" value="0" aria-label="Progress">
    <span id="duration" class="time">00:00</span>
    <div class="volume-group" id="volumeGroup">
      <button id="mute" class="control-button" type="button" aria-label="Mute" title="Mute"></button>
      <div class="volume-popover">
        <input id="volume" class="volume vertical" type="range" min="0" max="1" step="0.01" value="1" aria-label="Volume" aria-orientation="vertical">
      </div>
    </div>
    <button id="playMode" class="control-button" type="button" aria-label="Stop after playback" title="Stop after playback"></button>
    <button id="fullscreen" class="control-button" type="button" aria-label="Fullscreen" title="Fullscreen"></button>
  </div>
</div>
<script>
(function() {
  const AUTO_HIDE_MS = $_kMediaPreviewControlAutoHideMs;
  const POINTER_LEAVE_HIDE_MS = $_kMediaPreviewPointerLeaveHideMs;
  const media = document.getElementById('media');
  const shell = document.getElementById('shell');
  const play = document.getElementById('play');
  const rewind = document.getElementById('rewind');
  const forward = document.getElementById('forward');
  const progress = document.getElementById('progress');
  const current = document.getElementById('current');
  const duration = document.getElementById('duration');
  const volume = document.getElementById('volume');
  const mute = document.getElementById('mute');
  const volumeGroup = document.getElementById('volumeGroup');
  const playMode = document.getElementById('playMode');
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
  let loopPlayback = false;
  let lastSent = -1;
  const icon = {
    play: '<svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>',
    pause: '<svg viewBox="0 0 24 24"><path d="M6 5h4v14H6zM14 5h4v14h-4z"/></svg>',
    mute: '<svg viewBox="0 0 24 24"><path d="M4 9v6h4l5 4V5L8 9H4z"/><path d="M18 9l4 4m0-4-4 4" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/></svg>',
    volume: '<svg viewBox="0 0 24 24"><path d="M4 9v6h4l5 4V5L8 9H4z"/><path d="M16 8.5a5 5 0 010 7M18.5 6a8 8 0 010 12" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/></svg>',
    rewind: '<svg viewBox="0 0 24 24"><path d="M11 7l-6 5 6 5V7zm8 0l-6 5 6 5V7z"/><text x="12" y="21" text-anchor="middle" font-size="7" fill="currentColor">15</text></svg>',
    forward: '<svg viewBox="0 0 24 24"><path d="M13 7l6 5-6 5V7zM5 7l6 5-6 5V7z"/><text x="12" y="21" text-anchor="middle" font-size="7" fill="currentColor">15</text></svg>',
    loop: '<svg viewBox="0 0 24 24"><path d="M17 2l4 4-4 4" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/><path d="M3 11V9a3 3 0 013-3h15" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/><path d="M7 22l-4-4 4-4" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/><path d="M21 13v2a3 3 0 01-3 3H3" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/></svg>',
    stopAfter: '<svg viewBox="0 0 24 24"><rect x="7" y="7" width="10" height="10" rx="2"/><path d="M4 12h1.5M18.5 12H20" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/></svg>',
    fullscreen: '<svg viewBox="0 0 24 24"><path d="M5 9V5h4M15 5h4v4M19 15v4h-4M9 19H5v-4" stroke="currentColor" stroke-width="2.2" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  };
  rewind.innerHTML = icon.rewind;
  forward.innerHTML = icon.forward;
  fullscreen.innerHTML = icon.fullscreen;
  function formatTime(value) {
    if (!Number.isFinite(value) || value < 0) return '00:00';
    const total = Math.floor(value);
    const hours = Math.floor(total / 3600);
    const minutes = Math.floor((total % 3600) / 60);
    const seconds = total % 60;
    const pad = (n) => String(n).padStart(2, '0');
    return hours > 0 ? hours + ':' + pad(minutes) + ':' + pad(seconds) : pad(minutes) + ':' + pad(seconds);
  }
  function setRangeFill(input, ratio) {
    const value = Math.max(0, Math.min(100, ratio * 100));
    input.style.setProperty('--value', value + '%');
  }
  function clearHideTimer() {
    if (hideTimer) window.clearTimeout(hideTimer);
    hideTimer = 0;
  }
  function scheduleHide() {
    clearHideTimer();
    if (media.paused || dragging || volumeActive) return;
    hideTimer = window.setTimeout(() => {
      if (!media.paused && !dragging && !volumeActive) {
        shell.classList.remove('controls-visible');
        shell.classList.remove('volume-open');
      }
    }, AUTO_HIDE_MS);
  }
  function hideControlsAfterPointerLeave() {
    clearHideTimer();
    if (dragging || volumeActive) return;
    hideTimer = window.setTimeout(() => {
      if (!dragging && !volumeActive) {
        shell.classList.remove('controls-visible');
        shell.classList.remove('volume-open');
      }
    }, POINTER_LEAVE_HIDE_MS);
  }
  function showControls(sticky) {
    shell.classList.add('controls-visible');
    if (sticky) {
      clearHideTimer();
      return;
    }
    scheduleHide();
  }
  function updatePlayState() {
    play.innerHTML = media.paused ? icon.play : icon.pause;
    play.setAttribute('aria-label', media.paused ? 'Play' : 'Pause');
    play.setAttribute('title', media.paused ? 'Play' : 'Pause');
    if (media.paused || media.ended) showControls(true); else scheduleHide();
  }
  function updateTime() {
    const dur = Number.isFinite(media.duration) ? media.duration : 0;
    const cur = Number.isFinite(media.currentTime) ? media.currentTime : 0;
    current.textContent = formatTime(cur);
    duration.textContent = formatTime(dur);
    const ratio = dur > 0 ? cur / dur : 0;
    progress.value = String(Math.round(ratio * 1000));
    setRangeFill(progress, ratio);
  }
  function updateVolume() {
    const muted = media.muted || media.volume <= 0;
    mute.innerHTML = muted ? icon.mute : icon.volume;
    mute.setAttribute('aria-label', muted ? 'Unmute' : 'Mute');
    mute.setAttribute('title', muted ? 'Unmute' : 'Mute');
    volume.value = String(media.muted ? 0 : media.volume);
    setRangeFill(volume, media.muted ? 0 : media.volume);
  }
  function updatePlayMode() {
    media.loop = loopPlayback;
    playMode.innerHTML = loopPlayback ? icon.loop : icon.stopAfter;
    playMode.classList.toggle('is-active', loopPlayback);
    playMode.setAttribute('aria-label', loopPlayback ? 'Loop playback' : 'Stop after playback');
    playMode.setAttribute('title', loopPlayback ? 'Loop playback' : 'Stop after playback');
  }
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
  function seekBy(delta) {
    const dur = Number.isFinite(media.duration) ? media.duration : 0;
    const next = Math.max(0, Math.min(dur || Number.MAX_SAFE_INTEGER, media.currentTime + delta));
    media.currentTime = next;
    updateTime();
    showControls();
  }
  function setVolumeActive(active) {
    volumeActive = active;
    shell.classList.toggle('volume-open', active);
    if (active) showControls(true); else if (pointerInsideShell) scheduleHide(); else hideControlsAfterPointerLeave();
  }
  function beginProgressDrag(event) {
    dragging = true;
    progress.setPointerCapture?.(event.pointerId);
    showControls(true);
  }
  function endProgressDrag(event) {
    if (!dragging) return;
    dragging = false;
    progress.releasePointerCapture?.(event.pointerId);
    if (pointerInsideShell) showControls(false); else hideControlsAfterPointerLeave();
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
    loopPlayback = !loopPlayback;
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
                math.max(_kHeaderEstimate, _measuredHeaderHeight ?? 0) +
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
    if (isVideo) _scheduleHeaderHeightSync();
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
          child: Dialog(
            insetPadding: const EdgeInsets.all(_kInsetPadding),
            constraints: BoxConstraints(
              minWidth: metrics.dialogWidth,
              maxWidth: metrics.dialogWidth,
              maxHeight: metrics.maxDialogHeight,
            ),
            backgroundColor: isVideo ? colorScheme.surface : Colors.transparent,
            elevation: isVideo ? null : 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            clipBehavior: Clip.antiAlias,
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
    return AnimatedSize(
      duration: cardMotionDurationFor(context, expanding: true),
      curve: kCardMotionCurve,
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
                key: _headerKey,
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.videocam_outlined,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
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
                        tooltip: _localizedText(
                          context,
                          zh: '使用系统播放器打开',
                          en: 'Open with System Player',
                        ),
                        onPressed: () => _openInSystemPlayer(context),
                      ),
                    ),
                    const SizedBox(width: 4),
                    MicroPressFeedback(
                      child: IconButton(
                        icon: Icon(
                          Icons.content_copy_outlined,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        tooltip: _localizedText(
                          context,
                          zh: '复制媒体',
                          en: 'Copy Media',
                        ),
                        onPressed: _isCopyingMedia
                            ? null
                            : () => _copyMediaToClipboard(context),
                      ),
                    ),
                    const SizedBox(width: 4),
                    MicroPressFeedback(
                      child: IconButton(
                        icon: Icon(
                          Icons.fullscreen_rounded,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        tooltip: _localizedText(
                          context,
                          zh: '全屏沉浸播放',
                          en: 'Fullscreen playback',
                        ),
                        onPressed: () => _enterFullscreen(context),
                      ),
                    ),
                    const SizedBox(width: 4),
                    MicroPressFeedback(
                      child: IconButton(
                        icon: Icon(
                          Icons.download_rounded,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        tooltip: _localizedText(
                          context,
                          zh: '保存到本地',
                          en: 'Save to disk',
                        ),
                        onPressed: () => _saveMediaAs(context),
                      ),
                    ),
                    const SizedBox(width: 4),
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
                  borderRadius: BorderRadius.circular(12),
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
    final audioMotionDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : _playerMotionSettings.duration;
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
            tooltip: _localizedText(
              context,
              zh: '使用系统播放器打开',
              en: 'Open with System Player',
            ),
            onPressed: () => _openInSystemPlayer(context),
          ),
          const SizedBox(width: 10),
          _AudioOverlayIconButton(
            icon: Icons.content_copy_outlined,
            tooltip: _localizedText(context, zh: '复制媒体', en: 'Copy Media'),
            onPressed: _isCopyingMedia
                ? null
                : () => _copyMediaToClipboard(context),
          ),
          const SizedBox(width: 10),
          _AudioOverlayIconButton(
            icon: Icons.download_rounded,
            tooltip: _localizedText(context, zh: '保存到本地', en: 'Save to disk'),
            onPressed: () => _saveMediaAs(context),
          ),
          const SizedBox(width: 10),
          _AudioOverlayIconButton(
            icon: Icons.close_rounded,
            tooltip: _localizedText(context, zh: '关闭', en: 'Close'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  void _scheduleHeaderHeightSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final renderObject = _headerKey.currentContext?.findRenderObject();
      if (renderObject is! RenderBox) return;
      final height = renderObject.size.height;
      if (height <= 0) return;
      final previous = _measuredHeaderHeight;
      if (previous != null && (previous - height).abs() < 0.5) return;
      setState(() => _measuredHeaderHeight = height);
    });
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
      await Clipboard.setData(
        ClipboardData(text: widget.source.uri.toString()),
      ).timeout(_mediaClipboardOperationTimeout);
      if (!context.mounted) return;
      _showMediaClipboardSnack(
        context,
        zh: '已复制媒体地址。',
        en: 'Copied media URL.',
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
    // Capture the navigator before the async pause so we don't reference
    // a possibly-stale BuildContext after the await.
    final navigator = Navigator.of(context, rootNavigator: true);
    SettingsController? settingsController;
    try {
      settingsController = context.read<SettingsController>();
    } catch (_) {
      settingsController = null;
    }
    try {
      // Pause the underlying preview before we hand control to the
      // fullscreen route so the user never hears two audio tracks at once.
      try {
        await controller.runJavaScript(
          'try{if(window.media){window.media.pause();}}catch(_){}',
        );
      } catch (error, stack) {
        silentLog(
          'home_message_bubble',
          'media preview: pause-on-fullscreen failed',
          error,
          stack,
        );
      }
      if (!mounted) return;
      DialogAnimationSettings settings;
      try {
        settings =
            settingsController?.dialogAnimationSettings ??
            DialogAnimationSettings.defaults;
      } catch (_) {
        settings = DialogAnimationSettings.defaults;
      }
      final returnedTime = await navigator.push<double>(
        PageRouteBuilder<double>(
          fullscreenDialog: true,
          transitionDuration: settings.duration,
          reverseTransitionDuration: settings.duration * 0.85,
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
      );
      if (!mounted) return;
      if (returnedTime != null && returnedTime >= 0) {
        _currentTime = returnedTime;
        try {
          // Seek the preview to the same point the user left fullscreen at;
          // we deliberately do NOT auto-resume — the user can press play.
          await controller.runJavaScript(
            'try{if(window.media){window.media.currentTime=${returnedTime.toStringAsFixed(3)};}}catch(_){}',
          );
        } catch (error, stack) {
          silentLog(
            'home_message_bubble',
            'media preview: resume-from-fullscreen seek failed',
            error,
            stack,
          );
        }
      }
    } finally {
      if (!_disposed) _isEnteringFullscreen = false;
    }
  }

  Future<void> _saveMediaAs(BuildContext context) async {
    if (_isSaving) return;
    _isSaving = true;
    final messenger = ScaffoldMessenger.maybeOf(context);
    void showSnack(String zh, String en) {
      if (messenger == null) return;
      OpenHandSnackBar.hideCurrentOn(messenger);
      _showHomeSnackBarWithMessenger(
        context,
        messenger,
        SnackBar(
          content: Text(_localizedText(context, zh: zh, en: en)),
        ),
      );
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
        final source = File(filePath);
        if (!source.existsSync()) {
          throw FileSystemException('Media source file is missing.', filePath);
        }
        await source.copy(location.path);
        showSnack('已保存到：${location.path}', 'Saved to: ${location.path}');
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
        if (cachedPath != null) {
          final cachedFile = File(cachedPath);
          if (await cachedFile.exists()) {
            await cachedFile.copy(location.path);
            showSnack('已保存到：${location.path}', 'Saved to: ${location.path}');
            return;
          }
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
        showSnack('已保存到：${location.path}', 'Saved to: ${location.path}');
      } finally {
        if (identical(_saveCancel, cancel)) _saveCancel = null;
      }
    } on _MediaDownloadCancelled {
      showSnack('已取消保存。', 'Save cancelled.');
    } on TimeoutException catch (error) {
      showSnack(
        '保存超时：${error.message ?? ''}',
        'Save timed out: ${error.message ?? ''}',
      );
    } catch (error) {
      showSnack('保存失败：$error', 'Save failed: $error');
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
  final decodedPath = () {
    try {
      return Uri.decodeFull(uri.path);
    } catch (_) {
      return uri.path;
    }
  }();
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
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: colorScheme.error),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onOpenExternal,
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(
                _localizedText(context, zh: '系统播放器', en: 'System Player'),
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
  final decodedHref = () {
    try {
      return Uri.decodeFull(href);
    } catch (_) {
      return href;
    }
  }();
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
      if (kind == null || !_cachedMarkdownImageFileExists(filePath)) {
        return null;
      }
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
    if (kind != null && _cachedMarkdownImageFileExists(decodedHref)) {
      return _GeneratedMediaSource(
        kind: kind,
        uri: Uri.file(decodedHref),
        filePath: decodedHref,
      );
    }
  }
  final resolvedPath = resolveMarkdownMessageLinkPath(decodedHref, pathRoots);
  if (resolvedPath == null || resolvedPath.isDirectory) return null;
  final kind =
      _generatedMediaKindForText(resolvedPath.resolvedPath) ?? kindHint;
  if (kind == null ||
      !_cachedMarkdownImageFileExists(resolvedPath.resolvedPath)) {
    return null;
  }
  return _GeneratedMediaSource(
    kind: kind,
    uri: Uri.file(resolvedPath.resolvedPath),
    filePath: resolvedPath.resolvedPath,
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
    '.mp4' || '.m4v' => 'video/mp4',
    '.webm' => 'video/webm',
    '.mov' => 'video/quicktime',
    '.mkv' => 'video/x-matroska',
    '.mp3' => 'audio/mpeg',
    '.wav' => 'audio/wav',
    '.m4a' => 'audio/mp4',
    '.aac' => 'audio/aac',
    '.ogg' || '.opus' => 'audio/ogg',
    '.flac' => 'audio/flac',
    _ => 'application/octet-stream',
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
    resourceLabel: isVideo ? 'video' : 'audio',
    totalTimeout: isVideo
        ? _remoteVideoDownloadTimeout
        : _remoteAudioDownloadTimeout,
    maxBytes: isVideo
        ? _remoteVideoDownloadMaxBytes
        : _remoteAudioDownloadMaxBytes,
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
  String toString() => 'Media download cancelled by caller.';
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
  final List<String> evidence;
  final List<String> missing;

  static _GoalMessageViewData? fromMessage(AiSessionMessage message) {
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
    final marker = RegExp(
      r'\n\s*Goal:\s*',
      caseSensitive: false,
    ).firstMatch(trimmed);
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
    return Map<String, Object?>.from(value);
  }

  static String _readString(Object? value) {
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty || text == 'null') {
      return '';
    }
    return text;
  }

  static int? _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    return int.tryParse(_readString(value));
  }

  static double? _readDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(_readString(value));
  }

  static List<String> _readStringList(Object? value) {
    if (value is! List) {
      return const <String>[];
    }
    return value
        .map(_readString)
        .where((item) => item.isNotEmpty)
        .take(4)
        .toList(growable: false);
  }

  String chipLabel(BuildContext context) {
    final round = roundIndex == null ? '' : ' · #$roundIndex';
    return switch (kind) {
      _GoalMessageViewKind.autoFollowUp => _localizedText(
        context,
        zh: '目标自动推进',
        en: 'Goal Auto Follow-up',
      ),
      _GoalMessageViewKind.evaluationRequest =>
        _localizedText(context, zh: '目标评估请求', en: 'Goal Evaluation Request') +
            round,
      _GoalMessageViewKind.evaluationResponse =>
        _localizedText(context, zh: '目标评估响应', en: 'Goal Evaluation Response') +
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
      _GoalMessageViewKind.autoFollowUp => _localizedText(
        context,
        zh: '继续推进当前目标',
        en: 'Continue Current Goal',
      ),
      _GoalMessageViewKind.evaluationRequest => _localizedText(
        context,
        zh: '验证目标完成证据',
        en: 'Verify Goal Evidence',
      ),
      _GoalMessageViewKind.evaluationResponse =>
        data.passed == true
            ? _localizedText(context, zh: '目标证据已通过', en: 'Goal Evidence Passed')
            : _localizedText(
                context,
                zh: '目标仍需推进',
                en: 'Goal Still Needs Work',
              ),
    };
    final description = switch (data.kind) {
      _GoalMessageViewKind.autoFollowUp => _localizedText(
        context,
        zh: 'Agent Runtime 自动发送，用于在上一轮评估未通过后继续收敛目标。',
        en: 'Agent Runtime sent this automatically after evaluation required more evidence.',
      ),
      _GoalMessageViewKind.evaluationRequest => _localizedText(
        context,
        zh: '评估模型会基于当前目标和最近对话判断完成证据是否充分。',
        en: 'The evaluator checks the current goal and recent transcript for completion evidence.',
      ),
      _GoalMessageViewKind.evaluationResponse =>
        data.passed == true
            ? _localizedText(
                context,
                zh: '评估模型认为当前证据足以完成目标。',
                en: 'The evaluator found enough evidence to complete the goal.',
              )
            : _localizedText(
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
            const SizedBox(width: 8),
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
        const SizedBox(height: 8),
        Text(
          description,
          style: theme.textTheme.bodySmall?.copyWith(
            color: textColor.withValues(alpha: 0.78),
            height: 1.45,
          ),
        ),
        if ((data.objective ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          _GoalMessageField(
            label: _localizedText(context, zh: '目标', en: 'Goal'),
            value: data.objective!.trim(),
            textColor: textColor,
          ),
        ],
        if ((data.summary ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          _GoalMessageField(
            label: _localizedText(
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
          const SizedBox(height: 12),
          _GoalMessageField(
            label: _localizedText(context, zh: '下一步', en: 'Next Step'),
            value: data.followUpPrompt!.trim(),
            textColor: textColor,
          ),
        ],
        if (data.evidence.isNotEmpty) ...[
          const SizedBox(height: 12),
          _GoalMessageInlineList(
            label: _localizedText(context, zh: '证据', en: 'Evidence'),
            values: data.evidence,
            accent: OpenHandStatusColors.success,
          ),
        ],
        if (data.missing.isNotEmpty) ...[
          const SizedBox(height: 12),
          _GoalMessageInlineList(
            label: _localizedText(context, zh: '缺口', en: 'Missing'),
            values: data.missing,
            accent: theme.colorScheme.tertiary,
          ),
        ],
        if (_metricChips(context).isNotEmpty) ...[
          const SizedBox(height: 12),
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
      add(Icons.speed_rounded, '${data.tokensUsed}$budget tok');
    }
    if (data.recentMessageCount != null) {
      add(
        Icons.chat_bubble_outline_rounded,
        _localizedText(
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
        const SizedBox(height: 4),
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

class _GoalMessageInlineList extends StatelessWidget {
  const _GoalMessageInlineList({
    required this.label,
    required this.values,
    required this.accent,
  });

  final String label;
  final List<String> values;
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
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final value in values)
              _GoalMessageMetricChip(label: value, accent: accent),
          ],
        ),
      ],
    );
  }
}

class _GoalMessageMetricChip extends StatelessWidget {
  const _GoalMessageMetricChip({required this.label, this.icon, this.accent});

  static const double _fallbackMaxWidth = 520;
  static const double _viewportWidthFactor = 0.72;
  static const double _minReadableWidth = 120;
  static const int _maxLabelLines = 3;

  final String label;
  final IconData? icon;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = accent ?? theme.colorScheme.primary;
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
              borderRadius: _borderRadius999,
              border: Border.all(color: color.withValues(alpha: 0.18)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 13, color: color),
                  const SizedBox(width: 4),
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

/// Context capsules shown in the focused message action panel's second row.
/// Keeps message cards focused on message content while preserving mode, skill,
/// attachment, model, and timestamp metadata next to the selected message.
class _SelectedMessageContextRow extends StatelessWidget {
  const _SelectedMessageContextRow({
    required this.message,
    required this.attachments,
    required this.hardnessAnnotation,
    required this.textColor,
    required this.alignEnd,
    required this.showModelLabel,
    this.onSelectResponseVariant,
  });

  final AiSessionMessage message;
  final List<AiMessageAttachment> attachments;
  final _HeAnnotation? hardnessAnnotation;
  final Color textColor;
  final bool alignEnd;
  final bool showModelLabel;
  final Future<void> Function(int index)? onSelectResponseVariant;

  @override
  Widget build(BuildContext context) {
    final creationRequest = AiCreationRequest.fromMetadata(
      message.metadata[AiCreationRequest.metadataKey],
    );
    final skillMetadata = message.metadata[aiUserSkillSelectionMetadataKey];
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
      ..._GoalMessageContextCapsules.build(
        context,
        message: message,
        textColor: textColor,
      ),
      if (creationRequest.isActive)
        _CreationModeChip(request: creationRequest, textColor: textColor),
      if (_UserSkillSelectionChip.nameFromMetadata(skillMetadata).isNotEmpty)
        _UserSkillSelectionChip(metadata: skillMetadata, textColor: textColor),
      if (hardnessAnnotation != null && hardnessAnnotation!.hasAnnotations)
        ..._HardnessAnnotationContextCapsules.build(
          context,
          annotation: hardnessAnnotation!,
          textColor: textColor,
        ),
      for (final attachment in attachments)
        _AttachmentReferenceCapsule(
          attachment: attachment,
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
        label: _formatDateTime(message.createdAt),
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

class _HardnessAnnotationContextCapsules {
  const _HardnessAnnotationContextCapsules._();

  static List<Widget> build(
    BuildContext context, {
    required _HeAnnotation annotation,
    required Color textColor,
  }) {
    return <Widget>[
      if (annotation.agentRole != null)
        _MessageContextCapsule(
          icon: Icons.person_pin_rounded,
          label: _localizedText(
            context,
            zh: '角色 · ${_roleLabel(annotation, isZh: true)}${_agentSuffix(annotation)}',
            en: 'Role · ${_roleLabel(annotation, isZh: false)}${_agentSuffix(annotation)}',
          ),
          textColor: textColor,
        ),
      if (annotation.phase != null)
        _MessageContextCapsule(
          icon: _hePhaseIcons[annotation.phase] ?? Icons.timelapse_rounded,
          label: _localizedText(
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
        ? '${data.chipLabel(context)} · ${_localizedText(context, zh: '通过', en: 'Passed')}'
        : '${data.chipLabel(context)} · ${_localizedText(context, zh: '继续', en: 'Continue')}';
    return <Widget>[
      _MessageContextCapsule(
        icon: data.icon,
        label: label,
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
    final style = _messageActionChipStyle(context);
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
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    final curved = openHandBoundedCurveAnimation(
                      parent: animation,
                      curve: kCardMotionCurve,
                      reverseCurve: Curves.easeInCubic,
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
        child: Icon(icon, size: _messageActionIconSize, color: effectiveColor),
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
    final style = _messageActionChipStyle(context);
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
          leading ?? Icon(icon, size: _messageActionIconSize, color: iconColor),
      label: labelWidget,
    );
    if (onPressed != null) {
      return button;
    }
    return IgnorePointer(child: button);
  }
}

class _AttachmentReferenceCapsule extends StatelessWidget {
  const _AttachmentReferenceCapsule({
    required this.attachment,
    required this.textColor,
  });

  final AiMessageAttachment attachment;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return _MessageContextCapsule(
      icon: _iconForAttachmentKind(attachment.kind),
      label:
          '${attachment.name.trim().isNotEmpty ? attachment.name.trim() : _localizedText(context, zh: '附件', en: 'Attachment')} · ${aiFormatBytes(attachment.sizeBytes)}',
      textColor: textColor,
      maxLabelWidth: 280,
      onPressed: () {
        unawaited(_openAttachment(context, attachment));
      },
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
    final label = _localizedText(
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

/// Context capsule shown in the focused action panel when the message was
/// submitted with an explicit local-skill selection (e.g. `/caveman`).
class _UserSkillSelectionChip extends StatelessWidget {
  const _UserSkillSelectionChip({
    required this.metadata,
    required this.textColor,
  });

  final Object? metadata;
  final Color textColor;

  static String nameFromMetadata(Object? metadata) {
    if (metadata is! Map) return '';
    final map = Map<String, Object?>.from(metadata);
    return (map['name'] as String?)?.trim() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    if (metadata is! Map) return const SizedBox.shrink();
    final map = Map<String, Object?>.from(metadata as Map);
    final name = nameFromMetadata(metadata);
    if (name.isEmpty) return const SizedBox.shrink();
    final emoji = (map['emoji'] as String?)?.trim();
    final iconPath = (map['icon_path'] as String?)?.trim();
    final iconKind = (map['icon_kind'] as String?)?.trim();
    final leading = _buildLeading(emoji, iconPath, iconKind);
    final label = _localizedText(
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
          // Leading icon rendered at 14 logical px; cache at ~3x DPR.
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

/// Coordinates one-shot first-frame capture for local video files.
///
/// We render the existing `webview_flutter` stack (no new deps) inside an
/// `Offstage` host, ask the page to seek to ~0.1s, draw the first frame to
/// a 480px-wide canvas, and post the dataURL back through a JS channel.
/// The PNG is persisted next to the source video as `<video>.thumb.png` so
/// future card mounts simply read the cached file via `Image.file`.
///
/// Concurrency is intentionally capped at one capture in flight so the
/// UI never spawns multiple WKWebView platform views simultaneously,
/// which has historically caused jank/ANR on macOS. Subsequent requesters
/// queue and inherit the slot when the previous capture finishes.
class _VideoThumbnailManager {
  static final Queue<Completer<void>> _waiters = Queue<Completer<void>>();
  static int _active = 0;
  static const int _maxActive = 1;
  // Per-process retry guard: if a capture failed once we don't keep
  // re-creating WebViews for the same file in the same session.
  static final Set<String> _failed = <String>{};

  static String thumbnailPathFor(String videoPath) => '$videoPath.thumb.png';

  static bool isMarkedFailed(String videoPath) => _failed.contains(videoPath);
  static void _markFailed(String videoPath) => _failed.add(videoPath);

  static Future<void> _acquireSlot() {
    if (_active < _maxActive) {
      _active += 1;
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  static void _releaseSlot() {
    if (_active > 0) _active -= 1;
    if (_active < _maxActive && _waiters.isNotEmpty) {
      _active += 1;
      _waiters.removeFirst().complete();
    }
  }
}

/// Offstage WebView that captures a single first-frame PNG for a local
/// video file. Removes itself by calling `onResult` (which the parent
/// uses to swap the card to `Image.file`).
class _VideoThumbnailCaptureHost extends StatefulWidget {
  const _VideoThumbnailCaptureHost({
    required this.videoPath,
    required this.mimeType,
    required this.onResult,
  });

  final String videoPath;
  final String mimeType;
  final void Function(String? thumbPath) onResult;

  @override
  State<_VideoThumbnailCaptureHost> createState() =>
      _VideoThumbnailCaptureHostState();
}

class _VideoThumbnailCaptureHostState extends State<_VideoThumbnailCaptureHost>
    with WidgetsBindingObserver {
  static const Duration _thumbnailCaptureTimeout = Duration(seconds: 18);

  WebViewController? _controller;
  String? _tempHtmlPath;
  bool _slotHeld = false;
  bool _done = false;
  Timer? _watchdog;
  // 应用切到后台时 WebView/JS 通道可能被 OS 暂停，需将 watchdog 一并暂停，
  // 否则 18s 后会误判为超时并标记失败；回到前台时按完整预算重新计时。
  bool _watchdogPausedForLifecycle = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (_done) return;
    if (state != AppLifecycleState.resumed) {
      if (_watchdog != null && _watchdog!.isActive) {
        _watchdog!.cancel();
        _watchdog = null;
        _watchdogPausedForLifecycle = true;
      }
      return;
    }
    if (_watchdogPausedForLifecycle && _watchdog == null) {
      _watchdogPausedForLifecycle = false;
      _watchdog = startSafeTimer(_thumbnailCaptureTimeout, () {
        if (!_done) _finish(null);
      });
    }
  }

  Future<void> _start() async {
    await _VideoThumbnailManager._acquireSlot();
    _slotHeld = true;
    if (!mounted) {
      _finish(null);
      return;
    }
    try {
      final dir = p.dirname(widget.videoPath);
      final tempName =
          '.openhand_thumb_capture_${DateTime.now().microsecondsSinceEpoch}_${identityHashCode(this)}.html';
      final tempFile = File(p.join(dir, tempName));
      await tempFile.writeAsString(_buildCaptureHtml());
      _tempHtmlPath = tempFile.path;
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel('OpenHandThumb', onMessageReceived: _onMessage);
      if (!Platform.isMacOS) {
        controller.setBackgroundColor(Colors.transparent);
      }
      _controller = controller;
      await controller.loadFile(tempFile.path);
      if (!mounted) {
        _finish(null);
        return;
      }
      // Watchdog: if no message arrives within the budget, bail out so
      // the slot is released and the card stops trying for this session.
      _watchdog = startSafeTimer(_thumbnailCaptureTimeout, () {
        if (!_done) _finish(null);
      });
      setState(() {});
    } catch (error, stack) {
      silentLog(
        'home_message_bubble',
        'video thumbnail: setup failed',
        error,
        stack,
      );
      _finish(null);
    }
  }

  void _onMessage(JavaScriptMessage message) {
    if (_done) return;
    final value = message.message;
    if (value.startsWith('error')) {
      _finish(null);
      return;
    }
    const marker = 'base64,';
    final idx = value.indexOf(marker);
    if (idx < 0) {
      _finish(null);
      return;
    }
    final b64 = value.substring(idx + marker.length);
    Future<void>(() async {
      try {
        final bytes = base64.decode(b64);
        final outPath = _VideoThumbnailManager.thumbnailPathFor(
          widget.videoPath,
        );
        await File(outPath).writeAsBytes(bytes, flush: true);
        _finish(outPath);
      } catch (error, stack) {
        silentLog(
          'home_message_bubble',
          'video thumbnail: write failed',
          error,
          stack,
        );
        _finish(null);
      }
    });
  }

  void _finish(String? path) {
    if (_done) return;
    _done = true;
    _watchdog?.cancel();
    if (path == null) _VideoThumbnailManager._markFailed(widget.videoPath);
    final temp = _tempHtmlPath;
    if (temp != null) {
      Future<void>(() async {
        try {
          final f = File(temp);
          if (await f.exists()) await f.delete();
        } catch (error, stack) {
          silentLog(
            'home_message_bubble',
            'delete temp video thumbnail capture file',
            error,
            stack,
          );
        }
      });
    }
    if (_slotHeld) {
      _slotHeld = false;
      _VideoThumbnailManager._releaseSlot();
    }
    widget.onResult(path);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (!_done) {
      _done = true;
      _watchdog?.cancel();
      final temp = _tempHtmlPath;
      if (temp != null) {
        Future<void>(() async {
          try {
            final f = File(temp);
            if (await f.exists()) await f.delete();
          } catch (error, stack) {
            silentLog(
              'home_message_bubble',
              'delete temp video thumbnail capture file',
              error,
              stack,
            );
          }
        });
      }
      if (_slotHeld) {
        _slotHeld = false;
        _VideoThumbnailManager._releaseSlot();
      }
    }
    super.dispose();
  }

  String _buildCaptureHtml() {
    final src = const HtmlEscape(
      HtmlEscapeMode.attribute,
    ).convert(Uri.file(widget.videoPath).toString());
    final mime = const HtmlEscape(
      HtmlEscapeMode.attribute,
    ).convert(widget.mimeType);
    // We deliberately omit `crossorigin="anonymous"` — file:// requests in
    // WKWebView cannot honour it and the canvas would taint, making
    // toDataURL throw SecurityError. We also force play()→pause() to make
    // sure the decoder actually produces frames before drawImage runs;
    // muted preload="auto" alone is not enough on macOS WKWebView.
    return '''
<!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;background:#000;width:100%;height:100%;overflow:hidden}video{position:fixed;left:0;top:0;width:32px;height:32px;opacity:0.01;pointer-events:none}canvas{display:none}</style></head><body>
<video id="v" muted autoplay playsinline preload="auto" disableRemotePlayback><source src="$src" type="$mime"></video>
<canvas id="c"></canvas>
<script>(function(){
var v=document.getElementById('v');var c=document.getElementById('c');
var captured=false;
function post(m){try{if(window.OpenHandThumb&&window.OpenHandThumb.postMessage){window.OpenHandThumb.postMessage(String(m));}}catch(_){}}
function tryCapture(reason){
  if(captured)return false;
  var w=v.videoWidth, h=v.videoHeight;
  if(!w||!h)return false;
  try{
    var tw=Math.min(480,w);
    var th=Math.max(1,Math.round(h*(tw/w)));
    c.width=tw;c.height=th;
    var ctx=c.getContext('2d');
    ctx.drawImage(v,0,0,tw,th);
    var url=c.toDataURL('image/png');
    if(!url||url.length<64)return false;
    captured=true;
    post(url);
    return true;
  }catch(e){
    // Swallow transient drawImage failures so the polling loop or a
    // later seek event can still succeed without prematurely failing
    // the capture on the Dart side.
    return false;
  }
}
function safeSeek(t){try{v.currentTime=t;}catch(_){}}
function armRVFC(){
  if(captured)return;
  if(typeof v.requestVideoFrameCallback==='function'){
    try{v.requestVideoFrameCallback(function(){tryCapture('rvfc');if(!captured){v.requestVideoFrameCallback(function(){tryCapture('rvfc2');});}});}catch(_){}}
}
v.addEventListener('loadedmetadata',function(){
  // Kick off decode; some macOS WKWebView builds do not produce frames
  // until play() is called even with preload=auto.
  armRVFC();
  var p;
  try{v.muted=true;v.volume=0;p=v.play();}catch(_){p=null;}
  if(p&&p.then){
    p.then(function(){
      // Let the decoder produce 1-2 frames, then pause and snap.
      setTimeout(function(){
        tryCapture('after_play');
        try{v.pause();}catch(_){};
        safeSeek(Math.min(0.05,(v.duration||0)));
      },180);
    }).catch(function(){
      // Autoplay blocked or play() rejected; seek manually and rely on
      // the seeked / canplay / poll fallbacks.
      safeSeek(Math.min(0.05,(v.duration||0)));
    });
  }else{
    safeSeek(Math.min(0.05,(v.duration||0)));
  }
});
v.addEventListener('seeked',function(){tryCapture('seeked');});
v.addEventListener('canplay',function(){armRVFC();tryCapture('canplay');});
v.addEventListener('canplaythrough',function(){tryCapture('canplaythrough');});
// Repeated polling fallback in case neither seeked nor canplay produces a
// painted frame (rare but seen on some H.265 sources under WKWebView).
var attempts=0;
var poll=setInterval(function(){
  attempts++;
  if(captured||attempts>40){clearInterval(poll);return;}
  tryCapture('poll'+attempts);
},250);
v.addEventListener('error',function(){post('error:video_load');});
setTimeout(function(){if(!captured){clearInterval(poll);post('error:timeout');}},14000);
})();</script>
</body></html>
''';
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;
    if (ctrl == null) return const SizedBox.shrink();
    // The host MUST have a non-zero, non-occluded footprint so the
    // platform view is actually painted by the compositor — without that
    // WKWebView on macOS will not run the video decoder, and the canvas
    // capture stays empty (the symptom users see as a permanently black
    // thumbnail). 32×32 at opacity 0.01 is invisible in practice yet
    // keeps the platform view "live" until the first frame is grabbed.
    return SizedBox(
      width: 32,
      height: 32,
      child: IgnorePointer(
        child: Opacity(opacity: 0.01, child: WebViewWidget(controller: ctrl)),
      ),
    );
  }
}

/// Black-screen fullscreen route for immersive video playback. Reuses the
/// `loadFile` trick from `_MediaPreviewDialog` so WKWebView can grant
/// `file://` read access to the parent directory.
///
/// Pops with the most recent `currentTime` (in seconds) so the calling
/// preview dialog can resync its scrub position when the user returns.
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
  // Focus node owns the keyboard route so ESC exits fullscreen without
  // requiring the user to first click into the WebView surface.
  final FocusNode _focusNode = FocusNode(debugLabel: 'fullscreen-video');

  @override
  void initState() {
    super.initState();
    _currentTime = widget.initialTime;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('OpenHandFs', onMessageReceived: _onJsMessage)
      ..setNavigationDelegate(
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
    if (!Platform.isMacOS) {
      _controller.setBackgroundColor(Colors.black);
    }
    _bootstrap();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _onJsMessage(JavaScriptMessage message) {
    final value = message.message.trim();
    if (value == 'close') {
      _exit();
    } else if (value.startsWith('time:')) {
      final parsed = double.tryParse(value.substring(5));
      if (parsed != null && parsed >= 0) {
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
    final localPath = widget.source.filePath;
    if (localPath != null && File(localPath).existsSync()) {
      try {
        final dir = p.dirname(localPath);
        final tempName =
            '.openhand_fullscreen_${DateTime.now().microsecondsSinceEpoch}_${identityHashCode(this)}.html';
        final tempFile = File(p.join(dir, tempName));
        await tempFile.writeAsString(_buildHtml(localOverride: localPath));
        if (!mounted) {
          await tempFile.delete().catchError((_) => tempFile);
          return;
        }
        _tempHtmlPath = tempFile.path;
        await _controller.loadFile(tempFile.path);
        return;
      } catch (error, stack) {
        silentLog(
          'home_message_bubble',
          'fullscreen video: loadFile fallback failed',
          error,
          stack,
        );
      }
    }
    if (!mounted) return;
    await _controller.loadHtmlString(_buildHtml());
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
:root{--oh-motion-duration:${durationMs}ms;--oh-motion-curve:$motionCurve;--oh-control-bg:rgba(18,18,20,.76);--oh-control-border:rgba(255,255,255,.14);--oh-track:rgba(255,255,255,.22);--oh-track-fill:#fff}
html,body{margin:0;background:#000;width:100%;height:100%;overflow:hidden;color:#fff;font:13px/1.4 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
button,input{font:inherit}
.media-shell{position:relative;width:100%;height:100%;display:flex;align-items:center;justify-content:center;background:#000;user-select:none;overflow:hidden;isolation:isolate}
video{width:100vw;height:100vh;background:#000;object-fit:contain}
.scrim{position:absolute;inset:auto 0 0;height:38%;background:linear-gradient(to top,rgba(0,0,0,.52),transparent);opacity:1;transition:opacity var(--oh-motion-duration) var(--oh-motion-curve);pointer-events:none}
.media-shell:not(.controls-visible) .scrim{opacity:0}
.control-bar{position:absolute;left:50%;bottom:18px;z-index:5;display:flex;align-items:center;gap:10px;width:calc(100% - 48px);max-width:900px;min-height:50px;padding:8px 14px;box-sizing:border-box;border:1px solid var(--oh-control-border);border-radius:999px;background:var(--oh-control-bg);box-shadow:0 18px 42px rgba(0,0,0,.36);backdrop-filter:blur(22px) saturate(1.24);-webkit-backdrop-filter:blur(22px) saturate(1.24);transform-origin:bottom center;transform:translateX(-50%) translateY(0) scale(1);opacity:1;filter:blur(0);transition:opacity var(--oh-motion-duration) var(--oh-motion-curve),transform var(--oh-motion-duration) var(--oh-motion-curve),filter var(--oh-motion-duration) var(--oh-motion-curve)}
.media-shell:not(.controls-visible) .control-bar{opacity:0;pointer-events:none;transform:translateX(-50%) translateY(26px) scale(.94);filter:blur(4px)}
.control-button{width:30px;height:30px;min-width:30px;border:0;border-radius:999px;display:inline-flex;align-items:center;justify-content:center;background:transparent;color:#fff;cursor:pointer;transition:transform 160ms var(--oh-motion-curve),background-color 160ms ease-out,opacity 160ms ease-out}
.control-button:hover,.control-button:focus-visible{background:rgba(255,255,255,.14);transform:translateY(-1px) scale(1.06);outline:none}
.control-button.is-active{background:rgba(255,255,255,.20)}
.control-button:active{transform:scale(.92)}
.control-button svg{width:18px;height:18px;display:block;fill:currentColor}
.seek-button svg{width:21px;height:21px}
.time{min-width:48px;text-align:center;font-weight:700;font-variant-numeric:tabular-nums;color:rgba(255,255,255,.92);white-space:nowrap}
.progress{flex:1 1 220px;min-width:96px}
.volume-group{position:relative;display:inline-flex;align-items:center;justify-content:center}
.volume-popover{position:absolute;left:50%;bottom:40px;width:46px;height:136px;display:flex;align-items:center;justify-content:center;border:1px solid var(--oh-control-border);border-radius:999px;background:var(--oh-control-bg);box-shadow:0 18px 42px rgba(0,0,0,.34);backdrop-filter:blur(22px) saturate(1.24);-webkit-backdrop-filter:blur(22px) saturate(1.24);transform-origin:bottom center;transform:translateX(-50%) translateY(10px) scale(.88);opacity:0;pointer-events:none;filter:blur(3px);transition:opacity var(--oh-motion-duration) var(--oh-motion-curve),transform var(--oh-motion-duration) var(--oh-motion-curve),filter var(--oh-motion-duration) var(--oh-motion-curve)}
.volume-open .volume-popover,.volume-group:focus-within .volume-popover{opacity:1;pointer-events:auto;transform:translateX(-50%) translateY(0) scale(1);filter:blur(0)}
.volume.vertical{position:absolute;left:50%;top:50%;width:112px;transform:translate(-50%,-50%) rotate(-90deg);transform-origin:center}
input[type=range]{height:22px;margin:0;accent-color:#fff;cursor:pointer}
input[type=range]::-webkit-slider-runnable-track{height:7px;border-radius:999px;background:linear-gradient(to right,var(--oh-track-fill) 0%,var(--oh-track-fill) var(--value,0%),var(--oh-track) var(--value,0%),var(--oh-track) 100%)}
input[type=range]::-webkit-slider-thumb{-webkit-appearance:none;width:18px;height:18px;margin-top:-5.5px;border-radius:50%;background:#fff;box-shadow:0 2px 10px rgba(0,0,0,.35);transition:transform 160ms var(--oh-motion-curve)}
input[type=range]:hover::-webkit-slider-thumb,input[type=range]:focus-visible::-webkit-slider-thumb{transform:scale(1.12)}
.no-motion *{transition-duration:0ms!important;animation:none!important}
@media (max-width:720px){.control-bar{gap:6px;padding:7px 10px;width:calc(100% - 28px)}.progress{min-width:72px}.time{min-width:42px}.volume-popover{height:116px}.volume.vertical{width:94px}}
@media (max-width:460px){.seek-button{display:none}.control-bar{width:calc(100% - 18px)}.time{min-width:40px}.progress{min-width:64px}.volume-popover{height:104px}.volume.vertical{width:84px}}
</style></head><body>
<div id="shell" class="media-shell controls-visible$motionClass" tabindex="0">
  <video id="media" autoplay playsinline preload="auto" disableRemotePlayback><source src="$src" type="$mime"></video>
  <div class="scrim"></div>
  <div class="control-bar" id="controls">
    <button id="rewind" class="control-button seek-button" type="button" aria-label="Back 15 seconds" title="Back 15 seconds"></button>
    <button id="play" class="control-button" type="button" aria-label="Play" title="Play"></button>
    <button id="forward" class="control-button seek-button" type="button" aria-label="Forward 15 seconds" title="Forward 15 seconds"></button>
    <span id="current" class="time">00:00</span>
    <input id="progress" class="progress" type="range" min="0" max="1000" step="1" value="0" aria-label="Progress">
    <span id="duration" class="time">00:00</span>
    <div class="volume-group" id="volumeGroup">
      <button id="mute" class="control-button" type="button" aria-label="Mute" title="Mute"></button>
      <div class="volume-popover">
        <input id="volume" class="volume vertical" type="range" min="0" max="1" step="0.01" value="1" aria-label="Volume" aria-orientation="vertical">
      </div>
    </div>
    <button id="playMode" class="control-button" type="button" aria-label="Stop after playback" title="Stop after playback"></button>
    <button id="exit" class="control-button" type="button" aria-label="Exit fullscreen" title="Exit fullscreen"></button>
  </div>
</div>
<script>(function(){
const AUTO_HIDE_MS=$_kMediaPreviewControlAutoHideMs;
const POINTER_LEAVE_HIDE_MS=$_kMediaPreviewPointerLeaveHideMs;
const shell=document.getElementById('shell');
const v=document.getElementById('media');
const play=document.getElementById('play');
const rewind=document.getElementById('rewind');
const forward=document.getElementById('forward');
const progress=document.getElementById('progress');
const current=document.getElementById('current');
const duration=document.getElementById('duration');
const volume=document.getElementById('volume');
const mute=document.getElementById('mute');
const volumeGroup=document.getElementById('volumeGroup');
const playMode=document.getElementById('playMode');
const exit=document.getElementById('exit');
window.media=v;
function post(m){try{if(window.OpenHandFs&&window.OpenHandFs.postMessage){window.OpenHandFs.postMessage(String(m));}}catch(_){}}
if(!v){post('error:missing_video');return;}
let hideTimer=0;
let dragging=false;
let volumeActive=false;
let pointerInsideShell=true;
let playbackMode='stop';
const icon={
play:'<svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>',
pause:'<svg viewBox="0 0 24 24"><path d="M6 5h4v14H6zM14 5h4v14h-4z"/></svg>',
mute:'<svg viewBox="0 0 24 24"><path d="M4 9v6h4l5 4V5L8 9H4z"/><path d="M18 9l4 4m0-4-4 4" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/></svg>',
volume:'<svg viewBox="0 0 24 24"><path d="M4 9v6h4l5 4V5L8 9H4z"/><path d="M16 8.5a5 5 0 010 7M18.5 6a8 8 0 010 12" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/></svg>',
rewind:'<svg viewBox="0 0 24 24"><path d="M11 7l-6 5 6 5V7zm8 0l-6 5 6 5V7z"/><text x="12" y="21" text-anchor="middle" font-size="7" fill="currentColor">15</text></svg>',
forward:'<svg viewBox="0 0 24 24"><path d="M13 7l6 5-6 5V7zM5 7l6 5-6 5V7z"/><text x="12" y="21" text-anchor="middle" font-size="7" fill="currentColor">15</text></svg>',
loop:'<svg viewBox="0 0 24 24"><path d="M17 2l4 4-4 4" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/><path d="M3 11V9a3 3 0 013-3h15" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/><path d="M7 22l-4-4 4-4" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/><path d="M21 13v2a3 3 0 01-3 3H3" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/></svg>',
stopAfter:'<svg viewBox="0 0 24 24"><rect x="7" y="7" width="10" height="10" rx="2"/><path d="M4 12h1.5M18.5 12H20" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/></svg>',
exit:'<svg viewBox="0 0 24 24"><path d="M9 5H5v4M15 5h4v4M19 15v4h-4M5 15v4h4" stroke="currentColor" stroke-width="2.2" fill="none" stroke-linecap="round" stroke-linejoin="round"/><path d="M9 9l-5-5M15 9l5-5M15 15l5 5M9 15l-5 5" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/></svg>'
};
rewind.innerHTML=icon.rewind;
forward.innerHTML=icon.forward;
exit.innerHTML=icon.exit;
function fmt(value){if(!Number.isFinite(value)||value<0)return'00:00';const total=Math.floor(value);const h=Math.floor(total/3600);const m=Math.floor((total%3600)/60);const s=total%60;const pad=(n)=>String(n).padStart(2,'0');return h>0?h+':'+pad(m)+':'+pad(s):pad(m)+':'+pad(s);}
function setFill(input,ratio){const value=Math.max(0,Math.min(100,ratio*100));input.style.setProperty('--value',value+'%');}
function clearHideTimer(){if(hideTimer)window.clearTimeout(hideTimer);hideTimer=0;}
function scheduleHide(){clearHideTimer();if(v.paused||dragging||volumeActive)return;hideTimer=window.setTimeout(()=>{if(!v.paused&&!dragging&&!volumeActive){shell.classList.remove('controls-visible');shell.classList.remove('volume-open');}},AUTO_HIDE_MS);}
function hideControlsAfterPointerLeave(){clearHideTimer();if(dragging||volumeActive)return;hideTimer=window.setTimeout(()=>{if(!dragging&&!volumeActive){shell.classList.remove('controls-visible');shell.classList.remove('volume-open');}},POINTER_LEAVE_HIDE_MS);}
function showControls(sticky){shell.classList.add('controls-visible');if(sticky){clearHideTimer();return;}scheduleHide();}
function updatePlay(){play.innerHTML=v.paused?icon.play:icon.pause;play.setAttribute('aria-label',v.paused?'Play':'Pause');play.setAttribute('title',v.paused?'Play':'Pause');if(v.paused||v.ended)showControls(true);else scheduleHide();}
function updateTime(){const dur=Number.isFinite(v.duration)?v.duration:0;const cur=Number.isFinite(v.currentTime)?v.currentTime:0;current.textContent=fmt(cur);duration.textContent=fmt(dur);const ratio=dur>0?cur/dur:0;progress.value=String(Math.round(ratio*1000));setFill(progress,ratio);}
function updateVolume(){const muted=v.muted||v.volume<=0;mute.innerHTML=muted?icon.mute:icon.volume;mute.setAttribute('aria-label',muted?'Unmute':'Mute');mute.setAttribute('title',muted?'Unmute':'Mute');volume.value=String(v.muted?0:v.volume);setFill(volume,v.muted?0:v.volume);}
function updatePlayMode(){const looping=playbackMode==='loop';v.loop=looping;playMode.innerHTML=looping?icon.loop:icon.stopAfter;playMode.classList.toggle('is-active',looping);playMode.setAttribute('aria-label',looping?'Loop playback':'Stop after playback');playMode.setAttribute('title',looping?'Loop playback':'Stop after playback');}
function setVolumeActive(active){volumeActive=active;shell.classList.toggle('volume-open',active);if(active)showControls(true);else if(pointerInsideShell)scheduleHide();else hideControlsAfterPointerLeave();}
function seekBy(delta){const dur=Number.isFinite(v.duration)?v.duration:0;v.currentTime=Math.max(0,Math.min(dur||Number.MAX_SAFE_INTEGER,v.currentTime+delta));updateTime();showControls(false);}
function beginDrag(event){dragging=true;progress.setPointerCapture?.(event.pointerId);showControls(true);}
function endDrag(event){if(!dragging)return;dragging=false;progress.releasePointerCapture?.(event.pointerId);if(pointerInsideShell)showControls(false);else hideControlsAfterPointerLeave();}
let resumed=false;
function resume(){if(resumed)return;resumed=true;try{var t=parseFloat('$initial');if(!isNaN(t)&&t>0&&t<(v.duration||Infinity)){v.currentTime=t;}}catch(_){}updateTime();var p=v.play();if(p&&p.catch)p.catch(function(){updatePlay();});}
v.addEventListener('loadedmetadata',resume);
v.addEventListener('canplay',resume);
v.addEventListener('error',function(){post('error:video_load');});
var lastSent=-1;
function sendTime(){var t=v.currentTime||0;if(Math.abs(t-lastSent)>=0.2){lastSent=t;post('time:'+t.toFixed(3));}}
play.addEventListener('click',()=>{if(v.paused){v.play().catch(()=>showControls(true));}else{v.pause();}showControls(true);});
rewind.addEventListener('click',()=>seekBy(-15));
forward.addEventListener('click',()=>seekBy(15));
progress.addEventListener('pointerdown',beginDrag);
progress.addEventListener('pointerup',endDrag);
progress.addEventListener('pointercancel',endDrag);
progress.addEventListener('input',()=>{const dur=Number.isFinite(v.duration)?v.duration:0;if(dur>0)v.currentTime=(Number(progress.value)/1000)*dur;updateTime();showControls(true);});
volumeGroup.addEventListener('pointerenter',()=>setVolumeActive(true));
volumeGroup.addEventListener('pointerleave',()=>setVolumeActive(false));
volumeGroup.addEventListener('pointerdown',()=>setVolumeActive(true));
volumeGroup.addEventListener('pointerup',()=>setVolumeActive(false));
volumeGroup.addEventListener('pointercancel',()=>setVolumeActive(false));
volumeGroup.addEventListener('focusin',()=>setVolumeActive(true));
volumeGroup.addEventListener('focusout',(event)=>{if(!event.relatedTarget||!volumeGroup.contains(event.relatedTarget)){setVolumeActive(false);}});
volume.addEventListener('input',()=>{const next=Math.max(0,Math.min(1,Number(volume.value)));v.volume=Number.isFinite(next)?next:1;v.muted=v.volume<=0;updateVolume();setVolumeActive(true);});
mute.addEventListener('click',()=>{v.muted=!v.muted;if(!v.muted&&v.volume<=0)v.volume=0.6;updateVolume();setVolumeActive(true);});
playMode.addEventListener('click',()=>{playbackMode=playbackMode==='loop'?'stop':'loop';updatePlayMode();showControls(true);});
exit.addEventListener('click',()=>post('close'));
shell.addEventListener('pointerenter',()=>{pointerInsideShell=true;});
shell.addEventListener('pointermove',()=>{pointerInsideShell=true;showControls(false);});
shell.addEventListener('pointerdown',()=>showControls(false));
shell.addEventListener('pointerleave',()=>{pointerInsideShell=false;hideControlsAfterPointerLeave();});
shell.addEventListener('keydown',(event)=>{if(event.defaultPrevented)return;if(event.key===' '||event.key==='Enter'){event.preventDefault();play.click();}else if(event.key==='ArrowLeft'){event.preventDefault();seekBy(-5);}else if(event.key==='ArrowRight'){event.preventDefault();seekBy(5);}else if(event.key.toLowerCase()==='m'){event.preventDefault();mute.click();}});
document.addEventListener('keydown',(event)=>{if(event.defaultPrevented||event.key!=='Escape')return;event.preventDefault();post('close');},true);
v.addEventListener('timeupdate',sendTime);
v.addEventListener('timeupdate',updateTime);
v.addEventListener('pause',sendTime);
v.addEventListener('pause',updatePlay);
v.addEventListener('play',updatePlay);
v.addEventListener('seeked',sendTime);
v.addEventListener('seeked',updateTime);
v.addEventListener('ended',()=>{sendTime();updatePlay();showControls(true);});
v.addEventListener('volumechange',updateVolume);
window.addEventListener('beforeunload',clearHideTimer);
updatePlayMode();
updatePlay();
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
    // Stop playback synchronously-as-possible so the user does not hear
    // residual audio while the route pops. We fire the JS pause first,
    // then pop — the controller is still attached at this point.
    unawaited(_stopPlaybackBestEffort());
    Navigator.of(context).maybePop<double>(_currentTime);
  }

  Future<void> _togglePlayPause() async {
    try {
      await _controller.runJavaScript(
        "try{var m=document.getElementById('media');if(m){if(m.paused){var p=m.play();if(p&&p.catch)p.catch(function(){});}else{m.pause();}}}catch(_){}",
      );
    } catch (error, stack) {
      silentLog(
        'home_message_bubble',
        'fullscreen video: toggle play/pause failed',
        error,
        stack,
      );
    }
  }

  Future<void> _stopPlaybackBestEffort() async {
    try {
      // Pause + clear the source so WKWebView releases the decoder. Just
      // calling pause() sometimes leaves a pending audio frame queued on
      // macOS; removing the source forces a full teardown.
      await _controller.runJavaScript(
        "try{var m=document.getElementById('media');if(m){try{m.pause();}catch(_){};try{m.muted=true;}catch(_){};try{m.removeAttribute('src');}catch(_){};try{while(m.firstChild)m.removeChild(m.firstChild);}catch(_){};try{m.load();}catch(_){};}}catch(_){}",
      );
    } catch (error, stack) {
      silentLog(
        'home_message_bubble',
        'fullscreen video: stop playback failed',
        error,
        stack,
      );
    }
  }

  @override
  void dispose() {
    // Last-chance teardown in case the route was popped via a path that
    // bypassed `_exit` (e.g. a system gesture or programmatic Navigator
    // call). `runJavaScript` is fire-and-forget here; the controller may
    // already be in the process of disposal but this still helps with
    // the WKWebView audio-leak window observed on macOS.
    unawaited(_stopPlaybackBestEffort());
    _focusNode.dispose();
    final tmp = _tempHtmlPath;
    if (tmp != null) {
      Future<void>(() async {
        try {
          final f = File(tmp);
          if (await f.exists()) await f.delete();
        } catch (error, stack) {
          silentLog(
            'home_message_bubble',
            'fullscreen video: temp html cleanup failed',
            error,
            stack,
          );
        }
      });
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
                      tooltip: _localizedText(
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

/// Slim, glassy chrome button used for the fullscreen back affordance.
/// Designed to read as part of the player UI rather than a standalone
/// material button — soft white fill at low alpha + rounded square with a
/// thin border, matching the floating control aesthetic of native video
/// players.
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

class _FullscreenChromeButtonState extends State<_FullscreenChromeButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bg = _hover
        ? Colors.white.withValues(alpha: 0.22)
        : Colors.white.withValues(alpha: 0.12);
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          if (_hover) return;
          _hover = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
        },
        onExit: (_) {
          if (!_hover) return;
          _hover = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
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

/// Intent fired by the spacebar shortcut on the media preview / fullscreen
/// routes. Toggles play/pause on the embedded `<video>`/`<audio>` element.
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
    duration: const Duration(milliseconds: 950),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!TickerMode.valuesOf(context).enabled ||
        MediaQuery.disableAnimationsOf(context)) {
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
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
