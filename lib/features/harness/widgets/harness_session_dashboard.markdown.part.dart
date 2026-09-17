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
      'code': OpenHandMessageMarkdownThemeData.resolve(
        theme: widget.theme,
        backgroundColor: bg ?? widget.colorScheme.surface,
        textColor: widget.textColor ?? widget.colorScheme.onSurface,
      ).inlineCodeBuilder,
      'pre': OpenHandHighlightedCodeBlockBuilder(
        theme: widget.theme,
        baseColor: widget.textColor ?? widget.colorScheme.onSurface,
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

class _DiffLine extends StatelessWidget {
  const _DiffLine({required this.line, required this.isDark, required this.cs});

  static const _addedBg = Color(0xFF1A3D1A);
  static const _addedBgLight = Color(0xFFE6F4E6);
  static const _removedBg = Color(0xFF3D1A1A);
  static const _removedBgLight = Color(0xFFF4E6E6);
  static const _hunkBg = Color(0xFF1A2B3D);
  static const _hunkBgLight = Color(0xFFE6EEF4);

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
      bg = isDark ? _addedBg.withValues(alpha: 0.55) : _addedBgLight;
      fg = isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32);
    } else if (line.startsWith('-')) {
      bg = isDark ? _removedBg.withValues(alpha: 0.55) : _removedBgLight;
      fg = isDark ? const Color(0xFFE57373) : cs.error;
    } else if (line.startsWith('@@')) {
      bg = isDark ? _hunkBg.withValues(alpha: 0.55) : _hunkBgLight;
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
  const _HeReadyPlaceholder({required this.onStart});

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
  const _InitializingPlaceholder();

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
    required this.status,
    required this.onRestart,
  });

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
