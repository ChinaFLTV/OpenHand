part of 'openhand_home_page.dart';

const int _messageMarkdownCollapseCharThreshold = 5000;
const int _toolResultMarkdownCollapseCharThreshold = 1200;
const int _messageMarkdownCollapseLineThreshold = 90;

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
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
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
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOutCubic,
                  alignment: Alignment.topLeft,
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
    return ClipRect(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOutCubic,
        alignment: Alignment.topLeft,
        child: expanded
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
                  maxHeight: 142,
                  styleSheet: styleSheet,
                  builders: builders,
                  inlineSyntaxes: inlineSyntaxes,
                  pathRoots: pathRoots,
                  parseKey: '$parseKey|reasoning-preview',
                  fadeColor: fadeColor,
                ),
              ),
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
    return ClipRect(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topLeft,
        child: expanded
            ? KeyedSubtree(
                key: const ValueKey<String>(
                  'streaming-reasoning-markdown-expanded',
                ),
                child: _SafeMarkdownBody(
                  data: effectiveContent,
                  selectable: selectable,
                  builders: builders,
                  styleSheet: styleSheet,
                  inlineSyntaxes: inlineSyntaxes,
                  pathRoots: pathRoots,
                  parseKey: '$parseKey|streaming-markdown',
                ),
              )
            : KeyedSubtree(
                key: const ValueKey<String>(
                  'streaming-reasoning-markdown-preview',
                ),
                child: _MarkdownPreviewBody(
                  data: effectiveContent,
                  maxHeight: 142,
                  styleSheet: styleSheet,
                  builders: builders,
                  inlineSyntaxes: inlineSyntaxes,
                  pathRoots: pathRoots,
                  parseKey: '$parseKey|streaming-markdown-preview',
                  fadeColor: fadeColor,
                ),
              ),
      ),
    );
  }
}

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
    final detail = _localizedText(
      context,
      zh: '${data.length} 字符',
      en: '${data.length} chars',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: _borderRadius18,
            onTap: () {
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
                  Expanded(
                    child: Text(
                      '$label · $detail',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        ClipRect(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topLeft,
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
  // Hard cap on the character count that is actually handed to the
  // markdown parser for the collapsed preview. The preview only ever shows
  // `maxHeight` (≈142px) of content, but the underlying `_SafeMarkdownBody`
  // is laid out in an unconstrained-height `OverflowBox` so it can be
  // measured for the fade decision.  For long streaming reasoning blocks
  // (e.g. several KB), parsing + laying out the entire content on every
  // tick of the stream was the dominant UI-thread cost (observed 2.7s
  // build frames during streaming). Since we only need the top `maxHeight`
  // worth of rendered text, trimming to a modest character budget makes
  // the parse/layout O(constant) without changing visible output (the
  // truncated prefix still far exceeds `maxHeight`, so the fade still
  // triggers correctly).
  static const int _previewCharCap = 2000;

  double? _contentHeight;

  String get _effectiveData {
    final data = widget.data;
    if (data.length <= _previewCharCap) {
      return data;
    }
    return data.substring(0, _previewCharCap);
  }

  @override
  void didUpdateWidget(covariant _MarkdownPreviewBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.parseKey != widget.parseKey) {
      _contentHeight = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final measuredHeight = _contentHeight;
    final effectiveHeight = measuredHeight == null
        ? widget.maxHeight
        : math.min(measuredHeight, widget.maxHeight);
    final showFade =
        measuredHeight != null && measuredHeight > widget.maxHeight + 0.5;
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
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: constrainedWidth,
                    maxWidth: constrainedWidth,
                    minHeight: 0,
                    maxHeight: double.infinity,
                    child: _MeasureSize(
                      onChange: (size) {
                        if (!mounted) {
                          return;
                        }
                        final nextHeight = size.height;
                        final currentHeight = _contentHeight;
                        if (currentHeight != null &&
                            (currentHeight - nextHeight).abs() < 0.5) {
                          return;
                        }
                        setState(() {
                          _contentHeight = nextHeight;
                        });
                      },
                      // 2026-04-27: 不再用 IgnorePointer 包裹预览体，让代码块
                      // 内部的复制 / 下载 / 运行按钮在折叠状态也能响应点击。
                      // 外层的展开按钮位于同一个 Column 中的独立 InkWell，
                      // 互不干扰；渐变 fade 遮罩依然保留 IgnorePointer 以免拦截点击。
                      child: _SafeMarkdownBody(
                        data: _effectiveData,
                        // 2026-04-27: 折叠预览体也启用 selectable，让用户在折叠
                        // 状态下也能选中并复制可见文本，与展开态保持一致。
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
              if (showFade)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Container(
                      height: 26,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            widget.fadeColor.withValues(alpha: 0),
                            widget.fadeColor.withValues(alpha: 0.96),
                          ],
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
  factory _MessageMarkdownThemeData.fromMessageBubble({
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
        codeblockPadding: EdgeInsets.zero,
        codeblockDecoration: const BoxDecoration(),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: borderColor, width: 1.2)),
        ),
      ),
    );
  }
  const _MessageMarkdownThemeData({required this.styleSheet});

  final MarkdownStyleSheet styleSheet;
}

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
// the next frame. Smaller bodies (<= 2 KB) parse synchronously since the
// cost is negligible and the swap would otherwise produce a visible flicker.
const int _markdownDeferredParseThresholdChars = 2 * 1024;

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
  /// stand-in immediately and queue the real parse via
  /// `addPostFrameCallback`. This unblocks the frame that mounts a freshly
  /// opened transcript, which may contain a dozen+ such bubbles all
  /// competing for parse time. Subsequent updates parse synchronously to
  /// avoid mid-conversation flicker.
  void _parseMarkdownMaybeDeferred({required bool initial}) {
    if (initial &&
        widget.data.length > _markdownDeferredParseThresholdChars &&
        widget.data.length <= _markdownPlainTextSkipThresholdChars &&
        !_canRenderMarkdownAsPlainText(widget.data)) {
      _renderPlainTextPlaceholder();
      if (!_deferredParseScheduled) {
        _deferredParseScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
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
      final document = md.Document(
        extensionSet: md.ExtensionSet.gitHubFlavored,
        inlineSyntaxes: widget.inlineSyntaxes,
        encodeHtml: false,
      );
      final astNodes = document.parseLines(
        const LineSplitter().convert(normalizedSource),
      );
      _sanitizeMarkdownAst(astNodes);
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
    final stripped = _stripToolScaffolding(normalized);
    return _closeUnterminatedFencedCodeBlock(stripped).replaceAllMapped(
      _setextEscapePattern,
      (match) => '${match[1]}${match[2]}\\${match[3]}',
    );
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
      final previewTitle = label.isEmpty ? uri.toString() : label;
      return _wrapMarkdownImageTap(
        semanticsLabel: previewTitle,
        onTap: () {
          if (!mounted) {
            return;
          }
          showAnimatedDialog<void>(
            context: context,
            builder: (ctx) =>
                _ImagePreviewDialog.network(imageUri: uri, title: previewTitle),
          );
        },
        child: _buildMarkdownImageFrame(
          context,
          Image.network(
            uri.toString(),
            fit: BoxFit.contain,
            // Same constraint as the file variant; full image opens via
            // the preview dialog.
            cacheWidth: 1280,
            frameBuilder: _fadeInImageFrameBuilder,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) {
                return child;
              }
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
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: child,
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
        unawaited(_openResolvedMessagePath(context, resolvedPath));
      };
      return recognizer;
    }
    final externalUri = parseSupportedMessageLinkUri(href);
    if (externalUri != null) {
      recognizer.onTap = () {
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
    if (children.length == 1) {
      return children.single;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
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
