part of '../openhand_home_page.dart';

/// Maximum code-block length (in characters) at which we still attempt
/// syntax highlighting. Beyond this we render plain monospace text to keep
/// transcript open / scroll responsive (very long log dumps were the
/// dominant source of multi-second jank when opening a session).
const int _highlightSkipThresholdChars = 80 * 1024;

/// Code-block length above which we defer the first highlight pass to the
/// next frame, painting plain text on the first frame.
///
/// 短代码片段同步高亮；非平凡代码块走 FrameScheduler 分帧高亮
/// （首帧纯文本，后续帧补色），避免多 tool_call 同帧 mount 时把主线程撑爆。
/// _buildCodeBody 的 null 回退确保即使 span 为 null 也能显示内容。
const int _highlightDeferThresholdChars = 256;
const Duration _tempPreviewCleanupTotalTimeout = Duration(seconds: 20);
const Duration _tempPreviewWriteTimeout = Duration(seconds: 30);
const BoundedDeletePolicy _tempPreviewDeletePolicy = BoundedDeletePolicy(
  maxEntries: 128,
  maxDepth: 8,
  operationTimeout: Duration(seconds: 3),
  totalTimeout: Duration(seconds: 10),
);

/// Process-wide LRU cache for parsed code-block `TextSpan`s. The same code
/// snippet (e.g. a tool result, a generated diff) frequently appears in
/// many bubbles across a session; reusing the cached span avoids
/// re-tokenising on every rebuild and on cross-session navigation.
///
/// 含多 tool 调用的长会话很容易超过较小缓存容量；用少量内存
/// （每条仅 ~几 KiB span）换取跨会话导航和滚回时的命中率。
final _HighlightSpanCache _highlightSpanCache = _HighlightSpanCache(
  maxEntries: 512,
);
final Set<int> _pendingHighlightWarmups = <int>{};

/// 全局帧分散调度器。当一条消息含 N 个代码块同时展开时，
/// 所有代码块的 highlight 回调都注册到同一个 addPostFrameCallback，
/// 导致下一帧仍然要同步执行 N 次 tokenize。此调度器将 N 个任务分散
/// 到 ceil(N/2) 个帧中执行（每帧最多处理 2 个），彻底消除 ANR。
/// 每帧最多执行一个 highlight 任务。
/// 一些大段 bash/log 输出 tokenize 单次可能 ~30ms；同帧多个任务会直接撑爆
/// 60 fps 帧预算。1/帧 让慢机器也能稳；配合 [_HighlightSpanCache]，第二次
/// 展开 / 滚回时仍能瞬时拉起。
final _FrameTaskScheduler _highlightFrameScheduler = _FrameTaskScheduler(
  maxPerFrame: 1,
);

class _HighlightSpanCache {
  _HighlightSpanCache({required this.maxEntries});

  static const int _maxSourceChars = 4 * 1024 * 1024;
  final int maxEntries;
  final LinkedHashMap<int, _HighlightSpanCacheEntry> _entries =
      LinkedHashMap<int, _HighlightSpanCacheEntry>();
  int _sourceChars = 0;

  TextSpan? get(int key) {
    final entry = _entries.remove(key);
    if (entry != null) {
      _entries[key] = entry;
    }
    return entry?.span;
  }

  void put(int key, TextSpan span, int sourceChars) {
    final previous = _entries.remove(key);
    if (previous != null) {
      _sourceChars -= previous.sourceChars;
    }
    if (sourceChars > _maxSourceChars) {
      return;
    }
    _entries[key] = _HighlightSpanCacheEntry(span, sourceChars);
    _sourceChars += sourceChars;
    while (_entries.length > maxEntries || _sourceChars > _maxSourceChars) {
      final removed = _entries.remove(_entries.keys.first);
      if (removed != null) {
        _sourceChars -= removed.sourceChars;
      }
    }
  }
}

class _HighlightSpanCacheEntry {
  const _HighlightSpanCacheEntry(this.span, this.sourceChars);

  final TextSpan span;
  final int sourceChars;
}

int _highlightSignatureForInputs({
  required String content,
  required String? effectiveLanguage,
  required Color baseColor,
  required bool useDarkPalette,
  required ThemeData theme,
}) {
  return Object.hash(
    content,
    effectiveLanguage,
    baseColor.toARGB32(),
    useDarkPalette,
    theme.textTheme.bodyMedium?.fontSize,
    theme.textTheme.bodyMedium?.fontFamily,
    theme.textTheme.bodyMedium?.height,
  );
}

TextStyle _baseCodeStyleForTheme({
  required ThemeData theme,
  required Color baseColor,
  required bool useDarkPalette,
}) {
  final fontSize = theme.textTheme.bodyMedium?.fontSize ?? 14;
  return theme.textTheme.bodyMedium?.copyWith(
        color: baseColor,
        fontFamily: kOpenHandMonospaceFontFamily,
        fontSize: fontSize * 0.94,
        height: 1.5,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ) ??
      TextStyle(
        color: baseColor,
        fontFamily: kOpenHandMonospaceFontFamily,
        fontSize: fontSize * 0.94,
        height: 1.5,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      );
}

TextSpan _computeHighlightedCodeSpan({
  required String content,
  required String? effectiveLanguage,
  required ThemeData theme,
  required Color baseColor,
  required bool useDarkPalette,
  required int signature,
}) {
  final cached = _highlightSpanCache.get(signature);
  if (cached != null) {
    return cached;
  }
  final baseStyle = _baseCodeStyleForTheme(
    theme: theme,
    baseColor: baseColor,
    useDarkPalette: useDarkPalette,
  );
  if (content.length > _highlightSkipThresholdChars) {
    final span = TextSpan(text: content, style: baseStyle);
    _highlightSpanCache.put(signature, span, content.length);
    return span;
  }
  final timelineLabel = effectiveLanguage == null || effectiveLanguage.isEmpty
      ? '代码高亮（纯文本，${content.length} 字符）'
      : '代码高亮（$effectiveLanguage，${content.length} 字符）';
  TextSpan span;
  if (kDebugMode) {
    span = developer.Timeline.timeSync<TextSpan>(timelineLabel, () {
      final highlighter = _CodeSyntaxHighlighter(
        baseStyle: baseStyle,
        darkSurface: useDarkPalette,
      );
      return highlighter.build(content, language: effectiveLanguage);
    });
  } else {
    final highlighter = _CodeSyntaxHighlighter(
      baseStyle: baseStyle,
      darkSurface: useDarkPalette,
    );
    span = highlighter.build(content, language: effectiveLanguage);
  }
  _highlightSpanCache.put(signature, span, content.length);
  return span;
}

void _warmHighlightedCodeSpan({
  required String content,
  required ThemeData theme,
  required Color baseColor,
  required bool forceDarkSurface,
  String? language,
}) {
  final effectiveLanguage = _normalizeCodeLanguage(language);
  final useDarkPalette =
      forceDarkSurface || theme.brightness == Brightness.dark;
  final signature = _highlightSignatureForInputs(
    content: content,
    effectiveLanguage: effectiveLanguage,
    baseColor: baseColor,
    useDarkPalette: useDarkPalette,
    theme: theme,
  );
  if (_highlightSpanCache.get(signature) != null) {
    return;
  }
  if (content.length > _highlightSkipThresholdChars) {
    _highlightSpanCache.put(
      signature,
      TextSpan(
        text: content,
        style: _baseCodeStyleForTheme(
          theme: theme,
          baseColor: baseColor,
          useDarkPalette: useDarkPalette,
        ),
      ),
      content.length,
    );
    return;
  }
  if (!_pendingHighlightWarmups.add(signature)) {
    return;
  }
  void warmup() {
    try {
      _computeHighlightedCodeSpan(
        content: content,
        effectiveLanguage: effectiveLanguage,
        theme: theme,
        baseColor: baseColor,
        useDarkPalette: useDarkPalette,
        signature: signature,
      );
    } finally {
      _pendingHighlightWarmups.remove(signature);
    }
  }

  if (content.length > _highlightDeferThresholdChars) {
    _highlightFrameScheduler.schedule(
      warmup,
      onDropped: () => _pendingHighlightWarmups.remove(signature),
    );
    return;
  }
  warmup();
}

class _HighlightedCodeBlockBuilder extends MarkdownElementBuilder {
  _HighlightedCodeBlockBuilder({
    required ThemeData theme,
    required Color baseColor,
    required bool darkSurface,
    required bool selectable,
  }) : _theme = theme,
       _baseColor = baseColor,
       _darkSurface = darkSurface,
       _selectable = selectable;

  final ThemeData _theme;
  final Color _baseColor;
  final bool _darkSurface;
  final bool _selectable;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final codeElement = _findCodeElement(element);
    final rawCode = (codeElement?.textContent ?? element.textContent)
        .replaceFirst(_trailingNewlineCodeBlockPattern, '');
    final language = _extractCodeLanguage(codeElement);
    final content = rawCode.isEmpty ? ' ' : rawCode;
    if (_looksLikeInlineDiffCodeBlock(language: language, content: content)) {
      return RepaintBoundary(
        child: _InlineCodexDiffPanel(
          content: content,
          language: _languageForInlineDiffHighlight(language),
        ),
      );
    }
    return RepaintBoundary(
      child: _HighlightedCodePanel(
        content: content,
        theme: _theme,
        language: language,
        selectable: _selectable,
        baseColor: _baseColor,
        forceDarkSurface: _darkSurface,
      ),
    );
  }

  md.Element? _findCodeElement(md.Element element) {
    for (final child in element.children ?? const <md.Node>[]) {
      if (child is md.Element && child.tag == 'code') {
        return child;
      }
    }
    return null;
  }
}

const int _inlineDiffPreviewLineLimit = 28;
final RegExp _inlineDiffHunkHeaderPattern = RegExp(
  r'^@@\s+-(\d+)(?:,(\d+))?(?:\s+\+(\d+)(?:,(\d+))?)?',
);

bool _isDiffFenceLanguage(String? language) {
  final value = (language ?? '').trim().toLowerCase();
  return value == 'diff' ||
      value == 'patch' ||
      value == 'udiff' ||
      value == 'unified-diff' ||
      value == 'unified_diff' ||
      value.startsWith('diff-') ||
      value.startsWith('patch-');
}

String? _languageForInlineDiffHighlight(String? language) {
  final value = (language ?? '').trim().toLowerCase();
  if (value.startsWith('diff-')) {
    return _normalizeCodeLanguage(value.substring(5));
  }
  if (value.startsWith('patch-')) {
    return _normalizeCodeLanguage(value.substring(6));
  }
  if (_isDiffFenceLanguage(value)) {
    return null;
  }
  return _normalizeCodeLanguage(value);
}

bool _looksLikeInlineDiffCodeBlock({
  required String? language,
  required String content,
}) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) return false;
  final lines = trimRightNonEmptyLines(const LineSplitter().convert(trimmed));
  if (lines.length < 2) return false;

  var additions = 0;
  var deletions = 0;
  var structural = 0;
  var diffLike = 0;
  var other = 0;
  for (final line in lines) {
    if (line.startsWith('+++') || line.startsWith('---')) {
      structural += 1;
      diffLike += 1;
      continue;
    }
    if (line.startsWith('diff --git ') ||
        line.startsWith('index ') ||
        _inlineDiffHunkHeaderPattern.hasMatch(line)) {
      structural += 1;
      diffLike += 1;
      continue;
    }
    if (line.startsWith('+')) {
      additions += 1;
      diffLike += 1;
      continue;
    }
    if (line.startsWith('-')) {
      deletions += 1;
      diffLike += 1;
      continue;
    }
    if (line.startsWith(' ')) {
      diffLike += 1;
      continue;
    }
    other += 1;
  }

  final hasChanges = additions > 0 && deletions > 0;
  if (_isDiffFenceLanguage(language)) {
    return additions + deletions + structural > 0;
  }
  if (structural > 0) {
    return additions + deletions > 0;
  }
  if (!hasChanges || additions + deletions < 2) {
    return false;
  }
  final toleratedOtherLines = math.max(1, (lines.length * 0.25).floor());
  return diffLike / lines.length >= 0.55 && other <= toleratedOtherLines;
}

List<_CodexDiffLine> _inlineCodexDiffLines(String content) {
  final rawLines = content.replaceFirst(_trailingNewlineCodeBlockPattern, '');
  if (rawLines.trim().isEmpty) {
    return const <_CodexDiffLine>[];
  }
  final lines = const LineSplitter().convert(rawLines);
  final hasUnifiedStructure = lines.any(
    (line) =>
        line.startsWith('diff --git ') ||
        line.startsWith('index ') ||
        line.startsWith('---') ||
        line.startsWith('+++') ||
        _inlineDiffHunkHeaderPattern.hasMatch(line),
  );
  if (!hasUnifiedStructure) {
    return <_CodexDiffLine>[
      for (final line in lines)
        if (line.startsWith('+'))
          _CodexDiffLine(
            kind: _CodexDiffLineKind.addition,
            text: line.length > 1 ? line.substring(1) : '',
          )
        else if (line.startsWith('-'))
          _CodexDiffLine(
            kind: _CodexDiffLineKind.deletion,
            text: line.length > 1 ? line.substring(1) : '',
          )
        else
          _CodexDiffLine(
            kind: _CodexDiffLineKind.context,
            text: line.startsWith(' ') ? line.substring(1) : line,
          ),
    ];
  }
  return _codexDiffLinesFromUnifiedLines(lines);
}

List<_CodexDiffLine> _codexDiffLinesFromUnifiedLines(Iterable<String> diff) {
  final lines = <_CodexDiffLine>[];
  var oldLine = 1;
  var newLine = 1;
  var sawHunk = false;

  for (final rawLine in diff) {
    if (rawLine.startsWith('diff --git ') || rawLine.startsWith('index ')) {
      continue;
    }
    if (rawLine.startsWith('---') || rawLine.startsWith('+++')) {
      continue;
    }
    final hunkMatch = _inlineDiffHunkHeaderPattern.firstMatch(rawLine);
    if (hunkMatch != null) {
      final hunkOldStart = optionalIntFromValue(hunkMatch.group(1)) ?? oldLine;
      final hunkNewStart =
          optionalIntFromValue(hunkMatch.group(3)) ?? hunkOldStart;
      if (sawHunk) {
        final folded = hunkOldStart - oldLine;
        if (folded > 0) {
          lines.add(
            _CodexDiffLine(
              kind: _CodexDiffLineKind.folded,
              foldedCount: folded,
              foldedOldStart: oldLine,
              foldedNewStart: newLine,
            ),
          );
        }
      }
      oldLine = hunkOldStart;
      newLine = hunkNewStart;
      sawHunk = true;
      continue;
    }
    if (rawLine.startsWith('+')) {
      lines.add(
        _CodexDiffLine(
          kind: _CodexDiffLineKind.addition,
          lineNumber: sawHunk ? newLine : null,
          text: rawLine.length > 1 ? rawLine.substring(1) : '',
        ),
      );
      newLine += 1;
      continue;
    }
    if (rawLine.startsWith('-')) {
      lines.add(
        _CodexDiffLine(
          kind: _CodexDiffLineKind.deletion,
          lineNumber: sawHunk ? oldLine : null,
          text: rawLine.length > 1 ? rawLine.substring(1) : '',
        ),
      );
      oldLine += 1;
      continue;
    }
    final text = rawLine.startsWith(' ') ? rawLine.substring(1) : rawLine;
    lines.add(
      _CodexDiffLine(
        kind: _CodexDiffLineKind.context,
        lineNumber: sawHunk ? newLine : null,
        text: text,
      ),
    );
    oldLine += 1;
    newLine += 1;
  }
  return lines;
}

class _InlineCodexDiffPanel extends StatefulWidget {
  const _InlineCodexDiffPanel({required this.content, this.language});

  final String content;
  final String? language;

  @override
  State<_InlineCodexDiffPanel> createState() => _InlineCodexDiffPanelState();
}

class _InlineCodexDiffPanelState extends State<_InlineCodexDiffPanel> {
  static const Duration _actionResetDelay = Duration(milliseconds: 1600);
  static const int _expandedStateCacheLimit = 500;
  static final Map<int, bool> _expandedByContentKey = <int, bool>{};

  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();
  late List<_CodexDiffLine> _lines;
  late int _contentKey;
  late bool _showFull;
  bool _copied = false;
  bool _downloaded = false;
  Timer? _copiedResetTimer;
  Timer? _downloadedResetTimer;

  @override
  void initState() {
    super.initState();
    _rebuildLines(force: true);
  }

