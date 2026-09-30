part of '../openhand_home_page.dart';

class _MachineContainerPanel extends StatefulWidget {
  const _MachineContainerPanel({
    super.key,
    required this.sessionId,
    required this.terminalId,
    required this.run,
    required this.windows,
    required this.shell,
  });
  final String sessionId, terminalId;
  final Future<String> Function(String) run;
  final bool windows;
  final MachineTerminalCommandShell shell;
  @override
  State<_MachineContainerPanel> createState() => _MachineContainerPanelState();
}

class _MachineContainerPanelState extends State<_MachineContainerPanel> {
  final _scope = TextEditingController();
  final _search = TextEditingController();
  MachineContainerRuntime _runtime = MachineContainerRuntime.docker;
  MachineContainerClient? _client;
  List<MachineContainerEntry> _entries = [];
  String _metadata = '', _metrics = '', _error = '', _contextName = '';
  Map<String, String> _collectionIssues = {};
  bool _busy = false, _overlay = false;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    _scope.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    if (_busy || _overlay || !mounted) return;
    setState(() {
      _busy = true;
      _error = '';
      _collectionIssues = {};
    });
    final errors = <String, String>{};
    var client = MachineContainerClient(
      runtime: _runtime,
      run: widget.run,
      scope: _scope.text.trim(),
      windows: widget.windows,
    );
    try {
      if (_runtime == MachineContainerRuntime.kubernetes ||
          _runtime == MachineContainerRuntime.docker) {
        _contextName = (await client.execute(
          _runtime == MachineContainerRuntime.kubernetes
              ? ['config', 'current-context']
              : ['context', 'show'],
        )).trim();
        if (_contextName.isEmpty) throw StateError('未找到当前连接上下文。');
        client = MachineContainerClient(
          runtime: _runtime,
          run: widget.run,
          scope: _scope.text.trim(),
          contextName: _contextName,
          windows: widget.windows,
        );
      } else {
        _contextName = '';
      }
      if (!mounted) return;
      final entries = client.parse(await client.execute(client.listArguments));
      if (!mounted) return;
      if (_runtime == MachineContainerRuntime.cri) {
        try {
          entries.addAll(
            client.parse(
              await client.execute(['pods', '-o', 'json']),
              pods: true,
            ),
          );
        } catch (error) {
          errors['Pod 列表'] = '$error';
        }
      }
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _client = client;
      });
      try {
        _metadata = await client.execute(client.metadataArguments);
      } catch (error) {
        _metadata = '$error';
      }
      if (!mounted) return;
      if (_runtime == MachineContainerRuntime.kubernetes) {
        try {
          final nodes = await client.execute(['get', 'nodes', '-o', 'json']);
          _metadata = jsonEncode({
            '版本': jsonDecode(_metadata),
            '节点': jsonDecode(nodes),
          });
        } catch (error) {
          errors['节点信息'] = '$error';
        }
      }
      if (!mounted) return;
      try {
        _metrics = await client.execute(client.metricsArguments);
      } catch (error) {
        _metrics = '$error';
      }
      if (!mounted) return;
      setState(() {
        _collectionIssues = errors;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _entries = [];
          _client = null;
          _metadata = '';
          _metrics = '';
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

  Future<void> _open(MachineContainerEntry entry, String action) async {
    final client = _client;
    if (_busy || _overlay || client == null) return;
    setState(() {
      _overlay = true;
    });
    String? operationError;
    try {
      if (entry.isPod && const ['终端', '文件管理', '日志'].contains(action)) {
        final containers = _entries
            .where(
              (e) =>
                  !e.isPod &&
                  (client.runtime == MachineContainerRuntime.kubernetes
                      ? e.pod == entry.name && e.namespace == entry.namespace
                      : e.pod == entry.id) &&
                  (action == '日志' || e.running),
            )
            .toList();
        if (containers.isEmpty) throw StateError('该 Pod 暂无可操作的容器，请刷新后重试。');
        final selected = await showAnimatedDialog<MachineContainerEntry>(
          context: context,
          builder: (dialogContext) => buildOpenHandDialog(
            maxHeight: MediaQuery.sizeOf(context).height * .65,
            child: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MachineTerminalDialogHeader(
                    icon: Icons.inventory_2_outlined,
                    title: '选择 Pod 内的容器',
                    onClose: () => Navigator.pop(dialogContext),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final container in containers)
                            ListTile(
                              title: Text(container.name),
                              subtitle: Text(container.state),
                              onTap: () =>
                                  Navigator.pop(dialogContext, container),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        if (selected == null || !mounted) return;
        entry = selected;
      }
      if (['启动', '停止', '重启', '暂停', '恢复', '删除'].contains(action)) {
        final confirmed = await showOpenHandConfirmDialog(
          context: context,
          title: '$action · ${entry.name}',
          confirmLabel: '确认$action',
          destructive: action != '启动' && action != '恢复',
          message:
              '目标：${client.runtime.label} / ${entry.namespace.isEmpty ? client.scope : entry.namespace} / ${entry.name}\n'
              '${action == '删除' ? '删除后无法撤销；挂载卷不会主动删除。' : '此操作会改变容器运行状态。'}'
              '${entry.isPod ? '\n控制器管理的 Pod 删除后可能自动重建。' : ''}',
        );
        if (confirmed != true || !mounted) return;
        final output = await client.act(entry, action);
        if (!mounted) return;
        await showAnimatedDialog<void>(
          context: context,
          builder: (_) => _ContainerReportDialog(
            title: '$action · ${entry.name}',
            load: () async => output.isEmpty ? '操作已提交，请刷新查看当前状态。' : output,
          ),
        );
      } else if (action == '终端') {
        await client.verify(entry);
        if (!mounted) return;
        await showAnimatedDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _ContainerInteractiveTerminal(
            title: entry.name,
            sessionId: widget.sessionId,
            terminalId: widget.terminalId,
            command: client.execCommand(entry, 'exec /bin/sh', tty: true),
            shell: widget.shell,
          ),
        );
      } else if (action == '文件管理') {
        await client.verify(entry);
        if (!mounted) return;
        final files = MachineTerminalFileService(
          context.read<MachineTerminalService>(),
          scopedCommand: (command) async {
            await client.verify(entry);
            return widget.run(client.execCommand(entry, command));
          },
        );
        try {
          await showAnimatedDialog<void>(
            context: context,
            builder: (_) => ChangeNotifierProvider.value(
              value: files,
              child: _MachineTerminalFileManagerDialog(
                targetLabel: '${entry.name} · 容器文件',
                sessionId: widget.sessionId,
                terminalId: widget.terminalId,
              ),
            ),
          );
        } finally {
          await files.shutdown();
          files.dispose();
        }
      } else {
        await client.verify(entry);
        if (!mounted) return;
        await showAnimatedDialog<void>(
          context: context,
          builder: (_) => _ContainerReportDialog(
            title: '${entry.name} · $action',
            section: action == '日志' ? 'logs' : 'container_details',
            load: () async {
              await client.verify(entry);
              return action == '日志'
                  ? client.logs(entry)
                  : action == '事件'
                  ? client.execute([
                      'get',
                      'events',
                      '-n',
                      entry.namespace,
                      '--field-selector',
                      'involvedObject.uid=${entry.id}',
                      '-o',
                      'json',
                    ])
                  : client.inspect(entry);
            },
          ),
        );
      }
    } catch (error) {
      operationError = '$error';
    } finally {
      if (mounted) {
        setState(() {
          _overlay = false;
        });
        await refresh();
        if (mounted && operationError != null) {
          setState(() => _error = operationError!);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.toLowerCase();
    final entries = _entries
        .where(
          (e) => '${e.name} ${e.id} ${e.image} ${e.namespace} ${e.node}'
              .toLowerCase()
              .contains(query),
        )
        .toList();
    Widget table(bool pods) {
      final values = entries.where((e) => e.isPod == pods).toList();
      return _MaintenanceCard(
        title: '${pods ? 'Pod' : '容器'} · ${values.length}',
        icon: pods ? Icons.layers_outlined : Icons.inventory_2_outlined,
        scrollBody: false,
        child: values.isEmpty
            ? const _MaintenanceEmptyHint(message: '当前范围没有记录')
            : _MaintenanceTable(
                headers: const [
                  '名称',
                  '状态',
                  '命名空间 / Pod',
                  '镜像 / 节点',
                  '就绪',
                  '重启次数',
                  '创建时间',
                  '端口',
                ],
                maxBodyHeight: 360,
                rowActions: (row) => {
                  if (!_busy && !_overlay)
                    for (final action
                        in _client?.actions(
                              row.data as MachineContainerEntry,
                            ) ??
                            <String>[])
                      action: () =>
                          _open(row.data as MachineContainerEntry, action),
                },
                rows: [
                  for (final entry in values)
                    OpenHandOperationalRankRow(
                      rowKey: '${entry.id}/${entry.name}',
                      value: 0,
                      data: entry,
                      cells: [
                        entry.name,
                        entry.state,
                        '${entry.namespace} ${entry.pod}'.trim(),
                        pods ? entry.node : entry.image,
                        entry.ready,
                        entry.restarts,
                        entry.created,
                        entry.ports,
                      ],
                    ),
                ],
              ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _MaintenanceToolbarMenu<MachineContainerRuntime>(
              label: _runtime.label,
              tooltip: '容器运行时',
              value: _runtime,
              enabled: !_busy && !_overlay,
              items: {
                for (final runtime in MachineContainerRuntime.values)
                  runtime: runtime.label,
              },
              onSelected: (runtime) {
                setState(() {
                  _runtime = runtime;
                  _scope.clear();
                  _entries = [];
                  _metadata = '';
                  _metrics = '';
                });
                refresh();
              },
            ),
            if (_runtime == MachineContainerRuntime.containerd ||
                _runtime == MachineContainerRuntime.kubernetes ||
                _runtime == MachineContainerRuntime.cri)
              SizedBox(
                width: 270,
                child: TextField(
                  controller: _scope,
                  enabled: !_busy && !_overlay,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: _runtime == MachineContainerRuntime.containerd
                        ? 'containerd 命名空间（默认 default）'
                        : _runtime == MachineContainerRuntime.cri
                        ? 'CRI 端点（空值使用默认配置）'
                        : 'Kubernetes 命名空间（空值为全部）',
                  ),
                  onSubmitted: (_) => refresh(),
                ),
              ),
            SizedBox(
              width: 250,
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search),
                  hintText: '搜索名称、镜像、命名空间',
                ),
              ),
            ),
            IconButton(
              onPressed: _busy || _overlay ? null : refresh,
              tooltip: '刷新容器数据',
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        if (_contextName.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('连接上下文：$_contextName'),
          ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          ),
        if (_error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _MaintenanceReadout(text: _error, section: 'containers'),
          ),
        if (_collectionIssues.isNotEmpty)
          _MaintenanceReadout(
            report: MachineMaintenanceReadout(
              [],
              [],
              groups: {
                for (final issue in _collectionIssues.entries)
                  issue.key: MachineMaintenanceReadout(
                    ['名称', '数值'],
                    machineMaintenanceDiagnosticFields(issue.value),
                    fields: true,
                    issue:
                        machineMaintenanceCollectionIssue(
                          issue.value,
                          'containers',
                        ) ??
                        'unavailable',
                  ),
              },
            ),
          ),
        const SizedBox(height: 12),
        if (_runtime == MachineContainerRuntime.kubernetes ||
            _runtime == MachineContainerRuntime.cri) ...[
          table(true),
          const SizedBox(height: 12),
        ],
        table(false),
        const SizedBox(height: 12),
        _MaintenanceCard(
          title: '实时资源采样',
          icon: Icons.monitor_heart_outlined,
          scrollBody: false,
          child: _MaintenanceReadout(
            text: _metrics,
            section: 'container_metrics',
          ),
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          title: const Text('运行时元数据与状态'),
          children: [
            _MaintenanceReadout(text: _metadata, section: 'container_metadata'),
          ],
        ),
      ],
    );
  }
}

class _ContainerReportDialog extends StatefulWidget {
  const _ContainerReportDialog({
    required this.title,
    required this.load,
    this.section = 'container_details',
  });
  final String section;
  final String title;
  final Future<String> Function() load;
  @override
  State<_ContainerReportDialog> createState() => _ContainerReportDialogState();
}

class _ContainerReportDialogState extends State<_ContainerReportDialog> {
  String _text = '', _error = '';
  bool _busy = false, _automatic = false;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy || !mounted) return;
    _timer?.cancel();
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final text = await widget.load();
      if (mounted) {
        setState(() {
          _text = text;
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
        _schedule();
      }
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (!_automatic || !mounted) return;
    _timer = startSafeTimer(const Duration(seconds: 10), () {
      if ((ModalRoute.of(context)?.isCurrent ?? false) &&
          (WidgetsBinding.instance.lifecycleState == null ||
              WidgetsBinding.instance.lifecycleState ==
                  AppLifecycleState.resumed)) {
        _load();
      } else {
        _schedule();
      }
    });
  }

  @override
  Widget build(BuildContext context) => buildOpenHandDialog(
    maxHeight: MediaQuery.sizeOf(context).height * .85,
    child: SizedBox(
      width: math.min(1000, MediaQuery.sizeOf(context).width * .9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MachineTerminalDialogHeader(
            icon: Icons.inventory_2_outlined,
            title: widget.title,
            onClose: () => Navigator.pop(context),
            trailingActions: [
              IconButton(
                tooltip: '自动刷新',
                onPressed: () {
                  setState(() {
                    _automatic = !_automatic;
                  });
                  _schedule();
                },
                icon: Icon(_automatic ? Icons.pause : Icons.play_arrow),
              ),
              IconButton(
                tooltip: '刷新',
                onPressed: _busy ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (_busy) const LinearProgressIndicator(),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: _MaintenanceReadout(
                  text: _error.isEmpty ? _text : _error,
                  section: _error.isEmpty ? widget.section : 'containers',
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ContainerInteractiveTerminal extends StatefulWidget {
  const _ContainerInteractiveTerminal({
    required this.title,
    required this.sessionId,
    required this.terminalId,
    required this.command,
    required this.shell,
  });
  final String title, sessionId, terminalId, command;
  final MachineTerminalCommandShell shell;
  @override
  State<_ContainerInteractiveTerminal> createState() =>
      _ContainerInteractiveTerminalState();
}

class _ContainerInteractiveTerminalState
    extends State<_ContainerInteractiveTerminal> {
  final _controller = TerminalController();
  MachineTerminalSession? _session;
  MachineTerminalService? _service;
  MachineTerminalSnapshot? _before;
  bool _active = true, _ready = false;
  String _status = '正在连接容器终端…';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  Future<void> _connect() async {
    if (!mounted) return;
    final service = context.read<MachineTerminalService>();
    _service = service;
    final session = service.terminalFor(widget.sessionId, widget.terminalId);
    _session = session;
    _before = session?.snapshot();
    if (session == null) {
      setState(() {
        _active = false;
        _status = '原终端已关闭，请重新连接。';
      });
      return;
    }
    try {
      final result = await service.executeCommand(
        sessionId: widget.sessionId,
        terminalId: widget.terminalId,
        command: widget.command,
        commandShell: widget.shell,
        timeout: const Duration(minutes: 10),
        recordHistory: false,
        onOutput: (_) {
          if (mounted && !_ready) {
            setState(() {
              _ready = true;
              _status = '输入 exit 退出容器 Shell；单次连接最长 10 分钟。';
            });
          }
        },
      );
      if (mounted) {
        setState(() {
          _status = result.succeeded
              ? '容器终端已退出。'
              : result.error ?? '容器终端连接结束，请查看终端输出。';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _status = '$error';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _active = false;
          _ready = false;
        });
      }
    }
  }

  Future<void> _send(String data) async {
    if (!_active || !_ready) return;
    try {
      await _service?.writeInput(
        sessionId: widget.sessionId,
        terminalId: widget.terminalId,
        data: data,
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _status = '$error';
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    final before = _before;
    if (before != null) {
      unawaited(
        _service!
            .resizeTerminal(
              sessionId: widget.sessionId,
              terminalId: widget.terminalId,
              columns: before.columns,
              rows: before.rows,
            )
            .catchError((Object error, StackTrace stack) {
              silentLog('machine_containers', '恢复终端尺寸', error, stack);
            }),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_active,
    child: buildOpenHandDialog(
      maxHeight: MediaQuery.sizeOf(context).height * .9,
      child: SizedBox(
        width: math.min(1100, MediaQuery.sizeOf(context).width * .9),
        height: MediaQuery.sizeOf(context).height * .78,
        child: Column(
          children: [
            _MachineTerminalDialogHeader(
              icon: Icons.terminal_rounded,
              title: '${widget.title} · 交互终端',
              onClose: () {
                if (!_active) {
                  Navigator.pop(context);
                } else {
                  _send('\x04');
                }
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(child: Text(_status)),
                  TextButton(
                    onPressed: _ready ? () => _send('\x03') : null,
                    child: const Text('Ctrl+C'),
                  ),
                  TextButton(
                    onPressed: _ready ? () => _send('\x04') : null,
                    child: const Text('Ctrl+D / 退出'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _session == null
                  ? const Center(child: CircularProgressIndicator())
                  : Padding(
                      padding: const EdgeInsets.all(12),
                      child: TerminalView(
                        _session!.terminal,
                        controller: _controller,
                        readOnly: !_active || !_ready,
                        autofocus: true,
                      ),
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
