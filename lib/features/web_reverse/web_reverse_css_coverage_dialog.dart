/// CSS 规则使用率追踪面板。
///
/// CDP `CSS.startRuleUsageTracking` → 一段时间后 `CSS.stopRuleUsageTracking`
/// 返回每条 styleSheetId/range/used 的命中记录；按 styleSheet 聚合用量百分比。
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import 'web_reverse_clipboard.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseCssCoverageDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _CssCovDialog(controller: controller),
  );
}

class _CssCovDialog extends StatefulWidget {
  const _CssCovDialog({required this.controller});
  final WebReverseSessionController controller;
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
    final loc = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _status = loc?.webReverseCssCovStarting ?? 'Enabling CSS & starting...';
    });
    try {
      await widget.controller.sendRawCdp(method: 'DOM.enable');
      await widget.controller.sendRawCdp(method: 'CSS.enable');
      final r = await widget.controller.sendRawCdp(
        method: 'CSS.startRuleUsageTracking',
      );
      if (!mounted) return;
      if (r == null || r['error'] != null) {
        final err = (r?['error'] ?? 'unknown').toString();
        setState(() {
          _busy = false;
          _status =
              loc?.webReverseCssCovStartFailed(err) ?? 'Start failed: $err';
        });
        return;
      }
      setState(() {
        _busy = false;
        _tracking = true;
        _status =
            loc?.webReverseCssCovTrackingActive ??
            'Tracking — interact with the page, then click "Stop & Tally".';
      });
    } catch (e, s) {
      silentLog('web_reverse_css_coverage_dialog', 'css-cov.start', e, s);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Error: $e';
      });
    }
  }

  Future<void> _stop() async {
    final loc = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _status = loc?.webReverseCssCovStopping ?? 'Stopping and aggregating...';
    });
    Map<String, Object?>? r;
    try {
      r = await widget.controller.sendRawCdp(
        method: 'CSS.stopRuleUsageTracking',
      );
    } catch (e, s) {
      silentLog('web_reverse_css_coverage_dialog', 'css-cov.stop', e, s);
    }
    if (!mounted) return;
    if (r == null || r['error'] != null) {
      final err = (r?['error'] ?? 'unknown').toString();
      setState(() {
        _busy = false;
        _tracking = false;
        _status = loc?.webReverseCssCovStopFailed(err) ?? 'Stop failed: $err';
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
        final end = (u['endOffset'] is num)
            ? (u['endOffset'] as num).toInt()
            : 0;
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
        silentLog(
          'web_reverse_css_coverage_dialog',
          'css-cov.sheet-text',
          e,
          st,
        );
      }
    }
    final list = map.values.toList()
      ..sort((a, b) => b.totalBytes.compareTo(a.totalBytes));
    if (!mounted) return;
    final totalRules = list.fold<int>(0, (s, e) => s + e.totalRanges);
    setState(() {
      _busy = false;
      _tracking = false;
      _results = list;
      _status =
          loc?.webReverseCssCovResultsTallied(list.length, totalRules) ??
          '${list.length} sheets, $totalRules rules total.';
    });
  }

  Future<void> _copyJson() async {
    final json = const JsonEncoder.withIndent('  ').convert(
      _results
          .map(
            (e) => {
              'styleSheetId': e.styleSheetId,
              'totalRanges': e.totalRanges,
              'usedRanges': e.usedRanges,
              'totalBytes': e.totalBytes,
              'usedBytes': e.usedBytes,
              'usagePct': e.totalBytes == 0
                  ? 0
                  : (e.usedBytes * 100 / e.totalBytes).round(),
            },
          )
          .toList(),
    );
    final loc = AppLocalizations.of(context);
    final m = ScaffoldMessenger.maybeOf(context);
    try {
      final copied = await setWebReverseClipboardText(json);
      if (!mounted || m == null) return;
      OpenHandSnackBar.showSuccessOn(
        context,
        m,
        webReverseClipboardSnackMessage(
          isZh: loc?.localeName.startsWith('zh') ?? false,
          base: loc?.webReverseCssCovJsonCopied ?? 'JSON copied',
          result: copied,
        ),
      );
    } catch (e, st) {
      silentLog('web_reverse_css_coverage_dialog', 'css-cov.copy', e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: 820,
      child: Column(
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.style_rounded,
            title: loc?.webReverseCssCovTitle ?? 'CSS Rule Coverage',
            subtitle:
                loc?.webReverseCssCovSubtitle ??
                'CSS.startRuleUsageTracking · find dead rules',
            actions: [
              IconButton(
                onPressed: _results.isEmpty ? null : _copyJson,
                icon: const Icon(Icons.copy_rounded),
                tooltip: loc?.webReverseCssCovCopyJson ?? 'Copy JSON',
              ),
            ],
          ),
          Divider(height: 1, color: cs.outlineVariant),
          _buildTrackingBar(theme, cs, loc),
          if (_busy) const LinearProgressIndicator(minHeight: 3),
          if (_status.isNotEmpty)
            Container(
              width: double.infinity,
              color: cs.surfaceContainerHigh,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                _status,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Text(
                      loc?.webReverseCssCovEmpty ??
                          'No results yet. Start tracking then interact.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
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
                              loc?.webReverseCssCovRuleStats(
                                    r.usedRanges,
                                    r.totalRanges,
                                    (r.usedBytes / 1024).toStringAsFixed(1),
                                    (r.totalBytes / 1024).toStringAsFixed(1),
                                  ) ??
                                  '${r.usedRanges}/${r.totalRanges} rules · ${(r.usedBytes / 1024).toStringAsFixed(1)}/${(r.totalBytes / 1024).toStringAsFixed(1)} KB',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          buildOpenHandDialogFooter(
            primaryLabel: loc?.webReverseCssCovClose ?? 'Close',
            onPrimaryPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackingBar(
    ThemeData theme,
    ColorScheme cs,
    AppLocalizations? loc,
  ) {
    final stateLabel = _tracking
        ? (loc?.webReverseCssCovTracking ?? 'Tracking')
        : (loc?.webReverseCssCovIdle ?? 'Idle');
    final state = Row(
      mainAxisSize: MainAxisSize.min,
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
          stateLabel,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
    final button = _tracking
        ? FilledButton.icon(
            onPressed: _busy ? null : _stop,
            icon: const Icon(Icons.stop_rounded),
            label: Text(loc?.webReverseCssCovStopAndTally ?? 'Stop & Tally'),
          )
        : FilledButton.icon(
            onPressed: _busy ? null : _start,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(loc?.webReverseCssCovStartTracking ?? 'Start Tracking'),
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth.isFinite && constraints.maxWidth < 480;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                state,
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerRight, child: button),
              ],
            );
          }
          return Row(children: [state, const Spacer(), button]);
        },
      ),
    );
  }
}
