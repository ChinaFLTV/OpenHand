part of 'openhand_home_page.dart';

/// Dialog shown after selecting the "编程专家" template.
/// Lets the user choose a project root path, with a recent paths dropdown.
class _ProgrammingExpertProjectDialog extends StatefulWidget {
  const _ProgrammingExpertProjectDialog({
    required this.recentProjectPaths,
  });

  final List<String> recentProjectPaths;

  @override
  State<_ProgrammingExpertProjectDialog> createState() =>
      _ProgrammingExpertProjectDialogState();
}

class _ProgrammingExpertProjectDialogState
    extends State<_ProgrammingExpertProjectDialog> {
  final TextEditingController _pathController = TextEditingController();

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _pickDirectory() async {
    final current = _pathController.text.trim();
    final result = await getDirectoryPath(
      initialDirectory: current.isNotEmpty ? current : null,
    );
    if (result != null && mounted) {
      setState(() => _pathController.text = result);
    }
  }

  void _submit() {
    final path = _pathController.text.trim();
    if (path.isEmpty) return;
    Navigator.of(context).pop(path);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isZh =
        Localizations.localeOf(context).languageCode.startsWith('zh');
    final recentPaths = widget.recentProjectPaths;

    return AlertDialog(
      title: Text(isZh ? '选择项目路径' : 'Select Project Path'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isZh
                  ? '请选择或输入项目根目录路径，该路径将作为编程专家的工作空间。'
                  : 'Select or enter the project root path. This will be the workspace for the Programming Expert.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            // Directory picker row
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _pathController,
                    decoration: InputDecoration(
                      labelText: isZh ? '项目根目录' : 'Project Root',
                      hintText: isZh
                          ? '输入或选择项目根目录路径'
                          : 'Enter or browse project root path',
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: isZh ? '浏览文件夹' : 'Browse folder',
                  child: SizedBox(
                    height: 52,
                    width: 44,
                    child: OutlinedButton(
                      onPressed: _pickDirectory,
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        side: BorderSide(
                          color: colorScheme.outline.withValues(alpha: 0.6),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        foregroundColor: colorScheme.onSurfaceVariant,
                      ),
                      child: const Icon(Icons.folder_open_rounded, size: 18),
                    ),
                  ),
                ),
              ],
            ),
            // Recent paths dropdown
            if (recentPaths.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                isZh ? '最近使用' : 'Recent',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: recentPaths.map((path) {
                      final dirName = p.basename(path);
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            setState(() => _pathController.text = path);
                          },
                          onDoubleTap: () {
                            Navigator.of(context).pop(path);
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.folder_rounded,
                                  size: 18,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        dirName,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        path,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color:
                                                  colorScheme.onSurfaceVariant,
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
                    }).toList(growable: false),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          label: isZh ? '取消' : 'Cancel',
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _pathController,
          builder: (context, value, _) {
            final hasValue = value.text.trim().isNotEmpty;
            return OpenHandDialogActionButton.primary(
              onPressed: hasValue ? _submit : null,
              label: isZh ? '确定' : 'Confirm',
            );
          },
        ),
      ],
    );
  }
}

/// Collect unique project root paths from existing programming_expert sessions.
List<String> _collectRecentProjectPaths(List<AiSession> sessions) {
  final seen = <String>{};
  final result = <String>[];
  // Iterate newest-first (sessions are sorted newest-first by convention).
  for (final session in sessions) {
    if (session.templateId != 'programming_expert') continue;
    final config = session.metadata['programming_expert_config'];
    if (config is! Map) continue;
    final projectRoot = '${config['project_root'] ?? ''}'.trim();
    if (projectRoot.isNotEmpty && seen.add(projectRoot)) {
      result.add(projectRoot);
    }
    if (result.length >= 10) break;
  }
  return result;
}
