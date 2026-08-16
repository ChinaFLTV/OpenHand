/// Console REPL 对话框。
///
/// 多行 JS 输入 → [WebReverseSessionController.runReplExpression] →
/// 在窗口顶部展示「最近 N 条」历史会话（表达式 + 结果）；持久化使用
/// `pushReplHistory` 复用 controller 的 200 条上限。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/auto_follow_scroll_guard.dart';
import '../../shared/ui/motion_durations.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_form_fields.dart';
import '../../shared/ui/openhand_inline_empty_state.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import '../../shared/ui/openhand_spacing.dart';
import '../../shared/ui/openhand_typography.dart';
import '../../shared/util/byte_size_format.dart';
import '../../shared/util/text_clip.dart';
import 'web_reverse_clipboard.dart';
import 'web_reverse_dialog_utils.dart';
import 'web_reverse_session_controller.dart';

const int _kReplLogMaxEntries = 100;
const int _kReplLogExpressionChars = 64 * kBytesPerKiB;
const int _kReplLogResultChars = 64 * kBytesPerKiB;

Future<void> showWebReverseReplDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) {
  return webReverseToolDialogs.show<void>(
    context: context,
    builder: (_) => _ReplDialog(controller: controller),
  );
}

class _ReplDialog extends StatefulWidget {
  const _ReplDialog({required this.controller});
  final WebReverseSessionController controller;
  @override
  State<_ReplDialog> createState() => _ReplDialogState();
}

class _ReplEntry {
  _ReplEntry(this.expr, this.result, this.error);
  final String expr;
  final String result;
  final bool error;
}

