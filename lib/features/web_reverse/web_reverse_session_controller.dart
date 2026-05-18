import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../app/support/silent_log.dart';
import 'web_reverse_browser_launcher.dart';
import 'web_reverse_cdp_client.dart';
import 'web_reverse_har_replay_server.dart';
import 'web_reverse_mitmproxy_bridge.dart';
import 'web_reverse_session_artifacts.dart';
import 'web_reverse_session_config.dart';

/// 单个 Web 逆向会话的运行时编排：浏览器进程、CDP 通道、
/// dashboard 实时数据缓冲。
///
/// 生命周期：
///   detect (上游已完成)
///     → constructor
///     → start()        // 启动浏览器 + 连 CDP + 启用 dock
///     → 期间 widgets / 工具读取 [networkRequests] / [consoleMessages] 等
///     → stop()         // 关 dock + 关 CDP + kill 浏览器进程
///     → dispose()
///
/// 错误模型：start() 失败抛 Exception；运行期错误打到 [errorMessage]
/// 由 UI 显示，会话本身不会自杀。
class WebReverseSessionController extends ChangeNotifier {
  WebReverseSessionController({
    required this.config,
    required this.executablePath,
    required this.artifactsRootDir,
    WebReverseBrowserLauncher? launcher,
    WebReverseSessionArtifacts? artifacts,
  })  : _launcher = launcher ?? WebReverseBrowserLauncher(),
        _artifacts =
            artifacts ?? WebReverseSessionArtifacts(rootDir: artifactsRootDir);

  final WebReverseSessionConfig config;
  final String executablePath;

  /// 会话工作目录，默认 `~/.openhand/web_reverse/<session_id>`。
  /// 落盘的 jsonl / HAR / 截图都放这里，方便模型 Bash 读取。
  final String artifactsRootDir;

  final WebReverseBrowserLauncher _launcher;
  final WebReverseSessionArtifacts _artifacts;

  WebReverseLaunchResult? _launchResult;
  WebReverseCdpClient? _browserCdp;
  WebReverseCdpClient? _pageCdp;
  StreamSubscription<CdpEvent>? _pageEventsSub;
  String? _pageSessionId;
  WebReverseHarReplayServer? _harReplayServer;
  WebReverseHarReplayServer? get harReplayServer => _harReplayServer;

