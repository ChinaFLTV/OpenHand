// 报文重放/改包 (Resend·Edit) Dialog
// 从 Network 详情面板触发：以一个 [CdpNetworkEntry] 为初始模板，让用户
// 修改 URL / Method / Headers / Body 后默认通过 CDP 在页面上下文 fetch，
// 保留 Dart [HttpClient] 直连模式作为显式备选，结果实时展示状态、响应头、响应体。
// 顶部右侧 segmented action 可一键导出为 curl / Python requests / fetch
// 代码并复制到剪贴板，方便贴到外部脚本。
// 动画风格：showAnimatedDialog 自带 Q弹进退场；内部状态切换走
// AnimatedSwitcher 220ms + easeOutCubic，遵守 MediaQuery 减动效。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../app/support/system_proxy.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/net/http_response_utils.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/animated_expandable.dart';
import '../../shared/ui/motion_durations.dart';
import '../../shared/ui/motion_preference.dart';
import '../../shared/ui/oh_pill.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import '../../shared/ui/openhand_spacing.dart';
import '../../shared/ui/openhand_typography.dart';
import '../../shared/util/async_concurrency.dart';
import '../../shared/util/byte_size_format.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/localized_text.dart';
import '../../shared/util/text_clip.dart';
import 'web_reverse_clipboard.dart';
import 'web_reverse_dialog_utils.dart';
import 'web_reverse_pure_helpers.dart';
import 'web_reverse_select_button.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseResendRequestDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
  required CdpNetworkEntry entry,
}) {
  return webReverseToolDialogs.show<void>(
    context: context,
    builder: (_) =>
        _ResendRequestDialog(controller: controller, initial: entry),
  );
}

class _ResendRequestDialog extends StatefulWidget {
  const _ResendRequestDialog({required this.controller, required this.initial});
  final WebReverseSessionController controller;
  final CdpNetworkEntry initial;

  @override
  State<_ResendRequestDialog> createState() => _ResendRequestDialogState();
}

