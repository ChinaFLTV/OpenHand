part of 'harness_session_dashboard.dart';

void _disposeMarkdownRecognizers(List<GestureRecognizer> recognizers) {
  if (recognizers.isEmpty) return;
  final pending = List<GestureRecognizer>.of(recognizers, growable: false);
  recognizers.clear();
  for (final recognizer in pending) {
    recognizer.dispose();
  }
}

/// Markdown 路径链接的公共委托实现。
///
/// 完整视图与流式视图的链接识别、行内代码路径高亮与识别器生命周期完全一致；
/// 集中在这里，避免两处的跳转规则随各自演进而分叉。
mixin _HeMarkdownPathDelegate<T extends StatefulWidget> on State<T>
    implements MarkdownBuilderDelegate {
  final List<GestureRecognizer> _recognizers = <GestureRecognizer>[];

  /// 解析相对路径时的候选根目录。
  List<String> get markdownFilePathRoots;

  /// 行内代码识别为路径后的着色。
  Color get markdownLinkColor;

  void _disposeRecognizers() => _disposeMarkdownRecognizers(_recognizers);

  @override
  GestureRecognizer createLink(String text, String? href, String title) {
    return _createMarkdownPathLink(
      context: context,
      href: href,
      filePathRoots: markdownFilePathRoots,
      recognizers: _recognizers,
    );
  }

  @override
  TextSpan formatText(MarkdownStyleSheet styleSheet, String code) {
    return _formatMarkdownPathCode(
      context: context,
      styleSheet: styleSheet,
      code: code,
      filePathRoots: markdownFilePathRoots,
      recognizers: _recognizers,
      linkColor: markdownLinkColor,
    );
  }
}

GestureRecognizer _createMarkdownPathLink({
  required BuildContext context,
  required String? href,
  required List<String> filePathRoots,
  required List<GestureRecognizer> recognizers,
}) {
  final recognizer = TapGestureRecognizer();
  recognizers.add(recognizer);
  final resolvedPath = resolveMarkdownMessageLinkPath(href, filePathRoots);
  if (resolvedPath == null) return recognizer;
  recognizer.onTap = () {
    unawaited(
      copyOpenHandTextToClipboard(
        logTag: 'harness',
        context: context,
        text: resolvedPath.resolvedPath,
        successMessage: openHandLocalizedText(
          context,
          zh: '路径已复制：${resolvedPath.resolvedPath}',
          en: 'Path copied: ${resolvedPath.resolvedPath}',
        ),
        logAction: '复制 Markdown 链接路径',
      ),
    );
  };
  return recognizer;
}

TextSpan _formatMarkdownPathCode({
  required BuildContext context,
  required MarkdownStyleSheet styleSheet,
  required String code,
  required List<String> filePathRoots,
  required List<GestureRecognizer> recognizers,
  required Color linkColor,
}) {
  final normalizedCode = code.replaceAll(RegExp(r'\n$'), '');
  final resolvedPath = resolveExistingMessagePath(
    normalizedCode,
    filePathRoots,
  );
  if (resolvedPath == null) {
    return TextSpan(text: normalizedCode, style: styleSheet.code);
  }
  final recognizer = TapGestureRecognizer()
    ..onTap = () {
      unawaited(
        copyOpenHandTextToClipboard(
          logTag: 'harness',
          context: context,
          text: resolvedPath.resolvedPath,
          successMessage: openHandLocalizedText(
            context,
            zh: '路径已复制：${resolvedPath.resolvedPath}',
            en: 'Path copied: ${resolvedPath.resolvedPath}',
          ),
          logAction: '复制 Markdown 代码路径',
        ),
      );
    };
  recognizers.add(recognizer);
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

  /// 非空时覆盖 Markdown 配色，确保内容在指定背景上清晰可读。
  final Color? cardBackground;

  @override
  State<_HeSafeMarkdownBody> createState() => _HeSafeMarkdownBodyState();
}

