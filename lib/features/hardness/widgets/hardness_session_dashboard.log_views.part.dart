part of 'hardness_session_dashboard.dart';

class _HeLogSection extends StatefulWidget {
  const _HeLogSection({
    required this.log,
    required this.isZh,
    required this.onCopy,
    this.filePathRoots = const [],
  });

  final HardnessPhaseLog log;
  final bool isZh;
  final VoidCallback onCopy;
  final List<String> filePathRoots;

  @override
  State<_HeLogSection> createState() => _HeLogSectionState();
}

class _HeLogSectionState extends State<_HeLogSection> {
  bool _showRaw = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final log = widget.log;
    final isRunning = log.status == HardnessPhaseStatus.running;
    final lines = log.lines;
    final isZh = widget.isZh;

    // Running phases change content every frame — AnimatedSize cannot settle
    // in a SliverList (the size-change listener fires markNeedsLayout during
    // performLayout, causing a crash). Use a plain wrapper here.
    return Material(
      color: colorScheme.surface.withValues(alpha: 0.78),
      borderRadius: _br16,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Section header row ────────────────────────────────────────
            Row(
              children: [
                Icon(
                  Icons.terminal_rounded,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  isZh ? '执行输出' : 'Output',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                // Raw / rendered toggle (only shown when phase is done)
                if (!isRunning && lines.isNotEmpty) ...[
                  _HeSmallPill(
                    icon: _showRaw
                        ? Icons.auto_awesome_rounded
                        : Icons.code_rounded,
                    label: _showRaw
                        ? (isZh ? '渲染' : 'Rendered')
                        : (isZh ? '原始' : 'Raw'),
                    onTap: () => setState(() => _showRaw = !_showRaw),
                  ),
                  const SizedBox(width: 8),
                ],
                _HeSmallPill(
                  icon: Icons.copy_rounded,
                  label: isZh ? '复制' : 'Copy',
                  onTap: widget.onCopy,
                ),
              ],
            ),
            const SizedBox(height: 10),
            // ── Content area ──────────────────────────────────────────────
            if (lines.isEmpty)
              _HeEmptyOutputPlaceholder(isZh: isZh)
            else if (isRunning)
              _HeStreamingSubConversation(
                lines: lines,
                isZh: isZh,
                theme: theme,
                colorScheme: colorScheme,
                filePathRoots: widget.filePathRoots,
              )
            else if (_showRaw)
              _HeRawFullView(
                lines: lines,
                colorScheme: colorScheme,
                onCopy: widget.onCopy,
                isZh: isZh,
              )
            else
              _HeSubConversationView(
                lines: lines,
                isZh: isZh,
                theme: theme,
                colorScheme: colorScheme,
                filePathRoots: widget.filePathRoots,
              ),
          ],
        ),
      ),
    );
  }
}

// ── Empty placeholder ──────────────────────────────────────────────────────

class _HeEmptyOutputPlaceholder extends StatelessWidget {
  const _HeEmptyOutputPlaceholder({required this.isZh});
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.8,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            isZh ? '等待输出…' : 'Waiting for output…',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ── Raw full view (manual toggle) ─────────────────────────────────────────

class _HeRawFullView extends StatefulWidget {
  const _HeRawFullView({
    required this.lines,
    required this.colorScheme,
    required this.onCopy,
    required this.isZh,
  });

  final List<String> lines;
  final ColorScheme colorScheme;
  final VoidCallback onCopy;
  final bool isZh;

  static const int _previewCount = 30;

