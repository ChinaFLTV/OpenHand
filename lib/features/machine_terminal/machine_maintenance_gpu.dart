import 'dart:convert';

const machineGpuQuery =
    'uuid,name,driver_version,pci.bus_id,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw,power.limit,clocks.current.graphics,clocks.current.memory,fan.speed,pstate';

const machineGpuLinuxCollection = r"""
section gpu_nvidia
if command -v nvidia-smi >/dev/null 2>&1; then
  bounded nvidia-smi --query-gpu=__GPU_QUERY__ --format=csv,noheader,nounits 2>/dev/null | head -c 40000
fi
section gpu_processes
if command -v nvidia-smi >/dev/null 2>&1; then
  bounded nvidia-smi --query-compute-apps=gpu_uuid,pid,process_name,used_gpu_memory --format=csv,noheader,nounits 2>/dev/null | head -c 20000
fi
section gpu_drm
for d in /sys/class/drm/card[0-9]*/device; do
  [ -d "$d" ] || continue
  card=${d%/device}; card=${card##*/}
  case "$card" in *-*) continue;; esac
  printf 'id=%s\n' "$card"
  printf 'bus=%s\n' "$(basename "$(readlink -f "$d")")"
  printf 'driver=%s\n' "$(basename "$(readlink -f "$d/driver")")"
  for field in vendor device gpu_busy_percent mem_info_vram_used mem_info_vram_total; do
    [ -r "$d/$field" ] && printf '%s=%s\n' "$field" "$(cat "$d/$field")"
  done
  for h in "$d"/hwmon/hwmon*; do
    [ -d "$h" ] || continue
    for field in temp1_input power1_average power1_cap fan1_input; do
      [ -r "$h/$field" ] && printf '%s=%s\n' "$field" "$(cat "$h/$field")"
    done
    break
  done
  printf '\n'
done | head -c 30000
section end
""";

const machineGpuMacCollection = r"""
section gpu_apple
system_profiler SPDisplaysDataType -json -detailLevel mini 2>/dev/null | head -c 50000
section gpu_accelerators
ioreg -r -c IOAccelerator -l 2>/dev/null | awk '/^[| +]*\+-o / || /"model" =/ || /"PerformanceStatistics" =/' | head -c 30000
section end
""";

/// 数值统一到字节、摄氏度、瓦和 MHz；不可用字段保留为空。
class MachineGpuDevice {
  MachineGpuDevice(this.id, this.name, this.source, this.info, this.metrics);
  final String id, name, source;
  final Map<String, String> info;
  final Map<String, double> metrics;
}

class MachineGpuSnapshot {
  MachineGpuSnapshot(this.devices, this.processes, this.displays);

