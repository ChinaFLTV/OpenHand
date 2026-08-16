import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../app/support/safe_subprocess.dart';
import '../../app/support/silent_log.dart';
import '../../shared/net/bounded_server_bind.dart';
import '../../shared/util/async_concurrency.dart';
import '../../shared/util/bounded_file_io.dart';
import '../../shared/util/byte_size_format.dart';
import '../../shared/util/input_value_parsing.dart';

/// mitmproxy 桥接：通过 spawn `mitmdump` 子进程 + 自定义 inline addon，
/// 把所有进出流量以 NDJSON 形式 POST 到本地回调端口；OpenHand 这边起一个
/// `HttpServer` 接收并塞到 [WebReverseSessionController] 的网络缓冲。
///
/// 适用场景：用户想抓 OpenHand 控制不到的流量——App 内嵌 webview、
/// 第三方桌面应用、命令行工具等。CDP 在这种场景下完全够不到。
///
/// 准入条件：
/// 1. `mitmdump` 在 PATH 上可执行；macOS 默认走 Homebrew 装；
/// 2. 用户已安装 mitmproxy 根证书（http://mitm.it 或 ~/.mitmproxy/mitmproxy-ca-cert.pem）
///    并在系统钥匙串中信任；
/// 3. 用户把目标流量代理到 127.0.0.1:8080（或本桥接选定端口）。
///
/// 设计：本桥接只负责"启进程 + 收流量"两件事，不替用户配置代理 / 装证书。
/// 跨平台、零额外 Dart 依赖。
class WebReverseMitmproxyBridge {
  WebReverseMitmproxyBridge._({
    required this.mitmPort,
    required this.callbackPort,
    required Process process,
    required HttpServer server,
    required StreamController<Map<String, Object?>> controller,
    required StreamSubscription<HttpRequest> serverSub,
    required StreamSubscription<List<int>> stdoutSub,
    required StreamSubscription<List<int>> stderrSub,
    required String addonPath,
  }) : _process = process,
       _server = server,
       _controller = controller,
       _serverSub = serverSub,
       _stdoutSub = stdoutSub,
       _stderrSub = stderrSub,
       _addonPath = addonPath,
       eventStream = controller.stream;

  /// mitmdump 监听端口（用户客户端把流量代理到这）。
  final int mitmPort;

  /// OpenHand 这边接收 mitm addon 回调的 HTTP 端口。
  final int callbackPort;

  /// 解析后的请求-响应事件流。每条都是 `{kind, ts, ...}` 形式 JSON map。
  final Stream<Map<String, Object?>> eventStream;

  static const int _kMaxMitmBodyBytes = 256 * kBytesPerKiB;
  static const int _kMaxCallbackPayloadBytes = 2 * kBytesPerMiB;
  static const Duration _kBindTimeout = Duration(seconds: 5);
  static const Duration _kProcessStartTimeout = Duration(seconds: 8);
  static const Duration _kCallbackBodyIdleTimeout = Duration(seconds: 5);
  static const Duration _kCallbackBodyTotalTimeout = Duration(seconds: 20);
  static const Duration _kAddonFileOperationTimeout = Duration(seconds: 5);
  static const int _kMaxConcurrentCallbackRequests = 16;

  final Process _process;
  final HttpServer _server;
  final StreamController<Map<String, Object?>> _controller;
  final StreamSubscription<HttpRequest> _serverSub;
  final StreamSubscription<List<int>> _stdoutSub;
  final StreamSubscription<List<int>> _stderrSub;
  final String _addonPath;
  Future<void>? _closeFuture;