  bool _started = false;
  bool _stopped = false;
  bool _disposed = false;
  bool _preserveLog = true;
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// 由 dashboard banner 在用户主动关闭诊断卡片后调用：把 [_errorMessage]
  /// 清空，让 banner 不再渲染。下次 start() 失败会重置为新的错误文本。
  void clearErrorMessage() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    _safeNotify();
  }
  String? _lastHarPath;
  String? get lastHarPath => _lastHarPath;

  bool get isRunning => _started && !_stopped;

  /// 真实判定外部浏览器进程是否还活着。CDP WebSocket 自身有重连，但当
  /// `_closed=true` 时表示重连已彻底失败 → 浏览器多半被用户手动关掉了。
  /// `isRunning && isBrowserAlive` 同时为真才是「画面应该有响应」。
  bool get isBrowserAlive {
    if (_stopped) return false;
    final cdp = _browserCdp;
    if (cdp == null) return false;
    return !cdp.isClosed;
  }

  Timer? _aliveWatchdog;

  /// CDP 端口（已分配；可能与 config.cdpPort 不同——后者是 desired）。
  int? get cdpPort => _launchResult?.cdpPort;
  String? get browserVersion => _launchResult?.browserVersion;

  // ── Dashboard 数据缓冲 ────────────────────────────────────────────────
  // 目标：让 UI 用 ListenableBuilder 直接拉数据，CDP 事件 → 这里 → UI。
  // 容量上限保护：单条会话累计可能上万请求，超过 [_maxNetworkEntries] 后
  // FIFO 淘汰，避免内存膨胀。Dashboard 弹窗里也支持"清空"按钮主动复位。

  static const int _maxNetworkEntries = 2000;
  static const int _maxConsoleEntries = 2000;

  final List<CdpNetworkEntry> _networkRequests = <CdpNetworkEntry>[];
  final Map<String, CdpNetworkEntry> _networkByRequestId =
      <String, CdpNetworkEntry>{};
  final List<CdpConsoleEntry> _consoleMessages = <CdpConsoleEntry>[];

  List<CdpNetworkEntry> get networkRequests =>
      List<CdpNetworkEntry>.unmodifiable(_networkRequests);
  List<CdpConsoleEntry> get consoleMessages =>
      List<CdpConsoleEntry>.unmodifiable(_consoleMessages);

  int get errorCount =>
      _networkRequests.where((e) => e.isError).length +
      _consoleMessages.where((e) => e.level == 'error').length;

  // ── 内嵌浏览器 screencast 状态 ───────────────────────────────────────
  // dashboard 切到「浏览器」tab 时打开 startScreencast，把 page 的实时画面
  // 以 JPEG 帧推过来；切走 / 关闭 dashboard 时立刻 stopScreencast。资源
  // 控制三道闸：
  //   1. 引用计数 _screencastRefCount：多个 widget 同时订阅时只发一次 start。
  //   2. _latestScreencastFrame 仅保留最近一帧（Uint8List），避免堆内存爬高。
  //   3. ack-back 模型：CDP 每帧带 sessionId，需立即 Page.screencastFrameAck，
  //      否则浏览器会停推；这里同步 ack 保证每帧不积压。
  static const int _screencastDefaultMaxWidth = 1280;
  static const int _screencastDefaultMaxHeight = 720;
  static const int _screencastDefaultQuality = 70;

  int _screencastRefCount = 0;
  bool _screencastActive = false;
  Uint8List? _latestScreencastFrame;
  int _screencastFrameSeq = 0;
  // 给浏览器面板专用的细粒度信号源：每收到一帧自增一次。widget 监听
  // 这个 [Listenable] 局部 repaint，不会唤醒 controller 上的其它监听器
  // （dashboard 头部 / network list 等），把 60fps 帧流的 fanout 降到最小。
  final ValueNotifier<int> screencastFrameNotifier = ValueNotifier<int>(0);

  /// Initiator → Sources 跳转请求总线：dashboard 监听这个 notifier 切到
  /// Sources tab 并定位到 (url, line, col)。点击栈帧或重定向条目时
  /// `requestSourceJump` 更新 value，dashboard 处理完置回 null。
  final ValueNotifier<({String url, int line, int col})?> sourceJumpRequest =
      ValueNotifier<({String url, int line, int col})?>(null);

  /// 触发 Initiator 跳转到 Sources。`line` / `col` 都使用 CDP 的 0-based
  /// 行列号；UI 渲染时再 +1。
  void requestSourceJump({required String url, int line = 0, int col = 0}) {
    if (url.isEmpty) return;
    sourceJumpRequest.value = (url: url, line: line, col: col);
  }

  /// dashboard 完成跳转后调用以避免重复响应。
  void clearSourceJumpRequest() {
    sourceJumpRequest.value = null;
  }
  int _screencastWidth = _screencastDefaultMaxWidth;
  int _screencastHeight = _screencastDefaultMaxHeight;
  int _screencastQuality = _screencastDefaultQuality;
  DateTime? _lastScreencastFrameAt;

  /// 当前最新一帧（JPEG 字节）；切到浏览器 tab 后 widget 用 [Image.memory] 渲染。
  Uint8List? get latestScreencastFrame => _latestScreencastFrame;

  /// 帧序号（自增），widget 用作 key 触发 [Image.memory] 重绘。
  int get screencastFrameSeq => _screencastFrameSeq;

  /// 当前帧的浏览器视口尺寸（CSS 像素）。
  int get screencastWidth => _screencastWidth;
  int get screencastHeight => _screencastHeight;

  bool get isScreencastActive => _screencastActive;

  /// 上次帧到达时间，UI 用来判断"是否长时间无帧"以提示用户。
  DateTime? get lastScreencastFrameAt => _lastScreencastFrameAt;

  // ── 生命周期 ─────────────────────────────────────────────────────────

  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      await _artifacts.init();
      _launchResult = await _launcher.launch(
        executablePath: executablePath,
        browserKind: config.browserKind,
        userDataDir: config.userDataDir,
        startUrl: config.targetUrl,
        proxy: config.proxy,
      );
      _browserCdp = WebReverseCdpClient(
        endpoint: _launchResult!.webSocketDebuggerUrl,
      );
      await _browserCdp!.connect();
      // attach 到目标 page target，订阅其网络 / 控制台事件。
      await _attachToFirstPage();
      _startAliveWatchdog();
      _safeNotify();
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', 'start', error, stack);
      _errorMessage = error.toString();
      _started = false;
      await _safeStop();
      rethrow;
    }
  }

  Future<void> _attachToFirstPage() async {
    final cdp = _browserCdp!;
    // 列出所有 page target，挑第一个跟 config.targetUrl 同 origin 的。
    final targets = await cdp.send('Target.getTargets');
    final infos = (targets['targetInfos'] as List?) ?? const <Object?>[];
    Map<String, Object?>? chosen;
    for (final t in infos.whereType<Map>()) {
      if (t['type'] == 'page') {
        chosen = Map<String, Object?>.from(t);
        break;
      }
    }
    if (chosen == null) {
      throw const CdpException(code: -1, message: '未发现 page target；浏览器可能没有打开任何标签页');
    }
    final targetId = chosen['targetId'] as String;
    // 订阅 page target 的创建 / 销毁 / 信息变化，让 dashboard 实时更新 tab strip。
    await cdp.send(
      'Target.setDiscoverTargets',
      params: const <String, Object?>{'discover': true},
    );
    await _attachToTargetInternal(targetId);
    // 首次拉满当前所有 page target。
    _refreshTargetsFromInfos(infos);
  }

  /// 多标签页：dashboard 浏览器面板的 tab strip 数据源。每条 entry 反映一个
  /// CDP page target，包含 id / url / title / favicon。
  final List<CdpPageTargetSnapshot> _pageTargets = <CdpPageTargetSnapshot>[];
  String? _currentTargetId;

  /// 2026-05-24 — 每个 page target 的 panel 缓冲快照：切走时保存，切回时
  /// 恢复，避免"切走再切回 → 现场全没了"的体验断裂。Sources 缓存的源码
  /// 体积可能 MB 级，所以最多保留 8 个最近活跃 target，LRU 淘汰旧的。
  final Map<String, _PerTargetBuffer> _targetBuffers =
      <String, _PerTargetBuffer>{};
  static const int _kTargetBufferLruCap = 8;

  List<CdpPageTargetSnapshot> get pageTargets =>
      List<CdpPageTargetSnapshot>.unmodifiable(_pageTargets);
  String? get currentPageTargetId => _currentTargetId;

  void _captureBufferForCurrentTarget() {
    final id = _currentTargetId;
    if (id == null || id.isEmpty) return;
    _targetBuffers[id] = _PerTargetBuffer(
      networkRequests: List<CdpNetworkEntry>.from(_networkRequests),
      networkByRequestId: Map<String, CdpNetworkEntry>.from(_networkByRequestId),
      consoleMessages: List<CdpConsoleEntry>.from(_consoleMessages),
      parsedScripts:
          Map<String, ({String url, bool isModule})>.from(_parsedScripts),
      scriptSources: Map<String, String>.from(_scriptSources),
      bpIdByKey: Map<String, String>.from(_bpIdByKey),
      lastUsedAt: DateTime.now(),
    );
    _evictOldestTargetBuffers();
  }

  void _restoreBufferForTarget(String targetId) {
    final saved = _targetBuffers.remove(targetId);
    if (saved == null) return;
    _networkRequests
      ..clear()
      ..addAll(saved.networkRequests);
    _networkByRequestId
      ..clear()
      ..addAll(saved.networkByRequestId);
    _consoleMessages
      ..clear()
      ..addAll(saved.consoleMessages);
    _parsedScripts
      ..clear()
      ..addAll(saved.parsedScripts);
    _scriptSources
      ..clear()
      ..addAll(saved.scriptSources);
    _bpIdByKey
      ..clear()
      ..addAll(saved.bpIdByKey);
  }

  void _evictOldestTargetBuffers() {
    if (_targetBuffers.length <= _kTargetBufferLruCap) return;
    final entries = _targetBuffers.entries.toList()
      ..sort((a, b) => a.value.lastUsedAt.compareTo(b.value.lastUsedAt));
    while (_targetBuffers.length > _kTargetBufferLruCap && entries.isNotEmpty) {
      final oldest = entries.removeAt(0);
      _targetBuffers.remove(oldest.key);
    }
  }

  void _refreshTargetsFromInfos(List<dynamic> infos) {
    _pageTargets.clear();
    for (final t in infos.whereType<Map>()) {
      if (t['type'] != 'page') continue;
      _pageTargets.add(CdpPageTargetSnapshot(
        id: '${t['targetId'] ?? ''}',
        url: '${t['url'] ?? ''}',
        title: '${t['title'] ?? ''}',
      ));
    }
    _safeNotify();
  }

  Future<void> _attachToTargetInternal(String targetId) async {
    final cdp = _browserCdp!;
    // 切换前主动 detach 旧 session（如果有），避免事件流叠加。
    if (_pageSessionId != null) {
      try {
        await cdp.send(
          'Target.detachFromTarget',
          params: <String, Object?>{'sessionId': _pageSessionId},
        );
      } catch (_) {}
      _pageSessionId = null;
    }
    // 新 page 上 finder 还没注入；切完 target 第一次 findInPage 会按需注入。
    _finderInstalled = false;
    // 2026-05-24 — Per-tab buffer：切 tab 前先把当前 target 的 panel 缓冲
    // 快照存到 _targetBuffers，切到目标 tab 后再 restore；新建 / 首次访问
    // 的 target 没有快照就只清空。Sources 端的 _userBreakpoints 仍按
    // (url,line) 维度持久化在 metadata 里，不在这里动。
    _captureBufferForCurrentTarget();
    _networkRequests.clear();
    _networkByRequestId.clear();
    _consoleMessages.clear();
    _parsedScripts.clear();
    _scriptSources.clear();
    _bpIdByKey.clear();
    final attachResult = await cdp.send(
      'Target.attachToTarget',
      params: <String, Object?>{
        'targetId': targetId,
        'flatten': true,
      },
    );
    _pageSessionId = attachResult['sessionId'] as String?;
    _currentTargetId = targetId;
    // 2026-05-24 — 还原该 target 上次切走时保存的 panel 缓冲。新 target /
    // 第一次进入则跳过；网络 enable 之后再立刻补入，让 navigation 事件
    // 流接着累计。
    _restoreBufferForTarget(targetId);
    await cdp.send(
      'Network.enable',
      params: const <String, Object?>{
        'maxResourceBufferSize': 16 * 1024 * 1024,
        'maxTotalBufferSize': 64 * 1024 * 1024,
      },
      sessionId: _pageSessionId,
    );
    await cdp.send('Page.enable', sessionId: _pageSessionId);
    await cdp.send('Runtime.enable', sessionId: _pageSessionId);
    await cdp.send('Log.enable', sessionId: _pageSessionId);
    // 当前 target 换了，上轮拿到的 hook scriptId 在新 target 上
    // 无意义，重新沿着新 _pageSessionId 装载 enabled hook。
    await _reapplyEnabledHooks();
    await _pageEventsSub?.cancel();
    _pageEventsSub = cdp.events
        .where((ev) => ev.sessionId == null || ev.sessionId == _pageSessionId)
        .listen(_onCdpEvent);
    _safeNotify();
  }

  /// 切换当前活跃的 page target。会重启 screencast（若已激活）。
  Future<void> switchToPageTarget(String targetId) async {
    if (_currentTargetId == targetId) return;
    final cdp = _browserCdp;
    if (cdp == null) return;
    final wasActive = _screencastActive;
    if (wasActive) {
      try {
        await cdp.send('Page.stopScreencast', sessionId: _pageSessionId);
      } catch (_) {}
      _screencastActive = false;
    }
    try {
      await _attachToTargetInternal(targetId);
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'switchToPageTarget $targetId',
        error,
        stack,
      );
      return;
    }
    if (wasActive) {
      try {
        await cdp.send(
          'Page.startScreencast',
          params: <String, Object?>{
            'format': 'jpeg',
            'quality': _screencastQuality,
            'maxWidth': _screencastWidth,
            'maxHeight': _screencastHeight,
            'everyNthFrame': 1,
          },
          sessionId: _pageSessionId,
        );
        _screencastActive = true;
      } catch (_) {}
    }
  }

  /// 新建一个 page target（默认 about:blank）；上层切到它即可在新 tab 操作。
  /// 重排 page target 顺序：只动本地 `_pageTargets` 数组，并把当前顺序
  /// 同步给上层（持久化到 session metadata 由调用方负责）。
  void reorderPageTarget(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= _pageTargets.length ||
        newIndex < 0 ||
        newIndex > _pageTargets.length) {
      return;
    }
    final adjustedNewIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final item = _pageTargets.removeAt(oldIndex);
    _pageTargets.insert(adjustedNewIndex, item);
    _safeNotify();
  }

  /// 当前 page target 顺序的 ID 列表，调用方持久化用。
  List<String> get pageTargetOrder =>
      _pageTargets.map((e) => e.id).toList(growable: false);

  /// 用持久化过的顺序重排现有 `_pageTargets`：未在列表中的保留原序追加在末尾。
  void applyPageTargetOrder(List<String> order) {
    if (order.isEmpty || _pageTargets.isEmpty) return;
    final indexById = <String, int>{
      for (var i = 0; i < order.length; i++) order[i]: i,
    };
    _pageTargets.sort((a, b) {
      final ai = indexById[a.id] ?? (1 << 30);
      final bi = indexById[b.id] ?? (1 << 30);
      return ai.compareTo(bi);
    });
    _safeNotify();
  }

  /// 用新快照整体替换 [_pageTargets]，调用方保证元素对齐。
  void replacePageTargets(List<CdpPageTargetSnapshot> next) {
    _pageTargets
      ..clear()
      ..addAll(next);
    _safeNotify();
  }

  Future<String?> createPageTarget({String url = 'about:blank'}) async {
    final cdp = _browserCdp;
    if (cdp == null) return null;
    try {
      final r = await cdp.send(
        'Target.createTarget',
        params: <String, Object?>{'url': url},
      );
      return r['targetId'] as String?;
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'createPageTarget',
        error,
        stack,
      );
      return null;
    }
  }

  /// 关闭指定 page target。若正在被使用，先切到下一个再关。
  Future<void> closePageTarget(String targetId) async {
    final cdp = _browserCdp;
    if (cdp == null) return;
    if (_currentTargetId == targetId && _pageTargets.length > 1) {
      // 选下一个不同 id 的 target 切过去。
      final next = _pageTargets.firstWhere(
        (t) => t.id != targetId,
        orElse: () => const CdpPageTargetSnapshot(id: '', url: '', title: ''),
      );
      if (next.id.isNotEmpty) await switchToPageTarget(next.id);
    }
    try {
      await cdp.send(
        'Target.closeTarget',
        params: <String, Object?>{'targetId': targetId},
      );
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'closePageTarget $targetId',
        error,
        stack,
      );
    }
  }

  void _onCdpEvent(CdpEvent ev) {
    switch (ev.method) {
      case '__cdp_reconnected__':
        // CDP 抖动断开后自动重连成功 → 重新 enable 各 domain。
        // 不阻塞事件循环，全部 fire-and-forget。
        unawaited(_reattachAfterReconnect());
        return;
      case '__cdp_dead__':
        // 重连彻底失败：浏览器可能已经被用户手动关掉。把 screencast 状态
        // 复位、清掉缓存帧、通知 UI 切到"已断开 / 可重启"占位。
        _screencastActive = false;
        _latestScreencastFrame = null;
        _screencastFrameSeq = 0;
        if (!_disposed) {
          // 帧序号 +1 而不是赋 0，让 ValueListenableBuilder 一定能 rebuild
          // 拿到 null 帧切换到 placeholder。
          screencastFrameNotifier.value = screencastFrameNotifier.value + 1;
        }
        _errorMessage = '浏览器已断开（CDP 自动重连失败），可点击「重启浏览器」恢复。';
        _safeNotify();
        return;
      case 'Network.requestWillBeSent':
        _onRequestWillBeSent(ev.params);
      case 'Network.responseReceived':
        _onResponseReceived(ev.params);
      case 'Network.loadingFailed':
        _onLoadingFailed(ev.params);
      case 'Network.loadingFinished':
        _onLoadingFinished(ev.params);
      case 'Network.webSocketCreated':
        _onWebSocketCreated(ev.params);
      case 'Network.webSocketFrameSent':
        _onWebSocketFrame(ev.params, CdpWebSocketDirection.sent);
      case 'Network.webSocketFrameReceived':
        _onWebSocketFrame(ev.params, CdpWebSocketDirection.received);
      case 'Network.webSocketFrameError':
        _onWebSocketFrame(ev.params, CdpWebSocketDirection.error);
      case 'Page.frameNavigated':
        _onFrameNavigated(ev.params);
      case 'Page.screencastFrame':
        _onScreencastFrame(ev.params);
      case 'Target.targetCreated':
      case 'Target.targetInfoChanged':
        _onTargetUpserted(ev.params);
      case 'Target.targetDestroyed':
        _onTargetDestroyed(ev.params);
      case 'Runtime.consoleAPICalled':
        _onConsoleApi(ev.params);
      case 'Log.entryAdded':
        _onLogEntry(ev.params);
      case 'Security.securityStateChanged':
        _onSecurityStateChanged(ev.params);
      case 'Fetch.requestPaused':
        _onFetchRequestPaused(ev.params);
      case 'Debugger.scriptParsed':
        _onScriptParsed(ev.params);
    }
  }

  // ── Performance / Memory / Application / Security / Recorder API ─────

  /// 拉取 `Performance.getMetrics`：返回每个指标 (name, value)。失败返回空。
  Future<List<(String, double)>> performanceMetrics() async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return const [];
    try {
      await cdp.send('Performance.enable', sessionId: _pageSessionId);
      final r = await cdp.send(
        'Performance.getMetrics',
        sessionId: _pageSessionId,
      );
      final metrics = r['metrics'] as List?;
      if (metrics == null) return const [];
      return metrics.whereType<Map>().map((m) {
        final n = '${m['name'] ?? ''}';
        final v = (m['value'] as num?)?.toDouble() ?? 0;
        return (n, v);
      }).toList(growable: false);
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', 'performanceMetrics', error, stack);
      return const [];
    }
  }

  /// `HeapProfiler.takeHeapSnapshot` 并通过 chunk 事件聚合返回。
  /// 返回字段：(rawJson, totalBytes)；调用方写盘或解析 summary。
  Future<({String json, int bytes})?> takeHeapSnapshot() async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return null;
    final buffer = StringBuffer();
    final completer = Completer<void>();
    StreamSubscription<CdpEvent>? sub;
    try {
      await cdp.send('HeapProfiler.enable', sessionId: _pageSessionId);
      sub = cdp.events.where((e) => e.sessionId == _pageSessionId).listen((e) {
        if (e.method == 'HeapProfiler.addHeapSnapshotChunk') {
          buffer.write('${e.params['chunk'] ?? ''}');
        } else if (e.method == 'HeapProfiler.reportHeapSnapshotProgress') {
          if (e.params['finished'] == true && !completer.isCompleted) {
            completer.complete();
          }
        }
      });
      // CDP 在 takeHeapSnapshot 返回时已发完所有 chunk；后置完成兜底。
      await cdp.send(
        'HeapProfiler.takeHeapSnapshot',
        params: const <String, Object?>{
          'reportProgress': true,
          'captureNumericValue': false,
        },
        sessionId: _pageSessionId,
        timeout: const Duration(seconds: 60),
      );
      // takeHeapSnapshot 同步返回时一般 chunk 已 flush 完，等一小段防边界。
      await Future.any<void>([
        completer.future,
        Future<void>.delayed(const Duration(milliseconds: 250)),
      ]);
      final raw = buffer.toString();
      return (json: raw, bytes: raw.length);
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'takeHeapSnapshot',
        error,
        stack,
      );
      return null;
    } finally {
      await sub?.cancel();
    }
  }

  /// 跑一次 `Performance.startTrace` / `stopTrace` 并返回 trace JSON 字符串。
  /// CDP 把 trace 通过 dataCollected 事件分块推；本方法做完整收集。
  Future<String?> recordTrace({
    required Duration duration,
    List<String> categories = const [
      'devtools.timeline',
      'v8.execute',
      'disabled-by-default-devtools.timeline',
    ],
  }) async {
    final cdp = _browserCdp;
    if (cdp == null) return null; // tracing 用 root session
    final events = <Map<String, Object?>>[];
    final completer = Completer<void>();
    StreamSubscription<CdpEvent>? sub;
    try {
      sub = cdp.events.listen((e) {
        if (e.method == 'Tracing.dataCollected') {
          final list = e.params['value'] as List?;
          if (list != null) {
            for (final item in list.whereType<Map>()) {
              events.add(Map<String, Object?>.from(item));
            }
          }
        } else if (e.method == 'Tracing.tracingComplete') {
          if (!completer.isCompleted) completer.complete();
        }
      });
      await cdp.send('Tracing.start', params: <String, Object?>{
        'categories': categories.join(','),
        'transferMode': 'ReportEvents',
      });
      await Future<void>.delayed(duration);
      await cdp.send('Tracing.end');
      await completer.future
          .timeout(const Duration(seconds: 30), onTimeout: () {});
      return jsonEncode(<String, Object?>{
        'traceEvents': events,
        'metadata': <String, Object?>{
          'source': 'OpenHand WebReverseExpert',
          'duration_ms': duration.inMilliseconds,
        },
      });
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'recordTrace',
        error,
        stack,
      );
      return null;
    } finally {
      await sub?.cancel();
    }
  }

  // ── Application: Cookies / Storage ───────────────────────────────────

  Future<List<Map<String, Object?>>> listCookies() async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return const [];
    try {
      final r = await cdp.send('Network.getAllCookies', sessionId: _pageSessionId);
      final list = r['cookies'] as List?;
      return list?.whereType<Map>().map((m) => Map<String, Object?>.from(m)).toList() ??
          const [];
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', 'listCookies', error, stack);
      return const [];
    }
  }

  Future<List<({String key, String value})>> listDomStorage({
    required String origin,
    required bool isLocalStorage,
  }) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return const [];
    try {
      await cdp.send('DOMStorage.enable', sessionId: _pageSessionId);
      final r = await cdp.send(
        'DOMStorage.getDOMStorageItems',
        params: <String, Object?>{
          'storageId': <String, Object?>{
            'securityOrigin': origin,
            'isLocalStorage': isLocalStorage,
          },
        },
        sessionId: _pageSessionId,
      );
      final entries = r['entries'] as List?;
      if (entries == null) return const [];
      return entries
          .whereType<List>()
          .where((p) => p.length >= 2)
          .map((p) => (key: '${p[0]}', value: '${p[1]}'))
          .toList(growable: false);
    } catch (error, stack) {
      silentLog(
          'web_reverse_session_controller', 'listDomStorage', error, stack);
      return const [];
    }
  }

  /// `Network.deleteCookies` 删一条 cookie。失败返回 false。
  Future<bool> deleteCookie({
    required String name,
    String? domain,
    String? path,
  }) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    try {
      await cdp.send(
        'Network.deleteCookies',
        params: <String, Object?>{
          'name': name,
          if (domain != null) 'domain': domain,
          if (path != null) 'path': path,
        },
        sessionId: _pageSessionId,
      );
      return true;
    } catch (error, stack) {
      silentLog(
          'web_reverse_session_controller', 'deleteCookie $name', error, stack);
      return false;
    }
  }

  /// `Network.setCookie` 写 / 改一条 cookie。
  Future<bool> setCookie({
    required String name,
    required String value,
    String? domain,
    String? path,
    bool? secure,
    bool? httpOnly,
    String? sameSite,
    int? expires,
  }) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    try {
      await cdp.send(
        'Network.setCookie',
        params: <String, Object?>{
          'name': name,
          'value': value,
          if (domain != null) 'domain': domain,
          if (path != null) 'path': path,
          if (secure != null) 'secure': secure,
          if (httpOnly != null) 'httpOnly': httpOnly,
          if (sameSite != null) 'sameSite': sameSite,
          if (expires != null) 'expires': expires,
        },
        sessionId: _pageSessionId,
      );
      return true;
    } catch (error, stack) {
      silentLog(
          'web_reverse_session_controller', 'setCookie $name', error, stack);
      return false;
    }
  }

  /// `DOMStorage.setDOMStorageItem` —— 写 / 改一条 storage 项。
  Future<bool> setDomStorageItem({
    required String origin,
    required bool isLocalStorage,
    required String key,
    required String value,
  }) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    try {
      await cdp.send('DOMStorage.enable', sessionId: _pageSessionId);
      await cdp.send(
        'DOMStorage.setDOMStorageItem',
        params: <String, Object?>{
          'storageId': <String, Object?>{
            'securityOrigin': origin,
            'isLocalStorage': isLocalStorage,
          },
          'key': key,
          'value': value,
        },
        sessionId: _pageSessionId,
      );
      return true;
    } catch (error, stack) {
      silentLog(
          'web_reverse_session_controller', 'setDomStorageItem', error, stack);
      return false;
    }
  }

  Future<bool> removeDomStorageItem({
    required String origin,
    required bool isLocalStorage,
    required String key,
  }) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    try {
      await cdp.send('DOMStorage.enable', sessionId: _pageSessionId);
      await cdp.send(
        'DOMStorage.removeDOMStorageItem',
        params: <String, Object?>{
          'storageId': <String, Object?>{
            'securityOrigin': origin,
            'isLocalStorage': isLocalStorage,
          },
          'key': key,
        },
        sessionId: _pageSessionId,
      );
      return true;
    } catch (error, stack) {
      silentLog(
          'web_reverse_session_controller', 'removeDomStorageItem', error, stack);
      return false;
    }
  }

  /// 读取 page 当前主 frame 的 origin（formed via Runtime.evaluate）。
  Future<String?> currentOrigin() async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return null;
    try {
      final r = await cdp.send(
        'Runtime.evaluate',
        params: const <String, Object?>{
          'expression': 'window.location.origin',
          'returnByValue': true,
        },
        sessionId: _pageSessionId,
      );
      return (r['result'] as Map?)?['value'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// `IndexedDB.requestDatabaseNames` —— 当前 origin 下所有数据库名。
  Future<List<String>> listIndexedDbNames() async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return const [];
    try {
      await cdp.send('IndexedDB.enable', sessionId: _pageSessionId);
      final origin = await currentOrigin();
      if (origin == null) return const [];
      final r = await cdp.send(
        'IndexedDB.requestDatabaseNames',
        params: <String, Object?>{'securityOrigin': origin},
        sessionId: _pageSessionId,
      );
      final list = r['databaseNames'] as List?;
      return list?.whereType<String>().toList() ?? const [];
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'listIndexedDbNames',
        error,
        stack,
      );
      return const [];
    }
  }

  /// `IndexedDB.requestDatabase` —— 拿单个 db 的 schema 摘要。
  /// 返回字段：(name, version, objectStores)。
  Future<({String name, int version, List<String> stores})?>
      describeIndexedDb(String dbName) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return null;
    try {
      final origin = await currentOrigin();
      if (origin == null) return null;
      final r = await cdp.send(
        'IndexedDB.requestDatabase',
        params: <String, Object?>{
          'securityOrigin': origin,
          'databaseName': dbName,
        },
        sessionId: _pageSessionId,
      );
      final db = r['databaseWithObjectStores'] as Map?;
      if (db == null) return null;
      final version = (db['version'] as num?)?.toInt() ?? 0;
      final stores = (db['objectStores'] as List?)
              ?.whereType<Map>()
              .map((m) => '${m['name'] ?? ''}')
              .toList(growable: false) ??
          const <String>[];
      return (name: dbName, version: version, stores: stores);
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'describeIndexedDb $dbName',
        error,
        stack,
      );
      return null;
    }
  }

  /// `IndexedDB.requestData` —— 读单个 object store 的前 N 条记录。
  /// 返回 (entries, hasMore)；entries 元素为 `{key, primaryKey, value}` 的纯 Map。
  Future<({List<Map<String, Object?>> entries, bool hasMore})?>
      readIndexedDbStore({
    required String dbName,
    required String storeName,
    int skipCount = 0,
    int pageSize = 50,
  }) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return null;
    try {
      final origin = await currentOrigin();
      if (origin == null) return null;
      final r = await cdp.send(
        'IndexedDB.requestData',
        params: <String, Object?>{
          'securityOrigin': origin,
          'databaseName': dbName,
          'objectStoreName': storeName,
          'indexName': '',
          'skipCount': skipCount,
          'pageSize': pageSize,
        },
        sessionId: _pageSessionId,
        timeout: const Duration(seconds: 10),
      );
      final list = r['objectStoreDataEntries'] as List?;
      final hasMore = r['hasMore'] == true;
      final entries = list
              ?.whereType<Map>()
              .map((m) => Map<String, Object?>.from(m))
              .toList(growable: false) ??
          const <Map<String, Object?>>[];
      return (entries: entries, hasMore: hasMore);
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'readIndexedDbStore $dbName/$storeName',
        error,
        stack,
      );
      return null;
    }
  }

  /// `CacheStorage.requestCacheNames` —— 当前 origin 下所有 Cache 名。
  Future<List<String>> listCacheStorage() async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return const [];
    try {
      final origin = await currentOrigin();
      if (origin == null) return const [];
      final r = await cdp.send(
        'CacheStorage.requestCacheNames',
        params: <String, Object?>{'securityOrigin': origin},
        sessionId: _pageSessionId,
      );
      final list = r['caches'] as List?;
      return list
              ?.whereType<Map>()
              .map((m) => '${m['cacheName'] ?? ''}')
              .where((n) => n.isNotEmpty)
              .toList(growable: false) ??
          const <String>[];
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'listCacheStorage',
        error,
        stack,
      );
      return const [];
    }
  }

  /// 注册 / 更新 / 卸载指定 Service Worker。
  /// `register` 走 `ServiceWorker.startRegistration`（接 scopeURL）；
  /// `update` 走 `ServiceWorker.updateRegistration`；
  /// `unregister` 走 `ServiceWorker.unregister`。
  Future<bool> registerServiceWorker(String scopeURL) async {
    final cdp = _browserCdp;
    if (cdp == null) return false;
    try {
      await cdp.send('ServiceWorker.enable');
      await cdp.send(
        'ServiceWorker.startRegistration',
        params: <String, Object?>{'scopeURL': scopeURL},
      );
      return true;
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', 'registerSW', error, stack);
      return false;
    }
  }

  Future<bool> updateServiceWorker(String scopeURL) async {
    final cdp = _browserCdp;
    if (cdp == null) return false;
    try {
      await cdp.send(
        'ServiceWorker.updateRegistration',
        params: <String, Object?>{'scopeURL': scopeURL},
      );
      return true;
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', 'updateSW', error, stack);
      return false;
    }
  }

  Future<bool> unregisterServiceWorker(String scopeURL) async {
    final cdp = _browserCdp;
    if (cdp == null) return false;
    try {
      await cdp.send(
        'ServiceWorker.unregister',
        params: <String, Object?>{'scopeURL': scopeURL},
      );
      return true;
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', 'unregisterSW', error, stack);
      return false;
    }
  }

  /// `ServiceWorker.deliverPushMessage` 不暴露——这里只列已注册的 worker。
  /// 数据来自 `ServiceWorker.workerVersionUpdated` 事件累积；这里同步发一次
  /// `ServiceWorker.enable` 触发首次推送。
  Future<List<Map<String, Object?>>> listServiceWorkers() async {
    final cdp = _browserCdp;
    if (cdp == null) return const [];
    final list = <Map<String, Object?>>[];
    StreamSubscription<CdpEvent>? sub;
    try {
      // 监听 30ms 收集；超过 250ms 强制 cut 防卡。
      sub = cdp.events.listen((e) {
        if (e.method == 'ServiceWorker.workerVersionUpdated') {
          final versions = e.params['versions'] as List?;
          if (versions == null) return;
          for (final v in versions.whereType<Map>()) {
            list.add(Map<String, Object?>.from(v));
          }
        }
      });
      await cdp.send('ServiceWorker.enable');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      // 去重（按 versionId）。
      final seen = <String>{};
      final dedup = <Map<String, Object?>>[];
      for (final v in list) {
        final id = '${v['versionId'] ?? ''}';
        if (id.isEmpty || seen.add(id)) dedup.add(v);
      }
      return dedup;
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'listServiceWorkers',
        error,
        stack,
      );
      return const [];
    } finally {
      await sub?.cancel();
    }
  }

  // ── Security ─────────────────────────────────────────────────────────

  String? _securityState;
  String? get securityState => _securityState;
  String? _securityExplanationsJson;
  String? get securityExplanationsJson => _securityExplanationsJson;

  Future<void> enableSecurity() async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return;
    try {
      await cdp.send('Security.enable', sessionId: _pageSessionId);
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', 'enableSecurity', error, stack);
    }
  }

  void _onSecurityStateChanged(Map<String, Object?> p) {
    _securityState = '${p['securityState'] ?? ''}';
    final explanations = p['explanations'];
    if (explanations != null) {
      _securityExplanationsJson = jsonEncode(explanations);
    }
    _safeNotify();
  }

  // ── Recorder（极简）──────────────────────────────────────────────────
  // 通过 addScriptToEvaluateOnNewDocument 注入轻量监听器，把 click / input /
  // navigate 等动作打到 console，再聚合为一份 step 列表。这是"够用版"，
  // Chrome DevTools Recorder 的可视化重放与高级断言用 webview/CEF 才能做。

  bool _recording = false;
  String? _recorderScriptIdentifier;
  final List<Map<String, Object?>> _recorderSteps = <Map<String, Object?>>[];
  List<Map<String, Object?>> get recorderSteps =>
      List<Map<String, Object?>>.unmodifiable(_recorderSteps);
  bool get isRecording => _recording;

  Future<void> startRecording() async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return;
    if (_recording) return;
    const recorderJs = r'''
(() => {
  if (window.__oh_recorder_installed) return;
  window.__oh_recorder_installed = true;
  // 悬浮指示条：固定页面右上角，永远不接收手势（pointer-events:none），
  // 仅视觉表示"OpenHand 正在录制"，并实时显示已记录步数。
  const overlay = document.createElement('div');
  overlay.id = '__oh_recorder_overlay';
  overlay.setAttribute('aria-hidden', 'true');
  overlay.style.cssText = [
    'position:fixed', 'top:12px', 'right:12px', 'z-index:2147483647',
    'pointer-events:none', 'user-select:none',
    'padding:6px 10px', 'border-radius:999px',
    'background:rgba(244,67,54,0.92)', 'color:#fff',
    'font:600 12px/1 -apple-system,Segoe UI,Roboto,sans-serif',
    'box-shadow:0 2px 12px rgba(0,0,0,.25)',
    'display:flex', 'align-items:center', 'gap:8px',
  ].join(';');
  const dot = document.createElement('span');
  dot.style.cssText = [
    'display:inline-block', 'width:8px', 'height:8px',
    'border-radius:50%', 'background:#fff',
    'box-shadow:0 0 0 0 rgba(255,255,255,.6)',
    'animation:__oh_rec_pulse 1.2s ease-in-out infinite',
  ].join(';');
  const label = document.createElement('span');
  label.textContent = 'REC · 0';
  overlay.appendChild(dot);
  overlay.appendChild(label);
  // 关键帧动画注入到 documentElement 以躲开 page CSP（多数 CSP 不挡 inline style）。
  const style = document.createElement('style');
  style.textContent = '@keyframes __oh_rec_pulse{0%{box-shadow:0 0 0 0 rgba(255,255,255,.65)}70%{box-shadow:0 0 0 12px rgba(255,255,255,0)}100%{box-shadow:0 0 0 0 rgba(255,255,255,0)}}';
  document.documentElement.appendChild(style);
  // 早期 Page.addScriptToEvaluateOnNewDocument 注入时 body 还没存在；用 MutationObserver 等。
  const attach = () => {
    if (document.body && !document.getElementById('__oh_recorder_overlay')) {
      document.body.appendChild(overlay);
    }
  };
  attach();
  if (!document.body) {
    new MutationObserver(attach).observe(document.documentElement, {childList:true, subtree:true});
  }
  let _stepCount = 0;
  window.__oh_rec_inc = () => {
    _stepCount++;
    label.textContent = 'REC · ' + _stepCount;
  };
  // 计算稳定 CSS 选择器：优先 #id，其次按 tag + nth-child 链向上回溯到 body。
  const buildSelector = (el) => {
    if (!el || el.nodeType !== 1) return null;
    if (el.id) return '#' + CSS.escape(el.id);
    const parts = [];
    let node = el;
    while (node && node.nodeType === 1 && node !== document.body && parts.length < 6) {
      const parent = node.parentNode;
      if (!parent) break;
      const sibs = Array.from(parent.children).filter(c => c.tagName === node.tagName);
      const nth = sibs.length === 1 ? '' : ':nth-of-type(' + (sibs.indexOf(node) + 1) + ')';
      parts.unshift(node.tagName.toLowerCase() + nth);
      node = parent;
    }
    return parts.length ? parts.join(' > ') : null;
  };
  const log = (step) => {
    try {
      console.log('__OH_REC__', JSON.stringify(step));
      if (window.__oh_rec_inc) window.__oh_rec_inc();
    } catch (_) {}
  };
  // 连击去抖：同一选择器在 350ms 内的重复点击合并为一条 step。
  // 既能压平用户双击 / 误连击，也保留真实"快速点两次"的语义（设置 doubleClick 标记）。
  let _lastClickAt = 0;
  let _lastClickSel = '';
  document.addEventListener('click', (ev) => {
    const t = ev.target;
    const sel = buildSelector(t);
    const now = Date.now();
    if (sel && sel === _lastClickSel && (now - _lastClickAt) < 350) {
      _lastClickAt = now;
      log({
        type: 'click',
        selector: sel,
        text: t && t.innerText ? String(t.innerText).slice(0, 60) : '',
        ts: now,
        doubleClick: true,
      });
      return;
    }
    _lastClickAt = now;
    _lastClickSel = sel || '';
    log({
      type: 'click',
      selector: sel,
      text: t && t.innerText ? String(t.innerText).slice(0, 60) : '',
      ts: now,
    });
  }, true);
  document.addEventListener('input', (ev) => {
    const t = ev.target;
    if (!t || !('value' in t)) return;
    // 智能去抖：连续 input 用 250ms 计时器合并；用户停手或失焦或回车提交时落帧。
    // 防止每个键击都打一条 step，让 replay 既快又稳。
    const sel = buildSelector(t);
    if (!sel) return;
    const key = '__oh_input_buf::' + sel;
    if (window[key]) clearTimeout(window[key]);
    const flush = () => {
      window[key] = null;
      log({
        type: 'input',
        selector: sel,
        value: String(t.value).slice(0, 200),
        ts: Date.now(),
      });
    };
    window[key] = setTimeout(flush, 250);
    // 一次性挂 blur / Enter，强制立刻 flush。
    if (!t.__oh_flushers) {
      t.__oh_flushers = true;
      t.addEventListener('blur', () => {
        if (window[key]) { clearTimeout(window[key]); flush(); }
      }, { once: true });
      t.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' && window[key]) { clearTimeout(window[key]); flush(); }
      });
    }
  }, true);
  document.addEventListener('change', (ev) => {
    const t = ev.target;
    if (t && (t.tagName === 'SELECT' || (t.type && /checkbox|radio/.test(t.type)))) {
      log({
        type: 'change',
        selector: buildSelector(t),
        value: t.tagName === 'SELECT' ? t.value :
               t.type === 'checkbox' ? !!t.checked :
               t.checked ? t.value : null,
        ts: Date.now(),
      });
    }
  }, true);
  window.addEventListener('hashchange', () => log({ type: 'navigate', url: location.href, ts: Date.now() }));
  window.addEventListener('popstate', () => log({ type: 'navigate', url: location.href, ts: Date.now() }));
  log({ type: 'navigate', url: location.href, ts: Date.now() });
  // 暴露断言录制 API：用户可在 console 里手动调用插入断言步骤。
  window.__oh_assert_text = (selector, expected) => {
    log({ type: 'assertText', selector, expected: String(expected || ''), ts: Date.now() });
  };
  window.__oh_assert_visible = (selector) => {
    log({ type: 'assertVisible', selector, ts: Date.now() });
  };
})();
''';
    try {
      final r = await cdp.send(
        'Page.addScriptToEvaluateOnNewDocument',
        params: <String, Object?>{'source': recorderJs},
        sessionId: _pageSessionId,
      );
      _recorderScriptIdentifier = r['identifier'] as String?;
      // 当前页面也立即注入一次。
      await cdp.send(
        'Runtime.evaluate',
        params: const <String, Object?>{'expression': recorderJs},
        sessionId: _pageSessionId,
      );
      _recorderSteps.clear();
      _recording = true;
      _safeNotify();
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', 'startRecording', error, stack);
    }
  }

  Future<void> stopRecording() async {
    final cdp = _browserCdp;
    if (!_recording) return;
    _recording = false;
    if (cdp != null && _recorderScriptIdentifier != null) {
      try {
        await cdp.send(
          'Page.removeScriptToEvaluateOnNewDocument',
          params: <String, Object?>{'identifier': _recorderScriptIdentifier},
          sessionId: _pageSessionId,
        );
      } catch (_) {}
      _recorderScriptIdentifier = null;
    }
    // 摘掉页面上的悬浮指示条；页面没卸载时 stop 后 overlay 仍可能挂着。
    if (cdp != null && _pageSessionId != null) {
      try {
        await cdp.send(
          'Runtime.evaluate',
          params: const <String, Object?>{
            'expression':
                '(()=>{const el=document.getElementById("__oh_recorder_overlay");if(el)el.remove();window.__oh_recorder_installed=false;window.__oh_rec_inc=null;})()',
          },
          sessionId: _pageSessionId,
        );
      } catch (_) {}
    }
    _safeNotify();
  }

  /// 把已录制的 step 序列在浏览器里按时间间隔重放：
  /// click / input / change 转为 Runtime.evaluate 模拟，navigate 转为 Page.navigate。
  /// 返回值为 (执行步数, 失败步数)。
  Future<({int executed, int failed})> replaySteps({
    Duration interStepDelay = const Duration(milliseconds: 300),
    Duration stepTimeout = const Duration(seconds: 5),
  }) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) {
      return (executed: 0, failed: 0);
    }
    final steps = _recorderSteps;
    if (steps.isEmpty) return (executed: 0, failed: 0);

    // 在执行真正交互前先等元素可见，避免 click 太快撞 DOM 还没渲染。
    // 5s 超时；轮询 100ms 一次；可见性 = 元素存在且 boundingClientRect.width|height > 0。
    Future<bool> waitForSelector(String selector) async {
      const expr = r'''
(async (sel, timeoutMs) => {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const el = document.querySelector(sel);
    if (el) {
      const r = el.getBoundingClientRect();
      if (r.width > 0 && r.height > 0) return true;
    }
    await new Promise(r => setTimeout(r, 100));
  }
  return false;
})''';
      final r = await _evalBool(
        '$expr(${jsonEncode(selector)}, 5000)',
        stepTimeout + const Duration(seconds: 6),
      );
      return r ?? false;
    }

    var executed = 0;
    var failed = 0;
    for (final step in steps) {
      final type = '${step['type'] ?? ''}';
      try {
        switch (type) {
          case 'navigate':
            final url = '${step['url'] ?? ''}';
            if (url.isNotEmpty) {
              await cdp.send(
                'Page.navigate',
                params: <String, Object?>{'url': url},
                sessionId: _pageSessionId,
                timeout: stepTimeout,
              );
            }
          case 'click':
            final selector = '${step['selector'] ?? ''}';
            if (selector.isEmpty) {
              failed++;
              continue;
            }
            await waitForSelector(selector);
            await _evalScript(
              '(() => { const el = document.querySelector(${jsonEncode(selector)}); '
              'if (!el) return false; el.scrollIntoView({block:"center"}); el.click(); return true; })()',
              stepTimeout,
            );
          case 'input':
            final selector = '${step['selector'] ?? ''}';
            final value = '${step['value'] ?? ''}';
            if (selector.isEmpty) {
              failed++;
              continue;
            }
            await waitForSelector(selector);
            await _evalScript(
              '(() => { const el = document.querySelector(${jsonEncode(selector)}); '
              'if (!el) return false; '
              'const v = ${jsonEncode(value)}; '
              'const proto = Object.getPrototypeOf(el); '
              'const setter = Object.getOwnPropertyDescriptor(proto, "value") && Object.getOwnPropertyDescriptor(proto, "value").set; '
              'if (setter) setter.call(el, v); else el.value = v; '
              'el.dispatchEvent(new Event("input", {bubbles: true})); '
              'el.dispatchEvent(new Event("change", {bubbles: true})); return true; })()',
              stepTimeout,
            );
          case 'change':
            final selector = '${step['selector'] ?? ''}';
            final value = step['value'];
            if (selector.isEmpty) {
              failed++;
              continue;
            }
            await waitForSelector(selector);
            await _evalScript(
              '(() => { const el = document.querySelector(${jsonEncode(selector)}); '
              'if (!el) return false; '
              'const v = ${jsonEncode(value)}; '
              'if (el.tagName === "SELECT") { el.value = v; } '
              'else if (el.type === "checkbox") { el.checked = !!v; } '
              'el.dispatchEvent(new Event("change", {bubbles: true})); return true; })()',
              stepTimeout,
            );
          case 'assertText':
            final selector = '${step['selector'] ?? ''}';
            final expected = '${step['expected'] ?? ''}';
            if (selector.isEmpty) {
              failed++;
              continue;
            }
            final ok = await _evalBool(
              '(() => { const el = document.querySelector(${jsonEncode(selector)}); '
              'if (!el) return false; '
              'const text = String(el.innerText || el.textContent || ""); '
              'return text.includes(${jsonEncode(expected)}); })()',
              stepTimeout,
            );
            if (ok != true) {
              failed++;
              continue;
            }
          case 'assertVisible':
            final selector = '${step['selector'] ?? ''}';
            if (selector.isEmpty) {
              failed++;
              continue;
            }
            final ok = await _evalBool(
              '(() => { const el = document.querySelector(${jsonEncode(selector)}); '
              'if (!el) return false; '
              'const r = el.getBoundingClientRect(); '
              'const style = getComputedStyle(el); '
              'return r.width > 0 && r.height > 0 && style.visibility !== "hidden" && style.display !== "none" && Number(style.opacity) > 0; })()',
              stepTimeout,
            );
            if (ok != true) {
              failed++;
              continue;
            }
          default:
            // 未识别的步骤直接计为失败，但不阻断后续。
            failed++;
            continue;
        }
        executed++;
      } catch (error, stack) {
        failed++;
        silentLog(
          'web_reverse_session_controller',
          'replay step $type',
          error,
          stack,
        );
      }
      await Future<void>.delayed(interStepDelay);
    }
    return (executed: executed, failed: failed);
  }

  Future<void> _evalScript(String expression, Duration timeout) async {
    final cdp = _browserCdp;
    if (cdp == null) return;
    await cdp.send(
      'Runtime.evaluate',
      params: <String, Object?>{
        'expression': expression,
        'awaitPromise': true,
        'returnByValue': true,
      },
      sessionId: _pageSessionId,
      timeout: timeout,
    );
  }

  /// 类似 [_evalScript]，但同步取 expression 求值结果（returnByValue）的 bool。
  Future<bool?> _evalBool(String expression, Duration timeout) async {
    final cdp = _browserCdp;
    if (cdp == null) return null;
    try {
      final r = await cdp.send(
        'Runtime.evaluate',
        params: <String, Object?>{
          'expression': expression,
          'returnByValue': true,
        },
        sessionId: _pageSessionId,
        timeout: timeout,
      );
      final v = (r['result'] as Map?)?['value'];
      return v is bool ? v : null;
    } catch (_) {
      return null;
    }
  }

  /// 把一条断言追加到 _recorderSteps（让 UI 直接添加，不依赖浏览器 console）。
  void addAssertionStep(String type, {required String selector, String? expected}) {
    _recorderSteps.add(<String, Object?>{
      'type': type,
      'selector': selector,
      if (expected != null) 'expected': expected,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
    _safeNotify();
  }

  /// 替换当前 step 列表（导入 JSON 用）。
  void setRecorderSteps(List<Map<String, Object?>> steps) {
    _recorderSteps
      ..clear()
      ..addAll(steps);
    _safeNotify();
  }

  /// 清空 step 列表。
  void clearRecorderSteps() {
    _recorderSteps.clear();
    _safeNotify();
  }

  void _onRequestWillBeSent(Map<String, Object?> p) {
    final requestId = '${p['requestId']}';
    final request = p['request'] as Map?;
    if (request == null) return;
    final url = '${request['url'] ?? ''}';
    final method = '${request['method'] ?? 'GET'}';
    final headers = _flattenHeaders(request['headers']);
    // 同一个 requestId 出现重定向时，CDP 会再次发 requestWillBeSent 并带上
    // `redirectResponse`（前一次响应的状态/URL/headers）。把它累加到 chain
    // 里给前端的 Initiator → Request Initiator Chain 区段展示，对齐 Chrome
    // DevTools。重定向链按时间顺序：[第1跳响应, 第2跳响应, …, 当前请求前
    // 一跳]，再加上"当前请求"自己。
    final existing = _networkByRequestId[requestId];
    final redirect = p['redirectResponse'] as Map?;
    CdpNetworkEntry entry;
    if (existing != null && redirect != null) {
      entry = existing
        ..url = url
        ..method = method
        ..requestHeaders = headers
        ..requestPostData = request['postData'] as String?;
      entry.redirectChain.add(CdpRedirectStep(
        url: '${redirect['url'] ?? ''}',
        status: (redirect['status'] as num?)?.toInt(),
        statusText: redirect['statusText'] as String?,
        responseHeaders: _flattenHeaders(redirect['headers']),
        at: DateTime.now(),
      ));
    } else {
      entry = CdpNetworkEntry(
        requestId: requestId,
        url: url,
        method: method,
        timestamp: DateTime.now(),
        resourceType: '${p['type'] ?? 'Other'}',
      )
        ..requestHeaders = headers
        ..requestPostData = request['postData'] as String?;
    }
    final initiator = p['initiator'] as Map?;
    if (initiator != null) {
      entry.initiatorType = initiator['type'] as String?;
      entry.initiatorUrl = initiator['url'] as String?;
      entry.initiatorLineNumber = (initiator['lineNumber'] as num?)?.toInt();
      entry.initiatorColumnNumber =
          (initiator['columnNumber'] as num?)?.toInt();
      final stack = initiator['stack'] as Map?;
      final frames = stack?['callFrames'] as List?;
      if (frames != null) {
        entry.initiatorStack = frames
            .whereType<Map>()
            .map((f) => Map<String, Object?>.from(f))
            .toList(growable: false);
      }
    }
    if (existing == null) {
      _networkByRequestId[requestId] = entry;
      _networkRequests.add(entry);
      while (_networkRequests.length > _maxNetworkEntries) {
        final old = _networkRequests.removeAt(0);
        _networkByRequestId.remove(old.requestId);
      }
    }
    _artifacts
      ..appendNetwork(<String, Object?>{
        'kind': 'request',
        'request_id': requestId,
        'url': url,
        'method': method,
        'ts': entry.timestamp.toUtc().toIso8601String(),
      })
      ..recordHarRequest(
        requestId: requestId,
        url: url,
        method: method,
        headers: Map<String, Object?>.from(headers),
        postData: entry.requestPostData,
        startedAt: entry.timestamp,
      );
    _safeNotify();
  }

  void _onResponseReceived(Map<String, Object?> p) {
    final requestId = '${p['requestId']}';
    final response = p['response'] as Map?;
    if (response == null) return;
    final entry = _networkByRequestId[requestId];
    if (entry == null) return;
    final status = (response['status'] as num?)?.toInt();
    final mime = '${response['mimeType'] ?? ''}';
    final headers = _flattenHeaders(response['headers']);
    entry
      ..statusCode = status
      ..statusText = response['statusText'] as String?
      ..mimeType = mime
      ..responseHeaders = headers
      ..remoteAddress = _formatRemoteAddress(response)
      ..protocol = response['protocol'] as String?
      ..encodedDataLength = (response['encodedDataLength'] as num?)?.toInt()
      ..fromCache = response['fromDiskCache'] == true ||
          response['fromMemoryCache'] == true ||
          response['fromServiceWorker'] == true
      ..responseReceivedAt = DateTime.now();
    // CDP `Network.ResourceTiming` 提供 Chrome 风格的阶段瀑布数据：
    // requestTime / proxyStart-End / dnsStart-End / connectStart-End /
    // sslStart-End / sendStart-End / receiveHeadersEnd 等。除 requestTime
    // 单位是单调时钟秒外，其余字段都是相对 requestTime 的毫秒偏移。
    final timing = response['timing'];
    if (timing is Map) {
      final snapshot = <String, num>{};
      timing.forEach((k, v) {
        if (v is num) snapshot['$k'] = v;
      });
      if (snapshot.isNotEmpty) entry.resourceTiming = snapshot;
    }
    _artifacts
      ..appendNetwork(<String, Object?>{
        'kind': 'response',
        'request_id': requestId,
        'status': status,
        'mime': mime,
        'from_cache': entry.fromCache,
        'ts': DateTime.now().toUtc().toIso8601String(),
      })
      ..recordHarResponse(
        requestId: requestId,
        status: status ?? 0,
        statusText: '${response['statusText'] ?? ''}',
        mimeType: mime,
        headers: Map<String, Object?>.from(headers),
        bodySize: entry.encodedDataLength,
      );
    _safeNotify();
  }

  void _onLoadingFailed(Map<String, Object?> p) {
    final requestId = '${p['requestId']}';
    final entry = _networkByRequestId[requestId];
    if (entry == null) return;
    final err = '${p['errorText'] ?? 'failed'}';
    entry.failed = true;
    entry.errorText = err;
    entry.loadingFinishedAt = DateTime.now();
    _artifacts
      ..appendNetwork(<String, Object?>{
        'kind': 'failed',
        'request_id': requestId,
        'error': err,
        'ts': DateTime.now().toUtc().toIso8601String(),
      })
      ..recordHarFailed(requestId, err, DateTime.now());
    _safeNotify();
  }

  void _onLoadingFinished(Map<String, Object?> p) {
    final requestId = '${p['requestId']}';
    final entry = _networkByRequestId[requestId];
    if (entry == null) return;
    entry.loadingFinishedAt = DateTime.now();
    final encoded = (p['encodedDataLength'] as num?)?.toInt();
    if (encoded != null) entry.encodedDataLength = encoded;
    _artifacts.recordHarFinished(requestId, DateTime.now());
    _safeNotify();
  }

  void _onWebSocketCreated(Map<String, Object?> p) {
    final requestId = '${p['requestId']}';
    if (_networkByRequestId.containsKey(requestId)) return;
    final url = '${p['url'] ?? ''}';
    final entry = CdpNetworkEntry(
      requestId: requestId,
      url: url,
      method: 'GET',
      timestamp: DateTime.now(),
      resourceType: 'WebSocket',
    );
    _networkByRequestId[requestId] = entry;
    _networkRequests.add(entry);
    while (_networkRequests.length > _maxNetworkEntries) {
      final old = _networkRequests.removeAt(0);
      _networkByRequestId.remove(old.requestId);
    }
    _safeNotify();
  }

  void _onWebSocketFrame(
    Map<String, Object?> p,
    CdpWebSocketDirection direction,
  ) {
    final requestId = '${p['requestId']}';
    final entry = _networkByRequestId[requestId];
    if (entry == null) return;
    final response = p['response'] as Map?;
    final opcode = (response?['opcode'] as num?)?.toInt() ?? 0;
    final mask = response?['mask'] == true;
    var payload = '${response?['payloadData'] ?? ''}';
    if (payload.length > 8192) payload = '${payload.substring(0, 8192)}…';
    entry.wsFrames.add(CdpWebSocketFrame(
      direction: direction,
      timestamp: DateTime.now(),
      opcode: opcode,
      mask: mask,
      payload: payload,
      errorMessage: direction == CdpWebSocketDirection.error
          ? '${p['errorMessage'] ?? ''}'
          : null,
    ));
    // 防止单条 WS 累积爆炸。
    while (entry.wsFrames.length > 2000) {
      entry.wsFrames.removeAt(0);
    }
    _artifacts.appendNetwork(<String, Object?>{
      'kind': 'ws_${direction.name}',
      'request_id': requestId,
      'opcode': opcode,
      'mask': mask,
      'payload_preview': payload.length > 256
          ? '${payload.substring(0, 256)}…'
          : payload,
      'ts': DateTime.now().toUtc().toIso8601String(),
    });
    _safeNotify();
  }

  void _onFrameNavigated(Map<String, Object?> p) {
    // 仅主 frame 导航才触发 Preserve log 联动；子 frame / iframe 忽略。
    final frame = p['frame'] as Map?;
    if (frame == null) return;
    if (frame['parentId'] != null) return;
    final url = '${frame['url'] ?? ''}';
    if (url.isNotEmpty && !url.startsWith('chrome-error://')) {
      // 维护本会话访问历史：去掉相邻重复，最多保留最近 200 条。
      if (_navigationHistory.isEmpty || _navigationHistory.last != url) {
        _navigationHistory.add(url);
        while (_navigationHistory.length > 200) {
          _navigationHistory.removeAt(0);
        }
      }
    }
    if (!_preserveLog) {
      _networkRequests.clear();
      _networkByRequestId.clear();
      _safeNotify();
    }
    // 顶层 frame 导航完成后，主动拉一次 document.title 更新对应 page target，
    // 因为 CDP `Target.targetInfoChanged` 在 SPA / pushState 场景往往不会带新
    // title 抵达。这里延迟一帧调度，等页面 onload 把 <title> 渲染上去。
    final targetId = _currentTargetId;
    if (targetId != null && targetId.isNotEmpty) {
      unawaited(_refreshPageTitle(targetId));
    }
  }

  /// 通过 page session 的 `Runtime.evaluate('document.title')` 拉取最新标题，
  /// 并写回 `_pageTargets` 对应 entry；失败静默。重复调用安全（无 title
  /// 变化时不 notify）。
  Future<void> _refreshPageTitle(String targetId) async {
    final cdp = _browserCdp;
    final sid = _pageSessionId;
    if (cdp == null || sid == null) return;
    try {
      final r = await cdp.send(
        'Runtime.evaluate',
        params: {
          'expression': 'document.title',
          'returnByValue': true,
        },
        sessionId: sid,
      );
      final result = r['result'] as Map?;
      final value = result?['value'];
      if (value is! String) return;
      final title = value.trim();
      if (title.isEmpty) return;
      final idx = _pageTargets.indexWhere((e) => e.id == targetId);
      if (idx < 0) return;
      if (_pageTargets[idx].title == title) return;
      final prev = _pageTargets[idx];
      _pageTargets[idx] = CdpPageTargetSnapshot(
        id: prev.id,
        url: prev.url,
        title: title,
      );
      _safeNotify();
    } catch (e, st) {
      silentLog('web_reverse', '_refreshPageTitle', e, st);
    }
  }

  /// 本会话内主 frame 访问过的 URL 序列（按时间顺序，相邻去重）。
  /// dashboard 浏览器面板地址栏的历史下拉就读这个。
  final List<String> _navigationHistory = <String>[];
  List<String> get navigationHistory =>
      List<String>.unmodifiable(_navigationHistory);

  void _onTargetUpserted(Map<String, Object?> p) {
    final t = p['targetInfo'] as Map?;
    if (t == null) return;
    if ('${t['type'] ?? ''}' != 'page') return;
    final id = '${t['targetId'] ?? ''}';
    if (id.isEmpty) return;
    final url = '${t['url'] ?? ''}';
    final title = '${t['title'] ?? ''}';
    final idx = _pageTargets.indexWhere((e) => e.id == id);
    if (idx < 0) {
      _pageTargets.add(CdpPageTargetSnapshot(id: id, url: url, title: title));
    } else {
      _pageTargets[idx] = CdpPageTargetSnapshot(id: id, url: url, title: title);
    }
    _safeNotify();
  }

  void _onTargetDestroyed(Map<String, Object?> p) {
    final id = '${p['targetId'] ?? ''}';
    if (id.isEmpty) return;
    final before = _pageTargets.length;
    _pageTargets.removeWhere((e) => e.id == id);
    if (_pageTargets.length != before) {
      if (id == _currentTargetId && _pageTargets.isNotEmpty) {
        unawaited(switchToPageTarget(_pageTargets.first.id));
      }
      _safeNotify();
    }
  }

  /// CDP `Page.screencastFrame` 事件回调。每帧到达后必须立刻 ack，
  /// 否则浏览器会停止推帧；同时只保留最新一帧 + 自增帧号让 widget 重绘。
  void _onScreencastFrame(Map<String, Object?> p) {
    final data = p['data'] as String?;
    final sessionId = p['sessionId'];
    if (data != null && data.isNotEmpty) {
      try {
        _latestScreencastFrame = base64Decode(data);
        _screencastFrameSeq++;
        _lastScreencastFrameAt = DateTime.now();
        final meta = p['metadata'] as Map?;
        final w = (meta?['deviceWidth'] as num?)?.round();
        final h = (meta?['deviceHeight'] as num?)?.round();
        var viewportChanged = false;
        if (w != null && w > 0 && w != _screencastWidth) {
          _screencastWidth = w;
          viewportChanged = true;
        }
        if (h != null && h > 0 && h != _screencastHeight) {
          _screencastHeight = h;
          viewportChanged = true;
        }
        // 帧自增推到细粒度 notifier；只有 viewport 变化才唤醒主 listener。
        if (!_disposed) screencastFrameNotifier.value = _screencastFrameSeq;
        if (viewportChanged) _safeNotify();
      } catch (error, stack) {
        silentLog(
          'web_reverse_session_controller',
          'decode screencast frame',
          error,
          stack,
        );
      }
    }
    // ack 必须发送，且要带回原 sessionId。即便帧解码失败也要 ack，否则
    // 浏览器会卡住整个 screencast 流。
    final cdp = _browserCdp;
    if (cdp != null && _pageSessionId != null && sessionId is num) {
      unawaited(
        cdp
            .send(
              'Page.screencastFrameAck',
              params: <String, Object?>{'sessionId': sessionId.toInt()},
              sessionId: _pageSessionId,
              timeout: const Duration(seconds: 3),
            )
            .catchError((_) => <String, Object?>{}),
      );
    }
  }

  static Map<String, String> _flattenHeaders(Object? raw) {
    if (raw is! Map) return const <String, String>{};
    final out = <String, String>{};
    for (final entry in raw.entries) {
      out['${entry.key}'] = '${entry.value}';
    }
    return out;
  }

  static String? _formatRemoteAddress(Map response) {
    final ip = response['remoteIPAddress'];
    final port = response['remotePort'];
    if (ip == null) return null;
    if (port == null) return '$ip';
    return '$ip:$port';
  }

  void _onConsoleApi(Map<String, Object?> p) {
    final type = '${p['type'] ?? 'log'}';
    final args = p['args'] as List? ?? const <Object?>[];
    final text = args.whereType<Map>().map((a) {
      final v = a['value'];
      return v == null ? (a['description'] ?? '').toString() : v.toString();
    }).join(' ');
    // 拦截 recorder 标记，转为 step 列表（不影响 console 列表本身）。
    if (_recording && text.startsWith('__OH_REC__ ')) {
      try {
        final raw = text.substring('__OH_REC__ '.length).trim();
        // 去掉首尾可能的引号，再 JSON.decode。
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _recorderSteps.add(Map<String, Object?>.from(decoded));
          _safeNotify();
        }
      } catch (_) {}
    }
    _appendConsole(type, text);
  }

  void _onLogEntry(Map<String, Object?> p) {
    final entry = p['entry'] as Map?;
    if (entry == null) return;
    final level = '${entry['level'] ?? 'info'}';
    final text = '${entry['text'] ?? ''}';
    _appendConsole(level, text);
  }

  /// 4 秒一跳的浏览器存活探针：HTTP GET `/json/version`。任一探测失败立刻
  /// 把 `_browserCdp` 标记为已关闭并触发 `__cdp_dead__` 事件，让 UI 走到
  /// "重启浏览器" 占位。WebSocket 自身的 onDone 会更早触发，这里是兜底。
  void _startAliveWatchdog() {
    _stopAliveWatchdog();
    _aliveWatchdog = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_stopped || _disposed) return;
      final port = _launchResult?.cdpPort;
      if (port == null) return;
      final cdp = _browserCdp;
      if (cdp == null || cdp.isClosed) return;
      final client = HttpClient();
      client.findProxy = (_) => 'DIRECT';
      client.connectionTimeout = const Duration(seconds: 1);
      try {
        final req = await client
            .getUrl(Uri.parse('http://127.0.0.1:$port/json/version'))
            .timeout(const Duration(seconds: 1));
        final res = await req.close().timeout(const Duration(seconds: 1));
        await res.drain<void>();
      } catch (_) {
        // 浏览器已死：主动关 CDP 触发 __cdp_dead__ 事件路径。
        _stopAliveWatchdog();
        try {
          await _browserCdp?.close();
        } catch (_) {}
        if (_screencastActive) {
          _screencastActive = false;
          _latestScreencastFrame = null;
          _screencastFrameSeq = 0;
          if (!_disposed) {
            screencastFrameNotifier.value = screencastFrameNotifier.value + 1;
          }
        }
        _errorMessage = '浏览器已断开（进程异常退出），可点击「重启浏览器」恢复。';
        _safeNotify();
      } finally {
        client.close(force: true);
      }
    });
  }

  void _stopAliveWatchdog() {
    _aliveWatchdog?.cancel();
    _aliveWatchdog = null;
  }

  /// CDP 重连成功后调用：把 Page / Network / Runtime / Log 等 domain 重新 enable，
  /// 同时再次 attach 到 page target，确保事件不丢。
  Future<void> _reattachAfterReconnect() async {
    final cdp = _browserCdp;
    if (cdp == null) return;
    try {
      // 重新 attach；CDP 重连后 sessionId 失效。
      await _attachToFirstPage();
      // 把"已选好的"用户配置重新下发给浏览器：节流 / 持久 Header / 屏蔽 URL / 拦截开关。
      if (_extraHeaders.isNotEmpty) {
        await cdp.send(
          'Network.setExtraHTTPHeaders',
          params: <String, Object?>{'headers': _extraHeaders},
          sessionId: _pageSessionId,
        );
      }
      if (_blockedUrls.isNotEmpty) {
        await cdp.send(
          'Network.setBlockedURLs',
          params: <String, Object?>{'urls': _blockedUrls.toList()},
          sessionId: _pageSessionId,
        );
      }
      // 内嵌浏览器 widget 仍处于激活状态时，要把 screencast 拉起来续上画面。
      if (_screencastActive || _screencastRefCount > 0) {
        try {
          await cdp.send(
            'Page.startScreencast',
            params: <String, Object?>{
              'format': 'jpeg',
              'quality': _screencastQuality,
              'maxWidth': _screencastWidth,
              'maxHeight': _screencastHeight,
              'everyNthFrame': 1,
            },
            sessionId: _pageSessionId,
          );
          _screencastActive = true;
        } catch (_) {}
      }
      _appendConsole('info', '[OpenHand] CDP 已自动重连，已恢复网络 / 控制台监听');
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '_reattachAfterReconnect',
          error, stack);
    }
  }

  void _appendConsole(String level, String text) {
    final ts = DateTime.now();
    _consoleMessages.add(
      CdpConsoleEntry(level: level, text: text, timestamp: ts),
    );
    while (_consoleMessages.length > _maxConsoleEntries) {
      _consoleMessages.removeAt(0);
    }
    _artifacts.appendConsole(<String, Object?>{
      'level': level,
      'text': text,
      'ts': ts.toUtc().toIso8601String(),
    });
    _safeNotify();
  }

  /// Console REPL：把表达式喂给 page 的 Runtime.evaluate，
  /// REPL 命令历史，按时间顺序追加；UI 上下箭头浏览历史。
  /// 重启 dashboard / 切会话不丢，由 dashboard 侧把它持久化到 session metadata。
  final List<String> _replHistory = <String>[];
  static const int _kReplHistoryMax = 200;
  List<String> get replHistory => List<String>.unmodifiable(_replHistory);

  void pushReplHistory(String expr) {
    final t = expr.trim();
    if (t.isEmpty) return;
    if (_replHistory.isNotEmpty && _replHistory.last == t) return;
    _replHistory.add(t);
    while (_replHistory.length > _kReplHistoryMax) {
      _replHistory.removeAt(0);
    }
    _safeNotify();
  }

  void replaceReplHistory(List<String> items) {
    _replHistory
      ..clear()
      ..addAll(items.where((e) => e.trim().isNotEmpty));
    _safeNotify();
  }

  // ─── 脚本注入库 (Snippet Pad) ────────────────────────────────────────
  // 用户在「脚本」tab 创建的 JS 代码片段；执行时直接复用 [runReplExpression]，
  // 持久化由 dashboard 写入 session metadata。
  final List<WebReverseSnippet> _snippets = <WebReverseSnippet>[];
  List<WebReverseSnippet> get snippets => List.unmodifiable(_snippets);

  void replaceSnippets(List<WebReverseSnippet> items) {
    _snippets
      ..clear()
      ..addAll(items);
    _safeNotify();
  }

  WebReverseSnippet addSnippet({required String name, required String code}) {
    final id = 'snip_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    final s = WebReverseSnippet(
      id: id,
      name: name.trim().isEmpty ? 'untitled' : name.trim(),
      code: code,
      updatedAt: DateTime.now(),
    );
    _snippets.add(s);
    _safeNotify();
    return s;
  }

  void updateSnippet({
    required String id,
    String? name,
    String? code,
  }) {
    final i = _snippets.indexWhere((e) => e.id == id);
    if (i < 0) return;
    final old = _snippets[i];
    _snippets[i] = WebReverseSnippet(
      id: old.id,
      name: (name ?? old.name).trim().isEmpty ? old.name : (name ?? old.name).trim(),
      code: code ?? old.code,
      updatedAt: DateTime.now(),
    );
    _safeNotify();
  }

  void removeSnippet(String id) {
    final i = _snippets.indexWhere((e) => e.id == id);
    if (i < 0) return;
    _snippets.removeAt(i);
    _safeNotify();
  }

  /// 执行 snippet：直接走 REPL 通道，结果写入 Console 面板供回看。
  Future<String?> runSnippet(String id) async {
    final s = _snippets.firstWhere(
      (e) => e.id == id,
      orElse: () => const WebReverseSnippet(
        id: '', name: '', code: '', updatedAt: null,
      ),
    );
    if (s.id.isEmpty) return null;
    return runReplExpression(s.code);
  }

  // ─── JS Hook 库 (Hooks Pad) ─────────────────────────────────────────
  // 用户 Hook 脚本通过 Page.addScriptToEvaluateOnNewDocument 注入，在每个
  // 文档加载前执行：patch 全局对象 / 改写 fetch / 装载调试钩子。enabled 切换
  // 即装载/卸载；切换 target 时所有 enabled hook 自动重装。持久化由 dashboard
  // 写入 session metadata。
  final List<WebReverseHook> _hooks = <WebReverseHook>[];
  final Map<String, String> _hookCdpScriptId = <String, String>{};

  List<WebReverseHook> get hooks => List.unmodifiable(_hooks);

  Future<void> replaceHooks(List<WebReverseHook> items) async {
    for (final old in List<WebReverseHook>.from(_hooks)) {
      await _uninstallHook(old.id);
    }
    _hooks
      ..clear()
      ..addAll(items);
    for (final h in _hooks.where((e) => e.enabled)) {
      await _installHook(h);
    }
    _safeNotify();
  }

  Future<WebReverseHook> addHook({
    required String name,
    required String code,
  }) async {
    final id =
        'hook_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    final h = WebReverseHook(
      id: id,
      name: name.trim().isEmpty ? 'untitled' : name.trim(),
      code: code,
      enabled: true,
      updatedAt: DateTime.now(),
    );
    _hooks.add(h);
    await _installHook(h);
    _safeNotify();
    return h;
  }

  Future<void> updateHook({
    required String id,
    String? name,
    String? code,
  }) async {
    final i = _hooks.indexWhere((e) => e.id == id);
    if (i < 0) return;
    final old = _hooks[i];
    final next = WebReverseHook(
      id: old.id,
      name: (name ?? old.name).trim().isEmpty
          ? old.name
          : (name ?? old.name).trim(),
      code: code ?? old.code,
      enabled: old.enabled,
      updatedAt: DateTime.now(),
    );
    _hooks[i] = next;
    if (next.enabled) {
      await _uninstallHook(id);
      await _installHook(next);
    }
    _safeNotify();
  }

  Future<void> setHookEnabled(String id, bool enabled) async {
    final i = _hooks.indexWhere((e) => e.id == id);
    if (i < 0) return;
    final old = _hooks[i];
    _hooks[i] = WebReverseHook(
      id: old.id,
      name: old.name,
      code: old.code,
      enabled: enabled,
      updatedAt: DateTime.now(),
    );
    if (enabled) {
      await _installHook(_hooks[i]);
    } else {
      await _uninstallHook(id);
    }
    _safeNotify();
  }

  Future<void> removeHook(String id) async {
    await _uninstallHook(id);
    _hooks.removeWhere((e) => e.id == id);
    _safeNotify();
  }

  Future<void> _reapplyEnabledHooks() async {
    _hookCdpScriptId.clear();
    for (final h in _hooks.where((e) => e.enabled)) {
      await _installHook(h);
    }
  }

  Future<void> _installHook(WebReverseHook h) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return;
    try {
      final r = await cdp.send(
        'Page.addScriptToEvaluateOnNewDocument',
        params: <String, Object?>{'source': h.code},
        sessionId: _pageSessionId,
        timeout: const Duration(seconds: 5),
      );
      final sid = r['identifier'];
      if (sid is String) _hookCdpScriptId[h.id] = sid;
    } catch (e, st) {
      silentLog(
          'web_reverse_session_controller', 'installHook ${h.name}', e, st);
    }
  }

  Future<void> _uninstallHook(String id) async {
    final cdp = _browserCdp;
    final sid = _hookCdpScriptId.remove(id);
    if (cdp == null || _pageSessionId == null || sid == null) return;
    try {
      await cdp.send(
        'Page.removeScriptToEvaluateOnNewDocument',
        params: <String, Object?>{'identifier': sid},
        sessionId: _pageSessionId,
        timeout: const Duration(seconds: 5),
      );
    } catch (e, st) {
      silentLog('web_reverse_session_controller', 'uninstallHook', e, st);
    }
  }

  // ─── 定时任务 (Crons) ─────────────────────────────────────────────────
  // 周期性运行一段 JS：心跳脚本、轮询接口、固定 1 分钟点一下登录续期按钮。
  // 与 hook 不同——它不在文档加载时跑，而是按 intervalSeconds 节拍跑；
  // 关 dashboard 不停。dispose / replaceCrons 一定要 cancel 所有 Timer。
  final List<WebReverseCron> _crons = <WebReverseCron>[];
  final Map<String, Timer> _cronTimers = <String, Timer>{};
  final Map<String, DateTime> _cronLastRun = <String, DateTime>{};

  List<WebReverseCron> get crons => List.unmodifiable(_crons);

  /// 最近一次成功跑完的时刻（UI 显示「上次执行 X 秒前」用）。
  DateTime? cronLastRunAt(String id) => _cronLastRun[id];

  Future<void> replaceCrons(List<WebReverseCron> items) async {
    for (final t in _cronTimers.values) {
      t.cancel();
    }
    _cronTimers.clear();
    _crons
      ..clear()
      ..addAll(items);
    for (final c in _crons.where((e) => e.enabled)) {
      _scheduleCron(c);
    }
    _safeNotify();
  }

  Future<WebReverseCron> addCron({
    required String name,
    required String code,
    required int intervalSeconds,
  }) async {
    final id =
        'cron_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    final c = WebReverseCron(
      id: id,
      name: name.trim().isEmpty ? 'untitled' : name.trim(),
      code: code,
      intervalSeconds: intervalSeconds < 1 ? 1 : intervalSeconds,
      enabled: true,
      updatedAt: DateTime.now(),
    );
    _crons.add(c);
    _scheduleCron(c);
    _safeNotify();
    return c;
  }

  Future<void> updateCron({
    required String id,
    String? name,
    String? code,
    int? intervalSeconds,
  }) async {
    final i = _crons.indexWhere((e) => e.id == id);
    if (i < 0) return;
    final old = _crons[i];
    final next = WebReverseCron(
      id: old.id,
      name: (name ?? old.name).trim().isEmpty
          ? old.name
          : (name ?? old.name).trim(),
      code: code ?? old.code,
      intervalSeconds: () {
        final v = intervalSeconds ?? old.intervalSeconds;
        return v < 1 ? 1 : v;
      }(),
      enabled: old.enabled,
      updatedAt: DateTime.now(),
    );
    _crons[i] = next;
    if (next.enabled) {
      _cronTimers.remove(id)?.cancel();
      _scheduleCron(next);
    }
    _safeNotify();
  }

  Future<void> setCronEnabled(String id, bool enabled) async {
    final i = _crons.indexWhere((e) => e.id == id);
    if (i < 0) return;
    final old = _crons[i];
    _crons[i] = WebReverseCron(
      id: old.id,
      name: old.name,
      code: old.code,
      intervalSeconds: old.intervalSeconds,
      enabled: enabled,
      updatedAt: DateTime.now(),
    );
    if (enabled) {
      _scheduleCron(_crons[i]);
    } else {
      _cronTimers.remove(id)?.cancel();
    }
    _safeNotify();
  }

  Future<void> removeCron(String id) async {
    _cronTimers.remove(id)?.cancel();
    _cronLastRun.remove(id);
    _crons.removeWhere((e) => e.id == id);
    _safeNotify();
  }

  /// 立即手动触发一次（不影响周期定时）。
  Future<String?> runCronNow(String id) async {
    final c = _crons.firstWhere(
      (e) => e.id == id,
      orElse: () => const WebReverseCron(
        id: '', name: '', code: '', intervalSeconds: 0, enabled: false,
        updatedAt: null,
      ),
    );
    if (c.id.isEmpty) return null;
    return _executeCronOnce(c);
  }

  void _scheduleCron(WebReverseCron c) {
    final dur = Duration(seconds: c.intervalSeconds);
    _cronTimers[c.id] = Timer.periodic(dur, (_) {
      // 不 await——失败由 _executeCronOnce 内部吞掉，避免一次错误打死定时器。
      unawaited(_executeCronOnce(c));
    });
  }

  Future<String?> _executeCronOnce(WebReverseCron c) async {
    try {
      final r = await runReplExpression(c.code);
      _cronLastRun[c.id] = DateTime.now();
      _safeNotify();
      return r;
    } catch (e, st) {
      silentLog('web_reverse_session_controller', 'cron ${c.name}', e, st);
      return null;
    }
  }

  // ─── DOM Inspector (Elements 面板) ───────────────────────────────────
  // 直接走 CDP `DOM.*` / `CSS.*` / `DOMDebugger.*` 协议；所有方法返回
  // 解码后的原始 JSON（Map / List），上层 UI 自己拼树。无副作用，不持
  // 久化。失败统一返回 null / 空集合并写一行 console error 便于排查。

  /// `DOM.getDocument` — 拿到当前页面 root node（一次性 depth 控制深度，
  /// -1 表示完整树，但对大页面会卡，默认 2 层；UI 用 lazy expand 补深度）。
  Future<Map<String, dynamic>?> domGetDocument({int depth = 2}) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return null;
    try {
      final r = await cdp.send(
        'DOM.getDocument',
        params: <String, Object?>{'depth': depth, 'pierce': false},
        sessionId: _pageSessionId,
        timeout: const Duration(seconds: 8),
      );
      final root = r['root'];
      return root is Map<String, dynamic> ? root : null;
    } catch (e, st) {
      silentLog('web_reverse_session_controller', 'domGetDocument', e, st);
      return null;
    }
  }

  /// `DOM.describeNode` — 取指定 node 的最新结构 + 一层 children。
  Future<Map<String, dynamic>?> domDescribeNode(int nodeId,
      {int depth = 1}) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return null;
    try {
      final r = await cdp.send(
        'DOM.describeNode',
        params: <String, Object?>{'nodeId': nodeId, 'depth': depth},
        sessionId: _pageSessionId,
        timeout: const Duration(seconds: 6),
      );
      final node = r['node'];
      return node is Map<String, dynamic> ? node : null;
    } catch (e, st) {
      silentLog('web_reverse_session_controller', 'domDescribeNode', e, st);
      return null;
    }
  }

  /// `CSS.getComputedStyleForNode` — 返回 [{name,value}] 列表（已 enable
  /// CSS domain；首次调用会自动 enable）。
  Future<List<Map<String, String>>> domGetComputedStyle(int nodeId) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return const [];
    try {
      await cdp.send('CSS.enable',
          sessionId: _pageSessionId,
          timeout: const Duration(seconds: 3));
      final r = await cdp.send(
        'CSS.getComputedStyleForNode',
        params: <String, Object?>{'nodeId': nodeId},
        sessionId: _pageSessionId,
        timeout: const Duration(seconds: 6),
      );
      final list = r['computedStyle'];
      if (list is! List) return const [];
      return list.whereType<Map>().map((e) {
        return <String, String>{
          'name': '${e['name']}',
          'value': '${e['value']}',
        };
      }).toList();
    } catch (e, st) {
      silentLog('web_reverse_session_controller', 'domGetComputedStyle', e, st);
      return const [];
    }
  }

  /// `DOMDebugger.getEventListeners` 需要 objectId，先 `DOM.resolveNode`
  /// 把 nodeId 转成 Runtime objectId。返回 [{type,useCapture,passive,
  /// once,scriptId,lineNumber,columnNumber,handler:{description}}] 列表。
  Future<List<Map<String, dynamic>>> domGetEventListeners(int nodeId) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return const [];
    try {
      final resolved = await cdp.send(
        'DOM.resolveNode',
        params: <String, Object?>{'nodeId': nodeId},
        sessionId: _pageSessionId,
        timeout: const Duration(seconds: 5),
      );
      final obj = resolved['object'];
      if (obj is! Map) return const [];
      final objectId = obj['objectId'];
      if (objectId is! String) return const [];
      final r = await cdp.send(
        'DOMDebugger.getEventListeners',
        params: <String, Object?>{'objectId': objectId, 'depth': 1},
        sessionId: _pageSessionId,
        timeout: const Duration(seconds: 6),
      );
      final list = r['listeners'];
      if (list is! List) return const [];
      return list.whereType<Map<String, dynamic>>().toList();
    } catch (e, st) {
      silentLog('web_reverse_session_controller', 'domGetEventListeners', e, st);
      return const [];
    }
  }

  /// 走 `Runtime.callFunctionOn` + DOM.resolveNode 在浏览器侧合成 CSS
  /// selector 路径（nth-of-type / id 优先）。比纯客户端递归更准。
  Future<String?> domCssSelectorForNode(int nodeId) async {
    return _domEvaluatePathFn(nodeId, _kCssSelectorFn);
  }

  /// 同上，返回简化 XPath。
  Future<String?> domXPathForNode(int nodeId) async {
    return _domEvaluatePathFn(nodeId, _kXPathFn);
  }

  Future<String?> _domEvaluatePathFn(int nodeId, String fnBody) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return null;
    try {
      final resolved = await cdp.send(
        'DOM.resolveNode',
        params: <String, Object?>{'nodeId': nodeId},
        sessionId: _pageSessionId,
        timeout: const Duration(seconds: 5),
      );
      final obj = resolved['object'];
      if (obj is! Map) return null;
      final objectId = obj['objectId'];
      if (objectId is! String) return null;
      final r = await cdp.send(
        'Runtime.callFunctionOn',
        params: <String, Object?>{
          'objectId': objectId,
          'functionDeclaration': fnBody,
          'returnByValue': true,
        },
        sessionId: _pageSessionId,
        timeout: const Duration(seconds: 6),
      );
      final result = r['result'];
      if (result is Map && result['value'] is String) {
        return result['value'] as String;
      }
      return null;
    } catch (e, st) {
      silentLog('web_reverse_session_controller', '_domEvaluatePathFn', e, st);
      return null;
    }
  }

  /// `Overlay.highlightNode` — 在页面里画 inspector 高亮框。需要先 enable。
  Future<void> domHighlightNode(int nodeId) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return;
    try {
      await cdp.send('Overlay.enable',
          sessionId: _pageSessionId,
          timeout: const Duration(seconds: 3));
      await cdp.send(
        'Overlay.highlightNode',
        params: <String, Object?>{
          'nodeId': nodeId,
          'highlightConfig': <String, Object?>{
            'showInfo': true,
            'showRulers': false,
            'showExtensionLines': false,
            'contentColor': <String, Object?>{
              'r': 111, 'g': 168, 'b': 220, 'a': 0.35,
            },
            'paddingColor': <String, Object?>{
              'r': 147, 'g': 196, 'b': 125, 'a': 0.55,
            },
            'borderColor': <String, Object?>{
              'r': 255, 'g': 229, 'b': 153, 'a': 0.66,
            },
            'marginColor': <String, Object?>{
              'r': 246, 'g': 178, 'b': 107, 'a': 0.66,
            },
          },
        },
        sessionId: _pageSessionId,
        timeout: const Duration(seconds: 4),
      );
    } catch (e, st) {
      silentLog('web_reverse_session_controller', 'domHighlightNode', e, st);
    }
  }

  Future<void> domHideHighlight() async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return;
    try {
      await cdp.send('Overlay.hideHighlight',
          sessionId: _pageSessionId,
          timeout: const Duration(seconds: 3));
    } catch (e, st) {
      silentLog('web_reverse_session_controller', 'domHideHighlight', e, st);
    }
  }

  /// 滚动到目标节点，方便用户在页面里看到 inspector 选中的元素。
  Future<void> domScrollIntoView(int nodeId) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return;
    try {
      await cdp.send(
        'DOM.scrollIntoViewIfNeeded',
        params: <String, Object?>{'nodeId': nodeId},
        sessionId: _pageSessionId,
        timeout: const Duration(seconds: 4),
      );
    } catch (e, st) {
      silentLog('web_reverse_session_controller', 'domScrollIntoView', e, st);
    }
  }

  /// 输入和结果都以 [_appendConsole] 写回 console buffer，
  /// 渲染端按 'repl-input' / 'repl-result' / 'error' level 区分配色。
  Future<String?> runReplExpression(String expression) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return null;
    final raw = expression.trim();
    if (raw.isEmpty) return null;
    _appendConsole('repl-input', '> $raw');
    try {
      final r = await cdp.send(
        'Runtime.evaluate',
        params: <String, Object?>{
          'expression': raw,
          'returnByValue': true,
          'awaitPromise': true,
          'allowUnsafeEvalBlockedByCSP': true,
        },
        sessionId: _pageSessionId,
        timeout: const Duration(seconds: 15),
      );
      final exception = r['exceptionDetails'];
      if (exception is Map) {
        final m = '${exception['exception']?['description'] ?? exception['text'] ?? 'eval failed'}';
        _appendConsole('error', m);
        return null;
      }
      final res = r['result'];
      String preview;
      if (res is Map) {
        final type = '${res['type'] ?? ''}';
        final value = res['value'];
        if (value == null) {
          preview = '${res['description'] ?? type}';
        } else if (value is String) {
          preview = "'$value'";
        } else if (value is num || value is bool) {
          preview = '$value';
        } else {
          // 对象 / 数组：用 JsonEncoder 美化；过长截断到 2KB。
          try {
            preview = const JsonEncoder.withIndent('  ').convert(value);
          } catch (_) {
            preview = '$value';
          }
        }
      } else {
        preview = '$res';
      }
      if (preview.length > 2048) {
        preview = '${preview.substring(0, 2048)}\n…(truncated)';
      }
      _appendConsole('repl-result', preview);
      return preview;
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', 'runReplExpression', error, stack);
      _appendConsole('error', '$error');
      return null;
    }
  }

  /// 直接发送原始 CDP 命令，给"CDP 命令面板"用。method 形如
  /// `Network.getAllCookies`；params JSON 字符串可空。
  Future<Map<String, Object?>?> sendRawCdp({
    required String method,
    String? paramsJson,
    bool useSession = true,
  }) async {
    final cdp = _browserCdp;
    if (cdp == null) return null;
    Map<String, Object?>? params;
    if (paramsJson != null && paramsJson.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(paramsJson);
        if (decoded is Map) params = Map<String, Object?>.from(decoded);
      } catch (e) {
        return <String, Object?>{'error': 'invalid params JSON: $e'};
      }
    }
    try {
      return await cdp.send(
        method,
        params: params,
        sessionId: useSession ? _pageSessionId : null,
        timeout: const Duration(seconds: 30),
      );
    } catch (error) {
      return <String, Object?>{'error': '$error'};
    }
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    await _safeStop();
    _safeNotify();
  }

  /// 用户主动停止调试：杀掉外部浏览器进程并保留会话本身。后续可调
  /// [restartBrowser] 再起一个新的。会话工作目录 / artifacts / dashboard
  /// 网络/控制台缓冲全部保留以便回看。
  Future<void> stopBrowser() async {
    if (_stopped) return;
    silentLog(
      'web_reverse_session_controller',
      'stopBrowser',
      'user requested',
      StackTrace.current,
    );
    _stopAliveWatchdog();
    // 关 screencast → 关 CDP → kill 进程；artifacts / dock 不动。
    if (_screencastActive) {
      try {
        if (_browserCdp != null && _pageSessionId != null) {
          await _browserCdp!
              .send('Page.stopScreencast', sessionId: _pageSessionId)
              .timeout(const Duration(milliseconds: 500));
        }
      } catch (_) {}
      _screencastActive = false;
      _screencastRefCount = 0;
      _latestScreencastFrame = null;
      _screencastFrameSeq = 0;
      if (!_disposed) {
        screencastFrameNotifier.value = screencastFrameNotifier.value + 1;
      }
    }
    await _pageEventsSub?.cancel();
    _pageEventsSub = null;
    _pageSessionId = null;
    try {
      await _pageCdp?.close();
    } catch (_) {}
    _pageCdp = null;
    try {
      await _browserCdp?.close();
    } catch (_) {}
    _browserCdp = null;
    final p = _launchResult?.process;
    if (p != null) {
      try {
        p.kill();
      } catch (_) {}
    }
    _launchResult = null;
    _errorMessage = null;
    _safeNotify();
  }

  /// 把外部浏览器拉起来：要么是用户主动点了「停止调试」想再连一次，
  /// 要么是浏览器异常退出 / CDP 重连耗尽后用户点了「重启浏览器」。
  /// 复用 [start] 的全部启动逻辑，只是重置 stopped 标记。
  Future<void> restartBrowser() async {
    if (_disposed) return;
    silentLog(
      'web_reverse_session_controller',
      'restartBrowser',
      'user requested',
      StackTrace.current,
    );
    // 先确保旧资源完全释放。
    await stopBrowser();
    _stopped = false;
    _started = false;
    _errorMessage = null;
    _safeNotify();
    try {
      await start();
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'restartBrowser → start',
        error,
        stack,
      );
      _errorMessage = '浏览器重启失败：$error';
      _safeNotify();
      rethrow;
    }
  }

  Future<void> _safeStop() async {
    _stopAliveWatchdog();
    // 主动停 screencast：进程将被 kill，事件流也会断；提前 stop 防止
    // 浏览器侧 ack 队列卡住影响下次拉起。
    if (_screencastActive) {
      final cdp = _browserCdp;
      try {
        if (cdp != null && _pageSessionId != null) {
          await cdp
              .send('Page.stopScreencast', sessionId: _pageSessionId)
              .timeout(const Duration(milliseconds: 500));
        }
      } catch (_) {}
      _screencastActive = false;
      _screencastRefCount = 0;
      _latestScreencastFrame = null;
      _screencastFrameSeq = 0;
      if (!_disposed) {
        screencastFrameNotifier.value = screencastFrameNotifier.value + 1;
      }
    }
    await _pageEventsSub?.cancel();
    await _mitmSub?.cancel();
    final br = _mitmBridge;
    _mitmBridge = null;
    if (br != null) {
      try {
        await br.close();
      } catch (_) {}
    }
    final har = _harReplayServer;
    _harReplayServer = null;
    if (har != null) {
      try {
        await har.close();
      } catch (_) {}
    }
    _pageEventsSub = null;
    _pageSessionId = null;
    try {
      await _pageCdp?.close();
    } catch (_) {}
    _pageCdp = null;
    try {
      await _browserCdp?.close();
    } catch (_) {}
    _browserCdp = null;
    final p = _launchResult?.process;
    if (p != null) {
      try {
        p.kill();
      } catch (_) {}
    }
    // 收尾产物：先导 HAR（用 in-memory drafts），再关 artifacts。
    try {
      _lastHarPath = await _artifacts.exportHar();
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', 'export HAR', error, stack);
    }
    await _artifacts.close();
  }

  /// 清空 dashboard 缓冲（用户在 dashboard 点"清空"按钮时调用）。
  void clearBuffers() {
    _networkRequests.clear();
    _networkByRequestId.clear();
    _consoleMessages.clear();
    _safeNotify();
  }

  /// 在浏览器主 page 上启用/关闭缓存。
  Future<void> setCacheDisabled(bool disabled) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return;
    await cdp.send(
      'Network.setCacheDisabled',
      params: <String, Object?>{'cacheDisabled': disabled},
      sessionId: _pageSessionId,
    );
  }

  /// 安装一个轻量 FPS 计数器到 page：基于 requestAnimationFrame 的滚动计数。
  /// 之后通过 [readFps] 拉取最近 1 秒的 FPS 值。
  Future<void> installFpsCounter() async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return;
    const js = r'''
(() => {
  if (window.__oh_fps_installed) return;
  window.__oh_fps_installed = true;
  let frames = 0;
  let last = performance.now();
  let fps = 0;
  const tick = () => {
    frames++;
    const now = performance.now();
    if (now - last >= 1000) {
      fps = (frames * 1000) / (now - last);
      frames = 0;
      last = now;
    }
    requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
  Object.defineProperty(window, '__oh_fps', { get: () => fps });
})();
''';
    try {
      await cdp.send(
        'Runtime.evaluate',
        params: const <String, Object?>{'expression': js},
        sessionId: _pageSessionId,
      );
    } catch (_) {}
  }

  /// 安装 Long Task 观测：通过 PerformanceObserver 监听 entryType='longtask'
  /// 的事件并塞进 window.__oh_long_tasks（环形缓冲，上限 200）。
  /// 之后 [readLongTasks] 拉取并清空。
  Future<void> installLongTaskObserver() async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return;
    const js = r'''
(() => {
  if (window.__oh_longtask_installed) return;
  window.__oh_longtask_installed = true;
  window.__oh_long_tasks = [];
  try {
    const po = new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) {
        const attrib = (entry.attribution && entry.attribution[0]) || null;
        window.__oh_long_tasks.push({
          name: entry.name,
          start: entry.startTime,
          duration: entry.duration,
          ts: Date.now(),
          attribution: attrib ? {
            name: attrib.name,
            containerType: attrib.containerType,
            containerSrc: attrib.containerSrc,
            containerId: attrib.containerId,
            containerName: attrib.containerName,
          } : null,
        });
        if (window.__oh_long_tasks.length > 200) window.__oh_long_tasks.shift();
      }
    });
    po.observe({ entryTypes: ['longtask'] });
  } catch (e) {
    window.__oh_long_tasks_error = String(e);
  }
})();
''';
    try {
      // init script 让后续导航也保留观测器；同时在当前 page 立即注入。
      await cdp.send(
        'Page.addScriptToEvaluateOnNewDocument',
        params: <String, Object?>{'source': js},
        sessionId: _pageSessionId,
      );
      await cdp.send(
        'Runtime.evaluate',
        params: const <String, Object?>{'expression': js},
        sessionId: _pageSessionId,
      );
    } catch (_) {}
  }

  /// 拉取 long task 列表并 drain。failure 时返回空列表。
  Future<List<Map<String, Object?>>> readLongTasks() async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return const [];
    try {
      final r = await cdp.send(
        'Runtime.evaluate',
        params: const <String, Object?>{
          'expression':
              '(()=>{const a=window.__oh_long_tasks||[];window.__oh_long_tasks=[];return JSON.stringify(a);})()',
          'returnByValue': true,
        },
        sessionId: _pageSessionId,
      );
      final raw = (r['result'] as Map?)?['value'];
      if (raw is! String || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((m) => Map<String, Object?>.from(m))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  // ── WebRTC 资源捕获 ─────────────────────────────────────────────────
  // CDP 不直接给 WebRTC 流量。在 page 内 hook RTCPeerConnection 构造函数 + 关键方法，
  // 把 createOffer/createAnswer/setLocalDescription/setRemoteDescription/addIceCandidate
  // /track/datachannel/getStats 的全部入参出参以 JSON 形式塞到 window.__oh_rtc_log。
  bool _rtcInstalled = false;
  Future<bool> installWebRtcCapture() async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    if (_rtcInstalled) return true;
    const js = r'''
(() => {
  if (window.__oh_rtc_installed) return;
  window.__oh_rtc_installed = true;
  const log = (kind, payload) => {
    try {
      const buf = window.__oh_rtc_log = window.__oh_rtc_log || [];
      buf.push({ kind, ts: Date.now(), ...payload });
      if (buf.length > 800) buf.splice(0, buf.length - 800);
    } catch (_) {}
  };
  const Orig = window.RTCPeerConnection || window.webkitRTCPeerConnection;
  if (!Orig) return;
  let nextId = 1;
  // 活跃 PeerConnection 注册表，供周期性 getStats 轮询使用。
  const reg = window.__oh_rtc_reg = window.__oh_rtc_reg || new Map();
  function patched(...args) {
    const pc = new Orig(...args);
    const id = nextId++;
    reg.set(id, pc);
    log('pc.create', { id, config: args[0] || null });
    const wrap = (name) => {
      const m = pc[name];
      if (typeof m !== 'function') return;
      pc[name] = async function(...a) {
        log(name + ':call', { id, args: a.map(x => (x && x.toJSON) ? x.toJSON() : x) });
        try {
          const r = await m.apply(pc, a);
          if (r && (r.sdp || r.type)) {
            log(name + ':result', { id, sdp: r.sdp, type: r.type });
          }
          return r;
        } catch (e) {
          log(name + ':error', { id, error: String(e) });
          throw e;
        }
      };
    };
    ['createOffer', 'createAnswer', 'setLocalDescription', 'setRemoteDescription', 'addIceCandidate'].forEach(wrap);
    pc.addEventListener('icecandidate', (ev) => {
      if (ev.candidate) {
        log('icecandidate', {
          id,
          candidate: ev.candidate.candidate,
          sdpMid: ev.candidate.sdpMid,
          sdpMLineIndex: ev.candidate.sdpMLineIndex,
        });
      }
    });
    pc.addEventListener('track', (ev) => {
      log('track', {
        id,
        kind: ev.track.kind,
        readyState: ev.track.readyState,
        muted: ev.track.muted,
        streamIds: (ev.streams || []).map(s => s.id),
      });
    });
    pc.addEventListener('datachannel', (ev) => {
      log('datachannel', {
        id,
        label: ev.channel.label,
        protocol: ev.channel.protocol,
        ordered: ev.channel.ordered,
      });
    });
    pc.addEventListener('connectionstatechange', () => {
      log('connectionstatechange', { id, state: pc.connectionState });
      if (pc.connectionState === 'closed' || pc.connectionState === 'failed') {
        reg.delete(id);
      }
    });
    pc.addEventListener('iceconnectionstatechange', () => {
      log('iceconnectionstatechange', { id, state: pc.iceConnectionState });
    });
    return pc;
  }
  patched.prototype = Orig.prototype;
  window.RTCPeerConnection = patched;
  if (window.webkitRTCPeerConnection) window.webkitRTCPeerConnection = patched;
  // 每秒轮询所有活跃 PC 的 getStats，挑关键字段累计：
  // outbound-rtp / inbound-rtp 的 bytesSent/bytesReceived/packetsLost,
  // remote-candidate-pair 的 currentRoundTripTime。
  if (!window.__oh_rtc_stats_timer) {
    window.__oh_rtc_stats_timer = setInterval(async () => {
      for (const [id, pc] of reg) {
        try {
          if (!pc || pc.connectionState === 'closed') { reg.delete(id); continue; }
          const stats = await pc.getStats(null);
          const sample = { id, bytesSent: 0, bytesReceived: 0, packetsLost: 0, packetsSent: 0, packetsReceived: 0, rtt: null, jitter: null };
          stats.forEach((r) => {
            if (r.type === 'outbound-rtp') {
              sample.bytesSent += r.bytesSent || 0;
              sample.packetsSent += r.packetsSent || 0;
            } else if (r.type === 'inbound-rtp') {
              sample.bytesReceived += r.bytesReceived || 0;
              sample.packetsReceived += r.packetsReceived || 0;
              sample.packetsLost += r.packetsLost || 0;
              if (typeof r.jitter === 'number') sample.jitter = r.jitter;
            } else if (r.type === 'candidate-pair' && r.state === 'succeeded' && r.nominated) {
              if (typeof r.currentRoundTripTime === 'number') sample.rtt = r.currentRoundTripTime;
            }
          });
          log('stats', sample);
        } catch (_) {}
      }
    }, 1000);
  }
})();
''';
    try {
      await cdp.send(
        'Page.addScriptToEvaluateOnNewDocument',
        params: const <String, Object?>{'source': js},
        sessionId: _pageSessionId,
      );
      await cdp.send(
        'Runtime.evaluate',
        params: const <String, Object?>{'expression': js},
        sessionId: _pageSessionId,
      );
      _rtcInstalled = true;
      return true;
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', 'installWebRtcCapture',
          error, stack);
      return false;
    }
  }

  /// 拉取 WebRTC 日志并 drain。
  Future<List<Map<String, Object?>>> readWebRtcLog() async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return const [];
    try {
      final r = await cdp.send(
        'Runtime.evaluate',
        params: const <String, Object?>{
          'expression':
              '(()=>{const a=window.__oh_rtc_log||[];window.__oh_rtc_log=[];return JSON.stringify(a);})()',
          'returnByValue': true,
        },
        sessionId: _pageSessionId,
      );
      final raw = (r['result'] as Map?)?['value'];
      if (raw is! String || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((m) => Map<String, Object?>.from(m))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// 列出当前页活跃的 RTCPeerConnection id 列表。供调试面板挑选。
  Future<List<int>> listWebRtcConnections() async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return const [];
    try {
      final r = await cdp.send(
        'Runtime.evaluate',
        params: const <String, Object?>{
          'expression':
              '(()=>{const m=window.__oh_rtc_reg;if(!m)return "[]";return JSON.stringify(Array.from(m.keys()));})()',
          'returnByValue': true,
        },
        sessionId: _pageSessionId,
      );
      final raw = (r['result'] as Map?)?['value'];
      if (raw is! String || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<num>()
          .map((n) => n.toInt())
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// 读取 page 当前 FPS 值；installFpsCounter 应先调用。
  Future<double?> readFps() async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return null;
    try {
      final r = await cdp.send(
        'Runtime.evaluate',
        params: const <String, Object?>{
          'expression': 'window.__oh_fps || 0',
          'returnByValue': true,
        },
        sessionId: _pageSessionId,
      );
      final v = (r['result'] as Map?)?['value'];
      return v is num ? v.toDouble() : null;
    } catch (_) {
      return null;
    }
  }

  // ── 内嵌浏览器：screencast 控制 / 输入桥 / 导航 API ──────────────────

  /// dashboard "浏览器" tab 激活时调用。引用计数 +1，第一个订阅者真正发送
  /// `Page.startScreencast`；后续重复调用只是引用计数累加，避免重复发命令
  /// 触发浏览器侧不必要的开销。返回 true 表示当前已处于 active 状态。
  Future<bool> acquireScreencast({
    int maxWidth = _screencastDefaultMaxWidth,
    int maxHeight = _screencastDefaultMaxHeight,
    int quality = _screencastDefaultQuality,
    int everyNthFrame = 1,
  }) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    _screencastRefCount++;
    if (_screencastActive) return true;
    try {
      final clampedQuality = quality.clamp(20, 95);
      final clampedW = maxWidth.clamp(160, 4096);
      final clampedH = maxHeight.clamp(120, 4096);
      final clampedNth = everyNthFrame.clamp(1, 8);
      await cdp.send(
        'Page.startScreencast',
        params: <String, Object?>{
          'format': 'jpeg',
          'quality': clampedQuality,
          'maxWidth': clampedW,
          'maxHeight': clampedH,
          'everyNthFrame': clampedNth,
        },
        sessionId: _pageSessionId,
      );
      _screencastActive = true;
      _screencastQuality = clampedQuality;
      // 注意：不能最小化外部 Chrome 窗口。Chromium 在窗口最小化 / 完全
      // 不可见时会暂停 compositor，`Page.startScreencast` 不再产生新帧，
      // 用户在内嵌面板里点任何按钮都看不到反馈。这里只发 startScreencast，
      // 外部 Chrome 窗口由系统默认位置打开，不主动调位以免和用户的其它
      // 浏览器窗口抢空间。
      _safeNotify();
      return true;
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'acquireScreencast',
        error,
        stack,
      );
      _screencastRefCount = (_screencastRefCount - 1).clamp(0, 1 << 30);
      return false;
    }
  }

  /// dashboard "浏览器" tab 切走 / 关闭时调用。引用计数归零后才真正
  /// `Page.stopScreencast` + 清空缓存帧，避免 widget 重新挂载时拿到陈旧画面。
  Future<void> releaseScreencast() async {
    if (_screencastRefCount > 0) _screencastRefCount--;
    if (_screencastRefCount > 0) return;
    if (!_screencastActive) return;
    final cdp = _browserCdp;
    try {
      if (cdp != null && _pageSessionId != null) {
        await cdp
            .send('Page.stopScreencast', sessionId: _pageSessionId)
            .timeout(const Duration(seconds: 3));
      }
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'releaseScreencast',
        error,
        stack,
      );
    }
    _screencastActive = false;
    _latestScreencastFrame = null;
    _screencastFrameSeq = 0;
    if (!_disposed) {
      screencastFrameNotifier.value = screencastFrameNotifier.value + 1;
    }
    _safeNotify();
  }

  /// 调整 screencast 输出尺寸 / 质量。widget 矩形变化或用户手动切档位时调用。
  /// 内部对底层重新调一次 startScreencast 做参数热替换，仅在 active 时生效。
  Future<void> reconfigureScreencast({
    required int maxWidth,
    required int maxHeight,
    int? quality,
    int everyNthFrame = 1,
  }) async {
    if (!_screencastActive) return;
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return;
    final clampedW = maxWidth.clamp(160, 4096);
    final clampedH = maxHeight.clamp(120, 4096);
    final clampedQ = (quality ?? _screencastQuality).clamp(20, 95);
    final clampedNth = everyNthFrame.clamp(1, 8);
    try {
      await cdp.send(
        'Page.startScreencast',
        params: <String, Object?>{
          'format': 'jpeg',
          'quality': clampedQ,
          'maxWidth': clampedW,
          'maxHeight': clampedH,
          'everyNthFrame': clampedNth,
        },
        sessionId: _pageSessionId,
      );
      _screencastQuality = clampedQ;
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'reconfigureScreencast',
        error,
        stack,
      );
    }
  }

  /// `Input.dispatchMouseEvent`。坐标系：CSS 像素，相对于浏览器 viewport 左上角。
  /// 由内嵌浏览器 widget 把本地命中点折算成 viewport 坐标后调用。
  Future<void> dispatchMouseEvent({
    required String type,
    required double x,
    required double y,
    String button = 'none',
    int buttons = 0,
    int clickCount = 0,
    double deltaX = 0,
    double deltaY = 0,
    int modifiers = 0,
  }) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return;
    try {
      await cdp.send(
        'Input.dispatchMouseEvent',
        params: <String, Object?>{
          'type': type,
          'x': x,
          'y': y,
          'button': button,
          'buttons': buttons,
          'clickCount': clickCount,
          'deltaX': deltaX,
          'deltaY': deltaY,
          'modifiers': modifiers,
        },
        sessionId: _pageSessionId,
        timeout: const Duration(seconds: 3),
      );
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'dispatchMouseEvent $type',
        error,
        stack,
      );
    }
  }

  /// `Input.dispatchKeyEvent`。`type` ∈ keyDown / keyUp / rawKeyDown / char。
  Future<void> dispatchKeyEvent({
    required String type,
    String? key,
    String? code,
    String? text,
    int? windowsVirtualKeyCode,
    int? nativeVirtualKeyCode,
    int modifiers = 0,
    bool autoRepeat = false,
  }) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return;
    try {
      await cdp.send(
        'Input.dispatchKeyEvent',
        params: <String, Object?>{
          'type': type,
          if (key != null) 'key': key,
          if (code != null) 'code': code,
          if (text != null) 'text': text,
          if (windowsVirtualKeyCode != null)
            'windowsVirtualKeyCode': windowsVirtualKeyCode,
          if (nativeVirtualKeyCode != null)
            'nativeVirtualKeyCode': nativeVirtualKeyCode,
          'modifiers': modifiers,
          'autoRepeat': autoRepeat,
        },
        sessionId: _pageSessionId,
        timeout: const Duration(seconds: 3),
      );
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'dispatchKeyEvent $type',
        error,
        stack,
      );
    }
  }

  /// `Input.insertText`：IME 提交 / 多字符粘贴的快捷方式。
  Future<void> insertText(String text) async {
    if (text.isEmpty) return;
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return;
    try {
      await cdp.send(
        'Input.insertText',
        params: <String, Object?>{'text': text},
        sessionId: _pageSessionId,
        timeout: const Duration(seconds: 3),
      );
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'insertText',
        error,
        stack,
      );
    }
  }

  /// 把页面导航到 [url]。内嵌浏览器地址栏回车 / 下拉历史均走这里。
  Future<void> navigate(String url) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return;
    try {
      await cdp.send(
        'Page.navigate',
        params: <String, Object?>{'url': url},
        sessionId: _pageSessionId,
        timeout: const Duration(seconds: 10),
      );
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'navigate $url',
        error,
        stack,
      );
    }
  }

  /// 后退一帧（若有历史）。
  Future<void> goBack() async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return;
    try {
      final r = await cdp.send(
        'Page.getNavigationHistory',
        sessionId: _pageSessionId,
        timeout: const Duration(seconds: 3),
      );
      final entries = (r['entries'] as List?) ?? const [];
      final current = (r['currentIndex'] as num?)?.toInt() ?? -1;
      if (current <= 0 || entries.isEmpty) return;
      final id =
          (entries[current - 1] as Map?)?['id'];
      if (id == null) return;
      await cdp.send(
        'Page.navigateToHistoryEntry',
        params: <String, Object?>{'entryId': id},
        sessionId: _pageSessionId,
      );
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', 'goBack', error, stack);
    }
  }

  /// 前进一帧（若有历史）。
  Future<void> goForward() async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return;
    try {
      final r = await cdp.send(
        'Page.getNavigationHistory',
        sessionId: _pageSessionId,
        timeout: const Duration(seconds: 3),
      );
      final entries = (r['entries'] as List?) ?? const [];
      final current = (r['currentIndex'] as num?)?.toInt() ?? -1;
      if (current < 0 || current + 1 >= entries.length) return;
      final id =
          (entries[current + 1] as Map?)?['id'];
      if (id == null) return;
      await cdp.send(
        'Page.navigateToHistoryEntry',
        params: <String, Object?>{'entryId': id},
        sessionId: _pageSessionId,
      );
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', 'goForward', error, stack);
    }
  }

  /// 重新加载当前页（不清缓存）。
  Future<void> reload({bool ignoreCache = false}) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return;
    try {
      await cdp.send(
        'Page.reload',
        params: <String, Object?>{'ignoreCache': ignoreCache},
        sessionId: _pageSessionId,
      );
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', 'reload', error, stack);
    }
  }

  /// 设备模拟预设：移动 / 平板 / 桌面三档；底层走
  /// `Emulation.setDeviceMetricsOverride` + `Emulation.setUserAgentOverride`。
  /// 传 `null` 则 `Emulation.clearDeviceMetricsOverride`。
  /// 2026-05-24 — 让分辨率档位真正影响页面渲染：传入 cssWidth/cssHeight/
  /// deviceScaleFactor=0 表示清除 override（恢复浏览器原生窗口尺寸）；其
  /// 它值则下发 Emulation.setDeviceMetricsOverride，让页面真正按该 CSS
  /// 尺寸 reflow，而不是只 cap 帧尺寸。
  Future<void> applyResolutionEmulation({
    required int cssWidth,
    required int cssHeight,
    required double deviceScaleFactor,
  }) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return;
    try {
      if (cssWidth <= 0 || cssHeight <= 0 || deviceScaleFactor <= 0) {
        await cdp.send(
          'Emulation.clearDeviceMetricsOverride',
          sessionId: _pageSessionId,
        );
        return;
      }
      await cdp.send(
        'Emulation.setDeviceMetricsOverride',
        params: <String, Object?>{
          'width': cssWidth,
          'height': cssHeight,
          'deviceScaleFactor': deviceScaleFactor,
          'mobile': false,
        },
        sessionId: _pageSessionId,
      );
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'applyResolutionEmulation',
        error,
        stack,
      );
    }
  }

  /// 设备模拟预设：移动 / 平板 / 桌面三档；底层走
  Future<void> setDeviceMetricsPreset(WebReverseDevicePreset? preset) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return;
    try {
      if (preset == null) {
        await cdp.send(
          'Emulation.clearDeviceMetricsOverride',
          sessionId: _pageSessionId,
        );
        await cdp.send(
          'Emulation.setUserAgentOverride',
          params: const <String, Object?>{'userAgent': ''},
          sessionId: _pageSessionId,
        );
        return;
      }
      await cdp.send(
        'Emulation.setDeviceMetricsOverride',
        params: <String, Object?>{
          'width': preset.width,
          'height': preset.height,
          'deviceScaleFactor': preset.deviceScaleFactor,
          'mobile': preset.mobile,
        },
        sessionId: _pageSessionId,
      );
      if (preset.userAgent != null) {
        await cdp.send(
          'Emulation.setUserAgentOverride',
          params: <String, Object?>{'userAgent': preset.userAgent},
          sessionId: _pageSessionId,
        );
      }
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'setDeviceMetricsPreset',
        error,
        stack,
      );
    }
  }

  /// 设置浏览器侧的页面缩放比例。`scale=1` 即 100%。
  ///
  /// 历史遗留：早先用 `Emulation.setPageScaleFactor`，但它只在
  /// `Emulation.setDeviceMetricsOverride` 配合下生效（即"移动端模拟"模式
  /// 下的视觉缩放），桌面 page 上完全 no-op。
  ///
  /// 现行实现：直接走 Chrome 的 `chrome.tabs.setZoom` 等价 API ——
  /// `Browser.setDownloadBehavior`-级 endpoint 不存在 zoom，只能借助 JS
  /// `document.body.style.zoom`。问题是 SPA 在导航后会重置 body 样式，因此
  /// 双管齐下：
  ///   1. `Page.addScriptToEvaluateOnNewDocument` 注入一份"页面加载即套
  ///      zoom"的脚本，保证导航后值不丢；
  ///   2. 当前页立即 `Runtime.evaluate` 写一次 body.style.zoom；
  ///   3. body 不存在时（DOMContentLoaded 之前）回退给 documentElement，
  ///      事件触发后再补一次 body。
  Future<void> setZoomFactor(double scale) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return;
    final clamped = scale.clamp(0.25, 5.0);
    _zoomScriptId ??= '';
    try {
      // 移除旧 init script，再注一份新的（zoom 值变了）。
      if (_zoomScriptId != null && _zoomScriptId!.isNotEmpty) {
        try {
          await cdp.send(
            'Page.removeScriptToEvaluateOnNewDocument',
            params: <String, Object?>{'identifier': _zoomScriptId},
            sessionId: _pageSessionId,
          );
        } catch (_) {}
      }
      final initJs = '''
(() => {
  const apply = () => {
    if (document.body) document.body.style.zoom = '$clamped';
    if (document.documentElement) document.documentElement.style.zoom = '$clamped';
  };
  apply();
  if (!document.body) {
    document.addEventListener('DOMContentLoaded', apply, { once: true });
  }
})();
''';
      final r = await cdp.send(
        'Page.addScriptToEvaluateOnNewDocument',
        params: <String, Object?>{'source': initJs},
        sessionId: _pageSessionId,
      );
      _zoomScriptId = r['identifier'] as String?;
      // 当前页立即应用一次。
      await cdp.send(
        'Runtime.evaluate',
        params: <String, Object?>{
          'expression':
              '(document.body && (document.body.style.zoom = "$clamped"))'
                  ' || (document.documentElement.style.zoom = "$clamped");',
        },
        sessionId: _pageSessionId,
        timeout: const Duration(seconds: 3),
      );
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'setZoomFactor $clamped',
        error,
        stack,
      );
    }
  }

  /// 上次 setZoomFactor 注的 init script identifier，下次设置时先移除。
  String? _zoomScriptId;

  // ── 页面查找：基于注入 JS 的 textNode 扫描 + mark 高亮 + cycle ───────────
  // CDP `DOM.performSearch` 返回的是 DOM 节点 ID，需要再 `DOM.scrollIntoViewIfNeeded`
  // 才能跳转，体验上和浏览器原生 Cmd+F 还是有差距；这里改为 Runtime.evaluate
  // 注入一个轻量 finder：扫文档 textNode、insertion 高亮 mark 标签、维护
  // 当前 index、cycle next / prev / 清理。一次注入多次复用，性能比反复
  // performSearch 好，对模型来说也更可控。

  bool _finderInstalled = false;

  Future<int> findInPage(String query) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return 0;
    if (query.trim().isEmpty) {
      await clearFindHighlights();
      return 0;
    }
    if (!_finderInstalled) {
      await _installFinder();
    }
    try {
      final r = await cdp.send(
        'Runtime.evaluate',
        params: <String, Object?>{
          'expression': '__oh_find_set(${jsonEncode(query)})',
          'returnByValue': true,
        },
        sessionId: _pageSessionId,
        timeout: const Duration(seconds: 5),
      );
      final v = (r['result'] as Map?)?['value'];
      return v is num ? v.toInt() : 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> findCycleNext({bool forward = true}) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return;
    try {
      await cdp.send(
        'Runtime.evaluate',
        params: <String, Object?>{
          'expression': '__oh_find_cycle(${forward ? 1 : -1})',
        },
        sessionId: _pageSessionId,
      );
    } catch (_) {}
  }

  Future<void> clearFindHighlights() async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return;
    try {
      await cdp.send(
        'Runtime.evaluate',
        params: const <String, Object?>{
          'expression': 'window.__oh_find_clear && __oh_find_clear()',
        },
        sessionId: _pageSessionId,
      );
    } catch (_) {}
  }

  Future<void> _installFinder() async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return;
    const js = r'''
(() => {
  if (window.__oh_find_installed) return;
  window.__oh_find_installed = true;
  let marks = [];
  let curIndex = -1;
  const STYLE_ID = '__oh_find_style';
  const ensureStyle = () => {
    if (document.getElementById(STYLE_ID)) return;
    const s = document.createElement('style');
    s.id = STYLE_ID;
    s.textContent = '.__oh_find_mark{background:#ffd54f;color:#000;border-radius:2px}.__oh_find_mark.__oh_find_active{background:#ff9800;color:#fff}';
    document.documentElement.appendChild(s);
  };
  window.__oh_find_clear = () => {
    for (const m of marks) {
      const parent = m.parentNode;
      if (!parent) continue;
      parent.replaceChild(document.createTextNode(m.textContent || ''), m);
      parent.normalize();
    }
    marks = []; curIndex = -1;
  };
  const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  window.__oh_find_set = (q) => {
    __oh_find_clear();
    if (!q) return 0;
    ensureStyle();
    const re = new RegExp(escapeRe(q), 'gi');
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
      acceptNode: (n) => {
        const p = n.parentElement;
        if (!p) return NodeFilter.FILTER_REJECT;
        const tag = p.tagName;
        if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'NOSCRIPT') return NodeFilter.FILTER_REJECT;
        if (!n.nodeValue || !n.nodeValue.trim()) return NodeFilter.FILTER_REJECT;
        return NodeFilter.FILTER_ACCEPT;
      }
    });
    const nodes = []; let cur;
    while ((cur = walker.nextNode())) nodes.push(cur);
    for (const n of nodes) {
      const text = n.nodeValue;
      let m; const frag = document.createDocumentFragment();
      let last = 0;
      re.lastIndex = 0;
      while ((m = re.exec(text)) != null) {
        if (m.index > last) frag.appendChild(document.createTextNode(text.slice(last, m.index)));
        const span = document.createElement('mark');
        span.className = '__oh_find_mark';
        span.textContent = m[0];
        frag.appendChild(span);
        marks.push(span);
        last = re.lastIndex;
        if (m[0].length === 0) re.lastIndex++;
      }
      if (last > 0) {
        if (last < text.length) frag.appendChild(document.createTextNode(text.slice(last)));
        n.parentNode && n.parentNode.replaceChild(frag, n);
      }
    }
    if (marks.length > 0) {
      curIndex = 0;
      marks[0].classList.add('__oh_find_active');
      marks[0].scrollIntoView({block:'center', behavior:'smooth'});
    }
    return marks.length;
  };
  window.__oh_find_cycle = (dir) => {
    if (marks.length === 0) return 0;
    if (curIndex >= 0) marks[curIndex].classList.remove('__oh_find_active');
    curIndex = (curIndex + dir + marks.length) % marks.length;
    const m = marks[curIndex];
    m.classList.add('__oh_find_active');
    m.scrollIntoView({block:'center', behavior:'smooth'});
    return curIndex + 1;
  };
})();
''';
    try {
      await cdp.send(
        'Page.addScriptToEvaluateOnNewDocument',
        params: <String, Object?>{'source': js},
        sessionId: _pageSessionId,
      );
      await cdp.send(
        'Runtime.evaluate',
        params: <String, Object?>{'expression': js},
        sessionId: _pageSessionId,
      );
      _finderInstalled = true;
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        '_installFinder',
        error,
        stack,
      );
    }
  }

  /// 读取主 frame 的当前 URL。地址栏初始化 / 导航后同步用。
  Future<String?> currentUrl() async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return null;
    try {
      final r = await cdp.send(
        'Runtime.evaluate',
        params: const <String, Object?>{
          'expression': 'location.href',
          'returnByValue': true,
        },
        sessionId: _pageSessionId,
        timeout: const Duration(seconds: 3),
      );
      return (r['result'] as Map?)?['value'] as String?;
    } catch (_) {
      return null;
    }
  }

  // ── 截图 ─────────────────────────────────────────────────────────────

  /// 截当前可视区。返回 PNG / JPEG 字节；失败返回 null。
  /// `quality` 仅 jpeg 有效（0-100）。
  Future<Uint8List?> captureScreenshot({
    String format = 'png',
    int quality = 90,
  }) async {
    return _captureScreenshot(
      format: format,
      quality: quality,
      capturePastViewport: false,
    );
  }

  /// 截整页（自动滚动拼接）。Chromium ≥ 113 支持 `captureBeyondViewport`。
  Future<Uint8List?> captureFullPageScreenshot({
    String format = 'png',
    int quality = 90,
  }) async {
    return _captureScreenshot(
      format: format,
      quality: quality,
      capturePastViewport: true,
    );
  }

  Future<Uint8List?> _captureScreenshot({
    required String format,
    required int quality,
    required bool capturePastViewport,
  }) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return null;
    try {
      final params = <String, Object?>{
        'format': format,
        if (format == 'jpeg') 'quality': quality.clamp(1, 100),
        if (capturePastViewport) 'captureBeyondViewport': true,
        'fromSurface': true,
      };
      // Page.getLayoutMetrics 取整页尺寸，让浏览器走 captureBeyondViewport。
      if (capturePastViewport) {
        final metrics = await cdp.send(
          'Page.getLayoutMetrics',
          sessionId: _pageSessionId,
          timeout: const Duration(seconds: 10),
        );
        final content = metrics['cssContentSize'] as Map?;
        if (content != null) {
          params['clip'] = <String, Object?>{
            'x': 0,
            'y': 0,
            'width': (content['width'] as num?)?.toDouble() ?? 0,
            'height': (content['height'] as num?)?.toDouble() ?? 0,
            'scale': 1,
          };
        }
      }
      final r = await cdp.send(
        'Page.captureScreenshot',
        params: params,
        sessionId: _pageSessionId,
        timeout: const Duration(seconds: 30),
      );
      final data = r['data'] as String?;
      if (data == null || data.isEmpty) return null;
      return base64Decode(data);
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'captureScreenshot $format full=$capturePastViewport',
        error,
        stack,
      );
      return null;
    }
  }

  // ── Memory: V8 实时采样（HeapProfiler.startSampling） ─────────────────

  bool _samplingProfileRunning = false;
  bool get isMemorySampling => _samplingProfileRunning;

  /// 启动 V8 采样（HeapProfiler.startSampling）。失败返回 false。
  Future<bool> startMemorySampling({double samplingInterval = 32768}) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    if (_samplingProfileRunning) return true;
    try {
      await cdp.send('HeapProfiler.enable', sessionId: _pageSessionId);
      await cdp.send(
        'HeapProfiler.startSampling',
        params: <String, Object?>{'samplingInterval': samplingInterval},
        sessionId: _pageSessionId,
      );
      _samplingProfileRunning = true;
      _safeNotify();
      return true;
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'startMemorySampling',
        error,
        stack,
      );
      return false;
    }
  }

  /// 停止采样并返回汇总。停止前可多次调 stopMemorySampling 取中间快照。
  Future<({int totalSize, List<({String label, int size, List<String> stack})> top})?>
      stopMemorySampling() async {
    final cdp = _browserCdp;
    if (cdp == null || !_samplingProfileRunning) return null;
    try {
      final r = await cdp.send(
        'HeapProfiler.stopSampling',
        sessionId: _pageSessionId,
        timeout: const Duration(seconds: 10),
      );
      _samplingProfileRunning = false;
      _safeNotify();
      final profile = r['profile'] as Map?;
      if (profile == null) return null;
      // V8 SamplingHeapProfile 的 head 是火焰图根，递归累加 selfSize 并保留
      // 完整 callFrame 链。点击下钻看 stack 时直接读 entry.stack。
      final tally = <String, ({int size, List<String> stack})>{};
      var total = 0;
      void walk(Map node, List<String> parentStack) {
        final cf = (node['callFrame'] as Map?) ?? const <String, Object?>{};
        final fnName = '${cf['functionName'] ?? '(anon)'}';
        final url = '${cf['url'] ?? ''}';
        final line = (cf['lineNumber'] as num?)?.toInt() ?? 0;
        final col = (cf['columnNumber'] as num?)?.toInt() ?? 0;
        final stackEntry = url.isEmpty
            ? fnName
            : '${fnName.isEmpty ? "(anonymous)" : fnName} @ $url:${line + 1}:${col + 1}';
        final stack = [...parentStack, stackEntry];
        final self = (node['selfSize'] as num?)?.toInt() ?? 0;
        total += self;
        final old = tally[fnName];
        if (old == null) {
          tally[fnName] = (size: self, stack: stack);
        } else {
          tally[fnName] = (size: old.size + self, stack: old.stack);
        }
        final children = node['children'] as List?;
        if (children != null) {
          for (final c in children.whereType<Map>()) {
            walk(c, stack);
          }
        }
      }
      walk(Map<String, Object?>.from(profile['head'] as Map), const []);
      final entries = tally.entries.toList()
        ..sort((a, b) => b.value.size.compareTo(a.value.size));
      final top = entries
          .take(15)
          .map((e) => (
                label: e.key.isEmpty ? '(anonymous)' : e.key,
                size: e.value.size,
                stack: e.value.stack,
              ))
          .toList(growable: false);
      return (totalSize: total, top: top);
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'stopMemorySampling',
        error,
        stack,
      );
      return null;
    }
  }

  /// 拉一次 V8 内存上报（不停止采样）：JSHeapUsedSize / JSHeapTotalSize。
  /// 用于面板的实时折线，避免 stopSampling 中断采样数据。
  Future<({double used, double total})?> readJsHeap() async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return null;
    try {
      final r = await cdp.send(
        'Performance.getMetrics',
        sessionId: _pageSessionId,
      );
      final list = r['metrics'] as List?;
      if (list == null) return null;
      double used = 0;
      double tot = 0;
      for (final m in list.whereType<Map>()) {
        final name = '${m['name']}';
        final v = (m['value'] as num?)?.toDouble() ?? 0;
        if (name == 'JSHeapUsedSize') used = v;
        if (name == 'JSHeapTotalSize') tot = v;
      }
      return (used: used, total: tot);
    } catch (_) {
      return null;
    }
  }

  // ── Network: Fetch 域代理（throttle / abort） ─────────────────────────

  /// 通过 Fetch 域拦截全部请求。每次拦到都通过 [_pendingFetchRequests] 暴露
  /// 给 dashboard，用户可手动 continue / abort / 修改延迟。
  /// 启用后所有请求都需要 dashboard 显式放行；适合反爬调试与超时模拟，
  /// 不建议默认开。
  bool _fetchInterceptEnabled = false;
  bool get isFetchInterceptEnabled => _fetchInterceptEnabled;  // 请求 ID -> 暂存的元信息（method / url），等用户决策。
  final Map<String, Map<String, Object?>> _pendingFetchRequests =
      <String, Map<String, Object?>>{};
  List<({String requestId, String method, String url})>
      get pendingFetchRequests => _pendingFetchRequests.entries
          .map((e) => (
                requestId: e.key,
                method: '${e.value['method'] ?? 'GET'}',
                url: '${e.value['url'] ?? ''}',
              ))
          .toList(growable: false);

  Future<bool> setFetchInterceptEnabled(bool enabled) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    try {
      if (enabled) {
        await cdp.send(
          'Fetch.enable',
          params: const <String, Object?>{
            'patterns': [
              <String, Object?>{'requestStage': 'Request'},
            ],
          },
          sessionId: _pageSessionId,
        );
      } else {
        await cdp.send('Fetch.disable', sessionId: _pageSessionId);
        _pendingFetchRequests.clear();
      }
      _fetchInterceptEnabled = enabled;
      _safeNotify();
      return true;
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'setFetchInterceptEnabled',
        error,
        stack,
      );
      return false;
    }
  }

  Future<void> continueFetchRequest(String requestId) async {
    final cdp = _browserCdp;
    if (cdp == null) return;
    _pendingFetchRequests.remove(requestId);
    try {
      await cdp.send(
        'Fetch.continueRequest',
        params: <String, Object?>{'requestId': requestId},
        sessionId: _pageSessionId,
      );
    } catch (_) {}
    _safeNotify();
  }

  /// 改写后再放行：可覆盖 url / method / headers / postData。
  /// `headers` 字段：null = 保持原值；空 Map = 完全清空；非空 Map = 完全替换。
  Future<void> continueFetchRequestEdited(
    String requestId, {
    String? url,
    String? method,
    Map<String, String>? headers,
    String? postDataBase64,
  }) async {
    final cdp = _browserCdp;
    if (cdp == null) return;
    _pendingFetchRequests.remove(requestId);
    try {
      final params = <String, Object?>{'requestId': requestId};
      if (url != null && url.isNotEmpty) params['url'] = url;
      if (method != null && method.isNotEmpty) params['method'] = method;
      if (headers != null) {
        params['headers'] = headers.entries
            .map((e) => <String, Object?>{'name': e.key, 'value': e.value})
            .toList(growable: false);
      }
      if (postDataBase64 != null) params['postData'] = postDataBase64;
      await cdp.send(
        'Fetch.continueRequest',
        params: params,
        sessionId: _pageSessionId,
      );
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'continueFetchRequestEdited',
        error,
        stack,
      );
    }
    _safeNotify();
  }

  /// 终止某条请求；reason 见 CDP Network.ErrorReason 枚举。
  Future<void> abortFetchRequest(String requestId, {String reason = 'Aborted'}) async {
    final cdp = _browserCdp;
    if (cdp == null) return;
    _pendingFetchRequests.remove(requestId);
    try {
      await cdp.send(
        'Fetch.failRequest',
        params: <String, Object?>{
          'requestId': requestId,
          'errorReason': reason,
        },
        sessionId: _pageSessionId,
      );
    } catch (_) {}
    _safeNotify();
  }

  /// 全部放行已暂存请求。
  Future<void> continueAllFetch() async {
    final ids = _pendingFetchRequests.keys.toList();
    for (final id in ids) {
      await continueFetchRequest(id);
    }
  }

  void _onFetchRequestPaused(Map<String, Object?> p) {
    final requestId = '${p['requestId']}';
    final request = p['request'] as Map?;
    if (requestId.isEmpty || request == null) return;
    final url = '${request['url'] ?? ''}';
    // 自动规则匹配：先看匹配到的第一条 rule，决定是 block / rewrite / 放行。
    final rule = _matchInterceptRule(url);
    if (rule != null) {
      if (rule.block) {
        unawaited(abortFetchRequest(requestId, reason: 'BlockedByClient'));
        return;
      }
      String? newUrl;
      if (rule.replaceUrl != null && rule.replaceUrl!.isNotEmpty) {
        newUrl = rule.replaceUrl;
      }
      Map<String, String>? newHeaders;
      if (rule.headerOverrides.isNotEmpty) {
        final hdrs = <String, String>{};
        final orig = request['headers'] as Map? ?? const {};
        for (final entry in orig.entries) {
          hdrs['${entry.key}'] = '${entry.value}';
        }
        hdrs.addAll(rule.headerOverrides);
        newHeaders = hdrs;
      }
      if (newUrl != null || newHeaders != null) {
        unawaited(continueFetchRequestEdited(
          requestId,
          url: newUrl,
          headers: newHeaders,
        ));
        return;
      }
      // 命中规则但仅作"标记"，仍然 hold 住等用户决定。
    }
    _pendingFetchRequests[requestId] = <String, Object?>{
      'method': request['method'],
      'url': request['url'],
      'ts': DateTime.now().toUtc().toIso8601String(),
    };
    _safeNotify();
  }

  /// 自动规则集（URL 通配匹配）。匹配到的第一条按指令对请求 block / rewrite。
  /// 没有命中时回退到原有的"暂停 → 等用户操作"路径。
  final List<WebReverseInterceptRule> _interceptRules =
      <WebReverseInterceptRule>[];

  List<WebReverseInterceptRule> get interceptRules =>
      List<WebReverseInterceptRule>.unmodifiable(_interceptRules);

  void setInterceptRules(List<WebReverseInterceptRule> rules) {
    _interceptRules
      ..clear()
      ..addAll(rules);
    _safeNotify();
  }

  WebReverseInterceptRule? _matchInterceptRule(String url) {
    for (final r in _interceptRules) {
      if (!r.enabled) continue;
      if (r.matches(url)) return r;
    }
    return null;
  }

  /// 已被屏蔽的 URL pattern 集合（CDP `Network.setBlockedURLs`）。
  /// 支持通配符 `*`；对应到右键菜单"Block this URL"。
  final Set<String> _blockedUrls = <String>{};
  Set<String> get blockedUrls => Set<String>.unmodifiable(_blockedUrls);

  Future<void> blockUrl(String pattern) async {
    if (pattern.isEmpty) return;
    _blockedUrls.add(pattern);
    await _flushBlockedUrls();
  }

  Future<void> unblockUrl(String pattern) async {
    _blockedUrls.remove(pattern);
    await _flushBlockedUrls();
  }

  Future<void> clearBlockedUrls() async {
    _blockedUrls.clear();
    await _flushBlockedUrls();
  }

  Future<void> _flushBlockedUrls() async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) {
      _safeNotify();
      return;
    }
    try {
      await cdp.send(
        'Network.setBlockedURLs',
        params: <String, Object?>{'urls': _blockedUrls.toList()},
        sessionId: _pageSessionId,
      );
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'setBlockedURLs',
        error,
        stack,
      );
    }
    _safeNotify();
  }

  /// 在浏览器里重发指定请求（按 entry 当前的 method/url/headers/postData）。
  /// 走 `fetch()` 重发；返回 (status, bodyPreview)；失败返回 null。
  /// 可选 [overrideUrl] / [overrideHeaders] 让上层"先 rewrite 再 replay"，与
  /// intercept rule editor 共用同一套字段语义（headers null = 用原值；空 Map
  /// = 清空；非空 Map = 替换）。
  Future<({int status, String body})?> replayRequest(
    CdpNetworkEntry e, {
    String? overrideUrl,
    Map<String, String>? overrideHeaders,
  }) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return null;
    final url = overrideUrl != null && overrideUrl.isNotEmpty
        ? overrideUrl
        : e.url;
    final init = <String, Object?>{
      'method': e.method,
      if ((overrideHeaders ?? e.requestHeaders).isNotEmpty)
        'headers':
            (overrideHeaders ?? e.requestHeaders).map((k, v) => MapEntry(k, v)),
      if (e.requestPostData != null) 'body': e.requestPostData,
      'credentials': 'include',
    };
    final js = '''
(async () => {
  try {
    const r = await fetch(${jsonEncode(url)}, ${jsonEncode(init)});
    const text = await r.text();
    return JSON.stringify({ status: r.status, body: text.slice(0, 4096) });
  } catch (err) {
    return JSON.stringify({ status: -1, body: String(err) });
  }
})()
''';
    try {
      final r = await cdp.send(
        'Runtime.evaluate',
        params: <String, Object?>{
          'expression': js,
          'awaitPromise': true,
          'returnByValue': true,
        },
        sessionId: _pageSessionId,
        timeout: const Duration(seconds: 30),
      );
      final raw = (r['result'] as Map?)?['value'];
      if (raw is! String) return null;
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      return (
        status: (decoded['status'] as num?)?.toInt() ?? -1,
        body: '${decoded['body'] ?? ''}',
      );
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'replayRequest',
        error,
        stack,
      );
      return null;
    }
  }

  /// 是否在主 frame 导航时保留旧日志。关闭后下次导航自动清表。
  bool get preserveLog => _preserveLog;
  set preserveLog(bool v) {
    if (_preserveLog == v) return;
    _preserveLog = v;
    _safeNotify();
  }

  /// 设置网络节流模式：normal / offline / slow3g / fast3g。
  /// 失败/未启用时返回 false。
  Future<bool> setNetworkThrottling(WebReverseThrottlePreset preset) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    final params = preset.cdpParams;
    try {
      await cdp.send(
        'Network.emulateNetworkConditions',
        params: params,
        sessionId: _pageSessionId,
      );
      return true;
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'setNetworkThrottling',
        error,
        stack,
      );
      return false;
    }
  }

  /// Debugger 已 attach 的脚本（`Debugger.scriptParsed`）。Sources tab 用。
  /// key=scriptId，value=(url, isModule)。源码本身在 [_scriptSources] 缓存。
  final Map<String, ({String url, bool isModule})> _parsedScripts =
      <String, ({String url, bool isModule})>{};
  Map<String, ({String url, bool isModule})> get parsedScripts =>
      Map<String, ({String url, bool isModule})>.unmodifiable(_parsedScripts);
  final Map<String, String> _scriptSources = <String, String>{};

  void _onScriptParsed(Map<String, Object?> p) {
    final id = p['scriptId'] as String?;
    if (id == null || id.isEmpty) return;
    final url = '${p['url'] ?? ''}';
    if (url.isEmpty) return;
    _parsedScripts[id] = (url: url, isModule: p['isModule'] == true);
  }

  /// 在 page 上启用 Debugger domain；调用后 [_onScriptParsed] 会陆续填充 [_parsedScripts]。
  Future<bool> enableDebugger() async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    try {
      await cdp.send('Debugger.enable', sessionId: _pageSessionId);
      return true;
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', 'enableDebugger', error, stack);
      return false;
    }
  }

  /// 跨脚本全局搜索：把 [_parsedScripts] 全部源码 grep 一次（已缓存的复用，
  /// 未缓存的按需 getScriptSource 拉一次）。返回 hit 列表：每条包含
  /// scriptId / url / line / preview。仅做基本的字符串匹配（不区分大小写），
  /// 模型若需要正则可在 UI 端自己处理。
  Future<List<({String scriptId, String url, int line, String preview})>>
      searchScriptsGlobal(String query, {int limit = 200}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final hits =
        <({String scriptId, String url, int line, String preview})>[];
    for (final entry in _parsedScripts.entries) {
      if (hits.length >= limit) break;
      final id = entry.key;
      final src = await getScriptSource(id);
      if (src == null || src.isEmpty) continue;
      final lines = src.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (hits.length >= limit) break;
        final l = lines[i];
        if (l.toLowerCase().contains(q)) {
          hits.add((
            scriptId: id,
            url: entry.value.url,
            line: i,
            preview: l.length > 120 ? '${l.substring(0, 120)}…' : l,
          ));
        }
      }
    }
    return hits;
  }

  /// 拉取脚本源码。CDP `Debugger.getScriptSource`。
  /// 命中过的脚本缓存到 [_scriptSources]，重复点同一个 URL 不再发请求。
  Future<String?> getScriptSource(String scriptId) async {
    final cached = _scriptSources[scriptId];
    if (cached != null) return cached;
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return null;
    try {
      final r = await cdp.send(
        'Debugger.getScriptSource',
        params: <String, Object?>{'scriptId': scriptId},
        sessionId: _pageSessionId,
        timeout: const Duration(seconds: 15),
      );
      final src = r['scriptSource'] as String?;
      if (src != null) _scriptSources[scriptId] = src;
      return src;
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', 'getScriptSource', error, stack);
      return null;
    }
  }

  /// 用户在 Sources tab 设过的断点集合：dashboard 关掉再打开 / 浏览器
  /// 重启时由上层把这份持久化数据再次下发。
  final Set<({String url, int line})> _userBreakpoints =
      <({String url, int line})>{};
  // breakpointId 反查表：用户取消断点时按 (url,line) 找到原 breakpointId 调
  // remove。
  final Map<String, String> _bpIdByKey = <String, String>{};

  Set<({String url, int line})> get userBreakpoints =>
      Set<({String url, int line})>.unmodifiable(_userBreakpoints);

  /// 按 URL+lineNumber 下断点。返回 breakpointId 用于后续 remove。
  Future<String?> setBreakpointByUrl({
    required String url,
    required int lineNumber,
    int columnNumber = 0,
  }) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return null;
    try {
      final r = await cdp.send(
        'Debugger.setBreakpointByUrl',
        params: <String, Object?>{
          'url': url,
          'lineNumber': lineNumber,
          'columnNumber': columnNumber,
        },
        sessionId: _pageSessionId,
      );
      final bp = r['breakpointId'] as String?;
      if (bp != null) {
        _userBreakpoints.add((url: url, line: lineNumber));
        _bpIdByKey['$url#$lineNumber'] = bp;
        _safeNotify();
      }
      return bp;
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', 'setBreakpointByUrl', error, stack);
      return null;
    }
  }

  /// 持久化数据下发：恢复之前持久化的断点（dashboard 启动 / 浏览器重启用）。
  Future<void> restoreBreakpoints(Iterable<({String url, int line})> bps) async {
    for (final b in bps) {
      await setBreakpointByUrl(url: b.url, lineNumber: b.line);
    }
  }

  Future<bool> removeBreakpoint(String breakpointId) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    try {
      await cdp.send(
        'Debugger.removeBreakpoint',
        params: <String, Object?>{'breakpointId': breakpointId},
        sessionId: _pageSessionId,
      );
      _bpIdByKey.removeWhere((_, v) => v == breakpointId);
      _userBreakpoints.removeWhere(
        (b) => !_bpIdByKey.containsKey('${b.url}#${b.line}'),
      );
      _safeNotify();
      return true;
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', 'removeBreakpoint', error, stack);
      return false;
    }
  }

  /// 便捷封装：按 (url,line) 查 breakpointId 再 remove。Breakpoints 面板用。
  Future<bool> removeBreakpointAt({required String url, required int line}) async {
    final id = _bpIdByKey['$url#$line'];
    if (id == null) return false;
    return removeBreakpoint(id);
  }

  Future<bool> resumeDebugger() async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    try {
      await cdp.send('Debugger.resume', sessionId: _pageSessionId);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ─── 异常 / XHR 断点 ─────────────────────────────────────────────────
  // `Debugger.setPauseOnExceptions` 与 `DOMDebugger.setXHRBreakpoint` —— 让
  // breakpoint 面板可以拦截抛出的异常 与 任意子串匹配的 XHR/fetch。XHR
  // 断点服务端只接受字符串子串匹配（空串 = 拦截所有 XHR）；用户输入直接传。
  String _pauseOnExceptions = 'none'; // 'none' | 'uncaught' | 'all'
  final Set<String> _xhrBreakpoints = <String>{};

  String get pauseOnExceptions => _pauseOnExceptions;
  Set<String> get xhrBreakpoints => Set<String>.unmodifiable(_xhrBreakpoints);

  Future<bool> setPauseOnExceptions(String state) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    if (state != 'none' && state != 'uncaught' && state != 'all') return false;
    try {
      await cdp.send(
        'Debugger.setPauseOnExceptions',
        params: <String, Object?>{'state': state},
        sessionId: _pageSessionId,
      );
      _pauseOnExceptions = state;
      _safeNotify();
      return true;
    } catch (e, st) {
      silentLog('web_reverse_session_controller', 'setPauseOnExceptions', e, st);
      return false;
    }
  }

  Future<bool> addXhrBreakpoint(String urlSubstring) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    try {
      await cdp.send(
        'DOMDebugger.setXHRBreakpoint',
        params: <String, Object?>{'url': urlSubstring},
        sessionId: _pageSessionId,
      );
      _xhrBreakpoints.add(urlSubstring);
      _safeNotify();
      return true;
    } catch (e, st) {
      silentLog('web_reverse_session_controller', 'addXhrBreakpoint', e, st);
      return false;
    }
  }

  Future<bool> removeXhrBreakpoint(String urlSubstring) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    try {
      await cdp.send(
        'DOMDebugger.removeXHRBreakpoint',
        params: <String, Object?>{'url': urlSubstring},
        sessionId: _pageSessionId,
      );
      _xhrBreakpoints.remove(urlSubstring);
      _safeNotify();
      return true;
    } catch (e, st) {
      silentLog('web_reverse_session_controller', 'removeXhrBreakpoint', e, st);
      return false;
    }
  }

  /// 简易 JS 美化：单遍扫描，按 `{` `}` `;` `,` 缩进 / 换行。
  /// 不引入新依赖；牺牲 prettier 的精度换取零依赖、纯 Dart 实现。
  /// 输入超长（>= 2MB）时直接返回原文，避免阻塞 UI。
  static String prettifyJs(String src) {
    if (src.length >= 2 * 1024 * 1024) return src;
    final out = StringBuffer();
    var indent = 0;
    var inString = false;
    var stringChar = '';
    var prev = '';
    var inLineComment = false;
    var inBlockComment = false;
    void newline() {
      out.write('\n');
      out.write('  ' * indent);
    }

    for (var i = 0; i < src.length; i++) {
      final c = src[i];
      final next = i + 1 < src.length ? src[i + 1] : '';
      if (inLineComment) {
        out.write(c);
        if (c == '\n') {
          inLineComment = false;
          out.write('  ' * indent);
        }
        prev = c;
        continue;
      }
      if (inBlockComment) {
        out.write(c);
        if (c == '*' && next == '/') {
          out.write(next);
          i++;
          inBlockComment = false;
        }
        prev = c;
        continue;
      }
      if (!inString) {
        if (c == '/' && next == '/') {
          inLineComment = true;
          out.write(c);
          continue;
        }
        if (c == '/' && next == '*') {
          inBlockComment = true;
          out.write(c);
          continue;
        }
      }
      if (inString) {
        out.write(c);
        if (c == stringChar && prev != r'\') inString = false;
      } else {
        if (c == '"' || c == "'" || c == '`') {
          inString = true;
          stringChar = c;
          out.write(c);
        } else if (c == '{') {
          out.write(c);
          indent++;
          newline();
        } else if (c == '}') {
          indent = (indent - 1).clamp(0, 100);
          newline();
          out.write(c);
        } else if (c == ';') {
          out.write(c);
          newline();
        } else if (c == ',') {
          out.write(c);
          // 简单启发式：嵌套深度 > 0 时换行，避免一行参数列表也炸开。
          if (indent > 0) newline();
        } else if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
          // 跳过空白；indent 自带缩进。
          if (out.isNotEmpty && out.toString().codeUnits.last != 0x20 && out.toString().codeUnits.last != 0x0a) {
            out.write(' ');
          }
        } else {
          out.write(c);
        }
      }
      prev = c;
    }
    return out.toString();
  }

  /// 持久化注入到所有请求的 extra HTTP headers（CDP `Network.setExtraHTTPHeaders`）。
  /// 调用方传整张 map；空 map 表示清空。
  final Map<String, String> _extraHeaders = <String, String>{};
  Map<String, String> get extraHeaders =>
      Map<String, String>.unmodifiable(_extraHeaders);

  Future<bool> setExtraHttpHeaders(Map<String, String> headers) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    try {
      await cdp.send(
        'Network.setExtraHTTPHeaders',
        params: <String, Object?>{'headers': headers},
        sessionId: _pageSessionId,
      );
      _extraHeaders
        ..clear()
        ..addAll(headers);
      _safeNotify();
      return true;
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'setExtraHttpHeaders',
        error,
        stack,
      );
      return false;
    }
  }

  /// Anti-bot 检测：扫描已采集的请求 / 响应头 / 现 origin cookies 中的
  /// 常见反爬指纹（Cloudflare / Akamai / DataDome / PerimeterX / Imperva 等），
  /// 返回命中标签列表，UI 据此弹"反爬警告"。
  ///
  /// 仅做关键字 / cookie 名 / 头字段名匹配；不联网。
  List<String> detectAntiBot() {
    final hits = <String>{};
    final reqs = _networkRequests;
    void scanHeaders(Map<String, String> h) {
      h.forEach((k, v) {
        final ck = k.toLowerCase();
        final cv = v.toLowerCase();
        if (ck.contains('cf-ray') || cv.contains('cloudflare')) {
          hits.add('Cloudflare');
        }
        if (ck.contains('x-akamai-') ||
            cv.contains('akamai') ||
            ck.startsWith('akamai-')) {
          hits.add('Akamai');
        }
        if (ck.contains('x-datadome-') || ck == 'x-datadome') {
          hits.add('DataDome');
        }
        if (ck.contains('x-px-') || cv.contains('perimeterx')) {
          hits.add('PerimeterX');
        }
        if (ck.contains('x-iinfo') || cv.contains('imperva')) {
          hits.add('Imperva');
        }
        if (ck == 'set-cookie') {
          if (v.contains('__cf_bm') || v.contains('cf_clearance')) {
            hits.add('Cloudflare');
          }
          if (v.contains('_abck') || v.contains('bm_sz')) {
            hits.add('Akamai');
          }
          if (v.contains('datadome')) hits.add('DataDome');
          if (v.contains('_pxhd') || v.contains('_pxvid')) {
            hits.add('PerimeterX');
          }
          if (v.contains('incap_ses') || v.contains('visid_incap_')) {
            hits.add('Imperva');
          }
        }
      });
    }

    for (final e in reqs) {
      scanHeaders(e.requestHeaders);
      scanHeaders(e.responseHeaders);
      final url = e.url.toLowerCase();
      if (url.contains('cf-challenge') || url.contains('challenge-platform')) {
        hits.add('Cloudflare');
      }
      if (url.contains('captcha-delivery.com') || url.contains('datadome')) {
        hits.add('DataDome');
      }
      if (url.contains('px-cdn.net') || url.contains('perimeterx.net')) {
        hits.add('PerimeterX');
      }
    }
    return hits.toList(growable: false);
  }

  /// 启动一个本地 HAR 重放 mock server，把当前 artifacts 目录下的 HAR 1.2
  /// 文档作为只读源；返回 (port, entryCount)；失败返回 null。
  /// 调用方拿到 port 后用 `127.0.0.1:<port>/<原 path+query>` 即可命中 mock。
  Future<({int port, int entryCount})?> startHarReplayServer() async {
    if (_harReplayServer != null) {
      return (port: _harReplayServer!.port, entryCount: _harReplayServer!.entryCount);
    }
    try {
      // 优先用 in-flight artifacts；为空时生成一个临时 HAR。
      String? path = _lastHarPath;
      path ??= await _artifacts.exportHar();
      if (path == null) return null;
      final bytes = await File(path).readAsBytes();
      final s = await WebReverseHarReplayServer.start(harBytes: bytes);
      if (s == null) return null;
      _harReplayServer = s;
      _safeNotify();
      return (port: s.port, entryCount: s.entryCount);
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', 'startHarReplayServer', error, stack);
      return null;
    }
  }

  Future<void> stopHarReplayServer() async {
    final s = _harReplayServer;
    if (s == null) return;
    _harReplayServer = null;
    _safeNotify();
    await s.close();
  }

  // ── mitmproxy 桥接：抓 OpenHand 控制不到的流量（App 内嵌 webview / 第三方应用） ─
  WebReverseMitmproxyBridge? _mitmBridge;
  StreamSubscription<Map<String, Object?>>? _mitmSub;
  WebReverseMitmproxyBridge? get mitmproxyBridge => _mitmBridge;
  int _mitmCount = 0;
  int get mitmproxyCount => _mitmCount;

  Future<({int mitmPort, int callbackPort})?> startMitmproxyBridge({
    int mitmPort = 8080,
  }) async {
    if (_mitmBridge != null) {
      return (
        mitmPort: _mitmBridge!.mitmPort,
        callbackPort: _mitmBridge!.callbackPort,
      );
    }
    final br = await WebReverseMitmproxyBridge.start(mitmPort: mitmPort);
    if (br == null) return null;
    _mitmBridge = br;
    _mitmCount = 0;
    _mitmSub = br.eventStream.listen((m) {
      _mitmCount++;
      // 把 mitmproxy 流量也注入 dashboard 的网络列表，统一观察口径。
      // 这里只取核心字段做轻量适配；body 已 base64 缓存到 cachedBody 备查。
      final kind = '${m['kind'] ?? ''}';
      final url = '${m['url'] ?? ''}';
      if (url.isEmpty) return;
      if (kind == 'request') {
        final entry = CdpNetworkEntry(
          requestId: 'mitm-${m['ts'] ?? _mitmCount}',
          url: url,
          method: '${m['method'] ?? 'GET'}',
          timestamp: DateTime.now(),
          resourceType: 'mitmproxy',
        );
        final headers = (m['headers'] as List?) ?? const [];
        for (final h in headers.whereType<List>()) {
          if (h.length >= 2) {
            entry.requestHeaders['${h[0]}'] = '${h[1]}';
          }
        }
        final bodyB64 = m['body_b64'] as String?;
        if (bodyB64 != null && bodyB64.isNotEmpty) {
          try {
            entry.requestPostData = utf8.decode(base64Decode(bodyB64));
          } catch (_) {}
        }
        _networkRequests.add(entry);
        _networkByRequestId[entry.requestId] = entry;
        while (_networkRequests.length > _maxNetworkEntries) {
          final removed = _networkRequests.removeAt(0);
          _networkByRequestId.remove(removed.requestId);
        }
      } else if (kind == 'response') {
        // 找最近一条同 url 的 mitm 请求并补响应。
        final match = _networkRequests.lastWhere(
          (e) => e.url == url && e.requestId.startsWith('mitm-'),
          orElse: () => CdpNetworkEntry(
            requestId: 'mitm-resp-${m['ts'] ?? _mitmCount}',
            url: url,
            method: 'GET',
            timestamp: DateTime.now(),
            resourceType: 'mitmproxy',
          )..requestHeaders.clear(),
        );
        match.statusCode = (m['status'] as num?)?.toInt();
        final headers = (m['headers'] as List?) ?? const [];
        for (final h in headers.whereType<List>()) {
          if (h.length >= 2) {
            match.responseHeaders['${h[0]}'] = '${h[1]}';
          }
        }
        match.responseReceivedAt = DateTime.now();
        match.loadingFinishedAt = match.responseReceivedAt;
        final bodyB64 = m['body_b64'] as String?;
        if (bodyB64 != null && bodyB64.isNotEmpty) {
          match.cachedBody = bodyB64;
          match.cachedBodyBase64 = true;
        }
        if (!_networkByRequestId.containsKey(match.requestId)) {
          _networkRequests.add(match);
          _networkByRequestId[match.requestId] = match;
        }
      }
      _safeNotify();
    });
    _safeNotify();
    return (mitmPort: br.mitmPort, callbackPort: br.callbackPort);
  }

  Future<void> stopMitmproxyBridge() async {
    final br = _mitmBridge;
    if (br == null) return;
    _mitmBridge = null;
    await _mitmSub?.cancel();
    _mitmSub = null;
    _safeNotify();
    await br.close();
  }

  /// 一键打包"体检报告"：把 artifacts 目录下所有 jsonl/HAR/截图 +
  /// recorder steps + 当前 networkRequests 概要写到一个 .zip 临时文件，
  /// 返回输出路径。失败返回 null。
  Future<String?> exportSessionBundle({String? destPath}) async {
    final src = Directory(artifactsRootDir);
    if (!await src.exists()) return null;
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final out = File(
      destPath ?? '${Directory.systemTemp.path}/oh-web-reverse-bundle-$ts.zip',
    );
    try {
      // 这里直接用 zip 工具命令行，跨平台都有：macOS / Linux 用 zip；
      // Windows 用 PowerShell Compress-Archive。失败时降级为复制目录。
      if (Platform.isMacOS || Platform.isLinux) {
        final r = await Process.run(
          'zip',
          ['-r', out.path, src.path.split('/').last],
          workingDirectory: src.parent.path,
        );
        if (r.exitCode != 0) {
          silentLog(
            'web_reverse_session_controller',
            'zip exitCode=${r.exitCode}',
            r.stderr,
            StackTrace.current,
          );
          return null;
        }
      } else if (Platform.isWindows) {
        final r = await Process.run(
          'powershell',
          [
            '-Command',
            'Compress-Archive -Path "${src.path}\\*" -DestinationPath "${out.path}" -Force',
          ],
        );
        if (r.exitCode != 0) {
          silentLog(
            'web_reverse_session_controller',
            'Compress-Archive exitCode=${r.exitCode}',
            r.stderr,
            StackTrace.current,
          );
          return null;
        }
      }
      return out.path;
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', 'exportSessionBundle', error, stack);
      return null;
    }
  }

  /// 拉取指定请求的 response body（CDP `Network.getResponseBody`）。
  /// 自动缓存到 entry.cachedBody，重复点击不再发请求。
  /// 文本类返回 (body, false)，二进制类返回 (base64, true)；失败返回 null。
  Future<(String, bool)?> fetchResponseBody(String requestId) async {
    final entry = _networkByRequestId[requestId];
    if (entry == null) return null;
    if (entry.cachedBody != null) {
      return (entry.cachedBody!, entry.cachedBodyBase64);
    }
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return null;
    try {
      final result = await cdp.send(
        'Network.getResponseBody',
        params: <String, Object?>{'requestId': requestId},
        sessionId: _pageSessionId,
      );
      final body = '${result['body'] ?? ''}';
      final base64 = result['base64Encoded'] == true;
      entry.cachedBody = body;
      entry.cachedBodyBase64 = base64;
      return (body, base64);
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'fetchResponseBody $requestId',
        error,
        stack,
      );
      return null;
    }
  }

  /// 立即导出当前 HAR 草稿。返回写出路径或 null。
  /// 调用后 in-memory drafts 仍保留，stop() 时会再导一份；用户从 dashboard 手动触发用。
  Future<String?> exportHarNow() async {
    final path = await _artifacts.exportHar();
    if (path != null) {
      _lastHarPath = path;
      _safeNotify();
    }
    return path;
  }

  /// 把当前 HAR 写到用户选定路径（来自 file_selector）；返回写出路径或 null。
  Future<String?> exportHarToPath(String destPath) async {
    final src = await _artifacts.exportHar();
    if (src == null) return null;
    try {
      await File(src).copy(destPath);
      _lastHarPath = destPath;
      _safeNotify();
      return destPath;
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'exportHarToPath copy',
        error,
        stack,
      );
      return null;
    }
  }

  /// 反向加载：把外部 HAR 1.2 文档解析回 _networkRequests，便于离线复盘。
  /// 默认替换当前实时请求；当 [merge]=true 时将解析结果按 startedDateTime 时序
  /// 合并到现有列表中并保持总数 ≤ [_maxNetworkEntries]。不影响 artifacts 文件本身。
  /// 返回 (loaded, skipped)。
  ({int loaded, int skipped}) loadHarBytes(
    List<int> bytes, {
    bool merge = false,
  }) {
    try {
      final raw = utf8.decode(bytes);
      final har = jsonDecode(raw);
      if (har is! Map) return (loaded: 0, skipped: 0);
      final log = har['log'] as Map?;
      final entries = log?['entries'] as List?;
      if (entries == null) return (loaded: 0, skipped: 0);
      // 解析所有 entry 到候选列表；merge=false 时清空旧表后按解析顺序回填，
      // merge=true 时与现有列表按时间归并并 dedup。
      final candidates = <CdpNetworkEntry>[];
      var loaded = 0;
      var skipped = 0;
      for (var i = 0; i < entries.length; i++) {
        final raw = entries[i];
        if (raw is! Map) {
          skipped++;
          continue;
        }
        final req = raw['request'] as Map?;
        final res = raw['response'] as Map?;
        if (req == null) {
          skipped++;
          continue;
        }
        final url = '${req['url'] ?? ''}';
        final method = '${req['method'] ?? 'GET'}';
        final reqHeaders = <String, String>{};
        for (final h in (req['headers'] as List? ?? const [])
            .whereType<Map>()) {
          reqHeaders['${h['name'] ?? ''}'] = '${h['value'] ?? ''}';
        }
        final resHeaders = <String, String>{};
        for (final h in (res?['headers'] as List? ?? const [])
            .whereType<Map>()) {
          resHeaders['${h['name'] ?? ''}'] = '${h['value'] ?? ''}';
        }
        final startedRaw = '${raw['startedDateTime'] ?? ''}';
        DateTime started;
        try {
          started = DateTime.parse(startedRaw);
        } catch (_) {
          started = DateTime.now().toUtc().subtract(
                Duration(milliseconds: entries.length - i),
              );
        }
        final timeMs = (raw['time'] as num?)?.toInt() ?? 0;
        // requestId 在 merge 时必须避免与现有 / 同批次冲突；用 ts 后缀保证唯一。
        final reqId = merge
            ? 'har-${started.microsecondsSinceEpoch}-$i'
            : 'har-$i';
        final entry = CdpNetworkEntry(
          requestId: reqId,
          url: url,
          method: method,
          timestamp: started,
          resourceType:
              _resourceTypeFromMime('${res?['content']?['mimeType'] ?? ''}'),
        )
          ..requestHeaders = reqHeaders
          ..requestPostData = (req['postData'] as Map?)?['text'] as String?
          ..responseHeaders = resHeaders
          ..statusCode = (res?['status'] as num?)?.toInt()
          ..statusText = res?['statusText'] as String?
          ..mimeType = '${res?['content']?['mimeType'] ?? ''}'
          ..encodedDataLength = (res?['bodySize'] as num?)?.toInt()
          ..responseReceivedAt =
              started.add(Duration(milliseconds: timeMs ~/ 2))
          ..loadingFinishedAt = started.add(Duration(milliseconds: timeMs));
        candidates.add(entry);
        loaded++;
      }
      if (!merge) {
        _networkRequests.clear();
        _networkByRequestId.clear();
        for (final e in candidates) {
          _networkByRequestId[e.requestId] = e;
          _networkRequests.add(e);
        }
      } else {
        // 合并：按 timestamp 升序插入；超出容量时 FIFO 砍头。
        final combined = <CdpNetworkEntry>[
          ..._networkRequests,
          ...candidates,
        ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        if (combined.length > _maxNetworkEntries) {
          combined.removeRange(0, combined.length - _maxNetworkEntries);
        }
        _networkRequests
          ..clear()
          ..addAll(combined);
        _networkByRequestId
          ..clear()
          ..addEntries(combined.map((e) => MapEntry(e.requestId, e)));
      }
      _safeNotify();
      return (loaded: loaded, skipped: skipped);
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', 'loadHarBytes', error, stack);
      return (loaded: 0, skipped: 0);
    }
  }

  static String _resourceTypeFromMime(String mime) {
    final m = mime.toLowerCase();
    if (m.startsWith('image/')) return 'Image';
    if (m.contains('javascript')) return 'Script';
    if (m.contains('json')) return 'Fetch';
    if (m.contains('css')) return 'Stylesheet';
    if (m.contains('html')) return 'Document';
    if (m.contains('font')) return 'Font';
    if (m.startsWith('audio/') || m.startsWith('video/')) return 'Media';
    return 'Other';
  }

  @override
  void dispose() {
    _disposed = true;
    for (final t in _cronTimers.values) {
      t.cancel();
    }
    _cronTimers.clear();
    // 不阻塞 dispose；safeStop 内部所有调用都已对 _disposed 做了短路。
    unawaited(_safeStop());
    screencastFrameNotifier.dispose();
    super.dispose();
  }

  /// dispose 后再 notifyListeners 会抛 assertion。所有内部状态变更点统一走
  /// 这一层，避免任何回调（CDP 事件 / 异步收尾）在 controller 已 dispose
  /// 后再触发监听器。
  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }
}

