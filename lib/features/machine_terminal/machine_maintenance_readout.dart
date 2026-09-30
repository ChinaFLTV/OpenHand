import 'dart:convert';

part 'machine_maintenance_network_readout.dart';

const _machineReadoutFieldLimit = 4096;
const _machineReadoutDepthLimit = 16;

const machineMaintenanceNetworkReports = {
  'addresses',
  'policy_routes',
  'neighbors',
  'network_stats',
  'socket_details',
  'dns_status',
  'firewall',
  'firewall_rules',
  'firewall_nat',
  'firewall_states',
  'firewall_ipvfour',
  'firewall_ipvsix',
};

/// 仅识别采集输出开头的明确错误，日志正文和正常指标不参与错误推断。
String? machineMaintenanceCollectionIssue(String output, String section) {
  if (section == 'logs' || section == 'command') return null;
  final first = output
      .trimLeft()
      .split('\n')
      .first
      .trim()
      .replaceFirst(
        RegExp(r'^(?:Bad state|FormatException|Exception):\s*'),
        '',
      );
  final failure = RegExp(
    r'^(?:you need administrator access|not authorised|not authorized|cannot talk to daemon|FATA\[.*?\].*|error:.*(?:failed|cannot|denied|not found|refused)|failed to connect|cannot connect|error during connect|error response from daemon|permission denied|operation not permitted|access is denied|access denied|could not|unable to connect|connection refused|connection timed out|context deadline exceeded|查询超时|查询失败|未安装|缺少|权限不足|无法连接|(?:docker|podman|crictl|nerdctl|ctr|kubectl|cat|ls|sh|bash|zsh|sudo|systemctl|launchctl|journalctl|netstat|pfctl|nft|iptables|ip6tables-save|iptables-save)(?::|\s+error).*?(?:error|failed|cannot|could not|unable|denied|not permitted|not found|no such file|refused|timed out))',
    caseSensitive: false,
  );
  if (!failure.hasMatch(first)) {
    return RegExp(
          '^(?:Bad state|FormatException|Exception):',
        ).hasMatch(output.trimLeft())
        ? 'unavailable'
        : null;
  }
  if (RegExp(
    'permission denied|not permitted|access.*denied|administrator access|not authori[sz]ed|权限不足|拒绝访问',
    caseSensitive: false,
  ).hasMatch(first)) {
    return 'permission';
  }
  if (RegExp(
    'timed out|timeout|deadline exceeded|超时',
    caseSensitive: false,
  ).hasMatch(first)) {
    return 'timeout';
  }
  if (RegExp('connect|docker api|无法连接', caseSensitive: false).hasMatch(first)) {
    return 'connection';
  }
  if (RegExp(
    'command not found|not found|not recognized|未安装|缺少',
    caseSensitive: false,
  ).hasMatch(first)) {
    return 'missing';
  }
  return 'unavailable';
}

List<List<String>> machineMaintenanceDiagnosticFields(String output) {
  final rows = <List<String>>[];
  final issue = output
      .split('\n')
      .map((line) => machineMaintenanceCollectionIssue(line, 'diagnostic'))
      .whereType<String>()
      .firstOrNull;
  final results = RegExp(
    r'(?:result:|@@OH_RESULT:)\s*(\d+)(?:\s*\(([^)]+)\))?',
  ).allMatches(output).toList();
  final result =
      results.where((r) => r[1] != '0').firstOrNull ?? results.firstOrNull;
  if (issue != null) {
    rows.add([
      '原因',
      switch (issue) {
        'permission' => '读取权限不足',
        'timeout' => '目标响应超时',
        'connection' => '连接未建立',
        'missing' => '所需工具不可用',
        _ => '采集未完成',
      },
    ]);
  }
  if (result != null) {
    rows.add(['结果代码', result[1]!]);
    if (result[2] != null) {
      rows.add(['结果', result[2] == 'Timeout' ? '响应超时' : result[2]!]);
    }
  }
  final endpoint = RegExp(
    r'(?:unix|https?|tcp)://[^\s;]+|/dev/[\w/.-]+',
  ).firstMatch(output);
  if (endpoint != null) {
    rows.add(['连接地址', endpoint[0]!.replaceFirst(RegExp(r':$'), '')]);
  }
  if (output.contains('no such file or directory')) {
    rows.add(['资源状态', '连接文件不存在，请检查服务是否运行']);
  }
  final statuses = RegExp(
    r'@@OH_TIME:([^\n]+)\n[\s\S]*?@@OH_RESULT:(\d+)',
  ).allMatches(output);
  for (final status in statuses) {
    rows.add([
      '采集项 · ${status[1]}',
      status[2] == '0' ? '成功' : '未完成 · 退出码 ${status[2]}',
    ]);
  }
  if (rows.isEmpty) rows.add(['诊断状态', '部分输出格式尚未识别，请检查采集工具版本和数据范围']);
  return rows;
}

