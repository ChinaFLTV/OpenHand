import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/android_reverse/android_reverse_adb_client.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'openhand_adb_client_test_',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test(
    'preserves stdout and stderr for a non-zero adb exit',
    () async {
      final executable = await _writeExecutable(
        temporaryDirectory,
        'fake-adb-exit',
        '''#!/bin/sh
printf 'stdout-value\\n'
printf 'stderr-value\\n' >&2
exit 7
''',
      );
      final client = AndroidReverseAdbClient(adbPath: executable);

      final result = await client.disconnect();

      expect(result.exitCode, 7);
      expect(result.timedOut, isFalse);
      expect(result.stdout, 'stdout-value\n');
      expect(result.stderr, 'stderr-value\n');
    },
    skip: Platform.isWindows,
  );

  test(
    'returns partial stdout when an adb command times out',
    () async {
      final executable = await _writeExecutable(
        temporaryDirectory,
        'fake-adb-timeout',
        '''#!/bin/sh
printf 'partial-before-timeout\\n'
sleep 30
''',
      );
      final client = AndroidReverseAdbClient(adbPath: executable);

      final result = await client.shellDetailed(
        'ignored',
        timeout: const Duration(milliseconds: 100),
      );

      expect(result.exitCode, -1);
      expect(result.timedOut, isTrue);
      expect(result.partialOk, isTrue);
      expect(result.stdout, contains('partial-before-timeout'));
      expect(result.stderr, contains('timed out'));
    },
    skip: Platform.isWindows,
  );
}

Future<String> _writeExecutable(
  Directory directory,
  String name,
  String contents,
) async {
  final file = File('${directory.path}/$name');
  await file.writeAsString(contents, flush: true);
  final chmod = await Process.run('chmod', <String>['700', file.path]);
  if (chmod.exitCode != 0) {
    throw StateError('chmod failed: ${chmod.stderr}');
  }
  return file.path;
}
