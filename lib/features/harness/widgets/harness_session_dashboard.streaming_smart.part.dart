part of 'harness_session_dashboard.dart';

/// 最新流式区块的淡入上移时长。
const Duration _kStreamingBlockRevealDuration = kOpenHandMotion380;

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
    with _HeMarkdownPathDelegate<_HeStreamingSmartView> {
  static const int _tailSize = 80;

  List<Widget>? _markdownChildren;
  String? _lastSanitised;
  String? _lastCommand;
  int _lastHiddenAbove = 0;
  int? _lastThemeHash;

  @override
  List<String> get markdownFilePathRoots => widget.filePathRoots;

  @override
  Color get markdownLinkColor => widget.colorScheme.primary;

  // 仅递增新内容修订号，避免已有区块重复播放动画。
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
      _disposeRecognizers();
      _markdownChildren = null;
      _lastChildCount = 0;
      return;
    }

    _disposeRecognizers();
    _parseMarkdown(sanitised);

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
        messageResolvedPathElementTag: _HeFilePathBuilder(
          textColor: widget.colorScheme.onSurface,
        ),
        messagePendingPathElementTag: _HeFilePathBuilder(
          textColor: widget.colorScheme.onSurface,
        ),
      },
    };

    try {
      // 流式快渲通道不解析数学：清单留空以保持与非流式渲染的差异显式。
      final astNodes = parseOpenHandMarkdown(
        source,
        inlineSyntaxes: inlineSyntaxes,
        blockSyntaxes: const <md.BlockSyntax>[],
      );
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
      _disposeRecognizers();
      _markdownChildren = <Widget>[
        Text(
          source,
          style: TextStyle(
            fontFamily: kOpenHandMonospaceFontFamily,
            fontSize: 13,
            color: widget.colorScheme.onSurface,
          ),
        ),
      ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme;
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
                fontFamily: kOpenHandMonospaceFontFamily,
                fontSize: 11,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        if (_lastCommand != null) ...[
          _HeCommandStrip(command: _lastCommand!),
          kOpenHandGap8,
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
              // 仅让最新区块淡入上移，已有区块保持稳定。
              Widget animatedLast(Widget w) => TweenAnimationBuilder<double>(
                key: ValueKey<int>(_contentRevision),
                tween: Tween<double>(begin: 0.0, end: 1.0),
                duration: openHandMotionDuration(
                  context,
                  _kStreamingBlockRevealDuration,
                ),
                curve: kOpenHandSwitchInCurve,
                builder: (_, v, child) => Opacity(
                  opacity: clampUnitInterval(v),
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
              kOpenHandHGap8,
              Text(
                openHandLocalizedText(
                  context,
                  zh: '正在输出…',
                  zhHant: '正在輸出…',
                  en: 'Streaming…',
                  fr: 'Flux en cours…',
                  de: 'Streaming…',
                  ja: '出力中…',
                ),
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
    if (element.tag == messageResolvedPathElementTag) {
      final path = messageResolvedPathFromElement(element);
      return Text.rich(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: OpenHandFilePathChip(
              displayPath: path.displayPath,
              resolvedPath: path.resolvedPath,
              isDirectory: path.isDirectory,
              textColor: textColor,
              onOpen: () =>
                  _heOpenPathInFileBrowser(context, path.resolvedPath),
            ),
          ),
        ),
      );
    }

    final path = messagePendingPathFromElement(element);

    return Text.rich(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: _HeAsyncFilePathChip(
          normalizedPath: path.normalizedPath,
          candidateRoots: path.candidateRoots,
          fullMatch: path.fullMatch,
          trailing: path.trailing,
          isCodeSpan: path.isCodeSpan,
          parentStyle: parentStyle,
          textColor: textColor,
        ),
      ),
    );
  }
}

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
                    child: OpenHandFilePathChip(
                      displayPath: widget.normalizedPath,
                      resolvedPath: widget.normalizedPath,
                      isDirectory: widget.trailing.contains('/'),
                      isUnresolved: true,
                      textColor: widget.textColor,
                      onOpen: () => _heOpenPathInFileBrowser(
                        context,
                        widget.normalizedPath,
                      ),
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
                child: OpenHandFilePathChip(
                  displayPath: resolvedPath.displayPath,
                  resolvedPath: resolvedPath.resolvedPath,
                  isDirectory: resolvedPath.isDirectory,
                  textColor: widget.textColor,
                  onOpen: () => _heOpenPathInFileBrowser(
                    context,
                    resolvedPath.resolvedPath,
                  ),
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
        borderRadius: BorderRadius.circular(kOpenHandRadius4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: kOpenHandMonospaceFontFamily,
          fontSize: 12,
          color: widget.textColor.withValues(alpha: 0.80),
        ),
      ),
    );
  }
}
