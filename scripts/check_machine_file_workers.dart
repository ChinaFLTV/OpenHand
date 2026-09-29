import 'dart:io';

import 'support/flutter_widget_check.dart';

Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent;
  final source = await File(
    '${root.path}/lib/features/machine_terminal/machine_terminal_file_service.dart',
  ).readAsString();
  final commands = source.substring(
    source.indexOf('String _parallelWindowsFileCommands'),
    source.indexOf('String _fileDetailsCommand'),
  );
  await runFlutterWidgetCheck(
    root: root,
    name: 'machine_file_workers',
    source:
        '''
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/machine_terminal/machine_maintenance_parallel.dart';
import 'package:openhand/features/machine_terminal/machine_terminal_file_service.dart';
import 'package:openhand/shared/util/platform_shell.dart';
import 'package:openhand/features/machine_terminal/machine_terminal_service.dart';
import 'package:openhand/features/machine_terminal/machine_terminal_command_protocol.dart';
const _machineTerminalDirectoryEntryLimit = 2000;
const _machineTerminalFileWorkers = 8;
$commands
$_checks
''',
  );
}

const _checks = r'''
class _CommandTerminal extends Fake implements MachineTerminalService {
  _CommandTerminal(this.sessionsDirectoryPath, this.temporaryDirectory);
  @override
  final String sessionsDirectoryPath;
  final String temporaryDirectory;
  bool failWrite = false;
  bool cancelAfterWrite = false;
  bool cancelled = false;
  final commands = <String>[];

  @override
  Future<MachineTerminalCommandResult> executeCommand({
    required String sessionId, required String command, String? terminalId,
    Duration timeout = const Duration(seconds: 30), bool startIfNeeded = true,
    bool recordHistory = true, bool displayOutput = true,
    MachineTerminalCommandShell commandShell = MachineTerminalCommandShell.automatic,
    MachineTerminalCommandOutputCallback? onOutput,
  }) async {
    expect(recordHistory, isFalse);
    expect(displayOutput, isFalse);
    expect(timeout, lessThanOrEqualTo(const Duration(seconds: 30)));
    commands.add(command);
    final payload = machineTerminalCommandPayload(command: command,
      beginMarker: '开始', endMarker: '结束', shell: commandShell);
    for (final line in const LineSplitter().convert(payload)) {
      expect(utf8.encode(line).length, lessThan(1024), reason: '终端物理行超过安全上限');
    }
    final write = command.startsWith("printf '%s'");
    if (write && failWrite) {
      return MachineTerminalCommandResult(terminalId: terminalId!, command: command,
        output: '', status: MachineTerminalStatus.running, durationMs: 0, timedOut: true);
    }
    final result = await Process.run('/bin/sh', ['-c', command],
      environment: {'TMPDIR': temporaryDirectory});
    if (write && cancelAfterWrite) cancelled = true;
    return MachineTerminalCommandResult(terminalId: terminalId!, command: command,
      output: result.stdout as String, error: result.exitCode == 0 ? null : result.stderr as String,
      status: MachineTerminalStatus.running, durationMs: 0, exitCode: result.exitCode);
  }
}

void main() {
  test('分段参数保留空值、引号、换行和跨分段 Unicode，禁止注入', () async {
    if (Platform.isWindows) return;
    for (final value in ['', List.filled(63, '字').join() + '😀' + List.filled(80, "'美元\$;").join(), '第一行\n第二行']) {
      final result = await Process.run('/bin/sh', ['-c', "printf '%s' " + machineTerminalPosixArgument(value)]);
      expect(result.exitCode, 0);
      expect(result.stdout, value);
    }
  });

  test('长脚本传输成功、超时或取消均清理临时文件，失败后释放门闩', () async {
    if (Platform.isWindows) return;
    final root = await Directory.systemTemp.createTemp('openhand-transport-');
    final temporary = await Directory(root.path + '/' + List.filled(40, '路径').join() + "'" + '/' + List.filled(40, '目录').join()).create(recursive: true);
    final terminal = _CommandTerminal(root.path, temporary.path);
    final service = MachineTerminalFileService(terminal);
    final command = List.filled(100, '# 中文注释与特殊字符 😀').join('\n') + "\nprintf '完整结果'";
    Future<String> run() => service.runMaintenanceCommand(sessionId: '会话', terminalId: '终端',
      command: command, isCancelled: () => terminal.cancelled);
    try {
      terminal.cancelled = true;
      await expectLater(run(), throwsA(isA<MachineTerminalUploadCancelled>()));
      expect(terminal.commands, isEmpty);
      terminal.cancelled = false;
      terminal.failWrite = true;
      await expectLater(run(), throwsA(isA<TimeoutException>()));
      expect(await temporary.list().toList(), isEmpty);
      terminal.failWrite = false;
      terminal.cancelAfterWrite = true;
      await expectLater(run(), throwsA(isA<MachineTerminalUploadCancelled>()));
      expect(await temporary.list().toList(), isEmpty);
      terminal.cancelled = false;
      terminal.cancelAfterWrite = false;
      expect(await run(), '完整结果');
      expect(await temporary.list().toList(), isEmpty);
      expect(terminal.commands.last, contains('base64 -d'));
      await expectLater(service.runMaintenanceCommand(sessionId: '会话', terminalId: '终端',
        command: command + '\nexit 7'), throwsStateError);
      expect(await temporary.list().toList(), isEmpty);
      expect(await run(), '完整结果');
    } finally {
      await service.shutdown();
      service.dispose();
      await root.delete(recursive: true);
    }
  });

  test('八路目录读取保留特殊名称、链接与子项数量，失败不伪装为空目录', () async {
    if (Platform.isWindows) return;
    final root = await Directory.systemTemp.createTemp('openhand-file-workers-');
    try {
      final names = [for (var i = 0; i < 33; i++) '文件 $i', '.隐藏', '单引号\'与换行\n'];
      for (final name in names) { await File('${root.path}/$name').writeAsString('内容'); }
      final child = await Directory('${root.path}/子目录').create();
      await File('${child.path}/文件').writeAsString('内容');
      await Directory('${child.path}/下级').create();
      await Link('${root.path}/链接').create('${root.path}/${names.first}');
      final command = _listDirectoryCommand(root.path);
      expect(command, contains('oh_workers=8'));
      final result = await Process.run('sh', ['-c', command]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final output = result.stdout as String;
      final rows = const LineSplitter().convert(output).where((line) => line.startsWith('E\t')).map((line) => line.split('\t')).toList();
      final actual = rows.map((row) => utf8.decode(base64Decode(row[5]))).toList();
      expect(actual.toSet(), {...names, '子目录', '链接'});
      expect(actual.length, actual.toSet().length);
      final directory = rows.singleWhere((row) => utf8.decode(base64Decode(row[5])) == '子目录');
      expect(directory.sublist(7), ['1', '1']);
      final missing = await Process.run('sh', ['-c', _listDirectoryCommand('${root.path}/不存在')]);
      expect(missing.exitCode, isNot(0));
    } finally { await root.delete(recursive: true); }
  });
}
''';
