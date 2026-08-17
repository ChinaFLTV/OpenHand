part of '../openhand_home_page.dart';

const Set<String> _machineTerminalEditableExtensions = <String>{
  '.txt',
  '.md',
  '.conf',
  '.toml',
  '.yaml',
  '.yml',
  '.html',
  '.htm',
  '.css',
  '.scss',
  '.less',
  '.js',
  '.jsx',
  '.ts',
  '.tsx',
  '.json',
  '.xml',
  '.ini',
  '.cfg',
  '.properties',
  '.sh',
  '.bash',
  '.zsh',
  '.py',
  '.dart',
  '.go',
  '.rs',
  '.java',
  '.kt',
  '.swift',
  '.c',
  '.cc',
  '.cpp',
  '.h',
  '.hpp',
  '.sql',
  '.log',
};
const int _machineTerminalVisibleEntryLimit = 2000;

enum _MachineTerminalFileAction {
  refresh,
  details,
  rename,
  edit,
  move,
  copy,
  delete,
}

@immutable
class _MachineTerminalDestination {
  const _MachineTerminalDestination({
    required this.directory,
    required this.name,
  });

  final String directory;
  final String name;
}

class _MachineTerminalFileManagerDialog extends StatefulWidget {
  const _MachineTerminalFileManagerDialog({
    required this.sessionId,
    required this.terminalId,
  });

  final String sessionId;
  final String terminalId;

  @override
  State<_MachineTerminalFileManagerDialog> createState() =>
      _MachineTerminalFileManagerDialogState();
}

