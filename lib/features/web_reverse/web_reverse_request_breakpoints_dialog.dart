/// 报文条件断点管理弹窗。
///
/// 与 Network 面板的"全部拦截"开关不同：这里只关心命中条件的请求，命中
/// 后会在 hits 列表里立刻可见，可选触发 JS 表达式（例如 `debugger` 或
/// 录制调用栈）。前提：用户已经在工具栏打开「请求拦截」总开关，否则
/// Fetch 域没有事件抵达 controller。
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_inline_empty_state.dart';
import '../../shared/ui/openhand_spacing.dart';
import '../../shared/ui/openhand_typography.dart';
import '../../shared/util/date_time_format.dart';
import 'web_reverse_dialog_utils.dart';
import 'web_reverse_session_controller.dart';

const double _kRequestBreakpointsDialogRadius = 20;
const EdgeInsets _kRequestBreakpointsDialogInsetPadding = EdgeInsets.all(24);

Future<void> showWebReverseRequestBreakpointsDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) {
  return webReverseToolDialogs.show<void>(
    context: context,
    builder: (_) => _RequestBreakpointsDialog(controller: controller),
  );
}

class _RequestBreakpointsDialog extends StatefulWidget {
  const _RequestBreakpointsDialog({required this.controller});
  final WebReverseSessionController controller;
  @override
  State<_RequestBreakpointsDialog> createState() =>
      _RequestBreakpointsDialogState();
}

class _RequestBreakpointsDialogState extends State<_RequestBreakpointsDialog> {
  WebReverseRequestBreakpoint? _selected;

  @override
  void initState() {
    super.initState();
    final list = widget.controller.requestBreakpoints;
    if (list.isNotEmpty) _selected = list.first;
  }

  void _add() {
    if (widget.controller.requestBreakpoints.length >=
        WebReverseSessionController.maxRequestBreakpoints) {
      return;
    }
    final id = 'bp_${DateTime.now().microsecondsSinceEpoch}';
    final bp = WebReverseRequestBreakpoint(
      id: id,
      name:
          AppLocalizations.of(context)?.webReverseReqBpNewBreakpoint ??
          'New breakpoint',
      enabled: true,
      methodFilter: '',
      urlContains: '',
      bodyContains: '',
      evalExpression: '',
    );
    final list = [...widget.controller.requestBreakpoints, bp];
    widget.controller.setRequestBreakpoints(list);
    setState(() => _selected = bp);
  }

  void _delete(WebReverseRequestBreakpoint bp) {
    final list = widget.controller.requestBreakpoints
        .where((e) => e.id != bp.id)
        .toList();
    widget.controller.setRequestBreakpoints(list);
    setState(() {
      _selected = list.isEmpty ? null : list.first;
    });
  }

