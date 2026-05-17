part of 'web_reverse_dashboard_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────
// 内嵌浏览器面板：CDP screencast 帧渲染 + 输入桥（鼠标 / 滚轮 / 键盘）
//
// 设计要点：
//   1. 资源控制 —— 进入面板时调一次 `acquireScreencast`，离开 / dispose 时
//      `releaseScreencast`；controller 内部用引用计数避免重复 start/stop。
//      切到其它 tab 立即 release，浏览器立刻停推帧；切回再 acquire。这避免
//      "用户切走后帧仍在后台跑、堆积内存"。
//   2. 帧渲染 —— controller 暴露 [screencastFrameNotifier]，[_ScreencastImage]
//      用 [ValueListenableBuilder] 订阅它做局部 repaint，外层 Padding / Stack /
//      Column 完全不参与 60fps 帧流。每帧到达时帧序号 +1，[Image.memory] 用
//      ValueKey 触发 RepaintBoundary 内重绘。
//   3. 输入桥 —— Listener 捕获 PointerDown/Move/Up/Wheel；Focus.onKeyEvent
//      捕获物理键盘并通过 CDP `Input.dispatchMouseEvent` / `dispatchKeyEvent`
//      实时下发，所有事件先把本地坐标除以 devicePixelRatio 折算到浏览器
//      viewport（CSS 像素），保证 retina 一致。
//   4. 视口同步 —— widget 矩形在用户拖大 / 拖小窗口时变化，触发去抖 220ms
//      调 `reconfigureScreencast`，让浏览器侧 maxWidth/maxHeight 跟手。
// ─────────────────────────────────────────────────────────────────────────

class _BrowserBody extends StatefulWidget {
  const _BrowserBody({
    required this.controller,
    required this.isZh,
  });

  final WebReverseSessionController controller;
  final bool isZh;

  @override
  State<_BrowserBody> createState() => _BrowserBodyState();
}

class _BrowserBodyState extends State<_BrowserBody> implements TextInputClient {
  final TextEditingController _addressCtrl = TextEditingController();
  final FocusNode _surfaceFocus = FocusNode(debugLabel: 'browser-surface');
  final FocusNode _addressBarFocus = FocusNode(debugLabel: 'browser-address');
  final FocusNode _findFocus = FocusNode(debugLabel: 'browser-find');
  final TextEditingController _findCtrl = TextEditingController();
  bool _findBarOpen = false;
  int _findMatchCount = 0;
  Timer? _findDebouncer;
  Timer? _resizeDebouncer;
  Timer? _urlPoller;
  bool _addressEditing = false;
  Size? _lastConfiguredSize;
  double _lastDpr = 1;
  int _buttons = 0;
  // 缓存当前帧的浏览器 viewport 尺寸，将本地命中点折算成 CSS 像素时使用。
  // 注意：浏览器侧 maxWidth / maxHeight 是上界，实际帧可能更小。
  int _frameW = 1280;
  int _frameH = 720;
  // 上次记录的 alive 状态：浏览器死亡 / 拉起切换时整体 rebuild 一次，
  // 让按钮、placeholder 立刻响应。
  bool _wasAlive = false;
  // 浏览器侧 setPageScaleFactor 的当前值；面板内独立维护，下次切到 dashboard
  // 重新 attach 时不会保留（Chromium 重启即丢）。
  double _zoom = 1;
  // 上次记录的 tab 列表标识：targets 数量 / currentId 任一变化即 rebuild。
  int _lastTargetsLen = 0;
  String? _lastCurrentTargetId;
  // 框选导出模式：进入后吞掉所有指针事件，完成时把当前 viewport 矩形按
  // 浏览器侧 CSS 像素裁切成 PNG。
  bool _cropMode = false;
  Offset? _cropStart;
  Offset? _cropCurrent;

