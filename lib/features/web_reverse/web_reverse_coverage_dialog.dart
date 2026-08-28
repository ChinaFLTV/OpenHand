/// 代码覆盖率面板。
///
/// 通过 CDP `Profiler.startPreciseCoverage` + `Profiler.takePreciseCoverage`
/// 拉取页面所有脚本的已执行字节区间，汇总成"URL → 已覆盖 bytes / 总 bytes"
/// 表。停止采集时同步调用 `Profiler.stopPreciseCoverage`。Worker / iframe
/// 暂不聚合（CDP per-target，本面板只看主 frame）。
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_inline_empty_state.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import '../../shared/ui/openhand_spacing.dart';
import '../../shared/ui/openhand_typography.dart';
import '../../shared/util/byte_size_format.dart';
import '../../shared/util/date_time_format.dart';
import '../../shared/util/input_value_parsing.dart';
import 'web_reverse_clipboard.dart';
import 'web_reverse_dialog_utils.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseCoverageDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) {
  return webReverseToolDialogs.show<void>(
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
        _toast(
          false,
          '${loc?.webReverseCoverageStartFailed ?? 'start failed'}: $err',
        );
      } else {
        setState(() => _running = true);
        _toast(true, loc?.webReverseCoverageCollecting ?? 'Collecting…');
      }
    } catch (e, st) {
      silentLog('web_reverse_coverage_dialog', '启动覆盖率采集', e, st);
      if (mounted) {
        _toast(
          false,
          '${loc?.webReverseCoverageStartFailed ?? 'start failed'}: $e',
        );
      }
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
        _toast(
          false,
          '${loc?.webReverseCoverageTakeFailed ?? 'take failed'}: $err',
        );
        return;
      }
      final rows = <String, _CoverageRow>{};
      for (final raw in stringKeyedMapListFromValue(r?['result'])) {
        final url = '${raw['url'] ?? ''}';
        if (url.isEmpty) continue;
        final row = rows.putIfAbsent(url, () => _CoverageRow(url));
        final functions = stringKeyedMapListFromValue(raw['functions']);
        for (final fnRaw in functions) {
          row.functions += 1;
          final ranges = stringKeyedMapListFromValue(fnRaw['ranges']);
          if (ranges.isEmpty) continue;
          // 第一段 range = 整段函数的 start..end，count>0 → 至少进过一次。
          final first = ranges.first;
          final start = nonNegativeIntFromValue(
            first['startOffset'],
            fallback: 0,
          );
          final end = nonNegativeIntFromValue(first['endOffset'], fallback: 0);
          final span = end - start;
          if (span > 0) row.total += span;
          final cnt = nonNegativeIntFromValue(first['count'], fallback: 0);
          if (cnt > 0) row.coveredFunctions += 1;
          // 后续 ranges 是子区间，count>0 段累加为 covered bytes。
          for (var i = 1; i < ranges.length; i++) {
            final rng = ranges[i];
            final s = nonNegativeIntFromValue(rng['startOffset'], fallback: 0);
            final e = nonNegativeIntFromValue(rng['endOffset'], fallback: 0);
            final cnt = nonNegativeIntFromValue(rng['count'], fallback: 0);
            if (cnt > 0 && e > s) row.covered += e - s;
          }
        }
      }
      final sorted = rows.values.toList()
        ..sort((a, b) => b.total.compareTo(a.total));
      setState(() {
        _rows = sorted;
        _lastTakeAt = DateTime.now();
      });
      _toast(
        true,
        loc?.webReverseCoverageSampledCount(sorted.length) ??
            'Sampled ${sorted.length} scripts',
      );
    } catch (e, st) {
      silentLog('web_reverse_coverage_dialog', '获取覆盖率数据', e, st);
      if (mounted) {
        _toast(
          false,
          '${loc?.webReverseCoverageTakeFailed ?? 'take failed'}: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    if (_busy || !_running) return;
    final loc = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await widget.controller.sendRawCdp(
        method: 'Profiler.stopPreciseCoverage',
      );
      setState(() => _running = false);
      _toast(true, loc?.webReverseCoverageStopped ?? 'Stopped');
    } catch (e, st) {
      silentLog('web_reverse_coverage_dialog', '停止覆盖率采集', e, st);
      if (mounted) {
        _toast(false, '${loc?.tlCallFailed ?? 'Failed'}: $e');
      }
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
      buf.writeln(
        '- $pct%  ${row.covered}/${row.total}B  '
        '(${row.coveredFunctions}/${row.functions} fn)  ${row.url}',
      );
    }
    await copyWebReverseTextToClipboard(
      context: context,
      text: buf.toString(),
      successBase: loc?.webReverseCoverageReportCopied ?? 'Report copied',
      logTag: 'web_reverse_coverage_dialog',
      logAction: '复制覆盖率报告',
    );
  }

  void _toast(bool ok, String msg) {
    if (ok) {
      showOpenHandSuccessSnack(context, msg);
    } else {
      showOpenHandErrorSnack(context, msg);
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
    final globalRatio = unitRatio(coveredBytes, totalBytes);
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthExtraWide,
      maxHeight: kOpenHandDialogHeightStandard,
      insetPadding: const EdgeInsets.all(24),
      child: Column(
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.bar_chart_rounded,
            title: loc?.webReverseCoverageTitle ?? 'JS Coverage',
            subtitle:
                loc?.webReverseCoverageSubtitle ??
                'Start → exercise the page → take a sample to see which scripts ran',
            actions: [
              if (_running)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: kOpenHandBorderRadius6,
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
            ],
          ),
          Divider(height: 1, color: cs.outlineVariant),
          _buildToolbar(loc),
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
                kOpenHandHGap10,
                Text(
                  '${(globalRatio * 100).toStringAsFixed(1)}%  '
                  '${formatByteSize(coveredBytes)} / ${formatByteSize(totalBytes)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontFamily: kOpenHandMonospaceFontFamily,
                  ),
                ),
                if (_lastTakeAt != null) ...[
                  kOpenHandHGap10,
                  Text(
                    formatHourMinuteSecond(_lastTakeAt!),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          kOpenHandGap8,
          Expanded(
            child: rows.isEmpty
                ? OpenHandInlineEmptyState(
                    message:
                        loc?.webReverseCoverageNoData ??
                        'No data. Start → use the page → Take.',
                    dense: true,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => kOpenHandGap4,
                    itemBuilder: (_, idx) =>
                        _buildRow(theme, cs, rows[idx], loc),
                  ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          buildOpenHandDialogFooter(
            primaryLabel: loc?.webReverseCoverageClose ?? 'Close',
            onPrimaryPressed: () => Navigator.of(context).pop(),
            padding: const EdgeInsets.all(12),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(AppLocalizations? loc) {
    Widget filterField() {
      return TextField(
        onChanged: (v) => setState(() => _filter = v.trim()),
        decoration: InputDecoration(
          hintText: loc?.webReverseCoverageFilterHint ?? 'Filter by URL',
          prefixIcon: const Icon(Icons.filter_alt_rounded, size: 18),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      );
    }

    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: _busy || _running ? null : _start,
          icon: const Icon(Icons.play_arrow_rounded, size: 18),
          label: Text(loc?.webReverseCoverageStart ?? 'Start'),
        ),
        FilledButton.tonalIcon(
          onPressed: _busy || !_running ? null : _take,
          icon: const Icon(Icons.science_rounded, size: 18),
          label: Text(loc?.webReverseCoverageTake ?? 'Take'),
        ),
        OutlinedButton.icon(
          onPressed: _busy || !_running ? null : _stop,
          icon: const Icon(Icons.stop_rounded, size: 18),
          label: Text(loc?.webReverseCoverageStop ?? 'Stop'),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth.isFinite && constraints.maxWidth < 760;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                actions,
                kOpenHandGap8,
                Row(
                  children: [
                    Expanded(child: filterField()),
                    kOpenHandHGap8,
                    IconButton(
                      tooltip:
                          loc?.webReverseCoverageCopyReport ?? 'Copy report',
                      onPressed: _rows.isEmpty ? null : _copyReport,
                      icon: const Icon(Icons.copy_rounded),
                    ),
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              actions,
              kOpenHandHGap12,
              Expanded(child: filterField()),
              kOpenHandHGap8,
              IconButton(
                tooltip: loc?.webReverseCoverageCopyReport ?? 'Copy report',
                onPressed: _rows.isEmpty ? null : _copyReport,
                icon: const Icon(Icons.copy_rounded),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRow(
    ThemeData theme,
    ColorScheme cs,
    _CoverageRow row,
    AppLocalizations? loc,
  ) {
    final pct = row.ratio * 100;
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
      decoration: webReverseSurfaceCardDecoration(cs, radius: 8),
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
                fontFamily: kOpenHandMonospaceFontFamily,
              ),
            ),
          ),
          kOpenHandHGap8,
          SizedBox(
            width: 120,
            child: LinearProgressIndicator(
              value: row.ratio,
              backgroundColor: cs.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
              minHeight: 6,
            ),
          ),
          kOpenHandHGap12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: kOpenHandMonospaceFontFamily,
                  ),
                ),
                Text(
                  '${formatByteSize(row.covered)} / ${formatByteSize(row.total)}  ·  '
                  '${row.coveredFunctions}/${row.functions} fn',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: loc?.webReverseCoverageCopyUrl ?? 'Copy URL',
            onPressed: () async {
              await copyWebReverseTextToClipboard(
                context: context,
                text: row.url,
                successBase: loc?.webReverseCoverageCopied ?? 'Copied',
                logTag: 'web_reverse_coverage_dialog',
                logAction: '复制资源链接',
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
          ),
        ],
      ),
    );
  }
}
