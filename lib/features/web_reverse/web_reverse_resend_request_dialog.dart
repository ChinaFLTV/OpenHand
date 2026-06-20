// 报文重放/改包 (Resend·Edit) Dialog
//
// 从 Network 详情面板触发：以一个 [CdpNetworkEntry] 为初始模板，让用户
// 修改 URL / Method / Headers / Body 后用 Dart [HttpClient] 直接发请求
// （绕过浏览器，不受 CSP/CORS 影响），结果实时展示状态、响应头、响应体。
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
import 'package:flutter/services.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import 'web_reverse_clipboard.dart';
import 'web_reverse_select_button.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseResendRequestDialog(
  BuildContext context, {
  required CdpNetworkEntry entry,
  required bool isZh,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _ResendRequestDialog(initial: entry, isZh: isZh),
  );
}

class _ResendRequestDialog extends StatefulWidget {
  const _ResendRequestDialog({required this.initial, required this.isZh});
  final CdpNetworkEntry initial;
  final bool isZh;

  @override
  State<_ResendRequestDialog> createState() => _ResendRequestDialogState();
}

class _ResendRequestDialogState extends State<_ResendRequestDialog> {
  static const _kMethods = [
    'GET',
    'POST',
    'PUT',
    'PATCH',
    'DELETE',
    'HEAD',
    'OPTIONS',
  ];

  late final TextEditingController _urlCtrl;
  late final TextEditingController _bodyCtrl;
  late String _method;
  final List<_HeaderRow> _headers = <_HeaderRow>[];

  bool _sending = false;
  HttpClient? _activeClient;
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
    setState(() {
      _sending = true;
      _lastResp = null;
      _lastError = null;
    });
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
      for (final h in _headers) {
        if (!h.enabled) continue;
        final n = h.name.text.trim();
        if (n.isEmpty) continue;
        try {
          req.headers.set(n, h.value.text);
        } catch (_) {
          // 某些 header（如 transfer-encoding）HttpClient 不让覆盖，忽略。
        }
      }
      final body = _bodyCtrl.text;
      if (body.isNotEmpty && _method != 'GET' && _method != 'HEAD') {
        req.add(utf8.encode(body));
      }
      final resp = await req.close().timeout(const Duration(seconds: 30));
      final bodyBytes = <int>[];
      await for (final chunk in resp) {
        bodyBytes.addAll(chunk);
        if (bodyBytes.length > 2 * 1024 * 1024) break; // 2MB 上限防内存爆
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
      if (!mounted) return;
      setState(() {
        _lastResp = _ResponseSnapshot(
          status: resp.statusCode,
          reason: resp.reasonPhrase,
          headers: respHeaders,
          body: bodyText ?? '',
          bodyIsBase64: isBase64,
          byteSize: bodyBytes.length,
          elapsed: sw.elapsed,
        );
        _sending = false;
      });
    } catch (e, stack) {
      silentLog('web_reverse_resend_request_dialog', '_send', e, stack);
      if (!mounted) return;
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

  void _copy(String text, String kind) {
    Clipboard.setData(ClipboardData(text: text));
    final loc = AppLocalizations.of(context);
    OpenHandSnackBar.showSuccess(
      context,
      loc?.webReverseResendRequestCopiedAs(kind) ?? 'Copied as $kind',
      duration: const Duration(seconds: 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Dialog(
      backgroundColor: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(theme, cs, loc),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildUrlRow(theme, cs, loc),
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
                    loc?.webReverseResendRequestFooterNote ??
                        'This dialog re-issues via Dart HttpClient (bypasses CSP/CORS).',
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
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, ColorScheme cs, AppLocalizations? loc) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 12),
      child: Row(
        children: [
          Icon(Icons.replay_circle_filled_rounded, color: cs.primary),
          const SizedBox(width: 10),
          Text(
            loc?.webReverseResendRequestTitle ?? 'Resend / Edit',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: loc?.webReverseResendRequestClose ?? 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
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
                '${r.byteSize} B · ${r.elapsed.inMilliseconds} ms',
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
  });
  final int status;
  final String reason;
  final Map<String, String> headers;
  final String body;
  final bool bodyIsBase64;
  final int byteSize;
  final Duration elapsed;
}