class _HeSafeMarkdownBodyState extends State<_HeSafeMarkdownBody>
    with _HeMarkdownPathDelegate<_HeSafeMarkdownBody> {
  List<Widget>? _children;
  String? _lastSanitised;
  String? _lastRawContent;
  int? _lastThemeHash;

  @override
  List<String> get markdownFilePathRoots => widget.filePathRoots;

  @override
  Color get markdownLinkColor => widget.colorScheme.primary;

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
    // 内容和主题未变化时跳过重复清洗与解析。
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
      _disposeRecognizers();
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
        messageResolvedPathElementTag: _HeFilePathBuilder(
          textColor: widget.textColor ?? widget.colorScheme.onSurface,
        ),
        messagePendingPathElementTag: _HeFilePathBuilder(
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
      final astNodes = parseOpenHandMarkdown(
        source,
        inlineSyntaxes: effectiveInlineSyntaxes,
      );
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
      _disposeRecognizers();
      final fallbackStyle = TextStyle(
        fontFamily: kOpenHandMonospaceFontFamily,
        fontSize: 13,
        color: widget.textColor ?? widget.colorScheme.onSurface,
      );
      _children = <Widget>[SelectableText(source, style: fallbackStyle)];
    }
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

  // 长内容默认折叠。
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
    // 优先在字符上限前的词边界截断。
    final cut = widget.content.lastIndexOf(
      RegExp(r'\s'),
      _HeMarkdownContent._previewChars,
    );
    final end = cut > 0 ? cut : _HeMarkdownContent._previewChars;
    return clipTextByCodeUnits(widget.content, end, suffix: '…');
  }

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: kOpenHandMotion280)
      ..value = 1.0;
    // 入场使用 easeOutCubic：开始快、收尾舒缓，符合全局丝滑节奏；
    // 与 easeIn（开始慢）相比能更早把首帧像素呈现给用户。
    _fadeAnim = CurvedAnimation(
      parent: _fadeCtrl,
      curve: kOpenHandSwitchInCurve,
    );
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
          kOpenHandGap6,
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
          kOpenHandGap4,
          OpenHandTapRegion(
            onTap: _expand,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: kOpenHandBorderRadius16,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.expand_more_rounded,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  kOpenHandHGap6,
                  Text(
                    openHandLocalizedText(
                      context,
                      zh: '展开全部内容',
                      zhHant: '展開全部內容',
                      en: 'Show full content',
                      fr: 'Afficher tout le contenu',
                      de: 'Vollständigen Inhalt anzeigen',
                      ja: '全文を表示',
                    ),
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
      borderRadius: kOpenHandPillBorderRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: kOpenHandPillBorderRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: colorScheme.primary),
              kOpenHandHGap5,
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

class _LogLine extends StatelessWidget {
  const _LogLine({required this.line, required this.colorScheme});

  final String line;
  final ColorScheme colorScheme;

  Color? _resolveColor() {
    if (line.startsWith('\u2713')) return OpenHandStatusColors.success;
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
          fontFamily: kOpenHandMonospaceFontFamily,
          fontSize: 12.5,
          height: 1.55,
          color: color ?? colorScheme.onSurface.withValues(alpha: 0.87),
          fontWeight: weight,
        ),
      ),
    );
  }
}

/// 将 diff 或 patch 围栏代码块渲染为专用差异视图。
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
    if (element.tag != 'pre') return null;

    final codeEl = element.children
        ?.whereType<md.Element>()
        .where((e) => e.tag == 'code')
        .firstOrNull;

    if (codeEl == null) return null;

    final cls = codeEl.attributes['class'] ?? '';

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

    if (_diffLangRe.hasMatch(cls)) {
      return _HeDiffBlock(
        rawDiff: rawText,
        colorScheme: colorScheme,
        darkSurface: darkSurface,
      );
    }

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

/// Harness 会话的高亮代码面板，与应用端保持一致。
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
      fontFamily: kOpenHandMonospaceFontFamily,
      fontSize: 13,
      height: 1.5,
      color: isDark
          ? Colors.white.withValues(alpha: 0.92)
          : widget.colorScheme.onSurface,
    );

    // 超大代码块跳过高亮，避免阻塞界面。
    if (widget.content.length > 80 * kBytesPerKiB) {
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
    unawaited(
      copyOpenHandTextToClipboard(
            logTag: 'harness',
            context: context,
            text: widget.content,
            successMessage: openHandLocalizedText(
              context,
              zh: '代码已复制',
              zhHant: '程式碼已複製',
              en: 'Code copied',
              fr: 'Code copié',
              de: 'Code kopiert',
              ja: 'コードをコピーしました',
            ),
            logAction: '复制 Markdown 代码块',
            successDuration: const Duration(milliseconds: 1800),
          )
          .then((copied) {
            if (copied || !mounted) return;
            setState(() => _copied = false);
          })
          .catchError((Object _) {
            if (!mounted) return;
            setState(() => _copied = false);
          }),
    );
    _copiedResetTimer = startSafeTimer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark =
        widget.darkSurface || Theme.of(context).brightness == Brightness.dark;
    final cs = widget.colorScheme;
    final effectiveLanguage = _heNormalizeCodeLanguage(widget.language);

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
        borderRadius: kOpenHandBorderRadius16,
        border: Border.all(color: borderColor),
      ),
      child: ClipRRect(
        borderRadius: kOpenHandBorderRadius16,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                        borderRadius: kOpenHandPillBorderRadius,
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
                          kOpenHandHGap5,
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
                    kOpenHandGap26,
                  const Spacer(),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _copyCode,
                      borderRadius: kOpenHandPillBorderRadius,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : cs.surfaceContainerHighest,
                          borderRadius: kOpenHandPillBorderRadius,
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
                            kOpenHandHGap5,
                            Text(
                              _copied
                                  ? openHandCopiedLabel(context)
                                  : openHandCopyLabel(context),
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
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: bodyColor,
                borderRadius: _br12,
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

/// 带行背景色的统一差异视图。
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

    // 移除 Markdown 解析器常附加的末尾空行。
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
          borderRadius: kOpenHandBorderRadius16,
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.16)
                : colorScheme.outlineVariant.withValues(alpha: 0.40),
          ),
        ),
        child: ClipRRect(
          borderRadius: kOpenHandBorderRadius16,
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
          fontFamily: kOpenHandMonospaceFontFamily,
          fontSize: 12,
          height: 1.6,
          color: fg,
          fontWeight: weight,
        ),
      ),
    );
  }
}

