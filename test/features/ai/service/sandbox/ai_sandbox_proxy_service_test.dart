import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_deny_command_rule.dart';
import 'package:openhand/features/ai/model/ai_sandbox_settings.dart';
import 'package:openhand/features/ai/service/sandbox/ai_sandbox_proxy_service.dart';

void main() {
  group('AiSandboxProxyService', () {
    test('validates resource limits', () {
      expect(
        () => AiSandboxProxyService(handshakeTimeout: Duration.zero),
        throwsArgumentError,
      );
      expect(
        () => AiSandboxProxyService(maxConcurrentConnections: 0),
        throwsArgumentError,
      );
    });

    test('forwards HTTP with normalized target and proxy headers', () async {
      final upstream = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(upstream.close);
      final upstreamRequest = Completer<String>();
      final upstreamSubscription = upstream.listen((socket) {
        unawaited(() async {
          final reader = _TestSocketReader(socket);
          try {
            final header = await reader.readHeader();
            final body = await reader.readExactly(4);
            upstreamRequest.complete('$header${utf8.decode(body)}');
            socket.add(
              utf8.encode(
                'HTTP/1.1 200 OK\r\n'
                'Content-Length: 2\r\n'
                'Connection: close\r\n'
                '\r\n'
                'ok',
              ),
            );
            await socket.close();
          } catch (error, stack) {
            if (!upstreamRequest.isCompleted) {
              upstreamRequest.completeError(error, stack);
            }
            socket.destroy();
          } finally {
            await reader.cancel();
          }
        }());
      });
      addTearDown(upstreamSubscription.cancel);

      final lease = await _startProxy();
      addTearDown(lease.close);
      final client = await Socket.connect(
        InternetAddress.loopbackIPv4,
        lease.httpPort,
      );
      addTearDown(client.destroy);
      final reader = _TestSocketReader(client);
      addTearDown(reader.cancel);
      client.add(
        latin1.encode(
          'POST http://127.0.0.1:${upstream.port}/v1?q=1 HTTP/1.1\r\n'
          'Host: should-not-be-forwarded.invalid\r\n'
          'Proxy-Authorization: Basic secret\r\n'
          'Content-Length: 4\r\n'
          '\r\n'
          'data',
        ),
      );

      final response = latin1.decode(
        await reader.readToEnd().timeout(const Duration(seconds: 2)),
      );
      final request = await upstreamRequest.future.timeout(
        const Duration(seconds: 2),
      );
      expect(response, contains('HTTP/1.1 200 OK'));
      expect(response, endsWith('ok'));
      expect(request, startsWith('POST /v1?q=1 HTTP/1.1\r\n'));
      expect(request, contains('Host: 127.0.0.1:${upstream.port}\r\n'));
      expect(request, isNot(contains('should-not-be-forwarded.invalid')));
      expect(request, isNot(contains('Proxy-Authorization')));
      expect(request, endsWith('data'));
    });

    test('rejects a header whose terminator exceeds the limit', () async {
      final lease = await _startProxy();
      addTearDown(lease.close);
      final client = await Socket.connect(
        InternetAddress.loopbackIPv4,
        lease.httpPort,
      );
      addTearDown(client.destroy);
      final reader = _TestSocketReader(client);
      addTearDown(reader.cancel);
      client.add(
        latin1.encode(
          'GET http://127.0.0.1:9/ HTTP/1.1\r\n'
          'X-Oversized: ${'a' * (64 * 1024)}\r\n'
          '\r\n',
        ),
      );

      final response = latin1.decode(
        await reader.readToEnd().timeout(const Duration(seconds: 2)),
      );
      expect(response, startsWith('HTTP/1.1 431 '));
    });

    test('rejects malformed explicit destination ports', () async {
      final lease = await _startProxy();
      addTearDown(lease.close);
      final client = await Socket.connect(
        InternetAddress.loopbackIPv4,
        lease.httpPort,
      );
      addTearDown(client.destroy);
      final reader = _TestSocketReader(client);
      addTearDown(reader.cancel);
      client.add(
        latin1.encode(
          'CONNECT 127.0.0.1:not-a-port HTTP/1.1\r\n'
          'Host: 127.0.0.1:not-a-port\r\n'
          '\r\n',
        ),
      );

      final response = latin1.decode(
        await reader.readToEnd().timeout(const Duration(seconds: 1)),
      );
      expect(response, startsWith('HTTP/1.1 400 '));
    });

    test(
      'canonicalizes terminal DNS dots before applying deny rules',
      () async {
        final settings = AiSandboxSettings.defaults().copyWith(
          httpProxyPort: 0,
          deniedDomains: const <AiSandboxPatternRule>[
            AiSandboxPatternRule(
              id: 'deny-loopback',
              pattern: '127.0.0.1',
              matchMode: AiDenyCommandMatchMode.simple,
            ),
          ],
        );
        final lease = await AiSandboxProxyService().start(settings: settings);
        addTearDown(lease.close);
        final client = await Socket.connect(
          InternetAddress.loopbackIPv4,
          lease.httpPort,
        );
        addTearDown(client.destroy);
        final reader = _TestSocketReader(client);
        addTearDown(reader.cancel);
        client.add(
          latin1.encode(
            'CONNECT 127.0.0.1.:9 HTTP/1.1\r\n'
            'Host: 127.0.0.1.:9\r\n'
            '\r\n',
          ),
        );

        final response = latin1.decode(
          await reader.readToEnd().timeout(const Duration(seconds: 1)),
        );
        expect(response, startsWith('HTTP/1.1 403 '));
      },
    );

    test('rejects control characters in forwarded header values', () async {
      final lease = await _startProxy();
      addTearDown(lease.close);
      final client = await Socket.connect(
        InternetAddress.loopbackIPv4,
        lease.httpPort,
      );
      addTearDown(client.destroy);
      final reader = _TestSocketReader(client);
      addTearDown(reader.cancel);
      client.add(<int>[
        ...latin1.encode(
          'GET http://127.0.0.1:9/ HTTP/1.1\r\n'
          'Host: 127.0.0.1:9\r\n'
          'X-Unsafe: before',
        ),
        0,
        ...latin1.encode('after\r\n\r\n'),
      ]);

      final response = latin1.decode(
        await reader.readToEnd().timeout(const Duration(seconds: 1)),
      );
      expect(response, startsWith('HTTP/1.1 400 '));
    });

    test('rejects ambiguous HTTP request framing', () async {
      final lease = await _startProxy();
      addTearDown(lease.close);
      final client = await Socket.connect(
        InternetAddress.loopbackIPv4,
        lease.httpPort,
      );
      addTearDown(client.destroy);
      final reader = _TestSocketReader(client);
      addTearDown(reader.cancel);
      client.add(
        latin1.encode(
          'POST http://127.0.0.1:9/ HTTP/1.1\r\n'
          'Host: 127.0.0.1:9\r\n'
          'Content-Length: 4\r\n'
          'Transfer-Encoding: chunked\r\n'
          '\r\n',
        ),
      );

      final response = latin1.decode(
        await reader.readToEnd().timeout(const Duration(seconds: 1)),
      );
      expect(response, startsWith('HTTP/1.1 400 '));
    });

    test('bounds a stalled handshake and closes the client', () async {
      final lease = await _startProxy(
        service: AiSandboxProxyService(
          handshakeTimeout: const Duration(milliseconds: 80),
        ),
      );
      addTearDown(lease.close);
      final client = await Socket.connect(
        InternetAddress.loopbackIPv4,
        lease.httpPort,
      );
      addTearDown(client.destroy);
      final reader = _TestSocketReader(client);
      addTearDown(reader.cancel);

      expect(
        await reader.readToEnd().timeout(const Duration(seconds: 2)),
        isEmpty,
      );
    });

    test(
      'enforces the concurrent client limit and releases capacity',
      () async {
        final lease = await _startProxy(
          service: AiSandboxProxyService(
            handshakeTimeout: const Duration(seconds: 2),
            maxConcurrentConnections: 1,
          ),
        );
        addTearDown(lease.close);
        final first = await Socket.connect(
          InternetAddress.loopbackIPv4,
          lease.httpPort,
        );
        addTearDown(first.destroy);
        await Future<void>.delayed(const Duration(milliseconds: 30));

        final rejected = await Socket.connect(
          InternetAddress.loopbackIPv4,
          lease.httpPort,
        );
        addTearDown(rejected.destroy);
        final rejectedReader = _TestSocketReader(rejected);
        addTearDown(rejectedReader.cancel);
        expect(
          await rejectedReader.readToEndAllowReset().timeout(
            const Duration(seconds: 1),
          ),
          isEmpty,
        );

        first.destroy();
        await Future<void>.delayed(const Duration(milliseconds: 60));
        final accepted = await Socket.connect(
          InternetAddress.loopbackIPv4,
          lease.httpPort,
        );
        addTearDown(accepted.destroy);
        final acceptedReader = _TestSocketReader(accepted);
        addTearDown(acceptedReader.cancel);
        accepted.add(latin1.encode('invalid\r\n\r\n'));
        final response = latin1.decode(
          await acceptedReader.readToEnd().timeout(const Duration(seconds: 1)),
        );
        expect(response, startsWith('HTTP/1.1 400 '));
      },
    );

    test('rejects SOCKS authentication methods it does not support', () async {
      final lease = await _startProxy(enableSocks: true);
      addTearDown(lease.close);
      final client = await Socket.connect(
        InternetAddress.loopbackIPv4,
        lease.socksPort!,
      );
      addTearDown(client.destroy);
      final reader = _TestSocketReader(client);
      addTearDown(reader.cancel);
      client.add(Uint8List.fromList(<int>[0x05, 0x01, 0x02]));

      expect(await reader.readExactly(2), <int>[0x05, 0xff]);
      expect(
        await reader.readToEndAllowReset().timeout(const Duration(seconds: 1)),
        isEmpty,
      );
    });

    test('forwards SOCKS traffic with bounded backpressure', () async {
      final upstream = await _startEchoServer();
      addTearDown(upstream.close);
      final lease = await _startProxy(enableSocks: true);
      addTearDown(lease.close);
      final client = await Socket.connect(
        InternetAddress.loopbackIPv4,
        lease.socksPort!,
      );
      addTearDown(client.destroy);
      final reader = _TestSocketReader(client);
      addTearDown(reader.cancel);

      client.add(Uint8List.fromList(<int>[0x05, 0x01, 0x00]));
      expect(await reader.readExactly(2), <int>[0x05, 0x00]);
      client.add(
        Uint8List.fromList(<int>[
          0x05,
          0x01,
          0x00,
          0x01,
          127,
          0,
          0,
          1,
          upstream.port >> 8,
          upstream.port & 0xff,
        ]),
      );
      expect((await reader.readExactly(10))[1], 0x00);
      client.add(utf8.encode('through-socks'));
      expect(
        utf8.decode(await reader.readExactly('through-socks'.length)),
        'through-socks',
      );
    });

    test('preserves the reverse stream after a client half-close', () async {
      final upstream = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(upstream.close);
      final received = Completer<String>();
      final upstreamSubscription = upstream.listen((socket) {
        unawaited(() async {
          final reader = _TestSocketReader(socket);
          try {
            final request = utf8.decode(await reader.readToEnd());
            received.complete(request);
            socket.add(utf8.encode('response-after-eof'));
            await socket.close();
          } catch (error, stack) {
            if (!received.isCompleted) received.completeError(error, stack);
            socket.destroy();
          } finally {
            await reader.cancel();
          }
        }());
      });
      addTearDown(upstreamSubscription.cancel);
      final lease = await _startProxy(
        service: AiSandboxProxyService(
          idleTimeout: const Duration(seconds: 2),
          maxConnectionDuration: const Duration(seconds: 5),
        ),
      );
      addTearDown(lease.close);
      final client = await _connectHttpTunnel(lease.httpPort, upstream.port);
      addTearDown(client.socket.destroy);
      addTearDown(client.reader.cancel);

      client.socket.add(utf8.encode('request-before-eof'));
      await client.socket.flush();
      await client.socket.close();

      expect(
        await received.future.timeout(const Duration(seconds: 2)),
        'request-before-eof',
      );
      expect(
        utf8.decode(
          await client.reader.readToEnd().timeout(const Duration(seconds: 2)),
        ),
        'response-after-eof',
      );
    });

    test('closes an idle established tunnel', () async {
      final upstream = await _startEchoServer();
      addTearDown(upstream.close);
      final lease = await _startProxy(
        service: AiSandboxProxyService(
          idleTimeout: const Duration(milliseconds: 100),
          maxConnectionDuration: const Duration(seconds: 2),
        ),
      );
      addTearDown(lease.close);
      final client = await _connectHttpTunnel(lease.httpPort, upstream.port);
      addTearDown(client.socket.destroy);
      addTearDown(client.reader.cancel);

      expect(
        await client.reader.readToEnd().timeout(const Duration(seconds: 2)),
        isEmpty,
      );
    });

    test('closes a tunnel at its total lifetime limit', () async {
      final upstream = await _startEchoServer();
      addTearDown(upstream.close);
      final lease = await _startProxy(
        service: AiSandboxProxyService(
          idleTimeout: const Duration(seconds: 2),
          maxConnectionDuration: const Duration(milliseconds: 100),
        ),
      );
      addTearDown(lease.close);
      final client = await _connectHttpTunnel(lease.httpPort, upstream.port);
      addTearDown(client.socket.destroy);
      addTearDown(client.reader.cancel);

      expect(
        await client.reader.readToEnd().timeout(const Duration(seconds: 2)),
        isEmpty,
      );
    });

    test('close is single-flight and tears down active clients', () async {
      final lease = await _startProxy();
      final client = await Socket.connect(
        InternetAddress.loopbackIPv4,
        lease.httpPort,
      );
      addTearDown(client.destroy);
      final reader = _TestSocketReader(client);
      addTearDown(reader.cancel);

      await Future.wait<void>(<Future<void>>[lease.close(), lease.close()]);
      expect(
        await reader.readToEndAllowReset().timeout(const Duration(seconds: 1)),
        isEmpty,
      );
      await expectLater(
        Socket.connect(InternetAddress.loopbackIPv4, lease.httpPort),
        throwsA(isA<SocketException>()),
      );
    });
  });
}

