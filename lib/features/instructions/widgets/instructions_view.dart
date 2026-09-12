/// 与 [MemoryView] / McpView 等模块对齐：顶部页头 + 操作按钮 +
/// 列表正文。支持新增、编辑、删除、启停、拖拽排序。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/openhand_status_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/appear_once.dart';
import '../../../shared/ui/feature_page_shell.dart';
import '../../../shared/ui/feature_state_card.dart';
import '../../../shared/ui/list_removal_transition.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_code_editor.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_form_fields.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/reorder_proxy_decorator.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/localized_text.dart';
import '../../../shared/util/text_clip.dart';
import '../instructions_controller.dart';
import '../model/user_instruction_entry.dart';

enum _InstructionCardAction { edit, delete }

const double _kInstructionDragHandleExtent = 32;
const double _kInstructionDragHandleIconSize = 20;

class InstructionsView extends StatelessWidget {
  const InstructionsView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final snapshot = context
        .select<
          InstructionsController,
          ({
            bool isLoading,
            String? errorMessage,
            List<UserInstructionEntry> entries,
          })
        >(
          (c) => (
            isLoading: c.isLoading,
            errorMessage: c.errorMessage,
            entries: c.entries,
          ),
        );
    final controller = context.read<InstructionsController>();

    final actions = Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.end,
      children: [
        FilledButton.tonalIcon(
          onPressed: snapshot.isLoading ? null : controller.refresh,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(l10n.instructionRefresh),
        ),
        FilledButton.icon(
          onPressed:
              snapshot.isLoading ||
                  snapshot.entries.length >= UserInstructionEntry.maxEntries
              ? null
              : () => _openEditor(context, controller, null),
          icon: const Icon(Icons.add_rounded),
          label: Text(l10n.instructionNewEntry),
        ),
      ],
    );

    return FeaturePageShell(
      title: l10n.instructionPageTitle,
      subtitle: l10n.instructionPageSubtitle,
      actions: actions,
      successSignal: controller.saveSuccessSignal,
      notices: [
        if (snapshot.errorMessage != null && snapshot.entries.isNotEmpty)
          FeatureStateCard.inline(
            icon: Icons.error_outline_rounded,
            tone: FeatureStateTone.error,
            title: l10n.instructionLoadFailedTitle,
            body: snapshot.errorMessage!,
          ),
      ],
      body: _buildBody(context, controller, snapshot),
    );
  }

  Widget _buildBody(
    BuildContext context,
    InstructionsController controller,
    ({bool isLoading, String? errorMessage, List<UserInstructionEntry> entries})
    snapshot,
  ) {
    final l10n = AppLocalizations.of(context)!;
    if (snapshot.isLoading && snapshot.entries.isEmpty) {
      return const Center(
        key: ValueKey('loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (snapshot.errorMessage != null && snapshot.entries.isEmpty) {
      return FeatureStateCard.centered(
        key: const ValueKey('error'),
        icon: Icons.error_outline_rounded,
        tone: FeatureStateTone.error,
        title: l10n.instructionLoadFailedTitle,
        body: snapshot.errorMessage!,
      );
    }
    if (snapshot.entries.isEmpty) {
      return FeatureStateCard.centered(
        key: const ValueKey('empty'),
        icon: Icons.tips_and_updates_outlined,
        title: l10n.instructionEmptyTitle,
        body: l10n.instructionEmptyBody,
      );
    }
    return OpenHandRemovableListScope(
      builder: (context, removal) => ReorderableListView.builder(
        key: const ValueKey('list'),
        buildDefaultDragHandles: false,
        proxyDecorator: (child, index, animation) =>
            buildOpenHandReorderProxy(context, child, animation),
        itemCount: snapshot.entries.length,
        onReorderItem: (oldIndex, newIndex) async {
          final ids = snapshot.entries.map((e) => e.id).toList();
          final moved = ids.removeAt(oldIndex);
          ids.insert(newIndex, moved);
          await controller.reorder(ids);
        },
        itemBuilder: (context, index) {
          final entry = snapshot.entries[index];
          return Padding(
            key: ValueKey(entry.id),
            padding: const EdgeInsets.fromLTRB(0, 2, 0, 12),
            child: SettingsAwareAppearOnce(
              child: RepaintBoundary(
                child: OpenHandListRemovalTransition(
                  collapsed: removal.isRemoving(entry.id),
                  child: _InstructionCard(
                    entry: entry,
                    dragIndex: index,
                    onToggle: (value) => controller.setEnabled(entry.id, value),
                    onTap: () => _openEditor(context, controller, entry),
                    onActionSelected: (action) {
                      switch (action) {
                        case _InstructionCardAction.edit:
                          _openEditor(context, controller, entry);
                        case _InstructionCardAction.delete:
                          _confirmDelete(context, controller, removal, entry);
                      }
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    InstructionsController controller,
    UserInstructionEntry? source,
  ) async {
    await showAnimatedDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _InstructionEditorDialog(controller: controller, source: source),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    InstructionsController controller,
    OpenHandListRemoval removal,
    UserInstructionEntry entry,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: l10n.instructionDeleteConfirmTitle,
      message: '${l10n.instructionDeleteConfirmBody}\n\n${entry.name}',
      cancelLabel: l10n.commonCancel,
      confirmLabel: l10n.commonDelete,
      destructive: true,
    );
    if (confirmed) {
      await removal.run(entry.id, () => controller.deleteEntry(entry.id));
    }
  }
}

class _InstructionCard extends StatelessWidget {
  const _InstructionCard({
    required this.entry,
    required this.dragIndex,
    required this.onToggle,
    required this.onTap,
    required this.onActionSelected,
  });

  final UserInstructionEntry entry;
  final int dragIndex;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;
  final ValueChanged<_InstructionCardAction> onActionSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    // 过滤空白项，避免持久化历史中遗留的空字符串渲染出"空胶囊"。
    final visibleTaskTypes = stringListFromValue(entry.taskTypes);
    final visibleKeywords = stringListFromValue(entry.keywords);
    final taskTypes = visibleTaskTypes.take(4).toList(growable: false);
    final hiddenTaskTypeCount = visibleTaskTypes.length - taskTypes.length;
    final keywords = visibleKeywords.take(4).toList(growable: false);
    final hiddenKeywordCount = visibleKeywords.length - keywords.length;
    final trimmedVersion = entry.version.trim();
    final description = entry.description.trim();
    final applyTo = entry.applyTo.trim();
    final statusColor = entry.enabled
        ? OpenHandStatusColors.success
        : colorScheme.outline;

    return OpenHandFeatureListCard(
      onTap: onTap,
      identity: OpenHandListIdentity(
        title: entry.name,
        description: description.isEmpty ? null : description,
        leading: ReorderableDragStartListener(
          index: dragIndex,
          child: SizedBox(
            width: _kInstructionDragHandleExtent,
            height: _kInstructionDragHandleExtent,
            child: Icon(
              Icons.drag_indicator_rounded,
              size: _kInstructionDragHandleIconSize,
              color: colorScheme.outline,
            ),
          ),
        ),
      ),
      actions: [
        _InstructionEnabledSwitch(value: entry.enabled, onChanged: onToggle),
        AnimatedPopupMenuButton<_InstructionCardAction>(
          tooltip: openHandMoreActionsLabel(context),
          style: openHandFeatureCircleIconButtonStyle(colorScheme),
          onSelected: onActionSelected,
          itemBuilder: (context) => [
            PopupMenuItem<_InstructionCardAction>(
              value: _InstructionCardAction.edit,
              child: Text(l10n.commonEdit),
            ),
            PopupMenuItem<_InstructionCardAction>(
              value: _InstructionCardAction.delete,
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
          icon: entry.enabled
              ? Icons.check_circle_outline_rounded
              : Icons.pause_circle_outline_rounded,
          label: entry.enabled
              ? l10n.instructionEnabledStatus
              : l10n.instructionDisabledStatus,
          color: statusColor,
        ),
        if (trimmedVersion.isNotEmpty)
          OpenHandStatusPill(
            icon: Icons.label_outline_rounded,
            label: l10n.instructionSummaryVersion(trimmedVersion),
            color: colorScheme.secondary,
          ),
        if (entry.notes.isNotEmpty)
          OpenHandStatusPill(
            icon: Icons.notes_outlined,
            label: '${l10n.instructionNotesChipLabel}: ${entry.notes.length}',
            color: OpenHandStatusColors.warning,
          ),
      ],
      factChips: [
        if (applyTo.isNotEmpty)
          OpenHandFactChip(
            icon: Icons.account_tree_outlined,
            label: '${l10n.instructionApplyToChipLabel}: $applyTo',
            color: colorScheme.tertiary,
          ),
        for (final taskType in taskTypes)
          OpenHandFactChip(
            icon: Icons.category_outlined,
            label: taskType,
            color: colorScheme.primary,
          ),
        if (hiddenTaskTypeCount > 0)
          OpenHandFactChip(
            icon: Icons.more_horiz_rounded,
            label: '+$hiddenTaskTypeCount',
            color: colorScheme.primary,
          ),
        for (final keyword in keywords)
          OpenHandFactChip(
            icon: Icons.tag_rounded,
            label: keyword,
            color: OpenHandStatusColors.info,
          ),
        if (hiddenKeywordCount > 0)
          OpenHandFactChip(
            icon: Icons.more_horiz_rounded,
            label: '+$hiddenKeywordCount',
            color: OpenHandStatusColors.info,
          ),
      ],
      metrics: [
        (
          label: l10n.listCardMetricStatus,
          value: entry.enabled
              ? l10n.instructionEnabledStatus
              : l10n.instructionDisabledStatus,
          accent: statusColor,
        ),
        (
          label: l10n.instructionVersionField,
          value: trimmedVersion.isEmpty
              ? '—'
              : l10n.instructionSummaryVersion(trimmedVersion),
          accent: colorScheme.secondary,
        ),
        (
          label: l10n.instructionNotesChipLabel,
          value: '${entry.notes.length}',
          accent: OpenHandStatusColors.warning,
        ),
        (
          label: l10n.instructionSectionKeywords,
          value: '${visibleKeywords.length}',
          accent: OpenHandStatusColors.info,
        ),
      ],
    );
  }
}

class _InstructionEnabledSwitch extends StatelessWidget {
  const _InstructionEnabledSwitch({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Switch(
      value: value,
      onChanged: onChanged,
      thumbIcon: WidgetStateProperty.resolveWith<Icon?>((states) {
        if (states.contains(WidgetState.selected)) {
          return const Icon(Icons.check_rounded, size: 14);
        }
        return const Icon(Icons.close_rounded, size: 14);
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.selected)) return Colors.transparent;
        return colorScheme.outlineVariant;
      }),
    );
  }
}

class _InstructionToggleCard extends StatelessWidget {
  const _InstructionToggleCard({
    required this.value,
    required this.onChanged,
    required this.title,
    required this.subtitle,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(kOpenHandRadius20),
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: AnimatedContainer(
          duration: openHandMotionDuration(context, kOpenHandMotion180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: value
                ? colorScheme.primaryContainer.withValues(alpha: 0.55)
                : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(kOpenHandRadius20),
            border: Border.all(
              color: value
                  ? colorScheme.primary.withValues(alpha: 0.36)
                  : colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: value ? colorScheme.primary : colorScheme.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  value ? Icons.bolt_rounded : Icons.power_settings_new_rounded,
                  size: 18,
                  color: value ? colorScheme.onPrimary : colorScheme.outline,
                ),
              ),
              kOpenHandHGap12,
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: value
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    kOpenHandGap2,
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              kOpenHandHGap8,
              _InstructionEnabledSwitch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

const double _kInstructionEditorTwoColumnMinWidth = 560;

class _InstructionEditorDialog extends StatefulWidget {
  const _InstructionEditorDialog({required this.controller, this.source});

  final InstructionsController controller;
  final UserInstructionEntry? source;

  @override
  State<_InstructionEditorDialog> createState() =>
      _InstructionEditorDialogState();
}

class _InstructionEditorDialogState extends State<_InstructionEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _version;
  late final TextEditingController _applyTo;
  late final TextEditingController _notes;
  late final TextEditingController _taskTypes;
  late final TextEditingController _keywords;
  late final TextEditingController _body;
  late bool _enabled;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.source;
    _name = TextEditingController(text: s?.name ?? '');
    _description = TextEditingController(text: s?.description ?? '');
    _version = TextEditingController(text: s?.version ?? '1.0');
    _applyTo = TextEditingController(text: s?.applyTo ?? '');
    _notes = TextEditingController(text: (s?.notes ?? const []).join('\n'));
    _taskTypes = TextEditingController(
      text: (s?.taskTypes ?? const []).join(', '),
    );
    _keywords = TextEditingController(
      text: (s?.keywords ?? const []).join(', '),
    );
    _body = TextEditingController(text: s?.body ?? '');
    _enabled = s?.enabled ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _version.dispose();
    _applyTo.dispose();
    _notes.dispose();
    _taskTypes.dispose();
    _keywords.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.source != null;
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    return OpenHandEditorDialogScaffold(
      title: isEdit
          ? l10n.instructionDialogEditTitle
          : l10n.instructionDialogCreateTitle,
      subtitle: isEdit
          ? l10n.instructionEditorEditSubtitle
          : l10n.instructionEditorCreateSubtitle,
      icon: isEdit ? Icons.edit_note_rounded : Icons.post_add_rounded,
      iconColor: colorScheme.primary,
      busy: _saving,
      closeEnabled: !_saving,
      canPop: !_saving,
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _InstructionToggleCard(
              value: _enabled,
              title: l10n.instructionEnabledLabel,
              subtitle: l10n.instructionEnabledBody,
              onChanged: _saving ? null : (v) => setState(() => _enabled = v),
            ),
            kOpenHandGap14,
            OpenHandDialogSectionCard(
              icon: Icons.badge_outlined,
              accent: colorScheme.primary,
              title: l10n.instructionSectionBasics,
              child: Column(
                children: [
                  TextFormField(
                    controller: _name,
                    enabled: !_saving,
                    maxLength: UserInstructionEntry.maxNameLength,
                    decoration: InputDecoration(
                      labelText: l10n.instructionNameField,
                      counterText: '',
                    ),
                    validator: (v) {
                      if ((v ?? '').trim().isEmpty) {
                        return l10n.instructionNameRequired;
                      }
                      return null;
                    },
                  ),
                  kOpenHandGap12,
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final description = TextFormField(
                        controller: _description,
                        enabled: !_saving,
                        maxLength: UserInstructionEntry.maxDescriptionLength,
                        decoration: InputDecoration(
                          labelText: l10n.instructionDescriptionField,
                          counterText: '',
                        ),
                      );
                      final version = TextFormField(
                        controller: _version,
                        enabled: !_saving,
                        decoration: InputDecoration(
                          labelText: l10n.instructionVersionField,
                        ),
                      );
                      if (constraints.maxWidth <
                          _kInstructionEditorTwoColumnMinWidth) {
                        return Column(
                          children: [description, kOpenHandGap12, version],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(flex: 2, child: description),
                          kOpenHandHGap12,
                          Expanded(child: version),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            kOpenHandGap14,
            OpenHandDialogSectionCard(
              icon: Icons.alt_route_rounded,
              accent: colorScheme.tertiary,
              title: l10n.instructionSectionRouting,
              child: Column(
                children: [
                  TextFormField(
                    controller: _applyTo,
                    enabled: !_saving,
                    maxLength: UserInstructionEntry.maxApplyToLength,
                    decoration: InputDecoration(
                      labelText: l10n.instructionApplyToField,
                      counterText: '',
                    ),
                  ),
                  kOpenHandGap12,
                  TextFormField(
                    controller: _taskTypes,
                    enabled: !_saving,
                    decoration: InputDecoration(
                      labelText: l10n.instructionTaskTypesField,
                    ),
                  ),
                  kOpenHandGap12,
                  TextFormField(
                    controller: _keywords,
                    enabled: !_saving,
                    decoration: InputDecoration(
                      labelText: l10n.instructionKeywordsField,
                    ),
                  ),
                ],
              ),
            ),
            kOpenHandGap14,
            OpenHandDialogSectionCard(
              icon: Icons.article_outlined,
              accent: colorScheme.secondary,
              title: l10n.instructionSectionContent,
              child: Column(
                children: [
                  TextFormField(
                    controller: _notes,
                    enabled: !_saving,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: l10n.instructionNotesField,
                    ),
                  ),
                  kOpenHandGap12,
                  FormField<String>(
                    validator: (_) {
                      if (_body.text.trim().isEmpty) {
                        return l10n.instructionBodyRequired;
                      }
                      return null;
                    },
                    builder: (state) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          OpenHandCodeEditor(
                            value: _body.text,
                            language: 'markdown',
                            fileName: 'instruction.md',
                            icon: Icons.article_outlined,
                            height: 280,
                            borderRadius: kOpenHandBorderRadius16,
                            readOnly: _saving,
                            onChanged: (value) {
                              final clipped = clipTextByCodeUnits(
                                value,
                                UserInstructionEntry.maxBodyLength,
                                suffix: '',
                              );
                              _body.text = clipped;
                              state.didChange(clipped);
                            },
                          ),
                          if (state.hasError)
                            Padding(
                              padding: const EdgeInsets.only(top: 8, left: 4),
                              child: Text(
                                state.errorText!,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: colorScheme.error),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          label: l10n.commonCancel,
        ),
        OpenHandDialogActionButton.primary(
          onPressed: _saving ? null : _save,
          busy: _saving,
          label: isEdit ? l10n.commonSave : l10n.instructionCreateAction,
        ),
      ],
    );
  }

  List<String> _splitCsv(String value) =>
      splitTrimmedNonEmpty(value, separator: RegExp('[,，;；]'));

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _saving = true);
    try {
      final notes = splitTrimmedNonEmpty(_notes.text, separator: '\n');
      final taskTypes = _splitCsv(_taskTypes.text);
      final keywords = _splitCsv(_keywords.text);
      final ok = widget.source == null
          ? await widget.controller.createEntry(
              name: _name.text,
              body: _body.text,
              description: _description.text,
              version: _version.text,
              applyTo: _applyTo.text,
              notes: notes,
              taskTypes: taskTypes,
              keywords: keywords,
              enabled: _enabled,
            )
          : await widget.controller.updateEntry(
              widget.source!,
              name: _name.text,
              body: _body.text,
              description: _description.text,
              version: _version.text,
              applyTo: _applyTo.text,
              notes: notes,
              taskTypes: taskTypes,
              keywords: keywords,
              enabled: _enabled,
            );
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop();
      } else {
        OpenHandSnackBar.flash(
          context,
          l10n.instructionSaveFailed,
          kind: OpenHandSnackKind.error,
          postFrame: true,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
