/// DOM Mutation 录制面板。
///
/// 通过 CDP 注入一个全局 MutationObserver，监听 `document.documentElement`
/// 的 subtree 上所有 childList/attributes/characterData 变更，将每条变更
/// 压成精简记录写入 `window.__OH_DOM_MUT_BUF__` 队列（最多 5000 条）。
/// 面板每 800ms 从该队列 splice 出新条目并合并到本地 timeline。
///
/// 通过 `Page.addScriptToEvaluateOnNewDocument` + 立即 `Runtime.evaluate`
/// 安装，刷新 / SPA 路由切换都能继续录制；`Stop` 时清除 script identifier
/// 并断开 observer。
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/auto_follow_scroll_guard.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import '../../shared/ui/openhand_typography.dart';
import '../../shared/util/byte_size_format.dart';
import '../../shared/util/date_time_format.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/text_clip.dart';
import '../../shared/util/timer_safety.dart';
import 'web_reverse_clipboard.dart';
import 'web_reverse_dialog_utils.dart';
import 'web_reverse_pure_helpers.dart';
import 'web_reverse_session_controller.dart';

const int _kMaxMutationRecords = 5000;
const int _kMaxMutationRetainedChars = 8 * kBytesPerMiB;
const int _kMaxMutationDrainRecords = 500;
const int _kMaxMutationDrainJsonChars = 2 * kBytesPerMiB;
const int _kMaxMutationTargetChars = 512;
const int _kMaxMutationValueChars = kBytesPerKiB;
const int _kMaxMutationChildNodes = 8;
const int _kMaxMutationCallbackRecords = 1000;

final String _kInstallScript =
    r'''
(function(){
  if (window.__OH_DOM_MUT_INSTALLED__) return;
  window.__OH_DOM_MUT_INSTALLED__ = true;
  window.__OH_DOM_MUT_BUF__ = [];
  window.__OH_DOM_MUT_SEQ__ = 0;
  var maxBuf = __MAX_BUFFER__;
  var maxTargetChars = __MAX_TARGET_CHARS__;
  var maxValueChars = __MAX_VALUE_CHARS__;
  var maxChildNodes = __MAX_CHILD_NODES__;
  var maxCallbackRecords = __MAX_CALLBACK_RECORDS__;
  function cap(v, max){
    if (v === null || v === undefined) return null;
    return String(v).slice(0, max);
  }
  function describe(node){
    if (!node) return '';
    if (node.nodeType === 1) {
      var n = node.nodeName.toLowerCase();
      var id = node.id ? ('#' + cap(node.id, maxTargetChars)) : '';
      var cls = (node.className && typeof node.className === 'string')
        ? ('.' + node.className.slice(0, maxTargetChars).trim().split(/\s+/).slice(0,3).join('.'))
        : '';
      return (n + id + cls).slice(0, maxTargetChars);
    }
    if (node.nodeType === 3) {
      var t = (node.nodeValue || '').slice(0, 60);
      return '#text("'+ t.replace(/\s+/g,' ') +'")';
    }
    return '#node' + node.nodeType;
  }
  function push(rec){
    window.__OH_DOM_MUT_BUF__.push(rec);
    if (window.__OH_DOM_MUT_BUF__.length > maxBuf) {
      window.__OH_DOM_MUT_BUF__.splice(0, window.__OH_DOM_MUT_BUF__.length - maxBuf);
    }
  }
  var obs = new MutationObserver(function(list){
    var t = Date.now();
    var startIndex = Math.max(0, list.length - maxCallbackRecords);
    for (var i = startIndex; i < list.length; i++) {
      var m = list[i];
      var rec = {
        seq: ++window.__OH_DOM_MUT_SEQ__,
        t: t,
        kind: m.type,
        target: describe(m.target)
      };
      if (m.type === 'attributes') {
        rec.attr = cap(m.attributeName, 256);
        try { rec.oldValue = cap(m.oldValue, maxValueChars); } catch(e) {}
        try {
          rec.newValue = (m.target && m.target.getAttribute)
            ? cap(m.target.getAttribute(m.attributeName), maxValueChars) : null;
        } catch(e) {}
      } else if (m.type === 'characterData') {
        try { rec.oldValue = (m.oldValue||'').slice(0,120); } catch(e) {}
        try { rec.newValue = (m.target.nodeValue||'').slice(0,120); } catch(e) {}
      } else if (m.type === 'childList') {
        rec.added = [];
        rec.removed = [];
        for (var k = 0; k < m.addedNodes.length && k < maxChildNodes; k++) rec.added.push(describe(m.addedNodes[k]));
        for (var k2 = 0; k2 < m.removedNodes.length && k2 < maxChildNodes; k2++) rec.removed.push(describe(m.removedNodes[k2]));
      }
      push(rec);
    }
  });
  function start(){
    if (!window.__OH_DOM_MUT_INSTALLED__) return;
    try {
      obs.observe(document.documentElement || document, {
        attributes: true,
        attributeOldValue: true,
        characterData: true,
        characterDataOldValue: true,
        childList: true,
        subtree: true,
      });
    } catch(e) { /* 文档尚未就绪 */ }
  }
  if (document.documentElement) {
    start();
  } else {
    document.addEventListener('DOMContentLoaded', start, { once: true });
  }
  window.__OH_DOM_MUT_STOP__ = function(){
    document.removeEventListener('DOMContentLoaded', start);
    try { obs.disconnect(); } catch(e) {}
    delete window.__OH_DOM_MUT_BUF__;
    delete window.__OH_DOM_MUT_SEQ__;
    delete window.__OH_DOM_MUT_DRAIN__;
    delete window.__OH_DOM_MUT_INSTALLED__;
    delete window.__OH_DOM_MUT_STOP__;
    return true;
  };
  window.__OH_DOM_MUT_DRAIN__ = function(max){
    var b = window.__OH_DOM_MUT_BUF__;
    if (!Array.isArray(b)) return [];
    var count = Math.max(1, Math.min(Number(max) || 1, b.length));
    return b.splice(0, count);
  };
})();
'''
        .replaceAll('__MAX_BUFFER__', '$_kMaxMutationRecords')
        .replaceAll('__MAX_TARGET_CHARS__', '$_kMaxMutationTargetChars')
        .replaceAll('__MAX_VALUE_CHARS__', '$_kMaxMutationValueChars')
        .replaceAll('__MAX_CHILD_NODES__', '$_kMaxMutationChildNodes')
        .replaceAll(
          '__MAX_CALLBACK_RECORDS__',
          '$_kMaxMutationCallbackRecords',
        );

