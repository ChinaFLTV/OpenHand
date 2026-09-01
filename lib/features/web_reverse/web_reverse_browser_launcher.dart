import 'dart:async';
import 'dart:io';

import '../../app/support/safe_subprocess.dart';
import '../../app/support/silent_log.dart';
import '../../shared/net/bounded_http_request.dart';
import '../../shared/net/bounded_server_bind.dart';
import '../../shared/net/http_response_utils.dart';
import '../../shared/util/async_concurrency.dart';
import '../../shared/util/bounded_directory_io.dart';
import '../../shared/util/bounded_log_buffer.dart';
import '../../shared/util/byte_size_format.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/text_clip.dart';
import 'web_reverse_browser_kind.dart';
import 'web_reverse_cdp_http.dart';
import 'web_reverse_pure_helpers.dart';

/// 启动失败原因。UI 层据此给出可操作的提示。
enum WebReverseLaunchFailure { noFreePort, spawnFailed, cdpHandshakeFailed }

/// 启动结果。
class WebReverseLaunchResult {
  WebReverseLaunchResult({
    required this.process,
    required this.cdpPort,
    required this.userDataDir,
    required this.browserVersion,
    required this.webSocketDebuggerUrl,
    required this._stderrSubscription,
    required this._stdoutSubscription,
  });

  final Process process;
  final int cdpPort;
  final String userDataDir;
  final String browserVersion;
  final String webSocketDebuggerUrl;
  final StreamSubscription<String>? _stderrSubscription;
  final StreamSubscription<List<int>>? _stdoutSubscription;
  Future<void>? _outputCleanupFuture;

  Future<void> closeOutputStreams() =>
      _outputCleanupFuture ??= _cancelBrowserOutputSubscriptions(
        _stderrSubscription,
        _stdoutSubscription,
      );
}

/// 启动外部 Chrome（或同核浏览器）并完成 CDP 握手。
///
/// 关键参数：
/// - `--remote-debugging-port=<port>`：开放 CDP HTTP/WebSocket 端点。
/// - `--user-data-dir=<dir>`：独立 profile，避免污染用户日常浏览器。
/// - `--no-first-run --no-default-browser-check`：跳过首启向导。
/// - `--disable-features=...`：关掉若干会拦截 CDP 的功能。
class WebReverseBrowserLauncher {
  static const int _firstCdpPort = 9222;
  static const int _lastCdpPortExclusive = 9322;
  static const Duration _handshakeTimeout = Duration(seconds: 30);
  static const Duration _handshakeProbeTimeout = Duration(seconds: 2);
  static const Duration _portSelectionTimeout = Duration(seconds: 10);
  static const Duration _portProbeTimeout = Duration(milliseconds: 400);
  static const Duration _profileDirectoryTimeout = Duration(seconds: 5);
  static const Duration _processStartTimeout = Duration(seconds: 10);
  static const Duration _processFailureTerminateGrace = Duration(
    milliseconds: 500,
  );
  static const Duration _startupOutputDrainTimeout = Duration(
    milliseconds: 1500,
  );
  static const Duration _streamCleanupTimeout = Duration(seconds: 1);
  static const int _maxHandshakeResponseBytes = 64 * kBytesPerKiB;
  static const int _maxStartupStderrCharacters = 32 * kBytesPerKiB;
  static const int _maxStartupErrorSummaryCharacters = kBytesPerKiB;

  /// 在 [9222, 9322) 区间挑一个空闲端口，支持多会话并发。
  ///
  /// 检测策略：
  /// 1. 先尝试 HTTP GET `http://127.0.0.1:<port>/json/version` —— 200 就是别人的 CDP，跳过；
  ///    `Connection refused` 才是真空闲。
  /// 2. 再 ServerSocket.bind 一次确认本进程能 listen，避免操作系统级保留。
  /// 这两步组合能避开"用户已开 Chrome 占 9222"的常见冲突。
  Future<int?> _pickFreePort() async {
    final deadline = MonotonicDeadline(
      _portSelectionTimeout,
      timeoutMessage: '选择浏览器调试端口超过总时限。',
    );
    try {
      for (var port = _firstCdpPort; port < _lastCdpPortExclusive; port++) {
        final remaining = deadline.remainingOrNull();
        if (remaining == null) return null;
        final probeTimeout = deadline.limit(_portProbeTimeout);
        // 1) 是否已被 CDP 占用？每次探测独立持有客户端，超时后强制释放连接。
        try {
          final response = await _requestCdpEndpoint(
            webReverseCdpHttpUri(port, webReverseCdpJsonVersionPath),
            timeout: probeTimeout,
            readBody: false,
          );
          if (response.statusCode >= 200 && response.statusCode < 500) {
            continue;
          }
        } catch (_) {
          // 拒绝连接或超时后继续执行本地绑定确认。
        }
        // 2) 本进程能否 bind？
        try {
          final server = await bindServerSocketBounded(
            InternetAddress.loopbackIPv4,
            port,
            timeout: deadline.limit(_portProbeTimeout),
          );
          await server.close();
          return port;
        } on SocketException catch (_) {
          continue;
        } on TimeoutException catch (_) {
          continue;
        }
      }
      return null;
    } finally {
      deadline.stop();
    }
  }

