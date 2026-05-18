/// CDP Raw 命令控制台 —— 带历史、JSON 校验、快捷键。
///
/// 输入 method + JSON params，Cmd/Ctrl+Enter 发送，Ctrl+↑/↓ 翻历史。
/// 历史保存在静态列表里，应用生命周期内跨次打开保留。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/support/silent_log.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import 'web_reverse_session_controller.dart';

class _CdpHistoryEntry {
  _CdpHistoryEntry({
    required this.method,
    required this.paramsJson,
    required this.useSession,
    required this.timestamp,
    this.error,
    this.resultJson,
  });
  final String method;
  final String paramsJson;
  final bool useSession;
  final DateTime timestamp;
  String? error;
  String? resultJson;
}

final List<_CdpHistoryEntry> _cdpConsoleHistory = <_CdpHistoryEntry>[];

Future<void> showWebReverseCdpConsoleDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
  required bool isZh,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _CdpConsoleDialog(controller: controller, isZh: isZh),
  );
}

class _CdpConsoleDialog extends StatefulWidget {
  const _CdpConsoleDialog({required this.controller, required this.isZh});
  final WebReverseSessionController controller;
  final bool isZh;
  @override
  State<_CdpConsoleDialog> createState() => _CdpConsoleDialogState();
}

class _CdpConsoleDialogState extends State<_CdpConsoleDialog> {
  final _methodCtl = TextEditingController(text: 'Page.reload');
  final _paramsCtl = TextEditingController(text: '{}');
  final _paramsFocus = FocusNode();
  bool _useSession = true;
  bool _busy = false;
  int _historyCursor = -1;

