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
    required this.isSelected,
    required this.isScrollHighlighted,
    required this.onSelect,
    required this.onDeselect,
    required this.onCopy,
    required this.onDelete,
    this.onDeleteFromHere,
    this.onEdit,
    this.onAudit,
  });

  final AiSessionMessage message;
  final String sessionTitle;
  final AiSessionEnvironment sessionEnvironment;
  final bool showReasoningSweep;
  final bool trackLayoutChanges;
  final VoidCallback onLayoutChanged;
  final bool isSelected;
  final bool isScrollHighlighted;
  final VoidCallback onSelect;
  final VoidCallback onDeselect;
  final Future<void> Function() onCopy;
  final Future<void> Function() onDelete;
  final Future<void> Function()? onDeleteFromHere;
  final Future<void> Function()? onEdit;
  final VoidCallback? onAudit;

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  bool _compressionExpanded = false;
  bool? _reasoningExpandedOverride;
  bool _showRawContent = false;

  // 2026-04-27: 启用文本 selectable 后外层 GestureDetector 的 onTap
  // 会被子节点的文本选择手势抢占，导致点击气泡后
  // 接不到 onSelect（动作按钮不出现）。改用 Listener 直接
  // 跨越手势仑免判定点击，如果指针按下与抬起间隔<350ms
  // 且位移<8逻辑像素，视为一次选中点击。
  Offset? _pointerDownPosition;
  DateTime? _pointerDownAt;
  // 2026-05-17: 左上方胶囊（思考 / 工具调用 / 工具结果）有自己的
  // 折叠/展开语义。指针落在胶囊内部时不应触发外层 Listener 的"选中
  // 卡片"，否则会同时切换胶囊折叠和功能按钮。
  final GlobalKey _metaCapsuleKey = GlobalKey();

  // 2026-05-22: 外层 Listener.onPointerUp 在 Flutter gesture arena
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
  bool? _lastCacheIsSelected;
  bool? _lastCacheDarkCodeSurface;

  @override
  void didUpdateWidget(covariant _MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id) {
      _compressionExpanded = false;
      _reasoningExpandedOverride = null;
      _showRawContent = false;
      _invalidateCache();
    }
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
    _lastCacheIsSelected = null;
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

  /// 子交互回调（Markdown 链接、图片附件、代码块工具栏按钮等）在
  /// 触发自身动作之前调用此方法，告知气泡"本次点击已被消费"，从而
  /// 取消即将到来的延迟选中切换，避免点击交互后顺带切出/收起功能按钮。
  void markInteractiveTap() {
    _pendingSelectionToggleTimer?.cancel();
    _pendingSelectionToggleTimer = null;
  }

  void _scheduleSelectionToggle() {
    _pendingSelectionToggleTimer?.cancel();
    _pendingSelectionToggleTimer = Timer(const Duration(milliseconds: 80), () {
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
    final isToolCallStreaming =
        isToolCall &&
        (message.metadata['tool_arguments_streaming'] == true ||
            message.metadata[aiSessionMessageMetadataStreamingKey] == true);
    final isStatus = message.kind == AiSessionMessageKind.status;
    final isSelfLearning = message.kind == AiSessionMessageKind.selfLearning;
    final isRoundFileMutationSummary =
        message.kind == AiSessionMessageKind.fileMutationSummary ||
        (isStatus && message.metadata['round_file_mutation_summary'] == true);
    // 阶段⑰：「本轮文件变动汇总」状态卡走专属 Widget，跳过通用 bubble 流。
    if (isRoundFileMutationSummary) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
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
    final borderRadius = BorderRadius.circular(isReasoning ? 18 : 26);
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
        _lastCacheIsSelected != widget.isSelected ||
        _lastCacheDarkCodeSurface != useDarkCodeSurface;
    if (needsCacheRefresh) {
      _lastCacheMessageId = message.id;
      _lastCacheEnvironmentKey = environmentKey;
      _lastCacheThemeBrightness = themeBrightness;
      _lastCacheIsSelected = widget.isSelected;
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
          // 2026-04-27: 始终允许文本选择/复制，便于用户随时复制响应内容。
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

    // Parse Hardness Engineering agent/phase annotations from message content.
    // Only assistant-role messages can carry these markers.
    final heAnnotation =
        (!isUser &&
            !isCompressionPoint &&
            !isToolCall &&
            !isToolResult &&
            !isStatus &&
            !isSelfLearning)
        ? _parseHeAnnotation(message.content)
        : null;
    final effectiveContent = heAnnotation?.strippedContent ?? message.content;

    final isScrollHighlighted = widget.isScrollHighlighted;
    final highlightBorderColor = colorScheme.primary.withValues(alpha: 0.78);
    final disableBubbleSizeAnimation =
        isStreamingAssistant || isStreamingReasoning || isToolCallStreaming;
    final bubbleBody = Column(
      crossAxisAlignment: isUser
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        if (heAnnotation != null && heAnnotation.hasAnnotations)
          _HardnessAnnotationCapsuleRow(annotation: heAnnotation),
        AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
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
            // 2026-05-02: Smoothly interpolate bubble height as the
            // assistant streams in tokens / metadata grows. Without this
            // AnimatedSize wrapper, every chunk that lengthens the
            // markdown body bumps the bubble's intrinsic height in a
            // single frame, which feels rigid against the rest of the
            // app's motion design. Duration/curve 跟随全局弹窗动画设置
            // （与 reasoning / tool_call 折叠胶囊同一节奏），避免内外层
            // 动画相互竞争引发的「抽搐鬼畜」。
            // 2026-05-17 (Bug 5) — 时长 / 曲线全部走
            // `_home_motion_tokens.dart` 的 motion token，跨卡片节奏
            // 统一；不再在调用点写裸 milliseconds。
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
                          final nextExpanded = !reasoningExpanded;
                          setState(() {
                            _reasoningExpandedOverride = nextExpanded;
                          });
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
                    else if (!isUser &&
                        !isSelfLearning &&
                        message.modelLabel != null)
                      Text(
                        message.modelLabel!,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: isUser
                              ? textColor.withValues(alpha: 0.86)
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (isCompressionPoint ||
                        isReasoning ||
                        isToolCall ||
                        isToolResult ||
                        (!isUser &&
                            !isSelfLearning &&
                            message.modelLabel != null))
                      const SizedBox(height: 10),
                    if (isCompressionPoint)
                      _CompressionCheckpointBody(
                        content: message.content,
                        expanded: _compressionExpanded,
                        onToggle: () {
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
                      )
                    else if (isReasoning)
                      _ReasoningBody(
                        content: message.content,
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
                      )
                    else if (isToolCall)
                      _ToolCallBody(message: message, selectable: true)
                    else if (isSelfLearning)
                      ClipRect(
                        child: AnimatedSize(
                          duration: cardMotionDurationFor(
                            context,
                            expanding: true,
                          ),
                          curve: kCardMotionCurve,
                          alignment: Alignment.topLeft,
                          child: _SelfLearningCard(message: message),
                        ),
                      )
                    else if (isUser)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (attachments.isNotEmpty) ...[
                            _MessageAttachmentSummaryBlock(
                              attachments: attachments,
                              textColor: textColor,
                              backgroundColor: backgroundColor,
                              onAttachmentTap: (attachment) =>
                                  _openAttachment(context, attachment),
                            ),
                            const SizedBox(height: 10),
                          ],
                          _PlainTextMessageBody(
                            data: effectiveContent.isEmpty
                                ? ' '
                                : effectiveContent,
                            textColor: textColor,
                            backgroundColor: backgroundColor,
                            style: markdownStyleSheet.styleSheet.p,
                          ),
                        ],
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (attachments.isNotEmpty) ...[
                            _MessageAttachmentSummaryBlock(
                              attachments: attachments,
                              textColor: textColor,
                              backgroundColor: backgroundColor,
                              onAttachmentTap: (attachment) =>
                                  _openAttachment(context, attachment),
                            ),
                            const SizedBox(height: 10),
                          ],
                          if (_showRawContent)
                            SelectableText(
                              effectiveContent.isEmpty ? ' ' : effectiveContent,
                              style: markdownStyleSheet.styleSheet.p?.copyWith(
                                color: textColor,
                              ),
                            )
                          else if (isStreamingAssistant)
                            StreamingTextReveal(
                              textLength: effectiveContent.length,
                              streaming: true,
                              animateSize: false,
                              child: _StreamingAssistantTextBody(
                                data: effectiveContent,
                                textColor: textColor,
                                backgroundColor: backgroundColor,
                                style: markdownStyleSheet.styleSheet.p,
                              ),
                            )
                          else
                            _AssistantMessageBodyDispatcher(
                              data: effectiveContent.isEmpty
                                  ? ' '
                                  : effectiveContent,
                              format: resolvedMessageContentFormat,
                              htmlFallback: context
                                  .watch<SettingsController>()
                                  .aiHtmlRenderFallback,
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
                              previewMaxHeight: isToolResult ? 176 : 240,
                              wrapInSelectionArea: !isToolResult,
                            ),
                          if (isStreamingAssistant) ...[
                            const SizedBox(height: 4),
                            _TypewriterCaret(color: textColor),
                          ],
                        ],
                      ),
                    const SizedBox(height: 10),
                    Text(
                      _formatDateTime(message.createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: textColor.withValues(alpha: 0.78),
                      ),
                    ),
                    if (isUser)
                      _UserMessageCapsuleRow(
                        creationRequest: AiCreationRequest.fromMetadata(
                          message.metadata[AiCreationRequest.metadataKey],
                        ),
                        skillMetadata:
                            message.metadata[aiUserSkillSelectionMetadataKey],
                        attachments: attachments,
                        textColor: textColor,
                      ),
                  ],
                );
                return ClipRect(
                  child: disableBubbleSizeAnimation
                      ? bubbleContent
                      : AnimatedSize(
                          duration: cardMotionDurationFor(
                            context,
                            expanding: reasoningExpanded,
                          ),
                          curve: kCardMotionCurve,
                          alignment: Alignment.topLeft,
                          child: bubbleContent,
                        ),
                );
              },
            ),
          ),
        ),
        AnimatedSize(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: widget.isSelected
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutBack,
                    builder: (context, value, child) {
                      return Opacity(
                        opacity: value.clamp(0, 1).toDouble(),
                        child: Transform.scale(
                          scale: 0.85 + 0.15 * value,
                          child: child,
                        ),
                      );
                    },
                    child: Wrap(
                      spacing: 8,
                      children: [
                        _MessageActionButton(
                          onPressed: widget.onCopy,
                          icon: Icons.content_copy_outlined,
                          label: _localizedText(context, zh: '复制', en: 'Copy'),
                        ),
                        if (widget.onEdit != null)
                          _MessageActionButton(
                            onPressed: widget.onEdit,
                            icon: Icons.edit_outlined,
                            label: AppLocalizations.of(context)!.commonEdit,
                          ),
                        _MessageActionButton(
                          onPressed: widget.onDelete,
                          icon: Icons.delete_outline_rounded,
                          label: AppLocalizations.of(context)!.commonDelete,
                        ),
                        if (widget.onDeleteFromHere != null)
                          _MessageActionButton(
                            onPressed: widget.onDeleteFromHere,
                            icon: Icons.delete_sweep_outlined,
                            label: _localizedText(
                              context,
                              zh: '删除此条及后续',
                              en: 'Delete From Here',
                            ),
                          ),
                        if (widget.onAudit != null)
                          _MessageActionButton(
                            onPressed: () async => widget.onAudit!.call(),
                            icon: Icons.fact_check_outlined,
                            label: _localizedText(
                              context,
                              zh: '审计',
                              en: 'Audit',
                            ),
                          ),
                        if (!isUser &&
                            !isToolCall &&
                            !isReasoning &&
                            !isSelfLearning &&
                            !isCompressionPoint &&
                            !isStatus)
                          _MessageActionButton(
                            onPressed: () async => setState(
                              () => _showRawContent = !_showRawContent,
                            ),
                            icon: _showRawContent
                                ? Icons.code_off_outlined
                                : Icons.code_outlined,
                            label: _showRawContent
                                ? _localizedText(
                                    context,
                                    zh: '显示渲染',
                                    en: 'Show Rendered',
                                  )
                                : _localizedText(
                                    context,
                                    zh: '显示原始',
                                    en: 'Show Raw',
                                  ),
                          ),
                        if (!isUser &&
                            !isToolCall &&
                            !isReasoning &&
                            !isSelfLearning &&
                            !isCompressionPoint &&
                            !isStatus &&
                            resolvedMessageContentFormat ==
                                AiMessageContentFormat.html &&
                            _looksLikeHtml(effectiveContent))
                          _MessageActionButton(
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
                            label: _localizedText(
                              context,
                              zh: '浏览器打开',
                              en: 'Open in Browser',
                            ),
                          ),
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
    final messageContent = widget.trackLayoutChanges
        ? NotificationListener<SizeChangedLayoutNotification>(
            onNotification: (notification) {
              widget.onLayoutChanged();
              return false;
            },
            child: SizeChangedLayoutNotifier(child: bubbleBody),
          )
        : bubbleBody;

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
        if (movement <= 4) return;
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
        // 2026-05-17: 左上方"思考 / 工具调用 / 工具结果"胶囊有自己的
        // 折叠/展开手势，不应顺带触发整张消息卡的"选中"。这里取胶囊
        // 全局矩形与抬起点比较，命中即直接 swallow 不切换 selection。
        if (_isPointerInsideMetaCapsule(event.position)) {
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
          if (movement <= 8 && elapsed.inMilliseconds <= 600) {
            (htmlStateUp ?? htmlStateDown)?.simulateTapAtGlobal(event.position);
          }
          return;
        }
        final movement = (event.position - downPos).distance;
        final elapsed = DateTime.now().difference(downAt);
        if (movement <= 8 && elapsed.inMilliseconds <= 350) {
          // Toggle: 已选中时再次点击隐藏功能按钮，未选中时显示。
          // 延迟 80ms，给气泡内的子交互回调（链接 / 图片 / 工具栏按钮）
          // 一个调用 markInteractiveTap() 取消切换的窗口期。
          _scheduleSelectionToggle();
        }
      },
      child: TapRegion(
        enabled: widget.isSelected,
        onTapOutside: (_) => widget.onDeselect(),
        child: _BubbleHtmlInteractiveScope(
          state: this,
          child: Align(
            alignment: alignment,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: messageContent,
            ),
          ),
        ),
      ),
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

class _MessageActionButton extends StatelessWidget {
  const _MessageActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final Future<void> Function()? onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        textStyle: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
      ),
    );
  }
}