  // ── IME 桥（TextInputClient 手动接管） ────────────────────────────────
  // surface 拿到焦点时打开一条 TextInput connection，把 IME 候选词、回车 /
  // 退格、跨端剪贴板粘贴等都拿到 [updateEditingValue]。我们仅在 composing
  // 区间收敛后把"新增文本"作为一次 insertText 发到 CDP，删除字符则发
  // Backspace 序列；这样既支持中文 / 日文 / 韩文输入，又不会和物理键盘
  // 走的 Focus.onKeyEvent 重复下发文本字符。
  TextInputConnection? _imeConnection;
  TextEditingValue _lastImeValue = TextEditingValue.empty;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _surfaceFocus.addListener(_onSurfaceFocusChanged);
    _wasAlive = widget.controller.isBrowserAlive;
    // 首次进入时同步一次地址栏；CDP 已稳定时立即拉。
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final url = await widget.controller.currentUrl();
      if (!mounted || url == null) return;
      if (_addressCtrl.text != url) _addressCtrl.text = url;
    });
    // 进入面板就 acquire；离开 dispose 时 release。
    widget.controller.acquireScreencast();
    // 用户正在编辑地址栏时不强行覆写；导航 / 跳转后定时拉一次同步真实 URL。
    _urlPoller = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted || _addressEditing) return;
      final url = await widget.controller.currentUrl();
      if (!mounted || url == null) return;
      final addrChanged = _addressCtrl.text != url;
      if (addrChanged) _addressCtrl.text = url;
      // 同时让 controller 的 page target 列表 url 字段保持同步——targetInfoChanged
      // 在某些场景下不会立刻到达，这里兜底把当前 target 的 url 字段也改了。
      final cur = widget.controller.currentPageTargetId;
      if (cur != null) {
        final updated = <CdpPageTargetSnapshot>[];
        var dirty = false;
        for (final t in widget.controller.pageTargets) {
          if (t.id == cur && t.url != url) {
            updated.add(CdpPageTargetSnapshot(
              id: t.id,
              url: url,
              title: t.title,
            ));
            dirty = true;
          } else {
            updated.add(t);
          }
        }
        if (dirty) {
          widget.controller.replacePageTargets(updated);
          _persistTabsAndUrls();
        }
      }
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _surfaceFocus.removeListener(_onSurfaceFocusChanged);
    _resizeDebouncer?.cancel();
    _urlPoller?.cancel();
    _findDebouncer?.cancel();
    _metaPersistDebouncer?.cancel();
    widget.controller.releaseScreencast();
    _detachImeConnection();
    _addressCtrl.dispose();
    _surfaceFocus.dispose();
    _addressBarFocus.dispose();
    _findFocus.dispose();
    _findCtrl.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final w = widget.controller.screencastWidth;
    final h = widget.controller.screencastHeight;
    final alive = widget.controller.isBrowserAlive;
    final len = widget.controller.pageTargets.length;
    final cur = widget.controller.currentPageTargetId;
    final dirty = w != _frameW ||
        h != _frameH ||
        alive != _wasAlive ||
        len != _lastTargetsLen ||
        cur != _lastCurrentTargetId;
    final aliveJustFlipped = alive && !_wasAlive;
    _frameW = w;
    _frameH = h;
    _wasAlive = alive;
    _lastTargetsLen = len;
    _lastCurrentTargetId = cur;
    if (dirty) setState(() {});
    if (aliveJustFlipped) {
      // 浏览器刚拉起 / 重启完毕：尝试用上一轮持久化的 tab URL 恢复多 tab 场景。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final state = context
            .findAncestorStateOfType<_WebReverseDashboardDialogState>();
        state?.restoreBrowserTabs();
      });
    }
  }

  void _scheduleViewportSync(Size logical, double dpr) {
    if (_lastConfiguredSize == logical && _lastDpr == dpr) return;
    _lastConfiguredSize = logical;
    _lastDpr = dpr;
    _resizeDebouncer?.cancel();
    _resizeDebouncer = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      final w = (logical.width * dpr).round().clamp(160, 2560);
      final h = (logical.height * dpr).round().clamp(120, 1600);
      // 自适应帧率档位：viewport 大时降到 30fps + quality 65 节流，激活时
      // 升到 60fps + quality 80。临界值取 1600 像素长边，平衡 retina
      // 大屏 1440p / 4K 与常规 1280×720 dashboard 视窗。
      final big = math.max(w, h) > 1600;
      final everyNthFrame = big ? 2 : 1;
      final quality = big ? 65 : 80;
      widget.controller.reconfigureScreencast(
        maxWidth: w,
        maxHeight: h,
        quality: quality,
        everyNthFrame: everyNthFrame,
      );
    });
  }

  Offset _toViewport(Offset local, Size renderSize) {
    if (renderSize.width <= 0 || renderSize.height <= 0) {
      return Offset.zero;
    }
    final fx = local.dx / renderSize.width;
    final fy = local.dy / renderSize.height;
    return Offset(
      (fx * _frameW).clamp(0, _frameW - 1).toDouble(),
      (fy * _frameH).clamp(0, _frameH - 1).toDouble(),
    );
  }

  String _buttonName(int buttons) {
    if ((buttons & kPrimaryButton) != 0) return 'left';
    if ((buttons & kSecondaryButton) != 0) return 'right';
    if ((buttons & kMiddleMouseButton) != 0) return 'middle';
    return 'none';
  }

  int _modifiersFromKeys() {
    var m = 0;
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    if (pressed.contains(LogicalKeyboardKey.altLeft) ||
        pressed.contains(LogicalKeyboardKey.altRight)) {
      m |= 1;
    }
    if (pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight)) {
      m |= 2;
    }
    if (pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight)) {
      m |= 4;
    }
    if (pressed.contains(LogicalKeyboardKey.shiftLeft) ||
        pressed.contains(LogicalKeyboardKey.shiftRight)) {
      m |= 8;
    }
    return m;
  }

  void _handlePointerDown(PointerDownEvent e, Size renderSize) {
    _surfaceFocus.requestFocus();
    if (_cropMode) {
      // 第一次按下确定框选起点；之后 PointerMove 实时更新；松手 finalize。
      // 框选模式下不下发任何 mouse 事件到 CDP。
      setState(() {
        _cropStart = e.localPosition;
        _cropCurrent = e.localPosition;
      });
      return;
    }
    // 右键改为弹出 Flutter 渲染的上下文菜单（screencast 模式下浏览器原生
    // 右键菜单只会出现在外部 Chrome 窗口里，对内嵌面板的用户不可见）。
    // 注意不更新 _buttons，避免随后到达的 PointerUp 把右键当成 mouse
    // released 转发到浏览器。
    if ((e.buttons & kSecondaryButton) != 0) {
      _showContextMenu(e.position, renderSize, e.localPosition);
      return;
    }
    _buttons = e.buttons;
    final p = _toViewport(e.localPosition, renderSize);
    widget.controller.dispatchMouseEvent(
      type: 'mousePressed',
      x: p.dx,
      y: p.dy,
      button: _buttonName(e.buttons),
      buttons: e.buttons,
      clickCount: 1,
      modifiers: _modifiersFromKeys(),
    );
  }

  void _handlePointerMove(PointerMoveEvent e, Size renderSize) {
    if (_cropMode) {
      if (_cropStart == null) return;
      setState(() => _cropCurrent = e.localPosition);
      return;
    }
    final p = _toViewport(e.localPosition, renderSize);
    widget.controller.dispatchMouseEvent(
      type: 'mouseMoved',
      x: p.dx,
      y: p.dy,
      button: _buttonName(_buttons),
      buttons: e.buttons,
      modifiers: _modifiersFromKeys(),
    );
  }

  void _handlePointerHover(PointerHoverEvent e, Size renderSize) {
    if (_cropMode) return;
    final p = _toViewport(e.localPosition, renderSize);
    widget.controller.dispatchMouseEvent(
      type: 'mouseMoved',
      x: p.dx,
      y: p.dy,
      modifiers: _modifiersFromKeys(),
    );
  }

  void _handlePointerUp(PointerUpEvent e, Size renderSize) {
    if (_cropMode) {
      final start = _cropStart;
      final cur = _cropCurrent;
      if (start != null && cur != null && (start - cur).distance > 4) {
        unawaited(_finalizeCrop(start, cur, renderSize));
      } else {
        setState(() {
          _cropMode = false;
          _cropStart = null;
          _cropCurrent = null;
        });
      }
      return;
    }
    // 右键的按下我们已经截胡为 Flutter 上下文菜单，原 mouseUp 不需要发；
    // 否则会在浏览器侧产生一个孤立的 mouseReleased 事件。
    if (_buttons == 0) return;
    final p = _toViewport(e.localPosition, renderSize);
    widget.controller.dispatchMouseEvent(
      type: 'mouseReleased',
      x: p.dx,
      y: p.dy,
      button: _buttonName(_buttons),
      buttons: e.buttons,
      clickCount: 1,
      modifiers: _modifiersFromKeys(),
    );
    _buttons = 0;
  }

  void _handlePointerSignal(PointerSignalEvent e, Size renderSize) {
    if (_cropMode) return;
    if (e is PointerScrollEvent) {
      final p = _toViewport(e.localPosition, renderSize);
      widget.controller.dispatchMouseEvent(
        type: 'mouseWheel',
        x: p.dx,
        y: p.dy,
        deltaX: -e.scrollDelta.dx,
        deltaY: -e.scrollDelta.dy,
        modifiers: _modifiersFromKeys(),
      );
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    // 顶级快捷键拦截（Cmd on macOS / Ctrl elsewhere）：browser-like 操作走
    // 我们自己的 controller，不下发到浏览器侧（浏览器自身的快捷键被
    // screencast 屏蔽，需要 Flutter 端实现）。仅在 KeyDown 时触发，避免
    // KeyRepeat 二次触发误开多 tab / 关 tab。
    if (event is KeyDownEvent) {
      final pressed = HardwareKeyboard.instance.logicalKeysPressed;
      final hasMeta = pressed.contains(LogicalKeyboardKey.metaLeft) ||
          pressed.contains(LogicalKeyboardKey.metaRight);
      final hasCtrl = pressed.contains(LogicalKeyboardKey.controlLeft) ||
          pressed.contains(LogicalKeyboardKey.controlRight);
      final hasShift = pressed.contains(LogicalKeyboardKey.shiftLeft) ||
          pressed.contains(LogicalKeyboardKey.shiftRight);
      final cmd = Platform.isMacOS ? hasMeta : hasCtrl;
      if (cmd) {
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.keyT) {
          unawaited(_shortcutNewTab());
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.keyW) {
          unawaited(_shortcutCloseTab());
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.keyR) {
          unawaited(widget.controller.reload(ignoreCache: hasShift));
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.keyL) {
          _addressBarFocus.requestFocus();
          _addressCtrl.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _addressCtrl.text.length,
          );
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.keyF) {
          setState(() => _findBarOpen = true);
          // 等帧布局后让 find field 自动 focus，避免和 surface 焦点冲突。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _findFocus.requestFocus();
          });
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.equal ||
            key == LogicalKeyboardKey.add ||
            key == LogicalKeyboardKey.numpadAdd) {
          unawaited(_shortcutZoomDelta(1));
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.minus ||
            key == LogicalKeyboardKey.numpadSubtract) {
          unawaited(_shortcutZoomDelta(-1));
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.digit0 ||
            key == LogicalKeyboardKey.numpad0) {
          unawaited(_shortcutZoomReset());
          return KeyEventResult.handled;
        }
      }
      // Esc 关闭 find bar
      if (event.logicalKey == LogicalKeyboardKey.escape && _findBarOpen) {
        _closeFindBar();
        return KeyEventResult.handled;
      }
    }
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      final keyId = event.logicalKey.keyId;
      // 文本键（character 非空且为单字符）走 char 分发；功能键走 keyDown。
      final ch = event.character;
      if (ch != null && ch.isNotEmpty && keyId < 0x100) {
        widget.controller.dispatchKeyEvent(
          type: 'keyDown',
          key: ch,
          text: ch,
          modifiers: _modifiersFromKeys(),
          autoRepeat: event is KeyRepeatEvent,
        );
        return KeyEventResult.handled;
      }
      widget.controller.dispatchKeyEvent(
        type: 'rawKeyDown',
        key: _logicalKeyName(event.logicalKey),
        code: event.physicalKey.debugName,
        modifiers: _modifiersFromKeys(),
        autoRepeat: event is KeyRepeatEvent,
      );
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      widget.controller.dispatchKeyEvent(
        type: 'keyUp',
        key: _logicalKeyName(event.logicalKey),
        code: event.physicalKey.debugName,
        modifiers: _modifiersFromKeys(),
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── 快捷键实现 ────────────────────────────────────────────────────────

  Future<void> _shortcutNewTab() async {
    final id = await widget.controller.createPageTarget();
    if (id != null) await widget.controller.switchToPageTarget(id);
  }

  Future<void> _shortcutCloseTab() async {
    final cur = widget.controller.currentPageTargetId;
    if (cur == null) return;
    await widget.controller.closePageTarget(cur);
  }

  static const _zoomLadder = <double>[0.5, 0.75, 1.0, 1.25, 1.5];

  Future<void> _shortcutZoomDelta(int dir) async {
    var idx = _zoomLadder.indexWhere((v) => (v - _zoom).abs() < 0.01);
    if (idx < 0) {
      // 当前不是档位之一，先就近吸附。
      idx = 0;
      for (var i = 0; i < _zoomLadder.length; i++) {
        if ((_zoomLadder[i] - _zoom).abs() <
            (_zoomLadder[idx] - _zoom).abs()) {
          idx = i;
        }
      }
    }
    final next = (idx + dir).clamp(0, _zoomLadder.length - 1);
    final v = _zoomLadder[next];
    setState(() => _zoom = v);
    await widget.controller.setZoomFactor(v);
  }

  Future<void> _shortcutZoomReset() async {
    setState(() => _zoom = 1);
    await widget.controller.setZoomFactor(1);
  }

  // ── 持久化 tab 顺序 + 每个 target 的最后 URL ─────────────────────────
  // 顺序与 URL 都写到当前会话的 metadata，下次开 dashboard / 重启浏览器
  // 时由 controller 复用。fire-and-forget，不阻塞 UI。
  Timer? _metaPersistDebouncer;

  void _persistTabsAndUrls() {
    _metaPersistDebouncer?.cancel();
    _metaPersistDebouncer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final state =
          context.findAncestorStateOfType<_WebReverseDashboardDialogState>();
      if (state == null) return;
      state.persistBrowserPanelState();
    });
  }

  // ── 页面查找 ──────────────────────────────────────────────────────────

  void _closeFindBar() {
    _findDebouncer?.cancel();
    setState(() {
      _findBarOpen = false;
      _findMatchCount = 0;
    });
    _findCtrl.clear();
    unawaited(widget.controller.clearFindHighlights());
    _surfaceFocus.requestFocus();
  }

  void _onFindChanged(String s) {
    _findDebouncer?.cancel();
    _findDebouncer = Timer(const Duration(milliseconds: 200), () async {
      final n = await widget.controller.findInPage(s);
      if (!mounted) return;
      setState(() => _findMatchCount = n);
    });
  }

  Future<void> _findNext() async {
    await widget.controller.findCycleNext();
  }

  Future<void> _findPrev() async {
    await widget.controller.findCycleNext(forward: false);
  }

  String _logicalKeyName(LogicalKeyboardKey key) {
    final k = key.keyLabel;
    if (k.isNotEmpty) return k;
    return key.debugName ?? '';
  }

  // ── IME 桥实现 ────────────────────────────────────────────────────────

  void _onSurfaceFocusChanged() {
    if (!mounted) return;
    if (_surfaceFocus.hasFocus) {
      _attachImeConnection();
    } else {
      _detachImeConnection();
    }
  }

  void _attachImeConnection() {
    if (_imeConnection != null && _imeConnection!.attached) return;
    final c = TextInput.attach(
      this,
      const TextInputConfiguration(
        inputAction: TextInputAction.unspecified,
        autocorrect: false,
        enableSuggestions: false,
      ),
    );
    _imeConnection = c;
    _lastImeValue = TextEditingValue.empty;
    c.setEditingState(_lastImeValue);
    c.show();
  }

  void _detachImeConnection() {
    final c = _imeConnection;
    _imeConnection = null;
    if (c != null && c.attached) c.close();
  }

  @override
  void updateEditingValue(TextEditingValue value) {
    // 仅在 IME 完成 composition（composing 区间为空）时才把"已落字"作为
    // 一次 insertText 发到 CDP。中文 / 日文输入法在打字过程中会反复更新
    // composing 区间，这里跳过避免出现"半成品候选词被发送"。
    if (!value.composing.isCollapsed) {
      _lastImeValue = value;
      return;
    }
    final old = _lastImeValue.text;
    final cur = value.text;
    if (cur.length > old.length) {
      // 追加文本：取增量发送。多数 IME 一次提交 1-N 个字符。
      final delta = cur.substring(old.length);
      if (delta.isNotEmpty) widget.controller.insertText(delta);
    } else if (cur.length < old.length) {
      // 收缩：把删除量按 Backspace 序列发出，让浏览器侧 input/contenteditable
      // 真正退格。
      final n = old.length - cur.length;
      for (var i = 0; i < n; i++) {
        widget.controller.dispatchKeyEvent(
          type: 'rawKeyDown',
          key: 'Backspace',
          code: 'Backspace',
        );
        widget.controller.dispatchKeyEvent(
          type: 'keyUp',
          key: 'Backspace',
          code: 'Backspace',
        );
      }
    }
    // 重置 IME 端的"虚拟编辑器"为空，避免文本无限增长。
    _lastImeValue = TextEditingValue.empty;
    _imeConnection?.setEditingState(_lastImeValue);
  }

  @override
  void performAction(TextInputAction action) {
    if (action == TextInputAction.done ||
        action == TextInputAction.go ||
        action == TextInputAction.send ||
        action == TextInputAction.next) {
      widget.controller
        ..dispatchKeyEvent(
          type: 'rawKeyDown',
          key: 'Enter',
          code: 'Enter',
          text: '\r',
        )
        ..dispatchKeyEvent(
          type: 'keyUp',
          key: 'Enter',
          code: 'Enter',
        );
    }
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void connectionClosed() {
    _imeConnection = null;
  }

  @override
  void didChangeInputControl(
    TextInputControl? oldControl,
    TextInputControl? newControl,
  ) {}

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  TextEditingValue? get currentTextEditingValue => _lastImeValue;

  @override
  void insertTextPlaceholder(Size size) {}

  @override
  void removeTextPlaceholder() {}

  @override
  void showToolbar() {}

  @override
  void performSelector(String selectorName) {}

  @override
  void insertContent(KeyboardInsertedContent content) {}

  Future<void> _onAddressSubmit(String raw) async {
    var url = raw.trim();
    if (url.isEmpty) return;
    if (!url.contains('://')) url = 'https://$url';
    await widget.controller.navigate(url);
    _surfaceFocus.requestFocus();
  }

  /// 当前帧 PNG 落盘：优先用 CDP `Page.captureScreenshot` 拿一张实时全分辨
  /// 率截图（screencast 自身是 JPEG 低质，不适合做证据图）；失败则降级
  /// 用最近一帧 JPEG 字节直接落盘。
  Future<void> _saveCurrentFrame() async {
    final ctrl = widget.controller;
    final isZh = widget.isZh;
    final messenger = ScaffoldMessenger.of(context);
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    Uint8List? bytes;
    String ext = 'png';
    bytes = await ctrl.captureScreenshot();
    if (bytes == null) {
      bytes = ctrl.latestScreencastFrame;
      ext = 'jpg';
    }
    if (!mounted) return;
    if (bytes == null) {
      OpenHandSnackBar.showErrorOn(
        context,
        messenger,
        isZh ? '当前没有可用的画面帧' : 'No frame available',
        duration: const Duration(seconds: 2),
      );
      return;
    }
    final typeGroup = XTypeGroup(
      label: ext.toUpperCase(),
      extensions: <String>[ext],
    );
    FileSaveLocation? location;
    try {
      location = await getSaveLocation(
        suggestedName: 'browser-frame-$ts.$ext',
        acceptedTypeGroups: <XTypeGroup>[typeGroup],
      );
    } catch (_) {}
    if (!mounted || location == null) return;
    try {
      await File(location.path).writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      OpenHandSnackBar.showSuccessOn(
        context,
        messenger,
        isZh ? '已保存到 ${location.path}' : 'Saved to ${location.path}',
      );
    } catch (error, stack) {
      silentLog(
        'web_reverse_dashboard_dialog',
        'save current frame',
        error,
        stack,
      );
      if (!mounted) return;
      OpenHandSnackBar.showErrorOn(
        context,
        messenger,
        isZh ? '保存失败' : 'Save failed',
        duration: const Duration(seconds: 2),
      );
    }
  }

  /// 框选导出局部帧：full-resolution 截图后用 image 包做裁切，按用户在
  /// surface 上选的矩形百分比映射到浏览器侧 viewport 像素。
  Future<void> _finalizeCrop(Offset start, Offset end, Size renderSize) async {
    final isZh = widget.isZh;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _cropMode = false;
      _cropStart = null;
      _cropCurrent = null;
    });
    final rect = Rect.fromPoints(start, end);
    if (rect.width < 4 || rect.height < 4) return;
    final fx = rect.left / renderSize.width;
    final fy = rect.top / renderSize.height;
    final fw = rect.width / renderSize.width;
    final fh = rect.height / renderSize.height;
    Uint8List? png;
    try {
      png = await widget.controller
          .captureScreenshot()
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
    if (!mounted) return;
    if (png == null) {
      OpenHandSnackBar.showErrorOn(
        context,
        messenger,
        isZh ? '截图失败' : 'Screenshot failed',
        duration: const Duration(seconds: 2),
      );
      return;
    }
    final decoded = img.decodePng(png) ?? img.decodeImage(png);
    if (decoded == null) {
      OpenHandSnackBar.showErrorOn(
        context,
        messenger,
        isZh ? '解码失败' : 'Decode failed',
        duration: const Duration(seconds: 2),
      );
      return;
    }
    final cw = (decoded.width * fw).round().clamp(1, decoded.width);
    final ch = (decoded.height * fh).round().clamp(1, decoded.height);
    final cx = (decoded.width * fx).round().clamp(0, decoded.width - 1);
    final cy = (decoded.height * fy).round().clamp(0, decoded.height - 1);
    final cropped = img.copyCrop(
      decoded,
      x: cx,
      y: cy,
      width: cw.clamp(1, decoded.width - cx),
      height: ch.clamp(1, decoded.height - cy),
    );
    final out = Uint8List.fromList(img.encodePng(cropped));
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    const typeGroup = XTypeGroup(
      label: 'PNG',
      extensions: <String>['png'],
    );
    FileSaveLocation? location;
    try {
      location = await getSaveLocation(
        suggestedName: 'browser-crop-$ts.png',
        acceptedTypeGroups: <XTypeGroup>[typeGroup],
      );
    } catch (_) {}
    if (!mounted || location == null) return;
    try {
      await File(location.path).writeAsBytes(out, flush: true);
      if (!mounted) return;
      OpenHandSnackBar.showSuccessOn(
        context,
        messenger,
        isZh ? '已保存到 ${location.path}' : 'Saved to ${location.path}',
      );
    } catch (error, stack) {
      silentLog(
        'web_reverse_dashboard_dialog',
        'save crop',
        error,
        stack,
      );
      if (!mounted) return;
      OpenHandSnackBar.showErrorOn(
        context,
        messenger,
        isZh ? '保存失败' : 'Save failed',
        duration: const Duration(seconds: 2),
      );
    }
  }

  /// Flutter 端渲染的上下文菜单：复制 / 粘贴 / 全选 / 刷新 / 在外部浏览器
  /// 打开 / 检查元素 / 保存当前帧 / 框选导出。复制 / 粘贴 / 全选通过 CDP
  /// `Input.dispatchKeyEvent` 模拟 Cmd / Ctrl + C/V/A，让浏览器原生剪贴板
  /// 路径自然处理。
  Future<void> _showContextMenu(
    Offset globalPos,
    Size renderSize,
    Offset localPos,
  ) async {
    final isZh = widget.isZh;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromLTRB(
      globalPos.dx,
      globalPos.dy,
      overlay.size.width - globalPos.dx,
      overlay.size.height - globalPos.dy,
    );
    final selected = await showMenu<String>(
      context: context,
      position: position,
      items: [
        PopupMenuItem(
          value: 'copy',
          child: Text(isZh ? '复制' : 'Copy'),
        ),
        PopupMenuItem(
          value: 'paste',
          child: Text(isZh ? '粘贴' : 'Paste'),
        ),
        PopupMenuItem(
          value: 'selectAll',
          child: Text(isZh ? '全选' : 'Select all'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'reload',
          child: Text(isZh ? '刷新' : 'Reload'),
        ),
        PopupMenuItem(
          value: 'inspect',
          child: Text(isZh ? '检查元素 (DevTools)' : 'Inspect (DevTools)'),
        ),
        PopupMenuItem(
          value: 'openExternal',
          child: Text(isZh ? '在外部浏览器中打开' : 'Open in external browser'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'saveFrame',
          child: Text(isZh ? '保存当前帧 (PNG)' : 'Save current frame'),
        ),
        PopupMenuItem(
          value: 'cropFrame',
          child: Text(isZh ? '框选导出局部帧' : 'Save selected region'),
        ),
      ],
    );
    if (!mounted || selected == null) return;
    final ctrl = widget.controller;
    final isMac = Platform.isMacOS;
    Future<void> sendShortcut(String key) async {
      final mod = isMac ? 4 : 2; // Cmd on macOS, Ctrl elsewhere
      await ctrl.dispatchKeyEvent(
        type: 'rawKeyDown',
        key: key.toUpperCase(),
        code: 'Key${key.toUpperCase()}',
        modifiers: mod,
      );
      await ctrl.dispatchKeyEvent(
        type: 'keyUp',
        key: key.toUpperCase(),
        code: 'Key${key.toUpperCase()}',
        modifiers: mod,
      );
    }

    switch (selected) {
      case 'copy':
        await sendShortcut('c');
      case 'paste':
        await sendShortcut('v');
      case 'selectAll':
        await sendShortcut('a');
      case 'reload':
        await ctrl.reload();
      case 'inspect':
        if (mounted) {
          await _openOfficialDevToolsForController(context, ctrl, isZh);
        }
      case 'openExternal':
        final url = await ctrl.currentUrl();
        if (url == null || url.isEmpty) return;
        try {
          if (Platform.isMacOS) {
            await Process.run('/usr/bin/open', [url]);
          } else if (Platform.isWindows) {
            await Process.run('cmd', ['/c', 'start', '', url]);
          } else if (Platform.isLinux) {
            await Process.run('xdg-open', [url]);
          }
        } catch (_) {}
      case 'saveFrame':
        await _saveCurrentFrame();
      case 'cropFrame':
        setState(() {
          _cropMode = true;
          _cropStart = null;
          _cropCurrent = null;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isZh = widget.isZh;
    final ctrl = widget.controller;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return Column(
      children: [
        _TabStrip(
          targets: ctrl.pageTargets,
          currentId: ctrl.currentPageTargetId,
          enabled: ctrl.isBrowserAlive,
          isZh: isZh,
          onSwitch: (id) async {
            await ctrl.switchToPageTarget(id);
          },
          onClose: (id) async {
            await ctrl.closePageTarget(id);
          },
          onNew: () async {
            final id = await ctrl.createPageTarget();
            if (id != null) await ctrl.switchToPageTarget(id);
          },
          onReorder: (oldI, newI) {
            ctrl.reorderPageTarget(oldI, newI);
            _persistTabsAndUrls();
          },
        ),
        _buildAddressBar(theme, cs, isZh, ctrl),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final renderSize =
                  Size(constraints.maxWidth, constraints.maxHeight);
              _scheduleViewportSync(renderSize, dpr);
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: _ScreencastImage(
                            controller: ctrl,
                            placeholderBuilder: () =>
                                _buildPlaceholder(theme, cs, isZh, ctrl),
                          ),
                        ),
                        Positioned.fill(
                          child: Focus(
                            focusNode: _surfaceFocus,
                            onKeyEvent: _handleKey,
                            child: Listener(
                              behavior: HitTestBehavior.opaque,
                              onPointerDown: (e) =>
                                  _handlePointerDown(e, renderSize),
                              onPointerMove: (e) =>
                                  _handlePointerMove(e, renderSize),
                              onPointerHover: (e) =>
                                  _handlePointerHover(e, renderSize),
                              onPointerUp: (e) =>
                                  _handlePointerUp(e, renderSize),
                              onPointerSignal: (e) =>
                                  _handlePointerSignal(e, renderSize),
                              child: const MouseRegion(
                                cursor: SystemMouseCursors.basic,
                                child: SizedBox.expand(),
                              ),
                            ),
                          ),
                        ),
                        if (_findBarOpen)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: _FindBar(
                              focusNode: _findFocus,
                              controller: _findCtrl,
                              matchCount: _findMatchCount,
                              isZh: isZh,
                              onChanged: _onFindChanged,
                              onPrev: _findPrev,
                              onNext: _findNext,
                              onClose: _closeFindBar,
                            ),
                          ),
                        if (_cropMode)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: _CropOverlayPainter(
                                  start: _cropStart,
                                  current: _cropCurrent,
                                  color: cs.primary,
                                ),
                              ),
                            ),
                          ),
                        if (_cropMode)
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Material(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(_kToolbarRadius),
                              elevation: 4,
                              shadowColor: Colors.black26,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                child: Text(
                                  isZh
                                      ? '拖动选择导出区域，松手保存'
                                      : 'Drag to select region',
                                  style: theme.textTheme.labelSmall,
                                ),
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
      ],
    );
  }

  Widget _buildAddressBar(
    ThemeData theme,
    ColorScheme cs,
    bool isZh,
    WebReverseSessionController ctrl,
  ) {
    final alive = ctrl.isBrowserAlive;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          _NavIconButton(
            tooltip: isZh ? '后退' : 'Back',
            icon: Icons.arrow_back_rounded,
            onPressed: alive ? () => ctrl.goBack() : null,
          ),
          const SizedBox(width: 6),
          _NavIconButton(
            tooltip: isZh ? '前进' : 'Forward',
            icon: Icons.arrow_forward_rounded,
            onPressed: alive ? () => ctrl.goForward() : null,
          ),
          const SizedBox(width: 6),
          _NavIconButton(
            tooltip: isZh ? '刷新' : 'Reload',
            icon: Icons.refresh_rounded,
            onPressed: alive ? () => ctrl.reload() : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: _addressCtrl,
                focusNode: _addressBarFocus,
                enabled: alive,
                textAlignVertical: TextAlignVertical.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
                onTap: () => _addressEditing = true,
                onSubmitted: (s) async {
                  _addressEditing = false;
                  await _onAddressSubmit(s);
                },
                onTapOutside: (_) {
                  _addressEditing = false;
                  FocusScope.of(context).unfocus();
                },
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.85),
                  hintText: isZh ? '输入 URL 后回车' : 'Type URL and press Enter',
                  prefixIcon: Icon(
                    Icons.link_rounded,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(_kToolbarRadius),
                    borderSide: BorderSide(color: cs.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(_kToolbarRadius),
                    borderSide: BorderSide(color: cs.outlineVariant),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(_kToolbarRadius),
                    borderSide: BorderSide(color: cs.primary, width: 1.4),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _NavIconButton(
            tooltip: isZh ? '聚焦面板' : 'Focus surface',
            icon: Icons.center_focus_strong_rounded,
            onPressed: alive ? _surfaceFocus.requestFocus : null,
          ),
          const SizedBox(width: 6),
          _ZoomMenu(
            value: _zoom,
            enabled: alive,
            isZh: isZh,
            onChanged: (v) async {
              setState(() => _zoom = v);
              await ctrl.setZoomFactor(v);
            },
          ),
          const SizedBox(width: 6),
          _NavIconButton(
            tooltip: isZh ? '保存当前帧' : 'Save current frame',
            icon: Icons.photo_camera_outlined,
            onPressed: alive ? _saveCurrentFrame : null,
          ),
          const SizedBox(width: 6),
          _NavIconButton(
            tooltip: alive
                ? (isZh ? '重启浏览器' : 'Restart browser')
                : (isZh ? '启动浏览器' : 'Start browser'),
            icon: Icons.restart_alt_rounded,
            onPressed: () async {
              try {
                await ctrl.restartBrowser();
              } catch (_) {}
            },
          ),
          const SizedBox(width: 6),
          _NavIconButton(
            tooltip: isZh ? '停止调试' : 'Stop browser',
            icon: Icons.power_settings_new_rounded,
            onPressed: alive
                ? () async {
                    await ctrl.stopBrowser();
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder(
    ThemeData theme,
    ColorScheme cs,
    bool isZh,
    WebReverseSessionController ctrl,
  ) {
    final running = ctrl.isRunning;
    final alive = ctrl.isBrowserAlive;
    if (!alive) {
      // 浏览器进程已死（用户手动关 / 异常退出 / CDP 重连失败）：给一颗
      // 重启按钮，让用户自救拉起，不要让画面静默卡死。
      final err = (ctrl.errorMessage ?? '').trim();
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.power_off_rounded,
                size: 36,
                color: cs.error,
              ),
              const SizedBox(height: 12),
              Text(
                isZh ? '浏览器已断开' : 'Browser disconnected',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                err.isEmpty
                    ? (isZh
                        ? '会话仍在，但 CDP 已断。点击下方按钮重新拉起浏览器即可继续逆向。'
                        : 'Session retained but CDP is down. Click below to relaunch the browser.')
                    : err,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant, height: 1.5),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  try {
                    await ctrl.restartBrowser();
                  } catch (_) {}
                },
                icon: const Icon(Icons.restart_alt_rounded, size: 16),
                label: Text(isZh ? '重启浏览器' : 'Restart browser'),
              ),
            ],
          ),
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation(cs.primary),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            running
                ? (isZh ? '等待浏览器画面…' : 'Waiting for browser frame…')
                : (isZh
                    ? '会话尚未运行，无法启动 screencast'
                    : 'Session not running'),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _NavIconButton extends StatelessWidget {
  const _NavIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        height: _kToolbarHeight,
        width: _kToolbarHeight,
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_kToolbarRadius),
            side: BorderSide(
              color: enabled
                  ? cs.outlineVariant
                  : cs.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(_kToolbarRadius),
            child: Center(
              child: Icon(
                icon,
                size: 18,
                color: enabled
                    ? cs.onSurface
                    : cs.onSurface.withValues(alpha: 0.35),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 仅追踪 controller 的 [WebReverseSessionController.screencastFrameNotifier]
/// 变化，把 [Image.memory] 与 RepaintBoundary 隔离在最小子树内 —— 60fps 帧
/// 流不会触发外层 Padding / Stack / Column 重建，也不会触发 dashboard 头部 /
/// network list 的 listener。
class _ScreencastImage extends StatelessWidget {
  const _ScreencastImage({
    required this.controller,
    required this.placeholderBuilder,
  });

  final WebReverseSessionController controller;
  final Widget Function() placeholderBuilder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: controller.screencastFrameNotifier,
      builder: (_, seq, _) {
        final frame = controller.latestScreencastFrame;
        if (frame == null) return placeholderBuilder();
        return RepaintBoundary(
          child: Image.memory(
            frame,
            key: ValueKey<int>(seq),
            fit: BoxFit.fill,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
          ),
        );
      },
    );
  }
}


/// 缩放比例下拉胶囊：支持 50% / 75% / 100% / 125% / 150%。选中后立刻把
/// 比例下发到浏览器侧 `Emulation.setPageScaleFactor`，让 page reflow 即时
/// 反馈到 screencast 帧。
class _ZoomMenu extends StatelessWidget {
  const _ZoomMenu({
    required this.value,
    required this.enabled,
    required this.isZh,
    required this.onChanged,
  });

  final double value;
  final bool enabled;
  final bool isZh;
  final ValueChanged<double> onChanged;

  static const _presets = <double>[0.5, 0.75, 1.0, 1.25, 1.5];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Tooltip(
      message: isZh ? '页面缩放' : 'Page zoom',
      child: SizedBox(
        height: _kToolbarHeight,
        child: PopupMenuButton<double>(
          enabled: enabled,
          tooltip: '',
          onSelected: onChanged,
          itemBuilder: (_) => _presets
              .map((p) => PopupMenuItem<double>(
                    value: p,
                    child: Text('${(p * 100).round()}%'),
                  ))
              .toList(growable: false),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_kToolbarRadius),
              border: Border.all(
                color: enabled
                    ? cs.outlineVariant
                    : cs.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.zoom_in_rounded,
                  size: 14,
                  color: enabled
                      ? cs.onSurfaceVariant
                      : cs.onSurface.withValues(alpha: 0.35),
                ),
                const SizedBox(width: 4),
                Text(
                  '${(value * 100).round()}%',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: enabled
                        ? cs.onSurface
                        : cs.onSurface.withValues(alpha: 0.35),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


/// 浏览器面板顶部 tab strip：每个 page target 一个胶囊，激活态高亮。
/// 「+」按钮新建 about:blank tab；激活胶囊上挂×按钮关闭。长按拖动重排。
class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.targets,
    required this.currentId,
    required this.enabled,
    required this.isZh,
    required this.onSwitch,
    required this.onClose,
    required this.onNew,
    required this.onReorder,
  });

  final List<CdpPageTargetSnapshot> targets;
  final String? currentId;
  final bool enabled;
  final bool isZh;
  final ValueChanged<String> onSwitch;
  final ValueChanged<String> onClose;
  final VoidCallback onNew;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (targets.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: SizedBox(
        height: 32,
        child: Row(
          children: [
            Expanded(
              child: ReorderableListView.builder(
                scrollDirection: Axis.horizontal,
                buildDefaultDragHandles: false,
                onReorder: enabled ? onReorder : (_, _) {},
                proxyDecorator: (child, _, anim) {
                  return Material(
                    elevation: 4 * anim.value,
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    child: child,
                  );
                },
                itemCount: targets.length,
                itemBuilder: (_, i) {
                  final t = targets[i];
                  final active = t.id == currentId;
                  final label = t.title.isNotEmpty
                      ? t.title
                      : (t.url.isEmpty
                          ? (isZh ? '新标签页' : 'New tab')
                          : Uri.tryParse(t.url)?.host ?? t.url);
                  return Padding(
                    key: ValueKey<String>(t.id),
                    padding: EdgeInsets.only(
                      right: i == targets.length - 1 ? 0 : 6,
                    ),
                    child: ReorderableDelayedDragStartListener(
                      index: i,
                      child: Material(
                        color: active
                            ? cs.primaryContainer
                            : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(999),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: enabled ? () => onSwitch(t.id) : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.public_rounded,
                                  size: 12,
                                  color: active
                                      ? cs.onPrimaryContainer
                                      : cs.onSurfaceVariant,
                                ),
                                const SizedBox(width: 6),
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 140),
                                  child: Text(
                                    label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        theme.textTheme.labelSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: active
                                          ? cs.onPrimaryContainer
                                          : cs.onSurface,
                                    ),
                                  ),
                                ),
                                if (targets.length > 1) ...[
                                  const SizedBox(width: 6),
                                  InkResponse(
                                    radius: 12,
                                    onTap:
                                        enabled ? () => onClose(t.id) : null,
                                    child: Icon(
                                      Icons.close_rounded,
                                      size: 12,
                                      color: active
                                          ? cs.onPrimaryContainer
                                          : cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: isZh ? '新建标签页' : 'New tab',
              child: SizedBox(
                width: 26,
                height: 26,
                child: Material(
                  color: cs.surfaceContainerHighest,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: enabled ? onNew : null,
                    child: Icon(
                      Icons.add_rounded,
                      size: 16,
                      color: enabled
                          ? cs.onSurfaceVariant
                          : cs.onSurface.withValues(alpha: 0.35),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// 浏览器面板顶部右上角浮起的找词条：复刻 Chrome 的 Cmd+F 行为，
/// 支持回车下一项、Shift+Enter 上一项、Esc 关闭、关闭后清掉所有 mark 高亮。
class _FindBar extends StatelessWidget {
  const _FindBar({
    required this.focusNode,
    required this.controller,
    required this.matchCount,
    required this.isZh,
    required this.onChanged,
    required this.onPrev,
    required this.onNext,
    required this.onClose,
  });

  final FocusNode focusNode;
  final TextEditingController controller;
  final int matchCount;
  final bool isZh;
  final ValueChanged<String> onChanged;
  final Future<void> Function() onPrev;
  final Future<void> Function() onNext;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(_kToolbarRadius),
      elevation: 4,
      shadowColor: Colors.black26,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_kToolbarRadius),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_rounded, size: 14, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            SizedBox(
              width: 200,
              child: TextField(
                focusNode: focusNode,
                controller: controller,
                style: theme.textTheme.bodySmall,
                onChanged: onChanged,
                onSubmitted: (_) => onNext(),
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: isZh ? '查找词条' : 'Find',
                  hintStyle: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.65),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                ),
              ),
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 36),
              child: Text(
                matchCount > 0 ? '$matchCount' : '0',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            IconButton(
              tooltip: isZh ? '上一个' : 'Previous',
              visualDensity: VisualDensity.compact,
              onPressed: matchCount > 0 ? () async => onPrev() : null,
              icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 18),
            ),
            IconButton(
              tooltip: isZh ? '下一个' : 'Next',
              visualDensity: VisualDensity.compact,
              onPressed: matchCount > 0 ? () async => onNext() : null,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
            ),
            IconButton(
              tooltip: isZh ? '关闭' : 'Close',
              visualDensity: VisualDensity.compact,
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded, size: 16),
            ),
          ],
        ),
      ),
    );
  }
}


/// 框选导出时的虚线矩形 + 半透明遮罩。
class _CropOverlayPainter extends CustomPainter {
  _CropOverlayPainter({
    required this.start,
    required this.current,
    required this.color,
  });

  final Offset? start;
  final Offset? current;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.25);
    canvas.drawRect(Offset.zero & size, dim);
    final s = start;
    final c = current;
    if (s == null || c == null) return;
    final rect = Rect.fromPoints(s, c);
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(Offset.zero & size, dim);
    canvas.drawRect(
      rect,
      Paint()..blendMode = BlendMode.clear,
    );
    canvas.restore();
    final border = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawRect(rect, border);
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter old) {
    return old.start != start || old.current != current || old.color != color;
  }
}
