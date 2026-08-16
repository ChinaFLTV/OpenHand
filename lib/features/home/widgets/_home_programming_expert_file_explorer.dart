part of '../openhand_home_page.dart';

const Color _kFileExplorerWarningColor = Color(0xFFB7791F);
const Color _kFileExplorerSuccessColor = Color(0xFF2E7D32);
const Color _kFileExplorerDarkSurfaceText = Color(0xFFE5EDF5);
const Color _kFileExplorerLightSurfaceText = Color(0xFF111827);

// 文件浏览器面板。

enum _UnsavedCloseAction { save, discard, cancel }

/// 编辑器工具条容器的分隔边：贴在编辑区上方用 [top]，下方用 [bottom]。
enum _EditorToolbarEdge { top, bottom }

/// 编辑器工具条（查找 / 替换 / 跳转 / 符号 / 诊断）的统一底色与分隔线。
BoxDecoration _editorToolbarSurface(
  ColorScheme colorScheme, {
  _EditorToolbarEdge edge = _EditorToolbarEdge.bottom,
}) {
  final divider = BorderSide(
    color: colorScheme.outlineVariant.withValues(
      alpha: _editorToolbarDividerAlpha,
    ),
    width: _editorToolbarDividerWidth,
  );
  return BoxDecoration(
    color: colorScheme.surfaceContainerHigh.withValues(
      alpha: _editorToolbarSurfaceAlpha,
    ),
    border: edge == _EditorToolbarEdge.top
        ? Border(top: divider)
        : Border(bottom: divider),
  );
}

const double _editorToolbarSurfaceAlpha = 0.95;
const double _editorToolbarDividerAlpha = 0.25;
const double _editorToolbarDividerWidth = 0.5;
const double _editorToolbarFieldRadius = 6;
const double _editorToolbarFieldFontSize = 13;

/// 编辑器工具条内联输入框（查找 / 替换 / 跳转行 / 跳转符号）的统一装饰。
InputDecoration _editorToolbarInputDecoration(
  ColorScheme colorScheme, {
  String? hintText,
}) {
  final outlineBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(_editorToolbarFieldRadius),
    borderSide: BorderSide(color: colorScheme.outline.withValues(alpha: 0.3)),
  );
  return InputDecoration(
    hintText: hintText,
    hintStyle: TextStyle(
      fontSize: _editorToolbarFieldFontSize,
      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
    isDense: true,
    border: outlineBorder,
    enabledBorder: outlineBorder,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(_editorToolbarFieldRadius),
      borderSide: BorderSide(color: colorScheme.primary),
    ),
    filled: true,
    fillColor: colorScheme.surface,
  );
}

const double _kFileTreeIndentBase = 16;
const double _kFileTreeIndentPerLevel = 16;
const double _kFileTreeActiveBorderWidth = 2.5;
const double _kFileTreeRowTrailingPadding = 16;
const int _kEditorUnifiedDiffMaxMyersLineTotal = 10000;
const int _kFileExplorerDirectoryEntryLimit = 5000;
const int _kFileExplorerPopupEntryLimit = 500;
const int _kFileExplorerSearchEntryLimit = 20000;
const int _kProgrammingExplorerMaxEditableFileBytes = 2 * kBytesPerMiB;
const int _kProgrammingExplorerLspPreviewMaxBytes = 4 * kBytesPerMiB;
const BoundedCopyPolicy _kProgrammingExplorerCopyPolicy = BoundedCopyPolicy(
  maxEntries: 100000,
  maxBytes: 4 * kBytesPerGiB,
  maxDepth: 128,
  directoryIdleTimeout: Duration(seconds: 5),
  operationTimeout: Duration(minutes: 2),
  totalTimeout: Duration(minutes: 5),
);
const BoundedDeletePolicy _kProgrammingExplorerDeletePolicy =
    BoundedDeletePolicy(
      maxEntries: 100000,
      maxDepth: 128,
      directoryIdleTimeout: Duration(seconds: 5),
      operationTimeout: Duration(seconds: 30),
      totalTimeout: Duration(minutes: 5),
    );

class _DirectoryScanBudget {
  _DirectoryScanBudget(this.remaining);

  int remaining;

  bool consume() {
    if (remaining <= 0) return false;
    remaining -= 1;
    return true;
  }
}

Future<void> _setProgrammingExplorerClipboardText(
  String text, {
  required String logAction,
}) async {
  try {
    await setOpenHandClipboardText(text);
  } catch (error, stack) {
    silentLog('file_explorer', logAction, error, stack);
  }
}

class _FileExplorerPanel extends StatefulWidget {
  const _FileExplorerPanel({
    required this.rootPath,
    required this.onFileSelected,
    this.activeFilePath,
    this.onCloseRequested,
  });

  final String rootPath;
  final ValueChanged<String> onFileSelected;
  final String? activeFilePath;
  final VoidCallback? onCloseRequested;

  @override
  State<_FileExplorerPanel> createState() => _FileExplorerPanelState();
}

class _FileExplorerPanelState extends State<_FileExplorerPanel> {
  late _FileNode _rootNode;
  bool _loading = true;
  int _rootLoadGeneration = 0;
  final ScrollController _treeScrollController = ScrollController();
  final ScrollController _treeHorizontalScrollController = ScrollController();

  // 剪切、复制和粘贴状态。
  String? _clipboardPath;
  bool _clipboardIsCut = false;

  // 搜索状态。
  bool _searchActive = false;
  int _searchGeneration = 0;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final OpenHandDebouncer _searchDebounce = OpenHandDebouncer(
    delay: kOpenHandMotion220,
  );
  List<_FileNode> _searchResults = const [];
  bool _searchLoading = false;

  // 当前选中节点，供“展开所选”使用。
  String? _selectedNodePath;
  final Map<String, GlobalKey> _treeItemKeys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _rootNode = _FileNode(
      name: p.basename(widget.rootPath),
      path: widget.rootPath,
      isDirectory: true,
    );
    unawaited(_finishRootLoad(_rootNode, ++_rootLoadGeneration));
  }

  @override
  void didUpdateWidget(_FileExplorerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rootPath != widget.rootPath) {
      _searchDebounce.cancel();
      _searchGeneration++;
      _revealEpoch++;
      final root = _FileNode(
        name: p.basename(widget.rootPath),
        path: widget.rootPath,
        isDirectory: true,
      );
      setState(() {
        _loading = true;
        _selectedNodePath = null;
        _rootNode = root;
        _searchController.clear();
        _searchResults = const <_FileNode>[];
        _searchLoading = false;
      });
      unawaited(_finishRootLoad(root, ++_rootLoadGeneration));
    } else if (oldWidget.activeFilePath != widget.activeFilePath) {
      _revealActiveFile();
    }
  }

  @override
  void dispose() {
    _rootLoadGeneration++;
    _searchGeneration++;
    _revealEpoch++;
    _searchDebounce.dispose();
    _treeScrollController.dispose();
    _treeHorizontalScrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searchActive = !_searchActive;
      if (!_searchActive) {
        _searchGeneration++;
        _searchDebounce.cancel();
        _searchController.clear();
        _searchResults = const [];
        _searchLoading = false;
      }
    });
    if (_searchActive) {
      // 输入框挂载后再请求焦点，避免 macOS 文本通道错过首次连接。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_searchActive) return;
        _searchFocusNode.requestFocus();
      });
    }
  }

  void _onSearchChanged(String query) {
    _searchDebounce.cancel();
    final generation = ++_searchGeneration;
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) {
      setState(() {
        _searchResults = const [];
        _searchLoading = false;
      });
      return;
    }
    // 立即显示加载态，目录扫描延后执行以减少连续输入产生的 I/O。
    if (!_searchLoading && mounted) {
      setState(() => _searchLoading = true);
    }
    _searchDebounce.schedule(() async {
      if (!mounted || generation != _searchGeneration) return;
      await _performSearch(trimmed, generation);
    });
  }

  Future<void> _performSearch(String query, int generation) async {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) {
      if (mounted) {
        setState(() {
          _searchResults = const [];
          _searchLoading = false;
        });
      }
      return;
    }
    if (mounted) {
      setState(() => _searchLoading = true);
    }
    final rootPath = widget.rootPath;
    final results = <_FileNode>[];
    await _searchDirectory(
      Directory(rootPath),
      trimmed,
      results,
      0,
      _DirectoryScanBudget(_kFileExplorerSearchEntryLimit),
      generation,
    );
    if (!mounted ||
        generation != _searchGeneration ||
        !_searchActive ||
        rootPath != widget.rootPath ||
        _searchController.text.trim().toLowerCase() != trimmed) {
      return;
    }
    setState(() {
      _searchResults = results;
      _searchLoading = false;
    });
  }

  Future<void> _searchDirectory(
    Directory dir,
    String query,
    List<_FileNode> results,
    int depth,
    _DirectoryScanBudget budget,
    int generation,
  ) async {
    if (!mounted ||
        generation != _searchGeneration ||
        depth > 12 ||
        results.length >= 100 ||
        budget.remaining <= 0) {
      return;
    }
    try {
      final listing = await listDirectoryBounded(
        dir,
        maxEntries: math.min(
          _kFileExplorerDirectoryEntryLimit,
          budget.remaining,
        ),
      );
      final entries = listing.entries.toList(growable: false);
      entries.sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir != bIsDir) return aIsDir ? -1 : 1;
        return p
            .basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase());
      });
      for (final entry in entries) {
        if (!mounted || generation != _searchGeneration) return;
        if (!budget.consume()) return;
        if (results.length >= 100) return;
        final name = p.basename(entry.path);
        if (_isHiddenOrIgnored(name)) continue;
        if (name.toLowerCase().contains(query)) {
          results.add(
            _FileNode(
              name: name,
              path: entry.path,
              isDirectory: entry is Directory,
            ),
          );
        }
        if (entry is Directory) {
          await _searchDirectory(
            entry,
            query,
            results,
            depth + 1,
            budget,
            generation,
          );
        }
      }
    } catch (error, stack) {
      silentLog('file_explorer', '搜索目录', error, stack);
    }
  }

  /// 展开父目录并定位当前文件。
  int _revealEpoch = 0;

  Future<void> _revealActiveFile() async {
    final epoch = ++_revealEpoch;
    final active = widget.activeFilePath;
    if (active == null || !active.startsWith(widget.rootPath)) return;
    final relative = p.relative(active, from: widget.rootPath);
    final segments = p.split(relative).where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return;

    _FileNode current = _rootNode;
    for (var i = 0; i < segments.length - 1; i++) {
      if (!current.childrenLoaded) await _loadChildren(current);
      if (!mounted || epoch != _revealEpoch) return;
      final seg = segments[i];
      final match = current.children.where((c) => c.name == seg);
      if (match.isEmpty) return;
      current = match.first;
      current.isExpanded = true;
    }
    // 加载最后一级目录，确保目标文件可见。
    if (!current.childrenLoaded) await _loadChildren(current);
    if (!mounted || epoch != _revealEpoch) return;
    setState(() {
      _selectedNodePath = active;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || epoch != _revealEpoch) return;
      _scrollNodeIntoView(active);
    });
  }

  GlobalKey _treeItemKey(String path) {
    return _treeItemKeys.putIfAbsent(path, GlobalKey.new);
  }

  void _scrollNodeIntoView(String path) {
    final targetContext = _treeItemKeys[path]?.currentContext;
    if (targetContext == null) return;
    Scrollable.ensureVisible(
      targetContext,
      alignment: 0.18,
      duration: kOpenHandMotion180,
      curve: kOpenHandSwitchInCurve,
    );
  }

  Future<void> _loadChildren(_FileNode node) {
    if (!node.isDirectory || node.childrenLoaded) return Future<void>.value();
    return node.childrenLoad.run(() async {
      if (node.childrenLoaded) return;
      try {
        final dir = Directory(node.path);
        final entries = (await listDirectoryBounded(
          dir,
          maxEntries: _kFileExplorerDirectoryEntryLimit,
        )).entries.toList(growable: false);
        entries.sort((a, b) {
          final aIsDir = a is Directory;
          final bIsDir = b is Directory;
          if (aIsDir != bIsDir) return aIsDir ? -1 : 1;
          return p
              .basename(a.path)
              .toLowerCase()
              .compareTo(p.basename(b.path).toLowerCase());
        });
        final children = <_FileNode>[];
        for (final entry in entries) {
          final name = p.basename(entry.path);
          if (_isHiddenOrIgnored(name)) continue;
          children.add(
            _FileNode(
              name: name,
              path: entry.path,
              isDirectory: entry is Directory,
            ),
          );
        }
        node.children = children;
        node.childrenLoaded = true;
      } catch (error, stack) {
        silentLog('file_explorer', '加载子节点 ${node.path}', error, stack);
        node.children = const <_FileNode>[];
        node.childrenLoaded = true;
      }
    });
  }

  Future<void> _finishRootLoad(_FileNode root, int generation) async {
    await _loadChildren(root);
    if (!mounted ||
        generation != _rootLoadGeneration ||
        !identical(root, _rootNode)) {
      return;
    }
    setState(() {
      root.isExpanded = true;
      _loading = false;
    });
    unawaited(_revealActiveFile());
  }

  bool _isHiddenOrIgnored(String name) {
    if (name.startsWith('.')) return true;
    const ignored = {
      'node_modules',
      'build',
      '.dart_tool',
      '__pycache__',
      '.git',
      '.idea',
      '.vscode',
      'target',
      'dist',
      '.gradle',
    };
    return ignored.contains(name);
  }

  Future<void> _toggleExpand(_FileNode node) async {
    if (!node.isDirectory) return;
    if (!node.childrenLoaded) {
      await _loadChildren(node);
    }
    if (!mounted) return;
    setState(() => node.isExpanded = !node.isExpanded);
  }

  /// 定位并选中当前文件。
  Future<void> _selectOpenedFile() async {
    await _revealActiveFile();
  }

  /// 递归展开选中的目录节点。
  Future<void> _expandSelected() async {
    final targetPath = _selectedNodePath ?? widget.activeFilePath;
    if (targetPath == null) return;
    var node = _findNodeByPath(_rootNode, targetPath);
    if (node == null && widget.activeFilePath != null) {
      await _revealActiveFile();
      node = _findNodeByPath(_rootNode, targetPath);
    }
    if (node != null && !node.isDirectory) {
      node = _findNodeByPath(_rootNode, p.dirname(node.path));
    }
    if (node == null || !node.isDirectory) return;
    await _expandRecursive(node, 0);
    final expandedPath = node.path;
    if (!mounted) return;
    setState(() => _selectedNodePath = expandedPath);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollNodeIntoView(expandedPath);
    });
  }

  Future<void> _expandRecursive(_FileNode node, int depth) async {
    if (!mounted || !node.isDirectory || depth > 12) return;
    if (!node.childrenLoaded) await _loadChildren(node);
    if (!mounted) return;
    node.isExpanded = true;
    for (final child in node.children) {
      if (!mounted) return;
      if (child.isDirectory) {
        await _expandRecursive(child, depth + 1);
      }
    }
  }

  /// 折叠所有已展开目录。
  void _collapseAll() {
    for (final child in _rootNode.children) {
      if (child.isDirectory) {
        _collapseNode(child);
      }
    }
    _rootNode.isExpanded = true;
    setState(() {});
  }

  void _collapseNode(_FileNode node) {
    node.isExpanded = false;
    for (final child in node.children) {
      if (child.isDirectory) _collapseNode(child);
    }
  }

  _FileNode? _findNodeByPath(_FileNode current, String targetPath) {
    if (current.path == targetPath) return current;
    for (final child in current.children) {
      if (targetPath.startsWith(child.path)) {
        final found = _findNodeByPath(child, targetPath);
        if (found != null) return found;
      }
    }
    return null;
  }

  Future<void> _refreshNode(_FileNode node) async {
    node.childrenLoaded = false;
    node.children = const [];
    await _loadChildren(node);
    if (mounted) setState(() {});
  }

  Future<void> _refreshRoot() async {
    final root = _rootNode;
    root.childrenLoaded = false;
    root.children = const <_FileNode>[];
    await _loadChildren(root);
    if (mounted && identical(root, _rootNode)) setState(() {});
  }

  _FileNode? _findParentNode(_FileNode current, String childPath) {
    for (final child in current.children) {
      if (child.path == childPath) return current;
      if (child.isDirectory && child.childrenLoaded) {
        final found = _findParentNode(child, childPath);
        if (found != null) return found;
      }
    }
    return null;
  }

  Future<void> _handleContextMenuAction(
    String action,
    _FileNode node,
    Offset tapPosition,
  ) async {
    switch (action) {
      case 'rename':
        await _renameNode(node);
      case 'cut':
        _clipboardPath = node.path;
        _clipboardIsCut = true;
      case 'copy':
        _clipboardPath = node.path;
        _clipboardIsCut = false;
      case 'paste':
        await _pasteToNode(node);
      case 'delete':
        await _deleteNode(node);
      case 'open_in_finder':
        await _openInSystemExplorer(node);
      case 'copy_path':
        await _showCopyPathMenu(node, tapPosition);
    }
  }

  Future<void> _showCopyPathMenu(_FileNode node, Offset position) async {
    if (!mounted) return;
    final rootPath = widget.rootPath;
    final absolutePath = node.path;
    final fileName = node.name;
    final relativeFromRoot = p.relative(node.path, from: rootPath);

    final selected = await showAnimatedMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'abs',
          child: Row(
            children: [
              Expanded(
                child: Text(
                  openHandLocalizedText(
                    context,
                    zh: '绝对路径',
                    zhHant: '絕對路徑',
                    en: 'Absolute Path',
                    fr: 'Chemin absolu',
                    de: 'Absoluter Pfad',
                    ja: '絶対パス',
                  ),
                ),
              ),
              kOpenHandHGap16,
              Text(
                '⇧⌘C',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'name',
          child: Text(
            openHandLocalizedText(
              context,
              zh: '文件名',
              zhHant: '檔案名稱',
              en: 'File Name',
              fr: 'Nom du fichier',
              de: 'Dateiname',
              ja: 'ファイル名',
            ),
          ),
        ),
        PopupMenuItem<String>(
          value: 'content_root',
          child: Text(
            openHandLocalizedText(
              context,
              zh: '内容根目录相对路径',
              zhHant: '內容根目錄相對路徑',
              en: 'Path from Content Root',
              fr: 'Chemin depuis la racine du contenu',
              de: 'Pfad ab Inhaltswurzel',
              ja: 'コンテンツルートからのパス',
            ),
          ),
        ),
        PopupMenuItem<String>(
          value: 'repo_root',
          child: Text(
            openHandLocalizedText(
              context,
              zh: '仓库根目录相对路径',
              zhHant: '倉庫根目錄相對路徑',
              en: 'Path from Repository Root',
              fr: 'Chemin depuis la racine du dépôt',
              de: 'Pfad ab Repository-Wurzel',
              ja: 'リポジトリルートからのパス',
            ),
          ),
        ),
      ],
    );
    if (selected == null || !mounted) return;
    final textToCopy = switch (selected) {
      'abs' => absolutePath,
      'name' => fileName,
      'content_root' => relativeFromRoot,
      'repo_root' => relativeFromRoot,
      _ => absolutePath,
    };
    await copyOpenHandTextToClipboard(
      logTag: 'home',
      context: context,
      text: textToCopy,
      logAction: '复制编程资源管理器路径',
      successMessage: openHandPathCopiedLabel(context),
    );
  }

  Future<void> _renameNode(_FileNode node) async {
    final newName = await showOpenHandTextInputDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '重命名',
        zhHant: '重新命名',
        en: 'Rename',
        fr: 'Renommer',
        de: 'Umbenennen',
        ja: '名前を変更',
      ),
      initialValue: node.name,
      hintText: openHandLocalizedText(
        context,
        zh: '输入新名称',
        zhHant: '輸入新名稱',
        en: 'Enter new name',
        fr: 'Saisir le nouveau nom',
        de: 'Neuen Namen eingeben',
        ja: '新しい名前を入力',
      ),
      cancelLabel: openHandCancelLabel(context),
      confirmLabel: openHandOkLabel(context),
    );
    if (newName == null || newName == node.name) return;
    try {
      if (!isPortableFileNamePart(newName)) {
        throw FileSystemException('文件名包含不支持的字符。', newName);
      }
      final parentDir = p.dirname(node.path);
      final newPath = p.join(parentDir, newName);
      if (!isPathWithinOrEqual(widget.rootPath, newPath)) {
        throw FileSystemException('重命名目标超出工作区。', newPath);
      }
      if (await FileSystemEntity.type(
            newPath,
            followLinks: false,
          ).timeout(_kProgrammingExplorerCopyPolicy.operationTimeout) !=
          FileSystemEntityType.notFound) {
        throw FileSystemException('重命名目标已存在。', newPath);
      }
      await _renameEntityBounded(
        sourcePath: node.path,
        targetPath: newPath,
        isDirectory: node.isDirectory,
        onLateSuccess: _refreshRoot,
      );
      final parent = _findParentNode(_rootNode, node.path) ?? _rootNode;
      await _refreshNode(parent);
    } catch (error, stack) {
      silentLog('file_explorer', '重命名节点', error, stack);
    }
  }

  Future<void> _deleteNode(_FileNode node) async {
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '删除确认',
        zhHant: '刪除確認',
        en: 'Confirm Delete',
        fr: 'Confirmer la suppression',
        de: 'Löschen bestätigen',
        ja: '削除の確認',
      ),
      message: openHandLocalizedText(
        context,
        zh: '确定要删除 "${node.name}" 吗？此操作不可撤销。',
        zhHant: '確定要刪除 "${node.name}" 嗎？此操作無法復原。',
        en: 'Are you sure you want to delete "${node.name}"? This cannot be undone.',
        fr: 'Voulez-vous vraiment supprimer "${node.name}" ? Cette action est irréversible.',
        de: 'Möchtest du "${node.name}" wirklich löschen? Dies kann nicht rückgängig gemacht werden.',
        ja: '"${node.name}" を削除しますか？この操作は元に戻せません。',
      ),
      cancelLabel: openHandCancelLabel(context),
      confirmLabel: openHandDeleteLabel(context),
      destructive: true,
    );
    if (confirmed != true) return;
    try {
      await deletePathBounded(
        p.absolute(node.path),
        policy: _kProgrammingExplorerDeletePolicy,
        allowMissing: false,
        allowedRoot: p.absolute(widget.rootPath),
      );
      final parent = _findParentNode(_rootNode, node.path) ?? _rootNode;
      await _refreshNode(parent);
    } catch (error, stack) {
      silentLog('file_explorer', '删除节点', error, stack);
    }
  }

  Future<void> _pasteToNode(_FileNode node) async {
    final sourcePath = _clipboardPath;
    if (sourcePath == null) return;
    try {
      final targetDir = node.isDirectory ? node.path : p.dirname(node.path);
      final name = p.basename(sourcePath);
      final targetPath = p.join(targetDir, name);
      if (p.equals(p.normalize(targetPath), p.normalize(sourcePath))) return;
      if (!isPathWithinOrEqual(widget.rootPath, targetPath)) {
        throw FileSystemException('粘贴目标超出工作区。', targetPath);
      }
      final sourceEntity = await FileSystemEntity.type(
        sourcePath,
        followLinks: false,
      ).timeout(_kProgrammingExplorerCopyPolicy.operationTimeout);
      if (sourceEntity == FileSystemEntityType.notFound) return;
      if (sourceEntity != FileSystemEntityType.directory &&
          sourceEntity != FileSystemEntityType.file) {
        throw FileSystemException('只能粘贴普通文件和目录。', sourcePath);
      }
      if (sourceEntity == FileSystemEntityType.directory &&
          p.isWithin(p.normalize(sourcePath), p.normalize(targetPath))) {
        throw FileSystemException('目录不能粘贴到自身内部。', targetPath);
      }
      if (sourceEntity == FileSystemEntityType.directory &&
          _clipboardIsCut &&
          await isPhysicalPathWithinOrEqual(
            sourcePath,
            targetPath,
          ).timeout(_kProgrammingExplorerCopyPolicy.operationTimeout)) {
        throw FileSystemException('目录不能移动到自身内部。', targetPath);
      }
      if (await FileSystemEntity.type(
            targetPath,
            followLinks: false,
          ).timeout(_kProgrammingExplorerCopyPolicy.operationTimeout) !=
          FileSystemEntityType.notFound) {
        throw FileSystemException('粘贴目标已存在。', targetPath);
      }
      if (_clipboardIsCut) {
        await _renameEntityBounded(
          sourcePath: sourcePath,
          targetPath: targetPath,
          isDirectory: sourceEntity == FileSystemEntityType.directory,
          onLateSuccess: () async {
            if (_clipboardIsCut && _clipboardPath == sourcePath) {
              _clipboardPath = null;
              _clipboardIsCut = false;
            }
            await _refreshRoot();
          },
        );
        _clipboardPath = null;
        _clipboardIsCut = false;
      } else {
        if (sourceEntity == FileSystemEntityType.directory) {
          await copyDirectoryBounded(
            Directory(sourcePath),
            Directory(targetPath),
            policy: _kProgrammingExplorerCopyPolicy,
          );
        } else {
          await copyFileBounded(
            File(sourcePath),
            File(targetPath),
            policy: _kProgrammingExplorerCopyPolicy,
          );
        }
      }
      await _refreshRoot();
    } catch (error, stack) {
      silentLog('file_explorer', '粘贴节点', error, stack);
      if (!mounted) return;
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '粘贴失败：$error',
          zhHant: '貼上失敗：$error',
          en: 'Paste failed: $error',
          fr: 'Échec du collage : $error',
          de: 'Einfügen fehlgeschlagen: $error',
          ja: '貼り付けに失敗しました: $error',
        ),
        maxLines: 3,
      );
    }
  }

  Future<void> _renameEntityBounded({
    required String sourcePath,
    required String targetPath,
    required bool isDirectory,
    required Future<void> Function() onLateSuccess,
  }) async {
    final rename = isDirectory
        ? Directory(sourcePath).rename(targetPath).then<void>((_) {})
        : File(sourcePath).rename(targetPath).then<void>((_) {});
    try {
      await rename.timeout(_kProgrammingExplorerCopyPolicy.operationTimeout);
    } on TimeoutException {
      unawaited(
        rename.then<void>(
          (_) async {
            if (!mounted) return;
            try {
              await onLateSuccess();
            } catch (error, stack) {
              silentLog('file_explorer', '刷新迟到重命名结果', error, stack);
            }
          },
          onError: (Object error, StackTrace stack) {
            silentLog('file_explorer', '完成迟到重命名', error, stack);
          },
        ),
      );
      rethrow;
    }
  }

  Future<void> _openInSystemExplorer(_FileNode node) async {
    final target = node.isDirectory ? node.path : p.dirname(node.path);
    try {
      await openLocalPathWithSystemApp(
        target,
        tag: 'file_explorer.open_node_in_system_explorer',
      );
    } catch (error, stack) {
      silentLog('file_explorer', '在系统文件管理器中打开节点', error, stack);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    if (_loading) {
      return Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: colorScheme.primary,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Material(
                color: Colors.transparent,
                borderRadius: kOpenHandPillBorderRadius,
                child: InkWell(
                  borderRadius: kOpenHandPillBorderRadius,
                  onTap: _toggleSearch,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      _searchActive
                          ? Icons.search_off_rounded
                          : Icons.search_rounded,
                      size: 16,
                      color: _searchActive
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              kOpenHandHGap2,
              // Select Opened File (scroll-from-source)
              Tooltip(
                message: AppLocalizations.of(
                  context,
                )!.progExpFESelectOpenedFile,
                child: Material(
                  color: Colors.transparent,
                  borderRadius: kOpenHandPillBorderRadius,
                  child: InkWell(
                    borderRadius: kOpenHandPillBorderRadius,
                    onTap: _selectOpenedFile,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.my_location_rounded,
                        size: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
              kOpenHandHGap2,
              // Expand Selected
              Tooltip(
                message: AppLocalizations.of(context)!.progExpFEExpandSelected,
                child: Material(
                  color: Colors.transparent,
                  borderRadius: kOpenHandPillBorderRadius,
                  child: InkWell(
                    borderRadius: kOpenHandPillBorderRadius,
                    onTap: _expandSelected,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.unfold_more_rounded,
                        size: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
              kOpenHandHGap2,
              // Collapse All
              Tooltip(
                message: AppLocalizations.of(context)!.progExpFECollapseAll,
                child: Material(
                  color: Colors.transparent,
                  borderRadius: kOpenHandPillBorderRadius,
                  child: InkWell(
                    borderRadius: kOpenHandPillBorderRadius,
                    onTap: _collapseAll,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.unfold_less_rounded,
                        size: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
              kOpenHandHGap2,
              Material(
                color: Colors.transparent,
                borderRadius: kOpenHandPillBorderRadius,
                child: InkWell(
                  borderRadius: kOpenHandPillBorderRadius,
                  onTap: _refreshRoot,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.refresh_rounded,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              if (widget.onCloseRequested != null) ...[
                const Spacer(),
                Tooltip(
                  message: l10n.toolbarFilesHide,
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: kOpenHandPillBorderRadius,
                    child: InkWell(
                      borderRadius: kOpenHandPillBorderRadius,
                      onTap: widget.onCloseRequested,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        // Search input field.
        if (_searchActive) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                autofocus: true,
                style: theme.textTheme.bodySmall,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  hintText: openHandLocalizedText(
                    context,
                    zh: '搜索文件或目录…',
                    zhHant: '搜尋檔案或目錄…',
                    en: 'Search files…',
                    fr: 'Rechercher des fichiers…',
                    de: 'Dateien suchen…',
                    ja: 'ファイルを検索…',
                  ),
                  hintStyle: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(left: 8, right: 4),
                    child: Icon(
                      Icons.search_rounded,
                      size: 16,
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.6,
                      ),
                    ),
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 28,
                    maxHeight: 36,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? OpenHandTapRegion(
                          onTap: () {
                            _searchController.clear();
                            _onSearchChanged('');
                            _searchFocusNode.requestFocus();
                          },
                          child: Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.close_rounded,
                              size: 14,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : null,
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 24,
                    maxHeight: 36,
                  ),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  border: const OutlineInputBorder(borderRadius: kOpenHandBorderRadius12, borderSide: BorderSide.none),
                  enabledBorder: const OutlineInputBorder(borderRadius: kOpenHandBorderRadius12, borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: kOpenHandBorderRadius12,
                    borderSide: BorderSide(
                      color: colorScheme.primary.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ),
          ),
          kOpenHandGap4,
        ],
        Divider(
          height: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
        Expanded(
          child: _searchActive && _searchController.text.trim().isNotEmpty
              ? _buildSearchResults(theme, colorScheme)
              : _buildScrollableTree(),
        ),
      ],
    );
  }

  Widget _buildScrollableTree() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return OpenHandSafeScrollbar(
          controller: _treeHorizontalScrollController,
          thumbVisibility: true,
          notificationPredicate: (notification) =>
              notification.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: _treeHorizontalScrollController,
            scrollDirection: Axis.horizontal,
            primary: false,
            padding: const EdgeInsets.only(bottom: 10),
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: SingleChildScrollView(
                controller: _treeScrollController,
                primary: false,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _buildVisibleTree(
                    _rootNode.children,
                    constraints.maxWidth,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchResults(ThemeData theme, ColorScheme colorScheme) {
    if (_searchLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_searchResults.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            openHandLocalizedText(
              context,
              zh: '未找到匹配项',
              zhHant: '找不到相符項目',
              en: 'No matches found',
              fr: 'Aucun résultat',
              de: 'Keine Treffer',
              ja: '一致する項目はありません',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final node = _searchResults[index];
        final relativePath = p.relative(node.path, from: widget.rootPath);
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              if (node.isDirectory) {
                _toggleExpand(node);
              } else {
                widget.onFileSelected(node.path);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    _fileExplorerIcon(node),
                    size: 16,
                    color: node.isDirectory
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                  kOpenHandHGap8,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          node.name,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          relativePath,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.6,
                            ),
                            fontSize: 10,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 构建可见树，并丢弃本轮未出现的行 key。
  ///
  /// [_treeItemKeys] 按路径缓存 GlobalKey，只增不减的话，折叠、刷新、切目录
  /// 途经过的每条路径都会在框架的全局 key 注册表里常驻；大仓浏览久了就是纯
  /// 泄漏。这里以「本轮可见路径」为准做一次差集回收。
  List<Widget> _buildVisibleTree(
    List<_FileNode> nodes,
    double visibleMinWidth,
  ) {
    final visited = <String>{};
    final tree = _buildTree(nodes, 0, visibleMinWidth, visited);
    if (_treeItemKeys.length > visited.length) {
      _treeItemKeys.removeWhere((path, _) => !visited.contains(path));
    }
    return tree;
  }

  List<Widget> _buildTree(
    List<_FileNode> nodes,
    int depth,
    double visibleMinWidth,
    Set<String> visited,
  ) {
    final result = <Widget>[];
    for (final node in nodes) {
      visited.add(node.path);
      result.add(
        _FileTreeTile(
          key: _treeItemKey(node.path),
          node: node,
          depth: depth,
          visibleMinWidth: visibleMinWidth,
          isActive: widget.activeFilePath == node.path,
          isSelected: _selectedNodePath == node.path,
          hasClipboard: _clipboardPath != null,
          rootPath: widget.rootPath,
          onTap: () {
            setState(() => _selectedNodePath = node.path);
            if (node.isDirectory) {
              _toggleExpand(node);
            } else {
              widget.onFileSelected(node.path);
            }
          },
          onContextMenuAction: (action, position) =>
              _handleContextMenuAction(action, node, position),
        ),
      );
      if (node.isDirectory && node.isExpanded) {
        result.addAll(
          _buildTree(node.children, depth + 1, visibleMinWidth, visited),
        );
      }
    }
    return result;
  }
}

class _FileNode {
  _FileNode({
    required this.name,
    required this.path,
    required this.isDirectory,
  });

  final String name;
  final String path;
  final bool isDirectory;
  bool isExpanded = false;
  bool childrenLoaded = false;
  final OpenHandSingleFlight<void> childrenLoad = OpenHandSingleFlight<void>();
  List<_FileNode> children = const [];
}

class _FileTreeTile extends StatelessWidget {
  const _FileTreeTile({
    super.key,
    required this.node,
    required this.depth,
    required this.visibleMinWidth,
    required this.onTap,
    required this.onContextMenuAction,
    required this.rootPath,
    this.isActive = false,
    this.isSelected = false,
    this.hasClipboard = false,
  });

  final _FileNode node;
  final int depth;
  final double visibleMinWidth;
  final VoidCallback onTap;
  final void Function(String action, Offset position) onContextMenuAction;
  final String rootPath;
  final bool isActive;
  final bool isSelected;
  final bool hasClipboard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final indent = _kFileTreeIndentBase + depth * _kFileTreeIndentPerLevel;
    final text = openHandTextResolver(context);

    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      fontWeight: node.isDirectory
          ? FontWeight.w600
          : isActive
          ? FontWeight.w600
          : FontWeight.w400,
      color: isActive ? colorScheme.onPrimaryContainer : null,
    );
    final rowMinWidth =
        indent +
        16 +
        4 +
        16 +
        6 +
        _measureFileTreeLabelWidth(context, node.name, labelStyle) +
        _kFileTreeRowTrailingPadding;
    final effectiveRowMinWidth = rowMinWidth > visibleMinWidth
        ? rowMinWidth
        : visibleMinWidth;

    Offset? lastTapPosition;
    return GestureDetector(
      onSecondaryTapDown: (details) async {
        lastTapPosition = details.globalPosition;
        final selected = await showAnimatedMenu<String>(
          context: context,
          position: RelativeRect.fromLTRB(
            details.globalPosition.dx,
            details.globalPosition.dy,
            details.globalPosition.dx,
            details.globalPosition.dy,
          ),
          items: [
            PopupMenuItem<String>(
              value: 'rename',
              child: Row(
                children: [
                  const Icon(Icons.drive_file_rename_outline, size: 18),
                  kOpenHandHGap8,
                  Text(
                    text(
                      zh: '重命名',
                      zhHant: '重新命名',
                      en: 'Rename',
                      fr: 'Renommer',
                      de: 'Umbenennen',
                      ja: '名前を変更',
                    ),
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem<String>(
              value: 'cut',
              child: Row(
                children: [
                  const Icon(Icons.content_cut_rounded, size: 18),
                  kOpenHandHGap8,
                  Text(
                    text(
                      zh: '剪切',
                      zhHant: '剪下',
                      en: 'Cut',
                      fr: 'Couper',
                      de: 'Ausschneiden',
                      ja: '切り取り',
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'copy',
              child: Row(
                children: [
                  const Icon(Icons.content_copy_rounded, size: 18),
                  kOpenHandHGap8,
                  Text(
                    text(
                      zh: '复制',
                      zhHant: '複製',
                      en: 'Copy',
                      fr: 'Copier',
                      de: 'Kopieren',
                      ja: 'コピー',
                    ),
                  ),
                ],
              ),
            ),
            if (hasClipboard)
              PopupMenuItem<String>(
                value: 'paste',
                child: Row(
                  children: [
                    const Icon(Icons.content_paste_rounded, size: 18),
                    kOpenHandHGap8,
                    Text(
                      text(
                        zh: '粘贴',
                        zhHant: '貼上',
                        en: 'Paste',
                        fr: 'Coller',
                        de: 'Einfügen',
                        ja: '貼り付け',
                      ),
                    ),
                  ],
                ),
              ),
            const PopupMenuDivider(),
            PopupMenuItem<String>(
              value: 'copy_path',
              child: Row(
                children: [
                  const Icon(Icons.link_rounded, size: 18),
                  kOpenHandHGap8,
                  Expanded(
                    child: Text(
                      text(
                        zh: '复制路径/引用',
                        zhHant: '複製路徑/引用',
                        en: 'Copy Path/Reference',
                        fr: 'Copier chemin/référence',
                        de: 'Pfad/Referenz kopieren',
                        ja: 'パス/参照をコピー',
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem<String>(
              value: 'delete',
              child: Row(
                children: [
                  Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: colorScheme.error,
                  ),
                  kOpenHandHGap8,
                  Text(
                    text(
                      zh: '删除',
                      zhHant: '刪除',
                      en: 'Delete',
                      fr: 'Supprimer',
                      de: 'Löschen',
                      ja: '削除',
                    ),
                    style: TextStyle(color: colorScheme.error),
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem<String>(
              value: 'open_in_finder',
              child: Row(
                children: [
                  const Icon(Icons.folder_open_outlined, size: 18),
                  kOpenHandHGap8,
                  Text(
                    text(
                      zh: '在系统文件浏览器中打开',
                      zhHant: '在系統檔案瀏覽器中開啟',
                      en: 'Open in System Explorer',
                      fr: 'Ouvrir dans l’explorateur système',
                      de: 'Im System-Dateimanager öffnen',
                      ja: 'システムファイルブラウザで開く',
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
        if (selected == null || !context.mounted) return;
        onContextMenuAction(selected, lastTapPosition!);
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: BoxConstraints(minWidth: effectiveRowMinWidth),
            decoration: isActive
                ? BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.35),
                    border: Border(
                      left: BorderSide(
                        color: colorScheme.primary,
                        width: _kFileTreeActiveBorderWidth,
                      ),
                    ),
                  )
                : isSelected
                ? BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                  )
                : null,
            padding: EdgeInsets.only(
              left: isActive ? indent - _kFileTreeActiveBorderWidth : indent,
              right: 8,
              top: 4,
              bottom: 4,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (node.isDirectory)
                  AnimatedRotation(
                    turns: node.isExpanded ? 0.25 : 0,
                    duration: openHandMotionDuration(context, kOpenHandMotion200,
                    ),
                    curve: kOpenHandSwitchInCurve,
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: isActive
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  kOpenHandHGap16,
                kOpenHandHGap4,
                Icon(
                  _fileExplorerIcon(node),
                  size: 16,
                  color: node.isDirectory
                      ? colorScheme.primary
                      : isActive
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                kOpenHandHGap6,
                Text(
                  node.name,
                  style: labelStyle,
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

double _measureFileTreeLabelWidth(
  BuildContext context,
  String label,
  TextStyle? style,
) {
  final painter = TextPainter(
    text: TextSpan(text: label, style: style),
    textDirection: Directionality.of(context),
    maxLines: 1,
  )..layout();
  return painter.width.ceilToDouble();
}

/// 按文件名后缀取图标。文件树与 @ 提及列表共用，避免同一类文件在两处显示
/// 不同图标（此前两份名单各自缺了 .vue / .lock / .txt 等条目）。
IconData openHandFileNameIcon(String fileName) {
  return switch (p.extension(fileName).toLowerCase()) {
    '.dart' ||
    '.py' ||
    '.go' ||
    '.rs' ||
    '.java' ||
    '.kt' ||
    '.swift' ||
    '.c' ||
    '.cpp' ||
    '.h' ||
    '.hpp' ||
    '.xml' => Icons.code_rounded,
    '.js' || '.jsx' || '.ts' || '.tsx' => Icons.javascript_rounded,
    '.json' => Icons.data_object_rounded,
    '.yaml' || '.yml' => Icons.settings_rounded,
    '.md' => Icons.article_rounded,
    '.html' || '.htm' || '.vue' => Icons.web_rounded,
    '.css' || '.scss' || '.less' => Icons.palette_rounded,
    '.png' ||
    '.jpg' ||
    '.jpeg' ||
    '.gif' ||
    '.svg' ||
    '.webp' => Icons.image_rounded,
    '.sh' || '.bash' || '.zsh' => Icons.terminal_rounded,
    '.lock' => Icons.lock_rounded,
    '.sql' => Icons.storage_rounded,
    '.txt' || '.log' => Icons.description_rounded,
    _ => Icons.insert_drive_file_rounded,
  };
}

IconData _fileExplorerIcon(_FileNode node) {
  return node.isDirectory
      ? Icons.folder_rounded
      : openHandFileNameIcon(node.name);
}

String? _editorLanguageFromPath(String filePath) {
  final ext = p.extension(filePath).toLowerCase();
  return switch (ext) {
    '.dart' => 'dart',
    '.py' => 'python',
    '.js' => 'javascript',
    '.jsx' => 'javascript',
    '.ts' => 'typescript',
    '.tsx' => 'typescript',
    '.json' => 'json',
    '.yaml' || '.yml' => 'yaml',
    '.md' => 'markdown',
    '.html' || '.htm' => 'html',
    '.css' => 'css',
    '.scss' => 'scss',
    '.less' => 'less',
    '.xml' => 'xml',
    '.sql' => 'sql',
    '.go' => 'go',
    '.rs' => 'rust',
    '.java' => 'java',
    '.kt' => 'kotlin',
    '.swift' => 'swift',
    '.c' => 'c',
    '.cpp' || '.cc' || '.cxx' => 'cpp',
    '.h' || '.hpp' => 'cpp',
    '.sh' || '.bash' || '.zsh' => 'bash',
    '.rb' => 'ruby',
    '.php' => 'php',
    '.lua' => 'lua',
    '.r' => 'r',
    '.toml' => 'ini',
    '.ini' || '.cfg' => 'ini',
    '.gradle' => 'groovy',
    '.groovy' => 'groovy',
    '.dockerfile' => 'dockerfile',
    _ => null,
  };
}

String _resolveEditorLanguage({
  required String filePath,
  required String projectLanguage,
}) {
  final detected = _editorLanguageFromPath(filePath);
  if (detected != null) {
    return detected;
  }
  if (projectLanguage.isNotEmpty && projectLanguage != 'mixed') {
    return projectLanguage;
  }
  return 'plaintext';
}

String _inferWorkspaceRoot(String filePath) {
  return standardWorkspaceRootResolver.cachedOrFallback(filePath);
}

Future<String> _inferWorkspaceRootAsync(String filePath) {
  return standardWorkspaceRootResolver.resolve(filePath);
}

enum _EditorTabMenuAction {
  close,
  closeOthers,
  closeAll,
  closeUnmodified,
  closeLeft,
  closeRight,
  copyPathReference,
}

enum _ProjectToolchainTreeNodeTone { active, info, muted, warning, success }

class _ProjectToolchainTreeNode {
  const _ProjectToolchainTreeNode({
    required this.title,
    required this.description,
    required this.tone,
    this.icon = Icons.account_tree_rounded,
    this.badge,
    this.children = const <_ProjectToolchainTreeNode>[],
  });

  final String title;
  final String description;
  final _ProjectToolchainTreeNodeTone tone;
  final IconData icon;
  final String? badge;
  final List<_ProjectToolchainTreeNode> children;
}

// ─────────────────────────────────────────────────────────────────────────────
// Code Editor View — IDEA-style editor with Material You Expressive
// ─────────────────────────────────────────────────────────────────────────────

class _CodeEditorView extends StatefulWidget {
  const _CodeEditorView({
    required this.openFiles,
    required this.activeFilePath,
    required this.onOpenFile,
    required this.onTabSelected,
    required this.onTabClosed,
    required this.onCloseAll,
    required this.onReorderTabs,
    this.onToggleFileExplorer,
    this.fileExplorerVisible = false,
    this.projectLanguage = 'mixed',
    this.projectSdkPath = '',
    this.projectLspPath = '',
  });

  final List<String> openFiles;
  final String activeFilePath;
  final ValueChanged<String> onOpenFile;
  final ValueChanged<String> onTabSelected;
  final ValueChanged<String> onTabClosed;
  final VoidCallback onCloseAll;
  final void Function(int oldIndex, int newIndex) onReorderTabs;
  final VoidCallback? onToggleFileExplorer;
  final bool fileExplorerVisible;

  /// The configured project language ('dart', 'python', 'mixed', etc).
  final String projectLanguage;
  final String projectSdkPath;
  final String projectLspPath;

  @override
  State<_CodeEditorView> createState() => _CodeEditorViewState();
}

class _CodeEditorViewState extends State<_CodeEditorView>
    with TickerProviderStateMixin {
  static const Duration _editorLspDiagnosticsDebounce = Duration(
    milliseconds: 200,
  );
  static const Duration _editorLspSymbolsDebounce = Duration(milliseconds: 260);

  String _editorText({
    required String zh,
    String? zhHant,
    required String en,
    String? fr,
    String? de,
    String? ja,
  }) {
    return openHandLocalizedText(
      context,
      zh: zh,
      zhHant: zhHant,
      en: en,
      fr: fr,
      de: de,
      ja: ja,
    );
  }

  final Map<String, String?> _fileContents = {};
  final Map<String, bool> _fileLoading = {};
  final Map<String, bool> _fileDirty = {};
  final Map<String, int> _fileLoadGenerations = <String, int>{};
  final Map<String, ScrollController> _scrollControllers = {};
  final Map<String, _HighlightingTextController> _textControllers = {};
  final Map<String, FocusNode> _focusNodes = {};
  final Set<String> _forcedFullEditorFiles = <String>{};
  final Map<String, AiLspBackendResolution> _lspBackendByFile =
      <String, AiLspBackendResolution>{};
  final Set<String> _lspBackendLoadingFiles = <String>{};
  final Map<String, Future<AiLspBackendResolution>> _lspBackendRequests =
      <String, Future<AiLspBackendResolution>>{};
  final Map<String, Timer> _lspDiagnosticsTimers = <String, Timer>{};
  final Map<String, Object> _lspDiagnosticsRequestTokens = <String, Object>{};
  int _nextFileLoadGeneration = 0;

  /// Mutable font size for pinch / Cmd+scroll zoom.
  double _fontSize = _editorFontSizeDefault;

  /// Visual scale applied via Transform.scale during continuous zoom gestures.
  /// 1.0 means no transform; >1 means zoom-in, <1 means zoom-out.
  double _zoomVisualScale = 1.0;
  Timer? _zoomCommitTimer;

  // ── Find & Replace state ──
  bool _findBarVisible = false;
  bool _replaceBarVisible = false;
  final TextEditingController _findController = TextEditingController();
  final TextEditingController _replaceController = TextEditingController();
  final FocusNode _findFocusNode = FocusNode();
  List<int> _findMatchOffsets = const [];
  int _currentMatchIndex = -1;
  bool _findCaseSensitive = false;

  // ── Go To Line state ──
  bool _goToLineVisible = false;
  final TextEditingController _goToLineController = TextEditingController();
  final FocusNode _goToLineFocusNode = FocusNode();

  // ── Symbol navigation state ──
  bool _symbolBarVisible = false;
  bool _workspaceSymbolMode = false;
  final TextEditingController _symbolController = TextEditingController();
  final FocusNode _symbolFocusNode = FocusNode();
  List<_EditorSymbol> _allSymbols = const [];
  List<_EditorSymbol> _visibleSymbols = const [];
  bool _symbolsTruncated = false;
  bool _symbolsLoading = false;
  bool _symbolsUsingLsp = false;
  String? _symbolHintMessage;
  Timer? _symbolRefreshTimer;
  int _symbolRefreshEpoch = 0;

  // ── Diagnostics state backed by shared LSP sessions ──
  bool _projectToolchainBarVisible = false;
  bool _diagnosticsBarVisible = false;
  final Map<String, List<_EditorDiagnostic>> _diagnosticsByFile =
      <String, List<_EditorDiagnostic>>{};
  final Set<String> _diagnosticsLoadingFiles = <String>{};
  final Set<String> _diagnosticsStaleFiles = <String>{};

  /// Files that received a text change while a diagnostic refresh was already
  /// in-flight.  After the current refresh completes a re-fetch is queued so
  /// the latest content is always diagnosed.
  final Set<String> _diagnosticsPendingRefresh = <String>{};

  // ── LSP action results ──
  bool _lspResultBarVisible = false;
  bool _lspResultLoading = false;
  String _lspResultTitle = '';
  String? _lspResultMessage;
  List<AiLspLocation> _lspResultLocations = const <AiLspLocation>[];
  List<AiLspCodeAction> _lspResultCodeActions = const <AiLspCodeAction>[];
  bool _lspResultPreviewLoading = false;
  int _lspResultPreviewEpoch = 0;
  Map<String, _EditorLocationPreview> _lspResultPreviews =
      const <String, _EditorLocationPreview>{};
  AiLspHoverResult? _lspHoverResult;
  AiLspLocation? _pendingNavigationLocation;
  _PendingWorkspaceEditPreviewContext? _pendingWorkspaceEditPreviewContext;

  // ── Cursor position tracking ──
  int _cursorLine = 1;
  int _cursorColumn = 1;

  // ── Code completion (autocomplete) state ──
  List<AiLspCompletionItem> _completionItems = const <AiLspCompletionItem>[];
  List<AiLspCompletionItem> _filteredCompletionItems =
      const <AiLspCompletionItem>[];
  int _completionSelectedIndex = 0;
  bool _completionVisible = false;
  Timer? _completionDebounceTimer;
  String _completionPrefix = '';
  int _completionRequestEpoch = 0;
  String? _lastCompletionRequestFilePath;
  int _lastCompletionRequestOffset = -1;
  int _lastCompletionRequestRevision = -1;
  AiLspSignatureHelp? _signatureHelp;
  bool _signatureHelpVisible = false;
  Timer? _signatureHelpDebounceTimer;
  int _signatureHelpRequestEpoch = 0;
  String? _lastSignatureHelpRequestFilePath;
  int _lastSignatureHelpRequestOffset = -1;
  int _lastSignatureHelpRequestRevision = -1;

  @override
  void initState() {
    super.initState();
    _symbolController.addListener(_applySymbolFilter);
    AiLspClientService.instance.workspaceEditHandler =
        _applyIncomingWorkspaceEdit;
    AiLspClientService.instance.diagnosticsPushCallback =
        _handlePushedDiagnostics;
    _syncProjectLspOverrideSettings();
    unawaited(_ensureLspBackend(widget.activeFilePath));
    unawaited(_refreshInferredWorkspaceRoot(widget.activeFilePath));
  }

  @override
  void didUpdateWidget(covariant _CodeEditorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final projectLspConfigChanged =
        oldWidget.projectLanguage != widget.projectLanguage ||
        oldWidget.projectSdkPath != widget.projectSdkPath ||
        oldWidget.projectLspPath != widget.projectLspPath;
    if (projectLspConfigChanged) {
      _syncProjectLspOverrideSettings();
      _resetLspResolutionState();
    }
    for (final removedFile in oldWidget.openFiles) {
      if (widget.openFiles.contains(removedFile)) {
        continue;
      }
      _releaseFileResources(removedFile);
      unawaited(
        AiLspClientService.instance.closeDocument(
          filePath: removedFile,
          language: _resolvedLanguageForFile(removedFile),
        ),
      );
    }
    if (oldWidget.activeFilePath == widget.activeFilePath &&
        !projectLspConfigChanged) {
      return;
    }
    unawaited(
      _ensureLspBackend(widget.activeFilePath, force: projectLspConfigChanged),
    );
    unawaited(_refreshInferredWorkspaceRoot(widget.activeFilePath));
    final controller = _textControllers[widget.activeFilePath];
    if (controller != null) {
      _updateCursorPosition(controller);
      if (_findBarVisible && _findController.text.isNotEmpty) {
        _updateFindMatches(_findController.text);
      }
      if (_symbolBarVisible) {
        unawaited(_refreshSymbols());
      }
      _maybeApplyPendingNavigation();
      unawaited(_maybeRefreshDiagnostics(widget.activeFilePath));
    } else if (_symbolBarVisible) {
      setState(() {
        _allSymbols = const [];
        _visibleSymbols = const [];
        _symbolsTruncated = false;
        _symbolsLoading = false;
        _symbolsUsingLsp = false;
        _symbolHintMessage = null;
      });
    }
  }

  void _releaseFileResources(String filePath) {
    _fileLoadGenerations.remove(filePath);
    _fileContents.remove(filePath);
    _fileLoading.remove(filePath);
    _fileDirty.remove(filePath);
    final scrollController = _scrollControllers.remove(filePath);
    final textController = _textControllers.remove(filePath);
    final focusNode = _focusNodes.remove(filePath);
    if (scrollController != null ||
        textController != null ||
        focusNode != null) {
      // The old EditableText subtree is unmounted after didUpdateWidget.
      // Defer disposal until that frame finishes so it can detach listeners.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        scrollController?.dispose();
        textController?.dispose();
        focusNode?.dispose();
      });
    }
    _forcedFullEditorFiles.remove(filePath);
    _foldedRegions.remove(filePath);
    _lspDiagnosticsTimers.remove(filePath)?.cancel();
    _lspDiagnosticsRequestTokens.remove(filePath);
    _lspBackendRequests.remove(filePath);
    _lspBackendByFile.remove(filePath);
    _lspBackendLoadingFiles.remove(filePath);
    _diagnosticsByFile.remove(filePath);
    _diagnosticsLoadingFiles.remove(filePath);
    _diagnosticsStaleFiles.remove(filePath);
    _diagnosticsPendingRefresh.remove(filePath);
    if (_pendingNavigationLocation?.filePath == filePath) {
      _pendingNavigationLocation = null;
    }
  }

  // ── Zoom helpers ──

  /// Discrete keyboard zoom (Cmd+/Cmd-): apply font size change directly.
  void _zoomIn() {
    _commitZoomScale();
    setState(() {
      _fontSize = (_fontSize + 0.5).clamp(
        _editorFontSizeMin,
        _editorFontSizeMax,
      );
    });
  }

  void _zoomOut() {
    _commitZoomScale();
    setState(() {
      _fontSize = (_fontSize - 0.5).clamp(
        _editorFontSizeMin,
        _editorFontSizeMax,
      );
    });
  }

  void _zoomReset() {
    _commitZoomScale();
    setState(() => _fontSize = _editorFontSizeDefault);
  }

  /// Continuous zoom (pinch / scroll-wheel): apply a visual transform to avoid
  /// expensive re-layout + re-highlight on every frame.
  void _zoomByScale(double scaleDelta) {
    final effectiveNewSize = _fontSize * _zoomVisualScale * scaleDelta;
    // Clamp the visual scale so the effective font size stays within bounds.
    final clampedSize = effectiveNewSize.clamp(
      _editorFontSizeMin,
      _editorFontSizeMax,
    );
    setState(() {
      _zoomVisualScale = clampedSize / _fontSize;
    });
    // Schedule a commit: when the gesture settles, apply the real font size
    // change once (re-highlights only once instead of every frame).
    _zoomCommitTimer?.cancel();
    _zoomCommitTimer = startSafeTimer(
      kOpenHandMotion180,
      _commitZoomScale,
    );
  }

  /// Collapse `_zoomVisualScale` into `_fontSize` for a real layout update.
  void _commitZoomScale() {
    _zoomCommitTimer?.cancel();
    if ((_zoomVisualScale - 1.0).abs() < 0.001) return;
    final committed = (_fontSize * _zoomVisualScale).clamp(
      _editorFontSizeMin,
      _editorFontSizeMax,
    );
    setState(() {
      _fontSize = committed;
      _zoomVisualScale = 1.0;
    });
  }

  Map<String, AiLspLanguageSettings> _projectLspOverrideSettings() {
    final language = normalizeAiLspLanguage(widget.projectLanguage);
    if (language == 'mixed' || language == 'plaintext') {
      return const <String, AiLspLanguageSettings>{};
    }
    final overrideSettings = AiLspLanguageSettings(
      rootPath: OpenHandPaths.normalizeOptionalPath(widget.projectLspPath),
      sdkPath: OpenHandPaths.normalizeOptionalPath(widget.projectSdkPath),
    );
    if (overrideSettings.isEmpty) {
      return const <String, AiLspLanguageSettings>{};
    }
    return <String, AiLspLanguageSettings>{language: overrideSettings};
  }

  void _syncProjectLspOverrideSettings() {
    AiLspClientService.instance.updateProjectLanguageSettingsOverride(
      _projectLspOverrideSettings(),
    );
  }

  void _resetLspResolutionState() {
    for (final timer in _lspDiagnosticsTimers.values) {
      timer.cancel();
    }
    _lspDiagnosticsTimers.clear();
    _lspDiagnosticsRequestTokens.clear();
    _lspBackendRequests.clear();
    _lspBackendLoadingFiles.clear();
    _diagnosticsPendingRefresh.clear();
    if (!mounted) {
      _lspBackendByFile.clear();
      _diagnosticsByFile.clear();
      _diagnosticsLoadingFiles.clear();
      _diagnosticsStaleFiles.clear();
      return;
    }
    setState(() {
      _lspBackendByFile.clear();
      _diagnosticsByFile.clear();
      _diagnosticsLoadingFiles.clear();
      _diagnosticsStaleFiles
        ..clear()
        ..addAll(widget.openFiles);
    });
  }

  String _resolvedLanguageForFile(String filePath) {
    return _resolveEditorLanguage(
      filePath: filePath,
      projectLanguage: widget.projectLanguage,
    );
  }

  AiLspBackendResolution? _lspResolutionForFile(String filePath) {
    return _lspBackendByFile[filePath];
  }

  bool _supportsLspForFile(String filePath) {
    return _lspResolutionForFile(filePath)?.isAvailable == true;
  }

  Future<AiLspBackendResolution> _ensureLspBackend(
    String filePath, {
    bool force = false,
  }) async {
    final pending = _lspBackendRequests[filePath];
    if (pending != null) {
      return pending;
    }
    final cached = _lspBackendByFile[filePath];
    if (!force && cached != null) {
      return cached;
    }
    final completer = Completer<AiLspBackendResolution>();
    final request = completer.future;
    _lspBackendRequests[filePath] = request;

    Future<void> resolveBackend() async {
      _lspBackendLoadingFiles.add(filePath);
      try {
        final resolution = await AiLspClientService.instance
            .resolveBackendForFile(
              filePath: filePath,
              language: _resolvedLanguageForFile(filePath),
            );
        if (!mounted ||
            !widget.openFiles.contains(filePath) ||
            !identical(_lspBackendRequests[filePath], request)) {
          _lspBackendLoadingFiles.remove(filePath);
          completer.complete(resolution);
          return;
        }
        setState(() {
          _lspBackendLoadingFiles.remove(filePath);
          _lspBackendByFile[filePath] = resolution;
        });
        completer.complete(resolution);
      } catch (error, stackTrace) {
        _lspBackendLoadingFiles.remove(filePath);
        completer.completeError(error, stackTrace);
      } finally {
        if (identical(_lspBackendRequests[filePath], request)) {
          _lspBackendRequests.remove(filePath);
        }
      }
    }

    unawaited(resolveBackend());
    return completer.future;
  }

  int _offsetForLineColumn(
    _HighlightingTextController controller,
    int line,
    int column,
  ) {
    return controller._offsetForLineColumn(line, column);
  }

  int _lineForOffset(_HighlightingTextController controller, int offset) {
    return controller._lineIndexForOffset(offset) + 1;
  }

  void _scrollToLine(String filePath, int line) {
    final scrollController = _scrollControllers[filePath];
    if (scrollController == null || !scrollController.hasClients) {
      return;
    }
    final lineExtent = _fontSize * _editorLineHeight;
    final targetOffset = (math.max(1, line) - 1) * lineExtent;
    final viewportHeight = scrollController.position.viewportDimension;
    final centered = (targetOffset - viewportHeight / 3).clamp(
      0.0,
      scrollController.position.maxScrollExtent,
    );
    scrollController.animateTo(
      centered,
      duration: kOpenHandMotion180,
      curve: kOpenHandSwitchInCurve,
    );
  }

  void _jumpToLineColumn(int line, {int column = 1}) {
    final filePath = widget.activeFilePath;
    final controller = _textControllers[filePath];
    if (controller == null) {
      return;
    }
    final offset = _offsetForLineColumn(controller, line, column);
    controller.selection = TextSelection.collapsed(offset: offset);
    _updateCursorPosition(controller);
    _focusNodes[filePath]?.requestFocus();
    _scrollToLine(filePath, line);
  }

  void _scheduleDiagnosticsRefresh(String filePath) {
    _lspDiagnosticsTimers.remove(filePath)?.cancel();
    _lspDiagnosticsTimers[filePath] = startSafeTimer(
      _editorLspDiagnosticsDebounce,
      () => _refreshDiagnostics(filePath),
    );
  }

  /// LSP 服务推送新诊断时直接更新，避免轮询。
  void _handlePushedDiagnostics(
    String filePath,
    List<AiLspDiagnostic> diagnostics,
  ) {
    if (!mounted) return;
    // 只更新编辑器中仍然打开的文件。
    if (!_textControllers.containsKey(filePath)) return;
    setState(() {
      _diagnosticsByFile[filePath] = _mapLspDiagnostics(diagnostics);
      _diagnosticsStaleFiles.remove(filePath);
      if (!_lspDiagnosticsRequestTokens.containsKey(filePath)) {
        _diagnosticsLoadingFiles.remove(filePath);
      }
    });
    // 同步到文本控制器以刷新行内标记。
    final controller = _textControllers[filePath];
    if (controller != null) {
      controller.diagnostics =
          _diagnosticsByFile[filePath] ?? const <_EditorDiagnostic>[];
    }
  }

  void _maybeApplyPendingNavigation() {
    final pending = _pendingNavigationLocation;
    if (pending == null || pending.filePath != widget.activeFilePath) {
      return;
    }
    final controller = _textControllers[pending.filePath];
    if (controller == null) {
      return;
    }
    _pendingNavigationLocation = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _jumpToLineColumn(pending.line, column: pending.character);
    });
  }

  void _showSymbolBar() {
    // Toggle: if already visible in document-symbol mode, hide it.
    if (_symbolBarVisible && !_workspaceSymbolMode) {
      _hideSymbolBar();
      return;
    }
    _openSymbolBar(workspace: false);
  }

  void _showWorkspaceSymbolBar() {
    // Toggle: if already visible in workspace-symbol mode, hide it.
    if (_symbolBarVisible && _workspaceSymbolMode) {
      _hideSymbolBar();
      return;
    }
    _openSymbolBar(workspace: true);
  }

  void _openSymbolBar({required bool workspace}) {
    setState(() {
      _symbolBarVisible = true;
      _workspaceSymbolMode = workspace;
      _projectToolchainBarVisible = false;
      _diagnosticsBarVisible = false;
      _lspResultBarVisible = false;
      _findBarVisible = false;
      _replaceBarVisible = false;
      _goToLineVisible = false;
      _completionVisible = false;
      _signatureHelpVisible = false;
      _signatureHelp = null;
    });
    _scheduleSymbolRefresh(immediate: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _symbolFocusNode.requestFocus();
      }
    });
  }

  void _hideSymbolBar() {
    _symbolRefreshTimer?.cancel();
    setState(() {
      _symbolBarVisible = false;
      _workspaceSymbolMode = false;
      _symbolController.clear();
      _allSymbols = const [];
      _visibleSymbols = const [];
      _symbolsTruncated = false;
      _symbolsLoading = false;
      _symbolsUsingLsp = false;
      _symbolHintMessage = null;
    });
  }

  void _setSymbolSearchMode(bool workspace) {
    if (_workspaceSymbolMode == workspace) {
      return;
    }
    setState(() {
      _workspaceSymbolMode = workspace;
      _allSymbols = const [];
      _visibleSymbols = const [];
      _symbolsTruncated = false;
      _symbolsLoading = false;
      _symbolsUsingLsp = false;
      _symbolHintMessage = null;
    });
    _scheduleSymbolRefresh(immediate: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _symbolFocusNode.requestFocus();
      }
    });
  }

  List<_EditorSymbol> _filterSymbols(
    List<_EditorSymbol> symbols,
    String rawQuery,
  ) {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return symbols.take(72).toList(growable: false);
    }
    return symbols
        .where((symbol) {
          final name = symbol.name.toLowerCase();
          final signature = symbol.signature.toLowerCase();
          return name.contains(query) || signature.contains(query);
        })
        .take(72)
        .toList(growable: false);
  }

  void _applySymbolFilter() {
    if (!_symbolBarVisible) {
      return;
    }
    if (_workspaceSymbolMode) {
      _scheduleSymbolRefresh();
      return;
    }
    setState(() {
      _visibleSymbols = _filterSymbols(_allSymbols, _symbolController.text);
    });
  }

  void _scheduleSymbolRefresh({bool immediate = false}) {
    _symbolRefreshTimer?.cancel();
    if (!_symbolBarVisible) {
      return;
    }
    if (immediate) {
      unawaited(_refreshSymbols());
      return;
    }
    _symbolRefreshTimer = startSafeTimer(
      _editorLspSymbolsDebounce,
      _refreshSymbols,
    );
  }

  Future<void> _refreshSymbols() async {
    final controller = _textControllers[widget.activeFilePath];
    if (controller == null) {
      return;
    }
    final filePath = widget.activeFilePath;
    final refreshEpoch = ++_symbolRefreshEpoch;
    final fallbackExtraction = _extractEditorSymbols(
      filePath: filePath,
      text: controller.text,
      language: _resolvedLanguageForFile(filePath),
    );

    void applyExtraction(
      _EditorSymbolExtractionResult extraction, {
      required bool usingLsp,
      String? hintMessage,
    }) {
      if (!mounted ||
          refreshEpoch != _symbolRefreshEpoch ||
          widget.activeFilePath != filePath) {
        return;
      }
      setState(() {
        _symbolsLoading = false;
        _symbolsUsingLsp = usingLsp;
        _symbolHintMessage = hintMessage;
        _allSymbols = extraction.symbols;
        _visibleSymbols = _filterSymbols(
          extraction.symbols,
          _symbolController.text,
        );
        _symbolsTruncated = extraction.truncated;
      });
    }

    if (mounted) {
      setState(() {
        _symbolsLoading = true;
      });
    }

    if (_workspaceSymbolMode) {
      final query = _symbolController.text.trim();
      if (query.isEmpty) {
        applyExtraction(
          const _EditorSymbolExtractionResult(
            symbols: <_EditorSymbol>[],
            truncated: false,
          ),
          usingLsp: false,
          hintMessage: AppLocalizations.of(
            context,
          )!.progExpFETypeASymbolNameToSearch,
        );
        return;
      }
      try {
        final resolution = await _ensureLspBackend(filePath);
        if (!mounted ||
            refreshEpoch != _symbolRefreshEpoch ||
            widget.activeFilePath != filePath) {
          return;
        }
        if (!resolution.isAvailable) {
          applyExtraction(
            const _EditorSymbolExtractionResult(
              symbols: <_EditorSymbol>[],
              truncated: false,
            ),
            usingLsp: false,
            hintMessage: AppLocalizations.of(
              context,
            )!.progExpFENoWorkspaceSymbolBackendIsAvailable,
          );
          return;
        }
        final workspaceSymbols = await AiLspClientService.instance
            .workspaceSymbols(
              filePath: filePath,
              query: query,
              language: resolution.language,
            );
        if (!mounted ||
            refreshEpoch != _symbolRefreshEpoch ||
            widget.activeFilePath != filePath) {
          return;
        }
        final extraction = _extractEditorSymbolsFromWorkspaceLsp(
          workspaceSymbols: workspaceSymbols,
        );
        applyExtraction(
          extraction,
          usingLsp: true,
          hintMessage: extraction.symbols.isEmpty
              ? AppLocalizations.of(
                  context,
                )!.progExpFENoMatchingWorkspaceSymbolsWereFound
              : null,
        );
      } catch (error, stack) {
        silentLog('file_explorer', '加载工作区符号', error, stack);
        applyExtraction(
          const _EditorSymbolExtractionResult(
            symbols: <_EditorSymbol>[],
            truncated: false,
          ),
          usingLsp: false,
          hintMessage: AppLocalizations.of(
            context,
          )!.progExpFEFetchingWorkspaceSymbolsFailedConfirmTha,
        );
      }
      return;
    }

    if (controller.useVirtualizedPreview &&
        !_forcedFullEditorFiles.contains(filePath)) {
      applyExtraction(
        fallbackExtraction,
        usingLsp: false,
        hintMessage: AppLocalizations.of(
          context,
        )!.progExpFEThisFileIsStillInLarge,
      );
      return;
    }

    try {
      final resolution = await _ensureLspBackend(filePath);
      if (!mounted ||
          refreshEpoch != _symbolRefreshEpoch ||
          widget.activeFilePath != filePath) {
        return;
      }
      if (!resolution.isAvailable) {
        applyExtraction(
          fallbackExtraction,
          usingLsp: false,
          hintMessage: AppLocalizations.of(
            context,
          )!.progExpFENoLspSymbolBackendIsAvailable,
        );
        return;
      }

      final documentSymbols = await AiLspClientService.instance.documentSymbols(
        filePath: filePath,
        language: resolution.language,
        documentText: controller.text,
      );
      if (!mounted ||
          refreshEpoch != _symbolRefreshEpoch ||
          widget.activeFilePath != filePath) {
        return;
      }

      final extraction = _extractEditorSymbolsFromLsp(
        filePath: filePath,
        documentSymbols: documentSymbols,
        text: controller.text,
      );
      applyExtraction(
        extraction,
        usingLsp: true,
        hintMessage: extraction.symbols.isEmpty
            ? AppLocalizations.of(context)!.progExpFETheLspServerReturnedAnEmpty
            : null,
      );
    } catch (error, stack) {
      silentLog('file_explorer', '加载文档符号 $filePath', error, stack);
      applyExtraction(
        fallbackExtraction,
        usingLsp: false,
        hintMessage: AppLocalizations.of(
          context,
        )!.progExpFEFetchingLspSymbolsFailedSoThe,
      );
    }
  }

  String _locationPreviewKey(AiLspLocation location) {
    return '${p.normalize(location.filePath)}:${location.line}:${location.character}';
  }

  String _truncatePreviewText(String text, {int maxLength = 160}) {
    final normalized = text.replaceAll('\t', '  ').trimRight();
    return clipText(normalized, math.max(0, maxLength - 1), suffix: '…');
  }

  Future<void> _loadLspLocationPreviews(
    List<AiLspLocation> locations,
    int previewEpoch,
  ) async {
    final fileLinesCache = <String, List<String>>{};
    Future<List<String>> readLines(String filePath) async {
      final cached = fileLinesCache[filePath];
      if (cached != null) {
        return cached;
      }
      final controller = _textControllers[filePath];
      final text =
          controller?.text ??
          await readBoundedFileString(
            File(filePath),
            maxBytes: _kProgrammingExplorerLspPreviewMaxBytes,
          );
      final lines = const LineSplitter().convert(text);
      fileLinesCache[filePath] = lines;
      return lines;
    }

    final previews = <String, _EditorLocationPreview>{};
    for (final location in locations) {
      try {
        final lines = await readLines(location.filePath);
        if (!mounted || previewEpoch != _lspResultPreviewEpoch) {
          return;
        }
        if (lines.isEmpty) {
          continue;
        }
        final startLine = math.max(1, location.line - 1);
        final endLine = math.min(lines.length, location.line + 1);
        final previewLines = <_EditorPreviewLine>[];
        for (var lineNumber = startLine; lineNumber <= endLine; lineNumber++) {
          previewLines.add(
            _EditorPreviewLine(
              lineNumber: lineNumber,
              text: _truncatePreviewText(lines[lineNumber - 1]),
              isHighlight: lineNumber == location.line,
            ),
          );
        }
        previews[_locationPreviewKey(location)] = _EditorLocationPreview(
          lines: List<_EditorPreviewLine>.unmodifiable(previewLines),
        );
      } catch (error, stack) {
        silentLog(
          'file_explorer',
          '加载 LSP 位置预览 ${location.filePath}',
          error,
          stack,
        );
        if (!mounted || previewEpoch != _lspResultPreviewEpoch) {
          return;
        }
      }
    }

    if (!mounted || previewEpoch != _lspResultPreviewEpoch) {
      return;
    }
    setState(() {
      _lspResultPreviewLoading = false;
      _lspResultPreviews = Map<String, _EditorLocationPreview>.unmodifiable(
        previews,
      );
    });
  }

  Future<void> _navigateToEditorSymbol(_EditorSymbol symbol) async {
    _hideSymbolBar();
    final location = AiLspLocation(
      filePath: symbol.filePath,
      range: AiLspRange(
        start: AiLspPosition(line: symbol.line, character: symbol.column),
        end: AiLspPosition(line: symbol.line, character: symbol.column),
      ),
    );
    await _navigateToLspLocation(location);
  }

  AiLspPosition _positionForOffset(
    _HighlightingTextController controller,
    int offset,
  ) {
    final position = controller._lineColumnForOffset(offset);
    return AiLspPosition(line: position.line, character: position.column);
  }

  AiLspRange _selectionRangeForController(
    _HighlightingTextController controller,
  ) {
    final selection = controller.selection;
    final base = selection.baseOffset < 0 ? 0 : selection.baseOffset;
    final extent = selection.extentOffset < 0 ? base : selection.extentOffset;
    final startOffset = math.min(base, extent);
    final endOffset = math.max(base, extent);
    return AiLspRange(
      start: _positionForOffset(controller, startOffset),
      end: _positionForOffset(controller, endOffset),
    );
  }

  Future<void> _syncOpenDocumentsForLsp() async {
    for (final filePath in widget.openFiles) {
      final controller = _textControllers[filePath];
      if (controller == null) {
        continue;
      }
      final resolution = await _ensureLspBackend(filePath);
      if (!resolution.isAvailable) {
        continue;
      }
      await AiLspClientService.instance.syncDocument(
        filePath: filePath,
        language: resolution.language,
        documentText: controller.text,
      );
    }
  }

  String _currentSymbolName(_HighlightingTextController controller) {
    final selection = controller.selection;
    if (selection.start >= 0 && selection.end > selection.start) {
      return controller.text.substring(selection.start, selection.end).trim();
    }
    final offset = selection.baseOffset.clamp(0, controller.text.length);
    var start = offset;
    var end = offset;
    final text = controller.text;
    bool isSymbolChar(int codeUnit) {
      final isLetter =
          (codeUnit >= 65 && codeUnit <= 90) ||
          (codeUnit >= 97 && codeUnit <= 122);
      final isDigit = codeUnit >= 48 && codeUnit <= 57;
      return isLetter || isDigit || codeUnit == 95 || codeUnit == 36;
    }

    while (start > 0 && isSymbolChar(text.codeUnitAt(start - 1))) {
      start -= 1;
    }
    while (end < text.length && isSymbolChar(text.codeUnitAt(end))) {
      end += 1;
    }
    if (start >= end) {
      return '';
    }
    return text.substring(start, end).trim();
  }

  String _applyTextEdits(String text, List<AiLspTextEdit> edits) {
    var updated = text;
    for (final edit
        in edits.toList()..sort((left, right) {
          final leftStart = _editorOffsetForLineColumn(
            updated,
            left.range.start.line,
            left.range.start.character,
          );
          final rightStart = _editorOffsetForLineColumn(
            updated,
            right.range.start.line,
            right.range.start.character,
          );
          return rightStart.compareTo(leftStart);
        })) {
      final start = _editorOffsetForLineColumn(
        updated,
        edit.range.start.line,
        edit.range.start.character,
      );
      final end = _editorOffsetForLineColumn(
        updated,
        edit.range.end.line,
        edit.range.end.character,
      );
      updated = updated.replaceRange(start, end, edit.newText);
    }
    return updated;
  }

  Future<_PreparedWorkspaceEdit> _prepareWorkspaceEdit(
    AiLspWorkspaceEdit edit,
  ) async {
    final preparedFiles = <_PreparedWorkspaceEditFile>[];
    for (final fileEdit in edit.fileEdits) {
      final controller = _textControllers[fileEdit.filePath];
      final file = File(fileEdit.filePath);
      final originalText =
          controller?.text ??
          (await isRegularFilePath(file.path, followLinks: true)
              ? await readBoundedFileString(
                  file,
                  maxBytes: _kProgrammingExplorerMaxEditableFileBytes,
                )
              : '');
      final updatedText = _applyTextEdits(originalText, fileEdit.edits);
      final diffLines = originalText == updatedText
          ? const <String>[]
          : unifiedDiffLines(
              originalText.split('\n'),
              updatedText.split('\n'),
              maxMyersLineTotal: _kEditorUnifiedDiffMaxMyersLineTotal,
            );
      final additions = diffLines
          .where((line) => line.startsWith('+') && !line.startsWith('+++'))
          .length;
      final deletions = diffLines
          .where((line) => line.startsWith('-') && !line.startsWith('---'))
          .length;
      const maxPreviewLines = 240;
      preparedFiles.add(
        _PreparedWorkspaceEditFile(
          filePath: fileEdit.filePath,
          updatedText: updatedText,
          editCount: fileEdit.edits.length,
          diffLines: diffLines.length > maxPreviewLines
              ? diffLines.take(maxPreviewLines).toList(growable: false)
              : List<String>.from(diffLines, growable: false),
          additionCount: additions,
          deletionCount: deletions,
          isTruncated: diffLines.length > maxPreviewLines,
        ),
      );
    }
    return _PreparedWorkspaceEdit(edit: edit, files: preparedFiles);
  }

  Future<bool> _applyPreparedWorkspaceEdit(
    _PreparedWorkspaceEdit prepared,
  ) async {
    final edit = prepared.edit;
    if (edit.isEmpty && !edit.hasUnsupportedOperations) {
      return false;
    }

    final activeFilePath = widget.activeFilePath;
    for (final preparedFile in prepared.files) {
      final filePath = preparedFile.filePath;
      final newText = preparedFile.updatedText;
      final controller = _textControllers[filePath];
      if (controller != null) {
        final previousSelection = controller.selection;
        final collapsedOffset = previousSelection.baseOffset.clamp(
          0,
          newText.length,
        );
        controller.value = controller.value.copyWith(
          text: newText,
          selection: TextSelection.collapsed(offset: collapsedOffset),
        );
        _fileContents[filePath] = newText;
        if (filePath == activeFilePath) {
          _updateCursorPosition(controller);
          if (_findBarVisible && _findController.text.isNotEmpty) {
            _updateFindMatches(_findController.text);
          }
          if (_symbolBarVisible) {
            _scheduleSymbolRefresh(immediate: true);
          }
        }
        _fileDirty[filePath] = true;
      } else {
        await writeFileAtomically(File(filePath), newText);
      }
      _diagnosticsByFile.remove(filePath);
      _diagnosticsStaleFiles.add(filePath);
      await AiLspClientService.instance.syncDocument(
        filePath: filePath,
        language: _resolvedLanguageForFile(filePath),
        documentText: newText,
      );
    }

    if (!mounted) {
      return true;
    }
    setState(() {});
    if (prepared.files.any((item) => item.filePath == activeFilePath)) {
      unawaited(_refreshDiagnostics(activeFilePath));
    }
    return true;
  }

  Future<bool> _reviewWorkspaceEditAndMaybeApply({
    required String title,
    required AiLspWorkspaceEdit edit,
    String? description,
  }) async {
    if (edit.isEmpty && !edit.hasUnsupportedOperations) {
      return false;
    }
    final prepared = await _prepareWorkspaceEdit(edit);
    if (!mounted) {
      return false;
    }
    final approved = await _showWorkspaceEditPreviewDialog(
      title: title,
      preparedEdit: prepared,
      description: description,
    );
    if (!mounted || approved != true) {
      return false;
    }
    return _applyPreparedWorkspaceEdit(prepared);
  }

  Future<bool?> _showWorkspaceEditPreviewDialog({
    required String title,
    required _PreparedWorkspaceEdit preparedEdit,
    String? description,
  }) {
    return showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final colorScheme = theme.colorScheme;
        final text = openHandTextResolver(dialogContext);

        final canApply = preparedEdit.files.isNotEmpty;
        final fileCount = preparedEdit.files.length;
        final editCount = preparedEdit.edit.editCount;

        return buildOpenHandResponsiveDialogShell(
          context: dialogContext,
          maxWidth: kOpenHandDialogWidthPanel,
          maxHeight: kOpenHandDialogHeightTall,
          safeAreaMinimum: const EdgeInsets.symmetric(
            horizontal: 28,
            vertical: 24,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: openHandCloseLabel(dialogContext),
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                kOpenHandGap8,
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _WorkspaceEditStatChip(
                      label: text(
                        zh: '$fileCount 个文件',
                        zhHant: '$fileCount 個檔案',
                        en: '$fileCount files',
                        fr: '$fileCount fichiers',
                        de: '$fileCount Dateien',
                        ja: '$fileCount ファイル',
                      ),
                      color: colorScheme.primary,
                    ),
                    _WorkspaceEditStatChip(
                      label: text(
                        zh: '$editCount 处修改',
                        zhHant: '$editCount 處修改',
                        en: '$editCount edits',
                        fr: '$editCount modifications',
                        de: '$editCount Änderungen',
                        ja: '$editCount 件の編集',
                      ),
                      color: colorScheme.tertiary,
                    ),
                    if (preparedEdit.edit.hasUnsupportedOperations)
                      _WorkspaceEditStatChip(
                        label: text(
                          zh: '${preparedEdit.edit.unsupportedOperationsCount} 个未支持操作',
                          zhHant:
                              '${preparedEdit.edit.unsupportedOperationsCount} 個未支援操作',
                          en: '${preparedEdit.edit.unsupportedOperationsCount} unsupported ops',
                          fr: '${preparedEdit.edit.unsupportedOperationsCount} opérations non prises en charge',
                          de: '${preparedEdit.edit.unsupportedOperationsCount} nicht unterstützte Vorgänge',
                          ja: '${preparedEdit.edit.unsupportedOperationsCount} 件の未対応操作',
                        ),
                        color: colorScheme.error,
                      ),
                  ],
                ),
                if (description?.trim().isNotEmpty == true) ...[
                  kOpenHandGap10,
                  Text(
                    description!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
                if (preparedEdit.edit.hasUnsupportedOperations) ...[
                  kOpenHandGap10,
                  _buildDiagnosticsHint(
                    colorScheme,
                    text(
                      zh: '文件重命名、创建、删除等文件级操作还没有自动预览或应用能力，仅展示可计算的文本修改。',
                      zhHant: '檔案重新命名、建立、刪除等檔案級操作尚未支援自動預覽或套用，這裡只顯示可計算的文字修改。',
                      en: 'File-level operations such as rename, create, or delete are not previewed or applied automatically yet. Only text edits are shown here.',
                      fr: 'Les opérations de fichier comme renommer, créer ou supprimer ne sont pas encore prévisualisées ni appliquées automatiquement. Seules les modifications de texte sont affichées.',
                      de: 'Dateivorgänge wie Umbenennen, Erstellen oder Löschen werden noch nicht automatisch angezeigt oder angewendet. Hier erscheinen nur berechenbare Textänderungen.',
                      ja: 'リネーム、作成、削除などのファイル単位操作はまだ自動プレビュー/適用されません。ここでは計算可能なテキスト編集のみ表示します。',
                    ),
                  ),
                ],
                kOpenHandGap14,
                Expanded(
                  child: preparedEdit.files.isEmpty
                      ? OpenHandInlineEmptyState(
                          message: text(
                            zh: '当前没有可预览的文本修改。',
                            zhHant: '目前沒有可預覽的文字修改。',
                            en: 'There are no previewable text edits for this operation.',
                            fr: 'Aucune modification de texte prévisualisable pour cette opération.',
                            de: 'Für diesen Vorgang gibt es keine anzeigbaren Textänderungen.',
                            ja: 'この操作でプレビュー可能なテキスト編集はありません。',
                          ),
                        )
                      : ListView.separated(
                          itemCount: preparedEdit.files.length,
                          separatorBuilder: (_, _) =>
                              kOpenHandGap12,
                          itemBuilder: (dialogContext, index) {
                            final file = preparedEdit.files[index];
                            return Container(
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerLowest
                                    .withValues(alpha: 0.94),
                                borderRadius: kOpenHandBorderRadius14,
                                border: Border.all(
                                  color: colorScheme.outlineVariant.withValues(
                                    alpha: 0.22,
                                  ),
                                  width: 0.5,
                                ),
                              ),
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              p.basename(file.filePath),
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                    color:
                                                        colorScheme.onSurface,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                            kOpenHandGap2,
                                            Text(
                                              _displayPathForFilePath(
                                                file.filePath,
                                              ),
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color: colorScheme.primary,
                                                    fontFamily:
                                                        kOpenHandMonospaceFontFamily,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      kOpenHandHGap12,
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          _WorkspaceEditStatChip(
                                            label: text(
                                              zh: '${file.editCount} 处修改',
                                              zhHant: '${file.editCount} 處修改',
                                              en: '${file.editCount} edits',
                                              fr: '${file.editCount} modifications',
                                              de: '${file.editCount} Änderungen',
                                              ja: '${file.editCount} 件の編集',
                                            ),
                                            color: colorScheme.primary,
                                          ),
                                          if (file.additionCount > 0)
                                            _WorkspaceEditStatChip(
                                              label: text(
                                                zh: '+${file.additionCount} 新增',
                                                zhHant:
                                                    '+${file.additionCount} 新增',
                                                en: '+${file.additionCount}',
                                                fr: '+${file.additionCount}',
                                                de: '+${file.additionCount}',
                                                ja: '+${file.additionCount}',
                                              ),
                                              color: _kFileExplorerSuccessColor,
                                            ),
                                          if (file.deletionCount > 0)
                                            _WorkspaceEditStatChip(
                                              label: text(
                                                zh: '-${file.deletionCount} 删除',
                                                zhHant:
                                                    '-${file.deletionCount} 刪除',
                                                en: '-${file.deletionCount}',
                                                fr: '-${file.deletionCount}',
                                                de: '-${file.deletionCount}',
                                                ja: '-${file.deletionCount}',
                                              ),
                                              color: colorScheme.error,
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  kOpenHandGap10,
                                  if (file.diffLines.isEmpty)
                                    Text(
                                      text(
                                        zh: '该文件没有可显示的文本差异。',
                                        zhHant: '此檔案沒有可顯示的文字差異。',
                                        en: 'This file does not have a displayable text diff.',
                                        fr: 'Ce fichier n’a pas de diff texte affichable.',
                                        de: 'Diese Datei hat keinen anzeigbaren Text-Diff.',
                                        ja: 'このファイルには表示可能なテキスト差分がありません。',
                                      ),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                    )
                                  else
                                    Container(
                                      constraints: const BoxConstraints(
                                        maxHeight: 250,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colorScheme.surface,
                                        borderRadius: kOpenHandBorderRadius10,
                                        border: Border.all(
                                          color: colorScheme.outlineVariant
                                              .withValues(alpha: 0.2),
                                          width: 0.5,
                                        ),
                                      ),
                                      child: ListView.builder(
                                        shrinkWrap: true,
                                        itemCount:
                                            file.diffLines.length +
                                            (file.isTruncated ? 1 : 0),
                                        itemBuilder: (diffContext, diffIndex) {
                                          if (file.isTruncated &&
                                              diffIndex ==
                                                  file.diffLines.length) {
                                            return Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 8,
                                                  ),
                                              child: Text(
                                                text(
                                                  zh: '差异内容过长，已截断显示前 240 行。',
                                                  zhHant:
                                                      '差異內容過長，已截斷顯示前 240 行。',
                                                  en: 'The diff is long, so only the first 240 lines are shown.',
                                                  fr: 'Le diff est long ; seules les 240 premières lignes sont affichées.',
                                                  de: 'Der Diff ist lang; es werden nur die ersten 240 Zeilen angezeigt.',
                                                  ja: '差分が長いため、先頭 240 行のみ表示しています。',
                                                ),
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                      color: colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                              ),
                                            );
                                          }
                                          return _WorkspaceEditDiffLine(
                                            line: file.diffLines[diffIndex],
                                            colorScheme: colorScheme,
                                          );
                                        },
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                kOpenHandGap14,
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OpenHandDialogActionButton.secondary(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      label: openHandCancelLabel(dialogContext),
                    ),
                    kOpenHandHGap8,
                    OpenHandDialogActionButton.primary(
                      onPressed: canApply
                          ? () => Navigator.of(dialogContext).pop(true)
                          : null,
                      label: canApply
                          ? text(
                              zh: '应用修改',
                              zhHant: '套用修改',
                              en: 'Apply Changes',
                              fr: 'Appliquer les modifications',
                              de: 'Änderungen anwenden',
                              ja: '変更を適用',
                            )
                          : text(
                              zh: '无可应用修改',
                              zhHant: '沒有可套用修改',
                              en: 'No Applicable Changes',
                              fr: 'Aucune modification applicable',
                              de: 'Keine anwendbaren Änderungen',
                              ja: '適用可能な変更はありません',
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool> _applyWorkspaceEdit(AiLspWorkspaceEdit edit) async {
    final prepared = await _prepareWorkspaceEdit(edit);
    return _applyPreparedWorkspaceEdit(prepared);
  }

  Future<bool> _applyIncomingWorkspaceEdit(AiLspWorkspaceEdit edit) async {
    try {
      final previewContext = _pendingWorkspaceEditPreviewContext;
      if (previewContext == null) {
        return await _applyWorkspaceEdit(edit);
      }
      final applied = await _reviewWorkspaceEditAndMaybeApply(
        title: previewContext.title,
        edit: edit,
        description: previewContext.description,
      );
      if (applied) {
        previewContext.appliedSummaries.add(_workspaceEditSummary(edit));
      } else {
        previewContext.declined = true;
      }
      return applied;
    } catch (_) {
      return false;
    }
  }

  String _workspaceEditSummary(AiLspWorkspaceEdit edit) {
    final base = openHandLocalizedText(
      context,
      zh: '已应用 ${edit.editCount} 处修改，涉及 ${edit.fileCount} 个文件。',
      zhHant: '已套用 ${edit.editCount} 處修改，涉及 ${edit.fileCount} 個檔案。',
      en: 'Applied ${edit.editCount} edits across ${edit.fileCount} files.',
      fr: '${edit.editCount} modifications appliquées dans ${edit.fileCount} fichiers.',
      de: '${edit.editCount} Änderungen in ${edit.fileCount} Dateien angewendet.',
      ja: '${edit.fileCount} ファイルに ${edit.editCount} 件の編集を適用しました。',
    );
    if (!edit.hasUnsupportedOperations) {
      return base;
    }
    return openHandLocalizedText(
      context,
      zh: '$base 其中有 ${edit.unsupportedOperationsCount} 个文件级操作未自动处理。',
      zhHant: '$base 其中有 ${edit.unsupportedOperationsCount} 個檔案級操作未自動處理。',
      en: '$base ${edit.unsupportedOperationsCount} file-level operations were not applied automatically.',
      fr: '$base ${edit.unsupportedOperationsCount} opérations de fichier n’ont pas été appliquées automatiquement.',
      de: '$base ${edit.unsupportedOperationsCount} Dateivorgänge wurden nicht automatisch angewendet.',
      ja: '$base ${edit.unsupportedOperationsCount} 件のファイル単位操作は自動適用されませんでした。',
    );
  }

  Future<String?> _promptRenameSymbol(String initialValue) async {
    return showOpenHandTextInputDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '重命名符号',
        zhHant: '重新命名符號',
        en: 'Rename Symbol',
        fr: 'Renommer le symbole',
        de: 'Symbol umbenennen',
        ja: 'シンボル名を変更',
      ),
      initialValue: initialValue,
      hintText: _homeProgramminNewNameLabel(context),
      cancelLabel: openHandCancelLabel(context),
      confirmLabel: openHandLocalizedText(
        context,
        zh: '应用',
        zhHant: '套用',
        en: 'Apply',
        fr: 'Appliquer',
        de: 'Anwenden',
        ja: '適用',
      ),
      decoration: InputDecoration(
        labelText: _homeProgramminNewNameLabel(context),
        border: const OutlineInputBorder(borderRadius: kOpenHandBorderRadius8),
        focusedBorder: OutlineInputBorder(
          borderRadius: kOpenHandBorderRadius8,
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
        ),
      ),
    );
  }

  Future<void> _renameSymbolAtCursor() async {
    final title = AppLocalizations.of(context)!.progExpFERenameSymbol;
    final previewDescription = AppLocalizations.of(
      context,
    )!.progExpFEReviewTheDiffForThisRename;
    final previewCanceledMessage = AppLocalizations.of(
      context,
    )!.progExpFETheRenameWasCancelledAndNo;
    final resolution = await _prepareCursorLspAction(title);
    if (resolution == null) {
      return;
    }
    final controller = _textControllers[widget.activeFilePath];
    if (controller == null) {
      return;
    }
    try {
      await _syncOpenDocumentsForLsp();
      final prepared = await AiLspClientService.instance.prepareRename(
        filePath: widget.activeFilePath,
        line: _cursorLine,
        character: _cursorColumn,
        language: resolution.language,
        documentText: controller.text,
      );
      if (!mounted) {
        return;
      }
      if (prepared == null) {
        _showLspMessage(
          title: title,
          message: AppLocalizations.of(
            context,
          )!.progExpFETheSymbolAtTheCurrentCursor,
        );
        return;
      }
      final currentName = prepared.placeholder?.trim().isNotEmpty == true
          ? prepared.placeholder!.trim()
          : _currentSymbolName(controller);
      final newName = await _promptRenameSymbol(currentName);
      if (!mounted ||
          newName == null ||
          newName.isEmpty ||
          newName == currentName) {
        _hideLspResultBar();
        return;
      }
      _showLspLoading(title);
      final edit = await AiLspClientService.instance.renameSymbol(
        filePath: widget.activeFilePath,
        line: _cursorLine,
        character: _cursorColumn,
        newName: newName,
        language: resolution.language,
        documentText: controller.text,
      );
      if (!mounted) {
        return;
      }
      if (edit.isEmpty && !edit.hasUnsupportedOperations) {
        _showLspMessage(
          title: title,
          message: AppLocalizations.of(
            context,
          )!.progExpFETheLanguageServerDidNotReturn,
        );
        return;
      }
      final applied = await _reviewWorkspaceEditAndMaybeApply(
        title: title,
        edit: edit,
        description: previewDescription,
      );
      if (!mounted) {
        return;
      }
      if (!applied) {
        _showLspMessage(title: title, message: previewCanceledMessage);
        return;
      }
      _showLspMessage(title: title, message: _workspaceEditSummary(edit));
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showLspMessage(title: title, message: _friendlyLspError(error));
    }
  }

  Future<void> _showCodeActionsAtCursor() async {
    final title = AppLocalizations.of(context)!.progExpFECodeActions;
    final emptyMessage = AppLocalizations.of(
      context,
    )!.progExpFENoCodeActionsAreAvailableAt;
    final resolution = await _prepareCursorLspAction(title);
    if (resolution == null) {
      return;
    }
    final controller = _textControllers[widget.activeFilePath];
    if (controller == null) {
      return;
    }
    try {
      await _syncOpenDocumentsForLsp();
      final range = _selectionRangeForController(controller);
      final diagnostics = await AiLspClientService.instance.diagnosticsForFile(
        filePath: widget.activeFilePath,
        language: resolution.language,
        documentText: controller.text,
        waitForPublish: false,
      );
      final filteredDiagnostics = diagnostics
          .where((item) {
            final lineInRange =
                _cursorLine >= item.range.start.line &&
                _cursorLine <= item.range.end.line;
            if (lineInRange) {
              return true;
            }
            if (controller.selection.start != controller.selection.end) {
              final selectionStart = _editorOffsetForLineColumn(
                controller.text,
                range.start.line,
                range.start.character,
              );
              final selectionEnd = _editorOffsetForLineColumn(
                controller.text,
                range.end.line,
                range.end.character,
              );
              final diagnosticStart = _editorOffsetForLineColumn(
                controller.text,
                item.range.start.line,
                item.range.start.character,
              );
              final diagnosticEnd = _editorOffsetForLineColumn(
                controller.text,
                item.range.end.line,
                item.range.end.character,
              );
              return diagnosticStart <= selectionEnd &&
                  selectionStart <= diagnosticEnd;
            }
            return false;
          })
          .toList(growable: false);
      await _requestAndShowCodeActions(
        title: title,
        resolution: resolution,
        controller: controller,
        range: range,
        diagnostics: filteredDiagnostics,
        emptyMessage: emptyMessage,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showLspMessage(title: title, message: _friendlyLspError(error));
    }
  }

  Future<void> _applyCodeAction(AiLspCodeAction action) async {
    if (action.isDisabled) {
      return;
    }
    final title = action.title;
    final previewDescription = AppLocalizations.of(
      context,
    )!.progExpFEReviewTheDiffFromThisCode;
    final commandPreviewDescription = AppLocalizations.of(
      context,
    )!.progExpFEIfTheLanguageServerCommandRequests;
    final previewCanceledMessage = AppLocalizations.of(
      context,
    )!.progExpFETheCodeActionWasCancelledAnd;
    final commandExecutedMessage = AppLocalizations.of(
      context,
    )!.progExpFEExecutedTheLanguageServerCommand;
    final commandEditsSkippedMessage = AppLocalizations.of(
      context,
    )!.progExpFESomeLanguageServerRequestedEditsWere;
    final noApplicableEditsMessage = AppLocalizations.of(
      context,
    )!.progExpFEThisCodeActionDidNotReturn;
    _showLspLoading(title);
    final previewContext = _PendingWorkspaceEditPreviewContext(
      title: title,
      description: commandPreviewDescription,
    );
    _pendingWorkspaceEditPreviewContext = previewContext;
    try {
      final resolution = await _ensureLspBackend(widget.activeFilePath);
      if (!resolution.isAvailable) {
        if (mounted) {
          _showLspMessage(
            title: title,
            message: _lspUnavailableMessage(resolution),
          );
        }
        return;
      }
      await _syncOpenDocumentsForLsp();
      var resolvedAction = action;
      if (resolvedAction.edit == null &&
          resolvedAction.command == null &&
          resolvedAction.canResolve) {
        resolvedAction = await AiLspClientService.instance.resolveCodeAction(
          filePath: widget.activeFilePath,
          action: resolvedAction,
          language: resolution.language,
        );
      }
      var summaryParts = <String>[];
      if (resolvedAction.edit != null) {
        final applied = await _reviewWorkspaceEditAndMaybeApply(
          title: title,
          edit: resolvedAction.edit!,
          description: previewDescription,
        );
        if (!mounted) {
          return;
        }
        if (!applied) {
          _showLspMessage(title: title, message: previewCanceledMessage);
          return;
        }
        summaryParts.add(_workspaceEditSummary(resolvedAction.edit!));
      }
      if (resolvedAction.command != null) {
        await AiLspClientService.instance.executeCommand(
          filePath: widget.activeFilePath,
          language: resolution.language,
          command: resolvedAction.command!,
        );
        summaryParts.add(commandExecutedMessage);
        if (previewContext.appliedSummaries.isNotEmpty) {
          summaryParts.addAll(previewContext.appliedSummaries);
        }
        if (previewContext.declined) {
          summaryParts.add(commandEditsSkippedMessage);
        }
      }
      if (!mounted) {
        return;
      }
      if (summaryParts.isEmpty) {
        _showLspMessage(title: title, message: noApplicableEditsMessage);
        return;
      }
      _showLspMessage(title: title, message: summaryParts.join('\n'));
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showLspMessage(title: title, message: _friendlyLspError(error));
    } finally {
      if (identical(_pendingWorkspaceEditPreviewContext, previewContext)) {
        _pendingWorkspaceEditPreviewContext = null;
      }
    }
  }

  Future<List<AiLspCodeAction>> _requestCodeActions({
    required AiLspBackendResolution resolution,
    required _HighlightingTextController controller,
    required AiLspRange range,
    required List<AiLspDiagnostic> diagnostics,
  }) {
    return AiLspClientService.instance.codeActions(
      filePath: widget.activeFilePath,
      range: range,
      diagnostics: diagnostics,
      language: resolution.language,
      documentText: controller.text,
    );
  }

  Future<void> _requestAndShowCodeActions({
    required String title,
    required AiLspBackendResolution resolution,
    required _HighlightingTextController controller,
    required AiLspRange range,
    required List<AiLspDiagnostic> diagnostics,
    required String emptyMessage,
  }) async {
    final actions = await _requestCodeActions(
      resolution: resolution,
      controller: controller,
      range: range,
      diagnostics: diagnostics,
    );
    if (!mounted) {
      return;
    }
    if (actions.isEmpty) {
      _showLspMessage(title: title, message: emptyMessage);
      return;
    }
    _showLspCodeActions(title: title, actions: actions);
  }

  Future<AiLspBackendResolution?> _prepareLspActionWithoutResultBar(
    String title,
  ) async {
    final filePath = widget.activeFilePath;
    final precondition = _cursorLspPreconditionMessage(filePath);
    if (precondition != null) {
      _showLspMessage(title: title, message: precondition);
      return null;
    }
    final resolution = await _ensureLspBackend(filePath);
    if (!resolution.isAvailable) {
      if (mounted) {
        _showLspMessage(
          title: title,
          message: _lspUnavailableMessage(resolution),
        );
      }
      return null;
    }
    return resolution;
  }

  AiLspRange _editorDiagnosticRange(_EditorDiagnostic diagnostic) {
    return AiLspRange(
      start: AiLspPosition(line: diagnostic.line, character: diagnostic.column),
      end: AiLspPosition(
        line: diagnostic.endLine,
        character: diagnostic.endColumn,
      ),
    );
  }

  bool _lspRangesOverlap(AiLspRange left, AiLspRange right) {
    bool isBefore(AiLspPosition a, AiLspPosition b) {
      return a.line < b.line || (a.line == b.line && a.character < b.character);
    }

    return !isBefore(left.end, right.start) && !isBefore(right.end, left.start);
  }

  AiLspDiagnostic _editorDiagnosticToLspDiagnostic(
    _EditorDiagnostic diagnostic,
  ) {
    return AiLspDiagnostic(
      range: _editorDiagnosticRange(diagnostic),
      message: diagnostic.message,
      code: diagnostic.code,
      severity: switch (diagnostic.severity) {
        'ERROR' => 1,
        'WARNING' => 2,
        _ => 3,
      },
    );
  }

  AiLspRange _combinedEditorDiagnosticRange(
    List<_EditorDiagnostic> diagnostics,
  ) {
    var start = AiLspPosition(
      line: diagnostics.first.line,
      character: diagnostics.first.column,
    );
    var end = AiLspPosition(
      line: diagnostics.first.endLine,
      character: diagnostics.first.endColumn,
    );
    for (final diagnostic in diagnostics.skip(1)) {
      final nextStart = AiLspPosition(
        line: diagnostic.line,
        character: diagnostic.column,
      );
      final nextEnd = AiLspPosition(
        line: diagnostic.endLine,
        character: diagnostic.endColumn,
      );
      if (nextStart.line < start.line ||
          (nextStart.line == start.line &&
              nextStart.character < start.character)) {
        start = nextStart;
      }
      if (nextEnd.line > end.line ||
          (nextEnd.line == end.line && nextEnd.character > end.character)) {
        end = nextEnd;
      }
    }
    return AiLspRange(start: start, end: end);
  }

  Future<List<AiLspCodeAction>> _requestCodeActionsForEditorDiagnostics({
    required String title,
    required List<_EditorDiagnostic> diagnostics,
  }) async {
    if (diagnostics.isEmpty) {
      return const <AiLspCodeAction>[];
    }
    final resolution = await _prepareLspActionWithoutResultBar(title);
    if (resolution == null) {
      return const <AiLspCodeAction>[];
    }
    final controller = _textControllers[widget.activeFilePath];
    if (controller == null) {
      return const <AiLspCodeAction>[];
    }

    await _syncOpenDocumentsForLsp();
    final lspDiagnostics = await AiLspClientService.instance.diagnosticsForFile(
      filePath: widget.activeFilePath,
      language: resolution.language,
      documentText: controller.text,
      waitForPublish: false,
    );
    final diagnosticRanges = diagnostics
        .map(_editorDiagnosticRange)
        .toList(growable: false);
    final matchedDiagnostics = lspDiagnostics
        .where((diagnostic) {
          return diagnosticRanges.any(
            (range) => _lspRangesOverlap(diagnostic.range, range),
          );
        })
        .toList(growable: false);

    return _requestCodeActions(
      resolution: resolution,
      controller: controller,
      range: _combinedEditorDiagnosticRange(diagnostics),
      diagnostics: matchedDiagnostics.isNotEmpty
          ? matchedDiagnostics
          : diagnostics
                .map(_editorDiagnosticToLspDiagnostic)
                .toList(growable: false),
    );
  }

  AiLspCodeAction? _preferredDirectQuickFixAction(
    List<AiLspCodeAction> actions,
  ) {
    final applicable = actions
        .where((action) => !action.isDisabled)
        .toList(growable: false);
    if (applicable.isEmpty) {
      return null;
    }
    final quickFixes = applicable
        .where((action) {
          final kind = (action.kind ?? '').trim().toLowerCase();
          return kind.isEmpty || kind.startsWith('quickfix');
        })
        .toList(growable: false);
    final preferredQuickFixes = quickFixes
        .where((action) => action.isPreferred)
        .toList(growable: false);
    if (preferredQuickFixes.isNotEmpty) {
      return preferredQuickFixes.first;
    }
    if (quickFixes.length == 1) {
      return quickFixes.first;
    }
    if (quickFixes.isEmpty && applicable.length == 1) {
      return applicable.first;
    }
    return null;
  }

  Future<void> _applyQuickFixForEditorDiagnostics(
    List<_EditorDiagnostic> diagnostics,
    Offset anchorPosition,
  ) async {
    final title = AppLocalizations.of(context)!.progExpFEQuickFix;
    final noActionsMessage = AppLocalizations.of(
      context,
    )!.progExpFENoQuickFixesAreAvailableFor;
    try {
      final actions = await _requestCodeActionsForEditorDiagnostics(
        title: title,
        diagnostics: diagnostics,
      );
      if (!mounted) {
        return;
      }
      if (actions.isEmpty) {
        _showLspMessage(title: title, message: noActionsMessage);
        return;
      }
      final directAction = _preferredDirectQuickFixAction(actions);
      if (directAction != null) {
        await _applyCodeAction(directAction);
        return;
      }
      await _showInlineCodeActionMenu(
        title: title,
        actions: actions,
        anchorPosition: anchorPosition,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showLspMessage(title: title, message: _friendlyLspError(error));
    }
  }

  Future<void> _showMoreActionsForEditorDiagnostics(
    List<_EditorDiagnostic> diagnostics,
    Offset anchorPosition,
  ) async {
    final title = AppLocalizations.of(context)!.progExpFECodeActions;
    final noActionsMessage = AppLocalizations.of(
      context,
    )!.progExpFENoCodeActionsAreAvailableFor;
    try {
      final actions = await _requestCodeActionsForEditorDiagnostics(
        title: title,
        diagnostics: diagnostics,
      );
      if (!mounted) {
        return;
      }
      if (actions.isEmpty) {
        _showLspMessage(title: title, message: noActionsMessage);
        return;
      }
      await _showInlineCodeActionMenu(
        title: title,
        actions: actions,
        anchorPosition: anchorPosition,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showLspMessage(title: title, message: _friendlyLspError(error));
    }
  }

  Future<void> _showInlineCodeActionMenu({
    required String title,
    required List<AiLspCodeAction> actions,
    required Offset anchorPosition,
  }) async {
    const defaultSubgroupKey = '__default__';

    String groupKeyForAction(AiLspCodeAction action) {
      final kind = (action.kind ?? '').trim().toLowerCase();
      if (kind.isEmpty) {
        return 'quickfix';
      }
      final key = kind.split('.').first;
      if (key == 'quickfix' || key == 'refactor' || key == 'source') {
        return key;
      }
      return 'other';
    }

    int groupPriority(String key) {
      return switch (key) {
        'quickfix' => 0,
        'refactor' => 1,
        'source' => 2,
        _ => 3,
      };
    }

    String groupLabel(String key) {
      return switch (key) {
        'quickfix' => openHandLocalizedText(
          context,
          zh: '快速修复',
          zhHant: '快速修復',
          en: 'Quick Fix',
          fr: 'Correction rapide',
          de: 'Schnellkorrektur',
          ja: 'クイック修正',
        ),
        'refactor' => openHandLocalizedText(
          context,
          zh: '重构',
          zhHant: '重構',
          en: 'Refactor',
          fr: 'Refactoriser',
          de: 'Refaktorieren',
          ja: 'リファクタリング',
        ),
        'source' => openHandLocalizedText(
          context,
          zh: '源码操作',
          zhHant: '原始碼操作',
          en: 'Source',
          fr: 'Source',
          de: 'Quelle',
          ja: 'ソース操作',
        ),
        _ => openHandLocalizedText(
          context,
          zh: '其他操作',
          zhHant: '其他操作',
          en: 'Other Actions',
          fr: 'Autres actions',
          de: 'Weitere Aktionen',
          ja: 'その他の操作',
        ),
      };
    }

    String subgroupKeyForAction(AiLspCodeAction action, String groupKey) {
      final kind = (action.kind ?? '').trim();
      if (kind.isEmpty) {
        return defaultSubgroupKey;
      }
      final segments = kind.split('.');
      if (segments.length < 2) {
        return defaultSubgroupKey;
      }
      if (groupKey == 'other') {
        return segments.length >= 2 ? segments[1] : defaultSubgroupKey;
      }
      return segments[1].trim().isEmpty
          ? defaultSubgroupKey
          : segments[1].trim();
    }

    String humanizeKindSegment(String raw) {
      if (raw.trim().isEmpty || raw == defaultSubgroupKey) {
        return '';
      }
      final normalized = raw
          .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (match) {
            return '${match.group(1)} ${match.group(2)}';
          })
          .replaceAll(RegExp(r'[-_]+'), ' ')
          .replaceAll(kInlineWhitespacePattern, ' ')
          .trim();
      if (normalized.isEmpty) {
        return raw;
      }
      return normalized
          .split(' ')
          .map(
            (word) => word.isEmpty
                ? word
                : '${word[0].toUpperCase()}${word.substring(1)}',
          )
          .join(' ');
    }

    String subgroupLabel(String groupKey, String subgroupKey) {
      if (subgroupKey == defaultSubgroupKey) {
        return switch (groupKey) {
          'quickfix' => openHandLocalizedText(
            context,
            zh: '默认修复',
            zhHant: '預設修復',
            en: 'Default',
            fr: 'Par défaut',
            de: 'Standard',
            ja: '既定',
          ),
          'refactor' => openHandLocalizedText(
            context,
            zh: '通用重构',
            zhHant: '通用重構',
            en: 'General',
            fr: 'Général',
            de: 'Allgemein',
            ja: '一般',
          ),
          'source' => openHandLocalizedText(
            context,
            zh: '通用源码操作',
            zhHant: '通用原始碼操作',
            en: 'General',
            fr: 'Général',
            de: 'Allgemein',
            ja: '一般',
          ),
          _ => openHandLocalizedText(
            context,
            zh: '通用操作',
            zhHant: '通用操作',
            en: 'General',
            fr: 'Général',
            de: 'Allgemein',
            ja: '一般',
          ),
        };
      }
      final humanized = humanizeKindSegment(subgroupKey);
      return humanized.isEmpty ? subgroupKey : humanized;
    }

    int subgroupPriority(String subgroupKey) {
      return subgroupKey == defaultSubgroupKey ? 0 : 1;
    }

    final groupedEntries =
        <String, Map<String, List<(int, AiLspCodeAction)>>>{};
    for (var index = 0; index < actions.length; index++) {
      final action = actions[index];
      final groupKey = groupKeyForAction(action);
      final subgroupKey = subgroupKeyForAction(action, groupKey);
      final subgroups = groupedEntries[groupKey] ??=
          <String, List<(int, AiLspCodeAction)>>{};
      (subgroups[subgroupKey] ??= <(int, AiLspCodeAction)>[]).add((
        index,
        action,
      ));
    }
    final orderedGroups = groupedEntries.entries.toList(growable: false)
      ..sort(
        (left, right) =>
            groupPriority(left.key).compareTo(groupPriority(right.key)),
      );

    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) {
      _showLspCodeActions(title: title, actions: actions);
      return;
    }
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final menuItems = <PopupMenuEntry<int>>[];
    for (var groupIndex = 0; groupIndex < orderedGroups.length; groupIndex++) {
      final groupEntry = orderedGroups[groupIndex];
      final subgroupEntries = groupEntry.value.entries.toList(growable: false)
        ..sort((left, right) {
          final byPriority = subgroupPriority(
            left.key,
          ).compareTo(subgroupPriority(right.key));
          if (byPriority != 0) {
            return byPriority;
          }
          return subgroupLabel(
            groupEntry.key,
            left.key,
          ).toLowerCase().compareTo(
            subgroupLabel(groupEntry.key, right.key).toLowerCase(),
          );
        });
      final showSubgroupHeaders =
          subgroupEntries.length > 1 ||
          subgroupEntries.first.key != defaultSubgroupKey;

      if (groupIndex > 0) {
        menuItems.add(const PopupMenuDivider());
      }
      menuItems.add(
        PopupMenuItem<int>(
          enabled: false,
          height: 28,
          child: Text(
            groupLabel(groupEntry.key),
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ),
      );

      for (
        var subgroupIndex = 0;
        subgroupIndex < subgroupEntries.length;
        subgroupIndex++
      ) {
        final subgroupEntry = subgroupEntries[subgroupIndex];
        if (showSubgroupHeaders) {
          menuItems.add(
            PopupMenuItem<int>(
              enabled: false,
              height: 24,
              child: Padding(
                padding: const EdgeInsets.only(left: 24),
                child: Text(
                  subgroupLabel(groupEntry.key, subgroupEntry.key),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          );
        }

        final sortedEntries = subgroupEntry.value.toList(growable: false)
          ..sort((left, right) {
            if (left.$2.isDisabled != right.$2.isDisabled) {
              return left.$2.isDisabled ? 1 : -1;
            }
            if (left.$2.isPreferred != right.$2.isPreferred) {
              return left.$2.isPreferred ? -1 : 1;
            }
            return left.$2.title.toLowerCase().compareTo(
              right.$2.title.toLowerCase(),
            );
          });
        for (final entry in sortedEntries) {
          menuItems.add(
            PopupMenuItem<int>(
              value: entry.$1,
              enabled: !entry.$2.isDisabled,
              child: SizedBox(
                width: 320,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(
                        top: 1,
                        left: showSubgroupHeaders ? 16 : 0,
                      ),
                      child: Icon(
                        _codeActionIcon(entry.$2),
                        size: 16,
                        color: entry.$2.isDisabled
                            ? colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.45,
                              )
                            : colorScheme.primary,
                      ),
                    ),
                    kOpenHandHGap8,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  entry.$2.title,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: entry.$2.isDisabled
                                        ? colorScheme.onSurfaceVariant
                                        : colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              if (entry.$2.isPreferred)
                                Icon(
                                  Icons.star_rounded,
                                  size: 14,
                                  color: colorScheme.primary,
                                ),
                            ],
                          ),
                          kOpenHandGap2,
                          Text(
                            _codeActionSummary(entry.$2),
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant,
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
      }
    }
    final selectedIndex = await showAnimatedPointerMenu<int>(
      context: context,
      globalPosition: anchorPosition,
      items: menuItems,
    );
    if (selectedIndex == null || !mounted) {
      return;
    }
    final selectedAction = actions[selectedIndex];
    if (selectedAction.isDisabled) {
      return;
    }
    unawaited(_applyCodeAction(selectedAction));
  }

  Future<void> _showCodeActionsForDiagnosticLine(
    int lineNumber,
    Offset anchorPosition,
  ) async {
    final title = AppLocalizations.of(context)!.progExpFEQuickFix;
    final noDiagnosticsMessage = AppLocalizations.of(
      context,
    )!.progExpFENoQuickFixesAreAvailableFor2;
    final resolution = await _prepareLspActionWithoutResultBar(title);
    if (resolution == null) {
      return;
    }
    final controller = _textControllers[widget.activeFilePath];
    if (controller == null) {
      return;
    }
    try {
      await _syncOpenDocumentsForLsp();
      final diagnostics = await AiLspClientService.instance.diagnosticsForFile(
        filePath: widget.activeFilePath,
        language: resolution.language,
        documentText: controller.text,
        waitForPublish: false,
      );
      final lineDiagnostics = diagnostics
          .where((item) {
            return lineNumber >= item.range.start.line &&
                lineNumber <= item.range.end.line;
          })
          .toList(growable: false);
      if (lineDiagnostics.isEmpty) {
        _showLspMessage(title: title, message: noDiagnosticsMessage);
        return;
      }

      var start = lineDiagnostics.first.range.start;
      var end = lineDiagnostics.first.range.end;
      for (final diagnostic in lineDiagnostics.skip(1)) {
        final nextStart = diagnostic.range.start;
        final nextEnd = diagnostic.range.end;
        if (nextStart.line < start.line ||
            (nextStart.line == start.line &&
                nextStart.character < start.character)) {
          start = nextStart;
        }
        if (nextEnd.line > end.line ||
            (nextEnd.line == end.line && nextEnd.character > end.character)) {
          end = nextEnd;
        }
      }

      _jumpToLineColumn(lineNumber, column: start.character);
      final menuTitle = '$title  •  $lineNumber';
      final actions = await _requestCodeActions(
        resolution: resolution,
        controller: controller,
        range: AiLspRange(start: start, end: end),
        diagnostics: lineDiagnostics,
      );
      if (!mounted) {
        return;
      }
      if (actions.isEmpty) {
        _showLspMessage(title: menuTitle, message: noDiagnosticsMessage);
        return;
      }
      await _showInlineCodeActionMenu(
        title: menuTitle,
        actions: actions,
        anchorPosition: anchorPosition,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showLspMessage(title: title, message: _friendlyLspError(error));
    }
  }

  Future<void> _maybeRefreshDiagnostics(String filePath) async {
    if (_diagnosticsByFile.containsKey(filePath) ||
        _diagnosticsLoadingFiles.contains(filePath)) {
      return;
    }
    await _refreshDiagnostics(filePath);
  }

  Future<void> _refreshDiagnostics(String filePath) async {
    if (_diagnosticsLoadingFiles.contains(filePath)) {
      // 当前已有请求时排队补拉，确保完成后诊断最新内容。
      _diagnosticsPendingRefresh.add(filePath);
      return;
    }
    late final AiLspBackendResolution resolution;
    try {
      resolution = await _ensureLspBackend(filePath);
    } catch (error, stack) {
      if (mounted && widget.openFiles.contains(filePath)) {
        silentLog('file_explorer', '解析 LSP 诊断后端', error, stack);
      }
      return;
    }
    if (!mounted || !widget.openFiles.contains(filePath)) return;
    if (!resolution.isAvailable) {
      setState(() {
        _diagnosticsByFile.remove(filePath);
        _diagnosticsStaleFiles.remove(filePath);
      });
      return;
    }
    final requestToken = Object();
    _lspDiagnosticsRequestTokens[filePath] = requestToken;
    setState(() => _diagnosticsLoadingFiles.add(filePath));
    try {
      final controller = _textControllers[filePath];
      final diagnostics = await AiLspClientService.instance.diagnosticsForFile(
        filePath: filePath,
        language: resolution.language,
        documentText: controller?.text,
      );
      if (!mounted ||
          !widget.openFiles.contains(filePath) ||
          !identical(_lspDiagnosticsRequestTokens[filePath], requestToken)) {
        return;
      }
      setState(() {
        _diagnosticsLoadingFiles.remove(filePath);
        _diagnosticsByFile[filePath] = _mapLspDiagnostics(diagnostics);
        _diagnosticsStaleFiles.remove(filePath);
      });
    } catch (error, stack) {
      if (!mounted ||
          !widget.openFiles.contains(filePath) ||
          !identical(_lspDiagnosticsRequestTokens[filePath], requestToken)) {
        return;
      }
      silentLog('file_explorer', '刷新 LSP 诊断', error, stack);
      setState(() {
        _diagnosticsLoadingFiles.remove(filePath);
        _diagnosticsByFile.remove(filePath);
      });
    }

    if (!mounted ||
        !widget.openFiles.contains(filePath) ||
        !identical(_lspDiagnosticsRequestTokens[filePath], requestToken)) {
      return;
    }
    _lspDiagnosticsRequestTokens.remove(filePath);
    // 请求期间有新改动时立即补拉一次。
    if (_diagnosticsPendingRefresh.remove(filePath)) {
      unawaited(_refreshDiagnostics(filePath));
    }
  }

  String? _cursorLspPreconditionMessage(String filePath) {
    final controller = _textControllers[filePath];
    if (controller == null) {
      return AppLocalizations.of(
        context,
      )!.progExpFETheCurrentFileIsStillLoading;
    }
    if (controller.useVirtualizedPreview &&
        !_forcedFullEditorFiles.contains(filePath)) {
      return AppLocalizations.of(context)!.progExpFEThisFileIsStillInLarge2;
    }
    return null;
  }

  String? _documentLspPreconditionMessage(String filePath) {
    final controller = _textControllers[filePath];
    if (controller == null) {
      return AppLocalizations.of(
        context,
      )!.progExpFETheCurrentFileIsStillLoading2;
    }
    if (controller.useVirtualizedPreview &&
        !_forcedFullEditorFiles.contains(filePath)) {
      return AppLocalizations.of(context)!.progExpFEThisFileIsStillInLarge3;
    }
    return null;
  }

  String _lspUnavailableMessage(AiLspBackendResolution resolution) {
    return switch (resolution.availability) {
      AiLspBackendAvailability.unsupportedLanguage => openHandLocalizedText(
        context,
        zh: '当前语言 ${_programmingLanguageLabel(context, resolution.language)} 还没有映射到 LSP 后端。',
        zhHant:
            '目前語言 ${_programmingLanguageLabel(context, resolution.language)} 尚未對應到 LSP 後端。',
        en: 'No LSP backend mapping is configured for ${_programmingLanguageLabel(context, resolution.language)}.',
        fr: 'Aucun backend LSP n’est configuré pour ${_programmingLanguageLabel(context, resolution.language)}.',
        de: 'Für ${_programmingLanguageLabel(context, resolution.language)} ist kein LSP-Backend konfiguriert.',
        ja: '${_programmingLanguageLabel(context, resolution.language)} には LSP バックエンドのマッピングが設定されていません。',
      ),
      AiLspBackendAvailability.executableNotFound =>
        resolution.configuredInstallRoot?.trim().isNotEmpty == true
            ? openHandLocalizedText(
                context,
                zh: '已识别到 ${resolution.displayName ?? resolution.backendId}，但在你配置的 LSP 根路径 ${OpenHandPaths.shortenHomePath(resolution.configuredInstallRoot!)} 中没有找到命令 ${resolution.executable ?? ''}。',
                zhHant:
                    '已識別到 ${resolution.displayName ?? resolution.backendId}，但在你設定的 LSP 根路徑 ${OpenHandPaths.shortenHomePath(resolution.configuredInstallRoot!)} 中找不到命令 ${resolution.executable ?? ''}。',
                en: 'The editor resolved ${resolution.displayName ?? resolution.backendId}, but ${resolution.executable ?? ''} was not found inside the configured LSP root ${OpenHandPaths.shortenHomePath(resolution.configuredInstallRoot!)}.',
                fr: 'L’éditeur a résolu ${resolution.displayName ?? resolution.backendId}, mais ${resolution.executable ?? ''} est introuvable dans la racine LSP configurée ${OpenHandPaths.shortenHomePath(resolution.configuredInstallRoot!)}.',
                de: 'Der Editor hat ${resolution.displayName ?? resolution.backendId} aufgelöst, aber ${resolution.executable ?? ''} wurde im konfigurierten LSP-Stamm ${OpenHandPaths.shortenHomePath(resolution.configuredInstallRoot!)} nicht gefunden.',
                ja: 'エディタは ${resolution.displayName ?? resolution.backendId} を解決しましたが、設定済み LSP ルート ${OpenHandPaths.shortenHomePath(resolution.configuredInstallRoot!)} 内に ${resolution.executable ?? ''} が見つかりません。',
              )
            : openHandLocalizedText(
                context,
                zh: '已识别到 ${resolution.displayName ?? resolution.backendId}，但本机 PATH 中没有找到命令 ${resolution.executable ?? ''}。',
                zhHant:
                    '已識別到 ${resolution.displayName ?? resolution.backendId}，但本機 PATH 中找不到命令 ${resolution.executable ?? ''}。',
                en: 'The editor resolved ${resolution.displayName ?? resolution.backendId}, but ${resolution.executable ?? ''} was not found on PATH.',
                fr: 'L’éditeur a résolu ${resolution.displayName ?? resolution.backendId}, mais ${resolution.executable ?? ''} est introuvable dans PATH.',
                de: 'Der Editor hat ${resolution.displayName ?? resolution.backendId} aufgelöst, aber ${resolution.executable ?? ''} wurde im PATH nicht gefunden.',
                ja: 'エディタは ${resolution.displayName ?? resolution.backendId} を解決しましたが、PATH に ${resolution.executable ?? ''} が見つかりません。',
              ),
      AiLspBackendAvailability.available => openHandLocalizedText(
        context,
        zh: 'LSP 后端已就绪。',
        zhHant: 'LSP 後端已就緒。',
        en: 'The LSP backend is ready.',
        fr: 'Le backend LSP est prêt.',
        de: 'Das LSP-Backend ist bereit.',
        ja: 'LSP バックエンドの準備ができています。',
      ),
    };
  }

  /// 呈现 LSP 结果条：整体重置结果区状态并收起其余编辑器浮层，
  /// 五个入口只描述各自差异，避免同一段状态机被反复抄写。
  void _presentLspResult({
    required String title,
    bool loading = false,
    String? message,
    List<AiLspLocation> locations = const <AiLspLocation>[],
    List<AiLspCodeAction> codeActions = const <AiLspCodeAction>[],
    AiLspHoverResult? hover,
    bool previewLoading = false,
  }) {
    if (!mounted) return;
    setState(() {
      _lspResultBarVisible = true;
      _lspResultLoading = loading;
      _lspResultTitle = title;
      _lspResultMessage = message;
      _lspResultLocations = locations;
      _lspResultCodeActions = codeActions;
      _lspResultPreviewLoading = previewLoading;
      _lspResultPreviews = const <String, _EditorLocationPreview>{};
      _lspHoverResult = hover;
      _symbolBarVisible = false;
      _projectToolchainBarVisible = false;
      _diagnosticsBarVisible = false;
      _findBarVisible = false;
      _replaceBarVisible = false;
      _goToLineVisible = false;
      _completionVisible = false;
      _signatureHelpVisible = false;
      _signatureHelp = null;
    });
  }

  void _showLspLoading(String title) {
    _lspResultPreviewEpoch += 1;
    _presentLspResult(title: title, loading: true);
  }

  void _showLspMessage({required String title, required String message}) {
    _lspResultPreviewEpoch += 1;
    _presentLspResult(title: title, message: message);
  }

  void _showLspLocations({
    required String title,
    required List<AiLspLocation> locations,
    String? message,
  }) {
    final previewEpoch = ++_lspResultPreviewEpoch;
    _presentLspResult(
      title: title,
      message: message,
      locations: locations,
      previewLoading: locations.isNotEmpty,
    );
    if (locations.isNotEmpty) {
      unawaited(_loadLspLocationPreviews(locations, previewEpoch));
    }
  }

  void _showLspCodeActions({
    required String title,
    required List<AiLspCodeAction> actions,
    String? message,
  }) {
    _lspResultPreviewEpoch += 1;
    _presentLspResult(title: title, message: message, codeActions: actions);
  }

  void _showLspHoverResult({
    required String title,
    required AiLspHoverResult hover,
  }) {
    _lspResultPreviewEpoch += 1;
    _presentLspResult(title: title, hover: hover);
  }

  void _hideLspResultBar() {
    _lspResultPreviewEpoch += 1;
    setState(() {
      _lspResultBarVisible = false;
      _lspResultLoading = false;
      _lspResultTitle = '';
      _lspResultMessage = null;
      _lspResultLocations = const <AiLspLocation>[];
      _lspResultCodeActions = const <AiLspCodeAction>[];
      _lspResultPreviewLoading = false;
      _lspResultPreviews = const <String, _EditorLocationPreview>{};
      _lspHoverResult = null;
      _signatureHelpVisible = false;
      _signatureHelp = null;
    });
  }

  Future<void> _navigateToLspLocation(AiLspLocation location) async {
    if (location.filePath == widget.activeFilePath) {
      _jumpToLineColumn(location.line, column: location.character);
      return;
    }
    _pendingNavigationLocation = location;
    widget.onOpenFile(location.filePath);
  }

  Future<AiLspBackendResolution?> _prepareCursorLspAction(String title) async {
    final filePath = widget.activeFilePath;
    final precondition = _cursorLspPreconditionMessage(filePath);
    if (precondition != null) {
      _showLspMessage(title: title, message: precondition);
      return null;
    }
    _showLspLoading(title);
    final resolution = await _ensureLspBackend(filePath);
    if (!resolution.isAvailable) {
      if (mounted) {
        _showLspMessage(
          title: title,
          message: _lspUnavailableMessage(resolution),
        );
      }
      return null;
    }
    return resolution;
  }

  Future<void> _formatDocument(String filePath) async {
    final title = AppLocalizations.of(context)!.progExpFEFormatDocument;
    final precondition = _documentLspPreconditionMessage(filePath);
    if (precondition != null) {
      _showLspMessage(title: title, message: precondition);
      return;
    }

    final controller = _textControllers[filePath];
    if (controller == null) {
      _showLspMessage(
        title: title,
        message: AppLocalizations.of(
          context,
        )!.progExpFETheCurrentFileIsNotReady,
      );
      return;
    }

    _showLspLoading(title);
    try {
      final resolution = await _ensureLspBackend(filePath);
      if (!mounted) {
        return;
      }
      if (!resolution.isAvailable) {
        _showLspMessage(
          title: title,
          message: _lspUnavailableMessage(resolution),
        );
        return;
      }

      final edits = await AiLspClientService.instance.formatDocument(
        filePath: filePath,
        language: resolution.language,
        documentText: controller.text,
        tabSize: context.read<SettingsController>().editorIndentSpaces,
      );
      if (!mounted) {
        return;
      }
      if (edits.isEmpty) {
        _showLspMessage(
          title: title,
          message: AppLocalizations.of(
            context,
          )!.progExpFETheFormatterDidNotReturnAny,
        );
        return;
      }

      final nextText = _applyTextEdits(controller.text, edits);
      if (nextText == controller.text) {
        _showLspMessage(
          title: title,
          message: AppLocalizations.of(
            context,
          )!.progExpFEFormattingProducedTheSameContentSo,
        );
        return;
      }

      final currentSelection = controller.selection;
      _commitProgrammaticEditorValueChange(
        filePath,
        controller,
        TextEditingValue(
          text: nextText,
          selection: currentSelection.copyWith(
            baseOffset: currentSelection.baseOffset.clamp(0, nextText.length),
            extentOffset: currentSelection.extentOffset.clamp(
              0,
              nextText.length,
            ),
          ),
        ),
        dismissCompletionOverlay: true,
      );
      _showLspMessage(
        title: title,
        message: AppLocalizations.of(
          context,
        )!.progExpFEAppliedEditsLengthFormattingEdits(edits.length),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showLspMessage(title: title, message: _friendlyLspError(error));
    }
  }

  Future<void> _goToDefinitionAtCursor() async {
    final title = AppLocalizations.of(context)!.progExpFEGoToDefinition;
    final resolution = await _prepareCursorLspAction(title);
    if (resolution == null) {
      return;
    }
    final controller = _textControllers[widget.activeFilePath];
    if (controller == null) {
      return;
    }
    try {
      final locations = await AiLspClientService.instance.goToDefinition(
        filePath: widget.activeFilePath,
        line: _cursorLine,
        character: _cursorColumn,
        language: resolution.language,
        documentText: controller.text,
      );
      if (!mounted) {
        return;
      }
      if (locations.isEmpty) {
        _showLspMessage(
          title: title,
          message: AppLocalizations.of(
            context,
          )!.progExpFENoDefinitionWasFoundAtThe,
        );
        return;
      }
      if (locations.length == 1) {
        _hideLspResultBar();
        await _navigateToLspLocation(locations.first);
        return;
      }
      _showLspLocations(
        title: title,
        locations: locations,
        message: AppLocalizations.of(
          context,
        )!.progExpFEMultipleDefinitionsWereFoundChooseA,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showLspMessage(title: title, message: _friendlyLspError(error));
    }
  }

  Future<void> _findReferencesAtCursor() async {
    final title = AppLocalizations.of(context)!.progExpFEFindReferences;
    final resolution = await _prepareCursorLspAction(title);
    if (resolution == null) {
      return;
    }
    final controller = _textControllers[widget.activeFilePath];
    if (controller == null) {
      return;
    }
    try {
      final locations = await AiLspClientService.instance.findReferences(
        filePath: widget.activeFilePath,
        line: _cursorLine,
        character: _cursorColumn,
        language: resolution.language,
        documentText: controller.text,
      );
      if (!mounted) {
        return;
      }
      if (locations.isEmpty) {
        _showLspMessage(
          title: title,
          message: AppLocalizations.of(
            context,
          )!.progExpFENoReferencesWereFoundAtThe,
        );
        return;
      }
      _showLspLocations(title: title, locations: locations);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showLspMessage(title: title, message: _friendlyLspError(error));
    }
  }

  Future<void> _showHoverAtCursor() async {
    final title = AppLocalizations.of(context)!.progExpFEHoverInfo;
    final resolution = await _prepareCursorLspAction(title);
    if (resolution == null) {
      return;
    }
    final controller = _textControllers[widget.activeFilePath];
    if (controller == null) {
      return;
    }
    try {
      final hover = await AiLspClientService.instance.hover(
        filePath: widget.activeFilePath,
        line: _cursorLine,
        character: _cursorColumn,
        language: resolution.language,
        documentText: controller.text,
      );
      if (!mounted) {
        return;
      }
      if (hover == null || hover.renderedText.trim().isEmpty) {
        _showLspMessage(
          title: title,
          message: AppLocalizations.of(
            context,
          )!.progExpFEThereIsNoHoverInformationAt,
        );
        return;
      }
      _showLspHoverResult(title: title, hover: hover);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showLspMessage(title: title, message: _friendlyLspError(error));
    }
  }

  @override
  void dispose() {
    _fileLoadGenerations.clear();
    _zoomCommitTimer?.cancel();
    _completionDebounceTimer?.cancel();
    _signatureHelpDebounceTimer?.cancel();
    _dismissCompletionOverlay();
    _symbolController.removeListener(_applySymbolFilter);
    _symbolRefreshTimer?.cancel();
    AiLspClientService.instance.workspaceEditHandler = null;
    AiLspClientService.instance.diagnosticsPushCallback = null;
    AiLspClientService.instance.updateProjectLanguageSettingsOverride(null);
    for (final timer in _lspDiagnosticsTimers.values) {
      timer.cancel();
    }
    _lspDiagnosticsRequestTokens.clear();
    for (final filePath in _textControllers.keys) {
      unawaited(
        AiLspClientService.instance.closeDocument(
          filePath: filePath,
          language: _resolvedLanguageForFile(filePath),
        ),
      );
    }
    for (final controller in _scrollControllers.values) {
      controller.dispose();
    }
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    _symbolController.dispose();
    _symbolFocusNode.dispose();
    _findController.dispose();
    _replaceController.dispose();
    _findFocusNode.dispose();
    _goToLineController.dispose();
    _goToLineFocusNode.dispose();
    super.dispose();
  }

  // ── Find & Replace ──

  void _showFind() {
    if (_findBarVisible && !_replaceBarVisible) {
      _hideFindBar();
      return;
    }
    setState(() {
      _findBarVisible = true;
      _replaceBarVisible = false;
      _goToLineVisible = false;
      _symbolBarVisible = false;
      _projectToolchainBarVisible = false;
      _diagnosticsBarVisible = false;
      _lspResultBarVisible = false;
      _completionVisible = false;
      _signatureHelpVisible = false;
      _signatureHelp = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _findFocusNode.requestFocus();
    });
  }

  void _showFindAndReplace() {
    if (_findBarVisible && _replaceBarVisible) {
      _hideFindBar();
      return;
    }
    setState(() {
      _findBarVisible = true;
      _replaceBarVisible = true;
      _goToLineVisible = false;
      _symbolBarVisible = false;
      _projectToolchainBarVisible = false;
      _diagnosticsBarVisible = false;
      _lspResultBarVisible = false;
      _completionVisible = false;
      _signatureHelpVisible = false;
      _signatureHelp = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _findFocusNode.requestFocus();
    });
  }

  void _hideFindBar() {
    setState(() {
      _findBarVisible = false;
      _replaceBarVisible = false;
      _findMatchOffsets = const [];
      _currentMatchIndex = -1;
    });
  }

  void _updateFindMatches(String query) {
    if (query.isEmpty) {
      setState(() {
        _findMatchOffsets = const [];
        _currentMatchIndex = -1;
      });
      return;
    }
    final controller = _textControllers[widget.activeFilePath];
    if (controller == null) return;
    final offsets = findTextMatchOffsets(
      text: controller.text,
      query: query,
      caseSensitive: _findCaseSensitive,
    );
    setState(() {
      _findMatchOffsets = offsets;
      _currentMatchIndex = offsets.isEmpty ? -1 : 0;
    });
    if (offsets.isNotEmpty) {
      _selectMatch(0);
    }
  }

  void _findNext() {
    if (_findMatchOffsets.isEmpty) return;
    final next = (_currentMatchIndex + 1) % _findMatchOffsets.length;
    setState(() => _currentMatchIndex = next);
    _selectMatch(next);
  }

  void _findPrevious() {
    if (_findMatchOffsets.isEmpty) return;
    final prev =
        (_currentMatchIndex - 1 + _findMatchOffsets.length) %
        _findMatchOffsets.length;
    setState(() => _currentMatchIndex = prev);
    _selectMatch(prev);
  }

  void _selectMatch(int index) {
    if (index < 0 || index >= _findMatchOffsets.length) return;
    final controller = _textControllers[widget.activeFilePath];
    if (controller == null) return;
    final offset = _findMatchOffsets[index];
    final length = _findController.text.length;
    controller.selection = TextSelection(
      baseOffset: offset,
      extentOffset: offset + length,
    );
    _updateCursorPosition(controller);
    final focusNode = _focusNodes[widget.activeFilePath];
    focusNode?.requestFocus();
    _scrollToLine(widget.activeFilePath, _lineForOffset(controller, offset));
  }

  void _replaceCurrent() {
    if (_currentMatchIndex < 0 ||
        _currentMatchIndex >= _findMatchOffsets.length) {
      return;
    }
    final controller = _textControllers[widget.activeFilePath];
    if (controller == null) return;
    final offset = _findMatchOffsets[_currentMatchIndex];
    final findLen = _findController.text.length;
    final replaceText = _replaceController.text;
    final text = controller.text;
    controller.text = text.replaceRange(offset, offset + findLen, replaceText);
    controller.selection = TextSelection.collapsed(
      offset: offset + replaceText.length,
    );
    setState(() {
      _fileDirty[widget.activeFilePath] = true;
      _diagnosticsStaleFiles.add(widget.activeFilePath);
    });
    _scheduleDiagnosticsRefresh(widget.activeFilePath);
    if (_symbolBarVisible) {
      _scheduleSymbolRefresh(immediate: true);
    }
    _updateFindMatches(_findController.text);
  }

  void _replaceAll() {
    final controller = _textControllers[widget.activeFilePath];
    if (controller == null || _findController.text.isEmpty) return;
    final findText = _findController.text;
    final replaceText = _replaceController.text;
    if (_findCaseSensitive) {
      controller.text = controller.text.replaceAll(findText, replaceText);
    } else {
      controller.text = controller.text.replaceAll(
        RegExp(RegExp.escape(findText), caseSensitive: false),
        replaceText,
      );
    }
    setState(() {
      _fileDirty[widget.activeFilePath] = true;
      _diagnosticsStaleFiles.add(widget.activeFilePath);
      _findMatchOffsets = const [];
      _currentMatchIndex = -1;
    });
    _scheduleDiagnosticsRefresh(widget.activeFilePath);
    if (_symbolBarVisible) {
      _scheduleSymbolRefresh(immediate: true);
    }
    _updateFindMatches(findText);
  }

  // ── Go To Line ──

  void _showGoToLine() {
    final controller = _textControllers[widget.activeFilePath];
    if (_goToLineVisible) {
      setState(() => _goToLineVisible = false);
      return;
    }
    setState(() {
      _goToLineVisible = true;
      _findBarVisible = false;
      _replaceBarVisible = false;
      _symbolBarVisible = false;
      _projectToolchainBarVisible = false;
      _diagnosticsBarVisible = false;
      _lspResultBarVisible = false;
      _goToLineController.text = '';
      _completionVisible = false;
      _signatureHelpVisible = false;
      _signatureHelp = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _goToLineFocusNode.requestFocus();
    });
    if (controller != null) {
      _goToLineController.text = '$_cursorLine';
      _goToLineController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: '$_cursorLine'.length,
      );
    }
  }

  bool _supportsDiagnosticsForFile(String filePath) {
    return _supportsLspForFile(filePath);
  }

  String _diagnosticsUnavailableMessage(String filePath) {
    final resolution = _lspResolutionForFile(filePath);
    if (_lspBackendLoadingFiles.contains(filePath) && resolution == null) {
      return openHandLocalizedText(
        context,
        zh: '正在为当前文件解析 LSP 后端…',
        zhHant: '正在為目前檔案解析 LSP 後端…',
        en: 'Resolving an LSP backend for the current file...',
        fr: 'Résolution du backend LSP pour le fichier actuel...',
        de: 'LSP-Backend für die aktuelle Datei wird aufgelöst...',
        ja: '現在のファイルの LSP バックエンドを解決中...',
      );
    }
    if (resolution == null) {
      return openHandLocalizedText(
        context,
        zh: '当前文件的 LSP 后端尚未解析完成。',
        zhHant: '目前檔案的 LSP 後端尚未解析完成。',
        en: 'The LSP backend for this file has not been resolved yet.',
        fr: 'Le backend LSP de ce fichier n’est pas encore résolu.',
        de: 'Das LSP-Backend für diese Datei wurde noch nicht aufgelöst.',
        ja: 'このファイルの LSP バックエンドはまだ解決されていません。',
      );
    }
    return _lspUnavailableMessage(resolution);
  }

  String _lspBackendStatusLabel(BuildContext context, String filePath) {
    final resolution = _lspResolutionForFile(filePath);
    if (_lspBackendLoadingFiles.contains(filePath) && resolution == null) {
      return openHandLocalizedText(
        context,
        zh: 'LSP 解析中',
        zhHant: 'LSP 解析中',
        en: 'LSP...',
        fr: 'LSP...',
        de: 'LSP...',
        ja: 'LSP...',
      );
    }
    if (resolution == null) {
      return 'LSP';
    }
    if (resolution.isAvailable) {
      return resolution.displayName ??
          resolution.backendId ??
          _programmingLanguageLabel(context, resolution.language);
    }
    return openHandLocalizedText(
      context,
      zh: '无 LSP',
      zhHant: '無 LSP',
      en: 'No LSP',
      fr: 'Pas de LSP',
      de: 'Kein LSP',
      ja: 'LSP なし',
    );
  }

  bool _hasProjectToolchainOverride() {
    final projectLanguage = normalizeAiLspLanguage(widget.projectLanguage);
    if (projectLanguage == 'mixed' || projectLanguage == 'plaintext') {
      return false;
    }
    return widget.projectSdkPath.trim().isNotEmpty ||
        widget.projectLspPath.trim().isNotEmpty;
  }

  String _projectToolchainStatusLabel(BuildContext context, String filePath) {
    final projectLanguage = normalizeAiLspLanguage(widget.projectLanguage);
    final hasOverride = _hasProjectToolchainOverride();
    final isResolving =
        _lspBackendLoadingFiles.contains(filePath) &&
        _lspResolutionForFile(filePath) == null;
    if (isResolving && hasOverride) {
      return openHandLocalizedText(
        context,
        zh: '项目重绑',
        zhHant: '專案重綁',
        en: 'Rebinding',
        fr: 'Reliaison',
        de: 'Neu binden',
        ja: '再バインド',
      );
    }
    if (isResolving) {
      return openHandLocalizedText(
        context,
        zh: '解析中',
        zhHant: '解析中',
        en: 'Resolving',
        fr: 'Résolution',
        de: 'Auflösen',
        ja: '解決中',
      );
    }
    if (projectLanguage == 'mixed') {
      return openHandLocalizedText(
        context,
        zh: '混合模式',
        zhHant: '混合模式',
        en: 'Mixed',
        fr: 'Mixte',
        de: 'Gemischt',
        ja: '混在',
      );
    }
    if (hasOverride) {
      return openHandLocalizedText(
        context,
        zh: '项目覆盖',
        zhHant: '專案覆寫',
        en: 'Project',
        fr: 'Projet',
        de: 'Projekt',
        ja: 'プロジェクト',
      );
    }
    return openHandLocalizedText(
      context,
      zh: '全局默认',
      zhHant: '全域預設',
      en: 'Global',
      fr: 'Global',
      de: 'Global',
      ja: 'グローバル',
    );
  }

  Color _projectToolchainStatusColor(ColorScheme colorScheme, String filePath) {
    final projectLanguage = normalizeAiLspLanguage(widget.projectLanguage);
    final hasOverride = _hasProjectToolchainOverride();
    final isResolving =
        _lspBackendLoadingFiles.contains(filePath) &&
        _lspResolutionForFile(filePath) == null;
    if (isResolving) {
      return colorScheme.primary;
    }
    if (hasOverride) {
      return colorScheme.primary;
    }
    if (projectLanguage == 'mixed') {
      return colorScheme.tertiary;
    }
    return colorScheme.onSurfaceVariant;
  }

  String _projectToolchainStatusTooltip(BuildContext context, String filePath) {
    final projectLanguage = normalizeAiLspLanguage(widget.projectLanguage);
    final hasOverride = _hasProjectToolchainOverride();
    final isResolving =
        _lspBackendLoadingFiles.contains(filePath) &&
        _lspResolutionForFile(filePath) == null;
    if (isResolving && hasOverride) {
      return openHandLocalizedText(
        context,
        zh: '项目级 SDK / LSP 覆盖刚刚更新，当前文件正在重新绑定后端。',
        zhHant: '專案級 SDK / LSP 覆寫剛剛更新，目前檔案正在重新綁定後端。',
        en: 'Project-level SDK / LSP overrides were updated and the current file is rebinding its backend.',
        fr: 'Les remplacements SDK / LSP du projet ont été mis à jour ; le fichier actuel relie à nouveau son backend.',
        de: 'Projektweite SDK-/LSP-Überschreibungen wurden aktualisiert; die aktuelle Datei bindet ihr Backend neu.',
        ja: 'プロジェクト単位の SDK / LSP 上書きが更新され、現在のファイルはバックエンドを再バインド中です。',
      );
    }
    if (projectLanguage == 'mixed') {
      return openHandLocalizedText(
        context,
        zh: '混合模式下会按文件类型自动识别语言，并继续使用全局的按语言配置。点击展开来源树可查看当前文件命中的语言映射。',
        zhHant: '混合模式會依檔案類型自動識別語言，並繼續使用全域的各語言設定。點擊展開來源樹可查看目前檔案命中的語言對應。',
        en: 'Mixed mode auto-detects the language per file and continues using the global per-language mappings. Expand the panel to inspect which mapping was matched for the current file.',
        fr: 'Le mode mixte détecte le langage par fichier et utilise les correspondances globales. Dépliez le panneau pour voir la correspondance utilisée.',
        de: 'Der gemischte Modus erkennt die Sprache pro Datei und nutzt globale Sprachzuordnungen. Klappe das Panel auf, um die Zuordnung zu prüfen.',
        ja: '混在モードではファイルごとに言語を自動検出し、グローバルな言語別設定を使います。パネルを展開して現在のファイルに一致したマッピングを確認できます。',
      );
    }
    if (hasOverride) {
      return openHandLocalizedText(
        context,
        zh: '当前项目对 SDK 或 LSP 路径做了覆盖，点击展开项目级生效面板与来源树。',
        zhHant: '目前專案已覆寫 SDK 或 LSP 路徑，點擊可展開專案級生效面板與來源樹。',
        en: 'The current project overrides the SDK or LSP root. Click to expand the project-level status panel and source tree.',
        fr: 'Le projet actuel remplace la racine SDK ou LSP. Cliquez pour ouvrir le panneau d’état et l’arbre des sources.',
        de: 'Das aktuelle Projekt überschreibt den SDK- oder LSP-Stamm. Klicke, um Statuspanel und Quellbaum zu öffnen.',
        ja: '現在のプロジェクトは SDK または LSP パスを上書きしています。クリックすると状態パネルとソースツリーを展開します。',
      );
    }
    return openHandLocalizedText(
      context,
      zh: '当前项目没有单独覆盖，点击展开当前继承关系和全局映射命中来源。',
      zhHant: '目前專案沒有單獨覆寫，點擊可展開目前繼承關係與全域映射命中來源。',
      en: 'This project has no dedicated override. Click to expand the current inheritance details and the matched global mapping.',
      fr: 'Ce projet n’a pas de remplacement dédié. Cliquez pour voir l’héritage actuel et la correspondance globale.',
      de: 'Dieses Projekt hat keine eigene Überschreibung. Klicke, um Vererbung und globale Zuordnung anzuzeigen.',
      ja: 'このプロジェクトには個別の上書きがありません。クリックすると継承関係と一致したグローバルマッピングを表示します。',
    );
  }

  void _toggleProjectToolchainBar() {
    final shouldOpen = !_projectToolchainBarVisible;
    setState(() {
      _projectToolchainBarVisible = shouldOpen;
      if (shouldOpen) {
        _findBarVisible = false;
        _replaceBarVisible = false;
        _goToLineVisible = false;
        _symbolBarVisible = false;
        _diagnosticsBarVisible = false;
        _lspResultBarVisible = false;
      }
    });
    if (shouldOpen) {
      unawaited(
        _ensureLspBackend(
          widget.activeFilePath,
          force: _lspResolutionForFile(widget.activeFilePath) == null,
        ),
      );
    }
  }

  Color _lspBackendStatusColor(ColorScheme colorScheme, String filePath) {
    final resolution = _lspResolutionForFile(filePath);
    if (_lspBackendLoadingFiles.contains(filePath) && resolution == null) {
      return colorScheme.primary;
    }
    if (resolution == null) {
      return colorScheme.onSurfaceVariant;
    }
    if (resolution.isAvailable) {
      return colorScheme.onSurfaceVariant;
    }
    return resolution.availability ==
            AiLspBackendAvailability.executableNotFound
        ? colorScheme.error
        : colorScheme.onSurfaceVariant;
  }

  Color _lspActionColor(ColorScheme colorScheme, String filePath) {
    final resolution = _lspResolutionForFile(filePath);
    if (_lspBackendLoadingFiles.contains(filePath) && resolution == null) {
      return colorScheme.primary;
    }
    if (resolution?.isAvailable == true) {
      return colorScheme.onSurfaceVariant;
    }
    return colorScheme.onSurfaceVariant.withValues(alpha: 0.55);
  }

  String _displayPathForFilePath(String filePath) {
    final activeRoot = _lspResolutionForFile(widget.activeFilePath)?.rootPath;
    if (activeRoot != null && activeRoot.isNotEmpty) {
      try {
        final relative = p.relative(filePath, from: activeRoot);
        if (!relative.startsWith('..')) {
          return relative;
        }
      } catch (error, stack) {
        silentLog('file_explorer', '计算相对活动根目录的显示路径', error, stack);
      }
    }
    final inferredRoot = _inferWorkspaceRoot(widget.activeFilePath);
    try {
      final relative = p.relative(filePath, from: inferredRoot);
      if (!relative.startsWith('..')) {
        return relative;
      }
    } catch (error, stack) {
      silentLog('file_explorer', '计算相对推断根目录的显示路径', error, stack);
    }
    return filePath;
  }

  Future<void> _refreshInferredWorkspaceRoot(String filePath) async {
    await _inferWorkspaceRootAsync(filePath);
    if (!mounted || widget.activeFilePath != filePath) return;
    setState(() {});
  }

  String _displayPathForLspLocation(AiLspLocation location) {
    return _displayPathForFilePath(location.filePath);
  }

  Future<void> _showLspBackendStatusForActiveFile() async {
    final title = AppLocalizations.of(context)!.progExpFELspBackend;
    _showLspLoading(title);
    try {
      final resolution = await _ensureLspBackend(
        widget.activeFilePath,
        force: true,
      );
      if (!mounted) {
        return;
      }
      if (!resolution.isAvailable) {
        _showLspMessage(
          title: title,
          message: _lspUnavailableMessage(resolution),
        );
        return;
      }
      final command = trimmedNonEmptyStrings(<String>[
        resolution.executablePath ?? resolution.executable ?? '',
        ...resolution.arguments,
      ]).join(' ');
      final projectLanguage = normalizeAiLspLanguage(widget.projectLanguage);
      final hasProjectOverride = _hasProjectToolchainOverride();
      final lspSourceLine = widget.projectLspPath.trim().isNotEmpty
          ? openHandLocalizedText(
              context,
              zh: 'LSP 根路径来源：项目覆盖 (${OpenHandPaths.shortenHomePath(widget.projectLspPath)})',
              zhHant:
                  'LSP 根路徑來源：專案覆寫 (${OpenHandPaths.shortenHomePath(widget.projectLspPath)})',
              en: 'LSP root source: project override (${OpenHandPaths.shortenHomePath(widget.projectLspPath)})',
              fr: 'Source racine LSP : remplacement du projet (${OpenHandPaths.shortenHomePath(widget.projectLspPath)})',
              de: 'LSP-Stammquelle: Projektüberschreibung (${OpenHandPaths.shortenHomePath(widget.projectLspPath)})',
              ja: 'LSP ルートのソース: プロジェクト上書き (${OpenHandPaths.shortenHomePath(widget.projectLspPath)})',
            )
          : resolution.configuredInstallRoot?.trim().isNotEmpty == true
          ? openHandLocalizedText(
              context,
              zh: 'LSP 根路径来源：已保存配置 (${OpenHandPaths.shortenHomePath(resolution.configuredInstallRoot!)})',
              zhHant:
                  'LSP 根路徑來源：已儲存設定 (${OpenHandPaths.shortenHomePath(resolution.configuredInstallRoot!)})',
              en: 'LSP root source: saved mapping (${OpenHandPaths.shortenHomePath(resolution.configuredInstallRoot!)})',
              fr: 'Source racine LSP : correspondance enregistrée (${OpenHandPaths.shortenHomePath(resolution.configuredInstallRoot!)})',
              de: 'LSP-Stammquelle: gespeicherte Zuordnung (${OpenHandPaths.shortenHomePath(resolution.configuredInstallRoot!)})',
              ja: 'LSP ルートのソース: 保存済みマッピング (${OpenHandPaths.shortenHomePath(resolution.configuredInstallRoot!)})',
            )
          : openHandLocalizedText(
              context,
              zh: 'LSP 根路径来源：PATH 自动探测',
              zhHant: 'LSP 根路徑來源：PATH 自動偵測',
              en: 'LSP root source: PATH auto-detection',
              fr: 'Source racine LSP : détection automatique PATH',
              de: 'LSP-Stammquelle: automatische PATH-Erkennung',
              ja: 'LSP ルートのソース: PATH 自動検出',
            );
      final sdkSourceLine = widget.projectSdkPath.trim().isNotEmpty
          ? openHandLocalizedText(
              context,
              zh: 'SDK 来源：项目覆盖 (${OpenHandPaths.shortenHomePath(widget.projectSdkPath)})',
              zhHant:
                  'SDK 來源：專案覆寫 (${OpenHandPaths.shortenHomePath(widget.projectSdkPath)})',
              en: 'SDK source: project override (${OpenHandPaths.shortenHomePath(widget.projectSdkPath)})',
              fr: 'Source SDK : remplacement du projet (${OpenHandPaths.shortenHomePath(widget.projectSdkPath)})',
              de: 'SDK-Quelle: Projektüberschreibung (${OpenHandPaths.shortenHomePath(widget.projectSdkPath)})',
              ja: 'SDK ソース: プロジェクト上書き (${OpenHandPaths.shortenHomePath(widget.projectSdkPath)})',
            )
          : openHandLocalizedText(
              context,
              zh: 'SDK 来源：全局配置或系统默认',
              zhHant: 'SDK 來源：全域設定或系統預設',
              en: 'SDK source: global mapping or system default',
              fr: 'Source SDK : correspondance globale ou valeur système',
              de: 'SDK-Quelle: globale Zuordnung oder Systemstandard',
              ja: 'SDK ソース: グローバル設定またはシステム既定値',
            );
      final modeLine = projectLanguage == 'mixed'
          ? openHandLocalizedText(
              context,
              zh: '项目模式：混合语言，按文件后缀自动选择语言后端',
              zhHant: '專案模式：混合語言，依檔案副檔名自動選擇語言後端',
              en: 'Project mode: mixed language, resolve the backend per file type',
              fr: 'Mode projet : langage mixte, backend résolu par type de fichier',
              de: 'Projektmodus: gemischte Sprachen, Backend pro Dateityp auflösen',
              ja: 'プロジェクトモード: 混在言語、ファイル種別ごとにバックエンドを解決',
            )
          : hasProjectOverride
          ? openHandLocalizedText(
              context,
              zh: '项目模式：项目级工具链覆盖已启用',
              zhHant: '專案模式：已啟用專案級工具鏈覆寫',
              en: 'Project mode: project-level toolchain override enabled',
              fr: 'Mode projet : remplacement de chaîne d’outils activé au niveau projet',
              de: 'Projektmodus: projektweite Toolchain-Überschreibung aktiviert',
              ja: 'プロジェクトモード: プロジェクト単位のツールチェーン上書きが有効',
            )
          : openHandLocalizedText(
              context,
              zh: '项目模式：继续使用全局按语言配置',
              zhHant: '專案模式：繼續使用全域各語言設定',
              en: 'Project mode: using the global per-language mapping',
              fr: 'Mode projet : utilisation de la correspondance globale par langage',
              de: 'Projektmodus: globale Zuordnung pro Sprache verwenden',
              ja: 'プロジェクトモード: グローバルな言語別設定を使用',
            );
      final lspName = resolution.displayName ?? resolution.backendId ?? 'LSP';
      final projLang = _programmingLanguageLabel(
        context,
        widget.projectLanguage,
      );
      final fileLang = _programmingLanguageLabel(context, resolution.language);
      final rootPath = resolution.rootPath;
      _showLspMessage(
        title: title,
        message: AppLocalizations.of(context)!
            .progExpFEResolvedLspBackendForCurrentFile(
              lspName,
              projLang,
              fileLang,
              modeLine,
              sdkSourceLine,
              lspSourceLine,
              rootPath,
              command,
            ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showLspMessage(title: title, message: _friendlyLspError(error));
    }
  }

  Widget _buildProjectToolchainInfoRow({
    required ColorScheme colorScheme,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          kOpenHandHGap8,
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: valueColor ?? colorScheme.onSurface,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _languageMappingEntryLabel(BuildContext context, String language) {
    final normalizedLanguage = normalizeAiLspLanguage(language);
    return '${_programmingLanguageLabel(context, normalizedLanguage)} ($normalizedLanguage)';
  }

  Color _projectToolchainTreeToneColor(
    ColorScheme colorScheme,
    _ProjectToolchainTreeNodeTone tone,
  ) {
    return switch (tone) {
      _ProjectToolchainTreeNodeTone.active => colorScheme.primary,
      _ProjectToolchainTreeNodeTone.info => colorScheme.tertiary,
      _ProjectToolchainTreeNodeTone.muted => colorScheme.onSurfaceVariant,
      _ProjectToolchainTreeNodeTone.warning => colorScheme.error,
      _ProjectToolchainTreeNodeTone.success => _kFileExplorerSuccessColor,
    };
  }

  _ProjectToolchainTreeNode _projectToolchainLeafNode({
    required String title,
    required String description,
    required _ProjectToolchainTreeNodeTone tone,
    IconData icon = Icons.subdirectory_arrow_right_rounded,
    String? badge,
  }) {
    return _ProjectToolchainTreeNode(
      title: title,
      description: description,
      tone: tone,
      icon: icon,
      badge: badge,
    );
  }

  _ProjectToolchainTreeNode _projectToolchainSourceTree({
    required SettingsController settingsController,
    required String filePath,
    required AiLspBackendResolution? resolution,
  }) {
    final text = openHandTextResolver(context);

    final effectiveFileLanguage = normalizeAiLspLanguage(
      _resolvedLanguageForFile(filePath),
    );
    final projectLanguage = normalizeAiLspLanguage(widget.projectLanguage);
    final projectOverrideSettings =
        _projectLspOverrideSettings()[projectLanguage] ??
        const AiLspLanguageSettings();
    final projectOverrideTargetsCurrentFile =
        projectLanguage != 'mixed' &&
        projectLanguage != 'plaintext' &&
        effectiveFileLanguage == projectLanguage;
    final globalSettings = settingsController.editorLspSettingsForLanguage(
      effectiveFileLanguage,
    );
    final projectNode = switch (projectLanguage) {
      'mixed' => _ProjectToolchainTreeNode(
        title: text(
          zh: '项目层',
          zhHant: '專案層',
          en: 'Project layer',
          fr: 'Couche projet',
          de: 'Projektebene',
          ja: 'プロジェクト層',
        ),
        description: text(
          zh: '当前项目处于混合语言模式，不会把整个项目固定到单一语言；这个文件会继续使用 ${_languageMappingEntryLabel(context, effectiveFileLanguage)} 的全局映射。',
          zhHant:
              '目前專案處於混合語言模式，不會把整個專案固定到單一語言；這個檔案會繼續使用 ${_languageMappingEntryLabel(context, effectiveFileLanguage)} 的全域映射。',
          en: 'The project is in mixed-language mode, so it does not pin the whole workspace to a single language. This file continues with the global ${_languageMappingEntryLabel(context, effectiveFileLanguage)} mapping.',
          fr: 'Le projet est en mode langage mixte ; il ne fixe donc pas tout l’espace de travail sur un seul langage. Ce fichier continue avec la correspondance globale ${_languageMappingEntryLabel(context, effectiveFileLanguage)}.',
          de: 'Das Projekt ist im gemischten Sprachmodus und bindet den Arbeitsbereich nicht an eine einzelne Sprache. Diese Datei nutzt weiter die globale Zuordnung ${_languageMappingEntryLabel(context, effectiveFileLanguage)}.',
          ja: 'プロジェクトは混在言語モードのため、ワークスペース全体を単一言語に固定しません。このファイルは ${_languageMappingEntryLabel(context, effectiveFileLanguage)} のグローバルマッピングを使い続けます。',
        ),
        tone: _ProjectToolchainTreeNodeTone.info,
        icon: Icons.layers_rounded,
        badge: 'Mixed',
      ),
      _ when !projectOverrideTargetsCurrentFile => _ProjectToolchainTreeNode(
        title: text(
          zh: '项目层',
          zhHant: '專案層',
          en: 'Project layer',
          fr: 'Couche projet',
          de: 'Projektebene',
          ja: 'プロジェクト層',
        ),
        description: text(
          zh: '项目层当前只覆盖 ${_languageMappingEntryLabel(context, projectLanguage)}，而这个文件命中的是 ${_languageMappingEntryLabel(context, effectiveFileLanguage)}，所以项目级 SDK / LSP 覆盖不会参与。',
          zhHant:
              '專案層目前只覆寫 ${_languageMappingEntryLabel(context, projectLanguage)}，而這個檔案命中的是 ${_languageMappingEntryLabel(context, effectiveFileLanguage)}，因此專案級 SDK / LSP 覆寫不會參與。',
          en: 'The project layer currently targets ${_languageMappingEntryLabel(context, projectLanguage)}, while this file resolves to ${_languageMappingEntryLabel(context, effectiveFileLanguage)}, so project-level SDK / LSP overrides do not participate.',
          fr: 'La couche projet cible ${_languageMappingEntryLabel(context, projectLanguage)}, mais ce fichier correspond à ${_languageMappingEntryLabel(context, effectiveFileLanguage)} ; les remplacements SDK / LSP du projet ne participent donc pas.',
          de: 'Die Projektebene zielt auf ${_languageMappingEntryLabel(context, projectLanguage)}, diese Datei wird aber als ${_languageMappingEntryLabel(context, effectiveFileLanguage)} aufgelöst. Projektweite SDK-/LSP-Überschreibungen greifen daher nicht.',
          ja: 'プロジェクト層は現在 ${_languageMappingEntryLabel(context, projectLanguage)} のみを対象にしていますが、このファイルは ${_languageMappingEntryLabel(context, effectiveFileLanguage)} に一致するため、プロジェクト単位の SDK / LSP 上書きは使われません。',
        ),
        tone: _ProjectToolchainTreeNodeTone.muted,
        icon: Icons.layers_rounded,
        badge: text(
          zh: '未命中',
          zhHant: '未命中',
          en: 'No Match',
          fr: 'Aucune correspondance',
          de: 'Kein Treffer',
          ja: '不一致',
        ),
        children: <_ProjectToolchainTreeNode>[
          _projectToolchainLeafNode(
            title: text(
              zh: '项目语言',
              zhHant: '專案語言',
              en: 'Project language',
              fr: 'Langage du projet',
              de: 'Projektsprache',
              ja: 'プロジェクト言語',
            ),
            description: _languageMappingEntryLabel(context, projectLanguage),
            tone: _ProjectToolchainTreeNodeTone.muted,
            icon: Icons.flag_rounded,
          ),
        ],
      ),
      _ when projectOverrideSettings.isEmpty => _ProjectToolchainTreeNode(
        title: text(
          zh: '项目层',
          zhHant: '專案層',
          en: 'Project layer',
          fr: 'Couche projet',
          de: 'Projektebene',
          ja: 'プロジェクト層',
        ),
        description: text(
          zh: '项目层已命中 ${_languageMappingEntryLabel(context, projectLanguage)}，但当前项目没有额外保存 SDK / LSP 覆盖。',
          zhHant:
              '專案層已命中 ${_languageMappingEntryLabel(context, projectLanguage)}，但目前專案沒有額外儲存 SDK / LSP 覆寫。',
          en: 'The project layer matched ${_languageMappingEntryLabel(context, projectLanguage)}, but this project does not save an extra SDK / LSP override.',
          fr: 'La couche projet correspond à ${_languageMappingEntryLabel(context, projectLanguage)}, mais ce projet n’a pas de remplacement SDK / LSP supplémentaire.',
          de: 'Die Projektebene hat ${_languageMappingEntryLabel(context, projectLanguage)} getroffen, aber dieses Projekt speichert keine zusätzliche SDK-/LSP-Überschreibung.',
          ja: 'プロジェクト層は ${_languageMappingEntryLabel(context, projectLanguage)} に一致しましたが、このプロジェクトには追加の SDK / LSP 上書きが保存されていません。',
        ),
        tone: _ProjectToolchainTreeNodeTone.muted,
        icon: Icons.layers_rounded,
        badge: text(
          zh: '跟随全局',
          zhHant: '跟隨全域',
          en: 'Follow Global',
          fr: 'Suit le global',
          de: 'Folgt global',
          ja: 'グローバルに従う',
        ),
        children: <_ProjectToolchainTreeNode>[
          _projectToolchainLeafNode(
            title: 'SDK',
            description: text(
              zh: '未覆盖，继续跟随全局配置或系统默认。',
              zhHant: '未覆寫，繼續跟隨全域設定或系統預設。',
              en: 'Not overridden, so it continues with the global mapping or the system default.',
              fr: 'Aucun remplacement ; continue avec la correspondance globale ou la valeur système.',
              de: 'Nicht überschrieben; nutzt weiter die globale Zuordnung oder den Systemstandard.',
              ja: '上書きなし。グローバル設定またはシステム既定値に従います。',
            ),
            tone: _ProjectToolchainTreeNodeTone.muted,
            icon: Icons.developer_board_rounded,
          ),
          _projectToolchainLeafNode(
            title: 'LSP Root',
            description: text(
              zh: '未覆盖，继续跟随全局映射或 PATH 自动探测。',
              zhHant: '未覆寫，繼續跟隨全域映射或 PATH 自動偵測。',
              en: 'Not overridden, so it continues with the global mapping or PATH auto-detection.',
              fr: 'Aucun remplacement ; continue avec la correspondance globale ou la détection PATH.',
              de: 'Nicht überschrieben; nutzt weiter die globale Zuordnung oder automatische PATH-Erkennung.',
              ja: '上書きなし。グローバルマッピングまたは PATH 自動検出に従います。',
            ),
            tone: _ProjectToolchainTreeNodeTone.muted,
            icon: Icons.settings_ethernet_rounded,
          ),
        ],
      ),
      _ => _ProjectToolchainTreeNode(
        title: text(
          zh: '项目层',
          zhHant: '專案層',
          en: 'Project layer',
          fr: 'Couche projet',
          de: 'Projektebene',
          ja: 'プロジェクト層',
        ),
        description: text(
          zh: '项目层已命中 ${_languageMappingEntryLabel(context, projectLanguage)}，当前文件会优先检查项目级 SDK / LSP 覆盖。',
          zhHant:
              '專案層已命中 ${_languageMappingEntryLabel(context, projectLanguage)}，目前檔案會優先檢查專案級 SDK / LSP 覆寫。',
          en: 'The project layer matched ${_languageMappingEntryLabel(context, projectLanguage)}, so the current file checks the project-level SDK / LSP overrides first.',
          fr: 'La couche projet correspond à ${_languageMappingEntryLabel(context, projectLanguage)} ; ce fichier vérifie d’abord les remplacements SDK / LSP du projet.',
          de: 'Die Projektebene hat ${_languageMappingEntryLabel(context, projectLanguage)} getroffen; diese Datei prüft zuerst projektweite SDK-/LSP-Überschreibungen.',
          ja: 'プロジェクト層は ${_languageMappingEntryLabel(context, projectLanguage)} に一致したため、現在のファイルはプロジェクト単位の SDK / LSP 上書きを優先して確認します。',
        ),
        tone: _ProjectToolchainTreeNodeTone.active,
        icon: Icons.layers_rounded,
        badge: text(
          zh: '项目覆盖',
          zhHant: '專案覆寫',
          en: 'Project Override',
          fr: 'Remplacement projet',
          de: 'Projektüberschreibung',
          ja: 'プロジェクト上書き',
        ),
        children: <_ProjectToolchainTreeNode>[
          _projectToolchainLeafNode(
            title: 'SDK',
            description: projectOverrideSettings.sdkPath.trim().isNotEmpty
                ? OpenHandPaths.shortenHomePath(projectOverrideSettings.sdkPath)
                : text(
                    zh: '未覆盖，继续跟随全局配置或系统默认。',
                    zhHant: '未覆寫，繼續跟隨全域設定或系統預設。',
                    en: 'Not overridden, so it continues with the global mapping or the system default.',
                    fr: 'Aucun remplacement ; continue avec la correspondance globale ou la valeur système.',
                    de: 'Nicht überschrieben; nutzt weiter die globale Zuordnung oder den Systemstandard.',
                    ja: '上書きなし。グローバル設定またはシステム既定値に従います。',
                  ),
            tone: projectOverrideSettings.sdkPath.trim().isNotEmpty
                ? _ProjectToolchainTreeNodeTone.active
                : _ProjectToolchainTreeNodeTone.muted,
            icon: Icons.developer_board_rounded,
          ),
          _projectToolchainLeafNode(
            title: 'LSP Root',
            description: projectOverrideSettings.rootPath.trim().isNotEmpty
                ? OpenHandPaths.shortenHomePath(
                    projectOverrideSettings.rootPath,
                  )
                : text(
                    zh: '未覆盖，继续跟随全局映射或 PATH 自动探测。',
                    zhHant: '未覆寫，繼續跟隨全域映射或 PATH 自動偵測。',
                    en: 'Not overridden, so it continues with the global mapping or PATH auto-detection.',
                    fr: 'Aucun remplacement ; continue avec la correspondance globale ou la détection PATH.',
                    de: 'Nicht überschrieben; nutzt weiter die globale Zuordnung oder automatische PATH-Erkennung.',
                    ja: '上書きなし。グローバルマッピングまたは PATH 自動検出に従います。',
                  ),
            tone: projectOverrideSettings.rootPath.trim().isNotEmpty
                ? _ProjectToolchainTreeNodeTone.active
                : _ProjectToolchainTreeNodeTone.muted,
            icon: Icons.settings_ethernet_rounded,
          ),
        ],
      ),
    };

    final globalBackend = globalSettings.backendId.trim().isNotEmpty
        ? (aiLspBackendById(globalSettings.backendId.trim())?.displayName ??
              globalSettings.backendId.trim())
        : text(
            zh: '未固定，按该语言默认后端自动选择',
            zhHant: '未固定，依該語言預設後端自動選擇',
            en: 'Not pinned, using the default backend for this language',
            fr: 'Non fixé, utilise le backend par défaut pour ce langage',
            de: 'Nicht fixiert, nutzt das Standard-Backend für diese Sprache',
            ja: '固定なし。この言語の既定バックエンドを自動選択',
          );
    final globalNode = globalSettings.isEmpty
        ? _ProjectToolchainTreeNode(
            title: text(
              zh: '全局语言映射',
              zhHant: '全域語言映射',
              en: 'Global mapping',
              fr: 'Correspondance globale',
              de: 'Globale Zuordnung',
              ja: 'グローバル言語マッピング',
            ),
            description: text(
              zh: '没有保存 ${_languageMappingEntryLabel(context, effectiveFileLanguage)} 的全局映射，后续会继续回退到 PATH / 系统默认。',
              zhHant:
                  '沒有儲存 ${_languageMappingEntryLabel(context, effectiveFileLanguage)} 的全域映射，後續會繼續回退到 PATH / 系統預設。',
              en: 'There is no saved global mapping for ${_languageMappingEntryLabel(context, effectiveFileLanguage)}, so resolution continues to PATH / system defaults.',
              fr: 'Aucune correspondance globale enregistrée pour ${_languageMappingEntryLabel(context, effectiveFileLanguage)} ; la résolution continue vers PATH / valeurs système.',
              de: 'Es gibt keine gespeicherte globale Zuordnung für ${_languageMappingEntryLabel(context, effectiveFileLanguage)}; die Auflösung fällt auf PATH / Systemstandards zurück.',
              ja: '${_languageMappingEntryLabel(context, effectiveFileLanguage)} のグローバルマッピングは保存されていません。以降は PATH / システム既定値へフォールバックします。',
            ),
            tone: _ProjectToolchainTreeNodeTone.muted,
            icon: Icons.hub_rounded,
            badge: text(
              zh: '回退',
              zhHant: '回退',
              en: 'Fallback',
              fr: 'Repli',
              de: 'Fallback',
              ja: 'フォールバック',
            ),
          )
        : _ProjectToolchainTreeNode(
            title: text(
              zh: '全局语言映射',
              zhHant: '全域語言映射',
              en: 'Global mapping',
              fr: 'Correspondance globale',
              de: 'Globale Zuordnung',
              ja: 'グローバル言語マッピング',
            ),
            description: text(
              zh: '已命中 ${_languageMappingEntryLabel(context, effectiveFileLanguage)} 的全局映射。',
              zhHant:
                  '已命中 ${_languageMappingEntryLabel(context, effectiveFileLanguage)} 的全域映射。',
              en: 'Matched the global mapping for ${_languageMappingEntryLabel(context, effectiveFileLanguage)}.',
              fr: 'Correspondance globale trouvée pour ${_languageMappingEntryLabel(context, effectiveFileLanguage)}.',
              de: 'Globale Zuordnung für ${_languageMappingEntryLabel(context, effectiveFileLanguage)} gefunden.',
              ja: '${_languageMappingEntryLabel(context, effectiveFileLanguage)} のグローバルマッピングに一致しました。',
            ),
            tone: _ProjectToolchainTreeNodeTone.info,
            icon: Icons.hub_rounded,
            badge: text(
              zh: '已命中',
              zhHant: '已命中',
              en: 'Matched',
              fr: 'Correspondance',
              de: 'Treffer',
              ja: '一致',
            ),
            children: <_ProjectToolchainTreeNode>[
              _projectToolchainLeafNode(
                title: text(
                  zh: '后端',
                  zhHant: '後端',
                  en: 'Backend',
                  fr: 'Backend',
                  de: 'Backend',
                  ja: 'バックエンド',
                ),
                description: globalBackend,
                tone: _ProjectToolchainTreeNodeTone.info,
                icon: Icons.memory_rounded,
              ),
              _projectToolchainLeafNode(
                title: 'SDK',
                description: globalSettings.sdkPath.trim().isNotEmpty
                    ? OpenHandPaths.shortenHomePath(globalSettings.sdkPath)
                    : text(
                        zh: '未配置，继续跟随系统默认。',
                        zhHant: '未設定，繼續跟隨系統預設。',
                        en: 'Not configured, so it continues with the system default.',
                        fr: 'Non configuré ; continue avec la valeur système.',
                        de: 'Nicht konfiguriert; nutzt weiter den Systemstandard.',
                        ja: '未設定。システム既定値に従います。',
                      ),
                tone: globalSettings.sdkPath.trim().isNotEmpty
                    ? _ProjectToolchainTreeNodeTone.info
                    : _ProjectToolchainTreeNodeTone.muted,
                icon: Icons.developer_board_rounded,
              ),
              _projectToolchainLeafNode(
                title: 'LSP Root',
                description: globalSettings.rootPath.trim().isNotEmpty
                    ? OpenHandPaths.shortenHomePath(globalSettings.rootPath)
                    : text(
                        zh: '未配置，继续从 PATH 自动探测。',
                        zhHant: '未設定，繼續從 PATH 自動偵測。',
                        en: 'Not configured, so it continues with PATH auto-detection.',
                        fr: 'Non configuré ; continue avec la détection PATH.',
                        de: 'Nicht konfiguriert; nutzt weiter automatische PATH-Erkennung.',
                        ja: '未設定。PATH 自動検出に従います。',
                      ),
                tone: globalSettings.rootPath.trim().isNotEmpty
                    ? _ProjectToolchainTreeNodeTone.info
                    : _ProjectToolchainTreeNodeTone.muted,
                icon: Icons.settings_ethernet_rounded,
              ),
              if (globalSettings.version.trim().isNotEmpty)
                _projectToolchainLeafNode(
                  title: text(
                    zh: '版本',
                    zhHant: '版本',
                    en: 'Version',
                    fr: 'Version',
                    de: 'Version',
                    ja: 'バージョン',
                  ),
                  description: globalSettings.version.trim(),
                  tone: _ProjectToolchainTreeNodeTone.info,
                  icon: Icons.sell_rounded,
                ),
            ],
          );

    final finalNode = switch (resolution) {
      null => _ProjectToolchainTreeNode(
        title: text(
          zh: '最终解析',
          zhHant: '最終解析',
          en: 'Final resolution',
          fr: 'Résolution finale',
          de: 'Endgültige Auflösung',
          ja: '最終解決',
        ),
        description: text(
          zh: '正在等待当前文件的后端解析结果。',
          zhHant: '正在等待目前檔案的後端解析結果。',
          en: 'Waiting for the backend resolution of the current file.',
          fr: 'En attente de la résolution du backend du fichier actuel.',
          de: 'Warte auf die Backend-Auflösung der aktuellen Datei.',
          ja: '現在のファイルのバックエンド解決結果を待っています。',
        ),
        tone: _ProjectToolchainTreeNodeTone.info,
        icon: Icons.route_rounded,
        badge: text(
          zh: '等待中',
          zhHant: '等待中',
          en: 'Pending',
          fr: 'En attente',
          de: 'Ausstehend',
          ja: '待機中',
        ),
      ),
      final resolved when !resolved.isAvailable => _ProjectToolchainTreeNode(
        title: text(
          zh: '最终解析',
          zhHant: '最終解析',
          en: 'Final resolution',
          fr: 'Résolution finale',
          de: 'Endgültige Auflösung',
          ja: '最終解決',
        ),
        description: text(
          zh: '在 ${resolved.configuredInstallRoot?.trim().isNotEmpty == true ? OpenHandPaths.shortenHomePath(resolved.configuredInstallRoot!) : 'PATH'} 中未找到 ${resolved.displayName ?? resolved.backendId ?? resolved.executable ?? 'LSP'}。',
          zhHant:
              '在 ${resolved.configuredInstallRoot?.trim().isNotEmpty == true ? OpenHandPaths.shortenHomePath(resolved.configuredInstallRoot!) : 'PATH'} 中找不到 ${resolved.displayName ?? resolved.backendId ?? resolved.executable ?? 'LSP'}。',
          en: '${resolved.displayName ?? resolved.backendId ?? resolved.executable ?? 'LSP'} was not found in ${resolved.configuredInstallRoot?.trim().isNotEmpty == true ? OpenHandPaths.shortenHomePath(resolved.configuredInstallRoot!) : 'PATH'}.',
          fr: '${resolved.displayName ?? resolved.backendId ?? resolved.executable ?? 'LSP'} est introuvable dans ${resolved.configuredInstallRoot?.trim().isNotEmpty == true ? OpenHandPaths.shortenHomePath(resolved.configuredInstallRoot!) : 'PATH'}.',
          de: '${resolved.displayName ?? resolved.backendId ?? resolved.executable ?? 'LSP'} wurde in ${resolved.configuredInstallRoot?.trim().isNotEmpty == true ? OpenHandPaths.shortenHomePath(resolved.configuredInstallRoot!) : 'PATH'} nicht gefunden.',
          ja: '${resolved.configuredInstallRoot?.trim().isNotEmpty == true ? OpenHandPaths.shortenHomePath(resolved.configuredInstallRoot!) : 'PATH'} に ${resolved.displayName ?? resolved.backendId ?? resolved.executable ?? 'LSP'} が見つかりません。',
        ),
        tone: _ProjectToolchainTreeNodeTone.warning,
        icon: Icons.route_rounded,
        badge: text(
          zh: '未找到',
          zhHant: '找不到',
          en: 'Missing',
          fr: 'Manquant',
          de: 'Fehlt',
          ja: '未検出',
        ),
        children: <_ProjectToolchainTreeNode>[
          _projectToolchainLeafNode(
            title: text(
              zh: '工作区',
              zhHant: '工作區',
              en: 'Workspace',
              fr: 'Espace de travail',
              de: 'Arbeitsbereich',
              ja: 'ワークスペース',
            ),
            description: OpenHandPaths.shortenHomePath(resolved.rootPath),
            tone: _ProjectToolchainTreeNodeTone.muted,
            icon: Icons.folder_open_rounded,
          ),
          _projectToolchainLeafNode(
            title: text(
              zh: '命令名',
              zhHant: '命令名稱',
              en: 'Command',
              fr: 'Commande',
              de: 'Befehl',
              ja: 'コマンド名',
            ),
            description: resolved.executable ?? 'LSP',
            tone: _ProjectToolchainTreeNodeTone.warning,
            icon: Icons.terminal_rounded,
          ),
        ],
      ),
      final resolved => _ProjectToolchainTreeNode(
        title: text(
          zh: '最终解析',
          zhHant: '最終解析',
          en: 'Final resolution',
          fr: 'Résolution finale',
          de: 'Endgültige Auflösung',
          ja: '最終解決',
        ),
        description: resolved.configuredInstallRoot?.trim().isNotEmpty == true
            ? text(
                zh:
                    '已从 ${widget.projectLspPath.trim().isNotEmpty && projectOverrideTargetsCurrentFile
                        ? '项目级 LSP 根路径'
                        : globalSettings.rootPath.trim().isNotEmpty
                        ? '全局 ${_languageMappingEntryLabel(context, effectiveFileLanguage)} 映射'
                        : '已配置 LSP 根路径'} 解析到 ${resolved.displayName ?? resolved.backendId ?? 'LSP'}。',
                zhHant:
                    '已從 ${widget.projectLspPath.trim().isNotEmpty && projectOverrideTargetsCurrentFile
                        ? '專案級 LSP 根路徑'
                        : globalSettings.rootPath.trim().isNotEmpty
                        ? '全域 ${_languageMappingEntryLabel(context, effectiveFileLanguage)} 映射'
                        : '已設定 LSP 根路徑'} 解析到 ${resolved.displayName ?? resolved.backendId ?? 'LSP'}。',
                en:
                    'Resolved ${resolved.displayName ?? resolved.backendId ?? 'LSP'} from ${widget.projectLspPath.trim().isNotEmpty && projectOverrideTargetsCurrentFile
                        ? 'the project LSP root'
                        : globalSettings.rootPath.trim().isNotEmpty
                        ? 'the global ${_languageMappingEntryLabel(context, effectiveFileLanguage)} mapping'
                        : 'the configured LSP root'}.',
                fr:
                    '${resolved.displayName ?? resolved.backendId ?? 'LSP'} résolu depuis ${widget.projectLspPath.trim().isNotEmpty && projectOverrideTargetsCurrentFile
                        ? 'la racine LSP du projet'
                        : globalSettings.rootPath.trim().isNotEmpty
                        ? 'la correspondance globale ${_languageMappingEntryLabel(context, effectiveFileLanguage)}'
                        : 'la racine LSP configurée'}.',
                de:
                    '${resolved.displayName ?? resolved.backendId ?? 'LSP'} aus ${widget.projectLspPath.trim().isNotEmpty && projectOverrideTargetsCurrentFile
                        ? 'dem Projekt-LSP-Stamm'
                        : globalSettings.rootPath.trim().isNotEmpty
                        ? 'der globalen Zuordnung ${_languageMappingEntryLabel(context, effectiveFileLanguage)}'
                        : 'dem konfigurierten LSP-Stamm'} aufgelöst.',
                ja:
                    '${widget.projectLspPath.trim().isNotEmpty && projectOverrideTargetsCurrentFile
                        ? 'プロジェクト LSP ルート'
                        : globalSettings.rootPath.trim().isNotEmpty
                        ? 'グローバル ${_languageMappingEntryLabel(context, effectiveFileLanguage)} マッピング'
                        : '設定済み LSP ルート'} から ${resolved.displayName ?? resolved.backendId ?? 'LSP'} を解決しました。',
              )
            : text(
                zh: '已通过 PATH 解析到 ${resolved.displayName ?? resolved.backendId ?? 'LSP'}。',
                zhHant:
                    '已透過 PATH 解析到 ${resolved.displayName ?? resolved.backendId ?? 'LSP'}。',
                en: 'Resolved ${resolved.displayName ?? resolved.backendId ?? 'LSP'} from PATH.',
                fr: '${resolved.displayName ?? resolved.backendId ?? 'LSP'} résolu depuis PATH.',
                de: '${resolved.displayName ?? resolved.backendId ?? 'LSP'} über PATH aufgelöst.',
                ja: 'PATH から ${resolved.displayName ?? resolved.backendId ?? 'LSP'} を解決しました。',
              ),
        tone: _ProjectToolchainTreeNodeTone.success,
        icon: Icons.route_rounded,
        badge: resolved.configuredInstallRoot?.trim().isNotEmpty == true
            ? text(
                zh: '已绑定',
                zhHant: '已綁定',
                en: 'Bound',
                fr: 'Lié',
                de: 'Gebunden',
                ja: 'バインド済み',
              )
            : 'PATH',
        children: <_ProjectToolchainTreeNode>[
          _projectToolchainLeafNode(
            title: text(
              zh: '工作区',
              zhHant: '工作區',
              en: 'Workspace',
              fr: 'Espace de travail',
              de: 'Arbeitsbereich',
              ja: 'ワークスペース',
            ),
            description: OpenHandPaths.shortenHomePath(resolved.rootPath),
            tone: _ProjectToolchainTreeNodeTone.muted,
            icon: Icons.folder_open_rounded,
          ),
          _projectToolchainLeafNode(
            title: text(
              zh: '可执行文件',
              zhHant: '可執行檔',
              en: 'Executable',
              fr: 'Exécutable',
              de: 'Ausführbare Datei',
              ja: '実行ファイル',
            ),
            description: OpenHandPaths.shortenHomePath(
              resolved.executablePath?.trim().isNotEmpty == true
                  ? resolved.executablePath!
                  : (resolved.executable ?? ''),
            ),
            tone: _ProjectToolchainTreeNodeTone.success,
            icon: Icons.memory_rounded,
          ),
        ],
      ),
    };

    return _ProjectToolchainTreeNode(
      title: text(
        zh: '当前文件',
        zhHant: '目前檔案',
        en: 'Current file',
        fr: 'Fichier actuel',
        de: 'Aktuelle Datei',
        ja: '現在のファイル',
      ),
      description: text(
        zh: '${p.basename(filePath)} 当前识别为 ${_languageMappingEntryLabel(context, effectiveFileLanguage)}。',
        zhHant:
            '${p.basename(filePath)} 目前識別為 ${_languageMappingEntryLabel(context, effectiveFileLanguage)}。',
        en: '${p.basename(filePath)} currently resolves as ${_languageMappingEntryLabel(context, effectiveFileLanguage)}.',
        fr: '${p.basename(filePath)} est actuellement résolu comme ${_languageMappingEntryLabel(context, effectiveFileLanguage)}.',
        de: '${p.basename(filePath)} wird aktuell als ${_languageMappingEntryLabel(context, effectiveFileLanguage)} aufgelöst.',
        ja: '${p.basename(filePath)} は現在 ${_languageMappingEntryLabel(context, effectiveFileLanguage)} として解決されています。',
      ),
      tone: _ProjectToolchainTreeNodeTone.active,
      icon: Icons.insert_drive_file_rounded,
      badge: text(
        zh: '当前上下文',
        zhHant: '目前上下文',
        en: 'Current Context',
        fr: 'Contexte actuel',
        de: 'Aktueller Kontext',
        ja: '現在のコンテキスト',
      ),
      children: <_ProjectToolchainTreeNode>[projectNode, globalNode, finalNode],
    );
  }

  Widget _buildProjectToolchainSourceTreeNode({
    required ColorScheme colorScheme,
    required _ProjectToolchainTreeNode node,
  }) {
    final accentColor = _projectToolchainTreeToneColor(colorScheme, node.tone);
    final backgroundOpacity = switch (node.tone) {
      _ProjectToolchainTreeNodeTone.active => 0.10,
      _ProjectToolchainTreeNodeTone.info => 0.08,
      _ProjectToolchainTreeNodeTone.muted => 0.05,
      _ProjectToolchainTreeNodeTone.warning => 0.10,
      _ProjectToolchainTreeNodeTone.success => 0.08,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: backgroundOpacity),
            borderRadius: kOpenHandBorderRadius10,
            border: Border.all(
              color: accentColor.withValues(alpha: 0.18),
              width: 0.5,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(kOpenHandRadius7),
                ),
                alignment: Alignment.center,
                child: Icon(node.icon, size: 13, color: accentColor),
              ),
              kOpenHandHGap8,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            node.title,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                        if (node.badge?.trim().isNotEmpty == true)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.12),
                              borderRadius: kOpenHandPillBorderRadius,
                            ),
                            child: Text(
                              node.badge!,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: accentColor,
                              ),
                            ),
                          ),
                      ],
                    ),
                    kOpenHandGap4,
                    Text(
                      node.description,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.45,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (node.children.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(left: 18, top: 8),
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.22),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < node.children.length; index++) ...[
                  _buildProjectToolchainSourceTreeNode(
                    colorScheme: colorScheme,
                    node: node.children[index],
                  ),
                  if (index < node.children.length - 1)
                    kOpenHandGap8,
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildProjectToolchainBar(ColorScheme colorScheme) {
    if (!_projectToolchainBarVisible) {
      return const SizedBox.shrink();
    }
    final text = openHandTextResolver(context);

    final settingsController = context.watch<SettingsController>();
    final filePath = widget.activeFilePath;
    final resolution = _lspResolutionForFile(filePath);
    final projectLanguage = normalizeAiLspLanguage(widget.projectLanguage);
    final effectiveFileLanguage = _resolvedLanguageForFile(filePath);
    final hasProjectOverride = _hasProjectToolchainOverride();
    final isResolving =
        _lspBackendLoadingFiles.contains(filePath) && resolution == null;
    final sdkValue = widget.projectSdkPath.trim().isNotEmpty
        ? OpenHandPaths.shortenHomePath(widget.projectSdkPath)
        : text(
            zh: '跟随全局配置或系统默认',
            zhHant: '跟隨全域設定或系統預設',
            en: 'Following the global mapping or system default',
            fr: 'Suit la correspondance globale ou la valeur système',
            de: 'Folgt der globalen Zuordnung oder dem Systemstandard',
            ja: 'グローバル設定またはシステム既定値に従う',
          );
    final lspValue = widget.projectLspPath.trim().isNotEmpty
        ? OpenHandPaths.shortenHomePath(widget.projectLspPath)
        : text(
            zh: '跟随全局映射或 PATH 自动探测',
            zhHant: '跟隨全域映射或 PATH 自動偵測',
            en: 'Following the global mapping or PATH auto-detection',
            fr: 'Suit la correspondance globale ou la détection PATH',
            de: 'Folgt der globalen Zuordnung oder PATH-Erkennung',
            ja: 'グローバルマッピングまたは PATH 自動検出に従う',
          );
    final modeValue = projectLanguage == 'mixed'
        ? text(
            zh: '混合语言模式，按文件类型自动选择后端',
            zhHant: '混合語言模式，依檔案類型自動選擇後端',
            en: 'Mixed-language mode, resolve the backend per file type',
            fr: 'Mode langage mixte, backend résolu par type de fichier',
            de: 'Gemischter Sprachmodus, Backend pro Dateityp auflösen',
            ja: '混在言語モード、ファイル種別ごとに後端を解決',
          )
        : hasProjectOverride
        ? text(
            zh: '项目级 SDK / LSP 覆盖已启用',
            zhHant: '已啟用專案級 SDK / LSP 覆寫',
            en: 'Project-level SDK / LSP overrides are enabled',
            fr: 'Remplacements SDK / LSP activés au niveau projet',
            de: 'Projektweite SDK-/LSP-Überschreibungen sind aktiv',
            ja: 'プロジェクト単位の SDK / LSP 上書きが有効',
          )
        : text(
            zh: '未设置项目级覆盖，继续使用全局按语言配置',
            zhHant: '未設定專案級覆寫，繼續使用全域語言設定',
            en: 'No project override is set, so the global per-language mapping is used',
            fr: 'Aucun remplacement projet ; la correspondance globale par langage est utilisée',
            de: 'Keine Projektüberschreibung; die globale Zuordnung pro Sprache wird verwendet',
            ja: 'プロジェクト上書きなし。グローバルな言語別設定を使います',
          );
    final backendValue = resolution == null
        ? text(
            zh: '等待解析',
            zhHant: '等待解析',
            en: 'Waiting for resolution',
            fr: 'En attente de résolution',
            de: 'Warte auf Auflösung',
            ja: '解決待ち',
          )
        : resolution.isAvailable
        ? (resolution.displayName ?? resolution.backendId ?? 'LSP')
        : text(
            zh: '当前文件没有可用后端',
            zhHant: '目前檔案沒有可用後端',
            en: 'No backend is available for the current file',
            fr: 'Aucun backend disponible pour le fichier actuel',
            de: 'Für die aktuelle Datei ist kein Backend verfügbar',
            ja: '現在のファイルで利用できる後端はありません',
          );
    final sourceTree = _projectToolchainSourceTree(
      settingsController: settingsController,
      filePath: filePath,
      resolution: resolution,
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: _editorToolbarSurface(
          colorScheme,
          edge: _EditorToolbarEdge.top,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      text(
                        zh: '项目级 LSP 状态',
                        zhHant: '專案級 LSP 狀態',
                        en: 'Project LSP Status',
                        fr: 'État LSP du projet',
                        de: 'Projekt-LSP-Status',
                        ja: 'プロジェクト LSP 状態',
                      ),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  _FindBarButton(
                    icon: Icons.refresh_rounded,
                    tooltip: AppLocalizations.of(
                      context,
                    )!.progExpFEReResolveTheBackendForThe,
                    onPressed: () {
                      unawaited(
                        _ensureLspBackend(widget.activeFilePath, force: true),
                      );
                    },
                    colorScheme: colorScheme,
                  ),
                  _FindBarButton(
                    icon: Icons.hub_rounded,
                    tooltip: AppLocalizations.of(
                      context,
                    )!.progExpFEInspectBackendDetails,
                    onPressed: () {
                      unawaited(_showLspBackendStatusForActiveFile());
                    },
                    colorScheme: colorScheme,
                  ),
                  _FindBarButton(
                    icon: Icons.close_rounded,
                    tooltip: AppLocalizations.of(context)!.progExpFECloseEsc,
                    onPressed: () {
                      setState(() => _projectToolchainBarVisible = false);
                    },
                    colorScheme: colorScheme,
                  ),
                ],
              ),
              kOpenHandGap6,
              if (isResolving)
                Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.primary,
                      ),
                    ),
                    kOpenHandHGap8,
                    Text(
                      text(
                        zh: '项目切换或配置变更后，正在重新绑定当前文件的 LSP 后端…',
                        zhHant: '專案切換或設定變更後，正在重新綁定目前檔案的 LSP 後端…',
                        en: 'Rebinding the LSP backend for the current file after the project change or config update…',
                        fr: 'Reliaison du backend LSP du fichier actuel après le changement de projet ou de configuration…',
                        de: 'LSP-Backend der aktuellen Datei wird nach Projekt- oder Konfigurationsänderung neu gebunden…',
                        ja: 'プロジェクト切替または設定変更後、現在のファイルの LSP 後端を再バインドしています…',
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                )
              else ...[
                _buildProjectToolchainInfoRow(
                  colorScheme: colorScheme,
                  label: text(
                    zh: '项目语言',
                    zhHant: '專案語言',
                    en: 'Project language',
                    fr: 'Langage du projet',
                    de: 'Projektsprache',
                    ja: 'プロジェクト言語',
                  ),
                  value: _programmingLanguageLabel(
                    context,
                    widget.projectLanguage,
                  ),
                ),
                _buildProjectToolchainInfoRow(
                  colorScheme: colorScheme,
                  label: text(
                    zh: '当前文件语言',
                    zhHant: '目前檔案語言',
                    en: 'Current file',
                    fr: 'Fichier actuel',
                    de: 'Aktuelle Datei',
                    ja: '現在のファイル',
                  ),
                  value: _programmingLanguageLabel(
                    context,
                    effectiveFileLanguage,
                  ),
                ),
                _buildProjectToolchainInfoRow(
                  colorScheme: colorScheme,
                  label: text(
                    zh: '模式',
                    zhHant: '模式',
                    en: 'Mode',
                    fr: 'Mode',
                    de: 'Modus',
                    ja: 'モード',
                  ),
                  value: modeValue,
                  valueColor: hasProjectOverride
                      ? colorScheme.primary
                      : colorScheme.onSurface,
                ),
                _buildProjectToolchainInfoRow(
                  colorScheme: colorScheme,
                  label: 'SDK',
                  value: sdkValue,
                  valueColor: widget.projectSdkPath.trim().isNotEmpty
                      ? colorScheme.primary
                      : colorScheme.onSurface,
                ),
                _buildProjectToolchainInfoRow(
                  colorScheme: colorScheme,
                  label: 'LSP',
                  value: lspValue,
                  valueColor: widget.projectLspPath.trim().isNotEmpty
                      ? colorScheme.primary
                      : colorScheme.onSurface,
                ),
                _buildProjectToolchainInfoRow(
                  colorScheme: colorScheme,
                  label: text(
                    zh: '当前后端',
                    zhHant: '目前後端',
                    en: 'Effective backend',
                    fr: 'Backend actif',
                    de: 'Aktives Backend',
                    ja: '有効な後端',
                  ),
                  value: backendValue,
                  valueColor: resolution?.isAvailable == true
                      ? colorScheme.onSurface
                      : (resolution == null
                            ? colorScheme.onSurfaceVariant
                            : colorScheme.error),
                ),
                if (resolution?.isAvailable == true)
                  _buildProjectToolchainInfoRow(
                    colorScheme: colorScheme,
                    label: text(
                      zh: '工作区',
                      zhHant: '工作區',
                      en: 'Workspace',
                      fr: 'Espace de travail',
                      de: 'Arbeitsbereich',
                      ja: 'ワークスペース',
                    ),
                    value: OpenHandPaths.shortenHomePath(resolution!.rootPath),
                  ),
                kOpenHandGap8,
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLowest.withValues(
                      alpha: 0.92,
                    ),
                    borderRadius: kOpenHandBorderRadius10,
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text(
                          zh: '来源树',
                          zhHant: '來源樹',
                          en: 'Source Tree',
                          fr: 'Arbre des sources',
                          de: 'Quellbaum',
                          ja: 'ソースツリー',
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      kOpenHandGap6,
                      _buildProjectToolchainSourceTreeNode(
                        colorScheme: colorScheme,
                        node: sourceTree,
                      ),
                    ],
                  ),
                ),
                if (resolution != null && !resolution.isAvailable)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _buildDiagnosticsHint(
                      colorScheme,
                      _lspUnavailableMessage(resolution),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _goToLine(String input) {
    final lineNum = optionalPositiveIntFromValue(input);
    if (lineNum == null) return;
    final controller = _textControllers[widget.activeFilePath];
    if (controller == null) return;
    final targetLine = lineNum.clamp(1, controller.lineCount);
    _jumpToLineColumn(targetLine);
    setState(() => _goToLineVisible = false);
  }

  EditorShortcutAction? _matchEditorShortcutAction(
    Map<EditorShortcutAction, List<int>> bindings,
    Set<int> pressedKeyIds,
  ) {
    if (pressedKeyIds.isEmpty) {
      return null;
    }
    for (final action in EditorShortcutAction.values) {
      final shortcutKeyIds = normalizeShortcutKeyIds(
        bindings[action] ?? const <int>[],
      );
      if (shortcutKeyIds.isEmpty ||
          shortcutKeyIds.length != pressedKeyIds.length) {
        continue;
      }
      if (pressedKeyIds.containsAll(shortcutKeyIds)) {
        return action;
      }
    }
    return null;
  }

  Set<int> _pressedShortcutKeyIdsForEvent(KeyEvent event) {
    return normalizedPressedShortcutKeyIds(<LogicalKeyboardKey>{
      ...HardwareKeyboard.instance.logicalKeysPressed,
      event.logicalKey,
    });
  }

  KeyEventResult _handleEditorShortcutKeyEvent(
    String filePath,
    KeyEvent event,
  ) {
    if (_handleCompletionKeyEvent(event)) {
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_handleEditorAutoIndentKeyEvent(filePath, event)) {
      return KeyEventResult.handled;
    }
    if (_handleEditorCommentToggleKeyEvent(filePath, event)) {
      return KeyEventResult.handled;
    }
    if (_handleEditorIndentationKeyEvent(filePath, event)) {
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_completionVisible) {
        _dismissCompletionOverlay();
        return KeyEventResult.handled;
      }
      if (_signatureHelpVisible) {
        _hideSignatureHelpOverlay();
        return KeyEventResult.handled;
      }
      if (_findBarVisible) {
        _hideFindBar();
        return KeyEventResult.handled;
      }
      if (_symbolBarVisible) {
        _hideSymbolBar();
        return KeyEventResult.handled;
      }
      if (_goToLineVisible ||
          _diagnosticsBarVisible ||
          _projectToolchainBarVisible ||
          _lspResultBarVisible) {
        setState(() {
          _goToLineVisible = false;
          _diagnosticsBarVisible = false;
          _projectToolchainBarVisible = false;
          _lspResultBarVisible = false;
          _lspResultLoading = false;
          _lspResultTitle = '';
          _lspResultMessage = null;
          _lspResultLocations = const <AiLspLocation>[];
          _lspResultCodeActions = const <AiLspCodeAction>[];
          _lspResultPreviewLoading = false;
          _lspResultPreviews = const <String, _EditorLocationPreview>{};
          _lspHoverResult = null;
        });
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.f12) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        unawaited(_toggleFindReferencesAtCursor());
      } else {
        unawaited(_toggleDefinitionAtCursor());
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.f2) {
      _performEditorShortcutAction(EditorShortcutAction.renameSymbol, filePath);
      return KeyEventResult.handled;
    }

    final settingsController = context.read<SettingsController>();
    final action = _matchEditorShortcutAction(
      settingsController.editorShortcutBindings,
      _pressedShortcutKeyIdsForEvent(event),
    );
    if (action != null) {
      _performEditorShortcutAction(action, filePath);
      return KeyEventResult.handled;
    }

    final metaPressed =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (!metaPressed) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.minus) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _foldAll(filePath);
      } else {
        _foldAtCursor(filePath);
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.equal) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _unfoldAll(filePath);
      } else {
        _unfoldAtCursor(filePath);
      }
      return KeyEventResult.handled;
    }
    if (HardwareKeyboard.instance.isAltPressed) {
      if (event.logicalKey == LogicalKeyboardKey.keyM) {
        unawaited(
          _executeRefactorCodeAction(filePath, 'refactor.extract.function'),
        );
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyV) {
        unawaited(
          _executeRefactorCodeAction(filePath, 'refactor.extract.variable'),
        );
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyC) {
        unawaited(
          _executeRefactorCodeAction(filePath, 'refactor.extract.constant'),
        );
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyN) {
        unawaited(_executeRefactorCodeAction(filePath, 'refactor.inline'));
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  bool _handleEditorIndentationKeyEvent(String filePath, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.tab) {
      return false;
    }
    if (!(_focusNodes[filePath]?.hasFocus ?? false)) {
      return false;
    }
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isAltPressed) {
      return false;
    }

    final controller = _textControllers[filePath];
    if (controller == null) {
      return true;
    }
    final settingsController = context.read<SettingsController>();
    if (controller.selection.isCollapsed) {
      final matchedAction = _matchEditorShortcutAction(
        settingsController.editorShortcutBindings,
        _pressedShortcutKeyIdsForEvent(event),
      );
      if (matchedAction != null) {
        return false;
      }
    }
    final edit = applyEditorIndentation(
      text: controller.text,
      selection: controller.selection,
      indentSpaces: settingsController.editorIndentSpaces,
      outdent: HardwareKeyboard.instance.isShiftPressed,
    );
    if (!edit.didChange) {
      return true;
    }

    _commitProgrammaticEditorValueChange(
      filePath,
      controller,
      TextEditingValue(text: edit.text, selection: edit.selection),
      dismissCompletionOverlay: true,
    );
    return true;
  }

  bool _handleEditorAutoIndentKeyEvent(String filePath, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return false;
    }
    if (!(_focusNodes[filePath]?.hasFocus ?? false)) {
      return false;
    }
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isAltPressed) {
      return false;
    }

    final controller = _textControllers[filePath];
    if (controller == null) {
      return true;
    }
    final edit = applyEditorAutoIndentNewline(
      text: controller.text,
      selection: controller.selection,
      indentSpaces: context.read<SettingsController>().editorIndentSpaces,
      language: _resolvedLanguageForFile(filePath),
    );
    if (!edit.didChange) {
      return true;
    }

    _commitProgrammaticEditorValueChange(
      filePath,
      controller,
      TextEditingValue(text: edit.text, selection: edit.selection),
      dismissCompletionOverlay: true,
    );
    return true;
  }

  bool _handleEditorCommentToggleKeyEvent(String filePath, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.slash &&
        event.logicalKey != LogicalKeyboardKey.numpadDivide) {
      return false;
    }
    if (!(_focusNodes[filePath]?.hasFocus ?? false)) {
      return false;
    }
    final primaryModifier =
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    if (!primaryModifier || HardwareKeyboard.instance.isAltPressed) {
      return false;
    }

    final controller = _textControllers[filePath];
    if (controller == null) {
      return true;
    }
    final commentStyle = editorCommentStyleForLanguage(
      _resolvedLanguageForFile(filePath),
    );
    final title = AppLocalizations.of(context)!.progExpFEToggleComment;
    if (commentStyle == null) {
      _showLspMessage(
        title: title,
        message: AppLocalizations.of(
          context,
        )!.progExpFEThisLanguageDoesNotHaveA,
      );
      return true;
    }

    final edit = applyEditorToggleComment(
      text: controller.text,
      selection: controller.selection,
      commentStyle: commentStyle,
    );
    if (!edit.didChange) {
      return true;
    }

    _commitProgrammaticEditorValueChange(
      filePath,
      controller,
      TextEditingValue(text: edit.text, selection: edit.selection),
      dismissCompletionOverlay: true,
    );
    return true;
  }

  void _performEditorShortcutAction(
    EditorShortcutAction action,
    String filePath,
  ) {
    switch (action) {
      case EditorShortcutAction.saveFile:
        _saveFile(filePath);
      case EditorShortcutAction.triggerCompletion:
        _requestCompletion(explicit: true);
      case EditorShortcutAction.showSignatureHelp:
        unawaited(_toggleSignatureHelp());
      case EditorShortcutAction.find:
        _showFind();
      case EditorShortcutAction.replace:
        _showFindAndReplace();
      case EditorShortcutAction.goToLine:
        _showGoToLine();
      case EditorShortcutAction.showDocumentSymbols:
        _showSymbolBar();
      case EditorShortcutAction.showWorkspaceSymbols:
        _showWorkspaceSymbolBar();
      case EditorShortcutAction.goToDefinition:
        unawaited(_toggleDefinitionAtCursor());
      case EditorShortcutAction.findReferences:
        unawaited(_toggleFindReferencesAtCursor());
      case EditorShortcutAction.goToImplementation:
        unawaited(_toggleImplementationAtCursor());
      case EditorShortcutAction.showHoverInfo:
        unawaited(_toggleHoverAtCursor());
      case EditorShortcutAction.renameSymbol:
        unawaited(_renameSymbolAtCursor());
      case EditorShortcutAction.showCodeActions:
        unawaited(_toggleCodeActionsAtCursor());
      case EditorShortcutAction.formatDocument:
        unawaited(_formatDocument(filePath));
    }
  }

  bool _isLocationResultPanelOpen(String title) {
    return _lspResultBarVisible &&
        !_lspResultLoading &&
        _lspResultTitle == title &&
        _lspResultLocations.isNotEmpty;
  }

  Future<void> _toggleDefinitionAtCursor() async {
    final title = AppLocalizations.of(context)!.progExpFEGoToDefinition;
    if (_isLocationResultPanelOpen(title)) {
      _hideLspResultBar();
      return;
    }
    await _goToDefinitionAtCursor();
  }

  Future<void> _toggleFindReferencesAtCursor() async {
    final title = AppLocalizations.of(context)!.progExpFEFindReferences;
    if (_isLocationResultPanelOpen(title)) {
      _hideLspResultBar();
      return;
    }
    await _findReferencesAtCursor();
  }

  Future<void> _toggleImplementationAtCursor() async {
    final title = AppLocalizations.of(context)!.progExpFEGoToImplementation;
    if (_isLocationResultPanelOpen(title)) {
      _hideLspResultBar();
      return;
    }
    await _goToImplementationAtCursor();
  }

  Future<void> _toggleHoverAtCursor() async {
    if (_lspResultBarVisible && !_lspResultLoading && _lspHoverResult != null) {
      _hideLspResultBar();
      return;
    }
    await _showHoverAtCursor();
  }

  Future<void> _toggleCodeActionsAtCursor() async {
    final title = AppLocalizations.of(context)!.progExpFECodeActions;
    if (_lspResultBarVisible &&
        !_lspResultLoading &&
        _lspResultTitle == title &&
        _lspResultCodeActions.isNotEmpty) {
      _hideLspResultBar();
      return;
    }
    await _showCodeActionsAtCursor();
  }

  void _hideSignatureHelpOverlay() {
    _signatureHelpDebounceTimer?.cancel();
    _signatureHelpRequestEpoch += 1;
    if (!mounted) {
      _signatureHelpVisible = false;
      _signatureHelp = null;
      return;
    }
    if (!_signatureHelpVisible && _signatureHelp == null) {
      return;
    }
    setState(() {
      _signatureHelpVisible = false;
      _signatureHelp = null;
    });
  }

  Future<void> _toggleSignatureHelp({bool explicit = true}) async {
    if (_signatureHelpVisible) {
      _hideSignatureHelpOverlay();
      return;
    }
    _triggerSignatureHelp(explicit: explicit);
  }

  void _triggerSignatureHelp({
    bool explicit = false,
    String? triggerCharacter,
  }) {
    _signatureHelpDebounceTimer?.cancel();
    final controller = _textControllers[widget.activeFilePath];
    if (controller == null) {
      return;
    }
    final offset = controller.selection.baseOffset;
    if (offset < 0 || offset > controller.text.length) {
      return;
    }
    if (!explicit && !_signatureHelpVisible && triggerCharacter == null) {
      return;
    }
    final delay = explicit
        ? Duration.zero
        : (controller.useReducedInteractionMode
              ? kOpenHandMotion220
              : kOpenHandMotion120);
    if (delay == Duration.zero) {
      unawaited(
        _requestSignatureHelp(
          explicit: explicit,
          triggerCharacter: triggerCharacter,
          isRetrigger: _signatureHelpVisible,
        ),
      );
      return;
    }
    _signatureHelpDebounceTimer = startSafeTimer(delay, () async {
      if (!mounted) {
        return;
      }
      await _requestSignatureHelp(
        explicit: explicit,
        triggerCharacter: triggerCharacter,
        isRetrigger: _signatureHelpVisible,
      );
    });
  }

  Future<void> _requestSignatureHelp({
    bool explicit = false,
    String? triggerCharacter,
    bool isRetrigger = false,
  }) async {
    final filePath = widget.activeFilePath;
    final controller = _textControllers[filePath];
    if (controller == null) {
      _hideSignatureHelpOverlay();
      return;
    }
    final offset = controller.selection.baseOffset;
    if (offset < 0 || offset > controller.text.length) {
      _hideSignatureHelpOverlay();
      return;
    }

    final revision = controller.textRevision;
    if (!explicit &&
        _lastSignatureHelpRequestFilePath == filePath &&
        _lastSignatureHelpRequestOffset == offset &&
        _lastSignatureHelpRequestRevision == revision) {
      return;
    }
    _lastSignatureHelpRequestFilePath = filePath;
    _lastSignatureHelpRequestOffset = offset;
    _lastSignatureHelpRequestRevision = revision;

    final title = AppLocalizations.of(context)!.progExpFESignatureHelp;
    final precondition = _cursorLspPreconditionMessage(filePath);
    if (precondition != null) {
      if (explicit && mounted) {
        _showLspMessage(title: title, message: precondition);
      }
      _hideSignatureHelpOverlay();
      return;
    }

    final resolution = await _ensureLspBackend(filePath);
    if (!resolution.isAvailable) {
      if (explicit && mounted) {
        _showLspMessage(
          title: title,
          message: _lspUnavailableMessage(resolution),
        );
      }
      _hideSignatureHelpOverlay();
      return;
    }

    final position = controller._lineColumnForOffset(offset);
    final epoch = ++_signatureHelpRequestEpoch;
    try {
      final help = await AiLspClientService.instance.signatureHelp(
        filePath: filePath,
        line: position.line,
        character: position.column,
        language: resolution.language,
        documentText: controller.text,
        triggerCharacter: triggerCharacter,
        isRetrigger: isRetrigger,
      );
      if (!mounted || epoch != _signatureHelpRequestEpoch) {
        return;
      }
      if (help == null || help.isEmpty || help.selectedSignature == null) {
        if (explicit) {
          _showLspMessage(
            title: title,
            message: AppLocalizations.of(
              context,
            )!.progExpFEThereIsNoSignatureHelpAvailable,
          );
        }
        _hideSignatureHelpOverlay();
        return;
      }
      setState(() {
        _signatureHelp = help;
        _signatureHelpVisible = true;
      });
    } catch (error) {
      if (!mounted || epoch != _signatureHelpRequestEpoch) {
        return;
      }
      if (explicit) {
        _showLspMessage(title: title, message: _friendlyLspError(error));
      }
      _hideSignatureHelpOverlay();
    }
  }

  // ── Cursor position tracking ──

  // ── Code Completion (Autocomplete) ──

  String _identifierPrefixAtOffset(String text, int offset) {
    var prefixStart = offset;
    while (prefixStart > 0) {
      final ch = text.codeUnitAt(prefixStart - 1);
      if (_isIdentifierChar(ch)) {
        prefixStart--;
      } else {
        break;
      }
    }
    return text.substring(prefixStart, offset);
  }

  String? _completionTriggerCharacterAtOffset(String text, int offset) {
    if (offset <= 0 || offset > text.length) {
      return null;
    }
    final previousChar = text.codeUnitAt(offset - 1);
    if (!_isCompletionTriggerCharacter(previousChar)) {
      return null;
    }
    return String.fromCharCode(previousChar);
  }

  String? _signatureTriggerCharacterAtOffset(String text, int offset) {
    if (offset <= 0 || offset > text.length) {
      return null;
    }
    final previousChar = text.codeUnitAt(offset - 1);
    if (!_isSignatureTriggerCharacter(previousChar)) {
      return null;
    }
    return String.fromCharCode(previousChar);
  }

  bool _shouldAutoTriggerCompletion(
    _HighlightingTextController controller, {
    required String prefix,
    required String? triggerCharacter,
  }) {
    if (triggerCharacter != null) {
      return true;
    }
    if (_completionVisible) {
      return prefix.isNotEmpty;
    }
    if (controller.preferExplicitCompletion) {
      return prefix.length >= 2;
    }
    if (controller.useReducedInteractionMode) {
      return prefix.isNotEmpty;
    }
    return true;
  }

  void _triggerCompletion() {
    _completionDebounceTimer?.cancel();

    final controller = _textControllers[widget.activeFilePath];
    if (controller == null) {
      return;
    }

    final offset = controller.selection.baseOffset;
    final text = controller.text;
    if (offset < 0 || offset > text.length || text.isEmpty) {
      _dismissCompletionOverlay();
      return;
    }

    final triggerCharacter = _completionTriggerCharacterAtOffset(text, offset);
    if (triggerCharacter != null) {
      _requestCompletion(
        explicit: true,
        triggerCharacter: triggerCharacter,
        isRetrigger: _completionVisible,
      );
      return;
    }

    final prefix = _identifierPrefixAtOffset(text, offset);
    if (!_shouldAutoTriggerCompletion(
      controller,
      prefix: prefix,
      triggerCharacter: triggerCharacter,
    )) {
      _dismissCompletionOverlay();
      return;
    }

    final debounce = controller.useReducedInteractionMode
        ? kOpenHandMotion260
        : const Duration(milliseconds: 150);
    _completionDebounceTimer = startSafeTimer(debounce, () {
      if (!mounted) return;
      _requestCompletion(isRetrigger: _completionVisible);
    });
  }

  void _dismissCompletionOverlay() {
    if (_completionVisible) {
      setState(() => _completionVisible = false);
    }
  }

  Future<void> _requestCompletion({
    bool explicit = false,
    String? triggerCharacter,
    bool isRetrigger = false,
  }) async {
    final filePath = widget.activeFilePath;
    final controller = _textControllers[filePath];
    if (controller == null) {
      return;
    }
    final offset = controller.selection.baseOffset;
    // Guard against invalid or unset selection (-1) and offset beyond text.
    if (offset < 0) {
      return;
    }

    // Compute current line and column
    final text = controller.text;
    // Skip completion request if text is empty or offset exceeds length
    // (can happen briefly during rapid edits).
    if (text.isEmpty || offset > text.length) {
      return;
    }

    final position = controller._lineColumnForOffset(offset);
    final line = position.line;
    final col = position.column;

    final normalizedTriggerCharacter = triggerCharacter?.trim().isEmpty == true
        ? null
        : triggerCharacter;
    final prefix = _identifierPrefixAtOffset(text, offset);
    _completionPrefix = prefix;

    if (!explicit &&
        !_shouldAutoTriggerCompletion(
          controller,
          prefix: prefix,
          triggerCharacter: normalizedTriggerCharacter,
        )) {
      _dismissCompletionOverlay();
      return;
    }

    final revision = controller.textRevision;
    if (!explicit &&
        _lastCompletionRequestFilePath == filePath &&
        _lastCompletionRequestOffset == offset &&
        _lastCompletionRequestRevision == revision) {
      return;
    }
    _lastCompletionRequestFilePath = filePath;
    _lastCompletionRequestOffset = offset;
    _lastCompletionRequestRevision = revision;

    final epoch = ++_completionRequestEpoch;

    try {
      final items = await AiLspClientService.instance.completion(
        filePath: filePath,
        line: line,
        character: col,
        documentText: text,
        triggerCharacter: normalizedTriggerCharacter,
        isRetrigger: isRetrigger,
      );
      if (!mounted || epoch != _completionRequestEpoch) {
        return;
      }
      _completionItems = items;
      _filterCompletionItems();
      if (_filteredCompletionItems.isNotEmpty) {
        _showCompletionOverlay();
      } else {
        _dismissCompletionOverlay();
      }
    } catch (_) {
      // Completion request failed (e.g. LSP backend unavailable or timeout).
      // Silently dismiss overlay; the status bar already shows backend status.
      if (mounted && epoch == _completionRequestEpoch) {
        _dismissCompletionOverlay();
      }
    }
  }

  void _filterCompletionItems() {
    if (_completionPrefix.isEmpty) {
      _filteredCompletionItems = _completionItems.length > 40
          ? _completionItems.sublist(0, 40)
          : _completionItems;
    } else {
      final lowerPrefix = _completionPrefix.toLowerCase();
      _filteredCompletionItems = _completionItems
          .where(
            (item) =>
                item.effectiveFilterText.toLowerCase().contains(lowerPrefix),
          )
          .take(40)
          .toList(growable: false);
    }
    _completionSelectedIndex = 0;
  }

  void _showCompletionOverlay() {
    _dismissCompletionOverlay();
    setState(() => _completionVisible = true);
  }

  void _applyCompletionItem(AiLspCompletionItem item) {
    final filePath = widget.activeFilePath;
    final controller = _textControllers[filePath];
    if (controller == null) return;
    final offset = controller.selection.baseOffset;
    if (offset < 0) return;

    final text = controller.text;
    var prefixStart = offset;
    while (prefixStart > 0 &&
        _isIdentifierChar(text.codeUnitAt(prefixStart - 1))) {
      prefixStart--;
    }

    final before = text.substring(0, prefixStart);
    final after = text.substring(offset);
    final insertText = item.effectiveInsertText;
    final newText = '$before$insertText$after';
    final newOffset = prefixStart + insertText.length;

    _commitProgrammaticEditorValueChange(
      filePath,
      controller,
      TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newOffset),
      ),
      dismissCompletionOverlay: true,
    );
  }

  void _commitProgrammaticEditorValueChange(
    String filePath,
    _HighlightingTextController controller,
    TextEditingValue value, {
    bool dismissCompletionOverlay = false,
  }) {
    controller.value = value;
    if (dismissCompletionOverlay) {
      _dismissCompletionOverlay();
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _fileDirty[filePath] = true;
      _diagnosticsStaleFiles.add(filePath);
    });
    _scheduleDiagnosticsRefresh(filePath);
    _updateCursorPosition(controller);
    if (_findBarVisible && _findController.text.isNotEmpty) {
      _updateFindMatches(_findController.text);
    }
    if (_symbolBarVisible) {
      _scheduleSymbolRefresh();
    }
    if (_signatureHelpVisible) {
      _triggerSignatureHelp();
    }
  }

  bool _handleCompletionKeyEvent(KeyEvent event) {
    if (!_completionVisible || _filteredCompletionItems.isEmpty) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _completionSelectedIndex =
            (_completionSelectedIndex + 1) % _filteredCompletionItems.length;
      });
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _completionSelectedIndex =
            (_completionSelectedIndex - 1 + _filteredCompletionItems.length) %
            _filteredCompletionItems.length;
      });
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.tab) {
      _applyCompletionItem(_filteredCompletionItems[_completionSelectedIndex]);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _dismissCompletionOverlay();
      return true;
    }
    return false;
  }

  static bool _isIdentifierChar(int ch) {
    return (ch >= 65 && ch <= 90) || // A-Z
        (ch >= 97 && ch <= 122) || // a-z
        (ch >= 48 && ch <= 57) || // 0-9
        ch == 95 || // _
        ch == 36; // $
  }

  static bool _isCompletionTriggerCharacter(int ch) {
    return ch == 46 || ch == 58 || ch == 40 || ch == 60;
  }

  static bool _isSignatureTriggerCharacter(int ch) {
    return ch == 40 || ch == 44;
  }

  static IconData _completionItemKindIcon(int? kind) {
    return switch (kind) {
      2 => Icons.functions_rounded, // Method
      3 => Icons.functions_rounded, // Function
      4 => Icons.add_box_rounded, // Constructor
      5 => Icons.data_object_rounded, // Field
      6 => Icons.data_usage_rounded, // Variable
      7 => Icons.class_rounded, // Class
      8 => Icons.api_rounded, // Interface
      9 => Icons.inventory_2_rounded, // Module
      10 => Icons.tune_rounded, // Property
      13 => Icons.list_alt_rounded, // Enum
      14 => Icons.key_rounded, // Keyword
      15 => Icons.code_rounded, // Snippet
      20 => Icons.label_rounded, // EnumMember
      21 => Icons.lock_rounded, // Constant
      22 => Icons.account_tree_rounded, // Struct
      25 => Icons.text_fields_rounded, // TypeParameter
      _ => Icons.circle_outlined, // Default
    };
  }

  static String _completionItemKindLabel(int? kind) {
    return switch (kind) {
      1 => 'text',
      2 => 'method',
      3 => 'function',
      4 => 'constructor',
      5 => 'field',
      6 => 'variable',
      7 => 'class',
      8 => 'interface',
      9 => 'module',
      10 => 'property',
      11 => 'unit',
      12 => 'value',
      13 => 'enum',
      14 => 'keyword',
      15 => 'snippet',
      20 => 'enumMember',
      21 => 'constant',
      22 => 'struct',
      25 => 'typeParam',
      _ => '',
    };
  }

  void _updateCursorPosition(_HighlightingTextController controller) {
    final offset = controller.selection.baseOffset;
    if (offset < 0) return;
    final position = controller._lineColumnForOffset(offset);
    final line = position.line;
    final col = position.column;
    if (_cursorLine != line || _cursorColumn != col) {
      setState(() {
        _cursorLine = line;
        _cursorColumn = col;
      });
    }
  }

  // ── Find / Replace bar UI ──

  Widget _buildFindBar(ColorScheme colorScheme) {
    if (!_findBarVisible) return const SizedBox.shrink();
    final matchLabel = _findMatchOffsets.isEmpty
        ? ''
        : '${_currentMatchIndex + 1}/${_findMatchOffsets.length}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: _editorToolbarSurface(colorScheme),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Search row ──
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 30,
                  child: TextField(
                    controller: _findController,
                    focusNode: _findFocusNode,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface,
                    ),
                    decoration: _editorToolbarInputDecoration(
                      colorScheme,
                      hintText: _editorText(
                        zh: '查找',
                        zhHant: '尋找',
                        en: 'Find',
                        fr: 'Rechercher',
                        de: 'Suchen',
                        ja: '検索',
                      ),
                    ),
                    onChanged: _updateFindMatches,
                    onSubmitted: (_) => _findNext(),
                  ),
                ),
              ),
              if (matchLabel.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    matchLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              _FindBarButton(
                icon: Icons.keyboard_arrow_up_rounded,
                tooltip: AppLocalizations.of(context)!.progExpFEPreviousMatch,
                onPressed: _findMatchOffsets.isEmpty ? null : _findPrevious,
                colorScheme: colorScheme,
              ),
              _FindBarButton(
                icon: Icons.keyboard_arrow_down_rounded,
                tooltip: AppLocalizations.of(context)!.progExpFENextMatch,
                onPressed: _findMatchOffsets.isEmpty ? null : _findNext,
                colorScheme: colorScheme,
              ),
              _FindBarButton(
                icon: Icons.font_download_rounded,
                tooltip: AppLocalizations.of(context)!.progExpFEMatchCase,
                isActive: _findCaseSensitive,
                onPressed: () {
                  setState(() => _findCaseSensitive = !_findCaseSensitive);
                  _updateFindMatches(_findController.text);
                },
                colorScheme: colorScheme,
              ),
              if (!_replaceBarVisible)
                _FindBarButton(
                  icon: Icons.find_replace_rounded,
                  tooltip: AppLocalizations.of(context)!.progExpFEShowReplace,
                  onPressed: () => setState(() => _replaceBarVisible = true),
                  colorScheme: colorScheme,
                ),
              _FindBarButton(
                icon: Icons.close_rounded,
                tooltip: AppLocalizations.of(context)!.progExpFECloseEsc,
                onPressed: _hideFindBar,
                colorScheme: colorScheme,
              ),
            ],
          ),
          // ── Replace row ──
          if (_replaceBarVisible) ...[
            kOpenHandGap4,
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 30,
                    child: TextField(
                      controller: _replaceController,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurface,
                      ),
                      decoration: _editorToolbarInputDecoration(
                        colorScheme,
                        hintText: _editorText(
                          zh: '替换',
                          zhHant: '取代',
                          en: 'Replace',
                          fr: 'Remplacer',
                          de: 'Ersetzen',
                          ja: '置換',
                        ),
                      ),
                      onSubmitted: (_) => _replaceCurrent(),
                    ),
                  ),
                ),
                kOpenHandHGap4,
                _FindBarButton(
                  icon: Icons.find_replace_rounded,
                  tooltip: AppLocalizations.of(
                    context,
                  )!.progExpFEReplaceCurrent,
                  onPressed: _findMatchOffsets.isEmpty ? null : _replaceCurrent,
                  colorScheme: colorScheme,
                ),
                _FindBarButton(
                  icon: Icons.done_all_rounded,
                  tooltip: AppLocalizations.of(context)!.progExpFEReplaceAll,
                  onPressed: _findMatchOffsets.isEmpty ? null : _replaceAll,
                  colorScheme: colorScheme,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Go-to-Line bar UI ──

  Widget _buildGoToLineBar(ColorScheme colorScheme) {
    if (!_goToLineVisible) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: _editorToolbarSurface(colorScheme),
      child: Row(
        children: [
          Text(
            _editorText(
              zh: '跳转到行:',
              zhHant: '跳至行:',
              en: 'Go to Line:',
              fr: 'Aller à la ligne :',
              de: 'Gehe zu Zeile:',
              ja: '行へ移動:',
            ),
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
          kOpenHandHGap8,
          SizedBox(
            width: 100,
            height: 30,
            child: TextField(
              controller: _goToLineController,
              focusNode: _goToLineFocusNode,
              keyboardType: TextInputType.number,
              style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
              decoration: _editorToolbarInputDecoration(colorScheme),
              onSubmitted: (val) => _goToLine(val),
            ),
          ),
          kOpenHandHGap4,
          _FindBarButton(
            icon: Icons.close_rounded,
            tooltip: AppLocalizations.of(context)!.progExpFECloseEsc,
            onPressed: () => setState(() => _goToLineVisible = false),
            colorScheme: colorScheme,
          ),
        ],
      ),
    );
  }

  Widget _buildSymbolBar(ColorScheme colorScheme) {
    if (!_symbolBarVisible) {
      return const SizedBox.shrink();
    }
    final symbolCountLabel = _allSymbols.isEmpty
        ? ''
        : '${_visibleSymbols.length}/${_allSymbols.length}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: _editorToolbarSurface(colorScheme),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 30,
                  child: TextField(
                    controller: _symbolController,
                    focusNode: _symbolFocusNode,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface,
                    ),
                    decoration: _editorToolbarInputDecoration(
                      colorScheme,
                      hintText: _workspaceSymbolMode
                          ? _editorText(
                              zh: '搜索工作区符号',
                              zhHant: '搜尋工作區符號',
                              en: 'Search Workspace Symbols',
                              fr: 'Rechercher des symboles du workspace',
                              de: 'Workspace-Symbole suchen',
                              ja: 'ワークスペースシンボルを検索',
                            )
                          : _editorText(
                              zh: '跳转到符号',
                              zhHant: '跳至符號',
                              en: 'Go to Symbol',
                              fr: 'Aller au symbole',
                              de: 'Gehe zu Symbol',
                              ja: 'シンボルへ移動',
                            ),
                    ),
                  ),
                ),
              ),
              kOpenHandHGap4,
              _FindBarButton(
                icon: Icons.article_outlined,
                tooltip: AppLocalizations.of(
                  context,
                )!.progExpFECurrentFileSymbols,
                onPressed: _workspaceSymbolMode
                    ? () => _setSymbolSearchMode(false)
                    : null,
                colorScheme: colorScheme,
                isActive: !_workspaceSymbolMode,
              ),
              _FindBarButton(
                icon: Icons.travel_explore_rounded,
                tooltip: AppLocalizations.of(
                  context,
                )!.progExpFEWorkspaceSymbols,
                onPressed: _workspaceSymbolMode
                    ? null
                    : () => _setSymbolSearchMode(true),
                colorScheme: colorScheme,
                isActive: _workspaceSymbolMode,
              ),
              if (_symbolsLoading)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (_symbolsUsingLsp
                                  ? colorScheme.primaryContainer
                                  : colorScheme.surfaceContainerLowest)
                              .withValues(alpha: 0.8),
                      borderRadius: kOpenHandPillBorderRadius,
                    ),
                    child: Text(
                      _workspaceSymbolMode
                          ? 'WS'
                          : _symbolsUsingLsp
                          ? 'LSP'
                          : _editorText(
                              zh: '本地',
                              zhHant: '本機',
                              en: 'Local',
                              fr: 'Local',
                              de: 'Lokal',
                              ja: 'ローカル',
                            ),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: _symbolsUsingLsp
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              if (symbolCountLabel.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    symbolCountLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              _FindBarButton(
                icon: Icons.close_rounded,
                tooltip: AppLocalizations.of(context)!.progExpFECloseEsc,
                onPressed: _hideSymbolBar,
                colorScheme: colorScheme,
              ),
            ],
          ),
          kOpenHandGap6,
          if (_symbolsLoading && _allSymbols.isEmpty)
            Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary,
                  ),
                ),
                kOpenHandHGap8,
                Text(
                  _editorText(
                    zh: '正在加载符号列表…',
                    zhHant: '正在載入符號清單…',
                    en: 'Loading symbols…',
                    fr: 'Chargement des symboles…',
                    de: 'Symbole werden geladen…',
                    ja: 'シンボル一覧を読み込み中…',
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            )
          else if (_visibleSymbols.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                _allSymbols.isEmpty
                    ? (_workspaceSymbolMode
                          ? _editorText(
                              zh: '输入关键词后可跨文件搜索工作区符号',
                              zhHant: '輸入關鍵字後可跨檔案搜尋工作區符號',
                              en: 'Type a query to search workspace symbols across files',
                              fr: 'Saisissez une requête pour rechercher les symboles du workspace',
                              de: 'Gib eine Suche ein, um Workspace-Symbole dateiübergreifend zu finden',
                              ja: 'キーワードを入力すると複数ファイルのシンボルを検索できます',
                            )
                          : _editorText(
                              zh: '当前文件未提取到可导航符号',
                              zhHant: '目前檔案未提取到可導覽符號',
                              en: 'No navigable symbols found in this file',
                              fr: 'Aucun symbole navigable trouvé dans ce fichier',
                              de: 'Keine navigierbaren Symbole in dieser Datei gefunden',
                              ja: 'このファイルに移動可能なシンボルはありません',
                            ))
                    : (_workspaceSymbolMode
                          ? _editorText(
                              zh: '没有匹配的工作区符号',
                              zhHant: '沒有相符的工作區符號',
                              en: 'No matching workspace symbols',
                              fr: 'Aucun symbole du workspace correspondant',
                              de: 'Keine passenden Workspace-Symbole',
                              ja: '一致するワークスペースシンボルはありません',
                            )
                          : _editorText(
                              zh: '没有匹配的符号',
                              zhHant: '沒有相符的符號',
                              en: 'No matching symbols',
                              fr: 'Aucun symbole correspondant',
                              de: 'Keine passenden Symbole',
                              ja: '一致するシンボルはありません',
                            )),
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 190),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _visibleSymbols.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.15),
                ),
                itemBuilder: (context, index) {
                  final symbol = _visibleSymbols[index];
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        unawaited(_navigateToEditorSymbol(symbol));
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            if (symbol.depth > 0)
                              SizedBox(
                                width: math.min(symbol.depth * 12.0, 36.0),
                              ),
                            Icon(
                              _symbolKindIcon(symbol.kind),
                              size: 16,
                              color: colorScheme.primary,
                            ),
                            kOpenHandHGap8,
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    symbol.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                  if (_workspaceSymbolMode ||
                                      symbol.filePath != widget.activeFilePath)
                                    Text(
                                      _displayPathForFilePath(symbol.filePath),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: colorScheme.primary,
                                        fontFamily:
                                            kOpenHandMonospaceFontFamily,
                                      ),
                                    ),
                                  Text(
                                    symbol.signature,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            kOpenHandHGap8,
                            Text(
                              '${symbol.line}:${symbol.column}',
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant,
                                fontFamily: kOpenHandMonospaceFontFamily,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          if (_symbolHintMessage != null)
            Padding(
              padding: EdgeInsets.only(
                top: _symbolsTruncated ? 0 : 6,
                bottom: _symbolsTruncated ? 6 : 0,
              ),
              child: _buildDiagnosticsHint(colorScheme, _symbolHintMessage!),
            ),
          if (_symbolsTruncated)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _editorText(
                  zh: '符号列表已做性能截断，仅展示前部结果。',
                  zhHant: '符號清單已為效能截斷，僅顯示前段結果。',
                  en: 'The symbol list was truncated for performance.',
                  fr: 'La liste des symboles a été tronquée pour préserver les performances.',
                  de: 'Die Symbolliste wurde aus Leistungsgründen gekürzt.',
                  ja: 'パフォーマンスのため、シンボル一覧は先頭の結果のみ表示しています。',
                ),
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticsBar(ColorScheme colorScheme) {
    if (!_diagnosticsBarVisible) {
      return const SizedBox.shrink();
    }
    final filePath = widget.activeFilePath;
    final resolution = _lspResolutionForFile(filePath);
    final supportsDiagnostics = _supportsDiagnosticsForFile(filePath);
    final diagnostics =
        _diagnosticsByFile[filePath] ?? const <_EditorDiagnostic>[];
    final isLoading = _diagnosticsLoadingFiles.contains(filePath);
    final isResolvingBackend =
        _lspBackendLoadingFiles.contains(filePath) && resolution == null;
    final isStale =
        _fileDirty[filePath] == true ||
        _diagnosticsStaleFiles.contains(filePath);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: _editorToolbarSurface(
        colorScheme,
        edge: _EditorToolbarEdge.top,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _editorText(
                    zh: '代码诊断',
                    zhHant: '程式碼診斷',
                    en: 'Diagnostics',
                    fr: 'Diagnostics',
                    de: 'Diagnosen',
                    ja: '診断',
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              if (supportsDiagnostics)
                _FindBarButton(
                  icon: Icons.refresh_rounded,
                  tooltip: AppLocalizations.of(
                    context,
                  )!.progExpFERefreshDiagnostics,
                  onPressed: isLoading
                      ? null
                      : () => _refreshDiagnostics(filePath),
                  colorScheme: colorScheme,
                ),
              _FindBarButton(
                icon: Icons.close_rounded,
                tooltip: AppLocalizations.of(context)!.progExpFECloseEsc,
                onPressed: () => setState(() => _diagnosticsBarVisible = false),
                colorScheme: colorScheme,
              ),
            ],
          ),
          kOpenHandGap6,
          Flexible(
            child: _buildDiagnosticsContent(
              colorScheme: colorScheme,
              filePath: filePath,
              supportsDiagnostics: supportsDiagnostics,
              diagnostics: diagnostics,
              isLoading: isLoading,
              isResolvingBackend: isResolvingBackend,
              isStale: isStale,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticsContent({
    required ColorScheme colorScheme,
    required String filePath,
    required bool supportsDiagnostics,
    required List<_EditorDiagnostic> diagnostics,
    required bool isLoading,
    required bool isResolvingBackend,
    required bool isStale,
  }) {
    if (isResolvingBackend) {
      return Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorScheme.primary,
            ),
          ),
          kOpenHandHGap8,
          Text(
            _editorText(
              zh: '正在连接 LSP 后端…',
              zhHant: '正在連線 LSP 後端…',
              en: 'Resolving LSP backend…',
              fr: 'Résolution du backend LSP…',
              de: 'LSP-Backend wird aufgelöst…',
              ja: 'LSP 後端を解決中…',
            ),
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
        ],
      );
    }
    if (!supportsDiagnostics) {
      return _buildDiagnosticsHint(
        colorScheme,
        _diagnosticsUnavailableMessage(filePath),
      );
    }
    if (isLoading) {
      return Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorScheme.primary,
            ),
          ),
          kOpenHandHGap8,
          Text(
            _editorText(
              zh: '正在等待 LSP 诊断结果…',
              zhHant: '正在等待 LSP 診斷結果…',
              en: 'Waiting for LSP diagnostics…',
              fr: 'En attente des diagnostics LSP…',
              de: 'Warte auf LSP-Diagnosen…',
              ja: 'LSP 診断結果を待機中…',
            ),
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isStale)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _buildDiagnosticsHint(
              colorScheme,
              _editorText(
                zh: '编辑内容已经变化，诊断会按当前文本继续刷新。',
                zhHant: '編輯內容已變更，診斷會依目前文字繼續刷新。',
                en: 'The editor text changed; diagnostics will keep refreshing against the current content.',
                fr: 'Le texte de l’éditeur a changé ; les diagnostics continueront sur le contenu actuel.',
                de: 'Der Editorinhalt hat sich geändert; Diagnosen werden für den aktuellen Text aktualisiert.',
                ja: 'エディタの内容が変わったため、現在のテキストで診断を更新します。',
              ),
            ),
          ),
        if (diagnostics.isEmpty)
          Text(
            _editorText(
              zh: '未发现诊断问题。',
              zhHant: '未發現診斷問題。',
              en: 'No diagnostics found.',
              fr: 'Aucun diagnostic trouvé.',
              de: 'Keine Diagnosen gefunden.',
              ja: '診断問題は見つかりませんでした。',
            ),
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          )
        else
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: diagnostics.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.15),
              ),
              itemBuilder: (context, index) {
                final diagnostic = diagnostics[index];
                final severityColor = _diagnosticSeverityColor(
                  colorScheme,
                  diagnostic,
                );
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      _jumpToLineColumn(
                        diagnostic.line,
                        column: diagnostic.column,
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 8,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            diagnostic.isError
                                ? Icons.error_outline_rounded
                                : diagnostic.isWarning
                                ? Icons.warning_amber_rounded
                                : Icons.info_outline_rounded,
                            size: 16,
                            color: severityColor,
                          ),
                          kOpenHandHGap8,
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  diagnostic.message,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                kOpenHandGap2,
                                Text(
                                  '${diagnostic.code}  •  ${diagnostic.line}:${diagnostic.column}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.onSurfaceVariant,
                                    fontFamily: kOpenHandMonospaceFontFamily,
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
              },
            ),
          ),
      ],
    );
  }

  Widget _buildLspResultBar(ColorScheme colorScheme) {
    if (!_lspResultBarVisible) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final hasLocations = _lspResultLocations.isNotEmpty;
    final hasCodeActions = _lspResultCodeActions.isNotEmpty;
    final hover = _lspHoverResult;
    final message = _lspResultMessage;
    final hasScrollableContent =
        hover != null || hasLocations || hasCodeActions;
    final resultCount = hasLocations
        ? _lspResultLocations.length
        : hasCodeActions
        ? _lspResultCodeActions.length
        : 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: _editorToolbarSurface(
        colorScheme,
        edge: _EditorToolbarEdge.top,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        _lspResultTitle,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    if (resultCount > 0) ...[
                      kOpenHandHGap8,
                      Text(
                        '($resultCount)',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _FindBarButton(
                icon: Icons.close_rounded,
                tooltip: AppLocalizations.of(context)!.progExpFECloseEsc,
                onPressed: _hideLspResultBar,
                colorScheme: colorScheme,
              ),
            ],
          ),
          kOpenHandGap6,
          if (_lspResultPreviewLoading && hasLocations)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildDiagnosticsHint(
                colorScheme,
                _editorText(
                  zh: '正在加载结果附近的代码上下文…',
                  zhHant: '正在載入結果附近的程式碼上下文…',
                  en: 'Loading code context around the current results...',
                  fr: 'Chargement du contexte de code autour des résultats actuels...',
                  de: 'Codekontext um die aktuellen Ergebnisse wird geladen...',
                  ja: '現在の結果周辺のコードコンテキストを読み込み中...',
                ),
              ),
            ),
          if (_lspResultLoading)
            Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary,
                  ),
                ),
                kOpenHandHGap8,
                Text(
                  _editorText(
                    zh: '正在执行 LSP 请求…',
                    zhHant: '正在執行 LSP 請求…',
                    en: 'Running LSP request…',
                    fr: 'Exécution de la requête LSP…',
                    de: 'LSP-Anfrage wird ausgeführt…',
                    ja: 'LSP リクエストを実行中…',
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            )
          else ...[
            if (message != null) ...[
              _buildDiagnosticsHint(colorScheme, message),
              if (hasScrollableContent) kOpenHandGap8,
            ],
            if (hasScrollableContent)
              Flexible(
                child: _buildLspScrollableContent(
                  colorScheme: colorScheme,
                  theme: theme,
                  hover: hover,
                ),
              )
            else if (message == null)
              Text(
                _editorText(
                  zh: '当前请求没有返回可显示内容。',
                  zhHant: '目前請求沒有返回可顯示內容。',
                  en: 'This request returned no displayable content.',
                  fr: 'Cette requête n’a renvoyé aucun contenu affichable.',
                  de: 'Diese Anfrage lieferte keinen anzeigbaren Inhalt.',
                  ja: 'このリクエストは表示できる内容を返しませんでした。',
                ),
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildLspScrollableContent({
    required ColorScheme colorScheme,
    required ThemeData theme,
    required AiLspHoverResult? hover,
  }) {
    if (hover != null) {
      return SingleChildScrollView(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest.withValues(alpha: 0.9),
            borderRadius: kOpenHandBorderRadius10,
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.2),
              width: 0.5,
            ),
          ),
          child: hover.markdown?.trim().isNotEmpty == true
              ? _SafeMarkdownBody(
                  data: hover.markdown!,
                  selectable: true,
                  parseKey: hover.markdown!,
                  styleSheet: _buildLspHoverMarkdownStyleSheet(
                    theme,
                    colorScheme,
                  ),
                )
              : SelectableText(
                  hover.renderedText,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: colorScheme.onSurface,
                    fontFamily: kOpenHandMonospaceFontFamily,
                  ),
                ),
        ),
      );
    }

    if (_lspResultCodeActions.isNotEmpty) {
      return ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: _lspResultCodeActions.length,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.15),
        ),
        itemBuilder: (context, index) {
          final action = _lspResultCodeActions[index];
          final isDisabled = action.isDisabled;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isDisabled
                  ? null
                  : () {
                      unawaited(_applyCodeAction(action));
                    },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _codeActionIcon(action),
                      size: 16,
                      color: isDisabled
                          ? colorScheme.onSurfaceVariant.withValues(alpha: 0.45)
                          : colorScheme.primary,
                    ),
                    kOpenHandHGap8,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  action.title,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: isDisabled
                                        ? colorScheme.onSurfaceVariant
                                        : colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              if (action.isPreferred)
                                Icon(
                                  Icons.star_rounded,
                                  size: 14,
                                  color: colorScheme.primary,
                                ),
                            ],
                          ),
                          kOpenHandGap2,
                          Text(
                            _codeActionSummary(action),
                            style: TextStyle(
                              fontSize: 11,
                              color: isDisabled
                                  ? colorScheme.onSurfaceVariant.withValues(
                                      alpha: 0.7,
                                    )
                                  : colorScheme.onSurfaceVariant,
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
        },
      );
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _lspResultLocations.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        color: colorScheme.outlineVariant.withValues(alpha: 0.15),
      ),
      itemBuilder: (context, index) {
        final location = _lspResultLocations[index];
        final displayPath = _displayPathForLspLocation(location);
        final preview = _lspResultPreviews[_locationPreviewKey(location)];
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              unawaited(_navigateToLspLocation(location));
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.place_outlined,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  kOpenHandHGap8,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.basename(location.filePath),
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        kOpenHandGap2,
                        Text(
                          '$displayPath  •  ${location.line}:${location.character}',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                            fontFamily: kOpenHandMonospaceFontFamily,
                          ),
                        ),
                        if (preview != null) ...[
                          kOpenHandGap6,
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerLowest
                                  .withValues(alpha: 0.9),
                              borderRadius: kOpenHandBorderRadius8,
                              border: Border.all(
                                color: colorScheme.outlineVariant.withValues(
                                  alpha: 0.18,
                                ),
                                width: 0.5,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final line in preview.lines)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 1,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(
                                          width: 34,
                                          child: Text(
                                            '${line.lineNumber}',
                                            textAlign: TextAlign.right,
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              color: line.isHighlight
                                                  ? colorScheme.primary
                                                  : colorScheme
                                                        .onSurfaceVariant,
                                              fontFamily:
                                                  kOpenHandMonospaceFontFamily,
                                            ),
                                          ),
                                        ),
                                        kOpenHandHGap8,
                                        Expanded(
                                          child: Text(
                                            line.text.isEmpty ? ' ' : line.text,
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: line.isHighlight
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                              color: line.isHighlight
                                                  ? colorScheme.onSurface
                                                  : colorScheme
                                                        .onSurfaceVariant,
                                              fontFamily:
                                                  kOpenHandMonospaceFontFamily,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDiagnosticsHint(ColorScheme colorScheme, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, size: 14, color: colorScheme.primary),
        kOpenHandHGap6,
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  MarkdownStyleSheet _buildLspHoverMarkdownStyleSheet(
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final surface = colorScheme.surfaceContainerLowest;
    final border = colorScheme.outlineVariant.withValues(alpha: 0.35);
    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
        color: colorScheme.onSurface,
        fontSize: 12.5,
        height: 1.55,
      ),
      code: TextStyle(
        fontFamily: kOpenHandMonospaceFontFamily,
        fontSize: 11.5,
        color: colorScheme.primary,
        backgroundColor: surface,
      ),
      codeblockPadding: const EdgeInsets.all(10),
      codeblockDecoration: BoxDecoration(
        color: surface,
        borderRadius: kOpenHandBorderRadius10,
        border: Border.all(color: border),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      blockquoteDecoration: BoxDecoration(
        color: Color.alphaBlend(
          colorScheme.primary.withValues(alpha: 0.08),
          surface,
        ),
        borderRadius: kOpenHandBorderRadius10,
        border: Border.all(color: border),
      ),
    );
  }

  IconData _symbolKindIcon(String kind) {
    return switch (kind) {
      'class' || 'interface' || 'type' => Icons.account_tree_rounded,
      'enum' => Icons.list_alt_rounded,
      'function' || 'method' => Icons.functions_rounded,
      'extension' || 'mixin' => Icons.extension_rounded,
      _ => Icons.label_outline_rounded,
    };
  }

  IconData _codeActionIcon(AiLspCodeAction action) {
    final kind = action.kind ?? '';
    if (kind.startsWith('quickfix')) {
      return Icons.auto_fix_high_rounded;
    }
    if (kind.startsWith('refactor')) {
      return Icons.drive_file_rename_outline_rounded;
    }
    if (kind.startsWith('source')) {
      return Icons.build_circle_outlined;
    }
    return Icons.lightbulb_outline_rounded;
  }

  String _codeActionSummary(AiLspCodeAction action) {
    if (action.isDisabled) {
      return action.disabledReason!;
    }
    final parts = <String>[];
    if (action.kind != null && action.kind!.trim().isNotEmpty) {
      parts.add(action.kind!);
    }
    final edit = action.edit;
    if (edit != null && !edit.isEmpty) {
      parts.add(
        _editorText(
          zh: '${edit.fileCount} 文件 / ${edit.editCount} 修改',
          zhHant: '${edit.fileCount} 檔案 / ${edit.editCount} 修改',
          en: '${edit.fileCount} files / ${edit.editCount} edits',
          fr: '${edit.fileCount} fichiers / ${edit.editCount} modifs',
          de: '${edit.fileCount} Dateien / ${edit.editCount} Änderungen',
          ja: '${edit.fileCount} ファイル / ${edit.editCount} 編集',
        ),
      );
    }
    if (action.command != null) {
      parts.add(
        _editorText(
          zh: '命令',
          zhHant: '命令',
          en: 'Command',
          fr: 'Commande',
          de: 'Befehl',
          ja: 'コマンド',
        ),
      );
    }
    if (action.isPreferred) {
      parts.add(
        _editorText(
          zh: '推荐',
          zhHant: '推薦',
          en: 'Preferred',
          fr: 'Préféré',
          de: 'Bevorzugt',
          ja: '推奨',
        ),
      );
    }
    return parts.isEmpty
        ? _editorText(
            zh: '可应用操作',
            zhHant: '可套用操作',
            en: 'Applicable action',
            fr: 'Action applicable',
            de: 'Anwendbare Aktion',
            ja: '適用可能な操作',
          )
        : parts.join('  •  ');
  }

  Color _diagnosticSeverityColor(
    ColorScheme colorScheme,
    _EditorDiagnostic diagnostic,
  ) {
    if (diagnostic.isError) {
      return colorScheme.error;
    }
    if (diagnostic.isWarning) {
      return _kFileExplorerWarningColor;
    }
    return colorScheme.primary;
  }

  Map<int, List<_EditorDiagnostic>> _diagnosticsByLineForFile(String filePath) {
    final grouped = <int, List<_EditorDiagnostic>>{};
    for (final diagnostic
        in _diagnosticsByFile[filePath] ?? const <_EditorDiagnostic>[]) {
      (grouped[diagnostic.line] ??= <_EditorDiagnostic>[]).add(diagnostic);
    }
    return grouped;
  }

  _EditorDiagnostic? _primaryDiagnosticForLine(
    List<_EditorDiagnostic> diagnostics,
  ) {
    if (diagnostics.isEmpty) {
      return null;
    }
    for (final diagnostic in diagnostics) {
      if (diagnostic.isError) {
        return diagnostic;
      }
    }
    for (final diagnostic in diagnostics) {
      if (diagnostic.isWarning) {
        return diagnostic;
      }
    }
    return diagnostics.first;
  }

  String _diagnosticsStatusLabel(BuildContext context, String filePath) {
    final resolution = _lspResolutionForFile(filePath);
    if (_lspBackendLoadingFiles.contains(filePath) && resolution == null) {
      return openHandLocalizedText(
        context,
        zh: 'LSP中',
        zhHant: 'LSP中',
        en: 'LSP',
        fr: 'LSP',
        de: 'LSP',
        ja: 'LSP中',
      );
    }
    if (resolution == null) {
      return openHandLocalizedText(
        context,
        zh: '待解析',
        zhHant: '待解析',
        en: 'Resolve',
        fr: 'Résoudre',
        de: 'Auflösen',
        ja: '解決待ち',
      );
    }
    if (!resolution.isAvailable) {
      return openHandLocalizedText(
        context,
        zh: '无后端',
        zhHant: '無後端',
        en: 'No LSP',
        fr: 'Sans LSP',
        de: 'Kein LSP',
        ja: 'LSPなし',
      );
    }
    if (_diagnosticsLoadingFiles.contains(filePath)) {
      return openHandLocalizedText(
        context,
        zh: '诊断中',
        zhHant: '診斷中',
        en: 'LSP Diag',
        fr: 'Diag LSP',
        de: 'LSP-Diag',
        ja: '診断中',
      );
    }
    final diagnostics =
        _diagnosticsByFile[filePath] ?? const <_EditorDiagnostic>[];
    final errors = diagnostics.where((item) => item.isError).length;
    final warnings = diagnostics.where((item) => item.isWarning).length;
    final stale =
        _fileDirty[filePath] == true ||
        _diagnosticsStaleFiles.contains(filePath);
    if (errors == 0 && warnings == 0) {
      return stale
          ? openHandLocalizedText(
              context,
              zh: '已过期',
              zhHant: '已過期',
              en: 'Stale',
              fr: 'Périmé',
              de: 'Veraltet',
              ja: '古い',
            )
          : openHandLocalizedText(
              context,
              zh: '通过',
              zhHant: '通過',
              en: 'Clean',
              fr: 'OK',
              de: 'OK',
              ja: '正常',
            );
    }
    final buffer = StringBuffer();
    if (errors > 0) {
      buffer.write(
        openHandLocalizedText(
          context,
          zh: '$errors错',
          zhHant: '$errors錯',
          en: '${errors}E',
          fr: '${errors}E',
          de: '${errors}F',
          ja: '$errorsエ',
        ),
      );
    }
    if (warnings > 0) {
      if (buffer.isNotEmpty) {
        buffer.write(' · ');
      }
      buffer.write(
        openHandLocalizedText(
          context,
          zh: '$warnings警',
          zhHant: '$warnings警',
          en: '${warnings}W',
          fr: '${warnings}A',
          de: '${warnings}W',
          ja: '$warnings警',
        ),
      );
    }
    return buffer.toString();
  }

  Color _diagnosticsStatusColor(ColorScheme colorScheme, String filePath) {
    final resolution = _lspResolutionForFile(filePath);
    if (_lspBackendLoadingFiles.contains(filePath) && resolution == null) {
      return colorScheme.primary;
    }
    if (resolution == null) {
      return colorScheme.onSurfaceVariant;
    }
    if (!resolution.isAvailable) {
      return resolution.availability ==
              AiLspBackendAvailability.executableNotFound
          ? colorScheme.error
          : colorScheme.onSurfaceVariant;
    }
    if (_diagnosticsLoadingFiles.contains(filePath)) {
      return colorScheme.primary;
    }
    final diagnostics =
        _diagnosticsByFile[filePath] ?? const <_EditorDiagnostic>[];
    if (diagnostics.any((item) => item.isError)) {
      return colorScheme.error;
    }
    if (diagnostics.any((item) => item.isWarning)) {
      return _kFileExplorerWarningColor;
    }
    if (_fileDirty[filePath] == true ||
        _diagnosticsStaleFiles.contains(filePath)) {
      return colorScheme.tertiary;
    }
    return colorScheme.onSurfaceVariant;
  }

  Widget _buildStatusChip({
    required ColorScheme colorScheme,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    String? tooltip,
    Color? foregroundColor,
    bool active = false,
  }) {
    final resolvedForeground = foregroundColor ?? colorScheme.onSurfaceVariant;
    final chip = Material(
      color: active
          ? colorScheme.primaryContainer.withValues(alpha: 0.6)
          : Colors.transparent,
      borderRadius: kOpenHandBorderRadius8,
      child: InkWell(
        borderRadius: kOpenHandBorderRadius8,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: resolvedForeground),
              kOpenHandHGap5,
              Text(
                label,
                style: TextStyle(fontSize: 11, color: resolvedForeground),
              ),
            ],
          ),
        ),
      ),
    );
    if (tooltip == null || tooltip.isEmpty) {
      return chip;
    }
    return Tooltip(message: tooltip, child: chip);
  }

  // ── Status bar UI ──

  Widget _buildStatusBar(ColorScheme colorScheme) {
    final settingsController = context.watch<SettingsController>();
    final language = _resolvedLanguageForFile(widget.activeFilePath);
    final zoomPct = (_fontSize / _editorFontSizeDefault * 100).round();
    final diagnosticsLabel = _diagnosticsStatusLabel(
      context,
      widget.activeFilePath,
    );
    final backendResolution = _lspResolutionForFile(widget.activeFilePath);
    final lspActionColor = _lspActionColor(colorScheme, widget.activeFilePath);
    final definitionTitle = AppLocalizations.of(
      context,
    )!.progExpFEGoToDefinition;
    final referencesTitle = AppLocalizations.of(
      context,
    )!.progExpFEFindReferences;
    final renameTitle = AppLocalizations.of(context)!.progExpFERenameSymbol;
    final codeActionsTitle = AppLocalizations.of(context)!.progExpFECodeActions;
    final formatTitle = AppLocalizations.of(context)!.progExpFEFormatDocument;
    final formatShortcut = formatShortcutLabel(
      settingsController.editorShortcutBindings[EditorShortcutAction
              .formatDocument] ??
          const <int>[],
    );
    final hoverTitle = AppLocalizations.of(context)!.progExpFEHoverInfo;
    final backendTitle = AppLocalizations.of(context)!.progExpFELspBackend;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: Row(
                children: [
                  Text(
                    'Ln $_cursorLine, Col $_cursorColumn',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                      fontFamily: kOpenHandMonospaceFontFamily,
                    ),
                  ),
                  kOpenHandHGap16,
                  Text(
                    _programmingLanguageLabel(context, language),
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (zoomPct != 100) ...[
                    kOpenHandHGap16,
                    Text(
                      '$zoomPct%',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  kOpenHandHGap8,
                  _buildStatusChip(
                    colorScheme: colorScheme,
                    icon: Icons.account_tree_rounded,
                    label: AppLocalizations.of(context)!.progExpFESymbols,
                    tooltip: AppLocalizations.of(
                      context,
                    )!.progExpFESymbolNavigationShiftCmdCtrlO,
                    onTap: _showSymbolBar,
                    active: _symbolBarVisible && !_workspaceSymbolMode,
                  ),
                  kOpenHandHGap4,
                  _buildStatusChip(
                    colorScheme: colorScheme,
                    icon: Icons.travel_explore_rounded,
                    label: AppLocalizations.of(context)!.progExpFEWorkspace,
                    tooltip: AppLocalizations.of(
                      context,
                    )!.progExpFEWorkspaceSymbolSearchCmdCtrlT,
                    onTap: _showWorkspaceSymbolBar,
                    active: _symbolBarVisible && _workspaceSymbolMode,
                  ),
                  kOpenHandHGap4,
                  _buildStatusChip(
                    colorScheme: colorScheme,
                    icon: _supportsDiagnosticsForFile(widget.activeFilePath)
                        ? Icons.health_and_safety_rounded
                        : _lspBackendLoadingFiles.contains(
                            widget.activeFilePath,
                          )
                        ? Icons.sync_rounded
                        : Icons.info_outline_rounded,
                    label: diagnosticsLabel,
                    tooltip: AppLocalizations.of(
                      context,
                    )!.progExpFEShowDiagnosticsForTheCurrentFile,
                    onTap: () {
                      setState(() {
                        if (_diagnosticsBarVisible) {
                          // Toggle off — dismiss the panel.
                          _diagnosticsBarVisible = false;
                          return;
                        }
                        _diagnosticsBarVisible = true;
                        _symbolBarVisible = false;
                        _projectToolchainBarVisible = false;
                        _lspResultBarVisible = false;
                        _findBarVisible = false;
                        _replaceBarVisible = false;
                        _goToLineVisible = false;
                      });
                      if (_diagnosticsBarVisible) {
                        unawaited(
                          _maybeRefreshDiagnostics(widget.activeFilePath),
                        );
                      }
                    },
                    active: _diagnosticsBarVisible,
                    foregroundColor: _diagnosticsStatusColor(
                      colorScheme,
                      widget.activeFilePath,
                    ),
                  ),
                  kOpenHandHGap4,
                  _buildStatusChip(
                    colorScheme: colorScheme,
                    icon: _hasProjectToolchainOverride()
                        ? Icons.tune_rounded
                        : normalizeAiLspLanguage(widget.projectLanguage) ==
                              'mixed'
                        ? Icons.hub_outlined
                        : Icons.layers_outlined,
                    label: _projectToolchainStatusLabel(
                      context,
                      widget.activeFilePath,
                    ),
                    tooltip: _projectToolchainStatusTooltip(
                      context,
                      widget.activeFilePath,
                    ),
                    onTap: () {
                      _toggleProjectToolchainBar();
                    },
                    active: _projectToolchainBarVisible,
                    foregroundColor: _projectToolchainStatusColor(
                      colorScheme,
                      widget.activeFilePath,
                    ),
                  ),
                  kOpenHandHGap4,
                  _buildStatusChip(
                    colorScheme: colorScheme,
                    icon: switch (backendResolution?.availability) {
                      AiLspBackendAvailability.available => Icons.hub_rounded,
                      AiLspBackendAvailability.executableNotFound =>
                        Icons.error_outline_rounded,
                      AiLspBackendAvailability.unsupportedLanguage =>
                        Icons.link_off_rounded,
                      null =>
                        _lspBackendLoadingFiles.contains(widget.activeFilePath)
                            ? Icons.sync_rounded
                            : Icons.hub_outlined,
                    },
                    label: _lspBackendStatusLabel(
                      context,
                      widget.activeFilePath,
                    ),
                    tooltip: AppLocalizations.of(
                      context,
                    )!.progExpFEInspectTheLspBackendBoundTo,
                    onTap: () {
                      unawaited(_showLspBackendStatusForActiveFile());
                    },
                    active:
                        _lspResultBarVisible && _lspResultTitle == backendTitle,
                    foregroundColor: _lspBackendStatusColor(
                      colorScheme,
                      widget.activeFilePath,
                    ),
                  ),
                  kOpenHandHGap4,
                  _buildStatusChip(
                    colorScheme: colorScheme,
                    icon: Icons.subdirectory_arrow_right_rounded,
                    label: AppLocalizations.of(context)!.progExpFEDef,
                    tooltip: AppLocalizations.of(
                      context,
                    )!.progExpFEGoToDefinitionF12CmdCtrl,
                    onTap: () {
                      unawaited(_goToDefinitionAtCursor());
                    },
                    active:
                        _lspResultBarVisible &&
                        _lspResultTitle == definitionTitle,
                    foregroundColor: lspActionColor,
                  ),
                  kOpenHandHGap4,
                  _buildStatusChip(
                    colorScheme: colorScheme,
                    icon: Icons.format_list_bulleted_rounded,
                    label: AppLocalizations.of(context)!.progExpFERefs,
                    tooltip: AppLocalizations.of(
                      context,
                    )!.progExpFEFindReferencesShiftF12CmdCtrl,
                    onTap: () {
                      unawaited(_findReferencesAtCursor());
                    },
                    active:
                        _lspResultBarVisible &&
                        _lspResultTitle == referencesTitle,
                    foregroundColor: lspActionColor,
                  ),
                  kOpenHandHGap4,
                  _buildStatusChip(
                    colorScheme: colorScheme,
                    icon: Icons.info_outline_rounded,
                    label: AppLocalizations.of(context)!.progExpFEHover,
                    tooltip: AppLocalizations.of(
                      context,
                    )!.progExpFEHoverInfoCmdCtrlI,
                    onTap: () {
                      unawaited(_showHoverAtCursor());
                    },
                    active:
                        _lspResultBarVisible && _lspResultTitle == hoverTitle,
                    foregroundColor: lspActionColor,
                  ),
                  kOpenHandHGap4,
                  _buildStatusChip(
                    colorScheme: colorScheme,
                    icon: Icons.drive_file_rename_outline_rounded,
                    label: AppLocalizations.of(context)!.progExpFERename,
                    tooltip: AppLocalizations.of(
                      context,
                    )!.progExpFERenameSymbolF2,
                    onTap: () {
                      unawaited(_renameSymbolAtCursor());
                    },
                    active:
                        _lspResultBarVisible && _lspResultTitle == renameTitle,
                    foregroundColor: lspActionColor,
                  ),
                  kOpenHandHGap4,
                  _buildStatusChip(
                    colorScheme: colorScheme,
                    icon: Icons.lightbulb_outline_rounded,
                    label: AppLocalizations.of(context)!.progExpFEActions,
                    tooltip: AppLocalizations.of(
                      context,
                    )!.progExpFECodeActionsCmdCtrl,
                    onTap: () {
                      unawaited(_showCodeActionsAtCursor());
                    },
                    active:
                        _lspResultBarVisible &&
                        _lspResultTitle == codeActionsTitle,
                    foregroundColor: lspActionColor,
                  ),
                  kOpenHandHGap4,
                  _buildStatusChip(
                    colorScheme: colorScheme,
                    icon: Icons.auto_fix_high_rounded,
                    label: AppLocalizations.of(context)!.progExpFEFormat,
                    tooltip: AppLocalizations.of(context)!
                        .progExpFEFormatTheCurrentFileFormatshortcut(
                          formatShortcut,
                        ),
                    onTap: () {
                      unawaited(_formatDocument(widget.activeFilePath));
                    },
                    active:
                        _lspResultBarVisible && _lspResultTitle == formatTitle,
                    foregroundColor: lspActionColor,
                  ),
                ],
              ),
            ),
          ),
          kOpenHandHGap12,
          Text(
            'UTF-8',
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Future<void> _loadFile(String filePath) async {
    if (!widget.openFiles.contains(filePath) ||
        _fileContents.containsKey(filePath) ||
        _fileLoading[filePath] == true) {
      return;
    }
    final generation = ++_nextFileLoadGeneration;
    _fileLoadGenerations[filePath] = generation;
    _fileLoading[filePath] = true;
    try {
      final file = File(filePath);
      if (!_isCurrentFileLoad(filePath, generation)) return;
      final content = await readBoundedFileString(
        file,
        maxBytes: _kProgrammingExplorerMaxEditableFileBytes,
      );
      if (!_isCurrentFileLoad(filePath, generation)) return;
      _fileContents[filePath] = content;
      final controller = _HighlightingTextController(
        initialText: content,
        language: _resolvedLanguageForFile(filePath),
      );
      _textControllers[filePath] = controller;
      _focusNodes[filePath] = FocusNode();
      _fileDirty[filePath] = false;
      if (filePath == widget.activeFilePath) {
        _updateCursorPosition(controller);
        if (_symbolBarVisible) {
          _scheduleSymbolRefresh(immediate: true);
        }
        _maybeApplyPendingNavigation();
        unawaited(_maybeRefreshDiagnostics(filePath));
      }
    } catch (_) {
      if (_isCurrentFileLoad(filePath, generation)) {
        _fileContents[filePath] = null;
      }
    } finally {
      if (_isCurrentFileLoad(filePath, generation)) {
        setState(() => _fileLoading[filePath] = false);
      }
    }
  }

  bool _isCurrentFileLoad(String filePath, int generation) {
    return mounted &&
        widget.openFiles.contains(filePath) &&
        _fileLoadGenerations[filePath] == generation;
  }

  Future<void> _saveFile(String filePath) async {
    final controller = _textControllers[filePath];
    if (controller == null || _fileDirty[filePath] != true) return;
    try {
      await writeFileAtomically(File(filePath), controller.text);
      if (mounted) {
        setState(() {
          _fileDirty[filePath] = false;
          _diagnosticsStaleFiles.add(filePath);
        });
      }
      await _refreshDiagnostics(filePath);
    } catch (error, stack) {
      silentLog('file_explorer', '保存文件 $filePath', error, stack);
      if (!mounted) return;
      showOpenHandErrorSnack(
        context,
        _editorText(
          zh: '保存失败：${p.basename(filePath)}\n$error',
          zhHant: '儲存失敗：${p.basename(filePath)}\n$error',
          en: 'Save failed: ${p.basename(filePath)}\n$error',
          fr: 'Échec de l’enregistrement : ${p.basename(filePath)}\n$error',
          de: 'Speichern fehlgeschlagen: ${p.basename(filePath)}\n$error',
          ja: '保存に失敗しました: ${p.basename(filePath)}\n$error',
        ),
        maxLines: 3,
      );
    }
  }

  Future<void> _confirmCloseTab(String filePath) async {
    if (_fileDirty[filePath] != true) {
      widget.onTabClosed(filePath);
      return;
    }
    final fileName = p.basename(filePath);
    final result = await showAnimatedDialog<_UnsavedCloseAction>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return buildOpenHandAlertDialog(
          title: Text(
            _editorText(
              zh: '文件未保存',
              zhHant: '檔案未儲存',
              en: 'Unsaved Changes',
              fr: 'Modifications non enregistrées',
              de: 'Ungespeicherte Änderungen',
              ja: '未保存の変更',
            ),
            style: theme.textTheme.titleMedium,
          ),
          content: Text(
            _editorText(
              zh: '"$fileName" 有未保存的更改，是否保存？',
              zhHant: '"$fileName" 有未儲存的變更，是否儲存？',
              en: '"$fileName" has unsaved changes. Do you want to save?',
              fr: '"$fileName" contient des modifications non enregistrées. Voulez-vous les enregistrer ?',
              de: '"$fileName" hat ungespeicherte Änderungen. Möchtest du speichern?',
              ja: '"$fileName" には未保存の変更があります。保存しますか？',
            ),
          ),
          actions: [
            OpenHandDialogActionButton.secondary(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_UnsavedCloseAction.cancel),
              label: openHandCancelLabel(dialogContext),
            ),
            OpenHandDialogActionButton.destructive(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_UnsavedCloseAction.discard),
              label: _editorText(
                zh: '不保存',
                zhHant: '不儲存',
                en: "Don't Save",
                fr: 'Ne pas enregistrer',
                de: 'Nicht speichern',
                ja: '保存しない',
              ),
            ),
            OpenHandDialogActionButton.primary(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_UnsavedCloseAction.save),
              label: _editorText(
                zh: '保存',
                zhHant: '儲存',
                en: 'Save',
                fr: 'Enregistrer',
                de: 'Speichern',
                ja: '保存',
              ),
            ),
          ],
        );
      },
    );
    if (result == null || result == _UnsavedCloseAction.cancel) return;
    if (result == _UnsavedCloseAction.save) {
      await _saveFile(filePath);
    }
    widget.onTabClosed(filePath);
  }

  RelativeRect _menuPositionForGlobalOffset(Offset globalPosition) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) {
      return RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      );
    }
    final localPosition = overlay.globalToLocal(globalPosition);
    return RelativeRect.fromLTRB(
      localPosition.dx,
      localPosition.dy,
      overlay.size.width - localPosition.dx,
      overlay.size.height - localPosition.dy,
    );
  }

  void _closeTabBatch(List<String> filesToClose, {String? fallbackActiveFile}) {
    if (filesToClose.isEmpty) {
      return;
    }
    final closingSet = filesToClose.toSet();
    final safeFallback =
        fallbackActiveFile != null &&
            !closingSet.contains(fallbackActiveFile) &&
            widget.openFiles.contains(fallbackActiveFile)
        ? fallbackActiveFile
        : null;
    if (closingSet.contains(widget.activeFilePath) && safeFallback != null) {
      widget.onTabSelected(safeFallback);
    }
    for (final filePath
        in widget.openFiles.where(closingSet.contains).toList()) {
      widget.onTabClosed(filePath);
    }
  }

  Future<void> _showEditorFileCopyPathMenu(
    String filePath,
    Offset globalPosition,
  ) async {
    if (!mounted) {
      return;
    }
    final workspaceRoot =
        _lspResolutionForFile(filePath)?.rootPath.isNotEmpty == true
        ? _lspResolutionForFile(filePath)!.rootPath
        : await _inferWorkspaceRootAsync(filePath);
    if (!mounted) return;
    String relativeFromWorkspace = filePath;
    try {
      final candidate = p.relative(filePath, from: workspaceRoot);
      if (!candidate.startsWith('..')) {
        relativeFromWorkspace = candidate;
      }
    } catch (error, stack) {
      silentLog('file_explorer', '计算复制菜单的工作区相对路径', error, stack);
    }

    final selected = await showAnimatedMenu<String>(
      context: context,
      position: _menuPositionForGlobalOffset(globalPosition),
      items: [
        PopupMenuItem<String>(
          value: 'abs',
          child: Text(
            _editorText(
              zh: '绝对路径',
              zhHant: '絕對路徑',
              en: 'Absolute Path',
              fr: 'Chemin absolu',
              de: 'Absoluter Pfad',
              ja: '絶対パス',
            ),
          ),
        ),
        PopupMenuItem<String>(
          value: 'name',
          child: Text(
            _editorText(
              zh: '文件名',
              zhHant: '檔案名稱',
              en: 'File Name',
              fr: 'Nom du fichier',
              de: 'Dateiname',
              ja: 'ファイル名',
            ),
          ),
        ),
        PopupMenuItem<String>(
          value: 'workspace_root',
          child: Text(
            _editorText(
              zh: '相对工作区路径',
              zhHant: '相對工作區路徑',
              en: 'Path from Workspace Root',
              fr: 'Chemin depuis la racine du workspace',
              de: 'Pfad ab Workspace-Wurzel',
              ja: 'ワークスペースルートからのパス',
            ),
          ),
        ),
      ],
    );
    if (selected == null || !mounted) {
      return;
    }
    final textToCopy = switch (selected) {
      'abs' => filePath,
      'name' => p.basename(filePath),
      'workspace_root' => relativeFromWorkspace,
      _ => filePath,
    };
    await copyOpenHandTextToClipboard(
      logTag: 'home',
      context: context,
      text: textToCopy,
      logAction: '复制编辑器标签页路径',
      successMessage: _editorText(
        zh: '路径已复制。',
        zhHant: '路徑已複製。',
        en: 'Path copied.',
        fr: 'Chemin copié.',
        de: 'Pfad kopiert.',
        ja: 'パスをコピーしました。',
      ),
    );
  }

  Future<void> _handleEditorTabMenuAction(
    _EditorTabMenuAction action, {
    required String filePath,
    required Offset globalPosition,
  }) async {
    switch (action) {
      case _EditorTabMenuAction.close:
        widget.onTabClosed(filePath);
        return;
      case _EditorTabMenuAction.closeOthers:
        _closeTabBatch(
          widget.openFiles.where((path) => path != filePath).toList(),
          fallbackActiveFile: filePath,
        );
        return;
      case _EditorTabMenuAction.closeAll:
        widget.onCloseAll();
        return;
      case _EditorTabMenuAction.closeUnmodified:
        final filesToClose = widget.openFiles
            .where((path) => _fileDirty[path] != true)
            .toList(growable: false);
        final remainingFiles = widget.openFiles
            .where((path) => !filesToClose.contains(path))
            .toList(growable: false);
        _closeTabBatch(
          filesToClose,
          fallbackActiveFile: remainingFiles.isEmpty
              ? null
              : remainingFiles.last,
        );
        return;
      case _EditorTabMenuAction.closeLeft:
        final fileIndex = widget.openFiles.indexOf(filePath);
        if (fileIndex <= 0) {
          return;
        }
        _closeTabBatch(
          widget.openFiles.take(fileIndex).toList(growable: false),
          fallbackActiveFile: filePath,
        );
        return;
      case _EditorTabMenuAction.closeRight:
        final fileIndex = widget.openFiles.indexOf(filePath);
        if (fileIndex < 0 || fileIndex >= widget.openFiles.length - 1) {
          return;
        }
        _closeTabBatch(
          widget.openFiles.skip(fileIndex + 1).toList(growable: false),
          fallbackActiveFile: filePath,
        );
        return;
      case _EditorTabMenuAction.copyPathReference:
        unawaited(_showEditorFileCopyPathMenu(filePath, globalPosition));
        return;
    }
  }

  Future<void> _showEditorTabMenu(
    String filePath,
    Offset globalPosition,
  ) async {
    if (!mounted) {
      return;
    }
    final fileIndex = widget.openFiles.indexOf(filePath);
    if (fileIndex < 0) {
      return;
    }
    final hasOtherTabs = widget.openFiles.length > 1;
    final hasTabsToLeft = fileIndex > 0;
    final hasTabsToRight = fileIndex < widget.openFiles.length - 1;
    final hasUnmodifiedTabs = widget.openFiles.any(
      (path) => _fileDirty[path] != true,
    );

    PopupMenuItem<_EditorTabMenuAction> buildItem({
      required _EditorTabMenuAction value,
      required IconData icon,
      required String label,
      bool enabled = true,
    }) {
      return PopupMenuItem<_EditorTabMenuAction>(
        value: value,
        enabled: enabled,
        child: Row(
          children: [
            Icon(icon, size: 18),
            kOpenHandHGap10,
            Expanded(child: Text(label)),
          ],
        ),
      );
    }

    final selected = await showAnimatedMenu<_EditorTabMenuAction>(
      context: context,
      position: _menuPositionForGlobalOffset(globalPosition),
      items: [
        buildItem(
          value: _EditorTabMenuAction.close,
          icon: Icons.close_rounded,
          label: openHandCloseLabel(context),
        ),
        buildItem(
          value: _EditorTabMenuAction.closeOthers,
          icon: Icons.filter_none_rounded,
          label: _editorText(
            zh: '关闭其他标签页',
            zhHant: '關閉其他分頁',
            en: 'Close Other Tabs',
            fr: 'Fermer les autres onglets',
            de: 'Andere Tabs schließen',
            ja: '他のタブを閉じる',
          ),
          enabled: hasOtherTabs,
        ),
        buildItem(
          value: _EditorTabMenuAction.closeAll,
          icon: Icons.deselect_rounded,
          label: _editorText(
            zh: '关闭所有标签页',
            zhHant: '關閉所有分頁',
            en: 'Close All Tabs',
            fr: 'Fermer tous les onglets',
            de: 'Alle Tabs schließen',
            ja: 'すべてのタブを閉じる',
          ),
          enabled: widget.openFiles.isNotEmpty,
        ),
        buildItem(
          value: _EditorTabMenuAction.closeUnmodified,
          icon: Icons.cleaning_services_rounded,
          label: _editorText(
            zh: '关闭未修改标签页',
            zhHant: '關閉未修改分頁',
            en: 'Close Unmodified Tabs',
            fr: 'Fermer les onglets non modifiés',
            de: 'Unveränderte Tabs schließen',
            ja: '未変更のタブを閉じる',
          ),
          enabled: hasUnmodifiedTabs,
        ),
        buildItem(
          value: _EditorTabMenuAction.closeLeft,
          icon: Icons.keyboard_double_arrow_left_rounded,
          label: _editorText(
            zh: '关闭左侧标签页',
            zhHant: '關閉左側分頁',
            en: 'Close Tabs to the Left',
            fr: 'Fermer les onglets à gauche',
            de: 'Tabs links schließen',
            ja: '左側のタブを閉じる',
          ),
          enabled: hasTabsToLeft,
        ),
        buildItem(
          value: _EditorTabMenuAction.closeRight,
          icon: Icons.keyboard_double_arrow_right_rounded,
          label: _editorText(
            zh: '关闭右侧标签页',
            zhHant: '關閉右側分頁',
            en: 'Close Tabs to the Right',
            fr: 'Fermer les onglets à droite',
            de: 'Tabs rechts schließen',
            ja: '右側のタブを閉じる',
          ),
          enabled: hasTabsToRight,
        ),
        const PopupMenuDivider(),
        buildItem(
          value: _EditorTabMenuAction.copyPathReference,
          icon: Icons.content_copy_rounded,
          label: _editorText(
            zh: '复制路径 / 引用…',
            zhHant: '複製路徑 / 引用…',
            en: 'Copy Path / Reference…',
            fr: 'Copier chemin / référence…',
            de: 'Pfad / Referenz kopieren…',
            ja: 'パス / 参照をコピー…',
          ),
        ),
      ],
    );
    if (selected == null || !mounted) {
      return;
    }
    await _handleEditorTabMenuAction(
      selected,
      filePath: filePath,
      globalPosition: globalPosition,
    );
  }

  // Editor code area context menu (right-click)
  /// Top-level context menu action identifiers.
  static const _ctxGoToDefinition = 'go_to_definition';
  static const _ctxFindReferences = 'find_references';
  static const _ctxGoToImplementation = 'go_to_implementation';
  static const _ctxHoverInfo = 'hover_info';
  static const _ctxRefactorSubmenu = 'refactor';
  static const _ctxNavigateSubmenu = 'navigate';
  static const _ctxFoldingSubmenu = 'folding';
  static const _ctxCut = 'cut';
  static const _ctxCopy = 'copy';
  static const _ctxPaste = 'paste';
  static const _ctxSelectAll = 'select_all';
  static const _ctxFind = 'find';
  static const _ctxReplace = 'replace';
  static const _ctxOpenInExplorer = 'open_in_explorer';
  static const _ctxCopyPath = 'copy_path';

  void _showEditorCodeContextMenu(String filePath, Offset globalPosition) {
    unawaited(_showEditorCodeContextMenuAsync(filePath, globalPosition));
  }

  Future<void> _showEditorCodeContextMenuAsync(
    String filePath,
    Offset globalPosition,
  ) async {
    if (!mounted) return;
    final colorScheme = Theme.of(context).colorScheme;
    final controller = _textControllers[filePath];
    final hasSelection =
        controller != null &&
        controller.selection.start != controller.selection.end;

    Widget submenuIndicator() {
      return Icon(
        Icons.chevron_right_rounded,
        size: 16,
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
      );
    }

    Widget shortcutLabel(String text) {
      return Padding(
        padding: const EdgeInsets.only(left: 24),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    PopupMenuItem<String> buildItem({
      required String value,
      required IconData icon,
      required String label,
      String? shortcut,
      bool hasSubmenu = false,
      bool enabled = true,
      Color? iconColor,
      Color? textColor,
    }) {
      return PopupMenuItem<String>(
        value: value,
        enabled: enabled,
        child: Row(
          children: [
            Icon(icon, size: 18, color: iconColor),
            kOpenHandHGap10,
            Expanded(
              child: Text(
                label,
                style: textColor != null ? TextStyle(color: textColor) : null,
              ),
            ),
            if (shortcut != null) shortcutLabel(shortcut),
            if (hasSubmenu) submenuIndicator(),
          ],
        ),
      );
    }

    final selected = await showAnimatedMenu<String>(
      context: context,
      position: _menuPositionForGlobalOffset(globalPosition),
      items: [
        buildItem(
          value: _ctxGoToDefinition,
          icon: Icons.gps_fixed_rounded,
          label: _editorText(
            zh: '跳转到定义',
            zhHant: '跳至定義',
            en: 'Go to Definition',
            fr: 'Aller à la définition',
            de: 'Zur Definition',
            ja: '定義へ移動',
          ),
          shortcut: 'F12',
        ),
        buildItem(
          value: _ctxFindReferences,
          icon: Icons.search_rounded,
          label: _editorText(
            zh: '查找引用',
            zhHant: '尋找參照',
            en: 'Find References',
            fr: 'Rechercher les références',
            de: 'Referenzen suchen',
            ja: '参照を検索',
          ),
          shortcut: '⇧F12',
        ),
        buildItem(
          value: _ctxGoToImplementation,
          icon: Icons.integration_instructions_outlined,
          label: _editorText(
            zh: '跳转到实现',
            zhHant: '跳至實作',
            en: 'Go to Implementation',
            fr: 'Aller à l’implémentation',
            de: 'Zur Implementierung',
            ja: '実装へ移動',
          ),
          shortcut: '⌥⌘B',
        ),
        buildItem(
          value: _ctxHoverInfo,
          icon: Icons.info_outline_rounded,
          label: _editorText(
            zh: '悬浮信息',
            zhHant: '懸浮資訊',
            en: 'Hover Info',
            fr: 'Info au survol',
            de: 'Hover-Info',
            ja: 'ホバー情報',
          ),
          shortcut: '⌘I',
        ),
        const PopupMenuDivider(),
        buildItem(
          value: _ctxRefactorSubmenu,
          icon: Icons.build_rounded,
          label: _editorText(
            zh: '重构',
            zhHant: '重構',
            en: 'Refactor',
            fr: 'Refactoriser',
            de: 'Refaktorieren',
            ja: 'リファクタリング',
          ),
          hasSubmenu: true,
        ),
        buildItem(
          value: _ctxNavigateSubmenu,
          icon: Icons.explore_rounded,
          label: _editorText(
            zh: '导航',
            zhHant: '導覽',
            en: 'Navigate',
            fr: 'Naviguer',
            de: 'Navigieren',
            ja: 'ナビゲート',
          ),
          hasSubmenu: true,
        ),
        buildItem(
          value: _ctxFoldingSubmenu,
          icon: Icons.unfold_less_rounded,
          label: _editorText(
            zh: '折叠',
            zhHant: '摺疊',
            en: 'Folding',
            fr: 'Pliage',
            de: 'Faltung',
            ja: '折りたたみ',
          ),
          hasSubmenu: true,
        ),
        const PopupMenuDivider(),
        buildItem(
          value: _ctxCut,
          icon: Icons.content_cut_rounded,
          label: _editorText(
            zh: '剪切',
            zhHant: '剪下',
            en: 'Cut',
            fr: 'Couper',
            de: 'Ausschneiden',
            ja: '切り取り',
          ),
          shortcut: '⌘X',
          enabled: hasSelection,
        ),
        buildItem(
          value: _ctxCopy,
          icon: Icons.content_copy_rounded,
          label: _editorText(
            zh: '复制',
            zhHant: '複製',
            en: 'Copy',
            fr: 'Copier',
            de: 'Kopieren',
            ja: 'コピー',
          ),
          shortcut: '⌘C',
          enabled: hasSelection,
        ),
        buildItem(
          value: _ctxPaste,
          icon: Icons.content_paste_rounded,
          label: _editorText(
            zh: '粘贴',
            zhHant: '貼上',
            en: 'Paste',
            fr: 'Coller',
            de: 'Einfügen',
            ja: '貼り付け',
          ),
          shortcut: '⌘V',
        ),
        buildItem(
          value: _ctxSelectAll,
          icon: Icons.select_all_rounded,
          label: _editorText(
            zh: '全选',
            zhHant: '全選',
            en: 'Select All',
            fr: 'Tout sélectionner',
            de: 'Alles auswählen',
            ja: 'すべて選択',
          ),
          shortcut: '⌘A',
        ),
        const PopupMenuDivider(),
        buildItem(
          value: _ctxFind,
          icon: Icons.find_in_page_rounded,
          label: _editorText(
            zh: '查找',
            zhHant: '尋找',
            en: 'Find',
            fr: 'Rechercher',
            de: 'Suchen',
            ja: '検索',
          ),
          shortcut: '⌘F',
        ),
        buildItem(
          value: _ctxReplace,
          icon: Icons.find_replace_rounded,
          label: _editorText(
            zh: '替换',
            zhHant: '取代',
            en: 'Replace',
            fr: 'Remplacer',
            de: 'Ersetzen',
            ja: '置換',
          ),
          shortcut: '⌘H',
        ),
        const PopupMenuDivider(),
        buildItem(
          value: _ctxOpenInExplorer,
          icon: Icons.folder_open_outlined,
          label: _editorText(
            zh: '在系统文件浏览器中打开',
            zhHant: '在系統檔案瀏覽器中開啟',
            en: 'Open in System Explorer',
            fr: 'Ouvrir dans l’explorateur système',
            de: 'Im System-Dateimanager öffnen',
            ja: 'システムファイルブラウザで開く',
          ),
        ),
        buildItem(
          value: _ctxCopyPath,
          icon: Icons.link_rounded,
          label: _editorText(
            zh: '复制路径 / 引用…',
            zhHant: '複製路徑 / 引用…',
            en: 'Copy Path / Reference…',
            fr: 'Copier chemin / référence…',
            de: 'Pfad / Referenz kopieren…',
            ja: 'パス / 参照をコピー…',
          ),
        ),
      ],
    );
    if (selected == null || !mounted) return;

    switch (selected) {
      case _ctxGoToDefinition:
        unawaited(_goToDefinitionAtCursor());
      case _ctxFindReferences:
        unawaited(_findReferencesAtCursor());
      case _ctxGoToImplementation:
        unawaited(_goToImplementationAtCursor());
      case _ctxHoverInfo:
        unawaited(_showHoverAtCursor());
      case _ctxRefactorSubmenu:
        unawaited(_showRefactorSubmenu(filePath, globalPosition));
      case _ctxNavigateSubmenu:
        unawaited(_showNavigateSubmenu(filePath, globalPosition));
      case _ctxFoldingSubmenu:
        unawaited(_showFoldingSubmenu(filePath, globalPosition));
      case _ctxCut:
        _editorClipboardCut(filePath);
      case _ctxCopy:
        _editorClipboardCopy(filePath);
      case _ctxPaste:
        unawaited(_editorClipboardPaste(filePath));
      case _ctxSelectAll:
        _editorSelectAll(filePath);
      case _ctxFind:
        _showFind();
      case _ctxReplace:
        _showFindAndReplace();
      case _ctxOpenInExplorer:
        unawaited(_openFileInSystemExplorer(filePath));
      case _ctxCopyPath:
        unawaited(_showEditorFileCopyPathMenu(filePath, globalPosition));
    }
  }

  // ── Refactor submenu ──

  /// 重构 / 导航 / 折叠三个子菜单共用的条目构造，样式保持一致。
  PopupMenuItem<String> _buildSubmenuItem({
    required String value,
    required IconData icon,
    required String label,
    String? shortcut,
    bool enabled = true,
  }) {
    return PopupMenuItem<String>(
      value: value,
      enabled: enabled,
      child: Row(
        children: [
          Icon(icon, size: 18),
          kOpenHandHGap10,
          Expanded(child: Text(label)),
          if (shortcut != null)
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Text(
                shortcut,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showRefactorSubmenu(
    String filePath,
    Offset globalPosition,
  ) async {
    if (!mounted) return;

    final selected = await showAnimatedMenu<String>(
      context: context,
      position: _menuPositionForGlobalOffset(globalPosition),
      items: [
        _buildSubmenuItem(
          value: 'rename',
          icon: Icons.drive_file_rename_outline,
          label: _editorText(
            zh: '重命名…',
            zhHant: '重新命名…',
            en: 'Rename…',
            fr: 'Renommer…',
            de: 'Umbenennen…',
            ja: '名前を変更…',
          ),
          shortcut: 'F2',
        ),
        _buildSubmenuItem(
          value: 'code_actions',
          icon: Icons.lightbulb_outline_rounded,
          label: _editorText(
            zh: '代码操作…',
            zhHant: '程式碼操作…',
            en: 'Code Actions…',
            fr: 'Actions de code…',
            de: 'Codeaktionen…',
            ja: 'コードアクション…',
          ),
          shortcut: '⌘.',
        ),
        const PopupMenuDivider(),
        _buildSubmenuItem(
          value: 'extract_method',
          icon: Icons.functions_rounded,
          label: _editorText(
            zh: '提取方法…',
            zhHant: '提取方法…',
            en: 'Extract Method…',
            fr: 'Extraire une méthode…',
            de: 'Methode extrahieren…',
            ja: 'メソッドを抽出…',
          ),
          shortcut: '⌥⌘M',
        ),
        _buildSubmenuItem(
          value: 'extract_variable',
          icon: Icons.data_object_rounded,
          label: _editorText(
            zh: '提取变量…',
            zhHant: '提取變數…',
            en: 'Extract Variable…',
            fr: 'Extraire une variable…',
            de: 'Variable extrahieren…',
            ja: '変数を抽出…',
          ),
          shortcut: '⌥⌘V',
        ),
        _buildSubmenuItem(
          value: 'extract_constant',
          icon: Icons.pin_rounded,
          label: _editorText(
            zh: '提取常量…',
            zhHant: '提取常數…',
            en: 'Extract Constant…',
            fr: 'Extraire une constante…',
            de: 'Konstante extrahieren…',
            ja: '定数を抽出…',
          ),
          shortcut: '⌥⌘C',
        ),
        const PopupMenuDivider(),
        _buildSubmenuItem(
          value: 'inline',
          icon: Icons.compress_rounded,
          label: _editorText(
            zh: '内联函数/方法',
            zhHant: '內嵌函式/方法',
            en: 'Inline Function/Method',
            fr: 'Intégrer fonction/méthode',
            de: 'Funktion/Methode inline setzen',
            ja: '関数/メソッドをインライン化',
          ),
          shortcut: '⌥⌘N',
        ),
        _buildSubmenuItem(
          value: 'change_signature',
          icon: Icons.tune_rounded,
          label: _editorText(
            zh: '更改签名…',
            zhHant: '變更簽名…',
            en: 'Change Signature…',
            fr: 'Modifier la signature…',
            de: 'Signatur ändern…',
            ja: 'シグネチャを変更…',
          ),
          shortcut: '⌘F6',
        ),
      ],
    );
    if (selected == null || !mounted) return;

    switch (selected) {
      case 'rename':
        unawaited(_renameSymbolAtCursor());
      case 'code_actions':
        unawaited(_showCodeActionsAtCursor());
      case 'extract_method':
        unawaited(
          _executeRefactorCodeAction(filePath, 'refactor.extract.function'),
        );
      case 'extract_variable':
        unawaited(
          _executeRefactorCodeAction(filePath, 'refactor.extract.variable'),
        );
      case 'extract_constant':
        unawaited(
          _executeRefactorCodeAction(filePath, 'refactor.extract.constant'),
        );
      case 'inline':
        unawaited(_executeRefactorCodeAction(filePath, 'refactor.inline'));
      case 'change_signature':
        unawaited(_showCodeActionsAtCursor());
    }
  }

  // ── Navigate submenu ──

  Future<void> _showNavigateSubmenu(
    String filePath,
    Offset globalPosition,
  ) async {
    if (!mounted) return;

    final selected = await showAnimatedMenu<String>(
      context: context,
      position: _menuPositionForGlobalOffset(globalPosition),
      items: [
        _buildSubmenuItem(
          value: 'definition',
          icon: Icons.gps_fixed_rounded,
          label: _editorText(
            zh: '声明 / 用法',
            zhHant: '宣告 / 用法',
            en: 'Declaration or Usages',
            fr: 'Déclaration ou usages',
            de: 'Deklaration oder Verwendungen',
            ja: '宣言 / 使用箇所',
          ),
          shortcut: '⌘B',
        ),
        _buildSubmenuItem(
          value: 'implementation',
          icon: Icons.integration_instructions_outlined,
          label: _editorText(
            zh: '实现',
            zhHant: '實作',
            en: 'Implementation(s)',
            fr: 'Implémentation(s)',
            de: 'Implementierung(en)',
            ja: '実装',
          ),
          shortcut: '⌥⌘B',
        ),
        const PopupMenuDivider(),
        _buildSubmenuItem(
          value: 'document_symbols',
          icon: Icons.account_tree_rounded,
          label: _editorText(
            zh: '文档符号',
            zhHant: '文件符號',
            en: 'Document Symbols',
            fr: 'Symboles du document',
            de: 'Dokumentsymbole',
            ja: 'ドキュメントシンボル',
          ),
          shortcut: '⌘⇧O',
        ),
        _buildSubmenuItem(
          value: 'workspace_symbols',
          icon: Icons.workspaces_outlined,
          label: _editorText(
            zh: '工作区符号',
            zhHant: '工作區符號',
            en: 'Workspace Symbols',
            fr: 'Symboles du workspace',
            de: 'Workspace-Symbole',
            ja: 'ワークスペースシンボル',
          ),
          shortcut: '⌘T',
        ),
        const PopupMenuDivider(),
        _buildSubmenuItem(
          value: 'go_to_line',
          icon: Icons.format_list_numbered_rounded,
          label: _editorText(
            zh: '跳转到行…',
            zhHant: '跳至行…',
            en: 'Go to Line…',
            fr: 'Aller à la ligne…',
            de: 'Gehe zu Zeile…',
            ja: '行へ移動…',
          ),
          shortcut: '⌘G',
        ),
      ],
    );
    if (selected == null || !mounted) return;

    switch (selected) {
      case 'definition':
        unawaited(_goToDefinitionAtCursor());
      case 'implementation':
        unawaited(_goToImplementationAtCursor());
      case 'document_symbols':
        _showSymbolBar();
      case 'workspace_symbols':
        _showWorkspaceSymbolBar();
      case 'go_to_line':
        _showGoToLine();
    }
  }

  // ── Folding submenu ──

  Future<void> _showFoldingSubmenu(
    String filePath,
    Offset globalPosition,
  ) async {
    if (!mounted) return;
    final hasFoldedRegions = _foldedRegions[filePath]?.isNotEmpty == true;
    final foldableRegions = _foldableRegionsForFile(filePath);
    final hasFoldableRegions = foldableRegions.isNotEmpty;

    final selected = await showAnimatedMenu<String>(
      context: context,
      position: _menuPositionForGlobalOffset(globalPosition),
      items: [
        _buildSubmenuItem(
          value: 'toggle_fold',
          icon: Icons.unfold_more_rounded,
          label: _editorText(
            zh: '切换折叠',
            zhHant: '切換摺疊',
            en: 'Toggle Folding',
            fr: 'Basculer le pliage',
            de: 'Faltung umschalten',
            ja: '折りたたみを切り替え',
          ),
          enabled: hasFoldableRegions,
        ),
        const PopupMenuDivider(),
        _buildSubmenuItem(
          value: 'fold_all',
          icon: Icons.unfold_less_rounded,
          label: _editorText(
            zh: '全部折叠',
            zhHant: '全部摺疊',
            en: 'Collapse All',
            fr: 'Tout replier',
            de: 'Alle einklappen',
            ja: 'すべて折りたたむ',
          ),
          shortcut: '⇧⌘-',
          enabled: hasFoldableRegions,
        ),
        _buildSubmenuItem(
          value: 'unfold_all',
          icon: Icons.unfold_more_rounded,
          label: _editorText(
            zh: '全部展开',
            zhHant: '全部展開',
            en: 'Expand All',
            fr: 'Tout déplier',
            de: 'Alle ausklappen',
            ja: 'すべて展開',
          ),
          shortcut: '⇧⌘+',
          enabled: hasFoldedRegions,
        ),
        const PopupMenuDivider(),
        _buildSubmenuItem(
          value: 'fold_at_cursor',
          icon: Icons.expand_less_rounded,
          label: _editorText(
            zh: '折叠当前区域',
            zhHant: '摺疊目前區域',
            en: 'Collapse',
            fr: 'Replier',
            de: 'Einklappen',
            ja: '折りたたむ',
          ),
          shortcut: '⌘-',
          enabled: hasFoldableRegions,
        ),
        _buildSubmenuItem(
          value: 'unfold_at_cursor',
          icon: Icons.expand_more_rounded,
          label: _editorText(
            zh: '展开当前区域',
            zhHant: '展開目前區域',
            en: 'Expand',
            fr: 'Déplier',
            de: 'Ausklappen',
            ja: '展開',
          ),
          shortcut: '⌘+',
          enabled: hasFoldedRegions,
        ),
        const PopupMenuDivider(),
        _buildSubmenuItem(
          value: 'fold_comments',
          icon: Icons.comment_rounded,
          label: _editorText(
            zh: '折叠文档注释',
            zhHant: '摺疊文件註解',
            en: 'Collapse Doc Comments',
            fr: 'Replier les commentaires de doc',
            de: 'Doku-Kommentare einklappen',
            ja: 'ドキュメントコメントを折りたたむ',
          ),
          enabled: hasFoldableRegions,
        ),
        _buildSubmenuItem(
          value: 'unfold_comments',
          icon: Icons.insert_comment_rounded,
          label: _editorText(
            zh: '展开文档注释',
            zhHant: '展開文件註解',
            en: 'Expand Doc Comments',
            fr: 'Déplier les commentaires de doc',
            de: 'Doku-Kommentare ausklappen',
            ja: 'ドキュメントコメントを展開',
          ),
          enabled: hasFoldedRegions,
        ),
      ],
    );
    if (selected == null || !mounted) return;

    switch (selected) {
      case 'toggle_fold':
        _toggleFoldAtCursor(filePath);
      case 'fold_all':
        _foldAll(filePath);
      case 'unfold_all':
        _unfoldAll(filePath);
      case 'fold_at_cursor':
        _foldAtCursor(filePath);
      case 'unfold_at_cursor':
        _unfoldAtCursor(filePath);
      case 'fold_comments':
        _foldComments(filePath);
      case 'unfold_comments':
        _unfoldComments(filePath);
    }
  }

  // ── Go to Implementation (LSP textDocument/implementation) ──

  Future<void> _goToImplementationAtCursor() async {
    final title = AppLocalizations.of(context)!.progExpFEGoToImplementation;
    final resolution = await _prepareCursorLspAction(title);
    if (resolution == null) return;
    final controller = _textControllers[widget.activeFilePath];
    if (controller == null) return;
    try {
      final result = await AiLspClientService.instance.request(
        operation: 'goToImplementation',
        filePath: widget.activeFilePath,
        line: _cursorLine,
        character: _cursorColumn,
        language: resolution.language,
        documentText: controller.text,
      );
      if (!mounted) return;
      final locations = AiLspClientService.parseLocations(result);
      if (locations.isEmpty) {
        _showLspMessage(
          title: title,
          message: AppLocalizations.of(
            context,
          )!.progExpFENoImplementationWasFoundAtThe,
        );
        return;
      }
      if (locations.length == 1) {
        _hideLspResultBar();
        await _navigateToLspLocation(locations.first);
        return;
      }
      _showLspLocations(
        title: title,
        locations: locations,
        message: AppLocalizations.of(
          context,
        )!.progExpFEMultipleImplementationsFoundChooseATarge,
      );
    } catch (error) {
      if (!mounted) return;
      _showLspMessage(title: title, message: _friendlyLspError(error));
    }
  }

  // ── Refactor code action by kind ──

  Future<void> _executeRefactorCodeAction(
    String filePath,
    String codeActionKind,
  ) async {
    final title = AppLocalizations.of(context)!.progExpFERefactor;
    final resolution = await _prepareCursorLspAction(title);
    if (resolution == null) return;
    final controller = _textControllers[filePath];
    if (controller == null) return;
    try {
      await _syncOpenDocumentsForLsp();
      final range = _selectionRangeForController(controller);
      final actions = await AiLspClientService.instance.codeActions(
        filePath: filePath,
        range: range,
        language: resolution.language,
        documentText: controller.text,
      );
      if (!mounted) return;
      final matching = actions
          .where((a) => a.kind?.startsWith(codeActionKind) == true)
          .toList(growable: false);
      if (matching.isEmpty) {
        _showLspMessage(
          title: title,
          message: AppLocalizations.of(
            context,
          )!.progExpFENoCodeactionkindRefactoringIsAvailableAt(codeActionKind),
        );
        return;
      }
      if (matching.length == 1) {
        await _applyRefactorCodeAction(matching.first, filePath);
        return;
      }
      // Multiple matching actions — let user choose
      await _showCodeActionPickerAndApply(
        title: title,
        actions: matching,
        filePath: filePath,
      );
    } catch (error) {
      if (!mounted) return;
      _showLspMessage(title: title, message: _friendlyLspError(error));
    }
  }

  Future<void> _showCodeActionPickerAndApply({
    required String title,
    required List<AiLspCodeAction> actions,
    required String filePath,
  }) async {
    if (!mounted || actions.isEmpty) return;
    final selected = await showAnimatedDialog<AiLspCodeAction>(
      context: context,
      builder: (dialogContext) {
        return buildOpenHandAlertDialog(
          title: Text(title),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460, maxHeight: 320),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final action in actions)
                    ListTile(
                      title: Text(action.title),
                      subtitle: action.kind != null
                          ? Text(
                              action.kind!,
                              style: const TextStyle(fontSize: 11),
                            )
                          : null,
                      onTap: () => Navigator.of(dialogContext).pop(action),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            OpenHandDialogActionButton.secondary(
              onPressed: () => Navigator.of(dialogContext).pop(),
              label: openHandCancelLabel(dialogContext),
            ),
          ],
        );
      },
    );
    if (selected == null || !mounted) return;
    await _applyRefactorCodeAction(selected, filePath);
  }

  Future<void> _applyRefactorCodeAction(
    AiLspCodeAction action,
    String filePath,
  ) async {
    final title = action.title;
    try {
      final resolved = await AiLspClientService.instance.resolveCodeAction(
        filePath: filePath,
        action: action,
        language: _resolvedLanguageForFile(filePath),
      );
      if (!mounted) return;
      final edit = resolved.edit;
      if (edit != null && !edit.isEmpty) {
        final applied = await _reviewWorkspaceEditAndMaybeApply(
          title: title,
          edit: edit,
          description: AppLocalizations.of(
            context,
          )!.progExpFEReviewTheChangesBeforeApplying,
        );
        if (!mounted) return;
        if (applied) {
          _showLspMessage(title: title, message: _workspaceEditSummary(edit));
        }
        return;
      }
      final command = resolved.command;
      if (command != null) {
        await AiLspClientService.instance.executeCommand(
          filePath: filePath,
          command: command,
          language: _resolvedLanguageForFile(filePath),
        );
      }
    } catch (error) {
      if (!mounted) return;
      _showLspMessage(title: title, message: _friendlyLspError(error));
    }
  }

  // ── Clipboard operations (for context menu) ──

  void _editorClipboardCut(String filePath) {
    final controller = _textControllers[filePath];
    if (controller == null) return;
    final selection = controller.selection;
    if (selection.start == selection.end) return;
    final selectedText = controller.text.substring(
      selection.start,
      selection.end,
    );
    unawaited(
      _setProgrammingExplorerClipboardText(selectedText, logAction: '编辑器剪切'),
    );
    _commitProgrammaticEditorValueChange(
      filePath,
      controller,
      TextEditingValue(
        text: controller.text.replaceRange(selection.start, selection.end, ''),
        selection: TextSelection.collapsed(offset: selection.start),
      ),
    );
  }

  void _editorClipboardCopy(String filePath) {
    final controller = _textControllers[filePath];
    if (controller == null) return;
    final selection = controller.selection;
    if (selection.start == selection.end) return;
    final selectedText = controller.text.substring(
      selection.start,
      selection.end,
    );
    unawaited(
      _setProgrammingExplorerClipboardText(selectedText, logAction: '编辑器复制'),
    );
  }

  Future<void> _editorClipboardPaste(String filePath) async {
    final controller = _textControllers[filePath];
    if (controller == null) return;
    final pasteText = await getOpenHandClipboardText();
    if (pasteText == null || pasteText.isEmpty) return;
    final selection = controller.selection;
    final newOffset = selection.start + pasteText.length;
    _commitProgrammaticEditorValueChange(
      filePath,
      controller,
      TextEditingValue(
        text: controller.text.replaceRange(
          selection.start,
          selection.end,
          pasteText,
        ),
        selection: TextSelection.collapsed(offset: newOffset),
      ),
    );
  }

  void _editorSelectAll(String filePath) {
    final controller = _textControllers[filePath];
    if (controller == null) return;
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
  }

  // ── Open file in system explorer ──

  Future<void> _openFileInSystemExplorer(String filePath) async {
    final target = p.dirname(filePath);
    try {
      await openLocalPathWithSystemApp(
        target,
        tag: 'file_explorer.open_file_in_system_explorer',
      );
    } catch (error, stack) {
      silentLog('file_explorer', '在系统文件管理器中打开文件', error, stack);
    }
  }

  // ── Code folding infrastructure ──

  /// Map of filePath → set of start lines that are currently folded.
  final Map<String, Set<int>> _foldedRegions = <String, Set<int>>{};

  /// Returns foldable regions for a file from braces/indentation analysis.
  List<_FoldableRegion> _foldableRegionsForFile(String filePath) {
    final controller = _textControllers[filePath];
    if (controller == null) return const <_FoldableRegion>[];
    return _computeFoldableRegions(controller.text);
  }

  /// Computes foldable regions from code structure (brace matching).
  static List<_FoldableRegion> _computeFoldableRegions(String text) {
    final regions = <_FoldableRegion>[];
    final lines = text.split('\n');
    final braceStack = <int>[]; // stack of line numbers with opening braces

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trimRight();
      // Count brace openings/closings
      for (var j = 0; j < line.length; j++) {
        final ch = line.codeUnitAt(j);
        if (ch == 0x7B) {
          // '{'
          braceStack.add(i + 1); // 1-indexed line
        } else if (ch == 0x7D && braceStack.isNotEmpty) {
          // '}'
          final startLine = braceStack.removeLast();
          final endLine = i + 1;
          if (endLine > startLine + 1) {
            regions.add(
              _FoldableRegion(startLine: startLine, endLine: endLine),
            );
          }
        }
      }
    }

    // Also detect multi-line comment blocks (/* ... */ and /// doc comments)
    bool inBlockComment = false;
    int blockCommentStart = 0;
    int consecutiveDocStart = 0;
    int consecutiveDocCount = 0;

    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trimLeft();
      // Block comments
      if (!inBlockComment && trimmed.startsWith('/*')) {
        inBlockComment = true;
        blockCommentStart = i + 1;
      }
      if (inBlockComment && trimmed.contains('*/')) {
        inBlockComment = false;
        final endLine = i + 1;
        if (endLine > blockCommentStart + 1) {
          regions.add(
            _FoldableRegion(
              startLine: blockCommentStart,
              endLine: endLine,
              isComment: true,
            ),
          );
        }
      }
      // Consecutive line doc comments (///)
      if (trimmed.startsWith('///')) {
        if (consecutiveDocCount == 0) {
          consecutiveDocStart = i + 1;
        }
        consecutiveDocCount++;
      } else {
        if (consecutiveDocCount > 2) {
          regions.add(
            _FoldableRegion(
              startLine: consecutiveDocStart,
              endLine: consecutiveDocStart + consecutiveDocCount - 1,
              isComment: true,
            ),
          );
        }
        consecutiveDocCount = 0;
      }
    }
    if (consecutiveDocCount > 2) {
      regions.add(
        _FoldableRegion(
          startLine: consecutiveDocStart,
          endLine: consecutiveDocStart + consecutiveDocCount - 1,
          isComment: true,
        ),
      );
    }

    regions.sort((a, b) => a.startLine.compareTo(b.startLine));
    return regions;
  }

  _FoldableRegion? _foldableRegionAtCursor(String filePath) {
    final regions = _foldableRegionsForFile(filePath);
    for (final region in regions) {
      if (_cursorLine >= region.startLine && _cursorLine <= region.endLine) {
        return region;
      }
    }
    return null;
  }

  void _toggleFoldAtCursor(String filePath) {
    final region = _foldableRegionAtCursor(filePath);
    if (region == null) return;
    final folded = _foldedRegions.putIfAbsent(filePath, () => <int>{});
    setState(() {
      if (folded.contains(region.startLine)) {
        folded.remove(region.startLine);
      } else {
        folded.add(region.startLine);
      }
    });
    _applyFolding(filePath);
  }

  void _foldAtCursor(String filePath) {
    final region = _foldableRegionAtCursor(filePath);
    if (region == null) return;
    final folded = _foldedRegions.putIfAbsent(filePath, () => <int>{});
    if (folded.contains(region.startLine)) return;
    setState(() => folded.add(region.startLine));
    _applyFolding(filePath);
  }

  void _unfoldAtCursor(String filePath) {
    final region = _foldableRegionAtCursor(filePath);
    if (region == null) return;
    final folded = _foldedRegions[filePath];
    if (folded == null || !folded.contains(region.startLine)) return;
    setState(() => folded.remove(region.startLine));
    _applyFolding(filePath);
  }

  void _foldAll(String filePath) {
    final regions = _foldableRegionsForFile(filePath);
    if (regions.isEmpty) return;
    final folded = _foldedRegions.putIfAbsent(filePath, () => <int>{});
    setState(() {
      for (final region in regions) {
        folded.add(region.startLine);
      }
    });
    _applyFolding(filePath);
  }

  void _unfoldAll(String filePath) {
    final folded = _foldedRegions[filePath];
    if (folded == null || folded.isEmpty) return;
    setState(() => folded.clear());
    _applyFolding(filePath);
  }

  void _foldComments(String filePath) {
    final regions = _foldableRegionsForFile(filePath);
    final commentRegions = regions
        .where((r) => r.isComment)
        .toList(growable: false);
    if (commentRegions.isEmpty) return;
    final folded = _foldedRegions.putIfAbsent(filePath, () => <int>{});
    setState(() {
      for (final region in commentRegions) {
        folded.add(region.startLine);
      }
    });
    _applyFolding(filePath);
  }

  void _unfoldComments(String filePath) {
    final regions = _foldableRegionsForFile(filePath);
    final commentStarts = regions
        .where((r) => r.isComment)
        .map((r) => r.startLine)
        .toSet();
    final folded = _foldedRegions[filePath];
    if (folded == null || folded.isEmpty) return;
    setState(() => folded.removeWhere((line) => commentStarts.contains(line)));
    _applyFolding(filePath);
  }

  /// Applies folding state to the text controller by updating hidden lines.
  void _applyFolding(String filePath) {
    final controller = _textControllers[filePath];
    if (controller == null) return;
    final foldedStarts = _foldedRegions[filePath];
    if (foldedStarts == null || foldedStarts.isEmpty) {
      controller.foldedLineRanges = const <_FoldableRegion>[];
      return;
    }
    final regions = _foldableRegionsForFile(filePath);
    final active = regions
        .where((r) => foldedStarts.contains(r.startLine))
        .toList(growable: false);
    controller.foldedLineRanges = active;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (!_fileContents.containsKey(widget.activeFilePath) &&
        _fileLoading[widget.activeFilePath] != true) {
      _loadFile(widget.activeFilePath);
    }

    return Focus(
      onKeyEvent: (_, event) =>
          _handleEditorShortcutKeyEvent(widget.activeFilePath, event),
      child: Column(
        children: [
          // ── Tab bar — fully rounded pill container ──
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: kOpenHandBorderRadius22,
            ),
            child: Row(
              children: [
                Expanded(
                  child: ReorderableListView(
                    scrollDirection: Axis.horizontal,
                    buildDefaultDragHandles: false,
                    proxyDecorator: (child, index, animation) {
                      return Material(
                        elevation: 6,
                        color: Colors.transparent,
                        shadowColor: colorScheme.shadow.withValues(alpha: 0.3),
                        borderRadius: kOpenHandPillBorderRadius,
                        child: child,
                      );
                    },
                    onReorder: widget.onReorderTabs,
                    padding: const EdgeInsets.only(
                      left: 6,
                      top: 5,
                      bottom: 5,
                      right: 2,
                    ),
                    children: [
                      for (var i = 0; i < widget.openFiles.length; i++)
                        _EditorTab(
                          key: ValueKey<String>(widget.openFiles[i]),
                          index: i,
                          fileName: p.basename(widget.openFiles[i]),
                          filePath: widget.openFiles[i],
                          isActive:
                              widget.openFiles[i] == widget.activeFilePath,
                          isDirty: _fileDirty[widget.openFiles[i]] == true,
                          onTap: () =>
                              widget.onTabSelected(widget.openFiles[i]),
                          onClose: () => _confirmCloseTab(widget.openFiles[i]),
                          onShowMenu: (position) {
                            unawaited(
                              _showEditorTabMenu(widget.openFiles[i], position),
                            );
                          },
                        ),
                    ],
                  ),
                ),
                // Save button
                if (_fileDirty[widget.activeFilePath] == true) ...[
                  _EditorActionButton(
                    tooltip: AppLocalizations.of(context)!.progExpFESaveFile,
                    icon: Icons.save_rounded,
                    color: colorScheme.primary,
                    onPressed: () => _saveFile(widget.activeFilePath),
                  ),
                ],
                // File explorer toggle button
                if (widget.onToggleFileExplorer != null)
                  _EditorActionButton(
                    tooltip: (widget.fileExplorerVisible
                        ? AppLocalizations.of(context)!.progExpFEHideFileBrowser
                        : AppLocalizations.of(
                            context,
                          )!.progExpFEShowFileBrowser),
                    icon: widget.fileExplorerVisible
                        ? Icons.folder_open_rounded
                        : Icons.folder_rounded,
                    color: widget.fileExplorerVisible
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                    onPressed: widget.onToggleFileExplorer!,
                  ),
                // Close all button
                _EditorActionButton(
                  tooltip: AppLocalizations.of(
                    context,
                  )!.progExpFECloseEditorReturnToSession,
                  icon: Icons.close_rounded,
                  color: colorScheme.onSurfaceVariant,
                  onPressed: widget.onCloseAll,
                ),
                kOpenHandHGap6,
              ],
            ),
          ),
          // ── Gap between tab bar and editor ──
          kOpenHandGap6,
          // ── Editor content — rounded outer shell, square code area ──
          Expanded(
            child: _EditorZoomWrapper(
              onZoomIn: _zoomIn,
              onZoomOut: _zoomOut,
              onZoomReset: _zoomReset,
              onZoomByScale: _zoomByScale,
              child: Container(
                width: double.infinity,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: kOpenHandBorderRadius16,
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.2),
                    width: 0.5,
                  ),
                ),
                child: Column(
                  children: [
                    // ── Breadcrumb path bar ──
                    _EditorBreadcrumb(
                      filePath: widget.activeFilePath,
                      onNavigateToFile: widget.onTabSelected,
                    ),
                    // ── Divider ──
                    Divider(
                      height: 0.5,
                      thickness: 0.5,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                    ),
                    // ── Find / Replace bar ──
                    ClipRect(
                      child: AnimatedSize(
                        duration: openHandMotionDuration(context, kOpenHandMotion220,
                        ),
                        curve: kOpenHandSwitchInCurve,
                        alignment: Alignment.bottomCenter,
                        child: _buildFindBar(colorScheme),
                      ),
                    ),
                    // ── Go-to-Line bar ──
                    ClipRect(
                      child: AnimatedSize(
                        duration: openHandMotionDuration(context, kOpenHandMotion220,
                        ),
                        curve: kOpenHandSwitchInCurve,
                        alignment: Alignment.bottomCenter,
                        child: _buildGoToLineBar(colorScheme),
                      ),
                    ),
                    // ── Symbol navigation bar ──
                    ClipRect(
                      child: AnimatedSize(
                        duration: openHandMotionDuration(context, kOpenHandMotion220,
                        ),
                        curve: kOpenHandSwitchInCurve,
                        alignment: Alignment.bottomCenter,
                        child: _buildSymbolBar(colorScheme),
                      ),
                    ),
                    // ── Code content ──
                    Expanded(
                      child: ClipRect(
                        child: ColoredBox(
                          color: colorScheme.surface,
                          child: RepaintBoundary(
                            child: Transform.scale(
                              scale: _zoomVisualScale,
                              alignment: Alignment.topLeft,
                              child: _buildEditorContent(
                                widget.activeFilePath,
                                theme,
                                colorScheme,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // ── Bottom tool panels (IDEA-style: above status bar) ──
                    // Wrapped in AnimatedSize for smooth slide-in / slide-out.
                    ClipRect(
                      child: AnimatedSize(
                        duration: openHandMotionDuration(
                          context,
                          const Duration(milliseconds: 250),
                        ),
                        curve: kOpenHandSwitchInCurve,
                        alignment: Alignment.topCenter,
                        child: _buildProjectToolchainBar(colorScheme),
                      ),
                    ),
                    ClipRect(
                      child: AnimatedSize(
                        duration: openHandMotionDuration(
                          context,
                          const Duration(milliseconds: 250),
                        ),
                        curve: kOpenHandSwitchInCurve,
                        alignment: Alignment.topCenter,
                        child: _buildDiagnosticsBar(colorScheme),
                      ),
                    ),
                    ClipRect(
                      child: AnimatedSize(
                        duration: openHandMotionDuration(
                          context,
                          const Duration(milliseconds: 250),
                        ),
                        curve: kOpenHandSwitchInCurve,
                        alignment: Alignment.topCenter,
                        child: _buildLspResultBar(colorScheme),
                      ),
                    ),
                    // ── Status bar ──
                    _buildStatusBar(colorScheme),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditorContent(
    String filePath,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    if (_fileLoading[filePath] == true) {
      return Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: colorScheme.primary,
          ),
        ),
      );
    }
    final content = _fileContents[filePath];
    if (content == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            kOpenHandGap12,
            Text(
              _editorText(
                zh: '无法加载文件',
                zhHant: '無法載入檔案',
                en: 'Unable to load file',
                fr: 'Impossible de charger le fichier',
                de: 'Datei kann nicht geladen werden',
                ja: 'ファイルを読み込めません',
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            kOpenHandGap4,
            Text(
              p.basename(filePath),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      );
    }

    final textController = _textControllers[filePath];
    if (textController == null) return const SizedBox.shrink();

    final scrollController = _scrollControllers.putIfAbsent(
      filePath,
      ScrollController.new,
    );
    final focusNode = _focusNodes.putIfAbsent(filePath, FocusNode.new);
    final language = _resolvedLanguageForFile(filePath);
    final diagnostics =
        _diagnosticsByFile[filePath] ?? const <_EditorDiagnostic>[];
    final diagnosticsByLine = _diagnosticsByLineForFile(filePath);
    textController.diagnostics = diagnostics;

    if (!_forcedFullEditorFiles.contains(filePath) &&
        textController.useVirtualizedPreview) {
      return _LargeFileCodeView(
        key: ValueKey<String>('large-preview:$filePath'),
        controller: textController,
        scrollController: scrollController,
        language: language,
        fontSize: _fontSize,
        codeTheme: context.select<SettingsController, EditorCodeTheme>(
          (controller) => controller.editorCodeTheme,
        ),
        onOpenFullEditor: () {
          if (!mounted) return;
          textController.forceFullEditorHighlighting = true;
          textController.invalidateHighlightCache();
          setState(() => _forcedFullEditorFiles.add(filePath));
        },
      );
    }

    // Ensure the highlighting flag stays in sync when the full editor is forced
    // open for a large file (e.g. after hot reload or widget rebuild).
    if (textController.useVirtualizedPreview &&
        _forcedFullEditorFiles.contains(filePath)) {
      if (!textController.forceFullEditorHighlighting) {
        textController.forceFullEditorHighlighting = true;
        textController.invalidateHighlightCache();
      }
    }

    final Widget editorBody = Focus(
      onKeyEvent: (_, event) => _handleEditorShortcutKeyEvent(filePath, event),
      child: _SyntaxHighlightEditor(
        controller: textController,
        scrollController: scrollController,
        focusNode: focusNode,
        language: language,
        fontSize: _fontSize,
        // 逐项订阅：整体 watch 会让任意一条设置变更都重建整个编辑器。
        wordWrap: context.select<SettingsController, bool>(
          (controller) => controller.editorWordWrap,
        ),
        codeTheme: context.select<SettingsController, EditorCodeTheme>(
          (controller) => controller.editorCodeTheme,
        ),
        activeLine: _cursorLine,
        diagnostics: diagnostics,
        diagnosticsByLine: diagnosticsByLine,
        onChanged: (value) {
          if (!mounted) return;
          setState(() {
            _fileDirty[filePath] = true;
            _diagnosticsStaleFiles.add(filePath);
          });
          _scheduleDiagnosticsRefresh(filePath);
          _updateCursorPosition(textController);
          if (_findBarVisible && _findController.text.isNotEmpty) {
            _updateFindMatches(_findController.text);
          }
          if (_symbolBarVisible) {
            _scheduleSymbolRefresh();
          }
          // Trigger LSP completion on text changes
          _triggerCompletion();
          final signatureTriggerCharacter = _signatureTriggerCharacterAtOffset(
            textController.text,
            textController.selection.baseOffset,
          );
          if (signatureTriggerCharacter != null) {
            _triggerSignatureHelp(triggerCharacter: signatureTriggerCharacter);
          } else if (_signatureHelpVisible) {
            _triggerSignatureHelp();
          }
        },
        onSelectionChanged: () {
          if (!mounted) return;
          _updateCursorPosition(textController);
          if (_signatureHelpVisible) {
            _triggerSignatureHelp();
          }
        },
        onDiagnosticLineRequested: (lineNumber) {
          final diagnostics =
              diagnosticsByLine[lineNumber] ?? const <_EditorDiagnostic>[];
          final primaryDiagnostic = _primaryDiagnosticForLine(diagnostics);
          if (primaryDiagnostic == null) {
            return;
          }
          _jumpToLineColumn(lineNumber, column: primaryDiagnostic.column);
        },
        onDiagnosticQuickFixRequested: (lineNumber, anchorPosition) {
          unawaited(
            _showCodeActionsForDiagnosticLine(lineNumber, anchorPosition),
          );
        },
        onDiagnosticTooltipQuickFixRequested: (diagnostics, anchorPosition) {
          unawaited(
            _applyQuickFixForEditorDiagnostics(diagnostics, anchorPosition),
          );
        },
        onDiagnosticTooltipMoreActionsRequested: (diagnostics, anchorPosition) {
          unawaited(
            _showMoreActionsForEditorDiagnostics(diagnostics, anchorPosition),
          );
        },
        onSecondaryTapDown: (details) {
          _showEditorCodeContextMenu(filePath, details.globalPosition);
        },
      ),
    );

    // Always wrap with a stable Stack so toggling the completion overlay
    // does not restructure the widget tree (which would reset scroll position).
    final showCompletion =
        _completionVisible && _filteredCompletionItems.isNotEmpty;
    final showSignatureHelp =
        _signatureHelpVisible && _signatureHelp?.selectedSignature != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final children = <Widget>[editorBody];

        if (showCompletion || showSignatureHelp) {
          final lineCount = textController.lineCount;
          final hasAnyDiagnostics =
              (_diagnosticsByFile[filePath] ?? const <_EditorDiagnostic>[])
                  .isNotEmpty;
          final gutterWidth = _editorEditableGutterWidth(
            lineCount: lineCount,
            fontSize: _fontSize,
            hasDiagnostics: hasAnyDiagnostics,
          );
          // Measure monospace character width
          final charPainter = TextPainter(
            text: TextSpan(
              text: 'X',
              style: _editorBaseStyleForSize(_fontSize),
            ),
            textDirection: TextDirection.ltr,
            maxLines: 1,
          )..layout();
          final charWidth = charPainter.width;
          charPainter.dispose();

          final lineExtent = _fontSize * _editorLineHeight;
          const textPaddingLeft = 8.0;
          const textPaddingTop = 10.0;

          final scrollOffset = scrollController.hasClients
              ? scrollController.offset
              : 0.0;

          final cursorLeft =
              gutterWidth + textPaddingLeft + (_cursorColumn - 1) * charWidth;
          final cursorTop =
              textPaddingTop + (_cursorLine - 1) * lineExtent - scrollOffset;

          double? completionOverlayTop;
          double? completionOverlayLeft;

          if (showCompletion) {
            const overlayMaxHeight = 240.0;
            const overlayWidth = 360.0;

            // Default: show below cursor
            var overlayTop = cursorTop + lineExtent;
            // If popup would overflow bottom, flip above cursor
            if (overlayTop + overlayMaxHeight > constraints.maxHeight &&
                cursorTop - overlayMaxHeight > 0) {
              overlayTop = cursorTop - overlayMaxHeight;
            }
            // Clamp so it stays within bounds
            overlayTop = overlayTop.clamp(0.0, constraints.maxHeight - 40);

            // Clamp horizontal position
            var overlayLeft = cursorLeft;
            if (overlayLeft + overlayWidth > constraints.maxWidth) {
              overlayLeft = (constraints.maxWidth - overlayWidth).clamp(
                0.0,
                double.infinity,
              );
            }

            completionOverlayTop = overlayTop;
            completionOverlayLeft = overlayLeft;
            children.add(
              Positioned(
                left: overlayLeft,
                top: overlayTop,
                child: _CompletionOverlay(
                  items: _filteredCompletionItems,
                  selectedIndex: _completionSelectedIndex,
                  onSelected: _applyCompletionItem,
                  onDismissed: _dismissCompletionOverlay,
                ),
              ),
            );
          }

          if (showSignatureHelp) {
            const signatureMaxHeight = 220.0;
            const signatureWidth = 420.0;
            final signature = _signatureHelp!;
            var signatureTop = completionOverlayTop != null
                ? completionOverlayTop - signatureMaxHeight - 8
                : cursorTop + lineExtent + 8;
            if (completionOverlayTop == null &&
                signatureTop + signatureMaxHeight > constraints.maxHeight &&
                cursorTop - signatureMaxHeight - 8 > 0) {
              signatureTop = cursorTop - signatureMaxHeight - 8;
            }
            if (signatureTop < 0) {
              final fallbackTop = completionOverlayTop == null
                  ? cursorTop + lineExtent + 8
                  : completionOverlayTop + 240 + 8;
              signatureTop = math.min(
                math.max(0.0, fallbackTop),
                math.max(0.0, constraints.maxHeight - 40),
              );
            }

            var signatureLeft = completionOverlayLeft ?? cursorLeft;
            if (signatureLeft + signatureWidth > constraints.maxWidth) {
              signatureLeft = math.max(
                0.0,
                constraints.maxWidth - signatureWidth,
              );
            }

            children.add(
              Positioned(
                left: signatureLeft,
                top: signatureTop,
                child: _SignatureHelpOverlay(
                  help: signature,
                  onDismissed: _hideSignatureHelpOverlay,
                ),
              ),
            );
          }
        }

        return Stack(clipBehavior: Clip.none, children: children);
      },
    );
  }
}

// Completion overlay — IDEA-style autocomplete popup
class _CompletionOverlay extends StatelessWidget {
  const _CompletionOverlay({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.onDismissed,
  });

  final List<AiLspCompletionItem> items;
  final int selectedIndex;
  final ValueChanged<AiLspCompletionItem> onSelected;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final displayItems = items.length > 12 ? items.sublist(0, 12) : items;
    return Material(
      elevation: 8,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.3),
      borderRadius: kOpenHandBorderRadius10,
      color: colorScheme.surfaceContainerHighest,
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 420,
          minWidth: 200,
          maxHeight: 320,
        ),
        decoration: BoxDecoration(
          borderRadius: kOpenHandBorderRadius10,
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
            width: 0.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: kOpenHandBorderRadius10,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            shrinkWrap: true,
            itemCount: displayItems.length,
            itemBuilder: (context, index) {
              final item = displayItems[index];
              final isSelected = index == selectedIndex;
              final kindLabel = _CodeEditorViewState._completionItemKindLabel(
                item.kind,
              );
              return InkWell(
                onTap: () => onSelected(item),
                child: Container(
                  color: isSelected
                      ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                      : Colors.transparent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _CodeEditorViewState._completionItemKindIcon(item.kind),
                        size: 16,
                        color: isSelected
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                      kOpenHandHGap8,
                      Expanded(
                        child: Text(
                          item.label,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: kOpenHandMonospaceFontFamily,
                            fontSize: 12.5,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: isSelected
                                ? colorScheme.onPrimaryContainer
                                : colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (item.detail != null && item.detail!.isNotEmpty) ...[
                        kOpenHandHGap8,
                        Flexible(
                          child: Text(
                            item.detail!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.6,
                              ),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      if (kindLabel.isNotEmpty) ...[
                        kOpenHandHGap6,
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.secondaryContainer.withValues(
                              alpha: 0.5,
                            ),
                            borderRadius: BorderRadius.circular(kOpenHandRadius4),
                          ),
                          child: Text(
                            kindLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 9,
                              color: colorScheme.onSecondaryContainer
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SignatureHelpOverlay extends StatelessWidget {
  const _SignatureHelpOverlay({required this.help, required this.onDismissed});

  final AiLspSignatureHelp help;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final signature = help.selectedSignature;
    if (signature == null) {
      return const SizedBox.shrink();
    }
    final parameter = help.selectedParameter;
    final signatureDoc = signature.documentationPlainText.trim();
    final parameterDoc = parameter?.documentationPlainText.trim() ?? '';
    final hasParameterChips = signature.parameters.isNotEmpty;

    return Material(
      elevation: 10,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.28),
      borderRadius: kOpenHandBorderRadius12,
      color: colorScheme.surfaceContainerHighest,
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 460,
          minWidth: 260,
          maxHeight: 280,
        ),
        decoration: BoxDecoration(
          borderRadius: kOpenHandBorderRadius12,
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.34),
            width: 0.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: kOpenHandBorderRadius12,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        openHandLocalizedText(
                          context,
                          zh: '参数签名',
                          zhHant: '參數簽名',
                          en: 'Signature Help',
                          fr: 'Aide à la signature',
                          de: 'Signaturhilfe',
                          ja: 'シグネチャヘルプ',
                        ),
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    if (help.signatures.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          '${help.activeSignature + 1}/${help.signatures.length}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    InkWell(
                      borderRadius: kOpenHandPillBorderRadius,
                      onTap: onDismissed,
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                kOpenHandGap8,
                SelectableText.rich(
                  TextSpan(
                    children: _buildSignatureLabelSpans(
                      signature: signature,
                      activeParameterIndex: help.activeParameter,
                      theme: theme,
                      colorScheme: colorScheme,
                    ),
                  ),
                ),
                if (hasParameterChips) ...[
                  kOpenHandGap10,
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (
                        var index = 0;
                        index < signature.parameters.length;
                        index++
                      )
                        _SignatureParameterChip(
                          label: signature.parameters[index].label,
                          active: index == help.activeParameter,
                        ),
                    ],
                  ),
                ],
                if (parameterDoc.isNotEmpty) ...[
                  kOpenHandGap10,
                  Text(
                    openHandLocalizedText(
                      context,
                      zh: '当前参数',
                      zhHant: '目前參數',
                      en: 'Parameter',
                      fr: 'Paramètre',
                      de: 'Parameter',
                      ja: 'パラメータ',
                    ),
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.primary,
                    ),
                  ),
                  kOpenHandGap4,
                  SelectableText(
                    parameterDoc,
                    style: theme.textTheme.bodySmall?.copyWith(
                      height: 1.45,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
                if (signatureDoc.isNotEmpty) ...[
                  kOpenHandGap10,
                  Text(
                    openHandLocalizedText(
                      context,
                      zh: '文档说明',
                      zhHant: '文件說明',
                      en: 'Documentation',
                      fr: 'Documentation',
                      de: 'Dokumentation',
                      ja: 'ドキュメント',
                    ),
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.primary,
                    ),
                  ),
                  kOpenHandGap4,
                  SelectableText(
                    signatureDoc,
                    style: theme.textTheme.bodySmall?.copyWith(
                      height: 1.45,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static List<InlineSpan> _buildSignatureLabelSpans({
    required AiLspSignatureInformation signature,
    required int activeParameterIndex,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    final baseStyle = theme.textTheme.bodyMedium?.copyWith(
      fontFamily: kOpenHandMonospaceFontFamily,
      fontSize: 12.5,
      height: 1.4,
      color: colorScheme.onSurface,
    );
    final activeStyle = baseStyle?.copyWith(
      fontWeight: FontWeight.w700,
      color: colorScheme.primary,
      backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.42),
    );
    if (signature.parameters.isEmpty ||
        activeParameterIndex < 0 ||
        activeParameterIndex >= signature.parameters.length) {
      return <InlineSpan>[TextSpan(text: signature.label, style: baseStyle)];
    }
    final parameter = signature.parameters[activeParameterIndex];
    int? start = parameter.labelStart;
    int? end = parameter.labelEnd;
    if (!(parameter.hasExplicitOffsets &&
        start! >= 0 &&
        end! <= signature.label.length &&
        end > start)) {
      start = signature.label.indexOf(parameter.label);
      end = start < 0 ? null : start + parameter.label.length;
    }
    if (end == null || start < 0 || end > signature.label.length) {
      return <InlineSpan>[TextSpan(text: signature.label, style: baseStyle)];
    }
    return <InlineSpan>[
      if (start > 0)
        TextSpan(text: signature.label.substring(0, start), style: baseStyle),
      TextSpan(text: signature.label.substring(start, end), style: activeStyle),
      if (end < signature.label.length)
        TextSpan(text: signature.label.substring(end), style: baseStyle),
    ];
  }
}

class _SignatureParameterChip extends StatelessWidget {
  const _SignatureParameterChip({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final backgroundColor = active
        ? colorScheme.primaryContainer.withValues(alpha: 0.7)
        : colorScheme.surfaceContainerLow;
    final foregroundColor = active
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: kOpenHandPillBorderRadius,
        border: Border.all(
          color: active
              ? colorScheme.primary.withValues(alpha: 0.2)
              : colorScheme.outlineVariant.withValues(alpha: 0.2),
          width: 0.5,
        ),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: foregroundColor,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}

// Breadcrumb path bar — clickable segments showing directory contents
class _EditorBreadcrumb extends StatelessWidget {
  const _EditorBreadcrumb({required this.filePath, this.onNavigateToFile});

  final String filePath;
  final ValueChanged<String>? onNavigateToFile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final segments = p.split(filePath);
    final startIndex = segments.length > 4 ? segments.length - 4 : 0;
    final hasEllipsis = startIndex > 0;

    return Container(
      height: 30,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(
            _fileExplorerIcon(
              _FileNode(
                name: p.basename(filePath),
                path: filePath,
                isDirectory: false,
              ),
            ),
            size: 13,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          kOpenHandHGap6,
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasEllipsis) ...[
                    Text(
                      '...',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 12,
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.3,
                        ),
                      ),
                    ),
                  ],
                  for (var i = startIndex; i < segments.length; i++) ...[
                    if (i > startIndex)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 12,
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.3,
                          ),
                        ),
                      ),
                    _BreadcrumbSegment(
                      name: segments[i],
                      isLast: i == segments.length - 1,
                      targetPath: i == segments.length - 1
                          ? filePath
                          : p.joinAll(segments.sublist(0, i + 1)),
                      directoryPath: i == segments.length - 1
                          ? p.dirname(filePath)
                          : p.joinAll(segments.sublist(0, i + 1)),
                      onNavigateToFile: onNavigateToFile,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BreadcrumbSegment extends StatelessWidget {
  const _BreadcrumbSegment({
    required this.name,
    required this.isLast,
    required this.targetPath,
    required this.directoryPath,
    this.onNavigateToFile,
  });

  final String name;
  final bool isLast;
  final String targetPath;
  final String directoryPath;
  final ValueChanged<String>? onNavigateToFile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(kOpenHandRadius4),
      child: InkWell(
        borderRadius: BorderRadius.circular(kOpenHandRadius4),
        mouseCursor: SystemMouseCursors.click,
        hoverColor: colorScheme.primary.withValues(alpha: 0.06),
        onTap: () => _handleTap(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text(
            name,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 11,
              color: isLast
                  ? colorScheme.onSurface
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              fontWeight: isLast ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleTap(BuildContext context) async {
    await _showDirectoryPopup(
      context,
      directoryPath: directoryPath,
      initialValue: isLast ? targetPath : null,
    );
  }

  Future<void> _showDirectoryPopup(
    BuildContext context, {
    required String directoryPath,
    String? initialValue,
  }) async {
    String currentDirectoryPath = directoryPath;
    String? currentInitialValue = initialValue;
    while (context.mounted) {
      final dir = Directory(currentDirectoryPath);
      if (!await isDirectoryPath(dir.path, followLinks: true)) return;
      List<FileSystemEntity> entries;
      try {
        entries = (await listDirectoryBounded(
          dir,
          maxEntries: _kFileExplorerPopupEntryLimit,
        )).entries.toList(growable: false);
      } catch (_) {
        return;
      }
      entries.sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir != bIsDir) return aIsDir ? -1 : 1;
        return p
            .basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase());
      });
      final filtered = entries
          .where((e) => !p.basename(e.path).startsWith('.'))
          .take(80)
          .toList(growable: false);
      if (filtered.isEmpty || !context.mounted) return;

      final selected = await _showDirectoryEntriesMenu(
        context,
        entries: filtered,
        initialValue: currentInitialValue,
      );
      if (selected == null || !context.mounted) return;
      final selectedIsDirectory = filtered.any(
        (entry) => entry is Directory && p.equals(entry.path, selected),
      );
      if (selectedIsDirectory) {
        currentDirectoryPath = selected;
        currentInitialValue = null;
        continue;
      }
      onNavigateToFile?.call(selected);
      return;
    }
  }

  Future<String?> _showDirectoryEntriesMenu(
    BuildContext context, {
    required List<FileSystemEntity> entries,
    String? initialValue,
  }) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final target = context.findRenderObject() as RenderBox?;
    if (overlay == null || target == null) {
      return Future<String?>.value();
    }
    final topLeft = target.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight = target.localToGlobal(
      target.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    final anchorRect = Rect.fromPoints(topLeft, bottomRight);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return showAnimatedMenu<String>(
      context: context,
      position: RelativeRect.fromRect(anchorRect, Offset.zero & overlay.size),
      initialValue: initialValue,
      items: entries
          .map((entry) {
            final entryName = p.basename(entry.path);
            final isDir = entry is Directory;
            return PopupMenuItem<String>(
              value: entry.path,
              height: 36,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _fileExplorerIcon(
                      _FileNode(
                        name: entryName,
                        path: entry.path,
                        isDirectory: isDir,
                      ),
                    ),
                    size: 15,
                    color: isDir
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                  kOpenHandHGap8,
                  Expanded(
                    child: Text(
                      entryName,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: isDir ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            );
          })
          .toList()
          .cast<PopupMenuEntry<String>>(),
    );
  }
}

// Editor action button (save / close)
class _EditorActionButton extends StatelessWidget {
  const _EditorActionButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: kOpenHandPillBorderRadius,
        child: InkWell(
          borderRadius: kOpenHandPillBorderRadius,
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(icon, size: 17, color: color),
          ),
        ),
      ),
    );
  }
}

// Find bar icon button
class _FindBarButton extends StatelessWidget {
  const _FindBarButton({
    required this.icon,
    required this.tooltip,
    required this.colorScheme,
    this.onPressed,
    this.isActive = false,
  });

  final IconData icon;
  final String tooltip;
  final ColorScheme colorScheme;
  final VoidCallback? onPressed;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: isActive
            ? colorScheme.primaryContainer.withValues(alpha: 0.6)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(kOpenHandRadius4),
        child: InkWell(
          borderRadius: BorderRadius.circular(kOpenHandRadius4),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              icon,
              size: 16,
              color: onPressed == null
                  ? colorScheme.onSurfaceVariant.withValues(alpha: 0.3)
                  : isActive
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _EditorSymbol {
  const _EditorSymbol({
    required this.name,
    required this.kind,
    required this.filePath,
    required this.line,
    required this.column,
    required this.offset,
    required this.signature,
    required this.depth,
  });

  final String name;
  final String kind;
  final String filePath;
  final int line;
  final int column;
  final int offset;
  final String signature;
  final int depth;
}

class _EditorSymbolExtractionResult {
  const _EditorSymbolExtractionResult({
    required this.symbols,
    required this.truncated,
  });

  final List<_EditorSymbol> symbols;
  final bool truncated;
}

class _FoldableRegion {
  const _FoldableRegion({
    required this.startLine,
    required this.endLine,
    this.isComment = false,
  });

  /// 1-indexed start line of the foldable region.
  final int startLine;

  /// 1-indexed end line (inclusive) of the foldable region.
  final int endLine;

  /// Whether this region is a comment block.
  final bool isComment;
}

class _EditorDiagnostic {
  const _EditorDiagnostic({
    required this.severity,
    required this.code,
    required this.message,
    required this.line,
    required this.column,
    required this.endLine,
    required this.endColumn,
    required this.length,
  });

  final String severity;
  final String code;
  final String message;
  final int line;
  final int column;
  final int endLine;
  final int endColumn;
  final int length;

  bool get isError => severity == 'ERROR';
  bool get isWarning => severity == 'WARNING';
}

List<_EditorDiagnostic> _mapLspDiagnostics(List<AiLspDiagnostic> diagnostics) {
  return diagnostics
      .map(
        (item) => _EditorDiagnostic(
          severity: switch (item.severity) {
            1 => 'ERROR',
            2 => 'WARNING',
            _ => 'INFO',
          },
          code: item.code ?? item.source ?? 'lsp',
          message: item.message,
          line: item.range.start.line,
          column: item.range.start.character,
          endLine: item.range.end.line,
          endColumn: item.range.end.character,
          length: math.max(
            1,
            item.range.start.line == item.range.end.line
                ? item.range.end.character - item.range.start.character
                : 1,
          ),
        ),
      )
      .toList(growable: false);
}

class _EditorDiagnosticDecoratedRange {
  const _EditorDiagnosticDecoratedRange({
    required this.startOffset,
    required this.endOffset,
    required this.severityRank,
    required this.overlayStyle,
  });

  final int startOffset;
  final int endOffset;
  final int severityRank;
  final TextStyle overlayStyle;
}

class _EditorDiagnosticResolvedRange {
  const _EditorDiagnosticResolvedRange({
    required this.diagnostic,
    required this.startOffset,
    required this.endOffset,
  });

  final _EditorDiagnostic diagnostic;
  final int startOffset;
  final int endOffset;
}

class _EditorDiagnosticTooltipState {
  const _EditorDiagnosticTooltipState({
    required this.diagnostics,
    required this.anchorRect,
  });

  final List<_EditorDiagnostic> diagnostics;
  final Rect anchorRect;
}

class _EditorDecoratedInlineSpanResult {
  const _EditorDecoratedInlineSpanResult({
    required this.spans,
    required this.endOffset,
  });

  final List<InlineSpan> spans;
  final int endOffset;
}

int _editorDiagnosticSeverityRank(_EditorDiagnostic diagnostic) {
  if (diagnostic.isError) {
    return 3;
  }
  if (diagnostic.isWarning) {
    return 2;
  }
  return 1;
}

Color _editorDiagnosticUnderlineColor(_EditorDiagnostic diagnostic) {
  if (diagnostic.isError) {
    return const Color(0xFFD92D20);
  }
  if (diagnostic.isWarning) {
    return _kFileExplorerWarningColor;
  }
  return const Color(0xFF0B57D0);
}

TextStyle _editorDiagnosticOverlayStyle(_EditorDiagnostic diagnostic) {
  final accent = _editorDiagnosticUnderlineColor(diagnostic);
  return TextStyle(
    decoration: TextDecoration.underline,
    decorationColor: accent,
    decorationStyle: TextDecorationStyle.wavy,
    decorationThickness: diagnostic.isError ? 2 : 1.7,
    backgroundColor: accent.withValues(alpha: diagnostic.isError ? 0.08 : 0.06),
  );
}

List<_EditorDiagnosticResolvedRange> _buildEditorDiagnosticResolvedRanges(
  String text,
  List<_EditorDiagnostic> diagnostics,
) {
  final ranges = <_EditorDiagnosticResolvedRange>[];
  for (final diagnostic in diagnostics) {
    final startOffset = _editorOffsetForLineColumn(
      text,
      diagnostic.line,
      diagnostic.column,
    );
    var endOffset = _editorOffsetForLineColumn(
      text,
      diagnostic.endLine,
      diagnostic.endColumn,
    );
    if (endOffset <= startOffset) {
      endOffset = math.min(
        text.length,
        startOffset + math.max(1, diagnostic.length),
      );
    }
    if (endOffset <= startOffset) {
      continue;
    }
    ranges.add(
      _EditorDiagnosticResolvedRange(
        diagnostic: diagnostic,
        startOffset: startOffset,
        endOffset: endOffset,
      ),
    );
  }
  ranges.sort((left, right) {
    final byStart = left.startOffset.compareTo(right.startOffset);
    if (byStart != 0) {
      return byStart;
    }
    return _editorDiagnosticSeverityRank(
      right.diagnostic,
    ).compareTo(_editorDiagnosticSeverityRank(left.diagnostic));
  });
  return ranges;
}

List<_EditorDiagnosticDecoratedRange> _buildEditorDiagnosticDecoratedRanges(
  String text,
  List<_EditorDiagnostic> diagnostics,
) {
  return _buildEditorDiagnosticResolvedRanges(text, diagnostics)
      .map(
        (range) => _EditorDiagnosticDecoratedRange(
          startOffset: range.startOffset,
          endOffset: range.endOffset,
          severityRank: _editorDiagnosticSeverityRank(range.diagnostic),
          overlayStyle: _editorDiagnosticOverlayStyle(range.diagnostic),
        ),
      )
      .toList(growable: false);
}

TextSpan _applyEditorDiagnosticDecorationsToTextSpan(
  TextSpan span,
  String text,
  List<_EditorDiagnostic> diagnostics,
) {
  final ranges = _buildEditorDiagnosticDecoratedRanges(text, diagnostics);
  if (ranges.isEmpty) {
    return span;
  }
  final result = _decorateEditorInlineSpan(span, ranges, 0);
  if (result.spans.length == 1 && result.spans.first is TextSpan) {
    return result.spans.first as TextSpan;
  }
  return TextSpan(style: span.style, children: result.spans);
}

_EditorDecoratedInlineSpanResult _decorateEditorInlineSpan(
  InlineSpan span,
  List<_EditorDiagnosticDecoratedRange> ranges,
  int startOffset,
) {
  if (span is! TextSpan) {
    return _EditorDecoratedInlineSpanResult(
      spans: <InlineSpan>[span],
      endOffset: startOffset,
    );
  }
  if (span.text != null) {
    return _decorateEditorLeafTextSpan(span, ranges, startOffset);
  }
  final children = <InlineSpan>[];
  var cursor = startOffset;
  for (final child in span.children ?? const <InlineSpan>[]) {
    final childResult = _decorateEditorInlineSpan(child, ranges, cursor);
    children.addAll(childResult.spans);
    cursor = childResult.endOffset;
  }
  return _EditorDecoratedInlineSpanResult(
    spans: <InlineSpan>[TextSpan(style: span.style, children: children)],
    endOffset: cursor,
  );
}

_EditorDecoratedInlineSpanResult _decorateEditorLeafTextSpan(
  TextSpan span,
  List<_EditorDiagnosticDecoratedRange> ranges,
  int startOffset,
) {
  final leafText = span.text ?? '';
  final endOffset = startOffset + leafText.length;
  if (leafText.isEmpty) {
    return _EditorDecoratedInlineSpanResult(
      spans: <InlineSpan>[span],
      endOffset: endOffset,
    );
  }
  final relevantRanges = ranges
      .where((range) {
        return range.endOffset > startOffset && range.startOffset < endOffset;
      })
      .toList(growable: false);
  if (relevantRanges.isEmpty) {
    return _EditorDecoratedInlineSpanResult(
      spans: <InlineSpan>[span],
      endOffset: endOffset,
    );
  }

  final spans = <InlineSpan>[];
  var localOffset = 0;
  while (localOffset < leafText.length) {
    _EditorDiagnosticDecoratedRange? activeRange;
    var nextBoundary = leafText.length;
    for (final range in relevantRanges) {
      final localRangeStart = math.max(0, range.startOffset - startOffset);
      final localRangeEnd = math.min(
        leafText.length,
        range.endOffset - startOffset,
      );
      if (localRangeEnd <= localOffset) {
        continue;
      }
      if (localRangeStart > localOffset) {
        nextBoundary = math.min(nextBoundary, localRangeStart);
        continue;
      }
      if (localOffset >= localRangeStart && localOffset < localRangeEnd) {
        if (activeRange == null ||
            range.severityRank > activeRange.severityRank ||
            (range.severityRank == activeRange.severityRank &&
                range.endOffset > activeRange.endOffset)) {
          activeRange = range;
        }
        nextBoundary = math.min(nextBoundary, localRangeEnd);
      }
    }
    if (nextBoundary <= localOffset) {
      nextBoundary = localOffset + 1;
    }
    final segmentText = leafText.substring(localOffset, nextBoundary);
    final segmentStyle = activeRange == null
        ? span.style
        : (span.style?.merge(activeRange.overlayStyle) ??
              activeRange.overlayStyle);
    spans.add(TextSpan(text: segmentText, style: segmentStyle));
    localOffset = nextBoundary;
  }

  return _EditorDecoratedInlineSpanResult(spans: spans, endOffset: endOffset);
}

class _EditorPreviewLine {
  const _EditorPreviewLine({
    required this.lineNumber,
    required this.text,
    required this.isHighlight,
  });

  final int lineNumber;
  final String text;
  final bool isHighlight;
}

class _EditorLocationPreview {
  const _EditorLocationPreview({required this.lines});

  final List<_EditorPreviewLine> lines;
}

class _PreparedWorkspaceEdit {
  const _PreparedWorkspaceEdit({required this.edit, required this.files});

  final AiLspWorkspaceEdit edit;
  final List<_PreparedWorkspaceEditFile> files;
}

class _PreparedWorkspaceEditFile {
  const _PreparedWorkspaceEditFile({
    required this.filePath,
    required this.updatedText,
    required this.editCount,
    required this.diffLines,
    required this.additionCount,
    required this.deletionCount,
    required this.isTruncated,
  });

  final String filePath;
  final String updatedText;
  final int editCount;
  final List<String> diffLines;
  final int additionCount;
  final int deletionCount;
  final bool isTruncated;
}

class _PendingWorkspaceEditPreviewContext {
  _PendingWorkspaceEditPreviewContext({required this.title, this.description});

  final String title;
  final String? description;
  final List<String> appliedSummaries = <String>[];
  bool declined = false;
}

class _WorkspaceEditStatChip extends StatelessWidget {
  const _WorkspaceEditStatChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: kOpenHandPillBorderRadius,
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

class _WorkspaceEditDiffLine extends StatelessWidget {
  const _WorkspaceEditDiffLine({required this.line, required this.colorScheme});

  final String line;
  final ColorScheme colorScheme;

static const _addedBg = Color(0xFFE6F4E6);
  static const _removedBg = Color(0xFFF7E6E6);
  static const _hunkBg = Color(0xFFE8EEF8);
  static const _addedBgDark = Color(0xFF1A3D1A);
  static const _removedBgDark = Color(0xFF3D1A1A);
  static const _hunkBgDark = Color(0xFF1A2B3D);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Color? background;
    Color foreground;
    FontWeight fontWeight = FontWeight.normal;

    if (line.startsWith('+++') || line.startsWith('---')) {
      foreground = colorScheme.secondary;
      fontWeight = FontWeight.w700;
    } else if (line.startsWith('+')) {
      background = isDark ? _addedBgDark.withValues(alpha: 0.55) : _addedBg;
      foreground = isDark ? const Color(0xFF81C784) : _kFileExplorerSuccessColor;
    } else if (line.startsWith('-')) {
      background = isDark ? _removedBgDark.withValues(alpha: 0.55) : _removedBg;
      foreground = isDark ? const Color(0xFFE57373) : colorScheme.error;
    } else if (line.startsWith('@@')) {
      background = isDark ? _hunkBgDark.withValues(alpha: 0.55) : _hunkBg;
      foreground = isDark ? const Color(0xFF90CAF9) : colorScheme.primary;
      fontWeight = FontWeight.w700;
    } else {
      foreground = colorScheme.onSurface.withValues(alpha: 0.82);
    }

    return Container(
      width: double.infinity,
      color: background,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Text(
        line.isEmpty ? ' ' : line,
        style: TextStyle(
          color: foreground,
          fontWeight: fontWeight,
          fontSize: 11.8,
          height: 1.4,
          fontFamily: kOpenHandMonospaceFontFamily,
        ),
      ),
    );
  }
}

class _EditorSymbolPattern {
  const _EditorSymbolPattern(this.regExp, this.kind);

  final RegExp regExp;
  final String kind;
}

const Set<String> _editorIgnoredSymbolNames = <String>{
  'if',
  'for',
  'while',
  'switch',
  'catch',
  'return',
  'throw',
  'new',
  'else',
  'do',
};

/// 多语言符号表共享的 pattern 实例，避免重复编译同一正则。
final _EditorSymbolPattern _abstractClassSymbolPattern = _EditorSymbolPattern(
  RegExp(r'^\s*(?:abstract\s+)?class\s+([A-Za-z_][\w$]*)\b'),
  'class',
);
final _EditorSymbolPattern _plainEnumSymbolPattern = _EditorSymbolPattern(
  RegExp(r'^\s*enum\s+([A-Za-z_][\w$]*)\b'),
  'enum',
);
final _EditorSymbolPattern _pythonDefSymbolPattern = _EditorSymbolPattern(
  RegExp(r'^\s*(?:async\s+)?def\s+([A-Za-z_][\w$]*)\s*\('),
  'function',
);
final _EditorSymbolPattern _goFuncSymbolPattern = _EditorSymbolPattern(
  RegExp(r'^\s*func\s+(?:\([^)]+\)\s*)?([A-Za-z_][\w$]*)\s*\('),
  'function',
);

final List<_EditorSymbolPattern> _genericSymbolPatterns =
    <_EditorSymbolPattern>[
      _abstractClassSymbolPattern,
      _EditorSymbolPattern(
        RegExp(r'^\s*(?:abstract\s+)?interface\s+([A-Za-z_][\w$]*)\b'),
        'interface',
      ),
      _plainEnumSymbolPattern,
      _pythonDefSymbolPattern,
      _goFuncSymbolPattern,
      _EditorSymbolPattern(
        RegExp(
          r'^\s*(?:export\s+)?(?:async\s+)?function\s+([A-Za-z_][\w$]*)\s*\(',
        ),
        'function',
      ),
    ];

final List<_EditorSymbolPattern> _dartSymbolPatterns = <_EditorSymbolPattern>[
  _abstractClassSymbolPattern,
  _EditorSymbolPattern(RegExp(r'^\s*mixin\s+([A-Za-z_][\w$]*)\b'), 'mixin'),
  _plainEnumSymbolPattern,
  _EditorSymbolPattern(
    RegExp(r'^\s*extension\s+([A-Za-z_][\w$]*)\s+on\b'),
    'extension',
  ),
  _EditorSymbolPattern(RegExp(r'^\s*typedef\s+([A-Za-z_][\w$]*)\b'), 'typedef'),
  _EditorSymbolPattern(
    RegExp(
      r'^\s*(?:static\s+)?(?:[A-Za-z_<>,?\[\]\.]+\s+){0,3}([A-Za-z_][\w$]*)\s*\([^;]*\)\s*(?:\{|=>)',
    ),
    'method',
  ),
];

final List<_EditorSymbolPattern>
_javascriptSymbolPatterns = <_EditorSymbolPattern>[
  _EditorSymbolPattern(
    RegExp(r'^\s*(?:export\s+)?(?:default\s+)?class\s+([A-Za-z_][\w$]*)\b'),
    'class',
  ),
  _EditorSymbolPattern(
    RegExp(r'^\s*(?:export\s+)?interface\s+([A-Za-z_][\w$]*)\b'),
    'interface',
  ),
  _EditorSymbolPattern(
    RegExp(r'^\s*(?:export\s+)?type\s+([A-Za-z_][\w$]*)\b'),
    'type',
  ),
  _EditorSymbolPattern(
    RegExp(r'^\s*(?:export\s+)?enum\s+([A-Za-z_][\w$]*)\b'),
    'enum',
  ),
  _EditorSymbolPattern(
    RegExp(r'^\s*(?:export\s+)?(?:async\s+)?function\s+([A-Za-z_][\w$]*)\s*\('),
    'function',
  ),
  _EditorSymbolPattern(
    RegExp(
      r'^\s*(?:export\s+)?(?:const|let|var)\s+([A-Za-z_][\w$]*)\s*=\s*(?:async\s*)?(?:\([^)]*\)|[A-Za-z_][\w$]*)\s*=>',
    ),
    'function',
  ),
  _EditorSymbolPattern(
    RegExp(
      r'^\s*(?:public\s+|private\s+|protected\s+|static\s+|async\s+|readonly\s+|override\s+|get\s+|set\s+)*([A-Za-z_][\w$]*)\s*\([^;]*\)\s*\{',
    ),
    'method',
  ),
];

final List<_EditorSymbolPattern> _pythonSymbolPatterns = <_EditorSymbolPattern>[
  _EditorSymbolPattern(RegExp(r'^\s*class\s+([A-Za-z_][\w$]*)\b'), 'class'),
  _pythonDefSymbolPattern,
];

final List<_EditorSymbolPattern> _goSymbolPatterns = <_EditorSymbolPattern>[
  _EditorSymbolPattern(
    RegExp(r'^\s*type\s+([A-Za-z_][\w$]*)\s+(?:struct|interface)\b'),
    'type',
  ),
  _goFuncSymbolPattern,
];

final List<_EditorSymbolPattern>
_javaLikeSymbolPatterns = <_EditorSymbolPattern>[
  _EditorSymbolPattern(
    RegExp(
      r'^\s*(?:public\s+|private\s+|protected\s+|internal\s+|open\s+|abstract\s+|final\s+|sealed\s+|data\s+|static\s+)*class\s+([A-Za-z_][\w$]*)\b',
    ),
    'class',
  ),
  _EditorSymbolPattern(
    RegExp(
      r'^\s*(?:public\s+|private\s+|protected\s+|internal\s+|open\s+|sealed\s+|static\s+)*interface\s+([A-Za-z_][\w$]*)\b',
    ),
    'interface',
  ),
  _EditorSymbolPattern(
    RegExp(
      r'^\s*(?:public\s+|private\s+|protected\s+|internal\s+|static\s+)*enum\s+([A-Za-z_][\w$]*)\b',
    ),
    'enum',
  ),
  _EditorSymbolPattern(
    RegExp(
      r'^\s*(?:public\s+|private\s+|protected\s+|internal\s+|open\s+|final\s+|abstract\s+|override\s+|static\s+|suspend\s+|operator\s+|inline\s+|async\s+)*(?:[A-Za-z_<>,?\[\]\.]+\s+){0,3}([A-Za-z_][\w$]*)\s*\([^;]*\)\s*\{?',
    ),
    'method',
  ),
];

List<_EditorSymbolPattern> _symbolPatternsForLanguage(String language) {
  return switch (language) {
    'dart' => _dartSymbolPatterns,
    'javascript' || 'typescript' => _javascriptSymbolPatterns,
    'python' => _pythonSymbolPatterns,
    'go' => _goSymbolPatterns,
    'java' ||
    'kotlin' ||
    'csharp' ||
    'swift' ||
    'cpp' => _javaLikeSymbolPatterns,
    _ => _genericSymbolPatterns,
  };
}

bool _isEditorCommentLine(String trimmedLine) {
  return trimmedLine.startsWith('//') ||
      trimmedLine.startsWith('#') ||
      trimmedLine.startsWith('*') ||
      trimmedLine.startsWith('/*') ||
      trimmedLine.startsWith('<!--') ||
      trimmedLine.startsWith('--');
}

int _editorOffsetForLineColumn(String text, int line, int column) {
  final targetLine = math.max(1, line);
  final targetColumn = math.max(1, column);
  var currentLine = 1;
  var currentColumn = 1;
  for (var index = 0; index < text.length; index++) {
    if (currentLine == targetLine && currentColumn == targetColumn) {
      return index;
    }
    if (text.codeUnitAt(index) == 10) {
      if (currentLine == targetLine) {
        return index;
      }
      currentLine += 1;
      currentColumn = 1;
    } else {
      currentColumn += 1;
    }
  }
  return text.length;
}

String _editorSymbolKindFromLsp(int kind) {
  return switch (kind) {
    5 => 'class',
    6 => 'method',
    7 || 8 => 'field',
    9 => 'constructor',
    10 => 'enum',
    11 => 'interface',
    12 => 'function',
    13 || 14 => 'variable',
    22 => 'enumMember',
    23 => 'struct',
    26 => 'type',
    _ => 'symbol',
  };
}

_EditorSymbolExtractionResult _extractEditorSymbolsFromLsp({
  required String filePath,
  required List<AiLspDocumentSymbol> documentSymbols,
  required String text,
}) {
  const maxSymbols = 240;
  final symbols = <_EditorSymbol>[];
  var truncated = false;

  void visit(AiLspDocumentSymbol symbol, int depth) {
    if (symbols.length >= maxSymbols) {
      truncated = true;
      return;
    }
    final name = symbol.name.trim();
    if (name.isNotEmpty) {
      final kind = _editorSymbolKindFromLsp(symbol.kind);
      final detail = symbol.detail?.trim();
      symbols.add(
        _EditorSymbol(
          name: name,
          kind: kind,
          filePath: filePath,
          line: symbol.range.start.line,
          column: symbol.range.start.character,
          offset: _editorOffsetForLineColumn(
            text,
            symbol.range.start.line,
            symbol.range.start.character,
          ),
          signature: detail == null || detail.isEmpty ? kind : detail,
          depth: depth,
        ),
      );
    }
    if (symbols.length >= maxSymbols) {
      truncated = true;
      return;
    }
    for (final child in symbol.children) {
      visit(child, depth + 1);
      if (truncated) {
        return;
      }
    }
  }

  for (final symbol in documentSymbols) {
    visit(symbol, 0);
    if (truncated) {
      break;
    }
  }

  return _EditorSymbolExtractionResult(
    symbols: List<_EditorSymbol>.unmodifiable(symbols),
    truncated: truncated,
  );
}

_EditorSymbolExtractionResult _extractEditorSymbolsFromWorkspaceLsp({
  required List<AiLspWorkspaceSymbol> workspaceSymbols,
}) {
  const maxSymbols = 240;
  final symbols = <_EditorSymbol>[];
  var truncated = false;

  for (final symbol in workspaceSymbols) {
    if (symbols.length >= maxSymbols) {
      truncated = true;
      break;
    }
    final detail = symbol.detail?.trim();
    final containerName = symbol.containerName?.trim();
    symbols.add(
      _EditorSymbol(
        name: symbol.name,
        kind: _editorSymbolKindFromLsp(symbol.kind),
        filePath: symbol.location.filePath,
        line: symbol.location.line,
        column: symbol.location.character,
        offset: 0,
        signature: detail?.isNotEmpty == true
            ? detail!
            : containerName?.isNotEmpty == true
            ? containerName!
            : _editorSymbolKindFromLsp(symbol.kind),
        depth: 0,
      ),
    );
  }

  return _EditorSymbolExtractionResult(
    symbols: List<_EditorSymbol>.unmodifiable(symbols),
    truncated: truncated,
  );
}

_EditorSymbolExtractionResult _extractEditorSymbols({
  required String filePath,
  required String text,
  required String language,
}) {
  const maxSymbols = 240;
  const maxLines = 5000;
  const maxTextLength = 320 * kBytesPerKiB;

  final allLines = const LineSplitter().convert(text);
  final truncated = allLines.length > maxLines || text.length > maxTextLength;
  final lineCount = truncated
      ? math.min(allLines.length, maxLines)
      : allLines.length;
  final lines = allLines.take(lineCount).toList(growable: false);
  final patterns = _symbolPatternsForLanguage(language);
  final symbols = <_EditorSymbol>[];
  var offset = 0;

  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final trimmed = line.trimLeft();
    if (trimmed.isEmpty || _isEditorCommentLine(trimmed)) {
      offset += line.length + 1;
      continue;
    }
    for (final pattern in patterns) {
      final match = pattern.regExp.firstMatch(line);
      if (match == null) {
        continue;
      }
      final name = match.group(1)?.trim() ?? '';
      if (name.isEmpty || _editorIgnoredSymbolNames.contains(name)) {
        continue;
      }
      symbols.add(
        _EditorSymbol(
          name: name,
          kind: pattern.kind,
          filePath: filePath,
          line: index + 1,
          column: match.start + 1,
          offset: offset + match.start,
          signature: trimmed,
          depth: 0,
        ),
      );
      break;
    }
    offset += line.length + 1;
    if (symbols.length >= maxSymbols) {
      return _EditorSymbolExtractionResult(
        symbols: List<_EditorSymbol>.unmodifiable(symbols),
        truncated: true,
      );
    }
  }

  return _EditorSymbolExtractionResult(
    symbols: List<_EditorSymbol>.unmodifiable(symbols),
    truncated: truncated,
  );
}

// Syntax-highlighted editable editor widget
const double _editorFontSizeDefault = 13.0;
const double _editorFontSizeMin = 8.0;
const double _editorFontSizeMax = 32.0;
const double _editorLineHeight = 1.55;
const double _editorMaxEstimatedContentWidth = 32000.0;

TextStyle _editorBaseStyleForSize(double fontSize) => TextStyle(
  fontFamily: kOpenHandMonospaceFontFamily,
  fontSize: fontSize,
  height: _editorLineHeight,
  letterSpacing: 0,
);

double _measureEditorLineNumberTextWidth({
  required int lineCount,
  required double fontSize,
}) {
  final digits = math.max(1, '$lineCount'.length);
  final painter = TextPainter(
    text: TextSpan(
      text: List<String>.filled(digits, '8').join(),
      style: TextStyle(
        fontFamily: kOpenHandMonospaceFontFamily,
        fontSize: fontSize,
        height: _editorLineHeight,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  return painter.width.ceilToDouble();
}

double _editorEditableGutterWidth({
  required int lineCount,
  required double fontSize,
  required bool hasDiagnostics,
}) {
  final basePadding = hasDiagnostics ? 62.0 : 40.0;
  final minimumWidth = hasDiagnostics ? 88.0 : 60.0;
  return math.max(
    minimumWidth,
    _measureEditorLineNumberTextWidth(
          lineCount: lineCount,
          fontSize: fontSize,
        ) +
        basePadding,
  );
}

double _editorPreviewGutterWidth({
  required int lineCount,
  required double fontSize,
}) {
  return math.max(
    56.0,
    _measureEditorLineNumberTextWidth(
          lineCount: lineCount,
          fontSize: fontSize,
        ) +
        32.0,
  );
}

/// Handles Cmd/Ctrl + scroll‑wheel zoom and Cmd/Ctrl + +/-/0 keyboard zoom
/// for the code editor, similar to IntelliJ IDEA and VS Code.
class _EditorZoomWrapper extends StatefulWidget {
  const _EditorZoomWrapper({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onZoomReset,
    required this.onZoomByScale,
    required this.child,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomReset;
  final ValueChanged<double> onZoomByScale;
  final Widget child;

  @override
  State<_EditorZoomWrapper> createState() => _EditorZoomWrapperState();
}

class _EditorZoomWrapperState extends State<_EditorZoomWrapper> {
  // For smooth pinch-to-zoom on trackpad/touch
  double? _lastPanZoomScale;

  void _handlePanZoomStart(PointerPanZoomStartEvent event) {
    _lastPanZoomScale = 1.0;
  }

  void _handlePanZoomUpdate(PointerPanZoomUpdateEvent event) {
    final previousScale = _lastPanZoomScale ?? 1.0;
    final currentScale = event.scale;
    _lastPanZoomScale = currentScale;

    // Calculate incremental scale delta and apply directly for smooth zoom
    final scaleDelta = currentScale / previousScale;

    // Only process if there's meaningful scale change (filters out noise)
    if ((scaleDelta - 1.0).abs() > 0.001) {
      widget.onZoomByScale(scaleDelta);
    }
  }

  void _handlePanZoomEnd(PointerPanZoomEndEvent event) {
    _lastPanZoomScale = null;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final meta =
            HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed;
        if (!meta) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.equal ||
            event.logicalKey == LogicalKeyboardKey.numpadAdd) {
          widget.onZoomIn();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.minus ||
            event.logicalKey == LogicalKeyboardKey.numpadSubtract) {
          widget.onZoomOut();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.digit0 ||
            event.logicalKey == LogicalKeyboardKey.numpad0) {
          widget.onZoomReset();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            final meta =
                HardwareKeyboard.instance.isMetaPressed ||
                HardwareKeyboard.instance.isControlPressed;
            if (meta) {
              // Convert scroll delta to scale factor for smooth zoom
              // Sensitivity: 120 scroll units = ~10% zoom
              const scrollSensitivity = 0.001;
              final scaleFactor =
                  1.0 - (event.scrollDelta.dy * scrollSensitivity);
              widget.onZoomByScale(scaleFactor.clamp(0.9, 1.1));
            }
          } else if (event is PointerScaleEvent) {
            // Trackpad pinch-to-zoom: apply scale directly for smooth experience
            widget.onZoomByScale(event.scale);
          }
        },
        onPointerPanZoomStart: _handlePanZoomStart,
        onPointerPanZoomUpdate: _handlePanZoomUpdate,
        onPointerPanZoomEnd: _handlePanZoomEnd,
        child: widget.child,
      ),
    );
  }
}

class _HighlightingTextController extends TextEditingController {
  _HighlightingTextController({String? initialText, this.language})
    : _lastMeasuredText = initialText ?? '',
      super(text: initialText) {
    _updateDocumentMetrics(initialText ?? '');
  }

  _CodeSyntaxHighlighter? highlighter;
  String? language;
  static const int _plainTextCacheHash = -1;

  /// When true, override the normal highlighting size limits and use deferred
  /// highlighting so that large files opened via "Open Full Editor" still get
  /// syntax colouring without blocking the initial render.
  bool forceFullEditorHighlighting = false;

  /// Tracks whether the initial highlight for a forced-open large file has
  /// been performed.  After the first successful highlight, subsequent edits
  /// are deferred to keep typing smooth.
  bool _forceHighlightInitialDone = false;

  // ── Highlight cache ──
  TextSpan? _cachedSpan;
  String? _lastText;
  int? _lastHighlighterHash;
  int? _lastDiagnosticsRevision;
  Timer? _debounceTimer;
  String _lastMeasuredText;
  List<String>? _cachedLines;
  List<_EditorDiagnostic> _diagnostics = const <_EditorDiagnostic>[];
  int _diagnosticsRevision = 0;
  int _textRevision = 0;
  int _lineCount = 1;
  int _longestLineLength = 0;

  // ── Line offset index for O(log n) lookups ──
  /// Stores the character offset where each line starts (index 0 = line 0 = 0).
  List<int> _lineOffsets = const <int>[0];

  // ── Viewport-based highlighting for very large files ──
  /// Number of lines to highlight around the cursor for viewport mode.
  static const _viewportHighlightLines = 400;

  /// Buffer lines above/below the visible window so scrolling feels seamless.
  static const _viewportBufferLines = 100;

  /// Cached viewport range to avoid re-highlighting when cursor stays nearby.
  int _viewportStartLine = -1;
  int _viewportEndLine = -1;

  /// Cached cursor line for the viewport cache-hit check (avoids re-scanning).
  int _cachedCursorLine = 0;
  List<_FoldableRegion> _foldedLineRanges = const <_FoldableRegion>[];

  set foldedLineRanges(List<_FoldableRegion> value) {
    _foldedLineRanges = List<_FoldableRegion>.unmodifiable(value);
    invalidateHighlightCache();
    notifyListeners();
  }

  List<_FoldableRegion> get foldedLineRanges => _foldedLineRanges;

  /// Beyond this length, skip syntax highlighting entirely.
  static const _maxHighlightLength = 96 * kBytesPerKiB;

  /// Beyond this line count, skip syntax highlighting entirely.
  static const _maxHighlightLines = 1800;

  /// Absolute hard ceiling for forced full-editor highlighting.
  /// Files exceeding this are too large even for deferred parsing.
  static const _absoluteMaxHighlightLength = 512 * kBytesPerKiB;
  static const _absoluteMaxHighlightLines = 12000;

  /// Beyond this size, defer the expensive initial highlight parse.
  static const _deferHighlightLength = 36 * kBytesPerKiB;
  static const _deferHighlightLines = 900;

  /// Large interactive editor features become expensive well before the
  /// virtualized preview threshold.
  static const _reducedInteractivityLength = 80 * kBytesPerKiB;
  static const _reducedInteractivityLines = 1800;
  static const _reducedInteractivityLineLength = 1600;

  /// For very large documents, keep completion explicit instead of firing on
  /// every edit.
  static const _explicitCompletionLength = 128 * kBytesPerKiB;
  static const _explicitCompletionLines = 2800;
  static const _explicitCompletionLineLength = 2200;

  /// Measuring wrapped line heights requires a full-document layout pass.
  static const _preciseWrapMeasureLength = 72 * kBytesPerKiB;
  static const _preciseWrapMeasureLines = 1400;

  /// Large documents switch to a virtualized preview by default.
  static const _previewLength = 160 * kBytesPerKiB;
  static const _previewLines = 3200;

  int get lineCount => _lineCount;

  int get longestLineLength => _longestLineLength;

  int get textRevision => _textRevision;

  bool get useVirtualizedPreview =>
      text.length >= _previewLength || _lineCount >= _previewLines;

  bool get useReducedInteractionMode =>
      text.length >= _reducedInteractivityLength ||
      _lineCount >= _reducedInteractivityLines ||
      _longestLineLength >= _reducedInteractivityLineLength;

  bool get preferExplicitCompletion =>
      text.length >= _explicitCompletionLength ||
      _lineCount >= _explicitCompletionLines ||
      _longestLineLength >= _explicitCompletionLineLength;

  bool get supportsPreciseWrappedLineHeights =>
      text.length < _preciseWrapMeasureLength &&
      _lineCount < _preciseWrapMeasureLines &&
      _longestLineLength < _reducedInteractivityLineLength;

  bool get supportsDiagnosticHoverTooltips => !useReducedInteractionMode;

  List<String> get previewLines {
    _cachedLines ??= () {
      final lines = const LineSplitter().convert(text);
      return lines.isEmpty
          ? const <String>['']
          : List<String>.unmodifiable(lines);
    }();
    return _cachedLines!;
  }

  /// Whether the file is so large that even forced full-editor mode must use
  /// viewport-based highlighting (only the visible region is highlighted).
  bool get _useViewportHighlighting {
    if (!forceFullEditorHighlighting) return false;
    return text.length > _absoluteMaxHighlightLength ||
        _lineCount > _absoluteMaxHighlightLines;
  }

  bool get _disableHighlighting {
    if (forceFullEditorHighlighting) {
      // Never fully disable when force is on — very large files use viewport
      // highlighting instead.
      return false;
    }
    return text.length > _maxHighlightLength || _lineCount > _maxHighlightLines;
  }

  bool get _deferHighlighting {
    if (_disableHighlighting) return false;
    if (forceFullEditorHighlighting) {
      // For very large files (>100 KB / >2500 lines), always defer — even the
      // first render — to prevent a multi-second UI freeze while the highlight
      // parser runs synchronously on the main isolate.
      if (text.length > 100 * kBytesPerKiB || _lineCount > 2500) {
        return true;
      }
      // Smaller forced-open files: highlight synchronously on the first render
      // so colours appear immediately, then defer subsequent edits.
      return _forceHighlightInitialDone;
    }
    return text.length > _deferHighlightLength ||
        _lineCount > _deferHighlightLines;
  }

  set diagnostics(List<_EditorDiagnostic> value) {
    if (identical(_diagnostics, value)) {
      return;
    }
    _diagnostics = value.isEmpty
        ? const <_EditorDiagnostic>[]
        : List<_EditorDiagnostic>.unmodifiable(value);
    _diagnosticsRevision += 1;
    invalidateHighlightCache();
  }

  @override
  set value(TextEditingValue newValue) {
    final previousText = value.text;
    super.value = newValue;
    // Update cached cursor line for viewport highlighting (cheap binary search).
    if (_useViewportHighlighting) {
      _cachedCursorLine = _lineIndexForOffset(
        newValue.selection.baseOffset.clamp(0, newValue.text.length),
      );
    }
    if (newValue.text == previousText && newValue.text == _lastMeasuredText) {
      return;
    }
    _handleTextChanged(newValue.text);
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final hlHash = highlighter == null
        ? _plainTextCacheHash
        : identityHashCode(highlighter);
    final deferHighlighting = highlighter != null && _deferHighlighting;
    if (_cachedSpan != null &&
        _lastText == text &&
        (_lastHighlighterHash == hlHash ||
            (deferHighlighting &&
                _lastHighlighterHash == _plainTextCacheHash)) &&
        _lastDiagnosticsRevision == _diagnosticsRevision) {
      // For viewport-mode highlighting, still check if cursor has moved
      // outside the previously highlighted window so we can re-highlight.
      if (_useViewportHighlighting) {
        _cachedCursorLine = _lineIndexForOffset(
          selection.baseOffset.clamp(0, text.length),
        );
        if (_cachedCursorLine < _viewportStartLine + _viewportBufferLines ||
            _cachedCursorLine > _viewportEndLine - _viewportBufferLines) {
          // Cursor moved outside buffer — fall through to re-schedule.
        } else {
          return _cachedSpan!;
        }
      } else {
        return _cachedSpan!;
      }
    }
    if (highlighter == null || _disableHighlighting) {
      return _cachePlainTextSpan(style);
    }
    // ── Viewport-based highlighting for very large forced files ──
    if (_useViewportHighlighting) {
      _scheduleViewportHighlight(style);
      return _cachedSpan ?? _cachePlainTextSpan(style);
    }
    if (deferHighlighting) {
      _scheduleDelayedHighlight();
      return _cachePlainTextSpan(style);
    }
    _rebuildHighlight();
    if (forceFullEditorHighlighting) {
      _forceHighlightInitialDone = true;
    }
    return _cachedSpan ?? _cachePlainTextSpan(style);
  }

  void _rebuildHighlight() {
    if (highlighter == null) return;
    try {
      final highlighted = highlighter!.build(
        text,
        language: language,
        allowAutoDetection: language == null,
      );
      _cachedSpan = _diagnostics.isEmpty
          ? highlighted
          : _applyEditorDiagnosticDecorationsToTextSpan(
              highlighted,
              text,
              _diagnostics,
            );
      _lastText = text;
      _lastHighlighterHash = identityHashCode(highlighter);
      _lastDiagnosticsRevision = _diagnosticsRevision;
    } catch (error, stack) {
      silentLog('file_explorer', '重建完整高亮', error, stack);
    }
  }

  TextSpan _cachePlainTextSpan(TextStyle? style) {
    final plain = TextSpan(text: text, style: style);
    _cachedSpan = _diagnostics.isEmpty
        ? plain
        : _applyEditorDiagnosticDecorationsToTextSpan(
            plain,
            text,
            _diagnostics,
          );
    _lastText = text;
    _lastHighlighterHash = _plainTextCacheHash;
    _lastDiagnosticsRevision = _diagnosticsRevision;
    return _cachedSpan!;
  }

  void _scheduleDelayedHighlight() {
    _debounceTimer?.cancel();
    // Use a longer delay for very large files to avoid excessive CPU while
    // the user is actively typing.
    final delay = forceFullEditorHighlighting && _lineCount > 3000
        ? const Duration(milliseconds: 600)
        : const Duration(milliseconds: 350);
    _debounceTimer = startSafeTimer(delay, () {
      if (highlighter == null || _disableHighlighting) return;
      _rebuildHighlight();
      notifyListeners();
    });
  }

  void _handleTextChanged(String currentText) {
    _lastMeasuredText = currentText;
    _textRevision += 1;
    _cachedLines = null;
    _updateDocumentMetrics(currentText);
    invalidateHighlightCache();
  }

  void _updateDocumentMetrics(String currentText) {
    var computedLineCount = 1;
    var currentLineLength = 0;
    var longestLineLength = 0;
    // Build line-offset index in a single pass.
    final offsets = <int>[0];
    final codeUnits = currentText.codeUnits;
    for (var i = 0; i < codeUnits.length; i++) {
      final codeUnit = codeUnits[i];
      if (codeUnit == 10) {
        computedLineCount += 1;
        if (currentLineLength > longestLineLength) {
          longestLineLength = currentLineLength;
        }
        currentLineLength = 0;
        offsets.add(i + 1);
        continue;
      }
      if (codeUnit != 13) {
        currentLineLength += 1;
      }
    }
    if (currentLineLength > longestLineLength) {
      longestLineLength = currentLineLength;
    }
    _lineCount = math.max(1, computedLineCount);
    _longestLineLength = longestLineLength;
    _lineOffsets = offsets;
  }

  void invalidateHighlightCache() {
    _debounceTimer?.cancel();
    _cachedSpan = null;
    _lastText = null;
    _lastHighlighterHash = null;
    _lastDiagnosticsRevision = null;
    _viewportStartLine = -1;
    _viewportEndLine = -1;
  }

  // ── Viewport highlighting helpers ──

  /// Returns the line index (0-based) for a given character [offset].
  /// Uses a binary search over the pre-built [_lineOffsets] index (O(log n)).
  int _lineIndexForOffset(int offset) {
    if (offset <= 0) return 0;
    final clamped = offset.clamp(0, text.length);
    // Binary search: find the last entry in _lineOffsets that is <= clamped.
    var lo = 0;
    var hi = _lineOffsets.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_lineOffsets[mid] <= clamped) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// Returns the character offset where [lineIndex] (0-based) starts.
  /// Uses the pre-built [_lineOffsets] index (O(1)).
  int _offsetForLine(int lineIndex) {
    if (lineIndex <= 0) return 0;
    if (lineIndex >= _lineOffsets.length) return text.length;
    return _lineOffsets[lineIndex];
  }

  ({int line, int column}) _lineColumnForOffset(int offset) {
    final clampedOffset = offset.clamp(0, text.length);
    final lineIndex = _lineIndexForOffset(clampedOffset);
    final lineStart = _offsetForLine(lineIndex);
    return (line: lineIndex + 1, column: clampedOffset - lineStart + 1);
  }

  int _offsetForLineColumn(int line, int column) {
    if (text.isEmpty) {
      return 0;
    }
    final lineIndex = math.max(0, math.min(_lineCount - 1, line - 1));
    final lineStart = _offsetForLine(lineIndex);
    var lineEnd = lineIndex + 1 >= _lineOffsets.length
        ? text.length
        : _offsetForLine(lineIndex + 1);
    while (lineEnd > lineStart) {
      final trailingCodeUnit = text.codeUnitAt(lineEnd - 1);
      if (trailingCodeUnit == 10 || trailingCodeUnit == 13) {
        lineEnd -= 1;
        continue;
      }
      break;
    }
    final columnOffset = math.max(0, column - 1);
    return math.min(lineStart + columnOffset, lineEnd);
  }

  /// Schedule (or immediately perform) viewport-based highlighting for the
  /// window of lines around the current cursor position.
  void _scheduleViewportHighlight(TextStyle? style) {
    final cursorLine = _cachedCursorLine;

    // Check if the cursor is still within the already-highlighted viewport
    // buffer zone — if so, reuse the cached span.
    if (_cachedSpan != null &&
        _lastText == text &&
        cursorLine >= _viewportStartLine + _viewportBufferLines &&
        cursorLine <= _viewportEndLine - _viewportBufferLines &&
        _lastHighlighterHash == identityHashCode(highlighter) &&
        _lastDiagnosticsRevision == _diagnosticsRevision) {
      return;
    }

    // Compute the new viewport window.
    const halfWindow = _viewportHighlightLines ~/ 2;
    final startLine = math.max(0, cursorLine - halfWindow);
    final endLine = math.min(_lineCount - 1, cursorLine + halfWindow);

    // Debounce to avoid re-highlighting every frame during fast scrolling.
    _debounceTimer?.cancel();
    _debounceTimer = startSafeTimer(const Duration(milliseconds: 80), () {
      if (highlighter == null) return;
      _rebuildViewportHighlight(style, startLine, endLine);
      notifyListeners();
    });
  }

  /// Builds a composite TextSpan: plain-before + highlighted-window + plain-after.
  void _rebuildViewportHighlight(TextStyle? style, int startLine, int endLine) {
    try {
      final windowStart = _offsetForLine(startLine);
      final windowEnd = endLine >= _lineCount - 1
          ? text.length
          : _offsetForLine(endLine + 1);
      final windowText = text.substring(windowStart, windowEnd);

      final highlighted = highlighter!.build(
        windowText,
        language: language,
        allowAutoDetection: language == null,
      );

      final children = <InlineSpan>[];
      // Plain text before the highlighted window.
      if (windowStart > 0) {
        children.add(
          TextSpan(text: text.substring(0, windowStart), style: style),
        );
      }
      // The highlighted window.
      children.add(highlighted);
      // Plain text after the highlighted window.
      if (windowEnd < text.length) {
        children.add(TextSpan(text: text.substring(windowEnd), style: style));
      }

      final composedSpan = TextSpan(style: style, children: children);
      _cachedSpan = _diagnostics.isEmpty
          ? composedSpan
          : _applyEditorDiagnosticDecorationsToTextSpan(
              composedSpan,
              text,
              _diagnostics,
            );
      _lastText = text;
      _lastHighlighterHash = identityHashCode(highlighter);
      _lastDiagnosticsRevision = _diagnosticsRevision;
      _viewportStartLine = startLine;
      _viewportEndLine = endLine;
    } catch (error, stack) {
      silentLog('file_explorer', '重建视口高亮', error, stack);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}

class _SyntaxHighlightEditor extends StatefulWidget {
  const _SyntaxHighlightEditor({
    required this.controller,
    required this.scrollController,
    required this.focusNode,
    required this.onChanged,
    this.language,
    this.fontSize = _editorFontSizeDefault,
    this.wordWrap = true,
    this.codeTheme = EditorCodeTheme.materialYou,
    this.activeLine = 1,
    this.diagnostics = const <_EditorDiagnostic>[],
    this.diagnosticsByLine = const <int, List<_EditorDiagnostic>>{},
    this.onSelectionChanged,
    this.onDiagnosticLineRequested,
    this.onDiagnosticQuickFixRequested,
    this.onDiagnosticTooltipQuickFixRequested,
    this.onDiagnosticTooltipMoreActionsRequested,
    this.onSecondaryTapDown,
  });

  final _HighlightingTextController controller;
  final ScrollController scrollController;
  final FocusNode focusNode;
  final String? language;
  final ValueChanged<String> onChanged;
  final double fontSize;
  final bool wordWrap;
  final EditorCodeTheme codeTheme;
  final int activeLine;
  final List<_EditorDiagnostic> diagnostics;
  final Map<int, List<_EditorDiagnostic>> diagnosticsByLine;
  final VoidCallback? onSelectionChanged;
  final ValueChanged<int>? onDiagnosticLineRequested;
  final void Function(int lineNumber, Offset globalPosition)?
  onDiagnosticQuickFixRequested;
  final void Function(
    List<_EditorDiagnostic> diagnostics,
    Offset globalPosition,
  )?
  onDiagnosticTooltipQuickFixRequested;
  final void Function(
    List<_EditorDiagnostic> diagnostics,
    Offset globalPosition,
  )?
  onDiagnosticTooltipMoreActionsRequested;
  final void Function(TapDownDetails details)? onSecondaryTapDown;

  @override
  State<_SyntaxHighlightEditor> createState() => _SyntaxHighlightEditorState();
}

class _SyntaxHighlightEditorState extends State<_SyntaxHighlightEditor> {
  static const double _editorTextPaddingLeft = 8;
  static const double _editorTextPaddingRight = 12;
  static const double _editorTextPaddingTop = 10;
  static const double _editorTextPaddingBottom = 10;

  final GlobalKey _textViewportKey = GlobalKey();
  late final ScrollController _lineNumberScrollController;
  late final ScrollController _horizontalScrollController;
  bool _darkSurface = false;
  int? _hoveredGutterLine;
  final AnimatedOverlayEntryController _diagnosticTooltipOverlay =
      AnimatedOverlayEntryController();
  bool _diagnosticTooltipUpdateQueued = false;
  Timer? _diagnosticTooltipHideTimer;
  bool _hoveringDiagnosticTooltip = false;
  int? _hoveredTextDiagnosticOffset;
  List<_EditorDiagnostic> _hoveredTextDiagnostics = const <_EditorDiagnostic>[];
  Rect? _hoveredTextDiagnosticAnchorRect;
  TextPainter? _hoverTextPainter;
  String? _hoverTextPainterText;
  double? _hoverTextPainterWidth;
  List<_EditorDiagnosticResolvedRange>? _resolvedDiagnosticRangesCache;
  String? _resolvedDiagnosticRangesText;
  List<_EditorDiagnostic>? _resolvedDiagnosticRangesDiagnostics;

  // ── Word-wrap per-line height cache ──
  // When word wrap is on, each logical line may occupy multiple visual lines.
  // We measure the wrapped heights so that line-number items match the text.
  List<double>? _wrappedLineHeights;
  String? _wrappedLineHeightsText;
  double? _wrappedLineHeightsWidth;
  double? _wrappedLineHeightsFontSize;

  double get _lineExtent => widget.fontSize * _editorLineHeight;

  _EditorDiagnostic? _primaryDiagnosticForLine(int lineNumber) {
    final diagnostics =
        widget.diagnosticsByLine[lineNumber] ?? const <_EditorDiagnostic>[];
    if (diagnostics.isEmpty) {
      return null;
    }
    for (final diagnostic in diagnostics) {
      if (diagnostic.isError) {
        return diagnostic;
      }
    }
    for (final diagnostic in diagnostics) {
      if (diagnostic.isWarning) {
        return diagnostic;
      }
    }
    return diagnostics.first;
  }

  Color _diagnosticColor(
    ColorScheme colorScheme,
    _EditorDiagnostic diagnostic,
  ) {
    if (diagnostic.isError) {
      return colorScheme.error;
    }
    if (diagnostic.isWarning) {
      return _kFileExplorerWarningColor;
    }
    return colorScheme.primary;
  }

  String _diagnosticsTooltip(List<_EditorDiagnostic> diagnostics) {
    if (diagnostics.isEmpty) {
      return '';
    }
    final messages = trimmedNonEmptyStrings(
      diagnostics.map((diagnostic) => diagnostic.message),
    ).take(2).toList(growable: false);
    if (messages.isEmpty) {
      return '';
    }
    if (diagnostics.length <= 2) {
      return messages.join('\n');
    }
    return '${messages.join('\n')}\n…';
  }

  TextStyle _resolvedEditorStyle() {
    return _editorBaseStyleForSize(widget.fontSize).copyWith(
      color: _darkSurface ? _kFileExplorerDarkSurfaceText : _kFileExplorerLightSurfaceText,
    );
  }

  /// Compute per-logical-line wrapped heights using [TextPainter] so that
  /// line-number items match the actual rendered text when word wrap is on.
  List<double> _computeWrappedLineHeights(double textLayoutWidth) {
    final text = widget.controller.text;
    if (_wrappedLineHeights != null &&
        _wrappedLineHeightsText == text &&
        _wrappedLineHeightsWidth == textLayoutWidth &&
        _wrappedLineHeightsFontSize == widget.fontSize) {
      return _wrappedLineHeights!;
    }
    final editorStyle = _resolvedEditorStyle();
    final painter = TextPainter(
      text: TextSpan(text: text, style: editorStyle),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: textLayoutWidth);

    final metrics = painter.computeLineMetrics();
    final lineHeights = <double>[];
    double currentLogicalLineHeight = 0;
    for (final metric in metrics) {
      currentLogicalLineHeight += metric.height;
      if (metric.hardBreak) {
        lineHeights.add(math.max(currentLogicalLineHeight, _lineExtent));
        currentLogicalLineHeight = 0;
      }
    }
    // Handle last line if no trailing newline
    if (currentLogicalLineHeight > 0) {
      lineHeights.add(math.max(currentLogicalLineHeight, _lineExtent));
    }
    // Guarantee at least one entry
    if (lineHeights.isEmpty) {
      lineHeights.add(_lineExtent);
    }
    painter.dispose();
    _wrappedLineHeights = lineHeights;
    _wrappedLineHeightsText = text;
    _wrappedLineHeightsWidth = textLayoutWidth;
    _wrappedLineHeightsFontSize = widget.fontSize;
    return lineHeights;
  }

  @override
  void initState() {
    super.initState();
    _lineNumberScrollController = ScrollController();
    _horizontalScrollController = ScrollController();
    widget.scrollController.addListener(_syncLineNumbers);
    widget.controller.addListener(_handleSelectionChange);
    // Note: The highlighter is set in didChangeDependencies, which is called
    // after initState but before build. This ensures the Theme.of(context)
    // is available for determining dark/light surface colors.
  }

  @override
  void dispose() {
    _diagnosticTooltipHideTimer?.cancel();
    _diagnosticTooltipOverlay.dispose();
    _clearDiagnosticTooltipState();
    widget.scrollController.removeListener(_syncLineNumbers);
    widget.controller.removeListener(_handleSelectionChange);
    _lineNumberScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  void _handleSelectionChange() {
    widget.onSelectionChanged?.call();
    if (_hoveredTextDiagnosticOffset != null &&
        widget.controller.supportsDiagnosticHoverTooltips) {
      _scheduleDiagnosticTooltipUpdate();
    }
  }

  @override
  void didUpdateWidget(_SyntaxHighlightEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_syncLineNumbers);
      widget.scrollController.addListener(_syncLineNumbers);
    }
    final controllerChanged = oldWidget.controller != widget.controller;
    if (controllerChanged) {
      oldWidget.controller.removeListener(_handleSelectionChange);
      widget.controller.addListener(_handleSelectionChange);
      _hoverTextPainter = null;
      _hoverTextPainterText = null;
      _resolvedDiagnosticRangesCache = null;
      _resolvedDiagnosticRangesText = null;
      _resolvedDiagnosticRangesDiagnostics = null;
      _wrappedLineHeights = null;
      _removeDiagnosticTooltip();
    }
    // Re-apply highlighter when controller changes or font/theme changes.
    // Without this, switching files leaves the new controller without a
    // highlighter and buildTextSpan falls back to plain text rendering.
    if (controllerChanged ||
        oldWidget.fontSize != widget.fontSize ||
        oldWidget.codeTheme != widget.codeTheme) {
      // Invalidate wrapped line height cache on font change.
      _wrappedLineHeights = null;
      widget.controller.highlighter = _CodeSyntaxHighlighter(
        baseStyle: _resolvedEditorStyle(),
        darkSurface: _darkSurface,
        codeTheme: widget.codeTheme,
      );
      widget.controller.invalidateHighlightCache();
      _hoverTextPainter = null;
      _hoverTextPainterText = null;
      _hoverTextPainterWidth = null;
      if (_hoveredTextDiagnosticOffset != null &&
          widget.controller.supportsDiagnosticHoverTooltips) {
        _scheduleDiagnosticTooltipUpdate();
      }
      // Re-sync line numbers after font size change to ensure alignment
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncLineNumbers();
      });
    }
    if (!identical(oldWidget.diagnostics, widget.diagnostics)) {
      _resolvedDiagnosticRangesCache = null;
      _resolvedDiagnosticRangesText = null;
      _resolvedDiagnosticRangesDiagnostics = null;
      _removeDiagnosticTooltip();
    }
  }

  void _syncLineNumbers() {
    if (!_lineNumberScrollController.hasClients) return;
    if (!widget.scrollController.hasClients) return;
    final offset = widget.scrollController.offset;
    final textMax = widget.scrollController.position.maxScrollExtent;
    final lineMax = _lineNumberScrollController.position.maxScrollExtent;

    double targetOffset;
    // When word wrap is active the text area can be taller than the line-number
    // list (wrapped lines occupy extra visual height).  Use proportional sync
    // so both columns reach the end simultaneously.
    if (widget.wordWrap &&
        textMax > 0 &&
        lineMax > 0 &&
        (textMax - lineMax).abs() > _lineExtent) {
      targetOffset = offset * (lineMax / textMax);
    } else {
      targetOffset = offset;
    }
    _lineNumberScrollController.jumpTo(targetOffset.clamp(0.0, lineMax));
    if (_hoveredTextDiagnosticOffset != null &&
        widget.controller.supportsDiagnosticHoverTooltips) {
      _scheduleDiagnosticTooltipUpdate();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    final darkSurface = brightness == Brightness.dark;
    // Always update _darkSurface first, then check if highlighter needs refresh.
    final needsHighlighterRefresh =
        widget.controller.highlighter == null || darkSurface != _darkSurface;
    _darkSurface = darkSurface;
    if (needsHighlighterRefresh) {
      widget.controller.highlighter = _CodeSyntaxHighlighter(
        baseStyle: _resolvedEditorStyle(),
        darkSurface: darkSurface,
        codeTheme: widget.codeTheme,
      );
      widget.controller.invalidateHighlightCache();
      _hoverTextPainter = null;
      _hoverTextPainterText = null;
      _hoverTextPainterWidth = null;
      _diagnosticTooltipOverlay.markNeedsBuild();
      if (_hoveredTextDiagnosticOffset != null &&
          widget.controller.supportsDiagnosticHoverTooltips) {
        _scheduleDiagnosticTooltipUpdate();
      }
    }
  }

  List<_EditorDiagnosticResolvedRange> _resolvedDiagnosticRanges() {
    if (_resolvedDiagnosticRangesCache != null &&
        _resolvedDiagnosticRangesText == widget.controller.text &&
        identical(_resolvedDiagnosticRangesDiagnostics, widget.diagnostics)) {
      return _resolvedDiagnosticRangesCache!;
    }
    final ranges = _buildEditorDiagnosticResolvedRanges(
      widget.controller.text,
      widget.diagnostics,
    );
    _resolvedDiagnosticRangesCache = ranges;
    _resolvedDiagnosticRangesText = widget.controller.text;
    _resolvedDiagnosticRangesDiagnostics = widget.diagnostics;
    return ranges;
  }

  TextPainter _resolvedHoverTextPainter(double maxWidth, TextStyle style) {
    if (_hoverTextPainter != null &&
        _hoverTextPainterText == widget.controller.text &&
        _hoverTextPainterWidth == maxWidth) {
      return _hoverTextPainter!;
    }
    final painter = TextPainter(
      text: TextSpan(text: widget.controller.text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    _hoverTextPainter = painter;
    _hoverTextPainterText = widget.controller.text;
    _hoverTextPainterWidth = maxWidth;
    return painter;
  }

  int? _textOffsetForHoverPosition({
    required Offset localPosition,
    required double viewportWidth,
    required TextStyle style,
  }) {
    final contentWidth =
        viewportWidth - _editorTextPaddingLeft - _editorTextPaddingRight;
    if (contentWidth <= 0) {
      return null;
    }
    final adjusted = Offset(
      localPosition.dx - _editorTextPaddingLeft,
      localPosition.dy - _editorTextPaddingTop + widget.scrollController.offset,
    );
    if (adjusted.dx < 0 || adjusted.dy < 0 || adjusted.dx > contentWidth) {
      return null;
    }
    final painter = _resolvedHoverTextPainter(contentWidth, style);
    if (adjusted.dy > painter.height) {
      return null;
    }
    final position = painter.getPositionForOffset(adjusted);
    return position.offset.clamp(0, widget.controller.text.length);
  }

  List<_EditorDiagnosticResolvedRange> _diagnosticRangesAtTextOffset(
    int offset,
  ) {
    final matches =
        _resolvedDiagnosticRanges()
            .where((range) {
              return offset >= range.startOffset && offset < range.endOffset;
            })
            .toList(growable: false)
          ..sort((left, right) {
            final severity = _editorDiagnosticSeverityRank(
              right.diagnostic,
            ).compareTo(_editorDiagnosticSeverityRank(left.diagnostic));
            if (severity != 0) {
              return severity;
            }
            return left.startOffset.compareTo(right.startOffset);
          });
    return matches;
  }

  _EditorDiagnosticResolvedRange _preferredTooltipAnchorRange(
    List<_EditorDiagnosticResolvedRange> matches,
  ) {
    final sorted = matches.toList(growable: false)
      ..sort((left, right) {
        final leftLength = left.endOffset - left.startOffset;
        final rightLength = right.endOffset - right.startOffset;
        final byLength = leftLength.compareTo(rightLength);
        if (byLength != 0) {
          return byLength;
        }
        final severity = _editorDiagnosticSeverityRank(
          right.diagnostic,
        ).compareTo(_editorDiagnosticSeverityRank(left.diagnostic));
        if (severity != 0) {
          return severity;
        }
        return left.startOffset.compareTo(right.startOffset);
      });
    return sorted.first;
  }

  Rect? _diagnosticAnchorRectForRange({
    required _EditorDiagnosticResolvedRange range,
    required int hoveredOffset,
    required TextStyle editorStyle,
  }) {
    final renderBox =
        _textViewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached || !renderBox.hasSize) {
      return null;
    }

    final contentWidth =
        renderBox.size.width - _editorTextPaddingLeft - _editorTextPaddingRight;
    if (contentWidth <= 0) {
      return null;
    }

    final painter = _resolvedHoverTextPainter(contentWidth, editorStyle);
    final textLength = widget.controller.text.length;
    final startOffset = math.max(0, math.min(range.startOffset, textLength));
    final endOffset = math.max(
      startOffset,
      math.min(range.endOffset, textLength),
    );
    final safeHoverOffset = math.max(
      startOffset,
      math.min(hoveredOffset, math.max(startOffset, endOffset - 1)),
    );

    final selectionBoxes = endOffset > startOffset
        ? painter.getBoxesForSelection(
            TextSelection(baseOffset: startOffset, extentOffset: endOffset),
          )
        : const <TextBox>[];

    Rect contentRect;
    if (selectionBoxes.isNotEmpty) {
      final hoverCaretOffset = painter.getOffsetForCaret(
        TextPosition(offset: safeHoverOffset),
        Rect.zero,
      );
      final hoverPoint = Offset(
        hoverCaretOffset.dx,
        hoverCaretOffset.dy + (painter.preferredLineHeight / 2),
      );

      double distanceSquaredToRect(Rect rect) {
        final dx = hoverPoint.dx < rect.left
            ? rect.left - hoverPoint.dx
            : hoverPoint.dx > rect.right
            ? hoverPoint.dx - rect.right
            : 0.0;
        final dy = hoverPoint.dy < rect.top
            ? rect.top - hoverPoint.dy
            : hoverPoint.dy > rect.bottom
            ? hoverPoint.dy - rect.bottom
            : 0.0;
        return (dx * dx) + (dy * dy);
      }

      contentRect = selectionBoxes
          .map(
            (box) => Rect.fromLTRB(
              math.min(box.left, box.right),
              box.top,
              math.max(box.left, box.right),
              box.bottom,
            ),
          )
          .reduce((best, candidate) {
            return distanceSquaredToRect(candidate) <
                    distanceSquaredToRect(best)
                ? candidate
                : best;
          });
    } else {
      final caretOffset = painter.getOffsetForCaret(
        TextPosition(offset: startOffset),
        Rect.zero,
      );
      contentRect = Rect.fromLTWH(
        caretOffset.dx,
        caretOffset.dy,
        math.min(18.0, contentWidth),
        painter.preferredLineHeight,
      );
    }

    final minAnchorWidth = math.min(18.0, contentWidth);
    if (contentRect.width < minAnchorWidth) {
      final minCenterDx = minAnchorWidth / 2;
      final maxCenterDx = math.max(
        minCenterDx,
        contentWidth - minAnchorWidth / 2,
      );
      final centerDx = math.max(
        minCenterDx,
        math.min(contentRect.center.dx, maxCenterDx),
      );
      contentRect = Rect.fromCenter(
        center: Offset(centerDx, contentRect.center.dy),
        width: minAnchorWidth,
        height: math.max(contentRect.height, painter.preferredLineHeight),
      );
    }

    final scrollOffset = widget.scrollController.hasClients
        ? widget.scrollController.offset
        : 0.0;
    final viewportRect = contentRect.shift(
      Offset(_editorTextPaddingLeft, _editorTextPaddingTop - scrollOffset),
    );
    if (viewportRect.bottom < 0 ||
        viewportRect.top > renderBox.size.height ||
        viewportRect.right < 0 ||
        viewportRect.left > renderBox.size.width) {
      return null;
    }

    return Rect.fromPoints(
      renderBox.localToGlobal(viewportRect.topLeft),
      renderBox.localToGlobal(viewportRect.bottomRight),
    );
  }

  _EditorDiagnosticTooltipState? _resolveDiagnosticTooltipState() {
    final hoveredOffset = _hoveredTextDiagnosticOffset;
    if (hoveredOffset == null || widget.diagnostics.isEmpty) {
      return null;
    }

    final matches = _diagnosticRangesAtTextOffset(hoveredOffset);
    if (matches.isEmpty) {
      return null;
    }

    final anchorRect = _diagnosticAnchorRectForRange(
      range: _preferredTooltipAnchorRange(matches),
      hoveredOffset: hoveredOffset,
      editorStyle: _resolvedEditorStyle(),
    );
    if (anchorRect == null) {
      return null;
    }

    return _EditorDiagnosticTooltipState(
      diagnostics: matches
          .map((range) => range.diagnostic)
          .toList(growable: false),
      anchorRect: anchorRect,
    );
  }

  Offset _diagnosticMenuAnchorPosition(Rect anchorRect) {
    return Offset(anchorRect.center.dx, anchorRect.bottom + 6);
  }

  List<_EditorDiagnostic> _diagnosticsAtTextOffset(int offset) {
    return _diagnosticRangesAtTextOffset(
      offset,
    ).map((range) => range.diagnostic).toList(growable: false);
  }

  void _handleTextHover(
    PointerHoverEvent event, {
    required double viewportWidth,
    required TextStyle editorStyle,
  }) {
    if (widget.diagnostics.isEmpty) {
      _scheduleDiagnosticTooltipHide();
      return;
    }
    final offset = _textOffsetForHoverPosition(
      localPosition: event.localPosition,
      viewportWidth: viewportWidth,
      style: editorStyle,
    );
    if (offset == null) {
      _scheduleDiagnosticTooltipHide();
      return;
    }
    final diagnostics = _diagnosticsAtTextOffset(offset);
    if (diagnostics.isEmpty) {
      _scheduleDiagnosticTooltipHide();
      return;
    }
    _diagnosticTooltipHideTimer?.cancel();
    _hoveredTextDiagnosticOffset = offset;
    _scheduleDiagnosticTooltipUpdate();
  }

  void _removeDiagnosticTooltip({bool immediately = false}) {
    _diagnosticTooltipHideTimer?.cancel();
    _diagnosticTooltipHideTimer = null;
    _hoveringDiagnosticTooltip = false;
    _hoveredTextDiagnosticOffset = null;
    if (!_diagnosticTooltipOverlay.hasEntry) {
      _clearDiagnosticTooltipState();
      return;
    }
    _diagnosticTooltipOverlay.close(immediately: immediately || !mounted);
  }

  void _clearDiagnosticTooltipState() {
    _hoveredTextDiagnostics = const <_EditorDiagnostic>[];
    _hoveredTextDiagnosticAnchorRect = null;
  }

  void _scheduleDiagnosticTooltipHide() {
    _diagnosticTooltipHideTimer?.cancel();
    if (_hoveringDiagnosticTooltip) {
      return;
    }
    _diagnosticTooltipHideTimer = startSafeTimer(
      kOpenHandMotion120,
      () {
        if (!mounted || _hoveringDiagnosticTooltip) {
          return;
        }
        _removeDiagnosticTooltip();
      },
    );
  }

  void _scheduleDiagnosticTooltipUpdate() {
    _diagnosticTooltipHideTimer?.cancel();
    if (_diagnosticTooltipUpdateQueued) {
      return;
    }
    _diagnosticTooltipUpdateQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _diagnosticTooltipUpdateQueued = false;
      if (!mounted) {
        _removeDiagnosticTooltip();
        return;
      }
      final tooltipState = _resolveDiagnosticTooltipState();
      if (tooltipState == null) {
        _removeDiagnosticTooltip();
        return;
      }
      final diagnosticsUnchanged = listEquals(
        _hoveredTextDiagnostics,
        tooltipState.diagnostics,
      );
      final anchorUnchanged =
          _hoveredTextDiagnosticAnchorRect == tooltipState.anchorRect;
      _hoveredTextDiagnostics = tooltipState.diagnostics;
      _hoveredTextDiagnosticAnchorRect = tooltipState.anchorRect;
      final overlay = Overlay.of(context, rootOverlay: true);
      _diagnosticTooltipOverlay.show(
        overlay: overlay,
        onRemoved: _clearDiagnosticTooltipState,
        rebuildIfPresent: !diagnosticsUnchanged || !anchorUnchanged,
        builder: (overlayContext, visibility, onExitCompleted) =>
            AnimatedOverlayContent(
              visibility: visibility,
              onExitCompleted: onExitCompleted,
              child: _buildDiagnosticTooltipOverlay(overlayContext),
            ),
      );
    });
  }

  Widget _buildDiagnosticTooltipOverlay(BuildContext overlayContext) {
    final diagnostics = _hoveredTextDiagnostics;
    final globalAnchorRect = _hoveredTextDiagnosticAnchorRect;
    if (diagnostics.isEmpty || globalAnchorRect == null) {
      return const SizedBox.shrink();
    }
    final overlayBox =
        Overlay.of(overlayContext).context.findRenderObject() as RenderBox?;
    final mediaSize = MediaQuery.sizeOf(overlayContext);
    final overlaySize = overlayBox?.size ?? mediaSize;
    const tooltipMaxWidth = 340.0;
    const tooltipViewportMargin = 8.0;
    const tooltipGap = 10.0;
    final availableWidth = math.max(
      0.0,
      overlaySize.width - tooltipViewportMargin * 2,
    );
    if (availableWidth <= 0 || overlaySize.height <= 0) {
      return const SizedBox.shrink();
    }
    final tooltipWidth = math.min(tooltipMaxWidth, availableWidth);
    final maxLeft = math.max(
      tooltipViewportMargin,
      overlaySize.width - tooltipWidth - tooltipViewportMargin,
    );
    final left = globalAnchorRect.left
        .clamp(tooltipViewportMargin, maxLeft)
        .toDouble();
    final belowSpace = math.max(
      0.0,
      overlaySize.height -
          globalAnchorRect.bottom -
          tooltipGap -
          tooltipViewportMargin,
    );
    final aboveSpace = math.max(
      0.0,
      globalAnchorRect.top - tooltipGap - tooltipViewportMargin,
    );
    final showBelow = belowSpace >= aboveSpace;
    final tooltipMaxHeight = math.max(1.0, showBelow ? belowSpace : aboveSpace);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final visibleDiagnostics = diagnostics.take(4).toList(growable: false);
    final actionAnchor = _diagnosticMenuAnchorPosition(globalAnchorRect);

    return Positioned(
      left: left,
      top: showBelow ? globalAnchorRect.bottom + tooltipGap : null,
      bottom: showBelow
          ? null
          : overlaySize.height - globalAnchorRect.top + tooltipGap,
      child: MouseRegion(
        onEnter: (_) {
          _hoveringDiagnosticTooltip = true;
          _diagnosticTooltipHideTimer?.cancel();
        },
        onExit: (_) {
          _hoveringDiagnosticTooltip = false;
          _scheduleDiagnosticTooltipHide();
        },
        child: Material(
          color: Colors.transparent,
          elevation: 12,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: tooltipWidth,
              maxHeight: tooltipMaxHeight,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.98,
                ),
                borderRadius: kOpenHandBorderRadius12,
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                primary: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (
                      var index = 0;
                      index < visibleDiagnostics.length;
                      index++
                    ) ...[
                      if (index > 0)
                        Divider(
                          height: 12,
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.18,
                          ),
                        ),
                      _buildDiagnosticTooltipEntry(
                        theme,
                        colorScheme,
                        visibleDiagnostics[index],
                      ),
                    ],
                    if (diagnostics.length > visibleDiagnostics.length) ...[
                      kOpenHandGap6,
                      Text(
                        openHandLocalizedText(
                          context,
                          zh: '还有 ${diagnostics.length - visibleDiagnostics.length} 条重叠诊断',
                          zhHant:
                              '還有 ${diagnostics.length - visibleDiagnostics.length} 條重疊診斷',
                          en: '${diagnostics.length - visibleDiagnostics.length} more overlapping diagnostics',
                          fr: '${diagnostics.length - visibleDiagnostics.length} diagnostics superposés en plus',
                          de: '${diagnostics.length - visibleDiagnostics.length} weitere überlappende Diagnosen',
                          ja: 'ほかに ${diagnostics.length - visibleDiagnostics.length} 件の重なった診断',
                        ),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (widget.onDiagnosticTooltipQuickFixRequested != null ||
                        widget.onDiagnosticTooltipMoreActionsRequested !=
                            null) ...[
                      kOpenHandGap10,
                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (widget
                                    .onDiagnosticTooltipMoreActionsRequested !=
                                null)
                              OutlinedButton.icon(
                                onPressed: () {
                                  final selectedDiagnostics =
                                      List<_EditorDiagnostic>.from(
                                        diagnostics,
                                        growable: false,
                                      );
                                  _removeDiagnosticTooltip();
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    if (!mounted) {
                                      return;
                                    }
                                    widget
                                        .onDiagnosticTooltipMoreActionsRequested
                                        ?.call(
                                          selectedDiagnostics,
                                          actionAnchor,
                                        );
                                  });
                                },
                                icon: const Icon(
                                  Icons.more_horiz_rounded,
                                  size: 16,
                                ),
                                label: Text(
                                  openHandLocalizedText(
                                    context,
                                    zh: '更多操作',
                                    zhHant: '更多操作',
                                    en: 'More Actions',
                                    fr: 'Plus d’actions',
                                    de: 'Weitere Aktionen',
                                    ja: 'その他の操作',
                                  ),
                                ),
                              ),
                            if (widget.onDiagnosticTooltipQuickFixRequested !=
                                null)
                              FilledButton.tonalIcon(
                                onPressed: () {
                                  final selectedDiagnostics =
                                      List<_EditorDiagnostic>.from(
                                        diagnostics,
                                        growable: false,
                                      );
                                  _removeDiagnosticTooltip();
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    if (!mounted) {
                                      return;
                                    }
                                    widget.onDiagnosticTooltipQuickFixRequested
                                        ?.call(
                                          selectedDiagnostics,
                                          actionAnchor,
                                        );
                                  });
                                },
                                icon: const Icon(
                                  Icons.auto_fix_high_rounded,
                                  size: 16,
                                ),
                                label: Text(
                                  openHandLocalizedText(
                                    context,
                                    zh: '应用快速修复',
                                    zhHant: '套用快速修復',
                                    en: 'Apply Quick Fix',
                                    fr: 'Appliquer la correction rapide',
                                    de: 'Schnellkorrektur anwenden',
                                    ja: 'クイック修正を適用',
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDiagnosticTooltipEntry(
    ThemeData theme,
    ColorScheme colorScheme,
    _EditorDiagnostic diagnostic,
  ) {
    final accent = _diagnosticColor(colorScheme, diagnostic);
    final severityLabel = diagnostic.isError
        ? openHandErrorLabel(context)
        : diagnostic.isWarning
        ? openHandWarningLabel(context)
        : openHandLocalizedText(
            context,
            zh: '提示',
            zhHant: '提示',
            en: 'Info',
            fr: 'Info',
            de: 'Info',
            ja: '情報',
          );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            diagnostic.isError
                ? Icons.error_outline_rounded
                : diagnostic.isWarning
                ? Icons.warning_amber_rounded
                : Icons.info_outline_rounded,
            size: 16,
            color: accent,
          ),
        ),
        kOpenHandHGap8,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                diagnostic.message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              kOpenHandGap4,
              Text(
                '${diagnostic.code}  •  $severityLabel  •  ${diagnostic.line}:${diagnostic.column}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontFamily: kOpenHandMonospaceFontFamily,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Safety check: Ensure highlighter is set. This handles edge cases where
    // didChangeDependencies may not have run yet or was bypassed somehow.
    if (widget.controller.highlighter == null) {
      final brightness = Theme.of(context).brightness;
      _darkSurface = brightness == Brightness.dark;
      widget.controller.highlighter = _CodeSyntaxHighlighter(
        baseStyle: _resolvedEditorStyle(),
        darkSurface: _darkSurface,
        codeTheme: widget.codeTheme,
      );
      widget.controller.invalidateHighlightCache();
    }

    final supportsDiagnosticHoverTooltips =
        widget.controller.supportsDiagnosticHoverTooltips;
    if (!supportsDiagnosticHoverTooltips &&
        _diagnosticTooltipOverlay.hasEntry) {
      _removeDiagnosticTooltip();
    }

    final lineCount = widget.controller.lineCount;
    final hasAnyDiagnostics = widget.diagnosticsByLine.isNotEmpty;
    final lineNumberWidth = _editorEditableGutterWidth(
      lineCount: lineCount,
      fontSize: widget.fontSize,
      hasDiagnostics: hasAnyDiagnostics,
    );
    final editorStyle = _resolvedEditorStyle();

    const noScrollbarBehavior = OpenHandEditorScrollBehavior();

    return LayoutBuilder(
      builder: (context, outerConstraints) {
        // Compute per-line wrapped heights when word wrap is enabled and the
        // file is not too large for a full text layout measurement.
        List<double>? wrappedHeights;
        if (widget.wordWrap &&
            widget.controller.supportsPreciseWrappedLineHeights) {
          final textLayoutWidth =
              outerConstraints.maxWidth -
              lineNumberWidth -
              _editorTextPaddingLeft -
              _editorTextPaddingRight;
          if (textLayoutWidth > 0) {
            wrappedHeights = _computeWrappedLineHeights(textLayoutWidth);
          }
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Gutter: line numbers (no scrollbar) ──
            Container(
              width: lineNumberWidth,
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.2),
                    width: 0.5,
                  ),
                ),
              ),
              child: ScrollConfiguration(
                behavior: noScrollbarBehavior,
                child: ListView.builder(
                  // Key based on fontSize + wordWrap forces rebuild when zoom or
                  // wrap mode changes
                  key: ValueKey(
                    'line-numbers-${widget.fontSize}-${widget.wordWrap}',
                  ),
                  controller: _lineNumberScrollController,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(top: 10, bottom: 10),
                  itemCount: lineCount,
                  // Use fixed extent when word wrap is off (fast scroll); when on,
                  // use wrapped per-line heights for exact alignment.
                  itemExtent: wrappedHeights != null ? null : _lineExtent,
                  itemBuilder: (context, index) {
                    final lineNumber = index + 1;
                    final itemHeight = wrappedHeights != null
                        ? (index < wrappedHeights.length
                              ? wrappedHeights[index]
                              : _lineExtent)
                        : null;
                    final diagnostics =
                        widget.diagnosticsByLine[lineNumber] ??
                        const <_EditorDiagnostic>[];
                    final primaryDiagnostic = _primaryDiagnosticForLine(
                      lineNumber,
                    );
                    final hasDiagnostics = primaryDiagnostic != null;
                    final lineIsActive = widget.activeLine == lineNumber;
                    final showQuickFix =
                        hasDiagnostics &&
                        widget.onDiagnosticQuickFixRequested != null &&
                        (lineIsActive || _hoveredGutterLine == lineNumber);
                    final accentColor = hasDiagnostics
                        ? _diagnosticColor(colorScheme, primaryDiagnostic)
                        : colorScheme.onSurfaceVariant;
                    final tooltip = _diagnosticsTooltip(diagnostics);

                    Widget lineWidget = MouseRegion(
                      onEnter: hasDiagnostics
                          ? (_) {
                              if (_hoveredGutterLine != lineNumber) {
                                _hoveredGutterLine = lineNumber;
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  if (mounted) setState(() {});
                                });
                              }
                            }
                          : null,
                      onExit: hasDiagnostics
                          ? (_) {
                              if (_hoveredGutterLine == lineNumber) {
                                _hoveredGutterLine = null;
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  if (mounted) setState(() {});
                                });
                              }
                            }
                          : null,
                      child: Material(
                        color: hasDiagnostics && (lineIsActive || showQuickFix)
                            ? accentColor.withValues(alpha: 0.08)
                            : Colors.transparent,
                        child: InkWell(
                          onTap: hasDiagnostics
                              ? () => widget.onDiagnosticLineRequested?.call(
                                  lineNumber,
                                )
                              : null,
                          child: Padding(
                            padding: EdgeInsets.only(
                              left: 8,
                              right: hasAnyDiagnostics ? 6 : 14,
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 12,
                                  child: hasDiagnostics
                                      ? Center(
                                          child: Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: accentColor,
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: accentColor.withValues(
                                                    alpha: 0.2,
                                                  ),
                                                  blurRadius: 4,
                                                ),
                                              ],
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                                kOpenHandHGap6,
                                Expanded(
                                  child: Text(
                                    '$lineNumber',
                                    textAlign: TextAlign.right,
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.visible,
                                    style: TextStyle(
                                      fontFamily: kOpenHandMonospaceFontFamily,
                                      fontSize: widget.fontSize,
                                      height: _editorLineHeight,
                                      fontWeight: hasDiagnostics
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: hasDiagnostics
                                          ? accentColor
                                          : colorScheme.onSurfaceVariant
                                                .withValues(alpha: 0.48),
                                    ),
                                  ),
                                ),
                                if (hasAnyDiagnostics) ...[
                                  kOpenHandHGap4,
                                  SizedBox(
                                    width: 18,
                                    child: AnimatedOpacity(
                                      duration: openHandMotionDuration(
                                        context,
                                        kOpenHandMotion140,
                                      ),
                                      opacity: showQuickFix ? 1 : 0,
                                      child: IgnorePointer(
                                        ignoring: !showQuickFix,
                                        child: Tooltip(
                                          message: AppLocalizations.of(
                                            context,
                                          )!.progExpFEShowQuickFixesForThisDiagnostic,
                                          child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTapDown: (details) => widget
                                                .onDiagnosticQuickFixRequested
                                                ?.call(
                                                  lineNumber,
                                                  details.globalPosition,
                                                ),
                                            child: const Icon(
                                              Icons.lightbulb_outline_rounded,
                                              size: 15,
                                              color: _kFileExplorerWarningColor,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    );

                    if (hasDiagnostics && tooltip.isNotEmpty) {
                      lineWidget = Tooltip(message: tooltip, child: lineWidget);
                    }
                    // When using computed wrapped heights, constrain each item to
                    // the corresponding text line's visual height.
                    if (itemHeight != null) {
                      return SizedBox(height: itemHeight, child: lineWidget);
                    }
                    return lineWidget;
                  },
                ),
              ),
            ),
            // ── Code area — with optional horizontal scroll ──
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final viewportWidth = constraints.maxWidth;
                  final estimatedContentWidth = widget.wordWrap
                      ? viewportWidth
                      : math.min(
                          _editorMaxEstimatedContentWidth,
                          math.max(
                            viewportWidth,
                            widget.controller.longestLineLength *
                                    (widget.fontSize * 0.62) +
                                _editorTextPaddingLeft +
                                _editorTextPaddingRight +
                                48,
                          ),
                        );

                  Widget textFieldWidget = TextField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    autocorrect: false,
                    enableSuggestions: false,
                    maxLines: null,
                    expands: true,
                    scrollController: widget.scrollController,
                    smartDashesType: SmartDashesType.disabled,
                    smartQuotesType: SmartQuotesType.disabled,
                    style: editorStyle,
                    cursorColor: colorScheme.primary,
                    contextMenuBuilder: (context0, state0) =>
                        const SizedBox.shrink(),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      filled: false,
                      fillColor: Colors.transparent,
                      contentPadding: EdgeInsets.only(
                        top: _editorTextPaddingTop,
                        bottom: _editorTextPaddingBottom,
                        left: _editorTextPaddingLeft,
                        right: _editorTextPaddingRight,
                      ),
                      isDense: true,
                      isCollapsed: true,
                    ),
                    onChanged: widget.onChanged,
                  );

                  // When word wrap is disabled, wrap in horizontal scroll
                  if (!widget.wordWrap) {
                    textFieldWidget = SingleChildScrollView(
                      controller: _horizontalScrollController,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: estimatedContentWidth,
                        child: textFieldWidget,
                      ),
                    );
                  }

                  return PrimaryScrollController.none(
                    child: OpenHandSafeScrollbar(
                      controller: widget.scrollController,
                      thumbVisibility: true,
                      thickness: 9,
                      radius: kOpenHandPillRadius,
                      notificationPredicate: (notification) =>
                          notification.metrics.axis == Axis.vertical,
                      child: ScrollConfiguration(
                        behavior: noScrollbarBehavior,
                        child: GestureDetector(
                          onSecondaryTapDown: widget.onSecondaryTapDown,
                          child: MouseRegion(
                            key: _textViewportKey,
                            onExit: (_) => _scheduleDiagnosticTooltipHide(),
                            onHover:
                                widget.diagnostics.isEmpty ||
                                    !supportsDiagnosticHoverTooltips
                                ? null
                                : (event) => _handleTextHover(
                                    event,
                                    viewportWidth: viewportWidth,
                                    editorStyle: editorStyle,
                                  ),
                            child: textFieldWidget,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      }, // LayoutBuilder builder
    );
  }
}

class _LargeFileCodeView extends StatefulWidget {
  const _LargeFileCodeView({
    super.key,
    required this.controller,
    required this.scrollController,
    required this.language,
    required this.onOpenFullEditor,
    this.fontSize = _editorFontSizeDefault,
    this.codeTheme = EditorCodeTheme.materialYou,
  });

  final _HighlightingTextController controller;
  final ScrollController scrollController;
  final String? language;
  final VoidCallback onOpenFullEditor;
  final double fontSize;
  final EditorCodeTheme codeTheme;

  @override
  State<_LargeFileCodeView> createState() => _LargeFileCodeViewState();
}

class _LargeFileCodeViewState extends State<_LargeFileCodeView> {
  late final ScrollController _lineNumberScrollController;
  late final ScrollController _horizontalScrollController;
  final Map<int, TextSpan> _lineSpanCache = {};
  _CodeSyntaxHighlighter? _lineHighlighter;
  bool _darkSurface = false;
  static const int _plainPreviewLineLength = 2048;

  double get _lineExtent => widget.fontSize * _editorLineHeight;
  static const int _lineSpanCacheLimit = 600;

  TextStyle _resolvedEditorStyle() {
    return _editorBaseStyleForSize(widget.fontSize).copyWith(
      color: _darkSurface ? _kFileExplorerDarkSurfaceText : _kFileExplorerLightSurfaceText,
    );
  }

  @override
  void initState() {
    super.initState();
    _lineNumberScrollController = ScrollController();
    _horizontalScrollController = ScrollController();
    widget.scrollController.addListener(_syncLineNumbers);
  }

  @override
  void didUpdateWidget(covariant _LargeFileCodeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_syncLineNumbers);
      widget.scrollController.addListener(_syncLineNumbers);
    }
    if (oldWidget.controller != widget.controller ||
        oldWidget.language != widget.language ||
        oldWidget.codeTheme != widget.codeTheme) {
      _lineSpanCache.clear();
      _lineHighlighter = null;
    }
    // Handle font size changes: clear caches and re-sync scroll positions
    if (oldWidget.fontSize != widget.fontSize) {
      _lineSpanCache.clear();
      _lineHighlighter = null;
      // Proportionally adjust scroll position based on font size change ratio
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncLineNumbers();
      });
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_syncLineNumbers);
    _lineNumberScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  void _syncLineNumbers() {
    if (!_lineNumberScrollController.hasClients) return;
    if (!widget.scrollController.hasClients) return;
    final offset = widget.scrollController.offset;
    final lineMax = _lineNumberScrollController.position.maxScrollExtent;
    _lineNumberScrollController.jumpTo(offset.clamp(0.0, lineMax));
  }

  TextSpan _highlightLine(int index) {
    final cached = _lineSpanCache.remove(index);
    if (cached != null) {
      _lineSpanCache[index] = cached;
      return cached;
    }
    final line = widget.controller.previewLines[index];
    final editorStyle = _resolvedEditorStyle();
    final span = line.isEmpty
        ? TextSpan(text: ' ', style: editorStyle)
        : line.length >= _plainPreviewLineLength
        ? TextSpan(text: line, style: editorStyle)
        : (_lineHighlighter ??= _CodeSyntaxHighlighter(
            baseStyle: editorStyle,
            darkSurface: _darkSurface,
            codeTheme: widget.codeTheme,
          )).build(
            line,
            language: widget.language,
            allowAutoDetection: widget.language == null,
          );
    if (_lineSpanCache.length >= _lineSpanCacheLimit) {
      _lineSpanCache.remove(_lineSpanCache.keys.first);
    }
    _lineSpanCache[index] = span;
    return span;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final nextDarkSurface = theme.brightness == Brightness.dark;
    if (nextDarkSurface != _darkSurface) {
      _darkSurface = nextDarkSurface;
      _lineHighlighter = null;
      _lineSpanCache.clear();
    } else {
      _darkSurface = nextDarkSurface;
    }
    final lines = widget.controller.previewLines;
    final lineCount = lines.length;
    final lineNumberWidth = _editorPreviewGutterWidth(
      lineCount: lineCount,
      fontSize: widget.fontSize,
    );
    const noScrollbarBehavior = OpenHandEditorScrollBehavior();
    final bannerBackground = _darkSurface
        ? colorScheme.surfaceContainerHigh
        : colorScheme.primaryContainer.withValues(alpha: 0.42);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bannerBackground,
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.24),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.speed_rounded, size: 16, color: colorScheme.primary),
              kOpenHandHGap8,
              Expanded(
                child: Text(
                  AppLocalizations.of(
                    context,
                  )!.progExpFELargeFilePerformanceModeIsActive,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              kOpenHandHGap8,
              TextButton(
                onPressed: widget.onOpenFullEditor,
                child: Text(
                  AppLocalizations.of(context)!.progExpFEOpenFullEditorAnyway,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final estimatedContentWidth = math.min(
                _editorMaxEstimatedContentWidth,
                math.max(
                  constraints.maxWidth,
                  widget.controller.longestLineLength *
                          (widget.fontSize * 0.68) +
                      32,
                ),
              );
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: lineNumberWidth,
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.2,
                          ),
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: ScrollConfiguration(
                      behavior: noScrollbarBehavior,
                      child: ListView.builder(
                        // Key based on fontSize forces rebuild when zoom changes
                        key: ValueKey(
                          'preview-line-numbers-${widget.fontSize}',
                        ),
                        controller: _lineNumberScrollController,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(top: 10, bottom: 10),
                        itemCount: lineCount,
                        itemExtent: _lineExtent,
                        itemBuilder: (context, index) {
                          return Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 14, left: 10),
                            child: Text(
                              '${index + 1}',
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.visible,
                              style: TextStyle(
                                fontFamily: kOpenHandMonospaceFontFamily,
                                fontSize: widget.fontSize,
                                height: _editorLineHeight,
                                color: colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.48,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  Expanded(
                    child: PrimaryScrollController.none(
                      child: OpenHandSafeScrollbar(
                        controller: widget.scrollController,
                        thumbVisibility: true,
                        thickness: 9,
                        radius: kOpenHandPillRadius,
                        notificationPredicate: (notification) =>
                            notification.metrics.axis == Axis.vertical,
                        child: ScrollConfiguration(
                          behavior: noScrollbarBehavior,
                          child: SingleChildScrollView(
                            controller: _horizontalScrollController,
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: estimatedContentWidth,
                              child: ListView.builder(
                                // Key based on fontSize forces rebuild when zoom changes
                                key: ValueKey(
                                  'preview-content-${widget.fontSize}',
                                ),
                                controller: widget.scrollController,
                                padding: const EdgeInsets.only(
                                  top: 10,
                                  bottom: 10,
                                  left: 8,
                                  right: 12,
                                ),
                                cacheExtent: _lineExtent * 48,
                                itemCount: lineCount,
                                itemExtent: _lineExtent,
                                itemBuilder: (context, index) {
                                  return RepaintBoundary(
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text.rich(
                                        _highlightLine(index),
                                        maxLines: 1,
                                        softWrap: false,
                                        overflow: TextOverflow.visible,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// Editor tab — Material You Expressive pill tab
class _EditorTab extends StatelessWidget {
  const _EditorTab({
    super.key,
    required this.index,
    required this.fileName,
    required this.filePath,
    required this.isActive,
    required this.isDirty,
    required this.onTap,
    required this.onClose,
    required this.onShowMenu,
  });

  final int index;
  final String fileName;
  final String filePath;
  final bool isActive;
  final bool isDirty;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final ValueChanged<Offset> onShowMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final fgColor = isActive
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;

    return ReorderableDragStartListener(
      index: index,
      child: Padding(
        padding: const EdgeInsets.only(right: 3),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onSecondaryTapDown: (details) {
            onTap();
            onShowMenu(details.globalPosition);
          },
          onDoubleTapDown: (details) {
            onTap();
            onShowMenu(details.globalPosition);
          },
          child: Material(
            color: isActive
                ? colorScheme.primaryContainer
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: kOpenHandPillBorderRadius,
            elevation: isActive ? 1 : 0,
            shadowColor: colorScheme.shadow.withValues(alpha: 0.15),
            child: InkWell(
              onTap: onTap,
              borderRadius: kOpenHandPillBorderRadius,
              overlayColor: WidgetStatePropertyAll<Color>(
                colorScheme.primary.withValues(alpha: 0.08),
              ),
              child: AnimatedContainer(
                duration: openHandMotionDuration(context, kOpenHandMotion200,
                ),
                curve: kOpenHandSwitchInCurve,
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _fileExplorerIcon(
                        _FileNode(
                          name: fileName,
                          path: filePath,
                          isDirectory: false,
                        ),
                      ),
                      size: 14,
                      color: fgColor,
                    ),
                    kOpenHandHGap6,
                    Text(
                      fileName,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: isActive
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: fgColor,
                        letterSpacing: 0,
                      ),
                    ),
                    kOpenHandHGap6,
                    if (isDirty)
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colorScheme.primary,
                        ),
                      ),
                    OpenHandTapRegion(
                      onTap: onClose,
                      child: Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: fgColor.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 把 LSP 请求阶段抛出的常见异常翻译成更具操作性的中英双语文案，
/// 避免在编辑器结果栏里直接展示 `TimeoutException: ...` 这种栈底信息。
String _friendlyLspError(Object error) {
  if (error is TimeoutException) {
    return StructuredErrorText.format(
      title: StructuredErrorText.pick(
        zh: 'LSP 请求超时',
        en: 'LSP request timed out',
      ),
      reason: StructuredErrorText.pick(
        zh: 'LSP 服务器在限定时间内没有返回结果，可能是分析进程被大文件、索引重建或死锁卡住。',
        en: 'The LSP server did not return a result within the allowed time. A large file, index rebuild, or deadlock may have stalled the analysis process.',
      ),
      try_: StructuredErrorText.pick(
        zh:
            '· 等待索引完成后再试一次\n'
            '· 重启 LSP 服务器（设置 → 编辑器 → LSP）\n'
            '· 关闭过大的工作区或减少同时打开的项目\n'
            '· 升级或重新安装该语言的 LSP',
        en:
            '· Wait for indexing to finish and try again\n'
            '· Restart the LSP server (Settings → Editor → LSP)\n'
            '· Close very large workspaces or reduce the number of open projects\n'
            '· Upgrade or reinstall the language server',
      ),
      raw: '$error',
    );
  }
  if (error is UnsupportedError) {
    return StructuredErrorText.format(
      title: StructuredErrorText.pick(
        zh: 'LSP 操作不支持',
        en: 'Unsupported LSP operation',
      ),
      reason: StructuredErrorText.pick(
        zh: '当前 LSP 服务器没有声明这项能力，可能需要更换或升级语言服务器。',
        en: 'The current LSP server did not declare support for this operation. You may need to switch to a different language server or upgrade it.',
      ),
      try_: StructuredErrorText.pick(
        zh: '· 更换语言服务器后重试\n· 升级当前 LSP 或相关扩展',
        en:
            '· Retry with another language server\n'
            '· Upgrade the current LSP or related extension',
      ),
      raw: '$error',
    );
  }
  // StateError 通常来自 _resolutionErrorMessage(backend) 或 "too many
  // pending requests" — 它们的 message 已经是用户可读的描述，直接透传
  // 即可，避免重复包装一层。
  if (error is StateError) {
    return error.message;
  }
  return '$error';
}

// ── 本文件内复用的文案 ──
// 同一标签在本文件里出现两次以上；抽成函数后措辞只有一个改动点。

String _homeProgramminNewNameLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '新名称',
    zhHant: '新名稱',
    en: 'New name',
    fr: 'Nouveau nom',
    de: 'Neuer Name',
    ja: '新しい名前',
  );
}
