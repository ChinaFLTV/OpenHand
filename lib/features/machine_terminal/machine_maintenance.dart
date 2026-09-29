import '../../shared/util/platform_shell.dart';
import 'machine_maintenance_gpu.dart';
import 'machine_maintenance_health.dart';
import 'machine_maintenance_logs.dart';

export 'machine_maintenance_gpu.dart';
export 'machine_maintenance_health.dart';
export 'machine_maintenance_logs.dart';

const machineMaintenanceProcessLimit = 512;
const machineMaintenanceInterval = Duration(seconds: 10);
const _sectionPrefix = '__OH_OPS_';

/// 协议只接受完整采样，避免把超时、终端回显或截断数据当成有效指标。
class MachineMaintenanceSnapshot {
  MachineMaintenanceSnapshot(this.sections);

  factory MachineMaintenanceSnapshot.parse(
    String output, {
    MachineMaintenanceSnapshot? previous,
  }) {
    final sections = <String, String>{};
    String? section;
    final buffer = StringBuffer();
    var complete = false;
    for (final line in output.replaceAll('\r', '').split('\n')) {
      if (RegExp(r'^__OH_OPS_[a-z_]+__$').hasMatch(line)) {
        if (section != null) sections[section] = buffer.toString().trim();
        buffer.clear();
        section = line.substring(_sectionPrefix.length, line.length - 2);
        if (section == 'end') complete = true;
      } else if (section != null) {
        buffer.writeln(line);
      }
    }
    if (!complete) throw const FormatException('采样未完成，请重试。');
    if (sections['encoding'] == 'uri') {
      for (final key in sections.keys.toList()) {
        if (key != 'encoding') {
          sections[key] = Uri.decodeComponent(sections[key]!);
        }
      }
    }
    if (!const ['Linux', 'Darwin', 'Windows'].contains(sections['platform'])) {
      throw UnsupportedError('目标系统不支持当前运维协议。');
    }
    final result = MachineMaintenanceSnapshot(Map.unmodifiable(sections));
    if (previous != null && previous.identity == result.identity) {
      for (final entry in previous._counterCache.entries) {
        if (previous.text(entry.key) == result.text(entry.key)) {
          result._counterCache[entry.key] = entry.value;
        }
      }
      if (previous.text('memory') == result.text('memory')) {
        result._memory = previous._memory;
      }
      if (previous.text('processes') == result.text('processes')) {
        result._processes = previous._processes;
      }
    }
    return result;
  }

  final Map<String, String> sections;
  String text(String name) => sections[name] ?? '';
  double? get uptime => double.tryParse(text('uptime').split(' ').first);
  String get identity => '${text('platform')}|${text('host')}|${text('boot')}';

  final _counterCache = <String, Map<String, List<int>>>{};

  Map<String, List<int>> counters(String name, {bool colon = false}) {
    final cached = _counterCache[name];
    if (cached != null) return cached;
    final result = <String, List<int>>{};
    for (final line in text(name).split('\n')) {
      final fields = line
          .trim()
          .replaceAll(colon ? ':' : '\u0000', ' ')
          .split(RegExp(r'\s+'));
      if (fields.length < 2) continue;
      final values = fields.skip(1).map(int.tryParse).toList();
      if (values.any((value) => value == null)) continue;
      result[fields.first] = values.cast<int>();
    }
    _counterCache[name] = result;
    return result;
  }

  Map<String, int>? _memory;
  List<MachineMaintenanceProcess>? _processes;

  Map<String, int> get memory {
    if (_memory != null) return _memory!;
    final result = <String, int>{};
    for (final line in text('memory').split('\n')) {
      final fields = line.split(RegExp(r'[:\s]+'));
      if (fields.length >= 2) {
        final value = int.tryParse(fields[1]);
        if (value != null) {
          result[fields[0]] = value * (fields.contains('kB') ? 1024 : 1);
        }
      }
    }
    return _memory = Map.unmodifiable(result);
  }

  double? cpuUsage(MachineMaintenanceSnapshot? previous, [String cpu = 'cpu']) {
    final direct = counters('cpu_percent')[cpu]?.firstOrNull;
    if (direct != null) return (direct / 10000).clamp(0, 1);
    if (previous == null || previous.identity != identity) return null;
    final now = counters('cpu')[cpu];
    final old = previous.counters('cpu')[cpu];
    if (now == null || old == null || now.length < 8 || old.length < 8) {
      return null;
    }
    final deltas = List.generate(8, (index) => now[index] - old[index]);
    if (deltas.any((value) => value < 0)) return null;
    final total = deltas.fold<int>(0, (a, b) => a + b);
    return total <= 0
        ? null
        : ((total - deltas[3] - deltas[4]) / total).clamp(0, 1);
  }

