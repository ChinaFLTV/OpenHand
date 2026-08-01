import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/services/service/ai_jungler_client.dart';

void main() {
  test('拒绝超过限制的普通响应', () async {
    final server = await _startServer((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.contentLength = 9 * 1024 * 1024;
      request.response.add(List<int>.filled(9 * 1024 * 1024, 0x61));
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final client = _clientFor(server);
    addTearDown(client.close);

    await expectLater(
      client.health(),
      throwsA(
        isA<AiJunglerApiException>().having(
          (error) => error.message,
          'message',
          contains('超过'),
        ),
      ),
    );
  });

  test('拒绝超过限制的 SSE 单行', () async {
    final server = await _startServer((request) async {
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      request.response.write('data: ');
      request.response.add(List<int>.filled(300 * 1024, 0x61));
      request.response.write('\n\n');
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final client = _clientFor(server);
    addTearDown(client.close);

    await expectLater(
      client.events('job').drain<void>(),
      throwsA(
        isA<AiJunglerApiException>().having(
          (error) => error.message,
          'message',
          contains('实时事件超过'),
        ),
      ),
    );
  });
}

Future<HttpServer> _startServer(
  Future<void> Function(HttpRequest) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(handler);
  return server;
}

AiJunglerClient _clientFor(HttpServer server) => AiJunglerClient(
  baseUri: Uri.parse('http://${server.address.address}:${server.port}'),
  accessToken: 'test-token',
);
