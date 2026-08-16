part of 'harness_session_dashboard.dart';

class _HeReviewVerdictInfo {
  const _HeReviewVerdictInfo({required this.isPass, required this.comment});
  final bool isPass;
  final String comment;
}

/// 从用户输入片段中解析 PASS/FAIL 结论。
_HeReviewVerdictInfo? _parseReviewVerdict(_HeOutputSegment seg) {
  if (seg.kind != _HeSegmentKind.userInput) return null;
  final lines = seg.lines;
  if (lines.isEmpty) return null;

  // 仅首个非空行可作为结论。
  bool? isPass;
  int verdictLineIndex = -1;
  for (var i = 0; i < lines.length; i++) {
    final trimmed = lines[i].trim();
    if (trimmed.isEmpty) continue;
    if (trimmed == 'PASS') {
      isPass = true;
      verdictLineIndex = i;
      break;
    }
    if (trimmed == 'FAIL') {
      isPass = false;
      verdictLineIndex = i;
      break;
    }
    break;
  }
  if (isPass == null) return null;

  final commentLines = <String>[];
  for (var i = verdictLineIndex + 1; i < lines.length; i++) {
    commentLines.add(lines[i]);
  }
  final comment = commentLines.join('\n').trim();
  return _HeReviewVerdictInfo(isPass: isPass, comment: comment);
}

class _HeReviewVerdictCard extends StatelessWidget {
  const _HeReviewVerdictCard({
    required this.isPass,
    required this.comment,
    required this.roleLabel,
    required this.theme,
    required this.colorScheme,
  });

  final bool isPass;
  final String comment;
  final String roleLabel;
  final ThemeData theme;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    final verdictColor = isPass ? _heCompletedTone : _heFailedTone;
    final bgAlpha = isDark ? 0.22 : 0.10;
    final borderAlpha = isDark ? 0.45 : 0.32;