/// 命令展示模型保留字段顺序、重复字段和完整值，不执行或改写采样内容。
class MachineMaintenanceReadout {
  const MachineMaintenanceReadout(
    this.headers,
    this.rows, {
    this.fields = false,
    this.issue,
    this.raw = false,
    this.groups = const {},
  });

  factory MachineMaintenanceReadout.parse(String output, String section) {
    final issue = machineMaintenanceCollectionIssue(output, section);
    if (issue != null) return MachineMaintenanceReadout([], [], issue: issue);
    final lines = output
        .replaceAll('\r', '')
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty ||
        lines.every(
          (line) => const [
            '-- No entries --',
            'No entries',
            'No entries.',
          ].contains(line.trim()),
        )) {
      return const MachineMaintenanceReadout([], []);
    }
    if (machineMaintenanceNetworkReports.contains(section) ||
        section == 'interfaces') {
      return _parseMachineNetworkReadout(lines, section);
    }
    if (section != 'logs' &&
        (output.trimLeft().startsWith('{') ||
            output.trimLeft().startsWith('['))) {
      try {
        final documents = <dynamic>[];
        try {
          documents.add(jsonDecode(output));
        } on FormatException {
          for (final line in lines) {
            documents.add(jsonDecode(line));
          }
        }
        return _machineJsonReadout(
          documents.length == 1 ? documents.single : documents,
        );
      } on FormatException {
        // 非 JSON 的 launchd 配置继续按属性解析。
        if (!output.contains('=')) {
          return const MachineMaintenanceReadout([], [], issue: 'format');
        }
      }
    }
    if (section == 'memory' &&
        lines.any((line) => line.contains('REGION TYPE'))) {
      return _machineMemoryReadout(lines);
    }
    if (section == 'gpu_report') return _machineGpuReadout(lines);
    if (section == 'container_metrics') {
      return _machineColumnReadout(lines);
    }
    if (section == 'startup') {
      final entries = <List<String>>[];
      var directory = '';
      final mac = lines.any(
        (line) =>
            line.startsWith('__OH_STARTUP__\t') ||
            RegExp(r'^/.*Launch(?:Agents|Daemons):$').hasMatch(line.trim()),
      );
      if (mac) {
        for (final line in lines) {
          final text = line.trim();
          if (RegExp(r'^/.*Launch(?:Agents|Daemons):$').hasMatch(text)) {
            directory = text.substring(0, text.length - 1);
            continue;
          }
          final path = text.startsWith('__OH_STARTUP__\t')
              ? text.substring('__OH_STARTUP__\t'.length)
              : directory.isNotEmpty && text.endsWith('.plist')
              ? '$directory/$text'
              : null;
          if (path == null || !path.endsWith('.plist')) continue;
          final type = path.contains('/LaunchDaemons/')
              ? '系统守护进程'
              : path.startsWith('/Library/') || path.startsWith('/System/')
              ? '系统代理'
              : '用户代理';
          entries.add([path.split('/').last, type, path]);
        }
        return MachineMaintenanceReadout(['名称', '类型', '路径'], entries);
      }
      for (final line in lines) {
        final fields = line.trim().split(RegExp(r'\s+'));
        if (fields.length < 2 ||
            fields.first == 'UNIT' ||
            !RegExp(
              r'^(enabled|disabled|static|masked|indirect|generated|transient|alias|linked|enabled-runtime|masked-runtime|linked-runtime|Auto|Manual|Disabled|Automatic)$',
            ).hasMatch(fields[1])) {
          continue;
        }
        entries.add([
          fields[0],
          fields[1],
          fields.length > 2 ? fields[2] : '—',
        ]);
      }
      if (entries.isNotEmpty) {
        return MachineMaintenanceReadout(['名称', '启动方式', '预设'], entries);
      }
    }
    if (section == 'command') {
      final tokens = RegExp(
        r'''(?:[^\s"']+|"[^"]*"|'[^']*')+|\S+''',
      ).allMatches(output.trim()).map((match) => match[0]!).toList();
      return MachineMaintenanceReadout(
        ['名称', '数值'],
        [
          ['可执行文件与工作目录', tokens.first],
          for (var i = 1; i < tokens.length; i++) ['选项', tokens[i]],
        ],
        fields: true,
      );
    }
    final rows = <List<String>>[];
    if (section == 'sockets') {
      final macProcesses = lines.any((line) => line.contains('process:pid'));
      String socketProcess(String details) {
        final processes = RegExp(
          r'"([^"]+)",pid=(\d+),fd=(\d+)',
        ).allMatches(details).toList();
        if (processes.isNotEmpty) {
          return processes
              .map((m) => '${m[1]} · PID ${m[2]} · FD ${m[3]}')
              .join(' / ');
        }
        return '—';
      }

      for (final line in lines) {
        final values = line.trim().split(RegExp(r'\s+'));
        if (values.length >= 5 &&
            RegExp(
              r'^(?:ESTAB|LISTEN|UNCONN|SYN-SENT|SYN-RECV|FIN-WAIT-[12]|TIME-WAIT|CLOSE-WAIT|LAST-ACK|CLOSING|CLOSED)$',
            ).hasMatch(values.first)) {
          rows.add([
            'TCP',
            values[3],
            values[4],
            values[0],
            values[1],
            values[2],
            socketProcess(values.skip(5).join(' ')),
          ]);
          continue;
        }
        if (values.length < 4 ||
            !RegExp(
              r'^(tcp|udp)(?:4|6|46)?$',
              caseSensitive: false,
            ).hasMatch(values.first)) {
          continue;
        }
        final protocol = values.first.toUpperCase();
        if (values[1].contains(':')) {
          rows.add([
            protocol,
            values[1],
            values[2],
            protocol == 'TCP' && values.length > 4 ? values[3] : '—',
            '—',
            '—',
            values.last,
          ]);
        } else if (int.tryParse(values[1]) != null && values.length >= 5) {
          var process = values.last.contains('/') ? values.last : '—';
          if (macProcesses) {
            final details = values
                .skip(protocol.startsWith('TCP') ? 10 : 9)
                .toList();
            final end = details.indexWhere(
              (value) => RegExp(r':\d+$').hasMatch(value),
            );
            if (end >= 0) process = details.take(end + 1).join(' ');
          }
          rows.add([
            protocol,
            values[3],
            values[4],
            protocol.startsWith('TCP') && values.length > 5 ? values[5] : '—',
            values[1],
            values[2],
            process,
          ]);
        } else if (values.length >= 6) {
          rows.add([
            protocol,
            values[4],
            values[5],
            values[1],
            values[2],
            values[3],
            socketProcess(values.skip(6).join(' ')),
          ]);
        }
      }
      final unix = <List<String>>[];
      var unixHeaders = <String>[];
      for (final line in lines) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.first == 'Address' && parts.contains('Type')) {
          unixHeaders = parts;
          continue;
        }
        if (unixHeaders.isEmpty ||
            parts.length < 4 ||
            !RegExp(r'^[\da-fA-F]+$').hasMatch(parts.first)) {
          continue;
        }
        unix.add([
          for (var i = 0; i < unixHeaders.length; i++)
            i >= parts.length
                ? '—'
                : i == unixHeaders.length - 1
                ? parts.skip(i).join(' ')
                : parts[i],
        ]);
      }
      if (rows.isNotEmpty || unix.isNotEmpty) {
        return MachineMaintenanceReadout(
          ['协议', '本地地址', '远端地址', '状态', '接收队列', '发送队列', '进程'],
          rows,
          groups: {
            if (unix.isNotEmpty)
              '本地 UNIX 套接字': MachineMaintenanceReadout(unixHeaders, unix),
          },
        );
      }
      return const MachineMaintenanceReadout([], []);
    }
    if (section == 'users' &&
        !lines.any((line) => RegExp(r'LogonId\s*[:=]').hasMatch(line))) {
      final who = RegExp(r'^(\S+)\s+(\S+)\s+(.+?)(?:\s+\((.*)\))?$');
      for (final line in lines) {
        final m = who.firstMatch(line.trim());
        if (m == null) {
          rows.add(['—', '—', '—', line.trim()]);
        } else {
          rows.add([m[1]!, m[2]!, m[3]!, m[4] ?? '—']);
        }
      }
      return MachineMaintenanceReadout(['用户', '终端', '登录时间', '来源'], rows);
    }
    if (section == 'dns') {
      var group = '';
      for (final line in lines) {
        final value = line.trim();
        if (value.startsWith('#') || value == 'DNS configuration') continue;
        if (value.startsWith('resolver #')) {
          group = value;
          continue;
        }
        final m =
            RegExp(
              r'^(nameserver|search|domain|options)\s+(.+)$',
            ).firstMatch(value) ??
            RegExp(r'^([^:=]+?)\s*[:=]\s+(.*)$').firstMatch(value);
        if (m != null) {
          rows.add([group, m[1]!.trim(), m[2]!.trim()]);
        } else if (value.endsWith(':')) {
          group = value.substring(0, value.length - 1);
        } else if (RegExp(r'^[a-fA-F0-9:.%]+$').hasMatch(value) &&
            rows.isNotEmpty) {
          rows.add([group, rows.last[1], value]);
        } else {
          rows.add([group, '描述', value]);
        }
      }
      return MachineMaintenanceReadout(['范围', '名称', '地址'], rows);
    }
    if (section == 'paths' ||
        (section == 'descriptors' &&
            lines.any((line) => line.contains(' -> ')))) {
      for (final line in lines) {
        if (RegExp(r'^total\s+\d+$').hasMatch(line.trim())) continue;
        final m = RegExp(
          r'^(\S+)\s+\d+\s+(\S+)\s+(\S+)\s+\d+\s+\S+\s+\S+\s+\S+\s+(.+?)\s+->\s+(.*)$',
        ).firstMatch(line.trim());
        rows.add(
          m == null
              ? ['—', line.trim(), '—', '—']
              : [m[4]!, m[5]!, m[2]!, m[1]!],
        );
      }
      return MachineMaintenanceReadout(['路径', '目标', '用户', '权限'], rows);
    }
    if (section == 'cgroup') {
      for (final line in lines) {
        final m = RegExp(r'^(\d+):([^:]*):(.*)$').firstMatch(line.trim());
        rows.add(
          m == null
              ? ['—', '—', line.trim()]
              : [m[1]!, m[2]!.isEmpty ? '—' : m[2]!, m[3]!],
        );
      }
      return MachineMaintenanceReadout(['ID', '控制组', '路径'], rows);
    }
    if (section == 'cron') {
      for (final line in lines) {
        if (line.trim().startsWith('#')) continue;
        final m =
            RegExp(r'^((?:\S+\s+){4}\S+)\s+(.+)$').firstMatch(line.trim()) ??
            RegExp(r'^(@\S+)\s+(.+)$').firstMatch(line.trim());
        rows.add(m == null ? ['—', line.trim()] : [m[1]!, m[2]!]);
      }
      return MachineMaintenanceReadout(['计划', '启动命令'], rows);
    }
    if (section == 'logs') {
      for (final line in lines) {
        final m = RegExp(
          r'^(\d{4}-\d{2}-\d{2}[T ][^ ]+|[A-Z][a-z]{2}\s+\d+\s+\d+:\d+:\d+|\[\s*[\d.]+\])\s+(.*)$',
        ).firstMatch(line.trim());
        rows.add(m == null ? ['—', line.trim()] : [m[1]!, m[2]!]);
      }
      return MachineMaintenanceReadout(['时间', '消息'], rows);
    }
    if (section == 'routes') {
      if (lines.any(
        (line) =>
            line.contains('IPv4 Route Table') ||
            line.contains('IPv6 Route Table') ||
            line.contains('网络目标'),
      )) {
        return _machineWindowsRouteReadout(lines);
      }
      final bsd = lines.any(
        (line) =>
            RegExp(r'^Destination\s+Gateway\s+Flags').hasMatch(line.trim()),
      );
      if (bsd) {
        var family = 'IPv4';
        var headers = <String>[];
        for (final line in lines) {
          final parts = line.trim().split(RegExp(r'\s+'));
          if (line.trim() == 'Internet6:') family = 'IPv6';
          if (line.trim() == 'Internet:') family = 'IPv4';
          if (parts.first == 'Destination') {
            headers = parts;
            continue;
          }
          if (headers.isEmpty ||
              parts.length < 4 ||
              !RegExp('^(?:default|[0-9a-fA-F:.%/]+)').hasMatch(parts.first)) {
            continue;
          }
          String column(String key) {
            final index = headers.indexOf(key);
            return index < 0 || index >= parts.length ? '—' : parts[index];
          }

          rows.add([
            family,
            parts[0],
            parts[1],
            column('Netif') == '—' ? column('Iface') : column('Netif'),
            column('Flags'),
            column('Expire'),
          ]);
        }
        return MachineMaintenanceReadout([
          '地址族',
          '目的地址',
          '网关',
          '网卡',
          '标志',
          '过期时间',
        ], rows);
      }
      for (final line in lines) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length >= 8 &&
            RegExp(r'^\d+\.').hasMatch(parts.first) &&
            RegExp(r'^\d+\.').hasMatch(parts[2])) {
          rows.add([
            parts[0],
            parts[1],
            parts.last,
            '—',
            '—',
            '—',
            '—',
            parts[3],
            '子网掩码 ${parts[2]}',
          ]);
          continue;
        }
        const types = {
          'local',
          'broadcast',
          'unreachable',
          'blackhole',
          'prohibit',
          'throw',
          'multicast',
          'unicast',
        };
        final destination = types.contains(parts.first) && parts.length > 1
            ? parts[1]
            : parts.first;
        if (!RegExp(
          r'^(?:default|[0-9a-fA-F:.]+(?:/\d+)?)$',
        ).hasMatch(destination)) {
          continue;
        }
        // 过滤不同平台的表头，未知列结构交由格式提示处理。
        if (!parts.contains('dev') &&
            !parts.contains('via') &&
            !types.contains(parts.first)) {
          continue;
        }
        String after(String name) {
          final index = parts.indexOf(name);
          return index < 0 || index + 1 >= parts.length
              ? '—'
              : parts[index + 1];
        }

        rows.add([
          destination,
          after('via'),
          after('dev'),
          after('src'),
          after('table'),
          after('metric'),
          after('proto'),
          types.contains(parts.first) ? parts.first : 'unicast',
          parts.skip(1).join(' '),
        ]);
      }
      if (rows.isEmpty) {
        return const MachineMaintenanceReadout([], [], raw: true);
      }
      return MachineMaintenanceReadout([
        '目的地址',
        '网关',
        '网卡',
        '来源',
        '路由表',
        '跃点成本',
        '协议',
        '类型',
        '详情',
      ], rows);
    }
    if (section == 'status' &&
        lines.first.contains('PID') &&
        (lines.first.contains('COMMAND') || lines.first.contains('NAME'))) {
      final headers = lines.first.trim().split(RegExp(r'\s+'));
      for (final line in lines.skip(1)) {
        final values = line.trim().split(RegExp(r'\s+'));
        var cursor = 0;
        final cells = <String>[];
        for (var i = 0; i < headers.length; i++) {
          final count = i == headers.length - 1
              ? values.length - cursor
              : headers[i] == 'STARTED'
              ? 5
              : 1;
          final end = (cursor + count).clamp(cursor, values.length);
          cells.add(values.sublist(cursor, end).join(' '));
          cursor = end;
        }
        rows.add(cells);
      }
      if (section == 'status' && rows.length == 1) {
        return MachineMaintenanceReadout(
          ['名称', '数值'],
          [
            for (var i = 0; i < headers.length; i++)
              [headers[i], rows.single[i]],
          ],
          fields: true,
        );
      }
      return MachineMaintenanceReadout(headers, rows);
    }
    // 固定列输出按照表头的实际列位置切分，保留含空格的命令、时间和空列。
    final heading = lines.first;
    final columns = RegExp(
      r'\S(?:.*?\S)?(?=\s{2,}|$)',
    ).allMatches(heading).toList();
    if (columns.length > 1 &&
        !heading.contains('=') &&
        (section == 'containers' ||
            const [
              'limits',
              'descriptors',
              'filesystems',
              'startup',
              'timers',
            ].contains(section))) {
      for (final line in lines.skip(1)) {
        rows.add([
          for (var i = 0; i < columns.length; i++)
            columns[i].start >= line.length
                ? ''
                : line
                      .substring(
                        columns[i].start,
                        i + 1 == columns.length ||
                                columns[i + 1].start > line.length
                            ? line.length
                            : columns[i + 1].start,
                      )
                      .trim(),
        ]);
      }
      final headers = columns.map((m) => m[0]!).toList();
      if (section == 'limits') {
        return MachineMaintenanceReadout(
          ['名称', '数值'],
          [
            for (final row in rows)
              [
                row.first,
                [
                  for (var i = 1; i < headers.length; i++)
                    '${headers[i]}: ${row[i]}',
                ].join('\n'),
              ],
          ],
          fields: true,
        );
      }
      return MachineMaintenanceReadout(headers, rows);
    }
    final fields = <List<String>>[];
    final property = RegExp(
      r'^\s*(?:"([^"\n]+)"|([A-Za-z_][\w.() /%-]*?))\s*[:=]\s*(.*)$',
    );
    var unparsed = 0;
    var depth = 0;
    var quoted = false;
    var escaped = false;
    // 多行配置作为完整字段保留；引号中的括号不参与层级计算。
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final text = line.trim();
      if (depth == 0 &&
          ((index == 0 && text == '{') ||
              (index == lines.length - 1 && (text == '}' || text == '};')))) {
        continue;
      }
      if (depth == 0 &&
          fields.isNotEmpty &&
          fields.last[1].isEmpty &&
          RegExp(r'^[{(\[]').hasMatch(text)) {
        fields.last[1] = line;
      } else if (depth > 0) {
        fields.last[1] += '\n$line';
      } else {
        final match = property.firstMatch(line);
        if (match != null) {
          fields.add([(match[1] ?? match[2]!).trim(), match[3]!.trim()]);
        } else if (lines.length == 1) {
          fields.add(['说明', text]);
        } else if (section == 'system' && text.startsWith('Darwin ')) {
          final parts = text.split(RegExp(r'\s+'));
          if (parts.length >= 3) {
            fields.addAll([
              ['内核', parts[0]],
              ['主机名', parts[1]],
              ['内核版本', parts[2]],
            ]);
          }
        } else {
          unparsed++;
          continue;
        }
      }
      final value = depth > 0 ? line : fields.last[1];
      // 只追踪字段以容器开头的值，避免普通报告中的括号影响后续字段。
      if (depth == 0 && !RegExp(r'^[{(\[]').hasMatch(value.trimLeft())) {
        continue;
      }
      for (final rune in value.runes) {
        if (escaped) {
          escaped = false;
        } else if (rune == 92 && quoted) {
          escaped = true;
        } else if (rune == 34) {
          quoted = !quoted;
        } else if (!quoted) {
          if (rune == 123 || rune == 40 || rune == 91) depth++;
          if (rune == 125 || rune == 41 || rune == 93) {
            if (depth > 0) depth--;
          }
        }
      }
    }
    final structured = <List<String>>[];
    for (final field in fields) {
      if (RegExp(r'^[{(\[]').hasMatch(field[1].trimLeft())) {
        final parsed = _machinePropertyValue(field[1]);
        final report = _machineJsonReadout({field[0]: parsed});
        structured.addAll(report.rows);
        for (final group in report.groups.entries) {
          structured.addAll(
            group.value.rows.map((row) => ['${field[0]} / ${row[0]}', row[1]]),
          );
        }
      } else {
        structured.add([
          field[0],
          field[1]
              .replaceFirst(RegExp(r';$'), '')
              .replaceAllMapped(RegExp(r'^"([\s\S]*)"$'), (m) => m[1]!),
        ]);
      }
    }
    if (unparsed > 0 && structured.isNotEmpty) {
      structured.add(['解析状态', '已展示可识别字段，另有 $unparsed 行尚未匹配当前格式']);
    }
    return MachineMaintenanceReadout(
      ['名称', '数值'],
      structured,
      fields: true,
      issue: structured.isEmpty ? 'format' : null,
    );
  }
  final List<String> headers;
  final List<List<String>> rows;
  final bool fields;
  final bool raw;
  final String? issue;
  final Map<String, MachineMaintenanceReadout> groups;
}

