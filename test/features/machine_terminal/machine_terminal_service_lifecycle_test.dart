import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/machine_terminal/machine_terminal_service.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('shutdown and notifier disposal are idempotent', () async {
    final service = MachineTerminalService();

    await Future.wait<void>(<Future<void>>[
      service.shutdown(),
      service.shutdown(),
    ]);
    service.dispose();

    expect(service.dispose, returnsNormally);
    await expectLater(service.shutdown(), completes);
    expect(
      () => service.ensureWorkspace(sessionId: 'late-session', start: false),
      throwsStateError,
    );
  });

  test('unchanged terminal history is not rewritten', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'openhand-machine-terminal-',
    );
    final service = MachineTerminalService(
      sessionsDirectoryPath: temporaryDirectory.path,
    );
    addTearDown(() async {
      await service.shutdown();
      service.dispose();
      await temporaryDirectory.delete(recursive: true);
    });

    service.ensureWorkspace(sessionId: 'session', start: false);
    final terminal = await service.newTerminal(
      sessionId: 'session',
      start: false,
    );
    await Future<void>.delayed(const Duration(milliseconds: 800));
    final historyFile = File(
      p.join(
        temporaryDirectory.path,
        'session',
        'machine-terminal-history.json',
      ),
    );
    expect(await historyFile.exists(), isTrue);
    final firstModified = (await historyFile.stat()).modified;

    await service.selectTerminal(sessionId: 'session', terminalId: terminal.id);
    await Future<void>.delayed(const Duration(milliseconds: 800));

    expect((await historyFile.stat()).modified, firstModified);
  });
}
