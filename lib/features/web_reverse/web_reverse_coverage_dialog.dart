/// 代码覆盖率面板。
///
/// 通过 CDP `Profiler.startPreciseCoverage` + `Profiler.takePreciseCoverage`
/// 拉取页面所有脚本的已执行字节区间，汇总成"URL → 已覆盖 bytes / 总 bytes"
/// 表。停止采集时同步调用 `Profiler.stopPreciseCoverage`。Worker / iframe
/// 暂不聚合（CDP per-target，本面板只看主 frame）。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseCoverageDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _CoverageDialog(controller: controller),
  );
}

class _CoverageDialog extends StatefulWidget {
  const _CoverageDialog({required this.controller});
  final WebReverseSessionController controller;
  @override
  State<_CoverageDialog> createState() => _CoverageDialogState();
}

class _CoverageRow {
  _CoverageRow(this.url);
  final String url;
  int total = 0;
  int covered = 0;
  int functions = 0;
  int coveredFunctions = 0;
  double get ratio => total == 0 ? 0 : covered / total;
}

class _CoverageDialogState extends State<_CoverageDialog> {
  bool _running = false;
  bool _busy = false;
  List<_CoverageRow> _rows = const [];
  DateTime? _lastTakeAt;
  String _filter = '';

  Future<void> _start() async {
    if (_busy || _running) return;
    final loc = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await widget.controller.sendRawCdp(method: 'Profiler.enable');
      final r = await widget.controller.sendRawCdp(
        method: 'Profiler.startPreciseCoverage',
        paramsJson: jsonEncode(<String, Object?>{
          'callCount': true,
          'detailed': true,
          'allowTriggeredUpdates': false,
        }),
      );
      final err = r?['error'];
      if (err != null) {
        _toast(false, '${loc?.webReverseCoverageStartFailed ?? 'start failed'}: $err');
      } else {
        setState(() => _running = true);
        _toast(true, loc?.webReverseCoverageCollecting ?? 'Collecting…');
      }
    } catch (e, st) {
      silentLog('web_reverse_coverage_dialog', 'start', e, st);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _take() async {
    if (_busy || !_running) return;
    final loc = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final r = await widget.controller.sendRawCdp(
        method: 'Profiler.takePreciseCoverage',
      );
      final err = r?['error'];
      if (err != null) {
        _toast(false, '${loc?.webReverseCoverageTakeFailed ?? 'take failed'}: $err');
        return;
      }
      final list = (r?['result'] as List?) ?? const [];
      final rows = <String, _CoverageRow>{};
      for (final raw in list) {
        if (raw is! Map) continue;
        final url = '${raw['url'] ?? ''}';
        if (url.isEmpty) continue;
        final row = rows.putIfAbsent(url, () => _CoverageRow(url));
        final functions = (raw['functions'] as List?) ?? const [];
        for (final fnRaw in functions) {
          if (fnRaw is! Map) continue;
          row.functions += 1;
          final ranges = (fnRaw['ranges'] as List?) ?? const [];
          if (ranges.isEmpty) continue;
          // 第一段 range = 整段函数的 start..end，count>0 → 至少进过一次。
          final first = ranges.first;
          if (first is Map) {
            final start = (first['startOffset'] as num?)?.toInt() ?? 0;
            final end = (first['endOffset'] as num?)?.toInt() ?? 0;
            final span = end - start;
            if (span > 0) row.total += span;
            final cnt = (first['count'] as num?)?.toInt() ?? 0;
            if (cnt > 0) row.coveredFunctions += 1;
          }
          // 后续 ranges 是子区间，count>0 段累加为 covered bytes。
          for (var i = 1; i < ranges.length; i++) {
            final rng = ranges[i];
            if (rng is! Map) continue;
            final s = (rng['startOffset'] as num?)?.toInt() ?? 0;
            final e = (rng['endOffset'] as num?)?.toInt() ?? 0;
            final cnt = (rng['count'] as num?)?.toInt() ?? 0;
            if (cnt > 0 && e > s) row.covered += (e - s);
          }
        }
      }
      final sorted = rows.values.toList()
        ..sort((a, b) => b.total.compareTo(a.total));
      setState(() {
        _rows = sorted;
        _lastTakeAt = DateTime.now();
      });
      _toast(true,
          loc?.webReverseCoverageSampledCount(sorted.length) ??
              'Sampled ${sorted.length} scripts');
    } catch (e, st) {
      silentLog('web_reverse_coverage_dialog', 'take', e, st);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    if (_busy || !_running) return;
    final loc = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await widget.controller.sendRawCdp(method: 'Profiler.stopPreciseCoverage');
      setState(() => _running = false);
      _toast(true, loc?.webReverseCoverageStopped ?? 'Stopped');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyReport() async {
    final loc = AppLocalizations.of(context);
    final filtered = _visibleRows();
    final buf = StringBuffer()
      ..writeln('# JS Coverage Report')
      ..writeln('Total scripts: ${filtered.length}')
      ..writeln();
    for (final row in filtered) {
      final pct = (row.ratio * 100).toStringAsFixed(1);
      buf.writeln('- $pct%  ${row.covered}/${row.total}B  '
          '(${row.coveredFunctions}/${row.functions} fn)  ${row.url}');
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    _toast(true, loc?.webReverseCoverageReportCopied ?? 'Report copied');
  }

  void _toast(bool ok, String msg) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    if (ok) {
      OpenHandSnackBar.showSuccessOn(context, messenger, msg);
    } else {
      OpenHandSnackBar.showErrorOn(context, messenger, msg);
    }
  }

  List<_CoverageRow> _visibleRows() {
    if (_filter.isEmpty) return _rows;
    final lower = _filter.toLowerCase();
    return _rows.where((r) => r.url.toLowerCase().contains(lower)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    final rows = _visibleRows();
    final totalBytes = rows.fold<int>(0, (a, b) => a + b.total);
    final coveredBytes = rows.fold<int>(0, (a, b) => a + b.covered);
    final globalRatio =
        totalBytes == 0 ? 0.0 : (coveredBytes / totalBytes).clamp(0.0, 1.0);
    return Dialog(
      backgroundColor: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 680),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
              child: Row(
                children: [
                  Icon(Icons.bar_chart_rounded, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loc?.webReverseCoverageTitle ?? 'JS Coverage',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          loc?.webReverseCoverageSubtitle ??
                              'Start → exercise the page → take a sample to see which scripts ran',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (_running)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        loc?.webReverseCoverageRecording ?? 'RECORDING',
                        style: TextStyle(
                          color: cs.onPrimaryContainer,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  FilledButton.icon(
                    onPressed: _busy || _running ? null : _start,
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: Text(loc?.webReverseCoverageStart ?? 'Start'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: _busy || !_running ? null : _take,
                    icon: const Icon(Icons.science_rounded, size: 18),
                    label: Text(loc?.webReverseCoverageTake ?? 'Take'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _busy || !_running ? null : _stop,
                    icon: const Icon(Icons.stop_rounded, size: 18),
                    label: Text(loc?.webReverseCoverageStop ?? 'Stop'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _filter = v.trim()),
                      decoration: InputDecoration(
                        hintText: loc?.webReverseCoverageFilterHint ?? 'Filter by URL',
                        prefixIcon: const Icon(Icons.filter_alt_rounded, size: 18),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: loc?.webReverseCoverageCopyReport ?? 'Copy report',
                    onPressed: _rows.isEmpty ? null : _copyReport,
                    icon: const Icon(Icons.copy_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: globalRatio,
                      backgroundColor: cs.surfaceContainerHighest,
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${(globalRatio * 100).toStringAsFixed(1)}%  '
                    '${_humanBytes(coveredBytes)} / ${_humanBytes(totalBytes)}',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(fontFamily: 'monospace'),
                  ),
                  if (_lastTakeAt != null) ...[
                    const SizedBox(width: 10),
                    Text(
                      _stamp(_lastTakeAt!),
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: rows.isEmpty
                  ? Center(
                      child: Text(
                        loc?.webReverseCoverageNoData ?? 'No data. Start → use the page → Take.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 4),
                      itemBuilder: (_, idx) =>
                          _buildRow(theme, cs, rows[idx], loc),
                    ),
            ),
            Divider(height: 1, color: cs.outlineVariant),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OpenHandDialogActionButton.secondary(
                    label: loc?.webReverseCoverageClose ?? 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(
      ThemeData theme, ColorScheme cs, _CoverageRow row, AppLocalizations? loc) {
    final pct = (row.ratio * 100);
    final pctText = '${pct.toStringAsFixed(1)}%';
    Color barColor;
    if (pct >= 70) {
      barColor = Colors.green;
    } else if (pct >= 30) {
      barColor = cs.tertiary;
    } else {
      barColor = cs.error;
    }
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              pctText,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: barColor,
                fontWeight: FontWeight.w800,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: LinearProgressIndicator(
              value: row.ratio,
              backgroundColor: cs.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
              minHeight: 6,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontFamily: 'monospace'),
                ),
                Text(
                  '${_humanBytes(row.covered)} / ${_humanBytes(row.total)}  ·  '
                  '${row.coveredFunctions}/${row.functions} fn',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: loc?.webReverseCoverageCopyUrl ?? 'Copy URL',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: row.url));
              if (!mounted) return;
              _toast(true, loc?.webReverseCoverageCopied ?? 'Copied');
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
          ),
        ],
      ),
    );
  }

  String _humanBytes(int b) {
    if (b < 1024) return '${b}B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)}K';
    return '${(b / 1024 / 1024).toStringAsFixed(2)}M';
  }

  String _stamp(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
}
