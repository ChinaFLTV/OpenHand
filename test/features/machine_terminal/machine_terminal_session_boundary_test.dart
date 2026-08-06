import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/machine_terminal/index.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory sessionsDirectory;
  late MachineTerminalService service;

  setUp(() async {
    sessionsDirectory = await Directory.systemTemp.createTemp(
      'openhand_terminal_boundary_',
    );
    service = MachineTerminalService(
      sessionsDirectoryPath: sessionsDirectory.path,
    );
  });

  tearDown(() async {
    await service.shutdown();
    service.dispose();
    if (await sessionsDirectory.exists()) {
      await sessionsDirectory.delete(recursive: true);
    }
  });

  test('禁用自动启动时读写不会创建新 PTY', () async {
    const sessionId = 'no-auto-start';
    final initial = await service.ensureWorkspace(
      sessionId: sessionId,
      workingDirectory: sessionsDirectory.path,
      start: false,
    );
    expect(initial.activeTerminal?.pid, isNull);

    final result = await service.executeCommand(
      sessionId: sessionId,
      command: 'pwd',
      timeout: const Duration(seconds: 1),
      startIfNeeded: false,
    );
    expect(result.succeeded, isFalse);
    expect(service.snapshot(sessionId)?.activeTerminal?.pid, isNull);

    await expectLater(
      service.writeInput(
        sessionId: sessionId,
        data: 'pwd',
        appendNewline: true,
        startIfNeeded: false,
      ),
      throwsStateError,
    );
    expect(service.snapshot(sessionId)?.activeTerminal?.pid, isNull);
  });

  test(
    '命令超时后保留同一 PTY 并可继续执行',
    () async {
      const sessionId = 'timeout-preserves-session';
      await service.ensureWorkspace(
        sessionId: sessionId,
        workingDirectory: sessionsDirectory.path,
        start: false,
      );
      await service.startTerminal(sessionId: sessionId);
      final before = service.snapshot(sessionId)!.activeTerminal!;
      if (before.pid == null &&
          Platform.isMacOS &&
          (Platform.environment['DYLD_FRAMEWORK_PATH']?.trim().isEmpty ??
              true)) {
        markTestSkipped('当前 Flutter 测试宿主未装载原生 PTY 库。');
        return;
      }
      expect(before.pid, isNotNull);

      final timedOut = await service.executeCommand(
        sessionId: sessionId,
        command: "trap '' INT; sleep 3",
        timeout: const Duration(seconds: 1),
        startIfNeeded: false,
      );
      final afterTimeout = service.snapshot(sessionId)!.activeTerminal!;
      expect(timedOut.timedOut, isTrue);
      expect(timedOut.error, contains('未重启终端'));
      expect(afterTimeout.status, MachineTerminalStatus.running);
      expect(afterTimeout.terminalId, before.terminalId);
      expect(afterTimeout.pid, before.pid);

      await Future<void>.delayed(const Duration(seconds: 2));
      final followUp = await service.executeCommand(
        sessionId: sessionId,
        command: 'printf session-preserved',
        timeout: const Duration(seconds: 2),
        startIfNeeded: false,
      );
      final afterFollowUp = service.snapshot(sessionId)!.activeTerminal!;
      expect(
        followUp.succeeded,
        isTrue,
        reason: '${followUp.toToolOutput()}\n终端输出：\n${afterFollowUp.output}',
      );
      expect(followUp.output, contains('session-preserved'));
      expect(afterFollowUp.pid, before.pid);
    },
    skip: Platform.isWindows ? 'Windows PTY 不支持 POSIX 信号测试。' : false,
  );
}
