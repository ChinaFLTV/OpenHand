import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../../app/support/silent_log.dart';
import '../../../../shared/net/bounded_server_bind.dart';
import '../../../../shared/net/http_redirect_utils.dart';
import '../../../../shared/net/tcp_port_utils.dart';
import '../../../../shared/util/argument_guards.dart';
import '../../../../shared/util/async_concurrency.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../../../shared/util/message_frame_scan.dart';
import '../../../../shared/util/text_normalization.dart';
import '../../../../shared/util/timer_safety.dart';
import '../../model/ai_command_rule.dart';
import '../../model/ai_sandbox_settings.dart';

class AiSandboxProxyStartException implements Exception {
  const AiSandboxProxyStartException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AiSandboxProxyLease {
  AiSandboxProxyLease({
    required this.httpPort,
    required this.socksPort,
    required this.environment,
    required this.metadata,
    required Future<void> Function() close,
  }) : _close = close;

  final int httpPort;
  final int? socksPort;
  final Map<String, String> environment;
  final Map<String, Object?> metadata;
  final Future<void> Function() _close;
  Future<void>? _closeFuture;
  Future<void>? _boundedCloseFuture;

  List<int> get loopbackPorts => <int>[
    httpPort,
    if (socksPort != null) socksPort!,
  ];

  Future<void> close() => _closeFuture ??= _close();

  /// 单次化有界关闭；超时或异常仅记录，不阻断调用方后续清理。
  Future<void> closeBounded({
    required String logTag,
    required String logWhere,
    Duration timeout = kOpenHandDefaultAsyncCleanupTimeout,
  }) {
    final active = _boundedCloseFuture;
    if (active != null) return active;
    return _boundedCloseFuture = runAsyncCleanupBounded(
      close,
      timeout: timeout,
      onError: (error, stack) => silentLog(logTag, logWhere, error, stack),
    ).then<void>((_) {});
  }
}

class AiSandboxProxyService {
  AiSandboxProxyService({
    Duration handshakeTimeout = const Duration(seconds: 10),
    Duration connectionTimeout = const Duration(seconds: 20),
    Duration idleTimeout = const Duration(minutes: 10),
    Duration maxConnectionDuration = const Duration(hours: 6),
    int maxConcurrentConnections = 128,
    int maxHttpRequestBodyBytes = 512 * kBytesPerMiB,
  }) : _limits = _SandboxProxyLimits(
         handshakeTimeout: handshakeTimeout,
         connectionTimeout: connectionTimeout,
         idleTimeout: idleTimeout,
         maxConnectionDuration: maxConnectionDuration,
         maxConcurrentConnections: maxConcurrentConnections,
         maxHttpRequestBodyBytes: maxHttpRequestBodyBytes,
       );

  final _SandboxProxyLimits _limits;

  Future<AiSandboxProxyLease> start({
    required AiSandboxSettings settings,
  }) async {
    final instance = _SandboxProxyInstance(settings, _limits);
    return instance.start();
  }
}

class _SandboxProxyLimits {
  _SandboxProxyLimits({
    required this.handshakeTimeout,
    required this.connectionTimeout,
    required this.idleTimeout,
    required this.maxConnectionDuration,
    required this.maxConcurrentConnections,
    required this.maxHttpRequestBodyBytes,
  }) {
    requirePositiveDuration(handshakeTimeout, 'handshakeTimeout');
    requirePositiveDuration(connectionTimeout, 'connectionTimeout');
    requirePositiveDuration(idleTimeout, 'idleTimeout');
    requirePositiveDuration(maxConnectionDuration, 'maxConnectionDuration');
    requirePositiveInt(maxConcurrentConnections, 'maxConcurrentConnections');
    requirePositiveInt(maxHttpRequestBodyBytes, 'maxHttpRequestBodyBytes');
  }

  final Duration handshakeTimeout;
  final Duration connectionTimeout;
  final Duration idleTimeout;
  final Duration maxConnectionDuration;
  final int maxConcurrentConnections;
  final int maxHttpRequestBodyBytes;
}

class _SandboxProxyInstance {
  _SandboxProxyInstance(this.settings, this.limits);

  static const Duration _resourceCloseTimeout = Duration(seconds: 2);
  static const int _httpBodyChunkBytes = 64 * kBytesPerKiB;
  static const int _httpChunkLineMaxBytes = 8 * kBytesPerKiB;
  static const int _httpTrailerMaxBytes = 64 * kBytesPerKiB;

  final AiSandboxSettings settings;
  final _SandboxProxyLimits limits;
  final List<ServerSocket> _servers = <ServerSocket>[];
  final List<StreamSubscription<Socket>> _acceptSubscriptions =
      <StreamSubscription<Socket>>[];
  final Set<Socket> _openSockets = <Socket>{};
  final Set<Socket> _clientSockets = <Socket>{};
  final Set<_SocketReadBuffer> _readers = <_SocketReadBuffer>{};
  final Set<_SocketTunnel> _tunnels = <_SocketTunnel>{};
  bool _closed = false;
  Future<void>? _closeFuture;

  Future<AiSandboxProxyLease> start() async {
    if (settings.httpProxyPort > 0 &&
        settings.socksProxyPort > 0 &&
        settings.httpProxyPort == settings.socksProxyPort) {
      throw const AiSandboxProxyStartException('HTTP 和 SOCKS 沙箱代理端口不能相同。');
    }
    try {
      final httpServer = await _bind(settings.httpProxyPort);
      _servers.add(httpServer);
      _acceptSubscriptions.add(
        httpServer.listen(
          (client) => unawaited(_handleHttpClient(client)),
          onError: (Object error, StackTrace stack) {
            if (!_closed) {
              silentLog('ai_sandbox_proxy', '接受 HTTP 代理连接', error, stack);
            }
          },
        ),
      );

      ServerSocket? socksServer;
      if (settings.socksProxyPort > 0) {
        socksServer = await _bind(settings.socksProxyPort);
        _servers.add(socksServer);
        _acceptSubscriptions.add(
          socksServer.listen(
            (client) => unawaited(_handleSocksClient(client)),
            onError: (Object error, StackTrace stack) {
              if (!_closed) {
                silentLog('ai_sandbox_proxy', '接受 SOCKS 代理连接', error, stack);
              }
            },
          ),
        );
      }

      final httpPort = httpServer.port;
      final socksPort = socksServer?.port;
      final httpProxy = 'http://localhost:$httpPort';
      final environment = <String, String>{
        'HTTP_PROXY': httpProxy,
        'HTTPS_PROXY': httpProxy,
        'http_proxy': httpProxy,
        'https_proxy': httpProxy,
        'ALL_PROXY': socksPort == null
            ? httpProxy
            : 'socks5://localhost:$socksPort',
        'all_proxy': socksPort == null
            ? httpProxy
            : 'socks5://localhost:$socksPort',
        if (socksPort != null) 'SOCKS_PROXY': 'socks5://localhost:$socksPort',
        if (socksPort != null) 'socks_proxy': 'socks5://localhost:$socksPort',
        'NO_PROXY': '',
        'no_proxy': '',
        'OPENHAND_SANDBOX_ALLOWED_DOMAINS': _rulePatterns(
          settings.allowedDomains,
        ),
        'OPENHAND_SANDBOX_DENIED_DOMAINS': _rulePatterns(
          settings.deniedDomains,
        ),
      };
      final metadata = <String, Object?>{
        'sandbox_proxy_enabled': true,
        'sandbox_proxy_http_port': httpPort,
        if (socksPort != null) 'sandbox_proxy_socks_port': socksPort,
        'sandbox_proxy_allowed_domain_count': settings.allowedDomains.length,
        'sandbox_proxy_denied_domain_count': settings.deniedDomains.length,
        'sandbox_proxy_upstream': 'direct',
      };
      return AiSandboxProxyLease(
        httpPort: httpPort,
        socksPort: socksPort,
        environment: Map<String, String>.unmodifiable(environment),
        metadata: Map<String, Object?>.unmodifiable(metadata),
        close: close,
      );
    } catch (error, stack) {
      await close();
      silentLog('ai_sandbox_proxy', '启动沙箱代理', error, stack);
      throw AiSandboxProxyStartException('启动沙箱代理失败：$error');
    }
  }

