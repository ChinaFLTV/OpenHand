part of '../openhand_home_page.dart';

// 阶段㉒ — 触发「折叠 + 渐变预览」的字符 / 行阈值再下调一档，让 60+
// 条历史会话首次打开时大部分长消息只解析 2000 字预览块（_previewCharCap），
// 完整 markdown 解析推迟到用户主动展开时再触发。
// 5000 → 2400 字符：覆盖典型 GPT-4 / Claude 长答的 ~1200 token 输出。
// 1200 → 800：tool_result 压缩更激进 (Bash/grep 输出常以行计算)。
// 90 → 45 行：长答列表 / 大段代码即时折叠。
const int _messageMarkdownCollapseCharThreshold = 2400;
const int _toolResultMarkdownCollapseCharThreshold = 800;
const int _messageMarkdownCollapseLineThreshold = 45;

/// Maximum message body size (in characters) at which we still attempt
/// markdown parsing. Above this we render the raw text directly to keep
/// transcript open / scroll responsive — `flutter_markdown_plus` runs the
/// AST parse and widget build synchronously on the UI thread, and at this
/// size both passes start to dominate frame budgets and trigger ANR.
const int _markdownPlainTextSkipThresholdChars = 120 * 1024;
const int _toolResultMarkdownCollapseLineThreshold = 32;

class _CompressionCheckpointBody extends StatelessWidget {
  const _CompressionCheckpointBody({
    required this.content,
    required this.expanded,
    required this.onToggle,
    required this.selectable,
    required this.textColor,
    required this.fadeColor,
    required this.styleSheet,
    required this.builders,
    required this.inlineSyntaxes,
    required this.pathRoots,
    required this.parseKey,
  });

