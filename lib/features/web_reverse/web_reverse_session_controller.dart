import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';

import '../../app/support/safe_subprocess.dart';
import '../../app/support/silent_log.dart';
import '../../shared/util/async_concurrency.dart';
import '../../shared/util/byte_size_format.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/lifecycle_cache.dart';
import '../../shared/util/localized_text.dart';
import '../../shared/util/text_clip.dart';
import '../../shared/util/timer_safety.dart';
import 'web_reverse_browser_launcher.dart';
import 'web_reverse_cdp_client.dart';
import 'web_reverse_cdp_http.dart';
import 'web_reverse_har_io.dart';
import 'web_reverse_har_replay_server.dart';
import 'web_reverse_mitmproxy_bridge.dart';
import 'web_reverse_pure_helpers.dart';
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
  }) : _launcher = launcher ?? WebReverseBrowserLauncher(),
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
  bool _notifierDisposed = false;
  bool _resourcesStopped = false;
  bool _preserveLog = true;
  bool _reattachAfterReconnectInFlight = false;
  bool _reattachAfterReconnectQueued = false;
  Future<void>? _restartBrowserTask;
  Future<void>? _safeStopTask;
  Future<void>? _shutdownFuture;
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

  bool get isRunning => _started && !_stopped && isBrowserAlive;

  /// 真实判定外部浏览器进程是否还活着。CDP WebSocket 自身有重连，但当
  /// `_closed=true` 时表示重连已彻底失败 → 浏览器多半被用户手动关掉了。
  /// `isRunning` 只在浏览器 CDP 仍可用时为真，断连后 UI / Prompt 都应
  /// 明确进入可重启状态，而不是继续暴露一个已经失效的运行中端口。
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
  int get cdpConnectionGeneration =>
      _browserCdp == null ? 0 : identityHashCode(_browserCdp);

  // ── Dashboard 数据缓冲 ────────────────────────────────────────────────
  // 目标：让 UI 用 ListenableBuilder 直接拉数据，CDP 事件 → 这里 → UI。
  // 容量上限保护：单条会话累计可能上万请求，超过 [_maxNetworkEntries] 后
  // FIFO 淘汰，避免内存膨胀。Dashboard 弹窗里也支持"清空"按钮主动复位。

  static const int _maxNetworkEntries = 2000;
  static const int _maxConsoleEntries = 2000;
  static const int _maxWebSocketFramesPerEntry = 2000;
  static const int _maxWebSocketFramePayloadChars = 8192;
  static const int _maxHeapSnapshotChars = 120 * 1024 * 1024;
  static const int _maxTraceEvents = 120000;
  static const int _maxTracePayloadChars = 48 * 1024 * 1024;
  static const int _maxScreenshotBase64Chars = 64 * 1024 * 1024;
  static const int _maxRawCdpParamsJsonChars = 2 * 1024 * 1024;
  static const int maxReplExpressionChars = 2 * 1024 * 1024;
  static const int _maxReplHistoryExpressionChars = 64 * 1024;
  static const int _maxReplPreviewChars = 2048;
  static const int _maxConsoleTextChars = 64 * 1024;
  static const int maxSavedScriptCodeChars = maxReplExpressionChars;
  static const int maxSavedScriptNameChars = 120;
  static const int maxSavedSnippets = 200;
  static const int maxSavedHooks = 100;
  static const int maxSavedCrons = 100;
  static const int minCronIntervalSeconds = 5;
  static const int maxCronIntervalSeconds = 24 * 60 * 60;
  static const int _maxImportedUrlChars = 16 * 1024;
  static const int _maxImportedBodyChars = 2 * 1024 * 1024;
  static const int _maxImportedHeaderValueChars = 16 * 1024;
  static const int _maxSourceMapCacheEntries = 16;
  static const int _maxSourceMapCacheChars = 32 * kBytesPerMiB;
  static const int _maxSourceMapResponseBytes = 16 * kBytesPerMiB;
  static const int _maxSourceMapResultChars =
      _maxSourceMapResponseBytes + 64 * kBytesPerKiB;
  static const int _maxSourceMapListEntries = 100000;
  static const Duration _sourceMapFetchTimeout = Duration(seconds: 25);
  static const int _maxParsedScripts = 4096;
  static const int _maxScriptSourceChars = 6 * kBytesPerMiB;
  static const int _maxScriptSourceCacheEntries = 32;
  static const int _maxScriptSourceCacheChars = 16 * kBytesPerMiB;
  static const int _maxTargetBufferSourceChars = 32 * kBytesPerMiB;
  static const int maxBlockedUrlPatterns = 512;
  static const int maxSourceBreakpoints = 512;
  static const int maxXhrBreakpoints = 256;
  static const int maxEventListenerBreakpoints = 256;
  static const int maxDomBreakpoints = 256;
  static const int maxWatchExpressions = 256;
  static const int maxAccountSnapshots = 16;
  static const int maxInterceptRules = 256;
  static const int maxMockRules = 256;
  static const int maxRequestBreakpoints = 256;
  static const int maxBreakpointTextChars = 16 * kBytesPerKiB;
  static const int maxDebuggerExpressionChars = 64 * kBytesPerKiB;
  static const int maxRuleIdChars = 256;
  static const int maxRuleNameChars = 256;
  static const int maxRuleMethodChars = 32;
  static const int maxRuleContentTypeChars = 512;
  static const int maxRuleHeaderEntries = 128;
  static const int maxRuleHeaderNameChars = 256;
  static const int maxRuleHeaderValueChars = 16 * kBytesPerKiB;
  static const int maxRuleHeadersChars = 256 * kBytesPerKiB;
  static const int maxMockBodyChars = 2 * kBytesPerMiB;
  static const int maxRuleCollectionChars = 16 * kBytesPerMiB;
  static const int maxRuleImportChars = 16 * kBytesPerMiB;
  static const int maxRecorderSteps = 5000;
  static const int maxRecorderStepTextChars = 64 * kBytesPerKiB;
  static const int maxRecorderCollectionChars = 16 * kBytesPerMiB;
  static const int maxRecorderImportBytes = 16 * kBytesPerMiB;
  static const int maxPendingFetchRequests = 200;
  static const int fetchInterceptPendingTimeoutSeconds = 60;
  static const int maxEditedRequestBodyChars = 2 * kBytesPerMiB;
  static const int maxEditedRequestBodyBase64Chars = 8 * kBytesPerMiB;
  static const int maxAccountSnapshotNameChars = 256;
  static const int maxAccountSnapshotCookies = 512;
  static const int maxAccountSnapshotStorageEntries = 2048;
  static const int maxAccountSnapshotValueChars = 256 * kBytesPerKiB;
  static const int maxAccountSnapshotChars = 4 * kBytesPerMiB;
  static const int maxAccountSnapshotsTotalChars = 16 * kBytesPerMiB;
  static const int _accountSnapshotRestoreConcurrency = 4;
  static const Duration _accountSnapshotCommandTimeout = Duration(seconds: 3);
  static const Duration _accountSnapshotRestoreTimeout = Duration(seconds: 45);
  static const Set<String> _fetchErrorReasons = <String>{
    'Failed',
    'Aborted',
    'TimedOut',
    'AccessDenied',
    'ConnectionClosed',
    'ConnectionReset',
    'ConnectionRefused',
    'ConnectionAborted',
    'ConnectionFailed',
    'NameNotResolved',
    'InternetDisconnected',
    'AddressUnreachable',
    'BlockedByClient',
    'BlockedByResponse',
  };
  static const double _maxFullPageScreenshotCssPixels = 32 * 1000 * 1000;
  static const double _maxFullPageScreenshotCssSide = 32767;
  static final RegExp _rawCdpMethodPattern = RegExp(
    r'^[A-Za-z][A-Za-z0-9_.]*$',
  );

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

  /// 公共 CDP 事件广播：所有进入 [_onCdpEvent] 的事件都会同步推到这条流，
  /// 给独立的 dialog 面板（Issues / Layers / 自定义订阅）按需 listen 用。
  /// Broadcast stream，多个订阅者互不干扰；controller dispose 时一并关。
  final StreamController<CdpEvent> _rawCdpEventBus =
      StreamController<CdpEvent>.broadcast();

  /// 监听原始 CDP 事件（method + params），适合做按需启用的扩展面板。
  Stream<CdpEvent> get rawCdpEvents => _rawCdpEventBus.stream;

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
  DateTime? _screencastStartedAt;
  DateTime? _lastScreencastFrameAt;

  /// 当前最新一帧（JPEG 字节）；切到浏览器 tab 后 widget 用 [Image.memory] 渲染。
  Uint8List? get latestScreencastFrame => _latestScreencastFrame;

  /// 帧序号（自增），widget 用作 key 触发 [Image.memory] 重绘。
  int get screencastFrameSeq => _screencastFrameSeq;

  /// 当前帧的浏览器视口尺寸（CSS 像素）。
  int get screencastWidth => _screencastWidth;
  int get screencastHeight => _screencastHeight;

  bool get isScreencastActive => _screencastActive;

  /// 最近一次成功发送 `Page.startScreencast` 的时间。
  DateTime? get screencastStartedAt => _screencastStartedAt;

  /// 上次帧到达时间，UI 用来判断"是否长时间无帧"以提示用户。
  DateTime? get lastScreencastFrameAt => _lastScreencastFrameAt;

  // ── 生命周期 ─────────────────────────────────────────────────────────

  static const int _kInitialTargetPickAttempts = 16;
  static const Duration _kInitialTargetPickDelay = Duration(milliseconds: 150);
  static const Duration _browserStopGrace = Duration(milliseconds: 500);
  static const Duration _browserCleanupTimeout = Duration(seconds: 3);

  Future<void> start() async {
    if (_disposed) {
      throw StateError('Web reverse session has been disposed');
    }
    if (_started) return;
    _started = true;
    _resourcesStopped = false;
    try {
      await _artifacts.init();
      if (_stopped || _disposed) {
        _started = false;
        await _safeStop();
        return;
      }
      _launchResult = await _launcher.launch(
        executablePath: executablePath,
        browserKind: config.browserKind,
        userDataDir: config.userDataDir,
        startUrl: config.targetUrl,
        proxy: config.proxy,
      );
      if (_stopped || _disposed) {
        _started = false;
        await _safeStop();
        return;
      }
      _browserCdp = WebReverseCdpClient(
        endpoint: _launchResult!.webSocketDebuggerUrl,
      );
      await _browserCdp!.connect();
      if (_stopped || _disposed) {
        _started = false;
        await _safeStop();
        return;
      }
      // attach 到目标 page target，订阅其网络 / 控制台事件。
      await _attachToFirstPage();
      if (_stopped || _disposed) {
        _started = false;
        await _safeStop();
        return;
      }
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
    // 列出所有 page target，优先挑 config.targetUrl 同 origin 的目标页。
    // Chrome 冷启动时可能先暴露 about:blank / 恢复页；短暂轮询后仍未命中
    // 再回退到第一个可用 page，避免无限等待。
    List<Object?> infos = const <Object?>[];
    Map<String, Object?>? chosen;
    for (var attempt = 0; attempt < _kInitialTargetPickAttempts; attempt++) {
      final targets = await cdp.send('Target.getTargets');
      infos = (targets['targetInfos'] as List?) ?? const <Object?>[];
      chosen = _chooseInitialPageTarget(
        infos,
        allowFallback: attempt == _kInitialTargetPickAttempts - 1,
      );
      if (chosen != null) {
        break;
      }
      await Future<void>.delayed(_kInitialTargetPickDelay);
    }
    if (chosen == null) {
      throw CdpException(
        code: -1,
        message: openHandLocalizedTextForLocaleName(
          Platform.localeName,
          zh: '未发现目标 page target；浏览器可能没有打开目标页面',
          zhHant: '未發現目標 page target；瀏覽器可能沒有開啟目標頁面',
          en: 'No target page target was found. The browser may not have opened the target page.',
          fr: 'Aucune cible page target trouvée. Le navigateur n’a peut-être pas ouvert la page cible.',
          de: 'Kein Ziel-page target gefunden. Der Browser hat die Zielseite möglicherweise nicht geöffnet.',
          ja: '対象の page target が見つかりません。ブラウザで対象ページが開かれていない可能性があります。',
        ),
      );
    }
    final targetId = '${chosen['targetId'] ?? ''}';
    if (targetId.isEmpty) {
      throw CdpException(
        code: -1,
        message: openHandLocalizedTextForLocaleName(
          Platform.localeName,
          zh: '目标 page target 缺少 targetId',
          zhHant: '目標 page target 缺少 targetId',
          en: 'The target page target is missing targetId.',
          fr: 'La cible page target ne contient pas targetId.',
          de: 'Dem Ziel-page target fehlt targetId.',
          ja: '対象の page target に targetId がありません。',
        ),
      );
    }
    // 订阅 page target 的创建 / 销毁 / 信息变化，让 dashboard 实时更新 tab strip。
    await cdp.send(
      'Target.setDiscoverTargets',
      params: const <String, Object?>{'discover': true},
    );
    await _attachToTargetInternal(targetId);
    // 首次拉满当前所有 page target。
    _refreshTargetsFromInfos(infos);
  }

  Map<String, Object?>? _chooseInitialPageTarget(
    List<Object?> infos, {
    required bool allowFallback,
  }) {
    final pages = infos
        .whereType<Map>()
        .where((t) => t['type'] == 'page')
        .map((t) => Map<String, Object?>.from(t))
        .where((t) => '${t['targetId'] ?? ''}'.isNotEmpty)
        .toList(growable: false);
    if (pages.isEmpty) return null;

    final targetUri = _tryHttpUri(config.targetUrl);
    if (targetUri != null) {
      for (final page in pages) {
        final pageUri = _tryHttpUri('${page['url'] ?? ''}');
        if (pageUri != null && _sameHttpOrigin(pageUri, targetUri)) {
          return page;
        }
      }
      if (!allowFallback) return null;
    }

    for (final page in pages) {
      if (_isUsefulInitialPageUrl('${page['url'] ?? ''}')) {
        return page;
      }
    }
    return allowFallback || targetUri == null ? pages.first : null;
  }

  Uri? _tryHttpUri(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.host.isEmpty) return null;
    final scheme = uri.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https' ? uri : null;
  }

  bool _sameHttpOrigin(Uri a, Uri b) {
    return a.scheme.toLowerCase() == b.scheme.toLowerCase() &&
        a.host.toLowerCase() == b.host.toLowerCase() &&
        _effectiveHttpPort(a) == _effectiveHttpPort(b);
  }

  int _effectiveHttpPort(Uri uri) {
    if (uri.hasPort) return uri.port;
    return uri.scheme.toLowerCase() == 'https' ? 443 : 80;
  }

  bool _isUsefulInitialPageUrl(String raw) {
    final value = raw.trim().toLowerCase();
    return value.isNotEmpty &&
        value != 'about:blank' &&
        value != 'chrome://newtab' &&
        value != 'chrome://newtab/';
  }

  /// 多标签页：dashboard 浏览器面板的 tab strip 数据源。每条 entry 反映一个
  /// CDP page target，包含 id / url / title / favicon。
  final List<CdpPageTargetSnapshot> _pageTargets = <CdpPageTargetSnapshot>[];
  String? _currentTargetId;

  /// 每个 page target 的 panel 缓冲快照：切走时保存，切回时
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
      networkByRequestId: Map<String, CdpNetworkEntry>.from(
        _networkByRequestId,
      ),
      consoleMessages: List<CdpConsoleEntry>.from(_consoleMessages),
      parsedScripts: Map<String, ({String url, bool isModule})>.from(
        _parsedScripts,
      ),
      scriptSources: _scriptSources.snapshot(),
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
    _scriptSources.clear();
    for (final entry in saved.scriptSources.entries) {
      _scriptSources.put(entry.key, entry.value);
    }
    _bpIdByKey
      ..clear()
      ..addAll(saved.bpIdByKey);
  }

  void _evictOldestTargetBuffers() {
    var sourceChars = _targetBuffers.values.fold<int>(
      0,
      (total, buffer) => total + buffer.scriptSourceChars,
    );
    if (_targetBuffers.length <= _kTargetBufferLruCap &&
        sourceChars <= _maxTargetBufferSourceChars) {
      return;
    }
    final entries = _targetBuffers.entries.toList()
      ..sort((a, b) => a.value.lastUsedAt.compareTo(b.value.lastUsedAt));
    while ((_targetBuffers.length > _kTargetBufferLruCap ||
            sourceChars > _maxTargetBufferSourceChars) &&
        entries.isNotEmpty) {
      final oldest = entries.removeAt(0);
      final removed = _targetBuffers.remove(oldest.key);
      if (removed != null) sourceChars -= removed.scriptSourceChars;
    }
  }

  void _refreshTargetsFromInfos(List<dynamic> infos) {
    _pageTargets.clear();
    for (final t in infos.whereType<Map>()) {
      if (t['type'] != 'page') continue;
      _pageTargets.add(
        CdpPageTargetSnapshot(
          id: '${t['targetId'] ?? ''}',
          url: '${t['url'] ?? ''}',
          title: '${t['title'] ?? ''}',
        ),
      );
    }
    _safeNotify();
  }

  Future<void> _attachToTargetInternal(String targetId) async {
    final cdp = _browserCdp!;
    // 切换前主动 detach 旧 session（如果有），避免事件流叠加。
    if (_pageSessionId != null) {
      _clearPendingFetchRequests();
      try {
        await cdp.send(
          'Target.detachFromTarget',
          params: <String, Object?>{'sessionId': _pageSessionId},
        );
      } catch (error, stack) {
        silentLog(
          'web_reverse_session_controller',
          'detach old target',
          error,
          stack,
        );
      }
      _pageSessionId = null;
    }
    // 新 page 上 finder 还没注入；切完 target 第一次 findInPage 会按需注入。
    _finderInstalled = false;
    _longTaskObserverInstalled = false;
    _rtcInstalled = false;
    _zoomScriptId = null;
    // Per-tab buffer：切 tab 前先把当前 target 的 panel 缓冲
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
      params: <String, Object?>{'targetId': targetId, 'flatten': true},
    );
    _pageSessionId = attachResult['sessionId'] as String?;
    _currentTargetId = targetId;
    // 还原该 target 上次切走时保存的 panel 缓冲。新 target /
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
    await _restoreNetworkDomainState();
    // 当前 target 换了，上轮拿到的 hook scriptId 在新 target 上
    // 无意义，重新沿着新 _pageSessionId 装载 enabled hook。
    await _reapplyEnabledHooks();
    await _cancelRuntimeSubscription(_pageEventsSub, 'replace page events');
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
      } catch (error, stack) {
        silentLog(
          'web_reverse_session_controller',
          'stop screencast before target switch',
          error,
          stack,
        );
      }
      _screencastActive = false;
      _screencastStartedAt = null;
      _lastScreencastFrameAt = null;
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
        _screencastStartedAt = DateTime.now();
      } catch (error, stack) {
        silentLog(
          'web_reverse_session_controller',
          'restart screencast after target switch',
          error,
          stack,
        );
      }
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
    // 先广播给外部订阅者，再走内置 dispatch；广播失败不影响内部处理。
    if (!_rawCdpEventBus.isClosed) {
      try {
        _rawCdpEventBus.add(ev);
      } catch (e, st) {
        silentLog(
          'web_reverse_session_controller',
          'rawCdpEventBus.add',
          e,
          st,
        );
      }
    }
    switch (ev.method) {
      case '__cdp_reconnected__':
        // CDP 抖动断开后自动重连成功 → 重新 enable 各 domain。
        // 串行化 reattach，避免连续重连事件互相覆盖 page sessionId。
        _scheduleReattachAfterReconnect();
        return;
      case '__cdp_dead__':
        // 重连彻底失败：浏览器可能已经被用户手动关掉。把 screencast 状态
        // 复位、清掉缓存帧、通知 UI 切到"已断开 / 可重启"占位。
        _resetScreencastRuntimeState(resetRefCount: false);
        _clearPendingFetchRequests(resetEnabled: true);
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
      case 'Debugger.paused':
        _onDebuggerPaused(ev.params);
      case 'Debugger.resumed':
        _onDebuggerResumed();
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
      return metrics
          .whereType<Map>()
          .map((m) {
            final n = '${m['name'] ?? ''}';
            final v = doubleFromValue(m['value'], fallback: 0);
            return (n, v);
          })
          .toList(growable: false);
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'performanceMetrics',
        error,
        stack,
      );
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
    var totalChars = 0;
    var tooLarge = false;
    StreamSubscription<CdpEvent>? sub;
    try {
      await cdp.send('HeapProfiler.enable', sessionId: _pageSessionId);
      sub = cdp.events.where((e) => e.sessionId == _pageSessionId).listen((e) {
        if (e.method == 'HeapProfiler.addHeapSnapshotChunk') {
          final chunk = '${e.params['chunk'] ?? ''}';
          totalChars += chunk.length;
          if (totalChars <= _maxHeapSnapshotChars) {
            buffer.write(chunk);
          } else {
            tooLarge = true;
            if (!completer.isCompleted) completer.complete();
          }
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
      if (tooLarge) return null;
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
      await _cancelRuntimeSubscription(sub, 'heap snapshot events');
    }
  }

  /// 跑一次 `Performance.startTrace` / `stopTrace` 并返回 trace JSON 字符串。
  /// CDP 把 trace 通过 dataCollected 事件分块推；本方法做完整收集。
  ///
  /// 传入 [earlyStop]（任一 Future 完成即提前结束）即可在 UI 上提供 Stop。
  Future<String?> recordTrace({
    required Duration duration,
    List<String> categories = const [
      'devtools.timeline',
      'v8.execute',
      'disabled-by-default-devtools.timeline',
    ],
    Future<void>? earlyStop,
  }) async {
    final cdp = _browserCdp;
    if (cdp == null) return null; // tracing 用 root session
    final events = <Map<String, Object?>>[];
    var seenEvents = 0;
    var droppedEvents = 0;
    var tracePayloadChars = 0;
    var traceCapped = false;
    final completer = Completer<void>();
    StreamSubscription<CdpEvent>? sub;
    try {
      sub = cdp.events.listen((e) {
        if (e.method == 'Tracing.dataCollected') {
          final list = e.params['value'] as List?;
          if (list != null) {
            for (final item in list.whereType<Map>()) {
              seenEvents += 1;
              if (traceCapped) {
                droppedEvents += 1;
                continue;
              }
              final mapped = stringKeyedMapFromValue(item);
              final estimatedChars = mapped.toString().length;
              if (events.length >= _maxTraceEvents ||
                  tracePayloadChars + estimatedChars > _maxTracePayloadChars) {
                traceCapped = true;
                droppedEvents += 1;
                continue;
              }
              tracePayloadChars += estimatedChars;
              events.add(mapped);
            }
          }
        } else if (e.method == 'Tracing.tracingComplete') {
          if (!completer.isCompleted) completer.complete();
        }
      });
      await cdp.send(
        'Tracing.start',
        params: <String, Object?>{
          'categories': categories.join(','),
          'transferMode': 'ReportEvents',
        },
      );
      final timeout = Future<void>.delayed(duration);
      if (earlyStop != null) {
        await Future.any(<Future<void>>[timeout, earlyStop]);
      } else {
        await timeout;
      }
      await cdp.send('Tracing.end');
      await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {},
      );
      return jsonEncode(<String, Object?>{
        'traceEvents': events,
        'metadata': <String, Object?>{
          'source': 'OpenHand WebReverseExpert',
          'duration_ms': duration.inMilliseconds,
          'events_seen': seenEvents,
          'events_recorded': events.length,
          'events_dropped': droppedEvents,
          'events_capped': traceCapped,
          'event_count_cap': _maxTraceEvents,
          'payload_chars_cap': _maxTracePayloadChars,
        },
      });
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', 'recordTrace', error, stack);
      return null;
    } finally {
      await _cancelRuntimeSubscription(sub, 'performance trace events');
    }
  }

  // ── Application: Cookies / Storage ───────────────────────────────────

  Future<List<Map<String, Object?>>> listCookies() async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return const [];
    try {
      final r = await cdp.send(
        'Network.getAllCookies',
        sessionId: _pageSessionId,
      );
      final list = r['cookies'] as List?;
      return list == null
          ? const <Map<String, Object?>>[]
          : stringKeyedMapListFromValue(list);
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
        'web_reverse_session_controller',
        'listDomStorage',
        error,
        stack,
      );
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
        'web_reverse_session_controller',
        'deleteCookie $name',
        error,
        stack,
      );
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
        'web_reverse_session_controller',
        'setCookie $name',
        error,
        stack,
      );
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
        'web_reverse_session_controller',
        'setDomStorageItem',
        error,
        stack,
      );
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
        'web_reverse_session_controller',
        'removeDomStorageItem',
        error,
        stack,
      );
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
      final value = cdpResultValue(r);
      return value is String ? value : null;
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'currentOrigin',
        error,
        stack,
      );
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
  Future<({String name, int version, List<String> stores})?> describeIndexedDb(
    String dbName,
  ) async {
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
      final db = stringKeyedMapFromValue(r['databaseWithObjectStores']);
      if (db.isEmpty) return null;
      final version = nonNegativeIntFromValue(db['version'], fallback: 0);
      final stores =
          (db['objectStores'] as List?)
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
      final entries = stringKeyedMapListFromValue(list);
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

  /// `IndexedDB.clearObjectStore` —— 清空指定 store 全部记录。失败返回 false。
  Future<bool> clearIndexedDbStore({
    required String dbName,
    required String storeName,
  }) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    try {
      final origin = await currentOrigin();
      if (origin == null) return false;
      await cdp.send(
        'IndexedDB.clearObjectStore',
        params: <String, Object?>{
          'securityOrigin': origin,
          'databaseName': dbName,
          'objectStoreName': storeName,
        },
        sessionId: _pageSessionId,
        timeout: const Duration(seconds: 10),
      );
      return true;
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'clearIndexedDbStore $dbName/$storeName',
        error,
        stack,
      );
      return false;
    }
  }

  /// `IndexedDB.deleteObjectStoreEntries` —— 删除指定 key 的单条记录。
  /// CDP 协议要求 keyRange 用 `{lower, upper, lowerOpen, upperOpen}` 结构；
  /// 这里构造为 `[key, key]` 闭区间精准命中一条。
  /// key 走 IndexedDB.Key 结构：`{type: 'string'|'number'|'date'|'array', value, ...}`。
  Future<bool> deleteIndexedDbEntry({
    required String dbName,
    required String storeName,
    required Map<String, Object?> key,
  }) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    try {
      final origin = await currentOrigin();
      if (origin == null) return false;
      await cdp.send(
        'IndexedDB.deleteObjectStoreEntries',
        params: <String, Object?>{
          'securityOrigin': origin,
          'databaseName': dbName,
          'objectStoreName': storeName,
          'keyRange': <String, Object?>{
            'lower': key,
            'upper': key,
            'lowerOpen': false,
            'upperOpen': false,
          },
        },
        sessionId: _pageSessionId,
        timeout: const Duration(seconds: 10),
      );
      return true;
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'deleteIndexedDbEntry $dbName/$storeName',
        error,
        stack,
      );
      return false;
    }
  }

  /// `IndexedDB.deleteDatabase` —— 删除整个数据库。
  Future<bool> deleteIndexedDb(String dbName) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    try {
      final origin = await currentOrigin();
      if (origin == null) return false;
      await cdp.send(
        'IndexedDB.deleteDatabase',
        params: <String, Object?>{
          'securityOrigin': origin,
          'databaseName': dbName,
        },
        sessionId: _pageSessionId,
        timeout: const Duration(seconds: 10),
      );
      return true;
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'deleteIndexedDb $dbName',
        error,
        stack,
      );
      return false;
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
      await _cancelRuntimeSubscription(sub, 'service worker events');
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
      silentLog(
        'web_reverse_session_controller',
        'enableSecurity',
        error,
        stack,
      );
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
  final ListQueue<Map<String, Object?>> _recorderSteps =
      ListQueue<Map<String, Object?>>();
  int _recorderStepsChars = 0;
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
      _recorderStepsChars = 0;
      _recording = true;
      _safeNotify();
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'startRecording',
        error,
        stack,
      );
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
      } catch (error, stack) {
        silentLog(
          'web_reverse_session_controller',
          'remove recorder script',
          error,
          stack,
        );
      }
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
      } catch (error, stack) {
        silentLog(
          'web_reverse_session_controller',
          'remove recorder overlay',
          error,
          stack,
        );
      }
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
    final steps = List<Map<String, Object?>>.of(
      _recorderSteps,
      growable: false,
    );
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
      final v = cdpResultValue(r);
      return v is bool ? v : null;
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'eval bool expression',
        error,
        stack,
      );
      return null;
    }
  }

  /// 把一条断言追加到 _recorderSteps（让 UI 直接添加，不依赖浏览器 console）。
  void addAssertionStep(
    String type, {
    required String selector,
    String? expected,
  }) {
    _appendRecorderStep(<String, Object?>{
      'type': type,
      'selector': selector,
      if (expected != null) 'expected': expected,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 替换当前 step 列表（导入 JSON 用）。
  void setRecorderSteps(List<Map<String, Object?>> steps) {
    _recorderSteps.clear();
    _recorderStepsChars = 0;
    final start = steps.length > maxRecorderSteps
        ? steps.length - maxRecorderSteps
        : 0;
    for (final step in steps.skip(start)) {
      _appendRecorderStep(step, notify: false);
    }
    _safeNotify();
  }

  bool _appendRecorderStep(Map<String, Object?> step, {bool notify = true}) {
    final normalized = _normalizeRecorderStep(step);
    if (normalized == null) return false;
    final cost = _estimatedRecorderStepChars(normalized);
    while (_recorderSteps.isNotEmpty &&
        (_recorderSteps.length >= maxRecorderSteps ||
            _recorderStepsChars + cost > maxRecorderCollectionChars)) {
      _recorderStepsChars -= _estimatedRecorderStepChars(
        _recorderSteps.removeFirst(),
      );
    }
    if (_recorderStepsChars + cost > maxRecorderCollectionChars) return false;
    _recorderSteps.add(normalized);
    _recorderStepsChars += cost;
    if (notify) _safeNotify();
    return true;
  }

  /// 清空 step 列表。
  void clearRecorderSteps() {
    _recorderSteps.clear();
    _recorderStepsChars = 0;
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
    final redirect = stringKeyedMapFromValue(p['redirectResponse']);
    CdpNetworkEntry entry;
    if (existing != null && redirect.isNotEmpty) {
      entry = existing
        ..url = url
        ..method = method
        ..requestHeaders = headers
        ..requestPostData = request['postData'] as String?;
      entry.redirectChain.add(
        CdpRedirectStep(
          url: '${redirect['url'] ?? ''}',
          status: optionalIntFromValue(redirect['status']),
          statusText: redirect['statusText'] as String?,
          responseHeaders: _flattenHeaders(redirect['headers']),
          at: DateTime.now(),
        ),
      );
    } else {
      entry =
          CdpNetworkEntry(
              requestId: requestId,
              url: url,
              method: method,
              timestamp: DateTime.now(),
              resourceType: '${p['type'] ?? 'Other'}',
            )
            ..requestHeaders = headers
            ..requestPostData = request['postData'] as String?;
    }
    final initiator = stringKeyedMapFromValue(p['initiator']);
    if (initiator.isNotEmpty) {
      entry.initiatorType = initiator['type'] as String?;
      entry.initiatorUrl = initiator['url'] as String?;
      entry.initiatorLineNumber = optionalIntFromValue(initiator['lineNumber']);
      entry.initiatorColumnNumber = optionalIntFromValue(
        initiator['columnNumber'],
      );
      final stack = stringKeyedMapFromValue(initiator['stack']);
      final frames = stack['callFrames'] as List?;
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
        _artifacts.evictHarDraft(old.requestId);
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
    final response = stringKeyedMapFromValue(p['response']);
    if (response.isEmpty) return;
    final entry = _networkByRequestId[requestId];
    if (entry == null) return;
    final status = optionalIntFromValue(response['status']);
    final mime = '${response['mimeType'] ?? ''}';
    final headers = _flattenHeaders(response['headers']);
    entry
      ..statusCode = status
      ..statusText = response['statusText'] as String?
      ..mimeType = mime
      ..responseHeaders = headers
      ..remoteAddress = _formatRemoteAddress(response)
      ..protocol = response['protocol'] as String?
      ..encodedDataLength = optionalNonNegativeIntFromValue(
        response['encodedDataLength'],
      )
      ..fromCache =
          response['fromDiskCache'] == true ||
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
    final encoded = optionalNonNegativeIntFromValue(p['encodedDataLength']);
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
      _artifacts.evictHarDraft(old.requestId);
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
    final response = stringKeyedMapFromValue(p['response']);
    final opcode = intFromValue(response['opcode'], fallback: 0);
    final mask = response['mask'] == true;
    var payload = '${response['payloadData'] ?? ''}';
    if (payload.length > _maxWebSocketFramePayloadChars) {
      payload = '${payload.substring(0, _maxWebSocketFramePayloadChars)}…';
    }
    entry.wsFrames.add(
      CdpWebSocketFrame(
        direction: direction,
        timestamp: DateTime.now(),
        opcode: opcode,
        mask: mask,
        payload: payload,
        errorMessage: direction == CdpWebSocketDirection.error
            ? '${p['errorMessage'] ?? ''}'
            : null,
      ),
    );
    // 防止单条 WS 累积爆炸。
    while (entry.wsFrames.length > _maxWebSocketFramesPerEntry) {
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
        params: {'expression': 'document.title', 'returnByValue': true},
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
      silentLog('web_reverse_session_controller', '_refreshPageTitle', e, st);
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
    final text = args
        .whereType<Map>()
        .map((a) {
          final v = a['value'];
          return v == null ? (a['description'] ?? '').toString() : v.toString();
        })
        .join(' ');
    // 拦截 recorder 标记，转为 step 列表（不影响 console 列表本身）。
    if (_recording && text.startsWith('__OH_REC__ ')) {
      try {
        final raw = text.substring('__OH_REC__ '.length).trim();
        // 去掉首尾可能的引号，再 JSON.decode。
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _appendRecorderStep(stringKeyedMapFromValue(decoded));
        }
      } catch (error, stack) {
        silentLog(
          'web_reverse_session_controller',
          'decode recorder console step',
          error,
          stack,
        );
      }
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

  /// 2 秒一跳的浏览器存活探针：HTTP GET `/json/version`。任一探测失败立刻
  /// 把 `_browserCdp` 标记为已关闭并触发 `__cdp_dead__` 事件，让 UI 走到
  /// "重启浏览器" 占位。WebSocket 自身的 onDone 会更早触发，这里是兜底。
  void _startAliveWatchdog() {
    _stopAliveWatchdog();
    _aliveWatchdog = startNonOverlappingPeriodicTimer(
      const Duration(seconds: 2),
      (_) async {
        if (_stopped || _disposed) return;
        final port = _launchResult?.cdpPort;
        if (port == null) return;
        final cdp = _browserCdp;
        if (cdp == null || cdp.isClosed) return;
        final client = createWebReverseCdpHttpClient(
          connectionTimeout: const Duration(seconds: 1),
          idleTimeout: const Duration(seconds: 1),
        );
        try {
          final req = await client
              .getUrl(webReverseCdpHttpUri(port, '/json/version'))
              .timeout(const Duration(seconds: 1));
          final res = await req.close().timeout(const Duration(seconds: 1));
          await res.drain<void>().timeout(const Duration(seconds: 1));
        } catch (error, stack) {
          silentLog(
            'web_reverse_session_controller',
            'alive watchdog probe',
            error,
            stack,
          );
          // 浏览器已死：主动关 CDP 触发 __cdp_dead__ 事件路径。
          _stopAliveWatchdog();
          try {
            await _browserCdp?.close();
          } catch (closeError, closeStack) {
            silentLog(
              'web_reverse_session_controller',
              'close dead browser cdp',
              closeError,
              closeStack,
            );
          }
          _resetScreencastRuntimeState(resetRefCount: false);
          _errorMessage = '浏览器已断开（进程异常退出），可点击「重启浏览器」恢复。';
          _safeNotify();
        } finally {
          client.close(force: true);
        }
      },
      onError: (error, stack) => silentLog(
        'web_reverse_session_controller',
        'alive watchdog',
        error,
        stack,
      ),
    );
  }

  void _stopAliveWatchdog() {
    _aliveWatchdog?.cancel();
    _aliveWatchdog = null;
  }

  /// CDP 重连成功后调用：把 Page / Network / Runtime / Log 等 domain 重新 enable，
  /// 同时再次 attach 到 page target，确保事件不丢。
  void _scheduleReattachAfterReconnect() {
    if (_reattachAfterReconnectInFlight) {
      _reattachAfterReconnectQueued = true;
      return;
    }
    _reattachAfterReconnectInFlight = true;
    unawaited(() async {
      try {
        do {
          _reattachAfterReconnectQueued = false;
          await _reattachAfterReconnect();
        } while (_reattachAfterReconnectQueued && !_disposed && !_stopped);
      } finally {
        _reattachAfterReconnectInFlight = false;
      }
    }());
  }

  Future<void> _reattachAfterReconnect() async {
    if (_disposed || _stopped) return;
    final cdp = _browserCdp;
    if (cdp == null) return;
    try {
      // 重新 attach；CDP 重连后 sessionId 失效。
      await _attachToFirstPage();
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
          _screencastStartedAt = DateTime.now();
        } catch (error, stack) {
          silentLog(
            'web_reverse_session_controller',
            'restore screencast after reconnect',
            error,
            stack,
          );
        }
      }
      _appendConsole('info', '[OpenHand] CDP 已自动重连，已恢复网络 / 控制台监听');
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        '_reattachAfterReconnect',
        error,
        stack,
      );
    }
  }

  void _appendConsole(String level, String text) {
    final ts = DateTime.now();
    final cappedText = _capWebReverseText(
      text,
      _maxConsoleTextChars,
      'console text',
    );
    _consoleMessages.add(
      CdpConsoleEntry(level: level, text: cappedText, timestamp: ts),
    );
    while (_consoleMessages.length > _maxConsoleEntries) {
      _consoleMessages.removeAt(0);
    }
    _artifacts.appendConsole(<String, Object?>{
      'level': level,
      'text': cappedText,
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
    final t = _capWebReverseText(
      expr.trim(),
      _maxReplHistoryExpressionChars,
      'REPL history expression',
    );
    if (t.isEmpty) return;
    if (_replHistory.isNotEmpty && _replHistory.last == t) return;
    _replHistory.add(t);
    while (_replHistory.length > _kReplHistoryMax) {
      _replHistory.removeAt(0);
    }
    _safeNotify();
  }

  void replaceReplHistory(List<String> items) {
    final normalized = stringListFromValue(items)
        .map(
          (e) => _capWebReverseText(
            e,
            _maxReplHistoryExpressionChars,
            'REPL history expression',
          ),
        )
        .toList(growable: false);
    final start = normalized.length > _kReplHistoryMax
        ? normalized.length - _kReplHistoryMax
        : 0;
    _replHistory
      ..clear()
      ..addAll(normalized.skip(start));
    _safeNotify();
  }

  // ─── 脚本注入库 (Snippet Pad) ────────────────────────────────────────
  // 用户在「脚本」tab 创建的 JS 代码片段；执行时直接复用 [runReplExpression]，
  // 持久化由 dashboard 写入 session metadata。
  final List<WebReverseSnippet> _snippets = <WebReverseSnippet>[];
  List<WebReverseSnippet> get snippets => List.unmodifiable(_snippets);

  void replaceSnippets(List<WebReverseSnippet> items) {
    final normalized = items
        .where(
          (e) => e.id.isNotEmpty && e.code.length <= maxSavedScriptCodeChars,
        )
        .map(
          (e) => WebReverseSnippet(
            id: _capPlainWebReverseText(e.id, 128),
            name: _normalizeSavedScriptName(e.name),
            code: e.code,
            updatedAt: e.updatedAt,
          ),
        )
        .toList(growable: false);
    final start = normalized.length > maxSavedSnippets
        ? normalized.length - maxSavedSnippets
        : 0;
    _snippets
      ..clear()
      ..addAll(normalized.skip(start));
    _safeNotify();
  }

  WebReverseSnippet addSnippet({required String name, required String code}) {
    final id =
        'snip_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    final s = WebReverseSnippet(
      id: id,
      name: _normalizeSavedScriptName(name),
      code: _capPlainWebReverseText(code, maxSavedScriptCodeChars),
      updatedAt: DateTime.now(),
    );
    _snippets.add(s);
    while (_snippets.length > maxSavedSnippets) {
      _snippets.removeAt(0);
    }
    _safeNotify();
    return s;
  }

  void updateSnippet({required String id, String? name, String? code}) {
    final i = _snippets.indexWhere((e) => e.id == id);
    if (i < 0) return;
    final old = _snippets[i];
    _snippets[i] = WebReverseSnippet(
      id: old.id,
      name: name == null
          ? old.name
          : _normalizeSavedScriptName(name, fallback: old.name),
      code: code == null
          ? old.code
          : _capPlainWebReverseText(code, maxSavedScriptCodeChars),
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
      orElse: () =>
          const WebReverseSnippet(id: '', name: '', code: '', updatedAt: null),
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
    final normalized = items
        .where(
          (e) => e.id.isNotEmpty && e.code.length <= maxSavedScriptCodeChars,
        )
        .map(
          (e) => WebReverseHook(
            id: _capPlainWebReverseText(e.id, 128),
            name: _normalizeSavedScriptName(e.name),
            code: e.code,
            enabled: e.enabled,
            updatedAt: e.updatedAt,
          ),
        )
        .toList(growable: false);
    final start = normalized.length > maxSavedHooks
        ? normalized.length - maxSavedHooks
        : 0;
    for (final old in List<WebReverseHook>.from(_hooks)) {
      await _uninstallHook(old.id);
    }
    _hooks
      ..clear()
      ..addAll(normalized.skip(start));
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
      name: _normalizeSavedScriptName(name),
      code: _capPlainWebReverseText(code, maxSavedScriptCodeChars),
      enabled: true,
      updatedAt: DateTime.now(),
    );
    _hooks.add(h);
    while (_hooks.length > maxSavedHooks) {
      final removed = _hooks.removeAt(0);
      await _uninstallHook(removed.id);
    }
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
      name: name == null
          ? old.name
          : _normalizeSavedScriptName(name, fallback: old.name),
      code: code == null
          ? old.code
          : _capPlainWebReverseText(code, maxSavedScriptCodeChars),
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
    if (h.code.length > maxSavedScriptCodeChars) return;
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
        'web_reverse_session_controller',
        'installHook ${h.name}',
        e,
        st,
      );
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
    final normalized = items
        .where(
          (e) => e.id.isNotEmpty && e.code.length <= maxSavedScriptCodeChars,
        )
        .map(
          (e) => WebReverseCron(
            id: _capPlainWebReverseText(e.id, 128),
            name: _normalizeSavedScriptName(e.name),
            code: e.code,
            intervalSeconds: _normalizeCronInterval(e.intervalSeconds),
            enabled: e.enabled,
            updatedAt: e.updatedAt,
          ),
        )
        .toList(growable: false);
    final start = normalized.length > maxSavedCrons
        ? normalized.length - maxSavedCrons
        : 0;
    for (final t in _cronTimers.values) {
      t.cancel();
    }
    _cronTimers.clear();
    _crons
      ..clear()
      ..addAll(normalized.skip(start));
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
      name: _normalizeSavedScriptName(name),
      code: _capPlainWebReverseText(code, maxSavedScriptCodeChars),
      intervalSeconds: _normalizeCronInterval(intervalSeconds),
      enabled: true,
      updatedAt: DateTime.now(),
    );
    _crons.add(c);
    while (_crons.length > maxSavedCrons) {
      final removed = _crons.removeAt(0);
      _cronTimers.remove(removed.id)?.cancel();
      _cronLastRun.remove(removed.id);
    }
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
      name: name == null
          ? old.name
          : _normalizeSavedScriptName(name, fallback: old.name),
      code: code == null
          ? old.code
          : _capPlainWebReverseText(code, maxSavedScriptCodeChars),
      intervalSeconds: _normalizeCronInterval(
        intervalSeconds ?? old.intervalSeconds,
      ),
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
        id: '',
        name: '',
        code: '',
        intervalSeconds: 0,
        enabled: false,
        updatedAt: null,
      ),
    );
    if (c.id.isEmpty) return null;
    return _executeCronOnce(c);
  }

  void _scheduleCron(WebReverseCron c) {
    _cronTimers.remove(c.id)?.cancel();
    final dur = Duration(seconds: c.intervalSeconds);
    _cronTimers[c.id] = startNonOverlappingPeriodicTimer(
      dur,
      (_) => _executeCronOnce(c),
      onError: (error, stack) => silentLog(
        'web_reverse_session_controller',
        'cron timer ${c.name}',
        error,
        stack,
      ),
    );
  }

  Future<String?> _executeCronOnce(WebReverseCron c) async {
    if (c.code.length > maxSavedScriptCodeChars) return null;
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
      );
      final root = r['root'];
      return root is Map<String, dynamic> ? root : null;
    } catch (e, st) {
      silentLog('web_reverse_session_controller', 'domGetDocument', e, st);
      return null;
    }
  }

  /// `DOM.describeNode` — 取指定 node 的最新结构 + 一层 children。
  Future<Map<String, dynamic>?> domDescribeNode(
    int nodeId, {
    int depth = 1,
  }) async {
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
      await cdp.send(
        'CSS.enable',
        sessionId: _pageSessionId,
        timeout: const Duration(seconds: 3),
      );
      final r = await cdp.send(
        'CSS.getComputedStyleForNode',
        params: <String, Object?>{'nodeId': nodeId},
        sessionId: _pageSessionId,
        timeout: const Duration(seconds: 6),
      );
      final list = r['computedStyle'];
      if (list is! List) return const [];
      return stringKeyedMapListFromValue(list).map((e) {
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
      silentLog(
        'web_reverse_session_controller',
        'domGetEventListeners',
        e,
        st,
      );
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
      await cdp.send(
        'Overlay.enable',
        sessionId: _pageSessionId,
        timeout: const Duration(seconds: 3),
      );
      await cdp.send(
        'Overlay.highlightNode',
        params: <String, Object?>{
          'nodeId': nodeId,
          'highlightConfig': <String, Object?>{
            'showInfo': true,
            'showRulers': false,
            'showExtensionLines': false,
            'contentColor': <String, Object?>{
              'r': 111,
              'g': 168,
              'b': 220,
              'a': 0.35,
            },
            'paddingColor': <String, Object?>{
              'r': 147,
              'g': 196,
              'b': 125,
              'a': 0.55,
            },
            'borderColor': <String, Object?>{
              'r': 255,
              'g': 229,
              'b': 153,
              'a': 0.66,
            },
            'marginColor': <String, Object?>{
              'r': 246,
              'g': 178,
              'b': 107,
              'a': 0.66,
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
      await cdp.send(
        'Overlay.hideHighlight',
        sessionId: _pageSessionId,
        timeout: const Duration(seconds: 3),
      );
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
    if (raw.length > maxReplExpressionChars) {
      final message =
          'REPL expression too large: ${raw.length} chars, limit $maxReplExpressionChars';
      _appendConsole('error', message);
      return null;
    }
    _appendConsole('repl-input', '> $raw');
    try {
      // 暂停态下走 evaluateOnCallFrame，求值发生在用户当前栈帧的作用域里，
      // 可直接访问局部变量、闭包变量；正常运行态则走全局 Runtime.evaluate。
      final paused = _pausedState;
      Map<String, Object?> r;
      if (paused != null && paused.callFrames.isNotEmpty) {
        final fid = '${paused.callFrames.first['callFrameId'] ?? ''}';
        r = await cdp.send(
          'Debugger.evaluateOnCallFrame',
          params: <String, Object?>{
            'callFrameId': fid,
            'expression': raw,
            'returnByValue': true,
            'generatePreview': true,
            'objectGroup': 'oh_console',
          },
          sessionId: _pageSessionId,
          timeout: const Duration(seconds: 15),
        );
      } else {
        r = await cdp.send(
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
      }
      final exception = r['exceptionDetails'];
      if (exception is Map) {
        final m =
            '${exception['exception']?['description'] ?? exception['text'] ?? 'eval failed'}';
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
            preview = prettyPrintJson(value);
          } catch (error, stack) {
            silentLog(
              'web_reverse_session_controller',
              'format console eval result preview',
              error,
              stack,
            );
            preview = '$value';
          }
        }
      } else {
        preview = '$res';
      }
      if (preview.length > _maxReplPreviewChars) {
        preview = '${preview.substring(0, _maxReplPreviewChars)}\n…(truncated)';
      }
      _appendConsole('repl-result', preview);
      return preview;
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'runReplExpression',
        error,
        stack,
      );
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
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final cdp = _browserCdp;
    if (cdp == null) return null;
    final trimmedMethod = method.trim();
    if (trimmedMethod.isEmpty ||
        !_rawCdpMethodPattern.hasMatch(trimmedMethod)) {
      return <String, Object?>{'error': 'invalid CDP method name'};
    }
    Map<String, Object?>? params;
    final rawParamsJson = paramsJson?.trim();
    if (rawParamsJson != null && rawParamsJson.isNotEmpty) {
      if (rawParamsJson.length > _maxRawCdpParamsJsonChars) {
        return <String, Object?>{
          'error':
              'params JSON too large: ${rawParamsJson.length} chars, limit $_maxRawCdpParamsJsonChars',
        };
      }
      try {
        final decoded = jsonDecode(rawParamsJson);
        if (decoded is! Map) {
          return <String, Object?>{'error': 'params JSON must be an object'};
        }
        params = stringKeyedMapFromValue(decoded);
      } catch (e) {
        return <String, Object?>{'error': 'invalid params JSON: $e'};
      }
    }
    try {
      final result = await cdp.send(
        trimmedMethod,
        params: params,
        sessionId: useSession ? _pageSessionId : null,
        timeout: timeout,
      );
      _syncRawCdpNetworkState(trimmedMethod, params);
      return result;
    } catch (error) {
      return <String, Object?>{'error': '$error'};
    }
  }

  void _syncRawCdpNetworkState(String method, Map<String, Object?>? params) {
    if (params == null) return;
    var changed = false;
    switch (method) {
      case 'Network.setCacheDisabled':
        final disabled = params['cacheDisabled'];
        if (disabled is bool && _cacheDisabled != disabled) {
          _cacheDisabled = disabled;
          changed = true;
        }
        break;
      case 'Network.emulateNetworkConditions':
        final next = WebReverseNetworkConditions.fromCdpParams(params);
        if (_networkConditions != next) {
          _networkConditions = next;
          changed = true;
        }
        break;
      case 'Network.setExtraHTTPHeaders':
        final headers = params['headers'];
        if (headers is Map) {
          final normalized = _normalizeRuleHeaders(
            stringKeyedMapFromValue(
              headers,
            ).map((key, value) => MapEntry(key, '${value ?? ''}')),
          );
          _extraHeaders
            ..clear()
            ..addAll(normalized);
          changed = true;
        }
        break;
      case 'Network.setBlockedURLs':
        final urls = params['urls'];
        if (urls is List) {
          final normalized = stringListFromValue(urls)
              .map((url) => url.trim())
              .where(
                (url) => url.isNotEmpty && url.length <= maxBreakpointTextChars,
              )
              .take(maxBlockedUrlPatterns);
          _blockedUrls
            ..clear()
            ..addAll(normalized);
          changed = true;
        }
        break;
    }
    if (changed) _safeNotify();
  }

  Future<void> stop() async {
    if (_stopped) {
      final stopping = _safeStopTask;
      if (stopping != null) await stopping;
      return;
    }
    _stopped = true;
    await _safeStop();
    _safeNotify();
  }

  /// 用户主动停止调试：杀掉外部浏览器进程并关闭临时桥接服务，保留会话本身。
  /// 后续可调 [restartBrowser] 再起一个新的。会话工作目录 / artifacts /
  /// dashboard 网络/控制台缓冲全部保留以便回看。
  Future<void> stopBrowser() async {
    if (_stopped) return;
    _stopAliveWatchdog();
    // 关 screencast → 关 CDP → kill 进程；artifacts / dock 不动。
    if (_screencastActive) {
      try {
        if (_browserCdp != null && _pageSessionId != null) {
          await _browserCdp!
              .send('Page.stopScreencast', sessionId: _pageSessionId)
              .timeout(const Duration(milliseconds: 500));
        }
      } catch (error, stack) {
        silentLog(
          'web_reverse_session_controller',
          'stop browser screencast',
          error,
          stack,
        );
      }
    }
    _resetScreencastRuntimeState(resetRefCount: false);
    _clearPendingFetchRequests(resetEnabled: true);
    await _cancelRuntimeSubscription(_pageEventsSub, 'stop page events');
    _pageEventsSub = null;
    _pageSessionId = null;
    await _closeAuxiliaryServices();
    try {
      await _pageCdp?.close();
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'close page cdp',
        error,
        stack,
      );
    }
    _pageCdp = null;
    _sourceMapCache.clear();
    try {
      await _browserCdp?.close();
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'close browser cdp',
        error,
        stack,
      );
    }
    _browserCdp = null;
    final p = _launchResult?.process;
    _launchResult = null;
    if (p != null) {
      await _terminateBrowserProcess(p, 'stop browser process');
    }
    _errorMessage = null;
    _safeNotify();
  }

  /// 把外部浏览器拉起来：要么是用户主动点了「停止调试」想再连一次，
  /// 要么是浏览器异常退出 / CDP 重连耗尽后用户点了「重启浏览器」。
  /// 复用 [start] 的全部启动逻辑，只是重置 stopped 标记。
  Future<void> restartBrowser() {
    if (_disposed) {
      return Future<void>.error(
        StateError('Web reverse session has been disposed'),
      );
    }
    final currentTask = _restartBrowserTask;
    if (currentTask != null) return currentTask;
    final task = _restartBrowserInternal();
    _restartBrowserTask = task;
    return task.whenComplete(() {
      if (identical(_restartBrowserTask, task)) {
        _restartBrowserTask = null;
      }
    });
  }

  Future<void> _restartBrowserInternal() async {
    final restoreScreencastRefCount = _screencastRefCount;
    final restoreScreencastWidth = _screencastWidth;
    final restoreScreencastHeight = _screencastHeight;
    final restoreScreencastQuality = _screencastQuality;
    try {
      // 先确保旧资源完全释放。
      await stopBrowser();
      _stopped = false;
      _started = false;
      _screencastRefCount = restoreScreencastRefCount;
      _screencastWidth = restoreScreencastWidth;
      _screencastHeight = restoreScreencastHeight;
      _screencastQuality = restoreScreencastQuality;
      _errorMessage = null;
      _safeNotify();
      await start();
      if (restoreScreencastRefCount > 0) {
        _screencastRefCount = restoreScreencastRefCount;
        await _startScreencastForCurrentSubscribers(
          maxWidth: restoreScreencastWidth,
          maxHeight: restoreScreencastHeight,
          quality: restoreScreencastQuality,
        );
      }
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'restartBrowser → start',
        error,
        stack,
      );
      _screencastRefCount = restoreScreencastRefCount;
      _errorMessage = '浏览器重启失败：$error';
      _safeNotify();
      rethrow;
    }
  }

  Future<void> _safeStop() {
    if (_resourcesStopped) return Future<void>.value();
    final active = _safeStopTask;
    if (active != null) return active;
    late final Future<void> stopping;
    stopping = _safeStopUncached().whenComplete(() {
      _resourcesStopped = true;
      if (identical(_safeStopTask, stopping)) {
        _safeStopTask = null;
      }
    });
    _safeStopTask = stopping;
    return stopping;
  }

  Future<void> _safeStopUncached() async {
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
      } catch (error, stack) {
        silentLog(
          'web_reverse_session_controller',
          'safe stop screencast',
          error,
          stack,
        );
      }
    }
    _resetScreencastRuntimeState(resetRefCount: true);
    _clearPendingFetchRequests(resetEnabled: true);
    await _cancelRuntimeSubscription(_pageEventsSub, 'shutdown page events');
    await _closeAuxiliaryServices();
    _pageEventsSub = null;
    _pageSessionId = null;
    try {
      await _pageCdp?.close();
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'safe close page cdp',
        error,
        stack,
      );
    }
    _pageCdp = null;
    _sourceMapCache.clear();
    try {
      await _browserCdp?.close();
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'safe close browser cdp',
        error,
        stack,
      );
    }
    _browserCdp = null;
    final p = _launchResult?.process;
    _launchResult = null;
    if (p != null) {
      await _terminateBrowserProcess(p, 'shutdown browser process');
    }
    // 收尾产物：先导 HAR（用 in-memory drafts），再关 artifacts。
    try {
      _lastHarPath = await _artifacts.exportHar();
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', 'export HAR', error, stack);
    }
    await _artifacts.close();
  }

  Future<void> _terminateBrowserProcess(Process process, String where) async {
    await runAsyncCleanupBounded(
      () => terminateTrackedProcessTree(
        process,
        gracefulTimeout: _browserStopGrace,
      ),
      timeout: _browserCleanupTimeout,
      onError: (error, stack) =>
          silentLog('web_reverse_session_controller', where, error, stack),
    );
  }

  Future<void> _closeAuxiliaryServices() async {
    await _cancelRuntimeSubscription(_mitmSub, 'shutdown mitm events');
    _mitmSub = null;
    final br = _mitmBridge;
    _mitmBridge = null;
    if (br != null) {
      try {
        await br.close();
      } catch (error, stack) {
        silentLog(
          'web_reverse_session_controller',
          'close mitm bridge',
          error,
          stack,
        );
      }
    }
    final har = _harReplayServer;
    _harReplayServer = null;
    if (har != null) {
      try {
        await har.close();
      } catch (error, stack) {
        silentLog(
          'web_reverse_session_controller',
          'close har replay server',
          error,
          stack,
        );
      }
    }
  }

  /// 清空 dashboard 缓冲（用户在 dashboard 点"清空"按钮时调用）。
  void clearBuffers() {
    _networkRequests.clear();
    _networkByRequestId.clear();
    _consoleMessages.clear();
    _safeNotify();
  }

  /// 在浏览器主 page 上启用/关闭缓存。
  Future<bool> setCacheDisabled(bool disabled) async {
    _cacheDisabled = disabled;
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) {
      _safeNotify();
      return false;
    }
    try {
      await cdp.send(
        'Network.setCacheDisabled',
        params: <String, Object?>{'cacheDisabled': disabled},
        sessionId: _pageSessionId,
      );
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'setCacheDisabled',
        error,
        stack,
      );
      _safeNotify();
      return false;
    }
    _safeNotify();
    return true;
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
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'install fps counter',
        error,
        stack,
      );
    }
  }

  /// 安装 Long Task 观测：通过 PerformanceObserver 监听 entryType='longtask'
  /// 的事件并塞进 window.__oh_long_tasks（环形缓冲，上限 200）。
  /// 之后 [readLongTasks] 拉取并清空。
  bool _longTaskObserverInstalled = false;

  Future<void> installLongTaskObserver() async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return;
    if (_longTaskObserverInstalled) return;
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
      _longTaskObserverInstalled = true;
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'install long task observer',
        error,
        stack,
      );
    }
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
      final raw = cdpStringResultValue(r);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return stringKeyedMapListFromValue(decoded);
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'read long tasks',
        error,
        stack,
      );
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
      silentLog(
        'web_reverse_session_controller',
        'installWebRtcCapture',
        error,
        stack,
      );
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
      final raw = cdpStringResultValue(r);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return stringKeyedMapListFromValue(decoded);
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'read WebRTC logs',
        error,
        stack,
      );
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
      final raw = cdpStringResultValue(r);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<num>()
          .map((n) => n.toInt())
          .toList(growable: false);
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'list WebRTC connections',
        error,
        stack,
      );
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
      final v = cdpResultValue(r);
      return v is num ? v.toDouble() : null;
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', 'read fps', error, stack);
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
    _screencastRefCount++;
    if (_screencastActive) return true;
    final ok = await _startScreencastForCurrentSubscribers(
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      quality: quality,
      everyNthFrame: everyNthFrame,
    );
    if (!ok) {
      _screencastRefCount = (_screencastRefCount - 1).clamp(0, 1 << 30);
    }
    return ok;
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
    _resetScreencastRuntimeState(resetRefCount: false);
    _safeNotify();
  }

  Future<bool> _startScreencastForCurrentSubscribers({
    int maxWidth = _screencastDefaultMaxWidth,
    int maxHeight = _screencastDefaultMaxHeight,
    int quality = _screencastDefaultQuality,
    int everyNthFrame = 1,
  }) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null || _screencastActive) {
      return _screencastActive;
    }
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
      _screencastStartedAt = DateTime.now();
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
        'startScreencastForCurrentSubscribers',
        error,
        stack,
      );
      return false;
    }
  }

  void _resetScreencastRuntimeState({required bool resetRefCount}) {
    _screencastActive = false;
    if (resetRefCount) _screencastRefCount = 0;
    _latestScreencastFrame = null;
    _screencastFrameSeq = 0;
    _screencastStartedAt = null;
    _lastScreencastFrameAt = null;
    if (!_disposed) {
      // 帧序号 +1 而不是只写 0，让 ValueListenableBuilder 一定能 rebuild
      // 拿到 null 帧切换到 placeholder。
      screencastFrameNotifier.value = screencastFrameNotifier.value + 1;
    }
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
      silentLog('web_reverse_session_controller', 'insertText', error, stack);
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
    await _navigateHistoryOffset(-1, logAction: 'goBack');
  }

  /// 前进一帧（若有历史）。
  Future<void> goForward() async {
    await _navigateHistoryOffset(1, logAction: 'goForward');
  }

  Future<void> _navigateHistoryOffset(
    int offset, {
    required String logAction,
  }) async {
    if (offset == 0) return;
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return;
    try {
      final r = await cdp.send(
        'Page.getNavigationHistory',
        sessionId: _pageSessionId,
        timeout: const Duration(seconds: 3),
      );
      final entries = (r['entries'] as List?) ?? const [];
      final current = intFromValue(r['currentIndex'], fallback: -1);
      final target = current + offset;
      if (current < 0 || target < 0 || target >= entries.length) return;
      final id = optionalIntFromValue(
        stringKeyedMapFromValue(entries[target])['id'],
      );
      if (id == null) return;
      await cdp.send(
        'Page.navigateToHistoryEntry',
        params: <String, Object?>{'entryId': id},
        sessionId: _pageSessionId,
      );
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', logAction, error, stack);
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
  /// 让分辨率档位真正影响页面渲染：传入 cssWidth/cssHeight/
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
  Future<bool> setDeviceMetricsPreset(WebReverseDevicePreset? preset) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
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
        return true;
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
      await cdp.send(
        'Emulation.setUserAgentOverride',
        params: <String, Object?>{'userAgent': preset.userAgent ?? ''},
        sessionId: _pageSessionId,
      );
      return true;
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'setDeviceMetricsPreset',
        error,
        stack,
      );
      return false;
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
        } catch (error, stack) {
          silentLog(
            'web_reverse_session_controller',
            'remove old zoom script',
            error,
            stack,
          );
        }
      }
      final initJs =
          '''
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
      final v = cdpResultValue(r);
      return v is num ? v.toInt() : 0;
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', 'find in page', error, stack);
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
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', 'find cycle', error, stack);
    }
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
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'clear find highlights',
        error,
        stack,
      );
    }
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
      final value = cdpResultValue(r);
      return value is String ? value : null;
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'read current url',
        error,
        stack,
      );
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
        final content = stringKeyedMapFromValue(metrics['cssContentSize']);
        if (content.isNotEmpty) {
          final width =
              optionalNonNegativeDoubleFromValue(content['width']) ?? 0;
          final height =
              optionalNonNegativeDoubleFromValue(content['height']) ?? 0;
          if (width <= 0 ||
              height <= 0 ||
              width > _maxFullPageScreenshotCssSide ||
              height > _maxFullPageScreenshotCssSide ||
              width * height > _maxFullPageScreenshotCssPixels) {
            return null;
          }
          params['clip'] = <String, Object?>{
            'x': 0,
            'y': 0,
            'width': width,
            'height': height,
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
      if (data.length > _maxScreenshotBase64Chars) return null;
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
  Future<
    ({int totalSize, List<({String label, int size, List<String> stack})> top})?
  >
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
      final profile = stringKeyedMapFromValue(r['profile']);
      if (profile.isEmpty) return null;
      // V8 SamplingHeapProfile 的 head 是火焰图根，递归累加 selfSize 并保留
      // 完整 callFrame 链。点击下钻看 stack 时直接读 entry.stack。
      final tally = <String, ({int size, List<String> stack})>{};
      var total = 0;
      void walk(Map<String, Object?> node, List<String> parentStack) {
        final cf = stringKeyedMapFromValue(node['callFrame']);
        final fnName = '${cf['functionName'] ?? '(anon)'}';
        final url = '${cf['url'] ?? ''}';
        final line = intFromValue(cf['lineNumber'], fallback: 0);
        final col = intFromValue(cf['columnNumber'], fallback: 0);
        final stackEntry = url.isEmpty
            ? fnName
            : '${fnName.isEmpty ? "(anonymous)" : fnName} @ $url:${line + 1}:${col + 1}';
        final stack = [...parentStack, stackEntry];
        final self = nonNegativeIntFromValue(node['selfSize'], fallback: 0);
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
            walk(stringKeyedMapFromValue(c), stack);
          }
        }
      }

      final head = stringKeyedMapFromValue(profile['head']);
      if (head.isEmpty) return null;
      walk(head, const []);
      final entries = tally.entries.toList()
        ..sort((a, b) => b.value.size.compareTo(a.value.size));
      final top = entries
          .take(15)
          .map(
            (e) => (
              label: e.key.isEmpty ? '(anonymous)' : e.key,
              size: e.value.size,
              stack: e.value.stack,
            ),
          )
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
        final v = optionalNonNegativeDoubleFromValue(m['value']) ?? 0;
        if (name == 'JSHeapUsedSize') used = v;
        if (name == 'JSHeapTotalSize') tot = v;
      }
      return (used: used, total: tot);
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'read js heap usage',
        error,
        stack,
      );
      return null;
    }
  }

  // ── Network: Fetch 域代理（throttle / abort） ─────────────────────────

  /// 通过 Fetch 域拦截全部请求。每次拦到都通过 [_pendingFetchRequests] 暴露
  /// 给 dashboard，用户可手动 continue / abort / 修改延迟。
  /// 达到容量上限的新请求直接放行，超时未处理的请求也会自动放行，避免
  /// 调试面板无人操作时把页面永久挂死。适合反爬调试与超时模拟，不建议默认开。
  bool _fetchInterceptEnabled = false;
  bool get isFetchInterceptEnabled =>
      _fetchInterceptEnabled; // 请求 ID -> 暂存的元信息（method / url），等用户决策。
  final Map<String, Map<String, Object?>> _pendingFetchRequests =
      <String, Map<String, Object?>>{};
  Timer? _pendingFetchSweepTimer;
  List<({String requestId, String method, String url})>
  get pendingFetchRequests => _pendingFetchRequests.entries
      .map(
        (e) => (
          requestId: e.key,
          method: '${e.value['method'] ?? 'GET'}',
          url: '${e.value['url'] ?? ''}',
        ),
      )
      .toList(growable: false);

  void _clearPendingFetchRequests({bool resetEnabled = false}) {
    _pendingFetchSweepTimer?.cancel();
    _pendingFetchSweepTimer = null;
    _pendingFetchRequests.clear();
    if (resetEnabled) _fetchInterceptEnabled = false;
  }

  Map<String, Object?>? _removePendingFetchRequest(String requestId) {
    final removed = _pendingFetchRequests.remove(requestId);
    if (_pendingFetchRequests.isEmpty) {
      _pendingFetchSweepTimer?.cancel();
      _pendingFetchSweepTimer = null;
    }
    return removed;
  }

  void _ensurePendingFetchSweepTimer() {
    if (_pendingFetchSweepTimer != null || _pendingFetchRequests.isEmpty) {
      return;
    }
    _pendingFetchSweepTimer = startNonOverlappingPeriodicTimer(
      const Duration(seconds: 5),
      (_) async {
        if (_disposed ||
            !_fetchInterceptEnabled ||
            _pendingFetchRequests.isEmpty) {
          _clearPendingFetchRequests();
          return;
        }
        final cutoff =
            DateTime.now().millisecondsSinceEpoch -
            fetchInterceptPendingTimeoutSeconds * 1000;
        final expired = _pendingFetchRequests.entries
            .where(
              (entry) =>
                  intFromValue(entry.value['createdAtMs'], fallback: cutoff) <=
                  cutoff,
            )
            .map((entry) => entry.key)
            .toList(growable: false);
        if (expired.isEmpty) return;
        final sessionId = _pageSessionId;
        await forEachIndexWithConcurrencyLimit(
          itemCount: expired.length,
          maxConcurrency: 8,
          shouldContinue: () =>
              !_disposed &&
              _fetchInterceptEnabled &&
              _pageSessionId == sessionId,
          task: (index) => continueFetchRequest(expired[index], notify: false),
        );
        _safeNotify();
      },
    );
  }

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
        _clearPendingFetchRequests();
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

  Future<void> continueFetchRequest(
    String requestId, {
    bool notify = true,
  }) async {
    final cdp = _browserCdp;
    final pending = _removePendingFetchRequest(requestId);
    final sessionId = pending?['sessionId'] is String
        ? pending!['sessionId'] as String
        : _pageSessionId;
    if (cdp == null || sessionId == null) {
      if (notify) _safeNotify();
      return;
    }
    try {
      await cdp.send(
        'Fetch.continueRequest',
        params: <String, Object?>{'requestId': requestId},
        sessionId: sessionId,
      );
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'continue fetch request $requestId',
        error,
        stack,
      );
    }
    if (notify) _safeNotify();
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
    final normalizedUrl = url?.trim();
    final normalizedMethod = method?.trim().toUpperCase();
    if ((normalizedUrl?.length ?? 0) > maxBreakpointTextChars ||
        (normalizedMethod?.length ?? 0) > maxRuleMethodChars ||
        (postDataBase64?.length ?? 0) > maxEditedRequestBodyBase64Chars) {
      return;
    }
    final normalizedHeaders = headers == null
        ? null
        : _normalizeRuleHeaders(headers);
    final cdp = _browserCdp;
    final pending = _removePendingFetchRequest(requestId);
    final sessionId = pending?['sessionId'] is String
        ? pending!['sessionId'] as String
        : _pageSessionId;
    if (cdp == null || sessionId == null) {
      _safeNotify();
      return;
    }
    try {
      final params = <String, Object?>{'requestId': requestId};
      if (normalizedUrl != null && normalizedUrl.isNotEmpty) {
        params['url'] = normalizedUrl;
      }
      if (normalizedMethod != null && normalizedMethod.isNotEmpty) {
        params['method'] = normalizedMethod;
      }
      if (normalizedHeaders != null) {
        params['headers'] = normalizedHeaders.entries
            .map((e) => <String, Object?>{'name': e.key, 'value': e.value})
            .toList(growable: false);
      }
      if (postDataBase64 != null) params['postData'] = postDataBase64;
      await cdp.send(
        'Fetch.continueRequest',
        params: params,
        sessionId: sessionId,
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
  Future<void> abortFetchRequest(
    String requestId, {
    String reason = 'Aborted',
  }) async {
    final cdp = _browserCdp;
    final pending = _removePendingFetchRequest(requestId);
    final sessionId = pending?['sessionId'] is String
        ? pending!['sessionId'] as String
        : _pageSessionId;
    if (cdp == null || sessionId == null) {
      _safeNotify();
      return;
    }
    final normalizedReason = _fetchErrorReasons.contains(reason)
        ? reason
        : 'Aborted';
    try {
      await cdp.send(
        'Fetch.failRequest',
        params: <String, Object?>{
          'requestId': requestId,
          'errorReason': normalizedReason,
        },
        sessionId: sessionId,
      );
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'abort fetch request $requestId',
        error,
        stack,
      );
    }
    _safeNotify();
  }

  /// 全部放行已暂存请求。
  Future<void> continueAllFetch() async {
    final ids = _pendingFetchRequests.keys.toList();
    final sessionId = _pageSessionId;
    await forEachIndexWithConcurrencyLimit(
      itemCount: ids.length,
      maxConcurrency: 8,
      shouldContinue: () => !_disposed && _pageSessionId == sessionId,
      task: (index) => continueFetchRequest(ids[index], notify: false),
    );
    _safeNotify();
  }

  void _onFetchRequestPaused(Map<String, Object?> p) {
    final requestId = '${p['requestId']}';
    final request = p['request'] as Map?;
    if (requestId.isEmpty || request == null) return;
    if (requestId.length > maxRuleIdChars) {
      unawaited(continueFetchRequest(requestId, notify: false));
      return;
    }
    final url = '${request['url'] ?? ''}';
    final reqMethod = '${request['method'] ?? 'GET'}';
    // Local Mock：最高优先级。命中 mock 规则 → 用 Fetch.fulfillRequest
    // 直接回一段假数据短路网络层（典型场景：本地占位 / 测试 401/500 边界）。
    final mock = _matchMockRule(reqMethod, url);
    if (mock != null) {
      unawaited(_fulfillMockRequest(requestId, mock));
      return;
    }
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
        unawaited(
          continueFetchRequestEdited(
            requestId,
            url: newUrl,
            headers: newHeaders,
          ),
        );
        return;
      }
      // 命中规则但仅作"标记"，仍然 hold 住等用户决定。
    }
    // 条件断点：仅记录命中、可选触发 JS 求值，不改变后续 pending / 放行流程。
    final method = '${request['method'] ?? 'GET'}';
    final postData = request['postData'] is String
        ? request['postData'] as String?
        : null;
    final bp = _matchRequestBreakpoint(method, url, postData);
    if (bp != null) {
      unawaited(_onRequestBreakpointHit(bp, method, url, postData));
    }
    if (!_pendingFetchRequests.containsKey(requestId) &&
        _pendingFetchRequests.length >= maxPendingFetchRequests) {
      unawaited(continueFetchRequest(requestId, notify: false));
      return;
    }
    _pendingFetchRequests[requestId] = <String, Object?>{
      'method': _capPlainWebReverseText(
        '${request['method'] ?? 'GET'}'.trim().toUpperCase(),
        maxRuleMethodChars,
      ),
      'url': _capPlainWebReverseText(url, maxBreakpointTextChars),
      'createdAtMs': DateTime.now().millisecondsSinceEpoch,
      'sessionId': _pageSessionId,
    };
    _ensurePendingFetchSweepTimer();
    _safeNotify();
  }

  /// 自动规则集（URL 通配匹配）。匹配到的第一条按指令对请求 block / rewrite。
  /// 没有命中时回退到原有的"暂停 → 等用户操作"路径。
  final List<WebReverseInterceptRule> _interceptRules =
      <WebReverseInterceptRule>[];

  List<WebReverseInterceptRule> get interceptRules =>
      List<WebReverseInterceptRule>.unmodifiable(_interceptRules);

  void setInterceptRules(List<WebReverseInterceptRule> rules) {
    final bounded = <WebReverseInterceptRule>[];
    var retainedChars = 0;
    for (final rule in rules.take(maxInterceptRules)) {
      final normalized = _normalizeInterceptRule(rule);
      final cost = _estimatedInterceptRuleChars(normalized);
      if (retainedChars + cost > maxRuleCollectionChars) break;
      bounded.add(normalized);
      retainedChars += cost;
    }
    _interceptRules
      ..clear()
      ..addAll(bounded);
    _safeNotify();
  }

  WebReverseInterceptRule? _matchInterceptRule(String url) {
    for (final r in _interceptRules) {
      if (!r.enabled) continue;
      if (r.matches(url)) return r;
    }
    return null;
  }

  // ───────────────────── Local Mock 拦截 ─────────────────────
  // 与 InterceptRule 平行；命中即用 Fetch.fulfillRequest 短路网络层。
  final List<WebReverseMockRule> _mockRules = <WebReverseMockRule>[];
  final List<WebReverseMockHit> _mockHits = <WebReverseMockHit>[];
  static const int _maxMockHits = 200;

  List<WebReverseMockRule> get mockRules =>
      List<WebReverseMockRule>.unmodifiable(_mockRules);
  List<WebReverseMockHit> get mockHits =>
      List<WebReverseMockHit>.unmodifiable(_mockHits);

  void setMockRules(List<WebReverseMockRule> rules) {
    final bounded = <WebReverseMockRule>[];
    final usedIds = <String>{};
    var retainedChars = 0;
    for (final indexed in rules.take(maxMockRules).indexed) {
      final normalized = _normalizeMockRule(
        indexed.$2,
        id: _uniqueBoundedRuleId(
          indexed.$2.id,
          prefix: 'mock',
          index: indexed.$1,
          used: usedIds,
        ),
      );
      final cost = _estimatedMockRuleChars(normalized);
      if (retainedChars + cost > maxRuleCollectionChars) break;
      bounded.add(normalized);
      retainedChars += cost;
    }
    _mockRules
      ..clear()
      ..addAll(bounded);
    _safeNotify();
  }

  void clearMockHits() {
    _mockHits.clear();
    _safeNotify();
  }

  WebReverseMockRule? _matchMockRule(String method, String url) {
    final mu = method.toUpperCase();
    for (final r in _mockRules) {
      if (!r.enabled) continue;
      if (r.methodFilter.isNotEmpty && r.methodFilter.toUpperCase() != mu) {
        continue;
      }
      if (r.matches(url)) return r;
    }
    return null;
  }

  Future<void> _fulfillMockRequest(
    String requestId,
    WebReverseMockRule rule,
  ) async {
    final cdp = _browserCdp;
    if (cdp == null) return;
    try {
      final bytes = utf8.encode(rule.body);
      final body = base64Encode(bytes);
      final headers = <Map<String, Object?>>[
        <String, Object?>{
          'name': 'content-type',
          'value': rule.contentType.isEmpty
              ? 'application/json; charset=utf-8'
              : rule.contentType,
        },
        for (final e in rule.extraHeaders.entries)
          <String, Object?>{'name': e.key, 'value': e.value},
      ];
      await cdp.send(
        'Fetch.fulfillRequest',
        params: <String, Object?>{
          'requestId': requestId,
          'responseCode': rule.statusCode,
          'responseHeaders': headers,
          'body': body,
        },
        sessionId: _pageSessionId,
        timeout: const Duration(seconds: 5),
      );
      _mockHits.insert(
        0,
        WebReverseMockHit(
          ruleId: rule.id,
          ruleName: rule.name,
          status: rule.statusCode,
          at: DateTime.now(),
        ),
      );
      while (_mockHits.length > _maxMockHits) {
        _mockHits.removeLast();
      }
      _safeNotify();
    } catch (e, st) {
      silentLog('web_reverse_session_controller', '_fulfillMockRequest', e, st);
    }
  }

  /// 已被屏蔽的 URL pattern 集合（CDP `Network.setBlockedURLs`）。
  /// 支持通配符 `*`；对应到右键菜单"Block this URL"。
  final Set<String> _blockedUrls = <String>{};
  Set<String> get blockedUrls => Set<String>.unmodifiable(_blockedUrls);

  Future<void> blockUrl(String pattern) async {
    final normalized = pattern.trim();
    if (normalized.isEmpty || normalized.length > maxBreakpointTextChars) {
      return;
    }
    if (_blockedUrls.contains(normalized) ||
        _blockedUrls.length >= maxBlockedUrlPatterns) {
      return;
    }
    _blockedUrls.add(normalized);
    await _flushBlockedUrls();
  }

  Future<void> unblockUrl(String pattern) async {
    if (!_blockedUrls.remove(pattern.trim())) return;
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
        'headers': (overrideHeaders ?? e.requestHeaders).map(
          (k, v) => MapEntry(k, v),
        ),
      if (e.requestPostData != null) 'body': e.requestPostData,
      'credentials': 'include',
    };
    final js =
        '''
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
      final raw = cdpStringResultValue(r);
      if (raw == null) return null;
      final decoded = decodeStringKeyedJsonMap(raw);
      if (decoded == null) return null;
      return (
        status: intFromValue(decoded['status'], fallback: -1),
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

  /// 设置网络节流模式：固定预设由 toolbar 使用，自定义值由高级弹窗使用。
  /// 失败/未启用时返回 false。
  Future<bool> setNetworkThrottling(WebReverseThrottlePreset preset) async {
    return setNetworkConditions(WebReverseNetworkConditions.fromPreset(preset));
  }

  Future<bool> setNetworkConditions(
    WebReverseNetworkConditions conditions,
  ) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    final normalized = conditions.normalized;
    try {
      await cdp.send(
        'Network.emulateNetworkConditions',
        params: normalized.cdpParams,
        sessionId: _pageSessionId,
      );
      _networkConditions = normalized;
      _safeNotify();
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
  final LifecycleLruCache<String> _scriptSources = LifecycleLruCache<String>(
    maxEntries: _maxScriptSourceCacheEntries,
    maxCost: _maxScriptSourceCacheChars,
    costOf: (source) => source.length,
  );

  void _onScriptParsed(Map<String, Object?> p) {
    final id = p['scriptId'] as String?;
    if (id == null || id.isEmpty) return;
    final url = '${p['url'] ?? ''}';
    if (url.isEmpty || url.length > _maxImportedUrlChars) return;
    _parsedScripts.remove(id);
    _parsedScripts[id] = (url: url, isModule: p['isModule'] == true);
    while (_parsedScripts.length > _maxParsedScripts) {
      final oldestId = _parsedScripts.keys.first;
      _parsedScripts.remove(oldestId);
      _scriptSources.remove(oldestId);
    }
  }

  /// 在 page 上启用 Debugger domain；调用后 [_onScriptParsed] 会陆续填充 [_parsedScripts]。
  Future<bool> enableDebugger() async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    try {
      await cdp.send('Debugger.enable', sessionId: _pageSessionId);
      return true;
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'enableDebugger',
        error,
        stack,
      );
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
    final hits = <({String scriptId, String url, int line, String preview})>[];
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
            preview: clipTextWithEllipsis(l, 120),
          ));
        }
      }
    }
    return hits;
  }

  /// 拉取脚本源码。CDP `Debugger.getScriptSource`。
  /// 命中过的脚本缓存到 [_scriptSources]，重复点同一个 URL 不再发请求。
  Future<String?> getScriptSource(String scriptId) async {
    final cached = _scriptSources.get(scriptId);
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
      final source = r['scriptSource'] as String?;
      if (source == null) return null;
      final boundedSource = _capWebReverseText(
        source,
        _maxScriptSourceChars,
        'script source',
      );
      _scriptSources.put(scriptId, boundedSource);
      return boundedSource;
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'getScriptSource',
        error,
        stack,
      );
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

  // 条件断点：key = '$url#$line'，value = 用户填的 JS 表达式（求值为
  // truthy 才暂停）。空字符串/缺失表示无条件断点。Chrome DevTools 协议
  // 通过 `Debugger.setBreakpointByUrl` 的 `condition` 字段实现，修改条件
  // 必须先 removeBreakpoint 再 set，故 setBreakpointCondition 内部走该
  // 删→建流程。仅内存态，不持久化（避免恶意条件随 session 复活）。
  final Map<String, String> _bpConditions = <String, String>{};

  Set<({String url, int line})> get userBreakpoints =>
      Set<({String url, int line})>.unmodifiable(_userBreakpoints);

  /// 取某断点当前的条件表达式；无则返回空串。
  String breakpointCondition({required String url, required int line}) =>
      _bpConditions['$url#$line'] ?? '';

  /// 按 URL+lineNumber 下断点。返回 breakpointId 用于后续 remove。
  /// 可选 [condition]：JS 表达式，求值为 truthy 时才暂停。
  Future<String?> setBreakpointByUrl({
    required String url,
    required int lineNumber,
    int columnNumber = 0,
    String? condition,
  }) async {
    final normalizedUrl = url.trim();
    final normalizedCondition = condition?.trim() ?? '';
    if (normalizedUrl.isEmpty ||
        normalizedUrl.length > maxBreakpointTextChars ||
        normalizedCondition.length > maxDebuggerExpressionChars ||
        lineNumber < 0 ||
        columnNumber < 0) {
      return null;
    }
    final key = '$normalizedUrl#$lineNumber';
    final existingId = _bpIdByKey[key];
    if (existingId != null &&
        (_bpConditions[key] ?? '') == normalizedCondition) {
      return existingId;
    }
    if (!_userBreakpoints.any(
          (item) => item.url == normalizedUrl && item.line == lineNumber,
        ) &&
        _userBreakpoints.length >= maxSourceBreakpoints) {
      return null;
    }
    if (existingId != null && !await removeBreakpoint(existingId)) {
      return null;
    }
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return null;
    try {
      final params = <String, Object?>{
        'url': normalizedUrl,
        'lineNumber': lineNumber,
        'columnNumber': columnNumber,
      };
      if (normalizedCondition.isNotEmpty) {
        params['condition'] = normalizedCondition;
      }
      final r = await cdp.send(
        'Debugger.setBreakpointByUrl',
        params: params,
        sessionId: _pageSessionId,
      );
      final bp = r['breakpointId'] as String?;
      if (bp != null) {
        _userBreakpoints.add((url: normalizedUrl, line: lineNumber));
        _bpIdByKey[key] = bp;
        if (normalizedCondition.isEmpty) {
          _bpConditions.remove(key);
        } else {
          _bpConditions[key] = normalizedCondition;
        }
        _safeNotify();
      }
      return bp;
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'setBreakpointByUrl',
        error,
        stack,
      );
      return null;
    }
  }

  /// 修改已存在断点的条件表达式：先 removeBreakpoint 再 setBreakpointByUrl，
  /// 传空串等价于把它转换回普通断点。返回新 breakpointId。
  Future<String?> setBreakpointCondition({
    required String url,
    required int line,
    required String condition,
  }) async {
    final normalizedUrl = url.trim();
    final normalizedCondition = condition.trim();
    if (normalizedUrl.isEmpty ||
        normalizedUrl.length > maxBreakpointTextChars ||
        normalizedCondition.length > maxDebuggerExpressionChars ||
        line < 0) {
      return null;
    }
    final key = '$normalizedUrl#$line';
    final oldId = _bpIdByKey[key];
    if (oldId != null) {
      if (!await removeBreakpoint(oldId)) return null;
    }
    return setBreakpointByUrl(
      url: normalizedUrl,
      lineNumber: line,
      condition: normalizedCondition,
    );
  }

  /// 持久化数据下发：恢复之前持久化的断点（dashboard 启动 / 浏览器重启用）。
  Future<void> restoreBreakpoints(
    Iterable<({String url, int line})> bps,
  ) async {
    for (final b in bps.take(maxSourceBreakpoints)) {
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
      // 同步清理已失效断点的条件表达式。
      _bpConditions.removeWhere((k, _) => !_bpIdByKey.containsKey(k));
      _safeNotify();
      return true;
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'removeBreakpoint',
        error,
        stack,
      );
      return false;
    }
  }

  /// 便捷封装：按 (url,line) 查 breakpointId 再 remove。Breakpoints 面板用。
  Future<bool> removeBreakpointAt({
    required String url,
    required int line,
  }) async {
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
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'resume debugger',
        error,
        stack,
      );
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
      silentLog(
        'web_reverse_session_controller',
        'setPauseOnExceptions',
        e,
        st,
      );
      return false;
    }
  }

  Future<bool> addXhrBreakpoint(String urlSubstring) async {
    final normalized = urlSubstring.trim();
    if (normalized.length > maxBreakpointTextChars) return false;
    if (_xhrBreakpoints.contains(normalized)) return true;
    if (_xhrBreakpoints.length >= maxXhrBreakpoints) return false;
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    try {
      await cdp.send(
        'DOMDebugger.setXHRBreakpoint',
        params: <String, Object?>{'url': normalized},
        sessionId: _pageSessionId,
      );
      _xhrBreakpoints.add(normalized);
      _safeNotify();
      return true;
    } catch (e, st) {
      silentLog('web_reverse_session_controller', 'addXhrBreakpoint', e, st);
      return false;
    }
  }

  Future<bool> removeXhrBreakpoint(String urlSubstring) async {
    final normalized = urlSubstring.trim();
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    try {
      await cdp.send(
        'DOMDebugger.removeXHRBreakpoint',
        params: <String, Object?>{'url': normalized},
        sessionId: _pageSessionId,
      );
      _xhrBreakpoints.remove(normalized);
      _safeNotify();
      return true;
    } catch (e, st) {
      silentLog('web_reverse_session_controller', 'removeXhrBreakpoint', e, st);
      return false;
    }
  }

  // ─── Debugger 暂停 / step / evaluate-on-call-frame ───────────────────
  // 接收 `Debugger.paused` 事件后保留当前 call frames + scope chain + 命中
  // 的 breakpointId，给 Sources 面板和 Breakpoints 面板「Call Stack / Scope /
  // Watch」三段联动使用；`Debugger.resumed` 与所有 step* 操作前会清空。
  ({
    List<Map<String, Object?>> callFrames,
    String reason,
    Map<String, Object?> data,
    List<String> hitBreakpoints,
  })?
  _pausedState;

  ({
    List<Map<String, Object?>> callFrames,
    String reason,
    Map<String, Object?> data,
    List<String> hitBreakpoints,
  })?
  get pausedState => _pausedState;

  bool get isPaused => _pausedState != null;

  void _onDebuggerPaused(Map<String, Object?> p) {
    final frames =
        (p['callFrames'] as List?)
            ?.whereType<Map>()
            .map(Map<String, Object?>.from)
            .toList(growable: false) ??
        const <Map<String, Object?>>[];
    final reason = '${p['reason'] ?? ''}';
    final data =
        (p['data'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{};
    final hits =
        (p['hitBreakpoints'] as List?)?.whereType<String>().toList(
          growable: false,
        ) ??
        const <String>[];
    _pausedState = (
      callFrames: frames,
      reason: reason,
      data: data,
      hitBreakpoints: hits,
    );
    _safeNotify();
  }

  void _onDebuggerResumed() {
    if (_pausedState == null) return;
    _pausedState = null;
    _safeNotify();
  }

  Future<bool> stepOverDebugger() => _stepCommand('Debugger.stepOver');
  Future<bool> stepIntoDebugger() => _stepCommand('Debugger.stepInto');
  Future<bool> stepOutDebugger() => _stepCommand('Debugger.stepOut');

  Future<bool> _stepCommand(String method) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    try {
      await cdp.send(method, sessionId: _pageSessionId);
      return true;
    } catch (e, st) {
      silentLog('web_reverse_session_controller', method, e, st);
      return false;
    }
  }

  /// `Debugger.evaluateOnCallFrame` —— 在指定栈帧的作用域里求值。供 Sources
  /// 面板 Watch 列表 / 控制台「暂停时执行」复用。返回 RemoteObject map（保留
  /// description / type / value），失败返回 null。
  Future<Map<String, Object?>?> evaluateOnCallFrame({
    required String callFrameId,
    required String expression,
    bool returnByValue = false,
    bool generatePreview = true,
  }) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return null;
    try {
      final r = await cdp.send(
        'Debugger.evaluateOnCallFrame',
        params: <String, Object?>{
          'callFrameId': callFrameId,
          'expression': expression,
          'returnByValue': returnByValue,
          'generatePreview': generatePreview,
          'silent': true,
          'objectGroup': 'oh_watch',
        },
        sessionId: _pageSessionId,
      );
      final exception = r['exceptionDetails'];
      if (exception is Map) {
        return <String, Object?>{
          'type': 'error',
          'description':
              '${(exception['exception'] as Map?)?['description'] ?? exception['text'] ?? 'error'}',
        };
      }
      return (r['result'] as Map?)?.cast<String, Object?>();
    } catch (e, st) {
      silentLog('web_reverse_session_controller', 'evaluateOnCallFrame', e, st);
      return null;
    }
  }

  // ─── Watch 表达式 ────────────────────────────────────────────────────
  // 纯前端维护；每次调 evaluateWatch 时会按当前是否处于暂停态走
  // evaluateOnCallFrame 或 Runtime.evaluate。
  final List<String> _watchExpressions = <String>[];
  List<String> get watchExpressions =>
      List<String>.unmodifiable(_watchExpressions);

  bool addWatchExpression(String expr) {
    final e = expr.trim();
    if (e.isEmpty || e.length > maxDebuggerExpressionChars) return false;
    if (_watchExpressions.contains(e)) return true;
    if (_watchExpressions.length >= maxWatchExpressions) return false;
    _watchExpressions.add(e);
    _safeNotify();
    return true;
  }

  void removeWatchExpression(String expr) {
    if (_watchExpressions.remove(expr)) _safeNotify();
  }

  /// 求值单个 watch 表达式。暂停态走 evaluateOnCallFrame（top frame），否则
  /// 走 Runtime.evaluate。返回 RemoteObject map。
  Future<Map<String, Object?>?> evaluateWatch(String expression) async {
    final paused = _pausedState;
    if (paused != null && paused.callFrames.isNotEmpty) {
      final fid = '${paused.callFrames.first['callFrameId'] ?? ''}';
      if (fid.isNotEmpty) {
        return evaluateOnCallFrame(callFrameId: fid, expression: expression);
      }
    }
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return null;
    try {
      final r = await cdp.send(
        'Runtime.evaluate',
        params: <String, Object?>{
          'expression': expression,
          'silent': true,
          'returnByValue': false,
          'generatePreview': true,
          'objectGroup': 'oh_watch',
        },
        sessionId: _pageSessionId,
      );
      final exception = r['exceptionDetails'];
      if (exception is Map) {
        return <String, Object?>{
          'type': 'error',
          'description':
              '${(exception['exception'] as Map?)?['description'] ?? exception['text'] ?? 'error'}',
        };
      }
      return (r['result'] as Map?)?.cast<String, Object?>();
    } catch (e, st) {
      silentLog('web_reverse_session_controller', 'evaluateWatch', e, st);
      return null;
    }
  }

  // ─── Event Listener 断点 ─────────────────────────────────────────────
  // CDP `DOMDebugger.setEventListenerBreakpoint` —— 按事件名（如 'click' /
  // 'keydown' / 'timer:setTimeout'）拦截全局事件分发。Chrome DevTools 的
  // 「Event Listener Breakpoints」面板把这些事件分组（Mouse / Keyboard /
  // Animation / Control / Timer / Worker 等）；这里同样维护到 set 里。
  final Set<String> _eventListenerBreakpoints = <String>{};
  Set<String> get eventListenerBreakpoints =>
      Set<String>.unmodifiable(_eventListenerBreakpoints);

  Future<bool> setEventListenerBreakpoint(String eventName) async {
    final normalized = eventName.trim();
    if (normalized.isEmpty || normalized.length > maxBreakpointTextChars) {
      return false;
    }
    if (_eventListenerBreakpoints.contains(normalized)) return true;
    if (_eventListenerBreakpoints.length >= maxEventListenerBreakpoints) {
      return false;
    }
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    try {
      await cdp.send(
        'DOMDebugger.setEventListenerBreakpoint',
        params: <String, Object?>{'eventName': normalized},
        sessionId: _pageSessionId,
      );
      _eventListenerBreakpoints.add(normalized);
      _safeNotify();
      return true;
    } catch (e, st) {
      silentLog(
        'web_reverse_session_controller',
        'setEventListenerBreakpoint',
        e,
        st,
      );
      return false;
    }
  }

  Future<bool> removeEventListenerBreakpoint(String eventName) async {
    final normalized = eventName.trim();
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    try {
      await cdp.send(
        'DOMDebugger.removeEventListenerBreakpoint',
        params: <String, Object?>{'eventName': normalized},
        sessionId: _pageSessionId,
      );
      _eventListenerBreakpoints.remove(normalized);
      _safeNotify();
      return true;
    } catch (e, st) {
      silentLog(
        'web_reverse_session_controller',
        'removeEventListenerBreakpoint',
        e,
        st,
      );
      return false;
    }
  }

  // ─── DOM Breakpoints ─────────────────────────────────────────────────
  // CDP `DOMDebugger.setDOMBreakpoint({nodeId, type})` —— 监听 DOM 节点的
  // subtree-modified / attribute-modified / node-removed。前端按 (selector,
  // type) 维护；启动时由 selector 先 querySelector 拿 nodeId 再注册。
  final List<({String selector, String type})> _domBreakpoints =
      <({String selector, String type})>[];
  List<({String selector, String type})> get domBreakpoints =>
      List<({String selector, String type})>.unmodifiable(_domBreakpoints);

  /// 通过 `document.querySelector` + `DOM.requestNode` 把 selector 解析成
  /// nodeId，然后下断点。type ∈ {subtree-modified, attribute-modified,
  /// node-removed}（与 CDP 一致）。
  Future<bool> addDomBreakpoint({
    required String selector,
    required String type,
  }) async {
    final normalizedSelector = selector.trim();
    if (normalizedSelector.isEmpty ||
        normalizedSelector.length > maxBreakpointTextChars) {
      return false;
    }
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    if (type != 'subtree-modified' &&
        type != 'attribute-modified' &&
        type != 'node-removed') {
      return false;
    }
    if (_domBreakpoints.any(
      (item) => item.selector == normalizedSelector && item.type == type,
    )) {
      return true;
    }
    if (_domBreakpoints.length >= maxDomBreakpoints) return false;
    try {
      final eval = await cdp.send(
        'Runtime.evaluate',
        params: <String, Object?>{
          'expression':
              'document.querySelector(${jsonEncode(normalizedSelector)})',
          'objectGroup': 'oh_dombp',
        },
        sessionId: _pageSessionId,
      );
      final result = stringKeyedMapFromValue(eval['result']);
      final objectId = result['objectId'] as String?;
      if (objectId == null) return false;
      final node = await cdp.send(
        'DOM.requestNode',
        params: <String, Object?>{'objectId': objectId},
        sessionId: _pageSessionId,
      );
      final nodeId = optionalIntFromValue(node['nodeId']);
      if (nodeId == null) return false;
      await cdp.send(
        'DOMDebugger.setDOMBreakpoint',
        params: <String, Object?>{'nodeId': nodeId, 'type': type},
        sessionId: _pageSessionId,
      );
      // selector 同 type 重复添加时合并去重。
      _domBreakpoints.add((selector: normalizedSelector, type: type));
      _safeNotify();
      return true;
    } catch (e, st) {
      silentLog('web_reverse_session_controller', 'addDomBreakpoint', e, st);
      return false;
    }
  }

  Future<bool> removeDomBreakpoint({
    required String selector,
    required String type,
  }) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    try {
      final eval = await cdp.send(
        'Runtime.evaluate',
        params: <String, Object?>{
          'expression': 'document.querySelector(${jsonEncode(selector)})',
          'objectGroup': 'oh_dombp',
        },
        sessionId: _pageSessionId,
      );
      final objectId =
          stringKeyedMapFromValue(eval['result'])['objectId'] as String?;
      if (objectId != null) {
        final node = await cdp.send(
          'DOM.requestNode',
          params: <String, Object?>{'objectId': objectId},
          sessionId: _pageSessionId,
        );
        final nodeId = optionalIntFromValue(node['nodeId']);
        if (nodeId != null) {
          await cdp.send(
            'DOMDebugger.removeDOMBreakpoint',
            params: <String, Object?>{'nodeId': nodeId, 'type': type},
            sessionId: _pageSessionId,
          );
        }
      }
      _domBreakpoints.removeWhere(
        (b) => b.selector == selector && b.type == type,
      );
      _safeNotify();
      return true;
    } catch (e, st) {
      silentLog('web_reverse_session_controller', 'removeDomBreakpoint', e, st);
      return false;
    }
  }

  // ─── CSP Violation 断点 ──────────────────────────────────────────────
  // CDP `DOMDebugger.setBreakOnCSPViolation({violationTypes:[...]})`。
  // 只有两种 violationType：trustedtype-sink-violation /
  // trustedtype-policy-violation。
  final Set<String> _cspViolationBreakpoints = <String>{};
  Set<String> get cspViolationBreakpoints =>
      Set<String>.unmodifiable(_cspViolationBreakpoints);

  Future<bool> setCspViolationBreakpoints(Set<String> types) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    final allowed = <String>{
      'trustedtype-sink-violation',
      'trustedtype-policy-violation',
    };
    final clean = types.where(allowed.contains).toList(growable: false);
    try {
      await cdp.send(
        'DOMDebugger.setBreakOnCSPViolation',
        params: <String, Object?>{'violationTypes': clean},
        sessionId: _pageSessionId,
      );
      _cspViolationBreakpoints
        ..clear()
        ..addAll(clean);
      _safeNotify();
      return true;
    } catch (e, st) {
      silentLog(
        'web_reverse_session_controller',
        'setCspViolationBreakpoints',
        e,
        st,
      );
      return false;
    }
  }

  /// `Runtime.getProperties` —— Scope/Watch 展开时拉对象属性列表。
  Future<List<Map<String, Object?>>> runtimeGetProperties({
    required String objectId,
    bool ownProperties = true,
    bool generatePreview = true,
  }) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return const [];
    try {
      final r = await cdp.send(
        'Runtime.getProperties',
        params: <String, Object?>{
          'objectId': objectId,
          'ownProperties': ownProperties,
          'generatePreview': generatePreview,
        },
        sessionId: _pageSessionId,
      );
      final list = r['result'] as List?;
      if (list == null) return const [];
      return list
          .whereType<Map>()
          .map(Map<String, Object?>.from)
          .toList(growable: false);
    } catch (e, st) {
      silentLog(
        'web_reverse_session_controller',
        'runtimeGetProperties',
        e,
        st,
      );
      return const [];
    }
  }

  // ─── 全局事件监听器（window）─────────────────────────────────────────
  // CDP `DOMDebugger.getEventListeners` 需要一个 RemoteObject objectId；
  // 先 Runtime.evaluate 拿到 window 的 objectId 再请求。返回列表中每条包含
  // type/useCapture/passive/once/scriptId/lineNumber/columnNumber。
  Future<List<Map<String, Object?>>> listGlobalEventListeners() async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return const [];
    try {
      final win = await cdp.send(
        'Runtime.evaluate',
        params: <String, Object?>{
          'expression': 'window',
          'objectGroup': 'oh_global_listeners',
        },
        sessionId: _pageSessionId,
      );
      final objectId = (win['result'] as Map?)?['objectId'] as String?;
      if (objectId == null) return const [];
      final r = await cdp.send(
        'DOMDebugger.getEventListeners',
        params: <String, Object?>{'objectId': objectId, 'depth': 1},
        sessionId: _pageSessionId,
      );
      final list = r['listeners'] as List?;
      if (list == null) return const [];
      return list
          .whereType<Map>()
          .map(Map<String, Object?>.from)
          .toList(growable: false);
    } catch (e, st) {
      silentLog(
        'web_reverse_session_controller',
        'listGlobalEventListeners',
        e,
        st,
      );
      return const [];
    }
  }

  /// JS 美化：单遍状态机扫描，正确处理字符串 / 模板字面量 (含 `${}`
  /// 插值递归) / 行注释 / 块注释 / 正则字面量。按 `{[(` 缩进、`}])` 退
  /// 缩、`;` 与 `{` 后换行、`} else/catch/finally/while/,/)` 智能合并。
  /// 大于 4 MB 直接返回原文，避免阻塞 UI。设计为零依赖、纯 Dart 实现，
  /// 优先保证「能读」而不是 prettier 级别的精确。
  static String prettifyJs(String src) {
    const maxSize = 4 * 1024 * 1024;
    if (src.length >= maxSize) return src;
    final out = StringBuffer();
    var indent = 0;
    // 模板字面量内的 `${...}` 插值会进入 JS 模式但还要回到模板字符串。
    // 用一个简易栈表示当前所处的「字符串模式」：'`' 表示当前在模板字
    // 面量里，'$' 表示在模板里的 `${}` 插值（JS 代码）。空栈代表普通
    // JS 代码上下文。
    final tmplStack = <String>[];
    var i = 0;
    final n = src.length;

    void writeIndent() {
      for (var k = 0; k < indent; k++) {
        out.write('  ');
      }
    }

    void newline() {
      // 去掉本行末尾空格——避免缩进与之前残留空格叠加。
      while (out.length > 0) {
        final last = out.toString().codeUnitAt(out.length - 1);
        if (last == 0x20 || last == 0x09) {
          // O(N) 截断：写入一个新缓冲。下面 trimEndInPlace 替代。
          break;
        }
        break;
      }
      // 用 _trimTrailingWhitespace 一次性裁剪当前行末。
      _trimTrailingWhitespace(out);
      out.write('\n');
      writeIndent();
    }

    // 上一非空白可打印字符（用于正则 / 除号歧义判断）。
    var prevSig = '';

    // 把字符 c 写入 out 并刷新 prevSig（如果非空白）。
    void emit(String c) {
      out.write(c);
      if (c.isNotEmpty && c != ' ' && c != '\t' && c != '\n' && c != '\r') {
        prevSig = c;
      }
    }

    // 判断当前位置 i 上的 `/` 应当被解析为正则字面量起始（true）还是
    // 除号 / 注释（false）。基于 prevSig：若前一个有效字符是表达式起
    // 始/分隔符（如 `=,;:!&|?{}([*/+-~^%<>` 或空），则是正则。
    bool looksLikeRegexStart() {
      if (prevSig.isEmpty) return true;
      const exprStarters = r'=,;:!&|?{([*/+-~^%<>';
      if (exprStarters.contains(prevSig)) return true;
      // `return` / `typeof` / `in` / `of` 等关键字后接 `/` 也是正则。
      // 简化处理：回扫最多 8 个字符判断是否以这些关键字结尾。
      final tail = out.length > 12
          ? out.toString().substring(out.length - 12)
          : out.toString();
      for (final kw in const [
        'return',
        'typeof',
        'instanceof',
        'in',
        'of',
        'delete',
        'void',
        'throw',
        'new',
      ]) {
        if (tail.endsWith(kw) &&
            (tail.length == kw.length ||
                _isIdSep(tail[tail.length - kw.length - 1]))) {
          return true;
        }
      }
      return false;
    }

    while (i < n) {
      final c = src[i];
      final next = i + 1 < n ? src[i + 1] : '';
      final mode = tmplStack.isEmpty ? '' : tmplStack.last;

      // ───── 模板字符串字符模式 ─────
      if (mode == '`') {
        out.write(c);
        if (c == r'\' && next.isNotEmpty) {
          out.write(next);
          i += 2;
          continue;
        }
        if (c == r'$' && next == '{') {
          out.write(next);
          tmplStack.add(r'$');
          i += 2;
          continue;
        }
        if (c == '`') {
          tmplStack.removeLast();
          prevSig = '`';
        }
        i += 1;
        continue;
      }

      // ───── 普通字符串字符模式：直接遇到 emit 即可（下方分支处理） ─────

      // ───── 行注释 / 块注释 ─────
      if (c == '/' && next == '/') {
        // 写到行尾。
        out.write(c);
        out.write(next);
        i += 2;
        while (i < n && src[i] != '\n') {
          out.write(src[i]);
          i++;
        }
        if (i < n) {
          out.write('\n');
          writeIndent();
          i++;
        }
        prevSig = '';
        continue;
      }
      if (c == '/' && next == '*') {
        out.write(c);
        out.write(next);
        i += 2;
        while (i < n - 1 && !(src[i] == '*' && src[i + 1] == '/')) {
          out.write(src[i]);
          i++;
        }
        if (i < n - 1) {
          out.write('*/');
          i += 2;
        } else if (i < n) {
          out.write(src[i]);
          i++;
        }
        prevSig = '/';
        continue;
      }

      // ───── 普通字符串 ('  " ) ─────
      if (c == '"' || c == "'") {
        final quote = c;
        out.write(c);
        i++;
        while (i < n) {
          final ch = src[i];
          out.write(ch);
          if (ch == r'\' && i + 1 < n) {
            out.write(src[i + 1]);
            i += 2;
            continue;
          }
          i++;
          if (ch == quote) break;
        }
        prevSig = quote;
        continue;
      }

      // ───── 模板字符串起始 ─────
      if (c == '`') {
        out.write(c);
        tmplStack.add('`');
        i++;
        continue;
      }

      // ───── 正则字面量 ─────
      if (c == '/' && looksLikeRegexStart()) {
        out.write(c);
        i++;
        var inCharClass = false;
        while (i < n) {
          final ch = src[i];
          out.write(ch);
          if (ch == r'\' && i + 1 < n) {
            out.write(src[i + 1]);
            i += 2;
            continue;
          }
          if (ch == '[') inCharClass = true;
          if (ch == ']') inCharClass = false;
          i++;
          if (ch == '/' && !inCharClass) break;
        }
        // flags
        while (i < n && _isIdChar(src[i])) {
          out.write(src[i]);
          i++;
        }
        prevSig = '/';
        continue;
      }

      // ───── 缩进 / 换行控制字符 ─────
      if (c == '{') {
        emit(c);
        indent++;
        newline();
        i++;
        continue;
      }
      if (c == '}') {
        // 智能合并：把 } 之前一个 newline 撤掉前的空行清理。
        indent = (indent - 1).clamp(0, 200);
        // 如果当前 mode 是 '$'(模板插值)，遇到匹配的 } 要回到模板字
        // 符串模式，不参与缩进 / 换行。
        if (mode == r'$') {
          tmplStack.removeLast();
          out.write(c);
          prevSig = c;
          i++;
          continue;
        }
        newline();
        out.write(c);
        prevSig = c;
        i++;
        // 智能合并：`} else` / `} catch` / `} finally` / `} while` /
        // `},` / `})` / `};` / `}]`。
        // 先跳过空白（注意：跨原始换行不算）。
        var j = i;
        while (j < n && (src[j] == ' ' || src[j] == '\t')) {
          j++;
        }
        if (j < n) {
          final after = src[j];
          if (after == ',' ||
              after == ')' ||
              after == ';' ||
              after == ']' ||
              after == '.') {
            // 紧贴写；不换行。
            out.write(after);
            prevSig = after;
            i = j + 1;
            continue;
          }
          // 关键字合并：识别后续 identifier，若是 else/catch/finally/while
          // 则同行 `} else` 输出。
          var k = j;
          while (k < n && _isIdChar(src[k])) {
            k++;
          }
          final id = src.substring(j, k);
          if (id == 'else' ||
              id == 'catch' ||
              id == 'finally' ||
              id == 'while') {
            out.write(' ');
            out.write(id);
            prevSig = id[id.length - 1];
            i = k;
            continue;
          }
        }
        newline();
        continue;
      }
      if (c == '[' || c == '(') {
        emit(c);
        i++;
        continue;
      }
      if (c == ']' || c == ')') {
        emit(c);
        i++;
        continue;
      }
      if (c == ';') {
        emit(c);
        // for (;;) 头内不换行 —— 简化：若紧跟 `)` 不换行。
        var j = i + 1;
        while (j < n && (src[j] == ' ' || src[j] == '\t')) {
          j++;
        }
        if (j < n && src[j] == ')') {
          i++;
          continue;
        }
        newline();
        i++;
        continue;
      }
      if (c == ',') {
        emit(c);
        if (indent > 0) {
          newline();
        } else {
          out.write(' ');
        }
        i++;
        continue;
      }
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        // 折叠空白：仅当 out 末尾不是空白 / 换行时插一个空格。
        if (out.length > 0) {
          final last = out.toString().codeUnitAt(out.length - 1);
          if (last != 0x20 && last != 0x0a) {
            out.write(' ');
          }
        }
        i++;
        continue;
      }

      emit(c);
      i++;
    }
    return out.toString();
  }

  /// `_BreakpointsBodyState` 也会用到的简易标识符尾字符判断。
  static bool _isIdChar(String c) {
    if (c.isEmpty) return false;
    final code = c.codeUnitAt(0);
    return (code >= 0x30 && code <= 0x39) || // 0-9
        (code >= 0x41 && code <= 0x5a) || // A-Z
        (code >= 0x61 && code <= 0x7a) || // a-z
        code == 0x24 || // $
        code == 0x5f; // _
  }

  /// 与 _isIdChar 反向：用来判断关键字前一个字符是不是分隔符。
  static bool _isIdSep(String c) => !_isIdChar(c);

  /// 修剪 StringBuffer 末尾连续的空格 / Tab。仅当末尾确实有空白才重
  /// 建（避免无谓 toString）。
  static void _trimTrailingWhitespace(StringBuffer buf) {
    if (buf.length == 0) return;
    final s = buf.toString();
    var end = s.length;
    while (end > 0) {
      final code = s.codeUnitAt(end - 1);
      if (code == 0x20 || code == 0x09) {
        end--;
      } else {
        break;
      }
    }
    if (end != s.length) {
      buf
        ..clear()
        ..write(s.substring(0, end));
    }
  }

  /// 持久化注入到所有请求的 extra HTTP headers（CDP `Network.setExtraHTTPHeaders`）。
  /// 调用方传整张 map；空 map 表示清空。
  final Map<String, String> _extraHeaders = <String, String>{};
  Map<String, String> get extraHeaders =>
      Map<String, String>.unmodifiable(_extraHeaders);

  bool _cacheDisabled = false;
  bool get cacheDisabled => _cacheDisabled;

  WebReverseNetworkConditions _networkConditions =
      WebReverseNetworkConditions.none;
  WebReverseNetworkConditions get networkConditions => _networkConditions;
  WebReverseThrottlePreset get networkThrottlePreset =>
      _networkConditions.preset;

  Future<void> _restoreNetworkDomainState() async {
    final cdp = _browserCdp;
    final sessionId = _pageSessionId;
    if (cdp == null || sessionId == null) return;

    Future<bool> send(String method, {Map<String, Object?>? params}) async {
      try {
        await cdp.send(method, params: params, sessionId: sessionId);
        return true;
      } catch (error, stack) {
        silentLog(
          'web_reverse_session_controller',
          'restore $method',
          error,
          stack,
        );
        return false;
      }
    }

    await send(
      'Network.setCacheDisabled',
      params: <String, Object?>{'cacheDisabled': _cacheDisabled},
    );
    if (_extraHeaders.isNotEmpty) {
      await send(
        'Network.setExtraHTTPHeaders',
        params: <String, Object?>{'headers': _extraHeaders},
      );
    }
    await send(
      'Network.setBlockedURLs',
      params: <String, Object?>{'urls': _blockedUrls.toList()},
    );
    if (!_networkConditions.isNoThrottle) {
      await send(
        'Network.emulateNetworkConditions',
        params: _networkConditions.cdpParams,
      );
    }
    if (_fetchInterceptEnabled) {
      final restored = await send(
        'Fetch.enable',
        params: const <String, Object?>{
          'patterns': [
            <String, Object?>{'requestStage': 'Request'},
          ],
        },
      );
      if (!restored) _fetchInterceptEnabled = false;
    }
  }

  Future<bool> setExtraHttpHeaders(Map<String, String> headers) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    final normalized = _normalizeRuleHeaders(headers);
    try {
      await cdp.send(
        'Network.setExtraHTTPHeaders',
        params: <String, Object?>{'headers': normalized},
        sessionId: _pageSessionId,
      );
      _extraHeaders
        ..clear()
        ..addAll(normalized);
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
      return (
        port: _harReplayServer!.port,
        entryCount: _harReplayServer!.entryCount,
      );
    }
    try {
      // 优先用 in-flight artifacts；为空时生成一个临时 HAR。
      String? path = _lastHarPath;
      path ??= await _artifacts.exportHar();
      if (path == null) return null;
      final read = await readWebReverseHarPath(path);
      if (read.isTooLarge) return null;
      final bytes = read.bytes!;
      final s = await WebReverseHarReplayServer.start(harBytes: bytes);
      if (s == null) return null;
      _harReplayServer = s;
      _safeNotify();
      return (port: s.port, entryCount: s.entryCount);
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'startHarReplayServer',
        error,
        stack,
      );
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
          } catch (error, stack) {
            silentLog(
              'web_reverse_session_controller',
              'decode mitm body',
              error,
              stack,
            );
          }
        }
        _networkRequests.add(entry);
        _networkByRequestId[entry.requestId] = entry;
        while (_networkRequests.length > _maxNetworkEntries) {
          final removed = _networkRequests.removeAt(0);
          _networkByRequestId.remove(removed.requestId);
          _artifacts.evictHarDraft(removed.requestId);
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
        match.statusCode = optionalIntFromValue(m['status']);
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
    await _cancelRuntimeSubscription(_mitmSub, 'stop mitm events');
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
        final r = await runTrackedProcessOrFailed(
          'zip',
          ['-r', out.path, src.path.split('/').last],
          workingDirectory: src.parent.path,
          timeout: const Duration(minutes: 2),
          tag: 'web_reverse.zip_archive',
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
        final r = await runTrackedProcessOrFailed(
          'powershell',
          [
            '-Command',
            'Compress-Archive -Path "${src.path}\\*" -DestinationPath "${out.path}" -Force',
          ],
          timeout: const Duration(minutes: 2),
          tag: 'web_reverse.compress_archive',
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
      silentLog(
        'web_reverse_session_controller',
        'exportSessionBundle',
        error,
        stack,
      );
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
      final har = decodeStringKeyedJsonMap(raw);
      if (har == null) return (loaded: 0, skipped: 0);
      final log = stringKeyedMapFromValue(har['log']);
      final entries = log['entries'] as List?;
      if (entries == null) return (loaded: 0, skipped: 0);
      // 解析所有 entry 到候选列表；merge=false 时清空旧表后按解析顺序回填，
      // merge=true 时与现有列表按时间归并并 dedup。
      final candidates = <CdpNetworkEntry>[];
      var loaded = 0;
      final parseStart = entries.length > _maxNetworkEntries
          ? entries.length - _maxNetworkEntries
          : 0;
      var skipped = parseStart;
      for (var i = parseStart; i < entries.length; i++) {
        final raw = entries[i];
        if (raw is! Map) {
          skipped++;
          continue;
        }
        final req = stringKeyedMapFromValue(raw['request']);
        final res = stringKeyedMapFromValue(raw['response']);
        if (req.isEmpty) {
          skipped++;
          continue;
        }
        final resContent = stringKeyedMapFromValue(res['content']);
        final postData = stringKeyedMapFromValue(req['postData']);
        final url = _capPlainWebReverseText(
          '${req['url'] ?? ''}',
          _maxImportedUrlChars,
        );
        final method = _capPlainWebReverseText('${req['method'] ?? 'GET'}', 32);
        final reqHeaders = _headersFromHarList(req['headers']);
        final resHeaders = _headersFromHarList(res['headers']);
        final startedRaw = '${raw['startedDateTime'] ?? ''}';
        DateTime started;
        try {
          started = DateTime.parse(startedRaw);
        } catch (_) {
          started = DateTime.now().toUtc().subtract(
            Duration(milliseconds: entries.length - i),
          );
        }
        final timeMs = nonNegativeIntFromValue(raw['time'], fallback: 0);
        // requestId 在 merge 时必须避免与现有 / 同批次冲突；用 ts 后缀保证唯一。
        final reqId = merge
            ? 'har-${started.microsecondsSinceEpoch}-$i'
            : 'har-$i';
        final entry =
            CdpNetworkEntry(
                requestId: reqId,
                url: url,
                method: method,
                timestamp: started,
                resourceType: _resourceTypeFromMime(
                  '${resContent['mimeType'] ?? ''}',
                ),
              )
              ..requestHeaders = reqHeaders
              ..requestPostData = _importedTextOrNull(
                postData['text'],
                label: 'HAR request body',
              )
              ..responseHeaders = resHeaders
              ..statusCode = optionalIntFromValue(res['status'])
              ..statusText = res['statusText'] as String?
              ..mimeType = '${resContent['mimeType'] ?? ''}'
              ..encodedDataLength = optionalNonNegativeIntFromValue(
                res['bodySize'],
              )
              ..responseReceivedAt = started.add(
                Duration(milliseconds: timeMs ~/ 2),
              )
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
        final combined = <CdpNetworkEntry>[..._networkRequests, ...candidates]
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
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

  /// Releases browser/CDP processes, auxiliary servers, subscriptions, and the
  /// raw event bus through one idempotent shutdown future.
  Future<void> shutdown() {
    final active = _shutdownFuture;
    if (active != null) return active;
    _disposed = true;
    _stopped = true;
    for (final t in _cronTimers.values) {
      t.cancel();
    }
    _cronTimers.clear();
    final shutdown =
        () async {
          try {
            await _safeStop();
          } finally {
            await runAsyncCleanupBounded(
              _rawCdpEventBus.close,
              timeout: _browserCleanupTimeout,
              onError: (error, stack) => silentLog(
                'web_reverse_session_controller',
                'close raw CDP event bus',
                error,
                stack,
              ),
            );
          }
        }().catchError((Object error, StackTrace stack) {
          silentLog('web_reverse_session_controller', 'shutdown', error, stack);
        });
    _shutdownFuture = shutdown;
    return shutdown;
  }

  @override
  void dispose() {
    if (_notifierDisposed) return;
    _notifierDisposed = true;
    unawaited(shutdown());
    screencastFrameNotifier.dispose();
    super.dispose();
  }

  /// 把当前 target 的网络/控制台/WS 帧打成一个可重放的 JSON 快照。
  /// 用于离线分析、Issue 复现、跨机器协作；importSnapshot 反向还原。
  /// 不包含截屏二进制 / cookie / 浏览器进程信息。
  Map<String, Object?> exportSnapshot() {
    return <String, Object?>{
      'version': 1,
      'exported_ms': DateTime.now().millisecondsSinceEpoch,
      'target_id': _currentTargetId,
      'network': _networkRequests
          .map(
            (e) => <String, Object?>{
              'request_id': e.requestId,
              'url': e.url,
              'method': e.method,
              'ts': e.timestamp.toIso8601String(),
              'resource_type': e.resourceType,
              'request_headers': e.requestHeaders,
              'request_post': e.requestPostData,
              'status': e.statusCode,
              'status_text': e.statusText,
              'mime_type': e.mimeType,
              'response_headers': e.responseHeaders,
              'remote': e.remoteAddress,
              'protocol': e.protocol,
              'from_cache': e.fromCache,
              'encoded_len': e.encodedDataLength,
              'decoded_len': e.decodedBodyLength,
              'initiator_type': e.initiatorType,
              'initiator_url': e.initiatorUrl,
              'initiator_line': e.initiatorLineNumber,
              'initiator_col': e.initiatorColumnNumber,
              'cached_body': e.cachedBody,
              'cached_body_b64': e.cachedBodyBase64,
              'failed': e.failed,
              'error_text': e.errorText,
              'response_received_ms':
                  e.responseReceivedAt?.millisecondsSinceEpoch,
              'loading_finished_ms':
                  e.loadingFinishedAt?.millisecondsSinceEpoch,
              'ws_frames': e.wsFrames
                  .map(
                    (f) => <String, Object?>{
                      'dir': f.direction.name,
                      'ts': f.timestamp.toIso8601String(),
                      'opcode': f.opcode,
                      'mask': f.mask,
                      'payload': f.payload,
                      'error': f.errorMessage,
                    },
                  )
                  .toList(),
            },
          )
          .toList(),
      'console': _consoleMessages
          .map(
            (c) => <String, Object?>{
              'level': c.level,
              'text': c.text,
              'ts': c.timestamp.toIso8601String(),
            },
          )
          .toList(),
    };
  }

  /// 用 JSON 快照覆盖当前 target 的网络/控制台缓冲（保留实时连接、不动 cron/hook）。
  /// 返回成功导入的网络请求数；格式错误 / version 不识别时返回 -1。
  int importSnapshot(Map<String, Object?> snap) {
    try {
      final v = snap['version'];
      if (v is! int || v != 1) return -1;
      _networkRequests.clear();
      _networkByRequestId.clear();
      _consoleMessages.clear();
      final rawNet = snap['network'];
      if (rawNet is List) {
        final netStart = rawNet.length > _maxNetworkEntries
            ? rawNet.length - _maxNetworkEntries
            : 0;
        final usedRequestIds = <String>{};
        for (final raw in rawNet.skip(netStart)) {
          if (raw is! Map) continue;
          final m = raw.cast<String, Object?>();
          final requestId = _uniqueImportedRequestId(
            m['request_id'],
            usedRequestIds,
          );
          final entry = CdpNetworkEntry(
            requestId: requestId,
            url: _capPlainWebReverseText(
              '${m['url'] ?? ''}',
              _maxImportedUrlChars,
            ),
            method: _capPlainWebReverseText('${m['method'] ?? 'GET'}', 32),
            timestamp: dateTimeFromValue(m['ts']) ?? DateTime.now(),
            resourceType: _capPlainWebReverseText(
              '${m['resource_type'] ?? 'Other'}',
              64,
            ),
          );
          entry.requestHeaders = _headersFromSnapshotMap(m['request_headers']);
          entry.requestPostData = _importedTextOrNull(
            m['request_post'],
            label: 'snapshot request body',
          );
          entry.statusCode = m['status'] as int?;
          entry.statusText = _importedShortTextOrNull(m['status_text']);
          entry.mimeType = _importedShortTextOrNull(m['mime_type']);
          entry.responseHeaders = _headersFromSnapshotMap(
            m['response_headers'],
          );
          entry.remoteAddress = _importedShortTextOrNull(m['remote']);
          entry.protocol = _importedShortTextOrNull(m['protocol']);
          entry.fromCache = m['from_cache'] == true;
          entry.encodedDataLength = m['encoded_len'] as int?;
          entry.decodedBodyLength = m['decoded_len'] as int?;
          entry.initiatorType = _importedShortTextOrNull(m['initiator_type']);
          entry.initiatorUrl = _importedTextOrNull(
            m['initiator_url'],
            maxChars: _maxImportedUrlChars,
            label: 'snapshot initiator URL',
          );
          entry.initiatorLineNumber = m['initiator_line'] as int?;
          entry.initiatorColumnNumber = m['initiator_col'] as int?;
          final cachedBody = m['cached_body'];
          if (cachedBody is String &&
              cachedBody.length <= _maxImportedBodyChars) {
            entry.cachedBody = cachedBody;
            entry.cachedBodyBase64 = m['cached_body_b64'] == true;
          }
          entry.failed = m['failed'] == true;
          entry.errorText = _importedTextOrNull(
            m['error_text'],
            label: 'snapshot error text',
          );
          final rrMs = m['response_received_ms'];
          if (rrMs is int) {
            entry.responseReceivedAt = DateTime.fromMillisecondsSinceEpoch(
              rrMs,
            );
          }
          final lfMs = m['loading_finished_ms'];
          if (lfMs is int) {
            entry.loadingFinishedAt = DateTime.fromMillisecondsSinceEpoch(lfMs);
          }
          final rawWs = m['ws_frames'];
          if (rawWs is List) {
            final wsStart = rawWs.length > _maxWebSocketFramesPerEntry
                ? rawWs.length - _maxWebSocketFramesPerEntry
                : 0;
            for (final rf in rawWs.skip(wsStart)) {
              if (rf is! Map) continue;
              final fm = rf.cast<String, Object?>();
              final dir = enumByNameOr(
                CdpWebSocketDirection.values,
                fm['dir'],
                fallback: CdpWebSocketDirection.received,
              );
              entry.wsFrames.add(
                CdpWebSocketFrame(
                  direction: dir,
                  timestamp: dateTimeFromValue(fm['ts']) ?? DateTime.now(),
                  opcode: fm['opcode'] is int ? fm['opcode'] as int : 1,
                  mask: fm['mask'] == true,
                  payload: _capPlainWebReverseText(
                    '${fm['payload'] ?? ''}',
                    _maxWebSocketFramePayloadChars,
                  ),
                  errorMessage: _importedShortTextOrNull(fm['error']),
                ),
              );
            }
          }
          _networkRequests.add(entry);
          _networkByRequestId[entry.requestId] = entry;
        }
      }
      final rawCon = snap['console'];
      if (rawCon is List) {
        final conStart = rawCon.length > _maxConsoleEntries
            ? rawCon.length - _maxConsoleEntries
            : 0;
        for (final raw in rawCon.skip(conStart)) {
          if (raw is! Map) continue;
          final m = raw.cast<String, Object?>();
          _consoleMessages.add(
            CdpConsoleEntry(
              level: '${m['level'] ?? 'log'}',
              text: _capWebReverseText(
                '${m['text'] ?? ''}',
                _maxConsoleTextChars,
                'console text',
              ),
              timestamp: dateTimeFromValue(m['ts']) ?? DateTime.now(),
            ),
          );
        }
      }
      _safeNotify();
      return _networkRequests.length;
    } catch (e, st) {
      silentLog('web_reverse_session_controller', 'importSnapshot', e, st);
      return -1;
    }
  }

  /// dispose 后再 notifyListeners 会抛 assertion。所有内部状态变更点统一走
  /// 这一层，避免任何回调（CDP 事件 / 异步收尾）在 controller 已 dispose
  /// 后再触发监听器。
  Future<void> _cancelRuntimeSubscription<T>(
    StreamSubscription<T>? subscription,
    String where,
  ) async {
    await cancelStreamSubscriptionBounded<T>(
      subscription,
      onError: (error, stack) => silentLog(
        'web_reverse_session_controller',
        'cancel $where',
        error,
        stack,
      ),
    );
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  /// Headless 批量采集要直接持有 browser-level CDP（共享 sessionId-less 命令通道）。
  /// 仅在 controller 已经 `start()` 过、且没被 dispose 时返回非空。
  WebReverseCdpClient? get browserCdpForBatch => _disposed ? null : _browserCdp;

  // ── 报文条件断点 ─────────────────────────────────────────────────
  // 与拦截规则不同，这里不改写也不放行 —— 只在「请求拦截」全局开关已开的
  // 前提下，对命中条件的请求额外记录一次 hit 事件，方便用户在 dashboard
  // 里 review 触发链。可选地伴随一段 JS 表达式被丢给 page 评估（典型用法：
  // `debugger`、`console.log(__OH__breakpoint__)`、调用站点录制脚本）。
  // 全部命中放进 _breakpointHits 环形缓冲（≤200 条），UI 自助消费。
  final List<WebReverseRequestBreakpoint> _requestBreakpoints =
      <WebReverseRequestBreakpoint>[];
  List<WebReverseRequestBreakpoint> get requestBreakpoints =>
      List<WebReverseRequestBreakpoint>.unmodifiable(_requestBreakpoints);

  final List<WebReverseRequestBreakpointHit> _breakpointHits =
      <WebReverseRequestBreakpointHit>[];
  List<WebReverseRequestBreakpointHit> get requestBreakpointHits =>
      List<WebReverseRequestBreakpointHit>.unmodifiable(_breakpointHits);

  static const int _kBreakpointHitsCap = 200;

  void setRequestBreakpoints(List<WebReverseRequestBreakpoint> list) {
    final bounded = <WebReverseRequestBreakpoint>[];
    final usedIds = <String>{};
    var retainedChars = 0;
    for (final indexed in list.take(maxRequestBreakpoints).indexed) {
      final normalized = _normalizeRequestBreakpoint(
        indexed.$2,
        id: _uniqueBoundedRuleId(
          indexed.$2.id,
          prefix: 'breakpoint',
          index: indexed.$1,
          used: usedIds,
        ),
      );
      final cost = _estimatedRequestBreakpointChars(normalized);
      if (retainedChars + cost > maxRuleCollectionChars) break;
      bounded.add(normalized);
      retainedChars += cost;
    }
    _requestBreakpoints
      ..clear()
      ..addAll(bounded);
    _safeNotify();
  }

  void clearRequestBreakpointHits() {
    _breakpointHits.clear();
    _safeNotify();
  }

  WebReverseRequestBreakpoint? _matchRequestBreakpoint(
    String method,
    String url,
    String? body,
  ) {
    for (final bp in _requestBreakpoints) {
      if (!bp.enabled) continue;
      if (bp.methodFilter.isNotEmpty &&
          bp.methodFilter.toUpperCase() != method.toUpperCase()) {
        continue;
      }
      if (bp.urlContains.isNotEmpty &&
          !url.toLowerCase().contains(bp.urlContains.toLowerCase())) {
        continue;
      }
      if (bp.bodyContains.isNotEmpty) {
        if (body == null || body.isEmpty) continue;
        if (!body.contains(bp.bodyContains)) continue;
      }
      return bp;
    }
    return null;
  }

  Future<void> _onRequestBreakpointHit(
    WebReverseRequestBreakpoint bp,
    String method,
    String url,
    String? body,
  ) async {
    _breakpointHits.add(
      WebReverseRequestBreakpointHit(
        breakpointId: bp.id,
        breakpointName: bp.name,
        method: method,
        url: url,
        at: DateTime.now(),
      ),
    );
    if (_breakpointHits.length > _kBreakpointHitsCap) {
      _breakpointHits.removeRange(
        0,
        _breakpointHits.length - _kBreakpointHitsCap,
      );
    }
    _safeNotify();
    if (bp.evalExpression.isNotEmpty) {
      final cdp = _browserCdp;
      if (cdp != null && _pageSessionId != null) {
        try {
          await cdp.send(
            'Runtime.evaluate',
            params: <String, Object?>{
              'expression': bp.evalExpression,
              'awaitPromise': true,
              'returnByValue': true,
              'silent': true,
            },
            sessionId: _pageSessionId,
            timeout: const Duration(seconds: 3),
          );
        } catch (e, st) {
          silentLog('web_reverse_session_controller', 'breakpoint_eval', e, st);
        }
      }
    }
  }

  // ── 多账号会话快照 ────────────────────────────────────────────────
  // 把当前页面的 cookies + 当前 origin 的 localStorage/sessionStorage 命名
  // 保存到内存快照（用户主动 export 后才落盘）。restore 时先清掉同 domain
  // 现有 cookies，再批量回写，并把 storage 注入回去（页面刷新后生效）。
  final List<WebReverseAccountSnapshot> _accountSnapshots =
      <WebReverseAccountSnapshot>[];
  List<WebReverseAccountSnapshot> get accountSnapshots =>
      List<WebReverseAccountSnapshot>.unmodifiable(_accountSnapshots);

  void setAccountSnapshots(List<WebReverseAccountSnapshot> list) {
    final bounded = <WebReverseAccountSnapshot>[];
    var retainedChars = 0;
    final start = list.length > maxAccountSnapshots
        ? list.length - maxAccountSnapshots
        : 0;
    for (var i = list.length - 1; i >= start; i--) {
      final normalized = _normalizeAccountSnapshot(list[i]);
      final cost = _estimatedAccountSnapshotChars(normalized);
      if (retainedChars + cost > maxAccountSnapshotsTotalChars) continue;
      bounded.add(normalized);
      retainedChars += cost;
    }
    _accountSnapshots
      ..clear()
      ..addAll(bounded.reversed);
    _safeNotify();
  }

  Future<String?> _currentPageOrigin() async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return null;
    try {
      final r = await cdp.send(
        'Runtime.evaluate',
        params: const <String, Object?>{
          'expression': 'location.origin',
          'returnByValue': true,
        },
        sessionId: _pageSessionId,
      );
      final result = r['result'] as Map?;
      final v = result?['value'];
      return v is String && v.isNotEmpty ? v : null;
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'read current page origin',
        error,
        stack,
      );
      return null;
    }
  }

  /// 抓取当前 cookies + 当前 origin 的两类 storage，返回新快照（未入列表）。
  Future<WebReverseAccountSnapshot?> captureAccountSnapshot(String name) async {
    final origin = await _currentPageOrigin();
    final cookies = await listCookies();
    List<({String key, String value})> ls = const [];
    List<({String key, String value})> ss = const [];
    if (origin != null) {
      ls = await listDomStorage(origin: origin, isLocalStorage: true);
      ss = await listDomStorage(origin: origin, isLocalStorage: false);
    }
    final snap = _normalizeAccountSnapshot(
      WebReverseAccountSnapshot(
        id: 'acct_${DateTime.now().microsecondsSinceEpoch}',
        name: name.isEmpty ? 'snapshot' : name,
        origin: origin ?? '',
        capturedAt: DateTime.now(),
        cookies: cookies
            .map((c) => Map<String, Object?>.from(c))
            .toList(growable: false),
        localStorage: <String, String>{for (final e in ls) e.key: e.value},
        sessionStorage: <String, String>{for (final e in ss) e.key: e.value},
      ),
    );
    _accountSnapshots.add(snap);
    var retainedChars = _accountSnapshots.fold<int>(
      0,
      (total, item) => total + _estimatedAccountSnapshotChars(item),
    );
    while (_accountSnapshots.length > maxAccountSnapshots ||
        retainedChars > maxAccountSnapshotsTotalChars) {
      retainedChars -= _estimatedAccountSnapshotChars(
        _accountSnapshots.removeAt(0),
      );
    }
    _safeNotify();
    return snap;
  }

  Future<void> deleteAccountSnapshot(String id) async {
    _accountSnapshots.removeWhere((s) => s.id == id);
    _safeNotify();
  }

  /// 应用一份快照：清掉当前 cookies + 当前 origin storage，回写快照内容。
  /// 调用方负责刷新页面让 JS 重新读取 storage / cookies。
  Future<bool> restoreAccountSnapshot(WebReverseAccountSnapshot snap) async {
    final cdp = _browserCdp;
    final pageSessionId = _pageSessionId;
    if (cdp == null || pageSessionId == null) return false;
    final boundedSnapshot = _normalizeAccountSnapshot(snap);
    var restoreActive = true;
    bool canContinue() =>
        restoreActive &&
        !_disposed &&
        identical(_browserCdp, cdp) &&
        _pageSessionId == pageSessionId;

    Future<bool> applySnapshot() async {
      try {
        await cdp.send(
          'Network.clearBrowserCookies',
          sessionId: pageSessionId,
          timeout: _accountSnapshotCommandTimeout,
        );
      } catch (error, stack) {
        silentLog(
          'web_reverse_session_controller',
          'clearBrowserCookies',
          error,
          stack,
        );
        return false;
      }
      if (boundedSnapshot.cookies.isNotEmpty) {
        try {
          await cdp.send(
            'Network.setCookies',
            params: <String, Object?>{'cookies': boundedSnapshot.cookies},
            sessionId: pageSessionId,
            timeout: _accountSnapshotCommandTimeout,
          );
        } catch (error, stack) {
          silentLog(
            'web_reverse_session_controller',
            'restore account snapshot cookies',
            error,
            stack,
          );
          return false;
        }
      }
      if (!canContinue()) return false;

      final origin = boundedSnapshot.origin;
      if (origin.isEmpty) return true;
      final storageEntries =
          <({bool isLocalStorage, String key, String value})>[
            for (final entry in boundedSnapshot.localStorage.entries)
              (isLocalStorage: true, key: entry.key, value: entry.value),
            for (final entry in boundedSnapshot.sessionStorage.entries)
              (isLocalStorage: false, key: entry.key, value: entry.value),
          ];
      try {
        await cdp.send(
          'DOMStorage.enable',
          sessionId: pageSessionId,
          timeout: _accountSnapshotCommandTimeout,
        );
      } catch (error, stack) {
        silentLog(
          'web_reverse_session_controller',
          'enable DOM storage for account snapshot',
          error,
          stack,
        );
        return false;
      }
      await forEachIndexWithConcurrencyLimit(
        itemCount: storageEntries.length,
        maxConcurrency: _accountSnapshotRestoreConcurrency,
        shouldContinue: canContinue,
        task: (index) async {
          final entry = storageEntries[index];
          try {
            await cdp.send(
              'DOMStorage.setDOMStorageItem',
              params: <String, Object?>{
                'storageId': <String, Object?>{
                  'securityOrigin': origin,
                  'isLocalStorage': entry.isLocalStorage,
                },
                'key': entry.key,
                'value': entry.value,
              },
              sessionId: pageSessionId,
              timeout: _accountSnapshotCommandTimeout,
            );
          } catch (error, stack) {
            restoreActive = false;
            silentLog(
              'web_reverse_session_controller',
              'restore account snapshot storage',
              error,
              stack,
            );
          }
        },
      );
      return canContinue();
    }

    try {
      final succeeded = await applySnapshot().timeout(
        _accountSnapshotRestoreTimeout,
      );
      if (succeeded) _safeNotify();
      return succeeded;
    } on TimeoutException catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        'restore account snapshot timeout',
        error,
        stack,
      );
      return false;
    } finally {
      restoreActive = false;
    }
  }

  // ─── Source Map 解析（Slice 3：源码板块集成） ───
  // 缓存 key 用脚本 URL；map 经常达到数 MB，因此同时限制条目数与估算字符数。
  // null 表示「尝试过但失败 / 没有 sourceMappingURL」，避免反复重试。
  final LifecycleLruCache<WebReverseSourceMapInfo?> _sourceMapCache =
      LifecycleLruCache<WebReverseSourceMapInfo?>(
        maxEntries: _maxSourceMapCacheEntries,
        maxCost: _maxSourceMapCacheChars,
        costOf: (value) => value?.estimatedRetainedChars ?? 1,
      );

  /// 从已 parsed 脚本的 URL 抓取并解析 source map：先 fetch 文件文本拿
  /// `//# sourceMappingURL=` 注释，再 fetch map JSON，最后 Dart 端 VLQ
  /// 解码 mappings 为 segments（按行索引）。
  /// 返回 null：网络失败 / map 不存在 / JSON 解析失败。
  Future<WebReverseSourceMapInfo?> fetchSourceMapForUrl(String url) async {
    if (url.isEmpty || url.length > _maxImportedUrlChars) return null;
    if (_sourceMapCache.containsKey(url)) return _sourceMapCache.get(url);
    if (_browserCdp == null || _pageSessionId == null) return null;
    try {
      final js =
          '''
(async () => {
  const maxBytes = $_maxSourceMapResponseBytes;
  const maxUrlChars = $_maxImportedUrlChars;
  const controller = new AbortController();
  const timer = setTimeout(
    () => controller.abort('timeout'),
    ${_sourceMapFetchTimeout.inMilliseconds},
  );
  const readText = async (response) => {
    const declared = Number(response.headers.get('content-length'));
    if (Number.isFinite(declared) && declared > maxBytes) {
      throw new Error('response exceeds source map size limit');
    }
    const reader = response.body && response.body.getReader
      ? response.body.getReader()
      : null;
    if (!reader) throw new Error('streaming response body unavailable');
    const chunks = [];
    let total = 0;
    try {
      while (true) {
        const part = await reader.read();
        if (part.done) break;
        const value = part.value || new Uint8Array();
        if (total + value.byteLength > maxBytes) {
          try { await reader.cancel(); } catch (_) {}
          throw new Error('response exceeds source map size limit');
        }
        chunks.push(value);
        total += value.byteLength;
      }
    } finally {
      try { reader.releaseLock(); } catch (_) {}
    }
    const bytes = new Uint8Array(total);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.byteLength;
    }
    return new TextDecoder('utf-8').decode(bytes);
  };
  try {
    const r = await fetch(${jsonEncode(url)}, { signal: controller.signal });
    if (!r.ok) throw new Error('script fetch failed: HTTP ' + r.status);
    const text = await readText(r);
    const m = /[#@]\\s*sourceMappingURL=(\\S+)/.exec(text);
    if (!m) return JSON.stringify({ error: 'no sourceMappingURL' });
    let mapUrl = m[1];
    let mapText;
    if (mapUrl.startsWith('data:')) {
      const comma = mapUrl.indexOf(',');
      if (comma < 0) throw new Error('invalid inline source map URL');
      const metadata = mapUrl.slice(0, comma).toLowerCase();
      const payload = mapUrl.slice(comma + 1);
      if (metadata.includes(';base64')) {
        const binary = atob(payload);
        if (binary.length > maxBytes) {
          throw new Error('inline source map exceeds size limit');
        }
        const bytes = new Uint8Array(binary.length);
        for (let i = 0; i < binary.length; i += 1) {
          bytes[i] = binary.charCodeAt(i);
        }
        mapText = new TextDecoder('utf-8').decode(bytes);
      } else {
        mapText = decodeURIComponent(payload);
      }
      mapUrl = '<inline>';
    } else {
      mapUrl = new URL(mapUrl, ${jsonEncode(url)}).toString();
      if (mapUrl.length > maxUrlChars) {
        throw new Error('source map URL exceeds size limit');
      }
      const mr = await fetch(mapUrl, { signal: controller.signal });
      if (!mr.ok) throw new Error('source map fetch failed: HTTP ' + mr.status);
      mapText = await readText(mr);
    }
    if (mapText.length > maxBytes) {
      throw new Error('source map exceeds size limit');
    }
    const map = JSON.parse(mapText);
    if (!map || typeof map !== 'object' || Array.isArray(map)) {
      throw new Error('source map root must be an object');
    }
    return JSON.stringify({ map, mapUrl });
  } catch (err) {
    return JSON.stringify({ error: String(err) });
  } finally {
    clearTimeout(timer);
  }
})()
''';
      final r = await sendRawCdp(
        method: 'Runtime.evaluate',
        paramsJson: jsonEncode({
          'expression': js,
          'awaitPromise': true,
          'returnByValue': true,
        }),
        timeout: _sourceMapFetchTimeout + const Duration(seconds: 2),
      );
      final raw = cdpStringResultValue(r);
      if (raw == null || raw.length > _maxSourceMapResultChars) {
        return _cacheSourceMap(url, null);
      }
      final wrap = decodeStringKeyedJsonMap(raw);
      if (wrap == null || wrap['error'] != null || wrap['map'] is! Map) {
        return _cacheSourceMap(url, null);
      }
      final mapJson = stringKeyedMapFromValue(wrap['map']);
      final rawSources = mapJson['sources'];
      final rawNames = mapJson['names'];
      final rawSourcesContent = mapJson['sourcesContent'];
      if (rawSources is! List ||
          rawSources.length > _maxSourceMapListEntries ||
          (rawNames is List && rawNames.length > _maxSourceMapListEntries) ||
          (rawSourcesContent is List &&
              rawSourcesContent.length > _maxSourceMapListEntries)) {
        return _cacheSourceMap(url, null);
      }
      final sources = stringListFromValue(rawSources);
      final names = stringListFromValue(rawNames);
      final sourcesContent = List<String?>.filled(sources.length, null);
      if (rawSourcesContent is List) {
        final copyLength = rawSourcesContent.length < sources.length
            ? rawSourcesContent.length
            : sources.length;
        for (var i = 0; i < copyLength; i += 1) {
          final value = rawSourcesContent[i];
          sourcesContent[i] = value == null ? null : '$value';
        }
      }
      final sourceRoot = '${mapJson['sourceRoot'] ?? ''}';
      final mappings = '${mapJson['mappings'] ?? ''}';
      final info = WebReverseSourceMapInfo(
        scriptUrl: url,
        mapUrl: '${wrap['mapUrl'] ?? ''}',
        sources: sources,
        sourcesContent: sourcesContent,
        names: names,
        sourceRoot: sourceRoot,
        mappings: mappings,
      );
      return _cacheSourceMap(url, info);
    } catch (e, st) {
      silentLog(
        'web_reverse_session_controller',
        'fetchSourceMapForUrl',
        e,
        st,
      );
      return _cacheSourceMap(url, null);
    }
  }

  WebReverseSourceMapInfo? _cacheSourceMap(
    String url,
    WebReverseSourceMapInfo? value,
  ) {
    _sourceMapCache.put(url, value);
    return value;
  }

  /// 清除某个脚本的 sourcemap 缓存（用户主动「重新抓取」时调）。
  void invalidateSourceMapForUrl(String url) {
    _sourceMapCache.remove(url);
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

  bool get isError => failed || (statusCode != null && statusCode! >= 400);
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

String _capWebReverseText(String text, int maxChars, String label) {
  if (text.length <= maxChars) return text;
  final omitted = text.length - maxChars;
  return '${text.substring(0, maxChars)}\n\n[OpenHand clipped $label: $omitted chars omitted]';
}

String _capPlainWebReverseText(String text, int maxChars) {
  return clipText(text, maxChars, suffix: '');
}

String? _importedTextOrNull(
  Object? value, {
  int maxChars = WebReverseSessionController._maxImportedBodyChars,
  required String label,
}) {
  if (value == null) return null;
  final text = '$value';
  return _capWebReverseText(text, maxChars, label);
}

String? _importedShortTextOrNull(Object? value) {
  if (value == null) return null;
  return _capPlainWebReverseText('$value', 512);
}

Map<String, String> _headersFromHarList(Object? raw) {
  if (raw is! List) return const <String, String>{};
  final out = <String, String>{};
  for (final header in raw.whereType<Map>()) {
    final name = _capPlainWebReverseText('${header['name'] ?? ''}', 256).trim();
    if (name.isEmpty) continue;
    out[name] = _capPlainWebReverseText(
      '${header['value'] ?? ''}',
      WebReverseSessionController._maxImportedHeaderValueChars,
    );
  }
  return out;
}

Map<String, String> _headersFromSnapshotMap(Object? raw) {
  if (raw is! Map) return const <String, String>{};
  final out = <String, String>{};
  for (final entry in raw.entries) {
    final name = _capPlainWebReverseText('${entry.key}', 256).trim();
    if (name.isEmpty) continue;
    out[name] = _capPlainWebReverseText(
      '${entry.value}',
      WebReverseSessionController._maxImportedHeaderValueChars,
    );
  }
  return out;
}

String _uniqueImportedRequestId(Object? raw, Set<String> used) {
  var base = _capPlainWebReverseText('${raw ?? ''}', 256).trim();
  if (base.isEmpty) base = 'snapshot-${used.length}';
  var candidate = base;
  var suffix = 1;
  while (!used.add(candidate)) {
    candidate = _capPlainWebReverseText('$base-$suffix', 256);
    suffix++;
  }
  return candidate;
}

String _normalizeSavedScriptName(String name, {String fallback = 'untitled'}) {
  final trimmed = name.trim();
  return _capPlainWebReverseText(
    trimmed.isEmpty ? fallback : trimmed,
    WebReverseSessionController.maxSavedScriptNameChars,
  );
}

int _normalizeCronInterval(int seconds) {
  if (seconds < WebReverseSessionController.minCronIntervalSeconds) {
    return WebReverseSessionController.minCronIntervalSeconds;
  }
  if (seconds > WebReverseSessionController.maxCronIntervalSeconds) {
    return WebReverseSessionController.maxCronIntervalSeconds;
  }
  return seconds;
}

String _normalizeWildcardPattern(String pattern) {
  final clipped = _capPlainWebReverseText(
    pattern.trim(),
    WebReverseSessionController.maxBreakpointTextChars,
  );
  if (!clipped.contains('**')) return clipped;
  final normalized = StringBuffer();
  var previousWasStar = false;
  for (final rune in clipped.runes) {
    final isStar = rune == 0x2A;
    if (!isStar || !previousWasStar) normalized.writeCharCode(rune);
    previousWasStar = isStar;
  }
  return normalized.toString();
}

final RegExp _webReverseHeaderNamePattern = RegExp(
  r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$",
);

Map<String, String> _normalizeRuleHeaders(Map<String, String> headers) {
  final normalized = <String, String>{};
  var remainingChars = WebReverseSessionController.maxRuleHeadersChars;
  for (final entry in headers.entries) {
    if (normalized.length >= WebReverseSessionController.maxRuleHeaderEntries ||
        remainingChars <= 0) {
      break;
    }
    final name = _capPlainWebReverseText(
      entry.key.trim(),
      WebReverseSessionController.maxRuleHeaderNameChars,
    );
    if (!_webReverseHeaderNamePattern.hasMatch(name) ||
        name.length > remainingChars) {
      continue;
    }
    remainingChars -= name.length;
    final valueLimit =
        remainingChars < WebReverseSessionController.maxRuleHeaderValueChars
        ? remainingChars
        : WebReverseSessionController.maxRuleHeaderValueChars;
    final value = _capPlainWebReverseText(
      entry.value.trim(),
      valueLimit,
    ).replaceAll('\r', ' ').replaceAll('\n', ' ');
    normalized[name] = value;
    remainingChars -= value.length;
  }
  return Map<String, String>.unmodifiable(normalized);
}

int _estimatedHeaderChars(Map<String, String> headers) =>
    headers.entries.fold<int>(
      0,
      (total, entry) => total + entry.key.length + entry.value.length,
    );

WebReverseInterceptRule _normalizeInterceptRule(WebReverseInterceptRule rule) {
  final replacement = _capPlainWebReverseText(
    rule.replaceUrl?.trim() ?? '',
    WebReverseSessionController.maxBreakpointTextChars,
  );
  return WebReverseInterceptRule(
    urlPattern: _normalizeWildcardPattern(rule.urlPattern),
    enabled: rule.enabled,
    block: rule.block,
    replaceUrl: replacement.isEmpty ? null : replacement,
    headerOverrides: _normalizeRuleHeaders(rule.headerOverrides),
  );
}

int _estimatedInterceptRuleChars(WebReverseInterceptRule rule) =>
    rule.urlPattern.length +
    (rule.replaceUrl?.length ?? 0) +
    _estimatedHeaderChars(rule.headerOverrides);

String _uniqueBoundedRuleId(
  String raw, {
  required String prefix,
  required int index,
  required Set<String> used,
}) {
  var base = _capPlainWebReverseText(
    raw.trim(),
    WebReverseSessionController.maxRuleIdChars,
  );
  if (base.isEmpty) base = '${prefix}_$index';
  if (used.add(base)) return base;
  for (var suffix = 2; ; suffix++) {
    final suffixText = '_$suffix';
    final baseLimit =
        WebReverseSessionController.maxRuleIdChars - suffixText.length;
    final candidate = '${_capPlainWebReverseText(base, baseLimit)}$suffixText';
    if (used.add(candidate)) return candidate;
  }
}

WebReverseMockRule _normalizeMockRule(
  WebReverseMockRule rule, {
  required String id,
}) {
  final contentType = _capPlainWebReverseText(
    rule.contentType.trim(),
    WebReverseSessionController.maxRuleContentTypeChars,
  );
  final status = rule.statusCode < 100
      ? 100
      : rule.statusCode > 599
      ? 599
      : rule.statusCode;
  return WebReverseMockRule(
    id: id,
    name: _capPlainWebReverseText(
      rule.name.trim(),
      WebReverseSessionController.maxRuleNameChars,
    ),
    urlPattern: _normalizeWildcardPattern(rule.urlPattern),
    enabled: rule.enabled,
    methodFilter: _capPlainWebReverseText(
      rule.methodFilter.trim().toUpperCase(),
      WebReverseSessionController.maxRuleMethodChars,
    ),
    statusCode: status,
    contentType: contentType.isEmpty
        ? 'application/json; charset=utf-8'
        : contentType,
    body: _capPlainWebReverseText(
      rule.body,
      WebReverseSessionController.maxMockBodyChars,
    ),
    extraHeaders: _normalizeRuleHeaders(rule.extraHeaders),
  );
}

int _estimatedMockRuleChars(WebReverseMockRule rule) =>
    rule.id.length +
    rule.name.length +
    rule.urlPattern.length +
    rule.methodFilter.length +
    rule.contentType.length +
    rule.body.length +
    _estimatedHeaderChars(rule.extraHeaders);

WebReverseRequestBreakpoint _normalizeRequestBreakpoint(
  WebReverseRequestBreakpoint breakpoint, {
  required String id,
}) {
  return WebReverseRequestBreakpoint(
    id: id,
    name: _capPlainWebReverseText(
      breakpoint.name.trim(),
      WebReverseSessionController.maxRuleNameChars,
    ),
    enabled: breakpoint.enabled,
    methodFilter: _capPlainWebReverseText(
      breakpoint.methodFilter.trim().toUpperCase(),
      WebReverseSessionController.maxRuleMethodChars,
    ),
    urlContains: _capPlainWebReverseText(
      breakpoint.urlContains.trim(),
      WebReverseSessionController.maxBreakpointTextChars,
    ),
    bodyContains: _capPlainWebReverseText(
      breakpoint.bodyContains,
      WebReverseSessionController.maxDebuggerExpressionChars,
    ),
    evalExpression: _capPlainWebReverseText(
      breakpoint.evalExpression,
      WebReverseSessionController.maxDebuggerExpressionChars,
    ),
  );
}

int _estimatedRequestBreakpointChars(WebReverseRequestBreakpoint breakpoint) =>
    breakpoint.id.length +
    breakpoint.name.length +
    breakpoint.methodFilter.length +
    breakpoint.urlContains.length +
    breakpoint.bodyContains.length +
    breakpoint.evalExpression.length;

const Set<String> _webReverseRecorderStepTypes = <String>{
  'navigate',
  'click',
  'input',
  'change',
  'assertText',
  'assertVisible',
};

Map<String, Object?>? _normalizeRecorderStep(Map<String, Object?> step) {
  final type = _capPlainWebReverseText('${step['type'] ?? ''}'.trim(), 32);
  if (!_webReverseRecorderStepTypes.contains(type)) return null;
  final normalized = <String, Object?>{'type': type};
  final timestamp = optionalIntegralIntFromValue(step['ts']);
  if (timestamp != null) normalized['ts'] = timestamp;

  if (type == 'navigate') {
    final url = _capPlainWebReverseText(
      '${step['url'] ?? ''}'.trim(),
      WebReverseSessionController.maxBreakpointTextChars,
    );
    if (url.isEmpty) return null;
    normalized['url'] = url;
    return Map<String, Object?>.unmodifiable(normalized);
  }

  final selector = _capPlainWebReverseText(
    '${step['selector'] ?? ''}'.trim(),
    WebReverseSessionController.maxBreakpointTextChars,
  );
  if (selector.isEmpty) return null;
  normalized['selector'] = selector;
  switch (type) {
    case 'click':
      final text = _capPlainWebReverseText(
        '${step['text'] ?? ''}',
        WebReverseSessionController.maxRecorderStepTextChars,
      );
      if (text.isNotEmpty) normalized['text'] = text;
      if (step['doubleClick'] == true) normalized['doubleClick'] = true;
      break;
    case 'input':
      normalized['value'] = _capPlainWebReverseText(
        '${step['value'] ?? ''}',
        WebReverseSessionController.maxRecorderStepTextChars,
      );
      break;
    case 'change':
      final value = step['value'];
      normalized['value'] = value == null || value is bool || value is num
          ? value
          : _capPlainWebReverseText(
              '$value',
              WebReverseSessionController.maxRecorderStepTextChars,
            );
      break;
    case 'assertText':
      normalized['expected'] = _capPlainWebReverseText(
        '${step['expected'] ?? ''}',
        WebReverseSessionController.maxRecorderStepTextChars,
      );
      break;
    case 'assertVisible':
      break;
    case 'navigate':
      break;
  }
  return Map<String, Object?>.unmodifiable(normalized);
}

int _estimatedRecorderStepChars(Map<String, Object?> step) =>
    step.values.fold<int>(
      32,
      (total, value) => total + (value is String ? value.length : 8),
    );

WebReverseAccountSnapshot _normalizeAccountSnapshot(
  WebReverseAccountSnapshot snapshot,
) {
  var remainingChars = WebReverseSessionController.maxAccountSnapshotChars;

  String takeText(Object? raw, int maxChars) {
    if (remainingChars <= 0) return '';
    final limit = remainingChars < maxChars ? remainingChars : maxChars;
    final value = _capPlainWebReverseText('${raw ?? ''}', limit);
    remainingChars -= value.length;
    return value;
  }

  final id = takeText(
    snapshot.id.trim(),
    WebReverseSessionController.maxRuleIdChars,
  );
  final name = takeText(
    snapshot.name.trim(),
    WebReverseSessionController.maxAccountSnapshotNameChars,
  );
  final origin = takeText(
    snapshot.origin.trim(),
    WebReverseSessionController.maxBreakpointTextChars,
  );
  final cookies = <Map<String, Object?>>[];
  for (final raw in snapshot.cookies) {
    if (cookies.length >=
            WebReverseSessionController.maxAccountSnapshotCookies ||
        remainingChars <= 0) {
      break;
    }
    final rawName = '${raw['name'] ?? ''}'.trim();
    if (rawName.isEmpty) continue;
    final cookie = <String, Object?>{
      'name': takeText(
        rawName,
        WebReverseSessionController.maxRuleHeaderNameChars,
      ),
      'value': takeText(
        raw['value'],
        WebReverseSessionController.maxAccountSnapshotValueChars,
      ),
    };
    final domain = takeText(
      raw['domain'],
      WebReverseSessionController.maxBreakpointTextChars,
    );
    final path = takeText(
      raw['path'],
      WebReverseSessionController.maxBreakpointTextChars,
    );
    final sameSite = takeText(raw['sameSite'], 64);
    if (domain.isNotEmpty) cookie['domain'] = domain;
    if (path.isNotEmpty) cookie['path'] = path;
    if (const <String>{'Strict', 'Lax', 'None'}.contains(sameSite)) {
      cookie['sameSite'] = sameSite;
    }
    if (raw['secure'] == true) cookie['secure'] = true;
    if (raw['httpOnly'] == true) cookie['httpOnly'] = true;
    final expires = raw['expires'];
    if (expires is num && expires.isFinite) cookie['expires'] = expires;
    cookies.add(Map<String, Object?>.unmodifiable(cookie));
  }

  Map<String, String> normalizeStorage(Map<String, String> storage) {
    final normalized = <String, String>{};
    for (final entry in storage.entries) {
      if (normalized.length >=
              WebReverseSessionController.maxAccountSnapshotStorageEntries ||
          remainingChars <= 0) {
        break;
      }
      final key = takeText(
        entry.key,
        WebReverseSessionController.maxBreakpointTextChars,
      );
      final value = takeText(
        entry.value,
        WebReverseSessionController.maxAccountSnapshotValueChars,
      );
      normalized[key] = value;
    }
    return Map<String, String>.unmodifiable(normalized);
  }

  return WebReverseAccountSnapshot(
    id: id,
    name: name,
    origin: origin,
    capturedAt: snapshot.capturedAt,
    cookies: List<Map<String, Object?>>.unmodifiable(cookies),
    localStorage: normalizeStorage(snapshot.localStorage),
    sessionStorage: normalizeStorage(snapshot.sessionStorage),
  );
}

int _estimatedAccountSnapshotChars(WebReverseAccountSnapshot snapshot) {
  var total =
      snapshot.id.length + snapshot.name.length + snapshot.origin.length;
  for (final cookie in snapshot.cookies) {
    for (final value in cookie.values) {
      if (value is String) total += value.length;
    }
  }
  for (final storage in <Map<String, String>>[
    snapshot.localStorage,
    snapshot.sessionStorage,
  ]) {
    for (final entry in storage.entries) {
      total += entry.key.length + entry.value.length;
    }
  }
  return total;
}

/// CDP 网络节流预设，对标 DevTools 的 Throttling 下拉。
enum WebReverseThrottlePreset {
  none(
    id: 'no-throttle',
    zhLabel: '不限速',
    zhHantLabel: '不限速',
    label: 'No throttling',
    frLabel: 'Aucune limitation',
    deLabel: 'Keine Drosselung',
    jaLabel: 'スロットリングなし',
    isOffline: false,
    latencyMs: 0,
    downloadKbps: 0,
    uploadKbps: 0,
  ),
  offline(
    id: 'offline',
    zhLabel: '离线',
    zhHantLabel: '離線',
    label: 'Offline',
    frLabel: 'Hors ligne',
    deLabel: 'Offline',
    jaLabel: 'オフライン',
    isOffline: true,
    latencyMs: 0,
    downloadKbps: 0,
    uploadKbps: 0,
  ),
  gprs(
    id: 'gprs',
    zhLabel: 'GPRS (50/20kbps, 500ms)',
    zhHantLabel: 'GPRS (50/20kbps, 500ms)',
    label: 'GPRS (50/20kbps, 500ms)',
    frLabel: 'GPRS (50/20kbps, 500ms)',
    deLabel: 'GPRS (50/20kbps, 500ms)',
    jaLabel: 'GPRS (50/20kbps, 500ms)',
    isOffline: false,
    latencyMs: 500,
    downloadKbps: 50,
    uploadKbps: 20,
  ),
  slow3g(
    id: 'slow-3g',
    zhLabel: '慢速 3G (400/400kbps, 400ms)',
    zhHantLabel: '慢速 3G (400/400kbps, 400ms)',
    label: 'Slow 3G',
    frLabel: '3G lente',
    deLabel: 'Langsames 3G',
    jaLabel: '低速 3G',
    isOffline: false,
    latencyMs: 400,
    downloadKbps: 400,
    uploadKbps: 400,
  ),
  fast3g(
    id: 'fast-3g',
    zhLabel: '快速 3G (1.6/750kbps, 150ms)',
    zhHantLabel: '快速 3G (1.6/750kbps, 150ms)',
    label: 'Fast 3G',
    frLabel: '3G rapide',
    deLabel: 'Schnelles 3G',
    jaLabel: '高速 3G',
    isOffline: false,
    latencyMs: 150,
    downloadKbps: 1600,
    uploadKbps: 750,
  ),
  fourG(
    id: '4g',
    zhLabel: '4G (4/3 Mbps, 80ms)',
    zhHantLabel: '4G (4/3 Mbps, 80ms)',
    label: '4G (4/3 Mbps, 80ms)',
    frLabel: '4G (4/3 Mbps, 80ms)',
    deLabel: '4G (4/3 Mbps, 80ms)',
    jaLabel: '4G (4/3 Mbps, 80ms)',
    isOffline: false,
    latencyMs: 80,
    downloadKbps: 4000,
    uploadKbps: 3000,
  ),
  weakWifi(
    id: 'wifi',
    zhLabel: '弱 Wi-Fi (10/5 Mbps, 40ms)',
    zhHantLabel: '弱 Wi-Fi (10/5 Mbps, 40ms)',
    label: 'Weak Wi-Fi (10/5 Mbps, 40ms)',
    frLabel: 'Wi-Fi faible (10/5 Mbps, 40ms)',
    deLabel: 'Schwaches Wi-Fi (10/5 Mbps, 40ms)',
    jaLabel: '弱い Wi-Fi (10/5 Mbps, 40ms)',
    isOffline: false,
    latencyMs: 40,
    downloadKbps: 10000,
    uploadKbps: 5000,
  ),
  custom(
    id: 'custom',
    zhLabel: '自定义',
    zhHantLabel: '自訂',
    label: 'Custom',
    frLabel: 'Personnalisé',
    deLabel: 'Benutzerdefiniert',
    jaLabel: 'カスタム',
    isOffline: false,
    latencyMs: 0,
    downloadKbps: 0,
    uploadKbps: 0,
  );

  const WebReverseThrottlePreset({
    required this.id,
    required this.zhLabel,
    required this.label,
    required this.zhHantLabel,
    required this.frLabel,
    required this.deLabel,
    required this.jaLabel,
    required this.isOffline,
    required this.latencyMs,
    required this.downloadKbps,
    required this.uploadKbps,
  });

  final String id;
  final String zhLabel;
  final String zhHantLabel;
  final String label;
  final String frLabel;
  final String deLabel;
  final String jaLabel;
  final bool isOffline;
  final int latencyMs;
  final int downloadKbps;
  final int uploadKbps;

  bool get isSelectable => this != WebReverseThrottlePreset.custom;

  String displayLabel(Locale locale) => openHandLocalizedTextForLocale(
    locale,
    zh: zhLabel,
    zhHant: zhHantLabel,
    en: label,
    fr: frLabel,
    de: deLabel,
    ja: jaLabel,
  );

  Map<String, Object?> get cdpParams => <String, Object?>{
    'offline': isOffline,
    'latency': latencyMs,
    'downloadThroughput': _networkThroughputFromKbps(downloadKbps),
    'uploadThroughput': _networkThroughputFromKbps(uploadKbps),
  };
}

class WebReverseNetworkConditions {
  const WebReverseNetworkConditions({
    required this.preset,
    required this.offline,
    required this.latencyMs,
    required this.downloadKbps,
    required this.uploadKbps,
  });

  factory WebReverseNetworkConditions.fromPreset(
    WebReverseThrottlePreset preset,
  ) {
    if (preset == WebReverseThrottlePreset.custom) {
      return none;
    }
    return WebReverseNetworkConditions(
      preset: preset,
      offline: preset.isOffline,
      latencyMs: preset.latencyMs,
      downloadKbps: preset.downloadKbps,
      uploadKbps: preset.uploadKbps,
    );
  }

  factory WebReverseNetworkConditions.fromCdpParams(
    Map<String, Object?> params,
  ) {
    final offline = params['offline'] == true;
    final latencyMs = _objectAsNonNegativeInt(params['latency']);
    final downloadKbps = _networkKbpsFromThroughput(
      params['downloadThroughput'],
    );
    final uploadKbps = _networkKbpsFromThroughput(params['uploadThroughput']);
    final preset = _matchNetworkPreset(
      offline: offline,
      latencyMs: latencyMs,
      downloadKbps: downloadKbps,
      uploadKbps: uploadKbps,
    );
    return WebReverseNetworkConditions(
      preset: preset,
      offline: offline,
      latencyMs: latencyMs,
      downloadKbps: downloadKbps,
      uploadKbps: uploadKbps,
    ).normalized;
  }

  static const none = WebReverseNetworkConditions(
    preset: WebReverseThrottlePreset.none,
    offline: false,
    latencyMs: 0,
    downloadKbps: 0,
    uploadKbps: 0,
  );

  final WebReverseThrottlePreset preset;
  final bool offline;
  final int latencyMs;
  final int downloadKbps;
  final int uploadKbps;

  bool get isNoThrottle =>
      !offline && latencyMs <= 0 && downloadKbps <= 0 && uploadKbps <= 0;

  WebReverseNetworkConditions get normalized {
    if (isNoThrottle) return none;
    return WebReverseNetworkConditions(
      preset: preset == WebReverseThrottlePreset.none
          ? WebReverseThrottlePreset.custom
          : preset,
      offline: offline,
      latencyMs: _nonNegativeInt(latencyMs),
      downloadKbps: _nonNegativeInt(downloadKbps),
      uploadKbps: _nonNegativeInt(uploadKbps),
    );
  }

  Map<String, Object?> get cdpParams => <String, Object?>{
    'offline': offline,
    'latency': _nonNegativeInt(latencyMs),
    'downloadThroughput': _networkThroughputFromKbps(downloadKbps),
    'uploadThroughput': _networkThroughputFromKbps(uploadKbps),
  };

  @override
  bool operator ==(Object other) {
    return other is WebReverseNetworkConditions &&
        other.preset == preset &&
        other.offline == offline &&
        other.latencyMs == latencyMs &&
        other.downloadKbps == downloadKbps &&
        other.uploadKbps == uploadKbps;
  }

  @override
  int get hashCode =>
      Object.hash(preset, offline, latencyMs, downloadKbps, uploadKbps);
}

int _networkThroughputFromKbps(int kbps) {
  if (kbps <= 0) return -1;
  return (kbps * 1024 / 8).round();
}

int _networkKbpsFromThroughput(Object? value) {
  final throughput = value is num ? value : num.tryParse('$value');
  if (throughput == null || throughput <= 0) return 0;
  return (throughput * 8 / 1024).round();
}

WebReverseThrottlePreset _matchNetworkPreset({
  required bool offline,
  required int latencyMs,
  required int downloadKbps,
  required int uploadKbps,
}) {
  for (final preset in WebReverseThrottlePreset.values) {
    if (!preset.isSelectable) continue;
    if (preset.isOffline == offline &&
        preset.latencyMs == latencyMs &&
        preset.downloadKbps == downloadKbps &&
        preset.uploadKbps == uploadKbps) {
      return preset;
    }
  }
  return WebReverseThrottlePreset.custom;
}

int _objectAsNonNegativeInt(Object? value) {
  final parsed = optionalRoundedIntFromValue(value) ?? 0;
  return _nonNegativeInt(parsed);
}

int _nonNegativeInt(int value) => value < 0 ? 0 : value;

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

/// 抓取并解析后的 Source Map 信息，供源码板块「跳到原始源」使用。
/// 这里只保留浏览器侧返回的字段；mappings 解码是按需进行的：调用
/// [decodeOriginalLocation] 才会扫到目标段。
class WebReverseSourceMapInfo {
  WebReverseSourceMapInfo({
    required this.scriptUrl,
    required this.mapUrl,
    required this.sources,
    required this.sourcesContent,
    required this.names,
    required this.sourceRoot,
    required this.mappings,
  });

  /// 生成文件（压缩 JS）的 URL。
  final String scriptUrl;

  /// 来源 source map 的 URL（data: 内联时为 `<inline>`）。
  final String mapUrl;

  /// 原始源文件列表（sourceRoot 拼接前）。
  final List<String> sources;

  /// 与 [sources] 同长，可能含 null 表示该源未内联到 map 里。
  final List<String?> sourcesContent;

  /// 名字表，给段四元组中的 name 字段使用。
  final List<String> names;

  /// 拼接前缀。
  final String sourceRoot;

  /// 原始 mappings 字符串（按 `;` 分行，按 `,` 分段，每段 VLQ 编码）。
  final String mappings;

  /// Approximate retained UTF-16 character count used by the session LRU.
  int get estimatedRetainedChars =>
      scriptUrl.length +
      mapUrl.length +
      sourceRoot.length +
      mappings.length +
      sources.fold<int>(0, (total, value) => total + value.length) +
      sourcesContent.fold<int>(
        0,
        (total, value) => total + (value?.length ?? 0),
      ) +
      names.fold<int>(0, (total, value) => total + value.length);

  /// 通过 sourceRoot 拼出最终展示用的 source URL。
  String resolveSource(int sourceIndex) {
    if (sourceIndex < 0 || sourceIndex >= sources.length) return '?';
    final rel = sources[sourceIndex];
    if (sourceRoot.isEmpty) return rel;
    return sourceRoot.endsWith('/') ? '$sourceRoot$rel' : '$sourceRoot/$rel';
  }

  /// 把 (生成文件行, 生成文件列) 反查到 (sourceIndex, origLine, origCol,
  /// nameIndex?)。0-based。命中不到返回 null。
  /// 实现与独立 SourceMap 对话框等价，但内联到模型里便于复用。
  Map<String, int?>? decodeOriginalLocation({
    required int generatedLine,
    required int generatedColumn,
  }) {
    final lines = mappings.split(';');
    if (generatedLine < 0 || generatedLine >= lines.length) return null;
    var srcIdx = 0;
    var origLine = 0;
    var origCol = 0;
    var nameIdx = 0;
    for (var li = 0; li < generatedLine; li += 1) {
      for (final seg in lines[li].split(',')) {
        if (seg.isEmpty) continue;
        final nums = vlqDecode(seg);
        if (nums.length >= 4) {
          srcIdx += nums[1];
          origLine += nums[2];
          origCol += nums[3];
          if (nums.length >= 5) nameIdx += nums[4];
        }
      }
    }
    final lineStr = lines[generatedLine];
    if (lineStr.isEmpty) return null;
    var genCol = 0;
    Map<String, int?>? best;
    for (final seg in lineStr.split(',')) {
      if (seg.isEmpty) continue;
      final nums = vlqDecode(seg);
      genCol += nums[0];
      if (nums.length >= 4) {
        srcIdx += nums[1];
        origLine += nums[2];
        origCol += nums[3];
        if (nums.length >= 5) nameIdx += nums[4];
      }
      if (genCol > generatedColumn) break;
      best = <String, int?>{
        'source': srcIdx,
        'origLine': origLine,
        'origCol': origCol,
        'name': nums.length >= 5 ? nameIdx : null,
      };
    }
    return best;
  }
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
        urlPattern: stringFromValue(j['urlPattern']),
        enabled: boolFromValue(j['enabled'], defaultValue: true),
        block: boolFromValue(j['block']),
        replaceUrl: optionalStringFromValue(j['replaceUrl']),
        headerOverrides: _webReverseHeaderMapFromValue(j['headerOverrides']),
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
  }) => WebReverseInterceptRule(
    urlPattern: urlPattern ?? this.urlPattern,
    enabled: enabled ?? this.enabled,
    block: block ?? this.block,
    replaceUrl: replaceUrl ?? this.replaceUrl,
    headerOverrides: headerOverrides ?? this.headerOverrides,
  );

  bool matches(String url) {
    if (urlPattern.isEmpty) return false;
    return _webReverseWildcardPatternToRegExp(urlPattern).hasMatch(url);
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

  int get scriptSourceChars => scriptSources.values.fold<int>(
    0,
    (total, source) => total + source.length,
  );
}

/// 用户保存的 JS 片段（脚本注入库）。`runReplExpression` 执行后结果
/// 进入 Console 面板；持久化由 dashboard 写入 session metadata。
class WebReverseSnippet {
  factory WebReverseSnippet.fromJson(Map<String, Object?> json) {
    return WebReverseSnippet(
      id: stringFromValue(json['id']),
      name: stringFromValue(json['name'], fallback: 'untitled'),
      code: _webReverseRawTextFromValue(json['code']),
      updatedAt: _webReverseTimestampMsFromValue(json['updated_ms']),
    );
  }
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
}

/// 用户保存的 JS Hook（每个文档加载前注入）。
class WebReverseHook {
  factory WebReverseHook.fromJson(Map<String, Object?> json) {
    return WebReverseHook(
      id: stringFromValue(json['id']),
      name: stringFromValue(json['name'], fallback: 'untitled'),
      code: _webReverseRawTextFromValue(json['code']),
      enabled: boolFromValue(json['enabled'], defaultValue: true),
      updatedAt: _webReverseTimestampMsFromValue(json['updated_ms']),
    );
  }
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
}

class WebReverseCron {
  factory WebReverseCron.fromJson(Map<String, Object?> json) {
    final interval = optionalIntegralIntFromValue(json['interval_s']);
    return WebReverseCron(
      id: stringFromValue(json['id']),
      name: stringFromValue(json['name'], fallback: 'untitled'),
      code: _webReverseRawTextFromValue(json['code']),
      intervalSeconds: interval != null && interval >= 1 ? interval : 60,
      enabled: boolFromValue(json['enabled']),
      updatedAt: _webReverseTimestampMsFromValue(json['updated_ms']),
    );
  }
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
}

DateTime? _webReverseTimestampMsFromValue(Object? value) {
  final timestamp = optionalIntegralIntFromValue(value);
  return timestamp == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(timestamp);
}

String _webReverseRawTextFromValue(Object? value) {
  return value?.toString() ?? '';
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

/// 一条「报文条件断点」。匹配命中时只记录 hit + 可选触发 JS 表达式，
/// 不改变请求放行决策（用户仍需在「请求拦截」面板里继续/中止）。
class WebReverseRequestBreakpoint {
  const WebReverseRequestBreakpoint({
    required this.id,
    required this.name,
    required this.enabled,
    required this.methodFilter,
    required this.urlContains,
    required this.bodyContains,
    required this.evalExpression,
  });

  factory WebReverseRequestBreakpoint.fromJson(Map<String, Object?> j) =>
      WebReverseRequestBreakpoint(
        id: stringFromValue(j['id']),
        name: stringFromValue(j['name']),
        enabled: boolFromValue(j['enabled'], defaultValue: true),
        methodFilter: stringFromValue(j['method']),
        urlContains: stringFromValue(j['url_contains']),
        bodyContains: stringFromValue(j['body_contains']),
        evalExpression: _webReverseRawTextFromValue(j['eval']),
      );

  final String id;
  final String name;
  final bool enabled;
  final String methodFilter;
  final String urlContains;
  final String bodyContains;
  final String evalExpression;

  WebReverseRequestBreakpoint copyWith({
    String? name,
    bool? enabled,
    String? methodFilter,
    String? urlContains,
    String? bodyContains,
    String? evalExpression,
  }) => WebReverseRequestBreakpoint(
    id: id,
    name: name ?? this.name,
    enabled: enabled ?? this.enabled,
    methodFilter: methodFilter ?? this.methodFilter,
    urlContains: urlContains ?? this.urlContains,
    bodyContains: bodyContains ?? this.bodyContains,
    evalExpression: evalExpression ?? this.evalExpression,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'enabled': enabled,
    'method': methodFilter,
    'url_contains': urlContains,
    'body_contains': bodyContains,
    'eval': evalExpression,
  };
}

/// 单次断点命中记录。
class WebReverseRequestBreakpointHit {
  const WebReverseRequestBreakpointHit({
    required this.breakpointId,
    required this.breakpointName,
    required this.method,
    required this.url,
    required this.at,
  });

  final String breakpointId;
  final String breakpointName;
  final String method;
  final String url;
  final DateTime at;
}

/// 一份命名的账号会话快照（cookies + 当前 origin 的两类 storage）。
/// 在内存里持有；用户可在 UI 里手动 export 成 JSON 长期保留。
class WebReverseAccountSnapshot {
  const WebReverseAccountSnapshot({
    required this.id,
    required this.name,
    required this.origin,
    required this.capturedAt,
    required this.cookies,
    required this.localStorage,
    required this.sessionStorage,
  });

  factory WebReverseAccountSnapshot.fromJson(Map<String, Object?> j) {
    final timestampMs = optionalIntegralIntFromValue(j['captured_ms']);
    return WebReverseAccountSnapshot(
      id: stringFromValue(j['id']),
      name: stringFromValue(j['name']),
      origin: stringFromValue(j['origin']),
      capturedAt: timestampMs == null
          ? DateTime.now()
          : DateTime.fromMillisecondsSinceEpoch(timestampMs),
      cookies: stringKeyedMapListFromValue(j['cookies']),
      localStorage: _accountSnapshotStorageFromValue(j['localStorage']),
      sessionStorage: _accountSnapshotStorageFromValue(j['sessionStorage']),
    );
  }

  final String id;
  final String name;
  final String origin;
  final DateTime capturedAt;
  final List<Map<String, Object?>> cookies;
  final Map<String, String> localStorage;
  final Map<String, String> sessionStorage;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'origin': origin,
    'captured_ms': capturedAt.millisecondsSinceEpoch,
    'cookies': cookies,
    'localStorage': localStorage,
    'sessionStorage': sessionStorage,
  };
}

Map<String, String> _accountSnapshotStorageFromValue(Object? value) {
  final raw = stringKeyedMapFromValue(value);
  if (raw.isEmpty) return const <String, String>{};
  return Map<String, String>.unmodifiable(
    raw.map((key, item) => MapEntry(key, item?.toString() ?? '')),
  );
}

/// 本地 Mock 规则：URL 通配命中即用 Fetch.fulfillRequest 直接回 [statusCode]
/// + [body] + [contentType] + [extraHeaders]。methodFilter 留空表示全部方法。
class WebReverseMockRule {
  const WebReverseMockRule({
    required this.id,
    required this.name,
    required this.urlPattern,
    this.enabled = true,
    this.methodFilter = '',
    this.statusCode = 200,
    this.contentType = 'application/json; charset=utf-8',
    this.body = '{}',
    this.extraHeaders = const <String, String>{},
  });

  factory WebReverseMockRule.fromJson(Map<String, Object?> j) =>
      WebReverseMockRule(
        id: stringFromValue(j['id']),
        name: stringFromValue(j['name']),
        urlPattern: stringFromValue(j['urlPattern']),
        enabled: boolFromValue(j['enabled'], defaultValue: true),
        methodFilter: stringFromValue(j['method']),
        statusCode: clampedIntFromValue(
          j['status'],
          fallback: 200,
          min: 100,
          max: 599,
        ),
        contentType: stringFromValue(
          j['contentType'],
          fallback: 'application/json; charset=utf-8',
        ),
        body: stringFromValue(j['body']),
        extraHeaders: _webReverseHeaderMapFromValue(j['headers']),
      );

  final String id;
  final String name;
  final String urlPattern;
  final bool enabled;
  final String methodFilter;
  final int statusCode;
  final String contentType;
  final String body;
  final Map<String, String> extraHeaders;

  bool matches(String url) {
    if (urlPattern.isEmpty) return false;
    return _webReverseWildcardPatternToRegExp(urlPattern).hasMatch(url);
  }

  WebReverseMockRule copyWith({
    String? id,
    String? name,
    String? urlPattern,
    bool? enabled,
    String? methodFilter,
    int? statusCode,
    String? contentType,
    String? body,
    Map<String, String>? extraHeaders,
  }) => WebReverseMockRule(
    id: id ?? this.id,
    name: name ?? this.name,
    urlPattern: urlPattern ?? this.urlPattern,
    enabled: enabled ?? this.enabled,
    methodFilter: methodFilter ?? this.methodFilter,
    statusCode: statusCode ?? this.statusCode,
    contentType: contentType ?? this.contentType,
    body: body ?? this.body,
    extraHeaders: extraHeaders ?? this.extraHeaders,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'urlPattern': urlPattern,
    'enabled': enabled,
    'method': methodFilter,
    'status': statusCode,
    'contentType': contentType,
    'body': body,
    'headers': extraHeaders,
  };
}

Map<String, String> _webReverseHeaderMapFromValue(Object? value) {
  final raw = stringKeyedMapFromValue(value);
  if (raw.isEmpty) return const <String, String>{};
  final headers = <String, String>{};
  for (final entry in raw.entries) {
    final name = stringFromValue(entry.key);
    if (name.isEmpty) continue;
    headers[name] = stringFromValue(entry.value);
  }
  return Map<String, String>.unmodifiable(headers);
}

RegExp _webReverseWildcardPatternToRegExp(String pattern) {
  final buffer = StringBuffer('^');
  for (var i = 0; i < pattern.length; i++) {
    final ch = pattern[i];
    if (ch == '*') {
      buffer.write('.*');
    } else if (ch == '?') {
      buffer.write('.');
    } else {
      buffer.write(RegExp.escape(ch));
    }
  }
  buffer.write(r'$');
  return RegExp(buffer.toString(), caseSensitive: false);
}

/// 单次 mock 命中记录。
class WebReverseMockHit {
  const WebReverseMockHit({
    required this.ruleId,
    required this.ruleName,
    required this.status,
    required this.at,
  });
  final String ruleId;
  final String ruleName;
  final int status;
  final DateTime at;
}
