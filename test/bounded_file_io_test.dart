import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/bounded_file_io.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'openhand_bounded_file_io_',
    );
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('reads a regular file within all limits', () async {
    final file = File('${tempDirectory.path}/input.bin');
    await file.writeAsBytes(const <int>[1, 2, 3, 4]);

    final bytes = await readBoundedFileBytes(
      file,
      maxBytes: 4,
      idleTimeout: const Duration(seconds: 1),
      totalTimeout: const Duration(seconds: 2),
    );

    expect(bytes, const <int>[1, 2, 3, 4]);
  });

  test('reads an empty regular file without special casing callers', () async {
    final file = File('${tempDirectory.path}/empty.bin');
    await file.create();

    final bytes = await readBoundedFileBytes(
      file,
      maxBytes: 1,
      idleTimeout: const Duration(seconds: 1),
      totalTimeout: const Duration(seconds: 2),
    );

    expect(bytes, isEmpty);
  });

  test(
    'delegates handle ownership for operation-scoped cancellation',
    () async {
      final file = File('${tempDirectory.path}/owned.bin');
      await file.writeAsBytes(const <int>[1, 2, 3]);
      final owner = _RecordingFileHandleOwner();

      final bytes = await readBoundedFileBytes(
        file,
        maxBytes: 3,
        idleTimeout: const Duration(seconds: 1),
        totalTimeout: const Duration(seconds: 2),
        handleOwner: owner,
      );

      expect(bytes, const <int>[1, 2, 3]);
      expect(owner.acquired, 1);
      expect(owner.released, 1);
    },
  );

  test('rejects a directory even when its reported size is small', () async {
    final directory = Directory('${tempDirectory.path}/input-directory');
    await directory.create();

    await expectLater(
      readBoundedFileBytes(
        File(directory.path),
        maxBytes: 1024,
        idleTimeout: const Duration(seconds: 1),
        totalTimeout: const Duration(seconds: 2),
      ),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('rejects a FIFO before attempting a blocking open', () async {
    if (!Platform.isMacOS && !Platform.isLinux) return;
    final path = '${tempDirectory.path}/input.fifo';
    final created = await Process.run('mkfifo', <String>[
      path,
    ]).timeout(const Duration(seconds: 1));
    expect(created.exitCode, 0, reason: '${created.stderr}');
    final stopwatch = Stopwatch()..start();

    await expectLater(
      readBoundedFileBytes(
        File(path),
        maxBytes: 1024,
        idleTimeout: const Duration(milliseconds: 100),
        totalTimeout: const Duration(seconds: 1),
      ),
      throwsA(isA<FileSystemException>()),
    );
    stopwatch.stop();
    expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 500)));
  });

  test('rejects an oversized file before retaining it', () async {
    final file = File('${tempDirectory.path}/oversized.bin');
    await file.writeAsBytes(const <int>[1, 2, 3, 4, 5]);

    await expectLater(
      readBoundedFileBytes(
        file,
        maxBytes: 4,
        idleTimeout: const Duration(seconds: 1),
        totalTimeout: const Duration(seconds: 2),
      ),
      throwsA(
        isA<BoundedFileReadException>().having(
          (error) => error.failure,
          'failure',
          BoundedFileReadFailure.tooLarge,
        ),
      ),
    );
  });

  test('rejects non-positive limits at runtime', () async {
    final file = File('${tempDirectory.path}/input.bin');

    await expectLater(
      readBoundedFileBytes(
        file,
        maxBytes: 0,
        idleTimeout: const Duration(seconds: 1),
        totalTimeout: const Duration(seconds: 1),
      ),
      throwsArgumentError,
    );
    await expectLater(
      readBoundedFileBytes(
        file,
        maxBytes: 1,
        idleTimeout: Duration.zero,
        totalTimeout: const Duration(seconds: 1),
      ),
      throwsArgumentError,
    );
  });

  test('lease defers release until a timed-out operation settles', () async {
    final file = File('${tempDirectory.path}/deferred.bin');
    await file.writeAsBytes(const <int>[1]);
    final handle = await file.open();
    final operation = Completer<int>();
    final released = Completer<void>();
    var releaseCount = 0;
    final lease = BoundedRandomAccessFileLease(
      handle,
      release: (file) async {
        releaseCount += 1;
        await file.close();
        released.complete();
      },
    );

    await expectLater(
      lease.run(
        (_) => operation.future,
        timeout: const Duration(milliseconds: 20),
      ),
      throwsA(isA<TimeoutException>()),
    );
    await lease.cleanup();
    await lease.cleanup();
    expect(released.isCompleted, isFalse);

    operation.complete(1);
    await released.future.timeout(const Duration(seconds: 1));
    await lease.cleanup();
    expect(releaseCount, 1);
  });

  test('lease releases after a timed-out operation fails late', () async {
    final file = File('${tempDirectory.path}/late-error.bin');
    await file.writeAsBytes(const <int>[1]);
    final handle = await file.open();
    final operation = Completer<int>();
    final released = Completer<void>();
    final lease = BoundedRandomAccessFileLease(
      handle,
      release: (file) async {
        await file.close();
        released.complete();
      },
    );

    await expectLater(
      lease.run(
        (_) => operation.future,
        timeout: const Duration(milliseconds: 20),
      ),
      throwsA(isA<TimeoutException>()),
    );
    await lease.cleanup();
    operation.completeError(StateError('late failure'));

    await released.future.timeout(const Duration(seconds: 1));
  });

  test(
    'lease rejects operations after cleanup without invoking them',
    () async {
      final file = File('${tempDirectory.path}/closed.bin');
      await file.writeAsBytes(const <int>[1]);
      final lease = BoundedRandomAccessFileLease(await file.open());
      var invoked = false;

      await lease.cleanup();

      await expectLater(
        lease.run((_) async {
          invoked = true;
          return 1;
        }, timeout: const Duration(seconds: 1)),
        throwsStateError,
      );
      expect(invoked, isFalse);
    },
  );

  test(
    'lease distinguishes an operation TimeoutException from its deadline',
    () async {
      final file = File('${tempDirectory.path}/source-timeout.bin');
      await file.writeAsBytes(const <int>[1]);
      final lease = BoundedRandomAccessFileLease(await file.open());

      await expectLater(
        lease.run<int>(
          (_) => Future<int>.error(
            TimeoutException('The underlying operation timed out.'),
          ),
          timeout: const Duration(seconds: 1),
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(
        await lease.run(
          (input) => input.length(),
          timeout: const Duration(seconds: 1),
        ),
        1,
      );
      await lease.close(timeout: const Duration(seconds: 1));
    },
  );
}

class _RecordingFileHandleOwner implements BoundedFileHandleOwner {
  int acquired = 0;
  int released = 0;

  @override
  Future<RandomAccessFile> acquireFile(
    Future<RandomAccessFile> acquisition, {
    required Duration timeout,
  }) async {
    final file = await acquisition.timeout(timeout);
    acquired += 1;
    return file;
  }

  @override
  Future<void> releaseFile(RandomAccessFile file) async {
    released += 1;
    await file.close();
  }
}