  @override
  void didUpdateWidget(covariant _InlineCodexDiffPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content ||
        oldWidget.language != widget.language) {
      _copiedResetTimer?.cancel();
      _downloadedResetTimer?.cancel();
      _copied = false;
      _downloaded = false;
      _rebuildLines();
    }
  }

  @override
  void dispose() {
    _rememberExpandedState();
    _copiedResetTimer?.cancel();
    _downloadedResetTimer?.cancel();
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  void _rebuildLines({bool force = false}) {
    final nextKey = Object.hash(widget.content, widget.language);
    if (!force && _contentKey == nextKey) return;
    if (!force) _rememberExpandedState();
    _contentKey = nextKey;
    _showFull = _expandedByContentKey[nextKey] ?? false;
    _lines = _inlineCodexDiffLines(widget.content);
  }

  void _rememberExpandedState() {
    _expandedByContentKey.remove(_contentKey);
    if (_showFull) {
      _expandedByContentKey[_contentKey] = true;
    }
    while (_expandedByContentKey.length > _expandedStateCacheLimit) {
      _expandedByContentKey.remove(_expandedByContentKey.keys.first);
    }
  }

  void _setShowFull(bool value) {
    if (_showFull == value) return;
    _BubbleHtmlInteractiveScope.maybeOf(context)?.markInteractiveTap();
    setState(() => _showFull = value);
    _rememberExpandedState();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = _CodexDiffPalette.resolve(theme);
    final visibleLimit = math.max(1, _inlineDiffPreviewLineLimit);
    final clipped = !_showFull && _lines.length > visibleLimit;
    final visibleLines = clipped ? _lines.take(visibleLimit).toList() : _lines;
    final hiddenCount = _lines.length - visibleLines.length;
    final maxTextLength = visibleLines.fold<int>(
      0,
      (max, line) => math.max(max, line.text.length),
    );
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final maxBodyHeight = _showFull
        ? math.min(viewportHeight * 0.58, 640.0)
        : 320.0;
    final bodyHeight = codeBodyHeight(
      maxBodyHeight: maxBodyHeight,
      lineCount: visibleLines.length,
    );
    // 只订阅代码主题这一项：整体 watch 会让任意一条设置变更都重建每张代码卡。
    final codeTheme = context.select<SettingsController, EditorCodeTheme>(
      (controller) => controller.editorCodeTheme,
    );
    final brightness = theme.brightness;
    final paletteSignature = palette.signature;
    final baseStyle = openHandCodeBodyTextStyle(theme, color: palette.text);
    final highlighter = _CodeSyntaxHighlighter(
      baseStyle: baseStyle,
      darkSurface: brightness == Brightness.dark,
      codeTheme: codeTheme,
    );
    final diffDecoration = BoxDecoration(
      color: palette.surface,
      borderRadius: const BorderRadius.all(Radius.circular(kOpenHandRadius12)),
      border: Border.all(color: palette.border, width: 0.8),
    );

    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(kOpenHandRadius12)),
      child: DecoratedBox(
        decoration: diffDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _InlineCodexDiffHeader(
              copied: _copied,
              downloaded: _downloaded,
              onCopy: _copyDiff,
              onDownload: () => _downloadDiff(widget.language),
              palette: palette,
            ),
            if (_lines.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Text(
                  _homeNoTextualDiffAvailableLabel(context),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: palette.mutedText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final viewportWidth = constraints.maxWidth.isFinite
                      ? constraints.maxWidth
                      : 640.0;
                  final contentWidth = codeBodyContentWidth(
                    viewportWidth: viewportWidth,
                    maxTextLength: maxTextLength,
                  );
                  return _CodeLineViewport(
                    height: bodyHeight,
                    contentWidth: contentWidth,
                    itemCount: visibleLines.length,
                    verticalController: _verticalController,
                    horizontalController: _horizontalController,
                    itemBuilder: (context, index) {
                      final line = visibleLines[index];
                      return _CodexDiffLineRow(
                        line: line,
                        minWidth: viewportWidth,
                        highlighter: highlighter,
                        language: widget.language,
                        baseStyle: baseStyle,
                        palette: palette,
                        cacheKey:
                            'inline-diff|$_contentKey|'
                            '${brightness.name}|${codeTheme.name}|'
                            '$paletteSignature|$index',
                      );
                    },
                  );
                },
              ),
            if (clipped || (_showFull && _lines.length > visibleLimit))
              _CodexDiffFooter(
                hiddenCount: hiddenCount,
                showFull: _showFull,
                palette: palette,
                onToggle: () => _setShowFull(!_showFull),
              ),
          ],
        ),
      ),
    );
  }

  void _copyDiff() {
    _BubbleHtmlInteractiveScope.maybeOf(context)?.markInteractiveTap();
    _copiedResetTimer?.cancel();
    setState(() => _copied = true);
    replaceOpenHandSnack(
      context,
      openHandLocalizedText(context, zh: 'Diff 内容已复制。', en: 'Diff copied.'),
      kind: OpenHandSnackKind.success,
    );
    _copiedResetTimer = startSafeTimer(_actionResetDelay, () {
      if (!mounted) return;
      setState(() => _copied = false);
    });
    unawaited(_writeDiffToClipboard());
  }

  Future<void> _writeDiffToClipboard() async {
    try {
      await setOpenHandClipboardText(widget.content);
    } catch (error, stack) {
      silentLog('home_code_highlighting', '复制行内差异', error, stack);
      if (!mounted) return;
      _copiedResetTimer?.cancel();
      setState(() => _copied = false);
      replaceOpenHandSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '复制 Diff 失败。',
          en: 'Failed to copy diff.',
        ),
        kind: OpenHandSnackKind.error,
      );
    }
  }

  void _downloadDiff(String? language) {
    _BubbleHtmlInteractiveScope.maybeOf(context)?.markInteractiveTap();
    _downloadedResetTimer?.cancel();
    unawaited(_performDiffDownload(language));
  }

  Future<void> _performDiffDownload(String? language) async {
    final inferredExtension = _getFileExtensionForLanguage(language);
    final extension = inferredExtension == '.txt' ? '.diff' : inferredExtension;
    try {
      final selectedLocation = await getSaveLocation(
        suggestedName: 'diff_block$extension',
      );
      final selectedPath = selectedLocation?.path;
      if (!mounted || selectedPath == null || selectedPath.isEmpty) {
        return;
      }
      await writeFileAtomically(File(selectedPath), widget.content);
      if (!mounted) return;
      setState(() => _downloaded = true);
      replaceOpenHandSnack(
        context,
        openHandLocalizedText(
          context,
          zh: 'Diff 已下载为 ${p.basename(selectedPath)}',
          en: 'Diff downloaded as ${p.basename(selectedPath)}',
        ),
        kind: OpenHandSnackKind.success,
      );
      _downloadedResetTimer = startSafeTimer(_actionResetDelay, () {
        if (!mounted) return;
        setState(() => _downloaded = false);
      });
    } catch (error, stack) {
      silentLog('home_code_highlighting', '下载行内差异', error, stack);
      if (!mounted) return;
      replaceOpenHandSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '下载 Diff 失败。',
          en: 'Download failed.',
        ),
        kind: OpenHandSnackKind.error,
      );
    }
  }
}

class _InlineCodexDiffHeader extends StatelessWidget {
  const _InlineCodexDiffHeader({
    required this.copied,
    required this.downloaded,
    required this.onCopy,
    required this.onDownload,
    required this.palette,
  });

  final bool copied;
  final bool downloaded;
  final VoidCallback onCopy;
  final VoidCallback onDownload;
  final _CodexDiffPalette palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.footerSurface,
        border: Border(bottom: BorderSide(color: palette.footerBorder)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Row(
          children: [
            _InlineDiffPill(
              label: 'diff',
              icon: Icons.difference_rounded,
              backgroundColor: palette.foldedBackground,
              foregroundColor: palette.mutedText,
            ),
            const Spacer(),
            _InlineDiffPill(
              label: copied ? openHandCopiedLabel(context) : openHandCopyLabel(context),
              icon: copied ? Icons.check_rounded : Icons.content_copy_rounded,
              backgroundColor: palette.footerBorder,
              foregroundColor: palette.footerForeground,
              onTap: onCopy,
            ),
            kOpenHandHGap8,
            _InlineDiffPill(
              label: openHandLocalizedText(
                context,
                zh: downloaded ? '已下载' : '下载',
                en: downloaded ? 'Downloaded' : 'Download',
              ),
              icon: downloaded ? Icons.check_rounded : Icons.download_rounded,
              backgroundColor: palette.footerBorder,
              foregroundColor: palette.footerForeground,
              onTap: onDownload,
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineDiffPill extends StatelessWidget {
  const _InlineDiffPill({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: foregroundColor),
          kOpenHandHGap6,
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    final decoration = BoxDecoration(
      color: backgroundColor,
      borderRadius: kOpenHandPillBorderRadius,
    );
    if (onTap == null) {
      return DecoratedBox(decoration: decoration, child: child);
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: kOpenHandPillBorderRadius,
        child: Ink(decoration: decoration, child: child),
      ),
    );
  }
}

class _HighlightedCodePanel extends StatefulWidget {
  const _HighlightedCodePanel({
    required this.content,
    required this.theme,
    required this.baseColor,
    required this.selectable,
    this.language,
    this.forceDarkSurface = false,
    this.accentColor,
    this.wrapLines = false,
    this.showToolbar = true,
    this.internalVerticalScroll = false,
  });

  final String content;
  final ThemeData theme;
  final String? language;
  final Color baseColor;
  final bool selectable;
  final bool forceDarkSurface;
  final Color? accentColor;
  final bool wrapLines;
  final bool showToolbar;
  final bool internalVerticalScroll;

  @override
  State<_HighlightedCodePanel> createState() => _HighlightedCodePanelState();
}

class _HighlightedCodePanelState extends State<_HighlightedCodePanel> {
  static const Duration _codeActionResetDelay = Duration(milliseconds: 1600);

  TextSpan? _highlightedSpan;
  int? _highlightSignature;
  bool _copied = false;
  bool _downloaded = false;
  bool _copying = false;
  bool _downloading = false;
  bool _mermaidViewActive = false;
  Timer? _copiedResetTimer;
  Timer? _downloadedResetTimer;
  _CodeBlockPalette? _cachedPalette;
  int? _cachedPaletteSignature;
  bool _highlightScheduled = false;
  bool _highlightIsPlaceholder = false;
  ScrollController? _internalScrollController;
  TranscriptScrollActivity? _scrollActivity;
  bool _highlightPendingAfterScroll = false;
  int _lineCount = 1;

  ScrollController get _effectiveInternalScrollController {
    return _internalScrollController ??= ScrollController();
  }

  @override
  void initState() {
    super.initState();
    _lineCount = _countLines(widget.content);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final activity = _maybeTranscriptScrollActivityOf(context);
    if (!identical(activity, _scrollActivity)) {
      _scrollActivity?.removeListener(_handleScrollActivityChanged);
      _scrollActivity = activity;
      activity?.addListener(_handleScrollActivityChanged);
    }
    _ensureHighlightedSpan();
  }

  @override
  void didUpdateWidget(covariant _HighlightedCodePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content ||
        oldWidget.language != widget.language ||
        oldWidget.selectable != widget.selectable ||
        oldWidget.baseColor != widget.baseColor ||
        oldWidget.forceDarkSurface != widget.forceDarkSurface ||
        oldWidget.showToolbar != widget.showToolbar ||
        oldWidget.internalVerticalScroll != widget.internalVerticalScroll ||
        oldWidget.theme.brightness != widget.theme.brightness ||
        oldWidget.theme.textTheme.bodyMedium?.fontSize !=
            widget.theme.textTheme.bodyMedium?.fontSize ||
        oldWidget.theme.textTheme.bodyMedium?.fontFamily !=
            widget.theme.textTheme.bodyMedium?.fontFamily ||
        oldWidget.theme.textTheme.bodyMedium?.height !=
            widget.theme.textTheme.bodyMedium?.height) {
      _highlightedSpan = null;
      _highlightSignature = null;
      _highlightIsPlaceholder = false;
    }
    if (oldWidget.content != widget.content) {
      _lineCount = _countLines(widget.content);
      _copiedResetTimer?.cancel();
      _copied = false;
      _downloadedResetTimer?.cancel();
      _downloaded = false;
    }
    _ensureHighlightedSpan();
  }

  @override
  void dispose() {
    _scrollActivity?.removeListener(_handleScrollActivityChanged);
    _scrollActivity = null;
    _copiedResetTimer?.cancel();
    _downloadedResetTimer?.cancel();
    _internalScrollController?.dispose();
    super.dispose();
  }

  void _handleScrollActivityChanged() {
    final activity = _scrollActivity;
    if (activity == null || !mounted || activity.value) {
      return;
    }
    if (!_highlightPendingAfterScroll || _highlightScheduled) {
      return;
    }
    _highlightPendingAfterScroll = false;
    _scheduleDeferredHighlight();
  }

  void _toggleMermaidView() {
    _BubbleHtmlInteractiveScope.maybeOf(context)?.markInteractiveTap();
    setState(() {
      _mermaidViewActive = !_mermaidViewActive;
    });
  }

  int _countLines(String source) {
    var count = 1;
    for (final unit in source.codeUnits) {
      if (unit == 0x0A) count += 1;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final effectiveLanguage = _normalizeCodeLanguage(widget.language);
    final displayLanguage =
        effectiveLanguage == null || effectiveLanguage == 'plaintext'
        ? openHandPlainTextLabel(context)
        : effectiveLanguage;
    final useDarkPalette =
        widget.forceDarkSurface || widget.theme.brightness == Brightness.dark;
    final paletteSignature = Object.hash(
      widget.theme.colorScheme.primary.toARGB32(),
      widget.theme.brightness.index,
      useDarkPalette,
      widget.accentColor?.toARGB32(),
    );
    if (_cachedPalette == null || _cachedPaletteSignature != paletteSignature) {
      _cachedPalette = _CodeBlockPalette.fromTheme(
        widget.theme,
        useDarkPalette: useDarkPalette,
        accentColor: widget.accentColor,
      );
      _cachedPaletteSignature = paletteSignature;
    }
    final palette = _cachedPalette!;
    final copyLabel = _copied ? openHandCopiedLabel(context) : openHandCopyLabel(context);
    final downloadLabel = openHandLocalizedText(
      context,
      zh: _downloaded ? '已下载' : '下载',
      en: _downloaded ? 'Downloaded' : 'Download',
    );
    final runLabel = openHandLocalizedText(context, zh: '运行', en: 'Run');
    final isHtmlLanguage = _isHtmlLanguage(effectiveLanguage);
    final isMermaidLanguage = _isMermaidLanguage(effectiveLanguage);
    final viewLabel = openHandLocalizedText(
      context,
      zh: _mermaidViewActive ? '代码' : '视图',
      en: _mermaidViewActive ? 'Code' : 'View',
    );
    final lineCountLabel = openHandLocalizedText(
      context,
      zh: '$_lineCount 行',
      en: '$_lineCount lines',
    );
    return Container(
      decoration: BoxDecoration(
        color: palette.containerColor,
        borderRadius: _markdownCodeBlockRadius,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: palette.shadowColor,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: _markdownCodeBlockRadius,
        border: Border.all(color: palette.borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showToolbar)
            Container(
              padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
              decoration: BoxDecoration(
                color: palette.headerColor,
                border: Border(bottom: BorderSide(color: palette.dividerColor)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          Icons.code_rounded,
                          size: 15,
                          color: palette.badgeTextColor.withValues(alpha: 0.8),
                        ),
                        kOpenHandHGap7,
                        Flexible(
                          child: Text(
                            '$displayLanguage · $lineCountLabel',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: widget.theme.textTheme.labelMedium?.copyWith(
                              color: palette.badgeTextColor.withValues(
                                alpha: 0.82,
                              ),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isMermaidLanguage) ...[
                    _buildToolbarAction(
                      label: viewLabel,
                      icon: _mermaidViewActive
                          ? Icons.code_rounded
                          : Icons.visibility_outlined,
                      palette: palette,
                      active: _mermaidViewActive,
                      onTap: _toggleMermaidView,
                    ),
                    kOpenHandHGap4,
                  ],
                  _buildToolbarAction(
                    label: copyLabel,
                    icon: _copied
                        ? Icons.check_rounded
                        : Icons.content_copy_rounded,
                    palette: palette,
                    active: _copied,
                    onTap: () {
                      _BubbleHtmlInteractiveScope.maybeOf(
                        context,
                      )?.markInteractiveTap();
                      _copyCodeBlock();
                    },
                  ),
                  kOpenHandHGap4,
                  _buildToolbarAction(
                    label: downloadLabel,
                    icon: _downloaded
                        ? Icons.check_rounded
                        : Icons.download_rounded,
                    palette: palette,
                    active: _downloaded,
                    onTap: () {
                      _BubbleHtmlInteractiveScope.maybeOf(
                        context,
                      )?.markInteractiveTap();
                      _downloadCodeBlock(effectiveLanguage);
                    },
                  ),
                  if (isHtmlLanguage) ...[
                    kOpenHandHGap4,
                    _buildToolbarAction(
                      label: runLabel,
                      icon: Icons.play_arrow_rounded,
                      palette: palette,
                      onTap: () {
                        _BubbleHtmlInteractiveScope.maybeOf(
                          context,
                        )?.markInteractiveTap();
                        _runHtmlPreview();
                      },
                    ),
                  ],
                ],
              ),
            ),
          _buildPanelBody(palette, isMermaidLanguage),
        ],
      ),
    );
  }

  Widget _buildPanelBody(_CodeBlockPalette palette, bool isMermaidLanguage) {
    final body = isMermaidLanguage && _mermaidViewActive
        // 外层 Column 是 CrossAxisAlignment.start，子节点只拿到松约束。
        // _MermaidDiagramView 内层 Column 用 stretch，但实际宽度按
        // intrinsic 算 → 工具栏 Row 决定，WebView 视口塌成 0 宽，
        // 内部 stage 自然 0x0，pointer 永远命中不到。强制撑满父宽即可。
        ? SizedBox(
            width: double.infinity,
            child: _MermaidDiagramView(
              source: widget.content,
              palette: palette,
            ),
          )
        : _buildCodeBody(palette);
    final padding = EdgeInsets.all(widget.showToolbar ? 14 : 16);
    if (!widget.internalVerticalScroll) {
      return Padding(padding: padding, child: body);
    }
    final scrollController = _effectiveInternalScrollController;
    return Expanded(
      child: PrimaryScrollController.none(
        child: OpenHandSafeScrollbar(
          controller: scrollController,
          child: SingleChildScrollView(
            controller: scrollController,
            primary: false,
            padding: padding,
            physics: openHandDialogAwareScrollPhysics(context),
            child: body,
          ),
        ),
      ),
    );
  }

  Widget _buildCodeBody(_CodeBlockPalette palette) {
    // 确保 span 不为 null：如果 _highlightedSpan 仍为 null（理论上不应该，
    // 因为 didChangeDependencies 已经调用了 _ensureHighlightedSpan），
    // 回退到直接渲染纯文本，避免显示空白。
    final span =
        _highlightedSpan ??
        TextSpan(
          text: widget.content,
          style: _baseStyleForCurrentTheme(
            widget.forceDarkSurface ||
                widget.theme.brightness == Brightness.dark,
          ),
        );
    // 大代码块（> 8KB）使用 RichText 而非 SelectableText，避免
    // EditableText 层在大 TextSpan 上的 O(n) layout 开销。
    final useSelectable = widget.selectable && widget.content.length <= 8192;
    if (widget.wrapLines) {
      return useSelectable ? SelectableText.rich(span) : RichText(text: span);
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: useSelectable ? SelectableText.rich(span) : RichText(text: span),
    );
  }

  void _ensureHighlightedSpan() {
    final effectiveLanguage = _normalizeCodeLanguage(widget.language);
    final useDarkPalette =
        widget.forceDarkSurface || widget.theme.brightness == Brightness.dark;
    final signature = _highlightSignatureFor(
      effectiveLanguage: effectiveLanguage,
      useDarkPalette: useDarkPalette,
    );
    if (_highlightedSpan != null &&
        _highlightSignature == signature &&
        !_highlightIsPlaceholder) {
      return;
    }
    // Fast path: try the global LRU cache. Identical code blocks rendered
    // multiple times across the transcript reuse the same parsed TextSpan
    // instead of re-running the highlight tokenizer (the dominant cost
    // when opening a large session).
    final cached = _highlightSpanCache.get(signature);
    if (cached != null) {
      _highlightedSpan = cached;
      _highlightSignature = signature;
      _highlightIsPlaceholder = false;
      return;
    }
    // Skip syntax highlighting entirely for very large code blocks. The
    // `package:highlight` parser is single-pass but allocates one node per
    // token, which becomes the dominant frame cost for >~80KB code blocks
    // and produces visible jank/ANR when opening sessions that contain
    // long log dumps or generated source files. Plain text rendering keeps
    // the transcript responsive; users can still copy / download the code.
    if (widget.content.length > _highlightSkipThresholdChars) {
      _highlightedSpan = TextSpan(
        text: widget.content,
        style: _baseStyleForCurrentTheme(useDarkPalette),
      );
      _highlightSignature = signature;
      _highlightIsPlaceholder = false;
      return;
    }
    // For blocks above the defer threshold, defer highlight via the global
    // frame-spread scheduler. When a message with N code blocks expands,
    // each block registers its highlight task with the scheduler, which
    // executes at most 1 per frame instead of jamming them all into one.
    // The LRU cache ensures that on second expand (user's observation: "再次
    // 打开折叠消息卡片，卡顿情况会减少很多"), the highlight is instant.
    if (widget.content.length > _highlightDeferThresholdChars) {
      _highlightedSpan = TextSpan(
        text: widget.content,
        style: _baseStyleForCurrentTheme(useDarkPalette),
      );
      _highlightSignature = signature;
      _highlightIsPlaceholder = true;
      if (_scrollActivity?.value ?? false) {
        _highlightPendingAfterScroll = true;
      } else {
        _highlightPendingAfterScroll = false;
        _scheduleDeferredHighlight();
      }
      return;
    }
    _highlightPendingAfterScroll = false;
    _highlightedSpan = _runHighlight(
      effectiveLanguage,
      useDarkPalette,
      signature,
    );
    _highlightSignature = signature;
    _highlightIsPlaceholder = false;
  }

  void _scheduleDeferredHighlight() {
    if (_highlightScheduled) {
      return;
    }
    _highlightScheduled = true;
    _highlightFrameScheduler.schedule(
      () {
        if (!mounted) return;
        if (_scrollActivity?.value ?? false) {
          _highlightScheduled = false;
          _highlightPendingAfterScroll = true;
          return;
        }
        _highlightScheduled = false;
        _highlightPendingAfterScroll = false;
        final currentEffectiveLanguage = _normalizeCodeLanguage(
          widget.language,
        );
        final currentUseDarkPalette =
            widget.forceDarkSurface ||
            widget.theme.brightness == Brightness.dark;
        final currentSignature = _highlightSignatureFor(
          effectiveLanguage: currentEffectiveLanguage,
          useDarkPalette: currentUseDarkPalette,
        );
        if (_highlightedSpan != null &&
            _highlightSignature == currentSignature &&
            !_highlightIsPlaceholder) {
          return;
        }
        final span = widget.content.length > _highlightSkipThresholdChars
            ? TextSpan(
                text: widget.content,
                style: _baseStyleForCurrentTheme(currentUseDarkPalette),
              )
            : _highlightSpanCache.get(currentSignature) ??
                  _runHighlight(
                    currentEffectiveLanguage,
                    currentUseDarkPalette,
                    currentSignature,
                  );
        if (!mounted) return;
        setState(() {
          _highlightedSpan = span;
          _highlightSignature = currentSignature;
          _highlightIsPlaceholder = false;
        });
      },
      priority: true,
      isValid: () => mounted,
      onDropped: () {
        _highlightScheduled = false;
        _highlightPendingAfterScroll = false;
        _highlightIsPlaceholder = false;
      },
    );
  }

  int _highlightSignatureFor({
    required String? effectiveLanguage,
    required bool useDarkPalette,
  }) {
    return _highlightSignatureForInputs(
      content: widget.content,
      effectiveLanguage: effectiveLanguage,
      baseColor: widget.baseColor,
      useDarkPalette: useDarkPalette,
      theme: widget.theme,
    );
  }

  TextStyle _baseStyleForCurrentTheme(bool useDarkPalette) {
    return _baseCodeStyleForTheme(
      theme: widget.theme,
      baseColor: widget.baseColor,
      useDarkPalette: useDarkPalette,
    );
  }

  TextSpan _runHighlight(
    String? effectiveLanguage,
    bool useDarkPalette,
    int signature,
  ) {
    return _computeHighlightedCodeSpan(
      content: widget.content,
      effectiveLanguage: effectiveLanguage,
      theme: widget.theme,
      baseColor: widget.baseColor,
      useDarkPalette: useDarkPalette,
      signature: signature,
    );
  }

  Widget _buildToolbarAction({
    required String label,
    required IconData icon,
    required _CodeBlockPalette palette,
    required VoidCallback onTap,
    bool active = false,
  }) {
    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: kOpenHandPillBorderRadius,
        child: Ink(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: active ? palette.badgeColor : palette.actionColor,
            borderRadius: kOpenHandPillBorderRadius,
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: openHandMotionDuration(
                context,
                const Duration(milliseconds: 160),
              ),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
              ),
              child: Icon(
                icon,
                key: ValueKey<IconData>(icon),
                size: 16,
                color: active
                    ? palette.badgeTextColor
                    : palette.actionTextColor,
              ),
            ),
          ),
        ),
      ),
    );
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: MicroPressFeedback(scale: 0.9, child: button),
      ),
    );
  }

  void _copyCodeBlock() {
    _copiedResetTimer?.cancel();
    unawaited(_performCodeBlockCopy());
  }

  Future<void> _performCodeBlockCopy() async {
    if (_copying) return;
    _copying = true;
    try {
      await setOpenHandClipboardText(widget.content);
      if (!mounted) return;
      setState(() => _copied = true);
      replaceOpenHandSnack(
        context,
        openHandLocalizedText(context, zh: '代码块内容已复制。', en: 'Code copied.'),
        kind: OpenHandSnackKind.success,
      );
      _copiedResetTimer = startSafeTimer(_codeActionResetDelay, () {
        if (!mounted) return;
        setState(() => _copied = false);
      });
    } catch (error, stack) {
      silentLog('home_code_highlighting', '复制代码块', error, stack);
      if (!mounted) return;
      _copiedResetTimer?.cancel();
      if (_copied) setState(() => _copied = false);
      replaceOpenHandSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '复制代码块失败。',
          en: 'Failed to copy code.',
        ),
        kind: OpenHandSnackKind.error,
      );
    } finally {
      _copying = false;
    }
  }

  void _downloadCodeBlock(String? language) {
    _downloadedResetTimer?.cancel();
    unawaited(_performCodeBlockDownload(language));
  }

  Future<void> _performCodeBlockDownload(String? language) async {
    if (_downloading) return;
    _downloading = true;
    final extension = _getFileExtensionForLanguage(language);
    final suggestedName = 'code_block$extension';
    try {
      final selectedLocation = await getSaveLocation(
        suggestedName: suggestedName,
      );
      final selectedPath = selectedLocation?.path;
      if (!mounted || selectedPath == null || selectedPath.isEmpty) {
        return;
      }
      final file = File(selectedPath);
      await writeFileAtomically(file, widget.content);
      if (!mounted) {
        return;
      }
      setState(() {
        _downloaded = true;
      });
      replaceOpenHandSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '代码已下载为 ${p.basename(selectedPath)}',
          en: 'Code downloaded as ${p.basename(selectedPath)}',
        ),
        kind: OpenHandSnackKind.success,
      );
      _downloadedResetTimer = startSafeTimer(_codeActionResetDelay, () {
        if (!mounted) {
          return;
        }
        setState(() {
          _downloaded = false;
        });
      });
    } catch (error, stack) {
      silentLog('home_code_highlighting', '下载代码块', error, stack);
      if (!mounted) {
        return;
      }
      replaceOpenHandSnack(
        context,
        openHandLocalizedText(context, zh: '下载失败。', en: 'Download failed.'),
        kind: OpenHandSnackKind.error,
      );
    } finally {
      _downloading = false;
    }
  }

  void _runHtmlPreview() {
    showAnimatedDialog<void>(
      context: context,
      builder: (dialogContext) =>
          _HtmlPreviewDialog(htmlContent: widget.content, theme: widget.theme),
    );
  }
}

