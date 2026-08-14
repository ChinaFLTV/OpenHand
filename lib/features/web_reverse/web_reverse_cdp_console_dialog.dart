/// CDP Raw 命令控制台 —— 带历史、JSON 校验、快捷键。
///
/// 输入 method + JSON params，Cmd/Ctrl+Enter 发送，Ctrl+↑/↓ 翻历史。
/// 历史保存在静态列表里，应用生命周期内跨次打开保留。
library;

import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_busy_indicators.dart';
import '../../shared/ui/openhand_inline_empty_state.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import '../../shared/ui/openhand_spacing.dart';
import '../../shared/ui/openhand_typography.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/text_clip.dart';
import 'web_reverse_clipboard.dart';
import 'web_reverse_dialog_utils.dart';
import 'web_reverse_session_controller.dart';

class _CdpHistoryEntry {
  _CdpHistoryEntry({
    required this.method,
    required this.paramsJson,
    required this.paramsClipped,
    required this.useSession,
    required this.timestamp,
  });
  final String method;
  final String paramsJson;
  final bool paramsClipped;
  final bool useSession;
  final DateTime timestamp;
  String? error;
  String? resultJson;

  int get retainedCharacters =>
      method.length +
      paramsJson.length +
      (error?.length ?? 0) +
      (resultJson?.length ?? 0);
}

final ListQueue<_CdpHistoryEntry> _cdpConsoleHistory =
    ListQueue<_CdpHistoryEntry>();
const int _kCdpConsoleMaxParamsJsonChars = 2 * 1024 * 1024;
const int _kCdpConsoleHistoryParamsChars = 64 * 1024;
const int _kCdpConsoleHistoryResultChars = 512 * 1024;
const int _kCdpConsoleHistoryErrorChars = 64 * 1024;
const int _kCdpConsoleHistoryMaxEntries = 100;
const int _kCdpConsoleHistoryMaxCharacters = 8 * 1024 * 1024;
int _cdpConsoleHistoryCharacters = 0;

Future<void> showWebReverseCdpConsoleDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) {
  return webReverseToolDialogs.show<void>(
    context: context,
    builder: (_) => _CdpConsoleDialog(controller: controller),
  );
}

