import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/db/atomic_file_operations.dart';

void main() {
  group('writeFileAtomically', () {
    test('serializes writes to the same target path', () async {
      final dir = await Directory.systemTemp.createTemp('openhand_atomic_');
      addTearDown(() => dir.delete(recursive: true));
      final target = File('${dir.path}/settings.json');

      await Future.wait<void>(<Future<void>>[
        writeFileAtomically(target, 'one'),
        writeFileAtomically(target, 'two'),
        writeFileAtomically(target, 'three'),
      ]);

      expect(await target.readAsString(), 'three');
      expect(await File('${target.path}.tmp').exists(), isFalse);
      expect(await File('${target.path}.bak').exists(), isFalse);
    });
  });

  group('writeFileBytesAtomically', () {
    test('writes bytes with the same cleanup contract', () async {
      final dir = await Directory.systemTemp.createTemp('openhand_atomic_');
      addTearDown(() => dir.delete(recursive: true));
      final target = File('${dir.path}/payload.bin');

      await writeFileBytesAtomically(target, <int>[1, 2, 3, 4]);

      expect(await target.readAsBytes(), <int>[1, 2, 3, 4]);
      expect(await File('${target.path}.tmp').exists(), isFalse);
      expect(await File('${target.path}.bak').exists(), isFalse);
    });
  });

  group('recoverAtomicWriteBackupIfNeeded', () {
    test(
      'restores an orphaned temp file before falling back to backup',
      () async {
        final dir = await Directory.systemTemp.createTemp('openhand_atomic_');
        addTearDown(() => dir.delete(recursive: true));
        final target = File('${dir.path}/state.json');
        await File('${target.path}.tmp').writeAsString('temp');
        await File('${target.path}.bak').writeAsString('backup');

        await recoverAtomicWriteBackupIfNeeded(target);

        expect(await target.readAsString(), 'temp');
        expect(await File('${target.path}.bak').readAsString(), 'backup');
      },
    );

    test('restores backup when target and temp are missing', () async {
      final dir = await Directory.systemTemp.createTemp('openhand_atomic_');
      addTearDown(() => dir.delete(recursive: true));
      final target = File('${dir.path}/state.json');
      await File('${target.path}.bak').writeAsString('backup');

      await recoverAtomicWriteBackupIfNeeded(target);

      expect(await target.readAsString(), 'backup');
      expect(await File('${target.path}.bak').exists(), isFalse);
    });
  });
}
