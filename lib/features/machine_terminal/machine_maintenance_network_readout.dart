part of 'machine_maintenance_readout.dart';

MachineMaintenanceReadout _parseMachineNetworkReadout(
  List<String> lines,
  String section,
) {
  return switch (section) {
    'addresses' || 'interfaces' => _machineAddressReadout(lines),
    'neighbors' => _machineNeighborReadout(lines),
    'listeners' => _machineListenerReadout(lines),
    'proxy' => _machineProxyReadout(lines),
    'firewall_status' => _machineFirewallStatusReadout(lines),
    'network_stats' || 'firewall_states' => _machineCounterReadout(lines),
    'socket_details' => _machineSocketReadout(lines),
    'policy_routes' => _machinePolicyReadout(lines),
    'firewall' ||
    'firewall_rules' ||
    'firewall_nat' ||
    'firewall_ipvfour' ||
    'firewall_ipvsix' => _machineFirewallReadout(lines, section),
    _ => _machineConfigurationReadout(lines),
  };
}

MachineMaintenanceReadout _machineListenerReadout(List<String> lines) {
  final sockets = MachineMaintenanceReadout.parse(lines.join('\n'), 'sockets');
  final rows = sockets.rows.where((row) {
    if (row.length < 4) return false;
    final protocol = row[0].toUpperCase();
    final state = row[3].toUpperCase();
    if (protocol.startsWith('TCP')) {
      return state == 'LISTEN' || state == 'LISTENING';
    }
    final port = RegExp(r'[:.](\d+)$').firstMatch(row[1]);
    return protocol.startsWith('UDP') &&
        port != null &&
        int.parse(port[1]!) > 0;
  }).toList();
  return MachineMaintenanceReadout(sockets.headers, rows, issue: sockets.issue);
}

