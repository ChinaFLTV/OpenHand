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
}
