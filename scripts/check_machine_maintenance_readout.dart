import 'dart:io';

import 'package:openhand/features/machine_terminal/machine_maintenance_readout.dart';

void main() {
  void check(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  MachineMaintenanceReadout parse(String text, String section) =>
      MachineMaintenanceReadout.parse(text, section);
  final startup = parse(
    '/Library/LaunchAgents:\ncom.example.agent.plist\n/Library/LaunchDaemons:\ncom.example.daemon.plist\n/Users/test/Library/LaunchAgents:\nMy Agent.plist',
    'startup',
  );
  check(!startup.fields && startup.rows.length == 3, '启动目录被误当成描述条目');
  check(
    startup.rows.last.join('|') ==
        'My Agent.plist|用户代理|/Users/test/Library/LaunchAgents/My Agent.plist',
    '含空格启动项路径或类型丢失',
  );
  final tagged = parse(
    '__OH_STARTUP__\t/Library/LaunchDaemons/com.example.daemon.plist',
    'startup',
  );
  check(tagged.rows.single[1] == '系统守护进程', '带标记启动项解析失败');
  final systemd = parse(
    'UNIT FILE STATE PRESET\nnginx.service enabled disabled\nworker.service static -',
    'startup',
  );
  check(
    systemd.rows.length == 2 && systemd.rows.first[1] == 'enabled',
    'systemd 启动状态被当作表头丢失',
  );
  final windowsStartup = parse('Spooler\tAuto\nExample\tManual', 'startup');
  check(
    windowsStartup.rows.length == 2 &&
        windowsStartup.rows.first.first == 'Spooler',
    'Windows 启动项丢失首行',
  );
  final users = parse(
    'root pts/7 Sep 29 16:27 (host.example)\nadmin console Sep 28 09:00',
    'users',
  );
  check(
    users.rows.first.join('|') == 'root|pts/7|Sep 29 16:27|host.example',
    '登录会话字段错位',
  );
  check(users.rows.last.last == '—', '本地会话应允许来源为空');
  final dns = parse(
    '# comment\nnameserver 2001:db8::1\nsearch example.com\nresolver #2\n nameserver[0] : 10.0.0.1',
    'dns',
  );
  check(
    dns.rows.length == 3 && dns.rows.first.last == '2001:db8::1',
    'DNS 地址或注释解析错误',
  );
  check(dns.rows.last.first == 'resolver #2', '解析器分组丢失');
  final status = parse(
    'Name:\tworker\nUid:\t501 501 501 501\nRestart=no\nExecStart=/bin/app --value=a=b\nName: second',
    'status',
  );
  check(status.fields && status.rows.length == 5, '状态属性重复字段丢失');
  check(status.rows[3].last == '/bin/app --value=a=b', '字段值被截断');
  final windows = parse(
    'LogonId=42\nLogonType=2\nStartTime=2026-09-29T09:00:00',
    'users',
  );
  check(windows.fields && windows.rows.length == 3, 'Windows 会话解析错误');
  final paths = parse(
    'total 0\nlrwxrwxrwx 1 user group 0 Sep 29 16:41 /proc/42/cwd -> /home/my project',
    'paths',
  );
  check(paths.rows.single[1] == '/home/my project', '符号链接路径空格丢失');
  final container = parse(
    'CONTAINER ID  IMAGE         COMMAND          STATUS       PORTS       NAMES\nabc           app:latest    "sh -c hello"    Up 2 hours               worker',
    'containers',
  );
  check(
    container.rows.single.length == 6 &&
        container.rows.single[2] == '"sh -c hello"',
    '容器命令列解析错误',
  );
  check(
    container.rows.single[4].isEmpty && container.rows.single.last == 'worker',
    '容器空端口列错位',
  );
  check(parse('-- No entries --', 'logs').rows.isEmpty, '空日志未转换为空状态');
  final logs = parse(
    '2026-09-29T16:27:00+0800 host app[42]: ready\n continuation',
    'logs',
  );
  check(
    logs.rows.first.first.contains('+0800') &&
        logs.rows.last.last == 'continuation',
    '日志时间或续行丢失',
  );
  check(
    parse('0::/system.slice/app:worker', 'cgroup').rows.single.last ==
        '/system.slice/app:worker',
    '控制组路径截断',
  );
  check(
    parse('*/5 * * * * /bin/app --name "my app"', 'cron').rows.single.last ==
        '/bin/app --name "my app"',
    '计划任务命令截断',
  );
  final mac = parse(
    'PID PPID USER STAT STARTED COMMAND\n42 1 user S Tue Sep 29 16:00:00 2026 /Applications/My App\n43',
    'status',
  );
  check(mac.rows.first.last == '/Applications/My App', 'macOS 启动时间列错位');
  check(mac.rows.last.length == mac.headers.length, '缺失列应安全保留');
  check(
    parse('Permission denied', 'status').rows.single.last ==
        'Permission denied',
    '异常信息丢失',
  );
  final process = parse(
    'PID PPID USER STAT STARTED COMMAND\n42 1 user S Tue Sep 29 16:00:00 2026 /Applications/My App',
    'status',
  );
  check(process.fields && process.rows.length == 6, '单进程状态应转换为完整属性');
  check(process.rows.last.last == '/Applications/My App', '进程命令被截断');
  final service = parse('''{
  "Label" = "com.example.worker";
  "MachServices" = {
    "com.example.worker" = { "note" = "a } b"; };
  };
  "ProgramArguments" = (
    "/Applications/My App",
    "--verbose"
  );
  "PID" = 42;
}''', 'status');
  check(service.rows.length == 4, '嵌套服务配置不应拆为括号或描述行');
  check(
    service.rows[1].last.contains('"a } b"') &&
        service.rows[1].last.endsWith('};'),
    '嵌套配置值或闭括号丢失',
  );
  check(
    service.rows[2].last.contains('--verbose') &&
        service.rows.last.first == 'PID',
    '配置数组未完整保留或吞掉后续属性',
  );
  final incomplete = parse('"Options" = {\n "nested" = 42;', 'status');
  check(
    incomplete.rows.single.last.contains('"nested" = 42;'),
    '截断配置必须保留已采集内容',
  );
  final report = parse(
    'Date/Time: 2026-09-30 08:00:00 +0800\nREGION TYPE SIZE\nMALLOC 400M\nTOTAL 500M',
    'memory',
  );
  check(report.rows.first.last == '2026-09-30 08:00:00 +0800', '报告日期被改写');
  check(
    report.rows.last.last.contains('MALLOC 400M\nTOTAL 500M'),
    '非属性报告应完整成块保留',
  );
  const unixReport =
      'Active LOCAL (UNIX) domain sockets\nAddress Type Recv-Q Send-Q Inode Conn PID\n6d3890 stream 0 0 0 caaa89 68450 Cursor Helper';
  final unix = parse(unixReport, 'sockets');
  check(
    unix.fields && unix.rows.single.last == unixReport,
    'UNIX 套接字报告不得拆成错误属性或丢失记录',
  );
  check(parse('', 'status').rows.isEmpty, '空输出解析错误');
  for (final sample in [
    'TCP 127.0.0.1:80 0.0.0.0:0 LISTENING 42',
    'tcp4 0 0 127.0.0.1.80 *.* LISTEN',
    'tcp LISTEN 0 128 [::]:80 [::]:*',
  ]) {
    final result = parse(sample, 'sockets');
    check(!result.fields && result.rows.single.length == 7, '跨平台连接解析错误');
  }
  check(parse("'", 'command').rows.single.last == "'", '不完整引号不得丢失或抛出异常');
  check(
    parse(
          '"/Applications/My App" --config "my config"',
          'command',
        ).rows.length ==
        3,
    '启动参数引号解析错误',
  );
  stdout.writeln('运维结构化解析检查通过');
}
