import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';

import '../../app/support/safe_subprocess.dart';
import '../../app/support/silent_log.dart';
import '../../shared/db/atomic_file_operations.dart';
import '../../shared/net/bounded_http_request.dart';
import '../../shared/net/http_redirect_utils.dart';
import '../../shared/util/async_concurrency.dart';
import '../../shared/util/bounded_base64.dart';
import '../../shared/util/bounded_file_io.dart';
import '../../shared/util/byte_size_format.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/lifecycle_cache.dart';
import '../../shared/util/localized_text.dart';
import '../../shared/util/text_clip.dart';
import '../../shared/util/timer_safety.dart';
import '../../shared/util/user_failure_message.dart';
import 'web_reverse_browser_launcher.dart';
import 'web_reverse_cdp_client.dart';
import 'web_reverse_cdp_http.dart';
import 'web_reverse_har_io.dart';
import 'web_reverse_har_replay_server.dart';
import 'web_reverse_mitmproxy_bridge.dart';
import 'web_reverse_pure_helpers.dart';
import 'web_reverse_session_artifacts.dart';
import 'web_reverse_session_config.dart';

/// 页面上下文求值的 CDP 方法名，见
/// [WebReverseSessionController.evaluateJavaScript]。
const String kCdpRuntimeEvaluate = 'Runtime.evaluate';

/// 注册“每个新 document 加载前执行”的初始化脚本，见
/// [WebReverseSessionController._installDocumentInitScript]。
const String kCdpPageAddScriptToEvaluateOnNewDocument =
    'Page.addScriptToEvaluateOnNewDocument';

