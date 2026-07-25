import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/machine_terminal/machine_terminal_service.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('同一终端会拒绝并发命令而不是交错执行', () async {
    final session = MachineTerminalSession(
      id: 'term-1',
      sessionId: 'session-a',
      identity: 'machine-term-1',
      shell: Platform.isWindows ? 'cmd.exe' : '/bin/sh',
      workingDirectory: Directory.current.path,
      onChanged: () {},
    );

    final first = session.executeCommand(
      command: 'first',
      beginMarker: 'FIRST_BEGIN',
      endMarker: 'FIRST_END',
      timeout: const Duration(seconds: 1),
    );
    final second = session.executeCommand(
      command: 'second',
      beginMarker: 'SECOND_BEGIN',
      endMarker: 'SECOND_END',
      timeout: const Duration(seconds: 1),
    );

    expect((await first).error, 'Machine terminal is not running.');
    expect(
      (await second).error,
      'Another terminal command is already running.',
    );
    session.dispose();
  });

  test('拒绝可能造成存储目录碰撞的会话标识符', () async {
    final service = MachineTerminalService(
      sessionsDirectoryPath: Directory.systemTemp.path,
    );
    try {
      await expectLater(
        service.ensureWorkspace(sessionId: '../session-a', start: false),
        throwsArgumentError,
      );
    } finally {
      await service.shutdown();
    }
  });

  test('释放工作区会同时清理终端历史原子写入残留', () async {
    final root = await Directory.systemTemp.createTemp(
      'openhand-machine-terminal-test-',
    );
    final service = MachineTerminalService(sessionsDirectoryPath: root.path);
    final historyPath = p.join(
      root.path,
      'session-a',
      'machine-terminal-history.json',
    );
    final history = File(historyPath);
    final backup = File('$historyPath.bak');
    final temporary = File('$historyPath.tmp.123');

    try {
      await history.parent.create(recursive: true);
      await history.writeAsString('history');
      await backup.writeAsString('backup');
      await temporary.writeAsString('temporary');

      await service.disposeWorkspace('session-a');

      expect(await history.exists(), isFalse);
      expect(await backup.exists(), isFalse);
      expect(await temporary.exists(), isFalse);
    } finally {
      await service.shutdown();
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    }
  });
}