MachineMaintenanceReadout _machineProxyReadout(List<String> lines) {
  final groups = <String, List<List<String>>>{'终端环境': []};
  var scope = '终端环境';
  var arrayKey = '';
  void add(String source, String key, String value) {
    if (RegExp(
      'password|username|authentication-user',
      caseSensitive: false,
    ).hasMatch(key)) {
      return;
    }
    value = value
        .replaceAll(RegExp('[^/; ,]*@'), '***@')
        .replaceAll(RegExp(r'''[?#][^\s'"\]]*'''), '')
        .replaceAllMapped(RegExp(r"^'(.*)'$"), (match) => match[1]!);
    key =
        const {
          'HTTPEnable': 'HTTP / 代理状态',
          'HTTPProxy': 'HTTP / 代理地址',
          'HTTPPort': 'HTTP / 代理端口',
          'HTTPSEnable': 'HTTPS / 代理状态',
          'HTTPSProxy': 'HTTPS / 代理地址',
          'HTTPSPort': 'HTTPS / 代理端口',
          'SOCKSEnable': 'SOCKS / 代理状态',
          'SOCKSProxy': 'SOCKS / 代理地址',
          'SOCKSPort': 'SOCKS / 代理端口',
          'ProxyAutoConfigEnable': 'PAC 状态',
          'ProxyAutoConfigURLString': 'PAC 地址',
          'ProxyAutoDiscoveryEnable': '自动发现',
          'ExceptionsList': '绕过代理',
          'ExcludeSimpleHostnames': '绕过本地主机',
          'ProxyEnable': '代理状态',
          'ProxyServer': '代理服务器',
          'ProxyOverride': '绕过代理',
          'AutoConfigURL': 'PAC 地址',
          'Proxy Server(s)': '代理服务器',
          '代理服务器': '代理服务器',
          'Bypass List': '绕过代理',
          '绕过列表': '绕过代理',
          'mode': '代理模式',
          'autoconfig-url': 'PAC 地址',
          'ignore-hosts': '绕过代理',
          'http / enabled': 'HTTP / 代理状态',
          'http / host': 'HTTP / 代理地址',
          'http / port': 'HTTP / 代理端口',
          'https / host': 'HTTPS / 代理地址',
          'https / port': 'HTTPS / 代理端口',
          'socks / host': 'SOCKS / 代理地址',
          'socks / port': 'SOCKS / 代理端口',
          'http / use-authentication': '代理身份验证',
          'use-same-proxy': '共用代理',
          'ftp / host': 'FTP / 代理地址',
          'ftp / port': 'FTP / 代理端口',
        }[key] ??
        key;
    if (key.endsWith('状态') ||
        const ['自动发现', '绕过本地主机', '代理身份验证', '共用代理'].contains(key)) {
      value =
          const {'1': '启用', '0': '禁用', 'true': '启用', 'false': '禁用'}[value] ??
          value;
    }
    if (key == '代理模式') {
      value =
          const {'none': '直接连接', 'manual': '手动配置', 'auto': '自动配置'}[value] ??
          value;
    }
    (groups[source] ??= []).add([key, value.isEmpty ? '—' : value]);
  }

  for (final original in lines) {
    final line = original.trim();
    if (line.startsWith('__OH_PROXY_SCOPE__\t')) {
      scope = line.split('\t').skip(1).join(' ');
      groups.putIfAbsent(scope, () => []);
      continue;
    }
    if (line.startsWith('__OH_PROXY__\t')) {
      final fields = line.split('\t');
      if (fields.length >= 4) {
        add(fields[1], fields[2], fields.skip(3).join(' '));
      }
      continue;
    }
    if (line == '{' || line == '}' || line == ')' || line == '(') continue;
    if (line.endsWith(' : <array> {')) {
      arrayKey = line.substring(0, line.indexOf(' :')).trim();
      continue;
    }
    final arrayEntry = RegExp(r'^\d+\s*:\s*(.+)$').firstMatch(line);
    if (arrayEntry != null && arrayKey.isNotEmpty) {
      add(scope, arrayKey, arrayEntry[1]!);
      continue;
    }
    final gnome = RegExp(
      r'^org\.gnome\.system\.proxy(?:\.([\w-]+))?\s+([\w-]+)\s+(.+)$',
    ).firstMatch(line);
    if (gnome != null) {
      final key = [if (gnome[1] != null) gnome[1]!, gnome[2]!].join(' / ');
      add(scope, key, gnome[3]!);
      continue;
    }
    final field = RegExp(
      r'^(.+?)\s*(?:\s+:\s*|:\s+|\s{2,})(.+)$',
    ).firstMatch(line);
    if (field != null) {
      add(scope, field[1]!.trim(), field[2]!.trim());
    } else if (line.contains('Direct access') || line.contains('直接访问')) {
      (groups[scope] ??= []).add(['代理模式', '直接连接']);
    } else if (line.startsWith('缺少') ||
        line.startsWith('查询失败') ||
        line.toLowerCase().contains('error')) {
      (groups[scope] ??= []).add(['状态', line]);
    }
  }
  if (groups['终端环境']?.isEmpty ?? false) {
    groups.remove('终端环境');
  }
  return MachineMaintenanceReadout(
    [],
    [],
    groups: {
      for (final entry in groups.entries)
        entry.key: MachineMaintenanceReadout(
          ['名称', '数值'],
          entry.value.isEmpty
              ? [
                  ['状态', '当前范围未提供代理配置'],
                ]
              : entry.value,
          fields: true,
        ),
    },
  );
}

MachineMaintenanceReadout _machineFirewallStatusReadout(List<String> lines) {
  final normalized = <String>[];
  for (final original in lines) {
    final line = original.trim();
    if (line.startsWith('ERROR:') && line.contains('root')) {
      normalized.add('状态: 读取权限不足');
    } else if (line == 'running' || line == 'not running') {
      normalized.add('状态: ${line == 'running' ? '运行中' : '未运行'}');
    } else if (line.startsWith('Status:')) {
      normalized.add(
        '状态: ${line.endsWith('inactive')
            ? '禁用'
            : line.endsWith('active')
            ? '启用'
            : line.substring(7).trim()}',
      );
    } else if (!original.startsWith(' ') &&
        RegExp(r'^[\w-]+(?: \(active\))?$').hasMatch(line)) {
      normalized.add('$line:');
    } else {
      normalized.add(original);
    }
  }
  return _machineConfigurationReadout(normalized);
}

