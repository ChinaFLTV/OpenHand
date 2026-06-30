/// WebSocket 主动注入面板。
///
/// 在页面里安装一段 `WebSocket` 构造器代理脚本：所有由页面或第三方 JS 创建的
/// WebSocket 实例都会被登记在 `window.__OH_WS_REGISTRY__` 里，按创建顺序分配
/// 自增 id 并记录 url / 状态。本面板用 `Runtime.evaluate` 读取列表并通过
/// `__OH_WS_REGISTRY__[id].send(payload)` 注入文本帧——支持 JSON / 任意字符串。
///
/// 通过 `Page.addScriptToEvaluateOnNewDocument` 保证刷新 / 跳转后仍然生效，
/// 同时立即对当前 document 执行一遍以接管已运行页面上的现有连接。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/text_clip.dart';
import '../../shared/util/timer_safety.dart';
import 'web_reverse_pure_helpers.dart';
import 'web_reverse_session_controller.dart';

const String _kBootstrap = r'''
(() => {
  if (window.__OH_WS_PATCHED__) return 'already';
  window.__OH_WS_PATCHED__ = true;
  window.__OH_WS_REGISTRY__ = window.__OH_WS_REGISTRY__ || {};
  let nextId = 1;
  const NativeWS = window.WebSocket;
  function PatchedWS(url, protocols) {
    const inst = protocols === undefined
      ? new NativeWS(url)
      : new NativeWS(url, protocols);
    const id = nextId++;
    inst.__oh_id = id;
    window.__OH_WS_REGISTRY__[id] = inst;
    inst.addEventListener('close', () => {
      try { delete window.__OH_WS_REGISTRY__[id]; } catch (_) {}
    });
    return inst;
  }
  PatchedWS.prototype = NativeWS.prototype;
  PatchedWS.CONNECTING = NativeWS.CONNECTING;
  PatchedWS.OPEN = NativeWS.OPEN;
  PatchedWS.CLOSING = NativeWS.CLOSING;
  PatchedWS.CLOSED = NativeWS.CLOSED;
  window.WebSocket = PatchedWS;
  return 'installed';
})();
''';

const String _kList = r'''
(() => {
  const reg = window.__OH_WS_REGISTRY__ || {};
  const out = [];
  for (const k of Object.keys(reg)) {
    const ws = reg[k];
    if (!ws) continue;
    out.push({
      id: Number(k),
      url: ws.url,
      readyState: ws.readyState,
      protocol: ws.protocol || '',
      bufferedAmount: ws.bufferedAmount,
    });
  }
  return JSON.stringify(out);
})();
''';

const int _kWsInjectMaxRows = 200;
const int _kWsInjectMaxPayloadChars = 512 * 1024;
const int _kWsInjectMaxLogPayloadChars = 64 * 1024;
const int _kWsInjectMaxUrlChars = 2048;
const int _kWsInjectMaxLogEntries = 60;

Future<void> showWebReverseWsInjectDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _WsInjectDialog(controller: controller),
  );
}

class _WsRow {
  _WsRow({
    required this.id,
    required this.url,
    required this.readyState,
    required this.protocol,
    required this.bufferedAmount,
  });
  final int id;
  final String url;
  final int readyState;
  final String protocol;
  final int bufferedAmount;

  String get readyStateLabel {
    switch (readyState) {
      case 0:
        return 'CONNECTING';
      case 1:
        return 'OPEN';
      case 2:
        return 'CLOSING';
      case 3:
        return 'CLOSED';
      default:
        return '?';
    }
  }
}

class _WsInjectDialog extends StatefulWidget {
  const _WsInjectDialog({required this.controller});
  final WebReverseSessionController controller;
  @override
  State<_WsInjectDialog> createState() => _WsInjectDialogState();
}

