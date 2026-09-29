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
  check(ntp.tables['Chrony 时钟源']!.rows.single[5] == '377', 'Chrony 来源缺少可达性');
  check(
    parse(
          'clock',
          '2026-09-29 20:00:00 CST +0800\n2026-09-29 12:00:00 UTC',
        ).data.rows.length ==
        3,
    '本地与 UTC 时钟未解析',
  );
  final detailed = parse('ntp', """
@@OH_TIME:Chrony 跟踪
Last offset : -0.000006747 seconds
RMS offset : 0.000035822 seconds
Leap status : Normal
@@OH_RESULT:0
@@OH_TIME:Chrony 时钟源
^* 2001:db8::1 2 6 377 20 +12us[+14us] +/- 1ms
^- 192.0.2.2 2 6 377 21 -2ms[-3ms] +/- 4ms
^x 192.0.2.3 2 6 377 23 +1s[+1s] +/- 2ms
^? 192.0.2.4 0 6 0 - +0ns[+0ns] +/- 0ns
@@OH_RESULT:0
@@OH_TIME:Chrony 源统计
2001:db8::1 8 5 123 0.2 0.3 -12us 2us
@@OH_RESULT:0
@@OH_TIME:Chrony 选择详情
N 192.0.2.3 N N---- N---- 4 1.0 -61ms +62ms N
@@OH_RESULT:0
@@OH_TIME:额外查询
Not authorised
@@OH_RESULT:1
""");
  check(
    detailed.issue == 'partial' && detailed.tables.length == 3,
    '局部失败不能遮掉成功采集的源表',
  );
  check(
    detailed.tables['Chrony 时钟源']!.rows.first.first == '2001:db8::1',
    'IPv6 地址被冒号拆散',
  );
  check(
    detailed.tables['Chrony 时钟源']!.rows[1][1].contains('未参与'),
    'Chrony 未合并源不能误标为备份',
  );
  check(
    detailed.tables['Chrony 选择详情']!.rows.single[1].contains('noselect'),
    '缺少排除原因',
  );
  check(
    detailed.data.rows.any((r) => r.last == '-0.000006747 seconds'),
    '同步偏移的符号或单位丢失',
  );
  for (final table in detailed.tables.values) {
    check(
      table.rows.every((row) => row.length == table.headers.length),
      '时钟源表头与行错位',
    );
  }
  final peer = parse('ntp', """
@@OH_TIME:NTP 时钟源
*2001:db8:100:100:100:100:100:1
 .GPS. 1 u 4 64 377 0.25 -0.12 0.03
#192.0.2.2 .GPS. 1 u 8 64 377 1.5 +0.2 0.1
 192.0.2.3 .INIT. 16 u - 64 0 0.0 0.0 0.0
@@OH_RESULT:0
@@OH_TIME:NTP 系统变量
offset=-0.12, sys_jitter=0.03, frequency=1.2
@@OH_RESULT:0
""");
  check(peer.tables['NTP 时钟源']!.rows.length == 3, 'NTP 未选中源或长地址被遗漏');
  check(peer.tables['NTP 时钟源']!.rows[1][1].contains('备份'), 'NTP 备份标记未解析');
  check(
    peer.data.rows.any((r) => r.first == 'sys_jitter' && r.last == '0.03'),
    'NTP 系统变量未拆分',
  );
  final mac = parse(
    'ntp',
    '@@OH_TIME:SNTP 只读测量\n+0.05 +/- 0.2 time.apple.com 2001:db8::1\n@@OH_RESULT:0\n实时同步状态: 原生服务不提供选中源',
  );
  check(
    mac.tables.values.single.rows.single[2] == '+0.05' &&
        mac.issue == 'partial',
    'SNTP 测量不得冒充原生同步状态',
  );
  final win = parse(
    'ntp',
    '@@OH_TIME:Windows peers\nPeer: time.example.com,0x9\nState: Active\nStratum: 2\n@@OH_TIME:Windows status\nSource: time.example.com\nPhase Offset: 0.001s',
  );
  check(
    win.tables['Windows 时钟源']!.rows.single.first == 'time.example.com,0x9',
    'Windows 对等源未独立展示',
  );
  check(win.data.rows.any((r) => r.first == 'Phase Offset'), 'Windows 详细偏移未保留');
  check(
    parse(
          'ntp',
          'configured: /etc/ntp.conf\nNetwork Time Server: time.apple.com',
        ).issue ==
        'partial',
    '仅配置不能被视为已同步',
  );
  check(
    parse('ntp', 'Leap status : Not synchronised').issue == 'unsynchronized',
    '未同步不能显示为健康',
  );
  final tools = await Directory.systemTemp.createTemp('openhand-time-check-');
  try {
    final chronyc = File('${tools.path}/chronyc');
    await chronyc.writeAsString(r'''#!/bin/sh
for arg in "$@"; do command=$arg; done
case "$command" in
  tracking) printf '506 Cannot talk to daemon\n'; exit 1 ;;
  sources) printf '^* 192.0.2.1 2 6 377 20 +12us[+14us] +/- 1ms\n' ;;
  sourcestats) printf '192.0.2.1 8 5 123 0.2 0.3 -12us 2us\n' ;;
  selectdata) printf 'N 192.0.2.2 N N---- N---- 4 1.0 -61ms +62ms N\n' ;;
esac
''');
    await Process.run('chmod', ['+x', chronyc.path]);
    final sample = await Process.run(
      '/bin/sh',
      [
        '-c',
        'section() { printf "\\n__OH_OPS_%s__\\n" "\$1"; }\n$machineHealthPosixPrelude\nsection platform\nprintf Linux\nhealth ntp time_sources\nsection end',
      ],
      environment: {'PATH': '${tools.path}:/usr/bin:/bin'},
    ).timeout(const Duration(seconds: 15));
    final result = MachineMaintenanceSnapshot.parse(sample.stdout as String);
    final report = parse(
      'ntp',
      result.text('health_ntp'),
      result.text('health_ntp_status'),
    );
    check(
      report.tables.length >= 3 && report.issue == 'partial',
      '采集子命令失败导致后续源数据丢失',
    );
  } finally {
    await tools.delete(recursive: true);
  }
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
