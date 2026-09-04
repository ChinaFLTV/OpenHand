import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../app/support/silent_log.dart';
import '../../shared/util/argument_guards.dart';
import '../../shared/util/async_concurrency.dart';
import '../../shared/util/byte_size_format.dart';
import '../../shared/util/exponential_backoff.dart';
import '../../shared/util/input_value_parsing.dart';

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
/// WebSocket 被动断开后使用有上限的指数退避自动重连。成功时发布
/// `__cdp_reconnected__`，由上层重新启用所需 domain。
typedef WebReverseCdpConnector = WebReverseCdpTransport Function(Uri endpoint);

class WebReverseCdpTransport {
  const WebReverseCdpTransport({
    required this.ready,
    required this.stream,
    required this.sink,
  });

  factory WebReverseCdpTransport.connect(Uri endpoint) {
    final channel = WebSocketChannel.connect(endpoint);
    return WebReverseCdpTransport(
      ready: channel.ready,
      stream: channel.stream,
      sink: channel.sink,
    );
  }

  final Future<void> ready;
  final Stream<dynamic> stream;
  final StreamSink<dynamic> sink;
}

class WebReverseCdpClient {
  WebReverseCdpClient({
    required this.endpoint,
    this.reconnectMaxAttempts = 6,
    Duration handshakeTimeout = _defaultHandshakeTimeout,
    Duration connectionCleanupTimeout = _defaultConnectionCleanupTimeout,
    Duration reconnectInitialDelay = _defaultReconnectInitialDelay,
    Duration reconnectMaxDelay = _defaultReconnectMaxDelay,
    WebReverseCdpConnector? connector,
  }) : _endpointUri = Uri.parse(endpoint),
       _handshakeTimeout = handshakeTimeout,
       _connectionCleanupTimeout = connectionCleanupTimeout,
       _reconnectInitialDelay = reconnectInitialDelay,
       _reconnectMaxDelay = reconnectMaxDelay,
       _connector = connector ?? WebReverseCdpTransport.connect {
    if ((_endpointUri.scheme != 'ws' && _endpointUri.scheme != 'wss') ||
        _endpointUri.host.isEmpty) {
      throw ArgumentError.value(endpoint, 'endpoint', '必须是绝对 ws 或 wss 端点。');
    }
    requireNonNegativeIntAtMost(
      reconnectMaxAttempts,
      _maxReconnectAttempts,
      'reconnectMaxAttempts',
    );
    requirePositiveDurationAtMost(
      handshakeTimeout,
      _maxHandshakeTimeout,
      'handshakeTimeout',
    );
    requireNonNegativeDurationAtMost(
      connectionCleanupTimeout,
      _maxConnectionCleanupTimeout,
      'connectionCleanupTimeout',
    );
    requireNonNegativeDurationAtMost(
      reconnectInitialDelay,
      _maxReconnectDelay,
      'reconnectInitialDelay',
    );
    requireNonNegativeDurationAtMost(
      reconnectMaxDelay,
      _maxReconnectDelay,
      'reconnectMaxDelay',
    );
    if (reconnectMaxDelay < reconnectInitialDelay) {
      throw ArgumentError.value(
        reconnectMaxDelay,
        'reconnectMaxDelay',
        '不得短于 reconnectInitialDelay。',
      );
    }
  }

  static const Duration _defaultHandshakeTimeout = Duration(seconds: 8);
  static const Duration _defaultConnectionCleanupTimeout = Duration(seconds: 1);
  static const Duration _defaultReconnectInitialDelay = Duration(
    milliseconds: 200,
  );
  static const Duration _defaultReconnectMaxDelay = Duration(seconds: 5);
  static const int _maxReconnectAttempts = 32;
  static const Duration _maxHandshakeTimeout = Duration(minutes: 1);
  static const Duration _maxConnectionCleanupTimeout = Duration(seconds: 30);
  static const Duration _maxReconnectDelay = Duration(minutes: 1);
  static const int _maxPendingCommands = 256;
  static const int _maxRequestCharacters = 8 * kBytesPerMiB;
  static const Duration _maxCommandTimeout = Duration(minutes: 10);
  static const int _defaultMaxResponseCharacters = 8 * kBytesPerMiB;
  static const int _maxResponseCharacters = 65 * kBytesPerMiB;