/// 初始化脚本注入的等待上限：脚本本身很短，超时多半意味着页面已卡死。
const Duration _kInitScriptInstallTimeout = Duration(seconds: 5);
const Duration _kAliveProbeTimeout = Duration(seconds: 1);

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
  Future<({int port, int entryCount})?>? _harReplayStartTask;
  int _harReplayGeneration = 0;
  WebReverseHarReplayServer? get harReplayServer => _harReplayServer;

  bool _started = false;
  bool _stopped = false;
  bool _disposed = false;
  bool _notifierDisposed = false;
  bool _resourcesStopped = false;
  bool _preserveLog = true;
  bool _reattachAfterReconnectInFlight = false;
  bool _reattachAfterReconnectQueued = false;
  Future<void>? _startTask;
  Future<void>? _restartBrowserTask;
  Future<void>? _stopBrowserTask;
  Future<void>? _attachToTargetTask;
  Future<({String json, int bytes})?>? _heapSnapshotTask;
  Future<String?>? _traceTask;
  Completer<void>? _traceStopSignal;
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

  /// 即使 CDP 已断连，只要控制器仍持有浏览器进程，就必须继续占用运行时名额。
  bool get hasManagedBrowserProcess =>
      _launchResult != null || _stopBrowserTask != null;

  /// 真实判定外部浏览器进程是否还活着。CDP WebSocket 自身有重连，但当
  /// `_closed=true` 时表示重连已彻底失败 → 浏览器多半被用户手动关掉了。
  /// `isRunning` 只在浏览器 CDP 仍可用时为真，断连后 UI / Prompt 都应
  /// 明确进入可重启状态，而不是继续暴露一个已经失效的运行中端口。
  bool get isBrowserAlive {
    if (_stopped || _stopBrowserTask != null) return false;
    final cdp = _browserCdp;
    if (cdp == null) return false;
    return !cdp.isClosed;
  }

  Timer? _aliveWatchdog;
  int _aliveWatchdogFailureCount = 0;

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
  static const int _maxWebSocketFramePayloadChars = 8 * kBytesPerKiB;
  static const int _maxHeapSnapshotBytes = 120 * kBytesPerMiB;
  static const int _maxTraceEvents = 120000;
  static const int _maxTracePayloadChars = 48 * kBytesPerMiB;
  static const Duration _maxTraceDuration = Duration(minutes: 5);
  static const int _maxScreenshotBase64Chars = 64 * kBytesPerMiB;
  static const int _maxScreenshotDecodedBytes = 48 * kBytesPerMiB;
  static const int _maxScreenshotResponseCharacters =
      _maxScreenshotBase64Chars + 64 * kBytesPerKiB;
  static const int _maxScreencastFrameBytes = 6 * kBytesPerMiB;
  static const int maxRawCdpMethodChars = 256;
  static const int _maxRawCdpParamsJsonChars = 2 * kBytesPerMiB;
  static const int maxReplExpressionChars = 2 * kBytesPerMiB;
  static const int _maxReplHistoryExpressionChars = 64 * kBytesPerKiB;
  static const int _maxReplPreviewChars = 2 * kBytesPerKiB;
  static const int _maxConsoleTextChars = 64 * kBytesPerKiB;
  static const int _maxFindQueryChars = 512;
  static const int _maxFindTextNodes = 5000;
  static const int _maxFindTextChars = 2 * kBytesPerMiB;
  static const int _maxFindMatches = 2000;
  static const int _maxDomPathChars = 16 * kBytesPerKiB;
  static const int _aliveWatchdogFailureThreshold = 3;
  static const int _maxNetworkHeaderEntries = 256;
  static const int _maxNetworkHeadersChars = 2 * kBytesPerMiB;
  static const int _maxNetworkRequestBodyChars = 512 * kBytesPerKiB;
  static const int _maxCachedResponseBodyChars = 4 * kBytesPerMiB;
  static const int _maxMitmDecodedBodyBytes = 256 * kBytesPerKiB;
  static const int _maxImportedHarBytes = 64 * kBytesPerMiB;
  static const int _maxRedirectSteps = 64;
  static const int _maxInitiatorFrames = 256;
  static const int _maxInitiatorFrameChars = 8 * kBytesPerKiB;
  static const int _maxSecurityExplanationsChars = 64 * kBytesPerKiB;
  static const double _minMemorySamplingInterval = 1024;
  static const double _maxMemorySamplingInterval = 16.0 * kBytesPerMiB;
  static const int maxSavedScriptCodeChars = maxReplExpressionChars;
  static const int maxSavedScriptNameChars = 120;
  static const int maxSavedSnippets = 200;
  static const int maxSavedHooks = 100;
  static const int maxSavedCrons = 100;
  static const int minCronIntervalSeconds = 5;
  static const int maxCronIntervalSeconds = 24 * 60 * 60;
  static const int _maxImportedUrlChars = 16 * kBytesPerKiB;
  static const int _maxImportedBodyChars = 2 * kBytesPerMiB;
  static const int _maxImportedHeaderValueChars = 16 * kBytesPerKiB;
  static const int _maxSourceMapCacheEntries = 16;
  static const int _maxSourceMapCacheChars = 32 * kBytesPerMiB;
  static const int _maxSourceMapResponseBytes = 16 * kBytesPerMiB;
  static const int _maxSourceMapResultChars =
      _maxSourceMapResponseBytes + 64 * kBytesPerKiB;
  static const int _maxSourceMapListEntries = 100000;
  static const Duration _sourceMapFetchTimeout = Duration(seconds: 25);
  static const int _maxReplayResponsePreviewBytes = 4 * kBytesPerKiB;
  static const Duration _replayRequestTimeout = Duration(seconds: 25);
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
  static const int maxPageTargets = kWebReverseMaxPageTargets;
  static const int maxPageTargetIdChars = kWebReverseMaxPageTargetIdChars;
  static const int maxPageTargetUrlChars = kWebReverseMaxPageUrlChars;
  static const int maxPageTargetTitleChars = kWebReverseMaxPageTitleChars;
  static const int maxServiceWorkers = kWebReverseMaxServiceWorkers;
  static const int maxCookieNameChars = kWebReverseMaxCookieNameChars;
  static const int maxCookieValueChars = kWebReverseMaxCookieValueChars;
  static const int maxCookieDomainChars = kWebReverseMaxCookieDomainChars;
  static const int maxCookiePathChars = kWebReverseMaxCookiePathChars;
  static const int maxStorageKeyChars = kWebReverseMaxStorageKeyChars;
  static const int maxStorageValueChars = kWebReverseMaxStorageValueChars;
  static const int maxIndexedDbNameChars = kWebReverseMaxIndexedDbNameChars;
  static const int defaultIndexedDbPageSize =
      kWebReverseDefaultIndexedDbPageSize;
  static const int maxIndexedDbPageSize = kWebReverseMaxIndexedDbPageSize;
  static const int maxIndexedDbRetainedEntries =
      kWebReverseMaxIndexedDbRetainedEntries;
  static const int maxEditedRequestBodyChars = 2 * kBytesPerMiB;
  static const int maxEditedRequestBodyBase64Chars = 8 * kBytesPerMiB;
  static const int maxAccountSnapshotNameChars = 256;
  static const int maxAccountSnapshotCookies = 512;
  static const int maxAccountSnapshotStorageEntries = 2 * kBytesPerKiB;
  static const int maxAccountSnapshotValueChars = 256 * kBytesPerKiB;
  static const int maxAccountSnapshotChars = 4 * kBytesPerMiB;
  static const int maxAccountSnapshotsTotalChars = 16 * kBytesPerMiB;
  static const int _accountSnapshotRestoreConcurrency = 4;
  static const Duration _accountSnapshotCommandTimeout = Duration(seconds: 3);
  static const Duration _accountSnapshotRestoreTimeout = Duration(seconds: 45);

  // ── CDP 命令超时预算 ──────────────────────────────────────────────────
  // 按命令的开销量级分档，同档共用一个常量：调 某一类命令的预算只需改一处，
  // 也让「这条命令为什么给这么久」有据可查。

  /// 控制与轻量命令：enable / ack / 释放对象 / 输入派发 / 小体量求值。
  static const Duration _cdpControlTimeout = Duration(seconds: 3);

  /// 轻量查询与节点操作：滚动定位、高亮、指标开关。
  static const Duration _cdpLightCommandTimeout = Duration(seconds: 4);

  /// 脚本注入、节点解析与请求改写：需要页面侧配合但不返回大对象。
  static const Duration _cdpScriptTimeout = Duration(seconds: 5);

  /// DOM / 样式 / 监听器的结构化查询：返回体量随节点规模增长。
  static const Duration _cdpInspectTimeout = Duration(seconds: 6);

  /// 存储、导航与响应体等 I/O 类命令：受磁盘与网络影响。
  static const Duration _cdpIoTimeout = Duration(seconds: 10);

  /// 调试器求值与脚本源码：可能被页面自身代码阻塞。
  static const Duration _cdpDebuggerTimeout = Duration(seconds: 15);

  /// 截图：耗时随视口尺寸与渲染压力增长。
  static const Duration _cdpScreenshotTimeout = Duration(seconds: 30);

  /// 堆快照：数据量最大，单独给最长预算。
  static const Duration _cdpHeapSnapshotTimeout = Duration(seconds: 60);
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

  /// 只要条数，就不要走上面的拷贝型 getter。dashboard 的脏检查与 tab 徽标
  /// 每次 notifyListeners / 每帧都要读一次，走 unmodifiable 会各复制一份
  /// 最多 [_maxNetworkEntries] 个元素的列表。
  int get networkRequestCount => _networkRequests.length;
  int get consoleMessageCount => _consoleMessages.length;

  /// 网络 / 控制台数据的修订号。条目新增、原地更新（状态码、大小、耗时）、
  /// FIFO 淘汰、清空、导入都会推进它；screencast 帧不会——dashboard 依赖
  /// 这一点在收到画面帧时早退，不做整表重建。
  ///
  /// 必须有这个信号：条数打满 [_maxNetworkEntries] 后 length 恒定不变，
  /// 仅靠计数做脏检查会让网络面板彻底停止刷新。
  int get inspectorRevision => _inspectorRevision;
  int _inspectorRevision = 0;

  int _errorCountRevision = -1;
  int _cachedNetworkErrorCount = 0;
  int _cachedConsoleErrorCount = 0;

  /// 网络请求里的失败条数。按 [inspectorRevision] 记忆化：概览卡片与徽标
  /// 每帧都要读，逐帧全表扫描会直接吃掉 CDP 事件密集时的帧预算。
  int get networkErrorCount {
    _refreshErrorCounts();
    return _cachedNetworkErrorCount;
  }

  int get errorCount {
    _refreshErrorCounts();
    return _cachedNetworkErrorCount + _cachedConsoleErrorCount;
  }

  void _refreshErrorCounts() {
    if (_errorCountRevision == _inspectorRevision) return;
    _cachedNetworkErrorCount = _networkRequests.where((e) => e.isError).length;
    _cachedConsoleErrorCount = _consoleMessages
        .where((e) => e.level == 'error')
        .length;
    _errorCountRevision = _inspectorRevision;
  }

  /// 推进修订号并广播。所有会改变网络 / 控制台数据的路径都必须走这里，
  /// 而不是裸的 [_safeNotify]。
  void _notifyInspectorChanged() {
    _inspectorRevision++;
    _safeNotify();
  }

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
    if (_disposed || url.isEmpty) return;
    sourceJumpRequest.value = (url: url, line: line, col: col);
  }

  /// dashboard 完成跳转后调用以避免重复响应。
  void clearSourceJumpRequest() {
    if (_disposed) return;
    sourceJumpRequest.value = null;
  }

  int _screencastWidth = _screencastDefaultMaxWidth;
  int _screencastHeight = _screencastDefaultMaxHeight;
  int _screencastQuality = _screencastDefaultQuality;
  DateTime? _screencastStartedAt;

  /// 当前最新一帧（JPEG 字节）；切到浏览器 tab 后 widget 用 [Image.memory] 渲染。
  Uint8List? get latestScreencastFrame => _latestScreencastFrame;

  /// 当前帧的浏览器视口尺寸（CSS 像素）。
  int get screencastWidth => _screencastWidth;
  int get screencastHeight => _screencastHeight;

  bool get isScreencastActive => _screencastActive;

  /// 最近一次成功发送 `Page.startScreencast` 的时间。
  DateTime? get screencastStartedAt => _screencastStartedAt;

  // ── 生命周期 ─────────────────────────────────────────────────────────

  static const int _kInitialTargetPickAttempts = 16;
  static const Duration _kInitialTargetPickDelay = Duration(milliseconds: 150);
  static const Duration _browserStopGrace = Duration(milliseconds: 500);
  static const Duration _browserCleanupTimeout = Duration(seconds: 3);

  Future<void> start() {
    if (_disposed) {
      return Future<void>.error(StateError('Web 逆向会话已释放。'));
    }
    final active = _startTask;
    if (active != null) return active;
    if (_started) return Future<void>.value();
    late final Future<void> task;
    task = _startOnce().whenComplete(() {
      if (identical(_startTask, task)) {
        _startTask = null;
      }
    });
    _startTask = task;
    return task;
  }

  Future<void> _startOnce() async {
    _started = true;
    _resourcesStopped = false;
    try {
      final startUrl = _validatedPageUrlInput(config.targetUrl);
      if (startUrl == null) {
        throw const FormatException('目标 URL 无效或超过长度上限。');
      }
      await _artifacts.init();
      if (_stopped || _disposed) {
        _started = false;
        await _safeStop();
        return;
      }
      final launchResult = await _launcher.launch(
        executablePath: executablePath,
        browserKind: config.browserKind,
        userDataDir: config.userDataDir,
        startUrl: startUrl,
        proxy: config.proxy,
      );
      if (_stopped || _disposed) {
        _started = false;
        await _terminateBrowserLaunch(launchResult, '回收迟到启动的浏览器');
        await _safeStop();
        return;
      }
      _launchResult = launchResult;
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
      _resumeCronTimers();
      _startAliveWatchdog();
      _safeNotify();
    } catch (error) {
      _errorMessage = userFailureMessage(
        error,
        fallback: 'Web 逆向会话启动失败，请检查浏览器配置后重试。',
      );
      _started = false;
      await _safeStop();
      rethrow;
    }
  }

  Future<void> _attachToFirstPage() async {
    final cdp = _browserCdp!;
    bool isCurrent() =>
        !_disposed &&
        !_stopped &&
        _stopBrowserTask == null &&
        identical(_browserCdp, cdp) &&
        !cdp.isClosed;

    // 列出所有 page target，优先挑 config.targetUrl 同 origin 的目标页。
    // Chrome 冷启动时可能先暴露 about:blank / 恢复页；短暂轮询后仍未命中
    // 再回退到第一个可用 page，避免无限等待。
    List<WebReversePageTargetData> infos = const <WebReversePageTargetData>[];
    WebReversePageTargetData? chosen;
    for (var attempt = 0; attempt < _kInitialTargetPickAttempts; attempt++) {
      if (!isCurrent()) return;
      final targets = await cdp.send('Target.getTargets');
      infos = normalizeWebReversePageTargets(targets['targetInfos']);
      chosen = _chooseInitialPageTarget(
        infos,
        allowFallback: attempt == _kInitialTargetPickAttempts - 1,
      );
      if (chosen != null) {
        break;
      }
      final stillActive = await delayWhileContinuing(
        _kInitialTargetPickDelay,
        isCurrent,
      );
      if (!stillActive) return;
    }
    if (!isCurrent()) return;
    if (chosen == null) {
      throw CdpException(
        code: -1,
        message: openHandAmbientText(
          zh: '未发现目标 page target；浏览器可能没有打开目标页面',
          zhHant: '未發現目標 page target；瀏覽器可能沒有開啟目標頁面',
          en: 'No target page target was found. The browser may not have opened the target page.',
          fr: 'Aucune cible page target trouvée. Le navigateur n’a peut-être pas ouvert la page cible.',
          de: 'Kein Ziel-page target gefunden. Der Browser hat die Zielseite möglicherweise nicht geöffnet.',
          ja: '対象の page target が見つかりません。ブラウザで対象ページが開かれていない可能性があります。',
        ),
      );
    }
    final targetId = chosen.id;
    // 订阅 page target 的创建 / 销毁 / 信息变化，让 dashboard 实时更新 tab strip。
    await cdp.send(
      'Target.setDiscoverTargets',
      params: const <String, Object?>{'discover': true},
    );
    await _attachToTargetInternal(targetId);
    // 首次拉满当前所有 page target。
    _replacePageTargetsFromData(infos);
  }

  WebReversePageTargetData? _chooseInitialPageTarget(
    List<WebReversePageTargetData> pages, {
    required bool allowFallback,
  }) {
    if (pages.isEmpty) return null;

    final targetUri = _tryHttpUri(config.targetUrl);
    if (targetUri != null) {
      for (final page in pages) {
        final pageUri = _tryHttpUri(page.url);
        if (pageUri != null && _sameHttpOrigin(pageUri, targetUri)) {
          return page;
        }
      }
      if (!allowFallback) return null;
    }

    for (final page in pages) {
      if (_isUsefulInitialPageUrl(page.url)) {
        return page;
      }
    }
    return allowFallback || targetUri == null ? pages.first : null;
  }

  Uri? _tryHttpUri(String raw) {
    if (raw.length > maxPageTargetUrlChars) return null;
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

  String? _validatedPageTargetId(Object? raw) {
    if (raw is! String) return null;
    final normalized = raw.trim();
    if (normalized.isEmpty || normalized.length > maxPageTargetIdChars) {
      return null;
    }
    return normalized;
  }

  String? _validatedPageUrlInput(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty || normalized.length > maxPageTargetUrlChars) {
      return null;
    }
    return normalized;
  }

  String? _validatedCommandText(
    String raw,
    int maxChars, {
    bool allowEmpty = false,
    bool trim = true,
  }) {
    final normalized = trim ? raw.trim() : raw;
    if ((!allowEmpty && normalized.isEmpty) || normalized.length > maxChars) {
      return null;
    }
    return normalized;
  }

  String? _validatedIndexedDbIdentity(String raw) {
    return _validatedCommandText(
      raw,
      maxIndexedDbNameChars,
      allowEmpty: true,
      trim: false,
    );
  }

  /// 多标签页：dashboard 浏览器面板的 tab strip 数据源。每条 entry 反映一个
  /// CDP page target，包含 id / url / title / favicon。
  final List<CdpPageTargetSnapshot> _pageTargets = <CdpPageTargetSnapshot>[];
  final Map<String, int> _pageTargetFirstSeenOrder = <String, int>{};
  int _nextPageTargetFirstSeenOrder = 0;
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
    _inspectorRevision++;
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

  void _replacePageTargetsFromData(List<WebReversePageTargetData> next) {
    final retainedIds = next.map((target) => target.id).toSet();
    _pageTargetFirstSeenOrder.removeWhere(
      (targetId, _) => !retainedIds.contains(targetId),
    );
    _pageTargets
      ..clear()
      ..addAll(
        next.map((target) {
          _pageTargetFirstSeenOrder.putIfAbsent(
            target.id,
            () => _nextPageTargetFirstSeenOrder++,
          );
          return CdpPageTargetSnapshot(
            id: target.id,
            url: target.url,
            title: target.title,
          );
        }),
      );
    _safeNotify();
  }

  int _oldestEvictablePageTargetIndex() {
    var oldestIndex = -1;
    var oldestOrder = 1 << 62;
    for (var index = 0; index < _pageTargets.length; index++) {
      final target = _pageTargets[index];
      if (target.id == _currentTargetId) continue;
      final firstSeen = _pageTargetFirstSeenOrder[target.id] ?? -1;
      if (firstSeen < oldestOrder) {
        oldestIndex = index;
        oldestOrder = firstSeen;
      }
    }
    return oldestIndex;
  }

  void _upsertPageTarget(WebReversePageTargetData target) {
    final existingIndex = _pageTargets.indexWhere(
      (item) => item.id == target.id,
    );
    final snapshot = CdpPageTargetSnapshot(
      id: target.id,
      url: target.url,
      title: target.title,
    );
    if (existingIndex >= 0) {
      _pageTargets[existingIndex] = snapshot;
      return;
    }
    if (_pageTargets.length >= maxPageTargets) {
      final evictAt = _oldestEvictablePageTargetIndex();
      if (evictAt < 0) return;
      final removed = _pageTargets.removeAt(evictAt);
      _pageTargetFirstSeenOrder.remove(removed.id);
      _targetBuffers.remove(removed.id);
    }
    _pageTargetFirstSeenOrder[target.id] = _nextPageTargetFirstSeenOrder++;
    _pageTargets.add(snapshot);
  }

  /// 串行化 attach：cancel→await→assign `_pageEventsSub` 的写法在两条 attach
  /// 路径并发时会互相穿插，让其中一个订阅被覆盖后永不 cancel、持续回调
  /// `_onCdpEvent`。这里沿用本文件既有的单飞范式，把每次 attach 追加到上一次
  /// 之后串行执行。
  Future<void> _attachToTargetInternal(String targetId) {
    final previous = _attachToTargetTask;
    final task = (() async {
      if (previous != null) {
        // 前一次 attach 失败不应阻断本次；仅用于排队，吞掉其异常。
        await previous.catchError((_) {});
      }
      await _attachToTargetLocked(targetId);
    })();
    _attachToTargetTask = task;
    return task.whenComplete(() {
      if (identical(_attachToTargetTask, task)) {
        _attachToTargetTask = null;
      }
    });
  }

  Future<void> _attachToTargetLocked(String targetId) async {
    final normalizedTargetId = _validatedPageTargetId(targetId);
    if (normalizedTargetId == null) {
      throw const FormatException('页面目标 ID 无效。');
    }
    final cdp = _browserCdp!;
    // 切换前主动 detach 旧 session（如果有），避免事件流叠加。
    if (_pageSessionId != null) {
      _clearPendingFetchRequests();
      await stopRecording();
      await stopMemorySampling();
      try {
        await cdp.send(
          'Target.detachFromTarget',
          params: <String, Object?>{'sessionId': _pageSessionId},
        );
      } catch (error, stack) {
        silentLog('web_reverse_session_controller', '分离旧页面目标', error, stack);
      }
      _pageSessionId = null;
    }
    // 新 page 上 finder 还没注入；切完 target 第一次 findInPage 会按需注入。
    _findRequestGeneration += 1;
    _finderInstalled = false;
    _finderInstallTask = null;
    _performanceEnabled = false;
    _cssEnabled = false;
    _fpsCounterInstalled = false;
    _longTaskObserverInstalled = false;
    _rtcInstalled = false;
    _zoomScriptId = null;
    // Per-tab buffer：切 tab 前先把当前 target 的 panel 缓冲
    // 快照存到 _targetBuffers，切到目标 tab 后再 restore；新建 / 首次访问
    // 的 target 没有快照就只清空。Sources 端的 _userBreakpoints 仍按
    // (url,line) 维度持久化在 metadata 里，不在这里动。
    _captureBufferForCurrentTarget();
    _inspectorRevision++;
    _networkRequests.clear();
    _networkByRequestId.clear();
    _consoleMessages.clear();
    _parsedScripts.clear();
    _scriptSources.clear();
    _bpIdByKey.clear();
    final attachResult = await cdp.send(
      'Target.attachToTarget',
      params: <String, Object?>{
        'targetId': normalizedTargetId,
        'flatten': true,
      },
    );
    _pageSessionId = attachResult['sessionId'] as String?;
    _currentTargetId = normalizedTargetId;
    // 还原该 target 上次切走时保存的 panel 缓冲。新 target /
    // 第一次进入则跳过；网络 enable 之后再立刻补入，让 navigation 事件
    // 流接着累计。
    _restoreBufferForTarget(normalizedTargetId);
    await cdp.send(
      'Network.enable',
      params: const <String, Object?>{
        'maxResourceBufferSize': 16 * kBytesPerMiB,
        'maxTotalBufferSize': 64 * kBytesPerMiB,
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
    await _cancelRuntimeSubscription(_pageEventsSub, '替换页面事件订阅');
    _pageEventsSub = cdp.events
        .where((ev) => ev.sessionId == null || ev.sessionId == _pageSessionId)
        .listen(_onCdpEvent);
    _safeNotify();
  }

  /// 切换当前活跃的 page target。会重启 screencast（若已激活）。
  Future<void> switchToPageTarget(String targetId) async {
    final normalizedTargetId = _validatedPageTargetId(targetId);
    if (normalizedTargetId == null || _currentTargetId == normalizedTargetId) {
      return;
    }
    final cdp = _browserCdp;
    if (cdp == null) return;
    final wasActive = _screencastActive;
    if (wasActive) {
      try {
        await cdp.send('Page.stopScreencast', sessionId: _pageSessionId);
      } catch (error, stack) {
        silentLog(
          'web_reverse_session_controller',
          '切换页面目标前停止投屏',
          error,
          stack,
        );
      }
      _screencastActive = false;
      _screencastStartedAt = null;
    }
    try {
      await _attachToTargetInternal(normalizedTargetId);
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        '切换页面目标：$normalizedTargetId',
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
          '切换页面目标后恢复投屏',
          error,
          stack,
        );
      }
    }
  }

  /// 重排 page target 顺序：只动本地 `_pageTargets` 数组，并把当前顺序
  /// 同步给上层（持久化到 session metadata 由调用方负责）。
  void reorderPageTarget(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= _pageTargets.length ||
        newIndex < 0 ||
        newIndex > _pageTargets.length) {
      return;
    }
    final item = _pageTargets.removeAt(oldIndex);
    _pageTargets.insert(newIndex, item);
    _safeNotify();
  }

  /// 当前 page target 顺序的 ID 列表，调用方持久化用。
  List<String> get pageTargetOrder =>
      _pageTargets.map((e) => e.id).toList(growable: false);

  /// 用持久化过的顺序重排现有 `_pageTargets`：未在列表中的保留原序追加在末尾。
  void applyPageTargetOrder(Iterable<Object?> order) {
    if (_pageTargets.isEmpty) return;
    final existingIds = _pageTargets.map((target) => target.id).toSet();
    final indexById = <String, int>{};
    var inspected = 0;
    for (final rawId in order) {
      if (inspected++ >= maxPageTargets * 4 ||
          indexById.length >= maxPageTargets) {
        break;
      }
      final id = _validatedPageTargetId(rawId);
      if (id == null || !existingIds.contains(id)) continue;
      indexById.putIfAbsent(id, () => indexById.length);
    }
    if (indexById.isEmpty) return;
    final originalIndexById = <String, int>{
      for (var index = 0; index < _pageTargets.length; index++)
        _pageTargets[index].id: index,
    };
    _pageTargets.sort((a, b) {
      final ai = indexById[a.id];
      final bi = indexById[b.id];
      if (ai != null && bi != null) return ai.compareTo(bi);
      if (ai != null) return -1;
      if (bi != null) return 1;
      return (originalIndexById[a.id] ?? 0).compareTo(
        originalIndexById[b.id] ?? 0,
      );
    });
    _safeNotify();
  }

  /// 用新快照整体替换 [_pageTargets]，并统一执行数量、字段与当前页保护。
  void replacePageTargets(List<CdpPageTargetSnapshot> next) {
    final currentSnapshot = _pageTargets
        .where((target) => target.id == _currentTargetId)
        .firstOrNull;
    final normalized = normalizeWebReversePageTargets(
      next.map(
        (target) => <String, Object?>{
          'type': 'page',
          'targetId': target.id,
          'url': target.url,
          'title': target.title,
        },
      ),
      preferredId: _currentTargetId,
    ).toList(growable: true);
    if (currentSnapshot != null &&
        !normalized.any((target) => target.id == currentSnapshot.id)) {
      if (normalized.length >= maxPageTargets) normalized.removeAt(0);
      normalized.add((
        id: currentSnapshot.id,
        url: currentSnapshot.url,
        title: currentSnapshot.title,
      ));
    }
    _replacePageTargetsFromData(normalized);
  }

  /// 新建一个 page target（默认 about:blank）；上层切到它即可在新 tab 操作。
  Future<String?> createPageTarget({String url = 'about:blank'}) async {
    final cdp = _browserCdp;
    final normalizedUrl = _validatedPageUrlInput(url);
    if (cdp == null || normalizedUrl == null) return null;
    try {
      final r = await cdp.send(
        'Target.createTarget',
        params: <String, Object?>{'url': normalizedUrl},
      );
      return _validatedPageTargetId(r['targetId']);
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '创建页面目标', error, stack);
      return null;
    }
  }

  /// 关闭指定 page target。若正在被使用，先切到下一个再关。
  Future<void> closePageTarget(String targetId) async {
    final cdp = _browserCdp;
    final normalizedTargetId = _validatedPageTargetId(targetId);
    if (cdp == null || normalizedTargetId == null) return;
    if (_currentTargetId == normalizedTargetId && _pageTargets.length > 1) {
      // 选下一个不同 id 的 target 切过去。
      final next = _pageTargets.firstWhere(
        (t) => t.id != normalizedTargetId,
        orElse: () => const CdpPageTargetSnapshot(id: '', url: '', title: ''),
      );
      if (next.id.isNotEmpty) await switchToPageTarget(next.id);
    }
    try {
      await cdp.send(
        'Target.closeTarget',
        params: <String, Object?>{'targetId': normalizedTargetId},
      );
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        '关闭页面目标：$normalizedTargetId',
        error,
        stack,
      );
    }
  }

  void _onCdpEvent(CdpEvent ev) {
    if (_disposed || _stopped) return;
    // 先广播给外部订阅者，再走内置分发。
    if (!_rawCdpEventBus.isClosed) {
      _rawCdpEventBus.add(ev);
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
        _recorderGeneration += 1;
        _recording = false;
        _recorderScriptIdentifier = null;
        _memorySamplingGeneration += 1;
        _samplingProfileRunning = false;
        _requestTraceStop();
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
      case 'Runtime.executionContextsCleared':
        _onExecutionContextsCleared();
      case 'Debugger.scriptParsed':
        _onScriptParsed(ev.params);
      case 'Debugger.paused':
        _onDebuggerPaused(ev.params);
      case 'Debugger.resumed':
        _onDebuggerResumed();
    }
  }

  // ── Performance / Memory / Application / Security / Recorder API ─────

  bool _performanceEnabled = false;

  /// 拉取 `Performance.getMetrics`：返回每个指标 (name, value)。失败返回空。
  Future<List<(String, double)>> performanceMetrics() async {
    final cdp = _browserCdp;
    final sessionId = _pageSessionId;
    if (cdp == null || sessionId == null) return const [];
    try {
      if (!_performanceEnabled) {
        await cdp.send(
          'Performance.enable',
          sessionId: sessionId,
          timeout: _cdpLightCommandTimeout,
        );
        if (_pageSessionId != sessionId) return const [];
        _performanceEnabled = true;
      }
      final r = await cdp.send(
        'Performance.getMetrics',
        sessionId: sessionId,
        timeout: _cdpInspectTimeout,
      );
      if (_pageSessionId != sessionId) return const [];
      return normalizeWebReversePerformanceMetrics(r['metrics']);
    } catch (error, stack) {
      _performanceEnabled = false;
      silentLog('web_reverse_session_controller', '读取性能指标', error, stack);
      return const [];
    }
  }

  /// `HeapProfiler.takeHeapSnapshot` 并通过 chunk 事件聚合返回。
  /// 返回字段：(rawJson, totalBytes)；调用方写盘或解析 summary。
  Future<({String json, int bytes})?> takeHeapSnapshot() {
    final active = _heapSnapshotTask;
    if (active != null) return active;
    late final Future<({String json, int bytes})?> task;
    task = _takeHeapSnapshotOnce().whenComplete(() {
      if (identical(_heapSnapshotTask, task)) _heapSnapshotTask = null;
    });
    _heapSnapshotTask = task;
    return task;
  }

  Future<({String json, int bytes})?> _takeHeapSnapshotOnce() async {
    final cdp = _browserCdp;
    final sessionId = _pageSessionId;
    if (cdp == null ||
        sessionId == null ||
        _stopped ||
        _disposed ||
        _stopBrowserTask != null) {
      return null;
    }
    bool isCurrentSession() =>
        !_stopped &&
        !_disposed &&
        identical(_browserCdp, cdp) &&
        _pageSessionId == sessionId;
    final buffer = StringBuffer();
    final completer = Completer<void>();
    var totalBytes = 0;
    var tooLarge = false;
    StreamSubscription<CdpEvent>? sub;
    try {
      await cdp.send('HeapProfiler.enable', sessionId: sessionId);
      if (!isCurrentSession()) return null;
      sub = cdp.events.where((e) => e.sessionId == sessionId).listen((e) {
        if (e.method == 'HeapProfiler.addHeapSnapshotChunk') {
          if (tooLarge) return;
          final chunk = '${e.params['chunk'] ?? ''}';
          final chunkBytes = utf8.encode(chunk).length;
          if (chunkBytes > _maxHeapSnapshotBytes - totalBytes) {
            tooLarge = true;
            if (!completer.isCompleted) completer.complete();
            return;
          }
          totalBytes += chunkBytes;
          buffer.write(chunk);
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
        sessionId: sessionId,
        timeout: _cdpHeapSnapshotTimeout,
      );
      if (!isCurrentSession()) return null;
      // takeHeapSnapshot 同步返回时一般 chunk 已 flush 完，等一小段防边界。
      await Future.any<void>([
        completer.future,
        Future<void>.delayed(const Duration(milliseconds: 250)),
      ]);
      if (tooLarge || !isCurrentSession()) return null;
      final raw = buffer.toString();
      return (json: raw, bytes: totalBytes);
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '获取堆快照', error, stack);
      return null;
    } finally {
      await _cancelRuntimeSubscription(sub, '堆快照事件');
    }
  }

  /// 跑一次 `Tracing.start` / `Tracing.end` 并返回 trace JSON 字符串。
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
  }) {
    final active = _traceTask;
    if (active != null) {
      if (earlyStop != null) {
        unawaited(
          earlyStop.then<void>(
            (_) => _requestTraceStop(),
            onError: (Object _, StackTrace _) => _requestTraceStop(),
          ),
        );
      }
      return active;
    }
    final stopSignal = Completer<void>();
    late final Future<String?> task;
    task =
        _recordTraceOnce(
          duration: duration,
          categories: categories,
          earlyStop: earlyStop,
          lifecycleStop: stopSignal.future,
        ).whenComplete(() {
          if (identical(_traceTask, task)) {
            _traceTask = null;
            _traceStopSignal = null;
          }
        });
    _traceStopSignal = stopSignal;
    _traceTask = task;
    return task;
  }

  Future<String?> _recordTraceOnce({
    required Duration duration,
    required List<String> categories,
    required Future<void>? earlyStop,
    required Future<void> lifecycleStop,
  }) async {
    final cdp = _browserCdp;
    // tracing 使用 root session，但仍受当前浏览器生命周期约束。
    if (cdp == null || _stopped || _disposed || _stopBrowserTask != null) {
      return null;
    }
    final effectiveDuration = duration <= Duration.zero
        ? Duration.zero
        : duration > _maxTraceDuration
        ? _maxTraceDuration
        : duration;
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
              final mapped = compactWebReverseTraceEvent(item);
              if (mapped == null) {
                droppedEvents += 1;
                continue;
              }
              final estimatedChars = jsonEncode(mapped).length;
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
      final stopSignal = combineCancelSignals(<Future<void>?>[
        lifecycleStop,
        earlyStop,
      ])!;
      await Future.any(<Future<void>>[
        Future<void>.delayed(effectiveDuration),
        stopSignal,
      ]);
      if (!identical(_browserCdp, cdp) || cdp.isClosed) return null;
      await cdp.send('Tracing.end');
      await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {},
      );
      return jsonEncode(<String, Object?>{
        'traceEvents': events,
        'metadata': <String, Object?>{
          'source': 'OpenHand WebReverseExpert',
          'duration_ms': effectiveDuration.inMilliseconds,
          'events_seen': seenEvents,
          'events_recorded': events.length,
          'events_dropped': droppedEvents,
          'events_capped': traceCapped,
          'event_count_cap': _maxTraceEvents,
          'payload_chars_cap': _maxTracePayloadChars,
        },
      });
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '记录性能跟踪', error, stack);
      return null;
    } finally {
      await _cancelRuntimeSubscription(sub, '性能跟踪事件');
    }
  }

  void _requestTraceStop() {
    final signal = _traceStopSignal;
    if (signal != null && !signal.isCompleted) signal.complete();
  }

  Future<void> _stopTraceRecording() async {
    final active = _traceTask;
    if (active == null) return;
    _requestTraceStop();
    await runAsyncCleanupBounded(
      () async {
        await active;
      },
      timeout: _browserCleanupTimeout,
      onError: (error, stack) =>
          silentLog('web_reverse_session_controller', '停止性能跟踪', error, stack),
    );
  }

  // ── Application: Cookies / Storage ───────────────────────────────────

  Future<List<Map<String, Object?>>> listCookies({bool all = true}) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return const [];
    try {
      final r = await cdp.send(
        all ? 'Network.getAllCookies' : 'Network.getCookies',
        sessionId: _pageSessionId,
      );
      return compactWebReverseCookies(r['cookies']);
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        '读取浏览器 Cookie 列表',
        error,
        stack,
      );
      return const [];
    }
  }

  Future<List<({String key, String value})>> listDomStorage({
    required String origin,
    required bool isLocalStorage,
  }) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return const [];
    final normalizedOrigin = _validatedCommandText(
      origin,
      maxPageTargetUrlChars,
    );
    if (normalizedOrigin == null) return const [];
    try {
      await cdp.send('DOMStorage.enable', sessionId: _pageSessionId);
      final r = await cdp.send(
        'DOMStorage.getDOMStorageItems',
        params: <String, Object?>{
          'storageId': <String, Object?>{
            'securityOrigin': normalizedOrigin,
            'isLocalStorage': isLocalStorage,
          },
        },
        sessionId: _pageSessionId,
      );
      return normalizeWebReverseDomStorageEntries(r['entries']);
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '读取页面存储', error, stack);
      return const [];
    }
  }

  /// `Network.deleteCookies` 删一条 cookie。失败返回 false。
  Future<bool> deleteCookie({
    required String name,
    String? domain,
    String? path,
    Map<String, Object?>? partitionKey,
  }) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    final normalizedName = _validatedCommandText(
      name,
      maxCookieNameChars,
      trim: false,
    );
    final normalizedDomain = domain == null
        ? null
        : _validatedCommandText(
            domain,
            maxCookieDomainChars,
            allowEmpty: true,
            trim: false,
          );
    final normalizedPath = path == null
        ? null
        : _validatedCommandText(
            path,
            maxCookiePathChars,
            allowEmpty: true,
            trim: false,
          );
    final normalizedPartitionKey = _normalizeCookiePartitionKey(partitionKey);
    if (normalizedName == null ||
        (domain != null && normalizedDomain == null) ||
        (path != null && normalizedPath == null) ||
        (partitionKey != null && normalizedPartitionKey == null)) {
      return false;
    }
    try {
      await cdp.send(
        'Network.deleteCookies',
        params: <String, Object?>{
          'name': normalizedName,
          if (normalizedDomain != null && normalizedDomain.isNotEmpty)
            'domain': normalizedDomain,
          if (normalizedPath != null && normalizedPath.isNotEmpty)
            'path': normalizedPath,
          if (normalizedPartitionKey != null)
            'partitionKey': normalizedPartitionKey,
        },
        sessionId: _pageSessionId,
      );
      return true;
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        '删除浏览器 Cookie：$name',
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
    String? url,
    String? domain,
    String? path,
    Map<String, Object?>? partitionKey,
    bool? secure,
    bool? httpOnly,
    String? sameSite,
    num? expires,
  }) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    final normalizedName = _validatedCommandText(
      name,
      maxCookieNameChars,
      trim: false,
    );
    final normalizedValue = _validatedCommandText(
      value,
      maxCookieValueChars,
      allowEmpty: true,
      trim: false,
    );
    final normalizedUrl = url == null ? null : _validatedPageUrlInput(url);
    final normalizedDomain = domain == null
        ? null
        : _validatedCommandText(
            domain,
            maxCookieDomainChars,
            allowEmpty: true,
            trim: false,
          );
    final normalizedPath = path == null
        ? null
        : _validatedCommandText(
            path,
            maxCookiePathChars,
            allowEmpty: true,
            trim: false,
          );
    final normalizedPartitionKey = _normalizeCookiePartitionKey(partitionKey);
    final normalizedSameSite = sameSite?.trim();
    if (normalizedName == null ||
        normalizedValue == null ||
        (url != null && normalizedUrl == null) ||
        (domain != null && normalizedDomain == null) ||
        (path != null && normalizedPath == null) ||
        (partitionKey != null && normalizedPartitionKey == null) ||
        (normalizedSameSite != null &&
            normalizedSameSite.isNotEmpty &&
            !const <String>{
              'Strict',
              'Lax',
              'None',
            }.contains(normalizedSameSite)) ||
        (expires != null && !expires.isFinite)) {
      return false;
    }
    var effectiveUrl = normalizedUrl;
    if (effectiveUrl == null &&
        (normalizedDomain == null || normalizedDomain.isEmpty)) {
      effectiveUrl = await currentUrl();
      if (effectiveUrl == null) return false;
    }
    try {
      await cdp.send(
        'Network.setCookie',
        params: <String, Object?>{
          'name': normalizedName,
          'value': normalizedValue,
          if (effectiveUrl != null) 'url': effectiveUrl,
          if (normalizedDomain != null && normalizedDomain.isNotEmpty)
            'domain': normalizedDomain,
          if (normalizedPath != null && normalizedPath.isNotEmpty)
            'path': normalizedPath,
          if (normalizedPartitionKey != null)
            'partitionKey': normalizedPartitionKey,
          if (secure != null) 'secure': secure,
          if (httpOnly != null) 'httpOnly': httpOnly,
          if (normalizedSameSite != null && normalizedSameSite.isNotEmpty)
            'sameSite': normalizedSameSite,
          if (expires != null) 'expires': expires,
        },
        sessionId: _pageSessionId,
      );
      return true;
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        '写入浏览器 Cookie：$name',
        error,
        stack,
      );
      return false;
    }
  }

  Map<String, Object?>? _normalizeCookiePartitionKey(
    Map<String, Object?>? raw,
  ) {
    if (raw == null) return null;
    final topLevelSite = raw['topLevelSite'];
    if (topLevelSite is! String) return null;
    final normalizedSite = _validatedPageUrlInput(topLevelSite);
    if (normalizedSite == null) return null;
    return <String, Object?>{
      'topLevelSite': normalizedSite,
      'hasCrossSiteAncestor': raw['hasCrossSiteAncestor'] == true,
    };
  }

  Future<bool> clearAllCookies() async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    try {
      await cdp.send('Network.clearBrowserCookies', sessionId: _pageSessionId);
      return true;
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '清空浏览器 Cookie', error, stack);
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
    final normalizedOrigin = _validatedCommandText(
      origin,
      maxPageTargetUrlChars,
    );
    final normalizedKey = _validatedCommandText(
      key,
      maxStorageKeyChars,
      allowEmpty: true,
      trim: false,
    );
    final normalizedValue = _validatedCommandText(
      value,
      maxStorageValueChars,
      allowEmpty: true,
      trim: false,
    );
    if (normalizedOrigin == null ||
        normalizedKey == null ||
        normalizedValue == null) {
      return false;
    }
    try {
      await cdp.send('DOMStorage.enable', sessionId: _pageSessionId);
      await cdp.send(
        'DOMStorage.setDOMStorageItem',
        params: <String, Object?>{
          'storageId': <String, Object?>{
            'securityOrigin': normalizedOrigin,
            'isLocalStorage': isLocalStorage,
          },
          'key': normalizedKey,
          'value': normalizedValue,
        },
        sessionId: _pageSessionId,
      );
      return true;
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '写入页面存储项', error, stack);
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
    final normalizedOrigin = _validatedCommandText(
      origin,
      maxPageTargetUrlChars,
    );
    final normalizedKey = _validatedCommandText(
      key,
      maxStorageKeyChars,
      allowEmpty: true,
      trim: false,
    );
    if (normalizedOrigin == null || normalizedKey == null) return false;
    try {
      await cdp.send('DOMStorage.enable', sessionId: _pageSessionId);
      await cdp.send(
        'DOMStorage.removeDOMStorageItem',
        params: <String, Object?>{
          'storageId': <String, Object?>{
            'securityOrigin': normalizedOrigin,
            'isLocalStorage': isLocalStorage,
          },
          'key': normalizedKey,
        },
        sessionId: _pageSessionId,
      );
      return true;
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '删除页面存储项', error, stack);
      return false;
    }
  }

  Future<bool> clearDomStorage({
    required String origin,
    required bool isLocalStorage,
  }) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    final normalizedOrigin = _validatedCommandText(
      origin,
      maxPageTargetUrlChars,
    );
    if (normalizedOrigin == null) return false;
    try {
      await cdp.send('DOMStorage.enable', sessionId: _pageSessionId);
      await cdp.send(
        'DOMStorage.clear',
        params: <String, Object?>{
          'storageId': <String, Object?>{
            'securityOrigin': normalizedOrigin,
            'isLocalStorage': isLocalStorage,
          },
        },
        sessionId: _pageSessionId,
      );
      return true;
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '清空页面存储', error, stack);
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
      if (value is! String) return null;
      return _validatedCommandText(value, maxPageTargetUrlChars);
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '读取当前页面源地址', error, stack);
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
      return normalizeWebReverseIndexedDbNames(r['databaseNames']);
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '读取浏览器索引数据库列表', error, stack);
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
    final normalizedDbName = _validatedIndexedDbIdentity(dbName);
    if (normalizedDbName == null) return null;
    try {
      final origin = await currentOrigin();
      if (origin == null) return null;
      final r = await cdp.send(
        'IndexedDB.requestDatabase',
        params: <String, Object?>{
          'securityOrigin': origin,
          'databaseName': normalizedDbName,
        },
        sessionId: _pageSessionId,
      );
      final db = r['databaseWithObjectStores'];
      if (db is! Map) return null;
      final version = nonNegativeIntFromValue(db['version'], fallback: 0);
      final stores = normalizeWebReverseIndexedDbStoreNames(db['objectStores']);
      return (name: normalizedDbName, version: version, stores: stores);
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        '读取浏览器索引数据库结构：$dbName',
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
    int pageSize = defaultIndexedDbPageSize,
  }) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return null;
    final normalizedDbName = _validatedIndexedDbIdentity(dbName);
    final normalizedStoreName = _validatedIndexedDbIdentity(storeName);
    if (normalizedDbName == null || normalizedStoreName == null) return null;
    final normalizedSkipCount = skipCount.clamp(0, 0x7fffffff);
    final normalizedPageSize = pageSize.clamp(1, maxIndexedDbPageSize);
    try {
      final origin = await currentOrigin();
      if (origin == null) return null;
      final r = await cdp.send(
        'IndexedDB.requestData',
        params: <String, Object?>{
          'securityOrigin': origin,
          'databaseName': normalizedDbName,
          'objectStoreName': normalizedStoreName,
          'indexName': '',
          'skipCount': normalizedSkipCount,
          'pageSize': normalizedPageSize,
        },
        sessionId: _pageSessionId,
        timeout: _cdpIoTimeout,
      );
      final hasMore = r['hasMore'] == true;
      final entries = compactWebReverseIndexedDbEntries(
        r['objectStoreDataEntries'],
        maxEntries: normalizedPageSize,
      );
      return (entries: entries, hasMore: hasMore);
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        '读取浏览器索引数据库存储：$dbName/$storeName',
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
    final normalizedDbName = _validatedIndexedDbIdentity(dbName);
    final normalizedStoreName = _validatedIndexedDbIdentity(storeName);
    if (normalizedDbName == null || normalizedStoreName == null) return false;
    try {
      final origin = await currentOrigin();
      if (origin == null) return false;
      await cdp.send(
        'IndexedDB.clearObjectStore',
        params: <String, Object?>{
          'securityOrigin': origin,
          'databaseName': normalizedDbName,
          'objectStoreName': normalizedStoreName,
        },
        sessionId: _pageSessionId,
        timeout: _cdpIoTimeout,
      );
      return true;
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        '清空浏览器索引数据库存储：$dbName/$storeName',
        error,
        stack,
      );
      return false;
    }
  }

  /// `IndexedDB.deleteObjectStoreEntries` —— 删除指定 key 的单条记录。
  /// CDP 协议要求 keyRange 用 `{lower, upper, lowerOpen, upperOpen}` 结构；
  /// 这里构造为 `[key, key]` 闭区间精准命中一条。
  /// 仅接受 UI 当前支持的 string / number key，拒绝任意嵌套对象。
  Future<bool> deleteIndexedDbEntry({
    required String dbName,
    required String storeName,
    required Map<String, Object?> key,
  }) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    final normalizedDbName = _validatedIndexedDbIdentity(dbName);
    final normalizedStoreName = _validatedIndexedDbIdentity(storeName);
    final normalizedKey = _normalizeIndexedDbKey(key);
    if (normalizedDbName == null ||
        normalizedStoreName == null ||
        normalizedKey == null) {
      return false;
    }
    try {
      final origin = await currentOrigin();
      if (origin == null) return false;
      await cdp.send(
        'IndexedDB.deleteObjectStoreEntries',
        params: <String, Object?>{
          'securityOrigin': origin,
          'databaseName': normalizedDbName,
          'objectStoreName': normalizedStoreName,
          'keyRange': <String, Object?>{
            'lower': normalizedKey,
            'upper': normalizedKey,
            'lowerOpen': false,
            'upperOpen': false,
          },
        },
        sessionId: _pageSessionId,
        timeout: _cdpIoTimeout,
      );
      return true;
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        '删除浏览器索引数据库记录：$dbName/$storeName',
        error,
        stack,
      );
      return false;
    }
  }

  Map<String, Object?>? _normalizeIndexedDbKey(Map<String, Object?> raw) {
    final type = raw['type'];
    if (type == 'string') {
      final value = raw['string'];
      if (value is! String || value.length > maxStorageKeyChars) return null;
      return <String, Object?>{'type': 'string', 'string': value};
    }
    if (type == 'number') {
      final value = raw['number'];
      if (value is! num || !value.isFinite) return null;
      return <String, Object?>{'type': 'number', 'number': value};
    }
    return null;
  }

  /// `IndexedDB.deleteDatabase` —— 删除整个数据库。
  Future<bool> deleteIndexedDb(String dbName) async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    final normalizedDbName = _validatedIndexedDbIdentity(dbName);
    if (normalizedDbName == null) return false;
    try {
      final origin = await currentOrigin();
      if (origin == null) return false;
      await cdp.send(
        'IndexedDB.deleteDatabase',
        params: <String, Object?>{
          'securityOrigin': origin,
          'databaseName': normalizedDbName,
        },
        sessionId: _pageSessionId,
        timeout: _cdpIoTimeout,
      );
      return true;
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        '删除浏览器索引数据库：$dbName',
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
      return normalizeWebReverseCacheStorageNames(r['caches']);
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '读取浏览器缓存列表', error, stack);
      return const [];
    }
  }

  /// 注册 / 更新 / 卸载指定 Service Worker。
  /// `register` 走 `ServiceWorker.startRegistration`（接 scopeURL）；
  /// `update` 走 `ServiceWorker.updateRegistration`；
  /// `unregister` 走 `ServiceWorker.unregister`。
  Future<bool> registerServiceWorker(String scopeURL) async {
    final cdp = _browserCdp;
    final normalizedScope = _validatedServiceWorkerScope(scopeURL);
    if (cdp == null || normalizedScope == null) return false;
    try {
      await cdp.send('ServiceWorker.enable');
      await cdp.send(
        'ServiceWorker.startRegistration',
        params: <String, Object?>{'scopeURL': normalizedScope},
      );
      return true;
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '注册服务工作线程', error, stack);
      return false;
    }
  }

  Future<bool> updateServiceWorker(String scopeURL) async {
    final cdp = _browserCdp;
    final normalizedScope = _validatedServiceWorkerScope(scopeURL);
    if (cdp == null || normalizedScope == null) return false;
    try {
      await cdp.send(
        'ServiceWorker.updateRegistration',
        params: <String, Object?>{'scopeURL': normalizedScope},
      );
      return true;
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '更新服务工作线程', error, stack);
      return false;
    }
  }

  Future<bool> unregisterServiceWorker(String scopeURL) async {
    final cdp = _browserCdp;
    final normalizedScope = _validatedServiceWorkerScope(scopeURL);
    if (cdp == null || normalizedScope == null) return false;
    try {
      await cdp.send(
        'ServiceWorker.unregister',
        params: <String, Object?>{'scopeURL': normalizedScope},
      );
      return true;
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '注销服务工作线程', error, stack);
      return false;
    }
  }

  /// `ServiceWorker.deliverPushMessage` 不暴露——这里只列已注册的 worker。
  /// 数据来自 `ServiceWorker.workerVersionUpdated` 事件累积；这里同步发一次
  /// `ServiceWorker.enable` 触发首次推送。
  Future<List<Map<String, Object?>>> listServiceWorkers() async {
    final cdp = _browserCdp;
    if (cdp == null) return const [];
    final versionsByKey = <String, Map<String, Object?>>{};
    final registrationsById = <String, Map<String, Object?>>{};
    var anonymousVersionSequence = 0;
    var remainingVersionInspections = maxServiceWorkers * 4;
    var remainingRegistrationInspections = maxServiceWorkers * 4;
    StreamSubscription<CdpEvent>? sub;
    try {
      // 首次 enable 会推送 registration / version 快照；监听窗口有固定上限，
      // 每类数据也独立限量，避免异常事件流在短时间内撑大内存。
      sub = cdp.events.listen((e) {
        if (e.method == 'ServiceWorker.workerRegistrationUpdated') {
          final registrations = e.params['registrations'];
          if (registrations is! Iterable) return;
          for (final raw in registrations) {
            if (remainingRegistrationInspections-- <= 0) break;
            if (raw is! Map) continue;
            final id = _validatedPageTargetId(raw['registrationId']);
            if (id == null) continue;
            if (raw['isDeleted'] == true) {
              registrationsById.remove(id);
              continue;
            }
            if (!registrationsById.containsKey(id) &&
                registrationsById.length >= maxServiceWorkers) {
              continue;
            }
            registrationsById[id] = <String, Object?>{
              'registrationId': id,
              'scopeURL': _capPlainWebReverseText(
                '${raw['scopeURL'] ?? ''}',
                maxPageTargetUrlChars,
              ),
            };
          }
          return;
        }
        if (e.method != 'ServiceWorker.workerVersionUpdated') return;
        final versions = e.params['versions'];
        if (versions is! Iterable) return;
        for (final raw in versions) {
          if (remainingVersionInspections-- <= 0) break;
          if (raw is! Map) continue;
          final compact = compactWebReverseServiceWorkers(<Object?>[raw]);
          if (compact.isEmpty) continue;
          final version = compact.single;
          final versionId = version['versionId'];
          final key = versionId is String && versionId.isNotEmpty
              ? versionId
              : '#anonymous-${anonymousVersionSequence++}';
          if (!versionsByKey.containsKey(key) &&
              versionsByKey.length >= maxServiceWorkers) {
            continue;
          }
          versionsByKey[key] = version;
        }
      });
      await cdp.send('ServiceWorker.enable');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      return compactWebReverseServiceWorkers(
        versionsByKey.values,
        rawRegistrations: registrationsById.values,
      );
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '读取服务工作线程列表', error, stack);
      return const [];
    } finally {
      await _cancelRuntimeSubscription(sub, '服务工作线程事件');
    }
  }

  String? _validatedServiceWorkerScope(String raw) {
    final normalized = _validatedPageUrlInput(raw);
    if (normalized == null || _tryHttpUri(normalized) == null) return null;
    return normalized;
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
      silentLog('web_reverse_session_controller', '启用安全域', error, stack);
    }
  }

  void _onSecurityStateChanged(Map<String, Object?> p) {
    _securityState = _capPlainWebReverseText('${p['securityState'] ?? ''}', 32);
    final explanations = p['explanations'];
    _securityExplanationsJson = explanations == null
        ? null
        : _capWebReverseText(
            jsonEncode(explanations),
            _maxSecurityExplanationsChars,
            '安全说明',
          );
    _safeNotify();
  }

  // ── Recorder（极简）──────────────────────────────────────────────────
  // 通过 addScriptToEvaluateOnNewDocument 注入轻量监听器，把 click / input /
  // navigate 等动作打到 console，再聚合为一份 step 列表。这是"够用版"，
  // Chrome DevTools Recorder 的可视化重放与高级断言用 webview/CEF 才能做。

  bool _recording = false;
  String? _recorderScriptIdentifier;
  Future<void>? _recorderStartTask;
  int _recorderGeneration = 0;
  int _replayGeneration = 0;
  final ListQueue<Map<String, Object?>> _recorderSteps =
      ListQueue<Map<String, Object?>>();
  int _recorderStepsChars = 0;
  List<Map<String, Object?>> get recorderSteps =>
      List<Map<String, Object?>>.unmodifiable(_recorderSteps);
  bool get isRecording => _recording;

  Future<void> startRecording() {
    final cdp = _browserCdp;
    final sessionId = _pageSessionId;
    if (cdp == null || sessionId == null || _recording) {
      return Future<void>.value();
    }
    final active = _recorderStartTask;
    if (active != null) return active;
    final generation = ++_recorderGeneration;
    late final Future<void> task;
    task = _startRecordingOnce(cdp, sessionId, generation).whenComplete(() {
      if (identical(_recorderStartTask, task)) {
        _recorderStartTask = null;
      }
    });
    _recorderStartTask = task;
    return task;
  }

  Future<void> _startRecordingOnce(
    WebReverseCdpClient cdp,
    String sessionId,
    int generation,
  ) async {
    const recorderJs = '''
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
  style.id = '__oh_recorder_style';
  style.textContent = '@keyframes __oh_rec_pulse{0%{box-shadow:0 0 0 0 rgba(255,255,255,.65)}70%{box-shadow:0 0 0 12px rgba(255,255,255,0)}100%{box-shadow:0 0 0 0 rgba(255,255,255,0)}}';
  const staleOverlay = document.getElementById('__oh_recorder_overlay');
  if (staleOverlay) staleOverlay.remove();
  const staleStyle = document.getElementById('__oh_recorder_style');
  if (staleStyle) staleStyle.remove();
  // 早期 Page.addScriptToEvaluateOnNewDocument 注入时 body 还没存在；用 MutationObserver 等。
  let attachObserver = null;
  const attach = () => {
    if (document.documentElement && !document.getElementById('__oh_recorder_style')) {
      document.documentElement.appendChild(style);
    }
    if (document.body && !document.getElementById('__oh_recorder_overlay')) {
      document.body.appendChild(overlay);
    }
    if (document.documentElement && document.body && attachObserver) {
      attachObserver.disconnect();
      attachObserver = null;
    }
  };
  attach();
  if (!document.documentElement || !document.body) {
    attachObserver = new MutationObserver(attach);
    attachObserver.observe(document, {childList:true, subtree:true});
  }
  const listenerAbort = new AbortController();
  const listenerOptions = { capture: true, signal: listenerAbort.signal };
  const MAX_SELECTOR_DEPTH = 6;
  const MAX_SELECTOR_SIBLINGS = 4096;
  const MAX_SELECTOR_ID_CHARS = 4096;
  const MAX_PENDING_INPUTS = 256;
  let _stepCount = 0;
  window.__oh_rec_inc = () => {
    _stepCount++;
    label.textContent = 'REC · ' + _stepCount;
  };
  // 计算稳定 CSS 选择器：优先 #id，其次按 tag + nth-of-type 链向上回溯到 body。
  const buildSelector = (el) => {
    if (!el || el.nodeType !== 1) return null;
    if (el.id && String(el.id).length <= MAX_SELECTOR_ID_CHARS) {
      return '#' + CSS.escape(el.id);
    }
    const parts = [];
    let node = el;
    while (node && node.nodeType === 1 && node !== document.body && parts.length < MAX_SELECTOR_DEPTH) {
      const parent = node.parentNode;
      if (!parent) break;
      let count = 0;
      let index = 0;
      let scanned = 0;
      for (const sibling of parent.children) {
        if (++scanned > MAX_SELECTOR_SIBLINGS) return null;
        if (sibling.tagName !== node.tagName) continue;
        count++;
        if (sibling === node) index = count;
      }
      if (index === 0) return null;
      const nth = count === 1 ? '' : ':nth-of-type(' + index + ')';
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
  }, listenerOptions);
  const pendingInputs = new Map();
  document.addEventListener('input', (ev) => {
    const t = ev.target;
    if (!t || !('value' in t)) return;
    // 智能去抖：连续 input 用 250ms 计时器合并；用户停手或失焦或回车提交时落帧。
    // 防止每个键击都打一条 step，让 replay 既快又稳。
    const sel = buildSelector(t);
    if (!sel) return;
    const previous = pendingInputs.get(t);
    if (previous) clearTimeout(previous.timer);
    if (!previous && pendingInputs.size >= MAX_PENDING_INPUTS) {
      const oldest = pendingInputs.values().next().value;
      if (oldest) oldest.flush();
    }
    const flush = () => {
      const pending = pendingInputs.get(t);
      if (!pending) return;
      clearTimeout(pending.timer);
      pendingInputs.delete(t);
      log({
        type: 'input',
        selector: sel,
        value: String(t.value).slice(0, 200),
        ts: Date.now(),
      });
    };
    const timer = setTimeout(flush, 250);
    pendingInputs.set(t, { timer, flush });
  }, listenerOptions);
  document.addEventListener('blur', (ev) => {
    const pending = pendingInputs.get(ev.target);
    if (pending) pending.flush();
  }, listenerOptions);
  document.addEventListener('keydown', (ev) => {
    if (ev.key !== 'Enter') return;
    const pending = pendingInputs.get(ev.target);
    if (pending) pending.flush();
  }, listenerOptions);
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
  }, listenerOptions);
  window.addEventListener('hashchange', () => log({ type: 'navigate', url: location.href, ts: Date.now() }), { signal: listenerAbort.signal });
  window.addEventListener('popstate', () => log({ type: 'navigate', url: location.href, ts: Date.now() }), { signal: listenerAbort.signal });
  log({ type: 'navigate', url: location.href, ts: Date.now() });
  // 暴露断言录制 API：用户可在 console 里手动调用插入断言步骤。
  window.__oh_assert_text = (selector, expected) => {
    log({ type: 'assertText', selector, expected: String(expected || ''), ts: Date.now() });
  };
  window.__oh_assert_visible = (selector) => {
    log({ type: 'assertVisible', selector, ts: Date.now() });
  };
  window.__oh_rec_cleanup = () => {
    listenerAbort.abort();
    if (attachObserver) attachObserver.disconnect();
    attachObserver = null;
    for (const pending of pendingInputs.values()) clearTimeout(pending.timer);
    pendingInputs.clear();
    overlay.remove();
    style.remove();
    window.__oh_recorder_installed = false;
    window.__oh_rec_inc = null;
    window.__oh_assert_text = null;
    window.__oh_assert_visible = null;
    window.__oh_rec_cleanup = null;
  };
})();
''';
    String? scriptIdentifier;
    try {
      final r = await cdp.send(
        'Page.addScriptToEvaluateOnNewDocument',
        params: <String, Object?>{'source': recorderJs},
        sessionId: sessionId,
      );
      final rawScriptIdentifier = r['identifier'];
      if (rawScriptIdentifier is! String ||
          rawScriptIdentifier.isEmpty ||
          rawScriptIdentifier.length > kWebReverseMaxRemoteObjectIdChars) {
        throw StateError('浏览器未返回有效的录制脚本标识。');
      }
      scriptIdentifier = rawScriptIdentifier;
      if (!_isRecorderStartCurrent(cdp, sessionId, generation)) {
        await _cleanupRecorderRuntime(cdp, sessionId, scriptIdentifier);
        return;
      }
      _recorderScriptIdentifier = scriptIdentifier;
      // 当前页面也立即注入一次。
      final injection = await cdp.send(
        'Runtime.evaluate',
        params: const <String, Object?>{'expression': recorderJs},
        sessionId: sessionId,
      );
      if (injection['exceptionDetails'] is Map) {
        throw StateError('页面录制器注入失败。');
      }
      if (!_isRecorderStartCurrent(cdp, sessionId, generation)) {
        if (_recorderScriptIdentifier == scriptIdentifier) {
          _recorderScriptIdentifier = null;
        }
        await _cleanupRecorderRuntime(cdp, sessionId, scriptIdentifier);
        return;
      }
      _recorderSteps.clear();
      _recorderStepsChars = 0;
      _recording = true;
      _safeNotify();
    } catch (error, stack) {
      if (_recorderScriptIdentifier == scriptIdentifier) {
        _recorderScriptIdentifier = null;
      }
      if (scriptIdentifier != null) {
        await _cleanupRecorderRuntime(cdp, sessionId, scriptIdentifier);
      }
      if (_isRecorderStartCurrent(cdp, sessionId, generation)) {
        silentLog('web_reverse_session_controller', '开始录制', error, stack);
      }
    }
  }

  Future<void> stopRecording() async {
    final starting = _recorderStartTask;
    _recorderGeneration += 1;
    final cdp = _browserCdp;
    final sessionId = _pageSessionId;
    final scriptIdentifier = _recorderScriptIdentifier;
    final shouldNotify =
        _recording || starting != null || scriptIdentifier != null;
    _recording = false;
    _recorderScriptIdentifier = null;
    if (!shouldNotify) return;
    if (cdp != null && sessionId != null) {
      await _cleanupRecorderRuntime(cdp, sessionId, scriptIdentifier);
    }
    if (starting != null) {
      await runAsyncCleanupBounded(
        () => starting,
        timeout: _browserCleanupTimeout,
        onError: (error, stack) => silentLog(
          'web_reverse_session_controller',
          '等待录制器停止启动',
          error,
          stack,
        ),
      );
    }
    _safeNotify();
  }

  bool _isRecorderStartCurrent(
    WebReverseCdpClient cdp,
    String sessionId,
    int generation,
  ) {
    return !_disposed &&
        !_stopped &&
        generation == _recorderGeneration &&
        identical(_browserCdp, cdp) &&
        _pageSessionId == sessionId;
  }

  Future<void> _cleanupRecorderRuntime(
    WebReverseCdpClient cdp,
    String sessionId,
    String? scriptIdentifier,
  ) async {
    if (scriptIdentifier != null) {
      try {
        await cdp.send(
          'Page.removeScriptToEvaluateOnNewDocument',
          params: <String, Object?>{'identifier': scriptIdentifier},
          sessionId: sessionId,
        );
      } catch (error, stack) {
        silentLog('web_reverse_session_controller', '移除录制脚本', error, stack);
      }
    }
    // 摘掉页面上的悬浮指示条；页面没卸载时 stop 后 overlay 仍可能挂着。
    try {
      await cdp.send(
        'Runtime.evaluate',
        params: const <String, Object?>{
          'expression':
              '(()=>{if(window.__oh_rec_cleanup){window.__oh_rec_cleanup();return;}const el=document.getElementById("__oh_recorder_overlay");if(el)el.remove();const style=document.getElementById("__oh_recorder_style");if(style)style.remove();window.__oh_recorder_installed=false;window.__oh_rec_inc=null;})()',
        },
        sessionId: sessionId,
      );
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '移除录制浮层', error, stack);
    }
  }

  /// 把已录制的 step 序列在浏览器里按时间间隔重放：
  /// click / input / change 转为 Runtime.evaluate 模拟，navigate 转为 Page.navigate。
  /// 返回值为 (执行步数, 失败步数)。
  Future<({int executed, int failed})> replaySteps({
    Duration interStepDelay = const Duration(milliseconds: 300),
    Duration stepTimeout = const Duration(seconds: 5),
  }) async {
    final cdp = _browserCdp;
    final sessionId = _pageSessionId;
    if (cdp == null || sessionId == null || _stopBrowserTask != null) {
      return (executed: 0, failed: 0);
    }
    final generation = ++_replayGeneration;
    bool isCurrent() =>
        !_disposed &&
        !_stopped &&
        _stopBrowserTask == null &&
        generation == _replayGeneration &&
        identical(_browserCdp, cdp) &&
        _pageSessionId == sessionId &&
        !cdp.isClosed;

    final steps = List<Map<String, Object?>>.of(
      _recorderSteps,
      growable: false,
    );
    if (steps.isEmpty) return (executed: 0, failed: 0);

    // 在执行真正交互前先等元素可见，避免 click 太快撞 DOM 还没渲染。
    // 5s 超时；轮询 100ms 一次；可见性 = 元素存在且 boundingClientRect.width|height > 0。
    Future<bool> waitForSelector(String selector) async {
      const expr = '''
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
        cdp,
        sessionId,
        '$expr(${jsonEncode(selector)}, 5000)',
        stepTimeout + const Duration(seconds: 6),
      );
      return r ?? false;
    }

    var executed = 0;
    var failed = 0;
    for (final step in steps) {
      if (!isCurrent()) break;
      final type = '${step['type'] ?? ''}';
      try {
        switch (type) {
          case 'navigate':
            final url = '${step['url'] ?? ''}';
            if (url.isNotEmpty) {
              await cdp.send(
                'Page.navigate',
                params: <String, Object?>{'url': url},
                sessionId: sessionId,
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
              cdp,
              sessionId,
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
              cdp,
              sessionId,
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
              cdp,
              sessionId,
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
              cdp,
              sessionId,
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
              cdp,
              sessionId,
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
        if (!isCurrent()) break;
        executed++;
      } catch (error, stack) {
        if (!isCurrent()) break;
        failed++;
        silentLog(
          'web_reverse_session_controller',
          '重放录制步骤：$type',
          error,
          stack,
        );
      }
      final stillActive = await delayWhileContinuing(interStepDelay, isCurrent);
      if (!stillActive) break;
    }
    return (executed: executed, failed: failed);
  }

  Future<void> _evalScript(
    WebReverseCdpClient cdp,
    String sessionId,
    String expression,
    Duration timeout,
  ) async {
    await cdp.send(
      'Runtime.evaluate',
      params: <String, Object?>{
        'expression': expression,
        'awaitPromise': true,
        'returnByValue': true,
      },
      sessionId: sessionId,
      timeout: timeout,
    );
  }

  /// 类似 [_evalScript]，但同步取 expression 求值结果（returnByValue）的 bool。
  Future<bool?> _evalBool(
    WebReverseCdpClient cdp,
    String sessionId,
    String expression,
    Duration timeout,
  ) async {
    try {
      final r = await cdp.send(
        'Runtime.evaluate',
        params: <String, Object?>{
          'expression': expression,
          'returnByValue': true,
        },
        sessionId: sessionId,
        timeout: timeout,
      );
      final v = cdpResultValue(r);
      return v is bool ? v : null;
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '求值布尔表达式', error, stack);
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
    final requestId = _validatedNetworkRequestId(p['requestId']);
    if (requestId == null) return;
    final request = p['request'] as Map?;
    if (request == null) return;
    final url = _capPlainWebReverseText(
      '${request['url'] ?? ''}',
      _maxImportedUrlChars,
    );
    final method = _capPlainWebReverseText('${request['method'] ?? 'GET'}', 32);
    final headers = _flattenHeaders(request['headers']);
    final requestPostData = request['postData'] is String
        ? _capPlainWebReverseText(
            request['postData'] as String,
            _maxNetworkRequestBodyChars,
          )
        : null;
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
        ..requestPostData = requestPostData;
      entry.redirectChain.add(
        CdpRedirectStep(
          url: _capPlainWebReverseText(
            '${redirect['url'] ?? ''}',
            _maxImportedUrlChars,
          ),
          status: optionalIntFromValue(redirect['status']),
          statusText: redirect['statusText'] is String
              ? _capPlainWebReverseText(redirect['statusText'] as String, 512)
              : null,
          responseHeaders: _flattenHeaders(redirect['headers']),
          at: DateTime.now(),
        ),
      );
      while (entry.redirectChain.length > _maxRedirectSteps) {
        entry.redirectChain.removeAt(0);
      }
    } else {
      entry =
          CdpNetworkEntry(
              requestId: requestId,
              url: url,
              method: method,
              timestamp: DateTime.now(),
              resourceType: _capPlainWebReverseText(
                '${p['type'] ?? 'Other'}',
                64,
              ),
            )
            ..requestHeaders = headers
            ..requestPostData = requestPostData;
    }
    final initiator = stringKeyedMapFromValue(p['initiator']);
    if (initiator.isNotEmpty) {
      entry.initiatorType = initiator['type'] is String
          ? _capPlainWebReverseText(initiator['type'] as String, 64)
          : null;
      entry.initiatorUrl = initiator['url'] is String
          ? _capPlainWebReverseText(
              initiator['url'] as String,
              _maxImportedUrlChars,
            )
          : null;
      entry.initiatorLineNumber = optionalIntFromValue(initiator['lineNumber']);
      entry.initiatorColumnNumber = optionalIntFromValue(
        initiator['columnNumber'],
      );
      final stack = stringKeyedMapFromValue(initiator['stack']);
      final frames = stack['callFrames'] as List?;
      if (frames != null) {
        final compactFrames = <Map<String, Object?>>[];
        for (final frame in frames) {
          if (compactFrames.length >= _maxInitiatorFrames) break;
          final compact = compactWebReverseTraceEvent(
            frame,
            maxChars: _maxInitiatorFrameChars,
            maxFields: 32,
          );
          if (compact != null) compactFrames.add(compact);
        }
        entry.initiatorStack = compactFrames;
      }
    }
    if (existing == null) {
      _networkByRequestId[requestId] = entry;
      _networkRequests.add(entry);
      _trimNetworkEntries();
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
    _notifyInspectorChanged();
  }

  void _onResponseReceived(Map<String, Object?> p) {
    final requestId = _validatedNetworkRequestId(p['requestId']);
    if (requestId == null) return;
    final response = stringKeyedMapFromValue(p['response']);
    if (response.isEmpty) return;
    final entry = _networkByRequestId[requestId];
    if (entry == null) return;
    final status = optionalIntFromValue(response['status']);
    final mime = _capPlainWebReverseText('${response['mimeType'] ?? ''}', 256);
    final headers = _flattenHeaders(response['headers']);
    entry
      ..statusCode = status
      ..statusText = response['statusText'] is String
          ? _capPlainWebReverseText(response['statusText'] as String, 512)
          : null
      ..mimeType = mime
      ..responseHeaders = headers
      ..remoteAddress = _formatRemoteAddress(response)
      ..protocol = response['protocol'] is String
          ? _capPlainWebReverseText(response['protocol'] as String, 128)
          : null
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
      for (final timingEntry in timing.entries.take(64)) {
        final value = timingEntry.value;
        if (value is num && value.isFinite) {
          snapshot[_capPlainWebReverseText('${timingEntry.key}', 64)] = value;
        }
      }
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
    _notifyInspectorChanged();
  }

  void _onLoadingFailed(Map<String, Object?> p) {
    final requestId = _validatedNetworkRequestId(p['requestId']);
    if (requestId == null) return;
    final entry = _networkByRequestId[requestId];
    if (entry == null) return;
    final err = _capPlainWebReverseText(
      '${p['errorText'] ?? 'failed'}',
      _maxConsoleTextChars,
    );
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
    _notifyInspectorChanged();
  }

  void _onLoadingFinished(Map<String, Object?> p) {
    final requestId = _validatedNetworkRequestId(p['requestId']);
    if (requestId == null) return;
    final entry = _networkByRequestId[requestId];
    if (entry == null) return;
    entry.loadingFinishedAt = DateTime.now();
    final encoded = optionalNonNegativeIntFromValue(p['encodedDataLength']);
    if (encoded != null) entry.encodedDataLength = encoded;
    _artifacts.recordHarFinished(requestId, DateTime.now());
    _notifyInspectorChanged();
  }

  void _onWebSocketCreated(Map<String, Object?> p) {
    final requestId = _validatedNetworkRequestId(p['requestId']);
    if (requestId == null) return;
    if (_networkByRequestId.containsKey(requestId)) return;
    final url = _capPlainWebReverseText(
      '${p['url'] ?? ''}',
      _maxImportedUrlChars,
    );
    final entry = CdpNetworkEntry(
      requestId: requestId,
      url: url,
      method: 'GET',
      timestamp: DateTime.now(),
      resourceType: 'WebSocket',
    );
    _networkByRequestId[requestId] = entry;
    _networkRequests.add(entry);
    _trimNetworkEntries();
    _notifyInspectorChanged();
  }

  void _onWebSocketFrame(
    Map<String, Object?> p,
    CdpWebSocketDirection direction,
  ) {
    final requestId = _validatedNetworkRequestId(p['requestId']);
    if (requestId == null) return;
    final entry = _networkByRequestId[requestId];
    if (entry == null) return;
    final response = stringKeyedMapFromValue(p['response']);
    final opcode = intFromValue(response['opcode'], fallback: 0);
    final mask = response['mask'] == true;
    var payload = '${response['payloadData'] ?? ''}';
    if (payload.length > _maxWebSocketFramePayloadChars) {
      payload = clipTextByCodeUnits(
        payload,
        _maxWebSocketFramePayloadChars,
        suffix: '…',
      );
    }
    entry.wsFrames.add(
      CdpWebSocketFrame(
        direction: direction,
        timestamp: DateTime.now(),
        opcode: opcode,
        mask: mask,
        payload: payload,
        errorMessage: direction == CdpWebSocketDirection.error
            ? _capPlainWebReverseText(
                '${p['errorMessage'] ?? ''}',
                _maxConsoleTextChars,
              )
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
          ? clipTextByCodeUnits(payload, 256, suffix: '…')
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
    final url = _capPlainWebReverseText(
      '${frame['url'] ?? ''}',
      maxPageTargetUrlChars,
    );
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
      _notifyInspectorChanged();
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
      if (_pageSessionId != sid || _currentTargetId != targetId) return;
      final title = _capPlainWebReverseText(
        value.trim(),
        maxPageTargetTitleChars,
      );
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
      silentLog('web_reverse_session_controller', '刷新页面标题', e, st);
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
    final normalized = normalizeWebReversePageTargets(<Object?>[
      t,
    ], preferredId: _currentTargetId);
    if (normalized.isEmpty) return;
    _upsertPageTarget(normalized.single);
    _safeNotify();
  }

  void _onTargetDestroyed(Map<String, Object?> p) {
    final id = _validatedPageTargetId(p['targetId']);
    if (id == null) return;
    final before = _pageTargets.length;
    _pageTargets.removeWhere((e) => e.id == id);
    if (_pageTargets.length != before) {
      _pageTargetFirstSeenOrder.remove(id);
      _targetBuffers.remove(id);
      if (id == _currentTargetId) {
        _recorderGeneration += 1;
        _recording = false;
        _recorderScriptIdentifier = null;
        _memorySamplingGeneration += 1;
        _samplingProfileRunning = false;
        if (_pageTargets.isNotEmpty) {
          unawaited(switchToPageTarget(_pageTargets.first.id));
        } else {
          _currentTargetId = null;
          _pageSessionId = null;
          _clearPendingFetchRequests();
        }
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
        _latestScreencastFrame = decodeBase64Bounded(
          data,
          maxDecodedBytes: _maxScreencastFrameBytes,
        );
        _screencastFrameSeq++;
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
        silentLog('web_reverse_session_controller', '解析页面投屏帧', error, stack);
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
              timeout: _cdpControlTimeout,
            )
            .catchError((_) => <String, Object?>{}),
      );
    }
  }

  static Map<String, String> _flattenHeaders(Object? raw) {
    if (raw is! Map) return const <String, String>{};
    final out = <String, String>{};
    var retainedChars = 0;
    for (final entry in raw.entries) {
      if (out.length >= _maxNetworkHeaderEntries) break;
      final name = _capPlainWebReverseText('${entry.key}', 256).trim();
      if (name.isEmpty) continue;
      final value = _capPlainWebReverseText(
        '${entry.value}',
        _maxImportedHeaderValueChars,
      );
      if (retainedChars + name.length + value.length >
          _maxNetworkHeadersChars) {
        break;
      }
      out[name] = value;
      retainedChars += name.length + value.length;
    }
    return out;
  }

  static Map<String, String> _flattenHeaderPairs(Object? raw) {
    if (raw is! Iterable) return const <String, String>{};
    final out = <String, String>{};
    var retainedChars = 0;
    var inspected = 0;
    for (final item in raw) {
      if (inspected++ >= _maxNetworkHeaderEntries * 4 ||
          out.length >= _maxNetworkHeaderEntries) {
        break;
      }
      if (item is! List || item.length < 2) continue;
      final name = _capPlainWebReverseText('${item[0]}', 256).trim();
      if (name.isEmpty) continue;
      final value = _capPlainWebReverseText(
        '${item[1]}',
        _maxImportedHeaderValueChars,
      );
      if (retainedChars + name.length + value.length >
          _maxNetworkHeadersChars) {
        break;
      }
      out[name] = value;
      retainedChars += name.length + value.length;
    }
    return out;
  }

  static String? _validatedNetworkRequestId(Object? raw) {
    if (raw is! String || raw.isEmpty || raw.length > 512) return null;
    return raw;
  }

  void _trimNetworkEntries() {
    while (_networkRequests.length > _maxNetworkEntries) {
      final removed = _networkRequests.removeAt(0);
      _networkByRequestId.remove(removed.requestId);
      _artifacts.evictHarDraft(removed.requestId);
    }
  }

  static String? _formatRemoteAddress(Map response) {
    final ip = response['remoteIPAddress'];
    final port = response['remotePort'];
    if (ip == null) return null;
    if (port == null) return _capPlainWebReverseText('$ip', kBytesPerKiB);
    return _capPlainWebReverseText('$ip:$port', kBytesPerKiB);
  }

  void _onConsoleApi(Map<String, Object?> p) {
    final type = _capPlainWebReverseText('${p['type'] ?? 'log'}', 64);
    final args = p['args'] as List? ?? const <Object?>[];
    final textBuffer = StringBuffer();
    for (final arg in args.take(256)) {
      if (arg is! Map) continue;
      final value = arg['value'];
      final part = _capPlainWebReverseText(
        value == null ? '${arg['description'] ?? ''}' : '$value',
        _maxConsoleTextChars,
      );
      if (part.isEmpty) continue;
      if (textBuffer.isNotEmpty) textBuffer.write(' ');
      final remaining = _maxConsoleTextChars - textBuffer.length;
      if (remaining <= 0) break;
      textBuffer.write(clipTextByCodeUnits(part, remaining, suffix: ''));
      if (textBuffer.length >= _maxConsoleTextChars) break;
    }
    final text = textBuffer.toString();
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
        silentLog('web_reverse_session_controller', '解析控制台录制步骤', error, stack);
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

  /// 2 秒一跳的浏览器存活探针。WebSocket 断开会优先触发重连；这里只在
  /// 连续失败达到阈值后兜底关闭 CDP，避免浏览器短暂繁忙时误判离线。
  void _startAliveWatchdog() {
    _stopAliveWatchdog();
    _aliveWatchdog = startNonOverlappingPeriodicTimer(
      const Duration(seconds: 2),
      (timer) async {
        if (_stopped || _disposed || !identical(_aliveWatchdog, timer)) {
          return;
        }
        final port = _launchResult?.cdpPort;
        if (port == null) return;
        final cdp = _browserCdp;
        if (cdp == null || cdp.isClosed) return;
        final deadline = MonotonicDeadline(
          _kAliveProbeTimeout,
          timeoutMessage: '浏览器存活探测超时。',
        );
        try {
          await withWebReverseCdpHttpClient<void>(
            connectionTimeout: _kAliveProbeTimeout,
            idleTimeout: _kAliveProbeTimeout,
            action: (client) async {
              final req = await openHttpClientRequestBounded(
                () => client.getUrl(
                  webReverseCdpHttpUri(port, webReverseCdpJsonVersionPath),
                ),
                timeout: deadline.remaining(),
                timeoutMessage: 'Web 调试版本请求打开超时。',
              );
              final res = await closeHttpClientRequestBounded(
                req,
                timeout: deadline.remaining(),
                timeoutMessage: 'Web 调试版本响应头获取超时。',
              );
              await res.drain<void>().timeout(deadline.remaining());
            },
          );
          if (!identical(_aliveWatchdog, timer) ||
              !identical(_browserCdp, cdp)) {
            return;
          }
          _aliveWatchdogFailureCount = 0;
        } catch (error, stack) {
          if (!identical(_aliveWatchdog, timer) ||
              !identical(_browserCdp, cdp)) {
            return;
          }
          _aliveWatchdogFailureCount += 1;
          silentLog('web_reverse_session_controller', '浏览器存活探测', error, stack);
          if (_aliveWatchdogFailureCount < _aliveWatchdogFailureThreshold) {
            return;
          }
          _stopAliveWatchdog();
          try {
            await cdp.close();
          } catch (closeError, closeStack) {
            silentLog(
              'web_reverse_session_controller',
              '关闭失联浏览器调试协议连接',
              closeError,
              closeStack,
            );
          }
          if (_disposed ||
              _stopped ||
              _aliveWatchdog != null ||
              !identical(_browserCdp, cdp)) {
            return;
          }
          _pauseCronTimers();
          _resetScreencastRuntimeState(resetRefCount: false);
          _errorMessage = '浏览器已断开（进程异常退出），可点击「重启浏览器」恢复。';
          _safeNotify();
        } finally {
          deadline.stop();
        }
      },
      onError: (error, stack) => silentLog(
        'web_reverse_session_controller',
        '浏览器存活定时探测',
        error,
        stack,
      ),
    );
  }

  void _stopAliveWatchdog() {
    _aliveWatchdog?.cancel();
    _aliveWatchdog = null;
    _aliveWatchdogFailureCount = 0;
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
            '重连后恢复页面投屏',
            error,
            stack,
          );
        }
      }
      _appendConsole('info', '[OpenHand] CDP 已自动重连，已恢复网络 / 控制台监听');
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '重连后重新附加页面', error, stack);
    }
  }

  void _appendConsole(String level, String text) {
    final ts = DateTime.now();
    final cappedText = _capWebReverseText(text, _maxConsoleTextChars, '控制台文本');
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
    _notifyInspectorChanged();
  }

  /// REPL 命令历史，按时间顺序追加；UI 上下箭头浏览历史。
  /// 重启 dashboard / 切会话不丢，由 dashboard 侧把它持久化到 session metadata。
  final List<String> _replHistory = <String>[];
  static const int _kReplHistoryMax = 200;
  List<String> get replHistory => List<String>.unmodifiable(_replHistory);

  void pushReplHistory(String expr) {
    final t = _capWebReverseText(
      expr.trim(),
      _maxReplHistoryExpressionChars,
      'REPL 历史表达式',
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
            'REPL 历史表达式',
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
        timeout: _cdpScriptTimeout,
      );
      final sid = r['identifier'];
      if (sid is String) _hookCdpScriptId[h.id] = sid;
    } catch (e, st) {
      silentLog('web_reverse_session_controller', '安装钩子：${h.name}', e, st);
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
        timeout: _cdpScriptTimeout,
      );
    } catch (e, st) {
      silentLog('web_reverse_session_controller', '卸载钩子', e, st);
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

  void _pauseCronTimers() {
    for (final timer in _cronTimers.values) {
      timer.cancel();
    }
    _cronTimers.clear();
  }

  void _resumeCronTimers() {
    _pauseCronTimers();
    if (!isBrowserAlive) return;
    for (final cron in _crons.where((item) => item.enabled)) {
      _scheduleCron(cron);
    }
  }

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
    _pauseCronTimers();
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
    if (!isBrowserAlive) return;
    final dur = Duration(seconds: c.intervalSeconds);
    _cronTimers[c.id] = startNonOverlappingPeriodicTimer(
      dur,
      (timer) => _executeCronOnce(c, scheduledTimer: timer),
      onError: (error, stack) => silentLog(
        'web_reverse_session_controller',
        '定时任务计时器：${c.name}',
        error,
        stack,
      ),
    );
  }

  Future<String?> _executeCronOnce(
    WebReverseCron c, {
    Timer? scheduledTimer,
  }) async {
    if (c.code.length > maxSavedScriptCodeChars) return null;
    if (!isBrowserAlive) {
      if (scheduledTimer != null &&
          identical(_cronTimers[c.id], scheduledTimer)) {
        scheduledTimer.cancel();
        _cronTimers.remove(c.id);
      }
      return null;
    }
    if (scheduledTimer != null &&
        !identical(_cronTimers[c.id], scheduledTimer)) {
      return null;
    }
    try {
      final r = await runReplExpression(c.code);
      if (!_crons.any((cron) => cron.id == c.id) ||
          (scheduledTimer != null &&
              !identical(_cronTimers[c.id], scheduledTimer))) {
        return r;
      }
      _cronLastRun[c.id] = DateTime.now();
      _safeNotify();
      return r;
    } catch (e, st) {
      silentLog('web_reverse_session_controller', '执行定时任务：${c.name}', e, st);
      return null;
    }
  }

  // ─── DOM Inspector (Elements 面板) ───────────────────────────────────
  // 直接走 CDP `DOM.*` / `CSS.*` / `DOMDebugger.*` 协议；所有方法返回
  // 经边界裁剪的 Map / List，上层 UI 自己拼树。无副作用，不持久化。
  // 失败统一返回 null / 空集合并写一行 console error 便于排查。

  bool _cssEnabled = false;

  /// `DOM.getDocument` — 拿到当前页面 root node。深度限制为 0..4，默认
  /// 2 层；UI 用 lazy expand 补深度，避免一次保留完整的大型 DOM 树。
  Future<Map<String, dynamic>?> domGetDocument({int depth = 2}) async {
    final cdp = _browserCdp;
    final sessionId = _pageSessionId;
    if (cdp == null || sessionId == null) return null;
    try {
      final safeDepth = depth.clamp(0, kWebReverseMaxDomDepth);
      final r = await cdp.send(
        'DOM.getDocument',
        params: <String, Object?>{'depth': safeDepth, 'pierce': false},
        sessionId: sessionId,
      );
      if (_pageSessionId != sessionId) return null;
      final root = r['root'];
      return compactWebReverseDomNode(root, maxDepth: safeDepth);
    } catch (e, st) {
      silentLog('web_reverse_session_controller', '读取页面文档', e, st);
      return null;
    }
  }

  /// `DOM.describeNode` — 取指定 node 的最新结构 + 一层 children。
  Future<Map<String, dynamic>?> domDescribeNode(
    int nodeId, {
    int depth = 1,
  }) async {
    final cdp = _browserCdp;
    final sessionId = _pageSessionId;
    if (cdp == null || sessionId == null || nodeId <= 0) return null;
    try {
      final safeDepth = depth.clamp(0, 2);
      final r = await cdp.send(
        'DOM.describeNode',
        params: <String, Object?>{'nodeId': nodeId, 'depth': safeDepth},
        sessionId: sessionId,
        timeout: _cdpInspectTimeout,
      );
      if (_pageSessionId != sessionId) return null;
      final node = r['node'];
      return compactWebReverseDomNode(node, maxDepth: safeDepth);
    } catch (e, st) {
      silentLog('web_reverse_session_controller', '读取页面节点', e, st);
      return null;
    }
  }

  /// `CSS.getComputedStyleForNode` — 返回 [{name,value}] 列表（已 enable
  /// CSS domain；首次调用会自动 enable）。
  Future<List<Map<String, String>>> domGetComputedStyle(int nodeId) async {
    final cdp = _browserCdp;
    final sessionId = _pageSessionId;
    if (cdp == null || sessionId == null || nodeId <= 0) return const [];
    try {
      if (!_cssEnabled) {
        await cdp.send(
          'CSS.enable',
          sessionId: sessionId,
          timeout: _cdpControlTimeout,
        );
        if (_pageSessionId != sessionId) return const [];
        _cssEnabled = true;
      }
      final r = await cdp.send(
        'CSS.getComputedStyleForNode',
        params: <String, Object?>{'nodeId': nodeId},
        sessionId: sessionId,
        timeout: _cdpInspectTimeout,
      );
      if (_pageSessionId != sessionId) return const [];
      return compactWebReverseComputedStyles(r['computedStyle']);
    } catch (e, st) {
      _cssEnabled = false;
      silentLog('web_reverse_session_controller', '读取页面节点计算样式', e, st);
      return const [];
    }
  }

  /// `DOMDebugger.getEventListeners` 需要 objectId，先 `DOM.resolveNode`
  /// 把 nodeId 转成 Runtime objectId。返回 [{type,useCapture,passive,
  /// once,scriptId,lineNumber,columnNumber,handler:{description}}] 列表。
  Future<List<Map<String, dynamic>>> domGetEventListeners(int nodeId) async {
    final cdp = _browserCdp;
    final sessionId = _pageSessionId;
    if (cdp == null || sessionId == null || nodeId <= 0) return const [];
    String? objectId;
    try {
      final resolved = await cdp.send(
        'DOM.resolveNode',
        params: <String, Object?>{'nodeId': nodeId},
        sessionId: sessionId,
        timeout: _cdpScriptTimeout,
      );
      if (_pageSessionId != sessionId) return const [];
      final obj = resolved['object'];
      if (obj is! Map) return const [];
      final rawObjectId = obj['objectId'];
      if (rawObjectId is! String ||
          rawObjectId.isEmpty ||
          rawObjectId.length > kWebReverseMaxRemoteObjectIdChars) {
        return const [];
      }
      objectId = rawObjectId;
      final r = await cdp.send(
        'DOMDebugger.getEventListeners',
        params: <String, Object?>{'objectId': objectId, 'depth': 1},
        sessionId: sessionId,
        timeout: _cdpInspectTimeout,
      );
      if (_pageSessionId != sessionId) return const [];
      return compactWebReverseDomEventListeners(r['listeners']);
    } catch (e, st) {
      silentLog('web_reverse_session_controller', '读取页面节点事件监听器', e, st);
      return const [];
    } finally {
      await _releaseRuntimeObject(cdp, sessionId, objectId, '释放页面节点监听器对象');
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
    final sessionId = _pageSessionId;
    if (cdp == null || sessionId == null || nodeId <= 0) return null;
    String? objectId;
    try {
      final resolved = await cdp.send(
        'DOM.resolveNode',
        params: <String, Object?>{'nodeId': nodeId},
        sessionId: sessionId,
        timeout: _cdpScriptTimeout,
      );
      final obj = resolved['object'];
      if (obj is! Map) return null;
      final rawObjectId = obj['objectId'];
      if (rawObjectId is! String ||
          rawObjectId.isEmpty ||
          rawObjectId.length > kWebReverseMaxRemoteObjectIdChars) {
        return null;
      }
      objectId = rawObjectId;
      final r = await cdp.send(
        'Runtime.callFunctionOn',
        params: <String, Object?>{
          'objectId': objectId,
          'functionDeclaration': fnBody,
          'returnByValue': true,
        },
        sessionId: sessionId,
        timeout: _cdpInspectTimeout,
      );
      final result = r['result'];
      if (result is Map && result['value'] is String) {
        final path = result['value'] as String;
        if (path.isEmpty) return null;
        return clipTextByCodeUnits(path, _maxDomPathChars, suffix: '');
      }
      return null;
    } catch (e, st) {
      silentLog('web_reverse_session_controller', '计算页面节点路径', e, st);
      return null;
    } finally {
      await _releaseRuntimeObject(cdp, sessionId, objectId, '释放页面节点路径对象');
    }
  }

  Future<void> _releaseRuntimeObject(
    WebReverseCdpClient cdp,
    String sessionId,
    String? objectId,
    String logAction,
  ) async {
    if (objectId == null) return;
    try {
      await cdp.send(
        'Runtime.releaseObject',
        params: <String, Object?>{'objectId': objectId},
        sessionId: sessionId,
        timeout: _cdpControlTimeout,
      );
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', logAction, error, stack);
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
        timeout: _cdpControlTimeout,
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
        timeout: _cdpLightCommandTimeout,
      );
    } catch (e, st) {
      silentLog('web_reverse_session_controller', '高亮页面节点', e, st);
    }
  }

  Future<void> domHideHighlight() async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return;
    try {
      await cdp.send(
        'Overlay.hideHighlight',
        sessionId: _pageSessionId,
        timeout: _cdpControlTimeout,
      );
    } catch (e, st) {
      silentLog('web_reverse_session_controller', '隐藏页面节点高亮', e, st);
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
        timeout: _cdpLightCommandTimeout,
      );
    } catch (e, st) {
      silentLog('web_reverse_session_controller', '滚动到页面节点', e, st);
    }
  }

  /// Console REPL：把表达式喂给 page 的 Runtime.evaluate；
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
          timeout: _cdpDebuggerTimeout,
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
          timeout: _cdpDebuggerTimeout,
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
              '格式化控制台求值结果预览',
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
        preview = clipTextByCodeUnits(
          preview,
          _maxReplPreviewChars,
          suffix: '\n…（已截断）',
        );
      }
      _appendConsole('repl-result', preview);
      return preview;
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '运行控制台表达式', error, stack);
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
        trimmedMethod.length > maxRawCdpMethodChars ||
        !_rawCdpMethodPattern.hasMatch(trimmedMethod)) {
      return <String, Object?>{'error': 'CDP 方法名无效。'};
    }
    Map<String, Object?>? params;
    final rawParamsJson = paramsJson?.trim();
    if (rawParamsJson != null && rawParamsJson.isNotEmpty) {
      if (rawParamsJson.length > _maxRawCdpParamsJsonChars) {
        return <String, Object?>{
          'error':
              '参数 JSON 过大：${rawParamsJson.length} 个字符，上限为 $_maxRawCdpParamsJsonChars。',
        };
      }
      try {
        final decoded = jsonDecode(rawParamsJson);
        if (decoded is! Map) {
          return <String, Object?>{'error': '参数 JSON 必须是对象。'};
        }
        params = stringKeyedMapFromValue(decoded);
      } catch (e) {
        return <String, Object?>{'error': '参数 JSON 无效：$e'};
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
      if (useSession) _syncRawCdpDomainState(trimmedMethod);
      return result;
    } catch (error) {
      return <String, Object?>{'error': '$error'};
    }
  }

  /// 在页面上下文里求值一段 JS。
  ///
  /// 收敛全模块 `Runtime.evaluate` 的参数拼装：可选开关只在开启时写进 params，
  /// 其余保持 CDP 默认，避免各面板各自拼一份易漂移的 JSON。
  /// [timeout] 是本地传输等待上限；[evaluationTimeout] 是交给 V8 的页内执行
  /// 上限，用于给用户可编辑的表达式兜底，避免死循环把渲染进程挂住。
  Future<Map<String, Object?>?> evaluateJavaScript(
    String expression, {
    bool returnByValue = true,
    bool awaitPromise = false,
    bool userGesture = false,
    bool silent = false,
    bool allowUnsafeEvalBlockedByCsp = false,
    Duration? evaluationTimeout,
    Duration timeout = const Duration(seconds: 30),
  }) {
    return sendRawCdp(
      method: kCdpRuntimeEvaluate,
      paramsJson: jsonEncode(<String, Object?>{
        'expression': expression,
        'returnByValue': returnByValue,
        if (awaitPromise) 'awaitPromise': true,
        if (userGesture) 'userGesture': true,
        if (silent) 'silent': true,
        if (allowUnsafeEvalBlockedByCsp) 'allowUnsafeEvalBlockedByCSP': true,
        if (evaluationTimeout != null)
          'timeout': evaluationTimeout.inMilliseconds,
      }),
      timeout: timeout,
    );
  }

  /// 注入初始化脚本：登记到后续 document，并立刻在当前 document 执行一次，
  /// 使刷新 / SPA 导航后仍然生效，同时接管已经加载完的页面。
  ///
  /// 返回 CDP 分配的 script identifier（供后续卸载），失败时抛出异常。
  Future<String> _installDocumentInitScript(
    WebReverseCdpClient cdp,
    String source, {
    required String? sessionId,
    Duration timeout = _kInitScriptInstallTimeout,
  }) async {
    String? identifier;
    try {
      final registered = await cdp.send(
        kCdpPageAddScriptToEvaluateOnNewDocument,
        params: <String, Object?>{'source': source},
        sessionId: sessionId,
        timeout: timeout,
      );
      final rawIdentifier = registered['identifier'];
      if (rawIdentifier is! String ||
          rawIdentifier.isEmpty ||
          rawIdentifier.length > kWebReverseMaxRemoteObjectIdChars) {
        throw StateError('浏览器未返回有效的页面初始化脚本标识。');
      }
      identifier = rawIdentifier;
      final evaluated = await cdp.send(
        kCdpRuntimeEvaluate,
        params: <String, Object?>{'expression': source},
        sessionId: sessionId,
        timeout: timeout,
      );
      if (evaluated['exceptionDetails'] is Map) {
        throw StateError('页面初始化脚本执行失败。');
      }
      return rawIdentifier;
    } catch (error, stack) {
      if (identifier != null) {
        try {
          await cdp.send(
            'Page.removeScriptToEvaluateOnNewDocument',
            params: <String, Object?>{'identifier': identifier},
            sessionId: sessionId,
            timeout: timeout,
          );
        } catch (cleanupError, cleanupStack) {
          silentLog(
            'web_reverse_session_controller',
            '回滚页面初始化脚本',
            cleanupError,
            cleanupStack,
          );
        }
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  void _syncRawCdpDomainState(String method) {
    switch (method) {
      case 'CSS.enable':
        _cssEnabled = true;
      case 'CSS.disable':
        _cssEnabled = false;
      case 'Performance.enable':
        _performanceEnabled = true;
      case 'Performance.disable':
        _performanceEnabled = false;
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
      case 'Network.emulateNetworkConditions':
        final next = WebReverseNetworkConditions.fromCdpParams(params);
        if (_networkConditions != next) {
          _networkConditions = next;
          changed = true;
        }
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
  Future<void> stopBrowser() {
    if (_stopped) return Future<void>.value();
    final active = _stopBrowserTask;
    if (active != null) return active;
    late final Future<void> task;
    task = _stopBrowserOnce().whenComplete(() {
      if (identical(_stopBrowserTask, task)) {
        _stopBrowserTask = null;
        _safeNotify();
      }
    });
    _stopBrowserTask = task;
    return task;
  }

  Future<void> _stopBrowserOnce() async {
    _stopAliveWatchdog();
    _pauseCronTimers();
    await stopRecording();
    await stopMemorySampling();
    await _stopTraceRecording();
    // 关 screencast → 关 CDP → kill 进程；artifacts / dock 不动。
    if (_screencastActive) {
      try {
        if (_browserCdp != null && _pageSessionId != null) {
          await _browserCdp!
              .send('Page.stopScreencast', sessionId: _pageSessionId)
              .timeout(const Duration(milliseconds: 500));
        }
      } catch (error, stack) {
        silentLog('web_reverse_session_controller', '停止浏览器页面投屏', error, stack);
      }
    }
    _resetScreencastRuntimeState(resetRefCount: false);
    _clearPendingFetchRequests(resetEnabled: true);
    await _cancelRuntimeSubscription(_pageEventsSub, '停止页面事件订阅');
    _pageEventsSub = null;
    _pageSessionId = null;
    await _closeAuxiliaryServices();
    try {
      await _pageCdp?.close();
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '关闭页面调试协议连接', error, stack);
    }
    _pageCdp = null;
    _sourceMapCache.clear();
    try {
      await _browserCdp?.close();
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '关闭浏览器调试协议连接', error, stack);
    }
    _browserCdp = null;
    final launchResult = _launchResult;
    _launchResult = null;
    if (launchResult != null) {
      await _terminateBrowserLaunch(launchResult, '停止浏览器');
    }
    _errorMessage = null;
    _safeNotify();
  }

  /// 把外部浏览器拉起来：要么是用户主动点了「停止调试」想再连一次，
  /// 要么是浏览器异常退出 / CDP 重连耗尽后用户点了「重启浏览器」。
  /// 复用 [start] 的全部启动逻辑，只是重置 stopped 标记。
  Future<void> restartBrowser() {
    if (_disposed) {
      return Future<void>.error(StateError('Web 逆向会话已释放。'));
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
    // 不快照/回写 _screencastRefCount：stopBrowser 已刻意保留这份活计数
    // （resetRefCount: false），重启期间订阅者的 acquire/release 会实时增减它。
    // 此前先快照再无条件写回，会把这些并发增减整段丢弃（lost update）。宽高质量
    // 属配置量、不受并发增减影响，快照仅用于重启后按上次参数恢复投屏。
    final restoreScreencastWidth = _screencastWidth;
    final restoreScreencastHeight = _screencastHeight;
    final restoreScreencastQuality = _screencastQuality;
    try {
      // 先确保旧资源完全释放。
      await stopBrowser();
      _stopped = false;
      _started = false;
      _screencastWidth = restoreScreencastWidth;
      _screencastHeight = restoreScreencastHeight;
      _screencastQuality = restoreScreencastQuality;
      _errorMessage = null;
      _safeNotify();
      await start();
      if (_screencastRefCount > 0) {
        await _startScreencastForCurrentSubscribers(
          maxWidth: restoreScreencastWidth,
          maxHeight: restoreScreencastHeight,
          quality: restoreScreencastQuality,
        );
      }
    } catch (error) {
      _errorMessage = userFailureMessage(
        error,
        fallback: '浏览器重启失败，请检查浏览器配置后重试。',
      );
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
    final stoppingBrowser = _stopBrowserTask;
    if (stoppingBrowser != null) await stoppingBrowser;
    _stopAliveWatchdog();
    _pauseCronTimers();
    await stopRecording();
    await stopMemorySampling();
    await _stopTraceRecording();
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
        silentLog('web_reverse_session_controller', '安全停止页面投屏', error, stack);
      }
    }
    _resetScreencastRuntimeState(resetRefCount: true);
    _clearPendingFetchRequests(resetEnabled: true);
    await _cancelRuntimeSubscription(_pageEventsSub, '关闭页面事件订阅');
    await _closeAuxiliaryServices();
    _pageEventsSub = null;
    _pageSessionId = null;
    try {
      await _pageCdp?.close();
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '安全关闭页面调试协议连接', error, stack);
    }
    _pageCdp = null;
    _sourceMapCache.clear();
    try {
      await _browserCdp?.close();
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        '安全关闭浏览器调试协议连接',
        error,
        stack,
      );
    }
    _browserCdp = null;
    final launchResult = _launchResult;
    _launchResult = null;
    if (launchResult != null) {
      await _terminateBrowserLaunch(launchResult, '关闭浏览器');
    }
    // 收尾产物：先导 HAR（用 in-memory drafts），再关 artifacts。
    try {
      _lastHarPath = await _artifacts.exportHar();
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '导出网络归档', error, stack);
    }
    await _artifacts.close();
  }

  Future<void> _terminateBrowserLaunch(
    WebReverseLaunchResult launchResult,
    String where,
  ) async {
    await runAsyncCleanupBounded(
      () => terminateTrackedProcessTree(
        launchResult.process,
        gracefulTimeout: _browserStopGrace,
      ),
      timeout: _browserCleanupTimeout,
      onError: (error, stack) => silentLog(
        'web_reverse_session_controller',
        '终止浏览器进程：$where',
        error,
        stack,
      ),
    );
    await launchResult.closeOutputStreams();
  }

  Future<void> _closeAuxiliaryServices() async {
    try {
      await stopMitmproxyBridge();
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '关闭流量代理桥接', error, stack);
    }
    try {
      await stopHarReplayServer();
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '关闭网络归档重放服务', error, stack);
    }
  }

  /// 清空 dashboard 缓冲（用户在 dashboard 点"清空"按钮时调用）。
  void clearBuffers() {
    _networkRequests.clear();
    _networkByRequestId.clear();
    _consoleMessages.clear();
    _notifyInspectorChanged();
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
      silentLog('web_reverse_session_controller', '设置浏览器缓存禁用状态', error, stack);
      _safeNotify();
      return false;
    }
    _safeNotify();
    return true;
  }

  /// 安装一个轻量 FPS 计数器到 page：基于 requestAnimationFrame 的滚动计数。
  /// 之后通过 [readFps] 拉取最近 1 秒的 FPS 值。
  bool _fpsCounterInstalled = false;

  Future<bool> installFpsCounter() async {
    final cdp = _browserCdp;
    final sessionId = _pageSessionId;
    if (cdp == null || sessionId == null) return false;
    if (_fpsCounterInstalled) return true;
    const js = '''
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
      await _installDocumentInitScript(cdp, js, sessionId: sessionId);
      if (_pageSessionId != sessionId) return false;
      _fpsCounterInstalled = true;
      return true;
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '安装帧率计数器', error, stack);
      return false;
    }
  }

  /// 安装 Long Task 观测：通过 PerformanceObserver 监听 entryType='longtask'
  /// 的事件并塞进 window.__oh_long_tasks（环形缓冲，上限 200）。
  /// 之后 [readLongTasks] 拉取并清空。
  bool _longTaskObserverInstalled = false;

  Future<bool> installLongTaskObserver() async {
    final cdp = _browserCdp;
    final sessionId = _pageSessionId;
    if (cdp == null || sessionId == null) return false;
    if (_longTaskObserverInstalled) return true;
    const js = '''
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
          startTime: entry.startTime,
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
      await _installDocumentInitScript(cdp, js, sessionId: sessionId);
      if (_pageSessionId != sessionId) return false;
      _longTaskObserverInstalled = true;
      return true;
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '安装长任务观察器', error, stack);
      return false;
    }
  }

  /// 拉取 long task 列表并 drain。failure 时返回空列表。
  Future<List<Map<String, Object?>>> readLongTasks() async {
    final cdp = _browserCdp;
    final sessionId = _pageSessionId;
    if (cdp == null || sessionId == null) return const [];
    try {
      final r = await cdp.send(
        'Runtime.evaluate',
        params: const <String, Object?>{
          'expression':
              '(()=>{const a=window.__oh_long_tasks||[];window.__oh_long_tasks=[];return JSON.stringify(a);})()',
          'returnByValue': true,
        },
        sessionId: sessionId,
        timeout: _cdpScriptTimeout,
      );
      if (_pageSessionId != sessionId) return const [];
      final raw = cdpStringResultValue(r);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return compactWebReverseLongTasks(decoded);
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '读取长任务', error, stack);
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
    final sessionId = _pageSessionId;
    if (cdp == null || sessionId == null) return false;
    if (_rtcInstalled) return true;
    const js = '''
(() => {
  if (window.__oh_rtc_installed) return;
  window.__oh_rtc_installed = true;
  const sanitize = (value, depth = 0, seen = new WeakSet()) => {
    if (value == null || typeof value === 'boolean') return value;
    if (typeof value === 'number') return Number.isFinite(value) ? value : null;
    if (typeof value === 'string') return value.slice(0, 131072);
    if (typeof value !== 'object') return String(value).slice(0, 4096);
    if (depth >= 4) return '[Max depth]';
    if (seen.has(value)) return '[Circular]';
    seen.add(value);
    try {
      if (Array.isArray(value)) {
        return value.slice(0, 64).map(v => sanitize(v, depth + 1, seen));
      }
      const out = {};
      for (const key of Object.keys(value).slice(0, 64)) {
        try { out[key.slice(0, 256)] = sanitize(value[key], depth + 1, seen); }
        catch (_) { out[key.slice(0, 256)] = '[Unreadable]'; }
      }
      return out;
    } finally {
      seen.delete(value);
    }
  };
  const MAX_LOG_ENTRIES = 800;
  const log = (kind, payload) => {
    try {
      const buf = window.__oh_rtc_log = window.__oh_rtc_log || [];
      // 事件判别字段始终由本地控制；轨道事件使用 `trackKind` 保存媒体类型，
      // 避免载荷覆盖 `kind`。
      const clean = sanitize(payload);
      buf.push({ ...(clean || {}), kind, ts: Date.now() });
      if (buf.length > MAX_LOG_ENTRIES) {
        buf.splice(0, buf.length - MAX_LOG_ENTRIES);
      }
    } catch (_) {}
  };
  const Orig = window.RTCPeerConnection || window.webkitRTCPeerConnection;
  if (!Orig) return;
  let nextId = 1;
  // 活跃 PeerConnection 注册表，供周期性 getStats 轮询使用。
  const reg = window.__oh_rtc_reg = window.__oh_rtc_reg || new Map();
  const MAX_CONNECTIONS = 128;
  const STATS_INTERVAL_MS = 1000;
  const STATS_TIMEOUT_MS = 4000;
  let statsBusy = false;
  const stopStatsTimer = () => {
    if (!window.__oh_rtc_stats_timer) return;
    clearInterval(window.__oh_rtc_stats_timer);
    window.__oh_rtc_stats_timer = 0;
  };
  const getStatsBounded = async (pc) => {
    let timeoutId = 0;
    try {
      return await Promise.race([
        pc.getStats(null),
        new Promise(resolve => {
          timeoutId = setTimeout(() => resolve(null), STATS_TIMEOUT_MS);
        }),
      ]);
    } finally {
      if (timeoutId) clearTimeout(timeoutId);
    }
  };
  // 每秒采集活跃连接的收发量、丢包、往返时延和抖动。
  const pollStats = async () => {
    if (statsBusy) return;
    if (reg.size === 0) {
      stopStatsTimer();
      return;
    }
    statsBusy = true;
    try {
      for (const [id, pc] of reg) {
        try {
          if (!pc || pc.connectionState === 'closed' || pc.connectionState === 'failed') {
            reg.delete(id);
            continue;
          }
          const stats = await getStatsBounded(pc);
          if (!stats) {
            reg.delete(id);
            continue;
          }
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
    } finally {
      statsBusy = false;
      if (reg.size === 0) stopStatsTimer();
    }
  };
  const ensureStatsTimer = () => {
    if (window.__oh_rtc_stats_timer) return;
    window.__oh_rtc_stats_timer = setInterval(pollStats, STATS_INTERVAL_MS);
  };
  function patched(...args) {
    const pc = new Orig(...args);
    const id = nextId++;
    reg.set(id, pc);
    if (reg.size > MAX_CONNECTIONS) reg.delete(reg.keys().next().value);
    ensureStatsTimer();
    log('pc.create', { id, config: args[0] || null });
    const serializeArg = (value) => {
      try {
        return value && typeof value.toJSON === 'function'
          ? value.toJSON()
          : value;
      } catch (_) {
        return String(value);
      }
    };
    const wrap = (name) => {
      const m = pc[name];
      if (typeof m !== 'function') return;
      pc[name] = async function(...a) {
        log(name + ':call', {
          id,
          args: a.map(serializeArg),
        });
        try {
          const r = await m.apply(pc, a);
          if (r && (r.sdp || r.type)) {
            log(name + ':result', { id, sdp: r.sdp, type: r.type });
          }
          if (name === 'setLocalDescription' || name === 'setRemoteDescription') {
            const description = a[0] || r ||
              (name === 'setLocalDescription'
                ? pc.localDescription
                : pc.remoteDescription);
            if (description && (description.sdp || description.type)) {
              log(name + ':result', {
                id,
                sdp: description.sdp || '',
                type: description.type || '',
              });
            }
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
        trackKind: ev.track.kind,
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
        if (reg.size === 0) stopStatsTimer();
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
})();
''';
    try {
      await _installDocumentInitScript(cdp, js, sessionId: sessionId);
      if (_pageSessionId != sessionId) return false;
      _rtcInstalled = true;
      return true;
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '安装网页实时通信采集器', error, stack);
      return false;
    }
  }

  /// 拉取 WebRTC 日志并 drain。
  Future<List<Map<String, Object?>>> readWebRtcLog() async {
    final cdp = _browserCdp;
    final sessionId = _pageSessionId;
    if (cdp == null || sessionId == null) return const [];
    try {
      final r = await cdp.send(
        'Runtime.evaluate',
        params: const <String, Object?>{
          'expression':
              '(()=>{const a=window.__oh_rtc_log||[];window.__oh_rtc_log=[];return JSON.stringify(a);})()',
          'returnByValue': true,
        },
        sessionId: sessionId,
        timeout: _cdpInspectTimeout,
      );
      if (_pageSessionId != sessionId) return const [];
      final raw = cdpStringResultValue(r);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return compactWebReverseWebRtcLog(decoded);
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '读取网页实时通信日志', error, stack);
      return const [];
    }
  }

  /// 读取 page 当前 FPS 值；installFpsCounter 应先调用。
  Future<double?> readFps() async {
    final cdp = _browserCdp;
    final sessionId = _pageSessionId;
    if (cdp == null || sessionId == null) return null;
    try {
      final r = await cdp.send(
        'Runtime.evaluate',
        params: const <String, Object?>{
          'expression': 'window.__oh_fps || 0',
          'returnByValue': true,
        },
        sessionId: sessionId,
        timeout: _cdpLightCommandTimeout,
      );
      if (_pageSessionId != sessionId) return null;
      final v = cdpResultValue(r);
      return v is num ? v.toDouble() : null;
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '读取帧率', error, stack);
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
      return ok;
    }
    // start 是异步的：在它的 await 期间可能有订阅者 release 到 0，而那次
    // release 因为当时 _screencastActive 尚为 false 直接返回了、没真正 stop。
    // 若此刻已无人认领，这次 start 就成了停不下来的悬挂投屏，补一次收尾。
    if (_screencastRefCount == 0) {
      await releaseScreencast();
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
      silentLog('web_reverse_session_controller', '释放页面投屏', error, stack);
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
      silentLog('web_reverse_session_controller', '为当前订阅者启动页面投屏', error, stack);
      return false;
    }
  }

  void _resetScreencastRuntimeState({required bool resetRefCount}) {
    _screencastActive = false;
    if (resetRefCount) _screencastRefCount = 0;
    _latestScreencastFrame = null;
    _screencastFrameSeq = 0;
    _screencastStartedAt = null;
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
      silentLog('web_reverse_session_controller', '重新配置页面投屏', error, stack);
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
        timeout: _cdpControlTimeout,
      );
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '派发鼠标事件：$type', error, stack);
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
        timeout: _cdpControlTimeout,
      );
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '派发键盘事件：$type', error, stack);
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
        timeout: _cdpControlTimeout,
      );
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '插入文本', error, stack);
    }
  }

  /// 把页面导航到 [url]。内嵌浏览器地址栏回车 / 下拉历史均走这里。
  Future<void> navigate(String url) async {
    final cdp = _browserCdp;
    final normalizedUrl = _validatedPageUrlInput(url);
    if (cdp == null || _pageSessionId == null || normalizedUrl == null) return;
    try {
      await cdp.send(
        'Page.navigate',
        params: <String, Object?>{'url': normalizedUrl},
        sessionId: _pageSessionId,
        timeout: _cdpIoTimeout,
      );
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        '导航页面：$normalizedUrl',
        error,
        stack,
      );
    }
  }

  /// 后退一帧（若有历史）。
  Future<void> goBack() async {
    await _navigateHistoryOffset(-1, logAction: '后退');
  }

  /// 前进一帧（若有历史）。
  Future<void> goForward() async {
    await _navigateHistoryOffset(1, logAction: '前进');
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
        timeout: _cdpControlTimeout,
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
      silentLog(
        'web_reverse_session_controller',
        '页面历史导航：$logAction',
        error,
        stack,
      );
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
      silentLog('web_reverse_session_controller', '重新加载页面', error, stack);
    }
  }

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
      silentLog('web_reverse_session_controller', '应用分辨率模拟', error, stack);
    }
  }

  /// 设备模拟预设：移动 / 平板 / 桌面等档位；底层走
  /// `Emulation.setDeviceMetricsOverride` + `Emulation.setUserAgentOverride`，
  /// 传 `null` 则清除两类 override。
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
      silentLog('web_reverse_session_controller', '设置设备指标预设', error, stack);
      return false;
    }
  }

  /// 设置浏览器侧的页面缩放比例。`scale=1` 即 100%。
  ///
  /// 当前页立即应用缩放，并注入初始化脚本以在页面导航后恢复设置。
  /// DOM 尚未就绪时先处理根节点，再在加载完成后补充 body。
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
          silentLog('web_reverse_session_controller', '移除旧缩放脚本', error, stack);
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
      // initJs 自身在顶层调用 apply()，注入即对当前页生效，无需另拼一条
      // 立即执行的表达式——那份表达式用 `||` 短路，实际只会命中 body 与
      // documentElement 之一，与导航后重放的效果并不一致。
      _zoomScriptId = await _installDocumentInitScript(
        cdp,
        initJs,
        sessionId: _pageSessionId,
      );
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        '设置页面缩放比例：$clamped',
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
  Future<void>? _finderInstallTask;
  int _findRequestGeneration = 0;

  Future<int> findInPage(String query) async {
    final cdp = _browserCdp;
    final sessionId = _pageSessionId;
    if (cdp == null || sessionId == null) return 0;
    final boundedQuery = clipTextByCodeUnits(
      query,
      _maxFindQueryChars,
      suffix: '',
    );
    if (boundedQuery.trim().isEmpty) {
      await clearFindHighlights();
      return 0;
    }
    final requestGeneration = ++_findRequestGeneration;
    if (!_finderInstalled) {
      final installTask = _finderInstallTask ??= _installFinder();
      await installTask;
      if (identical(_finderInstallTask, installTask)) {
        _finderInstallTask = null;
      }
    }
    if (requestGeneration != _findRequestGeneration ||
        !identical(cdp, _browserCdp) ||
        sessionId != _pageSessionId) {
      return 0;
    }
    try {
      final r = await cdp.send(
        'Runtime.evaluate',
        params: <String, Object?>{
          'expression': '__oh_find_set(${jsonEncode(boundedQuery)})',
          'returnByValue': true,
        },
        sessionId: sessionId,
        timeout: _cdpScriptTimeout,
      );
      final v = cdpResultValue(r);
      return v is num ? v.toInt() : 0;
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '在页面中查找', error, stack);
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
      silentLog('web_reverse_session_controller', '切换页面查找结果', error, stack);
    }
  }

  Future<void> clearFindHighlights() async {
    _findRequestGeneration += 1;
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
      silentLog('web_reverse_session_controller', '清除页面查找高亮', error, stack);
    }
  }

  Future<void> _installFinder() async {
    final cdp = _browserCdp;
    final sessionId = _pageSessionId;
    if (cdp == null || sessionId == null) return;
    final js =
        r'''
(() => {
  if (window.__oh_find_installed) return;
  window.__oh_find_installed = true;
  let marks = [];
  let curIndex = -1;
  const MAX_TEXT_NODES = __OPENHAND_MAX_FIND_TEXT_NODES__;
  const MAX_TEXT_CHARS = __OPENHAND_MAX_FIND_TEXT_CHARS__;
  const MAX_MATCHES = __OPENHAND_MAX_FIND_MATCHES__;
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
    while (nodes.length < MAX_TEXT_NODES && (cur = walker.nextNode())) {
      nodes.push(cur);
    }
    let scannedTextChars = 0;
    for (const n of nodes) {
      if (scannedTextChars >= MAX_TEXT_CHARS) break;
      const sourceText = n.nodeValue || '';
      const remainingTextChars = MAX_TEXT_CHARS - scannedTextChars;
      const text = sourceText.length > remainingTextChars
        ? sourceText.slice(0, remainingTextChars)
        : sourceText;
      scannedTextChars += text.length;
      let m; const frag = document.createDocumentFragment();
      let last = 0;
      re.lastIndex = 0;
      while ((m = re.exec(text)) != null) {
        if (marks.length >= MAX_MATCHES) break;
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
        if (last < sourceText.length) frag.appendChild(document.createTextNode(sourceText.slice(last)));
        n.parentNode && n.parentNode.replaceChild(frag, n);
      }
      if (marks.length >= MAX_MATCHES) break;
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
'''
            .replaceAll(
              '__OPENHAND_MAX_FIND_TEXT_NODES__',
              '$_maxFindTextNodes',
            )
            .replaceAll(
              '__OPENHAND_MAX_FIND_TEXT_CHARS__',
              '$_maxFindTextChars',
            )
            .replaceAll('__OPENHAND_MAX_FIND_MATCHES__', '$_maxFindMatches');
    try {
      await _installDocumentInitScript(cdp, js, sessionId: sessionId);
      if (!identical(cdp, _browserCdp) || sessionId != _pageSessionId) return;
      _finderInstalled = true;
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '安装页面查找器', error, stack);
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
        timeout: _cdpControlTimeout,
      );
      final value = cdpResultValue(r);
      return value is String
          ? _capPlainWebReverseText(value, maxPageTargetUrlChars)
          : null;
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '读取当前页面地址', error, stack);
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
          timeout: _cdpIoTimeout,
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
        timeout: _cdpScreenshotTimeout,
        maxResponseCharacters: _maxScreenshotResponseCharacters,
      );
      final data = r['data'] as String?;
      if (data == null || data.isEmpty) return null;
      return decodeBase64Bounded(
        data,
        maxDecodedBytes: _maxScreenshotDecodedBytes,
      );
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        '截取页面图像：格式=$format，整页=$capturePastViewport',
        error,
        stack,
      );
      return null;
    }
  }

  // ── Memory: V8 实时采样（HeapProfiler.startSampling） ─────────────────

  bool _samplingProfileRunning = false;
  Future<bool>? _memorySamplingStartTask;
  int _memorySamplingGeneration = 0;
  bool get isMemorySampling => _samplingProfileRunning;

  /// 启动 V8 采样（HeapProfiler.startSampling）。失败返回 false。
  Future<bool> startMemorySampling({double samplingInterval = 32768}) {
    final cdp = _browserCdp;
    final sessionId = _pageSessionId;
    if (cdp == null || sessionId == null) return Future<bool>.value(false);
    if (_samplingProfileRunning) return Future<bool>.value(true);
    final active = _memorySamplingStartTask;
    if (active != null) return active;
    final normalizedInterval = samplingInterval.isFinite
        ? samplingInterval.clamp(
            _minMemorySamplingInterval,
            _maxMemorySamplingInterval,
          )
        : 32768.0;
    final generation = ++_memorySamplingGeneration;
    late final Future<bool> task;
    task =
        _startMemorySamplingOnce(
          cdp,
          sessionId,
          generation,
          normalizedInterval,
        ).whenComplete(() {
          if (identical(_memorySamplingStartTask, task)) {
            _memorySamplingStartTask = null;
          }
        });
    _memorySamplingStartTask = task;
    return task;
  }

  Future<bool> _startMemorySamplingOnce(
    WebReverseCdpClient cdp,
    String sessionId,
    int generation,
    double samplingInterval,
  ) async {
    try {
      await cdp.send('HeapProfiler.enable', sessionId: sessionId);
      if (!_isMemorySamplingStartCurrent(cdp, sessionId, generation)) {
        return false;
      }
      await cdp.send(
        'HeapProfiler.startSampling',
        params: <String, Object?>{'samplingInterval': samplingInterval},
        sessionId: sessionId,
      );
      if (!_isMemorySamplingStartCurrent(cdp, sessionId, generation)) {
        await _stopMemorySamplingRuntime(cdp, sessionId);
        return false;
      }
      _samplingProfileRunning = true;
      _safeNotify();
      return true;
    } catch (error, stack) {
      if (_isMemorySamplingStartCurrent(cdp, sessionId, generation)) {
        silentLog('web_reverse_session_controller', '开始内存采样', error, stack);
      }
      return false;
    }
  }

  /// 停止采样并返回汇总；采样未开启或已停止时调用返回 null。
  Future<
    ({int totalSize, List<({String label, int size, List<String> stack})> top})?
  >
  stopMemorySampling() async {
    final cdp = _browserCdp;
    final sessionId = _pageSessionId;
    final starting = _memorySamplingStartTask;
    _memorySamplingGeneration += 1;
    final wasRunning = _samplingProfileRunning;
    _samplingProfileRunning = false;
    if (wasRunning) _safeNotify();
    Map<String, Object?>? result;
    try {
      if (cdp != null &&
          sessionId != null &&
          (wasRunning || starting != null)) {
        result = await _stopMemorySamplingRuntime(cdp, sessionId);
      }
      if (starting != null) {
        await runAsyncCleanupBounded(
          () => starting,
          timeout: _browserCleanupTimeout,
          onError: (error, stack) => silentLog(
            'web_reverse_session_controller',
            '等待内存采样停止启动',
            error,
            stack,
          ),
        );
      }
      if (result == null) return null;
      final profile = stringKeyedMapFromValue(result['profile']);
      if (profile.isEmpty) return null;
      return summarizeSamplingHeapProfile(profile['head']);
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '停止内存采样', error, stack);
      return null;
    }
  }

  bool _isMemorySamplingStartCurrent(
    WebReverseCdpClient cdp,
    String sessionId,
    int generation,
  ) {
    return !_disposed &&
        !_stopped &&
        generation == _memorySamplingGeneration &&
        identical(_browserCdp, cdp) &&
        _pageSessionId == sessionId;
  }

  Future<Map<String, Object?>?> _stopMemorySamplingRuntime(
    WebReverseCdpClient cdp,
    String sessionId,
  ) async {
    try {
      return await cdp.send(
        'HeapProfiler.stopSampling',
        sessionId: sessionId,
        timeout: _cdpIoTimeout,
      );
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '停止内存采样运行时', error, stack);
      return null;
    }
  }

  /// 拉一次 V8 内存上报（不停止采样）：JSHeapUsedSize / JSHeapTotalSize。
  /// 用于面板的实时折线，避免 stopSampling 中断采样数据。
  Future<({double used, double total})?> readJsHeap() async {
    final metrics = await performanceMetrics();
    if (metrics.isEmpty) return null;
    var used = 0.0;
    var total = 0.0;
    for (final (name, value) in metrics) {
      if (name == 'JSHeapUsedSize') used = value < 0 ? 0 : value;
      if (name == 'JSHeapTotalSize') total = value < 0 ? 0 : value;
    }
    return (used: used, total: total);
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
  final Stopwatch _pendingFetchStopwatch = Stopwatch()..start();
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
            _pendingFetchStopwatch.elapsedMilliseconds -
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
      silentLog('web_reverse_session_controller', '设置请求拦截状态', error, stack);
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
        '继续请求：$requestId',
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
      silentLog('web_reverse_session_controller', '继续已编辑请求', error, stack);
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
        '终止请求：$requestId',
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
      'createdAtMs': _pendingFetchStopwatch.elapsedMilliseconds,
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
          'name': kContentTypeHeaderName,
          'value': rule.contentType.isEmpty
              ? kApplicationJsonUtf8ContentType
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
        timeout: _cdpScriptTimeout,
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
      silentLog('web_reverse_session_controller', '响应模拟请求', e, st);
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
      silentLog('web_reverse_session_controller', '设置拦截地址', error, stack);
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
        'headers': (overrideHeaders ?? e.requestHeaders).map(MapEntry.new),
      if (e.requestPostData != null) 'body': e.requestPostData,
      'credentials': 'include',
    };
    final js =
        '''
(async () => {
  const maxBytes = $_maxReplayResponsePreviewBytes;
  const controller = new AbortController();
  const timer = setTimeout(
    () => controller.abort('timeout'),
    ${_replayRequestTimeout.inMilliseconds},
  );
  try {
    const init = ${jsonEncode(init)};
    init.signal = controller.signal;
    const r = await fetch(${jsonEncode(url)}, init);
    if (!r.body) return JSON.stringify({ status: r.status, body: '' });
    const reader = r.body.getReader ? r.body.getReader() : null;
    if (!reader) throw new Error('无法流式读取响应体');
    const chunks = [];
    let total = 0;
    try {
      while (total < maxBytes) {
        const part = await reader.read();
        if (part.done) break;
        const value = part.value || new Uint8Array();
        const retained = value.slice(0, maxBytes - total);
        chunks.push(retained);
        total += retained.byteLength;
        if (retained.byteLength < value.byteLength || total >= maxBytes) {
          try { await reader.cancel(); } catch (_) {}
          break;
        }
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
    const body = new TextDecoder('utf-8').decode(bytes);
    return JSON.stringify({ status: r.status, body });
  } catch (err) {
    try { controller.abort('failed'); } catch (_) {}
    return JSON.stringify({
      status: -1,
      body: String(err).slice(0, maxBytes),
    });
  } finally {
    clearTimeout(timer);
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
        timeout: _replayRequestTimeout + const Duration(seconds: 2),
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
      silentLog('web_reverse_session_controller', '重放请求', error, stack);
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
      silentLog('web_reverse_session_controller', '设置网络限速', error, stack);
      return false;
    }
  }

  /// Debugger 已 attach 的脚本（`Debugger.scriptParsed`）。Sources tab 用。
  /// key=scriptId，value=(url, isModule)。源码本身在 [_scriptSources] 缓存。
  final Map<String, ({String url, bool isModule})> _parsedScripts =
      <String, ({String url, bool isModule})>{};
  late final Map<String, ({String url, bool isModule})> _parsedScriptsView =
      UnmodifiableMapView<String, ({String url, bool isModule})>(
        _parsedScripts,
      );
  Map<String, ({String url, bool isModule})> get parsedScripts =>
      _parsedScriptsView;
  final LifecycleLruCache<String> _scriptSources = LifecycleLruCache<String>(
    maxEntries: _maxScriptSourceCacheEntries,
    maxCost: _maxScriptSourceCacheChars,
    costOf: (source) => source.length,
  );
  bool _scriptNotifyScheduled = false;

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
    _scheduleScriptNotify();
  }

  void _scheduleScriptNotify() {
    if (_scriptNotifyScheduled || _disposed) return;
    _scriptNotifyScheduled = true;
    scheduleMicrotask(() {
      _scriptNotifyScheduled = false;
      _safeNotify();
    });
  }

  void _onExecutionContextsCleared() {
    _parsedScripts.clear();
    _scriptSources.clear();
    _sourceMapCache.clear();
    _safeNotify();
  }

  /// 在 page 上启用 Debugger domain；调用后 [_onScriptParsed] 会陆续填充 [_parsedScripts]。
  Future<bool> enableDebugger() async {
    final cdp = _browserCdp;
    if (cdp == null || _pageSessionId == null) return false;
    try {
      await cdp.send('Debugger.enable', sessionId: _pageSessionId);
      return true;
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '启用调试器', error, stack);
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
    final sessionId = _pageSessionId;
    if (cdp == null || sessionId == null) return null;
    try {
      final r = await cdp.send(
        'Debugger.getScriptSource',
        params: <String, Object?>{'scriptId': scriptId},
        sessionId: sessionId,
        timeout: _cdpDebuggerTimeout,
      );
      final source = r['scriptSource'] as String?;
      if (source == null) return null;
      if (_disposed ||
          !identical(_browserCdp, cdp) ||
          _pageSessionId != sessionId ||
          !_parsedScripts.containsKey(scriptId)) {
        return null;
      }
      final boundedSource = _capWebReverseText(
        source,
        _maxScriptSourceChars,
        '脚本源码',
      );
      _scriptSources.put(scriptId, boundedSource);
      return boundedSource;
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '读取脚本源码', error, stack);
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
      silentLog('web_reverse_session_controller', '按地址设置断点', error, stack);
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
      silentLog('web_reverse_session_controller', '移除断点', error, stack);
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
      silentLog('web_reverse_session_controller', '恢复调试器运行', error, stack);
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
      silentLog('web_reverse_session_controller', '设置异常暂停策略', e, st);
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
      silentLog('web_reverse_session_controller', '添加异步请求断点', e, st);
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
      silentLog('web_reverse_session_controller', '移除异步请求断点', e, st);
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
      silentLog('web_reverse_session_controller', '执行调试器命令：$method', e, st);
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
      silentLog('web_reverse_session_controller', '在调用帧中求值', e, st);
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
      silentLog('web_reverse_session_controller', '求值监视表达式', e, st);
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
      silentLog('web_reverse_session_controller', '设置事件监听器断点', e, st);
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
      silentLog('web_reverse_session_controller', '移除事件监听器断点', e, st);
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
      silentLog('web_reverse_session_controller', '添加页面节点断点', e, st);
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
      silentLog('web_reverse_session_controller', '移除页面节点断点', e, st);
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
      silentLog('web_reverse_session_controller', '设置内容安全策略违规断点', e, st);
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
    final sessionId = _pageSessionId;
    if (cdp == null ||
        sessionId == null ||
        objectId.isEmpty ||
        objectId.length > kBytesPerKiB) {
      return const [];
    }
    try {
      final r = await cdp.send(
        'Runtime.getProperties',
        params: <String, Object?>{
          'objectId': objectId,
          'ownProperties': ownProperties,
          'generatePreview': generatePreview,
        },
        sessionId: sessionId,
        timeout: _cdpInspectTimeout,
      );
      if (_pageSessionId != sessionId) return const [];
      return compactWebReverseRuntimeProperties(r['result']);
    } catch (e, st) {
      silentLog('web_reverse_session_controller', '读取运行时对象属性', e, st);
      return const [];
    }
  }

  // ─── 全局事件监听器（window）─────────────────────────────────────────
  // CDP `DOMDebugger.getEventListeners` 需要一个 RemoteObject objectId；
  // 先 Runtime.evaluate 拿到 window 的 objectId 再请求。返回列表中每条包含
  // type/useCapture/passive/once/scriptId/lineNumber/columnNumber。
  Future<List<Map<String, Object?>>> listGlobalEventListeners() async {
    final cdp = _browserCdp;
    final sessionId = _pageSessionId;
    if (cdp == null || sessionId == null) return const [];
    const objectGroup = 'oh_global_listeners';
    try {
      final win = await cdp.send(
        'Runtime.evaluate',
        params: const <String, Object?>{
          'expression': 'window',
          'objectGroup': objectGroup,
        },
        sessionId: sessionId,
        timeout: _cdpScriptTimeout,
      );
      if (_pageSessionId != sessionId) return const [];
      final objectId = (win['result'] as Map?)?['objectId'] as String?;
      if (objectId == null ||
          objectId.isEmpty ||
          objectId.length > kBytesPerKiB) {
        return const [];
      }
      final r = await cdp.send(
        'DOMDebugger.getEventListeners',
        params: <String, Object?>{'objectId': objectId, 'depth': 1},
        sessionId: sessionId,
        timeout: _cdpInspectTimeout,
      );
      if (_pageSessionId != sessionId) return const [];
      return compactWebReverseDomEventListeners(r['listeners']);
    } catch (e, st) {
      silentLog('web_reverse_session_controller', '读取全局事件监听器', e, st);
      return const [];
    } finally {
      if (_pageSessionId == sessionId) {
        try {
          await cdp.send(
            'Runtime.releaseObjectGroup',
            params: const <String, Object?>{'objectGroup': objectGroup},
            sessionId: sessionId,
            timeout: _cdpControlTimeout,
          );
        } catch (error, stack) {
          silentLog(
            'web_reverse_session_controller',
            '释放全局监听器对象',
            error,
            stack,
          );
        }
      }
    }
  }

  /// JS 美化：单遍状态机扫描，正确处理字符串 / 模板字面量 (含 `${}`
  /// 插值递归) / 行注释 / 块注释 / 正则字面量。按 `{[(` 缩进、`}])` 退
  /// 缩、`;` 与 `{` 后换行、`} else/catch/finally/while/,/)` 智能合并。
  /// 大于 4 MB 直接返回原文，避免阻塞 UI。设计为零依赖、纯 Dart 实现，
  /// 优先保证「能读」而不是 prettier 级别的精确。
  static String prettifyJs(String src) {
    const maxSize = 4 * kBytesPerMiB;
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
    // 始/分隔符（如 `=,;:!&|?{([*/+-~^%<>` 或空），则是正则。
    bool looksLikeRegexStart() {
      if (prevSig.isEmpty) return true;
      const exprStarters = '=,;:!&|?{([*/+-~^%<>';
      if (exprStarters.contains(prevSig)) return true;
      // `return` / `typeof` / `in` / `of` 等关键字后接 `/` 也是正则。
      // 简化处理：回扫最多 12 个字符判断是否以这些关键字结尾。
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
          '恢复网络域状态：$method',
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
      silentLog('web_reverse_session_controller', '设置附加请求头', error, stack);
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
  Future<({int port, int entryCount})?> startHarReplayServer() {
    if (_harReplayServer != null) {
      return Future.value((
        port: _harReplayServer!.port,
        entryCount: _harReplayServer!.entryCount,
      ));
    }
    if (_disposed || _stopped) {
      return Future.value();
    }
    final active = _harReplayStartTask;
    if (active != null) return active;
    final generation = ++_harReplayGeneration;
    late final Future<({int port, int entryCount})?> task;
    task = _startHarReplayServer(generation).whenComplete(() {
      if (identical(_harReplayStartTask, task)) {
        _harReplayStartTask = null;
      }
    });
    _harReplayStartTask = task;
    return task;
  }

  Future<({int port, int entryCount})?> _startHarReplayServer(
    int generation,
  ) async {
    try {
      // 优先用 in-flight artifacts；为空时生成一个临时 HAR。
      String? path = _lastHarPath;
      path ??= await _artifacts.exportHar();
      if (path == null ||
          _disposed ||
          _stopped ||
          generation != _harReplayGeneration) {
        return null;
      }
      final read = await readWebReverseHarPath(path);
      if (read.isTooLarge ||
          _disposed ||
          _stopped ||
          generation != _harReplayGeneration) {
        return null;
      }
      final s = await WebReverseHarReplayServer.start(harBytes: read.bytes!);
      if (s == null) return null;
      if (_disposed || _stopped || generation != _harReplayGeneration) {
        await s.close();
        return null;
      }
      _harReplayServer = s;
      _safeNotify();
      return (port: s.port, entryCount: s.entryCount);
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '启动网络归档重放服务', error, stack);
      return null;
    }
  }

  Future<void> stopHarReplayServer() async {
    final starting = _harReplayStartTask;
    _harReplayGeneration += 1;
    final s = _harReplayServer;
    _harReplayServer = null;
    if (s != null) {
      _safeNotify();
      await s.close();
    }
    if (starting != null) {
      await runAsyncCleanupBounded(
        () => starting,
        timeout: _browserCleanupTimeout,
        onError: (error, stack) => silentLog(
          'web_reverse_session_controller',
          '等待网络归档重放服务停止启动',
          error,
          stack,
        ),
      );
    }
  }

  // ── mitmproxy 桥接：抓 OpenHand 控制不到的流量（App 内嵌 webview / 第三方应用） ─
  WebReverseMitmproxyBridge? _mitmBridge;
  StreamSubscription<Map<String, Object?>>? _mitmSub;
  Future<({int mitmPort, int callbackPort})?>? _mitmBridgeStartTask;
  int _mitmBridgeGeneration = 0;
  WebReverseMitmproxyBridge? get mitmproxyBridge => _mitmBridge;
  int _mitmCount = 0;
  int get mitmproxyCount => _mitmCount;

  Future<({int mitmPort, int callbackPort})?> startMitmproxyBridge({
    int mitmPort = 8080,
  }) {
    if (_mitmBridge != null) {
      return Future.value((
        mitmPort: _mitmBridge!.mitmPort,
        callbackPort: _mitmBridge!.callbackPort,
      ));
    }
    if (_disposed || _stopped) {
      return Future.value();
    }
    final active = _mitmBridgeStartTask;
    if (active != null) return active;
    final generation = ++_mitmBridgeGeneration;
    late final Future<({int mitmPort, int callbackPort})?> task;
    task = _startMitmproxyBridge(mitmPort, generation).whenComplete(() {
      if (identical(_mitmBridgeStartTask, task)) {
        _mitmBridgeStartTask = null;
      }
    });
    _mitmBridgeStartTask = task;
    return task;
  }

  Future<({int mitmPort, int callbackPort})?> _startMitmproxyBridge(
    int mitmPort,
    int generation,
  ) async {
    final br = await WebReverseMitmproxyBridge.start(mitmPort: mitmPort);
    if (br == null) return null;
    if (_disposed || _stopped || generation != _mitmBridgeGeneration) {
      await br.close();
      return null;
    }
    _mitmBridge = br;
    _mitmCount = 0;
    _mitmSub = br.eventStream.listen((m) {
      if (_disposed || !identical(_mitmBridge, br)) return;
      _mitmCount++;
      // 把 mitmproxy 流量也注入 dashboard 的网络列表，统一观察口径。
      // 这里只取核心字段做轻量适配；body 已 base64 缓存到 cachedBody 备查。
      final kind = _capPlainWebReverseText('${m['kind'] ?? ''}', 32);
      final url = _capPlainWebReverseText(
        '${m['url'] ?? ''}',
        _maxImportedUrlChars,
      );
      if (url.isEmpty) return;
      if (kind == 'request') {
        final entry = CdpNetworkEntry(
          requestId: _capPlainWebReverseText(
            'mitm-$_mitmCount-${m['ts'] ?? ''}',
            512,
          ),
          url: url,
          method: _capPlainWebReverseText('${m['method'] ?? 'GET'}', 32),
          timestamp: DateTime.now(),
          resourceType: 'mitmproxy',
        );
        entry.requestHeaders.addAll(_flattenHeaderPairs(m['headers']));
        final bodyB64 = m['body_b64'] as String?;
        if (bodyB64 != null && bodyB64.isNotEmpty) {
          try {
            entry.requestPostData = utf8.decode(
              decodeBase64Bounded(
                bodyB64,
                maxDecodedBytes: _maxMitmDecodedBodyBytes,
              ),
            );
          } catch (_) {
            // 非法 base64 / 超限 / 非 UTF-8 请求体：按“无请求体”降级，
            // 不能让单条 mitm 记录中断整个抓包流。
          }
        }
        _networkRequests.add(entry);
        _networkByRequestId[entry.requestId] = entry;
      } else if (kind == 'response') {
        // 找最近一条同 url 的 mitm 请求并补响应。
        final match = _networkRequests.lastWhere(
          (e) => e.url == url && e.requestId.startsWith('mitm-'),
          orElse: () => CdpNetworkEntry(
            requestId: _capPlainWebReverseText(
              'mitm-resp-$_mitmCount-${m['ts'] ?? ''}',
              512,
            ),
            url: url,
            method: 'GET',
            timestamp: DateTime.now(),
            resourceType: 'mitmproxy',
          )..requestHeaders.clear(),
        );
        match.statusCode = optionalIntFromValue(m['status']);
        match.responseHeaders.addAll(_flattenHeaderPairs(m['headers']));
        match.responseReceivedAt = DateTime.now();
        match.loadingFinishedAt = match.responseReceivedAt;
        final bodyB64 = m['body_b64'] as String?;
        if (bodyB64 != null && bodyB64.isNotEmpty) {
          try {
            decodeBase64Bounded(
              bodyB64,
              maxDecodedBytes: _maxMitmDecodedBodyBytes,
            );
            match.cachedBody = bodyB64;
            match.cachedBodyBase64 = true;
          } catch (_) {
            // 非法 base64 或超出解码上限：跳过缓存响应体，保留其余元数据。
          }
        }
        if (!_networkByRequestId.containsKey(match.requestId)) {
          _networkRequests.add(match);
          _networkByRequestId[match.requestId] = match;
        }
      }
      _trimNetworkEntries();
      _notifyInspectorChanged();
    });
    _safeNotify();
    return (mitmPort: br.mitmPort, callbackPort: br.callbackPort);
  }

  Future<void> stopMitmproxyBridge() async {
    final starting = _mitmBridgeStartTask;
    _mitmBridgeGeneration += 1;
    final br = _mitmBridge;
    _mitmBridge = null;
    await _cancelRuntimeSubscription(_mitmSub, '停止流量代理事件订阅');
    _mitmSub = null;
    if (br != null) {
      _safeNotify();
      await br.close();
    }
    if (starting != null) {
      await runAsyncCleanupBounded(
        () => starting,
        timeout: _browserCleanupTimeout,
        onError: (error, stack) => silentLog(
          'web_reverse_session_controller',
          '等待流量代理桥接停止启动',
          error,
          stack,
        ),
      );
    }
  }

  /// 一键打包"体检报告"：把 artifacts 目录下所有 jsonl/HAR/截图 +
  /// recorder steps + 当前 networkRequests 概要写到一个 .zip 临时文件，
  /// 返回输出路径。失败返回 null。
  Future<String?> exportSessionBundle({String? destPath}) async {
    final src = Directory(artifactsRootDir);
    if (!await isDirectoryPath(src.path)) return null;
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
            '压缩会话包失败，退出码：${r.exitCode}',
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
            '压缩会话包失败，退出码：${r.exitCode}',
            r.stderr,
            StackTrace.current,
          );
          return null;
        }
      }
      return out.path;
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '导出会话包', error, stack);
      return null;
    }
  }

  /// 拉取指定请求的 response body（CDP `Network.getResponseBody`）。
  /// 自动缓存到 entry.cachedBody，重复点击不再发请求。
  /// 文本类返回 (body, false)，二进制类返回 (base64, true)；失败返回 null。
  Future<(String, bool)?> fetchResponseBody(String requestId) async {
    final normalizedRequestId = _validatedNetworkRequestId(requestId);
    if (normalizedRequestId == null) return null;
    final entry = _networkByRequestId[normalizedRequestId];
    if (entry == null) return null;
    if (entry.cachedBody != null) {
      return (entry.cachedBody!, entry.cachedBodyBase64);
    }
    final cdp = _browserCdp;
    final sessionId = _pageSessionId;
    if (cdp == null || sessionId == null) return null;
    try {
      final result = await cdp.send(
        'Network.getResponseBody',
        params: <String, Object?>{'requestId': normalizedRequestId},
        sessionId: sessionId,
        timeout: _cdpIoTimeout,
      );
      if (_pageSessionId != sessionId ||
          _networkByRequestId[normalizedRequestId] != entry) {
        return null;
      }
      final rawBody = result['body'];
      if (rawBody is! String) return null;
      var base64 = result['base64Encoded'] == true;
      late final String body;
      if (base64 && rawBody.length > _maxCachedResponseBodyChars) {
        body =
            '[OpenHand omitted oversized binary response: '
            '${rawBody.length} Base64 chars]';
        base64 = false;
      } else {
        body = base64
            ? rawBody
            : _capWebReverseText(rawBody, _maxCachedResponseBodyChars, '响应正文');
      }
      entry.cachedBody = body;
      entry.cachedBodyBase64 = base64;
      return (body, base64);
    } catch (error, stack) {
      silentLog(
        'web_reverse_session_controller',
        '读取响应正文：$normalizedRequestId',
        error,
        stack,
      );
      return null;
    }
  }

  /// 把当前 HAR 写到用户选定路径（来自 file_selector）；返回写出路径或 null。
  Future<String?> exportHarToPath(String destPath) async {
    final src = await _artifacts.exportHar();
    if (src == null) return null;
    try {
      await copyFileAtomically(
        File(src),
        File(destPath),
        maxBytes: _maxImportedHarBytes,
      );
      _lastHarPath = destPath;
      _safeNotify();
      return destPath;
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '复制网络归档到目标路径', error, stack);
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
    if (bytes.length > _maxImportedHarBytes) {
      return (loaded: 0, skipped: 1);
    }
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
                label: 'HAR 请求正文',
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
      _notifyInspectorChanged();
      return (loaded: loaded, skipped: skipped);
    } catch (error, stack) {
      silentLog('web_reverse_session_controller', '载入网络归档数据', error, stack);
      return (loaded: 0, skipped: 0);
    }
  }

  static String _resourceTypeFromMime(String mime) {
    final m = mime.toLowerCase();
    if (isImageMimeType(m)) return 'Image';
    if (m.contains('javascript')) return 'Script';
    if (m.contains('json')) return 'Fetch';
    if (m.contains('css')) return 'Stylesheet';
    if (m.contains('html')) return 'Document';
    if (m.contains('font')) return 'Font';
    if (isAudioMimeType(m) || isVideoMimeType(m)) return 'Media';
    return 'Other';
  }

  /// 通过同一个幂等异步任务关闭浏览器、辅助服务、订阅和原始事件总线。
  Future<void> shutdown() {
    final active = _shutdownFuture;
    if (active != null) return active;
    _disposed = true;
    _stopped = true;
    _pendingFetchStopwatch.stop();
    _pauseCronTimers();
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
                '关闭原始调试协议事件总线',
                error,
                stack,
              ),
            );
          }
        }().catchError((Object error, StackTrace stack) {
          silentLog('web_reverse_session_controller', '关闭会话', error, stack);
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
    sourceJumpRequest.dispose();
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
            label: '快照请求正文',
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
            label: '快照发起方 URL',
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
            label: '快照错误文本',
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
                '控制台文本',
              ),
              timestamp: dateTimeFromValue(m['ts']) ?? DateTime.now(),
            ),
          );
        }
      }
      _notifyInspectorChanged();
      return _networkRequests.length;
    } catch (e, st) {
      silentLog('web_reverse_session_controller', '导入会话快照', e, st);
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
        '取消运行时订阅：$where',
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
            timeout: _cdpControlTimeout,
          );
        } catch (e, st) {
          silentLog('web_reverse_session_controller', '执行断点表达式', e, st);
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
      silentLog('web_reverse_session_controller', '读取当前页面源地址', error, stack);
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
        cookies: cookies.map(Map<String, Object?>.from).toList(growable: false),
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
          '清空浏览器 Cookie',
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
            '恢复账户快照 Cookie',
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
          '为账户快照启用页面存储',
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
              '恢复账户快照存储',
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
      silentLog('web_reverse_session_controller', '恢复账户快照超时', error, stack);
      return false;
    } finally {
      restoreActive = false;
    }
  }

  // 源码映射解析
  // 缓存 key 用脚本 URL；map 经常达到数 MB，因此同时限制条目数与估算字符数。
  final LifecycleLruCache<WebReverseSourceMapInfo> _sourceMapCache =
      LifecycleLruCache<WebReverseSourceMapInfo>(
        maxEntries: _maxSourceMapCacheEntries,
        maxCost: _maxSourceMapCacheChars,
        costOf: (value) => value.estimatedRetainedChars,
      );

  /// 从已解析脚本的 URL 抓取并解析 Source Map：先读取脚本中的
  /// `sourceMappingURL`，再获取并校验映射文件。VLQ 定位由使用方按需执行。
  /// 返回 null：网络失败 / map 不存在 / JSON 解析失败。
  Future<WebReverseSourceMapInfo?> fetchSourceMapForUrl(String url) async {
    if (url.isEmpty || url.length > _maxImportedUrlChars) return null;
    final cached = _sourceMapCache.get(url);
    if (cached != null) return cached;
    final cdp = _browserCdp;
    final sessionId = _pageSessionId;
    if (cdp == null || sessionId == null) return null;
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
      throw new Error('响应超过 Source Map 大小上限');
    }
    const reader = response.body && response.body.getReader
      ? response.body.getReader()
      : null;
    if (!reader) throw new Error('无法流式读取响应体');
    const chunks = [];
    let total = 0;
    try {
      while (true) {
        const part = await reader.read();
        if (part.done) break;
        const value = part.value || new Uint8Array();
        if (total + value.byteLength > maxBytes) {
          try { await reader.cancel(); } catch (_) {}
          throw new Error('响应超过 Source Map 大小上限');
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
    if (!r.ok) throw new Error('脚本请求失败：HTTP ' + r.status);
    const text = await readText(r);
    const m = /[#@]\\s*sourceMappingURL=(\\S+)/.exec(text);
    if (!m) return JSON.stringify({ error: '未找到 sourceMappingURL' });
    let mapUrl = m[1];
    let mapText;
    if (mapUrl.startsWith('data:')) {
      const comma = mapUrl.indexOf(',');
      if (comma < 0) throw new Error('内联 Source Map URL 无效');
      const metadata = mapUrl.slice(0, comma).toLowerCase();
      const payload = mapUrl.slice(comma + 1);
      if (metadata.includes(';base64')) {
        const binary = atob(payload);
        if (binary.length > maxBytes) {
          throw new Error('内联 Source Map 超过大小上限');
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
        throw new Error('Source Map URL 超过长度上限');
      }
      const mr = await fetch(mapUrl, { signal: controller.signal });
      if (!mr.ok) throw new Error('Source Map 请求失败：HTTP ' + mr.status);
      mapText = await readText(mr);
    }
    if (mapText.length > maxBytes) {
      throw new Error('Source Map 超过大小上限');
    }
    const map = JSON.parse(mapText);
    if (!map || typeof map !== 'object' || Array.isArray(map)) {
      throw new Error('Source Map 根节点必须为对象');
    }
    return JSON.stringify({ map, mapUrl });
  } catch (err) {
    try { controller.abort('failed'); } catch (_) {}
    return JSON.stringify({ error: String(err) });
  } finally {
    clearTimeout(timer);
  }
})()
''';
      final r = await evaluateJavaScript(
        js,
        awaitPromise: true,
        timeout: _sourceMapFetchTimeout + const Duration(seconds: 2),
      );
      if (_disposed ||
          !identical(_browserCdp, cdp) ||
          _pageSessionId != sessionId) {
        return null;
      }
      final raw = cdpStringResultValue(r);
      if (raw == null || raw.length > _maxSourceMapResultChars) {
        return null;
      }
      final wrap = decodeStringKeyedJsonMap(raw);
      if (wrap == null || wrap['error'] != null || wrap['map'] is! Map) {
        return null;
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
        return null;
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
      silentLog('web_reverse_session_controller', '按地址获取源映射', e, st);
      return null;
    }
  }

  WebReverseSourceMapInfo _cacheSourceMap(
    String url,
    WebReverseSourceMapInfo value,
  ) {
    _sourceMapCache.put(url, value);
    return value;
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
  return clipTextByCodeUnits(
    text,
    maxChars,
    suffix: '\n\n[OpenHand 已截断：$label]',
  );
}

String _capPlainWebReverseText(String text, int maxChars) {
  return clipTextByCodeUnits(text, maxChars, suffix: '');
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
        ? kApplicationJsonUtf8ContentType
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
    case 'input':
      normalized['value'] = _capPlainWebReverseText(
        '${step['value'] ?? ''}',
        WebReverseSessionController.maxRecorderStepTextChars,
      );
    case 'change':
      final value = step['value'];
      normalized['value'] = value == null || value is bool || value is num
          ? value
          : _capPlainWebReverseText(
              '$value',
              WebReverseSessionController.maxRecorderStepTextChars,
            );
    case 'assertText':
      normalized['expected'] = _capPlainWebReverseText(
        '${step['expected'] ?? ''}',
        WebReverseSessionController.maxRecorderStepTextChars,
      );
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
    if (raw['partitionKeyOpaque'] == true) continue;
    if (raw['name'] is! String ||
        (raw['value'] != null && raw['value'] is! String) ||
        (raw['domain'] != null && raw['domain'] is! String) ||
        (raw['path'] != null && raw['path'] is! String) ||
        (raw['sameSite'] != null && raw['sameSite'] is! String)) {
      continue;
    }
    final rawName = raw['name'] as String;
    final rawValue = (raw['value'] as String?) ?? '';
    final rawDomain = (raw['domain'] as String?) ?? '';
    final rawPath = (raw['path'] as String?) ?? '';
    final rawSameSite = (raw['sameSite'] as String?) ?? '';
    final rawPartitionKey = raw['partitionKey'];
    final rawTopLevelSite =
        rawPartitionKey is Map && rawPartitionKey['topLevelSite'] is String
        ? rawPartitionKey['topLevelSite'] as String
        : '';
    if (rawPartitionKey != null && rawTopLevelSite.isEmpty) continue;
    if (rawName.isEmpty ||
        rawName.length > WebReverseSessionController.maxRuleHeaderNameChars ||
        rawValue.length >
            WebReverseSessionController.maxAccountSnapshotValueChars ||
        rawDomain.length > WebReverseSessionController.maxBreakpointTextChars ||
        rawPath.length > WebReverseSessionController.maxBreakpointTextChars ||
        rawSameSite.length > 64 ||
        rawTopLevelSite.length >
            WebReverseSessionController.maxPageTargetUrlChars) {
      continue;
    }
    final cookieChars =
        rawName.length +
        rawValue.length +
        rawDomain.length +
        rawPath.length +
        rawSameSite.length +
        rawTopLevelSite.length;
    if (cookieChars > remainingChars) break;
    final cookie = <String, Object?>{
      'name': takeText(
        rawName,
        WebReverseSessionController.maxRuleHeaderNameChars,
      ),
      'value': takeText(
        rawValue,
        WebReverseSessionController.maxAccountSnapshotValueChars,
      ),
    };
    final domain = takeText(
      rawDomain,
      WebReverseSessionController.maxBreakpointTextChars,
    );
    final path = takeText(
      rawPath,
      WebReverseSessionController.maxBreakpointTextChars,
    );
    final sameSite = takeText(rawSameSite, 64);
    if (domain.isNotEmpty) cookie['domain'] = domain;
    if (path.isNotEmpty) cookie['path'] = path;
    if (const <String>{'Strict', 'Lax', 'None'}.contains(sameSite)) {
      cookie['sameSite'] = sameSite;
    }
    if (raw['secure'] == true) cookie['secure'] = true;
    if (raw['httpOnly'] == true) cookie['httpOnly'] = true;
    final expires = raw['expires'];
    if (expires is num && expires.isFinite) cookie['expires'] = expires;
    if (rawPartitionKey is Map && rawTopLevelSite.isNotEmpty) {
      final topLevelSite = takeText(
        rawTopLevelSite,
        WebReverseSessionController.maxPageTargetUrlChars,
      );
      if (topLevelSite.isNotEmpty) {
        cookie['partitionKey'] = <String, Object?>{
          'topLevelSite': topLevelSite,
          'hasCrossSiteAncestor':
              rawPartitionKey['hasCrossSiteAncestor'] == true,
        };
      }
    }
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
      if (entry.key.length >
              WebReverseSessionController.maxBreakpointTextChars ||
          entry.value.length >
              WebReverseSessionController.maxAccountSnapshotValueChars) {
        continue;
      }
      final entryChars = entry.key.length + entry.value.length;
      if (entryChars > remainingChars) break;
      remainingChars -= entryChars;
      normalized[entry.key] = entry.value;
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
      if (value is Map) {
        for (final nested in value.values) {
          if (nested is String) total += nested.length;
        }
      }
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
  return (kbps * kBytesPerKiB / 8).round();
}

int _networkKbpsFromThroughput(Object? value) {
  final throughput = value is num ? value : num.tryParse('$value');
  if (throughput == null || throughput <= 0) return 0;
  return (throughput * 8 / kBytesPerKiB).round();
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

  /// 会话 LRU 估算保留的 UTF-16 字符数。
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

const String _kCssSelectorFn = '''
function() {
  const MAX_DEPTH = 256;
  const MAX_SIBLINGS = 4096;
  const MAX_ID_CHARS = 4096;
  function seg(el) {
    if (!el || el.nodeType !== 1) return '';
    if (el.id && String(el.id).length <= MAX_ID_CHARS) return '#' + CSS.escape(el.id);
    let name = el.localName;
    const parent = el.parentNode;
    if (!parent || parent.nodeType !== 1) return name;
    let count = 0;
    let index = 0;
    let scanned = 0;
    for (const child of parent.children) {
      if (++scanned > MAX_SIBLINGS) return '';
      if (child.localName !== name) continue;
      count++;
      if (child === el) index = count;
    }
    if (count <= 1 || index <= 0) return name;
    return name + ':nth-of-type(' + index + ')';
  }
  const parts = [];
  let cur = this;
  while (cur && cur.nodeType === 1 && cur !== document.documentElement && parts.length < MAX_DEPTH) {
    const s = seg(cur);
    if (!s) break;
    parts.unshift(s);
    if (s.startsWith('#')) return parts.join(' > ');
    cur = cur.parentNode;
  }
  if (cur === document.documentElement) parts.unshift('html');
  return parts.join(' > ');
}
''';

const String _kXPathFn = '''
function() {
  const MAX_DEPTH = 256;
  const MAX_SIBLINGS = 4096;
  const MAX_ID_CHARS = 4096;
  function ix(el) {
    let i = 1;
    let sib = el.previousElementSibling;
    let scanned = 0;
    while (sib && scanned++ < MAX_SIBLINGS) {
      if (sib.localName === el.localName) i++;
      sib = sib.previousElementSibling;
    }
    return sib ? 0 : i;
  }
  const parts = [];
  let cur = this;
  while (cur && cur.nodeType === 1 && parts.length < MAX_DEPTH) {
    if (cur.id && String(cur.id).length <= MAX_ID_CHARS && !/["']/.test(cur.id)) {
      parts.unshift('//*[@id="' + cur.id + '"]');
      break;
    }
    const index = ix(cur);
    if (index <= 0) return '';
    parts.unshift(cur.localName + '[' + index + ']');
    cur = cur.parentElement;
  }
  if (parts.length === 0) return '';
  if (parts[0].startsWith('//*[@id=')) return parts.join('/');
  return (cur && cur.nodeType === 1 ? '//' : '/') + parts.join('/');
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
      cookies: compactWebReverseCookies(
        j['cookies'],
        maxEntries: WebReverseSessionController.maxAccountSnapshotCookies,
      ),
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
  if (value is! Map) return const <String, String>{};
  final result = <String, String>{};
  var inspected = 0;
  for (final entry in value.entries) {
    if (inspected++ >=
            WebReverseSessionController.maxAccountSnapshotStorageEntries * 4 ||
        result.length >=
            WebReverseSessionController.maxAccountSnapshotStorageEntries) {
      break;
    }
    if (entry.key is! String || entry.value is! String) continue;
    result[entry.key as String] = entry.value as String;
  }
  return Map<String, String>.unmodifiable(result);
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
    this.contentType = kApplicationJsonUtf8ContentType,
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
          fallback: kApplicationJsonUtf8ContentType,
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
