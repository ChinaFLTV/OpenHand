part of '../openhand_home_page.dart';

const Set<String> _machineTerminalAdditionalTextExtensions = <String>{
  '.properties',
};
const int _machineTerminalVisibleEntryLimit = 2000;
const BoundedDeletePolicy _machineTerminalPreviewDeletePolicy =
    BoundedDeletePolicy(
      maxEntries: 4,
      maxDepth: 2,
      operationTimeout: Duration(seconds: 3),
      totalTimeout: Duration(seconds: 8),
    );

enum _MachineTerminalFileAction {
  refresh,
  details,
  download,
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
  final TextEditingController _pathController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  MachineTerminalDirectorySnapshot? _snapshot;
  bool _loading = true;
  int _loadGeneration = 0;
  String? _operationPath;
  String? _error;
  bool _syncingPath = false;

  @override
  void initState() {
    super.initState();
    _pathController.addListener(_handlePathChanged);
    _searchController.addListener(_handleSearchChanged);
    unawaited(_loadDirectory());
  }

  @override
  void dispose() {
    _loadGeneration += 1;
    _scrollController.dispose();
    _pathController
      ..removeListener(_handlePathChanged)
      ..dispose();
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    if (mounted) setState(() {});
  }

  void _handlePathChanged() {
    if (!_syncingPath && mounted) setState(() {});
  }

  void _setPathText(String path) {
    _syncingPath = true;
    _pathController.value = TextEditingValue(
      text: path,
      selection: TextSelection.collapsed(offset: path.length),
    );
    _syncingPath = false;
  }

