import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../app/model/hook_config.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/appear_once.dart';
import '../../../shared/ui/feature_page_shell.dart';
import '../../../shared/ui/feature_state_card.dart';
import '../../../shared/ui/list_removal_transition.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_typography.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../ai/index.dart'
    show
        AiResourceUsageKind,
        resourceUsageStatisticsButton,
        showResourceUsageStatisticsDialog;
import '../hooks_controller.dart';

class HooksView extends StatelessWidget {
  const HooksView({super.key});

  @override
  Widget build(BuildContext context) {
    final snapshot = context
        .select<
          HooksController,
          ({bool isLoading, String? errorMessage, List<HookEntry> entries})
        >(
          (controller) => (
            isLoading: controller.isLoading,
            errorMessage: controller.errorMessage,
            entries: controller.entries,
          ),
        );
    final hooksController = context.read<HooksController>();
    final l10n = AppLocalizations.of(context)!;

    final actions = Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.end,
      children: [
        resourceUsageStatisticsButton(
          context,
          onPressed: () => showResourceUsageStatisticsDialog(
            context,
            kind: AiResourceUsageKind.hook,
            resourceLabels: <String, String>{
              for (final entry in snapshot.entries) entry.id: entry.label,
            },
          ),
        ),
        if (snapshot.errorMessage != null)
          FilledButton.tonalIcon(
            onPressed: snapshot.isLoading ? null : hooksController.refresh,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(l10n.commonRetry),
          ),
        FilledButton.icon(
          onPressed: snapshot.isLoading || snapshot.errorMessage != null
              ? null
              : () => _showHookEditorDialog(context, null),
          icon: const Icon(Icons.add_rounded),
          label: Text(l10n.hooksNew),
        ),
      ],
    );

