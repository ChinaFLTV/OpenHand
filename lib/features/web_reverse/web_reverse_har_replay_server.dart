import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../app/support/silent_log.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/text_clip.dart';

/// 把 HAR 1.2 文档作为只读 mock server 跑起来，监听 127.0.0.1:N，
/// 收到 GET 请求时按 URL 全等匹配 HAR 条目并回放 status / headers / body。
///
/// 使用场景：复现脚本运行时不联网，直接打到本机 mock，得到与浏览器同样
/// 的字节流，避免远端站点反爬 / 限流影响调试节奏。
///
/// 仅支持 GET（HAR 里 POST 的 body 不一定能完整恢复，先不冒险）。
/// 查询参数会归一化排序后参与 key 计算，避免 a=1&b=2 与 b=2&a=1 误判。
class WebReverseHarReplayServer {
  WebReverseHarReplayServer._({
    required this.port,
    required HttpServer server,
    required this.entryCount,
  }) : _server = server;

  final int port;
  final int entryCount;
  final HttpServer _server;

  static const int _maxReplayEntries = 1000;
  static const int _maxReplayHeaders = 128;
  static const int _maxReplayHeaderValueChars = 8192;
  static const int _maxReplayBodyChars = 5 * 1024 * 1024;

  /// 从 HAR 字节启动一个本地 mock。失败返回 null。
  /// [requestedPort] 为 0 时让 OS 随机分配。
  static Future<WebReverseHarReplayServer?> start({
    required List<int> harBytes,
    int requestedPort = 0,
  }) async {
    Map<String, _HarHit> map;
    try {
      final raw = utf8.decode(harBytes);
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final har = stringKeyedMapFromValue(decoded);
      final log = stringKeyedMapFromValue(har['log']);
      final entries = stringKeyedMapListFromValue(log['entries']);
      map = <String, _HarHit>{};
      var accepted = 0;
      for (final entry in entries) {
        if (accepted >= _maxReplayEntries) break;
        final req = stringKeyedMapFromValue(entry['request']);
        final res = stringKeyedMapFromValue(entry['response']);
        if (req.isEmpty || res.isEmpty) continue;
        final method = stringFromValue(req['method'], fallback: 'GET');
        if (method.toUpperCase() != 'GET') continue;
        final url = stringFromValue(req['url']);
        if (url.isEmpty) continue;
        final fullKey = _normalizeKey(url);
        final pathKey = _pathKey(url);
        final headers = <String, String>{};
        for (final h in stringKeyedMapListFromValue(
          res['headers'],
        ).take(_maxReplayHeaders)) {
          final name = stringFromValue(h['name']);
          if (name.isEmpty) continue;
          headers[name] = clipText(
            stringFromValue(h['value']),
            _maxReplayHeaderValueChars,
          );
        }
        final content = stringKeyedMapFromValue(res['content']);
        final bodyRaw = content['text']?.toString() ?? '';
        final isB64 =
            stringFromValue(content['encoding']).toLowerCase() == 'base64';
        final body = _clipReplayBody(bodyRaw, isBase64: isB64);
        final hit = _HarHit(
          status: clampedIntFromValue(
            res['status'],
            fallback: 200,
            min: 100,
            max: 599,
          ),
          headers: headers,
          body: body,
          isBase64: isB64,
          mime: stringFromValue(
            content['mimeType'],
            fallback: 'application/octet-stream',
          ),
          truncated: body.length < bodyRaw.length,
        );
        // 同时按 full URL 与 path-only 两种 key 存：远端 origin 的 mock 走 full，
        // 本地复现脚本走 127.0.0.1:N/<path> 走 path-only。
        map[fullKey] = hit;
        if (pathKey.isNotEmpty) map[pathKey] = hit;
        accepted++;
      }
    } catch (error, stack) {
      silentLog('web_reverse_har_replay_server', 'parse', error, stack);
      return null;
    }
    HttpServer server;
    try {
      server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        requestedPort,
      );
    } catch (error, stack) {
      silentLog('web_reverse_har_replay_server', 'bind', error, stack);
      return null;
    }
    final boundPort = server.port;
    final instance = WebReverseHarReplayServer._(
      port: boundPort,
      server: server,
      entryCount: map.length,
    );
    server.listen((req) async {
      final key = _normalizeKey(req.requestedUri.toString());
      final hit = map[key];
      // 兜底：去掉 host 部分用 path+query 再查一次。
      final fallbackKey =
          '${req.requestedUri.path}?${_sortedQuery(req.requestedUri.queryParameters)}';
      final byPath = hit ?? map[fallbackKey];
      if (byPath == null) {
        req.response.statusCode = 404;
        req.response.headers.contentType = ContentType(
          'application',
          'json',
          charset: 'utf-8',
        );
        req.response.write(jsonEncode({'error': 'no har entry', 'key': key}));
        await req.response.close();
        return;
      }
      req.response.statusCode = byPath.status;
      byPath.headers.forEach((k, v) {
        // 跳过 hop-by-hop headers。
        final lk = k.toLowerCase();
        if (lk == 'transfer-encoding' ||
            lk == 'content-length' ||
            lk == 'connection') {
          return;
        }
        try {
          req.response.headers.set(k, v);
        } catch (error, stack) {
          silentLog(
            'web_reverse_har_replay_server',
            'set response header $k',
            error,
            stack,
          );
        }
      });
      if (byPath.truncated) {
        req.response.headers.set('x-openhand-har-body-truncated', '1');
      }
      try {
        if (byPath.isBase64) {
          req.response.add(base64Decode(byPath.body));
        } else {
          req.response.write(byPath.body);
        }
      } catch (error, stack) {
        silentLog(
          'web_reverse_har_replay_server',
          'write response body',
          error,
          stack,
        );
      }
      await req.response.close();
    });
    return instance;
  }

  Future<void> close() async {
    await _server.close(force: true);
  }

  static String _normalizeKey(String url) {
    try {
      final uri = Uri.parse(url);
      final qs = _sortedQuery(uri.queryParameters);
      return uri.replace(query: qs).toString();
    } catch (_) {
      return url;
    }
  }

  static String _pathKey(String url) {
    try {
      final uri = Uri.parse(url);
      final qs = _sortedQuery(uri.queryParameters);
      return '${uri.path}?$qs';
    } catch (_) {
      return '';
    }
  }

  static String _sortedQuery(Map<String, String> params) {
    final keys = params.keys.toList()..sort();
    return keys
        .map(
          (k) =>
              '${Uri.encodeQueryComponent(k)}=${Uri.encodeQueryComponent(params[k] ?? '')}',
        )
        .join('&');
  }

  static String _clipReplayBody(String body, {required bool isBase64}) {
    if (body.length <= _maxReplayBodyChars) return body;
    var keep = _maxReplayBodyChars;
    if (isBase64) {
      keep -= keep % 4;
    }
    if (keep <= 0) return '';
    return body.substring(0, keep);
  }
}

class _HarHit {
  _HarHit({
    required this.status,
    required this.headers,
    required this.body,
    required this.isBase64,
    required this.mime,
    required this.truncated,
  });
  final int status;
  final Map<String, String> headers;
  final String body;
  final bool isBase64;
  final String mime;
  final bool truncated;
}
