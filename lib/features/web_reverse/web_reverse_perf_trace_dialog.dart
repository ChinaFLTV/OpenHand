/// Performance Trace 录制面板 — 简洁包装 [WebReverseSessionController.recordTrace]。
///
/// UI：分类多选 + 时长滑块 + 开始按钮 → 等待完成 → 落盘 chrome-trace JSON
/// （chrome://tracing / Perfetto 可加载）。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/support/silent_log.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReversePerfTraceDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
  required bool isZh,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _PerfTraceDialog(controller: controller, isZh: isZh),
  );
}

class _PerfTraceDialog extends StatefulWidget {
  const _PerfTraceDialog({required this.controller, required this.isZh});
  final WebReverseSessionController controller;
  final bool isZh;
  @override
  State<_PerfTraceDialog> createState() => _PerfTraceDialogState();
}

class _PerfTraceDialogState extends State<_PerfTraceDialog> {
  bool _busy = false;
  double _seconds = 5;
  String _status = '';
  String _lastSaved = '';
  int _lastBytes = 0;
  Timer? _ticker;
  int _ticksLeft = 0;
  Completer<void>? _earlyStop;

  static const List<String> _categories = [
    'devtools.timeline',
    'devtools.timeline.async',
    'v8',
    'v8.execute',
    'disabled-by-default-devtools.timeline',
    'disabled-by-default-devtools.timeline.frame',
    'disabled-by-default-devtools.timeline.stack',
    'disabled-by-default-v8.cpu_profiler',
    'blink.user_timing',
    'blink.console',
    'loading',
    'latencyInfo',
    'netlog',
    'gpu',
  ];
  final Set<String> _selected = {
    'devtools.timeline',
    'devtools.timeline.async',
    'v8',
    'v8.execute',
    'disabled-by-default-devtools.timeline',
    'blink.user_timing',
    'loading',
  };

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final isZh = widget.isZh;
    final secs = _seconds.round();
    final earlyStop = Completer<void>();
    setState(() {
      _busy = true;
      _ticksLeft = secs;
      _earlyStop = earlyStop;
      _status = isZh ? '正在录制（剩余 ${secs}s）' : 'Recording (${secs}s left)';
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _ticksLeft = (_ticksLeft - 1).clamp(0, 999);
        _status = isZh
            ? '正在录制（剩余 ${_ticksLeft}s）'
            : 'Recording (${_ticksLeft}s left)';
      });
    });
    String? json;
    try {
      json = await widget.controller.recordTrace(
        duration: Duration(seconds: secs),
        categories: _selected.toList(),
        earlyStop: earlyStop.future,
      );
    } catch (e, s) {
      silentLog('web-reverse', 'perf-trace.record', e, s);
    }
    _ticker?.cancel();
    _ticker = null;
    if (!mounted) return;
    if (json == null || json.isEmpty) {
      setState(() {
        _busy = false;
        _earlyStop = null;
        _status = isZh ? '录制失败或无数据' : 'Trace failed or empty';
      });
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/openhand_trace_$ts.json');
    await file.writeAsString(json);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _earlyStop = null;
      _lastSaved = file.path;
      _lastBytes = json!.length;
      _status = isZh
          ? '已保存：${file.path} (${(_lastBytes / 1024).toStringAsFixed(1)} KB)'
          : 'Saved: ${file.path} (${(_lastBytes / 1024).toStringAsFixed(1)} KB)';
    });
    final m = ScaffoldMessenger.maybeOf(context);
    if (m != null) {
      OpenHandSnackBar.showSuccessOn(
        context,
        m,
        isZh ? 'Trace 已保存' : 'Trace saved',
      );
    }
  }

  void _stop() {
    final c = _earlyStop;
    if (c != null && !c.isCompleted) {
      c.complete();
      setState(() {
        _status = widget.isZh ? '已请求停止，正在收尾…' : 'Stopping, finalizing…';
      });
    }
  }

  Future<void> _copyPath() async {
    try {
      await Clipboard.setData(ClipboardData(text: _lastSaved));
    } catch (e, s) {
      silentLog('web-reverse', 'perf-trace.clipboard', e, s);
      return;
    }
    if (!mounted) return;
    final m = ScaffoldMessenger.maybeOf(context);
    if (m != null) {
      OpenHandSnackBar.showSuccessOn(
        context,
        m,
        widget.isZh ? '路径已复制' : 'Path copied',
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
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 700),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
              child: Row(
                children: [
                  Icon(Icons.timeline_rounded, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isZh ? 'Performance Trace 录制' : 'Performance Trace',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          isZh
                              ? 'Tracing 域 → chrome-trace JSON（Perfetto / chrome://tracing 加载）'
                              : 'Tracing → chrome-trace JSON',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
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
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Row(
                children: [
                  Text(
                    isZh ? '时长' : 'Duration',
                    style: theme.textTheme.labelLarge,
                  ),
                  Expanded(
                    child: Slider(
                      value: _seconds,
                      min: 2,
                      max: 30,
                      divisions: 28,
                      label: '${_seconds.round()}s',
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _seconds = v),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${_seconds.round()}s',
                      textAlign: TextAlign.end,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  isZh ? 'Trace 分类' : 'Trace Categories',
                  style: theme.textTheme.labelLarge,
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _categories.map((c) {
                    final on = _selected.contains(c);
                    return FilterChip(
                      label: Text(c, style: const TextStyle(fontSize: 11.5)),
                      selected: on,
                      onSelected: _busy
                          ? null
                          : (v) {
                              setState(() {
                                if (v) {
                                  _selected.add(c);
                                } else {
                                  _selected.remove(c);
                                }
                              });
                            },
                    );
                  }).toList(),
                ),
              ),
            ),
            if (_status.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                color: cs.surfaceContainerHigh,
                child: Text(
                  _status,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (_lastSaved.isNotEmpty)
                    OpenHandDialogActionButton.secondary(
                      label: isZh ? '复制路径' : 'Copy path',
                      icon: Icons.copy_rounded,
                      onPressed: _copyPath,
                    ),
                  if (_busy)
                    OpenHandDialogActionButton.destructive(
                      label: isZh ? '停止录制' : 'Stop',
                      icon: Icons.stop_circle_rounded,
                      onPressed: _earlyStop == null ? null : _stop,
                    )
                  else
                    OpenHandDialogActionButton.secondary(
                      label: isZh ? '开始录制' : 'Start',
                      icon: Icons.fiber_manual_record_rounded,
                      onPressed: _selected.isEmpty ? null : _start,
                    ),
                  OpenHandDialogActionButton.primary(
                    label: isZh ? '关闭' : 'Close',
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