  /// 探测 mitmdump 是否可用，返回可执行路径或 null。
  /// macOS 优先 Homebrew (`/opt/homebrew/bin/mitmdump`、`/usr/local/bin/mitmdump`)，
  /// 兜底走 PATH。
  static Future<String?> detectMitmdump() async {
    final candidates = <String>[
      if (Platform.isMacOS) ...[
        '/opt/homebrew/bin/mitmdump',
        '/usr/local/bin/mitmdump',
      ],
      'mitmdump',
    ];
    for (final c in candidates) {
      try {
        final r = await runTrackedProcessOrFailed(
          c,
          const ['--version'],
          timeout: const Duration(seconds: 5),
          tag: 'mitmproxy.version_probe',
        );
        if (r.exitCode == 0) return c;
      } catch (error, stack) {
        silentLog('web_reverse_mitmproxy_bridge', '探测 $c', error, stack);
      }
    }
    return null;
  }

  /// 启动桥接：先 bind 一个回调 [HttpServer]，再写一个临时 addon 文件，
  /// 然后 spawn `mitmdump -p mitmPort -s addon.py`。失败返回 null。
  static Future<WebReverseMitmproxyBridge?> start({
    int mitmPort = 8080,
    int callbackPort = 0,
    String? executable,
  }) async {
    final exec = executable ?? await detectMitmdump();
    if (exec == null) return null;

    HttpServer cbServer;
    try {
      cbServer = await bindHttpServerBounded(
        InternetAddress.loopbackIPv4,
        callbackPort,
        timeout: _kBindTimeout,
      );
    } catch (error, stack) {
      silentLog('web_reverse_mitmproxy_bridge', '绑定回调服务', error, stack);
      return null;
    }
    final actualCbPort = cbServer.port;
    final controller = StreamController<Map<String, Object?>>.broadcast();
    var activeCallbackRequests = 0;
    final serverSub = cbServer.listen(
      (req) async {
        if (activeCallbackRequests >= _kMaxConcurrentCallbackRequests) {
          req.response.statusCode = HttpStatus.tooManyRequests;
          await _closeCallbackResponse(req.response, '关闭过载回调响应');
          return;
        }
        activeCallbackRequests += 1;
        try {
          await _handleCallbackRequest(req, controller);
        } finally {
          activeCallbackRequests -= 1;
        }
      },
      onError: (Object error, StackTrace stack) {
        silentLog('web_reverse_mitmproxy_bridge', '监听回调请求', error, stack);
      },
    );

    late final String addonPath;
    try {
      addonPath = await _writeAddon(actualCbPort);
    } catch (error, stack) {
      silentLog(
        'web_reverse_mitmproxy_bridge',
        '写入 mitmproxy 插件',
        error,
        stack,
      );
      await _closeCallbackResources(
        serverSubscription: serverSub,
        server: cbServer,
        controller: controller,
        phase: '插件写入失败后',
      );
      return null;
    }
    Process p;
    try {
      p = await startTrackedProcessBounded(
        exec,
        <String>[
          '-p',
          '$mitmPort',
          '-s',
          addonPath,
          '--quiet',
          '--ssl-insecure',
        ],
        timeout: _kProcessStartTimeout,
        tag: 'web_reverse_mitmproxy_bridge',
        startInNewProcessGroup: true,
      );
    } catch (error, stack) {
      silentLog('web_reverse_mitmproxy_bridge', '启动 mitmdump', error, stack);
      await _closeCallbackResources(
        serverSubscription: serverSub,
        server: cbServer,
        controller: controller,
        phase: '进程启动失败后',
      );
      await _deleteAddon(addonPath);
      return null;
    }
    // drain stdout / stderr 避免管道阻塞
    final stdoutSub = p.stdout.listen((_) {});
    final stderrSub = p.stderr.listen((_) {});

    // 等 1.5s 看进程没立刻挂；mitmdump 启动慢，再快也会有 tls 初始化。
    final earlyExit = await Future.any<int?>([
      p.exitCode,
      Future<int?>.delayed(const Duration(milliseconds: 1500), () => null),
    ]);
    if (earlyExit != null) {
      silentLog(
        'web_reverse_mitmproxy_bridge',
        'mitmdump 提前退出',
        'mitmdump 已退出，退出码：$earlyExit',
      );
      await Future.wait<bool>(<Future<bool>>[
        _cancelSubscription(stdoutSub, '提前退出后取消标准输出订阅'),
        _cancelSubscription(stderrSub, '提前退出后取消标准错误订阅'),
      ]);
      await _closeCallbackResources(
        serverSubscription: serverSub,
        server: cbServer,
        controller: controller,
        phase: '进程提前退出后',
      );
      await _deleteAddon(addonPath);
      return null;
    }

    final bridge = WebReverseMitmproxyBridge._(
      mitmPort: mitmPort,
      callbackPort: actualCbPort,
      process: p,
      server: cbServer,
      controller: controller,
      serverSub: serverSub,
      stdoutSub: stdoutSub,
      stderrSub: stderrSub,
      addonPath: addonPath,
    );
    unawaited(bridge._closeAfterProcessExit());
    return bridge;
  }

