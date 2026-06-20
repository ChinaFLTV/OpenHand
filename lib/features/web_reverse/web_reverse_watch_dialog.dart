/// 变量监视器（Watch Expressions）。
///
/// 用户配置一组 JS 表达式（如 `localStorage.getItem('uid')`、`document.title`、
/// `Object.keys(window).length`）；面板定时（默认 1.5s）通过 CDP `Runtime.evaluate`
/// 在页面主帧上下文求值，记录每次结果 + 时间戳，最多 50 条历史。
///
/// 表达式列表保存在内存（重连/刷新后保留，由 controller 持有），可一键
/// 导出 JSON 到剪贴板。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import '../../shared/util/date_time_format.dart';
import '../../shared/util/timer_safety.dart';
import 'web_reverse_clipboard.dart';
import 'web_reverse_session_controller.dart';

const int _kWatchMaxExpressions = 32;
const int _kWatchMaxNameChars = 80;
const int _kWatchMaxExpressionChars = 16 * 1024;
const int _kWatchMaxResultChars = 800;
const int _kWatchMaxSamples = 50;

Future<void> showWebReverseWatchDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _WatchDialog(controller: controller),
  );
}

/// 单条表达式 + 其最近样本队列。完全本地状态（dialog 关闭即销毁）。
class _WatchExpr {
  _WatchExpr({required this.id, required this.name, required this.code});
  final String id;
  String name;
  String code;
  final List<_WatchSample> samples = <_WatchSample>[];
  bool error = false;
  String last = '';
}

class _WatchSample {
  const _WatchSample({
    required this.at,
    required this.value,
    required this.isError,
  });
  final DateTime at;
  final String value;
  final bool isError;
}

class _WatchDialog extends StatefulWidget {
  const _WatchDialog({required this.controller});
  final WebReverseSessionController controller;
  @override
  State<_WatchDialog> createState() => _WatchDialogState();
}

class _WatchDialogState extends State<_WatchDialog> {
  final List<_WatchExpr> _exprs = <_WatchExpr>[];
  int _selected = -1;
  Timer? _timer;
  Duration _interval = const Duration(milliseconds: 1500);
  bool _running = false;

  final TextEditingController _newCode = TextEditingController();
  final TextEditingController _newName = TextEditingController();

  @override
  void initState() {
    super.initState();
    _exprs.addAll([
      _WatchExpr(
        id: 'w_${DateTime.now().microsecondsSinceEpoch}',
        name: 'document.title',
        code: 'document.title',
      ),
      _WatchExpr(
        id: 'w_${DateTime.now().microsecondsSinceEpoch + 1}',
        name: 'localStorage 项数',
        code: 'localStorage.length',
      ),
    ]);
    _selected = 0;
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _newCode.dispose();
    _newName.dispose();
    super.dispose();
  }

  void _start() {
    _timer?.cancel();
    _timer = startNonOverlappingPeriodicTimer(_interval, (_) => _tick());
    setState(() => _running = true);
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    setState(() => _running = false);
  }

  Future<void> _tick() async {
    if (!mounted || _exprs.isEmpty) return;
    for (final e in _exprs) {
      await _evalOne(e);
      if (!mounted) return;
    }
    if (mounted) setState(() {});
  }

  Future<void> _evalOne(_WatchExpr e) async {
    try {
      final r = await widget.controller.sendRawCdp(
        method: 'Runtime.evaluate',
        paramsJson: jsonEncode(<String, Object?>{
          'expression': e.code,
          'returnByValue': true,
          'allowUnsafeEvalBlockedByCSP': true,
          'timeout': 800,
        }),
        timeout: const Duration(seconds: 2),
      );
      String text;
      bool err = false;
      if (r == null || r['error'] != null) {
        text = r?['error']?.toString() ?? 'no-response';
        err = true;
      } else {
        final result = r['result'] as Map?;
        final exception = r['exceptionDetails'];
        if (exception != null) {
          text = '${(exception as Map)['text'] ?? exception}';
          err = true;
        } else if (result == null) {
          text = 'undefined';
        } else if (result['value'] != null) {
          final v = result['value'];
          text = v is String ? v : jsonEncode(v);
        } else {
          text = '${result['description'] ?? result['type'] ?? 'undefined'}';
        }
      }
      _pushWatchSample(e, text, err);
    } catch (err, st) {
      silentLog('web_reverse_watch', 'evalOne', err, st);
      _pushWatchSample(e, '$err', true);
    }
  }

