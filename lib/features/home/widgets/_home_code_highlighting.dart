part of '../openhand_home_page.dart';

/// Maximum code-block length (in characters) at which we still attempt
/// syntax highlighting. Beyond this we render plain monospace text to keep
/// transcript open / scroll responsive (very long log dumps were the
/// dominant source of multi-second jank when opening a session).
const int _highlightSkipThresholdChars = 80 * 1024;

/// Code-block length above which we defer the first highlight pass to the
/// next frame, painting plain text on the first frame.
///
/// 阶段㉑ — 设为 1024 字节：平衡首帧响应速度与视觉闪烁。
/// < 1KB 的短代码片段同步高亮（瞬间完成，无闪烁）；
/// >= 1KB 的代码块走 FrameScheduler 分帧高亮（首帧纯文本，后续帧补色）。
/// _buildCodeBody 的 null 回退确保即使 span 为 null 也能显示内容。
/// 阶段㉒ — 1024 → 256：tool_call 卡的 JSON 参数普遍 200-800 字符，
/// 之前同步高亮路径在多 tool_call 同帧 mount 时叠加直接撑爆主线程。
/// 降阈值让几乎所有非平凡代码块都走异步分帧高亮。
const int _highlightDeferThresholdChars = 256;

/// Process-wide LRU cache for parsed code-block `TextSpan`s. The same code
/// snippet (e.g. a tool result, a generated diff) frequently appears in
/// many bubbles across a session; reusing the cached span avoids
/// re-tokenising on every rebuild and on cross-session navigation.
///
/// 阶段⑲ — 256 → 512：含多 tool 调用的长会话很容易超过 256 条命中边
/// 界；把 LRU 容量翻倍换内存（每条仅 ~几 KiB span）能显著提升命中率。
final _HighlightSpanCache _highlightSpanCache = _HighlightSpanCache(
  maxEntries: 512,
);

/// 阶段⑳：全局帧分散调度器。当一条消息含 N 个代码块同时展开时，
/// 所有代码块的 highlight 回调都注册到同一个 addPostFrameCallback，
/// 导致下一帧仍然要同步执行 N 次 tokenize。此调度器将 N 个任务分散
/// 到 ceil(N/2) 个帧中执行（每帧最多处理 2 个），彻底消除 ANR。
class _HighlightFrameScheduler {
  _HighlightFrameScheduler._();
  static final instance = _HighlightFrameScheduler._();

  final List<VoidCallback> _pending = [];
  bool _draining = false;

  /// 每帧最多执行的 highlight 任务数。
  /// 阶段㉒：3 → 1。一些大段 bash/log 输出 tokenize 单次可能 ~30ms，
  /// 同帧 3 个就直接撑爆 60 fps 帧预算。改为 1/帧后慢机器也能稳；
  /// 配合 [_HighlightSpanCache] 第二次展开/滚回时仍能瞬时拉起。
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
    // 取出本帧要执行的任务（最多 _maxPerFrame 个）
    final batch = _pending.length <= _maxPerFrame
        ? List<VoidCallback>.from(_pending)
        : _pending.sublist(0, _maxPerFrame);
    _pending.removeRange(0, batch.length);
    for (final task in batch) {
      task();
    }
    // 如果还有剩余，继续调度下一帧
    if (_pending.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(_drain);
    } else {
      _draining = false;
    }
  }
}

class _HighlightSpanCache {
  _HighlightSpanCache({required this.maxEntries});

  final int maxEntries;
  final LinkedHashMap<int, TextSpan> _entries = LinkedHashMap<int, TextSpan>();

  TextSpan? get(int key) {
    final value = _entries.remove(key);
    if (value != null) {
      _entries[key] = value;
    }
    return value;
  }

