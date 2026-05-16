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
  /// 默认 30s：macOS 首次起新 profile 时的"first-run + DNS warmup +
  /// start-maximized + 主页加载 + 远端代理"链路在慢机或带 proxy 的网络下
  /// 容易跨过 12s。如果被外部传入更短/更长值（测试场景）则按入参为准。
  Future<WebReverseLaunchResult> launch({
    required String executablePath,
    required WebReverseBrowserKind browserKind,
    required String userDataDir,
    required String startUrl,
    String? proxy,
    Duration handshakeTimeout = const Duration(seconds: 30),
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
      // proxy=direct:// 让 CDP 探测请求绕开系统代理；用户配置的 proxy
      // 只作用于浏览器自身的页面流量，不影响本进程对 127.0.0.1 的探测。
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
    // 收集 stderr 前 32KB，握手失败时把这段打到错误信息里，方便定位
    // "Profile 锁占用 / SUID sandbox / GPU init crash" 等真实根因。
    final stderrBuf = StringBuffer();
    StreamSubscription<String>? errSub;
    try {
      errSub = process.stderr
          .transform(systemEncoding.decoder)
          .listen((chunk) {
        if (stderrBuf.length < 32 * 1024) stderrBuf.write(chunk);
      });
    } catch (_) {}
    // drain stdout 防止管道堵塞导致浏览器进程阻塞写入。
    StreamSubscription<List<int>>? outSub;
    try {
      outSub = process.stdout.listen((_) {});
    } catch (_) {}
    // 进程退出标记：CDP 没起来就早退出（典型场景 user-data-dir 被锁）。
    var processExited = false;
    int? processExitCode;
    unawaited(process.exitCode.then((c) {
      processExited = true;
      processExitCode = c;
    }));
    // 轮询 /json/version 拿 webSocketDebuggerUrl。
    // 退避策略：前 2s 用 150ms 间隔（macOS 上 chrome 通常 800ms 就能起 CDP），
    // 之后切到 400ms 间隔，减少对系统的压力但仍能在 30s 内多次命中。
    final client = httpClientFactory?.call() ?? http.Client();
    final start = DateTime.now();
    final deadline = start.add(handshakeTimeout);
    String? wsUrl;
    String version = browserKind.displayName;
    var lastHttpError = '';
    int attempts = 0;
    try {
      while (DateTime.now().isBefore(deadline)) {
        if (processExited) break;
        attempts++;
        try {
          final resp = await client
              .get(Uri.parse('http://127.0.0.1:$port/json/version'))
              .timeout(const Duration(seconds: 2));
          if (resp.statusCode == 200) {
            final data = jsonDecode(resp.body) as Map<String, dynamic>;
            wsUrl = data['webSocketDebuggerUrl'] as String?;
            version = (data['Browser'] as String?) ?? version;
            if (wsUrl != null && wsUrl.isNotEmpty) break;
          } else {
            lastHttpError = 'HTTP ${resp.statusCode}';
          }
        } catch (e) {
          lastHttpError = '$e';
        }
        final elapsed = DateTime.now().difference(start);
        await Future<void>.delayed(
          elapsed < const Duration(seconds: 2)
              ? const Duration(milliseconds: 150)
              : const Duration(milliseconds: 400),
        );
      }
    } finally {
      if (httpClientFactory == null) client.close();
    }
    if (wsUrl == null || wsUrl.isEmpty) {
      try {
        process.kill();
      } catch (_) {}
      // 确认子进程退出，避免悬挂；最多等 1.5s。
      try {
        await process.exitCode.timeout(const Duration(milliseconds: 1500));
      } catch (_) {}
      await errSub?.cancel();
      await outSub?.cancel();
      final err = stderrBuf.toString().trim();
      final hint = err.isEmpty
          ? ''
          : '\n浏览器 stderr 摘要：\n${err.length > 1024 ? "${err.substring(err.length - 1024)} (truncated)" : err}';
      final exitedHint = processExited
          ? '\n浏览器进程已退出（exitCode=$processExitCode），常见为 user-data-dir 被另一实例锁定。'
          : '';
      throw WebReverseLaunchException(
        WebReverseLaunchFailure.cdpHandshakeFailed,
        'CDP 握手超时（${handshakeTimeout.inSeconds}s，已尝试 $attempts 次；'
        '最后一次探测错误：${lastHttpError.isEmpty ? "(无)" : lastHttpError}）。'
        '常见原因：① 已存在另一个 Chrome 实例占用同 user-data-dir；'
        '② --remote-allow-origins 被企业策略拒绝；'
        '③ 安全软件拦截 127.0.0.1 监听。$exitedHint$hint',
      );
    }
    // 握手成功后把 stderr/stdout 订阅释放，避免长跑时占用句柄。
    await errSub?.cancel();
    await outSub?.cancel();
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
