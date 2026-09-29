import 'dart:convert';

import 'package:xml/xml.dart';

const machineGpuQuery =
    'uuid,name,driver_version,pci.bus_id,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw,power.limit,clocks.current.graphics,clocks.current.memory,fan.speed,pstate';

const machineGpuLinuxCollection = r"""
gpu_probe() {
  if command -v timeout >/dev/null 2>&1; then timeout -k 1 -s TERM 2 "$@"; else bounded "$@"; fi
  code=$?
  [ "$code" -eq 0 ] || printf '\n__GPU_PROBE_EXIT_%s__\n' "$code"
}
section gpu_nvidia
if command -v nvidia-smi >/dev/null 2>&1; then
  bounded nvidia-smi --query-gpu=__GPU_QUERY__ --format=csv,noheader,nounits 2>/dev/null | head -c 40000
fi
section gpu_processes
if command -v nvidia-smi >/dev/null 2>&1; then
  bounded nvidia-smi --query-compute-apps=gpu_uuid,pid,process_name,used_gpu_memory --format=csv,noheader,nounits 2>/dev/null | head -c 20000
fi
section gpu_details
if command -v nvidia-smi >/dev/null 2>&1; then
  gpu_probe nvidia-smi -q -x 2>&1 | head -c 120000
fi
section gpu_links
if command -v nvidia-smi >/dev/null 2>&1; then
  gpu_probe nvidia-smi nvlink --status 2>&1 | head -c 20000
fi
section gpu_link_errors
if command -v nvidia-smi >/dev/null 2>&1; then
  gpu_probe nvidia-smi nvlink --errorcounters 2>&1 | head -c 16000
fi
section gpu_stack
if command -v nvcc >/dev/null 2>&1; then
  printf 'CUDA Toolkit\tpath\t%s\n' "$(command -v nvcc)"
  gpu_probe nvcc --version 2>/dev/null | awk '/release/ {print "CUDA Toolkit\tversion\t" $0}'
fi
if command -v dpkg-query >/dev/null 2>&1; then
  gpu_probe dpkg-query -W -f='${binary:Package}\t${Version}\t${db:Status-Status}\n' 'cuda-*' '*cudnn*' '*nccl*' '*fabricmanager*' '*nvswitch*' '*dcgm*' 2>/dev/null |
    awk -F '\t' '$3 == "installed" {print $1 "\tversion\t" $2}' | head -n 100
elif command -v rpm >/dev/null 2>&1; then
  gpu_probe rpm -qa --qf '%{NAME}\tversion\t%{VERSION}-%{RELEASE}\n' 2>/dev/null |
    awk '/^(cuda-|libcudnn|cudnn|libnccl|nccl|nvidia-fabric|nvidia-nvswitch|datacenter-gpu-manager)/' | head -n 100
fi
for f in /usr/include/cudnn_version.h /usr/local/cuda/include/cudnn_version.h /usr/include/x86_64-linux-gnu/cudnn_version.h /usr/local/include/cudnn_version.h /usr/local/cuda/targets/*/include/cudnn_version.h; do
  [ -r "$f" ] || continue
  printf 'cuDNN header\tpath\t%s\n' "$f"
  awk '/^#define CUDNN_(MAJOR|MINOR|PATCHLEVEL)[[:space:]]/ {print "cuDNN header\t" $2 "\t" $3}' "$f"
  break
done
section gpu_toolkit
for f in /usr/local/cuda/version.json /opt/cuda/version.json; do
  [ -r "$f" ] || continue
  head -c 16000 "$f"
  break
done
section gpu_fabric
if command -v systemctl >/dev/null 2>&1; then
  gpu_probe systemctl show nvidia-fabricmanager.service --no-pager -p LoadState -p ActiveState -p SubState -p MainPID -p NRestarts -p MemoryCurrent -p CPUUsageNSec -p Result 2>&1 | head -c 8000
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

/// 组件信息与硬件遥测分离；不把驱动兼容版本当成已安装的工具包。
class MachineGpuReport {
  MachineGpuReport(this.title, this.rows, {this.issue = ''});
  final String title, issue;
  final List<List<String>> rows;

  static List<MachineGpuReport> parse(Map<String, String> sections) {
    final reports = <MachineGpuReport>[];
    String failure(String raw) {
      final text = raw.toLowerCase();
      if (text.contains('permission') ||
          text.contains('access denied') ||
          text.contains('insufficient')) {
        return 'permission';
      }
      if (text.contains('not supported') || text.contains('unsupported')) {
        return 'unsupported';
      }
      if (text.contains('not found') || text.contains('not recognized')) {
        return 'missing';
      }
      return 'unavailable';
    }

    final xml = (sections['gpu_details'] ?? '').trim();
    if (xml.isNotEmpty) {
      try {
        final root = XmlDocument.parse(xml).rootElement;
        if (root.name.local != 'nvidia_smi_log') throw const FormatException();
        final driver = <List<String>>[];
        for (final key in ['driver_version', 'cuda_version', 'attached_gpus']) {
          final value = root.getElement(key)?.innerText.trim();
          if (value != null && value.isNotEmpty) driver.add([key, value]);
        }
        if (driver.isNotEmpty) reports.add(MachineGpuReport('NVIDIA', driver));
        for (final gpu in root.findElements('gpu')) {
          final id =
              gpu.getElement('uuid')?.innerText ??
              gpu.getAttribute('id') ??
              'GPU';
          // 迭代遍历限制深度和行数，完整保留指标路径，避免同名字段相互覆盖。
          final groups = <String, List<List<String>>>{};
          final pending = <(XmlElement, String, int)>[(gpu, '', 0)];
          var count = 0;
          while (pending.isNotEmpty && count < 700) {
            final (node, path, depth) = pending.removeLast();
            if (depth > 12) continue;
            final children = node.childElements.toList();
            if (children.isEmpty) {
              final value = node.innerText.trim();
              if (value.isEmpty) continue;
              final group = path.split('/').first;
              (groups[group] ??= []).add([path, value]);
              count++;
            } else {
              final totals = <String, int>{};
              for (final child in children) {
                totals.update(
                  child.name.local,
                  (n) => n + 1,
                  ifAbsent: () => 1,
                );
              }
              final indexes = Map<String, int>.of(totals);
              for (var i = children.length - 1; i >= 0; i--) {
                final child = children[i];
                final name = child.name.local;
                final suffix = totals[name]! > 1 ? '[${indexes[name]}]' : '';
                indexes[name] = indexes[name]! - 1;
                pending.add((
                  child,
                  '${path.isEmpty ? '' : '$path/'}${child.name.local}$suffix',
                  depth + 1,
                ));
              }
            }
          }
          reports.add(
            MachineGpuReport(
              id,
              groups.values.expand((rows) => rows).toList(),
              issue: pending.isNotEmpty ? 'truncated' : '',
            ),
          );
        }
      } on XmlException {
        reports.add(
          MachineGpuReport(
            'NVIDIA',
            [],
            issue: xml.startsWith('<') ? 'format' : failure(xml),
          ),
        );
      } on FormatException {
        reports.add(
          MachineGpuReport(
            'NVIDIA',
            [],
            issue: xml.startsWith('<') ? 'format' : failure(xml),
          ),
        );
      }
    }
    final components = <String, List<List<String>>>{};
    for (final line in (sections['gpu_stack'] ?? '').split('\n')) {
      final fields = line.split('\t');
      if (fields.length == 3 && fields.every((f) => f.trim().isNotEmpty)) {
        (components[fields[0]] ??= []).add(fields.sublist(1));
      }
    }
    final manifest = (sections['gpu_toolkit'] ?? '').trim();
    if (manifest.isNotEmpty) {
      try {
        final decoded = jsonDecode(manifest);
        if (decoded is! Map) throw const FormatException();
        for (final entry in decoded.entries) {
          if (entry.value is! Map) continue;
          final metadata = entry.value as Map;
          final version = metadata['version'];
          if (version is! String || version.isEmpty) continue;
          (components['${entry.key} (version.json)'] ??= []).add([
            'version',
            version,
          ]);
        }
      } on FormatException {
        reports.add(MachineGpuReport('CUDA version.json', [], issue: 'format'));
      }
    }
    for (final entry in components.entries) {
      reports.add(MachineGpuReport(entry.key, entry.value));
    }
    final fabric = (sections['gpu_fabric'] ?? '').trim();
    if (fabric.isNotEmpty) {
      final rows = <List<String>>[];
      for (final line in fabric.split('\n')) {
        final i = line.indexOf('=');
        if (i > 0) rows.add([line.substring(0, i), line.substring(i + 1)]);
      }
      reports.add(
        MachineGpuReport(
          'Fabric Manager',
          rows,
          issue: fabric.contains('LoadState=not-found')
              ? 'missing'
              : rows.isEmpty
              ? failure(fabric)
              : '',
        ),
      );
    }
    final links = (sections['gpu_links'] ?? '').trim();
    if (links.isNotEmpty) {
      var gpu = '';
      final rows = <List<String>>[];
      for (final line in links.split('\n')) {
        if (line.trimLeft().startsWith('GPU ')) gpu = line.trim();
        final match = RegExp(r'^\s*Link\s+(\d+)\s*:\s*(.+)$').firstMatch(line);
        if (match != null) rows.add(['$gpu / Link ${match[1]}', match[2]!]);
      }
      reports.add(
        MachineGpuReport(
          'NVLink',
          rows,
          issue: rows.isEmpty ? failure(links) : '',
        ),
      );
    }

    final errors = (sections['gpu_link_errors'] ?? '').trim();
    if (errors.isNotEmpty) {
      var device = '', link = '';
      final rows = <List<String>>[];
      for (final line in errors.split('\n')) {
        if (line.trimLeft().startsWith('GPU ')) {
          device = line.trim();
          link = '';
          continue;
        }
        final match = RegExp(r'^\s*Link\s+(\d+)\s*:\s*(.*)$').firstMatch(line);
        if (match != null) {
          link = 'Link ${match[1]}';
          if (match[2]!.isNotEmpty) rows.add(['$device / $link', match[2]!]);
          continue;
        }
        final i = line.indexOf(':');
        if (device.isNotEmpty && link.isNotEmpty && i > 0) {
          rows.add([
            '$device / $link / ${line.substring(0, i).trim()}',
            line.substring(i + 1).trim(),
          ]);
        }
      }
      reports.add(
        MachineGpuReport(
          'NVLink · counters',
          rows,
          issue: rows.isEmpty ? failure(errors) : '',
        ),
      );
    }
    return reports;
  }
}