  void _addExpr() {
    final loc = AppLocalizations.of(context);
    if (_exprs.length >= _kWatchMaxExpressions) {
      final isZh = loc?.localeName.startsWith('zh') ?? false;
      OpenHandSnackBar.showError(
        context,
        isZh
            ? '监视表达式最多 $_kWatchMaxExpressions 条'
            : 'Watch limit reached ($_kWatchMaxExpressions)',
      );
      return;
    }
    final code = _newCode.text.trim();
    if (code.isEmpty) return;
    if (code.length > _kWatchMaxExpressionChars) {
      OpenHandSnackBar.showError(
        context,
        'Expression too large: ${code.length}/$_kWatchMaxExpressionChars',
      );
      return;
    }
    final rawName = _newName.text.trim().isEmpty ? code : _newName.text.trim();
    final name = _capWatchText(rawName, _kWatchMaxNameChars);
    setState(() {
      _exprs.add(
        _WatchExpr(
          id: 'w_${DateTime.now().microsecondsSinceEpoch}',
          name: name,
          code: code,
        ),
      );
      _selected = _exprs.length - 1;
      _newCode.clear();
      _newName.clear();
    });
  }

  void _removeAt(int i) {
    setState(() {
      _exprs.removeAt(i);
      if (_selected >= _exprs.length) _selected = _exprs.length - 1;
    });
  }

  Future<void> _exportJson() async {
    final loc = AppLocalizations.of(context);
    final out = const JsonEncoder.withIndent('  ').convert(
      _exprs
          .map(
            (e) => {
              'name': e.name,
              'code': e.code,
              'samples': e.samples
                  .map(
                    (s) => {
                      'at': s.at.toIso8601String(),
                      'value': s.value,
                      'error': s.isError,
                    },
                  )
                  .toList(),
            },
          )
          .toList(),
    );
    final copied = await setWebReverseClipboardText(out);
    if (!mounted) return;
    final m = ScaffoldMessenger.maybeOf(context);
    if (m != null) {
      OpenHandSnackBar.showSuccessOn(
        context,
        m,
        webReverseClipboardSnackMessage(
          isZh: loc?.localeName.startsWith('zh') ?? false,
          base: loc?.webReverseWatchCopiedJson ?? 'JSON copied',
          result: copied,
        ),
      );
    }
  }

