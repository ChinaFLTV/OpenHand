import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../../app/support/silent_log.dart';
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
  bool _closed = false;

  List<int> get loopbackPorts => <int>[
    httpPort,
    if (socksPort != null) socksPort!,
  ];

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _close();
  }
}

class AiSandboxProxyService {
  Future<AiSandboxProxyLease> start({
    required AiSandboxSettings settings,
  }) async {
    final instance = _SandboxProxyInstance(settings);
    return instance.start();
  }
}

class _SandboxProxyInstance {
  _SandboxProxyInstance(this.settings);

  static const int _maxOpenSockets = 256;

  final AiSandboxSettings settings;
  final List<ServerSocket> _servers = <ServerSocket>[];
  final Set<Socket> _openSockets = <Socket>{};
  bool _closed = false;

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
      httpServer.listen(
        _handleHttpClient,
        onError: (Object error, StackTrace stack) {
          silentLog('ai_sandbox_proxy', 'http accept', error, stack);
        },
      );

      ServerSocket? socksServer;
      if (settings.socksProxyPort > 0) {
        socksServer = await _bind(settings.socksProxyPort);
        _servers.add(socksServer);
        socksServer.listen(
          _handleSocksClient,
          onError: (Object error, StackTrace stack) {
            silentLog('ai_sandbox_proxy', 'socks accept', error, stack);
          },
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

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final socket in _openSockets.toList(growable: false)) {
      socket.destroy();
    }
    _openSockets.clear();
    for (final server in _servers) {
      try {
        await server.close();
      } catch (error, stack) {
        silentLog('ai_sandbox_proxy', 'close server', error, stack);
      }
    }
    _servers.clear();
  }

