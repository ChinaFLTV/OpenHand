import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/db/atomic_file_operations.dart';
import 'package:path/path.dart' as p;

const String _processLockDirectoryName = 'openhand-atomic-locks-v1';
const Duration _processReadyTimeout = Duration(seconds: 5);
const Duration _writeTimeout = Duration(seconds: 5);

void main() {
  test(
    'atomic writes wait for the same target lock in another process',
    () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'openhand-atomic-lock-test-',
      );
      final target = File(p.join(temporaryDirectory.path, 'state.json'));
      final ready = File(p.join(temporaryDirectory.path, 'holder.ready'));
      final release = File(p.join(temporaryDirectory.path, 'holder.release'));
      await target.writeAsString('old');
      final lockFile = _processLockFile(target);
      final holder = await Process.start(
        'dart',
        <String>[
          'run',
          p.join('test', 'support', 'atomic_file_lock_holder.dart'),
          lockFile.path,
          ready.path,
          release.path,
        ],
        workingDirectory: Directory.current.path,
        runInShell: Platform.isWindows,
      );
      final stdoutFuture = holder.stdout.transform(utf8.decoder).join();
      final stderrFuture = holder.stderr.transform(utf8.decoder).join();

      try {
        await _waitForFile(ready, timeout: _processReadyTimeout);
        var completed = false;
        final write = writeFileAtomically(target, 'new').whenComplete(() {
          completed = true;
        });

        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(completed, isFalse);
        expect(await target.readAsString(), 'old');

        await release.writeAsString('release', flush: true);
        await write.timeout(_writeTimeout);
        expect(await target.readAsString(), 'new');
        expect(await holder.exitCode.timeout(_writeTimeout), 0);
        expect(await stderrFuture, isEmpty);
        await stdoutFuture;
      } finally {
        if (!await release.exists()) {
          await release.writeAsString('release', flush: true);
        }
        try {
          await holder.exitCode.timeout(const Duration(seconds: 2));
        } on TimeoutException {
          holder.kill();
        }
        if (await lockFile.exists()) await lockFile.delete();
        if (await temporaryDirectory.exists()) {
          await temporaryDirectory.delete(recursive: true);
        }
      }
    },
  );
}

File _processLockFile(File targetFile) {
  var identity = p.normalize(p.absolute(targetFile.path));
  if (Platform.isWindows) identity = identity.toLowerCase();
  final digest = sha256.convert(utf8.encode(identity));
  return File(
    p.join(
      Directory.systemTemp.path,
      _processLockDirectoryName,
      '$digest.lock',
    ),
  );
}

Future<void> _waitForFile(File file, {required Duration timeout}) async {
  final deadline = DateTime.now().add(timeout);
  while (!await file.exists()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Timed out waiting for ${file.path}.', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
