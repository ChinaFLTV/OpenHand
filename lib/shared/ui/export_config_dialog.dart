import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';

import '../../app/theme/openhand_status_colors.dart';
import '../../features/ai/model/ai_session_message.dart';
import '../../features/ai/service/session_io/ai_session_jsonl_exporter.dart';
import '../../l10n/app_localizations.dart';
import '../util/input_value_parsing.dart';
import 'animated_dialog.dart';
import 'openhand_dialog_action_button.dart';
import 'openhand_form_fields.dart';

/// 显示 AI 会话导出配置弹窗；确认后返回 [AiSessionExportConfig]，取消时返回
/// `null`。
///
/// [totalMessages] 用于校验并限制用户输入的消息范围。
Future<AiSessionExportConfig?> showAiSessionExportConfigDialog({
  required BuildContext context,
  required int totalMessages,
  AiSessionExportConfig initial = AiSessionExportConfig.defaults,
  bool allowRange = true,
}) {
  return showAnimatedDialog<AiSessionExportConfig>(
    context: context,
    builder: (dialogContext) => _AiSessionExportConfigDialog(
      totalMessages: totalMessages,
      initial: initial,
      allowRange: allowRange,
    ),
  );
}

/// 显示 Harness 会话导出配置弹窗。
Future<HarnessSessionExportConfig?> showHarnessSessionExportConfigDialog({
  required BuildContext context,
  required int totalPhaseLogs,
  HarnessSessionExportConfig initial = HarnessSessionExportConfig.defaults,
}) {
  return showAnimatedDialog<HarnessSessionExportConfig>(
    context: context,
    builder: (dialogContext) => _HarnessSessionExportConfigDialog(
      totalPhaseLogs: totalPhaseLogs,
      initial: initial,
    ),
  );
}

class _ExportIndexRange {
  const _ExportIndexRange({required this.startIndex, required this.endIndex});

  final int startIndex;
  final int endIndex;
}

const double _kExportRangeFieldSpacing = 12;

_ExportIndexRange? _tryParseExportIndexRange({
  required String startText,
  required String endText,
  required int totalCount,
}) {
  if (totalCount < 1) return null;
  final start = optionalIntFromText(startText);
  final end = optionalIntFromText(endText);
  if (start == null || end == null || start < 1 || end < start) {
    return null;
  }
  if (start > totalCount) return null;
  return _ExportIndexRange(
    startIndex: start,
    endIndex: end > totalCount ? totalCount : end,
  );
}

String _exportRangeErrorText(AppLocalizations l10n) => l10n.exportRangeInvalid;

Widget _buildExportIndexRangeFields({
  required AppLocalizations l10n,
  required TextEditingController startController,
  required TextEditingController endController,
}) {
  return Row(
    children: [
      _ExportIndexTextField(
        controller: startController,
        label: l10n.exportRangeStart,
      ),
      const SizedBox(width: _kExportRangeFieldSpacing),
      _ExportIndexTextField(
        controller: endController,
        label: l10n.exportRangeEnd,
      ),
    ],
  );
}

List<Widget> _buildExportDialogActions({
  required BuildContext context,
  required AppLocalizations l10n,
  required VoidCallback onConfirm,
}) {
  return [
    OpenHandDialogActionButton.secondary(
      onPressed: () => Navigator.of(context).pop(),
      label: l10n.commonCancel,
    ),
    OpenHandDialogActionButton.primary(
      onPressed: onConfirm,
      label: l10n.commonExport,
    ),
  ];
}

void _popExportConfig<T>(BuildContext context, T? config) {
  if (config != null) Navigator.of(context).pop(config);
}

class _ExportIndexTextField extends StatelessWidget {
  const _ExportIndexTextField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}

class _ExportOptionChip extends StatelessWidget {
  const _ExportOptionChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      selectedColor: color.withValues(alpha: 0.22),
      backgroundColor: color.withValues(alpha: 0.08),
      side: BorderSide(color: color.withValues(alpha: selected ? 0.55 : 0.28)),
      labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
      ),
      onSelected: onSelected,
    );
  }
}

class _AiSessionExportConfigDialog extends StatefulWidget {
  const _AiSessionExportConfigDialog({
    required this.totalMessages,
    required this.initial,
    required this.allowRange,
  });

  final int totalMessages;
  final AiSessionExportConfig initial;
  final bool allowRange;

  @override
  State<_AiSessionExportConfigDialog> createState() =>
      _AiSessionExportConfigDialogState();
}

