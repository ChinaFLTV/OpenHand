import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/ai/model/ai_session_message.dart';
import '../../features/ai/service/session_io/ai_session_jsonl_exporter.dart';
import '../../l10n/app_localizations.dart';
import '../util/input_value_parsing.dart';
import 'animated_dialog.dart';
import 'openhand_dialog_action_button.dart';

/// Shows the AI session export configuration dialog. Returns the chosen
/// [AiSessionExportConfig] when the user confirms, or `null` if the dialog
/// is cancelled / dismissed.
///
/// [totalMessages] is the size of the candidate message list and is used to
/// validate / clamp the user-supplied range bounds.
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

/// Shows the Harness session export configuration dialog.
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

const double _kAiSessionExportDialogWidth = 480;
const double _kHarnessExportDialogWidth = 460;
const double _kExportRangeFieldSpacing = 12;
const double _kExportSectionGap = 8;

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
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
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

  void _selectAllRoles(bool? value) {
    setState(() {
      if (value == true) {
        _roles = AiSessionMessageRole.values.toSet();
      } else {
        _roles.clear();
      }
    });
  }

  void _selectAllKinds(bool? value) {
    setState(() {
      if (value == true) {
        _kinds = AiSessionMessageKind.values.toSet();
      } else {
        _kinds.clear();
      }
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
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final allRolesSelected =
        _roles.length == AiSessionMessageRole.values.length;
    final allKindsSelected =
        _kinds.length == AiSessionMessageKind.values.length;
    return buildOpenHandAlertDialog(
      title: Text(l10n.exportSessionSettingsTitle),
      content: buildOpenHandDialogConstrainedContent(
        width: _kAiSessionExportDialogWidth,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.exportTotalMessages(widget.totalMessages),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              _SectionHeader(text: l10n.exportRolesSection),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: allRolesSelected,
                tristate: !allRolesSelected && _roles.isNotEmpty,
                onChanged: _selectAllRoles,
                title: Text(l10n.exportAllRoles),
              ),
              ...AiSessionMessageRole.values.map(
                (role) => CheckboxListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.only(left: 24),
                  value: _roles.contains(role),
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        _roles.add(role);
                      } else {
                        _roles.remove(role);
                      }
                    });
                  },
                  title: Text(_roleLabel(role, l10n)),
                ),
              ),
              const SizedBox(height: 8),
              _SectionHeader(text: l10n.exportMessageKindsSection),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: allKindsSelected,
                tristate: !allKindsSelected && _kinds.isNotEmpty,
                onChanged: _selectAllKinds,
                title: Text(l10n.exportAllKinds),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: AiSessionMessageKind.values
                    .map((kind) {
                      final selected = _kinds.contains(kind);
                      return FilterChip(
                        label: Text(_kindLabel(kind, l10n)),
                        selected: selected,
                        onSelected: (value) {
                          setState(() {
                            if (value) {
                              _kinds.add(kind);
                            } else {
                              _kinds.remove(kind);
                            }
                          });
                        },
                      );
                    })
                    .toList(growable: false),
              ),
              if (widget.allowRange) ...[
                const SizedBox(height: _kExportSectionGap),
                _SectionHeader(text: l10n.exportMessageRangeSection),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.exportOnlyRange),
                  value: _useRange,
                  onChanged: (value) => setState(() => _useRange = value),
                ),
                if (_useRange)
                  _buildExportIndexRangeFields(
                    l10n: l10n,
                    startController: _startController,
                    endController: _endController,
                  ),
              ],
              const SizedBox(height: _kExportSectionGap),
              _SectionHeader(text: l10n.exportOtherOptions),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _includeDeleted,
                onChanged: (value) =>
                    setState(() => _includeDeleted = value ?? false),
                title: Text(l10n.exportIncludeDeleted),
              ),
              const SizedBox(height: _kExportSectionGap),
              buildOpenHandDialogValidationMessage(
                context,
                message: _rangeError,
              ),
            ],
          ),
        ),
      ),
      actions: _buildExportDialogActions(
        context: context,
        l10n: l10n,
        onConfirm: () {
          final config = _buildConfig();
          if (config != null) {
            Navigator.of(context).pop(config);
          }
        },
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
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return buildOpenHandAlertDialog(
      title: Text(l10n.exportSessionSettingsTitle),
      content: buildOpenHandDialogConstrainedContent(
        width: _kHarnessExportDialogWidth,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.exportTotalPhaseLogs(widget.totalPhaseLogs),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              _SectionHeader(text: l10n.exportPhaseLogRangeSection),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.exportOnlyRange),
                value: _useRange,
                onChanged: (value) => setState(() => _useRange = value),
              ),
              if (_useRange)
                _buildExportIndexRangeFields(
                  l10n: l10n,
                  startController: _startController,
                  endController: _endController,
                ),
              const SizedBox(height: 12),
              _SectionHeader(text: l10n.exportOtherOptions),
              buildOpenHandDialogValidationMessage(
                context,
                message: _rangeError,
              ),
            ],
          ),
        ),
      ),
      actions: _buildExportDialogActions(
        context: context,
        l10n: l10n,
        onConfirm: () {
          final config = _buildConfig();
          if (config != null) {
            Navigator.of(context).pop(config);
          }
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