  /// `webSocketDebuggerUrl`，形如 `ws://127.0.0.1:9222/devtools/browser/<uuid>`。
  final String endpoint;

  /// 自动重连最多尝试次数，超过后发布 `__cdp_dead__`。
  final int reconnectMaxAttempts;

  final Uri _endpointUri;
  final Duration _handshakeTimeout;
  final Duration _connectionCleanupTimeout;
  final Duration _reconnectInitialDelay;
  final Duration _reconnectMaxDelay;
  final WebReverseCdpConnector _connector;

  WebReverseCdpTransport? _transport;
  WebReverseCdpTransport? _connectingTransport;
  Completer<void>? _connectingCancellation;
  StreamSubscription<dynamic>? _subscription;
  Future<void>? _connectFuture;
  Future<void>? _closeFuture;
  int _lifecycleGeneration = 0;
  int? _reconnectGeneration;
  bool _connected = false;
  bool _closed = false;

  final Map<int, _PendingCdpCommand> _pending = <int, _PendingCdpCommand>{};
  final StreamController<CdpEvent> _eventCtrl =
      StreamController<CdpEvent>.broadcast();

  Stream<CdpEvent> get events => _eventCtrl.stream;
  bool get isClosed => _closed;
  bool get _isReconnecting => _reconnectGeneration != null;

  int _nextId = 1;

  /// 建立连接；并发调用共享同一次握手。
  Future<void> connect() {
    if (_closed) {
      return Future<void>.error(StateError('CDP 客户端已关闭。'));
    }
    if (_connected && _transport != null) return Future<void>.value();
    final pending = _connectFuture;
    if (pending != null) return pending;

    final generation = ++_lifecycleGeneration;
    _reconnectGeneration = null;
    final completer = Completer<void>();
    final future = completer.future;
    _connectFuture = future;
    unawaited(
      _connectOnce(generation).then<void>(
        (_) {
          if (identical(_connectFuture, future)) _connectFuture = null;
          completer.complete();
        },
        onError: (Object error, StackTrace stack) {
          if (identical(_connectFuture, future)) _connectFuture = null;
          completer.completeError(error, stack);
        },
      ),
    );
    return future;
  }

  Future<void> _connectOnce(int generation) async {
    final connecting = _connectingTransport;
    final connectingCancellation = _connectingCancellation;
    _connectingTransport = null;
    _connectingCancellation = null;
    if (connectingCancellation != null && !connectingCancellation.isCompleted) {
      connectingCancellation.complete();
    }
    await Future.wait<void>(<Future<void>>[
      _disposeCurrentConnection(),
      if (connecting != null) _closeTransportQuietly(connecting, '关闭已被替代的连接'),
    ]);
    _throwIfSuperseded(generation);
    await _openTransport(generation);
  }

