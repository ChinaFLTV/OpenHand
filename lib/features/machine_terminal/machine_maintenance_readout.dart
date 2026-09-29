/// 命令展示模型保留字段顺序、重复字段和完整值，不执行或改写采样内容。
class MachineMaintenanceReadout {
  const MachineMaintenanceReadout(
    this.headers,
    this.rows, {
    this.fields = false,
  });

  factory MachineMaintenanceReadout.parse(String output, String section) {
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
          ]);
        } else if (int.tryParse(values[1]) != null && values.length >= 5) {
          rows.add([
            protocol,
            values[3],
            values[4],
            protocol.startsWith('TCP') && values.length > 5 ? values[5] : '—',
          ]);
        } else if (values.length >= 6) {
          rows.add([protocol, values[4], values[5], values[1]]);
        }
      }
      if (rows.isNotEmpty) {
        return MachineMaintenanceReadout(['协议', '本地地址', '远端地址', '状态'], rows);
      }
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
    if (section == 'routes' &&
        lines.any(
          (line) =>
              RegExp(r'^(default|[0-9a-fA-F.:]+/\d+)\s').hasMatch(line.trim()),
        )) {
      for (final line in lines) {
        final parts = line.trim().split(RegExp(r'\s+'));
        String after(String name) {
          final index = parts.indexOf(name);
          return index < 0 || index + 1 >= parts.length
              ? '—'
              : parts[index + 1];
        }

        rows.add([
          RegExp(r'^(default|[0-9a-fA-F.:]+/\d+)$').hasMatch(parts.first)
              ? parts.first
              : '—',
          after('via'),
          after('dev'),
          after('src'),
          parts.skip(1).join(' '),
        ]);
      }
      return MachineMaintenanceReadout(['目的地址', '网关', '网卡', '来源', '描述'], rows);
    }
    if ((section == 'status' || section == 'descriptors') &&
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
      return MachineMaintenanceReadout(
        columns.map((m) => m[0]!).toList(),
        rows,
      );
    }
    final fields = <List<String>>[];
    for (final line in lines) {
      final m = RegExp(
        r'^\s*([A-Za-z_][\w.() /-]*?)\s*[:=]\s*(.*)$',
      ).firstMatch(line);
      if (m != null) {
        fields.add([m[1]!.trim(), m[2]!.trim().isEmpty ? '—' : m[2]!.trim()]);
      } else if (line.trim().endsWith('{')) {
        fields.add(['范围', line.trim()]);
      } else if (line.trim() != '}' && line.trim() != '};') {
        fields.add(['描述', line.trim()]);
      }
    }
    return MachineMaintenanceReadout(['名称', '数值'], fields, fields: true);
  }
  final List<String> headers;
  final List<List<String>> rows;
  final bool fields;
}