/// 单条网络请求的精简快照，dashboard 用它渲染。
///
/// 字段量按 Chrome DevTools「请求详情」侧栏 5 个 tab 的需要补齐：
/// - Headers: requestHeaders / responseHeaders / statusCode / remoteAddress
/// - Preview / Response: 通过 controller.fetchResponseBody 异步拉取
/// - Initiator: initiatorType / initiatorStack
/// - Timing: requestSentAt / responseReceivedAt / loadingFinishedAt /
///           encodedDataLength / decodedBodyLength
class CdpNetworkEntry {
  CdpNetworkEntry({
    required this.requestId,
    required this.url,
    required this.method,
    required this.timestamp,
    required this.resourceType,
  });

  final String requestId;
  // url / method 在重定向链中会被更新为最新的目标地址（CDP 对同一
  // requestId 会再次推 `Network.requestWillBeSent` 并带 `redirectResponse`，
  // 这时 request.url 已是下一跳）。`timestamp` / `resourceType` 仍是首跳。
  String url;
  String method;
  final DateTime timestamp;
  final String resourceType;

  /// 请求侧。
  Map<String, String> requestHeaders = const <String, String>{};
  String? requestPostData;

  /// 响应侧（来自 Network.responseReceived）。
  int? statusCode;
  String? statusText;
  String? mimeType;
  Map<String, String> responseHeaders = const <String, String>{};
  String? remoteAddress;
  String? protocol;
  bool fromCache = false;
  int? encodedDataLength;
  int? decodedBodyLength;

