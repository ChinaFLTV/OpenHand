import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/support/silent_log.dart';
import 'web_reverse_browser_kind.dart';
import 'web_reverse_browser_launcher.dart';
import 'web_reverse_cdp_client.dart';
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
    WebReverseBrowserLauncher? launcher,
    WebReverseWindowDock? dock,
  }) : _launcher = launcher ?? WebReverseBrowserLauncher(),
       _dock = dock;

  final WebReverseSessionConfig config;
  final String executablePath;
  final WebReverseBrowserLauncher _launcher;
  WebReverseWindowDock? _dock;

  WebReverseLaunchResult? _launchResult;
  WebReverseCdpClient? _browserCdp;
  WebReverseCdpClient? _pageCdp;
  StreamSubscription<CdpEvent>? _pageEventsSub;
  String? _pageSessionId;

  bool _started = false;
  bool _stopped = false;
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

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
    // 启用相关 domain。
    await cdp.send('Network.enable', sessionId: _pageSessionId);
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
    final entry = CdpNetworkEntry(
      requestId: requestId,
      url: '${request['url'] ?? ''}',
      method: '${request['method'] ?? 'GET'}',
      timestamp: DateTime.now(),
      resourceType: '${p['type'] ?? 'Other'}',
    );
    _networkByRequestId[requestId] = entry;
    _networkRequests.add(entry);
    while (_networkRequests.length > _maxNetworkEntries) {
      final old = _networkRequests.removeAt(0);
      _networkByRequestId.remove(old.requestId);
    }
    notifyListeners();
  }

  void _onResponseReceived(Map<String, Object?> p) {
    final requestId = '${p['requestId']}';
    final response = p['response'] as Map?;
    if (response == null) return;
    final entry = _networkByRequestId[requestId];
    if (entry == null) return;
    entry.statusCode = (response['status'] as num?)?.toInt();
    entry.mimeType = '${response['mimeType'] ?? ''}';
    entry.fromCache = response['fromDiskCache'] == true ||
        response['fromMemoryCache'] == true ||
        response['fromServiceWorker'] == true;
    notifyListeners();
  }

  void _onLoadingFailed(Map<String, Object?> p) {
    final requestId = '${p['requestId']}';
    final entry = _networkByRequestId[requestId];
    if (entry == null) return;
    entry.failed = true;
    entry.errorText = '${p['errorText'] ?? 'failed'}';
    notifyListeners();
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
    _consoleMessages.add(
      CdpConsoleEntry(level: level, text: text, timestamp: DateTime.now()),
    );
    while (_consoleMessages.length > _maxConsoleEntries) {
      _consoleMessages.removeAt(0);
    }
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

/// 单条网络请求的精简快照，仅持有 dashboard 渲染必需的字段。
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

  int? statusCode;
  String? mimeType;
  bool fromCache = false;
  bool failed = false;
  String? errorText;

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
