/// JWT 自动续期面板。
///
/// 一键扫描页面所有 cookies/localStorage/sessionStorage 中形如 `xxx.yyy.zzz`
/// 的 JWT，解析 `exp` 字段并展示剩余时间。可配置一段刷新 JS 表达式
/// (例如 `await fetch('/api/refresh',{method:'POST'})` )，启用自动续期后
/// 每隔 N 秒重新扫描；任何 token 的剩余时间小于阈值就执行刷新脚本。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import 'web_reverse_session_controller.dart';

class _JwtSample {
  _JwtSample({
    required this.source,
    required this.key,
    required this.value,
    required this.exp,
    required this.iat,
    required this.iss,
    required this.sub,
  });
  final String source;
  final String key;
  final String value;
  final DateTime? exp;
  final DateTime? iat;
  final String? iss;
  final String? sub;

  Duration? remaining(DateTime now) =>
      exp == null ? null : exp!.difference(now);
}

class _RefreshLog {
  _RefreshLog({required this.at, required this.ok, required this.detail});
  final DateTime at;
  final bool ok;
  final String detail;
}

Future<void> showWebReverseJwtRefreshDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
  required bool isZh,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _JwtRefreshDialog(controller: controller, isZh: isZh),
  );
}

class _JwtRefreshDialog extends StatefulWidget {
  const _JwtRefreshDialog({required this.controller, required this.isZh});
  final WebReverseSessionController controller;
  // ignore: unused_field
  final bool isZh;
  @override
  State<_JwtRefreshDialog> createState() => _JwtRefreshDialogState();
}

class _JwtRefreshDialogState extends State<_JwtRefreshDialog> {
  final TextEditingController _refreshExpr = TextEditingController(
    text:
        "await (await fetch('/api/refresh',{method:'POST',credentials:'include'})).text()",
  );
  final TextEditingController _intervalCtrl =
      TextEditingController(text: '30');
  final TextEditingController _thresholdCtrl =
      TextEditingController(text: '60');

