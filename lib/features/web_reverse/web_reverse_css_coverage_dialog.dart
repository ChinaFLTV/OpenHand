/// CSS 规则使用率追踪面板。
///
/// CDP `CSS.startRuleUsageTracking` → 一段时间后 `CSS.stopRuleUsageTracking`
/// 返回每条 styleSheetId/range/used 的命中记录；按 styleSheet 聚合用量百分比。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/support/silent_log.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseCssCoverageDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
  required bool isZh,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _CssCovDialog(controller: controller, isZh: isZh),
  );
}

class _CssCovDialog extends StatefulWidget {
  const _CssCovDialog({required this.controller, required this.isZh});
  final WebReverseSessionController controller;
  final bool isZh;
  @override
  State<_CssCovDialog> createState() => _CssCovDialogState();
}

class _SheetUsage {
  _SheetUsage(this.styleSheetId);
  final String styleSheetId;
  int totalRanges = 0;
  int usedRanges = 0;
  int totalBytes = 0;
  int usedBytes = 0;
  String sourceUrl = '';
}

class _CssCovDialogState extends State<_CssCovDialog> {
  bool _busy = false;
  bool _tracking = false;
  String _status = '';
  List<_SheetUsage> _results = [];

  Future<void> _start() async {
    final isZh = widget.isZh;
    setState(() {
      _busy = true;
      _status = isZh ? '启用 CSS 域并启动追踪...' : 'Enabling CSS & starting...';
    });
    try {
      await widget.controller.sendRawCdp(method: 'DOM.enable');
      await widget.controller.sendRawCdp(method: 'CSS.enable');
      final r = await widget.controller
          .sendRawCdp(method: 'CSS.startRuleUsageTracking');
      if (!mounted) return;
      if (r == null || r['error'] != null) {
        setState(() {
          _busy = false;
          _status = isZh
              ? '启动失败: ${r?['error'] ?? 'unknown'}'
              : 'Start failed: ${r?['error'] ?? 'unknown'}';
        });
        return;
      }
      setState(() {
        _busy = false;
        _tracking = true;
        _status = isZh
            ? '正在追踪 — 请在页面上交互（点击、滚动、悬浮等），然后点击「停止并统计」。'
            : 'Tracking — interact with the page, then click "Stop & Tally".';
      });
    } catch (e, s) {
      silentLog('web-reverse', 'css-cov.start', e, s);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Error: $e';
      });
    }
  }

  Future<void> _stop() async {
    final isZh = widget.isZh;
    setState(() {
      _busy = true;
      _status = isZh ? '停止并聚合结果...' : 'Stopping and aggregating...';
    });
    Map<String, Object?>? r;
    try {
      r = await widget.controller
          .sendRawCdp(method: 'CSS.stopRuleUsageTracking');
    } catch (e, s) {
      silentLog('web-reverse', 'css-cov.stop', e, s);
    }
    if (!mounted) return;
    if (r == null || r['error'] != null) {
      setState(() {
        _busy = false;
        _tracking = false;
        _status = isZh
            ? '停止失败: ${r?['error'] ?? 'unknown'}'
            : 'Stop failed: ${r?['error'] ?? 'unknown'}';
      });
      return;
    }
    final usage = r['ruleUsage'];
    final map = <String, _SheetUsage>{};
    if (usage is List) {
      for (final u in usage.whereType<Map>()) {
        final sid = (u['styleSheetId'] ?? '').toString();
        if (sid.isEmpty) continue;
        final start = (u['startOffset'] is num)
            ? (u['startOffset'] as num).toInt()
            : 0;
        final end =
            (u['endOffset'] is num) ? (u['endOffset'] as num).toInt() : 0;
        final used = u['used'] == true;
        final bytes = (end - start).clamp(0, 1 << 30);
        final s = map.putIfAbsent(sid, () => _SheetUsage(sid));
        s.totalRanges += 1;
        s.totalBytes += bytes;
        if (used) {
          s.usedRanges += 1;
          s.usedBytes += bytes;
        }
      }
    }
    // 拉一次 source URL 信息
    for (final sid in map.keys.toList()) {
      try {
        final h = await widget.controller.sendRawCdp(
          method: 'CSS.getStyleSheetText',
          paramsJson: jsonEncode({'styleSheetId': sid}),
        );
        if (h != null && h['error'] == null) {
          // 没有直接 URL 字段；getHeader 通过 CSS.getStyleSheetHeader 不存在，
          // 使用 CSS.styleSheetAdded 事件中的 header.sourceURL 才有；
          // 这里把 styleSheetId 截短作为标签。
        }
      } catch (e, st) {
        silentLog('web-reverse', 'css-cov.sheet-text', e, st);
      }
    }
    final list = map.values.toList()
      ..sort((a, b) => b.totalBytes.compareTo(a.totalBytes));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _tracking = false;
      _results = list;
      _status = isZh
          ? '已统计 ${list.length} 个样式表，共 ${list.fold<int>(0, (s, e) => s + e.totalRanges)} 条规则。'
          : '${list.length} sheets, ${list.fold<int>(0, (s, e) => s + e.totalRanges)} rules total.';
    });
  }

  Future<void> _copyJson() async {
    final json = const JsonEncoder.withIndent('  ').convert(_results
        .map((e) => {
              'styleSheetId': e.styleSheetId,
              'totalRanges': e.totalRanges,
              'usedRanges': e.usedRanges,
              'totalBytes': e.totalBytes,
              'usedBytes': e.usedBytes,
              'usagePct': e.totalBytes == 0
                  ? 0
                  : (e.usedBytes * 100 / e.totalBytes).round(),
            })
        .toList());
    try {
      await Clipboard.setData(ClipboardData(text: json));
    } catch (e, st) {
      silentLog('web-reverse', 'css-cov.copy', e, st);
      return;
    }
    if (!mounted) return;
    final m = ScaffoldMessenger.maybeOf(context);
    if (m != null) {
      OpenHandSnackBar.showSuccessOn(
        context,
        m,
        widget.isZh ? 'JSON 已复制' : 'JSON copied',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isZh = widget.isZh;
    return Dialog(
      backgroundColor: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 720),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
              child: Row(
                children: [
                  Icon(Icons.style_rounded, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isZh ? 'CSS 规则使用率' : 'CSS Rule Coverage',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          isZh
                              ? 'CSS.startRuleUsageTracking · 统计未命中的死代码'
                              : 'CSS.startRuleUsageTracking · find dead rules',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _results.isEmpty ? null : _copyJson,
                    icon: const Icon(Icons.copy_rounded),
                    tooltip: isZh ? '复制 JSON' : 'Copy JSON',
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: _tracking ? Colors.green : cs.outlineVariant,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _tracking
                        ? (isZh ? '追踪中' : 'Tracking')
                        : (isZh ? '空闲' : 'Idle'),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  if (_tracking)
                    FilledButton.icon(
                      onPressed: _busy ? null : _stop,
                      icon: const Icon(Icons.stop_rounded),
                      label: Text(isZh ? '停止并统计' : 'Stop & Tally'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _busy ? null : _start,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(isZh ? '开始追踪' : 'Start Tracking'),
                    ),
                ],
              ),
            ),
            if (_busy) const LinearProgressIndicator(minHeight: 3),
            if (_status.isNotEmpty)
              Container(
                width: double.infinity,
                color: cs.surfaceContainerHigh,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  _status,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: Text(
                        isZh
                            ? '尚无结果。开始追踪后在页面上交互。'
                            : 'No results yet. Start tracking then interact.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      itemCount: _results.length,
                      itemBuilder: (_, i) {
                        final r = _results[i];
                        final pct = r.totalBytes == 0
                            ? 0
                            : (r.usedBytes * 100 / r.totalBytes).round();
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: cs.outlineVariant),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: SelectableText(
                                      r.styleSheetId,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '$pct%',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: pct < 30
                                          ? cs.error
                                          : pct < 70
                                              ? cs.tertiary
                                              : cs.primary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: r.totalBytes == 0
                                      ? 0
                                      : r.usedBytes / r.totalBytes,
                                  minHeight: 6,
                                  backgroundColor: cs.surfaceContainerHighest,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                isZh
                                    ? '${r.usedRanges}/${r.totalRanges} 规则 · ${(r.usedBytes / 1024).toStringAsFixed(1)}/${(r.totalBytes / 1024).toStringAsFixed(1)} KB'
                                    : '${r.usedRanges}/${r.totalRanges} rules · ${(r.usedBytes / 1024).toStringAsFixed(1)}/${(r.totalBytes / 1024).toStringAsFixed(1)} KB',
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: OpenHandDialogActionButton.primary(
                  label: isZh ? '关闭' : 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
