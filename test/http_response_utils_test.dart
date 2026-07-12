import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/net/http_response_utils.dart';

void main() {
  test('bounded byte streams collect successful chunks', () async {
    final bytes = await readBoundedByteStream(
      Stream<List<int>>.fromIterable(const <List<int>>[
        <int>[1, 2],
        <int>[3, 4],
      ]),
      maxBytes: 4,
      idleTimeout: const Duration(seconds: 1),
      totalTimeout: const Duration(seconds: 2),
    );

    expect(bytes, <int>[1, 2, 3, 4]);
  });

  test('size overflow cancels the response subscription', () async {
    final cancelled = Completer<void>();
    final controller = StreamController<List<int>>(
      onCancel: () {
        if (!cancelled.isCompleted) cancelled.complete();
      },
    );
    final read = readBoundedByteStream(
      controller.stream,
      maxBytes: 4,
      idleTimeout: const Duration(seconds: 1),
      totalTimeout: const Duration(seconds: 2),
    );

    controller.add(const <int>[1, 2, 3, 4, 5]);

    await expectLater(read, throwsA(isA<HttpException>()));
    await cancelled.future.timeout(const Duration(seconds: 1));
    await controller.close();
  });

  test('bounded previews truncate overflow and cancel the producer', () async {
    final cancelled = Completer<void>();
    final controller = StreamController<List<int>>(
      onCancel: () {
        if (!cancelled.isCompleted) cancelled.complete();
      },
    );
    final read = readBoundedByteStream(
      controller.stream,
      maxBytes: 4,
      idleTimeout: const Duration(seconds: 1),
      totalTimeout: const Duration(seconds: 2),
      truncateOnOverflow: true,
    );

    controller.add(const <int>[1, 2, 3]);
    controller.add(const <int>[4]);

    expect(await read, <int>[1, 2, 3, 4]);
    await cancelled.future.timeout(const Duration(seconds: 1));
    await controller.close();
  });

  test('bounded stream writes apply asynchronous backpressure', () async {
    final chunks = <List<int>>[];
    final written = await writeBoundedByteStream(
      Stream<List<int>>.fromIterable(const <List<int>>[
        <int>[1, 2],
        <int>[3, 4],
      ]),
      writeChunk: (chunk) async {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        chunks.add(List<int>.from(chunk));
      },
      maxBytes: 4,
      idleTimeout: const Duration(seconds: 1),
      totalTimeout: const Duration(seconds: 2),
    );

    expect(written, 4);
    expect(chunks, const <List<int>>[
      <int>[1, 2],
      <int>[3, 4],
    ]);
  });

  test('total timeout cancels a continuously active stream', () async {
    final cancelled = Completer<void>();
    final controller = StreamController<List<int>>(
      onCancel: () {
        if (!cancelled.isCompleted) cancelled.complete();
      },
    );
    final timer = Timer.periodic(
      const Duration(milliseconds: 5),
      (_) => controller.add(const <int>[1]),
    );
    try {
      await expectLater(
        drainByteStreamWithTimeout(
          controller.stream,
          idleTimeout: const Duration(seconds: 1),
          totalTimeout: const Duration(milliseconds: 40),
        ),
        throwsA(isA<TimeoutException>()),
      );
      await cancelled.future.timeout(const Duration(seconds: 1));
    } finally {
      timer.cancel();
      await controller.close();
    }
  });

  test(
    'streaming limits cancel trickle traffic at the total deadline',
    () async {
      final cancelled = Completer<void>();
      final controller = StreamController<List<int>>(
        onCancel: () {
          if (!cancelled.isCompleted) cancelled.complete();
        },
      );
      final timer = Timer.periodic(
        const Duration(milliseconds: 5),
        (_) => controller.add(const <int>[1]),
      );
      try {
        await expectLater(
          limitByteStream(
            controller.stream,
            maxBytes: 1024,
            idleTimeout: const Duration(seconds: 1),
            totalTimeout: const Duration(milliseconds: 40),
          ).drain<void>(),
          throwsA(isA<TimeoutException>()),
        );
        await cancelled.future.timeout(const Duration(seconds: 1));
      } finally {
        timer.cancel();
        await controller.close();
      }
    },
  );

  test('stream boundaries do not wait for a stalled source cancel', () async {
    final cancelStarted = Completer<void>();
    final cancelNeverCompletes = Completer<void>();
    final controller = StreamController<List<int>>(
      onCancel: () {
        if (!cancelStarted.isCompleted) cancelStarted.complete();
        return cancelNeverCompletes.future;
      },
    );
    final stopwatch = Stopwatch()..start();
    final read = limitByteStream(
      controller.stream,
      maxBytes: 1024,
      idleTimeout: const Duration(seconds: 1),
      totalTimeout: const Duration(milliseconds: 40),
    ).drain<void>();

    await expectLater(read, throwsA(isA<TimeoutException>()));
    stopwatch.stop();
    expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 300)));
    await cancelStarted.future.timeout(const Duration(seconds: 1));
    cancelNeverCompletes.complete();
    await controller.close();
  });
}
