import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/media/media_cache_service.dart';
import 'package:path/path.dart' as p;

void main() {
  group('MediaCacheService download lifecycle', () {
    for (final responseCase in _RejectedResponseCase.values) {
      test(
        '${responseCase.label} is rejected without draining the response',
        () async {
          final tempDir = await Directory.systemTemp.createTemp(
            'openhand_media_cache_reject_',
          );
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          final requestStarted = Completer<void>();
          final client = _TrackingHttpClient();
          final subscription = server.listen((request) async {
            try {
              responseCase.configure(request.response);
              request.response.add(const <int>[1, 2, 3]);
              await request.response.flush();
              if (!requestStarted.isCompleted) requestStarted.complete();
              await request.response.done;
            } catch (_) {
              if (!requestStarted.isCompleted) requestStarted.complete();
            }
          });
          final service = MediaCacheService.forTesting(
            cacheDirectoryPath: tempDir.path,
            createHttpClient: (_) => client,
          );

          try {
            final result = await service
                .ensureCached(
                  'http://${server.address.host}:${server.port}/asset.png',
                  kind: MediaCacheKind.image,
                )
                .timeout(const Duration(seconds: 2));

            expect(result, isNull);
            await requestStarted.future.timeout(const Duration(seconds: 2));
            expect(client.closed, isTrue);
            expect(client.forceClosed, isTrue);
            expect(tempDir.listSync().whereType<File>(), isEmpty);
          } finally {
            client.close(force: true);
            await subscription.cancel();
            await server.close(force: true);
            await tempDir.delete(recursive: true);
          }
        },
      );
    }

    test(
      'successful downloads are streamed to a finalized cache file',
      () async {
        const totalBytes = 2 * 1024 * 1024;
        final chunk = Uint8List(32 * 1024)..fillRange(0, 32 * 1024, 7);
        final tempDir = await Directory.systemTemp.createTemp(
          'openhand_media_cache_success_',
        );
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final client = _TrackingHttpClient();
        final subscription = server.listen((request) async {
          request.response.headers.contentType = ContentType('image', 'png');
          request.response.contentLength = totalBytes;
          for (var written = 0; written < totalBytes; written += chunk.length) {
            request.response.add(chunk);
            await request.response.flush();
          }
          await request.response.close();
        });
        final service = MediaCacheService.forTesting(
          cacheDirectoryPath: tempDir.path,
          createHttpClient: (_) => client,
        );

        try {
          final result = await service
              .ensureCached(
                'http://${server.address.host}:${server.port}/asset.png',
                kind: MediaCacheKind.image,
              )
              .timeout(const Duration(seconds: 5));

          expect(result, isNotNull);
          expect(await File(result!).length(), totalBytes);
          expect(File('$result.part').existsSync(), isFalse);
          expect(
            tempDir.listSync().whereType<File>().map(
              (file) => p.extension(file.path),
            ),
            containsAll(<String>['.png', '.json']),
          );
          expect(client.closed, isTrue);
          expect(client.forceClosed, isTrue);
        } finally {
          client.close(force: true);
          await subscription.cancel();
          await server.close(force: true);
          await tempDir.delete(recursive: true);
        }
      },
    );

    test('truncated responses remove the partial cache file', () async {
      const declaredBytes = 1024;
      final tempDir = await Directory.systemTemp.createTemp(
        'openhand_media_cache_truncated_',
      );
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[];
      final subscription = server.listen((socket) async {
        sockets.add(socket);
        try {
          await socket.first;
          socket.add(
            utf8.encode(
              'HTTP/1.1 200 OK\r\n'
              'Content-Type: image/png\r\n'
              'Content-Length: $declaredBytes\r\n'
              'Connection: close\r\n'
              '\r\n',
            ),
          );
          socket.add(Uint8List(128));
          await socket.flush();
        } finally {
          socket.destroy();
        }
      });
      final client = _TrackingHttpClient();
      final service = MediaCacheService.forTesting(
        cacheDirectoryPath: tempDir.path,
        createHttpClient: (_) => client,
      );

      try {
        final result = await service
            .ensureCached(
              'http://${server.address.host}:${server.port}/truncated.png',
              kind: MediaCacheKind.image,
            )
            .timeout(const Duration(seconds: 2));

        expect(result, isNull);
        expect(
          tempDir.listSync().whereType<File>().where(
            (file) => file.path.endsWith('.part'),
          ),
          isEmpty,
        );
        expect(client.closed, isTrue);
        expect(client.forceClosed, isTrue);
      } finally {
        client.close(force: true);
        for (final socket in sockets) {
          socket.destroy();
        }
        await subscription.cancel();
        await server.close();
        await tempDir.delete(recursive: true);
      }
    });
  });

  test(
    'directory creation failures fall back to null before opening HTTP',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'openhand_media_cache_bad_dir_',
      );
      final blockingFile = File(p.join(tempDir.path, 'cache'));
      await blockingFile.writeAsString('not a directory');
      var clientCreationCount = 0;
      final service = MediaCacheService.forTesting(
        cacheDirectoryPath: blockingFile.path,
        createHttpClient: (_) {
          clientCreationCount += 1;
          return HttpClient();
        },
      );

      try {
        expect(
          await service.ensureCached(
            'https://example.invalid/asset.png',
            kind: MediaCacheKind.image,
          ),
          isNull,
        );
        expect(clientCreationCount, 0);
      } finally {
        await tempDir.delete(recursive: true);
      }
    },
  );

  test('HTTP client creation failures fall back to null', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'openhand_media_cache_bad_client_',
    );
    final service = MediaCacheService.forTesting(
      cacheDirectoryPath: tempDir.path,
      createHttpClient: (_) => throw StateError('client unavailable'),
    );

    try {
      expect(
        await service.ensureCached(
          'https://example.invalid/asset.png',
          kind: MediaCacheKind.image,
        ),
        isNull,
      );
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test('background cache jobs contain unexpected async failures', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'openhand_media_cache_background_',
    );
    final invoked = Completer<void>();
    final service = _ThrowingMediaCacheService(tempDir.path, invoked);
    final unhandledErrors = <Object>[];

    try {
      await runZonedGuarded(() async {
        service.cacheInBackground(
          'https://example.invalid/asset.png',
          kind: MediaCacheKind.image,
        );
        await invoked.future;
        await Future<void>.delayed(Duration.zero);
      }, (error, stack) => unhandledErrors.add(error));

      expect(unhandledErrors, isEmpty);
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}

enum _RejectedResponseCase {
  failedStatus('non-success status'),
  wrongContentType('unexpected content type'),
  oversized('oversized declared body');

  const _RejectedResponseCase(this.label);

  final String label;

  void configure(HttpResponse response) {
    response.statusCode = this == failedStatus
        ? HttpStatus.notFound
        : HttpStatus.ok;
    response.headers.contentType = this == wrongContentType
        ? ContentType.text
        : ContentType('image', 'png');
    if (this == oversized) {
      response.contentLength = 65 * 1024 * 1024;
    }
  }
}

class _TrackingHttpClient implements HttpClient {
  _TrackingHttpClient() : _inner = HttpClient() {
    _inner.findProxy = (_) => 'DIRECT';
  }

  final HttpClient _inner;
  bool closed = false;
  bool forceClosed = false;

  @override
  Future<HttpClientRequest> getUrl(Uri url) => _inner.getUrl(url);

  @override
  void close({bool force = false}) {
    closed = true;
    forceClosed = forceClosed || force;
    _inner.close(force: force);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ThrowingMediaCacheService extends MediaCacheService {
  _ThrowingMediaCacheService(String cacheDirectoryPath, this.invoked)
    : super.forTesting(cacheDirectoryPath: cacheDirectoryPath);

  final Completer<void> invoked;

  @override
  Future<String?> ensureCached(String url, {MediaCacheKind? kind}) {
    if (!invoked.isCompleted) invoked.complete();
    return Future<String?>.error(StateError('unexpected failure'));
  }
}
