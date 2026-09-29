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
  final first = output.trimLeft().split('\n').first.trim();
  final failure = RegExp(
    r'^(?:failed to connect|cannot connect|error during connect|error response from daemon|permission denied|operation not permitted|access is denied|access denied|could not|unable to connect|connection refused|connection timed out|context deadline exceeded|查询超时|未安装|缺少|权限不足|无法连接|(?:docker|podman|cat|ls|sh|bash|zsh|sudo|systemctl|launchctl|journalctl|netstat|pfctl|nft|iptables)(?::|\s+error).*?(?:error|failed|cannot|could not|unable|denied|not permitted|not found|no such file|refused|timed out))',
    caseSensitive: false,
  );
  if (!failure.hasMatch(first)) return null;
  if (RegExp(
    'permission denied|not permitted|access.*denied|权限不足|拒绝访问',
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

/// 命令展示模型保留字段顺序、重复字段和完整值，不执行或改写采样内容。
class MachineMaintenanceReadout {
  const MachineMaintenanceReadout(
    this.headers,
    this.rows, {
    this.fields = false,
    this.issue,
    this.raw = false,
  });

  factory MachineMaintenanceReadout.parse(String output, String section) {
    if (machineMaintenanceNetworkReports.contains(section)) {
      return const MachineMaintenanceReadout([], [], raw: true);
    }
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
      for (final line in lines) {
        final values = line.trim().split(RegExp(r'\s+'));
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
            values.length > 6 ? values.skip(6).join(' ') : '—',
          ]);
        }
      }
      if (rows.isNotEmpty) {
        return MachineMaintenanceReadout([
          '协议',
          '本地地址',
          '远端地址',
          '状态',
          '接收队列',
          '发送队列',
          '进程',
        ], rows);
      }
      return const MachineMaintenanceReadout([], [], raw: true);
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
        // Windows 与旧版 netstat 输出使用不同列结构，保留完整报告。
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
        } else if (fields.isNotEmpty && fields.last[0] == '描述') {
          fields.last[1] += '\n$line';
        } else {
          fields.add(['描述', line]);
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
    return MachineMaintenanceReadout(['名称', '数值'], fields, fields: true);
  }
  final List<String> headers;
  final List<List<String>> rows;
  final bool fields;
  final bool raw;
  final String? issue;
}
