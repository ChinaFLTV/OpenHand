import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../../app/support/silent_log.dart';
import '../../../../shared/net/tcp_port_utils.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../model/ai_deny_command_rule.dart';
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

  List<int> get loopbackPorts => <int>[
    httpPort,
    if (socksPort != null) socksPort!,
  ];

  Future<void> close() => _closeFuture ??= _close();
}

class AiSandboxProxyService {
  AiSandboxProxyService({
    Duration handshakeTimeout = const Duration(seconds: 10),
    Duration connectionTimeout = const Duration(seconds: 20),
    Duration idleTimeout = const Duration(minutes: 10),
    Duration maxConnectionDuration = const Duration(hours: 6),
    int maxConcurrentConnections = 128,
  }) : _limits = _SandboxProxyLimits(
         handshakeTimeout: handshakeTimeout,
         connectionTimeout: connectionTimeout,
         idleTimeout: idleTimeout,
         maxConnectionDuration: maxConnectionDuration,
         maxConcurrentConnections: maxConcurrentConnections,
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
  }) {
    if (handshakeTimeout <= Duration.zero) {
      throw ArgumentError.value(
        handshakeTimeout,
        'handshakeTimeout',
        'Must be positive.',
      );
    }
    if (connectionTimeout <= Duration.zero) {
      throw ArgumentError.value(
        connectionTimeout,
        'connectionTimeout',
        'Must be positive.',
      );
    }
    if (idleTimeout <= Duration.zero) {
      throw ArgumentError.value(
        idleTimeout,
        'idleTimeout',
        'Must be positive.',
      );
    }
    if (maxConnectionDuration <= Duration.zero) {
      throw ArgumentError.value(
        maxConnectionDuration,
        'maxConnectionDuration',
        'Must be positive.',
      );
    }
    if (maxConcurrentConnections <= 0) {
      throw ArgumentError.value(
        maxConcurrentConnections,
        'maxConcurrentConnections',
        'Must be positive.',
      );
    }
  }

  final Duration handshakeTimeout;
  final Duration connectionTimeout;
  final Duration idleTimeout;
  final Duration maxConnectionDuration;
  final int maxConcurrentConnections;
}

class _SandboxProxyInstance {
  _SandboxProxyInstance(this.settings, this.limits);

