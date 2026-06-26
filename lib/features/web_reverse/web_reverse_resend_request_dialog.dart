// 报文重放/改包 (Resend·Edit) Dialog
//
// 从 Network 详情面板触发：以一个 [CdpNetworkEntry] 为初始模板，让用户
// 修改 URL / Method / Headers / Body 后默认通过 CDP 在页面上下文 fetch，
// 保留 Dart [HttpClient] 直连模式作为显式备选，结果实时展示状态、响应头、响应体。
//
// 顶部右侧 segmented action 可一键导出为 curl / Python requests / fetch
// 代码并复制到剪贴板，方便贴到外部脚本。
//
// 动画风格：showAnimatedDialog 自带 Q弹进退场；内部状态切换走
// AnimatedSwitcher 220ms + easeOutCubic，遵守 MediaQuery 减动效。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import 'web_reverse_clipboard.dart';
import 'web_reverse_pure_helpers.dart';
import 'web_reverse_select_button.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseResendRequestDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
  required CdpNetworkEntry entry,
  required bool isZh,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _ResendRequestDialog(
      controller: controller,
      initial: entry,
      isZh: isZh,
    ),
  );
}

class _ResendRequestDialog extends StatefulWidget {
  const _ResendRequestDialog({
    required this.controller,
    required this.initial,
    required this.isZh,
  });
  final WebReverseSessionController controller;
  final CdpNetworkEntry initial;
  final bool isZh;

  @override
  State<_ResendRequestDialog> createState() => _ResendRequestDialogState();
}

class _ResendRequestDialogState extends State<_ResendRequestDialog> {
  static const int _kMaxResponseBytes = 2 * 1024 * 1024;
  static const Duration _kRequestTimeout = Duration(seconds: 30);
  static const Duration _kResponseReadIdleTimeout = Duration(seconds: 5);

  static const _kMethods = [
    'GET',
    'POST',
    'PUT',
    'PATCH',
    'DELETE',
    'HEAD',
    'OPTIONS',
  ];

  static const _kBrowserFetchForbiddenHeaders = <String>{
    'accept-charset',
    'accept-encoding',
    'access-control-request-headers',
    'access-control-request-method',
    'connection',
    'content-length',
    'cookie',
    'cookie2',
    'date',
    'dnt',
    'expect',
    'host',
    'keep-alive',
    'origin',
    'referer',
    'te',
    'trailer',
    'transfer-encoding',
    'upgrade',
    'user-agent',
    'via',
  };

  late final TextEditingController _urlCtrl;
  late final TextEditingController _bodyCtrl;
  late String _method;
  final List<_HeaderRow> _headers = <_HeaderRow>[];