  factory MachineGpuSnapshot.parse(Map<String, String> sections) {
    final devices = <MachineGpuDevice>[];
    final processes = <List<String>>[];
    final displays = <List<String>>[];
    void addMetric(
      Map<String, double> metrics,
      String key,
      Object? raw, [
      double scale = 1,
    ]) {
      final value = number(raw);
      if (value != null &&
          (value * scale).isFinite &&
          (!['util', 'fan', 'renderer', 'tiler'].contains(key) ||
              value <= 100)) {
        metrics[key] = value * scale;
      }
    }

    for (final line in (sections['gpu_nvidia'] ?? '').split('\n')) {
      final f = csv(line);
      if (f.length != 14 || !f.first.startsWith('GPU-')) continue;
      final metrics = <String, double>{};
      const keys = [
        'util',
        'memoryUsed',
        'memoryTotal',
        'temperature',
        'power',
        'powerLimit',
        'coreClock',
        'memoryClock',
        'fan',
      ];
      for (var i = 0; i < keys.length; i++) {
        addMetric(metrics, keys[i], f[i + 4], i == 1 || i == 2 ? 1048576 : 1);
      }
      devices.add(
        MachineGpuDevice(f[0], f[1], 'NVIDIA SMI', {
          'vendor': 'NVIDIA',
          'driver': f[2],
          'bus': f[3],
          'state': f[13],
        }, metrics),
      );
    }
    for (final block in (sections['gpu_drm'] ?? '').split(RegExp(r'\n\s*\n'))) {
      final fields = <String, String>{};
      for (final line in block.split('\n')) {
        final i = line.indexOf('=');
        if (i > 0) fields[line.substring(0, i)] = line.substring(i + 1);
      }
      if (fields['id'] == null) continue;
      final bus = fields['bus'] ?? '';
      if (bus.isNotEmpty &&
          devices.any(
            (d) =>
                d.info['bus']?.toLowerCase().endsWith(bus.toLowerCase()) ??
                false,
          )) {
        continue;
      }
      final metrics = <String, double>{};
      for (final entry in {
        'gpu_busy_percent': ('util', 1.0),
        'mem_info_vram_used': ('memoryUsed', 1.0),
        'mem_info_vram_total': ('memoryTotal', 1.0),
        'temp1_input': ('temperature', .001),
        'power1_average': ('power', .000001),
        'power1_cap': ('powerLimit', .000001),
        'fan1_input': ('fanRpm', 1.0),
      }.entries) {
        addMetric(metrics, entry.value.$1, fields[entry.key], entry.value.$2);
      }
      final vendor = switch (fields['vendor']) {
        '0x1002' => 'AMD',
        '0x8086' => 'Intel',
        '0x10de' => 'NVIDIA',
        _ => fields['vendor'] ?? '—',
      };
      devices.add(
        MachineGpuDevice(
          bus.isEmpty ? fields['id']! : bus,
          '$vendor ${fields['device'] ?? fields['id']}',
          'DRM / sysfs',
          {'vendor': vendor, 'driver': fields['driver'] ?? '—', 'bus': bus},
          metrics,
        ),
      );
    }
    final apple = sections['gpu_apple'] ?? '';
    if (apple.trim().startsWith('{')) {
      try {
        final decoded = jsonDecode(apple);
        final cards = decoded is Map ? decoded['SPDisplaysDataType'] : null;
        if (cards is List) {
          for (final card in cards.whereType<Map>()) {
            final name = '${card['sppci_model'] ?? card['_name'] ?? 'GPU'}';
            final metrics = <String, double>{};
            final accelerators = (sections['gpu_accelerators'] ?? '').split(
              RegExp(r'\+-o '),
            );
            final matching = accelerators
                .where((block) => block.contains('"model" = "$name"'))
                .toList();
            if (matching.length == 1 &&
                cards
                        .whereType<Map>()
                        .where((c) => (c['sppci_model'] ?? c['_name']) == name)
                        .length ==
                    1) {
              const keys = {
                'Device Utilization %': 'util',
                'Renderer Utilization %': 'renderer',
                'Tiler Utilization %': 'tiler',
                'In use system memory': 'sharedUsed',
                'Alloc system memory': 'sharedAllocated',
                'recoveryCount': 'recoveries',
              };
              for (final entry in keys.entries) {
                final match = RegExp(
                  '"${RegExp.escape(entry.key)}"=(\\d+)',
                ).firstMatch(matching.single);
                addMetric(metrics, entry.value, match?.group(1));
              }
            }
            addMetric(metrics, 'cores', card['sppci_cores']);
            devices.add(
              MachineGpuDevice(
                'apple:${card['spdisplays_device-id'] ?? name}:${devices.length}',
                name,
                'system_profiler / IOAccelerator',
                {
                  'vendor': '${card['spdisplays_vendor'] ?? '—'}'.replaceFirst(
                    'sppci_vendor_',
                    '',
                  ),
                  'bus': '${card['sppci_bus'] ?? '—'}'.replaceFirst(
                    'spdisplays_',
                    '',
                  ),
                  'metal': '${card['spdisplays_mtlgpufamilysupport'] ?? '—'}'
                      .replaceFirst('spdisplays_', ''),
                },
                metrics,
              ),
            );
            final screens = card['spdisplays_ndrvs'];
            if (screens is List) {
              for (final screen in screens.whereType<Map>()) {
                displays.add([
                  name,
                  '${screen['_name'] ?? '—'}',
                  '${screen['_spdisplays_pixels'] ?? '—'}',
                  '${screen['_spdisplays_resolution'] ?? screen['spdisplays_resolution'] ?? '—'}',
                ]);
              }
            }
          }
        }
      } on FormatException {
        // 截断的硬件 JSON 不作为有效设备。
      }
    }
    for (final line in (sections['gpu_windows'] ?? '').split('\n')) {
      final f = line.split('\t');
      if (f.length < 6 || f[0].isEmpty) continue;
      if (devices.any((d) => d.name.toLowerCase() == f[1].toLowerCase())) {
        continue;
      }
      devices.add(
        MachineGpuDevice(f[0], f[1], 'WMI', {
          'vendor': f[2],
          'driver': f[3],
          'state': f[4],
          'bus': f[5],
        }, {}),
      );
    }
    for (final line in (sections['gpu_processes'] ?? '').split('\n')) {
      final f = csv(line);
      if (f.length == 4 &&
          f[0].startsWith('GPU-') &&
          int.tryParse(f[1]) != null) {
        processes.add(f);
      }
    }
    return MachineGpuSnapshot(devices, processes, displays);
  }
  final List<MachineGpuDevice> devices;
  final List<List<String>> processes, displays;

  static double? number(Object? value) {
    final parsed = double.tryParse('$value'.trim());
    return parsed != null && parsed.isFinite && parsed >= 0 ? parsed : null;
  }

  static List<String> csv(String line) {
    final result = <String>[];
    var quoted = false;
    var field = StringBuffer();
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        if (quoted && i + 1 < line.length && line[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (c == ',' && !quoted) {
        result.add(field.toString().trim());
        field = StringBuffer();
      } else {
        field.write(c);
      }
    }
    result.add(field.toString().trim());
    return quoted ? [] : result;
  }
}