/// 补齐未闭合的围栏代码块，避免流式片段产生错误结构。
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
          kOpenHandGap16,
          Text(
            openHandLocalizedText(
              context,
              zh: '就绪，点击下方按钮以启动本次会话',
              zhHant: '已就緒，點擊下方按鈕以啟動本次會話',
              en: 'Ready — press Start to run the session',
              fr: 'Prêt — appuyez sur Démarrer pour lancer la session',
              de: 'Bereit — Start drücken, um die Sitzung auszuführen',
              ja: '準備完了 — 開始を押してセッションを実行',
            ),
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
          ),
          kOpenHandGap20,
          FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(_heStartLabel(context)),
          ),
        ],
      ),
    );
  }
}

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
          kOpenHandGap16,
          Text(
            openHandLocalizedText(
              context,
              zh: '初始化中...',
              zhHant: '初始化中...',
              en: 'Initializing…',
              fr: 'Initialisation…',
              de: 'Initialisierung…',
              ja: '初期化中…',
            ),
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
  final HarnessOrchestratorStatus status;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (icon, title) = switch (status) {
      HarnessOrchestratorStatus.completed => (
        Icons.check_circle_rounded,
        _harnessSessionHistoricalSessionRestoredLabel(context),
      ),
      HarnessOrchestratorStatus.failed => (
        Icons.error_rounded,
        openHandLocalizedText(
          context,
          zh: '历史失败会话已恢复',
          zhHant: '歷史失敗會話已恢復',
          en: 'Failed session restored',
          fr: 'Session échouée restaurée',
          de: 'Fehlgeschlagene Sitzung wiederhergestellt',
          ja: '失敗したセッションを復元しました',
        ),
      ),
      HarnessOrchestratorStatus.cancelled => (
        Icons.cancel_rounded,
        openHandLocalizedText(
          context,
          zh: '历史中止会话已恢复',
          zhHant: '歷史中止會話已恢復',
          en: 'Cancelled session restored',
          fr: 'Session annulée restaurée',
          de: 'Abgebrochene Sitzung wiederhergestellt',
          ja: '中止されたセッションを復元しました',
        ),
      ),
      _ => (
        Icons.history_rounded,
        _harnessSessionHistoricalSessionRestoredLabel(context),
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
            kOpenHandGap16,
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            kOpenHandGap8,
            Text(
              openHandLocalizedText(
                context,
                zh: '该会话来自旧版持久化数据，未保存可回放的阶段日志，因此无法还原阶段卡片。',
                zhHant: '該會話來自舊版持久化資料，未保存可回放的階段日誌，因此無法還原階段卡片。',
                en: 'This session was restored from an older persisted snapshot that did not save replayable phase logs.',
                fr: 'Cette session vient d’un ancien instantané sans journaux de phase rejouables.',
                de: 'Diese Sitzung stammt aus einem älteren Snapshot ohne wiederabspielbare Phasenlogs.',
                ja: 'このセッションは古い保存データから復元され、再生可能なフェーズログがないためカードを復元できません。',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            kOpenHandGap16,
            OutlinedButton.icon(
              onPressed: onRestart,
              icon: const Icon(Icons.restart_alt_rounded),
              label: Text(_heRunAgainLabel(context)),
            ),
          ],
        ),
      ),
    );
  }
}

String _harnessSessionHistoricalSessionRestoredLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '历史会话已恢复',
    zhHant: '歷史會話已恢復',
    en: 'Historical session restored',
    fr: 'Session historique restaurée',
    de: 'Historische Sitzung wiederhergestellt',
    ja: '履歴セッションを復元しました',
  );
}