MachineMaintenanceReadout _machineSocketReadout(List<String> lines) {
  if (lines.any((line) => line.startsWith('COMMAND'))) {
    return _machineLsofReadout(lines);
  }
  final connections = MachineMaintenanceReadout.parse(
    lines.join('\n'),
    'sockets',
  );
  final groups = <String, MachineMaintenanceReadout>{};
  var name = '';
  for (final line in lines) {
    var metrics = line;
    final connection = RegExp(
      '^(?:tcp|udp|ESTAB|LISTEN|SYN-|FIN-|TIME-WAIT|CLOSE-WAIT)',
      caseSensitive: false,
    ).hasMatch(line.trimLeft());
    if (connection) {
      final parts = line.trim().split(RegExp(r'\s+'));
      final hasProtocol = RegExp('^(tcp|udp)').hasMatch(parts.first);
      name = parts.skip(hasProtocol ? 4 : 3).take(2).join(' → ');
      metrics = parts.skip(hasProtocol ? 6 : 5).join(' ');
    }
    if (name.isEmpty || (!connection && !line.startsWith(' '))) continue;
    final fields = [
      for (final match in RegExp(r'([\w.-]+):([^\s]+)').allMatches(metrics))
        if (!const {'users', 'skmem'}.contains(match[1]))
          [match[1]!, match[2]!],
    ];
    final memory = RegExp(r'skmem:\(([^)]+)\)').firstMatch(metrics);
    if (memory != null) {
      fields.addAll(
        RegExp(
          r'([a-z]+)(\d+)',
        ).allMatches(memory[1]!).map((m) => ['套接字内存 / ${m[1]}', m[2]!]),
      );
    }
    if (fields.isNotEmpty) {
      groups[name] = MachineMaintenanceReadout(
        ['指标', '数值'],
        [...?groups[name]?.rows, ...fields],
        fields: true,
      );
    }
  }
  if (groups.isEmpty) return connections;
  return MachineMaintenanceReadout(
    [],
    [],
    groups: {'连接': connections, ...groups},
  );
}

MachineMaintenanceReadout _machineWindowsRouteReadout(List<String> lines) {
  var family = 'IPv4';
  final rows = <List<String>>[];
  for (final line in lines) {
    if (line.contains('IPv6')) family = 'IPv6';
    if (line.contains('IPv4')) family = 'IPv4';
    final parts = line.trim().split(RegExp(r'\s+'));
    if (family == 'IPv4' &&
        parts.length == 5 &&
        RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(parts[0]) &&
        num.tryParse(parts[4]) != null) {
      rows.add([family, parts[0], parts[1], parts[2], parts[3], parts[4]]);
    } else if (family == 'IPv6' &&
        parts.length >= 4 &&
        int.tryParse(parts[0]) != null &&
        int.tryParse(parts[1]) != null &&
        parts[2].contains('/')) {
      rows.add([
        family,
        parts[2],
        '—',
        parts.skip(3).join(' '),
        parts[0],
        parts[1],
      ]);
    }
  }
  return MachineMaintenanceReadout([
    '地址族',
    '目的地址',
    '子网掩码',
    '网关',
    '网卡',
    '跃点成本',
  ], rows);
}