  List<_JwtSample> _samples = const <_JwtSample>[];
  bool _busy = false;
  bool _autoRefresh = false;
  Timer? _timer;
  final List<_RefreshLog> _logs = <_RefreshLog>[];
  DateTime _now = DateTime.now();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ticker?.cancel();
    _refreshExpr.dispose();
    _intervalCtrl.dispose();
    _thresholdCtrl.dispose();
    super.dispose();
  }

  Future<List<_JwtSample>> _scan() async {
    const js = r"""
(function(){
  function decode(seg){
    try {
      var s = seg.replace(/-/g,'+').replace(/_/g,'/');
      while (s.length % 4) s += '=';
      var raw = atob(s);
      try { raw = decodeURIComponent(escape(raw)); } catch(_) {}
      return JSON.parse(raw);
    } catch(_) { return null; }
  }
  function classify(v){
    if (typeof v !== 'string') return null;
    var m = v.match(/[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{0,}/);
    if (!m) return null;
    var parts = m[0].split('.');
    if (parts.length < 2) return null;
    var p = decode(parts[1]);
    if (!p) return null;
    return {raw: m[0], exp: p.exp || null, iat: p.iat || null, iss: p.iss || null, sub: p.sub || null};
  }
  var out = [];
  document.cookie.split(/;\s*/).forEach(function(c){
    var eq = c.indexOf('=');
    if (eq < 0) return;
    var k = c.slice(0, eq);
    var v = decodeURIComponent(c.slice(eq+1) || '');
    var info = classify(v);
    if (info) out.push({source:'cookie', key:k, value:info.raw, exp:info.exp, iat:info.iat, iss:info.iss, sub:info.sub});
  });
  for (var i=0; i<localStorage.length; i++){
    var k = localStorage.key(i);
    var v = localStorage.getItem(k);
    var info = classify(v||'');
    if (info) out.push({source:'localStorage', key:k, value:info.raw, exp:info.exp, iat:info.iat, iss:info.iss, sub:info.sub});
  }
  for (var i=0; i<sessionStorage.length; i++){
    var k = sessionStorage.key(i);
    var v = sessionStorage.getItem(k);
    var info = classify(v||'');
    if (info) out.push({source:'sessionStorage', key:k, value:info.raw, exp:info.exp, iat:info.iat, iss:info.iss, sub:info.sub});
  }
  return JSON.stringify(out);
})()
""";
    final r = await widget.controller.sendRawCdp(
      method: 'Runtime.evaluate',
      paramsJson: jsonEncode({
        'expression': js,
        'returnByValue': true,
        'awaitPromise': false,
        'userGesture': true,
      }),
      useSession: true,
    );
    if (r == null) return const <_JwtSample>[];
    final result = r['result'];
    if (result is! Map) return const <_JwtSample>[];
    final value = result['value'];
    if (value is! String) return const <_JwtSample>[];
    try {
      final list = jsonDecode(value);
      if (list is! List) return const <_JwtSample>[];
      return list
          .whereType<Map>()
          .map((e) => _JwtSample(
                source: '${e['source'] ?? ''}',
                key: '${e['key'] ?? ''}',
                value: '${e['value'] ?? ''}',
                exp: e['exp'] is int
                    ? DateTime.fromMillisecondsSinceEpoch(
                        (e['exp'] as int) * 1000)
                    : null,
                iat: e['iat'] is int
                    ? DateTime.fromMillisecondsSinceEpoch(
                        (e['iat'] as int) * 1000)
                    : null,
                iss: e['iss']?.toString(),
                sub: e['sub']?.toString(),
              ))
          .toList();
    } catch (e, st) {
      silentLog('web_reverse_jwt', 'parse', e, st);
      return const <_JwtSample>[];
    }
  }

  Future<void> _doScan() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      _samples = await _scan();
    } catch (e, st) {
      silentLog('web_reverse_jwt', 'scan', e, st);
      if (messenger != null && mounted) {
        OpenHandSnackBar.showErrorOn(context, messenger, '$e');
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<bool> _runRefresh() async {
    final expr = _refreshExpr.text.trim();
    if (expr.isEmpty) return false;
    final r = await widget.controller.sendRawCdp(
      method: 'Runtime.evaluate',
      paramsJson: jsonEncode({
        'expression': '(async()=>{ $expr })()',
        'awaitPromise': true,
        'returnByValue': true,
        'userGesture': true,
      }),
      useSession: true,
    );
    if (r == null) {
      _logs.insert(0, _RefreshLog(at: DateTime.now(), ok: false, detail: 'no response'));
      return false;
    }
    if (r['error'] != null) {
      _logs.insert(0, _RefreshLog(at: DateTime.now(), ok: false, detail: '${r['error']}'));
      return false;
    }
    final excp = r['exceptionDetails'];
    if (excp is Map) {
      _logs.insert(0, _RefreshLog(
        at: DateTime.now(),
        ok: false,
        detail: '${excp['text'] ?? excp}',
      ));
      return false;
    }
    final result = r['result'];
    final value = result is Map ? result['value'] : null;
    _logs.insert(0, _RefreshLog(
      at: DateTime.now(),
      ok: true,
      detail: value?.toString() ?? 'ok',
    ));
    return true;
  }

  void _toggleAuto(bool v) {
    _timer?.cancel();
    setState(() => _autoRefresh = v);
    if (!v) return;
    final interval = int.tryParse(_intervalCtrl.text) ?? 30;
    final threshold = int.tryParse(_thresholdCtrl.text) ?? 60;
    _timer = Timer.periodic(Duration(seconds: interval), (_) async {
      await _doScan();
      final now = DateTime.now();
      final needsRefresh = _samples.any((s) {
        final rem = s.remaining(now);
        return rem != null && rem.inSeconds <= threshold;
      });
      if (needsRefresh) {
        await _runRefresh();
        await _doScan();
        if (mounted) setState(() {});
      }
    });
  }

  String _formatRemaining(Duration? d) {
    if (d == null) return '—';
    if (d.isNegative) return 'expired';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inSeconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    final threshold = int.tryParse(_thresholdCtrl.text) ?? 60;

    return Dialog(
      backgroundColor: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 760),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
              child: Row(
                children: [
                  Icon(Icons.vpn_key_rounded, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loc?.webReverseJwtTitle ?? 'JWT Auto Refresh',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          loc?.webReverseJwtSubtitle ??
                              'Scan JWTs in cookies/storage, run refresh JS when near exp',
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
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _busy ? null : _doScan,
                          icon: const Icon(Icons.radar_rounded),
                          label: Text(loc?.webReverseJwtScanNow ?? 'Scan now'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _busy ? null : () async {
                            final ok = await _runRefresh();
                            if (ok) await _doScan();
                            if (mounted) setState(() {});
                          },
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(
                              loc?.webReverseJwtRefreshNow ?? 'Refresh now'),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(value: _autoRefresh, onChanged: _toggleAuto),
                            Text(loc?.webReverseJwtAuto ?? 'Auto'),
                          ],
                        ),
                        SizedBox(
                          width: 100,
                          child: TextField(
                            controller: _intervalCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: loc?.webReverseJwtIntervalSec ??
                                  'Interval(s)',
                              isDense: true,
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 120,
                          child: TextField(
                            controller: _thresholdCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: loc?.webReverseJwtThresholdSec ??
                                  'Threshold(s)',
                              isDense: true,
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _refreshExpr,
                      maxLines: 3,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      decoration: InputDecoration(
                        labelText: loc?.webReverseJwtRefreshExpr ??
                            'Refresh expression (async JS)',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      loc?.webReverseJwtFoundCount(_samples.length) ??
                          'JWTs (${_samples.length})',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    if (_samples.isEmpty)
                      Text(
                        loc?.webReverseJwtNoneFound ?? 'No JWT found',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    for (final s in _samples)
                      _SampleCard(
                        sample: s,
                        now: _now,
                        threshold: threshold,
                        formatRemaining: _formatRemaining,
                      ),
                    if (_logs.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text(
                        loc?.webReverseJwtRefreshLog ?? 'Refresh log',
                        style: theme.textTheme.labelLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      for (final l in _logs.take(20))
                        Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: l.ok ? cs.surfaceContainerHigh : cs.errorContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                l.ok
                                    ? Icons.check_circle_outline_rounded
                                    : Icons.error_outline_rounded,
                                size: 14,
                                color: l.ok ? cs.primary : cs.onErrorContainer,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _hms(l.at),
                                style: const TextStyle(
                                    fontFamily: 'monospace', fontSize: 11),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: SelectableText(
                                  l.detail,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    color: l.ok ? cs.onSurface : cs.onErrorContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OpenHandDialogActionButton.secondary(
                    label: loc?.webReverseJwtClose ?? 'Close',
                    onPressed: () {
                      _timer?.cancel();
                      Navigator.of(context).pop();
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

  String _hms(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}

class _SampleCard extends StatelessWidget {
  const _SampleCard({
    required this.sample,
    required this.now,
    required this.threshold,
    required this.formatRemaining,
  });
  final _JwtSample sample;
  final DateTime now;
  final int threshold;
  final String Function(Duration?) formatRemaining;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final rem = sample.remaining(now);
    final urgent = rem != null && rem.inSeconds <= threshold;
    final color = urgent
        ? cs.errorContainer
        : (rem != null && rem.inSeconds > 0
            ? cs.surfaceContainerHigh
            : cs.surfaceContainerHighest);
    return Card(
      color: color,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    sample.source,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 11),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    sample.key,
                    style: theme.textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  formatRemaining(rem),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontFamily: 'monospace',
                    color: urgent ? cs.error : cs.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SelectableText(
              sample.value,
              maxLines: 2,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: cs.onSurfaceVariant,
              ),
            ),
            if (sample.exp != null || sample.iss != null || sample.sub != null) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 2,
                children: [
                  if (sample.exp != null)
                    _kv('exp', sample.exp!.toIso8601String(), theme),
                  if (sample.iat != null)
                    _kv('iat', sample.iat!.toIso8601String(), theme),
                  if (sample.iss != null) _kv('iss', sample.iss!, theme),
                  if (sample.sub != null) _kv('sub', sample.sub!, theme),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v, ThemeData theme) {
    return Text('$k=$v',
        style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 10,
            color: theme.colorScheme.onSurfaceVariant));
  }
}
