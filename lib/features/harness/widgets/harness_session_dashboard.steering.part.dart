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
  late List<String> _pathSegments;
  List<_HeSteeringEntry> _entries = const [];
  bool _loading = true;
  bool _directoryMissing = false;
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
    var directoryMissing = false;
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
    } on PathNotFoundException {
      directoryMissing = true;
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
      _directoryMissing = directoryMissing;
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

  Color _steeringFolderAccent(ColorScheme colorScheme, String name) {
    return switch (name) {
      'meta' => OpenHandStatusColors.info,
      'plan' => colorScheme.primary,
      'feedback' => OpenHandStatusColors.warning,
      'handoff' => colorScheme.tertiary,
      'lesson' => OpenHandStatusColors.success,
      'log' => colorScheme.secondary,
      _ => colorScheme.primary,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final emptyAccent = _directoryMissing
        ? OpenHandStatusColors.warning
        : OpenHandStatusColors.info;
    return OpenHandEditorDialogScaffold(
      title: openHandLocalizedText(
        context,
        zh: '资产文件浏览器',
        zhHant: '資產檔案瀏覽器',
        en: 'Steering Assets Browser',
        fr: 'Explorateur des ressources de pilotage',
        de: 'Steuerungsdatei-Browser',
        ja: 'ステアリング資産ブラウザー',
      ),
      subtitle: _currentAbsolutePath,
      icon: Icons.folder_special_rounded,
      iconColor: colorScheme.primary,
      scrollBody: false,
      actions: [
        OpenHandDialogActionButton.primary(
          onPressed: () => Navigator.of(context).pop(),
          label: openHandCloseLabel(context),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OpenHandTintedPanel(
            accent: colorScheme.primary,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: _HeBreadcrumb(
              segments: _pathSegments,
              onNavigate: _navigateTo,
            ),
          ),
          kOpenHandGap12,
          Expanded(
            child: OpenHandContentStateSwitcher(
              animateSize: false,
              alignment: Alignment.center,
              stateKey: _loading
                  ? 'loading'
                  : _entries.isEmpty
                  ? (_directoryMissing ? 'missing' : 'empty')
                  : 'list-${_pathSegments.join('/')}',
              child: _loading
                  ? OpenHandTintedPanel(
                      accent: colorScheme.primary,
                      child: SizedBox(
                        height: 180,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.8,
                                  color: colorScheme.primary,
                                ),
                              ),
                              kOpenHandGap14,
                              Text(
                                openHandLocalizedText(
                                  context,
                                  zh: '正在扫描资产目录…',
                                  zhHant: '正在掃描資產目錄…',
                                  en: 'Scanning assets…',
                                  fr: 'Analyse des ressources…',
                                  de: 'Ressourcen werden gelesen…',
                                  ja: 'アセットを読み込んでいます…',
                                ),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : _entries.isEmpty
                  ? Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: OpenHandTintedPanel(
                          accent: emptyAccent,
                          icon: _directoryMissing
                              ? Icons.create_new_folder_outlined
                              : Icons.folder_off_rounded,
                          title: openHandLocalizedText(
                            context,
                            zh: _directoryMissing ? '尚未生成资产目录' : '此目录为空',
                            zhHant: _directoryMissing ? '尚未產生資產目錄' : '此目錄為空',
                            en: _directoryMissing
                                ? 'Assets folder not generated'
                                : 'This directory is empty',
                            fr: _directoryMissing
                                ? 'Dossier de ressources absent'
                                : 'Ce dossier est vide',
                            de: _directoryMissing
                                ? 'Ressourcenordner fehlt'
                                : 'Dieser Ordner ist leer',
                            ja: _directoryMissing
                                ? 'アセットフォルダー未生成'
                                : 'このディレクトリは空です',
                          ),
                          child: Text(
                            openHandLocalizedText(
                              context,
                              zh: _directoryMissing
                                  ? '会话开始后会在 steering 目录写入阶段资产。当前路径还不存在。'
                                  : '当前路径下没有可见文件。点按上方面包屑可返回上级目录。',
                              zhHant: _directoryMissing
                                  ? '會話開始後會在 steering 目錄寫入階段資產。目前路徑尚不存在。'
                                  : '目前路徑下沒有可見檔案。點按上方麵包屑可返回上層目錄。',
                              en: _directoryMissing
                                  ? 'Phase assets will be written under steering after the session starts. This path does not exist yet.'
                                  : 'No visible files in this path. Use the breadcrumb to go up.',
                              fr: _directoryMissing
                                  ? 'Les ressources de phase seront écrites dans steering après le démarrage. Ce chemin n’existe pas encore.'
                                  : 'Aucun fichier visible. Utilisez le fil d’Ariane pour remonter.',
                              de: _directoryMissing
                                  ? 'Phasenressourcen werden nach Sitzungsstart unter steering geschrieben. Dieser Pfad existiert noch nicht.'
                                  : 'Keine sichtbaren Dateien. Über die Pfadleiste eine Ebene höher gehen.',
                              ja: _directoryMissing
                                  ? 'セッション開始後に steering 配下へ成果物が書き込まれます。このパスはまだありません。'
                                  : 'このパスに表示できるファイルはありません。パンくずで上の階層へ戻れます。',
                            ),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.45,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: _entries.length,
                      separatorBuilder: (_, _) => kOpenHandGap8,
                      itemBuilder: (ctx, i) {
                        final entry = _entries[i];
                        return _HeSteeringEntryTile(
                          entry: entry,
                          description:
                              entry.isDirectory && _pathSegments.isEmpty
                              ? _directoryDescription(context, entry.name)
                              : null,
                          accent: entry.isDirectory
                              ? _steeringFolderAccent(colorScheme, entry.name)
                              : _HeSteeringEntryTile.fileAccent(
                                  colorScheme,
                                  entry.name,
                                ),
                          onTap: () => _onEntryTap(entry),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

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
    final colorScheme = Theme.of(context).colorScheme;
    final tone = isLast ? colorScheme.primary : colorScheme.secondary;
    return OhPill(
      icon: icon,
      label: label,
      onTap: onTap,
      foregroundColor: tone,
    );
  }
}

// ── Entry tile ──

class _HeSteeringEntryTile extends StatelessWidget {
  const _HeSteeringEntryTile({
    required this.entry,
    required this.accent,
    this.description,
    required this.onTap,
  });

  final _HeSteeringEntry entry;
  final Color accent;
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

  static Color fileAccent(ColorScheme cs, String name) {
    final ext = p.extension(name).toLowerCase();
    return switch (ext) {
      '.md' => OpenHandStatusColors.success,
      '.json' => cs.secondary,
      '.log' => OpenHandStatusColors.warning,
      '.yaml' || '.yml' => cs.tertiary,
      _ => cs.primary,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return HoverLift(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: kOpenHandBorderRadius16,
          child: OpenHandTintedPanel(
            accent: accent,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.18),
                    borderRadius: kOpenHandBorderRadius10,
                  ),
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Center(child: Icon(_icon, size: 18, color: accent)),
                  ),
                ),
                kOpenHandHGap12,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.name,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
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
                  OhPill(
                    icon: Icons.sd_storage_outlined,
                    label: formatByteSize(entry.size!),
                    foregroundColor: accent,
                  ),
                ],
                if (entry.modified != null) ...[
                  kOpenHandHGap8,
                  OhPill(
                    icon: Icons.schedule_rounded,
                    label: formatYearMonthDayHm(entry.modified!),
                    foregroundColor: colorScheme.onSurfaceVariant,
                  ),
                ],
                kOpenHandHGap4,
                Icon(
                  entry.isDirectory
                      ? Icons.chevron_right_rounded
                      : Icons.open_in_new_rounded,
                  size: 18,
                  color: accent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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

  /// 最近保存的正文，用于排除仅移动光标产生的控制器通知。
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

  void _refocus() => _editorFocusNode.requestFocus();

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
      final selected = text.substring(sel.start, sel.end);
      final snippet = '[$selected](url)';
      final newText =
          '${text.substring(0, sel.start)}$snippet${text.substring(sel.end)}';
      final urlStart = sel.start + selected.length + 3;
      _controller.value = v.copyWith(
        text: newText,
        selection: TextSelection(
          baseOffset: urlStart,
          extentOffset: urlStart + 3,
        ),
      );
    } else {
      final offset = sel.isValid ? sel.start : text.length;
      _controller.value = v.copyWith(
        text: '${text.substring(0, offset)}[](url)${text.substring(offset)}',
        selection: TextSelection.collapsed(offset: offset + 1),
      );
    }
    _refocus();
  }

  void _insertHR() => _insertSnippet('\n\n---\n\n');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fileName = p.basename(widget.filePath);
    final isMarkdown = fileName.endsWith('.md');

    return OpenHandEditorDialogScaffold(
      title: fileName,
      subtitle: p.dirname(widget.filePath),
      icon: Icons.edit_document,
      iconColor: _dirty ? colorScheme.error : colorScheme.primary,
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard()) {
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      scrollBody: false,
      maxWidth: kOpenHandDialogWidthPanel,
      maxHeight: kOpenHandDialogHeightFull,
      busy: _saving,
      headerActions: [
        if (!_loading && _error == null)
          ListenableBuilder(
            listenable: _controller,
            builder: (_, _) {
              final t = _controller.text;
              final words = countWhitespaceSeparatedWords(t);
              return OhPill(
                icon: Icons.text_fields_rounded,
                label: openHandLocalizedText(
                  context,
                  zh: '${t.length} 字符 · $words 词',
                  zhHant: '${t.length} 字元 · $words 詞',
                  en: '${t.length} chars · $words words',
                  fr: '${t.length} car. · $words mots',
                  de: '${t.length} Zeichen · $words Wörter',
                  ja: '${t.length} 文字 · $words 語',
                ),
                foregroundColor: colorScheme.tertiary,
              );
            },
          ),
        if (_dirty)
          OhPill(
            icon: Icons.edit_rounded,
            label: openHandLocalizedText(
              context,
              zh: '未保存',
              zhHant: '未儲存',
              en: 'Unsaved',
              fr: 'Non enregistré',
              de: 'Ungespeichert',
              ja: '未保存',
            ),
            foregroundColor: colorScheme.error,
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
            onPressed: () => setState(() => _showPreview = !_showPreview),
            icon: Icon(
              _showPreview
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              size: 20,
            ),
          ),
      ],
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () async {
            if (await _confirmDiscard()) {
              if (context.mounted) Navigator.of(context).pop();
            }
          },
          label: openHandCloseLabel(context),
        ),
        OpenHandDialogActionButton.primary(
          onPressed: _dirty && !_saving ? _save : null,
          icon: Icons.save_rounded,
          busy: _saving,
          label: openHandSaveLabel(context),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Markdown toolbar ──
          if (isMarkdown && !_loading && _error == null) ...[
            _buildToolbar(context, theme, colorScheme),
            kOpenHandGap6,
          ],

          // ── Body ──
          Expanded(
            child: OpenHandContentStateSwitcher(
              animateSize: false,
              alignment: Alignment.center,
              stateKey: _loading
                  ? 'loading'
                  : _error != null
                  ? 'error'
                  : isMarkdown && _showPreview
                  ? 'split'
                  : 'editor',
              child: _loading
                  ? OpenHandTintedPanel(
                      accent: colorScheme.primary,
                      child: const SizedBox(
                        height: 180,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    )
                  : _error != null
                  ? OpenHandTintedPanel(
                      accent: colorScheme.error,
                      icon: Icons.error_outline_rounded,
                      title: openHandLocalizedText(
                        context,
                        zh: '无法读取文件',
                        zhHant: '無法讀取檔案',
                        en: 'Unable to read file',
                        fr: 'Lecture impossible',
                        de: 'Datei nicht lesbar',
                        ja: 'ファイルを読めません',
                      ),
                      child: SelectableText(
                        _error!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface,
                          height: 1.4,
                        ),
                      ),
                    )
                  : isMarkdown && _showPreview
                  ? Row(
                      children: [
                        Expanded(
                          child: _buildEditorPane(context, theme, colorScheme),
                        ),
                        kOpenHandHGap10,
                        Expanded(
                          child: _buildPreviewPane(context, theme, colorScheme),
                        ),
                      ],
                    )
                  : _buildEditorPane(context, theme, colorScheme),
            ),
          ),
        ],
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
    return OpenHandTintedPanel(
      accent: colorScheme.primary,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: SizedBox(
        height: 38,
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
      ),
    );
  }

  Widget _buildEditorPane(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    // 使用独立合成层，避免弹窗白色背景从圆角边缘渗出。
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
          // 透明填充避免输入装饰覆盖容器背景。
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
