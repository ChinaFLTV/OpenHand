/// JWT 自动续期面板。
///
/// 一键扫描页面所有 cookies/localStorage/sessionStorage 中形如 `xxx.yyy.zzz`
/// 的 JWT，解析 `exp` 字段并展示剩余时间。可配置一段刷新 JS 表达式
/// (例如 `await fetch('/api/refresh',{method:'POST'})` )，启用自动续期后
/// 每隔 N 秒重新扫描；任何 token 的剩余时间小于阈值就执行刷新脚本。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import '../../shared/ui/openhand_spacing.dart';
import '../../shared/ui/openhand_typography.dart';
import '../../shared/util/byte_size_format.dart';
import '../../shared/util/date_time_format.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/text_clip.dart';
import '../../shared/util/timer_safety.dart';
import 'web_reverse_dialog_utils.dart';
import 'web_reverse_pure_helpers.dart';
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

  Duration? remaining(DateTime now) => exp?.difference(now);
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
}) {
  return webReverseToolDialogs.show<void>(
    context: context,
    builder: (_) => _JwtRefreshDialog(controller: controller),
  );
}

class _JwtRefreshDialog extends StatefulWidget {
  const _JwtRefreshDialog({required this.controller});
  final WebReverseSessionController controller;
  @override
  State<_JwtRefreshDialog> createState() => _JwtRefreshDialogState();
}

class _JwtRefreshDialogState extends State<_JwtRefreshDialog> {
  static const int _defaultAutoIntervalSeconds = 30;
  static const int _minAutoIntervalSeconds = 5;
  static const int _maxAutoIntervalSeconds = 3600;
  static const int _defaultRefreshThresholdSeconds = 60;
  static const int _minRefreshThresholdSeconds = 0;
  static const int _maxRefreshThresholdSeconds = 86400;
  static const int _maxRefreshLogs = 40;
  static const int _maxJwtSamples = 128;
  static const int _maxJwtScanValueChars = 256 * kBytesPerKiB;
  static const int _maxJwtTokenChars = 32 * kBytesPerKiB;
  static const int _maxJwtKeyChars = 512;
  static const int _maxJwtClaimChars = kBytesPerKiB;
  static const int _maxJwtSnapshotChars = 5 * kBytesPerMiB;
  static const int _maxRefreshLogDetailChars = 4 * kBytesPerKiB;

