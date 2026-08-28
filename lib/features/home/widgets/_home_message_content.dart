part of '../openhand_home_page.dart';

// Long messages parse only a bounded preview until the user expands them,
// keeping initial rendering of large transcripts responsive.
const int _messageMarkdownCollapseCharThreshold = 2400;
const int _toolResultMarkdownCollapseCharThreshold = 800;
const int _messageMarkdownCollapseLineThreshold = 45;
const int _markdownCollapsedPreviewMaxChars = 1200;
const int _plainTextCollapsedPreviewMaxChars = 1600;
const double _messageResponsePreviewMaxHeight = 240;
const double _toolResultPreviewMaxHeight = 176;
const double _collapsedMessageFadeHeight = 40;
const Duration _collapsedMessageFadeDuration = kOpenHandMotion160;
const Duration _collapsedPreviewScrollSettleDelay = Duration(milliseconds: 220);
const Duration _streamingHtmlDotsDuration = Duration(milliseconds: 1100);
const Duration _htmlBubbleShimmerDuration = kOpenHandMotion1400;
const double _collapsedPreviewBottomEnterEpsilon = 2;
const double _collapsedPreviewBottomExitEpsilon = 10;
const int _collapsedBodyScrollOffsetCacheLimit = 500;

/// Maximum message body size (in characters) at which we still attempt
/// markdown parsing. Above this we render the raw text directly to keep
/// transcript open / scroll responsive — `flutter_markdown_plus` runs the
/// AST parse and widget build synchronously on the UI thread, and at this
/// size both passes start to dominate frame budgets and trigger ANR.
const int _markdownPlainTextSkipThresholdChars = 120 * kBytesPerKiB;
const int _toolResultMarkdownCollapseLineThreshold = 32;
const int _htmlPreparedCacheMaxEntries = 160;
const int _htmlPreparedCacheMaxCost = 2 * kBytesPerMiB;
const int _htmlProgressiveRenderCharThreshold = 14 * kBytesPerKiB;
const int _htmlProgressiveRenderTagThreshold = 160;
const int _htmlProgressiveRenderHighCostTagThreshold = 12;
const int _htmlProgressiveRenderPreviewCharCap = 1800;
const int _htmlProgressiveRenderPreviewScanCharCap = 12 * kBytesPerKiB;
const int _htmlHealFullScanCharLimit = 48 * kBytesPerKiB;
const double _htmlProgressiveRenderPreviewMaxHeight = 220;

String _cssHexFromColor(Color color) {
  final red = (color.r * 255).round();
  final green = (color.g * 255).round();
  final blue = (color.b * 255).round();
  return '#${byteToHex(red)}${byteToHex(green)}${byteToHex(blue)}';
}

abstract final class _CollapsedBodyScrollOffsetCache {
  static final Map<String, double> _offsets = <String, double>{};

  static double? read(String? key) {
    if (key == null || key.isEmpty) return null;
    final value = _offsets.remove(key);
    if (value == null) return null;
    _offsets[key] = value;
    return value;
  }

  static void save(String? key, double value) {
    if (key == null || key.isEmpty) return;
    _offsets.remove(key);
    _offsets[key] = math.max(0, value);
    while (_offsets.length > _collapsedBodyScrollOffsetCacheLimit) {
      _offsets.remove(_offsets.keys.first);
    }
  }

  static void reset(String? key) {
    if (key == null || key.isEmpty) return;
    save(key, 0);
  }
}

void _restoreCollapsedBodyScrollOffset({
  required State<StatefulWidget> state,
  required ScrollController controller,
  required String? key,
  VoidCallback? onRestored,
}) {
  final savedOffset = _CollapsedBodyScrollOffsetCache.read(key);
  if (savedOffset == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!state.mounted || !controller.hasClients) return;
    final position = controller.position;
    final target = savedOffset
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((position.pixels - target).abs() > 0.5) {
      controller.jumpTo(target);
    }
    onRestored?.call();
  });
}

bool _isCollapsedPreviewAtBottom(
  ScrollPosition position, {
  required bool currentlyAtBottom,
}) {
  final maxExtent = position.maxScrollExtent;
  if (maxExtent <= _collapsedPreviewBottomEnterEpsilon) return true;
  final epsilon = currentlyAtBottom
      ? _collapsedPreviewBottomExitEpsilon
      : _collapsedPreviewBottomEnterEpsilon;
  return position.pixels >= maxExtent - epsilon;
}

/// 图片首帧解码完成后的淡入上移时长。
const Duration _kImageFirstFrameRevealDuration = kOpenHandMotion400;

class _CollapsedPreviewScrollCoordinator {
  _CollapsedPreviewScrollCoordinator({
    required this.controller,
    required this.isMounted,
    required this.isUserScrolling,
    required this.setUserScrolling,
  });

  final ScrollController controller;
  final bool Function() isMounted;
  final bool Function() isUserScrolling;
  final ValueChanged<bool> setUserScrolling;
  Timer? _settleTimer;

  void markUserScrolling() {
    if (!isUserScrolling()) {
      setUserScrolling(true);
    }
    armSettleTimer();
  }

  void armSettleTimer() {
    _settleTimer?.cancel();
    _settleTimer = startSafeTimer(_collapsedPreviewScrollSettleDelay, () {
      _settleTimer = null;
      if (!isMounted()) return;
      if (controller.hasClients &&
          controller.position.isScrollingNotifier.value) {
        armSettleTimer();
        return;
      }
      if (isUserScrolling()) {
        setUserScrolling(false);
      }
    });
  }

  void cancelSettleTimer() {
    _settleTimer?.cancel();
    _settleTimer = null;
  }

  void dispose() => cancelSettleTimer();
}

Widget _buildCollapsedPreviewScrollableFrame({
  required BuildContext context,
  required double maxHeight,
  required bool hasOverflow,
  required bool showFade,
  required ScrollController controller,
  required Color fadeColor,
  required bool animateFade,
  required ValueChanged<Size> onSizeChanged,
  required Widget child,
}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final constrainedWidth = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : MediaQuery.sizeOf(context).width;
      // 仅限制最大高度，不预占最大高度；短内容首帧直接收缩，避免异步测量后
      // 再触发外层 AnimatedSize 回缩，造成线程切换时消息列表抖动。
      return SizedBox(
        width: constrainedWidth,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Stack(
            children: [
              ClipRect(
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: false),
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _consumeNestedMessageScrollNotification,
                    child: SingleChildScrollView(
                      controller: controller,
                      primary: false,
                      physics: hasOverflow
                          ? openHandDialogAwareScrollPhysics(context)
                          : const NeverScrollableScrollPhysics(),
                      child: SizedBox(
                        width: constrainedWidth,
                        child: _MeasureSize(
                          onChange: onSizeChanged,
                          child: child,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _CollapsedPreviewFade(
                visible: showFade,
                fadeColor: fadeColor,
                animate: animateFade,
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _CollapsedPreviewFade extends StatelessWidget {
  const _CollapsedPreviewFade({
    required this.visible,
    required this.fadeColor,
    this.animate = true,
  });

  final bool visible;
  final Color fadeColor;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final transcriptScrolling = _isTranscriptScrollActive(context);
    final duration = transcriptScrolling || !animate
        ? Duration.zero
        : openHandMotionDuration(context, _collapsedMessageFadeDuration);
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: visible ? 1.0 : 0.0,
          duration: duration,
          curve: kOpenHandSwitchInCurve,
          child: Container(
            height: _collapsedMessageFadeHeight,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  fadeColor.withValues(alpha: 0),
                  fadeColor.withValues(alpha: 0.94),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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
    this.scrollStateKey,
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
  final String? scrollStateKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final toggleLabel = openHandLocalizedText(
      context,
      zh: expanded ? '收起摘要' : '展开摘要',
      en: expanded ? 'Collapse Summary' : 'Expand Summary',
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggle,
        borderRadius: kOpenHandBorderRadius18,
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
              kOpenHandGap8,
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
                          selectable: selectable,
                          styleSheet: styleSheet,
                          builders: builders,
                          inlineSyntaxes: inlineSyntaxes,
                          pathRoots: pathRoots,
                          parseKey: '$parseKey|compression-preview',
                          scrollStateKey: scrollStateKey == null
                              ? '$parseKey|compression-preview'
                              : '$scrollStateKey|preview',
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
    this.scrollStateKey,
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
  final String? scrollStateKey;

  @override
  Widget build(BuildContext context) {
    if (streaming) {
      return _StreamingReasoningBody(
        content: content,
        expanded: expanded,
        fadeColor: fadeColor,
        textColor: textColor,
        styleSheet: styleSheet,
        scrollStateKey: scrollStateKey == null
            ? '$parseKey|streaming-reasoning-preview'
            : '$scrollStateKey|streaming-preview',
      );
    }
    // 折叠态：展示前 5-6 行预览（maxHeight ≈ 142）并在底部叠渐隐遮罩，
    // 给用户「开始阅读」的锚点，与 WEB 端 ReasoningCollapsibleBody 对齐。
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
              selectable: selectable,
              styleSheet: styleSheet,
              builders: builders,
              inlineSyntaxes: inlineSyntaxes,
              pathRoots: pathRoots,
              parseKey: '$parseKey|reasoning-preview',
              scrollStateKey: scrollStateKey == null
                  ? '$parseKey|reasoning-preview'
                  : '$scrollStateKey|preview',
              fadeColor: fadeColor,
            ),
          );
  }
}

class _StreamingReasoningBody extends StatelessWidget {
  const _StreamingReasoningBody({
    required this.content,
    required this.expanded,
    required this.fadeColor,
    required this.textColor,
    required this.styleSheet,
    this.scrollStateKey,
  });

  final String content;
  final bool expanded;
  final Color fadeColor;
  final Color textColor;
  final MarkdownStyleSheet styleSheet;
  final String? scrollStateKey;

  @override
  Widget build(BuildContext context) {
    final effectiveContent = content.isEmpty ? ' ' : content;
    final textStyle = styleSheet.p?.copyWith(color: textColor);
    // 流式思考阶段保持纯文本：Markdown/代码块在逐 token 成型时会不断改变
    // 布局高度，容易把下方 tool-call pending 卡片顶上顶下。待流式结束后，
    // _ReasoningBody 会切回 _SafeMarkdownBody 做完整富文本渲染。
    return expanded
        ? KeyedSubtree(
            key: const ValueKey<String>('streaming-reasoning-plain-expanded'),
            child: StreamingTextRevealText(
              text: effectiveContent,
              streaming: true,
              animateSize: false,
              builder: (context, visibleContent) => _StreamingAssistantTextBody(
                data: visibleContent.isEmpty ? ' ' : visibleContent,
                textColor: textColor,
                backgroundColor: fadeColor,
                style: textStyle,
              ),
            ),
          )
        : KeyedSubtree(
            key: const ValueKey<String>('streaming-reasoning-plain-preview'),
            child: _PlainTextPreviewBody(
              data: effectiveContent,
              maxHeight: _reasoningPreviewMaxHeight,
              style: textStyle,
              textColor: textColor,
              fadeColor: fadeColor,
              scrollStateKey: scrollStateKey,
            ),
          );
  }
}

/// 思考卡片的折叠预览高度。≈ 6 行 × 22px line-height + 小呼吸，
/// 和 WEB 端 REASONING_PREVIEW_MAX_HEIGHT_PX 对齐。
const double _reasoningPreviewMaxHeight = 142;

/// 折叠预览体（纯文本 / Markdown）共用的滚动与截断生命周期。
///
/// 两个预览体此前各写一份滚动位置恢复、到底判定、内容高度锁定与用户滚动
/// 抑制逻辑；任一处修补都要记得同步另一处。差异只剩「滚动状态键」「预览字符
/// 上限」和渲染的子树，交由实现方给出。
mixin _CollapsedPreviewBodyState<T extends StatefulWidget> on State<T> {
  late final ScrollController _scrollController;
  late final _CollapsedPreviewScrollCoordinator _scrollCoordinator;
  double? _contentHeight;
  bool _atBottom = false;
  int? _lockedPreviewLength;
  // 用户滚动预览区期间跳过高度变化通知，防止外层视口被拽回底部。
  bool _userScrollingPreview = false;

  /// 预览原文。
  String get _previewSource;

  /// 预览区最大高度，超出后出现渐隐并允许内部滚动。
  double get _previewMaxHeight;

  /// 预览渲染的字符上限。
  int get _previewCharCap;

  /// 滚动位置缓存键；内容标识变化时应随之变化。
  String get _scrollStateKey;

  int get _previewDataLength {
    final data = _previewSource.isEmpty ? ' ' : _previewSource;
    final cappedLength = math.min(data.length, _previewCharCap);
    final lockedLength = _lockedPreviewLength;
    return lockedLength == null
        ? cappedLength
        : math.min(cappedLength, lockedLength);
  }

  /// 截断后的预览文本。裸 substring 会从中间切断 UTF-16 代理对（emoji /
  /// CJK 扩展 B），预览尾部会渲染成替换字形，因此统一走窗口化截断。
  String get _effectiveData {
    final data = _previewSource.isEmpty ? ' ' : _previewSource;
    return TranscriptListWindowing.boundedContentPreview(
      data,
      maxCharacters: _previewDataLength,
    );
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(
      initialScrollOffset:
          _CollapsedBodyScrollOffsetCache.read(_scrollStateKey) ?? 0,
    );
    _scrollCoordinator = _CollapsedPreviewScrollCoordinator(
      controller: _scrollController,
      isMounted: () => mounted,
      isUserScrolling: () => _userScrollingPreview,
      setUserScrolling: _setUserScrollingPreview,
    );
    _scrollController.addListener(_onScroll);
    _restoreScrollOffset();
  }

  @override
  void dispose() {
    _scrollCoordinator.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// 内容标识或布局输入发生变化时重置预览状态；仅追加时保留滚动位置。
  void _resetPreviewState() {
    _CollapsedBodyScrollOffsetCache.reset(_scrollStateKey);
    _contentHeight = null;
    _atBottom = false;
    _userScrollingPreview = false;
    _lockedPreviewLength = null;
    _scrollCoordinator.cancelSettleTimer();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    _CollapsedBodyScrollOffsetCache.save(_scrollStateKey, pos.pixels);
    _scrollCoordinator.markUserScrolling();
    _applyAtBottom(pos);
  }

  void _setUserScrollingPreview(bool value) {
    if (_userScrollingPreview == value) return;
    setState(() => _userScrollingPreview = value);
  }

  void _restoreScrollOffset() {
    _restoreCollapsedBodyScrollOffset(
      state: this,
      controller: _scrollController,
      key: _scrollStateKey,
      onRestored: _syncAtBottom,
    );
  }

  void _syncAtBottom() {
    if (!mounted || !_scrollController.hasClients) return;
    _applyAtBottom(_scrollController.position);
  }

  void _applyAtBottom(ScrollPosition position) {
    final atBottom = _isCollapsedPreviewAtBottom(
      position,
      currentlyAtBottom: _atBottom,
    );
    if (atBottom != _atBottom) setState(() => _atBottom = atBottom);
  }

  void _handleContentSizeChanged(Size size) {
    if (!mounted) return;
    if (_scrollController.hasClients &&
        _scrollController.position.isScrollingNotifier.value) {
      _scrollCoordinator.markUserScrolling();
      return;
    }
    if (_userScrollingPreview) {
      _scrollCoordinator.armSettleTimer();
      return;
    }
    final nextHeight = size.height;
    final currentHeight = _contentHeight;
    final nextLockedLength =
        _lockedPreviewLength ??
        (nextHeight > _previewMaxHeight + 0.5 ? _previewDataLength : null);
    if (currentHeight != null &&
        (currentHeight - nextHeight).abs() < 0.5 &&
        nextLockedLength == _lockedPreviewLength) {
      return;
    }
    setState(() {
      _contentHeight = nextHeight;
      _lockedPreviewLength = nextLockedLength;
    });
  }

  /// 预览是否超出 [_previewMaxHeight]，用于决定渐隐与滚动能力。
  bool get _hasPreviewOverflow {
    final measuredHeight = _contentHeight;
    return measuredHeight != null && measuredHeight > _previewMaxHeight + 0.5;
  }

  /// 包裹预览子树的滚动外壳，统一渐隐与测高接线。
  Widget _buildPreviewFrame(
    BuildContext context,
    Color fadeColor,
    Widget child,
  ) {
    final hasOverflow = _hasPreviewOverflow;
    return _buildCollapsedPreviewScrollableFrame(
      context: context,
      maxHeight: _previewMaxHeight,
      hasOverflow: hasOverflow,
      showFade: hasOverflow && !_atBottom,
      controller: _scrollController,
      fadeColor: fadeColor,
      animateFade: !_userScrollingPreview,
      onSizeChanged: _handleContentSizeChanged,
      child: child,
    );
  }
}

class _PlainTextPreviewBody extends StatefulWidget {
  const _PlainTextPreviewBody({
    required this.data,
    required this.maxHeight,
    required this.textColor,
    required this.fadeColor,
    this.style,
    this.scrollStateKey,
  });

  final String data;
  final double maxHeight;
  final Color textColor;
  final Color fadeColor;
  final TextStyle? style;
  final String? scrollStateKey;

  @override
  State<_PlainTextPreviewBody> createState() => _PlainTextPreviewBodyState();
}

class _PlainTextPreviewBodyState extends State<_PlainTextPreviewBody>
    with _CollapsedPreviewBodyState<_PlainTextPreviewBody> {
  @override
  String get _previewSource => widget.data;

  @override
  double get _previewMaxHeight => widget.maxHeight;

  @override
  int get _previewCharCap => _plainTextCollapsedPreviewMaxChars;

  @override
  String get _scrollStateKey =>
      widget.scrollStateKey ?? _plainPreviewScrollKey(widget);

  @override
  void didUpdateWidget(covariant _PlainTextPreviewBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    final appendOnlyDataUpdate =
        widget.data.length >= oldWidget.data.length &&
        widget.data.startsWith(oldWidget.data);
    final layoutInputsChanged =
        oldWidget.maxHeight != widget.maxHeight ||
        oldWidget.style != widget.style ||
        oldWidget.textColor != widget.textColor;
    final scrollStateChanged =
        (oldWidget.scrollStateKey ?? _plainPreviewScrollKey(oldWidget)) !=
        _scrollStateKey;
    if (scrollStateChanged || layoutInputsChanged || !appendOnlyDataUpdate) {
      _resetPreviewState();
    } else if (oldWidget.data != widget.data && _atBottom) {
      _atBottom = false;
    }
    _restoreScrollOffset();
  }

  @override
  Widget build(BuildContext context) {
    final style =
        widget.style?.copyWith(color: widget.textColor) ??
        TextStyle(color: widget.textColor, height: 1.55);
    return _buildPreviewFrame(
      context,
      widget.fadeColor,
      SelectableText(_effectiveData, style: style),
    );
  }
}

/// 纯文本预览未显式给键时的默认滚动状态键。
String _plainPreviewScrollKey(_PlainTextPreviewBody widget) =>
    'plain-preview|${widget.maxHeight}|${widget.data.length}|'
    '${boundedTextFingerprint(widget.data)}';

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
    this.collapsedOverride,
    this.onCollapsedChanged,
    this.showCollapseToggle = true,
    this.animateSize = true,
    this.scrollStateKey,
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
  final bool? collapsedOverride;
  final ValueChanged<bool>? onCollapsedChanged;
  final bool showCollapseToggle;
  final bool animateSize;
  final String? scrollStateKey;

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
    final recollapsedByParent =
        oldWidget.collapsedOverride == false &&
        widget.collapsedOverride == true;
    if (recollapsedByParent) {
      _CollapsedBodyScrollOffsetCache.reset(_scrollStateKey);
    }
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
    return _messageShouldCollapse(
      value,
      charThreshold: widget.collapseCharThreshold,
      lineThreshold: widget.collapseLineThreshold,
    );
  }

  bool get _effectiveCollapsed => widget.collapsedOverride ?? _collapsed;

  String get _scrollStateKey =>
      widget.scrollStateKey ?? '${widget.parseKey}|message-collapsed-full';

  void _setCollapsed(bool value) {
    if (value) {
      _CollapsedBodyScrollOffsetCache.reset(_scrollStateKey);
    }
    if (widget.collapsedOverride != null) {
      widget.onCollapsedChanged?.call(value);
      return;
    }
    setState(() {
      _collapsed = value;
      _userToggled = true;
    });
    widget.onCollapsedChanged?.call(value);
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

    final collapsed = _effectiveCollapsed;
    final previewBody = KeyedSubtree(
      key: const ValueKey<String>('message-markdown-preview'),
      child: _MarkdownPreviewBody(
        data: data,
        maxHeight: widget.previewMaxHeight,
        selectable: widget.selectable,
        styleSheet: widget.styleSheet,
        builders: widget.builders,
        inlineSyntaxes: widget.inlineSyntaxes,
        pathRoots: widget.pathRoots,
        parseKey: '${widget.parseKey}|message-preview',
        scrollStateKey: _scrollStateKey,
        fadeColor: widget.fadeColor,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showCollapseToggle) ...[
          _MessageCollapseToggleCapsule(
            collapsed: collapsed,
            characterCount: data.length,
            color: Theme.of(context).colorScheme.primary,
            onTap: () {
              _BubbleHtmlInteractiveScope.maybeOf(
                context,
              )?.markInteractiveTap();
              _setCollapsed(!collapsed);
            },
          ),
          kOpenHandGap8,
        ],
        _collapsibleMessageBodyMotion(
          context: context,
          collapsed: collapsed,
          animate: widget.animateSize,
          child: collapsed
              ? previewBody
              : KeyedSubtree(
                  key: const ValueKey<String>('message-markdown-expanded'),
                  child: _SafeMarkdownBody(
                    data: data,
                    selectable: widget.selectable,
                    builders: widget.builders,
                    styleSheet: widget.styleSheet,
                    inlineSyntaxes: widget.inlineSyntaxes,
                    pathRoots: widget.pathRoots,
                    parseKey: widget.parseKey,
                    deferredPlaceholder: previewBody,
                  ),
                ),
        ),
      ],
    );
  }
}

Widget _collapsibleMessageBodyMotion({
  required BuildContext context,
  required bool collapsed,
  bool animate = true,
  required Widget child,
}) {
  return maybeAnimatedSize(
    duration: animate
        ? cardMotionDurationFor(context, expanding: !collapsed)
        : Duration.zero,
    curve: kCardMotionCurve,
    alignment: Alignment.topLeft,
    child: ClipRect(child: child),
  );
}

bool _consumeNestedMessageScrollNotification(ScrollNotification _) {
  return true;
}

bool _messageShouldCollapse(
  String value, {
  required int charThreshold,
  required int lineThreshold,
}) {
  if (value.length > charThreshold) {
    return true;
  }
  var lineCount = 1;
  for (final unit in value.codeUnits) {
    if (unit == 0x0A) {
      lineCount += 1;
      if (lineCount > lineThreshold) {
        return true;
      }
    }
  }
  return false;
}

class _MessageCollapseToggleCapsule extends StatefulWidget {
  const _MessageCollapseToggleCapsule({
    required this.collapsed,
    required this.characterCount,
    required this.color,
    required this.onTap,
  });

  final bool collapsed;
  final int characterCount;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_MessageCollapseToggleCapsule> createState() =>
      _MessageCollapseToggleCapsuleState();
}

class _MessageCollapseToggleCapsuleState
    extends State<_MessageCollapseToggleCapsule> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() {
      _pressed = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveColor = widget.color.withValues(alpha: 0.88);
    final label = widget.collapsed
        ? openHandLocalizedText(context, zh: '展开完整内容', en: 'Show Full Content')
        : openHandLocalizedText(context, zh: '收起长内容', en: 'Collapse Content');
    final unitText = _homeMessageConCharsLabel(context);
    final textStyle =
        theme.textTheme.labelLarge?.copyWith(
          color: effectiveColor,
          fontWeight: FontWeight.w700,
        ) ??
        TextStyle(color: effectiveColor, fontWeight: FontWeight.w700);
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.subject_rounded, size: 18, color: effectiveColor),
        kOpenHandHGap8,
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle,
          ),
        ),
        Text(' · ', style: textStyle),
        RollingText(text: '${widget.characterCount}', style: textStyle),
        Text(unitText, style: textStyle),
        kOpenHandHGap6,
        AnimatedRotation(
          turns: widget.collapsed ? 0 : 0.5,
          duration: cardMotionDurationFor(
            context,
            expanding: !widget.collapsed,
          ),
          curve: kCardMotionCurve,
          child: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: widget.color.withValues(alpha: 0.78),
            size: 18,
          ),
        ),
      ],
    );
    final capsule = AnimatedScale(
      scale: _pressed ? 0.97 : 1,
      duration: cardMotionDurationFor(context, expanding: !_pressed),
      curve: kCardMotionCurve,
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: kOpenHandContentMaxWidth360,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.06),
          borderRadius: kOpenHandPillBorderRadius,
          border: Border.all(color: widget.color.withValues(alpha: 0.12)),
        ),
        child: row,
      ),
    );
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: _setPressed,
          borderRadius: kOpenHandPillBorderRadius,
          overlayColor: WidgetStatePropertyAll<Color>(
            widget.color.withValues(alpha: 0.03),
          ),
          child: capsule,
        ),
      ),
    );
  }
}

