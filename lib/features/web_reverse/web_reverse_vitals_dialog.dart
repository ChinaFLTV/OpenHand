/// Web Vitals 报告面板（Lighthouse-lite）。
///
/// 通过在页面里注入 PerformanceObserver 收集真实用户体验指标：
///   - LCP（Largest Contentful Paint）
///   - CLS（Cumulative Layout Shift）
///   - INP（Interaction to Next Paint，取所有事件 95 分位）
///   - FCP（First Contentful Paint）
///   - TTFB（Time To First Byte）
///   - LoadEvent / DOMContentLoaded
///
/// 完全本地化、不依赖 npx lighthouse；适合 staging 验收与逆向场景。
/// 评分阈值参考 web.dev：good / needs-improvement / poor。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import '../../shared/util/timer_safety.dart';
import 'web_reverse_pure_helpers.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseVitalsDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
  required bool isZh,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _VitalsDialog(controller: controller, isZh: isZh),
  );
}

class _VitalsDialog extends StatefulWidget {
  const _VitalsDialog({required this.controller, required this.isZh});
  final WebReverseSessionController controller;
  final bool isZh;
  @override
  State<_VitalsDialog> createState() => _VitalsDialogState();
}

class _MetricBucket {
  _MetricBucket(this.key, this.label, this.unit, this.goodMax, this.poorMin);
  final String key;
  final String label;
  final String unit;
  final double goodMax;
  final double poorMin;
  double? value;
}

class _VitalsDialogState extends State<_VitalsDialog> {
  Timer? _pullTimer;
  bool _bootstrapped = false;
  bool _busy = false;
  String _status = '';

  final List<_MetricBucket> _metrics = [
    _MetricBucket('lcp', 'LCP', 'ms', 2500, 4000),
    _MetricBucket('fcp', 'FCP', 'ms', 1800, 3000),
    _MetricBucket('cls', 'CLS', '', 0.1, 0.25),
    _MetricBucket('inp', 'INP', 'ms', 200, 500),
    _MetricBucket('ttfb', 'TTFB', 'ms', 800, 1800),
    _MetricBucket('dcl', 'DCL', 'ms', 1500, 3000),
    _MetricBucket('load', 'Load', 'ms', 3000, 6000),
  ];

