import 'dart:io';

import 'support/flutter_widget_check.dart';

// macOS 运行前将 DYLD_FRAMEWORK_PATH 指向已构建应用的 Contents/Frameworks。
// SHELL 可分别指定 /bin/zsh、/bin/bash，检查真实登录配置下的完整采集链路。
Future<void> main() => runFlutterWidgetCheck(
  root: File.fromUri(Platform.script).parent.parent,
  name: 'machine_maintenance_terminal',
  source: r'''
import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/machine_terminal/machine_terminal_service.dart';
import 'package:openhand/features/machine_terminal/machine_terminal_file_service.dart';
import 'package:openhand/features/machine_terminal/machine_terminal_command_protocol.dart';
import 'package:openhand/features/machine_terminal/machine_maintenance.dart';
import 'package:openhand/features/machine_terminal/machine_maintenance_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('真实登录终端连续采集、超时恢复和取消后复用', () async {
    final directory = await Directory.systemTemp.createTemp('openhand-terminal-check-');
    final service = MachineTerminalService(sessionsDirectoryPath: directory.path);
    final files = MachineTerminalFileService(service);
    try {
      await service.ensureWorkspace(sessionId: 'check', workingDirectory: directory.path, start: false);
      final terminal = service.activeTerminal('check')!;
      await terminal.start();
      Future<String> run(String command, {bool probe = false, bool cancel = false}) => files.runMaintenanceCommand(
        sessionId: 'check', terminalId: terminal.id, command: command,
        commandShell: probe ? MachineTerminalCommandShell.probe : MachineTerminalCommandShell.posix,
        isCancelled: () => cancel);
      final target = parseMachineTerminalShellProbe(await run(machineTerminalShellProbe, probe: true));
      expect(target.platform, Platform.isMacOS ? 'Darwin' : 'Linux');
      final shellVersion = parseMachineTerminalShellDetails(
        await run(machineTerminalShellDetailsCommand(target.shell)), target.shell);
      expect(shellVersion, startsWith(terminal.shell.split('/').last + ' '));
      final adapter = MachineMaintenancePlatformAdapter.forPlatform(target.platform);
      for (final workers in [4, 8]) {
        for (final tab in workers == 4 ? [0, 3, 0] : [0, 3, 0, 1, 2, 4, 5, 6]) {
          final timer = Stopwatch()..start();
          final result = await run(adapter.collect(tab, workers: workers));
          final snapshot = MachineMaintenanceSnapshot.parse(result);
          expect(snapshot.text('platform'), target.platform);
          expect(result, contains('__OH_OPS_end__'));
          print('真实终端采集通过：分区 $tab，并发 $workers，耗时 ${timer.elapsedMilliseconds} 毫秒。');
        }
      }
      if (terminal.shell.endsWith('/zsh') && Platform.isMacOS) {
        terminal.writeInput('/bin/bash --noprofile --norc\n');
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(await run("printf '嵌套终端可用'"), contains('嵌套终端可用'));
        terminal.writeInput('exit\n');
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(await run("printf '返回原终端'"), contains('返回原终端'));
      }
      final timedOut = await service.executeCommand(sessionId: 'check', terminalId: terminal.id,
        command: 'sleep 5', timeout: const Duration(milliseconds: 150),
        commandShell: MachineTerminalCommandShell.posix, displayOutput: false, recordHistory: false);
      expect(timedOut.timedOut, isTrue);
      expect(await run("printf '恢复成功'"), contains('恢复成功'));
      await expectLater(run(adapter.collect(0, workers: 8), cancel: true), throwsA(isA<MachineTerminalUploadCancelled>()));
      expect(await run("printf '取消后可用'"), contains('取消后可用'));
    } finally {
      await files.shutdown();
      files.dispose();
      await service.shutdown();
      service.dispose();
      await directory.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
''',
);
