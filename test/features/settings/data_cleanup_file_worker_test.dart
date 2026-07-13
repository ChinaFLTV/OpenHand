import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/settings/data_cleanup/data_cleanup_service.dart';

void main() {
  late Directory temporaryDirectory;
  late Directory retainedDirectory;
  late Directory removedDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'openhand-data-cleanup-',
    );
    retainedDirectory = Directory('${temporaryDirectory.path}/keep');
    removedDirectory = Directory('${temporaryDirectory.path}/remove');
    await retainedDirectory.create();
    await removedDirectory.create();
    await File('${temporaryDirectory.path}/root.txt').writeAsString('root');
    await File('${retainedDirectory.path}/keep.txt').writeAsString('keep');
    await File('${removedDirectory.path}/remove.txt').writeAsString('remove');
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('measures directory contents with an exclusion', () async {
    final complete = await DataCleanupFileWorker.measureDirectory(
      temporaryDirectory.path,
    );
    final excluding = await DataCleanupFileWorker.measureDirectoryExcluding(
      <String>[temporaryDirectory.path, retainedDirectory.path],
    );

    expect(complete.bytes, 14);
    expect(complete.itemCount, 3);
    expect(excluding.bytes, 10);
    expect(excluding.itemCount, 2);
  });

  test('deletes contents while preserving an excluded subtree', () async {
    await DataCleanupFileWorker.deleteDirectoryContentsExcluding(<String>[
      temporaryDirectory.path,
      retainedDirectory.path,
    ]);

    expect(await retainedDirectory.exists(), isTrue);
    expect(await File('${retainedDirectory.path}/keep.txt').exists(), isTrue);
    expect(await removedDirectory.exists(), isFalse);
    expect(await File('${temporaryDirectory.path}/root.txt').exists(), isFalse);
  });

  test('safe deletion rejects relative and root-like targets', () {
    expect(DataCleanupFileWorker.isSafeDeleteTarget('relative/path'), isFalse);
    expect(DataCleanupFileWorker.isSafeDeleteTarget('/'), isFalse);
    expect(
      DataCleanupFileWorker.isSafeDeleteTarget(temporaryDirectory.path),
      isTrue,
    );
  });
}
