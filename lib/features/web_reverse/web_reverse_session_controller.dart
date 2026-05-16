import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../app/support/silent_log.dart';
import 'web_reverse_browser_kind.dart';
import 'web_reverse_browser_launcher.dart';
import 'web_reverse_cdp_client.dart';
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

  bool _started = false;
  bool _stopped = false;
  String? _errorMessage;
  String? get errorMessage => _errorMessage;
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
      notifyListeners();
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
      case 'Network.requestWillBeSent':
        _onRequestWillBeSent(ev.params);
      case 'Network.responseReceived':
        _onResponseReceived(ev.params);
      case 'Network.loadingFailed':
        _onLoadingFailed(ev.params);
      case 'Network.loadingFinished':
        _onLoadingFinished(ev.params);
      case 'Runtime.consoleAPICalled':
        _onConsoleApi(ev.params);
      case 'Log.entryAdded':
        _onLogEntry(ev.params);
    }
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
    notifyListeners();
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
    notifyListeners();
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
    notifyListeners();
  }

  void _onLoadingFinished(Map<String, Object?> p) {
    final requestId = '${p['requestId']}';
    final entry = _networkByRequestId[requestId];
    if (entry == null) return;
    entry.loadingFinishedAt = DateTime.now();
    final encoded = (p['encodedDataLength'] as num?)?.toInt();
    if (encoded != null) entry.encodedDataLength = encoded;
    _artifacts.recordHarFinished(requestId, DateTime.now());
    notifyListeners();
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
    _appendConsole(type, text);
  }

  void _onLogEntry(Map<String, Object?> p) {
    final entry = p['entry'] as Map?;
    if (entry == null) return;
    final level = '${entry['level'] ?? 'info'}';
    final text = '${entry['text'] ?? ''}';
    _appendConsole(level, text);
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
    notifyListeners();
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    await _safeStop();
    notifyListeners();
  }

  Future<void> _safeStop() async {
    _dock?.stop();
    await _pageEventsSub?.cancel();
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
    notifyListeners();
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
      notifyListeners();
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
      notifyListeners();
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

  @override
  void dispose() {
    unawaited(_safeStop());
    super.dispose();
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

  bool get isError =>
      failed || (statusCode != null && statusCode! >= 400);
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
