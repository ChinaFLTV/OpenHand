import 'dart:io';

import 'package:openhand/features/machine_terminal/machine_maintenance_readout.dart';
import 'package:openhand/features/machine_terminal/machine_maintenance_time.dart';

void main() {
  void check(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  MachineMaintenanceReadout parse(String text, String section) =>
      MachineMaintenanceReadout.parse(text, section);
  const dockerError =
      'failed to connect to the docker API at unix:///tmp/docker.sock: connect: no such file or directory';
  check(
    parse(dockerError, 'containers').issue == 'connection',
    '容器连接失败应显示诊断状态',
  );
  check(parse(dockerError, 'containers').rows.isEmpty, '错误信息不能被拆成指标');
  check(parse(dockerError, 'logs').issue == null, '日志正文不能被错误状态替换');
  check(
    parse('permission denied: /tmp/socket', 'containers').issue == 'permission',
    '权限错误识别失败',
  );
  check(
    parse('context deadline exceeded', 'containers').issue == 'timeout',
    '超时识别失败',
  );
  check(
    parse('sh: docker: command not found', 'containers').issue == 'missing',
    '缺失工具识别失败',
  );
  check(
    parse('State: running\nErrors: 0', 'status').issue == null,
    '正常状态被误判为错误',
  );
  check(parse('docker: 27.0', 'status').issue == null, '正常工具版本不应误判为异常');
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
  check(dns.rows.last[1] == 'nameserver', 'macOS DNS 字段未规范化');
  final linuxDns = parse(
    '; 注释\nnameserver 1.1.1.1 # 首选\nnameserver fe80::1%eth0 ; 备用\noptions timeout:2 attempts:3',
    'dns',
  );
  check(
    linuxDns.rows.map((row) => row.last).join('|') ==
        '1.1.1.1|fe80::1%eth0|timeout:2 attempts:3',
    'Linux DNS 注释、区域标识或选项解析错误',
  );
  for (final label in [
    'DNS Servers',
    'DNS 服务器',
    'DNS 伺服器',
    'DNS-Server',
    'Serveurs DNS',
    'DNS サーバー',
  ]) {
    final windowsDns = parse(
      'Ethernet adapter Ethernet:\n'
          '   IPv4 Address . . . . : 192.168.1.2\n'
          '   $label . . . . : fe80::1%12\n'
          '                       1.1.1.1\n'
          '                       2001:db8::53\n'
          '   Default Gateway . . : 192.168.1.1\n'
          '                       fe80::2%12\n'
          'Wireless adapter Wi-Fi:\n'
          '   $label . . . . : 8.8.8.8',
      'dns',
    );
    final servers = windowsDns.rows
        .where((row) => row[1] == 'nameserver')
        .toList();
    check(
      servers.map((row) => row.last).join('|') ==
          'fe80::1%12|1.1.1.1|2001:db8::53|8.8.8.8',
      'Windows DNS 多行地址丢失或混入网关：$label',
    );
    check(
      servers.first.first == 'Ethernet adapter Ethernet' &&
          servers.last.first == 'Wireless adapter Wi-Fi',
      'Windows DNS 网卡分组错误',
    );
  }
  check(parse('', 'dns').rows.isEmpty, '空 DNS 应保留空状态');
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
    parse('Permission denied', 'status').issue == 'permission',
    '权限异常未进入诊断展示',
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
    service.rows[1].first == 'MachServices / com.example.worker / note' &&
        service.rows[1].last == 'a } b',
    '嵌套配置值或闭括号丢失',
  );
  check(
    service.rows[2].last.contains('--verbose') &&
        service.rows.last.first == 'PID',
    '配置数组未完整保留或吞掉后续属性',
  );
  final incomplete = parse('"Options" = {\n "nested" = 42;', 'status');
  check(
    incomplete.rows.single.first == 'Options / nested' &&
        incomplete.rows.single.last == '42',
    '截断配置必须保留已采集内容',
  );
  final report = parse(
    'Date/Time: 2026-09-30 08:00:00 +0800\nREGION TYPE SIZE\nMALLOC 400M\nTOTAL 500M',
    'memory',
  );
  check(report.rows.first.last == '2026-09-30 08:00:00 +0800', '报告日期被改写');
  check(
    report.groups['内存区域']?.rows.length == 2 &&
        report.groups['内存区域']?.rows.first[1] == '400M',
    '内存报告应按区域解析，避免整块命令输出',
  );
  const unixReport =
      'Active LOCAL (UNIX) domain sockets\nAddress Type Recv-Q Send-Q Inode Conn PID\n6d3890 stream 0 0 0 caaa89 68450 Cursor Helper';
  final unix = parse(unixReport, 'sockets');
  check(
    unix.groups['本地 UNIX 套接字']?.rows.single.last.contains('Cursor Helper') ==
        true,
    'UNIX 套接字字段未结构化或丢失进程名称',
  );
  final mixed = parse(
    'tcp4 0 0 127.0.0.1.80 *.* LISTEN\n$unixReport',
    'sockets',
  );
  check(
    mixed.rows.length == 1 && mixed.groups.length == 1 && !mixed.raw,
    'UNIX 报告不能导致网络连接丢失',
  );
  final routes = parse(
    'Routing tables\nInternet:\nDestination Gateway Flags Netif Expire\ndefault 192.168.1.1 UGScg en0\n10.0.0.2/31 2.0.6.125 UGSc utun4\nInternet6:\nDestination Gateway Flags Netif Expire\nfe80::%en0/64 link#4 UCI en0',
    'routes',
  );
  check(
    routes.rows.length == 3 &&
        routes.rows.first[2] == '192.168.1.1' &&
        routes.rows.first[3] == 'en0',
    'macOS 路由表头或网关列解析错误',
  );
  check(routes.rows.last.first == 'IPv6', 'IPv6 路由地址族丢失');
  final linuxRoutes = parse(
    'default via 10.0.0.1 dev eth0 proto dhcp metric 100\nlocal 10.0.0.2 dev eth0 table local src 10.0.0.2\nblackhole 10.1.0.0/16',
    'routes',
  );
  check(
    linuxRoutes.rows.length == 3 &&
        linuxRoutes.rows.first[5] == '100' &&
        linuxRoutes.rows[1][4] == 'local',
    'Linux 路由策略字段丢失',
  );
  check(
    parse(
          'Firewall is disabled. (State = 0)\npfctl: /dev/pf: Permission denied',
          'firewall',
        ).rows.length ==
        2,
    '混合防火墙报告应同时显示设置与权限状态',
  );
  final nextLine = parse('Options =\n{\n key = value;\n}\nPID = 42', 'status');
  check(
    nextLine.rows.length == 2 &&
        nextLine.rows.first.first == 'Options / key' &&
        nextLine.rows.first.last == 'value',
    '换行容器必须归属于原字段',
  );
  final limits = parse(
    'Limit               Soft Limit  Hard Limit  Units\nMax open files      1024        4096        files',
    'limits',
  );
  check(
    limits.fields && limits.rows.single.last.contains('Hard Limit: 4096'),
    '固定资源限制应完整显示为属性',
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

  final macAddress = parse('''
lo0: flags=8049<UP,LOOPBACK,RUNNING,MULTICAST> mtu 16384
  inet 127.0.0.1 netmask 0xff000000
  inet6 ::1 prefixlen 128
  inet6 fe80::1%lo0 prefixlen 64 scopeid 0x1
en0: flags=8863<UP,BROADCAST,RUNNING> mtu 1500
  ether 02:00:00:00:00:01
  media: autoselect (1000baseT <full-duplex>)
  status: active
''', 'addresses');
  check(
    macAddress.groups.length == 2 &&
        macAddress.groups['lo0']!.rows.any(
          (r) => r[0] == 'IPv6 地址' && r[1].contains('fe80::1%lo0'),
        ),
    'macOS 网卡多地址未完整分组',
  );
  final linuxAddress = parse('''
2: eth0@if3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP
  link/ether 02:00:00:00:00:02 brd ff:ff:ff:ff:ff:ff
  inet 10.0.0.2/24 brd 10.0.0.255 scope global eth0
    valid_lft forever preferred_lft forever
  RX: bytes packets errors dropped missed mcast
      1234 10 1 2 0 0
''', 'addresses');
  check(
    linuxAddress.groups.values.single.rows.any(
      (r) => r[0] == '接收 · 字节' && r[1] == '1234',
    ),
    'Linux 网卡计数器错位',
  );
  final windowsAddress = parse(
    'Ethernet adapter Ethernet:\n   Physical Address. . . . . . . . . : AA-BB-CC-DD-EE-FF\n   IPv4 Address. . . . . . . . . . . : 192.168.1.2\n   DNS Servers . . . . . . . . . . . : 192.168.1.1\n                                       2001:db8::1',
    'addresses',
  );
  check(
    windowsAddress.groups.values.single.rows.any(
      (r) => r[0] == 'DNS 服务器' && r[1].contains('2001:db8::1'),
    ),
    'Windows DNS 续行或适配器解析错误',
  );
  final neighbor = parse(
    '? (10.0.0.1) at aa:bb:cc:dd:ee:ff on en0 ifscope [ethernet]\nNeighbor Linklayer Address Netif Expire St Flgs Prbs\nfe80::1%lo0 (incomplete) lo0 permanent R\n2001:db8::2 dev eth0 lladdr aa:bb:cc:dd:ee:01 STALE',
    'neighbors',
  );
  check(
    neighbor.rows.length == 3 &&
        neighbor.rows[1][4] == '可达' &&
        neighbor.rows[2][3] == 'eth0',
    'ARP、NDP 和 Linux 邻居列错位',
  );
  final counters = parse(
    'TCP: inuse 2 orphan 0 tw 4 alloc 12 mem 0\nTcp: ActiveOpens PassiveOpens InSegs\nTcp: 10 20 300\nUdp:\n  12 datagrams received',
    'network_stats',
  );
  check(
    counters.groups['Tcp']!.rows.last.last == '300' &&
        counters.groups['TCP']!.rows.first.last == '2' &&
        counters.groups['Udp']!.rows.single.last == '12',
    '协议统计名称与数值配对错误',
  );
  final iptables = parse(
    '*filter\n:INPUT DROP [12:1024]\n[3:240] -A INPUT -s 10.0.0.0/8 -p tcp --dport 22 -j ACCEPT\nCOMMIT',
    'firewall_ipvfour',
  );
  final rule = iptables.groups['规则与计数器']!.rows.single;
  check(
    rule[2] == 'INPUT' &&
        rule[8] == '22' &&
        rule[11] == '3' &&
        rule[12] == '240',
    'iptables 规则或计数器解析错误',
  );
  final nft = parse(
    'table inet filter {\n chain input {\n type filter hook input priority 0; policy drop;\n ip saddr 10.0.0.0/8 tcp dport 22 counter packets 3 bytes 240 accept # handle 5\n }\n}',
    'firewall',
  );
  check(nft.groups['规则与计数器']!.rows.single[3] == 'accept', 'nft 表、链与动作未解析');
  final windowsFirewall = parse(
    'Domain Profile Settings:\nState                                 ON\nFirewall Policy                       BlockInbound,AllowOutbound',
    'firewall',
  );
  check(
    windowsFirewall.groups.values.single.rows.first.last == 'ON',
    'Windows 防火墙配置未结构化',
  );
  check(
    parse('pfctl: /dev/pf: Permission denied', 'firewall_rules').issue ==
        'permission',
    'PF 权限错误应独立显示',
  );
  final windowsRoutes = parse(
    'IPv4 Route Table\nNetwork Destination Netmask Gateway Interface Metric\n0.0.0.0 0.0.0.0 192.168.1.1 192.168.1.2 25\nIPv6 Route Table\n12 25 ::/0 fe80::1',
    'routes',
  );
  check(
    windowsRoutes.rows.length == 2 && windowsRoutes.rows.last[4] == '12',
    'Windows 双栈路由列错位',
  );
  final emptyConnections = parse(
    'Active Multipath Internet connections\nProto/ID Flags Local Address Foreign Address (state)\nActive Multipath Internet connections\nProto/ID Flags Local Address Foreign Address (state)',
    'sockets',
  );
  check(
    emptyConnections.rows.isEmpty &&
        emptyConnections.groups.isEmpty &&
        !emptyConnections.raw,
    '无连接表头不得作为命令正文显示',
  );
  final lsof = parse(
    'COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\nworker 42 root 5u IPv4 0x1 0t0 TCP 127.0.0.1:80 (LISTEN)',
    'socket_details',
  );
  check(
    lsof.rows.single[1] == '42' && lsof.rows.single.last.contains('LISTEN'),
    'macOS 连接进程解析错误',
  );
  final policy = parse(
    '100: from 10.0.0.0/8 lookup 200\n200: from all fwmark 0x1 iif eth0 lookup main',
    'policy_routes',
  );
  check(
    policy.rows.last[4] == '0x1' && policy.rows.last[5] == 'eth0',
    '策略路由匹配条件丢失',
  );
  final config = parse(
    'Global\n  DNS Servers: 10.0.0.1\nLink 2 (eth0)\n  Current DNS Server: 10.0.0.1',
    'dns_status',
  );
  check(config.groups.length == 2, 'DNS 状态范围未分组');
  final stats = parse(
    '{"Name":"worker","CPUPerc":"12.5%","MemUsage":"128MiB / 1GiB"}\n{"Name":"db","CPUPerc":"2.5%"}',
    'container_metrics',
  );
  check(
    stats.groups.length == 2 &&
        stats.groups.values.first.rows.any((r) => r[0] == 'MemUsage'),
    '容器逐行 JSON 采样未完整结构化',
  );
  final metadata = parse(
    '[{"Id":"abc","State":{"Status":"running","ExitCode":0},"Mounts":[{"Source":"/data","Destination":"/app"}]}]',
    'container_details',
  );
  check(
    metadata.groups.values.single.rows.any(
      (r) => r[0] == 'Mounts [1] / Source' && r[1] == '/data',
    ),
    '嵌套容器元数据或挂载点丢失',
  );
  final top = parse(
    'NAMESPACE POD NAME CPU(cores) MEMORY(bytes)\ndefault app worker 20m 128Mi',
    'container_metrics',
  );
  check(
    top.rows.single.length == 5 && top.rows.single[3] == '20m',
    'Kubernetes 容器资源采样错列',
  );
  final dcgm = parse('# Entity SMCLK MEMCLK\nGPU 0 N/A 1000', 'gpu_report');
  check(dcgm.rows.single.join('|') == 'GPU|0|N/A|1000', 'DCGM 实体编号与遥测列错位');
  final topology = parse(
    'GPU0 GPU1 CPU Affinity NUMA Affinity\nGPU0 X NV4 0-31 0\nGPU1 NV4 X 32-63 1',
    'gpu_report',
  );
  check(
    topology.rows.last.last == '1' && topology.headers.contains('CPU Affinity'),
    'GPU 拓扑解析错误',
  );
  final failedTime = MachineTimeReport.parse(
    '@@OH_TIME:SNTP 只读测量\nsntp_exchange {\n result: 6 (Timeout)\n offset: FFFFFFFF (-1999861048.013298512)\n delay: FFFFFFFF (-3999722096.026597023)\n addr: 17.253.114.35\n}\n@@OH_RESULT:69',
  );
  check(
    failedTime.data.rows.every(
      (r) => !const ['offset', 'delay', 't4', 'mean', 'error'].contains(r[0]),
    ),
    '失败 SNTP 调试值不得作为有效同步指标',
  );
  check(
    failedTime.partial &&
        failedTime.data.rows.any((r) => r[1].contains('请求超时')),
    'SNTP 失败原因未结构化',
  );
  final successTime = MachineTimeReport.parse(
    '@@OH_TIME:SNTP 只读测量\n+0.001 +/- 0.02 time.example 10.0.0.1\n@@OH_RESULT:0',
  );
  check(
    successTime.tables.values.single.rows.single[2] == '+0.001',
    '有效 SNTP 测量不应被隐藏',
  );
  check(
    parse(
          'Bad state: failed to connect to the docker API at unix:///tmp/docker.sock: no such file or directory',
          'container_metrics',
        ).issue ==
        'connection',
    '容器异常包装未被识别',
  );

  final tcpDetails = parse(
    'ESTAB 0 0 10.0.0.2:22 10.0.0.3:50000\n  cubic rto:200 rtt:1.25/0.5 cwnd:10',
    'socket_details',
  );
  check(
    tcpDetails.groups['连接']?.rows.single[1] == '10.0.0.2:22' &&
        tcpDetails.groups['10.0.0.2:22 → 10.0.0.3:50000']?.rows.any(
              (r) => r[0] == 'rtt' && r[1] == '1.25/0.5',
            ) ==
            true,
    'TCP 状态开头的连接及扩展指标未配对',
  );
  final netsh = parse(
    'Interface 12: Ethernet\nInternet Address Physical Address Type\n192.168.1.1 aa-bb-cc-dd-ee-ff Reachable\n2001:db8::1 aa-bb-cc-dd-ee-ff Stale',
    'neighbors',
  );
  check(
    netsh.rows.length == 2 && netsh.rows.every((r) => r[3] == '12'),
    'Windows 双栈邻居表接口丢失',
  );
  final windowsRules = parse(
    'Rule Name: Web\nEnabled: Yes\nLocalPort: 80\nRule Name: SSH\nEnabled: Yes\nLocalPort: 22',
    'firewall_rules',
  );
  check(
    windowsRules.groups.length == 2 &&
        windowsRules.groups['SSH']?.rows.last.last == '22',
    'Windows 防火墙规则未独立分组',
  );
  final setRule = parse(
    'table inet filter {\nchain input {\nip saddr { 10.0.0.0/8, 192.168.0.0/16 } tcp dport 22 accept\n}\n}',
    'firewall',
  );
  check(
    setRule.groups['规则与计数器']?.rows.single[5] ==
        '{ 10.0.0.0/8, 192.168.0.0/16 }',
    'nft 地址集合被截断',
  );
  final linuxInterfaces = parse(
    '2: eth0 inet 10.0.0.2/24 scope global eth0\neth0\naddress: aa:bb:cc:dd:ee:ff\nmtu: 1500',
    'interfaces',
  );
  check(linuxInterfaces.groups['eth0']?.rows.length == 4, '概览网卡地址与设备属性未合并');
  final gpuHeader = parse('# GPU SMCLK MEMCLK\n0 1500 N/A', 'gpu_report');
  check(
    gpuHeader.headers.length == 3 && gpuHeader.rows.single[1] == '1500',
    'DCGM 旧版表头前缀未移除',
  );
  final commandStart = parse(
    'ExecStart={ path=/bin/app ; argv[]=/bin/app --foo ; ignore_errors=no ; start_time=[Wed 2026-09-30 10:00] ; }',
    'status',
  );
  check(
    commandStart.rows.any(
      (r) => r[0] == 'ExecStart / argv[]' && r[1].contains('--foo'),
    ),
    'systemd 启动属性数组标识丢失',
  );
  final jsonLog = parse(
    '{"time":"2026-09-30","message":"permission denied"}',
    'logs',
  );
  check(
    jsonLog.groups.isEmpty && jsonLog.rows.single.last.contains('"message"'),
    'JSON 日志不能被元数据解析器改写',
  );
  final unknown = parse(
    'Unknown heading\nnot an operational field\nnot a supported table',
    'status',
  );
  check(unknown.issue == 'format' && unknown.rows.isEmpty, '未知输出不能伪装成描述指标');
  final oversized = parse(
    '{"items":[${List.generate(4200, (i) => '{"value":$i}').join(',')}]}',
    'container_details',
  );
  check(
    oversized.rows.any((r) => r[0] == '解析状态') &&
        oversized.groups.values.single.rows.length == 4096,
    '大报告解析应有明确且有界的限制',
  );
  final region = parse(
    '    VIRTUAL RESIDENT DIRTY SWAPPED\nREGION TYPE  SIZE  SIZE  SIZE  SIZE\n===========  ====  ====  ====  ====\nMALLOC  400M  20M  10M  0K\nTOTAL  500M  30M  15M  0K',
    'memory',
  );
  check(
    region.groups['内存区域']?.headers[2] == 'RESIDENT SIZE' &&
        region.groups['内存区域']?.rows.last[2] == '30M',
    '真实内存区域报告的多层表头错位',
  );
  final diagnosis = machineMaintenanceDiagnosticFields(
    '@@OH_TIME:服务状态\nActiveState=active\n@@OH_RESULT:0\n@@OH_TIME:SNTP 只读测量\nresult: 6 (Timeout)\n@@OH_RESULT:69',
  );
  check(diagnosis.any((r) => r[0] == '结果代码' && r[1] == '6'), '成功分区不得覆盖失败的诊断结果');

  check(
    machineMaintenanceDiagnosticFields(
      'You need administrator access to run this tool... exiting!',
    ).any((r) => r[0] == '原因' && r[1] == '读取权限不足'),
    '健康权限提示的原因不应误报为格式未识别',
  );

  stdout.writeln('运维结构化解析检查通过');
}
