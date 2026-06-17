import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../app/model/hook_config.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/appear_once.dart';
import '../../../shared/ui/feature_page_shell.dart';
import '../../../shared/ui/feature_state_card.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../hooks_controller.dart';

class HooksView extends StatelessWidget {
  const HooksView({super.key});

  @override
  Widget build(BuildContext context) {
    final entries = context.select<HooksController, List<HookEntry>>(
      (controller) => controller.entries,
    );
    final hooksController = context.read<HooksController>();
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');

    final actions = FilledButton.icon(
      onPressed: () => _showHookEditorDialog(context, null),
      icon: const Icon(Icons.add_rounded),
      label: Text(isZh ? '新增 Hook' : 'New Hook'),
    );

    return FeaturePageShell(
      title: 'Hooks',
      subtitle: isZh
          ? '为 AI Agent 的生命周期阶段配置要执行的脚本。每个 Hook 在对应事件触发时按顺序执行。'
          : 'Configure scripts to run at each AI agent lifecycle stage. Hooks execute sequentially when the corresponding event fires.',
      actions: actions,
      successSignal: hooksController.saveSuccessSignal,
      body: entries.isEmpty
          ? const _EmptyState(key: ValueKey<String>('empty'))
          : ScrollConfiguration(
              key: const ValueKey<String>('list'),
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: ListView.separated(
                padding: const EdgeInsets.only(top: 2),
                itemCount: entries.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return AppearOnce(
                    key: ValueKey<String>('hook-entry-${entry.id}'),
                    child: _HookEntryCard(
                      entry: entry,
                      isZh: isZh,
                      onEdit: () => _showHookEditorDialog(context, entry),
                      onToggle: (enabled) {
                        hooksController.toggleHookEnabled(
                          entry.id,
                          enabled: enabled,
                        );
                      },
                      onDelete: () => _confirmDelete(context, entry),
                    ),
                  );
                },
              ),
            ),
    );
  }

  void _showHookEditorDialog(BuildContext context, HookEntry? existing) {
    showAnimatedDialog(
      context: context,
      builder: (_) => _HookEditorDialog(existing: existing),
    );
  }

  Future<void> _confirmDelete(BuildContext context, HookEntry entry) async {
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: isZh ? '删除 Hook' : 'Delete Hook',
      message: isZh
          ? '确定删除 "${entry.label}" 吗？此操作不可撤销。'
          : 'Delete "${entry.label}"? This action cannot be undone.',
      cancelLabel: isZh ? '取消' : 'Cancel',
      confirmLabel: isZh ? '删除' : 'Delete',
      destructive: true,
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    context.read<HooksController>().deleteHook(entry.id);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    return FeatureStateCard.centered(
      icon: Icons.webhook_outlined,
      tone: FeatureStateTone.neutral,
      title: isZh ? '暂无 Hook 配置' : 'No hooks configured yet',
      body: isZh
          ? '点击右上角「新增 Hook」按钮开始配置。'
          : 'Click "New Hook" above to get started.',
    );
  }
}

class _HookEntryCard extends StatelessWidget {
  const _HookEntryCard({
    required this.entry,
    required this.isZh,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  final HookEntry entry;
  final bool isZh;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            // Event badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: entry.enabled
                    ? colorScheme.primaryContainer
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                entry.event.label(isZh),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: entry.enabled
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Label & script info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: entry.enabled
                          ? colorScheme.onSurface
                          : colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _scriptDescription,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Timeout badge
            Tooltip(
              message: isZh ? '超时时间' : 'Timeout',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${entry.timeoutSeconds}s',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Toggle switch
            Switch(value: entry.enabled, onChanged: onToggle),
            const SizedBox(width: 8),
            // Actions
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: isZh ? '编辑' : 'Edit',
              onPressed: onEdit,
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 20,
                color: colorScheme.error,
              ),
              tooltip: isZh ? '删除' : 'Delete',
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }

  String get _scriptDescription {
    if (entry.scriptPath != null && entry.scriptPath!.isNotEmpty) {
      return entry.scriptPath!;
    }
    if (entry.scriptContent != null && entry.scriptContent!.isNotEmpty) {
      final firstLine = entry.scriptContent!.split('\n').first.trim();
      return isZh ? '内联脚本: $firstLine' : 'Inline: $firstLine';
    }
    return isZh ? '未配置脚本' : 'No script configured';
  }
}

// ---------------------------------------------------------------------------
// Hook editor dialog
// ---------------------------------------------------------------------------

enum _HookScriptSource { file, inline }

class _HookEditorDialog extends StatefulWidget {
  const _HookEditorDialog({this.existing});

