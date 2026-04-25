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

    try {
      final document = md.Document(
        extensionSet: md.ExtensionSet.gitHubFlavored,
        inlineSyntaxes: inlineSyntaxes,
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
        builders: builders,
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
          ScaffoldMessenger.of(context).showSnackBar(
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
          ScaffoldMessenger.of(context).showSnackBar(
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
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
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
          return const Color(0xFFF59E0B);
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
    if (!_diffLangRe.hasMatch(cls)) return null;

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

    return _HeDiffBlock(
      rawDiff: rawText,
      colorScheme: colorScheme,
      darkSurface: darkSurface,
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

/// Closes an unterminated fenced code block so the Markdown parser/// never produces garbage output on streaming/partial content.
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

class _HePill extends StatelessWidget {
  const _HePill({
    required this.icon,
    required this.label,
    this.onTap,
    this.foregroundColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedForeground = foregroundColor ?? theme.colorScheme.primary;
    final child = Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: _br999,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: resolvedForeground),
          const SizedBox(width: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: theme.textTheme.labelMedium?.copyWith(
              color: foregroundColor ?? theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      borderRadius: _br999,
      child: InkWell(
        onTap: onTap,
        borderRadius: _br999,
        overlayColor: WidgetStatePropertyAll<Color>(
          theme.colorScheme.primary.withValues(alpha: 0.08),
        ),
        child: child,
      ),
    );
  }
}

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