class _AiSessionExportConfigDialogState
    extends State<_AiSessionExportConfigDialog> {
  late Set<AiSessionMessageRole> _roles;
  late Set<AiSessionMessageKind> _kinds;
  late bool _includeDeleted;
  late bool _useRange;
  late TextEditingController _startController;
  late TextEditingController _endController;
  String? _rangeError;

  @override
  void initState() {
    super.initState();
    _roles = (widget.initial.roles == null)
        ? AiSessionMessageRole.values.toSet()
        : Set<AiSessionMessageRole>.from(widget.initial.roles!);
    _kinds = (widget.initial.kinds == null)
        ? AiSessionMessageKind.values.toSet()
        : Set<AiSessionMessageKind>.from(widget.initial.kinds!);
    _includeDeleted = widget.initial.includeDeleted;
    _useRange =
        widget.allowRange &&
        (widget.initial.startIndex != null || widget.initial.endIndex != null);
    _startController = TextEditingController(
      text: widget.initial.startIndex?.toString() ?? '1',
    );
    _endController = TextEditingController(
      text:
          widget.initial.endIndex?.toString() ??
          widget.totalMessages.toString(),
    );
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  String _roleLabel(AiSessionMessageRole role, AppLocalizations l10n) {
    switch (role) {
      case AiSessionMessageRole.system:
        return l10n.exportRoleSystem;
      case AiSessionMessageRole.user:
        return l10n.exportRoleUser;
      case AiSessionMessageRole.assistant:
        return l10n.exportRoleAssistant;
      case AiSessionMessageRole.tool:
        return l10n.exportRoleTool;
    }
  }

  IconData _roleIcon(AiSessionMessageRole role) {
    switch (role) {
      case AiSessionMessageRole.system:
        return Icons.settings_suggest_outlined;
      case AiSessionMessageRole.user:
        return Icons.person_outline_rounded;
      case AiSessionMessageRole.assistant:
        return Icons.smart_toy_outlined;
      case AiSessionMessageRole.tool:
        return Icons.build_outlined;
    }
  }

  Color _roleColor(AiSessionMessageRole role, ColorScheme colorScheme) {
    switch (role) {
      case AiSessionMessageRole.system:
        return colorScheme.tertiary;
      case AiSessionMessageRole.user:
        return OpenHandStatusColors.info;
      case AiSessionMessageRole.assistant:
        return colorScheme.primary;
      case AiSessionMessageRole.tool:
        return OpenHandStatusColors.warning;
    }
  }

  String _kindLabel(AiSessionMessageKind kind, AppLocalizations l10n) {
    switch (kind) {
      case AiSessionMessageKind.user:
        return l10n.exportKindUser;
      case AiSessionMessageKind.assistant:
        return l10n.exportKindAssistant;
      case AiSessionMessageKind.reasoning:
        return l10n.exportKindReasoning;
      case AiSessionMessageKind.toolCall:
        return l10n.exportKindToolCall;
      case AiSessionMessageKind.tool:
        return l10n.exportKindTool;
      case AiSessionMessageKind.compressionPoint:
        return l10n.exportKindCompressionPoint;
      case AiSessionMessageKind.mcp:
        return l10n.exportKindMcp;
      case AiSessionMessageKind.skill:
        return l10n.exportKindSkill;
      case AiSessionMessageKind.hook:
        return l10n.exportKindHook;
      case AiSessionMessageKind.selfLearning:
        return l10n.exportKindSelfLearning;
      case AiSessionMessageKind.fileMutationSummary:
        return l10n.exportKindFileMutationSummary;
      case AiSessionMessageKind.status:
        return l10n.exportKindStatus;
    }
  }

  IconData _kindIcon(AiSessionMessageKind kind) {
    switch (kind) {
      case AiSessionMessageKind.user:
        return Icons.chat_bubble_outline_rounded;
      case AiSessionMessageKind.assistant:
        return Icons.reply_rounded;
      case AiSessionMessageKind.reasoning:
        return Icons.psychology_alt_outlined;
      case AiSessionMessageKind.toolCall:
        return Icons.handyman_outlined;
      case AiSessionMessageKind.tool:
        return Icons.output_outlined;
      case AiSessionMessageKind.compressionPoint:
        return Icons.compress_rounded;
      case AiSessionMessageKind.mcp:
        return Icons.extension_outlined;
      case AiSessionMessageKind.skill:
        return Icons.auto_awesome_outlined;
      case AiSessionMessageKind.hook:
        return Icons.webhook_outlined;
      case AiSessionMessageKind.selfLearning:
        return Icons.school_outlined;
      case AiSessionMessageKind.fileMutationSummary:
        return Icons.folder_open_outlined;
      case AiSessionMessageKind.status:
        return Icons.info_outline_rounded;
    }
  }

  Color _kindColor(AiSessionMessageKind kind, ColorScheme colorScheme) {
    switch (kind) {
      case AiSessionMessageKind.user:
        return OpenHandStatusColors.info;
      case AiSessionMessageKind.assistant:
        return colorScheme.primary;
      case AiSessionMessageKind.reasoning:
        return colorScheme.tertiary;
      case AiSessionMessageKind.toolCall:
        return OpenHandStatusColors.warning;
      case AiSessionMessageKind.tool:
        return colorScheme.secondary;
      case AiSessionMessageKind.compressionPoint:
        return OpenHandStatusColors.caution;
      case AiSessionMessageKind.mcp:
        return OpenHandStatusColors.info;
      case AiSessionMessageKind.skill:
        return colorScheme.primary;
      case AiSessionMessageKind.hook:
        return colorScheme.tertiary;
      case AiSessionMessageKind.selfLearning:
        return OpenHandStatusColors.success;
      case AiSessionMessageKind.fileMutationSummary:
        return colorScheme.secondary;
      case AiSessionMessageKind.status:
        return colorScheme.outline;
    }
  }

  void _toggleRole(AiSessionMessageRole role, bool selected) {
    setState(() {
      if (selected) {
        _roles.add(role);
      } else {
        _roles.remove(role);
      }
    });
  }

  void _toggleKind(AiSessionMessageKind kind, bool selected) {
    setState(() {
      if (selected) {
        _kinds.add(kind);
      } else {
        _kinds.remove(kind);
      }
    });
  }

  void _selectAllRoles(bool selected) {
    setState(() {
      _roles = selected
          ? AiSessionMessageRole.values.toSet()
          : <AiSessionMessageRole>{};
    });
  }

  void _selectAllKinds(bool selected) {
    setState(() {
      _kinds = selected
          ? AiSessionMessageKind.values.toSet()
          : <AiSessionMessageKind>{};
    });
  }

  AiSessionExportConfig? _buildConfig() {
    final l10n = AppLocalizations.of(context)!;
    int? start;
    int? end;
    if (widget.allowRange && _useRange) {
      final range = _tryParseExportIndexRange(
        startText: _startController.text,
        endText: _endController.text,
        totalCount: widget.totalMessages,
      );
      if (range == null) {
        setState(() {
          _rangeError = _exportRangeErrorText(l10n);
        });
        return null;
      }
      start = range.startIndex;
      end = range.endIndex;
    }
    if (_roles.isEmpty) {
      setState(() {
        _rangeError = l10n.exportPickOneRole;
      });
      return null;
    }
    if (_kinds.isEmpty) {
      setState(() {
        _rangeError = l10n.exportPickOneMessageKind;
      });
      return null;
    }
    setState(() => _rangeError = null);
    return AiSessionExportConfig(
      roles: _roles.length == AiSessionMessageRole.values.length
          ? null
          : _roles,
      kinds: _kinds.length == AiSessionMessageKind.values.length
          ? null
          : _kinds,
      includeDeleted: _includeDeleted,
      startIndex: start,
      endIndex: end,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final allRolesSelected =
        _roles.length == AiSessionMessageRole.values.length;
    final allKindsSelected =
        _kinds.length == AiSessionMessageKind.values.length;
    return OpenHandEditorDialogScaffold(
      title: l10n.exportSessionSettingsTitle,
      subtitle: l10n.exportTotalMessages(widget.totalMessages),
      icon: Icons.ios_share_rounded,
      iconColor: colorScheme.primary,
      maxWidth: kOpenHandDialogWidthCompact,
      maxHeight: kOpenHandDialogHeightStandard,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OpenHandDialogSectionCard(
            icon: Icons.badge_outlined,
            accent: colorScheme.primary,
            title: l10n.exportRolesSection,
            subtitle: '${_roles.length}/${AiSessionMessageRole.values.length}',
            trailing: _ExportOptionChip(
              label: l10n.exportAllRoles,
              icon: Icons.select_all_rounded,
              selected: allRolesSelected,
              color: colorScheme.primary,
              onSelected: _selectAllRoles,
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final role in AiSessionMessageRole.values)
                  _ExportOptionChip(
                    label: _roleLabel(role, l10n),
                    icon: _roleIcon(role),
                    selected: _roles.contains(role),
                    color: _roleColor(role, colorScheme),
                    onSelected: (selected) => _toggleRole(role, selected),
                  ),
              ],
            ),
          ),
          kOpenHandGap14,
          OpenHandDialogSectionCard(
            icon: Icons.category_outlined,
            accent: colorScheme.tertiary,
            title: l10n.exportMessageKindsSection,
            subtitle: '${_kinds.length}/${AiSessionMessageKind.values.length}',
            trailing: _ExportOptionChip(
              label: l10n.exportAllKinds,
              icon: Icons.select_all_rounded,
              selected: allKindsSelected,
              color: colorScheme.tertiary,
              onSelected: _selectAllKinds,
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final kind in AiSessionMessageKind.values)
                  _ExportOptionChip(
                    label: _kindLabel(kind, l10n),
                    icon: _kindIcon(kind),
                    selected: _kinds.contains(kind),
                    color: _kindColor(kind, colorScheme),
                    onSelected: (selected) => _toggleKind(kind, selected),
                  ),
              ],
            ),
          ),
          if (widget.allowRange) ...[
            kOpenHandGap14,
            OpenHandDialogSectionCard(
              icon: Icons.linear_scale_rounded,
              accent: OpenHandStatusColors.info,
              title: l10n.exportMessageRangeSection,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OpenHandAnimatedSwitchTile(
                    icon: Icons.filter_alt_outlined,
                    title: l10n.exportOnlyRange,
                    description: '',
                    value: _useRange,
                    onChanged: (value) => setState(() => _useRange = value),
                  ),
                  if (_useRange) ...[
                    kOpenHandGap12,
                    _buildExportIndexRangeFields(
                      l10n: l10n,
                      startController: _startController,
                      endController: _endController,
                    ),
                  ],
                ],
              ),
            ),
          ],
          kOpenHandGap14,
          OpenHandDialogSectionCard(
            icon: Icons.tune_rounded,
            accent: colorScheme.secondary,
            title: l10n.exportOtherOptions,
            child: OpenHandAnimatedSwitchTile(
              icon: Icons.delete_outline_rounded,
              disabledIcon: Icons.delete_outline_rounded,
              title: l10n.exportIncludeDeleted,
              description: '',
              value: _includeDeleted,
              onChanged: (value) => setState(() => _includeDeleted = value),
            ),
          ),
          if (_rangeError != null) ...[
            kOpenHandGap14,
            buildOpenHandDialogValidationMessage(context, message: _rangeError),
          ],
        ],
      ),
      actions: _buildExportDialogActions(
        context: context,
        l10n: l10n,
        onConfirm: () => _popExportConfig(context, _buildConfig()),
      ),
    );
  }
}

