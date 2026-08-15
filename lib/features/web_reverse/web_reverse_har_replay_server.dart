import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../app/support/silent_log.dart';
import '../../shared/net/bounded_server_bind.dart';
import '../../shared/net/http_redirect_utils.dart';
import '../../shared/util/async_concurrency.dart';
import '../../shared/util/byte_size_format.dart';
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
    required Map<String, _HarHit> replayMap,
  }) : _server = server,
       _replayMap = replayMap;

  final int port;
  final int entryCount;
  final HttpServer _server;
  final Map<String, _HarHit> _replayMap;

  static const int _maxReplayEntries = 1000;
  static const int _maxReplayHeaders = 128;
  static const int _maxReplayHeaderValueChars = 8192;
  static const int _maxReplayBodyBytes = 5 * kBytesPerMiB;
  static const int _maxConcurrentRequests = 64;
  static const Duration _bindTimeout = Duration(seconds: 3);
  static const Duration _closeTimeout = Duration(seconds: 2);
  static const Set<String> _hopByHopHeaders = <String>{
    'connection',
    'content-length',
    'keep-alive',
    'proxy-authenticate',
    'proxy-authorization',
    'te',
    'trailer',
    'transfer-encoding',
    'upgrade',
  };

  final Set<Future<void>> _pendingRequests = <Future<void>>{};
  StreamSubscription<HttpRequest>? _requestSubscription;
  int _activeRequests = 0;
  bool _closed = false;
  Future<void>? _closeFuture;

  /// 从 HAR 字节启动一个本地 mock。失败返回 null。
  /// [requestedPort] 为 0 时让 OS 随机分配。
  static Future<WebReverseHarReplayServer?> start({
    required List<int> harBytes,
    int requestedPort = 0,
  }) async {
    Map<String, _HarHit> map;
    late int replayEntryCount;
    try {
      final raw = utf8.decode(harBytes);
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final har = stringKeyedMapFromValue(decoded);
      final log = stringKeyedMapFromValue(har['log']);
      final entries = stringKeyedMapListFromValue(log['entries']);
      map = <String, _HarHit>{};
      final uniqueReplayKeys = <String>{};
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
        final headers = <_HarHeader>[];
        for (final h in stringKeyedMapListFromValue(
          res['headers'],
        ).take(_maxReplayHeaders)) {
          final name = stringFromValue(h['name']);
          if (name.isEmpty) continue;
          headers.add(
            _HarHeader(
              name: name,
              value: clipText(
                stringFromValue(h['value']),
                _maxReplayHeaderValueChars,
              ),
            ),
          );
        }
        final content = stringKeyedMapFromValue(res['content']);
        final bodyRaw = content['text']?.toString() ?? '';
        final isB64 =
            stringFromValue(content['encoding']).toLowerCase() == 'base64';
        final body = _decodeReplayBody(bodyRaw, isBase64: isB64);
        if (body == null) continue;
        final hit = _HarHit(
          status: clampedIntFromValue(
            res['status'],
            fallback: 200,
            min: 100,
            max: 599,
          ),
          headers: List<_HarHeader>.unmodifiable(headers),
          bodyBytes: body.bytes,
          mime: stringFromValue(
            content['mimeType'],
            fallback: kApplicationOctetStreamMimeType,
          ),
          truncated: body.truncated,
        );
        // 同时按 full URL 与 path-only 两种 key 存：远端 origin 的 mock 走 full，
        // 本地复现脚本走 127.0.0.1:N/<path> 走 path-only。
        map[fullKey] = hit;
        if (pathKey.isNotEmpty) map[pathKey] = hit;
        uniqueReplayKeys.add(fullKey);
        accepted++;
      }
      if (uniqueReplayKeys.isEmpty) return null;
      replayEntryCount = uniqueReplayKeys.length;
    } catch (error, stack) {
      silentLog('web_reverse_har_replay_server', '解析 HAR', error, stack);
      return null;
    }
    HttpServer server;
    try {
      server = await bindHttpServerBounded(
        InternetAddress.loopbackIPv4,
        requestedPort,
        timeout: _bindTimeout,
      );
    } catch (error, stack) {
      silentLog('web_reverse_har_replay_server', '绑定重放服务', error, stack);
      return null;
    }
    final boundPort = server.port;
    final instance = WebReverseHarReplayServer._(
      port: boundPort,
      server: server,
      entryCount: replayEntryCount,
      replayMap: Map<String, _HarHit>.unmodifiable(map),
    );
    instance._listen();
    return instance;
  }

  void _listen() {
    _requestSubscription = _server.listen(
      _dispatchRequest,
      onError: (Object error, StackTrace stack) {
        silentLog('web_reverse_har_replay_server', '读取服务请求流', error, stack);
      },
    );
  }

  void _dispatchRequest(HttpRequest request) {
    if (_closed) {
      unawaited(
        _respondJson(request, HttpStatus.serviceUnavailable, const {
          'error': 'server_closing',
        }),
      );
      return;
    }
    if (_activeRequests >= _maxConcurrentRequests) {
      unawaited(
        _respondJson(request, HttpStatus.tooManyRequests, const {
          'error': 'too_many_requests',
        }),
      );
      return;
    }

    _activeRequests++;
    if (_activeRequests >= _maxConcurrentRequests) {
      _requestSubscription?.pause();
    }
    late final Future<void> operation;
    operation = _handleRequest(request).whenComplete(() {
      _activeRequests--;
      _pendingRequests.remove(operation);
      if (!_closed && _activeRequests < _maxConcurrentRequests) {
        _requestSubscription?.resume();
      }
    });
    _pendingRequests.add(operation);
    unawaited(operation);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.method != 'GET') {
        request.response.headers.set(HttpHeaders.allowHeader, 'GET');
        await _respondJson(request, HttpStatus.methodNotAllowed, const {
          'error': 'method_not_allowed',
        });
        return;
      }

      final key = _normalizeKey(request.requestedUri.toString());
      final hit = _replayMap[key];
      final byPath = hit ?? _replayMap[_pathKeyForUri(request.requestedUri)];
      if (byPath == null) {
        await _respondJson(request, HttpStatus.notFound, {
          'error': 'no_har_entry',
          'key': key,
        });
        return;
      }

      final response = request.response;
      response.statusCode = byPath.status;
      var hasContentType = false;
      final blockedHeaders = <String>{..._hopByHopHeaders};
      for (final header in byPath.headers) {
        if (header.name.toLowerCase() != HttpHeaders.connectionHeader) {
          continue;
        }
        blockedHeaders.addAll(
          header.value
              .split(',')
              .map((value) => value.trim().toLowerCase())
              .where((value) => value.isNotEmpty),
        );
      }
      for (final header in byPath.headers) {
        final normalizedName = header.name.toLowerCase();
        if (blockedHeaders.contains(normalizedName)) continue;
        try {
          response.headers.add(header.name, header.value);
          if (normalizedName == HttpHeaders.contentTypeHeader) {
            hasContentType = true;
          }
        } catch (error, stack) {
          silentLog(
            'web_reverse_har_replay_server',
            '设置响应头 ${header.name}',
            error,
            stack,
          );
        }
      }
      if (!hasContentType) {
        response.headers.set(HttpHeaders.contentTypeHeader, byPath.mime);
      }
      if (byPath.truncated) {
        response.headers.set('x-openhand-har-body-truncated', '1');
      }
      response.add(byPath.bodyBytes);
      await response.close().timeout(_closeTimeout);
    } catch (error, stack) {
      silentLog('web_reverse_har_replay_server', '处理重放请求', error, stack);
      await _closeResponseAfterFailure(request);
    }
  }

  Future<void> _respondJson(
    HttpRequest request,
    int statusCode,
    Map<String, Object?> body,
  ) async {
    try {
      final response = request.response;
      response.statusCode = statusCode;
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode(body));
      await response.close().timeout(_closeTimeout);
    } catch (error, stack) {
      silentLog('web_reverse_har_replay_server', '写入 JSON 响应', error, stack);
      await _closeResponseAfterFailure(request);
    }
  }

  Future<void> _closeResponseAfterFailure(HttpRequest request) async {
    try {
      await request.response.close().timeout(_closeTimeout);
    } catch (_) {
      // 客户端可能已经离线，最终由服务器关闭流程强制回收连接。
    }
  }

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _closed = true;
    final subscription = _requestSubscription;
    _requestSubscription = null;
    await cancelStreamSubscriptionBounded<HttpRequest>(
      subscription,
      onError: (error, stack) =>
          silentLog('web_reverse_har_replay_server', '取消请求订阅', error, stack),
    );
    try {
      await _server.close(force: true).timeout(_closeTimeout);
    } catch (error, stack) {
      silentLog('web_reverse_har_replay_server', '关闭重放服务', error, stack);
    }
    final pending = _pendingRequests.toList(growable: false);
    if (pending.isEmpty) return;
    try {
      await Future.wait(pending).timeout(_closeTimeout);
    } catch (_) {
      // 强制关闭服务器即生命周期最终边界。
    }
  }

  static String _normalizeKey(String url) {
    try {
      final uri = Uri.parse(url);
      final qs = _sortedQuery(uri.queryParametersAll);
      return uri.replace(query: qs, fragment: '').toString();
    } catch (_) {
      return url;
    }
  }

  static String _pathKey(String url) {
    try {
      final uri = Uri.parse(url);
      return _pathKeyForUri(uri);
    } catch (_) {
      return '';
    }
  }

  static String _pathKeyForUri(Uri uri) {
    final query = _sortedQuery(uri.queryParametersAll);
    return query.isEmpty ? uri.path : '${uri.path}?$query';
  }

  static String _sortedQuery(Map<String, List<String>> params) {
    final pairs = <(String, String)>[];
    for (final entry in params.entries) {
      final values = entry.value.isEmpty ? const <String>[''] : entry.value;
      for (final value in values) {
        pairs.add((entry.key, value));
      }
    }
    pairs.sort((a, b) {
      final byName = a.$1.compareTo(b.$1);
      return byName != 0 ? byName : a.$2.compareTo(b.$2);
    });
    return pairs
        .map(
          (pair) =>
              '${Uri.encodeQueryComponent(pair.$1)}=${Uri.encodeQueryComponent(pair.$2)}',
        )
        .join('&');
  }

  static _DecodedReplayBody? _decodeReplayBody(
    String body, {
    required bool isBase64,
  }) {
    try {
      if (isBase64) {
        const encodedLimit = ((_maxReplayBodyBytes + 2) ~/ 3) * 4;
        final clippedLength = body.length <= encodedLimit
            ? body.length
            : encodedLimit - encodedLimit % 4;
        final decoded = base64Decode(body.substring(0, clippedLength));
        final bytes = decoded.length <= _maxReplayBodyBytes
            ? decoded
            : _copyPrefix(decoded, _maxReplayBodyBytes);
        return _DecodedReplayBody(
          bytes: bytes,
          truncated:
              clippedLength < body.length ||
              decoded.length > _maxReplayBodyBytes,
        );
      }
      final encoded = utf8.encode(body);
      return _DecodedReplayBody(
        bytes: encoded.length <= _maxReplayBodyBytes
            ? Uint8List.fromList(encoded)
            : _copyPrefix(encoded, _maxReplayBodyBytes),
        truncated: encoded.length > _maxReplayBodyBytes,
      );
    } catch (error, stack) {
      silentLog('web_reverse_har_replay_server', '解码重放响应体', error, stack);
      return null;
    }
  }

  static Uint8List _copyPrefix(List<int> bytes, int length) {
    final result = Uint8List(length);
    result.setRange(0, length, bytes);
    return result;
  }
}

class _DecodedReplayBody {
  const _DecodedReplayBody({required this.bytes, required this.truncated});

  final Uint8List bytes;
  final bool truncated;
}

class _HarHit {
  _HarHit({
    required this.status,
    required this.headers,
    required this.bodyBytes,
    required this.mime,
    required this.truncated,
  });
  final int status;
  final List<_HarHeader> headers;
  final Uint8List bodyBytes;
  final String mime;
  final bool truncated;
}

class _HarHeader {
  const _HarHeader({required this.name, required this.value});

  final String name;
  final String value;
}
