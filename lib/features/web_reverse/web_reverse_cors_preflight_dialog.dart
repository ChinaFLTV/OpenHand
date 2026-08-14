/// CORS 预检（OPTIONS）测试面板。
///
/// 输入目标 URL、实际请求方法、自定义请求头列表，在页面上下文里发起一次
/// preflight：method=OPTIONS + Access-Control-Request-Method +
/// Access-Control-Request-Headers，回填响应头并给出 pass/fail 诊断。
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/motion_durations.dart';
import '../../shared/ui/openhand_busy_indicators.dart';
import '../../shared/ui/openhand_inline_notice.dart';
import '../../shared/ui/openhand_reveal_switcher.dart';
import '../../shared/ui/openhand_spacing.dart';
import '../../shared/ui/openhand_typography.dart';
import '../../shared/util/input_value_parsing.dart';
import 'web_reverse_clipboard.dart';
import 'web_reverse_dialog_utils.dart';
import 'web_reverse_pure_helpers.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseCorsPreflightDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) {
  return webReverseToolDialogs.show<void>(
    context: context,
    builder: (_) => _CorsDialog(controller: controller),
  );
}

/// 错误详情的字号。
const double _kCorsErrorFontSize = 12;

class _CorsDialog extends StatefulWidget {
  const _CorsDialog({required this.controller});
  final WebReverseSessionController controller;
  @override
  State<_CorsDialog> createState() => _CorsDialogState();
}

class _CorsDialogState extends State<_CorsDialog> {
  final _urlCtl = TextEditingController(text: 'https://example.com/api');
  final _methodCtl = TextEditingController(text: 'POST');
  final _headersCtl = TextEditingController(
    text: 'Content-Type: application/json\nAuthorization: Bearer xxx',
  );
  final _originCtl = TextEditingController();
  bool _withCredentials = false;
  bool _busy = false;
  Map<String, Object?>? _result;
  String? _error;

  @override
  void dispose() {
    _urlCtl.dispose();
    _methodCtl.dispose();
    _headersCtl.dispose();
    _originCtl.dispose();
    super.dispose();
  }

  List<String> _requestedHeaderNames() {
    final out = <String>[];
    for (final raw in _headersCtl.text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final idx = line.indexOf(':');
      if (idx <= 0) continue;
      out.add(line.substring(0, idx).trim().toLowerCase());
    }
    return out;
  }

