part of 'hardness_session_dashboard.dart';

class _HeStreamingSmartView extends StatefulWidget {
  const _HeStreamingSmartView({
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

  @override
  State<_HeStreamingSmartView> createState() => _HeStreamingSmartViewState();
}

class _HeStreamingSmartViewState extends State<_HeStreamingSmartView>
    implements MarkdownBuilderDelegate {
  static const int _tailSize = 80;

  List<Widget>? _markdownChildren;
  String? _lastSanitised;
  String? _lastCommand;
  int _lastHiddenAbove = 0;
  int? _lastThemeHash;
  final List<GestureRecognizer> _recognizers = <GestureRecognizer>[];

  // Revision counter that increments whenever a new rendered block is added.
  // Used to key a TweenAnimationBuilder so only newly-appeared blocks
  // animate — existing blocks stay stable.
  int _contentRevision = 0;
  int _lastChildCount = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rebuildIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _HeStreamingSmartView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _rebuildIfNeeded();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _rebuildIfNeeded() {
    final lines = widget.lines;
    final start = lines.length > _tailSize ? lines.length - _tailSize : 0;
    final display = lines.length > _tailSize ? lines.sublist(start) : lines;
    final hiddenAbove = start;
    _lastHiddenAbove = hiddenAbove;

    final parsed = _heSplitLogForMarkdown(display);
    final body = parsed.body;
    _lastCommand = parsed.command;

    final sanitised = _heSanitizeMarkdownSource(body);
    final themeHash = Object.hashAll(<Object?>[
      widget.theme.brightness,
      widget.colorScheme.surface.toARGB32(),
      widget.colorScheme.primary.toARGB32(),
    ]);

    if (sanitised == _lastSanitised && themeHash == _lastThemeHash) return;
    _lastSanitised = sanitised;
    _lastThemeHash = themeHash;

    if (sanitised.isEmpty) {
      _markdownChildren = null;
      _lastChildCount = 0;
      return;
    }

    _disposeRecognizers();
    _parseMarkdown(sanitised);

    // If a new rendered block was added, bump the revision so the last block
    // gets a fresh fade-in animation (Q弹 entrance for new content chunks).
    final newCount = _markdownChildren?.length ?? 0;
    if (newCount > _lastChildCount) {
      _contentRevision++;
    }
    _lastChildCount = newCount;
  }

  void _parseMarkdown(String source) {
    final effectiveStyleSheet = MarkdownStyleSheet.fromTheme(
      widget.theme,
    ).merge(_heBuildMarkdownStyleSheet(widget.theme, widget.colorScheme));

    final inlineSyntaxes = widget.filePathRoots.isNotEmpty
        ? <md.InlineSyntax>[
            MessagePathCodeSyntax(candidateRoots: widget.filePathRoots),
            MessageFilePathSyntax(candidateRoots: widget.filePathRoots),
          ]
        : const <md.InlineSyntax>[];

    final builders = <String, MarkdownElementBuilder>{
      'pre': _HeDiffBuilder(colorScheme: widget.colorScheme),
      if (widget.filePathRoots.isNotEmpty) ...{
        'openhand-file-resolved': _HeFilePathBuilder(
          textColor: widget.colorScheme.onSurface,
        ),
        'openhand-file-pending': _HeFilePathBuilder(
          textColor: widget.colorScheme.onSurface,
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
        selectable: false,
        styleSheet: effectiveStyleSheet,
        imageDirectory: null,
        imageBuilder: null,
        checkboxBuilder: null,
        bulletBuilder: null,
        builders: builders,
        paddingBuilders: const <String, MarkdownPaddingBuilder>{},
        listItemCrossAxisAlignment: MarkdownListItemCrossAxisAlignment.baseline,
      );
      _markdownChildren = builder.build(astNodes);
    } catch (_) {
      // Fallback to plain text on parse error.
      _markdownChildren = <Widget>[
        Text(
          source,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            color: widget.colorScheme.onSurface,
          ),
        ),
      ];
    }
  }

  void _disposeRecognizers() {
    if (_recognizers.isEmpty) return;
    final local = List<GestureRecognizer>.from(_recognizers);
    _recognizers.clear();
    for (final r in local) {
      r.dispose();
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
    final colorScheme = widget.colorScheme;
    final isZh = widget.isZh;
    final children = _markdownChildren;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_lastHiddenAbove > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '… $_lastHiddenAbove ${_lastHiddenAbove == 1 ? 'line' : 'lines'} above',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        if (_lastCommand != null) ...[
          _HeCommandStrip(command: _lastCommand!),
          const SizedBox(height: 8),
        ],
        if (children != null && children.isNotEmpty)
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.white],
              stops: [0.0, 0.08],
            ).createShader(bounds),
            blendMode: BlendMode.dstIn,
            child: () {
              // Wrap the last rendered block in a Q弹 entrance animation:
              // whenever a new markdown block appears (_contentRevision ticks),
              // it fades in and slides up slightly. Existing blocks stay on
              // screen without flickering.
              Widget animatedLast(Widget w) => TweenAnimationBuilder<double>(
                key: ValueKey<int>(_contentRevision),
                tween: Tween<double>(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeOutCubic,
                builder: (_, v, child) => Opacity(
                  opacity: v.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0.0, 6.0 * (1.0 - v)),
                    child: child,
                  ),
                ),
                child: w,
              );
              if (children.length == 1) {
                return animatedLast(children.single);
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...children.take(children.length - 1),
                  animatedLast(children.last),
                ],
              );
            }(),
          ),
        // Streaming indicator
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
                isZh ? '正在输出…' : 'Streaming…',
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
// _HeFilePathBuilder — renders file path elements detected in markdown content.
// Supports both resolved (cached) and pending (async-resolved) paths following
// the same _AsyncFilePathChip pattern from the main chat.
// =============================================================================