class _CodeBlockPalette {
  factory _CodeBlockPalette.fromTheme(
    ThemeData theme, {
    required bool useDarkPalette,
    Color? accentColor,
  }) {
    final colorScheme = theme.colorScheme;
    final tint = accentColor ?? colorScheme.primary;
    if (useDarkPalette) {
      final darkScheme = theme.brightness == Brightness.dark
          ? colorScheme
          : () {
              final tintValue = tint.toARGB32();
              if (_cachedDarkScheme != null &&
                  _cachedDarkSchemeTintValue == tintValue) {
                return _cachedDarkScheme!;
              }
              final scheme = ColorScheme.fromSeed(
                seedColor: tint,
                brightness: Brightness.dark,
                dynamicSchemeVariant: DynamicSchemeVariant.expressive,
              );
              _cachedDarkScheme = scheme;
              _cachedDarkSchemeTintValue = tintValue;
              return scheme;
            }();
      return _CodeBlockPalette(
        containerColor: Color.alphaBlend(
          tint.withValues(alpha: 0.05),
          darkScheme.surfaceContainerHigh,
        ),
        borderColor: darkScheme.outlineVariant.withValues(alpha: 0.78),
        headerColor: Color.alphaBlend(
          tint.withValues(alpha: 0.08),
          darkScheme.surfaceContainerHighest,
        ),
        dividerColor: darkScheme.outlineVariant.withValues(alpha: 0.52),
        bodyColor: Color.alphaBlend(
          Colors.black.withValues(alpha: 0.14),
          darkScheme.surfaceContainerLow,
        ),
        badgeColor: Color.alphaBlend(
          tint.withValues(alpha: 0.16),
          darkScheme.surfaceContainerHighest,
        ),
        badgeTextColor: darkScheme.onSurface,
        actionColor: Color.alphaBlend(
          tint.withValues(alpha: 0.08),
          darkScheme.surfaceContainerHighest,
        ),
        actionTextColor: darkScheme.onSurface,
        shadowColor: Colors.black.withValues(alpha: 0.18),
      );
    }
    return _CodeBlockPalette(
      containerColor: Color.alphaBlend(
        tint.withValues(alpha: 0.025),
        colorScheme.surfaceContainerLow,
      ),
      borderColor: Color.alphaBlend(
        tint.withValues(alpha: 0.08),
        colorScheme.outlineVariant.withValues(alpha: 0.85),
      ),
      headerColor: Color.alphaBlend(
        tint.withValues(alpha: 0.05),
        colorScheme.surfaceContainer,
      ),
      dividerColor: colorScheme.outlineVariant.withValues(alpha: 0.62),
      bodyColor: Colors.white.withValues(alpha: 0.45),
      badgeColor: Color.alphaBlend(
        tint.withValues(alpha: 0.08),
        colorScheme.surface,
      ),
      badgeTextColor: colorScheme.onSurface,
      actionColor: Color.alphaBlend(
        colorScheme.surface.withValues(alpha: 0.4),
        colorScheme.surfaceContainerHighest,
      ),
      actionTextColor: colorScheme.onSurface,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.03),
    );
  }
  const _CodeBlockPalette({
    required this.containerColor,
    required this.borderColor,
    required this.headerColor,
    required this.dividerColor,
    required this.bodyColor,
    required this.badgeColor,
    required this.badgeTextColor,
    required this.actionColor,
    required this.actionTextColor,
    required this.shadowColor,
  });

  // 缓存开销较高的深色动态配色。
  static ColorScheme? _cachedDarkScheme;
  static int? _cachedDarkSchemeTintValue;

  final Color containerColor;
  final Color borderColor;
  final Color headerColor;
  final Color dividerColor;
  final Color bodyColor;
  final Color badgeColor;
  final Color badgeTextColor;
  final Color actionColor;
  final Color actionTextColor;
  final Color shadowColor;
}

final RegExp _markdownCodeFencePattern = RegExp(r'(^|\n)[ ]{0,3}(`{3,}|~{3,})');

bool _containsMarkdownCodeFence(String source) {
  return _markdownCodeFencePattern.hasMatch(source);
}

bool _canRenderMarkdownAsPlainText(String source) {
  final normalized = source.trim();
  if (normalized.isEmpty) {
    return true;
  }
  if (_containsMarkdownCodeFence(normalized)) {
    return false;
  }
  if (normalized.contains('/') || normalized.contains('\\')) {
    return false;
  }
  return !_markdownStructuralPattern.hasMatch(normalized);
}

final RegExp _fencedCodeBlockPattern = RegExp(
  r'^[ ]{0,3}((`{3,}|~{3,}))[^\n]*$',
);

String _closeUnterminatedFencedCodeBlock(String source) {
  final fencePattern = _fencedCodeBlockPattern;
  String? openFence;
  String? openFenceMarker;
  for (final line in const LineSplitter().convert(source)) {
    final match = fencePattern.firstMatch(line);
    if (match == null) {
      continue;
    }
    final delimiter = match.group(1)!;
    final marker = delimiter[0];
    if (openFence == null) {
      openFence = delimiter;
      openFenceMarker = marker;
      continue;
    }
    if (marker == openFenceMarker && delimiter.length >= openFence.length) {
      openFence = null;
      openFenceMarker = null;
    }
  }
  if (openFence == null) {
    return source;
  }
  final separator = source.isEmpty || source.endsWith('\n') ? '' : '\n';
  return '$source$separator$openFence';
}