  static const Duration _resourceCloseTimeout = Duration(seconds: 2);

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
      throw const AiSandboxProxyStartException(
        'HTTP and SOCKS sandbox proxy ports must be different.',
      );
    }
    try {
      final httpServer = await _bind(settings.httpProxyPort);
      _servers.add(httpServer);
      _acceptSubscriptions.add(
        httpServer.listen(
          (client) => unawaited(_handleHttpClient(client)),
          onError: (Object error, StackTrace stack) {
            if (!_closed) {
              silentLog('ai_sandbox_proxy', 'http accept', error, stack);
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
                silentLog('ai_sandbox_proxy', 'socks accept', error, stack);
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
      silentLog('ai_sandbox_proxy', 'start', error, stack);
      throw AiSandboxProxyStartException(
        'Failed to start sandbox proxy: $error',
      );
    }
  }

  Future<ServerSocket> _bind(int requestedPort) {
    return ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      requestedPort > 0 ? requestedPort : 0,
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
      for (final server in servers)
        _closeResource(server.close(), 'close server'),
      for (final subscription in acceptSubscriptions)
        _closeResource(subscription.cancel(), 'cancel accept'),
    ]);

    for (final socket in _openSockets.toList(growable: false)) {
      socket.destroy();
    }
    await Future.wait<void>(<Future<void>>[
      for (final reader in _readers.toList(growable: false))
        _closeResource(reader.cancel(), 'cancel reader'),
      for (final tunnel in _tunnels.toList(growable: false))
        _closeResource(tunnel.close(), 'close tunnel'),
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
        _writeHttpError(client, 400, 'Bad proxy request.');
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
        _writeHttpError(client, 431, 'Proxy request header is too large.');
      } else {
        client.destroy();
      }
    } on SocketException catch (error, stack) {
      if (!_closed) {
        silentLog('ai_sandbox_proxy', 'http connect', error, stack);
        _writeHttpError(client, 502, 'Proxy destination is unavailable.');
      } else {
        client.destroy();
      }
    } on TimeoutException catch (error, stack) {
      if (!_closed) {
        silentLog('ai_sandbox_proxy', 'http connect', error, stack);
        _writeHttpError(client, 504, 'Proxy destination timed out.');
      } else {
        client.destroy();
      }
    } catch (error, stack) {
      if (!_closed) {
        silentLog('ai_sandbox_proxy', 'http client', error, stack);
      }
      client.destroy();
    } finally {
      _readers.remove(reader);
      if (!reader.isHandedOff) {
        _clientSockets.remove(client);
        await _closeResource(
          reader.cancel(destroySocket: false),
          'cancel HTTP handshake reader',
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
      _startTunnel(client: client, remote: remote, reader: reader);
    } catch (_) {
      if (!reader.isHandedOff) remote.destroy();
      rethrow;
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
        silentLog('ai_sandbox_proxy', 'socks connect', error, stack);
        _writeSocksReply(client, 0x05);
      } else {
        client.destroy();
      }
    } on TimeoutException catch (error, stack) {
      if (!_closed) {
        silentLog('ai_sandbox_proxy', 'socks connect', error, stack);
        _writeSocksReply(client, 0x04);
      } else {
        client.destroy();
      }
    } catch (error, stack) {
      if (!_closed) {
        silentLog('ai_sandbox_proxy', 'socks client', error, stack);
      }
      client.destroy();
    } finally {
      _readers.remove(reader);
      if (!reader.isHandedOff) {
        _clientSockets.remove(client);
        await _closeResource(
          reader.cancel(destroySocket: false),
          'cancel SOCKS handshake reader',
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
          'Sandbox proxy denied $host:$port by rule "${rule.pattern}".',
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
    return _DomainDecision.blocked(
      'Sandbox proxy blocked $host:$port because it is not in the allowed domain list.',
    );
  }

  bool _matchesRule(AiSandboxPatternRule rule, String host, int port) {
    final pattern = rule.pattern.trim();
    if (pattern.isEmpty) return false;
    final values = <String>[host, '$host:$port'];
    try {
      final regex = rule.matchMode == AiDenyCommandMatchMode.regex
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
    // DNS treats a terminal dot as the absolute-name marker. Rules should see
    // the canonical host so `example.com.` cannot bypass `example.com`.
    while (host.length > 1 && host.endsWith('.')) {
      host = host.substring(0, host.length - 1);
    }
    return host;
  }

  void _startTunnel({
    required Socket client,
    required Socket remote,
    required _SocketReadBuffer reader,
  }) {
    late final _SocketTunnel tunnel;
    tunnel = _SocketTunnel(
      client: client,
      remote: remote,
      idleTimeout: limits.idleTimeout,
      maxDuration: limits.maxConnectionDuration,
      onClosed: () {
        _tunnels.remove(tunnel);
        _clientSockets.remove(client);
      },
    );
    _tunnels.add(tunnel);
    try {
      tunnel.start(reader.handOff());
    } catch (_) {
      unawaited(tunnel.close());
      rethrow;
    }
  }

  void _writeHttpError(Socket client, int status, String message) {
    final reason = switch (status) {
      400 => 'Bad Request',
      403 => 'Forbidden',
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
              silentLog('ai_sandbox_proxy', 'close socket', error, stack);
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
              silentLog('ai_sandbox_proxy', 'socket done', error, stack);
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
      throw StateError('Proxy tunnel has already been started or closed.');
    }
    _resetIdleTimer();
    _maxDurationTimer = Timer(maxDuration, () => unawaited(close()));
    _clientToRemote = clientInput
        .asyncMap((data) {
          return _forward(data, remote);
        })
        .listen(
          null,
          onDone: () => _onInputDone(clientToRemote: true),
          onError: (Object error, StackTrace stack) {
            _onPipeError('client pipe', error, stack);
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
            _onPipeError('remote pipe', error, stack);
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
      unawaited(close());
    }
  }

  void _halfClose(Socket socket) {
    unawaited(
      socket.close().catchError((Object error, StackTrace stack) {
        if (!_closed) {
          silentLog('ai_sandbox_proxy', 'half close', error, stack);
        }
        socket.destroy();
      }),
    );
  }

  void _onPipeError(String where, Object error, StackTrace stack) {
    if (_closed) return;
    silentLog('ai_sandbox_proxy', where, error, stack);
    unawaited(close());
  }

  void _resetIdleTimer() {
    if (_closed) return;
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, () => unawaited(close()));
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
      silentLog('ai_sandbox_proxy', 'cancel tunnel', error, stack);
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
  });

  final String method;
  final String target;
  final String version;
  final List<String> headerLines;
  final String host;
  final int port;
  final String forwardTarget;
  final String forwardHostHeader;

  static final RegExp _headerLineSeparatorPattern = RegExp(r'\r?\n');
  static final RegExp _requestLineWhitespacePattern = RegExp(r'\s+');
  static final RegExp _methodPattern = RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$");
  static final RegExp _headerNamePattern = RegExp(
    r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$",
  );

  bool get isConnect => method.toUpperCase() == 'CONNECT';

  String get forwardHeader {
    final buffer = StringBuffer()..writeln('$method $forwardTarget $version');
    var wroteHost = false;
    for (final line in headerLines) {
      final separator = line.indexOf(':');
      final name = separator < 0
          ? ''
          : lowercaseStringFromValue(line.substring(0, separator));
      if (name == 'proxy-connection' || name == 'proxy-authorization') {
        continue;
      }
      if (name == 'host') {
        if (!wroteHost) buffer.writeln('Host: $forwardHostHeader');
        wroteHost = true;
        continue;
      }
      buffer.writeln(line);
    }
    if (!wroteHost) buffer.writeln('Host: $forwardHostHeader');
    buffer.writeln();
    return buffer.toString().replaceAll('\n', '\r\n');
  }

  static _HttpProxyRequest? tryParse(String rawHeader) {
    final lines = rawHeader.split(_headerLineSeparatorPattern);
    if (lines.isEmpty) return null;
    final requestLine = lines.first.trim();
    final parts = requestLine.split(_requestLineWhitespacePattern);
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
      if (name == 'host' && headers.containsKey(name)) return null;
      if ((name == 'content-length' || name == 'transfer-encoding') &&
          headers.containsKey(name)) {
        return null;
      }
      final value = line.substring(separator + 1).trim();
      if (_containsInvalidHeaderText(value, allowTab: true)) return null;
      headers[name] = value;
    }
    if (headers.containsKey('content-length') &&
        headers.containsKey('transfer-encoding')) {
      return null;
    }
    final contentLength = headers['content-length'];
    if (contentLength != null) {
      final parsedContentLength = int.tryParse(contentLength);
      if (parsedContentLength == null || parsedContentLength < 0) return null;
    }
    final transferEncoding = lowercaseStringFromValue(
      headers['transfer-encoding'],
    );
    if (transferEncoding.isNotEmpty && transferEncoding != 'chunked') {
      return null;
    }

    if (method.toUpperCase() == 'CONNECT') {
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
      );
    }

    final uri = Uri.tryParse(target);
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
      final scheme = uri.scheme.toLowerCase();
      if (scheme != 'http' && scheme != 'https') return null;
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
          _error = const FormatException(
            'Proxy handshake read-ahead is too large.',
          );
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

  static const int _defaultMaxHeaderBytes = 64 * 1024;
  static const int _maxReadAheadBytes = 64 * 1024;
  static const int _maxExactReadBytes = 64 * 1024;
  static const Duration _cancelTimeout = Duration(seconds: 2);

  final Socket socket;
  final Duration readTimeout;
  final Stopwatch _readStopwatch;
  late final StreamSubscription<Uint8List> _subscription;
  final List<int> _buffer = <int>[];
  Completer<void>? _waiter;
  int _activeBufferLimit = 0;
  bool _operationActive = false;
  bool _paused = false;
  bool _cancelled = false;
  bool _handedOff = false;
  bool _done = false;
  Object? _error;
  StackTrace? _stack;

  bool get isHandedOff => _handedOff;

  Future<String?> readHeader({int maxBytes = _defaultMaxHeaderBytes}) async {
    final effectiveMaxBytes = maxBytes > 0 ? maxBytes : _defaultMaxHeaderBytes;
    return _readBounded(effectiveMaxBytes + _maxReadAheadBytes, () async {
      var scannedLength = 0;
      while (true) {
        _throwIfErrored();
        final end = _findHeaderEnd(
          _buffer,
          startIndex: scannedLength > 3 ? scannedLength - 3 : 0,
        );
        if (end >= 0) {
          if (end > effectiveMaxBytes) {
            throw const FormatException('Proxy header is too large.');
          }
          final header = _buffer.sublist(0, end);
          _buffer.removeRange(0, end);
          return latin1.decode(header);
        }
        if (_buffer.length >= effectiveMaxBytes) {
          throw const FormatException('Proxy header is too large.');
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

  Stream<Uint8List> handOff() {
    if (_operationActive || _handedOff || _cancelled) {
      throw StateError('Proxy socket reader cannot be handed off.');
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
      throw StateError('Proxy socket reader is not available.');
    }
    _operationActive = true;
    _activeBufferLimit = bufferLimit;
    try {
      final remaining = readTimeout - _readStopwatch.elapsed;
      if (remaining <= Duration.zero) {
        await _abortTimedOutRead();
        return null;
      }
      return await action().timeout(remaining);
    } on TimeoutException {
      await _abortTimedOutRead();
      return null;
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
    try {
      await _subscription.cancel().timeout(_cancelTimeout);
    } catch (error, stack) {
      silentLog('ai_sandbox_proxy', 'cancel handshake reader', error, stack);
    }
  }

  int _findHeaderEnd(List<int> bytes, {int startIndex = 0}) {
    final crlfStart = startIndex > 3 ? startIndex : 3;
    for (var index = crlfStart; index < bytes.length; index++) {
      if (bytes[index - 3] == 13 &&
          bytes[index - 2] == 10 &&
          bytes[index - 1] == 13 &&
          bytes[index] == 10) {
        return index + 1;
      }
    }
    final lfStart = startIndex > 1 ? startIndex : 1;
    for (var index = lfStart; index < bytes.length; index++) {
      if (bytes[index - 1] == 10 && bytes[index] == 10) {
        return index + 1;
      }
    }
    return -1;
  }
}
