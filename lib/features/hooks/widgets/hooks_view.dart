import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../app/model/hook_config.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/appear_once.dart';
import '../../../shared/ui/feature_page_shell.dart';
import '../../../shared/ui/feature_state_card.dart';
import '../../../shared/ui/list_removal_transition.dart';
import '../../../shared/ui/micro_press_feedback.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_code_editor.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_form_fields.dart';
import '../../../shared/ui/openhand_reveal_switcher.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_typography.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/localized_text.dart';
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
          onPressed:
              snapshot.isLoading ||
                  snapshot.errorMessage != null ||
                  snapshot.entries.length >= HookEntry.maxEntries
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

enum _HookCardAction { edit, delete }

const double _kHookCardIdentityExtent = 48;
const int _kHookScriptPreviewMaxLines = 3;
const int _kHookScriptPreviewMaxChars = 4000;

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
    final accent = _hookEventAccent(entry.event, colorScheme);
    final enabled = entry.enabled;
    final statusColor = enabled
        ? OpenHandStatusColors.success
        : colorScheme.outline;
    final scriptPath = entry.scriptPath?.trim() ?? '';
    final inline = entry.scriptContent?.trim() ?? '';
    final hasFile = scriptPath.isNotEmpty;
    final hasInline = inline.isNotEmpty;
    final lineCount = hasInline ? inline.split('\n').length : 0;
    final scriptLabel = hasFile
        ? _hookScriptFileName(scriptPath)
        : hasInline
        ? l10n.hooksScriptSourceInline
        : l10n.hooksNoScriptConfigured;
    final scriptColor = hasFile
        ? colorScheme.tertiary
        : hasInline
        ? colorScheme.secondary
        : OpenHandStatusColors.warning;
    final scriptIcon = hasFile
        ? Icons.description_outlined
        : hasInline
        ? Icons.terminal_rounded
        : Icons.warning_amber_rounded;
    final description = hasFile
        ? scriptPath
        : hasInline
        ? openHandLocalizedText(
            context,
            zh: '内联脚本 · $lineCount 行',
            en: 'Inline script · $lineCount lines',
          )
        : l10n.hooksNoScriptConfigured;
    final preview = hasFile
        ? scriptPath
        : hasInline
        ? inline
        : '';
    final lineCountLabel = hasInline ? '$lineCount' : '—';

    return OpenHandFeatureListCard(
      onTap: onEdit,
      identity: OpenHandListIdentity(
        title: entry.label,
        description: description,
        descriptionMaxLines: 2,
        leading: ClipRRect(
          borderRadius: kOpenHandBorderRadius16,
          child: ColoredBox(
            color: accent.withValues(alpha: 0.16),
            child: SizedBox(
              width: _kHookCardIdentityExtent,
              height: _kHookCardIdentityExtent,
              child: Icon(_hookEventIcon(entry.event), color: accent, size: 24),
            ),
          ),
        ),
      ),
      actions: [
        Switch(value: enabled, onChanged: onToggle),
        AnimatedPopupMenuButton<_HookCardAction>(
          tooltip: openHandMoreActionsLabel(context),
          style: openHandFeatureCircleIconButtonStyle(colorScheme),
          onSelected: (action) {
            switch (action) {
              case _HookCardAction.edit:
                onEdit();
              case _HookCardAction.delete:
                onDelete();
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem<_HookCardAction>(
              value: _HookCardAction.edit,
              child: Text(l10n.commonEdit),
            ),
            PopupMenuItem<_HookCardAction>(
              value: _HookCardAction.delete,
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
          icon: enabled
              ? Icons.check_circle_outline_rounded
              : Icons.pause_circle_outline_rounded,
          label: enabled
              ? l10n.mcpServerStatusEnabled
              : l10n.mcpServerStatusDisabled,
          color: statusColor,
        ),
        OpenHandStatusPill(
          icon: _hookEventIcon(entry.event),
          label: entry.event.label(l10n),
          color: accent,
        ),
      ],
      factChips: [
        OpenHandFactChip(
          icon: Icons.timer_outlined,
          label: '${entry.timeoutSeconds}s',
          color: colorScheme.primary,
        ),
        OpenHandFactChip(
          icon: scriptIcon,
          label: scriptLabel,
          color: scriptColor,
        ),
        if (hasInline)
          OpenHandFactChip(
            icon: Icons.format_list_numbered_rounded,
            label: openHandLocalizedText(
              context,
              zh: '$lineCount 行',
              en: '$lineCount lines',
            ),
            color: OpenHandStatusColors.info,
          ),
      ],
      footer: preview.isEmpty
          ? null
          : OpenHandTintedPanel(
              accent: scriptColor,
              icon: scriptIcon,
              title: scriptLabel,
              child: hasInline
                  ? Text.rich(
                      OpenHandCodeSyntaxHighlighter(
                        baseStyle:
                            theme.textTheme.bodySmall?.copyWith(
                              fontFamily: kOpenHandMonospaceFontFamily,
                              height: 1.45,
                            ) ??
                            const TextStyle(
                              fontFamily: kOpenHandMonospaceFontFamily,
                              fontSize: 12,
                              height: 1.45,
                            ),
                        darkSurface: theme.brightness == Brightness.dark,
                      ).build(
                        preview.length > _kHookScriptPreviewMaxChars
                            ? preview.substring(0, _kHookScriptPreviewMaxChars)
                            : preview,
                        language: _hookScriptLanguage(
                          scriptPath: scriptPath,
                          inline: inline,
                          hasFile: hasFile,
                        ),
                        allowAutoDetection: true,
                      ),
                      maxLines: _kHookScriptPreviewMaxLines,
                      overflow: TextOverflow.ellipsis,
                    )
                  : Text(
                      preview,
                      maxLines: _kHookScriptPreviewMaxLines,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: kOpenHandMonospaceFontFamily,
                        height: 1.45,
                      ),
                    ),
            ),
      metrics: [
        (
          label: l10n.listCardMetricStatus,
          value: enabled
              ? l10n.mcpServerStatusEnabled
              : l10n.mcpServerStatusDisabled,
          accent: statusColor,
        ),
        (
          label: l10n.hooksTriggerEvent,
          value: entry.event.label(l10n),
          accent: accent,
        ),
        (
          label: l10n.hooksTimeoutTooltip,
          value: '${entry.timeoutSeconds}s',
          accent: colorScheme.primary,
        ),
        (
          label: openHandLocalizedText(context, zh: '脚本行数', en: 'Lines'),
          value: lineCountLabel,
          accent: OpenHandStatusColors.info,
        ),
      ],
    );
  }
}