/// 解析 launchd 与 systemd 的嵌套属性，保留字段路径和数组顺序。
dynamic _machinePropertyValue(String text) {
  final tokens =
      RegExp(r'"(?:\\.|[^"\\])*"|=>|[{}()[\];,=\n]|[^"{}()[\];,=\n]+')
          .allMatches(text)
          .map((m) => m[0]!.trim())
          .where((v) => v.isNotEmpty)
          .toList();
  var cursor = 0;
  dynamic read(int depth) {
    if (cursor >= tokens.length) return null;
    final token = tokens[cursor++];
    if (depth > _machineReadoutDepthLimit) return null;
    if (const ['{', '(', '['].contains(token)) {
      final close = token == '{'
          ? '}'
          : token == '('
          ? ')'
          : ']';
      final fields = <String, dynamic>{};
      final values = <dynamic>[];
      while (cursor < tokens.length && tokens[cursor] != close) {
        if (const [';', ','].contains(tokens[cursor])) {
          cursor++;
          continue;
        }
        var key = read(depth + 1);
        if (cursor + 2 < tokens.length &&
            tokens[cursor] == '[' &&
            tokens[cursor + 1] == ']' &&
            tokens[cursor + 2] == '=') {
          key = '$key[]';
          cursor += 2;
        }
        if (cursor < tokens.length &&
            const ['=', '=>'].contains(tokens[cursor])) {
          cursor++;
          fields['$key'] = read(depth + 1);
        } else {
          values.add(key);
        }
      }
      if (cursor < tokens.length) cursor++;
      if (fields.isEmpty) return values;
      if (values.isNotEmpty) fields['条目'] = values;
      return fields;
    }
    if (token.startsWith('"') && token.endsWith('"')) {
      try {
        return jsonDecode(token);
      } on FormatException {
        return token.substring(1, token.length - 1);
      }
    }
    return token;
  }

  return read(0);
}