MachineMaintenanceReadout _machineAddressReadout(List<String> lines) {
  final interfaces = <String, Map<String, String>>{};
  var name = '主机配置';
  var previous = '';
  var counters = <String>[];
  var direction = '';
  void add(String key, String value) {
    if (key == '状态' || key == '链路状态') {
      value = switch (value.toLowerCase()) {
        'up' || 'active' => '已连接',
        'down' || 'inactive' => '未连接',
        _ => value,
      };
    }
    final fields = interfaces[name] ??= {};
    fields[key] = fields[key] == null || fields[key] == value
        ? value
        : '${fields[key]} · $value';
    previous = key;
  }

  for (final original in lines) {
    final line = original.trim();
    final tab = original.split('\t');
    if (tab.length == 6) {
      name = tab[0];
      for (var i = 0; i < tab.length; i++) {
        add(const ['网卡', '状态', 'MAC 地址', 'MTU', '地址', '默认网关'][i], tab[i]);
      }
      continue;
    }
    final singleAddress = RegExp(
      r'^\d+:\s+(\S+)\s+(inet6?)\s+(\S+)',
    ).firstMatch(line);
    if (singleAddress != null) {
      name = singleAddress[1]!.split('@').first;
      add(
        singleAddress[2] == 'inet' ? 'IPv4 地址' : 'IPv6 地址',
        singleAddress[3]!,
      );
      continue;
    }
    if (RegExp(r'^[\w.-]+$').hasMatch(line) && !original.startsWith(' ')) {
      name = line;
      add('网卡', name);
      continue;
    }
    final heading = RegExp(
      r'^(?:\d+:\s+)?([\w.@-]+):\s+(?:flags=\d+)?<([^>]*)>\s*(.*)$',
    ).firstMatch(line);
    if (heading != null) {
      name = heading[1]!;
      add('网卡', name);
      add('标志', heading[2]!.replaceAll(',', ' · '));
      final mtu = RegExp(r'\bmtu\s+(\d+)').firstMatch(heading[3]!);
      final state = RegExp(r'\bstate\s+(\S+)').firstMatch(heading[3]!);
      if (mtu != null) add('MTU', mtu[1]!);
      add(
        '状态',
        state?[1] ?? (heading[2]!.split(',').contains('UP') ? '启用' : '禁用'),
      );
      continue;
    }
    // Windows 适配器名可能带空格，点号仅作为字段的排版填充。
    if (!original.startsWith(' ') && line.endsWith(':')) {
      name = line.substring(0, line.length - 1);
      continue;
    }
    final address = RegExp(r'^(inet6?)\s+(\S+)(.*)$').firstMatch(line);
    if (address != null) {
      add(address[1] == 'inet' ? 'IPv4 地址' : 'IPv6 地址', address[2]!);
      for (final match in RegExp(
        r'\b(netmask|broadcast|prefixlen|scopeid|scope|valid_lft|preferred_lft)\s+(\S+)',
      ).allMatches(address[3]!)) {
        var value = match[2]!;
        if (match[1] == 'netmask' && value.startsWith('0x')) {
          final mask = int.tryParse(value.substring(2), radix: 16);
          if (mask != null && mask >= 0 && mask <= 0xffffffff) {
            value = [
              for (final shift in [24, 16, 8, 0]) (mask >> shift) & 255,
            ].join('.');
          }
        }
        add(
          const {
            'netmask': '子网掩码',
            'broadcast': '广播地址',
            'prefixlen': '前缀长度',
            'scopeid': '范围 ID',
            'scope': '地址范围',
            'valid_lft': '有效期',
            'preferred_lft': '首选有效期',
          }[match[1]]!,
          value,
        );
      }
      continue;
    }
    final mac = RegExp(r'^(?:ether|lladdr|link/\S+)\s+(\S+)').firstMatch(line);
    if (mac != null) {
      add('MAC 地址', mac[1]!);
      continue;
    }
    if (line.startsWith('RX:') || line.startsWith('TX:')) {
      direction = line.substring(0, 2) == 'RX' ? '接收' : '发送';
      counters = line.substring(3).trim().split(RegExp(r'\s+'));
      continue;
    }
    if (counters.isNotEmpty && RegExp(r'^\d+(?:\s+\d+)*$').hasMatch(line)) {
      final values = line.split(RegExp(r'\s+'));
      for (var i = 0; i < counters.length && i < values.length; i++) {
        add(
          '$direction · ${const {'bytes': '字节', 'packets': '包数', 'errors': '错误', 'dropped': '丢弃', 'missed': '遗漏', 'mcast': '组播'}[counters[i]] ?? counters[i]}',
          values[i],
        );
      }
      counters = [];
      continue;
    }
    final property = RegExp(r'^(.+?)\s*:\s+(.+)$').firstMatch(line);
    if (property != null) {
      final key = property[1]!.replaceAll(RegExp(r'[.\s]+$'), '').trim();
      final value = property[2]!;
      add(
        const {
              'status': '链路状态',
              'media': '介质',
              'options': '网卡选项',
              'nd6 options': 'IPv6 邻居选项',
              'address': 'MAC 地址',
              'operstate': '链路状态',
              'mtu': 'MTU',
              'speed': '速率 · Mb/s',
              'duplex': '双工模式',
              'Physical Address': 'MAC 地址',
              'IPv4 Address': 'IPv4 地址',
              'IPv6 Address': 'IPv6 地址',
              'Link-local IPv6 Address': '链路本地 IPv6',
              'Subnet Mask': '子网掩码',
              'Default Gateway': '默认网关',
              'DNS Servers': 'DNS 服务器',
              'DHCP Enabled': 'DHCP',
              'DHCP Server': 'DHCP 服务器',
            }[key] ??
            key,
        key == 'status' || key == 'operstate'
            ? const {
                    'active': '已连接',
                    'inactive': '未连接',
                    'up': '已连接',
                    'down': '未连接',
                  }[value] ??
                  value
            : value,
      );
    } else if (RegExp('^options=|^nd6 options=').hasMatch(line)) {
      final split = line.indexOf('=');
      add(
        line.startsWith('nd6') ? 'IPv6 邻居选项' : '网卡选项',
        line.substring(split + 1),
      );
    } else if (RegExp(r'^[\da-fA-F:.%]+$').hasMatch(line) &&
        previous.isNotEmpty) {
      add(previous, line);
    } else if (line.startsWith('valid_lft')) {
      final pairs = line.split(RegExp(r'\s+'));
      for (var i = 0; i + 1 < pairs.length; i += 2) {
        add(pairs[i] == 'valid_lft' ? '有效期' : '首选有效期', pairs[i + 1]);
      }
    }
  }
  return MachineMaintenanceReadout(
    [],
    [],
    groups: {
      for (final entry in interfaces.entries)
        entry.key: MachineMaintenanceReadout(
          ['名称', '数值'],
          [
            for (final field in entry.value.entries) [field.key, field.value],
          ],
          fields: true,
        ),
    },
    issue: interfaces.isEmpty ? 'format' : null,
  );
}

