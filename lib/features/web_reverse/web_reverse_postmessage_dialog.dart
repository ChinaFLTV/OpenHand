/// postMessage 追踪面板。
///
/// 思路：
///   1. 通过 `Page.addScriptToEvaluateOnNewDocument` 在新 document 注入 hook
///      把 `window.postMessage` 包裹一层、同时监听 `message` 事件，每条记录
///      写入 `window.__OH_PM__` ring buffer（最多保留 500 条）。
///   2. 启动后立刻在当前已有 document 也 `Runtime.evaluate` 一次相同脚本，
///      避免错过初始 frame；每 800ms 调一次 `__OH_PM_drain__` 把队列拉回。
///   3. UI 支持方向过滤（send/receive）、子串过滤、按行展开 data JSON、清空、
///      导出 JSON 到剪贴板。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_typography.dart';
import '../../shared/util/date_time_format.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/timer_safety.dart';
import 'web_reverse_clipboard.dart';
import 'web_reverse_dialog_utils.dart';
import 'web_reverse_pure_helpers.dart';
import 'web_reverse_session_controller.dart';

const String _kHookSource = r"""
(function(){
  if (window.__OH_PM_HOOKED__) return;
  window.__OH_PM_HOOKED__ = true;
  window.__OH_PM__ = [];
  var MAX = 500;
  function push(rec){
    try{
      var q = window.__OH_PM__;
      q.push(rec);
      if (q.length > MAX) q.splice(0, q.length - MAX);
    }catch(e){}
  }
  function safe(v){
    try{
      if (v === null || v === undefined) return v;
      if (typeof v === 'string') return v.length > 4096 ? v.slice(0,4096)+'…' : v;
      if (typeof v === 'number' || typeof v === 'boolean') return v;
      var s = JSON.stringify(v);
      if (s && s.length > 4096) s = s.slice(0,4096)+'…';
      return s;
    }catch(e){ return '[unserializable]'; }
  }
  var rawPost = window.postMessage.bind(window);
  window.postMessage = function(message, targetOrigin, transfer){
    push({
      dir: 'send',
      t: Date.now(),
      origin: location.origin,
      target: typeof targetOrigin === 'string' ? targetOrigin : '*',
      data: safe(message)
    });
    return rawPost(message, targetOrigin, transfer);
  };
  window.addEventListener('message', function(ev){
    try{
      push({
        dir: 'recv',
        t: Date.now(),
        origin: ev.origin || '',
        source: (ev.source && ev.source.location && ev.source.location.href) ? ev.source.location.href : '',
        data: safe(ev.data)
      });
    }catch(e){}
  }, true);
  window.__OH_PM_drain__ = function(){
    var q = window.__OH_PM__ || [];
    window.__OH_PM__ = [];
    return JSON.stringify(q);
  };
  window.__OH_PM_clear__ = function(){ window.__OH_PM__ = []; return true; };
})();
""";

class _PmRecord {
  factory _PmRecord.fromJson(Map<String, Object?> j) => _PmRecord(
    dir: j['dir']?.toString() ?? 'recv',
    at: DateTime.fromMillisecondsSinceEpoch(
      (j['t'] is num)
          ? (j['t'] as num).toInt()
          : DateTime.now().millisecondsSinceEpoch,
    ),
    origin: j['origin']?.toString() ?? '',
    target: j['target']?.toString() ?? '',
    source: j['source']?.toString() ?? '',
    data: j['data']?.toString() ?? '',
  );
  _PmRecord({
    required this.dir,
    required this.at,
    required this.origin,
    required this.target,
    required this.source,
    required this.data,
  });

  final String dir; // 'send' / 'recv'
  final DateTime at;
  final String origin;
  final String target;
  final String source;
  final String data;

  Map<String, Object?> toJson() => <String, Object?>{
    'dir': dir,
    'at': at.toIso8601String(),
    'origin': origin,
    'target': target,
    'source': source,
    'data': data,
  };
}

Future<void> showWebReversePostMessageDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) {
  return webReverseToolDialogs.show<void>(
    context: context,
    builder: (_) => _PmDialog(controller: controller),
  );
}

class _PmDialog extends StatefulWidget {
  const _PmDialog({required this.controller});
  final WebReverseSessionController controller;
  @override
  State<_PmDialog> createState() => _PmDialogState();
}