  Future<ServerSocket> _bind(int requestedPort) {
    return bindServerSocketBounded(
      InternetAddress.loopbackIPv4,
      requestedPort > 0 ? requestedPort : 0,
      timeout: limits.connectionTimeout,
    );
  }

  Future<void> close() {
    _closed = true;
    return _closeFuture ??= _closeResources();
  }

  Future<void> _closeResources() async {
    final servers = _servers.toList(growable: false);
    final acceptSubscriptions = _acceptSubscriptions.toList(growable: false);
    _servers.clear();
    _acceptSubscriptions.clear();

    await Future.wait<void>(<Future<void>>[
      for (final server in servers) _closeResource(server.close(), '关闭代理服务'),
      for (final subscription in acceptSubscriptions)
        _closeResource(subscription.cancel(), '取消代理连接监听'),
    ]);

    for (final socket in _openSockets.toList(growable: false)) {
      socket.destroy();
    }
    await Future.wait<void>(<Future<void>>[
      for (final reader in _readers.toList(growable: false))
        _closeResource(reader.cancel(), '取消代理读取器'),
      for (final tunnel in _tunnels.toList(growable: false))
        _closeResource(tunnel.close(), '关闭代理隧道'),
    ]);
    _readers.clear();
    _tunnels.clear();
    _clientSockets.clear();
    _openSockets.clear();
  }

  Future<void> _closeResource(Future<void> future, String where) async {
    try {
      await future.timeout(_resourceCloseTimeout);
    } catch (error, stack) {
      silentLog('ai_sandbox_proxy', where, error, stack);
    }
  }

  Future<void> _handleHttpClient(Socket client) async {
    if (!_trackClient(client)) return;
    final reader = _SocketReadBuffer(
      client,
      readTimeout: limits.handshakeTimeout,
    );
    _readers.add(reader);
    try {
      final rawHeader = await reader.readHeader();
      if (rawHeader == null) {
        client.destroy();
        return;
      }
      final request = _HttpProxyRequest.tryParse(rawHeader);
      if (request == null) {
        _writeHttpError(client, 400, '代理请求无效。');
        return;
      }
      final decision = _domainDecision(request.host, request.port);
      if (!decision.allowed) {
        _writeHttpError(client, 403, decision.reason);
        return;
      }
      if (request.isConnect) {
        await _handleHttpConnect(client, reader, request);
      } else {
        await _handleHttpForward(client, reader, request);
      }
    } on FormatException {
      if (!_closed) {
        _writeHttpError(client, 431, '代理请求头过大。');
      } else {
        client.destroy();
      }
    } on SocketException catch (error, stack) {
      if (!_closed) {
        silentLog('ai_sandbox_proxy', '建立 HTTP 代理连接', error, stack);
        _writeHttpError(client, 502, '代理目标不可用。');
      } else {
        client.destroy();
      }
    } on TimeoutException catch (error, stack) {
      if (!_closed) {
        silentLog('ai_sandbox_proxy', '建立 HTTP 代理连接', error, stack);
        _writeHttpError(client, 504, '代理目标连接超时。');
      } else {
        client.destroy();
      }
    } catch (error, stack) {
      if (!_closed) {
        silentLog('ai_sandbox_proxy', '处理 HTTP 代理客户端', error, stack);
      }
      client.destroy();
    } finally {
      _readers.remove(reader);
      if (!reader.isHandedOff) {
        _clientSockets.remove(client);
        await _closeResource(
          reader.cancel(destroySocket: false),
          '取消 HTTP 握手读取器',
        );
      }
    }
  }

  Future<void> _handleHttpConnect(
    Socket client,
    _SocketReadBuffer reader,
    _HttpProxyRequest request,
  ) async {
    final remote = await Socket.connect(
      request.host,
      request.port,
      timeout: limits.connectionTimeout,
    );
    if (!_trackRemote(remote)) {
      client.destroy();
      return;
    }
    try {
      client.add(
        latin1.encode(
          'HTTP/1.1 200 Connection Established\r\n'
          'Proxy-Agent: OpenHandSandboxProxy\r\n'
          '\r\n',
        ),
      );
      _startTunnel(client: client, remote: remote, reader: reader);
    } catch (_) {
      if (!reader.isHandedOff) remote.destroy();
      rethrow;
    }
  }

  Future<void> _handleHttpForward(
    Socket client,
    _SocketReadBuffer reader,
    _HttpProxyRequest request,
  ) async {
    final contentLength = request.contentLength;
    if (contentLength != null &&
        contentLength > limits.maxHttpRequestBodyBytes) {
      _writeHttpError(client, 413, '代理请求体过大。');
      return;
    }
    final remote = await Socket.connect(
      request.host,
      request.port,
      timeout: limits.connectionTimeout,
    );
    if (!_trackRemote(remote)) {
      client.destroy();
      return;
    }
    try {
      remote.add(latin1.encode(request.forwardHeader));
      await remote.flush().timeout(limits.connectionTimeout);
      _startTunnel(
        client: client,
        remote: remote,
        reader: reader,
        clientInput: _readSingleHttpRequestBody(reader, request),
      );
    } catch (_) {
      if (!reader.isHandedOff) remote.destroy();
      rethrow;
    }
  }

