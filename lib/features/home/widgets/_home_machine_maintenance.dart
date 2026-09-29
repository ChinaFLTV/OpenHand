part of '../openhand_home_page.dart';

const _maintenanceTabs = ['运行总览', '进程管理', '系统服务', '网络与诊断'];
const _maintenanceSectionLabels = {
  'system': '系统与内核',
  'processor': '处理器型号',
  'load': '系统负载 · 1 / 5 / 15 分钟',
  'pressure': '资源压力 · CPU / 内存 / IO',
  'filesystems': '文件系统容量 · KiB',
  'inodes': '文件系统 inode',
  'swap': '交换空间',
  'interfaces': '网卡链路与硬件',
  'sensors': '温度传感器',
  'memory': '内存详情',
  'memory_note': '内存统计口径',
  'memory_details': '内存与分页性能计数器',
  'vm': '虚拟内存计数器',
  'startup': '开机启动状态',
  'timers': '系统定时器',
  'sockets': '连接与监听端口',
  'routes': '地址与路由',
  'dns': 'DNS 配置',
  'logs': '最近日志',
  'users': '登录用户',
  'cron': '当前用户计划任务',
  'firewall': '防火墙规则',
  'containers': '容器状态',
  'status': '状态详情',
  'command': '启动命令',
  'paths': '可执行文件与工作目录',
  'io': '进程 IO 计数器',
  'limits': '资源限制',
  'cgroup': '控制组',
  'descriptors': '打开的文件描述符',
  'capabilities': '环境能力',
  'blocks': '块设备与 RAID',
  'cgroup_limits': '控制组资源限制 · 容器与主机视图可能不同',
  'kernel': '内核资源参数',
  'network': '网卡累计计数 · 字节、包、错误与丢包',
};

class _MachineMaintenanceDialog extends StatefulWidget {
  const _MachineMaintenanceDialog({
    required this.sessionId,
    required this.terminalId,
  });
  final String sessionId, terminalId;
  @override
  State<_MachineMaintenanceDialog> createState() =>
      _MachineMaintenanceDialogState();
}