MachineMaintenanceReadout _machineNeighborReadout(List<String> lines) {
  final rows = <List<String>>[];
  var interface = '—';
  for (final line in lines) {
    final text = line.trim();
    final heading = RegExp(r'^(?:Interface|接口)\s+([^:]+):').firstMatch(text);
    if (heading != null) {
      interface = heading[1]!;
      continue;
    }
    final arp = RegExp(
      r'^.*?\(([^)]+)\)\s+at\s+(\S+)\s+on\s+(\S+)(.*)$',
    ).firstMatch(text);
    if (arp != null) {
      rows.add([
        'IPv4',
        arp[1]!,
        arp[2] == '(incomplete)' ? '未解析' : arp[2]!,
        arp[3]!,
        arp[2] == '(incomplete)' ? '未完成' : '已解析',
        arp[4]!.contains('permanent') ? '永久' : '—',
        arp[4]!.contains('published') ? '代理' : '—',
      ]);
      continue;
    }
    final parts = text.split(RegExp(r'\s+'));
    if (parts.length < 3 ||
        !RegExp(r'^[\da-fA-F:.]+(?:%[\w.-]+)?$').hasMatch(parts.first)) {
      continue;
    }
    if (parts.contains('dev')) {
      String after(String key) {
        final i = parts.indexOf(key);
        return i < 0 || i + 1 >= parts.length ? '—' : parts[i + 1];
      }

      rows.add([
        parts.first.contains(':') ? 'IPv6' : 'IPv4',
        parts.first,
        after('lladdr'),
        after('dev'),
        parts.firstWhere(
          (part) => const {
            'REACHABLE',
            'STALE',
            'DELAY',
            'PROBE',
            'FAILED',
            'INCOMPLETE',
            'PERMANENT',
            'NOARP',
            'NONE',
          }.contains(part),
          orElse: () => '—',
        ),
        '—',
        parts.contains('router') ? '路由器' : '—',
      ]);
    } else if (parts.first.contains(':') && parts.length >= 5) {
      rows.add([
        'IPv6',
        parts[0],
        parts[1] == '(incomplete)' ? '未解析' : parts[1],
        parts[2],
        const {
              'R': '可达',
              'I': '未完成',
              'S': '已过期',
              'D': '等待探测',
              'P': '探测中',
              'N': '无状态',
              '?': '未知',
            }[parts[4]] ??
            parts[4],
        parts[3] == 'permanent' ? '永久' : parts[3],
        parts.length > 5 ? parts.skip(5).join(' · ') : '—',
      ]);
    } else {
      rows.add([
        parts.first.contains(':') ? 'IPv6' : 'IPv4',
        parts[0],
        parts[1],
        interface,
        parts[2],
        '—',
        '—',
      ]);
    }
  }
  return MachineMaintenanceReadout([
    '地址族',
    '邻居地址',
    'MAC 地址',
    '网卡',
    '状态',
    '过期时间',
    '标志',
  ], rows);
}