  final TextEditingController _refreshExpr = TextEditingController(
    text:
        "await (await fetch('/api/refresh',{method:'POST',credentials:'include'})).text()",
  );
  final TextEditingController _intervalCtrl = TextEditingController(
    text: '$_defaultAutoIntervalSeconds',
  );
  final TextEditingController _thresholdCtrl = TextEditingController(
    text: '$_defaultRefreshThresholdSeconds',
  );

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
    _ticker = startSafePeriodicTimer(const Duration(seconds: 1), (_) {
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

  String? _boundedOptionalJwtClaim(Object? value) {
    final claim = optionalStringFromValue(value);
    return claim == null
        ? null
        : clipText(claim, _maxJwtClaimChars, suffix: '');
  }

  Future<List<_JwtSample>> _scan() async {
    final js =
        r"""
(function(){
  var MAX_ITEMS = __MAX_ITEMS__;
  var MAX_SCAN_CHARS = __MAX_SCAN_CHARS__;
  var MAX_TOKEN_CHARS = __MAX_TOKEN_CHARS__;
  var MAX_KEY_CHARS = __MAX_KEY_CHARS__;
  var MAX_CLAIM_CHARS = __MAX_CLAIM_CHARS__;
  function text(v, max){
    if (v === null || v === undefined) return null;
    return String(v).slice(0, max);
  }
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
    if (v.length > MAX_SCAN_CHARS) return null;
    var m = v.match(/[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{0,}/);
    if (!m) return null;
    if (m[0].length > MAX_TOKEN_CHARS) return null;
    var parts = m[0].split('.');
    if (parts.length < 2) return null;
    var p = decode(parts[1]);
    if (!p) return null;
    return {raw: m[0], exp: p.exp || null, iat: p.iat || null, iss: text(p.iss, MAX_CLAIM_CHARS), sub: text(p.sub, MAX_CLAIM_CHARS)};
  }
  var out = [];
  function push(source, key, info){
    if (!info || out.length >= MAX_ITEMS) return;
    out.push({source:source, key:text(key, MAX_KEY_CHARS) || '', value:info.raw, exp:info.exp, iat:info.iat, iss:info.iss, sub:info.sub});
  }
  try {
    document.cookie.split(/;\s*/).forEach(function(c){
      var eq = c.indexOf('=');
      if (eq < 0) return;
      var k = c.slice(0, eq);
      var v = c.slice(eq+1) || '';
      try { v = decodeURIComponent(v); } catch (_) {}
      push('cookie', k, classify(v));
    });
  } catch (_) {}
  try {
    for (var i=0; i<localStorage.length && out.length<MAX_ITEMS; i++){
      var k = localStorage.key(i);
      var v = localStorage.getItem(k);
      push('localStorage', k, classify(v||''));
    }
  } catch (_) {}
  try {
    for (var i=0; i<sessionStorage.length && out.length<MAX_ITEMS; i++){
      var k = sessionStorage.key(i);
      var v = sessionStorage.getItem(k);
      push('sessionStorage', k, classify(v||''));
    }
  } catch (_) {}
  return JSON.stringify(out);
})()
"""
            .replaceAll('__MAX_ITEMS__', '$_maxJwtSamples')
            .replaceAll('__MAX_SCAN_CHARS__', '$_maxJwtScanValueChars')
            .replaceAll('__MAX_TOKEN_CHARS__', '$_maxJwtTokenChars')
            .replaceAll('__MAX_KEY_CHARS__', '$_maxJwtKeyChars')
            .replaceAll('__MAX_CLAIM_CHARS__', '$_maxJwtClaimChars');
    final r = await widget.controller.evaluateJavaScript(js, userGesture: true);
    if (r == null) return const <_JwtSample>[];
    final value = cdpStringResultValue(r);
    if (value == null) return const <_JwtSample>[];
    if (value.length > _maxJwtSnapshotChars) {
      return const <_JwtSample>[];
    }
    try {
      final entries = decodeStringKeyedJsonMapList(value);
      if (entries == null) return const <_JwtSample>[];
      return entries
          .take(_maxJwtSamples)
          .map(
            (entry) => _JwtSample(
              source: clipText(
                stringFromValue(entry['source']),
                32,
                suffix: '',
              ),
              key: clipText(
                stringFromValue(entry['key']),
                _maxJwtKeyChars,
                suffix: '',
              ),
              value: clipText(
                stringFromValue(entry['value']),
                _maxJwtTokenChars,
                suffix: '',
              ),
              exp: jwtNumericDateFromValue(entry['exp']),
              iat: jwtNumericDateFromValue(entry['iat']),
              iss: _boundedOptionalJwtClaim(entry['iss']),
              sub: _boundedOptionalJwtClaim(entry['sub']),
            ),
          )
          .toList(growable: false);
    } catch (e, st) {
      silentLog('web_reverse_jwt', '解析 JWT', e, st);
      return const <_JwtSample>[];
    }
  }

  Future<void> _doScan() async {
    if (!mounted || _busy) return;
    setState(() => _busy = true);
    try {
      _samples = await _scan();
    } catch (e, st) {
      silentLog('web_reverse_jwt', '扫描 JWT', e, st);
      if (mounted) showOpenHandErrorSnack(context, '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<bool> _runRefresh() async {
    final expr = _refreshExpr.text.trim();
    if (expr.isEmpty) return false;
    if (expr.length > WebReverseSessionController.maxDebuggerExpressionChars) {
      _addRefreshLog(ok: false, detail: 'refresh expression exceeds limit');
      return false;
    }
    try {
      final r = await widget.controller.evaluateJavaScript(
        '(async()=>{ $expr })()',
        awaitPromise: true,
        userGesture: true,
      );
      if (r == null) {
        _addRefreshLog(ok: false, detail: 'no response');
        return false;
      }
      if (r['error'] != null) {
        _addRefreshLog(ok: false, detail: '${r['error']}');
        return false;
      }
      final excp = r['exceptionDetails'];
      if (excp is Map) {
        _addRefreshLog(ok: false, detail: '${excp['text'] ?? excp}');
        return false;
      }
      final value = cdpResultValue(r);
      _addRefreshLog(ok: true, detail: value?.toString() ?? 'ok');
      return true;
    } catch (e, st) {
      silentLog('web_reverse_jwt', '刷新 JWT', e, st);
      _addRefreshLog(ok: false, detail: '$e');
      return false;
    }
  }

  void _toggleAuto(bool v) {
    _timer?.cancel();
    _timer = null;
    setState(() => _autoRefresh = v);
    if (!v) return;
    final interval = _autoIntervalSeconds;
    final threshold = _refreshThresholdSeconds;
    _intervalCtrl.text = '$interval';
    _thresholdCtrl.text = '$threshold';
    _timer = startNonOverlappingPeriodicTimer(
      Duration(seconds: interval),
      (timer) async {
        if (!mounted || !_autoRefresh || !identical(_timer, timer)) {
          return;
        }
        await _doScan();
        if (!mounted || !_autoRefresh || !identical(_timer, timer)) {
          return;
        }
        final now = DateTime.now();
        final needsRefresh = _samples.any((s) {
          final rem = s.remaining(now);
          return rem != null && rem.inSeconds <= threshold;
        });
        if (needsRefresh) {
          await _runRefresh();
          if (!mounted || !_autoRefresh || !identical(_timer, timer)) {
            return;
          }
          await _doScan();
          if (mounted && _autoRefresh && identical(_timer, timer)) {
            setState(() {});
          }
        }
      },
      min: const Duration(seconds: _minAutoIntervalSeconds),
      max: const Duration(seconds: _maxAutoIntervalSeconds),
    );
  }

  int get _autoIntervalSeconds => clampedIntFromText(
    _intervalCtrl.text,
    fallback: _defaultAutoIntervalSeconds,
    min: _minAutoIntervalSeconds,
    max: _maxAutoIntervalSeconds,
  );

  int get _refreshThresholdSeconds => clampedIntFromText(
    _thresholdCtrl.text,
    fallback: _defaultRefreshThresholdSeconds,
    min: _minRefreshThresholdSeconds,
    max: _maxRefreshThresholdSeconds,
  );

  void _addRefreshLog({required bool ok, required String detail}) {
    _logs.insert(
      0,
      _RefreshLog(
        at: DateTime.now(),
        ok: ok,
        detail: clipText(detail, _maxRefreshLogDetailChars, suffix: '…'),
      ),
    );
    if (_logs.length > _maxRefreshLogs) {
      _logs.removeRange(_maxRefreshLogs, _logs.length);
    }
  }

  String _formatRemaining(Duration? d) {
    if (d == null) return '—';
    if (d.isNegative) return 'expired';
    return formatCompactDuration(d);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    final threshold = _refreshThresholdSeconds;

    return buildOpenHandToolDialogShell(
      context: context,
      insetPadding: const EdgeInsets.all(24),
      maxWidth: kOpenHandDialogWidthExtraWide,
      maxHeight: kOpenHandDialogHeightTall,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
            child: Row(
              children: [
                Icon(Icons.vpn_key_rounded, color: cs.primary),
                kOpenHandHGap10,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loc?.webReverseJwtTitle ?? 'JWT Auto Refresh',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        loc?.webReverseJwtSubtitle ??
                            'Scan JWTs in cookies/storage, run refresh JS when near exp',
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
                        onPressed: _busy
                            ? null
                            : () async {
                                final ok = await _runRefresh();
                                if (ok) await _doScan();
                                if (mounted) setState(() {});
                              },
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(
                          loc?.webReverseJwtRefreshNow ?? 'Refresh now',
                        ),
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
                            labelText:
                                loc?.webReverseJwtIntervalSec ?? 'Interval(s)',
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
                            labelText:
                                loc?.webReverseJwtThresholdSec ??
                                'Threshold(s)',
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  kOpenHandGap12,
                  TextField(
                    controller: _refreshExpr,
                    maxLength:
                        WebReverseSessionController.maxDebuggerExpressionChars,
                    maxLines: 3,
                    style: const TextStyle(
                      fontFamily: kOpenHandMonospaceFontFamily,
                      fontSize: 12,
                    ),
                    decoration: InputDecoration(
                      labelText:
                          loc?.webReverseJwtRefreshExpr ??
                          'Refresh expression (async JS)',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  kOpenHandGap16,
                  Text(
                    loc?.webReverseJwtFoundCount(_samples.length) ??
                        'JWTs (${_samples.length})',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  kOpenHandGap6,
                  if (_samples.isEmpty)
                    Text(
                      loc?.webReverseJwtNoneFound ?? 'No JWT found',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  for (final s in _samples)
                    _SampleCard(
                      sample: s,
                      now: _now,
                      threshold: threshold,
                      formatRemaining: _formatRemaining,
                    ),
                  if (_logs.isNotEmpty) ...[
                    kOpenHandGap18,
                    Text(
                      loc?.webReverseJwtRefreshLog ?? 'Refresh log',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    kOpenHandGap6,
                    for (final l in _logs.take(20))
                      Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: l.ok
                              ? cs.surfaceContainerHigh
                              : cs.errorContainer,
                          borderRadius: kOpenHandBorderRadius6,
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
                            kOpenHandHGap6,
                            Text(
                              formatHourMinuteSecond(l.at),
                              style: const TextStyle(
                                fontFamily: kOpenHandMonospaceFontFamily,
                                fontSize: 11,
                              ),
                            ),
                            kOpenHandHGap8,
                            Expanded(
                              child: SelectableText(
                                l.detail,
                                style: TextStyle(
                                  fontFamily: kOpenHandMonospaceFontFamily,
                                  fontSize: 11,
                                  color: l.ok
                                      ? cs.onSurface
                                      : cs.onErrorContainer,
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
          buildOpenHandDialogFooter(
            primaryLabel: loc?.webReverseJwtClose ?? 'Close',
            onPrimaryPressed: () {
              _timer?.cancel();
              Navigator.of(context).pop();
            },
            padding: const EdgeInsets.all(12),
          ),
        ],
      ),
    );
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: kOpenHandBorderRadius4,
                  ),
                  child: Text(
                    sample.source,
                    style: const TextStyle(
                      fontFamily: kOpenHandMonospaceFontFamily,
                      fontSize: 11,
                    ),
                  ),
                ),
                kOpenHandHGap6,
                Expanded(
                  child: Text(
                    sample.key,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  formatRemaining(rem),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    color: urgent ? cs.error : cs.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            kOpenHandGap4,
            SelectableText(
              sample.value,
              maxLines: 2,
              style: TextStyle(
                fontFamily: kOpenHandMonospaceFontFamily,
                fontSize: 11,
                color: cs.onSurfaceVariant,
              ),
            ),
            if (sample.exp != null ||
                sample.iss != null ||
                sample.sub != null) ...[
              kOpenHandGap4,
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
    return Text(
      '$k=$v',
      style: TextStyle(
        fontFamily: kOpenHandMonospaceFontFamily,
        fontSize: 10,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
