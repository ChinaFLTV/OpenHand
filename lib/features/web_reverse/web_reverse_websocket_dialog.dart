/// WebSocket 帧查看 + 重放面板。
///
/// 左侧列出会话内的 WebSocket / EventSource 连接，右侧显示该连接的所有帧。
/// 「重放」按钮在页面上下文里开新 WebSocket(url) 并按顺序 send() 所有
/// `sent` 帧（接收帧仅展示，无法主动注入）。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/support/silent_log.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseWebSocketDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
  required bool isZh,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _WsDialog(controller: controller, isZh: isZh),
  );
}

class _WsDialog extends StatefulWidget {
  const _WsDialog({required this.controller, required this.isZh});
  final WebReverseSessionController controller;
  final bool isZh;
  @override
  State<_WsDialog> createState() => _WsDialogState();
}

class _WsDialogState extends State<_WsDialog> {
  String? _selectedId;
  String _status = '';
  bool _busy = false;

  List<CdpNetworkEntry> get _connections =>
      widget.controller.networkRequests.where((e) => e.isWebSocket).toList();

  CdpNetworkEntry? get _selected {
    if (_selectedId == null) return null;
    for (final e in _connections) {
      if (e.requestId == _selectedId) return e;
    }
    return null;
  }

  Future<void> _copyFramesJson() async {
    final e = _selected;
    if (e == null) return;
    final data = e.wsFrames
        .map((f) => {
              'direction': f.direction.name,
              'ts': f.timestamp.toIso8601String(),
              'opcode': f.opcode,
              'mask': f.mask,
              'payload': f.payload,
              if (f.errorMessage != null) 'error': f.errorMessage,
            })
        .toList();
    try {
      await Clipboard.setData(
        ClipboardData(text: const JsonEncoder.withIndent('  ').convert(data)),
      );
    } catch (err, st) {
      silentLog('web-reverse', 'ws.copy', err, st);
      return;
    }
    if (!mounted) return;
    final m = ScaffoldMessenger.maybeOf(context);
    if (m != null) {
      OpenHandSnackBar.showSuccessOn(
        context,
        m,
        widget.isZh ? '帧 JSON 已复制' : 'Frames JSON copied',
      );
    }
  }

