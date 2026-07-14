import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/bounded_copy.dart';

const BoundedCopyPolicy _testPolicy = BoundedCopyPolicy(
  maxEntries: 16,
  maxBytes: 1024,
  maxDepth: 4,
  directoryIdleTimeout: Duration(seconds: 1),
  operationTimeout: Duration(seconds: 1),
  totalTimeout: Duration(seconds: 5),
);

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'openhand-bounded-copy-',
    );
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test('directory copy publishes a complete nested tree', () async {
    final source = Directory('${temporaryDirectory.path}/source');
    final nested = Directory('${source.path}/nested');
    await nested.create(recursive: true);
    await File('${source.path}/root.txt').writeAsString('root');
    await File('${nested.path}/child.txt').writeAsString('child');
    final target = Directory('${temporaryDirectory.path}/target');

    final result = await copyDirectoryBounded(
      source,
      target,
      policy: _testPolicy,
    );

    expect(result.entryCount, 3);
    expect(result.fileCount, 2);
    expect(result.directoryCount, 1);
    expect(result.totalBytes, 9);
    expect(await File('${target.path}/root.txt').readAsString(), 'root');
    expect(
      await File('${target.path}/nested/child.txt').readAsString(),
      'child',
    );
  });

  test('directory copy rejects a target nested below the source', () async {
    final source = Directory('${temporaryDirectory.path}/source');
    await source.create();
    final target = Directory('${source.path}/nested/copy');

    await expectLater(
      copyDirectoryBounded(source, target, policy: _testPolicy),
      throwsA(isA<FileSystemException>()),
    );
    expect(await target.exists(), isFalse);
  });

  test(
    'directory copy enforces its entry limit without partial output',
    () async {
      final source = Directory('${temporaryDirectory.path}/source');
      await source.create();
      await File('${source.path}/a.txt').writeAsString('1234');
      await File('${source.path}/b.txt').writeAsString('5678');
      final target = Directory('${temporaryDirectory.path}/target');
      const policy = BoundedCopyPolicy(
        maxEntries: 1,
        maxBytes: 1024,
        maxDepth: 1,
        totalTimeout: Duration(seconds: 5),
      );

      await expectLater(
        copyDirectoryBounded(source, target, policy: policy),
        throwsA(isA<FileSystemException>()),
      );
      expect(await target.exists(), isFalse);
    },
  );

  test(
    'directory copy enforces its byte limit without partial output',
    () async {
      final source = Directory('${temporaryDirectory.path}/source');
      await source.create();
      await File('${source.path}/large.txt').writeAsString('12345');
      final target = Directory('${temporaryDirectory.path}/target');
      const policy = BoundedCopyPolicy(
        maxEntries: 2,
        maxBytes: 4,
        maxDepth: 1,
        totalTimeout: Duration(seconds: 5),
      );

      await expectLater(
        copyDirectoryBounded(source, target, policy: policy),
        throwsA(isA<FileSystemException>()),
      );
      expect(await target.exists(), isFalse);
    },
  );

  test('directory copy enforces its nesting depth', () async {
    final source = Directory('${temporaryDirectory.path}/source');
    await Directory('${source.path}/one/two').create(recursive: true);
    final target = Directory('${temporaryDirectory.path}/target');
    const policy = BoundedCopyPolicy(
      maxEntries: 4,
      maxBytes: 1024,
      maxDepth: 1,
      totalTimeout: Duration(seconds: 5),
    );

    await expectLater(
      copyDirectoryBounded(source, target, policy: policy),
      throwsA(isA<FileSystemException>()),
    );
    expect(await target.exists(), isFalse);
  });

  test(
    'directory copy can atomically replace an existing empty target',
    () async {
      final source = Directory('${temporaryDirectory.path}/source');
      await source.create();
      await File('${source.path}/file.txt').writeAsString('content');
      final target = Directory('${temporaryDirectory.path}/target');
      await target.create();

      await copyDirectoryBounded(
        source,
        target,
        policy: _testPolicy,
        allowExistingEmptyTarget: true,
      );

      expect(await File('${target.path}/file.txt').readAsString(), 'content');
    },
  );

  test(
    'directory copy rejects symbolic links',
    () async {
      final source = Directory('${temporaryDirectory.path}/source');
      await source.create();
      final outside = File('${temporaryDirectory.path}/outside.txt');
      await outside.writeAsString('outside');
      await Link('${source.path}/linked.txt').create(outside.path);
      final target = Directory('${temporaryDirectory.path}/target');

      await expectLater(
        copyDirectoryBounded(source, target, policy: _testPolicy),
        throwsA(isA<FileSystemException>()),
      );
      expect(await target.exists(), isFalse);
    },
    skip: Platform.isWindows
        ? 'Creating symbolic links can require elevated privileges on Windows.'
        : false,
  );

  test(
    'directory copy rejects a target that physically resolves below source',
    () async {
      final source = Directory('${temporaryDirectory.path}/source');
      await Directory('${source.path}/nested').create(recursive: true);
      final sourceLink = Link('${temporaryDirectory.path}/source-link');
      await sourceLink.create(source.path);
      final target = Directory('${sourceLink.path}/nested/copy');

      await expectLater(
        copyDirectoryBounded(source, target, policy: _testPolicy),
        throwsA(isA<FileSystemException>()),
      );
      expect(await target.exists(), isFalse);
    },
    skip: Platform.isWindows
        ? 'Creating symbolic links can require elevated privileges on Windows.'
        : false,
  );

  test('single-file copy publishes a complete file', () async {
    final source = File('${temporaryDirectory.path}/source.txt');
    final target = File('${temporaryDirectory.path}/target.txt');
    await source.writeAsString('source');

    await copyFileBounded(source, target, policy: _testPolicy);

    expect(await target.readAsString(), 'source');
  });

  test('single-file copy refuses to overwrite an existing target', () async {
    final source = File('${temporaryDirectory.path}/source.txt');
    final target = File('${temporaryDirectory.path}/target.txt');
    await source.writeAsString('source');
    await target.writeAsString('target');

    await expectLater(
      copyFileBounded(source, target, policy: _testPolicy),
      throwsA(isA<FileSystemException>()),
    );
    expect(await target.readAsString(), 'target');
  });
}
