import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/state/settings_controller.dart';
import '../../app/support/openhand_paths.dart';
import '../../l10n/app_localizations.dart';
import 'data/memory_store.dart';
import 'memory_controller.dart';
import 'model/user_memory_entry.dart';

enum _MemoryCardAction { edit, delete }

class MemoryView extends StatelessWidget {
  const MemoryView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final memoryController = context.watch<MemoryController>();
    final settingsController = context.watch<SettingsController>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 980;
            final actions = Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.tonalIcon(
                  onPressed: memoryController.isLoading
                      ? null
                      : () => memoryController.refresh(),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(l10n.memoryRefresh),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openDirectory(context),
                  icon: const Icon(Icons.folder_open_rounded),
                  label: Text(l10n.memoryOpenDirectory),
                ),
                FilledButton.icon(
                  onPressed: () => _showMemoryDialog(context),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(l10n.memoryNewEntry),
                ),
              ],
            );

            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MemoryPageHeader(
                    title: l10n.memoryPageTitle,
                    subtitle: l10n.memoryPageSubtitle,
                  ),
                  const SizedBox(height: 20),
                  actions,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _MemoryPageHeader(
                    title: l10n.memoryPageTitle,
                    subtitle: l10n.memoryPageSubtitle,
                  ),
                ),
                const SizedBox(width: 20),
                Flexible(child: actions),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        if (!settingsController.memoryEnabled) ...[
          _MemoryInfoCard(
            icon: Icons.toggle_off_rounded,
            title: l10n.memoryDisabledTitle,
            body: l10n.memoryDisabledBody,
          ),
          const SizedBox(height: 16),
        ],
        if (memoryController.persistenceIssue != null) ...[
          _MemoryPersistenceIssueCard(
            issue: memoryController.persistenceIssue!,
            onDismiss: memoryController.clearPersistenceIssue,
          ),
          const SizedBox(height: 16),
        ],
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _buildBody(context, memoryController),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, MemoryController memoryController) {
    final l10n = AppLocalizations.of(context)!;
    if (memoryController.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (memoryController.errorMessage != null) {
      return _MemoryStateCard(
        key: const ValueKey<String>('memory-error'),
        icon: Icons.error_outline_rounded,
        title: l10n.memoryLoadFailedTitle,
        body: memoryController.errorMessage!,
        primaryActionLabel: l10n.memoryRefresh,
        onPrimaryAction: () => memoryController.refresh(),
      );
    }
    if (memoryController.entries.isEmpty) {
      return _MemoryStateCard(
        key: const ValueKey<String>('memory-empty'),
        icon: Icons.psychology_alt_outlined,
        title: l10n.memoryEmptyTitle,
        body: l10n.memoryEmptyBody,
      );
    }

    return ListView.separated(
      key: const ValueKey<String>('memory-list'),
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: memoryController.entries.length,
      separatorBuilder: (context, index) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final entry = memoryController.entries[index];
        return _MemoryEntryCard(
          entry: entry,
          onTap: () => _showMemoryDialog(context, initialEntry: entry),
          onActionSelected: (action) {
            switch (action) {
              case _MemoryCardAction.edit:
                _showMemoryDialog(context, initialEntry: entry);
              case _MemoryCardAction.delete:
                _confirmDeleteMemory(context, entry);
            }
          },
        );
      },
    );
  }

  Future<void> _openDirectory(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await context.read<MemoryController>().openStorageDirectory();
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      _showSnackBar(context, l10n.memoryOperationFailed);
    }
  }

  Future<void> _showMemoryDialog(
    BuildContext context, {
    UserMemoryEntry? initialEntry,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return _MemoryEditorDialog(initialEntry: initialEntry);
      },
    );

    if (submitted != true || !context.mounted) {
      return;
    }
    _showSnackBar(
      context,
      initialEntry == null ? l10n.memoryEntryCreated : l10n.memoryEntryUpdated,
    );
  }

  Future<void> _confirmDeleteMemory(
    BuildContext context,
    UserMemoryEntry entry,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.memoryDeleteConfirmTitle),
          content: Text(l10n.memoryDeleteConfirmBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.commonDelete),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) {
      return;
    }

    final deleted = await context.read<MemoryController>().deleteMemory(entry);
    if (!context.mounted) {
      return;
    }
    if (!deleted) {
      _showSnackBar(context, l10n.memoryOperationFailed);
      return;
    }
    _showSnackBar(context, l10n.memoryEntryDeleted);
  }

  void _showSnackBar(BuildContext context, String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    });
  }
}

class _MemoryEditorDialog extends StatefulWidget {
  const _MemoryEditorDialog({this.initialEntry});

  final UserMemoryEntry? initialEntry;

  @override
  State<_MemoryEditorDialog> createState() => _MemoryEditorDialogState();
}

