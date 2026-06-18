part of 'web_reverse_dashboard_dialog.dart';

class _ConsoleBody extends StatefulWidget {
  const _ConsoleBody({
    required this.controller,
    required this.filter,
    required this.reduceMotion,
  });

  final WebReverseSessionController controller;
  final String filter;
  final bool reduceMotion;

  @override
  State<_ConsoleBody> createState() => _ConsoleBodyState();
}

class _ConsoleBodyState extends State<_ConsoleBody> {
  final _replCtrl = TextEditingController();
  final _replFocus = FocusNode();
  // history cursor: -1 表示当前没在历史里；0..len-1 指向某条历史。
  int _historyCursor = -1;

  // 2026-05-25 — 退场动画：维护一份「显示用槽位」列表。当 controller
  // 的 consoleMessages 移除某条（cap 截断 / 清空）时，对应槽位标记
  // isExiting=true 并启动 240ms 计时器；到期后真正从 _slots 移除。
  // build 中按身份 identical(slot.entry, e) 与最新列表对齐，过滤命中
  // 当前 filter 才显示，但 _slots 持续保留以保证退场过程不丢失。
  final List<_ConsoleSlot> _slots = <_ConsoleSlot>[];

  static const Duration _kConsoleExitDuration = Duration(milliseconds: 240);

  List<String> get _history => widget.controller.replHistory;

  // 跟踪上一次的暂停态：仅在 isPaused 翻转时 setState，避免控制器其他
  // 通知（如 console 新增）让我们重复 rebuild（_syncSlots 已经处理 console）。
  bool _wasPaused = false;

  @override
  void initState() {
    super.initState();
    _wasPaused = widget.controller.isPaused;
    widget.controller.addListener(_onPauseStateMaybeChanged);
  }

  void _onPauseStateMaybeChanged() {
    if (!mounted) return;
    final now = widget.controller.isPaused;
    if (now != _wasPaused) {
      _wasPaused = now;
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onPauseStateMaybeChanged);
    for (final s in _slots) {
      s.exitTimer?.cancel();
    }
    _replCtrl.dispose();
    _replFocus.dispose();
    super.dispose();
  }

  /// 将 _slots 与 controller.consoleMessages 对齐：
  ///   - 仍存在的条目：保留对应 slot；
  ///   - 新增的条目：插入新 slot（位置按 controller 列表顺序）；
  ///   - 已被移除的条目：标记 exiting + 启动计时器，下一帧仍渲染。
  /// 注意：本方法可在 build 中同步调用（仅修改 _slots 内部字段，不在
  /// build 中触发 setState），exitTimer 回调里才会 setState 真正抠掉。
  void _syncSlots() {
    final current = widget.controller.consoleMessages;

    // 已存在的 slot 中，找出在新列表里不再出现且尚未在退场的 → 标记退场。
    for (final s in _slots) {
      if (s.isExiting) continue;
      if (_findInList(current, s.entry) == null) {
        s.isExiting = true;
        s.exitTimer?.cancel();
        s.exitTimer = startSafeTimer(_kConsoleExitDuration, () {
          if (!mounted) return;
          setState(() {
            _slots.remove(s);
          });
        });
      }
    }

    // 重建活跃部分顺序与 controller 一致；退场槽位维持原位置。
    final newActiveOrder = <_ConsoleSlot>[];
    for (final e in current) {
      _ConsoleSlot? hit;
      for (final s in _slots) {
        if (!s.isExiting && identical(s.entry, e)) {
          hit = s;
          break;
        }
      }
      hit ??= _ConsoleSlot(e);
      newActiveOrder.add(hit);
    }
    // 提取仍在退场中的 slot（保持其在原 _slots 的相对位置）。
    final exitingSlots = _slots.where((s) => s.isExiting).toList();
    _slots
      ..clear()
      ..addAll(newActiveOrder)
      ..addAll(exitingSlots);
  }

  CdpConsoleEntry? _findInList(
    List<CdpConsoleEntry> list,
    CdpConsoleEntry target,
  ) {
    for (final e in list) {
      if (identical(e, target)) return e;
    }
    return null;
  }

  Future<void> _runExpr(String expr) async {
    final raw = expr.trim();
    if (raw.isEmpty) return;
    widget.controller.pushReplHistory(raw);
    _historyCursor = -1;
    _replCtrl.clear();
    // 通知 dashboard 异步把最新历史持久化到 session metadata。
    final dashState = context
        .findAncestorStateOfType<_WebReverseDashboardDialogState>();
    dashState?.persistConsoleReplHistory();
    final r = await widget.controller.runReplExpression(raw);
    if (!mounted) return;
    final loc = AppLocalizations.of(context);
    if (r == null) {
      OpenHandSnackBar.showError(
        context,
        loc?.webReverseConsoleEvalFailed ?? 'Eval failed',
        duration: const Duration(seconds: 2),
      );
    }
  }