  Future<void> _loadDirectory([
    String? path,
    bool restorePathOnFailure = false,
  ]) async {
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
      _setPathText(snapshot.path);
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    } catch (error, stack) {
      silentLog('machine_terminal_file', '加载终端目录', error, stack);
      if (!mounted || generation != _loadGeneration) return;
      if (restorePathOnFailure && _snapshot != null) {
        _setPathText(_snapshot!.path);
        setState(() {
          _loading = false;
          _error = null;
        });
        showOpenHandErrorSnack(
          context,
          openHandLocalizedText(
            context,
            zh: '无法导航到该路径：$error',
            en: 'Unable to open that path: $error',
          ),
          maxLines: 3,
        );
        return;
      }
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  void _navigateToEnteredPath() {
    final snapshot = _snapshot;
    if (snapshot == null || _loading) return;
    final path = _pathController.text;
    if (path == snapshot.path) return;
    if (path.isEmpty) {
      _setPathText(snapshot.path);
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '路径不能为空。',
          en: 'The path cannot be empty.',
        ),
      );
      setState(() {});
      return;
    }
    unawaited(_loadDirectory(path, true));
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
    final searchBorder = OutlineInputBorder(
      borderRadius: kOpenHandBorderRadius8,
      borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.55)),
    );
    final pathChanged =
        snapshot != null && _pathController.text != snapshot.path;
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
          child: SizedBox(
            height: 36,
            child: TextField(
              controller: _pathController,
              enabled: snapshot != null,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _navigateToEnteredPath(),
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontFamily: kOpenHandMonospaceFontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                hintText: openHandLocalizedText(
                  context,
                  zh: '输入目录路径',
                  en: 'Enter folder path',
                ),
                prefixIcon: const Icon(Icons.route_rounded, size: 18),
                prefixIconConstraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
                border: searchBorder,
                enabledBorder: searchBorder,
                focusedBorder: searchBorder.copyWith(
                  borderSide: BorderSide(color: cs.primary, width: 1.2),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: openHandMotionDuration(context, kOpenHandMotion180),
          curve: kOpenHandSwitchInCurve,
          child: pathChanged
              ? Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _MachineTerminalIconButton(
                    icon: Icons.arrow_forward_rounded,
                    tooltip: openHandLocalizedText(
                      context,
                      zh: '前往该目录',
                      en: 'Open This Folder',
                    ),
                    onPressed: _loading ? null : _navigateToEnteredPath,
                  ),
                )
              : const SizedBox.shrink(),
        ),
        kOpenHandHGap8,
        SizedBox(
          width: 220,
          height: 36,
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
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
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        disabledBackgroundColor: Colors.transparent,
                      ),
                    ),
              suffixIconConstraints: const BoxConstraints.tightFor(
                width: 36,
                height: 36,
              ),
              border: searchBorder,
              enabledBorder: searchBorder,
              focusedBorder: searchBorder.copyWith(
                borderSide: BorderSide(color: cs.primary, width: 1.2),
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
        onTap: busy ? null : () => unawaited(_openEntry(entry)),
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
                  entry.isDirectory
                      ? _machineTerminalDirectorySizeLabel(context, entry)
                      : formatByteSize(entry.size),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
    final mediaKind = _machineTerminalMediaPreviewKind(entry);
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
        if (entry.isFile)
          _fileMenuItem(
            _MachineTerminalFileAction.download,
            Icons.download_rounded,
            openHandLocalizedText(context, zh: '下载', en: 'Download'),
          ),
        _fileMenuItem(
          _MachineTerminalFileAction.rename,
          Icons.drive_file_rename_outline_rounded,
          openHandLocalizedText(context, zh: '重命名', en: 'Rename'),
        ),
        if (mediaKind == null)
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
      case _MachineTerminalFileAction.download:
        await _downloadEntry(entry);
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

  Future<void> _openEntry(MachineTerminalFileEntry entry) async {
    if (entry.isDirectory) {
      await _loadDirectory(entry.path);
      return;
    }
    if (_isMachineTerminalFileEditable(entry)) {
      await _openTextEntry(entry, readOnly: true);
      return;
    }
    final mediaKind = _machineTerminalMediaPreviewKind(entry);
    if (mediaKind != null) await _previewMediaEntry(entry, mediaKind);
  }

  Future<void> _downloadEntry(MachineTerminalFileEntry entry) async {
    try {
      final location = await getSaveLocation(suggestedName: entry.name);
      if (!mounted || location == null) return;
      context.read<MachineTerminalFileService>().enqueueDownload(
        sessionId: widget.sessionId,
        terminalId: widget.terminalId,
        sourcePath: entry.path,
        destinationPath: location.path,
        totalBytes: entry.size,
      );
      showOpenHandSuccessSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '已加入下载任务：${location.path}',
          en: 'Download queued: ${location.path}',
        ),
        maxLines: 2,
      );
      _showTransfers();
    } catch (error, stack) {
      _showOperationError('创建下载任务', error, stack);
    }
  }

  Future<void> _previewMediaEntry(
    MachineTerminalFileEntry entry,
    MediaPreviewKind kind,
  ) async {
    final service = context.read<MachineTerminalFileService>();
    Directory? temporaryDirectory;
    await _runEntryOperation(entry.path, '预览媒体文件', () async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'openhand-terminal-preview-',
      );
      final rawExtension = p.extension(entry.name).toLowerCase();
      final extension = RegExp(r'^\.[a-z0-9]{1,12}$').hasMatch(rawExtension)
          ? rawExtension
          : '';
      final localPath = p.join(temporaryDirectory!.path, 'preview$extension');
      await service.downloadFile(
        sessionId: widget.sessionId,
        terminalId: widget.terminalId,
        sourcePath: entry.path,
        destinationPath: localPath,
      );
      if (!mounted) return;
      await showAnimatedDialog<void>(
        context: context,
        builder: (dialogContext) => MediaPreviewDialog.file(
          filePath: localPath,
          title: entry.name,
          mimeType: aiMimeTypeForPath(entry.name),
          kind: kind,
        ),
      );
    });
    final directory = temporaryDirectory;
    if (directory == null) return;
    try {
      await deletePathBounded(
        p.absolute(directory.path),
        policy: _machineTerminalPreviewDeletePolicy,
        allowedRoot: p.absolute(Directory.systemTemp.path),
      );
    } catch (error, stack) {
      silentLog('machine_terminal_file', '清理媒体预览临时文件', error, stack);
    }
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

  Future<void> _editEntry(MachineTerminalFileEntry entry) =>
      _openTextEntry(entry, readOnly: false);

  Future<void> _openTextEntry(
    MachineTerminalFileEntry entry, {
    required bool readOnly,
  }) async {
    await _runEntryOperation(
      entry.path,
      readOnly ? '读取预览文件' : '读取待编辑文件',
      () async {
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
            readOnly: readOnly,
          ),
        );
        if (readOnly || !mounted || updated == null || updated == content) {
          return;
        }
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
      },
    );
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
      title: entry.isDirectory
          ? openHandLocalizedText(context, zh: '删除目录？', en: 'Delete Folder?')
          : openHandLocalizedText(context, zh: '删除文件？', en: 'Delete File?'),
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
      (aiAttachmentKindForPath(entry.name) == AiAttachmentKind.text ||
          _machineTerminalAdditionalTextExtensions.contains(
            p.extension(entry.name).toLowerCase(),
          ));
}

