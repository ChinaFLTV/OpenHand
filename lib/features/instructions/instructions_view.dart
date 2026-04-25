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

import '../../shared/widgets/animated_dialog.dart';
import '../../shared/widgets/appear_once.dart';
import 'instructions_controller.dart';
import 'model/user_instruction_entry.dart';

class InstructionsView extends StatelessWidget {
  const InstructionsView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snapshot = context
        .select<
          InstructionsController,
          ({
            bool isLoading,
            String? errorMessage,
            List<UserInstructionEntry> entries,
          })
        >((c) => (
              isLoading: c.isLoading,
              errorMessage: c.errorMessage,
              entries: c.entries,
            ));
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
                  onPressed:
                      snapshot.isLoading ? null : () => controller.refresh(),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('刷新'),
                ),
                FilledButton.icon(
                  onPressed: () => _openEditor(context, controller, null),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('新建指令'),
                ),
              ],
            );
            const header = _InstructionsHeader(
              title: '指令',
              subtitle: '维护应用内的可复用提示词片段。启用的指令会按当前顺序注入到所有线程模板的 system prompt，'
                  '并在会话窗口的输入框顶部以胶囊形式列出，可在单次发送前临时取消或重新加入。',
            );
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header,
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: actions,
                  ),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Expanded(child: header),
                const SizedBox(width: 20),
                Flexible(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: actions,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        if (snapshot.errorMessage != null) ...[
          _InstructionsBanner(
            icon: Icons.error_outline_rounded,
            color: theme.colorScheme.error,
            title: '加载失败',
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
    ({
      bool isLoading,
      String? errorMessage,
      List<UserInstructionEntry> entries,
    }) snapshot,
  ) {
    if (snapshot.isLoading && snapshot.entries.isEmpty) {
      return const Center(
        key: ValueKey('loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (snapshot.entries.isEmpty) {
      return Center(
        key: const ValueKey('empty'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tips_and_updates_outlined,
              size: 64,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              '尚未创建指令',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              '点击右上角「新建指令」创建第一条。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.7),
                  ),
            ),
          ],
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
            child: _InstructionCard(
              entry: entry,
              dragIndex: index,
              onToggle: (value) => controller.setEnabled(entry.id, value),
              onEdit: () => _openEditor(context, controller, entry),
              onDelete: () => _confirmDelete(context, controller, entry),
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
      builder: (_) => _InstructionEditorDialog(
        controller: controller,
        source: source,
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    InstructionsController controller,
    UserInstructionEntry entry,
  ) async {
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除指令'),
        content: Text('确定要删除指令"${entry.name}"吗？此操作无法撤销。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
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
        Text(title, style: theme.textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _InstructionsBanner extends StatelessWidget {
  const _InstructionsBanner({
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
    required this.onEdit,
    required this.onDelete,
  });

  final UserInstructionEntry entry;
  final int dragIndex;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = entry.enabled
        ? theme.colorScheme.primary
        : theme.colorScheme.outline;
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ReorderableDragStartListener(
                index: dragIndex,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: color,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _MetadataChip(
                          icon: Icons.label_outline_rounded,
                          label: 'v${entry.version}',
                        ),
                      ],
                    ),
                    if (entry.description.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        entry.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: <Widget>[
                        if (entry.applyTo.trim().isNotEmpty)
                          _MetadataChip(
                            icon: Icons.account_tree_outlined,
                            label: 'applyTo · ${entry.applyTo}',
                          ),
                        for (final t in entry.taskTypes)
                          _MetadataChip(
                            icon: Icons.category_outlined,
                            label: t,
                          ),
                        for (final k in entry.keywords)
                          _MetadataChip(
                            icon: Icons.tag_rounded,
                            label: k,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  Switch(value: entry.enabled, onChanged: onToggle),
                  IconButton(
                    tooltip: '删除',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: onDelete,
                  ),
                ],
              ),
            ],
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: theme.colorScheme.outline),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
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
  late final TextEditingController _notes; // newline separated
  late final TextEditingController _taskTypes; // comma separated
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
    _taskTypes =
        TextEditingController(text: (s?.taskTypes ?? const []).join(', '));
    _keywords =
        TextEditingController(text: (s?.keywords ?? const []).join(', '));
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
    final theme = Theme.of(context);
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        isEdit ? '编辑指令' : '新建指令',
                        style: theme.textTheme.headlineSmall,
                      ),
                    ),
                    Text(
                      '启用',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch.adaptive(
                      value: _enabled,
                      onChanged:
                          _saving ? null : (v) => setState(() => _enabled = v),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: _name,
                          maxLength: UserInstructionEntry.maxNameLength,
                          decoration: const InputDecoration(
                            labelText: '名称 *',
                            counterText: '',
                          ),
                          validator: (v) {
                            if ((v ?? '').trim().isEmpty) return '名称不能为空';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: _description,
                                maxLength:
                                    UserInstructionEntry.maxDescriptionLength,
                                decoration: const InputDecoration(
                                  labelText: '描述',
                                  counterText: '',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _version,
                                decoration: const InputDecoration(
                                  labelText: '版本',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _applyTo,
                          maxLength: UserInstructionEntry.maxApplyToLength,
                          decoration: const InputDecoration(
                            labelText: 'applyTo（自由文本，描述何时加载）',
                            counterText: '',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _taskTypes,
                          decoration: const InputDecoration(
                            labelText: 'trigger.taskTypes（逗号分隔）',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _keywords,
                          decoration: const InputDecoration(
                            labelText: 'trigger.keywords（逗号分隔）',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _notes,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'notes（每行一条）',
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
                          decoration: const InputDecoration(
                            labelText: '指令正文 *（Markdown）',
                            alignLabelWithHint: true,
                            counterText: '',
                          ),
                          validator: (v) {
                            if ((v ?? '').trim().isEmpty) return '正文不能为空';
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
                    TextButton(
                      onPressed:
                          _saving ? null : () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(isEdit ? '保存修改' : '创建'),
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

  List<String> _splitCsv(String value) =>
      value.split(RegExp(r'[,，;；]')).map((e) => e.trim()).toList();

  List<String> _splitLines(String value) =>
      value.split('\n').map((e) => e.trim()).toList();

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存失败，请检查必填项是否为空。')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
