/// User Instructions UI
///
/// 2026-04-25 / Phase 4-Instructions
///
/// 与 [MemoryView] / McpView 等模块对齐：顶部页头 + 操作按钮 +
/// 列表正文。支持新增、编辑、删除、启停、拖拽排序。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/widgets/animated_dialog.dart';
import '../../shared/widgets/animated_menu.dart';
import '../../shared/widgets/appear_once.dart';
import 'instructions_controller.dart';
import 'model/user_instruction_entry.dart';

enum _InstructionCardAction { edit, delete }

class InstructionsView extends StatelessWidget {
  const InstructionsView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 980;
            final actions = Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.end,
              children: [
                FilledButton.tonalIcon(
                  onPressed: snapshot.isLoading
                      ? null
                      : () => controller.refresh(),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(l10n.instructionRefresh),
                ),
                FilledButton.icon(
                  onPressed: () => _openEditor(context, controller, null),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(l10n.instructionNewEntry),
                ),
              ],
            );
            final header = _InstructionsHeader(
              title: l10n.instructionPageTitle,
              subtitle: l10n.instructionPageSubtitle,
            );
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header,
                  const SizedBox(height: 20),
                  Align(alignment: Alignment.centerRight, child: actions),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: header),
                const SizedBox(width: 20),
                Flexible(
                  child: Align(alignment: Alignment.topRight, child: actions),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        if (snapshot.errorMessage != null && snapshot.entries.isNotEmpty) ...[
          _InstructionsStateCard(
            icon: Icons.error_outline_rounded,
            color: theme.colorScheme.error,
            title: l10n.instructionLoadFailedTitle,
            body: snapshot.errorMessage!,
          ),
          const SizedBox(height: 16),
        ],
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _buildBody(context, controller, snapshot),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    InstructionsController controller,
    ({bool isLoading, String? errorMessage, List<UserInstructionEntry> entries})
    snapshot,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    if (snapshot.isLoading && snapshot.entries.isEmpty) {
      return const Center(
        key: ValueKey('loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (snapshot.errorMessage != null && snapshot.entries.isEmpty) {
      return Center(
        key: const ValueKey('error'),
        child: _InstructionsStateCard(
          icon: Icons.error_outline_rounded,
          color: colorScheme.error,
          title: l10n.instructionLoadFailedTitle,
          body: snapshot.errorMessage!,
        ),
      );
    }
    if (snapshot.entries.isEmpty) {
      return Center(
        key: const ValueKey('empty'),
        child: _InstructionsStateCard(
          icon: Icons.tips_and_updates_outlined,
          color: colorScheme.primary,
          title: l10n.instructionEmptyTitle,
          body: l10n.instructionEmptyBody,
        ),
      );
    }
    return ReorderableListView.builder(
      key: const ValueKey('list'),
      buildDefaultDragHandles: false,
      itemCount: snapshot.entries.length,
      onReorder: (oldIndex, newIndex) async {
        if (newIndex > oldIndex) newIndex -= 1;
        final ids = snapshot.entries.map((e) => e.id).toList();
        final moved = ids.removeAt(oldIndex);
        ids.insert(newIndex, moved);
        await controller.reorder(ids);
      },
      itemBuilder: (context, index) {
        final entry = snapshot.entries[index];
        return Padding(
          key: ValueKey(entry.id),
          padding: const EdgeInsets.only(bottom: 12),
          child: AppearOnce(
            child: RepaintBoundary(
              child: _InstructionCard(
                entry: entry,
                dragIndex: index,
                onToggle: (value) => controller.setEnabled(entry.id, value),
                onTap: () => _openEditor(context, controller, entry),
                onActionSelected: (action) {
                  switch (action) {
                    case _InstructionCardAction.edit:
                      _openEditor(context, controller, entry);
                      break;
                    case _InstructionCardAction.delete:
                      _confirmDelete(context, controller, entry);
                      break;
                  }
                },
              ),
            ),
          ),
        );
      },
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
    UserInstructionEntry entry,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.instructionDeleteConfirmTitle),
        content: Text('${l10n.instructionDeleteConfirmBody}\n\n${entry.name}'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.deleteEntry(entry.id);
    }
  }
}

class _InstructionsHeader extends StatelessWidget {
  const _InstructionsHeader({required this.title, required this.subtitle});

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

class _InstructionsStateCard extends StatelessWidget {
  const _InstructionsStateCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 560),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(body, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final taskTypes = entry.taskTypes.take(4).toList(growable: false);
    final hiddenTaskTypeCount = entry.taskTypes.length - taskTypes.length;
    final keywords = entry.keywords.take(4).toList(growable: false);
    final hiddenKeywordCount = entry.keywords.length - keywords.length;

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
                  ReorderableDragStartListener(
                    index: dragIndex,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: entry.enabled
                                ? colorScheme.primaryContainer
                                : colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.auto_awesome_motion_outlined,
                            color: entry.enabled
                                ? colorScheme.onPrimaryContainer
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Positioned(
                          left: -4,
                          top: -4,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHigh,
                              shape: BoxShape.circle,
                              border: Border.all(color: colorScheme.surface),
                            ),
                            child: Icon(
                              Icons.drag_indicator_rounded,
                              size: 15,
                              color: colorScheme.outline,
                            ),
                          ),
                        ),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: entry.enabled
                                  ? colorScheme.primary
                                  : colorScheme.outlineVariant,
                              shape: BoxShape.circle,
                              border: Border.all(color: colorScheme.surface),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          entry.enabled
                              ? l10n.instructionEnabledStatus
                              : l10n.instructionDisabledStatus,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: entry.enabled
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (entry.description.trim().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            entry.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: AnimatedPopupMenuButton<_InstructionCardAction>(
                      onSelected: onActionSelected,
                      itemBuilder: (context) => [
                        PopupMenuItem<_InstructionCardAction>(
                          value: _InstructionCardAction.edit,
                          child: Text(l10n.commonEdit),
                        ),
                        PopupMenuItem<_InstructionCardAction>(
                          value: _InstructionCardAction.delete,
                          child: Text(l10n.commonDelete),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    _InstructionToggleChip(
                      enabled: entry.enabled,
                      enabledLabel: l10n.instructionEnabledStatus,
                      disabledLabel: l10n.instructionDisabledStatus,
                      onPressed: () => onToggle(!entry.enabled),
                    ),
                    _MetadataChip(
                      icon: Icons.label_outline_rounded,
                      label: 'v${entry.version}',
                    ),
                    if (entry.applyTo.trim().isNotEmpty)
                      _MetadataChip(
                        icon: Icons.account_tree_outlined,
                        label:
                            '${l10n.instructionApplyToChipLabel}: ${entry.applyTo}',
                      ),
                    if (entry.notes.isNotEmpty)
                      _MetadataChip(
                        icon: Icons.notes_outlined,
                        label:
                            '${l10n.instructionNotesChipLabel}: ${entry.notes.length}',
                      ),
                    for (final taskType in taskTypes)
                      _MetadataChip(
                        icon: Icons.category_outlined,
                        label: taskType,
                      ),
                    if (hiddenTaskTypeCount > 0)
                      _MetadataChip(
                        icon: Icons.more_horiz_rounded,
                        label: '+$hiddenTaskTypeCount',
                      ),
                    for (final keyword in keywords)
                      _MetadataChip(icon: Icons.tag_rounded, label: keyword),
                    if (hiddenKeywordCount > 0)
                      _MetadataChip(
                        icon: Icons.more_horiz_rounded,
                        label: '+$hiddenKeywordCount',
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

class _InstructionToggleChip extends StatelessWidget {
  const _InstructionToggleChip({
    required this.enabled,
    required this.enabledLabel,
    required this.disabledLabel,
    required this.onPressed,
  });

  final bool enabled;
  final String enabledLabel;
  final String disabledLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final backgroundColor = enabled
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerHighest;
    final foregroundColor = enabled
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;
    final borderColor = enabled
        ? colorScheme.primary.withValues(alpha: 0.28)
        : colorScheme.outlineVariant;

    return ActionChip(
      avatar: Icon(
        enabled
            ? Icons.check_circle_outline_rounded
            : Icons.pause_circle_outline_rounded,
        size: 18,
        color: foregroundColor,
      ),
      label: Text(enabled ? enabledLabel : disabledLabel),
      onPressed: onPressed,
      backgroundColor: backgroundColor,
      side: BorderSide(color: borderColor),
      shape: const StadiumBorder(),
      labelStyle: theme.textTheme.labelLarge?.copyWith(
        color: foregroundColor,
        fontWeight: FontWeight.w600,
      ),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
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
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onChanged == null ? null : () => onChanged!(!value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: value
                  ? colorScheme.primaryContainer.withValues(alpha: 0.55)
                  : colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: value
                    ? colorScheme.primary.withValues(alpha: 0.36)
                    : colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: value ? colorScheme.primary : colorScheme.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    value
                        ? Icons.bolt_rounded
                        : Icons.power_settings_new_rounded,
                    size: 18,
                    color: value ? colorScheme.onPrimary : colorScheme.outline,
                  ),
                ),
                const SizedBox(width: 12),
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
                      const SizedBox(height: 2),
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
                const SizedBox(width: 8),
                _InstructionEnabledSwitch(value: value, onChanged: onChanged),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetadataChip extends StatelessWidget {
  const _MetadataChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Chip(
      avatar: Icon(icon, size: 18, color: colorScheme.outline),
      label: Text(label),
      side: BorderSide.none,
      backgroundColor: colorScheme.surfaceContainerHighest,
      labelStyle: theme.textTheme.labelSmall?.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

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
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context, isEdit, l10n),
                const Divider(height: 24),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: _name,
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
                        const SizedBox(height: 12),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final stacked = constraints.maxWidth < 560;
                            final description = TextFormField(
                              controller: _description,
                              maxLength:
                                  UserInstructionEntry.maxDescriptionLength,
                              decoration: InputDecoration(
                                labelText: l10n.instructionDescriptionField,
                                counterText: '',
                              ),
                            );
                            final version = TextFormField(
                              controller: _version,
                              decoration: InputDecoration(
                                labelText: l10n.instructionVersionField,
                              ),
                            );
                            if (stacked) {
                              return Column(
                                children: [
                                  description,
                                  const SizedBox(height: 12),
                                  version,
                                ],
                              );
                            }
                            return Row(
                              children: [
                                Expanded(flex: 2, child: description),
                                const SizedBox(width: 12),
                                Expanded(child: version),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _applyTo,
                          maxLength: UserInstructionEntry.maxApplyToLength,
                          decoration: InputDecoration(
                            labelText: l10n.instructionApplyToField,
                            counterText: '',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _taskTypes,
                          decoration: InputDecoration(
                            labelText: l10n.instructionTaskTypesField,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _keywords,
                          decoration: InputDecoration(
                            labelText: l10n.instructionKeywordsField,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _notes,
                          minLines: 2,
                          maxLines: 4,
                          decoration: InputDecoration(
                            labelText: l10n.instructionNotesField,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _body,
                          minLines: 6,
                          maxLines: 18,
                          maxLength: UserInstructionEntry.maxBodyLength,
                          inputFormatters: <TextInputFormatter>[
                            LengthLimitingTextInputFormatter(
                              UserInstructionEntry.maxBodyLength,
                            ),
                          ],
                          decoration: InputDecoration(
                            labelText: l10n.instructionBodyField,
                            alignLabelWithHint: true,
                            counterText: '',
                          ),
                          validator: (v) {
                            if ((v ?? '').trim().isEmpty) {
                              return l10n.instructionBodyRequired;
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    SizedBox(
                      width: 88,
                      height: 56,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          minimumSize: const Size(88, 56),
                          shape: const StadiumBorder(),
                        ),
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: Text(l10n.commonCancel),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 88,
                      height: 56,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          minimumSize: const Size(88, 56),
                          shape: const StadiumBorder(),
                        ),
                        onPressed: _saving ? null : _save,
                        child: Text(
                          isEdit
                              ? l10n.commonSave
                              : l10n.instructionCreateAction,
                        ),
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

  Widget _buildHeader(
    BuildContext context,
    bool isEdit,
    AppLocalizations l10n,
  ) {
    final theme = Theme.of(context);
    final title = Text(
      isEdit
          ? l10n.instructionDialogEditTitle
          : l10n.instructionDialogCreateTitle,
      style: theme.textTheme.headlineSmall,
    );
    final toggle = _InstructionToggleCard(
      value: _enabled,
      title: l10n.instructionEnabledLabel,
      subtitle: l10n.instructionEnabledBody,
      onChanged: _saving ? null : (v) => setState(() => _enabled = v),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, const SizedBox(height: 12), toggle],
          );
        }
        return Row(
          children: [
            Expanded(child: title),
            const SizedBox(width: 16),
            toggle,
          ],
        );
      },
    );
  }

  List<String> _splitCsv(String value) =>
      value.split(RegExp(r'[,，;；]')).map((e) => e.trim()).toList();

  List<String> _splitLines(String value) =>
      value.split('\n').map((e) => e.trim()).toList();

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _saving = true);
    try {
      final notes = _splitLines(_notes.text);
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.instructionSaveFailed)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
