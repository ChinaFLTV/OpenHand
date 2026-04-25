import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/state/settings_controller.dart';
import '../../app/support/openhand_paths.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/animated_dialog.dart';
import '../../shared/widgets/animated_menu.dart';
import '../../shared/widgets/appear_once.dart';
import 'data/memory_store.dart';
import 'memory_controller.dart';
import 'model/user_memory_entry.dart';

enum _MemoryCardAction { edit, delete }

const int _memoryTagPreviewLimit = 8;

enum _MemoryDisplayItemKind { profile, autoLearned, regular }

class _MemoryDisplayItem {
  const _MemoryDisplayItem._({
    required this.kind,
    this.entry,
    this.entries = const <UserMemoryEntry>[],
  });

  const _MemoryDisplayItem.profile(UserMemoryEntry entry)
    : this._(kind: _MemoryDisplayItemKind.profile, entry: entry);

  const _MemoryDisplayItem.autoLearned(List<UserMemoryEntry> entries)
    : this._(kind: _MemoryDisplayItemKind.autoLearned, entries: entries);

  const _MemoryDisplayItem.regular(UserMemoryEntry entry)
    : this._(kind: _MemoryDisplayItemKind.regular, entry: entry);

  final _MemoryDisplayItemKind kind;
  final UserMemoryEntry? entry;
  final List<UserMemoryEntry> entries;
}