enum _HookScriptSource { file, inline }

const double _kHookScriptSourceTwoColumnMinWidth = 520;

String _hookScriptFileName(String path) {
  final normalized = path.trim().replaceAll('\\', '/');
  if (normalized.isEmpty) return normalized;
  final slash = normalized.lastIndexOf('/');
  return slash < 0 ? normalized : normalized.substring(slash + 1);
}

String? _hookScriptLanguage({
  required String scriptPath,
  required String inline,
  required bool hasFile,
}) {
  if (hasFile) {
    final name = _hookScriptFileName(scriptPath).toLowerCase();
    if (name.endsWith('.ps1') || name.endsWith('.psm1')) return 'powershell';
    if (name.endsWith('.bat') || name.endsWith('.cmd')) return 'dos';
    if (name.endsWith('.py')) return 'python';
    if (name.endsWith('.js') || name.endsWith('.mjs')) return 'javascript';
    return 'bash';
  }
  final shebang = inline.split('\n').first.trim().toLowerCase();
  if (shebang.startsWith('#!')) {
    if (shebang.contains('python')) return 'python';
    if (shebang.contains('pwsh') || shebang.contains('powershell')) {
      return 'powershell';
    }
    if (shebang.contains('node')) return 'javascript';
  }
  return Platform.isWindows ? 'powershell' : 'bash';
}