  /// 启动浏览器并轮询 `/json/version` 直到拿到 webSocketDebuggerUrl。
  ///
  /// 超时 [_handshakeTimeout] 后视为失败。
  /// 默认 30s：macOS 首次起新 profile 时的"first-run + DNS warmup +
  /// start-maximized + 主页加载 + 远端代理"链路在慢机或带 proxy 的网络下
  /// 容易跨过 12s。
  Future<WebReverseLaunchResult> launch({
    required String executablePath,
    required WebReverseBrowserKind browserKind,
    required String userDataDir,
    required String startUrl,
    String? proxy,
  }) async {
    final port = await _pickFreePort();
    if (port == null) {
      throw const WebReverseLaunchException(
        WebReverseLaunchFailure.noFreePort,
        '9222-9322 区间没有空闲端口可用',
      );
    }
    final normalizedUserDataDir = nullIfBlank(userDataDir);
    if (normalizedUserDataDir == null) {
      throw const WebReverseLaunchException(
        WebReverseLaunchFailure.spawnFailed,
        'user-data-dir 为空，无法启动浏览器',
      );
    }
    final proxyArg = nullIfBlank(proxy);
    await createDirectoryBounded(
      Directory(normalizedUserDataDir),
      timeout: _profileDirectoryTimeout,
    );
    final args = <String>[
      // CDP 关键参数务必排在最前，确保 Chrome 解析到这些
      // 参数前不会因为别的初始化阶段卡住（部分 Chrome 版本对参数顺序
      // 敏感）。`--remote-debugging-pipe` 不用，因为我们要用 HTTP 探测。
      '--remote-debugging-port=$port',
      '--remote-debugging-address=127.0.0.1',
      '--remote-allow-origins=*',
      '--user-data-dir=$normalizedUserDataDir',
      '--no-first-run',
      '--no-default-browser-check',
      '--no-service-autorun',
      // Translate / 后台预取会导致 CDP 启动期被推迟；同时关掉 PromoUI、
      // FedCM 等首次启动 onboarding 流程，加速握手。
      '--disable-features=Translate,InfinitePrefetchHoldback,'
          'OptimizationGuideModelDownloading,GlobalMediaControls,'
          'FedCm,SegmentationPlatform,PrivacySandboxSettings4',
      '--disable-translate',
      '--disable-popup-blocking',
      // --no-default-browser-check 已涵盖；--password-store=basic 防 keychain
      // 弹窗阻塞主线程。
      '--password-store=basic',
      '--use-mock-keychain',
      // 防止 Chrome 因 metrics 上报卡握手期；--disable-component-update 让
      // 组件检查不抢占启动资源。
      '--disable-background-networking',
      '--disable-component-update',
      '--metrics-recording-only',
      '--no-pings',
      // proxy=direct:// 让 CDP 探测请求绕开系统代理；用户配置的 proxy
      // 只作用于浏览器自身的页面流量，不影响本进程对 127.0.0.1 的探测。
      if (proxyArg != null) '--proxy-server=$proxyArg',
      startUrl,
    ];
    Process process;
    try {
      process = await startTrackedProcessBounded(
        executablePath,
        args,
        timeout: _processStartTimeout,
        tag: 'web_reverse_browser_launcher',
        startInNewProcessGroup: true,
      );
    } catch (error, stack) {
      silentLog(
        'web_reverse_browser_launcher',
        '启动浏览器：$executablePath',
        error,
        stack,
      );
      throw WebReverseLaunchException(
        WebReverseLaunchFailure.spawnFailed,
        '$executablePath 启动失败：$error',
      );
    }
    // 保留 stderr 最新 32KB，握手失败时把这段打到错误信息里，方便定位
    // "Profile 锁占用 / SUID sandbox / GPU init crash" 等真实根因。
    // 管道关闭可在握手阶段快速识别浏览器提前退出；进程本身由
    // safe_subprocess 登记并尽量放入独立进程组，应用退出时可整树终止。
    final stderrBuffer = BoundedLogBuffer(
      maxCharacters: _maxStartupStderrCharacters,
    );
    var processExited = false;
    unawaited(
      process.exitCode.then<void>(
        (_) => processExited = true,
        onError: (Object error, StackTrace stack) {
          processExited = true;
          silentLog('web_reverse_browser_launcher', '监听浏览器退出状态', error, stack);
        },
      ),
    );
    StreamSubscription<String>? errSub;
    try {
      errSub = process.stderr
          .transform(systemEncoding.decoder)
          .listen(
            stderrBuffer.add,
            onError: (Object error, StackTrace stack) {
              silentLog(
                'web_reverse_browser_launcher',
                '读取浏览器标准错误流',
                error,
                stack,
              );
            },
          );
    } catch (error, stack) {
      silentLog('web_reverse_browser_launcher', '订阅浏览器标准错误流', error, stack);
    }
    // drain stdout 防止管道堵塞导致浏览器进程阻塞写入。
    StreamSubscription<List<int>>? outSub;
    try {
      outSub = process.stdout.listen(
        (_) {},
        onError: (Object error, StackTrace stack) {
          silentLog('web_reverse_browser_launcher', '读取浏览器标准输出流', error, stack);
        },
      );
    } catch (error, stack) {
      silentLog('web_reverse_browser_launcher', '订阅浏览器标准输出流', error, stack);
    }
    // 轮询 /json/version 拿 webSocketDebuggerUrl。
    // 退避策略：前 2s 用 150ms 间隔（macOS 上 chrome 通常 800ms 就能起 CDP），
    // 之后切到 400ms 间隔，减少对系统的压力但仍能在 30s 内多次命中。
    final handshakeDeadline = MonotonicDeadline(
      _handshakeTimeout,
      timeoutMessage: 'CDP 握手超过总时限。',
    );
    String? wsUrl;
    String version = browserKind.displayName;
    var lastHttpError = '';
    int attempts = 0;
    while (!handshakeDeadline.isExpired) {
      if (processExited) break;
      attempts++;
      try {
        final requestBudget = handshakeDeadline.remaining();
        final resp = await _requestCdpEndpoint(
          webReverseCdpHttpUri(port, webReverseCdpJsonVersionPath),
          timeout: requestBudget < _handshakeProbeTimeout
              ? requestBudget
              : _handshakeProbeTimeout,
        );
        if (resp.statusCode == 200) {
          final data = decodeStringKeyedJsonMap(resp.body);
          if (data == null) {
            lastHttpError = '/json/version 响应格式无效';
          } else {
            final nextWsUrl = data['webSocketDebuggerUrl'];
            final nextVersion = data['Browser'];
            wsUrl = nextWsUrl is String ? nullIfBlank(nextWsUrl) : null;
            final normalizedVersion = nextVersion is String
                ? nullIfBlank(nextVersion)
                : null;
            if (normalizedVersion != null) {
              version = normalizedVersion;
            }
            if (wsUrl != null) break;
          }
        } else {
          lastHttpError = 'HTTP ${resp.statusCode}';
        }
      } catch (e) {
        lastHttpError = '$e';
      }
      final remaining = handshakeDeadline.remainingOrNull();
      if (remaining == null) break;
      final retryDelay = handshakeDeadline.elapsed < const Duration(seconds: 2)
          ? const Duration(milliseconds: 150)
          : const Duration(milliseconds: 400);
      await Future<void>.delayed(
        remaining < retryDelay ? remaining : retryDelay,
      );
    }
    handshakeDeadline.stop();
    if (wsUrl == null) {
      await runAsyncCleanupBounded(
        () => terminateTrackedProcessTree(
          process,
          gracefulTimeout: _processFailureTerminateGrace,
        ),
        onError: (error, stack) => silentLog(
          'web_reverse_browser_launcher',
          '终止启动失败的浏览器',
          error,
          stack,
        ),
      );
      // 确认子进程输出管道结束，避免悬挂，最多等待 1.5 秒。
      final outputDone = <Future<void>>[
        if (errSub != null) errSub.asFuture<void>(),
        if (outSub != null) outSub.asFuture<void>(),
      ];
      if (outputDone.isNotEmpty) {
        try {
          await Future.any<void>(
            outputDone,
          ).timeout(_startupOutputDrainTimeout);
        } catch (error, stack) {
          silentLog(
            'web_reverse_browser_launcher',
            '等待启动失败的浏览器退出',
            error,
            stack,
          );
        }
      }
      await _cancelBrowserOutputSubscriptions(errSub, outSub);
      final err = stderrBuffer.snapshot().join().trim();
      final errSummary = err.length > _maxStartupErrorSummaryCharacters
          ? '${err.substring(safeUtf16SuffixStart(err, err.length - _maxStartupErrorSummaryCharacters))}（已截断）'
          : err;
      final hint = err.isEmpty ? '' : '\n浏览器 stderr 摘要：\n$errSummary';
      final exitedHint = processExited
          ? '\n浏览器进程已提前退出，常见原因是 user-data-dir 被另一实例锁定。'
          : '';
      throw WebReverseLaunchException(
        WebReverseLaunchFailure.cdpHandshakeFailed,
        'CDP 握手超时（${_handshakeTimeout.inSeconds}s，已尝试 $attempts 次；'
        '最后一次探测错误：${lastHttpError.isEmpty ? "(无)" : lastHttpError}）。'
        '常见原因：① 已存在另一个 Chrome 实例占用同 user-data-dir；'
        '② --remote-allow-origins 被企业策略拒绝；'
        '③ 安全软件拦截 127.0.0.1 监听。$exitedHint$hint',
      );
    }
    // 浏览器运行期间持续排空输出，避免子进程写满管道后阻塞。
    return WebReverseLaunchResult(
      process: process,
      cdpPort: port,
      userDataDir: normalizedUserDataDir,
      browserVersion: version,
      webSocketDebuggerUrl: wsUrl,
      stderrSubscription: errSub,
      stdoutSubscription: outSub,
    );
  }