  double? rate(
    MachineMaintenanceSnapshot? previous,
    String section,
    String key,
    int index, {
    int multiplier = 1,
  }) {
    final seconds = uptime;
    final oldSeconds = previous?.uptime;
    if (previous == null ||
        previous.identity != identity ||
        seconds == null ||
        oldSeconds == null ||
        seconds <= oldSeconds) {
      return null;
    }
    final current = counters(section, colon: section == 'network')[key];
    final old = previous.counters(section, colon: section == 'network')[key];
    if (current == null ||
        old == null ||
        current.length <= index ||
        old.length <= index ||
        current[index] < 0 ||
        old[index] < 0 ||
        current[index] < old[index]) {
      return null;
    }
    return (current[index] - old[index]) * multiplier / (seconds - oldSeconds);
  }

  List<MachineMaintenanceProcess> get processes =>
      _processes ??= text('processes')
          .split('\n')
          .map(MachineMaintenanceProcess.parse)
          .whereType<MachineMaintenanceProcess>()
          .toList();
}

class MachineMaintenanceProcess {
  const MachineMaintenanceProcess(
    this.pid,
    this.parent,
    this.state,
    this.nice,
    this.threads,
    this.residentPages,
    this.virtualBytes,
    this.ticks,
    this.started,
    this.name, {
    this.startToken,
  });
  static MachineMaintenanceProcess? parse(String line) {
    final fields = line.split('\t');
    if (fields.length < 10) return null;
    final numbers = [
      0,
      1,
      3,
      4,
      5,
      6,
      7,
      8,
    ].map((index) => int.tryParse(fields[index])).toList();
    if (numbers.any((value) => value == null)) return null;
    return MachineMaintenanceProcess(
      numbers[0]!,
      numbers[1]!,
      fields[2],
      numbers[2]!,
      numbers[3]!,
      numbers[4]!,
      numbers[5]!,
      numbers[6]!,
      numbers[7]!,
      fields[9],
      startToken: fields.length > 10 && fields[10].isNotEmpty
          ? fields[10]
          : null,
    );
  }

  final int pid,
      parent,
      nice,
      threads,
      residentPages,
      virtualBytes,
      ticks,
      started;
  final String state, name;
  final String? startToken;
}

const _linuxPrelude = r'''
export LC_ALL=C LANG=C SYSTEMD_COLORS=0 SYSTEMD_PAGER=cat PAGER=cat
section() { printf '\n__OH_OPS_%s__\n' "$1"; }
bounded() {
  if command -v timeout >/dev/null 2>&1; then timeout -s TERM 5 "$@"; else "$@"; fi
}
section platform
uname -s
[ "$(uname -s)" = Linux ] || { section end; exit 0; }
section host
hostname
section boot
cat /proc/sys/kernel/random/boot_id 2>/dev/null
''';