  Future<void> _handleHttpClient(Socket client) async {
    if (!_trackSocket(client)) return;
    final reader = _SocketReadBuffer(client);
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
    } catch (error, stack) {
      silentLog('ai_sandbox_proxy', 'http client', error, stack);
      client.destroy();
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
      timeout: const Duration(seconds: 20),
    );
    if (!_trackSocket(remote)) {
      client.destroy();
      return;
    }
    client.add(
      latin1.encode(
        'HTTP/1.1 200 Connection Established\r\n'
        'Proxy-Agent: OpenHandSandboxProxy\r\n'
        '\r\n',
      ),
    );
    _pipeBufferedClientToRemote(reader, remote);
    _pipeRemoteToClient(remote, client);
  }

  Future<void> _handleHttpForward(
    Socket client,
    _SocketReadBuffer reader,
    _HttpProxyRequest request,
  ) async {
    final remote = await Socket.connect(
      request.host,
      request.port,
      timeout: const Duration(seconds: 20),
    );
    if (!_trackSocket(remote)) {
      client.destroy();
      return;
    }
    remote.add(latin1.encode(request.forwardHeader));
    _pipeBufferedClientToRemote(reader, remote);
    _pipeRemoteToClient(remote, client);
  }

  Future<void> _handleSocksClient(Socket client) async {
    if (!_trackSocket(client)) return;
    final reader = _SocketReadBuffer(client);
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
      client.add(Uint8List.fromList(<int>[0x05, 0x00]));

      final requestHead = await reader.readExactly(4);
      if (requestHead == null || requestHead[0] != 0x05) {
        client.destroy();
        return;
      }
      if (requestHead[1] != 0x01) {
        _writeSocksReply(client, 0x07);
        return;
      }
      final address = await _readSocksAddress(reader, requestHead[3]);
      final portBytes = await reader.readExactly(2);
      if (address == null || portBytes == null) {
        client.destroy();
        return;
      }
      final port = ByteData.sublistView(portBytes).getUint16(0);
      final decision = _domainDecision(address, port);
      if (!decision.allowed) {
        _writeSocksReply(client, 0x02);
        return;
      }
      final remote = await Socket.connect(
        address,
        port,
        timeout: const Duration(seconds: 20),
      );
      if (!_trackSocket(remote)) {
        client.destroy();
        return;
      }
      _writeSocksReply(client, 0x00);
      _pipeBufferedClientToRemote(reader, remote);
      _pipeRemoteToClient(remote, client);
    } catch (error, stack) {
      silentLog('ai_sandbox_proxy', 'socks client', error, stack);
      client.destroy();
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
        final bytes = await reader.readExactly(lengthBytes[0]);
        if (bytes == null) return null;
        return utf8.decode(bytes, allowMalformed: true);
      case 0x04:
        final bytes = await reader.readExactly(16);
        if (bytes == null) return null;
        return InternetAddress.fromRawAddress(bytes).address;
      default:
        return null;
    }
  }

  void _writeSocksReply(Socket client, int status) {
    client.add(
      Uint8List.fromList(<int>[0x05, status, 0x00, 0x01, 0, 0, 0, 0, 0, 0]),
    );
    if (status != 0x00) _closeSocket(client);
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
    var host = value.trim().toLowerCase();
    if (host.startsWith('[') && host.endsWith(']')) {
      host = host.substring(1, host.length - 1);
    }
    return host;
  }

  void _pipeBufferedClientToRemote(_SocketReadBuffer reader, Socket remote) {
    reader.handOff(
      (data) {
        _addToSocket(remote, data, 'client to remote');
      },
      onDone: () => remote.destroy(),
      onError: (Object error, StackTrace stack) {
        silentLog('ai_sandbox_proxy', 'client pipe', error, stack);
        remote.destroy();
      },
    );
  }

  void _pipeRemoteToClient(Socket remote, Socket client) {
    remote.listen(
      (data) {
        _addToSocket(client, data, 'remote to client');
      },
      onDone: () => client.destroy(),
      onError: (Object error, StackTrace stack) {
        silentLog('ai_sandbox_proxy', 'remote pipe', error, stack);
        client.destroy();
      },
      cancelOnError: true,
    );
  }

  void _addToSocket(Socket socket, Uint8List data, String where) {
    try {
      socket.add(data);
    } catch (error, stack) {
      silentLog('ai_sandbox_proxy', where, error, stack);
      socket.destroy();
    }
  }

  void _writeHttpError(Socket client, int status, String message) {
    final reason = status == 403
        ? 'Forbidden'
        : status == 400
        ? 'Bad Request'
        : 'Proxy Error';
    final body = utf8.encode('$message\n');
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
  }

  void _closeSocket(Socket socket) {
    unawaited(
      socket.close().catchError((Object error, StackTrace stack) {
        silentLog('ai_sandbox_proxy', 'close socket', error, stack);
      }),
    );
  }

  bool _trackSocket(Socket socket) {
    if (_openSockets.length >= _maxOpenSockets) {
      socket.destroy();
      return false;
    }
    _openSockets.add(socket);
    unawaited(
      socket.done
          .catchError((Object error, StackTrace stack) {
            silentLog('ai_sandbox_proxy', 'socket done', error, stack);
          })
          .whenComplete(() {
            _openSockets.remove(socket);
          }),
    );
    return true;
  }

  String _rulePatterns(List<AiSandboxPatternRule> rules) {
    return trimmedNonEmptyStrings(rules.map((item) => item.pattern)).join(',');
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
  });

  final String method;
  final String target;
  final String version;
  final List<String> headerLines;
  final String host;
  final int port;
  final String forwardTarget;

  bool get isConnect => method.toUpperCase() == 'CONNECT';

  String get forwardHeader {
    final buffer = StringBuffer()..writeln('$method $forwardTarget $version');
    for (final line in headerLines) {
      if (line.toLowerCase().startsWith('proxy-connection:')) continue;
      buffer.writeln(line);
    }
    buffer.writeln();
    return buffer.toString().replaceAll('\n', '\r\n');
  }

  static _HttpProxyRequest? tryParse(String rawHeader) {
    final lines = rawHeader.split(RegExp(r'\r?\n'));
    if (lines.isEmpty) return null;
    final requestLine = lines.first.trim();
    final parts = requestLine.split(RegExp(r'\s+'));
    if (parts.length < 3) return null;
    final method = parts[0];
    final target = parts[1];
    final version = parts[2];
    final headerLines = trimRightNonEmptyLines(lines.skip(1));
    final headers = <String, String>{};
    for (final line in headerLines) {
      final separator = line.indexOf(':');
      if (separator <= 0) continue;
      headers[line.substring(0, separator).trim().toLowerCase()] = line
          .substring(separator + 1)
          .trim();
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
      );
    }

    final uri = Uri.tryParse(target);
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
      final defaultPort = uri.scheme.toLowerCase() == 'https' ? 443 : 80;
      return _HttpProxyRequest(
        method: method,
        target: target,
        version: version,
        headerLines: headerLines,
        host: uri.host,
        port: uri.hasPort ? uri.port : defaultPort,
        forwardTarget: _originForm(uri),
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
    );
  }

  static String _originForm(Uri uri) {
    final path = uri.path.isEmpty ? '/' : uri.path;
    if (uri.query.isEmpty) return path;
    return '$path?${uri.query}';
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
      final port = rest.startsWith(':')
          ? optionalPositiveIntFromValue(rest.substring(1))
          : null;
      return _HostPort(host, _normalizePort(port, defaultPort));
    }
    final colon = trimmed.lastIndexOf(':');
    if (colon > 0 && trimmed.indexOf(':') == colon) {
      final port = optionalPositiveIntFromValue(trimmed.substring(colon + 1));
      return _HostPort(
        trimmed.substring(0, colon),
        _normalizePort(port, defaultPort),
      );
    }
    return _HostPort(trimmed, defaultPort);
  }

  static int _normalizePort(int? port, int defaultPort) {
    if (port == null || port <= 0 || port > 65535) return defaultPort;
    return port;
  }
}

