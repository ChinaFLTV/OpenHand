import 'dart:async';

import 'package:flutter/material.dart';

import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_approval_chip.dart';
import '../../../shared/ui/openhand_countdown_progress_bar.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_safe_scrollbar.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/duration_bounds.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/localized_text.dart';
import '../../../shared/util/text_clip.dart';
import '../../../shared/util/timer_safety.dart';
import '../model/mcp_server_ops.dart';
import 'mcp_payload_format.dart';

const int _approvalPayloadMaxDepth = 8;
const int _approvalPayloadPreviewItemsPerLevel = 12;
const int _approvalPayloadMaxItemsPerLevel = 80;
const int _approvalPayloadExpandedMaxChars = 12000;

OpenHandDialogSession<bool> showMcpOpsWriteApprovalDialogOnNavigator(
  NavigatorState navigator, {
  required BuildContext context,
  required McpOpsApprovalRequest request,
}) {
  return _showMcpOpsWriteApprovalSession(
    request: request,
    present: (builder) => showTrackedAnimatedDialogOnNavigator<bool>(
      navigator: navigator,
      context: context,
      barrierDismissible: false,
      dismissOnEscape: false,
      builder: builder,
    ),
  );
}

OpenHandDialogSession<bool> _showMcpOpsWriteApprovalSession({
  required McpOpsApprovalRequest request,
  required OpenHandDialogSession<bool> Function(WidgetBuilder builder) present,
}) {
  final sessionHolder = <OpenHandDialogSession<bool>?>[null];
  final session = present(
    (_) => _McpOpsWriteApprovalDialog(
      request: request,
      onDecision: (approved) {
        final activeSession = sessionHolder[0];
        if (activeSession == null) return;
        unawaited(
          activeSession.dismiss(
            result: approved,
            logTag: 'mcp',
            logAction: '处理 MCP 写操作审批弹窗',
          ),
        );
      },
    ),
  );
  sessionHolder[0] = session;
  return session;
}

class _McpOpsWriteApprovalDialog extends StatefulWidget {
  const _McpOpsWriteApprovalDialog({
    required this.request,
    required this.onDecision,
  });

  final McpOpsApprovalRequest request;
  final ValueChanged<bool> onDecision;

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
  bool _decisionRequested = false;
  DateTime _now = DateTime.now().toUtc();

  String get _argumentsPreview => widget.request.argumentsPreview.trim();

  bool get _isLongPayload =>
      _argumentsPreview.length > 220 || _argumentsPreview.contains('\n');

  Duration get _remaining {
    return nonNegativeDuration(widget.request.expiresAt.difference(_now));
  }

  double get _remainingProgress {
    final total = widget.request.expiresAt
        .difference(widget.request.requestedAt)
        .inMilliseconds;
    if (total <= 0) return 0;
    return (_remaining.inMilliseconds / total).clamp(0.0, 1.0);
  }