Map<String, Object?>? _normalizeMutationRecord(Map<String, Object?> raw) {
  final kind = '${raw['kind'] ?? ''}';
  if (kind != 'attributes' && kind != 'characterData' && kind != 'childList') {
    return null;
  }
  String bounded(Object? value, int maxChars) =>
      clipText('${value ?? ''}', maxChars, suffix: '');
  String? boundedOptional(Object? value, int maxChars) =>
      value == null ? null : clipText('$value', maxChars, suffix: '');

  final normalized = <String, Object?>{
    'kind': kind,
    'target': bounded(raw['target'], _kMaxMutationTargetChars),
  };
  final sequence = optionalIntegralIntFromValue(raw['seq']);
  final timestamp = optionalIntegralIntFromValue(raw['t']);
  if (sequence != null) normalized['seq'] = sequence;
  if (timestamp != null) normalized['t'] = timestamp;
  if (kind == 'attributes') {
    normalized['attr'] = bounded(raw['attr'], 256);
    normalized['oldValue'] = boundedOptional(
      raw['oldValue'],
      _kMaxMutationValueChars,
    );
    normalized['newValue'] = boundedOptional(
      raw['newValue'],
      _kMaxMutationValueChars,
    );
  } else if (kind == 'characterData') {
    normalized['oldValue'] = boundedOptional(
      raw['oldValue'],
      _kMaxMutationValueChars,
    );
    normalized['newValue'] = boundedOptional(
      raw['newValue'],
      _kMaxMutationValueChars,
    );
  } else {
    for (final field in const <String>['added', 'removed']) {
      normalized[field] = stringListFromValue(raw[field])
          .take(_kMaxMutationChildNodes)
          .map((value) => bounded(value, _kMaxMutationTargetChars))
          .toList(growable: false);
    }
  }
  return Map<String, Object?>.unmodifiable(normalized);
}

