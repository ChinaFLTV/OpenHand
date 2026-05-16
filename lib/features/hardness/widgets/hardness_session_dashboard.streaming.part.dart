part of 'hardness_session_dashboard.dart';

class _HeStreamingSubConversation extends StatefulWidget {
  const _HeStreamingSubConversation({
    required this.lines,
    required this.isZh,
    required this.theme,
    required this.colorScheme,
    this.filePathRoots = const [],
  });

  final List<String> lines;
  final bool isZh;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final List<String> filePathRoots;

  static const int _tailSize = 80;

  @override
  State<_HeStreamingSubConversation> createState() =>
      _HeStreamingSubConversationState();
}

class _HeStreamingSubConversationState
    extends State<_HeStreamingSubConversation> {
  List<_HeOutputSegment>? _segments;
  List<_HeOutputSegment>? _olderSegments;
  int _lastHiddenAbove = 0;
  int _lastSegmentCount = 0;
  int _contentRevision = 0;
  bool _showEarlierSegments = false;
  bool _olderSegmentsLoading = false;
  int _olderSegmentWindowStart = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rebuildIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _HeStreamingSubConversation oldWidget) {
    super.didUpdateWidget(oldWidget);
    _rebuildIfNeeded();
  }

  void _rebuildIfNeeded() {
    final lines = widget.lines;
    final start = lines.length > _HeStreamingSubConversation._tailSize
        ? lines.length - _HeStreamingSubConversation._tailSize
        : 0;
    final display = lines.length > _HeStreamingSubConversation._tailSize
        ? lines.sublist(start)
        : lines;
    _lastHiddenAbove = start;
    _segments = _heParseOutputSegments(display);
    final newCount = _segments?.length ?? 0;
    if (newCount > _lastSegmentCount) {
      _contentRevision++;
    }
    _lastSegmentCount = newCount;

    if (!_showEarlierSegments) {
      _olderSegments = null;
      _olderSegmentsLoading = false;
      _olderSegmentWindowStart = -1;
      return;
    }

    _ensureOlderSegments(start);
  }

  void _ensureOlderSegments(int start) {
    if (!_showEarlierSegments || start <= 0) {
      _olderSegments = null;
      _olderSegmentsLoading = false;
      _olderSegmentWindowStart = -1;
      return;
    }
    if (_olderSegmentWindowStart == start && _olderSegments != null) {
      return;
    }
    final olderLines = widget.lines.sublist(0, start);
    _olderSegmentWindowStart = start;
    if (olderLines.length > 3000) {
      _olderSegmentsLoading = true;
      compute(_heParseOutputSegmentsIsolate, olderLines).then((result) {
        if (!mounted ||
            !_showEarlierSegments ||
            _olderSegmentWindowStart != start) {
          return;
        }
        setState(() {
          _olderSegments = result;
          _olderSegmentsLoading = false;
        });
      });
      return;
    }
    _olderSegments = _heParseOutputSegments(olderLines);
    _olderSegmentsLoading = false;
  }

  void _toggleEarlierSegments() {
    setState(() {
      _showEarlierSegments = !_showEarlierSegments;
      if (!_showEarlierSegments) {
        _olderSegments = null;
        _olderSegmentsLoading = false;
        _olderSegmentWindowStart = -1;
      }
    });
    if (_showEarlierSegments) {
      _ensureOlderSegments(_lastHiddenAbove);
    }
  }

  Widget _buildSegmentList(
    List<_HeOutputSegment> segments, {
    required bool animateLast,
  }) {
    final colorScheme = widget.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < segments.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          () {
            final card = _HeSegmentMiniCard(
              key: ValueKey<String>(_heSegmentWidgetKey(segments[i], i)),
              segment: segments[i],
              isZh: widget.isZh,
              theme: widget.theme,
              colorScheme: colorScheme,
              filePathRoots: widget.filePathRoots,
              isStreaming: animateLast && i == segments.length - 1,
            );
            final wrapped = RepaintBoundary(child: card);
            if (!animateLast || i != segments.length - 1) {
              return wrapped;
            }
            return _HeAnimatedSegmentEntry(
              key: ValueKey<String>(
                'he-stream-entry-$_contentRevision-${_heSegmentWidgetKey(segments[i], i)}',
              ),
              child: wrapped,
            );
          }(),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme;
    final segments = _segments ?? [];
    final olderSegments = _olderSegments;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_lastHiddenAbove > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: colorScheme.surface.withValues(alpha: 0.82),
              borderRadius: _br16,
              child: InkWell(
                onTap: _toggleEarlierSegments,
                borderRadius: _br16,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      AnimatedRotation(
                        turns: _showEarlierSegments ? 0.5 : 0,
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 16,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.isZh
                              ? (_showEarlierSegments
                                    ? '收起更早的子消息 · $_lastHiddenAbove 行'
                                    : '展开更早的子消息 · $_lastHiddenAbove 行')
                              : (_showEarlierSegments
                                    ? 'Hide earlier sub-messages · $_lastHiddenAbove lines'
                                    : 'Show earlier sub-messages · $_lastHiddenAbove lines'),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (_showEarlierSegments) ...[
          if (_olderSegmentsLoading)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.isZh
                        ? '正在加载更早的子消息…'
                        : 'Loading earlier sub-messages…',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.72,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (olderSegments != null && olderSegments.isNotEmpty) ...[
            RepaintBoundary(
              child: _buildSegmentList(olderSegments, animateLast: false),
            ),
            const SizedBox(height: 8),
          ],
        ],
        if (segments.isNotEmpty) _buildSegmentList(segments, animateLast: true),
        // Streaming indicator.
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                widget.isZh ? '正在输出…' : 'Streaming…',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.60),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// _HeSegmentMiniCard — Renders a single output segment as a styled mini-card
// matching the AI thread template's visual language for thinking, tool call,
// and assistant response messages.
// =============================================================================

class _HeSegmentMiniCard extends StatefulWidget {
  const _HeSegmentMiniCard({
    super.key,
    required this.segment,
    required this.isZh,
    required this.theme,
    required this.colorScheme,
    this.filePathRoots = const [],
    this.isStreaming = false,
  });

  final _HeOutputSegment segment;
  final bool isZh;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final List<String> filePathRoots;
  final bool isStreaming;

  @override
  State<_HeSegmentMiniCard> createState() => _HeSegmentMiniCardState();
}

class _HeSegmentMiniCardState extends State<_HeSegmentMiniCard> {
  late bool _expanded = widget.segment.kind != _HeSegmentKind.thinking;

  static const _maxPreviewChars = 600;

  @override
  void didUpdateWidget(covariant _HeSegmentMiniCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.segment.kind != widget.segment.kind) {
      _expanded = widget.segment.kind != _HeSegmentKind.thinking;
    }
  }

  @override
  Widget build(BuildContext context) {
    final seg = widget.segment;
    final colorScheme = widget.colorScheme;
    final isDark = widget.theme.brightness == Brightness.dark;

    if (seg.kind == _HeSegmentKind.toolCall ||
        seg.kind == _HeSegmentKind.toolResult) {
      return _HeStructuredToolTraceCard(
        segment: seg,
        isZh: widget.isZh,
        theme: widget.theme,
        colorScheme: colorScheme,
        isStreaming: widget.isStreaming,
      );
    }

    // ── Special rendering for manual review verdict segments ─────────
    if (seg.kind == _HeSegmentKind.userInput) {
      final verdictInfo = _parseReviewVerdict(seg);
      if (verdictInfo != null) {
        return _HeReviewVerdictCard(
          isPass: verdictInfo.isPass,
          comment: verdictInfo.comment,
          roleLabel:
              seg.roleLabel ?? (widget.isZh ? '用户人工验收结果' : 'Manual Review'),
          isZh: widget.isZh,
          theme: widget.theme,
          colorScheme: colorScheme,
        );
      }
    }

    // ── Determine card style by segment kind ────────────────────────────
    final (
      IconData icon,
      String label,
      Color cardBg,
      Color cardBorder,
      Color cardText,
      double borderRadius,
    ) = switch (seg.kind) {
      _HeSegmentKind.command => (
        Icons.terminal_rounded,
        widget.isZh ? '执行命令' : 'Command',
        colorScheme.surfaceContainerHighest,
        colorScheme.outlineVariant.withValues(alpha: 0.30),
        colorScheme.onSurface,
        16.0,
      ),
      _HeSegmentKind.thinking => (
        Icons.psychology_alt_outlined,
        widget.isZh ? '思考' : 'Thinking',
        const Color(0xFF18181B),
        Colors.white.withValues(alpha: 0.10),
        Colors.white,
        18.0,
      ),
      _HeSegmentKind.toolCall || _HeSegmentKind.toolResult => (
        Icons.build_circle_outlined,
        widget.isZh ? '工具调用' : 'Tool Call',
        colorScheme.secondaryContainer,
        colorScheme.secondary.withValues(alpha: 0.35),
        colorScheme.onSecondaryContainer,
        26.0,
      ),
      _HeSegmentKind.assistant => (
        Icons.auto_awesome_rounded,
        widget.isZh ? 'AI 回复' : 'AI Response',
        colorScheme.surfaceContainerHigh,
        colorScheme.outlineVariant.withValues(alpha: isDark ? 0.18 : 0.10),
        colorScheme.onSurface,
        26.0,
      ),
      _HeSegmentKind.output => (
        Icons.info_outline_rounded,
        widget.isZh ? '输出' : 'Output',
        colorScheme.surfaceContainerLow,
        colorScheme.outlineVariant.withValues(alpha: 0.15),
        colorScheme.onSurface,
        16.0,
      ),
      _HeSegmentKind.userInput => (
        Icons.person_rounded,
        seg.roleLabel ?? (widget.isZh ? '用户输入' : 'User Input'),
        Color.alphaBlend(
          colorScheme.tertiary.withValues(alpha: isDark ? 0.22 : 0.12),
          colorScheme.surface,
        ),
        colorScheme.tertiary.withValues(alpha: isDark ? 0.40 : 0.28),
        colorScheme.onSurface,
        18.0,
      ),
      _HeSegmentKind.handoff => (
        Icons.swap_horiz_rounded,
        seg.roleLabel ?? (widget.isZh ? '交接文档' : 'Handoff'),
        Color.alphaBlend(
          colorScheme.primary.withValues(alpha: isDark ? 0.18 : 0.10),
          colorScheme.surface,
        ),
        colorScheme.primary.withValues(alpha: isDark ? 0.45 : 0.30),
        colorScheme.onSurface,
        18.0,
      ),
    };

    // ── Special rendering for command segments ──────────────────────────
    if (seg.kind == _HeSegmentKind.command) {
      return _HeCommandStrip(command: seg.lines.join('\n'));
    }

    final isThinking = seg.kind == _HeSegmentKind.thinking;
    final body = seg.markdownBody;
    final needsCollapse =
        isThinking || (body.length > _maxPreviewChars && !widget.isStreaming);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: cardBorder),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(
              alpha: isDark
                  ? (isThinking ? 0.06 : 0.04)
                  : (isThinking ? 0.04 : 0.03),
            ),
            blurRadius: isThinking ? 12 : 8,
            offset: Offset(0, isThinking ? 3 : 2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(isThinking ? 18 : 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────────────
            if (isThinking)
              // Thinking pill header — matches default thread style.
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  borderRadius: _br999,
                  overlayColor: WidgetStatePropertyAll<Color>(
                    Colors.white.withValues(alpha: 0.03),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: _br999,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          size: 18,
                          color: cardText.withValues(alpha: 0.88),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          label,
                          style: widget.theme.textTheme.labelLarge?.copyWith(
                            color: cardText.withValues(alpha: 0.88),
                          ),
                        ),
                        const SizedBox(width: 6),
                        AnimatedRotation(
                          turns: _expanded ? 0.5 : 0,
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: cardText.withValues(alpha: 0.78),
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              InkWell(
                onTap: needsCollapse
                    ? () => setState(() => _expanded = !_expanded)
                    : null,
                borderRadius: _br999,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 14,
                        color: cardText.withValues(alpha: 0.72),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: widget.theme.textTheme.labelMedium?.copyWith(
                          color: cardText.withValues(alpha: 0.72),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (needsCollapse) ...[
                        const SizedBox(width: 4),
                        AnimatedRotation(
                          turns: _expanded ? 0.5 : 0,
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: cardText.withValues(alpha: 0.50),
                            size: 16,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            // ── Body ──────────────────────────────────────────────────
            if (body.isNotEmpty) ...[
              SizedBox(height: isThinking ? 10 : 8),
              if (isThinking)
                _HeThinkingSegmentBody(
                  content: body,
                  expanded: _expanded,
                  isStreaming: widget.isStreaming,
                  theme: widget.theme,
                  colorScheme: colorScheme,
                  textColor: cardText,
                  cardBackground: cardBg,
                  filePathRoots: widget.filePathRoots,
                )
              else
                _HeSegmentBody(
                  content: body,
                  expanded: _expanded || !needsCollapse,
                  isZh: widget.isZh,
                  theme: widget.theme,
                  colorScheme: colorScheme,
                  textColor: cardText,
                  filePathRoots: widget.filePathRoots,
                  onExpand: () => setState(() => _expanded = true),
                  cardBackground: isThinking ? cardBg : null,
                ),
            ] else
              Text(
                widget.isZh ? '（无内容）' : '(empty)',
                style: TextStyle(
                  color: cardText.withValues(alpha: 0.45),
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HeAnimatedSegmentEntry extends StatefulWidget {
  const _HeAnimatedSegmentEntry({super.key, required this.child});

  final Widget child;

  @override
  State<_HeAnimatedSegmentEntry> createState() =>
      _HeAnimatedSegmentEntryState();
}

class _HeAnimatedSegmentEntryState extends State<_HeAnimatedSegmentEntry>
    with SingleTickerProviderStateMixin {
  static const _entranceDuration = Duration(milliseconds: 420);

  late final AnimationController _entranceCtrl;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      duration: _entranceDuration,
      vsync: this,
    );
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceCtrl,
        curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
      ),
    );
    _scale = Tween<double>(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOutBack),
    );
    _slide = Tween<Offset>(begin: const Offset(0.0, 0.04), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOutCubic),
        );
    _entranceCtrl.forward();
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(
        scale: _scale,
        alignment: Alignment.topCenter,
        child: SlideTransition(position: _slide, child: widget.child),
      ),
    );
  }
}

// ── Structured API tool call metadata ────────────────────────────────────
//
// HardnessApiPhaseRunner emits two markers inside a toolCall segment:
//   📥 {args JSON}
//   📤 status: succeeded | 150ms | exit: 0 | cmd: ... | cwd: ...
// This class extracts those markers, removes them from the segment lines,
// and makes the structured data available to the tool trace card.
// ─────────────────────────────────────────────────────────────────────────

final RegExp _heApiArgsMarker = RegExp(r'^\s*📥\s+(.+)$');
final RegExp _heApiStatusMarker = RegExp(r'^\s*📤\s+(.+)$');