  final String content;
  final bool expanded;
  final VoidCallback onToggle;
  final bool selectable;
  final Color textColor;
  final Color fadeColor;
  final MarkdownStyleSheet styleSheet;
  final Map<String, MarkdownElementBuilder> builders;
  final List<md.InlineSyntax> inlineSyntaxes;
  final List<String> pathRoots;
  final String parseKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final toggleLabel = _localizedText(
      context,
      zh: expanded ? '收起摘要' : '展开摘要',
      en: expanded ? 'Collapse Summary' : 'Expand Summary',
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggle,
        borderRadius: _borderRadius18,
        overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      toggleLabel,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: textColor.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: cardMotionDurationFor(
                      context,
                      expanding: expanded,
                    ),
                    curve: kCardMotionCurve,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: textColor.withValues(alpha: 0.82),
                      size: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRect(
                child: expanded
                    ? KeyedSubtree(
                        key: const ValueKey<String>('compression-expanded'),
                        child: _SafeMarkdownBody(
                          data: content.isEmpty ? ' ' : content,
                          selectable: selectable,
                          builders: builders,
                          styleSheet: styleSheet,
                          inlineSyntaxes: inlineSyntaxes,
                          pathRoots: pathRoots,
                          parseKey: parseKey,
                        ),
                      )
                    : KeyedSubtree(
                        key: const ValueKey<String>('compression-preview'),
                        child: _MarkdownPreviewBody(
                          data: content.isEmpty ? ' ' : content,
                          maxHeight: 122,
                          styleSheet: styleSheet,
                          builders: builders,
                          inlineSyntaxes: inlineSyntaxes,
                          pathRoots: pathRoots,
                          parseKey: '$parseKey|compression-preview',
                          fadeColor: fadeColor,
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

class _ReasoningBody extends StatelessWidget {
  const _ReasoningBody({
    required this.content,
    required this.expanded,
    required this.streaming,
    required this.selectable,
    required this.textColor,
    required this.fadeColor,
    required this.styleSheet,
    required this.builders,
    required this.inlineSyntaxes,
    required this.pathRoots,
    required this.parseKey,
  });

  final String content;
  final bool expanded;
  final bool streaming;
  final bool selectable;
  final Color textColor;
  final Color fadeColor;
  final MarkdownStyleSheet styleSheet;
  final Map<String, MarkdownElementBuilder> builders;
  final List<md.InlineSyntax> inlineSyntaxes;
  final List<String> pathRoots;
  final String parseKey;

  @override
  Widget build(BuildContext context) {
    if (streaming) {
      return _StreamingReasoningBody(
        content: content,
        expanded: expanded,
        textStyle: styleSheet.p?.copyWith(color: textColor),
        fadeColor: fadeColor,
        selectable: selectable,
        styleSheet: styleSheet,
        builders: builders,
        inlineSyntaxes: inlineSyntaxes,
        pathRoots: pathRoots,
        parseKey: parseKey,
      );
    }
    // 折叠态：展示前 5-6 行预览（maxHeight ≈ 142）并在底部叠渐隐遮罩，
    // 给用户「开始阅读」的锚点，与 WEB 端 ReasoningCollapsibleBody 对齐。
    //
    // 注意：这里继续不再额外套内部 AnimatedSize。当前外层 `_MessageBubble`
    // 已恢复为单一尺寸动画壳，内部只保留 keyed 内容切换，把高度插值统一交给
    // 外层，避免再次出现多层尺寸动画竞争。
    return expanded
        ? KeyedSubtree(
            key: const ValueKey<String>('reasoning-expanded'),
            child: _SafeMarkdownBody(
              data: content.isEmpty ? ' ' : content,
              selectable: selectable,
              builders: builders,
              styleSheet: styleSheet,
              inlineSyntaxes: inlineSyntaxes,
              pathRoots: pathRoots,
              parseKey: parseKey,
            ),
          )
        : KeyedSubtree(
            key: const ValueKey<String>('reasoning-preview'),
            child: _MarkdownPreviewBody(
              data: content.isEmpty ? ' ' : content,
              maxHeight: _reasoningPreviewMaxHeight,
              styleSheet: styleSheet,
              builders: builders,
              inlineSyntaxes: inlineSyntaxes,
              pathRoots: pathRoots,
              parseKey: '$parseKey|reasoning-preview',
              fadeColor: fadeColor,
            ),
          );
  }
}

class _StreamingReasoningBody extends StatelessWidget {
  const _StreamingReasoningBody({
    required this.content,
    required this.expanded,
    required this.selectable,
    required this.textStyle,
    required this.fadeColor,
    required this.styleSheet,
    required this.builders,
    required this.inlineSyntaxes,
    required this.pathRoots,
    required this.parseKey,
  });

  final String content;
  final bool expanded;
  final bool selectable;
  final TextStyle? textStyle;
  final Color fadeColor;
  final MarkdownStyleSheet styleSheet;
  final Map<String, MarkdownElementBuilder> builders;
  final List<md.InlineSyntax> inlineSyntaxes;
  final List<String> pathRoots;
  final String parseKey;

  @override
  Widget build(BuildContext context) {
    final effectiveContent = content.isEmpty ? ' ' : content;
    // 流式期间若用户主动折叠（expanded=false），也展示前 5-6 行预览。
    // 这里继续不嵌内部 AnimatedSize：外层 bubble 已统一承接语义边界上的
    // 高度变化，内部只保留内容切换，避免双动画抖动。
    //
    // 2026-06-04 修复：流失追加阶段不再走 `_SafeMarkdownBody` 完整 markdown
    // 渲染路径。`_SafeMarkdownBody` 内部对 >400 字符内容走 deferred 解析,
    // 第一帧降级纯文本占位、第二帧再升级为 markdown 树,造成
    // 「plain text ↔ markdown」的逐帧高度抖动。当思考卡片占满整个窗口时,
    // 该抖动被外层 `SizeChangedLayoutNotifier` + `_scheduleScrollToBottom`
    // 的 jumpTo 捕获并把视口逐帧弹跳式拽回新底部,呈现"上蹿下跳 / 鬼畜抽搐"。
    // 正式响应卡片流式走的是 `_StreamingAssistantTextBody`(SelectableText),
    // 没有 markdown 占位/升级抖动,所以无此问题。
    //
    // 修复策略: 流失阶段与正式响应走同一套 plain text 路径,只保留文本流
    // 自身的高亮;外层 `_ReasoningBody` 在流结束后会切回完整 markdown 渲染
    // (与「流式期间 plain / 流式结束后 markdown」这一视觉切换一致)。
    return expanded
        ? KeyedSubtree(
            key: const ValueKey<String>('streaming-reasoning-plain-expanded'),
            child: StreamingTextReveal(
              textLength: effectiveContent.length,
              streaming: true,
              animateSize: false,
              child: _StreamingReasoningPlainBody(
                data: effectiveContent,
                textStyle: textStyle,
              ),
            ),
          )
        : KeyedSubtree(
            key: const ValueKey<String>('streaming-reasoning-markdown-preview'),
            child: _MarkdownPreviewBody(
              data: effectiveContent,
              maxHeight: _reasoningPreviewMaxHeight,
              styleSheet: styleSheet,
              builders: builders,
              inlineSyntaxes: inlineSyntaxes,
              pathRoots: pathRoots,
              parseKey: '$parseKey|streaming-markdown-preview',
              fadeColor: fadeColor,
            ),
          );
  }
}

/// 思考卡片流失追加阶段的纯文本渲染体。结构对齐
/// [_StreamingAssistantTextBody] / [_PlainTextMessageBody] 的 plain text
/// 路径,绕开 `_SafeMarkdownBody` 的 deferred parse 占位抖动;外层
/// `StreamingTextReveal` 仍负责流式字符的尾部 fade 高亮。
class _StreamingReasoningPlainBody extends StatelessWidget {
  const _StreamingReasoningPlainBody({required this.data, this.textStyle});

  final String data;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return SelectableText(
      data,
      // markdown 风格在流式阶段对纯文本主要体现在 p 段的 line-height
      // 与字号;直接套用上层传入的 textStyle 即可保证色、字号、字高与
      // 流结束后的 markdown 渲染一致,避免视觉跳变。
      style: textStyle,
    );
  }
}

/// 思考卡片的折叠预览高度。≈ 6 行 × 22px line-height + 小呼吸，
/// 和 WEB 端 REASONING_PREVIEW_MAX_HEIGHT_PX 对齐。
const double _reasoningPreviewMaxHeight = 142;

/// 2026-05-17 (Bug 5)：transcript 内消息卡片已统一切换到 motion token
/// （见 `_home_motion_tokens.dart` 的 `cardMotionDurationFor`），原本读取
/// `SettingsController.dialogAnimationSettings` 的 `_reasoningBodyAnimDuration`
/// helper 不再被引用，已随本次修复清理。所有调用点请直接使用 motion token。

class _CollapsibleMessageMarkdownBody extends StatefulWidget {
  const _CollapsibleMessageMarkdownBody({
    required this.data,
    required this.selectable,
    required this.styleSheet,
    required this.builders,
    required this.inlineSyntaxes,
    required this.pathRoots,
    required this.parseKey,
    required this.fadeColor,
    required this.collapseCharThreshold,
    required this.collapseLineThreshold,
    required this.previewMaxHeight,
  });

  final String data;
  final bool selectable;
  final MarkdownStyleSheet styleSheet;
  final Map<String, MarkdownElementBuilder> builders;
  final List<md.InlineSyntax> inlineSyntaxes;
  final List<String> pathRoots;
  final String parseKey;
  final Color fadeColor;
  final int collapseCharThreshold;
  final int collapseLineThreshold;
  final double previewMaxHeight;

  @override
  State<_CollapsibleMessageMarkdownBody> createState() =>
      _CollapsibleMessageMarkdownBodyState();
}

class _CollapsibleMessageMarkdownBodyState
    extends State<_CollapsibleMessageMarkdownBody> {
  late bool _collapsed = _shouldCollapse(widget.data);
  bool _userToggled = false;

  @override
  void didUpdateWidget(covariant _CollapsibleMessageMarkdownBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.parseKey != widget.parseKey) {
      _collapsed = _shouldCollapse(widget.data);
      _userToggled = false;
      return;
    }
    if (!_userToggled && oldWidget.data != widget.data) {
      _collapsed = _shouldCollapse(widget.data);
    }
  }

  bool _shouldCollapse(String value) {
    if (value.length > widget.collapseCharThreshold) {
      return true;
    }
    var lineCount = 1;
    for (final unit in value.codeUnits) {
      if (unit == 0x0A) {
        lineCount += 1;
        if (lineCount > widget.collapseLineThreshold) {
          return true;
        }
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data.isEmpty ? ' ' : widget.data;
    final shouldCollapse = _shouldCollapse(data);
    if (!shouldCollapse) {
      return _SafeMarkdownBody(
        data: data,
        selectable: widget.selectable,
        builders: widget.builders,
        styleSheet: widget.styleSheet,
        inlineSyntaxes: widget.inlineSyntaxes,
        pathRoots: widget.pathRoots,
        parseKey: widget.parseKey,
      );
    }

    final theme = Theme.of(context);
    final label = _collapsed
        ? _localizedText(context, zh: '展开完整内容', en: 'Show Full Content')
        : _localizedText(context, zh: '收起长内容', en: 'Collapse Content');
    final detailStyle =
        (theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        )) ??
        const TextStyle();
    final unitText = _localizedText(context, zh: ' 字符', en: ' chars');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: _borderRadius18,
            onTap: () {
              _BubbleHtmlInteractiveScope.maybeOf(
                context,
              )?.markInteractiveTap();
              setState(() {
                _collapsed = !_collapsed;
                _userToggled = true;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                    _collapsed
                        ? Icons.unfold_more_rounded
                        : Icons.unfold_less_rounded,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(label, style: detailStyle)),
                  Text(' · ', style: detailStyle),
                  // 字符计数翻牌：与 Token 胶囊共享同一 RollingText。
                  RollingText(text: '${data.length}', style: detailStyle),
                  Text(unitText, style: detailStyle),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        ClipRect(
          child: _collapsed
              ? KeyedSubtree(
                  key: const ValueKey<String>('message-markdown-preview'),
                  child: _MarkdownPreviewBody(
                    data: data,
                    maxHeight: widget.previewMaxHeight,
                    styleSheet: widget.styleSheet,
                    builders: widget.builders,
                    inlineSyntaxes: widget.inlineSyntaxes,
                    pathRoots: widget.pathRoots,
                    parseKey: '${widget.parseKey}|message-preview',
                    fadeColor: widget.fadeColor,
                  ),
                )
              : KeyedSubtree(
                  key: const ValueKey<String>('message-markdown-expanded'),
                  child: _SafeMarkdownBody(
                    data: data,
                    selectable: widget.selectable,
                    builders: widget.builders,
                    styleSheet: widget.styleSheet,
                    inlineSyntaxes: widget.inlineSyntaxes,
                    pathRoots: widget.pathRoots,
                    parseKey: '${widget.parseKey}|message-expanded',
                  ),
                ),
        ),
      ],
    );
  }
}

class _MarkdownPreviewBody extends StatefulWidget {
  const _MarkdownPreviewBody({
    required this.data,
    required this.maxHeight,
    required this.styleSheet,
    required this.builders,
    required this.inlineSyntaxes,
    required this.pathRoots,
    required this.parseKey,
    required this.fadeColor,
  });

  final String data;
  final double maxHeight;
  final MarkdownStyleSheet styleSheet;
  final Map<String, MarkdownElementBuilder> builders;
  final List<md.InlineSyntax> inlineSyntaxes;
  final List<String> pathRoots;
  final String parseKey;
  final Color fadeColor;

  @override
  State<_MarkdownPreviewBody> createState() => _MarkdownPreviewBodyState();
}

class _MarkdownPreviewBodyState extends State<_MarkdownPreviewBody> {
  // 预览字符上限：解析量 O(constant)，防止流式大块重复 parse/layout。
  // 1200 chars ≈ 30 行 markdown，远超 maxHeight 可见行数，
  // 可滚动后用户能看到约 15 行预览内容（约 maxHeight 的 2-3 倍）。
  static const int _previewCharCap = 1200;

  double? _contentHeight;
  final ScrollController _scrollController = ScrollController();
  bool _atBottom = false;
  // 用户滚动 Markdown 预览区期间跳过高度变化通知，防止外层视口被拽回底部。
  bool _userScrollingPreview = false;

  String get _effectiveData {
    final data = widget.data;
    if (data.length <= _previewCharCap) {
      return data;
    }
    return data.substring(0, _previewCharCap);
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final atBottom = pos.pixels >= pos.maxScrollExtent - 2;
    if (!_userScrollingPreview && pos.isScrollingNotifier.value) {
      _userScrollingPreview = true;
    }
    if (atBottom != _atBottom) setState(() => _atBottom = atBottom);
  }

  @override
  void didUpdateWidget(covariant _MarkdownPreviewBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.parseKey != widget.parseKey) {
      _contentHeight = null;
      _atBottom = false;
      _userScrollingPreview = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final measuredHeight = _contentHeight;
    final hasOverflow =
        measuredHeight != null && measuredHeight > widget.maxHeight + 0.5;
    final effectiveHeight = measuredHeight == null
        ? widget.maxHeight
        : math.min(measuredHeight, widget.maxHeight);
    // 滚到底部时淡出遮罩；初次渲染内容高度未知时先隐藏（与旧行为一致）。
    final showFade = hasOverflow && !_atBottom;
    return LayoutBuilder(
      builder: (context, constraints) {
        final constrainedWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return SizedBox(
          height: effectiveHeight,
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRect(
                  // 折叠预览体改为可滚动视图：用户无需展开即可上下浏览内容。
                  // 保留 _MeasureSize 测量实际内容高度，用于：
                  //   (1) 计算 effectiveHeight（内容较短时容器自动收缩）；
                  //   (2) 判断是否出现溢出，从而决定是否显示底部渐隐遮罩。
                  // ScrollConfiguration 隐藏滚动条（视觉简洁）。
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(
                      context,
                    ).copyWith(scrollbars: false),
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      // 内容未溢出时禁用滚动，避免与父级 ListView 争抢手势。
                      physics: hasOverflow
                          ? const BouncingScrollPhysics()
                          : const NeverScrollableScrollPhysics(),
                      child: SizedBox(
                        width: constrainedWidth,
                        child: _MeasureSize(
                          onChange: (size) {
                            if (!mounted) return;
                            if (_scrollController.hasClients &&
                                _scrollController
                                    .position
                                    .isScrollingNotifier
                                    .value) {
                              return;
                            }
                            if (_userScrollingPreview) {
                              final pos = _scrollController.position;
                              if (!pos.isScrollingNotifier.value) {
                                // 滚动已停止，启动 600ms 宽限期后重置标志
                                Future.delayed(
                                  const Duration(milliseconds: 600),
                                  () {
                                    if (mounted) {
                                      setState(
                                        () => _userScrollingPreview = false,
                                      );
                                    }
                                  },
                                );
                              }
                              return;
                            }
                            final nextHeight = size.height;
                            final currentHeight = _contentHeight;
                            if (currentHeight != null &&
                                (currentHeight - nextHeight).abs() < 0.5) {
                              return;
                            }
                            setState(() => _contentHeight = nextHeight);
                          },
                          child: _SafeMarkdownBody(
                            data: _effectiveData,
                            selectable: true,
                            builders: widget.builders,
                            styleSheet: widget.styleSheet,
                            inlineSyntaxes: widget.inlineSyntaxes,
                            pathRoots: widget.pathRoots,
                            parseKey: widget.parseKey,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // 底部渐隐遮罩：滚到底时 AnimatedOpacity 平滑淡出，
              // 告知用户已无更多预览内容（需展开查看完整正文）。
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: showFade ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            widget.fadeColor.withValues(alpha: 0),
                            widget.fadeColor.withValues(alpha: 1),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({required this.onChange, required super.child});

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderMeasureSize(onChange);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderMeasureSize renderObject,
  ) {
    renderObject.onChange = onChange;
  }
}

class _RenderMeasureSize extends RenderProxyBox {
  _RenderMeasureSize(this.onChange);

  ValueChanged<Size> onChange;
  Size? _oldSize;

  @override
  void performLayout() {
    super.performLayout();
    final newSize = child?.size;
    if (newSize == null || _oldSize == newSize) {
      return;
    }
    _oldSize = newSize;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onChange(newSize);
    });
  }
}

class _MessageMarkdownThemeData {
  const _MessageMarkdownThemeData({required this.styleSheet});

  factory _MessageMarkdownThemeData.fromMessageBubble({
    required ThemeData theme,
    required Color backgroundColor,
    required Color textColor,
    required bool useDarkCodeSurface,
  }) {
    // 阶段㉒：进程级缓存。`MarkdownStyleSheet.fromTheme + copyWith` 创建
    // 数十个 TextStyle / BoxDecoration，60+ 长会话首次打开会重复触发
    // N 次。按 (theme palette + bubble bg + text color + dark surface)
    // 签名命中率极高（同 role/状态的 bubble 共享同一份 stylesheet），
    // 命中后跳过整个工厂方法的重建工作。
    final cacheKey = Object.hashAll(<Object?>[
      theme.brightness.index,
      theme.colorScheme.primary.toARGB32(),
      theme.colorScheme.primaryContainer.toARGB32(),
      theme.textTheme.bodyLarge?.fontSize,
      theme.textTheme.bodyMedium?.fontSize,
      backgroundColor.toARGB32(),
      textColor.toARGB32(),
      useDarkCodeSurface,
    ]);
    final cached = _markdownThemeDataCache[cacheKey];
    if (cached != null) {
      _markdownThemeDataCache.remove(cacheKey);
      _markdownThemeDataCache[cacheKey] = cached; // touch LRU
      return cached;
    }
    final result = _buildFromMessageBubble(
      theme: theme,
      backgroundColor: backgroundColor,
      textColor: textColor,
      useDarkCodeSurface: useDarkCodeSurface,
    );
    _markdownThemeDataCache[cacheKey] = result;
    while (_markdownThemeDataCache.length > 64) {
      _markdownThemeDataCache.remove(_markdownThemeDataCache.keys.first);
    }
    return result;
  }

  static _MessageMarkdownThemeData _buildFromMessageBubble({
    required ThemeData theme,
    required Color backgroundColor,
    required Color textColor,
    required bool useDarkCodeSurface,
  }) {
    final colorScheme = theme.colorScheme;
    final palette = theme.extension<OpenHandPalette>();
    final bubbleIsDark =
        ThemeData.estimateBrightnessForColor(backgroundColor) ==
        Brightness.dark;
    final overlayBase = bubbleIsDark ? Colors.white : Colors.black;
    final subtleSurface = Color.alphaBlend(
      overlayBase.withValues(alpha: bubbleIsDark ? 0.06 : 0.035),
      backgroundColor,
    );
    final elevatedSurface = Color.alphaBlend(
      overlayBase.withValues(alpha: bubbleIsDark ? 0.11 : 0.06),
      backgroundColor,
    );
    final accentColor = bubbleIsDark
        ? Color.lerp(colorScheme.primaryContainer, Colors.white, 0.08) ??
              colorScheme.primaryContainer
        : colorScheme.primary;
    final linkColor = bubbleIsDark
        ? Color.lerp(accentColor, Colors.white, 0.08) ?? accentColor
        : accentColor;
    final borderColor =
        palette?.outlineSoft.withValues(alpha: bubbleIsDark ? 0.72 : 0.88) ??
        Color.alphaBlend(
          overlayBase.withValues(alpha: bubbleIsDark ? 0.18 : 0.12),
          backgroundColor,
        );
    final quoteSurface = Color.alphaBlend(
      accentColor.withValues(alpha: bubbleIsDark ? 0.22 : 0.10),
      elevatedSurface,
    );
    final secondaryTextColor = textColor.withValues(
      alpha: bubbleIsDark ? 0.92 : 0.88,
    );
    final bodyStyle =
        theme.textTheme.bodyLarge?.copyWith(color: textColor, height: 1.55) ??
        TextStyle(color: textColor, height: 1.55);
    final tableBodyStyle =
        theme.textTheme.bodyMedium?.copyWith(color: textColor, height: 1.5) ??
        TextStyle(color: textColor, height: 1.5);
    final codeStyle =
        theme.textTheme.bodyMedium?.copyWith(
          color: textColor,
          fontFamily: 'monospace',
          fontSize: (theme.textTheme.bodyMedium?.fontSize ?? 14) * 0.94,
          backgroundColor: subtleSurface,
        ) ??
        TextStyle(
          color: textColor,
          fontFamily: 'monospace',
          backgroundColor: subtleSurface,
        );
    return _MessageMarkdownThemeData(
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        a: bodyStyle.copyWith(
          color: linkColor,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
          decorationColor: linkColor.withValues(alpha: 0.78),
        ),
        p: bodyStyle,
        code: codeStyle,
        em: bodyStyle.copyWith(fontStyle: FontStyle.italic),
        strong: bodyStyle.copyWith(fontWeight: FontWeight.w700),
        blockquote: bodyStyle.copyWith(color: secondaryTextColor),
        listBullet: bodyStyle.copyWith(
          color: secondaryTextColor,
          fontWeight: FontWeight.w700,
        ),
        listBulletPadding: const EdgeInsets.only(right: 8),
        tableHead: bodyStyle.copyWith(fontWeight: FontWeight.w700),
        tableBody: tableBodyStyle,
        tableBorder: TableBorder.all(color: borderColor),
        tableCellsPadding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        tableCellsDecoration: BoxDecoration(color: subtleSurface),
        tableHeadCellsPadding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        tableHeadCellsDecoration: BoxDecoration(color: elevatedSurface),
        tableColumnWidth: const IntrinsicColumnWidth(),
        blockquotePadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        blockquoteDecoration: BoxDecoration(
          color: quoteSurface,
          borderRadius: _borderRadius18,
          border: Border(left: BorderSide(color: accentColor, width: 3)),
        ),
        // Message bubbles render fenced code blocks through the custom
        // `_HighlightedCodeBlockBuilder`, and `flutter_markdown_plus`
        // still wraps every `pre` in `codeblockDecoration`. Keep the
        // markdown-level wrapper inert here so only the highlighted panel
        // owns the visible border/radius; otherwise the two shells drift
        // apart (14 vs 18 radius) and create a double-outline ghost.
        //
        // 注意: flutter_markdown_plus 的 builder.dart 对 `pre` 元素强制
        // 设置了 `clipBehavior: Clip.hardEdge`。如果 codeblockDecoration
        // 的 borderRadius 为 null (默认 BorderRadius.zero), 则子组件
        // (_HighlightedCodePanel) 的圆角会被矩形裁剪掉。因此这里必须
        // 给 codeblockDecoration 设置比代码面板稍大的 borderRadius (19
        // vs 18), 让 clip path 完全包含内层 Border.all 的外边缘像素,
        // 避免 Clip.hardEdge 在圆角处裁掉边框。
        codeblockPadding: EdgeInsets.zero,
        codeblockDecoration: const BoxDecoration(borderRadius: _borderRadius19),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: borderColor, width: 1.2)),
        ),
      ),
    );
  }

  final MarkdownStyleSheet styleSheet;
}

/// 阶段㉒：[_MessageMarkdownThemeData] 的 LRU 缓存。容量 64 足以覆盖
/// 「亮/暗 × user/assistant/tool/reasoning × 选中/未选中」全部组合。
final LinkedHashMap<int, _MessageMarkdownThemeData> _markdownThemeDataCache =
    LinkedHashMap<int, _MessageMarkdownThemeData>();

class _SafeMarkdownBody extends StatefulWidget {
  const _SafeMarkdownBody({
    required this.data,
    required this.styleSheet,
    this.selectable = false,
    this.builders = const <String, MarkdownElementBuilder>{},
    this.inlineSyntaxes = const <md.InlineSyntax>[],
    this.pathRoots = const <String>[],
    this.parseKey = '',
  });

  final String data;
  final MarkdownStyleSheet styleSheet;
  final bool selectable;
  final Map<String, MarkdownElementBuilder> builders;
  final List<md.InlineSyntax> inlineSyntaxes;
  final List<String> pathRoots;
  final String parseKey;

  @override
  State<_SafeMarkdownBody> createState() => _SafeMarkdownBodyState();
}

// Markdown bodies above this size get a one-frame delayed parse: on the
// first frame we paint a plain-text placeholder so the transcript reveal /
// scroll lands instantly, then upgrade to the rich Markdown widget tree on
// the next frame.
//
// 阶段⑳ — 从 1.5 KiB 下调到 800 字节：含多代码块的消息（如截图所示
// 3个bash代码块）总字符数通常在 1000–3000 范围，但 markdown 解析 +
// MarkdownBuilder.build() + 每个代码块的 widget 构造叠加起来就是
// 主线程的致命负担。将阈值降到 800 字节让几乎所有含代码块的消息都
// 走 deferred 路径，首帧仅渲染纯文本，下一帧再构建富文本树。
// 阶段㉒ — 800 → 400：用户反馈 60+ 条历史消息会话首次打开仍卡顿，原因
// 是历史里很多 ~600 字节的中等长度消息绕过了 deferred 路径，几张同帧
// 同步解析就把 16 ms 帧预算撑爆。再降一档把更多消息纳入帧节流。
const int _markdownDeferredParseThresholdChars = 400;

/// 阶段㉒：进程级 AST 解析结果缓存。同一段 markdown 内容（按内容 +
/// 主题/builder 签名 hash 索引）在多次 mount 之间复用 AST 节点，
/// 避免「滚回去再滚回来」「跨会话引用同一段示例代码」时反复跑
/// `md.Document.parseLines()`。AST 节点是纯数据结构，体积远小于
/// 构建出的 widget 树，整体内存压力可控；512 entries 对单条 ~几 KiB
/// 的消息内容已经足够覆盖典型 60+ 长会话。
class _MarkdownAstCache {
  _MarkdownAstCache();

  static const int _maxEntries = 512;
  final LinkedHashMap<int, List<md.Node>> _entries =
      LinkedHashMap<int, List<md.Node>>();

  List<md.Node>? get(int key) {
    final value = _entries.remove(key);
    if (value != null) {
      _entries[key] = value;
    }
    return value;
  }

  void put(int key, List<md.Node> value) {
    _entries.remove(key);
    _entries[key] = value;
    while (_entries.length > _maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }
}

final _MarkdownAstCache _markdownAstCache = _MarkdownAstCache();

/// 阶段㉑：全局帧节流的 markdown 解析调度器。
///
/// 在打开存量会话或快速切换会话时，多张消息卡片会在「同一帧」内同时
/// 调用 `addPostFrameCallback` 注册 deferred 解析，结果下一帧仍要在
/// 主线程串行跑 N 次 `_parseMarkdown()`，单帧时间常常突破 16ms 预算
/// 直接触发 ANR。本调度器把 N 个解析任务拆分到 ceil(N/_maxPerFrame)
/// 帧里执行，与 [_HighlightFrameScheduler] 思路一致 —— 牺牲数十毫秒的
/// 完整渲染时间换取主线程持续 60 FPS 的丝滑感。
class _MarkdownFrameScheduler {
  _MarkdownFrameScheduler._();
  static final instance = _MarkdownFrameScheduler._();

  final List<VoidCallback> _pending = <VoidCallback>[];
  bool _draining = false;

  /// 每帧最多执行的 markdown 解析任务数。1 条足以让首屏视觉焦点
  /// (最新消息) 第一时间从纯文本占位升级到完整 markdown 渲染，剩余
  /// 卡片按帧节奏陆续到位；保持 1/帧 严格守住 16 ms 单帧预算，避免
  /// 单条带多代码块的长消息把帧预算撑爆触发 jank/ANR。
  static const int _maxPerFrame = 1;

  void schedule(VoidCallback task) {
    _pending.add(task);
    if (!_draining) {
      _draining = true;
      WidgetsBinding.instance.addPostFrameCallback(_drain);
    }
  }

  void _drain(Duration _) {
    if (_pending.isEmpty) {
      _draining = false;
      return;
    }
    final batch = _pending.length <= _maxPerFrame
        ? List<VoidCallback>.from(_pending)
        : _pending.sublist(0, _maxPerFrame);
    _pending.removeRange(0, batch.length);
    for (final task in batch) {
      task();
    }
    if (_pending.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(_drain);
    } else {
      _draining = false;
    }
  }
}

class _SafeMarkdownBodyState extends State<_SafeMarkdownBody>
    implements MarkdownBuilderDelegate {
  List<Widget>? _children;
  final List<GestureRecognizer> _recognizers = <GestureRecognizer>[];
  int? _lastThemeSignature;
  String? _lastData;
  bool? _lastSelectable;
  String? _lastBuilderSignature;
  String? _lastParseKey;
  bool _deferredParseScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final themeSignature = _computeThemeSignature();
    if (_children == null || _lastThemeSignature != themeSignature) {
      _lastThemeSignature = themeSignature;
      _parseMarkdownMaybeDeferred(initial: _children == null);
    }
  }

  @override
  void didUpdateWidget(covariant _SafeMarkdownBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    final builderSignature = _builderSignature();
    if (_lastData != widget.data ||
        _lastSelectable != widget.selectable ||
        _lastBuilderSignature != builderSignature ||
        _lastParseKey != widget.parseKey) {
      _parseMarkdownMaybeDeferred(initial: false);
      return;
    }
    final themeSignature = _computeThemeSignature();
    if (_lastThemeSignature != themeSignature) {
      _lastThemeSignature = themeSignature;
      _parseMarkdownMaybeDeferred(initial: false);
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  /// Decides whether to parse synchronously or defer to the next frame.
  ///
  /// On the FIRST mount of a non-trivial body we paint a cheap plain-text
  /// stand-in immediately and queue the real parse via the global
  /// [_MarkdownFrameScheduler]. This unblocks the frame that mounts a freshly
  /// opened transcript, which may contain a dozen+ such bubbles all
  /// competing for parse time. Subsequent updates parse synchronously to
  /// avoid mid-conversation flicker.
  /// 阶段⑳：无论是首次挂载还是展开触发的重建，只要内容超过阈值就走
  /// deferred 路径。这是解决"展开含多代码块消息时ANR"的关键：展开时
  /// 新的 _SafeMarkdownBody 被创建（initial=true），但即使是非 initial
  /// 的更新（如流式追加），大内容也应该 defer 以避免阻塞当前帧。
  /// 阶段㉑：deferred 任务交由 [_MarkdownFrameScheduler] 帧节流。同帧内
  /// 多个 bubble 一起注册时，每帧只跑 2 个 markdown 解析，剩余排队到
  /// 下一帧，避免 N 张卡片同时 parse 把单帧预算撑爆触发 ANR。
  void _parseMarkdownMaybeDeferred({required bool initial}) {
    if (widget.data.length > _markdownDeferredParseThresholdChars &&
        widget.data.length <= _markdownPlainTextSkipThresholdChars &&
        !_canRenderMarkdownAsPlainText(widget.data)) {
      // 2026-05-25 — 流式抽搐修复：仅在「真·首挂载」（_children == null）
      // 时铺纯文本占位；后续 didUpdateWidget（流式 chunk / 主题变化）路径
      // 保留上一帧已解析好的富文本，等帧节流回调 setState 再无缝替换。
      // 之前每次 chunk 都把 _children 推回纯文本，造成「rich → plain
      // (看起来像折叠摘要) → rich」反复闪烁。
      if (_children == null) {
        _renderPlainTextPlaceholder();
      }
      if (!_deferredParseScheduled) {
        _deferredParseScheduled = true;
        _MarkdownFrameScheduler.instance.schedule(() {
          if (!mounted) {
            _deferredParseScheduled = false;
            return;
          }
          _deferredParseScheduled = false;
          setState(_parseMarkdown);
        });
      }
      return;
    }
    _parseMarkdown();
  }

  void _renderPlainTextPlaceholder() {
    final effectiveStyleSheet = MarkdownStyleSheet.fromTheme(
      Theme.of(context),
    ).merge(widget.styleSheet);
    final normalizedSource = _sanitizeMarkdownSource(
      widget.data.isEmpty ? ' ' : widget.data,
    );
    _disposeRecognizers();
    _children = <Widget>[
      widget.selectable
          ? SelectableText(normalizedSource, style: effectiveStyleSheet.p)
          : Text(normalizedSource, style: effectiveStyleSheet.p),
    ];
  }

  void _parseMarkdown() {
    developer.Timeline.startSync(
      'openhand.markdown.parse',
      arguments: <String, Object?>{'chars': widget.data.length},
    );
    try {
      _parseMarkdownInner();
    } finally {
      developer.Timeline.finishSync();
    }
  }

  void _parseMarkdownInner() {
    final effectiveStyleSheet = MarkdownStyleSheet.fromTheme(
      Theme.of(context),
    ).merge(widget.styleSheet);
    final normalizedSource = _sanitizeMarkdownSource(
      widget.data.isEmpty ? ' ' : widget.data,
    );
    _lastThemeSignature = _computeThemeSignature();
    _lastData = widget.data;
    _lastSelectable = widget.selectable;
    _lastBuilderSignature = _builderSignature();
    _lastParseKey = widget.parseKey;
    _disposeRecognizers();
    if (_canRenderMarkdownAsPlainText(widget.data)) {
      _children = <Widget>[
        widget.selectable
            ? SelectableText(normalizedSource, style: effectiveStyleSheet.p)
            : Text(normalizedSource, style: effectiveStyleSheet.p),
      ];
      return;
    }
    // Hard size ceiling: very large messages (long log dumps, generated
    // payloads pasted into the chat) blow up the markdown parser + builder
    // — both run synchronously on the UI thread and produce visible
    // freezes when opening the transcript. Fall back to plain text; users
    // can still copy / select the body. The threshold (~120KB) is well
    // above any natural human-authored markdown but below the size at
    // which the parser starts to dominate frame budgets.
    if (widget.data.length > _markdownPlainTextSkipThresholdChars) {
      _children = <Widget>[
        widget.selectable
            ? SelectableText(normalizedSource, style: effectiveStyleSheet.p)
            : Text(normalizedSource, style: effectiveStyleSheet.p),
      ];
      return;
    }
    try {
      // 阶段㉒：先查 AST 缓存。命中则直接复用，跳过昂贵的
      // `md.Document.parseLines` + `_sanitizeMarkdownAst`。MarkdownBuilder
      // 的 widget 构造仍按当前主题样式 fresh 跑一次，避免主题切换时
      // 残留旧色。
      final astCacheKey = Object.hashAll(<Object?>[
        normalizedSource,
        widget.parseKey,
        widget.inlineSyntaxes.length,
        for (final syn in widget.inlineSyntaxes) syn.runtimeType,
      ]);
      final cachedAst = _markdownAstCache.get(astCacheKey);
      final List<md.Node> astNodes;
      if (cachedAst != null) {
        astNodes = cachedAst;
      } else {
        final document = md.Document(
          extensionSet: md.ExtensionSet.gitHubFlavored,
          inlineSyntaxes: widget.inlineSyntaxes,
          encodeHtml: false,
        );
        astNodes = document.parseLines(
          const LineSplitter().convert(normalizedSource),
        );
        _sanitizeMarkdownAst(astNodes);
        _markdownAstCache.put(astCacheKey, astNodes);
      }
      final builder = MarkdownBuilder(
        delegate: this,
        selectable: widget.selectable,
        styleSheet: effectiveStyleSheet,
        imageDirectory: null,
        imageBuilder: _buildMarkdownImage,
        checkboxBuilder: null,
        bulletBuilder: null,
        builders: widget.builders,
        paddingBuilders: const <String, MarkdownPaddingBuilder>{},
        fitContent: true,
        listItemCrossAxisAlignment: MarkdownListItemCrossAxisAlignment.baseline,
      );
      _children = builder.build(astNodes);
    } catch (_) {
      _children = <Widget>[
        widget.selectable
            ? SelectableText(widget.data, style: effectiveStyleSheet.p)
            : Text(widget.data, style: effectiveStyleSheet.p),
      ];
    }
  }

  int _computeThemeSignature() {
    final theme = Theme.of(context);
    return Object.hashAll(<Object?>[
      theme.brightness,
      theme.colorScheme.surface.toARGB32(),
      theme.colorScheme.onSurface.toARGB32(),
      theme.colorScheme.primary.toARGB32(),
      widget.styleSheet.hashCode,
      widget.styleSheet.p?.color?.toARGB32(),
      widget.styleSheet.code?.color?.toARGB32(),
    ]);
  }

  String _builderSignature() {
    final keys = widget.builders.keys.toList(growable: false)..sort();
    return keys.join('|');
  }

  static final RegExp _setextEscapePattern = RegExp(
    r'(^|\n)(\s*)(=+|\^+)(?=\n|$)',
  );

  /// Matches scaffolding lines that sometimes leak from models into the
  /// visible markdown body, e.g. a bare `Tool: Bash`, `工具: Bash`,
  /// `工具调用：xxx`, `[tool_call] ...`, or `function_calls: ...`.
  ///
  /// These come from the model's own chain-of-thought / training data and
  /// should be rendered by the structured tool-call bubble, not as plain text.
  /// We strip them before markdown parsing to keep transcripts clean.
  static final RegExp _toolScaffoldingLinePattern = RegExp(
    r'^\s*(?:'
    r'tool\s*:\s*\w[\w\-\.]*'
    r'|工具\s*[:：]\s*\w[\w\-\.]*'
    r'|工具调用\s*[:：].*'
    r'|\[?tool_call\]?\s*[:：]?\s*.*'
    r'|function_calls?\s*[:：].*'
    r'|<?function_calls?>?\s*$'
    r'|</?invoke[^>]*>\s*$'
    r')\s*$',
    caseSensitive: false,
    multiLine: true,
  );

  String _sanitizeMarkdownSource(String source) {
    final normalized = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final normalizedFences = _normalizeInlineFencedCodeBlocks(normalized);
    final stripped = _stripToolScaffolding(normalizedFences);
    return _closeUnterminatedFencedCodeBlock(stripped).replaceAllMapped(
      _setextEscapePattern,
      (match) => '${match[1]}${match[2]}\\${match[3]}',
    );
  }

  static final RegExp _inlineFencedBlockLinePattern = RegExp(
    r'^( {0,3})(`{3,}|~{3,})([^\n]*)$',
  );
  static final RegExp _fenceInfoTokenPattern = RegExp(
    r'^([A-Za-z0-9_+#\.-]+)(?:\s+|$)',
  );

  String _normalizeInlineFencedCodeBlocks(String source) {
    if (source.isEmpty || !source.contains('```') && !source.contains('~~~')) {
      return source;
    }
    final lines = source.split('\n');
    var changed = false;
    final normalizedLines = <String>[];
    for (final line in lines) {
      final match = _inlineFencedBlockLinePattern.firstMatch(line);
      if (match == null) {
        normalizedLines.add(line);
        continue;
      }
      final indent = match.group(1)!;
      final fence = match.group(2)!;
      final afterFence = match.group(3)!;
      final closingIndex = afterFence.lastIndexOf(fence);
      if (closingIndex <= 0) {
        normalizedLines.add(line);
        continue;
      }
      final inlineSegment = afterFence.substring(0, closingIndex).trimLeft();
      final trailingSegment = afterFence.substring(closingIndex + fence.length);
      if (inlineSegment.isEmpty) {
        normalizedLines.add(line);
        continue;
      }
      String openingFence = '$indent$fence';
      var codeBody = inlineSegment;
      final infoMatch = _fenceInfoTokenPattern.firstMatch(inlineSegment);
      if (infoMatch != null) {
        final infoToken = infoMatch.group(1)!;
        final remainder = inlineSegment.substring(infoMatch.end).trimLeft();
        if (remainder.isNotEmpty) {
          openingFence = '$openingFence$infoToken';
          codeBody = remainder;
        }
      }
      if (codeBody.trim().isEmpty) {
        normalizedLines.add(line);
        continue;
      }
      changed = true;
      normalizedLines.add(openingFence);
      normalizedLines.add(codeBody.trimRight());
      normalizedLines.add('$indent$fence');
      final trailing = trailingSegment.trimLeft();
      if (trailing.isNotEmpty) {
        normalizedLines.add(trailing);
      }
    }
    if (!changed) {
      return source;
    }
    return normalizedLines.join('\n');
  }

  /// Removes scaffolding-only lines while **preserving** any line inside a
  /// fenced code block — users may legitimately write `Tool: Bash` inside
  /// a code sample. We track fence state (``` / ~~~) and only strip in prose.
  String _stripToolScaffolding(String source) {
    if (!_toolScaffoldingLinePattern.hasMatch(source)) {
      return source;
    }
    final lines = source.split('\n');
    final buffer = StringBuffer();
    var inFence = false;
    String? fenceMarker;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trimLeft();
      if (inFence) {
        if (fenceMarker != null && trimmed.startsWith(fenceMarker)) {
          inFence = false;
          fenceMarker = null;
        }
        buffer.write(line);
        if (i != lines.length - 1) buffer.write('\n');
        continue;
      }
      if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
        inFence = true;
        fenceMarker = trimmed.startsWith('```') ? '```' : '~~~';
        buffer.write(line);
        if (i != lines.length - 1) buffer.write('\n');
        continue;
      }
      if (_toolScaffoldingLinePattern.hasMatch(line)) {
        // Drop the scaffolding line entirely (including its newline).
        continue;
      }
      buffer.write(line);
      if (i != lines.length - 1) buffer.write('\n');
    }
    return buffer.toString();
  }

  void _sanitizeMarkdownAst(List<md.Node> nodes) {
    for (final node in nodes) {
      if (node is! md.Element) {
        continue;
      }
      final attributes = node.attributes;
      // Defensively scrub any attribute whose value is consumed by
      // flutter_markdown_plus via `int.parse(...)` (currently only `start`
      // on ordered lists). If upstream ever widens the set we simply add the
      // attribute name here.
      if (node.tag == 'ol') {
        final start = attributes['start'];
        if (start == null || int.tryParse(start.trim()) == null) {
          attributes.remove('start');
        } else {
          // Normalize to a trimmed decimal representation so int.parse
          // cannot choke on stray whitespace or leading '+' signs.
          attributes['start'] = int.parse(start.trim()).toString();
        }
      }
      final children = node.children;
      if (children != null && children.isNotEmpty) {
        _sanitizeMarkdownAst(children);
      }
    }
  }

  void _disposeRecognizers() {
    if (_recognizers.isEmpty) {
      return;
    }
    final localRecognizers = List<GestureRecognizer>.from(_recognizers);
    _recognizers.clear();
    for (final recognizer in localRecognizers) {
      recognizer.dispose();
    }
  }

  Widget _buildMarkdownImage(Uri uri, String? title, String? alt) {
    final label = (alt ?? title ?? uri.toString()).trim();
    final resolvedFilePath = _resolveMarkdownImageFilePath(uri);
    if (resolvedFilePath != null &&
        _cachedMarkdownImageFileExists(resolvedFilePath)) {
      final previewTitle = label.isEmpty ? p.basename(resolvedFilePath) : label;
      return _wrapMarkdownImageTap(
        semanticsLabel: previewTitle,
        onTap: () {
          if (!mounted) {
            return;
          }
          showAnimatedDialog<void>(
            context: context,
            builder: (ctx) => _ImagePreviewDialog.file(
              filePath: resolvedFilePath,
              title: previewTitle,
            ),
          );
        },
        child: _buildMarkdownImageFrame(
          context,
          Image.file(
            File(resolvedFilePath),
            fit: BoxFit.contain,
            // Inline thumbnail constrained by _buildMarkdownImageFrame to
            // 60% screen width / 400 height. Decode at 1280 logical px to
            // cover most desktop sizes at 2x DPR; full-resolution image is
            // shown via the dedicated preview dialog on tap.
            cacheWidth: 1280,
            frameBuilder: _fadeInImageFrameBuilder,
            errorBuilder: (_, _, _) =>
                _brokenImagePlaceholder(context, previewTitle),
          ),
        ),
      );
    }
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      final urlString = uri.toString();
      final previewTitle = label.isEmpty ? urlString : label;
      // 检查是否已有本地缓存 (上次网络加载成功后后台缓存的副本)。
      final cachedPath = MediaCacheService.instance.cachedPathForUrl(urlString);
      if (cachedPath != null && _cachedMarkdownImageFileExists(cachedPath)) {
        return _wrapMarkdownImageTap(
          semanticsLabel: previewTitle,
          onTap: () {
            if (!mounted) return;
            showAnimatedDialog<void>(
              context: context,
              builder: (ctx) => _ImagePreviewDialog.file(
                filePath: cachedPath,
                title: previewTitle,
              ),
            );
          },
          child: _buildMarkdownImageFrame(
            context,
            Image.file(
              File(cachedPath),
              fit: BoxFit.contain,
              cacheWidth: 1280,
              frameBuilder: _fadeInImageFrameBuilder,
              errorBuilder: (_, _, _) =>
                  _brokenImagePlaceholder(context, previewTitle),
            ),
          ),
        );
      }
      // 无本地缓存: 走网络加载, 成功后触发后台缓存。
      return _wrapMarkdownImageTap(
        semanticsLabel: previewTitle,
        onTap: () {
          if (!mounted) return;
          showAnimatedDialog<void>(
            context: context,
            builder: (ctx) =>
                _ImagePreviewDialog.network(imageUri: uri, title: previewTitle),
          );
        },
        child: _buildMarkdownImageFrame(
          context,
          Image.network(
            urlString,
            fit: BoxFit.contain,
            cacheWidth: 1280,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              // 图片帧解码完成 → 触发后台缓存。
              if (frame != null) {
                MediaCacheService.instance.cacheInBackground(urlString);
              }
              return _fadeInImageFrameBuilder(
                context,
                child,
                frame,
                wasSynchronouslyLoaded,
              );
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              final total = loadingProgress.expectedTotalBytes;
              final progress = total != null && total > 0
                  ? loadingProgress.cumulativeBytesLoaded / total
                  : null;
              return SizedBox(
                width: 200,
                height: 200,
                child: Center(
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 2.4,
                  ),
                ),
              );
            },
            errorBuilder: (_, _, _) =>
                _brokenImagePlaceholder(context, previewTitle),
          ),
        ),
      );
    }
    return Text(label.isEmpty ? uri.toString() : label);
  }

  String? _resolveMarkdownImageFilePath(Uri uri) {
    if (uri.scheme == 'file') {
      try {
        return uri.toFilePath();
      } catch (_) {
        return null;
      }
    }
    if (uri.scheme.isEmpty && uri.path.startsWith('/')) {
      try {
        return Uri.decodeFull(uri.path);
      } catch (_) {
        return uri.path;
      }
    }
    if (uri.scheme.isEmpty) {
      final href = _decodeMarkdownImageHref(uri);
      final resolved = resolveMarkdownMessageLinkPath(href, widget.pathRoots);
      if (resolved != null && !resolved.isDirectory) {
        return resolved.resolvedPath;
      }
    }
    return null;
  }

  String _decodeMarkdownImageHref(Uri uri) {
    final raw = uri.toString();
    try {
      return Uri.decodeFull(raw);
    } catch (_) {
      return raw;
    }
  }

  Widget _buildMarkdownImageFrame(BuildContext context, Widget image) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.6,
          maxHeight: 400,
        ),
        child: image,
      ),
    );
  }

  Widget _wrapMarkdownImageTap({
    required String semanticsLabel,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Semantics(
        button: true,
        label: semanticsLabel,
        child: Builder(
          builder: (ctx) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _BubbleHtmlInteractiveScope.maybeOf(ctx)?.markInteractiveTap();
              onTap();
            },
            child: child,
          ),
        ),
      ),
    );
  }

  /// Shared frame builder that fades in images with a smooth animation.
  static Widget _fadeInImageFrameBuilder(
    BuildContext context,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) {
    if (wasSynchronouslyLoaded) return child;
    if (frame == null) {
      // No frame decoded yet — show shimmer placeholder.
      return const _ImageShimmerPlaceholder();
    }
    // First frame decoded — fade in with a one-shot animation.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      builder: (context, value, child) => Opacity(opacity: value, child: child),
      child: child,
    );
  }

  static Widget _brokenImagePlaceholder(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.broken_image_outlined,
            size: 18,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  @override
  GestureRecognizer createLink(String text, String? href, String title) {
    final recognizer = TapGestureRecognizer();
    _recognizers.add(recognizer);
    final resolvedPath = resolveMarkdownMessageLinkPath(href, widget.pathRoots);
    if (resolvedPath != null) {
      recognizer.onTap = () {
        _BubbleHtmlInteractiveScope.maybeOf(context)?.markInteractiveTap();
        unawaited(_openResolvedMessagePath(context, resolvedPath));
      };
      return recognizer;
    }
    final externalUri = parseSupportedMessageLinkUri(href);
    if (externalUri != null) {
      recognizer.onTap = () {
        _BubbleHtmlInteractiveScope.maybeOf(context)?.markInteractiveTap();
        unawaited(_openMessageLinkUri(context, externalUri));
      };
    }
    return recognizer;
  }

  static final RegExp _trailingNewlinePattern = RegExp(r'\n$');

  @override
  TextSpan formatText(MarkdownStyleSheet styleSheet, String code) {
    final normalizedCode = code.replaceAll(_trailingNewlinePattern, '');
    final resolvedPath = resolveExistingMessagePath(
      normalizedCode,
      widget.pathRoots,
    );
    if (resolvedPath == null) {
      return TextSpan(text: normalizedCode, style: styleSheet.code);
    }
    final recognizer = TapGestureRecognizer()
      ..onTap = () {
        _BubbleHtmlInteractiveScope.maybeOf(context)?.markInteractiveTap();
        unawaited(_openResolvedMessagePath(context, resolvedPath));
      };
    _recognizers.add(recognizer);
    final linkColor = Theme.of(context).colorScheme.primary;
    return TextSpan(
      text: normalizedCode,
      recognizer: recognizer,
      style: styleSheet.code?.copyWith(
        color: linkColor,
        decoration: TextDecoration.underline,
        decorationColor: linkColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final children = _children;
    if (children == null || children.isEmpty) {
      return const SizedBox.shrink();
    }
    final body = children.length == 1
        ? children.single
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          );
    if (!widget.selectable) return body;
    // 2026-06-04 修复：跨多行 select 选中 BUG。
    //
    // 旧实现直接用 `SelectionArea(child: body)`，但 `SelectionArea` 内部
    // 是 `SelectableRegion`，其 `add(Selectable)` 强制 `assert(_selectable == null)`，
    // 一棵子树里只能注册一个 `Selectable`。而 `flutter_markdown_plus` 的
    // `MarkdownBuilder.build()` 会把每个段落、列表项、表格 cell 各生成
    // 一个独立带 `UniqueKey()` 的 `SelectableText.rich`，多个 `Selectable`
    // 同时竞争 `SelectableRegion` 的注册 — 只有最后一个能成功，其余全部
    // 沦为「选择孤岛」，用户在孤岛之间拖拽就会被卡死，体感是「只能选一行」。
    //
    // 修复策略：在 `SelectionArea` 与 body 之间再嵌一层 `SelectionContainer`，
    // 它本身是一个 `Selectable` 节点，对外层 `SelectionArea` 暴露为唯一
    // 注册项；其 delegate 维护内部 N 个 `Selectable`（各 `SelectableText.rich`
    // + 代码块内 `SelectableText.rich`），把跨节点的 selection event 派发到
    // 命中节点。`MultiSelectableSelectionContainerDelegate` 未从
    // `package:flutter/widgets.dart` 公开导出（仅由 `SelectableRegion`
    // 内部持有），这里以最简实现覆盖核心需求：拖选/选词/选段/全选/清除
    // 在多个 `Selectable` 之间正确串联。
    return SelectionArea(child: _MarkdownSelectionContainer(child: body));
  }
}

/// 维持 markdown 树内多个 `SelectableText.rich` 节点的统一选择 registrar。
///
/// Flutter 内部用 `MultiSelectableSelectionContainerDelegate`（1000+ 行）支撑
/// `SelectableRegion` 跨多 `Selectable` 行为，但该类未从公开 API 导出。
/// 这里给 markdown 体专门写一个聚焦「选择区域派发」的精简版：
/// - `add` / `remove` 维护 N 个 `Selectable` 列表（按文档顺序）；
/// - `dispatchSelectionEvent` 路由到命中指针位置的 `Selectable`,
///   并在拖选过程中追踪 start/end `Selectable` 以串联跨节点选区；
/// - `getSelectedContent` / `value` 汇总整棵子树的 selection geometry。
class _MarkdownSelectionDelegate extends SelectionContainerDelegate
    with ChangeNotifier {
  final List<Selectable> _selectables = <Selectable>[];
  bool _disposed = false;
  SelectionGeometry _geometry = const SelectionGeometry(
    status: SelectionStatus.none,
    hasContent: false,
  );
  // 跨节点拖选时锁定 start/end 节点,让中间 `Selectable` 同步全选。
  Selectable? _anchorStart;
  Selectable? _anchorEnd;

  @override
  void add(Selectable selectable) {
    if (_disposed) return;
    _selectables.add(selectable);
    _sortSelectables();
    selectable.addListener(_onSelectableChanged);
    _refreshGeometry();
  }

  @override
  void remove(Selectable selectable) {
    if (_disposed) return;
    selectable.removeListener(_onSelectableChanged);
    _selectables.remove(selectable);
    if (_anchorStart == selectable) _anchorStart = null;
    if (_anchorEnd == selectable) _anchorEnd = null;
    _refreshGeometry(notify: false);
  }

  void _onSelectableChanged() {
    if (_disposed) return;
    _refreshGeometry();
  }

  void _sortSelectables() {
    Rect? firstGlobalRectOf(Selectable selectable) {
      try {
        if (selectable.boundingBoxes.isEmpty) return null;
        return MatrixUtils.transformRect(
          selectable.getTransformTo(null),
          selectable.boundingBoxes.first,
        );
      } catch (_) {
        return null;
      }
    }

    _selectables.sort((a, b) {
      final rectA = firstGlobalRectOf(a);
      final rectB = firstGlobalRectOf(b);
      if (rectA == null || rectB == null) return 0;
      final dy = rectA.top - rectB.top;
      if (dy.abs() > 0.5) return dy < 0 ? -1 : 1;
      return rectA.left.compareTo(rectB.left);
    });
  }

  int _indexOf(Selectable selectable) {
    final i = _selectables.indexOf(selectable);
    return i;
  }

  Selectable? _selectableAt(Offset globalPosition) {
    for (final selectable in _selectables) {
      try {
        if (selectable.boundingBoxes.isEmpty) continue;
        final local = selectable.getTransformTo(null)..invert();
        final localPoint = MatrixUtils.transformPoint(local, globalPosition);
        for (final rect in selectable.boundingBoxes) {
          if (rect.contains(localPoint)) {
            return selectable;
          }
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  void _fillIntermediate(Selectable start, Selectable end) {
    final startIdx = _indexOf(start);
    final endIdx = _indexOf(end);
    if (startIdx < 0 || endIdx < 0) return;
    final from = startIdx <= endIdx ? startIdx : endIdx;
    final to = startIdx <= endIdx ? endIdx : startIdx;
    for (var i = from + 1; i < to; i++) {
      // 中间节点全选:发送 SelectAllSelectionEvent 即可。
      _selectables[i].dispatchSelectionEvent(const SelectAllSelectionEvent());
    }
  }

  void _clearOutsideRange(Selectable start, Selectable end) {
    final startIdx = _indexOf(start);
    final endIdx = _indexOf(end);
    if (startIdx < 0 || endIdx < 0) return;
    final from = startIdx <= endIdx ? startIdx : endIdx;
    final to = startIdx <= endIdx ? endIdx : startIdx;
    for (var i = 0; i < _selectables.length; i++) {
      if (i < from || i > to) {
        if (_selectables[i].value.hasContent) {
          _selectables[i].dispatchSelectionEvent(const ClearSelectionEvent());
        }
      }
    }
  }

  void _refreshGeometry({bool notify = true}) {
    if (_disposed) return;
    if (_selectables.isEmpty) {
      if (_geometry.hasContent || _geometry.status != SelectionStatus.none) {
        _geometry = const SelectionGeometry(
          status: SelectionStatus.none,
          hasContent: false,
        );
        if (notify) notifyListeners();
      }
      return;
    }
    var hasAny = false;
    var uncollapsed = false;
    SelectionPoint? startPoint;
    SelectionPoint? endPoint;
    final rects = <Rect>[];
    for (final selectable in _selectables) {
      final g = selectable.value;
      if (!g.hasContent) continue;
      hasAny = true;
      if (g.status == SelectionStatus.uncollapsed) uncollapsed = true;
      startPoint ??= g.startSelectionPoint;
      endPoint = g.endSelectionPoint ?? endPoint;
      rects.addAll(g.selectionRects);
    }
    final next = hasAny
        ? SelectionGeometry(
            startSelectionPoint: startPoint,
            endSelectionPoint: endPoint,
            selectionRects: rects,
            status: uncollapsed
                ? SelectionStatus.uncollapsed
                : SelectionStatus.collapsed,
            hasContent: true,
          )
        : const SelectionGeometry(
            status: SelectionStatus.none,
            hasContent: false,
          );
    if (next != _geometry) {
      _geometry = next;
      if (notify) notifyListeners();
    }
  }

  @override
  void dispose() {
    // 2026-06-04: 严格按顺序清理，避免 Selectable 的回调
    // 在我们已经 dispose 之后才抵达 _onSelectableChanged。
    _disposed = true;
    for (final selectable in _selectables) {
      selectable.removeListener(_onSelectableChanged);
    }
    _selectables.clear();
    _anchorStart = null;
    _anchorEnd = null;
    // 不再主动 _refreshGeometry，避免在 SelectionContainer 节点已
    // 失活时尝试 read renderObject，触发
    // "Cannot get renderObject of inactive element"。
    super.dispose();
  }

  @override
  SelectionGeometry get value => _geometry;

  @override
  int get contentLength {
    var total = 0;
    for (final selectable in _selectables) {
      total += selectable.contentLength;
    }
    return total;
  }

  @override
  void pushHandleLayers(LayerLink? startHandle, LayerLink? endHandle) {
    for (final selectable in _selectables) {
      selectable.pushHandleLayers(startHandle, endHandle);
    }
  }

  @override
  SelectedContent? getSelectedContent() {
    final buffer = StringBuffer();
    for (final selectable in _selectables) {
      final content = selectable.getSelectedContent();
      if (content == null) continue;
      if (buffer.isNotEmpty && content.plainText.isNotEmpty) {
        buffer.write('\n');
      }
      buffer.write(content.plainText);
    }
    if (buffer.isEmpty) return null;
    return SelectedContent(plainText: buffer.toString());
  }

  @override
  SelectedContentRange? getSelection() {
    if (_selectables.isEmpty) return null;
    int? startOffset;
    int? endOffset;
    for (final selectable in _selectables) {
      final range = selectable.getSelection();
      if (range == null) continue;
      if (startOffset == null) {
        startOffset = range.startOffset;
        endOffset = range.endOffset;
      } else {
        endOffset = range.endOffset;
      }
    }
    if (startOffset == null || endOffset == null) return null;
    return SelectedContentRange(startOffset: startOffset, endOffset: endOffset);
  }

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    if (_selectables.isEmpty) return SelectionResult.none;
    switch (event.type) {
      case SelectionEventType.startEdgeUpdate:
        final typed = event as SelectionEdgeUpdateEvent;
        final target =
            _selectableAt(typed.globalPosition) ?? _selectables.first;
        _anchorStart = target;
        _anchorEnd ??= target;
        final result = target.dispatchSelectionEvent(typed);
        _fillIntermediate(_anchorStart!, _anchorEnd!);
        return result;
      case SelectionEventType.endEdgeUpdate:
        final typed = event as SelectionEdgeUpdateEvent;
        final target = _selectableAt(typed.globalPosition) ?? _selectables.last;
        _anchorEnd = target;
        _anchorStart ??= _selectables.first;
        _clearOutsideRange(_anchorStart!, _anchorEnd!);
        final result = target.dispatchSelectionEvent(typed);
        _fillIntermediate(_anchorStart!, _anchorEnd!);
        return result;
      case SelectionEventType.clear:
        for (final selectable in _selectables) {
          selectable.dispatchSelectionEvent(const ClearSelectionEvent());
        }
        _anchorStart = null;
        _anchorEnd = null;
        return SelectionResult.none;
      case SelectionEventType.selectAll:
        for (final selectable in _selectables) {
          selectable.dispatchSelectionEvent(const SelectAllSelectionEvent());
        }
        _anchorStart = _selectables.first;
        _anchorEnd = _selectables.last;
        return SelectionResult.none;
      case SelectionEventType.selectWord:
        final typed = event as SelectWordSelectionEvent;
        final target = _selectableAt(typed.globalPosition);
        if (target != null) {
          _anchorStart = target;
          _anchorEnd = target;
          for (final s in _selectables) {
            if (s != target && s.value.hasContent) {
              s.dispatchSelectionEvent(const ClearSelectionEvent());
            }
          }
          return target.dispatchSelectionEvent(typed);
        }
        return SelectionResult.none;
      case SelectionEventType.selectParagraph:
        final typed = event as SelectParagraphSelectionEvent;
        final target = _selectableAt(typed.globalPosition);
        if (target != null) {
          _anchorStart = target;
          _anchorEnd = target;
          for (final s in _selectables) {
            if (s != target && s.value.hasContent) {
              s.dispatchSelectionEvent(const ClearSelectionEvent());
            }
          }
          return target.dispatchSelectionEvent(typed);
        }
        return SelectionResult.none;
      case SelectionEventType.granularlyExtendSelection:
      case SelectionEventType.directionallyExtendSelection:
        for (final selectable in _selectables) {
          selectable.dispatchSelectionEvent(event);
        }
        return SelectionResult.end;
    }
  }
}

/// 把 markdown 子树包进 [SelectionContainer] 的薄壳 widget，
/// 持有 [_MarkdownSelectionDelegate] 的生命周期。
class _MarkdownSelectionContainer extends StatefulWidget {
  const _MarkdownSelectionContainer({required this.child});

  final Widget child;

  @override
  State<_MarkdownSelectionContainer> createState() =>
      _MarkdownSelectionContainerState();
}

class _MarkdownSelectionContainerState
    extends State<_MarkdownSelectionContainer> {
  late final _MarkdownSelectionDelegate _delegate =
      _MarkdownSelectionDelegate();

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SelectionContainer(delegate: _delegate, child: widget.child);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cached file existence probe for markdown image rendering.
//
// During AI streaming the message bubble rebuilds many times per second. Each
// rebuild previously ran `File(path).existsSync()` for every inline image URL,
// which is a blocking syscall per image per frame. This TTL cache collapses
// hundreds of syscalls per second into one per path per short window while
// still picking up newly created/deleted files within ~2s.
// ─────────────────────────────────────────────────────────────────────────────
const Duration _markdownImageExistsTtl = Duration(seconds: 2);
const int _markdownImageExistsCacheCap = 256;
final Map<String, _MarkdownImageExistsCacheEntry> _markdownImageExistsCache =
    <String, _MarkdownImageExistsCacheEntry>{};

class _MarkdownImageExistsCacheEntry {
  const _MarkdownImageExistsCacheEntry(this.exists, this.checkedAt);

  final bool exists;
  final DateTime checkedAt;
}

bool _cachedMarkdownImageFileExists(String path) {
  final now = DateTime.now();
  final cached = _markdownImageExistsCache[path];
  if (cached != null &&
      now.difference(cached.checkedAt) < _markdownImageExistsTtl) {
    return cached.exists;
  }
  final exists = File(path).existsSync();
  _markdownImageExistsCache[path] = _MarkdownImageExistsCacheEntry(exists, now);
  if (_markdownImageExistsCache.length > _markdownImageExistsCacheCap) {
    final oldestKey = _markdownImageExistsCache.entries
        .reduce((a, b) => a.value.checkedAt.isBefore(b.value.checkedAt) ? a : b)
        .key;
    _markdownImageExistsCache.remove(oldestKey);
  }
  return exists;
}

/// 用户消息纯文本渲染体 - 不对用户输入内容做 Markdown 解析，
/// 直接展示原始文本，减少进入线程会话时的解析开销与卡顿。
///
/// 仍保留超长消息折叠逻辑，阈值与 markdown 折叠体保持一致。
class _StreamingAssistantTextBody extends StatelessWidget {
  const _StreamingAssistantTextBody({
    required this.data,
    required this.textColor,
    required this.backgroundColor,
    this.style,
  });

  final String data;
  final Color textColor;
  final Color backgroundColor;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return _PlainTextMessageBody(
      data: data.isEmpty ? ' ' : data,
      textColor: textColor,
      backgroundColor: backgroundColor,
      style: style,
    );
  }
}

class _PlainTextMessageBody extends StatefulWidget {
  const _PlainTextMessageBody({
    required this.data,
    required this.textColor,
    required this.backgroundColor,
    this.style,
  });

  final String data;
  final Color textColor;
  final Color backgroundColor;
  final TextStyle? style;

  @override
  State<_PlainTextMessageBody> createState() => _PlainTextMessageBodyState();
}

class _PlainTextMessageBodyState extends State<_PlainTextMessageBody> {
  late bool _collapsed = _shouldCollapse(widget.data);
  bool _userToggled = false;
  final ScrollController _scrollController = ScrollController();
  bool _atBottom = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final atBottom = pos.pixels >= pos.maxScrollExtent - 2;
    if (atBottom != _atBottom) setState(() => _atBottom = atBottom);
  }

  @override
  void didUpdateWidget(covariant _PlainTextMessageBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_userToggled && oldWidget.data != widget.data) {
      _collapsed = _shouldCollapse(widget.data);
    }
  }

  bool _shouldCollapse(String value) {
    if (value.length > _messageMarkdownCollapseCharThreshold) return true;
    var lineCount = 1;
    for (final unit in value.codeUnits) {
      if (unit == 0x0A) {
        lineCount += 1;
        if (lineCount > _messageMarkdownCollapseLineThreshold) return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = widget.data.isEmpty ? ' ' : widget.data;
    final shouldCollapse = _shouldCollapse(data);
    final effectiveStyle =
        widget.style?.copyWith(color: widget.textColor) ??
        TextStyle(color: widget.textColor, height: 1.55);

    if (!shouldCollapse) {
      return SelectableText(data, style: effectiveStyle);
    }

    final label = _collapsed
        ? _localizedText(context, zh: '展开完整内容', en: 'Show Full Content')
        : _localizedText(context, zh: '收起长内容', en: 'Collapse Content');
    final detailStyle =
        (theme.textTheme.labelLarge?.copyWith(
          color: widget.textColor.withValues(alpha: 0.82),
          fontWeight: FontWeight.w700,
        )) ??
        const TextStyle();
    final unitText = _localizedText(context, zh: ' 字符', en: ' chars');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: _borderRadius18,
            onTap: () {
              _BubbleHtmlInteractiveScope.maybeOf(
                context,
              )?.markInteractiveTap();
              final nextCollapsed = !_collapsed;
              setState(() {
                _collapsed = nextCollapsed;
                _userToggled = true;
                if (nextCollapsed) _atBottom = false;
              });
              // 重新折叠时将预览滚回顶部，保证每次折叠都从头开始浏览。
              if (nextCollapsed) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _scrollController.hasClients) {
                    _scrollController.jumpTo(0);
                  }
                });
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                    _collapsed
                        ? Icons.unfold_more_rounded
                        : Icons.unfold_less_rounded,
                    size: 18,
                    color: widget.textColor.withValues(alpha: 0.82),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(label, style: detailStyle)),
                  Text(' · ', style: detailStyle),
                  RollingText(text: '${data.length}', style: detailStyle),
                  Text(unitText, style: detailStyle),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        ClipRect(
          child: _collapsed
              ? SizedBox(
                  height: 240,
                  child: Stack(
                    children: [
                      // 折叠态改为可滚动：用户无需展开即可浏览长文本。
                      Positioned.fill(
                        child: ClipRect(
                          child: ScrollConfiguration(
                            behavior: ScrollConfiguration.of(
                              context,
                            ).copyWith(scrollbars: false),
                            child: SingleChildScrollView(
                              controller: _scrollController,
                              physics: const BouncingScrollPhysics(),
                              child: SelectableText(
                                data,
                                style: effectiveStyle,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 底部渐隐遮罩：滚到底时平滑淡出，与 _MarkdownPreviewBody 行为一致。
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: AnimatedOpacity(
                            opacity: _atBottom ? 0.0 : 1.0,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            child: Container(
                              height: 40,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    widget.backgroundColor.withValues(alpha: 0),
                                    widget.backgroundColor.withValues(alpha: 1),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : SelectableText(data, style: effectiveStyle),
        ),
      ],
    );
  }
}

/// 简单的 HTML 嗅探：判断字符串是否大概率为 HTML 文档。
/// 用于消息内容格式 = HTML 时的"内容不像 HTML 就走回退"路径。
final RegExp _htmlLikelyTagPattern = RegExp(
  r'<\s*(?:!doctype|html|body|div|span|p|h[1-6]|ul|ol|li|table|thead|tbody|tfoot|tr|td|th|caption|col|colgroup|a|img|br|hr|pre|code|strong|em|b|i|u|s|del|ins|mark|small|sub|sup|abbr|cite|q|blockquote|section|article|header|footer|nav|main|aside|button|form|input|textarea|select|option|label|fieldset|legend|details|summary|figure|figcaption|time|progress|meter|style|script|link|meta|iframe|video|audio|canvas|svg|path|rect|circle|ellipse|line|polyline|polygon|text|g|defs|use|symbol)\b',
  caseSensitive: false,
);

bool _looksLikeHtml(String value) {
  if (value.isEmpty) return false;
  return _htmlLikelyTagPattern.hasMatch(value);
}

/// 宽松的 HTML 标签结构检测：识别任意 `<标签名>` 或 `</标签名>` 形式，
/// 用于捕获白名单外的有效 HTML 标签（如 `<del>`、`<kbd>`、`<dfn>` 等）。
/// 配合 `_looksLikeHtml` 使用，避免 AI 输出的非常见标签被误判为纯文本。
final RegExp _htmlAnyTagPattern = RegExp(
  r'<\s*/?[a-zA-Z][a-zA-Z0-9-]*\b[^>]*>',
);

bool _hasHtmlTagStructure(String value) {
  if (value.isEmpty) return false;
  // 至少包含 1 个完整的 HTML 标签（开/闭/自闭合均可）。
  return _htmlAnyTagPattern.hasMatch(value);
}

bool _startsWithFencedMermaidBlock(String source) {
  final normalized = source.trimLeft();
  return normalized.startsWith('```mermaid') ||
      normalized.startsWith('~~~mermaid');
}

// 自闭合标签，不参与开/闭配平。
const Set<String> _htmlVoidTags = <String>{
  'area',
  'base',
  'br',
  'col',
  'embed',
  'hr',
  'img',
  'input',
  'link',
  'meta',
  'param',
  'source',
  'track',
  'wbr',
};

final RegExp _htmlTagScanPattern = RegExp(
  r'<\s*(/?)\s*([a-zA-Z][a-zA-Z0-9-]*)\b[^>]*?(/?)\s*>',
);

/// 轻量 HTML 自愈：扫描 `_htmlTagScanPattern`，按栈补齐末尾未匹配的开
/// 标签；尾部出现的残缺 `<tag...`（无对应 `>`）如果看起来是开标签，也
/// 入栈并补齐。
///
/// 触发场景：AI 回复因 `finish_reason: max_tokens` 被截断，留下未闭合
/// 的 `<div>` / `<table>` 等。直接交给 WebView 时浏览器虽然会自动闭合，
/// 但 flutter_widget_from_html_core 旧版回退路径会因此崩溃或渲染出 0
/// 高度的占位 widget，导致消息卡片出现"空白"或"展开后空"的假死。
///
/// 设计原则：只追加闭合标签、不删除/重排原有字符，保持用户可见内容
/// 原貌；平衡时（栈空）返回原值（共享字符串避免无谓分配）。
final RegExp _htmlPartialOpenTagPattern = RegExp(
  r'<\s*([a-zA-Z][a-zA-Z0-9-]*)',
);

String _healUnbalancedHtml(String value) {
  if (value.isEmpty) return value;
  final lastLt = value.lastIndexOf('<');
  final lastGt = value.lastIndexOf('>');
  final stack = <String>[];
  for (final match in _htmlTagScanPattern.allMatches(value)) {
    final isClosing = (match.group(1) ?? '').isNotEmpty;
    final tag = (match.group(2) ?? '').toLowerCase();
    final selfClose = (match.group(3) ?? '').isNotEmpty;
    if (_htmlVoidTags.contains(tag) || selfClose) continue;
    if (isClosing) {
      final idx = stack.lastIndexOf(tag);
      if (idx < 0) continue; // 容忍错位，不阻断
      stack.removeRange(idx, stack.length);
    } else {
      stack.add(tag);
    }
  }
  // 末尾残缺 `<tag...`（无 `>`）：若 tagName 合法且非自闭合，仍入栈并
  // 在尾部补齐闭合。这一步是关键——AI 输出被 max_tokens 截断时，最常
  // 见的就是「最后一个 `<table ... 属性没写完」就停了。
  if (lastLt > lastGt) {
    final tail = value.substring(lastLt);
    final partial = _htmlPartialOpenTagPattern.firstMatch(tail);
    if (partial != null) {
      final tag = partial.group(1)!.toLowerCase();
      if (!_htmlVoidTags.contains(tag)) {
        stack.add(tag);
      }
    }
  }
  if (stack.isEmpty) return value;
  final buffer = StringBuffer(value);
  for (var i = stack.length - 1; i >= 0; i--) {
    buffer.write('</');
    buffer.write(stack[i]);
    buffer.write('>');
  }
  return buffer.toString();
}

/// HTML 渲染体：调用 `flutter_widget_from_html_core` 的 `HtmlWidget` 解析渲染。
/// 任何渲染期抛出都会被外层 `_AssistantMessageBodyDispatcher` 的回退链兜住。
///
/// flutter_widget_from_html_core 0.16.x 对 `flex-wrap` / CSS grid 支持有限。
/// 这里不再剥离 `display:flex`，而是在自定义 factory 里为常见卡片行布局补
/// Wrap/Grid 兜底，保证消息卡片尽量接近浏览器预览，同时避免窄气泡溢出。
String _prepareStreamingHtml(String value) => _healUnbalancedHtml(value);

class _OpenHandHtmlWidgetFactory extends WidgetFactory {
  static const String _cssDisplayGrid = 'grid';
  static const String _cssDisplayInlineGrid = 'inline-grid';
  static const String _cssFlexWrap = 'flex-wrap';
  static const String _cssFlexWrapWrap = 'wrap';
  static const String _cssGap = 'gap';
  static const String _cssColumnGap = 'column-gap';
  static const String _cssRowGap = 'row-gap';
  static const String _cssGridTemplateColumns = 'grid-template-columns';

  static final RegExp _repeatColumnPattern = RegExp(
    r'repeat\(\s*(\d+)\s*,',
    caseSensitive: false,
  );
  static final RegExp _autoFitMinmaxPattern = RegExp(
    r'repeat\(\s*auto-(?:fit|fill)\s*,\s*minmax\(\s*([0-9.]+)px',
    caseSensitive: false,
  );
  static final RegExp _cssLengthPattern = RegExp(
    r'([0-9.]+)\s*(px|rem|em|%)?',
    caseSensitive: false,
  );
  static final RegExp _flexSizingPattern = RegExp(
    r'(?:^|;)\s*(?:flex|flex-basis)\s*:',
    caseSensitive: false,
  );
  static final RegExp _flexValuePattern = RegExp(
    r'(?:^|;)\s*flex\s*:\s*([^;]+)',
    caseSensitive: false,
  );
  static final RegExp _flexBasisPattern = RegExp(
    r'(?:^|;)\s*flex-basis\s*:\s*([^;]+)',
    caseSensitive: false,
  );
  static final RegExp _minWidthPattern = RegExp(
    r'(?:^|;)\s*min-width\s*:\s*([^;]+)',
    caseSensitive: false,
  );
  static final RegExp _widthPercentPattern = RegExp(
    r'(?:^|;)\s*width\s*:\s*(?:calc\()?\s*([0-9.]+)%',
    caseSensitive: false,
  );
  static final RegExp _widthPattern = RegExp(
    r'(?:^|;)\s*width\s*:\s*([^;]+)',
    caseSensitive: false,
  );

  @override
  Widget? buildFlex(
    BuildTree tree,
    List<Widget> children, {
    CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.center,
    required Axis direction,
    MainAxisAlignment mainAxisAlignment = MainAxisAlignment.start,
    double spacing = 0.0,
    TextBaseline textBaseline = TextBaseline.alphabetic,
    TextDirection textDirection = TextDirection.ltr,
  }) {
    final flexWrap = _styleValue(tree, _cssFlexWrap);
    if (direction == Axis.horizontal &&
        flexWrap == _cssFlexWrapWrap &&
        children.isNotEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = _finiteHtmlWidth(context, constraints);
          final gap = _gapFor(tree, spacing);
          final wrappedChildren = _maybeConstrainFlexChildren(
            tree,
            children,
            maxWidth,
            gap.column,
          );
          return CssSizingHint(
            maxWidth: maxWidth,
            child: Wrap(
              spacing: gap.column,
              runSpacing: gap.row,
              alignment: _toWrapAlignment(mainAxisAlignment),
              crossAxisAlignment: _toWrapCrossAlignment(crossAxisAlignment),
              textDirection: textDirection,
              children: wrappedChildren,
            ),
          );
        },
      );
    }
    return super.buildFlex(
      tree,
      children,
      crossAxisAlignment: crossAxisAlignment,
      direction: direction,
      mainAxisAlignment: mainAxisAlignment,
      spacing: spacing,
      textBaseline: textBaseline,
      textDirection: textDirection,
    );
  }

  @override
  void parseStyleDisplay(BuildTree tree, String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == _cssDisplayGrid || normalized == _cssDisplayInlineGrid) {
      tree.register(_gridBuildOp());
      return;
    }
    super.parseStyleDisplay(tree, value);
  }

  BuildOp _gridBuildOp() {
    return BuildOp(
      alwaysRenderBlock: true,
      debugLabel: _cssDisplayGrid,
      onRenderedChildren: (tree, children) {
        final childPlaceholders = children.toList(growable: false);
        if (childPlaceholders.isEmpty) return null;
        return WidgetPlaceholder(
          debugLabel: _cssDisplayGrid,
          builder: (context, _) {
            final unwrapped = childPlaceholders
                .map((child) => WidgetPlaceholder.unwrap(context, child))
                .where((child) => child != widget0)
                .toList(growable: false);
            if (unwrapped.isEmpty) return widget0;
            return LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = _finiteHtmlWidth(context, constraints);
                final gap = _gapFor(tree, 0.0);
                final columnCount = _gridColumnCount(
                  tree,
                  maxWidth,
                  unwrapped.length,
                  gap.column,
                );
                final childWidth = columnCount <= 1
                    ? maxWidth
                    : math.max(
                        0.0,
                        (maxWidth - gap.column * (columnCount - 1)) /
                            columnCount,
                      );
                return CssSizingHint(
                  maxWidth: maxWidth,
                  child: Wrap(
                    spacing: gap.column,
                    runSpacing: gap.row,
                    children: [
                      for (final child in unwrapped)
                        SizedBox(width: childWidth, child: child),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  static List<Widget> _maybeConstrainFlexChildren(
    BuildTree tree,
    List<Widget> children,
    double maxWidth,
    double gap,
  ) {
    if (children.length < 2) return children;
    final elementChildren = tree.element.children;
    if (elementChildren.length != children.length ||
        !elementChildren.every(_elementUsesFlexibleWidth)) {
      return children;
    }
    final basis = elementChildren
        .map((element) => _elementPreferredWidth(element, maxWidth))
        .whereType<double>()
        .fold<double>(0.0, math.max);
    final effectiveColumns = basis > 0
        ? ((maxWidth + gap) / (basis + gap))
              .floor()
              .clamp(1, children.length)
              .toInt()
        : children.length;
    final childWidth = math.max(
      0.0,
      (maxWidth - gap * (effectiveColumns - 1)) / effectiveColumns,
    );
    return [
      for (final child in children) SizedBox(width: childWidth, child: child),
    ];
  }

  static bool _elementUsesFlexibleWidth(dynamic element) {
    final style = _inlineStyle(element).toLowerCase();
    if (_flexSizingPattern.hasMatch(style)) return true;
    final widthMatch = _widthPercentPattern.firstMatch(style);
    if (widthMatch == null) return false;
    final percent = double.tryParse(widthMatch.group(1) ?? '');
    return percent != null && percent > 0 && percent < 99;
  }

  static double? _elementPreferredWidth(dynamic element, double maxWidth) {
    final style = _inlineStyle(element).toLowerCase();
    for (final pattern in <RegExp>[
      _minWidthPattern,
      _flexBasisPattern,
      _widthPattern,
    ]) {
      final value = pattern.firstMatch(style)?.group(1);
      final parsed = _parseCssLength(value, maxWidth: maxWidth);
      if (parsed != null && parsed > 0) return parsed;
    }
    final flexValue = _flexValuePattern.firstMatch(style)?.group(1);
    if (flexValue != null) {
      final matches = _cssLengthPattern.allMatches(flexValue).toList();
      for (final match in matches.reversed) {
        final parsed = _parseCssLengthMatch(match, maxWidth: maxWidth);
        if (parsed != null && parsed > 1) return parsed;
      }
    }
    return null;
  }

  static String _inlineStyle(dynamic element) {
    final attributes = element.attributes;
    if (attributes is Map) {
      return attributes['style'] as String? ?? '';
    }
    return '';
  }

  static int _gridColumnCount(
    BuildTree tree,
    double maxWidth,
    int childCount,
    double gap,
  ) {
    final template = _styleValue(tree, _cssGridTemplateColumns);
    final autoFit = _autoFitMinmaxPattern.firstMatch(template);
    if (autoFit != null) {
      final minWidth = double.tryParse(autoFit.group(1) ?? '') ?? maxWidth;
      final columns = ((maxWidth + gap) / (minWidth + gap)).floor();
      return columns.clamp(1, childCount).toInt();
    }
    final repeat = _repeatColumnPattern.firstMatch(template);
    if (repeat != null) {
      return (int.tryParse(repeat.group(1) ?? '') ?? childCount)
          .clamp(1, childCount)
          .toInt();
    }
    final explicitTracks = _splitCssTrackList(template);
    if (explicitTracks.length > 1) {
      return explicitTracks.length.clamp(1, childCount).toInt();
    }
    return math.min(childCount, 3).clamp(1, childCount).toInt();
  }

  static List<String> _splitCssTrackList(String value) {
    if (value.isEmpty) return const <String>[];
    final tracks = <String>[];
    final buffer = StringBuffer();
    var depth = 0;
    for (var i = 0; i < value.length; i++) {
      final char = value[i];
      if (char == '(') depth += 1;
      if (char == ')') depth = math.max(0, depth - 1);
      if (depth == 0 && char.trim().isEmpty) {
        if (buffer.isNotEmpty) {
          tracks.add(buffer.toString());
          buffer.clear();
        }
        continue;
      }
      buffer.write(char);
    }
    if (buffer.isNotEmpty) tracks.add(buffer.toString());
    return tracks;
  }

  static String _styleValue(BuildTree tree, String property) {
    for (final style in tree.element.styles) {
      if (style.property.toLowerCase() == property) {
        final value = style.value ?? style.term;
        return value == null ? '' : value.toString().trim().toLowerCase();
      }
    }
    return '';
  }

  static _HtmlGap _gapFor(BuildTree tree, double fallback) {
    final shorthand = _parseCssGap(_styleValue(tree, _cssGap), fallback);
    final row = _parseCssLength(_styleValue(tree, _cssRowGap)) ?? shorthand.row;
    final column =
        _parseCssLength(_styleValue(tree, _cssColumnGap)) ?? shorthand.column;
    return _HtmlGap(row, column);
  }

  static _HtmlGap _parseCssGap(String value, double fallback) {
    final matches = _cssLengthPattern.allMatches(value).toList();
    if (matches.isEmpty) return _HtmlGap(fallback, fallback);
    final row = _parseCssLengthMatch(matches.first) ?? fallback;
    final column = matches.length > 1
        ? _parseCssLengthMatch(matches[1]) ?? row
        : row;
    return _HtmlGap(row, column);
  }

  static double? _parseCssLength(String? value, {double? maxWidth}) {
    if (value == null || value.trim().isEmpty) return null;
    final match = _cssLengthPattern.firstMatch(value);
    if (match == null) return null;
    return _parseCssLengthMatch(match, maxWidth: maxWidth);
  }

  static double? _parseCssLengthMatch(RegExpMatch match, {double? maxWidth}) {
    final raw = double.tryParse(match.group(1) ?? '');
    if (raw == null) return null;
    final unit = match.group(2)?.toLowerCase();
    switch (unit) {
      case '%':
        return maxWidth == null ? null : maxWidth * raw / 100;
      case 'rem':
      case 'em':
        return raw * 16;
      case 'px':
      case null:
      case '':
        return raw;
    }
    return raw;
  }

  static double _finiteHtmlWidth(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    final maxWidth = constraints.maxWidth;
    if (maxWidth.isFinite && maxWidth > 0) return maxWidth;
    return MediaQuery.sizeOf(context).width;
  }

  static WrapAlignment _toWrapAlignment(MainAxisAlignment alignment) {
    switch (alignment) {
      case MainAxisAlignment.start:
        return WrapAlignment.start;
      case MainAxisAlignment.end:
        return WrapAlignment.end;
      case MainAxisAlignment.center:
        return WrapAlignment.center;
      case MainAxisAlignment.spaceBetween:
        return WrapAlignment.spaceBetween;
      case MainAxisAlignment.spaceAround:
        return WrapAlignment.spaceAround;
      case MainAxisAlignment.spaceEvenly:
        return WrapAlignment.spaceEvenly;
    }
  }

  static WrapCrossAlignment _toWrapCrossAlignment(
    CrossAxisAlignment alignment,
  ) {
    switch (alignment) {
      case CrossAxisAlignment.start:
        return WrapCrossAlignment.start;
      case CrossAxisAlignment.end:
        return WrapCrossAlignment.end;
      case CrossAxisAlignment.center:
        return WrapCrossAlignment.center;
      case CrossAxisAlignment.stretch:
      case CrossAxisAlignment.baseline:
        return WrapCrossAlignment.start;
    }
  }
}

class _HtmlGap {
  const _HtmlGap(this.row, this.column);

  final double row;
  final double column;
}

class _HtmlMessageBody extends StatelessWidget {
  const _HtmlMessageBody({
    required this.data,
    required this.textColor,
    this.baseTextStyle,
  });

  final String data;
  final Color textColor;
  final TextStyle? baseTextStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final base =
        baseTextStyle?.copyWith(color: textColor) ??
        TextStyle(color: textColor);
    final accent = theme.colorScheme.primary;
    final borderColor = theme.colorScheme.outlineVariant;
    final codeBg = isDark
        ? theme.colorScheme.surfaceContainerHigh
        : theme.colorScheme.surfaceContainerLow;
    final mutedText = theme.colorScheme.onSurfaceVariant;

    String hex(Color c) {
      final r = (c.r * 255).round() & 0xff;
      final g = (c.g * 255).round() & 0xff;
      final b = (c.b * 255).round() & 0xff;
      return '#${r.toRadixString(16).padLeft(2, '0')}'
          '${g.toRadixString(16).padLeft(2, '0')}'
          '${b.toRadixString(16).padLeft(2, '0')}';
    }

    final accentHex = hex(accent);
    final borderHex = hex(borderColor);
    final codeBgHex = hex(codeBg);
    final mutedHex = hex(mutedText);

    final prepared = _prepareStreamingHtml(data);
    return ClipRect(
      child: SelectionArea(
        child: HtmlWidget(
          prepared.isEmpty ? ' ' : prepared,
          textStyle: base,
          factoryBuilder: _OpenHandHtmlWidgetFactory.new,
          customStylesBuilder: (element) {
            // 主题感知的默认样式。
            switch (element.localName) {
              case 'code':
                return <String, String>{
                  'background-color': codeBgHex,
                  'padding': '2px 6px',
                  'border-radius': '4px',
                  'font-family': 'monospace',
                };
              case 'pre':
                return <String, String>{
                  'background-color': codeBgHex,
                  'padding': '12px 14px',
                  'border-radius': '8px',
                  'border': '1px solid $borderHex',
                  'overflow-x': 'auto',
                };
              case 'blockquote':
                return <String, String>{
                  'border-left': '3px solid $accentHex',
                  'padding': '4px 12px',
                  'margin': '8px 0',
                  'color': mutedHex,
                  'background-color': codeBgHex,
                  'border-radius': '0 6px 6px 0',
                };
              case 'table':
                return <String, String>{
                  'border-collapse': 'collapse',
                  'border': '1px solid $borderHex',
                  'margin': '8px 0',
                };
              case 'th':
                return <String, String>{
                  'border': '1px solid $borderHex',
                  'padding': '6px 10px',
                  'background-color': codeBgHex,
                  'font-weight': '600',
                };
              case 'td':
                return <String, String>{
                  'border': '1px solid $borderHex',
                  'padding': '6px 10px',
                };
              case 'h2':
                return <String, String>{
                  'margin-top': '18px',
                  'margin-bottom': '8px',
                  'font-weight': '700',
                };
              case 'h3':
                return <String, String>{
                  'margin-top': '14px',
                  'margin-bottom': '6px',
                  'font-weight': '600',
                };
              case 'h4':
                return <String, String>{
                  'margin-top': '12px',
                  'margin-bottom': '4px',
                  'font-weight': '600',
                };
              case 'details':
                return <String, String>{
                  'border': '1px solid $borderHex',
                  'border-radius': '8px',
                  'padding': '8px 12px',
                  'margin': '8px 0',
                  'background-color': codeBgHex,
                };
              case 'summary':
                return <String, String>{
                  'cursor': 'pointer',
                  'font-weight': '600',
                };
              case 'a':
                return <String, String>{
                  'color': accentHex,
                  'text-decoration': 'underline',
                };
              case 'hr':
                return <String, String>{
                  'border': 'none',
                  'border-top': '1px solid $borderHex',
                  'margin': '14px 0',
                };
            }
            return null;
          },
          onErrorBuilder: (context, element, error) =>
              SelectableText(data, style: base),
          onLoadingBuilder: (context, element, progress) => const SizedBox(
            height: 12,
            width: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
    );
  }
}

/// 流式 HTML 卡片占位：AI 仍在持续流式追加 HTML 时，UI 不直接展示
/// 原始 HTML 字符（避免大量 `<div>...</div>` 给用户带来困惑），改为
/// 呈现一个 Q 弹的"正在生成"骨架屏 + 闪动光点 + 右下角实时字符计数。
/// 流式结束后由 `_AssistantMessageBodyDispatcher` 做一次性 body 模式切换，
/// 并附带轻量 fade+scale 落位动画。
class _StreamingHtmlPlaceholder extends StatefulWidget {
  const _StreamingHtmlPlaceholder({
    required this.textColor,
    required this.contentLength,
  });

  final Color textColor;
  final int contentLength;

  @override
  State<_StreamingHtmlPlaceholder> createState() =>
      _StreamingHtmlPlaceholderState();
}

class _StreamingHtmlPlaceholderState extends State<_StreamingHtmlPlaceholder>
    with TickerProviderStateMixin {
  late final AnimationController _dotCtrl;
  late final Animation<double> _dotAnim;

  @override
  void initState() {
    super.initState();
    _dotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
    _dotAnim = CurvedAnimation(parent: _dotCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _dotCtrl.dispose();
    super.dispose();
  }

  Widget _dot(int index) {
    // 错相位波浪：每个点在自己 [0, 1] 窗口内从亮到暗，循环周期内
    // 三个点都"亮起→暗下去"，不再有永远亮/永远暗的端点。
    final phase = (_dotAnim.value - index * 0.33).clamp(0.0, 1.0);
    final scale = 0.55 + 0.45 * (1.0 - phase);
    final alpha = 0.30 + 0.70 * (1.0 - phase);
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 7,
        height: 7,
        margin: EdgeInsets.symmetric(horizontal: index == 1 ? 4 : 2),
        decoration: BoxDecoration(
          color: widget.textColor.withValues(alpha: alpha),
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final animationsEnabled =
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    if (!animationsEnabled) {
      _dotCtrl.stop();
    } else if (!_dotCtrl.isAnimating) {
      _dotCtrl.repeat();
    }
    final captionStyle = TextStyle(
      fontSize: 12,
      color: widget.textColor.withValues(alpha: 0.78),
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _HtmlBubbleShimmer(),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_awesome_outlined,
                      size: 14,
                      color: cs.primary.withValues(alpha: 0.85),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _localizedText(
                          context,
                          zh: '正在生成 HTML 卡片',
                          en: 'Generating HTML card',
                        ),
                        style: captionStyle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    AnimatedBuilder(
                      animation: _dotAnim,
                      builder: (context, _) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [_dot(0), _dot(1), _dot(2)],
                      ),
                    ),
                  ],
                ),
              ),
              // 右下角：实时字符计数。与 Token 胶囊 / 消息卡左上角字符数共享
              // 同一 `RollingText`，Q 弹 easeOutBack 翻牌，多位独立动画。
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  RollingText(
                    text: '${widget.contentLength}',
                    style: captionStyle.copyWith(
                      color: widget.textColor.withValues(alpha: 0.62),
                    ),
                  ),
                  Text(
                    _localizedText(context, zh: ' 字符', en: ' chars'),
                    style: captionStyle.copyWith(
                      color: widget.textColor.withValues(alpha: 0.62),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 首次加载 HTML 气泡时的骨架屏占位，与 [_AuditShimmerPlaceholder]
/// 同款扫光动画，避免 WebView 加载期间显示一个 ~25px 的空盒子。
///
/// 容器底色固定为 `Colors.transparent`：占位只会出现在消息卡片内部
///（assistant = surfaceContainerHigh / 工具结果 = surfaceContainerHighest），
/// 不应再叠一层"更深一档"色块，否则会与卡片背景产生肉眼可见的色差。
/// 高亮感由 shimmer 条带本身的 surfaceContainerLow 渐变承担。
class _HtmlBubbleShimmer extends StatefulWidget {
  const _HtmlBubbleShimmer();

  @override
  State<_HtmlBubbleShimmer> createState() => _HtmlBubbleShimmerState();
}

class _HtmlBubbleShimmerState extends State<_HtmlBubbleShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
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
    final baseColor = cs.onSurface.withValues(alpha: 0.08);
    final highlightColor = cs.onSurface.withValues(alpha: 0.18);
    final animationsEnabled =
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    if (!animationsEnabled) {
      _ctrl.stop();
      return _buildContent(baseColor, highlightColor, 0.5);
    }
    if (!_ctrl.isAnimating) {
      _ctrl.repeat();
    }
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return _buildContent(baseColor, highlightColor, _ctrl.value);
      },
    );
  }

  Widget _buildBar(
    Color base,
    Color highlight,
    double progress, {
    double? width,
  }) {
    return Container(
      width: width ?? double.infinity,
      height: 12,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: LinearGradient(
          begin: Alignment(-1.0 + 2.0 * progress, 0),
          end: Alignment(-1.0 + 2.0 * progress + 1.0, 0),
          colors: [base, highlight, base],
        ),
      ),
    );
  }

  Widget _buildContent(Color base, Color highlight, double progress) {
    // 容器底色透明：避免在 assistant 卡片（surfaceContainerHigh）等
    // 任意底色之上再叠一块"更深一档"的色块导致色差。
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBar(base, highlight, progress),
          const SizedBox(height: 8),
          _buildBar(base, highlight, progress),
          const SizedBox(height: 8),
          _buildBar(base, highlight, progress),
          const SizedBox(height: 8),
          _buildBar(base, highlight, progress, width: 180),
        ],
      ),
    );
  }
}

double _estimateHtmlBubbleHeight(String data) {
  final length = data.length;
  if (length == 0) return _HtmlBubbleWebViewState._kEstimatedMinHeight;
  final lines = (length / _HtmlBubbleWebViewState._kEstimatedCharsPerLine)
      .ceil();
  return (lines * _HtmlBubbleWebViewState._kEstimatedLineHeight)
      .clamp(
        _HtmlBubbleWebViewState._kEstimatedMinHeight,
        _HtmlBubbleWebViewState._kEstimatedMaxHeight,
      )
      .toDouble();
}

class _HtmlWebViewFrameScheduler {
  _HtmlWebViewFrameScheduler._();
  static final _HtmlWebViewFrameScheduler instance =
      _HtmlWebViewFrameScheduler._();

  static const int _maxPerFrame = 1;
  final List<VoidCallback> _pending = <VoidCallback>[];
  bool _draining = false;

  void schedule(VoidCallback task) {
    _pending.add(task);
    if (_draining) return;
    _draining = true;
    WidgetsBinding.instance.addPostFrameCallback(_drain);
  }

  void _drain(Duration _) {
    if (_pending.isEmpty) {
      _draining = false;
      return;
    }
    final batchSize = math.min(_pending.length, _maxPerFrame);
    final batch = _pending.sublist(0, batchSize);
    _pending.removeRange(0, batchSize);
    for (final task in batch) {
      task();
    }
    if (_pending.isEmpty) {
      _draining = false;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback(_drain);
  }
}

class _DeferredHtmlBubbleWebView extends StatefulWidget {
  const _DeferredHtmlBubbleWebView({
    super.key,
    required this.data,
    required this.textColor,
    required this.backgroundColor,
    this.baseTextStyle,
  });

  final String data;
  final Color textColor;
  final Color backgroundColor;
  final TextStyle? baseTextStyle;

  @override
  State<_DeferredHtmlBubbleWebView> createState() =>
      _DeferredHtmlBubbleWebViewState();
}

class _DeferredHtmlBubbleWebViewState
    extends State<_DeferredHtmlBubbleWebView> {
  bool _mountWebView = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scheduleMount();
  }

  @override
  void didUpdateWidget(covariant _DeferredHtmlBubbleWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data ||
        oldWidget.textColor != widget.textColor ||
        oldWidget.backgroundColor != widget.backgroundColor ||
        oldWidget.baseTextStyle != widget.baseTextStyle) {
      _mountWebView = false;
      _scheduleMount();
    }
  }

  @override
  void dispose() {
    _generation += 1;
    super.dispose();
  }

  void _scheduleMount() {
    final generation = ++_generation;
    _HtmlWebViewFrameScheduler.instance.schedule(() {
      if (!mounted || generation != _generation || _mountWebView) {
        return;
      }
      setState(() {
        _mountWebView = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final duration = cardMotionDurationFor(context, expanding: true);
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: kCardMotionCurve,
      switchOutCurve: Curves.easeOutCubic,
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: kCardMotionCurve,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.985, end: 1.0).animate(curved),
            alignment: Alignment.topCenter,
            child: child,
          ),
        );
      },
      child: _mountWebView
          ? _HtmlBubbleWebView(
              key: ValueKey<int>(
                Object.hash(
                  widget.data,
                  widget.textColor,
                  widget.backgroundColor,
                  widget.baseTextStyle,
                ),
              ),
              data: widget.data,
              textColor: widget.textColor,
              backgroundColor: widget.backgroundColor,
              baseTextStyle: widget.baseTextStyle,
            )
          : SizedBox(
              key: const ValueKey<String>('html-webview-mount-placeholder'),
              height: _estimateHtmlBubbleHeight(widget.data),
              child: const _HtmlBubbleShimmer(),
            ),
    );
  }
}

/// 嵌入式 WebView HTML 气泡渲染器。
///
/// 线程内 HTML 需要保留浏览器级 CSS/布局保真；macOS 平台视图鼠标事件
/// 不稳定，因此点击与拖选由外层气泡 Listener 转发到此 state 合成 DOM
/// 事件/Selection Range，同时用高度缓存减少会话切换时的二次跳动。
class _HtmlBubbleWebView extends StatefulWidget {
  const _HtmlBubbleWebView({
    super.key,
    required this.data,
    required this.textColor,
    required this.backgroundColor,
    this.baseTextStyle,
  });

  final String data;
  final Color textColor;
  final Color backgroundColor;
  final TextStyle? baseTextStyle;

  @override
  State<_HtmlBubbleWebView> createState() => _HtmlBubbleWebViewState();
}

class _HtmlBubbleWebViewState extends State<_HtmlBubbleWebView> {
  // 高度测量与防抖常量
  static const double _kMinHeightClamp = 24.0;
  static const double _kMaxHeightClamp = 50000.0;
  static const double _kFirstMeasurementSkipThreshold = 5000.0;
  // 2026-06-07：1.0 → 8.0。WebView 测高受 DPR/字体子像素/DOM 抖动影响，
  // 1px 阈值下任何微小 CSS reflow 都会触发 setState。结合滚动期间冻结，
  // 进一步在稳态下过滤掉测量噪声，避免 maxScrollExtent 持续抖动。
  static const double _kMinHeightDelta = 8.0;
  static const double _kLargeChangeRatio = 0.30;
  static const Duration _kMinHeightApplyInterval = Duration(milliseconds: 300);
  // 2026-06-07：96 → 512。长会话（>96 条 HTML 消息）下滑回来时，被淘汰
  // 的旧消息 cachedHeight 丢失，会走 shimmer → actual 路径触发 maxScroll
  // Extent 抖动。更大的 cache 让绝大多数用户场景下缓存命中，避免重建。
  static const int _kHeightCacheMaxSize = 512;
  // 2026-06-07：移除 stability 检查 + 5 秒超时兜底。stability 检查
  // 试图用 Flutter 端逻辑去判断 WebView 异步渲染状态根本不可靠——
  // 一旦后续 reflow 触发了大幅变化（图片懒加载、字体回退）导致
  // stability 翻转，shimmer 会重新出现；且 timer 取消后从未重启，
  // 5 秒超时失效，shimmer 永久卡死。改回简单条件 + 首次测量 outlier
  // 检查：`_height == null && cachedHeight == null` 才显示 shimmer，
  // 几百毫秒内 _height 被设置后即切到 WebView，逻辑可靠。
  // 2026-06-07：防抖时长 500ms → 250ms。WebView 内部 reflow（图片懒
  // 加载、字体回退）通常在 200ms 内收敛，500ms 防抖让 shimmer 多停
  // 留 300ms 显得拖沓；250ms 既能滤掉高频回调、又不让用户等太久。
  static const Duration _kHeightDebounceDuration = Duration(milliseconds: 250);
  // 渲染占位高度估算常量：HTML 文本在 14px 字体下平均每行约容纳 80
  // 字符、24 像素高。占位时按内容长度给出一个不至于"突然伸长"的
  // 初始高度，避免 shimmer 96px 与真实 2000+px 之间出现夸张落差。
  static const double _kEstimatedLineHeight = 24.0;
  static const int _kEstimatedCharsPerLine = 80;
  static const double _kEstimatedMinHeight = 96.0;
  static const double _kEstimatedMaxHeight = 2000.0;
  // 2026-06-07：首次测量 outlier 阈值。WebView 第一次测高常因图片/CSS
  // 未完成返回异常大的值（如 5000+），直接应用会撑出"渲染下方空白"。
  // 当首测高度 > 估算高度 × ratio 时，**先应用估算高度**作为初始
  // 显示尺寸，后续测量（250ms 防抖）会把高度修正到准确值；视觉上看
  // 是"由小到大"生长，比"由大到小收缩留下大片空白"更可接受。
  static const double _kFirstMeasurementOutlierRatio = 2.0;
  // 2026-06-07：基于参考高度的 outlier 阈值。WebView 测高在 CSS reset
  // 注入前/字体回退/图片懒加载等瞬态下可能返回"原始 HTML 文本高度"
  // ——把标签字符当纯文本逐行排版的高度（远大于渲染后高度）。一旦
  // 新测量值 > 参考高度 × ratio，视为瞬态噪声，**保留旧值**而不用
  // 新值——让后续稳定测量来修正，避免"渲染下方空白"的偶发跳变。
  // 1.5 倍是经验值：合法增长（details 展开、聊天消息展开）通常 <1.3 倍。
  static const double _kReferenceOutlierRatio = 1.5;
  static final RegExp _documentShellPattern = RegExp(
    r'<\s*(?:!doctype|html|head|body)\b',
    caseSensitive: false,
  );
  static final RegExp _headClosePattern = RegExp(
    r'</head\s*\>',
    caseSensitive: false,
  );
  static final RegExp _headOpenPattern = RegExp(
    r'<head\b[^>]*>',
    caseSensitive: false,
  );

  static const String _embeddedDocumentResetStyle =
      '<style id="openhand-html-bubble-reset">'
      'html,body{min-height:0!important;height:auto!important;'
      'overflow-x:auto;overflow-y:hidden!important;}'
      'html,body,body *{-webkit-user-select:text;user-select:text;}'
      'body{box-sizing:border-box;cursor:text;}'
      'a,button,summary,[role="button"]{cursor:pointer;}'
      'input,textarea,select{cursor:text;}'
      '</style>';

  static const String _heightObserverScript = r'''
(function(){
  if (window.__openhandHeightObserverInstalled) {
    if (window.__openhandScheduleHeight) window.__openhandScheduleHeight();
    return;
  }
  window.__openhandHeightObserverInstalled = true;
  var __lastReportedHeight = 0;
  function px(value) {
    var parsed = parseFloat(value);
    return Number.isFinite(parsed) ? parsed : 0;
  }
  function installRuntimeReset() {
    try {
      var style = document.getElementById('openhand-html-bubble-runtime-reset');
      if (!style) {
        style = document.createElement('style');
        style.id = 'openhand-html-bubble-runtime-reset';
        (document.head || document.documentElement).appendChild(style);
      }
      var _resetCss = 'html,body{min-height:0!important;height:auto!important;overflow-y:hidden!important;}html,body,body *{-webkit-user-select:text;user-select:text;}body{box-sizing:border-box!important;cursor:text;}a,button,summary,[role="button"]{cursor:pointer;}input,textarea,select{cursor:text;}';
	      if (style.textContent !== _resetCss) {
	        style.textContent = _resetCss;
	      }
      if (document.documentElement) {
        var de = document.documentElement.style;
        if (de.getPropertyValue('min-height') !== '0') de.setProperty('min-height', '0', 'important');
        if (de.getPropertyValue('height') !== 'auto') de.setProperty('height', 'auto', 'important');
      }
      if (document.body) {
        var bs = document.body.style;
        if (bs.getPropertyValue('min-height') !== '0') bs.setProperty('min-height', '0', 'important');
        if (bs.getPropertyValue('height') !== 'auto') bs.setProperty('height', 'auto', 'important');
        if (bs.getPropertyValue('overflow-y') !== 'hidden') bs.setProperty('overflow-y', 'hidden', 'important');
      }
    } catch (_) {}
  }
  function tagOf(node) {
    return String((node && node.tagName) || '').toLowerCase();
  }
  function isHiddenStyle(styles) {
    return !styles || styles.display === 'none' ||
      styles.visibility === 'hidden' || styles.visibility === 'collapse';
  }
  function isIgnoredTag(tag) {
    return /^(script|style|noscript|template|meta|link|title|head)$/i.test(tag);
  }
  function isContentBoxTag(tag) {
    return /^(img|video|canvas|svg|iframe|table|pre|hr|button|input|textarea|select|summary)$/i.test(tag);
  }
  function insideClosedDetailsContent(node, container) {
    var original = node.nodeType === 1 ? node : node.parentElement;
    var element = original;
    while (element && element !== container.parentElement) {
      if (tagOf(element) === 'details' && !element.open) {
        var summary = null;
        for (var i = 0; i < element.children.length; i++) {
          if (tagOf(element.children[i]) === 'summary') {
            summary = element.children[i];
            break;
          }
        }
        if (!summary || !summary.contains(original)) return true;
      }
      if (element === container) break;
      element = element.parentElement;
    }
    return false;
  }
  function isViewportFiller(node, styles, rect) {
    if (!node || !styles || !rect) return false;
    var tag = tagOf(node);
    if (isContentBoxTag(tag)) return false;
    var viewport = window.innerHeight || 0;
    if (viewport < 32 || rect.height < viewport - 1) return false;
    var inlineStyle = '';
    try { inlineStyle = String(node.getAttribute('style') || '').toLowerCase(); } catch (_) {}
    var minHeight = px(styles.minHeight);
    if (Math.abs(minHeight - viewport) < 2) return true;
    if (/(^|;)\s*(?:min-height|height)\s*:[^;]*\d(?:\.\d+)?vh\b/.test(inlineStyle)) return true;
    return !!node.children && node.children.length > 0 && rect.height >= viewport - 1;
  }
  function visibleInContainer(node, container) {
    if (insideClosedDetailsContent(node, container)) return false;
    var element = node.nodeType === 1 ? node : node.parentElement;
    while (element && element !== container.parentElement) {
      var tag = tagOf(element);
      if (isIgnoredTag(tag)) return false;
      var styles = window.getComputedStyle(element);
      if (isHiddenStyle(styles) || styles.position === 'fixed') return false;
      if (element === container) return true;
      element = element.parentElement;
    }
    return true;
  }
  function trailingInsetFor(node, container, contentBottom) {
    var element = node && node.nodeType === 1 ? node : node && node.parentElement;
    var inset = 0;
    var visualInset = 0;
    while (element && element !== container.parentElement) {
      var styles = window.getComputedStyle(element);
      var rect = element.getBoundingClientRect();
      if (!isHiddenStyle(styles) && styles.position !== 'fixed' && !isViewportFiller(element, styles, rect)) {
        var paddingAndBorder = Math.min(28, px(styles.paddingBottom) + px(styles.borderBottomWidth));
        var margin = Math.min(20, px(styles.marginBottom));
        inset = Math.min(56, inset + paddingAndBorder + margin);
        visualInset = Math.max(
          visualInset,
          Math.min(56, Math.max(0, rect.bottom + px(styles.marginBottom) - contentBottom))
        );
      }
      if (element === container) break;
      element = element.parentElement;
    }
    return Math.max(inset, visualInset);
  }
  function flowEndInsetFor(container, contentBottom) {
    try {
      var marker = document.getElementById('openhand-html-bubble-flow-end');
      if (!marker) {
        marker = document.createElement('span');
        marker.id = 'openhand-html-bubble-flow-end';
        marker.setAttribute('aria-hidden', 'true');
      }
      marker.style.cssText = 'display:block;clear:both;width:0;height:0;margin:0;padding:0;border:0;overflow:hidden;pointer-events:none;';
      if (marker.parentElement !== container) container.appendChild(marker);
      var rect = marker.getBoundingClientRect();
      var styles = window.getComputedStyle(container);
      var inset = rect.bottom - contentBottom + px(styles.paddingBottom) + px(styles.borderBottomWidth);
      if (!Number.isFinite(inset) || inset <= 0 || inset > 96) return 0;
      return inset;
    } catch (_) {
      return 0;
    }
  }
  function visibleHeightFor(container, includeMargins) {
    if (!container) return 0;
    var baseRect = container.getBoundingClientRect();
    var styles = window.getComputedStyle(container);
    var top = baseRect.top - (includeMargins ? px(styles.marginTop) : 0);
    var bottom = baseRect.top + px(styles.paddingTop) + px(styles.borderTopWidth);
    var bottomNode = null;

    function includeRect(node, rect, nodeStyles, includeMargin) {
      if (!rect || rect.width <= 0 || rect.height <= 0) return;
      var next = rect.bottom + (includeMargin && nodeStyles ? px(nodeStyles.marginBottom) : 0);
      if (next > bottom) {
        bottom = next;
        bottomNode = node;
      }
    }

    try {
      var textWalker = document.createTreeWalker(container, 4);
      var textCount = 0;
      while (textWalker.nextNode() && textCount < 2400) {
        var textNode = textWalker.currentNode;
        if (!textNode.nodeValue || !textNode.nodeValue.trim()) continue;
        if (!visibleInContainer(textNode, container)) continue;
        var range = document.createRange();
        range.selectNodeContents(textNode);
        var rects = range.getClientRects();
        for (var r = 0; r < rects.length; r++) {
          includeRect(textNode, rects[r], null, false);
        }
        range.detach && range.detach();
        textCount++;
      }
    } catch (_) {}

    var nodes = container.querySelectorAll ? container.querySelectorAll('*') : [];
    var limit = Math.min(nodes.length, 1800);
    for (var i = 0; i < limit; i++) {
      var node = nodes[i];
      var tag = tagOf(node);
      if (isIgnoredTag(tag) || !isContentBoxTag(tag)) continue;
      if (!visibleInContainer(node, container)) continue;
      var rect = node.getBoundingClientRect();
      if (!rect || (rect.width === 0 && rect.height === 0)) continue;
      var nodeStyles = window.getComputedStyle(node);
      if (isHiddenStyle(nodeStyles)) continue;
      if (nodeStyles.position === 'fixed') continue;
      if (isViewportFiller(node, nodeStyles, rect)) continue;
      includeRect(node, rect, nodeStyles, true);
    }

    if (!bottomNode) {
      bottomNode = container;
    }
    var trailingInset = Math.max(
      trailingInsetFor(bottomNode, container, bottom),
      flowEndInsetFor(container, bottom)
    );
    var measured = Math.max(0, bottom - top + trailingInset);
    return Math.ceil(measured);
  }
  function measure() {
    try {
      installRuntimeReset();
      var root = document.getElementById('oh-root');
      var body = document.body;
      var doc = document.documentElement;
      var height = 0;
      if (root) {
        height = Math.max(height, visibleHeightFor(root, false));
      } else {
        height = Math.max(height, visibleHeightFor(body, true));
      }
      if (doc && height <= 0) {
        height = Math.max(doc.scrollHeight || 0, doc.offsetHeight || 0);
      }
      var dpr = window.devicePixelRatio || 1;
      height = Math.ceil(height * dpr) / dpr;
      if (height > 0 && Math.abs(height - __lastReportedHeight) > 0.5) {
        __lastReportedHeight = height;
        window.flutter_inappwebview.callHandler('OpenHandHeight', height);
      }
    } catch (_) {}
  }
  var pending = false;
  function schedule() {
    if (pending) return;
    pending = true;
    window.requestAnimationFrame(function(){
      pending = false;
      measure();
    });
  }
  window.__openhandScheduleHeight = schedule;
  installRuntimeReset();
  measure();
  try {
    var resizeObserver = new ResizeObserver(schedule);
    if (document.getElementById('oh-root')) resizeObserver.observe(document.getElementById('oh-root'));
    if (document.body) resizeObserver.observe(document.body);
    if (document.documentElement) resizeObserver.observe(document.documentElement);
  } catch (_) {}
  try {
    var mutationObserver = new MutationObserver(schedule);
    if (document.body) {
      mutationObserver.observe(document.body, {
        subtree: true,
        attributes: true,
        childList: true,
        characterData: true
      });
    }
  } catch (_) {}
  document.addEventListener('toggle', schedule, true);
  document.addEventListener('transitionend', schedule, true);
  document.addEventListener('animationend', schedule, true);
  window.addEventListener('load', schedule);
  setTimeout(schedule, 100);
  setTimeout(schedule, 300);
})();
''';

  static const String _selectionBridgeScript = r'''
(function(){
  if (window.__openhandSelectionBridgeInstalled) return;
  window.__openhandSelectionBridgeInstalled = true;
  var anchor = null;
  function textPointFromPoint(x, y) {
    try {
      if (document.caretRangeFromPoint) {
        var range = document.caretRangeFromPoint(x, y);
        if (range) return { node: range.startContainer, offset: range.startOffset };
      }
      if (document.caretPositionFromPoint) {
        var position = document.caretPositionFromPoint(x, y);
        if (position) return { node: position.offsetNode, offset: position.offset };
      }
      var element = document.elementFromPoint(x, y);
      if (!element) return null;
      if (element.nodeType === 3) return { node: element, offset: 0 };
      var walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT, {
        acceptNode: function(node) {
          return node.nodeValue && node.nodeValue.trim()
            ? NodeFilter.FILTER_ACCEPT
            : NodeFilter.FILTER_REJECT;
        }
      });
      var text = walker.nextNode();
      return text ? { node: text, offset: 0 } : null;
    } catch (_) {
      return null;
    }
  }
  function comparePoints(a, b) {
    if (!a || !b) return 0;
    if (a.node === b.node) return a.offset - b.offset;
    var position = a.node.compareDocumentPosition(b.node);
    if (position & Node.DOCUMENT_POSITION_FOLLOWING) return -1;
    if (position & Node.DOCUMENT_POSITION_PRECEDING) return 1;
    return 0;
  }
  function applySelection(from, to) {
    try {
      if (!from || !to) return '';
      var start = from;
      var end = to;
      if (comparePoints(start, end) > 0) {
        start = to;
        end = from;
      }
      var range = document.createRange();
      range.setStart(start.node, start.offset);
      range.setEnd(end.node, end.offset);
      var selection = window.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
      return selection.toString();
    } catch (_) {
      return '';
    }
  }
  window.__openhandSelectionBridge = function(kind, x, y) {
    var point = textPointFromPoint(x, y);
    if (!point) return '';
    if (kind === 'start') {
      anchor = point;
      return applySelection(anchor, point);
    }
    if (!anchor) anchor = point;
    return applySelection(anchor, point);
  };
})();
''';

  iaw.InAppWebViewController? _controller;
  double? _height;
  bool _hasError = false;
  bool _selectionUpdateInFlight = false;
  bool _selectionBridgeStarted = false;
  Offset? _selectionAnchorGlobalPosition;
  Offset? _pendingSelectionUpdate;
  static final Map<int, double> _heightCache = <int, double>{};
  // 2026-06-07：跨 State 生命周期的单调 floor。
  // State dispose 时把真实测量高度写入此 cache，新 State 重建后若 _height
  // 丢失则用 floor 兜底，防止 Stack 高度收缩到 estimatedHeight 导致
  // maxScrollExtent 抖动。与 _heightCache 分离：floor 只写 dispose 时的
  // 真实高度，outlier 占位估计绝不写入，避免污染持久化数据。
  static final Map<int, double> _heightFloorCache = <int, double>{};
  // 2026-06-07：HTML 文档字符串缓存。`_buildDocument()` 在每次 build 都会
  // 拼装 1-2KB HTML 字符串（多次 RegExp.match、字符串切片、模板拼接），
  // 长会话首屏 8-15 个 HTML 气泡同帧 build 时叠加，单帧 ~5-15ms 浪费
  // 在重复拼装同一份文档上。改为按 (data 引用, textColor 引用,
  // backgroundColor 引用) 在 State 维度内缓存，引用相同即视为输入未变。
  // 使用引用比对而非 hash 避免罕见的 hash 冲突错返缓存。
  String? _documentCacheData;
  Color? _documentCacheTextColor;
  Color? _documentCacheBackgroundColor;
  String? _documentCache;
  int _measurementCount = 0;
  Timer? _heightDebounceTimer;
  // 2026-06-06（线程模板抽搐 bug 真凶）：HTML WebView 通过 ResizeObserver
  // + rAF 在 macOS focus/blur、JS 二次布局、scrollIntoView 触发时都会重新
  // 测高，每帧 16-30ms 一次。原来的 100ms 防抖每次都被新一轮测量重置、
  // 永远不触发，结果 maxScrollExtent 在 7544 ↔ 4971 之间反复回流，用户实测
  // 日志里 applyCD#N d=+28/-31/-72/-26/-15/... 持续几十帧，整张消息列表跟
  // 着上下抖。改用「累积最新测量 + 500ms 一次性定时器」：后续新测量只更新
  // _pendingHeight，**不重置**定时器，确保 500ms 后必然触发、应用终值。
  double? _pendingHeight;
  // 限制高度应用间隔，阻断 WebView resize → setState → 再次 resize 闭环振荡。
  DateTime? _lastHeightApplyTime;
  // 2026-05-25: 用于让外层气泡 pointer 监听在命中 WebView 区域时跳过
  // "选中卡片"切换，从而让 HTML 内部的按钮/超链接/表单能被点击。
  final GlobalKey _webViewRegionKey = GlobalKey();
  _MessageBubbleState? _bubbleStateForRegion;
  // 2026-06-07：滚动活动协调信号。active=true 时 JS 测高只缓存、不应用，
  // 避免 maxScrollExtent 抖动把 viewport 拽回底部。inactive 后才一次性
  // 应用累积的最新高度。
  TranscriptScrollActivity? _scrollActivity;
  bool _scrollActive = false;
  // 滚动停止后是否有待应用的最新高度。
  bool _hasPendingHeightAfterScroll = false;
  // 2026-06-07：首次测量 outlier 检查状态位。首次非跳过的测量若超
  // 出估算高度 × ratio，标记为已处理并应用估算高度（避免"渲染下方
  // 空白"）；之后不再做 outlier 检查，正常走 500ms 防抖路径。
  bool _firstMeasurementHandled = false;
  int get _heightCacheKey => Object.hash(
    widget.data,
    widget.baseTextStyle?.fontSize,
    widget.baseTextStyle?.height,
  );

  @override
  void didUpdateWidget(covariant _HtmlBubbleWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data ||
        oldWidget.textColor != widget.textColor ||
        oldWidget.backgroundColor != widget.backgroundColor) {
      _reload();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextBubble = _BubbleHtmlInteractiveScope.maybeOf(context);
    if (!identical(nextBubble, _bubbleStateForRegion)) {
      _bubbleStateForRegion?.unregisterHtmlInteractiveRegion(_webViewRegionKey);
      _bubbleStateForRegion = nextBubble;
      _bubbleStateForRegion?.registerHtmlInteractiveRegion(
        _webViewRegionKey,
        this,
      );
    }
    // 顶层 _OpenHandHomePageState 注入的滚动活动信号；订阅其 value
    // 变化以在用户滚动期间冻结高度应用。didChangeDependencies 可能
    // 多次触发，但 Provider 拿到的是同一个实例，重复 addListener 不会
    // 出问题——不过为安全起见，先 remove 再 add。
    final activity = context.read<TranscriptScrollActivity>();
    if (!identical(activity, _scrollActivity)) {
      _scrollActivity?.removeListener(_onScrollActivityChanged);
      _scrollActivity = activity;
      _scrollActive = activity.value;
      activity.addListener(_onScrollActivityChanged);
    }
  }

  void _onScrollActivityChanged() {
    final activity = _scrollActivity;
    if (activity == null || !mounted) return;
    final isActive = activity.value;
    if (isActive == _scrollActive) return;
    setState(() => _scrollActive = isActive);
    if (!isActive && _hasPendingHeightAfterScroll) {
      _hasPendingHeightAfterScroll = false;
      _applyPendingHeightIfAny();
    }
  }

  @override
  void dispose() {
    _heightDebounceTimer?.cancel();
    _scrollActivity?.removeListener(_onScrollActivityChanged);
    _scrollActivity = null;
    _bubbleStateForRegion?.unregisterHtmlInteractiveRegion(_webViewRegionKey);
    _bubbleStateForRegion = null;
    // State 被 ListView 回收前，把当前真实高度保存为 floor。
    // 新 State 重建后若 _height 丢失，可用此 floor 防止收缩。
    if (_height != null) {
      _heightFloorCache[_heightCacheKey] = _height!;
    }
    super.dispose();
  }

  Future<void> _reload() async {
    final controller = _controller;
    if (controller == null) return;
    // 内容/样式变化时清除旧高度缓存与 floor，避免新内容被旧大值撑出空白。
    _heightCache.remove(_heightCacheKey);
    _heightFloorCache.remove(_heightCacheKey);
    // 文档字符串缓存一并失效，下一次 _buildDocument() 会按新 data/颜色
    // 重新拼装。
    _documentCacheData = null;
    _documentCacheTextColor = null;
    _documentCacheBackgroundColor = null;
    _documentCache = null;
    setState(() {
      _height = null;
      _hasError = false;
    });
    _measurementCount = 0;
    _heightDebounceTimer?.cancel();
    try {
      await controller.loadData(data: _buildDocument());
    } catch (error, stack) {
      silentLog(
        'home_message_content',
        'html bubble reload failed',
        error,
        stack,
      );
    }
  }

  void _onContentSizeChanged(Size newSize) {
    final next = newSize.height
        .clamp(_kMinHeightClamp, _kMaxHeightClamp)
        .toDouble();
    if (!mounted) return;
    _measurementCount++;
    // CSS reset 前的全文档高度可能异常大（如 16222），直接应用会导致
    // 卡片闪变和缓存错误值。仅跳过此类不合理超大值，正常高度立即应用。
    // 否则 JS 端已记录 __lastReportedHeight，Flutter 端跳过首个测量后
    // 再无差值 >0.5px 的回调触发，形成 JS/Flutter 双端死锁。
    if (_measurementCount == 1 && next > _kFirstMeasurementSkipThreshold) {
      return;
    }
    // 2026-06-07（HTML 卡片上滑抽搐 bug 关键修复）：用户正在滚动外层
    // ListView 时，WebView 的 ResizeObserver / MutationObserver 也会
    // 持续回测高度。如果立即 apply 触发 setState → SliverList 重新
    // 布局 → maxScrollExtent 抖动 → Flutter clamp 滚动位置 → 视口被
    // 拽回底部。此期间只缓存最新值，滚动结束由
    // `_onScrollActivityChanged` 一次性应用。
    if (_scrollActive) {
      _pendingHeight = next;
      _hasPendingHeightAfterScroll = true;
      return;
    }
    // 2026-06-07：首次非跳过的测量做 outlier 检查。WebView 首测常因
    // 图片/CSS 未完成返回异常大值，直接应用会撑出"渲染下方空白"。
    // 若超出估算高度 × ratio，改用估算高度作初始显示值，后续测量
    // 经 500ms 防抖会修正到准确值。视觉上是"由小到大"生长，比
    // "由大到小收缩留下空白"更可接受。仅对首测做一次判定，避免后
    // 续正常 reflow 持续被当成 outlier 抑制。
    if (!_firstMeasurementHandled) {
      _firstMeasurementHandled = true;
      final estimated = _estimateHeight();
      if (next > estimated * _kFirstMeasurementOutlierRatio) {
        // outlier 占位高度只写本地 _height，**绝不写入任何持久化 cache**，
        // 避免 estimatedHeight 污染 _heightCache / _heightFloorCache。
        setState(() => _height = estimated);
        return;
      }
    }
    // 注：参考高度 outlier 检查已**下沉到 _applyHeight**，覆盖所有
    // 上游路径（scroll-active 缓存、pending apply、debounce timer）。
    if (_height != null && (next - _height!).abs() < _kMinHeightDelta) {
      return;
    }
    if (_height != null) {
      final changeRatio = (next - _height!).abs() / _height!;
      // 大幅变化优先立即应用，但 250ms 内最多一次，阻断 resize 闭环振荡。
      if (changeRatio >= _kLargeChangeRatio) {
        final lastApply = _lastHeightApplyTime;
        if (lastApply != null &&
            DateTime.now().difference(lastApply) < _kMinHeightApplyInterval) {
          _pendingHeight = next;
          final timer = _heightDebounceTimer;
          if (timer == null || !timer.isActive) {
            _heightDebounceTimer = Timer(_kHeightDebounceDuration, () {
              if (!mounted) return;
              final pending = _pendingHeight;
              _heightDebounceTimer = null;
              _pendingHeight = null;
              if (pending == null) return;
              if (_height != null &&
                  (pending - _height!).abs() < _kMinHeightDelta) {
                return;
              }
              _applyHeight(pending);
            });
          }
          return;
        }
        _heightDebounceTimer?.cancel();
        _heightDebounceTimer = null;
        _pendingHeight = null;
        _applyHeight(next);
        return;
      }
    }
    // 小幅变化：累积最新测量值，启动/沿用 500ms 一次性稳定定时器；
    // **不在每次新测量时重置定时器**，确保在 WebView 持续以 16-30ms 频率
    // 回流的情况下定时器也必然在 500ms 后触发，应用累积终值。
    _pendingHeight = next;
    final timer = _heightDebounceTimer;
    if (timer == null || !timer.isActive) {
      _heightDebounceTimer = Timer(_kHeightDebounceDuration, () {
        if (!mounted) return;
        final pending = _pendingHeight;
        _heightDebounceTimer = null;
        _pendingHeight = null;
        if (pending == null) return;
        if (_height != null && (pending - _height!).abs() < _kMinHeightDelta) {
          return;
        }
        _applyHeight(pending);
      });
    }
  }

  void _applyHeight(double next) {
    // 2026-06-07：outlier 检查**集中**在 apply 入口——所有上游路径
    //（scroll-active 缓存、pending apply、debounce timer、immediate
    // apply）都通过本方法落地，确保"rendered → raw → rendered"跳变
    // 在任何路径下都被拒收。参考高度优先级：floor（dispose 时写入的
    // 真实高度）> current _height > cached。瞬态测量（CSS reset 注
    // 入/字体回退/图片懒加载/卡片重进 viewport 触发的二次 layout）
    // 返回的"原始 HTML 文本高度"通常 > 1.5× 真实渲染高度，直接判
    // 为噪声保留旧值。
    final refHeight =
        _heightFloorCache[_heightCacheKey] ??
        _height ??
        _heightCache[_heightCacheKey];
    if (refHeight != null && refHeight > 0) {
      final refRatio = next / refHeight;
      if (refRatio > _kReferenceOutlierRatio) {
        return;
      }
    }
    _heightCache[_heightCacheKey] = next;
    if (_heightCache.length > _kHeightCacheMaxSize) {
      _heightCache.remove(_heightCache.keys.first);
    }
    _lastHeightApplyTime = DateTime.now();
    setState(() => _height = next);
  }

  /// 滚动停止后应用滚动期间累积的最近一次高度测量。统一走 `_applyHeight`
  /// 走 outlier 检查，避免 scroll-active 缓存路径绕过校验。差值过小则
  /// 忽略，与原语义一致。
  void _applyPendingHeightIfAny() {
    final pending = _pendingHeight;
    if (pending == null) return;
    _pendingHeight = null;
    if (_height != null && (pending - _height!).abs() < _kMinHeightDelta) {
      return;
    }
    _applyHeight(pending);
  }

  /// macOS Flutter embedder 不会把鼠标 NSEvent 转发给嵌入的 WKWebView
  /// 平台视图——Flutter Listener 看得到 DOWN/UP，但 DOM 完全收不到 click。
  /// 外层气泡 Listener 在检测到在此 WebView 区域内 tap-like 抬起时调用
  /// 此方法，以 globalToLocal 折算到 WebView 内坐标后用 evaluateJavascript 在
  /// document.elementFromPoint() 上依次合成 mousedown / mouseup / click
  /// （表单控件额外 .focus()）。这样 `<details>` / `<summary>` / `<a>` /
  /// `<button>` / `<input>` 都可以交互。
  Future<void> simulateTapAtGlobal(Offset globalPosition) async {
    final controller = _controller;
    if (controller == null) return;
    final context = _webViewRegionKey.currentContext;
    final renderObject = context?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return;
    final local = renderObject.globalToLocal(globalPosition);
    final x = local.dx.toStringAsFixed(2);
    final y = local.dy.toStringAsFixed(2);
    try {
      await controller.evaluateJavascript(
        source:
            "(function(){try{var x=$x,y=$y;var el=document.elementFromPoint(x,y);if(!el)return;var opts={bubbles:true,cancelable:true,composed:true,view:window,clientX:x,clientY:y,button:0};try{el.dispatchEvent(new PointerEvent('pointerdown',Object.assign({pointerType:'mouse',isPrimary:true},opts)));}catch(_){}el.dispatchEvent(new MouseEvent('mousedown',opts));try{el.dispatchEvent(new PointerEvent('pointerup',Object.assign({pointerType:'mouse',isPrimary:true},opts)));}catch(_){}el.dispatchEvent(new MouseEvent('mouseup',opts));el.dispatchEvent(new MouseEvent('click',opts));if(typeof el.focus==='function'){try{el.focus();}catch(_){}}}catch(_){}})();",
      );
    } catch (error, stack) {
      silentLog(
        'home_message_content',
        'html bubble simulate tap failed',
        error,
        stack,
      );
    }
  }

  Future<void> beginSelectionAtGlobal(Offset globalPosition) async {
    HtmlSelectionBridgeClipboard.clear();
    _selectionAnchorGlobalPosition = globalPosition;
    _selectionBridgeStarted = false;
    _pendingSelectionUpdate = null;
  }

  void updateSelectionAtGlobal(Offset globalPosition) {
    if (_selectionUpdateInFlight) {
      _pendingSelectionUpdate = globalPosition;
      return;
    }
    _selectionUpdateInFlight = true;
    unawaited(
      _runSelectionUpdate(globalPosition).whenComplete(() {
        _selectionUpdateInFlight = false;
        final pending = _pendingSelectionUpdate;
        _pendingSelectionUpdate = null;
        if (pending != null && mounted) {
          updateSelectionAtGlobal(pending);
        }
      }),
    );
  }

  Future<void> finishSelectionAtGlobal(Offset globalPosition) async {
    _pendingSelectionUpdate = null;
    await _ensureSelectionAnchorStarted();
    await _runSelectionBridge('end', globalPosition);
    _selectionAnchorGlobalPosition = null;
    _selectionBridgeStarted = false;
  }

  Future<void> _runSelectionUpdate(Offset globalPosition) async {
    await _ensureSelectionAnchorStarted();
    await _runSelectionBridge('update', globalPosition);
  }

  Future<void> _ensureSelectionAnchorStarted() async {
    if (_selectionBridgeStarted) return;
    final anchor = _selectionAnchorGlobalPosition;
    if (anchor == null) return;
    _selectionBridgeStarted = true;
    await _runSelectionBridge('start', anchor);
  }

  Future<void> _runSelectionBridge(String kind, Offset globalPosition) async {
    final controller = _controller;
    if (controller == null) return;
    final context = _webViewRegionKey.currentContext;
    final renderObject = context?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return;
    final local = renderObject.globalToLocal(globalPosition);
    final x = local.dx.toStringAsFixed(2);
    final y = local.dy.toStringAsFixed(2);
    try {
      final result = await controller.evaluateJavascript(
        source:
            "(function(){try{if(window.__openhandSelectionBridge){return window.__openhandSelectionBridge('$kind',$x,$y)||'';}return '';}catch(_){return '';}})();",
      );
      HtmlSelectionBridgeClipboard.update(result?.toString());
    } catch (error, stack) {
      silentLog(
        'home_message_content',
        'html bubble selection bridge failed',
        error,
        stack,
      );
    }
  }

  String _buildDocument() {
    // 2026-06-07：按 (data 引用, textColor 引用, backgroundColor 引用) 命中
    // 复用已拼装的文档字符串。build 阶段被 WebView reload 路径
    // （didUpdateWidget 触发 _reload）会主动调用 buildDocument() 刷新
    // 缓存；普通 rebuild 命中后直接返回缓存，跳过 1-2KB 字符串拼装 +
    // RegExp 扫描 + healUnbalancedHtml。
    if (identical(_documentCacheData, widget.data) &&
        identical(_documentCacheTextColor, widget.textColor) &&
        identical(_documentCacheBackgroundColor, widget.backgroundColor) &&
        _documentCache != null) {
      return _documentCache!;
    }
    String hex(Color c) {
      final r = (c.r * 255).round() & 0xff;
      final g = (c.g * 255).round() & 0xff;
      final b = (c.b * 255).round() & 0xff;
      return '#${r.toRadixString(16).padLeft(2, '0')}'
          '${g.toRadixString(16).padLeft(2, '0')}'
          '${b.toRadixString(16).padLeft(2, '0')}';
    }

    final base = widget.baseTextStyle;
    final fontSize = (base?.fontSize ?? 14).toStringAsFixed(2);
    final lineHeight = (base?.height ?? 1.55).toStringAsFixed(2);
    final fontFamily = base?.fontFamily;
    final family = (fontFamily == null || fontFamily.isEmpty)
        ? '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, "PingFang SC", "Microsoft YaHei", sans-serif'
        : '"$fontFamily", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif';
    final textHex = hex(widget.textColor);
    final bgHex = hex(widget.backgroundColor);
    // 先做轻量自愈：补齐 AI 侧因 `max_tokens` 截断后未闭合的 `<div>` /
    // `<table>` 等，避免浏览器 parser 与 wfh fallback 路径把未闭合
    // 标签解释成 0 高度占位（用户视觉上就是"空消息卡 / 展开后空"）。
    final healed = _healUnbalancedHtml(widget.data);
    final source = healed.trimLeft();

    final String result;
    if (_documentShellPattern.hasMatch(source)) {
      result = _injectEmbeddedDocumentReset(healed);
    } else {
      result =
          '<!DOCTYPE html>'
          '<html><head><meta charset="utf-8">'
          '<meta name="viewport" content="width=device-width, initial-scale=1">'
          '<style>'
          'html,body{margin:0;padding:0;background:$bgHex;color:$textHex;'
          'font-family:$family;font-size:${fontSize}px;line-height:$lineHeight;'
          '-webkit-text-size-adjust:100%;text-rendering:optimizeLegibility;'
          '-webkit-font-smoothing:antialiased;'
          '-webkit-user-select:text;user-select:text;cursor:text;}'
          'body{overflow-x:auto;}'
          // 2026-05-25: 用独立的 oh-root 包裹负责提供"内容本身"的几何尺寸，
          // 避免 JS 用 document.scrollHeight 读到的是被 Flutter 侧 SizedBox 高度
          // 裹挟后的值（那样在 <details> 收起后高度不会变小，气泡只能变大
          // 不能变小）。oh-root 以 flow-root 阻断子元素 margin 折叠，真实
          // 高度由 JS 动态扫描可见内容底边给出，不再追加固定留白。
          '#oh-root{display:flow-root;width:100%;min-height:1px;'
          'height:auto;box-sizing:border-box;padding:2px;'
          'overflow:visible;}'
          '#oh-root,#oh-root *{-webkit-user-select:text;user-select:text;}'
          'a,button,summary,[role="button"]{cursor:pointer;}'
          'input,textarea,select{cursor:text;}'
          'img,video,canvas,svg{max-width:100%;height:auto;}'
          'pre,code{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;}'
          'pre{overflow-x:auto;}'
          'table{border-collapse:collapse;}'
          'a{color:inherit;}'
          '</style></head>'
          '<body><div id="oh-root">$healed</div></body></html>';
    }
    _documentCacheData = widget.data;
    _documentCacheTextColor = widget.textColor;
    _documentCacheBackgroundColor = widget.backgroundColor;
    _documentCache = result;
    return result;
  }

  String _injectEmbeddedDocumentReset(String html) {
    final headClose = _headClosePattern.firstMatch(html);
    if (headClose != null) {
      return html.replaceRange(
        headClose.start,
        headClose.start,
        _embeddedDocumentResetStyle,
      );
    }
    final headOpen = _headOpenPattern.firstMatch(html);
    if (headOpen != null) {
      return html.replaceRange(
        headOpen.end,
        headOpen.end,
        _embeddedDocumentResetStyle,
      );
    }
    return '$_embeddedDocumentResetStyle$html';
  }

  /// 按内容长度粗略估算 HTML 渲染后占据的高度，用于 shimmer 占位期间
  /// 给一个"不至于突然伸长/收缩"的初始高度。公式：
  /// `行数 = ceil(字符数 / 每行字符数)`，`高度 = 行数 * 行高`，clamp
  /// 到 `_kEstimatedMinHeight` / `_kEstimatedMaxHeight`。
  /// HTML 标签、图片、表格等会让真实高度偏离估算，但只用作占位期
  /// 几百毫秒内的视觉占位，精度足够。
  double _estimateHeight() {
    return _estimateHtmlBubbleHeight(widget.data);
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return _HtmlMessageBody(
        data: widget.data,
        textColor: widget.textColor,
        baseTextStyle: widget.baseTextStyle,
      );
    }
    final cachedHeight = _heightCache[_heightCacheKey];
    final floor = _heightFloorCache[_heightCacheKey];
    // 2026-06-07：仅在"完全没有任何高度可参考"时显示 shimmer 骨架屏。
    // 一旦 `_height` 或 `cachedHeight` 有值就切到真实 WebView。逻辑
    // 简洁可靠：500ms 防抖让首测在 500ms 内被应用，shimmer 不会停留
    // 太久；cachedHeight 处理"下滑后上滑"——用户见过此内容，state
    // 重建时 cachedHeight 命中，直接显示 WebView，无须等待 JS 测量。
    // 首次测量的"渲染下方空白"问题由 `_onContentSizeChanged` 中的
    // outlier 检查（超出估算高度 × ratio 时改用估算值）解决。
    final showShimmer = _height == null && cachedHeight == null;
    final estimatedHeight = _estimateHeight();
    // 2026-06-07：跨 State 单调 floor——State dispose 时把真实高度写入
    // `_heightFloorCache`，新 State 重建后若 _height 丢失则用 floor
    // 兜底，防止 Stack 高度收缩到 estimatedHeight 导致 maxScrollExtent
    // 抖动。floor 与 cache 分离，outlier 占位估计绝不写入，避免污染。
    // 正常运营期间（同 State 内）允许 _height 自由减小，不受 floor 限制。
    final baseDisplayHeight = _height ?? cachedHeight ?? estimatedHeight;
    final displayHeight = floor != null && baseDisplayHeight < floor
        ? floor
        : baseDisplayHeight;

    // WebView 必须始终在 widget 树中——它加载 HTML 并通过 JS 回调报告高度。
    // 2026-06-07：改用 Stack 叠加（shimmer 在 WebView 之上），让 shimmer
    // 阶段与 WebView 阶段占父级空间完全一致（仅 WebView 撑起 Stack
    // 高度 = displayHeight），消除旧 Column 模式 shimmer 阶段
    // `displayHeight + 1.0` 与 WebView 阶段 `displayHeight` 之间的
    // 1px 跳变——该跳变在用户处于"距 maxScrollExtent 较近"位置时
    // 触发 Flutter clamp 滚动位置，表现为"强制往下滚动"的偶发
    // UI 异常。Stack 模式从根上消除该高度差。
    final webViewChild = RepaintBoundary(
      // 2026-06-07：WebView 高度回调 → setState → RepaintBoundary 隔离
      // 之后只重绘 WebView 自身的 layer，不再让外层消息卡（外层有阴影 /
      // border / AnimatedSize / ActionButtons 等复杂 layout）跟着整张重
      // 绘。长会话滚动期间 8-15 个 HTML 气泡同时有 WebView 在跑 ResizeObserver，
      // 一次 setState 就会拖累整页 paint，RepaintBoundary 阻断这层
      // repaint 蔓延。
      child: KeyedSubtree(
        key: _webViewRegionKey,
        child: iaw.InAppWebView(
          initialData: iaw.InAppWebViewInitialData(data: _buildDocument()),
          initialSettings: iaw.InAppWebViewSettings(
            transparentBackground: !Platform.isMacOS,
            disableVerticalScroll: true,
          ),
          onWebViewCreated: (controller) {
            _controller = controller;
            controller.addJavaScriptHandler(
              handlerName: 'OpenHandHeight',
              callback: (args) {
                if (args.isEmpty) return;
                final raw = args.first;
                final value = raw is num
                    ? raw.toDouble()
                    : double.tryParse(raw.toString());
                if (value == null || !value.isFinite) return;
                _onContentSizeChanged(Size(0, value));
              },
            );
          },
          onLoadStop: (controller, url) async {
            try {
              await controller.evaluateJavascript(
                source: _heightObserverScript,
              );
              await controller.evaluateJavascript(
                source: _selectionBridgeScript,
              );
            } catch (error, stack) {
              silentLog(
                'home_message_content',
                'html bubble height observer install failed',
                error,
                stack,
              );
            }
          },
          onReceivedError: (controller, request, error) {
            silentLog(
              'home_message_content',
              'html bubble webview error',
              error,
            );
            if (mounted) {
              setState(() => _hasError = true);
            }
          },
        ),
      ),
    );

    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    // Q 弹进场：流式结束 → 一次性渲染 HTML 时，给 WebView 加一次 fade+scale
    // 进场动画。曲线与全局卡片动效一致（轻微 overshoot 的回弹）。
    final entrance = TweenAnimationBuilder<double>(
      key: const ValueKey<String>('openhand.htmlBubble.entrance'),
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: reduceMotion ? Duration.zero : kCardMotionDurationExpand,
      curve: reduceMotion ? Curves.linear : kCardMotionCurve,
      builder: (context, value, child) {
        return Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.985 + 0.015 * value,
            alignment: Alignment.topCenter,
            child: child,
          ),
        );
      },
      child: Stack(
        children: [
          // 2026-06-07：Container(color: widget.backgroundColor) 作为
          // macOS WKWebView 默认白底的 fallback——HTML 加载完成前避免
          // 闪一下白屏与气泡底色形成强烈对比。其他平台
          // transparentBackground: true 时同样受益，HTML 没设背景时
          // 容器色自然透出与气泡衔接。
          // 2026-06-07：loading 阶段用 Opacity(0) 隐藏 WebView 内容——
          // 旧版 shimmer 透明叠加在 WebView 之上导致 HTML 渲染字符与骨架
          // 条同时可见，UI 杂乱。隐藏 WebView 后用户只看到骨架屏，加载
          // 完成后由 setState 触发 WebView 显示，衔接由外层 entrance
          // TweenAnimationBuilder 的 fade+scale 落位动画保证自然 Q 弹。
          Container(
            color: widget.backgroundColor,
            child: SizedBox(
              width: double.infinity,
              height: displayHeight,
              child: Opacity(
                opacity: showShimmer ? 0.0 : 1.0,
                child: webViewChild,
              ),
            ),
          ),
          // 2026-06-07：用 Stack 叠加替代 Column 堆叠——shimmer 永远
          // 覆盖在 WebView 之上，**两个阶段 Column/Stretch 占的父级空间
          // 始终一致**（仅 WebView 撑起 Stack 高度 = displayHeight）。
          // 旧 Column 模式 shimmer 阶段 = `displayHeight + 1.0`（shimmer
          // + 1px WebView）、WebView 阶段 = `displayHeight`，切换瞬间存在
          // 1px 高度跳变 → 在用户处于"距 maxScrollExtent 较近"的位置时
          // 触发 Flutter clamp 滚动位置，表现为"强制往下滚动一段距离"
          // 的偶发性 UI 异常。Stack 模式从根上消除该高度差。
          if (showShimmer) const Positioned.fill(child: _HtmlBubbleShimmer()),
        ],
      ),
    );
    return entrance;
  }
}

/// 助手消息正文按"消息内容格式"设置分派：
/// - Markdown：原有 `_CollapsibleMessageMarkdownBody`
/// - 纯文本：`_PlainTextMessageBody`
/// - HTML：内容像 HTML → `_HtmlBubbleWebView`（WebView 高保真渲染 + 手动文本选择桥）；否则按回退链跳到 Markdown 或纯文本
///
/// 当 `isStreaming` 为 true 且格式为 HTML 时：
/// - 不直接渲染 AI 侧流式追加的原始 HTML 字符（避免大量 `<div>...</div>`
///   给用户带来困惑与迷失感）；
/// - 改为渲染 `_StreamingHtmlPlaceholder` 骨架屏 + 状态提示；
/// - 流式结束后通过一次性 body 模式切换进入真正的 `_HtmlBubbleWebView`，
///   并给最终 body 一个轻量 fade+scale 落位。
class _AssistantMessageBodyDispatcher extends StatelessWidget {
  const _AssistantMessageBodyDispatcher({
    required this.data,
    required this.format,
    required this.htmlFallback,
    required this.textColor,
    required this.backgroundColor,
    required this.markdownBuilders,
    required this.markdownStyleSheet,
    required this.inlineSyntaxes,
    required this.filePathRoots,
    required this.filePathParseKey,
    required this.collapseCharThreshold,
    required this.collapseLineThreshold,
    required this.previewMaxHeight,
    this.wrapInSelectionArea = true,
    this.isStreaming = false,
  });

  final String data;
  final AiMessageContentFormat format;
  final AiHtmlRenderFallback htmlFallback;
  final Color textColor;
  final Color backgroundColor;
  final Map<String, MarkdownElementBuilder> markdownBuilders;
  final MarkdownStyleSheet markdownStyleSheet;
  final List<md.InlineSyntax> inlineSyntaxes;
  final List<String> filePathRoots;
  final String filePathParseKey;
  final int collapseCharThreshold;
  final int collapseLineThreshold;
  final double previewMaxHeight;
  final bool wrapInSelectionArea;
  final bool isStreaming;

  Widget _wrapSelection(Widget child) {
    if (!wrapInSelectionArea) return child;
    return SelectionArea(child: child);
  }

  Widget _buildMarkdownOrFallback() {
    // Markdown 格式智能回退：仅当内容整体看起来像 HTML 文档时，才优先尝试
    // HTML 渲染。若消息里已经出现 fenced code block，则必须坚持走 Markdown
    // 路径 —— 代码块正文可能合法包含 `<br/>` / `<div>` / `<table>` 等字样
    //（典型如 mermaid、HTML 示例代码），此时回退到 WebView 会把整个 fenced
    // block 当普通文本吃掉，导致代码块/mermaid 完全失效。
    final normalized = data.trim();
    if (_startsWithFencedMermaidBlock(normalized) ||
        _containsMarkdownCodeFence(normalized)) {
      return _buildMarkdown();
    }
    final bool hasHtmlLikeTags = _looksLikeHtml(data);
    final bool hasTagStructure = !hasHtmlLikeTags && _hasHtmlTagStructure(data);

    if (hasHtmlLikeTags || hasTagStructure) {
      return SizedBox(
        width: double.infinity,
        child: _DeferredHtmlBubbleWebView(
          key: ValueKey(Object.hash(data, textColor)),
          data: data,
          textColor: textColor,
          backgroundColor: backgroundColor,
          baseTextStyle: markdownStyleSheet.p,
        ),
      );
    }
    return _buildMarkdown();
  }

  Widget _buildMarkdown() {
    return _CollapsibleMessageMarkdownBody(
      data: data.isEmpty ? ' ' : data,
      selectable: !wrapInSelectionArea,
      builders: markdownBuilders,
      styleSheet: markdownStyleSheet,
      inlineSyntaxes: inlineSyntaxes,
      pathRoots: filePathRoots,
      parseKey: filePathParseKey,
      fadeColor: backgroundColor,
      collapseCharThreshold: collapseCharThreshold,
      collapseLineThreshold: collapseLineThreshold,
      previewMaxHeight: previewMaxHeight,
    );
  }

  Widget _buildPlainText() {
    return _PlainTextMessageBody(
      data: data.isEmpty ? ' ' : data,
      textColor: textColor,
      backgroundColor: backgroundColor,
      style: markdownStyleSheet.p,
    );
  }

  Widget _buildHtmlOrFallback() {
    // 优先尝试 HTML 渲染：
    // 1. 首先用 `_looksLikeHtml` 检查是否包含常见 HTML 标签（白名单）；
    // 2. 如果不在白名单但内容含有「<标签名>」形式的结构（宽松启发式），
    //    也尝试 HTML 渲染——这能捕获 AI 输出中 `<del>` / `<kbd>` 等白名单外
    //    的有效标签，避免它们被误判为纯文本而显示原生标签字符。
    // 3. HTML 渲染失败时再走 `htmlFallback` 降级链：markdown → plainText。
    //
    // WebView 内置 HTML 解析器对未闭合标签有原生容错，且 `_HtmlBubbleWebView
    // ._buildDocument` 会先走 `_healUnbalancedHtml` 轻量自愈，进一步降低
    // layout 阶段崩溃的概率；旧版本走 markdown fallback 时，未闭合的
    // `<table>` 经常渲染成 0 高度占位 → 用户看到的就是「空白卡片 / 展开后空」。
    final bool hasHtmlLikeTags = _looksLikeHtml(data);
    final bool hasTagStructure = !hasHtmlLikeTags && _hasHtmlTagStructure(data);

    if (hasHtmlLikeTags || hasTagStructure) {
      return SizedBox(
        width: double.infinity,
        child: _DeferredHtmlBubbleWebView(
          key: ValueKey(Object.hash(data, textColor)),
          data: data,
          textColor: textColor,
          backgroundColor: backgroundColor,
          baseTextStyle: markdownStyleSheet.p,
        ),
      );
    }
    // 不像 HTML 时走 fallback 降级链。
    return htmlFallback == AiHtmlRenderFallback.plainText
        ? _buildPlainText()
        : _buildMarkdown();
  }

  /// 把内部渲染产物按"是否处于流式阶段"做一次性模式切换：
  /// - 流式中且格式为 HTML → 骨架屏占位；
  /// - 流式结束 → 真正的格式分支（带智能回退）。
  /// 这里的 AnimatedSwitcher 只负责 body 级别的 fade+scale 落位，不承担
  /// 尺寸插值；高度动画统一交给外层消息气泡。
  Widget _buildDispatchedBody() {
    if (isStreaming && format == AiMessageContentFormat.html) {
      return _StreamingHtmlPlaceholder(
        textColor: textColor,
        contentLength: data.length,
      );
    }
    return switch (format) {
      AiMessageContentFormat.plainText => _buildPlainText(),
      AiMessageContentFormat.html => _buildHtmlOrFallback(),
      AiMessageContentFormat.markdown => _buildMarkdownOrFallback(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final body = AnimatedSwitcher(
      duration: cardMotionDurationFor(context, expanding: !isStreaming),
      switchInCurve: kCardMotionCurve,
      switchOutCurve: Curves.easeOutCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.topLeft,
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        final fade = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        final scale = Tween<double>(begin: 0.985, end: 1.0).animate(
          CurvedAnimation(
            parent: animation,
            curve: kCardMotionCurve,
            reverseCurve: Curves.easeInCubic,
          ),
        );
        return FadeTransition(
          opacity: fade,
          child: ScaleTransition(
            scale: scale,
            alignment: Alignment.topCenter,
            child: child,
          ),
        );
      },
      child: KeyedSubtree(
        key: ValueKey<String>(
          '${format.storageKey}|${isStreaming ? 'streaming' : 'stable'}|${wrapInSelectionArea ? 'select' : 'plain'}',
        ),
        child: _buildDispatchedBody(),
      ),
    );
    return _wrapSelection(body);
  }
}
