import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/ai/model/ai_session_message.dart';
import '../../features/ai/service/session_io/ai_session_jsonl_exporter.dart';
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
}) {
  return showAnimatedDialog<AiSessionExportConfig>(
    context: context,
    builder: (dialogContext) => _AiSessionExportConfigDialog(
      totalMessages: totalMessages,
      initial: initial,
    ),
  );
}

/// Shows the Hardness session export configuration dialog.
Future<HardnessSessionExportConfig?> showHardnessSessionExportConfigDialog({
  required BuildContext context,
  required int totalPhaseLogs,
  HardnessSessionExportConfig initial = HardnessSessionExportConfig.defaults,
}) {
  return showAnimatedDialog<HardnessSessionExportConfig>(
    context: context,
    builder: (dialogContext) => _HardnessSessionExportConfigDialog(
      totalPhaseLogs: totalPhaseLogs,
      initial: initial,
    ),
  );
}

class _AiSessionExportConfigDialog extends StatefulWidget {
  const _AiSessionExportConfigDialog({
    required this.totalMessages,
    required this.initial,
  });

  final int totalMessages;
  final AiSessionExportConfig initial;

  @override
  State<_AiSessionExportConfigDialog> createState() =>
      _AiSessionExportConfigDialogState();
}

class _AiSessionExportConfigDialogState
    extends State<_AiSessionExportConfigDialog> {
  late Set<AiSessionMessageRole> _roles;
  late Set<AiSessionMessageKind> _kinds;
  late bool _includeDeleted;
  late bool _prettyPrint;
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
    _prettyPrint = widget.initial.prettyPrint;
    _useRange =
        widget.initial.startIndex != null || widget.initial.endIndex != null;
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

  bool get _isZh =>
      Localizations.localeOf(context).languageCode.startsWith('zh');

  String _roleLabel(AiSessionMessageRole role) {
    switch (role) {
      case AiSessionMessageRole.system:
        return _isZh ? '系统 (system)' : 'System';
      case AiSessionMessageRole.user:
        return _isZh ? '用户 (user)' : 'User';
      case AiSessionMessageRole.assistant:
        return _isZh ? '助手 (assistant)' : 'Assistant';
      case AiSessionMessageRole.tool:
        return _isZh ? '工具 (tool)' : 'Tool';
    }
  }

  String _kindLabel(AiSessionMessageKind kind) {
    if (_isZh) {
      switch (kind) {
        case AiSessionMessageKind.user:
          return '用户消息';
        case AiSessionMessageKind.assistant:
          return '助手回复';
        case AiSessionMessageKind.reasoning:
          return '思考过程';
        case AiSessionMessageKind.toolCall:
          return '工具调用';
        case AiSessionMessageKind.tool:
          return '工具结果';
        case AiSessionMessageKind.compressionPoint:
          return '压缩节点';
        case AiSessionMessageKind.mcp:
          return 'MCP 事件';
        case AiSessionMessageKind.skill:
          return '技能事件';
        case AiSessionMessageKind.hook:
          return 'Hook 事件';
        case AiSessionMessageKind.selfLearning:
          return '自学习';
        case AiSessionMessageKind.fileMutationSummary:
          return '文件变动总结';
        case AiSessionMessageKind.status:
          return '状态消息';
      }
    }
    return kind.storageValue;
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
    int? start;
    int? end;
    if (_useRange) {
      start = int.tryParse(_startController.text.trim());
      end = int.tryParse(_endController.text.trim());
      if (start == null || end == null || start < 1 || end < start) {
        setState(() {
          _rangeError = _isZh
              ? '请输入有效区间 (1 ≤ 起始 ≤ 结束)'
              : 'Enter a valid range (1 ≤ start ≤ end)';
        });
        return null;
      }
      if (end > widget.totalMessages) end = widget.totalMessages;
    }
    if (_roles.isEmpty) {
      setState(() {
        _rangeError = _isZh ? '请至少选择一个 role。' : 'Pick at least one role.';
      });
      return null;
    }
    if (_kinds.isEmpty) {
      setState(() {
        _rangeError = _isZh
            ? '请至少选择一个消息类型。'
            : 'Pick at least one message kind.';
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
      prettyPrint: _prettyPrint,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allRolesSelected =
        _roles.length == AiSessionMessageRole.values.length;
    final allKindsSelected =
        _kinds.length == AiSessionMessageKind.values.length;
    return AlertDialog(
      title: Text(_isZh ? '导出会话配置' : 'Export Session Settings'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _isZh
                    ? '共 ${widget.totalMessages} 条消息可导出'
                    : 'Total messages available: ${widget.totalMessages}',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              _SectionHeader(text: _isZh ? '导出 Role' : 'Roles'),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: allRolesSelected,
                tristate: !allRolesSelected && _roles.isNotEmpty,
                onChanged: _selectAllRoles,
                title: Text(_isZh ? '全部 role' : 'All roles'),
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
                  title: Text(_roleLabel(role)),
                ),
              ),
              const SizedBox(height: 8),
              _SectionHeader(text: _isZh ? '消息类型 (kind)' : 'Message Kinds'),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: allKindsSelected,
                tristate: !allKindsSelected && _kinds.isNotEmpty,
                onChanged: _selectAllKinds,
                title: Text(_isZh ? '全部类型' : 'All kinds'),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: AiSessionMessageKind.values
                    .map((kind) {
                      final selected = _kinds.contains(kind);
                      return FilterChip(
                        label: Text(_kindLabel(kind)),
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
              const SizedBox(height: 8),
              _SectionHeader(text: _isZh ? '消息区间' : 'Message Range'),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _isZh
                      ? '仅导出指定区间 (1-based, 包含两端)'
                      : 'Export only a range (1-based, inclusive)',
                ),
                value: _useRange,
                onChanged: (value) => setState(() => _useRange = value),
              ),
              if (_useRange)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _startController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          labelText: _isZh ? '起始' : 'Start',
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _endController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          labelText: _isZh ? '结束' : 'End',
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              _SectionHeader(text: _isZh ? '其他选项' : 'Other Options'),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _includeDeleted,
                onChanged: (value) =>
                    setState(() => _includeDeleted = value ?? false),
                title: Text(_isZh ? '包含已删除消息' : 'Include deleted messages'),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _prettyPrint,
                onChanged: (value) =>
                    setState(() => _prettyPrint = value ?? false),
                title: Text(
                  _isZh
                      ? 'JSON 格式化输出 (可读性优先, 非严格 JSONL)'
                      : 'Pretty-print JSON (multi-line per entry)',
                ),
              ),
              if (_rangeError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _rangeError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          label: _isZh ? '取消' : 'Cancel',
        ),
        OpenHandDialogActionButton.primary(
          onPressed: () {
            final config = _buildConfig();
            if (config != null) {
              Navigator.of(context).pop(config);
            }
          },
          label: _isZh ? '确认导出' : 'Export',
        ),
      ],
    );
  }
}

class _HardnessSessionExportConfigDialog extends StatefulWidget {
  const _HardnessSessionExportConfigDialog({
    required this.totalPhaseLogs,
    required this.initial,
  });

  final int totalPhaseLogs;
  final HardnessSessionExportConfig initial;

  @override
  State<_HardnessSessionExportConfigDialog> createState() =>
      _HardnessSessionExportConfigDialogState();
}

class _HardnessSessionExportConfigDialogState
    extends State<_HardnessSessionExportConfigDialog> {
  late bool _useRange;
  late bool _prettyPrint;
  late TextEditingController _startController;
  late TextEditingController _endController;
  String? _rangeError;

  @override
  void initState() {
    super.initState();
    _useRange =
        widget.initial.startIndex != null || widget.initial.endIndex != null;
    _prettyPrint = widget.initial.prettyPrint;
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

  bool get _isZh =>
      Localizations.localeOf(context).languageCode.startsWith('zh');

  HardnessSessionExportConfig? _buildConfig() {
    int? start;
    int? end;
    if (_useRange) {
      start = int.tryParse(_startController.text.trim());
      end = int.tryParse(_endController.text.trim());
      if (start == null || end == null || start < 1 || end < start) {
        setState(() {
          _rangeError = _isZh
              ? '请输入有效区间 (1 ≤ 起始 ≤ 结束)'
              : 'Enter a valid range (1 ≤ start ≤ end)';
        });
        return null;
      }
      if (end > widget.totalPhaseLogs) end = widget.totalPhaseLogs;
    }
    setState(() => _rangeError = null);
    return HardnessSessionExportConfig(
      startIndex: start,
      endIndex: end,
      prettyPrint: _prettyPrint,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(_isZh ? '导出会话配置' : 'Export Session Settings'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _isZh
                    ? '共 ${widget.totalPhaseLogs} 条阶段日志可导出'
                    : 'Total phase logs available: ${widget.totalPhaseLogs}',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              _SectionHeader(text: _isZh ? '阶段日志区间' : 'Phase Log Range'),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _isZh
                      ? '仅导出指定区间 (1-based, 包含两端)'
                      : 'Export only a range (1-based, inclusive)',
                ),
                value: _useRange,
                onChanged: (value) => setState(() => _useRange = value),
              ),
              if (_useRange)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _startController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          labelText: _isZh ? '起始' : 'Start',
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _endController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          labelText: _isZh ? '结束' : 'End',
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              _SectionHeader(text: _isZh ? '其他选项' : 'Other Options'),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _prettyPrint,
                onChanged: (value) =>
                    setState(() => _prettyPrint = value ?? false),
                title: Text(
                  _isZh
                      ? 'JSON 格式化输出 (可读性优先, 非严格 JSONL)'
                      : 'Pretty-print JSON (multi-line per entry)',
                ),
              ),
              if (_rangeError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _rangeError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          label: _isZh ? '取消' : 'Cancel',
        ),
        OpenHandDialogActionButton.primary(
          onPressed: () {
            final config = _buildConfig();
            if (config != null) {
              Navigator.of(context).pop(config);
            }
          },
          label: _isZh ? '确认导出' : 'Export',
        ),
      ],
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
