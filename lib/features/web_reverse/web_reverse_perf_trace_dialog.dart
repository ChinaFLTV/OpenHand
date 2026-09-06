/// Performance Trace 录制面板 — 简洁包装 [WebReverseSessionController.recordTrace]。
///
/// UI：分类多选 + 时长滑块 + 开始按钮 → 等待完成 → 落盘 chrome-trace JSON
/// （chrome://tracing / Perfetto 可加载）。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/db/atomic_file_operations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_busy_indicators.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import '../../shared/util/byte_size_format.dart';
import '../../shared/util/timer_safety.dart';
import 'web_reverse_clipboard.dart';
import 'web_reverse_dialog_utils.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReversePerfTraceDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) {
  return webReverseToolDialogs.show<void>(
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
  static const Duration _fileMetadataTimeout = Duration(seconds: 2);

  bool _busy = false;
  double _seconds = 5;
  String _status = '';
  String _lastSaved = '';
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
    final earlyStop = _earlyStop;
    if (earlyStop != null && !earlyStop.isCompleted) {
      earlyStop.complete();
    }
    _earlyStop = null;
    _ticker?.cancel();
    super.dispose();
  }

  void _finishWithFailure(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _earlyStop = null;
      _status = message;
    });
    showOpenHandErrorSnack(context, message);
  }

  Future<void> _start() async {
    if (_busy) return;
    final loc = AppLocalizations.of(context);
    final secs = _seconds.round().clamp(2, 30);
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
      silentLog('web_reverse_perf_trace_dialog', '录制性能轨迹', e, s);
    }
    _ticker?.cancel();
    _ticker = null;
    if (!mounted) return;
    if (json == null || json.isEmpty) {
      _finishWithFailure(
        loc?.webReversePerfTraceFailed ?? 'Trace failed or empty',
      );
      return;
    }
    late final File file;
    late final int savedBytes;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      file = File('${dir.path}/openhand_trace_$ts.json');
      await writeFileAtomically(file, json);
      savedBytes = await file.length().timeout(_fileMetadataTimeout);
    } catch (e, s) {
      silentLog('web_reverse_perf_trace_dialog', '保存性能轨迹', e, s);
      if (!mounted) return;
      _finishWithFailure(
        loc?.webReversePerfTraceFailed ?? 'Trace failed or empty',
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _earlyStop = null;
      _lastSaved = file.path;
      final kb = (savedBytes / kBytesPerKiB).toStringAsFixed(1);
      _status =
          loc?.webReversePerfSaved(file.path, kb) ??
          'Saved: ${file.path} ($kb KB)';
    });
    showOpenHandSuccessSnack(
      context,
      loc?.webReversePerfTraceSaved ?? 'Trace saved',
    );
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
    await copyWebReverseTextToClipboard(
      context: context,
      text: _lastSaved,
      successBase: loc?.webReversePerfPathCopied ?? 'Path copied',
      logTag: 'web_reverse_perf_trace_dialog',
      logAction: '复制性能轨迹',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    final dialog = buildOpenHandToolDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthStandard,
      maxHeight: kOpenHandDialogHeightTall,
      child: Column(
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.timeline_rounded,
            title: loc?.webReversePerfTitle ?? 'Performance Trace',
            subtitle:
                loc?.webReversePerfSubtitle ?? 'Tracing → chrome-trace JSON',
            closeEnabled: !_busy,
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
          OpenHandBusyProgressBar(busy: _busy),
          buildWebReverseStatusBar(context, status: _status),
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
    );
    return PopScope(canPop: !_busy, child: dialog);
  }
}