// Code editor colour themes
/// Returns a set of token colours for the given [theme] and [darkSurface] flag.
({
  Color comment,
  Color keyword,
  Color string,
  Color number,
  Color title,
  Color type,
  Color meta,
  Color operator,
})
_codeThemeColors(EditorCodeTheme theme, bool darkSurface) {
  return switch (theme) {
    EditorCodeTheme.materialYou => (
      comment: darkSurface ? const Color(0xFF7DD3A7) : const Color(0xFF5B6472),
      keyword: darkSurface ? const Color(0xFFF9A8D4) : const Color(0xFF0B57D0),
      string: darkSurface ? const Color(0xFFFDE68A) : const Color(0xFFB42318),
      number: darkSurface ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8),
      title: darkSurface ? const Color(0xFF67E8F9) : const Color(0xFF7C3AED),
      type: darkSurface ? const Color(0xFFC4B5FD) : const Color(0xFF8A3C00),
      meta: darkSurface ? const Color(0xFFCBD5E1) : const Color(0xFF0F4C81),
      operator: darkSurface ? const Color(0xFFE2E8F0) : const Color(0xFF1F2937),
    ),
    EditorCodeTheme.monokai => (
      comment: darkSurface ? const Color(0xFF75715E) : const Color(0xFF8E908C),
      keyword: darkSurface ? const Color(0xFFF92672) : const Color(0xFFC7254E),
      string: darkSurface ? const Color(0xFFE6DB74) : const Color(0xFF718C00),
      number: darkSurface ? const Color(0xFFAE81FF) : const Color(0xFF8959A8),
      title: darkSurface ? const Color(0xFFA6E22E) : const Color(0xFF4271AE),
      type: darkSurface ? const Color(0xFF66D9EF) : const Color(0xFFC82828),
      meta: darkSurface ? const Color(0xFFFD971F) : const Color(0xFFEAB700),
      operator: darkSurface ? const Color(0xFFF8F8F2) : const Color(0xFF3E3D32),
    ),
    EditorCodeTheme.solarized => (
      comment: darkSurface ? const Color(0xFF586E75) : const Color(0xFF93A1A1),
      keyword: darkSurface ? const Color(0xFF859900) : const Color(0xFF859900),
      string: darkSurface ? const Color(0xFF2AA198) : const Color(0xFF2AA198),
      number: darkSurface ? const Color(0xFFD33682) : const Color(0xFFD33682),
      title: darkSurface ? const Color(0xFF268BD2) : const Color(0xFF268BD2),
      type: darkSurface ? const Color(0xFFB58900) : const Color(0xFFB58900),
      meta: darkSurface ? const Color(0xFF6C71C4) : const Color(0xFF6C71C4),
      operator: darkSurface ? const Color(0xFF839496) : const Color(0xFF657B83),
    ),
    EditorCodeTheme.oneDark => (
      comment: darkSurface ? const Color(0xFF5C6370) : const Color(0xFFA0A1A7),
      keyword: darkSurface ? const Color(0xFFC678DD) : const Color(0xFFA626A4),
      string: darkSurface ? const Color(0xFF98C379) : const Color(0xFF50A14F),
      number: darkSurface ? const Color(0xFFD19A66) : const Color(0xFF986801),
      title: darkSurface ? const Color(0xFF61AFEF) : const Color(0xFF4078F2),
      type: darkSurface ? const Color(0xFFE5C07B) : const Color(0xFFC18401),
      meta: darkSurface ? const Color(0xFF56B6C2) : const Color(0xFF0184BC),
      operator: darkSurface ? const Color(0xFFABB2BF) : const Color(0xFF383A42),
    ),
    EditorCodeTheme.github => (
      comment: darkSurface ? const Color(0xFF8B949E) : const Color(0xFF6A737D),
      keyword: darkSurface ? const Color(0xFFFF7B72) : const Color(0xFFD73A49),
      string: darkSurface ? const Color(0xFFA5D6FF) : const Color(0xFF032F62),
      number: darkSurface ? const Color(0xFF79C0FF) : const Color(0xFF005CC5),
      title: darkSurface ? const Color(0xFFD2A8FF) : const Color(0xFF6F42C1),
      type: darkSurface ? const Color(0xFFFFA657) : const Color(0xFFE36209),
      meta: darkSurface ? const Color(0xFF7EE787) : const Color(0xFF22863A),
      operator: darkSurface ? const Color(0xFFC9D1D9) : const Color(0xFF24292E),
    ),
    EditorCodeTheme.dracula => (
      comment: darkSurface ? const Color(0xFF6272A4) : const Color(0xFF8E908C),
      keyword: darkSurface ? const Color(0xFFFF79C6) : const Color(0xFFD73A49),
      string: darkSurface ? const Color(0xFFF1FA8C) : const Color(0xFF50A14F),
      number: darkSurface ? const Color(0xFFBD93F9) : const Color(0xFF6F42C1),
      title: darkSurface ? const Color(0xFF50FA7B) : const Color(0xFF22863A),
      type: darkSurface ? const Color(0xFF8BE9FD) : const Color(0xFF005CC5),
      meta: darkSurface ? const Color(0xFFFFB86C) : const Color(0xFFE36209),
      operator: darkSurface ? const Color(0xFFF8F8F2) : const Color(0xFF24292E),
    ),
  };
}

class _CodeSyntaxHighlighter {
  _CodeSyntaxHighlighter({
    required TextStyle baseStyle,
    required bool darkSurface,
    EditorCodeTheme codeTheme = EditorCodeTheme.materialYou,
  }) : _baseStyle = baseStyle {
    final colors = _codeThemeColors(codeTheme, darkSurface);
    _commentStyle = baseStyle.copyWith(
      color: colors.comment,
      fontStyle: FontStyle.italic,
    );
    _keywordStyle = baseStyle.copyWith(
      color: colors.keyword,
      fontWeight: FontWeight.w700,
    );
    _stringStyle = baseStyle.copyWith(color: colors.string);
    _numberStyle = baseStyle.copyWith(color: colors.number);
    _titleStyle = baseStyle.copyWith(
      color: colors.title,
      fontWeight: FontWeight.w700,
    );
    _typeStyle = baseStyle.copyWith(
      color: colors.type,
      fontWeight: FontWeight.w600,
    );
    _metaStyle = baseStyle.copyWith(color: colors.meta);
    _operatorStyle = baseStyle.copyWith(color: colors.operator);
  }

  final TextStyle _baseStyle;

  // Pre-computed styles — avoids hundreds of copyWith() calls per code block.
  late final TextStyle _commentStyle;
  late final TextStyle _keywordStyle;
  late final TextStyle _stringStyle;
  late final TextStyle _numberStyle;
  late final TextStyle _titleStyle;
  late final TextStyle _typeStyle;
  late final TextStyle _metaStyle;
  late final TextStyle _operatorStyle;

  // Class-name → style fast lookup.
  static const Set<String> _commentClasses = {'comment', 'quote'};
  static const Set<String> _keywordClasses = {
    'keyword',
    'selector-tag',
    'meta-keyword',
    'doctag',
  };
  static const Set<String> _stringClasses = {
    'string',
    'regexp',
    'attribute',
    'template-variable',
  };
  static const Set<String> _numberClasses = {
    'number',
    'literal',
    'symbol',
    'bullet',
  };
  static const Set<String> _titleClasses = {
    'title',
    'function',
    'section',
    'title.function_',
    'title.class_',
  };
  static const Set<String> _typeClasses = {
    'type',
    'built_in',
    'class',
    'params',
    'variable',
    'selector-id',
    'selector-class',
    'selector-attr',
    'selector-pseudo',
    'property',
  };
  static const Set<String> _metaClasses = {'meta', 'attr', 'tag', 'name'};
  static const Set<String> _operatorClasses = {'operator', 'punctuation'};

  TextSpan build(
    String source, {
    String? language,
    bool allowAutoDetection = false,
  }) {
    final normalizedLanguage = _normalizeCodeLanguage(language);
    if (normalizedLanguage == 'plaintext' ||
        normalizedLanguage == null && !allowAutoDetection) {
      return TextSpan(text: source, style: _baseStyle);
    }
    try {
      final parsed = highlight.highlight.parse(
        source,
        language: normalizedLanguage,
        autoDetection: allowAutoDetection && normalizedLanguage == null,
      );
      return TextSpan(
        style: _baseStyle,
        children: _buildHighlightedNodes(parsed.nodes),
      );
    } catch (_) {
      if (allowAutoDetection && normalizedLanguage != null) {
        try {
          final parsed = highlight.highlight.parse(source, autoDetection: true);
          return TextSpan(
            style: _baseStyle,
            children: _buildHighlightedNodes(parsed.nodes),
          );
        } catch (_) {
          // Fall through to plain text rendering.
        }
      }
      return TextSpan(text: source, style: _baseStyle);
    }
  }

  List<InlineSpan> _buildHighlightedNodes(List<highlight.Node>? nodes) {
    if (nodes == null || nodes.isEmpty) {
      return <InlineSpan>[TextSpan(style: _baseStyle)];
    }
    final spans = <InlineSpan>[];
    for (final node in nodes) {
      if (node.value != null) {
        spans.add(
          TextSpan(
            text: node.value,
            style: node.className == null
                ? null
                : _styleForClass(node.className),
          ),
        );
        continue;
      }
      spans.add(
        TextSpan(
          style: node.className == null ? null : _styleForClass(node.className),
          children: _buildHighlightedNodes(node.children),
        ),
      );
    }
    return spans;
  }

  TextStyle _styleForClass(String? className) {
    final classes = (className ?? '').split(' ');
    for (final cls in classes) {
      if (_commentClasses.contains(cls)) return _commentStyle;
      if (_keywordClasses.contains(cls)) return _keywordStyle;
      if (_stringClasses.contains(cls)) return _stringStyle;
      if (_numberClasses.contains(cls)) return _numberStyle;
      if (_titleClasses.contains(cls)) return _titleStyle;
      if (_typeClasses.contains(cls)) return _typeStyle;
      if (_metaClasses.contains(cls)) return _metaStyle;
      if (_operatorClasses.contains(cls)) return _operatorStyle;
    }
    return _baseStyle;
  }
}

String? _extractCodeLanguage(md.Element? element) {
  final classes = (element?.attributes['class'] ?? '').trim();
  if (classes.isEmpty) {
    return null;
  }
  for (final name in classes.split(' ')) {
    if (name.startsWith('language-') && name.length > 9) {
      return name.substring(9);
    }
    if (name.startsWith('lang-') && name.length > 5) {
      return name.substring(5);
    }
  }
  return null;
}

String? _normalizeCodeLanguage(String? language) {
  final normalized = (language ?? '').trim().toLowerCase();
  if (normalized.isEmpty) {
    return null;
  }
  return switch (normalized) {
    'text' || 'txt' || 'plain' || 'plaintext' => 'plaintext',
    'shell' || 'sh' || 'zsh' => 'bash',
    'yml' => 'yaml',
    'htm' => 'html',
    _ => normalized,
  };
}

bool _isHtmlLanguage(String? language) {
  final normalized = (language ?? '').trim().toLowerCase();
  return normalized == 'html' || normalized == 'htm';
}

bool _isMermaidLanguage(String? language) {
  final normalized = (language ?? '').trim().toLowerCase();
  return normalized == 'mermaid';
}

String _getFileExtensionForLanguage(String? language) {
  final normalized = (language ?? '').trim().toLowerCase();
  if (normalized.isEmpty) {
    return '.txt';
  }
  return switch (normalized) {
    'javascript' || 'js' => '.js',
    'typescript' || 'ts' => '.ts',
    'python' || 'py' => '.py',
    'java' => '.java',
    'kotlin' || 'kt' => '.kt',
    'swift' => '.swift',
    'go' || 'golang' => '.go',
    'rust' || 'rs' => '.rs',
    'c' => '.c',
    'cpp' || 'c++' || 'cxx' => '.cpp',
    'csharp' || 'cs' || 'c#' => '.cs',
    'ruby' || 'rb' => '.rb',
    'php' => '.php',
    'html' || 'htm' => '.html',
    'css' => '.css',
    'scss' => '.scss',
    'sass' => '.sass',
    'less' => '.less',
    'json' => '.json',
    'xml' => '.xml',
    'yaml' || 'yml' => '.yaml',
    'markdown' || 'md' => '.md',
    'sql' => '.sql',
    'bash' || 'shell' || 'sh' || 'zsh' => '.sh',
    'powershell' || 'ps1' => '.ps1',
    'dart' => '.dart',
    'lua' => '.lua',
    'perl' || 'pl' => '.pl',
    'r' => '.r',
    'scala' => '.scala',
    'groovy' => '.groovy',
    'julia' || 'jl' => '.jl',
    'elixir' || 'ex' => '.ex',
    'erlang' || 'erl' => '.erl',
    'haskell' || 'hs' => '.hs',
    'clojure' || 'clj' => '.clj',
    'fsharp' || 'fs' || 'f#' => '.fs',
    'ocaml' || 'ml' => '.ml',
    'objective-c' || 'objc' || 'm' => '.m',
    'vue' => '.vue',
    'jsx' => '.jsx',
    'tsx' => '.tsx',
    'svelte' => '.svelte',
    'graphql' || 'gql' => '.graphql',
    'protobuf' || 'proto' => '.proto',
    'toml' => '.toml',
    'ini' || 'cfg' => '.ini',
    'dockerfile' => '.dockerfile',
    'makefile' || 'make' => '.makefile',
    'cmake' => '.cmake',
    'nginx' => '.conf',
    'apache' => '.conf',
    _ => '.$normalized',
  };
}

class _HtmlPreviewDialog extends StatefulWidget {
  const _HtmlPreviewDialog({required this.htmlContent, required this.theme});

  final String htmlContent;
  final ThemeData theme;

  @override
  State<_HtmlPreviewDialog> createState() => _HtmlPreviewDialogState();
}

class _HtmlPreviewDialogState extends State<_HtmlPreviewDialog> {
  bool _isCleaning = false;
  double _zoom = 1.0;
  _HtmlPreviewMetrics? _contentMetrics;
  final GlobalKey<_HtmlWebViewPreviewState> _previewKey =
      GlobalKey<_HtmlWebViewPreviewState>();

  static const double _zoomMin = 0.4;
  static const double _zoomMax = 3.0;
  static const double _zoomStep = 0.1;
  static const double _minDialogWidth = 560.0;
  static const double _maxDialogWidth = 1200.0;
  static const double _minDialogHeight = 420.0;
  static const double _maxDialogHeight = 900.0;
  static const double _contentWidthChrome = 56.0;
  static const double _contentHeightChrome = 92.0;
  static const int _maxTempHtmlCleanupEntries = 4096;

  void _applyZoom(double next) {
    final clamped = next.clamp(_zoomMin, _zoomMax);
    if ((clamped - _zoom).abs() < 0.001) return;
    setState(() => _zoom = clamped);
    _previewKey.currentState?.setZoom(clamped);
  }

  void _resetZoom() => _applyZoom(1.0);

  void _onZoomChangedFromWebView(double next) {
    final clamped = next.clamp(_zoomMin, _zoomMax);
    if ((clamped - _zoom).abs() < 0.005) return;
    setState(() => _zoom = clamped);
  }

  void _onContentMetricsChanged(_HtmlPreviewMetrics metrics) {
    final previous = _contentMetrics;
    if (previous != null &&
        (previous.width - metrics.width).abs() < 8 &&
        (previous.height - metrics.height).abs() < 8) {
      return;
    }
    setState(() => _contentMetrics = metrics);
  }