MachineMaintenanceReadout _machineMemoryReadout(List<String> lines) {
  final fields = <List<String>>[];
  final groups = <String, MachineMaintenanceReadout>{};
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.contains('REGION TYPE') || line.startsWith('MALLOC ZONE')) {
      final columns = line.split(RegExp(r'\s{2,}'));
      if (columns.length == 1) {
        final rows = <List<String>>[];
        while (i + 1 < lines.length) {
          final match = RegExp(
            r'^(.+?)\s+([\d.]+[KMGT]?)(?:\s+(.*))?$',
          ).firstMatch(lines[i + 1].trim());
          if (match == null) break;
          i++;
          rows.add([match[1]!, match[2]!, match[3] ?? '—']);
        }
        groups['内存区域'] = MachineMaintenanceReadout(['区域类型', '大小', '详情'], rows);
        continue;
      }
      final previous = i > 0
          ? lines[i - 1].trim().split(RegExp(r'\s+'))
          : <String>[];
      var prefix = 0;
      final headers = <String>[
        columns.first == 'REGION TYPE' ? '区域类型' : '分配区',
        for (var c = 1; c < columns.length; c++)
          columns[c].contains('%')
              ? '碎片率'
              : prefix < previous.length
              ? '${previous[prefix++]} ${columns[c]}'
              : columns[c],
      ];
      final rows = <List<String>>[];
      var annotation = false;
      while (i + 1 < lines.length) {
        final row = lines[i + 1].trim();
        if (RegExp(r'^[=\-\s]+$').hasMatch(row)) {
          i++;
          continue;
        }
        final cells = row.split(RegExp(r'\s{2,}'));
        if (cells.length < 2 ||
            !RegExp(r'^[\d.]+[KMGT%]?$').hasMatch(cells[1])) {
          break;
        }
        i++;
        if (!annotation && cells.length > headers.length) {
          annotation = true;
          headers.add('说明');
          for (final old in rows) {
            old.add('—');
          }
        }
        rows.add([
          for (var c = 0; c < headers.length; c++)
            c >= cells.length
                ? '—'
                : annotation && c == headers.length - 1
                ? cells.skip(c).join(' · ')
                : cells[c],
        ]);
      }
      groups[line.startsWith('MALLOC ZONE') ? '内存分配区' : '内存区域'] =
          MachineMaintenanceReadout(headers, rows);
    } else {
      final pair = RegExp(r'^([^:]+):\s*(.+)$').firstMatch(line);
      if (pair != null) {
        final metrics = RegExp(
          r'([\w_]+)=([^\s]+)',
        ).allMatches(pair[2]!).toList();
        if (metrics.isNotEmpty) {
          fields.addAll(metrics.map((m) => ['${pair[1]} / ${m[1]}', m[2]!]));
        } else {
          fields.add([pair[1]!, pair[2]!]);
        }
      }
    }
  }
  return MachineMaintenanceReadout(
    ['名称', '数值'],
    fields,
    fields: true,
    groups: groups,
  );
}