    return FeaturePageShell(
      title: l10n.hooksTitle,
      subtitle: l10n.hooksSubtitle,
      actions: actions,
      successSignal: hooksController.saveSuccessSignal,
      notices: [
        if (snapshot.errorMessage != null && snapshot.entries.isNotEmpty)
          FeatureStateCard.inline(
            icon: Icons.error_outline_rounded,
            tone: FeatureStateTone.error,
            title: l10n.settingsPersistenceLoadFailedTitle,
            body: snapshot.errorMessage!,
          ),
      ],
      body: snapshot.isLoading && snapshot.entries.isEmpty
          ? const Center(
              key: ValueKey<String>('loading'),
              child: CircularProgressIndicator(),
            )
          : snapshot.errorMessage != null && snapshot.entries.isEmpty
          ? FeatureStateCard.centered(
              key: const ValueKey<String>('error'),
              icon: Icons.error_outline_rounded,
              tone: FeatureStateTone.error,
              title: l10n.settingsPersistenceLoadFailedTitle,
              body: snapshot.errorMessage!,
            )
          : snapshot.entries.isEmpty
          ? const SizedBox.expand(
              key: ValueKey<String>('empty'),
              child: _EmptyState(),
            )
          : ScrollConfiguration(
              key: const ValueKey<String>('list'),
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: OpenHandRemovableListScope(
                builder: (context, removal) => ListView.separated(
                  padding: const EdgeInsets.only(top: 2),
                  itemCount: snapshot.entries.length,
                  separatorBuilder: (_, _) => kOpenHandGap12,
                  itemBuilder: (context, index) {
                    final entry = snapshot.entries[index];
                    return AppearOnce(
                      key: ValueKey<String>('hook-entry-${entry.id}'),
                      child: OpenHandListRemovalTransition(
                        collapsed: removal.isRemoving(entry.id),
                        child: _HookEntryCard(
                          entry: entry,
                          onEdit: () => _showHookEditorDialog(context, entry),
                          onToggle: (enabled) {
                            hooksController.toggleHookEnabled(
                              entry.id,
                              enabled: enabled,
                            );
                          },
                          onDelete: () =>
                              _confirmDelete(context, removal, entry),
                        ),
                      ),
                    );
                  },
                ),
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

  Future<void> _confirmDelete(
    BuildContext context,
    OpenHandListRemoval removal,
    HookEntry entry,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: l10n.hooksDeleteTitle,
      message: l10n.hooksDeleteMessage(entry.label),
      cancelLabel: l10n.commonCancel,
      confirmLabel: l10n.commonDelete,
      destructive: true,
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    final controller = context.read<HooksController>();
    await removal.run(entry.id, () => controller.deleteHook(entry.id));
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return FeatureStateCard.centered(
      icon: Icons.webhook_outlined,
      tone: FeatureStateTone.neutral,
      title: l10n.hooksEmptyTitle,
      body: l10n.hooksEmptyBody,
    );
  }
}

class _HookEntryCard extends StatelessWidget {
  const _HookEntryCard({
    required this.entry,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  final HookEntry entry;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: entry.enabled
                    ? colorScheme.primaryContainer
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(kOpenHandRadius16),
              ),
              child: Text(
                entry.event.label(l10n),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: entry.enabled
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            kOpenHandHGap16,
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
                  kOpenHandGap4,
                  Text(
                    _scriptDescription(l10n),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            kOpenHandHGap12,
            OpenHandMetricChip(
              label: '${entry.timeoutSeconds}s',
              tooltip: l10n.hooksTimeoutTooltip,
            ),
            kOpenHandHGap8,
            Switch(value: entry.enabled, onChanged: onToggle),
            kOpenHandHGap8,
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: l10n.commonEdit,
              onPressed: onEdit,
            ),
            kOpenHandHGap4,
            IconButton(
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 20,
                color: colorScheme.error,
              ),
              tooltip: l10n.commonDelete,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }

  String _scriptDescription(AppLocalizations l10n) {
    if (entry.scriptPath != null && entry.scriptPath!.isNotEmpty) {
      return entry.scriptPath!;
    }
    if (entry.scriptContent != null && entry.scriptContent!.isNotEmpty) {
      final firstLine = entry.scriptContent!.split('\n').first.trim();
      return l10n.hooksInlineScriptDescription(firstLine);
    }
    return l10n.hooksNoScriptConfigured;
  }
}

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
  bool _saving = false;
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
      text: '${existing?.timeoutSeconds ?? HookEntry.defaultTimeoutSeconds}',
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return buildOpenHandAlertDialog(
      title: Text(_isEditing ? l10n.hooksEditTitle : l10n.hooksNew),
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
              if (_formError != null) kOpenHandGap12,
              TextField(
                controller: _labelController,
                decoration: InputDecoration(
                  labelText: l10n.hooksLabelField,
                  hintText: l10n.hooksLabelHint,
                ),
              ),
              kOpenHandGap18,
              Text(l10n.hooksTriggerEvent, style: theme.textTheme.titleSmall),
              kOpenHandGap8,
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: HookEvent.values.map((event) {
                  final selected = event == _selectedEvent;
                  return ChoiceChip(
                    label: Text(event.label(l10n)),
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
              kOpenHandGap18,
              Text(l10n.hooksScriptSource, style: theme.textTheme.titleSmall),
              kOpenHandGap8,
              SegmentedButton<_HookScriptSource>(
                segments: [
                  ButtonSegment(
                    value: _HookScriptSource.file,
                    icon: const Icon(Icons.file_open_outlined, size: 18),
                    label: Text(l10n.hooksScriptSourceFile),
                  ),
                  ButtonSegment(
                    value: _HookScriptSource.inline,
                    icon: const Icon(Icons.code_rounded, size: 18),
                    label: Text(l10n.hooksScriptSourceInline),
                  ),
                ],
                selected: {_scriptSource},
                onSelectionChanged: (selected) {
                  setState(() => _scriptSource = selected.first);
                },
              ),
              kOpenHandGap14,
              if (_scriptSource == _HookScriptSource.file) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _scriptPathController,
                        decoration: InputDecoration(
                          labelText: l10n.hooksScriptFilePath,
                          hintText: l10n.hooksScriptFileHint,
                        ),
                        readOnly: true,
                      ),
                    ),
                    kOpenHandHGap8,
                    FilledButton.tonal(
                      onPressed: _pickScriptFile,
                      child: Text(l10n.hooksBrowse),
                    ),
                  ],
                ),
                kOpenHandGap6,
                SelectableText(
                  l10n.hooksScriptContextFileHelp,
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
                    fontFamily: kOpenHandMonospaceFontFamily,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.all(12),
                    hintText: Platform.isWindows
                        ? l10n.hooksInlineWindowsHint
                        : l10n.hooksInlineShellHint,
                    hintStyle: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.5,
                      ),
                      fontFamily: kOpenHandMonospaceFontFamily,
                      fontSize: 13,
                    ),
                  ),
                ),
                kOpenHandGap6,
                SelectableText(
                  l10n.hooksScriptContextInlineHelp,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ],
              kOpenHandGap18,
              Row(
                children: [
                  Text(
                    l10n.hooksTimeoutSeconds,
                    style: theme.textTheme.titleSmall,
                  ),
                  kOpenHandHGap12,
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
              kOpenHandGap14,
              Row(
                children: [
                  Text(l10n.hooksEnabled, style: theme.textTheme.titleSmall),
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
          label: l10n.commonCancel,
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        OpenHandDialogActionButton.primary(
          label: l10n.commonSave,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }

  Future<void> _pickScriptFile() async {
    final l10n = AppLocalizations.of(context)!;
    final List<XTypeGroup> typeGroups;
    if (Platform.isWindows) {
      typeGroups = [
        XTypeGroup(
          label: l10n.hooksFileTypeScripts,
          extensions: const ['ps1', 'bat', 'cmd'],
        ),
      ];
    } else {
      typeGroups = [
        XTypeGroup(
          label: l10n.hooksFileTypeShellScripts,
          extensions: const ['sh'],
        ),
        XTypeGroup(label: l10n.hooksFileTypeAllFiles, extensions: const ['*']),
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

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context)!;
    final label = _labelController.text.trim();
    final validationError = _validateForm(label, l10n);
    if (validationError != null) {
      setState(() => _formError = validationError);
      return;
    }

    final timeout = HookEntry.timeoutSecondsFromValue(_timeoutController.text);
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

    setState(() => _saving = true);
    try {
      final controller = context.read<HooksController>();
      final saved = _isEditing
          ? await controller.updateHook(entry)
          : await controller.addHook(entry);
      if (!mounted) return;
      if (saved) {
        Navigator.of(context).pop();
      } else {
        setState(() {
          _formError =
              controller.errorMessage ?? l10n.settingsPersistenceSaveFailedBody;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _validateForm(String label, AppLocalizations l10n) {
    if (label.isEmpty) {
      return l10n.hooksValidationLabelRequired;
    }
    if (_scriptSource == _HookScriptSource.file &&
        nullIfBlank(_scriptPathController.text) == null) {
      return l10n.hooksValidationScriptFileRequired;
    }
    if (_scriptSource == _HookScriptSource.inline &&
        nullIfBlank(_scriptContentController.text) == null) {
      return l10n.hooksValidationInlineScriptRequired;
    }
    return null;
  }
}
