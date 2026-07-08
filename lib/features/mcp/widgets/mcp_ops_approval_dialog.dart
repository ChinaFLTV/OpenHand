import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_safe_scrollbar.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/localized_text.dart';
import '../model/mcp_server_ops.dart';

Future<bool?> showMcpOpsWriteApprovalDialog(
  BuildContext context, {
  required McpOpsApprovalRequest request,
  ValueChanged<BuildContext>? onDialogContext,
}) {
  return showAnimatedDialog<bool>(
    context: context,
    barrierDismissible: false,
    dismissOnEscape: false,
    builder: (dialogContext) {
      onDialogContext?.call(dialogContext);
      return _McpOpsWriteApprovalDialog(request: request);
    },
  );
}

class _McpOpsWriteApprovalDialog extends StatefulWidget {
  const _McpOpsWriteApprovalDialog({required this.request});

  final McpOpsApprovalRequest request;

  @override
  State<_McpOpsWriteApprovalDialog> createState() =>
      _McpOpsWriteApprovalDialogState();
}

class _McpOpsWriteApprovalDialogState
    extends State<_McpOpsWriteApprovalDialog> {
  static const Duration _tick = Duration(seconds: 1);

  final ScrollController _bodyScrollController = ScrollController();
  final FocusNode _shortcutFocusNode = FocusNode();
  Timer? _timer;
  bool _isExpanded = false;
  DateTime _now = DateTime.now().toUtc();

  String get _argumentsPreview => widget.request.argumentsPreview.trim();

  bool get _isLongPayload =>
      _argumentsPreview.length > 220 || _argumentsPreview.contains('\n');

  String get _shortPayload {
    if (!_isLongPayload) return _argumentsPreview;
    final firstLine = _argumentsPreview.split('\n').first.trim();
    final prefix = firstLine.length > 180
        ? firstLine.substring(0, 180)
        : firstLine;
    final omitted = math.max(0, _argumentsPreview.length - prefix.length);
    return '$prefix... [omitted $omitted chars]';
  }

  Duration get _remaining {
    final value = widget.request.expiresAt.difference(_now);
    return value.isNegative ? Duration.zero : value;
  }

  double get _remainingProgress {
    final total = widget.request.expiresAt
        .difference(widget.request.requestedAt)
        .inMilliseconds;
    if (total <= 0) return 0;
    return (_remaining.inMilliseconds / total).clamp(0.0, 1.0);
  }

  void _closeWith(bool approved) {
    if (!mounted) return;
    Navigator.of(context).pop(approved);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _shortcutFocusNode.requestFocus();
    });
    _timer = Timer.periodic(_tick, (_) {
      if (!mounted) return;
      final nextNow = DateTime.now().toUtc();
      setState(() => _now = nextNow);
      if (!nextNow.isBefore(widget.request.expiresAt)) {
        _closeWith(false);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _shortcutFocusNode.dispose();
    _bodyScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const warning = OpenHandStatusColors.warning;
    return Focus(
      focusNode: _shortcutFocusNode,
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) {
          _closeWith(true);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: buildOpenHandResponsiveDialogShell(
        context: context,
        maxWidth: 860,
        maxHeight: double.infinity,
        maxHeightFraction: 0.82,
        safeAreaMinimum: const EdgeInsets.symmetric(
          horizontal: 28,
          vertical: 24,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: warning.withValues(alpha: 0.28),
                      ),
                    ),
                    child: const Icon(
                      Icons.verified_user_rounded,
                      color: warning,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          openHandLocalizedText(
                            context,
                            zh: '确认 MCP 写调用',
                            en: 'Confirm MCP Write Call',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          openHandLocalizedText(
                            context,
                            zh: '外部客户端请求执行写类型工具，需要你明确放行后才会运行。',
                            en: 'An external client requested a write-capable tool. OpenHand will run it only after your approval.',
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: _remainingProgress,
                  minHeight: 6,
                  backgroundColor: cs.surfaceContainerHighest,
                  valueColor: const AlwaysStoppedAnimation<Color>(warning),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ApprovalChip(
                    icon: Icons.extension_rounded,
                    label: widget.request.toolName,
                  ),
                  _ApprovalChip(
                    icon: Icons.devices_other_rounded,
                    label: widget.request.clientName,
                  ),
                  _ApprovalChip(
                    icon: Icons.public_rounded,
                    label: widget.request.ipAddress,
                  ),
                  _ApprovalChip(
                    icon: Icons.hourglass_top_rounded,
                    label: _formatRemaining(context, _remaining),
                    color: warning,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: OpenHandSafeScrollbar(
                  controller: _bodyScrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _bodyScrollController,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ApprovalInfoPanel(
                          icon: Icons.route_rounded,
                          title: openHandLocalizedText(
                            context,
                            zh: '调用环境',
                            en: 'Call Context',
                          ),
                          rows: {
                            openHandLocalizedText(
                              context,
                              zh: '工具',
                              en: 'Tool',
                            ): widget.request.toolName,
                            openHandLocalizedText(
                              context,
                              zh: '客户端',
                              en: 'Client',
                            ): widget.request.clientName,
                            openHandLocalizedText(
                              context,
                              zh: '来源地址',
                              en: 'Peer',
                            ): widget.request.ipAddress,
                            openHandLocalizedText(
                              context,
                              zh: '请求时间',
                              en: 'Requested',
                            ): formatMonthDayHms(
                              widget.request.requestedAt.toLocal(),
                            ),
                            openHandLocalizedText(
                              context,
                              zh: '自动拒绝',
                              en: 'Auto Reject',
                            ): formatMonthDayHms(
                              widget.request.expiresAt.toLocal(),
                            ),
                          },
                        ),
                        const SizedBox(height: 12),
                        _ApprovalPayloadPanel(
                          text: _isExpanded ? _argumentsPreview : _shortPayload,
                        ),
                        if (_isLongPayload)
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextButton.icon(
                              onPressed: () =>
                                  setState(() => _isExpanded = !_isExpanded),
                              icon: Icon(
                                _isExpanded
                                    ? Icons.unfold_less_rounded
                                    : Icons.unfold_more_rounded,
                                size: 18,
                              ),
                              label: Text(
                                _isExpanded
                                    ? openHandLocalizedText(
                                        context,
                                        zh: '收起参数',
                                        en: 'Collapse',
                                      )
                                    : openHandLocalizedText(
                                        context,
                                        zh: '查看完整参数',
                                        en: 'View Full Parameters',
                                      ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                openHandLocalizedText(
                  context,
                  zh: '快捷键：Enter 放行 · Esc 不关闭，请明确选择放行或拒绝',
                  en: 'Shortcuts: Enter approves · Esc is ignored; choose Allow or Reject explicitly',
                ),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OpenHandDialogActionButton.secondary(
                    onPressed: () => _closeWith(false),
                    label: openHandLocalizedText(
                      context,
                      zh: '拒绝调用',
                      en: 'Reject',
                    ),
                  ),
                  const SizedBox(width: 12),
                  OpenHandDialogActionButton.primary(
                    onPressed: () => _closeWith(true),
                    label: openHandLocalizedText(
                      context,
                      zh: '允许执行',
                      en: 'Allow',
                    ),
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

class _ApprovalChip extends StatelessWidget {
  const _ApprovalChip({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = color ?? cs.primary;
    final maxWidth = math.min(420.0, MediaQuery.sizeOf(context).width * 0.58);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: accent),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Text(
              label.trim().isEmpty ? '-' : label.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApprovalInfoPanel extends StatelessWidget {
  const _ApprovalInfoPanel({
    required this.icon,
    required this.title,
    required this.rows,
  });

  final IconData icon;
  final String title;
  final Map<String, String> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.62)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: cs.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final row in rows.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 104,
                    child: Text(
                      row.key,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SelectableText(
                      row.value.trim().isEmpty ? '-' : row.value.trim(),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ApprovalPayloadPanel extends StatelessWidget {
  const _ApprovalPayloadPanel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final payload = text.trim();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: OpenHandStatusColors.warning.withValues(alpha: 0.24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.data_object_rounded,
                color: OpenHandStatusColors.warning,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                openHandLocalizedText(context, zh: '请求参数', en: 'Parameters'),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SelectableText(
            payload.isEmpty ? '-' : payload,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              height: 1.5,
              color: payload.isEmpty ? cs.onSurfaceVariant : null,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatRemaining(BuildContext context, Duration remaining) {
  final seconds = remaining.inSeconds;
  if (seconds <= 0) {
    return openHandLocalizedText(context, zh: '即将超时', en: 'Expiring now');
  }
  if (seconds < 60) {
    return openHandLocalizedText(
      context,
      zh: '${seconds}s 后自动拒绝',
      en: 'Auto-reject in ${seconds}s',
    );
  }
  final minutes = seconds ~/ 60;
  final tail = seconds % 60;
  return openHandLocalizedText(
    context,
    zh: '${minutes}m ${tail}s 后自动拒绝',
    en: 'Auto-reject in ${minutes}m ${tail}s',
  );
}
