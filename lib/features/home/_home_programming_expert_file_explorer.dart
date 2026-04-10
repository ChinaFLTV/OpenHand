part of 'openhand_home_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// File Explorer Panel — replaces the navigation sidebar when toggled
// ─────────────────────────────────────────────────────────────────────────────

class _FileExplorerPanel extends StatefulWidget {
  const _FileExplorerPanel({
    required this.rootPath,
    required this.onFileSelected,
    this.activeFilePath,
  });

  final String rootPath;
  final ValueChanged<String> onFileSelected;
  final String? activeFilePath;

  @override
  State<_FileExplorerPanel> createState() => _FileExplorerPanelState();
}

class _FileExplorerPanelState extends State<_FileExplorerPanel> {
  late _FileNode _rootNode;
  bool _loading = true;

  // Clipboard state for cut/copy/paste operations.
  String? _clipboardPath;
  bool _clipboardIsCut = false;

  @override
  void initState() {
    super.initState();
    _rootNode = _FileNode(
      name: p.basename(widget.rootPath),
      path: widget.rootPath,
      isDirectory: true,
    );
    _loadChildren(_rootNode).then((_) {
      if (mounted) {
        setState(() {
          _rootNode.isExpanded = true;
          _loading = false;
        });
        _revealActiveFile();
      }
    });
  }