class MemoryView extends StatelessWidget {
  const MemoryView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final memorySnapshot = context
        .select<
          MemoryController,
          ({
            bool isLoading,
            String? errorMessage,
            List<UserMemoryEntry> entries,
            MemoryPersistenceIssue? persistenceIssue,
          })
        >((controller) {
          return (
            isLoading: controller.isLoading,
            errorMessage: controller.errorMessage,
            entries: controller.entries,
            persistenceIssue: controller.persistenceIssue,
          );
        });
    final memoryController = context.read<MemoryController>();
    final memoryEnabled = context.select<SettingsController, bool>(
      (controller) => controller.memoryEnabled,
    );

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
                  onPressed: memorySnapshot.isLoading
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
        if (!memoryEnabled) ...[
          _MemoryInfoCard(
            icon: Icons.toggle_off_rounded,
            title: l10n.memoryDisabledTitle,
            body: l10n.memoryDisabledBody,
          ),
          const SizedBox(height: 16),
        ],
        if (memorySnapshot.persistenceIssue != null) ...[
          _MemoryPersistenceIssueCard(
            issue: memorySnapshot.persistenceIssue!,
            onDismiss: memoryController.clearPersistenceIssue,
          ),
          const SizedBox(height: 16),
        ],
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _buildBody(
              context,
              isLoading: memorySnapshot.isLoading,
              errorMessage: memorySnapshot.errorMessage,
              entries: memorySnapshot.entries,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required bool isLoading,
    required String? errorMessage,
    required List<UserMemoryEntry> entries,
  }) {
    final l10n = AppLocalizations.of(context)!;
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (errorMessage != null) {
      return _MemoryStateCard(
        key: const ValueKey<String>('memory-error'),
        icon: Icons.error_outline_rounded,
        title: l10n.memoryLoadFailedTitle,
        body: errorMessage,
        primaryActionLabel: l10n.memoryRefresh,
        onPrimaryAction: () => context.read<MemoryController>().refresh(),
      );
    }
    if (entries.isEmpty) {
      return _MemoryStateCard(
        key: const ValueKey<String>('memory-empty'),
        icon: Icons.psychology_alt_outlined,
        title: l10n.memoryEmptyTitle,
        body: l10n.memoryEmptyBody,
      );
    }

    UserMemoryEntry? profile;
    final autoLearned = <UserMemoryEntry>[];
    final regular = <UserMemoryEntry>[];
    for (final entry in entries) {
      if (entry.type == UserMemoryEntry.userProfileType && profile == null) {
        profile = entry;
        continue;
      }
      if (entry.isAutoLearned) {
        autoLearned.add(entry);
        continue;
      }
      regular.add(entry);
    }

    final items = <_MemoryDisplayItem>[];
    if (profile != null) {
      items.add(_MemoryDisplayItem.profile(profile));
    }
    if (autoLearned.isNotEmpty) {
      items.add(_MemoryDisplayItem.autoLearned(autoLearned));
    }
    for (final entry in regular) {
      items.add(_MemoryDisplayItem.regular(entry));
    }

    return ListView.separated(
      key: const ValueKey<String>('memory-list'),
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: items.length,
      cacheExtent: 600,
      separatorBuilder: (context, index) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final item = items[index];
        switch (item.kind) {
          case _MemoryDisplayItemKind.profile:
            final entry = item.entry!;
            return AppearOnce(
              key: ValueKey<String>('memory-profile-appear-${entry.id}'),
              child: RepaintBoundary(
                child: _MemoryEntryCard(
                  key: ValueKey<String>('memory-profile-${entry.id}'),
                  entry: entry,
                  isProfile: true,
                  onTap: () =>
                      _showMemoryDialog(context, initialEntry: entry),
                  onActionSelected: (action) {
                    switch (action) {
                      case _MemoryCardAction.edit:
                        _showMemoryDialog(context, initialEntry: entry);
                      case _MemoryCardAction.delete:
                        _confirmDeleteMemory(context, entry);
                    }
                  },
                ),
              ),
            );
          case _MemoryDisplayItemKind.autoLearned:
            return AppearOnce(
              key: const ValueKey<String>('memory-auto-learned-appear'),
              child: RepaintBoundary(
                child: _AutoLearnedSection(
                  key: const PageStorageKey<String>(
                    'memory-auto-learned-section',
                  ),
                  entries: item.entries,
                  onTapEntry: (entry) =>
                      _showMemoryDialog(context, initialEntry: entry),
                  onActionSelected: (entry, action) {
                    switch (action) {
                      case _MemoryCardAction.edit:
                        _showMemoryDialog(context, initialEntry: entry);
                      case _MemoryCardAction.delete:
                        _confirmDeleteMemory(context, entry);
                    }
                  },
                ),
              ),
            );
          case _MemoryDisplayItemKind.regular:
            final entry = item.entry!;
            return AppearOnce(
              key: ValueKey<String>('memory-entry-appear-${entry.id}'),
              child: RepaintBoundary(
                child: _MemoryEntryCard(
                  key: ValueKey<String>('memory-entry-${entry.id}'),
                  entry: entry,
                  onTap: () =>
                      _showMemoryDialog(context, initialEntry: entry),
                  onActionSelected: (action) {
                    switch (action) {
                      case _MemoryCardAction.edit:
                        _showMemoryDialog(context, initialEntry: entry);
                      case _MemoryCardAction.delete:
                        _confirmDeleteMemory(context, entry);
                    }
                  },
                ),
              ),
            );
        }
      },
    );
  }

  Future<void> _openDirectory(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await context.read<MemoryController>().openStorageDirectory();
    } catch (e) {
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
    final submitted = await showAnimatedDialog<bool>(
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
    final isProfile = entry.isUserProfile;
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) {
        if (isProfile) {
          return AlertDialog(
            title: Text(l10n.memoryDeleteConfirmTitle),
            content: const Text(
              '用户画像将被删除。Self-learning will recreate this on next cycle.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Delete anyway'),
              ),
            ],
          );
        }
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
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(
      text: widget.initialEntry?.content ?? '',
    );
    _tagInputController = TextEditingController();
    _tagInputFocusNode = FocusNode(onKeyEvent: _handleTagInputKeyEvent);
    _tags = List<String>.from(widget.initialEntry?.tags ?? const <String>[]);
  }

  @override
  void dispose() {
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
      if (widget.initialEntry == null) {
        saved = await controller.createMemory(content: content, tags: tags);
      } else if (widget.initialEntry!.isUserProfile) {
        await controller.upsertUserProfile(content: content, tags: tags);
        saved = true;
      } else {
        saved = await controller.updateMemory(
          widget.initialEntry!,
          content: content,
          tags: tags,
        );
      }
    } catch (e) {
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

  KeyEventResult _handleTagInputKeyEvent(FocusNode node, KeyEvent event) {
    if (!mounted || _isSaving || !node.hasFocus) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey != LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }
    if (_tagInputController.text.isNotEmpty || _tags.isEmpty) {
      return KeyEventResult.ignored;
    }
    setState(() {
      _tags.removeLast();
      _errorMessage = null;
    });
    return KeyEventResult.handled;
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
    super.key,
    required this.entry,
    required this.onTap,
    required this.onActionSelected,
    this.isProfile = false,
  });

  final UserMemoryEntry entry;
  final VoidCallback onTap;
  final ValueChanged<_MemoryCardAction> onActionSelected;
  final bool isProfile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final isAutoLearned = entry.isAutoLearned;
    final displayTags = entry.tags
        .where(
          (tag) =>
              !isAutoLearned ||
              tag.toLowerCase() != UserMemoryEntry.autoLearnedTag.toLowerCase(),
        )
        .toList(growable: false);
    final visibleTags = displayTags
        .take(_memoryTagPreviewLimit)
        .toList(growable: false);
    final hiddenTagCount = displayTags.length - visibleTags.length;

    return Card(
      clipBehavior: Clip.antiAlias,
      color: isProfile
          ? colorScheme.primaryContainer.withValues(alpha: 0.35)
          : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isProfile) ...[
                Text(
                  'User Profile · 用户画像',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
              ],
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
                      isProfile
                          ? Icons.account_circle_outlined
                          : Icons.psychology_alt_outlined,
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
                  AnimatedPopupMenuButton<_MemoryCardAction>(
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
                    avatar: Icon(
                      isProfile
                          ? Icons.account_circle_outlined
                          : Icons.person_outline_rounded,
                      size: 18,
                    ),
                    label: Text(isProfile ? '用户画像' : l10n.memoryTypeUser),
                  ),
                  if (isAutoLearned)
                    const Chip(
                      avatar: Icon(Icons.auto_awesome_outlined, size: 18),
                      label: Text(UserMemoryEntry.autoLearnedTag),
                    ),
                  for (final tag in visibleTags)
                    Chip(
                      avatar: const Icon(Icons.sell_outlined, size: 18),
                      label: Text(tag),
                    ),
                  if (hiddenTagCount > 0)
                    Chip(
                      avatar: const Icon(Icons.more_horiz_rounded, size: 18),
                      label: Text('+$hiddenTagCount'),
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

class _AutoLearnedSection extends StatefulWidget {
  const _AutoLearnedSection({
    super.key,
    required this.entries,
    required this.onTapEntry,
    required this.onActionSelected,
  });

  final List<UserMemoryEntry> entries;
  final ValueChanged<UserMemoryEntry> onTapEntry;
  final void Function(UserMemoryEntry entry, _MemoryCardAction action)
  onActionSelected;

  @override
  State<_AutoLearnedSection> createState() => _AutoLearnedSectionState();
}

class _AutoLearnedSectionState extends State<_AutoLearnedSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      color: colorScheme.secondaryContainer.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome_outlined, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '自主学习 · Auto-learned (${widget.entries.length})',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          // Smoothly grow / shrink the auto-learned drawer.  AnimatedSize is
          // a RenderObject animation (not ticker-based), so it composes
          // safely with the surrounding ListView.separated.  We pair it with
          // an AnimatedOpacity for a coordinated fade so the bottom edge
          // does not appear to "wipe" the cards in.
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _expanded ? 1.0 : 0.0,
              curve: Curves.easeOut,
              child: _expanded
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                          child: SizedBox(
                            height: math.min(
                              520.0,
                              widget.entries.length * 132.0,
                            ),
                            child: ListView.separated(
                              primary: false,
                              padding: EdgeInsets.zero,
                              itemCount: widget.entries.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final entry = widget.entries[index];
                                return _MemoryEntryCard(
                                  key: ValueKey<String>(
                                    'memory-autolearned-${entry.id}',
                                  ),
                                  entry: entry,
                                  onTap: () => widget.onTapEntry(entry),
                                  onActionSelected: (action) =>
                                      widget.onActionSelected(entry, action),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ),
        ],
      ),
    );
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
