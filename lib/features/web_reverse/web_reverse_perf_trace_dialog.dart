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
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import '../../shared/util/timer_safety.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReversePerfTraceDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _PerfTraceDialog(controller: controller),
  );
}

class _PerfTraceDialog extends StatefulWidget {
  const _PerfTraceDialog({required this.controller});
  final WebReverseSessionController controller;
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
    if (_busy) return;
    final loc = AppLocalizations.of(context);
    final secs = _seconds.round().clamp(2, 30).toInt();
    final earlyStop = Completer<void>();
    setState(() {
      _busy = true;
      _ticksLeft = secs;
      _earlyStop = earlyStop;
      _status =
          loc?.webReversePerfRecording(secs) ?? 'Recording (${secs}s left)';
    });
    _ticker?.cancel();
    _ticker = startSafePeriodicTimer(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _ticksLeft = (_ticksLeft - 1).clamp(0, 999);
        _status =
            loc?.webReversePerfRecording(_ticksLeft) ??
            'Recording (${_ticksLeft}s left)';
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
        _status = loc?.webReversePerfTraceFailed ?? 'Trace failed or empty';
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
      final kb = (_lastBytes / 1024).toStringAsFixed(1);
      _status =
          loc?.webReversePerfSaved(file.path, kb) ??
          'Saved: ${file.path} ($kb KB)';
    });
    final m = ScaffoldMessenger.maybeOf(context);
    if (m != null) {
      OpenHandSnackBar.showSuccessOn(
        context,
        m,
        loc?.webReversePerfTraceSaved ?? 'Trace saved',
      );
    }
  }

  void _stop() {
    final c = _earlyStop;
    if (c != null && !c.isCompleted) {
      c.complete();
      setState(() {
        _status =
            AppLocalizations.of(context)?.webReversePerfStopping ??
            'Stopping, finalizing…';
      });
    }
  }

  Future<void> _copyPath() async {
    final loc = AppLocalizations.of(context);
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
        loc?.webReversePerfPathCopied ?? 'Path copied',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
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
                          loc?.webReversePerfTitle ?? 'Performance Trace',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          loc?.webReversePerfSubtitle ??
                              'Tracing → chrome-trace JSON',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
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
                    loc?.webReversePerfDuration ?? 'Duration',
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
                  loc?.webReversePerfCategories ?? 'Trace Categories',
                  style: theme.textTheme.labelLarge,
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
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
            if (_busy) const LinearProgressIndicator(minHeight: 3),
            if (_status.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                color: cs.surfaceContainerHigh,
                child: Text(
                  _status,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            buildOpenHandDialogActionsBar(
              actions: [
                if (_lastSaved.isNotEmpty)
                  OpenHandDialogActionButton.secondary(
                    label: loc?.webReversePerfCopyPath ?? 'Copy path',
                    icon: Icons.copy_rounded,
                    onPressed: _copyPath,
                  ),
                if (_busy)
                  OpenHandDialogActionButton.destructive(
                    label: loc?.webReversePerfStop ?? 'Stop',
                    icon: Icons.stop_circle_rounded,
                    onPressed: _earlyStop == null ? null : _stop,
                  )
                else
                  OpenHandDialogActionButton.secondary(
                    label: loc?.webReversePerfStart ?? 'Start',
                    icon: Icons.fiber_manual_record_rounded,
                    onPressed: _selected.isEmpty ? null : _start,
                  ),
                OpenHandDialogActionButton.primary(
                  label: loc?.webReversePerfClose ?? 'Close',
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
