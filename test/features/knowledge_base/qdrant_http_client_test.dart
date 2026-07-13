import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/knowledge_base/service/qdrant_http_client.dart';
import 'package:openhand/shared/net/http_response_utils.dart';

const Duration _timeout = Duration(seconds: 2);

void main() {
  late HttpServer server;
  late StreamSubscription<HttpRequest> requests;
  late Future<void> Function(HttpRequest request) handler;
  var requestCount = 0;

  setUp(() async {
    requestCount = 0;
    handler = (request) async {
      request.response.write('{}');
      await request.response.close();
    };
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    requests = server.listen((request) {
      requestCount += 1;
      unawaited(handler(request));
    });
  });

  tearDown(() async {
    await requests.cancel();
    await server.close(force: true);
  });

  Future<QdrantHttpResponse> send({
    int maxResponseBytes = 1024,
    Future<void>? cancelSignal,
  }) {
    return sendQdrantJsonRequest(
      method: 'GET',
      uri: Uri.parse('http://127.0.0.1:${server.port}/test'),
      connectionTimeout: _timeout,
      openTimeout: _timeout,
      responseTimeout: _timeout,
      responseIdleTimeout: _timeout,
      maxResponseBytes: maxResponseBytes,
      cancelSignal: cancelSignal,
    );
  }

  test('completed cancellation prevents the request from starting', () async {
    final cancelled = Completer<void>()..complete();

    await expectLater(
      send(cancelSignal: cancelled.future),
      throwsA(isA<QdrantRequestCancelledException>()),
    );
    expect(requestCount, 0);
  });

  test('in-flight cancellation aborts a pending response', () async {
    final requestStarted = Completer<void>();
    final cancelled = Completer<void>();
    handler = (request) async {
      requestStarted.complete();
    };

    final pending = send(cancelSignal: cancelled.future);
    await requestStarted.future.timeout(_timeout);
    cancelled.complete();

    await expectLater(pending, throwsA(isA<QdrantRequestCancelledException>()));
    expect(requestCount, 1);
  });

  test('rejects a response larger than the configured limit', () async {
    handler = (request) async {
      request.response.write('12345');
      await request.response.close();
    };

    await expectLater(
      send(maxResponseBytes: 4),
      throwsA(isA<ByteStreamSizeLimitException>()),
    );
  });

  test('clips oversized error bodies', () async {
    handler = (request) async {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write(
        '${List<String>.filled(5000, 'x').join()}tail-marker',
      );
      await request.response.close();
    };

    await expectLater(
      send(maxResponseBytes: 6000),
      throwsA(
        isA<HttpException>()
            .having(
              (error) => error.message.length,
              'message length',
              lessThan(5000),
            )
            .having(
              (error) => error.message,
              'message',
              isNot(contains('tail-marker')),
            ),
      ),
    );
  });
}