  static Future<void> _handleCallbackRequest(
    HttpRequest request,
    StreamController<Map<String, Object?>> controller,
  ) async {
    try {
      if (request.method == 'POST') {
        final raw = await _readCallbackBody(request);
        if (raw == null) {
          request.response.statusCode = HttpStatus.requestEntityTooLarge;
          return;
        }
        for (final line in raw.split('\n')) {
          final text = line.trim();
          if (text.isEmpty) continue;
          try {
            final decoded = jsonDecode(text);
            if (decoded is Map && !controller.isClosed) {
              controller.add(stringKeyedMapFromValue(decoded));
            }
          } catch (error, stack) {
            silentLog('web_reverse_mitmproxy_bridge', '解码回调数据行', error, stack);
          }
        }
      }
      request.response.statusCode = HttpStatus.noContent;
    } on TimeoutException catch (error, stack) {
      silentLog('web_reverse_mitmproxy_bridge', '读取回调请求体超时', error, stack);
      request.response.statusCode = HttpStatus.requestTimeout;
    } catch (error, stack) {
      silentLog('web_reverse_mitmproxy_bridge', '处理回调请求', error, stack);
      request.response.statusCode = HttpStatus.internalServerError;
    } finally {
      await _closeCallbackResponse(request.response, '关闭回调响应');
    }
  }

  static Future<void> _closeCallbackResponse(
    HttpResponse response,
    String action,
  ) async {
    await runAsyncCleanupBounded(
      response.close,
      onError: (error, stack) =>
          silentLog('web_reverse_mitmproxy_bridge', action, error, stack),
    );
  }

  static Future<String?> _readCallbackBody(HttpRequest req) async {
    final builder = BytesBuilder(copy: false);
    var total = 0;
    final deadline = MonotonicDeadline(_kCallbackBodyTotalTimeout);
    try {
      await for (final chunk in req.timeout(_kCallbackBodyIdleTimeout)) {
        if (deadline.isExpired) {
          throw TimeoutException('mitmproxy 回调请求体超过总时限。');
        }
        total += chunk.length;
        if (total > _kMaxCallbackPayloadBytes) {
          return null;
        }
        builder.add(chunk);
      }
      return utf8.decode(builder.takeBytes(), allowMalformed: true);
    } finally {
      deadline.stop();
    }
  }

