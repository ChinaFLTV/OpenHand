import 'dart:io';

import 'package:openhand/features/machine_terminal/machine_maintenance.dart';
import 'package:openhand/features/machine_terminal/machine_maintenance_platform.dart';

void main() async {
  void check(bool value, String message) {
    if (!value) throw StateError(message);
  }

  MachineHealthReport parse(String key, String text, [String status = '0']) =>
      MachineHealthReport.parse(key, text, status, locale: 'zh');
  final system = parse(
    'system',
    'Darwin host 27.0.0 Darwin Kernel Version arm64\nProductName: macOS\nProductVersion: 27.0.1\nBuildVersion: 26A434',
  );
  check(system.data.rows.length == 7, '系统字段解析不完整');
  final sessions = parse(
    'sessions',
    'reader console Sep 29 09:41 08:30 608\nreader pts/0 2026-09-29 09:41 . 609 (10.0.0.1)',
  );
  check(
    sessions.data.rows.length == 2 &&
        sessions.data.rows.last.last == '(10.0.0.1)',
    '会话来源或日期解析失败',
  );
  final logins = parse(
    'logins',
    'reader ttys000 Tue Sep 29 19:22 still logged in\nreader pts/0 10.0.0.1 Tue Sep 29 19:22 - 20:22 (01:00)\nwtmp begins Tue Sep 29 10:26:38 CST 2026',
  );
  check(
    logins.data.rows.length == 2 &&
        logins.data.rows.first.last == 'still logged in',
    '登录记录解析错误',
  );
  final policy = parse(
    'password',
    '''<?xml version="1.0"?><plist><dict><key>policyContent</key><string>policyAttributePassword matches '.{4,}+'</string><key>policyIdentifier</key><string>example</string><key>policyContentDescription</key><dict><key>en</key><string>At least four characters</string><key>zh-Hans</key><string>至少四个字符</string></dict></dict></plist>''',
  );
  check(
    policy.data.rows.any((r) => r.last == '至少四个字符') &&
        policy.data.rows.any((r) => r.first == '最少字符数' && r.last == '4'),
    '密码策略未提取说明与约束',
  );
  final traditional = MachineHealthReport.parse(
    'password',
    '<plist><dict><key>policyContentDescription</key><dict><key>zh_CN</key><string>简体</string><key>zh_TW</key><string>繁體</string></dict></dict></plist>',
    '0',
    locale: 'zh-Hant',
  );
  check(traditional.data.rows.single.last == '繁體', '繁体策略说明未按语言选择');
  check(
    !policy.data.rows.any((r) => r.last.contains('<key>')),
    '密码策略泄漏 XML 标记',
  );
  check(parse('password', '<plist><dict>').issue == 'format', '损坏策略没有明确状态');
  for (final status in ['0', '1']) {
    check(
      parse(
            'sync',
            'You need administrator access to run this tool... exiting!',
            status,
          ).issue ==
          'permission',
      '权限错误被当成有效数据',
    );
  }
  check(
    parse('ssh', 'sshd: no hostkeys available -- exiting.', '1').issue ==
        'hostkeys',
    'SSH 主机密钥错误分类失败',
  );
  check(parse('temperature', '', '125').issue == 'unsupported', '平台不支持状态错误');
  check(parse('sync', '', '').issue == 'pending', '未采集状态错误');
  final thermal = parse(
    'temperature',
    'Note: No thermal warning level has been recorded\nNote: No performance warning level has been recorded\nNote: No CPU power status has been recorded',
  );
  check(
    thermal.data.rows.length == 3 &&
        !thermal.data.rows.any((r) => r.last.contains('°C')),
    '热状态不应伪造温度',
  );
  final battery = parse(
    'power',
    "Now drawing from 'AC Power'\n-InternalBattery-0 (id=123) 80%; AC attached; not charging present: true\nCycleCount: 42\nVoltage: 12000",
  );
  check(
    battery.data.rows.any((r) => r.last == '80%') &&
        battery.data.rows.any((r) => r.first == 'CycleCount'),
    '电源或循环数据丢失',
  );
  final ntp = parse(
    'ntp',
    'Reference ID : AABBCCDD\nStratum : 2\n^* 192.0.2.1 1 6 377 20 +12us[+14us] +/- 1ms',
  );
  check(
    ntp.data.rows.any((r) => r.first == 'reach' && r.last == '377'),
    'Chrony 来源缺少可达性',
  );
  check(
    parse(
          'clock',
          '2026-09-29 20:00:00 CST +0800\n2026-09-29 12:00:00 UTC',
        ).data.rows.length ==
        3,
    '本地与 UTC 时钟未解析',
  );
  final rotation = MachineLogMetadata.parse(
    'logrotate state -- version 2\n"/var/log/app.log" 2026-9-29-0:0:0',
    'rotation',
  );
  check(rotation.single.first == '/var/log/app.log', '轮转状态丢失日志路径');
  final config = MachineLogMetadata.parse(
    '/etc/logrotate.d/app\n/var/log/app.log {\nweekly\nrotate 7\npostrotate\n  systemctl reload app\nendscript\n}',
    'config',
  );
  check(
    config.length == 3 && !config.any((r) => r.join().contains('systemctl')),
    '轮转规则把脚本正文当作字段',
  );
  for (final platform in ['Linux', 'Darwin']) {
    final shell = await Process.start('/bin/sh', ['-n']);
    shell.stdin.write(
      MachineMaintenancePlatformAdapter.forPlatform(platform).collect(6),
    );
    await shell.stdin.close();
    check(await shell.exitCode == 0, '健康采集脚本语法错误：$platform');
  }
  if (Platform.isMacOS) {
    final result = await Process.run('/bin/sh', [
      '-c',
      MachineMaintenancePlatformAdapter.forPlatform('Darwin').collect(6),
    ]).timeout(const Duration(seconds: 30));
    check(result.exitCode == 0, '本机采集失败');
    final snapshot = MachineMaintenanceSnapshot.parse(result.stdout as String);
    for (final section in machineHealthSections) {
      final report = parse(
        section,
        snapshot.text('health_$section'),
        snapshot.text('health_${section}_status'),
      );
      check(
        report.data.rows.isNotEmpty || report.issue != null,
        '采集结果既无数据又无状态：$section',
      );
      stdout.writeln(
        '本机验证：$section，字段 ${report.data.rows.length}，状态 ${report.issue ?? "已解析"}，未解析 ${report.unparsed}',
      );
    }
  }
  stdout.writeln('健康与日志结构化检查通过。');
}
