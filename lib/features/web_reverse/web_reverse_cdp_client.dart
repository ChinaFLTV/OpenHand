import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../app/support/silent_log.dart';

/// CDP（Chrome DevTools Protocol）轻量客户端：连 WebSocket、发命令、订阅事件。
///
/// 这里只覆盖 Web 逆向 Dashboard 需要的子集——Network / Console /
/// Page / Target。不复制 puppeteer / Playwright 的全量 API；遗漏的
/// CDP method 由外部直接 send() 即可。
///
/// 线程模型：
/// - 单条 WebSocket，单线性 id 序列。
/// - 命令通过 [send] 走 future-based 请求-响应。
/// - 事件通过 [events] 流给上层订阅。
class WebReverseCdpClient {
  WebReverseCdpClient({required this.endpoint});

  /// `webSocketDebuggerUrl`，形如 `ws://127.0.0.1:9222/devtools/browser/<uuid>`。
  final String endpoint;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  /// 已发出但尚未收到响应的命令。
  final Map<int, Completer<Map<String, Object?>>> _pending =
      <int, Completer<Map<String, Object?>>>{};

  /// 事件流（method + params）。Dashboard 用它实时刷新。
  final StreamController<CdpEvent> _eventCtrl =
      StreamController<CdpEvent>.broadcast();

  Stream<CdpEvent> get events => _eventCtrl.stream;

  int _nextId = 1;
  bool _closed = false;
  bool get isClosed => _closed;

  /// 建立连接。
  Future<void> connect() async {
    final channel = WebSocketChannel.connect(Uri.parse(endpoint));
    await channel.ready;
    _channel = channel;
    _subscription = channel.stream.listen(
      _onMessage,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
  }

  /// 发送命令，等待响应。`sessionId` 用于多目标场景（attach 到 page target 后必填）。
  Future<Map<String, Object?>> send(
    String method, {
    Map<String, Object?>? params,
    String? sessionId,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (_closed || _channel == null) {
      throw StateError('CDP client is closed');
    }
    final id = _nextId++;
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    final payload = <String, Object?>{
      'id': id,
      'method': method,
      if (params != null) 'params': params,
      if (sessionId != null) 'sessionId': sessionId,
    };
    _channel!.sink.add(jsonEncode(payload));
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      _pending.remove(id);
      rethrow;
    }
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return;
      final map = Map<String, Object?>.from(data);
      final id = map['id'];
      if (id is int) {
        final pending = _pending.remove(id);
        if (pending == null || pending.isCompleted) return;
        if (map['error'] is Map) {
          final err = Map<String, Object?>.from(map['error'] as Map);
          pending.completeError(CdpException(
            code: err['code'] is int ? err['code'] as int : -1,
            message: '${err['message'] ?? 'unknown error'}',
          ));
        } else {
          pending.complete(
            map['result'] is Map
                ? Map<String, Object?>.from(map['result'] as Map)
                : <String, Object?>{},
          );
        }
        return;
      }
      final method = map['method'];
      if (method is String) {
        final params = map['params'] is Map
            ? Map<String, Object?>.from(map['params'] as Map)
            : const <String, Object?>{};
        final sessionId = map['sessionId'] as String?;
        if (!_eventCtrl.isClosed) {
          _eventCtrl.add(CdpEvent(method: method, params: params, sessionId: sessionId));
        }
      }
    } catch (error, stack) {
      silentLog('web_reverse_cdp_client', '_onMessage', error, stack);
    }
  }

  void _onError(Object error, StackTrace stack) {
    silentLog('web_reverse_cdp_client', 'ws error', error, stack);
    _failAllPending(error);
  }

  void _onDone() {
    _failAllPending(StateError('CDP WebSocket closed'));
    _closed = true;
  }

  void _failAllPending(Object error) {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(error);
    }
    _pending.clear();
  }

  Future<void> close() async {
    _closed = true;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    _failAllPending(StateError('CDP client manually closed'));
    if (!_eventCtrl.isClosed) await _eventCtrl.close();
  }
}

class CdpEvent {
  const CdpEvent({
    required this.method,
    required this.params,
    this.sessionId,
  });

  final String method;
  final Map<String, Object?> params;
  final String? sessionId;
}

class CdpException implements Exception {
  const CdpException({required this.code, required this.message});
  final int code;
  final String message;

  @override
  String toString() => 'CdpException($code): $message';
}