  Future<void> _replaySent() async {
    final e = _selected;
    if (e == null) return;
    final isZh = widget.isZh;
    final sentFrames = e.wsFrames
        .where((f) => f.direction == CdpWebSocketDirection.sent)
        .map((f) => f.payload)
        .toList();
    if (sentFrames.isEmpty) {
      setState(() => _status = isZh ? '该连接没有发送帧可重放' : 'No sent frames');
      return;
    }
    setState(() {
      _busy = true;
      _status =
          isZh ? '在页面打开新 WS 并按序重放...' : 'Opening WS and replaying...';
    });
    final js = '''
(async () => {
  try {
    const url = ${jsonEncode(e.url)};
    const ws = new WebSocket(url);
    const frames = ${jsonEncode(sentFrames)};
    const result = await new Promise((resolve) => {
      let sent = 0;
      const received = [];
      let timer = null;
      ws.addEventListener('open', () => {
        const tick = () => {
          if (sent >= frames.length) {
            timer = setTimeout(() => {
              try { ws.close(); } catch (_) {}
              resolve({ ok: true, sent, received });
            }, 800);
            return;
          }
          try { ws.send(frames[sent]); } catch (err) {
            resolve({ ok: false, sent, error: String(err), received });
            return;
          }
          sent += 1;
          setTimeout(tick, 30);
        };
        tick();
      });
      ws.addEventListener('message', (ev) => {
        if (received.length < 16) {
          const data = typeof ev.data === 'string' ? ev.data : '<binary>';
          received.push(data.length > 256 ? data.slice(0, 256) + '…' : data);
        }
      });
      ws.addEventListener('error', () => {
        if (timer) clearTimeout(timer);
        resolve({ ok: false, sent, error: 'ws error', received });
      });
      setTimeout(() => {
        if (timer) clearTimeout(timer);
        try { ws.close(); } catch (_) {}
        resolve({ ok: true, sent, received, timeout: true });
      }, 8000);
    });
    return JSON.stringify(result);
  } catch (err) {
    return JSON.stringify({ ok: false, error: String(err) });
  }
})()
''';
    try {
      final r = await widget.controller.sendRawCdp(
        method: 'Runtime.evaluate',
        paramsJson: jsonEncode({
          'expression': js,
          'awaitPromise': true,
          'returnByValue': true,
        }),
      );
      final raw = (r?['result'] as Map?)?['value'];
      if (raw is! String) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _status = isZh ? '重放返回值异常' : 'Bad eval result';
        });
        return;
      }
      final res = jsonDecode(raw) as Map<String, Object?>;
      final sent = (res['sent'] is num) ? (res['sent'] as num).toInt() : 0;
      final ok = res['ok'] == true;
      final received =
          (res['received'] as List?)?.cast<Object?>().map((x) => '$x').toList() ??
              const <String>[];
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = ok
            ? (isZh
                ? '完成：已发送 $sent 条，收到 ${received.length} 条'
                : 'Done: sent $sent, received ${received.length}')
            : (isZh
                ? '失败：sent=$sent err=${res['error']}'
                : 'Failed: sent=$sent err=${res['error']}');
      });
    } catch (err, st) {
      silentLog('web-reverse', 'ws.replay', err, st);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Error: $err';
      });
    }
  }

  String _opName(int op) {
    switch (op) {
      case 1:
        return 'text';
      case 2:
        return 'binary';
      case 8:
        return 'close';
      case 9:
        return 'ping';
      case 10:
        return 'pong';
      default:
        return 'op$op';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isZh = widget.isZh;
    final conns = _connections;
    final cur = _selected;
    if (_selectedId == null && conns.isNotEmpty) {
      _selectedId = conns.last.requestId;
    }
    return Dialog(
      backgroundColor: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 760),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
              child: Row(
                children: [
                  Icon(Icons.swap_horiz_rounded, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isZh ? 'WebSocket 帧录制 / 重放' : 'WebSocket Frames',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          isZh
                              ? '查看帧 · 重放 sent 帧到新连接'
                              : 'inspect frames · replay sent frames in new ws',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: cur == null ? null : _copyFramesJson,
                    icon: const Icon(Icons.copy_rounded),
                    tooltip: isZh ? '复制帧 JSON' : 'Copy frames JSON',
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
              child: conns.isEmpty
                  ? Center(
                      child: Text(
                        isZh
                            ? '当前会话没有 WebSocket / EventSource 连接'
                            : 'No WebSocket / EventSource connections',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 280,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(8, 10, 4, 10),
                            itemCount: conns.length,
                            itemBuilder: (_, i) {
                              final c = conns[i];
                              final picked = c.requestId == _selectedId;
                              return InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () =>
                                    setState(() => _selectedId = c.requestId),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: picked
                                        ? cs.primaryContainer
                                            .withValues(alpha: 0.4)
                                        : cs.surfaceContainerHigh,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: picked
                                          ? cs.primary
                                          : cs.outlineVariant,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        c.url,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 11,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${c.wsFrames.length} ${isZh ? '帧' : 'frames'}',
                                        style: theme.textTheme.labelSmall,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        VerticalDivider(width: 1, color: cs.outlineVariant),
                        Expanded(
                          child: cur == null
                              ? const SizedBox.shrink()
                              : Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          12, 10, 12, 6),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: SelectableText(
                                              cur.url,
                                              style: const TextStyle(
                                                fontFamily: 'monospace',
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                          FilledButton.icon(
                                            onPressed: _busy
                                                ? null
                                                : _replaySent,
                                            icon: const Icon(
                                                Icons.send_rounded),
                                            label: Text(isZh
                                                ? '重放 sent 帧'
                                                : 'Replay sent'),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_busy)
                                      const LinearProgressIndicator(
                                          minHeight: 3),
                                    Expanded(
                                      child: ListView.builder(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 6),
                                        itemCount: cur.wsFrames.length,
                                        itemBuilder: (_, i) {
                                          final f = cur.wsFrames[i];
                                          final isSent = f.direction ==
                                              CdpWebSocketDirection.sent;
                                          final isErr = f.direction ==
                                              CdpWebSocketDirection.error;
                                          return Container(
                                            margin: const EdgeInsets.only(
                                                bottom: 4),
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: isErr
                                                  ? cs.errorContainer
                                                      .withValues(alpha: 0.5)
                                                  : isSent
                                                      ? cs.primaryContainer
                                                          .withValues(
                                                              alpha: 0.18)
                                                      : cs.surfaceContainerHigh,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                  color: cs.outlineVariant),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Icon(
                                                      isErr
                                                          ? Icons
                                                              .error_outline_rounded
                                                          : isSent
                                                              ? Icons
                                                                  .north_east_rounded
                                                              : Icons
                                                                  .south_west_rounded,
                                                      size: 14,
                                                      color: isErr
                                                          ? cs.error
                                                          : isSent
                                                              ? cs.primary
                                                              : cs.tertiary,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      _opName(f.opcode),
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color:
                                                            cs.onSurfaceVariant,
                                                      ),
                                                    ),
                                                    const Spacer(),
                                                    Text(
                                                      f.timestamp
                                                          .toIso8601String()
                                                          .substring(11, 23),
                                                      style: TextStyle(
                                                        fontFamily: 'monospace',
                                                        fontSize: 10,
                                                        color: cs
                                                            .onSurfaceVariant
                                                            .withValues(
                                                                alpha: 0.7),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                SelectableText(
                                                  f.payload.length > 800
                                                      ? '${f.payload.substring(0, 800)}…'
                                                      : f.payload,
                                                  style: const TextStyle(
                                                    fontFamily: 'monospace',
                                                    fontSize: 11,
                                                  ),
                                                ),
                                                if (f.errorMessage != null)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            top: 3),
                                                    child: Text(
                                                      f.errorMessage!,
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: cs.error,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ],
                    ),
            ),
            if (_status.isNotEmpty)
              Container(
                width: double.infinity,
                color: cs.surfaceContainerHigh,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  _status,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: OpenHandDialogActionButton.primary(
                  label: isZh ? '关闭' : 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