class _HeFilePathBuilder extends MarkdownElementBuilder {
  _HeFilePathBuilder({required this.textColor});

  final Color textColor;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    if (element.tag == 'openhand-file-resolved') {
      final resolvedPath = (element.attributes['resolved_path'] ?? '').trim();
      final displayPath = element.textContent.trim();
      final isDirectory =
          (element.attributes['entity_type'] ?? '').trim() == 'directory';
      return Text.rich(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _HeFilePathChipInline(
              displayPath: displayPath,
              resolvedPath: resolvedPath,
              isDirectory: isDirectory,
              textColor: textColor,
            ),
          ),
        ),
      );
    }

    // Pending path — async resolve, then show chip or fallback.
    final normalizedPath = element.attributes['normalized_path'] ?? '';
    final candidateRoots = (element.attributes['candidate_roots'] ?? '').split(
      '\r',
    );
    final fullMatch = element.textContent;
    final trailing = element.attributes['trailing'] ?? '';
    final isCodeSpan = element.attributes['is_code_span'] == 'true';

    return Text.rich(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: _HeAsyncFilePathChip(
          normalizedPath: normalizedPath,
          candidateRoots: candidateRoots,
          fullMatch: fullMatch,
          trailing: trailing,
          isCodeSpan: isCodeSpan,
          parentStyle: parentStyle,
          textColor: textColor,
        ),
      ),
    );
  }
}

/// Async file-path chip that resolves paths in the background, matching
/// the _AsyncFilePathChip pattern from the main thread chat.
class _HeAsyncFilePathChip extends StatefulWidget {
  const _HeAsyncFilePathChip({
    required this.normalizedPath,
    required this.candidateRoots,
    required this.fullMatch,
    required this.trailing,
    required this.isCodeSpan,
    required this.parentStyle,
    required this.textColor,
  });

  final String normalizedPath;
  final List<String> candidateRoots;
  final String fullMatch;
  final String trailing;
  final bool isCodeSpan;
  final TextStyle? parentStyle;
  final Color textColor;

  @override
  State<_HeAsyncFilePathChip> createState() => _HeAsyncFilePathChipState();
}

class _HeAsyncFilePathChipState extends State<_HeAsyncFilePathChip> {
  Future<MessageResolvedPath?>? _future;

