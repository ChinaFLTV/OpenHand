part of 'web_reverse_dashboard_dialog.dart';

class _ConsoleBody extends StatefulWidget {
  const _ConsoleBody({
    required this.controller,
    required this.filter,
    required this.isZh,
    required this.reduceMotion,
  });

  final WebReverseSessionController controller;
  final String filter;
  final bool isZh;
  final bool reduceMotion;

  @override
  State<_ConsoleBody> createState() => _ConsoleBodyState();
}

class _ConsoleBodyState extends State<_ConsoleBody> {
  final _replCtrl = TextEditingController();
  final _replFocus = FocusNode();
  // 表达式历史；上下方向键回放最近 50 条。
  final List<String> _history = <String>[];
  int _historyCursor = -1;

  @override
  void dispose() {
    _replCtrl.dispose();
    _replFocus.dispose();
    super.dispose();
  }

  Future<void> _runExpr(String expr) async {
    final raw = expr.trim();
    if (raw.isEmpty) return;
    _history.add(raw);
    while (_history.length > 50) {
      _history.removeAt(0);
    }
    _historyCursor = _history.length;
    _replCtrl.clear();
    final r = await widget.controller.runReplExpression(raw);
    if (!mounted) return;
    final isZh = widget.isZh;
    final cs = Theme.of(context).colorScheme;
    if (r == null) {
      OpenHandSnackBar.show(
        context,
        ScaffoldMessenger.of(context),
        SnackBar(
          backgroundColor: cs.errorContainer,
          content: Text(isZh ? '执行失败' : 'Eval failed'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  KeyEventResult _onReplKey(KeyEvent ev) {
    if (ev is! KeyDownEvent) return KeyEventResult.ignored;
    if (ev.logicalKey == LogicalKeyboardKey.arrowUp && _history.isNotEmpty) {
      _historyCursor = (_historyCursor - 1).clamp(0, _history.length - 1);
      _replCtrl.text = _history[_historyCursor];
      _replCtrl.selection =
          TextSelection.collapsed(offset: _replCtrl.text.length);
      return KeyEventResult.handled;
    }
    if (ev.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_historyCursor < _history.length - 1) {
        _historyCursor++;
        _replCtrl.text = _history[_historyCursor];
        _replCtrl.selection =
            TextSelection.collapsed(offset: _replCtrl.text.length);
      } else {
        _historyCursor = _history.length;
        _replCtrl.clear();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isZh = widget.isZh;
    final all = widget.controller.consoleMessages;
    final filter = widget.filter;
    final filtered = filter.isEmpty
        ? all
        : all
            .where((e) => e.text.toLowerCase().contains(filter.toLowerCase()))
            .toList(growable: false);
    return Column(
      children: [
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      isZh ? '暂无控制台输出。' : 'No console output yet.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: filtered.length,
                  itemBuilder: (_, idx) {
                    final e = filtered[filtered.length - 1 - idx];
                    final color = switch (e.level) {
                      'error' => cs.errorContainer,
                      'warning' => cs.tertiaryContainer,
                      'repl-input' => cs.primaryContainer,
                      'repl-result' => cs.secondaryContainer,
                      _ => cs.surfaceContainerHigh,
                    };
                    final onColor = switch (e.level) {
                      'error' => cs.onErrorContainer,
                      'warning' => cs.onTertiaryContainer,
                      'repl-input' => cs.onPrimaryContainer,
                      'repl-result' => cs.onSecondaryContainer,
                      _ => cs.onSurface,
                    };
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _AnimatedAppearOnce(
                        duration: widget.reduceMotion
                            ? Duration.zero
                            : _kSwitchDuration,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 84,
                                child: Text(
                                  e.level.toUpperCase(),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontFamily: 'monospace',
                                    color:
                                        onColor.withValues(alpha: 0.75),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: SelectableText(
                                  e.text,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
                                    color: onColor,
                                  ),
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
        Divider(height: 1, color: cs.outlineVariant),
        // REPL 输入：单行。回车执行；上下方向键浏览历史；
        // 结果通过 controller.runReplExpression 写入 console，复用渲染。
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Row(
            children: [
              Icon(Icons.chevron_right_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 6),
              Expanded(
                child: KeyboardListener(
                  focusNode: FocusNode(skipTraversal: true),
                  onKeyEvent: _onReplKey,
                  child: TextField(
                    controller: _replCtrl,
                    focusNode: _replFocus,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: isZh
                          ? '输入 JS 表达式回车执行；↑↓ 浏览历史'
                          : 'JS expression; ↑↓ history',
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: _runExpr,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _runExpr(_replCtrl.text),
                icon: const Icon(Icons.play_arrow_rounded, size: 16),
                label: Text(isZh ? '执行' : 'Run'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