MachineMaintenanceReadout _machinePolicyReadout(List<String> lines) {
  final rows = <List<String>>[];
  for (final line in lines) {
    final match = RegExp(r'^(\d+):\s+(.*)$').firstMatch(line.trim());
    if (match == null) continue;
    final parts = match[2]!.split(RegExp(r'\s+'));
    String after(String key) {
      final i = parts.indexOf(key);
      return i < 0 || i + 1 >= parts.length ? '—' : parts[i + 1];
    }

    rows.add([
      match[1]!,
      after('from'),
      after('to'),
      after('lookup') == '—' ? after('table') : after('lookup'),
      after('fwmark'),
      after('iif'),
      after('oif'),
      parts.contains('unreachable')
          ? '不可达'
          : parts.contains('blackhole')
          ? '黑洞'
          : '查询路由表',
    ]);
  }
  return MachineMaintenanceReadout([
    '优先级',
    '源地址',
    '目的地址',
    '路由表',
    '防火墙标记',
    '入站网卡',
    '出站网卡',
    '动作',
  ], rows);
}

MachineMaintenanceReadout _machineLsofReadout(List<String> lines) {
  final rows = <List<String>>[];
  for (final line in lines.skip(1)) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 9 || int.tryParse(parts[1]) == null) continue;
    rows.add([
      parts[0],
      parts[1],
      parts[2],
      parts[3],
      parts[4],
      parts[5],
      parts[6],
      parts[7],
      parts.skip(8).join(' '),
    ]);
  }
  return MachineMaintenanceReadout([
    '进程',
    'PID',
    '用户',
    '文件描述符',
    '地址族',
    '设备标识',
    '大小 / 位移',
    '协议',
    '连接地址',
  ], rows);
}

MachineMaintenanceReadout _machineCounterReadout(List<String> lines) {
  final groups = <String, List<List<String>>>{};
  final headings = <String, List<String>>{};
  var group = '统计';
  for (final original in lines) {
    final line = original.trim();
    if (line.startsWith('Status:')) {
      (groups[group] ??= []).add(['状态', line.substring(7).trim()]);
      continue;
    }
    if (line.endsWith(':') ||
        RegExp(
          '^(?:TCP|UDP|IPv[46]|ICMPv?[46]?) Statistics',
          caseSensitive: false,
        ).hasMatch(line)) {
      group = line.replaceFirst(RegExp(r':$'), '');
      continue;
    }
    final colon = RegExp(r'^(\S+):\s+(.*)$').firstMatch(line);
    if (colon != null) {
      group = colon[1]!;
      final parts = colon[2]!.split(RegExp(r'\s+'));
      if (parts.every((v) => num.tryParse(v) != null) &&
          headings[group] != null) {
        for (var i = 0; i < parts.length && i < headings[group]!.length; i++) {
          (groups[group] ??= []).add([headings[group]![i], parts[i]]);
        }
      } else if (parts.length.isEven &&
          parts.where((v) => num.tryParse(v) != null).length ==
              parts.length ~/ 2) {
        for (var i = 0; i < parts.length; i += 2) {
          (groups[group] ??= []).add([parts[i], parts[i + 1]]);
        }
      } else {
        headings[group] = parts;
      }
      continue;
    }
    final count = RegExp(r'^(\d+)\s+(.+)$').firstMatch(line);
    final keyValue = RegExp(
      r'^(.+?)\s*(?:=|\s{2,})\s*(\d+)\s*$',
    ).firstMatch(line);
    if (count != null) {
      (groups[group] ??= []).add([count[2]!, count[1]!]);
    } else if (keyValue != null) {
      (groups[group] ??= []).add([keyValue[1]!, keyValue[2]!]);
    }
  }
  return MachineMaintenanceReadout(
    [],
    [],
    groups: {
      for (final entry in groups.entries)
        entry.key: MachineMaintenanceReadout(
          ['指标', '数值'],
          entry.value,
          fields: true,
        ),
    },
    issue: groups.isEmpty ? 'format' : null,
  );
}

