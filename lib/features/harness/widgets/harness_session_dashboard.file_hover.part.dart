part of 'harness_session_dashboard.dart';

Future<void> _heOpenPathInFileBrowser(BuildContext context, String path) async {
  try {
    final launched = await revealLocalPathInSystemFileManager(
      path,
      tag: 'harness_session_dashboard.file_hover.reveal',
    );
    if (launched) return;
    throw const FileSystemException('Unable to open file location.');
  } catch (error) {
    if (!context.mounted) return;
    showFriendlyErrorSnackBar(
      context,
      message: '$error',
      fallback: openHandLocalizedText(
        context,
        zh: '打开文件位置失败',
        en: 'Failed to open file location',
        zhHant: '打開檔案位置失敗',
        fr: 'Impossible d’ouvrir l’emplacement du fichier',
        de: 'Dateispeicherort konnte nicht geöffnet werden',
        ja: 'ファイルの場所を開けませんでした',
      ),
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