    return Container(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          verdictColor.withValues(alpha: bgAlpha),
          colorScheme.surface,
        ),
        borderRadius: kOpenHandBorderRadius18,
        border: Border.all(
          color: verdictColor.withValues(alpha: borderAlpha),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: isDark ? 0.06 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header with role label ──────────────────────────────
            Row(
              children: [
                Icon(
                  Icons.person_rounded,
                  size: 14,
                  color: colorScheme.onSurface.withValues(alpha: 0.60),
                ),
                kOpenHandHGap6,
                Text(
                  roleLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.60),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            kOpenHandGap12,
            // ── Verdict banner ──────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: verdictColor.withValues(alpha: isDark ? 0.20 : 0.12),
                borderRadius: _br12,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isPass ? Icons.check_circle_rounded : Icons.cancel_rounded,
                    size: 22,
                    color: verdictColor,
                  ),
                  kOpenHandHGap10,
                  Text(
                    isPass
                        ? openHandLocalizedText(
                            context,
                            zh: '验收通过',
                            en: 'Review Passed',
                            zhHant: '驗收通過',
                            fr: 'Revue réussie',
                            de: 'Prüfung bestanden',
                            ja: 'レビュー合格',
                          )
                        : openHandLocalizedText(
                            context,
                            zh: '验收未通过',
                            en: 'Review Failed',
                            zhHant: '驗收未通過',
                            fr: 'Revue échouée',
                            de: 'Prüfung fehlgeschlagen',
                            ja: 'レビュー不合格',
                          ),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: verdictColor,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
            // ── Comment body ────────────────────────────────────────
            if (comment.isNotEmpty) ...[
              kOpenHandGap12,
              Text(
                comment,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.85),
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// _HeSegmentBody — renders markdown content within a segment card
class _HeSegmentBody extends StatelessWidget {
  const _HeSegmentBody({
    required this.content,
    required this.expanded,
    required this.theme,
    required this.colorScheme,
    required this.textColor,
    required this.onExpand,
    this.filePathRoots = const [],
    this.cardBackground,
  });

  final String content;
  final bool expanded;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final Color textColor;
  final VoidCallback onExpand;
  final List<String> filePathRoots;
  final Color? cardBackground;

  static const int _previewChars = 500;

  String get _displayContent {
    if (expanded) return content;
    final cut = content.lastIndexOf(RegExp(r'\s'), _previewChars);
    final end = cut > 0 ? cut : _previewChars;
    return clipTextByCodeUnits(content, end, suffix: '…');
  }

  @override
  Widget build(BuildContext context) {
    final displayContent = _displayContent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_heShouldRenderSegmentAsLogLines(displayContent))
          _HeStructuredLogLines(
            lines: const LineSplitter().convert(displayContent),
            colorScheme: colorScheme,
          )
        else
          _HeSafeMarkdownBody(
            content: displayContent,
            theme: theme,
            colorScheme: colorScheme,
            filePathRoots: filePathRoots,
            textColor: textColor,
            cardBackground: cardBackground,
          ),
        if (!expanded) ...[
          kOpenHandGap4,
          OpenHandTapRegion(
            onTap: onExpand,
            child: Builder(
              builder: (context) {
                final onDark =
                    cardBackground != null &&
                    ThemeData.estimateBrightnessForColor(cardBackground!) ==
                        Brightness.dark;
                final expandBg = onDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : colorScheme.surfaceContainerHighest;
                final expandFg = onDark
                    ? Colors.white.withValues(alpha: 0.88)
                    : colorScheme.primary;
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: expandBg,
                    borderRadius: kOpenHandBorderRadius16,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.expand_more_rounded,
                        size: 14,
                        color: expandFg,
                      ),
                      kOpenHandHGap4,
                      Text(
                        openHandLocalizedText(
                          context,
                          zh: '展开全部',
                          en: 'Show full content',
                          zhHant: '展開全部',
                          fr: 'Afficher tout le contenu',
                          de: 'Vollständigen Inhalt anzeigen',
                          ja: '全文を表示',
                        ),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: expandFg,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _HeThinkingSegmentBody extends StatelessWidget {
  const _HeThinkingSegmentBody({
    required this.content,
    required this.expanded,
    required this.isStreaming,
    required this.theme,
    required this.colorScheme,
    required this.textColor,
    required this.cardBackground,
    this.filePathRoots = const [],
  });

  final String content;
  final bool expanded;
  final bool isStreaming;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final Color textColor;
  final Color cardBackground;
  final List<String> filePathRoots;

  static const double _previewHeight = 142;

  @override
  Widget build(BuildContext context) {
    final effectiveContent = content.isEmpty ? ' ' : content;
    final parseKey = [
      effectiveContent.hashCode,
      filePathRoots.join('\u0000').hashCode,
    ].join('|');

    if (isStreaming) {
      return _HeStreamingThinkingBody(
        content: effectiveContent,
        expanded: expanded,
        theme: theme,
        colorScheme: colorScheme,
        textColor: textColor,
        cardBackground: cardBackground,
        filePathRoots: filePathRoots,
        parseKey: parseKey,
      );
    }

    return ClipRect(
      child: AnimatedSize(
        duration: openHandMotionDuration(context, kOpenHandMotion220),
        curve: kOpenHandEmphasizedTransitionCurve,
        alignment: Alignment.topLeft,
        child: expanded
            ? KeyedSubtree(
                key: const ValueKey<String>('he-thinking-expanded'),
                child: _HeSafeMarkdownBody(
                  content: effectiveContent,
                  theme: theme,
                  colorScheme: colorScheme,
                  filePathRoots: filePathRoots,
                  textColor: textColor,
                  cardBackground: cardBackground,
                ),
              )
            : KeyedSubtree(
                key: const ValueKey<String>('he-thinking-preview'),
                child: _HeMarkdownPreviewBody(
                  content: effectiveContent,
                  maxHeight: _previewHeight,
                  theme: theme,
                  colorScheme: colorScheme,
                  textColor: textColor,
                  cardBackground: cardBackground,
                  filePathRoots: filePathRoots,
                  parseKey: '$parseKey|preview',
                ),
              ),
      ),
    );
  }
}

class _HeStreamingThinkingBody extends StatelessWidget {
  const _HeStreamingThinkingBody({
    required this.content,
    required this.expanded,
    required this.theme,
    required this.colorScheme,
    required this.textColor,
    required this.cardBackground,
    required this.filePathRoots,
    required this.parseKey,
  });

  final String content;
  final bool expanded;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final Color textColor;
  final Color cardBackground;
  final List<String> filePathRoots;
  final String parseKey;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedSize(
        duration: openHandMotionDuration(context, kOpenHandMotion180),
        curve: kOpenHandSwitchInCurve,
        alignment: Alignment.topLeft,
        child: expanded
            ? KeyedSubtree(
                key: const ValueKey<String>('he-thinking-streaming-expanded'),
                child: _HeSafeMarkdownBody(
                  content: content,
                  theme: theme,
                  colorScheme: colorScheme,
                  filePathRoots: filePathRoots,
                  textColor: textColor,
                  cardBackground: cardBackground,
                ),
              )
            : KeyedSubtree(
                key: const ValueKey<String>('he-thinking-streaming-preview'),
                child: _HeMarkdownPreviewBody(
                  content: content,
                  maxHeight: _HeThinkingSegmentBody._previewHeight,
                  theme: theme,
                  colorScheme: colorScheme,
                  textColor: textColor,
                  cardBackground: cardBackground,
                  filePathRoots: filePathRoots,
                  parseKey: '$parseKey|streaming-preview',
                ),
              ),
      ),
    );
  }
}

class _HeMarkdownPreviewBody extends StatefulWidget {
  const _HeMarkdownPreviewBody({
    required this.content,
    required this.maxHeight,
    required this.theme,
    required this.colorScheme,
    required this.textColor,
    required this.cardBackground,
    required this.filePathRoots,
    required this.parseKey,
  });

  final String content;
  final double maxHeight;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final Color textColor;
  final Color cardBackground;
  final List<String> filePathRoots;
  final String parseKey;

  @override
  State<_HeMarkdownPreviewBody> createState() => _HeMarkdownPreviewBodyState();
}

class _HeMarkdownPreviewBodyState extends State<_HeMarkdownPreviewBody> {
  double? _contentHeight;

  @override
  void didUpdateWidget(covariant _HeMarkdownPreviewBody oldWidget) {
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
        : (measuredHeight < widget.maxHeight
              ? measuredHeight
              : widget.maxHeight);
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
                    child: _HeMeasureSize(
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
                        // Defer the height-driven setState to the next frame
                        // so a single layout pass that emits multiple
                        // intermediate sizes (common with streaming
                        // markdown) collapses into one rebuild instead of
                        // many.
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          if (_contentHeight == nextHeight) return;
                          setState(() {
                            _contentHeight = nextHeight;
                          });
                        });
                      },
                      child: IgnorePointer(
                        child: _HeSafeMarkdownBody(
                          content: widget.content,
                          theme: widget.theme,
                          colorScheme: widget.colorScheme,
                          filePathRoots: widget.filePathRoots,
                          textColor: widget.textColor,
                          cardBackground: widget.cardBackground,
                        ),
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
                            widget.cardBackground.withValues(alpha: 0),
                            widget.cardBackground.withValues(alpha: 0.96),
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

class _HeMeasureSize extends SingleChildRenderObjectWidget {
  const _HeMeasureSize({required this.onChange, required super.child});

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _HeRenderMeasureSize(onChange);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _HeRenderMeasureSize renderObject,
  ) {
    renderObject.onChange = onChange;
  }
}

class _HeRenderMeasureSize extends RenderProxyBox {
  _HeRenderMeasureSize(this.onChange);

  ValueChanged<Size> onChange;
  Size? _oldSize;

  @override
  void performLayout() {
    super.performLayout();
    final newSize = child?.size;
    if (_oldSize == newSize || newSize == null) {
      return;
    }
    _oldSize = newSize;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(newSize));
  }
}

// ── Command strip ─────────────────────────────────────────────────────────

class _HeCommandStrip extends StatefulWidget {
  const _HeCommandStrip({required this.command});
  final String command;

  @override
  State<_HeCommandStrip> createState() => _HeCommandStripState();
}

class _HeCommandStripState extends State<_HeCommandStrip>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _ctrl;
  late final Animation<double> _turn;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: kOpenHandMotion220);
    _turn = Tween<double>(
      begin: 0,
      end: 0.5,
    ).animate(CurvedAnimation(parent: _ctrl, curve: kOpenHandSwitchInCurve));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return OpenHandTapRegion(
      onTap: _toggle,
      child: AnimatedContainer(
        duration: openHandMotionDuration(context, kOpenHandMotion220),
        curve: kOpenHandSwitchInCurve,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: kOpenHandBorderRadius16,
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.30),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.terminal_rounded, size: 14, color: colorScheme.primary),
            kOpenHandHGap8,
            Expanded(
              child: AnimatedCrossFade(
                duration: openHandMotionDuration(context, kOpenHandMotion220),
                firstCurve: kOpenHandSwitchInCurve,
                secondCurve: kOpenHandSwitchInCurve,
                crossFadeState: _expanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: Text(
                  widget.command,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    fontSize: 11.5,
                    color: colorScheme.onSurface.withValues(alpha: 0.68),
                  ),
                ),
                secondChild: SelectableText(
                  widget.command,
                  style: TextStyle(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    fontSize: 11.5,
                    color: colorScheme.onSurface.withValues(alpha: 0.68),
                  ),
                ),
              ),
            ),
            kOpenHandHGap6,
            RotationTransition(
              turns: _turn,
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Markdown content with collapse/expand ─────────────────────────────────