const machineMaintenanceOverviewCommand =
    _linuxPrelude +
    r'''
section capabilities
printf '内核接口：'
for f in /proc/stat /proc/meminfo /proc/diskstats /proc/net/dev /proc/pressure/io; do
  [ -r "$f" ] && printf ' %s' "$f"
done
printf '\n可用工具：'
for t in systemctl rc-status rc-service sv service ip ss netstat journalctl nft iptables docker podman; do
  command -v "$t" >/dev/null 2>&1 && printf ' %s' "$t"
done
printf '\n'
section blocks
if command -v lsblk >/dev/null 2>&1; then bounded lsblk 2>&1 | head -c 8000; fi
cat /proc/mdstat 2>/dev/null
section cgroup_limits
cat /proc/self/cgroup 2>/dev/null
for f in /sys/fs/cgroup/memory.max /sys/fs/cgroup/memory.current /sys/fs/cgroup/cpu.max /sys/fs/cgroup/memory/memory.limit_in_bytes /sys/fs/cgroup/cpu/cpu.cfs_quota_us /sys/fs/cgroup/cpu/cpu.cfs_period_us; do
  [ -r "$f" ] && printf '%s: %s\n' "$f" "$(cat "$f")"
done
section kernel
for f in /proc/sys/fs/file-nr /proc/sys/fs/file-max /proc/sys/kernel/pid_max /proc/sys/kernel/threads-max /proc/sys/vm/swappiness /proc/sys/net/core/somaxconn; do
  [ -r "$f" ] && printf '%s: %s\n' "$f" "$(cat "$f")"
done
section system
cat /etc/os-release 2>/dev/null
uname -a
section uptime
cat /proc/uptime
section load
cat /proc/loadavg
section cpu
head -c 24576 /proc/stat
section processor
awk -F: '/model name|Hardware|Processor/ {print $2; exit}' /proc/cpuinfo
section memory
cat /proc/meminfo
section vm
cat /proc/vmstat
section disks
awk '{print $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14}' /proc/diskstats
section network
cat /proc/net/dev
section pressure
for f in /proc/pressure/*; do [ -r "$f" ] || continue; printf '%s\n' "$f"; cat "$f"; done
section filesystems
bounded df -Pk 2>&1 | head -c 12000
section inodes
bounded df -Pi 2>&1 | head -c 8000
section swap
cat /proc/swaps
section interfaces
if command -v ip >/dev/null 2>&1; then bounded ip -o address show 2>/dev/null; fi
for d in /sys/class/net/*; do
  [ -d "$d" ] || continue
  printf '\n%s\n' "${d##*/}"
  for f in address operstate mtu speed duplex; do [ -r "$d/$f" ] && printf '%s: %s\n' "$f" "$(cat "$d/$f" 2>/dev/null)"; done
done
section sensors
for d in /sys/class/thermal/thermal_zone*; do
  [ -r "$d/temp" ] || continue
  printf '%s: %s 毫摄氏度\n' "$(cat "$d/type")" "$(cat "$d/temp")"
done
section end
''';

String machineMaintenanceProcessesCommand({int offset = 0}) {
  if (offset < 0) throw ArgumentError('进程偏移无效。');
  return _linuxPrelude +
      r'''
section uptime
cat /proc/uptime
section page_size
getconf PAGESIZE 2>/dev/null || printf '未知\n'
section clock_ticks
getconf CLK_TCK 2>/dev/null || printf '未知\n'
section processes
awk '
FNR == 1 {
  count++; if (count <= __PROCESS_OFFSET__ || count > __PROCESS_OFFSET__ + __PROCESS_LIMIT__) { next }
  pid=$1; name=$0; sub(/^[^(]*\(/,"",name); sub(/\) .*/,"",name)
  line=$0; sub(/^.*\) /,"",line); n=split(line,a," ")
  gsub(/[\t\r\n]/," ",name)
  if (n>=22) printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%.0f\t%s\t%s\n",pid,a[2],a[1],a[17],a[18],a[22],a[21],a[12]+a[13],a[20],name
}
END {printf "__COUNT__\t%d\n",count}
' /proc/[0-9]*/stat 2>/dev/null
section end
'''
          .replaceAll('__PROCESS_LIMIT__', '$machineMaintenanceProcessLimit')
          .replaceAll('__PROCESS_OFFSET__', '$offset');
}

const machineMaintenanceServicesCommand =
    _linuxPrelude +
    r'''
section manager
if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
  printf 'systemd\n'
  section services
  bounded systemctl list-units --type=service --all --no-legend --plain --no-pager 2>&1 | head -c 50000
  section service_metrics
  bounded sh -c 'systemctl list-units --type=service --all --no-legend --plain --no-pager | sed "s/^ *//;s/ .*//" | grep "[.]service$" | xargs -r -d "\n" systemctl show --no-pager -p Id -p MainPID -p MemoryCurrent -p CPUUsageNSec -p TasksCurrent -p NRestarts -p ExecMainStatus -p Requires -p Wants --' 2>&1 | head -c 160000
  section startup
  bounded systemctl list-unit-files --type=service --no-legend --no-pager 2>&1 | head -c 20000
  section timers
  bounded systemctl list-timers --all --no-pager 2>&1 | head -c 12000
elif command -v rc-status >/dev/null 2>&1 && command -v rc-service >/dev/null 2>&1; then
  printf 'OpenRC\n'
  section services
  bounded rc-status --all 2>&1 | head -c 30000
  section installed
  bounded rc-service --list 2>&1 | head -c 16000
  section startup
  bounded rc-update show 2>&1 | head -c 16000
elif command -v sv >/dev/null 2>&1; then
  printf 'runit\n'
  section services
  for d in /var/service/* /etc/service/*; do
    [ -d "$d" ] || continue
    printf '%s\t%s\n' "$d" "$(sv status "$d" 2>&1)"
  done | head -c 50000
elif [ -d /etc/init.d ]; then
  printf 'SysV\n'
  section services
  for f in /etc/init.d/*; do
    [ -x "$f" ] && [ -f "$f" ] || continue
    printf '%s\t状态按需查询\n' "${f##*/}"
  done | head -c 50000
else
  printf '未知\n'; section services; printf '未发现受支持的服务管理器。\n'
fi
section end
''';