  late _ReplayTransport _transport;
  bool _sending = false;
  HttpClient? _activeClient;
  String? _activeBrowserAbortKey;
  int _sendGeneration = 0;
  _ResponseSnapshot? _lastResp;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.initial.url);
    _bodyCtrl = TextEditingController(
      text: widget.initial.requestPostData ?? '',
    );
    _method = _kMethods.contains(widget.initial.method.toUpperCase())
        ? widget.initial.method.toUpperCase()
        : 'GET';
    _transport = widget.controller.isBrowserAlive
        ? _ReplayTransport.browser
        : _ReplayTransport.direct;
    widget.initial.requestHeaders.forEach((k, v) {
      if (k.startsWith(':')) return; // 跳过 HTTP/2 伪头
      _headers.add(
        _HeaderRow(
          name: TextEditingController(text: k),
          value: TextEditingController(text: v),
          enabled: true,
        ),
      );
    });
    if (_headers.isEmpty) _addBlankHeader();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _bodyCtrl.dispose();
    for (final h in _headers) {
      h.name.dispose();
      h.value.dispose();
    }
    _activeClient?.close(force: true);
    super.dispose();
  }

  void _addBlankHeader() {
    setState(() {
      _headers.add(
        _HeaderRow(
          name: TextEditingController(),
          value: TextEditingController(),
          enabled: true,
        ),
      );
    });
  }

  void _removeHeader(int i) {
    setState(() {
      final h = _headers.removeAt(i);
      h.name.dispose();
      h.value.dispose();
      if (_headers.isEmpty) _addBlankHeader();
    });
  }

  Future<void> _send() async {
    final urlText = _urlCtrl.text.trim();
    final loc0 = AppLocalizations.of(context);
    if (urlText.isEmpty) {
      OpenHandSnackBar.showError(
        context,
        loc0?.webReverseResendRequestUrlEmpty ?? 'URL is required',
      );
      return;
    }
    Uri uri;
    try {
      uri = Uri.parse(urlText);
      if (!uri.hasScheme || !(uri.scheme == 'http' || uri.scheme == 'https')) {
        throw const FormatException('only http/https');
      }
    } catch (_) {
      OpenHandSnackBar.showError(
        context,
        loc0?.webReverseResendRequestUrlInvalid ?? 'Invalid URL',
      );
      return;
    }
    final generation = ++_sendGeneration;
    setState(() {
      _sending = true;
      _lastResp = null;
      _lastError = null;
    });
    if (_transport == _ReplayTransport.browser) {
      await _sendViaBrowser(uri, generation);
    } else {
      await _sendViaHttpClient(uri, generation);
    }
  }

  Future<void> _sendViaBrowser(Uri uri, int generation) async {
    if (!widget.controller.isBrowserAlive) {
      if (!mounted || generation != _sendGeneration) return;
      setState(() {
        _lastError = widget.isZh
            ? 'CDP 浏览器运行时不可用'
            : 'CDP browser runtime is unavailable';
        _sending = false;
      });
      return;
    }
    final sw = Stopwatch()..start();
    final abortKey =
        '__openhandResendAbort_${DateTime.now().microsecondsSinceEpoch}_$generation';
    _activeBrowserAbortKey = abortKey;
    try {
      final headers = _headersMap(forBrowserFetch: true);
      final body = _requestBodyOrNull();
      final js = _browserFetchExpression(
        url: uri.toString(),
        method: _method,
        headers: headers,
        body: body,
        abortKey: abortKey,
      );
      final result = await widget.controller.sendRawCdp(
        method: 'Runtime.evaluate',
        paramsJson: jsonEncode(<String, Object?>{
          'expression': js,
          'awaitPromise': true,
          'returnByValue': true,
          'silent': true,
        }),
        timeout: _kRequestTimeout + const Duration(seconds: 2),
      );
      final raw = cdpStringResultValue(result);
      if (raw == null) {
        throw StateError(
          '${result?['error'] ?? 'Runtime.evaluate returned no value'}',
        );
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('Invalid browser replay response.');
      }
      final map = Map<String, Object?>.from(decoded);
      if (map['ok'] != true) {
        final name = '${map['name'] ?? ''}'.trim();
        final error = '${map['error'] ?? 'Browser fetch failed'}'.trim();
        throw StateError(name.isEmpty ? error : '$name: $error');
      }
      if (!mounted || generation != _sendGeneration) return;
      setState(() {
        _lastResp = _ResponseSnapshot(
          status: (map['status'] as num?)?.toInt() ?? 0,
          reason: '${map['reason'] ?? ''}',
          headers: _stringMap(map['headers']),
          body: '${map['body'] ?? ''}',
          bodyIsBase64: map['bodyIsBase64'] == true,
          byteSize: (map['byteSize'] as num?)?.toInt() ?? 0,
          elapsed: Duration(
            milliseconds:
                (map['elapsedMs'] as num?)?.round() ?? sw.elapsedMilliseconds,
          ),
          transport: _ReplayTransport.browser,
          truncated: map['truncated'] == true,
        );
        _sending = false;
      });
    } catch (e, stack) {
      silentLog(
        'web_reverse_resend_request_dialog',
        '_sendViaBrowser',
        e,
        stack,
      );
      if (!mounted || generation != _sendGeneration) return;
      setState(() {
        _lastError = '$e';
        _sending = false;
      });
    } finally {
      if (identical(_activeBrowserAbortKey, abortKey)) {
        _activeBrowserAbortKey = null;
      }
    }
  }

  Future<void> _sendViaHttpClient(Uri uri, int generation) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..idleTimeout = const Duration(seconds: 6)
      ..badCertificateCallback = (_, _, _) => true;
    _activeClient = client;
    final sw = Stopwatch()..start();
    try {
      final req = await client.openUrl(_method, uri);
      // 默认不自动补 Host/Content-Length/Content-Type；由用户在 headers 里
      // 显式控制。仅当用户没写 Content-Length 且有 body 时由 HttpClient 自动加。
      req.followRedirects = false;
      req.persistentConnection = false;
      for (final entry in _headersMap().entries) {
        try {
          req.headers.set(entry.key, entry.value);
        } catch (_) {
          // 某些 header（如 transfer-encoding）HttpClient 不让覆盖，忽略。
        }
      }
      final body = _requestBodyOrNull();
      if (body != null && body.isNotEmpty) {
        req.add(utf8.encode(body));
      }
      final resp = await req.close().timeout(_kRequestTimeout);
      final bodyBytes = <int>[];
      var truncated = false;
      final readDeadline = DateTime.now().add(_kRequestTimeout);
      await for (final chunk in resp.timeout(_kResponseReadIdleTimeout)) {
        bodyBytes.addAll(chunk);
        if (bodyBytes.length > _kMaxResponseBytes) {
          bodyBytes.removeRange(_kMaxResponseBytes, bodyBytes.length);
          truncated = true;
          break;
        }
        if (DateTime.now().isAfter(readDeadline)) {
          truncated = true;
          break;
        }
      }
      sw.stop();
      final respHeaders = <String, String>{};
      resp.headers.forEach((name, vals) {
        respHeaders[name] = vals.join(', ');
      });
      String? bodyText;
      bool isBase64 = false;
      try {
        bodyText = utf8.decode(bodyBytes, allowMalformed: false);
      } catch (_) {
        bodyText = base64Encode(bodyBytes);
        isBase64 = true;
      }
      if (!mounted || generation != _sendGeneration) return;
      setState(() {
        _lastResp = _ResponseSnapshot(
          status: resp.statusCode,
          reason: resp.reasonPhrase,
          headers: respHeaders,
          body: bodyText ?? '',
          bodyIsBase64: isBase64,
          byteSize: bodyBytes.length,
          elapsed: sw.elapsed,
          transport: _ReplayTransport.direct,
          truncated: truncated,
        );
        _sending = false;
      });
    } catch (e, stack) {
      silentLog('web_reverse_resend_request_dialog', '_send', e, stack);
      if (!mounted || generation != _sendGeneration) return;
      setState(() {
        _lastError = '$e';
        _sending = false;
      });
    } finally {
      client.close(force: true);
      if (identical(_activeClient, client)) _activeClient = null;
    }
  }

  void _abort() {
    _sendGeneration++;
    final abortKey = _activeBrowserAbortKey;
    if (abortKey != null && abortKey.isNotEmpty) {
      unawaited(
        widget.controller.sendRawCdp(
          method: 'Runtime.evaluate',
          paramsJson: jsonEncode(<String, Object?>{
            'expression':
                '(() => { const c = window[${jsonEncode(abortKey)}]; '
                'if (c) c.abort("aborted"); delete window[${jsonEncode(abortKey)}]; })()',
            'returnByValue': true,
            'silent': true,
          }),
        ),
      );
      _activeBrowserAbortKey = null;
    }
    _activeClient?.close(force: true);
    _activeClient = null;
    if (mounted) {
      final loc = AppLocalizations.of(context);
      setState(() {
        _sending = false;
        _lastError = loc?.webReverseResendRequestAborted ?? 'Aborted';
      });
    }
  }

  Map<String, String> _headersMap({bool forBrowserFetch = false}) {
    final out = <String, String>{};
    for (final h in _headers) {
      if (!h.enabled) continue;
      final name = h.name.text.trim();
      if (name.isEmpty) continue;
      final normalized = name.toLowerCase();
      if (forBrowserFetch &&
          (_kBrowserFetchForbiddenHeaders.contains(normalized) ||
              normalized.startsWith('proxy-') ||
              normalized.startsWith('sec-'))) {
        continue;
      }
      out[name] = h.value.text;
    }
    return out;
  }

  String? _requestBodyOrNull() {
    if (_method == 'GET' || _method == 'HEAD') return null;
    final body = _bodyCtrl.text;
    return body.isEmpty ? null : body;
  }

  Map<String, String> _stringMap(Object? raw) {
    if (raw is! Map) return const <String, String>{};
    return raw.map((key, value) => MapEntry('$key', '$value'));
  }

  String _browserFetchExpression({
    required String url,
    required String method,
    required Map<String, String> headers,
    required String? body,
    required String abortKey,
  }) {
    return '''
(async () => {
  const started = performance.now();
  const maxBytes = $_kMaxResponseBytes;
  const controller = new AbortController();
  window[${jsonEncode(abortKey)}] = controller;
  const timer = setTimeout(() => controller.abort('timeout'), ${_kRequestTimeout.inMilliseconds});
  const toBase64 = (bytes) => {
    let binary = '';
    const step = 0x8000;
    for (let i = 0; i < bytes.length; i += step) {
      binary += String.fromCharCode(...bytes.subarray(i, i + step));
    }
    return btoa(binary);
  };
  try {
    const init = {
      method: ${jsonEncode(method)},
      headers: ${jsonEncode(headers)},
      credentials: 'include',
      redirect: 'manual',
      cache: 'no-store',
      signal: controller.signal,
    };
    const body = ${jsonEncode(body)};
    if (body !== null && body !== undefined) init.body = body;
    const response = await fetch(${jsonEncode(url)}, init);
    const chunks = [];
    let total = 0;
    let truncated = false;
    const reader = response.body && response.body.getReader ? response.body.getReader() : null;
    if (reader) {
      try {
        while (true) {
          const part = await reader.read();
          if (part.done) break;
          const value = part.value || new Uint8Array();
          const remaining = maxBytes - total;
          if (value.length > remaining) {
            chunks.push(value.slice(0, Math.max(remaining, 0)));
            total += Math.max(remaining, 0);
            truncated = true;
            try { await reader.cancel(); } catch (_) {}
            break;
          }
          chunks.push(value);
          total += value.length;
          if (total >= maxBytes) {
            truncated = true;
            try { await reader.cancel(); } catch (_) {}
            break;
          }
        }
      } finally {
        try { reader.releaseLock(); } catch (_) {}
      }
    } else {
      const all = new Uint8Array(await response.arrayBuffer());
      truncated = all.length > maxBytes;
      chunks.push(truncated ? all.slice(0, maxBytes) : all);
      total = chunks[0].length;
    }
    const bytes = new Uint8Array(total);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.length;
    }
    let responseBody = '';
    let bodyIsBase64 = false;
    try {
      responseBody = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
    } catch (_) {
      responseBody = toBase64(bytes);
      bodyIsBase64 = true;
    }
    return JSON.stringify({
      ok: true,
      status: response.status,
      reason: response.statusText || '',
      headers: Object.fromEntries(response.headers.entries()),
      body: responseBody,
      bodyIsBase64,
      byteSize: total,
      elapsedMs: Math.round(performance.now() - started),
      truncated,
    });
  } catch (error) {
    return JSON.stringify({
      ok: false,
      name: error && error.name ? String(error.name) : '',
      error: error && error.message ? String(error.message) : String(error),
      elapsedMs: Math.round(performance.now() - started),
    });
  } finally {
    clearTimeout(timer);
    delete window[${jsonEncode(abortKey)}];
  }
})()
''';
  }

  // ─── 代码导出 ─────────────────────────────────────────────────────────
  String _exportCurl() {
    String q(String s) => "'${s.replaceAll(r"'", r"'\''")}'";
    final buf = StringBuffer('curl ${q(_urlCtrl.text)}');
    if (_method != 'GET') buf.write(' \\\n  -X $_method');
    for (final h in _headers) {
      if (!h.enabled) continue;
      final n = h.name.text.trim();
      if (n.isEmpty) continue;
      buf.write(' \\\n  -H ${q("$n: ${h.value.text}")}');
    }
    final body = _bodyCtrl.text;
    if (body.isNotEmpty) buf.write(' \\\n  --data-raw ${q(body)}');
    return buf.toString();
  }

  String _exportPython() {
    final hbuf = StringBuffer('{\n');
    for (final h in _headers) {
      if (!h.enabled) continue;
      final n = h.name.text.trim();
      if (n.isEmpty) continue;
      hbuf.writeln('    ${jsonEncode(n)}: ${jsonEncode(h.value.text)},');
    }
    hbuf.write('}');
    final body = _bodyCtrl.text;
    final dataLine = body.isEmpty
        ? ''
        : '    data=${jsonEncode(body)}.encode("utf-8"),\n';
    return '''import requests

resp = requests.request(
    "${_method.toUpperCase()}",
    ${jsonEncode(_urlCtrl.text)},
    headers=$hbuf,
$dataLine    timeout=30,
    verify=False,
    allow_redirects=False,
)
print(resp.status_code)
print(resp.text[:2000])''';
  }

  String _exportFetch() {
    final hbuf = StringBuffer('{\n');
    for (final h in _headers) {
      if (!h.enabled) continue;
      final n = h.name.text.trim();
      if (n.isEmpty) continue;
      hbuf.writeln('    ${jsonEncode(n)}: ${jsonEncode(h.value.text)},');
    }
    hbuf.write('  }');
    final body = _bodyCtrl.text;
    final bodyLine = body.isEmpty ? '' : ',\n  body: ${jsonEncode(body)}';
    return '''await fetch(${jsonEncode(_urlCtrl.text)}, {
  method: ${jsonEncode(_method)},
  headers: $hbuf,
  credentials: "include"$bodyLine,
});''';
  }

  Future<void> _copy(String text, String kind) async {
    final copied = await setWebReverseClipboardText(text);
    if (!mounted) return;
    final loc = AppLocalizations.of(context);
    OpenHandSnackBar.showSuccess(
      context,
      webReverseClipboardSnackMessage(
        isZh: widget.isZh,
        base: loc?.webReverseResendRequestCopiedAs(kind) ?? 'Copied as $kind',
        result: copied,
      ),
      duration: const Duration(seconds: 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return buildOpenHandToolDialogShell(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(loc),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildUrlRow(theme, cs, loc),
                  const SizedBox(height: 14),
                  _buildTransportRow(theme, cs, loc),
                  const SizedBox(height: 14),
                  _buildHeadersBlock(theme, cs, loc),
                  const SizedBox(height: 14),
                  _buildBodyBlock(theme, cs, loc),
                  const SizedBox(height: 14),
                  _buildExportBlock(theme, cs, loc),
                  const SizedBox(height: 14),
                  AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    child: _buildResultBlock(theme, cs, loc),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
            child: Row(
              children: [
                Text(
                  _transport == _ReplayTransport.browser
                      ? (widget.isZh
                            ? '通过 CDP 在页面上下文重放请求'
                            : 'Replays through CDP in the page context')
                      : (loc?.webReverseResendRequestFooterNote ??
                            'Direct mode uses Dart HttpClient and bypasses the browser.'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                OpenHandDialogActionButton.secondary(
                  onPressed: () => Navigator.of(context).pop(),
                  label: loc?.webReverseResendRequestClose ?? 'Close',
                ),
                const SizedBox(width: 8),
                _sending
                    ? OpenHandDialogActionButton.destructive(
                        onPressed: _abort,
                        icon: Icons.stop_rounded,
                        label: loc?.webReverseResendRequestAbort ?? 'Abort',
                      )
                    : OpenHandDialogActionButton.primary(
                        onPressed: _send,
                        icon: Icons.send_rounded,
                        label: loc?.webReverseResendRequestSend ?? 'Send',
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransportRow(
    ThemeData theme,
    ColorScheme cs,
    AppLocalizations? loc,
  ) {
    final browserAlive = widget.controller.isBrowserAlive;
    return Row(
      children: [
        Icon(Icons.route_rounded, size: 16, color: cs.primary),
        const SizedBox(width: 8),
        Text(
          widget.isZh ? '发送方式' : 'Transport',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 12),
        SegmentedButton<_ReplayTransport>(
          selected: <_ReplayTransport>{_transport},
          showSelectedIcon: false,
          segments: <ButtonSegment<_ReplayTransport>>[
            ButtonSegment<_ReplayTransport>(
              value: _ReplayTransport.browser,
              enabled: browserAlive,
              icon: const Icon(Icons.travel_explore_rounded, size: 16),
              label: const Text('CDP'),
            ),
            ButtonSegment<_ReplayTransport>(
              value: _ReplayTransport.direct,
              icon: const Icon(Icons.cable_rounded, size: 16),
              label: Text(widget.isZh ? '直连' : 'Direct'),
            ),
          ],
          onSelectionChanged: (values) {
            final next = values.firstOrNull;
            if (next == null) return;
            setState(() => _transport = next);
          },
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _transport == _ReplayTransport.browser
                ? (widget.isZh
                      ? '使用页面 Cookie 和浏览器网络栈'
                      : 'Page cookies and browser network stack')
                : (widget.isZh
                      ? '绕过浏览器，适合隔离验证'
                      : 'Bypasses browser for isolated checks'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(AppLocalizations? loc) {
    return buildOpenHandToolDialogHeader(
      context: context,
      icon: Icons.replay_circle_filled_rounded,
      title: loc?.webReverseResendRequestTitle ?? 'Resend / Edit',
      closeTooltip: loc?.webReverseResendRequestClose ?? 'Close',
    );
  }

  Widget _buildUrlRow(ThemeData theme, ColorScheme cs, AppLocalizations? loc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: WebReverseSelectFormField<String>(
            initialValue: _method,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
            options: [
              for (final m in _kMethods)
                WebReverseSelectOption(value: m, label: m),
            ],
            tooltip: 'Method',
            onChanged: (v) => setState(() => _method = v),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: _urlCtrl,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              labelText: 'URL',
              hintText: 'https://...',
            ),
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }

  Widget _buildHeadersBlock(
    ThemeData theme,
    ColorScheme cs,
    AppLocalizations? loc,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.list_rounded, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                loc?.webReverseResendRequestHeadersLabel ?? 'Headers',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.add_rounded, size: 16),
                label: Text(loc?.webReverseResendRequestAddRow ?? 'Add'),
                onPressed: _addBlankHeader,
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < _headers.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Checkbox(
                    value: _headers[i].enabled,
                    onChanged: (v) =>
                        setState(() => _headers[i].enabled = v ?? true),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  Expanded(
                    flex: 4,
                    child: TextField(
                      controller: _headers[i].name,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        hintText: 'name',
                      ),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 7,
                    child: TextField(
                      controller: _headers[i].value,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        hintText: 'value',
                      ),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: cs.onSurfaceVariant,
                    ),
                    onPressed: () => _removeHeader(i),
                    tooltip: loc?.webReverseResendRequestRemove ?? 'Remove',
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBodyBlock(
    ThemeData theme,
    ColorScheme cs,
    AppLocalizations? loc,
  ) {
    final canBody = _method != 'GET' && _method != 'HEAD';
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.data_object_rounded, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                loc?.webReverseResendRequestBodyLabel ?? 'Body',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (!canBody)
                Text(
                  loc?.webReverseResendRequestHasNoBody(_method) ??
                      '$_method has no body',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              if (canBody && _bodyCtrl.text.isNotEmpty)
                TextButton.icon(
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 14),
                  label: Text(
                    loc?.webReverseResendRequestBeautifyJson ?? 'Beautify JSON',
                  ),
                  onPressed: () {
                    final loc2 = AppLocalizations.of(context);
                    try {
                      final v = jsonDecode(_bodyCtrl.text);
                      _bodyCtrl.text = const JsonEncoder.withIndent(
                        '  ',
                      ).convert(v);
                      setState(() {});
                    } catch (_) {
                      OpenHandSnackBar.showError(
                        context,
                        loc2?.webReverseResendRequestInvalidJson ??
                            'Body is not valid JSON',
                      );
                    }
                  },
                ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _bodyCtrl,
            enabled: canBody,
            minLines: 4,
            maxLines: 10,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              hintText: 'raw body…',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExportBlock(
    ThemeData theme,
    ColorScheme cs,
    AppLocalizations? loc,
  ) {
    Widget chip(IconData icon, String label, VoidCallback onTap) {
      return OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 14),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text(
            loc?.webReverseResendRequestExportAs ?? 'Export as:',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        chip(
          Icons.terminal_rounded,
          'curl',
          () => _copy(_exportCurl(), 'curl'),
        ),
        chip(
          Icons.code_rounded,
          'Python requests',
          () => _copy(_exportPython(), 'Python'),
        ),
        chip(
          Icons.javascript_rounded,
          'fetch',
          () => _copy(_exportFetch(), 'fetch'),
        ),
      ],
    );
  }

  Widget _buildResultBlock(
    ThemeData theme,
    ColorScheme cs,
    AppLocalizations? loc,
  ) {
    if (_lastError != null) {
      return Container(
        key: const ValueKey('err'),
        decoration: BoxDecoration(
          color: cs.errorContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.error.withValues(alpha: 0.5)),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, color: cs.error, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: SelectableText(
                _lastError!,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }
    final r = _lastResp;
    if (r == null) {
      return const SizedBox(key: ValueKey('empty'));
    }
    final color = r.status >= 500
        ? cs.error
        : (r.status >= 400 ? cs.tertiary : cs.primary);
    return Container(
      key: ValueKey('resp_${r.status}_${r.byteSize}'),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${r.status} ${r.reason}',
                  style: TextStyle(color: color, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${r.transport.label(widget.isZh)} · ${r.byteSize} B · ${r.elapsed.inMilliseconds} ms',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip:
                    loc?.webReverseResendRequestCopyResponse ?? 'Copy response',
                icon: const Icon(Icons.content_copy_rounded, size: 14),
                onPressed: () async {
                  final dialogContext = context;
                  final messenger = ScaffoldMessenger.of(dialogContext);
                  final loc2 = AppLocalizations.of(dialogContext);
                  final isZh = loc2?.localeName.startsWith('zh') ?? false;
                  final base =
                      loc2?.webReverseResendRequestResponseCopied ??
                      'Response copied';
                  final copied = await setWebReverseClipboardText(r.body);
                  if (!dialogContext.mounted) return;
                  OpenHandSnackBar.showSuccessOn(
                    dialogContext,
                    messenger,
                    webReverseClipboardSnackMessage(
                      isZh: isZh,
                      base: base,
                      result: copied,
                    ),
                    duration: const Duration(seconds: 1),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: Text(
              loc?.webReverseResendRequestHeadersWithCount(r.headers.length) ??
                  'Headers (${r.headers.length})',
              style: theme.textTheme.bodySmall,
            ),
            children: [
              for (final e in r.headers.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 2,
                    horizontal: 6,
                  ),
                  child: SelectableText(
                    '${e.key}: ${e.value}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
          const Divider(height: 12),
          Text(
            r.bodyIsBase64
                ? (loc?.webReverseResendRequestBase64Hint ??
                      'Non-UTF8 response (base64 preview):')
                : r.truncated
                ? (widget.isZh ? 'Body (已截断):' : 'Body (truncated):')
                : (loc?.webReverseResendRequestBodyHint ?? 'Body:'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                r.body.length > 8000
                    ? '${r.body.substring(0, 8000)}\n…(truncated)'
                    : r.body,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _ReplayTransport {
  browser,
  direct;

  String label(bool isZh) {
    return switch (this) {
      _ReplayTransport.browser => isZh ? 'CDP' : 'CDP',
      _ReplayTransport.direct => isZh ? '直连' : 'Direct',
    };
  }
}

class _HeaderRow {
  _HeaderRow({required this.name, required this.value, required this.enabled});
  final TextEditingController name;
  final TextEditingController value;
  bool enabled;
}

class _ResponseSnapshot {
  const _ResponseSnapshot({
    required this.status,
    required this.reason,
    required this.headers,
    required this.body,
    required this.bodyIsBase64,
    required this.byteSize,
    required this.elapsed,
    required this.transport,
    required this.truncated,
  });
  final int status;
  final String reason;
  final Map<String, String> headers;
  final String body;
  final bool bodyIsBase64;
  final int byteSize;
  final Duration elapsed;
  final _ReplayTransport transport;
  final bool truncated;
}