  Stream<Uint8List> _readSingleHttpRequestBody(
    _SocketReadBuffer reader,
    _HttpProxyRequest request,
  ) async* {
    final contentLength = request.contentLength;
    if (contentLength != null) {
      var remaining = contentLength;
      while (remaining > 0) {
        reader.restartReadWindow(limits.idleTimeout);
        final chunk = await reader.readExactly(
          remaining < _httpBodyChunkBytes ? remaining : _httpBodyChunkBytes,
        );
        if (chunk == null) {
          throw const SocketException('代理客户端在发送完声明的请求体前已关闭。');
        }
        remaining -= chunk.length;
        yield chunk;
      }
      return;
    }
    if (!request.isChunked) return;

    var bodyBytes = 0;
    while (true) {
      reader.restartReadWindow(limits.idleTimeout);
      final sizeLine = await reader.readLine(maxBytes: _httpChunkLineMaxBytes);
      if (sizeLine == null) {
        throw const SocketException('代理客户端在分块请求体结束前已关闭。');
      }
      final sizeText = latin1.decode(sizeLine.sublist(0, sizeLine.length - 2));
      if (_HttpProxyRequest._containsInvalidHeaderText(
        sizeText,
        allowTab: true,
      )) {
        throw const FormatException('HTTP 分块扩展无效。');
      }
      final extensionIndex = sizeText.indexOf(';');
      var chunkSizeEnd = extensionIndex < 0 ? sizeText.length : extensionIndex;
      if (extensionIndex >= 0) {
        while (chunkSizeEnd > 0 &&
            _HttpProxyRequest.isHttpBadWhitespace(
              sizeText.codeUnitAt(chunkSizeEnd - 1),
            )) {
          chunkSizeEnd -= 1;
        }
      }
      final chunkSizeText = sizeText.substring(0, chunkSizeEnd);
      if (chunkSizeText.length > 16 ||
          !_HttpProxyRequest._chunkSizePattern.hasMatch(chunkSizeText)) {
        throw const FormatException('HTTP 分块大小无效。');
      }
      if (extensionIndex >= 0 &&
          !_HttpProxyRequest.isValidChunkExtensions(
            sizeText.substring(extensionIndex),
          )) {
        throw const FormatException('HTTP 分块扩展无效。');
      }
      final chunkSize = int.tryParse(chunkSizeText, radix: 16);
      if (chunkSize == null || chunkSize < 0) {
        throw const FormatException('HTTP 分块大小无效。');
      }
      if (chunkSize > limits.maxHttpRequestBodyBytes - bodyBytes) {
        throw const FormatException('代理请求体过大。');
      }
      // 分块扩展属于逐跳元数据；校验语法后移除，确保上游收到规范分帧。
      yield Uint8List.fromList(latin1.encode('$chunkSizeText\r\n'));
      if (chunkSize == 0) {
        var trailerBytes = 0;
        while (true) {
          reader.restartReadWindow(limits.idleTimeout);
          final trailer = await reader.readLine(
            maxBytes: _httpChunkLineMaxBytes,
          );
          if (trailer == null) {
            throw const SocketException('代理客户端在 HTTP 尾部结束前已关闭。');
          }
          trailerBytes += trailer.length;
          if (trailerBytes > _httpTrailerMaxBytes) {
            throw const FormatException('HTTP 尾部过大。');
          }
          if (trailer.length == 2) {
            yield Uint8List.fromList(const <int>[13, 10]);
            return;
          }
          if (!_HttpProxyRequest.isValidTrailerLine(
            latin1.decode(trailer.sublist(0, trailer.length - 2)),
          )) {
            throw const FormatException('HTTP 尾部无效。');
          }
          // 请求尾部可能改变路由、鉴权或载荷解释；只在有界预算内消费，不跨沙箱转发。
        }
      }

      var remaining = chunkSize;
      while (remaining > 0) {
        reader.restartReadWindow(limits.idleTimeout);
        final chunk = await reader.readExactly(
          remaining < _httpBodyChunkBytes ? remaining : _httpBodyChunkBytes,
        );
        if (chunk == null) {
          throw const SocketException('代理客户端在 HTTP 分块结束前已关闭。');
        }
        remaining -= chunk.length;
        yield chunk;
      }
      reader.restartReadWindow(limits.idleTimeout);
      final terminator = await reader.readExactly(2);
      if (terminator == null || terminator[0] != 13 || terminator[1] != 10) {
        throw const FormatException('HTTP 分块终止符无效。');
      }
      yield terminator;
      bodyBytes += chunkSize;
    }
  }

  Future<void> _handleSocksClient(Socket client) async {
    if (!_trackClient(client)) return;
    final reader = _SocketReadBuffer(
      client,
      readTimeout: limits.handshakeTimeout,
    );
    _readers.add(reader);
    try {
      final greeting = await reader.readExactly(2);
      if (greeting == null || greeting[0] != 0x05) {
        client.destroy();
        return;
      }
      final methods = await reader.readExactly(greeting[1]);
      if (methods == null) {
        client.destroy();
        return;
      }
      if (!methods.contains(0x00)) {
        _writeSocksMethodReply(client, 0xff);
        return;
      }
      if (!_writeSocksMethodReply(client, 0x00)) return;

      final requestHead = await reader.readExactly(4);
      if (requestHead == null ||
          requestHead[0] != 0x05 ||
          requestHead[2] != 0x00) {
        client.destroy();
        return;
      }
      if (requestHead[1] != 0x01) {
        _writeSocksReply(client, 0x07);
        return;
      }
      if (requestHead[3] != 0x01 &&
          requestHead[3] != 0x03 &&
          requestHead[3] != 0x04) {
        _writeSocksReply(client, 0x08);
        return;
      }
      final address = await _readSocksAddress(reader, requestHead[3]);
      final portBytes = await reader.readExactly(2);
      if (address == null || portBytes == null) {
        client.destroy();
        return;
      }
      final port = ByteData.sublistView(portBytes).getUint16(0);
      if (!isValidTcpPort(port)) {
        _writeSocksReply(client, 0x01);
        return;
      }
      final decision = _domainDecision(address, port);
      if (!decision.allowed) {
        _writeSocksReply(client, 0x02);
        return;
      }
      final remote = await Socket.connect(
        address,
        port,
        timeout: limits.connectionTimeout,
      );
      if (!_trackRemote(remote)) {
        client.destroy();
        return;
      }
      if (!_writeSocksReply(client, 0x00)) {
        remote.destroy();
        return;
      }
      _startTunnel(client: client, remote: remote, reader: reader);
    } on SocketException catch (error, stack) {
      if (!_closed) {
        silentLog('ai_sandbox_proxy', '建立 SOCKS 代理连接', error, stack);
        _writeSocksReply(client, 0x05);
      } else {
        client.destroy();
      }
    } on TimeoutException catch (error, stack) {
      if (!_closed) {
        silentLog('ai_sandbox_proxy', '建立 SOCKS 代理连接', error, stack);
        _writeSocksReply(client, 0x04);
      } else {
        client.destroy();
      }
    } catch (error, stack) {
      if (!_closed) {
        silentLog('ai_sandbox_proxy', '处理 SOCKS 代理客户端', error, stack);
      }
      client.destroy();
    } finally {
      _readers.remove(reader);
      if (!reader.isHandedOff) {
        _clientSockets.remove(client);
        await _closeResource(
          reader.cancel(destroySocket: false),
          '取消 SOCKS 握手读取器',
        );
      }
    }
  }