const machineMaintenanceDiagnosticsCommand =
    _linuxPrelude +
    r'''
section sockets
if command -v ss >/dev/null 2>&1; then ss -tunap 2>&1 | head -c 18000
elif command -v netstat >/dev/null 2>&1; then netstat -tunap 2>&1 | head -c 18000
else printf '未安装 ss 或 netstat。\n'; fi
section routes
if command -v ip >/dev/null 2>&1; then ip address 2>&1; ip route 2>&1; ip -6 route 2>&1
else cat /proc/net/route /proc/net/ipv6_route 2>/dev/null; fi
section dns
cat /etc/resolv.conf 2>/dev/null
section logs
if command -v journalctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then bounded journalctl -n 80 --no-pager -o short-iso 2>&1 | head -c 20000
else dmesg 2>&1 | tail -n 80 | head -c 20000; fi
section users
who 2>&1
section cron
if command -v crontab >/dev/null 2>&1; then crontab -l 2>&1 | head -c 8000; else printf '未安装 crontab。\n'; fi
section firewall
if command -v nft >/dev/null 2>&1; then bounded nft list ruleset 2>&1 | head -c 12000
elif command -v iptables >/dev/null 2>&1; then bounded iptables -S 2>&1 | head -c 12000
else printf '未安装 nft 或 iptables。\n'; fi
section containers
if command -v docker >/dev/null 2>&1; then bounded docker ps -a --no-trunc 2>&1 | head -c 12000
elif command -v podman >/dev/null 2>&1; then bounded podman ps -a --no-trunc 2>&1 | head -c 12000
else printf '未安装 Docker 或 Podman。\n'; fi
section end
''';

String machineMaintenanceProcessCommand(
  MachineMaintenanceProcess process, {
  String? signal,
}) {
  if (process.pid < 1 || process.started < 0) throw ArgumentError('进程标识无效。');
  if (signal != null &&
      (process.pid <= 1 || !const ['TERM', 'STOP', 'CONT'].contains(signal))) {
    throw ArgumentError('不支持该信号。');
  }
  final guard =
      '''
pid=${process.pid}
[ -r /proc/\$pid/stat ] || { printf '进程已经退出或无权访问。\\n'; exit 1; }
start=\$(sed 's/^.*) //' /proc/\$pid/stat | awk '{print \$20}')
[ "\$start" = '${process.started}' ] || { printf '进程标识已经被重用，请刷新。\\n'; exit 1; }
''';
  if (signal != null) return '$_linuxPrelude$guard\nkill -$signal "\$pid"';
  return '''$_linuxPrelude$guard
section status
cat /proc/\$pid/status 2>&1
section command
tr '\\000' ' ' < /proc/\$pid/cmdline
section paths
ls -ld /proc/\$pid/exe /proc/\$pid/cwd /proc/\$pid/root 2>&1
section io
cat /proc/\$pid/io 2>&1
section limits
cat /proc/\$pid/limits 2>&1
section cgroup
cat /proc/\$pid/cgroup 2>&1
section memory
cat /proc/\$pid/smaps_rollup 2>&1 | head -c 10000
section descriptors
ls -l /proc/\$pid/fd 2>&1 | head -c 20000
section logs
if command -v journalctl >/dev/null 2>&1; then
  since=\$(awk -v ticks=${process.started} -v hz="\$(getconf CLK_TCK)" '\$1=="btime" && hz>0 {printf "%.0f",\$2+ticks/hz}' /proc/stat)
  [ -n "\$since" ] && bounded journalctl -b --since="@\$since" _PID=\$pid -n 60 --no-pager -o short-iso 2>&1 | head -c 20000; fi
section end
''';
}

