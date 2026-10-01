part of '../openhand_home_page.dart';

const _maintenanceControlHeight = 34.0;
const _maintenanceNoticeMaxWidth = 480.0;
const _maintenanceSearchWidth = 280.0;
const _maintenanceCpuTimeColumnMinWidth = 220.0;
const _maintenanceTimestampColumnMinWidth = 200.0;
const _maintenanceGridGap = 12.0;
const _maintenanceFieldMinWidth = 240.0;
const _maintenanceFieldHeight = 104.0;
const _maintenanceFieldMaxColumns = 4;
const _maintenanceSectionHeaderHeight = 54.0;
const _maintenancePanelBottomInset = 8.0;
const _maintenanceLogPreviewMaxHeight = 260.0;
const _maintenanceDetailPadding = EdgeInsets.fromLTRB(18, 4, 18, 12);

const _maintenanceTabs = [
  '运行总览',
  '进程管理',
  '系统服务',
  '网络与诊断',
  'GPU 管理',
  '日志管理',
  '账户与健康',
  '容器管理',
];
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
  'listeners': '监听端口',
  'proxy': '系统网络代理',
  'firewall_status': '防火墙状态',
  'routes': '地址与路由',
  'addresses': '网卡地址与链路统计',
  'policy_routes': '策略路由 · IPv4 / IPv6',
  'neighbors': '邻居表 · ARP / NDP',
  'network_stats': '网络协议与错误统计',
  'socket_details': '连接进程与 TCP 诊断',
  'dns_status': '解析器与代理状态',
  'firewall_rules': '防火墙规则与计数器',
  'firewall_nat': 'NAT 与地址转换规则',
  'firewall_states': '防火墙运行统计',
  'firewall_ipvfour': 'iptables · IPv4 规则与计数器',
  'firewall_ipvsix': 'ip6tables · IPv6 规则与计数器',
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
  'blocks': '块设备与 RAID',
  'cgroup_limits': '控制组资源限制 · 容器与主机视图可能不同',
  'kernel': '内核资源参数',
  'network': '网卡累计计数 · 字节、包、错误与丢包',
};

const _maintenanceTabIcons = <IconData>[
  Icons.dashboard_outlined,
  Icons.memory_rounded,
  Icons.settings_suggest_outlined,
  Icons.hub_outlined,
  Icons.developer_board_rounded,
  Icons.article_outlined,
  Icons.health_and_safety_outlined,
  Icons.inventory_2_outlined,
];
const _maintenanceDistributionMaxWidth = 380.0;
const _maintenanceDonutSize = 132.0;
const _maintenanceDonutGap = 16.0;
const _maintenanceDonutLegendMinWidth = 128.0;
const _maintenanceCardRadius = kOpenHandRadius12;
const _maintenanceNoOverlay = WidgetStatePropertyAll<Color?>(
  Colors.transparent,
);

Color _maintenanceUsageColor(ColorScheme cs, double? ratio) {
  if (ratio == null) return cs.onSurfaceVariant;
  if (ratio >= 0.85) return OpenHandStatusColors.error;
  if (ratio >= 0.70) return OpenHandStatusColors.warning;
  return OpenHandStatusColors.success;
}

Color _maintenanceStateColor(ColorScheme cs, String label) {
  return switch (label) {
    '运行中' || '运行' || '采集成功' || '健康' || '已连接' => OpenHandStatusColors.success,
    '异常' || '僵尸' || '数据可能过期' => OpenHandStatusColors.error,
    '待检查' || '暂停' || 'IO 等待' || '部分不可用 · 查看原因' => OpenHandStatusColors.warning,
    '未运行' || '休眠' || '空闲' || '暂无阈值提醒' => cs.onSurfaceVariant,
    _ => OpenHandStatusColors.info,
  };
}

String _maintenancePlatformLabel(BuildContext context, String? platform) {
  return switch (platform) {
    'Darwin' => maintenanceLabel(context, 'macOS'),
    null || '' => maintenanceLabel(context, '正在识别目标系统'),
    _ => platform,
  };
}

String _maintenanceShellChoice(
  MachineTerminalCommandShell shell,
  String? autoLabel,
) => switch (shell) {
  MachineTerminalCommandShell.automatic ||
  MachineTerminalCommandShell.probe => autoLabel ?? '自动识别 Shell',
  MachineTerminalCommandShell.posix => 'POSIX Shell',
  MachineTerminalCommandShell.powershell => 'PowerShell',
  MachineTerminalCommandShell.cmd => 'CMD',
};

IconData _maintenanceSectionIcon(String? section) => switch (section) {
  'disks' || 'blocks' || 'inodes' => Icons.storage_rounded,
  'memory' || 'memory_details' || 'vm' => Icons.memory_rounded,
  'interfaces' => Icons.lan_outlined,
  'pressure' || 'sensors' => Icons.monitor_heart_outlined,
  'kernel' || 'cgroup_limits' => Icons.tune_rounded,
  _ => Icons.analytics_outlined,
};

BoxDecoration _maintenanceTileDecoration(ColorScheme cs) => BoxDecoration(
  color: cs.surfaceContainerLowest,
  borderRadius: BorderRadius.circular(_maintenanceCardRadius),
  border: Border.all(color: cs.outlineVariant.withValues(alpha: .6)),
);