  void _pushWatchSample(_WatchExpr expr, String text, bool isError) {
    final capped = _capWatchText(text, _kWatchMaxResultChars);
    expr.last = capped;
    expr.error = isError;
    expr.samples.insert(
      0,
      _WatchSample(at: DateTime.now(), value: capped, isError: isError),
    );
    while (expr.samples.length > _kWatchMaxSamples) {
      expr.samples.removeLast();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    final cur = (_selected >= 0 && _selected < _exprs.length)
        ? _exprs[_selected]
        : null;
    return Dialog(
      backgroundColor: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1020, maxHeight: 720),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
              child: Row(
                children: [
                  Icon(Icons.visibility_rounded, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loc?.webReverseWatchTitle ?? 'Watch Expressions',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          loc?.webReverseWatchSubtitleHint(
                                _interval.inMilliseconds,
                                _kWatchMaxSamples,
                              ) ??
                              'Polls Runtime.evaluate every ${_interval.inMilliseconds}ms, keeps last $_kWatchMaxSamples samples',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: loc?.webReverseWatchExportJson ?? 'Export JSON',
                    onPressed: _exportJson,
                    icon: const Icon(Icons.upload_rounded),
                  ),
                  IconButton(
                    tooltip: _running
                        ? (loc?.webReverseWatchPause ?? 'Pause')
                        : (loc?.webReverseWatchResume ?? 'Resume'),
                    onPressed: _running ? _stop : _start,
                    icon: Icon(
                      _running
                          ? Icons.pause_circle_filled_rounded
                          : Icons.play_circle_filled_rounded,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            _IntervalRow(
              interval: _interval,
              onChanged: (d) {
                setState(() => _interval = d);
                if (_running) _start();
              },
            ),
            Divider(height: 1, color: cs.outlineVariant),
            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width: 340,
                    child: Column(
                      children: [
                        Expanded(
                          child: _exprs.isEmpty
                              ? Center(
                                  child: Text(
                                    loc?.webReverseWatchNoExpressions ??
                                        'No expressions',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.all(8),
                                  itemCount: _exprs.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 4),
                                  itemBuilder: (_, i) {
                                    final e = _exprs[i];
                                    final sel = i == _selected;
                                    return Material(
                                      color: sel
                                          ? cs.primaryContainer.withValues(
                                              alpha: 0.4,
                                            )
                                          : cs.surfaceContainerHigh,
                                      borderRadius: BorderRadius.circular(8),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(8),
                                        onTap: () =>
                                            setState(() => _selected = i),
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            10,
                                            6,
                                            4,
                                            6,
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                e.error
                                                    ? Icons.error_outline
                                                    : Icons
                                                          .check_circle_outline,
                                                size: 16,
                                                color: e.error
                                                    ? cs.error
                                                    : cs.primary,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      e.name,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: theme
                                                          .textTheme
                                                          .labelMedium,
                                                    ),
                                                    Text(
                                                      e.last.isEmpty
                                                          ? (loc?.webReverseWatchAwaiting ??
                                                                'awaiting…')
                                                          : e.last,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: theme
                                                          .textTheme
                                                          .labelSmall
                                                          ?.copyWith(
                                                            color: e.error
                                                                ? cs.error
                                                                : cs.onSurfaceVariant,
                                                            fontFamily:
                                                                'monospace',
                                                          ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              IconButton(
                                                tooltip:
                                                    loc?.webReverseWatchDelete ??
                                                    'Delete',
                                                onPressed: () => _removeAt(i),
                                                icon: const Icon(
                                                  Icons.delete_outline,
                                                  size: 16,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                        Divider(height: 1, color: cs.outlineVariant),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            children: [
                              TextField(
                                controller: _newName,
                                maxLength: _kWatchMaxNameChars,
                                maxLengthEnforcement:
                                    MaxLengthEnforcement.enforced,
                                buildCounter: _hideWatchCounter,
                                decoration: InputDecoration(
                                  labelText:
                                      loc?.webReverseWatchNameLabel ??
                                      'Name (optional)',
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _newCode,
                                minLines: 2,
                                maxLines: 4,
                                maxLength: _kWatchMaxExpressionChars,
                                maxLengthEnforcement:
                                    MaxLengthEnforcement.enforced,
                                buildCounter: _hideWatchCounter,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                                decoration: InputDecoration(
                                  labelText:
                                      loc?.webReverseWatchExpressionLabel ??
                                      'JS expression',
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                              const SizedBox(height: 6),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.tonalIcon(
                                  onPressed: _addExpr,
                                  icon: const Icon(Icons.add_rounded, size: 16),
                                  label: Text(
                                    loc?.webReverseWatchAddWatch ?? 'Add watch',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  VerticalDivider(width: 1, color: cs.outlineVariant),
                  Expanded(
                    child: cur == null
                        ? Center(
                            child: Text(
                              loc?.webReverseWatchPickWatch ?? 'Pick a watch',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          )
                        : _HistoryPane(expr: cur),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant),
            buildOpenHandDialogFooter(
              primaryLabel: loc?.webReverseWatchClose ?? 'Close',
              onPrimaryPressed: () => Navigator.of(context).pop(),
              padding: const EdgeInsets.all(12),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntervalRow extends StatelessWidget {
  const _IntervalRow({required this.interval, required this.onChanged});
  final Duration interval;
  final ValueChanged<Duration> onChanged;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    const presets = <Duration>[
      Duration(milliseconds: 500),
      Duration(milliseconds: 1500),
      Duration(seconds: 5),
      Duration(seconds: 15),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      child: Row(
        children: [
          Text(
            loc?.webReverseWatchInterval ?? 'Interval',
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Wrap(
            spacing: 6,
            children: presets.map((d) {
              final sel = d == interval;
              return ChoiceChip(
                label: Text('${d.inMilliseconds}ms'),
                selected: sel,
                onSelected: (_) => onChanged(d),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _HistoryPane extends StatelessWidget {
  const _HistoryPane({required this.expr});
  final _WatchExpr expr;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                expr.name,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              SelectableText(
                expr.code,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
          child: Row(
            children: [
              Text(
                loc?.webReverseWatchHistory(expr.samples.length) ??
                    'History (${expr.samples.length})',
                style: theme.textTheme.labelMedium,
              ),
              const Spacer(),
              if (expr.samples.isNotEmpty)
                Text(
                  loc?.webReverseWatchNewestFirst ?? 'newest first',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: expr.samples.isEmpty
              ? Center(
                  child: Text(
                    loc?.webReverseWatchAwaitingFirst ?? 'awaiting first eval…',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  itemCount: expr.samples.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (_, i) {
                    final s = expr.samples[i];
                    return Container(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                      decoration: BoxDecoration(
                        color: s.isError
                            ? cs.errorContainer.withValues(alpha: 0.3)
                            : cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _fmt(s.at),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SelectableText(
                              s.value,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: s.isError ? cs.error : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _fmt(DateTime t) => formatHourMinuteSecondMillis(t);
}

String _capWatchText(String text, int maxChars) {
  if (text.length <= maxChars) return text;
  return '${text.substring(0, maxChars)}…';
}

Widget? _hideWatchCounter(
  BuildContext context, {
  required int currentLength,
  required bool isFocused,
  required int? maxLength,
}) => null;
