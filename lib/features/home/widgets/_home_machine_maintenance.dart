part of '../openhand_home_page.dart';

const _maintenanceControlHeight = 34.0;
const _maintenancePanelBottomInset = 8.0;

const _maintenanceTabs = ['运行总览', '进程管理', '系统服务', '网络与诊断', 'GPU 管理', '日志管理'];
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
  final _logBuffers = <String, MachineLogBuffer>{};
  final _gpuHistory = <String, List<({double time, double value})>>{};
  final _cpuHistory = <({double time, double value})>[];
  final _search = TextEditingController();
  Timer? _timer;
  MachineMaintenancePlatformAdapter? _platform;
  String? _platformName;
  ({MachineTerminalCommandShell shell, String platform})? _detectedTarget;
  MachineTerminalCommandShell _commandShell = MachineTerminalCommandShell.posix;
  MachineTerminalCommandShell _requestedShell =
      MachineTerminalCommandShell.automatic;
  bool _loading = false,
      _manualRefresh = false,
      _automatic = false,
      _foreground = true,
      _detailOpen = false,
      _closing = false;
  String? _error;
  String? _shellLabel;
  int _tab = 0, _sort = 0;
  int _intervalSeconds = machineMaintenanceInterval.inSeconds;
  int _workers = machineMaintenanceDefaultWorkers;
  Object? _bodyIdentity;
  Widget? _body;

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
        !_closing &&
        _automatic &&
        _foreground &&
        !_loading &&
        !_detailOpen &&
        _error == null) {
      _timer = startSafeTimer(
        Duration(seconds: _intervalSeconds),
        () => _refresh(detectShell: false),
      );
    }
  }

  Future<String> _run(
    String command, {
    bool probe = false,
    MachineTerminalCommandShell? shell,
  }) => context.read<MachineTerminalFileService>().runMaintenanceCommand(
    sessionId: widget.sessionId,
    terminalId: widget.terminalId,
    command: command,
    windowsScript:
        !probe && shell == null && (_platform?.windowsScript ?? false),
    commandShell:
        shell ?? (probe ? MachineTerminalCommandShell.probe : _commandShell),
    isCancelled: () => !mounted || _closing,
  );

  Future<void> _refresh({bool manual = false, bool detectShell = true}) async {
    if (_loading || !mounted || _closing) return;
    _timer?.cancel();
    final tab = _tab;
    setState(() {
      _loading = true;
      _manualRefresh = manual;
      _error = null;
    });
    try {
      final target = detectShell || _detectedTarget == null
          ? parseMachineTerminalShellProbe(
              await _run(machineTerminalShellProbe, probe: true),
            )
          : _detectedTarget!;
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
      }
      if (detectShell ||
          _shellLabel == null ||
          _platformName != target.platform) {
        _shellLabel = parseMachineTerminalShellDetails(
          await _run(
            machineTerminalShellDetailsCommand(target.shell),
            shell: target.shell,
          ),
          target.shell,
        );
        if (!mounted || _closing) return;
      }
      _detectedTarget = target;
      _platformName = target.platform;
      _platform = MachineMaintenancePlatformAdapter.forPlatform(
        target.platform,
      );
      _commandShell = _requestedShell == MachineTerminalCommandShell.automatic
          ? target.shell
          : _requestedShell;
      final result = MachineMaintenanceSnapshot.parse(
        await _run(_platform!.collect(tab, workers: _workers)),
        previous: _snapshots[tab],
      );
      if (!mounted || _closing) return;
      setState(() {
        final old = _snapshots[tab];
        if (old != null) _previous[tab] = old;
        _snapshots[tab] = result;
        if (tab == 5) {
          if (old?.identity != result.identity) _logBuffers.clear();
          for (final source in machineLogSources) {
            _logBuffers
                .putIfAbsent(source, MachineLogBuffer.new)
                .append(
                  result.sections['log_$source'] ?? '',
                  eventLog: result.sections['platform']?.trim() == 'Windows',
                );
          }
        }
        if (tab == 4) {
          if (old?.identity != result.identity) _gpuHistory.clear();
          final devices = MachineGpuSnapshot.parse(result.sections).devices;
          final ids = devices.map((device) => device.id).toSet();
          _gpuHistory.removeWhere((id, _) => !ids.contains(id));
          for (final device in devices) {
            final utilization = device.metrics['util'];
            if (utilization == null) {
              _gpuHistory.remove(device.id);
              continue;
            }
            final history = _gpuHistory.putIfAbsent(device.id, () => []);
            history.add((
              time: DateTime.now().millisecondsSinceEpoch.toDouble(),
              value: utilization / 100,
            ));
            if (history.length > 60) history.removeAt(0);
          }
        }
        if (tab == 0) {
          if (old?.identity != result.identity) _cpuHistory.clear();
          final cpu = result.cpuUsage(old);
          if (cpu != null && cpu.isFinite) {
            _cpuHistory.add((
              time: DateTime.now().millisecondsSinceEpoch.toDouble(),
              value: cpu.clamp(0, 1),
            ));
          }
          if (_cpuHistory.length > 60) _cpuHistory.removeAt(0);
        }
      });
    } catch (error) {
      _detectedTarget = null;
      if (mounted && !_closing && tab == _tab) {
        setState(() {
          _error = '$error';
        });
      }
    } finally {
      if (mounted && !_closing) {
        setState(() {
          _loading = false;
          _manualRefresh = false;
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
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            isDense: true,
            constraints: const BoxConstraints.tightFor(
              height: _maintenanceControlHeight,
            ),
            prefixIconConstraints: const BoxConstraints.tightFor(
              width: _maintenanceControlHeight,
              height: _maintenanceControlHeight,
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
                    height: _maintenanceControlHeight,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _MaintenanceToolbarMenu<MachineTerminalCommandShell>(
                            label: switch (_requestedShell) {
                              MachineTerminalCommandShell.automatic =>
                                _shellLabel ?? '自动识别 Shell',
                              MachineTerminalCommandShell.posix =>
                                'POSIX Shell',
                              MachineTerminalCommandShell.powershell =>
                                'PowerShell',
                              _ => 'CMD',
                            },
                            tooltip: maintenanceLabel(context, '终端 Shell'),
                            enabled: !_loading,
                            value: _requestedShell,
                            items: {
                              MachineTerminalCommandShell.automatic:
                                  _shellLabel ?? '自动识别 Shell',
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
                            onPressed: _loading
                                ? null
                                : () => _refresh(manual: true),
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
                              minimumSize: const Size(
                                0,
                                _maintenanceControlHeight,
                              ),
                              maximumSize: const Size(
                                double.infinity,
                                _maintenanceControlHeight,
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.standard,
                              foregroundColor: selected
                                  ? cs.primary
                                  : cs.onSurfaceVariant,
                              backgroundColor: selected
                                  ? cs.surfaceContainerLowest
                                  : Colors.transparent,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
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
                                Icons.developer_board_rounded,
                                Icons.article_outlined,
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
                child: _loading && _manualRefresh && data != null
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
                child: Padding(
                  padding: const EdgeInsets.only(
                    bottom: _maintenancePanelBottomInset,
                  ),
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
              4 => _gpu(data),
              5 => _MaintenanceLogBrowser(buffers: _logBuffers, data: data),
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
                const SizedBox(height: 16),
                _MaintenanceNotice(message: _error!, error: true),
                const SizedBox(height: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, _maintenanceControlHeight),
                    maximumSize: const Size(
                      double.infinity,
                      _maintenanceControlHeight,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: _loading ? null : () => _refresh(manual: true),
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
        maxHeight: MediaQuery.sizeOf(context).height * .7,
        child: SizedBox(
          width: math.min(MediaQuery.sizeOf(context).width * .86, 900),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MachineTerminalDialogHeader(
                icon: Icons.article_outlined,
                title: maintenanceLabel(context, title),
                onClose: () => Navigator.of(context).pop(),
              ),
              Flexible(
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
            Wrap(
              spacing: 16,
              runSpacing: 16,
              alignment: WrapAlignment.center,
              children: [
                _MaintenanceGauge(label: 'CPU', value: cpu, color: cs.primary),
                _MaintenanceGauge(
                  label: maintenanceLabel(context, '内存'),
                  value: memoryUsage,
                  color: cs.tertiary,
                ),
                _MaintenanceGauge(
                  label: 'SWAP',
                  value: swap != null && swap > 0 && freeSwap != null
                      ? (swap - freeSwap) / swap
                      : null,
                  color: cs.secondary,
                ),
              ],
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
      if (total != null && total > 0 && available != null)
        _MaintenanceCard(
          title: AppLocalizations.of(context)!.maintenanceMemoryShare,
          icon: Icons.donut_large_rounded,
          child: _MaintenanceVisual(
            donut: true,
            centerLabel: formatByteSize(total),
            segments: [
              OpenHandChartSegment(
                label: AppLocalizations.of(context)!.maintenanceUsed,
                value: (total - available).clamp(0, total),
                color: cs.primary,
                valueLabel: formatByteSize((total - available).clamp(0, total)),
              ),
              OpenHandChartSegment(
                label: AppLocalizations.of(context)!.maintenanceAvailable,
                value: available.clamp(0, total),
                color: cs.tertiary,
                valueLabel: formatByteSize(available.clamp(0, total)),
              ),
            ],
          ),
        ),

      _MaintenanceCard(
        title: maintenanceLabel(context, 'CPU 实时趋势'),
        icon: Icons.show_chart_rounded,
        child: SizedBox(
          height: 190,
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
              : _MaintenanceTrend(points: List.of(_cpuHistory)),
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
            if (warnings.isNotEmpty) const SizedBox(height: 10),
            for (final warning in warnings.take(6))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  warning,
                  style: TextStyle(fontSize: 12, color: cs.error),
                ),
              ),
          ],
        ),
      ),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    maintenanceLabel(context, subtitle),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
                if (progress != null) const SizedBox(height: 7),
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
    final cs = Theme.of(context).colorScheme;
    final samples = <OpenHandChartSegment>[];
    for (final key in keys) {
      for (var i = 0; i < 2; i++) {
        final value = data.rate(
          _previous[0],
          section,
          key,
          indexes[i],
          multiplier: multipliers[i],
        );
        if (value != null && value.isFinite && value >= 0) {
          samples.add(
            OpenHandChartSegment(
              label:
                  '${data.text('platform') == 'Windows' ? Uri.decodeComponent(key) : key} · ${maintenanceLabel(context, headings[i + 1])}',
              value: value,
              color: i == 0 ? cs.primary : cs.tertiary,
              valueLabel: _maintenanceRateLabel(value, bytes: true),
            ),
          );
        }
      }
    }
    samples.sort((a, b) => b.value.compareTo(a.value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (samples.isNotEmpty) ...[
          _MaintenanceVisual(
            segments: samples.take(_maintenanceChartLimit).toList(),
          ),
          const SizedBox(height: 12),
        ],
        _MaintenanceTable(
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
        ),
      ],
    );
  }

  Widget _gpu(MachineMaintenanceSnapshot data) {
    final gpu = MachineGpuSnapshot.parse(data.sections);
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final labels = {
      'util': l10n.maintenanceGpuUtil,
      'memoryUsed': l10n.maintenanceGpuMemoryUsed,
      'memoryTotal': l10n.maintenanceGpuMemoryTotal,
      'temperature': l10n.maintenanceGpuTemperature,
      'power': l10n.maintenanceGpuPower,
      'powerLimit': l10n.maintenanceGpuPowerLimit,
      'coreClock': l10n.maintenanceGpuCoreClock,
      'memoryClock': l10n.maintenanceGpuMemoryClock,
      'fan': l10n.maintenanceGpuFan,
      'fanRpm': l10n.maintenanceGpuFanRpm,
      'renderer': l10n.maintenanceGpuRenderer,
      'tiler': l10n.maintenanceGpuTiler,
      'sharedUsed': l10n.maintenanceGpuSharedUsed,
      'sharedAllocated': l10n.maintenanceGpuSharedAllocated,
      'recoveries': l10n.maintenanceGpuRecoveries,
      'cores': l10n.maintenanceGpuCores,
    };
    String value(MachineGpuDevice device, String key) {
      final n = device.metrics[key];
      if (n == null) return '—';
      if ([
        'memoryUsed',
        'memoryTotal',
        'sharedUsed',
        'sharedAllocated',
      ].contains(key)) {
        return formatByteSize(n.round());
      }
      final unit = switch (key) {
        'util' || 'fan' || 'renderer' || 'tiler' => '%',
        'temperature' => ' °C',
        'power' || 'powerLimit' => ' W',
        'coreClock' || 'memoryClock' => ' MHz',
        'fanRpm' => ' RPM',
        _ => '',
      };
      return '${n == n.roundToDouble() ? n.toInt() : n.toStringAsFixed(1)}$unit';
    }

    if (gpu.devices.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l10n.maintenanceGpuEmpty),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      children: [
        for (final device in gpu.devices) ...[
          _MaintenanceCard(
            title: device.name,
            scrollBody: false,
            icon: Icons.developer_board_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MaintenanceGrid(
                  minWidth: 190,
                  maxColumns: 4,
                  children: [
                    for (final key in [
                      'util',
                      device.metrics.containsKey('sharedUsed')
                          ? 'sharedUsed'
                          : 'memoryUsed',
                      device.metrics.containsKey('renderer')
                          ? 'renderer'
                          : 'temperature',
                      device.metrics.containsKey('cores') ? 'cores' : 'power',
                    ])
                      _metric(
                        labels[key]!,
                        value(device, key),
                        '',
                        switch (key) {
                          'util' => Icons.speed_rounded,
                          'memoryUsed' => Icons.memory_rounded,
                          'temperature' => Icons.thermostat_rounded,
                          _ => Icons.bolt_rounded,
                        },
                        key == 'temperature' ? cs.tertiary : cs.primary,
                        key == 'util'
                            ? (device.metrics[key] == null
                                  ? null
                                  : device.metrics[key]! / 100)
                            : null,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _MaintenanceGrid(
                  minWidth: 280,
                  children: [
                    _MaintenanceCard(
                      title: l10n.maintenanceGpuTrend,
                      icon: Icons.show_chart_rounded,
                      child: SizedBox(
                        height: 190,
                        child: (_gpuHistory[device.id]?.length ?? 0) >= 2
                            ? _MaintenanceTrend(
                                key: ValueKey(device.id),
                                points: List.of(_gpuHistory[device.id]!),
                              )
                            : Center(child: Text(value(device, 'util'))),
                      ),
                    ),
                    if ((device.metrics['memoryTotal'] ?? 0) > 0 &&
                        device.metrics['memoryUsed'] != null)
                      _MaintenanceCard(
                        title: l10n.maintenanceGpuMemoryUsed,
                        icon: Icons.pie_chart_outline_rounded,
                        child: _MaintenanceVisual(
                          donut: true,
                          segments: [
                            OpenHandChartSegment(
                              label: l10n.maintenanceGpuMemoryUsed,
                              value: device.metrics['memoryUsed']!.clamp(
                                0,
                                device.metrics['memoryTotal']!,
                              ),
                              valueLabel: value(device, 'memoryUsed'),
                              color: cs.primary,
                            ),
                            OpenHandChartSegment(
                              label: l10n.maintenanceGpuMemoryFree,
                              value: math.max(
                                0,
                                device.metrics['memoryTotal']! -
                                    device.metrics['memoryUsed']!,
                              ),
                              color: cs.secondary,
                            ),
                          ],
                        ),
                      ),
                    _MaintenanceFacts(
                      values: {
                        'UUID / ID': device.id,
                        l10n.maintenanceGpuSource: device.source,
                        for (final entry in device.info.entries)
                          switch (entry.key) {
                            'vendor' => l10n.maintenanceGpuVendor,
                            'driver' => l10n.maintenanceGpuDriver,
                            'bus' => l10n.maintenanceGpuBus,
                            'state' => maintenanceLabel(context, '状态'),
                            _ => 'Metal',
                          }: maintenanceDetailValue(
                            context,
                            entry.value,
                          ),
                        for (final entry in device.metrics.entries)
                          labels[entry.key] ?? entry.key: value(
                            device,
                            entry.key,
                          ),
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (gpu.processes.isNotEmpty) ...[
          _MaintenanceCard(
            title: l10n.maintenanceGpuProcesses,
            icon: Icons.account_tree_outlined,
            child: _MaintenanceTable(
              headers: [
                'GPU UUID',
                'PID',
                maintenanceLabel(context, '进程'),
                l10n.maintenanceGpuMemoryUsed,
              ],
              rows: [
                for (final row in gpu.processes)
                  OpenHandOperationalRankRow(
                    value: 0,
                    cells: [
                      ...row.take(3),
                      MachineGpuSnapshot.number(row[3]) == null
                          ? '—'
                          : formatByteSize(
                              (MachineGpuSnapshot.number(row[3])! * 1048576)
                                  .round(),
                            ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (gpu.displays.isNotEmpty)
          _MaintenanceCard(
            title: l10n.maintenanceGpuDisplays,
            icon: Icons.monitor_rounded,
            child: _MaintenanceTable(
              headers: [
                'GPU',
                maintenanceLabel(context, '名称'),
                l10n.maintenanceGpuPixels,
                l10n.maintenanceGpuResolution,
              ],
              rows: [
                for (final row in gpu.displays)
                  OpenHandOperationalRankRow(value: 0, cells: row),
              ],
            ),
          ),
      ],
    );
  }

  Widget _processes(MachineMaintenanceSnapshot data) {
    final query = _search.text.trim().toLowerCase();
    final rows = data.processes.toList();
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
    final cs = Theme.of(context).colorScheme;
    final cpuRank = rows.where((p) => cpu(p) != null).toList()
      ..sort((a, b) => cpu(b)!.compareTo(cpu(a)!));
    final memoryRank = rows.where((p) => p.residentPages >= 0).toList()
      ..sort((a, b) => b.residentPages.compareTo(a.residentPages));
    final charts = _MaintenanceGrid(
      minWidth: 300,
      children: [
        _MaintenanceCard(
          title: AppLocalizations.of(context)!.maintenanceCpuRank,
          icon: Icons.bar_chart_rounded,
          child: _MaintenanceVisual(
            segments: [
              for (final p in cpuRank.take(_maintenanceChartLimit))
                OpenHandChartSegment(
                  label: '${p.pid} · ${p.name.split('/').last}',
                  value: cpu(p)!,
                  valueLabel: '${cpu(p)!.toStringAsFixed(1)}%',
                  color: cs.primary,
                ),
            ],
          ),
        ),
        _MaintenanceCard(
          title: AppLocalizations.of(context)!.maintenanceMemoryRank,
          icon: Icons.stacked_bar_chart_rounded,
          child: _MaintenanceVisual(
            segments: [
              if (pageSize != null && pageSize > 0)
                for (final p in memoryRank.take(_maintenanceChartLimit))
                  OpenHandChartSegment(
                    label: '${p.pid} · ${p.name.split('/').last}',
                    value: p.residentPages * pageSize,
                    valueLabel: formatByteSize(p.residentPages * pageSize),
                    color: cs.tertiary,
                  ),
            ],
          ),
        ),
      ],
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
                final search = SizedBox(
                  width: math.min(240, constraints.maxWidth),
                  child: TextField(
                    controller: _search,
                    style: const TextStyle(fontSize: 13, height: 1.2),
                    textAlignVertical: TextAlignVertical.center,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: maintenanceLabel(context, '搜索 PID 或进程名'),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    ),
                  ),
                );
                final sort = _MaintenanceToolbarMenu<int>(
                  label: const ['CPU 降序', '内存降序', 'PID 升序'][_sort],
                  tooltip: const ['CPU 降序', '内存降序', 'PID 升序'][_sort],
                  value: _sort,
                  items: const {0: 'CPU 降序', 1: '内存降序', 2: 'PID 升序'},
                  onSelected: (value) => setState(() => _sort = value),
                );
                if (constraints.maxWidth <
                    420 * MediaQuery.textScalerOf(context).scale(12) / 12) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(alignment: Alignment.centerLeft, child: search),
                      const SizedBox(height: 10),
                      Align(alignment: Alignment.centerRight, child: sort),
                    ],
                  );
                }
                return Row(children: [search, const Spacer(), sort]);
              },
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (_, constraints) => SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    charts,
                    const SizedBox(height: 12),
                    _MaintenanceBrowser(
                      query: query,
                      nameColumn: 1,
                      parents: {
                        for (final p in rows) '${p.pid}': ['${p.parent}'],
                      },
                      table: _MaintenanceTable(
                        limitToViewport: false,
                        maxBodyHeight: math.max(
                          100,
                          constraints.maxHeight -
                              (constraints.maxWidth < 720 ? 148 : 96),
                        ),
                        headers: const [
                          'PID',
                          '进程',
                          '状态',
                          'CPU / 单核',
                          '驻留内存',
                          '线程',
                          '父进程 ID',
                          '优先级',
                          '虚拟内存',
                          '累计 CPU 时间',
                        ],
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
                                    : formatByteSize(
                                        p.residentPages * pageSize,
                                      ),
                                p.threads < 0 ? '—' : '${p.threads}',
                                '${p.parent}',
                                '${p.nice}',
                                p.virtualBytes < 0
                                    ? '—'
                                    : formatByteSize(p.virtualBytes),
                                ticksPerSecond == null ||
                                        ticksPerSecond <= 0 ||
                                        p.ticks < 0
                                    ? '—'
                                    : '${(p.ticks / ticksPerSecond).toStringAsFixed(2)} s',
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
                  ],
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
    final startup = <String, String>{
      for (final line in data.text('startup').split('\n'))
        if (line.trim().split(RegExp(r'\s+')).length >= 2)
          line.trim().split(RegExp(r'\s+')).first: line.trim().split(
            RegExp(r'\s+'),
          )[1],
    };
    final serviceMetrics = <String, Map<String, String>>{};
    for (final block
        in data.text('service_metrics').split(RegExp(r'\n\s*\n'))) {
      final values = <String, String>{};
      for (final line in block.split('\n')) {
        final separator = line.indexOf('=');
        if (separator > 0) {
          values[line.substring(0, separator)] = line.substring(separator + 1);
        }
      }
      if (values['Id'] case final String name) {
        serviceMetrics[name] = values;
      }
    }
    final serviceHeaders = switch (manager) {
      'systemd' => const [
        '名称',
        '状态',
        '加载状态',
        '子状态',
        '启动方式',
        '描述',
        'PID',
        '内存',
        '累计 CPU 时间',
        '任务数',
        '重启次数',
        '退出代码',
      ],
      'launchd' => const ['名称', '状态', 'PID', '退出代码'],
      'Windows SCM' => const [
        '名称',
        '状态',
        '描述',
        '启动方式',
        'PID',
        '用户',
        '退出代码',
        '路径',
      ],
      _ => const ['名称', '状态', '状态详情'],
    };
    List<String> serviceCells(String line, String status) {
      final fields = line.trim().split(RegExp(r'\s+'));
      final columns = line.split('\t');
      final name = columns.length > 1 ? columns.first : fields.first;
      if (manager == 'systemd') {
        final metrics = serviceMetrics[name] ?? const <String, String>{};
        String counter(
          String key, {
          bool bytes = false,
          bool duration = false,
        }) {
          final value = int.tryParse(metrics[key] ?? '');
          if (value == null || value < 0 || value >= 9223372036854775807) {
            return '—';
          }
          return bytes
              ? formatByteSize(value)
              : duration
              ? '${(value / 1000000000).toStringAsFixed(2)} s'
              : '$value';
        }

        final loaded = fields.length >= 4 && fields[2] != '—';
        return [
          name,
          status,
          loaded ? maintenanceDetailValue(context, fields[1]) : '—',
          loaded ? maintenanceDetailValue(context, fields[3]) : '—',
          maintenanceDetailValue(context, startup[name] ?? '—'),
          loaded ? fields.skip(4).join(' ') : '—',
          counter('MainPID'),
          counter('MemoryCurrent', bytes: true),
          counter('CPUUsageNSec', duration: true),
          counter('TasksCurrent'),
          counter('NRestarts'),
          counter('ExecMainStatus'),
        ];
      }
      if (manager == 'launchd') {
        return [
          name,
          status,
          fields.length > 1 ? fields[1] : '—',
          fields.length > 2 ? fields[2] : '—',
        ];
      }
      if (manager == 'Windows SCM') {
        return [
          name,
          status,
          columns.length > 2 ? columns[2] : '—',
          maintenanceDetailValue(context, startup[name] ?? '—'),
          for (var i = 3; i < 7; i++)
            columns.length > i && columns[i].isNotEmpty ? columns[i] : '—',
        ];
      }
      return [name, status, line];
    }

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

    final parents = <String, List<String>>{};
    for (final entry in serviceMetrics.entries) {
      parents[entry.key] = [
        for (final property in ['Requires', 'Wants'])
          ...(entry.value[property] ?? '')
              .split(' ')
              .where((name) => name.endsWith('.service')),
      ];
    }
    for (final line in data.text('service_dependencies').split('\n')) {
      final fields = line.split('\t');
      if (fields.length == 2) (parents[fields[0]] ??= []).add(fields[1]);
    }
    final distribution = <String, int>{};
    for (final line in rows) {
      final label = maintenanceLabel(context, state(line));
      distribution[label] = (distribution[label] ?? 0) + 1;
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
              '',
              Icons.play_circle_outline,
              cs.tertiary,
              null,
            ),
            _metric(
              '异常服务',
              '${rows.where((line) => state(line) == '异常').length}',
              '',
              Icons.error_outline,
              cs.error,
              null,
            ),
          ],
        ),

        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            const height = _maintenanceControlHeight;
            final search = SizedBox(
              height: height,
              child: TextField(
                controller: _search,
                style: const TextStyle(fontSize: 13, height: 1.2),
                textAlignVertical: TextAlignVertical.center,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
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
          child: _MaintenanceBrowser(
            query: _search.text,
            parents: parents,
            groupNames: manager == 'launchd',
            table: _MaintenanceTable(
              maxBodyHeight: 360,
              headers: serviceHeaders,
              rows: [
                for (final line in rows)
                  OpenHandOperationalRankRow(
                    value: 0,
                    rowKey: line.contains('\t')
                        ? line.split('\t').first
                        : line.trim().split(RegExp(r'\s+')).first,
                    data: line,
                    cells: serviceCells(
                      line,
                      maintenanceLabel(context, state(line)),
                    ),
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
        ),
        const SizedBox(height: 12),
        _MaintenanceCard(
          title: AppLocalizations.of(context)!.maintenanceServiceShare,
          icon: Icons.pie_chart_outline_rounded,
          child: _MaintenanceVisual(
            donut: true,
            segments: [
              for (final entry in distribution.entries)
                OpenHandChartSegment(
                  label: entry.key,
                  value: entry.value,
                  color: entry.key == maintenanceLabel(context, '异常')
                      ? cs.error
                      : entry.key == maintenanceLabel(context, '运行中')
                      ? cs.primary
                      : cs.secondary,
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _sections(MachineMaintenanceSnapshot data, List<String> names) {
    final cs = Theme.of(context).colorScheme;
    final connections = _maintenanceConnections(data);
    final states = <String, int>{};
    for (final row in connections) {
      final label = maintenanceLabel(context, row[3]);
      states[label] = (states[label] ?? 0) + 1;
    }
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
              child: Text(maintenanceLabel(context, '暂无可用数据')),
            )
          : _MaintenanceTable(
              maxBodyHeight: 360,
              headers: const ['协议', '本地地址', '远端地址', '状态', '接收队列', '发送队列', '进程'],
              rows: [
                for (final row in connections)
                  OpenHandOperationalRankRow(
                    value: 0,
                    cells: [
                      row[0],
                      row[1],
                      row[2],
                      maintenanceLabel(context, row[3]),
                      ...row.skip(4),
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      children: [
        _MaintenanceGrid(
          minWidth: 210,
          children: [
            _metric(
              '已解析连接',
              '${connections.length}',
              '',
              Icons.hub_outlined,
              cs.primary,
              null,
            ),
            _metric(
              'DNS 服务器',
              '${dns.length}',
              '',
              Icons.language_rounded,
              cs.tertiary,
              null,
            ),
            _metric(
              '诊断项目',
              '${names.length}',
              '',
              Icons.fact_check_outlined,
              cs.secondary,
              null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _MaintenanceGrid(
          minWidth: 340,
          children: [
            _MaintenanceCard(
              title: AppLocalizations.of(context)!.maintenanceConnectionShare,
              icon: Icons.donut_small_rounded,
              child: _MaintenanceVisual(
                donut: true,
                segments: [
                  for (final entry in states.entries)
                    OpenHandChartSegment(
                      label: entry.key,
                      value: entry.value,
                      color: [
                        cs.primary,
                        cs.tertiary,
                        cs.secondary,
                        cs.error,
                      ][states.keys.toList().indexOf(entry.key) % 4],
                    ),
                ],
              ),
            ),
            _MaintenanceCard(
              title: AppLocalizations.of(context)!.maintenanceConnectionGraph,
              icon: Icons.account_tree_outlined,
              child: _MaintenanceConnectionGraph(rows: connections),
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
        const SizedBox(height: 12),
        _MaintenanceCard(
          title: maintenanceLabel(context, '最近日志'),
          icon: Icons.receipt_long_outlined,
          onOpen: () => _showCollected('最近日志', data.text('logs')),
          child: _MaintenanceLogTimeline(
            rows: MachineMaintenanceReadout.parse(
              data.text('logs'),
              'logs',
            ).rows,
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
      Theme.of(context),
      Localizations.localeOf(context),
    );
    if (_identity == identity) return _content!;
    _identity = identity;
    final metrics = MachineMaintenanceMetrics.parse(data, section);
    return _content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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

class _MaintenanceBrowser extends StatefulWidget {
  const _MaintenanceBrowser({
    required this.table,
    required this.parents,
    required this.query,
    this.nameColumn = 0,
    this.groupNames = false,
  });
  final _MaintenanceTable table;
  final Map<String, List<String>> parents;
  final String query;
  final int nameColumn;
  final bool groupNames;

  @override
  State<_MaintenanceBrowser> createState() => _MaintenanceBrowserState();
}

class _MaintenanceBrowserState extends State<_MaintenanceBrowser> {
  bool _tree = false;
  final _collapsed = <String>{};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final motion = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
    final rows = {for (final row in widget.table.rows) row.cells.first: row};
    final children = <String, List<String>>{};
    final parent = <String, String>{};
    for (final id in rows.keys) {
      if (widget.groupNames) {
        final dot = id.lastIndexOf('.');
        if (dot > 0) {
          final group = 'group:${id.substring(0, dot)}';
          parent[id] = group;
          (children[group] ??= []).add(id);
        }
      } else {
        for (final candidate in widget.parents[id] ?? const <String>[]) {
          if (candidate == id || !rows.containsKey(candidate)) continue;
          var ancestor = candidate;
          final seen = <String>{id};
          while (seen.add(ancestor) && parent.containsKey(ancestor)) {
            ancestor = parent[ancestor]!;
          }
          if (seen.contains(ancestor) && parent.containsKey(ancestor) ||
              ancestor == id) {
            continue;
          }
          parent[id] = candidate;
          (children[candidate] ??= []).add(id);
          break;
        }
      }
    }
    final query = widget.query.trim().toLowerCase();
    final matches = rows.keys
        .where((id) => rows[id]!.cells.join(' ').toLowerCase().contains(query))
        .toSet();
    final visible = {...matches};
    for (final id in matches) {
      var ancestor = parent[id];
      while (ancestor != null && visible.add(ancestor)) {
        ancestor = parent[ancestor];
      }
    }
    final roots = [
      ...children.keys.where((id) => id.startsWith('group:')),
      ...rows.keys.where((id) => !parent.containsKey(id)),
    ];
    _collapsed.removeWhere((id) => !children.containsKey(id));
    final entries = <(String, int)>[];
    final stack = [for (final id in roots.reversed) (id, 0)];
    final visited = <String>{};
    while (stack.isNotEmpty) {
      final entry = stack.removeLast();
      if (!visited.add(entry.$1) || !visible.contains(entry.$1)) continue;
      entries.add(entry);
      if (query.isEmpty && _collapsed.contains(entry.$1)) continue;
      for (final child in (children[entry.$1] ?? const <String>[]).reversed) {
        stack.add((child, entry.$2 + 1));
      }
    }
    final entryIndexes = {
      for (var i = 0; i < entries.length; i++) entries[i].$1: i,
    };
    final table = _MaintenanceTable(
      key: ValueKey((false, query)),
      headers: widget.table.headers,
      rows: rows.entries
          .where((entry) => matches.contains(entry.key))
          .map((entry) => entry.value)
          .toList(),
      maxBodyHeight: widget.table.maxBodyHeight,
      limitToViewport: widget.table.limitToViewport,
      onRowTap: widget.table.onRowTap,
    );
    final tree = ConstrainedBox(
      key: const ValueKey(true),
      constraints: BoxConstraints(maxHeight: widget.table.maxBodyHeight),
      child: entries.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(18),
              child: Text(maintenanceLabel(context, '暂无可用数据')),
            )
          : ListView.builder(
              primary: false,
              shrinkWrap: true,
              itemCount: entries.length,
              findChildIndexCallback: (key) =>
                  key is ValueKey<String> ? entryIndexes[key.value] : null,
              itemBuilder: (context, index) {
                final (id, depth) = entries[index];
                final row = rows[id];
                final branches = children[id] ?? const <String>[];
                final collapsed = query.isEmpty && _collapsed.contains(id);
                return TweenAnimationBuilder<double>(
                  key: ValueKey(id),
                  tween: Tween(begin: 0, end: 1),
                  duration: openHandMotionDuration(context, motion.duration),
                  builder: (_, value, child) =>
                      Opacity(opacity: value.clamp(0, 1), child: child),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: index.isEven ? cs.surface : cs.surfaceContainerLow,
                      border: Border(
                        bottom: BorderSide(
                          color: cs.outlineVariant.withValues(alpha: .35),
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsetsDirectional.only(
                        start: math.min(depth, 8) * 16.0,
                        end: 8,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 34,
                            child: branches.isEmpty
                                ? Icon(
                                    Icons.subdirectory_arrow_right_rounded,
                                    size: 16,
                                    color: cs.outline,
                                  )
                                : IconButton(
                                    tooltip: collapsed
                                        ? l10n.maintenanceTreeExpand
                                        : l10n.maintenanceTreeCollapse,
                                    onPressed: query.isNotEmpty
                                        ? null
                                        : () => setState(() {
                                            if (!_collapsed.add(id)) {
                                              _collapsed.remove(id);
                                            }
                                          }),
                                    icon: AnimatedRotation(
                                      turns: collapsed ? 0 : .25,
                                      duration: openHandMotionDuration(
                                        context,
                                        motion.duration,
                                      ),
                                      curve: motion.curve.curve,
                                      child: const Icon(
                                        Icons.chevron_right_rounded,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                          ),
                          Expanded(
                            child: InkWell(
                              hoverColor: Colors.transparent,
                              onTap: row == null
                                  ? null
                                  : () => widget.table.onRowTap?.call(row),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      row == null
                                          ? id.substring(6)
                                          : row.cells[widget.nameColumn],
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: row == null
                                            ? cs.primary
                                            : cs.onSurface,
                                      ),
                                    ),
                                    if (row != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        [
                                          for (final i
                                              in widget.nameColumn == 1
                                                  ? const [0, 2, 3, 4, 6]
                                                  : const [1, 2, 3, 4])
                                            if (i < row.cells.length)
                                              '${maintenanceLabel(context, widget.table.headers[i])}: ${row.cells[i]}',
                                        ].join(' · '),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                      if (widget.nameColumn == 0 &&
                                          !widget.groupNames &&
                                          (widget.parents[id]?.isNotEmpty ??
                                              false))
                                        Text(
                                          '${l10n.maintenanceTreeDependencies}: ${widget.parents[id]!.join(', ')}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (branches.isNotEmpty)
                            Text(
                              '${branches.length}',
                              style: TextStyle(color: cs.primary, fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SegmentedButton<bool>(
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: false,
                  icon: const Icon(Icons.view_list_outlined, size: 16),
                  label: Text(l10n.maintenanceListView),
                ),
                ButtonSegment(
                  value: true,
                  icon: const Icon(Icons.account_tree_outlined, size: 16),
                  label: Text(
                    widget.groupNames
                        ? l10n.maintenanceNameTree
                        : l10n.maintenanceTreeView,
                  ),
                ),
              ],
              selected: {_tree},
              onSelectionChanged: (selection) =>
                  setState(() => _tree = selection.first),
            ),
          ),
        ),
        AnimatedSize(
          duration: openHandMotionDuration(context, motion.duration),
          curve: motion.curve.curve,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: openHandMotionDuration(context, motion.duration),
            switchInCurve: motion.curve.curve,
            switchOutCurve: Curves.easeOut,
            child: _tree ? tree : table,
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
    compact: true,
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
        height: _maintenanceControlHeight,
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
    if (widget.section == 'logs') {
      return _MaintenanceLogTimeline(rows: _data.rows);
    }
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
                _data.fields
                    ? c == 0
                          ? maintenanceDetailLabel(context, _data.rows[i][c])
                          : maintenanceDetailValue(context, _data.rows[i][c])
                    : const [
                        '状态',
                        'STATUS',
                        'STATE',
                        'PRESET',
                        'TYPE',
                        'State',
                        '启动方式',
                        '预设',
                        '类型',
                      ].contains(_data.headers[c])
                    ? maintenanceDetailValue(context, _data.rows[i][c])
                    : _data.rows[i][c],
            ],
            cellWidgets:
                _data.fields && const ['io', 'memory'].contains(widget.section)
                ? [
                    Text(maintenanceDetailLabel(context, _data.rows[i][0])),
                    _MaintenanceNumber(raw: _data.rows[i][1], maxLines: 3),
                  ]
                : null,
          ),
      ],
      maxBodyHeight: 480,
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

const _maintenanceChartLimit = 6;

class _MaintenanceGauge extends StatelessWidget {
  const _MaintenanceGauge({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final double? value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final motion = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(end: (value ?? 0).clamp(0, 1)),
      duration: motion.disablesAnimation
          ? Duration.zero
          : motion.entranceDuration,
      curve: motion.curve.curve,
      builder: (_, current, _) => OpenHandOperationalMeter(
        label: label,
        value: current,
        color: color,
        gaugeSize: 92,
        unavailable: value == null,
        valueLabel: value == null
            ? '—'
            : '${(current.clamp(0, 1) * 100).toStringAsFixed(1)}%',
      ),
    );
  }
}

class _MaintenanceSeriesTween extends Tween<Map<String, double>> {
  _MaintenanceSeriesTween({required Map<String, double> end}) : super(end: end);
  @override
  Map<String, double> lerp(double t) => {
    for (final entry in end!.entries)
      entry.key: math.max(
        0,
        (begin?[entry.key] ?? 0) + (entry.value - (begin?[entry.key] ?? 0)) * t,
      ),
  };
}

class _MaintenanceVisual extends StatefulWidget {
  const _MaintenanceVisual({
    required this.segments,
    this.donut = false,
    this.centerLabel,
  });
  final List<OpenHandChartSegment> segments;
  final bool donut;
  final String? centerLabel;

  @override
  State<_MaintenanceVisual> createState() => _MaintenanceVisualState();
}

class _MaintenanceVisualState extends State<_MaintenanceVisual> {
  Map<String, double> _target = {};
  List<OpenHandChartSegment> get segments => widget.segments;
  bool get donut => widget.donut;

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) return Text(maintenanceLabel(context, '暂无可用数据'));
    final motion = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
    final cs = Theme.of(context).colorScheme;
    final next = {
      for (final segment in segments) segment.label: segment.safeValue,
    };
    if (!mapEquals(_target, next)) _target = next;
    return TweenAnimationBuilder<Map<String, double>>(
      tween: _MaintenanceSeriesTween(end: _target),
      duration: motion.disablesAnimation
          ? Duration.zero
          : motion.entranceDuration,
      curve: motion.curve.curve,
      builder: (context, values, _) {
        final maximum = math.max(1.0, values.values.fold<double>(0, math.max));
        final total = segments.fold<double>(
          0,
          (sum, segment) => sum + segment.safeValue,
        );
        final legend = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final segment in segments)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Semantics(
                  label:
                      '${segment.label}: ${segment.valueLabel ?? segment.value}',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: segment.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Tooltip(
                              message: segment.label,
                              child: Text(
                                segment.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            fit: FlexFit.tight,
                            child: _MaintenanceValue(
                              value: segment.valueLabel ?? '${segment.value}',
                              alignment: Alignment.centerRight,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (!donut) ...[
                        const SizedBox(height: 5),
                        LinearProgressIndicator(
                          value: ((values[segment.label] ?? 0) / maximum).clamp(
                            0,
                            1,
                          ),
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(4),
                          color: segment.color,
                          backgroundColor: segment.color.withValues(alpha: .10),
                        ),
                      ] else
                        Text(
                          total > 0
                              ? '${(segment.safeValue / total * 100).toStringAsFixed(1)}%'
                              : '—',
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            fontSize: 10,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
        if (!donut) return legend;
        final chart = Semantics(
          label: segments
              .map((s) => '${s.label}: ${s.valueLabel ?? s.value}')
              .join(', '),
          child: SizedBox(
            width: 132,
            height: 132,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: OpenHandDonutChartPainter(
                  values: [
                    for (final segment in segments) values[segment.label] ?? 0,
                  ],
                  colors: segments.map((s) => s.color).toList(),
                  trackColor: cs.surfaceContainerHighest,
                ),
                child: Center(
                  child: _MaintenanceNumber(
                    raw: total.toStringAsFixed(0),
                    readable: widget.centerLabel,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        return LayoutBuilder(
          builder: (_, constraints) => constraints.maxWidth < 340
              ? Column(children: [chart, const SizedBox(height: 12), legend])
              : Row(
                  children: [
                    chart,
                    const SizedBox(width: 18),
                    Expanded(child: legend),
                  ],
                ),
        );
      },
    );
  }
}

class _MaintenanceConnectionGraph extends StatelessWidget {
  const _MaintenanceConnectionGraph({required this.rows});
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final links = <(String, String), int>{};
    for (final row in rows) {
      if (row.length < 4 ||
          const [
            '*:*',
            '*.*',
            '*:0',
            '0.0.0.0:*',
            '0.0.0.0:0',
            '[::]:0',
            '[::]:*',
            '—',
          ].contains(row[2])) {
        continue;
      }
      final key = (row[1], row[2]);
      links[key] = (links[key] ?? 0) + 1;
    }
    final visible = links.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0
            ? byCount
            : a.key.toString().compareTo(b.key.toString());
      });
    Widget node(String label, Color color) => Expanded(
      child: Tooltip(
        message: label,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: .25)),
          ),
          child: _MaintenanceValue(
            value: label,
            maxLines: 2,
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                maintenanceLabel(context, '本地地址'),
                style: const TextStyle(fontSize: 11),
              ),
            ),
            Expanded(
              child: Text(
                maintenanceLabel(context, '远端地址'),
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (visible.isEmpty) Text(maintenanceLabel(context, '暂无可用数据')),
        for (final entry in visible.take(_maintenanceChartLimit))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                node(entry.key.$1, cs.primary),
                SizedBox(
                  width: 48,
                  height: 38,
                  child: CustomPaint(
                    painter: _MaintenanceEdgePainter(cs.outlineVariant),
                    child: Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: _MaintenanceValue(
                            value: '${entry.value}',
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                node(entry.key.$2, cs.tertiary),
              ],
            ),
          ),
      ],
    );
  }
}

class _MaintenanceEdgePainter extends CustomPainter {
  const _MaintenanceEdgePainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height / 2)
      ..cubicTo(
        size.width * .3,
        2,
        size.width * .7,
        size.height - 2,
        size.width,
        size.height / 2,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_MaintenanceEdgePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _MaintenanceLogTimeline extends StatelessWidget {
  const _MaintenanceLogTimeline({required this.rows});
  final List<List<String>> rows;
  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return Text(maintenanceLabel(context, '暂无可用数据'));
    final cs = Theme.of(context).colorScheme;
    final motion = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 300),
      child: ListView.builder(
        shrinkWrap: true,
        primary: false,
        itemCount: rows.length,
        itemBuilder: (_, index) {
          final row = rows[index];
          return Container(
            margin: const EdgeInsets.only(left: 5),
            padding: const EdgeInsets.fromLTRB(12, 4, 6, 12),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: cs.primary.withValues(alpha: .3),
                  width: 2,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.schedule_rounded, size: 12, color: cs.primary),
                    const SizedBox(width: 5),
                    Expanded(
                      child: _MaintenanceValue(
                        value: row.first,
                        style: TextStyle(fontSize: 11, color: cs.primary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                AnimatedSwitcher(
                  duration: motion.disablesAnimation
                      ? Duration.zero
                      : motion.entranceDuration,
                  switchInCurve: motion.curve.curve,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.topLeft,
                    children: [...previous, ?current],
                  ),
                  child: SelectableText(
                    row.skip(1).join(' · '),
                    key: ValueKey(row.join(' · ')),
                    style: const TextStyle(fontSize: 12, height: 1.5),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MaintenanceTrend extends StatefulWidget {
  const _MaintenanceTrend({super.key, required this.points});
  final List<({double time, double value})> points;

  @override
  State<_MaintenanceTrend> createState() => _MaintenanceTrendState();
}

class _MaintenanceTrendState extends State<_MaintenanceTrend>
    with SingleTickerProviderStateMixin {
  static const _segments = 120;
  late final AnimationController _animation = AnimationController(vsync: this);
  late List<double> _from;
  late List<double> _to;
  late double _start;
  late double _end;
  late double _fromStart;
  late double _fromEnd;
  double? _window;
  double? _anchorEnd;
  double _gestureSpan = 0;
  double _gestureAnchor = 0;
  double _gestureFraction = 0;
  Curve _curve = kOpenHandEntranceCurve;

  @override
  void initState() {
    super.initState();
    _start = _fromStart = widget.points.first.time;
    _end = _fromEnd = widget.points.last.time;
    _from = _to = _values();
    _animation.value = 1;
  }

  List<double> _values() {
    var index = 0;
    return List.generate(_segments + 1, (i) {
      final time = _start + (_end - _start) * i / _segments;
      while (index < widget.points.length - 2 &&
          widget.points[index + 1].time < time) {
        index++;
      }
      final a = widget.points[index];
      final b = widget.points[index + 1];
      final fraction = b.time <= a.time
          ? 1.0
          : ((time - a.time) / (b.time - a.time)).clamp(0.0, 1.0);
      final smooth = fraction * fraction * (3 - 2 * fraction);
      return a.value + (b.value - a.value) * smooth;
    });
  }

  void _update({bool animate = true}) {
    final progress = _curve.transform(_animation.value);
    _from = List.generate(
      _to.length,
      (i) => (_from[i] + (_to[i] - _from[i]) * progress).clamp(0, 1),
    );
    _fromStart += (_start - _fromStart) * progress;
    _fromEnd += (_end - _fromEnd) * progress;
    final first = widget.points.first.time;
    final last = widget.points.last.time;
    final span = (_window ?? last - first).clamp(
      1.0,
      math.max(1.0, last - first),
    );
    _end = (_anchorEnd ?? last).clamp(
      first + span,
      math.max(first + span, last),
    );
    _start = _end - span;
    _to = _values();
    final settings = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
    _curve = settings.curve.curve;
    _animation.duration = settings.entranceDuration;
    if (!animate || settings.disablesAnimation) {
      _animation.value = 1;
    } else {
      _animation.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(_MaintenanceTrend oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.points, widget.points)) _update();
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final axisWidth = math.max(
                38.0,
                MediaQuery.textScalerOf(context).scale(10) * 4 + 6,
              );
              final width = math.max(
                1.0,
                constraints.maxWidth - axisWidth - 16,
              );
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                trackpadScrollCausesScale: true,
                onDoubleTap: () => setState(() {
                  _window = _anchorEnd = null;
                  _update();
                }),
                onScaleStart: (details) {
                  _gestureSpan = math.max(1, _end - _start);
                  _gestureFraction =
                      ((details.localFocalPoint.dx - axisWidth) / width).clamp(
                        0,
                        1,
                      );
                  _gestureAnchor = _start + _gestureSpan * _gestureFraction;
                },
                onScaleUpdate: (details) => setState(() {
                  final total = math.max(
                    1.0,
                    widget.points.last.time - widget.points.first.time,
                  );
                  _window = (_gestureSpan / math.max(.01, details.scale)).clamp(
                    math.min(1000.0, total),
                    total,
                  );
                  final fraction =
                      ((details.localFocalPoint.dx - axisWidth) / width).clamp(
                        0,
                        1,
                      );
                  _anchorEnd = _gestureAnchor + _window! * (1 - fraction);
                  _update(animate: false);
                }),
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _animation,
                    builder: (context, _) => CustomPaint(
                      size: Size.infinite,
                      painter: _MaintenanceTrendPainter(
                        from: _from,
                        to: _to,
                        progress: _curve.transform(_animation.value),
                        start: _fromStart,
                        end: _fromEnd,
                        targetStart: _start,
                        targetEnd: _end,
                        color: cs.primary,
                        labelColor: cs.onSurfaceVariant,
                        gridColor: cs.outlineVariant,
                        textDirection: Directionality.of(context),
                        textScale: MediaQuery.textScalerOf(context).scale(10),
                        fontFamily: Theme.of(
                          context,
                        ).textTheme.bodySmall?.fontFamily,
                        timeLabel: (time, milliseconds) {
                          final date = DateTime.fromMillisecondsSinceEpoch(
                            time.round(),
                          );
                          final label = MaterialLocalizations.of(context)
                              .formatTimeOfDay(
                                TimeOfDay.fromDateTime(date),
                                alwaysUse24HourFormat: true,
                              );
                          final seconds =
                              '$label:${date.second.toString().padLeft(2, '0')}';
                          return milliseconds
                              ? '$seconds.${date.millisecond.toString().padLeft(3, '0')}'
                              : seconds;
                        },
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MaintenanceTrendPainter extends CustomPainter {
  const _MaintenanceTrendPainter({
    required this.from,
    required this.to,
    required this.progress,
    required this.start,
    required this.end,
    required this.targetStart,
    required this.targetEnd,
    required this.color,
    required this.labelColor,
    required this.gridColor,
    required this.textDirection,
    required this.textScale,
    required this.timeLabel,
    this.fontFamily,
  });
  final List<double> from, to;
  final double progress, start, end, targetStart, targetEnd, textScale;
  final Color color, labelColor, gridColor;
  final TextDirection textDirection;
  final String Function(double, bool) timeLabel;
  final String? fontFamily;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(
      math.max(38, textScale * 4 + 6),
      8,
      size.width - 16,
      size.height - textScale - 14,
    );
    if (plot.width <= 0 || plot.height <= 0) return;
    void label(String text, Offset position, double align) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: textScale,
            color: labelColor,
            fontFamily: fontFamily,
          ),
        ),
        textDirection: textDirection,
      )..layout();
      painter.paint(
        canvas,
        Offset(
          (position.dx - painter.width * align).clamp(
            0,
            math.max(0, size.width - painter.width),
          ),
          position.dy,
        ),
      );
      painter.dispose();
    }

    final grid = Paint()
      ..color = gridColor.withValues(alpha: .65)
      ..strokeWidth = .7;
    for (var i = 0; i <= 4; i++) {
      final y = plot.bottom - plot.height * i / 4;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      label('${i * 25}%', Offset(plot.left - 5, y - textScale / 2), 1);
    }
    final left = start + (targetStart - start) * progress;
    final right = end + (targetEnd - end) * progress;
    final milliseconds = right - left < 3000;
    final labelWidth = textScale * (milliseconds ? 11 : 8) + 16;
    final ticks = (plot.width / labelWidth).floor().clamp(1, 3);
    for (var i = 0; i <= ticks; i++) {
      final x = plot.left + plot.width * i / ticks;
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), grid);
      label(
        timeLabel(left + (right - left) * i / ticks, milliseconds),
        Offset(x, plot.bottom + 7),
        i == 0
            ? 0
            : i == ticks
            ? 1
            : .5,
      );
    }
    final path = Path();
    Offset? previous;
    for (var i = 0; i < to.length; i++) {
      final value = (from[i] + (to[i] - from[i]) * progress).clamp(0, 1);
      final point = Offset(
        plot.left + plot.width * i / (to.length - 1),
        plot.bottom - plot.height * value,
      );
      if (previous == null) {
        path.moveTo(point.dx, point.dy);
      } else {
        final middle = (previous.dx + point.dx) / 2;
        path.cubicTo(middle, previous.dy, middle, point.dy, point.dx, point.dy);
      }
      previous = point;
    }
    canvas.save();
    canvas.clipRect(plot.inflate(1));
    final fill = Path.from(path)
      ..lineTo(plot.right, plot.bottom)
      ..lineTo(plot.left, plot.bottom)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: .10));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MaintenanceTrendPainter oldDelegate) => true;
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
      maxHeight: size.height * .82,
      child: SizedBox(
        width: math.min(size.width * .9, 940),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) => _MachineTerminalDialogHeader(
                icon: Icons.analytics_outlined,
                title: widget.title,
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
                            Semantics(
                              button: true,
                              enabled: !_busy,
                              child: _MachineTerminalIconButton(
                                icon: switch (action.key) {
                                  '终止进程' => Icons.stop_circle_outlined,
                                  '暂停进程' => Icons.pause_rounded,
                                  '恢复进程' => Icons.play_arrow_rounded,
                                  '启动服务' => Icons.play_circle_outline_rounded,
                                  '停止服务' => Icons.stop_rounded,
                                  '重启服务' => Icons.restart_alt_rounded,
                                  '启用开机启动' ||
                                  '自动启动' => Icons.event_available_outlined,
                                  '禁用开机启动' => Icons.event_busy_outlined,
                                  '手动启动' => Icons.touch_app_outlined,
                                  '禁用服务' => Icons.block_rounded,
                                  _ => Icons.settings_outlined,
                                },
                                tooltip: maintenanceLabel(context, action.key),
                                onPressed: _busy ? null : () => _act(action),
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
            Flexible(
              child: _data == null
                  ? Center(
                      heightFactor: 3,
                      child: Text(
                        maintenanceLabel(
                          context,
                          _busy ? '正在读取详情…' : '读取失败，请重试。',
                        ),
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
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

class _MaintenanceLogBrowser extends StatefulWidget {
  const _MaintenanceLogBrowser({required this.buffers, required this.data});
  final Map<String, MachineLogBuffer> buffers;
  final MachineMaintenanceSnapshot data;
  @override
  State<_MaintenanceLogBrowser> createState() => _MaintenanceLogBrowserState();
}

class _MaintenanceLogBrowserState extends State<_MaintenanceLogBrowser> {
  final _scroll = ScrollController();
  String _source = 'system', _query = '';
  int _level = -1;
  bool _follow = true;
  List<MachineLogEntry> _visible = [];
  static const _rowHeight = 64.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients && _follow) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _MaintenanceLogBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    final index = (offset / _rowHeight).floor();
    final anchor = index < _visible.length ? _visible[index].id : null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (_follow) {
        final duration = openHandMotionDuration(context, kOpenHandMotion260);
        if (duration == Duration.zero) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        } else {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: duration,
            curve: Curves.easeOutCubic,
          );
        }
      } else if (anchor != null) {
        final next = _visible.indexWhere((entry) => entry.id == anchor);
        _scroll.jumpTo(
          (next < 0 ? 0.0 : next * _rowHeight + offset % _rowHeight).clamp(
            0,
            _scroll.position.maxScrollExtent,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final buffer = widget.buffers[_source];
    final entries = buffer?.entries ?? const <MachineLogEntry>[];
    _visible = entries
        .where(
          (e) =>
              (_level < 0 || e.level == _level) &&
              e.message.toLowerCase().contains(_query),
        )
        .toList();
    final names = [
      l.maintenanceLogError,
      l.maintenanceLogWarning,
      l.maintenanceLogInfo,
    ];
    final colors = [cs.error, cs.tertiary, cs.primary];
    final platform = widget.data.sections['platform']?.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        12,
        8,
        12,
        _maintenancePanelBottomInset,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _MaintenanceToolbarMenu<String>(
                tooltip: l.maintenanceLogsTab,
                label: switch (_source) {
                  'kernel' =>
                    platform == 'Windows'
                        ? l.maintenanceLogApplication
                        : l.maintenanceLogKernel,
                  'security' =>
                    platform == 'Darwin'
                        ? l.maintenanceLogSystem
                        : l.maintenanceLogSecurity,
                  _ => l.maintenanceLogSystem,
                },
                value: _source,
                items: {
                  'system': l.maintenanceLogSystem,
                  'kernel': platform == 'Windows'
                      ? l.maintenanceLogApplication
                      : l.maintenanceLogKernel,
                  'security': platform == 'Darwin'
                      ? '/var/log/system.log'
                      : l.maintenanceLogSecurity,
                },
                onSelected: (value) => setState(() {
                  _source = value;
                  if (_scroll.hasClients) _scroll.jumpTo(0);
                }),
              ),
              SizedBox(
                width: 230,
                height: _maintenanceControlHeight,
                child: TextField(
                  onChanged: (value) =>
                      setState(() => _query = value.toLowerCase()),
                  decoration: InputDecoration(
                    hintText: l.maintenanceLogSearch,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                ),
              ),
              _MaintenanceToolbarMenu<int>(
                tooltip: l.maintenanceLogAll,
                label: _level < 0 ? l.maintenanceLogAll : names[_level],
                value: _level,
                items: {
                  -1: l.maintenanceLogAll,
                  for (var i = 0; i < names.length; i++) i: names[i],
                },
                onSelected: (value) => setState(() => _level = value),
              ),
              FilterChip(
                label: Text(l.maintenanceLogFollow),
                selected: _follow,
                onSelected: (value) => setState(() {
                  _follow = value;
                  if (value && _scroll.hasClients) {
                    _scroll.jumpTo(_scroll.position.maxScrollExtent);
                  }
                }),
              ),
              for (var i = 0; i < names.length; i++)
                Chip(
                  avatar: Icon(
                    i == 0
                        ? Icons.error_outline
                        : i == 1
                        ? Icons.warning_amber_rounded
                        : Icons.info_outline,
                    size: 16,
                    color: colors[i],
                  ),
                  label: Text(
                    '${names[i]} ${entries.where((e) => e.level == i).length}',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (buffer?.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                l.maintenanceLogUnavailable,
                style: TextStyle(color: cs.error),
              ),
            ),
          Expanded(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                border: Border.all(color: cs.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _visible.isEmpty
                  ? Center(child: Text(l.maintenanceLogEmpty))
                  : NotificationListener<ScrollNotification>(
                      onNotification: (event) {
                        if (event is ScrollUpdateNotification &&
                            event.dragDetails != null &&
                            _follow) {
                          setState(() => _follow = false);
                        }
                        if (event is UserScrollNotification &&
                            event.direction != ScrollDirection.idle &&
                            _follow) {
                          setState(() => _follow = false);
                        }
                        return false;
                      },
                      child: ListView.builder(
                        controller: _scroll,
                        itemExtent: _rowHeight,
                        itemCount: _visible.length,
                        itemBuilder: (context, index) {
                          final entry = _visible[index];
                          return InkWell(
                            key: ValueKey(entry.id),
                            onTap: () => _showEntry(entry),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(
                                    color: colors[entry.level],
                                    width: 3,
                                  ),
                                  bottom: BorderSide(
                                    color: cs.outlineVariant.withValues(
                                      alpha: .35,
                                    ),
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 145,
                                    child: Text(
                                      entry.time.isEmpty
                                          ? names[entry.level]
                                          : entry.time.replaceFirst('T', ' '),
                                      maxLines: 2,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: colors[entry.level],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      entry.message,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 8),
            title: Text(l.maintenanceLogRotation),
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 140),
                child: SingleChildScrollView(
                  child: SelectableText(
                    [
                      widget.data.sections['log_rotation'] ?? '',
                      widget.data.sections['log_config'] ?? '',
                      if ((widget.data.sections['log_storage'] ?? '')
                          .isNotEmpty)
                        '${l.maintenanceLogStorage}: ${widget.data.sections['log_storage']} KiB',
                    ].where((s) => s.isNotEmpty).join('\n\n'),
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showEntry(MachineLogEntry entry) {
    showAnimatedDialog<void>(
      context: context,
      builder: (context) => buildOpenHandAlertDialog(
        title: Text(
          entry.time.isEmpty
              ? AppLocalizations.of(context)!.maintenanceLogsTab
              : entry.time,
        ),
        content: SingleChildScrollView(child: SelectableText(entry.message)),
      ),
    );
  }
}
