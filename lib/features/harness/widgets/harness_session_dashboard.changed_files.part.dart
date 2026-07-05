part of 'harness_session_dashboard.dart';

class _HeChangedFilesList extends StatelessWidget {
  const _HeChangedFilesList({required this.files, required this.isZh});

  final List<HarnessChangedFile> files;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.78),
        borderRadius: _br16,
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.difference_rounded,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                _heHarnessText(
                  context,
                  zh: '文件变动 (${files.length})',
                  zhHant: '檔案變動 (${files.length})',
                  en: 'Changed Files (${files.length})',
                  fr: 'Fichiers modifiés (${files.length})',
                  de: 'Geänderte Dateien (${files.length})',
                  ja: '変更ファイル (${files.length})',
                ),
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            cacheExtent: 400,
            itemCount: files.length,
            itemBuilder: (context, index) {
              final file = files[index];
              final (icon, iconColor) = switch (file.changeType) {
                HarnessFileChangeType.added => (
                  Icons.add_circle_outline_rounded,
                  const Color(0xFF4CAF50),
                ),
                HarnessFileChangeType.modified => (
                  Icons.edit_outlined,
                  colorScheme.primary,
                ),
                HarnessFileChangeType.deleted => (
                  Icons.remove_circle_outline_rounded,
                  colorScheme.error,
                ),
              };
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: _br999,
                  onTap: () => _showDiffDialog(context, file),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 4,
                    ),
                    child: Row(
                      children: [
                        Icon(icon, size: 14, color: iconColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            file.relativePath,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showDiffDialog(BuildContext context, HarnessChangedFile file) {
    showAnimatedDialog(
      context: context,
      builder: (ctx) => _HeFileDiffDialog(file: file, isZh: isZh),
    );
  }
}

// _HeFileDiffDialog — full-width dialog showing file content diff.
// Computes diff asynchronously in an isolate to keep the UI responsive.
/// Isolate-friendly top-level function for diff computation.
List<String> _computeDiffIsolate(List<Object> args) {
  return unifiedDiffLinesFromText(args[0] as String, args[1] as String);
}

class _HeFileDiffDialog extends StatefulWidget {
  const _HeFileDiffDialog({required this.file, required this.isZh});

  final HarnessChangedFile file;
  final bool isZh;

  @override
  State<_HeFileDiffDialog> createState() => _HeFileDiffDialogState();
}

class _HeFileDiffDialogState extends State<_HeFileDiffDialog> {
  List<String>? _diffLines;
  bool _computing = true;

  @override
  void initState() {
    super.initState();
    _computeDiff();
  }

  Future<void> _computeDiff() async {
    final before = widget.file.beforeContent ?? '';
    final after = widget.file.afterContent ?? '';
    try {
      final result = await compute(_computeDiffIsolate, <Object>[
        before,
        after,
      ]);
      if (mounted) {
        setState(() {
          _diffLines = result;
          _computing = false;
        });
      }
    } catch (_) {
      // Fallback: compute on main thread.
      if (!mounted) return;
      final result = unifiedDiffLinesFromText(before, after);
      if (mounted) {
        setState(() {
          _diffLines = result;
          _computing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final file = widget.file;
    final diffLines = _diffLines ?? const <String>[];
    final additions = diffLines.where((l) => l.startsWith('+')).length - 1;
    final deletions = diffLines.where((l) => l.startsWith('-')).length - 1;
    final safeAdditions = additions < 0 ? 0 : additions;
    final safeDeletions = deletions < 0 ? 0 : deletions;

    return buildOpenHandResponsiveDialogShell(
      context: context,
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Title ──
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.relativePath,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _DiffStatChip(
                            label: _changeTypeLabel(),
                            color: switch (file.changeType) {
                              HarnessFileChangeType.added => const Color(
                                0xFF4CAF50,
                              ),
                              HarnessFileChangeType.modified =>
                                colorScheme.primary,
                              HarnessFileChangeType.deleted =>
                                colorScheme.error,
                            },
                          ),
                          if (!_computing) ...[
                            const SizedBox(width: 8),
                            Text(
                              _heHarnessText(
                                context,
                                zh: '$safeAdditions 处新增，$safeDeletions 处删除',
                                zhHant: '$safeAdditions 處新增，$safeDeletions 處刪除',
                                en: '$safeAdditions additions, $safeDeletions deletions',
                                fr: '$safeAdditions ajouts, $safeDeletions suppressions',
                                de: '$safeAdditions Ergänzungen, $safeDeletions Löschungen',
                                ja: '$safeAdditions 件追加、$safeDeletions 件削除',
                              ),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // ── Diff view ──
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.6,
                  ),
                  borderRadius: _br16,
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.40),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: _br16,
                  child: _computing
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(),
                                const SizedBox(height: 16),
                                Text(
                                  _heHarnessText(
                                    context,
                                    zh: '正在计算差异…',
                                    zhHant: '正在計算差異…',
                                    en: 'Computing diff…',
                                    fr: 'Calcul du diff…',
                                    de: 'Diff wird berechnet…',
                                    ja: '差分を計算中…',
                                  ),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          cacheExtent: 400,
                          itemCount: diffLines.length,
                          itemBuilder: (_, i) => _DiffLine(
                            line: diffLines[i],
                            isDark: isDark,
                            cs: colorScheme,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OpenHandDialogActionButton.secondary(
                  onPressed: _computing
                      ? null
                      : () {
                          Clipboard.setData(
                            ClipboardData(text: diffLines.join('\n')),
                          );
                          showOpenHandSnackBar(
                            context,
                            SnackBar(
                              content: Text(
                                _heHarnessText(
                                  context,
                                  zh: 'Diff 已复制',
                                  zhHant: 'Diff 已複製',
                                  en: 'Diff copied',
                                  fr: 'Diff copié',
                                  de: 'Diff kopiert',
                                  ja: 'Diff をコピーしました',
                                ),
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                  label: _heHarnessText(
                    context,
                    zh: '复制 Diff',
                    zhHant: '複製 Diff',
                    en: 'Copy Diff',
                    fr: 'Copier le diff',
                    de: 'Diff kopieren',
                    ja: 'Diff をコピー',
                  ),
                ),
                const SizedBox(width: 10),
                OpenHandDialogActionButton.secondary(
                  onPressed: () => Navigator.of(context).pop(),
                  label: _heHarnessText(
                    context,
                    zh: '关闭',
                    zhHant: '關閉',
                    en: 'Close',
                    fr: 'Fermer',
                    de: 'Schließen',
                    ja: '閉じる',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _changeTypeLabel() {
    return switch (widget.file.changeType) {
      HarnessFileChangeType.added => _heHarnessText(
        context,
        zh: '新增文件',
        zhHant: '新增檔案',
        en: 'Added',
        fr: 'Ajouté',
        de: 'Hinzugefügt',
        ja: '追加',
      ),
      HarnessFileChangeType.modified => _heHarnessText(
        context,
        zh: '已修改',
        zhHant: '已修改',
        en: 'Modified',
        fr: 'Modifié',
        de: 'Geändert',
        ja: '変更済み',
      ),
      HarnessFileChangeType.deleted => _heHarnessText(
        context,
        zh: '已删除',
        zhHant: '已刪除',
        en: 'Deleted',
        fr: 'Supprimé',
        de: 'Gelöscht',
        ja: '削除済み',
      ),
    };
  }
}

class _DiffStatChip extends StatelessWidget {
  const _DiffStatChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: _br999,
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// _HeStreamingSmartView — StatefulWidget that caches the parsed markdown AST
// between rebuilds during streaming, only re-parsing when the content actually
// changes. Uses _SafeMarkdownBody-style manual AST parsing + MarkdownBuilder
// for reliability and performance during rapid streaming updates.