IconData _hookEventIcon(HookEvent event) {
  return switch (event) {
    HookEvent.sessionStart => Icons.play_circle_outline_rounded,
    HookEvent.userPromptSubmit => Icons.chat_outlined,
    HookEvent.preToolUse => Icons.construction_outlined,
    HookEvent.postToolUse => Icons.done_all_rounded,
    HookEvent.subagentStart => Icons.person_add_alt_1_outlined,
    HookEvent.subagentStop => Icons.person_off_outlined,
    HookEvent.stop => Icons.stop_circle_outlined,
    HookEvent.preCompact => Icons.compress_outlined,
    HookEvent.sessionEnd => Icons.flag_outlined,
    HookEvent.errorOccurred => Icons.error_outline_rounded,
  };
}

Color _hookEventAccent(HookEvent event, ColorScheme colorScheme) {
  return switch (event) {
    HookEvent.sessionStart => OpenHandStatusColors.success,
    HookEvent.userPromptSubmit => OpenHandStatusColors.info,
    HookEvent.preToolUse => OpenHandStatusColors.warning,
    HookEvent.postToolUse => OpenHandStatusColors.success,
    HookEvent.subagentStart => colorScheme.tertiary,
    HookEvent.subagentStop => OpenHandStatusColors.caution,
    HookEvent.stop => OpenHandStatusColors.error,
    HookEvent.preCompact => colorScheme.secondary,
    HookEvent.sessionEnd => colorScheme.primary,
    HookEvent.errorOccurred => OpenHandStatusColors.error,
  };
}