  Future<String?> _readSocksAddress(
    _SocketReadBuffer reader,
    int addressType,
  ) async {
    switch (addressType) {
      case 0x01:
        final bytes = await reader.readExactly(4);
        if (bytes == null) return null;
        return bytes.join('.');
      case 0x03:
        final lengthBytes = await reader.readExactly(1);
        if (lengthBytes == null) return null;
        if (lengthBytes[0] == 0) return null;
        final bytes = await reader.readExactly(lengthBytes[0]);
        if (bytes == null) return null;
        try {
          return utf8.decode(bytes);
        } on FormatException {
          return null;
        }
      case 0x04:
        final bytes = await reader.readExactly(16);
        if (bytes == null) return null;
        return InternetAddress.fromRawAddress(bytes).address;
      default:
        return null;
    }
  }

  bool _writeSocksMethodReply(Socket client, int method) {
    try {
      client.add(Uint8List.fromList(<int>[0x05, method]));
      if (method == 0xff) _closeSocket(client);
      return true;
    } catch (_) {
      client.destroy();
      return false;
    }
  }

  bool _writeSocksReply(Socket client, int status) {
    try {
      client.add(
        Uint8List.fromList(<int>[0x05, status, 0x00, 0x01, 0, 0, 0, 0, 0, 0]),
      );
      if (status != 0x00) _closeSocket(client);
      return true;
    } catch (_) {
      client.destroy();
      return false;
    }
  }

  _DomainDecision _domainDecision(String rawHost, int port) {
    final host = _normalizeHost(rawHost);
    for (final rule in settings.deniedDomains) {
      if (_matchesRule(rule, host, port)) {
        return _DomainDecision.blocked(
          '沙箱代理按规则“${rule.pattern}”拒绝 $host:$port。',
        );
      }
    }
    if (settings.allowedDomains.isEmpty) {
      return const _DomainDecision.allowed();
    }
    for (final rule in settings.allowedDomains) {
      if (_matchesRule(rule, host, port)) {
        return const _DomainDecision.allowed();
      }
    }
    return _DomainDecision.blocked('沙箱代理已阻止 $host:$port：目标不在允许域名列表中。');
  }

  bool _matchesRule(AiSandboxPatternRule rule, String host, int port) {
    final pattern = rule.pattern.trim();
    if (pattern.isEmpty) return false;
    final values = <String>[host, '$host:$port'];
    try {
      final regex = rule.matchMode == AiCommandMatchMode.regex
          ? RegExp(pattern, multiLine: true, caseSensitive: false)
          : RegExp(
              simplePatternToRegex(pattern.toLowerCase()),
              multiLine: true,
            );
      return values.any(regex.hasMatch);
    } catch (_) {
      return false;
    }
  }

  String _normalizeHost(String value) {
    var host = lowercaseStringFromValue(value);
    if (host.startsWith('[') && host.endsWith(']')) {
      host = host.substring(1, host.length - 1);
    }
    // DNS 末尾点表示绝对域名；规则统一匹配规范主机名，避免借此绕过限制。
    while (host.length > 1 && host.endsWith('.')) {
      host = host.substring(0, host.length - 1);
    }
    return host;
  }

  void _startTunnel({
    required Socket client,
    required Socket remote,
    required _SocketReadBuffer reader,
    Stream<Uint8List>? clientInput,
  }) {
    if (clientInput != null) reader.claimManagedRead();
    late final _SocketTunnel tunnel;
    tunnel = _SocketTunnel(
      client: client,
      remote: remote,
      idleTimeout: limits.idleTimeout,
      maxDuration: limits.maxConnectionDuration,
      onClosed: () {
        _tunnels.remove(tunnel);
        _clientSockets.remove(client);
        if (clientInput != null) {
          unawaited(reader.cancel(destroySocket: false));
        }
      },
    );
    _tunnels.add(tunnel);
    try {
      tunnel.start(clientInput ?? reader.handOff());
    } catch (_) {
      unawaited(tunnel.close());
      rethrow;
    }
  }

  void _writeHttpError(Socket client, int status, String message) {
    final reason = switch (status) {
      400 => 'Bad Request',
      403 => 'Forbidden',
      413 => 'Payload Too Large',
      431 => 'Request Header Fields Too Large',
      502 => 'Bad Gateway',
      504 => 'Gateway Timeout',
      _ => 'Proxy Error',
    };
    final body = utf8.encode('$message\n');
    try {
      client.add(
        latin1.encode(
          'HTTP/1.1 $status $reason\r\n'
          'Content-Type: text/plain; charset=utf-8\r\n'
          'Connection: close\r\n'
          'Content-Length: ${body.length}\r\n'
          '\r\n',
        ),
      );
      client.add(body);
      _closeSocket(client);
    } catch (_) {
      client.destroy();
    }
  }

  void _closeSocket(Socket socket) {
    unawaited(
      socket
          .close()
          .timeout(
            _resourceCloseTimeout,
            onTimeout: () {
              socket.destroy();
            },
          )
          .catchError((Object error, StackTrace stack) {
            if (!_closed) {
              silentLog('ai_sandbox_proxy', '关闭代理套接字', error, stack);
            }
            socket.destroy();
          }),
    );
  }

  bool _trackClient(Socket socket) {
    if (_closed || _clientSockets.length >= limits.maxConcurrentConnections) {
      socket.destroy();
      return false;
    }
    _clientSockets.add(socket);
    _trackSocket(socket, onDone: () => _clientSockets.remove(socket));
    return true;
  }

  bool _trackRemote(Socket socket) {
    if (_closed) {
      socket.destroy();
      return false;
    }
    _trackSocket(socket);
    return true;
  }

  void _trackSocket(Socket socket, {void Function()? onDone}) {
    _openSockets.add(socket);
    unawaited(
      socket.done
          .catchError((Object error, StackTrace stack) {
            if (!_closed) {
              silentLog('ai_sandbox_proxy', '等待套接字关闭', error, stack);
            }
          })
          .whenComplete(() {
            _openSockets.remove(socket);
            onDone?.call();
          }),
    );
  }