class _DomainDecision {
  const _DomainDecision.allowed() : allowed = true, reason = '';
  const _DomainDecision.blocked(this.reason) : allowed = false;

  final bool allowed;
  final String reason;
}

class _SocketReadBuffer {
  _SocketReadBuffer(this.socket) {
    _subscription = socket.listen(
      (data) {
        _buffer.addAll(data);
        _wakeWaiter();
      },
      onDone: () {
        _done = true;
        _wakeWaiter();
      },
      onError: (Object error, StackTrace stack) {
        _error = error;
        _stack = stack;
        _wakeWaiter();
      },
      cancelOnError: true,
    );
  }

  final Socket socket;
  late final StreamSubscription<Uint8List> _subscription;
  final List<int> _buffer = <int>[];
  Completer<void>? _waiter;
  bool _done = false;
  Object? _error;
  StackTrace? _stack;

  Future<String?> readHeader({
    int maxBytes = 64 * 1024,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    return _withTimeout(timeout, () async {
      while (true) {
        _throwIfErrored();
        final end = _findHeaderEnd(_buffer);
        if (end >= 0) {
          final header = _buffer.sublist(0, end);
          _buffer.removeRange(0, end);
          return latin1.decode(header);
        }
        if (_buffer.length > maxBytes) {
          throw const FormatException('Proxy header is too large.');
        }
        if (_done) return null;
        await _waitForData();
      }
    });
  }

  Future<Uint8List?> readExactly(
    int count, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    return _withTimeout(timeout, () async {
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

  void handOff(
    void Function(Uint8List data) onData, {
    required void Function() onDone,
    required void Function(Object error, StackTrace stack) onError,
  }) {
    final pending = _takePending();
    if (pending.isNotEmpty) onData(pending);
    if (_done) {
      onDone();
      return;
    }
    if (_error != null) {
      onError(_error!, _stack ?? StackTrace.current);
      return;
    }
    _subscription
      ..onData(onData)
      ..onDone(onDone)
      ..onError(onError);
  }

  Uint8List _takePending() {
    if (_buffer.isEmpty) return Uint8List(0);
    final pending = Uint8List.fromList(_buffer);
    _buffer.clear();
    return pending;
  }

  Future<T?> _withTimeout<T>(
    Duration timeout,
    Future<T?> Function() action,
  ) async {
    try {
      return await action().timeout(timeout);
    } on TimeoutException {
      socket.destroy();
      return null;
    }
  }

  Future<void> _waitForData() {
    _waiter ??= Completer<void>();
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

  int _findHeaderEnd(List<int> bytes) {
    for (var index = 3; index < bytes.length; index++) {
      if (bytes[index - 3] == 13 &&
          bytes[index - 2] == 10 &&
          bytes[index - 1] == 13 &&
          bytes[index] == 10) {
        return index + 1;
      }
    }
    for (var index = 1; index < bytes.length; index++) {
      if (bytes[index - 1] == 10 && bytes[index] == 10) {
        return index + 1;
      }
    }
    return -1;
  }
}
