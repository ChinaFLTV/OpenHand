import 'machine_maintenance.dart';

/// 指标表只保存已识别的数据；格式异常单独计数，不将命令正文冒充指标。
class MachineMaintenanceMetricTable {
  const MachineMaintenanceMetricTable(this.headers, this.rows);
  final List<String> headers;
  final List<List<String>> rows;
}

class MachineMaintenanceMetrics {
  factory MachineMaintenanceMetrics.parse(
    MachineMaintenanceSnapshot data,
    String section,
  ) {
    final platform = data.text('platform');
    final lines = data
        .text(section)
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final rows = <List<String>>[];
    var headers = <String>['名称', '数值', '单位'];
    var unparsed = 0;
    switch (section) {
      case 'disks':
        headers = [
          '设备',
          '累计读取次数',
          '累计写入次数',
          '累计读取字节',
          '累计写入字节',
          '累计读取耗时',
          '累计写入耗时',
        ];
        for (final entry in data.counters('disks').entries) {
          final v = entry.value;
          if (v.length < 8) {
            unparsed++;
            continue;
          }
          String count(int index, [int scale = 1]) =>
              v[index] < 0 ? '—' : '${v[index] * scale}';
          rows.add([
            platform == 'Windows' ? Uri.decodeComponent(entry.key) : entry.key,
            count(0),
            count(4),
            count(2, 512),
            count(6, 512),
            platform == 'Windows' || v[3] < 0 ? '—' : '${count(3)} ms',
            platform == 'Windows' || v[7] < 0 ? '—' : '${count(7)} ms',
          ]);
        }
      case 'memory':
      case 'memory_details':
      case 'vm':
      case 'kernel':
      case 'sensors':
        final field = RegExp(r'^([^:=]+?)\s*[:=]\s*(.*?)\s*$');
        final counter = RegExp(r'^([A-Za-z_][\w.()/-]*)\s+(-?\d+(?:\.\d+)?)$');
        for (final line in lines) {
          final m = field.firstMatch(line) ?? counter.firstMatch(line);
          if (m == null || m[2]!.isEmpty) {
            unparsed++;
            continue;
          }
          final name = m[1]!.trim();
          if (name == 'sysctl') {
            unparsed++;
            continue;
          }
          if (section == 'kernel' && name == '/proc/sys/fs/file-nr') {
            final values = m[2]!.trim().split(RegExp(r'\s+'));
            if (values.length == 3 &&
                values.every((v) => int.tryParse(v) != null)) {
              rows.addAll([
                ['已分配文件句柄', values[0], '次数'],
                ['空闲文件句柄', values[1], '次数'],
                ['文件上限', values[2], '次数'],
              ]);
            } else {
              unparsed++;
            }
            continue;
          }
          if (section == 'memory_details' &&
              (name.startsWith('Timestamp_') ||
                  name.startsWith('Frequency_') ||
                  const ['Caption', 'Description', 'Name'].contains(name))) {
            continue;
          }
          var value = m[2]!.trim();
          if (const ['memory', 'memory_details', 'vm'].contains(section) &&
              num.tryParse(value.split(RegExp(r'\s+')).first) == null) {
            unparsed++;
            continue;
          }
          var unit = '—';
          if (section == 'sensors') {
            final temp = double.tryParse(value.split(RegExp(r'\s+')).first);
            if (temp == null) {
              unparsed++;
              continue;
            }
            value = (temp / 1000).toStringAsFixed(1);
            unit = '°C';
          } else if (section == 'memory') {
            final parts = value.split(RegExp(r'\s+'));
            if (num.tryParse(parts.first) != null) {
              value = parts.first;
              unit = parts.length > 1
                  ? (parts[1] == 'kB' ? 'KiB' : parts[1])
                  : const [
                      'MemTotal',
                      'MemAvailable',
                      'SwapTotal',
                      'SwapFree',
                    ].contains(name)
                  ? 'B'
                  : '—';
            }
          } else if (section == 'vm') {
            unit = const ['pgpgin', 'pgpgout'].contains(name)
                ? 'KiB'
                : const ['pswpin', 'pswpout'].contains(name)
                ? '页数'
                : '—';
          } else if (section == 'memory_details') {
            unit = name.endsWith('KBytes')
                ? 'KiB'
                : name.endsWith('MBytes')
                ? 'MiB'
                : name.endsWith('Bytes')
                ? 'B'
                : '—';
          }
          rows.add([name, value, unit]);
        }
      case 'pressure':
        if (platform == 'Linux') {
          headers = ['资源', '范围', '10 秒平均', '60 秒平均', '300 秒平均', '累计等待时间'];
          var resource = '';
          for (final line in lines) {
            if (line.startsWith('/proc/pressure/')) {
              resource = line.split('/').last;
              continue;
            }
            final values = {
              for (final m in RegExp(
                r'(avg10|avg60|avg300|total)=([\d.]+)',
              ).allMatches(line))
                m[1]!: m[2]!,
            };
            if (resource.isEmpty ||
                values.length != 4 ||
                !RegExp(r'^(some|full)\s').hasMatch(line)) {
              unparsed++;
              continue;
            }
            rows.add([
              resource,
              line.split(' ').first,
              '${values['avg10']}%',
              '${values['avg60']}%',
              '${values['avg300']}%',
              '${values['total']} µs',
            ]);
          }
        } else if (platform == 'Darwin') {
          for (final line in lines) {
            final size = RegExp(
              r'^The system has (\d+) \((\d+) pages with a page size of (\d+)\)\.$',
            ).firstMatch(line);
            final free = RegExp(
              r'^System-wide memory free percentage:\s*([\d.]+)%$',
            ).firstMatch(line);
            if (size != null) {
              rows.addAll([
                ['MemTotal', size[1]!, 'B'],
                ['页数', size[2]!, '页数'],
                ['页大小', size[3]!, 'B'],
              ]);
            } else if (free != null) {
              rows.add(['空闲内存比例', free[1]!, '%']);
            } else {
              unparsed++;
            }
          }
        } else {
          return MachineMaintenanceMetrics.parse(data, 'pressure_fields');
        }
      case 'pressure_fields':
        for (final line in data.text('pressure').split('\n')) {
          final m = RegExp(r'^([A-Za-z]\w*):\s*(.+)$').firstMatch(line);
          if (m != null) {
            if (m[1]!.startsWith('Timestamp_') ||
                m[1]!.startsWith('Frequency_') ||
                const [
                  'Caption',
                  'Description',
                  'Name',
                  'SystemUpTime',
                ].contains(m[1])) {
              continue;
            }
            rows.add([m[1]!, m[2]!, '—']);
          } else if (line.trim().isNotEmpty) {
            unparsed++;
          }
        }
      case 'inodes':
        headers = ['设备', '已用 inode', '可用 inode', 'inode 使用率', '挂载点'];
        for (final line in lines) {
          if (line.startsWith('Filesystem ') || line.startsWith('设备 ')) {
            continue;
          }
          final m =
              (platform == 'Darwin'
                      ? RegExp(
                          r'^(.*?)\s+\d+\s+\d+\s+\d+\s+\S+\s+(\d+)\s+(\d+)\s+(\S+)\s+(.+)$',
                        )
                      : RegExp(r'^(.*?)\s+\d+\s+(\d+)\s+(\d+)\s+(\S+)\s+(.+)$'))
                  .firstMatch(line);
          if (m == null) {
            unparsed++;
            continue;
          }
          rows.add([for (var i = 1; i <= 5; i++) m[i]!]);
        }
      case 'blocks':
        headers = ['设备', '类型', '名称', '容量', '所属设备'];
        if (platform == 'Darwin') {
          var parent = '';
          for (final line in lines) {
            final device = RegExp(r'^(/dev/\S+)\s+\((.+)\):$').firstMatch(line);
            if (device != null) {
              parent = device[1]!;
              rows.add([parent, device[2]!, '—', '—', '—']);
              continue;
            }
            if (line.startsWith('#:')) continue;
            final store = RegExp(r'^Physical Store (\S+)$').firstMatch(line);
            if (store != null) {
              rows.add([store[1]!, 'Physical Store', '—', '—', parent]);
              continue;
            }
            final part = RegExp(
              r'^\d+:\s+(.+?)\s+([*+]?\d+(?:\.\d+)?\s+[KMGTPE]?B)\s+(\S+)$',
            ).firstMatch(line);
            if (part == null) {
              unparsed++;
              continue;
            }
            final description = part[1]!;
            final type = RegExp(
              r'^(APFS (?:Volume|Snapshot|Container Scheme)|\S+)(?:\s+(.*))?$',
            ).firstMatch(description)!;
            rows.add([
              part[3]!,
              type[1]!,
              type[2] ?? '—',
              part[2]!.replaceFirst(RegExp('^[*+]'), ''),
              parent,
            ]);
          }
        } else if (platform == 'Windows') {
          for (final line in lines) {
            final v = line.split('\t');
            if (v.length == 5) {
              rows.add(v);
            } else {
              unparsed++;
            }
          }
        } else {
          // lsblk 默认表头提供列位置；RAID 状态使用独立表，避免按空白猜测成员名称。
          headers = ['设备', '主次设备号', '可移除', '容量', '只读', '类型', '挂载点'];
          final raid = <List<String>>[];
          var inRaid = false;
          for (final line in lines) {
            if (line.startsWith('NAME ')) continue;
            if (line.startsWith('Personalities')) {
              inRaid = true;
              continue;
            }
            if (inRaid) {
              final m = RegExp(
                r'^(md\S+)\s*:\s*(\S+)\s+(\S+)\s*(.*)$',
              ).firstMatch(line);
              if (m != null) {
                raid.add([m[1]!, m[2]!, m[3]!, m[4]!]);
              } else if (line.startsWith('unused devices:')) {
                continue;
              } else if (raid.isNotEmpty) {
                raid.last[3] = '${raid.last[3]} · $line';
              } else {
                unparsed++;
              }
              continue;
            }
            final m = RegExp(
              r'^([^\s]+)\s+(\d+:\d+)\s+([01])\s+(\S+)\s+([01])\s+(\S+)(?:\s+(.*))?$',
            ).firstMatch(line);
            if (m == null) {
              unparsed++;
              continue;
            }
            rows.add([
              m[1]!.replaceFirst(RegExp('^[^A-Za-z0-9/]+'), ''),
              m[2]!,
              m[3]!,
              m[4]!,
              m[5]!,
              m[6]!,
              m[7] ?? '—',
            ]);
          }
          return MachineMaintenanceMetrics([
            MachineMaintenanceMetricTable(headers, rows),
            if (raid.isNotEmpty)
              MachineMaintenanceMetricTable([
                '设备',
                '状态',
                '类型',
                '成员与同步状态',
              ], raid),
          ], unparsed: unparsed);
        }
      case 'interfaces':
        headers = ['网卡', '状态', 'MAC', 'MTU', '地址', '链路'];
        if (platform == 'Windows') {
          for (final line in lines) {
            final v = line.split('\t');
            if (v.length == 6) {
              rows.add(v);
            } else {
              unparsed++;
            }
          }
        } else {
          List<String>? current;
          for (final line in lines) {
            final macHeader = RegExp(
              r'^(\S+): flags=([^ ]+).*\bmtu (\d+)',
            ).firstMatch(line);
            if (platform == 'Darwin' && macHeader != null) {
              current = [
                macHeader[1]!,
                macHeader[2]!,
                '—',
                macHeader[3]!,
                '—',
                '—',
              ];
              rows.add(current);
              continue;
            }
            if (platform == 'Linux' && !line.contains(':')) {
              current = [line, '—', '—', '—', '—', '—'];
              rows.add(current);
              continue;
            }
            if (current == null) {
              unparsed++;
              continue;
            }
            if (platform == 'Linux') {
              final m = RegExp(
                r'^(address|operstate|mtu|speed|duplex):\s*(.*)$',
              ).firstMatch(line);
              if (m == null) {
                unparsed++;
                continue;
              }
              switch (m[1]) {
                case 'address':
                  current[2] = m[2]!;
                case 'operstate':
                  current[1] = m[2]!;
                case 'mtu':
                  current[3] = m[2]!;
                case 'speed':
                  current[5] = m[2] == '-1' || m[2]!.isEmpty
                      ? '—'
                      : '${m[2]} Mb/s';
                case 'duplex':
                  current[5] = '${current[5]} ${m[2]}';
              }
            } else {
              final m = RegExp(
                r'^(ether|inet6?|status:|media:)\s+(.+)$',
              ).firstMatch(line);
              if (m != null) {
                final value = m[2]!;
                switch (m[1]) {
                  case 'ether':
                    current[2] = value;
                  case 'status:':
                    current[1] = value;
                  case 'media:':
                    current[5] = value;
                  default:
                    current[4] = current[4] == '—'
                        ? value
                        : '${current[4]} · $value';
                }
              }
              // 网桥与驱动选项属于附加属性，不将其误判为网卡。
            }
          }
        }
      case 'cgroup_limits':
        headers = ['名称', '数值', '单位', '路径'];
        for (final line in lines) {
          final m = RegExp(r'^(/[^:]+):\s*(.+)$').firstMatch(line);
          final membership = RegExp(r'^(\d+):([^:]*):(.*)$').firstMatch(line);
          if (m != null) {
            final path = m[1]!;
            final value = m[2]!;
            final name = path.split('/').last;
            if (name == 'cpu.max') {
              final values = value.split(RegExp(r'\s+'));
              if (values.length == 2) {
                rows.addAll([
                  [
                    'CPU 配额',
                    values[0] == 'max' ? '不设上限' : values[0],
                    'µs',
                    path,
                  ],
                  ['CPU 配额周期', values[1], 'µs', path],
                ]);
              } else {
                unparsed++;
              }
            } else {
              rows.add([
                switch (name) {
                  'memory.max' || 'memory.limit_in_bytes' => '内存上限',
                  'memory.current' => '当前内存',
                  'cpu.cfs_quota_us' => 'CPU 配额',
                  'cpu.cfs_period_us' => 'CPU 配额周期',
                  _ => name,
                },
                value == 'max' || (name == 'cpu.cfs_quota_us' && value == '-1')
                    ? '不设上限'
                    : value,
                name.startsWith('memory.')
                    ? 'B'
                    : name.endsWith('_us')
                    ? 'µs'
                    : '—',
                path,
              ]);
            }
          } else if (membership != null) {
            rows.add([
              'cgroup ${membership[1]}:${membership[2]}',
              '—',
              '—',
              membership[3]!,
            ]);
          } else {
            unparsed++;
          }
        }
      case 'capabilities':
        headers = ['类型', '名称'];
        for (final line in lines) {
          final m = RegExp(
            r'^(内核接口|可用工具|macOS 原生命令)[：:]\s*(.*)$',
          ).firstMatch(line);
          if (m != null) {
            for (final item
                in m[2]!
                    .split('；')
                    .first
                    .split(RegExp(r'[、\s]+'))
                    .where((v) => v.isNotEmpty)) {
              rows.add([m[1]!, item]);
            }
          } else if (line.startsWith('Windows WMI / WSH')) {
            rows.addAll([
              ['可用工具', 'WMI'],
              ['可用工具', 'WSH JScript'],
            ]);
          } else {
            unparsed++;
          }
        }
      default:
        unparsed = lines.length;
    }
    return MachineMaintenanceMetrics([
      MachineMaintenanceMetricTable(headers, rows),
    ], unparsed: unparsed);
  }
  const MachineMaintenanceMetrics(this.tables, {this.unparsed = 0});
  final List<MachineMaintenanceMetricTable> tables;
  final int unparsed;
}