MachineMaintenanceReadout _machineConfigurationReadout(List<String> lines) {
  final groups = <String, List<List<String>>>{};
  var group = '配置';
  List<String>? previous;
  for (final original in lines) {
    final line = original.trim();
    if (line == '{' || line == '}' || RegExp(r'^\d+\s*:\s*<').hasMatch(line)) {
      continue;
    }
    if (line.endsWith(':') ||
        RegExp(
          r'^(Global|Link \d+|IPv[46] network interface information)',
        ).hasMatch(line)) {
      group = line.replaceFirst(RegExp(r':$'), '');
      previous = null;
      continue;
    }
    final rule = RegExp(r'^(?:Rule Name|规则名称):\s*(.+)$').firstMatch(line);
    if (rule != null) {
      group = rule[1]!;
      previous = null;
      continue;
    }
    final field =
        RegExp(r'^([^:=]+?)\s*[:=]\s*(.*)$').firstMatch(line) ??
        RegExp(r'^(.+?)\s{2,}(\S.*)$').firstMatch(line);
    if (field != null) {
      previous = [field[1]!.trim(), field[2]!.trim()];
      (groups[group] ??= []).add(previous);
    } else if (line.contains('Direct access') || line.contains('直接访问')) {
      (groups[group] ??= []).add(['代理模式', '直接连接']);
    } else if (line.startsWith('flags')) {
      (groups[group] ??= []).add(['标志', line.substring(5).trim()]);
    } else if (line.contains(' : ')) {
      final split = line.indexOf(' : ');
      (groups[group] ??= []).add([
        line.substring(0, split),
        line.substring(split + 3),
      ]);
    } else if (previous != null &&
        original.startsWith(' ') &&
        !line.startsWith('Network information')) {
      previous[1] += ' · $line';
    }
  }
  return MachineMaintenanceReadout(
    [],
    [],
    groups: {
      for (final entry in groups.entries)
        entry.key: MachineMaintenanceReadout(
          ['名称', '数值'],
          entry.value,
          fields: true,
        ),
    },
    issue: groups.isEmpty ? 'format' : null,
  );
}

