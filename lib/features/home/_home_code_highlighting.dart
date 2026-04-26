part of 'openhand_home_page.dart';

/// Maximum code-block length (in characters) at which we still attempt
/// syntax highlighting. Beyond this we render plain monospace text to keep
/// transcript open / scroll responsive (very long log dumps were the
/// dominant source of multi-second jank when opening a session).
const int _highlightSkipThresholdChars = 80 * 1024;

/// Code-block length above which we defer the first highlight pass to a
/// microtask, painting plain text on the first frame. Tuned so that small
/// snippets (the common case) still highlight synchronously and feel
/// instant while heavier blocks no longer block the initial layout.
const int _highlightDeferThresholdChars = 4 * 1024;

/// Process-wide LRU cache for parsed code-block `TextSpan`s. The same code
/// snippet (e.g. a tool result, a generated diff) frequently appears in
/// many bubbles across a session; reusing the cached span avoids
/// re-tokenising on every rebuild and on cross-session navigation.
final _HighlightSpanCache _highlightSpanCache = _HighlightSpanCache(
  maxEntries: 256,
);

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
  Timer? _copiedResetTimer;
  Timer? _downloadedResetTimer;
  _CodeBlockPalette? _cachedPalette;
  int? _cachedPaletteSignature;
  bool _highlightScheduled = false;

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
    // Use ClipRRect for corner clipping to avoid ghosting artifacts
    // from overlapping border + background rendering at rounded corners.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: _borderRadius18,
        boxShadow: [
          BoxShadow(
            color: palette.shadowColor,
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: _borderRadius18,
        child: Container(
          decoration: BoxDecoration(
            color: palette.containerColor,
            borderRadius: _borderRadius18,
            border: Border.all(color: palette.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.headerColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(17),
                    topRight: Radius.circular(17),
                  ),
                  border: Border(
                    bottom: BorderSide(color: palette.dividerColor),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(
                    children: [
                      if (effectiveLanguage != null)
                        _buildHeaderPill(
                          label: effectiveLanguage,
                          icon: Icons.code_rounded,
                          backgroundColor: palette.badgeColor,
                          foregroundColor: palette.badgeTextColor,
                        )
                      else
                        const SizedBox(height: 32),
                      const Spacer(),
                      _buildHeaderPill(
                        label: copyLabel,
                        icon: _copied
                            ? Icons.check_rounded
                            : Icons.content_copy_rounded,
                        backgroundColor: palette.actionColor,
                        foregroundColor: palette.actionTextColor,
                        onTap: _copyCodeBlock,
                      ),
                      const SizedBox(width: 8),
                      _buildHeaderPill(
                        label: downloadLabel,
                        icon: _downloaded
                            ? Icons.check_rounded
                            : Icons.download_rounded,
                        backgroundColor: palette.actionColor,
                        foregroundColor: palette.actionTextColor,
                        onTap: () => _downloadCodeBlock(effectiveLanguage),
                      ),
                      if (isHtmlLanguage) ...[
                        const SizedBox(width: 8),
                        _buildHeaderPill(
                          label: runLabel,
                          icon: Icons.play_arrow_rounded,
                          backgroundColor: palette.actionColor,
                          foregroundColor: palette.actionTextColor,
                          onTap: _runHtmlPreview,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.bodyColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: palette.bodyBorderColor),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: widget.wrapLines
                        ? (widget.selectable
                              ? SelectableText.rich(
                                  _highlightedSpan ?? const TextSpan(),
                                )
                              : RichText(
                                  text: _highlightedSpan ?? const TextSpan(),
                                ))
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: widget.selectable
                                ? SelectableText.rich(
                                    _highlightedSpan ?? const TextSpan(),
                                  )
                                : RichText(
                                    text: _highlightedSpan ?? const TextSpan(),
                                  ),
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

  void _ensureHighlightedSpan() {
    final effectiveLanguage = _normalizeCodeLanguage(widget.language);
    final useDarkPalette =
        widget.forceDarkSurface || widget.theme.brightness == Brightness.dark;
    final signature = Object.hashAll(<Object?>[
      widget.content,
      effectiveLanguage,
      widget.allowAutoDetection,
      widget.baseColor.toARGB32(),
      useDarkPalette,
      widget.theme.textTheme.bodyMedium?.fontSize,
      widget.theme.textTheme.bodyMedium?.fontFamily,
      widget.theme.textTheme.bodyMedium?.height,
    ]);
    if (_highlightedSpan != null && _highlightSignature == signature) {
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
      return;
    }
    // For medium-sized blocks, defer the highlight work to the next
    // microtask so the first frame can paint a plain-text placeholder,
    // avoiding a multi-message transcript from blocking on a single
    // expensive parse during the initial layout pass.
    if (widget.content.length > _highlightDeferThresholdChars &&
        _highlightedSpan == null) {
      if (!_highlightScheduled) {
        _highlightScheduled = true;
        _highlightedSpan = TextSpan(
          text: widget.content,
          style: _baseStyleForCurrentTheme(useDarkPalette),
        );
        _highlightSignature = signature;
        scheduleMicrotask(() {
          if (!mounted) return;
          _highlightScheduled = false;
          // Re-check the signature in case the widget was updated while
          // the microtask was queued.
          if (_highlightSignature != signature) return;
          final span = _runHighlight(
            effectiveLanguage,
            useDarkPalette,
            signature,
          );
          if (!mounted) return;
          setState(() {
            _highlightedSpan = span;
          });
        });
        return;
      }
    }
    _highlightedSpan = _runHighlight(
      effectiveLanguage,
      useDarkPalette,
      signature,
    );
    _highlightSignature = signature;
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
  }

  Widget _buildHeaderPill({
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
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
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
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              _localizedText(
                context,
                zh: '复制代码块失败。',
                en: 'Failed to copy code.',
              ),
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
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
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
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
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

  @override
  Widget build(BuildContext context) {
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    final titleText = isZh ? 'HTML 预览' : 'HTML Preview';
    final closeText = isZh ? '关闭' : 'Close';
    final openInBrowserText = isZh ? '在浏览器中打开' : 'Open in Browser';
    final cleanupText = isZh ? '清理缓存' : 'Clean Cache';

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: math.min(MediaQuery.sizeOf(context).width * 0.85, 1200.0),
        height: math.min(MediaQuery.sizeOf(context).height * 0.85, 900.0),
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                  TextButton.icon(
                    onPressed: _isCleaning ? null : _cleanupTempHtmlFiles,
                    icon: _isCleaning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cleaning_services_rounded, size: 18),
                    label: Text(cleanupText),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _openInBrowser(context),
                    icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                    label: Text(openInBrowserText),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: Text(closeText),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(20),
                ),
                child: _HtmlWebViewPreview(htmlContent: widget.htmlContent),
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
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
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
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(isZh ? '清理缓存失败: $e' : 'Failed to clean cache: $e'),
          ),
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
        await Process.run('open', [uri.toFilePath()]);
      } else if (Platform.isWindows) {
        await Process.run('start', ['', uri.toFilePath()], runInShell: true);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [uri.toFilePath()]);
      }
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(isZh ? '无法在浏览器中打开。' : 'Could not open in browser.'),
          ),
        );
    }
  }
}

class _HtmlWebViewPreview extends StatefulWidget {
  const _HtmlWebViewPreview({required this.htmlContent});

  final String htmlContent;

  @override
  State<_HtmlWebViewPreview> createState() => _HtmlWebViewPreviewState();
}

class _HtmlWebViewPreviewState extends State<_HtmlWebViewPreview> {
  WebViewController? _webViewController;
  String? _tempFilePath;
  bool _isLoading = true;
  String? _errorMessage;
  double _loadingProgress = 0;

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
        _errorMessage = e.toString();
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
