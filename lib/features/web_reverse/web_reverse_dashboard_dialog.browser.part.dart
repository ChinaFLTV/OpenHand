part of 'web_reverse_dashboard_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────
// 内嵌浏览器面板：CDP screencast 帧渲染 + 输入桥（鼠标 / 滚轮 / 键盘 / IME）
//
// 设计要点：
//   1. 资源控制 —— 进入面板时调一次 `acquireScreencast`，离开 / dispose 时
//      `releaseScreencast`；controller 内部用引用计数避免重复 start/stop。
//      切到其它 tab 立即 release，浏览器立刻停推帧；切回再 acquire。这避免
//      "用户切走后帧仍在后台跑、堆积内存"。
//   2. 帧渲染 —— 只保留最近一帧 `Uint8List`，每帧到达时帧序号自增，widget
//      用 [Image.memory] + ValueKey 触发 RepaintBoundary 内重绘，列表 / 工具
//      栏完全不会被脏区拖累。
//   3. 输入桥 —— Listener 捕获 PointerDown/Move/Up/Wheel；KeyboardListener
//      捕获 LogicalKey；TextField (IME 通道) 用零宽透明输入框接 insertText。
//      所有事件都会先把本地坐标除以 devicePixelRatio 再折算到浏览器
//      viewport（CSS 像素），保证 retina 一致。
//   4. 视口同步 —— widget 矩形在用户拖大 / 拖小窗口时变化，触发去抖 200ms 后
//      调 `reconfigureScreencast`，让浏览器侧 maxWidth/maxHeight 跟手；同时
//      同步 setDeviceMetricsOverride，让 page 的 layout 也按面板尺寸渲染。
// ─────────────────────────────────────────────────────────────────────────

class _BrowserBody extends StatefulWidget {
  const _BrowserBody({
    required this.controller,
    required this.isZh,
    required this.reduceMotion,
  });

  final WebReverseSessionController controller;
  final bool isZh;
  final bool reduceMotion;

  @override
  State<_BrowserBody> createState() => _BrowserBodyState();
}

class _BrowserBodyState extends State<_BrowserBody> {
  final TextEditingController _addressCtrl = TextEditingController();
  final FocusNode _surfaceFocus = FocusNode(debugLabel: 'browser-surface');
  final FocusNode _imeFocus = FocusNode(debugLabel: 'browser-ime');
  final TextEditingController _imeCtrl = TextEditingController();
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

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
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
      if (_addressCtrl.text != url) _addressCtrl.text = url;
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _resizeDebouncer?.cancel();
    _urlPoller?.cancel();
    widget.controller.releaseScreencast();
    _addressCtrl.dispose();
    _surfaceFocus.dispose();
    _imeFocus.dispose();
    _imeCtrl.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    _frameW = widget.controller.screencastWidth;
    _frameH = widget.controller.screencastHeight;
    setState(() {});
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
      widget.controller.reconfigureScreencast(maxWidth: w, maxHeight: h);
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
    final p = _toViewport(e.localPosition, renderSize);
    widget.controller.dispatchMouseEvent(
      type: 'mouseMoved',
      x: p.dx,
      y: p.dy,
      modifiers: _modifiersFromKeys(),
    );
  }

  void _handlePointerUp(PointerUpEvent e, Size renderSize) {
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

  String _logicalKeyName(LogicalKeyboardKey key) {
    final k = key.keyLabel;
    if (k.isNotEmpty) return k;
    return key.debugName ?? '';
  }

  Future<void> _onAddressSubmit(String raw) async {
    var url = raw.trim();
    if (url.isEmpty) return;
    if (!url.contains('://')) url = 'https://$url';
    await widget.controller.navigate(url);
    _surfaceFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isZh = widget.isZh;
    final ctrl = widget.controller;
    final frame = ctrl.latestScreencastFrame;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return Column(
      children: [
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
                          child: frame == null
                              ? _buildPlaceholder(theme, cs, isZh, ctrl)
                              : RepaintBoundary(
                                  child: Image.memory(
                                    frame,
                                    key: ValueKey<int>(ctrl.screencastFrameSeq),
                                    fit: BoxFit.fill,
                                    gaplessPlayback: true,
                                    filterQuality: FilterQuality.low,
                                  ),
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
                        // 零宽透明 IME 输入桥：仅当用户聚焦面板时挂着，专门
                        // 接 macOS / Windows / Linux IME 提交（如中文 / 日文输入法）。
                        Positioned(
                          left: 0,
                          top: 0,
                          width: 1,
                          height: 1,
                          child: Opacity(
                            opacity: 0,
                            child: TextField(
                              focusNode: _imeFocus,
                              controller: _imeCtrl,
                              onChanged: (s) {
                                if (s.isNotEmpty) {
                                  widget.controller.insertText(s);
                                  _imeCtrl.clear();
                                }
                              },
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          _NavIconButton(
            tooltip: isZh ? '后退' : 'Back',
            icon: Icons.arrow_back_rounded,
            onPressed: ctrl.goBack,
          ),
          const SizedBox(width: 6),
          _NavIconButton(
            tooltip: isZh ? '前进' : 'Forward',
            icon: Icons.arrow_forward_rounded,
            onPressed: ctrl.goForward,
          ),
          const SizedBox(width: 6),
          _NavIconButton(
            tooltip: isZh ? '刷新' : 'Reload',
            icon: Icons.refresh_rounded,
            onPressed: () => ctrl.reload(),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: _addressCtrl,
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
            onPressed: _surfaceFocus.requestFocus,
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
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        height: _kToolbarHeight,
        width: _kToolbarHeight,
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_kToolbarRadius),
            side: BorderSide(color: cs.outlineVariant),
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(_kToolbarRadius),
            child: Center(
              child: Icon(icon, size: 18, color: theme.colorScheme.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}
