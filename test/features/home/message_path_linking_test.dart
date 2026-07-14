import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/home/util/message_path_linking.dart';
import 'package:path/path.dart' as p;

import '../../support/test_directory.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'openhand-message-path-',
    );
  });

  tearDown(() => deleteTestDirectory(temporaryDirectory));

  test(
    'synchronous lookup reads only the asynchronous resolution cache',
    () async {
      final file = File(p.join(temporaryDirectory.path, 'example.txt'));
      await file.writeAsString('content');
      final roots = <String>[temporaryDirectory.path];

      expect(resolveExistingMessagePath('example.txt', roots), isNull);

      final resolved = await resolveExistingMessagePathAsync(
        'example.txt',
        roots,
      );

      expect(resolved?.resolvedPath, file.path);
      expect(
        resolveExistingMessagePath('example.txt', roots)?.resolvedPath,
        file.path,
      );
    },
  );

  test('lexical candidate resolution performs no existence requirement', () {
    final candidate = firstMessagePathCandidate('future/video.mp4', <String>[
      temporaryDirectory.path,
    ]);

    expect(candidate, p.join(temporaryDirectory.path, 'future', 'video.mp4'));
  });
}