  String _rulePatterns(List<AiSandboxPatternRule> rules) {
    return trimmedNonEmptyStrings(rules.map((item) => item.pattern)).join(',');
  }
}

class _SocketTunnel {
  _SocketTunnel({
    required this.client,
    required this.remote,
    required this.idleTimeout,
    required this.maxDuration,
    required void Function() onClosed,
  }) : _onClosed = onClosed;

  static const Duration _cancelTimeout = Duration(seconds: 2);

  final Socket client;
  final Socket remote;
  final Duration idleTimeout;
  final Duration maxDuration;
  final void Function() _onClosed;
  StreamSubscription<void>? _clientToRemote;
  StreamSubscription<void>? _remoteToClient;
  Timer? _idleTimer;
  Timer? _maxDurationTimer;
  Future<void>? _closeFuture;
  bool _clientInputDone = false;
  bool _remoteInputDone = false;
  bool _closed = false;

  void start(Stream<Uint8List> clientInput) {
    if (_closed || _clientToRemote != null || _remoteToClient != null) {
      throw StateError('代理隧道已启动或关闭。');
    }
    _resetIdleTimer();
    _maxDurationTimer = startSafeTimer(
      maxDuration,
      close,
      max: maxDuration,
      onError: (error, stack) =>
          silentLog('ai_sandbox_proxy', '按最大时长关闭代理隧道', error, stack),
    );
    _clientToRemote = clientInput
        .asyncMap((data) {
          return _forward(data, remote);
        })
        .listen(
          null,
          onDone: () => _onInputDone(clientToRemote: true),
          onError: (Object error, StackTrace stack) {
            _onPipeError('客户端转发管道', error, stack);
          },
          cancelOnError: true,
        );
    _remoteToClient = remote
        .asyncMap((data) {
          return _forward(data, client);
        })
        .listen(
          null,
          onDone: () => _onInputDone(clientToRemote: false),
          onError: (Object error, StackTrace stack) {
            _onPipeError('远端转发管道', error, stack);
          },
          cancelOnError: true,
        );
  }

  Future<void> _forward(Uint8List data, Socket destination) async {
    if (_closed || data.isEmpty) return;
    _resetIdleTimer();
    destination.add(data);
    await destination.flush().timeout(idleTimeout);
    if (!_closed) _resetIdleTimer();
  }

  void _onInputDone({required bool clientToRemote}) {
    if (_closed) return;
    if (clientToRemote) {
      _clientInputDone = true;
      _halfClose(remote);
    } else {
      _remoteInputDone = true;
      _halfClose(client);
    }
    if (_clientInputDone && _remoteInputDone) {
      _closeWithoutWaiting('关闭已完成双向传输的代理隧道');
    }
  }

  void _halfClose(Socket socket) {
    unawaited(
      socket
          .close()
          .timeout(
            _cancelTimeout,
            onTimeout: () {
              socket.destroy();
            },
          )
          .catchError((Object error, StackTrace stack) {
            if (!_closed) {
              silentLog('ai_sandbox_proxy', '半关闭代理套接字', error, stack);
            }
            socket.destroy();
          }),
    );
  }

  void _onPipeError(String where, Object error, StackTrace stack) {
    if (_closed) return;
    if (error is! FormatException && error is! SocketException) {
      silentLog('ai_sandbox_proxy', where, error, stack);
    }
    _closeWithoutWaiting('转发异常后关闭代理隧道');
  }

  void _resetIdleTimer() {
    if (_closed) return;
    _idleTimer?.cancel();
    _idleTimer = startSafeTimer(
      idleTimeout,
      close,
      max: idleTimeout,
      onError: (error, stack) =>
          silentLog('ai_sandbox_proxy', '按空闲超时关闭代理隧道', error, stack),
    );
  }

  void _closeWithoutWaiting(String action) {
    unawaited(
      close().catchError(
        (Object error, StackTrace stack) =>
            silentLog('ai_sandbox_proxy', action, error, stack),
      ),
    );
  }

  Future<void> close() {
    if (!_closed) {
      _closed = true;
      _idleTimer?.cancel();
      _maxDurationTimer?.cancel();
      client.destroy();
      remote.destroy();
    }
    return _closeFuture ??= _finishClose();
  }

  Future<void> _finishClose() async {
    try {
      final cancellations = <Future<void>>[
        if (_clientToRemote != null) _clientToRemote!.cancel(),
        if (_remoteToClient != null) _remoteToClient!.cancel(),
      ];
      if (cancellations.isNotEmpty) {
        await Future.wait<void>(
          cancellations,
        ).timeout(_cancelTimeout, onTimeout: () => <void>[]);
      }
    } catch (error, stack) {
      silentLog('ai_sandbox_proxy', '取消代理隧道订阅', error, stack);
    } finally {
      _onClosed();
    }
  }
}

class _HttpProxyRequest {
  _HttpProxyRequest({
    required this.method,
    required this.target,
    required this.version,
    required this.headerLines,
    required this.host,
    required this.port,
    required this.forwardTarget,
    required this.forwardHostHeader,
    required this.contentLength,
    required this.isChunked,
  });

  final String method;
  final String target;
  final String version;
  final List<String> headerLines;
  final String host;
  final int port;
  final String forwardTarget;
  final String forwardHostHeader;
  final int? contentLength;
  final bool isChunked;

  static final RegExp _headerLineSeparatorPattern = RegExp(r'\r?\n');
  static final RegExp _methodPattern = RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$");
  static final RegExp _headerNamePattern = RegExp(
    r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$",
  );
  static final RegExp _contentLengthPattern = RegExp(r'^[0-9]+$');
  static final RegExp _chunkSizePattern = RegExp(r'^[0-9A-Fa-f]+$');

  bool get isConnect => method.toUpperCase() == 'CONNECT';

  String get forwardHeader {
    final buffer = StringBuffer()..writeln('$method $forwardTarget $version');
    final connectionHeaders = <String>{
      'connection',
      kConnectionKeepAlive,
      'proxy-authenticate',
      'proxy-authorization',
      'proxy-connection',
      'te',
      'trailer',
    };
    for (final line in headerLines) {
      final separator = line.indexOf(':');
      if (separator <= 0 ||
          lowercaseStringFromValue(line.substring(0, separator)) !=
              'connection') {
        continue;
      }
      connectionHeaders.addAll(
        line
            .substring(separator + 1)
            .split(',')
            .map(lowercaseStringFromValue)
            .where((name) => name.isNotEmpty),
      );
    }
    var wroteHost = false;
    for (final line in headerLines) {
      final separator = line.indexOf(':');
      final name = separator < 0
          ? ''
          : lowercaseStringFromValue(line.substring(0, separator));
      if (connectionHeaders.contains(name)) continue;
      if (name == HttpHeaders.hostHeader) {
        if (!wroteHost) buffer.writeln('Host: $forwardHostHeader');
        wroteHost = true;
        continue;
      }
      buffer.writeln(line);
    }
    if (!wroteHost) buffer.writeln('Host: $forwardHostHeader');
    buffer.writeln('Connection: close');
    buffer.writeln();
    return buffer.toString().replaceAll('\n', '\r\n');
  }

