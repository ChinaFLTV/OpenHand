import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openhand/features/ai/service/model_registry/ai_model_scanner.dart';
import 'package:openhand/features/ai/service/runtime/ai_transport_client.dart';

void main() {
  final uri = Uri.parse('https://example.test/resource');

  test('model scanner rejects ambiguous transport ownership at runtime', () {
    final client = _CallbackClient(
      (_) => throw StateError('No request should be sent.'),
    );
    final transport = AiTransportClient(client: client);

    expect(
      () => AiModelScanner(httpClient: client, transport: transport),
      throwsArgumentError,
    );
    transport.dispose();
  });

  test('form requests share abortable bounded transport semantics', () async {
    final aborted = Completer<void>();
    final client = _CallbackClient((request) async {
      _observeAbort(request, aborted);
      expect(request, isA<http.Request>());
      expect((request as http.Request).bodyFields, <String, String>{
        'q': 'hello world',
      });
      return http.StreamedResponse(
        Stream<List<int>>.value('ok'.codeUnits),
        200,
        request: request,
      );
    });
    final transport = AiTransportClient(client: client);

    final response = await transport.sendForm(
      uri: uri,
      method: 'POST',
      headers: const <String, String>{
        'content-type': 'application/x-www-form-urlencoded',
      },
      body: const <String, String>{'q': 'hello world'},
      timeout: const Duration(seconds: 1),
      maxResponseBytes: 2,
    );

    expect(response.body, 'ok');
    await aborted.future.timeout(const Duration(seconds: 1));
  });

  test('JSON transport accepts a non-object root value', () async {
    final client = _CallbackClient((request) async {
      expect(jsonDecode((request as http.Request).body), <Object?>['first', 2]);
      return http.StreamedResponse(
        Stream<List<int>>.value('[]'.codeUnits),
        200,
        request: request,
      );
    });
    final transport = AiTransportClient(client: client);

    final response = await transport.sendJson(
      uri: uri,
      method: 'POST',
      headers: const <String, String>{'content-type': 'application/json'},
      body: const <Object?>['first', 2],
      timeout: const Duration(seconds: 1),
      maxResponseBytes: 2,
    );

    expect(response.body, '[]');
  });

  test(
    'synchronous request construction failures do not poison reuse',
    () async {
      var sendCount = 0;
      final client = _CallbackClient((request) async {
        sendCount += 1;
        return http.StreamedResponse(
          Stream<List<int>>.value('ok'.codeUnits),
          200,
          request: request,
        );
      });
      final transport = AiTransportClient(client: client);
      final cyclic = <Object?>[];
      cyclic.add(cyclic);

      await expectLater(
        transport.sendJson(
          uri: uri,
          method: 'POST',
          headers: const <String, String>{'content-type': 'application/json'},
          body: cyclic,
          timeout: const Duration(seconds: 1),
        ),
        throwsA(isA<JsonCyclicError>()),
      );
      await expectLater(
        transport.sendForm(
          uri: uri,
          method: 'POST',
          headers: const <String, String>{'content-type': 'application/json'},
          body: const <String, String>{'q': 'invalid-content-type'},
          timeout: const Duration(seconds: 1),
        ),
        throwsStateError,
      );

      final response = await transport.sendText(
        uri: uri,
        method: 'POST',
        headers: const <String, String>{},
        body: 'valid',
        timeout: const Duration(seconds: 1),
        maxResponseBytes: 2,
      );
      expect(response.body, 'ok');
      expect(sendCount, 1);
      transport.dispose();
    },
  );

  test('dispose aborts active requests without owning the client', () async {
    final aborted = Completer<void>();
    final headers = Completer<http.StreamedResponse>();
    final client = _CallbackClient((request) {
      if (request case http.Abortable(:final abortTrigger?)) {
        abortTrigger.whenComplete(() {
          if (!aborted.isCompleted) aborted.complete();
          if (!headers.isCompleted) {
            headers.completeError(
              http.ClientException('transport disposed', request.url),
            );
          }
        });
      }
      return headers.future;
    });
    final transport = AiTransportClient(client: client);
    final response = transport.get(
      uri: uri,
      headers: const <String, String>{},
      timeout: const Duration(seconds: 5),
    );

    transport.dispose();

    await aborted.future.timeout(const Duration(seconds: 1));
    await expectLater(response, throwsA(isA<http.ClientException>()));
    await expectLater(
      transport.get(
        uri: uri,
        headers: const <String, String>{},
        timeout: const Duration(seconds: 1),
      ),
      throwsStateError,
    );
  });

  test(
    'request timeout aborts the transport before response headers',
    () async {
      final aborted = Completer<void>();
      final cancelled = Completer<void>();
      final responseBody = StreamController<List<int>>(
        onCancel: () {
          if (!cancelled.isCompleted) cancelled.complete();
        },
      );
      final headers = Completer<http.StreamedResponse>();
      final client = _CallbackClient((request) {
        _observeAbort(request, aborted);
        return headers.future;
      });
      final transport = AiTransportClient(client: client);

      await expectLater(
        transport.get(
          uri: uri,
          headers: const <String, String>{},
          timeout: const Duration(milliseconds: 30),
        ),
        throwsA(isA<TimeoutException>()),
      );
      await aborted.future.timeout(const Duration(seconds: 1));
      headers.complete(http.StreamedResponse(responseBody.stream, 200));
      await cancelled.future.timeout(const Duration(seconds: 1));
      await responseBody.close();
    },
  );

  test('completed response releases the abort trigger lifecycle', () async {
    final aborted = Completer<void>();
    final client = _CallbackClient((request) async {
      _observeAbort(request, aborted);
      return http.StreamedResponse(
        Stream<List<int>>.value('ok'.codeUnits),
        200,
        request: request,
      );
    });
    final transport = AiTransportClient(client: client);

    final response = await transport.get(
      uri: uri,
      headers: const <String, String>{},
      timeout: const Duration(seconds: 1),
    );

    expect(response.body, 'ok');
    await aborted.future.timeout(const Duration(seconds: 1));
  });

  test('body timeout aborts and cancels the response stream', () async {
    final aborted = Completer<void>();
    final cancelled = Completer<void>();
    final controller = StreamController<List<int>>(
      onCancel: () {
        if (!cancelled.isCompleted) cancelled.complete();
      },
    );
    final client = _CallbackClient((request) async {
      _observeAbort(request, aborted);
      return http.StreamedResponse(controller.stream, 200, request: request);
    });
    final transport = AiTransportClient(client: client);

    await expectLater(
      transport.get(
        uri: uri,
        headers: const <String, String>{},
        timeout: const Duration(milliseconds: 30),
      ),
      throwsA(isA<TimeoutException>()),
    );
    await Future.wait(<Future<void>>[
      aborted.future,
      cancelled.future,
    ]).timeout(const Duration(seconds: 1));
    await controller.close();
  });

  test('stream consumers cannot leave an unread response attached', () async {
    final cancelled = Completer<void>();
    final controller = StreamController<List<int>>(
      onCancel: () {
        if (!cancelled.isCompleted) cancelled.complete();
      },
    );
    final transport = AiTransportClient(
      client: _CallbackClient(
        (request) async => http.StreamedResponse(
          controller.stream,
          200,
          request: request,
          headers: const <String, String>{'content-type': 'application/json'},
        ),
      ),
    );

    final result = await transport.consumeJsonStream<String>(
      uri: uri,
      method: 'POST',
      headers: const <String, String>{'content-type': 'application/json'},
      body: const <String, Object?>{},
      timeout: const Duration(seconds: 1),
      maxResponseBytes: 1024,
      consume: (_, _) async => 'done',
    );

    expect(result, 'done');
    await cancelled.future.timeout(const Duration(seconds: 1));
    await controller.close();
  });

  test(
    'successful response overflow aborts and cancels the body stream',
    () async {
      final aborted = Completer<void>();
      final cancelled = Completer<void>();
      final controller = StreamController<List<int>>(
        onCancel: () {
          if (!cancelled.isCompleted) cancelled.complete();
        },
      );
      final client = _CallbackClient((request) async {
        _observeAbort(request, aborted);
        return http.StreamedResponse(controller.stream, 200, request: request);
      });
      final transport = AiTransportClient(client: client);
      final response = transport.get(
        uri: uri,
        headers: const <String, String>{},
        timeout: const Duration(seconds: 1),
        maxResponseBytes: 4,
      );

      controller.add(const <int>[1, 2, 3, 4, 5]);

      await expectLater(response, throwsA(isA<HttpException>()));
      await Future.wait(<Future<void>>[
        aborted.future,
        cancelled.future,
      ]).timeout(const Duration(seconds: 1));
      await controller.close();
    },
  );

  test(
    'oversized error body is retained as a bounded status response',
    () async {
      final cancelled = Completer<void>();
      final controller = StreamController<List<int>>(
        onCancel: () {
          if (!cancelled.isCompleted) cancelled.complete();
        },
      );
      final client = _CallbackClient(
        (request) async => http.StreamedResponse(
          controller.stream,
          500,
          request: request,
          headers: const <String, String>{'content-type': 'text/plain'},
        ),
      );
      final transport = AiTransportClient(client: client);
      final responseFuture = transport.get(
        uri: uri,
        headers: const <String, String>{},
        timeout: const Duration(seconds: 1),
        maxResponseBytes: 4,
      );

      controller.add('abcdef'.codeUnits);

      final response = await responseFuture;
      expect(response.statusCode, 500);
      expect(response.body, 'abcd');
      await cancelled.future.timeout(const Duration(seconds: 1));
      await controller.close();
    },
  );

  test(
    'declared success size is rejected before reading the response',
    () async {
      final aborted = Completer<void>();
      final cancelled = Completer<void>();
      final controller = StreamController<List<int>>(
        onCancel: () {
          if (!cancelled.isCompleted) cancelled.complete();
        },
      );
      final client = _CallbackClient((request) async {
        _observeAbort(request, aborted);
        return http.StreamedResponse(
          controller.stream,
          200,
          request: request,
          contentLength: 5,
        );
      });
      final transport = AiTransportClient(client: client);

      await expectLater(
        transport.get(
          uri: uri,
          headers: const <String, String>{},
          timeout: const Duration(seconds: 1),
          maxResponseBytes: 4,
        ),
        throwsA(isA<HttpException>()),
      );
      await Future.wait(<Future<void>>[
        aborted.future,
        cancelled.future,
      ]).timeout(const Duration(seconds: 1));
      await controller.close();
    },
  );

  test('in-memory downloads keep the conservative default cap', () async {
    final cancelled = Completer<void>();
    final controller = StreamController<List<int>>(
      onCancel: () {
        if (!cancelled.isCompleted) cancelled.complete();
      },
    );
    final transport = AiTransportClient(
      client: _CallbackClient(
        (request) async => http.StreamedResponse(
          controller.stream,
          200,
          request: request,
          contentLength: defaultAiTransportDownloadMaxBytes + 1,
        ),
      ),
    );

    await expectLater(
      transport.downloadBytes(
        uri: uri,
        headers: const <String, String>{},
        timeout: const Duration(seconds: 1),
      ),
      throwsA(isA<HttpException>()),
    );
    await cancelled.future.timeout(const Duration(seconds: 1));
    await controller.close();
  });

  test('streaming download writes to disk without retaining bytes', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'transport_download_',
    );
    final destination = File('${tempDir.path}/media.bin');
    final aborted = Completer<void>();
    final client = _CallbackClient((request) async {
      _observeAbort(request, aborted);
      return http.StreamedResponse(
        Stream<List<int>>.fromIterable(const <List<int>>[
          <int>[1, 2],
          <int>[3, 4],
        ]),
        200,
        request: request,
        headers: const <String, String>{
          'content-type': 'application/octet-stream',
        },
      );
    });
    final transport = AiTransportClient(client: client);
    try {
      final result = await transport.downloadToFile(
        uri: uri,
        headers: const <String, String>{},
        timeout: const Duration(seconds: 1),
        destination: destination,
        maxBytes: 4,
      );

      expect(result.isSuccess, isTrue);
      expect(result.bytesWritten, 4);
      expect(result.filePath, destination.path);
      expect(result.errorBody, isEmpty);
      expect(await destination.readAsBytes(), <int>[1, 2, 3, 4]);
      await aborted.future.timeout(const Duration(seconds: 1));
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test('streaming download overflow removes its partial file', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'transport_overflow_',
    );
    final destination = File('${tempDir.path}/media.bin');
    final cancelled = Completer<void>();
    final controller = StreamController<List<int>>(
      onCancel: () {
        if (!cancelled.isCompleted) cancelled.complete();
      },
    );
    final client = _CallbackClient(
      (request) async => http.StreamedResponse(
        controller.stream,
        200,
        request: request,
        headers: const <String, String>{
          'content-type': 'application/octet-stream',
        },
      ),
    );
    final transport = AiTransportClient(client: client);
    final download = transport.downloadToFile(
      uri: uri,
      headers: const <String, String>{},
      timeout: const Duration(seconds: 1),
      destination: destination,
      maxBytes: 4,
    );
    controller.add(const <int>[1, 2, 3, 4, 5]);

    try {
      await expectLater(download, throwsA(isA<HttpException>()));
      await cancelled.future.timeout(const Duration(seconds: 1));
      expect(await destination.exists(), isFalse);
    } finally {
      await controller.close();
      await tempDir.delete(recursive: true);
    }
  });

  test('multipart rejects an oversized file before starting HTTP', () async {
    final tempDir = await Directory.systemTemp.createTemp('transport_upload_');
    final upload = File('${tempDir.path}/upload.bin');
    await upload.writeAsBytes(const <int>[1, 2, 3, 4, 5]);
    var sendCount = 0;
    final client = _CallbackClient((_) {
      sendCount += 1;
      throw StateError('HTTP must not start for an oversized upload.');
    });
    final transport = AiTransportClient(client: client);
    try {
      await expectLater(
        transport.sendMultipart(
          uri: uri,
          method: 'POST',
          headers: const <String, String>{},
          body: <String, Object?>{
            'file': AiMultipartUploadFile(filePath: upload.path),
          },
          timeout: const Duration(seconds: 1),
          maxFileBytes: 4,
        ),
        throwsA(isA<HttpException>()),
      );
      expect(sendCount, 0);
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test('multipart enforces the cumulative request limit', () async {
    final tempDir = await Directory.systemTemp.createTemp('transport_total_');
    final first = File('${tempDir.path}/first.bin');
    final second = File('${tempDir.path}/second.bin');
    await first.writeAsBytes(const <int>[1, 2]);
    await second.writeAsBytes(const <int>[3, 4]);
    var sendCount = 0;
    final transport = AiTransportClient(
      client: _CallbackClient((_) {
        sendCount += 1;
        throw StateError('HTTP must not start over the cumulative limit.');
      }),
    );
    try {
      await expectLater(
        transport.sendMultipart(
          uri: uri,
          method: 'POST',
          headers: const <String, String>{},
          body: <String, Object?>{
            'files': <AiMultipartUploadFile>[
              AiMultipartUploadFile(filePath: first.path),
              AiMultipartUploadFile(filePath: second.path),
            ],
          },
          timeout: const Duration(seconds: 1),
          maxFileBytes: 3,
          maxTotalBytes: 3,
        ),
        throwsA(isA<HttpException>()),
      );
      expect(sendCount, 0);
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'multipart file inspection consumes the request timeout budget',
    () async {
      var sendCount = 0;
      final transport = AiTransportClient(
        client: _CallbackClient((_) {
          sendCount += 1;
          throw StateError('HTTP must not start after preparation timeout.');
        }),
        multipartFileLengthReader: (_) => Completer<int>().future,
      );

      await expectLater(
        transport.sendMultipart(
          uri: uri,
          method: 'POST',
          headers: const <String, String>{},
          body: const <String, Object?>{
            'file': AiMultipartUploadFile(filePath: '/pending/file.bin'),
          },
          timeout: const Duration(milliseconds: 30),
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(sendCount, 0);
    },
  );

  test('multipart upload is locked to the inspected file length', () async {
    final tempDir = await Directory.systemTemp.createTemp('transport_growth_');
    final upload = File('${tempDir.path}/upload.bin');
    await upload.writeAsBytes(const <int>[1, 2]);
    int? declaredLength;
    int? emittedLength;
    final client = _CallbackClient((request) async {
      declaredLength = request.contentLength;
      emittedLength = (await request.finalize().toBytes()).length;
      return http.StreamedResponse(
        Stream<List<int>>.value('{}'.codeUnits),
        200,
        request: request,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final transport = AiTransportClient(
      client: client,
      multipartFileLengthReader: (path) async {
        final length = await File(path).length();
        await File(
          path,
        ).writeAsBytes(const <int>[3, 4, 5], mode: FileMode.append);
        return length;
      },
    );
    try {
      await transport.sendMultipart(
        uri: uri,
        method: 'POST',
        headers: const <String, String>{},
        body: <String, Object?>{
          'file': AiMultipartUploadFile(filePath: upload.path),
        },
        timeout: const Duration(seconds: 1),
      );

      expect(emittedLength, declaredLength);
      expect(await upload.length(), 5);
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test('completed abort triggers do not poison a reused client', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requestCount = 0;
    final serverDone = server.listen((request) async {
      requestCount += 1;
      request.response.write('ok$requestCount');
      await request.response.close();
    }).asFuture<void>();
    final client = http.Client();
    final transport = AiTransportClient(client: client);
    final localUri = Uri.parse('http://${server.address.host}:${server.port}/');
    try {
      final first = await transport.get(
        uri: localUri,
        headers: const <String, String>{},
        timeout: const Duration(seconds: 1),
      );
      final second = await transport.get(
        uri: localUri,
        headers: const <String, String>{},
        timeout: const Duration(seconds: 1),
      );

      expect(first.body, 'ok1');
      expect(second.body, 'ok2');
    } finally {
      client.close();
      await server.close(force: true);
      await serverDone;
    }
  });
}

void _observeAbort(http.BaseRequest request, Completer<void> aborted) {
  if (request case http.Abortable(:final abortTrigger?)) {
    abortTrigger.whenComplete(() {
      if (!aborted.isCompleted) aborted.complete();
    });
    return;
  }
  throw StateError('Expected an abortable request.');
}

class _CallbackClient extends http.BaseClient {
  _CallbackClient(this.onSend);

  final Future<http.StreamedResponse> Function(http.BaseRequest request) onSend;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      onSend(request);
}
