import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../app/support/silent_log.dart';

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
    required this.eventStream,
  })  : _process = process,
        _server = server;

  /// mitmdump 监听端口（用户客户端把流量代理到这）。
  final int mitmPort;

  /// OpenHand 这边接收 mitm addon 回调的 HTTP 端口。
  final int callbackPort;

  /// 解析后的请求-响应事件流。每条都是 `{kind, ts, ...}` 形式 JSON map。
  final Stream<Map<String, Object?>> eventStream;

  final Process _process;
  final HttpServer _server;
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
        final r = await Process.run(c, const ['--version']);
        if (r.exitCode == 0) return c;
      } catch (_) {}
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
      cbServer = await HttpServer.bind(InternetAddress.loopbackIPv4, callbackPort);
    } catch (error, stack) {
      silentLog('web_reverse_mitmproxy_bridge', 'cb bind', error, stack);
      return null;
    }
    final actualCbPort = cbServer.port;
    final controller = StreamController<Map<String, Object?>>.broadcast();
    cbServer.listen((req) async {
      try {
        if (req.method == 'POST') {
          final raw = await utf8.decoder.bind(req).join();
          for (final line in raw.split('\n')) {
            final t = line.trim();
            if (t.isEmpty) continue;
            try {
              final m = jsonDecode(t);
              if (m is Map) {
                controller.add(Map<String, Object?>.from(m));
              }
            } catch (_) {}
          }
        }
        req.response.statusCode = 204;
        await req.response.close();
      } catch (_) {
        try {
          await req.response.close();
        } catch (_) {}
      }
    });

    final addonPath = await _writeAddon(actualCbPort);
    Process p;
    try {
      p = await Process.start(
        exec,
        <String>[
          '-p', '$mitmPort',
          '-s', addonPath,
          '--quiet',
          '--ssl-insecure',
        ],
      );
    } catch (error, stack) {
      silentLog('web_reverse_mitmproxy_bridge', 'spawn', error, stack);
      await cbServer.close(force: true);
      await controller.close();
      return null;
    }
    // drain stdout / stderr 避免管道阻塞
    p.stdout.listen((_) {});
    p.stderr.listen((_) {});

    // 等 1.5s 看进程没立刻挂；mitmdump 启动慢，再快也会有 tls 初始化。
    await Future<void>.delayed(const Duration(milliseconds: 1500));

    return WebReverseMitmproxyBridge._(
      mitmPort: mitmPort,
      callbackPort: actualCbPort,
      process: p,
      server: cbServer,
      eventStream: controller.stream,
    );
  }

  static Future<String> _writeAddon(int callbackPort) async {
    // 极简 mitmproxy addon：每条 request / response 在 done 时 POST 到回调。
    // body 用 base64 包装防止编码问题；headers 用 list-of-pairs 防 case-fold。
    final addon = '''
import base64
import json
import urllib.request

CALLBACK = "http://127.0.0.1:$callbackPort/"

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
        _send({
            "kind": "request",
            "ts": flow.request.timestamp_start,
            "method": flow.request.method,
            "url": flow.request.pretty_url,
            "headers": list(flow.request.headers.items(multi=True)),
            "body_b64": base64.b64encode(flow.request.raw_content or b"").decode("ascii"),
        })
    except Exception:
        pass

def response(flow):
    try:
        _send({
            "kind": "response",
            "ts": flow.response.timestamp_end,
            "url": flow.request.pretty_url,
            "status": flow.response.status_code,
            "headers": list(flow.response.headers.items(multi=True)),
            "body_b64": base64.b64encode(flow.response.raw_content or b"").decode("ascii"),
        })
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

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      _process.kill();
    } catch (_) {}
    try {
      await _process.exitCode.timeout(const Duration(milliseconds: 1500));
    } catch (_) {}
    try {
      await _server.close(force: true);
    } catch (_) {}
  }
}
