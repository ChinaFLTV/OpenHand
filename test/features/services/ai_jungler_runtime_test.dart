import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/services/service/ai_jungler_runtime.dart';

void main() {
  test('外部服务切换失败时保留当前可用连接', () async {
    final healthy = await _startHealthServer(HttpStatus.ok);
    final unavailable = await _startHealthServer(HttpStatus.serviceUnavailable);
    addTearDown(() => healthy.close(force: true));
    addTearDown(() => unavailable.close(force: true));
    final runtime = AiJunglerRuntime();
    addTearDown(runtime.dispose);

    final address = _addressOf(healthy);
    final current = await runtime.connectExternal(
      address: address,
      accessToken: 'current-token',
    );

    await expectLater(
      runtime.connectExternal(
        address: _addressOf(unavailable),
        accessToken: 'replacement-token',
      ),
      throwsException,
    );

    expect(runtime.client, same(current));
    expect(runtime.isConnectedToExternalAddress(address.toString()), isTrue);
    expect((await runtime.client!.health()).version, 'test');
  });

  test('外部服务拒绝会被忽略的非根路径', () async {
    final runtime = AiJunglerRuntime();
    addTearDown(runtime.dispose);

    await expectLater(
      runtime.connectExternal(
        address: Uri.parse('http://127.0.0.1:37821/proxy'),
        accessToken: 'token',
      ),
      throwsA(isA<FormatException>()),
    );
  });
}

Future<HttpServer> _startHealthServer(int statusCode) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    await request.drain<void>();
    request.response.statusCode = statusCode;
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode(<String, Object?>{
        'status': statusCode == HttpStatus.ok ? 'ready' : 'unavailable',
        'version': 'test',
        'databasePath': '/tmp/test.db',
        'uptimeSeconds': 1,
      }),
    );
    await request.response.close();
  });
  return server;
}

Uri _addressOf(HttpServer server) =>
    Uri.parse('http://${server.address.address}:${server.port}');