  void _closeWith(bool approved) {
    if (!mounted || _decisionRequested) return;
    _decisionRequested = true;
    _timer?.cancel();
    widget.onDecision(approved);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _shortcutFocusNode.requestFocus();
    });
    _timer = startSafePeriodicTimer(_tick, (_) {
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
    final accent = cs.primary;
    final dialog = Focus(
      focusNode: _shortcutFocusNode,
      autofocus: true,
      onKeyEvent: (_, event) => handleOpenHandApprovalDialogKey(
        event,
        onConfirm: () => _closeWith(true),
      ),
      child: buildOpenHandResponsiveDialogShell(
        context: context,
        maxWidth: kOpenHandApprovalDialogMaxWidth,
        maxHeightFraction: 0.82,
        safeAreaMinimum: const EdgeInsets.symmetric(
          horizontal: 28,
          vertical: 24,
        ),
        expandToMax: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              buildOpenHandApprovalDialogHeader(
                context,
                icon: Icons.verified_user_rounded,
                accent: accent,
                title: openHandLocalizedText(
                  context,
                  zh: 'MCP写调用确认',
                  en: 'MCP Write Call Confirmation',
                ),
                description: openHandLocalizedText(
                  context,
                  zh: '外部客户端请求执行写类型工具，需要你明确放行后才会运行。',
                  en:
                      'An external client requested a write-capable tool. '
                      'OpenHand will run it only after your approval.',
                ),
              ),
              kOpenHandGap16,
              OpenHandCountdownProgressBar(
                value: _remainingProgress,
                color: accent,
                semanticLabel: openHandLocalizedText(
                  context,
                  zh: '审批剩余时间',
                  en: 'Approval time remaining',
                ),
              ),
              kOpenHandGap12,
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OpenHandApprovalChip(
                    icon: Icons.extension_rounded,
                    label: widget.request.toolName,
                  ),
                  OpenHandApprovalChip(
                    icon: Icons.devices_other_rounded,
                    label: widget.request.clientName,
                  ),
                  OpenHandApprovalChip(
                    icon: Icons.public_rounded,
                    label: widget.request.ipAddress,
                  ),
                  OpenHandApprovalChip(
                    icon: Icons.hourglass_top_rounded,
                    label: formatOpenHandAutoRejectCountdown(
                      context,
                      _remaining,
                    ),
                    color: accent,
                  ),
                ],
              ),
              kOpenHandGap16,
              Expanded(
                child: OpenHandSafeScrollbar(
                  controller: _bodyScrollController,
                  thumbVisibility: false,
                  child: ListView(
                    controller: _bodyScrollController,
                    physics: openHandDialogAwareScrollPhysics(context),
                    padding: EdgeInsets.zero,
                    children: [
                      _ApprovalInfoPanel(
                        icon: Icons.route_rounded,
                        title: openHandLocalizedText(
                          context,
                          zh: '调用环境',
                          en: 'Call Context',
                        ),
                        rows: {
                          openHandToolLabel(context): widget.request.toolName,
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
                      kOpenHandGap12,
                      _ApprovalPayloadPanel(
                        text: _argumentsPreview,
                        expanded: _isExpanded,
                        canToggle: _isLongPayload,
                        onToggle: _isLongPayload
                            ? () => setState(() {
                                _isExpanded = !_isExpanded;
                              })
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
              kOpenHandGap12,
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
              kOpenHandGap16,
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
                  kOpenHandHGap12,
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
    return PopScope<bool>(canPop: false, child: dialog);
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
        borderRadius: BorderRadius.circular(kOpenHandRadius18),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.62)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: cs.primary, size: 20),
              kOpenHandHGap8,
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          kOpenHandGap12,
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
                  kOpenHandHGap12,
                  Expanded(
                    child: SelectableText(
                      nonBlankStringOr(row.value, '-'),
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
  const _ApprovalPayloadPanel({
    required this.text,
    required this.expanded,
    required this.canToggle,
    required this.onToggle,
  });

  final String text;
  final bool expanded;
  final bool canToggle;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final parsed = _parseApprovalPayload(text);
    final accent = cs.primary;
    return AnimatedContainer(
      duration: openHandMotionDuration(context, kOpenHandMotion180,
      ),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            accent.withValues(alpha: 0.08),
            cs.surfaceContainerHighest.withValues(alpha: 0.32),
          ],
        ),
        borderRadius: BorderRadius.circular(kOpenHandRadius18),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.035),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(kOpenHandRadius11),
                  border: Border.all(color: accent.withValues(alpha: 0.22)),
                ),
                child: Icon(Icons.data_object_rounded, color: accent, size: 19),
              ),
              kOpenHandHGap10,
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      openHandLocalizedText(
                        context,
                        zh: '请求参数',
                        en: 'Request Parameters',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    kOpenHandGap7,
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        _ApprovalPayloadPill(
                          icon: Icons.schema_rounded,
                          label: mcpPayloadShapeLabel(
                            context,
                            parsed.value,
                            parsed.structured,
                          ),
                          color: accent,
                        ),
                        _ApprovalPayloadPill(
                          icon: Icons.format_list_bulleted_rounded,
                          label: mcpPayloadCountLabel(context, parsed.value),
                          color: cs.onSurfaceVariant,
                        ),
                        _ApprovalPayloadPill(
                          icon: Icons.notes_rounded,
                          label: mcpPayloadSizeLabel(context, parsed.raw),
                          color: cs.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          kOpenHandGap12,
          AnimatedSize(
            duration: openHandMotionDuration(context, kOpenHandMotion180,
            ),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: openHandMotionDuration(
                context,
                kOpenHandMotion160,
              ),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _ApprovalPayloadNode(
                key: ValueKey<String>(
                  'approval-payload-${expanded ? 'full' : 'preview'}-${parsed.raw.hashCode}',
                ),
                value: parsed.value,
                raw: parsed.raw,
                structured: parsed.structured,
                expanded: expanded,
                accent: accent,
              ),
            ),
          ),
          if (canToggle && onToggle != null) ...[
            kOpenHandGap12,
            _ApprovalPayloadToggle(
              expanded: expanded,
              onPressed: onToggle!,
              color: accent,
            ),
          ],
        ],
      ),
    );
  }
}

class _ApprovalPayloadNode extends StatelessWidget {
  const _ApprovalPayloadNode({
    required this.value,
    required this.raw,
    required this.structured,
    required this.expanded,
    required this.accent,
    this.depth = 0,
    this.semanticKey = '',
    super.key,
  });

  final Object? value;
  final String raw;
  final bool structured;
  final bool expanded;
  final Color accent;
  final int depth;
  final String semanticKey;

  @override
  Widget build(BuildContext context) {
    if (!structured) {
      return _ApprovalPayloadScalar(
        value: raw,
        semanticKey: semanticKey,
        expanded: expanded,
        accent: accent,
      );
    }
    final current = value;
    if (depth >= _approvalPayloadMaxDepth &&
        (current is Map || current is List)) {
      return _ApprovalPayloadScalar(
        value: current,
        semanticKey: semanticKey,
        expanded: expanded,
        accent: accent,
      );
    }
    if (current is Map) {
      final entries = current.entries
          .where((entry) => '${entry.key}'.trim().isNotEmpty)
          .toList(growable: false);
      if (entries.isEmpty) {
        return _ApprovalPayloadScalar(
          value: '{}',
          semanticKey: semanticKey,
          expanded: expanded,
          accent: accent,
        );
      }
      final maxItems = expanded
          ? _approvalPayloadMaxItemsPerLevel
          : _approvalPayloadPreviewItemsPerLevel;
      final visibleEntries = entries.take(maxItems).toList(growable: false);
      return buildMcpPayloadEntryColumn(
        visible: visibleEntries,
        hiddenCount: entries.length - visibleEntries.length,
        fieldBuilder: (_, entry) => _ApprovalPayloadField(
          label: '${entry.key}',
          value: entry.value,
          expanded: expanded,
          accent: accent,
          depth: depth,
        ),
        overflowBuilder: (hidden) =>
            _ApprovalPayloadOverflowNotice(hiddenCount: hidden),
      );
    }
    if (current is List) {
      if (current.isEmpty) {
        return _ApprovalPayloadScalar(
          value: '[]',
          semanticKey: semanticKey,
          expanded: expanded,
          accent: accent,
        );
      }
      final maxItems = expanded
          ? _approvalPayloadMaxItemsPerLevel
          : _approvalPayloadPreviewItemsPerLevel;
      final visibleItems = current.take(maxItems).toList(growable: false);
      return buildMcpPayloadEntryColumn(
        visible: visibleItems,
        hiddenCount: current.length - visibleItems.length,
        fieldBuilder: (index, item) => _ApprovalPayloadField(
          label: '#${index + 1}',
          value: item,
          expanded: expanded,
          accent: accent,
          depth: depth,
        ),
        overflowBuilder: (hidden) =>
            _ApprovalPayloadOverflowNotice(hiddenCount: hidden),
      );
    }
    return _ApprovalPayloadScalar(
      value: current,
      semanticKey: semanticKey,
      expanded: expanded,
      accent: accent,
    );
  }
}

class _ApprovalPayloadField extends StatelessWidget {
  const _ApprovalPayloadField({
    required this.label,
    required this.value,
    required this.expanded,
    required this.accent,
    required this.depth,
  });

  final String label;
  final Object? value;
  final bool expanded;
  final Color accent;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final nested = value is Map || value is List;
    final tone = depth == 0 ? accent : cs.primary.withValues(alpha: 0.78);
    return Container(
      decoration: BoxDecoration(
        color: depth == 0
            ? cs.surface.withValues(alpha: 0.58)
            : cs.surfaceContainerLow.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(kOpenHandRadius15),
        border: Border.all(
          color: (depth == 0 ? accent : cs.outlineVariant).withValues(
            alpha: depth == 0 ? 0.18 : 0.42,
          ),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 0,
            width: 3,
            child: ColoredBox(color: tone.withValues(alpha: 0.78)),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(15, 11, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: tone.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(kOpenHandRadius9),
                        border: Border.all(color: tone.withValues(alpha: 0.20)),
                      ),
                      child: Icon(
                        mcpPayloadValueIcon(value),
                        size: 16,
                        color: tone,
                      ),
                    ),
                    kOpenHandHGap9,
                    Expanded(
                      child: SelectableText(
                        label,
                        maxLines: 2,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          height: 1.12,
                        ),
                      ),
                    ),
                    kOpenHandHGap8,
                    _ApprovalPayloadPill(
                      icon: Icons.category_rounded,
                      label: mcpPayloadTypeLabel(context, value),
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
                kOpenHandGap10,
                _ApprovalPayloadNode(
                  value: value,
                  raw: mcpPayloadScalarText(value),
                  structured: nested,
                  expanded: expanded,
                  accent: accent,
                  depth: depth + 1,
                  semanticKey: label,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ApprovalPayloadOverflowNotice extends StatelessWidget {
  const _ApprovalPayloadOverflowNotice({required this.hiddenCount});

  final int hiddenCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = cs.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(kOpenHandRadius12),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(Icons.unfold_more_rounded, size: 16, color: accent),
          kOpenHandHGap8,
          Expanded(
            child: Text(
              openHandLocalizedText(
                context,
                zh: '仍有 $hiddenCount 项未展开，审批记录中会保留原始参数摘要',
                en: '$hiddenCount more entries are hidden; the approval record keeps the raw parameter summary',
              ),
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApprovalPayloadScalar extends StatelessWidget {
  const _ApprovalPayloadScalar({
    required this.value,
    required this.semanticKey,
    required this.expanded,
    required this.accent,
  });

  final Object? value;
  final String semanticKey;
  final bool expanded;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final rawText = mcpPayloadScalarText(value);
    final text = _clipApprovalPayloadText(
      rawText,
      maxChars: expanded ? _approvalPayloadExpandedMaxChars : 260,
    );
    final muted = text.trim().isEmpty;
    final mono = mcpPayloadPrefersMonospace(semanticKey, rawText);
    final block = mono || rawText.length > 96 || rawText.contains('\n');
    if (!block) {
      return SelectableText(
        muted ? '-' : text,
        style: theme.textTheme.bodyMedium?.copyWith(
          height: 1.36,
          color: muted ? cs.onSurfaceVariant : null,
          fontWeight: muted ? FontWeight.w700 : FontWeight.w600,
        ),
      );
    }
    return buildMcpPayloadTextCard(
      context,
      semanticKey: semanticKey,
      text: text,
      rawText: rawText,
      accent: accent,
      mono: mono,
      muted: muted,
    );
  }
}

class _ApprovalPayloadPill extends StatelessWidget {
  const _ApprovalPayloadPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: kOpenHandPillBorderRadius,
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color.withValues(alpha: 0.9)),
          kOpenHandHGap5,
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _ApprovalPayloadToggle extends StatelessWidget {
  const _ApprovalPayloadToggle({
    required this.expanded,
    required this.onPressed,
    required this.color,
  });

  final bool expanded;
  final VoidCallback onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final label = expanded
        ? openHandLocalizedText(context, zh: '收起参数', en: 'Collapse Parameters')
        : openHandLocalizedText(context, zh: '展开完整参数', en: 'Expand Parameters');
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Material(
        color: Colors.transparent,
        borderRadius: kOpenHandPillBorderRadius,
        child: InkWell(
          onTap: onPressed,
          borderRadius: kOpenHandPillBorderRadius,
          hoverColor: color.withValues(alpha: 0.08),
          splashColor: color.withValues(alpha: 0.10),
          highlightColor: color.withValues(alpha: 0.06),
          child: AnimatedContainer(
            duration: openHandMotionDuration(
              context,
              kOpenHandMotion160,
            ),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: kOpenHandPillBorderRadius,
              border: Border.all(color: color.withValues(alpha: 0.22)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: openHandMotionDuration(
                    context,
                    kOpenHandMotion160,
                  ),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: color,
                  ),
                ),
                kOpenHandHGap6,
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w900,
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

class _ApprovalParsedPayload {
  const _ApprovalParsedPayload({
    required this.value,
    required this.raw,
    required this.structured,
  });

  final Object? value;
  final String raw;
  final bool structured;
}

_ApprovalParsedPayload _parseApprovalPayload(String text) {
  final raw = text.trim();
  if (raw.isEmpty) {
    return const _ApprovalParsedPayload(
      value: null,
      raw: '',
      structured: false,
    );
  }
  final decoded = tryDecodeJson(raw);
  if (decoded is Map || decoded is List) {
    return _ApprovalParsedPayload(value: decoded, raw: raw, structured: true);
  }
  final looseMap = parseMcpLoosePayloadMap(raw);
  if (looseMap != null && looseMap.isNotEmpty) {
    return _ApprovalParsedPayload(value: looseMap, raw: raw, structured: true);
  }
  return _ApprovalParsedPayload(value: raw, raw: raw, structured: false);
}

String _clipApprovalPayloadText(String text, {required int maxChars}) {
  final trimmed = text.trim();
  return clipTextByCodeUnits(trimmed, maxChars);
}