MachineMaintenanceReadout _machineJsonReadout(dynamic value) {
  final groups = <String, MachineMaintenanceReadout>{};
  final fields = <List<String>>[];
  var count = 0;
  var limited = false;
  void collect(dynamic item, String path, List<List<String>> rows, int depth) {
    if (depth > _machineReadoutDepthLimit ||
        count >= _machineReadoutFieldLimit) {
      limited = true;
      return;
    }
    if (item is Map) {
      for (final entry in item.entries) {
        collect(
          entry.value,
          path.isEmpty ? '${entry.key}' : '$path / ${entry.key}',
          rows,
          depth + 1,
        );
      }
    } else if (item is List) {
      if (item.every((e) => e is! Map && e is! List)) {
        rows.add([path, item.map((e) => e?.toString() ?? '—').join(' · ')]);
        count++;
      } else {
        for (var i = 0; i < item.length; i++) {
          collect(item[i], '$path [${i + 1}]', rows, depth + 1);
        }
      }
    } else {
      rows.add([path.isEmpty ? '数值' : path, item?.toString() ?? '—']);
      count++;
    }
  }

  if (value is Map) {
    for (final entry in value.entries) {
      if (entry.value is Map ||
          (entry.value is List &&
              (entry.value as List).any((e) => e is Map || e is List))) {
        final rows = <List<String>>[];
        collect(entry.value, '', rows, 0);
        groups['${entry.key}'] = MachineMaintenanceReadout(
          ['名称', '数值'],
          rows,
          fields: true,
        );
      } else {
        collect(entry.value, '${entry.key}', fields, 0);
      }
    }
  } else if (value is List) {
    for (
      var i = 0;
      i < value.length && count < _machineReadoutFieldLimit;
      i++
    ) {
      final rows = <List<String>>[];
      collect(value[i], '', rows, 0);
      final item = value[i];
      final name = item is Map
          ? item['Name'] ??
                item['name'] ??
                item['ID'] ??
                item['Id'] ??
                item['id']
          : null;
      groups['${i + 1} · ${name ?? "记录"}'] = MachineMaintenanceReadout(
        ['名称', '数值'],
        rows,
        fields: true,
      );
    }
    if (groups.length < value.length) limited = true;
  } else {
    collect(value, '', fields, 0);
  }
  if (limited) {
    fields.add([
      '解析状态',
      '报告过大或层级过深，已展示可解析字段（上限 $_machineReadoutFieldLimit 个）；请缩小采集范围。',
    ]);
  }
  return MachineMaintenanceReadout(
    ['名称', '数值'],
    fields,
    fields: true,
    groups: groups,
  );
}

