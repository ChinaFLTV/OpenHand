import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/harness/service/harness_bounded_file_io.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'openhand_harness_file_io_',
    );
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'text reads reject oversized UTF-8 without retaining a prefix',
    () async {
      final oversized = File(p.join(tempDirectory.path, 'oversized.md'));
      final normal = File(p.join(tempDirectory.path, 'normal.md'));
      await oversized.writeAsString('你好'); // Six UTF-8 bytes.
      await normal.writeAsString('ok');
      final fileIo = HarnessBoundedFileIo(
        _limits(maxFileBytes: 5, maxTotalBytes: 8),
      );

      final rejected = await fileIo.readText(oversized);
      final accepted = await fileIo.readText(normal);

      expect(rejected, isNull);
      expect(accepted?.text, 'ok');
      expect(fileIo.filesRead, 2);
      expect(fileIo.bytesRead, 2);
    },
  );

  test('joined lesson content obeys file and aggregate byte limits', () async {
    for (var index = 0; index < 3; index++) {
      await File(p.join(tempDirectory.path, '$index.md')).writeAsString('ab');
    }
    final fileIo = HarnessBoundedFileIo(
      _limits(
        maxScannedFiles: 3,
        maxTextFiles: 3,
        maxDirectoryEntries: 8,
        maxFileBytes: 4,
        maxTotalBytes: 16,
      ),
    );

    final joined = await fileIo.readJoinedTextFiles(
      tempDirectory,
      separator: '|',
      maxJoinedBytes: 5,
      maxFiles: 2,
    );

    expect(joined.split('|'), hasLength(2));
    expect(joined.replaceAll('|', ''), 'abab');
    expect(utf8.encode(joined), hasLength(5));
  });

  test(
    'recursive scans skip ignored trees and expose count truncation',
    () async {
      final ignored = Directory(p.join(tempDirectory.path, 'node_modules'));
      await ignored.create();
      for (var index = 0; index < 4; index++) {
        await File(p.join(ignored.path, '$index.js')).writeAsString('ignored');
        await File(
          p.join(tempDirectory.path, '$index.txt'),
        ).writeAsString('ok');
      }
      final fileIo = HarnessBoundedFileIo(
        _limits(maxScannedFiles: 2, maxDirectoryEntries: 16),
      );

      final scan = await fileIo.scanFiles(
        tempDirectory,
        recursive: true,
        ignoredNames: const <String>{'node_modules'},
      );

      expect(scan.files, hasLength(2));
      expect(
        scan.files.every((file) => !file.path.contains('node_modules')),
        isTrue,
      );
      expect(scan.complete, isFalse);
    },
  );

  test(
    'snapshot retains bounded content while keeping complete metadata',
    () async {
      for (var index = 0; index < 3; index++) {
        await File(
          p.join(tempDirectory.path, '$index.txt'),
        ).writeAsString('data');
      }
      final ignored = Directory(p.join(tempDirectory.path, '.git'));
      await ignored.create();
      await File(p.join(ignored.path, 'config')).writeAsString('ignored');
      final fileIo = HarnessBoundedFileIo(
        _limits(
          maxScannedFiles: 8,
          maxTextFiles: 8,
          maxDirectoryEntries: 16,
          maxFileBytes: 4,
          maxTotalBytes: 5,
        ),
      );

      final snapshot = await fileIo.snapshotDirectory(
        tempDirectory,
        ignoredNames: const <String>{'.git'},
      );

      expect(snapshot.complete, isTrue);
      expect(snapshot.files, hasLength(3));
      expect(
        snapshot.files.values.where((entry) => entry.content != null),
        hasLength(1),
      );
      expect(fileIo.bytesRead, lessThanOrEqualTo(5));
    },
  );

  test(
    'expired scans return promptly and cannot masquerade as complete',
    () async {
      await File(
        p.join(tempDirectory.path, 'file.txt'),
      ).writeAsString('content');
      final fileIo = HarnessBoundedFileIo(
        _limits(totalTimeout: const Duration(microseconds: 1)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 1));
      final stopwatch = Stopwatch()..start();

      final snapshot = await fileIo.snapshotDirectory(tempDirectory);
      stopwatch.stop();

      expect(snapshot.files, isEmpty);
      expect(snapshot.complete, isFalse);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    },
  );

  test('latest context selection remains lexicographic', () async {
    await File(p.join(tempDirectory.path, '001.md')).writeAsString('older');
    await File(p.join(tempDirectory.path, '002.md')).writeAsString('latest');
    final nested = Directory(p.join(tempDirectory.path, 'nested'));
    await nested.create();
    await File(p.join(nested.path, '999.md')).writeAsString('nested');
    final fileIo = HarnessBoundedFileIo(
      _limits(maxScannedFiles: 2, maxTextFiles: 1),
    );

    final latest = await fileIo.readLexicographicallyLatestText(tempDirectory);

    expect(latest, 'latest');
    expect(fileIo.filesRead, 1);
  });

  test(
    'latest context selection rejects an incomplete directory scan',
    () async {
      await File(p.join(tempDirectory.path, '001.md')).writeAsString('first');
      await File(p.join(tempDirectory.path, '002.md')).writeAsString('second');
      await File(p.join(tempDirectory.path, '003.md')).writeAsString('third');
      final fileIo = HarnessBoundedFileIo(
        _limits(maxScannedFiles: 2, maxTextFiles: 1),
      );

      final latest = await fileIo.readLexicographicallyLatestText(
        tempDirectory,
      );

      expect(latest, isEmpty);
      expect(fileIo.filesRead, 0);
    },
  );

  test('I/O limits reject non-positive budgets', () {
    expect(() => _limits(maxScannedFiles: 0), throwsArgumentError);
    expect(() => _limits(totalTimeout: Duration.zero), throwsArgumentError);
    expect(() => _limits(operationTimeout: Duration.zero), throwsArgumentError);
  });
}

HarnessFileIoLimits _limits({
  int maxScannedFiles = 16,
  int maxTextFiles = 16,
  int maxDirectoryEntries = 32,
  int maxFileBytes = 64,
  int maxTotalBytes = 256,
  Duration totalTimeout = const Duration(seconds: 3),
  Duration operationTimeout = const Duration(seconds: 1),
}) {
  return HarnessFileIoLimits(
    maxScannedFiles: maxScannedFiles,
    maxTextFiles: maxTextFiles,
    maxDirectoryEntries: maxDirectoryEntries,
    maxFileBytes: maxFileBytes,
    maxTotalBytes: maxTotalBytes,
    totalTimeout: totalTimeout,
    operationTimeout: operationTimeout,
  );
}
