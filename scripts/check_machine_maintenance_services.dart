import 'dart:io';

import 'package:openhand/features/machine_terminal/machine_maintenance.dart';
import 'package:openhand/features/machine_terminal/machine_maintenance_platform.dart';
import 'package:openhand/features/machine_terminal/machine_maintenance_readout.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  final mac = MachineMaintenancePlatformAdapter.forPlatform('Darwin');
  final launchd = mac.servicesFor('launchd')!;
  final detail = launchd.command('com.apple.bird');
  check(
    detail.contains('launchctl print') && detail.contains('alarm 6'),
    'macOS 详情或日志超时缺失',
  );
  check(mac.collect(2).contains('section service_processes'), '服务资源缺少批量采样');
  for (final name in ['bad;touch /tmp/x', 'bad\nname', '../service']) {
    check(!launchd.accepts(name), '服务名称校验失效');
  }
  final fields = MachineMaintenanceReadout.parse('''目标 = gui/501/com.example
state = running
program = /Applications/Example App/run
arguments = {
  /Applications/Example App/run
  --flag
}
runs = 3
last exit code = 0
''', 'status');
  check(fields.fields && fields.rows.length == 6, '服务运行详情未按固定字段解析');
  check(
    fields.rows.any(
      (row) => row[0] == 'arguments' && row[1].contains('--flag'),
    ),
    '启动参数丢失',
  );
  for (final manager in ['systemd', 'OpenRC', 'SysV', 'runit']) {
    final adapter = MachineMaintenanceServiceAdapter.detect(manager)!;
    final command = adapter.command(
      manager == 'systemd'
          ? 'example.service'
          : manager == 'runit'
          ? '/etc/service/example'
          : 'example',
    );
    check(
      command.contains('section logs') && command.contains('-n 120'),
      '$manager 缺少有界服务日志',
    );
  }
  final windows = MachineMaintenancePlatformAdapter.forPlatform('Windows');
  check(windows.collect(2).contains('AcceptPause'), 'Windows 服务能力字段缺失');
  final eventCommand = windows
      .servicesFor('Windows SCM')!
      .command("Example's service");
  check(
    eventCommand.contains('TimeGenerated >=') &&
        !eventCommand.contains('Message LIKE'),
    'Windows 事件查询缺少时间范围或存在插值风险',
  );
  if (!Platform.isWindows) {
    const fixture = r"""
uname() { printf 'Darwin\n'; }
sysctl() { printf '{ sec = 100, usec = 0 }\n'; }
launchctl() { printf 'PID\tStatus\tLabel\n42\t0\tcom.example.running\n-\t0\tcom.example.idle\n7\t0\tcom.example.second\n42\t0\tcom.example.shared\n'; }
ps() {
  [ "$1" = -ww ] && [ "$2" = -p ] && [ "$3" = '42,7' ] || return 64
  printf '42 tester 2.5 1024 01:23 1:02.30 /Applications/Example App/run --flag value\n7 root 0.0 0 01:00 0:00.00 /usr/libexec/example\n'
}
""";
    final result = await Process.run('sh', [
      '-c',
      '$fixture\n${mac.collect(2)}',
    ]);
    final snapshot = MachineMaintenanceSnapshot.parse(result.stdout as String);
    final rows = snapshot
        .text('service_processes')
        .split('\n')
        .map((s) => s.split('\t'))
        .toList();
    check(
      result.exitCode == 0 && snapshot.text('service_processes_status') == 'ok',
      '服务采样失败',
    );
    check(rows.length == 2 && rows.every((r) => r.length == 7), '批量采样字段缺失');
    check(
      rows.first[1] == 'tester' &&
          rows.first[2] == '2.5' &&
          rows.first[3] == '1024' &&
          rows.first[4] == '01:23' &&
          rows.first[5] == '1:02.30' &&
          rows.first[6] == '/Applications/Example App/run --flag value',
      '进程指标或带空格的启动命令丢失',
    );
    for (final scenario in ['failed', 'partial', 'idle', 'parser']) {
      final override = switch (scenario) {
        'failed' => 'ps() { return 1; }',
        'parser' =>
          r'''awk() { case "$1" in *'row=sprintf'*) return 2;; *) command awk "$@";; esac; }''',
        'idle' =>
          r'''launchctl() { printf 'PID\tStatus\tLabel\n-\t0\tcom.example.idle\n'; }; ps() { printf '错误：不应调用 ps' >&2; return 1; }''',
        _ =>
          '''ps() { command awk 'BEGIN {for(i=1;i<=3000;i++)print i,"tester 0.0 1024 01:00 0:00.00 /Applications/Example App/run --argument value"}'; }''',
      };
      final result = await Process.run('sh', [
        '-c',
        '$fixture\n$override\n${mac.collect(2)}',
      ]);
      final snapshot = MachineMaintenanceSnapshot.parse(
        result.stdout as String,
      );
      check(
        result.exitCode == 0 && snapshot.text('services').isNotEmpty,
        '指标失败不得丢失服务列表',
      );
      check(
        snapshot.text('service_processes_status') ==
            (scenario == 'idle'
                ? 'ok'
                : scenario == 'parser'
                ? 'failed'
                : scenario),
        '采集异常或空闲状态误报：$scenario',
      );
      if (scenario == 'partial') {
        check(
          snapshot.text('service_processes').length <= 160000 &&
              snapshot
                  .text('service_processes')
                  .split('\n')
                  .every((line) => line.split('\t').length == 7),
          '采样上限必须保留完整记录',
        );
      } else {
        check(snapshot.text('service_processes').isEmpty, '空闲或失败不能伪造指标');
      }
    }
    final failed = await Process.run('sh', [
      '-c',
      '$fixture\nlaunchctl() { return 1; }\n${mac.collect(2)}',
    ]);
    check(
      failed.exitCode != 0 &&
          !(failed.stdout as String).contains('__OH_OPS_end__'),
      '服务列表采集失败不能伪装成成功空列表',
    );
  }
  if (Platform.isMacOS) {
    for (final workers in [null, 4]) {
      final result = await Process.run('sh', [
        '-c',
        mac.collect(2, workers: workers, timeout: const Duration(seconds: 10)),
      ]).timeout(const Duration(seconds: 15));
      final snapshot = MachineMaintenanceSnapshot.parse(
        result.stdout as String,
      );
      final pids = snapshot
          .text('services')
          .split('\n')
          .map((line) => line.split('\t'))
          .where((row) => row.length >= 3 && (int.tryParse(row[1]) ?? 0) > 0)
          .map((row) => row[1])
          .toSet();
      final metrics = snapshot
          .text('service_processes')
          .split('\n')
          .map((line) => line.split('\t'))
          .where((row) => row.length == 7)
          .map((row) => row.first)
          .toSet();
      check(
        result.exitCode == 0 &&
            pids.isNotEmpty &&
            metrics.intersection(pids).length >= pids.length * .9,
        'macOS 实机运行中服务未获得进程指标',
      );
      check(snapshot.text('service_processes_status') == 'ok', 'macOS 实机采样不完整');
      stdout.writeln(
        'macOS 实机服务采样通过：${pids.length} 个运行 PID，${metrics.intersection(pids).length} 个匹配，并发设置 $workers。',
      );
    }
    final exists = await Process.run('launchctl', ['list', 'com.apple.bird']);
    if (exists.exitCode == 0) {
      final result = await Process.run('sh', [
        '-c',
        detail,
      ]).timeout(const Duration(seconds: 15));
      final sample = MachineMaintenanceSnapshot.parse(result.stdout as String);
      final readout = MachineMaintenanceReadout.parse(
        sample.text('status'),
        'status',
      );
      check(
        result.exitCode == 0 &&
            readout.rows.length > 10 &&
            sample.sections.containsKey('logs'),
        'macOS 实机详情不完整',
      );
      if (readout.rows.any(
        (row) => row[0] == 'pid' && (int.tryParse(row[1]) ?? 0) > 0,
      )) {
        check(
          sample.text('process').contains('User = ') &&
              sample.text('process').contains('CPUTime = ') &&
              sample.text('process').contains('Command = '),
          'macOS 实机服务详情缺少进程指标',
        );
      }
      stdout.writeln('macOS 实机服务详情与日志通道通过，${readout.rows.length} 个状态字段。');
    }
  }
  stdout.writeln('服务字段、日志边界、参数校验与多平台适配检查通过。');
}
