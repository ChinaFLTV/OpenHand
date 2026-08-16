part of 'harness_session_dashboard.dart';

class _HeLogSection extends StatefulWidget {
  const _HeLogSection({
    required this.log,
    required this.isZh,
    required this.onCopy,
    this.filePathRoots = const [],
  });

  final HarnessPhaseLog log;
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
    final isRunning = log.status == HarnessPhaseStatus.running;
    final lines = log.lines;

    // 运行阶段每帧都会改变内容，AnimatedSize 在 SliverList 中无法稳定布局。
    return Material(
      color: colorScheme.surface.withValues(alpha: 0.78),
      borderRadius: kOpenHandBorderRadius16,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.terminal_rounded,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
                kOpenHandHGap6,
                Text(
                  openHandLocalizedText(
                    context,
                    zh: '执行输出',
                    zhHant: '執行輸出',
                    en: 'Output',
                    fr: 'Sortie',
                    de: 'Ausgabe',
                    ja: '実行出力',
                  ),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                // 仅在阶段结束后允许切换原始内容与渲染结果。
                if (!isRunning && lines.isNotEmpty) ...[
                  _HeSmallPill(
                    icon: _showRaw
                        ? Icons.auto_awesome_rounded
                        : Icons.code_rounded,
                    label: _showRaw
                        ? openHandLocalizedText(
                            context,
                            zh: '渲染',
                            zhHant: '渲染',
                            en: 'Rendered',
                            fr: 'Rendu',
                            de: 'Gerendert',
                            ja: 'レンダリング',
                          )
                        : openHandLocalizedText(
                            context,
                            zh: '原始',
                            zhHant: '原始',
                            en: 'Raw',
                            fr: 'Brut',
                            de: 'Roh',
                            ja: '生データ',
                          ),
                    onTap: () => setState(() => _showRaw = !_showRaw),
                  ),
                  kOpenHandHGap8,
                ],
                _HeSmallPill(
                  icon: Icons.copy_rounded,
                  label: openHandCopyLabel(context),
                  onTap: widget.onCopy,
                ),
              ],
            ),
            kOpenHandGap10,
            if (lines.isEmpty)
              _HeEmptyOutputPlaceholder(isZh: widget.isZh)
            else if (isRunning)
              _HeStreamingSubConversation(
                lines: lines,
                isZh: widget.isZh,
                theme: theme,
                colorScheme: colorScheme,
                filePathRoots: widget.filePathRoots,
              )
            else if (_showRaw)
              _HeRawFullView(
                lines: lines,
                colorScheme: colorScheme,
                onCopy: widget.onCopy,
                isZh: widget.isZh,
              )
            else
              _HeSubConversationView(
                lines: lines,
                isZh: widget.isZh,
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
          kOpenHandHGap10,
          Text(
            openHandLocalizedText(
              context,
              zh: '等待输出…',
              zhHant: '等待輸出…',
              en: 'Waiting for output…',
              fr: 'En attente de sortie…',
              de: 'Warte auf Ausgabe…',
              ja: '出力を待機中…',
            ),
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

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
            child: OpenHandTapRegion(
              onTap: () => setState(() => _expanded = true),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: kOpenHandPillBorderRadius,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.unfold_more_rounded,
                      size: 14,
                      color: colorScheme.primary,
                    ),
                    kOpenHandHGap6,
                    Text(
                      openHandLocalizedText(
                        context,
                        zh: '显示全部 ${lines.length} 行',
                        zhHant: '顯示全部 ${lines.length} 行',
                        en: 'Show all ${lines.length} lines',
                        fr: 'Afficher les ${lines.length} lignes',
                        de: 'Alle ${lines.length} Zeilen anzeigen',
                        ja: '${lines.length} 行すべて表示',
                      ),
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

// 超过阈值的大日志交给隔离线程解析，避免阻塞界面线程。

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

  static const int _isolateThreshold = 3000;

  @override
  State<_HeSmartView> createState() => _HeSmartViewState();
}

// compute 只能调用顶层函数。
({String? command, String body}) _heSplitLogForMarkdownCompute(
  List<String> lines,
) => _heSplitLogForMarkdown(lines);

Widget _heProcessingIndicator(BuildContext context, ColorScheme colorScheme) {
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
        kOpenHandHGap10,
        Text(
          openHandLocalizedText(
            context,
            zh: '正在处理…',
            zhHant: '正在處理…',
            en: 'Processing…',
            fr: 'Traitement…',
            de: 'Wird verarbeitet…',
            ja: '処理中…',
          ),
          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
        ),
      ],
    ),
  );
}

