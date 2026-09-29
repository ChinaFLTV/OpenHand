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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final size = MediaQuery.sizeOf(context);
    final data = _snapshots[_tab];
    final motion = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
    final status = _loading
        ? '采集中'
        : _error != null
        ? '采集异常'
        : _automatic
        ? '自动刷新'
        : '手动刷新';
    return buildOpenHandDialog(
      insetPadding: const EdgeInsets.all(18),
      backgroundColor: Color.alphaBlend(
        cs.primary.withValues(alpha: .025),
        cs.brightness == Brightness.light ? Colors.white : cs.surface,
      ),
      child: Theme(
        data: theme.copyWith(
          textTheme: theme.textTheme.copyWith(
            bodyMedium: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
            bodySmall: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
            labelLarge: theme.textTheme.labelLarge?.copyWith(fontSize: 13),
          ),
          dataTableTheme: DataTableThemeData(
            headingRowColor: WidgetStatePropertyAll(cs.surfaceContainerLow),
            headingTextStyle: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            headingRowHeight: 34,
            dataRowMinHeight: 38,
            dataRowMaxHeight: 46,
            horizontalMargin: 14,
            columnSpacing: 22,
            dividerThickness: .5,
          ),
          inputDecorationTheme: theme.inputDecorationTheme.copyWith(
            filled: true,
            fillColor: cs.surfaceContainerLow,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: cs.outlineVariant),
            ),
          ),
        ),
        child: SizedBox(
          width: math.min(size.width * .9, 1180),
          height: size.height * .88,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (_, constraints) => _MachineTerminalDialogHeader(
                  icon: Icons.dns_rounded,
                  title: '服务器运维中心',
                  subtitle:
                      '${data?.text('host') ?? widget.terminalId}  /  ${_platformName ?? '正在识别目标系统'}',
                  onClose: () => Navigator.of(context).pop(),
                  trailingActions: [
                    SizedBox(
                      width: math.min(
                        580,
                        math.max(72, constraints.maxWidth - 400),
                      ),
                      height: 34,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        reverse: true,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _MaintenanceToolbarMenu<
                              MachineTerminalCommandShell
                            >(
                              label: switch (_requestedShell) {
                                MachineTerminalCommandShell.automatic =>
                                  '自动识别 Shell',
                                MachineTerminalCommandShell.posix =>
                                  'POSIX Shell',
                                MachineTerminalCommandShell.powershell =>
                                  'PowerShell',
                                _ => 'CMD',
                              },
                              tooltip: '终端 Shell',
                              enabled: !_loading,
                              value: _requestedShell,
                              items: const {
                                MachineTerminalCommandShell.automatic:
                                    '自动识别 Shell',
                                MachineTerminalCommandShell.posix:
                                    'POSIX Shell',
                                MachineTerminalCommandShell.powershell:
                                    'PowerShell',
                                MachineTerminalCommandShell.cmd: 'CMD',
                              },
                              onSelected: (value) {
                                setState(() => _requestedShell = value);
                                _refresh();
                              },
                            ),
                            const SizedBox(width: 8),
                            _MaintenanceToolbarMenu<int>(
                              label: '$_intervalSeconds 秒',
                              tooltip: '自动刷新间隔',
                              icon: Icons.timer_outlined,
                              value: _intervalSeconds,
                              items: const {
                                5: '5 秒',
                                10: '10 秒',
                                30: '30 秒',
                                60: '60 秒',
                              },
                              onSelected: (value) {
                                setState(() => _intervalSeconds = value);
                                _schedule();
                              },
                            ),
                            const SizedBox(width: 8),
                            Container(
                              height: 34,
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              decoration: BoxDecoration(
                                color: (_error != null ? cs.error : cs.primary)
                                    .withValues(alpha: .08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                status,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: _error != null ? cs.error : cs.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _updated == null
                                  ? '等待首次采样'
                                  : '更新于 ${_updated!.toLocal().toString().substring(11, 19)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    _MachineTerminalIconButton(
                      icon: _automatic
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      tooltip: _automatic ? '暂停自动刷新' : '开启自动刷新（当前分区）',
                      onPressed: () {
                        setState(() => _automatic = !_automatic);
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
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: .6),
                    ),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: List.generate(_maintenanceTabs.length, (index) {
                        final selected = _tab == index;
                        return Padding(
                          padding: const EdgeInsets.all(4),
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: selected
                                  ? cs.primary
                                  : cs.onSurfaceVariant,
                              backgroundColor: selected
                                  ? cs.surfaceContainerLowest
                                  : Colors.transparent,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              side: selected
                                  ? BorderSide(
                                      color: cs.primary.withValues(alpha: .3),
                                    )
                                  : BorderSide.none,
                            ),
                            icon: Icon(
                              const [
                                Icons.dashboard_outlined,
                                Icons.memory_rounded,
                                Icons.settings_suggest_outlined,
                                Icons.hub_outlined,
                              ][index],
                              size: 18,
                            ),
                            label: Text(
                              _maintenanceTabs[index],
                              style: TextStyle(
                                fontWeight: selected
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                              ),
                            ),
                            onPressed: _loading
                                ? null
                                : () {
                                    setState(() {
                                      _tab = index;
                                      _page = 0;
                                      _search.clear();
                                      _error = null;
                                    });
                                    _refresh();
                                  },
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 2,
                child: _loading
                    ? const LinearProgressIndicator()
                    : Divider(
                        height: 1,
                        color: cs.outlineVariant.withValues(alpha: .5),
                      ),
              ),
              if (data != null &&
                  (_error != null || data.text('notice').isNotEmpty))
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                  child: _MaintenanceNotice(
                    message: _error == null
                        ? data.text('notice')
                        : '采集失败，已暂停自动重试；当前保留上次数据。$_error',
                    error: _error != null,
                  ),
                ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: motion.entranceDuration,
                  reverseDuration: motion.exitDuration,
                  switchInCurve: kOpenHandSwitchInCurve,
                  switchOutCurve: kOpenHandSwitchOutCurve,
                  child: KeyedSubtree(
                    key: ValueKey((_tab, data == null)),
                    child: data == null
                        ? _emptyState()
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
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      size: 14,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '当前终端 · 辅助命令不持久化 · 速率需两次采样',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _MaintenanceCard(
          title: _loading ? '正在连接当前终端' : '机器状态暂不可用',
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Icon(
                  _loading ? Icons.sensors_rounded : Icons.cloud_off_rounded,
                  size: 42,
                  color: _error == null ? cs.primary : cs.error,
                ),
                const SizedBox(height: 14),
                Text(
                  _loading ? '识别系统并读取运行状态' : '未能完成本次采集',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                Text(
                  _loading
                      ? '数据就绪后将显示资源、进程、服务与网络状态。'
                      : '请确认终端已连接并处于命令提示符，再重新采集。',
                  textAlign: TextAlign.center,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  _MaintenanceNotice(message: _error!, error: true),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _loading ? null : _refresh,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('重新采集'),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _MaintenanceGrid(
          minWidth: 220,
          maxColumns: 4,
          children: [
            for (final item in const [
              (Icons.memory_rounded, 'CPU'),
              (Icons.storage_rounded, '内存'),
              (Icons.dns_outlined, '磁盘'),
              (Icons.hub_outlined, '网络'),
            ])
              _metric(item.$2, '—', '等待目标机器数据', item.$1, cs.primary, null),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _showCollected(String title, String text) async {
    _detailOpen = true;
    _timer?.cancel();
    await showAnimatedDialog<void>(
      context: context,
      builder: (context) => buildOpenHandDialog(
        child: SizedBox(
          width: math.min(MediaQuery.sizeOf(context).width * .86, 900),
          height: MediaQuery.sizeOf(context).height * .7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MachineTerminalDialogHeader(
                icon: Icons.article_outlined,
                title: title,
                subtitle: '当前采样 · 完整原始内容',
                onClose: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: SingleChildScrollView(
                    child: _MaintenanceReadout(text: text),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    _detailOpen = false;
    if (mounted) _schedule();
  }

  void _selectSection(int index) {
    if (_loading) return;
    setState(() {
      _tab = index;
      _page = 0;
      _search.clear();
      _error = null;
    });
    _refresh();
  }

  Widget _overview(MachineMaintenanceSnapshot data) {
    final cs = Theme.of(context).colorScheme;
    final memory = data.memory;
    final total = memory['MemTotal'];
    final available = memory['MemAvailable'];
    final swap = memory['SwapTotal'];
    final freeSwap = memory['SwapFree'];
    final cpu = data.cpuUsage(_previous[0]);
    final memoryUsage = total != null && total > 0 && available != null
        ? (total - available) / total
        : null;
    final cores = data
        .counters('cpu')
        .keys
        .where((key) => RegExp(r'^cpu\d+$').hasMatch(key))
        .toList();
    final facts = _maintenanceFacts(data);
    final volumes = data
        .text('filesystems')
        .split('\n')
        .skip(1)
        .map((line) => line.trim().split(RegExp(r'\s+')))
        .where(
          (f) =>
              f.length >= 6 &&
              int.tryParse(f[1]) != null &&
              int.tryParse(f[2]) != null,
        )
        .toList();
    final warnings = <String>[
      if (cpu != null && cpu >= .85)
        'CPU 使用率较高：${(cpu * 100).toStringAsFixed(0)}%',
      if (memoryUsage != null && memoryUsage >= .85)
        '内存使用率较高：${(memoryUsage * 100).toStringAsFixed(0)}%',
    ];
    final visibleVolumes = volumes.where((v) {
      final mount = v.skip(5).join(' ');
      return !const ['devfs', 'tmpfs', 'devtmpfs'].contains(v.first) &&
          !mount.startsWith('/Library/Developer/CoreSimulator/') &&
          (!mount.startsWith('/System/Volumes/') ||
              mount == '/System/Volumes/Data');
    }).toList();
    final left = <Widget>[
      _MaintenanceCard(
        title: '资源使用',
        icon: Icons.memory_rounded,
        child: Column(
          children: [
            _MaintenanceUsage(label: 'CPU', value: cpu, color: cs.primary),
            _MaintenanceUsage(
              label: '内存',
              value: memoryUsage,
              color: cs.tertiary,
            ),
            _MaintenanceUsage(
              label: 'SWAP',
              value: swap != null && swap > 0 && freeSwap != null
                  ? (swap - freeSwap) / swap
                  : null,
              color: cs.secondary,
            ),
            const Divider(height: 18),
            _MaintenanceFacts(
              values: {
                '运行时间': facts['运行时间']!,
                '负载均衡': data
                    .text('load')
                    .split(RegExp(r'\s+'))
                    .take(3)
                    .join(' / '),
                '处理器': data.text('processor'),
              },
            ),
          ],
        ),
      ),
      _MaintenanceCard(
        title: '采样状态',
        icon: Icons.sensors_rounded,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MaintenanceStatus(
              label: _error != null ? '数据可能过期' : '采集成功',
              color: _error != null ? cs.error : cs.primary,
            ),
            const SizedBox(height: 10),
            _MaintenanceFacts(
              values: {
                '刷新方式': _automatic ? '自动 · $_intervalSeconds 秒' : '手动刷新',
                '趋势样本': '${_cpuHistory.length} / 60',
                '目标平台': facts['操作系统']!,
              },
            ),
            const SizedBox(height: 8),
            Text(
              '速率根据连续采样计算；不可用字段不作推断。',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
      if (cores.isNotEmpty)
        _MaintenanceCard(
          title: '每核负载',
          icon: Icons.grid_view_rounded,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final core in cores)
                _MaintenanceStatus(
                  label:
                      '$core · ${data.cpuUsage(_previous[0], core) == null ? '—' : '${(data.cpuUsage(_previous[0], core)! * 100).round()}%'}',
                  color: cs.primary,
                ),
            ],
          ),
        ),
    ];
    final center = <Widget>[
      _MaintenanceCard(
        title: '基本信息',
        icon: Icons.info_outline_rounded,
        onOpen: () => _showCollected('系统原始信息', data.text('system')),
        child: _MaintenanceFacts(
          values: {
            '主机名': facts['主机名']!,
            '操作系统': facts['操作系统']!,
            '系统版本': facts['系统版本']!,
            '内核版本': facts['内核版本']!,
            '逻辑处理器': facts['逻辑处理器']!,
          },
        ),
      ),
      _MaintenanceCard(
        title: '存储空间',
        icon: Icons.storage_rounded,
        onOpen: () => _showCollected('文件系统', data.text('filesystems')),
        child: visibleVolumes.isEmpty
            ? const Text('暂无可读的文件系统', style: TextStyle(fontSize: 12))
            : Column(
                children: [
                  for (final v in visibleVolumes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  v.skip(5).join(' '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(v[4], style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 5),
                          LinearProgressIndicator(
                            value:
                                ((double.tryParse(v[4].replaceAll('%', '')) ??
                                            0) /
                                        100)
                                    .clamp(0, 1),
                            minHeight: 5,
                            borderRadius: BorderRadius.circular(4),
                            color:
                                (double.tryParse(v[4].replaceAll('%', '')) ??
                                        0) >=
                                    85
                                ? cs.error
                                : cs.primary,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${formatByteSize(int.parse(v[2]) * 1024)} / ${formatByteSize(int.parse(v[1]) * 1024)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
      _MaintenanceCard(
        title: '网络吞吐',
        icon: Icons.swap_vert_rounded,
        onOpen: () => _showCollected('网卡详情', data.text('interfaces')),
        child: _rateTable(
          data,
          'network',
          const ['网卡', '接收 / 秒', '发送 / 秒'],
          const [0, 8],
          const [1, 1],
        ),
      ),
    ];
    final right = <Widget>[
      _MaintenanceCard(
        title: 'CPU 实时趋势',
        icon: Icons.show_chart_rounded,
        child: SizedBox(
          height: 94,
          child: _cpuHistory.length < 2
              ? Center(
                  child: Text(
                    _automatic ? '正在积累样本…' : '开启自动刷新后显示趋势',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                )
              : CustomPaint(
                  painter: _MaintenanceSparkline(
                    List.of(_cpuHistory),
                    cs.primary,
                  ),
                ),
        ),
      ),
      _MaintenanceCard(
        title: '运维操作',
        icon: Icons.tune_rounded,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final action in const [
              (1, Icons.memory_rounded, '查看进程'),
              (2, Icons.settings_suggest_outlined, '管理系统服务'),
              (3, Icons.hub_outlined, '网络诊断'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                  onPressed: _loading ? null : () => _selectSection(action.$1),
                  icon: Icon(action.$2, size: 16),
                  label: Text(action.$3, style: const TextStyle(fontSize: 12)),
                ),
              ),
          ],
        ),
      ),
      _MaintenanceCard(
        title: '资源提醒',
        icon: Icons.notifications_none_rounded,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MaintenanceStatus(
              label: warnings.isEmpty ? '暂无阈值提醒' : '${warnings.length} 项需关注',
              color: warnings.isEmpty ? cs.primary : cs.error,
            ),
            const SizedBox(height: 10),
            for (final warning in warnings.take(6))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  warning,
                  style: TextStyle(fontSize: 12, color: cs.error),
                ),
              ),
            Text(
              '依据当前 CPU 与内存采样，提醒阈值 85%；磁盘完整信息可在详情查看。',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _MaintenanceGrid(
          minWidth: 200,
          maxColumns: 4,
          children: [
            _metric(
              'CPU 使用率',
              cpu == null ? '—' : '${(cpu * 100).toStringAsFixed(1)}%',
              '${facts['逻辑处理器']} 个逻辑处理器',
              Icons.memory_rounded,
              cs.primary,
              cpu,
            ),
            _metric(
              '内存使用率',
              memoryUsage == null
                  ? '—'
                  : '${(memoryUsage * 100).toStringAsFixed(0)}%',
              total == null || available == null
                  ? '暂无数据'
                  : '${formatByteSize(total - available)} / ${formatByteSize(total)}',
              Icons.storage_rounded,
              cs.tertiary,
              memoryUsage,
            ),
            _metric(
              'SWAP 使用量',
              swap == null || freeSwap == null
                  ? '—'
                  : formatByteSize(swap - freeSwap),
              swap == 0
                  ? '未配置交换空间'
                  : '总量 ${swap == null ? '—' : formatByteSize(swap)}',
              Icons.swap_horiz_rounded,
              cs.secondary,
              swap != null && swap > 0 && freeSwap != null
                  ? (swap - freeSwap) / swap
                  : null,
            ),
            _metric(
              '运行时间',
              facts['运行时间']!,
              facts['操作系统']!,
              Icons.schedule_rounded,
              cs.primary,
              null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (_, constraints) {
            Widget stack(List<Widget> items) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: item,
                  ),
              ],
            );
            if (constraints.maxWidth <
                900 * MediaQuery.textScalerOf(context).scale(12) / 12) {
              return stack([...center, ...left, ...right]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 26, child: stack(left)),
                const SizedBox(width: 12),
                Expanded(flex: 44, child: stack(center)),
                const SizedBox(width: 12),
                Expanded(flex: 30, child: stack(right)),
              ],
            );
          },
        ),
        _MaintenanceCard(
          title: '更多系统指标',
          icon: Icons.dashboard_customize_outlined,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final key in const [
                'disks',
                'vm',
                'pressure',
                'memory',
                'memory_note',
                'memory_details',
                'kernel',
                'blocks',
                'interfaces',
                'inodes',
                'sensors',
                'cgroup_limits',
                'capabilities',
              ])
                if (data.text(key).isNotEmpty)
                  OutlinedButton(
                    onPressed: () => _showCollected(
                      _maintenanceSectionLabels[key] ?? key,
                      data.text(key),
                    ),
                    child: Text(
                      _maintenanceSectionLabels[key] ?? key,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _MaintenanceCard(
          title: '磁盘 IO',
          icon: Icons.speed_rounded,
          child: _rateTable(
            data,
            'disks',
            const ['设备', '读取 / 秒', '写入 / 秒', '读 IOPS', '写 IOPS'],
            const [2, 6, 0, 4],
            const [512, 512, 1, 1],
          ),
        ),
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .65)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .11),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 21, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 7),
                if (progress != null)
                  LinearProgressIndicator(
                    value: progress.clamp(0, 1),
                    color: color,
                    backgroundColor: color.withValues(alpha: .1),
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(4),
                  )
                else
                  const SizedBox(height: 4),
              ],
            ),
          ),
        ],
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        key: const ValueKey('运维进程列表'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 240,
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
                  width: 156,
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
                  '匹配 ${rows.length} 项 · 总数 ${countLine?.split('\t').last ?? '未知'}',
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: .6),
                ),
              ),
              child: LayoutBuilder(
                builder: (_, constraints) => SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: constraints.maxWidth,
                      ),
                      child: DataTable(
                        showCheckboxColumn: false,
                        columns: const [
                          DataColumn(label: Text('PID')),
                          DataColumn(label: Text('进程')),
                          DataColumn(label: Text('状态')),
                          DataColumn(label: Text('CPU / 单核')),
                          DataColumn(label: Text('驻留内存')),
                          DataColumn(label: Text('线程')),
                        ],
                        rows: rows
                            .skip(currentPage * 40)
                            .take(40)
                            .map(
                              (p) => DataRow(
                                onSelectChanged:
                                    !_platform!.canInspectProcess(p)
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
                                      child: Tooltip(
                                        message: p.name,
                                        child: Text(
                                          p.name
                                              .split('/')
                                              .last
                                              .split('\\')
                                              .last,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    _MaintenanceStatus(
                                      label: _maintenanceProcessState(p.state),
                                      color: p.state.startsWith('Z')
                                          ? Theme.of(context).colorScheme.error
                                          : Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                    ),
                                  ),
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
          ),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 4,
            children: [
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
                                (int.tryParse(
                                      countLine?.split('\t').last ?? '',
                                    ) ??
                                    0)
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
              Row(
                mainAxisSize: MainAxisSize.min,
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
            ],
          ),
        ],
      ),
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
    final cs = Theme.of(context).colorScheme;
    final manager = data.text('manager');
    String state(String line) {
      final fields = line.trim().split(RegExp(r'\s+'));
      if (manager == 'launchd') {
        return fields.length > 1 && int.tryParse(fields[1]) != null
            ? '运行中'
            : '未运行';
      }
      if (manager == 'Windows SCM') {
        final columns = line.split('\t');
        return columns.length > 1 ? columns[1] : '未知';
      }
      if (line.contains(' failed ')) return '异常';
      if (line.contains(' active ') || line.contains('[ started ]')) {
        return '运行中';
      }
      if (line.contains(' inactive ') || line.contains('[ stopped ]')) {
        return '未运行';
      }
      return '待检查';
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _MaintenanceGrid(
          minWidth: 210,
          children: [
            _metric(
              '已发现服务',
              '${rows.length}',
              manager,
              Icons.settings_suggest_outlined,
              cs.primary,
              null,
            ),
            _metric(
              '运行中',
              '${rows.where((line) => const ['运行中', 'Running'].contains(state(line))).length}',
              '当前可见服务',
              Icons.play_circle_outline,
              cs.tertiary,
              null,
            ),
            _metric(
              '异常服务',
              '${rows.where((line) => state(line) == '异常').length}',
              '仅统计明确报告失败的条目',
              Icons.error_outline,
              cs.error,
              null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            isDense: true,
            hintText: '筛选服务',
            prefixIcon: Icon(Icons.search_rounded, size: 18),
          ),
        ),
        const SizedBox(height: 12),
        _MaintenanceCard(
          title: '服务列表 · ${filtered.length} 项',
          icon: Icons.view_list_outlined,
          maxHeight: 420,
          child: SizedBox(
            height: math.min(410, MediaQuery.sizeOf(context).height * .43),
            child: ListView.builder(
              primary: false,
              itemCount: filtered.length,
              itemBuilder: (_, index) {
                final line = filtered[index];
                final name = line.contains('\t')
                    ? line.split('\t').first
                    : line.trim().split(RegExp(r'\s+')).first;
                final enabled = adapter?.accepts(name) ?? false;
                final status = state(line);
                return Container(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: .4),
                      ),
                    ),
                  ),
                  child: ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: Icon(
                      Icons.settings_suggest_outlined,
                      size: 19,
                      color: status == '异常' ? cs.error : cs.primary,
                    ),
                    title: Tooltip(
                      message: line,
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 90,
                          child: _MaintenanceStatus(
                            label: status,
                            color: status == '异常'
                                ? cs.error
                                : status == '未运行'
                                ? cs.onSurfaceVariant
                                : cs.primary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.chevron_right, size: 16),
                      ],
                    ),
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
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            for (final name in const ['startup', 'timers'])
              if (data.text(name).isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => _showCollected(
                    _maintenanceSectionLabels[name]!,
                    data.text(name),
                  ),
                  icon: const Icon(Icons.article_outlined, size: 16),
                  label: Text(_maintenanceSectionLabels[name]!),
                ),
          ],
        ),
      ],
    );
  }

  Widget _sections(MachineMaintenanceSnapshot data, List<String> names) {
    final cs = Theme.of(context).colorScheme;
    final connections = _maintenanceConnections(data);
    final dns = RegExp(
      r'(?:nameserver(?:\[\d+\])?\s*:?\s*|DNS Servers[^:]*:\s*)([a-fA-F0-9:.]+)',
    ).allMatches(data.text('dns')).map((m) => m[1]!).toSet().toList();
    final primary = _MaintenanceCard(
      title: '连接与监听端口',
      icon: Icons.hub_outlined,
      onOpen: () => _showCollected('连接与监听端口', data.text('sockets')),
      maxHeight: 470,
      child: connections.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(18),
              child: Text('未解析到 TCP / UDP 连接，可查看原始数据。'),
            )
          : LayoutBuilder(
              builder: (_, constraints) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('协议')),
                      DataColumn(label: Text('本地地址')),
                      DataColumn(label: Text('远端地址')),
                      DataColumn(label: Text('状态')),
                    ],
                    rows: [
                      for (final row in connections)
                        DataRow(
                          cells: [
                            for (final cell in row)
                              DataCell(
                                Tooltip(
                                  message: cell,
                                  child: SizedBox(
                                    width: cell == row.first ? 46 : 150,
                                    child: Text(
                                      cell,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
    final secondary = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MaintenanceCard(
          title: 'DNS 服务器',
          icon: Icons.language_rounded,
          onOpen: () => _showCollected('DNS 配置', data.text('dns')),
          child: dns.isEmpty
              ? const Text('暂无可解析的服务器地址', style: TextStyle(fontSize: 12))
              : _MaintenanceFacts(
                  values: {
                    for (var i = 0; i < dns.length; i++) '服务器 ${i + 1}': dns[i],
                  },
                ),
        ),
        const SizedBox(height: 12),
        _MaintenanceCard(
          title: '诊断项目',
          maxHeight: 360,
          icon: Icons.fact_check_outlined,
          child: Column(
            children: [
              for (final name in names.where(
                (name) => name != 'sockets' && name != 'dns',
              ))
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _maintenanceSectionIcon(name),
                    size: 18,
                    color: cs.primary,
                  ),
                  title: Text(
                    _maintenanceSectionLabels[name] ?? name,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    data.text(name).trim().isEmpty
                        ? '暂无数据'
                        : _maintenanceOutputStatus(data.text(name)),
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 16),
                  onTap: () => _showCollected(
                    _maintenanceSectionLabels[name] ?? name,
                    data.text(name),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _MaintenanceGrid(
          minWidth: 210,
          children: [
            _metric(
              '已解析连接',
              '${connections.length}',
              '当前采样中的 TCP / UDP',
              Icons.hub_outlined,
              cs.primary,
              null,
            ),
            _metric(
              'DNS 服务器',
              '${dns.length}',
              '解析自当前系统配置',
              Icons.language_rounded,
              cs.tertiary,
              null,
            ),
            _metric(
              '诊断项目',
              '${names.length}',
              '路由、日志、任务与安全',
              Icons.fact_check_outlined,
              cs.secondary,
              null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (_, constraints) => constraints.maxWidth < 850
              ? Column(
                  children: [primary, const SizedBox(height: 12), secondary],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 7, child: primary),
                    const SizedBox(width: 12),
                    Expanded(flex: 3, child: secondary),
                  ],
                ),
        ),
      ],
    );
  }
}

List<Widget> _sectionWidgets(
  MachineMaintenanceSnapshot data,
  List<String> names,
) => names
    .where(data.sections.containsKey)
    .map(
      (name) => _MaintenanceCard(
        title: _maintenanceSectionLabels[name] ?? name,
        child: _MaintenanceReadout(text: data.text(name)),
      ),
    )
    .toList();

Map<String, String> _maintenanceFacts(MachineMaintenanceSnapshot data) {
  final system = data.text('system');
  String field(String key) =>
      RegExp(
        '^${RegExp.escape(key)}\\s*[:=]\\s*(.+)\$',
        multiLine: true,
      ).firstMatch(system)?.group(1)?.trim().replaceAll('"', '') ??
      '';
  final platform = data.text('platform');
  final name = platform == 'Darwin' ? 'macOS' : platform;
  final kernel = platform == 'Darwin'
      ? RegExp('Darwin Kernel Version ([^:]+)').firstMatch(system)?.group(1)
      : platform == 'Linux'
      ? RegExp(
          r'^Linux\s+\S+\s+(\S+)',
          multiLine: true,
        ).firstMatch(system)?.group(1)
      : field('Version');
  final version = platform == 'Darwin'
      ? field('ProductVersion')
      : platform == 'Windows'
      ? field('Caption')
      : field('PRETTY_NAME');
  return {
    '主机名': data.text('host'),
    '操作系统': name,
    '系统版本': version.isEmpty ? '未提供' : version,
    '内核版本': kernel == null || kernel.isEmpty ? '未提供' : kernel,
    '逻辑处理器': data.text('core_count').isEmpty
        ? '${data.counters('cpu').keys.where((key) => RegExp(r'^cpu\d+$').hasMatch(key)).length}'
        : data.text('core_count'),
    '运行时间': data.uptime == null
        ? '—'
        : '${(data.uptime! / 86400).floor()} 天 ${(data.uptime! / 3600).floor() % 24} 小时',
  };
}

List<List<String>> _maintenanceConnections(MachineMaintenanceSnapshot data) {
  final rows = <List<String>>[];
  for (final line in data.text('sockets').split('\n')) {
    final fields = line.trim().split(RegExp(r'\s+'));
    if (fields.length < 4 ||
        !RegExp(
          r'^(tcp|udp)(?:4|6|46)?$',
          caseSensitive: false,
        ).hasMatch(fields[0])) {
      continue;
    }
    if (data.text('platform') == 'Windows') {
      rows.add([
        fields[0].toUpperCase(),
        fields[1],
        fields[2],
        fields[0].toLowerCase() == 'tcp' && fields.length > 4 ? fields[3] : '—',
      ]);
    } else if (fields.length >= 5 && int.tryParse(fields[1]) != null) {
      rows.add([
        fields[0].toUpperCase(),
        fields[3],
        fields[4],
        fields.length > 5 && fields[0].startsWith('tcp') ? fields[5] : '—',
      ]);
    } else if (fields.length >= 6) {
      rows.add([fields[0].toUpperCase(), fields[4], fields[5], fields[1]]);
    }
  }
  return rows;
}

String _maintenanceProcessState(String state) =>
    switch (state.isEmpty ? '' : state[0]) {
      'R' => '运行',
      'S' => '休眠',
      'I' => '空闲',
      'T' => '暂停',
      'Z' => '僵尸',
      'D' => 'IO 等待',
      _ => state,
    };

String _maintenanceOutputStatus(String text) =>
    RegExp(
      'permission denied|not permitted|could not|unavailable|not found|拒绝|不可用|未安装',
      caseSensitive: false,
    ).hasMatch(text)
    ? '部分不可用 · 查看原因'
    : '已采集 · 查看详情';

IconData _maintenanceSectionIcon(String name) => switch (name) {
  'routes' => Icons.route_outlined,
  'logs' => Icons.article_outlined,
  'users' => Icons.people_outline,
  'cron' => Icons.schedule_rounded,
  'firewall' => Icons.shield_outlined,
  'containers' => Icons.inventory_2_outlined,
  _ => Icons.analytics_outlined,
};

class _MaintenanceFacts extends StatelessWidget {
  const _MaintenanceFacts({required this.values});
  final Map<String, String> values;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final entry in values.entries)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: .35),
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 78,
                child: Text(
                  entry.key,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Tooltip(
                  message: entry.value,
                  child: Text(
                    entry.value.isEmpty ? '未提供' : entry.value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

class _MaintenanceStatus extends StatelessWidget {
  const _MaintenanceStatus({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 7, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _MaintenanceUsage extends StatelessWidget {
  const _MaintenanceUsage({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final double? value;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: LinearProgressIndicator(
            value: (value ?? 0).clamp(0, 1),
            minHeight: 5,
            color: color,
            backgroundColor: color.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        SizedBox(
          width: 42,
          child: Text(
            value == null ? '—' : '${(value! * 100).round()}%',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

class _MaintenanceGrid extends StatelessWidget {
  const _MaintenanceGrid({
    required this.children,
    this.minWidth = 360,
    this.maxColumns = 3,
  });
  final List<Widget> children;
  final double minWidth;
  final int maxColumns;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final columns = ((constraints.maxWidth + 12) / (minWidth * scale + 12))
          .floor()
          .clamp(1, maxColumns);
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class _MaintenanceToolbarMenu<T> extends StatelessWidget {
  const _MaintenanceToolbarMenu({
    required this.label,
    required this.tooltip,
    required this.value,
    required this.items,
    required this.onSelected,
    this.icon,
    this.enabled = true,
  });
  final String label, tooltip;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onSelected;
  final IconData? icon;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedPopupMenuButton<T>(
      tooltip: tooltip,
      enabled: enabled,
      initialValue: value,
      position: PopupMenuPosition.under,
      padding: EdgeInsets.zero,
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final item in items.entries)
          PopupMenuItem(value: item.key, child: Text(item.value)),
      ],
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: cs.surface.withValues(alpha: .72),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: .55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: enabled ? cs.onSurface : cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.expand_more_rounded,
              size: 16,
              color: cs.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _MaintenanceNotice extends StatelessWidget {
  const _MaintenanceNotice({required this.message, this.error = false});
  final String message;
  final bool error;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = error ? cs.error : cs.tertiary;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        border: Border.all(color: color.withValues(alpha: .18)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            error ? Icons.error_outline : Icons.info_outline,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 90),
              child: SingleChildScrollView(
                primary: false,
                child: Text(
                  message,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: color),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MaintenanceReadout extends StatelessWidget {
  const _MaintenanceReadout({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: SelectableText(
      text.isEmpty ? '暂无可用数据' : text,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 12,
        height: 1.65,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    ),
  );
}

class _MaintenanceCard extends StatelessWidget {
  const _MaintenanceCard({
    required this.title,
    required this.child,
    this.icon = Icons.analytics_outlined,
    this.onOpen,
    this.maxHeight = 280,
  });
  final String title;
  final Widget child;
  final IconData icon;
  final VoidCallback? onOpen;
  final double maxHeight;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .65)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            color: cs.surfaceContainerLow,
            child: Row(
              children: [
                Icon(icon, size: 16, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (onOpen != null)
                  Tooltip(
                    message: '查看详情',
                    child: InkWell(
                      onTap: onOpen,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: math.min(
                  maxHeight,
                  MediaQuery.sizeOf(context).height * .56,
                ),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: SingleChildScrollView(primary: false, child: child),
              ),
            ),
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
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
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
                child: _MaintenanceNotice(
                  message: _error ?? _result!,
                  error: _error != null,
                ),
              ),
            Expanded(
              child: _data == null
                  ? Center(child: Text(_busy ? '正在读取详情…' : '读取失败，请重试。'))
                  : ListView(
                      padding: const EdgeInsets.all(18),
                      children: [
                        _MaintenanceGrid(
                          children: _sectionWidgets(
                            _data!,
                            _data!.sections.keys
                                .where(
                                  (key) => !const [
                                    'platform',
                                    'host',
                                    'boot',
                                    'encoding',
                                    'uptime',
                                  ].contains(key),
                                )
                                .toList(),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
