part of 'web_reverse_dashboard_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────
// 内嵌浏览器面板：CDP screencast 帧渲染 + 输入桥（鼠标 / 滚轮 / 键盘）
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

// LogicalKeyboardKey → (CDP key, CDP code, windowsVirtualKeyCode) 静态表。
// 仅覆盖 character 为空的"功能键 / 控制键"；可打印字符直接走 character。
// 值来自 W3C UI Events code list 与 Windows VK 常量。
final Map<LogicalKeyboardKey, (String, String?, int?)> _kCdpSpecialKey = {
  LogicalKeyboardKey.backspace: ('Backspace', 'Backspace', 8),
  LogicalKeyboardKey.tab: ('Tab', 'Tab', 9),
  LogicalKeyboardKey.enter: ('Enter', 'Enter', 13),
  LogicalKeyboardKey.numpadEnter: ('Enter', 'NumpadEnter', 13),
  LogicalKeyboardKey.escape: ('Escape', 'Escape', 27),
  LogicalKeyboardKey.space: (' ', 'Space', 32),
  LogicalKeyboardKey.pageUp: ('PageUp', 'PageUp', 33),
  LogicalKeyboardKey.pageDown: ('PageDown', 'PageDown', 34),
  LogicalKeyboardKey.end: ('End', 'End', 35),
  LogicalKeyboardKey.home: ('Home', 'Home', 36),
  LogicalKeyboardKey.arrowLeft: ('ArrowLeft', 'ArrowLeft', 37),
  LogicalKeyboardKey.arrowUp: ('ArrowUp', 'ArrowUp', 38),
  LogicalKeyboardKey.arrowRight: ('ArrowRight', 'ArrowRight', 39),
  LogicalKeyboardKey.arrowDown: ('ArrowDown', 'ArrowDown', 40),
  LogicalKeyboardKey.delete: ('Delete', 'Delete', 46),
  LogicalKeyboardKey.insert: ('Insert', 'Insert', 45),
  LogicalKeyboardKey.shiftLeft: ('Shift', 'ShiftLeft', 16),
  LogicalKeyboardKey.shiftRight: ('Shift', 'ShiftRight', 16),
  LogicalKeyboardKey.controlLeft: ('Control', 'ControlLeft', 17),
  LogicalKeyboardKey.controlRight: ('Control', 'ControlRight', 17),
  LogicalKeyboardKey.altLeft: ('Alt', 'AltLeft', 18),
  LogicalKeyboardKey.altRight: ('Alt', 'AltRight', 18),
  LogicalKeyboardKey.metaLeft: ('Meta', 'MetaLeft', 91),
  LogicalKeyboardKey.metaRight: ('Meta', 'MetaRight', 93),
  LogicalKeyboardKey.capsLock: ('CapsLock', 'CapsLock', 20),
  LogicalKeyboardKey.f1: ('F1', 'F1', 112),
  LogicalKeyboardKey.f2: ('F2', 'F2', 113),
  LogicalKeyboardKey.f3: ('F3', 'F3', 114),
  LogicalKeyboardKey.f4: ('F4', 'F4', 115),
  LogicalKeyboardKey.f5: ('F5', 'F5', 116),
  LogicalKeyboardKey.f6: ('F6', 'F6', 117),
  LogicalKeyboardKey.f7: ('F7', 'F7', 118),
  LogicalKeyboardKey.f8: ('F8', 'F8', 119),
  LogicalKeyboardKey.f9: ('F9', 'F9', 120),
  LogicalKeyboardKey.f10: ('F10', 'F10', 121),
  LogicalKeyboardKey.f11: ('F11', 'F11', 122),
  LogicalKeyboardKey.f12: ('F12', 'F12', 123),
};

class _BrowserBody extends StatefulWidget {
  const _BrowserBody({
    required this.controller,
    required this.onRestartBrowser,
  });

  final WebReverseSessionController controller;
  final Future<void> Function() onRestartBrowser;

  @override
  State<_BrowserBody> createState() => _BrowserBodyState();
}

class _BrowserBodyState extends State<_BrowserBody> implements TextInputClient {
  static const Duration _kPlaceholderRefreshInterval = Duration(seconds: 1);
  static const Duration _kFirstFrameSlowThreshold = Duration(seconds: 8);

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
  Timer? _placeholderTicker;
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
  bool _wasScreencastActive = false;
  bool _surfaceInputReady = false;
  bool _restartBrowserInFlight = false;
  // 浏览器侧 setPageScaleFactor 的当前值；面板内独立维护，下次切到 dashboard
  // 重新 attach 时不会保留（Chromium 重启即丢）。
  double _zoom = 1;
  // screencast 分辨率档位：null = 自动跟随面板尺寸；其它值表示固定上界。
  // 用户在地址栏「分辨率」下拉里选，按 (maxWidth, maxHeight) 元组。
  ({int w, int h})? _resolutionOverride;
  // 设备模拟预设：null = 桌面默认；其它对应 Mobile / Tablet / Desktop。
  WebReverseDevicePreset? _devicePreset;
  // 上次记录的 tab 列表标识：targets 数量 / currentId 任一变化即 rebuild。
  int _lastTargetsLen = 0;
  String? _lastCurrentTargetId;
  // 顺序 / 标题指纹：拖拽 reorder 或 Page 标题刷新时长度不变，需要单独感知。
  int _lastTargetsOrderHash = 0;
  int _lastTargetsTitleHash = 0;
  // 框选导出模式：进入后吞掉所有指针事件，完成时把当前 viewport 矩形按
  // 浏览器侧 CSS 像素裁切成 PNG。
  bool _cropMode = false;
  bool _cropScheduled = false;
  bool _zoomScheduled = false;
  Offset? _cropStart;
  Offset? _cropCurrent;
  // macOS trackpad 两指平移会派发 PointerPanZoom 事件而不是 PointerScroll，
  // 这里记录是否处于 pan-zoom 中，方便累计 delta。
  bool _panZoomActive = false;
  Offset _lastPanZoomPan = Offset.zero;
  // 两指捂合 → 页面缩放：记录上次派发缩放事件的“scale”快照。
  // 只有增量 > 4% 才应用一次，避免频繁设置 zoomFactor。
  double _lastPanZoomScale = 1;
  // 自然停止动效：手势结束后用指数衰减把残余速度继续派发，
  // 直到接近 0 或用户再次开始滑动手势。让滚动有 macOS / iOS 般的惯性。
  Timer? _scrollInertiaTimer;
  Offset _scrollInertiaVelocity = Offset.zero;
  DateTime _scrollInertiaAt = DateTime.now();
  Offset _scrollInertiaPos = Offset.zero;