  KeyEventResult _onReplKey(KeyEvent ev) {
    if (ev is! KeyDownEvent) return KeyEventResult.ignored;
    final hist = _history;
    if (ev.logicalKey == LogicalKeyboardKey.arrowUp && hist.isNotEmpty) {
      // 上箭头：往更早走。从底往上滚。
      if (_historyCursor < 0) {
        _historyCursor = hist.length - 1;
      } else if (_historyCursor > 0) {
        _historyCursor--;
      }
      _replCtrl.text = hist[_historyCursor];
      _replCtrl.selection = TextSelection.collapsed(
        offset: _replCtrl.text.length,
      );
      return KeyEventResult.handled;
    }
    if (ev.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_historyCursor < 0) return KeyEventResult.ignored;
      if (_historyCursor < hist.length - 1) {
        _historyCursor++;
        _replCtrl.text = hist[_historyCursor];
        _replCtrl.selection = TextSelection.collapsed(
          offset: _replCtrl.text.length,
        );
      } else {
        _historyCursor = -1;
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
    final loc = AppLocalizations.of(context);
    _syncSlots();
    final filter = widget.filter.toLowerCase();
    // _slots 当前是 controller 顺序（旧 → 新）+ 已退场槽位；UI 想要新在
    // 上、旧在下，因此 reverse 后再过滤 / 渲染。退场中的槽位无论是否
    // 命中 filter 都要继续显示，否则它们会瞬间消失，吃掉退场动画。
    final ordered = _slots.reversed.toList(growable: false);
    final visible = filter.isEmpty
        ? ordered
        : ordered
              .where(
                (s) =>
                    s.isExiting || s.entry.text.toLowerCase().contains(filter),
              )
              .toList(growable: false);
    final hasContent = visible.any((s) => !s.isExiting);
    return Column(
      children: [
        Expanded(
          child: !hasContent && visible.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      loc?.webReverseConsoleEmpty ?? 'No console output yet.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: visible.length,
                  itemBuilder: (_, idx) {
                    final slot = visible[idx];
                    final e = slot.entry;
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
                    final card = Container(
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
                                color: onColor.withValues(alpha: 0.75),
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
                    );
                    final padded = Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: card,
                    );
                    // 退场：240ms 内 AnimatedSize 折叠 + AnimatedOpacity
                    // 淡出 + 轻微缩放，与 _TabStrip 退场风格保持一致。
                    if (widget.reduceMotion) {
                      return slot.isExiting ? const SizedBox.shrink() : padded;
                    }
                    return AnimatedSize(
                      key: ValueKey(identityHashCode(slot)),
                      duration: _kConsoleExitDuration,
                      curve: Curves.easeInCubic,
                      alignment: Alignment.topCenter,
                      child: AnimatedOpacity(
                        duration: _kConsoleExitDuration,
                        curve: Curves.easeOut,
                        opacity: slot.isExiting ? 0.0 : 1.0,
                        child: AnimatedScale(
                          duration: _kConsoleExitDuration,
                          curve: Curves.easeInCubic,
                          scale: slot.isExiting ? 0.92 : 1.0,
                          child: slot.isExiting
                              ? padded
                              : _AnimatedAppearOnce(
                                  duration: _kSwitchDuration,
                                  child: padded,
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
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: widget.controller.isPaused
              ? FadeTransition(
                  opacity: const AlwaysStoppedAnimation(1),
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: cs.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.pause_circle_filled_rounded,
                          size: 14,
                          color: cs.onErrorContainer,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            loc?.webReverseConsolePausedHint ??
                                'Debugger paused · expressions evaluate in the top frame scope',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
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
                      hintText:
                          loc?.webReverseConsoleReplHint ??
                          'JS expression; ↑↓ history',
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
                label: Text(loc?.webReverseReplRun ?? 'Run'),
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

/// 控制台单条消息的渲染槽位：包裹 entry + 退场状态 + 定时器，让
/// `_ConsoleBodyState` 在条目被 controller 移除（cap 截断 / 清空）后
/// 仍能保留 240ms 的折叠 + 淡出动画。
class _ConsoleSlot {
  _ConsoleSlot(this.entry);

  final CdpConsoleEntry entry;
  bool isExiting = false;
  Timer? exitTimer;
}