  static _HttpProxyRequest? tryParse(String rawHeader) {
    final lines = rawHeader.split(_headerLineSeparatorPattern);
    if (lines.isEmpty) return null;
    final requestLine = lines.first.trim();
    final parts = requestLine.split(kInlineWhitespacePattern);
    if (parts.length != 3) return null;
    final method = parts[0];
    final target = parts[1];
    final version = parts[2];
    if (!_methodPattern.hasMatch(method) ||
        target.isEmpty ||
        _containsInvalidHeaderText(target, allowTab: false) ||
        (version != 'HTTP/1.0' && version != 'HTTP/1.1')) {
      return null;
    }
    final headerLines = trimRightNonEmptyLines(lines.skip(1));
    final headers = <String, String>{};
    for (final line in headerLines) {
      final separator = line.indexOf(':');
      if (separator <= 0) return null;
      final rawName = line.substring(0, separator);
      if (!_headerNamePattern.hasMatch(rawName)) return null;
      final name = lowercaseStringFromValue(rawName);
      if (name == HttpHeaders.hostHeader && headers.containsKey(name)) return null;
      if ((name == HttpHeaders.connectionHeader ||
              name == HttpHeaders.contentLengthHeader ||
              name == HttpHeaders.transferEncodingHeader) &&
          headers.containsKey(name)) {
        return null;
      }
      final value = line.substring(separator + 1).trim();
      if (_containsInvalidHeaderText(value, allowTab: true)) return null;
      headers[name] = value;
    }
    if (headers.containsKey(HttpHeaders.contentLengthHeader) &&
        headers.containsKey(HttpHeaders.transferEncodingHeader)) {
      return null;
    }
    final rawContentLength = headers[HttpHeaders.contentLengthHeader];
    int? parsedContentLength;
    if (rawContentLength != null) {
      if (!_contentLengthPattern.hasMatch(rawContentLength)) return null;
      parsedContentLength = int.tryParse(rawContentLength);
      if (parsedContentLength == null || parsedContentLength < 0) return null;
    }
    final transferEncoding = lowercaseStringFromValue(
      headers[HttpHeaders.transferEncodingHeader],
    );
    if (transferEncoding.isNotEmpty && transferEncoding != 'chunked') {
      return null;
    }
    final isChunked = transferEncoding == 'chunked';
    if (isChunked && version == 'HTTP/1.0') return null;
    final isConnect = method.toUpperCase() == 'CONNECT';
    final connectionTokens = lowercaseStringFromValue(
      headers[HttpHeaders.connectionHeader],
    ).split(',').map((item) => item.trim()).toSet();
    if (connectionTokens.contains(HttpHeaders.hostHeader) ||
        connectionTokens.contains(HttpHeaders.contentLengthHeader) ||
        connectionTokens.contains(HttpHeaders.transferEncodingHeader)) {
      return null;
    }
    if (!isConnect &&
        (nullIfBlank(headers['upgrade']) != null ||
            connectionTokens.contains('upgrade'))) {
      return null;
    }

    if (isConnect) {
      final authority = _HostPort.parse(target, defaultPort: 443);
      if (authority == null) return null;
      return _HttpProxyRequest(
        method: method,
        target: target,
        version: version,
        headerLines: headerLines,
        host: authority.host,
        port: authority.port,
        forwardTarget: target,
        forwardHostHeader: _formatHostHeader(
          authority.host,
          authority.port,
          443,
        ),
        contentLength: parsedContentLength,
        isChunked: isChunked,
      );
    }

    final uri = Uri.tryParse(target);
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
      final scheme = uri.scheme.toLowerCase();
      if (scheme != 'http' && scheme != 'https') return null;
      // HTTPS 代理必须使用 CONNECT，禁止把绝对 HTTPS 地址按明文转发。
      if (scheme == 'https') return null;
      if (!_HostPort._isValidHost(uri.host)) return null;
      final defaultPort = scheme == 'https' ? 443 : 80;
      final int port;
      try {
        port = uri.hasPort ? uri.port : defaultPort;
      } on FormatException {
        return null;
      }
      if (!isValidTcpPort(port)) return null;
      return _HttpProxyRequest(
        method: method,
        target: target,
        version: version,
        headerLines: headerLines,
        host: uri.host,
        port: port,
        forwardTarget: _originForm(uri),
        forwardHostHeader: _formatHostHeader(uri.host, port, defaultPort),
        contentLength: parsedContentLength,
        isChunked: isChunked,
      );
    }

    final hostHeader = headers['host'];
    if (hostHeader == null || hostHeader.isEmpty) return null;
    final authority = _HostPort.parse(hostHeader, defaultPort: 80);
    if (authority == null) return null;
    return _HttpProxyRequest(
      method: method,
      target: target,
      version: version,
      headerLines: headerLines,
      host: authority.host,
      port: authority.port,
      forwardTarget: target.isEmpty ? '/' : target,
      forwardHostHeader: _formatHostHeader(authority.host, authority.port, 80),
      contentLength: parsedContentLength,
      isChunked: isChunked,
    );
  }

  static String _formatHostHeader(String host, int port, int defaultPort) {
    final formattedHost = host.contains(':') ? '[$host]' : host;
    return port == defaultPort ? formattedHost : '$formattedHost:$port';
  }

  static String _originForm(Uri uri) {
    final path = uri.path.isEmpty ? '/' : uri.path;
    if (uri.query.isEmpty) return path;
    return '$path?${uri.query}';
  }

  static bool _containsInvalidHeaderText(
    String value, {
    required bool allowTab,
  }) {
    for (final codeUnit in value.codeUnits) {
      if (codeUnit == 0x7f ||
          (codeUnit < 0x20 && !(allowTab && codeUnit == 0x09))) {
        return true;
      }
    }
    return false;
  }

  static bool isValidTrailerLine(String line) {
    if (_containsInvalidHeaderText(line, allowTab: true)) return false;
    final separator = line.indexOf(':');
    if (separator <= 0 ||
        !_headerNamePattern.hasMatch(line.substring(0, separator))) {
      return false;
    }
    final name = lowercaseStringFromValue(line.substring(0, separator));
    return name != HttpHeaders.contentLengthHeader &&
        name != HttpHeaders.hostHeader &&
        name != HttpHeaders.transferEncodingHeader;
  }