class _HookEventChip extends StatelessWidget {
  const _HookEventChip({
    required this.icon,
    required this.label,
    required this.accent,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final foreground = selected ? accent : colorScheme.onSurfaceVariant;
    return MicroPressFeedback(
      enabled: enabled,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: kOpenHandBorderRadius16,
          child: AnimatedContainer(
            duration: openHandMotionDuration(context, kOpenHandMotion180),
            curve: kOpenHandSwitchInCurve,
            padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: 0.16)
                  : colorScheme.surface,
              borderRadius: kOpenHandBorderRadius16,
              border: Border.all(
                color: selected
                    ? accent.withValues(alpha: 0.72)
                    : colorScheme.outlineVariant,
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: selected
                        ? accent.withValues(alpha: 0.22)
                        : colorScheme.surfaceContainerHigh,
                    borderRadius: kOpenHandBorderRadius10,
                  ),
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: Center(
                      child: Icon(icon, size: 16, color: foreground),
                    ),
                  ),
                ),
                kOpenHandHGap8,
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected ? accent : colorScheme.onSurface,
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
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return OpenHandEditorDialogScaffold(
      title: _isEditing ? l10n.hooksEditTitle : l10n.hooksNew,
      subtitle: _isEditing
          ? l10n.hooksEditorEditSubtitle
          : l10n.hooksEditorCreateSubtitle,
      icon: _isEditing ? Icons.edit_note_rounded : Icons.webhook_outlined,
      iconColor: colorScheme.primary,
      busy: _saving,
      closeEnabled: !_saving,
      canPop: !_saving,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          buildOpenHandDialogValidationMessage(context, message: _formError),
          if (_formError != null) kOpenHandGap12,
          _buildBasicsSection(l10n, colorScheme),
          kOpenHandGap14,
          _buildTriggerSection(l10n),
          kOpenHandGap14,
          _buildScriptSection(l10n),
          kOpenHandGap14,
          _buildPolicySection(l10n),
        ],
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          label: l10n.commonCancel,
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        OpenHandDialogActionButton.primary(
          label: l10n.commonSave,
          busy: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }

  Widget _buildBasicsSection(AppLocalizations l10n, ColorScheme colorScheme) {
    return OpenHandDialogSectionCard(
      icon: Icons.badge_outlined,
      accent: colorScheme.primary,
      title: l10n.hooksSectionBasics,
      child: Column(
        children: [
          TextField(
            controller: _labelController,
            enabled: !_saving,
            maxLength: HookEntry.maxLabelCharacters,
            decoration: InputDecoration(
              labelText: l10n.hooksLabelField,
              hintText: l10n.hooksLabelHint,
              counterText: '',
            ),
          ),
          kOpenHandGap12,
          OpenHandAnimatedSwitchTile(
            icon: Icons.bolt_rounded,
            disabledIcon: Icons.power_settings_new_rounded,
            title: l10n.hooksEnabled,
            description: l10n.hooksEnabledBody,
            value: _enabled,
            enabled: !_saving,
            onChanged: (value) => setState(() => _enabled = value),
          ),
        ],
      ),
    );
  }

  Widget _buildTriggerSection(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    return OpenHandDialogSectionCard(
      icon: Icons.alt_route_rounded,
      accent: colorScheme.tertiary,
      title: l10n.hooksSectionTrigger,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final event in HookEvent.values)
            _HookEventChip(
              icon: _hookEventIcon(event),
              label: event.label(l10n),
              accent: _hookEventAccent(event, colorScheme),
              selected: event == _selectedEvent,
              enabled: !_saving,
              onTap: () => setState(() => _selectedEvent = event),
            ),
        ],
      ),
    );
  }

  Widget _buildScriptSection(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return OpenHandDialogSectionCard(
      icon: Icons.terminal_rounded,
      accent: colorScheme.secondary,
      title: l10n.hooksSectionScript,
      subtitle: l10n.hooksScriptSource,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final fileTile = OpenHandSelectTile(
                selected: _scriptSource == _HookScriptSource.file,
                icon: Icons.file_open_outlined,
                label: l10n.hooksScriptSourceFile,
                hint: l10n.hooksScriptSourceFileHint,
                enabled: !_saving,
                onTap: () =>
                    setState(() => _scriptSource = _HookScriptSource.file),
              );
              final inlineTile = OpenHandSelectTile(
                selected: _scriptSource == _HookScriptSource.inline,
                icon: Icons.code_rounded,
                label: l10n.hooksScriptSourceInline,
                hint: l10n.hooksScriptSourceInlineHint,
                enabled: !_saving,
                onTap: () =>
                    setState(() => _scriptSource = _HookScriptSource.inline),
              );
              if (constraints.maxWidth < _kHookScriptSourceTwoColumnMinWidth) {
                return Column(children: [fileTile, kOpenHandGap10, inlineTile]);
              }
              return Row(
                children: [
                  Expanded(child: fileTile),
                  kOpenHandHGap10,
                  Expanded(child: inlineTile),
                ],
              );
            },
          ),
          kOpenHandGap14,
          AnimatedSize(
            duration: openHandMotionDuration(context, kOpenHandMotion220),
            curve: kOpenHandSwitchInCurve,
            alignment: Alignment.topCenter,
            child: OpenHandCrossFadeSwitcher(
              child: _scriptSource == _HookScriptSource.file
                  ? KeyedSubtree(
                      key: const ValueKey<String>('hook-script-file'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _scriptPathController,
                                  enabled: !_saving,
                                  readOnly: true,
                                  decoration: InputDecoration(
                                    labelText: l10n.hooksScriptFilePath,
                                    hintText: l10n.hooksScriptFileHint,
                                  ),
                                ),
                              ),
                              kOpenHandHGap8,
                              FilledButton.tonal(
                                onPressed: _saving ? null : _pickScriptFile,
                                child: Text(l10n.hooksBrowse),
                              ),
                            ],
                          ),
                          kOpenHandGap12,
                          OpenHandTintedPanel(
                            accent: colorScheme.secondary,
                            child: SelectableText(
                              l10n.hooksScriptContextFileHelp,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : KeyedSubtree(
                      key: const ValueKey<String>('hook-script-inline'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _scriptContentController,
                            enabled: !_saving,
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
                          kOpenHandGap12,
                          OpenHandTintedPanel(
                            accent: colorScheme.secondary,
                            child: SelectableText(
                              l10n.hooksScriptContextInlineHelp,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPolicySection(AppLocalizations l10n) {
    return OpenHandDialogSectionCard(
      icon: Icons.timer_outlined,
      accent: Theme.of(context).colorScheme.tertiary,
      title: l10n.hooksSectionPolicy,
      child: TextField(
        controller: _timeoutController,
        enabled: !_saving,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: l10n.hooksTimeoutSeconds,
          hintText: '${HookEntry.defaultTimeoutSeconds}',
          helperText:
              '${HookEntry.minTimeoutSeconds}–${HookEntry.maxTimeoutSeconds}',
        ),
      ),
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