  @override
  State<_HeRawFullView> createState() => _HeRawFullViewState();
}

class _HeRawFullViewState extends State<_HeRawFullView> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final lines = widget.lines;
    final theme = Theme.of(context);
    final colorScheme = widget.colorScheme;
    final shortened = !_expanded && lines.length > _HeRawFullView._previewCount;
    final display = shortened
        ? lines.sublist(0, _HeRawFullView._previewCount)
        : lines;
    final hidden = shortened ? lines.length - _HeRawFullView._previewCount : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          cacheExtent: 800,
          itemCount: display.length,
          itemBuilder: (_, i) =>
              _LogLine(line: display[i], colorScheme: colorScheme),
        ),
        if (hidden > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: GestureDetector(
              onTap: () => setState(() => _expanded = true),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: _br999,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.unfold_more_rounded,
                      size: 14,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.isZh
                          ? '显示全部 ${lines.length} 行'
                          : 'Show all ${lines.length} lines',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Smart view (markdown rendered) ────────────────────────────────────────
// For large payloads (>3 000 lines) the log-splitting is offloaded to a
// background isolate via compute() so the UI thread stays responsive.

class _HeSmartView extends StatefulWidget {
  const _HeSmartView({
    required this.lines,
    required this.isZh,
    required this.theme,
    required this.colorScheme,
    required this.filePathRoots,
  });

  final List<String> lines;
  final bool isZh;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final List<String> filePathRoots;

  // Threshold: below this, parse on the UI thread synchronously (faster
  // round-trip); above it, hand off to an isolate.
  static const int _isolateThreshold = 3000;

  @override
  State<_HeSmartView> createState() => _HeSmartViewState();
}

// Top-level function required by compute() — must not be a closure.
({String? command, String body}) _heSplitLogForMarkdownCompute(
  List<String> lines,
) => _heSplitLogForMarkdown(lines);

class _HeSmartViewState extends State<_HeSmartView> {
  ({String? command, String body})? _parsed;

  @override
  void initState() {
    super.initState();
    _parse(widget.lines);
  }

  @override
  void didUpdateWidget(_HeSmartView old) {
    super.didUpdateWidget(old);
    if (old.lines != widget.lines) {
      _parsed = null;
      _parse(widget.lines);
    }
  }

  void _parse(List<String> lines) {
    if (lines.length > _HeSmartView._isolateThreshold) {
      compute(_heSplitLogForMarkdownCompute, lines).then((result) {
        if (mounted) setState(() => _parsed = result);
      });
    } else {
      _parsed = _heSplitLogForMarkdown(lines);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme;

    // Show a lightweight spinner while the isolate is working.
    if (_parsed == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              widget.isZh ? '正在处理…' : 'Processing…',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    final (:command, :body) = _parsed!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (command != null) ...[
          _HeCommandStrip(command: command),
          const SizedBox(height: 10),
        ],
        if (body.isNotEmpty)
          _HeMarkdownContent(
            content: body,
            isZh: widget.isZh,
            theme: widget.theme,
            colorScheme: colorScheme,
            filePathRoots: widget.filePathRoots,
          )
        else
          Text(
            widget.isZh ? '（无文本输出）' : '(no text output)',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// _HeSubConversationView — Structured sub-conversation rendering (completed phase)
//
// Parses CLI output into typed segments and renders each as an independent
// mini-card within the phase card, providing a structured conversation feel
// that matches the AI thread template's visual language.
// =============================================================================

class _HeSubConversationView extends StatefulWidget {
  const _HeSubConversationView({
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

  @override
  State<_HeSubConversationView> createState() => _HeSubConversationViewState();
}

class _HeSubConversationViewState extends State<_HeSubConversationView> {
  List<_HeOutputSegment>? _segments;
  bool _showAllSegments = false;
  int _lastSegmentCount = 0;
  int _contentRevision = 0;
  bool _hasParsedOnce = false;

  // Show at most this many segments initially; the rest hidden behind a
  // "show more" button. This avoids laying out hundreds of segment widgets
  // inside a shrinkWrap ListView — the chief source of scroll jank.
  static const int _initialVisibleCount = 20;

  @override
  void initState() {
    super.initState();
    _parseSegments();
  }

  @override
  void didUpdateWidget(_HeSubConversationView old) {
    super.didUpdateWidget(old);
    if (old.lines != widget.lines) {
      _showAllSegments = false;
      _parseSegments();
    }
  }

  void _parseSegments() {
    if (widget.lines.length > 3000) {
      compute(_heParseOutputSegmentsIsolate, widget.lines).then((result) {
        if (!mounted) {
          return;
        }
        setState(() {
          _applyParsedSegments(result);
        });
      });
    } else {
      _applyParsedSegments(_heParseOutputSegments(widget.lines));
    }
  }

  void _applyParsedSegments(List<_HeOutputSegment> result) {
    if (_hasParsedOnce && result.length > _lastSegmentCount) {
      _contentRevision++;
    }
    _segments = result;
    _lastSegmentCount = result.length;
    _hasParsedOnce = true;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme;
    final segments = _segments;

    if (segments == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              widget.isZh ? '正在处理…' : 'Processing…',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    if (segments.isEmpty) {
      return Text(
        widget.isZh ? '（无文本输出）' : '(no text output)',
        style: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 13,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    final needsTruncation =
        !_showAllSegments && segments.length > _initialVisibleCount;
    final hiddenCount = needsTruncation
        ? segments.length - _initialVisibleCount
        : 0;
    final visibleSegments = needsTruncation
        ? segments.sublist(segments.length - _initialVisibleCount)
        : segments;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (needsTruncation)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: colorScheme.surface.withValues(alpha: 0.82),
              borderRadius: _br16,
              child: InkWell(
                onTap: () => setState(() => _showAllSegments = true),
                borderRadius: _br16,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.isZh
                              ? '展开更早的 $hiddenCount 条子消息'
                              : 'Show $hiddenCount earlier sub-messages',
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
        for (var i = 0; i < visibleSegments.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          () {
            final segmentKey = _heSegmentWidgetKey(visibleSegments[i], i);
            final card = RepaintBoundary(
              child: _HeSegmentMiniCard(
                key: ValueKey<String>(segmentKey),
                segment: visibleSegments[i],
                isZh: widget.isZh,
                theme: widget.theme,
                colorScheme: colorScheme,
                filePathRoots: widget.filePathRoots,
              ),
            );
            final shouldAnimateIn =
                _contentRevision > 0 && i == visibleSegments.length - 1;
            if (!shouldAnimateIn) {
              return card;
            }
            return _HeAnimatedSegmentEntry(
              key: ValueKey<String>(
                'he-sub-entry-$_contentRevision-$segmentKey',
              ),
              child: card,
            );
          }(),
        ],
      ],
    );
  }
}

/// Top-level function for isolate use in compute().
List<_HeOutputSegment> _heParseOutputSegmentsIsolate(List<String> lines) =>
    _heParseOutputSegments(lines);

// =============================================================================
// _HeStreamingSubConversation — Streaming sub-conversation (running phase)
//
// Similar to _HeSubConversationView but operates on a tail of lines and
// includes streaming indicators.
// =============================================================================