class _ResendRequestDialogState extends State<_ResendRequestDialog> {
  static const int _kMaxResponseBytes = 2 * kBytesPerMiB;
  static const int _kMaxHeaderRows = 128;
  static const int _kMaxUrlCharacters = 16 * 1024;
  static const int _kMaxHeaderCharacters = 64 * kBytesPerKiB;
  static const int _kMaxRequestBodyBytes = kBytesPerMiB;
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
    for (final entry in widget.initial.requestHeaders.entries) {
      final k = entry.key;
      if (k.startsWith(':')) continue; // 跳过 HTTP/2 伪头
      if (_headers.length >= _kMaxHeaderRows) break;
      _headers.add(
        _HeaderRow(
          name: TextEditingController(text: k),
          value: TextEditingController(text: entry.value),
          enabled: true,
        ),
      );
    }
    if (_headers.isEmpty) _headers.add(_createBlankHeader());
  }

  @override
  void dispose() {
    _sendGeneration++;
    _cancelActiveTransports();
    _urlCtrl.dispose();
    _bodyCtrl.dispose();
    for (final h in _headers) {
      h.name.dispose();
      h.value.dispose();
    }
    super.dispose();
  }

  _HeaderRow _createBlankHeader() {
    return _HeaderRow(
      name: TextEditingController(),
      value: TextEditingController(),
      enabled: true,
    );
  }

  void _addBlankHeader() {
    if (_headers.length >= _kMaxHeaderRows) return;
    setState(() {
      _headers.add(_createBlankHeader());
    });
  }

  void _removeHeader(int i) {
    setState(() {
      final h = _headers.removeAt(i);
      h.name.dispose();
      h.value.dispose();
      if (_headers.isEmpty) _headers.add(_createBlankHeader());
    });
  }

  Future<void> _send() async {
    final urlText = _urlCtrl.text.trim();
    final loc0 = AppLocalizations.of(context);
    if (urlText.isEmpty) {
      showOpenHandErrorSnack(
        context,
        loc0?.webReverseResendRequestUrlEmpty ?? 'URL is required',
      );
      return;
    }
    if (urlText.length > _kMaxUrlCharacters) {
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: 'URL 超过长度上限',
          en: 'URL exceeds the length limit',
        ),
      );
      return;
    }
    final headerCharacters = _headers.fold<int>(
      0,
      (total, header) => header.enabled
          ? total + header.name.text.length + header.value.text.length
          : total,
    );
    if (headerCharacters > _kMaxHeaderCharacters) {
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '请求头超过容量上限',
          en: 'Request headers exceed the size limit',
        ),
      );
      return;
    }
    final body = _requestBodyOrNull();
    final bodyBytes = body == null || body.length > _kMaxRequestBodyBytes
        ? null
        : utf8.encode(body);
    if (body != null &&
        (bodyBytes == null || bodyBytes.length > _kMaxRequestBodyBytes)) {
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '请求体超过 1 MiB 上限',
          en: 'Request body exceeds the 1 MiB limit',
        ),
      );
      return;
    }
    Uri uri;
    try {
      uri = Uri.parse(urlText);
      if (!uri.hasScheme || !(uri.scheme == 'http' || uri.scheme == 'https')) {
        throw const FormatException('仅支持 HTTP/HTTPS 地址。');
      }
    } catch (_) {
      showOpenHandErrorSnack(
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
      await _sendViaBrowser(uri, generation, body: body);
    } else {
      await _sendViaHttpClient(uri, generation, bodyBytes: bodyBytes);
    }
  }

  Future<void> _sendViaBrowser(
    Uri uri,
    int generation, {
    required String? body,
  }) async {
    if (!widget.controller.isBrowserAlive) {
      if (!mounted || generation != _sendGeneration) return;
      setState(() {
        _lastError = openHandLocalizedText(
          context,
          zh: 'CDP 浏览器运行时不可用',
          zhHant: 'CDP 瀏覽器執行階段不可用',
          en: 'CDP browser runtime is unavailable',
          fr: 'Le runtime navigateur CDP est indisponible',
          de: 'CDP-Browserlaufzeit ist nicht verfügbar',
          ja: 'CDP ブラウザランタイムを利用できません',
        );
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
      final js = _browserFetchExpression(
        url: uri.toString(),
        method: _method,
        headers: headers,
        body: body,
        abortKey: abortKey,
      );
      final result = await widget.controller.evaluateJavaScript(
        js,
        awaitPromise: true,
        silent: true,
        timeout: _kRequestTimeout + const Duration(seconds: 2),
      );
      final raw = cdpStringResultValue(result);
      if (raw == null) {
        throw StateError('${result?['error'] ?? 'Runtime.evaluate 未返回值'}');
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('浏览器重放响应无效。');
      }
      final map = stringKeyedMapFromValue(decoded);
      if (map['ok'] != true) {
        final name = '${map['name'] ?? ''}'.trim();
        final error = '${map['error'] ?? '浏览器请求失败'}'.trim();
        throw StateError(name.isEmpty ? error : '$name: $error');
      }
      if (!mounted || generation != _sendGeneration) return;
      setState(() {
        _lastResp = _ResponseSnapshot(
          status: nonNegativeIntFromValue(map['status'], fallback: 0),
          reason: '${map['reason'] ?? ''}',
          headers: _stringMap(map['headers']),
          body: '${map['body'] ?? ''}',
          bodyIsBase64: boolFromValue(map['bodyIsBase64']),
          byteSize: nonNegativeIntFromValue(map['byteSize'], fallback: 0),
          elapsed: Duration(
            milliseconds: nonNegativeIntFromValue(
              map['elapsedMs'],
              fallback: sw.elapsedMilliseconds,
            ),
          ),
          transport: _ReplayTransport.browser,
          truncated: boolFromValue(map['truncated']),
        );
        _sending = false;
      });
    } catch (e, stack) {
      silentLog('web_reverse_resend_request_dialog', '通过浏览器重发请求', e, stack);
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

  Future<void> _sendViaHttpClient(
    Uri uri,
    int generation, {
    required List<int>? bodyBytes,
  }) async {
    final client = SystemProxyResolver.instance.createRawHttpClient(
      connectionTimeout: const Duration(seconds: 12),
    )..idleTimeout = const Duration(seconds: 6);
    _activeClient = client;
    final deadline = MonotonicDeadline(
      _kRequestTimeout,
      timeoutMessage: '请求超过总时限。',
    );

    try {
      final req = await client
          .openUrl(_method, uri)
          .timeout(deadline.remaining());
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
      if (bodyBytes != null && bodyBytes.isNotEmpty) {
        req.add(bodyBytes);
      }
      final resp = await req.close().timeout(deadline.remaining());
      final remainingReadTime = deadline.remaining();
      final readIdleTimeout = remainingReadTime < _kResponseReadIdleTimeout
          ? remainingReadTime
          : _kResponseReadIdleTimeout;
      final bodyResult = await readBoundedByteStreamPrefix(
        resp,
        maxBytes: _kMaxResponseBytes,
        idleTimeout: readIdleTimeout,
        totalTimeout: remainingReadTime,
      );
      final responseBodyBytes = bodyResult.bytes;
      deadline.stop();
      final respHeaders = <String, String>{};
      resp.headers.forEach((name, vals) {
        respHeaders[name] = vals.join(', ');
      });
      String? bodyText;
      bool isBase64 = false;
      try {
        bodyText = utf8.decode(responseBodyBytes, allowMalformed: false);
      } catch (_) {
        bodyText = base64Encode(responseBodyBytes);
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
          byteSize: responseBodyBytes.length,
          elapsed: deadline.elapsed,
          transport: _ReplayTransport.direct,
          truncated: bodyResult.truncated,
        );
        _sending = false;
      });
    } catch (e, stack) {
      silentLog('web_reverse_resend_request_dialog', '重发请求', e, stack);
      if (!mounted || generation != _sendGeneration) return;
      setState(() {
        _lastError = '$e';
        _sending = false;
      });
    } finally {
      deadline.stop();
      client.close(force: true);
      if (identical(_activeClient, client)) _activeClient = null;
    }
  }

  void _abort() {
    _sendGeneration++;
    _cancelActiveTransports();
    if (mounted) {
      final loc = AppLocalizations.of(context);
      setState(() {
        _sending = false;
        _lastError = loc?.webReverseResendRequestAborted ?? 'Aborted';
      });
    }
  }

  void _cancelActiveTransports() {
    final abortKey = _activeBrowserAbortKey;
    if (abortKey != null && abortKey.isNotEmpty) {
      _activeBrowserAbortKey = null;
      unawaited(_abortBrowserReplay(abortKey));
    }
    _activeClient?.close(force: true);
    _activeClient = null;
  }

  Future<void> _abortBrowserReplay(String abortKey) async {
    if (!widget.controller.isBrowserAlive) return;
    try {
      await widget.controller.evaluateJavaScript(
        '(() => { const c = window[${jsonEncode(abortKey)}]; '
        'if (c) c.abort("aborted"); delete window[${jsonEncode(abortKey)}]; })()',
        silent: true,
        timeout: const Duration(seconds: 2),
      );
    } catch (error, stack) {
      silentLog('web_reverse_resend_request_dialog', '终止浏览器重放请求', error, stack);
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
  const probeMaxBytes = maxBytes + 1;
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
    const reader = response.body && response.body.getReader ? response.body.getReader() : null;
    if (response.body && !reader) {
      throw new Error('无法流式读取响应体');
    }
    if (reader) {
      try {
        while (true) {
          const part = await reader.read();
          if (part.done) break;
          const value = part.value || new Uint8Array();
          const remaining = probeMaxBytes - total;
          if (value.length > remaining) {
            chunks.push(value.slice(0, Math.max(remaining, 0)));
            total += Math.max(remaining, 0);
            try { await reader.cancel(); } catch (_) {}
            break;
          }
          chunks.push(value);
          total += value.length;
          if (total >= probeMaxBytes) {
            try { await reader.cancel(); } catch (_) {}
            break;
          }
        }
      } finally {
        try { reader.releaseLock(); } catch (_) {}
      }
    }
    const truncated = total > maxBytes;
    const retainedBytes = Math.min(total, maxBytes);
    const bytes = new Uint8Array(retainedBytes);
    let offset = 0;
    for (const chunk of chunks) {
      const remaining = retainedBytes - offset;
      if (remaining <= 0) break;
      const part = chunk.length > remaining ? chunk.subarray(0, remaining) : chunk;
      bytes.set(part, offset);
      offset += part.length;
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
      byteSize: retainedBytes,
      elapsedMs: Math.round(performance.now() - started),
      truncated,
    });
  } catch (error) {
    try { controller.abort('failed'); } catch (_) {}
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
    final loc = AppLocalizations.of(context);
    await copyWebReverseTextToClipboard(
      context: context,
      text: text,
      successBase:
          loc?.webReverseResendRequestCopiedAs(kind) ?? 'Copied as $kind',
      logTag: 'web_reverse_resend_request_dialog',
      logAction: '复制 $kind',
      successDuration: const Duration(seconds: 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    final reduceMotion = !openHandTickerMotionEnabled(context);
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
                  kOpenHandGap14,
                  _buildTransportRow(theme, cs, loc),
                  kOpenHandGap14,
                  _buildHeadersBlock(theme, cs, loc),
                  kOpenHandGap14,
                  _buildBodyBlock(theme, cs, loc),
                  kOpenHandGap14,
                  _buildExportBlock(theme, cs, loc),
                  kOpenHandGap14,
                  AnimatedSwitcher(
                    duration: reduceMotion ? Duration.zero : kOpenHandMotion220,
                    switchInCurve: Curves.easeOutCubic,
                    child: _buildResultBlock(theme, cs, loc),
                  ),
                  kOpenHandGap12,
                ],
              ),
            ),
          ),
          buildWebReverseDialogFooter(
            context,
            leading: Text(
              _transport == _ReplayTransport.browser
                  ? openHandLocalizedText(
                      context,
                      zh: '通过 CDP 在页面上下文重放请求',
                      zhHant: '透過 CDP 在頁面上下文重放請求',
                      en: 'Replays through CDP in the page context',
                      fr: 'Rejoue via CDP dans le contexte de la page',
                      de: 'Wiederholt per CDP im Seitenkontext',
                      ja: 'CDP でページコンテキスト内にリプレイ',
                    )
                  : (loc?.webReverseResendRequestFooterNote ??
                        'Direct mode uses Dart HttpClient and bypasses the browser.'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            actions: [
              OpenHandDialogActionButton.secondary(
                onPressed: () => Navigator.of(context).pop(),
                label: loc?.webReverseResendRequestClose ?? 'Close',
              ),
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
        kOpenHandHGap8,
        Text(
          openHandLocalizedText(
            context,
            zh: '发送方式',
            zhHant: '傳送方式',
            en: 'Transport',
            fr: 'Transport',
            de: 'Transport',
            ja: '送信方式',
          ),
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        kOpenHandHGap12,
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
              label: Text(_ReplayTransport.direct.label(context)),
            ),
          ],
          onSelectionChanged: (values) {
            final next = values.firstOrNull;
            if (next == null) return;
            setState(() => _transport = next);
          },
        ),
        kOpenHandHGap10,
        Expanded(
          child: Text(
            _transport == _ReplayTransport.browser
                ? openHandLocalizedText(
                    context,
                    zh: '使用页面 Cookie 和浏览器网络栈',
                    zhHant: '使用頁面 Cookie 與瀏覽器網路棧',
                    en: 'Page cookies and browser network stack',
                    fr: 'Cookies de page et pile réseau du navigateur',
                    de: 'Seiten-Cookies und Browser-Netzwerkstack',
                    ja: 'ページ Cookie とブラウザのネットワークスタック',
                  )
                : openHandLocalizedText(
                    context,
                    zh: '绕过浏览器，适合隔离验证',
                    zhHant: '繞過瀏覽器，適合隔離驗證',
                    en: 'Bypasses browser for isolated checks',
                    fr: 'Contourne le navigateur pour des vérifications isolées',
                    de: 'Umgeht den Browser für isolierte Prüfungen',
                    ja: 'ブラウザを迂回して単独検証に使用',
                  ),
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
        kOpenHandHGap10,
        Expanded(
          child: TextField(
            controller: _urlCtrl,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              labelText: 'URL',
              hintText: 'https://...',
            ),
            style: const TextStyle(fontFamily: kOpenHandMonospaceFontFamily),
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
      decoration: webReverseSurfaceCardDecoration(cs, radius: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.list_rounded, size: 16, color: cs.primary),
              kOpenHandHGap6,
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
                onPressed: _headers.length >= _kMaxHeaderRows
                    ? null
                    : _addBlankHeader,
              ),
            ],
          ),
          kOpenHandGap6,
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
                        fontFamily: kOpenHandMonospaceFontFamily,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  kOpenHandHGap6,
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
                        fontFamily: kOpenHandMonospaceFontFamily,
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
      decoration: webReverseSurfaceCardDecoration(cs, radius: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.data_object_rounded, size: 16, color: cs.primary),
              kOpenHandHGap6,
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
                      _bodyCtrl.text = prettyPrintJson(v);
                      setState(() {});
                    } catch (_) {
                      showOpenHandErrorSnack(
                        context,
                        loc2?.webReverseResendRequestInvalidJson ??
                            'Body is not valid JSON',
                      );
                    }
                  },
                ),
            ],
          ),
          kOpenHandGap6,
          TextField(
            controller: _bodyCtrl,
            enabled: canBody,
            minLines: 4,
            maxLines: 10,
            style: const TextStyle(
              fontFamily: kOpenHandMonospaceFontFamily,
              fontSize: 12,
            ),
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
          borderRadius: kOpenHandBorderRadius12,
          border: Border.all(color: cs.error.withValues(alpha: 0.5)),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, color: cs.error, size: 16),
            kOpenHandHGap8,
            Expanded(
              child: SelectableText(
                _lastError!,
                style: const TextStyle(
                  fontFamily: kOpenHandMonospaceFontFamily,
                  fontSize: 12,
                ),
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
    final truncatedBodySuffix =
        '\n${openHandLocalizedText(context, zh: '…（已截断）', zhHant: '…（已截斷）', en: '…(truncated)', fr: '…(tronqué)', de: '…(gekürzt)', ja: '…（切り詰め済み）')}';
    final responseBodyPreview = clipText(
      r.body,
      8000,
      suffix: truncatedBodySuffix,
    );
    final color = r.status >= 500
        ? cs.error
        : (r.status >= 400 ? cs.tertiary : cs.primary);
    return Container(
      key: ValueKey('resp_${r.status}_${r.byteSize}'),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: kOpenHandBorderRadius12,
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
                  borderRadius: kOpenHandPillBorderRadius,
                ),
                child: Text(
                  '${r.status} ${r.reason}',
                  style: TextStyle(color: color, fontWeight: FontWeight.w800),
                ),
              ),
              kOpenHandHGap8,
              Text(
                '${r.transport.label(context)} · ${r.byteSize} B · ${r.elapsed.inMilliseconds} ms',
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
                  final loc2 = AppLocalizations.of(dialogContext);
                  final base =
                      loc2?.webReverseResendRequestResponseCopied ??
                      'Response copied';
                  await copyWebReverseTextToClipboard(
                    context: dialogContext,
                    text: r.body,
                    successBase: base,
                    logTag: 'web_reverse_resend_request_dialog',
                    logAction: '复制响应',
                    successDuration: const Duration(seconds: 1),
                  );
                },
              ),
            ],
          ),
          kOpenHandGap6,
          OpenHandExpansionTile(
            tilePadding: EdgeInsets.zero,
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
                      fontFamily: kOpenHandMonospaceFontFamily,
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
                ? openHandLocalizedText(
                    context,
                    zh: 'Body（已截断）：',
                    zhHant: 'Body（已截斷）：',
                    en: 'Body (truncated):',
                    fr: 'Body (tronqué) :',
                    de: 'Body (gekürzt):',
                    ja: 'Body（切り詰め済み）:',
                  )
                : (loc?.webReverseResendRequestBodyHint ?? 'Body:'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          kOpenHandGap4,
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: kOpenHandBorderRadius8,
              border: Border.all(color: cs.outlineVariant),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                responseBodyPreview,
                style: const TextStyle(
                  fontFamily: kOpenHandMonospaceFontFamily,
                  fontSize: 11,
                ),
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

  String label(BuildContext context) {
    return switch (this) {
      _ReplayTransport.browser => 'CDP',
      _ReplayTransport.direct => openHandLocalizedText(
        context,
        zh: '直连',
        zhHant: '直連',
        en: 'Direct',
        fr: 'Direct',
        de: 'Direkt',
        ja: '直接',
      ),
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
