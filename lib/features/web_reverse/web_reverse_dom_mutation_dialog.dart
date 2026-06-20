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
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import '../../shared/util/date_time_format.dart';
import '../../shared/util/timer_safety.dart';
import 'web_reverse_clipboard.dart';
import 'web_reverse_pure_helpers.dart';
import 'web_reverse_session_controller.dart';

const String _kInstallScript = r'''
(function(){
  if (window.__OH_DOM_MUT_INSTALLED__) return;
  window.__OH_DOM_MUT_INSTALLED__ = true;
  window.__OH_DOM_MUT_BUF__ = [];
  window.__OH_DOM_MUT_SEQ__ = 0;
  var maxBuf = 5000;
  function describe(node){
    if (!node) return '';
    if (node.nodeType === 1) {
      var n = node.nodeName.toLowerCase();
      var id = node.id ? ('#' + node.id) : '';
      var cls = (node.className && typeof node.className === 'string')
        ? ('.' + node.className.trim().split(/\s+/).slice(0,3).join('.'))
        : '';
      return n + id + cls;
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
    for (var i = 0; i < list.length; i++) {
      var m = list[i];
      var rec = {
        seq: ++window.__OH_DOM_MUT_SEQ__,
        t: t,
        kind: m.type,
        target: describe(m.target)
      };
      if (m.type === 'attributes') {
        rec.attr = m.attributeName;
        try { rec.oldValue = m.oldValue; } catch(e) {}
        try {
          rec.newValue = (m.target && m.target.getAttribute)
            ? m.target.getAttribute(m.attributeName) : null;
        } catch(e) {}
      } else if (m.type === 'characterData') {
        try { rec.oldValue = (m.oldValue||'').slice(0,120); } catch(e) {}
        try { rec.newValue = (m.target.nodeValue||'').slice(0,120); } catch(e) {}
      } else if (m.type === 'childList') {
        rec.added = [];
        rec.removed = [];
        for (var k = 0; k < m.addedNodes.length && k < 8; k++) rec.added.push(describe(m.addedNodes[k]));
        for (var k2 = 0; k2 < m.removedNodes.length && k2 < 8; k2++) rec.removed.push(describe(m.removedNodes[k2]));
      }
      push(rec);
    }
  });
  function start(){
    try {
      obs.observe(document.documentElement || document, {
        attributes: true,
        attributeOldValue: true,
        characterData: true,
        characterDataOldValue: true,
        childList: true,
        subtree: true,
      });
    } catch(e) { /* document not ready yet */ }
  }
  if (document.documentElement) {
    start();
  } else {
    document.addEventListener('DOMContentLoaded', start, { once: true });
  }
  window.__OH_DOM_MUT_STOP__ = function(){
    try { obs.disconnect(); } catch(e) {}
    window.__OH_DOM_MUT_INSTALLED__ = false;
  };
  window.__OH_DOM_MUT_DRAIN__ = function(){
    var b = window.__OH_DOM_MUT_BUF__;
    window.__OH_DOM_MUT_BUF__ = [];
    return b;
  };
})();
''';

Future<void> showWebReverseDomMutationDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) {
  return showAnimatedDialog<void>(
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
  final List<Map<String, Object?>> _records = <Map<String, Object?>>[];
  String _filter = '';
  String _kindFilter = 'all'; // all|attributes|characterData|childList
  static const int _maxLocal = 5000;
  final ScrollController _scroll = ScrollController();
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
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      // 注册到 new document 上 → 刷新后立即生效。
      final reg = await widget.controller.sendRawCdp(
        method: 'Page.addScriptToEvaluateOnNewDocument',
        paramsJson: jsonEncode({'source': _kInstallScript}),
      );
      _scriptIdentifier = reg?['identifier']?.toString();
      // 当前页面立即装一次。
      await widget.controller.sendRawCdp(
        method: 'Runtime.evaluate',
        paramsJson: jsonEncode({
          'expression': _kInstallScript,
          'awaitPromise': false,
        }),
      );
      _drainTimer = startNonOverlappingPeriodicTimer(
        const Duration(milliseconds: 800),
        (_) => _drain(),
      );
      if (mounted) {
        setState(() {
          _recording = true;
          _installing = false;
        });
      }
      if (messenger != null && mounted) {
        OpenHandSnackBar.showSuccessOn(
          context,
          messenger,
          AppLocalizations.of(context)?.webReverseDomMutRecordingStarted ??
              'Recording DOM mutations',
        );
      }
    } catch (e, st) {
      silentLog('web_reverse_dom_mutation', 'install', e, st);
      if (mounted) {
        setState(() {
          _installing = false;
          _recording = false;
        });
      }
      if (messenger != null && mounted) {
        OpenHandSnackBar.showErrorOn(
          context,
          messenger,
          AppLocalizations.of(
                context,
              )?.webReverseDomMutInstallFailed(e.toString()) ??
              'Install failed: $e',
        );
      }
    }
  }

  Future<void> _stop() => _cleanupInstalledScript();

  Future<void> _cleanupInstalledScript({bool notify = true}) async {
    _drainTimer?.cancel();
    _drainTimer = null;
    final scriptIdentifier = _scriptIdentifier;
    _scriptIdentifier = null;
    try {
      if (scriptIdentifier != null) {
        await widget.controller.sendRawCdp(
          method: 'Page.removeScriptToEvaluateOnNewDocument',
          paramsJson: jsonEncode({'identifier': scriptIdentifier}),
          timeout: const Duration(seconds: 3),
        );
      }
      await widget.controller.sendRawCdp(
        method: 'Runtime.evaluate',
        paramsJson: jsonEncode({
          'expression':
              'window.__OH_DOM_MUT_STOP__ && window.__OH_DOM_MUT_STOP__()',
        }),
        timeout: const Duration(seconds: 3),
      );
    } catch (e, st) {
      silentLog('web_reverse_dom_mutation', 'stop', e, st);
    }
    if (notify && mounted) {
      setState(() {
        _recording = false;
        _installing = false;
      });
    }
  }

  Future<void> _drain() async {
    try {
      final r = await widget.controller.sendRawCdp(
        method: 'Runtime.evaluate',
        paramsJson: jsonEncode({
          'expression':
              '(window.__OH_DOM_MUT_DRAIN__ && JSON.stringify(window.__OH_DOM_MUT_DRAIN__())) || "[]"',
          'returnByValue': true,
        }),
      );
      final v = cdpStringResultValue(r);
      if (v == null) return;
      final list = jsonDecode(v);
      if (list is! List) return;
      bool dirty = false;
      for (final item in list) {
        if (item is Map) {
          _records.add(Map<String, Object?>.from(item));
          dirty = true;
        }
      }
      while (_records.length > _maxLocal) {
        _records.removeAt(0);
      }
      if (dirty && mounted) {
        setState(() {});
        if (_autoFollow && _scroll.hasClients) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scroll.hasClients) {
              _scroll.jumpTo(_scroll.position.maxScrollExtent);
            }
          });
        }
      }
    } catch (e, st) {
      silentLog('web_reverse_dom_mutation', 'drain', e, st);
    }
  }

  Future<void> _exportJson() async {
    final loc = AppLocalizations.of(context);
    final copied = await setWebReverseClipboardText(
      const JsonEncoder.withIndent('  ').convert(_records),
    );
    if (!mounted) return;
    final m = ScaffoldMessenger.maybeOf(context);
    if (m != null) {
      OpenHandSnackBar.showSuccessOn(
        context,
        m,
        webReverseClipboardSnackMessage(
          isZh: Localizations.localeOf(context).languageCode.startsWith('zh'),
          base:
              loc?.webReverseDomMutCopiedRecords(_records.length) ??
              'Copied ${_records.length} records',
          result: copied,
        ),
      );
    }
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

    return Dialog(
      backgroundColor: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1020, maxHeight: 760),
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
                          loc?.webReverseDomMutTitle ?? 'DOM Mutation Recorder',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          loc?.webReverseDomMutSubtitle ??
                              'Injects MutationObserver → live timeline',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: loc?.webReverseDomMutExportJson ?? 'Export JSON',
                    onPressed: _records.isEmpty ? null : _exportJson,
                    icon: const Icon(Icons.upload_rounded),
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
                        : () => setState(_records.clear),
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
                    label: Text(
                      loc?.webReverseDomMutAutoFollow ?? 'Auto-follow',
                    ),
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
                            : (loc?.webReverseDomMutPressStart ??
                                  'Press Start'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final r = filtered[i];
                        return _MutRow(rec: r);
                      },
                    ),
            ),
            Divider(height: 1, color: cs.outlineVariant),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OpenHandDialogActionButton.secondary(
                    label: loc?.webReverseDomMutClose ?? 'Close',
                    onPressed: () async {
                      if (_recording) await _stop();
                      if (context.mounted) Navigator.of(context).pop();
                    },
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
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
          SizedBox(
            width: 92,
            child: Text(
              kind,
              style: TextStyle(
                fontFamily: 'monospace',
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
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
          Expanded(
            child: SelectableText(
              detail,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}