int _estimatedMutationRecordChars(Map<String, Object?> record) {
  var total = 48;
  for (final value in record.values) {
    if (value is String) {
      total += value.length;
    } else if (value is List) {
      total += value.whereType<String>().fold<int>(
        0,
        (sum, item) => sum + item.length,
      );
    } else {
      total += 8;
    }
  }
  return total;
}

Future<void> showWebReverseDomMutationDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) {
  return webReverseToolDialogs.show<void>(
    context: context,
    builder: (_) => _DomMutationDialog(controller: controller),
  );
}

class _DomMutationDialog extends StatefulWidget {
  const _DomMutationDialog({required this.controller});
  final WebReverseSessionController controller;
  @override
  State<_DomMutationDialog> createState() => _DomMutationDialogState();
}

class _DomMutationDialogState extends State<_DomMutationDialog> {
  bool _installing = false;
  bool _recording = false;
  String? _scriptIdentifier;
  Timer? _drainTimer;
  final ListQueue<Map<String, Object?>> _records =
      ListQueue<Map<String, Object?>>();
  int _retainedRecordChars = 0;
  String _filter = '';
  String _kindFilter = 'all'; // all|attributes|characterData|childList
  final ScrollController _scroll = ScrollController();
  final AutoFollowScrollGuard _scrollGuard = AutoFollowScrollGuard();
  bool _autoFollow = true;