  /// Initiator（脚本调用栈，CDP 提供）。
  String? initiatorType; // parser / script / preflight / other
  String? initiatorUrl;
  int? initiatorLineNumber;
  int? initiatorColumnNumber;
  List<Map<String, Object?>> initiatorStack = const <Map<String, Object?>>[];

  /// 重定向链：每一次 3xx 跳转都会被 CDP 用 `redirectResponse` 推给同一
  /// requestId，按时间顺序记录历史响应（URL / status / headers）。Chrome
  /// DevTools 的 "Request Initiator Chain" 区段就是渲染这个数据。
  final List<CdpRedirectStep> redirectChain = <CdpRedirectStep>[];

  /// CDP `Network.ResourceTiming` 原始快照（response.timing）。各字段为
  /// 相对 `requestTime`（秒）的毫秒偏移，requestTime 自身是单调时钟秒。
  /// 用于 Timing tab 还原 Chrome 风格的阶段瀑布图。
  Map<String, num>? resourceTiming;

  /// Timing 字段（绝对时刻；时长由 dashboard 计算差值）。
  DateTime? responseReceivedAt;
  DateTime? loadingFinishedAt;

  bool failed = false;
  String? errorText;

  /// dashboard 拉过的 response body 缓存（一次取后保留，避免 CDP 多次访问）。
  /// 仅在用户点 Preview / Response tab 时填。
  String? cachedBody;
  bool cachedBodyBase64 = false;

