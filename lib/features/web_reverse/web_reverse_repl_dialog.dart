/// Console REPL 对话框。
///
/// 多行 JS 输入 → [WebReverseSessionController.runReplExpression] →
/// 在窗口顶部展示「最近 N 条」历史会话（表达式 + 结果）；持久化使用
/// `pushReplHistory` 复用 controller 的 200 条上限。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/support/silent_log.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseReplDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
  required bool isZh,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _ReplDialog(controller: controller, isZh: isZh),
  );
}

class _ReplDialog extends StatefulWidget {
  const _ReplDialog({required this.controller, required this.isZh});
  final WebReverseSessionController controller;
  final bool isZh;
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
    setState(() => _busy = true);
    widget.controller.pushReplHistory(expr);
    _historyCursor = -1;
    String result = '';
    bool error = false;
    try {
      final r = await widget.controller.runReplExpression(expr);
      if (r == null) {
        error = true;
        result = widget.isZh ? '(无返回)' : '(no result)';
      } else {
        result = r;
      }
    } catch (e, s) {
      silentLog('web-reverse', 'repl.run', e, s);
      error = true;
      result = e.toString();
    }
    if (!mounted) return;
    setState(() {
      _log.add(_ReplEntry(expr, result, error));
      _busy = false;
      _input.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        );
      }
    });
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
      _input.selection =
          TextSelection.collapsed(offset: _input.text.length);
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
        _input.selection =
            TextSelection.collapsed(offset: _input.text.length);
      });
    }
  }

  Future<void> _copy(String s) async {
    try {
      await Clipboard.setData(ClipboardData(text: s));
    } catch (e, st) {
      silentLog('web-reverse', 'repl.copy', e, st);
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
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 760),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
              child: Row(
                children: [
                  Icon(Icons.terminal_rounded, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isZh ? 'Console REPL' : 'Console REPL',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          isZh
                              ? 'Runtime.evaluate · ↑/↓ 历史 · Ctrl/⌘+Enter 执行'
                              : 'Runtime.evaluate · ↑/↓ history · Ctrl/⌘+Enter run',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _log.isEmpty
                        ? null
                        : () => setState(_log.clear),
                    icon: const Icon(Icons.delete_sweep_rounded),
                    tooltip: isZh ? '清空输出' : 'Clear log',
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
              child: _log.isEmpty
                  ? Center(
                      child: Text(
                        isZh
                            ? '在下方输入 JS 表达式 → Ctrl/⌘+Enter 执行'
                            : 'Type JS below → Ctrl/⌘+Enter to run',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      itemCount: _log.length,
                      itemBuilder: (_, i) {
                        final e = _log[i];
                        return _LogTile(entry: e, onCopy: _copy, cs: cs);
                      },
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
                hint: isZh
                    ? '示例: document.title  或  await fetch("/api").then(r=>r.json())'
                    : 'eg: document.title or await fetch("/api").then(r=>r.json())',
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 10,
                children: [
                  OpenHandDialogActionButton.secondary(
                    label: isZh ? '执行' : 'Run',
                    icon: Icons.play_arrow_rounded,
                    busy: _busy,
                    onPressed: _busy ? null : _run,
                  ),
                  OpenHandDialogActionButton.primary(
                    label: isZh ? '关闭' : 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({
    required this.entry,
    required this.onCopy,
    required this.cs,
  });
  final _ReplEntry entry;
  final ValueChanged<String> onCopy;
  final ColorScheme cs;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.chevron_right_rounded, size: 14, color: cs.primary),
              const SizedBox(width: 6),
              Expanded(
                child: SelectableText(
                  entry.expr,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              InkWell(
                onTap: () => onCopy(entry.expr),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.copy_rounded,
                      size: 14, color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
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
              const SizedBox(width: 6),
              Expanded(
                child: SelectableText(
                  entry.result,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: entry.error ? cs.error : cs.onSurface,
                  ),
                ),
              ),
              InkWell(
                onTap: () => onCopy(entry.result),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.copy_rounded,
                      size: 14, color: cs.onSurfaceVariant),
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
          _RunIntent: CallbackAction<_RunIntent>(onInvoke: (_) {
            if (!busy) onRun();
            return null;
          }),
          _HistUpIntent:
              CallbackAction<_HistUpIntent>(onInvoke: (_) {
            onHistoryUp();
            return null;
          }),
          _HistDownIntent:
              CallbackAction<_HistDownIntent>(onInvoke: (_) {
            onHistoryDown();
            return null;
          }),
        },
        child: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 8,
          enabled: !busy,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
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