class _MachineMaintenanceDialogState extends State<_MachineMaintenanceDialog>
    with WidgetsBindingObserver {
  final _snapshots = <int, MachineMaintenanceSnapshot>{};
  final _previous = <int, MachineMaintenanceSnapshot>{};
  final _cpuHistory = <double>[];
  final _search = TextEditingController();
  Timer? _timer;
  MachineMaintenancePlatformAdapter? _platform;
  String? _platformName;
  MachineTerminalCommandShell _commandShell = MachineTerminalCommandShell.posix;
  MachineTerminalCommandShell _requestedShell =
      MachineTerminalCommandShell.automatic;
  bool _loading = false,
      _automatic = false,
      _foreground = true,
      _detailOpen = false;
  String? _error;
  DateTime? _updated;
  int _tab = 0, _page = 0, _sort = 0, _processOffset = 0;
  int _intervalSeconds = machineMaintenanceInterval.inSeconds;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (mounted &&
        _automatic &&
        _foreground &&
        !_loading &&
        !_detailOpen &&
        _error == null) {
      _timer = startSafeTimer(Duration(seconds: _intervalSeconds), _refresh);
    }
  }

  Future<String> _run(String command, {bool probe = false}) =>
      context.read<MachineTerminalFileService>().runMaintenanceCommand(
        sessionId: widget.sessionId,
        terminalId: widget.terminalId,
        command: command,
        windowsScript: !probe && (_platform?.windowsScript ?? false),
        commandShell: probe ? MachineTerminalCommandShell.probe : _commandShell,
        isCancelled: () => !mounted,
      );

  Future<void> _refresh() async {
    if (_loading || !mounted) return;
    _timer?.cancel();
    final tab = _tab;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final target = parseMachineTerminalShellProbe(
        await _run(machineTerminalShellProbe, probe: true),
      );
      if (!mounted) return;
      if (_requestedShell != MachineTerminalCommandShell.automatic &&
          (_requestedShell == MachineTerminalCommandShell.posix) !=
              (target.platform != 'Windows')) {
        throw StateError('所选 Shell 与目标系统不匹配，请改为自动识别或实际使用的 Shell。');
      }
      if (_platformName != null && _platformName != target.platform) {
        _snapshots.clear();
        _previous.clear();
        _cpuHistory.clear();
        _processOffset = 0;
      }
      _platformName = target.platform;
      _platform = MachineMaintenancePlatformAdapter.forPlatform(
        target.platform,
      );
      _commandShell = _requestedShell == MachineTerminalCommandShell.automatic
          ? target.shell
          : _requestedShell;
      final result = MachineMaintenanceSnapshot.parse(
        await _run(_platform!.collect(tab, offset: _processOffset)),
      );
      if (!mounted) return;
      setState(() {
        final old = _snapshots[tab];
        if (old != null) _previous[tab] = old;
        _snapshots[tab] = result;
        _updated = DateTime.now();
        if (tab == 0) {
          if (old?.identity != result.identity) _cpuHistory.clear();
          final cpu = result.cpuUsage(old);
          if (cpu != null) _cpuHistory.add(cpu);
          if (_cpuHistory.length > 60) _cpuHistory.removeAt(0);
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
        _schedule();
      }
    }
  }

  Future<void> _details(
    String title,
    String command, {
    Map<String, String> actions = const {},
  }) async {
    if (_loading || _platform == null) return;
    final platform = _platform!;
    final snapshot = _snapshots[_tab]!;
    _detailOpen = true;
    _timer?.cancel();
    await showAnimatedDialog<void>(
      context: context,
      builder: (_) => _MachineMaintenanceDetails(
        title: title,
        load: () => _run(platform.bind(snapshot, command)),
        actions: actions,
        execute: (command) => _run(platform.bind(snapshot, command)),
      ),
    );
    _detailOpen = false;
    if (mounted) _schedule();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final data = _snapshots[_tab];
    return buildOpenHandDialog(
      insetPadding: const EdgeInsets.all(14),
      backgroundColor: cs.surface,
      child: SizedBox(
        width: math.min(size.width * .96, 1240),
        height: size.height * .9,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MachineTerminalDialogHeader(
              icon: Icons.monitor_heart_outlined,
              title: '服务器运维',
              subtitle:
                  '${_platformName ?? '目标系统识别中'} · ${data?.text('host') ?? widget.terminalId} · ${_updated == null ? '正在连接当前终端' : '更新于 ${_updated!.toLocal().toString().substring(11, 19)}'}',
              onClose: () => Navigator.of(context).pop(),
              trailingActions: [
                _MachineTerminalIconButton(
                  icon: _automatic
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  tooltip: _automatic ? '暂停自动刷新' : '开启自动刷新（当前分区）',
                  onPressed: () {
                    setState(() {
                      _automatic = !_automatic;
                    });
                    _schedule();
                  },
                ),
                _MachineTerminalIconButton(
                  icon: Icons.refresh_rounded,
                  tooltip: '刷新当前分区',
                  onPressed: _loading ? null : _refresh,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(
                  _maintenanceTabs.length,
                  (index) => ChoiceChip(
                    label: Text(_maintenanceTabs[index]),
                    selected: _tab == index,
                    onSelected: _loading
                        ? null
                        : (_) {
                            setState(() {
                              _tab = index;
                              _page = 0;
                              _search.clear();
                              _error = null;
                            });
                            _refresh();
                          },
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 190,
                    child:
                        AnimatedDropdownButtonFormField<
                          MachineTerminalCommandShell
                        >(
                          value: _requestedShell,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.all(
                                Radius.circular(12),
                              ),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: MachineTerminalCommandShell.automatic,
                              child: Text('自动识别 Shell'),
                            ),
                            DropdownMenuItem(
                              value: MachineTerminalCommandShell.posix,
                              child: Text('POSIX Shell'),
                            ),
                            DropdownMenuItem(
                              value: MachineTerminalCommandShell.powershell,
                              child: Text('PowerShell'),
                            ),
                            DropdownMenuItem(
                              value: MachineTerminalCommandShell.cmd,
                              child: Text('CMD'),
                            ),
                          ],
                          onChanged: _loading
                              ? null
                              : (value) {
                                  setState(() {
                                    _requestedShell = value!;
                                  });
                                  _refresh();
                                },
                        ),
                  ),
                  const Text('自动刷新间隔'),
                  SizedBox(
                    width: 120,
                    child: AnimatedDropdownButtonFormField<int>(
                      value: _intervalSeconds,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                      ),
                      borderRadius: BorderRadius.circular(12),
                      items: [5, 10, 30, 60]
                          .map(
                            (seconds) => DropdownMenuItem(
                              value: seconds,
                              child: Text('$seconds 秒'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _intervalSeconds = value!;
                        });
                        _schedule();
                      },
                    ),
                  ),
                  Text(
                    _automatic
                        ? (_error == null ? '已开启 · 上次采集完成后计时' : '自动刷新等待手动恢复')
                        : '已暂停',
                    style: TextStyle(color: cs.primary),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
              child: Text(
                '沿用当前终端身份与权限 · 辅助命令不持久化 · ${_automatic && _error == null ? '自动采样已开启' : '等待手动采样'} · 速率需两次采样，缺失数据表示不可用',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            SizedBox(
              height: 3,
              child: _loading ? const LinearProgressIndicator() : null,
            ),
            if (data?.text('notice').isNotEmpty ?? false)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  data!.text('notice'),
                  style: TextStyle(color: cs.tertiary),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '采集失败，已暂停自动重试；现有数据可能过期。\n$_error',
                  style: TextStyle(color: cs.error),
                ),
              ),
            Expanded(
              child: data == null
                  ? Center(child: Text(_loading ? '正在读取机器状态…' : '暂无数据，点击刷新重试。'))
                  : switch (_tab) {
                      0 => _overview(data),
                      1 => _processes(data),
                      2 => _services(data),
                      _ => _sections(data, const [
                        'sockets',
                        'routes',
                        'dns',
                        'logs',
                        'users',
                        'cron',
                        'firewall',
                        'containers',
                      ]),
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _overview(MachineMaintenanceSnapshot data) {
    final cs = Theme.of(context).colorScheme;
    final memory = data.memory;
    final total = memory['MemTotal'];
    final available = memory['MemAvailable'];
    final swap = memory['SwapTotal'];
    final freeSwap = memory['SwapFree'];
    final cpu = data.cpuUsage(_previous[0]);
    final cores = data
        .counters('cpu')
        .keys
        .where((key) => RegExp(r'^cpu\d+$').hasMatch(key))
        .toList();
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _metric(
              'CPU 使用率',
              cpu == null ? '等待下次采样' : '${(cpu * 100).toStringAsFixed(1)}%',
              data.text('core_count').isEmpty && cores.isEmpty
                  ? '逻辑处理器数量未知'
                  : '${data.text('core_count').isEmpty ? cores.length : data.text('core_count')} 个逻辑处理器',
              Icons.memory_rounded,
              cs.primary,
              cpu,
            ),
            _metric(
              '物理内存',
              total == null || available == null
                  ? '不可用'
                  : formatByteSize(total - available),
              '总量 ${total == null ? '未知' : formatByteSize(total)}',
              Icons.storage_rounded,
              cs.tertiary,
              total != null && total > 0 && available != null
                  ? (total - available) / total
                  : null,
            ),
            _metric(
              'SWAP 使用量',
              swap == null || freeSwap == null
                  ? '不可用'
                  : formatByteSize(swap - freeSwap),
              '总量 ${swap == null ? '未知' : formatByteSize(swap)}',
              Icons.swap_horiz_rounded,
              cs.secondary,
              swap != null && swap > 0 && freeSwap != null
                  ? (swap - freeSwap) / swap
                  : null,
            ),
            _metric(
              '运行时间',
              data.uptime == null
                  ? '未知'
                  : '${(data.uptime! / 86400).floor()} 天 ${(data.uptime! / 3600).floor() % 24} 小时',
              '负载 ${data.text('load').split(' ').take(3).join(' / ')}',
              Icons.schedule_rounded,
              cs.primary,
              null,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _MaintenanceCard(
          title: 'CPU 趋势 · 最近 60 个有效采样',
          child: SizedBox(
            height: 90,
            child: _cpuHistory.length < 2
                ? const Center(child: Text('开启自动采样或手动刷新以绘制趋势'))
                : CustomPaint(
                    painter: _MaintenanceSparkline(
                      List.of(_cpuHistory),
                      cs.primary,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        _MaintenanceCard(
          title: '每核负载',
          child: cores.isEmpty
              ? const Text('当前系统未提供每核计数。')
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: cores.map((core) {
                    final value = data.cpuUsage(_previous[0], core);
                    return Chip(
                      label: Text(
                        '$core · ${value == null ? '待采样' : '${(value * 100).toStringAsFixed(0)}%'}',
                      ),
                    );
                  }).toList(),
                ),
        ),
        const SizedBox(height: 12),
        _MaintenanceCard(
          title: '存储空间',
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('挂载点')),
                DataColumn(label: Text('容量')),
                DataColumn(label: Text('已用')),
                DataColumn(label: Text('可用')),
                DataColumn(label: Text('使用率')),
              ],
              rows: data
                  .text('filesystems')
                  .split('\n')
                  .skip(1)
                  .map((line) => line.trim().split(RegExp(r'\s+')))
                  .where(
                    (fields) =>
                        fields.length >= 6 && int.tryParse(fields[1]) != null,
                  )
                  .map(
                    (fields) => DataRow(
                      cells: [
                        DataCell(
                          SizedBox(
                            width: 220,
                            child: Text(
                              fields.skip(5).join(' '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        ...[1, 2, 3].map(
                          (index) => DataCell(
                            Text(
                              formatByteSize(
                                (int.tryParse(fields[index]) ?? 0) * 1024,
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 130,
                            child: Row(
                              children: [
                                Expanded(
                                  child: LinearProgressIndicator(
                                    value:
                                        ((double.tryParse(
                                                      fields[4].replaceAll(
                                                        '%',
                                                        '',
                                                      ),
                                                    ) ??
                                                    0) /
                                                100)
                                            .clamp(0, 1),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(fields[4]),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _MaintenanceCard(
          title: '磁盘 IO · 设备与分区可能重叠，不作累加',
          child: _rateTable(
            data,
            'disks',
            const ['设备', '读取 / 秒', '写入 / 秒', '读 IOPS', '写 IOPS', '忙碌毫秒 / 秒'],
            const [2, 6, 0, 4, 9],
            const [512, 512, 1, 1, 1],
          ),
        ),
        const SizedBox(height: 12),
        _MaintenanceCard(
          title: '网络 IO',
          child: _rateTable(
            data,
            'network',
            const ['网卡', '接收 / 秒', '发送 / 秒', '接收丢包 / 秒', '发送丢包 / 秒'],
            const [0, 8, 3, 11],
            const [1, 1, 1, 1],
          ),
        ),
        const SizedBox(height: 12),
        _MaintenanceCard(
          title: '内存 IO · 分页与交换',
          child: data.text('vm').isEmpty
              ? const Text('当前系统未提供统一分页计数，请查看下方内存性能详情。')
              : Wrap(
                  spacing: 20,
                  runSpacing: 8,
                  children:
                      [
                        'pgpgin',
                        'pgpgout',
                        'pswpin',
                        'pswpout',
                        'pgfault',
                        'pgmajfault',
                      ].map((key) {
                        final value = data.rate(_previous[0], 'vm', key, 0);
                        return Text(
                          '$key：${value == null ? '待采样' : value.toStringAsFixed(1)} ${key.startsWith('pgpg') ? 'KiB/s' : '次/s'}',
                        );
                      }).toList(),
                ),
        ),
        const SizedBox(height: 12),
        ..._sectionWidgets(data, const [
          'processor',
          'system',
          'capabilities',
          'blocks',
          'cgroup_limits',
          'kernel',
          'network',
          'pressure',
          'filesystems',
          'inodes',
          'swap',
          'interfaces',
          'sensors',
          'memory',
          'memory_note',
          'memory_details',
          'vm',
        ]),
      ],
    );
  }

  Widget _metric(
    String title,
    String value,
    String subtitle,
    IconData icon,
    Color color,
    double? progress,
  ) {
    return SizedBox(
      width: 270,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: color.withValues(alpha: .09),
          border: Border.all(color: color.withValues(alpha: .2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 8),
                Text(title),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (progress ?? 0).clamp(0, 1),
                color: color,
                minHeight: 5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rateTable(
    MachineMaintenanceSnapshot data,
    String section,
    List<String> headings,
    List<int> indexes,
    List<int> multipliers,
  ) {
    final keys = data.counters(section, colon: section == 'network').keys;
    if (keys.isEmpty) return const Text('当前环境未提供可用计数器。');
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: headings.map((name) => DataColumn(label: Text(name))).toList(),
        rows: keys
            .map(
              (key) => DataRow(
                cells: [
                  DataCell(
                    Text(
                      data.text('platform') == 'Windows'
                          ? Uri.decodeComponent(key)
                          : key,
                    ),
                  ),
                  ...List.generate(indexes.length, (i) {
                    final rate = data.rate(
                      _previous[0],
                      section,
                      key,
                      indexes[i],
                      multiplier: multipliers[i],
                    );
                    return DataCell(
                      Text(
                        rate == null
                            ? '—'
                            : i < 2
                            ? '${formatByteSize(rate)}/s'
                            : rate.toStringAsFixed(1),
                      ),
                    );
                  }),
                ],
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _processes(MachineMaintenanceSnapshot data) {
    final query = _search.text.trim().toLowerCase();
    final rows = data.processes
        .where((p) => '${p.pid} ${p.name}'.toLowerCase().contains(query))
        .toList();
    final pageSize = int.tryParse(data.text('page_size'));
    final ticksPerSecond = int.tryParse(data.text('clock_ticks'));
    final old = _previous[1];
    final previousProcesses = {
      for (final p in old?.processes ?? <MachineMaintenanceProcess>[]) p.pid: p,
    };
    double? cpu(MachineMaintenanceProcess p) {
      final before = previousProcesses[p.pid];
      final elapsed = (data.uptime ?? 0) - (old?.uptime ?? 0);
      if (old?.identity != data.identity ||
          before == null ||
          before.started != p.started ||
          before.startToken != p.startToken ||
          p.ticks < 0 ||
          before.ticks < 0 ||
          ticksPerSecond == null ||
          ticksPerSecond <= 0 ||
          elapsed <= 0 ||
          p.ticks < before.ticks) {
        return null;
      }
      return (p.ticks - before.ticks) / ticksPerSecond / elapsed * 100;
    }

    rows.sort(
      (a, b) => switch (_sort) {
        1 => b.residentPages.compareTo(a.residentPages),
        2 => a.pid.compareTo(b.pid),
        _ => (cpu(b) ?? -1).compareTo(cpu(a) ?? -1),
      },
    );
    final pages = math.max(1, (rows.length / 40).ceil());
    final currentPage = math.min(_page, pages - 1);
    final countLine = data
        .text('processes')
        .split('\n')
        .where((line) => line.startsWith('__COUNT__'))
        .firstOrNull;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {
                    _page = 0;
                  }),
                  decoration: const InputDecoration(
                    hintText: '搜索 PID 或进程名',
                    prefixIcon: Icon(Icons.search_rounded),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 180,
                child: AnimatedDropdownButtonFormField<int>(
                  value: _sort,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('CPU 降序')),
                    DropdownMenuItem(value: 1, child: Text('内存降序')),
                    DropdownMenuItem(value: 2, child: Text('PID 升序')),
                  ],
                  onChanged: (value) => setState(() {
                    _sort = value!;
                    _page = 0;
                  }),
                ),
              ),
              Text(
                '本批匹配 ${rows.length} · 可见总数 ${countLine?.split('\t').last ?? '未知'} · 从第 ${_processOffset + 1} 条起，每批 $machineMaintenanceProcessLimit 条',
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (_, constraints) => SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: DataTable(
                    showCheckboxColumn: false,
                    columns: const [
                      DataColumn(label: Text('PID')),
                      DataColumn(label: Text('进程')),
                      DataColumn(label: Text('状态')),
                      DataColumn(label: Text('CPU · 单核 100%')),
                      DataColumn(label: Text('驻留内存')),
                      DataColumn(label: Text('线程')),
                    ],
                    rows: rows
                        .skip(currentPage * 40)
                        .take(40)
                        .map(
                          (p) => DataRow(
                            onSelectChanged: !_platform!.canInspectProcess(p)
                                ? null
                                : (_) => _details(
                                    '进程 ${p.pid} · ${p.name}',
                                    _platform!.process(p),
                                    actions: {
                                      for (final action
                                          in _platform!
                                              .processActions(p)
                                              .entries)
                                        action.key: _platform!.process(
                                          p,
                                          action: action.value,
                                        ),
                                    },
                                  ),
                            cells: [
                              DataCell(Text('${p.pid}')),
                              DataCell(
                                SizedBox(
                                  width: 220,
                                  child: Text(
                                    p.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataCell(Text(p.state)),
                              DataCell(
                                Text(
                                  cpu(p) == null
                                      ? '—'
                                      : '${cpu(p)!.toStringAsFixed(1)}%',
                                ),
                              ),
                              DataCell(
                                Text(
                                  pageSize == null || p.residentPages < 0
                                      ? '不可用'
                                      : formatByteSize(
                                          p.residentPages * pageSize,
                                        ),
                                ),
                              ),
                              DataCell(
                                Text(p.threads < 0 ? '—' : '${p.threads}'),
                              ),
                            ],
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: currentPage > 0
                  ? () => setState(() {
                      _page = currentPage - 1;
                    })
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Text('${currentPage + 1} / $pages'),
            IconButton(
              onPressed: currentPage + 1 < pages
                  ? () => setState(() {
                      _page = currentPage + 1;
                    })
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: !_loading && _processOffset > 0
                  ? () {
                      setState(() {
                        _processOffset = math.max(
                          0,
                          _processOffset - machineMaintenanceProcessLimit,
                        );
                        _page = 0;
                      });
                      _refresh();
                    }
                  : null,
              child: const Text('上一批进程'),
            ),
            TextButton(
              onPressed:
                  !_loading &&
                      _processOffset + machineMaintenanceProcessLimit <
                          (int.tryParse(countLine?.split('\t').last ?? '') ?? 0)
                  ? () {
                      setState(() {
                        _processOffset += machineMaintenanceProcessLimit;
                        _page = 0;
                      });
                      _refresh();
                    }
                  : null,
              child: const Text('下一批进程'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _services(MachineMaintenanceSnapshot data) {
    final adapter = _platform?.servicesFor(data.text('manager'));
    final rows = data
        .text('services')
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
    final known = rows
        .map(
          (line) => (line.contains('\t')
              ? line.split('\t').first
              : line.trim().split(RegExp(r'\s+')).first),
        )
        .toSet();
    final extra = data.text(
      data.text('manager') == 'systemd' ? 'startup' : 'installed',
    );
    for (final line in extra.split('\n')) {
      final name = (line.contains('\t')
          ? line.split('\t').first
          : line.trim().split(RegExp(r'\s+')).first);
      if ((adapter?.accepts(name) ?? false) && known.add(name)) rows.add(line);
    }
    final filtered = rows
        .where(
          (line) => line.toLowerCase().contains(_search.text.toLowerCase()),
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          '服务管理器：${data.text('manager')} · 点击服务查看状态与可用操作',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: '筛选服务',
            prefixIcon: Icon(Icons.search_rounded),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: math.min(360, MediaQuery.sizeOf(context).height * .42),
          child: ListView.builder(
            primary: false,
            itemCount: filtered.length,
            itemBuilder: (_, index) {
              final line = filtered[index];
              final name = (line.contains('\t')
                  ? line.split('\t').first
                  : line.trim().split(RegExp(r'\s+')).first);
              final enabled = adapter?.accepts(name) ?? false;
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: Icon(
                  line.contains(' failed ')
                      ? Icons.error_outline
                      : Icons.settings_suggest_outlined,
                  color: line.contains(' failed ')
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
                ),
                title: Text(name),
                subtitle: Text(line),
                trailing: enabled ? const Icon(Icons.chevron_right) : null,
                onTap: enabled
                    ? () => _details(
                        name,
                        adapter!.command(name),
                        actions: {
                          for (final action in adapter.actions.entries)
                            action.key: adapter.command(name, action.value),
                        },
                      )
                    : null,
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        ..._sectionWidgets(data, const ['startup', 'timers']),
      ],
    );
  }

  Widget _sections(MachineMaintenanceSnapshot data, List<String> names) =>
      ListView(
        padding: const EdgeInsets.all(18),
        children: _sectionWidgets(data, names),
      );
}

List<Widget> _sectionWidgets(
  MachineMaintenanceSnapshot data,
  List<String> names,
) => names
    .where(data.sections.containsKey)
    .map(
      (name) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _MaintenanceCard(
          title: _maintenanceSectionLabels[name] ?? name,
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text(
              data.text(name).isEmpty
                  ? '无数据 · 组件不可用或权限不足'
                  : '${data.text(name).split('\n').length} 行 · 展开查看',
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  data.text(name).isEmpty ? '未返回数据。' : data.text(name),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    )
    .toList();

class _MaintenanceCard extends StatelessWidget {
  const _MaintenanceCard({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: math.min(320, MediaQuery.sizeOf(context).height * .42),
            ),
            child: SingleChildScrollView(primary: false, child: child),
          ),
        ],
      ),
    );
  }
}

class _MaintenanceSparkline extends CustomPainter {
  _MaintenanceSparkline(this.points, this.color);
  final List<double> points;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = i * size.width / (points.length - 1);
      final y = size.height * (1 - points[i]);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: .25), color.withValues(alpha: .01)],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_MaintenanceSparkline oldDelegate) =>
      color != oldDelegate.color || !listEquals(points, oldDelegate.points);
}

class _MachineMaintenanceDetails extends StatefulWidget {
  const _MachineMaintenanceDetails({
    required this.title,
    required this.load,
    required this.actions,
    required this.execute,
  });
  final String title;
  final Future<String> Function() load;
  final Future<String> Function(String) execute;
  final Map<String, String> actions;
  @override
  State<_MachineMaintenanceDetails> createState() =>
      _MachineMaintenanceDetailsState();
}

class _MachineMaintenanceDetailsState
    extends State<_MachineMaintenanceDetails> {
  MachineMaintenanceSnapshot? _data;
  String? _error, _result;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = MachineMaintenanceSnapshot.parse(await widget.load());
      if (mounted) {
        setState(() {
          _data = data;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _act(MapEntry<String, String> action) async {
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: action.key,
      confirmLabel: '确认执行',
      destructive: true,
      message: '目标：${widget.title}\n将使用当前终端权限执行“${action.key}”，可能影响正在运行的任务。',
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      await widget.execute(action.value);
      if (mounted) {
        setState(() {
          _result = '${action.key}已执行，点击刷新查看最新状态。';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return buildOpenHandDialog(
      insetPadding: const EdgeInsets.all(18),
      child: SizedBox(
        width: math.min(size.width * .9, 940),
        height: size.height * .82,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MachineTerminalDialogHeader(
              icon: Icons.analytics_outlined,
              title: widget.title,
              subtitle: '实时详情 · 部分字段需要更高权限',
              onClose: () => Navigator.of(context).pop(),
              trailingActions: [
                _MachineTerminalIconButton(
                  icon: Icons.refresh_rounded,
                  tooltip: '刷新详情',
                  onPressed: _busy ? null : _load,
                ),
              ],
            ),
            if (widget.actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: widget.actions.entries
                      .map(
                        (action) => OutlinedButton(
                          onPressed: _busy ? null : () => _act(action),
                          child: Text(action.key),
                        ),
                      )
                      .toList(),
                ),
              ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null || _result != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error ?? _result!,
                  style: TextStyle(
                    color: _error == null
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            Expanded(
              child: _data == null
                  ? Center(child: Text(_busy ? '正在读取详情…' : '读取失败，请重试。'))
                  : ListView(
                      padding: const EdgeInsets.all(18),
                      children: _sectionWidgets(
                        _data!,
                        _data!.sections.keys
                            .where(
                              (key) => !const [
                                'platform',
                                'host',
                                'boot',
                              ].contains(key),
                            )
                            .toList(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