  @override
  void didUpdateWidget(_FileExplorerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rootPath != widget.rootPath) {
      setState(() {
        _loading = true;
        _rootNode = _FileNode(
          name: p.basename(widget.rootPath),
          path: widget.rootPath,
          isDirectory: true,
        );
      });
      _loadChildren(_rootNode).then((_) {
        if (mounted) {
          setState(() {
            _rootNode.isExpanded = true;
            _loading = false;
          });
          _revealActiveFile();
        }
      });
    } else if (oldWidget.activeFilePath != widget.activeFilePath) {
      _revealActiveFile();
    }
  }

  /// Expand parent directories to make the active file visible in the tree
  /// (similar to IntelliJ IDEA's "scroll from source" behaviour).
  Future<void> _revealActiveFile() async {
    final active = widget.activeFilePath;
    if (active == null || !active.startsWith(widget.rootPath)) return;
    final relative = p.relative(active, from: widget.rootPath);
    final segments = p.split(relative).where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return;

    _FileNode current = _rootNode;
    for (var i = 0; i < segments.length - 1; i++) {
      if (!current.childrenLoaded) await _loadChildren(current);
      final seg = segments[i];
      final match = current.children.where((c) => c.name == seg);
      if (match.isEmpty) return;
      current = match.first;
      current.isExpanded = true;
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadChildren(_FileNode node) async {
    if (!node.isDirectory || node.childrenLoaded) return;
    try {
      final dir = Directory(node.path);
      final entries = await dir.list().toList();
      entries.sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir != bIsDir) return aIsDir ? -1 : 1;
        return p.basename(a.path).toLowerCase().compareTo(
          p.basename(b.path).toLowerCase(),
        );
      });
      final children = <_FileNode>[];
      for (final entry in entries) {
        final name = p.basename(entry.path);
        if (_isHiddenOrIgnored(name)) continue;
        children.add(_FileNode(
          name: name,
          path: entry.path,
          isDirectory: entry is Directory,
        ));
      }
      node.children = children;
      node.childrenLoaded = true;
    } catch (_) {
      node.children = const [];
      node.childrenLoaded = true;
    }
  }

  bool _isHiddenOrIgnored(String name) {
    if (name.startsWith('.')) return true;
    const ignored = {
      'node_modules', 'build', '.dart_tool', '__pycache__',
      '.git', '.idea', '.vscode', 'target', 'dist', '.gradle',
    };
    return ignored.contains(name);
  }

  Future<void> _toggleExpand(_FileNode node) async {
    if (!node.isDirectory) return;
    if (!node.childrenLoaded) {
      await _loadChildren(node);
    }
    setState(() => node.isExpanded = !node.isExpanded);
  }

  Future<void> _refreshNode(_FileNode node) async {
    node.childrenLoaded = false;
    node.children = const [];
    await _loadChildren(node);
    if (mounted) setState(() {});
  }

  Future<void> _refreshRoot() async {
    _rootNode.childrenLoaded = false;
    _rootNode.children = const [];
    await _loadChildren(_rootNode);
    if (mounted) setState(() {});
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
    final isZh =
        Localizations.localeOf(context).languageCode.startsWith('zh');
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
                child: Text(isZh ? '绝对路径' : 'Absolute Path'),
              ),
              const SizedBox(width: 16),
              Text(
                '⇧⌘C',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'name',
          child: Text(isZh ? '文件名' : 'File Name'),
        ),
        PopupMenuItem<String>(
          value: 'content_root',
          child: Text(isZh ? '内容根目录相对路径' : 'Path from Content Root'),
        ),
        PopupMenuItem<String>(
          value: 'repo_root',
          child: Text(isZh ? '仓库根目录相对路径' : 'Path from Repository Root'),
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
    await Clipboard.setData(ClipboardData(text: textToCopy));
  }

  Future<void> _renameNode(_FileNode node) async {
    final controller = TextEditingController(text: node.name);
    final newName = await showAnimatedDialog<String>(
      context: context,
      builder: (dialogContext) {
        final isZh = Localizations.localeOf(dialogContext).languageCode
            .startsWith('zh');
        return AlertDialog(
          title: Text(isZh ? '重命名' : 'Rename'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: isZh ? '输入新名称' : 'Enter new name',
            ),
            onSubmitted: (value) {
              Navigator.of(dialogContext).pop(value.trim());
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(isZh ? '取消' : 'Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(controller.text.trim());
              },
              child: Text(isZh ? '确定' : 'OK'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (newName == null || newName.isEmpty || newName == node.name) return;
    try {
      final parentDir = p.dirname(node.path);
      final newPath = p.join(parentDir, newName);
      if (node.isDirectory) {
        await Directory(node.path).rename(newPath);
      } else {
        await File(node.path).rename(newPath);
      }
      final parent = _findParentNode(_rootNode, node.path) ?? _rootNode;
      await _refreshNode(parent);
    } catch (_) {}
  }

  Future<void> _deleteNode(_FileNode node) async {
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(isZh ? '删除确认' : 'Confirm Delete'),
          content: Text(
            isZh
                ? '确定要删除 "${node.name}" 吗？此操作不可撤销。'
                : 'Are you sure you want to delete "${node.name}"? This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(isZh ? '取消' : 'Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                isZh ? '删除' : 'Delete',
                style: TextStyle(
                  color: Theme.of(dialogContext).colorScheme.error,
                ),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    try {
      if (node.isDirectory) {
        await Directory(node.path).delete(recursive: true);
      } else {
        await File(node.path).delete();
      }
      final parent = _findParentNode(_rootNode, node.path) ?? _rootNode;
      await _refreshNode(parent);
    } catch (_) {}
  }

  Future<void> _pasteToNode(_FileNode node) async {
    final sourcePath = _clipboardPath;
    if (sourcePath == null) return;
    final targetDir = node.isDirectory ? node.path : p.dirname(node.path);
    final name = p.basename(sourcePath);
    final targetPath = p.join(targetDir, name);
    if (targetPath == sourcePath) return;
    try {
      final sourceEntity = FileSystemEntity.typeSync(sourcePath);
      if (sourceEntity == FileSystemEntityType.notFound) return;
      if (_clipboardIsCut) {
        if (sourceEntity == FileSystemEntityType.directory) {
          await Directory(sourcePath).rename(targetPath);
        } else {
          await File(sourcePath).rename(targetPath);
        }
        _clipboardPath = null;
        _clipboardIsCut = false;
      } else {
        if (sourceEntity == FileSystemEntityType.directory) {
          await _copyDirectory(Directory(sourcePath), Directory(targetPath));
        } else {
          await File(sourcePath).copy(targetPath);
        }
      }
      await _refreshRoot();
    } catch (_) {}
  }

  Future<void> _copyDirectory(Directory source, Directory target) async {
    await target.create(recursive: true);
    await for (final entity in source.list()) {
      final name = p.basename(entity.path);
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(p.join(target.path, name)));
      } else if (entity is File) {
        await entity.copy(p.join(target.path, name));
      }
    }
  }

  Future<void> _openInSystemExplorer(_FileNode node) async {
    final target = node.isDirectory ? node.path : p.dirname(node.path);
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [target]);
      } else if (Platform.isWindows) {
        await Process.run('explorer', [target]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [target]);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
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
              Icon(
                Icons.folder_open_rounded,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _rootNode.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Material(
                color: Colors.transparent,
                borderRadius: _borderRadius999,
                child: InkWell(
                  borderRadius: _borderRadius999,
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
            ],
          ),
        ),
        Divider(
          height: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _buildTree(_rootNode.children, 0),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildTree(List<_FileNode> nodes, int depth) {
    final result = <Widget>[];
    for (final node in nodes) {
      result.add(_FileTreeTile(
        node: node,
        depth: depth,
        isActive: widget.activeFilePath == node.path,
        hasClipboard: _clipboardPath != null,
        rootPath: widget.rootPath,
        onTap: () {
          if (node.isDirectory) {
            _toggleExpand(node);
          } else {
            widget.onFileSelected(node.path);
          }
        },
        onContextMenuAction: (action, position) =>
            _handleContextMenuAction(action, node, position),
      ));
      if (node.isDirectory && node.isExpanded) {
        result.addAll(_buildTree(node.children, depth + 1));
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
  List<_FileNode> children = const [];
}

class _FileTreeTile extends StatelessWidget {
  const _FileTreeTile({
    required this.node,
    required this.depth,
    required this.onTap,
    required this.onContextMenuAction,
    required this.rootPath,
    this.isActive = false,
    this.hasClipboard = false,
  });

  final _FileNode node;
  final int depth;
  final VoidCallback onTap;
  final void Function(String action, Offset position) onContextMenuAction;
  final String rootPath;
  final bool isActive;
  final bool hasClipboard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final indent = 16.0 + depth * 16.0;
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');

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
                  const SizedBox(width: 8),
                  Text(isZh ? '重命名' : 'Rename'),
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem<String>(
              value: 'cut',
              child: Row(
                children: [
                  const Icon(Icons.content_cut_rounded, size: 18),
                  const SizedBox(width: 8),
                  Text(isZh ? '剪切' : 'Cut'),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'copy',
              child: Row(
                children: [
                  const Icon(Icons.content_copy_rounded, size: 18),
                  const SizedBox(width: 8),
                  Text(isZh ? '复制' : 'Copy'),
                ],
              ),
            ),
            if (hasClipboard)
              PopupMenuItem<String>(
                value: 'paste',
                child: Row(
                  children: [
                    const Icon(Icons.content_paste_rounded, size: 18),
                    const SizedBox(width: 8),
                    Text(isZh ? '粘贴' : 'Paste'),
                  ],
                ),
              ),
            const PopupMenuDivider(),
            PopupMenuItem<String>(
              value: 'copy_path',
              child: Row(
                children: [
                  const Icon(Icons.link_rounded, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(isZh ? '复制路径/引用' : 'Copy Path/Reference'),
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
                  const SizedBox(width: 8),
                  Text(
                    isZh ? '删除' : 'Delete',
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
                  const SizedBox(width: 8),
                  Text(isZh ? '在系统文件浏览器中打开' : 'Open in System Explorer'),
                ],
              ),
            ),
          ],
        );
        if (selected == null || !context.mounted) return;
        _scheduleOverlayActionAfterMenuDismissal(context, () {
          onContextMenuAction(selected, lastTapPosition!);
        });
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: isActive
                ? BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.35),
                    border: Border(
                      left: BorderSide(
                        color: colorScheme.primary,
                        width: 2.5,
                      ),
                    ),
                  )
                : null,
            padding: EdgeInsets.only(
              left: isActive ? indent - 2.5 : indent,
              right: 8,
              top: 4,
              bottom: 4,
            ),
            child: Row(
              children: [
                if (node.isDirectory)
                  Icon(
                    node.isExpanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.chevron_right_rounded,
                    size: 16,
                    color: isActive
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  )
                else
                  const SizedBox(width: 16),
                const SizedBox(width: 4),
                Icon(
                  _fileExplorerIcon(node),
                  size: 16,
                  color: node.isDirectory
                      ? colorScheme.primary
                      : isActive
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    node.name,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: node.isDirectory
                          ? FontWeight.w600
                          : isActive
                              ? FontWeight.w600
                              : FontWeight.w400,
                      color: isActive
                          ? colorScheme.onPrimaryContainer
                          : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

IconData _fileExplorerIcon(_FileNode node) {
  if (node.isDirectory) return Icons.folder_rounded;
  final ext = p.extension(node.name).toLowerCase();
  return switch (ext) {
    '.dart' => Icons.code_rounded,
    '.py' => Icons.code_rounded,
    '.js' || '.jsx' || '.ts' || '.tsx' => Icons.javascript_rounded,
    '.json' => Icons.data_object_rounded,
    '.yaml' || '.yml' => Icons.settings_rounded,
    '.md' => Icons.article_rounded,
    '.html' || '.htm' => Icons.web_rounded,
    '.css' || '.scss' || '.less' => Icons.palette_rounded,
    '.png' || '.jpg' || '.jpeg' || '.gif' || '.svg' || '.webp' =>
      Icons.image_rounded,
    '.sh' || '.bash' || '.zsh' => Icons.terminal_rounded,
    '.lock' => Icons.lock_rounded,
    '.xml' => Icons.code_rounded,
    '.sql' => Icons.storage_rounded,
    '.go' => Icons.code_rounded,
    '.rs' => Icons.code_rounded,
    '.java' || '.kt' => Icons.code_rounded,
    '.swift' => Icons.code_rounded,
    '.c' || '.cpp' || '.h' || '.hpp' => Icons.code_rounded,
    '.txt' || '.log' => Icons.description_rounded,
    _ => Icons.insert_drive_file_rounded,
  };
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

// ─────────────────────────────────────────────────────────────────────────────
// Code Editor View — IDEA-style editor with Material You Expressive
// ─────────────────────────────────────────────────────────────────────────────

class _CodeEditorView extends StatefulWidget {
  const _CodeEditorView({
    required this.openFiles,
    required this.activeFilePath,
    required this.onTabSelected,
    required this.onTabClosed,
    required this.onCloseAll,
    required this.onReorderTabs,
  });

  final List<String> openFiles;
  final String activeFilePath;
  final ValueChanged<String> onTabSelected;
  final ValueChanged<String> onTabClosed;
  final VoidCallback onCloseAll;
  final void Function(int oldIndex, int newIndex) onReorderTabs;

  @override
  State<_CodeEditorView> createState() => _CodeEditorViewState();
}

class _CodeEditorViewState extends State<_CodeEditorView> {
  final Map<String, String?> _fileContents = {};
  final Map<String, bool> _fileLoading = {};
  final Map<String, bool> _fileDirty = {};
  final Map<String, ScrollController> _scrollControllers = {};
  final Map<String, _HighlightingTextController> _textControllers = {};
  final Map<String, FocusNode> _focusNodes = {};

  @override
  void dispose() {
    for (final controller in _scrollControllers.values) {
      controller.dispose();
    }
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  Future<void> _loadFile(String filePath) async {
    if (_fileContents.containsKey(filePath)) return;
    _fileLoading[filePath] = true;
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final stat = await file.stat();
        if (stat.size > 2 * 1024 * 1024) {
          _fileContents[filePath] = null;
          if (mounted) setState(() => _fileLoading[filePath] = false);
          return;
        }
        final content = await file.readAsString();
        _fileContents[filePath] = content;
        _textControllers[filePath] = _HighlightingTextController(
          text: content,
          language: _editorLanguageFromPath(filePath),
        );
        _focusNodes[filePath] = FocusNode();
        _fileDirty[filePath] = false;
      } else {
        _fileContents[filePath] = null;
      }
    } catch (_) {
      _fileContents[filePath] = null;
    }
    if (mounted) setState(() => _fileLoading[filePath] = false);
  }

  Future<void> _saveFile(String filePath) async {
    final controller = _textControllers[filePath];
    if (controller == null || _fileDirty[filePath] != true) return;
    try {
      await File(filePath).writeAsString(controller.text);
      if (mounted) setState(() => _fileDirty[filePath] = false);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (!_fileContents.containsKey(widget.activeFilePath) &&
        _fileLoading[widget.activeFilePath] != true) {
      _loadFile(widget.activeFilePath);
    }

    return Column(
      children: [
        // ── Tab bar — fully rounded pill container ──
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: const BorderRadius.all(Radius.circular(22)),
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
                      borderRadius: _borderRadius999,
                      child: child,
                    );
                  },
                  onReorder: widget.onReorderTabs,
                  padding: const EdgeInsets.only(
                    left: 6, top: 5, bottom: 5, right: 2,
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
                        onClose: () =>
                            widget.onTabClosed(widget.openFiles[i]),
                      ),
                  ],
                ),
              ),
              // Save button
              if (_fileDirty[widget.activeFilePath] == true) ...[
                _EditorActionButton(
                  tooltip: _localizedText(
                    context,
                    zh: '保存文件',
                    en: 'Save file',
                  ),
                  icon: Icons.save_rounded,
                  color: colorScheme.primary,
                  onPressed: () => _saveFile(widget.activeFilePath),
                ),
              ],
              // Close all button
              _EditorActionButton(
                tooltip: _localizedText(
                  context,
                  zh: '关闭编辑器，返回会话',
                  en: 'Close editor, return to session',
                ),
                icon: Icons.close_rounded,
                color: colorScheme.onSurfaceVariant,
                onPressed: widget.onCloseAll,
              ),
              const SizedBox(width: 6),
            ],
          ),
        ),
        // ── Gap between tab bar and editor ──
        const SizedBox(height: 6),
        // ── Editor content — fully rounded container ──
        Expanded(
          child: Container(
            width: double.infinity,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: const BorderRadius.all(Radius.circular(16)),
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
                // ── Code content ──
                Expanded(
                  child: RepaintBoundary(
                    child: _buildEditorContent(
                      widget.activeFilePath,
                      theme,
                      colorScheme,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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
      final isZh =
          Localizations.localeOf(context).languageCode.startsWith('zh');
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              isZh ? '无法加载文件' : 'Unable to load file',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
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
    final language = _editorLanguageFromPath(filePath);

    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.keyS &&
            (HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed)) {
          _saveFile(filePath);
        }
      },
      child: _SyntaxHighlightEditor(
        controller: textController,
        scrollController: scrollController,
        focusNode: focusNode,
        language: language,
        onChanged: (value) {
          if (!mounted) return;
          setState(() => _fileDirty[filePath] = true);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Breadcrumb path bar — clickable segments showing directory contents
// ---------------------------------------------------------------------------

class _EditorBreadcrumb extends StatelessWidget {
  const _EditorBreadcrumb({
    required this.filePath,
    this.onNavigateToFile,
  });

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
            _fileExplorerIcon(_FileNode(
              name: p.basename(filePath),
              path: filePath,
              isDirectory: false,
            )),
            size: 13,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 6),
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
                        color: colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.6),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 12,
                        color: colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.3),
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
                          color: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.3),
                        ),
                      ),
                    _BreadcrumbSegment(
                      name: segments[i],
                      isLast: i == segments.length - 1,
                      dirPath: i == segments.length - 1
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
    required this.dirPath,
    this.onNavigateToFile,
  });

  final String name;
  final bool isLast;
  final String dirPath;
  final ValueChanged<String>? onNavigateToFile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        hoverColor: colorScheme.primary.withValues(alpha: 0.06),
        onTap: () => _showDirectoryPopup(context),
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

  Future<void> _showDirectoryPopup(BuildContext context) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return;
    List<FileSystemEntity> entries;
    try {
      entries = await dir.list().toList();
    } catch (_) {
      return;
    }
    entries.sort((a, b) {
      final aIsDir = a is Directory;
      final bIsDir = b is Directory;
      if (aIsDir != bIsDir) return aIsDir ? -1 : 1;
      return p.basename(a.path).toLowerCase().compareTo(
            p.basename(b.path).toLowerCase(),
          );
    });
    final filtered = entries
        .where((e) => !p.basename(e.path).startsWith('.'))
        .take(50)
        .toList();
    if (filtered.isEmpty || !context.mounted) return;
    final rb = context.findRenderObject() as RenderBox?;
    if (rb == null) return;
    final offset = rb.localToGlobal(Offset(0, rb.size.height));
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selected = await showAnimatedMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + 2,
        offset.dx,
        offset.dy + 2,
      ),
      items: filtered.map((entry) {
        final entryName = p.basename(entry.path);
        final isDir = entry is Directory;
        return PopupMenuItem<String>(
          value: entry.path,
          height: 36,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _fileExplorerIcon(_FileNode(
                  name: entryName,
                  path: entry.path,
                  isDirectory: isDir,
                )),
                size: 15,
                color: isDir
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                entryName,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: isDir ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        );
      }).toList().cast<PopupMenuEntry<String>>(),
    );
    if (selected == null || !context.mounted) return;
    if (!FileSystemEntity.isDirectorySync(selected)) {
      onNavigateToFile?.call(selected);
    }
  }
}

// ---------------------------------------------------------------------------
// Editor action button (save / close)
// ---------------------------------------------------------------------------

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
        borderRadius: _borderRadius999,
        child: InkWell(
          borderRadius: _borderRadius999,
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

// ---------------------------------------------------------------------------
// Syntax-highlighted editable editor widget
// ---------------------------------------------------------------------------

class _HighlightingTextController extends TextEditingController {
  _HighlightingTextController({super.text, this.language});

  _CodeSyntaxHighlighter? highlighter;
  String? language;

  // ── Highlight cache ──
  TextSpan? _cachedSpan;
  String? _lastText;
  int? _lastHighlighterHash;
  Timer? _debounceTimer;

  /// Beyond this length, skip syntax highlighting entirely.
  static const _maxHighlightLength = 200 * 1024;

  /// Beyond this length, debounce re-highlighting during rapid edits.
  static const _debounceLength = 30 * 1024;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (highlighter == null || text.length > _maxHighlightLength) {
      return TextSpan(text: text, style: style);
    }
    final hlHash = identityHashCode(highlighter);
    if (_cachedSpan != null &&
        _lastText == text &&
        _lastHighlighterHash == hlHash) {
      return _cachedSpan!;
    }
    // For large files, return plain text immediately and schedule a delayed
    // re-highlight so that rapid keystrokes do not trigger expensive parsing
    // on every frame.
    if (text.length > _debounceLength && _cachedSpan != null) {
      // The stale cached span was built for an older version of the text
      // and cannot be reused directly (it would not match the current text
      // length).  Return unstyled text while waiting for the debounce.
      _scheduleDelayedHighlight();
      return TextSpan(text: text, style: style);
    }
    _rebuildHighlight();
    return _cachedSpan ?? TextSpan(text: text, style: style);
  }

  void _rebuildHighlight() {
    if (highlighter == null) return;
    _cachedSpan = highlighter!.build(
      text,
      language: language,
      allowAutoDetection: language == null,
    );
    _lastText = text;
    _lastHighlighterHash = identityHashCode(highlighter);
  }

  void _scheduleDelayedHighlight() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      if (highlighter == null) return;
      _rebuildHighlight();
      notifyListeners();
    });
  }

  void invalidateHighlightCache() {
    _cachedSpan = null;
    _lastText = null;
    _lastHighlighterHash = null;
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
  });

  final _HighlightingTextController controller;
  final ScrollController scrollController;
  final FocusNode focusNode;
  final String? language;
  final ValueChanged<String> onChanged;

  @override
  State<_SyntaxHighlightEditor> createState() =>
      _SyntaxHighlightEditorState();
}

