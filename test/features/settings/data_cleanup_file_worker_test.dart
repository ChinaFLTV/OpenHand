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

  test('deletes all contents and recreates an empty root', () async {
    await DataCleanupFileWorker.deleteDirectoryContents(
      temporaryDirectory.path,
    );

    expect(await temporaryDirectory.exists(), isTrue);
    expect(await temporaryDirectory.list().toList(), isEmpty);
  });

  test(
    'directory cleanup deletes a link without following its target',
    () async {
      final target = Directory('${temporaryDirectory.path}/target');
      final outside = Directory('${temporaryDirectory.path}/outside');
      await target.create();
      await outside.create();
      final outsideFile = File('${outside.path}/keep.txt');
      await outsideFile.writeAsString('keep');
      await Link('${target.path}/outside-link').create(outside.path);

      await DataCleanupFileWorker.deleteDirectoryContents(target.path);

      expect(await target.exists(), isTrue);
      expect(await target.list().toList(), isEmpty);
      expect(await outsideFile.readAsString(), 'keep');
    },
    skip: Platform.isWindows ? 'Symbolic links can require elevation.' : false,
  );

  test('safe deletion rejects relative and root-like targets', () {
    expect(DataCleanupFileWorker.isSafeDeleteTarget('relative/path'), isFalse);
    expect(DataCleanupFileWorker.isSafeDeleteTarget('/'), isFalse);
    expect(
      DataCleanupFileWorker.isSafeDeleteTarget(temporaryDirectory.path),
      isTrue,
    );
  });
}
