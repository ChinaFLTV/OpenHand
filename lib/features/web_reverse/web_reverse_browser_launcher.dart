import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../app/support/silent_log.dart';
import 'web_reverse_browser_kind.dart';

/// 启动失败原因。UI 层据此给出可操作的提示。
enum WebReverseLaunchFailure {
  noFreePort,
  spawnFailed,
  cdpHandshakeFailed,
}

/// 启动结果。
class WebReverseLaunchResult {
  const WebReverseLaunchResult({
    required this.process,
    required this.cdpPort,
    required this.userDataDir,
    required this.browserVersion,
    required this.webSocketDebuggerUrl,
  });

  final Process process;
  final int cdpPort;
  final String userDataDir;
  final String browserVersion;
  final String webSocketDebuggerUrl;
}

/// 启动外部 Chrome（或同核浏览器）并完成 CDP 握手。
///
/// 关键参数：
/// - `--remote-debugging-port=<port>`：开放 CDP HTTP/WebSocket 端点。
/// - `--user-data-dir=<dir>`：独立 profile，避免污染用户日常浏览器。
/// - `--no-first-run --no-default-browser-check`：跳过首启向导。
/// - `--disable-features=...`：关掉若干会拦截 CDP 的功能。
class WebReverseBrowserLauncher {
  WebReverseBrowserLauncher({this.httpClientFactory});

  final http.Client Function()? httpClientFactory;

  /// 在 [9222, 9242) 区间挑一个空闲端口。
  ///
  /// 检测策略：
  /// 1. 先尝试 HTTP GET `http://127.0.0.1:<port>/json/version` —— 200 就是别人的 CDP，跳过；
  ///    `Connection refused` 才是真空闲。
  /// 2. 再 ServerSocket.bind 一次确认本进程能 listen，避免操作系统级保留。
  /// 这两步组合能避开"用户已开 Chrome 占 9222"的常见冲突。
  Future<int?> pickFreePort({int start = 9222, int end = 9242}) async {
    final probeClient = httpClientFactory?.call() ?? http.Client();
    final ownsClient = httpClientFactory == null;
    try {
      for (var port = start; port < end; port++) {
        // 1) 是否已被 CDP 占用？
        try {
          final resp = await probeClient
              .get(Uri.parse('http://127.0.0.1:$port/json/version'))
              .timeout(const Duration(milliseconds: 400));
          if (resp.statusCode >= 200 && resp.statusCode < 500) {
            // 端口活着且响应——大概率是别的浏览器实例占用，跳过。
            continue;
          }
        } catch (_) {
          // refused / timeout 都是好事，继续走 bind 探测。
        }
        // 2) 本进程能否 bind？
        try {
          final server =
              await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
          await server.close();
          return port;
        } on SocketException {
          continue;
        }
      }
      return null;
    } finally {
      if (ownsClient) probeClient.close();
    }
  }

  /// 启动浏览器并轮询 `/json/version` 直到拿到 webSocketDebuggerUrl。
  ///
  /// 超时 [handshakeTimeout] 后视为失败。
  Future<WebReverseLaunchResult> launch({
    required String executablePath,
    required WebReverseBrowserKind browserKind,
    required String userDataDir,
    required String startUrl,
    String? proxy,
    Duration handshakeTimeout = const Duration(seconds: 12),
  }) async {
    final port = await pickFreePort();
    if (port == null) {
      throw const WebReverseLaunchException(
        WebReverseLaunchFailure.noFreePort,
        '9222-9242 区间没有空闲端口可用',
      );
    }
    await Directory(userDataDir).create(recursive: true);
    final args = <String>[
      '--remote-debugging-port=$port',
      '--remote-debugging-address=127.0.0.1',
      '--remote-allow-origins=*',
      '--user-data-dir=$userDataDir',
      '--no-first-run',
      '--no-default-browser-check',
      '--disable-features=Translate,InfinitePrefetchHoldback',
      '--disable-translate',
      '--disable-popup-blocking',
      '--start-maximized',
      if (proxy != null && proxy.trim().isNotEmpty)
        '--proxy-server=${proxy.trim()}',
      startUrl,
    ];
    Process process;
    try {
      process = await Process.start(
        executablePath,
        args,
        mode: ProcessStartMode.detachedWithStdio,
      );
    } catch (error, stack) {
      silentLog(
        'web_reverse_browser_launcher',
        'spawn $executablePath',
        error,
        stack,
      );
      throw WebReverseLaunchException(
        WebReverseLaunchFailure.spawnFailed,
        '$executablePath 启动失败：$error',
      );
    }
    // 轮询 /json/version 拿 webSocketDebuggerUrl。
    final client = httpClientFactory?.call() ?? http.Client();
    final deadline = DateTime.now().add(handshakeTimeout);
    String? wsUrl;
    String version = browserKind.displayName;
    try {
      while (DateTime.now().isBefore(deadline)) {
        try {
          final resp = await client
              .get(Uri.parse('http://127.0.0.1:$port/json/version'))
              .timeout(const Duration(seconds: 2));
          if (resp.statusCode == 200) {
            final data = jsonDecode(resp.body) as Map<String, dynamic>;
            wsUrl = data['webSocketDebuggerUrl'] as String?;
            version = (data['Browser'] as String?) ?? version;
            if (wsUrl != null && wsUrl.isNotEmpty) break;
          }
        } catch (_) {
          // 端口尚未起来，下个循环重试。
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    } finally {
      if (httpClientFactory == null) client.close();
    }
    if (wsUrl == null || wsUrl.isEmpty) {
      process.kill();
      throw const WebReverseLaunchException(
        WebReverseLaunchFailure.cdpHandshakeFailed,
        'CDP 握手超时：浏览器进程已起但 /json/version 未返回 webSocketDebuggerUrl',
      );
    }
    return WebReverseLaunchResult(
      process: process,
      cdpPort: port,
      userDataDir: userDataDir,
      browserVersion: version,
      webSocketDebuggerUrl: wsUrl,
    );
  }
}

class WebReverseLaunchException implements Exception {
  const WebReverseLaunchException(this.failure, this.message);

  final WebReverseLaunchFailure failure;
  final String message;

  @override
  String toString() => 'WebReverseLaunchException($failure): $message';
}
