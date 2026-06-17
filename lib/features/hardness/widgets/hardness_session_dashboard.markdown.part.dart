part of 'hardness_session_dashboard.dart';

class _HeSafeMarkdownBody extends StatefulWidget {
  const _HeSafeMarkdownBody({
    required this.content,
    required this.theme,
    required this.colorScheme,
    this.filePathRoots = const [],
    this.textColor,
    this.cardBackground,
  });

  final String content;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final List<String> filePathRoots;
  final Color? textColor;

  /// When non-null, overrides the markdown colour palette so that text,
  /// code blocks, blockquotes, etc. are legible on this background colour
  /// (e.g. the always-dark thinking card).
  final Color? cardBackground;

  @override
  State<_HeSafeMarkdownBody> createState() => _HeSafeMarkdownBodyState();
}

class _HeSafeMarkdownBodyState extends State<_HeSafeMarkdownBody>
    implements MarkdownBuilderDelegate {
  List<Widget>? _children;
  String? _lastSanitised;
  String? _lastRawContent;
  int? _lastThemeHash;
  final List<GestureRecognizer> _recognizers = <GestureRecognizer>[];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rebuildIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _HeSafeMarkdownBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    _rebuildIfNeeded();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _rebuildIfNeeded() {
    final themeHash = Object.hashAll(<Object?>[
      widget.theme.brightness,
      widget.colorScheme.surface.toARGB32(),
      widget.colorScheme.primary.toARGB32(),
      widget.textColor?.toARGB32(),
      widget.cardBackground?.toARGB32(),
      widget.filePathRoots.join('\u0000'),
    ]);
    // Fast-path: if the raw content and relevant theme inputs are unchanged
    // we can skip even the sanitization work.
    if (_children != null &&
        _lastRawContent == widget.content &&
        _lastThemeHash == themeHash) {
      return;
    }
    final sanitised = _heSanitizeMarkdownSource(widget.content);

    if (sanitised == _lastSanitised && themeHash == _lastThemeHash) {
      _lastRawContent = widget.content;
      return;
    }

    _lastRawContent = widget.content;
    _lastSanitised = sanitised;
    _lastThemeHash = themeHash;
    if (sanitised.isEmpty) {
      _children = const <Widget>[];
      return;
    }

    _disposeRecognizers();
    _parseMarkdown(sanitised);
  }

  void _parseMarkdown(String source) {
    final MarkdownStyleSheet effectiveStyleSheet;
    final bg = widget.cardBackground;
    final darkSurface =
        bg != null &&
        ThemeData.estimateBrightnessForColor(bg) == Brightness.dark;
    if (bg != null) {
      effectiveStyleSheet = MarkdownStyleSheet.fromTheme(widget.theme).merge(
        _heBuildDarkAwareMarkdownStyleSheet(
          widget.theme,
          widget.colorScheme,
          bg,
          widget.textColor,
        ),
      );
    } else {
      effectiveStyleSheet = MarkdownStyleSheet.fromTheme(
        widget.theme,
      ).merge(_heBuildMarkdownStyleSheet(widget.theme, widget.colorScheme));
    }

    final inlineSyntaxes = widget.filePathRoots.isNotEmpty
        ? <md.InlineSyntax>[
            MessagePathCodeSyntax(candidateRoots: widget.filePathRoots),
            MessageFilePathSyntax(candidateRoots: widget.filePathRoots),
          ]
        : const <md.InlineSyntax>[];

    final builders = <String, MarkdownElementBuilder>{
      'pre': _HeDiffBuilder(
        colorScheme: widget.colorScheme,
        darkSurface: darkSurface,
      ),
      if (widget.filePathRoots.isNotEmpty) ...{
        'openhand-file-resolved': _HeFilePathBuilder(
          textColor: widget.textColor ?? widget.colorScheme.onSurface,
        ),
        'openhand-file-pending': _HeFilePathBuilder(
          textColor: widget.textColor ?? widget.colorScheme.onSurface,
        ),
      },
    };
    final effectiveInlineSyntaxes = withOpenHandMarkdownMathInlineSyntaxes(
      inlineSyntaxes,
    );
    final effectiveBuilders = withOpenHandMarkdownMathBuilders(
      builders,
      fallbackTextStyle: effectiveStyleSheet.p,
      textColor:
          widget.textColor ??
          effectiveStyleSheet.p?.color ??
          widget.colorScheme.onSurface,
    );

    try {
      final document = md.Document(
        extensionSet: md.ExtensionSet.gitHubFlavored,
        blockSyntaxes: openHandMarkdownMathBlockSyntaxes,
        inlineSyntaxes: effectiveInlineSyntaxes,
        encodeHtml: false,
      );
      final astNodes = document.parseLines(
        const LineSplitter().convert(source),
      );
      _heSanitizeMarkdownAst(astNodes);
      final builder = MarkdownBuilder(
        delegate: this,
        selectable: true,
        styleSheet: effectiveStyleSheet,
        imageDirectory: null,
        imageBuilder: null,
        checkboxBuilder: null,
        bulletBuilder: null,
        builders: effectiveBuilders,
        paddingBuilders: const <String, MarkdownPaddingBuilder>{},
        listItemCrossAxisAlignment: MarkdownListItemCrossAxisAlignment.baseline,
      );
      _children = builder.build(astNodes);
    } catch (_) {
      final fallbackStyle = TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        color: widget.textColor ?? widget.colorScheme.onSurface,
      );
      _children = <Widget>[SelectableText(source, style: fallbackStyle)];
    }
  }

  void _disposeRecognizers() {
    if (_recognizers.isEmpty) {
      return;
    }
    final local = List<GestureRecognizer>.from(_recognizers);
    _recognizers.clear();
    for (final recognizer in local) {
      recognizer.dispose();
    }
  }

  @override
  GestureRecognizer createLink(String text, String? href, String title) {
    final recognizer = TapGestureRecognizer();
    _recognizers.add(recognizer);
    final resolvedPath = resolveMarkdownMessageLinkPath(
      href,
      widget.filePathRoots,
    );
    if (resolvedPath != null) {
      recognizer.onTap = () {
        Clipboard.setData(ClipboardData(text: resolvedPath.resolvedPath));
        if (mounted) {
          _showHardnessSnackBar(
            context,
            SnackBar(
              content: Text('Path copied: ${resolvedPath.resolvedPath}'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      };
    }
    return recognizer;
  }

  @override
  TextSpan formatText(MarkdownStyleSheet styleSheet, String code) {
    final normalizedCode = code.replaceAll(RegExp(r'\n$'), '');
    final resolvedPath = resolveExistingMessagePath(
      normalizedCode,
      widget.filePathRoots,
    );
    if (resolvedPath == null) {
      return TextSpan(text: normalizedCode, style: styleSheet.code);
    }
    final recognizer = TapGestureRecognizer()
      ..onTap = () {
        Clipboard.setData(ClipboardData(text: resolvedPath.resolvedPath));
        if (mounted) {
          _showHardnessSnackBar(
            context,
            SnackBar(
              content: Text('Path copied: ${resolvedPath.resolvedPath}'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      };
    _recognizers.add(recognizer);
    final linkColor = widget.colorScheme.primary;
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _HeMarkdownContent extends StatefulWidget {
  const _HeMarkdownContent({
    required this.content,
    required this.isZh,
    required this.theme,
    required this.colorScheme,
    this.filePathRoots = const [],
  });

  final String content;
  final bool isZh;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final List<String> filePathRoots;

  // When the rendered content looks long, start collapsed.
  static const int _collapseCharThreshold = 1800;
  static const int _previewChars = 1200;

  @override
  State<_HeMarkdownContent> createState() => _HeMarkdownContentState();
}

class _HeMarkdownContentState extends State<_HeMarkdownContent>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  bool get _needsCollapse =>
      widget.content.length > _HeMarkdownContent._collapseCharThreshold;

  String get _displayContent {
    if (!_needsCollapse || _expanded) return widget.content;
    // Find the last word boundary before the char limit.
    final cut = widget.content.lastIndexOf(
      RegExp(r'\s'),
      _HeMarkdownContent._previewChars,
    );
    final end = cut > 0 ? cut : _HeMarkdownContent._previewChars;
    return '${widget.content.substring(0, end)}…';
  }

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..value = 1.0;
    // 入场使用 easeOutCubic：开始快、收尾舒缓，符合全局丝滑节奏；
    // 与 easeIn（开始慢）相比能更早把首帧像素呈现给用户。
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _expand() {
    _fadeCtrl.value = 0;
    setState(() => _expanded = true);
    _fadeCtrl.forward();
  }

  @override
  Widget build(BuildContext context) {
    final isZh = widget.isZh;
    final colorScheme = widget.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FadeTransition(
          opacity: _fadeAnim,
          child: _HeSafeMarkdownBody(
            content: _displayContent,
            theme: widget.theme,
            colorScheme: colorScheme,
            filePathRoots: widget.filePathRoots,
          ),
        ),
        if (_needsCollapse && !_expanded) ...[
          const SizedBox(height: 6),
          // Fading gradient overlay + expand button
          ClipRect(
            child: Column(
              children: [
                Container(
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        colorScheme.surface.withValues(alpha: 0),
                        colorScheme.surface.withValues(alpha: 0.80),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: _expand,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: _br16,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.expand_more_rounded,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isZh ? '展开全部内容' : 'Show full content',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// =============================================================================
// _HeSmallPill — compact action chip used in the log section header
// =============================================================================

class _HeSmallPill extends StatelessWidget {
  const _HeSmallPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: _br999,
      child: InkWell(
        onTap: onTap,
        borderRadius: _br999,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: colorScheme.primary),
              const SizedBox(width: 5),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Log line — renders one CLI output line with level-based colouring
// Used only in the raw view.
// =============================================================================

class _LogLine extends StatelessWidget {
  const _LogLine({required this.line, required this.colorScheme});

  final String line;
  final ColorScheme colorScheme;

  Color? _resolveColor() {
    if (line.startsWith('\u2713')) return const Color(0xFF4CAF50);
    if (line.startsWith('\u2717')) return colorScheme.error;
    if (line.startsWith('>')) return colorScheme.primary;
    if (line.startsWith('\u25b6')) return colorScheme.secondary;
    if (line.startsWith('\u26a0')) return colorScheme.tertiary;
    final match = _logLevelPattern.firstMatch(line);
    if (match != null) {
      final level = match.group(0)!.toUpperCase();
      switch (level) {
        case 'ERROR':
        case 'ERR':
          return colorScheme.error;
        case 'WARN':
        case 'WARNING':
          return OpenHandStatusColors.warning;
        case 'INFO':
          return colorScheme.primary;
        case 'DEBUG':
          return colorScheme.onSurfaceVariant.withValues(alpha: 0.65);
        case 'TRACE':
          return colorScheme.onSurfaceVariant.withValues(alpha: 0.45);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    FontWeight? weight;
    final color = _resolveColor();
    if (line.startsWith('\u2713') ||
        line.startsWith('\u2717') ||
        line.startsWith('\u25b6')) {
      weight = FontWeight.w600;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: SelectableText(
        line.isEmpty ? '\u200B' : line,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12.5,
          height: 1.55,
          color: color ?? colorScheme.onSurface.withValues(alpha: 0.87),
          fontWeight: weight,
        ),
      ),
    );
  }
}

// =============================================================================
// _HeDiffBuilder — MarkdownElementBuilder that intercepts fenced code blocks
// whose language tag is "diff" or "patch" and renders them with a dedicated
// side-by-side / unified diff widget instead of a plain code block.
// =============================================================================

class _HeDiffBuilder extends MarkdownElementBuilder {
  _HeDiffBuilder({required this.colorScheme, this.darkSurface = false});

  final ColorScheme colorScheme;
  final bool darkSurface;

  static final _diffLangRe = RegExp(
    r'\blanguage-(diff|patch|udiff)\b',
    caseSensitive: false,
  );

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    // We intercept <pre> elements.  The child <code> carries the language class
    // and the text content.
    if (element.tag != 'pre') return null;

    final codeEl = element.children
        ?.whereType<md.Element>()
        .where((e) => e.tag == 'code')
        .firstOrNull;

    if (codeEl == null) return null;

    final cls = codeEl.attributes['class'] ?? '';

    // Collect plain text from all descendant text nodes.
    final buf = StringBuffer();
    void collect(md.Node node) {
      if (node is md.Text) {
        buf.write(node.text);
      } else if (node is md.Element) {
        node.children?.forEach(collect);
      }
    }

    codeEl.children?.forEach(collect);

    final rawText = buf.toString();
    if (rawText.isEmpty) return null;

    // Diff language → specialized diff block
    if (_diffLangRe.hasMatch(cls)) {
      return _HeDiffBlock(
        rawDiff: rawText,
        colorScheme: colorScheme,
        darkSurface: darkSurface,
      );
    }

    // All other code blocks → highlighted code panel with copy/language header
    final language = _heExtractCodeLanguage(cls);
    return RepaintBoundary(
      child: _HeHighlightedCodePanel(
        content: rawText.replaceFirst(RegExp(r'\n$'), ''),
        language: language,
        colorScheme: colorScheme,
        darkSurface: darkSurface,
      ),
    );
  }
}

String? _heExtractCodeLanguage(String classes) {
  if (classes.isEmpty) return null;
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

String? _heNormalizeCodeLanguage(String? language) {
  final normalized = (language ?? '').trim().toLowerCase();
  if (normalized.isEmpty || normalized == 'text' || normalized == 'plaintext') {
    return null;
  }
  return normalized;
}

/// Highlighted code panel for the Hardness (WEB) session — provides language
/// label, copy button, and syntax highlighting consistent with the APP side.
class _HeHighlightedCodePanel extends StatefulWidget {
  const _HeHighlightedCodePanel({
    required this.content,
    required this.colorScheme,
    this.language,
    this.darkSurface = false,
  });

  final String content;
  final ColorScheme colorScheme;
  final String? language;
  final bool darkSurface;

  @override
  State<_HeHighlightedCodePanel> createState() =>
      _HeHighlightedCodePanelState();
}

class _HeHighlightedCodePanelState extends State<_HeHighlightedCodePanel> {
  TextSpan? _highlightedSpan;
  bool _copied = false;
  Timer? _copiedResetTimer;

  @override
  void initState() {
    super.initState();
    _buildHighlightedSpan();
  }

  @override
  void didUpdateWidget(covariant _HeHighlightedCodePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content ||
        oldWidget.language != widget.language ||
        oldWidget.darkSurface != widget.darkSurface) {
      _highlightedSpan = null;
      _buildHighlightedSpan();
    }
  }

  @override
  void dispose() {
    _copiedResetTimer?.cancel();
    super.dispose();
  }

  void _buildHighlightedSpan() {
    final effectiveLanguage = _heNormalizeCodeLanguage(widget.language);
    final isDark = widget.darkSurface;
    final baseStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 13,
      height: 1.5,
      color: isDark
          ? Colors.white.withValues(alpha: 0.92)
          : widget.colorScheme.onSurface,
    );

    // Skip highlighting for very large blocks
    if (widget.content.length > 80 * 1024) {
      _highlightedSpan = TextSpan(text: widget.content, style: baseStyle);
      return;
    }

    try {
      final parsed = highlight.highlight.parse(
        widget.content,
        language: effectiveLanguage,
        autoDetection: effectiveLanguage == null,
      );
      _highlightedSpan = TextSpan(
        style: baseStyle,
        children: _buildNodes(parsed.nodes, baseStyle, isDark),
      );
    } catch (_) {
      _highlightedSpan = TextSpan(text: widget.content, style: baseStyle);
    }
  }

  List<InlineSpan> _buildNodes(
    List<highlight.Node>? nodes,
    TextStyle baseStyle,
    bool isDark,
  ) {
    if (nodes == null || nodes.isEmpty) return [TextSpan(style: baseStyle)];
    final spans = <InlineSpan>[];
    for (final node in nodes) {
      if (node.value != null) {
        spans.add(
          TextSpan(
            text: node.value,
            style: node.className == null
                ? null
                : _heStyleForClass(node.className, baseStyle, isDark),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            style: node.className == null
                ? null
                : _heStyleForClass(node.className, baseStyle, isDark),
            children: _buildNodes(node.children, baseStyle, isDark),
          ),
        );
      }
    }
    return spans;
  }

  TextStyle _heStyleForClass(String? className, TextStyle base, bool isDark) {
    final classes = (className ?? '').split(' ');
    for (final cls in classes) {
      if (const {'comment', 'quote'}.contains(cls)) {
        return base.copyWith(
          color: isDark ? const Color(0xFF7DD3A7) : const Color(0xFF5B6472),
          fontStyle: FontStyle.italic,
        );
      }
      if (const {
        'keyword',
        'selector-tag',
        'meta-keyword',
        'doctag',
      }.contains(cls)) {
        return base.copyWith(
          color: isDark ? const Color(0xFFF9A8D4) : const Color(0xFF0B57D0),
          fontWeight: FontWeight.w700,
        );
      }
      if (const {
        'string',
        'regexp',
        'attribute',
        'template-variable',
      }.contains(cls)) {
        return base.copyWith(
          color: isDark ? const Color(0xFFFDE68A) : const Color(0xFFB42318),
        );
      }
      if (const {'number', 'literal', 'symbol', 'bullet'}.contains(cls)) {
        return base.copyWith(
          color: isDark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8),
        );
      }
      if (const {
        'title',
        'function',
        'section',
        'title.function_',
        'title.class_',
      }.contains(cls)) {
        return base.copyWith(
          color: isDark ? const Color(0xFF67E8F9) : const Color(0xFF7C3AED),
          fontWeight: FontWeight.w700,
        );
      }
      if (const {
        'type',
        'built_in',
        'class',
        'params',
        'variable',
        'selector-id',
        'selector-class',
        'property',
      }.contains(cls)) {
        return base.copyWith(
          color: isDark ? const Color(0xFFC4B5FD) : const Color(0xFF8A3C00),
          fontWeight: FontWeight.w600,
        );
      }
      if (const {'meta', 'attr', 'tag', 'name'}.contains(cls)) {
        return base.copyWith(
          color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF0F4C81),
        );
      }
      if (const {'operator', 'punctuation'}.contains(cls)) {
        return base.copyWith(
          color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1F2937),
        );
      }
    }
    return base;
  }

  void _copyCode() {
    _copiedResetTimer?.cancel();
    setState(() => _copied = true);
    Clipboard.setData(ClipboardData(text: widget.content))
        .then((_) {
          if (!mounted) return;
          _showHardnessSnackBar(
            context,
            SnackBar(
              content: Text(
                Localizations.localeOf(context).languageCode.startsWith('zh')
                    ? '代码已复制'
                    : 'Code copied',
              ),
              duration: const Duration(milliseconds: 1800),
            ),
          );
        })
        .catchError((Object _) {
          if (!mounted) return;
          setState(() => _copied = false);
          _showHardnessSnackBar(
            context,
            SnackBar(
              content: Text(
                Localizations.localeOf(context).languageCode.startsWith('zh')
                    ? '复制失败'
                    : 'Copy failed',
              ),
              duration: const Duration(milliseconds: 1800),
            ),
          );
        });
    _copiedResetTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark =
        widget.darkSurface || Theme.of(context).brightness == Brightness.dark;
    final cs = widget.colorScheme;
    final effectiveLanguage = _heNormalizeCodeLanguage(widget.language);
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');

    final containerColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : cs.surfaceContainerLow;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : cs.outlineVariant.withValues(alpha: 0.6);
    final headerColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : cs.surfaceContainer;
    final bodyColor = isDark
        ? Colors.black.withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.5);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: _br16,
        border: Border.all(color: borderColor),
      ),
      child: ClipRRect(
        borderRadius: _br16,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with language label and copy button
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                color: headerColor,
                border: Border(bottom: BorderSide(color: borderColor)),
              ),
              child: Row(
                children: [
                  if (effectiveLanguage != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.1)
                            : cs.primary.withValues(alpha: 0.08),
                        borderRadius: _br999,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.code_rounded,
                            size: 13,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.8)
                                : cs.onSurface,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            effectiveLanguage,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.8)
                                  : cs.onSurface,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    const SizedBox(height: 26),
                  const Spacer(),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _copyCode,
                      borderRadius: _br999,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : cs.surfaceContainerHighest,
                          borderRadius: _br999,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _copied
                                  ? Icons.check_rounded
                                  : Icons.content_copy_rounded,
                              size: 13,
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.8)
                                  : cs.onSurface,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _copied
                                  ? (isZh ? '已复制' : 'Copied')
                                  : (isZh ? '复制' : 'Copy'),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.8)
                                    : cs.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Code body with syntax highlighting
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: bodyColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : cs.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText.rich(
                  _highlightedSpan ?? const TextSpan(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// _HeDiffBlock — renders a unified diff with coloured line backgrounds.
// =============================================================================

class _HeDiffBlock extends StatelessWidget {
  const _HeDiffBlock({
    required this.rawDiff,
    required this.colorScheme,
    this.darkSurface = false,
  });

  final String rawDiff;
  final ColorScheme colorScheme;
  final bool darkSurface;

  static const _addedBg = Color(0xFF1A3D1A);
  static const _addedBgLight = Color(0xFFE6F4E6);
  static const _removedBg = Color(0xFF3D1A1A);
  static const _removedBgLight = Color(0xFFF4E6E6);
  static const _hunkBg = Color(0xFF1A2B3D);
  static const _hunkBgLight = Color(0xFFE6EEF4);

  @override
  Widget build(BuildContext context) {
    final isDark =
        darkSurface || Theme.of(context).brightness == Brightness.dark;
    final lines = rawDiff.split('\n');

    // Remove a trailing empty line that the Markdown parser often appends.
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    final trimmed = lines;

    return RepaintBoundary(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: _br16,
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.16)
                : colorScheme.outlineVariant.withValues(alpha: 0.40),
          ),
        ),
        child: ClipRRect(
          borderRadius: _br16,
          child: ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            cacheExtent: 600,
            addRepaintBoundaries: false, // each row is simple — skip overhead
            itemCount: trimmed.length,
            itemBuilder: (_, i) =>
                _DiffLine(line: trimmed[i], isDark: isDark, cs: colorScheme),
          ),
        ),
      ),
    );
  }
}

class _DiffLine extends StatelessWidget {
  const _DiffLine({required this.line, required this.isDark, required this.cs});

  final String line;
  final bool isDark;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    Color? bg;
    Color fg;
    FontWeight weight = FontWeight.normal;

    if (line.startsWith('+++') || line.startsWith('---')) {
      fg = cs.secondary;
      weight = FontWeight.w600;
    } else if (line.startsWith('+')) {
      bg = isDark
          ? _HeDiffBlock._addedBg.withValues(alpha: 0.55)
          : _HeDiffBlock._addedBgLight;
      fg = isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32);
    } else if (line.startsWith('-')) {
      bg = isDark
          ? _HeDiffBlock._removedBg.withValues(alpha: 0.55)
          : _HeDiffBlock._removedBgLight;
      fg = isDark ? const Color(0xFFE57373) : cs.error;
    } else if (line.startsWith('@@')) {
      bg = isDark
          ? _HeDiffBlock._hunkBg.withValues(alpha: 0.55)
          : _HeDiffBlock._hunkBgLight;
      fg = isDark ? const Color(0xFF90CAF9) : cs.primary;
      weight = FontWeight.w600;
    } else {
      fg = cs.onSurface.withValues(alpha: 0.80);
    }

    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 1),
      child: SelectableText(
        line.isEmpty ? '\u200B' : line,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.6,
          color: fg,
          fontWeight: weight,
        ),
      ),
    );
  }
}

/// Closes an unterminated fenced code block so the Markdown parser never
/// produces garbage output on streaming/partial content.
String _heCloseUnterminatedCodeBlock(String source) {
  final fenceRe = RegExp(r'^[ ]{0,3}(`{3,}|~{3,})[^\n]*$', multiLine: true);
  String? openFence;
  String? openMarker;
  for (final match in fenceRe.allMatches(source)) {
    final delim = match.group(1)!;
    final marker = delim[0];
    if (openFence == null) {
      openFence = delim;
      openMarker = marker;
    } else if (marker == openMarker && delim.length >= openFence.length) {
      openFence = null;
      openMarker = null;
    }
  }
  if (openFence == null) return source;
  return '$source\n$openFence';
}

String _heSanitizeMarkdownSource(String source) {
  if (source.isEmpty) {
    return source;
  }
  final escapedSetext = source.replaceAllMapped(
    _heSetextEscapePattern,
    (m) => '${m[1]}${m[2]}\\${m[3]}',
  );
  return _heCloseUnterminatedCodeBlock(escapedSetext);
}

/// Strip or normalize markdown attributes that flutter_markdown_plus would
/// feed into `int.parse` (currently only ordered-list `start`). Without this
/// guard a malformed attribute value can surface as an uncaught
/// FormatException that the Flutter engine reports from an async binding
/// callback, causing noticeable jank on first paint of a long thread.
void _heSanitizeMarkdownAst(List<md.Node> nodes) {
  for (final node in nodes) {
    if (node is! md.Element) {
      continue;
    }
    final attributes = node.attributes;
    if (node.tag == 'ol') {
      final start = attributes['start'];
      if (start == null || int.tryParse(start.trim()) == null) {
        attributes.remove('start');
      } else {
        attributes['start'] = int.parse(start.trim()).toString();
      }
    }
    final children = node.children;
    if (children != null && children.isNotEmpty) {
      _heSanitizeMarkdownAst(children);
    }
  }
}

// =============================================================================
// _HePill — matches _ToolbarPill (surfaceContainerHighest bg, primary icon, h:32)
// =============================================================================

// =============================================================================
// _HePill — backed by shared `OhPill` so other panels can reuse the visual.
// Typedef keeps existing call sites (`const _HePill(...)`) compiling untouched.
// =============================================================================

typedef _HePill = OhPill;

// =============================================================================
// _HeOutputLinesDial — mirrors _TokenDial but for CLI output lines
// Displays total output lines from all phase logs as a proxy for activity.
// =============================================================================

class _HeOutputLinesDial extends StatelessWidget {
  const _HeOutputLinesDial({required this.totalLines});

  final int totalLines;

  String _format(int n) {
    if (n == 0) return '--';
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: _br999,
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.terminal_rounded, size: 14, color: colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            _format(totalLines),
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Lines',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// _HeChip — matches _ToolExecutionChip (surface overlay bg, rounded)
// =============================================================================

class _HeChip extends StatelessWidget {
  const _HeChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: _br999,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

// =============================================================================
// _HeReadyPlaceholder — idle orchestrator (restored from disk); tap Start
// =============================================================================

class _HeReadyPlaceholder extends StatelessWidget {
  const _HeReadyPlaceholder({required this.isZh, required this.onStart});

  final bool isZh;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.construction_rounded,
            size: 48,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 16),
          Text(
            isZh
                ? '就绪，点击下方按钮以启动本次会话'
                : 'Ready \u2014 press Start to run the session',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(isZh ? '开始执行' : 'Start'),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// _InitializingPlaceholder — spinner while phases are being set up
// =============================================================================

class _InitializingPlaceholder extends StatelessWidget {
  const _InitializingPlaceholder({required this.isZh});

  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isZh ? '初始化中...' : 'Initializing\u2026',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _HeRestoredSessionPlaceholder extends StatelessWidget {
  const _HeRestoredSessionPlaceholder({
    required this.isZh,
    required this.status,
    required this.onRestart,
  });

  final bool isZh;
  final HardnessOrchestratorStatus status;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (icon, title) = switch (status) {
      HardnessOrchestratorStatus.completed => (
        Icons.check_circle_rounded,
        isZh ? '历史会话已恢复' : 'Historical session restored',
      ),
      HardnessOrchestratorStatus.failed => (
        Icons.error_rounded,
        isZh ? '历史失败会话已恢复' : 'Failed session restored',
      ),
      HardnessOrchestratorStatus.cancelled => (
        Icons.cancel_rounded,
        isZh ? '历史中止会话已恢复' : 'Cancelled session restored',
      ),
      _ => (
        Icons.history_rounded,
        isZh ? '历史会话已恢复' : 'Historical session restored',
      ),
    };

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 48,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isZh
                  ? '该会话来自旧版持久化数据，未保存可回放的阶段日志，因此无法还原阶段卡片。'
                  : 'This session was restored from an older persisted snapshot that did not save replayable phase logs.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRestart,
              icon: const Icon(Icons.restart_alt_rounded),
              label: Text(isZh ? '重新执行' : 'Run Again'),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// _HeComposer — HE composer with active permission toggle, collapse state,
// auto-follow control, and a conditional manual-review input.
// =============================================================================
