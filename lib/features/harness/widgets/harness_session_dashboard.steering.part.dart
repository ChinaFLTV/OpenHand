part of 'harness_session_dashboard.dart';

const int _harnessSteeringFileMaxBytes = 4 * kBytesPerMiB;
const int _harnessSteeringDirectoryMaxEntries = 1000;
const Duration _harnessSteeringDirectoryScanTimeout = Duration(seconds: 3);
const Duration _harnessSteeringEntryStatTimeout = Duration(milliseconds: 250);

class _HeSteeringAssetsDialog extends StatefulWidget {
  const _HeSteeringAssetsDialog({required this.steeringRoot});

  final String steeringRoot;

  @override
  State<_HeSteeringAssetsDialog> createState() =>
      _HeSteeringAssetsDialogState();
}

class _HeSteeringAssetsDialogState extends State<_HeSteeringAssetsDialog> {
  /// The path segments relative to steeringRoot. Empty = root.
  late List<String> _pathSegments;

  /// Cached entries for the current directory.
  List<_HeSteeringEntry> _entries = const [];

  /// Whether we're still scanning.
  bool _loading = true;
  int _scanGeneration = 0;

  @override
  void initState() {
    super.initState();
    _pathSegments = [];
    unawaited(_scanDirectory());
  }

  String get _currentAbsolutePath => _pathSegments.isEmpty
      ? widget.steeringRoot
      : p.joinAll([widget.steeringRoot, ..._pathSegments]);

  void _navigateTo(List<String> segments) {
    setState(() {
      _pathSegments = List.of(segments);
      _loading = true;
    });
    unawaited(_scanDirectory());
  }

