import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/bounded_file_io.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'openhand-bounded-file-io-',
    );
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

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

  test('bounded string reader rejects malformed UTF-8', () async {
    final file = File('${temporaryDirectory.path}/malformed.txt');
    await file.writeAsBytes(<int>[0xc3, 0x28]);

    await expectLater(
      readBoundedFileString(file, maxBytes: 16),
      throwsA(isA<FormatException>()),
    );
  });
}