class _WsInjectDialogState extends State<_WsInjectDialog> {
  final TextEditingController _payloadCtrl = TextEditingController();
  bool _busy = false;
  bool _installed = false;
  String? _installError;
  List<_WsRow> _rows = const [];
  int? _selectedId;
  Timer? _pollTimer;
  final List<_LogEntry> _log = [];
  String? _scriptId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _install());
    _pollTimer = startNonOverlappingPeriodicTimer(
      const Duration(seconds: 2),
      (_) => _refresh(),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _removeBootstrapScript();
    _payloadCtrl.dispose();
    super.dispose();
  }

  void _removeBootstrapScript() {
    final scriptId = _scriptId;
    if (scriptId == null) return;
    _scriptId = null;
    unawaited(
      widget.controller.sendRawCdp(
        method: 'Page.removeScriptToEvaluateOnNewDocument',
        paramsJson: jsonEncode(<String, Object?>{'identifier': scriptId}),
        timeout: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _install() async {
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      // 注册 newDocument 钩子 → 刷新/跳转后自动应用。
      final addRes = await widget.controller.sendRawCdp(
        method: 'Page.addScriptToEvaluateOnNewDocument',
        paramsJson: jsonEncode(<String, Object?>{'source': _kBootstrap}),
      );
      if (addRes != null && addRes['error'] != null) {
        _installError = '${addRes['error']}';
      } else if (addRes != null && addRes['identifier'] != null) {
        _scriptId = '${addRes['identifier']}';
      }
      // 立即在当前 document 应用一次。
      final evalRes = await widget.controller.sendRawCdp(
        method: 'Runtime.evaluate',
        paramsJson: jsonEncode(<String, Object?>{
          'expression': _kBootstrap,
          'returnByValue': true,
        }),
      );
      if (evalRes != null && evalRes['error'] != null) {
        _installError = '${evalRes['error']}';
      } else {
        _installed = true;
      }
    } catch (e, st) {
      silentLog('web_reverse_ws_inject', 'install', e, st);
      _installError = '$e';
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    try {
      final res = await widget.controller.sendRawCdp(
        method: 'Runtime.evaluate',
        paramsJson: jsonEncode(<String, Object?>{
          'expression': _kList,
          'returnByValue': true,
        }),
      );
      if (res == null) return;
      final value = cdpStringResultValue(res);
      if (value == null) return;
      final decoded = decodeJsonList(value);
      if (decoded == null) return;
      final parsed = <_WsRow>[];
      for (final m in stringKeyedMapListFromValue(decoded)) {
        if (parsed.length >= _kWsInjectMaxRows) break;
        final id = optionalPositiveIntFromValue(m['id']);
        if (id == null) continue;
        parsed.add(
          _WsRow(
            id: id,
            url: _capWsInjectText('${m['url'] ?? ''}', _kWsInjectMaxUrlChars),
            readyState: clampedIntFromValue(
              m['readyState'],
              fallback: -1,
              min: -1,
              max: 3,
            ),
            protocol: _capWsInjectText('${m['protocol'] ?? ''}', 128),
            bufferedAmount: nonNegativeIntFromValue(
              m['bufferedAmount'],
              fallback: 0,
            ),
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _rows = parsed;
        if (_selectedId != null && !_rows.any((r) => r.id == _selectedId)) {
          _selectedId = null;
        }
      });
    } catch (e, st) {
      silentLog('web_reverse_ws_inject', 'refresh', e, st);
    }
  }

  Future<void> _send() async {
    final id = _selectedId;
    if (id == null) return;
    final raw = _payloadCtrl.text;
    if (raw.isEmpty) return;
    final loc = AppLocalizations.of(context);
    if (raw.length > _kWsInjectMaxPayloadChars) {
      final m = ScaffoldMessenger.maybeOf(context);
      if (m != null) {
        OpenHandSnackBar.showErrorOn(
          context,
          m,
          'Payload too large: ${raw.length}/$_kWsInjectMaxPayloadChars',
        );
      }
      return;
    }
    setState(() => _busy = true);
    try {
      final encoded = jsonEncode(raw);
      final expr =
          "window.__OH_WS_REGISTRY__ && "
          "window.__OH_WS_REGISTRY__[$id] && "
          "window.__OH_WS_REGISTRY__[$id].readyState === 1 "
          "? (window.__OH_WS_REGISTRY__[$id].send($encoded), 'sent') "
          ": 'not-open';";
      final res = await widget.controller.sendRawCdp(
        method: 'Runtime.evaluate',
        paramsJson: jsonEncode(<String, Object?>{
          'expression': expr,
          'returnByValue': true,
        }),
      );
      final value = cdpResultValue(res);
      final ok = value == 'sent';
      _log.insert(
        0,
        _LogEntry(
          at: DateTime.now(),
          ok: ok,
          summary: ok
              ? (loc?.webReverseWsInjectSentBytes(raw.length) ??
                    'Sent ${raw.length} bytes')
              : (loc?.webReverseWsInjectFailedReason('$value') ??
                    'Failed: $value'),
          payload: _capWsInjectText(raw, _kWsInjectMaxLogPayloadChars),
        ),
      );
      if (_log.length > _kWsInjectMaxLogEntries) _log.removeLast();
      if (!mounted) return;
      final m = ScaffoldMessenger.maybeOf(context);
      if (m != null) {
        if (ok) {
          OpenHandSnackBar.showSuccessOn(
            context,
            m,
            loc?.webReverseWsInjectInjected ?? 'Injected',
          );
        } else {
          OpenHandSnackBar.showErrorOn(
            context,
            m,
            loc?.webReverseWsInjectInjectFailed ?? 'Inject failed',
          );
        }
      }
    } catch (e, st) {
      silentLog('web_reverse_ws_inject', 'send', e, st);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);

    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: 880,
      maxHeight: 700,
      insetPadding: const EdgeInsets.all(24),
      child: Column(
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.wifi_tethering_rounded,
            title: loc?.webReverseWsInjectTitle ?? 'WebSocket Inject',
            subtitle:
                loc?.webReverseWsInjectSubtitle ??
                'All page-created WebSockets are proxied → pick one → inject any text frame',
            actions: [
              if (_installed)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    loc?.webReverseWsInjectProxyOn ?? 'PROXY ON',
                    style: TextStyle(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
          Divider(height: 1, color: cs.outlineVariant),
          if (_installError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${loc?.webReverseWsInjectInstallFailed ?? 'Install failed'}: $_installError',
                  style: TextStyle(color: cs.onErrorContainer, fontSize: 12),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Text(
                  loc?.webReverseWsInjectLiveCount(_rows.length) ??
                      '${_rows.length} live WebSocket(s)',
                  style: theme.textTheme.labelMedium,
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _busy ? null : _refresh,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: Text(loc?.webReverseWsInjectRefresh ?? 'Refresh'),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 160,
            child: _rows.isEmpty
                ? Center(
                    child: Text(
                      loc?.webReverseWsInjectNoLive ??
                          'No live WebSockets.\nRefresh the page to let the proxy intercept new ones.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 4),
                    itemBuilder: (_, i) {
                      final row = _rows[i];
                      final selected = row.id == _selectedId;
                      return Material(
                        color: selected
                            ? cs.primaryContainer.withValues(alpha: 0.4)
                            : cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => setState(() => _selectedId = row.id),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                            child: Row(
                              children: [
                                Icon(
                                  row.readyState == 1
                                      ? Icons.radio_button_checked_rounded
                                      : Icons.radio_button_off_rounded,
                                  size: 16,
                                  color: row.readyState == 1
                                      ? Colors.green
                                      : cs.onSurfaceVariant,
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 24,
                                  child: Text(
                                    '#${row.id}',
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    row.url,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  row.readyStateLabel,
                                  style: TextStyle(
                                    color: row.readyState == 1
                                        ? Colors.green
                                        : cs.onSurfaceVariant,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Divider(height: 16, color: cs.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _payloadCtrl,
              minLines: 4,
              maxLines: 8,
              maxLength: _kWsInjectMaxPayloadChars,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              buildCounter: _hideWsInjectCounter,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: InputDecoration(
                labelText:
                    loc?.webReverseWsInjectPayloadLabel ?? 'Text frame / JSON',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () async {
                    final clippedSnackBar = OpenHandSnackBar.info(
                      context,
                      'Pasted payload clipped to $_kWsInjectMaxPayloadChars chars',
                    );
                    final data = await Clipboard.getData('text/plain');
                    if (!mounted) return;
                    if (data?.text != null) {
                      final raw = data!.text!;
                      final clipped = raw.length > _kWsInjectMaxPayloadChars;
                      setState(
                        () => _payloadCtrl.text = _capWsInjectText(
                          raw,
                          _kWsInjectMaxPayloadChars,
                        ),
                      );
                      if (clipped) {
                        OpenHandGlobalSnackBarHost.showSnackBar(
                          clippedSnackBar,
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.paste_rounded, size: 16),
                  label: Text(loc?.webReverseWsInjectPaste ?? 'Paste'),
                ),
                const Spacer(),
                Text(
                  _selectedId == null
                      ? (loc?.webReverseWsInjectPickTarget ?? 'Pick a target')
                      : '${loc?.webReverseWsInjectTargetLabel ?? 'Target'}: #$_selectedId',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: _log.isEmpty
                  ? Center(
                      child: Text(
                        loc?.webReverseWsInjectLogEmpty ??
                            'Inject log appears here',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: _log.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 4),
                      itemBuilder: (_, i) {
                        final e = _log[i];
                        return Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: e.ok
                                ? cs.primaryContainer.withValues(alpha: 0.2)
                                : cs.errorContainer.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                e.ok
                                    ? Icons.check_circle_rounded
                                    : Icons.error_rounded,
                                size: 14,
                                color: e.ok ? Colors.green : cs.error,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${_fmt(e.at)} · ${e.summary}',
                                      style: theme.textTheme.labelSmall,
                                    ),
                                    Text(
                                      e.payload.length > 200
                                          ? '${e.payload.substring(0, 200)}…'
                                          : e.payload,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OpenHandDialogActionButton.secondary(
                  label: loc?.webReverseWsInjectClose ?? 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                OpenHandDialogActionButton.primary(
                  label: loc?.webReverseWsInjectSend ?? 'Send',
                  onPressed:
                      _selectedId == null || _payloadCtrl.text.isEmpty || _busy
                      ? null
                      : _send,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
}

class _LogEntry {
  _LogEntry({
    required this.at,
    required this.ok,
    required this.summary,
    required this.payload,
  });
  final DateTime at;
  final bool ok;
  final String summary;
  final String payload;
}

String _capWsInjectText(String text, int maxChars) {
  return clipText(text, maxChars, suffix: '');
}

Widget? _hideWsInjectCounter(
  BuildContext context, {
  required int currentLength,
  required bool isFocused,
  required int? maxLength,
}) => null;
