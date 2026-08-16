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
  final _replHistoryFocus = FocusNode(skipTraversal: true);
  final _consoleScroll = ScrollController();
  final _consoleScrollGuard = AutoFollowScrollGuard();
  bool _autoFollowConsole = true;
  bool _consoleFollowScheduled = false;
  int _lastConsoleFingerprint = 0;
  Offset? _lastConsoleMenuPosition;
  // history cursor: -1 表示当前没在历史里；0..len-1 指向某条历史。
  int _historyCursor = -1;

  // 退场动画：维护一份「显示用槽位」列表。当 controller
  // 的 consoleMessages 移除某条（cap 截断 / 清空）时，对应槽位标记
  // isExiting=true 并启动 240ms 计时器；到期后真正从 _slots 移除。
  // build 中按身份 identical(slot.entry, e) 与最新列表对齐，过滤命中
  // 当前 filter 才显示，但 _slots 持续保留以保证退场过程不丢失。
  final List<_ConsoleSlot> _slots = <_ConsoleSlot>[];
  final Set<CdpConsoleEntry> _expandedConsoleEntries = <CdpConsoleEntry>{};

  static const Duration _kConsoleExitDuration = kOpenHandMotion240;
  static const Duration _kConsoleFollowDuration = Duration(milliseconds: 320);
  static const int _kConsoleCollapsedChars = 420;
  static const int _kConsoleCollapsedLines = 4;
  static const double _kConsoleReplControlHeight = 40;
  static const double _kConsoleActionIconSize = 18;
  static const Color _kWarningContainerLight = Color(0xFFFFF1D2);
  static const Color _kWarningOnContainerLight = Color(0xFF5C3A00);
  static const Color _kWarningContainerDark = Color(0xFF4A3412);
  static const Color _kWarningOnContainerDark = Color(0xFFFFD99A);

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
    _replHistoryFocus.dispose();
    _consoleScroll.dispose();
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
    final currentSet = current.toSet();
    _expandedConsoleEntries.removeWhere((entry) => !currentSet.contains(entry));

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

    // 重建活跃部分顺序与 controller 一致；退场槽位按旧位置插回，
    // 避免 cap 截断 / 清空时退场项跳到列表尾部。
    final previousOrder = List<_ConsoleSlot>.of(_slots);
    final previousIndex = <_ConsoleSlot, int>{
      for (var i = 0; i < previousOrder.length; i++) previousOrder[i]: i,
    };
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
    final exitingSlots = _slots.where((s) => s.isExiting).toList()
      ..sort(
        (a, b) => (previousIndex[a] ?? 0).compareTo(previousIndex[b] ?? 0),
      );
    _slots
      ..clear()
      ..addAll(newActiveOrder);
    for (final exiting in exitingSlots) {
      final index = (previousIndex[exiting] ?? _slots.length)
          .clamp(0, _slots.length)
          .toInt();
      _slots.insert(index, exiting);
    }
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
    _scheduleConsoleFollow();
    // 通知 dashboard 异步把最新历史持久化到 session metadata。
    final dashState = context
        .findAncestorStateOfType<_WebReverseDashboardDialogState>();
    dashState?.persistConsoleReplHistory();
    final r = await widget.controller.runReplExpression(raw);
    if (!mounted) return;
    _scheduleConsoleFollow();
    final loc = AppLocalizations.of(context);
    if (r == null) {
      showOpenHandErrorSnack(
        context,
        loc?.webReverseConsoleEvalFailed ?? 'Eval failed',
        duration: kOpenHandSnackBarBriefDuration,
      );
    }
  }

  bool _isLongConsoleText(String text) {
    if (text.runes.length > _kConsoleCollapsedChars) return true;
    return '\n'.allMatches(text).length >= _kConsoleCollapsedLines;
  }

  String _previewConsoleText(String text) {
    final lines = text.split('\n');
    final lineLimited = lines.take(_kConsoleCollapsedLines).join('\n');
    final truncatedByLines = lines.length > _kConsoleCollapsedLines;
    final runes = lineLimited.runes.toList(growable: false);
    final truncatedByChars = runes.length > _kConsoleCollapsedChars;
    final charLimited = truncatedByChars
        ? String.fromCharCodes(runes.take(_kConsoleCollapsedChars))
        : lineLimited;
    return truncatedByLines || truncatedByChars
        ? '$charLimited...'
        : charLimited;
  }

  Future<void> _copyConsoleText(String text) async {
    await copyWebReverseTextToClipboard(
      context: context,
      text: text,
      successBase: openHandLocalizedText(
        context,
        zh: '控制台全文已复制',
        zhHant: '主控台全文已複製',
        en: 'Console text copied',
        fr: 'Texte de console copié',
        de: 'Konsolentext kopiert',
        ja: 'コンソール全文をコピーしました',
      ),
      logTag: 'web_reverse_console_panel',
      logAction: '复制控制台文本',
    );
  }

  ({Color color, Color onColor}) _consoleEntryColors(
    ThemeData theme,
    ColorScheme cs,
    String level,
  ) {
    final warningColor = theme.brightness == Brightness.dark
        ? _kWarningContainerDark
        : _kWarningContainerLight;
    final warningOnColor = theme.brightness == Brightness.dark
        ? _kWarningOnContainerDark
        : _kWarningOnContainerLight;
    return switch (level) {
      'error' => (color: cs.errorContainer, onColor: cs.onErrorContainer),
      'warning' || 'warn' => (color: warningColor, onColor: warningOnColor),
      'repl-input' => (
        color: cs.primaryContainer,
        onColor: cs.onPrimaryContainer,
      ),
      'repl-result' => (
        color: cs.secondaryContainer,
        onColor: cs.onSecondaryContainer,
      ),
      _ => (color: cs.surfaceContainerHigh, onColor: cs.onSurface),
    };
  }

  int _consoleFingerprint(List<CdpConsoleEntry> entries) {
    if (entries.isEmpty) return 0;
    return Object.hash(entries.length, identityHashCode(entries.last));
  }

  void _scheduleConsoleFollow({bool force = false}) {
    if ((!_autoFollowConsole && !force) || _consoleFollowScheduled) return;
    _consoleFollowScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consoleFollowScheduled = false;
      if (!mounted) return;
      _consoleScrollGuard.followToBottom(
        _consoleScroll,
        animated: !widget.reduceMotion,
        animationDuration: _kConsoleFollowDuration,
      );
    });
  }

  void _toggleConsoleAutoFollow() {
    setState(() => _autoFollowConsole = !_autoFollowConsole);
    if (_autoFollowConsole) {
      _scheduleConsoleFollow(force: true);
    }
  }

  ButtonStyle _consoleAutoFollowButtonStyle(ColorScheme cs) {
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return cs.primary;
        return null;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return cs.onPrimary;
        return null;
      }),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (!states.contains(WidgetState.selected)) return null;
        if (states.contains(WidgetState.pressed)) {
          return cs.onPrimary.withValues(alpha: 0.12);
        }
        if (states.contains(WidgetState.hovered)) {
          return cs.onPrimary.withValues(alpha: 0.08);
        }
        if (states.contains(WidgetState.focused)) {
          return cs.onPrimary.withValues(alpha: 0.10);
        }
        return null;
      }),
    );
  }

  Future<void> _showConsoleEntryMenu({
    required CdpConsoleEntry entry,
    required Offset position,
    required bool longText,
    required bool expanded,
  }) async {
    final selected = await showAnimatedPointerMenu<_ConsoleEntryAction>(
      context: context,
      globalPosition: position,
      items: [
        if (longText)
          PopupMenuItem<_ConsoleEntryAction>(
            value: _ConsoleEntryAction.toggleExpanded,
            child: Row(
              children: [
                Icon(
                  expanded
                      ? Icons.unfold_less_rounded
                      : Icons.unfold_more_rounded,
                  size: 18,
                ),
                kOpenHandHGap10,
                Text(
                  expanded
                      ? openHandLocalizedText(
                          context,
                          zh: '收起',
                          zhHant: '收合',
                          en: 'Collapse',
                          fr: 'Réduire',
                          de: 'Einklappen',
                          ja: '折りたたむ',
                        )
                      : openHandLocalizedText(
                          context,
                          zh: '展开全文',
                          zhHant: '展開全文',
                          en: 'Expand',
                          fr: 'Développer',
                          de: 'Erweitern',
                          ja: '全文を展開',
                        ),
                ),
              ],
            ),
          ),
        PopupMenuItem<_ConsoleEntryAction>(
          value: _ConsoleEntryAction.copyText,
          child: Row(
            children: [
              const Icon(Icons.copy_rounded, size: 18),
              kOpenHandHGap10,
              Text(
                openHandLocalizedText(
                  context,
                  zh: '复制全文',
                  zhHant: '複製全文',
                  en: 'Copy full',
                  fr: 'Copier tout',
                  de: 'Alles kopieren',
                  ja: '全文をコピー',
                ),
              ),
            ],
          ),
        ),
      ],
      shape: const RoundedRectangleBorder(borderRadius: kOpenHandBorderRadius12),
    );
    if (!mounted || selected == null) return;
    switch (selected) {
      case _ConsoleEntryAction.toggleExpanded:
        if (!longText) return;
        setState(() {
          if (expanded) {
            _expandedConsoleEntries.remove(entry);
          } else {
            _expandedConsoleEntries.add(entry);
          }
        });
      case _ConsoleEntryAction.copyText:
        await _copyConsoleText(entry.text);
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
    final fingerprint = _consoleFingerprint(widget.controller.consoleMessages);
    if (fingerprint != _lastConsoleFingerprint) {
      _lastConsoleFingerprint = fingerprint;
      _scheduleConsoleFollow();
    }
    final filter = widget.filter.toLowerCase();
    // _slots 当前是 controller 顺序（旧 → 新）+ 按原位置保留的退场槽位；
    // 控制台按常规时间线从上到下渲染，新消息追加到尾部。
    // 退场中的槽位无论是否命中 filter 都要继续显示，否则会瞬间消失。
    final ordered = _slots;
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
              ? OpenHandInlineEmptyState(
                  message:
                      loc?.webReverseConsoleEmpty ?? 'No console output yet.',
                )
              : NotificationListener<ScrollNotification>(
                  onNotification: _consoleScrollGuard.handleNotification,
                  child: OpenHandSafeScrollbar(
                    controller: _consoleScroll,
                    thumbVisibility: true,
                    thickness: 8,
                    radius: kOpenHandPillRadius,
                    child: ListView.builder(
                      controller: _consoleScroll,
                      padding: const EdgeInsets.all(12),
                      itemCount: visible.length,
                      itemBuilder: (_, idx) {
                        final slot = visible[idx];
                        final e = slot.entry;
                        final palette = _consoleEntryColors(theme, cs, e.level);
                        final color = palette.color;
                        final onColor = palette.onColor;
                        final longText = _isLongConsoleText(e.text);
                        final expanded = _expandedConsoleEntries.contains(e);
                        final displayText = longText && !expanded
                            ? _previewConsoleText(e.text)
                            : e.text;
                        final card = Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: kOpenHandBorderRadius8,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 84,
                                child: Text(
                                  e.level.toUpperCase(),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontFamily: kOpenHandMonospaceFontFamily,
                                    color: onColor.withValues(alpha: 0.75),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    AnimatedSize(
                                      duration: widget.reduceMotion
                                          ? Duration.zero
                                          : _kConsoleExitDuration,
                                      curve: Curves.easeOutBack,
                                      alignment: Alignment.topLeft,
                                      child: SelectableText(
                                        displayText,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              fontFamily:
                                                  kOpenHandMonospaceFontFamily,
                                              color: onColor,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                        final padded = Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onDoubleTapDown: (details) {
                              _lastConsoleMenuPosition = details.globalPosition;
                            },
                            onDoubleTap: () {
                              _showConsoleEntryMenu(
                                entry: e,
                                position:
                                    _lastConsoleMenuPosition ?? Offset.zero,
                                longText: longText,
                                expanded: expanded,
                              );
                            },
                            onSecondaryTapDown: (details) {
                              _showConsoleEntryMenu(
                                entry: e,
                                position: details.globalPosition,
                                longText: longText,
                                expanded: expanded,
                              );
                            },
                            child: card,
                          ),
                        );
                        // 退场：240ms 内 AnimatedSize 折叠 + AnimatedOpacity
                        // 淡出 + 轻微缩放，与 _TabStrip 退场风格保持一致。
                        if (widget.reduceMotion) {
                          return slot.isExiting
                              ? const SizedBox.shrink()
                              : padded;
                        }
                        return AnimatedSize(
                          key: ValueKey(identityHashCode(slot)),
                          duration: openHandMotionDuration(
                            context,
                            _kConsoleExitDuration,
                          ),
                          curve: Curves.easeInCubic,
                          alignment: Alignment.topCenter,
                          child: AnimatedOpacity(
                            duration: openHandMotionDuration(
                              context,
                              _kConsoleExitDuration,
                            ),
                            curve: Curves.easeOut,
                            opacity: slot.isExiting ? 0.0 : 1.0,
                            child: AnimatedScale(
                              duration: openHandMotionDuration(
                                context,
                                _kConsoleExitDuration,
                              ),
                              curve: Curves.easeInCubic,
                              scale: slot.isExiting ? 0.92 : 1.0,
                              child: slot.isExiting
                                  ? padded
                                  : AppearOnce(
                                      duration: _kSwitchDuration,
                                      child: padded,
                                    ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
        ),
        Divider(height: 1, color: cs.outlineVariant),
        // REPL 输入：单行。回车执行；上下方向键浏览历史；
        // 结果通过 controller.runReplExpression 写入 console，复用渲染。
        AnimatedSize(
          duration: openHandMotionDuration(context, kOpenHandMotion280),
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
                      borderRadius: kOpenHandBorderRadius8,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.pause_circle_filled_rounded,
                          size: 14,
                          color: cs.onErrorContainer,
                        ),
                        kOpenHandHGap6,
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
              Expanded(
                child: SizedBox(
                  height: _kConsoleReplControlHeight,
                  child: KeyboardListener(
                    focusNode: _replHistoryFocus,
                    onKeyEvent: _onReplKey,
                    child: TextField(
                      controller: _replCtrl,
                      focusNode: _replFocus,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: kOpenHandMonospaceFontFamily,
                        fontSize: 12.5,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        hintText:
                            loc?.webReverseConsoleReplHint ??
                            'JS expression; ↑↓ history',
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: _runExpr,
                    ),
                  ),
                ),
              ),
              kOpenHandHGap8,
              Tooltip(
                message: _autoFollowConsole
                    ? openHandLocalizedText(
                        context,
                        zh: '自动跟随已开启',
                        zhHant: '自動跟隨已開啟',
                        en: 'Auto-follow on',
                        fr: 'Suivi auto activé',
                        de: 'Automatisches Folgen ein',
                        ja: '自動追従オン',
                      )
                    : openHandLocalizedText(
                        context,
                        zh: '自动跟随已关闭',
                        zhHant: '自動跟隨已關閉',
                        en: 'Auto-follow off',
                        fr: 'Suivi auto désactivé',
                        de: 'Automatisches Folgen aus',
                        ja: '自動追従オフ',
                      ),
                child: SizedBox(
                  width: _kConsoleReplControlHeight,
                  height: _kConsoleReplControlHeight,
                  child: IconButton.filledTonal(
                    isSelected: _autoFollowConsole,
                    selectedIcon: const Icon(
                      Icons.vertical_align_bottom_rounded,
                      size: _kConsoleActionIconSize,
                    ),
                    icon: const Icon(
                      Icons.vertical_align_bottom_outlined,
                      size: _kConsoleActionIconSize,
                    ),
                    onPressed: _toggleConsoleAutoFollow,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    style: _consoleAutoFollowButtonStyle(cs),
                  ),
                ),
              ),
              kOpenHandHGap8,
              SizedBox(
                height: _kConsoleReplControlHeight,
                child: FilledButton.icon(
                  onPressed: () => _runExpr(_replCtrl.text),
                  icon: const Icon(
                    Icons.play_arrow_rounded,
                    size: _kConsoleActionIconSize,
                  ),
                  label: Text(loc?.webReverseReplRun ?? 'Run'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size(0, _kConsoleReplControlHeight),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
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

enum _ConsoleEntryAction { toggleExpanded, copyText }