  @override
  Widget build(BuildContext context) {
    final titleText = openHandLocalizedText(
      context,
      zh: 'HTML 预览',
      zhHant: 'HTML 預覽',
      en: 'HTML Preview',
      fr: 'Aperçu HTML',
      de: 'HTML-Vorschau',
      ja: 'HTML プレビュー',
    );
    final closeText = openHandCloseLabel(context);
    final openInBrowserText = openHandLocalizedText(
      context,
      zh: '在浏览器中打开',
      zhHant: '在瀏覽器中開啟',
      en: 'Open in Browser',
      fr: 'Ouvrir dans le navigateur',
      de: 'Im Browser öffnen',
      ja: 'ブラウザで開く',
    );
    final cleanupText = openHandLocalizedText(
      context,
      zh: '清理缓存',
      zhHant: '清理快取',
      en: 'Clean Cache',
      fr: 'Nettoyer le cache',
      de: 'Cache leeren',
      ja: 'キャッシュを削除',
    );
    final zoomInText = openHandLocalizedText(
      context,
      zh: '放大',
      zhHant: '放大',
      en: 'Zoom In',
      fr: 'Zoom avant',
      de: 'Vergrößern',
      ja: '拡大',
    );
    final zoomOutText = openHandLocalizedText(
      context,
      zh: '缩小',
      zhHant: '縮小',
      en: 'Zoom Out',
      fr: 'Zoom arrière',
      de: 'Verkleinern',
      ja: '縮小',
    );
    final zoomResetText = openHandLocalizedText(
      context,
      zh: '重置缩放',
      zhHant: '重設縮放',
      en: 'Reset Zoom',
      fr: 'Réinitialiser le zoom',
      de: 'Zoom zurücksetzen',
      ja: 'ズームをリセット',
    );
    final zoomPercentText = '${(_zoom * 100).round()}%';
    final viewport = MediaQuery.sizeOf(context);
    final maxWidth = math.min(viewport.width * 0.9, _maxDialogWidth);
    final minWidth = math.min(maxWidth, _minDialogWidth);
    final maxHeight = math.min(viewport.height * 0.85, _maxDialogHeight);
    final minHeight = math.min(maxHeight, _minDialogHeight);
    final metrics = _contentMetrics;
    final dialogWidth = metrics == null
        ? maxWidth
        : (metrics.width + _contentWidthChrome)
              .clamp(minWidth, maxWidth)
              .toDouble();
    final dialogHeight = metrics == null
        ? maxHeight
        : (metrics.height + _contentHeightChrome)
              .clamp(minHeight, maxHeight)
              .toDouble();
    context.watch<SettingsController>();
    final animationSettings = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
    final sizeDuration = openHandMotionDuration(
      context,
      animationSettings.duration,
    );
    final sizeCurve = animationSettings.curve.curve;

    return buildOpenHandDialog(
      backgroundColor: Colors.transparent,
      clipBehavior: Clip.none,
      child: AnimatedContainer(
        duration: sizeDuration,
        curve: sizeCurve,
        width: dialogWidth,
        height: dialogHeight,
        decoration: BoxDecoration(
          color: widget.theme.colorScheme.surface,
          borderRadius: kOpenHandBorderRadius20,
          boxShadow: [
            BoxShadow(
              color: widget.theme.colorScheme.shadow.withValues(alpha: 0.2),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: widget.theme.colorScheme.surfaceContainerHigh,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(kOpenHandRadius20),
                ),
                border: Border(
                  bottom: BorderSide(
                    color: widget.theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.5,
                    ),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.html_rounded,
                    color: widget.theme.colorScheme.primary,
                    size: 22,
                  ),
                  kOpenHandHGap10,
                  Text(
                    titleText,
                    style: widget.theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: zoomOutText,
                    onPressed: _zoom <= _zoomMin + 0.001
                        ? null
                        : () => _applyZoom(_zoom - _zoomStep),
                    icon: const Icon(Icons.zoom_out_rounded, size: 20),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 48),
                    child: Center(
                      child: Text(
                        zoomPercentText,
                        style: widget.theme.textTheme.bodySmall?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: zoomInText,
                    onPressed: _zoom >= _zoomMax - 0.001
                        ? null
                        : () => _applyZoom(_zoom + _zoomStep),
                    icon: const Icon(Icons.zoom_in_rounded, size: 20),
                  ),
                  kOpenHandHGap4,
                  IconButton(
                    tooltip: zoomResetText,
                    onPressed: (_zoom - 1.0).abs() < 0.001 ? null : _resetZoom,
                    icon: const Icon(Icons.restart_alt_rounded, size: 20),
                  ),
                  kOpenHandHGap12,
                  IconButton(
                    tooltip: cleanupText,
                    onPressed: _isCleaning ? null : _cleanupTempHtmlFiles,
                    icon: OpenHandBusyStatusIcon(
                      busy: _isCleaning,
                      icon: Icons.cleaning_services_rounded,
                      size: 20,
                    ),
                  ),
                  kOpenHandHGap4,
                  IconButton(
                    tooltip: openInBrowserText,
                    onPressed: () => _openInBrowser(context),
                    icon: const Icon(Icons.open_in_browser_rounded, size: 20),
                  ),
                  kOpenHandHGap4,
                  IconButton(
                    tooltip: closeText,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(kOpenHandRadius20),
                ),
                child: _HtmlWebViewPreview(
                  key: _previewKey,
                  htmlContent: widget.htmlContent,
                  onZoomChanged: _onZoomChangedFromWebView,
                  onMetricsChanged: _onContentMetricsChanged,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _cleanupTempHtmlFiles() async {
    setState(() {
      _isCleaning = true;
    });
    try {
      final tempDir = Directory.systemTemp;
      int deletedCount = 0;
      final cleanupStopwatch = Stopwatch()..start();
      final listing = await listDirectoryBounded(
        tempDir,
        maxEntries: _maxTempHtmlCleanupEntries,
        totalTimeout: const Duration(seconds: 3),
      );
      for (final entity in listing.entries) {
        if (cleanupStopwatch.elapsed >= _tempPreviewCleanupTotalTimeout) {
          break;
        }
        if (entity is Directory &&
            p.basename(entity.path).startsWith('openhand_html_')) {
          try {
            await deletePathBounded(
              p.absolute(entity.path),
              policy: _tempPreviewDeletePolicy,
              allowedRoot: p.absolute(tempDir.path),
            );
            deletedCount++;
          } catch (error, stack) {
            silentLog(
              'home_code_highlighting',
              '删除临时 HTML 缓存 ${entity.path}',
              error,
              stack,
            );
          }
        }
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _isCleaning = false;
      });
      replaceOpenHandSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '已清理 $deletedCount 个临时 HTML 缓存目录。',
          zhHant: '已清理 $deletedCount 個臨時 HTML 快取目錄。',
          en: 'Cleaned $deletedCount temporary HTML cache directories.',
          fr: '$deletedCount dossiers de cache HTML temporaires nettoyés.',
          de: '$deletedCount temporäre HTML-Cache-Ordner wurden bereinigt.',
          ja: '$deletedCount 個の一時 HTML キャッシュディレクトリを削除しました。',
        ),
        kind: OpenHandSnackKind.success,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isCleaning = false;
      });
      showFriendlyErrorSnackBar(
        context,
        message: '$e',
        fallback: openHandLocalizedText(
          context,
          zh: '清理缓存失败',
          zhHant: '清理快取失敗',
          en: 'Failed to clean cache',
          fr: 'Échec du nettoyage du cache',
          de: 'Cache konnte nicht geleert werden',
          ja: 'キャッシュの削除に失敗しました',
        ),
      );
    }
  }

  Future<void> _openInBrowser(BuildContext context) async {
    try {
      final htmlFile = await writeNewTemporaryFileTextBounded(
        directoryPrefix: 'openhand_html_',
        fileName: 'preview.html',
        text: widget.htmlContent,
        timeout: _tempPreviewWriteTimeout,
        onSecondaryError: (error, stack) =>
            silentLog('home_code_highlighting', '清理浏览器预览临时文件', error, stack),
      );
      await openLocalPathWithSystemApp(
        htmlFile.path,
        tag: 'home_code_highlighting.open_html_preview',
      );
    } catch (error, stack) {
      silentLog('home_code_highlighting', '在浏览器中打开 HTML 预览', error, stack);
      if (!context.mounted) {
        return;
      }
      replaceOpenHandSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '无法在浏览器中打开。',
          zhHant: '無法在瀏覽器中開啟。',
          en: 'Could not open in browser.',
          fr: 'Impossible d’ouvrir dans le navigateur.',
          de: 'Konnte nicht im Browser geöffnet werden.',
          ja: 'ブラウザで開けませんでした。',
        ),
        kind: OpenHandSnackKind.error,
      );
    }
  }
}

class _HtmlPreviewMetrics {
  const _HtmlPreviewMetrics({required this.width, required this.height});

  final double width;
  final double height;
}

class _HtmlWebViewPreview extends StatefulWidget {
  const _HtmlWebViewPreview({
    super.key,
    required this.htmlContent,
    this.onZoomChanged,
    this.onMetricsChanged,
  });

  final String htmlContent;
  final ValueChanged<double>? onZoomChanged;
  final ValueChanged<_HtmlPreviewMetrics>? onMetricsChanged;

  @override
  State<_HtmlWebViewPreview> createState() => _HtmlWebViewPreviewState();
}

class _HtmlWebViewPreviewState extends State<_HtmlWebViewPreview> {
  WebViewController? _webViewController;
  String? _tempFilePath;
  bool _isLoading = true;
  String? _errorMessage;
  double _loadingProgress = 0;
  double _currentZoom = 1.0;

  /// Called by parent dialog to programmatically set zoom.
  Future<void> setZoom(double zoom) async {
    _currentZoom = zoom;
    final controller = _webViewController;
    if (controller == null) return;
    try {
      await controller.runJavaScript(
        'window.__openhandSetZoom && window.__openhandSetZoom(${zoom.toStringAsFixed(3)});',
      );
    } catch (error, stack) {
      silentLog('home_code_highlighting', 'HTML 预览 setZoom 失败', error, stack);
    }
  }

  void _onZoomMessage(JavaScriptMessage message) {
    final value = optionalDoubleFromValue(message.message);
    if (value == null) return;
    _currentZoom = value;
    widget.onZoomChanged?.call(value);
  }

  void _onMetricsMessage(JavaScriptMessage message) {
    try {
      final decoded = stringKeyedMapFromValue(jsonDecode(message.message));
      if (decoded.isEmpty) return;
      final width = optionalDoubleFromValue(decoded['width']);
      final height = optionalDoubleFromValue(decoded['height']);
      if (width == null || height == null) return;
      if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
        return;
      }
      widget.onMetricsChanged?.call(
        _HtmlPreviewMetrics(width: width, height: height),
      );
    } catch (error, stack) {
      silentLog('home_code_highlighting', '解析 HTML 预览指标失败', error, stack);
    }
  }

  Future<void> _installZoomBridge([WebViewController? target]) async {
    final controller = target ?? _webViewController;
    if (controller == null) return;
    try {
      await controller.runJavaScript(_zoomBridgeScript);
      if (_currentZoom != 1.0) {
        await controller.runJavaScript(
          'window.__openhandSetZoom(${_currentZoom.toStringAsFixed(3)});',
        );
      }
    } catch (error, stack) {
      silentLog('home_code_highlighting', '安装缩放桥接失败', error, stack);
    }
  }

  Future<void> _installMetricsBridge([WebViewController? target]) async {
    final controller = target ?? _webViewController;
    if (controller == null) return;
    try {
      await controller.runJavaScript(_metricsBridgeScript);
    } catch (error, stack) {
      silentLog('home_code_highlighting', '安装预览指标桥接失败', error, stack);
    }
  }

  static const String _zoomBridgeScript =
      '(function(){if(window.__openhandZoomInstalled)return;window.__openhandZoomInstalled=true;'
      'var meta=document.querySelector(\'meta[name="viewport"]\');'
      'if(!meta){meta=document.createElement("meta");meta.name="viewport";'
      'meta.content="width=device-width, initial-scale=1, minimum-scale=0.4, maximum-scale=3.0, user-scalable=yes";'
      'document.head&&document.head.appendChild(meta);}'
      'var z=1.0;function clamp(v){return Math.max(0.4,Math.min(3.0,v));}'
      'function apply(v){z=clamp(v);'
      'document.documentElement.style.transformOrigin="0 0";'
      'document.documentElement.style.transform="scale("+z+")";'
      'document.documentElement.style.width=(100/z)+"%";'
      'try{OpenHandZoom.postMessage(String(z));}catch(_){}}'
      'window.__openhandSetZoom=apply;'
      'window.addEventListener("wheel",function(e){if(e.ctrlKey||e.metaKey){e.preventDefault();var d=e.deltaY<0?0.05:-0.05;apply(z+d);}},{passive:false});'
      'var pinchBase=z;'
      'window.addEventListener("gesturestart",function(e){e.preventDefault();pinchBase=z;},{passive:false});'
      'window.addEventListener("gesturechange",function(e){e.preventDefault();apply(pinchBase*e.scale);},{passive:false});'
      'window.addEventListener("gestureend",function(e){e.preventDefault();},{passive:false});'
      'var touchInitialDist=0,touchInitialZoom=1.0;'
      'function dist(t){var dx=t[0].clientX-t[1].clientX,dy=t[0].clientY-t[1].clientY;return Math.sqrt(dx*dx+dy*dy);}'
      'window.addEventListener("touchstart",function(e){if(e.touches.length===2){touchInitialDist=dist(e.touches);touchInitialZoom=z;}});'
      'window.addEventListener("touchmove",function(e){if(e.touches.length===2&&touchInitialDist>0){var d=dist(e.touches);apply(touchInitialZoom*(d/touchInitialDist));e.preventDefault();}},{passive:false});'
      '})();';

  static const String _metricsBridgeScript = r'''
(function(){
  if (window.__openhandPreviewMetricsInstalled) {
    if (window.__openhandPreviewMetricsSchedule) window.__openhandPreviewMetricsSchedule();
    return;
  }
  window.__openhandPreviewMetricsInstalled = true;
  function tagOf(node){return String((node && node.tagName) || '').toLowerCase();}
  function hidden(styles){return !styles || styles.display==='none' || styles.visibility==='hidden' || styles.visibility==='collapse';}
  function contentBoxTag(tag){return /^(img|video|canvas|svg|iframe|table|pre|hr|button|input|textarea|select|summary)$/i.test(tag);}
  function visible(node){
    var el = node.nodeType === 1 ? node : node.parentElement;
    while (el && el !== document.documentElement) {
      var styles = window.getComputedStyle(el);
      if (hidden(styles) || styles.position === 'fixed') return false;
      el = el.parentElement;
    }
    return true;
  }
  function includeRect(bounds, rect){
    if (!rect || rect.width <= 0 || rect.height <= 0) return;
    bounds.left = Math.min(bounds.left, rect.left);
    bounds.right = Math.max(bounds.right, rect.right);
    bounds.bottom = Math.max(bounds.bottom, rect.bottom);
  }
  function measure(){
    try {
      var root = document.body || document.documentElement;
      if (!root) return;
      var bounds = {left: Infinity, right: 0, bottom: 0};
      try {
        var walker = document.createTreeWalker(root, 4);
        var textCount = 0;
        while (walker.nextNode() && textCount < 2400) {
          var text = walker.currentNode;
          if (!text.nodeValue || !text.nodeValue.trim() || !visible(text)) continue;
          var range = document.createRange();
          range.selectNodeContents(text);
          var rects = range.getClientRects();
          for (var i = 0; i < rects.length; i++) includeRect(bounds, rects[i]);
          range.detach && range.detach();
          textCount++;
        }
      } catch (_) {}
      var nodes = root.querySelectorAll ? root.querySelectorAll('*') : [];
      var limit = Math.min(nodes.length, 1800);
      for (var n = 0; n < limit; n++) {
        var node = nodes[n];
        var tag = tagOf(node);
        if (!contentBoxTag(tag) || !visible(node)) continue;
        includeRect(bounds, node.getBoundingClientRect());
      }
      var body = document.body;
      var doc = document.documentElement;
      var fallbackWidth = Math.max(
        body ? body.scrollWidth || 0 : 0,
        doc ? doc.scrollWidth || 0 : 0,
        window.innerWidth || 0
      );
      var fallbackHeight = Math.max(
        body ? body.scrollHeight || 0 : 0,
        doc ? doc.scrollHeight || 0 : 0,
        window.innerHeight || 0
      );
      var width = bounds.left === Infinity ? fallbackWidth : bounds.right - bounds.left;
      var height = bounds.bottom > 0 ? bounds.bottom : fallbackHeight;
      OpenHandPreviewMetrics.postMessage(JSON.stringify({
        width: Math.ceil(Math.max(1, width)),
        height: Math.ceil(Math.max(1, height))
      }));
    } catch (_) {}
  }
  var pending = false;
  function schedule(){
    if (pending) return;
    pending = true;
    window.requestAnimationFrame(function(){pending = false; measure();});
  }
  window.__openhandPreviewMetricsSchedule = schedule;
  measure();
  try {
    var ro = new ResizeObserver(schedule);
    if (document.body) ro.observe(document.body);
    if (document.documentElement) ro.observe(document.documentElement);
  } catch (_) {}
  try {
    var mo = new MutationObserver(schedule);
    if (document.body) mo.observe(document.body,{subtree:true,childList:true,attributes:true,characterData:true});
  } catch (_) {}
  window.addEventListener('load', schedule);
  window.addEventListener('resize', schedule);
  setTimeout(schedule, 80);
  setTimeout(schedule, 240);
  setTimeout(schedule, 720);
})();
''';

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  @override
  void didUpdateWidget(covariant _HtmlWebViewPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.htmlContent != widget.htmlContent) {
      _cleanupTempFile();
      _webViewController = null;
      _initializeWebView();
    }
  }

  @override
  void dispose() {
    _cleanupTempFile();
    super.dispose();
  }

  Future<void> _initializeWebView() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _loadingProgress = 0;
    });

    try {
      if (!mounted) return;

      // Initialize WebViewController with platform-safe configuration.
      final controller = WebViewController();

      // Set JavaScript mode (safe on all platforms).
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.addJavaScriptChannel(
        'OpenHandZoom',
        onMessageReceived: _onZoomMessage,
      );
      await controller.addJavaScriptChannel(
        'OpenHandPreviewMetrics',
        onMessageReceived: _onMetricsMessage,
      );

      // Set navigation delegate for progress and error handling.
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) {
              setState(() {
                _loadingProgress = progress / 100.0;
              });
            }
          },
          onPageStarted: (url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
              });
            }
          },
          onPageFinished: (url) {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
            _installZoomBridge(controller);
            _installMetricsBridge(controller);
          },
          onWebResourceError: (error) {
            if (mounted) {
              setState(() {
                _errorMessage = error.description;
                _isLoading = false;
              });
            }
          },
        ),
      );

      if (!mounted) return;

      // Load HTML content directly (more compatible across platforms).
      await controller.loadHtmlString(widget.htmlContent);

      if (!mounted) return;

      setState(() {
        _webViewController = controller;
        // Note: _isLoading will be set to false by onPageFinished callback.
      });
    } catch (e) {
      if (!mounted) return;

      // If direct HTML loading fails, try with file-based approach.
      await _tryLoadFromFile();
    }
  }

  Future<void> _tryLoadFromFile() async {
    try {
      // 创建临时 HTML 文件作为后备加载源。
      final htmlFile = await writeNewTemporaryFileTextBounded(
        directoryPrefix: 'openhand_html_',
        fileName: 'preview.html',
        text: widget.htmlContent,
        timeout: _tempPreviewWriteTimeout,
        onSecondaryError: (error, stack) =>
            silentLog('home_code_highlighting', '清理 HTML 预览临时文件', error, stack),
      );
      _tempFilePath = htmlFile.path;

      if (!mounted) return;

      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.addJavaScriptChannel(
        'OpenHandZoom',
        onMessageReceived: _onZoomMessage,
      );
      await controller.addJavaScriptChannel(
        'OpenHandPreviewMetrics',
        onMessageReceived: _onMetricsMessage,
      );
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) {
              setState(() {
                _loadingProgress = progress / 100.0;
              });
            }
          },
          onPageFinished: (url) {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
            _installZoomBridge(controller);
            _installMetricsBridge(controller);
          },
          onWebResourceError: (error) {
            if (mounted) {
              setState(() {
                _errorMessage = error.description;
                _isLoading = false;
              });
            }
          },
        ),
      );

      await controller.loadFile(_tempFilePath!);

      if (!mounted) return;

      setState(() {
        _webViewController = controller;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = openHandLocalizedText(
          context,
          zh: 'HTML 预览加载失败（WebView 初始化或写临时文件出错）。\n原始错误：$e',
          zhHant: 'HTML 預覽載入失敗（WebView 初始化或寫入臨時檔案出錯）。\n原始錯誤：$e',
          en: 'HTML preview failed to load (WebView init or temp file write).\nRaw: $e',
          fr: 'Échec du chargement de l’aperçu HTML (initialisation WebView ou fichier temporaire).\nErreur brute : $e',
          de: 'HTML-Vorschau konnte nicht geladen werden (WebView-Init oder temporäre Datei).\nRohfehler: $e',
          ja: 'HTML プレビューの読み込みに失敗しました（WebView 初期化または一時ファイル書き込み）。\n元のエラー: $e',
        );
        _isLoading = false;
      });
    }
  }

  Future<void> _cleanupTempFile() async {
    if (_tempFilePath != null) {
      try {
        final file = File(_tempFilePath!);
        await deletePathBounded(
          p.absolute(file.parent.path),
          policy: _tempPreviewDeletePolicy,
          allowedRoot: p.absolute(Directory.systemTemp.path),
        );
      } catch (error, stack) {
        silentLog('home_code_highlighting', '清理临时 HTML 文件', error, stack);
      }
      _tempFilePath = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: theme.colorScheme.error,
                size: 48,
              ),
              kOpenHandGap16,
              Text(
                openHandLocalizedText(
                  context,
                  zh: '加载预览失败',
                  zhHant: '載入預覽失敗',
                  en: 'Failed to load preview',
                  fr: 'Échec du chargement',
                  de: 'Vorschau konnte nicht geladen werden',
                  ja: 'プレビューの読み込みに失敗',
                ),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              kOpenHandGap8,
              Text(
                _errorMessage!,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_webViewController == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            kOpenHandGap16,
            Text(
              openHandLocalizedText(
                context,
                zh: '正在初始化预览...',
                zhHant: '正在初始化預覽...',
                en: 'Initializing preview...',
                fr: 'Initialisation de l’aperçu...',
                de: 'Vorschau wird initialisiert...',
                ja: 'プレビューを初期化中...',
              ),
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        WebViewWidget(controller: _webViewController!),
        if (_isLoading)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              value: _loadingProgress > 0 ? _loadingProgress : null,
              backgroundColor: theme.colorScheme.surfaceContainerLow,
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colorScheme.primary,
              ),
            ),
          ),
      ],
    );
  }
}