/// 只允许在采样时的机器上读取详情和执行操作，不接受终端切换后的陈旧目标。
String machineMaintenanceBoundCommand(
  MachineMaintenanceSnapshot snapshot,
  String command,
) {
  final host = posixShellQuote(snapshot.text('host'));
  final boot = posixShellQuote(snapshot.text('boot'));
  return '\n[ "\$(hostname)" = $host ] && '
      '[ "\$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)" = $boot ] || '
      '{ printf "终端目标已经变化，请关闭面板后重新打开。\\n"; exit 1; }\n$command';
}

/// 按能力选择策略，发行版版本和名称不参与命令分支。
abstract class MachineMaintenanceServiceAdapter {
  const MachineMaintenanceServiceAdapter();

  static MachineMaintenanceServiceAdapter? detect(String manager) =>
      switch (manager) {
        'systemd' => const _SystemdMaintenanceAdapter(),
        'OpenRC' => const _OpenRcMaintenanceAdapter(),
        'runit' => const _RunitMaintenanceAdapter(),
        'SysV' => const _SysVMaintenanceAdapter(),
        _ => null,
      };

  Map<String, String> get actions => const {
    '启动服务': 'start',
    '停止服务': 'stop',
    '重启服务': 'restart',
  };
  bool accepts(String name) =>
      RegExp(r'^[a-zA-Z0-9_][a-zA-Z0-9_.:@\x2d]*$').hasMatch(name);
  String invoke(String name, String action);
  String detail(String name) =>
      '$_linuxPrelude\nsection status\n${invoke(name, 'status')} 2>&1\nsection end';

  String command(String name, [String? action]) {
    if (!accepts(name) || (action != null && !actions.containsValue(action))) {
      throw ArgumentError('服务名称或操作无效。');
    }
    return action == null ? detail(name) : invoke(name, action);
  }
}

class _SystemdMaintenanceAdapter extends MachineMaintenanceServiceAdapter {
  const _SystemdMaintenanceAdapter();
  @override
  Map<String, String> get actions => {
    ...super.actions,
    '启用开机启动': 'enable',
    '禁用开机启动': 'disable',
  };
  @override
  bool accepts(String name) => super.accepts(name) && name.endsWith('.service');
  @override
  String invoke(String name, String action) =>
      'systemctl --no-ask-password $action -- ${posixShellQuote(name)}';
  @override
  String detail(String name) =>
      '''$_linuxPrelude
section status
systemctl show --no-pager -- ${posixShellQuote(name)} 2>&1 | head -c 25000
section logs
journalctl -u ${posixShellQuote(name)} -n 60 --no-pager -o short-iso 2>&1 | head -c 20000
section end
''';
}

class _OpenRcMaintenanceAdapter extends MachineMaintenanceServiceAdapter {
  const _OpenRcMaintenanceAdapter();
  @override
  bool accepts(String name) => super.accepts(name) && !name.endsWith(':');
  @override
  Map<String, String> get actions => {
    ...super.actions,
    '加入默认运行级别': 'enable',
    '移出默认运行级别': 'disable',
  };
  @override
  String invoke(String name, String action) => switch (action) {
    'enable' => 'rc-update add ${posixShellQuote(name)} default',
    'disable' => 'rc-update del ${posixShellQuote(name)} default',
    _ => 'rc-service ${posixShellQuote(name)} $action',
  };
}

class _RunitMaintenanceAdapter extends MachineMaintenanceServiceAdapter {
  const _RunitMaintenanceAdapter();
  @override
  bool accepts(String name) => RegExp(
    r'^/(var|etc)/service/[a-zA-Z0-9_][a-zA-Z0-9_.:@\x2d]*$',
  ).hasMatch(name);
  @override
  String invoke(String name, String action) {
    final verb = switch (action) {
      'start' => 'up',
      'stop' => 'down',
      _ => action,
    };
    return 'sv -w 10 $verb ${posixShellQuote(name)}';
  }
}

class _SysVMaintenanceAdapter extends MachineMaintenanceServiceAdapter {
  const _SysVMaintenanceAdapter();
  @override
  String invoke(String name, String action) =>
      'if command -v service >/dev/null 2>&1; then service ${posixShellQuote(name)} $action; '
      'else ${posixShellQuote('/etc/init.d/$name')} $action; fi';
}

final machineMaintenanceGpuCommand =
    _linuxPrelude +
    machineGpuLinuxCollection.replaceAll('__GPU_QUERY__', machineGpuQuery);

const machineMaintenanceLogsCommand =
    _linuxPrelude + machineLogsLinuxCollection;

const machineMaintenanceHealthCommand =
    _linuxPrelude + machineHealthLinuxCollection;