  Future<void> _openTransport(int generation) async {
    _throwIfSuperseded(generation);
    final transport = _connector(_endpointUri);
    final cancellation = Completer<void>();
    StreamSubscription<dynamic>? subscription;
    _connectingTransport = transport;
    _connectingCancellation = cancellation;
    try {
      final outcome = await Future.any<_CdpHandshakeOutcome>([
        transport.ready.then((_) => _CdpHandshakeOutcome.ready),
        cancellation.future.then((_) => _CdpHandshakeOutcome.cancelled),
      ]).timeout(_handshakeTimeout);
      if (outcome == _CdpHandshakeOutcome.cancelled) {
        throw StateError('CDP 连接已取消。');
      }
      if (!_ownsConnectingTransport(transport, generation)) {
        throw StateError('CDP 连接已被新请求替代。');
      }

      _connectingTransport = null;
      _connectingCancellation = null;
      if (!cancellation.isCompleted) cancellation.complete();
      _transport = transport;
      _connected = true;
      subscription = transport.stream.listen(
        (raw) => _handleMessage(transport, generation, raw),
        onError: (Object error, StackTrace stack) =>
            _handleTransportError(transport, generation, error, stack),
        onDone: () => _handleTransportDone(transport, generation),
        cancelOnError: false,
      );
      if (!_ownsActiveTransport(transport, generation)) {
        throw StateError('CDP 连接在安装期间已关闭。');
      }
      _subscription = subscription;
      _observeSink(transport, generation);
    } catch (error, stack) {
      var shouldCloseTransport = false;
      if (identical(_connectingTransport, transport)) {
        _connectingTransport = null;
        shouldCloseTransport = true;
      }
      if (identical(_connectingCancellation, cancellation)) {
        _connectingCancellation = null;
      }
      if (identical(_transport, transport)) {
        _transport = null;
        _connected = false;
        shouldCloseTransport = true;
      }
      if (!cancellation.isCompleted) cancellation.complete();
      await Future.wait<void>(<Future<void>>[
        _cancelSubscriptionQuietly(subscription, '取消失败的连接'),
        if (shouldCloseTransport) _closeTransportQuietly(transport, '关闭失败的连接'),
      ]);
      Error.throwWithStackTrace(error, stack);
    }
  }

