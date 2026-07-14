import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/bounded_delete.dart';
import 'package:path/path.dart' as p;

const BoundedDeletePolicy _testPolicy = BoundedDeletePolicy(
  maxEntries: 16,
  maxDepth: 4,
  directoryIdleTimeout: Duration(seconds: 1),
  operationTimeout: Duration(seconds: 1),
  totalTimeout: Duration(seconds: 5),
);

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'openhand-bounded-delete-',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('deletes a complete directory tree in post-order', () async {
    final target = Directory('${temporaryDirectory.path}/target');
    final nested = Directory('${target.path}/nested');
    await nested.create(recursive: true);
    await File('${target.path}/root.txt').writeAsString('root');
    await File('${nested.path}/child.txt').writeAsString('child');

    final result = await deletePathBounded(target.path, policy: _testPolicy);

    expect(await target.exists(), isFalse);
    expect(result.plannedEntries, 4);
    expect(result.deletedEntries, 4);
    expect(result.fileCount, 2);
    expect(result.directoryCount, 2);
    expect(result.linkCount, 0);
    expect(result.wasMissing, isFalse);
  });

  test('missing targets are idempotent by default', () async {
    final result = await deletePathBounded(
      '${temporaryDirectory.path}/missing',
      policy: _testPolicy,
    );

    expect(result.wasMissing, isTrue);
    expect(result.deletedEntries, 0);
  });

  test('can reject a missing target', () async {
    await expectLater(
      deletePathBounded(
        '${temporaryDirectory.path}/missing',
        policy: _testPolicy,
        allowMissing: false,
      ),
      throwsA(
        isA<BoundedDeleteException>().having(
          (error) => error.reason,
          'reason',
          BoundedDeleteFailureReason.fileSystemFailure,
        ),
      ),
    );
  });

  test('entry limit fails before deleting any path', () async {
    final target = Directory('${temporaryDirectory.path}/target');
    await target.create();
    final first = File('${target.path}/first.txt');
    final second = File('${target.path}/second.txt');
    await first.writeAsString('first');
    await second.writeAsString('second');
    const policy = BoundedDeletePolicy(
      maxEntries: 2,
      maxDepth: 2,
      totalTimeout: Duration(seconds: 5),
    );

    await expectLater(
      deletePathBounded(target.path, policy: policy),
      throwsA(
        isA<BoundedDeleteException>()
            .having(
              (error) => error.reason,
              'reason',
              BoundedDeleteFailureReason.entryLimitExceeded,
            )
            .having((error) => error.deletedEntries, 'deleted entries', 0),
      ),
    );
    expect(await first.exists(), isTrue);
    expect(await second.exists(), isTrue);
  });

  test('depth limit fails before deleting any path', () async {
    final target = Directory('${temporaryDirectory.path}/target');
    final nested = Directory('${target.path}/one/two');
    await nested.create(recursive: true);
    final file = File('${nested.path}/file.txt');
    await file.writeAsString('content');
    const policy = BoundedDeletePolicy(
      maxEntries: 16,
      maxDepth: 1,
      totalTimeout: Duration(seconds: 5),
    );

    await expectLater(
      deletePathBounded(target.path, policy: policy),
      throwsA(
        isA<BoundedDeleteException>().having(
          (error) => error.reason,
          'reason',
          BoundedDeleteFailureReason.depthLimitExceeded,
        ),
      ),
    );
    expect(await file.exists(), isTrue);
  });

  test(
    'deletes a symbolic link without touching its target',
    () async {
      final outside = Directory('${temporaryDirectory.path}/outside');
      await outside.create();
      final outsideFile = File('${outside.path}/keep.txt');
      await outsideFile.writeAsString('keep');
      final link = Link('${temporaryDirectory.path}/linked-directory');
      await link.create(outside.path);

      final result = await deletePathBounded(link.path, policy: _testPolicy);

      expect(await link.exists(), isFalse);
      expect(await outsideFile.readAsString(), 'keep');
      expect(result.linkCount, 1);
      expect(result.deletedEntries, 1);
    },
    skip: Platform.isWindows ? 'Symbolic links can require elevation.' : false,
  );

  test(
    'allowed root blocks deletion through an escaping parent link',
    () async {
      final allowedRoot = Directory('${temporaryDirectory.path}/allowed');
      final outside = Directory('${temporaryDirectory.path}/outside');
      final outsideTarget = Directory('${outside.path}/delete-me');
      await allowedRoot.create();
      await outsideTarget.create(recursive: true);
      final escapeLink = Link('${allowedRoot.path}/escape');
      await escapeLink.create(outside.path);

      await expectLater(
        deletePathBounded(
          '${escapeLink.path}/delete-me',
          policy: _testPolicy,
          allowedRoot: allowedRoot.path,
        ),
        throwsA(
          isA<BoundedDeleteException>().having(
            (error) => error.reason,
            'reason',
            BoundedDeleteFailureReason.invalidTarget,
          ),
        ),
      );
      expect(await outsideTarget.exists(), isTrue);
    },
    skip: Platform.isWindows ? 'Symbolic links can require elevation.' : false,
  );

  test('rejects relative, root, and protected paths', () async {
    for (final path in <String>[
      'relative/path',
      Directory.current.path,
      Directory.systemTemp.path,
      p.rootPrefix(Directory.current.path),
    ]) {
      await expectLater(
        deletePathBounded(path, policy: _testPolicy),
        throwsA(
          isA<BoundedDeleteException>().having(
            (error) => error.reason,
            'reason',
            BoundedDeleteFailureReason.invalidTarget,
          ),
        ),
      );
    }
  });

  test('reports a total timeout as a bounded delete failure', () async {
    final target = Directory('${temporaryDirectory.path}/target');
    await target.create();
    await File('${target.path}/file.txt').writeAsString('content');
    const policy = BoundedDeletePolicy(
      maxEntries: 16,
      maxDepth: 4,
      directoryIdleTimeout: Duration(microseconds: 1),
      operationTimeout: Duration(microseconds: 1),
      totalTimeout: Duration(microseconds: 1),
    );

    await expectLater(
      deletePathBounded(target.path, policy: policy),
      throwsA(
        isA<BoundedDeleteException>().having(
          (error) => error.reason,
          'reason',
          BoundedDeleteFailureReason.timeout,
        ),
      ),
    );
  });
}