class _MachineTerminalFileManagerDialogState
    extends State<_MachineTerminalFileManagerDialog> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  MachineTerminalDirectorySnapshot? _snapshot;
  bool _loading = true;
  int _loadGeneration = 0;
  String? _operationPath;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    unawaited(_loadDirectory());
  }

  @override
  void dispose() {
    _loadGeneration += 1;
    _scrollController.dispose();
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadDirectory([String? path]) async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = await context
          .read<MachineTerminalFileService>()
          .listDirectory(
            sessionId: widget.sessionId,
            terminalId: widget.terminalId,
            path: path,
          );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    } catch (error, stack) {
      silentLog('machine_terminal_file', '加载终端目录', error, stack);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final viewport = MediaQuery.sizeOf(context);
    final dialogWidth = math.min(
      viewport.width * 0.96,
      kOpenHandDialogWidthPanel,
    );
    final dialogHeight = math.min(
      viewport.height * 0.92,
      kOpenHandDialogHeightTall,
    );
    final snapshot = _snapshot;
    final transfers = context.watch<MachineTerminalFileService>().transfers(
      sessionId: widget.sessionId,
      terminalId: widget.terminalId,
    );
    final activeTransfers = transfers.where((task) => task.isActive).length;

    return buildOpenHandDialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      clipBehavior: Clip.none,
      insetPadding: const EdgeInsets.all(14),
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: kOpenHandBorderRadius20,
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.62)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.22),
              blurRadius: 38,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: Column(
          children: [
            _MachineTerminalDialogHeader(
              icon: Icons.folder_copy_rounded,
              title: openHandLocalizedText(
                context,
                zh: '终端文件管理',
                en: 'Terminal File Manager',
              ),
              subtitle:
                  snapshot?.path ??
                  openHandLocalizedText(
                    context,
                    zh: '正在读取当前终端路径',
                    en: 'Reading current terminal path',
                  ),
              trailingActions: [
                _MachineTerminalIconButton(
                  icon: Icons.refresh_rounded,
                  tooltip: openHandLocalizedText(
                    context,
                    zh: '强制刷新',
                    en: 'Force Refresh',
                  ),
                  onPressed: _loading
                      ? null
                      : () => _loadDirectory(snapshot?.path),
                ),
                _MachineTerminalIconButton(
                  icon: Icons.upload_file_rounded,
                  tooltip: openHandLocalizedText(
                    context,
                    zh: '上传文件',
                    en: 'Upload Files',
                  ),
                  onPressed: snapshot == null ? null : _selectUploads,
                ),
                Badge(
                  isLabelVisible: activeTransfers > 0,
                  label: Text('$activeTransfers'),
                  child: _MachineTerminalIconButton(
                    icon: Icons.swap_vert_circle_rounded,
                    tooltip: openHandLocalizedText(
                      context,
                      zh: '传输记录',
                      en: 'Transfers',
                    ),
                    onPressed: _showTransfers,
                  ),
                ),
              ],
              onClose: () => Navigator.of(context).pop(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _buildNavigationBar(context, snapshot),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: _buildContent(context, snapshot),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationBar(
    BuildContext context,
    MachineTerminalDirectorySnapshot? snapshot,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        _MachineTerminalIconButton(
          icon: Icons.my_location_rounded,
          tooltip: openHandLocalizedText(
            context,
            zh: '当前终端路径',
            en: 'Terminal Current Path',
          ),
          onPressed: _loading ? null : () => _loadDirectory(),
        ),
        kOpenHandHGap7,
        _MachineTerminalIconButton(
          icon: Icons.arrow_upward_rounded,
          tooltip: openHandLocalizedText(
            context,
            zh: '上一级目录',
            en: 'Parent Directory',
          ),
          onPressed:
              snapshot == null ||
                  machineTerminalParentPath(snapshot.path) == snapshot.path
              ? null
              : () => _loadDirectory(machineTerminalParentPath(snapshot.path)),
        ),
        kOpenHandHGap8,
        Expanded(
          child: Container(
            height: 36,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: kOpenHandBorderRadius8,
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.55),
              ),
            ),
            child: SelectableText(
              snapshot?.path ?? '-',
              maxLines: 1,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontFamily: kOpenHandMonospaceFontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        kOpenHandHGap8,
        SizedBox(
          width: 220,
          height: 36,
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              isDense: true,
              hintText: openHandLocalizedText(
                context,
                zh: '筛选当前目录',
                en: 'Filter Folder',
              ),
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: openHandClearLabel(context),
                      onPressed: _searchController.clear,
                      icon: const Icon(Icons.close_rounded, size: 17),
                    ),
              border: const OutlineInputBorder(
                borderRadius: kOpenHandBorderRadius8,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(
    BuildContext context,
    MachineTerminalDirectorySnapshot? snapshot,
  ) {
    final cs = Theme.of(context).colorScheme;
    if (_loading && snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && snapshot == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            OpenHandInlineEmptyState(
              icon: Icons.folder_off_rounded,
              message: openHandLocalizedText(
                context,
                zh: '无法读取当前终端目录\n$_error',
                en: 'Unable to read the terminal directory\n$_error',
              ),
            ),
            FilledButton.icon(
              onPressed: _loadDirectory,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(openHandRetryLabel(context)),
            ),
          ],
        ),
      );
    }
    if (snapshot == null) return const SizedBox.shrink();
    final query = _searchController.text.trim().toLowerCase();
    final entries = query.isEmpty
        ? snapshot.entries
        : snapshot.entries
              .where((entry) => entry.name.toLowerCase().contains(query))
              .toList(growable: false);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: kOpenHandBorderRadius12,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.52)),
      ),
      child: ClipRRect(
        borderRadius: kOpenHandBorderRadius12,
        child: Column(
          children: [
            _MachineTerminalFileTableHeader(count: entries.length),
            if (snapshot.truncated)
              Container(
                width: double.infinity,
                color: cs.tertiaryContainer.withValues(alpha: 0.42),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                child: Text(
                  openHandLocalizedText(
                    context,
                    zh: '目录条目较多，仅展示前 $_machineTerminalVisibleEntryLimit 项。',
                    en: 'This folder is large; showing the first $_machineTerminalVisibleEntryLimit items.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onTertiaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            Expanded(
              child: entries.isEmpty
                  ? OpenHandInlineEmptyState(
                      icon: query.isEmpty
                          ? Icons.folder_open_rounded
                          : Icons.search_off_rounded,
                      message: query.isEmpty
                          ? openHandLocalizedText(
                              context,
                              zh: '当前目录为空。',
                              en: 'This folder is empty.',
                            )
                          : openHandLocalizedText(
                              context,
                              zh: '没有匹配的文件。',
                              en: 'No matching files.',
                            ),
                    )
                  : OpenHandSafeScrollbar(
                      controller: _scrollController,
                      child: ListView.builder(
                        controller: _scrollController,
                        itemCount: entries.length,
                        itemExtent: 52,
                        itemBuilder: (context, index) =>
                            _buildFileRow(context, entries[index]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileRow(BuildContext context, MachineTerminalFileEntry entry) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final busy = _operationPath == entry.path;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: entry.isDirectory && !busy
            ? () => _loadDirectory(entry.path)
            : null,
        hoverColor: cs.primary.withValues(alpha: 0.045),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Icon(
                        _machineTerminalFileIcon(entry),
                        size: 20,
                        color: _machineTerminalFileColor(cs, entry),
                      ),
                      kOpenHandHGap10,
                      Expanded(
                        child: Text(
                          entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  _machineTerminalFileKindLabel(context, entry.kind),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  entry.isDirectory ? '-' : formatByteSize(entry.size),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  _formatMachineTerminalFileTime(entry.modifiedAt),
                  maxLines: 1,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: 48,
                child: busy
                    ? const Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _MachineTerminalFileMenuButton(
                        onTapDown: (details) => _showEntryMenu(entry, details),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showEntryMenu(
    MachineTerminalFileEntry entry,
    TapDownDetails details,
  ) async {
    final editable = _isMachineTerminalFileEditable(entry);
    final selected = await showAnimatedMenu<_MachineTerminalFileAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx,
        details.globalPosition.dy,
      ),
      items: [
        _fileMenuItem(
          _MachineTerminalFileAction.refresh,
          Icons.refresh_rounded,
          openHandLocalizedText(context, zh: '刷新', en: 'Refresh'),
        ),
        _fileMenuItem(
          _MachineTerminalFileAction.details,
          Icons.info_outline_rounded,
          openHandLocalizedText(context, zh: '详情', en: 'Details'),
        ),
        _fileMenuItem(
          _MachineTerminalFileAction.rename,
          Icons.drive_file_rename_outline_rounded,
          openHandLocalizedText(context, zh: '重命名', en: 'Rename'),
        ),
        _fileMenuItem(
          _MachineTerminalFileAction.edit,
          Icons.edit_note_rounded,
          openHandLocalizedText(context, zh: '编辑', en: 'Edit'),
          enabled: editable,
        ),
        const PopupMenuDivider(),
        _fileMenuItem(
          _MachineTerminalFileAction.move,
          Icons.drive_file_move_rounded,
          openHandLocalizedText(context, zh: '移动', en: 'Move'),
        ),
        _fileMenuItem(
          _MachineTerminalFileAction.copy,
          Icons.copy_all_rounded,
          openHandLocalizedText(context, zh: '复制', en: 'Copy'),
        ),
        const PopupMenuDivider(),
        _fileMenuItem(
          _MachineTerminalFileAction.delete,
          Icons.delete_outline_rounded,
          openHandLocalizedText(context, zh: '删除', en: 'Delete'),
          destructive: true,
        ),
      ],
    );
    if (selected == null || !mounted) return;
    switch (selected) {
      case _MachineTerminalFileAction.refresh:
        await _refreshEntry(entry);
      case _MachineTerminalFileAction.details:
        await _showDetails(entry);
      case _MachineTerminalFileAction.rename:
        await _renameEntry(entry);
      case _MachineTerminalFileAction.edit:
        await _editEntry(entry);
      case _MachineTerminalFileAction.move:
        await _moveOrCopyEntry(entry, copy: false);
      case _MachineTerminalFileAction.copy:
        await _moveOrCopyEntry(entry, copy: true);
      case _MachineTerminalFileAction.delete:
        await _deleteEntry(entry);
    }
  }

  PopupMenuItem<_MachineTerminalFileAction> _fileMenuItem(
    _MachineTerminalFileAction value,
    IconData icon,
    String label, {
    bool enabled = true,
    bool destructive = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final color = destructive ? cs.error : null;
    return PopupMenuItem<_MachineTerminalFileAction>(
      value: value,
      enabled: enabled,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          kOpenHandHGap10,
          Text(label, style: color == null ? null : TextStyle(color: color)),
        ],
      ),
    );
  }

  Future<void> _selectUploads() async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    try {
      final selected = await openFiles();
      if (!mounted || selected.isEmpty) return;
      if (selected.length > kMachineTerminalMaxUploadFiles) {
        showOpenHandErrorSnack(
          context,
          openHandLocalizedText(
            context,
            zh: '一次最多选择 $kMachineTerminalMaxUploadFiles 个文件。',
            en: 'Select up to $kMachineTerminalMaxUploadFiles files at a time.',
          ),
        );
        return;
      }
      await context.read<MachineTerminalFileService>().enqueueUploads(
        sessionId: widget.sessionId,
        terminalId: widget.terminalId,
        targetDirectory: snapshot.path,
        sourcePaths: selected.map((file) => file.path).toList(growable: false),
      );
      if (!mounted) return;
      showOpenHandSuccessSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '已加入 ${selected.length} 个串行传输任务。',
          en: '${selected.length} serial transfer tasks queued.',
        ),
      );
      _showTransfers();
    } catch (error, stack) {
      _showOperationError('选择上传文件', error, stack);
    }
  }

  void _showTransfers() {
    showAnimatedDialog<void>(
      context: context,
      builder: (dialogContext) => _MachineTerminalTransfersDialog(
        sessionId: widget.sessionId,
        terminalId: widget.terminalId,
      ),
    );
  }

  Future<void> _refreshEntry(MachineTerminalFileEntry entry) async {
    await _runEntryOperation(entry.path, '刷新文件', () async {
      final details = await context
          .read<MachineTerminalFileService>()
          .fileDetails(
            sessionId: widget.sessionId,
            terminalId: widget.terminalId,
            path: entry.path,
          );
      if (!mounted || _snapshot == null) return;
      final entries = _snapshot!.entries.toList(growable: true);
      final index = entries.indexWhere((item) => item.path == entry.path);
      if (index < 0) return;
      entries[index] = details.entry;
      setState(() {
        _snapshot = MachineTerminalDirectorySnapshot(
          path: _snapshot!.path,
          entries: List<MachineTerminalFileEntry>.unmodifiable(entries),
          truncated: _snapshot!.truncated,
          windowsPath: _snapshot!.windowsPath,
        );
      });
    });
  }

  Future<void> _showDetails(MachineTerminalFileEntry entry) async {
    await _runEntryOperation(entry.path, '读取文件详情', () async {
      final details = await context
          .read<MachineTerminalFileService>()
          .fileDetails(
            sessionId: widget.sessionId,
            terminalId: widget.terminalId,
            path: entry.path,
          );
      if (!mounted) return;
      await showAnimatedDialog<void>(
        context: context,
        builder: (dialogContext) =>
            _MachineTerminalFileDetailsDialog(details: details),
      );
    });
  }

  Future<void> _renameEntry(MachineTerminalFileEntry entry) async {
    final name = await showOpenHandTextInputDialog(
      context: context,
      title: openHandLocalizedText(context, zh: '重命名文件', en: 'Rename File'),
      initialValue: entry.name,
      confirmLabel: openHandSaveLabel(context),
      icon: const Icon(Icons.drive_file_rename_outline_rounded),
    );
    if (!mounted || name == null || name == entry.name) return;
    await _runEntryOperation(entry.path, '重命名文件', () async {
      await context.read<MachineTerminalFileService>().rename(
        sessionId: widget.sessionId,
        terminalId: widget.terminalId,
        sourcePath: entry.path,
        newName: name,
      );
      await _loadDirectory(_snapshot?.path);
    });
  }

  Future<void> _editEntry(MachineTerminalFileEntry entry) async {
    await _runEntryOperation(entry.path, '读取待编辑文件', () async {
      final service = context.read<MachineTerminalFileService>();
      final content = await service.readTextFile(
        sessionId: widget.sessionId,
        terminalId: widget.terminalId,
        entry: entry,
      );
      if (!mounted) return;
      final updated = await showAnimatedDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => _MachineTerminalFileEditorDialog(
          path: entry.path,
          initialContent: content,
        ),
      );
      if (!mounted || updated == null || updated == content) return;
      setState(() => _operationPath = entry.path);
      try {
        await service.writeTextFile(
          sessionId: widget.sessionId,
          terminalId: widget.terminalId,
          path: entry.path,
          content: updated,
        );
        if (!mounted) return;
        showOpenHandSuccessSnack(
          context,
          openHandLocalizedText(context, zh: '文件已保存。', en: 'File saved.'),
        );
        await _loadDirectory(_snapshot?.path);
      } finally {
        if (mounted) setState(() => _operationPath = null);
      }
    });
  }

  Future<void> _moveOrCopyEntry(
    MachineTerminalFileEntry entry, {
    required bool copy,
  }) async {
    final currentPath = _snapshot?.path;
    if (currentPath == null) return;
    final destination = await showAnimatedDialog<_MachineTerminalDestination>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _MachineTerminalDirectoryPickerDialog(
        sessionId: widget.sessionId,
        terminalId: widget.terminalId,
        initialDirectory: currentPath,
        initialName: entry.name,
        copy: copy,
      ),
    );
    if (!mounted || destination == null) return;
    final targetPath = machineTerminalJoinPath(
      destination.directory,
      destination.name,
    );
    if (targetPath == entry.path) {
      showOpenHandInfoSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '源文件与目标文件相同。',
          en: 'Source and destination are identical.',
        ),
      );
      return;
    }
    await _runEntryOperation(entry.path, copy ? '复制文件' : '移动文件', () async {
      final service = context.read<MachineTerminalFileService>();
      if (copy) {
        await service.copy(
          sessionId: widget.sessionId,
          terminalId: widget.terminalId,
          sourcePath: entry.path,
          targetPath: targetPath,
        );
      } else {
        await service.move(
          sessionId: widget.sessionId,
          terminalId: widget.terminalId,
          sourcePath: entry.path,
          targetPath: targetPath,
        );
      }
      await _loadDirectory(_snapshot?.path);
    });
  }

  Future<void> _deleteEntry(MachineTerminalFileEntry entry) async {
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: openHandLocalizedText(context, zh: '删除文件？', en: 'Delete File?'),
      message: openHandLocalizedText(
        context,
        zh: '将永久删除“${entry.name}”${entry.isDirectory ? '及其全部内容' : ''}，此操作不可恢复。',
        en: '“${entry.name}”${entry.isDirectory ? ' and all of its contents' : ''} will be permanently deleted. This cannot be undone.',
      ),
      confirmLabel: openHandDeleteLabel(context),
      destructive: true,
    );
    if (!mounted || !confirmed) return;
    await _runEntryOperation(entry.path, '删除文件', () async {
      await context.read<MachineTerminalFileService>().delete(
        sessionId: widget.sessionId,
        terminalId: widget.terminalId,
        path: entry.path,
      );
      await _loadDirectory(_snapshot?.path);
    });
  }

  Future<void> _runEntryOperation(
    String path,
    String action,
    Future<void> Function() operation,
  ) async {
    if (_operationPath != null) return;
    setState(() => _operationPath = path);
    try {
      await operation();
    } catch (error, stack) {
      _showOperationError(action, error, stack);
    } finally {
      if (mounted) setState(() => _operationPath = null);
    }
  }

  void _showOperationError(String action, Object error, StackTrace stack) {
    silentLog('machine_terminal_file', action, error, stack);
    if (!mounted) return;
    showOpenHandErrorSnack(
      context,
      openHandLocalizedText(
        context,
        zh: '$action失败：$error',
        en: '$action failed: $error',
      ),
      maxLines: 3,
    );
  }
}

class _MachineTerminalFileTableHeader extends StatelessWidget {
  const _MachineTerminalFileTableHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    Widget label(String value, int flex) => Expanded(
      flex: flex,
      child: Text(
        value,
        maxLines: 1,
        style: theme.textTheme.labelMedium?.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
    return Container(
      height: 40,
      padding: const EdgeInsets.only(left: 14),
      color: cs.surfaceContainerHighest.withValues(alpha: 0.56),
      child: Row(
        children: [
          label(
            '${openHandLocalizedText(context, zh: '名称', en: 'Name')} ($count)',
            5,
          ),
          label(openHandLocalizedText(context, zh: '类型', en: 'Type'), 2),
          label(openHandLocalizedText(context, zh: '大小', en: 'Size'), 2),
          label(openHandLocalizedText(context, zh: '修改时间', en: 'Modified'), 3),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _MachineTerminalFileMenuButton extends StatelessWidget {
  const _MachineTerminalFileMenuButton({required this.onTapDown});

  final GestureTapDownCallback onTapDown;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: openHandLocalizedText(context, zh: '更多操作', en: 'More Actions'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: onTapDown,
        child: const SizedBox(
          width: 40,
          height: 40,
          child: Icon(Icons.more_vert_rounded, size: 20),
        ),
      ),
    );
  }
}

bool _isMachineTerminalFileEditable(MachineTerminalFileEntry entry) {
  return entry.isFile &&
      entry.size < kMachineTerminalMaxEditableFileBytes &&
      _machineTerminalEditableExtensions.contains(
        p.extension(entry.name).toLowerCase(),
      );
}

IconData _machineTerminalFileIcon(MachineTerminalFileEntry entry) {
  if (entry.isDirectory) return Icons.folder_rounded;
  if (entry.isLink) return Icons.link_rounded;
  return openHandFileNameIcon(entry.name);
}

Color _machineTerminalFileColor(
  ColorScheme cs,
  MachineTerminalFileEntry entry,
) {
  if (entry.isDirectory) return cs.primary;
  if (entry.isLink) return cs.tertiary;
  return cs.secondary;
}

String _machineTerminalFileKindLabel(
  BuildContext context,
  MachineTerminalFileKind kind,
) => switch (kind) {
  MachineTerminalFileKind.file => openHandLocalizedText(
    context,
    zh: '文件',
    en: 'File',
  ),
  MachineTerminalFileKind.directory => openHandLocalizedText(
    context,
    zh: '目录',
    en: 'Folder',
  ),
  MachineTerminalFileKind.link => openHandLocalizedText(
    context,
    zh: '链接',
    en: 'Link',
  ),
  MachineTerminalFileKind.other => openHandLocalizedText(
    context,
    zh: '其他',
    en: 'Other',
  ),
};

String _formatMachineTerminalFileTime(DateTime? value) {
  if (value == null) return '-';
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

class _MachineTerminalFileDetailsDialog extends StatelessWidget {
  const _MachineTerminalFileDetailsDialog({required this.details});

  final MachineTerminalFileDetails details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final viewport = MediaQuery.sizeOf(context);
    final width = math.min(viewport.width * 0.92, kOpenHandDialogWidthStandard);
    final height = math.min(
      viewport.height * 0.84,
      kOpenHandDialogHeightStandard,
    );
    final entry = details.entry;
    final rows = <(String, String, IconData)>[
      (
        openHandLocalizedText(context, zh: '名称', en: 'Name'),
        entry.name,
        Icons.text_fields_rounded,
      ),
      (
        openHandLocalizedText(context, zh: '完整路径', en: 'Full Path'),
        entry.path,
        Icons.route_rounded,
      ),
      (
        openHandLocalizedText(context, zh: '资源类型', en: 'Resource Type'),
        _machineTerminalFileKindLabel(context, entry.kind),
        _machineTerminalFileIcon(entry),
      ),
      (
        openHandLocalizedText(context, zh: '文件大小', en: 'Size'),
        '${formatByteSize(entry.size)} (${entry.size} B)',
        Icons.data_usage_rounded,
      ),
      (
        openHandLocalizedText(context, zh: 'MIME 类型', en: 'MIME Type'),
        details.mimeType.isEmpty ? '-' : details.mimeType,
        Icons.category_outlined,
      ),
      (
        openHandLocalizedText(context, zh: '权限/属性', en: 'Permissions'),
        entry.permissions.isEmpty ? '-' : entry.permissions,
        Icons.admin_panel_settings_outlined,
      ),
      (
        openHandLocalizedText(context, zh: '所有者', en: 'Owner'),
        details.owner.isEmpty ? '-' : details.owner,
        Icons.person_outline_rounded,
      ),
      (
        openHandLocalizedText(context, zh: '用户组', en: 'Group'),
        details.group.isEmpty ? '-' : details.group,
        Icons.group_outlined,
      ),
      (
        openHandLocalizedText(context, zh: '文件标识', en: 'Inode / ID'),
        details.inode.isEmpty ? '-' : details.inode,
        Icons.fingerprint_rounded,
      ),
      if (entry.linkTarget != null)
        (
          openHandLocalizedText(context, zh: '链接目标', en: 'Link Target'),
          entry.linkTarget!,
          Icons.link_rounded,
        ),
      (
        openHandLocalizedText(context, zh: '创建时间', en: 'Created'),
        _formatMachineTerminalFileTime(details.createdAt),
        Icons.add_circle_outline_rounded,
      ),
      (
        openHandLocalizedText(context, zh: '修改时间', en: 'Modified'),
        _formatMachineTerminalFileTime(entry.modifiedAt),
        Icons.edit_calendar_outlined,
      ),
      (
        openHandLocalizedText(context, zh: '访问时间', en: 'Accessed'),
        _formatMachineTerminalFileTime(details.accessedAt),
        Icons.visibility_outlined,
      ),
      (
        openHandLocalizedText(context, zh: '状态变更', en: 'Changed'),
        _formatMachineTerminalFileTime(details.changedAt),
        Icons.update_rounded,
      ),
    ];
    return buildOpenHandDialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(18),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: kOpenHandBorderRadius20,
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.2),
              blurRadius: 34,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          children: [
            _MachineTerminalDialogHeader(
              icon: _machineTerminalFileIcon(entry),
              title: openHandLocalizedText(
                context,
                zh: '文件详情',
                en: 'File Details',
              ),
              subtitle: entry.name,
              onClose: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                itemCount: rows.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  color: cs.outlineVariant.withValues(alpha: 0.34),
                ),
                itemBuilder: (context, index) {
                  final row = rows[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(row.$3, size: 18, color: cs.primary),
                        kOpenHandHGap10,
                        SizedBox(
                          width: 120,
                          child: Text(
                            row.$1,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        kOpenHandHGap12,
                        Expanded(
                          child: SelectableText(
                            row.$2,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontFamily: row.$1.contains('路径')
                                  ? kOpenHandMonospaceFontFamily
                                  : null,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MachineTerminalDirectoryPickerDialog extends StatefulWidget {
  const _MachineTerminalDirectoryPickerDialog({
    required this.sessionId,
    required this.terminalId,
    required this.initialDirectory,
    required this.initialName,
    required this.copy,
  });

  final String sessionId;
  final String terminalId;
  final String initialDirectory;
  final String initialName;
  final bool copy;

  @override
  State<_MachineTerminalDirectoryPickerDialog> createState() =>
      _MachineTerminalDirectoryPickerDialogState();
}

class _MachineTerminalDirectoryPickerDialogState
    extends State<_MachineTerminalDirectoryPickerDialog> {
  late final TextEditingController _nameController;
  final ScrollController _scrollController = ScrollController();
  MachineTerminalDirectorySnapshot? _snapshot;
  bool _loading = true;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName)
      ..addListener(_handleNameChanged);
    unawaited(_load(widget.initialDirectory));
  }

  @override
  void dispose() {
    _generation += 1;
    _nameController
      ..removeListener(_handleNameChanged)
      ..dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleNameChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load(String path) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = await context
          .read<MachineTerminalFileService>()
          .listDirectory(
            sessionId: widget.sessionId,
            terminalId: widget.terminalId,
            path: path,
          );
      if (!mounted || generation != _generation) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
    } catch (error, stack) {
      silentLog('machine_terminal_file', '加载目标目录', error, stack);
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final viewport = MediaQuery.sizeOf(context);
    final width = math.min(viewport.width * 0.92, kOpenHandDialogWidthWide);
    final height = math.min(
      viewport.height * 0.86,
      kOpenHandDialogHeightStandard,
    );
    final snapshot = _snapshot;
    final directories =
        snapshot?.entries
            .where((entry) => entry.isDirectory)
            .toList(growable: false) ??
        const <MachineTerminalFileEntry>[];
    final name = _nameController.text.trim();
    final validName =
        name.isNotEmpty &&
        name != '.' &&
        name != '..' &&
        !name.contains('/') &&
        !name.contains(r'\');

    return buildOpenHandDialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(18),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: kOpenHandBorderRadius20,
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.2),
              blurRadius: 34,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          children: [
            _MachineTerminalDialogHeader(
              icon: widget.copy
                  ? Icons.copy_all_rounded
                  : Icons.drive_file_move_rounded,
              title: widget.copy
                  ? openHandLocalizedText(
                      context,
                      zh: '选择复制目标',
                      en: 'Choose Copy Destination',
                    )
                  : openHandLocalizedText(
                      context,
                      zh: '选择移动目标',
                      en: 'Choose Move Destination',
                    ),
              subtitle: snapshot?.path ?? widget.initialDirectory,
              onClose: () => Navigator.of(context).pop(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  _MachineTerminalIconButton(
                    icon: Icons.arrow_upward_rounded,
                    tooltip: openHandLocalizedText(
                      context,
                      zh: '上一级目录',
                      en: 'Parent Directory',
                    ),
                    onPressed:
                        snapshot == null ||
                            machineTerminalParentPath(snapshot.path) ==
                                snapshot.path
                        ? null
                        : () => _load(machineTerminalParentPath(snapshot.path)),
                  ),
                  kOpenHandHGap8,
                  Expanded(
                    child: Container(
                      height: 36,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withValues(
                          alpha: 0.52,
                        ),
                        borderRadius: kOpenHandBorderRadius8,
                      ),
                      child: SelectableText(
                        snapshot?.path ?? widget.initialDirectory,
                        maxLines: 1,
                        style: const TextStyle(
                          fontFamily: kOpenHandMonospaceFontFamily,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLowest,
                  borderRadius: kOpenHandBorderRadius8,
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? OpenHandInlineEmptyState(
                        icon: Icons.folder_off_rounded,
                        message: _error!,
                      )
                    : directories.isEmpty
                    ? OpenHandInlineEmptyState(
                        icon: Icons.folder_open_rounded,
                        message: openHandLocalizedText(
                          context,
                          zh: '当前目录没有子目录。',
                          en: 'No subfolders here.',
                        ),
                      )
                    : OpenHandSafeScrollbar(
                        controller: _scrollController,
                        child: ListView.separated(
                          controller: _scrollController,
                          itemCount: directories.length,
                          separatorBuilder: (_, _) => Divider(
                            height: 1,
                            color: cs.outlineVariant.withValues(alpha: 0.3),
                          ),
                          itemBuilder: (context, index) {
                            final directory = directories[index];
                            return ListTile(
                              dense: true,
                              leading: Icon(
                                Icons.folder_rounded,
                                color: cs.primary,
                              ),
                              title: Text(
                                directory.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () => _load(directory.path),
                            );
                          },
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: openHandLocalizedText(
                          context,
                          zh: '目标文件名（含后缀名）',
                          en: 'Destination Name (with extension)',
                        ),
                        prefixIcon: const Icon(
                          Icons.drive_file_rename_outline_rounded,
                        ),
                        errorText: name.isNotEmpty && !validName
                            ? openHandLocalizedText(
                                context,
                                zh: '请输入不含路径分隔符的文件名。',
                                en: 'Enter a name without path separators.',
                              )
                            : null,
                      ),
                    ),
                  ),
                  kOpenHandHGap12,
                  FilledButton.icon(
                    onPressed: snapshot == null || !validName
                        ? null
                        : () => Navigator.of(context).pop(
                            _MachineTerminalDestination(
                              directory: snapshot.path,
                              name: name,
                            ),
                          ),
                    icon: Icon(
                      widget.copy
                          ? Icons.copy_all_rounded
                          : Icons.drive_file_move_rounded,
                    ),
                    label: Text(
                      widget.copy
                          ? openHandLocalizedText(
                              context,
                              zh: '复制到这里',
                              en: 'Copy Here',
                            )
                          : openHandLocalizedText(
                              context,
                              zh: '移动到这里',
                              en: 'Move Here',
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MachineTerminalFileEditorDialog extends StatefulWidget {
  const _MachineTerminalFileEditorDialog({
    required this.path,
    required this.initialContent,
  });

  final String path;
  final String initialContent;

  @override
  State<_MachineTerminalFileEditorDialog> createState() =>
      _MachineTerminalFileEditorDialogState();
}

class _MachineTerminalFileEditorDialogState
    extends State<_MachineTerminalFileEditorDialog> {
  late final _HighlightingTextController _controller;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'terminal-file-editor');
  late final String _language;
  bool _dirty = false;
  int _contentBytes = 0;

  @override
  void initState() {
    super.initState();
    _language = _resolveEditorLanguage(
      filePath: widget.path,
      projectLanguage: 'mixed',
    );
    _controller = _HighlightingTextController(
      initialText: widget.initialContent,
      language: _language,
    );
    _contentBytes = utf8.encode(widget.initialContent).length;
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final viewport = MediaQuery.sizeOf(context);
    final width = math.min(
      viewport.width * 0.96,
      kOpenHandDialogWidthExtraWide,
    );
    final height = math.min(viewport.height * 0.92, kOpenHandDialogHeightTall);
    final exceedsLimit = _contentBytes >= kMachineTerminalMaxEditableFileBytes;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: buildOpenHandDialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(14),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: kOpenHandBorderRadius20,
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.62),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: cs.shadow.withValues(alpha: 0.22),
                blurRadius: 38,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: Column(
            children: [
              _MachineTerminalDialogHeader(
                icon: Icons.edit_note_rounded,
                title: openHandLocalizedText(
                  context,
                  zh: '编辑终端文件',
                  en: 'Edit Terminal File',
                ),
                subtitle: widget.path,
                trailingActions: [
                  _MachineTerminalIconButton(
                    icon: Icons.save_rounded,
                    tooltip: openHandSaveLabel(context),
                    onPressed: _dirty && !exceedsLimit
                        ? () => Navigator.of(context).pop(_controller.text)
                        : null,
                  ),
                ],
                onClose: () => unawaited(_close()),
              ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: kOpenHandBorderRadius8,
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.54),
                    ),
                  ),
                  child: _SyntaxHighlightEditor(
                    controller: _controller,
                    scrollController: _scrollController,
                    focusNode: _focusNode,
                    language: _language,
                    wordWrap: context.select<SettingsController, bool>(
                      (controller) => controller.editorWordWrap,
                    ),
                    codeTheme: context
                        .select<SettingsController, EditorCodeTheme>(
                          (controller) => controller.editorCodeTheme,
                        ),
                    onChanged: (value) {
                      final bytes = utf8.encode(value).length;
                      final dirty = value != widget.initialContent;
                      if (_contentBytes == bytes && _dirty == dirty) return;
                      setState(() {
                        _contentBytes = bytes;
                        _dirty = dirty;
                      });
                    },
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(18, 9, 18, 12),
                decoration: BoxDecoration(
                  color: exceedsLimit
                      ? cs.errorContainer.withValues(alpha: 0.5)
                      : cs.surfaceContainerHighest.withValues(alpha: 0.45),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(kOpenHandRadius20),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      exceedsLimit
                          ? Icons.warning_amber_rounded
                          : Icons.code_rounded,
                      size: 17,
                      color: exceedsLimit ? cs.error : cs.primary,
                    ),
                    kOpenHandHGap8,
                    Expanded(
                      child: Text(
                        exceedsLimit
                            ? openHandLocalizedText(
                                context,
                                zh: '内容已达到 5 MB 上限，请缩减后保存。',
                                en: 'Content reached the 5 MB limit. Reduce it before saving.',
                              )
                            : '$_language · ${formatByteSize(_contentBytes)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: exceedsLimit
                              ? cs.onErrorContainer
                              : cs.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (_dirty)
                      Text(
                        openHandLocalizedText(
                          context,
                          zh: '未保存',
                          en: 'Unsaved',
                        ),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: cs.tertiary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _close() async {
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showOpenHandConfirmDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '放弃未保存的修改？',
        en: 'Discard Unsaved Changes?',
      ),
      message: openHandLocalizedText(
        context,
        zh: '当前编辑内容尚未保存，关闭后无法恢复。',
        en: 'The current edits have not been saved and cannot be recovered after closing.',
      ),
      confirmLabel: openHandLocalizedText(
        context,
        zh: '放弃修改',
        en: 'Discard Changes',
      ),
      destructive: true,
    );
    if (discard && mounted) Navigator.of(context).pop();
  }
}

class _MachineTerminalTransfersDialog extends StatelessWidget {
  const _MachineTerminalTransfersDialog({
    required this.sessionId,
    required this.terminalId,
  });

  final String sessionId;
  final String terminalId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final viewport = MediaQuery.sizeOf(context);
    final width = math.min(viewport.width * 0.92, kOpenHandDialogWidthWide);
    final height = math.min(
      viewport.height * 0.86,
      kOpenHandDialogHeightStandard,
    );
    final service = context.watch<MachineTerminalFileService>();
    final tasks = service.transfers(
      sessionId: sessionId,
      terminalId: terminalId,
    );
    final active = tasks.where((task) => task.isActive).length;
    final completed = tasks
        .where((task) => task.status == MachineTerminalTransferStatus.completed)
        .length;

    return buildOpenHandDialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(18),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: kOpenHandBorderRadius20,
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.2),
              blurRadius: 34,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          children: [
            _MachineTerminalDialogHeader(
              icon: Icons.swap_vert_circle_rounded,
              title: openHandLocalizedText(
                context,
                zh: '文件传输记录',
                en: 'File Transfers',
              ),
              subtitle: openHandLocalizedText(
                context,
                zh: '共 ${tasks.length} 项 · 进行中 $active · 已完成 $completed',
                en: '${tasks.length} total · $active active · $completed completed',
              ),
              onClose: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: tasks.isEmpty
                  ? OpenHandInlineEmptyState(
                      icon: Icons.cloud_upload_outlined,
                      message: openHandLocalizedText(
                        context,
                        zh: '暂无文件传输记录。',
                        en: 'No file transfers yet.',
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: tasks.length,
                      separatorBuilder: (_, _) => kOpenHandGap8,
                      itemBuilder: (context, index) =>
                          _MachineTerminalTransferRow(task: tasks[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MachineTerminalTransferRow extends StatelessWidget {
  const _MachineTerminalTransferRow({required this.task});

  final MachineTerminalTransferTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final service = context.read<MachineTerminalFileService>();
    final statusColor = _machineTerminalTransferColor(cs, task.status);
    final canPause =
        task.status == MachineTerminalTransferStatus.queued ||
        task.status == MachineTerminalTransferStatus.transferring;
    final canResume = task.status == MachineTerminalTransferStatus.paused;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.055),
        borderRadius: kOpenHandBorderRadius8,
        border: Border.all(color: statusColor.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: kOpenHandBorderRadius8,
                ),
                child: Icon(
                  _machineTerminalTransferIcon(task.status),
                  size: 18,
                  color: statusColor,
                ),
              ),
              kOpenHandHGap10,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    kOpenHandGap3,
                    Text(
                      '${_machineTerminalTransferStatusLabel(context, task.status)} · '
                      '${formatByteSize(task.transferredBytes)} / ${formatByteSize(task.totalBytes)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (canPause || canResume)
                _MachineTerminalMiniActionButton(
                  icon: canResume
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                  tooltip: canResume
                      ? openHandLocalizedText(
                          context,
                          zh: '恢复传输',
                          en: 'Resume Transfer',
                        )
                      : openHandLocalizedText(
                          context,
                          zh: '暂停传输',
                          en: 'Pause Transfer',
                        ),
                  onPressed: canResume
                      ? () => service.resumeTransfer(task.id)
                      : () => service.pauseTransfer(task.id),
                ),
              if (task.isActive) ...[
                kOpenHandHGap6,
                _MachineTerminalMiniActionButton(
                  icon: Icons.cancel_outlined,
                  tooltip: openHandLocalizedText(
                    context,
                    zh: '取消传输',
                    en: 'Cancel Transfer',
                  ),
                  destructive: true,
                  onPressed: () => service.cancelTransfer(task.id),
                ),
              ],
              kOpenHandHGap6,
              _MachineTerminalMiniActionButton(
                icon: Icons.delete_outline_rounded,
                tooltip: openHandLocalizedText(
                  context,
                  zh: '删除记录',
                  en: 'Delete Record',
                ),
                destructive: true,
                onPressed: () => service.deleteTransfer(task.id),
              ),
            ],
          ),
          kOpenHandGap10,
          ClipRRect(
            borderRadius: kOpenHandPillBorderRadius,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: task.progress),
              duration: openHandMotionDuration(context, kOpenHandMotion220),
              curve: kOpenHandSwitchInCurve,
              builder: (context, value, _) => LinearProgressIndicator(
                minHeight: 7,
                value: value,
                color: statusColor,
                backgroundColor: cs.surfaceContainerHighest,
              ),
            ),
          ),
          if (task.error != null && task.error!.isNotEmpty) ...[
            kOpenHandGap8,
            Text(
              task.error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _machineTerminalTransferStatusLabel(
  BuildContext context,
  MachineTerminalTransferStatus status,
) => switch (status) {
  MachineTerminalTransferStatus.queued => openHandLocalizedText(
    context,
    zh: '等待中',
    en: 'Queued',
  ),
  MachineTerminalTransferStatus.transferring => openHandLocalizedText(
    context,
    zh: '传输中',
    en: 'Transferring',
  ),
  MachineTerminalTransferStatus.paused => openHandLocalizedText(
    context,
    zh: '已暂停',
    en: 'Paused',
  ),
  MachineTerminalTransferStatus.completed => openHandLocalizedText(
    context,
    zh: '已完成',
    en: 'Completed',
  ),
  MachineTerminalTransferStatus.failed => openHandLocalizedText(
    context,
    zh: '失败',
    en: 'Failed',
  ),
  MachineTerminalTransferStatus.canceled => openHandLocalizedText(
    context,
    zh: '已取消',
    en: 'Canceled',
  ),
};

IconData _machineTerminalTransferIcon(MachineTerminalTransferStatus status) =>
    switch (status) {
      MachineTerminalTransferStatus.queued => Icons.schedule_rounded,
      MachineTerminalTransferStatus.transferring => Icons.upload_rounded,
      MachineTerminalTransferStatus.paused => Icons.pause_circle_rounded,
      MachineTerminalTransferStatus.completed => Icons.check_circle_rounded,
      MachineTerminalTransferStatus.failed => Icons.error_rounded,
      MachineTerminalTransferStatus.canceled => Icons.cancel_rounded,
    };

Color _machineTerminalTransferColor(
  ColorScheme cs,
  MachineTerminalTransferStatus status,
) => switch (status) {
  MachineTerminalTransferStatus.queued => cs.secondary,
  MachineTerminalTransferStatus.transferring => cs.primary,
  MachineTerminalTransferStatus.paused => cs.tertiary,
  MachineTerminalTransferStatus.completed => OpenHandStatusColors.success,
  MachineTerminalTransferStatus.failed => cs.error,
  MachineTerminalTransferStatus.canceled => cs.onSurfaceVariant,
};
