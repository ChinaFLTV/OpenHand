import 'dart:io';

import 'support/flutter_widget_check.dart';

// macOS 运行前将 DYLD_FRAMEWORK_PATH 指向已构建应用的 Contents/Frameworks。
// SHELL 可分别指定 /bin/zsh、/bin/bash，检查真实登录配置下的完整采集链路。
Future<void> main() => runFlutterWidgetCheck(
  root: File.fromUri(Platform.script).parent.parent,
  name: 'machine_maintenance_terminal',
  source: r'''
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/machine_terminal/machine_terminal_service.dart';
import 'package:openhand/features/machine_terminal/machine_terminal_file_service.dart';
import 'package:openhand/features/machine_terminal/machine_terminal_command_protocol.dart';
import 'package:openhand/features/machine_terminal/machine_maintenance.dart';
import 'package:openhand/features/machine_terminal/machine_maintenance_platform.dart';
import 'package:openhand/features/machine_terminal/machine_containers.dart';
import 'package:openhand/features/machine_terminal/machine_scheduled_tasks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('普通输入模式的交互 Bash 保持容器上下文和 JSON 输出纯净', () async {
    if (Platform.isWindows) return;
    final directory = await Directory.systemTemp.createTemp('openhand-container-terminal-');
    final service = MachineTerminalService(sessionsDirectoryPath: directory.path);
    final files = MachineTerminalFileService(service);
    try {
      await service.ensureWorkspace(sessionId: 'container-check', workingDirectory: directory.path, start: false);
      final terminal = service.activeTerminal('container-check')!;
      await terminal.start();
      terminal.writeInput('/bin/bash --noprofile --norc\n');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      terminal.writeInput("PS1='[root@test ~]# '; PS2='> '; bind 'set enable-bracketed-paste off' 2>/dev/null\n");
      await Future<void>.delayed(const Duration(milliseconds: 300));
      Future<String> run(String command) => files.runMaintenanceCommand(
        sessionId: 'container-check', terminalId: terminal.id, command: command,
        maxOutputCharacters: machineContainerOutputLimit,
        commandShell: MachineTerminalCommandShell.posix);
      expect((await run("printf 'default\\n'")).trim(), 'default');
      terminal.writeInput(r"""
docker() {
  case "$1" in
    context) printf 'default\n';;
    ps) printf '%s\n' '{"ID":"abc123","Names":"服务","State":"running"}';;
    info) printf '%s\n' '{"ServerVersion":"27.5.1"}';;
    stats) printf '%s\n' '{"Name":"服务","CPUPerc":"4.2%"}';;
    *) return 64;;
  esac
}
""");
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final selected = await discoverMachineContainers(run: run);
      expect(selected.client.contextName, 'default');
      expect(selected.entries.single.name, '服务');
      expect(jsonDecode(await selected.client.execute(selected.client.metadataArguments))['ServerVersion'], '27.5.1');
      expect(jsonDecode(await selected.client.execute(selected.client.metricsArguments))['CPUPerc'], '4.2%');
      expect((await run("printf '%s\\n' '[root@test ~]# 这是数据' '> 这也是数据'")).trim(),
          '[root@test ~]# 这是数据\n> 这也是数据');
      await expectLater(run('exit 7'), throwsStateError);
      expect((await run("printf '失败后可用'")).trim(), '失败后可用');
    } finally {
      await files.shutdown(); files.dispose();
      await service.shutdown(); service.dispose();
      await directory.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 1)));
  test('真实终端完整传输较大定时任务定义并拒绝过期覆盖', () async {
    if (Platform.isWindows) return;
    final directory = await Directory.systemTemp.createTemp('openhand-task-terminal-');
    final service = MachineTerminalService(sessionsDirectoryPath: directory.path);
    final files = MachineTerminalFileService(service);
    try {
      final bin = await Directory('${directory.path}/bin').create();
      final store = File('${directory.path}/cron');
      final original = '${List.filled(500, '# 保留任务环境和注释').join('\n')}\n0 1 * * * echo preserved\n0 2 * * * echo selected\n';
      await store.writeAsString(original);
      final tool = File('${bin.path}/crontab');
      await tool.writeAsString('#!/bin/sh\nif [ "\$1" = -u ]; then shift 2; fi\nif [ "\$1" = -l ]; then cat "\$TASK_STORE"; else cp "\$1" "\$TASK_STORE"; fi\n');
      await Process.run('chmod', ['+x', tool.path]);
      await service.ensureWorkspace(sessionId:'tasks',workingDirectory:directory.path,start:false);
      final terminal=service.activeTerminal('tasks')!; await terminal.start();
      terminal.writeInput('/bin/bash --noprofile --norc\n');
      await Future<void>.delayed(const Duration(milliseconds:300));
      terminal.writeInput('export PATH="${bin.path}:\$PATH" TASK_STORE="${store.path}"\n');
      await Future<void>.delayed(const Duration(milliseconds:300));
      Future<String> run(String command) => files.runMaintenanceCommand(sessionId:'tasks',terminalId:terminal.id,command:command,
        commandShell:MachineTerminalCommandShell.posix,maxOutputCharacters:machineScheduledTaskOutputLimit,timeout:machineScheduledTaskTimeout);
      String record(String kind,List<String> values) => '__OH_TASK__\t$kind\t${values.map((v)=>base64Encode(utf8.encode(v))).join('\t')}\n';
      final data=MachineScheduledTaskSnapshot.parse('${record('meta',['tester','UTC','2026-09-30'])}${record('cron',['user:tester','tester',original,'1'])}__OH_TASK_END__');
      final client=MachineScheduledTaskClient(platform:'Linux',run:run);
      await client.saveCron(data,data.tasks.last,schedule:'0 3 * * *',command:'echo updated',enabled:true);
      expect(await store.readAsString(),original.replaceAll('0 2 * * * echo selected','0 3 * * * echo updated'));
      await expectLater(client.delete(data.tasks.first),throwsA(isA<MachineTaskException>().having((e)=>e.code,'冲突','conflict')));
      expect((await run("printf '终端仍可用'")).trim(),'终端仍可用');
    } finally {
      await files.shutdown();files.dispose();await service.shutdown();service.dispose();await directory.delete(recursive:true);
    }
  },timeout:const Timeout(Duration(minutes:2)));
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
      expect(service.terminalFor('check', terminal.id), same(terminal));
      final ready = Completer<void>();
      final interactive = service.executeCommand(
        sessionId: 'check', terminalId: terminal.id,
        command: "printf '交互就绪\\n'; read answer; printf '收到:%s\\n' \"\$answer\"",
        commandShell: MachineTerminalCommandShell.posix,
        timeout: const Duration(seconds: 10), recordHistory: false,
        onOutput: (output) { if (output.contains('交互就绪') && !ready.isCompleted) ready.complete(); },
      );
      await ready.future.timeout(const Duration(seconds: 5));
      await service.writeInput(sessionId: 'check', terminalId: terminal.id, data: '容器交互检查\n');
      expect((await interactive).output, contains('收到:容器交互检查'));
      final large = await files.runMaintenanceCommand(sessionId: 'check', terminalId: terminal.id,
        command: "awk 'BEGIN { for(i=0;i<180000;i++) printf \"x\" }'",
        maxOutputCharacters: 200000);
      expect(large.trim().length, 180000, reason: '结构化报告不能沿用工具输出的截断值');
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
