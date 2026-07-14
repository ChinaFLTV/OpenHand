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
    final services = <MachineTerminalService>[];
    final firstService = MachineTerminalService(
      sessionsDirectoryPath: temporaryDirectory.path,
    );
    services.add(firstService);
    addTearDown(() async {
      for (final service in services) {
        await service.shutdown();
        service.dispose();
      }
      await temporaryDirectory.delete(recursive: true);
    });

    firstService.ensureWorkspace(sessionId: 'session', start: false);
    await firstService.newTerminal(sessionId: 'session', start: false);
    await firstService.shutdown();
    firstService.dispose();
    final historyFile = File(
      p.join(
        temporaryDirectory.path,
        'session',
        'machine-terminal-history.json',
      ),
    );
    expect(await historyFile.exists(), isTrue);
    final sentinelModified = DateTime.utc(2001, 2, 3, 4, 5, 6);
    await historyFile.setLastModified(sentinelModified);
    final storedSentinelModified = (await historyFile.stat()).modified;

    final restoredService = MachineTerminalService(
      sessionsDirectoryPath: temporaryDirectory.path,
    );
    services.add(restoredService);
    final restored = restoredService.ensureWorkspace(
      sessionId: 'session',
      start: false,
    );
    await restoredService.selectTerminal(
      sessionId: 'session',
      terminalId: restored.activeTerminalId,
    );
    await restoredService.shutdown();

    expect((await historyFile.stat()).modified, storedSentinelModified);
  });
}
