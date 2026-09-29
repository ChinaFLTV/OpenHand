import 'dart:io';

import 'package:openhand/features/machine_terminal/machine_maintenance.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

String sample({
  int uptime = 10,
  int user = 10,
  int idle = 90,
  int bytes = 100,
  String boot = '启动标识',
}) =>
    '''
终端回显
__OH_OPS_platform__
Linux
__OH_OPS_host__
测试机器
__OH_OPS_boot__
$boot
__OH_OPS_uptime__
$uptime 0
__OH_OPS_cpu__
cpu $user 0 0 $idle 0 0 0 0 100 0
cpu0 $user 0 0 $idle 0 0 0 0 100 0
__OH_OPS_network__
eth0: $bytes 0 0 0 0 0 0 0 $bytes 0 0 0 0 0 0 0
__OH_OPS_memory__
MemTotal: 1024 kB
MemAvailable: 512 kB
__OH_OPS_end__
提示符
''';

Future<void> main() async {
  final before = MachineMaintenanceSnapshot.parse(sample());
  final after = MachineMaintenanceSnapshot.parse(
    sample(uptime: 20, user: 50, idle: 150, bytes: 1100),
  );
  check(after.cpuUsage(before) == .4, 'CPU 差值或访客时间计算错误');
  check(after.rate(before, 'network', 'eth0', 0) == 100, '网络速率计算错误');
  check(after.memory['MemTotal'] == 1048576, '内存单位换算错误');
  check(before.cpuUsage(null) == null, '首次采样不能显示虚假使用率');
  check(before.rate(after, 'network', 'eth0', 0) == null, '计数器回退不能产生负速率');
  check(
    after.cpuUsage(MachineMaintenanceSnapshot.parse(sample(boot: '另一台机器'))) ==
        null,
    '不同机器不能混算指标',
  );
  for (final invalid in [
    sample().replaceAll('__OH_OPS_end__', ''),
    sample().replaceAll('Linux', 'Darwin'),
  ]) {
    var rejected = false;
    try {
      MachineMaintenanceSnapshot.parse(invalid);
    } catch (_) {
      rejected = true;
    }
    check(rejected, '截断结果或非 Linux 环境应拒绝解析');
  }
  final process = MachineMaintenanceProcess.parse(
    '42\t1\tS\t0\t2\t100\t4096\t20\t300\t进程 (测试)',
  )!;
  check(
    process.pid == 42 && process.started == 300 && process.residentPages == 100,
    '进程字段解析错误',
  );
  check(
    machineMaintenanceProcessCommand(process, signal: 'TERM').contains('300'),
    '进程操作缺少启动时间校验',
  );
  check(MachineMaintenanceProcess.parse('42\t乱码') == null, '无效进程行应被忽略');
  for (final manager in ['systemd', 'OpenRC', 'runit', 'SysV']) {
    final adapter = MachineMaintenanceServiceAdapter.detect(manager)!;
    final name = manager == 'runit'
        ? '/var/service/nginx'
        : manager == 'systemd'
        ? 'nginx.service'
        : 'nginx';
    check(adapter.command(name).contains('section end'), '服务详情缺少完整帧');
    for (final action in adapter.actions.values) {
      check(adapter.command(name, action).isNotEmpty, '服务操作未生成');
    }
    for (final malicious in [
      '-恶意参数',
      'nginx; touch /tmp/注入',
      '/etc/../恶意路径',
      'x\ny',
    ]) {
      check(!adapter.accepts(malicious), '服务策略允许命令注入');
    }
  }
  check(MachineMaintenanceServiceAdapter.detect('未知') == null, '未知服务管理器不应猜测');
  final commands = [
    machineMaintenanceOverviewCommand,
    machineMaintenanceProcessesCommand(),
    machineMaintenanceServicesCommand,
    machineMaintenanceDiagnosticsCommand,
    machineMaintenanceProcessCommand(process),
    machineMaintenanceBoundCommand(before, 'true'),
    for (final manager in ['systemd', 'OpenRC', 'runit', 'SysV'])
      MachineMaintenanceServiceAdapter.detect(manager)!.command(
        manager == 'runit'
            ? '/var/service/nginx'
            : manager == 'systemd'
            ? 'nginx.service'
            : 'nginx',
      ),
  ];
  for (final command in commands) {
    final shell = await Process.start('/bin/sh', ['-n']);
    shell.stdin.write(command);
    await shell.stdin.close();
    check(
      await shell.exitCode == 0,
      '采集脚本语法错误：${await shell.stderr.transform(const SystemEncoding().decoder).join()}',
    );
    check(command.length < 16384, '采集脚本超出传输限制');
  }
  final directory = await Directory.systemTemp.createTemp('openhand-运维检查-');
  try {
    final proc = Directory('${directory.path}/proc');
    await Directory('${proc.path}/42').create(recursive: true);
    final fields = List<String>.filled(50, '0');
    fields[0] = 'S';
    fields[1] = '1';
    fields[11] = '7';
    fields[12] = '3';
    fields[17] = '2';
    fields[19] = '300';
    fields[20] = '4096';
    fields[21] = '100';
    await File(
      '${proc.path}/42/stat',
    ).writeAsString('42 (进程 (带括号)) ${fields.join(' ')}\n');
    await File('${proc.path}/uptime').writeAsString('10 0\n');
    final bin = await Directory('${directory.path}/bin').create();
    final uname = await File(
      '${bin.path}/uname',
    ).writeAsString('#!/bin/sh\nprintf "Linux\\n"\n');
    await Process.run('chmod', ['+x', uname.path]);
    final output = await Process.run(
      '/bin/sh',
      [
        '-c',
        machineMaintenanceProcessesCommand().replaceAll(
          '/proc/',
          '${proc.path}/',
        ),
      ],
      environment: {'PATH': '${bin.path}:${Platform.environment['PATH']}'},
    );
    check(output.exitCode == 0, '进程采集执行失败');
    final actual = MachineMaintenanceSnapshot.parse(
      output.stdout as String,
    ).processes.single;
    check(
      actual.started == 300 &&
          actual.ticks == 10 &&
          actual.residentPages == 100,
      '真实 awk 执行字段错位',
    );
    check(actual.name == '进程 (带括号)', '带括号进程名截断');
  } finally {
    await directory.delete(recursive: true);
  }
  stdout.writeln('运维采样、速率换算、服务策略、注入防护与脚本检查通过。');
}
