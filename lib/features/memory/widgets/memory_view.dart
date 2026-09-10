import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/state/settings_controller.dart';
import '../../../app/support/openhand_paths.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/appear_once.dart';
import '../../../shared/ui/feature_page_shell.dart';
import '../../../shared/ui/feature_state_card.dart';
import '../../../shared/ui/list_removal_transition.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_form_fields.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/persistence_issue_card.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/localized_text.dart';
import '../../ai/index.dart'
    show
        AiResourceUsageKind,
        resourceUsageStatisticsButton,
        showResourceUsageStatisticsDialog;
import '../data/memory_store.dart';
import '../memory_controller.dart';
import '../model/user_memory_entry.dart';

enum _MemoryCardAction { edit, delete }

const int _memoryTagPreviewLimit = 8;

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
            bool isQuotaRecoveryMode,
          })
        >((controller) {
          return (
            isLoading: controller.isLoading,
            errorMessage: controller.errorMessage,
            entries: controller.entries,
            persistenceIssue: controller.persistenceIssue,
            isQuotaRecoveryMode: controller.isQuotaRecoveryMode,
          );
        });
    final memoryController = context.read<MemoryController>();
    final memoryEnabled = context.select<SettingsController, bool>(
      (controller) => controller.memoryEnabled,
    );

    final actions = FeaturePageToolbar(
      spacing: 12,
      primaryActions: [
        FilledButton.tonalIcon(
          onPressed: memorySnapshot.isLoading ? null : memoryController.refresh,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(l10n.memoryRefresh),
        ),
        resourceUsageStatisticsButton(
          context,
          onPressed: () => showResourceUsageStatisticsDialog(
            context,
            kind: AiResourceUsageKind.memory,
            resourceLabels: <String, String>{
              for (final entry in memorySnapshot.entries)
                entry.id: entry.title.trim().isEmpty
                    ? entry.type
                    : entry.title.trim(),
            },
          ),
        ),
        FilledButton.icon(
          onPressed: () => _openDirectory(context),
          icon: const Icon(Icons.folder_open_rounded),
          label: Text(l10n.memoryOpenDirectory),
        ),
        FilledButton.icon(
          onPressed:
              memorySnapshot.isLoading || memorySnapshot.isQuotaRecoveryMode
              ? null
              : () => _showMemoryDialog(context),
          icon: const Icon(Icons.add_rounded),
          label: Text(l10n.memoryNewEntry),
        ),
      ],
    );

    return FeaturePageShell(
      title: l10n.memoryPageTitle,
      subtitle: l10n.memoryPageSubtitle,
      actions: actions,
      headerFlex: 2,
      actionsFlex: 3,
      successSignal: memoryController.saveSuccessSignal,
      notices: [
        if (!memoryEnabled)
          FeatureStateCard.inline(
            icon: Icons.toggle_off_rounded,
            tone: FeatureStateTone.secondary,
            title: l10n.memoryDisabledTitle,
            body: l10n.memoryDisabledBody,
          ),
        if (memorySnapshot.isQuotaRecoveryMode)
          FeatureStateCard.inline(
            icon: Icons.warning_amber_rounded,
            tone: FeatureStateTone.secondary,
            title: l10n.memoryQuotaRecoveryTitle,
            body: l10n.memoryQuotaRecoveryBody,
          ),
        if (memorySnapshot.persistenceIssue != null)
          _MemoryPersistenceIssueCard(
            issue: memorySnapshot.persistenceIssue!,
            onDismiss: memoryController.clearPersistenceIssue,
          ),
      ],
      body: _buildBody(
        context,
        isLoading: memorySnapshot.isLoading,
        errorMessage: memorySnapshot.errorMessage,
        entries: memorySnapshot.entries,
      ),
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
      return FeatureStateCard.centered(
        key: const ValueKey<String>('memory-error'),
        icon: Icons.error_outline_rounded,
        tone: FeatureStateTone.error,
        title: l10n.memoryLoadFailedTitle,
        body: l10n.memoryLoadFailedBody,
        action: OpenHandDialogActionButton.primary(
          onPressed: () => context.read<MemoryController>().refresh(),
          label: l10n.memoryRefresh,
        ),
      );
    }
    if (entries.isEmpty) {
      return FeatureStateCard.centered(
        key: const ValueKey<String>('memory-empty'),
        icon: Icons.psychology_alt_outlined,
        title: l10n.memoryEmptyTitle,
        body: l10n.memoryEmptyBody,
      );
    }

    // 用户画像条目已迁移至 全局设置 → AI 设置 → 会话设置 中独立
    // 维护，记忆面板不再展示，仅在分流时跳过首个 userProfile 条目。
    final autoLearned = <UserMemoryEntry>[];
    final regular = <UserMemoryEntry>[];
    var profileSkipped = false;
    for (final entry in entries) {
      if (!profileSkipped && entry.type == UserMemoryEntry.userProfileType) {
        profileSkipped = true;
        continue;
      }
      if (entry.isAutoLearned) {
        autoLearned.add(entry);
        continue;
      }
      regular.add(entry);
    }

    final items = <UserMemoryEntry>[...autoLearned, ...regular];
    if (items.isEmpty) {
      return FeatureStateCard.centered(
        key: const ValueKey<String>('memory-empty-after-filter'),
        icon: Icons.psychology_alt_outlined,
        title: l10n.memoryEmptyTitle,
        body: l10n.memoryEmptyBody,
      );
    }

    return OpenHandRemovableListScope(
      builder: (context, removal) => ListView.separated(
        scrollCacheExtent: const ScrollCacheExtent.pixels(600),
        key: const ValueKey<String>('memory-list'),
        padding: const EdgeInsets.fromLTRB(0, 2, 0, 12),
        itemCount: items.length,
        separatorBuilder: (context, index) => kOpenHandGap14,
        itemBuilder: (context, index) {
          final entry = items[index];
          final keyPrefix = entry.isAutoLearned
              ? 'memory-auto-learned'
              : 'memory-entry';
          return SettingsAwareAppearOnce(
            key: ValueKey<String>('$keyPrefix-appear-${entry.id}'),
            child: RepaintBoundary(
              child: OpenHandListRemovalTransition(
                collapsed: removal.isRemoving(entry.id),
                child: _MemoryEntryCard(
                  key: ValueKey<String>('$keyPrefix-${entry.id}'),
                  entry: entry,
                  onTap: () => _showMemoryDialog(context, initialEntry: entry),
                  onActionSelected: (action) {
                    switch (action) {
                      case _MemoryCardAction.edit:
                        _showMemoryDialog(context, initialEntry: entry);
                      case _MemoryCardAction.delete:
                        _confirmDeleteMemory(context, removal, entry);
                    }
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openDirectory(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await context.read<MemoryController>().openStorageDirectory();
    } catch (e) {
      if (!context.mounted) return;
      flashOpenHandErrorOnCatch(context, l10n.memoryOperationFailed);
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
    flashOpenHandSnack(
      context,
      initialEntry == null ? l10n.memoryEntryCreated : l10n.memoryEntryUpdated,
      kind: OpenHandSnackKind.success,
    );
  }

  Future<void> _confirmDeleteMemory(
    BuildContext context,
    OpenHandListRemoval removal,
    UserMemoryEntry entry,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: l10n.memoryDeleteConfirmTitle,
      message: l10n.memoryDeleteConfirmBody,
      cancelLabel: l10n.commonCancel,
      confirmLabel: l10n.commonDelete,
      destructive: true,
    );
    if (!confirmed || !context.mounted) {
      return;
    }

    final memoryController = context.read<MemoryController>();
    var deleted = false;
    await removal.run(entry.id, () async {
      deleted = await memoryController.deleteMemory(entry);
    });
    if (!context.mounted) {
      return;
    }
    if (!deleted) {
      flashOpenHandSnack(
        context,
        l10n.memoryOperationFailed,
        kind: OpenHandSnackKind.error,
      );
      return;
    }
    flashOpenHandSnack(
      context,
      l10n.memoryEntryDeleted,
      kind: OpenHandSnackKind.success,
    );
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
  late final TextEditingController _titleController;
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
    _titleController = TextEditingController(
      text: widget.initialEntry?.title ?? '',
    );
    _tagInputController = TextEditingController();
    _tagInputFocusNode = FocusNode(onKeyEvent: _handleTagInputKeyEvent);
    _tags = List<String>.from(widget.initialEntry?.tags ?? const <String>[]);
  }

  /// 该条目是否为"自主学习"特殊记忆。该标签由 LLM 自我学习子 Agent 自动
  /// 写入，是区分自主学习与普通记忆的唯一信号；为防止误删/误加：
  /// * 普通记忆编辑/新建时，无法手动添加 `自主学习` 标签（输入会被静默过滤）；
  /// * 自主学习记忆编辑时，无法移除 `自主学习` 标签（Chip 不渲染删除手柄，
  ///   且任何 split-input 都会强制保留该标签）。
  bool get _isAutoLearnedEntry => widget.initialEntry?.isAutoLearned ?? false;

  static bool _isAutoLearnedTag(String tag) {
    return tag.trim().toLowerCase() ==
        UserMemoryEntry.autoLearnedTag.toLowerCase();
  }

  @override
  void dispose() {
    _contentController.dispose();
    _titleController.dispose();
    _tagInputController.dispose();
    _tagInputFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final isEdit = widget.initialEntry != null;
    return OpenHandEditorDialogScaffold(
      title: isEdit ? l10n.memoryDialogEditTitle : l10n.memoryDialogCreateTitle,
      subtitle: isEdit
          ? l10n.memoryEditorEditSubtitle
          : l10n.memoryEditorCreateSubtitle,
      icon: isEdit ? Icons.edit_note_rounded : Icons.psychology_alt_outlined,
      iconColor: _isAutoLearnedEntry
          ? colorScheme.tertiary
          : colorScheme.primary,
      busy: _isSaving,
      closeEnabled: !_isSaving,
      canPop: !_isSaving,
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OpenHandDialogSectionCard(
              icon: Icons.title_rounded,
              accent: colorScheme.primary,
              title: l10n.memorySectionBasics,
              child: TextFormField(
                controller: _titleController,
                enabled: !_isSaving,
                maxLength: UserMemoryEntry.maxTitleLength,
                decoration: InputDecoration(
                  labelText: l10n.memoryTitleField,
                  hintText: l10n.memoryTitleHint,
                  counterText: '',
                ),
              ),
            ),
            kOpenHandGap14,
            OpenHandDialogSectionCard(
              icon: Icons.notes_rounded,
              accent: colorScheme.secondary,
              title: l10n.memorySectionContent,
              child: TextFormField(
                controller: _contentController,
                minLines: 7,
                maxLines: 12,
                maxLength: UserMemoryEntry.maxContentCharacters,
                enabled: !_isSaving,
                decoration: InputDecoration(
                  labelText: l10n.memoryContentField,
                  alignLabelWithHint: true,
                ),
                validator: (value) {
                  if (UserMemoryEntry.normalizeContent(value ?? '').isEmpty) {
                    return l10n.memoryContentRequired;
                  }
                  return null;
                },
              ),
            ),
            kOpenHandGap14,
            OpenHandDialogSectionCard(
              icon: Icons.sell_outlined,
              accent: colorScheme.tertiary,
              title: l10n.memorySectionTags,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _tagInputController,
                    focusNode: _tagInputFocusNode,
                    enabled: !_isSaving,
                    maxLength: UserMemoryEntry.maxTagCharacters,
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
                        padding: const EdgeInsetsDirectional.only(end: 10),
                        child: IconButton(
                          onPressed: _isSaving ? null : _addTagsFromInput,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: colorScheme.onSurfaceVariant,
                            disabledForegroundColor: colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.38),
                            minimumSize: const Size(36, 36),
                            maximumSize: const Size(36, 36),
                            padding: EdgeInsets.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.add_rounded, size: 22),
                        ),
                      ),
                    ),
                  ),
                  if (_tags.isNotEmpty) ...[
                    kOpenHandGap12,
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _tags
                          .map((tag) {
                            final locked =
                                _isAutoLearnedEntry && _isAutoLearnedTag(tag);
                            return InputChip(
                              avatar: Icon(
                                locked
                                    ? Icons.auto_awesome_outlined
                                    : Icons.sell_outlined,
                                size: 16,
                              ),
                              label: Text(
                                locked ? l10n.memoryAutoLearnedTag : tag,
                              ),
                              onDeleted: _isSaving || locked
                                  ? null
                                  : () => _removeTag(tag),
                            );
                          })
                          .toList(growable: false),
                    ),
                  ],
                  kOpenHandGap8,
                  Text(
                    _isAutoLearnedEntry
                        ? l10n.memoryAutoLearnedLockedHint(
                            UserMemoryEntry.autoLearnedTag,
                          )
                        : l10n.memoryAutoLearnedRestrictedHint(
                            UserMemoryEntry.autoLearnedTag,
                          ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  OpenHandDialogErrorText(message: _errorMessage, topGap: 16),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          label: l10n.commonCancel,
        ),
        OpenHandDialogActionButton.primary(
          onPressed: _isSaving ? null : _handleSave,
          busy: _isSaving,
          label: l10n.commonSave,
        ),
      ],
    );
  }

  Future<void> _handleSave() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final pendingTags = _mergedTagsWithInput();
    if (pendingTags.length > UserMemoryEntry.maxTags) {
      setState(() {
        _errorMessage = l10n.memoryTagLimitExceeded;
      });
      return;
    }
    final tags = _commitPendingTags(pendingTags);
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final content = _contentController.text;
    final title = _titleController.text;
    final controller = context.read<MemoryController>();

    late final bool saved;
    try {
      if (widget.initialEntry == null) {
        saved = await controller.createMemory(
          content: content,
          tags: tags,
          title: title,
        );
      } else {
        saved = await controller.updateMemory(
          widget.initialEntry!,
          content: content,
          tags: tags,
          title: title,
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
    if (nextTags.length > UserMemoryEntry.maxTags) {
      setState(() {
        _errorMessage = AppLocalizations.of(context)!.memoryTagLimitExceeded;
      });
      return;
    }
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

  List<String> _commitPendingTags(List<String> nextTags) {
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
    final raw = <String>[..._tags, ..._splitTagInput(_tagInputController.text)];
    // 防御性过滤：普通记忆永远剔除 `自主学习` 标签；自主学习记忆永远保留。
    final isAutoLearnedEntry = _isAutoLearnedEntry;
    final filtered = <String>[];
    var sawAutoLearned = false;
    for (final tag in raw) {
      if (_isAutoLearnedTag(tag)) {
        if (!isAutoLearnedEntry) {
          // 普通条目：丢弃用户尝试添加的 `自主学习` 标签。
          continue;
        }
        if (sawAutoLearned) {
          continue;
        }
        sawAutoLearned = true;
      }
      filtered.add(tag);
    }
    if (isAutoLearnedEntry && !sawAutoLearned) {
      // 用户某种方式抹掉了，强制补回（兜底）。
      filtered.insert(0, UserMemoryEntry.autoLearnedTag);
    }
    return UserMemoryEntry.normalizeTags(filtered);
  }

  List<String> _splitTagInput(String value) {
    return splitTrimmedNonEmpty(value, separator: RegExp(r'[\n,，;；]+'));
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

class _MemoryEntryCard extends StatelessWidget {
  const _MemoryEntryCard({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onActionSelected,
  });

  final UserMemoryEntry entry;
  final VoidCallback onTap;
  final ValueChanged<_MemoryCardAction> onActionSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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

    final kindLabel = isAutoLearned
        ? l10n.memoryAutoLearnedTag
        : l10n.memoryTypeUser;
    final kindColor = isAutoLearned
        ? colorScheme.tertiary
        : OpenHandStatusColors.success;
    final titled = entry.title.trim().isNotEmpty;
    final body = entry.content.trim();
    final title = titled
        ? entry.title.trim()
        : (body.isEmpty ? kindLabel : entry.preview);
    final description = titled
        ? (body.isEmpty ? null : body)
        : (body.length > 72 ? body : null);
    final createdLabel = formatYearMonthDayHmLocal(entry.createdAt);

    return OpenHandFeatureListCard(
      onTap: onTap,
      identity: OpenHandListIdentity(title: title, description: description),
      actions: [
        AnimatedPopupMenuButton<_MemoryCardAction>(
          tooltip: openHandMoreActionsLabel(context),
          style: openHandFeatureCircleIconButtonStyle(colorScheme),
          onSelected: onActionSelected,
          itemBuilder: (context) => [
            PopupMenuItem<_MemoryCardAction>(
              value: _MemoryCardAction.edit,
              child: Text(l10n.commonEdit),
            ),
            PopupMenuItem<_MemoryCardAction>(
              value: _MemoryCardAction.delete,
              child: Text(
                l10n.commonDelete,
                style: TextStyle(
                  color: colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
      statusPills: [
        OpenHandStatusPill(
          icon: isAutoLearned
              ? Icons.auto_awesome_outlined
              : Icons.person_outline_rounded,
          label: kindLabel,
          color: kindColor,
        ),
        OpenHandStatusPill(
          icon: Icons.schedule_rounded,
          label: createdLabel,
          color: OpenHandStatusColors.warning,
        ),
      ],
      factChips: [
        for (final tag in visibleTags)
          OpenHandFactChip(
            icon: Icons.sell_outlined,
            label: tag,
            color: OpenHandStatusColors.info,
          ),
        if (hiddenTagCount > 0)
          OpenHandFactChip(
            icon: Icons.more_horiz_rounded,
            label: '+$hiddenTagCount',
            color: colorScheme.onSurfaceVariant,
          ),
      ],
      metrics: [
        (label: l10n.listCardMetricKind, value: kindLabel, accent: kindColor),
        (
          label: l10n.memorySectionTags,
          value: '${displayTags.length}',
          accent: colorScheme.primary,
        ),
        (
          label: l10n.memoryCreatedAtLabel,
          value: createdLabel,
          accent: OpenHandStatusColors.warning,
        ),
        (
          label: l10n.listCardMetricContent,
          value: '${body.length}',
          accent: colorScheme.tertiary,
        ),
      ],
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
    final shortPath = OpenHandPaths.shortenHomePath(issue.filePath);

    return PersistenceIssueCard(
      title: l10n.memoryPersistenceSaveFailedTitle,
      body: '${l10n.memoryPersistenceSaveFailedBody}\n$shortPath',
      dismissLabel: l10n.settingsPersistenceDismiss,
      onDismiss: onDismiss,
    );
  }
}