  Future<void> _scanDirectory() async {
    final generation = ++_scanGeneration;
    final directoryPath = _currentAbsolutePath;
    final dir = Directory(directoryPath);
    final entries = <_HeSteeringEntry>[];
    final stopwatch = Stopwatch()..start();
    try {
      final listing = await listDirectoryBounded(
        dir,
        maxEntries: _harnessSteeringDirectoryMaxEntries,
        totalTimeout: _harnessSteeringDirectoryScanTimeout,
      );
      for (final entity in listing.entries) {
        if (!mounted || generation != _scanGeneration) break;
        final name = p.basename(entity.path);
        if (name.startsWith('.')) continue;
        final isDir = entity is Directory;
        FileStat? stat;
        final remaining =
            _harnessSteeringDirectoryScanTimeout - stopwatch.elapsed;
        if (remaining > Duration.zero) {
          final timeout = remaining < _harnessSteeringEntryStatTimeout
              ? remaining
              : _harnessSteeringEntryStatTimeout;
          try {
            stat = await entity.stat().timeout(timeout);
          } on TimeoutException {
            stat = null;
          } catch (error, stack) {
            silentLog('harness_steering', '读取目录条目元数据', error, stack);
          }
        }
        entries.add(
          _HeSteeringEntry(
            name: name,
            isDirectory: isDir,
            absolutePath: entity.path,
            size: stat?.size,
            modified: stat?.modified,
          ),
        );
      }
    } on FileSystemException catch (error, stack) {
      silentLog('harness_steering', '扫描目录', error, stack);
    } finally {
      stopwatch.stop();
    }
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.name.compareTo(b.name);
    });
    if (!mounted || generation != _scanGeneration) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  void _onEntryTap(_HeSteeringEntry entry) {
    if (entry.isDirectory) {
      _navigateTo([..._pathSegments, entry.name]);
    } else {
      _openFileEditor(entry);
    }
  }

  void _openFileEditor(_HeSteeringEntry entry) {
    showAnimatedDialog<void>(
      context: context,
      builder: (_) => _HeSteeringFileEditorDialog(filePath: entry.absolutePath),
    ).then((_) {
      // Refresh in case file was modified.
      _scanDirectory();
    });
  }

  String? _directoryDescription(BuildContext context, String name) {
    return switch (name) {
      'meta' => openHandLocalizedText(
        context,
        zh: '元信息 - 架构、约定、配置',
        zhHant: '元資訊 - 架構、慣例、設定',
        en: 'Meta - architecture, conventions, config',
        fr: 'Métadonnées - architecture, conventions, configuration',
        de: 'Meta - Architektur, Konventionen, Konfiguration',
        ja: 'メタ - アーキテクチャ、規約、設定',
      ),
      'plan' => openHandLocalizedText(
        context,
        zh: '规划 - 阶段计划文件',
        zhHant: '規劃 - 階段計畫檔案',
        en: 'Plans - phase planning files',
        fr: 'Plans - fichiers de planification des phases',
        de: 'Pläne - Phasenplanungsdateien',
        ja: '計画 - フェーズ計画ファイル',
      ),
      'feedback' => openHandLocalizedText(
        context,
        zh: '反馈 - 验收与审查反馈',
        zhHant: '回饋 - 驗收與審查回饋',
        en: 'Feedback - review and acceptance feedback',
        fr: 'Retours - validation et revue',
        de: 'Feedback - Abnahme und Prüfung',
        ja: 'フィードバック - 受け入れとレビュー',
      ),
      'handoff' => openHandLocalizedText(
        context,
        zh: '交接 - 阶段间交接文件',
        zhHant: '交接 - 階段間交接檔案',
        en: 'Handoff - inter-phase handoff files',
        fr: 'Transfert - fichiers entre phases',
        de: 'Übergabe - Dateien zwischen Phasen',
        ja: '引き継ぎ - フェーズ間ファイル',
      ),
      'lesson' => openHandLocalizedText(
        context,
        zh: '记忆 - 经验教训文件',
        zhHant: '記憶 - 經驗教訓檔案',
        en: 'Lessons - lessons learned files',
        fr: 'Leçons - retours d’expérience',
        de: 'Lessons - Erfahrungsdateien',
        ja: '学び - 教訓ファイル',
      ),
      'log' => openHandLocalizedText(
        context,
        zh: '日志 - 运行日志',
        zhHant: '日誌 - 執行日誌',
        en: 'Logs - runtime log files',
        fr: 'Journaux - fichiers d’exécution',
        de: 'Logs - Laufzeitprotokolle',
        ja: 'ログ - 実行ログ',
      ),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return buildOpenHandResponsiveDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthWide,
      maxHeight: double.infinity,
      maxHeightFraction: 0.80,
      safeAreaMinimum: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Title row ──
            Row(
              children: [
                Icon(
                  Icons.folder_special_rounded,
                  color: colorScheme.primary,
                  size: 26,
                ),
                kOpenHandHGap10,
                Expanded(
                  child: Text(
                    openHandLocalizedText(
                      context,
                      zh: '资产文件浏览器',
                      zhHant: '資產檔案瀏覽器',
                      en: 'Steering Assets Browser',
                      fr: 'Explorateur des ressources de pilotage',
                      de: 'Steuerungsdatei-Browser',
                      ja: 'ステアリング資産ブラウザー',
                    ),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            kOpenHandGap12,

            // ── Breadcrumb ──
            _HeBreadcrumb(segments: _pathSegments, onNavigate: _navigateTo),
            kOpenHandGap8,
            const Divider(height: 1),

            // ── File list ──
            Expanded(
              child: AnimatedSwitcher(
                duration: openHandMotionDuration(context, kOpenHandMotion220),
                switchInCurve: kOpenHandSwitchInCurve,
                switchOutCurve: kOpenHandSwitchOutCurve,
                child: _loading
                    ? const Center(
                        key: ValueKey<String>('loading'),
                        child: CircularProgressIndicator(),
                      )
                    : _entries.isEmpty
                    ? OpenHandInlineEmptyState(
                        key: const ValueKey<String>('empty'),
                        message: openHandLocalizedText(
                          context,
                          zh: '此目录为空',
                          zhHant: '此目錄為空',
                          en: 'This directory is empty',
                          fr: 'Ce dossier est vide',
                          de: 'Dieser Ordner ist leer',
                          ja: 'このディレクトリは空です',
                        ),
                      )
                    : ListView.separated(
                        key: ValueKey<String>(
                          'list-${_pathSegments.join('/')}',
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _entries.length,
                        separatorBuilder: (_, _) => kOpenHandGap2,
                        itemBuilder: (ctx, i) {
                          final entry = _entries[i];
                          return _HeSteeringEntryTile(
                            entry: entry,
                            description:
                                entry.isDirectory && _pathSegments.isEmpty
                                ? _directoryDescription(context, entry.name)
                                : null,
                            onTap: () => _onEntryTap(entry),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Entry model ──

class _HeSteeringEntry {
  const _HeSteeringEntry({
    required this.name,
    required this.isDirectory,
    required this.absolutePath,
    this.size,
    this.modified,
  });

  final String name;
  final bool isDirectory;
  final String absolutePath;
  final int? size;
  final DateTime? modified;
}

// ── Breadcrumb ──

class _HeBreadcrumb extends StatelessWidget {
  const _HeBreadcrumb({required this.segments, required this.onNavigate});

  final List<String> segments;
  final void Function(List<String>) onNavigate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final items = <Widget>[
      _breadcrumbChip(
        context,
        label: 'steering',
        icon: Icons.home_rounded,
        onTap: () => onNavigate([]),
        isLast: segments.isEmpty,
      ),
    ];
    for (var i = 0; i < segments.length; i++) {
      items.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ),
      );
      final isLast = i == segments.length - 1;
      items.add(
        _breadcrumbChip(
          context,
          label: segments[i],
          icon: isLast ? Icons.folder_open_rounded : Icons.folder_rounded,
          onTap: isLast ? null : () => onNavigate(segments.sublist(0, i + 1)),
          isLast: isLast,
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: items),
    );
  }

  Widget _breadcrumbChip(
    BuildContext context, {
    required String label,
    required IconData icon,
    VoidCallback? onTap,
    bool isLast = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: isLast
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHighest,
      borderRadius: _br8,
      child: InkWell(
        onTap: onTap,
        borderRadius: _br8,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isLast
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
              kOpenHandHGap4,
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: isLast ? FontWeight.w700 : FontWeight.w500,
                  color: isLast
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Entry tile ──

class _HeSteeringEntryTile extends StatelessWidget {
  const _HeSteeringEntryTile({
    required this.entry,
    this.description,
    required this.onTap,
  });

  final _HeSteeringEntry entry;
  final String? description;
  final VoidCallback onTap;

  IconData get _icon {
    if (entry.isDirectory) return Icons.folder_rounded;
    final ext = p.extension(entry.name).toLowerCase();
    return switch (ext) {
      '.md' => Icons.description_rounded,
      '.json' => Icons.data_object_rounded,
      '.log' => Icons.receipt_long_rounded,
      '.yaml' || '.yml' => Icons.settings_rounded,
      _ => Icons.insert_drive_file_rounded,
    };
  }

  Color _iconColor(ColorScheme cs) {
    if (entry.isDirectory) return cs.primary;
    final ext = p.extension(entry.name).toLowerCase();
    return switch (ext) {
      '.md' => cs.tertiary,
      '.json' => cs.secondary,
      '.log' => cs.onSurfaceVariant,
      _ => cs.onSurfaceVariant,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: _br10,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(_icon, size: 24, color: _iconColor(colorScheme)),
              kOpenHandHGap12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (description != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          description!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (!entry.isDirectory && entry.size != null) ...[
                kOpenHandHGap8,
                Text(
                  formatByteSize(entry.size!),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (entry.modified != null) ...[
                kOpenHandHGap12,
                Text(
                  formatYearMonthDayHm(entry.modified!),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              kOpenHandHGap4,
              Icon(
                entry.isDirectory
                    ? Icons.chevron_right_rounded
                    : Icons.open_in_new_rounded,
                size: 18,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// _HeSteeringFileEditorDialog — Markdown editor with live preview
class _HeSteeringFileEditorDialog extends StatefulWidget {
  const _HeSteeringFileEditorDialog({required this.filePath});

  final String filePath;

  @override
  State<_HeSteeringFileEditorDialog> createState() =>
      _HeSteeringFileEditorDialogState();
}

class _HeSteeringFileEditorDialogState
    extends State<_HeSteeringFileEditorDialog> {
  late final TextEditingController _controller;
  late final FocusNode _editorFocusNode;
  bool _loading = true;
  bool _dirty = false;
  bool _saving = false;
  String? _error;
  bool _showPreview = true;

  /// The text as last saved (or as loaded). Used to detect real changes
  /// vs cursor-only movements (which also fire the controller listener).
  String _savedText = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _editorFocusNode = FocusNode();
    _loadFile();
  }

  @override
  void dispose() {
    _controller.dispose();
    _editorFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadFile() async {
    try {
      final content = await readBoundedFileString(
        File(widget.filePath),
        maxBytes: _harnessSteeringFileMaxBytes,
      );
      if (!mounted) return;
      setState(() {
        _controller.text = content;
        _savedText = content;
        _loading = false;
      });
      _controller.addListener(_onEdit);
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();
      final isMissing =
          raw.startsWith('PathNotFoundException') ||
          raw.contains('No such file or directory');
      final isFs = raw.startsWith('FileSystemException');
      String friendly;
      if (isMissing) {
        friendly = openHandLocalizedText(
          context,
          zh: '文件已不存在或路径已被移动。\n原始错误：$raw',
          zhHant: '檔案已不存在或路徑已移動。\n原始錯誤：$raw',
          en: 'File no longer exists or has been moved.\nRaw: $raw',
          fr: 'Le fichier n’existe plus ou a été déplacé.\nBrut : $raw',
          de: 'Die Datei existiert nicht mehr oder wurde verschoben.\nRaw: $raw',
          ja: 'ファイルが存在しないか移動されています。\nRaw: $raw',
        );
      } else if (isFs) {
        friendly = openHandLocalizedText(
          context,
          zh: '读取文件失败 (可能是权限不足 / 编码异常 / 磁盘错误)。\n原始错误：$raw',
          zhHant: '讀取檔案失敗 (可能是權限不足 / 編碼異常 / 磁碟錯誤)。\n原始錯誤：$raw',
          en: 'Failed to read file (permission, encoding, or disk error).\nRaw: $raw',
          fr: 'Impossible de lire le fichier (permission, encodage ou disque).\nBrut : $raw',
          de: 'Datei konnte nicht gelesen werden (Berechtigung, Kodierung oder Datenträger).\nRaw: $raw',
          ja: 'ファイルを読み取れませんでした（権限、文字コード、ディスクエラーの可能性）。\nRaw: $raw',
        );
      } else {
        friendly = raw;
      }
      setState(() {
        _error = friendly;
        _loading = false;
      });
    }
  }

  void _onEdit() {
    // Fire only when the text itself has changed, not on mere cursor movement.
    final nowDirty = _controller.text != _savedText;
    if (nowDirty != _dirty) setState(() => _dirty = nowDirty);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await writeFileAtomically(File(widget.filePath), _controller.text);
      if (!mounted) return;
      setState(() {
        _savedText = _controller.text;
        _dirty = false;
        _saving = false;
      });
      showOpenHandSuccessSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '文件已保存',
          zhHant: '檔案已儲存',
          en: 'File saved',
          fr: 'Fichier enregistré',
          de: 'Datei gespeichert',
          ja: 'ファイルを保存しました',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showFriendlyErrorSnackBar(
        context,
        message: '$e',
        fallback: openHandSaveFailedLabel(context),
      );
    }
  }

  Future<bool> _confirmDiscard() {
    if (!_dirty) return Future<bool>.value(true);
    return showOpenHandConfirmDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '放弃更改？',
        zhHant: '放棄變更？',
        en: 'Discard changes?',
        fr: 'Ignorer les modifications ?',
        de: 'Änderungen verwerfen?',
        ja: '変更を破棄しますか？',
      ),
      message: openHandLocalizedText(
        context,
        zh: '你有未保存的更改，确定要放弃吗？',
        zhHant: '你有未儲存的變更，確定要放棄嗎？',
        en: 'You have unsaved changes. Discard them?',
        fr: 'Vous avez des modifications non enregistrées. Les ignorer ?',
        de: 'Es gibt ungespeicherte Änderungen. Verwerfen?',
        ja: '未保存の変更があります。破棄しますか？',
      ),
      cancelLabel: openHandCancelLabel(context),
      confirmLabel: openHandLocalizedText(
        context,
        zh: '放弃',
        zhHant: '放棄',
        en: 'Discard',
        fr: 'Ignorer',
        de: 'Verwerfen',
        ja: '破棄',
      ),
      destructive: true,
    );
  }

  // ── Format helpers ─────────────────────────────────────────────────────────

  void _refocus() => _editorFocusNode.requestFocus();

  /// Wraps current selection (or cursor position) with [prefix]/[suffix].
  void _wrapInline(String prefix, [String? suffix]) {
    suffix ??= prefix;
    final v = _controller.value;
    final text = v.text;
    final sel = v.selection;
    if (!sel.isValid) return;

    final String newText;
    final TextSelection newSel;
    if (sel.isCollapsed) {
      final before = text.substring(0, sel.start);
      final after = text.substring(sel.start);
      newText = '$before$prefix$suffix$after';
      newSel = TextSelection.collapsed(offset: sel.start + prefix.length);
    } else {
      final before = text.substring(0, sel.start);
      final selected = text.substring(sel.start, sel.end);
      final after = text.substring(sel.end);
      newText = '$before$prefix$selected$suffix$after';
      newSel = TextSelection(
        baseOffset: sel.start,
        extentOffset:
            sel.start + prefix.length + selected.length + suffix.length,
      );
    }
    _controller.value = v.copyWith(text: newText, selection: newSel);
    _refocus();
  }

  /// Prefixes every line covered by the selection with [prefix].
  void _prefixLines(String prefix) {
    final v = _controller.value;
    final text = v.text;
    final sel = v.selection;
    if (!sel.isValid) return;

    final lineStart =
        text.lastIndexOf('\n', sel.start > 0 ? sel.start - 1 : 0) + 1;
    var lineEnd = text.indexOf('\n', sel.end);
    if (lineEnd == -1) lineEnd = text.length;

    final block = text.substring(lineStart, lineEnd);
    final prefixed = block.split('\n').map((l) => '$prefix$l').join('\n');

    _controller.value = v.copyWith(
      text:
          '${text.substring(0, lineStart)}$prefixed${text.substring(lineEnd)}',
      selection: TextSelection(
        baseOffset: lineStart,
        extentOffset: lineStart + prefixed.length,
      ),
    );
    _refocus();
  }

  /// Inserts [snippet] at cursor, optionally placing cursor at [cursorOffset].
  void _insertSnippet(String snippet, {int? cursorOffset}) {
    final v = _controller.value;
    final text = v.text;
    final sel = v.selection;
    final offset = sel.isValid ? sel.start : text.length;
    final end = sel.isValid && !sel.isCollapsed ? sel.end : offset;
    final newText =
        '${text.substring(0, offset)}$snippet${text.substring(end)}';
    _controller.value = v.copyWith(
      text: newText,
      selection: TextSelection.collapsed(
        offset: offset + (cursorOffset ?? snippet.length),
      ),
    );
    _refocus();
  }

  // ── Format actions ─────────────────────────────────────────────────────────

  void _applyHeading(int level) => _prefixLines('${'#' * level} ');
  void _applyBold() => _wrapInline('**');
  void _applyItalic() => _wrapInline('*');
  void _applyStrikethrough() => _wrapInline('~~');
  void _applyInlineCode() => _wrapInline('`');
  void _applyBlockquote() => _prefixLines('> ');
  void _applyBulletList() => _prefixLines('- ');

  void _applyCodeBlock() => _insertSnippet('```\n\n```\n', cursorOffset: 4);

  void _applyOrderedList() {
    final v = _controller.value;
    final text = v.text;
    final sel = v.selection;
    if (!sel.isValid) return;
    final lineStart =
        text.lastIndexOf('\n', sel.start > 0 ? sel.start - 1 : 0) + 1;
    var lineEnd = text.indexOf('\n', sel.end);
    if (lineEnd == -1) lineEnd = text.length;
    final block = text.substring(lineStart, lineEnd);
    var i = 1;
    final prefixed = block.split('\n').map((l) => '${i++}. $l').join('\n');
    _controller.value = v.copyWith(
      text:
          '${text.substring(0, lineStart)}$prefixed${text.substring(lineEnd)}',
      selection: TextSelection(
        baseOffset: lineStart,
        extentOffset: lineStart + prefixed.length,
      ),
    );
    _refocus();
  }

  void _insertLink() {
    final v = _controller.value;
    final text = v.text;
    final sel = v.selection;
    if (sel.isValid && !sel.isCollapsed) {
      // Wrap selection as link text; select "url" placeholder for easy editing.
      final selected = text.substring(sel.start, sel.end);
      final snippet = '[$selected](url)';
      final newText =
          '${text.substring(0, sel.start)}$snippet${text.substring(sel.end)}';
      // "url" is at sel.start + 1 + selected.length + 2 = sel.start + selected.length + 3
      final urlStart = sel.start + selected.length + 3;
      _controller.value = v.copyWith(
        text: newText,
        selection: TextSelection(
          baseOffset: urlStart,
          extentOffset: urlStart + 3,
        ),
      );
    } else {
      // No selection: insert [](url) with cursor between brackets.
      final offset = sel.isValid ? sel.start : text.length;
      _controller.value = v.copyWith(
        text: '${text.substring(0, offset)}[](url)${text.substring(offset)}',
        selection: TextSelection.collapsed(offset: offset + 1),
      );
    }
    _refocus();
  }

  void _insertHR() => _insertSnippet('\n\n---\n\n');

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fileName = p.basename(widget.filePath);
    final isMarkdown = fileName.endsWith('.md');

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard()) {
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: buildOpenHandResponsiveDialogShell(
        context: context,
        maxWidth: kOpenHandDialogWidthPanel,
        maxHeight: double.infinity,
        maxHeightFraction: 0.88,
        safeAreaMinimum: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Title row ──
              Row(
                children: [
                  Icon(
                    Icons.edit_document,
                    size: 22,
                    color: colorScheme.primary,
                  ),
                  kOpenHandHGap8,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fileName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          p.dirname(widget.filePath),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (isMarkdown)
                    IconButton(
                      tooltip: _showPreview
                          ? openHandLocalizedText(
                              context,
                              zh: '隐藏预览',
                              zhHant: '隱藏預覽',
                              en: 'Hide preview',
                              fr: 'Masquer l’aperçu',
                              de: 'Vorschau ausblenden',
                              ja: 'プレビューを非表示',
                            )
                          : openHandLocalizedText(
                              context,
                              zh: '显示预览',
                              zhHant: '顯示預覽',
                              en: 'Show preview',
                              fr: 'Afficher l’aperçu',
                              de: 'Vorschau anzeigen',
                              ja: 'プレビューを表示',
                            ),
                      onPressed: () =>
                          setState(() => _showPreview = !_showPreview),
                      icon: Icon(
                        _showPreview
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        size: 20,
                      ),
                    ),
                  kOpenHandHGap4,
                  IconButton(
                    onPressed: () async {
                      if (await _confirmDiscard()) {
                        if (context.mounted) Navigator.of(context).pop();
                      }
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              kOpenHandGap10,
              const Divider(height: 1),
              kOpenHandGap6,

              // ── Markdown toolbar ──
              if (isMarkdown && !_loading && _error == null) ...[
                _buildToolbar(context, theme, colorScheme),
                kOpenHandGap6,
              ],

              // ── Body ──
              Expanded(
                child: AnimatedSwitcher(
                  duration: openHandMotionDuration(context, kOpenHandMotion220),
                  switchInCurve: kOpenHandSwitchInCurve,
                  switchOutCurve: kOpenHandSwitchOutCurve,
                  child: _loading
                      ? const Center(
                          key: ValueKey<String>('loading'),
                          child: CircularProgressIndicator(),
                        )
                      : _error != null
                      ? Center(
                          key: const ValueKey<String>('error'),
                          child: SelectableText(
                            _error!,
                            style: TextStyle(color: colorScheme.error),
                          ),
                        )
                      : isMarkdown && _showPreview
                      ? Row(
                          key: const ValueKey<String>('split'),
                          children: [
                            Expanded(
                              child: _buildEditorPane(
                                context,
                                theme,
                                colorScheme,
                              ),
                            ),
                            kOpenHandHGap10,
                            VerticalDivider(
                              width: 1,
                              color: colorScheme.outlineVariant,
                            ),
                            kOpenHandHGap10,
                            Expanded(
                              child: _buildPreviewPane(
                                context,
                                theme,
                                colorScheme,
                              ),
                            ),
                          ],
                        )
                      : KeyedSubtree(
                          key: const ValueKey<String>('editor'),
                          child: _buildEditorPane(context, theme, colorScheme),
                        ),
                ),
              ),
              kOpenHandGap8,
              const Divider(height: 1),
              kOpenHandGap10,

              // ── Action row ──
              Row(
                children: [
                  if (!_loading && _error == null)
                    ListenableBuilder(
                      listenable: _controller,
                      builder: (_, _) {
                        final t = _controller.text;
                        final words = countWhitespaceSeparatedWords(t);
                        return Text(
                          openHandLocalizedText(
                            context,
                            zh: '${t.length} 字符  $words 词',
                            zhHant: '${t.length} 字元  $words 詞',
                            en: '${t.length} chars  $words words',
                            fr: '${t.length} car.  $words mots',
                            de: '${t.length} Zeichen  $words Wörter',
                            ja: '${t.length} 文字  $words 語',
                          ),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        );
                      },
                    ),
                  const Spacer(),
                  if (_dirty)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text(
                        openHandLocalizedText(
                          context,
                          zh: '有未保存的更改',
                          zhHant: '有未儲存的變更',
                          en: 'Unsaved changes',
                          fr: 'Modifications non enregistrées',
                          de: 'Ungespeicherte Änderungen',
                          ja: '未保存の変更があります',
                        ),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  OpenHandDialogActionButton.secondary(
                    onPressed: () async {
                      if (await _confirmDiscard()) {
                        if (context.mounted) Navigator.of(context).pop();
                      }
                    },
                    label: openHandCloseLabel(context),
                  ),
                  kOpenHandHGap8,
                  OpenHandDialogActionButton.primary(
                    onPressed: _dirty && !_saving ? _save : null,
                    icon: Icons.save_rounded,
                    busy: _saving,
                    label: openHandSaveLabel(context),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final sep = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: SizedBox(
        height: 18,
        child: VerticalDivider(width: 1, color: colorScheme.outlineVariant),
      ),
    );
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: _br8,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _MdToolbarBtn(
              label: 'H₁',
              tooltip: openHandHeading1Label(context),
              onTap: () => _applyHeading(1),
            ),
            _MdToolbarBtn(
              label: 'H₂',
              tooltip: openHandHeading2Label(context),
              onTap: () => _applyHeading(2),
            ),
            _MdToolbarBtn(
              label: 'H₃',
              tooltip: openHandHeading3Label(context),
              onTap: () => _applyHeading(3),
            ),
            sep,
            _MdToolbarBtn(
              icon: Icons.format_bold,
              tooltip: openHandLocalizedText(
                context,
                zh: '粗体 **text**',
                zhHant: '粗體 **text**',
                en: 'Bold **text**',
                fr: 'Gras **text**',
                de: 'Fett **text**',
                ja: '太字 **text**',
              ),
              onTap: _applyBold,
            ),
            _MdToolbarBtn(
              icon: Icons.format_italic,
              tooltip: openHandLocalizedText(
                context,
                zh: '斜体 *text*',
                zhHant: '斜體 *text*',
                en: 'Italic *text*',
                fr: 'Italique *text*',
                de: 'Kursiv *text*',
                ja: '斜体 *text*',
              ),
              onTap: _applyItalic,
            ),
            _MdToolbarBtn(
              icon: Icons.format_strikethrough,
              tooltip: openHandLocalizedText(
                context,
                zh: '删除线 ~~text~~',
                zhHant: '刪除線 ~~text~~',
                en: 'Strikethrough ~~text~~',
                fr: 'Barré ~~text~~',
                de: 'Durchgestrichen ~~text~~',
                ja: '取り消し線 ~~text~~',
              ),
              onTap: _applyStrikethrough,
            ),
            _MdToolbarBtn(
              icon: Icons.code,
              tooltip: openHandLocalizedText(
                context,
                zh: '内联代码 `code`',
                zhHant: '行內程式碼 `code`',
                en: 'Inline code `code`',
                fr: 'Code inline `code`',
                de: 'Inline-Code `code`',
                ja: 'インラインコード `code`',
              ),
              onTap: _applyInlineCode,
            ),
            sep,
            // Block
            _MdToolbarBtn(
              icon: Icons.data_object_rounded,
              tooltip: openHandCodeBlockLabel(context),
              onTap: _applyCodeBlock,
            ),
            _MdToolbarBtn(
              icon: Icons.format_quote_rounded,
              tooltip: openHandLocalizedText(
                context,
                zh: '引用块 > text',
                zhHant: '引用區塊 > text',
                en: 'Blockquote > text',
                fr: 'Citation > text',
                de: 'Zitatblock > text',
                ja: '引用ブロック > text',
              ),
              onTap: _applyBlockquote,
            ),
            sep,
            // Lists
            _MdToolbarBtn(
              icon: Icons.format_list_bulleted,
              tooltip: openHandLocalizedText(
                context,
                zh: '无序列表 - item',
                zhHant: '無序列表 - item',
                en: 'Bullet list - item',
                fr: 'Liste à puces - item',
                de: 'Aufzählung - item',
                ja: '箇条書き - item',
              ),
              onTap: _applyBulletList,
            ),
            _MdToolbarBtn(
              icon: Icons.format_list_numbered,
              tooltip: openHandLocalizedText(
                context,
                zh: '有序列表 1. item',
                zhHant: '有序列表 1. item',
                en: 'Ordered list 1. item',
                fr: 'Liste numérotée 1. item',
                de: 'Nummerierte Liste 1. item',
                ja: '番号付きリスト 1. item',
              ),
              onTap: _applyOrderedList,
            ),
            sep,
            // Misc
            _MdToolbarBtn(
              icon: Icons.link_rounded,
              tooltip: openHandLocalizedText(
                context,
                zh: '插入链接 [text](url)',
                zhHant: '插入連結 [text](url)',
                en: 'Insert link [text](url)',
                fr: 'Insérer un lien [text](url)',
                de: 'Link einfügen [text](url)',
                ja: 'リンクを挿入 [text](url)',
              ),
              onTap: _insertLink,
            ),
            _MdToolbarBtn(
              icon: Icons.horizontal_rule_rounded,
              tooltip: openHandLocalizedText(
                context,
                zh: '分隔线 ---',
                zhHant: '分隔線 ---',
                en: 'Horizontal rule ---',
                fr: 'Séparateur ---',
                de: 'Trennlinie ---',
                ja: '水平線 ---',
              ),
              onTap: _insertHR,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditorPane(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    // Clip.antiAliasWithSaveLayer composites to a separate layer before
    // blending, fully eliminating the white-corner bleed that Clip.antiAlias
    // produces when a Dialog's white background shows through the rounded
    // edges during anti-aliasing.
    return Container(
      clipBehavior: Clip.antiAliasWithSaveLayer,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: _br10,
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: TextField(
        controller: _controller,
        focusNode: _editorFocusNode,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontFamily: kOpenHandMonospaceFontFamily,
          height: 1.55,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          // Transparent fill prevents InputDecorator from painting its own
          // opaque background on top of the Container's background colour.
          filled: true,
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.all(14),
          hintText: openHandLocalizedText(
            context,
            zh: '在此编辑文件内容…',
            zhHant: '在此編輯檔案內容…',
            en: 'Edit file content here…',
            fr: 'Modifiez le contenu du fichier ici…',
            de: 'Dateiinhalt hier bearbeiten…',
            ja: 'ここでファイル内容を編集…',
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewPane(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Container(
      clipBehavior: Clip.antiAliasWithSaveLayer,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: _br10,
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            color: colorScheme.surfaceContainerHigh,
            child: Text(
              openHandPreviewLabel(context),
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: ListenableBuilder(
                listenable: _controller,
                builder: (_, _) => _HeSafeMarkdownBody(
                  content: _controller.text,
                  theme: theme,
                  colorScheme: colorScheme,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// _MdToolbarBtn — compact toolbar button (icon or text label)
class _MdToolbarBtn extends StatelessWidget {
  const _MdToolbarBtn({
    this.icon,
    this.label,
    required this.tooltip,
    required this.onTap,
  }) : assert(icon != null || label != null);

  final IconData? icon;
  final String? label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Tooltip(
      message: tooltip,
      waitDuration: kOpenHandTooltipWait,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: _br6,
          child: SizedBox(
            width: 30,
            height: 30,
            child: Center(
              child: icon != null
                  ? Icon(icon, size: 17, color: colorScheme.onSurfaceVariant)
                  : Text(
                      label!,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
