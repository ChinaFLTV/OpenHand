part of '../openhand_home_page.dart';

class _MachineContainerPanel extends StatefulWidget {
  const _MachineContainerPanel({
    super.key,
    required this.sessionId,
    required this.terminalId,
    required this.run,
    this.probe,
    required this.windows,
    required this.shell,
  });
  final String sessionId, terminalId;
  final Future<String> Function(String) run;
  final Future<String> Function(String)? probe;
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
  String _appliedScope = '';
  Map<String, String> _collectionIssues = {};
  bool _busy = false, _overlay = false, _autoRuntime = true;
  bool _listingFailed = false;

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

  Future<void> refresh({bool reset = false, bool applyScope = false}) async {
    if (_busy || _overlay || !mounted) return;
    final scope = reset || applyScope ? _scope.text.trim() : _appliedScope;
    final preserveDraft =
        !reset && !applyScope && _scope.text.trim() != _appliedScope;
    setState(() {
      final scopeChanged = !reset && scope != _appliedScope;
      if (scopeChanged) _autoRuntime = false;
      if (reset || scopeChanged) {
        _entries = [];
        _client = null;
        _metadata = '';
        _metrics = '';
        _contextName = '';
        _listingFailed = false;
      }
      _appliedScope = scope;
      _busy = true;
      _error = '';
      _collectionIssues = {};
    });
    final errors = <String, String>{};
    try {
      final selected = await discoverMachineContainers(
        run: widget.run,
        probe: widget.probe,
        runtime: _autoRuntime ? null : _runtime,
        preferred: _client?.scope == scope ? _client : null,
        scope: scope,
        windows: widget.windows,
        isCancelled: () => !mounted,
      );
      if (!mounted) return;
      final client = selected.client;
      final entries = selected.entries;
      if (client.runtime == MachineContainerRuntime.cri) {
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
        _runtime = client.runtime;
        _appliedScope = client.scope;
        if (!preserveDraft) _scope.text = client.scope;
        _contextName = client.contextName;
        _listingFailed = false;
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
            if (_metadata.trimLeft().startsWith('{'))
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
          _listingFailed = true;
          if (error is MachineContainerDiscoveryException) {
            _error = error.issues.values.first;
            _collectionIssues = Map.fromEntries(error.issues.entries.skip(1));
          } else {
            _error = '$error';
          }
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
    if (_busy || _overlay || _listingFailed || client == null) return;
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
                    title: maintenanceLabel(dialogContext, '选择 Pod 内的容器'),
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
                              subtitle: Text(
                                maintenanceContainerState(
                                  dialogContext,
                                  container.state,
                                ),
                              ),
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
          title: '${maintenanceLabel(context, action)} · ${entry.name}',
          confirmLabel:
              '${AppLocalizations.of(context)!.commonConfirm} ${maintenanceLabel(context, action)}',
          destructive: action != '启动' && action != '恢复',
          message:
              '${maintenanceDetailLabel(context, '目标')}：${client.runtime.label} / ${entry.namespace.isEmpty ? client.scope : entry.namespace} / ${entry.name}\n'
              '${maintenanceLabel(context, action == '删除' ? '删除后无法撤销；挂载卷不会主动删除。' : '此操作会改变容器运行状态。')}'
              '${entry.isPod ? '\n${maintenanceLabel(context, '控制器管理的 Pod 删除后可能自动重建。')}' : ''}',
        );
        if (confirmed != true || !mounted) return;
        final output = await client.act(entry, action);
        if (!mounted) return;
        await showAnimatedDialog<void>(
          context: context,
          builder: (_) => _ContainerReportDialog(
            title: '${maintenanceLabel(context, action)} · ${entry.name}',
            load: () async => jsonEncode({
              '结果': output.isEmpty
                  ? maintenanceLabel(context, '操作已提交，请刷新查看当前状态。')
                  : output,
            }),
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
                targetLabel:
                    '${entry.name} · ${maintenanceLabel(context, '容器文件')}',
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
            title: '${entry.name} · ${maintenanceLabel(context, action)}',
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
      final kubernetes = _runtime == MachineContainerRuntime.kubernetes;
      final hasNamespace =
          kubernetes || _runtime == MachineContainerRuntime.cri;
      return _MaintenanceCard(
        title:
            '${maintenanceLabel(context, pods ? 'Pod' : '容器')}'
            '${_client == null ? '' : ' · ${values.length}'}',
        icon: pods ? Icons.layers_outlined : Icons.inventory_2_outlined,
        scrollBody: false,
        child: values.isEmpty
            ? _MaintenanceEmptyHint(
                message: maintenanceLabel(
                  context,
                  _listingFailed && _client == null ? '当前数据暂不可用' : '当前范围没有记录',
                ),
              )
            : _MaintenanceTable(
                headers:
                    [
                          '名称',
                          '状态',
                          if (hasNamespace) pods ? '命名空间' : '命名空间 / Pod',
                          if (!pods || kubernetes) pods ? '节点' : '镜像',
                          if (kubernetes) ...['就绪', '重启次数'],
                          '创建时间',
                          if (!pods && !kubernetes) '端口',
                        ]
                        .map((label) => maintenanceDetailLabel(context, label))
                        .toList(),
                maxBodyHeight: 360,
                rowActions: (row) => {
                  if (!_busy && !_overlay && !_listingFailed)
                    for (final action
                        in _client?.actions(
                              row.data as MachineContainerEntry,
                            ) ??
                            <String>[])
                      if (action != '详情')
                        maintenanceLabel(context, action): () =>
                            _open(row.data as MachineContainerEntry, action),
                },
                onRowTap: _busy || _overlay || _listingFailed
                    ? null
                    : (row) => _open(row.data as MachineContainerEntry, '详情'),
                rows: [
                  for (final entry in values)
                    OpenHandOperationalRankRow(
                      rowKey: '${entry.id}/${entry.name}',
                      value: 0,
                      data: entry,
                      cells: [
                        entry.name,
                        maintenanceContainerState(context, entry.state),
                        if (hasNamespace)
                          '${entry.namespace} ${entry.pod}'.trim(),
                        if (!pods || kubernetes)
                          pods ? entry.node : entry.image,
                        if (kubernetes) ...[
                          maintenanceDetailValue(context, entry.ready),
                          entry.restarts,
                        ],
                        maintenanceDetailValue(context, entry.created),
                        if (!pods && !kubernetes) entry.ports,
                      ].map((value) => value.isEmpty ? '—' : value).toList(),
                      cellWidgets: [
                        null,
                        Tooltip(
                          message: entry.state,
                          child: _MaintenanceStatus(
                            label: maintenanceContainerState(
                              context,
                              entry.state,
                            ),
                            color: entry.running
                                ? OpenHandStatusColors.success
                                : entry.state.toLowerCase().contains('paused')
                                ? OpenHandStatusColors.warning
                                : entry.state.toLowerCase().contains('fail') ||
                                      entry.state.toLowerCase().contains(
                                        'backoff',
                                      )
                                ? OpenHandStatusColors.error
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
      );
    }

    return _MaintenanceAnimatedList(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          key: const ValueKey('container-runtime-toolbar'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(_maintenanceCardRadius),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: .65),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, bounds) {
              final theme = Theme.of(context);
              final cs = theme.colorScheme;
              final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
              final hasScope =
                  _runtime == MachineContainerRuntime.containerd ||
                  _runtime == MachineContainerRuntime.kubernetes ||
                  _runtime == MachineContainerRuntime.cri;
              final wide = bounds.maxWidth >= (hasScope ? 980 : 720) * scale;
              final inputWidth = wide ? 260 * scale : bounds.maxWidth;
              final scopeHint = maintenanceLabel(
                context,
                _runtime == MachineContainerRuntime.containerd
                    ? '命名空间（默认 default）'
                    : _runtime == MachineContainerRuntime.cri
                    ? 'CRI 端点（留空使用默认配置）'
                    : '命名空间（留空为全部）',
              );
              final border = OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: .55),
                ),
              );
              InputDecoration decoration(String hint, {IconData? icon}) =>
                  InputDecoration(
                    hintText: hint,
                    isDense: false,
                    constraints: const BoxConstraints.tightFor(
                      height: _maintenanceControlHeight,
                    ),
                    filled: true,
                    fillColor: cs.surfaceContainerLow,
                    border: border,
                    enabledBorder: border,
                    disabledBorder: border,
                    focusedBorder: border.copyWith(
                      borderSide: BorderSide(color: cs.primary, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    prefixIcon: icon == null ? null : Icon(icon, size: 16),
                    prefixIconConstraints: const BoxConstraints(minWidth: 34),
                  );
              final controls = Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _MaintenanceToolbarMenu<String>(
                    label: _autoRuntime
                        ? '${AppLocalizations.of(context)!.maintenanceContainerAuto}'
                              '${_client == null ? '' : ' · ${_runtime.label}'}'
                        : _runtime.label,
                    tooltip: '容器运行时',
                    value: _autoRuntime ? 'auto' : _runtime.name,
                    enabled: !_busy && !_overlay,
                    items: {
                      'auto': AppLocalizations.of(
                        context,
                      )!.maintenanceContainerAuto,
                      for (final runtime in MachineContainerRuntime.values)
                        runtime.name: runtime.label,
                    },
                    onSelected: (value) {
                      setState(() {
                        _autoRuntime = value == 'auto';
                        if (!_autoRuntime) {
                          _runtime = MachineContainerRuntime.values.byName(
                            value,
                          );
                        }
                        _scope.clear();
                      });
                      refresh(reset: true);
                    },
                  ),
                  if (hasScope)
                    SizedBox(
                      width: inputWidth,
                      height: _maintenanceControlHeight,
                      child: Tooltip(
                        message: scopeHint,
                        child: TextField(
                          controller: _scope,
                          enabled: !_busy && !_overlay,
                          style: theme.textTheme.bodySmall,
                          decoration: decoration(scopeHint),
                          onSubmitted: (_) => refresh(applyScope: true),
                        ),
                      ),
                    ),
                  SizedBox(
                    width: inputWidth,
                    height: _maintenanceControlHeight,
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      style: theme.textTheme.bodySmall,
                      decoration: decoration(
                        maintenanceLabel(context, '搜索名称、镜像、命名空间'),
                        icon: Icons.search_rounded,
                      ),
                    ),
                  ),
                ],
              );
              final contextLabel =
                  '${maintenanceLabel(context, '连接上下文')} · $_contextName';
              final heading = Row(
                children: [
                  _MaintenanceIconBadge(
                    icon: Icons.inventory_2_outlined,
                    color: cs.primary,
                    size: _maintenanceControlHeight,
                    iconSize: 17,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          maintenanceLabel(context, '容器运行时'),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (_contextName.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Tooltip(
                            message: contextLabel,
                            child: Text(
                              contextLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
              final refreshButton = SizedBox.square(
                dimension: _maintenanceControlHeight,
                child: _MachineTerminalIconButton(
                  onPressed: _busy || _overlay
                      ? null
                      : () => refresh(applyScope: true),
                  tooltip: maintenanceLabel(context, '刷新容器数据'),
                  icon: Icons.refresh_rounded,
                ),
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(child: heading),
                      const SizedBox(width: 16),
                      if (wide) ...[controls, const SizedBox(width: 10)],
                      refreshButton,
                    ],
                  ),
                  if (!wide) ...[const SizedBox(height: 12), controls],
                ],
              );
            },
          ),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          ),
        if (_error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _MaintenanceSection(
              title: maintenanceLabel(context, '采集异常'),
              icon: Icons.info_outline_rounded,
              accent: OpenHandStatusColors.warning,
              initiallyExpanded: true,
              child: _MaintenanceReadout(text: _error, section: 'containers'),
            ),
          ),
        if (_collectionIssues.isNotEmpty) ...[
          const SizedBox(height: _maintenanceGridGap),
          _MaintenanceSection(
            title: maintenanceLabel(context, '诊断项目'),
            icon: Icons.manage_search_rounded,
            initiallyExpanded: !_listingFailed,
            child: _MaintenanceReadout(
              section: 'containers',
              report: MachineMaintenanceReadout(
                [],
                [],
                groups: {
                  for (final issue in _collectionIssues.entries)
                    maintenanceDetailLabel(
                      context,
                      issue.key,
                    ): MachineMaintenanceReadout(
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
          ),
        ],
        const SizedBox(height: _maintenanceGridGap),
        if (_client != null) ...[
          _MaintenanceGrid(
            minWidth: 180,
            children: [
              for (final metric in [
                (
                  '运行中容器',
                  _entries.where((e) => !e.isPod && e.running).length,
                  OpenHandStatusColors.success,
                  Icons.play_circle_outline_rounded,
                ),
                (
                  '暂停容器',
                  _entries
                      .where(
                        (e) =>
                            !e.isPod &&
                            e.state.toLowerCase().contains('paused'),
                      )
                      .length,
                  OpenHandStatusColors.warning,
                  Icons.pause_circle_outline_rounded,
                ),
                (
                  '未运行',
                  _entries
                      .where(
                        (e) =>
                            !e.isPod &&
                            !e.running &&
                            !e.state.toLowerCase().contains('paused'),
                      )
                      .length,
                  Theme.of(context).colorScheme.secondary,
                  Icons.stop_circle_outlined,
                ),
              ])
                _MaintenanceCard(
                  title: metric.$1,
                  icon: metric.$4,
                  accent: metric.$3,
                  scrollBody: false,
                  child: _MaintenanceValue(
                    value: '${metric.$2}',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: metric.$3,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
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
        _MaintenanceSection(
          title: maintenanceLabel(context, '运行时元数据与状态'),
          icon: Icons.inventory_2_outlined,
          subtitle: maintenanceLabel(
            context,
            _maintenanceOutputStatus(_metadata),
          ),
          child: _MaintenanceReadout(
            text: _metadata,
            section: 'container_metadata',
          ),
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
              _MachineTerminalIconButton(
                tooltip: maintenanceLabel(
                  context,
                  _automatic ? '暂停自动刷新' : '自动刷新',
                ),
                onPressed: () {
                  setState(() {
                    _automatic = !_automatic;
                  });
                  _schedule();
                },
                icon: _automatic
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
              ),
              _MachineTerminalIconButton(
                tooltip: maintenanceLabel(context, '刷新'),
                onPressed: _busy ? null : _load,
                icon: Icons.refresh_rounded,
              ),
            ],
          ),
          if (_busy) const LinearProgressIndicator(),
          Flexible(
            child: _busy && _text.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: _MaintenanceEmptyHint(
                        centered: true,
                        icon: Icons.downloading_rounded,
                        message: maintenanceLabel(context, '正在读取详情…'),
                      ),
                    ),
                  )
                : Padding(
                    padding: _maintenanceDetailPadding,
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
              title: '${widget.title} · ${maintenanceLabel(context, '交互终端')}',
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
                  Expanded(child: Text(maintenanceLabel(context, _status))),
                  TextButton(
                    onPressed: _ready ? () => _send('\x03') : null,
                    child: const Text('Ctrl+C'),
                  ),
                  TextButton(
                    onPressed: _ready ? () => _send('\x04') : null,
                    child: Text('Ctrl+D / ${maintenanceLabel(context, '退出')}'),
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
