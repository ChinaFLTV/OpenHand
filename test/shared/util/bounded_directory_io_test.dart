import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/bounded_directory_io.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'openhand-bounded-directory-',
    );
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test('directory listing retains at most the configured entries', () async {
    for (var index = 0; index < 5; index++) {
      await File('${temporaryDirectory.path}/$index.txt').writeAsString('');
    }

    final result = await listDirectoryBounded(
      temporaryDirectory,
      maxEntries: 3,
    );

    expect(result.entries, hasLength(3));
    expect(result.truncated, isTrue);
  });

  test('directory listing reports complete results below the limit', () async {
    await File('${temporaryDirectory.path}/file.txt').writeAsString('');

    final result = await listDirectoryBounded(
      temporaryDirectory,
      maxEntries: 3,
    );

    expect(result.entries, hasLength(1));
    expect(result.truncated, isFalse);
  });

  test('directory listing rejects a non-positive entry limit', () async {
    await expectLater(
      listDirectoryBounded(temporaryDirectory, maxEntries: 0),
      throwsArgumentError,
    );
  });

  test(
    'directory usage measures nested files without retaining entries',
    () async {
      final nested = Directory('${temporaryDirectory.path}/nested');
      await nested.create();
      await File('${temporaryDirectory.path}/root.txt').writeAsString('1234');
      await File('${nested.path}/child.txt').writeAsString('123456');

      final result = await measureDirectoryBounded(
        temporaryDirectory,
        maxEntries: 10,
      );

      expect(result.fileCount, 2);
      expect(result.directoryCount, 1);
      expect(result.totalBytes, 10);
      expect(result.scannedEntries, 3);
      expect(result.truncated, isFalse);
    },
  );

  test('directory usage stops at the configured entry limit', () async {
    for (var index = 0; index < 5; index++) {
      await File('${temporaryDirectory.path}/$index.txt').writeAsString('x');
    }

    final result = await measureDirectoryBounded(
      temporaryDirectory,
      maxEntries: 2,
    );

    expect(result.scannedEntries, 2);
    expect(result.fileCount, lessThanOrEqualTo(2));
    expect(result.truncated, isTrue);
  });
}