class _ReplDialogState extends State<_ReplDialog> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final AutoFollowScrollGuard _scrollGuard = AutoFollowScrollGuard();
  final List<_ReplEntry> _log = [];
  int _historyCursor = -1;
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final expr = _input.text.trim();
    if (expr.isEmpty || _busy) return;
    if (expr.length > WebReverseSessionController.maxReplExpressionChars) {
      showOpenHandErrorSnack(
        context,
        'Expression too large: ${expr.length} chars, limit ${WebReverseSessionController.maxReplExpressionChars}',
      );
      return;
    }
    final noResultLabel =
        AppLocalizations.of(context)?.webReverseReplNoResult ?? '(no result)';
    setState(() => _busy = true);
    widget.controller.pushReplHistory(expr);
    _historyCursor = -1;
    String result = '';
    bool error = false;
    try {
      final r = await widget.controller.runReplExpression(expr);
      if (r == null) {
        error = true;
        result = noResultLabel;
      } else {
        result = r;
      }
    } catch (e, s) {
      silentLog('web_reverse_repl_dialog', '执行 REPL', e, s);
      error = true;
      result = e.toString();
    }
    if (!mounted) return;
    setState(() {
      _log.add(
        _ReplEntry(
          _capReplDialogText(expr, _kReplLogExpressionChars, '表达式'),
          _capReplDialogText(result, _kReplLogResultChars, '结果'),
          error,
        ),
      );
      while (_log.length > _kReplLogMaxEntries) {
        _log.removeAt(0);
      }
      _busy = false;
      _input.clear();
    });
    _scrollGuard.scheduleFollowToBottom(
      _scroll,
      animated: true,
      animationDuration: kOpenHandMotion240,
    );
  }

  void _historyUp() {
    final h = widget.controller.replHistory;
    if (h.isEmpty) return;
    final next = (_historyCursor < 0)
        ? h.length - 1
        : (_historyCursor - 1).clamp(0, h.length - 1);
    setState(() {
      _historyCursor = next;
      _input.text = h[next];
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
    });
  }

  void _historyDown() {
    final h = widget.controller.replHistory;
    if (_historyCursor < 0) return;
    final next = _historyCursor + 1;
    if (next >= h.length) {
      setState(() {
        _historyCursor = -1;
        _input.clear();
      });
    } else {
      setState(() {
        _historyCursor = next;
        _input.text = h[next];
        _input.selection = TextSelection.collapsed(offset: _input.text.length);
      });
    }
  }

  Future<void> _copy(String s) async {
    await copyWebReverseTextToClipboard(
      context: context,
      text: s,
      successBase:
          AppLocalizations.of(context)?.webReverseReplCopied ?? 'Copied',
      logTag: 'web_reverse_repl_dialog',
      logAction: '复制 REPL 结果',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    return buildOpenHandToolDialogShell(
      context: context,
      maxHeight: kOpenHandDialogHeightTall,
      child: Column(
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.terminal_rounded,
            title: loc?.webReverseReplTitle ?? 'Console REPL',
            subtitle:
                loc?.webReverseReplSubtitle ??
                'Runtime.evaluate · ↑/↓ history · Ctrl/⌘+Enter run',
            actions: [
              IconButton(
                onPressed: _log.isEmpty ? null : () => setState(_log.clear),
                icon: const Icon(Icons.delete_sweep_rounded),
                tooltip: loc?.webReverseReplClear ?? 'Clear log',
              ),
            ],
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Expanded(
            child: _log.isEmpty
                ? OpenHandInlineEmptyState(
                    message:
                        loc?.webReverseReplEmpty ??
                        'Type JS below → Ctrl/⌘+Enter to run',
                    dense: true,
                  )
                : NotificationListener<ScrollNotification>(
                    onNotification: _scrollGuard.handleNotification,
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      itemCount: _log.length,
                      itemBuilder: (_, i) {
                        final e = _log[i];
                        return _LogTile(entry: e, onCopy: _copy, cs: cs);
                      },
                    ),
                  ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: _ReplInput(
              controller: _input,
              busy: _busy,
              onRun: _run,
              onHistoryUp: _historyUp,
              onHistoryDown: _historyDown,
              hint:
                  loc?.webReverseReplHint ??
                  'eg: document.title or await fetch("/api").then(r=>r.json())',
            ),
          ),
          buildOpenHandDialogActionsBar(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            spacing: 10,
            actions: [
              OpenHandDialogActionButton.secondary(
                label: loc?.webReverseReplRun ?? 'Run',
                icon: Icons.play_arrow_rounded,
                busy: _busy,
                onPressed: _busy ? null : _run,
              ),
              OpenHandDialogActionButton.primary(
                label: loc?.commonClose ?? 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry, required this.onCopy, required this.cs});
  final _ReplEntry entry;
  final ValueChanged<String> onCopy;
  final ColorScheme cs;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: webReverseSurfaceCardDecoration(cs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.chevron_right_rounded, size: 14, color: cs.primary),
              kOpenHandHGap6,
              Expanded(
                child: SelectableText(
                  entry.expr,
                  style: const TextStyle(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              InkWell(
                onTap: () => onCopy(entry.expr),
                borderRadius: kOpenHandBorderRadius6,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.copy_rounded,
                    size: 14,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          kOpenHandGap6,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                entry.error
                    ? Icons.error_outline_rounded
                    : Icons.subdirectory_arrow_right_rounded,
                size: 14,
                color: entry.error ? cs.error : cs.tertiary,
              ),
              kOpenHandHGap6,
              Expanded(
                child: SelectableText(
                  entry.result,
                  style: TextStyle(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    fontSize: 12,
                    color: entry.error ? cs.error : cs.onSurface,
                  ),
                ),
              ),
              InkWell(
                onTap: () => onCopy(entry.result),
                borderRadius: kOpenHandBorderRadius6,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.copy_rounded,
                    size: 14,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReplInput extends StatelessWidget {
  const _ReplInput({
    required this.controller,
    required this.busy,
    required this.onRun,
    required this.onHistoryUp,
    required this.onHistoryDown,
    required this.hint,
  });
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onRun;
  final VoidCallback onHistoryUp;
  final VoidCallback onHistoryDown;
  final String hint;
  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter, meta: true): _RunIntent(),
        SingleActivator(LogicalKeyboardKey.enter, control: true): _RunIntent(),
        SingleActivator(LogicalKeyboardKey.arrowUp, control: true):
            _HistUpIntent(),
        SingleActivator(LogicalKeyboardKey.arrowDown, control: true):
            _HistDownIntent(),
      },
      child: Actions(
        actions: {
          _RunIntent: CallbackAction<_RunIntent>(
            onInvoke: (_) {
              if (!busy) onRun();
              return null;
            },
          ),
          _HistUpIntent: CallbackAction<_HistUpIntent>(
            onInvoke: (_) {
              onHistoryUp();
              return null;
            },
          ),
          _HistDownIntent: CallbackAction<_HistDownIntent>(
            onInvoke: (_) {
              onHistoryDown();
              return null;
            },
          ),
        },
        child: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 8,
          maxLength: WebReverseSessionController.maxReplExpressionChars,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          buildCounter: openHandHiddenTextFieldCounter,
          enabled: !busy,
          autofocus: true,
          style: const TextStyle(
            fontFamily: kOpenHandMonospaceFontFamily,
            fontSize: 13,
          ),
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ),
    );
  }
}

class _RunIntent extends Intent {
  const _RunIntent();
}

class _HistUpIntent extends Intent {
  const _HistUpIntent();
}

class _HistDownIntent extends Intent {
  const _HistDownIntent();
}

String _capReplDialogText(String text, int maxChars, String label) {
  return clipTextByCodeUnits(
    text,
    maxChars,
    suffix: '\n\n[OpenHand 已截断 REPL $label]',
  );
}
