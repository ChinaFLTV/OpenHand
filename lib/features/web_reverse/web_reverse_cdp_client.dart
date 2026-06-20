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
///
/// 自动重连：当 WebSocket 因网络抖动 / 浏览器 GPU 进程重启等被动断开时，
/// 触发 [_scheduleReconnect]，使用指数退避（200ms → 400ms → 800ms …，
/// 上限 5s）尝试最多 [reconnectMaxAttempts] 次。重连成功后会自动 emit
/// [CdpReconnectEvent] 给上层，上层负责重新 enable 各 domain。
class WebReverseCdpClient {
  WebReverseCdpClient({required this.endpoint, this.reconnectMaxAttempts = 6});

  /// `webSocketDebuggerUrl`，形如 `ws://127.0.0.1:9222/devtools/browser/<uuid>`。
  final String endpoint;

  /// 自动重连最多尝试次数，超过后放弃并抛出最后一次错误。
  final int reconnectMaxAttempts;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  bool _reconnecting = false;
  bool _connected = false;

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
    if (_closed) {
      throw StateError('CDP client is closed');
    }
    await _disposeCurrentConnection();
    final channel = WebSocketChannel.connect(Uri.parse(endpoint));
    try {
      await channel.ready;
    } catch (error, stack) {
      await _closeChannelQuietly(channel, 'close failed connection');
      silentLog('web_reverse_cdp_client', 'connect ready', error, stack);
      rethrow;
    }
    if (_closed) {
      await _closeChannelQuietly(channel, 'close late connection');
      throw StateError('CDP client is closed');
    }
    _channel = channel;
    _connected = true;
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
    final channel = _channel;
    if (_closed || channel == null || !_connected) {
      throw StateError('CDP client is closed');
    }
    if (_reconnecting) {
      throw StateError('CDP client is reconnecting');
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
    try {
      channel.sink.add(jsonEncode(payload));
    } catch (error, stack) {
      _pending.remove(id);
      if (!completer.isCompleted) completer.completeError(error, stack);
      Error.throwWithStackTrace(error, stack);
    }
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
          pending.completeError(
            CdpException(
              code: err['code'] is int ? err['code'] as int : -1,
              message: '${err['message'] ?? 'unknown error'}',
            ),
          );
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
          _eventCtrl.add(
            CdpEvent(method: method, params: params, sessionId: sessionId),
          );
        }
      }
    } catch (error, stack) {
      silentLog('web_reverse_cdp_client', '_onMessage', error, stack);
    }
  }

  void _onError(Object error, StackTrace stack) {
    silentLog('web_reverse_cdp_client', 'ws error', error, stack);
    _connected = false;
    _failAllPending(error);
    if (!_closed) {
      _scheduleReconnect();
    }
  }

  void _onDone() {
    _connected = false;
    _channel = null;
    _subscription = null;
    _failAllPending(StateError('CDP WebSocket closed'));
    if (!_closed) {
      // 非主动 close → 异常断开，尝试自动重连。
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_reconnecting || _closed) return;
    _reconnecting = true;
    () async {
      try {
        await _disposeCurrentConnection();
        var delayMs = 200;
        for (var attempt = 1; attempt <= reconnectMaxAttempts; attempt++) {
          if (_closed) return;
          await Future<void>.delayed(Duration(milliseconds: delayMs));
          if (_closed) return;
          try {
            final channel = WebSocketChannel.connect(Uri.parse(endpoint));
            await channel.ready;
            if (_closed) {
              await _closeChannelQuietly(channel, 'close late reconnect');
              return;
            }
            _channel = channel;
            _connected = true;
            _subscription = channel.stream.listen(
              _onMessage,
              onError: _onError,
              onDone: _onDone,
              cancelOnError: false,
            );
            if (!_eventCtrl.isClosed) {
              _eventCtrl.add(
                CdpEvent(
                  method: '__cdp_reconnected__',
                  params: <String, Object?>{'attempt': attempt},
                ),
              );
            }
            return;
          } catch (error, stack) {
            silentLog(
              'web_reverse_cdp_client',
              'reconnect attempt $attempt',
              error,
              stack,
            );
            delayMs = (delayMs * 2).clamp(200, 5000);
          }
        }
        _closed = true;
        _connected = false;
        _failAllPending(StateError('CDP reconnect failed'));
        // 重连彻底失败：上层 controller 据此把状态切换到「浏览器已挂掉」，
        // UI 拿到事件后展示"重启浏览器"按钮，避免用户停留在静默 placeholder。
        if (!_eventCtrl.isClosed) {
          _eventCtrl.add(
            const CdpEvent(method: '__cdp_dead__', params: <String, Object?>{}),
          );
        }
      } finally {
        _reconnecting = false;
      }
    }();
  }

  void _failAllPending(Object error) {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(error);
    }
    _pending.clear();
  }

  Future<void> close() async {
    _closed = true;
    _connected = false;
    await _disposeCurrentConnection();
    _failAllPending(StateError('CDP client manually closed'));
    if (!_eventCtrl.isClosed) await _eventCtrl.close();
  }

  Future<void> _disposeCurrentConnection() async {
    final sub = _subscription;
    final channel = _channel;
    _subscription = null;
    _channel = null;
    _connected = false;
    try {
      await sub?.cancel();
    } catch (error, stack) {
      silentLog('web_reverse_cdp_client', 'cancel subscription', error, stack);
    }
    try {
      await channel?.sink.close();
    } catch (error, stack) {
      silentLog('web_reverse_cdp_client', 'close sink', error, stack);
    }
  }

  Future<void> _closeChannelQuietly(
    WebSocketChannel channel,
    String where,
  ) async {
    try {
      await channel.sink.close();
    } catch (error, stack) {
      silentLog('web_reverse_cdp_client', where, error, stack);
    }
  }
}

class CdpEvent {
  const CdpEvent({required this.method, required this.params, this.sessionId});

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
