import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/db/atomic_file_operations.dart';

void main() {
  Future<Directory> createTempDir() async {
    final dir = await Directory.systemTemp.createTemp(
      'openhand_atomic_file_ops_test_',
    );
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });
    return dir;
  }

  test('recover keeps recent temp artifacts when target is intact', () async {
    final dir = await createTempDir();
    final target = File('${dir.path}/data.json');
    final recentTemp = File('${target.path}.tmp');

    await target.writeAsString('current');
    await recentTemp.writeAsString('pending');

    await recoverAtomicWriteBackupIfNeeded(target);

    expect(await target.readAsString(), 'current');
    expect(await recentTemp.exists(), isTrue);
  });

  test('recover removes stale temp artifacts when target is intact', () async {
    final dir = await createTempDir();
    final target = File('${dir.path}/data.json');
    final staleTemp = File('${target.path}.tmp');

    await target.writeAsString('current');
    await staleTemp.writeAsString('stale');
    await staleTemp.setLastModified(
      DateTime.now().subtract(const Duration(minutes: 11)),
    );

    await recoverAtomicWriteBackupIfNeeded(target);

    expect(await target.readAsString(), 'current');
    expect(await staleTemp.exists(), isFalse);
  });

  test('recover restores newest temp artifact before backup', () async {
    final dir = await createTempDir();
    final target = File('${dir.path}/data.json');
    final backup = File('${target.path}.bak');
    final olderTemp = File('${target.path}.tmp.older');
    final newerTemp = File('${target.path}.tmp.newer');

    await backup.writeAsString('backup');
    await olderTemp.writeAsString('older');
    await newerTemp.writeAsString('newer');
    await olderTemp.setLastModified(
      DateTime.now().subtract(const Duration(minutes: 2)),
    );

    await recoverAtomicWriteBackupIfNeeded(target);

    expect(await target.readAsString(), 'newer');
    expect(await backup.exists(), isFalse);
  });

  test('concurrent writes and recoveries do not lose temp files', () async {
    final dir = await createTempDir();
    final target = File('${dir.path}/data.json');

    await writeFileAtomically(target, 'seed');

    final tasks = <Future<void>>[];
    for (var i = 0; i < 80; i++) {
      tasks.add(writeFileAtomically(target, 'value-$i'));
      tasks.add(recoverAtomicWriteBackupIfNeeded(target));
    }

    await Future.wait(tasks);

    expect(await target.exists(), isTrue);
    expect(await target.readAsString(), startsWith('value-'));
  });
}