  final HookEntry? existing;

  @override
  State<_HookEditorDialog> createState() => _HookEditorDialogState();
}

class _HookEditorDialogState extends State<_HookEditorDialog> {
  static const Uuid _uuid = Uuid();

  late HookEvent _selectedEvent;
  late final TextEditingController _labelController;
  late final TextEditingController _scriptPathController;
  late final TextEditingController _scriptContentController;
  late final TextEditingController _timeoutController;
  late _HookScriptSource _scriptSource;
  late bool _enabled;
  String? _formError;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _selectedEvent = existing?.event ?? HookEvent.sessionStart;
    _labelController = TextEditingController(text: existing?.label ?? '');
    _scriptPathController = TextEditingController(
      text: existing?.scriptPath ?? '',
    );
    _scriptContentController = TextEditingController(
      text: existing?.scriptContent ?? '',
    );
    _timeoutController = TextEditingController(
      text: '${existing?.timeoutSeconds ?? 12}',
    );
    _enabled = existing?.enabled ?? true;
    _scriptSource =
        (existing?.scriptPath != null && existing!.scriptPath!.isNotEmpty)
        ? _HookScriptSource.file
        : _HookScriptSource.inline;
  }

  @override
  void dispose() {
    _labelController.dispose();
    _scriptPathController.dispose();
    _scriptContentController.dispose();
    _timeoutController.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.existing != null;
  bool get isZh =>
      Localizations.localeOf(context).languageCode.startsWith('zh');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return buildOpenHandAlertDialog(
      title: Text(
        _isEditing
            ? (isZh ? '编辑 Hook' : 'Edit Hook')
            : (isZh ? '新增 Hook' : 'New Hook'),
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildOpenHandDialogValidationMessage(
                context,
                message: _formError,
              ),
              if (_formError != null) const SizedBox(height: 12),
              // Label
              TextField(
                controller: _labelController,
                decoration: InputDecoration(
                  labelText: isZh ? '名称' : 'Label',
                  hintText: isZh ? '例如: 日志记录' : 'e.g. Logging',
                ),
              ),
              const SizedBox(height: 18),
              // Event selector
              Text(
                isZh ? '触发事件' : 'Trigger Event',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: HookEvent.values.map((event) {
                  final selected = event == _selectedEvent;
                  return ChoiceChip(
                    label: Text(event.label(isZh)),
                    selected: selected,
                    selectedColor: colorScheme.primaryContainer,
                    labelStyle: TextStyle(
                      color: selected
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant,
                    ),
                    onSelected: (_) => setState(() => _selectedEvent = event),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
              // Script source toggle
              Text(
                isZh ? '脚本来源' : 'Script Source',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              SegmentedButton<_HookScriptSource>(
                segments: [
                  ButtonSegment(
                    value: _HookScriptSource.file,
                    icon: const Icon(Icons.file_open_outlined, size: 18),
                    label: Text(isZh ? '选择文件' : 'File'),
                  ),
                  ButtonSegment(
                    value: _HookScriptSource.inline,
                    icon: const Icon(Icons.code_rounded, size: 18),
                    label: Text(isZh ? '编写脚本' : 'Inline'),
                  ),
                ],
                selected: {_scriptSource},
                onSelectionChanged: (selected) {
                  setState(() => _scriptSource = selected.first);
                },
              ),
              const SizedBox(height: 14),
              // File selector or inline editor
              if (_scriptSource == _HookScriptSource.file) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _scriptPathController,
                        decoration: InputDecoration(
                          labelText: isZh ? '脚本文件路径' : 'Script File Path',
                          hintText: isZh
                              ? '选择 .sh / .ps1 / .bat 文件'
                              : 'Select a .sh / .ps1 / .bat file',
                        ),
                        readOnly: true,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: _pickScriptFile,
                      child: Text(isZh ? '浏览' : 'Browse'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SelectableText(
                  isZh
                      ? '上下文 JSON 通过两种方式传入（均可安全用于 jq）：\n'
                            '① 临时文件: jq -r .session_id "\$OPENHAND_HOOK_CONTEXT_FILE"\n'
                            '② stdin 原始字节: jq -r .session_id\n'
                            '包含 session_id、session_file_path、environment 等字段。'
                      : 'Context JSON is passed in two safe ways (both work with jq):\n'
                            '① Temp file: jq -r .session_id "\$OPENHAND_HOOK_CONTEXT_FILE"\n'
                            '② Raw stdin: jq -r .session_id\n'
                            'Fields: session_id, session_file_path, environment, etc.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _scriptContentController,
                  maxLines: 8,
                  minLines: 4,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.all(12),
                    hintText: Platform.isWindows
                        ? (isZh
                              ? '输入 PowerShell / BAT 脚本'
                              : 'Enter PowerShell / BAT script')
                        : (isZh
                              ? '输入 Shell 脚本（无需 #!/bin/bash）'
                              : 'Enter shell script (#!/bin/bash not required)'),
                    hintStyle: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.5,
                      ),
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  isZh
                      ? '上下文 JSON 通过两种方式传入（均可安全用于 jq）：\n'
                            '① 临时文件: SID=\$(jq -r .session_id "\$OPENHAND_HOOK_CONTEXT_FILE")\n'
                            '② stdin 原始字节: SID=\$(jq -r .session_id)\n'
                            '包含 session_id、session_file_path、environment、statistics 等字段。'
                      : 'Context JSON is passed in two safe ways (both work with jq):\n'
                            '① Temp file: SID=\$(jq -r .session_id "\$OPENHAND_HOOK_CONTEXT_FILE")\n'
                            '② Raw stdin: SID=\$(jq -r .session_id)\n'
                            'Fields: session_id, session_file_path, environment, statistics, etc.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              // Timeout
              Row(
                children: [
                  Text(
                    isZh ? '超时时间（秒）' : 'Timeout (seconds)',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: _timeoutController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Enabled switch
              Row(
                children: [
                  Text(
                    isZh ? '启用' : 'Enabled',
                    style: theme.textTheme.titleSmall,
                  ),
                  const Spacer(),
                  Switch(
                    value: _enabled,
                    onChanged: (value) => setState(() => _enabled = value),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          label: isZh ? '取消' : 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        OpenHandDialogActionButton.primary(
          label: isZh ? '保存' : 'Save',
          onPressed: _save,
        ),
      ],
    );
  }

  Future<void> _pickScriptFile() async {
    final List<XTypeGroup> typeGroups;
    if (Platform.isWindows) {
      typeGroups = [
        const XTypeGroup(label: 'Scripts', extensions: ['ps1', 'bat', 'cmd']),
      ];
    } else {
      typeGroups = [
        const XTypeGroup(label: 'Shell Scripts', extensions: ['sh']),
        const XTypeGroup(label: 'All Files', extensions: ['*']),
      ];
    }
    final file = await openFile(acceptedTypeGroups: typeGroups);
    if (!mounted) return;
    if (file != null) {
      setState(() {
        _scriptPathController.text = file.path;
      });
    }
  }

  void _save() {
    final label = _labelController.text.trim();
    final validationError = _validateForm(label);
    if (validationError != null) {
      setState(() => _formError = validationError);
      return;
    }

    final timeout = clampedIntFromText(
      _timeoutController.text,
      fallback: 12,
      min: 1,
      max: 60,
    );
    final entry = HookEntry(
      id: widget.existing?.id ?? _uuid.v4(),
      event: _selectedEvent,
      label: label,
      scriptPath: _scriptSource == _HookScriptSource.file
          ? _scriptPathController.text.trim()
          : null,
      scriptContent: _scriptSource == _HookScriptSource.inline
          ? _scriptContentController.text
          : null,
      enabled: _enabled,
      timeoutSeconds: timeout,
    );

    final controller = context.read<HooksController>();
    if (_isEditing) {
      controller.updateHook(entry);
    } else {
      controller.addHook(entry);
    }
    Navigator.of(context).pop();
  }

  String? _validateForm(String label) {
    if (label.isEmpty) {
      return isZh ? '请填写 Hook 名称。' : 'Enter a hook label.';
    }
    if (_scriptSource == _HookScriptSource.file &&
        nullIfBlank(_scriptPathController.text) == null) {
      return isZh ? '请选择脚本文件。' : 'Select a script file.';
    }
    if (_scriptSource == _HookScriptSource.inline &&
        nullIfBlank(_scriptContentController.text) == null) {
      return isZh ? '请填写内联脚本内容。' : 'Enter inline script content.';
    }
    return null;
  }
}