class _PmDialogState extends State<_PmDialog> {
  final List<_PmRecord> _records = <_PmRecord>[];
  final TextEditingController _filterCtrl = TextEditingController();
  Timer? _pollTimer;
  bool _hooked = false;
  bool _busy = false;
  String? _status;
  String? _hookScriptId;

  // 方向开关
  bool _showSend = true;
  bool _showRecv = true;

  @override
  void dispose() {
    _pollTimer?.cancel();
    _removeNewDocumentHook();
    _filterCtrl.dispose();
    super.dispose();
  }

  void _removeNewDocumentHook() {
    final scriptId = _hookScriptId;
    if (scriptId == null) return;
    _hookScriptId = null;
    unawaited(
      removeWebReverseNewDocumentScriptBestEffort(
        controller: widget.controller,
        identifier: scriptId,
      ),
    );
  }

  Future<void> _toggleHook() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!_hooked) {
        // 1. 注入 on-new-document（覆盖未来 navigation）
        final addRes = await widget.controller.sendRawCdp(
          method: 'Page.addScriptToEvaluateOnNewDocument',
          paramsJson: jsonEncode({'source': _kHookSource}),
        );
        if (addRes != null && addRes['identifier'] != null) {
          _hookScriptId = addRes['identifier'].toString();
        }
        // 2. 当前 document 也直接 eval 一次
        await widget.controller.sendRawCdp(
          method: 'Runtime.evaluate',
          paramsJson: jsonEncode({
            'expression': _kHookSource,
            'awaitPromise': false,
            'returnByValue': true,
          }),
        );
        _pollTimer?.cancel();
        _pollTimer = startNonOverlappingPeriodicTimer(
          const Duration(milliseconds: 800),
          (_) => _drain(),
        );
        if (mounted) {
          setState(() {
            _hooked = true;
            _status =
                AppLocalizations.of(context)?.webReversePmHookInjected ??
                'Hook injected';
          });
        }
      } else {
        _pollTimer?.cancel();
        _pollTimer = null;
        // 清理：撤销 on-new-document + 还原（页面侧 hook 一旦注入只能等 reload）
        final hookScriptId = _hookScriptId;
        _hookScriptId = null;
        if (hookScriptId != null) {
          await widget.controller.sendRawCdp(
            method: 'Page.removeScriptToEvaluateOnNewDocument',
            paramsJson: jsonEncode({'identifier': hookScriptId}),
          );
        }
        if (mounted) {
          setState(() {
            _hooked = false;
            _status =
                AppLocalizations.of(context)?.webReversePmHookStopped ??
                'Stopped (full unhook after reload)';
          });
        }
      }
    } catch (e, st) {
      silentLog('web_reverse_pm', '切换 postMessage 监听', e, st);
      if (mounted) setState(() => _status = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _drain() async {
    try {
      final r = await widget.controller.sendRawCdp(
        method: 'Runtime.evaluate',
        paramsJson: jsonEncode({
          'expression':
              'window.__OH_PM_drain__ ? window.__OH_PM_drain__() : "[]"',
          'returnByValue': true,
        }),
      );
      if (r == null || r['error'] != null) return;
      final value = cdpStringResultValue(r);
      if (value == null || value.isEmpty) return;
      final parsed = jsonDecode(value);
      if (parsed is! List) return;
      if (parsed.isEmpty) return;
      if (!mounted) return;
      setState(() {
        for (final m in parsed) {
          if (m is Map) {
            try {
              _records.add(_PmRecord.fromJson(stringKeyedMapFromValue(m)));
            } catch (e, st) {
              silentLog('web_reverse_pm', '解析 postMessage 记录', e, st);
            }
          }
        }
        if (_records.length > 1000) {
          _records.removeRange(0, _records.length - 1000);
        }
      });
    } catch (e, st) {
      silentLog('web_reverse_pm', '排空 postMessage 事件', e, st);
    }
  }

  Future<void> _clear() async {
    setState(() => _records.clear());
    try {
      await widget.controller.sendRawCdp(
        method: 'Runtime.evaluate',
        paramsJson: jsonEncode({
          'expression': 'window.__OH_PM_clear__ && window.__OH_PM_clear__()',
          'returnByValue': true,
        }),
      );
    } catch (e, st) {
      silentLog('web_reverse_pm', '清空 postMessage 事件', e, st);
    }
  }

  Future<void> _copy() async {
    final filtered = _filtered();
    if (filtered.isEmpty) return;
    final json = prettyPrintJson(filtered.map((r) => r.toJson()).toList());
    final loc = AppLocalizations.of(context);
    await copyWebReverseTextToClipboard(
      context: context,
      text: json,
      successBase:
          loc?.webReversePmCopiedCount(filtered.length) ??
          'Copied ${filtered.length} records',
      logTag: 'web_reverse_pm',
    );
  }

  List<_PmRecord> _filtered() {
    final q = _filterCtrl.text.trim().toLowerCase();
    return _records.where((r) {
      if (r.dir == 'send' && !_showSend) return false;
      if (r.dir == 'recv' && !_showRecv) return false;
      if (q.isEmpty) return true;
      return r.origin.toLowerCase().contains(q) ||
          r.target.toLowerCase().contains(q) ||
          r.source.toLowerCase().contains(q) ||
          r.data.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    final filtered = _filtered();
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: 920,
      maxHeight: 760,
      insetPadding: const EdgeInsets.all(24),
      child: Column(
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.swap_horiz_rounded,
            title: loc?.webReversePmTitle ?? 'postMessage Trace',
            subtitle:
                loc?.webReversePmSubtitle ??
                'Inject hook → ring buffer → drain every 800ms (incl. iframe)',
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _toggleHook,
                  icon: Icon(
                    _hooked ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  ),
                  label: Text(
                    _hooked
                        ? (loc?.webReversePmStop ?? 'Stop')
                        : (loc?.webReversePmInject ?? 'Inject'),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.tonalIcon(
                  onPressed: _records.isEmpty ? null : _clear,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: Text(loc?.webReversePmClear ?? 'Clear'),
                ),
                const SizedBox(width: 10),
                FilledButton.tonalIcon(
                  onPressed: filtered.isEmpty ? null : _copy,
                  icon: const Icon(Icons.copy_all_rounded),
                  label: Text(loc?.webReversePmCopyJson ?? 'Copy JSON'),
                ),
                const Spacer(),
                Text(
                  '${filtered.length}/${_records.length}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _filterCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      hintText:
                          loc?.webReversePmFilterHint ?? 'filter by substring',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilterChip(
                  label: Text(loc?.webReversePmChipSend ?? 'Send'),
                  selected: _showSend,
                  onSelected: (v) => setState(() => _showSend = v),
                ),
                const SizedBox(width: 6),
                FilterChip(
                  label: Text(loc?.webReversePmChipRecv ?? 'Recv'),
                  selected: _showRecv,
                  onSelected: (v) => setState(() => _showRecv = v),
                ),
              ],
            ),
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _status!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontFamily: kOpenHandMonospaceFontFamily,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 6),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              decoration: webReverseSurfaceCardDecoration(cs),
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        _hooked
                            ? (loc?.webReversePmWaiting ??
                                  'Waiting for postMessage…')
                            : (loc?.webReversePmClickToCapture ??
                                  'Click Inject to start capturing'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: filtered.length,
                      reverse: true,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, color: cs.outlineVariant),
                      itemBuilder: (_, i) {
                        final r = filtered[filtered.length - 1 - i];
                        final isSend = r.dir == 'send';
                        final accent = isSend ? cs.tertiary : cs.primary;
                        return Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      isSend
                                          ? (loc?.webReversePmTagSend ?? 'SEND')
                                          : (loc?.webReversePmTagRecv ??
                                                'RECV'),
                                      style: TextStyle(
                                        color: accent,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    formatHourMinuteSecondMillis(r.at),
                                    style: const TextStyle(
                                      fontFamily: kOpenHandMonospaceFontFamily,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      isSend
                                          ? '${r.origin}  →  ${r.target}'
                                          : '${r.origin}  →  (this)',
                                      style: TextStyle(
                                        fontFamily:
                                            kOpenHandMonospaceFontFamily,
                                        fontSize: 11,
                                        color: cs.onSurfaceVariant,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              SelectableText(
                                r.data,
                                style: const TextStyle(
                                  fontFamily: kOpenHandMonospaceFontFamily,
                                  fontSize: 11,
                                ),
                                maxLines: 6,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
          buildWebReverseDialogFooter(
            context,
            actions: [
              OpenHandDialogActionButton.secondary(
                label: loc?.webReversePmClose ?? 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