Future<AiSandboxProxyLease> _startProxy({
  AiSandboxProxyService? service,
  bool enableSocks = false,
}) async {
  final settings = AiSandboxSettings.defaults().copyWith(
    httpProxyPort: 0,
    socksProxyPort: enableSocks ? await _unusedLoopbackPort() : 0,
  );
  return (service ?? AiSandboxProxyService()).start(settings: settings);
}

Future<int> _unusedLoopbackPort() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = server.port;
  await server.close();
  return port;
}

Future<ServerSocket> _startEchoServer() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((socket) {
    socket.listen(
      socket.add,
      onDone: socket.close,
      onError: (Object _) => socket.destroy(),
      cancelOnError: true,
    );
  });
  return server;
}

Future<({Socket socket, _TestSocketReader reader})> _connectHttpTunnel(
  int proxyPort,
  int targetPort,
) async {
  final socket = await Socket.connect(InternetAddress.loopbackIPv4, proxyPort);
  final reader = _TestSocketReader(socket);
  socket.add(
    latin1.encode(
      'CONNECT 127.0.0.1:$targetPort HTTP/1.1\r\n'
      'Host: 127.0.0.1:$targetPort\r\n'
      '\r\n',
    ),
  );
  final responseHeader = await reader.readHeader().timeout(
    const Duration(seconds: 2),
  );
  expect(responseHeader, startsWith('HTTP/1.1 200 '));
  return (socket: socket, reader: reader);
}

