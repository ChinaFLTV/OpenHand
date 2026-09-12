import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';

import '../../app/theme/openhand_status_colors.dart';
import '../../features/ai/model/ai_session_message.dart';
import '../../features/ai/service/session_io/ai_session_jsonl_exporter.dart';
import '../../l10n/app_localizations.dart';
import '../util/input_value_parsing.dart';
import '../util/localized_text.dart';
import '../util/text_clip.dart';
import '../util/text_normalization.dart';
import 'animated_dialog.dart';
import 'motion_durations.dart';
import 'motion_preference.dart';
import 'oh_pill.dart';
import 'openhand_dialog_action_button.dart';
import 'openhand_form_fields.dart';
import 'openhand_reveal_switcher.dart';

/// 显示 AI 会话导出配置弹窗；确认后返回 [AiSessionExportConfig]，取消时返回
/// `null`。
///
/// [totalMessages] 用于校验并限制区间；传入 [messages] 后按消息内容点选
/// 起点和终点，不再要求用户手填轮次序号。
Future<AiSessionExportConfig?> showAiSessionExportConfigDialog({
  required BuildContext context,
  required int totalMessages,
  List<AiSessionMessage> messages = const <AiSessionMessage>[],
  AiSessionExportConfig initial = AiSessionExportConfig.defaults,
  bool allowRange = true,
}) {
  return showAnimatedDialog<AiSessionExportConfig>(
    context: context,
    builder: (dialogContext) => _AiSessionExportConfigDialog(
      totalMessages: totalMessages,
      messages: messages,
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
const int _kExportRangePreviewChars = 72;
const double _kExportRangeListMaxHeight = 280;
const double _kExportRangeTileHeight = 64;

enum _ExportRangeEndpoint { start, end }

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

class _ExportRangeMessageTile extends StatelessWidget {
  const _ExportRangeMessageTile({
    required this.index,
    required this.kindLabel,
    required this.preview,
    required this.icon,
    required this.accent,
    required this.inRange,
    required this.isStart,
    required this.isEnd,
    required this.deleted,
    required this.onTap,
  });

  final int index;
  final String kindLabel;
  final String preview;
  final IconData icon;
  final Color accent;
  final bool inRange;
  final bool isStart;
  final bool isEnd;
  final bool deleted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final endpoint = isStart || isEnd;
    final tone = isStart
        ? colorScheme.primary
        : isEnd
        ? OpenHandStatusColors.success
        : accent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: openHandMotionDuration(context, kOpenHandMotion180),
          curve: kOpenHandSwitchInCurve,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: inRange
                ? Color.alphaBlend(
                    tone.withValues(alpha: endpoint ? 0.16 : 0.07),
                    colorScheme.surfaceContainerLow,
                  )
                : Colors.transparent,
          ),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.16),
                  borderRadius: kOpenHandBorderRadius10,
                ),
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Center(child: Icon(icon, size: 16, color: tone)),
                ),
              ),
              kOpenHandHGap10,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '#$index · $kindLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: tone,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    kOpenHandGap2,
                    Text(
                      preview.isEmpty ? kindLabel : preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: deleted
                            ? colorScheme.outline
                            : colorScheme.onSurfaceVariant,
                        decoration: deleted
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
              if (endpoint)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: tone.withValues(alpha: 0.16),
                      borderRadius: kOpenHandPillBorderRadius,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      child: Text(
                        isStart && isEnd
                            ? openHandLocalizedText(
                                context,
                                zh: '起止',
                                zhHant: '起止',
                                en: 'Only',
                                fr: 'Seul',
                                de: 'Nur',
                                ja: 'のみ',
                              )
                            : isStart
                            ? openHandLocalizedText(
                                context,
                                zh: '起',
                                zhHant: '起',
                                en: 'From',
                                fr: 'Début',
                                de: 'Von',
                                ja: '開始',
                              )
                            : openHandLocalizedText(
                                context,
                                zh: '止',
                                zhHant: '止',
                                en: 'To',
                                fr: 'Fin',
                                de: 'Bis',
                                ja: '終了',
                              ),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: tone,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AiSessionExportConfigDialog extends StatefulWidget {
  const _AiSessionExportConfigDialog({
    required this.totalMessages,
    required this.messages,
    required this.initial,
    required this.allowRange,
  });

  final int totalMessages;
  final List<AiSessionMessage> messages;
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
  late int _startIndex;
  late int _endIndex;
  late _ExportRangeEndpoint _activeEndpoint;
  TextEditingController? _startController;
  TextEditingController? _endController;
  ScrollController? _rangeScrollController;
  String? _rangeError;

  bool get _hasMessagePicker => widget.allowRange && widget.messages.isNotEmpty;

  int get _rangeCount {
    if (widget.messages.isNotEmpty) return widget.messages.length;
    return widget.totalMessages < 0 ? 0 : widget.totalMessages;
  }

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
    final count = math.max(_rangeCount, 1);
    final initialStart = widget.initial.startIndex ?? 1;
    final initialEnd = widget.initial.endIndex ?? count;
    _startIndex = initialStart.clamp(1, count);
    _endIndex = initialEnd.clamp(_startIndex, count);
    _activeEndpoint = _ExportRangeEndpoint.start;
    if (_hasMessagePicker) {
      _rangeScrollController = ScrollController();
      if (_useRange) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scrollRangeListTo(_startIndex);
        });
      }
    } else {
      _startController = TextEditingController(text: '$_startIndex');
      _endController = TextEditingController(text: '$_endIndex');
    }
  }

  @override
  void dispose() {
    _rangeScrollController?.dispose();
    _startController?.dispose();
    _endController?.dispose();
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

  void _scrollRangeListTo(int oneBased) {
    final controller = _rangeScrollController;
    if (controller == null || !controller.hasClients) return;
    final maxExtent = controller.position.maxScrollExtent;
    if (maxExtent <= 0) return;
    final target = ((oneBased - 1) * _kExportRangeTileHeight).clamp(
      0.0,
      maxExtent,
    );
    final duration = openHandMotionDuration(context, kOpenHandMotion280);
    if (duration <= Duration.zero) {
      controller.jumpTo(target);
      return;
    }
    controller.animateTo(
      target,
      duration: duration,
      curve: kOpenHandEntranceCurve,
    );
  }

  void _assignRangeIndex(int oneBased) {
    final count = _rangeCount;
    if (count < 1) return;
    final index = oneBased.clamp(1, count);
    setState(() {
      if (_activeEndpoint == _ExportRangeEndpoint.start) {
        _startIndex = index;
        if (_startIndex > _endIndex) _endIndex = _startIndex;
        _activeEndpoint = _ExportRangeEndpoint.end;
      } else {
        _endIndex = index;
        if (_endIndex < _startIndex) _startIndex = _endIndex;
      }
      _rangeError = null;
    });
  }

  void _setRangeValues(int start, int end) {
    final count = _rangeCount;
    if (count < 1) return;
    final nextStart = start.clamp(1, count);
    final nextEnd = end.clamp(nextStart, count);
    setState(() {
      _startIndex = nextStart;
      _endIndex = nextEnd;
      _rangeError = null;
    });
  }

  AiSessionExportConfig? _buildConfig() {
    final l10n = AppLocalizations.of(context)!;
    int? start;
    int? end;
    if (widget.allowRange && _useRange) {
      if (_hasMessagePicker) {
        if (_startIndex < 1 ||
            _endIndex < _startIndex ||
            _startIndex > _rangeCount) {
          setState(() => _rangeError = _exportRangeErrorText(l10n));
          return null;
        }
        start = _startIndex;
        end = _endIndex;
      } else {
        final range = _tryParseExportIndexRange(
          startText: _startController?.text ?? '',
          endText: _endController?.text ?? '',
          totalCount: _rangeCount,
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

  String _messagePreview(AiSessionMessage message) {
    final text = collapseInlineWhitespace(message.content);
    final clipped = clipTextWithEllipsis(text, _kExportRangePreviewChars);
    return clipped.trim();
  }

  Widget _buildMessageRangePicker(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) {
    final messages = widget.messages;
    final count = messages.length;
    final startMessage = messages[_startIndex - 1];
    final endMessage = messages[_endIndex - 1];
    final listHeight = math.min(
      _kExportRangeListMaxHeight,
      count * _kExportRangeTileHeight,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OpenHandRangeEndpointPair(
          start: OpenHandRangeEndpointCard(
            label: l10n.exportRangeStart,
            badge: openHandLocalizedText(
              context,
              zh: '起',
              zhHant: '起',
              en: 'From',
              fr: 'Début',
              de: 'Von',
              ja: '開始',
            ),
            indexLabel:
                '#$_startIndex · ${_kindLabel(startMessage.kind, l10n)}',
            preview: _messagePreview(startMessage),
            accent: colorScheme.primary,
            selected: _activeEndpoint == _ExportRangeEndpoint.start,
            onTap: () {
              setState(() => _activeEndpoint = _ExportRangeEndpoint.start);
              _scrollRangeListTo(_startIndex);
            },
          ),
          end: OpenHandRangeEndpointCard(
            label: l10n.exportRangeEnd,
            badge: openHandLocalizedText(
              context,
              zh: '止',
              zhHant: '止',
              en: 'To',
              fr: 'Fin',
              de: 'Bis',
              ja: '終了',
            ),
            indexLabel: '#$_endIndex · ${_kindLabel(endMessage.kind, l10n)}',
            preview: _messagePreview(endMessage),
            accent: OpenHandStatusColors.success,
            selected: _activeEndpoint == _ExportRangeEndpoint.end,
            onTap: () {
              setState(() => _activeEndpoint = _ExportRangeEndpoint.end);
              _scrollRangeListTo(_endIndex);
            },
          ),
        ),
        if (count > 1) ...[
          kOpenHandGap8,
          RangeSlider(
            values: RangeValues(_startIndex.toDouble(), _endIndex.toDouble()),
            min: 1,
            max: count.toDouble(),
            divisions: count - 1,
            labels: RangeLabels('#$_startIndex', '#$_endIndex'),
            onChanged: (values) {
              _setRangeValues(values.start.round(), values.end.round());
            },
            onChangeEnd: (values) {
              _scrollRangeListTo(
                _activeEndpoint == _ExportRangeEndpoint.start
                    ? values.start.round()
                    : values.end.round(),
              );
            },
          ),
        ],
        kOpenHandGap8,
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: listHeight),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                OpenHandStatusColors.info.withValues(alpha: 0.06),
                colorScheme.surfaceContainerLow,
              ),
              borderRadius: kOpenHandBorderRadius16,
              border: Border.all(
                color: OpenHandStatusColors.info.withValues(alpha: 0.16),
              ),
            ),
            child: ClipRRect(
              borderRadius: kOpenHandBorderRadius16,
              child: ListView.builder(
                controller: _rangeScrollController,
                primary: false,
                itemExtent: _kExportRangeTileHeight,
                itemCount: count,
                physics: openHandDialogAwareScrollPhysics(context),
                itemBuilder: (context, offset) {
                  final message = messages[offset];
                  final index = offset + 1;
                  final inRange = index >= _startIndex && index <= _endIndex;
                  return _ExportRangeMessageTile(
                    index: index,
                    kindLabel: _kindLabel(message.kind, l10n),
                    preview: _messagePreview(message),
                    icon: _kindIcon(message.kind),
                    accent: _kindColor(message.kind, colorScheme),
                    inRange: inRange,
                    isStart: index == _startIndex,
                    isEnd: index == _endIndex,
                    deleted: message.isDeleted,
                    onTap: () => _assignRangeIndex(index),
                  );
                },
              ),
            ),
          ),
        ),
      ],
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
      maxWidth: kOpenHandDialogWidthStandard,
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
              subtitle: _useRange
                  ? openHandLocalizedText(
                      context,
                      zh: '第 $_startIndex–$_endIndex 条 · 共 ${_endIndex - _startIndex + 1} 条',
                      zhHant:
                          '第 $_startIndex–$_endIndex 則 · 共 ${_endIndex - _startIndex + 1} 則',
                      en: '#$_startIndex–$_endIndex · ${_endIndex - _startIndex + 1} messages',
                      fr: 'n° $_startIndex–$_endIndex · ${_endIndex - _startIndex + 1} messages',
                      de: 'Nr. $_startIndex–$_endIndex · ${_endIndex - _startIndex + 1} Nachrichten',
                      ja: '$_startIndex–$_endIndex 番 · ${_endIndex - _startIndex + 1} 件',
                    )
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OpenHandAnimatedSwitchTile(
                    icon: Icons.filter_alt_outlined,
                    title: openHandLocalizedText(
                      context,
                      zh: '只导出选中的消息区间',
                      zhHant: '只匯出選中的訊息區間',
                      en: 'Export only the selected range',
                      fr: 'Exporter uniquement la plage sélectionnée',
                      de: 'Nur den gewählten Bereich exportieren',
                      ja: '選択した範囲だけエクスポート',
                    ),
                    description: _hasMessagePicker
                        ? openHandLocalizedText(
                            context,
                            zh: '先点起点卡片或列表中的消息，再点终点。',
                            zhHant: '先點起點卡片或清單中的訊息，再點終點。',
                            en: 'Tap a start message, then an end message.',
                            fr: 'Touchez un message de début, puis de fin.',
                            de: 'Tippen Sie zuerst die Start-, dann die Endnachricht.',
                            ja: '開始メッセージを選び、次に終了メッセージを選びます。',
                          )
                        : '',
                    value: _useRange,
                    onChanged: (value) {
                      setState(() => _useRange = value);
                      if (value && _hasMessagePicker) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _scrollRangeListTo(_startIndex);
                        });
                      }
                    },
                  ),
                  OpenHandVerticalRevealSwitcher(
                    presentKey: const ValueKey<String>('export-range-body'),
                    slideBeginOffsetY: 0.04,
                    child: !_useRange
                        ? null
                        : Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: _hasMessagePicker
                                ? _buildMessageRangePicker(
                                    context,
                                    l10n,
                                    colorScheme,
                                  )
                                : _buildExportIndexRangeFields(
                                    l10n: l10n,
                                    startController: _startController!,
                                    endController: _endController!,
                                  ),
                          ),
                  ),
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
