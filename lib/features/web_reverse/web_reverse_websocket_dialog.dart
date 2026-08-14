/// WebSocket 帧查看 + 重放面板。
///
/// 左侧列出会话内的 WebSocket / EventSource 连接，右侧显示该连接的所有帧。
/// 「重放」按钮在页面上下文里开新 WebSocket(url) 并按顺序 send() 所有
/// `sent` 帧（接收帧仅展示，无法主动注入）。
library;

import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_busy_indicators.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_inline_empty_state.dart';
import '../../shared/ui/openhand_spacing.dart';
import '../../shared/ui/openhand_typography.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/localized_text.dart';
import '../../shared/util/text_clip.dart';
import 'web_reverse_clipboard.dart';
import 'web_reverse_dialog_utils.dart';
import 'web_reverse_pure_helpers.dart';
import 'web_reverse_session_controller.dart';

const int _kJsonFuzzMaxSafeInteger = 9007199254740991;
const int _kJsonFuzzMinSafeInteger = -_kJsonFuzzMaxSafeInteger;
const String _kJsonFuzzUnsafeIntegerText = '9007199254740993';
const int _kWsEvalCloseDelayMs = 800;
const int _kWsEvalDefaultDelayMs = 30;
const int _kWsEvalDefaultReceiveLimit = 32;
const int _kWsEvalDefaultPreviewChars = 512;
const int _kWsEvalDefaultTimeoutMs = 8000;
const int _kWsReplayReceiveLimit = 16;
const int _kWsReplayPreviewChars = 256;
const int _kWsEditTimeoutMs = 5000;
const int _kWsFuzzBaseTimeoutMs = 6000;
const double _kWsDialogActionSpacing = 10;
final String _jsonFuzzLongString = 'A' * 1024;

Future<void> showWebReverseWebSocketDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) {
  return webReverseToolDialogs.show<void>(
    context: context,
    builder: (_) => _WsDialog(controller: controller),
  );
}

