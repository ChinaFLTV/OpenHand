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
  if (Platform.isMacOS) {
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
      stdout.writeln('macOS 实机服务详情与日志通道通过，${readout.rows.length} 个状态字段。');
    }
  }
  stdout.writeln('服务字段、日志边界、参数校验与多平台适配检查通过。');
}