class _MemoryEditorDialogState extends State<_MemoryEditorDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _contentController;
  late final TextEditingController _tagInputController;
  late final FocusNode _tagInputFocusNode;
  late final List<String> _tags;
  late final KeyEventCallback _tagInputKeyHandler;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(
      text: widget.initialEntry?.content ?? '',
    );
    _tagInputController = TextEditingController();
    _tagInputFocusNode = FocusNode();
    _tags = List<String>.from(widget.initialEntry?.tags ?? const <String>[]);
    _tagInputKeyHandler = _handleTagInputKeyEvent;
    HardwareKeyboard.instance.addHandler(_tagInputKeyHandler);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_tagInputKeyHandler);
    _contentController.dispose();
    _tagInputController.dispose();
    _tagInputFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final title = widget.initialEntry == null
        ? l10n.memoryDialogCreateTitle
        : l10n.memoryDialogEditTitle;

    return PopScope(
      canPop: !_isSaving,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            controller: _contentController,
                            minLines: 7,
                            maxLines: 12,
                            enabled: !_isSaving,
                            decoration: InputDecoration(
                              labelText: l10n.memoryContentField,
                              alignLabelWithHint: true,
                            ),
                            validator: (value) {
                              if (UserMemoryEntry.normalizeContent(
                                value ?? '',
                              ).isEmpty) {
                                return l10n.memoryContentRequired;
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _tagInputController,
                            focusNode: _tagInputFocusNode,
                            enabled: !_isSaving,
                            textInputAction: TextInputAction.done,
                            onChanged: _handleTagInputChanged,
                            onSubmitted: (_) => _addTagsFromInput(),
                            decoration: InputDecoration(
                              labelText: l10n.memoryTagsField,
                              hintText: l10n.memoryTagsHint,
                              suffixIconConstraints: const BoxConstraints(
                                minWidth: 56,
                                minHeight: 40,
                              ),
                              suffixIcon: Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  end: 10,
                                ),
                                child: IconButton(
                                  onPressed: _isSaving
                                      ? null
                                      : _addTagsFromInput,
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    foregroundColor:
                                        colorScheme.onSurfaceVariant,
                                    disabledForegroundColor: colorScheme
                                        .onSurfaceVariant
                                        .withValues(alpha: 0.38),
                                    minimumSize: const Size(36, 36),
                                    maximumSize: const Size(36, 36),
                                    padding: EdgeInsets.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  icon: const Icon(Icons.add_rounded, size: 22),
                                ),
                              ),
                            ),
                          ),
                          if (_tags.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _tags
                                  .map(
                                    (tag) => InputChip(
                                      label: Text(tag),
                                      onDeleted: _isSaving
                                          ? null
                                          : () => _removeTag(tag),
                                    ),
                                  )
                                  .toList(growable: false),
                            ),
                          ],
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              _errorMessage!,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (_isSaving) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: 132,
                      height: 52,
                      child: OutlinedButton(
                        onPressed: _isSaving
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: Text(l10n.commonCancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 132,
                      height: 52,
                      child: FilledButton(
                        onPressed: _isSaving ? null : _handleSave,
                        child: Text(l10n.commonSave),
                      ),
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

  Future<void> _handleSave() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final tags = _commitPendingTags();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final content = _contentController.text;
    final controller = context.read<MemoryController>();

    late final bool saved;
    try {
      saved = widget.initialEntry == null
          ? await controller.createMemory(content: content, tags: tags)
          : await controller.updateMemory(
              widget.initialEntry!,
              content: content,
              tags: tags,
            );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _errorMessage = l10n.memoryOperationFailed;
      });
      return;
    }
    if (!mounted) {
      return;
    }
    if (!saved) {
      setState(() {
        _isSaving = false;
        _errorMessage = l10n.memoryOperationFailed;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  void _addTagsFromInput() {
    if (_isSaving) {
      return;
    }
    final nextTags = _mergedTagsWithInput();
    if (_tagInputController.text.trim().isEmpty &&
        nextTags.length == _tags.length) {
      return;
    }
    setState(() {
      _tags
        ..clear()
        ..addAll(nextTags);
      _tagInputController.clear();
      _errorMessage = null;
    });
  }

  void _removeTag(String tag) {
    if (_isSaving) {
      return;
    }
    setState(() {
      _tags.remove(tag);
      _errorMessage = null;
    });
  }

  List<String> _commitPendingTags() {
    final nextTags = _mergedTagsWithInput();
    final shouldRefreshUi =
        _tagInputController.text.trim().isNotEmpty ||
        nextTags.length != _tags.length;
    if (shouldRefreshUi) {
      setState(() {
        _tags
          ..clear()
          ..addAll(nextTags);
        _tagInputController.clear();
      });
      return List<String>.from(_tags);
    }
    return List<String>.from(_tags);
  }

  List<String> _mergedTagsWithInput() {
    return UserMemoryEntry.normalizeTags(<String>[
      ..._tags,
      ..._splitTagInput(_tagInputController.text),
    ]);
  }

  List<String> _splitTagInput(String value) {
    return value
        .split(RegExp(r'[\n,，;；]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  void _handleTagInputChanged(String value) {
    if (_isSaving || !_containsTagDelimiter(value)) {
      return;
    }
    _addTagsFromInput();
  }

  bool _containsTagDelimiter(String value) {
    return value.contains(RegExp(r'[\n,，;；]'));
  }

  bool _handleTagInputKeyEvent(KeyEvent event) {
    if (!mounted || _isSaving || !_tagInputFocusNode.hasFocus) {
      return false;
    }
    if (event is! KeyDownEvent) {
      return false;
    }
    if (event.logicalKey != LogicalKeyboardKey.backspace) {
      return false;
    }
    if (_tagInputController.text.isNotEmpty || _tags.isEmpty) {
      return false;
    }
    setState(() {
      _tags.removeLast();
      _errorMessage = null;
    });
    return true;
  }
}

class _MemoryPageHeader extends StatelessWidget {
  const _MemoryPageHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.displaySmall),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _MemoryEntryCard extends StatelessWidget {
  const _MemoryEntryCard({
    required this.entry,
    required this.onTap,
    required this.onActionSelected,
  });

  final UserMemoryEntry entry;
  final VoidCallback onTap;
  final ValueChanged<_MemoryCardAction> onActionSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.psychology_alt_outlined,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.preview, style: theme.textTheme.titleLarge),
                        const SizedBox(height: 6),
                        Text(
                          '${l10n.memoryCreatedAtLabel}: ${_formatCreatedAt(context, entry.createdAt)}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          entry.content,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  PopupMenuButton<_MemoryCardAction>(
                    onSelected: onActionSelected,
                    itemBuilder: (context) {
                      return [
                        PopupMenuItem<_MemoryCardAction>(
                          value: _MemoryCardAction.edit,
                          child: Text(l10n.commonEdit),
                        ),
                        PopupMenuItem<_MemoryCardAction>(
                          value: _MemoryCardAction.delete,
                          child: Text(l10n.commonDelete),
                        ),
                      ];
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: const Icon(Icons.person_outline_rounded, size: 18),
                    label: Text(l10n.memoryTypeUser),
                  ),
                  for (final tag in entry.tags)
                    Chip(
                      avatar: const Icon(Icons.sell_outlined, size: 18),
                      label: Text(tag),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatCreatedAt(BuildContext context, DateTime value) {
    final localizations = MaterialLocalizations.of(context);
    final localValue = value.toLocal();
    final date = localizations.formatCompactDate(localValue);
    final time = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(localValue),
      alwaysUse24HourFormat: true,
    );
    return '$date $time';
  }
}

class _MemoryStateCard extends StatelessWidget {
  const _MemoryStateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.primaryActionLabel,
    this.onPrimaryAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? primaryActionLabel;
  final VoidCallback? onPrimaryAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: colorScheme.onPrimaryContainer),
                ),
                const SizedBox(height: 18),
                Text(title, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 10),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (primaryActionLabel != null && onPrimaryAction != null) ...[
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: onPrimaryAction,
                    child: Text(primaryActionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MemoryInfoCard extends StatelessWidget {
  const _MemoryInfoCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      color: colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: colorScheme.onSecondaryContainer),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSecondaryContainer,
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

class _MemoryPersistenceIssueCard extends StatelessWidget {
  const _MemoryPersistenceIssueCard({
    required this.issue,
    required this.onDismiss,
  });

  final MemoryPersistenceIssue issue;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final (title, body) = switch (issue.kind) {
      MemoryPersistenceIssueKind.recoveredInvalidFile => (
        l10n.memoryPersistenceRecoveredTitle,
        '${l10n.memoryPersistenceRecoveredBody}\n${OpenHandPaths.shortenHomePath(issue.filePath)}',
      ),
      MemoryPersistenceIssueKind.sanitizedInvalidContent => (
        l10n.memoryPersistenceSanitizedTitle,
        '${l10n.memoryPersistenceSanitizedBody}\n${OpenHandPaths.shortenHomePath(issue.filePath)}',
      ),
      MemoryPersistenceIssueKind.saveFailed => (
        l10n.memoryPersistenceSaveFailedTitle,
        '${l10n.memoryPersistenceSaveFailedBody}\n${OpenHandPaths.shortenHomePath(issue.filePath)}',
      ),
    };

    return Card(
      color: colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: onDismiss,
              child: Text(
                l10n.settingsPersistenceDismiss,
                style: TextStyle(color: colorScheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