class _MarkdownPreviewBody extends StatefulWidget {
  const _MarkdownPreviewBody({
    required this.data,
    required this.maxHeight,
    required this.selectable,
    required this.styleSheet,
    required this.builders,
    required this.inlineSyntaxes,
    required this.pathRoots,
    required this.parseKey,
    required this.fadeColor,
    this.scrollStateKey,
  });

  final String data;
  final double maxHeight;
  final bool selectable;
  final MarkdownStyleSheet styleSheet;
  final Map<String, MarkdownElementBuilder> builders;
  final List<md.InlineSyntax> inlineSyntaxes;
  final List<String> pathRoots;
  final String parseKey;
  final Color fadeColor;
  final String? scrollStateKey;

  @override
  State<_MarkdownPreviewBody> createState() => _MarkdownPreviewBodyState();
}

class _MarkdownPreviewBodyState extends State<_MarkdownPreviewBody>
    with _CollapsedPreviewBodyState<_MarkdownPreviewBody> {
  @override
  String get _previewSource => widget.data;

  @override
  double get _previewMaxHeight => widget.maxHeight;

  @override
  int get _previewCharCap => _markdownCollapsedPreviewMaxChars;

  @override
  String get _scrollStateKey => widget.scrollStateKey ?? widget.parseKey;

  @override
  void didUpdateWidget(covariant _MarkdownPreviewBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    final appendOnlyDataUpdate =
        widget.data.length >= oldWidget.data.length &&
        widget.data.startsWith(oldWidget.data);
    final scrollStateChanged =
        (oldWidget.scrollStateKey ?? oldWidget.parseKey) != _scrollStateKey;
    if (scrollStateChanged ||
        oldWidget.parseKey != widget.parseKey ||
        !appendOnlyDataUpdate) {
      _resetPreviewState();
    } else if (oldWidget.data != widget.data && _atBottom) {
      _atBottom = false;
    }
    _restoreScrollOffset();
  }

  @override
  Widget build(BuildContext context) {
    return _buildPreviewFrame(
      context,
      widget.fadeColor,
      _SafeMarkdownBody(
        data: _effectiveData,
        selectable: widget.selectable,
        builders: widget.builders,
        styleSheet: widget.styleSheet,
        inlineSyntaxes: widget.inlineSyntaxes,
        pathRoots: widget.pathRoots,
        parseKey: widget.parseKey,
      ),
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
  const _MessageMarkdownThemeData({
    required this.styleSheet,
    required this.inlineCodeBuilder,
  });

  factory _MessageMarkdownThemeData.fromMessageBubble({
    required ThemeData theme,
    required Color backgroundColor,
    required Color textColor,
    required bool useDarkCodeSurface,
  }) {
    // 进程级缓存。`MarkdownStyleSheet.fromTheme + copyWith` 创建
    // 数十个 TextStyle / BoxDecoration，60+ 长会话首次打开会重复触发
    // N 次。按 (theme palette + bubble bg + text color + dark surface)
    // 签名命中率极高（同 role/状态的 bubble 共享同一份 stylesheet），
    // 命中后跳过整个工厂方法的重建工作。
    final cacheKey = Object.hash(
      theme.brightness.index,
      theme.colorScheme.primary.toARGB32(),
      theme.colorScheme.primaryContainer.toARGB32(),
      theme.textTheme.bodyLarge?.fontSize,
      theme.textTheme.bodyMedium?.fontSize,
      backgroundColor.toARGB32(),
      textColor.toARGB32(),
      useDarkCodeSurface,
    );
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
    final tones = OpenHandMarkdownSurfaceTones.resolve(
      colorScheme: colorScheme,
      background: backgroundColor,
    );
    final bubbleIsDark = tones.isDark;
    final overlayBase = tones.overlayBase;
    final subtleSurface = tones.subtleSurface;
    final elevatedSurface = tones.elevatedSurface;
    final inlineCodeSurface = Color.alphaBlend(
      overlayBase.withValues(alpha: bubbleIsDark ? 0.12 : 0.055),
      backgroundColor,
    );
    final accentColor = tones.accent;
    final linkColor = tones.link;
    final borderColor =
        palette?.outlineSoft.withValues(alpha: bubbleIsDark ? 0.72 : 0.88) ??
        Color.alphaBlend(
          overlayBase.withValues(alpha: bubbleIsDark ? 0.18 : 0.12),
          backgroundColor,
        );
    final quoteSurface = Color.alphaBlend(
      accentColor.withValues(alpha: bubbleIsDark ? 0.16 : 0.07),
      elevatedSurface,
    );
    final secondaryTextColor = textColor.withValues(
      alpha: bubbleIsDark ? 0.92 : 0.88,
    );
    final bodyFontSize = theme.textTheme.bodyMedium?.fontSize ?? 14;
    final bodyStyle =
        theme.textTheme.bodyMedium?.copyWith(
          color: textColor,
          fontSize: bodyFontSize * 1.04,
          height: 1.5,
          letterSpacing: 0.02,
        ) ??
        TextStyle(color: textColor, fontSize: bodyFontSize, height: 1.5);
    final headingStyle = bodyStyle.copyWith(height: 1.24, letterSpacing: -0.22);
    final tableBodyStyle = bodyStyle.copyWith(
      fontSize: bodyFontSize * 0.95,
      height: 1.42,
    );
    final codeStyle =
        theme.textTheme.bodyMedium?.copyWith(
          color: textColor,
          fontFamily: kOpenHandMonospaceFontFamily,
          fontSize: bodyFontSize * 0.92,
          fontWeight: FontWeight.w500,
          height: 1.28,
        ) ??
        TextStyle(
          color: textColor,
          fontFamily: kOpenHandMonospaceFontFamily,
          fontSize: bodyFontSize * 0.92,
          fontWeight: FontWeight.w500,
          height: 1.28,
        );
    return _MessageMarkdownThemeData(
      inlineCodeBuilder: OpenHandMarkdownInlineCodeBuilder(
        textStyle: codeStyle,
        backgroundColor: inlineCodeSurface,
      ),
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        a: bodyStyle.copyWith(
          color: linkColor,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
          decorationColor: linkColor.withValues(alpha: 0.78),
        ),
        p: bodyStyle,
        pPadding: EdgeInsets.zero,
        code: codeStyle,
        h1: headingStyle.copyWith(
          fontSize: bodyFontSize * 1.46,
          fontWeight: FontWeight.w800,
        ),
        h1Padding: const EdgeInsets.only(top: 4, bottom: 2),
        h2: headingStyle.copyWith(
          fontSize: bodyFontSize * 1.28,
          fontWeight: FontWeight.w800,
        ),
        h2Padding: const EdgeInsets.only(top: 3, bottom: 1),
        h3: headingStyle.copyWith(
          fontSize: bodyFontSize * 1.15,
          fontWeight: FontWeight.w700,
        ),
        h3Padding: const EdgeInsets.only(top: 2),
        h4: headingStyle.copyWith(
          fontSize: bodyFontSize * 1.07,
          fontWeight: FontWeight.w700,
        ),
        h4Padding: const EdgeInsets.only(top: 1),
        h5: headingStyle.copyWith(fontWeight: FontWeight.w700),
        h6: headingStyle.copyWith(
          color: secondaryTextColor,
          fontWeight: FontWeight.w700,
        ),
        em: bodyStyle.copyWith(fontStyle: FontStyle.italic),
        strong: bodyStyle.copyWith(fontWeight: FontWeight.w700),
        del: bodyStyle.copyWith(decoration: TextDecoration.lineThrough),
        blockquote: bodyStyle.copyWith(color: secondaryTextColor),
        blockSpacing: 10,
        listIndent: 22,
        listBullet: bodyStyle.copyWith(
          color: secondaryTextColor,
          fontWeight: FontWeight.w700,
        ),
        listBulletPadding: const EdgeInsets.only(right: 7),
        tableHead: bodyStyle.copyWith(fontWeight: FontWeight.w700),
        tableBody: tableBodyStyle,
        tableBorder: TableBorder.all(
          color: borderColor,
          borderRadius: kOpenHandBorderRadius12,
        ),
        tablePadding: const EdgeInsets.symmetric(vertical: 2),
        tableCellsPadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        tableCellsDecoration: BoxDecoration(color: subtleSurface),
        tableHeadCellsPadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        tableHeadCellsDecoration: BoxDecoration(color: elevatedSurface),
        tableColumnWidth: const IntrinsicColumnWidth(),
        blockquotePadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 11,
        ),
        blockquoteDecoration: BoxDecoration(
          color: quoteSurface,
          borderRadius: kOpenHandBorderRadius12,
          border: Border(left: BorderSide(color: accentColor, width: 2.5)),
        ),
        // 代码面板自行裁剪圆角，外层仅约束边界，避免重复裁剪削薄四角边框。
        codeblockPadding: EdgeInsets.zero,
        codeblockDecoration: const BoxDecoration(),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: borderColor)),
        ),
      ),
    );
  }

  final MarkdownStyleSheet styleSheet;
  final OpenHandMarkdownInlineCodeBuilder inlineCodeBuilder;
}

/// [_MessageMarkdownThemeData] 的 LRU 缓存。容量 64 足以覆盖
/// 「亮/暗 × user/assistant/tool/reasoning × 选中/未选中」全部组合。
final LinkedHashMap<int, _MessageMarkdownThemeData> _markdownThemeDataCache =
    LinkedHashMap<int, _MessageMarkdownThemeData>();

class _SafeMarkdownBody extends StatefulWidget {
  const _SafeMarkdownBody({
    required this.data,
    required this.styleSheet,
    this.selectable = false,
    this.streaming = false,
    this.builders = const <String, MarkdownElementBuilder>{},
    this.inlineSyntaxes = const <md.InlineSyntax>[],
    this.pathRoots = const <String>[],
    this.parseKey = '',
    this.deferredPlaceholder,
  });

  final String data;
  final MarkdownStyleSheet styleSheet;
  final bool selectable;
  final bool streaming;
  final Map<String, MarkdownElementBuilder> builders;
  final List<md.InlineSyntax> inlineSyntaxes;
  final List<String> pathRoots;
  final String parseKey;
  final Widget? deferredPlaceholder;

  @override
  State<_SafeMarkdownBody> createState() => _SafeMarkdownBodyState();
}

// 大型 Markdown 冷解析先显示轻量占位，再按共享帧预算构建富文本树。
const int _markdownDeferredParseThresholdChars = 2 * kBytesPerKiB;

// 流式追加时更早进入 deferred 路径，并把富文本树重建合并到稳定节奏；
// 小公式 / 列表仍能尽快渲染，长回答不会按 token 频率反复解析整棵树。
const int _markdownStreamingDeferredParseThresholdChars = 160;
const int _markdownStreamingInitialSyncParseThresholdChars = 8 * kBytesPerKiB;
const int _markdownStreamingParseMinIntervalMs = 96;
const int _markdownStreamingPlaceholderMaxLines = 6;
const int _markdownDeferredPlaceholderMaxLines = 24;
const int _markdownPlaceholderCharsPerLine = 72;
const double _markdownStreamingPlaceholderMinHeight = 28;
const double _markdownStreamingPlaceholderMaxHeight = 132;
const double _markdownDeferredPlaceholderMinHeight = 44;
const double _markdownDeferredPlaceholderMaxHeight = 520;
const double _markdownPlaceholderMaxWidth = 560;

/// 进程级 AST LRU 缓存，同时限制条目数和源文本总量，避免长会话挤占内存。
class _MarkdownAstCache {
  _MarkdownAstCache();

  static const int _maxEntries = 512;
  static const int _maxSourceChars = 4 * kBytesPerMiB;
  final LinkedHashMap<int, _MarkdownAstCacheEntry> _entries =
      LinkedHashMap<int, _MarkdownAstCacheEntry>();
  int _sourceChars = 0;