class _HarnessSessionExportConfigDialog extends StatefulWidget {
  const _HarnessSessionExportConfigDialog({
    required this.totalPhaseLogs,
    required this.initial,
  });

  final int totalPhaseLogs;
  final HarnessSessionExportConfig initial;

  @override
  State<_HarnessSessionExportConfigDialog> createState() =>
      _HarnessSessionExportConfigDialogState();
}

class _HarnessSessionExportConfigDialogState
    extends State<_HarnessSessionExportConfigDialog> {
  late bool _useRange;
  late TextEditingController _startController;
  late TextEditingController _endController;
  String? _rangeError;

  @override
  void initState() {
    super.initState();
    _useRange =
        widget.initial.startIndex != null || widget.initial.endIndex != null;
    _startController = TextEditingController(
      text: widget.initial.startIndex?.toString() ?? '1',
    );
    _endController = TextEditingController(
      text:
          widget.initial.endIndex?.toString() ??
          widget.totalPhaseLogs.toString(),
    );
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  HarnessSessionExportConfig? _buildConfig() {
    final l10n = AppLocalizations.of(context)!;
    int? start;
    int? end;
    if (_useRange) {
      final range = _tryParseExportIndexRange(
        startText: _startController.text,
        endText: _endController.text,
        totalCount: widget.totalPhaseLogs,
      );
      if (range == null) {
        setState(() {
          _rangeError = _exportRangeErrorText(l10n);
        });
        return null;
      }
      start = range.startIndex;
      end = range.endIndex;
    }
    setState(() => _rangeError = null);
    return HarnessSessionExportConfig(startIndex: start, endIndex: end);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return OpenHandEditorDialogScaffold(
      title: l10n.exportSessionSettingsTitle,
      subtitle: l10n.exportTotalPhaseLogs(widget.totalPhaseLogs),
      icon: Icons.ios_share_rounded,
      iconColor: colorScheme.primary,
      maxWidth: kOpenHandDialogWidthCompact,
      maxHeight: kOpenHandDialogHeightCompact,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OpenHandDialogSectionCard(
            icon: Icons.linear_scale_rounded,
            accent: OpenHandStatusColors.info,
            title: l10n.exportPhaseLogRangeSection,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OpenHandAnimatedSwitchTile(
                  icon: Icons.filter_alt_outlined,
                  title: l10n.exportOnlyRange,
                  description: '',
                  value: _useRange,
                  onChanged: (value) => setState(() => _useRange = value),
                ),
                if (_useRange) ...[
                  kOpenHandGap12,
                  _buildExportIndexRangeFields(
                    l10n: l10n,
                    startController: _startController,
                    endController: _endController,
                  ),
                ],
              ],
            ),
          ),
          if (_rangeError != null) ...[
            kOpenHandGap14,
            buildOpenHandDialogValidationMessage(context, message: _rangeError),
          ],
        ],
      ),
      actions: _buildExportDialogActions(
        context: context,
        l10n: l10n,
        onConfirm: () => _popExportConfig(context, _buildConfig()),
      ),
    );
  }
}