bool _maintenanceLogUnreadable(String text) => RegExp(
  'Could not open local log store|not refer to a valid log archive',
  caseSensitive: false,
).hasMatch(text);

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
  final _containersKey = GlobalKey<_MachineContainerPanelState>();
  final _snapshots = <int, MachineMaintenanceSnapshot>{};
  final _previous = <int, MachineMaintenanceSnapshot>{};
  final _logBuffers = <String, MachineLogBuffer>{};
  final _gpuHistory = <String, List<({double time, double value})>>{};
  final _cpuHistory = <({double time, double value})>[];
  final _search = TextEditingController();
  Timer? _timer, _progressTimer;
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
  int get _timeoutSeconds =>
      context.read<SettingsController>().maintenanceTimeoutSeconds;
  bool _savingTimeout = false;
  int get _workers => context.read<SettingsController>().maintenanceWorkers;
  bool _savingWorkers = false;
  int _scheduledTaskOperations = 0;
  bool get _scheduledTasksBusy => _scheduledTaskOperations > 0;
  Future<void>? _scheduledTaskPending;
  bool _scheduledTasksRefreshPending = false;
  Object? _bodyIdentity;
  Widget? _body;
  MachineEgressReport? _egress;
  String? _egressIdentity, _egressError, _egressLanguage;
  bool _egressBusy = false, _egressAttempted = false;

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
    _progressTimer?.cancel();
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
        !_scheduledTasksBusy &&
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
    bool Function()? isCancelled,
    MachineTerminalCommandOutputCallback? onOutput,
  }) => context.read<MachineTerminalFileService>().runMaintenanceCommand(
    sessionId: widget.sessionId,
    terminalId: widget.terminalId,
    command: command,
    timeout: Duration(seconds: _timeoutSeconds),
    windowsScript:
        !probe && shell == null && (_platform?.windowsScript ?? false),
    commandShell:
        shell ?? (probe ? MachineTerminalCommandShell.probe : _commandShell),
    isCancelled: () => !mounted || _closing || (isCancelled?.call() ?? false),
    onOutput: onOutput,
    maxOutputCharacters: onOutput == null
        ? null
        : machineMaintenanceOutputLimit,
  );

  Future<void> _refresh({
    bool manual = false,
    bool detectShell = true,
    bool egressOnly = false,
  }) async {
    if (_loading || !mounted || _closing) return;
    if (_scheduledTasksBusy) {
      _scheduledTasksRefreshPending = true;
      return;
    }
    if (_tab == 7 && _platformName != null) {
      _timer?.cancel();
      await _containersKey.currentState?.refresh(applyScope: manual);
      if (!mounted || _closing) return;
      if (_containersKey.currentState?._client == null ||
          _containersKey.currentState?._listingFailed == true) {
        setState(() => _automatic = false);
      }
      _schedule();
      return;
    }
    _timer?.cancel();
    final tab = _tab;
    final baseline = _snapshots[tab];
    final beforeBaseline = _previous[tab];
    var committed = false;
    final sampledAt = DateTime.now().millisecondsSinceEpoch.toDouble();
    final savedCpu = tab == 0 ? List.of(_cpuHistory) : null;
    final savedGpu = tab == 4
        ? {
            for (final entry in _gpuHistory.entries)
              entry.key: List.of(entry.value),
          }
        : null;
    final savedLogs = tab == 5
        ? {
            for (final entry in _logBuffers.entries)
              entry.key: MachineLogBuffer.copy(entry.value),
          }
        : null;
    String? publishedIdentity = baseline?.identity;
    final publishedLogs = <String, String>{
      if (tab == 5 && baseline != null)
        for (final source in machineLogSources)
          source: baseline.text('log_$source'),
    };
    void updateTelemetry(MachineMaintenanceSnapshot next) {
      final changedTarget = publishedIdentity != next.identity;
      publishedIdentity = next.identity;
      if (tab == 5) {
        if (changedTarget) {
          _logBuffers.clear();
          publishedLogs.clear();
        }
        for (final source in machineLogSources) {
          final raw = next.text('log_$source');
          if (!next.receivedSection('log_$source') ||
              publishedLogs[source] == raw) {
            continue;
          }
          publishedLogs[source] = raw;
          _logBuffers
              .putIfAbsent(source, MachineLogBuffer.new)
              .append(
                next.text('log_$source'),
                eventLog: next.text('platform') == 'Windows',
              );
        }
      }
      if (tab == 0) {
        if (changedTarget) _cpuHistory.clear();
        if (next.receivedSection('cpu') ||
            next.receivedSection('cpu_percent')) {
          final cpu = next.cpuUsage(baseline);
          if (cpu != null && cpu.isFinite) {
            _cpuHistory.removeWhere((point) => point.time == sampledAt);
            _cpuHistory.add((time: sampledAt, value: cpu.clamp(0, 1)));
            if (_cpuHistory.length > 60) _cpuHistory.removeAt(0);
          }
        }
      }
      if (tab == 4) {
        if (changedTarget) _gpuHistory.clear();
        final devices = next.gpu.devices;
        if (next.isComplete) {
          final ids = devices.map((device) => device.id).toSet();
          _gpuHistory.removeWhere((id, _) => !ids.contains(id));
        }
        for (final device in devices) {
          final section = switch (device.source) {
            'NVIDIA SMI' =>
              next.text('gpu_nvidia').isNotEmpty ? 'gpu_nvidia' : 'gpu_details',
            'DRM / sysfs' => 'gpu_drm',
            _ => 'gpu_accelerators',
          };
          if (!next.receivedSection(section)) continue;
          final utilization = device.metrics['util'];
          if (utilization == null) {
            if (next.isComplete) _gpuHistory.remove(device.id);
            continue;
          }
          final history = _gpuHistory.putIfAbsent(device.id, () => []);
          history.removeWhere((point) => point.time == sampledAt);
          history.add((time: sampledAt, value: utilization / 100));
          if (history.length > 60) history.removeAt(0);
        }
      }
    }

    MachineMaintenanceSnapshot? pending;
    Object? streamError;
    final stream = MachineMaintenanceStream(
      baseline: baseline,
      beforeBaseline: beforeBaseline,
    );
    void publishProgress() {
      _progressTimer = null;
      final next = pending;
      pending = null;
      if (!mounted || _closing || tab != _tab || next == null) return;
      setState(() {
        if (baseline != null && baseline.identity == next.identity) {
          _previous[tab] = baseline;
        } else {
          _previous.remove(tab);
        }
        _snapshots[tab] = next;
        updateTelemetry(next);
      });
    }

    setState(() {
      _loading = true;
      _manualRefresh = manual;
      _error = null;
    });
    try {
      if (egressOnly &&
          _platform != null &&
          _snapshots[3] != null &&
          tab == 3) {
        await _loadEgress(_snapshots[3]!.identity, force: true);
        return;
      }
      final target = detectShell || _detectedTarget == null
          ? parseMachineTerminalShellProbe(
              await _run(
                machineTerminalShellProbe,
                probe: true,
                isCancelled: () => tab != _tab,
              ),
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
            isCancelled: () => tab != _tab,
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
        await _run(
          _platform!.collect(
            tab,
            workers: _workers,
            timeout: Duration(seconds: _timeoutSeconds),
          ),
          isCancelled: () => tab != _tab,
          onOutput: (output) {
            if (!mounted || _closing || streamError != null) return;
            try {
              final next = stream.add(output);
              if (next == null) return;
              pending = next;
              _progressTimer ??= startSafeTimer(
                const Duration(milliseconds: 48),
                publishProgress,
              );
            } catch (error) {
              streamError = error;
            }
          },
        ),
        previous: baseline,
      );
      if (streamError != null) throw streamError!;
      _progressTimer?.cancel();
      _progressTimer = null;
      pending = null;
      if (!mounted || _closing) return;
      committed = true;
      setState(() {
        final old = baseline;
        if (old != null) _previous[tab] = old;
        _snapshots[tab] = result;
        updateTelemetry(result);
      });
      if (tab == 3 && _tab == 3) {
        await _loadEgress(result.identity, force: manual);
      }
    } on MachineTerminalUploadCancelled {
      // 关闭弹窗后停止传输，不将主动取消报告为采集故障。
      return;
    } catch (error, stack) {
      _detectedTarget = null;
      if (mounted && !_closing && tab == _tab) {
        // 超时已有本地化错误状态，未知故障仍保留堆栈供排查。
        if (error is! TimeoutException) {
          silentLog('machine_maintenance', '采集运维数据', error, stack);
        }
        setState(() {
          _error = error is TimeoutException
              ? AppLocalizations.of(context)!.maintenanceCommandTimedOut
              : error is StateError
              ? error.message
              : error is UnsupportedError
              ? error.message ??
                    AppLocalizations.of(context)!.maintenanceCollectionFailed
              : AppLocalizations.of(context)!.maintenanceCollectionFailed;
        });
      }
    } finally {
      _progressTimer?.cancel();
      _progressTimer = null;
      pending = null;
      if (mounted && !_closing) {
        setState(() {
          if (!committed && _snapshots[tab]?.isComplete == false) {
            if (savedCpu != null) {
              _cpuHistory
                ..clear()
                ..addAll(savedCpu);
            }
            if (savedGpu != null) {
              _gpuHistory
                ..clear()
                ..addAll(savedGpu);
            }
            if (savedLogs != null) {
              _logBuffers
                ..clear()
                ..addAll(savedLogs);
            }
            if (baseline == null) {
              _snapshots.remove(tab);
            } else {
              _snapshots[tab] = baseline;
            }
            if (beforeBaseline == null) {
              _previous.remove(tab);
            } else {
              _previous[tab] = beforeBaseline;
            }
          }
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

  Future<void> _loadEgress(String identity, {required bool force}) async {
    final language = Localizations.localeOf(context).languageCode;
    if (_egressIdentity != identity) {
      _egressIdentity = identity;
      _egress = null;
      _egressError = null;
      _egressAttempted = false;
    }
    if (!force &&
        _egressLanguage == language &&
        _egressAttempted &&
        (_egressError != null ||
            (_egress != null &&
                DateTime.now().difference(_egress!.collectedAt) <
                    machineEgressCacheDuration))) {
      return;
    }
    setState(() {
      _egressBusy = true;
      _egressError = null;
    });
    final service = context.read<MachineTerminalFileService>();
    bool cancelled() => !mounted || _closing || _tab != 3;
    try {
      final result = await queryMachineEgress(
        language: language,
        windows: _platformName == 'Windows',
        isCancelled: cancelled,
        run: (command) => service.runMaintenanceCommand(
          sessionId: widget.sessionId,
          terminalId: widget.terminalId,
          command: command,
          commandShell: _commandShell,
          timeout: machineEgressTimeout,
          maxOutputCharacters: machineEgressOutputLimit,
          isCancelled: cancelled,
        ),
      );
      if (!cancelled()) {
        setState(() {
          _egress = result;
          _egressLanguage = language;
          _egressAttempted = true;
        });
      }
    } on MachineTerminalUploadCancelled {
      // 切换分区或关闭弹窗时取消查询，保留上次有效结果。
    } catch (error, stack) {
      if (!cancelled()) {
        silentLog('machine_maintenance', '查询目标机器出口地址', error, stack);
        setState(() {
          _egressLanguage = language;
          _egressError = error is MachineEgressException
              ? error.code
              : 'request';
          _egressAttempted = true;
        });
      }
    } finally {
      if (mounted) setState(() => _egressBusy = false);
    }
  }

  Future<void> _details(
    String title,
    String command, {
    Map<String, String> actions = const {},
    bool service = false,
    String? initialAction,
  }) async {
    if (_loading || _platform == null) return;
    final platform = _platform!;
    final snapshot = _snapshots[_tab]!;
    _detailOpen = true;
    _timer?.cancel();
    var active = true;
    try {
      await showAnimatedDialog<void>(
        context: context,
        builder: (_) => _MachineMaintenanceDetails(
          title: title,
          initialAction: initialAction,
          load: () => _run(
            platform.bind(snapshot, command),
            isCancelled: () => !active,
          ),
          refreshInterval: service ? Duration(seconds: _intervalSeconds) : null,
          actions: actions,
          execute: (command) => _run(platform.bind(snapshot, command)),
        ),
      );
    } finally {
      active = false;
      _detailOpen = false;
      if (mounted) _schedule();
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeoutSeconds = context.select<SettingsController, int>(
      (settings) => settings.maintenanceTimeoutSeconds,
    );
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
          shadowColor: Colors.transparent,
          splashColor: cs.primary.withValues(alpha: .12),
          highlightColor: Colors.transparent,
          chipTheme: theme.chipTheme.copyWith(
            elevation: 0,
            pressElevation: 0,
            shadowColor: Colors.transparent,
            selectedShadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
          ),
          iconButtonTheme: IconButtonThemeData(
            style: (theme.iconButtonTheme.style ?? const ButtonStyle())
                .copyWith(
                  elevation: const WidgetStatePropertyAll(0),
                  shadowColor: const WidgetStatePropertyAll(Colors.transparent),
                  overlayColor: _maintenanceNoOverlay,
                ),
          ),
          expansionTileTheme: const ExpansionTileThemeData(
            shape: Border(),
            collapsedShape: Border(),
          ),
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
                            label: _maintenanceShellChoice(
                              _requestedShell,
                              _shellLabel,
                            ),
                            tooltip: maintenanceLabel(context, '终端 Shell'),
                            enabled: !_loading,
                            value: _requestedShell,
                            items: {
                              MachineTerminalCommandShell.automatic:
                                  _maintenanceShellChoice(
                                    MachineTerminalCommandShell.automatic,
                                    _shellLabel,
                                  ),
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
                            label: maintenanceTimeoutLabel(
                              context,
                              timeoutSeconds,
                            ),
                            tooltip: AppLocalizations.of(
                              context,
                            )!.maintenanceTimeout,
                            icon: Icons.hourglass_bottom_rounded,
                            enabled:
                                !_loading &&
                                !_scheduledTasksBusy &&
                                !_savingTimeout,
                            value: timeoutSeconds,
                            items: {
                              for (final seconds
                                  in machineMaintenanceTimeoutOptions)
                                seconds: maintenanceTimeoutLabel(
                                  context,
                                  seconds,
                                ),
                            },
                            onSelected: (value) async {
                              setState(() => _savingTimeout = true);
                              try {
                                await context
                                    .read<SettingsController>()
                                    .updateMaintenanceTimeoutSeconds(value);
                              } finally {
                                if (mounted) {
                                  setState(() => _savingTimeout = false);
                                }
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                          _MaintenanceToolbarMenu<int>(
                            label: AppLocalizations.of(
                              context,
                            )!.maintenanceSeconds('$_intervalSeconds'),
                            tooltip: maintenanceLabel(context, '自动刷新间隔'),
                            icon: Icons.timer_outlined,
                            enabled: !_loading,
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
                            enabled: !_loading && !_savingWorkers,
                            value: _workers,
                            items: {
                              for (final count
                                  in AppSettingsSnapshot
                                      .maintenanceWorkerOptions)
                                count: AppLocalizations.of(
                                  context,
                                )!.maintenanceWorkers('$count'),
                            },
                            onSelected: (value) async {
                              setState(() => _savingWorkers = true);
                              try {
                                await context
                                    .read<SettingsController>()
                                    .updateMaintenanceWorkers(value);
                              } finally {
                                if (mounted) {
                                  setState(() => _savingWorkers = false);
                                }
                              }
                            },
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
                            '${data?.text('host') ?? widget.terminalId}  /  ${_maintenancePlatformLabel(context, _platformName)}',
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
                            onPressed: _loading && !_automatic
                                ? null
                                : () {
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
                            icon: Icon(_maintenanceTabIcons[index], size: 18),
                            label: Text(
                              maintenanceLabel(
                                context,
                                _maintenanceTabs[index],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
      (data?.isComplete == false, (_tab == 2 || _tab == 5) && _loading, _error),
      _tab == 3 ? (_egress, _egressBusy, _egressError, _loading) : null,
    );
    if (_tab == 7 && _platformName != null) {
      Future<String> runContainerCommand(
        String command, {
        Duration? timeout,
        void Function(String)? onOutput,
        bool Function()? isCancelled,
      }) => context.read<MachineTerminalFileService>().runMaintenanceCommand(
        sessionId: widget.sessionId,
        terminalId: widget.terminalId,
        command: command,
        commandShell: _commandShell,
        timeout: timeout ?? Duration(seconds: _timeoutSeconds),
        maxOutputCharacters: machineContainerOutputLimit,
        onOutput: onOutput,
        isCancelled: () =>
            !mounted || _closing || _tab != 7 || (isCancelled?.call() ?? false),
      );
      return _MachineContainerPanel(
        key: _containersKey,
        sessionId: widget.sessionId,
        terminalId: widget.terminalId,
        windows: _platformName == 'Windows',
        shell: _commandShell,
        probe: (command) =>
            runContainerCommand(command, timeout: machineContainerProbeTimeout),
        run: runContainerCommand,
        operationTimeout: Duration(seconds: _timeoutSeconds),
        query: runContainerCommand,
        operate: runContainerCommand,
      );
    }
    if (_bodyIdentity != identity) {
      _bodyIdentity = identity;
      _body = data == null
          ? _emptyState()
          : switch (_tab) {
              0 => _overview(data),
              1 => _processes(data),
              2 => _services(data),
              4 => _gpu(data),
              5 => _MaintenanceLogBrowser(
                buffers: _logBuffers,
                data: data,
                busy: _loading,
              ),
              6 => _health(data),
              _ => _sections(data, const [
                'sockets',
                'routes',
                'addresses',
                'policy_routes',
                'neighbors',
                'network_stats',
                'socket_details',
                'dns_status',
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
          constraints: const BoxConstraints(
            maxWidth: _maintenanceNoticeMaxWidth,
          ),
          child: DecoratedBox(
            decoration: _maintenanceTileDecoration(theme.colorScheme),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (failed)
                    _MaintenanceIconBadge(
                      icon: Icons.cloud_off_rounded,
                      color: theme.colorScheme.error,
                      size: 48,
                      iconSize: 24,
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
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (failed) ...[
                    const SizedBox(height: 16),
                    _MaintenanceNotice(message: _error!, error: true),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        minimumSize: const Size(0, _maintenanceControlHeight),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 8,
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
        ),
      ),
    );
  }

  Future<void> _showCollected(
    String title,
    String text, {
    MachineMaintenanceReadout? report,
  }) async {
    _detailOpen = true;
    _timer?.cancel();
    await showAnimatedDialog<void>(
      context: context,
      builder: (context) => buildOpenHandDialog(
        maxHeight: MediaQuery.sizeOf(context).height * .7,
        child: SizedBox(
          width: math.min(
            MediaQuery.sizeOf(context).width * .86,
            machineMaintenanceCollectionIssue(
                      text,
                      title == '最近日志' ? 'logs' : '',
                    ) ==
                    null
                ? 900
                : 660,
          ),
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
                  padding: _maintenanceDetailPadding,
                  child: SingleChildScrollView(
                    child: _MaintenanceReadout(
                      text: text,
                      report: report,
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
    final usedMemory =
        total != null && total > 0 && available != null && available >= 0
        ? (total - available).clamp(0, total)
        : null;
    final memoryUsage = usedMemory == null ? null : usedMemory / total!;
    final swapUsage =
        swap != null && swap > 0 && freeSwap != null && freeSwap >= 0
        ? ((swap - freeSwap) / swap).clamp(0.0, 1.0)
        : null;
    final cores = data
        .counters('cpu')
        .keys
        .where((key) => RegExp(r'^cpu\d+$').hasMatch(key))
        .toList();
    final load = data
        .text('load')
        .trim()
        .split(RegExp(r'\s+'))
        .take(3)
        .toList();
    final hasLoad =
        load.length == 3 &&
        load.every((value) {
          final number = double.tryParse(value);
          return number != null && number.isFinite && number >= 0;
        });
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
    final panels = <Widget>[
      _MaintenanceCard(
        title: maintenanceLabel(context, '基本信息'),
        icon: Icons.info_outline_rounded,
        onOpen: () => _showCollected('系统原始信息', data.text('system')),
        scrollBody: false,
        child: _MaintenanceFacts(
          values: {
            '主机名': facts['主机名']!,
            '操作系统': facts['操作系统']!,
            '系统版本': facts['系统版本']!,
            '内核版本': facts['内核版本']!,
            '逻辑处理器': facts['逻辑处理器']!,
            '处理器': data.text('processor'),
          },
        ),
      ),
      _MaintenanceCard(
        title: maintenanceLabel(context, 'CPU 实时趋势'),
        icon: Icons.show_chart_rounded,
        scrollBody: false,
        child: _MaintenanceAnimatedColumn(
          children: [
            if (_cpuHistory.length < 2)
              _MaintenanceEmptyHint(
                key: const ValueKey('cpu-trend-empty'),
                icon: Icons.show_chart_rounded,
                message: _automatic
                    ? AppLocalizations.of(context)!.maintenanceAccumulating
                    : AppLocalizations.of(context)!.maintenanceTrendHelp,
              )
            else
              SizedBox(
                key: const ValueKey('cpu-trend-data'),
                height: 160,
                child: _MaintenanceTrend(points: List.of(_cpuHistory)),
              ),
            const SizedBox(height: 12),
            Tooltip(
              message: AppLocalizations.of(context)!.maintenanceLoadIntervals,
              child: _MaintenanceFacts(
                values: {'系统负载': hasLoad ? load.join(' / ') : '未提供'},
              ),
            ),
          ],
        ),
      ),
      _MaintenanceCard(
        title: AppLocalizations.of(context)!.maintenanceMemoryShare,
        icon: Icons.donut_large_rounded,
        fillWidth: true,
        scrollBody: false,
        child: memoryUsage == null
            ? _MaintenanceEmptyHint(
                message: maintenanceLabel(context, '暂无可用数据'),
              )
            : _MaintenanceVisual(
                donut: true,
                centerLabel: formatLocalizedByteSizeOf(context, total!),
                segments: [
                  OpenHandChartSegment(
                    label: AppLocalizations.of(context)!.maintenanceUsed,
                    value: usedMemory!,
                    color: cs.primary,
                    valueLabel: formatLocalizedByteSizeOf(context, usedMemory),
                  ),
                  OpenHandChartSegment(
                    label: AppLocalizations.of(context)!.maintenanceAvailable,
                    value: available!.clamp(0, total),
                    color: cs.tertiary,
                    valueLabel: formatLocalizedByteSizeOf(
                      context,
                      available.clamp(0, total),
                    ),
                  ),
                ],
              ),
      ),

      _MaintenanceCard(
        title: maintenanceLabel(context, '存储空间'),
        icon: Icons.storage_rounded,
        onOpen: () => _showCollected('文件系统', data.text('filesystems')),
        child: visibleVolumes.isEmpty
            ? _MaintenanceEmptyHint(
                message: maintenanceLabel(context, '暂无可读的文件系统'),
              )
            : _MaintenanceAnimatedColumn(
                children: [
                  for (final v in visibleVolumes)
                    Padding(
                      key: ValueKey((v.first, v.skip(5).join(' '))),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              _MaintenanceIconBadge(
                                icon: Icons.storage_rounded,
                                color: _maintenanceUsageColor(
                                  cs,
                                  (double.tryParse(v[4].replaceAll('%', '')) ??
                                          0) /
                                      100,
                                ),
                                size: 28,
                                iconSize: 14,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  v.skip(5).join(' '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          _MaintenanceUsage(
                            label: '存储空间',
                            icon: Icons.storage_rounded,
                            value:
                                (double.tryParse(v[4].replaceAll('%', '')) ??
                                    0) /
                                100,
                            color: _maintenanceUsageColor(
                              cs,
                              (double.tryParse(v[4].replaceAll('%', '')) ?? 0) /
                                  100,
                            ),
                          ),
                          _MaintenanceValue(
                            value:
                                '${formatLocalizedByteSizeOf(context, int.parse(v[2]) * 1024)} / ${formatLocalizedByteSizeOf(context, int.parse(v[1]) * 1024)}',
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
        scrollBody: false,
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
      _MaintenanceCard(
        title: maintenanceLabel(context, '采样状态'),
        icon: Icons.sensors_rounded,
        scrollBody: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MaintenanceStatus(
              label: _error != null
                  ? '数据可能过期'
                  : data.isComplete
                  ? '采集成功'
                  : '采集中',
              color: _error != null
                  ? OpenHandStatusColors.error
                  : data.isComplete
                  ? OpenHandStatusColors.success
                  : cs.primary,
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
                      '${AppLocalizations.of(context)!.maintenanceCoreLabel(core.substring(3))} · ${data.cpuUsage(_previous[0], core) == null ? '—' : '${(data.cpuUsage(_previous[0], core)! * 100).round()}%'}',
                  color: _maintenanceUsageColor(
                    cs,
                    data.cpuUsage(_previous[0], core),
                  ),
                ),
            ],
          ),
        ),
      _MaintenanceCard(
        title: maintenanceLabel(context, '资源提醒'),
        icon: Icons.notifications_none_rounded,
        child: _MaintenanceAnimatedColumn(
          children: [
            _MaintenanceStatus(
              label: warnings.isEmpty
                  ? '暂无阈值提醒'
                  : AppLocalizations.of(
                      context,
                    )!.maintenanceAlertCount('${warnings.length}'),
              color: warnings.isEmpty
                  ? OpenHandStatusColors.success
                  : OpenHandStatusColors.error,
            ),
            if (warnings.isNotEmpty) const SizedBox(height: 10),
            for (final warning in warnings.take(6))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: DecoratedBox(
                  decoration: _maintenanceTileDecoration(cs),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        const _MaintenanceIconBadge(
                          icon: Icons.warning_amber_rounded,
                          color: OpenHandStatusColors.error,
                          size: 28,
                          iconSize: 14,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _MaintenanceValue(
                            value: warning,
                            maxLines: null,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: cs.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ];
    return _MaintenanceAnimatedList(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      children: [
        _MaintenanceGrid(
          key: const ValueKey('maintenance-overview-summary'),
          minWidth: 200,
          maxColumns: 4,
          balanceColumns: true,
          children: [
            _metric(
              'CPU 使用率',
              cpu == null ? '—' : '${(cpu * 100).toStringAsFixed(1)}%',
              (int.tryParse(facts['逻辑处理器']!) ?? 0) > 0
                  ? AppLocalizations.of(
                      context,
                    )!.maintenanceCpuCount(facts['逻辑处理器']!)
                  : maintenanceLabel(context, '未提供'),
              Icons.memory_rounded,
              _maintenanceUsageColor(cs, cpu),
              cpu,
            ),
            _metric(
              '内存使用率',
              memoryUsage == null
                  ? '—'
                  : '${(memoryUsage * 100).toStringAsFixed(0)}%',
              usedMemory == null
                  ? '暂无数据'
                  : '${formatLocalizedByteSizeOf(context, usedMemory)} / ${formatLocalizedByteSizeOf(context, total!)}',
              Icons.storage_rounded,
              _maintenanceUsageColor(cs, memoryUsage),
              memoryUsage,
            ),
            _metric(
              'SWAP 使用量',
              swap == null || swap < 0 || freeSwap == null || freeSwap < 0
                  ? '—'
                  : formatLocalizedByteSizeOf(
                      context,
                      (swap - freeSwap).clamp(0, swap),
                    ),
              swap == 0
                  ? '未配置交换空间'
                  : AppLocalizations.of(context)!.maintenanceTotal(
                      swap == null || swap < 0
                          ? '—'
                          : formatLocalizedByteSizeOf(context, swap),
                    ),
              Icons.swap_horiz_rounded,
              _maintenanceUsageColor(cs, swapUsage),
              swapUsage,
            ),
            _metric(
              '运行时间',
              facts['运行时间']!,
              facts['操作系统']!,
              Icons.schedule_rounded,
              OpenHandStatusColors.info,
              null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _MaintenanceGrid(
          key: const ValueKey('maintenance-overview-resources'),
          minWidth: 300,
          children: panels,
        ),
        const SizedBox(height: _maintenanceGridGap),
        _MaintenanceCard(
          title: maintenanceLabel(context, '磁盘 IO'),
          scrollBody: false,
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
        ])
          if (data.text(section).isNotEmpty)
            Padding(
              key: ValueKey(section),
              padding: const EdgeInsets.only(top: 12),
              child: _MaintenanceCard(
                title: maintenanceLabel(
                  context,
                  section == 'disks'
                      ? '磁盘累计计数'
                      : _maintenanceSectionLabels[section] ?? section,
                ),
                icon: _maintenanceSectionIcon(section),
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
    final motion = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return OpenHandOperationalLiveContent(
      key: ValueKey(title),
      preserveState: true,
      value: (title, value, subtitle, icon, color, progress, motion),
      builder: () => Container(
        padding: const EdgeInsets.all(12),
        decoration: _maintenanceTileDecoration(cs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MaintenanceIconBadge(
              icon: icon,
              color: color,
              size: 40,
              iconSize: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Tooltip(
                    message: maintenanceLabel(context, title),
                    child: Text(
                      maintenanceLabel(context, title),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  _MaintenanceNumber(
                    raw: value,
                    padding: EdgeInsets.zero,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Tooltip(
                      message: maintenanceLabel(context, subtitle),
                      child: _MaintenanceValue(
                        value: maintenanceLabel(context, subtitle),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 7),
                  if (progress != null)
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(
                        begin: progress.clamp(0, 1),
                        end: progress.clamp(0, 1),
                      ),
                      duration: motion.entranceDuration,
                      curve: motion.curve.curve,
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
      ),
    );
  }

  Widget _rateTable(
    MachineMaintenanceSnapshot data,
    String section,
    List<String> headings,
    List<int> indexes,
    List<int> multipliers, {
    int previousTab = 0,
  }) {
    final keys = data.counters(section, colon: section == 'network').keys;
    if (keys.isEmpty) {
      return _MaintenanceEmptyHint(
        icon: Icons.speed_rounded,
        message: maintenanceLabel(context, '当前环境未提供可用计数器。'),
      );
    }
    final cs = Theme.of(context).colorScheme;
    final samples = <OpenHandChartSegment>[];
    for (final key in keys) {
      for (var i = 0; i < 2; i++) {
        final value = data.rate(
          _previous[previousTab],
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
    return _MaintenanceAnimatedColumn(
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
                        _previous[previousTab],
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
    final gpu = data.gpu;
    final reports = MachineGpuReport.parse(data.sections);
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
    String fieldLabel(String path) => maintenanceGpuFieldLabel(context, path);

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

    return _MaintenanceAnimatedList(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      empty: _MaintenanceEmptyHint(message: l10n.maintenanceGpuEmpty),
      children: [
        for (final device in gpu.devices) ...[
          _MaintenanceCard(
            key: ValueKey(('gpu', device.id)),
            title: device.name,
            scrollBody: false,
            icon: Icons.developer_board_rounded,
            child: _MaintenanceAnimatedColumn(
              children: [
                _MaintenanceGrid(
                  key: const ValueKey('maintenance-gpu-summary'),
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
                          'memoryUsed' || 'sharedUsed' => Icons.memory_rounded,
                          'renderer' => Icons.layers_outlined,
                          'cores' => Icons.developer_board_rounded,
                          'temperature' => Icons.thermostat_rounded,
                          _ => Icons.bolt_rounded,
                        },
                        switch (key) {
                          'memoryUsed' || 'sharedUsed' => cs.tertiary,
                          'temperature' || 'renderer' => cs.secondary,
                          _ => cs.primary,
                        },
                        null,
                      ),
                  ],
                ),
                if ((_gpuHistory[device.id]?.length ?? 0) >= 2 ||
                    ((device.metrics['memoryTotal'] ?? 0) > 0 &&
                        device.metrics['memoryUsed'] != null)) ...[
                  const SizedBox(height: 12),
                  _MaintenanceGrid(
                    key: const ValueKey('maintenance-gpu-charts'),
                    minWidth: 280,
                    children: [
                      if ((_gpuHistory[device.id]?.length ?? 0) >= 2)
                        _MaintenanceCard(
                          title: l10n.maintenanceGpuTrend,
                          icon: Icons.show_chart_rounded,
                          child: SizedBox(
                            height: 190,
                            child: _MaintenanceTrend(
                              key: ValueKey(device.id),
                              points: List.of(_gpuHistory[device.id]!),
                            ),
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
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                _MaintenanceCard(
                  title: maintenanceLabel(context, '基本信息'),
                  icon: Icons.info_outline_rounded,
                  scrollBody: false,
                  child: _MaintenanceFacts(
                    values: {
                      'UUID / ID': device.id,
                      l10n.maintenanceGpuSource: maintenanceGpuSourceLabel(
                        context,
                        device.source,
                      ),
                      for (final entry in device.info.entries)
                        switch (entry.key) {
                          'vendor' => l10n.maintenanceGpuVendor,
                          'driver' => l10n.maintenanceGpuDriver,
                          'bus' => l10n.maintenanceGpuBus,
                          'state' => maintenanceLabel(context, '状态'),
                          'metal' => l10n.maintenanceGpuMetal,
                          _ => l10n.maintenanceExtendedMetric(entry.key),
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
        if (reports.isNotEmpty) ...[
          _MaintenanceCard(
            title: l10n.maintenanceGpuComponents,
            icon: Icons.hub_outlined,
            scrollBody: false,
            child: _MaintenanceAnimatedColumn(
              spacing: _maintenanceGridGap,
              children: [
                for (final report in reports)
                  _MaintenanceSection(
                    key: ValueKey('gpu-component-${report.title}'),
                    icon: report.issue.isEmpty
                        ? Icons.developer_board_outlined
                        : Icons.info_outline_rounded,
                    accent: report.issue.isEmpty
                        ? cs.primary
                        : OpenHandStatusColors.warning,
                    title: report.title == 'NVLink · counters'
                        ? l10n.maintenanceGpuDetailLinkCounters
                        : report.title,
                    subtitle: report.issue.isEmpty
                        ? (report.raw.isNotEmpty
                              ? null
                              : '${report.rows.length} · ${l10n.maintenanceGpuFields}')
                        : switch (report.issue) {
                            'permission' || 'missing' || 'format' =>
                              maintenanceHealthLabel(context, report.issue),
                            'unsupported' => l10n.maintenanceHealthUnsupported,
                            _ => l10n.maintenanceGpuProbeUnavailable,
                          },
                    child: _MaintenanceAnimatedColumn(
                      spacing: _maintenanceGridGap,
                      children: [
                        if (report.raw.isNotEmpty)
                          _MaintenanceReadout(
                            text: report.raw,
                            section: 'gpu_report',
                          ),
                        if (report.rows.isNotEmpty)
                          report.rows.length > 24 && report.groups.length > 1
                              ? _MaintenanceAnimatedColumn(
                                  spacing: _maintenanceGridGap,
                                  children: [
                                    for (final group in report.groups.entries)
                                      _MaintenanceSection(
                                        key: ValueKey(
                                          'gpu-${report.title}-${group.key}',
                                        ),
                                        title: fieldLabel(group.key),
                                        subtitle:
                                            '${group.value.length} · ${l10n.maintenanceGpuFields}',
                                        child: _MaintenanceFields(
                                          fieldKeys: [
                                            for (final row in group.value)
                                              row[0],
                                          ],
                                          rows: [
                                            for (final row in group.value)
                                              [
                                                fieldLabel(row[0]),
                                                maintenanceGpuFieldValue(
                                                  context,
                                                  row[0],
                                                  row[1],
                                                ),
                                              ],
                                          ],
                                        ),
                                      ),
                                  ],
                                )
                              : _MaintenanceFields(
                                  fieldKeys: [
                                    for (final row in report.rows) row[0],
                                  ],
                                  rows: [
                                    for (final row in report.rows)
                                      [
                                        fieldLabel(row[0]),
                                        maintenanceGpuFieldValue(
                                          context,
                                          row[0],
                                          row[1],
                                        ),
                                      ],
                                  ],
                                ),
                      ],
                    ),
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
                  OpenHandOperationalRankRow(
                    value: 0,
                    cells: [
                      for (final cell in row)
                        maintenanceDetailValue(context, cell),
                    ],
                  ),
              ],
              paginate: gpu.displays.length > 20,
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
    final sample = data.sampledData('processes');
    final old = data.comparisonBase('processes', _previous[1]);
    final previousProcesses = {for (final p in old.processes) p.pid: p};
    double? cpu(MachineMaintenanceProcess p) {
      final before = previousProcesses[p.pid];
      final elapsed = (sample.uptime ?? 0) - (old.uptime ?? 0);
      if (old.identity != sample.identity ||
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
      key: const ValueKey('maintenance-process-charts'),
      minWidth: 300,
      children: [
        if (cpuRank.isNotEmpty)
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
        if (memoryRank.isNotEmpty && pageSize != null && pageSize > 0)
          _MaintenanceCard(
            title: AppLocalizations.of(context)!.maintenanceMemoryRank,
            icon: Icons.stacked_bar_chart_rounded,
            child: _MaintenanceVisual(
              segments: [
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
    void openProcess(OpenHandOperationalRankRow row, {String? action}) {
      final p = row.data! as MachineMaintenanceProcess;
      if (!_platform!.canInspectProcess(p)) return;
      _details(
        AppLocalizations.of(context)!.maintenanceProcessTitle(
          '${p.pid}',
          p.name.split('/').last.split('\\').last,
        ),
        _platform!.process(p),
        initialAction: action,
        actions: {
          for (final action in _platform!.processActions(p).entries)
            action.key: _platform!.process(p, action: action.value),
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: LayoutBuilder(
        key: const ValueKey('运维进程列表'),
        builder: (_, constraints) => SizedBox.expand(
          child: SingleChildScrollView(
            child: _MaintenanceAnimatedColumn(
              children: [
                charts,
                const SizedBox(height: 12),
                _MaintenanceBrowser(
                  toolbarBuilder: (viewToggle) => LayoutBuilder(
                    builder: (_, constraints) {
                      final search = SizedBox(
                        width: math.min(
                          _maintenanceSearchWidth,
                          constraints.maxWidth,
                        ),
                        child: TextField(
                          controller: _search,
                          style: const TextStyle(fontSize: 13, height: 1.2),
                          textAlignVertical: TextAlignVertical.center,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: maintenanceLabel(context, '搜索 PID 或进程名'),
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              size: 18,
                            ),
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
                      return OverflowBar(
                        alignment: MainAxisAlignment.spaceBetween,
                        overflowAlignment: OverflowBarAlignment.end,
                        spacing: 12,
                        overflowSpacing: 10,
                        children: [
                          search,
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth,
                            ),
                            child: Wrap(
                              alignment: WrapAlignment.end,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 8,
                              children: [sort, viewToggle],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
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
                                : formatByteSize(p.residentPages * pageSize),
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
                              color: _maintenanceStateColor(
                                Theme.of(context).colorScheme,
                                _maintenanceProcessState(p.state),
                              ),
                            ),
                          ],
                        ),
                    ],
                    onRowTap: openProcess,
                    rowActions: (row) => {
                      if (_platform!.canInspectProcess(
                        row.data! as MachineMaintenanceProcess,
                      ))
                        for (final action
                            in _platform!
                                .processActions(
                                  row.data! as MachineMaintenanceProcess,
                                )
                                .keys)
                          maintenanceLabel(context, action): () =>
                              openProcess(row, action: action),
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _services(MachineMaintenanceSnapshot data) {
    final targetPlatform = MachineMaintenancePlatformAdapter.forPlatform(
      data.text('platform'),
    );
    final targetShell = _commandShell;
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
    final processMetrics = <int, List<String>>{};
    for (final line in data.text('service_processes').split('\n')) {
      final fields = line.split('\t');
      final pid = int.tryParse(fields.first);
      if (pid != null && pid > 0 && fields.length >= 7) {
        processMetrics[pid] = fields;
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
        '用户',
        '配置文件',
        '启动时间',
        '结果',
      ],
      'launchd' => const [
        '名称',
        '状态',
        'PID',
        '退出代码',
        '用户',
        'CPU / 单核',
        '驻留内存',
        '运行时长',
        '累计 CPU 时间',
        '启动命令',
      ],
      'Windows SCM' => const [
        '名称',
        '状态',
        '描述',
        '启动方式',
        'PID',
        '用户',
        '退出代码',
        '路径',
        '服务类型',
        '允许停止',
        '允许暂停',
        '服务退出代码',
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
          for (final key in [
            'User',
            'FragmentPath',
            'ActiveEnterTimestamp',
            'Result',
          ])
            metrics[key]?.isNotEmpty == true ? metrics[key]! : '—',
        ];
      }
      if (manager == 'launchd') {
        final pid = fields.length > 1 ? int.tryParse(fields[1]) : null;
        final metrics = processMetrics[pid];
        final memory = metrics == null ? null : int.tryParse(metrics[3]);
        return [
          name,
          status,
          fields.length > 1 ? fields[1] : '—',
          fields.length > 2 ? fields[2] : '—',
          metrics?[1] ?? '—',
          metrics == null ? '—' : '${metrics[2]}%',
          memory == null || memory < 0 ? '—' : formatByteSize(memory * 1024),
          metrics?[4] ?? '—',
          metrics?[5] ?? '—',
          metrics?[6] ?? '—',
        ];
      }
      if (manager == 'Windows SCM') {
        return [
          name,
          status,
          columns.length > 2 ? columns[2] : '—',
          maintenanceDetailValue(context, startup[name] ?? '—'),
          for (var i = 3; i < 11; i++)
            columns.length > i && columns[i].isNotEmpty ? columns[i] : '—',
        ];
      }
      return [name, status, line];
    }

    String state(String line) {
      final fields = line.trim().split(RegExp(r'\s+'));
      if (manager == 'launchd') {
        return fields.length > 1 && (int.tryParse(fields[1]) ?? 0) > 0
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
    void openService(OpenHandOperationalRankRow row, {String? action}) {
      final name = row.cells.first;
      if (!(adapter?.accepts(name) ?? false)) return;
      _details(
        name,
        adapter!.command(name),
        service: true,
        initialAction: action,
        actions: {
          for (final action in adapter.actions.entries)
            action.key: adapter.command(name, action.value),
        },
      );
    }

    return _MaintenanceAnimatedList(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      children: [
        _MaintenanceGrid(
          key: const ValueKey('maintenance-service-summary'),
          minWidth: 210,
          children: [
            _metric(
              '已发现服务',
              '${rows.length}',
              manager,
              Icons.settings_suggest_outlined,
              OpenHandStatusColors.info,
              null,
            ),
            _metric(
              '运行中',
              '${rows.where((line) => const ['运行中', 'Running'].contains(state(line))).length}',
              '',
              Icons.play_circle_outline,
              OpenHandStatusColors.success,
              null,
            ),
            _metric(
              '异常服务',
              '${rows.where((line) => state(line) == '异常').length}',
              '',
              Icons.error_outline,
              OpenHandStatusColors.error,
              null,
            ),
          ],
        ),

        if (const {
          'failed',
          'partial',
        }.contains(data.text('service_processes_status'))) ...[
          const SizedBox(height: _maintenanceGridGap),
          _MaintenanceNotice(
            message: AppLocalizations.of(
              context,
            )!.maintenanceServiceMetricsUnavailable,
          ),
        ],
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            const height = _maintenanceControlHeight;
            final search = SizedBox(
              width: math.min(_maintenanceSearchWidth, constraints.maxWidth),
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
              for (final name in const ['startup'])
                if (data.text(name).isNotEmpty)
                  SizedBox(
                    height: height,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        backgroundColor: cs.surface.withValues(alpha: .72),
                        foregroundColor: cs.onSurface,
                        side: BorderSide(
                          color: cs.outlineVariant.withValues(alpha: .55),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
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
            if (buttons.isEmpty) {
              return Align(alignment: Alignment.centerLeft, child: search);
            }
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
                  Align(alignment: Alignment.centerLeft, child: search),
                  const SizedBox(height: 10),
                  Align(alignment: Alignment.centerRight, child: actions),
                ],
              );
            }
            return Row(
              children: [
                search,
                const SizedBox(width: 12),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: actions,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        _MaintenanceBrowser(
          title: AppLocalizations.of(
            context,
          )!.maintenanceServiceCount('${filtered.length}'),
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
                      color: _maintenanceStateColor(cs, state(line)),
                    ),
                  ],
                ),
            ],
            onRowTap: openService,
            rowActions: (row) => {
              if (adapter?.accepts(row.cells.first) ?? false)
                for (final action in adapter!.actions.keys)
                  maintenanceLabel(context, action): () =>
                      openService(row, action: action),
            },
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
                      ? OpenHandStatusColors.error
                      : entry.key == maintenanceLabel(context, '运行中')
                      ? OpenHandStatusColors.success
                      : cs.secondary,
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _MachineScheduledTaskPanel(
          key: ValueKey('scheduled-tasks-${data.identity}'),
          platform: data.text('platform'),
          refreshToken: data.isComplete ? data : null,
          enabled: !_loading,
          onFailure: () {
            if (mounted) setState(() => _automatic = false);
          },
          onBusy: (busy) {
            _scheduledTaskOperations += busy ? 1 : -1;
            if (!_scheduledTasksBusy &&
                _scheduledTasksRefreshPending &&
                mounted &&
                !_closing) {
              _scheduledTasksRefreshPending = false;
              scheduleMicrotask(() {
                if (mounted && !_closing) _refresh();
              });
            }
            _schedule();
          },
          run: (command, cancelled) async {
            final previous = _scheduledTaskPending;
            final completed = Completer<void>();
            _scheduledTaskPending = completed.future;
            try {
              // 快速切回板块时等待旧请求收尾，已离开的排队请求不再执行。
              await previous;
              if (!mounted || _closing || cancelled()) {
                throw const MachineTerminalUploadCancelled();
              }
              return await context
                  .read<MachineTerminalFileService>()
                  .runMaintenanceCommand(
                    sessionId: widget.sessionId,
                    terminalId: widget.terminalId,
                    command: targetPlatform.bind(data, command),
                    windowsScript: targetPlatform.windowsScript,
                    commandShell: targetShell,
                    timeout: Duration(seconds: _timeoutSeconds),
                    maxOutputCharacters: machineScheduledTaskOutputLimit,
                    isCancelled: () => !mounted || _closing || cancelled(),
                  );
            } finally {
              completed.complete();
              if (identical(_scheduledTaskPending, completed.future)) {
                _scheduledTaskPending = null;
              }
            }
          },
        ),
        const SizedBox(height: _maintenancePanelBottomInset),
      ],
    );
  }

  Widget _health(MachineMaintenanceSnapshot data) {
    final l = AppLocalizations.of(context)!;
    final titles = [
      maintenanceLabel(context, '系统与内核'),
      l.maintenanceHealthSessions,
      l.maintenanceHealthLogins,
      l.maintenanceHealthAccounts,
      l.maintenanceHealthPassword,
      l.maintenanceHealthSsh,
      l.maintenanceHealthTemperature,
      l.maintenanceHealthPower,
      l.maintenanceHealthDate,
      l.maintenanceHealthClock,
      l.maintenanceHealthNtp,
    ];
    const icons = [
      Icons.computer_outlined,
      Icons.people_outline,
      Icons.login,
      Icons.manage_accounts_outlined,
      Icons.password,
      Icons.key_outlined,
      Icons.thermostat,
      Icons.battery_charging_full,
      Icons.schedule,
      Icons.sync,
      Icons.access_time_filled,
    ];
    return _MaintenanceAnimatedList(
      padding: const EdgeInsets.fromLTRB(
        12,
        12,
        12,
        _maintenancePanelBottomInset,
      ),
      children: [
        _MaintenanceGrid(
          key: const ValueKey('maintenance-health-reports'),
          minWidth: 420,
          maxColumns: 2,
          children: [
            for (var i = 0; i < machineHealthSections.length; i++)
              Builder(
                key: ValueKey(machineHealthSections[i]),
                builder: (context) {
                  final key = machineHealthSections[i];
                  final raw = data.text('health_$key').trim();
                  final status = data.text('health_${key}_status').trim();
                  final report = MachineHealthReport.parse(
                    key,
                    raw,
                    status,
                    locale: Localizations.localeOf(context).toLanguageTag(),
                  );
                  return _MaintenanceCard(
                    title: titles[i],
                    icon: icons[i],
                    scrollBody: false,
                    accent: report.issue == null
                        ? OpenHandStatusColors.success
                        : report.issue == 'pending' ||
                              report.issue == 'empty' ||
                              report.issue == 'partial'
                        ? OpenHandStatusColors.warning
                        : OpenHandStatusColors.error,
                    trailing: _MaintenanceStatus(
                      label: report.issue == null
                          ? '健康'
                          : report.issue == 'pending' ||
                                report.issue == 'empty' ||
                                report.issue == 'partial'
                          ? '待检查'
                          : '异常',
                      color: report.issue == null
                          ? OpenHandStatusColors.success
                          : report.issue == 'pending' ||
                                report.issue == 'empty' ||
                                report.issue == 'partial'
                          ? OpenHandStatusColors.warning
                          : OpenHandStatusColors.error,
                    ),
                    child: _MaintenanceHealthContent(report: report, raw: raw),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _sections(MachineMaintenanceSnapshot data, List<String> names) {
    final cs = Theme.of(context).colorScheme;
    final connections = _maintenanceConnections(data);
    final listeners = MachineMaintenanceReadout.parse(
      data.text('listeners'),
      'listeners',
    );
    final adapters = MachineMaintenanceReadout.parse(
      data.text('addresses'),
      'addresses',
    );
    final states = <String, int>{};
    for (final row in connections) {
      final label = maintenanceLabel(context, row[3]);
      states[label] = (states[label] ?? 0) + 1;
    }
    final dns = MachineMaintenanceReadout.parse(data.text('dns'), 'dns').rows
        .where((row) => row[1] == 'nameserver')
        .map((row) => row[2])
        .toSet()
        .toList();
    final primary = _MaintenanceCard(
      title: maintenanceLabel(context, '连接与监听端口'),
      icon: Icons.hub_outlined,
      onOpen: () => _showCollected('连接与监听端口', data.text('sockets')),
      maxHeight: 470,
      child: connections.isEmpty
          ? _MaintenanceReadout(text: data.text('sockets'), section: 'sockets')
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
                    cellWidgets: [
                      null,
                      null,
                      null,
                      _MaintenanceStatus(
                        label: maintenanceLabel(context, row[3]),
                        color: switch (row[3].toUpperCase()) {
                          'LISTENING' ||
                          'LISTEN' ||
                          'ESTABLISHED' => OpenHandStatusColors.success,
                          'TIME_WAIT' ||
                          'CLOSE_WAIT' ||
                          'SYN_SENT' ||
                          'FIN_WAIT' => OpenHandStatusColors.warning,
                          _ => _maintenanceStateColor(
                            cs,
                            maintenanceLabel(context, row[3]),
                          ),
                        },
                      ),
                    ],
                  ),
              ],
            ),
    );
    final dnsCard = _MaintenanceCard(
      title: maintenanceLabel(context, 'DNS 服务器'),
      icon: Icons.language_rounded,
      scrollBody: false,
      onOpen: () => _showCollected('DNS 配置', data.text('dns')),
      child: dns.isEmpty
          ? _MaintenanceEmptyHint(
              message: maintenanceLabel(context, '暂无可解析的服务器地址'),
            )
          : _MaintenanceTable(
              headers: const ['名称', '地址'],
              rows: [
                for (var i = 0; i < dns.length; i++)
                  OpenHandOperationalRankRow(
                    rowKey: dns[i],
                    value: 0,
                    cells: [
                      AppLocalizations.of(
                        context,
                      )!.maintenanceServerNumber('${i + 1}'),
                      dns[i],
                    ],
                  ),
              ],
            ),
    );
    final diagnosticNames = names.where(
      (name) =>
          name != 'sockets' &&
          name != 'listeners' &&
          name != 'proxy' &&
          name != 'network' &&
          name != 'addresses' &&
          name != 'network_stats' &&
          name != 'firewall_status' &&
          name != 'dns' &&
          name != 'routes' &&
          name != 'firewall' &&
          data.sections.containsKey(name),
    );
    final diagnostics = _MaintenanceCard(
      title: maintenanceLabel(context, '诊断项目'),
      contentPadding: const EdgeInsets.all(8),
      scrollBody: false,
      icon: Icons.fact_check_outlined,
      child: _MaintenanceTable(
        maxBodyHeight: 360,
        headers: const ['诊断项目', '状态'],
        rows: [
          for (final name in diagnosticNames)
            OpenHandOperationalRankRow(
              rowKey: name,
              value: 0,
              cells: [
                maintenanceLabel(
                  context,
                  _maintenanceSectionLabels[name] ?? name,
                ),
                maintenanceLabel(
                  context,
                  _maintenanceOutputStatus(data.text(name)),
                ),
              ],
            ),
        ],
        onRowTap: (row) {
          final name = row.rowKey as String;
          _showCollected(
            _maintenanceSectionLabels[name] ?? name,
            data.text(name),
          );
        },
      ),
    );
    return _MaintenanceAnimatedList(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      children: [
        _MaintenanceGrid(
          key: const ValueKey('maintenance-network-summary'),
          minWidth: 210,
          children: [
            _metric(
              '已解析连接',
              data.hasSection('sockets') ? '${connections.length}' : '—',
              '',
              Icons.hub_outlined,
              OpenHandStatusColors.info,
              null,
            ),
            _metric(
              '监听端口',
              data.hasSection('listeners') && listeners.issue == null
                  ? '${listeners.rows.length}'
                  : '—',
              '',
              Icons.settings_input_antenna_rounded,
              OpenHandStatusColors.success,
              null,
            ),
            _metric(
              '网卡',
              data.hasSection('addresses') && adapters.issue == null
                  ? '${adapters.groups.length}'
                  : '—',
              '',
              Icons.settings_ethernet_rounded,
              OpenHandStatusColors.info,
              null,
            ),
            _metric(
              'DNS 服务器',
              data.hasSection('dns') ? '${dns.length}' : '—',
              '',
              Icons.language_rounded,
              OpenHandStatusColors.success,
              null,
            ),
            _metric(
              '诊断项目',
              '${names.length}',
              '',
              Icons.fact_check_outlined,
              OpenHandStatusColors.warning,
              null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (connections.isNotEmpty)
          _MaintenanceGrid(
            key: const ValueKey('maintenance-connection-charts'),
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
        primary,
        const SizedBox(height: _maintenanceGridGap),
        _MaintenanceGrid(
          key: const ValueKey('maintenance-network-configuration'),
          minWidth: 380,
          maxColumns: 2,
          children: [
            _MaintenanceCard(
              title: maintenanceLabel(context, '监听端口'),
              icon: Icons.settings_input_antenna_rounded,
              scrollBody: false,
              onOpen: () => _showCollected('监听端口', data.text('listeners')),
              child: _MaintenanceReadout(
                report: listeners,
                section: 'listeners',
              ),
            ),
            _MaintenanceCard(
              title: maintenanceLabel(context, '网卡地址与链路统计'),
              icon: Icons.settings_ethernet_rounded,
              scrollBody: false,
              onOpen: () => _showCollected('网卡地址与链路统计', data.text('addresses')),
              child: adapters.groups.isEmpty
                  ? _MaintenanceReadout(report: adapters, section: 'addresses')
                  : _MaintenanceTable(
                      headers: const ['网卡', '状态', 'MAC 地址', '地址'],
                      maxBodyHeight: 360,
                      rows: [
                        for (final entry in adapters.groups.entries)
                          OpenHandOperationalRankRow(
                            rowKey: entry.key,
                            value: 0,
                            cells: [
                              entry.key,
                              maintenanceDetailValue(
                                context,
                                entry.value.rows
                                        .where(
                                          (row) =>
                                              row[0] == '状态' ||
                                              row[0] == '链路状态',
                                        )
                                        .map((row) => row[1])
                                        .lastOrNull ??
                                    '—',
                              ),
                              entry.value.rows
                                      .where((row) => row[0] == 'MAC 地址')
                                      .map((row) => row[1])
                                      .firstOrNull ??
                                  '—',
                              entry.value.rows
                                  .where(
                                    (row) => const [
                                      '地址',
                                      'IPv4 地址',
                                      'IPv6 地址',
                                    ].contains(row[0]),
                                  )
                                  .map((row) => row[1])
                                  .join(' · '),
                            ],
                          ),
                      ],
                      onRowTap: (row) => _showCollected(
                        '网卡详情',
                        data.text('addresses'),
                        report: adapters.groups[row.rowKey],
                      ),
                    ),
            ),
          ],
        ),
        const SizedBox(height: _maintenanceGridGap),
        _MaintenanceCard(
          title: maintenanceLabel(context, '网络吞吐'),
          icon: Icons.speed_rounded,
          scrollBody: false,
          child: _rateTable(
            data,
            'network',
            const [
              '网卡',
              '接收 / 秒',
              '发送 / 秒',
              '接收包 / 秒',
              '发送包 / 秒',
              '接收错误 / 秒',
              '发送错误 / 秒',
              '接收丢包 / 秒',
              '发送丢包 / 秒',
            ],
            const [0, 8, 1, 9, 2, 10, 3, 11],
            const [1, 1, 1, 1, 1, 1, 1, 1],
            previousTab: 3,
          ),
        ),
        const SizedBox(height: _maintenanceGridGap),
        _MaintenanceCard(
          title: maintenanceLabel(context, '系统网络代理'),
          icon: Icons.lan_outlined,
          scrollBody: false,
          child: _MaintenanceReadout(
            text: data.text('proxy'),
            section: 'proxy',
          ),
        ),
        const SizedBox(height: _maintenanceGridGap),
        _MaintenanceEgressCard(
          report: _egress,
          busy: _egressBusy,
          error: _egressError,
          onRefresh: _loading
              ? null
              : () => _refresh(
                  manual: true,
                  detectShell: false,
                  egressOnly: true,
                ),
        ),
        const SizedBox(height: _maintenanceGridGap),
        _MaintenanceGrid(
          key: const ValueKey('maintenance-network-diagnostics'),
          maxColumns: 2,
          children: [
            dnsCard,
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
        ),
        const SizedBox(height: _maintenanceGridGap),
        _MaintenanceCard(
          title: '路由表',
          scrollBody: false,
          icon: Icons.alt_route_rounded,
          onOpen: () => _showCollected('地址与路由', data.text('routes')),
          child: _MaintenanceReadout(
            text: data.text('routes'),
            section: 'routes',
          ),
        ),
        const SizedBox(height: _maintenanceGridGap),
        _MaintenanceCard(
          title: '防火墙与 NAT',
          icon: Icons.shield_outlined,
          scrollBody: false,
          child: _MaintenanceAnimatedColumn(
            spacing: _maintenanceGridGap,
            children: [
              for (final name in const [
                'firewall_status',
                'firewall',
                'firewall_ipvfour',
                'firewall_ipvsix',
                'firewall_rules',
                'firewall_nat',
                'firewall_states',
              ].where(data.sections.containsKey))
                _MaintenanceSection(
                  title: _maintenanceSectionLabels[name] ?? name,
                  icon: Icons.shield_outlined,
                  subtitle: _maintenanceOutputStatus(data.text(name)),
                  child: _MaintenanceReadout(
                    text: data.text(name),
                    section: name,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: _maintenanceGridGap),
        _MaintenanceCard(
          title: maintenanceLabel(context, '网络协议与错误统计'),
          icon: Icons.monitor_heart_outlined,
          scrollBody: false,
          child: _MaintenanceReadout(
            text: data.text('network_stats'),
            section: 'network_stats',
          ),
        ),
        const SizedBox(height: _maintenanceGridGap),
        diagnostics,
        const SizedBox(height: _maintenancePanelBottomInset),
      ],
    );
  }
}

class _MaintenanceEgressCard extends StatelessWidget {
  const _MaintenanceEgressCard({
    required this.report,
    required this.busy,
    required this.error,
    required this.onRefresh,
  });
  final MachineEgressReport? report;
  final bool busy;
  final String? error;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final data = report;
    return _MaintenanceCard(
      title: l10n.maintenanceEgressTitle,
      icon: Icons.public_rounded,
      accent: OpenHandStatusColors.info,
      scrollBody: false,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (data != null) ...[
            _MachineTerminalIconButton(
              icon: Icons.copy_rounded,
              tooltip: '${l10n.commonCopy} IP',
              onPressed: () => copyOpenHandTextToClipboard(
                context: context,
                text: data.ip,
                logTag: 'home_machine_maintenance',
                logAction: '复制出口地址',
              ),
            ),
            const SizedBox(width: 8),
          ],
          _MachineTerminalIconButton(
            tooltip: l10n.maintenanceEgressRefresh,
            onPressed: busy ? null : onRefresh,
            icon: Icons.refresh_rounded,
          ),
        ],
      ),
      child: _MaintenanceAnimatedColumn(
        spacing: _maintenanceGridGap,
        children: [
          if (data == null && busy)
            SizedBox(
              height: 120,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.maintenanceEgressLoading,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          if (error != null)
            _MaintenanceEmptyHint(
              icon: Icons.info_outline_rounded,
              message: error == 'tool'
                  ? l10n.maintenanceEgressMissingTool
                  : data == null
                  ? l10n.maintenanceEgressFailed
                  : l10n.maintenanceEgressStale,
            ),
          if (data == null && !busy && error == null)
            _MaintenanceEmptyHint(message: l10n.maintenanceEgressPending),
          if (data != null) ...[
            Container(
              key: const ValueKey('egress-summary'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: LayoutBuilder(
                builder: (context, bounds) {
                  final address = Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _MaintenanceValue(
                        value: data.ip,
                        selectable: true,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      _MaintenanceStatus(
                        label: data.version,
                        color: OpenHandStatusColors.info,
                      ),
                    ],
                  );
                  final source = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (busy) ...[
                        const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: _MaintenanceValue(
                          value:
                              '${l10n.maintenanceEgressSource} · ${data.source}\n${l10n.maintenanceUpdated(MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(data.collectedAt)))}',
                          maxLines: null,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  );
                  if (bounds.maxWidth <
                      MediaQuery.textScalerOf(context).scale(640)) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [address, const SizedBox(height: 8), source],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: address),
                      const SizedBox(width: 20),
                      source,
                    ],
                  );
                },
              ),
            ),
            for (final entry in data.groups.entries)
              if (entry.key == '地理位置' || entry.key == '网络归属')
                _MaintenanceCard(
                  key: ValueKey(('egress-group', entry.key)),
                  title: maintenanceLabel(context, entry.key),
                  icon: entry.key == '地理位置'
                      ? Icons.location_on_outlined
                      : Icons.hub_outlined,
                  accent: entry.key == '地理位置'
                      ? OpenHandStatusColors.info
                      : OpenHandStatusColors.success,
                  scrollBody: false,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: _MaintenanceEgressFields(
                    rows: entry.value,
                    report: data,
                  ),
                )
              else
                _MaintenanceSection(
                  key: ValueKey(('egress-group', entry.key)),
                  title: entry.key,
                  icon: switch (entry.key) {
                    '时区信息' => Icons.schedule_rounded,
                    '国家信息' => Icons.flag_outlined,
                    _ => Icons.data_object_rounded,
                  },
                  accent: entry.key == '国家信息'
                      ? OpenHandStatusColors.warning
                      : cs.tertiary,
                  child: _MaintenanceEgressFields(
                    rows: entry.value,
                    report: data,
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

/// 数量不定的出口属性使用紧凑详情行，共享字号与间距，不嵌套滚动表格。
class _MaintenanceEgressFields extends StatelessWidget {
  const _MaintenanceEgressFields({required this.rows, required this.report});
  final List<List<String>> rows;
  final MachineEgressReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final occurrences = <String, int>{};
    return _MaintenanceGrid(
      minWidth: 460,
      maxColumns: 2,
      children: [
        for (var index = 0; index < rows.length; index++)
          Container(
            key: ValueKey((
              rows[index][0],
              occurrences.update(
                rows[index][0],
                (count) => count + 1,
                ifAbsent: () => 0,
              ),
            )),
            constraints: const BoxConstraints(minHeight: 42),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: .35),
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: LayoutBuilder(
              builder: (context, bounds) {
                final row = rows[index];
                final translated = maintenanceDetailLabel(context, row[0]);
                final unknown =
                    translated == row[0] &&
                    RegExp(r'^[\x00-\x7F]+$').hasMatch(row[0]);
                final label = Tooltip(
                  message: row[0],
                  child: Text(
                    unknown
                        ? '${l10n.maintenanceEgressExtraField} ${index + 1}'
                        : translated,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                );
                final value = _MaintenanceValue(
                  value: maintenanceEgressValue(
                    context,
                    report,
                    row[0],
                    row[1],
                  ),
                  selectable: true,
                  maxLines: null,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    height: 1.5,
                  ),
                );
                final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
                if (bounds.maxWidth < 400 * scale) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [label, const SizedBox(height: 4), value],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: math.min(bounds.maxWidth * .32, 200 * scale),
                      child: label,
                    ),
                    const SizedBox(width: 20),
                    Expanded(child: value),
                  ],
                );
              },
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
  final coreCount =
      int.tryParse(data.text('core_count')) ??
      data
          .counters('cpu')
          .keys
          .where((key) => RegExp(r'^cpu\d+$').hasMatch(key))
          .length;
  return {
    '主机名': data.text('host'),
    '操作系统': name,
    '系统版本': version.isEmpty ? '未提供' : version,
    '内核版本': kernel == null || kernel.isEmpty ? '未提供' : kernel,
    '逻辑处理器': coreCount > 0 ? '$coreCount' : '未提供',
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
  return readout.fields || readout.raw ? [] : readout.rows;
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

String _maintenanceReadoutValue(
  BuildContext context,
  String key,
  String value,
) {
  final normalized = key.trim();
  final plain = value.trim();
  final leaf = normalized.split(' / ').last;
  if (const {
    'Status',
    'State',
    'state',
    'status',
    'phase',
    '状态',
  }.contains(leaf)) {
    final state = maintenanceContainerState(context, plain);
    if (state != plain) return state;
  }
  if (const {'STAT', 'STATE', 'State', '状态', 'state'}.contains(normalized) &&
      RegExp(r'^[RSIZTD][<NsLsl+]*$').hasMatch(plain)) {
    return maintenanceLabel(context, _maintenanceProcessState(plain));
  }
  if (const {'RSS', 'VSZ', '驻留内存', '虚拟内存'}.contains(normalized)) {
    final bytes = int.tryParse(plain);
    if (bytes != null && bytes >= 0) return formatByteSize(bytes * 1024);
  }
  if (const {'%CPU', '%MEM', 'CPU / 单核', '内存使用率'}.contains(normalized) &&
      num.tryParse(plain) != null &&
      !plain.contains('%')) {
    return '$plain%';
  }
  return maintenanceDetailValue(context, value, field: key);
}

IconData _maintenanceFieldIcon(String key) => switch (key) {
  '路径' ||
  '启动命令' ||
  '启动参数' ||
  'Path' ||
  'NAME' ||
  'Program' ||
  'COMMAND' => Icons.route_outlined,
  '进程' || '名称' || '进程类型' || 'Process' => Icons.memory_rounded,
  'PID' || '父进程 ID' || 'PPID' => Icons.tag_rounded,
  '用户' || 'USER' || 'UserName' => Icons.person_outline,
  '状态' || 'STAT' || 'STATE' || 'State' => Icons.circle,
  '系统版本' || 'Version' || 'OS Version' => Icons.info_outline,
  '加载地址' || 'Load Address' => Icons.place_outlined,
  '驻留内存' || '虚拟内存' || 'RSS' || 'VSZ' => Icons.sd_storage_outlined,
  'CPU / 单核' || '累计 CPU 时间' || '%CPU' || 'TIME' => Icons.speed_rounded,
  '创建时间' || '本地时间' || '登录时间' || 'STARTED' => Icons.schedule_rounded,
  '控制台' || '终端' => Icons.terminal_rounded,
  _ => Icons.data_object_outlined,
};

String _maintenanceOutputStatus(String text) => text.trim().isEmpty
    ? '暂无可用数据'
    : machineMaintenanceCollectionIssue(text, '') != null ||
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
    return _content = _MaintenanceAnimatedColumn(
      children: [
        for (var t = 0; t < metrics.tables.length; t++)
          if (metrics.tables[t].rows.isEmpty)
            _MaintenanceEmptyHint(message: maintenanceLabel(context, '暂无可用数据'))
          else if ((section != 'sensors' &&
                  metrics.tables[t].headers.contains('数值')) ||
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
                          section: section,
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
    context.watch<SettingsController?>();
    final motion = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
    final cs = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context);
    final icon = _maintenanceSectionIcon(section);
    final tones = [
      cs.primary,
      cs.tertiary,
      cs.secondary,
      OpenHandStatusColors.info,
    ];
    return _MaintenanceGrid(
      key: const ValueKey('maintenance-metric-summary'),
      minWidth: pressure ? 280 : 200,
      maxColumns: pressure ? 3 : 4,
      children: [
        for (var i = 0; i < table.rows.length; i++)
          OpenHandOperationalLiveContent(
            key: ValueKey((
              section,
              table.rows[i].first,
              pressure ? table.rows[i][1] : null,
            )),
            preserveState: true,
            value: (
              table.rows[i].join("\u0000"),
              table.headers.join("\u0000"),
              section,
              motion,
              pressure,
              tones[i % tones.length],
            ),
            builder: () {
              final row = table.rows[i];
              final tone = tones[i % tones.length];
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: _maintenanceTileDecoration(cs),
                child: pressure
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              _MaintenanceIconBadge(
                                icon: icon,
                                color: tone,
                                size: 32,
                                iconSize: 16,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '${maintenanceMetricLabel(context, row[0], '资源')} · ${maintenanceMetricLabel(context, row[1], '范围')}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          for (var i = 2; i < 5; i++) ...[
                            const SizedBox(height: 10),
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
                                    ((double.tryParse(
                                                  row[i].replaceAll('%', ''),
                                                ) ??
                                                0) /
                                            100)
                                        .clamp(0, 1),
                              ),
                              duration: motion.entranceDuration,
                              curve: motion.curve.curve,
                              builder: (_, value, _) => LinearProgressIndicator(
                                value: value.clamp(0, 1),
                                color: _maintenanceUsageColor(cs, value),
                                minHeight: 6,
                                borderRadius: BorderRadius.circular(
                                  kOpenHandRadius4,
                                ),
                                backgroundColor: cs.surfaceContainerHighest,
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Text(
                            maintenanceLabel(context, table.headers.last),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          _MaintenanceNumber(
                            raw: row.last,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: tone,
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
                              number != null &&
                                  multiplier != null &&
                                  number >= 0
                              ? formatByteSize(
                                  number * multiplier,
                                  languageCode: locale.languageCode,
                                  scriptCode: locale.scriptCode,
                                  countryCode: locale.countryCode,
                                )
                              : '${maintenanceMetricLabel(context, row[1], '数值')}${unit == '—' || number == null ? '' : ' ${maintenanceMetricLabel(context, unit, '单位')}'}';
                          return Tooltip(
                            message: row.join(' · '),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _MaintenanceIconBadge(icon: icon, color: tone),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        maintenanceMetricLabel(
                                          context,
                                          row.first,
                                          '名称',
                                          section: section,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      _MaintenanceNumber(
                                        raw: row[1],
                                        unit: unit == '—'
                                            ? ''
                                            : maintenanceMetricLabel(
                                                context,
                                                unit,
                                                '单位',
                                              ),
                                        readable: multiplier != null
                                            ? value
                                            : null,
                                        maxLines: 2,
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                          color: tone,
                                        ),
                                      ),
                                      if (row.length > 3) ...[
                                        const SizedBox(height: 6),
                                        _MaintenanceValue(
                                          value: row[3],
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              );
            },
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
    this.toolbarBuilder,
    this.title,
  });
  final _MaintenanceTable table;
  final Map<String, List<String>> parents;
  final String query;
  final int nameColumn;
  final bool groupNames;
  final Widget Function(Widget viewToggle)? toolbarBuilder;
  final String? title;

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
      rowActions: widget.table.rowActions,
    );
    final tree = ConstrainedBox(
      key: const ValueKey(true),
      constraints: BoxConstraints(maxHeight: widget.table.maxBodyHeight),
      child: entries.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(18),
              child: _MaintenanceEmptyHint(
                message: maintenanceLabel(context, '暂无可用数据'),
              ),
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
                  duration: motion.entranceDuration,
                  builder: (_, value, child) =>
                      Opacity(opacity: value.clamp(0, 1), child: child),
                  child: CustomPaint(
                    foregroundPainter: _MaintenanceTreeGuide(
                      depth: math.min(depth, 8),
                      color: cs.outlineVariant,
                      rtl: Directionality.of(context) == TextDirection.rtl,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: index.isEven
                            ? cs.surface
                            : cs.surfaceContainerLow,
                        border: Border(
                          bottom: BorderSide(
                            color: cs.outlineVariant.withValues(alpha: .35),
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsetsDirectional.only(
                          start: 12 + math.min(depth, 8) * 20.0,
                          end: 12,
                          top: 6,
                          bottom: 6,
                        ),
                        child: Row(
                          spacing: 8,
                          children: [
                            SizedBox(
                              width: 32,
                              height: 32,
                              child: branches.isEmpty
                                  ? Icon(
                                      Icons.subdirectory_arrow_right_rounded,
                                      size: 16,
                                      color: cs.outline,
                                    )
                                  : IconButton(
                                      style: IconButton.styleFrom(
                                        minimumSize: const Size.square(32),
                                        maximumSize: const Size.square(32),
                                        padding: EdgeInsets.zero,
                                        backgroundColor: Colors.transparent,
                                        hoverColor: Colors.transparent,
                                        highlightColor: Colors.transparent,
                                        overlayColor: Colors.transparent,
                                        shadowColor: Colors.transparent,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                      ),
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
                                splashColor: Colors.transparent,
                                highlightColor: Colors.transparent,
                                overlayColor: _maintenanceNoOverlay,
                                onTap: row == null
                                    ? null
                                    : () => widget.table.onRowTap?.call(row),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  spacing: 4,
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        _MaintenanceValue(
                                          value: maintenanceDetailValue(
                                            context,
                                            row == null
                                                ? id.substring(6)
                                                : row.cells[widget.nameColumn],
                                          ),
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: row == null
                                                ? cs.primary
                                                : cs.onSurface,
                                          ),
                                        ),
                                        if (row != null)
                                          for (final i
                                              in widget.nameColumn == 1
                                                  ? const [0, 2, 3, 4, 6]
                                                  : const [1, 2, 3, 4])
                                            if (i < row.cells.length &&
                                                i < widget.table.headers.length)
                                              widget.table.headers[i] == '状态'
                                                  ? _MaintenanceStatus(
                                                      label: row.cells[i],
                                                      color:
                                                          _maintenanceStateColor(
                                                            cs,
                                                            row.cells[i],
                                                          ),
                                                    )
                                                  : Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 1,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: cs
                                                            .surfaceContainerHighest
                                                            .withValues(
                                                              alpha: .5,
                                                            ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                        border: Border.all(
                                                          color: cs
                                                              .outlineVariant
                                                              .withValues(
                                                                alpha: .45,
                                                              ),
                                                        ),
                                                      ),
                                                      child: _MaintenanceValue(
                                                        value:
                                                            '${maintenanceLabel(context, widget.table.headers[i])} ${row.cells[i]}',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: cs
                                                              .onSurfaceVariant,
                                                        ),
                                                      ),
                                                    ),
                                      ],
                                    ),
                                    if (row != null &&
                                        widget.nameColumn == 0 &&
                                        !widget.groupNames &&
                                        (widget.parents[id]?.isNotEmpty ??
                                            false))
                                      _MaintenanceValue(
                                        value:
                                            '${l10n.maintenanceTreeDependencies}: ${widget.parents[id]!.join(', ')}',
                                        maxLines: null,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            if (row != null && widget.table.onRowTap != null)
                              OpenHandOperationalRowMenu(
                                onDetails: () => widget.table.onRowTap!(row),
                                actions:
                                    widget.table.rowActions?.call(row) ??
                                    const {},
                              ),
                            if (branches.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.primary.withValues(alpha: .1),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: _MaintenanceValue(
                                  value: '${branches.length}',
                                  style: TextStyle(
                                    color: cs.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
    final viewToggle = SizedBox(
      height: _maintenanceControlHeight,
      child: SegmentedButton<bool>(
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 14),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          textStyle: WidgetStatePropertyAll(
            Theme.of(context).textTheme.labelLarge?.copyWith(
              fontSize: 13,
              height: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          // 选中配色交给全局分段按钮主题统一管理。
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? null : cs.surface,
          ),
          side: WidgetStatePropertyAll(BorderSide(color: cs.outlineVariant)),
          elevation: const WidgetStatePropertyAll(0),
          shadowColor: const WidgetStatePropertyAll(Colors.transparent),
          overlayColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.pressed)
                ? cs.primary.withValues(alpha: .12)
                : Colors.transparent,
          ),
          // 内部分段默认高 40px，收至外层的 34px，避免文字与图标向下偏移。
          visualDensity: const VisualDensity(vertical: -1.5),
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
    );
    final content = _MaintenanceAnimatedSize(
      child: AnimatedSwitcher(
        duration: motion.entranceDuration,
        reverseDuration: motion.exitDuration,
        switchInCurve: OpenHandBoundedCurve(motion.curve.curve),
        switchOutCurve: OpenHandBoundedCurve(motion.curve.reverseCurve),
        child: _tree
            ? ClipRRect(
                key: const ValueKey(true),
                borderRadius: BorderRadius.circular(12),
                child: Material(color: cs.surface, child: tree),
              )
            : table,
      ),
    );
    if (widget.title != null) {
      return _MaintenanceCard(
        title: widget.title!,
        icon: Icons.view_list_outlined,
        trailing: viewToggle,
        wrapHeader: true,
        scrollBody: false,
        child: content,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child:
              widget.toolbarBuilder?.call(viewToggle) ??
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: viewToggle,
              ),
        ),
        content,
      ],
    );
  }
}

class _MaintenanceTreeGuide extends CustomPainter {
  const _MaintenanceTreeGuide({
    required this.depth,
    required this.color,
    required this.rtl,
  });
  final int depth;
  final Color color;
  final bool rtl;
  @override
  void paint(Canvas canvas, Size size) {
    if (rtl) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final pen = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var level = 0; level < depth; level++) {
      final x = 28.0 + level * 20;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), pen);
      if (level == depth - 1) {
        canvas.drawLine(
          Offset(x, size.height / 2),
          Offset(x + 10, size.height / 2),
          pen,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MaintenanceTreeGuide oldDelegate) =>
      depth != oldDelegate.depth ||
      color != oldDelegate.color ||
      rtl != oldDelegate.rtl;
}

class _MaintenanceTable extends StatelessWidget {
  const _MaintenanceTable({
    super.key,
    required this.headers,
    required this.rows,
    this.onRowTap,
    this.rowActions,
    this.maxBodyHeight = 220,
    this.limitToViewport = true,
    this.paginate = true,
    this.columnAlignments = const {},
    this.minimumColumnWidths = const {},
  });
  final List<String> headers;
  final List<OpenHandOperationalRankRow> rows;
  final ValueChanged<OpenHandOperationalRankRow>? onRowTap;
  final Map<String, VoidCallback> Function(OpenHandOperationalRankRow)?
  rowActions;
  final double maxBodyHeight;
  final bool limitToViewport;
  final bool paginate;
  final Map<int, Alignment> columnAlignments;
  final Map<int, double> minimumColumnWidths;
  @override
  Widget build(BuildContext context) {
    final timestampColumns = {
      for (var i = 0; i < headers.length; i++)
        if (maintenanceIsTimestampColumn(context, headers[i])) i,
    };
    return OpenHandOperationalRankTable(
      headers: headers
          .map((label) => maintenanceLabel(context, label))
          .toList(),
      rows: [
        for (final row in rows)
          OpenHandOperationalRankRow(
            cells: [
              for (var i = 0; i < row.cells.length; i++)
                timestampColumns.contains(i)
                    ? machineMaintenanceTimestamp(
                            row.cells[i],
                            allowEpoch: true,
                          ) ??
                          row.cells[i]
                    : row.cells[i],
            ],
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
                    !timestampColumns.contains(i) &&
                    (machineMaintenanceReadableDuration(
                              row.cells[i],
                              field: headers[i],
                            ) !=
                            null ||
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
                        }.contains(headers[i])))
                  _MaintenanceNumber(
                    raw: row.cells[i],
                    field: headers[i],
                    maxLines: 2,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                    ),
                    unit: headers[i].contains('字节') ? 'B' : '',
                  )
                else
                  null,
            ],
          ),
      ],
      sortByValue: false,
      paginate: paginate,
      compact: true,
      animateCellChanges: true,
      animateRows: true,
      onRowTap: onRowTap,
      rowActions: rowActions,
      maxBodyHeight: limitToViewport
          ? math.min(maxBodyHeight, MediaQuery.sizeOf(context).height * .45)
          : maxBodyHeight,
      emptyLabel: maintenanceLabel(context, '暂无可用数据'),
      minimumColumnWidths: {
        for (var i = 0; i < headers.length; i++)
          if (headers[i] == '累计 CPU 时间' || timestampColumns.contains(i))
            i:
                (timestampColumns.contains(i)
                    ? _maintenanceTimestampColumnMinWidth
                    : _maintenanceCpuTimeColumnMinWidth) *
                MediaQuery.textScalerOf(context).scale(13) /
                13,
        ...minimumColumnWidths,
      },
      semanticsLabel: headers
          .map((label) => maintenanceLabel(context, label))
          .join(' · '),
      columnAlignments: {
        for (var i = 0; i < headers.length; i++) i: Alignment.centerLeft,
        ...columnAlignments,
      },
    );
  }
}

class _MaintenanceFacts extends StatelessWidget {
  const _MaintenanceFacts({required this.values});
  final Map<String, String> values;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
    return _MaintenanceGrid(
      minWidth: 380,
      maxColumns: 2,
      children: [
        for (final entry in values.entries)
          LayoutBuilder(
            key: ValueKey(entry.key),
            builder: (context, bounds) {
              final label = Text(
                maintenanceLabel(context, entry.key),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              );
              final value = _MaintenanceValue(
                value: entry.value.isEmpty || entry.value == '未提供'
                    ? maintenanceLabel(context, '未提供')
                    : entry.value,
                selectable: true,
                maxLines: null,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              );
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: bounds.maxWidth < 260 * scale
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 4,
                        children: [label, value],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: math.min(bounds.maxWidth * .34, 140 * scale),
                            child: label,
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: value),
                        ],
                      ),
              );
            },
          ),
      ],
    );
  }
}

class _MaintenanceStatus extends StatelessWidget {
  const _MaintenanceStatus({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    widthFactor: 1,
    heightFactor: 1,
    child: AnimatedContainer(
      duration: openHandMotionSettingsOf(
        context,
        OpenHandMotionSettingsScope.dialog,
      ).entranceDuration,
      curve: kOpenHandSwitchInCurve,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 7, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: _MaintenanceValue(
              value: maintenanceLabel(context, label),
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
    super.key,
    required this.raw,
    this.unit = '',
    this.field = '',
    this.readable,
    this.style,
    this.maxLines = 1,
    this.padding = const EdgeInsets.symmetric(vertical: 4),
  });
  final String raw;
  final String unit;
  final String field;
  final String? readable;
  final TextStyle? style;
  final int maxLines;
  final EdgeInsetsGeometry padding;
  @override
  State<_MaintenanceNumber> createState() => _MaintenanceNumberState();
}

class _MaintenanceNumberState extends State<_MaintenanceNumber> {
  bool _exact = false;

  @override
  Widget build(BuildContext context) {
    final match = RegExp(
      r'^(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\s*(B|[KMGTPE]i?B|ms|s|min|h|d|%)?$',
    ).firstMatch(widget.raw);
    final number = match == null ? null : double.tryParse(match[1]!);
    final unit = widget.unit.isNotEmpty ? widget.unit : match?[2] ?? '';
    final raw = widget.unit.isEmpty
        ? widget.raw
        : '${widget.raw} ${widget.unit}';
    final duration = machineMaintenanceReadableDuration(
      raw,
      field: widget.field,
      languageCode: Localizations.localeOf(context).languageCode,
    );
    var readable = widget.readable ?? duration ?? raw;
    if (widget.readable == null &&
        duration == null &&
        number != null &&
        number.isFinite &&
        !RegExp(r'^[KMGTPE]i?B$').hasMatch(unit)) {
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
        if (number.abs() >= 1000) {
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
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          overlayColor: _maintenanceNoOverlay,
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _exact = !_exact),
          child: Padding(padding: widget.padding, child: value),
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
    this.selectable = false,
    this.alignment = Alignment.centerLeft,
  });
  final String value;
  final TextStyle? style;
  final int? maxLines;
  final bool selectable;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => OpenHandOperationalLiveContent(
    value: (value, style, maxLines, selectable),
    alignment: alignment,
    builder: () => selectable
        ? SelectableText(value, maxLines: maxLines, style: style)
        : Text(
            value,
            maxLines: maxLines,
            overflow: maxLines == null
                ? TextOverflow.clip
                : TextOverflow.ellipsis,
            style: style,
          ),
  );
}

class _MaintenanceUsage extends StatelessWidget {
  const _MaintenanceUsage({
    required this.label,
    required this.value,
    required this.color,
    this.icon = Icons.speed_rounded,
  });
  final String label;
  final double? value;
  final Color color;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    context.watch<SettingsController?>();
    final motion = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          _MaintenanceIconBadge(
            icon: icon,
            color: color,
            size: 28,
            iconSize: 14,
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 64,
            child: Text(
              maintenanceLabel(context, label),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TweenAnimationBuilder<double>(
              tween: Tween(
                begin: (value ?? 0).clamp(0, 1),
                end: (value ?? 0).clamp(0, 1),
              ),
              duration: motion.entranceDuration,
              curve: motion.curve.curve,
              builder: (_, progress, _) => LinearProgressIndicator(
                value: progress.clamp(0, 1),
                minHeight: 6,
                color: color,
                backgroundColor: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(kOpenHandRadius4),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 44,
            child: _MaintenanceValue(
              value: value == null ? '—' : '${(value! * 100).round()}%',
              alignment: Alignment.centerRight,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 以业务身份匹配卡片；连续间隔取最大值并入后续卡片，避免条件卡片隐藏后留白叠加。
List<Widget> _maintenanceMotionChildren(
  List<Widget> children, {
  double spacing = 0,
  bool mergeSpacing = true,
}) {
  Key identity(Widget child) {
    if (child.key != null) return child.key!;
    if (child is _MaintenanceCard) return ValueKey(('card', child.title));
    if (child is _MaintenanceSection) return ValueKey(('section', child.title));
    if (child is Padding && child.child != null) return identity(child.child!);
    return ValueKey(child.runtimeType);
  }

  final result = <Widget>[];
  final occurrences = <Key, int>{};
  var gap = 0.0;
  for (final child in children) {
    if (mergeSpacing &&
        child is SizedBox &&
        child.child == null &&
        child.height != null) {
      gap = math.max(gap, child.height!);
      continue;
    }
    final key = identity(child);
    final occurrence = occurrences.update(
      key,
      (count) => count + 1,
      ifAbsent: () => 0,
    );
    result.add(
      Padding(
        key: ValueKey((key, occurrence)),
        padding: EdgeInsets.only(top: gap + (result.isEmpty ? 0 : spacing)),
        child: child,
      ),
    );
    gap = 0;
  }
  if (gap > 0 && result.isNotEmpty) {
    final last = result.removeLast() as Padding;
    result.add(
      Padding(
        key: last.key,
        padding: last.padding.add(EdgeInsets.only(bottom: gap)),
        child: last.child,
      ),
    );
  }
  return result;
}

/// 尺寸曲线限制在有效布局范围，弹性视觉仍由进退场组件负责。
class _MaintenanceAnimatedSize extends StatelessWidget {
  const _MaintenanceAnimatedSize({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    context.watch<SettingsController?>();
    final motion = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) => OpenHandAnimatedChipWrap(
          settings: motion,
          spacing: 0,
          runSpacing: 0,
          children: [
            SizedBox(
              key: const ValueKey('content'),
              width: constraints.hasBoundedWidth ? constraints.maxWidth : null,
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

/// 滚动板块复用有界退场生命周期，屏幕外的卡片也会按时释放。
class _MaintenanceAnimatedList extends StatelessWidget {
  const _MaintenanceAnimatedList({
    required this.children,
    this.padding = EdgeInsets.zero,
    this.shrinkWrap = false,
    this.spacing = 0,
    this.empty,
  });
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final bool shrinkWrap;
  final double spacing;
  final Widget? empty;

  @override
  Widget build(BuildContext context) {
    context.watch<SettingsController?>();
    final motion = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
    return CustomScrollView(
      shrinkWrap: shrinkWrap,
      slivers: [
        SliverPadding(
          padding: padding,
          sliver: OpenHandAnimatedSliverList(
            settings: motion,
            children: _maintenanceMotionChildren(children, spacing: spacing),
          ),
        ),
        if (children.isEmpty && empty != null)
          SliverFillRemaining(
            hasScrollBody: false,
            child: AnimatedAppearance(
              settings: motion,
              collapseSize: false,
              child: Center(
                child: Padding(padding: const EdgeInsets.all(24), child: empty),
              ),
            ),
          ),
      ],
    );
  }
}

/// 非滚动子板块复用网格的显隐和位移动效，不叠加入场动画。
class _MaintenanceAnimatedColumn extends StatelessWidget {
  const _MaintenanceAnimatedColumn({required this.children, this.spacing = 0});
  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    context.watch<SettingsController?>();
    final motion = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
    return LayoutBuilder(
      builder: (context, constraints) => OpenHandAnimatedChipWrap(
        settings: motion,
        followAnimatedChildHeight: true,
        spacing: 0,
        runSpacing: 0,
        children: [
          for (final child in _maintenanceMotionChildren(
            children,
            spacing: spacing,
          ))
            SizedBox(key: child.key, width: constraints.maxWidth, child: child),
        ],
      ),
    );
  }
}

class _MaintenanceGrid extends StatelessWidget {
  const _MaintenanceGrid({
    super.key,
    required this.children,
    this.minWidth = 360,
    this.maxColumns = 3,
    this.balanceColumns = false,
  });
  final List<Widget> children;
  final double minWidth;
  final int maxColumns;
  final bool balanceColumns;
  @override
  Widget build(BuildContext context) {
    context.watch<SettingsController?>();
    final motion = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
    return LayoutBuilder(
      builder: (_, constraints) {
        final keyed = _maintenanceMotionChildren(children, mergeSpacing: false);
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final capacity =
            ((constraints.maxWidth + _maintenanceGridGap) /
                    (minWidth * scale + _maintenanceGridGap))
                .floor()
                .clamp(1, math.max(1, math.min(maxColumns, children.length)))
                .toInt();
        final columns = balanceColumns && children.isNotEmpty
            ? (children.length / (children.length / capacity).ceil()).ceil()
            : capacity;
        final tiles = <Widget>[];
        for (var start = 0; start < children.length; start += columns) {
          // 末行按实际卡片数分配宽度，不留下整列空位。
          final count = math.min(columns, children.length - start);
          final width =
              (constraints.maxWidth - (count - 1) * _maintenanceGridGap) /
              count;
          final widths = List<double>.filled(count, width);
          final flexible = <int>[];
          var spare = 0.0;
          for (var i = 0; i < count; i++) {
            final child = children[start + i];
            final preferred = child is _MaintenanceCard
                ? child.preferredWidth(context)
                : double.infinity;
            if (preferred.isFinite) {
              widths[i] = math.min(width, preferred);
              spare += width - widths[i];
            } else {
              flexible.add(i);
            }
          }
          // 紧凑卡释放的宽度交给同行内容卡，避免外框变窄但仍占着整列。
          for (final i in flexible) {
            widths[i] += spare / flexible.length;
          }
          for (var i = 0; i < count; i++) {
            tiles.add(
              AnimatedContainer(
                key: keyed[start + i].key,
                duration: motion.entranceDuration,
                curve: OpenHandBoundedCurve(motion.curve.curve),
                width: widths[i],
                child: keyed[start + i],
              ),
            );
          }
        }
        return OpenHandAnimatedChipWrap(
          settings: motion,
          equalRunHeights: true,
          followAnimatedChildHeight: true,
          spacing: _maintenanceGridGap,
          runSpacing: _maintenanceGridGap,
          children: tiles,
        );
      },
    );
  }
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        const chrome = 1.0 + 10.0 + 16.0 + 6.0 + 10.0 + 1.0;
        final leading = icon == null ? 0.0 : 22.0;
        final textMax = constraints.maxWidth.isFinite
            ? math.max(0.0, constraints.maxWidth - chrome - leading)
            : double.infinity;
        return PopupMenuTheme(
          data: PopupMenuTheme.of(context).copyWith(
            color: cs.surfaceContainerLowest,
            elevation: 0,
            shadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            menuPadding: const EdgeInsets.all(4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: cs.outlineVariant.withValues(alpha: .65)),
            ),
          ),
          child: AnimatedPopupMenuButton<T>(
            tooltip: maintenanceLabel(context, tooltip),
            enabled: enabled,
            initialValue: value,
            position: PopupMenuPosition.under,
            padding: EdgeInsets.zero,
            offset: const Offset(0, 4),
            onSelected: onSelected,
            itemBuilder: (_) => [
              for (final item in items.entries)
                PopupMenuItem(
                  value: item.key,
                  height: math.max(
                    _maintenanceControlHeight,
                    MediaQuery.textScalerOf(context).scale(12) * 1.4 + 12,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  child: Semantics(
                    selected: item.key == value,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            maintenanceLabel(context, item.value),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: item.key == value
                                  ? cs.primary
                                  : cs.onSurface,
                              fontWeight: item.key == value
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: item.key == value
                              ? cs.primary
                              : Colors.transparent,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            child: AnimatedOpacity(
              opacity: enabled ? 1 : .42,
              duration: openHandMotionDuration(context, kOpenHandMotion140),
              child: Container(
                height: _maintenanceControlHeight,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: cs.surface.withValues(alpha: .72),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: .55),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 16, color: cs.onSurfaceVariant),
                      const SizedBox(width: 6),
                    ],
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: textMax),
                      child: Text(
                        maintenanceLabel(context, label),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: enabled ? cs.onSurface : cs.onSurfaceVariant,
                        ),
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
            ),
          ),
        );
      },
    );
  }
}

class _MaintenanceNotice extends StatefulWidget {
  const _MaintenanceNotice({required this.message, this.error = false});
  final String message;
  final bool error;
  @override
  State<_MaintenanceNotice> createState() => _MaintenanceNoticeState();
}

class _MaintenanceNoticeState extends State<_MaintenanceNotice> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = widget.error ? cs.error : cs.tertiary;
    return Align(
      widthFactor: 1,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maintenanceNoticeMaxWidth),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .07),
            border: Border.all(color: color.withValues(alpha: .18)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MaintenanceIconBadge(
                icon: widget.error ? Icons.error_outline : Icons.info_outline,
                color: color,
                size: 28,
                iconSize: 15,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: (MediaQuery.sizeOf(context).height * .25).clamp(
                      96.0,
                      240.0,
                    ),
                  ),
                  child: Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      padding: const EdgeInsets.only(right: 10),
                      child: _MaintenanceValue(
                        value: widget.message,
                        maxLines: null,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: color),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MaintenanceHealthContent extends StatelessWidget {
  const _MaintenanceHealthContent({required this.report, required this.raw});
  final MachineHealthReport report;
  final String raw;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final issue = switch (report.issue) {
      'unsynchronized' => l.maintenanceHealthUnsynchronized,
      'partial' => l.maintenanceHealthPartial,
      'unsupported' => l.maintenanceHealthUnsupported,
      'empty' => maintenanceLabel(context, '暂无数据'),
      'pending' => maintenanceHealthLabel(context, 'pending'),
      'permission' ||
      'missing' ||
      'hostkeys' ||
      'format' => maintenanceHealthLabel(context, report.issue!),
      null => '',
      _ => l.maintenanceHealthUnavailable,
    };
    final fields = <List<String>>[];
    final notes = <List<String>>[];
    for (final row in report.data.rows) {
      if (report.data.fields && const {'实时同步状态', '测量说明'}.contains(row[0])) {
        notes.add(row);
      } else {
        fields.add(row);
      }
    }
    final hasData = fields.isNotEmpty || report.tables.isNotEmpty;
    final tone = const {'partial', 'pending', 'empty'}.contains(report.issue)
        ? OpenHandStatusColors.warning
        : Theme.of(context).colorScheme.error;
    return _MaintenanceAnimatedColumn(
      spacing: _maintenanceGridGap,
      children: [
        if (issue.isNotEmpty && hasData)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: tone.withValues(alpha: .07),
              borderRadius: kOpenHandBorderRadius10,
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: tone),
                const SizedBox(width: 8),
                Expanded(
                  child: _MaintenanceValue(
                    value: issue,
                    maxLines: null,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          )
        else if (issue.isNotEmpty)
          _MaintenanceEmptyHint(message: issue)
        else if (report.data.rows.isEmpty && report.tables.isEmpty)
          _MaintenanceEmptyHint(message: maintenanceLabel(context, '暂无可用数据')),
        if (fields.isNotEmpty && report.data.fields)
          _MaintenanceFields(
            rows: [
              for (final row in fields)
                [
                  maintenanceHealthLabel(context, row[0]),
                  maintenanceHealthValue(context, row[1], field: row[0]),
                ],
            ],
          ),
        if (report.data.rows.isNotEmpty && !report.data.fields)
          _MaintenanceTable(
            maxBodyHeight: 300,
            paginate: report.data.rows.length > 20,
            headers: report.data.headers
                .map((s) => maintenanceHealthLabel(context, s))
                .toList(),
            rows: [
              for (var i = 0; i < report.data.rows.length; i++)
                OpenHandOperationalRankRow(
                  rowKey: i,
                  value: 0,
                  cells: [
                    for (var c = 0; c < report.data.headers.length; c++)
                      c < report.data.rows[i].length
                          ? maintenanceHealthValue(
                              context,
                              report.data.rows[i][c],
                              field: report.data.headers[c],
                            )
                          : '—',
                  ],
                ),
            ],
          ),
        for (final entry in report.tables.entries)
          Column(
            key: ValueKey(entry.key),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              Row(
                children: [
                  _MaintenanceIconBadge(
                    icon: Icons.table_rows_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 28,
                    iconSize: 14,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      RegExp(r'[^\x00-\x7F]').hasMatch(entry.key)
                          ? entry.key
                          : maintenanceHealthLabel(context, entry.key),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              _MaintenanceTable(
                maxBodyHeight: 300,
                paginate: entry.value.rows.length > 20,
                headers: [
                  for (final header in entry.value.headers)
                    maintenanceHealthLabel(context, header),
                ],
                rows: [
                  for (var i = 0; i < entry.value.rows.length; i++)
                    OpenHandOperationalRankRow(
                      rowKey: i,
                      value: 0,
                      cells: [
                        for (var c = 0; c < entry.value.rows[i].length; c++)
                          maintenanceHealthValue(
                            context,
                            entry.value.rows[i][c],
                            field: entry.value.headers[c],
                          ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        if (notes.isNotEmpty ||
            (raw.isNotEmpty && (report.issue != null || report.unparsed > 0)))
          _MaintenanceSection(
            title: maintenanceHealthLabel(context, 'diagnostic'),
            icon: Icons.fact_check_outlined,
            child: _MaintenanceAnimatedColumn(
              spacing: _maintenanceGridGap,
              children: [
                for (final note in notes)
                  Column(
                    key: ValueKey(note[0]),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 4,
                    children: [
                      Text(
                        maintenanceHealthLabel(context, note[0]),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      _MaintenanceValue(
                        value: maintenanceHealthValue(context, note[1]),
                        maxLines: null,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                if (raw.isNotEmpty &&
                    (notes.isEmpty ||
                        report.unparsed > 0 ||
                        raw.contains('@@OH_RESULT:')))
                  _MaintenanceFields(
                    rows: machineMaintenanceDiagnosticFields(raw),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MaintenanceFields extends StatelessWidget {
  const _MaintenanceFields({required this.rows, this.fieldKeys});
  final List<List<String>> rows;
  final List<String>? fieldKeys;

  @override
  Widget build(BuildContext context) {
    context.watch<SettingsController?>();
    final motion = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    final scale = scaler.scale(14) / 14;
    final style = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 14,
      height: 1.35,
      fontWeight: FontWeight.w600,
      color: cs.onSurface,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final capacity =
            ((constraints.maxWidth + _maintenanceGridGap) /
                    (_maintenanceFieldMinWidth * scale + _maintenanceGridGap))
                .floor()
                .clamp(1, _maintenanceFieldMaxColumns);
        // 保持最少行数，再均衡列数，避免少量字段占空列或末行孤立。
        final rowCount = math.max(1, (rows.length / capacity).ceil());
        final columns = math.max(1, (rows.length / rowCount).ceil());
        final width =
            (constraints.maxWidth - (columns - 1) * _maintenanceGridGap) /
            columns;
        final occurrences = <String, int>{};
        final keys = [
          for (var i = 0; i < rows.length; i++)
            ValueKey((
              fieldKeys?[i] ?? rows[i][0],
              occurrences.update(
                fieldKeys?[i] ?? rows[i][0],
                (count) => count + 1,
                ifAbsent: () => 0,
              ),
            )),
        ];
        return OpenHandAnimatedChipWrap(
          settings: motion,
          spacing: _maintenanceGridGap,
          runSpacing: _maintenanceGridGap,
          children: [
            for (var i = 0; i < rows.length; i++)
              OpenHandOperationalLiveContent(
                key: keys[i],
                preserveState: true,
                value: (
                  rows[i].join("\u0000"),
                  fieldKeys?[i],
                  width,
                  scale,
                  style,
                  motion,
                ),
                builder: () {
                  final label = rows[i][0];
                  final raw = rows[i][1].isEmpty ? '—' : rows[i][1];
                  final field = fieldKeys?[i] ?? label;
                  final duration = machineMaintenanceReadableDuration(
                    raw,
                    field: field,
                  );
                  final painter = TextPainter(
                    text: TextSpan(text: raw, style: style),
                    textDirection: Directionality.of(context),
                    textScaler: scaler,
                    maxLines: 2,
                  )..layout(maxWidth: math.max(0, width - 24));
                  final truncated = painter.didExceedMaxLines;
                  painter.dispose();
                  void openValue() {
                    showAnimatedDialog<void>(
                      context: context,
                      builder: (context) => buildOpenHandDialog(
                        maxHeight: MediaQuery.sizeOf(context).height * .7,
                        child: SizedBox(
                          width: math.min(
                            MediaQuery.sizeOf(context).width * .86,
                            kOpenHandDialogDefaultMaxWidth,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _MachineTerminalDialogHeader(
                                icon: _maintenanceFieldIcon(label),
                                title: label,
                                onClose: () => Navigator.of(context).pop(),
                                trailingActions: [
                                  _MachineTerminalIconButton(
                                    tooltip: AppLocalizations.of(
                                      context,
                                    )!.commonCopy,
                                    icon: Icons.copy_rounded,
                                    onPressed: () =>
                                        copyOpenHandTextToClipboard(
                                          context: context,
                                          text: raw,
                                          logTag: 'home_machine_maintenance',
                                          logAction: '复制运维字段',
                                          showSuccess: false,
                                        ),
                                  ),
                                ],
                              ),
                              Flexible(
                                child: SingleChildScrollView(
                                  padding: _maintenanceDetailPadding,
                                  child: SelectableText(raw, style: style),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  return AnimatedContainer(
                    key: ValueKey('maintenance-field-$field'),
                    duration: motion.entranceDuration,
                    curve: OpenHandBoundedCurve(motion.curve.curve),
                    width: width,
                    height: _maintenanceFieldHeight * scale,
                    child: DecoratedBox(
                      decoration: _maintenanceTileDecoration(cs),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                _MaintenanceIconBadge(
                                  icon: _maintenanceFieldIcon(label),
                                  color: cs.primary,
                                  size: 24,
                                  iconSize: 14,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Tooltip(
                                    message: label,
                                    child: Text(
                                      label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                ),
                                if (truncated)
                                  SizedBox.square(
                                    dimension: 28,
                                    child: IconButton(
                                      tooltip: maintenanceLabel(
                                        context,
                                        '查看详情',
                                      ),
                                      padding: EdgeInsets.zero,
                                      style: IconButton.styleFrom(
                                        shape: const CircleBorder(),
                                        visualDensity: VisualDensity.standard,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      iconSize: 16,
                                      onPressed: openValue,
                                      icon: const Icon(
                                        Icons.open_in_full_rounded,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: Align(
                                alignment: AlignmentDirectional.topStart,
                                child: duration != null
                                    ? _MaintenanceNumber(
                                        key: ValueKey(field),
                                        raw: raw,
                                        field: field,
                                        maxLines: 2,
                                        style: style,
                                      )
                                    : truncated
                                    ? Tooltip(
                                        message: maintenanceLabel(
                                          context,
                                          '查看详情',
                                        ),
                                        child: InkWell(
                                          onTap: openValue,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          child: _MaintenanceValue(
                                            value: raw,
                                            maxLines: 2,
                                            style: style,
                                          ),
                                        ),
                                      )
                                    : _MaintenanceValue(
                                        value: raw,
                                        selectable: true,
                                        maxLines: 2,
                                        style: style,
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

/// 诊断、元数据与高级指标共用的折叠面板，动效遵循弹窗设置。
class _MaintenanceSection extends StatelessWidget {
  const _MaintenanceSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.icon = Icons.data_object_outlined,
    this.initiallyExpanded = false,
    this.accent,
  });
  final String title;
  final String? subtitle;
  final Widget child;
  final IconData icon;
  final bool initiallyExpanded;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    context.watch<SettingsController?>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tone = accent ?? cs.primary;
    final motion = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
    return Material(
      color: cs.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_maintenanceCardRadius),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: .65)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTileTheme.merge(
        shape: const RoundedRectangleBorder(),
        minVerticalPadding: 4,
        minLeadingWidth: 32,
        horizontalTitleGap: 10,
        child: ExpansionTile(
          // 稳定组件身份，避免折叠状态与内部滚动位置共用存储键。
          key: ValueKey(('expansion', key ?? title)),
          initiallyExpanded: initiallyExpanded,
          shape: const Border(),
          collapsedShape: const Border(),
          minTileHeight:
              _maintenanceSectionHeaderHeight *
              MediaQuery.textScalerOf(context).scale(13) /
              13,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          leading: _MaintenanceIconBadge(
            icon: icon,
            color: tone,
            size: 32,
            iconSize: 16,
          ),
          title: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Tooltip(
                message: maintenanceDetailLabel(context, title),
                child: Text(
                  maintenanceDetailLabel(context, title),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  maintenanceLabel(context, subtitle!),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          iconColor: tone,
          collapsedIconColor: cs.onSurfaceVariant,
          expansionAnimationStyle: AnimationStyle(
            duration: motion.disablesAnimation
                ? Duration.zero
                : motion.entranceDuration,
            reverseDuration: motion.disablesAnimation
                ? Duration.zero
                : motion.exitDuration,
            curve: OpenHandBoundedCurve(motion.curve.curve),
            reverseCurve: OpenHandBoundedCurve(motion.curve.reverseCurve),
          ),
          children: [
            const SizedBox(height: 8),
            _MaintenanceAnimatedSize(child: child),
          ],
        ),
      ),
    );
  }
}

class _MaintenanceReadout extends StatefulWidget {
  const _MaintenanceReadout({
    this.text = '',
    this.section = '',
    this.report,
    this.logMaxHeight = _maintenanceLogPreviewMaxHeight,
  });
  final MachineMaintenanceReadout? report;
  final String text;
  final String section;
  final double logMaxHeight;
  @override
  State<_MaintenanceReadout> createState() => _MaintenanceReadoutState();
}

class _MaintenanceReadoutState extends State<_MaintenanceReadout> {
  late MachineMaintenanceReadout _data;
  @override
  void initState() {
    super.initState();
    _data =
        widget.report ??
        MachineMaintenanceReadout.parse(widget.text, widget.section);
  }

  @override
  void didUpdateWidget(covariant _MaintenanceReadout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.section != widget.section ||
        oldWidget.report != widget.report) {
      _data =
          widget.report ??
          MachineMaintenanceReadout.parse(widget.text, widget.section);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_data.groups.isNotEmpty) {
      return _MaintenanceAnimatedColumn(
        spacing: _maintenanceGridGap,
        children: [
          if (_data.rows.isNotEmpty)
            _MaintenanceReadout(
              report: MachineMaintenanceReadout(
                _data.headers,
                _data.rows,
                fields: _data.fields,
              ),
            ),
          for (final entry in _data.groups.entries)
            _MaintenanceSection(
              key: ValueKey(entry.key),
              title:
                  widget.section == 'network_stats' ||
                      widget.section == 'firewall_states'
                  ? maintenanceNetworkGroupLabel(
                      context,
                      entry.key,
                      _data.groups.keys.toList().indexOf(entry.key) + 1,
                    )
                  : entry.key,
              icon: Icons.hub_outlined,
              initiallyExpanded:
                  _data.groups.length <= 4 && entry.value.rows.length <= 12,
              child: _MaintenanceReadout(
                report: entry.value,
                section: widget.section,
              ),
            ),
        ],
      );
    }
    if (_data.issue != null || _data.raw) {
      final issue = _data.issue ?? 'format';
      final cs = Theme.of(context).colorScheme;
      final title = switch (issue) {
        'permission' => '当前账户无权读取',
        'timeout' => '采集响应超时',
        'connection' =>
          widget.section == 'containers' ? '容器服务暂不可用' : '暂时无法连接服务',
        'missing' => '缺少采集所需工具',
        'format' => '采集格式暂未识别',
        _ => '当前数据暂不可用',
      };
      final message = switch (issue) {
        'permission' => '请检查当前账户的访问权限后重试。',
        'timeout' => '请检查目标服务的运行状态和连接，稍后重新采集。',
        'connection' =>
          widget.section == 'containers'
              ? '请确认所选容器运行时已启动，并检查连接上下文与端点。'
              : '请确认目标服务已启动，并检查连接地址。',
        'missing' => '请确认目标机器已安装对应工具，且命令可在当前终端使用。',
        'format' => '当前工具输出格式尚未识别，请检查工具版本和采集范围后重试。',
        _ => '请检查目标服务、权限和工具状态后重新采集。',
      };
      return _MaintenanceAnimatedColumn(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: .055),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MaintenanceIconBadge(
                  icon: issue == 'permission'
                      ? Icons.lock_outline_rounded
                      : Icons.info_outline_rounded,
                  color: OpenHandStatusColors.warning,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        maintenanceLabel(context, title),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        maintenanceLabel(context, message),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (widget.text.isNotEmpty || _data.rows.isNotEmpty) ...[
            const SizedBox(height: 8),
            _MaintenanceFields(
              rows: [
                for (final row
                    in _data.rows.isNotEmpty
                        ? _data.rows
                        : machineMaintenanceDiagnosticFields(widget.text))
                  [
                    maintenanceDetailLabel(context, row[0]),
                    maintenanceDetailValue(context, row[1]),
                  ],
              ],
            ),
          ],
        ],
      );
    }
    if (_data.rows.isEmpty) {
      return _MaintenanceEmptyHint(
        message: maintenanceLabel(context, '暂无可用数据'),
      );
    }
    if (widget.section == 'logs') {
      return _MaintenanceLogTimeline(
        rows: _data.rows,
        maxHeight: widget.logMaxHeight,
      );
    }
    if (_data.fields &&
        (widget.section == 'network_stats' ||
            widget.section == 'firewall_states')) {
      final l = AppLocalizations.of(context)!;
      final rows = <OpenHandOperationalRankRow>[];
      for (var i = 0; i < _data.rows.length; i++) {
        final field = _data.rows[i][0];
        final known = maintenanceDetailLabel(context, field);
        final label =
            maintenanceNetworkCounterLabel(context, field) ??
            (known != field || !RegExp('[A-Za-z]').hasMatch(field)
                ? known
                : l.maintenanceReadoutUnknownMetric('${i + 1}'));
        rows.add(
          OpenHandOperationalRankRow(
            rowKey: (field, i),
            value: 0,
            cells: [label, maintenanceDetailValue(context, _data.rows[i][1])],
            cellWidgets: [
              Tooltip(
                message: l.maintenanceReadoutRawMetric(field),
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              null,
            ],
          ),
        );
      }
      return _MaintenanceTable(
        headers: _data.headers,
        rows: rows,
        maxBodyHeight: 420,
        paginate: rows.length > 20,
      );
    }

    if (_data.fields) {
      return _MaintenanceFields(
        fieldKeys: [for (final row in _data.rows) row[0]],
        rows: [
          for (final row in _data.rows)
            [
              maintenanceDetailLabel(context, row[0]),
              _maintenanceReadoutValue(context, row[0], row[1]),
            ],
        ],
      );
    }
    if (widget.section == 'descriptors') {
      final headers = _data.headers;
      int at(List<String> names) => headers.indexWhere(names.contains);
      final columns = [
        at(['NAME', '路径', '目标']),
        at(['FD']),
        at(const ['TYPE', '类型']),
        at(const ['USER', '用户']),
      ].where((index) => index >= 0).toList();
      if (columns.isNotEmpty) {
        return _MaintenanceTable(
          headers: [
            for (final index in columns)
              maintenanceDetailLabel(context, headers[index]),
          ],
          paginate: _data.rows.length > 20,
          maxBodyHeight: 420,
          rows: [
            for (var i = 0; i < _data.rows.length; i++)
              OpenHandOperationalRankRow(
                rowKey: i,
                value: 0,
                cells: [
                  for (final index in columns)
                    index < _data.rows[i].length
                        ? _maintenanceReadoutValue(
                            context,
                            headers[index],
                            _data.rows[i][index],
                          )
                        : '—',
                ],
              ),
          ],
        );
      }
    }
    final table = _MaintenanceTable(
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
                const [
                          '状态',
                          'STAT',
                          'STATUS',
                          'STATE',
                          'PRESET',
                          'TYPE',
                          'State',
                          '启动方式',
                          '预设',
                          '类型',
                        ].contains(_data.headers[c]) ||
                        machineMaintenanceIsTimestampField(_data.headers[c])
                    ? _maintenanceReadoutValue(
                        context,
                        _data.headers[c],
                        _data.rows[i][c],
                      )
                    : _data.rows[i][c],
            ],
          ),
      ],
      paginate: _data.rows.length > 20,
      maxBodyHeight: 480,
    );
    return table;
  }
}

class _MaintenanceEmptyHint extends StatelessWidget {
  const _MaintenanceEmptyHint({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
  });
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) =>
      OpenHandOperationalEmptyState(message: message, icon: icon);
}

class _MaintenanceIconBadge extends StatelessWidget {
  const _MaintenanceIconBadge({
    required this.icon,
    required this.color,
    this.size = 36,
    this.iconSize = 18,
  });
  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(kOpenHandRadius10),
      ),
      child: Icon(icon, size: iconSize, color: color),
    );
  }
}

class _MaintenanceCard extends StatelessWidget {
  const _MaintenanceCard({
    super.key,
    required this.title,
    required this.child,
    this.icon = Icons.analytics_outlined,
    this.onOpen,
    this.maxHeight = 280,
    this.scrollBody = true,
    this.contentPadding = const EdgeInsets.all(14),
    this.trailing,
    this.wrapHeader = false,
    this.accent,
    this.fillWidth = false,
  });
  final String title;
  final Widget child;
  final IconData icon;
  final VoidCallback? onOpen;
  final double maxHeight;
  final bool scrollBody;
  final EdgeInsetsGeometry contentPadding;
  final Widget? trailing;
  final bool wrapHeader;
  final Color? accent;
  final bool fillWidth;

  double preferredWidth(BuildContext context) {
    if (fillWidth || child is! _MaintenanceVisual) return double.infinity;
    final visual = child as _MaintenanceVisual;
    if (!visual.donut) return double.infinity;
    if (trailing != null) return _maintenanceDistributionMaxWidth;
    final theme = Theme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    double measure(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final base = DefaultTextStyle.of(context).style;
    final total = visual.segments.fold<double>(
      0,
      (sum, item) => sum + item.safeValue,
    );
    var legendWidth = _maintenanceDonutLegendMinWidth * scaler.scale(12) / 12;
    for (final item in visual.segments) {
      final labelWidth = measure(item.label, base.copyWith(fontSize: 12));
      final valueWidth = measure(
        item.valueLabel ?? '${item.value}',
        base.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
      );
      final shareWidth = measure(
        total > 0
            ? '${(item.safeValue / total * 100).toStringAsFixed(1)}%'
            : '—',
        base.copyWith(fontSize: 11),
      );
      legendWidth = math.max(
        legendWidth,
        15 + math.max(labelWidth, valueWidth + 8 + shareWidth),
      );
    }
    final headerWidth =
        66 +
        (onOpen == null ? 0 : 24) +
        measure(
          maintenanceLabel(context, title),
          (theme.textTheme.titleSmall ?? base).copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        );
    final bodyWidth =
        _maintenanceDonutSize +
        _maintenanceDonutGap +
        legendWidth +
        contentPadding.resolve(direction).horizontal +
        2;
    return math.min(
      _maintenanceDistributionMaxWidth,
      math.max(headerWidth, bodyWidth),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tone = accent ?? cs.primary;
    final heading = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MaintenanceIconBadge(icon: icon, color: tone, size: 32, iconSize: 16),
        const SizedBox(width: 10),
        Flexible(
          child: _MaintenanceValue(
            value: maintenanceLabel(context, title),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
    final card = Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(_maintenanceCardRadius),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_maintenanceCardRadius),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .65)),
      ),
      // 等高网格或尺寸过渡压缩卡片时，保留自然布局并允许访问全部内容。
      child: SingleChildScrollView(
        primary: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
              child: Row(
                children: [
                  Expanded(
                    child: wrapHeader
                        ? OverflowBar(
                            alignment: MainAxisAlignment.spaceBetween,
                            overflowAlignment: OverflowBarAlignment.end,
                            spacing: 12,
                            overflowSpacing: 10,
                            children: [
                              heading,
                              if (trailing != null) trailing!,
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(child: heading),
                              if (trailing != null) ...[
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    heightFactor: 1,
                                    child: trailing,
                                  ),
                                ),
                              ],
                            ],
                          ),
                  ),
                  if (onOpen != null)
                    Tooltip(
                      message: maintenanceLabel(context, '查看详情'),
                      child: InkWell(
                        onTap: onOpen,
                        hoverColor: Colors.transparent,
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                        overlayColor: _maintenanceNoOverlay,
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
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: .45)),
            Padding(
              padding: contentPadding,
              // 列表自行约束数据区，外层不能再次截断分页栏。
              child: _MaintenanceAnimatedSize(
                child:
                    !scrollBody ||
                        child is _MaintenanceTable ||
                        child is _MaintenanceBrowser ||
                        child is _MaintenanceReadout ||
                        child is _MaintenanceLogTimeline
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
            ),
          ],
        ),
      ),
    );
    final width = preferredWidth(context);
    return width.isFinite
        ? Align(
            alignment: AlignmentDirectional.topStart,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: width),
              child: card,
            ),
          )
        : card;
  }
}

const _maintenanceChartLimit = 6;

// ignore: unused_element
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
    if (segments.isEmpty) {
      return _MaintenanceEmptyHint(
        message: maintenanceLabel(context, '暂无可用数据'),
      );
    }
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
                key: ValueKey(segment.label),
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
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: segment.color,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Tooltip(
                                  message: segment.label,
                                  child: Text(
                                    segment.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: donut ? cs.onSurfaceVariant : null,
                                    ),
                                  ),
                                ),
                                if (donut) ...[
                                  const SizedBox(height: 3),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 3,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      _MaintenanceValue(
                                        value:
                                            segment.valueLabel ??
                                            '${segment.value}',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      _MaintenanceValue(
                                        value: total > 0
                                            ? '${(segment.safeValue / total * 100).toStringAsFixed(1)}%'
                                            : '—',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: segment.color,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (!donut) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              fit: FlexFit.tight,
                              child: _MaintenanceValue(
                                value: segment.valueLabel ?? '${segment.value}',
                                alignment: Alignment.centerRight,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: segment.color,
                                ),
                              ),
                            ),
                          ],
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
                      ],
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
            width: _maintenanceDonutSize,
            height: _maintenanceDonutSize,
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
          builder: (_, constraints) =>
              constraints.maxWidth <
                  _maintenanceDonutSize +
                      _maintenanceDonutGap +
                      _maintenanceDonutLegendMinWidth *
                          (MediaQuery.textScalerOf(context).scale(12) / 12)
              ? Column(
                  children: [
                    chart,
                    const SizedBox(height: _maintenanceDonutGap),
                    legend,
                  ],
                )
              : Row(
                  children: [
                    chart,
                    const SizedBox(width: _maintenanceDonutGap),
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: .28)),
          ),
          child: Row(
            children: [
              _MaintenanceIconBadge(
                icon: color == cs.primary
                    ? Icons.lan_outlined
                    : Icons.public_rounded,
                color: color,
                size: 24,
                iconSize: 13,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _MaintenanceValue(
                  value: label,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return _MaintenanceAnimatedColumn(
      spacing: 8,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                maintenanceLabel(context, '本地地址'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: Text(
                maintenanceLabel(context, '远端地址'),
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        if (visible.isEmpty)
          _MaintenanceEmptyHint(
            icon: Icons.account_tree_outlined,
            message: maintenanceLabel(context, '暂无可用数据'),
          ),
        for (final entry in visible.take(_maintenanceChartLimit))
          Padding(
            key: ValueKey(entry.key),
            padding: EdgeInsets.zero,
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
                          color: cs.primary.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: _MaintenanceValue(
                            value: '${entry.value}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: cs.primary,
                            ),
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
  const _MaintenanceLogTimeline({
    required this.rows,
    this.maxHeight = _maintenanceLogPreviewMaxHeight,
  });
  final List<List<String>> rows;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final text = rows.isEmpty
        ? ''
        : rows
              .map((row) => row.first == '—' ? row.last : row.join('  '))
              .join('\n');
    if (text.isEmpty || _maintenanceLogUnreadable(text)) {
      return _MaintenanceEmptyHint(
        icon: Icons.article_outlined,
        message: text.isEmpty
            ? AppLocalizations.of(context)!.maintenanceLogEmpty
            : AppLocalizations.of(context)!.maintenanceLogUnavailable,
      );
    }
    return OpenHandConsoleText(
      title: maintenanceLabel(context, '最近日志'),
      text: text,
      maxHeight: maxHeight,
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    context.watch<SettingsController?>();
    final settings = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
    _curve = settings.curve.curve;
    _animation.duration = settings.entranceDuration;
    if (settings.disablesAnimation) _animation.value = 1;
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
    this.refreshInterval,
    this.initialAction,
  });
  final String? initialAction;
  final Duration? refreshInterval;
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
  bool _busy = false, _automatic = false, _logsOnly = false;
  Timer? _refreshTimer;

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    if (!_automatic || !mounted || widget.refreshInterval == null) return;
    _refreshTimer = startSafeTimer(widget.refreshInterval!, () {
      if (!mounted) return;
      if (!_busy &&
          (ModalRoute.of(context)?.isCurrent ?? true) &&
          (WidgetsBinding.instance.lifecycleState == null ||
              WidgetsBinding.instance.lifecycleState ==
                  AppLifecycleState.resumed)) {
        _load();
      } else {
        _scheduleRefresh();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      final action = widget.initialAction;
      if (mounted &&
          _error == null &&
          action != null &&
          widget.actions.containsKey(action)) {
        _act(MapEntry(action, widget.actions[action]!));
      }
    });
  }

  Future<void> _load() async {
    if (_busy || !mounted) return;
    _refreshTimer?.cancel();
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
          _automatic = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
        _scheduleRefresh();
      }
    }
  }

  Future<void> _act(MapEntry<String, String> action) async {
    _refreshTimer?.cancel();
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
    if (confirmed != true || !mounted) {
      _scheduleRefresh();
      return;
    }
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
        _scheduleRefresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final sections = _data == null
        ? const <Widget>[]
        : _sectionWidgets(
            _data!,
            _data!.sections.keys
                .where(
                  (key) =>
                      (!_logsOnly || key == 'logs') &&
                      !const [
                        'platform',
                        'host',
                        'boot',
                        'encoding',
                        'uptime',
                      ].contains(key),
                )
                .toList(),
          );
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
                  if (widget.refreshInterval != null)
                    _MachineTerminalIconButton(
                      icon: _logsOnly
                          ? Icons.analytics_outlined
                          : Icons.article_outlined,
                      tooltip: _logsOnly ? '查看服务详情' : '查看服务日志',
                      onPressed: () => setState(() => _logsOnly = !_logsOnly),
                    ),
                  if (widget.refreshInterval != null)
                    _MachineTerminalIconButton(
                      icon: _automatic
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      tooltip: _automatic
                          ? '暂停自动刷新服务与日志'
                          : '自动刷新服务与日志（${widget.refreshInterval!.inSeconds} 秒）',
                      onPressed: () {
                        setState(() => _automatic = !_automatic);
                        _scheduleRefresh();
                      },
                    ),
                  _MachineTerminalIconButton(
                    icon: Icons.refresh_rounded,
                    tooltip: widget.refreshInterval == null
                        ? maintenanceLabel(context, '刷新详情')
                        : '刷新服务与日志',
                    onPressed: _busy ? null : _load,
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 3,
              child: _busy ? const LinearProgressIndicator() : null,
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
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: _MaintenanceEmptyHint(
                          icon: _busy
                              ? Icons.downloading_rounded
                              : Icons.cloud_off_rounded,
                          message: maintenanceLabel(
                            context,
                            _busy ? '正在读取详情…' : '读取失败，请重试。',
                          ),
                        ),
                      ),
                    )
                  : _MaintenanceAnimatedList(
                      shrinkWrap: true,
                      padding: _maintenanceDetailPadding,
                      spacing: _maintenanceGridGap,
                      children: sections,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MaintenanceLogBrowser extends StatefulWidget {
  const _MaintenanceLogBrowser({
    required this.buffers,
    required this.data,
    this.busy = false,
  });
  final Map<String, MachineLogBuffer> buffers;
  final MachineMaintenanceSnapshot data;
  final bool busy;
  @override
  State<_MaintenanceLogBrowser> createState() => _MaintenanceLogBrowserState();
}

class _MaintenanceLogBrowserState extends State<_MaintenanceLogBrowser> {
  final _scroll = ScrollController();
  String _source = 'system', _query = '';
  int _level = -1;
  String _metadataKind = 'rotation';
  bool _follow = true;
  List<MachineLogEntry> _visible = [];
  bool _selecting = false;
  int _selectionRevision = 0;
  Object? _filter;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (_follow) {
        final motion = openHandMotionSettingsOf(
          context,
          OpenHandMotionSettingsScope.dialog,
        );
        final duration = motion.entranceDuration;
        if (duration == Duration.zero) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        } else {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: duration,
            curve: OpenHandBoundedCurve(motion.curve.curve),
          );
        }
      } else {
        _scroll.jumpTo(offset.clamp(0, _scroll.position.maxScrollExtent));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final buffer = widget.buffers[_source];
    final entries = buffer?.entries ?? const <MachineLogEntry>[];
    final filter = (_source, _query, _level);
    if (_filter != filter) _selecting = false;
    _filter = filter;
    // 选区存在时保留当前文本快照，避免后台追加改变复制范围。
    if (!_selecting) {
      _visible = entries
          .where(
            (e) =>
                (_level < 0 || e.level == _level) &&
                e.message.toLowerCase().contains(_query),
          )
          .toList();
    }
    final names = [
      l.maintenanceLogError,
      l.maintenanceLogWarning,
      l.maintenanceLogInfo,
    ];
    final platform = widget.data.sections['platform']?.trim();
    final metadata = {
      for (final kind in ['rotation', 'config', 'storage'])
        kind: MachineLogMetadata.parse(widget.data.text('log_$kind'), kind),
    };
    final groups = <String, Map<String, String>>{};
    for (final row in metadata['rotation']!) {
      (groups[row[0]] ??= {})[row[1]] = row[2];
    }
    final rotationFields = ['字节', '修改时间', '最近轮转']
        .where(
          (field) => groups.values.any((fields) => fields.containsKey(field)),
        )
        .toList();
    final canGroupRotation =
        groups.isNotEmpty &&
        groups.values.every(
          (fields) => fields.keys.every(rotationFields.contains),
        );
    final titles = {
      'rotation': l.maintenanceLogArchives,
      'config': l.maintenanceLogPolicy,
      'storage': l.maintenanceLogStorage,
    };
    final selectedRows = metadata[_metadataKind]!;
    return LayoutBuilder(
      builder: (context, bounds) => Padding(
        padding: const EdgeInsets.fromLTRB(
          12,
          8,
          12,
          _maintenancePanelBottomInset,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, toolbarBounds) {
                final controls = Wrap(
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
                            ? l.maintenanceLogSystem
                            : l.maintenanceLogSecurity,
                      },
                      onSelected: (value) => setState(() {
                        _source = value;
                        if (_scroll.hasClients) _scroll.jumpTo(0);
                      }),
                    ),
                    SizedBox(
                      width: _maintenanceSearchWidth,
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
                    SizedBox(
                      height: _maintenanceControlHeight,
                      child: FilterChip(
                        key: const ValueKey('maintenance-log-follow'),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.standard,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        labelPadding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        side: BorderSide(
                          color: (_follow ? cs.primary : cs.outlineVariant)
                              .withValues(alpha: .55),
                        ),
                        backgroundColor: cs.surface.withValues(alpha: .72),
                        selectedColor: cs.primaryContainer,
                        checkmarkColor: cs.onPrimaryContainer,
                        labelStyle: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(
                              color: _follow
                                  ? cs.onPrimaryContainer
                                  : cs.onSurface,
                            ),
                        elevation: 0,
                        pressElevation: 0,
                        shadowColor: Colors.transparent,
                        selectedShadowColor: Colors.transparent,
                        surfaceTintColor: Colors.transparent,
                        label: Text(l.maintenanceLogFollow),
                        selected: _follow,
                        onSelected: (value) => setState(() {
                          _follow = value;
                          if (value) {
                            _selecting = false;
                            _selectionRevision++;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted && _follow && _scroll.hasClients) {
                                _scroll.jumpTo(
                                  _scroll.position.maxScrollExtent,
                                );
                              }
                            });
                          }
                        }),
                      ),
                    ),
                    _MachineTerminalIconButton(
                      tooltip: l.maintenanceLogClear,
                      icon: Icons.cleaning_services_rounded,
                      onPressed: widget.busy || entries.isEmpty
                          ? null
                          : () => setState(() {
                              buffer!.clear();
                              _selecting = false;
                              _selectionRevision++;
                              _visible = [];
                              if (_scroll.hasClients) _scroll.jumpTo(0);
                            }),
                    ),
                  ],
                );
                final counters = Wrap(
                  key: const ValueKey('maintenance-log-counts'),
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < names.length; i++)
                      Container(
                        key: ValueKey('maintenance-log-count-$i'),
                        height: _maintenanceControlHeight,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: cs.surface.withValues(alpha: .72),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: cs.outlineVariant.withValues(alpha: .55),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              [
                                Icons.error_outline,
                                Icons.warning_amber_rounded,
                                Icons.info_outline,
                              ][i],
                              size: 16,
                              color: [cs.error, cs.tertiary, cs.primary][i],
                            ),
                            const SizedBox(width: 6),
                            _MaintenanceValue(
                              value:
                                  '${names[i]} ${entries.where((e) => e.level == i).length}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurface),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
                if (toolbarBounds.maxWidth >=
                    MediaQuery.textScalerOf(context).scale(900)) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: controls),
                      const SizedBox(width: 16),
                      counters,
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [controls, const SizedBox(height: 8), counters],
                );
              },
            ),
            const SizedBox(height: 8),
            if (buffer?.error != null && _visible.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  l.maintenanceLogUnavailable,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: OpenHandConsoleFrame(
                title:
                    '${l.maintenanceLogsTab} / ${switch (_source) {
                      'kernel' => platform == 'Windows' ? l.maintenanceLogApplication : l.maintenanceLogKernel,
                      'security' => platform == 'Darwin' ? l.maintenanceLogSystem : l.maintenanceLogSecurity,
                      _ => l.maintenanceLogSystem,
                    }} · ${_visible.length}',
                expandBody: true,
                child: _visible.isEmpty
                    ? OpenHandOperationalEmptyState(
                        textColor: OpenHandConsolePalette.text,
                        surfaceColor: OpenHandConsolePalette.deepSurface,
                        icon: buffer?.error != null
                            ? Icons.cloud_off_rounded
                            : Icons.article_outlined,
                        color: buffer?.error != null
                            ? OpenHandConsolePalette.warning
                            : OpenHandConsolePalette.notice,
                        message: buffer?.error != null
                            ? l.maintenanceLogUnavailable
                            : l.maintenanceLogEmpty,
                      )
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
                        child: OpenHandConsoleText(
                          key: ValueKey((filter, _selectionRevision)),
                          title: l.maintenanceLogsTab,
                          framed: false,
                          maxHeight: double.infinity,
                          scrollController: _scroll,
                          text: _visible
                              .map(
                                (entry) => entry.time.isEmpty
                                    ? entry.message
                                    : '${entry.time}  ${entry.message}',
                              )
                              .join('\n'),
                          onSelectionChanged: (selection, cause) {
                            final selecting = !selection.isCollapsed;
                            if (_selecting == selecting) return;
                            setState(() {
                              _selecting = selecting;
                              if (selecting) _follow = false;
                            });
                          },
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            _MaintenanceSection(
              title: l.maintenanceLogRotation,
              icon: Icons.inventory_2_outlined,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: math.min(300, bounds.maxHeight * .4),
                ),
                child: SingleChildScrollView(
                  primary: false,
                  padding: EdgeInsets.zero,
                  child: _MaintenanceAnimatedColumn(
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final kind in titles.keys)
                            ChoiceChip(
                              elevation: 0,
                              pressElevation: 0,
                              shadowColor: Colors.transparent,
                              selectedShadowColor: Colors.transparent,
                              surfaceTintColor: Colors.transparent,
                              visualDensity: VisualDensity.standard,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              side: BorderSide(
                                color:
                                    (_metadataKind == kind
                                            ? cs.primary
                                            : cs.outlineVariant)
                                        .withValues(alpha: .55),
                              ),
                              backgroundColor: cs.surface.withValues(
                                alpha: .72,
                              ),
                              selectedColor: cs.primaryContainer,
                              labelStyle: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: _metadataKind == kind
                                        ? cs.onPrimaryContainer
                                        : cs.onSurface,
                                  ),
                              label: Text(
                                '${titles[kind]} · ${kind == 'rotation' && canGroupRotation ? groups.length : metadata[kind]!.length}',
                              ),
                              selected: _metadataKind == kind,
                              onSelected: (_) =>
                                  setState(() => _metadataKind = kind),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (_metadataKind == 'config')
                        _MaintenanceReadout(
                          report: MachineMaintenanceReadout(
                            [],
                            [],
                            groups: {
                              for (final path
                                  in metadata['config']!
                                      .map((row) => row[0])
                                      .toSet())
                                path.isEmpty
                                    ? titles['config']!
                                    : path: MachineMaintenanceReadout(
                                  ['名称', '数值'],
                                  [
                                    for (final row in metadata['config']!.where(
                                      (row) => row[0] == path,
                                    ))
                                      [
                                        maintenanceHealthLabel(context, row[1]),
                                        maintenanceHealthValue(
                                          context,
                                          row[2],
                                          field: row[1],
                                        ),
                                      ],
                                  ],
                                  fields: true,
                                ),
                            },
                          ),
                        )
                      else
                        _MaintenanceTable(
                          key: ValueKey(_metadataKind),
                          maxBodyHeight: 160,
                          paginate: false,
                          limitToViewport: false,
                          headers: [
                            maintenanceLabel(context, '路径'),
                            if (_metadataKind == 'rotation' && canGroupRotation)
                              ...rotationFields.map(
                                (field) => field == '字节'
                                    ? l.listCardMetricSize
                                    : maintenanceHealthLabel(context, field),
                              )
                            else if (_metadataKind == 'storage')
                              l.maintenanceLogStorage
                            else ...[
                              maintenanceLabel(context, '名称'),
                              maintenanceLabel(context, '数值'),
                            ],
                          ],
                          rows: _metadataKind == 'rotation' && canGroupRotation
                              ? [
                                  for (final entry in groups.entries)
                                    OpenHandOperationalRankRow(
                                      value: 0,
                                      cells: [
                                        entry.key,
                                        for (final field in rotationFields)
                                          field == '字节' &&
                                                  int.tryParse(
                                                        entry.value[field] ??
                                                            '',
                                                      ) !=
                                                      null
                                              ? formatByteSize(
                                                  int.parse(
                                                    entry.value[field]!,
                                                  ),
                                                )
                                              : machineMaintenanceTimestamp(
                                                      entry.value[field] ?? '',
                                                      allowEpoch:
                                                          machineMaintenanceIsTimestampField(
                                                            field,
                                                          ),
                                                    ) ??
                                                    entry.value[field] ??
                                                    '—',
                                      ],
                                    ),
                                ]
                              : [
                                  for (final row in selectedRows)
                                    OpenHandOperationalRankRow(
                                      value: 0,
                                      cells: [
                                        row[0],
                                        if (_metadataKind == 'storage')
                                          int.tryParse(row[2]) == null
                                              ? row[2]
                                              : formatByteSize(
                                                  int.parse(row[2]) * 1024,
                                                )
                                        else ...[
                                          maintenanceHealthLabel(
                                            context,
                                            row[1],
                                          ),
                                          maintenanceHealthValue(
                                            context,
                                            row[2],
                                            field: row[1],
                                          ),
                                        ],
                                      ],
                                    ),
                                ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