  List<md.Node>? get(int key) {
    final entry = _entries.remove(key);
    if (entry != null) {
      _entries[key] = entry;
    }
    return entry?.nodes;
  }

  void put(int key, List<md.Node> nodes, int sourceChars) {
    final previous = _entries.remove(key);
    if (previous != null) {
      _sourceChars -= previous.sourceChars;
    }
    if (sourceChars > _maxSourceChars) {
      return;
    }
    _entries[key] = _MarkdownAstCacheEntry(nodes, sourceChars);
    _sourceChars += sourceChars;
    while (_entries.length > _maxEntries || _sourceChars > _maxSourceChars) {
      final removed = _entries.remove(_entries.keys.first);
      if (removed != null) {
        _sourceChars -= removed.sourceChars;
      }
    }
  }
}

class _MarkdownAstCacheEntry {
  const _MarkdownAstCacheEntry(this.nodes, this.sourceChars);

  final List<md.Node> nodes;
  final int sourceChars;
}

final _MarkdownAstCache _markdownAstCache = _MarkdownAstCache();
final Set<int> _pendingMarkdownWarmups = <int>{};

int _markdownAstCacheKeyForInputs({
  required String normalizedSource,
  required String parseKey,
  required List<md.InlineSyntax> inlineSyntaxes,
}) {
  // 用 boundedTextFingerprint 代替完整字符串 hash，避免对长消息
  // 做 O(n) 遍历。fingerprint 只取首尾各 128 字符，碰撞率足够低。
  return Object.hash(
    boundedTextFingerprint(normalizedSource),
    parseKey,
    openHandMarkdownMathSyntaxVersion,
    inlineSyntaxes.length,
    Object.hashAll(inlineSyntaxes.map((syn) => syn.runtimeType)),
  );
}

int _markdownAstCacheKeyFor(String normalizedSource, _SafeMarkdownBody widget) {
  return _markdownAstCacheKeyForInputs(
    normalizedSource: normalizedSource,
    parseKey: widget.parseKey,
    inlineSyntaxes: withOpenHandMarkdownMathInlineSyntaxes(
      widget.inlineSyntaxes,
    ),
  );
}

final RegExp _markdownSetextEscapePattern = RegExp(
  r'(^|\n)(\s*)(=+|\^+)(?=\n|$)',
);
final RegExp _markdownInlineFencedBlockLinePattern = RegExp(
  r'^( {0,3})(`{3,}|~{3,})([^\n]*)$',
);
final RegExp _markdownFenceInfoTokenPattern = RegExp(
  r'^([A-Za-z0-9_+#\.-]+)(?:\s+|$)',
);