  void _update(WebReverseRequestBreakpoint updated) {
    final list = widget.controller.requestBreakpoints
        .map((e) => e.id == updated.id ? updated : e)
        .toList();
    widget.controller.setRequestBreakpoints(list);
    setState(() => _selected = updated);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => buildOpenHandDialog(
        backgroundColor: cs.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_kRequestBreakpointsDialogRadius),
        ),
        insetPadding: _kRequestBreakpointsDialogInsetPadding,
        maxWidth: kOpenHandDialogWidthPanel,
        maxHeight: kOpenHandDialogHeightTall,
        child: Column(
          children: [
            _buildHeader(theme, cs, loc),
            Divider(height: 1, color: cs.outlineVariant),
            Expanded(
              child: Row(
                children: [
                  SizedBox(width: 340, child: _buildList(theme, cs, loc)),
                  VerticalDivider(width: 1, color: cs.outlineVariant),
                  Expanded(
                    child: _selected == null
                        ? _buildEmpty(theme, cs, loc)
                        : _BreakpointEditor(
                            key: ValueKey(_selected!.id),
                            breakpoint: _selected!,
                            onChange: _update,
                            onDelete: () => _delete(_selected!),
                          ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant),
            _buildHits(theme, cs, loc),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, ColorScheme cs, AppLocalizations? loc) {
    final ctrl = widget.controller;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
      child: Row(
        children: [
          Icon(Icons.notifications_active_rounded, color: cs.primary),
          kOpenHandHGap10,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loc?.webReverseReqBpTitle ?? 'Request Breakpoints',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  loc?.webReverseReqBpSubtitle ??
                      'Match by URL/body substring → log hit + optional JS eval. Toggle "Intercept" first.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (!ctrl.isFetchInterceptEnabled)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: cs.errorContainer,
                borderRadius: kOpenHandBorderRadius6,
              ),
              child: Text(
                loc?.webReverseReqBpInterceptOff ?? 'Intercept OFF',
                style: TextStyle(
                  color: cs.onErrorContainer,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
          IconButton(
            tooltip: loc?.webReverseReqBpAdd ?? 'Add',
            onPressed:
                ctrl.requestBreakpoints.length >=
                    WebReverseSessionController.maxRequestBreakpoints
                ? null
                : _add,
            icon: const Icon(Icons.add_rounded),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildList(ThemeData theme, ColorScheme cs, AppLocalizations? loc) {
    final list = widget.controller.requestBreakpoints;
    if (list.isEmpty) {
      return OpenHandInlineEmptyState(
        icon: Icons.bookmark_add_rounded,
        dense: true,
        message:
            loc?.webReverseReqBpEmptyHint ??
            'Click + to add your first breakpoint',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: list.length,
      separatorBuilder: (_, _) => kOpenHandGap2,
      itemBuilder: (_, idx) {
        final bp = list[idx];
        final active = _selected?.id == bp.id;
        return Material(
          color: active ? cs.primaryContainer : Colors.transparent,
          borderRadius: kOpenHandBorderRadius8,
          child: InkWell(
            borderRadius: kOpenHandBorderRadius8,
            onTap: () => setState(() => _selected = bp),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Switch(
                    value: bp.enabled,
                    onChanged: (v) => _update(bp.copyWith(enabled: v)),
                  ),
                  kOpenHandHGap6,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bp.name.isEmpty
                              ? (loc?.webReverseReqBpUnnamed ?? '(unnamed)')
                              : bp.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          [
                            if (bp.methodFilter.isNotEmpty) bp.methodFilter,
                            if (bp.urlContains.isNotEmpty)
                              'url~${bp.urlContains}',
                            if (bp.bodyContains.isNotEmpty)
                              'body~${bp.bodyContains}',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontFamily: kOpenHandMonospaceFontFamily,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmpty(ThemeData theme, ColorScheme cs, AppLocalizations? loc) {
    return Center(
      child: Text(
        loc?.webReverseReqBpPickHint ?? 'Pick a breakpoint to edit',
        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
    );
  }

  Widget _buildHits(ThemeData theme, ColorScheme cs, AppLocalizations? loc) {
    final hits = widget.controller.requestBreakpointHits;
    return SizedBox(
      height: 180,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
            child: Row(
              children: [
                Icon(Icons.bolt_rounded, size: 16, color: cs.primary),
                kOpenHandHGap6,
                Text(
                  loc?.webReverseReqBpHitsCount(hits.length) ??
                      'Hits (recent ${hits.length})',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                if (hits.isNotEmpty)
                  TextButton.icon(
                    icon: const Icon(Icons.clear_all_rounded, size: 16),
                    label: Text(loc?.webReverseReqBpClear ?? 'Clear'),
                    onPressed: widget.controller.clearRequestBreakpointHits,
                  ),
              ],
            ),
          ),
          Expanded(
            child: hits.isEmpty
                ? OpenHandInlineEmptyState(
                    message: loc?.webReverseReqBpNoHits ?? 'No hits yet',
                    dense: true,
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: hits.length,
                    itemBuilder: (_, idx) {
                      final h = hits[hits.length - 1 - idx];
                      final ts = formatHourMinuteSecond(h.at);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: DefaultTextStyle.merge(
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontFamily: kOpenHandMonospaceFontFamily,
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 60,
                                child: Text(
                                  ts,
                                  style: TextStyle(color: cs.onSurfaceVariant),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.tertiaryContainer,
                                  borderRadius: BorderRadius.circular(
                                    kOpenHandRadius3,
                                  ),
                                ),
                                child: Text(
                                  h.method,
                                  style: TextStyle(
                                    color: cs.onTertiaryContainer,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              kOpenHandHGap6,
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.primaryContainer,
                                  borderRadius: BorderRadius.circular(
                                    kOpenHandRadius3,
                                  ),
                                ),
                                child: Text(
                                  h.breakpointName,
                                  style: TextStyle(
                                    color: cs.onPrimaryContainer,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              kOpenHandHGap8,
                              Expanded(
                                child: Text(
                                  h.url,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _BreakpointEditor extends StatefulWidget {
  const _BreakpointEditor({
    super.key,
    required this.breakpoint,
    required this.onChange,
    required this.onDelete,
  });
  final WebReverseRequestBreakpoint breakpoint;
  final ValueChanged<WebReverseRequestBreakpoint> onChange;
  final VoidCallback onDelete;
  @override
  State<_BreakpointEditor> createState() => _BreakpointEditorState();
}

class _BreakpointEditorState extends State<_BreakpointEditor> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _bodyCtrl;
  late final TextEditingController _evalCtrl;
  String _method = '';

  @override
  void initState() {
    super.initState();
    final b = widget.breakpoint;
    _nameCtrl = TextEditingController(text: b.name);
    _urlCtrl = TextEditingController(text: b.urlContains);
    _bodyCtrl = TextEditingController(text: b.bodyContains);
    _evalCtrl = TextEditingController(text: b.evalExpression);
    _method = b.methodFilter;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _bodyCtrl.dispose();
    _evalCtrl.dispose();
    super.dispose();
  }

  void _commit() {
    widget.onChange(
      widget.breakpoint.copyWith(
        name: _nameCtrl.text,
        urlContains: _urlCtrl.text,
        bodyContains: _bodyCtrl.text,
        evalExpression: _evalCtrl.text,
        methodFilter: _method,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          TextField(
            controller: _nameCtrl,
            maxLength: WebReverseSessionController.maxRuleNameChars,
            decoration: InputDecoration(
              labelText: loc?.webReverseReqBpNameField ?? 'Name',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => _commit(),
          ),
          kOpenHandGap12,
          Wrap(
            spacing: 8,
            children: [
              for (final m in const [
                '',
                'GET',
                'POST',
                'PUT',
                'DELETE',
                'PATCH',
              ])
                ChoiceChip(
                  label: Text(
                    m.isEmpty ? (loc?.webReverseReqBpAnyMethod ?? 'Any') : m,
                  ),
                  selected: _method == m,
                  onSelected: (_) {
                    setState(() => _method = m);
                    _commit();
                  },
                ),
            ],
          ),
          kOpenHandGap12,
          TextField(
            controller: _urlCtrl,
            maxLength: WebReverseSessionController.maxBreakpointTextChars,
            decoration: InputDecoration(
              labelText: loc?.webReverseReqBpUrlContains ?? 'URL contains',
              hintText: '/api/v1/sign',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => _commit(),
          ),
          kOpenHandGap12,
          TextField(
            controller: _bodyCtrl,
            maxLength: WebReverseSessionController.maxDebuggerExpressionChars,
            decoration: InputDecoration(
              labelText: loc?.webReverseReqBpBodyContains ?? 'Body contains',
              hintText: '"action":"login"',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => _commit(),
          ),
          kOpenHandGap16,
          Text(
            loc?.webReverseReqBpEvalOnHit ?? 'Eval on hit (optional)',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          kOpenHandGap6,
          TextField(
            controller: _evalCtrl,
            maxLength: WebReverseSessionController.maxDebuggerExpressionChars,
            minLines: 4,
            maxLines: 10,
            style: const TextStyle(
              fontFamily: kOpenHandMonospaceFontFamily,
              fontSize: 12,
            ),
            decoration: InputDecoration(
              hintText:
                  loc?.webReverseReqBpEvalHint ??
                  'e.g. debugger; or console.trace("hit", new Error().stack)',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => _commit(),
          ),
          kOpenHandGap16,
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OpenHandDialogActionButton.destructive(
                label:
                    loc?.webReverseReqBpDeleteBreakpoint ?? 'Delete breakpoint',
                onPressed: widget.onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