  static bool isValidChunkExtensions(String value) {
    var index = 0;
    while (index < value.length) {
      index = _skipHttpBadWhitespace(value, index);
      if (index == value.length) return true;
      if (value.codeUnitAt(index) != 0x3b) return false;
      index += 1;
      index = _skipHttpBadWhitespace(value, index);
      final nameStart = index;
      while (index < value.length &&
          !isHttpBadWhitespace(value.codeUnitAt(index)) &&
          value.codeUnitAt(index) != 0x3b &&
          value.codeUnitAt(index) != 0x3d) {
        index += 1;
      }
      if (nameStart == index ||
          !_headerNamePattern.hasMatch(value.substring(nameStart, index))) {
        return false;
      }
      index = _skipHttpBadWhitespace(value, index);
      if (index == value.length || value.codeUnitAt(index) == 0x3b) {
        continue;
      }
      if (value.codeUnitAt(index) != 0x3d) return false;

      index += 1;
      index = _skipHttpBadWhitespace(value, index);
      if (index == value.length) return false;
      if (value.codeUnitAt(index) != 0x22) {
        final tokenStart = index;
        while (index < value.length &&
            !isHttpBadWhitespace(value.codeUnitAt(index)) &&
            value.codeUnitAt(index) != 0x3b) {
          index += 1;
        }
        if (tokenStart == index ||
            !_headerNamePattern.hasMatch(value.substring(tokenStart, index))) {
          return false;
        }
        index = _skipHttpBadWhitespace(value, index);
        if (index < value.length && value.codeUnitAt(index) != 0x3b) {
          return false;
        }
        continue;
      }

      index += 1;
      var closed = false;
      while (index < value.length) {
        final codeUnit = value.codeUnitAt(index);
        if (codeUnit == 0x22) {
          index += 1;
          closed = true;
          break;
        }
        if (codeUnit == 0x5c) {
          index += 1;
          if (index == value.length ||
              !_isValidQuotedPairCodeUnit(value.codeUnitAt(index))) {
            return false;
          }
          index += 1;
          continue;
        }
        if (!_isValidQuotedTextCodeUnit(codeUnit)) return false;
        index += 1;
      }
      index = _skipHttpBadWhitespace(value, index);
      if (!closed ||
          (index < value.length && value.codeUnitAt(index) != 0x3b)) {
        return false;
      }
    }
    return true;
  }

  static bool _isValidQuotedTextCodeUnit(int value) {
    return value == 0x09 ||
        value == 0x20 ||
        value == 0x21 ||
        (value >= 0x23 && value <= 0x5b) ||
        (value >= 0x5d && value <= 0x7e) ||
        (value >= 0x80 && value <= 0xff);
  }

  static bool _isValidQuotedPairCodeUnit(int value) {
    return value == 0x09 ||
        value == 0x20 ||
        (value >= 0x21 && value <= 0x7e) ||
        (value >= 0x80 && value <= 0xff);
  }

  static bool isHttpBadWhitespace(int value) {
    return value == 0x20 || value == 0x09;
  }

  static int _skipHttpBadWhitespace(String value, int index) {
    while (index < value.length &&
        isHttpBadWhitespace(value.codeUnitAt(index))) {
      index += 1;
    }
    return index;
  }
}

class _HostPort {
  const _HostPort(this.host, this.port);

  final String host;
  final int port;

  static _HostPort? parse(String value, {required int defaultPort}) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('[')) {
      final closing = trimmed.indexOf(']');
      if (closing <= 0) return null;
      final host = trimmed.substring(1, closing);
      final rest = trimmed.substring(closing + 1);
      if (!_isValidHost(host)) return null;
      if (rest.isEmpty) return _HostPort(host, defaultPort);
      if (!rest.startsWith(':') || rest.length == 1) return null;
      final port = tcpPortFromText(rest.substring(1));
      return port == null ? null : _HostPort(host, port);
    }
    final colon = trimmed.lastIndexOf(':');
    if (colon >= 0) {
      if (colon == 0 || trimmed.indexOf(':') != colon) return null;
      final host = trimmed.substring(0, colon);
      final port = tcpPortFromText(trimmed.substring(colon + 1));
      if (!_isValidHost(host) || port == null) return null;
      return _HostPort(host, port);
    }
    if (!_isValidHost(trimmed)) return null;
    return _HostPort(trimmed, defaultPort);
  }

  static bool _isValidHost(String value) {
    if (value.isEmpty || value.length > 253) return false;
    for (final codeUnit in value.codeUnits) {
      if (codeUnit <= 0x20 || codeUnit == 0x7f) return false;
    }
    return !value.contains(RegExp(r'[/\\?#@]'));
  }
}

class _DomainDecision {
  const _DomainDecision.allowed() : allowed = true, reason = '';
  const _DomainDecision.blocked(this.reason) : allowed = false;

  final bool allowed;
  final String reason;
}

class _SocketReadBuffer {
  _SocketReadBuffer(this.socket, {required this.readTimeout})
    : _readStopwatch = Stopwatch()..start() {
    _subscription = socket.listen(
      (data) {
        _pause();
        if (_activeBufferLimit > 0 &&
            _buffer.length + data.length > _activeBufferLimit) {
          _error = const FormatException('代理握手预读数据过大。');
          _stack = StackTrace.current;
          socket.destroy();
          _wakeWaiter();
          return;
        }
        _buffer.addAll(data);
        _wakeWaiter();
      },
      onDone: () {
        _done = true;
        _wakeWaiter();
      },
      onError: (Object error, StackTrace stack) {
        _error ??= error;
        _stack ??= stack;
        _done = true;
        _wakeWaiter();
      },
      cancelOnError: true,
    );
    _pause();
  }

  static const int _defaultMaxHeaderBytes = 64 * kBytesPerKiB;
  static const int _maxReadAheadBytes = 64 * kBytesPerKiB;
  static const int _maxExactReadBytes = 64 * kBytesPerKiB;

  final Socket socket;
  Duration readTimeout;
  final Stopwatch _readStopwatch;
  late final StreamSubscription<Uint8List> _subscription;
  final List<int> _buffer = <int>[];
  Completer<void>? _waiter;
  int _activeBufferLimit = 0;
  bool _operationActive = false;
  bool _paused = false;
  bool _cancelled = false;
  bool _handedOff = false;
  bool _managedRead = false;
  bool _done = false;
  Object? _error;
  StackTrace? _stack;

  bool get isHandedOff => _handedOff || _managedRead;

