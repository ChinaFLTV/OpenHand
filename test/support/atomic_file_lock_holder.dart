import 'dart:async';
import 'dart:io';

const Duration _releasePollInterval = Duration(milliseconds: 10);
const Duration _releaseTimeout = Duration(seconds: 15);

Future<void> main(List<String> arguments) async {
  if (arguments.length != 3) {
    stderr.writeln('Expected lock, ready, and release file paths.');
    exitCode = 64;
    return;
  }

  final lockFile = File(arguments[0]);
  final readyFile = File(arguments[1]);
  final releaseFile = File(arguments[2]);
  await lockFile.parent.create(recursive: true);
  final handle = await lockFile.open(mode: FileMode.append);
  var locked = false;
  try {
    await handle.lock();
    locked = true;
    await readyFile.writeAsString('ready', flush: true);
    final deadline = DateTime.now().add(_releaseTimeout);
    while (!await releaseFile.exists()) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException(
          'Timed out waiting for the test process to release the lock.',
          _releaseTimeout,
        );
      }
      await Future<void>.delayed(_releasePollInterval);
    }
  } finally {
    if (locked) await handle.unlock();
    await handle.close();
  }
}