/// 进程级缓存约 3.3 MB 的 Mermaid 资源；失败后允许再次加载。
final OpenHandRetryableAsyncCache<String> _mermaidJsCache =
    OpenHandRetryableAsyncCache<String>(
      () =>
          rootBundle.loadString('assets/tooling/mermaid.min.js', cache: false),
    );
Future<String> _loadMermaidJs() => _mermaidJsCache.load();

/// Mermaid 流程图渲染视图。在代码块 header 右上角的「视图/代码」toggle
/// 按钮切到视图时启用：用 [WebView] + 内联 mermaid.js (assets 离线) 渲染 SVG,
/// 配合 CSS `transform: scale/translate` + `touch-action: none` 让
/// JS 完全接管双指放缩与长按拖动平移；mermaid 原生 `interaction: true`
/// 还能让用户点击图元悬浮 tooltip、点击边/节点触发回调。
///
/// 仅在用户主动切到「视图」时才挂载 WebView，默认展示代码文本，
/// 不浪费主线程 / WebView 内存，与正式响应 markdown 渲染节流同源思路。
class _SvgClipboardVerification {
  const _SvgClipboardVerification({
    required this.pbpasteLen,
    required this.flutterLen,
    required this.osLayerOk,
  });

  final int pbpasteLen;
  final int flutterLen;
  final bool osLayerOk;
}

class _MermaidDiagramView extends StatefulWidget {
  const _MermaidDiagramView({required this.source, required this.palette});

  final String source;
  final _CodeBlockPalette palette;

  @override
  State<_MermaidDiagramView> createState() => _MermaidDiagramViewState();
}

class _MermaidDiagramViewState extends State<_MermaidDiagramView> {
  static const Duration _mermaidLoadTimeout = Duration(seconds: 60);
  static const Duration _svgClipboardProcessTimeout = Duration(seconds: 2);
  static const int _maxPngDecodedBytes = 32 * kBytesPerMiB;
  static const int _svgClipboardVerificationMinBytes = 64 * 1024;
  static const int _svgClipboardVerificationMaxBytes = 16 * 1024 * 1024;
  static const int _svgClipboardStderrMaxBytes = 8 * 1024;

  final GlobalKey _interactiveRegionKey = GlobalKey();
  WebViewController? _controller;
  bool _isReady = false;
  String? _loadError;
  Timer? _loadWatchdog;
  String? _tempHtmlPath;
  String _svgMarkup = '';
  String _pngDataUrl = '';
  double _zoomPercent = 100;
  bool _bridgeReady = false;
  Brightness? _lastBrightness;
  // 缓存 didChangeDependencies 阶段拿到的 scope，让 dispose 不再重复查询 ancestor，避免
  // “Looking up a deactivated widget's ancestor is unsafe”。
  _MessageBubbleState? _bubbleScope;
  // macOS 触控板捏合/平移：用 onPointerPanZoom* 跟踪累计 scale，
  // 把"相对于手势起点的累计值"换算成"相对上一个回调的增量"，
  // 再桥接到 WebView 内部的 __openhandZoomAt / __openhandPan。
  double _trackpadLastScale = 1.0;