class _TestSocketReader {
  _TestSocketReader(Socket socket) : _iterator = StreamIterator(socket);

  final StreamIterator<Uint8List> _iterator;
  final List<int> _buffer = <int>[];
  bool _done = false;

  Future<String> readHeader() async {
    while (true) {
      final end = _headerEnd(_buffer);
      if (end >= 0) {
        final bytes = _buffer.sublist(0, end);
        _buffer.removeRange(0, end);
        return latin1.decode(bytes);
      }
      if (!await _readMore()) {
        throw const SocketException('Socket closed before a complete header.');
      }
    }
  }

  Future<Uint8List> readExactly(int count) async {
    while (_buffer.length < count) {
      if (!await _readMore()) {
        throw const SocketException(
          'Socket closed before enough bytes arrived.',
        );
      }
    }
    final bytes = Uint8List.fromList(_buffer.sublist(0, count));
    _buffer.removeRange(0, count);
    return bytes;
  }

  Future<Uint8List> readToEnd() async {
    while (await _readMore()) {}
    return Uint8List.fromList(_buffer);
  }

  Future<Uint8List> readToEndAllowReset() async {
    try {
      return await readToEnd();
    } on SocketException {
      return Uint8List.fromList(_buffer);
    }
  }

  Future<bool> _readMore() async {
    if (_done) return false;
    if (!await _iterator.moveNext()) {
      _done = true;
      return false;
    }
    _buffer.addAll(_iterator.current);
    return true;
  }

  Future<void> cancel() => _iterator.cancel();

  int _headerEnd(List<int> bytes) {
    for (var index = 3; index < bytes.length; index++) {
      if (bytes[index - 3] == 13 &&
          bytes[index - 2] == 10 &&
          bytes[index - 1] == 13 &&
          bytes[index] == 10) {
        return index + 1;
      }
    }
    return -1;
  }
}