  /// WebSocket 专属：帧序列（双向）。CDP 通过 `Network.webSocketFrameSent` /
  /// `webSocketFrameReceived` 推；非 WS 请求始终为空。
  final List<CdpWebSocketFrame> wsFrames = <CdpWebSocketFrame>[];

  bool get isWebSocket =>
      resourceType.toLowerCase() == 'websocket' ||
      resourceType.toLowerCase() == 'eventsource';

  bool get isError =>
      failed || (statusCode != null && statusCode! >= 400);
}

/// 一条 WebSocket 帧（发送 / 接收 / 错误）。`payload` 截断到 8KB 防止内存爆。
class CdpWebSocketFrame {
  CdpWebSocketFrame({
    required this.direction,
    required this.timestamp,
    required this.opcode,
    required this.mask,
    required this.payload,
    this.errorMessage,
  });

  final CdpWebSocketDirection direction;
  final DateTime timestamp;
  final int opcode; // 1=text, 2=binary, 8=close, 9=ping, 10=pong
  final bool mask;
  final String payload;
  final String? errorMessage;
}

enum CdpWebSocketDirection { sent, received, error }

/// 单条重定向响应（CDP `redirectResponse`）。在请求被 3xx 跳转时，CDP 会
/// 把每一跳的旧响应作为下一次 `requestWillBeSent` 的 `redirectResponse`
/// 字段推过来，我们顺序累加到 [CdpNetworkEntry.redirectChain] 给 UI 渲染
/// "Request Initiator Chain"。
class CdpRedirectStep {
  CdpRedirectStep({
    required this.url,
    required this.status,
    required this.statusText,
    required this.responseHeaders,
    required this.at,
  });
  final String url;
  final int? status;
  final String? statusText;
  final Map<String, String> responseHeaders;
  final DateTime at;
}