MachineMaintenanceReadout _machineFirewallReadout(
  List<String> lines,
  String section,
) {
  final fields = <List<String>>[];
  final rules = <List<String>>[];
  final policies = <List<String>>[];
  var table = 'filter';
  var chain = '—';
  var family = section == 'firewall_ipvfour'
      ? 'IPv4'
      : section == 'firewall_ipvsix'
      ? 'IPv6'
      : '—';
  final tables = <String>{};
  for (final original in lines) {
    final line = original.trim();
    if (line.startsWith('#') || line == 'COMMIT' || line == '}') continue;
    final issue = machineMaintenanceCollectionIssue(line, 'firewall');
    if (issue != null) {
      fields.add([
        '采集状态',
        switch (issue) {
          'permission' => '权限不足，当前账户无法读取规则',
          'missing' => '缺少防火墙工具',
          _ => '部分规则暂不可用',
        },
      ]);
      continue;
    }
    if (line.startsWith('Firewall is ') ||
        line.startsWith('Firewall has ') ||
        line.startsWith('Firewall stealth ')) {
      final key = line.contains('block all')
          ? '阻止所有入站连接'
          : line.contains('stealth')
          ? '隐身模式'
          : '应用防火墙';
      fields.add([
        key,
        RegExp(r'\bdisabled\b|\boff\b').hasMatch(line) ? '禁用' : '启用',
      ]);
      continue;
    }
    if (line.startsWith('*')) {
      table = line.substring(1);
      tables.add(table);
      continue;
    }
    final policy = RegExp(
      r'^:(\S+)\s+(\S+)\s+\[(\d+):(\d+)\]',
    ).firstMatch(line);
    final simplePolicy = RegExp(r'^-P\s+(\S+)\s+(\S+)').firstMatch(line);
    if (policy != null || simplePolicy != null) {
      policies.add([
        table,
        (policy ?? simplePolicy)![1]!,
        (policy ?? simplePolicy)![2]!,
        policy?[3] ?? '—',
        policy?[4] ?? '—',
      ]);
      continue;
    }
    final nftTable = RegExp(r'^table\s+(\S+)\s+(\S+)').firstMatch(line);
    if (nftTable != null) {
      family = nftTable[1]!;
      table = nftTable[2]!;
      tables.add('$family / $table');
      continue;
    }
    final nftChain = RegExp(r'^chain\s+(\S+)').firstMatch(line);
    if (nftChain != null) {
      chain = nftChain[1]!;
      continue;
    }
    if (line.startsWith('type ') && line.contains('hook')) {
      for (final match in RegExp(
        r'\b(type|hook|priority|policy)\s+([^;\s]+)',
      ).allMatches(line)) {
        final label = const {
          'type': '链类型',
          'hook': '挂载点',
          'priority': '优先级',
          'policy': '默认动作',
        }[match[1]]!;
        fields.add(['$table / $chain / $label', match[2]!]);
      }
      continue;
    }
    final tokens = RegExp(
      r'''"[^"]*"|'[^']*'|\S+''',
    ).allMatches(line).map((m) => m[0]!).toList();
    String after(String key) {
      final i = tokens.indexOf(key);
      return i < 0 || i + 1 >= tokens.length ? '—' : tokens[i + 1];
    }

    if (tokens.contains('-A') || tokens.contains('-I')) {
      final counter = RegExp(r'^\[(\d+):(\d+)\]').firstMatch(line);
      final options = <String>[];
      const known = {
        '-A',
        '-I',
        '-s',
        '-d',
        '-p',
        '-i',
        '-o',
        '-j',
        '-g',
        '--dport',
        '--sport',
      };
      for (var i = counter == null ? 0 : 1; i < tokens.length; i++) {
        if (known.contains(tokens[i])) {
          i++;
        } else {
          options.add(tokens[i]);
        }
      }
      rules.add([
        family,
        table,
        after('-A') == '—' ? after('-I') : after('-A'),
        after('-j') == '—' ? after('-g') : after('-j'),
        after('-p'),
        after('-s'),
        after('-d'),
        after('--sport'),
        after('--dport'),
        after('-i'),
        after('-o'),
        counter?[1] ?? '—',
        counter?[2] ?? '—',
        options.join(' '),
      ]);
      continue;
    }
    // PF 与 nft 保留匹配表达式，按规则归属、动作和计数器拆分。
    final action = RegExp(
      r'\b(accept|drop|reject|return|pass|block|nat|rdr|match|jump|goto|log)\b',
    ).firstMatch(line);
    if (action != null) {
      final packets = RegExp(r'\bpackets\s+(\d+)').firstMatch(line);
      final bytes = RegExp(r'\bbytes\s+(\d+)').firstMatch(line);
      final source =
          RegExp(r'\bfrom\s+(\{[^}]*\}|\S+)').firstMatch(line) ??
          RegExp(r'\bsaddr\s+(\{[^}]*\}|\S+)').firstMatch(line);
      final destination =
          RegExp(r'\bto\s+(\{[^}]*\}|\S+)').firstMatch(line) ??
          RegExp(r'\bdaddr\s+(\{[^}]*\}|\S+)').firstMatch(line);
      rules.add([
        family,
        table,
        chain,
        action[1]!,
        after('proto') == '—'
            ? tokens.firstWhere(
                (v) =>
                    const {'tcp', 'udp', 'icmp', 'icmpv6', 'sctp'}.contains(v),
                orElse: () => '—',
              )
            : after('proto'),
        source?[1] ?? '—',
        destination?[1] ?? '—',
        after('sport'),
        after('dport'),
        after('on'),
        '—',
        packets?[1] ?? '—',
        bytes?[1] ?? '—',
        line
            .replaceAll(RegExp(r'#\s*handle\s+\d+'), '')
            .replaceAll(RegExp(r'counter\s+packets\s+\d+\s+bytes\s+\d+'), '')
            .trim(),
      ]);
    } else if (line.startsWith('[') && rules.isNotEmpty) {
      for (final metric in RegExp(
        r'(Evaluations|Packets|Bytes|States):\s*(\d+)',
      ).allMatches(line)) {
        if (metric[1] == 'Packets') rules.last[11] = metric[2]!;
        if (metric[1] == 'Bytes') rules.last[12] = metric[2]!;
      }
    }
  }
  if (fields.isEmpty &&
      policies.isEmpty &&
      rules.isEmpty &&
      tables.isNotEmpty) {
    fields.addAll(tables.map((name) => ['规则表', name]));
    fields.add(['规则数', '0']);
  }
  if (fields.isEmpty && policies.isEmpty && rules.isEmpty) {
    return _machineConfigurationReadout(lines);
  }
  return MachineMaintenanceReadout(
    ['名称', '数值'],
    fields,
    fields: true,
    groups: {
      if (policies.isNotEmpty)
        '链策略': MachineMaintenanceReadout([
          '规则表',
          '链',
          '默认动作',
          '包数',
          '字节',
        ], policies),
      if (rules.isNotEmpty)
        '规则与计数器': MachineMaintenanceReadout([
          '地址族',
          '规则表',
          '链',
          '动作',
          '协议',
          '源地址',
          '目的地址',
          '源端口',
          '目的端口',
          '入站网卡',
          '出站网卡',
          '包数',
          '字节',
          '匹配条件',
        ], rules),
    },
  );
}