class _CdpConsoleDialog extends StatefulWidget {
  const _CdpConsoleDialog({required this.controller});
  final WebReverseSessionController controller;
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
    final loc = AppLocalizations.of(context);
    final method = _methodCtl.text.trim();
    if (method.isEmpty) {
      setState(() {});
      return;
    }
    final paramsText = _paramsCtl.text.trim();
    String? paramsJson;
    if (paramsText.isNotEmpty && paramsText != '{}') {
      if (paramsText.length > _kCdpConsoleMaxParamsJsonChars) {
        showOpenHandErrorSnack(
          context,
          'Params JSON too large: ${paramsText.length} chars, limit $_kCdpConsoleMaxParamsJsonChars',
        );
        return;
      }
      try {
        jsonDecode(paramsText);
        paramsJson = paramsText;
      } catch (err) {
        showOpenHandErrorSnack(
          context,
          loc?.webReverseCdpInvalidJson('$err') ?? 'Invalid JSON: $err',
        );
        return;
      }
    }
    setState(() => _busy = true);
    final entry = _CdpHistoryEntry(
      method: clipText(
        method,
        WebReverseSessionController.maxRawCdpMethodChars,
        suffix: '',
      ),
      paramsJson: _capCdpConsoleHistoryText(
        paramsJson ?? '',
        _kCdpConsoleHistoryParamsChars,
      ),
      paramsClipped: (paramsJson ?? '').length > _kCdpConsoleHistoryParamsChars,
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
        entry.error = loc?.webReverseCdpSendFailed ?? 'Send failed';
      } else if (r['error'] != null) {
        entry.error = _capCdpConsoleHistoryText(
          '${r['error']}',
          _kCdpConsoleHistoryErrorChars,
        );
      } else {
        entry.resultJson = _capCdpConsoleHistoryText(
          prettyPrintJson(r),
          _kCdpConsoleHistoryResultChars,
        );
      }
    } catch (err, st) {
      silentLog('web_reverse_cdp_console_dialog', '发送 CDP 控制台命令', err, st);
      entry.error = _capCdpConsoleHistoryText(
        '$err',
        _kCdpConsoleHistoryErrorChars,
      );
    }
    _cdpConsoleHistory.addFirst(entry);
    _cdpConsoleHistoryCharacters += entry.retainedCharacters;
    while (_cdpConsoleHistory.length > _kCdpConsoleHistoryMaxEntries ||
        _cdpConsoleHistoryCharacters > _kCdpConsoleHistoryMaxCharacters) {
      _cdpConsoleHistoryCharacters -= _cdpConsoleHistory
          .removeLast()
          .retainedCharacters;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _historyCursor = 0;
    });
  }

  void _loadHistoryAt(int idx) {
    if (idx < 0 || idx >= _cdpConsoleHistory.length) return;
    final h = _cdpConsoleHistory.elementAt(idx);
    setState(() {
      _historyCursor = idx;
      _methodCtl.text = h.method;
      _paramsCtl.text = h.paramsClipped
          ? '{}'
          : h.paramsJson.isEmpty
          ? '{}'
          : h.paramsJson;
      _useSession = h.useSession;
    });
    if (h.paramsClipped) {
      showOpenHandInfoSnack(
        context,
        'Params were clipped in history; input reset to {}.',
      );
    }
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final ctrl =
        keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight) ||
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight);
    if (ctrl && e.logicalKey == LogicalKeyboardKey.enter) {
      _send();
      return KeyEventResult.handled;
    }
    if (ctrl && e.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_cdpConsoleHistory.isEmpty) return KeyEventResult.handled;
      _loadHistoryAt(
        (_historyCursor + 1).clamp(0, _cdpConsoleHistory.length - 1),
      );
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
    await copyWebReverseTextToClipboard(
      context: context,
      text: t,
      successBase:
          AppLocalizations.of(context)?.webReverseCdpCopied ?? 'Copied',
      logTag: 'web_reverse_cdp_console_dialog',
      logAction: '复制 CDP 控制台内容',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthExtraWide,
      maxHeight: kOpenHandDialogHeightTall,
      child: Focus(
        onKeyEvent: _onKey,
        child: Column(
          children: [
            buildOpenHandToolDialogHeader(
              context: context,
              icon: Icons.terminal_rounded,
              title: loc?.webReverseCdpTitle ?? 'CDP Raw Console',
              subtitle:
                  loc?.webReverseCdpSubtitle(_cdpConsoleHistory.length) ??
                  '⌘/Ctrl+Enter send · Ctrl+↑/↓ history · ${_cdpConsoleHistory.length} entries',
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
            ),
            Divider(height: 1, color: cs.outlineVariant),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 左侧：输入区与历史列表。
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
                                  labelText:
                                      loc?.webReverseCdpMethodLabel ?? 'method',
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                                style: const TextStyle(
                                  fontFamily: kOpenHandMonospaceFontFamily,
                                  fontSize: 12,
                                ),
                              ),
                              kOpenHandGap8,
                              TextField(
                                controller: _paramsCtl,
                                focusNode: _paramsFocus,
                                maxLines: 6,
                                style: const TextStyle(
                                  fontFamily: kOpenHandMonospaceFontFamily,
                                  fontSize: 11,
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'params (JSON)',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              kOpenHandGap8,
                              Row(
                                children: [
                                  Switch(
                                    value: _useSession,
                                    onChanged: (v) =>
                                        setState(() => _useSession = v),
                                  ),
                                  kOpenHandHGap4,
                                  Text(
                                    loc?.webReverseCdpUseSession ??
                                        'use page session',
                                    style: theme.textTheme.labelMedium,
                                  ),
                                  const Spacer(),
                                  FilledButton.icon(
                                    onPressed: _busy ? null : _send,
                                    icon: const Icon(Icons.send_rounded),
                                    label: Text(
                                      loc?.webReverseCdpSend ?? 'Send',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        OpenHandBusyProgressBar(busy: _busy),
                        Divider(height: 1, color: cs.outlineVariant),
                        Expanded(
                          child: _cdpConsoleHistory.isEmpty
                              ? OpenHandInlineEmptyState(
                                  message:
                                      loc?.webReverseCdpNoHistory ??
                                      'No history',
                                )
                              : ListView.builder(
                                  itemCount: _cdpConsoleHistory.length,
                                  itemBuilder: (_, i) {
                                    final h = _cdpConsoleHistory.elementAt(i);
                                    final picked = i == _historyCursor;
                                    return InkWell(
                                      onTap: () => _loadHistoryAt(i),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: picked
                                              ? cs.primaryContainer.withValues(
                                                  alpha: 0.3,
                                                )
                                              : null,
                                          border: Border(
                                            bottom: BorderSide(
                                              color: cs.outlineVariant,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              h.error == null
                                                  ? Icons.check_circle_rounded
                                                  : Icons.cancel_rounded,
                                              size: 12,
                                              color: h.error == null
                                                  ? cs.primary
                                                  : cs.error,
                                            ),
                                            kOpenHandHGap6,
                                            Expanded(
                                              child: Text(
                                                h.method,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontFamily:
                                                      kOpenHandMonospaceFontFamily,
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
                                                fontFamily:
                                                    kOpenHandMonospaceFontFamily,
                                                color: cs.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                  VerticalDivider(width: 1, color: cs.outlineVariant),
                  // 右侧：最近或当前选中记录的详情。
                  Expanded(
                    child: _historyCursor < 0 || _cdpConsoleHistory.isEmpty
                        ? Center(
                            child: Text(
                              loc?.webReverseCdpSendHint ?? 'Send a command',
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          )
                        : _detailFor(
                            _cdpConsoleHistory.elementAt(_historyCursor),
                          ),
                  ),
                ],
              ),
            ),
            buildOpenHandDialogFooter(
              primaryLabel: loc?.webReverseCdpClose ?? 'Close',
              onPrimaryPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailFor(_CdpHistoryEntry h) {
    final cs = Theme.of(context).colorScheme;
    final loc = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                h.method,
                style: const TextStyle(
                  fontFamily: kOpenHandMonospaceFontFamily,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 18),
                tooltip: loc?.webReverseCdpCopyResponse ?? 'Copy response',
                onPressed: () => _copy(h.resultJson ?? h.error ?? ''),
              ),
            ],
          ),
          if (h.paramsJson.isNotEmpty) ...[
            kOpenHandGap6,
            Text(
              h.paramsClipped
                  ? '${loc?.webReverseCdpParams ?? 'Params'} (clipped)'
                  : loc?.webReverseCdpParams ?? 'Params',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            Container(
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: kOpenHandBorderRadius6,
              ),
              child: SelectableText(
                h.paramsJson,
                style: const TextStyle(
                  fontFamily: kOpenHandMonospaceFontFamily,
                  fontSize: 11,
                ),
              ),
            ),
          ],
          kOpenHandGap10,
          Text(
            h.error == null
                ? (loc?.webReverseCdpResponse ?? 'Response')
                : (loc?.webReverseCdpError ?? 'Error'),
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
                borderRadius: kOpenHandBorderRadius6,
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  h.error ?? h.resultJson ?? '',
                  style: TextStyle(
                    fontFamily: kOpenHandMonospaceFontFamily,
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

String _capCdpConsoleHistoryText(String text, int maxChars) {
  return clipTextByCodeUnits(
    text,
    maxChars,
    suffix: '\n\n[OpenHand 已截断 CDP 控制台历史]',
  );
}