  @override
  void initState() {
    super.initState();
    _future = resolveExistingMessagePathAsync(
      widget.normalizedPath,
      widget.candidateRoots,
    );
  }

  @override
  void didUpdateWidget(_HeAsyncFilePathChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.normalizedPath != widget.normalizedPath ||
        oldWidget.candidateRoots.join('|') != widget.candidateRoots.join('|')) {
      _future = resolveExistingMessagePathAsync(
        widget.normalizedPath,
        widget.candidateRoots,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MessageResolvedPath?>(
      future: _future,
      builder: (context, snapshot) {
        final resolvedPath = snapshot.data;
        if (resolvedPath == null) {
          // Not resolved — show as code span or plain text.
          if (widget.isCodeSpan) {
            return _buildCodeSpan(context, widget.fullMatch);
          }
          final isExplicit =
              widget.normalizedPath.startsWith('~/') ||
              widget.normalizedPath.startsWith('./') ||
              widget.normalizedPath.startsWith('../') ||
              looksLikeAbsoluteMessagePath(widget.normalizedPath);
          if (isExplicit) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _HeFilePathChipInline(
                      displayPath: widget.normalizedPath,
                      resolvedPath: widget.normalizedPath,
                      isDirectory: widget.trailing.contains('/'),
                      isUnresolved: true,
                      textColor: widget.textColor,
                    ),
                  ),
                ),
                if (widget.trailing.isNotEmpty)
                  Text(widget.trailing, style: widget.parentStyle),
              ],
            );
          }
          return Text(widget.fullMatch, style: widget.parentStyle);
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _HeFilePathChipInline(
                  displayPath: resolvedPath.displayPath,
                  resolvedPath: resolvedPath.resolvedPath,
                  isDirectory: resolvedPath.isDirectory,
                  textColor: widget.textColor,
                ),
              ),
            ),
            if (widget.trailing.isNotEmpty)
              Text(widget.trailing, style: widget.parentStyle),
          ],
        );
      },
    );
  }

  Widget _buildCodeSpan(BuildContext context, String text) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: widget.textColor.withValues(alpha: 0.80),
        ),
      ),
    );
  }
}

class _HeFilePathChipInline extends StatelessWidget {
  const _HeFilePathChipInline({
    required this.displayPath,
    required this.resolvedPath,
    required this.isDirectory,
    this.isUnresolved = false,
    required this.textColor,
  });

  final String displayPath;
  final String resolvedPath;
  final bool isDirectory;
  final bool isUnresolved;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Match _FilePathChip reference: surface-based background + textColor.
    final chipColor = theme.colorScheme.surface.withValues(alpha: 0.68);
    final borderColor = textColor.withValues(alpha: 0.24);
    final labelStyle =
        theme.textTheme.labelMedium?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w700,
        ) ??
        TextStyle(color: textColor, fontWeight: FontWeight.w700);

    return _HeFileHoverPopup(
      resolvedPath: resolvedPath,
      isUnresolved: isUnresolved,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: _br999,
          onTap: isUnresolved ? null : () => _openPath(context),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isUnresolved
                  ? chipColor.withValues(alpha: 0.3)
                  : chipColor,
              borderRadius: _br999,
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isUnresolved
                      ? Icons.help_outline
                      : isDirectory
                      ? Icons.folder_outlined
                      : Icons.insert_drive_file_outlined,
                  size: 14,
                  color: isUnresolved
                      ? textColor.withValues(alpha: 0.5)
                      : textColor.withValues(alpha: 0.9),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: Text(
                      displayPath,
                      overflow: TextOverflow.ellipsis,
                      style: isUnresolved
                          ? labelStyle.copyWith(
                              color: textColor.withValues(alpha: 0.5),
                            )
                          : labelStyle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openPath(BuildContext context) {
    _heOpenPathInFileBrowser(context, resolvedPath, isDirectory: isDirectory);
  }
}

// =============================================================================
// _HeFileHoverPopup — Ctrl/Cmd+hover overlay showing file/directory metadata.
// Mirrors the _FileHoverPopup pattern from openhand_home_page.dart.
// =============================================================================

