import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../app/support/safe_subprocess.dart';
import '../../app/support/silent_log.dart';
import '../../shared/net/bounded_server_bind.dart';
import '../../shared/util/async_concurrency.dart';
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

  static const int _kMaxMitmBodyBytes = 256 * 1024;
  static const int _kMaxCallbackPayloadBytes = 2 * 1024 * 1024;
  static const Duration _kBindTimeout = Duration(seconds: 5);
  static const Duration _kCallbackBodyIdleTimeout = Duration(seconds: 5);
  static const Duration _kCallbackBodyTotalTimeout = Duration(seconds: 20);

  final Process _process;
  final HttpServer _server;
  final StreamController<Map<String, Object?>> _controller;
  final StreamSubscription<HttpRequest> _serverSub;
  final StreamSubscription<List<int>> _stdoutSub;
  final StreamSubscription<List<int>> _stderrSub;
  final String _addonPath;
  bool _closed = false;

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
        silentLog('web_reverse_mitmproxy_bridge', 'detect $c', error, stack);
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
      silentLog('web_reverse_mitmproxy_bridge', 'cb bind', error, stack);
      return null;
    }
    final actualCbPort = cbServer.port;
    final controller = StreamController<Map<String, Object?>>.broadcast();
    final serverSub = cbServer.listen((req) async {
      try {
        if (req.method == 'POST') {
          final raw = await _readCallbackBody(req);
          if (raw == null) {
            req.response.statusCode = 413;
            await req.response.close();
            return;
          }
          for (final line in raw.split('\n')) {
            final t = line.trim();
            if (t.isEmpty) continue;
            try {
              final m = jsonDecode(t);
              if (m is Map && !controller.isClosed) {
                controller.add(stringKeyedMapFromValue(m));
              }
            } catch (error, stack) {
              silentLog(
                'web_reverse_mitmproxy_bridge',
                'decode callback line',
                error,
                stack,
              );
            }
          }
        }
        req.response.statusCode = 204;
        await req.response.close();
      } on TimeoutException catch (error, stack) {
        silentLog(
          'web_reverse_mitmproxy_bridge',
          'callback body timeout',
          error,
          stack,
        );
        req.response.statusCode = HttpStatus.requestTimeout;
        try {
          await req.response.close();
        } catch (closeError, closeStack) {
          silentLog(
            'web_reverse_mitmproxy_bridge',
            'close timed out callback response',
            closeError,
            closeStack,
          );
        }
      } catch (error, stack) {
        silentLog(
          'web_reverse_mitmproxy_bridge',
          'handle callback',
          error,
          stack,
        );
        try {
          await req.response.close();
        } catch (closeError, closeStack) {
          silentLog(
            'web_reverse_mitmproxy_bridge',
            'close callback response',
            closeError,
            closeStack,
          );
        }
      }
    });

    final addonPath = await _writeAddon(actualCbPort);
    Process p;
    try {
      p = await startTrackedProcess(exec, <String>[
        '-p',
        '$mitmPort',
        '-s',
        addonPath,
        '--quiet',
        '--ssl-insecure',
      ]);
    } catch (error, stack) {
      silentLog('web_reverse_mitmproxy_bridge', 'spawn', error, stack);
      await _cancelSubscription(
        serverSub,
        'cancel callback server after spawn',
      );
      await Future.wait<bool>(<Future<bool>>[
        _closeResource(
          () => cbServer.close(force: true),
          'close callback server after spawn',
        ),
        _closeResource(controller.close, 'close event stream after spawn'),
      ]);
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
        'early exit',
        'mitmdump exited with code $earlyExit',
      );
      await Future.wait<bool>(<Future<bool>>[
        _cancelSubscription(stdoutSub, 'cancel stdout after early exit'),
        _cancelSubscription(stderrSub, 'cancel stderr after early exit'),
        _cancelSubscription(serverSub, 'cancel callback after early exit'),
      ]);
      await Future.wait<bool>(<Future<bool>>[
        _closeResource(
          () => cbServer.close(force: true),
          'close callback server after early exit',
        ),
        _closeResource(controller.close, 'close stream after early exit'),
      ]);
      await _deleteAddon(addonPath);
      return null;
    }

    return WebReverseMitmproxyBridge._(
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
    final dir = Directory.systemTemp;
    final f = File(
      '${dir.path}/oh-mitm-addon-${DateTime.now().microsecondsSinceEpoch}.py',
    );
    await f.writeAsString(addon);
    return f.path;
  }

  static Future<void> _deleteAddon(String addonPath) async {
    try {
      await File(addonPath).delete();
    } catch (error, stack) {
      silentLog('web_reverse_mitmproxy_bridge', 'delete addon', error, stack);
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

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await terminateTrackedProcessTree(
      _process,
      gracefulTimeout: const Duration(milliseconds: 1500),
    );
    await Future.wait<bool>(<Future<bool>>[
      _cancelSubscription(_stdoutSub, 'cancel stdout'),
      _cancelSubscription(_stderrSub, 'cancel stderr'),
      _cancelSubscription(_serverSub, 'cancel callback server'),
    ]);
    await Future.wait<bool>(<Future<bool>>[
      _closeResource(() => _server.close(force: true), 'close server'),
      _closeResource(_controller.close, 'close event stream'),
    ]);
    await _deleteAddon(_addonPath);
  }
}