class _SyntaxHighlightEditorState extends State<_SyntaxHighlightEditor> {
  late final ScrollController _lineNumberScrollController;
  bool _darkSurface = false;

  static const _editorFontSize = 13.0;
  static const _editorLineHeight = 1.55;
  static const _lineExtent = _editorFontSize * _editorLineHeight;
  static const _editorStyle = TextStyle(
    fontFamily: 'JetBrains Mono, Menlo, Consolas, monospace',
    fontSize: _editorFontSize,
    height: _editorLineHeight,
    letterSpacing: 0,
  );

  @override
  void initState() {
    super.initState();
    _lineNumberScrollController = ScrollController();
    widget.scrollController.addListener(_syncLineNumbers);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_syncLineNumbers);
    _lineNumberScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_SyntaxHighlightEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_syncLineNumbers);
      widget.scrollController.addListener(_syncLineNumbers);
    }
  }

  void _syncLineNumbers() {
    if (!_lineNumberScrollController.hasClients) return;
    final offset = widget.scrollController.offset;
    final max = _lineNumberScrollController.position.maxScrollExtent;
    _lineNumberScrollController.jumpTo(offset.clamp(0.0, max));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    final darkSurface = brightness == Brightness.dark;
    if (widget.controller.highlighter == null || darkSurface != _darkSurface) {
      _darkSurface = darkSurface;
      widget.controller.highlighter = _CodeSyntaxHighlighter(
        baseStyle: _editorStyle,
        darkSurface: darkSurface,
      );
      widget.controller.invalidateHighlightCache();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final text = widget.controller.text;
    final lineCount = '\n'.allMatches(text).length + 1;
    final digitCount = '$lineCount'.length;
    final lineNumberWidth = (digitCount * 8.5) + 32;

    // Suppress platform-generated scrollbars per-widget so that only the
    // single explicit Scrollbar around the code area is visible.
    final noScrollbarBehavior =
        ScrollConfiguration.of(context).copyWith(scrollbars: false);

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
                    style: TextStyle(
                      fontFamily:
                          'JetBrains Mono, Menlo, Consolas, monospace',
                      fontSize: 12,
                      height: _editorLineHeight,
                      color: colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.35),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        // ── Code area — single explicit scrollbar only ──
        Expanded(
          child: Scrollbar(
            controller: widget.scrollController,
            thumbVisibility: true,
            child: ScrollConfiguration(
              behavior: noScrollbarBehavior,
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                maxLines: null,
                expands: true,
                scrollController: widget.scrollController,
                style: _editorStyle,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.only(
                    top: 10,
                    bottom: 10,
                    left: 8,
                    right: 12,
                  ),
                  isDense: true,
                  isCollapsed: true,
                ),
                onChanged: widget.onChanged,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Editor tab — Material You Expressive pill tab
// ---------------------------------------------------------------------------

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
  });

  final int index;
  final String fileName;
  final String filePath;
  final bool isActive;
  final bool isDirty;
  final VoidCallback onTap;
  final VoidCallback onClose;

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
        child: Material(
          color: isActive
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: _borderRadius999,
          elevation: isActive ? 1 : 0,
          shadowColor: colorScheme.shadow.withValues(alpha: 0.15),
          child: InkWell(
            onTap: onTap,
            borderRadius: _borderRadius999,
            overlayColor: WidgetStatePropertyAll<Color>(
              colorScheme.primary.withValues(alpha: 0.08),
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _fileExplorerIcon(_FileNode(
                      name: fileName,
                      path: filePath,
                      isDirectory: false,
                    )),
                    size: 14,
                    color: fgColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    fileName,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight:
                          isActive ? FontWeight.w700 : FontWeight.w500,
                      color: fgColor,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: onClose,
                    child: isDirty
                        ? Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colorScheme.primary,
                            ),
                          )
                        : Icon(
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
    );
  }
}