  static Future<String> _writeAddon(int callbackPort) async {
    // 极简 mitmproxy addon：每条 request / response 在 done 时 POST 到回调。
    // body 用 base64 包装防止编码问题；headers 用 list-of-pairs 防 case-fold。
    final addon =
        '''
import base64
import json
import urllib.request

CALLBACK = "http://127.0.0.1:$callbackPort/"
MAX_BODY_BYTES = $_kMaxMitmBodyBytes

def _body(raw):
    raw = raw or b""
    clipped = raw[:MAX_BODY_BYTES]
    return {
        "body_b64": base64.b64encode(clipped).decode("ascii"),
        "body_size": len(raw),
        "body_truncated": len(raw) > MAX_BODY_BYTES,
    }

def _send(payload):
    try:
        data = (json.dumps(payload, ensure_ascii=False) + "\\n").encode("utf-8")
        urllib.request.urlopen(
            urllib.request.Request(CALLBACK, data=data, method="POST"),
            timeout=2,
        ).read()
    except Exception:
        pass

def request(flow):
    try:
        payload = {
            "kind": "request",
            "ts": flow.request.timestamp_start,
            "method": flow.request.method,
            "url": flow.request.pretty_url,
            "headers": list(flow.request.headers.items(multi=True)),
        }
        payload.update(_body(flow.request.raw_content))
        _send(payload)
    except Exception:
        pass

def response(flow):
    try:
        payload = {
            "kind": "response",
            "ts": flow.response.timestamp_end,
            "url": flow.request.pretty_url,
            "status": flow.response.status_code,
            "headers": list(flow.response.headers.items(multi=True)),
        }
        payload.update(_body(flow.response.raw_content))
        _send(payload)
    except Exception:
        pass
''';
    final f = File(
      p.join(
        Directory.systemTemp.path,
        'oh-mitm-addon-$pid-${DateTime.now().microsecondsSinceEpoch}.py',
      ),
    );
    await writeTemporaryFileTextBounded(
      f,
      addon,
      timeout: _kAddonFileOperationTimeout,
      onSecondaryError: (error, stack) => silentLog(
        'web_reverse_mitmproxy_bridge',
        '清理 mitmproxy 插件文件',
        error,
        stack,
      ),
    );
    return f.path;
  }

  static Future<void> _deleteAddon(String addonPath) async {
    try {
      final file = File(addonPath);
      if (await file.exists().timeout(_kAddonFileOperationTimeout)) {
        await file.delete().timeout(_kAddonFileOperationTimeout);
      }
    } catch (error, stack) {
      silentLog(
        'web_reverse_mitmproxy_bridge',
        '删除 mitmproxy 插件',
        error,
        stack,
      );
    }
  }

  static Future<bool> _cancelSubscription<T>(
    StreamSubscription<T>? subscription,
    String where,
  ) {
    return cancelStreamSubscriptionBounded<T>(
      subscription,
      onError: (error, stack) =>
          silentLog('web_reverse_mitmproxy_bridge', where, error, stack),
    );
  }

  static Future<bool> _closeResource(
    FutureOr<void> Function() close,
    String where,
  ) {
    return runAsyncCleanupBounded(
      close,
      onError: (error, stack) =>
          silentLog('web_reverse_mitmproxy_bridge', where, error, stack),
    );
  }

  static Future<void> _closeCallbackResources({
    required StreamSubscription<HttpRequest> serverSubscription,
    required HttpServer server,
    required StreamController<Map<String, Object?>> controller,
    required String phase,
  }) async {
    await _cancelSubscription(serverSubscription, '$phase取消回调订阅');
    await Future.wait<bool>(<Future<bool>>[
      _closeResource(() => server.close(force: true), '$phase关闭回调服务器'),
      _closeResource(controller.close, '$phase关闭事件流'),
    ]);
  }

  Future<void> close() => _closeFuture ??= _performClose();

  Future<void> _closeAfterProcessExit() async {
    try {
      await _process.exitCode;
    } catch (error, stack) {
      silentLog('web_reverse_mitmproxy_bridge', '等待 mitmdump 退出', error, stack);
    }
    await close();
  }

  Future<void> _performClose() async {
    await _closeResource(
      () => terminateTrackedProcessTree(
        _process,
        gracefulTimeout: const Duration(milliseconds: 1500),
      ),
      '终止 mitmdump 进程',
    );
    await Future.wait<bool>(<Future<bool>>[
      _cancelSubscription(_stdoutSub, '取消标准输出订阅'),
      _cancelSubscription(_stderrSub, '取消标准错误订阅'),
    ]);
    await _closeCallbackResources(
      serverSubscription: _serverSub,
      server: _server,
      controller: _controller,
      phase: '',
    );
    await _deleteAddon(_addonPath);
  }
}