class _MessageAttachmentSummaryBlock extends StatelessWidget {
  const _MessageAttachmentSummaryBlock({
    required this.attachments,
    required this.textColor,
    required this.backgroundColor,
    this.onAttachmentTap,
  });

  final List<AiMessageAttachment> attachments;
  final Color textColor;
  final Color backgroundColor;
  final void Function(AiMessageAttachment attachment)? onAttachmentTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: attachments
          .map(
            (attachment) => MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  _BubbleHtmlInteractiveScope.maybeOf(
                    context,
                  )?.markInteractiveTap();
                  onAttachmentTap?.call(attachment);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(
                      textColor.withValues(alpha: 0.08),
                      backgroundColor,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: textColor.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _iconForAttachmentKind(attachment.kind),
                        size: 16,
                        color: textColor.withValues(alpha: 0.88),
                      ),
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 280),
                        child: Text(
                          '${attachment.name} · ${aiFormatBytes(attachment.sizeBytes)}',
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: textColor.withValues(alpha: 0.88),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

/// Opens a message attachment: images are shown in an in-app preview dialog;
/// other file types are opened with the system default application.
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

  // Non-image files: open with system default application.
  await _openLocalPathWithSystemApp(context, storagePath);
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
  final hasLeadingDash = normalizedPath.startsWith('-');
  if (looksLikeUri || hasLeadingDash) {
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
    final ProcessResult? result;
    if (Platform.isMacOS) {
      result = await runProcessWithTimeout(
        'open',
        <String>[normalizedPath],
        timeout: const Duration(seconds: 6),
        tag: 'home_message_bubble',
      );
    } else if (Platform.isWindows) {
      result = await runProcessWithTimeout(
        'cmd',
        <String>['/c', 'start', '', normalizedPath],
        timeout: const Duration(seconds: 6),
        tag: 'home_message_bubble',
      );
    } else if (Platform.isLinux) {
      result = await runProcessWithTimeout(
        'xdg-open',
        <String>[normalizedPath],
        timeout: const Duration(seconds: 6),
        tag: 'home_message_bubble',
      );
    } else {
      throw const FileSystemException('Unsupported platform.');
    }
    if (result != null && result.exitCode == 0) {
      return;
    }
    final message = result == null
        ? 'open command timed out'
        : '${result.stderr}'.trim();
    throw FileSystemException(
      message.isEmpty ? 'Failed to open file.' : message,
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

/// Opens a composer attachment draft: images are shown in an in-app preview
/// dialog; other file types are opened with the system default application.
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

/// Full-screen image preview dialog with zoom and pan support.
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

  /// 弹窗最小宽度, 确保头部 3 个图标按钮 + 标题省略号始终能够放下。
  static const double _kMinDialogW = 280.0;

  /// 加载中 / 解析失败 / 来源缺失时的方形占位边长。
  static const double _kFallbackSide = 320.0;

  ImageStream? _imageStream;
  ImageStreamListener? _imageStreamListener;
  Size? _naturalSize;

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
    final viewport = MediaQuery.sizeOf(context);
    final disableAnim = MediaQuery.disableAnimationsOf(context);

    // 弹窗的最大可用尺寸 (扣除两侧 inset)。
    final maxDialogW = math.max(
      _kMinDialogW,
      viewport.width - _kInsetPadding * 2,
    );
    final maxDialogH = math.max(200.0, viewport.height - _kInsetPadding * 2);
    // body (图片显示区) 的最大可用尺寸: 扣除头部 + 分隔线 + 四周统一 padding。
    final maxBodyW = math.max(0.0, maxDialogW - _kPadding * 2);
    final maxBodyH = math.max(
      0.0,
      maxDialogH - _kHeaderEstimate - _kDividerH - _kPadding * 2,
    );

    double bodyW;
    double bodyH;
    final natural = _naturalSize;
    if (natural != null && natural.width > 0 && natural.height > 0) {
      // 等比缩放至 maxBodyW × maxBodyH 的最大内接矩形, 与 BoxFit.contain 等价,
      // 但宽高直接落到外层 SizedBox 上, 因此四周不会出现 letterbox 白边。
      final ratio = natural.width / natural.height;
      bodyW = maxBodyW;
      bodyH = bodyW / ratio;
      if (bodyH > maxBodyH) {
        bodyH = maxBodyH;
        bodyW = bodyH * ratio;
      }
    } else {
      // 加载中 / 来源缺失时给一个相对小的方形占位, 避免一开始就撑满弹窗,
      // 等真实尺寸到位后由 AnimatedSize 平滑过渡到目标体积。
      final side = math.min(_kFallbackSide, math.min(maxBodyW, maxBodyH));
      bodyW = math.max(0.0, side);
      bodyH = math.max(0.0, side);
    }

    final dialogW = (bodyW + _kPadding * 2).clamp(_kMinDialogW, maxDialogW);

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
        backgroundColor: colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: AnimatedSize(
          duration: disableAnim
              ? Duration.zero
              : const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxDialogW,
              maxHeight: maxDialogH,
            ),
            child: SizedBox(
              width: dialogW,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 头部标题栏。
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
                    child: Row(
                      children: [
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
                  // 由于 SizedBox 的尺寸已经精确等于 BoxFit.contain 后的图片尺寸,
                  // Image 控件内部不会再产生 letterbox 白边。
                  Padding(
                    padding: const EdgeInsets.all(_kPadding),
                    child: SizedBox(
                      width: bodyW,
                      height: bodyH,
                      child: _buildPreviewImage(context),
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

  Widget _buildPreviewImage(BuildContext context) {
    final sourceFilePath = widget.filePath;
    if (sourceFilePath != null) {
      return Image.file(
        File(sourceFilePath),
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
      fit: BoxFit.contain,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        // 网络图片帧解码完成 → 触发后台缓存, 下次可直接走本地文件。
        if (frame != null) {
          MediaCacheService.instance.cacheInBackground(urlString);
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
    final scheme = sourceUri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      throw FileSystemException(
        'Unsupported image URI scheme: ${sourceUri.scheme}',
        sourceUri.toString(),
      );
    }

    final client = SystemProxyResolver.instance.createRawHttpClient(
      connectionTimeout: const Duration(seconds: 20),
    );
    try {
      final request = await client
          .getUrl(sourceUri)
          .timeout(const Duration(seconds: 20));
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'HTTP ${response.statusCode} while downloading image.',
          uri: sourceUri,
        );
      }
      final contentType = response.headers.contentType;
      if (contentType != null && contentType.primaryType != 'image') {
        throw HttpException(
          'Unexpected content type: ${contentType.mimeType}',
          uri: sourceUri,
        );
      }

      final output = File(destination).openWrite();
      try {
        // Cap idle gap between TCP chunks at 30s and total body read at
        // 5min so a malicious / stalled origin cannot hang the bubble
        // forever.
        await output
            .addStream(response.timeout(const Duration(seconds: 30)))
            .timeout(const Duration(minutes: 5));
        await output.flush();
      } finally {
        await output.close();
      }
    } finally {
      client.close(force: true);
    }
  }
}

enum _GeneratedMessageMediaKind { video, audio }

class _GeneratedMediaSource {
  const _GeneratedMediaSource({
    required this.kind,
    required this.uri,
    this.filePath,
  });

  final _GeneratedMessageMediaKind kind;
  final Uri uri;
  final String? filePath;

  bool get isLocalFile => filePath != null;
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
  // Without this guard, rapid double-clicks on the inline card stacked two
  // identical preview dialogs (each spinning up its own WebView), which
  // pinned the UI thread and leaked event handlers.
  bool _dialogOpen = false;
  // Cached sidecar PNG path for local video previews. `null` while the
  // capture is pending or when the source is remote / not a video.
  String? _videoThumbPath;
  bool _videoCaptureRequested = false;

  @override
  void initState() {
    super.initState();
    _initVideoThumbnail();
  }

  @override
  void didUpdateWidget(covariant _GeneratedMediaLinkCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source.filePath != widget.source.filePath ||
        oldWidget.source.kind != widget.source.kind) {
      _videoThumbPath = null;
      _videoCaptureRequested = false;
      _initVideoThumbnail();
    }
  }

  Future<void> _initVideoThumbnail() async {
    final source = widget.source;
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
    if (_dialogOpen) return;
    _dialogOpen = true;
    try {
      await showAnimatedDialog<void>(
        context: context,
        builder: (dialogContext) =>
            _MediaPreviewDialog(source: widget.source, title: widget.title),
      );
    } finally {
      if (mounted) _dialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = widget.source;
    final title = widget.title;
    final textColor = widget.textColor;
    final backgroundColor = widget.backgroundColor;
    final isVideo = source.kind == _GeneratedMessageMediaKind.video;
    if (isVideo) {
      return _buildVideoCard(theme, source, title, textColor, backgroundColor);
    }
    const icon = Icons.graphic_eq;
    final label = _localizedText(context, zh: '音频', en: 'Audio');
    final detail = source.isLocalFile
        ? p.basename(source.filePath!)
        : source.uri.host.isEmpty
        ? source.uri.toString()
        : source.uri.host;
    final cardColor = Color.alphaBlend(
      textColor.withValues(alpha: 0.08),
      backgroundColor,
    );
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
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: textColor.withValues(alpha: 0.16)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 26, color: textColor.withValues(alpha: 0.9)),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: textColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$label · $detail',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: textColor.withValues(alpha: 0.76),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.open_in_full_rounded,
                    size: 18,
                    color: textColor.withValues(alpha: 0.78),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoCard(
    ThemeData theme,
    _GeneratedMediaSource source,
    String title,
    Color textColor,
    Color backgroundColor,
  ) {
    final detail = source.isLocalFile
        ? p.basename(source.filePath!)
        : source.uri.host.isEmpty
        ? source.uri.toString()
        : source.uri.host;
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

class _MediaPreviewDialog extends StatefulWidget {
  const _MediaPreviewDialog({required this.source, required this.title});

  final _GeneratedMediaSource source;
  final String title;

  @override
  State<_MediaPreviewDialog> createState() => _MediaPreviewDialogState();
}

class _MediaPreviewDialogState extends State<_MediaPreviewDialog> {
  static const Duration _mediaLoadTimeout = Duration(seconds: 18);

  late final WebViewController _controller;
  Timer? _loadTimeoutTimer;
  bool _pageLoaded = false;
  bool _mediaReady = false;
  String? _loadError;
  // Reentrancy guards: rapid double-taps on the system-player / save buttons
  // were spawning duplicate downloads to the same destination, corrupting
  // the output file and pinning the WebView event loop.
  bool _isSaving = false;
  bool _isOpeningExternal = false;
  bool _disposed = false;
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
    _controller = WebViewController()
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
      _controller.setBackgroundColor(Colors.transparent);
    }
    _bootstrapMediaPage();
    _loadTimeoutTimer = Timer(_mediaLoadTimeout, () {
      if (!mounted || _mediaReady) return;
      setState(() {
        _loadError = _localizedText(
          context,
          zh: '载入超时，可使用系统播放器打开。',
          en: 'Loading timed out. Open with the system player instead.',
        );
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _dialogFocus.requestFocus();
    });
  }

  Future<void> _togglePlayPause() async {
    try {
      await _controller.runJavaScript(
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
        await _controller.loadFile(tempFile.path);
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
    await _controller.loadHtmlString(_buildMediaHtml());
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
    // Stop any audio playback so closing the dialog never leaves a
    // ghost track playing while the WebView tears down.
    unawaited(
      _controller
          .runJavaScript(
            "try{var m=document.getElementById('media');if(m){try{m.pause();}catch(_){};try{m.muted=true;}catch(_){};try{m.removeAttribute('src');}catch(_){};try{while(m.firstChild)m.removeChild(m.firstChild);}catch(_){};try{m.load();}catch(_){};}}catch(_){}",
          )
          .catchError((_) {}),
    );
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

  void _handleMediaMessage(JavaScriptMessage message) {
    if (!mounted) return;
    final value = message.message.trim();
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
  }

  String _buildMediaHtml({String? localOverride}) {
    final rawSource = localOverride != null
        ? Uri.file(localOverride).toString()
        : widget.source.uri.toString();
    final source = const HtmlEscape(
      HtmlEscapeMode.attribute,
    ).convert(rawSource);
    final isVideo = widget.source.kind == _GeneratedMessageMediaKind.video;
    final mimeType = _mimeTypeForGeneratedMedia(widget.source);
    final escapedMime = const HtmlEscape(
      HtmlEscapeMode.attribute,
    ).convert(mimeType);
    final mediaTag = isVideo
        ? '<video id="media" controls playsinline preload="metadata"><source src="$source" type="$escapedMime"></video>'
        : '<audio id="media" controls preload="metadata"><source src="$source" type="$escapedMime"></audio>';
    return '''
<!doctype html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
html, body { margin: 0; padding: 0; width: 100%; height: 100%; background: transparent; }
body { display: flex; align-items: center; justify-content: center; overflow: hidden; }
video { width: 100%; height: 100%; max-height: 100vh; background: #000; object-fit: contain; }
audio { width: min(680px, calc(100vw - 24px)); }
</style>
</head>
<body>
$mediaTag
<script>
(function() {
  const media = document.getElementById('media');
  window.media = media;
  const post = (value) => {
    if (window.OpenHandMedia && window.OpenHandMedia.postMessage) {
      window.OpenHandMedia.postMessage(value);
    }
  };
  ['loadedmetadata', 'canplay', 'playing'].forEach((eventName) => {
    media.addEventListener(eventName, () => post(eventName));
  });
  media.addEventListener('error', () => {
    const err = media.error ? String(media.error.code) : 'unknown';
    post('error:' + err);
  });
  // Throttled time reporting so Dart can hand the resume timestamp to
  // the fullscreen route without flooding the JS bridge.
  let lastSent = -1;
  function sendTime() {
    const t = media.currentTime || 0;
    if (Math.abs(t - lastSent) >= 0.2) {
      lastSent = t;
      post('time:' + t.toFixed(3));
    }
  }
  media.addEventListener('timeupdate', sendTime);
  media.addEventListener('pause', sendTime);
  media.addEventListener('seeked', sendTime);
  setTimeout(() => {
    if (!media || media.readyState === 0) post('error:timeout');
  }, ${_mediaLoadTimeout.inMilliseconds});
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
    final mediaHeight = isVideo
        ? MediaQuery.sizeOf(context).height * 0.68
        : 126.0;
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
            insetPadding: const EdgeInsets.all(24),
            backgroundColor: colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: math.min(
                  MediaQuery.sizeOf(context).width * 0.92,
                  960,
                ),
                maxHeight: MediaQuery.sizeOf(context).height * 0.9,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                    child: Row(
                      children: [
                        Icon(
                          isVideo ? Icons.videocam_outlined : Icons.audiotrack,
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
                        if (isVideo) ...[
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
                        ],
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
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          height: mediaHeight,
                          width: double.infinity,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Positioned.fill(
                                child: WebViewWidget(controller: _controller),
                              ),
                              if (!_pageLoaded ||
                                  (!_mediaReady && _loadError == null))
                                const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.6,
                                  ),
                                ),
                              if (_loadError != null)
                                _MediaLoadFallback(
                                  message: _loadError!,
                                  onOpenExternal: () =>
                                      _openInSystemPlayer(context),
                                ),
                            ],
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

  Future<void> _enterFullscreen(BuildContext context) async {
    // Capture the navigator before the async pause so we don't reference
    // a possibly-stale BuildContext after the await.
    final navigator = Navigator.of(context, rootNavigator: true);
    SettingsController? settingsController;
    try {
      settingsController = context.read<SettingsController>();
    } catch (_) {
      settingsController = null;
    }
    // Pause the underlying preview before we hand control to the
    // fullscreen route so the user never hears two audio tracks at once.
    try {
      await _controller.runJavaScript(
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
        await _controller.runJavaScript(
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
        await _downloadRemoteMedia(
          widget.source,
          location.path,
          cancelSignal: cancel.future,
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
    final filePath = widget.source.filePath;
    if (filePath != null) {
      final basename = p.basename(filePath).trim();
      if (basename.isNotEmpty) return basename;
    }
    final decodedPath = () {
      try {
        return Uri.decodeFull(widget.source.uri.path);
      } catch (_) {
        return widget.source.uri.path;
      }
    }();
    final basename = p.basename(decodedPath).trim();
    if (basename.isNotEmpty && basename != '/' && basename != '.') {
      return basename;
    }
    final prefix = widget.source.kind == _GeneratedMessageMediaKind.video
        ? 'video'
        : 'audio';
    final ext = widget.source.kind == _GeneratedMessageMediaKind.video
        ? '.mp4'
        : '.mp3';
    return '$prefix-${DateTime.now().millisecondsSinceEpoch}$ext';
  }
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
  if (filePath != null) return p.basename(filePath);
  final basename = p.basename(source.uri.path).trim();
  if (basename.isNotEmpty && basename != '/' && basename != '.') {
    return basename;
  }
  return source.kind == _GeneratedMessageMediaKind.video
      ? 'AI Generated Video'
      : 'AI Generated Audio';
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
  final scheme = source.uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    throw FileSystemException(
      'Unsupported media URI scheme: ${source.uri.scheme}',
      source.uri.toString(),
    );
  }
  final client = SystemProxyResolver.instance.createRawHttpClient(
    connectionTimeout: const Duration(seconds: 20),
  );
  var cancelled = false;
  cancelSignal?.whenComplete(() {
    cancelled = true;
    client.close(force: true);
  });
  try {
    final request = await client
        .getUrl(source.uri)
        .timeout(const Duration(seconds: 20));
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'HTTP ${response.statusCode} while downloading media.',
        uri: source.uri,
      );
    }
    final contentType = response.headers.contentType;
    final expectedPrimary = source.kind == _GeneratedMessageMediaKind.video
        ? 'video'
        : 'audio';
    if (contentType != null &&
        contentType.primaryType != expectedPrimary &&
        contentType.mimeType != 'application/octet-stream') {
      throw HttpException(
        'Unexpected content type: ${contentType.mimeType}',
        uri: source.uri,
      );
    }
    final maxBytes = source.kind == _GeneratedMessageMediaKind.video
        ? 2 * 1024 * 1024 * 1024
        : 256 * 1024 * 1024;
    final downloadDeadline = DateTime.now().add(
      source.kind == _GeneratedMessageMediaKind.video
          ? const Duration(minutes: 20)
          : const Duration(minutes: 5),
    );
    final outputFile = File(destination);
    final output = outputFile.openWrite();
    var receivedBytes = 0;
    var outputClosed = false;

    Future<void> closeOutput() async {
      if (outputClosed) return;
      outputClosed = true;
      await output.close();
    }

    try {
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        if (cancelled) {
          throw const _MediaDownloadCancelled();
        }
        if (DateTime.now().isAfter(downloadDeadline)) {
          throw TimeoutException('Media download exceeded time limit.');
        }
        receivedBytes += chunk.length;
        if (receivedBytes > maxBytes) {
          throw FileSystemException(
            'Media download exceeded size limit.',
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
          'close failed media download stream',
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
          'delete partial media download',
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

/// Small capsule rendered directly under a user message timestamp when the
/// message was sent with a non-text creation mode (image / video / audio / deep
/// research). Lets the reader tell at a glance what action the message is
/// asking for even after the composer chip is gone.
class _UserMessageCapsuleRow extends StatelessWidget {
  const _UserMessageCapsuleRow({
    required this.creationRequest,
    required this.skillMetadata,
    required this.attachments,
    required this.textColor,
  });

  final AiCreationRequest creationRequest;
  final Object? skillMetadata;
  final List<AiMessageAttachment> attachments;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final skillName = _UserSkillSelectionChip.nameFromMetadata(skillMetadata);
    final attachmentCapsules = _AttachmentCapsuleData.fromAttachments(
      context,
      attachments,
    );
    if (!creationRequest.isActive &&
        skillName.isEmpty &&
        attachmentCapsules.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          if (creationRequest.isActive)
            _CreationModeChip(request: creationRequest, textColor: textColor),
          if (skillName.isNotEmpty)
            _UserSkillSelectionChip(
              metadata: skillMetadata,
              textColor: textColor,
            ),
          for (final capsule in attachmentCapsules)
            _AttachmentKindCapsule(data: capsule, textColor: textColor),
        ],
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
  });

  final IconData icon;
  final String label;
  final Color textColor;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: textColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: textColor.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading ??
              Icon(icon, size: 12, color: textColor.withValues(alpha: 0.9)),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: textColor.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
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

/// Capsule rendered under a user message timestamp when the message was
/// submitted with an explicit local-skill selection (e.g. `/caveman`).
/// Mirrors [_CreationModeChip] so the transcript conveys at a glance which
/// skill was activated for the turn.
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

class _AttachmentKindCapsule extends StatelessWidget {
  const _AttachmentKindCapsule({required this.data, required this.textColor});

  final _AttachmentCapsuleData data;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return _MessageContextCapsule(
      icon: data.icon,
      label: data.label,
      textColor: textColor,
    );
  }
}

class _AttachmentCapsuleData {
  const _AttachmentCapsuleData({required this.icon, required this.label});

  factory _AttachmentCapsuleData.fromKind(
    BuildContext context, {
    required AiAttachmentKind kind,
    required int count,
  }) {
    final (icon, labelZh, labelEn) = switch (kind) {
      AiAttachmentKind.image => (Icons.image_outlined, '图片', 'Image'),
      AiAttachmentKind.text => (Icons.description_outlined, '文本', 'Text'),
      AiAttachmentKind.spreadsheet => (
        Icons.table_chart_outlined,
        '表格',
        'Spreadsheet',
      ),
      AiAttachmentKind.pdf => (Icons.picture_as_pdf_outlined, 'PDF', 'PDF'),
      AiAttachmentKind.binary => (
        Icons.insert_drive_file_outlined,
        '文件',
        'File',
      ),
    };
    final base = _localizedText(
      context,
      zh: '附件 · $labelZh',
      en: 'Attachment · $labelEn',
    );
    return _AttachmentCapsuleData(
      icon: icon,
      label: count > 1 ? '$base · x$count' : base,
    );
  }

  final IconData icon;
  final String label;

  static List<_AttachmentCapsuleData> fromAttachments(
    BuildContext context,
    List<AiMessageAttachment> attachments,
  ) {
    if (attachments.isEmpty) return const <_AttachmentCapsuleData>[];
    final counts = <AiAttachmentKind, int>{};
    for (final attachment in attachments) {
      counts[attachment.kind] = (counts[attachment.kind] ?? 0) + 1;
    }
    return [
      for (final kind in AiAttachmentKind.values)
        if ((counts[kind] ?? 0) > 0)
          _AttachmentCapsuleData.fromKind(
            context,
            kind: kind,
            count: counts[kind]!,
          ),
    ];
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
      _watchdog = Timer(const Duration(seconds: 18), () {
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
      _watchdog = Timer(const Duration(seconds: 18), () {
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
        } catch (_) {
          // best effort
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
          } catch (_) {
            // best effort
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
    this.initialTime = 0,
  });

  final _GeneratedMediaSource source;
  final String title;
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
    if (value.startsWith('time:')) {
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
    return '''
<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1.0"><style>html,body{margin:0;background:#000;width:100%;height:100%;overflow:hidden}video{width:100vw;height:100vh;background:#000;object-fit:contain}</style></head><body>
<video id="media" controls autoplay playsinline preload="auto"><source src="$src" type="$mime"></video>
<script>(function(){
var v=document.getElementById('media');
function post(m){try{if(window.OpenHandFs&&window.OpenHandFs.postMessage){window.OpenHandFs.postMessage(String(m));}}catch(_){}}
var resumed=false;
function resume(){
  if(resumed)return;resumed=true;
  try{var t=parseFloat('$initial');if(!isNaN(t)&&t>0&&t<(v.duration||Infinity)){v.currentTime=t;}}catch(_){}}
v.addEventListener('loadedmetadata',resume);
v.addEventListener('canplay',resume);
v.addEventListener('error',function(){post('error:video_load');});
var lastSent=-1;
function sendTime(){var t=v.currentTime||0;if(Math.abs(t-lastSent)>=0.2){lastSent=t;post('time:'+t.toFixed(3));}}
v.addEventListener('timeupdate',sendTime);
v.addEventListener('pause',sendTime);
v.addEventListener('seeked',sendTime);
})();</script>
</body></html>
''';
  }

  void _exit() {
    if (!mounted) return;
    // Stop playback synchronously-as-possible so the user does not hear
    // residual audio while the route pops. We fire the JS pause first,
    // then pop — the controller is still attached at this point.
    _stopPlaybackBestEffort();
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
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 140),
            curve: Curves.easeOut,
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
/// 2026-05-17 — 配合 [_StreamCharThrottle] 的 60fps 节流，给低速率字符
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
