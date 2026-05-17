import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../app/support/silent_log.dart';
import 'web_reverse_browser_kind.dart';
import 'web_reverse_browser_launcher.dart';
import 'web_reverse_cdp_client.dart';
import 'web_reverse_har_replay_server.dart';
import 'web_reverse_mitmproxy_bridge.dart';
import 'web_reverse_session_artifacts.dart';
import 'web_reverse_session_config.dart';
import 'web_reverse_window_dock.dart';

/// 单个 Web 逆向会话的运行时编排：浏览器进程、CDP 通道、窗口吸附、
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
    WebReverseWindowDock? dock,
    WebReverseSessionArtifacts? artifacts,
  })  : _launcher = launcher ?? WebReverseBrowserLauncher(),
        _dock = dock,
        _artifacts =
            artifacts ?? WebReverseSessionArtifacts(rootDir: artifactsRootDir);

  final WebReverseSessionConfig config;
  final String executablePath;

  /// 会话工作目录，默认 `~/.openhand/web_reverse/<session_id>`。
  /// 落盘的 jsonl / HAR / 截图都放这里，方便模型 Bash 读取。
  final String artifactsRootDir;

  final WebReverseBrowserLauncher _launcher;
  WebReverseWindowDock? _dock;
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
      // 启动窗口吸附。
      _dock ??= WebReverseWindowDock(
        browserAppName: _browserAppNameFor(config.browserKind),
      );
      _dock!.start();
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
    final attachResult = await cdp.send(
      'Target.attachToTarget',
      params: <String, Object?>{
        'targetId': targetId,
        'flatten': true,
      },
    );
    _pageSessionId = attachResult['sessionId'] as String?;
    // 启用相关 domain。给 Network 加大 buffer 让 getResponseBody 能拿到大文本。
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
    // 把 browser CDP 的事件流接到 dashboard 缓冲。
    _pageEventsSub = cdp.events
        .where((ev) => ev.sessionId == null || ev.sessionId == _pageSessionId)
        .listen(_onCdpEvent);
  }

  void _onCdpEvent(CdpEvent ev) {
    switch (ev.method) {
      case '__cdp_reconnected__':
        // CDP 抖动断开后自动重连成功 → 重新 enable 各 domain。
        // 不阻塞事件循环，全部 fire-and-forget。
        unawaited(_reattachAfterReconnect());
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
      silentLog('web_reverse_session_controller', 'listDomStorage', error, stack);
      return const [];
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
    final entry = CdpNetworkEntry(
      requestId: requestId,
      url: url,
      method: method,
      timestamp: DateTime.now(),
      resourceType: '${p['type'] ?? 'Other'}',
    )
      ..requestHeaders = headers
      ..requestPostData = request['postData'] as String?;
    final initiator = p['initiator'] as Map?;
    if (initiator != null) {
      entry.initiatorType = initiator['type'] as String?;
      entry.initiatorUrl = initiator['url'] as String?;
      entry.initiatorLineNumber = (initiator['lineNumber'] as num?)?.toInt();
      final stack = initiator['stack'] as Map?;
      final frames = stack?['callFrames'] as List?;
      if (frames != null) {
        entry.initiatorStack = frames
            .whereType<Map>()
            .map((f) => Map<String, Object?>.from(f))
            .toList(growable: false);
      }
    }
    _networkByRequestId[requestId] = entry;
    _networkRequests.add(entry);
    while (_networkRequests.length > _maxNetworkEntries) {
      final old = _networkRequests.removeAt(0);
      _networkByRequestId.remove(old.requestId);
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
    if (!_preserveLog) {
      _networkRequests.clear();
      _networkByRequestId.clear();
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

  Future<void> _safeStop() async {
    _dock?.stop();
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
      if (!_disposed) screencastFrameNotifier.value = 0;
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
      if (buf.length > 500) buf.splice(0, buf.length - 500);
    } catch (_) {}
  };
  const Orig = window.RTCPeerConnection || window.webkitRTCPeerConnection;
  if (!Orig) return;
  let nextId = 1;
  function patched(...args) {
    const pc = new Orig(...args);
    const id = nextId++;
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
    });
    pc.addEventListener('iceconnectionstatechange', () => {
      log('iceconnectionstatechange', { id, state: pc.iceConnectionState });
    });
    return pc;
  }
  patched.prototype = Orig.prototype;
  window.RTCPeerConnection = patched;
  if (window.webkitRTCPeerConnection) window.webkitRTCPeerConnection = patched;
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
      // 屏幕已被 Flutter 端 screencast 接管渲染：暂停外部窗口吸附 + 把
      // 真实浏览器窗口最小化，避免两套画面同时出现。
      _dock?.stop();
      unawaited(_dock?.hideBrowserWindow());
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
    if (!_disposed) screencastFrameNotifier.value = 0;
    // 还原外部浏览器窗口与吸附线程，让用户可以继续用真实浏览器。
    unawaited(_dock?.showBrowserWindow());
    _dock?.start();
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
    _pendingFetchRequests[requestId] = <String, Object?>{
      'method': request['method'],
      'url': request['url'],
      'ts': DateTime.now().toUtc().toIso8601String(),
    };
    _safeNotify();
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
  Future<({int status, String body})?> replayRequest(
    CdpNetworkEntry e,
  ) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return null;
    final init = <String, Object?>{
      'method': e.method,
      if (e.requestHeaders.isNotEmpty)
        'headers': e.requestHeaders.map((k, v) => MapEntry(k, v)),
      if (e.requestPostData != null) 'body': e.requestPostData,
      'credentials': 'include',
    };
    final js = '''
(async () => {
  try {
    const r = await fetch(${jsonEncode(e.url)}, ${jsonEncode(init)});
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
      return r['breakpointId'] as String?;
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', 'setBreakpointByUrl', error, stack);
      return null;
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
      return true;
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', 'removeBreakpoint', error, stack);
      return false;
    }
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

  String _browserAppNameFor(WebReverseBrowserKind k) {
    return switch (k) {
      WebReverseBrowserKind.chrome => 'Google Chrome',
      WebReverseBrowserKind.chromeBeta => 'Google Chrome Beta',
      WebReverseBrowserKind.edge => 'Microsoft Edge',
      WebReverseBrowserKind.brave => 'Brave Browser',
      WebReverseBrowserKind.chromium => 'Chromium',
    };
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
  final String url;
  final String method;
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
  List<Map<String, Object?>> initiatorStack = const <Map<String, Object?>>[];

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
