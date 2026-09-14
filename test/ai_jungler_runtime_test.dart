import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/services/service/ai_jungler_runtime.dart';

const _testTimeout = Duration(seconds: 2);

void main() {
  late HttpServer server;
  late StreamIterator<HttpRequest> requests;
  late AiJunglerRuntime runtime;
  late Uri address;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    requests = StreamIterator(server);
    runtime = AiJunglerRuntime();
    address = Uri.parse('http://127.0.0.1:${server.port}');
  });

  tearDown(() async {
    await runtime.dispose();
    await server.close(force: true);
    await requests.cancel();
  });

  Future<HttpRequest> nextRequest() async {
    expect(await requests.moveNext().timeout(_testTimeout), isTrue);
    return requests.current;
  }

  Future<void> expectCancelled(Future<Object?> operation) => expectLater(
    operation.timeout(_testTimeout),
    throwsA(allOf(isA<Exception>(), isNot(isA<TimeoutException>()))),
  );

  test('停止时立即取消仍在等待响应头的外部连接', () async {
    final connecting = runtime.connectExternal(
      address: address,
      accessToken: 'test-token',
    );
    final cancelled = expectCancelled(connecting);
    await nextRequest();
    await runtime.stop();
    await cancelled;
    expect(runtime.client, isNull);
  });

  test('新连接取消旧连接，迟到的清理不关闭新客户端', () async {
    final first = runtime.connectExternal(
      address: address,
      accessToken: 'old-token',
    );
    final cancelled = expectCancelled(first);
    await nextRequest();
    final second = runtime.connectExternal(
      address: address,
      accessToken: 'new-token',
    );
    final request = await nextRequest();
    expect(
      request.headers.value(HttpHeaders.authorizationHeader),
      'Bearer new-token',
    );
    request.response.write('{}');
    await request.response.close();
    final client = await second.timeout(_testTimeout);
    await cancelled;
    expect(identical(runtime.client, client), isTrue);

    final health = client.health();
    final healthRequest = await nextRequest();
    healthRequest.response.write('{"version":"测试版本"}');
    await healthRequest.response.close();
    expect((await health.timeout(_testTimeout)).version, '测试版本');
  });

  test('释放时取消未完成连接，重复释放安全且拒绝新连接', () async {
    final connecting = runtime.connectExternal(
      address: address,
      accessToken: 'test-token',
    );
    final cancelled = expectCancelled(connecting);
    await nextRequest();
    final disposing = runtime.dispose();
    expect(identical(runtime.dispose(), disposing), isTrue);
    await disposing;
    await cancelled;
    await expectLater(
      runtime.connectExternal(address: address, accessToken: 'test-token'),
      throwsStateError,
    );
  });
}
