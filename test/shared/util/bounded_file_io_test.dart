import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/bounded_file_io.dart';

import '../../support/test_directory.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'openhand-bounded-file-io-',
    );
  });

  tearDown(() => deleteTestDirectory(temporaryDirectory));

  test('bounded string reader decodes a regular UTF-8 file', () async {
    final file = File('${temporaryDirectory.path}/config.json');
    await file.writeAsString('{"ok":true}');

    expect(await readBoundedFileString(file, maxBytes: 64), '{"ok":true}');
  });

  test(
    'bounded string reader rejects an oversized file before decoding',
    () async {
      final file = File('${temporaryDirectory.path}/oversized.txt');
      await file.writeAsBytes(<int>[1, 2, 3, 4, 5]);

      await expectLater(
        readBoundedFileString(file, maxBytes: 4),
        throwsA(
          isA<BoundedFileReadException>().having(
            (error) => error.failure,
            'failure',
            BoundedFileReadFailure.tooLarge,
          ),
        ),
      );
    },
  );

  test(
    'bounded prefix reader accepts a larger file without over-reading',
    () async {
      final file = File('${temporaryDirectory.path}/large-preview.bin');
      await file.writeAsBytes(<int>[1, 2, 3, 4, 5]);

      expect(await readBoundedFilePrefixBytes(file, maxBytes: 3), <int>[
        1,
        2,
        3,
      ]);
    },
  );

  test('bounded string reader rejects malformed UTF-8', () async {
    final file = File('${temporaryDirectory.path}/malformed.txt');
    await file.writeAsBytes(<int>[0xc3, 0x28]);

    await expectLater(
      readBoundedFileString(file, maxBytes: 16),
      throwsA(isA<FormatException>()),
    );
  });

  test('regular file probe rejects missing paths and symbolic links', () async {
    final target = File('${temporaryDirectory.path}/target.txt');
    await target.writeAsString('content');
    final link = Link('${temporaryDirectory.path}/linked.txt');
    await link.create(target.path);

    expect(await isRegularFilePath(target.path), isTrue);
    expect(await isRegularFilePath(link.path), isFalse);
    expect(
      await isRegularFilePath('${temporaryDirectory.path}/missing.txt'),
      isFalse,
    );
  });

  test('directory probe rejects files and symbolic links', () async {
    final directory = Directory('${temporaryDirectory.path}/directory');
    await directory.create();
    final file = File('${temporaryDirectory.path}/file.txt');
    await file.writeAsString('content');
    final link = Link('${temporaryDirectory.path}/linked-directory');
    await link.create(directory.path);

    expect(await isDirectoryPath(directory.path), isTrue);
    expect(await isDirectoryPath(file.path), isFalse);
    expect(await isDirectoryPath(link.path), isFalse);
    expect(
      await probeFileSystemEntityType(link.path, followLinks: true),
      FileSystemEntityType.directory,
    );
    expect(
      await probeFileSystemEntityType('', followLinks: true),
      FileSystemEntityType.notFound,
    );
  });
}