/// 单条控制台消息的精简快照。
class CdpConsoleEntry {
  CdpConsoleEntry({
    required this.level,
    required this.text,
    required this.timestamp,
  });
  final String level;
  final String text;
  final DateTime timestamp;
}

/// CDP 网络节流预设，对标 DevTools 的 Throttling 下拉。
enum WebReverseThrottlePreset {
  none(
    label: 'No throttling',
    isOffline: false,
    latencyMs: 0,
    downloadKbps: -1,
    uploadKbps: -1,
  ),
  offline(
    label: 'Offline',
    isOffline: true,
    latencyMs: 0,
    downloadKbps: 0,
    uploadKbps: 0,
  ),
  slow3g(
    label: 'Slow 3G',
    isOffline: false,
    latencyMs: 2000,
    downloadKbps: 500,
    uploadKbps: 500,
  ),
  fast3g(
    label: 'Fast 3G',
    isOffline: false,
    latencyMs: 562,
    downloadKbps: 1500,
    uploadKbps: 750,
  );

  const WebReverseThrottlePreset({
    required this.label,
    required this.isOffline,
    required this.latencyMs,
    required this.downloadKbps,
    required this.uploadKbps,
  });

  final String label;
  final bool isOffline;
  final int latencyMs;
  final int downloadKbps;
  final int uploadKbps;