MachineMaintenanceReadout _machineColumnReadout(List<String> lines) {
  final useful = lines
      .where(
        (line) =>
            !line.trim().startsWith('__GPU_') &&
            !RegExp(r'^[+\-=\s]+$').hasMatch(line),
      )
      .toList();
  final header = useful.indexWhere(
    (line) =>
        line.contains('CPU') ||
        line.contains('GPU') ||
        line.trim().startsWith('#Entity') ||
        line.contains('MEMORY'),
  );
  if (header < 0) {
    return const MachineMaintenanceReadout([], [], issue: 'format');
  }
  final title = useful[header].trim().replaceFirst(RegExp(r'^#\s*'), '');
  final headings = title.split(RegExp(r'\s{2,}|\t'));
  final headers = headings.length > 1 ? headings : title.split(RegExp(r'\s+'));
  final rows = <List<String>>[];
  for (final line in useful.skip(header + 1)) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < headers.length) continue;
    rows.add([
      for (var i = 0; i < headers.length; i++)
        i == headers.length - 1 ? parts.skip(i).join(' ') : parts[i],
    ]);
  }
  return MachineMaintenanceReadout(headers, rows);
}

MachineMaintenanceReadout _machineGpuReadout(List<String> lines) {
  final issue = machineMaintenanceCollectionIssue(lines.join('\n'), 'gpu');
  if (issue != null) return MachineMaintenanceReadout([], [], issue: issue);
  if (lines.any((line) => line.contains('__GPU_PROBE_EXIT_'))) {
    return const MachineMaintenanceReadout([], [], issue: 'unavailable');
  }
  final devices = <List<String>>[];
  for (final line in lines) {
    final match = RegExp(
      r'^\s*(GPU|MIG)\s+([^:]+):?\s*(.*?)\s*\(UUID:\s*([^)]+)\)',
    ).firstMatch(line);
    if (match != null) {
      devices.add([match[1]!, match[2]!.trim(), match[3]!.trim(), match[4]!]);
    }
  }
  if (devices.isNotEmpty) {
    return MachineMaintenanceReadout(['类型', '编号 / 配置', '名称', 'UUID'], devices);
  }
  final topology = lines.indexWhere((line) => line.contains('CPU Affinity'));
  if (topology >= 0) {
    final headers = RegExp(
      r'GPU\d+|NIC\d+|CPU Affinity|NUMA Affinity|GPU NUMA ID',
    ).allMatches(lines[topology]).map((m) => m[0]!).toList();
    final rows = <List<String>>[];
    for (final line in lines.skip(topology + 1)) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (!RegExp(r'^(GPU|NIC)\d+$').hasMatch(parts.first)) continue;
      rows.add([
        for (var i = 0; i <= headers.length; i++)
          i < parts.length ? parts[i] : '—',
      ]);
    }
    return MachineMaintenanceReadout(['设备', ...headers], rows);
  }
  final entity = lines.indexWhere(
    (line) => RegExp(r'^#\s*Entity\b').hasMatch(line),
  );
  if (entity >= 0) {
    final headers = lines[entity]
        .replaceFirst(RegExp(r'^#\s*Entity\s*'), '')
        .trim()
        .split(RegExp(r'\s+'));
    final rows = <List<String>>[];
    for (final line in lines.skip(entity + 1)) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 2 ||
          !const ['GPU', 'CPU', 'GI', 'CI', 'SWITCH'].contains(parts.first)) {
        continue;
      }
      rows.add([
        for (var i = 0; i < headers.length + 2; i++)
          i < parts.length ? parts[i] : '—',
      ]);
    }
    return MachineMaintenanceReadout(['实体类型', '实体 ID', ...headers], rows);
  }
  final pipe = lines
      .where((line) => line.trim().startsWith('|'))
      .map((line) => line.trim().split('|').skip(1).toList()..removeLast())
      .toList();
  if (pipe.isNotEmpty) {
    return MachineMaintenanceReadout(
      ['名称', '数值'],
      [
        for (final row in pipe)
          if (row.length >= 2 && row[1].trim().isNotEmpty)
            [row[0].trim(), row.skip(1).map((c) => c.trim()).join(' · ')],
      ],
      fields: true,
    );
  }
  final columns = _machineColumnReadout(lines);
  if (columns.issue == null && columns.rows.isNotEmpty) return columns;
  final fields = [
    for (final line in lines)
      if (RegExp(r'^([^:]+):\s*(.+)$').firstMatch(line) case final match?)
        [match[1]!, match[2]!],
  ];
  return MachineMaintenanceReadout(
    ['名称', '数值'],
    fields,
    fields: true,
    issue: fields.isEmpty ? 'format' : null,
  );
}