/// Matches scaffolding lines that sometimes leak from models into the
/// visible markdown body, e.g. a bare `Tool: Bash`, `工具: Bash`,
/// `工具调用：xxx`, `[tool_call] ...`, or `function_calls: ...`.
///
/// These come from the model's own chain-of-thought / training data and
/// should be rendered by the structured tool-call bubble, not as plain text.
/// We strip them before markdown parsing to keep transcripts clean.
final RegExp _markdownToolScaffoldingLinePattern = RegExp(
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

/// sanitize 结果缓存。同一次解析周期内 `_parseMarkdownMaybeDeferred`（为算
/// AST cache key）与 `_parseMarkdownInner` 会各跑一次 sanitize，而 sanitize
/// 本身是数次全串扫描 + 两次 split，对长消息是实打实的毫秒级开销。缓存后
/// 每条消息只付一次，AST 缓存的收益也不再被「为查缓存先算一遍」抵消。
class _MarkdownSanitizeCache {
  static const int _maxEntries = 256;
  // 单条准入阈值必须远小于总预算，否则一条超大消息插入后会把整个缓存
  // （连同它自己）全部淘汰，命中率恒为 0，比不加缓存更差。
  static const int _maxEntryChars = 256 * kBytesPerKiB;
  static const int _maxTotalChars = 2 * kBytesPerMiB;

  final LinkedHashMap<String, String> _entries =
      LinkedHashMap<String, String>();
  int _chars = 0;

  String resolve(String source, String Function(String) compute) {
    final cached = _entries.remove(source);
    if (cached != null) {
      _entries[source] = cached;
      return cached;
    }
    final value = compute(source);
    if (source.length > _maxEntryChars) return value;
    _entries[source] = value;
    _chars += source.length + value.length;
    while (_entries.length > _maxEntries || _chars > _maxTotalChars) {
      final key = _entries.keys.first;
      final removed = _entries.remove(key);
      if (removed == null) break;
      _chars -= key.length + removed.length;
    }
    return value;
  }
}

final _MarkdownSanitizeCache _markdownSanitizeCache = _MarkdownSanitizeCache();

String _sanitizeMarkdownSource(String source) {
  return _markdownSanitizeCache.resolve(
    source,
    _computeSanitizedMarkdownSource,
  );
}

String _computeSanitizedMarkdownSource(String source) {
  final normalized = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final normalizedFences = _normalizeInlineFencedCodeBlocks(normalized);
  final stripped = _stripToolScaffoldingFromMarkdown(normalizedFences);
  return _closeUnterminatedFencedCodeBlock(stripped).replaceAllMapped(
    _markdownSetextEscapePattern,
    (match) => '${match[1]}${match[2]}\\${match[3]}',
  );
}

String _normalizeInlineFencedCodeBlocks(String source) {
  if (source.isEmpty || !source.contains('```') && !source.contains('~~~')) {
    return source;
  }
  final lines = source.split('\n');
  var changed = false;
  final normalizedLines = <String>[];
  for (final line in lines) {
    final match = _markdownInlineFencedBlockLinePattern.firstMatch(line);
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
    final infoMatch = _markdownFenceInfoTokenPattern.firstMatch(inlineSegment);
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

String _stripToolScaffoldingFromMarkdown(String source) {
  if (!_markdownToolScaffoldingLinePattern.hasMatch(source)) {
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
    if (_markdownToolScaffoldingLinePattern.hasMatch(line)) {
      continue;
    }
    buffer.write(line);
    if (i != lines.length - 1) buffer.write('\n');
  }
  return buffer.toString();
}

void _warmMarkdownAst({
  required String data,
  required String parseKey,
  required List<md.InlineSyntax> inlineSyntaxes,
  void Function(List<md.Node> astNodes)? onReady,
}) {
  if (data.length > _markdownPlainTextSkipThresholdChars ||
      _canRenderMarkdownAsPlainText(data)) {
    return;
  }
  final normalizedSource = _sanitizeMarkdownSource(data.isEmpty ? ' ' : data);
  final effectiveInlineSyntaxes = withOpenHandMarkdownMathInlineSyntaxes(
    inlineSyntaxes,
  );
  final astCacheKey = _markdownAstCacheKeyForInputs(
    normalizedSource: normalizedSource,
    parseKey: parseKey,
    inlineSyntaxes: effectiveInlineSyntaxes,
  );
  final cachedAst = _markdownAstCache.get(astCacheKey);
  if (cachedAst != null) {
    onReady?.call(cachedAst);
    return;
  }
  if (!_pendingMarkdownWarmups.add(astCacheKey)) {
    return;
  }
  void warmup() {
    try {
      final astNodes = parseOpenHandMarkdown(
        normalizedSource,
        inlineSyntaxes: effectiveInlineSyntaxes,
      );
      _markdownAstCache.put(astCacheKey, astNodes, normalizedSource.length);
      onReady?.call(astNodes);
    } finally {
      _pendingMarkdownWarmups.remove(astCacheKey);
    }
  }

  if (data.length > _markdownDeferredParseThresholdChars) {
    _markdownFrameScheduler.schedule(
      warmup,
      onDropped: () => _pendingMarkdownWarmups.remove(astCacheKey),
    );
    return;
  }
  warmup();
}

md.Element? _findMarkdownCodeElement(md.Element element) {
  for (final child in element.children ?? const <md.Node>[]) {
    if (child is md.Element && child.tag == 'code') {
      return child;
    }
  }
  return null;
}

void _warmHighlightedCodeBlocksFromMarkdownAst({
  required List<md.Node> nodes,
  required ThemeData theme,
  required Color textColor,
  required bool useDarkCodeSurface,
}) {
  for (final node in nodes) {
    if (node is! md.Element) {
      continue;
    }
    if (node.tag == 'pre') {
      final codeElement = _findMarkdownCodeElement(node);
      final rawCode = (codeElement?.textContent ?? node.textContent)
          .replaceFirst(_trailingNewlineCodeBlockPattern, '');
      final content = rawCode.isEmpty ? ' ' : rawCode;
      _warmHighlightedCodeSpan(
        content: content,
        theme: theme,
        baseColor: textColor,
        forceDarkSurface: useDarkCodeSurface,
        language: _extractCodeLanguage(codeElement),
      );
    }
    final children = node.children;
    if (children != null && children.isNotEmpty) {
      _warmHighlightedCodeBlocksFromMarkdownAst(
        nodes: children,
        theme: theme,
        textColor: textColor,
        useDarkCodeSurface: useDarkCodeSurface,
      );
    }
  }
}

void _warmMarkdownRenderPath({
  required String data,
  required String parseKey,
  required List<md.InlineSyntax> inlineSyntaxes,
  required ThemeData theme,
  required Color textColor,
  required bool useDarkCodeSurface,
}) {
  _warmMarkdownAst(
    data: data,
    parseKey: parseKey,
    inlineSyntaxes: inlineSyntaxes,
    onReady: (astNodes) {
      _warmHighlightedCodeBlocksFromMarkdownAst(
        nodes: astNodes,
        theme: theme,
        textColor: textColor,
        useDarkCodeSurface: useDarkCodeSurface,
      );
    },
  );
}

/// 全局帧节流的 markdown 解析调度器。
///
/// 在打开存量会话或快速切换会话时，多张消息卡片会在「同一帧」内同时
/// 调用 `addPostFrameCallback` 注册 deferred 解析，结果下一帧仍要在
/// 主线程串行跑 N 次 `_parseMarkdown()`，单帧时间常常突破 16ms 预算
/// 直接触发 ANR。本调度器把 N 个解析任务拆分到 ceil(N/_maxPerFrame)
/// 帧里执行，与 [_highlightFrameScheduler] 思路一致 —— 牺牲数十毫秒的
/// 完整渲染时间换取主线程持续 60 FPS 的丝滑感。
/// 每帧最多执行一个 markdown 解析任务。1 条足以让首屏视觉焦点（最新消息）
/// 第一时间从轻量占位升级到完整 markdown 渲染，剩余卡片按帧节奏陆续到位；
/// 1/帧 严格守住 16 ms 单帧预算，避免单条带多代码块的长消息触发 jank/ANR。
final _FrameTaskScheduler _markdownFrameScheduler = _FrameTaskScheduler(
  maxPerFrame: 1,
);

class _MarkdownStabilizingPlaceholder extends StatelessWidget {
  const _MarkdownStabilizingPlaceholder({
    required this.source,
    required this.style,
    required this.maxLines,
    required this.minHeight,
    required this.maxHeight,
  });

  final String source;
  final TextStyle? style;
  final int maxLines;
  final double minHeight;
  final double maxHeight;

  int get _lineCount {
    final trimmed = source.trimRight();
    if (trimmed.isEmpty) return 1;
    var explicitLines = 1;
    for (var i = 0; i < source.length; i += 1) {
      if (source.codeUnitAt(i) == 0x0A) {
        explicitLines += 1;
        if (explicitLines >= maxLines) {
          break;
        }
      }
    }
    final wrappedLines = (trimmed.length / _markdownPlaceholderCharsPerLine)
        .ceil();
    return math.max(explicitLines, wrappedLines).clamp(1, maxLines).toInt();
  }

  double get _lineHeight {
    final fontSize = style?.fontSize ?? 14;
    return fontSize * (style?.height ?? 1.48);
  }

  @override
  Widget build(BuildContext context) {
    final color =
        style?.color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    final lines = _lineCount;
    final lineHeight = _lineHeight;
    final barHeight = math.max(8.0, lineHeight * 0.42);
    final gap = math.min(8.0, lineHeight * 0.32);
    final height = (lines * barHeight + math.max(0, lines - 1) * gap)
        .clamp(minHeight, maxHeight)
        .toDouble();
    const widths = <double>[0.72, 0.9, 0.64, 0.82, 0.58, 0.46];
    final fillColor = color.withValues(alpha: 0.12);
    return Semantics(
      label: openHandLocalizedText(
        context,
        zh: '消息内容正在渲染',
        en: 'Rendering message content',
      ),
      child: ClipRRect(
        borderRadius: kOpenHandBorderRadius18,
        child: OpenHandSweepShimmer(
          sweepColor: color.withValues(alpha: 0.10),
          maskToChildAlpha: true,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth.isFinite
                  ? math.max(
                      1.0,
                      math.min(
                        constraints.maxWidth,
                        _markdownPlaceholderMaxWidth,
                      ),
                    )
                  : _markdownPlaceholderMaxWidth;
              return SizedBox(
                width: width,
                height: height,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List<Widget>.generate(lines, (index) {
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index == lines - 1 ? 0 : gap,
                      ),
                      child: Container(
                        width: width * widths[index % widths.length],
                        height: barHeight,
                        decoration: BoxDecoration(
                          color: fillColor,
                          borderRadius: kOpenHandPillBorderRadius,
                        ),
                      ),
                    );
                  }),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SafeMarkdownBodyState extends State<_SafeMarkdownBody>
    implements MarkdownBuilderDelegate {
  List<Widget>? _children;
  final List<GestureRecognizer> _recognizers = <GestureRecognizer>[];
  int? _lastThemeSignature;
  String? _lastData;
  bool? _lastSelectable;
  bool? _lastStreaming;
  String? _lastBuilderSignature;
  String? _lastParseKey;
  bool _deferredParseScheduled = false;
  Timer? _deferredParseThrottleTimer;
  final Stopwatch _markdownParseStopwatch = Stopwatch()..start();
  int _lastMarkdownParseAtMs = -1;
  TranscriptScrollActivity? _scrollActivity;
  bool _deferredParsePendingAfterScroll = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindScrollActivity();
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
        _lastStreaming != widget.streaming ||
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
    _cancelDeferredParseThrottle();
    _markdownParseStopwatch.stop();
    _scrollActivity?.removeListener(_handleScrollActivityChanged);
    _scrollActivity = null;
    _disposeRecognizers();
    super.dispose();
  }

  void _bindScrollActivity() {
    final activity = _maybeTranscriptScrollActivityOf(context);
    if (identical(activity, _scrollActivity)) {
      return;
    }
    _scrollActivity?.removeListener(_handleScrollActivityChanged);
    _scrollActivity = activity;
    activity?.addListener(_handleScrollActivityChanged);
  }

  void _handleScrollActivityChanged() {
    final activity = _scrollActivity;
    if (activity == null || !mounted || activity.value) {
      return;
    }
    if (!_deferredParsePendingAfterScroll ||
        _deferredParseScheduled ||
        _deferredParseThrottleTimer != null) {
      return;
    }
    _deferredParsePendingAfterScroll = false;
    _scheduleDeferredParse(throttle: widget.streaming && _children != null);
  }

  /// 大体量 Markdown 冷解析延迟到共享帧预算；缓存命中时同步复用 AST。
  /// 流式更新保留上一棵富文本树，避免内容在富文本和占位之间反复切换。
  void _parseMarkdownMaybeDeferred({required bool initial}) {
    final normalizedSource = _sanitizeMarkdownSource(
      widget.data.isEmpty ? ' ' : widget.data,
    );
    final astCacheKey = _markdownAstCacheKeyFor(normalizedSource, widget);
    final hasWarmAst =
        !widget.streaming && _markdownAstCache.get(astCacheKey) != null;
    final deferredThreshold = widget.streaming
        ? _markdownStreamingDeferredParseThresholdChars
        : _markdownDeferredParseThresholdChars;
    if (widget.data.length > deferredThreshold &&
        widget.data.length <= _markdownPlainTextSkipThresholdChars &&
        !_canRenderMarkdownAsPlainText(widget.data) &&
        !hasWarmAst) {
      // 仅首次挂载使用占位，后续更新保留上一帧富文本直到新解析完成。
      final hadChildren = _children != null;
      if (widget.streaming &&
          !hadChildren &&
          widget.data.length <=
              _markdownStreamingInitialSyncParseThresholdChars) {
        _deferredParsePendingAfterScroll = false;
        _cancelDeferredParseThrottle();
        _parseMarkdown();
        return;
      }
      if (initial || !hadChildren) {
        _renderDeferredPlaceholder(
          normalizedSource,
          streaming: widget.streaming,
        );
      }
      if (_scrollActivity?.value ?? false) {
        _deferredParsePendingAfterScroll = true;
      } else {
        _deferredParsePendingAfterScroll = false;
        _scheduleDeferredParse(throttle: widget.streaming && hadChildren);
      }
      return;
    }
    _deferredParsePendingAfterScroll = false;
    _cancelDeferredParseThrottle();
    _parseMarkdown();
  }

  void _cancelDeferredParseThrottle() {
    final timer = _deferredParseThrottleTimer;
    if (timer == null) {
      return;
    }
    timer.cancel();
    _deferredParseThrottleTimer = null;
  }

  void _scheduleDeferredParse({bool throttle = false}) {
    if (_deferredParseScheduled) {
      return;
    }
    if (!throttle) {
      _cancelDeferredParseThrottle();
    } else if (_deferredParseThrottleTimer != null) {
      return;
    } else {
      final nowMs = _markdownParseStopwatch.elapsedMilliseconds;
      final elapsedMs = _lastMarkdownParseAtMs < 0
          ? _markdownStreamingParseMinIntervalMs
          : nowMs - _lastMarkdownParseAtMs;
      final remainingMs = _markdownStreamingParseMinIntervalMs - elapsedMs;
      if (remainingMs > 0) {
        _deferredParseThrottleTimer = startSafeTimer(
          Duration(milliseconds: remainingMs),
          () {
            _deferredParseThrottleTimer = null;
            if (!mounted) {
              return;
            }
            _scheduleDeferredParse();
          },
        );
        return;
      }
    }
    _deferredParseScheduled = true;
    _markdownFrameScheduler.schedule(
      () {
        if (!mounted) {
          _deferredParseScheduled = false;
          return;
        }
        if (_scrollActivity?.value ?? false) {
          _deferredParseScheduled = false;
          _deferredParsePendingAfterScroll = true;
          return;
        }
        _deferredParseScheduled = false;
        _deferredParsePendingAfterScroll = false;
        setState(_parseMarkdown);
      },
      priority: true,
      isValid: () => mounted,
      onDropped: () {
        _deferredParseScheduled = false;
        _deferredParsePendingAfterScroll = false;
      },
    );
  }

  void _renderDeferredPlaceholder(
    String normalizedSource, {
    required bool streaming,
  }) {
    final deferredPlaceholder = widget.deferredPlaceholder;
    if (!streaming && deferredPlaceholder != null) {
      _disposeRecognizers();
      _children = <Widget>[deferredPlaceholder];
      return;
    }
    final effectiveStyleSheet = MarkdownStyleSheet.fromTheme(
      Theme.of(context),
    ).merge(widget.styleSheet);
    _disposeRecognizers();
    if (streaming) {
      _children = <Widget>[
        _MarkdownStabilizingPlaceholder(
          source: normalizedSource,
          style: effectiveStyleSheet.p,
          maxLines: _markdownStreamingPlaceholderMaxLines,
          minHeight: _markdownStreamingPlaceholderMinHeight,
          maxHeight: _markdownStreamingPlaceholderMaxHeight,
        ),
      ];
      return;
    }
    _children = <Widget>[
      _MarkdownStabilizingPlaceholder(
        source: normalizedSource,
        style: effectiveStyleSheet.p,
        maxLines: _markdownDeferredPlaceholderMaxLines,
        minHeight: _markdownDeferredPlaceholderMinHeight,
        maxHeight: _markdownDeferredPlaceholderMaxHeight,
      ),
    ];
  }

  void _parseMarkdown() {
    if (kDebugMode) {
      developer.Timeline.startSync(
        'openhand.markdown.parse',
        arguments: <String, Object?>{'chars': widget.data.length},
      );
      try {
        _parseMarkdownInner();
      } finally {
        _lastMarkdownParseAtMs = _markdownParseStopwatch.elapsedMilliseconds;
        developer.Timeline.finishSync();
      }
      return;
    }
    _parseMarkdownInner();
    _lastMarkdownParseAtMs = _markdownParseStopwatch.elapsedMilliseconds;
  }

  /// 解析入口：负责手势识别器的所有权交接。
  ///
  /// 上一帧的识别器仍被当前 widget 树引用，只能在新一轮 children 真正提交
  /// 之后再销毁；流式解析失败保留旧树时，反过来要丢弃本轮登记的半成品并把
  /// 旧识别器交还——否则旧树里全是已 dispose 的识别器，点击行内链接/文件
  /// 路径立刻触发 “used after being disposed”。
  void _parseMarkdownInner() {
    final previousRecognizers = _detachRecognizers();
    if (_rebuildMarkdownChildren()) {
      _disposeRecognizers();
      _recognizers.addAll(previousRecognizers);
      return;
    }
    _disposeAllRecognizers(previousRecognizers);
  }

  /// 重建 [_children]；返回 true 表示沿用上一帧的 children（流式解析失败兜底）。
  bool _rebuildMarkdownChildren() {
    final effectiveStyleSheet = MarkdownStyleSheet.fromTheme(
      Theme.of(context),
    ).merge(widget.styleSheet);
    final normalizedSource = _sanitizeMarkdownSource(
      widget.data.isEmpty ? ' ' : widget.data,
    );
    _lastThemeSignature = _computeThemeSignature();
    _lastData = widget.data;
    _lastSelectable = widget.selectable;
    _lastStreaming = widget.streaming;
    _lastBuilderSignature = _builderSignature();
    _lastParseKey = widget.parseKey;
    if (_canRenderMarkdownAsPlainText(widget.data)) {
      _children = <Widget>[
        widget.selectable
            ? SelectableText(normalizedSource, style: effectiveStyleSheet.p)
            : Text(normalizedSource, style: effectiveStyleSheet.p),
      ];
      return false;
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
      return false;
    }
    try {
      // 先查 AST 缓存。命中则直接复用，跳过昂贵的
      // `md.Document.parseLines` + `_sanitizeMarkdownAst`。MarkdownBuilder
      // 的 widget 构造仍按当前主题样式 fresh 跑一次，避免主题切换时
      // 残留旧色。
      final astCacheKey = _markdownAstCacheKeyFor(normalizedSource, widget);
      final shouldCacheAst = !widget.streaming;
      final cachedAst = shouldCacheAst
          ? _markdownAstCache.get(astCacheKey)
          : null;
      final List<md.Node> astNodes;
      if (cachedAst != null) {
        astNodes = cachedAst;
      } else {
        astNodes = parseOpenHandMarkdown(
          normalizedSource,
          inlineSyntaxes: withOpenHandMarkdownMathInlineSyntaxes(
            widget.inlineSyntaxes,
          ),
        );
        if (shouldCacheAst) {
          _markdownAstCache.put(astCacheKey, astNodes, normalizedSource.length);
        }
      }
      _children = buildOpenHandMarkdownWidgets(
        nodes: astNodes,
        delegate: this,
        selectable: widget.selectable,
        styleSheet: effectiveStyleSheet,
        imageBuilder: _buildMarkdownImage,
        builders: widget.builders,
      );
    } catch (_) {
      if (widget.streaming) {
        if (_children != null && _children!.isNotEmpty) {
          return true;
        }
        _children = <Widget>[
          _MarkdownStabilizingPlaceholder(
            source: normalizedSource,
            style: effectiveStyleSheet.p,
            maxLines: _markdownStreamingPlaceholderMaxLines,
            minHeight: _markdownStreamingPlaceholderMinHeight,
            maxHeight: _markdownStreamingPlaceholderMaxHeight,
          ),
        ];
        return false;
      }
      _children = <Widget>[
        widget.selectable
            ? SelectableText(widget.data, style: effectiveStyleSheet.p)
            : Text(widget.data, style: effectiveStyleSheet.p),
      ];
    }
    return false;
  }

  int _computeThemeSignature() {
    final theme = Theme.of(context);
    return Object.hash(
      theme.brightness,
      theme.colorScheme.surface.toARGB32(),
      theme.colorScheme.onSurface.toARGB32(),
      theme.colorScheme.primary.toARGB32(),
      widget.styleSheet.hashCode,
      widget.styleSheet.p?.color?.toARGB32(),
      widget.styleSheet.code?.color?.toARGB32(),
    );
  }

  String _builderSignature() {
    final keys = widget.builders.keys.toList(growable: false)..sort();
    return '$openHandMarkdownMathSyntaxVersion|${keys.join('|')}';
  }

  /// 摘走当前已登记的识别器并交出所有权，调用方负责销毁。
  List<GestureRecognizer> _detachRecognizers() {
    if (_recognizers.isEmpty) {
      return const <GestureRecognizer>[];
    }
    final detached = List<GestureRecognizer>.from(_recognizers);
    _recognizers.clear();
    return detached;
  }

  static void _disposeAllRecognizers(List<GestureRecognizer> recognizers) {
    for (final recognizer in recognizers) {
      recognizer.dispose();
    }
  }

  void _disposeRecognizers() => _disposeAllRecognizers(_detachRecognizers());

  Widget _buildMarkdownImage(Uri uri, String? title, String? alt) {
    final label = (alt ?? title ?? uri.toString()).trim();
    final resolvedFilePath = _resolveMarkdownImageFilePath(uri);
    if (resolvedFilePath != null) {
      final previewTitle = label.isEmpty ? p.basename(resolvedFilePath) : label;
      return _wrapMarkdownImageTap(
        semanticsLabel: previewTitle,
        onTap: () =>
            unawaited(_openMarkdownImageFile(resolvedFilePath, previewTitle)),
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
      final cachedPath = MediaCacheService.instance.cachedPathForUrl(
        urlString,
        kind: MediaCacheKind.image,
      );
      if (cachedPath != null) {
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
              errorBuilder: (_, _, _) {
                MediaCacheService.instance.invalidate(
                  urlString,
                  kind: MediaCacheKind.image,
                );
                return Image.network(
                  urlString,
                  fit: BoxFit.contain,
                  cacheWidth: 1280,
                  frameBuilder: (context, child, frame, loadedSynchronously) {
                    if (frame != null) {
                      MediaCacheService.instance.cacheInBackground(
                        urlString,
                        kind: MediaCacheKind.image,
                      );
                    }
                    return _fadeInImageFrameBuilder(
                      context,
                      child,
                      frame,
                      loadedSynchronously,
                    );
                  },
                  errorBuilder: (_, _, _) =>
                      _brokenImagePlaceholder(context, previewTitle),
                );
              },
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
                MediaCacheService.instance.cacheInBackground(
                  urlString,
                  kind: MediaCacheKind.image,
                );
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

  Future<void> _openMarkdownImageFile(String path, String title) async {
    if (!await isRegularFilePath(path)) {
      if (!mounted) return;
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '图片文件不存在或已被移动。',
          en: 'Image file not found or has been moved.',
        ),
      );
      return;
    }
    if (!mounted) return;
    showAnimatedDialog<void>(
      context: context,
      builder: (ctx) => _ImagePreviewDialog.file(filePath: path, title: title),
    );
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
      return decodeUriFullOrOriginal(uri.path);
    }
    if (uri.scheme.isEmpty) {
      final href = _decodeMarkdownImageHref(uri);
      final resolved = resolveMarkdownMessageLinkPath(href, widget.pathRoots);
      if (resolved != null && !resolved.isDirectory) {
        return resolved.resolvedPath;
      }
      return firstMessagePathCandidate(href, widget.pathRoots);
    }
    return null;
  }

  String _decodeMarkdownImageHref(Uri uri) {
    return decodeUriFullOrOriginal(uri.toString());
  }

  Widget _buildMarkdownImageFrame(BuildContext context, Widget image) {
    return ClipRRect(
      borderRadius: kOpenHandBorderRadius8,
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
    final revealDuration = openHandMotionDuration(
      context,
      _kImageFirstFrameRevealDuration,
    );
    if (revealDuration == Duration.zero) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: revealDuration,
      curve: kOpenHandEntranceCurve,
      builder: (context, value, child) {
        final t = value.clamp(0.0, 1.0);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 8),
            child: Transform.scale(
              alignment: Alignment.centerLeft,
              scale: 0.97 + 0.03 * value,
              child: child,
            ),
          ),
        );
      },
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
          kOpenHandHGap6,
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
    recognizer.onTap = () {
      _BubbleHtmlInteractiveScope.maybeOf(context)?.markInteractiveTap();
      unawaited(_openMarkdownLink(href));
    };
    return recognizer;
  }

  Future<void> _openMarkdownLink(String? href) async {
    final normalizedHref = (href ?? '').trim();
    if (normalizedHref.isEmpty) return;
    final externalUri = parseSupportedMessageLinkUri(normalizedHref);
    if (externalUri != null && externalUri.scheme != 'file') {
      if (mounted) await _openMessageLinkUri(context, externalUri);
      return;
    }
    var pathText = normalizedHref;
    if (normalizedHref.startsWith('file://')) {
      try {
        pathText = Uri.parse(normalizedHref).toFilePath();
      } catch (_) {
        pathText = normalizedHref;
      }
    }
    final resolvedPath = await resolveExistingMessagePathAsync(
      pathText,
      widget.pathRoots,
    );
    if (!mounted) return;
    if (resolvedPath != null) {
      await _openResolvedMessagePath(context, resolvedPath);
      return;
    }
    if (externalUri != null && mounted) {
      await _openMessageLinkUri(context, externalUri);
    }
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
    // 通过统一选择容器协调 Markdown 内多个可选节点，支持跨段落选择。
    return SelectionArea(child: _MarkdownSelectionContainer(child: body));
  }
}

/// 维持 markdown 树内多个 `SelectableText.rich` 节点的统一选择 registrar。
///
/// Flutter 内部的多选代理包含滚动虚拟化等复杂逻辑。Markdown 内容在流式
/// 更新时不需要这些能力，这里专门写一个聚焦「选择区域派发」的精简版：
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
  bool _orderDirty = false;
  bool _updateScheduled = false;
  bool _pendingNotify = false;
  int _dispatchDepth = 0;
  final Set<Selectable> _pendingAdds = <Selectable>{};
  final Set<Selectable> _pendingRemovals = <Selectable>{};

  // `MarkdownBuilder` 会为每个段落/列表项/表格 cell/代码块各建一个
  // `SelectableText.rich`，一条长消息挂载时是几十到几百次 `add`。若每次
  // add 都同步排序 + 重算 geometry，总代价是 O(N² log N) 次渲染树遍历
  // (比较器里的 `getTransformTo(null)` 要沿祖先链累乘矩阵)，长会话直接卡死。
  // 这里与 Flutter 自身的 `MultiSelectableSelectionContainerDelegate` 一致：
  // 只置脏并把排序与 geometry 合并到帧末/微任务里跑一次。
  @override
  void add(Selectable selectable) {
    if (_disposed) return;
    if (_dispatchDepth > 0) {
      _pendingRemovals.remove(selectable);
      _pendingAdds.add(selectable);
      return;
    }
    if (_selectables.contains(selectable)) return;
    _selectables.add(selectable);
    selectable.addListener(_onSelectableChanged);
    _scheduleSelectableUpdate();
  }

  @override
  void remove(Selectable selectable) {
    if (_disposed) return;
    if (_dispatchDepth > 0) {
      if (_pendingAdds.remove(selectable)) return;
      _pendingRemovals.add(selectable);
      return;
    }
    selectable.removeListener(_onSelectableChanged);
    _selectables.remove(selectable);
    if (_anchorStart == selectable) _anchorStart = null;
    if (_anchorEnd == selectable) _anchorEnd = null;
    // 拆除阶段不通知：markdown 树重建时的成批 remove 不应把用户当前选区
    // 的可视状态冲掉。
    _scheduleSelectableUpdate(notify: false);
  }

  void _applyPendingMutations() {
    if (_pendingRemovals.isEmpty && _pendingAdds.isEmpty) return;
    for (final selectable in _pendingRemovals) {
      selectable.removeListener(_onSelectableChanged);
      _selectables.remove(selectable);
      if (_anchorStart == selectable) _anchorStart = null;
      if (_anchorEnd == selectable) _anchorEnd = null;
    }
    _pendingRemovals.clear();
    for (final selectable in _pendingAdds) {
      if (_selectables.contains(selectable)) continue;
      _selectables.add(selectable);
      selectable.addListener(_onSelectableChanged);
    }
    _pendingAdds.clear();
    _scheduleSelectableUpdate(notify: false);
  }

  // 选择事件必须同步刷新 geometry：外层 SelectableRegion 在派发完事件后会
  // 立刻读 value 来决定是否显示选择手柄与工具条，推迟就会「长按选词没反应」。
  // 需要合并的只是挂载期成批的 add/remove。
  void _onSelectableChanged() {
    if (_disposed) return;
    _refreshGeometry();
  }

  void _scheduleSelectableUpdate({bool notify = true}) {
    if (_disposed) return;
    _orderDirty = true;
    _pendingNotify = _pendingNotify || notify;
    if (_updateScheduled) return;
    _updateScheduled = true;
    void flush([Duration? _]) {
      _updateScheduled = false;
      final shouldNotify = _pendingNotify;
      _pendingNotify = false;
      if (_disposed) return;
      _refreshGeometry(notify: shouldNotify);
    }

    // build/layout/paint 阶段内不能立刻 notifyListeners，推到本帧帧末；
    // 其余阶段用微任务，保证同一手势内的多次变更仍在本帧生效。
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback(flush);
    } else {
      scheduleMicrotask(flush);
    }
  }

  /// 惰性排序：所有依赖文档顺序的读取路径先调用它。
  ///
  /// 注意 `_refreshGeometry` 只在没有 flush 在途时才排序——挂载期 selectable
  /// 每次布局通知都会走到那里，若无条件排序就会退化回「每 add 一次排一次」。
  /// 顺序真正被消费的路径（事件派发 / 取选中内容 / 手柄定位）一律无条件调用。
  void _ensureSorted() {
    if (!_orderDirty) return;
    if (_selectables.length < 2) {
      _orderDirty = false;
      return;
    }
    // 排序键一次算好。放在比较器里会让每次比较都重新走一遍祖先链变换，
    // N log N 次树遍历是这个类此前最大的单点开销。
    final origins = Map<Selectable, Offset?>.identity();
    var resolved = 0;
    for (final selectable in _selectables) {
      final origin = _firstGlobalOriginOf(selectable);
      if (origin != null) resolved += 1;
      origins[selectable] = origin;
    }
    _orderDirty = false;
    // 可定位节点不足两个时无从排序：比较器会退化成「全部相等」，而 List.sort
    // 不稳定，反而会把本来正确的顺序打乱。此时直接沿用注册顺序——
    // MarkdownBuilder 本就按文档顺序构建，这是比乱序更好的兜底。
    if (resolved < 2) return;
    _selectables.sort((a, b) {
      final originA = origins[a];
      final originB = origins[b];
      if (originA == null || originB == null) return 0;
      final dy = originA.dy - originB.dy;
      if (dy.abs() > 0.5) return dy < 0 ? -1 : 1;
      return originA.dx.compareTo(originB.dx);
    });
  }

  Offset? _firstGlobalOriginOf(Selectable selectable) {
    try {
      if (selectable.boundingBoxes.isEmpty) return null;
      return MatrixUtils.transformRect(
        selectable.getTransformTo(null),
        selectable.boundingBoxes.first,
      ).topLeft;
    } catch (_) {
      return null;
    }
  }

  int _indexOf(Selectable selectable) {
    _ensureSorted();
    return _selectables.indexOf(selectable);
  }

  Selectable? _selectableAt(Offset globalPosition) {
    _ensureSorted();
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
    if (!_updateScheduled) _ensureSorted();
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
      Matrix4? transform;
      try {
        transform = getTransformFrom(selectable);
      } on Object {
        // 节点正在卸载时可能暂时没有可用的渲染对象，保留状态并等待下一次
        // geometry 通知，避免在选择回调中读取失活节点。
      }
      if (transform == null) continue;
      final start = g.startSelectionPoint;
      if (start != null) {
        final position = MatrixUtils.transformPoint(
          transform,
          start.localPosition,
        );
        if (position.isFinite) {
          startPoint ??= SelectionPoint(
            localPosition: position,
            lineHeight: start.lineHeight,
            handleType: start.handleType,
          );
        }
      }
      final end = g.endSelectionPoint;
      if (end != null) {
        final position = MatrixUtils.transformPoint(
          transform,
          end.localPosition,
        );
        if (position.isFinite) {
          endPoint = SelectionPoint(
            localPosition: position,
            lineHeight: end.lineHeight,
            handleType: end.handleType,
          );
        }
      }
      for (final rect in g.selectionRects) {
        final transformed = MatrixUtils.transformRect(transform, rect);
        if (transformed.isFinite && !transformed.isEmpty) {
          rects.add(transformed);
        }
      }
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
    // 严格按顺序清理，避免 Selectable 的回调
    // 在我们已经 dispose 之后才抵达 _onSelectableChanged。
    _disposed = true;
    for (final selectable in _selectables.toList(growable: false)) {
      selectable.removeListener(_onSelectableChanged);
    }
    _selectables.clear();
    _pendingAdds.clear();
    _pendingRemovals.clear();
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
    final handleTargets = _resolveHandleTargets();
    for (final selectable in _selectables) {
      selectable.pushHandleLayers(
        selectable == handleTargets.$1 ? startHandle : null,
        selectable == handleTargets.$2 ? endHandle : null,
      );
    }
  }

  (Selectable?, Selectable?) _resolveHandleTargets() {
    _ensureSorted();
    Selectable? startSelectable;
    Selectable? endSelectable;
    for (final selectable in _selectables) {
      final geometry = selectable.value;
      if (geometry.hasContent &&
          (geometry.startSelectionPoint != null ||
              geometry.endSelectionPoint != null)) {
        startSelectable ??= selectable;
        endSelectable = selectable;
      }
    }
    return (startSelectable, endSelectable);
  }

  @override
  SelectedContent? getSelectedContent() {
    _ensureSorted();
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
    _ensureSorted();
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
    if (_disposed) return SelectionResult.none;
    _dispatchDepth += 1;
    try {
      return _dispatchSelectionEvent(event);
    } finally {
      _dispatchDepth -= 1;
      if (_dispatchDepth == 0 && !_disposed) _applyPendingMutations();
    }
  }

  SelectionResult _dispatchSelectionEvent(SelectionEvent event) {
    _ensureSorted();
    if (_selectables.isEmpty) return SelectionResult.none;
    switch (event.type) {
      case SelectionEventType.startEdgeUpdate:
        final typed = event as SelectionEdgeUpdateEvent;
        final target = _selectableAt(typed.globalPosition);
        // 工具栏、内边距等非文本区域没有可选择节点，点击时不应回退到
        // 首个文本节点，否则后续结束事件会把整条消息误选中。
        if (target == null) {
          _anchorStart = null;
          _anchorEnd = null;
          return SelectionResult.none;
        }
        _anchorStart = target;
        _anchorEnd ??= target;
        final result = target.dispatchSelectionEvent(typed);
        _fillIntermediate(_anchorStart!, _anchorEnd!);
        return result;
      case SelectionEventType.endEdgeUpdate:
        final typed = event as SelectionEdgeUpdateEvent;
        final target = _selectableAt(typed.globalPosition);
        if (target == null || _anchorStart == null) {
          return SelectionResult.none;
        }
        _anchorEnd = target;
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
    this.scrollStateKey,
  });

  final String data;
  final Color textColor;
  final Color backgroundColor;
  final TextStyle? style;
  final String? scrollStateKey;

  @override
  Widget build(BuildContext context) {
    return _PlainTextMessageBody(
      data: data.isEmpty ? ' ' : data,
      textColor: textColor,
      backgroundColor: backgroundColor,
      style: style,
      scrollStateKey: scrollStateKey,
    );
  }
}

class _PlainTextMessageBody extends StatefulWidget {
  const _PlainTextMessageBody({
    required this.data,
    required this.textColor,
    required this.backgroundColor,
    this.previewMaxHeight = _messageResponsePreviewMaxHeight,
    this.style,
    this.collapsedOverride,
    this.onCollapsedChanged,
    this.showCollapseToggle = true,
    this.animateSize = true,
    this.scrollStateKey,
  });

  final String data;
  final Color textColor;
  final Color backgroundColor;
  final double previewMaxHeight;
  final TextStyle? style;
  final bool? collapsedOverride;
  final ValueChanged<bool>? onCollapsedChanged;
  final bool showCollapseToggle;
  final bool animateSize;
  final String? scrollStateKey;

  @override
  State<_PlainTextMessageBody> createState() => _PlainTextMessageBodyState();
}

class _PlainTextMessageBodyState extends State<_PlainTextMessageBody> {
  late bool _collapsed = _shouldCollapse(widget.data);
  bool _userToggled = false;

  String get _scrollStateKey =>
      widget.scrollStateKey ??
      'plain-message|${widget.data.length}|${boundedTextFingerprint(widget.data)}';

  @override
  void didUpdateWidget(covariant _PlainTextMessageBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    final recollapsedByParent =
        oldWidget.collapsedOverride == false &&
        widget.collapsedOverride == true;
    if (recollapsedByParent) {
      _CollapsedBodyScrollOffsetCache.reset(_scrollStateKey);
    }
    final oldScrollStateKey =
        oldWidget.scrollStateKey ??
        'plain-message|${oldWidget.data.length}|${boundedTextFingerprint(oldWidget.data)}';
    if (oldScrollStateKey != _scrollStateKey) {
      _CollapsedBodyScrollOffsetCache.reset(_scrollStateKey);
    }
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

  bool get _effectiveCollapsed => widget.collapsedOverride ?? _collapsed;

  void _setCollapsed(bool value) {
    if (value) {
      _CollapsedBodyScrollOffsetCache.reset(_scrollStateKey);
    }
    if (widget.collapsedOverride != null) {
      widget.onCollapsedChanged?.call(value);
      return;
    }
    setState(() {
      _collapsed = value;
      _userToggled = true;
    });
    widget.onCollapsedChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data.isEmpty ? ' ' : widget.data;
    final shouldCollapse = _shouldCollapse(data);
    final effectiveStyle =
        widget.style?.copyWith(color: widget.textColor) ??
        TextStyle(color: widget.textColor, height: 1.55);

    if (!shouldCollapse) {
      return SelectableText(data, style: effectiveStyle);
    }

    final collapsed = _effectiveCollapsed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showCollapseToggle) ...[
          _MessageCollapseToggleCapsule(
            collapsed: collapsed,
            characterCount: data.length,
            color: widget.textColor,
            onTap: () {
              _BubbleHtmlInteractiveScope.maybeOf(
                context,
              )?.markInteractiveTap();
              _setCollapsed(!collapsed);
            },
          ),
          kOpenHandGap8,
        ],
        _collapsibleMessageBodyMotion(
          context: context,
          collapsed: collapsed,
          animate: widget.animateSize,
          child: collapsed
              ? _PlainTextPreviewBody(
                  data: data,
                  maxHeight: widget.previewMaxHeight,
                  textColor: widget.textColor,
                  fadeColor: widget.backgroundColor,
                  style: effectiveStyle,
                  scrollStateKey: _scrollStateKey,
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
  if (!value.contains('<')) return false;
  return _htmlLikelyTagPattern.hasMatch(value);
}

/// 宽松的 HTML 标签结构检测：识别任意 `<标签名>` 或 `</标签名>` 形式，
/// 用于捕获白名单外的有效 HTML 标签（如 `<del>`、`<kbd>`、`<dfn>` 等）。
/// 配合 `_looksLikeHtml` 使用，避免 AI 输出的非常见标签被误判为纯文本。
final RegExp _htmlAnyTagPattern = RegExp(
  r'<\s*/?[a-zA-Z][a-zA-Z0-9-]*\b[^>]*>',
);
final RegExp _htmlHighCostTagPattern = RegExp(
  r'<\s*(?:table|tr|td|th|svg|path|canvas|video|audio|iframe|img|style|script)\b',
  caseSensitive: false,
);
final RegExp _htmlPreviewRawTextElementPattern = RegExp(
  r'<\s*(?:script|style|template)\b[\s\S]*?<\s*/\s*(?:script|style|template)\s*>',
  caseSensitive: false,
);
final RegExp _htmlPreviewLineBreakTagPattern = RegExp(
  r'<\s*br\s*/?\s*>',
  caseSensitive: false,
);
final RegExp _htmlPreviewBlockEndTagPattern = RegExp(
  r'</\s*(?:p|div|li|tr|table|section|article|header|footer|main|aside|h[1-6]|blockquote|pre)\s*>',
  caseSensitive: false,
);
final RegExp _htmlPreviewAnyTagPattern = RegExp(r'<[^>]+>');
final RegExp _htmlPreviewWhitespacePattern = RegExp(r'[ \t\f\r]+');
final RegExp _htmlPreviewBlankLinesPattern = RegExp(r'\n\s*\n\s*\n+');
final RegExp _htmlPreviewNumericEntityPattern = RegExp(
  r'&#(x[0-9a-fA-F]+|\d+);',
);

bool _hasHtmlTagStructure(String value) {
  if (value.isEmpty) return false;
  if (!value.contains('<')) return false;
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
  if (value.length > _htmlHealFullScanCharLimit) {
    if (lastLt <= lastGt) return value;
    final tail = value.substring(lastLt);
    final partial = _htmlPartialOpenTagPattern.firstMatch(tail);
    if (partial == null) return value;
    final tag = partial.group(1)!.toLowerCase();
    if (_htmlVoidTags.contains(tag)) return value;
    return '$value</$tag>';
  }
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
class _PreparedHtmlRenderData {
  const _PreparedHtmlRenderData({
    required this.sourceLength,
    required this.sourceFingerprint,
    required this.healedHtml,
    required this.previewText,
    required this.looksLikeHtml,
    required this.hasTagStructure,
    required this.tagCount,
    required this.highCostTagCount,
    required this.hasMarkdownFence,
    required this.healedSharesSource,
  });

  final int sourceLength;
  final int sourceFingerprint;
  final String healedHtml;
  final String previewText;
  final bool looksLikeHtml;
  final bool hasTagStructure;
  final int tagCount;
  final int highCostTagCount;

  /// 内容以 mermaid fence 开头或包含 fenced code block。此类内容必须坚持
  /// 走 Markdown 渲染；随 prepared 数据一起缓存，避免分发器每次 build 重
  /// 复对全文跑 fence 正则。
  final bool hasMarkdownFence;

  /// [healedHtml] 是否与源串同一实例（未做补齐）。
  final bool healedSharesSource;

  bool get isHtmlCandidate => looksLikeHtml || hasTagStructure;

  bool get shouldUseProgressiveHighFidelity {
    if (!isHtmlCandidate) return false;
    return sourceLength >= _htmlProgressiveRenderCharThreshold ||
        tagCount >= _htmlProgressiveRenderTagThreshold ||
        highCostTagCount >= _htmlProgressiveRenderHighCostTagThreshold;
  }

  /// 只按「本条目独占的新增驻留」记账：healedHtml 与源串共享实例时不计入，
  /// 否则大段纯文本 / markdown 消息会以全文长度挤占预算，把真正需要缓存的
  /// HTML 卡条目全部逐出，长会话滚动往返时被迫反复同步重算。
  int get cacheCost =>
      (healedSharesSource ? 0 : healedHtml.length) + previewText.length + 64;
}

final LifecycleLruCache<_PreparedHtmlRenderData> _preparedHtmlRenderCache =
    LifecycleLruCache<_PreparedHtmlRenderData>(
      maxEntries: _htmlPreparedCacheMaxEntries,
      maxCost: _htmlPreparedCacheMaxCost,
      costOf: (value) => value.cacheCost,
    );

/// 流式期间 markdown 格式消息的 HTML 嗅探粘滞判定（key 为消息级
/// scrollStateKey，流式期间稳定）。内容只会追加，「像 HTML 文档」的判定
/// 命中后不会随追加翻转为否；未命中时每次 flush 只做轻量正则判定，
/// 不进 prepared 管线、不污染 LRU。
final LifecycleLruCache<bool> _streamingHtmlSniffCache =
    LifecycleLruCache<bool>(maxEntries: 64, maxCost: 64, costOf: (_) => 1);

bool _streamingMarkdownLooksLikeHtml(String data, String? stickyKey) {
  if (data.isEmpty) return false;
  if (stickyKey != null && _streamingHtmlSniffCache.get(stickyKey) == true) {
    return true;
  }
  // fenced code block 一律坚持 Markdown：代码块正文可合法包含 HTML 字样。
  if (_containsMarkdownCodeFence(data)) return false;
  final looksHtml = _looksLikeHtml(data) || _hasHtmlTagStructure(data);
  if (looksHtml && stickyKey != null) {
    _streamingHtmlSniffCache.put(stickyKey, true);
  }
  return looksHtml;
}

String _preparedHtmlCacheKey(String value, int fingerprint) {
  // fingerprint 已含首尾采样 + 长度，再拼 value.hashCode 对长 HTML 是 O(n)
  // 且无额外区分力；用 length + fingerprint 即可。
  return '${value.length}:$fingerprint';
}

_PreparedHtmlRenderData _preparedHtmlRenderDataFor(String value) {
  final sourceLength = value.length;
  final sourceFingerprint = boundedTextFingerprint(value);
  final cacheKey = _preparedHtmlCacheKey(value, sourceFingerprint);
  final cached = _preparedHtmlRenderCache.get(cacheKey);
  if (cached != null &&
      cached.sourceLength == sourceLength &&
      cached.sourceFingerprint == sourceFingerprint) {
    return cached;
  }

  final looksLikeHtml = _looksLikeHtml(value);
  final hasTagStructure = !looksLikeHtml && _hasHtmlTagStructure(value);
  final isHtmlCandidate = looksLikeHtml || hasTagStructure;
  final healedHtml = isHtmlCandidate ? _healUnbalancedHtml(value) : value;
  final tagCount = isHtmlCandidate
      ? _countPatternMatchesUpTo(
          _htmlTagScanPattern,
          healedHtml,
          _htmlProgressiveRenderTagThreshold + 1,
        )
      : 0;
  final highCostTagCount = isHtmlCandidate
      ? _countPatternMatchesUpTo(
          _htmlHighCostTagPattern,
          healedHtml,
          _htmlProgressiveRenderHighCostTagThreshold + 1,
        )
      : 0;
  final trimmed = value.trim();
  final prepared = _PreparedHtmlRenderData(
    sourceLength: sourceLength,
    sourceFingerprint: sourceFingerprint,
    healedHtml: healedHtml,
    previewText: isHtmlCandidate ? _htmlPlainTextPreview(healedHtml) : '',
    looksLikeHtml: looksLikeHtml,
    hasTagStructure: hasTagStructure,
    tagCount: tagCount,
    highCostTagCount: highCostTagCount,
    hasMarkdownFence:
        _startsWithFencedMermaidBlock(trimmed) ||
        _containsMarkdownCodeFence(trimmed),
    healedSharesSource: identical(healedHtml, value),
  );
  _preparedHtmlRenderCache.put(cacheKey, prepared);
  return prepared;
}

int _countPatternMatchesUpTo(RegExp pattern, String value, int limit) {
  if (value.isEmpty || limit <= 0) return 0;
  var count = 0;
  for (final _ in pattern.allMatches(value)) {
    count += 1;
    if (count >= limit) break;
  }
  return count;
}

String _htmlPlainTextPreview(String html) {
  if (html.isEmpty) return '';
  final source = html.length > _htmlProgressiveRenderPreviewScanCharCap
      ? clipTextByCodeUnits(
          html,
          _htmlProgressiveRenderPreviewScanCharCap,
          suffix: '',
        )
      : html;
  var text = source
      .replaceAll(_htmlPreviewRawTextElementPattern, ' ')
      .replaceAll(_htmlPreviewLineBreakTagPattern, '\n')
      .replaceAll(_htmlPreviewBlockEndTagPattern, '\n')
      .replaceAll(_htmlPreviewAnyTagPattern, ' ');
  text = _decodeBasicHtmlEntities(text)
      .replaceAll(_htmlPreviewWhitespacePattern, ' ')
      .replaceAll(_htmlPreviewBlankLinesPattern, '\n\n')
      .trim();
  if (text.isEmpty) {
    final fallback = source.trim();
    if (fallback.length <= _htmlProgressiveRenderPreviewCharCap) {
      return fallback;
    }
    return clipTextByCodeUnits(
      fallback,
      _htmlProgressiveRenderPreviewCharCap,
      suffix: '',
    ).trimRight();
  }
  if (text.length <= _htmlProgressiveRenderPreviewCharCap) {
    return text;
  }
  return clipTextByCodeUnits(
    text,
    _htmlProgressiveRenderPreviewCharCap,
    suffix: '',
  ).trimRight();
}

String _decodeBasicHtmlEntities(String value) {
  if (!value.contains('&')) return value;
  final decoded = value
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'");
  return decoded.replaceAllMapped(_htmlPreviewNumericEntityPattern, (match) {
    final raw = match.group(1) ?? '';
    final isHex = raw.startsWith('x') || raw.startsWith('X');
    final codePoint = optionalIntFromText(
      isHex ? raw.substring(1) : raw,
      radix: isHex ? 16 : 10,
    );
    if (codePoint == null || codePoint < 0 || codePoint > 0x10FFFF) {
      return match.group(0) ?? '';
    }
    return String.fromCharCode(codePoint);
  });
}

String _prepareStreamingHtml(String value) =>
    _preparedHtmlRenderDataFor(value).healedHtml;

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
    final percent = optionalDoubleFromValue(widthMatch.group(1));
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
      final minWidth = optionalDoubleFromValue(autoFit.group(1)) ?? maxWidth;
      // `minmax(0px, …)` 且未声明 gap 时分母为 0，除法得到 Infinity/NaN，
      // `.floor()` 会抛 UnsupportedError 并把整个消息体换成错误占位。
      // 先在浮点域按 [1, childCount] 夹紧再取整，取整永远落在合法区间。
      final track = minWidth + gap;
      final rawColumns = track > 0
          ? (maxWidth + gap) / track
          : childCount.toDouble();
      return rawColumns.isFinite
          ? rawColumns.clamp(1.0, childCount.toDouble()).floor()
          : childCount;
    }
    final repeat = _repeatColumnPattern.firstMatch(template);
    if (repeat != null) {
      return (optionalIntFromValue(repeat.group(1)) ?? childCount)
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
    final text = nullIfBlank(value);
    if (text == null) return null;
    final match = _cssLengthPattern.firstMatch(text);
    if (match == null) return null;
    return _parseCssLengthMatch(match, maxWidth: maxWidth);
  }

  static double? _parseCssLengthMatch(RegExpMatch match, {double? maxWidth}) {
    final raw = optionalDoubleFromValue(match.group(1));
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

    final accentHex = _cssHexFromColor(accent);
    final borderHex = _cssHexFromColor(borderColor);
    final codeBgHex = _cssHexFromColor(codeBg);
    final mutedHex = _cssHexFromColor(mutedText);

    final prepared = _prepareStreamingHtml(data);
    return ClipRect(
      child: SelectionArea(
        child: _MarkdownSelectionContainer(
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
      duration: _streamingHtmlDotsDuration,
    );
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
    final animationsEnabled = openHandTickerMotionEnabled(context);
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
                    kOpenHandHGap6,
                    Flexible(
                      child: Text(
                        openHandLocalizedText(
                          context,
                          zh: '正在生成 HTML 卡片',
                          en: 'Generating HTML card',
                        ),
                        style: captionStyle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    kOpenHandHGap4,
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
                    _homeMessageConCharsLabel(context),
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
/// 高亮感由共享扫光层承担。
class _HtmlBubbleShimmer extends StatelessWidget {
  const _HtmlBubbleShimmer();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final baseColor = cs.onSurface.withValues(alpha: 0.08);
    return OpenHandSweepShimmer(
      duration: _htmlBubbleShimmerDuration,
      sweepColor: cs.onSurface.withValues(alpha: 0.10),
      maskToChildAlpha: true,
      child: _buildContent(baseColor),
    );
  }

  Widget _buildBar(Color color, {double? width}) {
    return Container(
      width: width ?? double.infinity,
      height: 12,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kOpenHandRadius6),
        color: color,
      ),
    );
  }

  Widget _buildContent(Color color) {
    // 容器底色透明：避免在 assistant 卡片（surfaceContainerHigh）等
    // 任意底色之上再叠一块"更深一档"的色块导致色差。
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBar(color),
          kOpenHandGap8,
          _buildBar(color),
          kOpenHandGap8,
          _buildBar(color),
          kOpenHandGap8,
          _buildBar(color, width: 180),
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

int _htmlBubbleHeightCacheKey(String data, TextStyle? baseTextStyle) {
  return Object.hash(
    boundedTextFingerprint(data),
    baseTextStyle?.fontSize,
    baseTextStyle?.height,
  );
}

/// 平台视图挂载同样限制为 1/帧：WebView 创建会同步阻塞 UI 线程。
final _FrameTaskScheduler _htmlWebViewFrameScheduler = _FrameTaskScheduler(
  maxPerFrame: 1,
);

void _scheduleHtmlWebViewPermitGrant(void Function() task) {
  WidgetsBinding.instance.addPostFrameCallback((_) => task());
  WidgetsBinding.instance.ensureVisualUpdate();
}

final HtmlWebViewMountLimiter _htmlWebViewActiveLimiter =
    HtmlWebViewMountLimiter(
      maxMounted: _htmlWebViewMaxActiveInstances,
      scheduleGranted: _scheduleHtmlWebViewPermitGrant,
    );
final HtmlWebViewMountLimiter _htmlWebViewBootstrapLimiter =
    HtmlWebViewMountLimiter(
      maxMounted: _htmlWebViewMaxConcurrentBootstraps,
      scheduleGranted: _scheduleHtmlWebViewPermitGrant,
    );

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
  /// 许可等待超时的重试上限：超过后转 Flutter 静态 HTML 渲染，内容照常
  /// 可见。视口内 HTML 卡多于并发上限时，无界重试会形成「销毁-重建」
  /// 平台视图风暴（WebView 创建同步阻塞 UI 线程，是 ANR 的直接来源）。
  static const int _kPermitWaitMaxTimeouts = 2;

  bool _mountWebView = false;
  bool _useFlutterFallback = false;
  // 压力型回退（许可等待超时/排队溢出）可在限流器出现空位后重试；
  // WebView 真实失败的回退保持永久，避免坏内容反复重载循环。
  bool _canRetryFallbackOnCapacity = false;
  int _generation = 0;
  int? _mountedWebViewGeneration;
  TranscriptScrollActivity? _scrollActivity;
  bool _pendingMountAfterScroll = false;
  HtmlWebViewMountPermit? _activePermit;
  HtmlWebViewMountPermit? _bootstrapPermit;
  Timer? _coldMountTimer;
  Timer? _permitWaitTimer;
  Timer? _bootstrapTimer;
  int _permitWaitTimeoutCount = 0;

  bool _hasWarmWebViewMetrics() {
    final cacheKey = _htmlBubbleHeightCacheKey(
      widget.data,
      widget.baseTextStyle,
    );
    return _HtmlBubbleWebViewState._readBoundedHeightCache(
              _HtmlBubbleWebViewState._heightCache,
              cacheKey,
            ) !=
            null ||
        _HtmlBubbleWebViewState._readBoundedHeightCache(
              _HtmlBubbleWebViewState._heightFloorCache,
              cacheKey,
            ) !=
            null ||
        _HtmlBubbleWebViewState._readBoundedHeightCache(
              _HtmlBubbleWebViewState._revealedHeightCache,
              cacheKey,
            ) !=
            null;
  }

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
      if (_useFlutterFallback) _useFlutterFallback = false;
      if (_mountWebView) return;
      _generation += 1;
      _permitWaitTimeoutCount = 0;
      _pendingMountAfterScroll = false;
      _cancelColdMountTimer();
      _bootstrapTimer?.cancel();
      _bootstrapTimer = null;
      _releaseHtmlWebViewPermits();
      _scheduleMount();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final activity = _maybeTranscriptScrollActivityOf(context);
    if (identical(activity, _scrollActivity)) {
      return;
    }
    _scrollActivity?.removeListener(_handleScrollActivityChanged);
    _scrollActivity = activity;
    activity?.addListener(_handleScrollActivityChanged);
    if (activity == null && _pendingMountAfterScroll && !_mountWebView) {
      _pendingMountAfterScroll = false;
      _scheduleMount();
    }
  }

  @override
  void dispose() {
    _scrollActivity?.removeListener(_handleScrollActivityChanged);
    _scrollActivity = null;
    _generation += 1;
    _cancelColdMountTimer();
    _bootstrapTimer?.cancel();
    _bootstrapTimer = null;
    _releaseHtmlWebViewPermits();
    super.dispose();
  }

  void _handleScrollActivityChanged() {
    final activity = _scrollActivity;
    if (activity == null || !mounted || activity.value) {
      return;
    }
    // 压力型回退的自愈时机：滚动停止且限流器有空位时重试一次。
    // 以滚动事件为节拍天然有界；keepAlive 的离屏卡释放许可后，
    // 曾被饿死的卡不再永久停留在静态形态。
    if (_useFlutterFallback &&
        _canRetryFallbackOnCapacity &&
        _htmlWebViewActiveLimiter.hasCapacity) {
      _canRetryFallbackOnCapacity = false;
      _permitWaitTimeoutCount = 0;
      setState(() => _useFlutterFallback = false);
      _scheduleMount();
      return;
    }
    if (!_pendingMountAfterScroll || _mountWebView) {
      return;
    }
    _pendingMountAfterScroll = false;
    _scheduleMount();
  }

  void _scheduleMount({bool allowColdDelay = true}) {
    if (_mountWebView || _activePermit != null || _coldMountTimer != null) {
      return;
    }
    // 滚动进行中一律推迟挂载（不再豁免有高度缓存的 warm 卡）：WebView
    // 创建同步占用 UI 线程数十毫秒，fling 中挂载必然掉帧；warm 卡的占位
    // 盒尺寸精确，等滚动停止再挂载没有布局跳动。
    if (_scrollActivity?.value ?? false) {
      _pendingMountAfterScroll = true;
      return;
    }
    if (allowColdDelay && !_hasWarmWebViewMetrics()) {
      final generation = ++_generation;
      _coldMountTimer = startSafeTimer(_htmlWebViewColdMountDelay, () {
        _coldMountTimer = null;
        if (!mounted || generation != _generation || _mountWebView) {
          return;
        }
        _scheduleMount(allowColdDelay: false);
      });
      return;
    }
    final generation = ++_generation;
    final scheduled = _htmlWebViewFrameScheduler.schedule(
      () {
        if (!mounted || generation != _generation || _mountWebView) {
          return;
        }
        if (_scrollActivity?.value ?? false) {
          _pendingMountAfterScroll = true;
          return;
        }
        _tryMountWebView(generation);
      },
      priority: true,
      isValid: () => mounted && generation == _generation && !_mountWebView,
    );
    if (!scheduled) _handleWebViewFallback(retryOnCapacity: true);
  }

  void _tryMountWebView(int generation) {
    if (!mounted || generation != _generation || _mountWebView) return;
    final existing = _activePermit;
    if (existing != null) {
      if (existing.granted) _requestWebViewBootstrap(generation);
      return;
    }

    late final HtmlWebViewMountPermit permit;
    final warmMetrics = _hasWarmWebViewMetrics();
    permit = _htmlWebViewActiveLimiter.request(() {
      if (!mounted ||
          generation != _generation ||
          _mountWebView ||
          !identical(_activePermit, permit)) {
        permit.release();
        return;
      }
      if (_scrollActivity?.value ?? false) {
        // 许可授予落在滚动进行中：释放并等滚动停止后重排，避免 fling
        // 中同步创建平台视图掉帧。
        _pendingMountAfterScroll = true;
        _activePermit = null;
        permit.release();
        return;
      }
      _permitWaitTimeoutCount = 0;
      _pendingMountAfterScroll = false;
      _cancelPermitWaitTimer();
      _requestWebViewBootstrap(generation);
    }, priority: warmMetrics);
    _activePermit = permit;
    if (permit.released) {
      _handleWebViewFallback(retryOnCapacity: true);
      return;
    }
    if (permit.granted) {
      _permitWaitTimeoutCount = 0;
      _pendingMountAfterScroll = false;
      _cancelPermitWaitTimer();
      _requestWebViewBootstrap(generation);
    } else {
      _startPermitWaitTimer(permit, generation);
    }
  }

  void _requestWebViewBootstrap(int generation) {
    if (!mounted ||
        generation != _generation ||
        _mountWebView ||
        _activePermit?.granted != true ||
        _bootstrapPermit != null) {
      return;
    }
    late final HtmlWebViewMountPermit permit;
    permit = _htmlWebViewBootstrapLimiter.request(() {
      if (!mounted ||
          generation != _generation ||
          _mountWebView ||
          !identical(_bootstrapPermit, permit) ||
          _activePermit?.granted != true) {
        permit.release();
        return;
      }
      _mountGrantedWebView(generation);
    }, priority: _hasWarmWebViewMetrics());
    _bootstrapPermit = permit;
    if (permit.released) {
      _handleWebViewFallback(retryOnCapacity: true);
      return;
    }
    if (permit.granted) _mountGrantedWebView(generation);
  }

  void _mountGrantedWebView(int generation) {
    if (!mounted ||
        generation != _generation ||
        _mountWebView ||
        _activePermit?.granted != true ||
        _bootstrapPermit?.granted != true) {
      return;
    }
    _mountedWebViewGeneration = generation;
    _beginWebViewBootstrap(generation);
    setState(() => _mountWebView = true);
  }

  void _beginWebViewBootstrap(int generation) {
    _bootstrapTimer?.cancel();
    _bootstrapTimer = startSafeTimer(
      _htmlWebViewBootstrapTimeout,
      () => _handleWebViewBootstrapReady(generation),
    );
  }

  void _handleWebViewBootstrapReady(int generation) {
    if (generation != _generation || generation != _mountedWebViewGeneration) {
      return;
    }
    _bootstrapTimer?.cancel();
    _bootstrapTimer = null;
    _releaseBootstrapPermit();
  }

  void _handleWebViewFallback({bool retryOnCapacity = false}) {
    _bootstrapTimer?.cancel();
    _bootstrapTimer = null;
    _releaseHtmlWebViewPermits();
    _mountedWebViewGeneration = null;
    _canRetryFallbackOnCapacity = retryOnCapacity;
    if (mounted) {
      setState(() {
        _mountWebView = false;
        _useFlutterFallback = true;
      });
    }
  }

  void _releaseBootstrapPermit() {
    final permit = _bootstrapPermit;
    if (permit == null) return;
    _bootstrapPermit = null;
    permit.release();
  }

  void _releaseHtmlWebViewPermits() {
    // 等待计时器必须无条件取消：若跟着 `_activePermit == null` 提前返回，
    // 计时器会越过 dispose 继续持有已销毁的 State 直到超时。
    _cancelPermitWaitTimer();
    _releaseBootstrapPermit();
    final permit = _activePermit;
    if (permit == null) return;
    _activePermit = null;
    permit.release();
  }

  void _cancelColdMountTimer() {
    final timer = _coldMountTimer;
    if (timer == null) {
      return;
    }
    timer.cancel();
    _coldMountTimer = null;
  }

  void _cancelPermitWaitTimer() {
    final timer = _permitWaitTimer;
    if (timer == null) {
      return;
    }
    timer.cancel();
    _permitWaitTimer = null;
  }

  void _startPermitWaitTimer(HtmlWebViewMountPermit permit, int generation) {
    _cancelPermitWaitTimer();
    _permitWaitTimer = startSafeTimer(_htmlWebViewPermitWaitTimeout, () {
      _permitWaitTimer = null;
      if (!mounted ||
          generation != _generation ||
          _mountWebView ||
          !identical(_activePermit, permit) ||
          permit.granted) {
        return;
      }
      _activePermit = null;
      permit.release();
      // 有界重试：并发上限长期占满（视口内 HTML 卡过多）时不再撤销正在
      // 展示的卡片去喂等待者——那会造成可见卡轮流闪白重载；重试耗尽后
      // 直接回退 Flutter 静态渲染，内容依旧完整可见。
      _permitWaitTimeoutCount += 1;
      if (_permitWaitTimeoutCount >= _kPermitWaitMaxTimeouts) {
        _handleWebViewFallback(retryOnCapacity: true);
        return;
      }
      if (_scrollActivity?.value ?? false) {
        _pendingMountAfterScroll = true;
        return;
      }
      _coldMountTimer = startSafeTimer(_htmlWebViewPermitRetryDelay, () {
        _coldMountTimer = null;
        if (!mounted || generation != _generation || _mountWebView) {
          return;
        }
        _scheduleMount(allowColdDelay: false);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_useFlutterFallback) {
      return _HtmlMessageBody(
        data: widget.data,
        textColor: widget.textColor,
        baseTextStyle: widget.baseTextStyle,
      );
    }
    if (_mountWebView) {
      return _HtmlBubbleWebView(
        key: const ValueKey<String>('html-bubble-webview'),
        data: widget.data,
        textColor: widget.textColor,
        backgroundColor: widget.backgroundColor,
        baseTextStyle: widget.baseTextStyle,
        onBootstrapReady: () =>
            _handleWebViewBootstrapReady(_mountedWebViewGeneration ?? -1),
        onFallback: _handleWebViewFallback,
      );
    }
    return SizedBox(
      height: _estimateHtmlBubbleHeight(widget.data),
      child: const _HtmlBubbleShimmer(),
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
    required this.onBootstrapReady,
    required this.onFallback,
    this.baseTextStyle,
  });

  final String data;
  final Color textColor;
  final Color backgroundColor;
  final VoidCallback onBootstrapReady;
  final VoidCallback onFallback;
  final TextStyle? baseTextStyle;

  @override
  State<_HtmlBubbleWebView> createState() => _HtmlBubbleWebViewState();
}

class _HtmlBubbleWebViewState extends State<_HtmlBubbleWebView> {
  // 高度测量与防抖常量
  static const double _kMinHeightClamp = 24.0;
  static const double _kMaxHeightClamp = 50000.0;
  static const double _kFirstMeasurementSkipThreshold = 5000.0;
  // Filter DPR, font-subpixel and DOM measurement noise in steady state.
  static const double _kMinHeightDelta = 8.0;
  static const double _kLargeChangeRatio = 0.30;
  static const Duration _kMinHeightApplyInterval = Duration(milliseconds: 300);
  // Retain enough measured heights to avoid rebuilding HTML placeholders when
  // a long transcript scrolls back into view.
  static const int _kHeightCacheMaxSize = 512;
  // Debounce image/font reflow measurements without keeping the placeholder
  // visible after the WebView has settled.
  static const Duration _kHeightDebounceDuration = Duration(milliseconds: 250);
  // 渲染占位高度估算常量：HTML 文本在 14px 字体下平均每行约容纳 80
  // 字符、24 像素高。占位时按内容长度给出一个不至于"突然伸长"的
  // 初始高度，避免 shimmer 96px 与真实高度之间出现夸张落差。
  static const double _kEstimatedLineHeight = 24.0;
  static const int _kEstimatedCharsPerLine = 80;
  static const double _kEstimatedMinHeight = 96.0;
  static const double _kEstimatedMaxHeight = 960.0;
  static const Duration _kInitialRevealFallbackDelay = Duration(
    milliseconds: 1600,
  );
  // 首次测量 outlier 阈值。WebView 第一次测高常因图片/CSS
  // 未完成返回异常大的值（如 5000+），直接应用会撑出"渲染下方空白"。
  // 当首测高度 > 估算高度 × ratio 时，**先应用估算高度**作为初始
  // 显示尺寸，后续测量（250ms 防抖）会把高度修正到准确值；视觉上看
  // 是"由小到大"生长，比"由大到小收缩留下大片空白"更可接受。
  static const double _kFirstMeasurementOutlierRatio = 2.0;
  // 基于参考高度的 outlier 阈值。WebView 测高在 CSS reset
  // 注入前/字体回退/图片懒加载等瞬态下可能返回"原始 HTML 文本高度"
  // ——把标签字符当纯文本逐行排版的高度（远大于渲染后高度）。一旦
  // 新测量值 > 参考高度 × ratio，视为瞬态噪声，**保留旧值**而不用
  // 新值——让后续稳定测量来修正，避免"渲染下方空白"的偶发跳变。
  // 1.5 倍是经验值：合法增长（details 展开、聊天消息展开）通常 <1.3 倍。
  static const double _kReferenceOutlierRatio = 1.5;
  static const String _viewportHeightResetCss =
      'body.min-h-screen,body.h-screen,body.min-h-dvh,body.h-dvh,'
      'body.min-h-svh,body.h-svh,body.min-h-lvh,body.h-lvh,'
      'body[class*="100vh"],body[class*="100dvh"],'
      'body[class*="100svh"],body[class*="100lvh"],'
      'body [class~="min-h-screen"],body [class~="h-screen"],'
      'body [class~="min-h-dvh"],body [class~="h-dvh"],'
      'body [class~="min-h-svh"],body [class~="h-svh"],'
      'body [class~="min-h-lvh"],body [class~="h-lvh"],'
      'body [class*="100vh"],body [class*="100dvh"],'
      'body [class*="100svh"],body [class*="100lvh"],'
      'body [style*="100vh"],body [style*="100dvh"],'
      'body [style*="100svh"],body [style*="100lvh"]{'
      'min-height:auto!important;height:auto!important;}';
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
      '$_viewportHeightResetCss'
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
      var _resetCss = 'html,body{min-height:0!important;height:auto!important;overflow-y:hidden!important;}html,body,body *{-webkit-user-select:text;user-select:text;}body{box-sizing:border-box!important;cursor:text;}body.min-h-screen,body.h-screen,body.min-h-dvh,body.h-dvh,body.min-h-svh,body.h-svh,body.min-h-lvh,body.h-lvh,body[class*="100vh"],body[class*="100dvh"],body[class*="100svh"],body[class*="100lvh"],body [class~="min-h-screen"],body [class~="h-screen"],body [class~="min-h-dvh"],body [class~="h-dvh"],body [class~="min-h-svh"],body [class~="h-svh"],body [class~="min-h-lvh"],body [class~="h-lvh"],body [class*="100vh"],body [class*="100dvh"],body [class*="100svh"],body [class*="100lvh"],body [style*="100vh"],body [style*="100dvh"],body [style*="100svh"],body [style*="100lvh"]{min-height:auto!important;height:auto!important;}a,button,summary,[role="button"]{cursor:pointer;}input,textarea,select{cursor:text;}';
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
      normalizeViewportHeightFillers();
    } catch (_) {}
  }
  function normalizeViewportHeightFillers() {
    try {
      var selector = 'body.min-h-screen,body.h-screen,body.min-h-dvh,body.h-dvh,body.min-h-svh,body.h-svh,body.min-h-lvh,body.h-lvh,body[class*="100vh"],body[class*="100dvh"],body[class*="100svh"],body[class*="100lvh"],body [class~="min-h-screen"],body [class~="h-screen"],body [class~="min-h-dvh"],body [class~="h-dvh"],body [class~="min-h-svh"],body [class~="h-svh"],body [class~="min-h-lvh"],body [class~="h-lvh"],body [class*="100vh"],body [class*="100dvh"],body [class*="100svh"],body [class*="100lvh"],body [style*="100vh"],body [style*="100dvh"],body [style*="100svh"],body [style*="100lvh"]';
      var nodes = document.querySelectorAll ? document.querySelectorAll(selector) : [];
      var limit = Math.min(nodes.length, 240);
      for (var i = 0; i < limit; i++) {
        var style = nodes[i] && nodes[i].style;
        if (!style) continue;
        // 写前比较：无条件 setProperty 会触发 attributes MutationObserver →
        // schedule → measure → 再写，形成 60Hz 永续的全量 DOM 扫描死循环。
        // 值与 !important 优先级都一致才跳过，首写后即收敛、不再自激。
        if (style.getPropertyValue('min-height') !== 'auto' || style.getPropertyPriority('min-height') !== 'important') style.setProperty('min-height', 'auto', 'important');
        if (style.getPropertyValue('height') !== 'auto' || style.getPropertyPriority('height') !== 'important') style.setProperty('height', 'auto', 'important');
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
    if (/(^|;)\s*(?:min-height|height)\s*:[^;]*\d(?:\.\d+)?(?:vh|dvh|svh|lvh)\b/.test(inlineStyle)) return true;
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
        // 样式只在创建时写一次：每次 measure 重写 cssText 会被 subtree
        // attributes 观察者捕获并再次 schedule，构成测高自激循环。
        marker.style.cssText = 'display:block;clear:both;width:0;height:0;margin:0;padding:0;border:0;overflow:hidden;pointer-events:none;';
      }
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
        var bridge = window.flutter_inappwebview;
        if (bridge && typeof bridge.callHandler === 'function') {
          try {
            bridge.callHandler('OpenHandHeight', height);
            __lastReportedHeight = height;
          } catch (_) {
            setTimeout(schedule, 120);
          }
        } else {
          setTimeout(schedule, 120);
        }
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
  static final LinkedHashMap<int, double> _heightCache =
      LinkedHashMap<int, double>();
  // 跨 State 生命周期的单调 floor。
  // State dispose 时把真实测量高度写入此 cache，新 State 重建后若 _height
  // 丢失则用 floor 兜底，防止 Stack 高度收缩到 estimatedHeight 导致
  // maxScrollExtent 抖动。与 _heightCache 分离：floor 只写 dispose 时的
  // 真实高度，outlier 占位估计绝不写入，避免污染持久化数据。
  static final LinkedHashMap<int, double> _heightFloorCache =
      LinkedHashMap<int, double>();
  // 记录用户已经看见过真实 WebView 内容的高度。它可以来自真实测量，
  // 也可以来自首次揭示 fallback；重进视口时用它跳过 shimmer，避免
  // 已渲染 HTML 卡片重新显示骨架屏。
  static final LinkedHashMap<int, double> _revealedHeightCache =
      LinkedHashMap<int, double>();
  // Cache the assembled document by content and effective styling so ordinary
  // rebuilds do not repeat regex and template work.
  String? _documentCacheData;
  Color? _documentCacheTextColor;
  Color? _documentCacheBackgroundColor;
  TextStyle? _documentCacheBaseTextStyle;
  String? _documentCache;
  String? _webViewWidgetDocument;
  Widget? _webViewWidget;
  late final iaw.InAppWebViewSettings _webViewSettings =
      iaw.InAppWebViewSettings(
        transparentBackground: !Platform.isMacOS,
        disableVerticalScroll: true,
      );
  int _measurementCount = 0;
  int _loadGeneration = 0;
  Timer? _heightDebounceTimer;
  Timer? _initialRevealFallbackTimer;
  // ResizeObserver updates only replace the pending value; they do not reset
  // the one-shot timer, guaranteeing that continuous reflow eventually lands.
  double? _pendingHeight;
  // 限制高度应用间隔，阻断 WebView resize → setState → 再次 resize 闭环振荡。
  final Stopwatch _heightApplyStopwatch = Stopwatch()..start();
  int? _lastHeightApplyAtMs;
  // 用于让外层气泡 pointer 监听在命中 WebView 区域时跳过
  // "选中卡片"切换，从而让 HTML 内部的按钮/超链接/表单能被点击。
  final GlobalKey _webViewRegionKey = GlobalKey();
  _MessageBubbleState? _bubbleStateForRegion;
  // 滚动活动协调信号。active=true 时 JS 测高只缓存、不应用，
  // 避免 maxScrollExtent 抖动把 viewport 拽回底部。inactive 时外层滚动
  // 宽限期已经结束，可在当前可见消息锚点保护下一次性应用最新高度。
  TranscriptScrollActivity? _scrollActivity;
  bool _scrollActive = false;
  bool _safeSetStateQueued = false;
  // 首次测量 outlier 检查状态位。首次非跳过的测量若超
  // 出估算高度 × ratio，标记为已处理并应用估算高度（避免"渲染下方
  // 空白"）；之后不再做 outlier 检查，正常走 500ms 防抖路径。
  bool _firstMeasurementHandled = false;
  bool _heightFromFallback = false;
  bool _bootstrapReadyReported = false;
  int get _heightCacheKey =>
      _htmlBubbleHeightCacheKey(widget.data, widget.baseTextStyle);

  bool get _heightUpdatesFrozen => _scrollActive;

  static void _writeBoundedHeightCache(
    LinkedHashMap<int, double> cache,
    int key,
    double value,
  ) {
    cache.remove(key);
    cache[key] = value;
    if (cache.length > _kHeightCacheMaxSize) {
      cache.remove(cache.keys.first);
    }
  }

  static double? _readBoundedHeightCache(
    LinkedHashMap<int, double> cache,
    int key,
  ) {
    final value = cache.remove(key);
    if (value == null) return null;
    cache[key] = value;
    return value;
  }

  @override
  void initState() {
    super.initState();
    _armInitialRevealFallback();
  }

  @override
  void didUpdateWidget(covariant _HtmlBubbleWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data ||
        oldWidget.textColor != widget.textColor ||
        oldWidget.backgroundColor != widget.backgroundColor ||
        oldWidget.baseTextStyle != widget.baseTextStyle) {
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
    final activity = _maybeTranscriptScrollActivityOf(context);
    if (!identical(activity, _scrollActivity)) {
      _scrollActivity?.removeListener(_onScrollActivityChanged);
      _scrollActivity = activity;
      final wasScrollActive = _scrollActive;
      _scrollActive = activity?.value ?? false;
      activity?.addListener(_onScrollActivityChanged);
      if (activity == null && wasScrollActive) {
        _applyPendingHeightIfAny();
      }
    }
  }

  void _onScrollActivityChanged() {
    final activity = _scrollActivity;
    if (activity == null || !mounted) return;
    final isActive = activity.value;
    if (isActive == _scrollActive) return;
    if (isActive) {
      _heightDebounceTimer?.cancel();
      _heightDebounceTimer = null;
      _scrollActive = true;
      return;
    }
    _scrollActive = false;
    _applyPendingHeightIfAny();
  }

  @override
  void dispose() {
    _heightDebounceTimer?.cancel();
    _initialRevealFallbackTimer?.cancel();
    _heightApplyStopwatch.stop();
    _scrollActivity?.removeListener(_onScrollActivityChanged);
    _scrollActivity = null;
    _bubbleStateForRegion?.unregisterHtmlInteractiveRegion(_webViewRegionKey);
    _bubbleStateForRegion = null;
    // State 被 ListView 回收前，只保存 JS 实测过的真实高度。fallback /
    // outlier 估算值不能写入 floor，否则滚动冻结时会把消息卡撑出空白。
    if (_height != null && !_heightFromFallback) {
      _writeBoundedHeightCache(_heightFloorCache, _heightCacheKey, _height!);
    }
    if (_height != null) {
      _writeBoundedHeightCache(_revealedHeightCache, _heightCacheKey, _height!);
    }
    super.dispose();
  }

  void _safeSetState(VoidCallback update) {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    final inFrame =
        phase == SchedulerPhase.transientCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks ||
        phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.postFrameCallbacks;
    if (!inFrame) {
      setState(update);
      return;
    }
    update();
    if (_safeSetStateQueued) return;
    _safeSetStateQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _safeSetStateQueued = false;
      setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _reload() async {
    _loadGeneration += 1;
    // 内容/样式变化时清除旧高度缓存与 floor，避免新内容被旧大值撑出空白。
    _heightCache.remove(_heightCacheKey);
    _heightFloorCache.remove(_heightCacheKey);
    _invalidateDocumentCaches();
    _safeSetState(() {
      _height = null;
      _hasError = false;
      _heightFromFallback = false;
    });
    _measurementCount = 0;
    _firstMeasurementHandled = false;
    _heightDebounceTimer?.cancel();
    _armInitialRevealFallback();
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.loadData(data: _buildDocument());
    } catch (error, stack) {
      silentLog('home_message_content', '重新加载 HTML 气泡失败', error, stack);
    }
  }

  void _reportBootstrapReady() {
    if (_bootstrapReadyReported) return;
    _bootstrapReadyReported = true;
    widget.onBootstrapReady();
  }

  void _armInitialRevealFallback() {
    _initialRevealFallbackTimer?.cancel();
    final generation = _loadGeneration;
    _initialRevealFallbackTimer = startSafeTimer(
      _kInitialRevealFallbackDelay,
      () {
        if (!mounted || generation != _loadGeneration || _hasError) {
          return;
        }
        if (_height != null ||
            _readBoundedHeightCache(_heightCache, _heightCacheKey) != null) {
          return;
        }
        final estimated = _estimateHeight();
        _writeBoundedHeightCache(
          _revealedHeightCache,
          _heightCacheKey,
          estimated,
        );
        _safeSetState(() {
          _height = estimated;
          _heightFromFallback = true;
        });
        _reportBootstrapReady();
        final controller = _controller;
        if (controller != null) {
          unawaited(
            controller
                .evaluateJavascript(source: _heightObserverScript)
                .catchError((Object error, StackTrace stack) {
                  silentLog(
                    'home_message_content',
                    '探测 HTML 气泡备用高度失败',
                    error,
                    stack,
                  );
                  return null;
                }),
          );
        }
      },
    );
  }

  void _onContentSizeChanged(Size newSize) {
    _reportBootstrapReady();
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
    // 用户正在滚动外层
    // ListView 时，WebView 的 ResizeObserver / MutationObserver 也会
    // 持续回测高度。如果立即 apply 触发 setState → SliverList 重新
    // 布局 → maxScrollExtent 抖动 → Flutter clamp 滚动位置 → 视口被
    // 拽回底部。此期间只缓存最新值，滚动结束后的安静期再一次性应用。
    if (_heightUpdatesFrozen) {
      _pendingHeight = next;
      return;
    }
    // 首次非跳过的测量做 outlier 检查。WebView 首测常因
    // 图片/CSS 未完成返回异常大值，直接应用会撑出"渲染下方空白"。
    // 若超出估算高度 × ratio，改用估算高度作初始显示值，后续测量
    // 经 500ms 防抖会修正到准确值。视觉上是"由小到大"生长，比
    // "由大到小收缩留下空白"更可接受。仅对首测做一次判定，避免后
    // 续正常 reflow 持续被当成 outlier 抑制。
    if (!_firstMeasurementHandled && !_heightFromFallback) {
      _firstMeasurementHandled = true;
      final estimated = _estimateHeight();
      if (next > estimated * _kFirstMeasurementOutlierRatio) {
        // outlier 占位高度只写本地 _height，**绝不写入任何持久化 cache**，
        // 避免 estimatedHeight 污染 _heightCache / _heightFloorCache。
        _safeSetState(() {
          _height = estimated;
          _heightFromFallback = true;
        });
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
        final lastApplyAtMs = _lastHeightApplyAtMs;
        if (lastApplyAtMs != null &&
            _heightApplyStopwatch.elapsedMilliseconds - lastApplyAtMs <
                _kMinHeightApplyInterval.inMilliseconds) {
          _pendingHeight = next;
          final timer = _heightDebounceTimer;
          if (timer == null || !timer.isActive) {
            _heightDebounceTimer = startSafeTimer(_kHeightDebounceDuration, () {
              if (!mounted) return;
              _heightDebounceTimer = null;
              if (_heightUpdatesFrozen) {
                return;
              }
              final pending = _pendingHeight;
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
      _heightDebounceTimer = startSafeTimer(_kHeightDebounceDuration, () {
        if (!mounted) return;
        _heightDebounceTimer = null;
        if (_heightUpdatesFrozen) {
          return;
        }
        final pending = _pendingHeight;
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
    _initialRevealFallbackTimer?.cancel();
    // outlier 检查**集中**在 apply 入口——所有上游路径
    //（scroll-active 缓存、pending apply、debounce timer、immediate
    // apply）都通过本方法落地，确保"rendered → raw → rendered"跳变
    // 在任何路径下都被拒收。参考高度优先级：floor（dispose 时写入的
    // 真实高度）> current _height > cached。瞬态测量（CSS reset 注
    // 入/字体回退/图片懒加载/卡片重进 viewport 触发的二次 layout）
    // 返回的"原始 HTML 文本高度"通常 > 1.5× 真实渲染高度，直接判
    // 为噪声保留旧值。
    final refHeight =
        _readBoundedHeightCache(_heightFloorCache, _heightCacheKey) ??
        (_heightFromFallback ? null : _height) ??
        _readBoundedHeightCache(_heightCache, _heightCacheKey);
    if (refHeight != null && refHeight > 0) {
      final refRatio = next / refHeight;
      if (refRatio > _kReferenceOutlierRatio) {
        return;
      }
    }
    _writeBoundedHeightCache(_heightCache, _heightCacheKey, next);
    _writeBoundedHeightCache(_heightFloorCache, _heightCacheKey, next);
    _writeBoundedHeightCache(_revealedHeightCache, _heightCacheKey, next);
    _lastHeightApplyAtMs = _heightApplyStopwatch.elapsedMilliseconds;
    _safeSetState(() {
      _height = next;
      _heightFromFallback = false;
    });
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
      silentLog('home_message_content', '模拟 HTML 气泡点击失败', error, stack);
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
      silentLog('home_message_content', 'HTML 气泡选择桥接失败', error, stack);
    }
  }

  void _invalidateDocumentCaches() {
    _documentCacheData = null;
    _documentCacheTextColor = null;
    _documentCacheBackgroundColor = null;
    _documentCacheBaseTextStyle = null;
    _documentCache = null;
    _webViewWidgetDocument = null;
    _webViewWidget = null;
  }

  String _buildDocument() {
    // 按内容/颜色/正文样式命中复用已拼装的文档字符串。build 阶段被 WebView reload 路径
    // （didUpdateWidget 触发 _reload）会主动调用 buildDocument() 刷新
    // 缓存；普通 rebuild 命中后直接返回缓存，跳过 1-2KB 字符串拼装 +
    // RegExp 扫描 + healUnbalancedHtml。
    if (_documentCacheData == widget.data &&
        _documentCacheTextColor == widget.textColor &&
        _documentCacheBackgroundColor == widget.backgroundColor &&
        _documentCacheBaseTextStyle == widget.baseTextStyle &&
        _documentCache != null) {
      return _documentCache!;
    }
    final base = widget.baseTextStyle;
    final fontSize = (base?.fontSize ?? 14).toStringAsFixed(2);
    final lineHeight = (base?.height ?? 1.55).toStringAsFixed(2);
    final fontFamily = base?.fontFamily;
    final family = (fontFamily == null || fontFamily.isEmpty)
        ? '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, "PingFang SC", "Microsoft YaHei", sans-serif'
        : '"$fontFamily", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif';
    final textHex = _cssHexFromColor(widget.textColor);
    final bgHex = _cssHexFromColor(widget.backgroundColor);
    // 先做轻量自愈：补齐 AI 侧因 `max_tokens` 截断后未闭合的 `<div>` /
    // `<table>` 等，避免浏览器 parser 与 wfh fallback 路径把未闭合
    // 标签解释成 0 高度占位（用户视觉上就是"空消息卡 / 展开后空"）。
    final healed = _prepareStreamingHtml(widget.data);
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
          '$_viewportHeightResetCss'
          // 用独立的 oh-root 包裹负责提供"内容本身"的几何尺寸，
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
    _documentCacheBaseTextStyle = widget.baseTextStyle;
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

  Widget _stableInAppWebView() {
    final document = _buildDocument();
    final cached = _webViewWidget;
    if (cached != null && identical(_webViewWidgetDocument, document)) {
      return cached;
    }
    _webViewWidgetDocument = document;
    return _webViewWidget = iaw.InAppWebView(
      initialData: iaw.InAppWebViewInitialData(data: document),
      initialSettings: _webViewSettings,
      onWebViewCreated: _handleWebViewCreated,
      onLoadStop: (controller, _) => _installWebViewScripts(controller),
      onReceivedError: _handleWebViewError,
    );
  }

  void _handleWebViewCreated(iaw.InAppWebViewController controller) {
    _controller = controller;
    controller.addJavaScriptHandler(
      handlerName: 'OpenHandHeight',
      callback: (args) {
        if (args.isEmpty) return;
        final raw = args.first;
        final value = optionalDoubleFromValue(raw);
        if (value == null) return;
        _onContentSizeChanged(Size(0, value));
      },
    );
  }

  Future<void> _installWebViewScripts(
    iaw.InAppWebViewController controller,
  ) async {
    try {
      await controller.evaluateJavascript(source: _heightObserverScript);
      await controller.evaluateJavascript(source: _selectionBridgeScript);
    } catch (error, stack) {
      silentLog('home_message_content', '安装 HTML 气泡高度观察器失败', error, stack);
    } finally {
      _reportBootstrapReady();
    }
  }

  void _handleWebViewError(
    iaw.InAppWebViewController controller,
    iaw.WebResourceRequest request,
    iaw.WebResourceError error,
  ) {
    _reportBootstrapReady();
    widget.onFallback();
    silentLog('home_message_content', 'HTML 气泡 WebView 错误', error);
    if (mounted) {
      _safeSetState(() => _hasError = true);
    }
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
    final cachedHeight = _readBoundedHeightCache(_heightCache, _heightCacheKey);
    final floor = _readBoundedHeightCache(_heightFloorCache, _heightCacheKey);
    final revealedHeight = _readBoundedHeightCache(
      _revealedHeightCache,
      _heightCacheKey,
    );
    // 仅在"完全没有任何高度/揭示记录可参考"时显示 shimmer 骨架屏。
    // 一旦用户看见过该 HTML 内容，State 重建也直接展示 WebView，
    // 后续由 JS 测高修正尺寸，不再回退到二次骨架屏。
    final showShimmer =
        _height == null && cachedHeight == null && revealedHeight == null;
    final estimatedHeight = _estimateHeight();
    // 跨 State 单调 floor——State dispose 时把真实高度写入
    // `_heightFloorCache`，新 State 重建后若 _height 丢失则用 floor
    // 兜底，防止 Stack 高度收缩到 estimatedHeight 导致 maxScrollExtent
    // 抖动。floor 与 cache 分离，outlier 占位估计绝不写入，避免污染。
    final baseDisplayHeight =
        _height ?? cachedHeight ?? floor ?? revealedHeight ?? estimatedHeight;
    final displayHeight =
        _heightUpdatesFrozen && floor != null && baseDisplayHeight < floor
        ? floor
        : baseDisplayHeight;

    // WebView 必须始终在 widget 树中——它加载 HTML 并通过 JS 回调报告高度。
    // 改用 Stack 叠加（shimmer 在 WebView 之上），让 shimmer
    // 阶段与 WebView 阶段占父级空间完全一致（仅 WebView 撑起 Stack
    // 高度 = displayHeight），消除旧 Column 模式 shimmer 阶段
    // `displayHeight + 1.0` 与 WebView 阶段 `displayHeight` 之间的
    // 1px 跳变——该跳变在用户处于"距 maxScrollExtent 较近"位置时
    // 触发 Flutter clamp 滚动位置，表现为"强制往下滚动"的偶发
    // UI 异常。Stack 模式从根上消除该高度差。
    final webViewChild = RepaintBoundary(
      // WebView 高度回调 → setState → RepaintBoundary 隔离
      // 之后只重绘 WebView 自身的 layer，不再让外层消息卡（外层有阴影 /
      // border / AnimatedSize / ActionButtons 等复杂 layout）跟着整张重
      // 绘。长会话滚动期间 8-15 个 HTML 气泡同时有 WebView 在跑 ResizeObserver，
      // 一次 setState 就会拖累整页 paint，RepaintBoundary 阻断这层
      // repaint 蔓延。
      child: KeyedSubtree(key: _webViewRegionKey, child: _stableInAppWebView()),
    );

    final content = Stack(
      children: [
        // Container(color: widget.backgroundColor) 作为
        // macOS WKWebView 默认白底的 fallback——HTML 加载完成前避免
        // 闪一下白屏与气泡底色形成强烈对比。其他平台
        // transparentBackground: true 时同样受益，HTML 没设背景时
        // 容器色自然透出与气泡衔接。
        // loading 阶段 WebView 保持挂载并正常测高；骨架屏用不透明底色
        // 覆盖在上方，避免对平台视图做 Opacity/fade/scale 合成导致滚动闪烁。
        Container(
          color: widget.backgroundColor,
          child: SizedBox(
            width: double.infinity,
            height: displayHeight,
            child: webViewChild,
          ),
        ),
        // 用 Stack 叠加替代 Column 堆叠——shimmer 永远
        // 覆盖在 WebView 之上，**两个阶段 Column/Stretch 占的父级空间
        // 始终一致**（仅 WebView 撑起 Stack 高度 = displayHeight）。
        // 旧 Column 模式 shimmer 阶段 = `displayHeight + 1.0`（shimmer
        // + 1px WebView）、WebView 阶段 = `displayHeight`，切换瞬间存在
        // 1px 高度跳变 → 在用户处于"距 maxScrollExtent 较近"的位置时
        // 触发 Flutter clamp 滚动位置，表现为"强制往下滚动一段距离"
        // 的偶发性 UI 异常。Stack 模式从根上消除该高度差。
        if (showShimmer)
          Positioned.fill(child: ColoredBox(color: widget.backgroundColor)),
        if (showShimmer) const Positioned.fill(child: _HtmlBubbleShimmer()),
      ],
    );
    return content;
  }
}

class _ProgressiveHtmlMessageBody extends StatefulWidget {
  const _ProgressiveHtmlMessageBody({
    required this.prepared,
    required this.textColor,
    required this.backgroundColor,
    required this.baseTextStyle,
    required this.previewMaxHeight,
    this.collapsedOverride,
    this.onCollapsedChanged,
    this.animateSize = true,
    this.scrollStateKey,
  });

  final _PreparedHtmlRenderData prepared;
  final Color textColor;
  final Color backgroundColor;
  final TextStyle? baseTextStyle;
  final double previewMaxHeight;
  final bool? collapsedOverride;
  final ValueChanged<bool>? onCollapsedChanged;
  final bool animateSize;
  final String? scrollStateKey;

  @override
  State<_ProgressiveHtmlMessageBody> createState() =>
      _ProgressiveHtmlMessageBodyState();
}

class _ProgressiveHtmlMessageBodyState
    extends State<_ProgressiveHtmlMessageBody> {
  late bool _collapsed = widget.prepared.shouldUseProgressiveHighFidelity;

  bool get _effectiveCollapsed => widget.collapsedOverride ?? _collapsed;

  String get _scrollStateKey =>
      widget.scrollStateKey ??
      'html-progressive|${widget.prepared.sourceLength}|${widget.prepared.sourceFingerprint}';

  @override
  void didUpdateWidget(covariant _ProgressiveHtmlMessageBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collapsedOverride == false &&
        widget.collapsedOverride == true) {
      _CollapsedBodyScrollOffsetCache.reset(_scrollStateKey);
    }
    final contentChanged =
        oldWidget.prepared.sourceLength != widget.prepared.sourceLength ||
        oldWidget.prepared.sourceFingerprint !=
            widget.prepared.sourceFingerprint;
    if (!contentChanged) {
      return;
    }
    _CollapsedBodyScrollOffsetCache.reset(_scrollStateKey);
    _collapsed = widget.prepared.shouldUseProgressiveHighFidelity;
  }

  void _setCollapsed(bool value) {
    if (value) {
      _CollapsedBodyScrollOffsetCache.reset(_scrollStateKey);
    }
    if (widget.collapsedOverride != null) {
      widget.onCollapsedChanged?.call(value);
      return;
    }
    setState(() => _collapsed = value);
    widget.onCollapsedChanged?.call(value);
  }

  Widget _buildHtmlBody() {
    return SizedBox(
      width: double.infinity,
      child: _DeferredHtmlBubbleWebView(
        key: ValueKey<Object>(
          Object.hash(
            widget.prepared.sourceLength,
            widget.prepared.sourceFingerprint,
            widget.textColor,
          ),
        ),
        data: widget.prepared.healedHtml,
        textColor: widget.textColor,
        backgroundColor: widget.backgroundColor,
        baseTextStyle: widget.baseTextStyle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shouldProgressive = widget.prepared.shouldUseProgressiveHighFidelity;
    if (!shouldProgressive) {
      return _buildHtmlBody();
    }

    final previewText = widget.prepared.previewText.isEmpty
        ? widget.prepared.healedHtml
        : widget.prepared.previewText;
    final collapsed = _effectiveCollapsed;
    final previewStyle =
        widget.baseTextStyle?.copyWith(color: widget.textColor) ??
        TextStyle(color: widget.textColor, height: 1.55);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MessageCollapseToggleCapsule(
          collapsed: collapsed,
          characterCount: widget.prepared.sourceLength,
          color: widget.textColor,
          onTap: () {
            _BubbleHtmlInteractiveScope.maybeOf(context)?.markInteractiveTap();
            _setCollapsed(!collapsed);
          },
        ),
        kOpenHandGap8,
        _collapsibleMessageBodyMotion(
          context: context,
          collapsed: collapsed,
          animate: widget.animateSize,
          child: collapsed
              ? KeyedSubtree(
                  key: const ValueKey<String>('html-progressive-preview'),
                  child: _PlainTextPreviewBody(
                    data: previewText,
                    maxHeight: math.min(
                      widget.previewMaxHeight,
                      _htmlProgressiveRenderPreviewMaxHeight,
                    ),
                    textColor: widget.textColor,
                    fadeColor: widget.backgroundColor,
                    style: previewStyle,
                    scrollStateKey: '$_scrollStateKey|preview',
                  ),
                )
              : KeyedSubtree(
                  key: const ValueKey<String>('html-progressive-full'),
                  child: _buildHtmlBody(),
                ),
        ),
      ],
    );
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
    this.collapsedOverride,
    this.onCollapsedChanged,
    this.showCollapseToggle = true,
    this.contentMotionKey,
    this.forceMotionWhenScrolling = false,
    this.scrollStateKey,
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
  final bool? collapsedOverride;
  final ValueChanged<bool>? onCollapsedChanged;
  final bool showCollapseToggle;
  final Object? contentMotionKey;
  final bool forceMotionWhenScrolling;
  final String? scrollStateKey;

  Widget _wrapSelection(Widget child) {
    if (!wrapInSelectionArea) return child;
    // 先合并成一个稳定的选择节点，再交给 SelectionArea 处理手势。
    // Markdown、纯文本和 HTML 在更新期间都会替换内部 SelectableText；
    // 直接把多个节点暴露给 Flutter 的根选择代理，清除选区时容易和
    // ListView 的可见节点刷新同时发生并触发 ConcurrentModificationError。
    return SelectionArea(child: _MarkdownSelectionContainer(child: child));
  }

  Widget _buildMarkdownOrFallback() {
    // 流式阶段不走 prepared 管线：对半成品缓冲做完整嗅探每个 delta 都会
    // 缓存 miss 并全量重算（O(N²) 累积），还会把中间版本挤进 prepared LRU
    // 污染真正需要的条目。轻量粘滞嗅探保住可见行为：整体像 HTML 文档的
    // 内容显示骨架占位（与 html 格式流式一致）而非原始标签文本，流结束
    // 后由稳定实例做一次性完整嗅探并落到 HTML 卡。
    if (isStreaming) {
      if (_streamingMarkdownLooksLikeHtml(data, scrollStateKey)) {
        return _StreamingHtmlPlaceholder(
          textColor: textColor,
          contentLength: data.length,
        );
      }
      return _buildMarkdown();
    }
    // Markdown 格式智能回退：仅当内容整体看起来像 HTML 文档时，才优先尝试
    // HTML 渲染。若消息里已经出现 fenced code block，则必须坚持走 Markdown
    // 路径 —— 代码块正文可能合法包含 `<br/>` / `<div>` / `<table>` 等字样
    //（典型如 mermaid、HTML 示例代码），此时回退到 WebView 会把整个 fenced
    // block 当普通文本吃掉，导致代码块/mermaid 完全失效。
    // fence 判定与 HTML 嗅探结果都随 prepared 数据按内容缓存，build 路径
    // 不再重复对全文跑正则。
    final preparedHtml = _preparedHtmlRenderDataFor(data);
    if (preparedHtml.hasMarkdownFence) {
      return _buildMarkdown();
    }

    if (preparedHtml.isHtmlCandidate) {
      return _ProgressiveHtmlMessageBody(
        prepared: preparedHtml,
        textColor: textColor,
        backgroundColor: backgroundColor,
        baseTextStyle: markdownStyleSheet.p,
        previewMaxHeight: previewMaxHeight,
        collapsedOverride: collapsedOverride,
        onCollapsedChanged: onCollapsedChanged,
        animateSize: collapsedOverride == null,
        scrollStateKey: scrollStateKey == null ? null : '$scrollStateKey|html',
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
      collapsedOverride: collapsedOverride,
      onCollapsedChanged: onCollapsedChanged,
      showCollapseToggle: showCollapseToggle,
      animateSize: collapsedOverride == null,
      scrollStateKey: scrollStateKey == null
          ? null
          : '$scrollStateKey|markdown',
    );
  }

  Widget _buildPlainText() {
    return _PlainTextMessageBody(
      data: data.isEmpty ? ' ' : data,
      textColor: textColor,
      backgroundColor: backgroundColor,
      previewMaxHeight: previewMaxHeight,
      style: markdownStyleSheet.p,
      collapsedOverride: collapsedOverride,
      onCollapsedChanged: onCollapsedChanged,
      showCollapseToggle: showCollapseToggle,
      animateSize: collapsedOverride == null,
      scrollStateKey: scrollStateKey == null ? null : '$scrollStateKey|plain',
    );
  }

  Widget _buildHtmlOrFallback() {
    // 优先尝试 HTML 渲染：
    // 1. 首先用 `_looksLikeHtml` 检查是否包含常见 HTML 标签（白名单）；
    // 2. 如果不在白名单但内容含有「<标签名>」形式的结构（宽松启发式），
    //    也尝试 HTML 渲染——这能捕获 AI 输出中 `<del>` / `<kbd>` 等白名单外
    //    的有效标签，避免它们被误判为纯文本而显示原生标签字符。
    // 3. HTML 渲染失败时再走 `htmlFallback` 降级链：markdown → plainText。
    // WebView 内置 HTML 解析器对未闭合标签有原生容错，且 `_HtmlBubbleWebView
    // ._buildDocument` 会先走 `_healUnbalancedHtml` 轻量自愈，进一步降低
    // layout 阶段崩溃的概率；旧版本走 markdown fallback 时，未闭合的
    // `<table>` 经常渲染成 0 高度占位 → 用户看到的就是「空白卡片 / 展开后空」。
    final preparedHtml = _preparedHtmlRenderDataFor(data);

    if (preparedHtml.isHtmlCandidate) {
      return _ProgressiveHtmlMessageBody(
        prepared: preparedHtml,
        textColor: textColor,
        backgroundColor: backgroundColor,
        baseTextStyle: markdownStyleSheet.p,
        previewMaxHeight: previewMaxHeight,
        collapsedOverride: collapsedOverride,
        onCollapsedChanged: onCollapsedChanged,
        animateSize: collapsedOverride == null,
        scrollStateKey: scrollStateKey == null ? null : '$scrollStateKey|html',
      );
    }
    // 不像 HTML 时走 fallback 降级链。
    return htmlFallback == AiHtmlRenderFallback.plainText
        ? _buildPlainText()
        : _buildMarkdown();
  }

  bool _buildsPlatformHtmlBody() {
    if (isStreaming || data.isEmpty) {
      return false;
    }
    // 空白内容不可能是 HTML 候选（looksLikeHtml / tagStructure 均为 false），
    // 无需先 trim 复制一份再判空。
    return switch (format) {
      AiMessageContentFormat.plainText => false,
      AiMessageContentFormat.html => _preparedHtmlRenderDataFor(
        data,
      ).isHtmlCandidate,
      AiMessageContentFormat.markdown => () {
        final prepared = _preparedHtmlRenderDataFor(data);
        return !prepared.hasMarkdownFence && prepared.isHtmlCandidate;
      }(),
    };
  }

  /// 把内部渲染产物按"是否处于流式阶段"做一次性模式切换：
  /// - 流式中且格式为 HTML → 骨架屏占位；
  /// - 流式结束 → 真正的格式分支（带智能回退）。
  /// 非平台视图路径由外层 AnimatedSwitcher 负责 body 级别的 fade+scale
  /// 落位；平台 HTML WebView 在 build() 中直接返回，避免滚动时被
  /// Opacity/Scale/SelectionArea 等合成层触发闪烁或 DOM 状态重置。
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
    if (_buildsPlatformHtmlBody()) {
      return KeyedSubtree(
        key: ValueKey<Object>(
          Object.hash(format.storageKey, wrapInSelectionArea, contentMotionKey),
        ),
        child: _buildDispatchedBody(),
      );
    }

    final transcriptScrolling = _isTranscriptScrollActive(context);
    final shouldAnimateBodySwitch = isStreaming || contentMotionKey != null;
    final motionEnabled =
        shouldAnimateBodySwitch &&
        openHandTickerMotionEnabled(context) &&
        (!transcriptScrolling || forceMotionWhenScrolling);
    final motionDuration = motionEnabled
        ? cardMotionDurationFor(context, expanding: !isStreaming)
        : Duration.zero;
    final body = AnimatedSwitcher(
      duration: motionDuration,
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
        final fade = openHandBoundedCurveAnimation(
          parent: animation,
          curve: kOpenHandSwitchInCurve,
          reverseCurve: kOpenHandSwitchOutCurve,
        );
        final scale = Tween<double>(begin: 0.985, end: 1.0).animate(
          openHandCurveAnimation(
            parent: animation,
            curve: kCardMotionCurve,
            reverseCurve: kOpenHandSwitchOutCurve,
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
        key: ValueKey<Object>(
          Object.hash(
            format.storageKey,
            isStreaming,
            wrapInSelectionArea,
            contentMotionKey,
          ),
        ),
        child: _buildDispatchedBody(),
      ),
    );
    return _wrapSelection(
      maybeAnimatedSize(
        duration: collapsedOverride == null ? motionDuration : Duration.zero,
        curve: kCardMotionCurve,
        alignment: Alignment.topLeft,
        child: body,
      ),
    );
  }
}

String _homeMessageConCharsLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: ' 字符', en: ' chars');
}