  void put(int key, TextSpan value) {
    _entries.remove(key);
    _entries[key] = value;
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }
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
    return RepaintBoundary(
      child: _HighlightedCodePanel(
        content: content,
        theme: _theme,
        language: language,
        selectable: _selectable,
        baseColor: _baseColor,
        forceDarkSurface: _darkSurface,
        allowAutoDetection: true,
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

class _HighlightedCodePanel extends StatefulWidget {
  const _HighlightedCodePanel({
    required this.content,
    required this.theme,
    required this.baseColor,
    required this.selectable,
    this.language,
    this.forceDarkSurface = false,
    this.accentColor,
    this.allowAutoDetection = false,
    this.wrapLines = false,
  });

  final String content;
  final ThemeData theme;
  final String? language;
  final Color baseColor;
  final bool selectable;
  final bool forceDarkSurface;
  final Color? accentColor;
  final bool allowAutoDetection;
  final bool wrapLines;

  @override
  State<_HighlightedCodePanel> createState() => _HighlightedCodePanelState();
}

class _HighlightedCodePanelState extends State<_HighlightedCodePanel> {
  TextSpan? _highlightedSpan;
  int? _highlightSignature;
  bool _copied = false;
  bool _downloaded = false;
  bool _mermaidViewActive = false;
  Timer? _copiedResetTimer;
  Timer? _downloadedResetTimer;
  _CodeBlockPalette? _cachedPalette;
  int? _cachedPaletteSignature;
  bool _highlightScheduled = false;
  bool _highlightIsPlaceholder = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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
        oldWidget.allowAutoDetection != widget.allowAutoDetection ||
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
      _copiedResetTimer?.cancel();
      _copied = false;
      _downloadedResetTimer?.cancel();
      _downloaded = false;
    }
    _ensureHighlightedSpan();
  }

  @override
  void dispose() {
    _copiedResetTimer?.cancel();
    _downloadedResetTimer?.cancel();
    super.dispose();
  }

  void _toggleMermaidView() {
    _BubbleHtmlInteractiveScope.maybeOf(context)?.markInteractiveTap();
    setState(() {
      _mermaidViewActive = !_mermaidViewActive;
    });
  }

  @override
  Widget build(BuildContext context) {
    final effectiveLanguage = _normalizeCodeLanguage(widget.language);
    final useDarkPalette =
        widget.forceDarkSurface || widget.theme.brightness == Brightness.dark;
    final paletteSignature = Object.hashAll(<Object?>[
      widget.theme.colorScheme.primary.toARGB32(),
      widget.theme.brightness.index,
      useDarkPalette,
      widget.accentColor?.toARGB32(),
    ]);
    if (_cachedPalette == null || _cachedPaletteSignature != paletteSignature) {
      _cachedPalette = _CodeBlockPalette.fromTheme(
        widget.theme,
        useDarkPalette: useDarkPalette,
        accentColor: widget.accentColor,
      );
      _cachedPaletteSignature = paletteSignature;
    }
    final palette = _cachedPalette!;
    final copyLabel = _localizedText(
      context,
      zh: _copied ? '已复制' : '复制',
      en: _copied ? 'Copied' : 'Copy',
    );
    final downloadLabel = _localizedText(
      context,
      zh: _downloaded ? '已下载' : '下载',
      en: _downloaded ? 'Downloaded' : 'Download',
    );
    final runLabel = _localizedText(context, zh: '运行', en: 'Run');
    final isHtmlLanguage = _isHtmlLanguage(effectiveLanguage);
    final isMermaidLanguage = _isMermaidLanguage(effectiveLanguage);
    final viewLabel = _localizedText(
      context,
      zh: _mermaidViewActive ? '代码' : '视图',
      en: _mermaidViewActive ? 'Code' : 'View',
    );
    // 修复：将 border 移至 foregroundDecoration，确保边框绘制在子组件
    // 之上，避免 header 背景色在圆角处覆盖 border。
    // decoration 仅负责背景色 + 圆角裁剪；foregroundDecoration 负责边框。
    return Container(
      decoration: BoxDecoration(
        color: palette.containerColor,
        borderRadius: _borderRadius18,
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: _borderRadius18,
        border: Border.all(color: palette.borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: palette.headerColor,
              border: Border(bottom: BorderSide(color: palette.dividerColor)),
            ),
            child: Row(
              children: [
                if (effectiveLanguage != null)
                  _buildToolPill(
                    label: effectiveLanguage,
                    icon: Icons.code_rounded,
                    backgroundColor: palette.badgeColor,
                    foregroundColor: palette.badgeTextColor,
                  )
                else
                  const SizedBox(height: 32),
                const Spacer(),
                if (isMermaidLanguage) ...[
                  _buildToolPill(
                    label: viewLabel,
                    icon: _mermaidViewActive
                        ? Icons.code_rounded
                        : Icons.visibility_outlined,
                    backgroundColor: _mermaidViewActive
                        ? palette.actionColor
                        : palette.actionColor,
                    foregroundColor: palette.actionTextColor,
                    onTap: _toggleMermaidView,
                  ),
                  const SizedBox(width: 8),
                ],
                _buildToolPill(
                  label: copyLabel,
                  icon: _copied
                      ? Icons.check_rounded
                      : Icons.content_copy_rounded,
                  backgroundColor: palette.actionColor,
                  foregroundColor: palette.actionTextColor,
                  onTap: () {
                    _BubbleHtmlInteractiveScope.maybeOf(
                      context,
                    )?.markInteractiveTap();
                    _copyCodeBlock();
                  },
                ),
                const SizedBox(width: 8),
                _buildToolPill(
                  label: downloadLabel,
                  icon: _downloaded
                      ? Icons.check_rounded
                      : Icons.download_rounded,
                  backgroundColor: palette.actionColor,
                  foregroundColor: palette.actionTextColor,
                  onTap: () {
                    _BubbleHtmlInteractiveScope.maybeOf(
                      context,
                    )?.markInteractiveTap();
                    _downloadCodeBlock(effectiveLanguage);
                  },
                ),
                if (isHtmlLanguage) ...[
                  const SizedBox(width: 8),
                  _buildToolPill(
                    label: runLabel,
                    icon: Icons.play_arrow_rounded,
                    backgroundColor: palette.actionColor,
                    foregroundColor: palette.actionTextColor,
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
          Padding(
            padding: const EdgeInsets.all(14),
            child: isMermaidLanguage && _mermaidViewActive
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
                : _buildCodeBody(palette),
          ),
        ],
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
    //
    // The LRU cache ensures that on second expand (user's observation: "再次
    // 打开折叠消息卡片，卡顿情况会减少很多"), the highlight is instant.
    if (widget.content.length > _highlightDeferThresholdChars) {
      _highlightedSpan = TextSpan(
        text: widget.content,
        style: _baseStyleForCurrentTheme(useDarkPalette),
      );
      _highlightSignature = signature;
      _highlightIsPlaceholder = true;
      if (!_highlightScheduled) {
        _highlightScheduled = true;
        _HighlightFrameScheduler.instance.schedule(() {
          if (!mounted) return;
          _highlightScheduled = false;
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
        });
      }
      return;
    }
    _highlightedSpan = _runHighlight(
      effectiveLanguage,
      useDarkPalette,
      signature,
    );
    _highlightSignature = signature;
    _highlightIsPlaceholder = false;
  }

  int _highlightSignatureFor({
    required String? effectiveLanguage,
    required bool useDarkPalette,
  }) {
    return Object.hashAll(<Object?>[
      widget.content,
      effectiveLanguage,
      widget.allowAutoDetection,
      widget.baseColor.toARGB32(),
      useDarkPalette,
      widget.theme.textTheme.bodyMedium?.fontSize,
      widget.theme.textTheme.bodyMedium?.fontFamily,
      widget.theme.textTheme.bodyMedium?.height,
    ]);
  }

  TextStyle _baseStyleForCurrentTheme(bool useDarkPalette) {
    return widget.theme.textTheme.bodyMedium?.copyWith(
          color: widget.baseColor,
          fontFamily: 'monospace',
          height: 1.48,
        ) ??
        TextStyle(
          color: widget.baseColor,
          fontFamily: 'monospace',
          height: 1.48,
        );
  }

  TextSpan _runHighlight(
    String? effectiveLanguage,
    bool useDarkPalette,
    int signature,
  ) {
    // 阶段⑲ — 给 highlight tokenizer 加 Timeline 标记，方便 devtools
    // 性能面板按帧定位耗时来源（仅 debug/profile 模式可见，release 由
    // dart:developer 自身 tree-shake 掉）。
    final timelineLabel = effectiveLanguage == null || effectiveLanguage.isEmpty
        ? 'highlight(auto, ${widget.content.length}c)'
        : 'highlight($effectiveLanguage, ${widget.content.length}c)';
    return developer.Timeline.timeSync<TextSpan>(timelineLabel, () {
      final highlighter = _CodeSyntaxHighlighter(
        baseStyle: _baseStyleForCurrentTheme(useDarkPalette),
        darkSurface: useDarkPalette,
      );
      final span = highlighter.build(
        widget.content,
        language: effectiveLanguage,
        allowAutoDetection: widget.allowAutoDetection,
      );
      _highlightSpanCache.put(signature, span);
      return span;
    });
  }

  Widget _buildToolPill({
    required String label,
    required IconData icon,
    required Color backgroundColor,
    required Color foregroundColor,
    VoidCallback? onTap,
  }) {
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: foregroundColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: widget.theme.textTheme.labelMedium?.copyWith(
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
      borderRadius: _borderRadius999,
    );
    if (onTap == null) {
      return DecoratedBox(decoration: decoration, child: child);
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: _borderRadius999,
        child: Ink(decoration: decoration, child: child),
      ),
    );
  }

  void _copyCodeBlock() {
    _copiedResetTimer?.cancel();
    setState(() {
      _copied = true;
    });
    final messenger = ScaffoldMessenger.of(context);
    OpenHandSnackBar.hideCurrentOn(messenger);
    _showHomeSnackBarWithMessenger(
      context,
      messenger,
      SnackBar(
        content: Text(
          _localizedText(context, zh: '代码块内容已复制。', en: 'Code copied.'),
        ),
      ),
    );
    _copiedResetTimer = Timer(const Duration(milliseconds: 1600), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _copied = false;
      });
    });
    unawaited(_writeCodeBlockToClipboard());
  }

  Future<void> _writeCodeBlockToClipboard() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.content));
    } catch (_) {
      if (!mounted) {
        return;
      }
      _copiedResetTimer?.cancel();
      setState(() {
        _copied = false;
      });
      final messenger = ScaffoldMessenger.of(context);
      OpenHandSnackBar.hideCurrentOn(messenger);
      _showHomeSnackBarWithMessenger(
        context,
        messenger,
        SnackBar(
          content: Text(
            _localizedText(context, zh: '复制代码块失败。', en: 'Failed to copy code.'),
          ),
        ),
      );
    }
  }

  void _downloadCodeBlock(String? language) {
    _downloadedResetTimer?.cancel();
    unawaited(_performCodeBlockDownload(language));
  }

  Future<void> _performCodeBlockDownload(String? language) async {
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
      await file.writeAsString(widget.content);
      if (!mounted) {
        return;
      }
      setState(() {
        _downloaded = true;
      });
      final messenger = ScaffoldMessenger.of(context);
      OpenHandSnackBar.hideCurrentOn(messenger);
      _showHomeSnackBarWithMessenger(
        context,
        messenger,
        SnackBar(
          content: Text(
            _localizedText(
              context,
              zh: '代码已下载为 ${p.basename(selectedPath)}',
              en: 'Code downloaded as ${p.basename(selectedPath)}',
            ),
          ),
        ),
      );
      _downloadedResetTimer = Timer(const Duration(milliseconds: 1600), () {
        if (!mounted) {
          return;
        }
        setState(() {
          _downloaded = false;
        });
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      OpenHandSnackBar.hideCurrentOn(messenger);
      _showHomeSnackBarWithMessenger(
        context,
        messenger,
        SnackBar(
          content: Text(
            _localizedText(context, zh: '下载失败。', en: 'Download failed.'),
          ),
        ),
      );
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
        bodyBorderColor: darkScheme.outlineVariant.withValues(alpha: 0.34),
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
      bodyBorderColor: colorScheme.outlineVariant.withValues(alpha: 0.38),
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
    required this.bodyBorderColor,
    required this.badgeColor,
    required this.badgeTextColor,
    required this.actionColor,
    required this.actionTextColor,
    required this.shadowColor,
  });

  // Static cache for the expensive ColorScheme.fromSeed dark palette.
  static ColorScheme? _cachedDarkScheme;
  static int? _cachedDarkSchemeTintValue;

  final Color containerColor;
  final Color borderColor;
  final Color headerColor;
  final Color dividerColor;
  final Color bodyColor;
  final Color bodyBorderColor;
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

// ---------------------------------------------------------------------------
// Code editor colour themes
// ---------------------------------------------------------------------------

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
      if (normalizedLanguage != null) {
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
  if (normalized.isEmpty || normalized == 'text' || normalized == 'plaintext') {
    return null;
  }
  return switch (normalized) {
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
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    final titleText = isZh ? 'HTML 预览' : 'HTML Preview';
    final closeText = isZh ? '关闭' : 'Close';
    final openInBrowserText = isZh ? '在浏览器中打开' : 'Open in Browser';
    final cleanupText = isZh ? '清理缓存' : 'Clean Cache';
    final zoomInText = isZh ? '放大' : 'Zoom In';
    final zoomOutText = isZh ? '缩小' : 'Zoom Out';
    final zoomResetText = isZh ? '重置缩放' : 'Reset Zoom';
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
    final animationSettings = context
        .watch<SettingsController>()
        .dialogAnimationSettings;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final sizeDuration = reduceMotion
        ? Duration.zero
        : animationSettings.duration;
    final sizeCurve = reduceMotion
        ? Curves.linear
        : animationSettings.curve.curve;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: AnimatedContainer(
        duration: sizeDuration,
        curve: sizeCurve,
        width: dialogWidth,
        height: dialogHeight,
        decoration: BoxDecoration(
          color: widget.theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
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
                  top: Radius.circular(20),
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
                  const SizedBox(width: 10),
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
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: zoomResetText,
                    onPressed: (_zoom - 1.0).abs() < 0.001 ? null : _resetZoom,
                    icon: const Icon(Icons.restart_alt_rounded, size: 20),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    tooltip: cleanupText,
                    onPressed: _isCleaning ? null : _cleanupTempHtmlFiles,
                    icon: _isCleaning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cleaning_services_rounded, size: 20),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: openInBrowserText,
                    onPressed: () => _openInBrowser(context),
                    icon: const Icon(Icons.open_in_browser_rounded, size: 20),
                  ),
                  const SizedBox(width: 4),
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
                  bottom: Radius.circular(20),
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
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    setState(() {
      _isCleaning = true;
    });
    try {
      final tempDir = Directory.systemTemp;
      int deletedCount = 0;
      await for (final entity in tempDir.list()) {
        if (entity is Directory &&
            p.basename(entity.path).startsWith('openhand_html_')) {
          try {
            await entity.delete(recursive: true);
            deletedCount++;
          } catch (_) {
            // Ignore individual deletion errors.
          }
        }
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _isCleaning = false;
      });
      final messenger = ScaffoldMessenger.of(context);
      OpenHandSnackBar.hideCurrentOn(messenger);
      _showHomeSnackBarWithMessenger(
        context,
        messenger,
        SnackBar(
          content: Text(
            isZh
                ? '已清理 $deletedCount 个临时 HTML 缓存目录。'
                : 'Cleaned $deletedCount temporary HTML cache directories.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isCleaning = false;
      });
      OpenHandSnackBar.hideCurrentOn(ScaffoldMessenger.of(context));
      showFriendlyErrorSnackBar(
        context,
        message: '$e',
        fallback: isZh ? '清理缓存失败' : 'Failed to clean cache',
      );
    }
  }

  Future<void> _openInBrowser(BuildContext context) async {
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    try {
      final tempDir = await Directory.systemTemp.createTemp('openhand_html_');
      final htmlFile = File(p.join(tempDir.path, 'preview.html'));
      await htmlFile.writeAsString(widget.htmlContent);
      final uri = Uri.file(htmlFile.path);
      if (Platform.isMacOS) {
        await runDetachedSystemOpen('open', [uri.toFilePath()]);
      } else if (Platform.isWindows) {
        await runDetachedSystemOpen('cmd', [
          '/c',
          'start',
          '',
          uri.toFilePath(),
        ], runInShell: true);
      } else if (Platform.isLinux) {
        await runDetachedSystemOpen('xdg-open', [uri.toFilePath()]);
      }
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      OpenHandSnackBar.hideCurrentOn(messenger);
      _showHomeSnackBarWithMessenger(
        context,
        messenger,
        SnackBar(
          content: Text(isZh ? '无法在浏览器中打开。' : 'Could not open in browser.'),
        ),
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
      silentLog(
        'home_code_highlighting',
        'html preview setZoom failed',
        error,
        stack,
      );
    }
  }

  void _onZoomMessage(JavaScriptMessage message) {
    final value = double.tryParse(message.message);
    if (value == null || !value.isFinite) return;
    _currentZoom = value;
    widget.onZoomChanged?.call(value);
  }

  void _onMetricsMessage(JavaScriptMessage message) {
    try {
      final decoded = jsonDecode(message.message);
      if (decoded is! Map<String, dynamic>) return;
      final width = (decoded['width'] as num?)?.toDouble();
      final height = (decoded['height'] as num?)?.toDouble();
      if (width == null || height == null) return;
      if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
        return;
      }
      widget.onMetricsChanged?.call(
        _HtmlPreviewMetrics(width: width, height: height),
      );
    } catch (error, stack) {
      silentLog(
        'home_code_highlighting',
        'html preview metrics parse failed',
        error,
        stack,
      );
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
      silentLog(
        'home_code_highlighting',
        'install zoom bridge failed',
        error,
        stack,
      );
    }
  }

  Future<void> _installMetricsBridge([WebViewController? target]) async {
    final controller = target ?? _webViewController;
    if (controller == null) return;
    try {
      await controller.runJavaScript(_metricsBridgeScript);
    } catch (error, stack) {
      silentLog(
        'home_code_highlighting',
        'install preview metrics bridge failed',
        error,
        stack,
      );
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
      // Create temp HTML file as fallback.
      final tempDir = await Directory.systemTemp.createTemp('openhand_html_');
      final htmlFile = File(p.join(tempDir.path, 'preview.html'));
      await htmlFile.writeAsString(widget.htmlContent);
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
      final isZh = Localizations.localeOf(
        context,
      ).languageCode.startsWith('zh');
      setState(() {
        _errorMessage = isZh
            ? 'HTML 预览加载失败 (WebView 初始化或写临时文件出错)。\n原始错误：$e'
            : 'HTML preview failed to load (WebView init or temp file write).\nRaw: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _cleanupTempFile() async {
    if (_tempFilePath != null) {
      try {
        final file = File(_tempFilePath!);
        if (await file.exists()) {
          await file.parent.delete(recursive: true);
        }
      } catch (_) {
        // Ignore cleanup errors.
      }
      _tempFilePath = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');

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
              const SizedBox(height: 16),
              Text(
                isZh ? '加载预览失败' : 'Failed to load preview',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 8),
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
            const SizedBox(height: 16),
            Text(
              isZh ? '正在初始化预览...' : 'Initializing preview...',
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

/// 进程级 mermaid.js 字符串缓存。asset 文件 ~3.3 MB，第一次读完后
/// 后续所有 mermaid 视图共享同一份内存，避免每个 WebView 重复 IO + 解析。
String? _cachedMermaidJs;
Future<String> _loadMermaidJs() async {
  final cached = _cachedMermaidJs;
  if (cached != null) return cached;
  final loaded = await rootBundle.loadString(
    'assets/tooling/mermaid.min.js',
  );
  _cachedMermaidJs = loaded;
  return loaded;
}

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
  // 2026-06-04: 缓存 didChangeDependencies 阶段拿到的 scope，
  // 让 dispose 不再重复查询 ancestor，避免
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
          const SizedBox(width: 6),
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
      borderRadius: _borderRadius999,
    );
    if (onTap == null) {
      return DecoratedBox(decoration: decoration, child: child);
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: _borderRadius999,
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
      return base64Decode(base64Part);
    } catch (_) {
      return null;
    }
  }

  Future<void> _bootstrap() async {
    try {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        // 2026-06-08 临时诊断：把 WebView 内所有 console 输出
        // (log/warn/error) 桥接到 Dart 端 developer.log，让我们能在
        // 不打开 WebView devtools 的情况下拿到 mermaid 加载链路上
        // 每一段精确状态。问题修复后清理。
        ..setOnConsoleMessage((message) {
          developer.log(
            '[js:${message.level.name}] ${message.message}',
            name: 'openhand.mermaid',
          );
        })
        ..addJavaScriptChannel(
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
              final value = double.tryParse(raw.substring(5));
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
      // 关键：mermaid.js 不再内联（WKWebView inline JS 体积上限约 2MB，
      // 3.3MB min.js 会被静默截断成"加载超时"），改为写到与 HTML 同目录
      // 的 mermaid.min.js，HTML 用相对路径 <script src> 引用。
      // macOS / Linux / Windows 用 loadFile 走磁盘；其它平台用
      // loadHtmlString 但同样把 mermaid.js base64 内嵌 data: URL，
      // 保证 file:// / 自定义 scheme 都不影响 JS 加载。
      final mermaidJs = await _loadMermaidJs();
      final html = _buildMermaidHtml();
      if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
        final tempDir = Directory.systemTemp.createTempSync(
          'openhand_mermaid_',
        );
        final tempFile = File(p.join(tempDir.path, 'index.html'));
        final jsFile = File(p.join(tempDir.path, 'mermaid.min.js'));
        // 关键：flush: true 强制把 3.3MB JS 真正 flush 到磁盘，
        // 否则 flush:false 仅在 Dart 层 buffer，WebView 立刻 loadFile
        // 读到的可能是 0 字节空文件，rendered/ready 永远收不到、
        // 60s 看门狗照样报超时。
        await jsFile.writeAsString(mermaidJs, flush: true);
        await tempFile.writeAsString(html, flush: true);
        _tempHtmlPath = tempFile.path;
        final jsSize = await jsFile.length();
        final htmlSize = await tempFile.length();
        // 2026-06-08 临时诊断日志：精确定位 mermaid 加载链路上每一段
        // （asset 读出 / 写盘 / loadFile 触发）是否到位。问题修复后清理。
        developer.log(
          '[mermaid] bootstrap: '
          'html=${tempFile.path} (${htmlSize}B), '
          'js=${jsFile.path} (${jsSize}B, expected ${mermaidJs.length}B), '
          'controller=$controller',
          name: 'openhand.mermaid',
        );
        await controller.loadFile(tempFile.path);
      } else {
        // 移动端：把 mermaid.js 序列化成 data: URL 内联到 <script src>，
        // 避免 webview_flutter 在 loadHtmlString 下使用 file:// 协议的
        // 限制 / Android WebView asset loader 跨域拦截。
        final dataUrl =
            'data:application/javascript;charset=utf-8,${Uri.encodeComponent(mermaidJs)}';
        final needle = '<script src="mermaid.min.js"></script>';
        final replacement = '<script src="$dataUrl"></script>';
        final idx = html.indexOf(needle);
        final htmlWithDataUrl = idx < 0
            ? html
            : html.substring(0, idx) +
                replacement +
                html.substring(idx + needle.length);
        developer.log(
          '[mermaid] bootstrap: dataUrl(${mermaidJs.length}B) inline, '
          'htmlSize=${htmlWithDataUrl.length}B',
          name: 'openhand.mermaid',
        );
        await controller.loadHtmlString(htmlWithDataUrl);
      }
      _controller = controller;
      // 关键：Mermaid 11.x min.js ~3.3MB 解析 + 初始化在慢机器上可能 > 18s，
      // 把看门狗延长到 60s；同时引入 _MermaidLoadPhase 阶段反馈，用户
      // 至少能看到"解析中 / 渲染中"提示而不是直接黑屏 18s。
      _loadWatchdog = Timer(const Duration(seconds: 60), () {
        if (!mounted) return;
        // 只有当 rendered 与 bridge ready 都还没到时，才判为超时。
        // 单一信号到达意味着 WebView 至少部分可用，再写超时会把可用链路标坏。
        if (!_isReady && !_bridgeReady) {
          setState(() {
            _loadError ??= _localizedText(
              context,
              zh: 'Mermaid 加载超时',
              en: 'Mermaid load timed out',
            );
            _isReady = true;
          });
        }
      });
    } catch (error, stack) {
      silentLog(
        'home_code_highlighting',
        'mermaid: setup failed',
        error,
        stack,
      );
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
    // 2026-06-04: dispose 阶段 context 已经 deactivate，
    // 直接 _BubbleHtmlInteractiveScope.maybeOf(context) 会触发
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
          if (await file.exists()) await file.delete();
          final parent = file.parent;
          if (await parent.exists()) await parent.delete(recursive: true);
        } catch (_) {}
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
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              _buildToolPill(
                label: _localizedText(context, zh: '适配', en: 'Fit'),
                icon: Icons.fit_screen_rounded,
                backgroundColor: widget.palette.actionColor,
                foregroundColor: widget.palette.actionTextColor,
                onTap: controlsLocked ? null : _fitToView,
              ),
              const SizedBox(width: 8),
              _buildToolPill(
                label: _localizedText(context, zh: '重置', en: 'Reset'),
                icon: Icons.center_focus_strong_rounded,
                backgroundColor: widget.palette.actionColor,
                foregroundColor: widget.palette.actionTextColor,
                onTap: controlsLocked ? null : _resetView,
              ),
              const SizedBox(width: 8),
              _buildToolPill(
                label: _localizedText(context, zh: '复制 SVG', en: 'Copy SVG'),
                icon: Icons.copy_all_rounded,
                backgroundColor: widget.palette.actionColor,
                foregroundColor: widget.palette.actionTextColor,
                onTap: controlsLocked ? null : () => unawaited(_copySvgMarkup()),
              ),
              const SizedBox(width: 8),
              _buildToolPill(
                label: _localizedText(context, zh: '复制图像', en: 'Copy Image'),
                icon: Icons.image_outlined,
                backgroundColor: widget.palette.actionColor,
                foregroundColor: widget.palette.actionTextColor,
                onTap: controlsLocked ? null : () => unawaited(_copySvgImage()),
              ),
              const SizedBox(width: 8),
              _buildToolPill(
                label: _localizedText(context, zh: '导出 SVG', en: 'Export SVG'),
                icon: Icons.download_rounded,
                backgroundColor: widget.palette.actionColor,
                foregroundColor: widget.palette.actionTextColor,
                onTap: controlsLocked ? null : () => unawaited(_downloadSvg()),
              ),
              const SizedBox(width: 8),
              _buildToolPill(
                label: _localizedText(context, zh: '导出 PNG', en: 'Export PNG'),
                icon: Icons.image_rounded,
                backgroundColor: widget.palette.actionColor,
                foregroundColor: widget.palette.actionTextColor,
                onTap: controlsLocked ? null : () => unawaited(_downloadPng()),
              ),
              const SizedBox(width: 8),
              _buildToolPill(
                label: '${_zoomPercent.toStringAsFixed(0)}%',
                icon: Icons.search_rounded,
                backgroundColor: widget.palette.actionColor.withValues(alpha: 0.72),
                foregroundColor: widget.palette.actionTextColor,
                onTap: controlsLocked ? null : _resetView,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // 画布区域手势完全交给 WebView JS（touch-action: none + pointerdown/move/up），
        // 这里不要再用 Flutter Listener 拦截：macOS 的 WKWebView 是 platform view，
        // 不会把 pointer 事件回灌到 Flutter；iOS / Android 上的 webview_flutter 也是
        // 直接由 platform view 消费事件，Listener 收到的是 platform view 之外的空白处。
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 220, maxHeight: 560),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
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
      silentLog(
        'home_code_highlighting',
        'mermaid command failed',
        error,
        stack,
      );
    } catch (error, stack) {
      silentLog(
        'home_code_highlighting',
        'mermaid command failed',
        error,
        stack,
      );
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
    final messenger = ScaffoldMessenger.of(context);

    if (mounted) {
      OpenHandSnackBar.hideCurrentOn(messenger);
      _showHomeSnackBarWithMessenger(
        context,
        messenger,
        SnackBar(
          content: Text(
            _localizedText(
              context,
              zh: '正在复制 SVG…',
              en: 'Copying SVG…',
            ),
          ),
          duration: const Duration(milliseconds: 700),
        ),
      );
    }

    String svg = _svgMarkup.trim();
    if (svg.isEmpty) {
      final controller = _controller;
      if (controller == null) {
        _showSvgNotReadySnack(messenger);
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
      } catch (_) {
        // ignore: WebView fallback failed; fall through to "not ready" branch.
      }
    }

    if (svg.isEmpty) {
      _showSvgNotReadySnack(messenger);
      return;
    }

    // macOS 上 Flutter 的 Clipboard.setData / Pasteboard.writeText 在部分
    // 用户环境里会"静默"返回成功但剪贴板里没数据；先走 OS 原生 pbcopy，
    // 再回退到 Pasteboard / Clipboard.setData。
    bool writeOk = false;
    String? writeMethod;
    if (Platform.isMacOS) {
      try {
        final proc = await Process.start('pbcopy', const <String>[]);
        proc.stdin.write(utf8.encode(svg));
        await proc.stdin.flush();
        await proc.stdin.close();
        if (await proc.exitCode == 0) {
          writeOk = true;
          writeMethod = 'pbcopy';
        }
      } catch (_) {}
    }
    if (!writeOk) {
      try {
        Pasteboard.writeText(svg);
        writeOk = true;
        writeMethod = 'Pasteboard.writeText';
      } catch (_) {}
    }
    if (!writeOk) {
      try {
        await Clipboard.setData(ClipboardData(text: svg));
        writeOk = true;
        writeMethod = 'Clipboard.setData';
      } catch (_) {}
    }

    // 验证剪贴板（OS 通道 pbpaste 优先，Flutter 通道为辅），用以决定
    // snackbar 文案与是否提供"打开文件"按钮。
    final verification = await _verifySvgClipboard(svg);

    // 始终把 SVG 写到 /tmp 临时文件，给用户一条不依赖剪贴板的可靠路径。
    String? savedPath;
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final tempDir = Directory.systemTemp.createTempSync('openhand_svg_');
      final tempFile = File(p.join(tempDir.path, 'mermaid_$ts.svg'));
      await tempFile.writeAsString(svg);
      savedPath = tempFile.path;
    } catch (_) {}

    if (!mounted) return;
    OpenHandSnackBar.hideCurrentOn(messenger);
    final pathHint = savedPath ?? _localizedText(
      context,
      zh: '临时文件写入失败',
      en: 'temp file write failed',
    );
    if (writeOk && verification.osLayerOk) {
      _showHomeSnackBarWithMessenger(
        context,
        messenger,
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(
            _localizedText(
              context,
              zh: 'SVG 已复制（${svg.length} 字节，方法=$writeMethod）。如粘贴异常，可打开文件: $pathHint',
              en: 'SVG copied (${svg.length}B, method=$writeMethod). If paste fails, file at: $pathHint',
            ),
            maxLines: 4,
          ),
        ),
      );
    } else {
      _showHomeSnackBarWithMessenger(
        context,
        messenger,
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(
            _localizedText(
              context,
              zh: '剪贴板不可信：写 ${svg.length}B, pbpaste 读 ${verification.pbpasteLen}B。SVG 已存到文件: $pathHint，请打开后复制。',
              en: 'Clipboard unreliable: wrote ${svg.length}B, pbpaste read ${verification.pbpasteLen}B. SVG saved to: $pathHint. Open and copy.',
            ),
            maxLines: 4,
          ),
          action: savedPath == null
              ? null
              : SnackBarAction(
                  label: _localizedText(context, zh: '打开', en: 'Open'),
                  onPressed: () {
                    try {
                      Process.start('open', <String>[savedPath!]);
                    } catch (_) {}
                  },
                ),
        ),
      );
    }
  }

  Future<_SvgClipboardVerification> _verifySvgClipboard(String svg) async {
    int pbpasteLen = 0;
    int pbpasteSvgOpenCount = 0;
    int pbpasteSvgCloseCount = 0;
    int flutterLen = 0;
    try {
      final proc = await Process.start('pbpaste', const <String>[]);
      final chunks = <int>[];
      await for (final chunk in proc.stdout) {
        chunks.addAll(chunk);
      }
      await proc.exitCode;
      final bytes = Uint8List.fromList(chunks);
      pbpasteLen = bytes.length;
      if (pbpasteLen > 0) {
        final text = utf8.decode(bytes, allowMalformed: true);
        pbpasteSvgOpenCount = '<svg'.allMatches(text).length;
        pbpasteSvgCloseCount = '</svg>'.allMatches(text).length;
      }
    } catch (_) {}
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      flutterLen = data?.text?.length ?? 0;
    } catch (_) {}
    final osLayerOk = pbpasteLen == svg.length &&
        pbpasteSvgOpenCount == 1 &&
        pbpasteSvgCloseCount == 1;
    return _SvgClipboardVerification(
      pbpasteLen: pbpasteLen,
      flutterLen: flutterLen,
      osLayerOk: osLayerOk,
    );
  }

  void _showSvgNotReadySnack(ScaffoldMessengerState messenger) {
    if (!mounted) return;
    OpenHandSnackBar.hideCurrentOn(messenger);
    _showHomeSnackBarWithMessenger(
      context,
      messenger,
      SnackBar(
        content: Text(
          _localizedText(
            context,
            zh: 'SVG 还未生成，请稍后再试。',
            en: 'SVG is not ready yet. Please try again.',
          ),
        ),
      ),
    );
  }

  Uint8List _svgUtf8Bytes(String svg) => Uint8List.fromList(utf8.encode(svg));

  Future<void> _copySvgImage() async {
    final pngBytes = _decodePngBytes(_pngDataUrl);
    if (pngBytes != null) {
      try {
        await Pasteboard.writeImage(pngBytes);
        if (!mounted) return;
        _showHomeSnackBarWithMessenger(
          context,
          ScaffoldMessenger.of(context),
          SnackBar(
            content: Text(
              _localizedText(context, zh: '已复制图像。', en: 'Image copied.'),
            ),
          ),
        );
        return;
      } catch (_) {}
    }
    final svg = _svgMarkup.trim();
    if (svg.isEmpty) return;
    try {
      await Pasteboard.writeImage(_svgUtf8Bytes(svg));
      if (!mounted) return;
      _showHomeSnackBarWithMessenger(
        context,
        ScaffoldMessenger.of(context),
        SnackBar(
          content: Text(
            _localizedText(
              context,
              zh: 'PNG 复制失败，已回退复制 SVG 图像。',
              en: 'PNG copy failed; copied SVG image instead.',
            ),
          ),
        ),
      );
    } catch (_) {
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
            mimeTypes: <String>['image/svg+xml'],
            extensions: <String>['svg'],
          ),
        ],
      );
      final path = location?.path;
      if (!mounted || path == null || path.isEmpty) return;
      await File(path).writeAsString(svg, flush: true);
      if (!mounted) return;
      _showHomeSnackBarWithMessenger(
        context,
        ScaffoldMessenger.of(context),
        SnackBar(
          content: Text(
            _localizedText(context, zh: 'SVG 已导出。', en: 'SVG exported.'),
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> _downloadPng() async {
    final pngBytes = _decodePngBytes(_pngDataUrl);
    if (pngBytes == null) {
      if (!mounted) return;
      _showHomeSnackBarWithMessenger(
        context,
        ScaffoldMessenger.of(context),
        SnackBar(
          content: Text(
            _localizedText(
              context,
              zh: 'PNG 仍未就绪，请稍后重试。',
              en: 'PNG is not ready yet. Please try again.',
            ),
          ),
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
            mimeTypes: <String>['image/png'],
            extensions: <String>['png'],
          ),
        ],
      );
      final path = location?.path;
      if (!mounted || path == null || path.isEmpty) return;
      await File(path).writeAsBytes(pngBytes, flush: true);
      if (!mounted) return;
      _showHomeSnackBarWithMessenger(
        context,
        ScaffoldMessenger.of(context),
        SnackBar(
          content: Text(
            _localizedText(context, zh: 'PNG 已导出。', en: 'PNG exported.'),
          ),
        ),
      );
    } catch (_) {}
  }

  String _buildMermaidHtml() {
    final rawSource = widget.source;
    final escaped = const HtmlEscape(HtmlEscapeMode.element).convert(rawSource);
    final isDark = widget.palette.headerColor.computeLuminance() < 0.4;
    // 关键：与代码块容器使用同一调色板，让 WebView body / mermaid 节点 /
    // 边线全部沿用同套主题色，杜绝硬编码 0xFF0F1115 与全局深色主题割裂。
    final palette = widget.palette;
    String argbToCss(Color c) =>
        c.toARGB32().toRadixString(16).padLeft(8, '0');
    String argbToRgbHex(Color c) {
      final hex = argbToCss(c);
      return hex.length == 8 ? hex.substring(2) : hex;
    }

    final bgHex = argbToCss(palette.containerColor);
    final fgHex = argbToCss(palette.actionTextColor);
    final bgRgb = argbToRgbHex(palette.containerColor);
    final fgRgb = argbToRgbHex(palette.actionTextColor);
    final borderRgb = argbToRgbHex(palette.borderColor);
    // 关键：mermaid.js 不内联，改用 <script src="mermaid.min.js"> 让
    // WebView 走 file:// 协议异步加载。规避 WKWebView inline JS ~2MB 体积
    // 上限（3.3MB min.js 会被静默截断）导致的"加载超时"。
    // 调用方在 loadFile 之前已经把 mermaid.min.js 写到与 HTML 同目录，
    // 相对路径自动 resolve。
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
  .mermaid-stage svg .root > * { background: transparent !important; }
  .mermaid-stage svg > rect,
  .mermaid-stage svg .background,
  .mermaid-stage svg rect.background { fill: transparent !important; }
  .mermaid-stage svg { --background: transparent !important; }
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
    // 关键：mermaid.js 走 file:// 相对路径加载，由调用方在
    // loadFile 之前把 mermaid.min.js 写到与 index.html 同目录。
    // 避开 WKWebView inline JS 体积限制，根治"加载超时"。
  </script>
  <script>
    // 关键：mermaid.js 走 file:// 相对路径加载，由调用方在
    // loadFile 之前把 mermaid.min.js 写到与 index.html 同目录。
    // 避开 WKWebView inline JS 体积限制，根治"加载超时"。
  </script>
  <script src="mermaid.min.js"
    onload="console.log('[openhand-mermaid] script.onload fired, mermaid typeof =', typeof window.mermaid, 'keys =', window.mermaid ? Object.keys(window.mermaid).slice(0,8) : null)"
    onerror="console.error('[openhand-mermaid] script.onerror fired, src =', this.src, 'readyState =', this.readyState)"></script>
  <script>
    // 2026-06-08 临时诊断日志：mermaid 解析+初始化+渲染每一段
    // 节点都打点，宿主 developer.log 通过 webview console 桥接拿到。
    // 问题修复后清理。
    (function () {
      var post = function (value) {
        if (window.OpenHandMermaid && window.OpenHandMermaid.postMessage) {
          window.OpenHandMermaid.postMessage(value);
        }
      };
      console.log('[openhand-mermaid] script body entered, t0 =', Date.now());
      var formatError = function (err) {
        if (err && typeof err === 'object') {
          if (typeof err.str === 'string' && err.str.trim()) return err.str.trim();
          if (typeof err.message === 'string' && err.message.trim()) return err.message.trim();
          if (typeof err.hash === 'string' && err.hash.trim()) return err.hash.trim();
          try {
            var json = JSON.stringify(err, null, 2);
            if (json && json !== '{}') return json;
          } catch (_) {}
        }
        return String(err);
      };
      var svgMarkupOf = function (value) {
        if (typeof value === 'string') return value;
        if (value && value.tagName && String(value.tagName).toLowerCase() === 'svg') {
          return value.outerHTML || '';
        }
        return '';
      };
      if (!window.mermaid) {
        post('error:mermaid-js 加载失败,请检查网络');
        post('ready');
        return;
      }
      try {
        window.mermaid.initialize({
          startOnLoad: false,
          theme: 'base',
          securityLevel: 'loose',
          flowchart: { useMaxWidth: false, htmlLabels: true, curve: 'basis' },
          sequence: { useMaxWidth: false, showSequenceNumbers: true },
          gantt: { useMaxWidth: false },
          // 关键：使用 base 主题 + 同 palette 颜色，杜绝 mermaid dark 主题
          // 自身 #1f2020 节点色与全局调色板割裂的问题。
          themeVariables: {
            fontSize: '13px',
            background: '#$bgRgb',
            primaryColor: '#$bgRgb',
            primaryBorderColor: '#$borderRgb',
            primaryTextColor: '#$fgRgb',
            secondaryColor: '#$bgRgb',
            tertiaryColor: '#$bgRgb',
            lineColor: '#$fgRgb',
          },
        });
      } catch (err) {
        post('error:init_failed:' + formatError(err));
        post('ready');
        return;
      }
      var sourceEl = document.getElementById('mermaid-source');
      var source = (sourceEl && sourceEl.textContent) || '';
      console.log('[openhand-mermaid] initialize done, source length =', source.length, 't1 =', Date.now());
      Promise.resolve()
        .then(function () {
          console.log('[openhand-mermaid] render start, t2 =', Date.now());
          return window.mermaid.render('mermaid-svg', source);
        })
        .then(function (result) {
          console.log('[openhand-mermaid] render resolved, t3 =', Date.now(), 'hasSvg =', !!(result && (result.svg || typeof result === 'string')));
          var svg = svgMarkupOf(result) || svgMarkupOf(result && result.svg);
          if (!svg || svg.indexOf('<svg') === -1) {
            throw new Error(formatError(result));
          }
          // 关键：Mermaid 10.9.1 输出的 SVG 自带 <rect class="background">
          // 节点填满整张画布（fill 走 var(--background) 或硬编码深色），
          // 视觉上让 body #$bgHex 透不出来。在 innerHTML 注入前先把
          // background rect 摘掉、inline style 抹掉，确保 body 容器色
          // 完全穿透 SVG 呈现。CSS 选择器兜底（见 <style>）覆盖未命中场景。
          svg = svg
            // 关键：Dart 字符串里 \\b 才在 JS 解析为正则单词边界（\b 在
            // Dart 是退格符，会把整条 regex 吃成乱码）。
            .replace(/<rect[^>]*\\bclass=["'][^"']*\\bbackground\\b[^"']*["'][^>]*\/?>(?:<\/rect>)?/gi, '')
            .replace(/<rect[^>]*class=["'][^"']*background[^"']*["'][^>]*\/?>(?:<\/rect>)?/gi, '')
            .replace(/\sstyle=["'][^"']*background[^"']*["']/gi, '')
            .replace(/--background\s*:\s*[^;!}]+/gi, '--background: transparent');
          var inner = document.getElementById('inner');
          if (inner) {
            inner.innerHTML = svg;
            // 二次兜底：DOM 注入后再 sweep 一次，处理 mermaid 偶尔漏掉
            // 的 inline style / class 命名变体。
            try {
              var svgEl = inner.querySelector('svg');
              if (svgEl) {
                svgEl.removeAttribute('style');
                var bgRects = svgEl.querySelectorAll(
                  'rect.background, rect[class*="background"]'
                );
                for (var ri = 0; ri < bgRects.length; ri++) {
                  var r = bgRects[ri];
                  r.parentNode && r.parentNode.removeChild(r);
                }
                var styleBlocks = svgEl.querySelectorAll('style');
                for (var si = 0; si < styleBlocks.length; si++) {
                  styleBlocks[si].textContent = (styleBlocks[si].textContent || '')
                    .replace(/--background\s*:\s*[^;!}]+/g, '--background: transparent');
                }
              }
            } catch (_) { /* 抹除失败不影响主路径 */ }
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
        })
        .catch(function (err) {
          var inner = document.getElementById('inner');
          if (inner) {
            inner.innerHTML = '<div class="mermaid-error">' + formatError(err) + '</div>';
          }
          post('error:render_failed:' + formatError(err));
        })
        .then(function () {
          // 无论成功或失败，都发 ready，保证 bridge 一定 ready。
          post('ready');
        });
    })();
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
