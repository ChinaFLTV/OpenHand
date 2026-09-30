import 'machine_maintenance_readout.dart';

/// 保留原始单位和地址；源选择状态与采集成功分别判断。
class MachineTimeReport {
  MachineTimeReport.parse(String raw) {
    var block = '';
    final sources = <List<String>>[];
    final peers = <List<String>>[];
    final statistics = <List<String>>[];
    final selections = <List<String>>[];
    final measurements = <List<String>>[];
    final fields = <List<String>>[];
    var pendingPeer = '';
    final windowsPeers = <Map<String, String>>[];
    final services = <Map<String, String>>[];
    var service = <String, String>{};
    var measurementStart = 0;
    for (final original in raw.split('\n')) {
      var line = original.trim();
      if (pendingPeer.isNotEmpty) {
        line = '$pendingPeer $line';
        pendingPeer = '';
      }
      if (block == 'NTP 时钟源' &&
          RegExp(r'^[*+#ox.\-]?[0-9a-fA-F:.%]+$').hasMatch(line) &&
          line.contains(':')) {
        pendingPeer = line;
        continue;
      }
      if ((line.isEmpty || line.startsWith('@@OH_')) && service.isNotEmpty) {
        services.add(service);
        service = {};
      }
      if (line.isEmpty) continue;
      if (line.startsWith('@@OH_TIME:')) {
        block = line.substring(10);
        measurementStart = measurements.length;
        continue;
      }
      if (line.startsWith('@@OH_RESULT:')) {
        final code = line.substring(12);
        if (code != '0') {
          if (block == 'SNTP 只读测量') {
            measurements.removeRange(measurementStart, measurements.length);
          }
          fields.add(['采集状态 · $block', '查询失败（退出码 $code），查看采集详情']);
          partial = true;
        }
        block = '';
        continue;
      }
      if (block == 'SNTP 只读测量') {
        final sample = RegExp(
          r'^([-+]?\d+(?:\.\d+)?)\s+\+/-\s+(\d+(?:\.\d+)?)\s+(\S+)\s+(\S+)$',
        ).firstMatch(line);
        if (sample != null) {
          measurements.add([sample[3]!, sample[4]!, sample[1]!, sample[2]!]);
          continue;
        }
        final result = RegExp(r'^result:\s*\d+\s*\(([^)]+)\)').firstMatch(line);
        final address = RegExp(r'^addr:\s*(\S+)').firstMatch(line);
        if (result != null) {
          fields.add([
            'SNTP 测量结果',
            result[1] == 'Timeout' ? '请求超时，未获得有效偏移样本' : result[1]!,
          ]);
        }
        if (address != null) fields.add(['SNTP 目标地址', address[1]!]);
        // 超时调试包中的十六进制时间与派生偏移不是有效采样。
        continue;
      }
      final chrony = RegExp(
        r'^([\^=#])([*+\-?x~])\s+(\S+)\s+(\d+)\s+(-?\d+)\s+(\d+)\s+(\S+)\s+([^\[]+)\[\s*([^\]]+)\]\s+\+/-\s*(.+)$',
      ).firstMatch(line);
      if (chrony != null) {
        const states = {
          '*': '最优 · 当前选中',
          '+': '参与合并',
          '-': '可用 · 未参与合并',
          '?': '不可选 · 不可达或样本不足',
          'x': '排除 · 错误时钟',
          '~': '排除 · 波动过大',
        };
        sources.add([
          chrony[3]!,
          '${chrony[2]} ${states[chrony[2]]}',
          const {'^': '服务器', '=': '对等节点', '#': '参考时钟'}[chrony[1]]!,
          for (var i = 4; i <= 10; i++) chrony[i]!.trim(),
        ]);
        continue;
      }
      final ntp = RegExp(
        r'^([*+#ox.\-]?)(\S+)\s+(\S+)\s+(\d+)\s+(\S+)\s+(\S+)\s+(\d+)\s+(\d+)\s+([-+\d.]+)\s+([-+\d.]+)\s+([-+\d.]+)$',
      ).firstMatch(line);
      if (ntp != null) {
        const states = {
          '*': '当前选中',
          'o': '当前选中 · PPS',
          '+': '候选',
          '#': '备份',
          '-': '排除 · 离群',
          'x': '排除 · 错误时钟',
          '.': '排除 · 过量',
          '': '拒绝或不可达',
        };
        peers.add([
          ntp[2]!,
          '${ntp[1]} ${states[ntp[1]]}'.trim(),
          for (var i = 3; i <= 11; i++) ntp[i]!,
        ]);
        continue;
      }
      if (block == 'Chrony 源统计') {
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length == 8 && int.tryParse(parts[1]) != null) {
          statistics.add(parts);
          continue;
        }
      }
      if (block == 'Chrony 选择详情') {
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length == 10 &&
            parts[0].length == 1 &&
            double.tryParse(parts[6]) != null) {
          const states = {
            '*': '最优 · 当前选中',
            '+': '参与合并',
            'N': '排除 · noselect',
            'M': '样本不足',
            's': '未同步',
            'd': '根距离超限',
            '~': '抖动超限',
            'w': '等待其他源采样',
            'S': '样本过旧',
            'O': '孤立层级',
            'T': '不符合信任源',
            'x': '错误时钟',
            'W': '等待可选源',
            'P': '其他源优先',
            'U': '等待新样本',
            'D': '未合并 · 根距离过大',
          };
          selections.add([
            parts[1],
            '${parts[0]} ${states[parts[0]] ?? "未知状态"}',
            ...parts.skip(2),
          ]);
          continue;
        }
      }
      if (line.startsWith('===') ||
          line.startsWith('MS ') ||
          line.startsWith('S Name/') ||
          line.startsWith('Name/IP') ||
          line.startsWith('remote ') ||
          line.startsWith('200 OK')) {
        continue;
      }
      if (block == 'NTP 系统变量') {
        final values = RegExp(r'(\w+)=("[^"]*"|[^,]+)').allMatches(line);
        if (values.isNotEmpty) {
          for (final value in values) {
            fields.add([value[1]!, value[2]!.trim()]);
          }
          continue;
        }
      }
      // 地址中的冒号不能作为字段分隔符。
      final field =
          RegExp(r'^([^:=]+?)\s*(?::\s+|=)\s*(.+)$').firstMatch(line) ??
          RegExp(r'^([A-Za-z][A-Za-z /()_-]*):\s*(.+)$').firstMatch(line);
      if (field != null) {
        final name = field[1]!.trim();
        final value = field[2]!.trim();
        if (block == '时间服务状态') {
          service[name] = value;
        } else if (block == 'Windows peers' &&
            const ['Peer', '对等机', '对等体'].contains(name)) {
          windowsPeers.add({'时钟源': value});
        } else if (block == 'Windows peers' && windowsPeers.isNotEmpty) {
          windowsPeers.last[name] = value;
        } else {
          fields.add([name, value]);
        }
      } else {
        unparsed++;
      }
    }
    if (service.isNotEmpty) services.add(service);
    if (services.isNotEmpty) {
      tables['时间服务状态'] = MachineMaintenanceReadout(
        ['服务', '加载状态', '运行状态', '子状态'],
        [
          for (final service in services)
            [
              for (final key in ['Id', 'LoadState', 'ActiveState', 'SubState'])
                service[key] ?? '—',
            ],
        ],
      );
    }
    if (measurements.isNotEmpty) {
      tables['SNTP 只读测量（非系统选中状态）'] = MachineMaintenanceReadout([
        '配置源',
        '响应地址',
        '偏移（秒）',
        '误差界限（秒）',
      ], measurements);
    }
    if (windowsPeers.isNotEmpty) {
      final headers = windowsPeers.expand((peer) => peer.keys).toSet().toList();
      tables['Windows 时钟源'] = MachineMaintenanceReadout(headers, [
        for (final peer in windowsPeers)
          [for (final key in headers) peer[key] ?? '—'],
      ]);
    }
    if (sources.isNotEmpty) {
      tables['Chrony 时钟源'] = MachineMaintenanceReadout([
        '时钟源',
        '选择状态',
        '类型',
        '层级',
        '轮询（log₂ 秒）',
        '可达寄存器（八进制）',
        '距上次接收',
        '校正后偏移',
        '原始偏移',
        '误差界限',
      ], sources);
    }
    if (peers.isNotEmpty) {
      tables['NTP 时钟源'] = MachineMaintenanceReadout([
        '时钟源',
        '选择状态',
        '参考源',
        '层级',
        '类型',
        '距上次接收',
        '轮询（秒）',
        '可达寄存器（八进制）',
        '延迟（ms）',
        '偏移（ms）',
        '抖动（ms）',
      ], peers);
    }
    if (statistics.isNotEmpty) {
      tables['Chrony 源统计'] = MachineMaintenanceReadout([
        '时钟源',
        '样本数',
        '残差游程数',
        '采样跨度',
        '频率（ppm）',
        '频率误差（ppm）',
        '估计偏移',
        '标准差',
      ], statistics);
    }
    if (selections.isNotEmpty) {
      tables['Chrony 选择详情'] = MachineMaintenanceReadout([
        '时钟源',
        '选择状态',
        '认证',
        '配置选项',
        '有效选项',
        '距上次样本（秒）',
        '评分',
        '下界',
        '上界',
        '闰秒',
      ], selections);
    }
    if (sources.isEmpty &&
        peers.isEmpty &&
        measurements.isEmpty &&
        windowsPeers.isEmpty &&
        !fields.any(
          (r) => const [
            'ServerName',
            'ServerAddress',
            'Source',
            'Reference ID',
            '来源',
            '源',
          ].contains(r[0]),
        ) &&
        fields.any((r) => r[0] == 'configured')) {
      fields.add(['实时同步状态', '仅有配置，无法确定当前选中源、偏移或同步状态']);
      partial = true;
    }
    unsynchronized = fields.any(
      (r) =>
          (r[0] == 'Leap status' && r[1] == 'Not synchronised') ||
          (r[0] == 'leap' && r[1] == '11'),
    );
    if (RegExp(
      'Not authorised|Cannot talk to daemon|The following error occurred|发生以下错误|permission denied|access is denied',
      caseSensitive: false,
    ).hasMatch(raw)) {
      partial = true;
      unparsed++;
    }
    if (fields.any((r) => r[0] == '实时同步状态')) partial = true;
    if (pendingPeer.isNotEmpty) unparsed++;
    data = MachineMaintenanceReadout(['名称', '数值'], fields, fields: true);
  }
  late final MachineMaintenanceReadout data;
  final tables = <String, MachineMaintenanceReadout>{};
  bool partial = false;
  bool unsynchronized = false;
  int unparsed = 0;
}
