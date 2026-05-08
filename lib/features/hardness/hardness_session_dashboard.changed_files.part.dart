part of 'hardness_session_dashboard.dart';

class _HeChangedFilesList extends StatelessWidget {
  const _HeChangedFilesList({required this.files, required this.isZh});

  final List<HardnessChangedFile> files;
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
                isZh
                    ? '文件变动 (${files.length})'
                    : 'Changed Files (${files.length})',
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
                HardnessFileChangeType.added => (
                  Icons.add_circle_outline_rounded,
                  const Color(0xFF4CAF50),
                ),
                HardnessFileChangeType.modified => (
                  Icons.edit_outlined,
                  colorScheme.primary,
                ),
                HardnessFileChangeType.deleted => (
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

  void _showDiffDialog(BuildContext context, HardnessChangedFile file) {
    showAnimatedDialog(
      context: context,
      builder: (ctx) => _HeFileDiffDialog(file: file, isZh: isZh),
    );
  }
}

// =============================================================================
// _HeFileDiffDialog — full-width dialog showing file content diff.
// Computes diff asynchronously in an isolate to keep the UI responsive.
// =============================================================================

/// Isolate-friendly top-level function for diff computation.
List<String> _computeDiffIsolate(List<Object> args) {
  final before = (args[0] as String).split('\n');
  final after = (args[1] as String).split('\n');
  return _computeSimpleUnifiedDiff(before, after);
}

class _HeFileDiffDialog extends StatefulWidget {
  const _HeFileDiffDialog({required this.file, required this.isZh});