  Future<void> _run() async {
    final loc = AppLocalizations.of(context);
    final url = _urlCtl.text.trim();
    if (url.isEmpty) {
      setState(() {
        _error = loc?.webReverseCorsUrlRequired ?? 'URL required';
      });
      return;
    }
    final method = _methodCtl.text.trim().toUpperCase();
    final headerNames = _requestedHeaderNames();
    final originOverride = _originCtl.text.trim();
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    final js =
        '''
(async () => {
  try {
    const url = ${jsonEncode(url)};
    const method = ${jsonEncode(method)};
    const headerList = ${jsonEncode(headerNames)};
    const credentials = ${_withCredentials ? "'include'" : "'omit'"};
    const reqHeaders = { 'Access-Control-Request-Method': method };
    if (headerList.length) {
      reqHeaders['Access-Control-Request-Headers'] = headerList.join(', ');
    }
    const r = await fetch(url, {
      method: 'OPTIONS',
      mode: 'cors',
      credentials,
      headers: reqHeaders,
    });
    const respHeaders = {};
    r.headers.forEach((v, k) => { respHeaders[k.toLowerCase()] = v; });
    return JSON.stringify({
      ok: true,
      status: r.status,
      statusText: r.statusText,
      respHeaders,
      origin: location.origin,
    });
  } catch (err) {
    return JSON.stringify({ ok: false, error: String(err), origin: location.origin });
  }
})()
''';
    try {
      final r = await widget.controller.evaluateJavaScript(
        js,
        awaitPromise: true,
      );
      final res = cdpJsonMapStringResultValue(r);
      if (res == null) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = loc?.webReverseCorsBadEval ?? 'Bad eval result';
        });
        return;
      }
      if (originOverride.isNotEmpty) {
        res['origin'] = originOverride;
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _result = res;
      });
    } catch (err, st) {
      silentLog('web_reverse_cors_preflight_dialog', '执行 CORS 预检', err, st);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$err';
      });
    }
  }

  List<_Diagnostic> _diagnose(AppLocalizations? loc) {
    final res = _result;
    if (res == null || res['ok'] != true) return const [];
    final hdr = stringKeyedMapFromValue(res['respHeaders']);
    final origin = '${res['origin'] ?? ''}';
    final method = _methodCtl.text.trim().toUpperCase();
    final names = _requestedHeaderNames();
    final out = <_Diagnostic>[];
    final allowOrigin = '${hdr['access-control-allow-origin'] ?? ''}';
    out.add(
      _Diagnostic(
        label: 'Access-Control-Allow-Origin',
        value: allowOrigin,
        pass: allowOrigin == '*' || allowOrigin == origin,
        hint: allowOrigin.isEmpty
            ? (loc?.webReverseCorsMissing ?? 'missing')
            : (loc?.webReverseCorsMatchOrigin ?? 'matches current origin'),
      ),
    );
    final allowMethods = splitTrimmedNonEmpty(
      '${hdr['access-control-allow-methods'] ?? ''}',
    ).map((s) => s.toUpperCase()).toList(growable: false);
    out.add(
      _Diagnostic(
        label: 'Access-Control-Allow-Methods',
        value: '${hdr['access-control-allow-methods'] ?? ''}',
        pass: allowMethods.contains(method) || allowMethods.contains('*'),
        hint: loc?.webReverseCorsMustInclude(method) ?? 'must include $method',
      ),
    );
    final allowHeaders = splitTrimmedNonEmpty(
      '${hdr['access-control-allow-headers'] ?? ''}',
    ).map((s) => s.toLowerCase()).toList(growable: false);
    final missing = names
        .where((n) => !allowHeaders.contains(n) && !allowHeaders.contains('*'))
        .toList();
    out.add(
      _Diagnostic(
        label: 'Access-Control-Allow-Headers',
        value: '${hdr['access-control-allow-headers'] ?? ''}',
        pass: missing.isEmpty,
        hint: missing.isEmpty
            ? (loc?.webReverseCorsAllHeadersAllowed ??
                  'all requested headers allowed')
            : (loc?.webReverseCorsMissingHeaders(missing.join(', ')) ??
                  'missing: ${missing.join(', ')}'),
      ),
    );
    if (_withCredentials) {
      final allowCreds = '${hdr['access-control-allow-credentials'] ?? ''}';
      out.add(
        _Diagnostic(
          label: 'Access-Control-Allow-Credentials',
          value: allowCreds,
          pass: allowCreds.toLowerCase() == 'true' && allowOrigin != '*',
          hint:
              loc?.webReverseCorsCredsRule ??
              'must be true and Allow-Origin must not be *',
        ),
      );
    }
    final maxAge = '${hdr['access-control-max-age'] ?? ''}';
    if (maxAge.isNotEmpty) {
      out.add(
        _Diagnostic(
          label: 'Access-Control-Max-Age',
          value: maxAge,
          pass: true,
          hint: loc?.webReverseCorsCacheSeconds ?? 'cache seconds',
        ),
      );
    }
    return out;
  }

  Future<void> _copy() async {
    final res = _result;
    if (res == null) return;
    final loc = AppLocalizations.of(context);
    await copyWebReverseTextToClipboard(
      context: context,
      text: prettyPrintJson(res),
      successBase: loc?.webReverseCorsResultCopied ?? 'Result copied',
      logTag: 'web_reverse_cors_preflight_dialog',
      logAction: '复制 CORS 预检结果',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    final res = _result;
    final diags = _diagnose(loc);
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthWide,
      maxHeight: kOpenHandDialogHeightTall,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
            child: Row(
              children: [
                Icon(Icons.shield_moon_rounded, color: cs.primary),
                kOpenHandHGap10,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loc?.webReverseCorsTitle ?? 'CORS Preflight',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        loc?.webReverseCorsSubtitle ??
                            'OPTIONS · diagnose Allow-Origin / Methods / Headers / Credentials',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: res == null ? null : _copy,
                  icon: const Icon(Icons.copy_rounded),
                  tooltip: loc?.webReverseCorsCopyJson ?? 'Copy JSON',
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
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _urlCtl,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: loc?.webReverseCorsTargetUrl ?? 'Target URL',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                kOpenHandGap10,
                Row(
                  children: [
                    SizedBox(
                      width: 140,
                      child: TextField(
                        controller: _methodCtl,
                        decoration: InputDecoration(
                          labelText:
                              loc?.webReverseCorsActualMethod ??
                              'Actual Method',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    kOpenHandHGap10,
                    Expanded(
                      child: TextField(
                        controller: _originCtl,
                        decoration: InputDecoration(
                          labelText:
                              loc?.webReverseCorsOriginOverride ??
                              'Origin override (optional, display only)',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                kOpenHandGap10,
                TextField(
                  controller: _headersCtl,
                  maxLines: 4,
                  style: const TextStyle(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    fontSize: 12,
                  ),
                  decoration: InputDecoration(
                    labelText:
                        loc?.webReverseCorsCustomHeaders ??
                        'Custom headers (one K: V per line; only names sent in preflight)',
                    border: const OutlineInputBorder(),
                  ),
                ),
                kOpenHandGap8,
                Row(
                  children: [
                    Switch(
                      value: _withCredentials,
                      onChanged: (v) => setState(() => _withCredentials = v),
                    ),
                    kOpenHandHGap4,
                    Text('withCredentials', style: theme.textTheme.labelMedium),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _busy ? null : _run,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(
                        loc?.webReverseCorsRunButton ?? 'Run Preflight',
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: OpenHandBusyProgressBar(busy: _busy),
                ),
                OpenHandVerticalRevealSwitcher(
                  duration: kOpenHandInlineErrorRevealDuration,
                  presentKey: ValueKey<String>(_error ?? ''),
                  child: _error == null
                      ? null
                      : Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: cs.errorContainer.withValues(alpha: 0.4),
                              borderRadius: kOpenHandBorderRadius8,
                            ),
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: cs.error,
                                fontSize: _kCorsErrorFontSize,
                              ),
                            ),
                          ),
                        ),
                ),
                if (res != null) ...[
                  kOpenHandGap16,
                  OpenHandVerticalRevealSwitcher(
                    duration: kOpenHandMotion280,
                    child: res['ok'] == true
                        ? const SizedBox.shrink(key: ValueKey('cors-result-ok'))
                        : Container(
                            key: const ValueKey('cors-result-err'),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: cs.errorContainer.withValues(alpha: 0.4),
                              borderRadius: kOpenHandBorderRadius8,
                            ),
                            child: Text(
                              '${res['error'] ?? 'failed'}',
                              style: TextStyle(color: cs.error, fontSize: 12),
                            ),
                          ),
                  ),
                  if (res['ok'] == true) ...[
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: cs.primaryContainer.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(
                              kOpenHandRadius20,
                            ),
                          ),
                          child: Text(
                            'HTTP ${res['status']} ${res['statusText']}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        kOpenHandHGap10,
                        Text(
                          'origin: ${res['origin']}',
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                    kOpenHandGap12,
                    Text(
                      loc?.webReverseCorsDiagnostics ?? 'Diagnostics',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    kOpenHandGap6,
                    for (final d in diags)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHigh,
                          borderRadius: kOpenHandBorderRadius8,
                          border: Border.all(
                            color: d.pass
                                ? cs.primary.withValues(alpha: 0.5)
                                : cs.error.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  d.pass
                                      ? Icons.check_circle_rounded
                                      : Icons.cancel_rounded,
                                  size: 16,
                                  color: d.pass ? cs.primary : cs.error,
                                ),
                                kOpenHandHGap6,
                                Text(
                                  d.label,
                                  style: const TextStyle(
                                    fontFamily: kOpenHandMonospaceFontFamily,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            kOpenHandGap4,
                            SelectableText(
                              d.value.isEmpty ? '—' : d.value,
                              style: const TextStyle(
                                fontFamily: kOpenHandMonospaceFontFamily,
                                fontSize: 11,
                              ),
                            ),
                            kOpenHandGap2,
                            Text(
                              d.hint,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    kOpenHandGap10,
                    Text(
                      loc?.webReverseCorsAllHeaders ?? 'All response headers',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    kOpenHandGap6,
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: kOpenHandBorderRadius8,
                      ),
                      child: SelectableText(
                        ((res['respHeaders'] as Map?) ?? {}).entries
                            .map((e) => '${e.key}: ${e.value}')
                            .join('\n'),
                        style: const TextStyle(
                          fontFamily: kOpenHandMonospaceFontFamily,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
          buildOpenHandDialogFooter(
            primaryLabel: loc?.webReverseCorsClose ?? 'Close',
            onPrimaryPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _Diagnostic {
  _Diagnostic({
    required this.label,
    required this.value,
    required this.pass,
    required this.hint,
  });
  final String label;
  final String value;
  final bool pass;
  final String hint;
}
