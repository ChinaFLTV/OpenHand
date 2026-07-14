import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/directory_cleanup.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'openhand-directory-cleanup-',
    );
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'empty-directory check distinguishes empty and populated directories',
    () async {
      final directory = Directory('${temporaryDirectory.path}/child');
      await directory.create();

      expect(await isDirectoryEmpty(directory), isTrue);

      await File('${directory.path}/file.txt').writeAsString('content');
      expect(await isDirectoryEmpty(directory), isFalse);
    },
  );

  test(
    'empty-directory check rejects symbolic links',
    () async {
      final target = Directory('${temporaryDirectory.path}/target');
      await target.create();
      final link = Link('${temporaryDirectory.path}/link');
      await link.create(target.path);

      expect(await isDirectoryEmpty(Directory(link.path)), isFalse);
    },
    skip: Platform.isWindows ? 'Symbolic links may require elevation.' : false,
  );
}
