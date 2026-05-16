import 'dart:async';
import 'dart:convert';
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
  bool _preserveLog = true;
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
      case 'Runtime.consoleAPICalled':
        _onConsoleApi(ev.params);
      case 'Log.entryAdded':
        _onLogEntry(ev.params);
      case 'Security.securityStateChanged':
        _onSecurityStateChanged(ev.params);
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
    notifyListeners();
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
  const log = (step) => {
    try { console.log('__OH_REC__', JSON.stringify(step)); } catch (_) {}
  };
  document.addEventListener('click', (ev) => {
    const t = ev.target;
    log({ type: 'click', selector: t && t.outerHTML ? t.outerHTML.slice(0,80) : '?', ts: Date.now() });
  }, true);
  document.addEventListener('input', (ev) => {
    const t = ev.target;
    log({ type: 'input', value: t && 'value' in t ? String(t.value).slice(0,200) : '', ts: Date.now() });
  }, true);
  window.addEventListener('hashchange', () => log({ type: 'hashchange', url: location.href, ts: Date.now() }));
  window.addEventListener('popstate', () => log({ type: 'popstate', url: location.href, ts: Date.now() }));
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
      notifyListeners();
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
    notifyListeners();
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
    notifyListeners();
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
    notifyListeners();
  }

  void _onFrameNavigated(Map<String, Object?> p) {
    // 仅主 frame 导航才触发 Preserve log 联动；子 frame / iframe 忽略。
    final frame = p['frame'] as Map?;
    if (frame == null) return;
    if (frame['parentId'] != null) return;
    if (!_preserveLog) {
      _networkRequests.clear();
      _networkByRequestId.clear();
      notifyListeners();
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
          notifyListeners();
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

  /// 是否在主 frame 导航时保留旧日志。关闭后下次导航自动清表。
  bool get preserveLog => _preserveLog;
  set preserveLog(bool v) {
    if (_preserveLog == v) return;
    _preserveLog = v;
    notifyListeners();
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