class _WsDialog extends StatefulWidget {
  const _WsDialog({required this.controller});
  final WebReverseSessionController controller;
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
        .map(
          (f) => {
            'direction': f.direction.name,
            'ts': f.timestamp.toIso8601String(),
            'opcode': f.opcode,
            'mask': f.mask,
            'payload': f.payload,
            if (f.errorMessage != null) 'error': f.errorMessage,
          },
        )
        .toList();
    await copyWebReverseTextToClipboard(
      context: context,
      text: prettyPrintJson(data),
      successBase: openHandLocalizedText(
        context,
        zh: '帧 JSON 已复制',
        zhHant: '影格 JSON 已複製',
        en: 'Frames JSON copied',
        fr: 'JSON des trames copié',
        de: 'Frame-JSON kopiert',
        ja: 'フレーム JSON をコピーしました',
      ),
      logTag: 'web_reverse_websocket_dialog',
    );
  }

  Future<void> _replaySent() async {
    final e = _selected;
    if (e == null) return;
    final sentFrames = e.wsFrames
        .where((f) => f.direction == CdpWebSocketDirection.sent)
        .map((f) => f.payload)
        .toList();
    if (sentFrames.isEmpty) {
      setState(
        () => _status = openHandLocalizedText(
          context,
          zh: '该连接没有发送帧可重放',
          zhHant: '此連線沒有可重放的送出影格',
          en: 'No sent frames',
          fr: 'Aucune trame envoyée',
          de: 'Keine gesendeten Frames',
          ja: '再生できる送信フレームがありません',
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _status = openHandLocalizedText(
        context,
        zh: '在页面打开新 WS 并按序重放...',
        zhHant: '正在頁面開啟新 WS 並依序重放...',
        en: 'Opening WS and replaying...',
        fr: 'Ouverture du WS et relecture...',
        de: 'WS wird geöffnet und wiederholt...',
        ja: 'WS を開いて順にリプレイしています...',
      );
    });
    try {
      final res = await _evalSendFrames(
        e.url,
        sentFrames,
        receiveLimit: _kWsReplayReceiveLimit,
        previewChars: _kWsReplayPreviewChars,
      );
      if (res == null) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _status = openHandLocalizedText(
            context,
            zh: '重放返回值异常',
            zhHant: '重放回傳值異常',
            en: 'Bad eval result',
            fr: 'Résultat eval invalide',
            de: 'Ungültiges Eval-Ergebnis',
            ja: 'eval の戻り値が不正です',
          );
        });
        return;
      }
      final sent = nonNegativeIntFromValue(res['sent'], fallback: 0);
      final ok = res['ok'] == true;
      final received = stringListFromValue(res['received']);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = ok
            ? openHandLocalizedText(
                context,
                zh: '完成：已发送 $sent 条，收到 ${received.length} 条',
                zhHant: '完成：已送出 $sent 條，收到 ${received.length} 條',
                en: 'Done: sent $sent, received ${received.length}',
                fr: 'Terminé : $sent envoyées, ${received.length} reçues',
                de: 'Fertig: $sent gesendet, ${received.length} empfangen',
                ja: '完了: $sent 件送信、${received.length} 件受信',
              )
            : openHandLocalizedText(
                context,
                zh: '失败：sent=$sent err=${res['error']}',
                zhHant: '失敗：sent=$sent err=${res['error']}',
                en: 'Failed: sent=$sent err=${res['error']}',
                fr: 'Échec : sent=$sent err=${res['error']}',
                de: 'Fehlgeschlagen: sent=$sent err=${res['error']}',
                ja: '失敗: sent=$sent err=${res['error']}',
              );
      });
    } catch (err, st) {
      silentLog('web_reverse_websocket_dialog', '重放 WebSocket 消息', err, st);
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

  /// 在页面里开一条新 WebSocket，按顺序发送 [frames]，可选间隔 [delayMs]。
  /// 返回 `{ok, sent, received, error?}`。
  Future<Map<String, Object?>?> _evalSendFrames(
    String url,
    List<String> frames, {
    int delayMs = _kWsEvalDefaultDelayMs,
    int timeoutMs = _kWsEvalDefaultTimeoutMs,
    int receiveLimit = _kWsEvalDefaultReceiveLimit,
    int previewChars = _kWsEvalDefaultPreviewChars,
  }) async {
    final js =
        '''
(async () => {
  try {
    const url = ${jsonEncode(url)};
    const frames = ${jsonEncode(frames)};
    const delay = ${jsonEncode(delayMs)};
    const receiveLimit = ${jsonEncode(receiveLimit)};
    const previewChars = ${jsonEncode(previewChars)};
    const ws = new WebSocket(url);
    const result = await new Promise((resolve) => {
      let sent = 0;
      const received = [];
      let closeTimer = null;
      let timeoutTimer = null;
      let settled = false;
      const cleanup = () => {
        if (closeTimer) clearTimeout(closeTimer);
        if (timeoutTimer) clearTimeout(timeoutTimer);
        closeTimer = null;
        timeoutTimer = null;
      };
      const finish = (value) => {
        if (settled) return;
        settled = true;
        cleanup();
        resolve(value);
      };
      ws.addEventListener('open', () => {
        const tick = () => {
          if (settled) return;
          if (sent >= frames.length) {
            closeTimer = setTimeout(() => {
              try { ws.close(); } catch (_) {}
              finish({ ok: true, sent, received });
            }, ${jsonEncode(_kWsEvalCloseDelayMs)});
            return;
          }
          try { ws.send(frames[sent]); } catch (err) {
            finish({ ok: false, sent, error: String(err), received });
            return;
          }
          sent += 1;
          setTimeout(tick, delay);
        };
        tick();
      });
      ws.addEventListener('message', (ev) => {
        if (received.length < receiveLimit) {
          const data = typeof ev.data === 'string' ? ev.data : '<binary>';
          received.push(data.length > previewChars ? data.slice(0, previewChars) + '…' : data);
        }
      });
      ws.addEventListener('error', () => {
        finish({ ok: false, sent, error: 'ws error', received });
      });
      timeoutTimer = setTimeout(() => {
        try { ws.close(); } catch (_) {}
        finish({ ok: true, sent, received, timeout: true });
      }, ${jsonEncode(timeoutMs)});
    });
    return JSON.stringify(result);
  } catch (err) {
    return JSON.stringify({ ok: false, error: String(err) });
  }
})()
''';
    final r = await widget.controller.evaluateJavaScript(
      js,
      awaitPromise: true,
    );
    return cdpJsonMapStringResultValue(r);
  }

  Future<void> _editAndSend(String basePayload) async {
    final e = _selected;
    if (e == null) return;
    final edited = await _showEditFrameDialog(basePayload);
    if (edited == null || !mounted) return;
    setState(() {
      _busy = true;
      _status = openHandLocalizedText(
        context,
        zh: '发送单帧...',
        zhHant: '正在傳送單一影格...',
        en: 'Sending edited frame...',
        fr: 'Envoi de la trame modifiée...',
        de: 'Bearbeiteter Frame wird gesendet...',
        ja: '編集したフレームを送信しています...',
      );
    });
    try {
      final res = await _evalSendFrames(e.url, [
        edited,
      ], timeoutMs: _kWsEditTimeoutMs);
      if (!mounted) return;
      if (res == null) {
        setState(() {
          _busy = false;
          _status = openHandLocalizedText(
            context,
            zh: '发送失败：返回值异常',
            zhHant: '傳送失敗：回傳值異常',
            en: 'Bad eval result',
            fr: 'Résultat eval invalide',
            de: 'Ungültiges Eval-Ergebnis',
            ja: 'eval の戻り値が不正です',
          );
        });
        return;
      }
      final ok = res['ok'] == true;
      final recv = stringListFromValue(res['received']).length;
      setState(() {
        _busy = false;
        _status = ok
            ? openHandLocalizedText(
                context,
                zh: '已发送 1 条，收到 $recv 条',
                zhHant: '已送出 1 條，收到 $recv 條',
                en: 'Sent 1, received $recv',
                fr: '1 envoyée, $recv reçues',
                de: '1 gesendet, $recv empfangen',
                ja: '1 件送信、$recv 件受信',
              )
            : openHandLocalizedText(
                context,
                zh: '失败：${res['error']}',
                zhHant: '失敗：${res['error']}',
                en: 'Failed: ${res['error']}',
                fr: 'Échec : ${res['error']}',
                de: 'Fehlgeschlagen: ${res['error']}',
                ja: '失敗: ${res['error']}',
              );
      });
    } catch (err, st) {
      silentLog('web_reverse_websocket_dialog', '编辑并发送 WebSocket 消息', err, st);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Error: $err';
      });
    }
  }

  Future<void> _fuzz(String basePayload) async {
    final e = _selected;
    if (e == null) return;
    final cfg = await _showFuzzConfigDialog(basePayload);
    if (cfg == null || !mounted) return;
    final mutated = <String>[];
    final rng = Random();
    for (var i = 0; i < cfg.count; i++) {
      mutated.add(_mutatePayload(basePayload, rng, intensity: cfg.intensity));
    }
    setState(() {
      _busy = true;
      _status = openHandLocalizedText(
        context,
        zh: 'Fuzz 中：发送 ${cfg.count} 条变异帧...',
        zhHant: 'Fuzz 中：傳送 ${cfg.count} 條變異影格...',
        en: 'Fuzzing ${cfg.count}...',
        fr: 'Fuzzing de ${cfg.count} trames...',
        de: 'Fuzzing von ${cfg.count} Frames...',
        ja: '${cfg.count} 件の変異フレームを fuzz しています...',
      );
    });
    try {
      final res = await _evalSendFrames(
        e.url,
        mutated,
        delayMs: cfg.delayMs,
        timeoutMs: _kWsFuzzBaseTimeoutMs + cfg.count * cfg.delayMs,
      );
      if (!mounted) return;
      if (res == null) {
        setState(() {
          _busy = false;
          _status = openHandLocalizedText(
            context,
            zh: 'Fuzz 失败：返回值异常',
            zhHant: 'Fuzz 失敗：回傳值異常',
            en: 'Fuzz bad eval',
            fr: 'Eval fuzz invalide',
            de: 'Ungültiges Fuzz-Eval',
            ja: 'Fuzz の eval 結果が不正です',
          );
        });
        return;
      }
      final ok = res['ok'] == true;
      final sent = nonNegativeIntFromValue(res['sent'], fallback: 0);
      final recv = stringListFromValue(res['received']).length;
      setState(() {
        _busy = false;
        _status = ok
            ? openHandLocalizedText(
                context,
                zh: 'Fuzz 完成：发送 $sent 条，收到 $recv 条',
                zhHant: 'Fuzz 完成：送出 $sent 條，收到 $recv 條',
                en: 'Fuzz done: sent $sent, recv $recv',
                fr: 'Fuzz terminé : $sent envoyées, $recv reçues',
                de: 'Fuzz fertig: $sent gesendet, $recv empfangen',
                ja: 'Fuzz 完了: $sent 件送信、$recv 件受信',
              )
            : openHandLocalizedText(
                context,
                zh: 'Fuzz 失败：sent=$sent err=${res['error']}',
                zhHant: 'Fuzz 失敗：sent=$sent err=${res['error']}',
                en: 'Fuzz failed: $sent err=${res['error']}',
                fr: 'Fuzz échoué : sent=$sent err=${res['error']}',
                de: 'Fuzz fehlgeschlagen: sent=$sent err=${res['error']}',
                ja: 'Fuzz 失敗: sent=$sent err=${res['error']}',
              );
      });
    } catch (err, st) {
      silentLog('web_reverse_websocket_dialog', '模糊测试 WebSocket 消息', err, st);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Error: $err';
      });
    }
  }

  /// 按 [intensity] (1-5) 对 [payload] 做随机变异。
  /// 优先把 payload 当 JSON：随机挑一个叶子值改成边界值/类型反转。
  /// 否则按字节随机翻转 / 插入 / 截断。
  String _mutatePayload(String payload, Random rng, {int intensity = 2}) {
    Object? parsed;
    try {
      parsed = jsonDecode(payload);
    } catch (_) {
      parsed = null;
    }
    if (parsed is Map || parsed is List) {
      final rounds = intensity.clamp(1, 5);
      for (var i = 0; i < rounds; i++) {
        _mutateJsonInPlace(parsed!, rng);
      }
      try {
        return jsonEncode(parsed);
      } catch (_) {
        /* fallthrough */
      }
    }
    // 字节级 fuzz
    final bytes = utf8.encode(payload).toList();
    if (bytes.isEmpty) return payload;
    final ops = intensity.clamp(1, 5);
    for (var i = 0; i < ops; i++) {
      final pick = rng.nextInt(4);
      switch (pick) {
        case 0: // 翻转
          final pos = rng.nextInt(bytes.length);
          bytes[pos] = bytes[pos] ^ (1 << rng.nextInt(8)) & 0xff;
        case 1: // 插入
          bytes.insert(rng.nextInt(bytes.length + 1), rng.nextInt(256));
        case 2: // 删除
          if (bytes.length > 1) bytes.removeAt(rng.nextInt(bytes.length));
        case 3: // 截断或填充
          if (rng.nextBool() && bytes.length > 4) {
            bytes.length = rng.nextInt(bytes.length);
          } else {
            bytes.addAll(
              List.generate(4 + rng.nextInt(16), (_) => rng.nextInt(256)),
            );
          }
      }
    }
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return String.fromCharCodes(bytes);
    }
  }

  void _mutateJsonInPlace(Object node, Random rng) {
    final boundaries = <Object?>[
      null,
      0,
      -1,
      1,
      2147483647,
      -2147483648,
      _kJsonFuzzMaxSafeInteger,
      _kJsonFuzzMinSafeInteger,
      _kJsonFuzzUnsafeIntegerText,
      1.7e308,
      double.nan,
      double.infinity,
      '',
      '<script>alert(1)</script>',
      "' OR 1=1--",
      _jsonFuzzLongString,
      true,
      false,
      <Object?>[],
      <String, Object?>{},
    ];
    if (node is Map<String, Object?>) {
      if (node.isEmpty) return;
      final keys = node.keys.toList();
      final key = keys[rng.nextInt(keys.length)];
      final v = node[key];
      if (v is Map || v is List) {
        _mutateJsonInPlace(v!, rng);
      } else {
        node[key] = boundaries[rng.nextInt(boundaries.length)];
      }
    } else if (node is List) {
      if (node.isEmpty) return;
      final idx = rng.nextInt(node.length);
      final v = node[idx];
      if (v is Map || v is List) {
        _mutateJsonInPlace(v!, rng);
      } else {
        node[idx] = boundaries[rng.nextInt(boundaries.length)];
      }
    }
  }

  Future<String?> _showEditFrameDialog(String initial) async {
    final ctrl = TextEditingController(text: initial);
    try {
      return await webReverseToolDialogs.show<String>(
        context: context,
        builder: (ctx) {
          final cs = Theme.of(ctx).colorScheme;
          return buildOpenHandToolDialogShell(
            context: ctx,
            maxWidth: kOpenHandDialogWidthStandard,
            maxHeight: kOpenHandDialogHeightCompact,
            child: Column(
              children: [
                buildOpenHandToolDialogHeader(
                  context: ctx,
                  icon: Icons.edit_note_rounded,
                  title: openHandLocalizedText(
                    ctx,
                    zh: '编辑单帧再发送',
                    zhHant: '編輯單一影格後傳送',
                    en: 'Edit frame & send',
                    fr: 'Modifier puis envoyer',
                    de: 'Frame bearbeiten und senden',
                    ja: 'フレームを編集して送信',
                  ),
                ),
                Divider(height: 1, color: cs.outlineVariant),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: TextField(
                      controller: ctrl,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      style: const TextStyle(
                        fontFamily: kOpenHandMonospaceFontFamily,
                        fontSize: 12,
                      ),
                      decoration: InputDecoration(
                        hintText: openHandLocalizedText(
                          ctx,
                          zh: '在这里修改 payload，然后点发送',
                          zhHant: '在這裡修改 payload，然後點傳送',
                          en: 'Edit payload, then send',
                          fr: 'Modifiez le payload, puis envoyez',
                          de: 'Payload bearbeiten, dann senden',
                          ja: 'payload を編集してから送信',
                        ),
                        filled: true,
                        fillColor: cs.surface,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                ),
                Divider(height: 1, color: cs.outlineVariant),
                _buildFrameDialogActionRow(
                  ctx,
                  primaryIcon: Icons.send_rounded,
                  primaryLabel: openHandLocalizedText(
                    ctx,
                    zh: '发送',
                    zhHant: '傳送',
                    en: 'Send',
                    fr: 'Envoyer',
                    de: 'Senden',
                    ja: '送信',
                  ),
                  onPrimaryPressed: () => Navigator.of(ctx).pop(ctrl.text),
                ),
              ],
            ),
          );
        },
      );
    } finally {
      ctrl.dispose();
    }
  }

  Future<_FuzzConfig?> _showFuzzConfigDialog(String basePayload) async {
    final countCtrl = TextEditingController(text: '20');
    final delayCtrl = TextEditingController(text: '50');
    var intensity = 2;
    try {
      return await showOpenHandStatefulDialog<_FuzzConfig>(
        context: context,
        builder: (ctx, setLocal) {
          final cs = Theme.of(ctx).colorScheme;
          return buildOpenHandToolDialogShell(
            context: ctx,
            maxWidth: kOpenHandDialogWidthCompact,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                buildOpenHandToolDialogHeader(
                  context: ctx,
                  icon: Icons.bug_report_rounded,
                  iconColor: cs.tertiary,
                  title: openHandLocalizedText(
                    ctx,
                    zh: 'Fuzz 帧（按 JSON 叶子或字节变异）',
                    zhHant: 'Fuzz 影格（依 JSON 葉節點或位元組變異）',
                    en: 'Fuzz frame',
                    fr: 'Fuzz de trame',
                    de: 'Frame fuzzing',
                    ja: 'フレームを fuzz',
                  ),
                ),
                Divider(height: 1, color: cs.outlineVariant),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        openHandLocalizedText(
                          ctx,
                          zh: '基准 payload 长度：${basePayload.length} 字符',
                          zhHant: '基準 payload 長度：${basePayload.length} 字元',
                          en: 'Base payload: ${basePayload.length} chars',
                          fr: 'Payload de base : ${basePayload.length} caractères',
                          de: 'Basis-Payload: ${basePayload.length} Zeichen',
                          ja: '基準 payload: ${basePayload.length} 文字',
                        ),
                        style: Theme.of(ctx).textTheme.labelSmall,
                      ),
                      kOpenHandGap8,
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: countCtrl,
                              decoration: InputDecoration(
                                labelText: openHandLocalizedText(
                                  ctx,
                                  zh: '发送次数 (1-200)',
                                  zhHant: '傳送次數 (1-200)',
                                  en: 'Count (1-200)',
                                  fr: 'Nombre (1-200)',
                                  de: 'Anzahl (1-200)',
                                  ja: '回数 (1-200)',
                                ),
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: _kWsDialogActionSpacing),
                          Expanded(
                            child: TextField(
                              controller: delayCtrl,
                              decoration: InputDecoration(
                                labelText: openHandLocalizedText(
                                  ctx,
                                  zh: '间隔 ms (10-1000)',
                                  zhHant: '間隔 ms (10-1000)',
                                  en: 'Delay ms (10-1000)',
                                  fr: 'Délai ms (10-1000)',
                                  de: 'Pause ms (10-1000)',
                                  ja: '間隔 ms (10-1000)',
                                ),
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      kOpenHandGap14,
                      Text(
                        openHandLocalizedText(
                          ctx,
                          zh: '变异强度',
                          zhHant: '變異強度',
                          en: 'Intensity',
                          fr: 'Intensité',
                          de: 'Intensität',
                          ja: '強度',
                        ),
                        style: Theme.of(ctx).textTheme.labelSmall,
                      ),
                      Slider(
                        value: intensity.toDouble(),
                        min: 1,
                        max: 5,
                        divisions: 4,
                        label: '$intensity',
                        onChanged: (v) => setLocal(() => intensity = v.round()),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: cs.outlineVariant),
                _buildFrameDialogActionRow(
                  ctx,
                  primaryIcon: Icons.play_arrow_rounded,
                  primaryLabel: openHandLocalizedText(
                    ctx,
                    zh: '开始 Fuzz',
                    zhHant: '開始 Fuzz',
                    en: 'Start Fuzz',
                    fr: 'Démarrer le fuzz',
                    de: 'Fuzz starten',
                    ja: 'Fuzz 開始',
                  ),
                  onPrimaryPressed: () {
                    Navigator.of(ctx).pop(
                      _FuzzConfig(
                        count: clampedIntFromValue(
                          countCtrl.text,
                          fallback: 20,
                          min: 1,
                          max: 200,
                        ),
                        delayMs: clampedIntFromValue(
                          delayCtrl.text,
                          fallback: 50,
                          min: 10,
                          max: 1000,
                        ),
                        intensity: intensity,
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      );
    } finally {
      countCtrl.dispose();
      delayCtrl.dispose();
    }
  }

  Widget _buildFrameDialogActionRow(
    BuildContext ctx, {
    required IconData primaryIcon,
    required String primaryLabel,
    required VoidCallback onPrimaryPressed,
  }) {
    return buildOpenHandDialogActionsBar(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      spacing: _kWsDialogActionSpacing,
      actions: [
        OpenHandDialogActionButton.secondary(
          label: openHandCancelLabel(ctx),
          onPressed: () => Navigator.of(ctx).pop(),
        ),
        OpenHandDialogActionButton.primary(
          icon: primaryIcon,
          label: primaryLabel,
          onPressed: onPrimaryPressed,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final conns = _connections;
    final cur = _selected;
    if (_selectedId == null && conns.isNotEmpty) {
      _selectedId = conns.last.requestId;
    }
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthExtraWide,
      maxHeight: kOpenHandDialogHeightTall,
      child: Column(
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.swap_horiz_rounded,
            title: openHandLocalizedText(
              context,
              zh: 'WebSocket 帧录制 / 重放',
              zhHant: 'WebSocket 影格錄製 / 重放',
              en: 'WebSocket Frames',
              fr: 'Trames WebSocket',
              de: 'WebSocket-Frames',
              ja: 'WebSocket フレーム',
            ),
            subtitle: openHandLocalizedText(
              context,
              zh: '查看帧 · 重放 sent 帧到新连接',
              zhHant: '查看影格 · 將 sent 影格重放到新連線',
              en: 'inspect frames · replay sent frames in new ws',
              fr: 'inspecter les trames · rejouer les trames envoyées',
              de: 'Frames prüfen · gesendete Frames in neuer WS wiederholen',
              ja: 'フレーム確認 · sent フレームを新しい WS にリプレイ',
            ),
            actions: [
              IconButton(
                onPressed: cur == null ? null : _copyFramesJson,
                icon: const Icon(Icons.copy_rounded),
                tooltip: openHandLocalizedText(
                  context,
                  zh: '复制帧 JSON',
                  zhHant: '複製影格 JSON',
                  en: 'Copy frames JSON',
                  fr: 'Copier le JSON des trames',
                  de: 'Frame-JSON kopieren',
                  ja: 'フレーム JSON をコピー',
                ),
              ),
            ],
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Expanded(
            child: conns.isEmpty
                ? OpenHandInlineEmptyState(
                    message: openHandLocalizedText(
                      context,
                      zh: '当前会话没有 WebSocket / EventSource 连接',
                      zhHant: '目前會話沒有 WebSocket / EventSource 連線',
                      en: 'No WebSocket / EventSource connections',
                      fr: 'Aucune connexion WebSocket / EventSource',
                      de: 'Keine WebSocket-/EventSource-Verbindungen',
                      ja: 'WebSocket / EventSource 接続がありません',
                    ),
                    dense: true,
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
                              borderRadius: kOpenHandBorderRadius10,
                              onTap: () =>
                                  setState(() => _selectedId = c.requestId),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: picked
                                      ? cs.primaryContainer.withValues(
                                          alpha: 0.4,
                                        )
                                      : cs.surfaceContainerHigh,
                                  borderRadius: kOpenHandBorderRadius10,
                                  border: Border.all(
                                    color: picked
                                        ? cs.primary
                                        : cs.outlineVariant,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      c.url,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontFamily:
                                            kOpenHandMonospaceFontFamily,
                                        fontSize: 11,
                                      ),
                                    ),
                                    kOpenHandGap4,
                                    Text(
                                      openHandLocalizedText(
                                        context,
                                        zh: '${c.wsFrames.length} 帧',
                                        zhHant: '${c.wsFrames.length} 影格',
                                        en: '${c.wsFrames.length} frames',
                                        fr: '${c.wsFrames.length} trames',
                                        de: '${c.wsFrames.length} Frames',
                                        ja: '${c.wsFrames.length} フレーム',
                                      ),
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
                                      12,
                                      10,
                                      12,
                                      6,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: SelectableText(
                                            cur.url,
                                            style: const TextStyle(
                                              fontFamily:
                                                  kOpenHandMonospaceFontFamily,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        FilledButton.icon(
                                          onPressed: _busy ? null : _replaySent,
                                          icon: const Icon(Icons.send_rounded),
                                          label: Text(
                                            openHandLocalizedText(
                                              context,
                                              zh: '重放 sent 帧',
                                              zhHant: '重放 sent 影格',
                                              en: 'Replay sent',
                                              fr: 'Rejouer envoyées',
                                              de: 'Gesendete wiederholen',
                                              ja: 'sent をリプレイ',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  OpenHandBusyProgressBar(busy: _busy),
                                  Expanded(
                                    child: ListView.builder(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      itemCount: cur.wsFrames.length,
                                      itemBuilder: (_, i) {
                                        final f = cur.wsFrames[i];
                                        final isSent =
                                            f.direction ==
                                            CdpWebSocketDirection.sent;
                                        final isErr =
                                            f.direction ==
                                            CdpWebSocketDirection.error;
                                        return Container(
                                          margin: const EdgeInsets.only(
                                            bottom: 4,
                                          ),
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: isErr
                                                ? cs.errorContainer.withValues(
                                                    alpha: 0.5,
                                                  )
                                                : isSent
                                                ? cs.primaryContainer
                                                      .withValues(alpha: 0.18)
                                                : cs.surfaceContainerHigh,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: cs.outlineVariant,
                                            ),
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
                                                  kOpenHandHGap6,
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
                                                      fontFamily:
                                                          kOpenHandMonospaceFontFamily,
                                                      fontSize: 10,
                                                      color: cs.onSurfaceVariant
                                                          .withValues(
                                                            alpha: 0.7,
                                                          ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              kOpenHandGap4,
                                              SelectableText(
                                                clipTextByCodeUnits(
                                                  f.payload,
                                                  800,
                                                  suffix: '…',
                                                ),
                                                style: const TextStyle(
                                                  fontFamily:
                                                      kOpenHandMonospaceFontFamily,
                                                  fontSize: 11,
                                                ),
                                              ),
                                              if (f.errorMessage != null)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 3,
                                                      ),
                                                  child: Text(
                                                    f.errorMessage!,
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: cs.error,
                                                    ),
                                                  ),
                                                ),
                                              if (!isErr &&
                                                  f.payload.isNotEmpty)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 4,
                                                      ),
                                                  child: Row(
                                                    children: [
                                                      _MiniFrameAction(
                                                        icon: Icons
                                                            .replay_rounded,
                                                        tooltip:
                                                            openHandLocalizedText(
                                                              context,
                                                              zh: '重发此帧',
                                                              zhHant: '重送此影格',
                                                              en: 'Resend',
                                                              fr: 'Renvoyer',
                                                              de: 'Erneut senden',
                                                              ja: '再送信',
                                                            ),
                                                        onTap: _busy
                                                            ? null
                                                            : () =>
                                                                  _editAndSend(
                                                                    f.payload,
                                                                  ),
                                                        // 直接重发=编辑窗预填，用户点发送即可；
                                                        // 若想免确认重发可改成 _replaySingle
                                                      ),
                                                      kOpenHandHGap6,
                                                      _MiniFrameAction(
                                                        icon:
                                                            Icons.edit_rounded,
                                                        tooltip: openHandLocalizedText(
                                                          context,
                                                          zh: '编辑并发送',
                                                          zhHant: '編輯並傳送',
                                                          en: 'Edit & send',
                                                          fr: 'Modifier et envoyer',
                                                          de: 'Bearbeiten und senden',
                                                          ja: '編集して送信',
                                                        ),
                                                        onTap: _busy
                                                            ? null
                                                            : () =>
                                                                  _editAndSend(
                                                                    f.payload,
                                                                  ),
                                                      ),
                                                      kOpenHandHGap6,
                                                      _MiniFrameAction(
                                                        icon: Icons
                                                            .bug_report_rounded,
                                                        tooltip:
                                                            openHandLocalizedText(
                                                              context,
                                                              zh: 'Fuzz 此帧',
                                                              zhHant:
                                                                  'Fuzz 此影格',
                                                              en: 'Fuzz',
                                                              fr: 'Fuzzer',
                                                              de: 'Fuzzen',
                                                              ja: 'Fuzz',
                                                            ),
                                                        onTap: _busy
                                                            ? null
                                                            : () => _fuzz(
                                                                f.payload,
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
                                ],
                              ),
                      ),
                    ],
                  ),
          ),
          buildWebReverseStatusBar(context, status: _status),
          buildOpenHandDialogFooter(
            primaryLabel: openHandCloseLabel(context),
            onPrimaryPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _FuzzConfig {
  const _FuzzConfig({
    required this.count,
    required this.delayMs,
    required this.intensity,
  });
  final int count;
  final int delayMs;
  final int intensity;
}

class _MiniFrameAction extends StatelessWidget {
  const _MiniFrameAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: kOpenHandBorderRadius6,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 14,
            color: enabled
                ? cs.primary
                : cs.onSurfaceVariant.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }
}
