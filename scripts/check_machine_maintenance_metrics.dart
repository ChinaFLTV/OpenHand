import 'dart:convert';
import 'dart:io';

import 'package:openhand/features/machine_terminal/machine_maintenance.dart';
import 'package:openhand/features/machine_terminal/machine_maintenance_metrics.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

void main() {
  MachineMaintenanceMetrics parse(String platform, String key, String value) =>
      MachineMaintenanceMetrics.parse(
        MachineMaintenanceSnapshot({'platform': platform, key: value}),
        key,
      );
  final disks = parse(
    'Linux',
    'disks',
    'sda 20 0 4 8 30 0 6 9 0 10 11',
  ).tables.single.rows.single;
  check(
    disks[1] == '20' &&
        disks[2] == '30' &&
        disks[3] == '2048' &&
        disks[4] == '3072',
    '磁盘计数或扇区换算错误',
  );
  final win = parse(
    'Windows',
    'disks',
    'C%3A%20data -1 0 2 0 4 0 8 0',
  ).tables.single.rows.single;
  check(win[0] == 'C: data' && win[1] == '—' && win[5] == '—', '缺失磁盘计数不应显示零');
  final memory = parse(
    'Linux',
    'memory',
    'MemTotal: 1234 kB\nHugePages_Total: 0\n不可用',
  ).tables.single.rows;
  check(memory[0][2] == 'KiB' && memory[1][1] == '0', '内存单位或合法零值错误');
  final pages = parse(
    'Darwin',
    'vm',
    'pgpgin 8192\npswpout 4',
  ).tables.single.rows;
  check(pages[0][2] == 'KiB' && pages[1][2] == '页数', '分页流量与页数混淆');
  final vm = parse(
    'Linux',
    'vm',
    'nr_free_pages 42\npgfault 8',
  ).tables.single.rows;
  check(vm[0][2] == '页数' && vm[1][2] == '—', '内存页计数与事件计数单位混淆');
  final pressure = parse(
    'Linux',
    'pressure',
    '/proc/pressure/cpu\nsome avg10=1.2 avg60=0.4 avg300=0.1 total=12345\n损坏行',
  );
  check(
    pressure.tables.single.rows.single[2] == '1.2%' && pressure.unparsed == 1,
    '压力采样未隔离损坏行',
  );
  check(
    parse(
          'Darwin',
          'pressure',
          'The system has 32768 (2 pages with a page size of 16384).\nSystem-wide memory free percentage: 58%',
        ).tables.single.rows.length ==
        4,
    'macOS 内存压力解析失败',
  );
  final blocks = parse('Darwin', 'blocks', '''/dev/disk0 (internal, physical):
   #: TYPE NAME SIZE IDENTIFIER
   0: GUID_partition_scheme *500.3 GB disk0
   1: Apple_APFS Container disk3 494.4 GB disk0s1
/dev/disk3 (synthesized):
   0: APFS Container Scheme - +494.4 GB disk3
      Physical Store disk0s1
   1: APFS Volume Macintosh HD 13.7 GB disk3s1
''');
  check(
    blocks.unparsed == 0 &&
        blocks.tables.single.rows.last[2] == 'Macintosh HD' &&
        blocks.tables.single.rows.last[4] == '/dev/disk3',
    'macOS 分区名称或父设备丢失',
  );
  final linuxBlocks = parse(
    'Linux',
    'blocks',
    '''NAME MAJ:MIN RM SIZE RO TYPE MOUNTPOINTS
sda 8:0 0 500G 0 disk
└─sda1 8:1 0 500G 0 part /data folder
Personalities : [raid1]
md0 : active raid1 sda1[0] sdb1[1]
  100 blocks [2/2] [UU]
unused devices: <none>
''',
  );
  check(
    linuxBlocks.unparsed == 0 &&
        linuxBlocks.tables.length == 2 &&
        linuxBlocks.tables.first.rows.last.last == '/data folder',
    'Linux 块设备与 RAID 未正确分组',
  );
  final net = parse(
    'Darwin',
    'interfaces',
    '''en0: flags=8863<UP,BROADCAST,RUNNING> mtu 1500
 ether aa:bb:cc:dd:ee:ff
 inet6 fe80::1%en0 prefixlen 64 scopeid 0xe
 inet 10.0.0.2 netmask 0xffffff00 broadcast 10.0.0.255
 status: active
''',
  ).tables.single.rows.single;
  check(
    net[0] == 'en0' && net[1] == 'active' && net[4].contains('fe80::1%en0'),
    '网卡地址或状态解析失败',
  );
  check(
    parse(
          'Linux',
          'inodes',
          'Filesystem Inodes IUsed IFree IUse% Mounted on\n/dev/sda 100 30 70 30% /data folder',
        ).tables.single.rows.single.last ==
        '/data folder',
    'inode 挂载路径空格丢失',
  );
  check(
    parse('Darwin', 'blocks', 'diskutil: permission denied').unparsed == 1,
    '权限错误被当成指标',
  );
  final limits = parse(
    'Linux',
    'cgroup_limits',
    '/sys/fs/cgroup/cpu.max: max 100000\n/sys/fs/cgroup/memory.current: 2048',
  );
  check(
    limits.tables.single.rows.length == 3 &&
        limits.tables.single.rows.first[1] == '不设上限' &&
        limits.tables.single.rows.last[2] == 'B',
    '控制组配额与内存单位错误',
  );
  check(
    parse('Linux', 'memory', 'cat: permission denied').unparsed == 1,
    '内存读取错误被误当数值',
  );
  check(
    parse('Linux', 'inodes', 'df: permission denied').unparsed == 1,
    'inode 读取错误未报告',
  );
  final sample = File('/tmp/maintenance-real-data.json');
  if (sample.existsSync()) {
    final values = jsonDecode(sample.readAsStringSync()) as Map;
    final data = MachineMaintenanceSnapshot.parse(values['overview'] as String);
    for (final key in [
      'disks',
      'memory',
      'vm',
      'pressure',
      'blocks',
      'interfaces',
      'inodes',
      'capabilities',
    ]) {
      final result = MachineMaintenanceMetrics.parse(data, key);
      check(
        result.tables.any((table) => table.rows.isNotEmpty),
        '实机样本未解析出指标：$key',
      );
      check(result.unparsed == 0, '实机样本存在未识别内容：$key（${result.unparsed} 行）');
    }
  }
  stdout.writeln('三平台指标、单位、设备层次、IPv6 与异常数据解析检查通过。');
}