  void claimManagedRead() {
    if (_operationActive || _handedOff || _managedRead || _cancelled) {
      throw StateError('代理套接字读取器当前无法接管。');
    }
    _managedRead = true;
  }

  void restartReadWindow(Duration timeout) {
    requirePositiveDuration(timeout, 'timeout');
    if (_operationActive || _handedOff || _cancelled) {
      throw StateError('代理套接字读取器不可用。');
    }
    readTimeout = timeout;
    _readStopwatch
      ..reset()
      ..start();
  }

  Future<String?> readHeader({int maxBytes = _defaultMaxHeaderBytes}) async {
    final effectiveMaxBytes = maxBytes > 0 ? maxBytes : _defaultMaxHeaderBytes;
    return _readBounded(effectiveMaxBytes + _maxReadAheadBytes, () async {
      var scannedLength = 0;
      while (true) {
        _throwIfErrored();
        final frame = findMessageFrameHeaderEnd(
          _buffer,
          startIndex: scannedLength,
        );
        if (frame != null) {
          final end = frame.bodyStart;
          if (end > effectiveMaxBytes) {
            throw const FormatException('代理请求头过大。');
          }
          final header = _buffer.sublist(0, end);
          _buffer.removeRange(0, end);
          return latin1.decode(header);
        }
        if (_buffer.length >= effectiveMaxBytes) {
          throw const FormatException('代理请求头过大。');
        }
        if (_done) return null;
        scannedLength = _buffer.length;
        await _waitForData();
      }
    });
  }

  Future<Uint8List?> readExactly(int count) async {
    if (count < 0 || count > _maxExactReadBytes) {
      throw RangeError.range(count, 0, _maxExactReadBytes, 'count');
    }
    if (count == 0) {
      return Uint8List(0);
    }
    return _readBounded(_maxExactReadBytes, () async {
      while (_buffer.length < count) {
        _throwIfErrored();
        if (_done) return null;
        await _waitForData();
      }
      final bytes = Uint8List.fromList(_buffer.sublist(0, count));
      _buffer.removeRange(0, count);
      return bytes;
    });
  }

  Future<Uint8List?> readLine({required int maxBytes}) async {
    if (maxBytes < 1 || maxBytes > _defaultMaxHeaderBytes) {
      throw RangeError.range(maxBytes, 1, _defaultMaxHeaderBytes, 'maxBytes');
    }
    return _readBounded(maxBytes + _maxReadAheadBytes, () async {
      var scannedLength = 0;
      while (true) {
        _throwIfErrored();
        final end = _findCrlf(
          _buffer,
          startIndex: scannedLength > 1 ? scannedLength - 1 : 0,
        );
        if (end >= 0) {
          if (end > maxBytes) {
            throw const FormatException('代理协议行过大。');
          }
          final line = Uint8List.fromList(_buffer.sublist(0, end + 2));
          _buffer.removeRange(0, end + 2);
          return line;
        }
        if (_buffer.length > maxBytes + 1) {
          throw const FormatException('代理协议行过大。');
        }
        if (_done) return null;
        scannedLength = _buffer.length;
        await _waitForData();
      }
    });
  }

  Stream<Uint8List> handOff() {
    if (_operationActive || _handedOff || _managedRead || _cancelled) {
      throw StateError('代理套接字读取器当前无法移交。');
    }
    _handedOff = true;
    _readStopwatch.stop();
    final pending = _takePending();
    final pendingError = _error;
    final pendingStack = _stack;
    late final StreamController<Uint8List> controller;
    controller = StreamController<Uint8List>(
      sync: true,
      onListen: () {
        _subscription
          ..onData(controller.add)
          ..onDone(() {
            unawaited(controller.close());
          })
          ..onError((Object error, StackTrace stack) {
            controller.addError(error, stack);
            unawaited(controller.close());
          });
        if (pending.isNotEmpty) controller.add(pending);
        if (pendingError != null) {
          controller.addError(pendingError, pendingStack ?? StackTrace.current);
          unawaited(controller.close());
        } else if (_done) {
          unawaited(controller.close());
        } else if (!controller.isPaused) {
          _resume();
        }
      },
      onPause: _pause,
      onResume: _resume,
      onCancel: _cancelSubscription,
    );
    return controller.stream;
  }

  Uint8List _takePending() {
    if (_buffer.isEmpty) return Uint8List(0);
    final pending = Uint8List.fromList(_buffer);
    _buffer.clear();
    return pending;
  }

  Future<T?> _readBounded<T>(
    int bufferLimit,
    Future<T?> Function() action,
  ) async {
    if (_operationActive || _handedOff || _cancelled) {
      throw StateError('代理套接字读取器不可用。');
    }
    _operationActive = true;
    _activeBufferLimit = bufferLimit;
    try {
      final remaining = readTimeout - _readStopwatch.elapsed;
      if (remaining <= Duration.zero) {
        await _abortTimedOutRead();
        return null;
      }
      var deadlineExpired = false;
      final result = await action().timeout(
        remaining,
        onTimeout: () {
          deadlineExpired = true;
          return null;
        },
      );
      if (deadlineExpired) await _abortTimedOutRead();
      return result;
    } finally {
      _activeBufferLimit = 0;
      _operationActive = false;
      _pause();
    }
  }

  Future<void> _abortTimedOutRead() async {
    socket.destroy();
    await cancel();
  }

  Future<void> _waitForData() {
    _waiter ??= Completer<void>();
    _resume();
    return _waiter!.future;
  }

  void _wakeWaiter() {
    final waiter = _waiter;
    _waiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  void _throwIfErrored() {
    final error = _error;
    if (error != null) {
      Error.throwWithStackTrace(error, _stack ?? StackTrace.current);
    }
  }

  void _pause() {
    if (_paused || _cancelled || _done) return;
    _subscription.pause();
    _paused = true;
  }

  void _resume() {
    if (!_paused || _cancelled || _done) return;
    _paused = false;
    _subscription.resume();
  }

  Future<void> cancel({bool destroySocket = true}) {
    if (destroySocket) socket.destroy();
    return _cancelSubscription();
  }

  Future<void> _cancelSubscription() async {
    if (_cancelled) return;
    _cancelled = true;
    _done = true;
    _readStopwatch.stop();
    _wakeWaiter();
    await cancelStreamSubscriptionBounded<Uint8List>(
      _subscription,
      onError: (error, stack) =>
          silentLog('ai_sandbox_proxy', '取消握手读取器', error, stack),
    );
  }

  int _findCrlf(List<int> bytes, {int startIndex = 0}) {
    final start = startIndex > 0 ? startIndex : 0;
    for (var index = start; index + 1 < bytes.length; index++) {
      if (bytes[index] == 13 && bytes[index + 1] == 10) return index;
    }
    return -1;
  }
}