  @override
  void initState() {
    super.initState();
    // 真实采集需要在 page 注入完观察器再轮询，所以延迟一帧避免抢 dialog 首帧。
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _pullTimer?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _status =
          AppLocalizations.of(context)?.webReverseVitalsInstalling ??
          'Installing observers…';
    });
    const installer = '''
(function(){
  if (window.__oh_vitals_installed) return 'ALREADY';
  window.__oh_vitals_installed = true;
  var bag = window.__oh_vitals = {
    lcp: null, fcp: null, cls: 0, inp: 0, ttfb: null, dcl: null, load: null,
    inp_samples: []
  };
  try {
    var nav = performance.getEntriesByType && performance.getEntriesByType('navigation')[0];
    if (nav) {
      bag.ttfb = nav.responseStart - nav.startTime;
      bag.dcl = nav.domContentLoadedEventEnd - nav.startTime;
      bag.load = nav.loadEventEnd ? (nav.loadEventEnd - nav.startTime) : null;
    }
  } catch (_) {}
  function obs(type, cb){
    try {
      var po = new PerformanceObserver(function(list){ list.getEntries().forEach(cb); });
      po.observe({ type: type, buffered: true });
    } catch (_) {}
  }
  obs('largest-contentful-paint', function(e){ bag.lcp = e.startTime; });
  obs('paint', function(e){ if (e.name === 'first-contentful-paint') bag.fcp = e.startTime; });
  obs('layout-shift', function(e){ if (!e.hadRecentInput) bag.cls += e.value; });
  obs('event', function(e){
    if (e.duration > 16) {
      bag.inp_samples.push(e.duration);
      if (bag.inp_samples.length > 200) bag.inp_samples.shift();
      var s = bag.inp_samples.slice().sort(function(a,b){return a-b;});
      bag.inp = s[Math.floor(s.length * 0.95)] || 0;
    }
  });
  return 'OK';
})()
''';
    try {
      final res = await widget.controller.sendRawCdp(
        method: 'Runtime.evaluate',
        paramsJson: jsonEncode({
          'expression': installer,
          'returnByValue': true,
          'awaitPromise': false,
        }),
      );
      if ((res?['error']) != null) {
        if (mounted) {
          setState(() => _status = 'Runtime.evaluate · ${res!['error']}');
        }
      } else {
        _bootstrapped = true;
        if (mounted) setState(() => _status = '');
      }
    } catch (e, st) {
      silentLog('web_reverse_vitals_dialog', 'bootstrap', e, st);
      if (mounted) setState(() => _status = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    _pullTimer?.cancel();
    _pullTimer = startNonOverlappingPeriodicTimer(
      const Duration(seconds: 1),
      (_) => _pull(),
    );
    _pull();
  }

  Future<void> _pull() async {
    if (!mounted || !_bootstrapped) return;
    try {
      final res = await widget.controller.sendRawCdp(
        method: 'Runtime.evaluate',
        paramsJson: jsonEncode({
          'expression': 'JSON.stringify(window.__oh_vitals || {})',
          'returnByValue': true,
        }),
      );
      final value = cdpStringResultValue(res);
      if (value == null) return;
      final parsed = jsonDecode(value);
      if (parsed is! Map) return;
      if (!mounted) return;
      setState(() {
        for (final m in _metrics) {
          final v = parsed[m.key];
          if (v is num) m.value = v.toDouble();
        }
      });
    } catch (e, st) {
      silentLog('web_reverse_vitals_dialog', 'pull', e, st);
    }
  }

  Future<void> _reset() async {
    setState(() {
      _busy = true;
      _status =
          AppLocalizations.of(context)?.webReverseVitalsResetting ??
          'Resetting…';
    });
    try {
      await widget.controller.sendRawCdp(
        method: 'Runtime.evaluate',
        paramsJson: jsonEncode({
          'expression':
              'delete window.__oh_vitals; delete window.__oh_vitals_installed;',
        }),
      );
      for (final m in _metrics) {
        m.value = null;
      }
      _bootstrapped = false;
      await _bootstrap();
    } catch (e, st) {
      silentLog('web_reverse_vitals_dialog', 'reset', e, st);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyReport() async {
    final report = <String, Object?>{
      'collected_at': DateTime.now().toIso8601String(),
      'metrics': {
        for (final m in _metrics)
          m.key: {'value': m.value, 'unit': m.unit, 'rating': _ratingOf(m)},
      },
    };
    try {
      await Clipboard.setData(
        ClipboardData(text: const JsonEncoder.withIndent('  ').convert(report)),
      );
      if (mounted) {
        final m = ScaffoldMessenger.maybeOf(context);
        if (m != null) {
          OpenHandSnackBar.showSuccessOn(
            context,
            m,
            AppLocalizations.of(context)?.webReverseVitalsReportCopied ??
                'Report JSON copied',
          );
        }
      }
    } catch (e, st) {
      silentLog('web_reverse_vitals_dialog', 'copy', e, st);
    }
  }

  String _ratingOf(_MetricBucket m) {
    final v = m.value;
    if (v == null) return 'unknown';
    if (v <= m.goodMax) return 'good';
    if (v >= m.poorMin) return 'poor';
    return 'needs-improvement';
  }

  Color _colorOf(String rating, ColorScheme cs) {
    switch (rating) {
      case 'good':
        return const Color(0xFF12B886);
      case 'needs-improvement':
        return const Color(0xFFF59F00);
      case 'poor':
        return cs.error;
    }
    return cs.outline;
  }

  String _fmt(_MetricBucket m) {
    final v = m.value;
    if (v == null) return '—';
    if (m.unit == 'ms') {
      if (v >= 1000) return '${(v / 1000).toStringAsFixed(2)} s';
      return '${v.toStringAsFixed(0)} ms';
    }
    return v.toStringAsFixed(3);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: 720,
      maxHeight: 680,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.speed_rounded,
            title: loc?.webReverseVitalsTitle ?? 'Web Vitals',
            subtitle:
                loc?.webReverseVitalsSubtitle ??
                'PerformanceObserver · LCP / CLS / INP / FCP / TTFB · live',
            closeTooltip: loc?.webReverseVitalsClose ?? 'Close',
            actions: [
              IconButton(
                tooltip: loc?.webReverseVitalsCopyJson ?? 'Copy JSON',
                onPressed: _copyReport,
                icon: const Icon(Icons.copy_rounded),
              ),
              IconButton(
                tooltip: loc?.webReverseVitalsReset ?? 'Reset',
                onPressed: _busy ? null : _reset,
                icon: const Icon(Icons.restart_alt_rounded),
              ),
            ],
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              children: [
                for (final m in _metrics) _metricCard(m, cs, tt),
                if (_status.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(_status, style: tt.bodySmall?.copyWith(color: cs.error)),
                ],
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    loc?.webReverseVitalsThresholdsHint ??
                        'Thresholds per web.dev. After reset, reload or interact to retrigger LCP / event samples.',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          buildOpenHandDialogFooter(
            primaryLabel: loc?.webReverseVitalsClose ?? 'Close',
            onPrimaryPressed: () => Navigator.of(context).pop(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
            leading: _busy
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _metricCard(_MetricBucket m, ColorScheme cs, TextTheme tt) {
    final rating = _ratingOf(m);
    final color = _colorOf(rating, cs);
    final v = m.value;
    double pct = 0;
    if (v != null) {
      // 进度条直观对齐 good 阈值；超出就 1.0 满格 + 颜色变红。
      pct = (v / (m.poorMin * 1.2)).clamp(0.0, 1.0).toDouble();
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                m.label,
                style: tt.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  rating,
                  style: tt.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                _fmt(m),
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 5,
              backgroundColor: cs.surfaceContainerLowest,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}