  Future<({int statusCode, String body})> _requestCdpEndpoint(
    Uri uri, {
    required Duration timeout,
    bool readBody = true,
  }) async {
    final deadline = MonotonicDeadline(
      timeout,
      timeoutMessage: 'CDP HTTP 探测超时。',
    );

    try {
      return await withWebReverseCdpHttpClient<({int statusCode, String body})>(
        connectionTimeout: timeout,
        idleTimeout: timeout,
        action: (client) async {
          final request = await openHttpClientRequestBounded(
            () => client.getUrl(uri),
            timeout: deadline.remaining(),
            timeoutMessage: 'Web 调试地址请求打开超时。',
          );
          request
            ..followRedirects = false
            ..persistentConnection = false;
          final response = await closeHttpClientRequestBounded(
            request,
            timeout: deadline.remaining(),
            timeoutMessage: 'Web 调试地址响应头获取超时。',
          );
          if (!readBody) {
            return (statusCode: response.statusCode, body: '');
          }
          final body = await readBoundedHttpResponseText(
            response,
            maxBytes: _maxHandshakeResponseBytes,
            idleTimeout: deadline.remaining(),
            totalTimeout: deadline.remaining(),
            allowMalformed: true,
          );
          return (statusCode: response.statusCode, body: body);
        },
      );
    } finally {
      deadline.stop();
    }
  }
}

Future<void> _cancelBrowserOutputSubscriptions(
  StreamSubscription<String>? stderrSubscription,
  StreamSubscription<List<int>>? stdoutSubscription,
) async {
  await Future.wait<bool>(<Future<bool>>[
    cancelStreamSubscriptionBounded<String>(
      stderrSubscription,
      timeout: WebReverseBrowserLauncher._streamCleanupTimeout,
      onError: (error, stack) => silentLog(
        'web_reverse_browser_launcher',
        '取消浏览器标准错误流订阅',
        error,
        stack,
      ),
    ),
    cancelStreamSubscriptionBounded<List<int>>(
      stdoutSubscription,
      timeout: WebReverseBrowserLauncher._streamCleanupTimeout,
      onError: (error, stack) => silentLog(
        'web_reverse_browser_launcher',
        '取消浏览器标准输出流订阅',
        error,
        stack,
      ),
    ),
  ]);
}

class WebReverseLaunchException implements Exception {
  const WebReverseLaunchException(this.failure, this.message);

  final WebReverseLaunchFailure failure;
  final String message;

  @override
  String toString() => 'WebReverseLaunchException($failure): $message';
}