  /// 发送命令，等待响应。`sessionId` 用于 attach 后的多目标场景。
  Future<Map<String, Object?>> send(
    String method, {
    Map<String, Object?>? params,
    String? sessionId,
    Duration timeout = const Duration(seconds: 8),
    int maxResponseCharacters = _defaultMaxResponseCharacters,
  }) async {
    requireNonNegativeDurationAtMost(timeout, _maxCommandTimeout, 'timeout');
    if (maxResponseCharacters < 1 ||
        maxResponseCharacters > _maxResponseCharacters) {
      throw RangeError.range(
        maxResponseCharacters,
        1,
        _maxResponseCharacters,
        'maxResponseCharacters',
      );
    }
    if (_closed) throw StateError('CDP 客户端已关闭。');
    if (_isReconnecting) throw StateError('CDP 客户端正在重连。');
    final transport = _transport;
    if (transport == null || !_connected) {
      throw StateError('CDP 客户端尚未连接。');
    }
    if (_pending.length >= _maxPendingCommands) {
      throw StateError('CDP 待处理命令过多。');
    }

    final id = _nextId++;
    final payload = <String, Object?>{
      'id': id,
      'method': method,
      if (params != null) 'params': params,
      if (sessionId != null) 'sessionId': sessionId,
    };
    final encodedPayload = jsonEncode(payload);
    if (encodedPayload.length > _maxRequestCharacters) {
      throw StateError('CDP 请求超过安全上限。');
    }
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = _PendingCdpCommand(
      completer,
      maxResponseCharacters: maxResponseCharacters,
    );
    try {
      transport.sink.add(encodedPayload);
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

  void _handleMessage(
    WebReverseCdpTransport transport,
    int generation,
    dynamic raw,
  ) {
    if (!_ownsActiveTransport(transport, generation) || raw is! String) return;
    if (!_canAcceptIncomingLength(raw.length)) {
      _handleTransportError(
        transport,
        generation,
        StateError('CDP 消息超过安全上限。'),
        StackTrace.current,
      );
      return;
    }
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return;
      final map = stringKeyedMapFromValue(data);
      final id = map['id'];
      if (id is int) {
        final pending = _pending.remove(id);
        if (pending == null || pending.completer.isCompleted) return;
        if (raw.length > pending.maxResponseCharacters) {
          pending.completer.completeError(StateError('CDP 响应超过安全上限。'));
          return;
        }
        if (map['error'] is Map) {
          final err = stringKeyedMapFromValue(map['error']);
          pending.completer.completeError(
            CdpException(
              code: intFromValue(err['code'], fallback: -1),
              message: '${err['message'] ?? '未知错误'}',
            ),
          );
        } else {
          pending.completer.complete(
            map['result'] is Map
                ? stringKeyedMapFromValue(map['result'])
                : <String, Object?>{},
          );
        }
        return;
      }

      if (raw.length > _defaultMaxResponseCharacters) {
        _handleTransportError(
          transport,
          generation,
          StateError('CDP 事件超过安全上限。'),
          StackTrace.current,
        );
        return;
      }
      final method = map['method'];
      if (method is! String || _eventCtrl.isClosed) return;
      final params = map['params'] is Map
          ? stringKeyedMapFromValue(map['params'])
          : const <String, Object?>{};
      _eventCtrl.add(
        CdpEvent(
          method: method,
          params: params,
          sessionId: map['sessionId'] as String?,
        ),
      );
    } catch (error, stack) {
      silentLog('web_reverse_cdp_client', '解析 CDP 消息', error, stack);
    }
  }

  bool _canAcceptIncomingLength(int length) {
    if (length <= _defaultMaxResponseCharacters) return true;
    for (final pending in _pending.values) {
      if (length <= pending.maxResponseCharacters) return true;
    }
    return false;
  }

  void _handleTransportError(
    WebReverseCdpTransport transport,
    int generation,
    Object error,
    StackTrace stack,
  ) {
    if (!_ownsActiveTransport(transport, generation)) return;
    silentLog('web_reverse_cdp_client', 'WebSocket 传输错误', error, stack);
    _connected = false;
    _failAllPending(error, stack);
    _scheduleReconnect(generation);
  }

  void _handleTransportDone(WebReverseCdpTransport transport, int generation) {
    if (!_ownsActiveTransport(transport, generation)) return;
    _connected = false;
    _failAllPending(StateError('CDP WebSocket 已关闭。'));
    _scheduleReconnect(generation);
  }

  void _observeSink(WebReverseCdpTransport transport, int generation) {
    unawaited(
      transport.sink.done.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          _handleTransportError(transport, generation, error, stack);
        },
      ),
    );
  }

  void _scheduleReconnect(int generation) {
    if (_closed ||
        generation != _lifecycleGeneration ||
        _reconnectGeneration != null) {
      return;
    }
    _reconnectGeneration = generation;
    unawaited(_runReconnectLoop(generation));
  }

  Future<void> _runReconnectLoop(int generation) async {
    try {
      await _disposeCurrentConnection();
      if (!_ownsReconnect(generation)) return;
      for (var attempt = 1; attempt <= reconnectMaxAttempts; attempt += 1) {
        if (_reconnectInitialDelay > Duration.zero) {
          final stillOwned = await delayWhileContinuing(
            Duration(
              milliseconds: exponentialBackoffMs(
                attempt: attempt,
                baseMs: _reconnectInitialDelay.inMilliseconds,
                capMs: _reconnectMaxDelay.inMilliseconds,
              ),
            ),
            () => _ownsReconnect(generation),
          );
          if (!stillOwned) return;
        }
        try {
          await _openTransport(generation);
          final transport = _transport;
          if (!_ownsReconnect(generation) ||
              transport == null ||
              !_ownsActiveTransport(transport, generation)) {
            throw StateError('CDP 重连已被新请求替代。');
          }
          _reconnectGeneration = null;
          _emitEvent(
            CdpEvent(
              method: '__cdp_reconnected__',
              params: <String, Object?>{'attempt': attempt},
            ),
          );
          return;
        } catch (error, stack) {
          if (!_ownsReconnect(generation)) return;
          silentLog('web_reverse_cdp_client', '第 $attempt 次重连', error, stack);
        }
      }

      _failReconnect(generation, StateError('CDP 重连失败。'));
    } catch (error, stack) {
      silentLog('web_reverse_cdp_client', '执行 CDP 重连循环', error, stack);
      _failReconnect(generation, StateError('CDP 重连清理失败：$error'), stack);
    } finally {
      if (_reconnectGeneration == generation) {
        _reconnectGeneration = null;
      }
    }
  }

  bool _ownsConnectingTransport(
    WebReverseCdpTransport transport,
    int generation,
  ) {
    return !_closed &&
        generation == _lifecycleGeneration &&
        identical(_connectingTransport, transport);
  }

  bool _ownsActiveTransport(WebReverseCdpTransport transport, int generation) {
    return !_closed &&
        _connected &&
        generation == _lifecycleGeneration &&
        identical(_transport, transport);
  }

  bool _ownsReconnect(int generation) {
    return !_closed &&
        generation == _lifecycleGeneration &&
        _reconnectGeneration == generation;
  }

  void _failReconnect(int generation, Object error, [StackTrace? stack]) {
    if (!_ownsReconnect(generation)) return;
    _reconnectGeneration = null;
    _closed = true;
    _connected = false;
    _lifecycleGeneration += 1;
    _failAllPending(error, stack);
    _emitEvent(
      const CdpEvent(method: '__cdp_dead__', params: <String, Object?>{}),
    );
  }

  void _throwIfSuperseded(int generation) {
    if (_closed) throw StateError('CDP 客户端已关闭。');
    if (generation != _lifecycleGeneration) {
      throw StateError('CDP 连接已被新请求替代。');
    }
  }

  void _emitEvent(CdpEvent event) {
    if (!_eventCtrl.isClosed) _eventCtrl.add(event);
  }

  void _failAllPending(Object error, [StackTrace? stack]) {
    for (final pending in _pending.values) {
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(error, stack ?? StackTrace.current);
      }
    }
    _pending.clear();
  }

  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) return existing;
    final completer = Completer<void>();
    _closeFuture = completer.future;
    unawaited(
      _closeInternal().then<void>(
        (_) => completer.complete(),
        onError: (Object error, StackTrace stack) {
          completer.completeError(error, stack);
        },
      ),
    );
    return completer.future;
  }

  Future<void> _closeInternal() async {
    _closed = true;
    _connected = false;
    _lifecycleGeneration += 1;
    _reconnectGeneration = null;
    final connecting = _connectingTransport;
    final connectingCancellation = _connectingCancellation;
    _connectingTransport = null;
    _connectingCancellation = null;
    if (connectingCancellation != null && !connectingCancellation.isCompleted) {
      connectingCancellation.complete();
    }
    final active = _transport;
    await Future.wait<void>(<Future<void>>[
      _disposeCurrentConnection(),
      if (connecting != null && !identical(connecting, active))
        _closeTransportQuietly(connecting, '关闭连接中的传输'),
    ]);
    _failAllPending(StateError('CDP 客户端已手动关闭。'));
    if (!_eventCtrl.isClosed) {
      try {
        await _eventCtrl.close().timeout(_connectionCleanupTimeout);
      } catch (error, stack) {
        silentLog('web_reverse_cdp_client', '关闭事件流', error, stack);
      }
    }
  }

  Future<void> _disposeCurrentConnection() async {
    final subscription = _subscription;
    final transport = _transport;
    _subscription = null;
    _transport = null;
    _connected = false;
    await Future.wait<void>(<Future<void>>[
      _cancelSubscriptionQuietly(subscription, '取消订阅'),
      if (transport != null) _closeTransportQuietly(transport, '关闭活动传输'),
    ]);
  }

  Future<void> _cancelSubscriptionQuietly(
    StreamSubscription<dynamic>? subscription,
    String where,
  ) async {
    await cancelStreamSubscriptionBounded<dynamic>(
      subscription,
      timeout: _connectionCleanupTimeout,
      onError: (error, stack) =>
          silentLog('web_reverse_cdp_client', where, error, stack),
    );
  }

  Future<void> _closeTransportQuietly(
    WebReverseCdpTransport transport,
    String where,
  ) async {
    try {
      await transport.sink.close().timeout(_connectionCleanupTimeout);
    } catch (error, stack) {
      silentLog('web_reverse_cdp_client', where, error, stack);
    }
  }
}

class _PendingCdpCommand {
  const _PendingCdpCommand(
    this.completer, {
    required this.maxResponseCharacters,
  });

  final Completer<Map<String, Object?>> completer;
  final int maxResponseCharacters;
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

enum _CdpHandshakeOutcome { ready, cancelled }
