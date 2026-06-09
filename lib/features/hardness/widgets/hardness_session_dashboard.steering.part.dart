part of 'hardness_session_dashboard.dart';

class _HeSteeringAssetsDialog extends StatefulWidget {
  const _HeSteeringAssetsDialog({
    required this.steeringRoot,
    required this.isZh,
  });

  final String steeringRoot;
  final bool isZh;

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

  static const _directoryDescriptions = <String, (String, String)>{
    'meta': ('元信息 — 架构、约定、配置', 'Meta — architecture, conventions, config'),
    'plan': ('规划 — 阶段计划文件', 'Plans — phase planning files'),
    'feedback': ('反馈 — 验收与审查反馈', 'Feedback — review & acceptance feedback'),
    'handoff': ('交接 — 阶段间交接文件', 'Handoff — inter-phase handoff files'),
    'lesson': ('记忆 — 经验教训文件', 'Lessons — lessons learned files'),
    'log': ('日志 — 运行日志', 'Logs — runtime log files'),
  };

  @override
  void initState() {
    super.initState();
    _pathSegments = [];
    _scanDirectory();
  }

  String get _currentAbsolutePath => _pathSegments.isEmpty
      ? widget.steeringRoot
      : p.joinAll([widget.steeringRoot, ..._pathSegments]);

  void _navigateTo(List<String> segments) {
    setState(() {
      _pathSegments = List.of(segments);
      _loading = true;
    });
    _scanDirectory();
  }