Widget _heEmptyOutputText(BuildContext context, ColorScheme colorScheme) {
  return Text(
    openHandLocalizedText(
      context,
      zh: '（无文本输出）',
      zhHant: '（無文字輸出）',
      en: '(no text output)',
      fr: '(aucune sortie texte)',
      de: '(keine Textausgabe)',
      ja: '（テキスト出力なし）',
    ),
    style: TextStyle(
      color: colorScheme.onSurfaceVariant,
      fontSize: 13,
      fontStyle: FontStyle.italic,
    ),
  );
}

class _HeSmartViewState extends State<_HeSmartView> {
  ({String? command, String body})? _parsed;
  int _parseGeneration = 0;

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
    final generation = ++_parseGeneration;
    if (lines.length > _HeSmartView._isolateThreshold) {
      compute(_heSplitLogForMarkdownCompute, lines).then<void>(
        (result) {
          if (!mounted || generation != _parseGeneration) return;
          setState(() => _parsed = result);
        },
        onError: (Object error, StackTrace stack) {
          silentLog('harness_log_view', '在隔离线程解析日志', error, stack);
          if (!mounted || generation != _parseGeneration) return;
          setState(() => _parsed = _heSplitLogForMarkdown(lines));
        },
      );
    } else {
      _parsed = _heSplitLogForMarkdown(lines);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme;

    if (_parsed == null) {
      return _heProcessingIndicator(context, colorScheme);
    }

    final (:command, :body) = _parsed!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (command != null) ...[
          _HeCommandStrip(command: command),
          kOpenHandGap10,
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
          _heEmptyOutputText(context, colorScheme),
      ],
    );
  }
}

// 将已完成阶段的命令行输出解析为独立片段。
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
  int _parseGeneration = 0;

  // 首屏限制片段数量，避免一次布局数百个组件。
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
    final lines = widget.lines;
    final generation = ++_parseGeneration;
    if (lines.length > 3000) {
      compute(_heParseOutputSegmentsIsolate, lines).then<void>(
        (result) {
          if (!mounted || generation != _parseGeneration) return;
          setState(() => _applyParsedSegments(result));
        },
        onError: (Object error, StackTrace stack) {
          silentLog('harness_log_view', '在隔离线程解析输出片段', error, stack);
          if (!mounted || generation != _parseGeneration) return;
          setState(() => _applyParsedSegments(_heParseOutputSegments(lines)));
        },
      );
    } else {
      _applyParsedSegments(_heParseOutputSegments(lines));
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
      return _heProcessingIndicator(context, colorScheme);
    }

    if (segments.isEmpty) {
      return _heEmptyOutputText(context, colorScheme);
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
              borderRadius: kOpenHandBorderRadius16,
              child: InkWell(
                onTap: () => setState(() => _showAllSegments = true),
                borderRadius: kOpenHandBorderRadius16,
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
                      kOpenHandHGap8,
                      Expanded(
                        child: Text(
                          openHandLocalizedText(
                            context,
                            zh: '展开更早的 $hiddenCount 条子消息',
                            zhHant: '展開更早的 $hiddenCount 則子訊息',
                            en: 'Show $hiddenCount earlier sub-messages',
                            fr: 'Afficher $hiddenCount sous-messages précédents',
                            de: '$hiddenCount frühere Teilnachrichten anzeigen',
                            ja: '$hiddenCount 件の前のサブメッセージを表示',
                          ),
                          style: TextStyle(
                            fontFamily: kOpenHandMonospaceFontFamily,
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
          if (i > 0) kOpenHandGap8,
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

/// 供 compute 调用的顶层解析函数。
List<_HeOutputSegment> _heParseOutputSegmentsIsolate(List<String> lines) =>
    _heParseOutputSegments(lines);
// 运行阶段仅解析日志尾部，并显示流式状态。
