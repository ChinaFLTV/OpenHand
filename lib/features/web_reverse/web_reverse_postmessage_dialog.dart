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
import '../../shared/ui/openhand_spacing.dart';
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
  var MAX_TEXT = 4096;
  var MAX_KEYS = 16;
  var MAX_DEPTH = 3;
  var MAX_NODES = 128;
  function cap(v, max){ return String(v == null ? '' : v).slice(0, max); }
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
      if (typeof v === 'string') return cap(v, MAX_TEXT);
      if (typeof v === 'number' || typeof v === 'boolean') return v;
      var seen = new WeakSet();
      var remaining = MAX_NODES;
      function normalize(value, depth){
        if (--remaining < 0) return '[Truncated]';
        if (value === null || value === undefined) return value;
        var type = typeof value;
        if (type === 'string') return cap(value, 512);
        if (type === 'number' || type === 'boolean') return value;
        if (type !== 'object') return cap(value, 512);
        if (depth >= MAX_DEPTH) return '[Max depth]';
        if (seen.has(value)) return '[Circular]';
        seen.add(value);
        try {
          if (Array.isArray(value)) {
            var array = [];
            for (var i = 0; i < value.length && i < MAX_KEYS; i++) {
              array.push(normalize(value[i], depth + 1));
            }
            return array;
          }
          var out = {};
          var count = 0;
          for (var key in value) {
            if (count >= MAX_KEYS) break;
            if (!Object.prototype.hasOwnProperty.call(value, key)) continue;
            var boundedKey = cap(key, 256);
            try { out[boundedKey] = normalize(value[key], depth + 1); }
            catch (_) { out[boundedKey] = '[Unreadable]'; }
            count++;
          }
          return out;
        } finally {
          seen.delete(value);
        }
      }
      var serialized = JSON.stringify(normalize(v, 0));
      return cap(serialized, MAX_TEXT);
    }catch(e){ return '[unserializable]'; }
  }
  var rawPost = window.postMessage;
  var wrappedPost = function(message, targetOrigin, transfer){
    push({
      dir: 'send',
      t: Date.now(),
      origin: cap(location.origin, MAX_TEXT),
      target: typeof targetOrigin === 'string' ? cap(targetOrigin, MAX_TEXT) : '*',
      data: safe(message)
    });
    return rawPost.call(window, message, targetOrigin, transfer);
  };
  window.postMessage = wrappedPost;
  var onMessage = function(ev){
    try{
      var source = '';
      try {
        source = ev.source && ev.source.location
          ? cap(ev.source.location.href, MAX_TEXT)
          : '';
      } catch (_) {}
      push({
        dir: 'recv',
        t: Date.now(),
        origin: cap(ev.origin || '', MAX_TEXT),
        source: source,
        data: safe(ev.data)
      });
    }catch(e){}
  };
  window.addEventListener('message', onMessage, true);
  window.__OH_PM_drain__ = function(){
    var q = window.__OH_PM__ || [];
    window.__OH_PM__ = [];
    return JSON.stringify(q);
  };
  window.__OH_PM_clear__ = function(){ window.__OH_PM__ = []; return true; };
  window.__OH_PM_STOP__ = function(){
    window.removeEventListener('message', onMessage, true);
    if (window.postMessage === wrappedPost) window.postMessage = rawPost;
    window.__OH_PM__ = [];
    delete window.__OH_PM_drain__;
    delete window.__OH_PM_clear__;
    delete window.__OH_PM_HOOKED__;
    delete window.__OH_PM_STOP__;
    return true;
  };
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

  final String dir; // 发送/接收
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
    unawaited(_cleanupHook());
    _filterCtrl.dispose();
    super.dispose();
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
        final rawHookScriptId = addRes?['identifier'];
        if (rawHookScriptId is! String ||
            rawHookScriptId.isEmpty ||
            rawHookScriptId.length > kWebReverseMaxRemoteObjectIdChars) {
          throw StateError(
            '${addRes?['error'] ?? '浏览器未返回有效的 postMessage 脚本标识。'}',
          );
        }
        final hookScriptId = rawHookScriptId;
        if (!mounted) {
          await removeWebReverseNewDocumentScriptBestEffort(
            controller: widget.controller,
            identifier: hookScriptId,
          );
          return;
        }
        _hookScriptId = hookScriptId;
        // 2. 当前 document 也直接 eval 一次
        final evaluation = await widget.controller.evaluateJavaScript(
          _kHookSource,
        );
        if (evaluation == null ||
            evaluation['error'] != null ||
            evaluation['exceptionDetails'] is Map) {
          throw StateError('页面 postMessage 监听脚本注入失败。');
        }
        if (!mounted) {
          await _cleanupHook();
          return;
        }
        _pollTimer?.cancel();
        _pollTimer = startNonOverlappingPeriodicTimer(
          const Duration(milliseconds: 800),
          (timer) => _drain(timer),
        );
        setState(() {
          _hooked = true;
          _status =
              AppLocalizations.of(context)?.webReversePmHookInjected ??
              'Hook injected';
        });
      } else {
        await _cleanupHook();
        if (mounted) {
          setState(() {
            _hooked = false;
            _status =
                AppLocalizations.of(context)?.webReversePmHookStopped ??
                'Stopped';
          });
        }
      }
    } catch (e, st) {
      silentLog('web_reverse_pm', '切换 postMessage 监听', e, st);
      await _cleanupHook();
      if (mounted) setState(() => _status = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _cleanupHook() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    final hookScriptId = _hookScriptId;
    _hookScriptId = null;
    if (hookScriptId != null) {
      await removeWebReverseNewDocumentScriptBestEffort(
        controller: widget.controller,
        identifier: hookScriptId,
      );
    }
    try {
      await widget.controller.evaluateJavaScript(
        'window.__OH_PM_STOP__ && window.__OH_PM_STOP__()',
        returnByValue: false,
        timeout: const Duration(seconds: 3),
      );
    } catch (error, stack) {
      silentLog('web_reverse_pm', '清理 postMessage 监听', error, stack);
    }
    _hooked = false;
  }

  Future<void> _drain(Timer timer) async {
    try {
      final r = await widget.controller.evaluateJavaScript(
        'window.__OH_PM_drain__ ? window.__OH_PM_drain__() : "[]"',
      );
      if (!mounted || !_hooked || !identical(_pollTimer, timer)) return;
      if (r == null || r['error'] != null) return;
      final value = cdpStringResultValue(r);
      if (value == null || value.isEmpty) return;
      final parsed = jsonDecode(value);
      if (parsed is! List) return;
      if (parsed.isEmpty) return;
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
      await widget.controller.evaluateJavaScript(
        'window.__OH_PM_clear__ && window.__OH_PM_clear__()',
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
      maxWidth: kOpenHandDialogWidthExtraWide,
      maxHeight: kOpenHandDialogHeightTall,
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
                kOpenHandHGap10,
                FilledButton.tonalIcon(
                  onPressed: _records.isEmpty ? null : _clear,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: Text(loc?.webReversePmClear ?? 'Clear'),
                ),
                kOpenHandHGap10,
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
                kOpenHandHGap12,
                FilterChip(
                  label: Text(loc?.webReversePmChipSend ?? 'Send'),
                  selected: _showSend,
                  onSelected: (v) => setState(() => _showSend = v),
                ),
                kOpenHandHGap6,
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
          kOpenHandGap6,
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
                                      borderRadius: kOpenHandBorderRadius4,
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
                                  kOpenHandHGap8,
                                  Text(
                                    formatHourMinuteSecondMillis(r.at),
                                    style: const TextStyle(
                                      fontFamily: kOpenHandMonospaceFontFamily,
                                      fontSize: 11,
                                    ),
                                  ),
                                  kOpenHandHGap8,
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
                              kOpenHandGap4,
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