  Map<String, Object?> get cdpParams => <String, Object?>{
        'offline': isOffline,
        'latency': latencyMs,
        'downloadThroughput': downloadKbps < 0 ? -1 : downloadKbps * 1024 / 8,
        'uploadThroughput': uploadKbps < 0 ? -1 : uploadKbps * 1024 / 8,
      };
}


/// CDP page target 的精简快照，给 dashboard 浏览器面板的 tab strip 渲染用。
class CdpPageTargetSnapshot {
  const CdpPageTargetSnapshot({
    required this.id,
    required this.url,
    required this.title,
  });

  final String id;
  final String url;
  final String title;
}


/// 一条网络拦截规则：URL 通配匹配后对请求 block 或 rewrite。
/// `urlPattern` 支持 `*` 任意段、`?` 单字符；不区分大小写。
class WebReverseInterceptRule {
  const WebReverseInterceptRule({
    required this.urlPattern,
    this.enabled = true,
    this.block = false,
    this.replaceUrl,
    this.headerOverrides = const <String, String>{},
  });

  factory WebReverseInterceptRule.fromJson(Map<String, Object?> j) =>
      WebReverseInterceptRule(
        urlPattern: '${j['urlPattern'] ?? ''}',
        enabled: j['enabled'] != false,
        block: j['block'] == true,
        replaceUrl:
            j['replaceUrl'] is String ? j['replaceUrl'] as String : null,
        headerOverrides: (j['headerOverrides'] as Map?)
                ?.map((k, v) => MapEntry('$k', '$v')) ??
            const <String, String>{},
      );