  final HardnessChangedFile file;
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
      final result = _computeSimpleUnifiedDiff(
        before.split('\n'),
        after.split('\n'),
      );
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
    final isZh = widget.isZh;
    final file = widget.file;
    final diffLines = _diffLines ?? const <String>[];

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 900,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
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
                                HardnessFileChangeType.added => const Color(
                                  0xFF4CAF50,
                                ),
                                HardnessFileChangeType.modified =>
                                  colorScheme.primary,
                                HardnessFileChangeType.deleted =>
                                  colorScheme.error,
                              },
                            ),
                            if (!_computing) ...[
                              const SizedBox(width: 8),
                              Text(
                                '${diffLines.where((l) => l.startsWith('+')).length - 1} additions, '
                                '${diffLines.where((l) => l.startsWith('-')).length - 1} deletions',
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
                                    isZh ? '正在计算差异…' : 'Computing diff…',
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
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OpenHandDialogActionButton.secondary(
                    onPressed: _computing
                        ? null
                        : () {
                            Clipboard.setData(
                              ClipboardData(text: diffLines.join('\n')),
                            );
                            _showHardnessSnackBar(
                              context,
                              SnackBar(
                                content: Text(
                                  isZh ? 'Diff 已复制' : 'Diff copied',
                                ),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                    label: isZh ? '复制 Diff' : 'Copy Diff',
                  ),
                  const SizedBox(width: 10),
                  OpenHandDialogActionButton.secondary(
                    onPressed: () => Navigator.of(context).pop(),
                    label: isZh ? '关闭' : 'Close',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _changeTypeLabel() {
    return switch (widget.file.changeType) {
      HardnessFileChangeType.added => widget.isZh ? '新增文件' : 'Added',
      HardnessFileChangeType.modified => widget.isZh ? '已修改' : 'Modified',
      HardnessFileChangeType.deleted => widget.isZh ? '已删除' : 'Deleted',
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

/// Computes a unified diff between two lists of lines using the Myers
/// algorithm with proper backtracking and hunk generation. Context lines
/// default to 3 around each change.
List<String> _computeSimpleUnifiedDiff(
  List<String> before,
  List<String> after,
) {
  if (before.isEmpty && after.isEmpty) return const [];
  if (before.isEmpty) {
    return [
      '--- /dev/null',
      '+++ b/file',
      '@@ -0,0 +1,${after.length} @@',
      ...after.map((l) => '+$l'),
    ];
  }
  if (after.isEmpty) {
    return [
      '--- a/file',
      '+++ /dev/null',
      '@@ -1,${before.length} +0,0 @@',
      ...before.map((l) => '-$l'),
    ];
  }

  // For very large files, fall back to a simple line-by-line comparison.
  if (before.length + after.length > 10000) {
    return _fallbackDiff(before, after);
  }

  // ── Myers diff (forward pass) ──────────────────────────────────────
  final n = before.length;
  final m = after.length;
  final max = n + m;
  final size = 2 * max + 1;
  final v = List<int>.filled(size, 0);
  final traces = <List<int>>[];

  var found = false;
  for (var d = 0; d <= max && !found; d++) {
    traces.add(List<int>.from(v));
    for (var k = -d; k <= d; k += 2) {
      int x;
      if (k == -d || (k != d && v[k - 1 + max] < v[k + 1 + max])) {
        x = v[k + 1 + max];
      } else {
        x = v[k - 1 + max] + 1;
      }
      var y = x - k;
      while (x < n && y < m && before[x] == after[y]) {
        x++;
        y++;
      }
      v[k + max] = x;
      if (x >= n && y >= m) {
        found = true;
        break;
      }
    }
  }

  // ── Backtrack to produce the edit script (in forward order) ────────
  final editScript = <({String type, String text})>[];
  var bx = n, by = m;
  for (var d = traces.length - 1; d > 0; d--) {
    final vPrev = traces[d - 1];
    final k = bx - by;
    int prevK;
    if (k == -d || (k != d && vPrev[k - 1 + max] < vPrev[k + 1 + max])) {
      prevK = k + 1;
    } else {
      prevK = k - 1;
    }
    final prevX = vPrev[prevK + max];
    final prevY = prevX - prevK;

    // Diagonal (equal) lines
    while (bx > prevX && by > prevY) {
      bx--;
      by--;
      editScript.add((type: ' ', text: before[bx]));
    }
    if (bx == prevX && by > prevY) {
      by--;
      editScript.add((type: '+', text: after[by]));
    } else if (by == prevY && bx > prevX) {
      bx--;
      editScript.add((type: '-', text: before[bx]));
    }
  }
  // Any remaining diagonal at d=0
  while (bx > 0 && by > 0) {
    bx--;
    by--;
    editScript.add((type: ' ', text: before[bx]));
  }
  while (bx > 0) {
    bx--;
    editScript.add((type: '-', text: before[bx]));
  }
  while (by > 0) {
    by--;
    editScript.add((type: '+', text: after[by]));
  }

  // Reverse because we built it backwards
  final edits = editScript.reversed.toList();

  // ── Generate unified-diff hunks with 3-line context ────────────────
  const contextSize = 3;
  final result = <String>['--- a/file', '+++ b/file'];

  // Find change regions.
  final changeIndices = <int>[];
  for (var i = 0; i < edits.length; i++) {
    if (edits[i].type != ' ') changeIndices.add(i);
  }
  if (changeIndices.isEmpty) return const []; // identical files

  // Group changes into hunks.
  final hunkRanges = <(int, int)>[];
  var hunkStart = (changeIndices.first - contextSize).clamp(0, edits.length);
  var hunkEnd = (changeIndices.first + contextSize + 1).clamp(0, edits.length);

  for (var ci = 1; ci < changeIndices.length; ci++) {
    final s = (changeIndices[ci] - contextSize).clamp(0, edits.length);
    final e = (changeIndices[ci] + contextSize + 1).clamp(0, edits.length);
    if (s <= hunkEnd) {
      // Merge with current hunk.
      hunkEnd = e;
    } else {
      hunkRanges.add((hunkStart, hunkEnd));
      hunkStart = s;
      hunkEnd = e;
    }
  }
  hunkRanges.add((hunkStart, hunkEnd));

  // Emit each hunk.
  for (final (start, end) in hunkRanges) {
    var beforeLine = 0;
    var afterLine = 0;
    // Count lines up to hunk start.
    for (var i = 0; i < start; i++) {
      if (edits[i].type != '+') beforeLine++;
      if (edits[i].type != '-') afterLine++;
    }
    final hunkBeforeStart = beforeLine + 1;
    final hunkAfterStart = afterLine + 1;
    var hunkBeforeCount = 0;
    var hunkAfterCount = 0;
    final hunkLines = <String>[];
    for (var i = start; i < end; i++) {
      final e = edits[i];
      hunkLines.add('${e.type}${e.text}');
      if (e.type != '+') hunkBeforeCount++;
      if (e.type != '-') hunkAfterCount++;
    }
    result.add(
      '@@ -$hunkBeforeStart,$hunkBeforeCount '
      '+$hunkAfterStart,$hunkAfterCount @@',
    );
    result.addAll(hunkLines);
  }

  return result;
}

List<String> _fallbackDiff(List<String> before, List<String> after) {
  final result = <String>['--- a/file', '+++ b/file'];
  final maxLen = before.length > after.length ? before.length : after.length;
  var diffStart = -1;
  final hunks = <String>[];

  for (var i = 0; i < maxLen; i++) {
    final bLine = i < before.length ? before[i] : null;
    final aLine = i < after.length ? after[i] : null;
    if (bLine == aLine) {
      if (hunks.isNotEmpty) {
        result.add('@@ -${diffStart + 1} @@');
        result.addAll(hunks);
        hunks.clear();
        diffStart = -1;
      }
      continue;
    }
    if (diffStart < 0) diffStart = i;
    if (bLine != null) hunks.add('-$bLine');
    if (aLine != null) hunks.add('+$aLine');
  }
  if (hunks.isNotEmpty) {
    result.add('@@ -${(diffStart < 0 ? 0 : diffStart) + 1} @@');
    result.addAll(hunks);
  }

  return result;
}

// =============================================================================
// _HeStreamingSmartView — StatefulWidget that caches the parsed markdown AST
// between rebuilds during streaming, only re-parsing when the content actually
// changes. Uses _SafeMarkdownBody-style manual AST parsing + MarkdownBuilder
// for reliability and performance during rapid streaming updates.
// =============================================================================
