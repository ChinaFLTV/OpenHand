part of '../openhand_home_page.dart';

const _maintenanceTabs = ['运行总览', '进程管理', '系统服务', '网络与诊断'];
const _maintenanceSectionLabels = {
  'system': '系统与内核',
  'disks': '磁盘 IO',
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
      _detailOpen = false,
      _closing = false;
  String? _error;
  DateTime? _updated;
  int _tab = 0, _sort = 0, _processOffset = 0;
  int _intervalSeconds = machineMaintenanceInterval.inSeconds;
  int _workers = machineMaintenanceDefaultWorkers;
  Object? _bodyIdentity;
  Widget? _body;
  final _collecting = ValueNotifier(false);

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
    _collecting.dispose();
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
        !_closing &&
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
        isCancelled: () => !mounted || _closing,
      );

  Future<void> _refresh() async {
    if (_loading || !mounted || _closing) return;
    _timer?.cancel();
    final tab = _tab;
    _collecting.value = true;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final target = parseMachineTerminalShellProbe(
        await _run(machineTerminalShellProbe, probe: true),
      );
      if (!mounted || _closing) return;
      if (_requestedShell != MachineTerminalCommandShell.automatic &&
          (_requestedShell == MachineTerminalCommandShell.posix) !=
              (target.platform != 'Windows')) {
        throw StateError(
          maintenanceLabel(context, '所选 Shell 与目标系统不匹配，请改为自动识别或实际使用的 Shell。'),
        );
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
        await _run(
          _platform!.collect(tab, offset: _processOffset, workers: _workers),
        ),
        previous: _snapshots[tab],
      );
      if (!mounted || _closing) return;
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
      if (mounted && !_closing && tab == _tab) {
        setState(() {
          _error = '$error';
        });
      }
    } finally {
      if (mounted && !_closing) {
        _collecting.value = false;
        setState(() {
          _loading = false;
        });
        if (tab != _tab) {
          unawaited(_refresh());
        } else {
          _schedule();
        }
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
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: cs.outlineVariant),
    );
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
    final dialog = buildOpenHandDialog(
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
          inputDecorationTheme: theme.inputDecorationTheme.copyWith(
            filled: true,
            fillColor: cs.surfaceContainerLow,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: inputBorder,
            enabledBorder: inputBorder,
            disabledBorder: inputBorder.copyWith(
              borderSide: BorderSide(
                color: cs.outlineVariant.withValues(alpha: .5),
              ),
            ),
            focusedBorder: inputBorder.copyWith(
              borderSide: BorderSide(color: cs.primary, width: 2),
            ),
            errorBorder: inputBorder.copyWith(
              borderSide: BorderSide(color: cs.error),
            ),
            focusedErrorBorder: inputBorder.copyWith(
              borderSide: BorderSide(color: cs.error, width: 2),
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
                builder: (_, constraints) {
                  final controls = SizedBox(
                    width: constraints.maxWidth < 900
                        ? constraints.maxWidth - 36
                        : math.min(
                            680,
                            math.max(72, constraints.maxWidth - 350),
                          ),
                    height: 34,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _MaintenanceToolbarMenu<MachineTerminalCommandShell>(
                            label: switch (_requestedShell) {
                              MachineTerminalCommandShell.automatic =>
                                '自动识别 Shell',
                              MachineTerminalCommandShell.posix =>
                                'POSIX Shell',
                              MachineTerminalCommandShell.powershell =>
                                'PowerShell',
                              _ => 'CMD',
                            },
                            tooltip: maintenanceLabel(context, '终端 Shell'),
                            enabled: !_loading,
                            value: _requestedShell,
                            items: const {
                              MachineTerminalCommandShell.automatic:
                                  '自动识别 Shell',
                              MachineTerminalCommandShell.posix: 'POSIX Shell',
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
                            label: AppLocalizations.of(
                              context,
                            )!.maintenanceSeconds('$_intervalSeconds'),
                            tooltip: maintenanceLabel(context, '自动刷新间隔'),
                            icon: Icons.timer_outlined,
                            value: _intervalSeconds,
                            items: {
                              3: AppLocalizations.of(
                                context,
                              )!.maintenanceSeconds('3'),
                              5: AppLocalizations.of(
                                context,
                              )!.maintenanceSeconds('5'),
                              10: AppLocalizations.of(
                                context,
                              )!.maintenanceSeconds('10'),
                              30: AppLocalizations.of(
                                context,
                              )!.maintenanceSeconds('30'),
                              60: AppLocalizations.of(
                                context,
                              )!.maintenanceSeconds('60'),
                            },
                            onSelected: (value) {
                              setState(() => _intervalSeconds = value);
                              _schedule();
                            },
                          ),
                          const SizedBox(width: 8),
                          _MaintenanceToolbarMenu<int>(
                            label: AppLocalizations.of(
                              context,
                            )!.maintenanceWorkers('$_workers'),
                            tooltip: AppLocalizations.of(
                              context,
                            )!.maintenanceWorkersHelp,
                            icon: Icons.account_tree_outlined,
                            enabled: !_loading,
                            value: _workers,
                            items: {
                              for (final count in const [1, 2, 4, 8])
                                count: AppLocalizations.of(
                                  context,
                                )!.maintenanceWorkers('$count'),
                            },
                            onSelected: (value) =>
                                setState(() => _workers = value),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            height: 34,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: (_error != null ? cs.error : cs.primary)
                                  .withValues(alpha: .08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              maintenanceLabel(context, status),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: _error != null ? cs.error : cs.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            maintenanceLabel(
                              context,
                              _updated == null
                                  ? '等待首次采样'
                                  : AppLocalizations.of(
                                      context,
                                    )!.maintenanceUpdated(
                                      _updated!.toLocal().toString().substring(
                                        11,
                                        19,
                                      ),
                                    ),
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                  return Column(
                    children: [
                      _MachineTerminalDialogHeader(
                        icon: Icons.dns_rounded,
                        title: maintenanceLabel(context, '服务器运维中心'),
                        subtitle:
                            '${data?.text('host') ?? widget.terminalId}  /  ${_platformName ?? maintenanceLabel(context, '正在识别目标系统')}',
                        onClose: () => Navigator.of(context).pop(),
                        trailingActions: [
                          if (constraints.maxWidth >= 900) controls,
                          _MachineTerminalIconButton(
                            icon: _automatic
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            tooltip: maintenanceLabel(
                              context,
                              _automatic ? '暂停自动刷新' : '开启自动刷新（当前分区）',
                            ),
                            onPressed: () {
                              setState(() => _automatic = !_automatic);
                              _schedule();
                            },
                          ),
                          _MachineTerminalIconButton(
                            icon: Icons.refresh_rounded,
                            tooltip: maintenanceLabel(context, '刷新当前分区'),
                            onPressed: _loading ? null : _refresh,
                          ),
                        ],
                      ),
                      if (constraints.maxWidth < 900)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: controls,
                          ),
                        ),
                    ],
                  );
                },
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
                              maintenanceLabel(
                                context,
                                _maintenanceTabs[index],
                              ),
                              style: TextStyle(
                                fontWeight: selected
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                              ),
                            ),
                            onPressed: () {
                              if (_tab == index) return;
                              setState(() {
                                _tab = index;

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
                child: _loading && data != null
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
                        : AppLocalizations.of(
                            context,
                          )!.maintenanceCollectionErrorDetail(_error!),
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
                    key: ValueKey((
                      _tab,
                      data == null,
                      data == null && _error != null,
                    )),
                    child: _content(data, theme, size, motion),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) return;
        _closing = true;
        _timer?.cancel();
      },
      child: dialog,
    );
  }

  Widget _content(
    MachineMaintenanceSnapshot? data,
    ThemeData theme,
    Size size,
    Object motion,
  ) {
    final identity = (
      _tab,
      data,
      _sort,
      _search.text,
      _processOffset,
      _automatic,
      _intervalSeconds,
      theme,
      size,
      Localizations.localeOf(context),
      motion,
      data == null ? (_loading, _error) : null,
    );
    if (_bodyIdentity != identity) {
      _bodyIdentity = identity;
      _body = data == null
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
            };
    }
    return _body!;
  }

  Widget _emptyState() {
    final theme = Theme.of(context);
    final failed = _error != null;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (failed)
                Icon(
                  Icons.cloud_off_rounded,
                  size: 36,
                  color: theme.colorScheme.error,
                )
              else
                SizedBox.square(
                  dimension: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    semanticsLabel: maintenanceLabel(context, '采集中'),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                maintenanceLabel(context, failed ? '机器状态暂不可用' : '采集中'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall,
              ),
              if (failed) ...[
                const SizedBox(height: 10),
                Text(
                  maintenanceLabel(context, '请确认终端已连接并处于命令提示符，再重新采集。'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                _MaintenanceNotice(message: _error!, error: true),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _loading ? null : _refresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(maintenanceLabel(context, '重新采集')),
                ),
              ],
            ],
          ),
        ),
      ),
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
                title: maintenanceLabel(context, title),
                subtitle: maintenanceLabel(context, '已采集 · 查看详情'),
                onClose: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: SingleChildScrollView(
                    child: _MaintenanceReadout(
                      text: text,
                      section:
                          _maintenanceSectionLabels.entries
                              .where((entry) => entry.value == title)
                              .firstOrNull
                              ?.key ??
                          (title == '文件系统'
                              ? 'filesystems'
                              : title == '网卡详情'
                              ? 'interfaces'
                              : 'system'),
                    ),
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
    if (data.uptime != null) {
      facts['运行时间'] = AppLocalizations.of(context)!.maintenanceDuration(
        '${(data.uptime! / 86400).floor()}',
        '${(data.uptime! / 3600).floor() % 24}',
      );
    }
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
        AppLocalizations.of(
          context,
        )!.maintenanceCpuAlert((cpu * 100).toStringAsFixed(0)),
      if (memoryUsage != null && memoryUsage >= .85)
        AppLocalizations.of(
          context,
        )!.maintenanceMemoryAlert((memoryUsage * 100).toStringAsFixed(0)),
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
        title: maintenanceLabel(context, '资源使用'),
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
        title: maintenanceLabel(context, '采样状态'),
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
                '刷新方式': _automatic
                    ? AppLocalizations.of(
                        context,
                      )!.maintenanceAutoInterval('$_intervalSeconds')
                    : maintenanceLabel(context, '手动刷新'),
                '趋势样本': '${_cpuHistory.length} / 60',
                '目标平台': facts['操作系统']!,
              },
            ),
            const SizedBox(height: 8),
            Text(
              maintenanceLabel(context, '速率根据连续采样计算；不可用字段不作推断。'),
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
      if (cores.isNotEmpty)
        _MaintenanceCard(
          title: maintenanceLabel(context, '每核负载'),
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
        title: maintenanceLabel(context, '基本信息'),
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
        title: maintenanceLabel(context, '存储空间'),
        icon: Icons.storage_rounded,
        onOpen: () => _showCollected('文件系统', data.text('filesystems')),
        child: visibleVolumes.isEmpty
            ? Text(
                maintenanceLabel(context, '暂无可读的文件系统'),
                style: const TextStyle(fontSize: 12),
              )
            : Column(
                children: [
                  for (final v in visibleVolumes)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            v.skip(5).join(' '),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          _MaintenanceUsage(
                            label: '存储空间',
                            value:
                                (double.tryParse(v[4].replaceAll('%', '')) ??
                                    0) /
                                100,
                            color: cs.primary,
                          ),
                          _MaintenanceValue(
                            value:
                                '${formatByteSize(int.parse(v[2]) * 1024)} / ${formatByteSize(int.parse(v[1]) * 1024)}',
                            style: TextStyle(
                              fontSize: 12,
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
        title: maintenanceLabel(context, '网络吞吐'),
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
        title: maintenanceLabel(context, 'CPU 实时趋势'),
        icon: Icons.show_chart_rounded,
        child: SizedBox(
          height: 94,
          child: _cpuHistory.length < 2
              ? Center(
                  child: Text(
                    maintenanceLabel(
                      context,
                      _automatic ? '正在积累样本…' : '开启自动刷新后显示趋势',
                    ),
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
        title: maintenanceLabel(context, '资源提醒'),
        icon: Icons.notifications_none_rounded,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MaintenanceStatus(
              label: warnings.isEmpty
                  ? '暂无阈值提醒'
                  : AppLocalizations.of(
                      context,
                    )!.maintenanceAlertCount('${warnings.length}'),
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
              maintenanceLabel(
                context,
                '依据当前 CPU 与内存采样，提醒阈值 85%；磁盘完整信息可在详情查看。',
              ),
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
              AppLocalizations.of(
                context,
              )!.maintenanceCpuCount(facts['逻辑处理器']!),
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
                  : AppLocalizations.of(context)!.maintenanceTotal(
                      swap == null ? '—' : formatByteSize(swap),
                    ),
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
          title: maintenanceLabel(context, '磁盘 IO'),
          icon: Icons.speed_rounded,
          child: _rateTable(
            data,
            'disks',
            const ['设备', '读取 / 秒', '写入 / 秒', '读 IOPS', '写 IOPS'],
            const [2, 6, 0, 4],
            const [512, 512, 1, 1],
          ),
        ),
        for (final section in const [
          'disks',
          'memory',
          'memory_details',
          'vm',
          'pressure',
          'kernel',
          'blocks',
          'interfaces',
          'inodes',
          'sensors',
          'cgroup_limits',
          'capabilities',
        ])
          if (data.text(section).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _MaintenanceCard(
                title: maintenanceLabel(
                  context,
                  section == 'disks'
                      ? '磁盘累计计数'
                      : _maintenanceSectionLabels[section] ?? section,
                ),
                icon: switch (section) {
                  'disks' || 'blocks' || 'inodes' => Icons.storage_rounded,
                  'memory' || 'memory_details' || 'vm' => Icons.memory_rounded,
                  'interfaces' => Icons.lan_outlined,
                  'pressure' || 'sensors' => Icons.monitor_heart_outlined,
                  _ => Icons.tune_rounded,
                },
                scrollBody: false,
                child: _MaintenanceMetricContent(data: data, section: section),
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
                  maintenanceLabel(context, title),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 5),
                _MaintenanceNumber(
                  raw: value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  maintenanceLabel(context, subtitle),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 7),
                if (progress != null)
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(
                      begin: progress.clamp(0, 1),
                      end: progress.clamp(0, 1),
                    ),
                    duration: openHandMotionDuration(
                      context,
                      kOpenHandMotion260,
                    ),
                    curve: kOpenHandSwitchInCurve,
                    builder: (_, value, _) => LinearProgressIndicator(
                      value: value.clamp(0, 1),
                      color: color,
                      backgroundColor: color.withValues(alpha: .1),
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(4),
                    ),
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
    if (keys.isEmpty) return Text(maintenanceLabel(context, '当前环境未提供可用计数器。'));
    return _MaintenanceTable(
      headers: headings,
      rows: [
        for (final key in keys)
          OpenHandOperationalRankRow(
            value: 0,
            rowKey: key,
            cells: [
              data.text('platform') == 'Windows'
                  ? Uri.decodeComponent(key)
                  : key,
              for (var i = 0; i < indexes.length; i++)
                _maintenanceRateLabel(
                  data.rate(
                    _previous[0],
                    section,
                    key,
                    indexes[i],
                    multiplier: multipliers[i],
                  ),
                  bytes: i < 2,
                ),
            ],
          ),
      ],
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
    final countLine = data
        .text('processes')
        .split('\n')
        .where((line) => line.startsWith('__COUNT__'))
        .firstOrNull;
    final total =
        int.tryParse(countLine?.split('\t').last ?? '') ??
        data.processes.length;
    final summary = ValueListenableBuilder<bool>(
      valueListenable: _collecting,
      builder: (context, collecting, _) => _MaintenanceToolbarMenu<int>(
        label: '${rows.length} / $total',
        tooltip: AppLocalizations.of(
          context,
        )!.maintenanceMatched('${rows.length}', '$total'),
        icon: Icons.filter_list_rounded,
        value: _processOffset,
        enabled: !collecting && total > machineMaintenanceProcessLimit,
        items: {
          for (
            var offset = 0;
            offset < total;
            offset += machineMaintenanceProcessLimit
          )
            offset:
                '${offset + 1}–${math.min(offset + machineMaintenanceProcessLimit, total)} / $total',
        },
        onSelected: (offset) {
          if (_loading || offset == _processOffset) return;
          setState(() => _processOffset = offset);
          _refresh();
        },
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        key: const ValueKey('运维进程列表'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: LayoutBuilder(
              builder: (_, constraints) {
                final filters = Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 240,
                      child: TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: maintenanceLabel(context, '搜索 PID 或进程名'),
                          prefixIcon: const Icon(Icons.search_rounded),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 156,
                      child: AnimatedDropdownButtonFormField<int>(
                        value: _sort,
                        decoration: const InputDecoration(isDense: true),
                        items: [
                          DropdownMenuItem(
                            value: 0,
                            child: Text(maintenanceLabel(context, 'CPU 降序')),
                          ),
                          DropdownMenuItem(
                            value: 1,
                            child: Text(maintenanceLabel(context, '内存降序')),
                          ),
                          DropdownMenuItem(
                            value: 2,
                            child: Text(maintenanceLabel(context, 'PID 升序')),
                          ),
                        ],
                        onChanged: (value) => setState(() {
                          _sort = value!;
                        }),
                      ),
                    ),
                  ],
                );
                if (constraints.maxWidth <
                    720 * MediaQuery.textScalerOf(context).scale(12) / 12) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      filters,
                      const SizedBox(height: 8),
                      Align(alignment: Alignment.centerRight, child: summary),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: filters),
                    const SizedBox(width: 12),
                    summary,
                  ],
                );
              },
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (_, constraints) => SingleChildScrollView(
                child: _MaintenanceTable(
                  key: ValueKey((_search.text, _sort, _processOffset)),
                  limitToViewport: false,
                  maxBodyHeight: math.max(
                    100,
                    constraints.maxHeight -
                        (constraints.maxWidth < 720 ? 148 : 96),
                  ),
                  headers: const ['PID', '进程', '状态', 'CPU / 单核', '驻留内存', '线程'],
                  rows: [
                    for (final p in rows)
                      OpenHandOperationalRankRow(
                        value: 0,
                        rowKey: (p.pid, p.startToken),
                        data: p,
                        cells: [
                          '${p.pid}',
                          p.name.split('/').last.split('\\').last,
                          maintenanceLabel(
                            context,
                            _maintenanceProcessState(p.state),
                          ),
                          cpu(p) == null
                              ? '—'
                              : '${cpu(p)!.toStringAsFixed(1)}%',
                          pageSize == null || p.residentPages < 0
                              ? maintenanceLabel(context, '不可用')
                              : formatByteSize(p.residentPages * pageSize),
                          p.threads < 0 ? '—' : '${p.threads}',
                        ],
                        cellWidgets: [
                          null,
                          Tooltip(
                            message: p.name,
                            child: Text(
                              p.name.split('/').last.split('\\').last,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          _MaintenanceStatus(
                            label: _maintenanceProcessState(p.state),
                            color: p.state.startsWith('Z')
                                ? Theme.of(context).colorScheme.error
                                : Theme.of(context).colorScheme.primary,
                          ),
                        ],
                      ),
                  ],
                  onRowTap: (row) {
                    final p = row.data! as MachineMaintenanceProcess;
                    if (!_platform!.canInspectProcess(p)) return;
                    _details(
                      AppLocalizations.of(
                        context,
                      )!.maintenanceProcessTitle('${p.pid}', p.name),
                      _platform!.process(p),
                      actions: {
                        for (final action
                            in _platform!.processActions(p).entries)
                          action.key: _platform!.process(
                            p,
                            action: action.value,
                          ),
                      },
                    );
                  },
                ),
              ),
            ),
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
        LayoutBuilder(
          builder: (context, constraints) {
            final height = math.max(
              42.0,
              MediaQuery.textScalerOf(context).scale(14) + 24,
            );
            final search = SizedBox(
              height: height,
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  hintText: maintenanceLabel(context, '筛选服务'),
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                ),
              ),
            );
            final buttons = [
              for (final name in const ['startup', 'timers'])
                if (data.text(name).isNotEmpty)
                  SizedBox(
                    height: height,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.standard,
                      ),
                      onPressed: () => _showCollected(
                        _maintenanceSectionLabels[name]!,
                        data.text(name),
                      ),
                      icon: const Icon(Icons.article_outlined, size: 16),
                      label: Text(
                        maintenanceLabel(
                          context,
                          _maintenanceSectionLabels[name]!,
                        ),
                      ),
                    ),
                  ),
            ];
            if (buttons.isEmpty) return search;
            final actions = Wrap(
              alignment: WrapAlignment.end,
              spacing: 10,
              runSpacing: 8,
              children: buttons,
            );
            if (constraints.maxWidth <
                720 * MediaQuery.textScalerOf(context).scale(14) / 14) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  search,
                  const SizedBox(height: 10),
                  Align(alignment: Alignment.centerRight, child: actions),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: search),
                const SizedBox(width: 12),
                actions,
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        _MaintenanceCard(
          title: maintenanceLabel(
            context,
            AppLocalizations.of(
              context,
            )!.maintenanceServiceCount('${filtered.length}'),
          ),
          icon: Icons.view_list_outlined,
          maxHeight: 420,
          child: _MaintenanceTable(
            key: ValueKey(_search.text),
            maxBodyHeight: 360,
            headers: const ['名称', '状态', '状态详情'],
            rows: [
              for (final line in filtered)
                OpenHandOperationalRankRow(
                  value: 0,
                  rowKey: line.contains('\t')
                      ? line.split('\t').first
                      : line.trim().split(RegExp(r'\s+')).first,
                  data: line,
                  cells: [
                    line.contains('\t')
                        ? line.split('\t').first
                        : line.trim().split(RegExp(r'\s+')).first,
                    maintenanceLabel(context, state(line)),
                    line,
                  ],
                  cellWidgets: [
                    null,
                    _MaintenanceStatus(
                      label: state(line),
                      color: state(line) == '异常' ? cs.error : cs.primary,
                    ),
                  ],
                ),
            ],
            onRowTap: (row) {
              final name = row.cells.first;
              if (!(adapter?.accepts(name) ?? false)) return;
              _details(
                name,
                adapter!.command(name),
                actions: {
                  for (final action in adapter.actions.entries)
                    action.key: adapter.command(name, action.value),
                },
              );
            },
          ),
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
      title: maintenanceLabel(context, '连接与监听端口'),
      icon: Icons.hub_outlined,
      onOpen: () => _showCollected('连接与监听端口', data.text('sockets')),
      maxHeight: 470,
      child: connections.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                maintenanceLabel(context, '未解析到 TCP / UDP 连接，可查看原始数据。'),
              ),
            )
          : _MaintenanceTable(
              maxBodyHeight: 360,
              headers: const ['协议', '本地地址', '远端地址', '状态'],
              rows: [
                for (final row in connections)
                  OpenHandOperationalRankRow(
                    value: 0,
                    cells: [
                      row[0],
                      row[1],
                      row[2],
                      maintenanceLabel(context, row[3]),
                    ],
                  ),
              ],
            ),
    );
    final secondary = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MaintenanceCard(
          title: maintenanceLabel(context, 'DNS 服务器'),
          icon: Icons.language_rounded,
          onOpen: () => _showCollected('DNS 配置', data.text('dns')),
          child: dns.isEmpty
              ? Text(
                  maintenanceLabel(context, '暂无可解析的服务器地址'),
                  style: const TextStyle(fontSize: 12),
                )
              : _MaintenanceFacts(
                  values: {
                    for (var i = 0; i < dns.length; i++)
                      AppLocalizations.of(
                        context,
                      )!.maintenanceServerNumber('${i + 1}'): dns[i],
                  },
                ),
        ),
        const SizedBox(height: 12),
        _MaintenanceCard(
          title: maintenanceLabel(context, '诊断项目'),
          maxHeight: 360,
          icon: Icons.fact_check_outlined,
          child: Column(
            children: [
              for (final name in names.where(
                (name) => name != 'sockets' && name != 'dns',
              ))
                ListTile(
                  hoverColor: Colors.transparent,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.fact_check_outlined,
                    color: cs.primary,
                    size: 20,
                  ),
                  title: Text(
                    maintenanceLabel(
                      context,
                      _maintenanceSectionLabels[name] ?? name,
                    ),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    maintenanceLabel(
                      context,
                      data.text(name).trim().isEmpty
                          ? '暂无数据'
                          : _maintenanceOutputStatus(data.text(name)),
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded, size: 18),
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
        child: _MaintenanceReadout(text: data.text(name), section: name),
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
  final readout = MachineMaintenanceReadout.parse(
    data.text('sockets'),
    'sockets',
  );
  return readout.fields ? [] : readout.rows;
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

String _maintenanceRateLabel(double? rate, {required bool bytes}) =>
    rate == null
    ? '—'
    : bytes
    ? '${formatByteSize(rate)}/s'
    : rate.toStringAsFixed(1);

class _MaintenanceMetricContent extends StatefulWidget {
  const _MaintenanceMetricContent({required this.data, required this.section});
  final MachineMaintenanceSnapshot data;
  final String section;

  @override
  State<_MaintenanceMetricContent> createState() =>
      _MaintenanceMetricContentState();
}

class _MaintenanceMetricContentState extends State<_MaintenanceMetricContent> {
  Object? _identity;
  Widget? _content;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final section = widget.section;
    final identity = (
      section,
      data.text(section),
      data.text('platform'),
      data.text('memory_note'),
      Theme.of(context),
      Localizations.localeOf(context),
    );
    if (_identity == identity) return _content!;
    _identity = identity;
    final metrics = MachineMaintenanceMetrics.parse(data, section);
    return _content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (section == 'memory' && data.text('memory_note').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(maintenanceLabel(context, '可用内存包含可回收页，具体统计口径因系统而异。')),
          ),
        for (var t = 0; t < metrics.tables.length; t++)
          if (metrics.tables[t].rows.isEmpty)
            Text(maintenanceLabel(context, '暂无可用数据'))
          else if (section == 'capabilities')
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final row in metrics.tables[t].rows)
                  Tooltip(
                    message: maintenanceMetricLabel(context, row.first, '类型'),
                    child: Chip(
                      avatar: Icon(
                        Icons.check_circle_outline_rounded,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      label: Text(row.last),
                    ),
                  ),
              ],
            )
          else if (metrics.tables[t].headers.contains('数值') ||
              section == 'pressure')
            _MaintenanceMetricTiles(
              key: ValueKey((section, t)),
              table: metrics.tables[t],
              section: section,
              pressure: metrics.tables[t].headers.contains('10 秒平均'),
            )
          else
            _MaintenanceTable(
              key: ValueKey((section, t)),
              headers: metrics.tables[t].headers,
              rows: [
                for (var r = 0; r < metrics.tables[t].rows.length; r++)
                  OpenHandOperationalRankRow(
                    value: 0,
                    rowKey: '$section:$t:$r',
                    cells: [
                      for (var c = 0; c < metrics.tables[t].rows[r].length; c++)
                        maintenanceMetricLabel(
                          context,
                          metrics.tables[t].rows[r][c],
                          metrics.tables[t].headers[c],
                        ),
                    ],
                  ),
              ],
            ),
        if (metrics.unparsed > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              maintenanceLabel(context, '部分字段未识别或不可用，已显示可解析的指标。'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _MaintenanceMetricTiles extends StatelessWidget {
  const _MaintenanceMetricTiles({
    super.key,
    required this.table,
    this.section,
    this.pressure = false,
  });
  final MachineMaintenanceMetricTable table;
  final String? section;
  final bool pressure;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context);
    return _MaintenanceGrid(
      minWidth: pressure ? 280 : 200,
      maxColumns: pressure ? 3 : 5,
      children: [
        for (final row in table.rows)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: .45),
              ),
            ),
            child: pressure
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${maintenanceMetricLabel(context, row[0], '资源')} · ${maintenanceMetricLabel(context, row[1], '范围')}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      for (var i = 2; i < 5; i++) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                maintenanceLabel(context, table.headers[i]),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                            _MaintenanceValue(value: row[i]),
                          ],
                        ),
                        const SizedBox(height: 5),
                        TweenAnimationBuilder<double>(
                          tween: Tween(
                            end:
                                ((double.tryParse(row[i].replaceAll('%', '')) ??
                                            0) /
                                        100)
                                    .clamp(0, 1),
                          ),
                          duration: openHandMotionDuration(
                            context,
                            kOpenHandMotion260,
                          ),
                          curve: kOpenHandSwitchInCurve,
                          builder: (_, value, _) => LinearProgressIndicator(
                            value: value.clamp(0, 1),
                            color: switch (row.first) {
                              'memory' => cs.secondary,
                              'io' => cs.tertiary,
                              _ => cs.primary,
                            },
                            borderRadius: BorderRadius.circular(8),
                            backgroundColor: cs.surfaceContainerHighest,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        maintenanceLabel(context, table.headers.last),
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      _MaintenanceNumber(
                        raw: row.last,
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  )
                : Builder(
                    builder: (context) {
                      final unit = row.length > 2 ? row[2] : '—';
                      final number = num.tryParse(row[1]);
                      final multiplier = const {
                        'B': 1,
                        'KiB': 1024,
                        'MiB': 1048576,
                      }[unit];
                      final value =
                          number != null && multiplier != null && number >= 0
                          ? formatByteSize(
                              number * multiplier,
                              languageCode: locale.languageCode,
                              scriptCode: locale.scriptCode,
                              countryCode: locale.countryCode,
                            )
                          : '${maintenanceMetricLabel(context, row[1], '数值')}${unit == '—' || number == null ? '' : ' ${maintenanceMetricLabel(context, unit, '单位')}'}';
                      return Tooltip(
                        message: row.join(' · '),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              maintenanceMetricLabel(
                                context,
                                row.first,
                                '名称',
                                section: section,
                              ),
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _MaintenanceNumber(
                              raw: row[1],
                              unit: unit == '—'
                                  ? ''
                                  : maintenanceMetricLabel(context, unit, '单位'),
                              readable: multiplier != null ? value : null,
                              maxLines: 2,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: cs.primary,
                              ),
                            ),
                            if (row.length > 3) ...[
                              const SizedBox(height: 6),
                              Text(
                                row[3],
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
      ],
    );
  }
}

class _MaintenanceTable extends StatelessWidget {
  const _MaintenanceTable({
    super.key,
    required this.headers,
    required this.rows,
    this.onRowTap,
    this.maxBodyHeight = 220,
    this.limitToViewport = true,
  });
  final List<String> headers;
  final List<OpenHandOperationalRankRow> rows;
  final ValueChanged<OpenHandOperationalRankRow>? onRowTap;
  final double maxBodyHeight;
  final bool limitToViewport;
  @override
  Widget build(BuildContext context) => OpenHandOperationalRankTable(
    headers: headers.map((label) => maintenanceLabel(context, label)).toList(),
    rows: [
      for (final row in rows)
        OpenHandOperationalRankRow(
          cells: row.cells,
          value: row.value,
          rowKey: row.rowKey,
          subtitle: row.subtitle,
          cellSubtitles: row.cellSubtitles,
          data: row.data,
          cellWidgets: [
            for (var i = 0; i < row.cells.length; i++)
              if (row.cellWidgets != null &&
                  i < row.cellWidgets!.length &&
                  row.cellWidgets![i] != null)
                row.cellWidgets![i]
              else if (i < headers.length &&
                  const {
                    '累计读取次数',
                    '累计写入次数',
                    '累计读取字节',
                    '累计写入字节',
                    '累计读取耗时',
                    '累计写入耗时',
                    '已用 inode',
                    '可用 inode',
                    '接收字节',
                    '发送字节',
                    '读取字节',
                    '写入字节',
                    '线程',
                    '读 IOPS',
                    '写 IOPS',
                    '次数',
                    '页数',
                    '数值',
                  }.contains(headers[i]))
                _MaintenanceNumber(
                  raw: row.cells[i],
                  unit: headers[i].contains('字节') ? 'B' : '',
                )
              else
                null,
          ],
        ),
    ],
    sortByValue: false,
    animateCellChanges: true,
    onRowTap: onRowTap,
    maxBodyHeight: limitToViewport
        ? math.min(maxBodyHeight, MediaQuery.sizeOf(context).height * .45)
        : maxBodyHeight,
    emptyLabel: maintenanceLabel(context, '暂无可用数据'),
    semanticsLabel: headers
        .map((label) => maintenanceLabel(context, label))
        .join(' · '),
    columnAlignments: {
      for (var i = 0; i < headers.length; i++) i: Alignment.centerLeft,
    },
  );
}

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
                  maintenanceLabel(context, entry.key),
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
                  child: _MaintenanceValue(
                    value: entry.value.isEmpty || entry.value == '未提供'
                        ? maintenanceLabel(context, '未提供')
                        : entry.value,
                    maxLines: 2,
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
              maintenanceLabel(context, label),
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

/// 完整数值始终使用采样原文，避免大整数经浮点换算后丢失精度。
class _MaintenanceNumber extends StatefulWidget {
  const _MaintenanceNumber({
    required this.raw,
    this.unit = '',
    this.readable,
    this.style,
    this.maxLines = 1,
  });
  final String raw;
  final String unit;
  final String? readable;
  final TextStyle? style;
  final int maxLines;
  @override
  State<_MaintenanceNumber> createState() => _MaintenanceNumberState();
}

class _MaintenanceNumberState extends State<_MaintenanceNumber> {
  bool _exact = false;

  @override
  Widget build(BuildContext context) {
    final match = RegExp(
      r'^(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\s*(.*)$',
    ).firstMatch(widget.raw);
    final number = match == null ? null : double.tryParse(match[1]!);
    final unit = widget.unit.isNotEmpty ? widget.unit : match?[2] ?? '';
    final raw = widget.unit.isEmpty
        ? widget.raw
        : '${widget.raw} ${widget.unit}';
    var readable = widget.readable ?? raw;
    if (widget.readable == null && number != null && number.isFinite) {
      var scaled = number;
      var suffix = unit;
      if (unit == 'B') {
        final locale = Localizations.localeOf(context);
        readable = formatByteSize(
          number,
          languageCode: locale.languageCode,
          scriptCode: locale.scriptCode,
          countryCode: locale.countryCode,
        );
      } else {
        if (unit == 'ms' && number.abs() >= 1000) {
          scaled /= 1000;
          suffix = 's';
          if (scaled.abs() >= 60) {
            scaled /= 60;
            suffix = 'min';
          }
          if (suffix == 'min' && scaled.abs() >= 60) {
            scaled /= 60;
            suffix = 'h';
          }
          if (suffix == 'h' && scaled.abs() >= 24) {
            scaled /= 24;
            suffix = 'd';
          }
        } else if (number.abs() >= 1000) {
          const prefixes = ['', 'k', 'M', 'G', 'T', 'P', 'E'];
          var index = 0;
          while (scaled.abs() >= 999.95 && index < prefixes.length - 1) {
            scaled /= 1000;
            index++;
          }
          suffix = '${prefixes[index]}${unit.isEmpty ? '' : ' $unit'}';
        }
        if (scaled != number) {
          var digits = scaled
              .toStringAsFixed(1)
              .replaceFirst(RegExp(r'\.0$'), '');
          if (const [
            'fr',
            'de',
          ].contains(Localizations.localeOf(context).languageCode)) {
            digits = digits.replaceAll('.', ',');
          }
          readable =
              '$digits${const ['s', 'min', 'h', 'd'].contains(suffix) ? ' ' : ''}$suffix';
        }
      }
    }
    final value = _MaintenanceValue(
      value: _exact ? raw : readable,
      style: widget.style,
      maxLines: widget.maxLines,
    );
    if (readable == raw) return value;
    final l10n = AppLocalizations.of(context)!;
    return Tooltip(
      message:
          '${_exact ? l10n.maintenanceShowReadableValue : l10n.maintenanceShowExactValue} · ${_exact ? readable : raw}',
      child: Semantics(
        button: true,
        label: _exact
            ? l10n.maintenanceShowReadableValue
            : l10n.maintenanceShowExactValue,
        child: InkWell(
          hoverColor: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _exact = !_exact),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: value,
          ),
        ),
      ),
    );
  }
}

class _MaintenanceValue extends StatelessWidget {
  const _MaintenanceValue({
    required this.value,
    this.style,
    this.maxLines = 1,
    this.alignment = Alignment.centerLeft,
  });
  final String value;
  final TextStyle? style;
  final int maxLines;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: openHandMotionDuration(context, kOpenHandMotion260),
    switchInCurve: kOpenHandSwitchInCurve,
    switchOutCurve: kOpenHandSwitchOutCurve,
    layoutBuilder: (current, previous) =>
        Stack(alignment: alignment, children: [...previous, ?current]),
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(
          begin: .97,
          end: 1,
        ).chain(CurveTween(curve: kOpenHandEntranceCurve)).animate(animation),
        child: child,
      ),
    ),
    child: Text(
      value,
      key: ValueKey(value),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: style,
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
          child: Text(
            maintenanceLabel(context, label),
            style: const TextStyle(fontSize: 12),
          ),
        ),
        Expanded(
          child: TweenAnimationBuilder<double>(
            tween: Tween(
              begin: (value ?? 0).clamp(0, 1),
              end: (value ?? 0).clamp(0, 1),
            ),
            duration: openHandMotionDuration(context, kOpenHandMotion260),
            curve: kOpenHandSwitchInCurve,
            builder: (_, progress, _) => LinearProgressIndicator(
              value: progress.clamp(0, 1),
              minHeight: 5,
              color: color,
              backgroundColor: color.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        SizedBox(
          width: 42,
          child: _MaintenanceValue(
            value: value == null ? '—' : '${(value! * 100).round()}%',
            alignment: Alignment.centerRight,
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
      tooltip: maintenanceLabel(context, tooltip),
      enabled: enabled,
      initialValue: value,
      position: PopupMenuPosition.under,
      padding: EdgeInsets.zero,
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final item in items.entries)
          PopupMenuItem(
            value: item.key,
            child: Text(maintenanceLabel(context, item.value)),
          ),
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
              maintenanceLabel(context, label),
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

class _MaintenanceReadout extends StatefulWidget {
  const _MaintenanceReadout({required this.text, this.section = ''});
  final String text;
  final String section;
  @override
  State<_MaintenanceReadout> createState() => _MaintenanceReadoutState();
}

class _MaintenanceReadoutState extends State<_MaintenanceReadout> {
  late MachineMaintenanceReadout _data;
  @override
  void initState() {
    super.initState();
    _data = MachineMaintenanceReadout.parse(widget.text, widget.section);
  }

  @override
  void didUpdateWidget(covariant _MaintenanceReadout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.section != widget.section) {
      _data = MachineMaintenanceReadout.parse(widget.text, widget.section);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_data.rows.isEmpty) return Text(maintenanceLabel(context, '暂无可用数据'));
    if (!_data.fields) {
      return _MaintenanceTable(
        headers: _data.headers
            .map((label) => maintenanceDetailLabel(context, label))
            .toList(),
        rows: [
          for (var i = 0; i < _data.rows.length; i++)
            OpenHandOperationalRankRow(
              rowKey: i,
              value: 0,
              cells: [
                for (var c = 0; c < _data.rows[i].length; c++)
                  _data.headers[c] == '名称'
                      ? maintenanceDetailLabel(context, _data.rows[i][c])
                      : _data.rows[i][c],
              ],
            ),
        ],
        maxBodyHeight: 480,
      );
    }
    return _MaintenanceGrid(
      minWidth: 220,
      children: [
        for (final row in _data.rows)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tooltip(
                  message: row.first,
                  child: Text(
                    maintenanceDetailLabel(context, row.first),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                const SizedBox(height: 8),
                if (const ['io', 'memory'].contains(widget.section) &&
                    num.tryParse(row.last.split(' ').first) != null)
                  _MaintenanceNumber(raw: row.last, maxLines: 3)
                else
                  SelectableText(
                    maintenanceDetailValue(context, row.last),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MaintenanceCard extends StatelessWidget {
  const _MaintenanceCard({
    required this.title,
    required this.child,
    this.icon = Icons.analytics_outlined,
    this.onOpen,
    this.maxHeight = 280,
    this.scrollBody = true,
  });
  final String title;
  final Widget child;
  final IconData icon;
  final VoidCallback? onOpen;
  final double maxHeight;
  final bool scrollBody;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
      ),
      foregroundDecoration: BoxDecoration(
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
                    maintenanceLabel(context, title),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (onOpen != null)
                  Tooltip(
                    message: maintenanceLabel(context, '查看详情'),
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
            child: !scrollBody || child is _MaintenanceTable
                ? child
                : ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: math.min(
                        maxHeight,
                        MediaQuery.sizeOf(context).height * .56,
                      ),
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      child: SingleChildScrollView(
                        primary: false,
                        child: child,
                      ),
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
      title: maintenanceLabel(context, action.key),
      confirmLabel: maintenanceLabel(context, '确认执行'),
      destructive: true,
      message: maintenanceLabel(
        context,
        AppLocalizations.of(context)!.maintenanceConfirmAction(
          widget.title,
          maintenanceLabel(context, action.key),
        ),
      ),
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
          _result = action.key;
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
            LayoutBuilder(
              builder: (context, constraints) => _MachineTerminalDialogHeader(
                icon: Icons.analytics_outlined,
                title: widget.title,
                subtitle: maintenanceLabel(context, '实时详情 · 部分字段需要更高权限'),
                onClose: () => Navigator.of(context).pop(),
                trailingActions: [
                  if (widget.actions.isNotEmpty)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: math.max(100, constraints.maxWidth - 330),
                      ),
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          for (final action in widget.actions.entries)
                            Tooltip(
                              message: maintenanceLabel(context, action.key),
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 34),
                                  maximumSize: const Size(180, 34),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.standard,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                onPressed: _busy ? null : () => _act(action),
                                child: Text(
                                  maintenanceLabel(context, action.key),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  _MachineTerminalIconButton(
                    icon: Icons.refresh_rounded,
                    tooltip: maintenanceLabel(context, '刷新详情'),
                    onPressed: _busy ? null : _load,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 2, 18, 12),
              child: SizedBox(
                height: 3,
                child: _busy
                    ? LinearProgressIndicator(
                        borderRadius: BorderRadius.circular(3),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            if (_error != null || _result != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: _MaintenanceNotice(
                  message:
                      _error ??
                      AppLocalizations.of(context)!.maintenanceActionDone(
                        maintenanceLabel(context, _result!),
                      ),
                  error: _error != null,
                ),
              ),
            Expanded(
              child: _data == null
                  ? Center(
                      child: Text(
                        maintenanceLabel(
                          context,
                          _busy ? '正在读取详情…' : '读取失败，请重试。',
                        ),
                      ),
                    )
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
