import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/machine_terminal/machine_terminal_service.dart';
import 'package:path/path.dart' as p;

import '../../support/test_directory.dart';

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
    await expectLater(
      service.ensureWorkspace(sessionId: 'late-session', start: false),
      throwsA(isA<StateError>()),
    );
  });

  test('current atomic temp is restored without rewriting history', () async {
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
      await deleteTestDirectory(temporaryDirectory);
    });

    await firstService.ensureWorkspace(sessionId: 'session', start: false);
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
    final readyFile = File('${historyFile.path}.tmp.test-ready');
    await historyFile.rename(readyFile.path);
    expect(await historyFile.exists(), isFalse);

    final restoredService = MachineTerminalService(
      sessionsDirectoryPath: temporaryDirectory.path,
    );
    services.add(restoredService);
    final restored = await restoredService.ensureWorkspace(
      sessionId: 'session',
      start: false,
    );
    await restoredService.selectTerminal(
      sessionId: 'session',
      terminalId: restored.activeTerminalId,
    );
    await restoredService.shutdown();

    expect(await readyFile.exists(), isFalse);
    expect(await historyFile.exists(), isTrue);
    expect((await historyFile.stat()).modified, storedSentinelModified);
  });

  test('concurrent workspace initialization is single-flight', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'openhand-machine-terminal-single-flight-',
    );
    final service = MachineTerminalService(
      sessionsDirectoryPath: temporaryDirectory.path,
    );
    addTearDown(() async {
      await service.shutdown();
      service.dispose();
      await deleteTestDirectory(temporaryDirectory);
    });

    final snapshots = await Future.wait<MachineTerminalWorkspaceSnapshot>(
      <Future<MachineTerminalWorkspaceSnapshot>>[
        service.ensureWorkspace(sessionId: 'session', start: false),
        service.ensureWorkspace(sessionId: 'session', start: false),
      ],
    );

    expect(snapshots, hasLength(2));
    expect(snapshots.first.terminals, hasLength(1));
    expect(snapshots.last.activeTerminalId, snapshots.first.activeTerminalId);
  });
}