MediaPreviewKind? _machineTerminalMediaPreviewKind(
  MachineTerminalFileEntry entry,
) {
  if (!entry.isFile) return null;
  return switch (aiAttachmentKindForPath(entry.name)) {
    AiAttachmentKind.image => MediaPreviewKind.image,
    AiAttachmentKind.video => MediaPreviewKind.video,
    AiAttachmentKind.audio => MediaPreviewKind.audio,
    _ => null,
  };
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

String _machineTerminalDirectorySizeLabel(
  BuildContext context,
  MachineTerminalFileEntry entry,
) => openHandLocalizedText(
  context,
  zh: '${entry.childDirectoryCount} 目录 ${entry.childFileCount} 文件',
  en: '${entry.childDirectoryCount} folders · ${entry.childFileCount} files',
);

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
        entry.isDirectory
            ? _machineTerminalDirectorySizeLabel(context, entry)
            : '${formatByteSize(entry.size)} (${entry.size} B)',
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
    required this.readOnly,
  });

  final String path;
  final String initialContent;
  final bool readOnly;

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
  double _fontSize = _editorFontSizeDefault;
  double _zoomVisualScale = 1;
  Timer? _zoomCommitTimer;

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
    _zoomCommitTimer?.cancel();
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
      canPop: widget.readOnly || !_dirty,
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
                icon: widget.readOnly
                    ? Icons.visibility_rounded
                    : Icons.edit_note_rounded,
                title: openHandLocalizedText(
                  context,
                  zh: widget.readOnly ? '预览终端文件' : '编辑终端文件',
                  en: widget.readOnly
                      ? 'Preview Terminal File'
                      : 'Edit Terminal File',
                ),
                subtitle: widget.path,
                trailingActions: widget.readOnly
                    ? const <Widget>[]
                    : <Widget>[
                        _MachineTerminalIconButton(
                          icon: Icons.save_rounded,
                          tooltip: openHandSaveLabel(context),
                          onPressed: _dirty && !exceedsLimit
                              ? () =>
                                    Navigator.of(context).pop(_controller.text)
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
                  child: _EditorZoomWrapper(
                    onZoomIn: () => _changeZoom(0.5),
                    onZoomOut: () => _changeZoom(-0.5),
                    onZoomReset: _resetZoom,
                    onZoomByScale: _zoomByScale,
                    child: RepaintBoundary(
                      child: Transform.scale(
                        scale: _zoomVisualScale,
                        alignment: Alignment.topLeft,
                        child: _SyntaxHighlightEditor(
                          controller: _controller,
                          scrollController: _scrollController,
                          focusNode: _focusNode,
                          language: _language,
                          fontSize: _fontSize,
                          readOnly: widget.readOnly,
                          wordWrap: context.select<SettingsController, bool>(
                            (controller) => controller.editorWordWrap,
                          ),
                          codeTheme: context
                              .select<SettingsController, EditorCodeTheme>(
                                (controller) => controller.editorCodeTheme,
                              ),
                          onChanged: (value) {
                            if (widget.readOnly) return;
                            final bytes = utf8.encode(value).length;
                            final dirty = value != widget.initialContent;
                            if (_contentBytes == bytes && _dirty == dirty) {
                              return;
                            }
                            setState(() {
                              _contentBytes = bytes;
                              _dirty = dirty;
                            });
                          },
                        ),
                      ),
                    ),
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
                        widget.readOnly
                            ? openHandLocalizedText(
                                context,
                                zh: '只读 · $_language · ${formatByteSize(_contentBytes)}',
                                en: 'Read only · $_language · ${formatByteSize(_contentBytes)}',
                              )
                            : exceedsLimit
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
    if (widget.readOnly || !_dirty) {
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

  void _changeZoom(double delta) {
    final next = (_fontSize + delta).clamp(
      _editorFontSizeMin,
      _editorFontSizeMax,
    );
    if (next == _fontSize) return;
    _zoomCommitTimer?.cancel();
    setState(() {
      _fontSize = next;
      _zoomVisualScale = 1;
    });
  }

  void _resetZoom() {
    if (_fontSize == _editorFontSizeDefault && _zoomVisualScale == 1) return;
    _zoomCommitTimer?.cancel();
    setState(() {
      _fontSize = _editorFontSizeDefault;
      _zoomVisualScale = 1;
    });
  }

  void _zoomByScale(double scaleDelta) {
    final next = (_fontSize * _zoomVisualScale * scaleDelta).clamp(
      _editorFontSizeMin,
      _editorFontSizeMax,
    );
    setState(() => _zoomVisualScale = next / _fontSize);
    _zoomCommitTimer?.cancel();
    _zoomCommitTimer = startSafeTimer(kOpenHandMotion180, _commitZoom);
  }

  void _commitZoom() {
    _zoomCommitTimer?.cancel();
    if ((_zoomVisualScale - 1).abs() < 0.001) return;
    setState(() {
      _fontSize = (_fontSize * _zoomVisualScale).clamp(
        _editorFontSizeMin,
        _editorFontSizeMax,
      );
      _zoomVisualScale = 1;
    });
  }
}

class _MachineTerminalTransfersDialog extends StatefulWidget {
  const _MachineTerminalTransfersDialog({
    required this.sessionId,
    required this.terminalId,
  });

  final String sessionId;
  final String terminalId;

  @override
  State<_MachineTerminalTransfersDialog> createState() =>
      _MachineTerminalTransfersDialogState();
}

class _MachineTerminalTransfersDialogState
    extends State<_MachineTerminalTransfersDialog> {
  Timer? _statsRefreshTimer;
  bool _hasActiveTransfers = false;

  @override
  void initState() {
    super.initState();
    _statsRefreshTimer = startSafePeriodicTimer(
      const Duration(milliseconds: 250),
      (_) {
        if (mounted && _hasActiveTransfers) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _statsRefreshTimer?.cancel();
    super.dispose();
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
    final service = context.watch<MachineTerminalFileService>();
    final tasks = service.transfers(
      sessionId: widget.sessionId,
      terminalId: widget.terminalId,
    );
    final active = tasks.where((task) => task.isActive).length;
    _hasActiveTransfers = active > 0;
    final uploads = tasks
        .where(
          (task) => task.direction == MachineTerminalTransferDirection.upload,
        )
        .length;
    final downloads = tasks
        .where(
          (task) => task.direction == MachineTerminalTransferDirection.download,
        )
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
                zh: '共 ${tasks.length} 项 · 上传 $uploads · 下载 $downloads · 进行中 $active',
                en: '${tasks.length} total · $uploads uploads · $downloads downloads · $active active',
              ),
              onClose: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: tasks.isEmpty
                  ? OpenHandInlineEmptyState(
                      icon: Icons.swap_vert_circle_outlined,
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
                          _MachineTerminalTransferRow(
                            key: ValueKey<String>(tasks[index].id),
                            task: tasks[index],
                          ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MachineTerminalTransferRow extends StatelessWidget {
  const _MachineTerminalTransferRow({super.key, required this.task});

  final MachineTerminalTransferTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final service = context.read<MachineTerminalFileService>();
    final statusColor = _machineTerminalTransferColor(cs, task.status);
    final directionColor = _machineTerminalTransferDirectionColor(
      cs,
      task.direction,
    );
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
                  color: directionColor.withValues(alpha: 0.12),
                  borderRadius: kOpenHandBorderRadius8,
                ),
                child: Icon(
                  _machineTerminalTransferIcon(task.status, task.direction),
                  size: 18,
                  color: directionColor,
                ),
              ),
              kOpenHandHGap10,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: directionColor.withValues(alpha: 0.12),
                            borderRadius: kOpenHandPillBorderRadius,
                          ),
                          child: Text(
                            _machineTerminalTransferDirectionLabel(
                              context,
                              task.direction,
                            ),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: directionColor,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        kOpenHandHGap8,
                        Expanded(
                          child: Text(
                            task.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    kOpenHandGap3,
                    Text(
                      '${_machineTerminalTransferStatusLabel(context, task.status)} · '
                      '${formatByteSize(task.transferredBytes)} / ${formatByteSize(task.totalBytes)} · '
                      '${_machineTerminalTransferPercent(task.progress)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                    kOpenHandGap3,
                    Text(
                      _machineTerminalTransferStatsLabel(context, task),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.primary,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                    kOpenHandGap3,
                    Text(
                      '${task.sourcePath}  →  '
                      '${task.direction == MachineTerminalTransferDirection.upload ? machineTerminalJoinPath(task.targetDirectory, task.fileName) : p.join(task.targetDirectory, task.fileName)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontFamily: kOpenHandMonospaceFontFamily,
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
            child: _MachineTerminalTransferProgressBar(
              value: task.progress,
              color: statusColor,
              backgroundColor: cs.surfaceContainerHighest,
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

class _MachineTerminalTransferProgressBar extends StatefulWidget {
  const _MachineTerminalTransferProgressBar({
    required this.value,
    required this.color,
    required this.backgroundColor,
  });

  final double value;
  final Color color;
  final Color backgroundColor;

  @override
  State<_MachineTerminalTransferProgressBar> createState() =>
      _MachineTerminalTransferProgressBarState();
}

class _MachineTerminalTransferProgressBarState
    extends State<_MachineTerminalTransferProgressBar> {
  double _displayedValue = 0;

  @override
  Widget build(BuildContext context) {
    final target = widget.value.clamp(0.0, 1.0).toDouble();
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: _displayedValue, end: target),
      duration: openHandMotionDuration(context, kOpenHandMotion220),
      curve: kOpenHandSwitchInCurve,
      builder: (context, value, _) {
        _displayedValue = value;
        return LinearProgressIndicator(
          minHeight: 7,
          value: value,
          color: widget.color,
          backgroundColor: widget.backgroundColor,
        );
      },
    );
  }
}

String _machineTerminalTransferPercent(double progress) {
  final value = (progress.clamp(0.0, 1.0) * 100).toDouble();
  if (value >= 99.95) return '100%';
  final digits = value >= 10 ? 1 : 2;
  return '${value.toStringAsFixed(digits)}%';
}

String _machineTerminalTransferDuration(Duration duration) {
  final milliseconds = duration.inMilliseconds.clamp(0, 359999999);
  final hours = milliseconds ~/ Duration.millisecondsPerHour;
  final minutes =
      (milliseconds % Duration.millisecondsPerHour) ~/
      Duration.millisecondsPerMinute;
  final seconds =
      (milliseconds % Duration.millisecondsPerMinute) ~/
      Duration.millisecondsPerSecond;
  final tenths = (milliseconds % Duration.millisecondsPerSecond) ~/ 100;
  String two(int value) => value.toString().padLeft(2, '0');
  return hours > 0
      ? '${two(hours)}:${two(minutes)}:${two(seconds)}'
      : '${two(minutes)}:${two(seconds)}.$tenths';
}

String _machineTerminalTransferStatsLabel(
  BuildContext context,
  MachineTerminalTransferTask task,
) {
  final speed = task.effectiveSpeedBytesPerSecond;
  final speedValue = speed > 0
      ? '${formatByteSize(speed)}/s'
      : openHandLocalizedText(context, zh: '计算中', en: 'Calculating');
  final elapsed = _machineTerminalTransferDuration(task.elapsed);
  final remaining = task.estimatedRemaining;
  final speedLabel = openHandLocalizedText(context, zh: '速度', en: 'Speed');
  final elapsedLabel = openHandLocalizedText(context, zh: '耗时', en: 'Elapsed');
  final etaLabel = openHandLocalizedText(context, zh: '剩余', en: 'ETA');
  return '$speedLabel $speedValue · $elapsedLabel $elapsed'
      '${remaining == null ? '' : ' · $etaLabel ${_machineTerminalTransferDuration(remaining)}'}';
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

String _machineTerminalTransferDirectionLabel(
  BuildContext context,
  MachineTerminalTransferDirection direction,
) => switch (direction) {
  MachineTerminalTransferDirection.upload => openHandLocalizedText(
    context,
    zh: '上传',
    en: 'Upload',
  ),
  MachineTerminalTransferDirection.download => openHandLocalizedText(
    context,
    zh: '下载',
    en: 'Download',
  ),
};

IconData _machineTerminalTransferIcon(
  MachineTerminalTransferStatus status,
  MachineTerminalTransferDirection direction,
) => switch (status) {
  MachineTerminalTransferStatus.queued => Icons.schedule_rounded,
  MachineTerminalTransferStatus.transferring =>
    direction == MachineTerminalTransferDirection.upload
        ? Icons.upload_rounded
        : Icons.download_rounded,
  MachineTerminalTransferStatus.paused => Icons.pause_circle_rounded,
  MachineTerminalTransferStatus.completed => Icons.check_circle_rounded,
  MachineTerminalTransferStatus.failed => Icons.error_rounded,
  MachineTerminalTransferStatus.canceled => Icons.cancel_rounded,
};

Color _machineTerminalTransferDirectionColor(
  ColorScheme cs,
  MachineTerminalTransferDirection direction,
) => switch (direction) {
  MachineTerminalTransferDirection.upload => cs.secondary,
  MachineTerminalTransferDirection.download => cs.tertiary,
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