  @override
  void dispose() {
    _drainTimer?.cancel();
    unawaited(_cleanupInstalledScript(notify: false));
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _install() async {
    if (_installing || _recording) return;
    setState(() => _installing = true);
    try {
      // 注册到 new document 上 → 刷新后立即生效。
      final reg = await widget.controller.sendRawCdp(
        method: 'Page.addScriptToEvaluateOnNewDocument',
        paramsJson: jsonEncode({'source': _kInstallScript}),
      );
      final rawScriptIdentifier = reg?['identifier'];
      if (rawScriptIdentifier is! String ||
          rawScriptIdentifier.isEmpty ||
          rawScriptIdentifier.length > kWebReverseMaxRemoteObjectIdChars) {
        throw StateError('${reg?['error'] ?? '浏览器未返回有效的 DOM 变更脚本标识。'}');
      }
      _scriptIdentifier = rawScriptIdentifier;
      if (!mounted) {
        await _cleanupInstalledScript(notify: false);
        return;
      }
      // 当前页面立即装一次。
      final evaluation = await widget.controller.evaluateJavaScript(
        _kInstallScript,
        returnByValue: false,
      );
      if (evaluation == null ||
          evaluation['error'] != null ||
          evaluation['exceptionDetails'] is Map) {
        throw StateError('页面 DOM 变更脚本注入失败。');
      }
      if (!mounted) {
        await _cleanupInstalledScript(notify: false);
        return;
      }
      _drainTimer = startNonOverlappingPeriodicTimer(
        const Duration(milliseconds: 800),
        (timer) => _drain(timer),
      );
      setState(() {
        _recording = true;
        _installing = false;
      });
      showOpenHandSuccessSnack(
        context,
        AppLocalizations.of(context)?.webReverseDomMutRecordingStarted ??
            'Recording DOM mutations',
      );
    } catch (e, st) {
      silentLog('web_reverse_dom_mutation', '安装 DOM 变更监听', e, st);
      await _cleanupInstalledScript(notify: false);
      if (mounted) {
        setState(() {
          _installing = false;
          _recording = false;
        });
      }
      if (mounted) {
        showOpenHandErrorSnack(
          context,
          AppLocalizations.of(
                context,
              )?.webReverseDomMutInstallFailed(e.toString()) ??
              'Install failed: $e',
        );
      }
    }
  }

  Future<void> _stop() => _cleanupInstalledScript();

  void _clearRecords() {
    _records.clear();
    _retainedRecordChars = 0;
  }

  bool _appendRecord(Map<String, Object?> raw) {
    final normalized = _normalizeMutationRecord(raw);
    if (normalized == null) return false;
    final cost = _estimatedMutationRecordChars(normalized);
    while (_records.isNotEmpty &&
        (_records.length >= _kMaxMutationRecords ||
            _retainedRecordChars + cost > _kMaxMutationRetainedChars)) {
      _retainedRecordChars -= _estimatedMutationRecordChars(
        _records.removeFirst(),
      );
    }
    if (_retainedRecordChars + cost > _kMaxMutationRetainedChars) {
      return false;
    }
    _records.addLast(normalized);
    _retainedRecordChars += cost;
    return true;
  }

  Future<void> _cleanupInstalledScript({bool notify = true}) async {
    _drainTimer?.cancel();
    _drainTimer = null;
    final scriptIdentifier = _scriptIdentifier;
    _scriptIdentifier = null;
    if (scriptIdentifier != null) {
      await removeWebReverseNewDocumentScriptBestEffort(
        controller: widget.controller,
        identifier: scriptIdentifier,
      );
    }
    try {
      await widget.controller.evaluateJavaScript(
        'window.__OH_DOM_MUT_STOP__ && window.__OH_DOM_MUT_STOP__()',
        returnByValue: false,
        timeout: const Duration(seconds: 3),
      );
    } catch (e, st) {
      silentLog('web_reverse_dom_mutation', '停止 DOM 变更监听', e, st);
    }
    if (notify && mounted) {
      setState(() {
        _recording = false;
        _installing = false;
      });
    }
  }

  Future<void> _drain(Timer timer) async {
    try {
      final r = await widget.controller.evaluateJavaScript(
        '(window.__OH_DOM_MUT_DRAIN__ && JSON.stringify(window.__OH_DOM_MUT_DRAIN__($_kMaxMutationDrainRecords))) || "[]"',
      );
      if (!mounted || !_recording || !identical(_drainTimer, timer)) {
        return;
      }
      final v = cdpStringResultValue(r);
      if (v == null || v.length > _kMaxMutationDrainJsonChars) return;
      final list = decodeStringKeyedJsonMapList(v);
      if (list == null) return;
      bool dirty = false;
      for (final item in list.take(_kMaxMutationDrainRecords)) {
        dirty = _appendRecord(item) || dirty;
      }
      if (dirty) {
        setState(() {});
        if (_autoFollow) {
          _scrollGuard.scheduleFollowToBottom(_scroll, animated: true);
        }
      }
    } catch (e, st) {
      silentLog('web_reverse_dom_mutation', '排空 DOM 变更事件', e, st);
    }
  }

  Future<void> _exportJson() async {
    final loc = AppLocalizations.of(context);
    await copyWebReverseTextToClipboard(
      context: context,
      text: prettyPrintJson(_records.toList(growable: false)),
      successBase:
          loc?.webReverseDomMutCopiedRecords(_records.length) ??
          'Copied ${_records.length} records',
      logTag: 'web_reverse_dom_mutation',
    );
  }

  List<Map<String, Object?>> _filtered() {
    final f = _filter.trim().toLowerCase();
    return _records.where((r) {
      if (_kindFilter != 'all' && r['kind'] != _kindFilter) return false;
      if (f.isEmpty) return true;
      final s = jsonEncode(r).toLowerCase();
      return s.contains(f);
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
      maxWidth: kOpenHandDialogWidthPanel,
      maxHeight: kOpenHandDialogHeightTall,
      child: Column(
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.timeline_rounded,
            title: loc?.webReverseDomMutTitle ?? 'DOM Mutation Recorder',
            subtitle:
                loc?.webReverseDomMutSubtitle ??
                'Injects MutationObserver → live timeline',
            actions: [
              IconButton(
                tooltip: loc?.webReverseDomMutExportJson ?? 'Export JSON',
                onPressed: _records.isEmpty ? null : _exportJson,
                icon: const Icon(Icons.upload_rounded),
              ),
            ],
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  onPressed: (_installing || _recording) ? null : _install,
                  icon: Icon(
                    _recording
                        ? Icons.fiber_manual_record
                        : Icons.play_arrow_rounded,
                  ),
                  label: Text(
                    _recording
                        ? (loc?.webReverseDomMutRecording ?? 'Recording')
                        : (loc?.webReverseDomMutStart ?? 'Start'),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _recording ? _stop : null,
                  icon: const Icon(Icons.stop_rounded),
                  label: Text(loc?.webReverseDomMutStop ?? 'Stop'),
                ),
                OutlinedButton.icon(
                  onPressed: _records.isEmpty
                      ? null
                      : () => setState(_clearRecords),
                  icon: const Icon(Icons.cleaning_services_rounded, size: 16),
                  label: Text(loc?.webReverseDomMutClear ?? 'Clear'),
                ),
                for (final k in const [
                  'all',
                  'childList',
                  'attributes',
                  'characterData',
                ])
                  ChoiceChip(
                    label: Text(k),
                    selected: _kindFilter == k,
                    onSelected: (_) => setState(() => _kindFilter = k),
                  ),
                SizedBox(
                  width: 220,
                  child: TextField(
                    onChanged: (v) => setState(() => _filter = v),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(
                        Icons.filter_alt_outlined,
                        size: 16,
                      ),
                      labelText:
                          loc?.webReverseDomMutFilterHint ??
                          'Filter (substring)',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                FilterChip(
                  selected: _autoFollow,
                  onSelected: (v) => setState(() => _autoFollow = v),
                  label: Text(loc?.webReverseDomMutAutoFollow ?? 'Auto-follow'),
                ),
                Text(
                  loc?.webReverseDomMutCounter(
                        filtered.length,
                        _records.length,
                      ) ??
                      '${filtered.length} / ${_records.length}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      _recording
                          ? (loc?.webReverseDomMutWaiting ??
                                'Waiting for mutations…')
                          : (loc?.webReverseDomMutPressStart ?? 'Press Start'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  )
                : NotificationListener<ScrollNotification>(
                    onNotification: _scrollGuard.handleNotification,
                    child: ListView.builder(
                      controller: _scroll,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final r = filtered[i];
                        return _MutRow(rec: r);
                      },
                    ),
                  ),
          ),
          buildWebReverseDialogFooter(
            context,
            actions: [
              OpenHandDialogActionButton.secondary(
                label: loc?.webReverseDomMutClose ?? 'Close',
                onPressed: () async {
                  if (_recording) await _stop();
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MutRow extends StatelessWidget {
  const _MutRow({required this.rec});
  final Map<String, Object?> rec;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final kind = '${rec['kind'] ?? '?'}';
    final color = switch (kind) {
      'attributes' => cs.tertiary,
      'characterData' => cs.secondary,
      'childList' => cs.primary,
      _ => cs.onSurfaceVariant,
    };
    final t = rec['t'];
    String ts = '';
    if (t is int) {
      ts = formatHourMinuteSecondMillis(DateTime.fromMillisecondsSinceEpoch(t));
    }
    String detail;
    if (kind == 'attributes') {
      detail =
          '@${rec['attr']} : ${rec['oldValue'] ?? 'null'} → ${rec['newValue'] ?? 'null'}';
    } else if (kind == 'characterData') {
      detail = '"${rec['oldValue']}" → "${rec['newValue']}"';
    } else if (kind == 'childList') {
      final added = (rec['added'] as List?)?.join(', ') ?? '';
      final removed = (rec['removed'] as List?)?.join(', ') ?? '';
      final parts = <String>[];
      if (added.isNotEmpty) parts.add('+ $added');
      if (removed.isNotEmpty) parts.add('- $removed');
      detail = parts.join('   ');
    } else {
      detail = jsonEncode(rec);
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: Text(
              ts,
              style: const TextStyle(
                fontFamily: kOpenHandMonospaceFontFamily,
                fontSize: 11,
              ),
            ),
          ),
          SizedBox(
            width: 92,
            child: Text(
              kind,
              style: TextStyle(
                fontFamily: kOpenHandMonospaceFontFamily,
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            width: 220,
            child: Text(
              '${rec['target'] ?? ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: kOpenHandMonospaceFontFamily,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              detail,
              style: const TextStyle(
                fontFamily: kOpenHandMonospaceFontFamily,
                fontSize: 11,
              ),
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}