  // ── IME 桥（TextInputClient 手动接管） ────────────────────────────────
  // surface 拿到焦点时打开一条 TextInput connection，把 IME 候选词、回车 /
  // 退格、跨端剪贴板粘贴等都拿到 [updateEditingValue]。我们仅在 composing
  // 区间收敛后把"新增文本"作为一次 insertText 发到 CDP，删除字符则发
  // Backspace 序列；这样既支持中文 / 日文 / 韩文输入，又不会和物理键盘
  // 走的 Focus.onKeyEvent 重复下发文本字符。
  TextInputConnection? _imeConnection;
  TextEditingValue _lastImeValue = TextEditingValue.empty;
  InputRepairParticipantToken? _inputRepairParticipantToken;
  // CJK 输入模式开关。默认关闭：所有按键经 HardwareKeyboard
  // → `_handleKey` → CDP 透传，Backspace / 方向键 / 标点都生效，但 macOS
  // 输入法激活时无法在内嵌页面打中文 / 日文 / 韩文。开启后挂 TextInput
  // connection 走 [updateEditingValue] diff，CJK 候选词上屏可用，但部分
  // 特殊键会被 IMK 拦截。用户可在地址栏按钮上手动 toggle。
  bool _cjkInputEnabled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _surfaceFocus.addListener(_onSurfaceFocusChanged);
    _inputRepairParticipantToken = InputRepairService.instance
        .registerParticipant(
          debugLabel: 'web_reverse_browser_surface',
          onRepair: (_) async {
            _detachImeConnection();
            _lastImeValue = TextEditingValue.empty;
            _surfaceFocus.unfocus();
            _addressBarFocus.unfocus();
            _findFocus.unfocus();
            _findBarOpen = false;
            _findCtrl.clear();
            _scrollInertiaTimer?.cancel();
            _scrollInertiaTimer = null;
            return const InputRepairParticipantResult.success();
          },
        );
    _wasAlive = widget.controller.isBrowserAlive;
    _wasScreencastActive = widget.controller.isScreencastActive;
    _surfaceInputReady =
        widget.controller.isBrowserAlive &&
        widget.controller.latestScreencastFrame != null;
    widget.controller.screencastFrameNotifier.addListener(
      _onScreencastFrameStateChanged,
    );
    _startPlaceholderTicker();
    // 首次进入时同步一次地址栏；CDP 已稳定时立即拉。空 URL 或 about:blank
    // 时让地址栏保持空白让 placeholder 顶上去，避免初次打开就看到一行
    // about:blank 占位文字。
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final url = await widget.controller.currentUrl();
      if (!mounted) return;
      final next = (url == null || url.isEmpty || url == 'about:blank')
          ? ''
          : url;
      if (_addressCtrl.text != next) _addressCtrl.text = next;
    });
    // 进入面板就 acquire；离开 dispose 时 release。
    widget.controller.acquireScreencast();
    // 用户正在编辑地址栏时不强行覆写；导航 / 跳转后定时拉一次同步真实 URL。
    _urlPoller = startNonOverlappingPeriodicTimer(
      const Duration(seconds: 2),
      (_) async {
        if (!mounted || _addressEditing) return;
        final url = await widget.controller.currentUrl();
        if (!mounted) return;
        final next = (url == null || url.isEmpty || url == 'about:blank')
            ? ''
            : url;
        final addrChanged = _addressCtrl.text != next;
        if (addrChanged) _addressCtrl.text = next;
        // 同时让 controller 的 page target 列表 url 字段保持同步——targetInfoChanged
        // 在某些场景下不会立刻到达，这里兜底把当前 target 的 url 字段也改了。
        final cur = widget.controller.currentPageTargetId;
        if (cur != null) {
          final realUrl = url ?? '';
          final updated = <CdpPageTargetSnapshot>[];
          var dirty = false;
          for (final t in widget.controller.pageTargets) {
            if (t.id == cur && t.url != realUrl) {
              updated.add(
                CdpPageTargetSnapshot(id: t.id, url: realUrl, title: t.title),
              );
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
      },
      callbackTimeout: const Duration(seconds: 5),
      onError: (error, stack) =>
          silentLog('web_reverse_dashboard_dialog', '轮询当前链接', error, stack),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    widget.controller.screencastFrameNotifier.removeListener(
      _onScreencastFrameStateChanged,
    );
    _surfaceFocus.removeListener(_onSurfaceFocusChanged);
    _inputRepairParticipantToken?.dispose();
    _inputRepairParticipantToken = null;
    _resizeDebouncer?.cancel();
    _urlPoller?.cancel();
    _placeholderTicker?.cancel();
    _findDebouncer?.cancel();
    _scrollInertiaTimer?.cancel();
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
    final screencastActive = widget.controller.isScreencastActive;
    final surfaceInputReady =
        alive && widget.controller.latestScreencastFrame != null;
    final len = widget.controller.pageTargets.length;
    final cur = widget.controller.currentPageTargetId;
    final orderHash = _pageTargetsOrderHash(widget.controller.pageTargets);
    final titleHash = _pageTargetsTitleHash(widget.controller.pageTargets);
    final targetStateDirty =
        len != _lastTargetsLen ||
        cur != _lastCurrentTargetId ||
        orderHash != _lastTargetsOrderHash ||
        titleHash != _lastTargetsTitleHash;
    final dirty =
        w != _frameW ||
        h != _frameH ||
        alive != _wasAlive ||
        screencastActive != _wasScreencastActive ||
        surfaceInputReady != _surfaceInputReady ||
        targetStateDirty;
    final aliveJustFlipped = alive && !_wasAlive;
    _frameW = w;
    _frameH = h;
    _wasAlive = alive;
    _wasScreencastActive = screencastActive;
    _surfaceInputReady = surfaceInputReady;
    _lastTargetsLen = len;
    _lastCurrentTargetId = cur;
    _lastTargetsOrderHash = orderHash;
    _lastTargetsTitleHash = titleHash;
    if (dirty) setState(() {});
    if (targetStateDirty) _persistTabsAndUrls();
    if (aliveJustFlipped) {
      // 浏览器刚拉起 / 重启完毕：① 重新 acquire screencast（之前 release/safeStop
      // 已把引用计数和 active 都清零，否则面板会一直停在"等待浏览器画面"
      // 的占位上不动）；② 用上一轮持久化的 tab URL 恢复多 tab 场景；
      // ③ 恢复持久化的 Sources 断点。
      unawaited(widget.controller.acquireScreencast());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final state = context
            .findAncestorStateOfType<_WebReverseDashboardDialogState>();
        state?.restoreBrowserTabs();
        state?.restoreBreakpoints();
      });
    }
  }

  void _onScreencastFrameStateChanged() {
    if (!mounted) return;
    final next =
        widget.controller.isBrowserAlive &&
        widget.controller.latestScreencastFrame != null;
    if (next == _surfaceInputReady) return;
    setState(() => _surfaceInputReady = next);
  }

  String _restartFailureMessage(Object error) {
    final raw = '$error'.trim();
    final clipped = clipText(raw, 220);
    return openHandLocalizedText(
      context,
      zh: '浏览器重启失败：$clipped',
      zhHant: '瀏覽器重啟失敗：$clipped',
      en: 'Browser restart failed: $clipped',
      fr: 'Échec du redémarrage du navigateur : $clipped',
      de: 'Browser-Neustart fehlgeschlagen: $clipped',
      ja: 'ブラウザの再起動に失敗しました: $clipped',
    );
  }

  Future<void> _restartBrowserFromUi(String source) async {
    if (_restartBrowserInFlight) return;
    final disconnectedAfterRestartMessage = openHandLocalizedText(
      context,
      zh: '重启完成后 CDP 仍未连接，请检查浏览器是否被系统或安全策略拦截。',
      zhHant: '重啟完成後 CDP 仍未連線，請檢查瀏覽器是否被系統或安全策略攔截。',
      en: 'CDP is still disconnected after restart. Check whether the browser was blocked by the system or security policy.',
      fr: 'CDP reste déconnecté après le redémarrage. Vérifiez si le navigateur a été bloqué.',
      de: 'CDP ist nach dem Neustart weiterhin getrennt. Prüfen Sie, ob der Browser blockiert wurde.',
      ja: '再起動後も CDP が未接続です。システムやセキュリティ設定によるブロックを確認してください。',
    );
    setState(() => _restartBrowserInFlight = true);
    try {
      await widget.onRestartBrowser();
      if (!widget.controller.isBrowserAlive) {
        throw StateError(disconnectedAfterRestartMessage);
      }
      if (!mounted) return;
      _lastConfiguredSize = null;
      showOpenHandSuccessSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '浏览器已重启',
          zhHant: '瀏覽器已重啟',
          en: 'Browser restarted',
          fr: 'Navigateur redémarré',
          de: 'Browser neu gestartet',
          ja: 'ブラウザを再起動しました',
        ),
      );
    } catch (error, stack) {
      silentLog(
        'web_reverse_dashboard_dialog',
        '从 $source 重启浏览器',
        error,
        stack,
      );
      if (!mounted) return;
      showOpenHandErrorSnack(
        context,
        _restartFailureMessage(error),
        duration: kOpenHandSnackBarLongReadDuration,
      );
    } finally {
      if (mounted) setState(() => _restartBrowserInFlight = false);
    }
  }

  void _startPlaceholderTicker() {
    _placeholderTicker?.cancel();
    _placeholderTicker = startNonOverlappingPeriodicTimer(
      _kPlaceholderRefreshInterval,
      (_) async {
        if (!mounted) return;
        final ctrl = widget.controller;
        if (!ctrl.isBrowserAlive || ctrl.latestScreencastFrame != null) {
          return;
        }
        if (ctrl.isRunning || ctrl.isScreencastActive) {
          setState(() {});
        }
      },
      onError: (error, stack) =>
          silentLog('web_reverse_dashboard_dialog', '浏览器占位计时器', error, stack),
    );
  }

  void _scheduleViewportSync(Size logical, double dpr) {
    if (_lastConfiguredSize == logical && _lastDpr == dpr) return;
    _lastConfiguredSize = logical;
    _lastDpr = dpr;
    _resizeDebouncer?.cancel();
    _resizeDebouncer = startSafeTimer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      // 三档优先级：① 设备模拟激活时强制按设备像素，避免画面被拉伸 / 模糊；
      // ② 用户在分辨率下拉手动指定时按它；③ 最后才是面板尺寸自适应。
      final device = _devicePreset;
      final autoW = (logical.width * dpr).round().clamp(160, 2560);
      final autoH = (logical.height * dpr).round().clamp(120, 1600);
      final override = _resolutionOverride;
      final int w;
      final int h;
      if (device != null) {
        w = (device.width * device.deviceScaleFactor).round();
        h = (device.height * device.deviceScaleFactor).round();
      } else if (override != null) {
        w = override.w;
        h = override.h;
      } else {
        w = autoW;
        h = autoH;
      }
      // 仅 cap 帧尺寸不会改变页面渲染尺寸（screencast 帧最终
      // 会被 BoxFit 拉到面板大小，看起来就"分辨率没生效"）；分辨率档位
      // 有效时同步下发 Emulation.setDeviceMetricsOverride，让页面真的按
      // 该尺寸渲染。device preset 自己已经管 emulation，保留原路径不动；
      // 选 Auto + 没设备 preset 时 clearDeviceMetricsOverride 把页面恢复
      // 为浏览器原生窗口尺寸。
      if (device == null) {
        if (override != null) {
          unawaited(
            widget.controller.applyResolutionEmulation(
              cssWidth: (override.w / dpr).round().clamp(160, 4096),
              cssHeight: (override.h / dpr).round().clamp(120, 4096),
              deviceScaleFactor: dpr,
            ),
          );
        } else {
          unawaited(
            widget.controller.applyResolutionEmulation(
              cssWidth: 0,
              cssHeight: 0,
              deviceScaleFactor: 0,
            ),
          );
        }
      }
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
    // 设备模拟激活后帧用 BoxFit.contain 渲染，画面只占面板
    // 中央一片，需要把鼠标 local 折算回去。计算思路：image 的宽高比 vs
    // renderSize 比，长边占满，短边居中留白；命中点先减去留白偏移再做
    // 比例换算。BoxFit.fill 路径下 letterbox = 0，等价旧逻辑。
    final letterboxed = _devicePreset != null && _frameW > 0 && _frameH > 0;
    var px = local.dx;
    var py = local.dy;
    var dispW = renderSize.width;
    var dispH = renderSize.height;
    if (letterboxed) {
      final imgAspect = _frameW / _frameH;
      final boxAspect = renderSize.width / renderSize.height;
      if (imgAspect > boxAspect) {
        // 横向更宽：上下留白。
        dispW = renderSize.width;
        dispH = renderSize.width / imgAspect;
        py = local.dy - (renderSize.height - dispH) / 2;
      } else {
        // 纵向更高：左右留白。
        dispH = renderSize.height;
        dispW = renderSize.height * imgAspect;
        px = local.dx - (renderSize.width - dispW) / 2;
      }
    }
    if (dispW <= 0 || dispH <= 0) return Offset.zero;
    final fx = px / dispW;
    final fy = py / dispH;
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
      _cropStart = e.localPosition;
      _cropCurrent = e.localPosition;
      if (!_cropScheduled) {
        _cropScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _cropScheduled = false;
          if (mounted) setState(() {});
        });
      }
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
      _cropCurrent = e.localPosition;
      if (!_cropScheduled) {
        _cropScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _cropScheduled = false;
          if (mounted) setState(() {});
        });
      }
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
        _cropMode = false;
        _cropStart = null;
        _cropCurrent = null;
        if (!_cropScheduled) {
          _cropScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _cropScheduled = false;
            if (mounted) setState(() {});
          });
        }
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
      // 用户使用真实鼠标滚轮，先把 trackpad 衰减计时器取消，避免两路同
      // 时往浏览器派 wheel 抖屏。
      _scrollInertiaTimer?.cancel();
      _scrollInertiaVelocity = Offset.zero;
      final p = _toViewport(e.localPosition, renderSize);
      // CDP Input.dispatchMouseEvent(mouseWheel) 约定：deltaY 为正 = 内容向上
      // 滚动（即用户看到的页面往下走），与 Flutter PointerScrollEvent.scrollDelta
      // 的方向语义已经一致，不需要再取反。早先取反导致页面往反方向走，体感
      // 上"完全无响应"。
      widget.controller.dispatchMouseEvent(
        type: 'mouseWheel',
        x: p.dx,
        y: p.dy,
        deltaX: e.scrollDelta.dx,
        deltaY: e.scrollDelta.dy,
        modifiers: _modifiersFromKeys(),
      );
    }
  }

  /// macOS / Linux trackpad 两指平移：Flutter 派发 PanZoom 事件而不是
  /// PointerScroll。这里把累计 pan delta 转成 mouseWheel 下发到 CDP，
  /// 让浏览器同样能滚动。
  void _handlePanZoomStart(PointerPanZoomStartEvent e, Size renderSize) {
    if (_cropMode) return;
    _panZoomActive = true;
    _lastPanZoomPan = Offset.zero;
    _lastPanZoomScale = 1;
    _scrollInertiaTimer?.cancel();
    _scrollInertiaVelocity = Offset.zero;
    _scrollInertiaAt = DateTime.now();
  }

  void _handlePanZoomUpdate(PointerPanZoomUpdateEvent e, Size renderSize) {
    if (_cropMode || !_panZoomActive) return;
    // ¹ 两指捂合缩放：e.scale 是相对手势起始的累计倍率。每当累计
    // 增量超过 4%，调一次 setZoomFactor，以下次应用的 scale 为基点重新
    // 起计。避免频繁下发 zoom 设置。
    final scaleRatio = e.scale / _lastPanZoomScale;
    if (scaleRatio < 0.96 || scaleRatio > 1.04) {
      final next = (_zoom * scaleRatio).clamp(0.25, 3.0);
      _lastPanZoomScale = e.scale;
      if ((next - _zoom).abs() > 0.005) {
        _zoom = next;
        if (!_zoomScheduled) {
          _zoomScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _zoomScheduled = false;
            if (mounted) setState(() {});
          });
        }
        unawaited(widget.controller.setZoomFactor(next));
      }
      return;
    }
    final delta = e.pan - _lastPanZoomPan;
    _lastPanZoomPan = e.pan;
    if (delta == Offset.zero) return;
    final p = _toViewport(e.localPosition, renderSize);
    final scaledDx = -delta.dx;
    final scaledDy = -delta.dy;
    widget.controller.dispatchMouseEvent(
      type: 'mouseWheel',
      x: p.dx,
      y: p.dy,
      // PanZoom 的 pan 正方向 = 手指右下；滚轮 deltaY 正 = 页面下移。两者
      // 一致，不取反。
      deltaX: scaledDx,
      deltaY: scaledDy,
      modifiers: _modifiersFromKeys(),
    );
    // 用最近一次 update 的速度近似当前手势速度（dt 取本次 update 的耗
    // 时；clamp 避免抖动放大）。下一次 update 用新的 delta 替换。
    final now = DateTime.now();
    final dtMs = now.difference(_scrollInertiaAt).inMilliseconds.clamp(8, 80);
    _scrollInertiaVelocity = Offset(
      scaledDx / dtMs * 16, // 折成「16ms 的位移」
      scaledDy / dtMs * 16,
    );
    _scrollInertiaAt = now;
    _scrollInertiaPos = p;
  }

  void _handlePanZoomEnd(PointerPanZoomEndEvent e, Size renderSize) {
    _panZoomActive = false;
    // 自然停止：松手后按指数衰减把残余速度继续以 16ms 间隔
    // 下发，模仿 macOS / iOS trackpad 的惯性。≈300ms 内把速度衰到接近 0。
    if (_scrollInertiaVelocity.distance < 1.5) {
      _scrollInertiaVelocity = Offset.zero;
      return;
    }
    _startScrollInertia();
  }

  void _startScrollInertia() {
    _scrollInertiaTimer?.cancel();
    _scrollInertiaTimer = startSafePeriodicTimer(
      kOpenHandFramePeriodicTimerInterval,
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        final v = _scrollInertiaVelocity;
        if (v.distance < 0.6) {
          timer.cancel();
          _scrollInertiaVelocity = Offset.zero;
          return;
        }
        widget.controller.dispatchMouseEvent(
          type: 'mouseWheel',
          x: _scrollInertiaPos.dx,
          y: _scrollInertiaPos.dy,
          deltaX: v.dx,
          deltaY: v.dy,
        );
        // 衰减系数 0.92：≈300ms 内速度衰减到 5%。
        _scrollInertiaVelocity = v * 0.92;
      },
      min: kOpenHandFramePeriodicTimerInterval,
    );
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    // ESC 是唯一不下发到浏览器的按键：交给外层
    // `_EscapeDismissDialogScope` 关闭整个 Web 逆向调试弹窗（find bar 已开
    // 时优先关 find bar）。其它所有按键统一通过 CDP `Input.dispatchKeyEvent`
    // 透传给浏览器侧 —— 不再走 IME 中转，因为 macOS IMK 会吞 Backspace /
    // Arrow / 标点。
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      if (_findBarOpen) {
        _closeFindBar();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    // 顶级快捷键拦截（Cmd on macOS / Ctrl elsewhere）：browser-like 操作走
    // 我们自己的 controller，不下发到浏览器侧（浏览器自身的快捷键被
    // screencast 屏蔽，需要 Flutter 端实现）。仅在 KeyDown 时触发，避免
    // KeyRepeat 二次触发误开多 tab / 关 tab。
    if (event is KeyDownEvent) {
      final pressed = HardwareKeyboard.instance.logicalKeysPressed;
      final hasMeta =
          pressed.contains(LogicalKeyboardKey.metaLeft) ||
          pressed.contains(LogicalKeyboardKey.metaRight);
      final hasCtrl =
          pressed.contains(LogicalKeyboardKey.controlLeft) ||
          pressed.contains(LogicalKeyboardKey.controlRight);
      final hasShift =
          pressed.contains(LogicalKeyboardKey.shiftLeft) ||
          pressed.contains(LogicalKeyboardKey.shiftRight);
      final cmd = Platform.isMacOS ? hasMeta : hasCtrl;
      if (cmd) {
        final key = event.logicalKey;
        // Cmd/Ctrl+V 走系统剪贴板透传：读取 Flutter 端
        // `Clipboard.getData('text/plain')`，通过 CDP `Input.insertText`
        // 注入到当前焦点输入框。直接模拟 Cmd+V 的旧路径只能让浏览器拿到
        // 它自己进程里的剪贴板（headless Chromium 通常是空的），剪贴桥
        // 不通。
        if (key == LogicalKeyboardKey.keyV) {
          unawaited(_shortcutPasteFromHostClipboard());
          return KeyEventResult.handled;
        }
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
    }
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      final meta = _cdpKeyMeta(event);
      final ch = event.character;
      final hasPrintable =
          ch != null && ch.isNotEmpty && ch.codeUnitAt(0) >= 0x20;
      // keyDown 一律不带 text；可打印字符通过紧随其后的 char
      // 事件写入文本节点。若 keyDown 也带 text，Chromium 会同时触发 keydown
      // 的默认插入路径 + char 的 textInput 路径，导致每个字符被写入两次
      // （bug：输入 "h" 浏览器显示 "hh"）。
      widget.controller.dispatchKeyEvent(
        type: hasPrintable ? 'keyDown' : 'rawKeyDown',
        key: meta.key,
        code: meta.code,
        windowsVirtualKeyCode: meta.vk,
        modifiers: _modifiersFromKeys(),
        autoRepeat: event is KeyRepeatEvent,
      );
      if (hasPrintable) {
        widget.controller.dispatchKeyEvent(
          type: 'char',
          key: ch,
          text: ch,
          modifiers: _modifiersFromKeys(),
        );
      }
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      final meta = _cdpKeyMeta(event);
      widget.controller.dispatchKeyEvent(
        type: 'keyUp',
        key: meta.key,
        code: meta.code,
        windowsVirtualKeyCode: meta.vk,
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
    _persistTabsAndUrls();
  }

  /// 读取宿主系统剪贴板的纯文本，按 CDP `Input.insertText` 注入到当前焦点
  /// 输入框。空剪贴板或非文本内容静默忽略。
  Future<void> _shortcutPasteFromHostClipboard() async {
    try {
      final text = await getOpenHandClipboardText();
      if (text == null || text.isEmpty) return;
      await widget.controller.insertText(text);
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', '从主机剪贴板粘贴', error, stack);
    }
  }

  Future<void> _shortcutCloseTab() async {
    final cur = widget.controller.currentPageTargetId;
    if (cur == null) return;
    await widget.controller.closePageTarget(cur);
    _persistTabsAndUrls();
  }

  static const _zoomLadder = <double>[0.5, 0.75, 1.0, 1.25, 1.5];

  Future<void> _shortcutZoomDelta(int dir) async {
    var idx = _zoomLadder.indexWhere((v) => (v - _zoom).abs() < 0.01);
    if (idx < 0) {
      // 当前不是档位之一，先就近吸附。
      idx = 0;
      for (var i = 0; i < _zoomLadder.length; i++) {
        if ((_zoomLadder[i] - _zoom).abs() < (_zoomLadder[idx] - _zoom).abs()) {
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
    _metaPersistDebouncer = startSafeTimer(
      const Duration(milliseconds: 350),
      () {
        if (!mounted) return;
        final state = context
            .findAncestorStateOfType<_WebReverseDashboardDialogState>();
        if (state == null) return;
        state.persistBrowserPanelState();
      },
    );
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
    _findDebouncer = startSafeTimer(
      const Duration(milliseconds: 200),
      () async {
        final n = await widget.controller.findInPage(s);
        if (!mounted) return;
        setState(() => _findMatchCount = n);
      },
    );
  }

  Future<void> _findNext() async {
    await widget.controller.findCycleNext();
  }

  Future<void> _findPrev() async {
    await widget.controller.findCycleNext(forward: false);
  }

  /// 把 Flutter [KeyEvent] 折成 CDP `Input.dispatchKeyEvent` 期待的三元组：
  ///   * `key`  ——  W3C UI Events `KeyboardEvent.key`（字符自身或 "Backspace"
  ///                "ArrowUp" "Enter" 等控制名）。
  ///   * `code` ——  W3C `KeyboardEvent.code`（"KeyA" / "Digit1" / "ArrowUp"
  ///                / "ShiftLeft"），表示物理键位置。
  ///   * `vk`   ——  Windows virtual-key-code（VK_BACK=8 / VK_RETURN=13 /
  ///                方向键 37–40 等），Chromium 用它生成 `keyCode` 兼容历史
  ///                Web 代码。
  /// 这是 Backspace / 方向键 / Enter / 标点真正能落到内嵌页面输入框的关键。
  ({String? key, String? code, int? vk}) _cdpKeyMeta(KeyEvent event) {
    final logical = event.logicalKey;
    final phys = event.physicalKey;
    final special = _kCdpSpecialKey[logical];
    if (special != null) {
      return (
        key: special.$1,
        code: special.$2 ?? phys.debugName,
        vk: special.$3,
      );
    }
    final ch = event.character;
    if (ch != null && ch.isNotEmpty) {
      // 字母 / 数字 / 标点：key = 字符；code 用 physical 名字；vk 取 ASCII
      // 大写值（Chromium 行为）。
      final upper = ch.toUpperCase();
      final cu = upper.codeUnitAt(0);
      return (key: ch, code: phys.debugName, vk: cu < 0x80 ? cu : null);
    }
    // 兜底：用 logical keyLabel 或 debugName，CDP 拿到非标准值时会忽略
    // 但至少不抛异常。
    final label = logical.keyLabel;
    return (
      key: label.isNotEmpty ? label : (logical.debugName ?? ''),
      code: phys.debugName,
      vk: null,
    );
  }

  // ── IME 桥实现 ────────────────────────────────────────────────────────

  void _onSurfaceFocusChanged() {
    if (!mounted) return;
    // 默认不随焦点挂 IME（macOS IMK 会吞 Backspace / 方向键 /
    // 标点 / Enter）；仅在用户显式开启 CJK 输入模式时，surface 拿焦才挂
    // TextInput connection，丢焦立即断。
    if (_cjkInputEnabled && _surfaceFocus.hasFocus) {
      _attachImeConnection();
    } else {
      _detachImeConnection();
    }
  }

  /// 切换 CJK 输入模式（地址栏键盘按钮触发）。开启后将挂 TextInput
  /// connection，让 macOS IME 把候选词通过 [updateEditingValue] 提交到内嵌
  /// 页面；关闭后立即断开，恢复物理键直通。
  void _toggleCjkInput() {
    if (!mounted) return;
    setState(() {
      _cjkInputEnabled = !_cjkInputEnabled;
    });
    if (_cjkInputEnabled && _surfaceFocus.hasFocus) {
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
    // 哨兵空格：IME 端始终保持一个可删的字符，这样物理 Backspace
    // 在默认空串的状态下也能产生 cur.length < old.length 增量，避免
    // 路由到 IME 的 Backspace 被默默吞掉。检测到哨兵被删后重置。
    _lastImeValue = const TextEditingValue(
      text: ' ',
      selection: TextSelection.collapsed(offset: 1),
    );
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
    // 通用 diff：找出公共前缀，old 剩余部分按 Backspace 删除，cur 剩余部分
    // 作为 insertText。这样无论 IME 是「追加 / 删尾 / 整体替换」哪种行为都能
    // 正确转换。包含哨兵空格被删的场景：old=' ', cur='' → 删一个；
    // 哨兵 + 追加字符：old=' ', cur=' a' → 删 0 个 + insert 'a'；
    // 整体替换：old=' ', cur='a' → 删 1 个 + insert 'a'。
    final oldCharacters = old.characters.toList(growable: false);
    final currentCharacters = cur.characters.toList(growable: false);
    var prefixLength = 0;
    final maxPrefix = math.min(oldCharacters.length, currentCharacters.length);
    while (prefixLength < maxPrefix &&
        oldCharacters[prefixLength] == currentCharacters[prefixLength]) {
      prefixLength++;
    }
    final toDelete = oldCharacters.length - prefixLength;
    final toInsert = currentCharacters.skip(prefixLength).join();
    for (var i = 0; i < toDelete; i++) {
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
    if (toInsert.isNotEmpty) {
      widget.controller.insertText(toInsert);
    }
    // 重置 IME 端为「哨兵空格」，让下一次物理 Backspace 仍能产生 delta，
    // 不会被 IME 默默吞掉；同时也避免文本无限增长。
    _lastImeValue = const TextEditingValue(
      text: ' ',
      selection: TextSelection.collapsed(offset: 1),
    );
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
        ..dispatchKeyEvent(type: 'keyUp', key: 'Enter', code: 'Enter');
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
    final ctrl = widget.controller;
    // 用户语义：每次回车都开一个新 tab。空白 about:blank 当前页可复用，
    // 否则新建 page target 后 switchTo。这样既保留多页对照逆向的工作流，
    // 又避免误覆盖当前已经登录 / 调试中的页面状态。
    final cur = ctrl.currentPageTargetId;
    final curUrl = cur == null
        ? null
        : ctrl.pageTargets
              .firstWhere(
                (t) => t.id == cur,
                orElse: () =>
                    const CdpPageTargetSnapshot(id: '', url: '', title: ''),
              )
              .url;
    final isBlank =
        curUrl == null ||
        curUrl.isEmpty ||
        curUrl.startsWith('about:') ||
        curUrl == 'chrome://newtab/';
    if (isBlank) {
      await ctrl.navigate(url);
    } else {
      final id = await ctrl.createPageTarget(url: url);
      if (id != null) await ctrl.switchToPageTarget(id);
    }
    _surfaceFocus.requestFocus();
  }

  /// 当前帧 PNG 落盘：优先用 CDP `Page.captureScreenshot` 拿一张实时全分辨
  /// 率截图（screencast 自身是 JPEG 低质，不适合做证据图）；失败则降级
  /// 用最近一帧 JPEG 字节直接落盘。
  Future<void> _saveCurrentFrame() async {
    final ctrl = widget.controller;
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
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '当前没有可用的画面帧',
          zhHant: '目前沒有可用的畫面幀',
          en: 'No frame available',
          fr: 'Aucune frame disponible',
          de: 'Kein Frame verfügbar',
          ja: '利用できるフレームがありません',
        ),
        duration: kOpenHandSnackBarBriefDuration,
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
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', '选择当前帧保存位置', error, stack);
    }
    if (!mounted || location == null) return;
    try {
      await writeBytesFileAtomically(File(location.path), bytes);
      if (!mounted) return;
      showOpenHandSuccessSnack(
        context,
        webReverseSavedToFileMessage(context, location.path),
      );
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', '保存当前帧', error, stack);
      if (!mounted) return;
      showOpenHandErrorSnack(
        context,
        webReverseSaveFailedMessage(context),
        duration: kOpenHandSnackBarBriefDuration,
      );
    }
  }

  /// 框选导出局部帧：full-resolution 截图后用 image 包做裁切，按用户在
  /// surface 上选的矩形百分比映射到浏览器侧 viewport 像素。
  Future<void> _finalizeCrop(Offset start, Offset end, Size renderSize) async {
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
      png = await widget.controller.captureScreenshot().timeout(
        const Duration(seconds: 10),
      );
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', '截取裁剪区域', error, stack);
    }
    if (!mounted) return;
    if (png == null) {
      showOpenHandErrorSnack(
        context,
        _wrScreenshotFailedLabel(context),
        duration: kOpenHandSnackBarBriefDuration,
      );
      return;
    }
    final decoded = img.decodePng(png) ?? img.decodeImage(png);
    if (decoded == null) {
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '解码失败',
          zhHant: '解碼失敗',
          en: 'Decode failed',
          fr: 'Échec du décodage',
          de: 'Dekodierung fehlgeschlagen',
          ja: 'デコードに失敗しました',
        ),
        duration: kOpenHandSnackBarBriefDuration,
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
    const typeGroup = XTypeGroup(label: 'PNG', extensions: <String>['png']);
    FileSaveLocation? location;
    try {
      location = await getSaveLocation(
        suggestedName: 'browser-crop-$ts.png',
        acceptedTypeGroups: <XTypeGroup>[typeGroup],
      );
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', '选择裁剪截图保存位置', error, stack);
    }
    if (!mounted || location == null) return;
    try {
      await writeBytesFileAtomically(File(location.path), out);
      if (!mounted) return;
      showOpenHandSuccessSnack(
        context,
        webReverseSavedToFileMessage(context, location.path),
      );
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', '保存裁剪截图', error, stack);
      if (!mounted) return;
      showOpenHandErrorSnack(
        context,
        webReverseSaveFailedMessage(context),
        duration: kOpenHandSnackBarBriefDuration,
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
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromLTRB(
      globalPos.dx,
      globalPos.dy,
      overlay.size.width - globalPos.dx,
      overlay.size.height - globalPos.dy,
    );
    final selected = await showAnimatedMenu<String>(
      context: context,
      position: position,
      items: [
        PopupMenuItem(value: 'copy', child: Text(openHandCopyLabel(context))),
        PopupMenuItem(
          value: 'paste',
          child: Text(
            openHandLocalizedText(
              context,
              zh: '粘贴',
              zhHant: '貼上',
              en: 'Paste',
              fr: 'Coller',
              de: 'Einfügen',
              ja: '貼り付け',
            ),
          ),
        ),
        PopupMenuItem(
          value: 'selectAll',
          child: Text(
            openHandLocalizedText(
              context,
              zh: '全选',
              zhHant: '全選',
              en: 'Select all',
              fr: 'Tout sélectionner',
              de: 'Alles auswählen',
              ja: 'すべて選択',
            ),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'reload', child: Text(_wrReloadLabel(context))),
        PopupMenuItem(
          value: 'inspect',
          child: Text(
            openHandLocalizedText(
              context,
              zh: '检查元素 (DevTools)',
              zhHant: '檢查元素 (DevTools)',
              en: 'Inspect (DevTools)',
              fr: 'Inspecter (DevTools)',
              de: 'Untersuchen (DevTools)',
              ja: '検証 (DevTools)',
            ),
          ),
        ),
        PopupMenuItem(
          value: 'openExternal',
          child: Text(
            openHandLocalizedText(
              context,
              zh: '在外部浏览器中打开',
              zhHant: '在外部瀏覽器中開啟',
              en: 'Open in external browser',
              fr: 'Ouvrir dans le navigateur externe',
              de: 'In externem Browser öffnen',
              ja: '外部ブラウザで開く',
            ),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'saveFrame',
          child: Text(
            openHandLocalizedText(
              context,
              zh: '保存当前帧 (PNG)',
              zhHant: '儲存目前幀 (PNG)',
              en: 'Save current frame',
              fr: 'Enregistrer la frame',
              de: 'Aktuellen Frame speichern',
              ja: '現在のフレームを保存',
            ),
          ),
        ),
        PopupMenuItem(
          value: 'cropFrame',
          child: Text(
            openHandLocalizedText(
              context,
              zh: '框选导出局部帧',
              zhHant: '框選匯出局部幀',
              en: 'Save selected region',
              fr: 'Enregistrer la zone sélectionnée',
              de: 'Ausgewählten Bereich speichern',
              ja: '選択範囲を保存',
            ),
          ),
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
        // 走宿主系统剪贴板，与 Cmd/Ctrl+V 透传同源；headless Chromium
        // 自己进程的剪贴板默认是空的，直接模拟 Cmd+V 会粘贴失败。
        await _shortcutPasteFromHostClipboard();
      case 'selectAll':
        await sendShortcut('a');
      case 'reload':
        await ctrl.reload();
      case 'inspect':
        if (mounted) {
          await _openOfficialDevToolsForController(context, ctrl);
        }
      case 'openExternal':
        final url = await ctrl.currentUrl();
        if (url == null || url.isEmpty) return;
        try {
          if (Platform.isMacOS) {
            await runTrackedProcessOrFailed(
              '/usr/bin/open',
              [url],
              timeout: _kOpenExternalUrlTimeout,
              tag: 'web_reverse.open_external',
            );
          } else if (Platform.isWindows) {
            await runTrackedProcessOrFailed(
              'cmd',
              ['/c', 'start', '', url],
              timeout: _kOpenExternalUrlTimeout,
              tag: 'web_reverse.open_external',
            );
          } else if (Platform.isLinux) {
            await runTrackedProcessOrFailed(
              'xdg-open',
              [url],
              timeout: _kOpenExternalUrlTimeout,
              tag: 'web_reverse.open_external',
            );
          }
        } catch (error, stack) {
          silentLog('web_reverse_dashboard_dialog', '在外部打开链接', error, stack);
        }
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
    final ctrl = widget.controller;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Column(
      children: [
        _TabStrip(
          targets: ctrl.pageTargets,
          currentId: ctrl.currentPageTargetId,
          enabled: ctrl.isBrowserAlive,
          onSwitch: (id) async {
            await ctrl.switchToPageTarget(id);
            _persistTabsAndUrls();
          },
          onClose: (id) async {
            await ctrl.closePageTarget(id);
            _persistTabsAndUrls();
          },
          onNew: () async {
            final id = await ctrl.createPageTarget();
            if (id != null) await ctrl.switchToPageTarget(id);
            _persistTabsAndUrls();
          },
          onReorder: (oldI, newI) {
            ctrl.reorderPageTarget(oldI, newI);
            _persistTabsAndUrls();
          },
        ),
        _buildAddressBar(theme, cs, ctrl),
        kOpenHandGap8,
        Expanded(
          // LayoutBuilder 必须包在 Padding 内部，否则 constraints
          // 是 Padding 外层尺寸（含 12+12 横向、12 纵向留白），而 Listener 实际
          // 命中区是 Padding 内层；二者错位导致 `_toViewport` 把右下角的点击
          // 投影到画面之外，"点不到截图边缘按钮"。
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final renderSize = Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                _scheduleViewportSync(renderSize, dpr);
                return ClipRRect(
                  borderRadius: kOpenHandBorderRadius14,
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: kOpenHandBorderRadius14,
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: _ScreencastImage(
                            controller: ctrl,
                            // 设备模拟激活时切到 contain 防止移动 / 平板尺寸
                            // 被横向拉伸 / 纵向截断；其它情况下用 fill 把帧
                            // 完整撑满面板（这是桌面 1:1 镜像的预期）。
                            fit: _devicePreset != null
                                ? BoxFit.contain
                                : BoxFit.fill,
                            placeholderBuilder: () =>
                                _buildPlaceholder(theme, cs, ctrl),
                          ),
                        ),
                        if (_surfaceInputReady)
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
                                onPointerPanZoomStart: (e) =>
                                    _handlePanZoomStart(e, renderSize),
                                onPointerPanZoomUpdate: (e) =>
                                    _handlePanZoomUpdate(e, renderSize),
                                onPointerPanZoomEnd: (e) =>
                                    _handlePanZoomEnd(e, renderSize),
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
                              borderRadius: BorderRadius.circular(
                                _kToolbarRadius,
                              ),
                              elevation: 4,
                              shadowColor: Colors.black26,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                child: Text(
                                  openHandLocalizedText(
                                    context,
                                    zh: '拖动选择导出区域，松手保存',
                                    zhHant: '拖動選擇匯出區域，放開後儲存',
                                    en: 'Drag to select region',
                                    fr: 'Faites glisser pour sélectionner',
                                    de: 'Bereich durch Ziehen auswählen',
                                    ja: 'ドラッグして保存範囲を選択',
                                  ),
                                  style: theme.textTheme.labelSmall,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddressBar(
    ThemeData theme,
    ColorScheme cs,
    WebReverseSessionController ctrl,
  ) {
    final alive = ctrl.isBrowserAlive;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          _NavIconButton(
            tooltip: openHandLocalizedText(
              context,
              zh: '后退',
              zhHant: '返回',
              en: 'Back',
              fr: 'Retour',
              de: 'Zurück',
              ja: '戻る',
            ),
            icon: Icons.arrow_back_rounded,
            onPressed: alive ? () => ctrl.goBack() : null,
          ),
          kOpenHandHGap6,
          _NavIconButton(
            tooltip: openHandLocalizedText(
              context,
              zh: '前进',
              zhHant: '前進',
              en: 'Forward',
              fr: 'Avancer',
              de: 'Vorwärts',
              ja: '進む',
            ),
            icon: Icons.arrow_forward_rounded,
            onPressed: alive ? () => ctrl.goForward() : null,
          ),
          kOpenHandHGap6,
          _NavIconButton(
            tooltip: _wrReloadLabel(context),
            icon: Icons.refresh_rounded,
            onPressed: alive ? () => ctrl.reload() : null,
          ),
          kOpenHandHGap10,
          Expanded(
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: _addressCtrl,
                focusNode: _addressBarFocus,
                enabled: alive,
                textAlignVertical: TextAlignVertical.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: kOpenHandMonospaceFontFamily,
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
                  hintText: openHandLocalizedText(
                    context,
                    zh: '输入 URL 后回车',
                    zhHant: '輸入 URL 後按 Enter',
                    en: 'Type URL and press Enter',
                    fr: 'Saisissez une URL puis Entrée',
                    de: 'URL eingeben und Enter drücken',
                    ja: 'URL を入力して Enter',
                  ),
                  prefixIcon: _HistoryDropdownIcon(
                    enabled: alive,
                    history: ctrl.navigationHistory,
                    onPick: (url) async {
                      _addressCtrl.text = url;
                      await ctrl.navigate(url);
                      _surfaceFocus.requestFocus();
                    },
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
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
          kOpenHandHGap10,
          _NavIconButton(
            tooltip: openHandLocalizedText(
              context,
              zh: '把键盘焦点交给页面（Esc/Tab/方向键等会送给浏览器）',
              zhHant: '將鍵盤焦點交給頁面（Esc/Tab/方向鍵會送給瀏覽器）',
              en: 'Focus surface (route Esc/Tab/Arrow keys to the page)',
              fr: 'Focaliser la page (Esc/Tab/flèches vers le navigateur)',
              de: 'Seite fokussieren (Esc/Tab/Pfeile an den Browser)',
              ja: 'ページにフォーカス（Esc/Tab/矢印キーをブラウザへ送信）',
            ),
            icon: Icons.center_focus_strong_rounded,
            onPressed: alive
                ? () {
                    // 1. 先 unfocus 让 IconButton 自身别抢走焦点；
                    // 2. microtask 里再 requestFocus 给 surface，并 dispatch 一次
                    //    mouseMoved 让 cursor 回到画面区域。
                    FocusScope.of(context).unfocus();
                    Future.microtask(() {
                      if (!mounted) return;
                      FocusScope.of(context).requestFocus(_surfaceFocus);
                    });
                  }
                : null,
          ),
          kOpenHandHGap6,
          _ZoomMenu(
            value: _zoom,
            enabled: alive,
            onChanged: (v) async {
              setState(() => _zoom = v);
              await ctrl.setZoomFactor(v);
            },
          ),
          kOpenHandHGap6,
          _ResolutionMenu(
            value: _resolutionOverride,
            enabled: alive,
            onChanged: (next) {
              setState(() {
                _resolutionOverride = next;
                // 强制下一次 LayoutBuilder rebuild 走 _scheduleViewportSync
                // 真实地按面板 logical size 算 maxWidth/maxHeight 再下发；
                // 直接读 ancestor render box 拿到的尺寸是错的（包了 padding 和
                // clip）。
                _lastConfiguredSize = null;
              });
            },
          ),
          kOpenHandHGap6,
          _DevicePresetMenu(
            value: _devicePreset,
            enabled: alive,
            onChanged: (next) async {
              setState(() {
                _devicePreset = next;
                _lastConfiguredSize = null;
              });
              await ctrl.setDeviceMetricsPreset(next);
              // 设备模拟切档后立即按设备物理像素更新 screencast 上界，
              // 否则 maxWidth/maxHeight 仍是面板尺寸 → 帧拉伸 / 模糊。
              if (next != null) {
                final w = (next.width * next.deviceScaleFactor).round();
                final h = (next.height * next.deviceScaleFactor).round();
                await ctrl.reconfigureScreencast(
                  maxWidth: w,
                  maxHeight: h,
                  quality: 80,
                );
              }
            },
          ),
          kOpenHandHGap6,
          _NavIconButton(
            tooltip: _cjkInputEnabled
                ? openHandLocalizedText(
                    context,
                    zh: '关闭中文输入（默认按键直发，特殊键全可用）',
                    zhHant: '關閉中文輸入（預設按鍵直送，特殊鍵全可用）',
                    en: 'Disable CJK input (default raw key passthrough)',
                    fr: 'Désactiver la saisie CJK',
                    de: 'CJK-Eingabe deaktivieren',
                    ja: 'CJK 入力を無効化',
                  )
                : openHandLocalizedText(
                    context,
                    zh: '开启中文输入（中/日/韩 IME 候选词上屏，部分特殊键可能被 IME 拦截）',
                    zhHant: '開啟中文輸入（中/日/韓 IME 候選詞上屏，部分特殊鍵可能被 IME 攔截）',
                    en: 'Enable CJK input (IME composition; some special keys may be captured)',
                    fr: 'Activer la saisie CJK via IME',
                    de: 'CJK-Eingabe über IME aktivieren',
                    ja: 'CJK 入力を有効化（IME 変換対応）',
                  ),
            icon: _cjkInputEnabled
                ? Icons.keyboard_alt_rounded
                : Icons.keyboard_alt_outlined,
            tinted: _cjkInputEnabled,
            onPressed: _toggleCjkInput,
          ),
          kOpenHandHGap6,
          _NavIconButton(
            tooltip: openHandLocalizedText(
              context,
              zh: '保存当前帧',
              zhHant: '儲存目前幀',
              en: 'Save current frame',
              fr: 'Enregistrer la frame',
              de: 'Aktuellen Frame speichern',
              ja: '現在のフレームを保存',
            ),
            icon: Icons.photo_camera_outlined,
            onPressed: alive ? _saveCurrentFrame : null,
          ),
          kOpenHandHGap6,
          _NavIconButton(
            tooltip: alive
                ? _webReverseDashRestartBrowserLabel(context)
                : openHandLocalizedText(
                    context,
                    zh: '启动浏览器',
                    zhHant: '啟動瀏覽器',
                    en: 'Start browser',
                    fr: 'Démarrer le navigateur',
                    de: 'Browser starten',
                    ja: 'ブラウザを起動',
                  ),
            icon: _restartBrowserInFlight
                ? Icons.hourglass_top_rounded
                : Icons.restart_alt_rounded,
            onPressed: _restartBrowserInFlight
                ? null
                : () => _restartBrowserFromUi('toolbar'),
          ),
          kOpenHandHGap6,
          _NavIconButton(
            tooltip: openHandLocalizedText(
              context,
              zh: '停止调试',
              zhHant: '停止偵錯',
              en: 'Stop browser',
              fr: 'Arrêter le navigateur',
              de: 'Browser stoppen',
              ja: 'ブラウザを停止',
            ),
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
              Icon(Icons.power_off_rounded, size: 36, color: cs.error),
              kOpenHandGap12,
              Text(
                openHandLocalizedText(
                  context,
                  zh: '浏览器已断开',
                  zhHant: '瀏覽器已斷開',
                  en: 'Browser disconnected',
                  fr: 'Navigateur déconnecté',
                  de: 'Browser getrennt',
                  ja: 'ブラウザが切断されました',
                ),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              kOpenHandGap6,
              Text(
                err.isEmpty
                    ? openHandLocalizedText(
                        context,
                        zh: '会话仍在，但 CDP 已断。点击下方按钮重新拉起浏览器即可继续逆向。',
                        zhHant: '會話仍在，但 CDP 已斷開。點擊下方按鈕重新拉起瀏覽器即可繼續逆向。',
                        en: 'Session retained but CDP is down. Click below to relaunch the browser.',
                        fr: 'La session est conservée mais CDP est coupé. Relancez le navigateur ci-dessous.',
                        de: 'Die Sitzung bleibt erhalten, aber CDP ist getrennt. Starten Sie den Browser unten neu.',
                        ja: 'セッションは残っていますが CDP が切断されています。下のボタンで再起動できます。',
                      )
                    : err,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              kOpenHandGap16,
              FilledButton.icon(
                onPressed: _restartBrowserInFlight
                    ? null
                    : () => _restartBrowserFromUi('placeholder'),
                icon: _restartBrowserInFlight
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(cs.onPrimary),
                        ),
                      )
                    : const Icon(Icons.restart_alt_rounded, size: 16),
                label: Text(
                  _restartBrowserInFlight
                      ? _webReverseDashRestartingLabel(context)
                      : _webReverseDashRestartBrowserLabel(context),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final screencastActive = ctrl.isScreencastActive;
    final startedAt = ctrl.screencastStartedAt;
    final waiting = startedAt == null
        ? Duration.zero
        : DateTime.now().difference(startedAt);
    final waitingSeconds = waiting.inSeconds.clamp(0, 999);
    final slow = screencastActive && waiting >= _kFirstFrameSlowThreshold;
    final target = _currentTargetLabel(ctrl);
    final title = !running
        ? openHandLocalizedText(
            context,
            zh: '会话尚未运行',
            zhHant: '會話尚未執行',
            en: 'Session is not running',
            fr: 'La session n’est pas lancée',
            de: 'Sitzung läuft nicht',
            ja: 'セッションは実行されていません',
          )
        : screencastActive
        ? openHandLocalizedText(
            context,
            zh: '等待 CDP 首帧',
            zhHant: '等待 CDP 首幀',
            en: 'Waiting for first CDP frame',
            fr: 'Attente de la première frame CDP',
            de: 'Warten auf ersten CDP-Frame',
            ja: 'CDP の最初のフレームを待機中',
          )
        : openHandLocalizedText(
            context,
            zh: '正在启动 CDP screencast',
            zhHant: '正在啟動 CDP screencast',
            en: 'Starting CDP screencast',
            fr: 'Démarrage du screencast CDP',
            de: 'CDP-Screencast wird gestartet',
            ja: 'CDP screencast を開始中',
          );
    final detail = !running
        ? openHandLocalizedText(
            context,
            zh: 'CDP 会话未运行，无法启动浏览器画面。',
            zhHant: 'CDP 會話未執行，無法啟動瀏覽器畫面。',
            en: 'The CDP session is not running, so the browser surface cannot start.',
            fr: 'La session CDP n’est pas lancée, la surface ne peut pas démarrer.',
            de: 'Die CDP-Sitzung läuft nicht; die Browserfläche kann nicht starten.',
            ja: 'CDP セッションが実行されていないため、ブラウザ画面を開始できません。',
          )
        : slow
        ? openHandLocalizedText(
            context,
            zh: 'CDP screencast 已启动 ${waitingSeconds}s，但还没有收到画面帧。Chrome 窗口最小化或 target 切换中都可能暂停首帧。',
            zhHant:
                'CDP screencast 已啟動 ${waitingSeconds}s，但尚未收到畫面幀。Chrome 視窗最小化或 target 切換中都可能延後首幀。',
            en: 'CDP screencast has been active for ${waitingSeconds}s without a frame. A minimized Chrome window or target switch can delay the first frame.',
            fr: 'Le screencast CDP est actif depuis ${waitingSeconds}s sans frame. Une fenêtre minimisée ou un changement de cible peut retarder la première frame.',
            de: 'CDP-Screencast ist seit ${waitingSeconds}s aktiv, aber ohne Frame. Ein minimiertes Chrome-Fenster oder Zielwechsel kann den ersten Frame verzögern.',
            ja: 'CDP screencast は ${waitingSeconds}s 動作中ですがフレーム未受信です。Chrome の最小化や target 切替で遅れる場合があります。',
          )
        : screencastActive
        ? openHandLocalizedText(
            context,
            zh: 'CDP screencast 已启动，正在等待浏览器推送画面帧。',
            zhHant: 'CDP screencast 已啟動，正在等待瀏覽器推送畫面幀。',
            en: 'CDP screencast is active and waiting for Chrome to push a frame.',
            fr: 'Le screencast CDP est actif et attend une frame Chrome.',
            de: 'CDP-Screencast ist aktiv und wartet auf einen Chrome-Frame.',
            ja: 'CDP screencast は開始済みで、Chrome からのフレームを待っています。',
          )
        : openHandLocalizedText(
            context,
            zh: '正在向当前 page target 发送 Page.startScreencast。',
            zhHant: '正在向目前 page target 傳送 Page.startScreencast。',
            en: 'Sending Page.startScreencast to the current page target.',
            fr: 'Envoi de Page.startScreencast à la cible page actuelle.',
            de: 'Page.startScreencast wird an das aktuelle page target gesendet.',
            ja: '現在の page target に Page.startScreencast を送信中です。',
          );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation(
                    slow ? cs.tertiary : cs.primary,
                  ),
                ),
              ),
              kOpenHandGap12,
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              kOpenHandGap6,
              Text(
                detail,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              if (target.isNotEmpty) ...[
                kOpenHandGap8,
                Text(
                  target,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontFamily: kOpenHandMonospaceFontFamily,
                  ),
                ),
              ],
              if (slow || !running) ...[
                kOpenHandGap16,
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (running)
                      OutlinedButton.icon(
                        onPressed: () => ctrl.reload(),
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: Text(
                          openHandLocalizedText(
                            context,
                            zh: '刷新页面',
                            zhHant: '重新整理頁面',
                            en: 'Reload',
                            fr: 'Recharger',
                            de: 'Neu laden',
                            ja: '再読み込み',
                          ),
                        ),
                      ),
                    FilledButton.icon(
                      onPressed: _restartBrowserInFlight
                          ? null
                          : () => _restartBrowserFromUi('frame placeholder'),
                      icon: _restartBrowserInFlight
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(
                                  cs.onPrimary,
                                ),
                              ),
                            )
                          : const Icon(Icons.restart_alt_rounded, size: 16),
                      label: Text(
                        _restartBrowserInFlight
                            ? _webReverseDashRestartingLabel(context)
                            : openHandLocalizedText(
                                context,
                                zh: '重启浏览器',
                                zhHant: '重啟瀏覽器',
                                en: 'Restart',
                                fr: 'Redémarrer',
                                de: 'Neu starten',
                                ja: '再起動',
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _currentTargetLabel(WebReverseSessionController ctrl) {
    final currentId = ctrl.currentPageTargetId;
    if (currentId == null || currentId.isEmpty) return '';
    for (final target in ctrl.pageTargets) {
      if (target.id != currentId) continue;
      final url = target.url.trim();
      if (url.isNotEmpty && url != 'about:blank') return url;
      final title = target.title.trim();
      if (title.isNotEmpty) return title;
      return currentId;
    }
    return currentId;
  }
}

class _NavIconButton extends StatelessWidget {
  const _NavIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.tinted = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool tinted;

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
          color: tinted
              ? cs.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_kToolbarRadius),
            side: BorderSide(
              color: tinted
                  ? cs.primary.withValues(alpha: 0.55)
                  : (enabled
                        ? cs.outlineVariant
                        : cs.outlineVariant.withValues(alpha: 0.4)),
            ),
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(_kToolbarRadius),
            child: Center(
              child: Icon(
                icon,
                size: 18,
                color: tinted
                    ? cs.primary
                    : (enabled
                          ? cs.onSurface
                          : cs.onSurface.withValues(alpha: 0.35)),
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
    required this.fit,
  });

  final WebReverseSessionController controller;
  final Widget Function() placeholderBuilder;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: controller.screencastFrameNotifier,
      builder: (_, _, _) {
        final frame = controller.latestScreencastFrame;
        if (frame == null) return placeholderBuilder();
        // 关键：不要在 [Image.memory] 上挂 ValueKey(seq)。挂上后每帧 seq
        // 自增都会让 Flutter 销毁旧 Image element 重建新的，导致 gaplessPlayback
        // 完全失效，鼠标稍微一动就出现"瞬间空白闪烁"。这里依赖
        // [MemoryImage] 内置的 bytes 引用比较 + gaplessPlayback 把旧帧
        // 挂在画面上直到新帧 decode 完毕，整个画面流就稳定不抖。
        return RepaintBoundary(
          child: Image.memory(
            frame,
            fit: fit,
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
    required this.onChanged,
  });

  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;

  static const _presets = <double>[0.5, 0.75, 1.0, 1.25, 1.5];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Tooltip(
      message: openHandLocalizedText(
        context,
        zh: '页面缩放',
        zhHant: '頁面縮放',
        en: 'Page zoom',
        fr: 'Zoom de page',
        de: 'Seitenzoom',
        ja: 'ページズーム',
      ),
      child: SizedBox(
        height: _kToolbarHeight,
        child: AnimatedPopupMenuButton<double>(
          enabled: enabled,
          tooltip: '',
          onSelected: onChanged,
          itemBuilder: (_) => _presets
              .map(
                (p) => PopupMenuItem<double>(
                  value: p,
                  child: Text('${(p * 100).round()}%'),
                ),
              )
              .toList(growable: false),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: _toolbarChipDecoration(cs, enabled: enabled),
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
                kOpenHandHGap4,
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
class _TabStrip extends StatefulWidget {
  const _TabStrip({
    required this.targets,
    required this.currentId,
    required this.enabled,
    required this.onSwitch,
    required this.onClose,
    required this.onNew,
    required this.onReorder,
  });

  final List<CdpPageTargetSnapshot> targets;
  final String? currentId;
  final bool enabled;
  final ValueChanged<String> onSwitch;
  final ValueChanged<String> onClose;
  final VoidCallback onNew;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  State<_TabStrip> createState() => _TabStripState();
}

class _TabStripState extends State<_TabStrip> {
  // 维护一份「正在显示中」的 Tab 列表 + 「正在退场中」的 id 集合：
  // 当父组件传入的 targets 较上一帧少了某个 id（Tab 关闭），不立刻把它
  // 从 ListView 中拿掉，而是先标记为 closing，让 _TabPill 通过 AnimatedSize
  // + AnimatedOpacity + AnimatedScale 收缩到 0；240ms 后再从内部列表移除，
  // 避免「啪地一下消失」。新增 Tab 直接走 TweenAnimationBuilder 入场。
  final List<CdpPageTargetSnapshot> _displayed = <CdpPageTargetSnapshot>[];
  final Set<String> _closingIds = <String>{};
  final Map<String, Timer> _closingTimers = <String, Timer>{};
  static const Duration _closeAnim = kOpenHandMotion240;

  @override
  void initState() {
    super.initState();
    _displayed.addAll(widget.targets);
  }

  @override
  void didUpdateWidget(covariant _TabStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTargets(widget.targets);
  }

  @override
  void dispose() {
    for (final t in _closingTimers.values) {
      t.cancel();
    }
    _closingTimers.clear();
    super.dispose();
  }

  void _syncTargets(List<CdpPageTargetSnapshot> incoming) {
    final incomingIds = incoming.map((t) => t.id).toSet();
    // 1) 把已经在 incoming 里的 id 同步元数据 + 顺序：从 _displayed 中
    //    剔除非 closing 项，按 incoming 的顺序重排（closing 项保持原位置）。
    final retained = <CdpPageTargetSnapshot>[];
    final closingKept = <CdpPageTargetSnapshot>[];
    for (final d in _displayed) {
      if (_closingIds.contains(d.id)) {
        // closing 项继续保留在末尾占位，等动画跑完。
        closingKept.add(d);
      }
    }
    for (final t in incoming) {
      retained.add(t);
    }
    // 2) 找出新被关闭的：上一帧在 _displayed 里、这一帧不在 incoming 里、
    //    且还没标记 closing 的，标记为 closing 并启动 240ms 定时器。
    for (final d in _displayed) {
      if (!incomingIds.contains(d.id) && !_closingIds.contains(d.id)) {
        _closingIds.add(d.id);
        // 维持当前快照里的最后一份元数据（含可能已变的 title）。
        closingKept.add(d);
        _closingTimers[d.id]?.cancel();
        _closingTimers[d.id] = startSafeTimer(_closeAnim, () {
          if (!mounted) return;
          setState(() {
            _closingIds.remove(d.id);
            _closingTimers.remove(d.id);
            _displayed.removeWhere((x) => x.id == d.id);
          });
        });
      }
    }
    _displayed
      ..clear()
      ..addAll(retained)
      ..addAll(closingKept);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (_displayed.isEmpty) return const SizedBox.shrink();
    // 退场动效跟随全局设置；关闭动效时标签立即消失，_closeAnim 定时器仍按原
    // 时长把它从 _displayed 里摘掉，不影响清理时序。
    final closeMotionDuration = openHandMotionDuration(context, _closeAnim);
    // 把 onReorder 限定在「非 closing」前缀范围内 —— ReorderableListView 自带
    // 索引是覆盖整个列表的，但 closing 项不能参与排序，所以把传出的索引按需
    // 截断到 widget.targets 的范围内。
    final activeCount = widget.targets.length;
    final targets = _displayed;
    final currentId = widget.currentId;
    final enabled = widget.enabled;
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
                onReorder: enabled
                    ? (oldI, newI) {
                        // 只允许在「活跃 Tab」范围内排序；不让用户拖到 closing 占位上。
                        if (oldI >= activeCount) return;
                        var clamped = newI;
                        if (clamped > activeCount) clamped = activeCount;
                        widget.onReorder(oldI, clamped);
                      }
                    : (_, _) {},
                proxyDecorator: (child, _, anim) {
                  return Material(
                    elevation: 4 * anim.value,
                    color: Colors.transparent,
                    borderRadius: kOpenHandPillBorderRadius,
                    child: child,
                  );
                },
                itemCount: targets.length,
                itemBuilder: (_, i) {
                  final t = targets[i];
                  final active = t.id == currentId;
                  final closing = _closingIds.contains(t.id);
                  final label = t.title.isNotEmpty
                      ? t.title
                      : (t.url.isEmpty
                            ? _wrNewTabLabel(context)
                            : Uri.tryParse(t.url)?.host ?? t.url);
                  return Padding(
                    key: ValueKey<String>(t.id),
                    padding: EdgeInsets.only(
                      right: i == targets.length - 1 ? 0 : 6,
                    ),
                    // 退场动画外壳：closing=true 时把高度 / 宽度 / 透明度 / 缩放
                    // 一起收缩到 0，240ms 后由定时器从 _displayed 里移除。
                    child: AnimatedSize(
                      duration: closeMotionDuration,
                      curve: Curves.easeInCubic,
                      alignment: Alignment.centerLeft,
                      child: AnimatedOpacity(
                        duration: closeMotionDuration,
                        opacity: closing ? 0 : 1,
                        curve: Curves.easeInCubic,
                        child: AnimatedScale(
                          duration: closeMotionDuration,
                          scale: closing ? 0.6 : 1,
                          curve: Curves.easeInCubic,
                          alignment: Alignment.centerLeft,
                          child: closing
                              ? const SizedBox(width: 0, height: 0)
                              : TweenAnimationBuilder<double>(
                                  tween: Tween<double>(begin: 0.85, end: 1),
                                  duration: openHandMotionDuration(
                                    context,
                                    kOpenHandMotion260,
                                  ),
                                  curve: Curves.easeOutBack,
                                  builder: (_, v, child) => Opacity(
                                    opacity: v.clamp(0, 1),
                                    child: Transform.scale(
                                      scale: v,
                                      child: child,
                                    ),
                                  ),
                                  child: AnimatedContainer(
                                    duration: openHandMotionDuration(
                                      context,
                                      kOpenHandMotion220,
                                    ),
                                    curve: Curves.easeOutCubic,
                                    decoration: BoxDecoration(
                                      color: active
                                          ? cs.primaryContainer
                                          : cs.surfaceContainerHighest,
                                      borderRadius: kOpenHandPillBorderRadius,
                                      border: Border.all(
                                        color: active
                                            ? cs.primary.withValues(alpha: 0.4)
                                            : Colors.transparent,
                                      ),
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      borderRadius: kOpenHandPillBorderRadius,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // 在 tab 左侧加一个独立 drag
                                          // handle，使用 ReorderableDragStartListener
                                          // 即点即拖，不再需要等长按（之前的 long-
                                          // press 在桌面下被 InkWell 抢走 / 体验差）。
                                          ReorderableDragStartListener(
                                            index: i,
                                            child: MouseRegion(
                                              cursor: SystemMouseCursors.grab,
                                              child: Padding(
                                                padding: const EdgeInsets.only(
                                                  left: 6,
                                                  right: 2,
                                                ),
                                                child: Icon(
                                                  Icons.drag_indicator_rounded,
                                                  size: 12,
                                                  color: active
                                                      ? cs.onPrimaryContainer
                                                            .withValues(
                                                              alpha: 0.7,
                                                            )
                                                      : cs.onSurfaceVariant
                                                            .withValues(
                                                              alpha: 0.7,
                                                            ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          InkWell(
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                            onTap: enabled
                                                ? () => widget.onSwitch(t.id)
                                                : null,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
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
                                                  kOpenHandHGap6,
                                                  AnimatedDefaultTextStyle(
                                                    duration:
                                                        kOpenHandMotion220,
                                                    style: theme
                                                        .textTheme
                                                        .labelSmall!
                                                        .copyWith(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: active
                                                              ? cs.onPrimaryContainer
                                                              : cs.onSurface,
                                                        ),
                                                    child: ConstrainedBox(
                                                      constraints:
                                                          const BoxConstraints(
                                                            maxWidth: 140,
                                                          ),
                                                      child: AnimatedSwitcher(
                                                        duration:
                                                            kOpenHandMotion280,
                                                        switchInCurve:
                                                            Curves.easeOutBack,
                                                        switchOutCurve:
                                                            Curves.easeInCubic,
                                                        transitionBuilder: (child, animation) {
                                                          // Q 弹文本切换：fade + 轻微上推 + 缩放，
                                                          // 标题刷新（CDP `Page.frameNavigated` 后
                                                          // `_refreshPageTitle` 写回）时让胶囊文字
                                                          // 顺滑替换，不闪烁。
                                                          final slide =
                                                              Tween<Offset>(
                                                                begin:
                                                                    const Offset(
                                                                      0,
                                                                      0.25,
                                                                    ),
                                                                end:
                                                                    Offset.zero,
                                                              ).animate(
                                                                animation,
                                                              );
                                                          return FadeTransition(
                                                            opacity: animation,
                                                            child: SlideTransition(
                                                              position: slide,
                                                              child: ScaleTransition(
                                                                scale:
                                                                    Tween<
                                                                          double
                                                                        >(
                                                                          begin:
                                                                              0.92,
                                                                          end:
                                                                              1,
                                                                        )
                                                                        .animate(
                                                                          animation,
                                                                        ),
                                                                child: child,
                                                              ),
                                                            ),
                                                          );
                                                        },
                                                        layoutBuilder:
                                                            (
                                                              current,
                                                              previous,
                                                            ) {
                                                              return Stack(
                                                                alignment: Alignment
                                                                    .centerLeft,
                                                                children: [
                                                                  ...previous,
                                                                  if (current !=
                                                                      null)
                                                                    current,
                                                                ],
                                                              );
                                                            },
                                                        child: Text(
                                                          label,
                                                          key: ValueKey<String>(
                                                            label,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  if (activeCount > 1) ...[
                                                    kOpenHandHGap6,
                                                    InkResponse(
                                                      radius: 12,
                                                      onTap: enabled
                                                          ? () => widget
                                                                .onClose(t.id)
                                                          : null,
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
                                        ],
                                      ),
                                    ),
                                  ),
                                ), // TweenAnimationBuilder
                        ), // AnimatedScale
                      ), // AnimatedOpacity
                    ), // AnimatedSize
                  );
                },
              ),
            ),
            kOpenHandHGap6,
            Tooltip(
              message: openHandLocalizedText(
                context,
                zh: '新建标签页',
                zhHant: '新增分頁',
                en: 'New tab',
                fr: 'Nouvel onglet',
                de: 'Neuer Tab',
                ja: '新しいタブ',
              ),
              child: SizedBox(
                width: 26,
                height: 26,
                child: Material(
                  color: cs.surfaceContainerHighest,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: enabled ? widget.onNew : null,
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
    required this.onChanged,
    required this.onPrev,
    required this.onNext,
    required this.onClose,
  });

  final FocusNode focusNode;
  final TextEditingController controller;
  final int matchCount;
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
            kOpenHandHGap6,
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
                  hintText: openHandLocalizedText(
                    context,
                    zh: '查找词条',
                    zhHant: '查找詞條',
                    en: 'Find',
                    fr: 'Rechercher',
                    de: 'Suchen',
                    ja: '検索',
                  ),
                  hintStyle: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.65),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                ),
              ),
            ),
            kOpenHandHGap6,
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
              tooltip: openHandLocalizedText(
                context,
                zh: '上一个',
                zhHant: '上一個',
                en: 'Previous',
                fr: 'Précédent',
                de: 'Vorheriges',
                ja: '前へ',
              ),
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              onPressed: matchCount > 0 ? () async => onPrev() : null,
              icon: const Icon(Icons.keyboard_arrow_up_rounded),
            ),
            kOpenHandHGap4,
            IconButton(
              tooltip: openHandLocalizedText(
                context,
                zh: '下一个',
                zhHant: '下一個',
                en: 'Next',
                fr: 'Suivant',
                de: 'Nächstes',
                ja: '次へ',
              ),
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              onPressed: matchCount > 0 ? () async => onNext() : null,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
            ),
            kOpenHandHGap4,
            IconButton(
              tooltip: openHandCloseLabel(context),
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded),
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
    canvas.drawRect(rect, Paint()..blendMode = BlendMode.clear);
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

/// screencast 分辨率档位下拉：自动 / 720p / 1080p / 1440p / 2160p。
/// 选中后立即覆盖 [_BrowserBodyState._resolutionOverride] 并触发一次重新
/// 下发；选「自动」回到面板尺寸自适应路径。
class _ResolutionMenu extends StatelessWidget {
  const _ResolutionMenu({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final ({int w, int h})? value;
  final bool enabled;
  final ValueChanged<({int w, int h})?> onChanged;

  static const _presets = <({String label, int? w, int? h})>[
    (label: 'Auto', w: null, h: null),
    (label: '720p', w: 1280, h: 720),
    (label: '1080p', w: 1920, h: 1080),
    (label: '1440p', w: 2560, h: 1440),
    (label: '2160p', w: 3840, h: 2160),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cur = value;
    final label = cur == null ? openHandAutoLabel(context) : '${cur.h}p';
    return Tooltip(
      message: openHandLocalizedText(
        context,
        zh: '画面分辨率',
        zhHant: '畫面解析度',
        en: 'Frame resolution',
        fr: 'Résolution de la frame',
        de: 'Frame-Auflösung',
        ja: 'フレーム解像度',
      ),
      child: SizedBox(
        height: _kToolbarHeight,
        child: AnimatedPopupMenuButton<({int? w, int? h})>(
          enabled: enabled,
          tooltip: '',
          onSelected: (p) {
            if (p.w == null || p.h == null) {
              onChanged(null);
            } else {
              onChanged((w: p.w!, h: p.h!));
            }
          },
          itemBuilder: (_) => _presets
              .map(
                (p) => PopupMenuItem<({int? w, int? h})>(
                  value: (w: p.w, h: p.h),
                  child: Text(p.label),
                ),
              )
              .toList(growable: false),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: _toolbarChipDecoration(cs, enabled: enabled),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.high_quality_rounded,
                  size: 14,
                  color: enabled
                      ? cs.onSurfaceVariant
                      : cs.onSurface.withValues(alpha: 0.35),
                ),
                kOpenHandHGap4,
                Text(
                  label,
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

/// 设备模拟预设下拉：桌面 / 平板 / 移动；选中后调
/// `Emulation.setDeviceMetricsOverride` + `setUserAgentOverride`。
class _DevicePresetMenu extends StatelessWidget {
  const _DevicePresetMenu({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final WebReverseDevicePreset? value;
  final bool enabled;
  final ValueChanged<WebReverseDevicePreset?> onChanged;

  static const _presets = <WebReverseDevicePreset?>[
    null,
    WebReverseDevicePreset.mobile375,
    WebReverseDevicePreset.tablet768,
    WebReverseDevicePreset.desktop1440,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    String label() {
      switch (value?.id) {
        case 'mobile':
          return openHandLocalizedText(
            context,
            zh: '移动',
            zhHant: '行動',
            en: 'Mobile',
            fr: 'Mobile',
            de: 'Mobil',
            ja: 'モバイル',
          );
        case 'tablet':
          return openHandLocalizedText(
            context,
            zh: '平板',
            zhHant: '平板',
            en: 'Tablet',
            fr: 'Tablette',
            de: 'Tablet',
            ja: 'タブレット',
          );
        case 'desktop':
          return openHandLocalizedText(
            context,
            zh: '桌面',
            zhHant: '桌面',
            en: 'Desktop',
            fr: 'Bureau',
            de: 'Desktop',
            ja: 'デスクトップ',
          );
        default:
          return openHandLocalizedText(
            context,
            zh: '原生',
            zhHant: '原生',
            en: 'Native',
            fr: 'Natif',
            de: 'Nativ',
            ja: 'ネイティブ',
          );
      }
    }

    IconData icon() {
      switch (value?.id) {
        case 'mobile':
          return Icons.smartphone_rounded;
        case 'tablet':
          return Icons.tablet_mac_rounded;
        case 'desktop':
          return Icons.desktop_windows_rounded;
        default:
          return Icons.devices_other_rounded;
      }
    }

    return Tooltip(
      message: openHandLocalizedText(
        context,
        zh: '设备模拟',
        zhHant: '裝置模擬',
        en: 'Device emulation',
        fr: 'Émulation d’appareil',
        de: 'Geräteemulation',
        ja: 'デバイスエミュレーション',
      ),
      child: SizedBox(
        height: _kToolbarHeight,
        child: AnimatedPopupMenuButton<({WebReverseDevicePreset? preset})>(
          enabled: enabled,
          tooltip: '',
          onSelected: (selection) => onChanged(selection.preset),
          itemBuilder: (_) => _presets
              .map(
                (p) => PopupMenuItem<({WebReverseDevicePreset? preset})>(
                  value: (preset: p),
                  child: Text(
                    p == null
                        ? openHandLocalizedText(
                            context,
                            zh: '原生（清除模拟）',
                            zhHant: '原生（清除模擬）',
                            en: 'Native (clear)',
                            fr: 'Natif (effacer)',
                            de: 'Nativ (zurücksetzen)',
                            ja: 'ネイティブ（解除）',
                          )
                        : p.label,
                  ),
                ),
              )
              .toList(growable: false),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: _toolbarChipDecoration(cs, enabled: enabled),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon(),
                  size: 14,
                  color: enabled
                      ? cs.onSurfaceVariant
                      : cs.onSurface.withValues(alpha: 0.35),
                ),
                kOpenHandHGap4,
                Text(
                  label(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
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

/// 地址栏前置图标兼"历史下拉"按钮：点击弹本会话访问过的 URL 列表，
/// 按时间倒序，最多显示最近 30 条。选中即直接 navigate 过去。
class _HistoryDropdownIcon extends StatelessWidget {
  const _HistoryDropdownIcon({
    required this.enabled,
    required this.history,
    required this.onPick,
  });

  final bool enabled;
  final List<String> history;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final visible = history.reversed.take(30).toList(growable: false);
    return AnimatedPopupMenuButton<String>(
      enabled: enabled && visible.isNotEmpty,
      tooltip: openHandLocalizedText(
        context,
        zh: '导航历史',
        zhHant: '導覽歷史',
        en: 'Navigation history',
        fr: 'Historique de navigation',
        de: 'Navigationsverlauf',
        ja: 'ナビゲーション履歴',
      ),
      onSelected: onPick,
      itemBuilder: (_) => visible
          .map(
            (u) => PopupMenuItem<String>(
              value: u,
              height: 32,
              child: Text(
                u,
                style: const TextStyle(
                  fontFamily: kOpenHandMonospaceFontFamily,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(growable: false),
      child: Padding(
        padding: const EdgeInsets.only(left: 12, right: 4),
        child: Icon(
          Icons.history_rounded,
          size: 18,
          color: enabled
              ? cs.onSurfaceVariant
              : cs.onSurface.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}

// ── 本文件内复用的文案 ──
// 同一标签在本文件里出现两次以上；抽成函数后措辞只有一个改动点。

String _webReverseDashRestartBrowserLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '重启浏览器',
    zhHant: '重啟瀏覽器',
    en: 'Restart browser',
    fr: 'Redémarrer le navigateur',
    de: 'Browser neu starten',
    ja: 'ブラウザを再起動',
  );
}

String _webReverseDashRestartingLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '重启中...',
    zhHant: '重啟中...',
    en: 'Restarting...',
    fr: 'Redémarrage...',
    de: 'Neustart...',
    ja: '再起動中...',
  );
}