  final String urlPattern;
  final bool enabled;
  final bool block;
  final String? replaceUrl;
  final Map<String, String> headerOverrides;

  WebReverseInterceptRule copyWith({
    String? urlPattern,
    bool? enabled,
    bool? block,
    String? replaceUrl,
    Map<String, String>? headerOverrides,
  }) =>
      WebReverseInterceptRule(
        urlPattern: urlPattern ?? this.urlPattern,
        enabled: enabled ?? this.enabled,
        block: block ?? this.block,
        replaceUrl: replaceUrl ?? this.replaceUrl,
        headerOverrides: headerOverrides ?? this.headerOverrides,
      );

  bool matches(String url) {
    if (urlPattern.isEmpty) return false;
    final regexSrc = urlPattern
        .split(RegExp(r'([*?])'))
        .map(RegExp.escape)
        .join()
        .replaceAll(r'\*', '.*')
        .replaceAll(r'\?', '.');
    return RegExp('^$regexSrc\$', caseSensitive: false).hasMatch(url);
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'urlPattern': urlPattern,
        'enabled': enabled,
        'block': block,
        if (replaceUrl != null) 'replaceUrl': replaceUrl,
        'headerOverrides': headerOverrides,
      };
}


/// 一档设备模拟预设：尺寸 + DPR + UA + mobile flag。
class WebReverseDevicePreset {
  const WebReverseDevicePreset({
    required this.id,
    required this.label,
    required this.width,
    required this.height,
    required this.deviceScaleFactor,
    required this.mobile,
    this.userAgent,
  });

  final String id;
  final String label;
  final int width;
  final int height;
  final double deviceScaleFactor;
  final bool mobile;
  final String? userAgent;

  static const mobile375 = WebReverseDevicePreset(
    id: 'mobile',
    label: 'Mobile (iPhone 13 mini)',
    width: 375,
    height: 812,
    deviceScaleFactor: 3,
    mobile: true,
    userAgent:
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
  );

  static const tablet768 = WebReverseDevicePreset(
    id: 'tablet',
    label: 'Tablet (iPad)',
    width: 768,
    height: 1024,
    deviceScaleFactor: 2,
    mobile: true,
    userAgent:
        'Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
  );

  static const desktop1440 = WebReverseDevicePreset(
    id: 'desktop',
    label: 'Desktop (1440)',
    width: 1440,
    height: 900,
    deviceScaleFactor: 2,
    mobile: false,
  );
}


/// 切 tab 时的 panel 缓冲快照。仅在 controller 内部使用，存进
/// _targetBuffers map（LRU 8 槽）保留每个 page target 上次离开时的现场。
/// 字段都按 tab 维度独立，不影响其它 tab；switchToPageTarget 切回时整体
/// 灌回 controller 的活动缓冲。
class _PerTargetBuffer {
  _PerTargetBuffer({
    required this.networkRequests,
    required this.networkByRequestId,
    required this.consoleMessages,
    required this.parsedScripts,
    required this.scriptSources,
    required this.bpIdByKey,
    required this.lastUsedAt,
  });

  final List<CdpNetworkEntry> networkRequests;
  final Map<String, CdpNetworkEntry> networkByRequestId;
  final List<CdpConsoleEntry> consoleMessages;
  final Map<String, ({String url, bool isModule})> parsedScripts;
  final Map<String, String> scriptSources;
  final Map<String, String> bpIdByKey;
  final DateTime lastUsedAt;
}


/// 用户保存的 JS 片段（脚本注入库）。`runReplExpression` 执行后结果
/// 进入 Console 面板；持久化由 dashboard 写入 session metadata。
class WebReverseSnippet {
  const WebReverseSnippet({
    required this.id,
    required this.name,
    required this.code,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String code;
  final DateTime? updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'code': code,
        'updated_ms': updatedAt?.millisecondsSinceEpoch,
      };

  factory WebReverseSnippet.fromJson(Map<String, Object?> json) {
    final ms = json['updated_ms'];
    return WebReverseSnippet(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? 'untitled'}',
      code: '${json['code'] ?? ''}',
      updatedAt: ms is int ? DateTime.fromMillisecondsSinceEpoch(ms) : null,
    );
  }
}

/// 用户保存的 JS Hook（每个文档加载前注入）。
class WebReverseHook {
  const WebReverseHook({
    required this.id,
    required this.name,
    required this.code,
    required this.enabled,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String code;
  final bool enabled;
  final DateTime? updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'code': code,
        'enabled': enabled,
        'updated_ms': updatedAt?.millisecondsSinceEpoch,
      };

  factory WebReverseHook.fromJson(Map<String, Object?> json) {
    final ms = json['updated_ms'];
    return WebReverseHook(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? 'untitled'}',
      code: '${json['code'] ?? ''}',
      enabled: json['enabled'] != false,
      updatedAt: ms is int ? DateTime.fromMillisecondsSinceEpoch(ms) : null,
    );
  }
}

class WebReverseCron {
  const WebReverseCron({
    required this.id,
    required this.name,
    required this.code,
    required this.intervalSeconds,
    required this.enabled,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String code;
  final int intervalSeconds;
  final bool enabled;
  final DateTime? updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'code': code,
        'interval_s': intervalSeconds,
        'enabled': enabled,
        'updated_ms': updatedAt?.millisecondsSinceEpoch,
      };

  factory WebReverseCron.fromJson(Map<String, Object?> json) {
    final ms = json['updated_ms'];
    final iv = json['interval_s'];
    return WebReverseCron(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? 'untitled'}',
      code: '${json['code'] ?? ''}',
      intervalSeconds: iv is int && iv >= 1 ? iv : 60,
      enabled: json['enabled'] == true,
      updatedAt: ms is int ? DateTime.fromMillisecondsSinceEpoch(ms) : null,
    );
  }
}

// ─── DOM 路径 JS 函数体 ────────────────────────────────────────────────
// 由 `domCssSelectorForNode` / `domXPathForNode` 通过 `Runtime.callFunctionOn`
// 注入到目标对象上执行。注意 `this` 即对应 DOM node。

const String _kCssSelectorFn = r'''
function() {
  function seg(el) {
    if (!el || el.nodeType !== 1) return '';
    if (el.id) return '#' + CSS.escape(el.id);
    let name = el.localName;
    const parent = el.parentNode;
    if (!parent || parent.nodeType !== 1) return name;
    const siblings = Array.from(parent.children).filter(c => c.localName === name);
    if (siblings.length === 1) return name;
    const idx = siblings.indexOf(el) + 1;
    return name + ':nth-of-type(' + idx + ')';
  }
  const parts = [];
  let cur = this;
  while (cur && cur.nodeType === 1 && cur !== document.documentElement) {
    const s = seg(cur);
    if (!s) break;
    parts.unshift(s);
    if (s.startsWith('#')) return parts.join(' > ');
    cur = cur.parentNode;
  }
  parts.unshift('html');
  return parts.join(' > ');
}
''';

const String _kXPathFn = r'''
function() {
  function ix(el) {
    let i = 1;
    let sib = el.previousElementSibling;
    while (sib) {
      if (sib.localName === el.localName) i++;
      sib = sib.previousElementSibling;
    }
    return i;
  }
  const parts = [];
  let cur = this;
  while (cur && cur.nodeType === 1) {
    if (cur.id) {
      parts.unshift('//*[@id="' + cur.id + '"]');
      break;
    }
    parts.unshift(cur.localName + '[' + ix(cur) + ']');
    cur = cur.parentElement;
  }
  return '/' + parts.join('/');
}
''';