  Widget _buildToolPill({
    required String label,
    required IconData icon,
    required Color backgroundColor,
    required Color foregroundColor,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: foregroundColor),
          kOpenHandHGap6,
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
    final decoration = BoxDecoration(
      color: backgroundColor,
      borderRadius: kOpenHandPillBorderRadius,
    );
    if (onTap == null) {
      return DecoratedBox(decoration: decoration, child: child);
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: kOpenHandPillBorderRadius,
        child: Ink(decoration: decoration, child: child),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = _BubbleHtmlInteractiveScope.maybeOf(context);
    if (scope != _bubbleScope) {
      _bubbleScope?.unregisterEmbeddedInteractiveRegion(_interactiveRegionKey);
      _bubbleScope = scope;
      scope?.registerEmbeddedInteractiveRegion(_interactiveRegionKey);
    }
    final brightness = Theme.of(context).brightness;
    if (_lastBrightness == null) {
      _lastBrightness = brightness;
      return;
    }
    if (_lastBrightness != brightness) {
      _lastBrightness = brightness;
      unawaited(
        _runMermaidCommand(
          'window.__openhandMermaidFit&&window.__openhandMermaidFit();',
        ),
      );
    }
  }

  Uint8List? _decodePngBytes(String dataUrl) {
    final trimmed = dataUrl.trim();
    if (trimmed.isEmpty) return null;
    final match = RegExp(
      r'^data:image\/png;base64,(.+)$',
      dotAll: true,
    ).firstMatch(trimmed);
    final base64Part = match?.group(1);
    if (base64Part == null || base64Part.isEmpty) return null;
    try {
      return decodeBase64Bounded(
        base64Part,
        maxDecodedBytes: _maxPngDecodedBytes,
      );
    } on BoundedBase64Exception {
      return null;
    }
  }

  Future<void> _bootstrap() async {
    try {
      final controller = WebViewController();
      // 关键：逐行 await，确保 setup 三步全部就绪后再 loadFile。
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.addJavaScriptChannel(
        'OpenHandMermaid',
        onMessageReceived: (message) {
          final raw = message.message.trim();
          if (raw == 'rendered') {
            _loadWatchdog?.cancel();
            if (mounted && !_isReady) {
              setState(() => _isReady = true);
            }
            return;
          }
          if (raw == 'ready') {
            _loadWatchdog?.cancel();
            if (mounted) {
              setState(() => _bridgeReady = true);
            }
            return;
          }
          if (raw.startsWith('zoom:')) {
            final value = optionalDoubleFromValue(raw.substring(5));
            if (value != null && mounted) {
              setState(() => _zoomPercent = value);
            }
            return;
          }
          if (raw.startsWith('svg:')) {
            if (mounted) {
              setState(() => _svgMarkup = raw.substring(4));
            }
            return;
          }
          if (raw.startsWith('png:')) {
            if (mounted) {
              setState(() => _pngDataUrl = raw.substring(4));
            }
            return;
          }
          if (raw.startsWith('error:')) {
            _loadWatchdog?.cancel();
            if (mounted) {
              setState(() {
                _loadError = raw.length > 6 ? raw.substring(6) : raw;
                _isReady = true;
              });
            }
          }
        },
      );
      if (!Platform.isMacOS) {
        controller.setBackgroundColor(Colors.transparent);
      }
      // 把 mermaid.js 内联到单文件 HTML，loadFile 一次性加载。
      final mermaidJs = await _loadMermaidJs();
      final themeColors = _computeMermaidThemeColors();
      // 关键：把 mermaid.js 内联到 HTML 里，走 loadFile 加载单文件。
      // WKWebView 对 loadFile(file://) 没有 inline script 体积限制
      // （那只是 loadHtmlString 的坑）。同时把渲染 IIFE 也一并内联在
      // 同一个 <script> 标签末尾，彻底消除双 script 标签 / runJavaScript
      // 被抢占的一整类竞态问题。
      final html = _buildMermaidHtml(
        themeColors.bg,
        themeColors.fg,
        themeColors.border,
        mermaidJs,
      );
      if (isDesktopPlatform()) {
        final tempFile = await writeNewTemporaryFileTextBounded(
          directoryPrefix: 'openhand_mermaid_',
          fileName: 'index.html',
          text: html,
          timeout: _tempPreviewWriteTimeout,
          onSecondaryError: (error, stack) => silentLog(
            'home_code_highlighting',
            '清理 Mermaid 临时页面',
            error,
            stack,
          ),
        );
        _tempHtmlPath = tempFile.path;
        await controller.loadFile(tempFile.path);
      } else {
        await controller.loadHtmlString(html);
      }
      _controller = controller;
      // 关键：Mermaid 11.x min.js ~3.3MB 解析 + 初始化在慢机器上可能 > 18s，
      // 把看门狗延长到 60s；同时引入 _MermaidLoadPhase 阶段反馈，用户
      // 至少能看到"解析中 / 渲染中"提示而不是直接黑屏 18s。
      _loadWatchdog = startSafeTimer(_mermaidLoadTimeout, () {
        if (!mounted) return;
        // 只有当 rendered 与 bridge ready 都还没到时，才判为超时。
        // 单一信号到达意味着 WebView 至少部分可用，再写超时会把可用链路标坏。
        if (!_isReady && !_bridgeReady) {
          setState(() {
            _loadError ??= openHandLocalizedText(
              context,
              zh: 'Mermaid 加载超时',
              en: 'Mermaid load timed out',
            );
            _isReady = true;
          });
        }
      });
    } catch (error, stack) {
      silentLog('home_code_highlighting', '初始化 Mermaid 失败', error, stack);
      if (mounted) {
        setState(() {
          _loadError = '$error';
          _isReady = true;
        });
      }
    }
  }

  @override
  void dispose() {
    // dispose 阶段 context 已经 deactivate，直接 _BubbleHtmlInteractiveScope.maybeOf(context) 会触发
    // “Looking up a deactivated widget's ancestor is unsafe”。
    // 因此把在 didChangeDependencies 阶段拿到的 scope 缓存下来，
    // 这里只走 cached 引用注销内嵌交互区域，不再二次查询 ancestor。
    _bubbleScope?.unregisterEmbeddedInteractiveRegion(_interactiveRegionKey);
    _bubbleScope = null;
    _loadWatchdog?.cancel();
    final tempPath = _tempHtmlPath;
    if (tempPath != null) {
      Future<void>(() async {
        try {
          final file = File(tempPath);
          await deletePathBounded(
            p.absolute(file.parent.path),
            policy: _tempPreviewDeletePolicy,
            allowedRoot: p.absolute(Directory.systemTemp.path),
          );
        } catch (error, stack) {
          silentLog('home_code_highlighting', '清理 Mermaid 临时文件', error, stack);
        }
      });
    }
    super.dispose();
  }

  // macOS 上 webview_flutter 把 WKWebView 当 Flutter 子层，pointer 事件被
  // Flutter 命中测试先吃掉、不再回灌给 WebView。这里只在 macOS 用 Listener
  // 把事件桥接到 WebView：单指/鼠标 -> dispatchEvent 同等 PointerEvent，
  // 滚轮 -> __openhandZoomAt，触控板 pan/zoom -> __openhandPan/__openhandZoomAt。
  // 其他平台 (iOS/Android/WEB) 原生事件能进 WebView，直接返回原 widget 即可。
  Widget _buildWebViewWithGestures() {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    final webView = WebViewWidget(controller: controller);
    if (!Platform.isMacOS) return webView;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) => _forwardPointer('down', e),
      onPointerMove: (e) => _forwardPointer('move', e),
      onPointerUp: (e) => _forwardPointer('up', e),
      onPointerCancel: (e) => _forwardPointer('cancel', e),
      onPointerSignal: (e) {
        if (e is PointerScrollEvent && e.scrollDelta.dy != 0) {
          // 鼠标滚轮 / 触控板双指上下推动：以光标为锚点缩放，
          // 系数与 JS 原生 wheel 路径保持一致 (0.0025/px)。
          final factor = (1 - e.scrollDelta.dy * 0.0025).clamp(0.5, 2.0);
          _forwardZoom(factor, e.localPosition);
        }
      },
      onPointerPanZoomStart: (_) => _trackpadLastScale = 1.0,
      onPointerPanZoomUpdate: (e) {
        // 触控板捏合 + 同步两指推动：scale 是相对手势起点的累计值，
        // 取增量再桥接，避免每帧重复施加历史缩放。
        final scaleStep = e.scale / _trackpadLastScale;
        _trackpadLastScale = e.scale;
        if ((scaleStep - 1).abs() > 0.001) {
          _forwardZoom(scaleStep, e.localPosition);
        }
        final pan = e.localPanDelta;
        if (pan.dx != 0 || pan.dy != 0) {
          _forwardPan(pan.dx, pan.dy);
        }
      },
      onPointerPanZoomEnd: (_) => _trackpadLastScale = 1.0,
      child: webView,
    );
  }

  void _forwardPointer(String type, PointerEvent e) {
    final controller = _controller;
    if (controller == null) return;
    final kind = e.kind == PointerDeviceKind.mouse
        ? 'mouse'
        : e.kind == PointerDeviceKind.touch
        ? 'touch'
        : 'pen';
    final x = e.localPosition.dx;
    final y = e.localPosition.dy;
    unawaited(
      controller.runJavaScript(
        'window.__openhandDispatchPointer&&'
        'window.__openhandDispatchPointer("$type",${e.pointer},$x,$y,"$kind")',
      ),
    );
  }

  void _forwardZoom(double scaleFactor, Offset anchor) {
    final controller = _controller;
    if (controller == null) return;
    unawaited(
      controller.runJavaScript(
        'window.__openhandZoomAt&&'
        'window.__openhandZoomAt($scaleFactor,${anchor.dx},${anchor.dy})',
      ),
    );
  }

  void _forwardPan(double dx, double dy) {
    final controller = _controller;
    if (controller == null) return;
    unawaited(
      controller.runJavaScript(
        'window.__openhandPan&&window.__openhandPan($dx,$dy)',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controlsLocked =
        !_isReady || !_bridgeReady || _loadError != null || _controller == null;
    final body = Stack(
      children: [
        if (_controller != null)
          Positioned.fill(child: _buildWebViewWithGestures()),
        if (!_isReady)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              backgroundColor: widget.palette.containerColor,
              valueColor: AlwaysStoppedAnimation<Color>(
                widget.palette.actionTextColor,
              ),
            ),
          ),
        if (_loadError != null)
          Positioned.fill(
            child: Container(
              color: widget.palette.containerColor,
              padding: const EdgeInsets.all(12),
              alignment: Alignment.center,
              child: Text(
                _loadError!,
                style: TextStyle(color: widget.palette.actionTextColor),
              ),
            ),
          ),
      ],
    );
    return Column(
      key: _interactiveRegionKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: openHandDialogAwareScrollPhysics(context),
          child: Row(
            children: [
              _buildToolPill(
                label: openHandLocalizedText(context, zh: '适配', en: 'Fit'),
                icon: Icons.fit_screen_rounded,
                backgroundColor: widget.palette.actionColor,
                foregroundColor: widget.palette.actionTextColor,
                onTap: controlsLocked ? null : _fitToView,
              ),
              kOpenHandHGap8,
              _buildToolPill(
                label: openHandResetLabel(context),
                icon: Icons.center_focus_strong_rounded,
                backgroundColor: widget.palette.actionColor,
                foregroundColor: widget.palette.actionTextColor,
                onTap: controlsLocked ? null : _resetView,
              ),
              kOpenHandHGap8,
              _buildToolPill(
                label: openHandLocalizedText(
                  context,
                  zh: '复制 SVG',
                  en: 'Copy SVG',
                ),
                icon: Icons.copy_all_rounded,
                backgroundColor: widget.palette.actionColor,
                foregroundColor: widget.palette.actionTextColor,
                onTap: controlsLocked
                    ? null
                    : () => unawaited(_copySvgMarkup()),
              ),
              kOpenHandHGap8,
              _buildToolPill(
                label: openHandLocalizedText(
                  context,
                  zh: '复制图像',
                  en: 'Copy Image',
                ),
                icon: Icons.image_outlined,
                backgroundColor: widget.palette.actionColor,
                foregroundColor: widget.palette.actionTextColor,
                onTap: controlsLocked ? null : () => unawaited(_copySvgImage()),
              ),
              kOpenHandHGap8,
              _buildToolPill(
                label: openHandLocalizedText(
                  context,
                  zh: '导出 SVG',
                  en: 'Export SVG',
                ),
                icon: Icons.download_rounded,
                backgroundColor: widget.palette.actionColor,
                foregroundColor: widget.palette.actionTextColor,
                onTap: controlsLocked ? null : () => unawaited(_downloadSvg()),
              ),
              kOpenHandHGap8,
              _buildToolPill(
                label: openHandLocalizedText(
                  context,
                  zh: '导出 PNG',
                  en: 'Export PNG',
                ),
                icon: Icons.image_rounded,
                backgroundColor: widget.palette.actionColor,
                foregroundColor: widget.palette.actionTextColor,
                onTap: controlsLocked ? null : () => unawaited(_downloadPng()),
              ),
              kOpenHandHGap8,
              _buildToolPill(
                label: '${_zoomPercent.toStringAsFixed(0)}%',
                icon: Icons.search_rounded,
                backgroundColor: widget.palette.actionColor.withValues(
                  alpha: 0.72,
                ),
                foregroundColor: widget.palette.actionTextColor,
                onTap: controlsLocked ? null : _resetView,
              ),
            ],
          ),
        ),
        kOpenHandGap10,
        // 画布区域手势完全交给 WebView JS（touch-action: none + pointerdown/move/up），
        // 这里不要再用 Flutter Listener 拦截：macOS 的 WKWebView 是 platform view，
        // 不会把 pointer 事件回灌到 Flutter；iOS / Android 上的 webview_flutter 也是
        // 直接由 platform view 消费事件，Listener 收到的是 platform view 之外的空白处。
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 220, maxHeight: 560),
          child: ClipRRect(
            borderRadius: kOpenHandBorderRadius10,
            child: body,
          ),
        ),
      ],
    );
  }

  Future<void> _runMermaidCommand(String script) async {
    final controller = _controller;
    if (controller == null || !_isReady || _loadError != null) return;
    try {
      await controller.runJavaScript('''
        (function(){
          try {
            $script
          } catch (_) {}
        })();
      ''');
    } on PlatformException catch (error, stack) {
      silentLog('home_code_highlighting', '执行 Mermaid 命令失败', error, stack);
    } catch (error, stack) {
      silentLog('home_code_highlighting', '执行 Mermaid 命令失败', error, stack);
    }
  }

  void _resetView() {
    _BubbleHtmlInteractiveScope.maybeOf(context)?.markInteractiveTap();
    unawaited(
      _runMermaidCommand(
        'window.__openhandMermaidReset&&window.__openhandMermaidReset();',
      ),
    );
  }

  void _fitToView() {
    _BubbleHtmlInteractiveScope.maybeOf(context)?.markInteractiveTap();
    unawaited(
      _runMermaidCommand(
        'window.__openhandMermaidFit&&window.__openhandMermaidFit();',
      ),
    );
  }

  Future<void> _copySvgMarkup() async {
    if (mounted) {
      replaceOpenHandSnack(
        context,
        openHandLocalizedText(context, zh: '正在复制 SVG…', en: 'Copying SVG…'),
        duration: kOpenHandSnackBarBriefDuration,
      );
    }

    String svg = _svgMarkup.trim();
    if (svg.isEmpty) {
      final controller = _controller;
      if (controller == null) {
        _showSvgNotReadySnack();
        return;
      }
      try {
        final raw = await controller.runJavaScriptReturningResult(
          "(function(){try{var el=document.getElementById('inner');if(!el)return '';"
          "var n=el.querySelector('svg');if(!n)return '';"
          "return new XMLSerializer().serializeToString(n);}catch(_){return '';}})();",
        );
        if (raw is String && raw.isNotEmpty) {
          svg = raw.trim();
        }
      } catch (error, stack) {
        silentLog(
          'home_code_highlighting',
          '从 WebView 读取 Mermaid SVG',
          error,
          stack,
        );
      }
    }

    if (svg.isEmpty) {
      _showSvgNotReadySnack();
      return;
    }

    // macOS 上 Flutter 文本剪贴板 / Pasteboard.writeText 在部分
    // 用户环境里会"静默"返回成功但剪贴板里没数据；先走 OS 原生 pbcopy，
    // 再回退到 Pasteboard / OpenHand 剪贴板公共入口。
    final svgBytes = _svgUtf8Bytes(svg);
    bool writeOk = false;
    String? writeMethod;
    if (Platform.isMacOS) {
      try {
        final result = await runBinaryProcessWithTimeout(
          'pbcopy',
          const <String>[],
          stdinBytes: svgBytes,
          timeout: _svgClipboardProcessTimeout,
          maxStdoutBytes: 0,
          maxStderrBytes: _svgClipboardStderrMaxBytes,
          tag: 'home_code_highlighting.pbcopy',
        );
        if (result?.exitCode == 0) {
          writeOk = true;
          writeMethod = 'pbcopy';
        }
      } catch (error, stack) {
        silentLog('home_code_highlighting', '通过 pbcopy 复制 SVG', error, stack);
      }
    }
    if (!writeOk) {
      try {
        Pasteboard.writeText(svg);
        writeOk = true;
        writeMethod = 'Pasteboard.writeText';
      } catch (error, stack) {
        silentLog(
          'home_code_highlighting',
          '通过 Pasteboard.writeText 复制 SVG',
          error,
          stack,
        );
      }
    }
    if (!writeOk) {
      try {
        await setOpenHandClipboardText(svg);
        writeOk = true;
        writeMethod = 'setOpenHandClipboardText';
      } catch (error, stack) {
        silentLog(
          'home_code_highlighting',
          '通过 setOpenHandClipboardText 复制 SVG',
          error,
          stack,
        );
      }
    }

    // 验证剪贴板（OS 通道 pbpaste 优先，Flutter 通道为辅），用以决定
    // snackbar 文案与是否提供"打开文件"按钮。
    final verification = await _verifySvgClipboard(
      expectedByteLength: svgBytes.length,
    );

    // 始终把 SVG 写到 /tmp 临时文件，给用户一条不依赖剪贴板的可靠路径。
    String? savedPath;
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final tempFile = await writeNewTemporaryFileTextBounded(
        directoryPrefix: 'openhand_svg_',
        fileName: 'mermaid_$ts.svg',
        text: svg,
        timeout: _tempPreviewWriteTimeout,
        onSecondaryError: (error, stack) => silentLog(
          'home_code_highlighting',
          '清理 Mermaid SVG 临时文件',
          error,
          stack,
        ),
      );
      savedPath = tempFile.path;
    } catch (error, stack) {
      silentLog('home_code_highlighting', '写入 Mermaid SVG 临时文件', error, stack);
    }

    if (!mounted) return;
    final pathHint =
        savedPath ??
        openHandLocalizedText(
          context,
          zh: '临时文件写入失败',
          en: 'temp file write failed',
        );
    if (writeOk && verification.osLayerOk) {
      replaceOpenHandSnack(
        context,
        openHandLocalizedText(
          context,
          zh: 'SVG 已复制（${svgBytes.length} 字节，方法=$writeMethod）。如粘贴异常，可打开文件: $pathHint',
          en: 'SVG copied (${svgBytes.length}B, method=$writeMethod). If paste fails, file at: $pathHint',
        ),
        kind: OpenHandSnackKind.success,
        duration: kOpenHandSnackBarLongReadDuration,
        maxLines: 4,
      );
    } else {
      replaceOpenHandSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '剪贴板不可信：写 ${svgBytes.length}B, pbpaste 读 ${verification.pbpasteLen}B。SVG 已存到文件: $pathHint，请打开后复制。',
          en: 'Clipboard unreliable: wrote ${svgBytes.length}B, pbpaste read ${verification.pbpasteLen}B. SVG saved to: $pathHint. Open and copy.',
        ),
        kind: OpenHandSnackKind.error,
        duration: kOpenHandSnackBarLongReadDuration,
        maxLines: 4,
        action: savedPath == null
            ? null
            : SnackBarAction(
                label: _homeOpenLabel(context),
                onPressed: () {
                  unawaited(_openSavedSvgFile(savedPath!));
                },
              ),
      );
    }
  }

  Future<void> _openSavedSvgFile(String path) async {
    try {
      await openLocalPathWithSystemApp(
        path,
        tag: 'home_code_highlighting.open_saved_svg',
      );
    } catch (error, stack) {
      silentLog('home_code_highlighting', '打开已保存 SVG', error, stack);
    }
  }

  Future<_SvgClipboardVerification> _verifySvgClipboard({
    required int expectedByteLength,
  }) async {
    int pbpasteLen = 0;
    int pbpasteSvgOpenCount = 0;
    int pbpasteSvgCloseCount = 0;
    int flutterLen = 0;
    try {
      final result = await runBinaryProcessWithTimeout(
        'pbpaste',
        const <String>[],
        timeout: _svgClipboardProcessTimeout,
        maxStdoutBytes: math.min(
          math.max(expectedByteLength + 1, _svgClipboardVerificationMinBytes),
          _svgClipboardVerificationMaxBytes,
        ),
        maxStderrBytes: _svgClipboardStderrMaxBytes,
        tag: 'home_code_highlighting.pbpaste',
      );
      if (result?.exitCode == 0 && result?.stdout is Uint8List) {
        final bytes = result!.stdout as Uint8List;
        pbpasteLen = bytes.length;
        if (pbpasteLen > 0) {
          final text = utf8.decode(bytes, allowMalformed: true);
          pbpasteSvgOpenCount = '<svg'.allMatches(text).length;
          pbpasteSvgCloseCount = '</svg>'.allMatches(text).length;
        }
      }
    } catch (error, stack) {
      silentLog('home_code_highlighting', '通过 pbpaste 校验 SVG', error, stack);
    }
    final clipboardText = await getOpenHandClipboardText();
    flutterLen = clipboardText?.length ?? 0;
    final osLayerOk =
        pbpasteLen == expectedByteLength &&
        pbpasteSvgOpenCount == 1 &&
        pbpasteSvgCloseCount == 1;
    return _SvgClipboardVerification(
      pbpasteLen: pbpasteLen,
      flutterLen: flutterLen,
      osLayerOk: osLayerOk,
    );
  }

  void _showSvgNotReadySnack() {
    if (!mounted) return;
    replaceOpenHandSnack(
      context,
      openHandLocalizedText(
        context,
        zh: 'SVG 还未生成，请稍后再试。',
        en: 'SVG is not ready yet. Please try again.',
      ),
    );
  }

  Uint8List _svgUtf8Bytes(String svg) => Uint8List.fromList(utf8.encode(svg));

  Future<void> _copySvgImage() async {
    final pngBytes = _decodePngBytes(_pngDataUrl);
    if (pngBytes != null) {
      try {
        await writeOpenHandClipboardImage(pngBytes);
        if (!mounted) return;
        replaceOpenHandSnack(
          context,
          openHandLocalizedText(context, zh: '已复制图像。', en: 'Image copied.'),
          kind: OpenHandSnackKind.success,
        );
        return;
      } catch (error, stack) {
        silentLog('home_code_highlighting', '复制 Mermaid PNG 图片', error, stack);
      }
    }
    final svg = _svgMarkup.trim();
    if (svg.isEmpty) return;
    try {
      await writeOpenHandClipboardImage(_svgUtf8Bytes(svg));
      if (!mounted) return;
      replaceOpenHandSnack(
        context,
        openHandLocalizedText(
          context,
          zh: 'PNG 复制失败，已回退复制 SVG 图像。',
          en: 'PNG copy failed; copied SVG image instead.',
        ),
      );
    } catch (error, stack) {
      silentLog('home_code_highlighting', '兜底复制 Mermaid SVG 图片', error, stack);
      await _copySvgMarkup();
    }
  }

  Future<void> _downloadSvg() async {
    final svg = _svgMarkup.trim();
    if (svg.isEmpty) return;
    try {
      final location = await getSaveLocation(
        suggestedName: 'mermaid_diagram.svg',
        acceptedTypeGroups: <XTypeGroup>[
          const XTypeGroup(
            label: 'SVG',
            mimeTypes: <String>[kImageSvgXmlMimeType],
            extensions: <String>['svg'],
          ),
        ],
      );
      final path = location?.path;
      if (!mounted || path == null || path.isEmpty) return;
      await writeFileAtomically(File(path), svg);
      if (!mounted) return;
      replaceOpenHandSnack(
        context,
        openHandLocalizedText(context, zh: 'SVG 已导出。', en: 'SVG exported.'),
        kind: OpenHandSnackKind.success,
      );
    } catch (error, stack) {
      silentLog('home_code_highlighting', '下载 Mermaid SVG', error, stack);
    }
  }

  Future<void> _downloadPng() async {
    final pngBytes = _decodePngBytes(_pngDataUrl);
    if (pngBytes == null) {
      if (!mounted) return;
      replaceOpenHandSnack(
        context,
        openHandLocalizedText(
          context,
          zh: 'PNG 仍未就绪，请稍后重试。',
          en: 'PNG is not ready yet. Please try again.',
        ),
      );
      return;
    }
    try {
      final location = await getSaveLocation(
        suggestedName: 'mermaid_diagram.png',
        acceptedTypeGroups: <XTypeGroup>[
          const XTypeGroup(
            label: 'PNG',
            mimeTypes: <String>[kImagePngMimeType],
            extensions: <String>['png'],
          ),
        ],
      );
      final path = location?.path;
      if (!mounted || path == null || path.isEmpty) return;
      await writeBytesFileAtomically(File(path), pngBytes);
      if (!mounted) return;
      replaceOpenHandSnack(
        context,
        openHandLocalizedText(context, zh: 'PNG 已导出。', en: 'PNG exported.'),
        kind: OpenHandSnackKind.success,
      );
    } catch (error, stack) {
      silentLog('home_code_highlighting', '下载 Mermaid PNG', error, stack);
    }
  }

  ({String bg, String fg, String border}) _computeMermaidThemeColors() {
    String argbToCss(Color c) => c.toARGB32().toRadixString(16).padLeft(8, '0');
    String argbToRgbHex(Color c) {
      final hex = argbToCss(c);
      return hex.length == 8 ? hex.substring(2) : hex;
    }

    return (
      bg: argbToRgbHex(widget.palette.containerColor),
      fg: argbToRgbHex(widget.palette.actionTextColor),
      border: argbToRgbHex(widget.palette.borderColor),
    );
  }

  /// 构建由 Dart 端 runJavaScript 注入的 mermaid 渲染脚本。
  /// 不再嵌在 HTML 模板中——WKWebView 对内联 <script> 标签偶发
  /// 不执行，runJavaScript 走 platform channel 注入绕开此问题。
  String _buildRenderJs(String bg, String fg, String border) {
    return '''
(function () {
  var post = function (value) {
    try {
      if (window.OpenHandMermaid && window.OpenHandMermaid.postMessage) {
        window.OpenHandMermaid.postMessage(value);
      }
    } catch (e) {}
  };
  try {
    if (!window.mermaid) {
      post('error:mermaid-js 加载失败');
      post('ready');
      return;
    }
    window.mermaid.initialize({
      startOnLoad: false,
      theme: 'base',
      securityLevel: 'loose',
      flowchart: { useMaxWidth: false, htmlLabels: true, curve: 'basis' },
      sequence: { useMaxWidth: false, showSequenceNumbers: true },
      gantt: { useMaxWidth: false },
      themeVariables: {
        fontSize: '13px',
        background: '#$bg',
        primaryColor: '#$bg',
        primaryBorderColor: '#$border',
        primaryTextColor: '#$fg',
        secondaryColor: '#$bg',
        tertiaryColor: '#$bg',
        lineColor: '#$fg',
      },
    });
    var sourceEl = document.getElementById('mermaid-source');
    var source = (sourceEl && sourceEl.textContent) || '';
    function svgMarkupOf(value) {
      if (typeof value === 'string') return value;
      if (value && value.tagName && String(value.tagName).toLowerCase() === 'svg') {
        return value.outerHTML || '';
      }
      return '';
    }
    function stripBackgroundRect(svgStr) {
      // 关键：BFS 级去除所有"背景着色"痕迹：
      // 1. 摘掉所有 rect.background / rect[class*="background"] 节点
      // 2. 抹掉所有 inline style="background:..." 属性
      // 3. 把 style 块里 --background:... 炸成 transparent
      // 4. 把 style 块里所有 var(--background, #RRGGBB) 回退值炸掉
      // 5. 收尾：所有 fill="var(--..." 也替换 fill 为 transparent
      return svgStr
        .replace(/<rect[^>]*\\bclass=["'][^"']*\\bbackground\\b[^"']*["'][^>]*\\/?>/gi, '')
        .replace(/<rect[^>]*class=["'][^"']*background[^"']*["'][^>]*\\/?>/gi, '')
        .replace(/\\sstyle=["'][^"']*background[^"']*["']/gi, '')
        .replace(/--background\\s*:\\s*[^;!}]+/gi, '--background: transparent')
        .replace(/var\\s*\\(\\s*--background\\s*,[^)]*\\)/gi, 'transparent');
    }
    window.mermaid.render('mermaid-svg', source).then(function (result) {
      var svg = svgMarkupOf(result) || svgMarkupOf(result && result.svg);
      if (!svg || svg.indexOf('<svg') === -1) {
        throw new Error('svg_not_found_in_result');
      }
      svg = stripBackgroundRect(svg);
      var inner = document.getElementById('inner');
      if (inner) {
        inner.innerHTML = svg;
        try {
          var svgEl = inner.querySelector('svg');
          if (svgEl) {
            // 关键：直接在 DOM 上设 style.background 覆盖 inline/interior
            // style 里的任何 var(--background, #B00020) 回退值。
            svgEl.style.setProperty('background', 'transparent', 'important');
            svgEl.style.setProperty('background-color', 'transparent', 'important');
            svgEl.removeAttribute('style');
            var bgRects = svgEl.querySelectorAll('rect.background, rect[class*="background"]');
            for (var ri = 0; ri < bgRects.length; ri++) {
              var r = bgRects[ri];
              r.parentNode && r.parentNode.removeChild(r);
            }
            var styleBlocks = svgEl.querySelectorAll('style');
            for (var si = 0; si < styleBlocks.length; si++) {
              styleBlocks[si].textContent = (styleBlocks[si].textContent || '')
                .replace(/--background\\s*:\\s*[^;!}]+/g, '--background: transparent')
                // 关键：把 style 块里所有 var(--background, *) 回退值也炸掉
                .replace(/var\\s*\\(\\s*--background\\s*,[^)]*\\)/gi, 'transparent');
            }
          }
        } catch (_) {}
      }
      post('svg:' + svg);
      try {
        if (result && typeof result.bindFunctions === 'function') {
          result.bindFunctions(document.getElementById('inner'));
        }
      } catch (_) {}
      try {
        var svgNode = document.querySelector('#inner svg');
        if (svgNode) {
          var box = svgNode.getBBox
            ? svgNode.getBBox()
            : { x: 0, y: 0, width: svgNode.clientWidth || 1, height: svgNode.clientHeight || 1 };
          var canvas = document.createElement('canvas');
          canvas.width = Math.max(1, Math.ceil(box.width || svgNode.clientWidth || 1));
          canvas.height = Math.max(1, Math.ceil(box.height || svgNode.clientHeight || 1));
          var ctx = canvas.getContext('2d');
          if (ctx) {
            var img = new Image();
            img.onload = function () {
              try {
                ctx.clearRect(0, 0, canvas.width, canvas.height);
                ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
                post('png:' + canvas.toDataURL('image/png'));
              } catch (_) {}
            };
            img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg);
          }
        }
      } catch (_) {}
      post('rendered');
    }).catch(function (err) {
      var inner = document.getElementById('inner');
      if (inner) {
        inner.innerHTML = '<div class="mermaid-error">' + String(err) + '</div>';
      }
      post('error:render_failed:' + String(err));
    }).then(function () {
      post('ready');
    });
  } catch (outerErr) {
    try {
      post('error:outer_crash:' + (outerErr && outerErr.message ? outerErr.message : String(outerErr)));
      post('ready');
    } catch (_) {}
  }
})();
''';
  }

  String _buildMermaidHtml(
    String bgRgb,
    String fgRgb,
    String borderRgb,
    String mermaidJs,
  ) {
    final rawSource = widget.source;
    final escaped = const HtmlEscape(HtmlEscapeMode.element).convert(rawSource);
    final isDark = widget.palette.headerColor.computeLuminance() < 0.4;
    final palette = widget.palette;
    // 关键：toARGB32() 返回 0xAARRGGBB，CSS 8位 hex 是 #RRGGBBAA，
    // 直接 toRadixString(16) 会把 alpha(ff) 当 red 用 → #FF1E1E24
    // 在浏览器里变成 R=FF 亮红，导致整个 Mermaid 视图背景"深红色"。
    // 只取后 6 位 RRGGBB（颜色必定不透明，alpha 直接丢弃）。
    String cssHex(Color c) {
      final hex = c.toARGB32().toRadixString(16).padLeft(8, '0');
      return hex.length >= 7 ? hex.substring(hex.length - 6) : hex;
    }

    final bgHex = cssHex(palette.bodyColor);
    final fgHex = cssHex(palette.actionTextColor);
    // 把渲染 IIFE 内联到模板末尾，与 mermaid.js 同一个 <script> 标签。
    final renderJs = _buildRenderJs(bgRgb, fgRgb, borderRgb);
    return '''
<!doctype html>
<html>
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=4.0, user-scalable=yes" />
<title>Mermaid</title>
<style>
  :root { color-scheme: ${isDark ? 'dark' : 'light'}; }
  html, body {
    margin: 0; padding: 0; width: 100%; height: 100%;
    background: #$bgHex; color: #$fgHex;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
    overflow: hidden;
  }
  .mermaid-stage {
    /* position: fixed + inset:0 让 stage 始终铺满 WKWebView 视口，
       不依赖 html/body 100% 高度链，避免边缘情况下 stage 塌成 0x0
       而吃不到 pointer 事件。 */
    position: fixed;
    top: 0; left: 0; right: 0; bottom: 0;
    touch-action: none;
    overflow: hidden;
    cursor: grab;
    user-select: none;
    -webkit-user-select: none;
  }
  .mermaid-stage:active { cursor: grabbing; }
  .mermaid-stage .mermaid-inner {
    transform-origin: 0 0;
    transition: transform 80ms ease-out;
  }
  .mermaid-stage svg { max-width: none; height: auto; }
  /* 关键：Mermaid 10.x 输出的 SVG 自带一个 <rect class="background"> 节点
     填满整张画布并使用 fill: var(--background, #1f2020)。当 --background
     在 10.9.1 的内联 style 里被错算成 #B00020（红色）时，整张画布就会
     染成与代码块容器色割裂的红色。强制把这个 rect + var(--background)
     双向 transparent，让 body 的 #$bgHex 直接透出。 */
  .mermaid-stage svg,
  .mermaid-stage svg .root,
  .mermaid-stage svg .root > *,
  .mermaid-stage svg > g,
  .mermaid-stage svg > rect { background: transparent !important; }
  .mermaid-stage svg > rect,
  .mermaid-stage svg .background,
  .mermaid-stage svg rect.background,
  .mermaid-stage svg [class*="background"] { fill: transparent !important; }
  /* 关键：Mermaid base 主题 CSS 用 var(--background, #B00020) 回退值
     把整张画布染红。这里直接在 svg 元素上把 background 写死 transparent，
     同时覆盖 --background 变量，双保险不让 var() 的 red fallback 生效。 */
  .mermaid-stage svg { --background: transparent !important; background: transparent !important; }
  .mermaid-error {
    color: #d93025; padding: 16px; font-size: 13px;
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    white-space: pre-wrap;
  }
</style>
</head>
<body>
  <div class="mermaid-stage" id="stage">
    <div class="mermaid-inner" id="inner">
      <pre class="mermaid" id="mermaid-source">$escaped</pre>
    </div>
  </div>
  <script>
    // mermaid.js 内联 + 渲染 IIFE，单文件单 script 标签加载。
    $mermaidJs
    $renderJs
  </script>
  <script>
    // IIFE #2: 平移/缩放/双击重置手势；fit/reset 通过全局桥接函数暴露。
    (function () {
      var stage = document.getElementById('stage');
      var inner = document.getElementById('inner');
      if (!stage || !inner) return;
      var state = { scale: 1, tx: 0, ty: 0 };
      var pointers = new Map();
      var pinchStartDist = 0;
      var pinchStartScale = 1;
      var longPressTimer = null;
      var dragReady = false;
      var longPressPointerId = null;
      // tap 转发：记录本轮手势的起点位置和累计移动量，
      // 在所有手指抬起且无拖动时向 elementFromPoint 派发 click。
      var tapStart = null;
      var pointerMoved = false;
      var post = function (value) {
        if (window.OpenHandMermaid && window.OpenHandMermaid.postMessage) {
          window.OpenHandMermaid.postMessage(value);
        }
      };
      var postZoom = function () { post('zoom:' + Math.round(state.scale * 100)); };
      var postDrag = function (active) { post('drag:' + (active ? '1' : '0')); };
      var clearLongPress = function () {
        if (longPressTimer) { clearTimeout(longPressTimer); longPressTimer = null; }
      };
      var setInteractiveTransition = function (enabled) {
        inner.style.transition = enabled ? 'transform 80ms ease-out' : 'none';
      };
      var apply = function () {
        inner.style.transform = 'translate(' + state.tx + 'px,' + state.ty + 'px) scale(' + state.scale + ')';
        postZoom();
      };
      var forwardTap = function (x, y) {
        try {
          var el = document.elementFromPoint(x, y);
          if (!el || el === stage) return;
          var opts = { bubbles: true, cancelable: true, view: window,
                       clientX: x, clientY: y, button: 0 };
          el.dispatchEvent(new MouseEvent('click', opts));
          // 兼容依赖 PointerEvent 的 mermaid click handler。
          try {
            el.dispatchEvent(new PointerEvent('pointerdown',
              Object.assign({ pointerType: 'mouse', isPrimary: true }, opts)));
            el.dispatchEvent(new PointerEvent('pointerup',
              Object.assign({ pointerType: 'mouse', isPrimary: true }, opts)));
          } catch (_) {}
          if (typeof el.focus === 'function') { try { el.focus(); } catch (_) {} }
        } catch (_) {}
      };
      var reset = function () {
        clearLongPress();
        dragReady = false;
        longPressPointerId = null;
        state.scale = 1; state.tx = 0; state.ty = 0;
        setInteractiveTransition(true);
        postDrag(false);
        apply();
      };
      var fit = function () {
        setInteractiveTransition(true);
        clearLongPress();
        dragReady = false;
        longPressPointerId = null;
        var svg = inner.querySelector('svg');
        if (!svg || !svg.getBBox) { reset(); return; }
        var stageRect = stage.getBoundingClientRect();
        var box = svg.getBBox();
        if (!(box.width > 0) || !(box.height > 0) || !(stageRect.width > 0) || !(stageRect.height > 0)) {
          reset();
          return;
        }
        var padding = 24;
        var fitScale = Math.min(8, Math.max(0.2, Math.min(
          (stageRect.width - padding * 2) / box.width,
          (stageRect.height - padding * 2) / box.height,
        )));
        state.scale = fitScale;
        state.tx = padding - box.x * fitScale + Math.max(0, (stageRect.width - box.width * fitScale - padding * 2) / 2);
        state.ty = padding - box.y * fitScale + Math.max(0, (stageRect.height - box.height * fitScale - padding * 2) / 2);
        postDrag(false);
        apply();
      };
      window.__openhandMermaidReset = reset;
      window.__openhandMermaidFit = fit;
      // macOS 上 webview_flutter 把 WKWebView 嵌成 Flutter 子层，Flutter
      // 的命中测试会先吃掉 pointer 事件，WebView 内的 JS 监听拿不到。
      // 因此 Flutter 端在 macOS 用 Listener 接住事件，转手通过下面这些
      // 桥接函数派发等价 PointerEvent / 直接操作 transform，让已有手势
      // 逻辑无缝复用。iOS / Android / WEB 内嵌时仍走原生事件路径。
      window.__openhandDispatchPointer = function (type, id, x, y, kind) {
        try {
          var event = new PointerEvent('pointer' + type, {
            pointerId: id,
            clientX: x,
            clientY: y,
            pointerType: kind || 'mouse',
            isPrimary: true,
            bubbles: true,
            cancelable: true,
            button: 0,
            buttons: (type === 'down' || type === 'move') ? 1 : 0,
          });
          stage.dispatchEvent(event);
        } catch (_) {}
      };
      window.__openhandZoomAt = function (scaleFactor, anchorX, anchorY) {
        clearLongPress();
        setInteractiveTransition(false);
        var newScale = Math.min(8, Math.max(0.2, state.scale * scaleFactor));
        if (newScale === state.scale) return;
        var rect = stage.getBoundingClientRect();
        var cx = anchorX - rect.left;
        var cy = anchorY - rect.top;
        state.tx = cx - (cx - state.tx) * (newScale / state.scale);
        state.ty = cy - (cy - state.ty) * (newScale / state.scale);
        state.scale = newScale;
        apply();
      };
      window.__openhandPan = function (dx, dy) {
        if (dx === 0 && dy === 0) return;
        setInteractiveTransition(false);
        state.tx += dx;
        state.ty += dy;
        apply();
      };
      // 滚轮 + Ctrl/Cmd 缩放，以光标为锚点（原生 wheel 兜底，
      // 桌面端会被 Flutter Listener 截掉，所以主路径走 __openhandZoomAt）。
      stage.addEventListener('wheel', function (e) {
        if (!(e.ctrlKey || e.metaKey)) return;
        e.preventDefault();
        clearLongPress();
        setInteractiveTransition(false);
        var delta = -e.deltaY * 0.0025;
        var newScale = Math.min(8, Math.max(0.2, state.scale * (1 + delta)));
        var rect = stage.getBoundingClientRect();
        var cx = e.clientX - rect.left;
        var cy = e.clientY - rect.top;
        state.tx = cx - (cx - state.tx) * (newScale / state.scale);
        state.ty = cy - (cy - state.ty) * (newScale / state.scale);
        state.scale = newScale;
        apply();
      }, { passive: false });
      var onPointerDown = function (e) {
        try { stage.setPointerCapture(e.pointerId); } catch (_) {}
        // 阻止 iOS Safari / 桌面浏览器默认手势（图片拖出、长按菜单等）。
        if (e.cancelable) e.preventDefault();
        pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
        if (pointers.size === 2) {
          clearLongPress();
          dragReady = false;
          tapStart = null;
          pointerMoved = false;
          postDrag(false);
          setInteractiveTransition(false);
          var pts = Array.from(pointers.values());
          pinchStartDist = Math.hypot(pts[0].x - pts[1].x, pts[0].y - pts[1].y);
          pinchStartScale = state.scale;
          return;
        }
        if (pointers.size !== 1) return;
        dragReady = false;
        pointerMoved = false;
        tapStart = { x: e.clientX, y: e.clientY };
        postDrag(false);
        longPressPointerId = e.pointerId;
        stage.dataset.dragX = String(e.clientX);
        stage.dataset.dragY = String(e.clientY);
        stage.dataset.dragTx = String(state.tx);
        stage.dataset.dragTy = String(state.ty);
        clearLongPress();
        if (e.pointerType === 'mouse') {
          // 桌面鼠标按下即可拖；但保留 tapStart，让"按下后没移动直接抬起"
          // 还能识别成 tap 转发到 mermaid 节点，链接/回调不丢。
          dragReady = true;
          postDrag(true);
          setInteractiveTransition(false);
          return;
        }
        longPressTimer = setTimeout(function () {
          if (pointers.size === 1 && longPressPointerId === e.pointerId) {
            dragReady = true;
            tapStart = null;
            postDrag(true);
            setInteractiveTransition(false);
          }
        }, 280);
      };
      var onPointerMove = function (e) {
        if (!pointers.has(e.pointerId)) return;
        var previous = pointers.get(e.pointerId);
        var dx = previous ? (e.clientX - previous.x) : 0;
        var dy = previous ? (e.clientY - previous.y) : 0;
        var moved = Math.hypot(dx, dy);
        pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
        if (moved > 4) pointerMoved = true;
        if (pointers.size === 2) {
          clearLongPress();
          dragReady = false;
          tapStart = null;
          postDrag(false);
          setInteractiveTransition(false);
          var pts = Array.from(pointers.values());
          var dist = Math.hypot(pts[0].x - pts[1].x, pts[0].y - pts[1].y);
          if (pinchStartDist > 0) {
            // 双指缩放以双指中心为锚点。
            var rect = stage.getBoundingClientRect();
            var centerX = (pts[0].x + pts[1].x) / 2 - rect.left;
            var centerY = (pts[0].y + pts[1].y) / 2 - rect.top;
            var newScale = Math.min(8, Math.max(0.2, pinchStartScale * (dist / pinchStartDist)));
            state.tx = centerX - (centerX - state.tx) * (newScale / state.scale);
            state.ty = centerY - (centerY - state.ty) * (newScale / state.scale);
            state.scale = newScale;
            apply();
          }
          return;
        }
        if (pointers.size === 1) {
          if (!dragReady && moved > 8) clearLongPress();
          if (dragReady && stage.dataset.dragX) {
            var ddx = e.clientX - parseFloat(stage.dataset.dragX);
            var ddy = e.clientY - parseFloat(stage.dataset.dragY);
            state.tx = parseFloat(stage.dataset.dragTx) + ddx;
            state.ty = parseFloat(stage.dataset.dragTy) + ddy;
            apply();
          }
        }
      };
      var onPointerEnd = function (e) {
        pointers.delete(e.pointerId);
        clearLongPress();
        if (pointers.size < 2) pinchStartDist = 0;
        if (pointers.size === 0) {
          // "未发生移动" 就是 tap，鼠标/触屏一致 —— 鼠标按下即 dragReady
          // 不再当作非 tap，避免单击 mermaid 节点时丢链接回调。
          var wasTap = tapStart != null && !pointerMoved;
          var tapX = tapStart ? tapStart.x : 0;
          var tapY = tapStart ? tapStart.y : 0;
          dragReady = false;
          longPressPointerId = null;
          tapStart = null;
          pointerMoved = false;
          postDrag(false);
          setInteractiveTransition(true);
          delete stage.dataset.dragX;
          delete stage.dataset.dragY;
          delete stage.dataset.dragTx;
          delete stage.dataset.dragTy;
          if (wasTap) forwardTap(tapX, tapY);
        }
      };
      // 关键修复：使用 capture 阶段。Mermaid 10.x 在 SVG 节点上挂的
      // click / pointer 处理器会 e.stopPropagation()，把 pointer 事件
      // 拦在 SVG 内不再冒泡到 stage；切到 capture 后 stage 的监听
      // 会在 SVG 自己的处理器之前触发，gesture 真正能拿到事件。
      stage.addEventListener('pointerdown', onPointerDown, { capture: true });
      stage.addEventListener('pointermove', onPointerMove, { capture: true });
      stage.addEventListener('pointerup', onPointerEnd, { capture: true });
      stage.addEventListener('pointercancel', onPointerEnd, { capture: true });
      stage.addEventListener('dblclick', function () { reset(); });
    })();
  </script>
</body>
</html>
''';
  }
}