  Future<void> _scanDirectory() async {
    final dir = Directory(_currentAbsolutePath);
    final entries = <_HeSteeringEntry>[];
    try {
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          final name = p.basename(entity.path);
          if (name.startsWith('.')) continue;
          final isDir = entity is Directory;
          FileStat? stat;
          try {
            stat = await entity.stat();
          } catch (error, stack) {
            silentLog(
              'hardness_steering',
              'stat directory entry',
              error,
              stack,
            );
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
      }
    } catch (_) {
      // Permission denied or directory does not exist — show empty.
    }
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.name.compareTo(b.name);
    });
    if (!mounted) return;
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
      builder: (_) => _HeSteeringFileEditorDialog(
        filePath: entry.absolutePath,
        isZh: widget.isZh,
      ),
    ).then((_) {
      // Refresh in case file was modified.
      _scanDirectory();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 780,
          maxHeight: MediaQuery.sizeOf(context).height * 0.80,
        ),
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
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.isZh ? '资产文件浏览器' : 'Steering Assets Browser',
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
              const SizedBox(height: 12),

              // ── Breadcrumb ──
              _HeBreadcrumb(
                segments: _pathSegments,
                isZh: widget.isZh,
                onNavigate: _navigateTo,
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),

              // ── File list ──
              Expanded(
                child: AnimatedSwitcher(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _loading
                      ? const Center(
                          key: ValueKey<String>('loading'),
                          child: CircularProgressIndicator(),
                        )
                      : _entries.isEmpty
                      ? Center(
                          key: const ValueKey<String>('empty'),
                          child: Text(
                            widget.isZh ? '此目录为空' : 'This directory is empty',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.separated(
                          key: ValueKey<String>(
                            'list-${_pathSegments.join('/')}',
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _entries.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 2),
                          itemBuilder: (ctx, i) {
                            final entry = _entries[i];
                            return _HeSteeringEntryTile(
                              entry: entry,
                              isZh: widget.isZh,
                              description:
                                  entry.isDirectory && _pathSegments.isEmpty
                                  ? _directoryDescriptions[entry.name]
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
  const _HeBreadcrumb({
    required this.segments,
    required this.isZh,
    required this.onNavigate,
  });

  final List<String> segments;
  final bool isZh;
  final void Function(List<String>) onNavigate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final items = <Widget>[
      _breadcrumbChip(
        context,
        label: isZh ? 'steering' : 'steering',
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
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
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
              const SizedBox(width: 4),
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
    required this.isZh,
    this.description,
    required this.onTap,
  });

  final _HeSteeringEntry entry;
  final bool isZh;
  final (String, String)? description;
  final VoidCallback onTap;

  String _formatSize(int bytes) => formatByteSize(bytes);

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

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
    final desc = description;
    final descText = desc != null ? (isZh ? desc.$1 : desc.$2) : null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(_icon, size: 24, color: _iconColor(colorScheme)),
              const SizedBox(width: 12),
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
                    if (descText != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          descText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (!entry.isDirectory && entry.size != null) ...[
                const SizedBox(width: 8),
                Text(
                  _formatSize(entry.size!),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (entry.modified != null) ...[
                const SizedBox(width: 12),
                Text(
                  _formatDate(entry.modified!),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(width: 4),
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

// =============================================================================
// _HeSteeringFileEditorDialog — Markdown editor with live preview
// =============================================================================

class _HeSteeringFileEditorDialog extends StatefulWidget {
  const _HeSteeringFileEditorDialog({
    required this.filePath,
    required this.isZh,
  });

  final String filePath;
  final bool isZh;

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
      final content = await File(widget.filePath).readAsString();
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
        friendly = widget.isZh
            ? '文件已不存在或路径已被移动。\n原始错误：$raw'
            : 'File no longer exists or has been moved.\nRaw: $raw';
      } else if (isFs) {
        friendly = widget.isZh
            ? '读取文件失败 (可能是权限不足 / 编码异常 / 磁盘错误)。\n原始错误：$raw'
            : 'Failed to read file (permission, encoding, or disk error).\nRaw: $raw';
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
      await File(widget.filePath).writeAsString(_controller.text);
      if (!mounted) return;
      setState(() {
        _savedText = _controller.text;
        _dirty = false;
        _saving = false;
      });
      _showHardnessSnackBar(
        context,
        SnackBar(
          content: Text(widget.isZh ? '文件已保存' : 'File saved'),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showFriendlyErrorSnackBar(
        context,
        message: '$e',
        fallback: widget.isZh ? '保存失败' : 'Save failed',
      );
    }
  }

  Future<bool> _confirmDiscard() {
    if (!_dirty) return Future<bool>.value(true);
    return showOpenHandConfirmDialog(
      context: context,
      title: widget.isZh ? '放弃更改？' : 'Discard changes?',
      message: widget.isZh
          ? '你有未保存的更改，确定要放弃吗？'
          : 'You have unsaved changes. Discard them?',
      cancelLabel: widget.isZh ? '取消' : 'Cancel',
      confirmLabel: widget.isZh ? '放弃' : 'Discard',
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
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 1060,
            maxHeight: MediaQuery.sizeOf(context).height * 0.88,
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
                    const SizedBox(width: 8),
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
                            ? (widget.isZh ? '隐藏预览' : 'Hide preview')
                            : (widget.isZh ? '显示预览' : 'Show preview'),
                        onPressed: () =>
                            setState(() => _showPreview = !_showPreview),
                        icon: Icon(
                          _showPreview
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          size: 20,
                        ),
                      ),
                    const SizedBox(width: 4),
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
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 6),

                // ── Markdown toolbar ──
                if (isMarkdown && !_loading && _error == null) ...[
                  _buildToolbar(theme, colorScheme),
                  const SizedBox(height: 6),
                ],

                // ── Body ──
                Expanded(
                  child: AnimatedSwitcher(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
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
                                child: _buildEditorPane(theme, colorScheme),
                              ),
                              const SizedBox(width: 10),
                              VerticalDivider(
                                width: 1,
                                color: colorScheme.outlineVariant,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildPreviewPane(theme, colorScheme),
                              ),
                            ],
                          )
                        : KeyedSubtree(
                            key: const ValueKey<String>('editor'),
                            child: _buildEditorPane(theme, colorScheme),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 10),

                // ── Action row ──
                Row(
                  children: [
                    if (!_loading && _error == null)
                      ListenableBuilder(
                        listenable: _controller,
                        builder: (_, _) {
                          final t = _controller.text;
                          final words = t.trim().isEmpty
                              ? 0
                              : t
                                    .trim()
                                    .split(RegExp(r'\s+'))
                                    .where((w) => w.isNotEmpty)
                                    .length;
                          return Text(
                            widget.isZh
                                ? '${t.length} 字符  $words 词'
                                : '${t.length} chars  $words words',
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
                          widget.isZh ? '有未保存的更改' : 'Unsaved changes',
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
                      label: widget.isZh ? '关闭' : 'Close',
                    ),
                    const SizedBox(width: 8),
                    OpenHandDialogActionButton.primary(
                      onPressed: _dirty && !_saving ? _save : null,
                      icon: Icons.save_rounded,
                      busy: _saving,
                      label: widget.isZh ? '保存' : 'Save',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar(ThemeData theme, ColorScheme colorScheme) {
    final sep = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: SizedBox(
        height: 18,
        child: VerticalDivider(width: 1, color: colorScheme.outlineVariant),
      ),
    );
    final zh = widget.isZh;
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Headings
            _MdToolbarBtn(
              label: 'H₁',
              tooltip: zh ? '一级标题' : 'Heading 1',
              onTap: () => _applyHeading(1),
            ),
            _MdToolbarBtn(
              label: 'H₂',
              tooltip: zh ? '二级标题' : 'Heading 2',
              onTap: () => _applyHeading(2),
            ),
            _MdToolbarBtn(
              label: 'H₃',
              tooltip: zh ? '三级标题' : 'Heading 3',
              onTap: () => _applyHeading(3),
            ),
            sep,
            // Inline styles
            _MdToolbarBtn(
              icon: Icons.format_bold,
              tooltip: zh ? '粗体 **text**' : 'Bold **text**',
              onTap: _applyBold,
            ),
            _MdToolbarBtn(
              icon: Icons.format_italic,
              tooltip: zh ? '斜体 *text*' : 'Italic *text*',
              onTap: _applyItalic,
            ),
            _MdToolbarBtn(
              icon: Icons.format_strikethrough,
              tooltip: zh ? '删除线 ~~text~~' : 'Strikethrough ~~text~~',
              onTap: _applyStrikethrough,
            ),
            _MdToolbarBtn(
              icon: Icons.code,
              tooltip: zh ? '内联代码 `code`' : 'Inline code `code`',
              onTap: _applyInlineCode,
            ),
            sep,
            // Block
            _MdToolbarBtn(
              icon: Icons.data_object_rounded,
              tooltip: zh ? '代码块' : 'Code block',
              onTap: _applyCodeBlock,
            ),
            _MdToolbarBtn(
              icon: Icons.format_quote_rounded,
              tooltip: zh ? '引用块 > text' : 'Blockquote > text',
              onTap: _applyBlockquote,
            ),
            sep,
            // Lists
            _MdToolbarBtn(
              icon: Icons.format_list_bulleted,
              tooltip: zh ? '无序列表 - item' : 'Bullet list - item',
              onTap: _applyBulletList,
            ),
            _MdToolbarBtn(
              icon: Icons.format_list_numbered,
              tooltip: zh ? '有序列表 1. item' : 'Ordered list 1. item',
              onTap: _applyOrderedList,
            ),
            sep,
            // Misc
            _MdToolbarBtn(
              icon: Icons.link_rounded,
              tooltip: zh ? '插入链接 [text](url)' : 'Insert link [text](url)',
              onTap: _insertLink,
            ),
            _MdToolbarBtn(
              icon: Icons.horizontal_rule_rounded,
              tooltip: zh ? '分隔线 ---' : 'Horizontal rule ---',
              onTap: _insertHR,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditorPane(ThemeData theme, ColorScheme colorScheme) {
    // Clip.antiAliasWithSaveLayer composites to a separate layer before
    // blending, fully eliminating the white-corner bleed that Clip.antiAlias
    // produces when a Dialog's white background shows through the rounded
    // edges during anti-aliasing.
    return Container(
      clipBehavior: Clip.antiAliasWithSaveLayer,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
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
          fontFamily: 'monospace',
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
          hintText: widget.isZh ? '在此编辑文件内容…' : 'Edit file content here…',
        ),
      ),
    );
  }

  Widget _buildPreviewPane(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      clipBehavior: Clip.antiAliasWithSaveLayer,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
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
              widget.isZh ? '预览' : 'Preview',
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

// =============================================================================
// _MdToolbarBtn — compact toolbar button (icon or text label)
// =============================================================================

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
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
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