  @override
  void dispose() {
    _methodCtl.dispose();
    _paramsCtl.dispose();
    _paramsFocus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final isZh = widget.isZh;
    final method = _methodCtl.text.trim();
    if (method.isEmpty) {
      setState(() {});
      return;
    }
    final paramsText = _paramsCtl.text.trim();
    String? paramsJson;
    if (paramsText.isNotEmpty && paramsText != '{}') {
      try {
        jsonDecode(paramsText);
        paramsJson = paramsText;
      } catch (err) {
        final m = ScaffoldMessenger.maybeOf(context);
        if (m != null) {
          OpenHandSnackBar.showErrorOn(
            context,
            m,
            isZh ? 'JSON 解析失败：$err' : 'Invalid JSON: $err',
          );
        }
        return;
      }
    }
    setState(() => _busy = true);
    final entry = _CdpHistoryEntry(
      method: method,
      paramsJson: paramsJson ?? '',
      useSession: _useSession,
      timestamp: DateTime.now(),
    );
    try {
      final r = await widget.controller.sendRawCdp(
        method: method,
        paramsJson: paramsJson,
        useSession: _useSession,
      );
      if (r == null) {
        entry.error = isZh ? '调用失败（未连接？）' : 'Send failed';
      } else if (r['error'] != null) {
        entry.error = '${r['error']}';
      } else {
        entry.resultJson = const JsonEncoder.withIndent('  ').convert(r);
      }
    } catch (err, st) {
      silentLog('web-reverse', 'cdp-console.send', err, st);
      entry.error = '$err';
    }
    _cdpConsoleHistory.insert(0, entry);
    if (_cdpConsoleHistory.length > 100) {
      _cdpConsoleHistory.removeRange(100, _cdpConsoleHistory.length);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _historyCursor = -1;
    });
  }

  void _loadHistoryAt(int idx) {
    if (idx < 0 || idx >= _cdpConsoleHistory.length) return;
    final h = _cdpConsoleHistory[idx];
    setState(() {
      _historyCursor = idx;
      _methodCtl.text = h.method;
      _paramsCtl.text = h.paramsJson.isEmpty ? '{}' : h.paramsJson;
      _useSession = h.useSession;
    });
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final ctrl = keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight) ||
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight);
    if (ctrl && e.logicalKey == LogicalKeyboardKey.enter) {
      _send();
      return KeyEventResult.handled;
    }
    if (ctrl && e.logicalKey == LogicalKeyboardKey.arrowUp) {
      _loadHistoryAt(
          (_historyCursor + 1).clamp(0, _cdpConsoleHistory.length - 1));
      return KeyEventResult.handled;
    }
    if (ctrl && e.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_historyCursor <= 0) {
        setState(() {
          _historyCursor = -1;
          _methodCtl.clear();
          _paramsCtl.text = '{}';
        });
      } else {
        _loadHistoryAt(_historyCursor - 1);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _copy(String t) async {
    try {
      await Clipboard.setData(ClipboardData(text: t));
    } catch (err, st) {
      silentLog('web-reverse', 'cdp-console.copy', err, st);
      return;
    }
    if (!mounted) return;
    final m = ScaffoldMessenger.maybeOf(context);
    if (m != null) {
      OpenHandSnackBar.showSuccessOn(
        context,
        m,
        widget.isZh ? '已复制' : 'Copied',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isZh = widget.isZh;
    return Dialog(
      backgroundColor: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 760),
        child: Focus(
          autofocus: false,
          onKeyEvent: _onKey,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
              child: Row(children: [
                Icon(Icons.terminal_rounded, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isZh ? 'CDP Raw 命令控制台' : 'CDP Raw Console',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        isZh
                            ? '⌘/Ctrl+Enter 发送 · Ctrl+↑/↓ 翻历史 · 共 ${_cdpConsoleHistory.length} 条'
                            : '⌘/Ctrl+Enter send · Ctrl+↑/↓ history · ${_cdpConsoleHistory.length} entries',
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
              ]),
            ),
            Divider(height: 1, color: cs.outlineVariant),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Left: input + history list ──
                  SizedBox(
                    width: 320,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                controller: _methodCtl,
                                autofocus: true,
                                decoration: InputDecoration(
                                  labelText: isZh
                                      ? 'method (Domain.command)'
                                      : 'method',
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                                style: const TextStyle(
                                    fontFamily: 'monospace', fontSize: 12),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _paramsCtl,
                                focusNode: _paramsFocus,
                                maxLines: 6,
                                style: const TextStyle(
                                    fontFamily: 'monospace', fontSize: 11),
                                decoration: const InputDecoration(
                                  labelText: 'params (JSON)',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(children: [
                                Switch(
                                  value: _useSession,
                                  onChanged: (v) =>
                                      setState(() => _useSession = v),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isZh
                                      ? '使用 page session'
                                      : 'use page session',
                                  style: theme.textTheme.labelMedium,
                                ),
                                const Spacer(),
                                FilledButton.icon(
                                  onPressed: _busy ? null : _send,
                                  icon: const Icon(Icons.send_rounded),
                                  label: Text(isZh ? '发送' : 'Send'),
                                ),
                              ]),
                            ],
                          ),
                        ),
                        if (_busy) const LinearProgressIndicator(minHeight: 3),
                        Divider(height: 1, color: cs.outlineVariant),
                        Expanded(
                          child: _cdpConsoleHistory.isEmpty
                              ? Center(
                                  child: Text(
                                    isZh ? '历史为空' : 'No history',
                                    style: TextStyle(
                                        color: cs.onSurfaceVariant,
                                        fontSize: 12),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: _cdpConsoleHistory.length,
                                  itemBuilder: (_, i) {
                                    final h = _cdpConsoleHistory[i];
                                    final picked = i == _historyCursor;
                                    return InkWell(
                                      onTap: () => _loadHistoryAt(i),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: picked
                                              ? cs.primaryContainer
                                                  .withValues(alpha: 0.3)
                                              : null,
                                          border: Border(
                                            bottom: BorderSide(
                                                color: cs.outlineVariant),
                                          ),
                                        ),
                                        child: Row(children: [
                                          Icon(
                                            h.error == null
                                                ? Icons.check_circle_rounded
                                                : Icons.cancel_rounded,
                                            size: 12,
                                            color: h.error == null
                                                ? cs.primary
                                                : cs.error,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              h.method,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontFamily: 'monospace',
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            h.timestamp
                                                .toIso8601String()
                                                .substring(11, 19),
                                            style: TextStyle(
                                                fontSize: 10,
                                                fontFamily: 'monospace',
                                                color: cs.onSurfaceVariant),
                                          ),
                                        ]),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                  VerticalDivider(width: 1, color: cs.outlineVariant),
                  // ── Right: detail of last/selected ──
                  Expanded(
                    child: _historyCursor < 0 || _cdpConsoleHistory.isEmpty
                        ? Center(
                            child: Text(
                              isZh ? '发送命令后在此查看响应' : 'Send a command',
                              style: TextStyle(
                                  color: cs.onSurfaceVariant, fontSize: 12),
                            ),
                          )
                        : _detailFor(_cdpConsoleHistory[_historyCursor]),
                  ),
                ],
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
          ]),
        ),
      ),
    );
  }

  Widget _detailFor(_CdpHistoryEntry h) {
    final cs = Theme.of(context).colorScheme;
    final isZh = widget.isZh;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Text(
              h.method,
              style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                  fontSize: 13),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 18),
              tooltip: isZh ? '复制响应 JSON' : 'Copy response',
              onPressed: () => _copy(h.resultJson ?? h.error ?? ''),
            ),
          ]),
          if (h.paramsJson.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              isZh ? '请求参数' : 'Params',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            Container(
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectableText(
                h.paramsJson,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            h.error == null ? (isZh ? '响应' : 'Response') : (isZh ? '错误' : 'Error'),
            style: Theme.of(context).textTheme.labelSmall,
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: h.error == null
                    ? cs.surfaceContainerHigh
                    : cs.errorContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(6),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  h.error ?? h.resultJson ?? '',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: h.error == null ? null : cs.error,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
