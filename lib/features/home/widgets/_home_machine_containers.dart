part of '../openhand_home_page.dart';

const _containerTerminalSessionTimeout = Duration(minutes: 10);
const _containerTerminalExitTimeout = Duration(seconds: 3);
const _containerTerminalActionWidth = 136.0;

const _containerLogDialogHeightFraction = .9;
const _containerLogBodyHeightFraction = .7;

// 同一终端按顺序交接命令；用户操作可取消后台采集，旧结果不再写回。
class _ContainerQueryScope {
  _ContainerQueryScope({
    required this.fallback,
    required this.timeout,
    this.query,
    this.probe,
    Future<void>? previous,
  }) : _settled = previous ?? Future<void>.value();

  final Future<String> Function(String) fallback;
  final Future<String> Function(String)? probe;
  final MachineContainerOperationRunner? query;
  final Duration timeout;
  Future<void> _settled;
  bool cancelled = false;
  Future<void> get settled => _settled;
  void cancel() => cancelled = true;

  Future<String> run(
    String command, {
    bool probing = false,
    Duration? timeout,
    MachineContainerOperationRunner? runner,
    void Function(String)? onOutput,
    bool Function()? isCancelled,
  }) async {
    final previous = _settled;
    final done = Completer<void>();
    _settled = done.future;
    bool stopped() => cancelled || (isCancelled?.call() ?? false);
    try {
      await previous;
      if (stopped()) throw const MachineContainerConfigException('cancelled');
      final execute = runner ?? query;
      final result = await (execute == null
          ? (probing ? probe ?? fallback : fallback)(command)
          : execute(
              command,
              timeout:
                  timeout ??
                  (probing ? machineContainerProbeTimeout : this.timeout),
              onOutput: onOutput,
              isCancelled: stopped,
            ));
      if (stopped()) throw const MachineContainerConfigException('cancelled');
      return result;
    } finally {
      done.complete();
    }
  }
}

class _MachineContainerPanel extends StatefulWidget {
  const _MachineContainerPanel({
    super.key,
    required this.sessionId,
    required this.terminalId,
    required this.run,
    this.probe,
    this.query,
    this.operate,
    required this.registryFactory,
    this.operationTimeout = const Duration(seconds: 30),
    required this.windows,
    required this.shell,
  });
  final String sessionId, terminalId;
  final Future<String> Function(String) run;
  final Future<String> Function(String)? probe;
  final MachineContainerOperationRunner? query, operate;
  final MachineImageRegistry Function() registryFactory;
  final Duration operationTimeout;
  final bool windows;
  final MachineTerminalCommandShell shell;
  @override
  State<_MachineContainerPanel> createState() => _MachineContainerPanelState();
}

class _MachineContainerPanelState extends State<_MachineContainerPanel> {
  final _scope = TextEditingController();
  final _search = TextEditingController();
  final _resourcesKey = GlobalKey<_MachineContainerResourcesState>();
  final _telemetryKey = GlobalKey<_ContainerTelemetryPanelState>();
  int _resourceTab = 3;
  MachineContainerRuntime _runtime = MachineContainerRuntime.docker;
  MachineContainerClient? _client;
  List<MachineContainerEntry> _entries = [];
  Map<String, MachineContainerListDetails> _listDetails = {};
  Map<String, MachineContainerUsage> _usageSamples = {};
  String _metadata = '', _metrics = '', _error = '', _contextName = '';
  String _appliedScope = '';
  final _kubernetesMetadata = <String, Object?>{};
  Map<String, String> _collectionIssues = {};
  bool _busy = false, _overlay = false, _autoRuntime = true;
  bool _copyingCommand = false;
  bool _listingFailed = false;
  _ContainerQueryScope? _query;

  bool get _refreshFailed {
    if (_resourceTab >= 3) {
      final telemetry = _telemetryKey.currentState;
      return _resourceTab == 3 && _client == null && _listingFailed ||
          telemetry != null &&
              (telemetry._error.isNotEmpty ||
                  telemetry._plan.isNotEmpty &&
                      telemetry._plan.every(
                        (item) => telemetry._issues.containsKey(item.id),
                      ));
    }
    return _client == null || _listingFailed;
  }

  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    _query?.cancel();
    _scope.dispose();
    _search.dispose();
    super.dispose();
  }

  _ContainerQueryScope _beginQuery() {
    final previous = _query;
    previous?.cancel();
    _busy = false;
    return _query = _ContainerQueryScope(
      fallback: widget.run,
      probe: widget.probe,
      query: widget.query,
      timeout: widget.operationTimeout,
      previous: previous?.settled,
    );
  }

  Future<({String output, String image})> _pullImage(
    MachineContainerClient client,
    String image, {
    required Duration timeout,
    void Function(String)? onOutput,
    MachineImageTransferProgress? onProgress,
    bool Function()? isCancelled,
  }) {
    final service = context.read<MachineTerminalFileService>();
    final query = _query!;
    final l = AppLocalizations.of(context)!;
    final elapsed = Stopwatch()..start();
    var lastLog = Duration.zero;
    MachineImageTransferStage? lastStage;
    return MachineImageOperations(
      clientFactory: SystemProxyResolver.instance.createRawHttpClient,
      run: (command, {required timeout, onOutput, isCancelled}) => query.run(
        command,
        runner: widget.operate,
        timeout: timeout,
        onOutput: onOutput,
        isCancelled: isCancelled,
      ),
      upload: (file, directory, stopped, progress) =>
          service.uploadTemporaryFile(
            sessionId: widget.sessionId,
            terminalId: widget.terminalId,
            sourcePath: file.path,
            targetDirectory: directory,
            targetName: 'image.tar',
            onProgress: progress,
            isCancelled: stopped,
          ),
      cleanup: (command) async {
        try {
          await service.runMaintenanceCommand(
            sessionId: widget.sessionId,
            terminalId: widget.terminalId,
            command: command,
            commandShell: widget.shell,
            timeout: const Duration(seconds: 5),
          );
        } catch (error, stack) {
          silentLog('machine_image', '清理目标机器的镜像临时目录', error, stack);
        }
      },
    ).pull(
      client,
      image,
      timeout: timeout,
      isCancelled: isCancelled,
      onOutput: onOutput,
      onProgress: (stage, received, total) {
        if (!mounted || (isCancelled?.call() ?? false)) {
          return;
        }
        onProgress?.call(stage, received, total);
        if (stage == lastStage &&
            received != total &&
            elapsed.elapsed - lastLog < const Duration(milliseconds: 100)) {
          return;
        }
        lastStage = stage;
        lastLog = elapsed.elapsed;
        onOutput?.call(
          '${switch (stage) {
            MachineImageTransferStage.preparing => l.maintenanceImagePreparing,
            MachineImageTransferStage.download => l.maintenanceImageDownloading,
            MachineImageTransferStage.upload => l.maintenanceImageUploading,
            MachineImageTransferStage.import => l.maintenanceImageImporting,
          }}${total == 0 ? '' : ' · ${formatLocalizedByteSizeOf(context, received)} / ${formatLocalizedByteSizeOf(context, total)}'}',
        );
      },
    );
  }

  Future<void> refresh({bool reset = false, bool applyScope = false}) async {
    applyScope =
        applyScope && _resourceTab < 3 && _scope.text.trim() != _appliedScope;
    if ((_busy && !reset && !applyScope) || _overlay || !mounted) return;
    if (_resourceTab >= 3 &&
        !reset &&
        !applyScope &&
        (_client != null || _resourceTab == 4)) {
      await _telemetryKey.currentState?.refresh();
      return;
    }
    if (_resourceTab != 0 && !reset && !applyScope && _client != null) {
      await _resourcesKey.currentState?.refresh();
      return;
    }
    final query = _beginQuery();
    final scope = reset || applyScope ? _scope.text.trim() : _appliedScope;
    final preserveDraft =
        !reset && !applyScope && _scope.text.trim() != _appliedScope;
    setState(() {
      final scopeChanged = !reset && scope != _appliedScope;
      if (scopeChanged) _autoRuntime = false;
      if (reset || scopeChanged) {
        _entries = [];
        _listDetails = {};
        _usageSamples = {};
        _client = null;
        _metadata = '';
        _kubernetesMetadata.clear();
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
        run: query.run,
        probe: (command) => query.run(command, probing: true),
        runtime: _autoRuntime ? null : _runtime,
        preferred: _client?.scope == scope ? _client : null,
        scope: scope,
        windows: widget.windows,
        isCancelled: () => !mounted || query.cancelled,
      );
      if (!mounted || query.cancelled) return;
      final client = selected.client;
      final entries = selected.entries;
      final sameTarget =
          _client?.runtime == client.runtime &&
          _client?.scope == client.scope &&
          _contextName == client.contextName &&
          listEquals(_client?.launcher, client.launcher);
      setState(() {
        if (!sameTarget) {
          _listDetails = {};
          _usageSamples = {};
          _metadata = '';
          _kubernetesMetadata.clear();
          _metrics = '';
        }
        _entries = [
          ...entries,
          if (sameTarget && client.runtime == MachineContainerRuntime.cri)
            ..._entries.where((entry) => entry.isPod),
        ];
        final ids = entries.map((entry) => entry.id).toSet();
        _listDetails.removeWhere((id, _) => !ids.contains(id));
        _usageSamples.removeWhere((id, _) => !ids.contains(id));
        _client = client.copyWith(run: widget.run);
        _runtime = client.runtime;
        _appliedScope = client.scope;
        if (!preserveDraft) _scope.text = client.scope;
        _contextName = client.contextName;
        _listingFailed = false;
      });
      if (_resourceTab != 0) return;
      if (client.runtime == MachineContainerRuntime.cri) {
        try {
          final pods = client.parse(
            await client.execute(['pods', '-o', 'json']),
            pods: true,
          );
          if (!mounted || query.cancelled) return;
          setState(() => _entries = [...entries, ...pods]);
        } catch (error) {
          if (!mounted || query.cancelled) return;
          errors['Pod 列表'] = '$error';
          setState(() => _collectionIssues = Map.of(errors));
        }
      }
      try {
        var metadata = await client.execute(client.metadataArguments);
        if (!mounted || query.cancelled) return;
        if (client.runtime == MachineContainerRuntime.kubernetes) {
          _kubernetesMetadata['版本'] = jsonDecode(metadata);
          metadata = jsonEncode(_kubernetesMetadata);
        }
        if (_metadata != metadata) setState(() => _metadata = metadata);
      } catch (error) {
        if (!mounted || query.cancelled) return;
        errors['运行时元数据与状态'] = '$error';
        setState(() => _collectionIssues = Map.of(errors));
      }
      if (client.runtime == MachineContainerRuntime.kubernetes) {
        try {
          final nodes = await client.execute(['get', 'nodes', '-o', 'json']);
          if (!mounted || query.cancelled) return;
          _kubernetesMetadata['节点'] = jsonDecode(nodes);
          final metadata = jsonEncode(_kubernetesMetadata);
          if (_metadata != metadata) setState(() => _metadata = metadata);
        } catch (error) {
          if (!mounted || query.cancelled) return;
          errors['节点信息'] = '$error';
          setState(() => _collectionIssues = Map.of(errors));
        }
      }
      try {
        final metrics = await client.execute(client.metricsArguments);
        if (!mounted || query.cancelled) return;
        final usage = client.usageSamples(metrics, entries);
        if (_metrics != metrics || !mapEquals(_usageSamples, usage)) {
          setState(() {
            _metrics = metrics;
            _usageSamples = usage;
          });
        }
      } catch (error) {
        if (!mounted || query.cancelled) return;
        errors['实时资源采样'] = '$error';
        setState(() {
          _usageSamples = {};
          _collectionIssues = Map.of(errors);
        });
      }
      final details = <String, MachineContainerListDetails>{};
      try {
        await for (final batch in client.listDetails(
          entries,
          isCancelled: () => !mounted || query.cancelled,
        )) {
          if (!mounted || query.cancelled) return;
          details.addAll(batch);
          if (batch.entries.any(
            (entry) => _listDetails[entry.key] != entry.value,
          )) {
            setState(() => _listDetails.addAll(batch));
          }
        }
      } catch (error) {
        if (!mounted || query.cancelled) return;
        errors['最近启动时间'] = '$error';
        setState(() {
          _listDetails = details;
          _collectionIssues = Map.of(errors);
        });
      }
    } catch (error) {
      if (mounted && !query.cancelled) {
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
      if (mounted && !query.cancelled) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _createContainer() async {
    if (_overlay || _client == null) return;
    final query = _beginQuery();
    final client = _client!.copyWith(run: query.run);
    setState(() => _overlay = true);
    bool? changed;
    try {
      changed = await showAnimatedDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ContainerResourceFormDialog(
          client: client,
          action: _ContainerResourceAction.createContainer,
          pullImage: _pullImage,
          registryFactory: widget.registryFactory,
          operate: (command, {required timeout, onOutput, isCancelled}) =>
              query.run(
                command,
                runner: widget.operate,
                timeout: timeout,
                onOutput: onOutput,
                isCancelled: isCancelled,
              ),
          timeout: widget.operationTimeout,
          imageReferences: _entries.map((entry) => entry.image).toList(),
        ),
      );
    } finally {
      query.cancel();
      if (mounted) setState(() => _overlay = false);
    }
    if (mounted && changed == true) await refresh();
  }

  Future<void> _open(MachineContainerEntry entry, String action) async {
    if (_overlay || _client == null) return;
    final query = _beginQuery();
    final client = _client!.copyWith(run: query.run);
    setState(() {
      _overlay = true;
      _copyingCommand = action == '复制 run 命令';
      _error = '';
    });
    String? operationError;
    var refreshNeeded = false;
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
              '${AppLocalizations.of(context)!.commonConfirm}'
              '${openHandIsChineseLocale(context) ? '' : ' '}'
              '${maintenanceLabel(context, action)}',
          destructive: action != '启动' && action != '恢复',
          message:
              '${maintenanceDetailLabel(context, '目标')}：${client.runtime.label} / ${entry.namespace.isEmpty ? client.scope : entry.namespace} / ${entry.name}\n'
              '${maintenanceLabel(context, action == '删除' ? '删除后无法撤销；挂载卷不会主动删除。' : '此操作会改变容器运行状态。')}'
              '${entry.isPod ? '\n${maintenanceLabel(context, '控制器管理的 Pod 删除后可能自动重建。')}' : ''}',
        );
        if (confirmed != true || !mounted) return;
        refreshNeeded = true;
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
      } else if (action == '复制 run 命令') {
        final command = await client.runCommand(
          entry,
          isCancelled: () => !mounted,
        );
        if (!mounted) return;
        await copyOpenHandTextToClipboard(
          context: context,
          text: command,
          logTag: 'machine_containers',
          logAction: '复制容器运行命令',
          successMessage: AppLocalizations.of(
            context,
          )!.maintenanceContainerRunCopied,
        );
      } else if (action == '查看镜像详情') {
        await showAnimatedDialog<void>(
          context: context,
          builder: (_) => _ContainerReportDialog(
            title: '${entry.name} · ${maintenanceLabel(context, action)}',
            section: 'container_image',
            isCancelled: () => query.cancelled,
            load: () => client.imageDetails(
              entry,
              isCancelled: () => !mounted || query.cancelled,
            ),
          ),
        );
      } else if (action == '终端') {
        await client.verify(entry);
        await query.settled;
        if (!mounted || query.cancelled) return;
        final readyMarker =
            '__OH_CONTAINER_READY_${DateTime.now().microsecondsSinceEpoch}__';
        await showAnimatedDialog<void>(
          context: context,
          barrierDismissible: false,
          dismissOnEscape: false,
          builder: (_) => _ContainerInteractiveTerminal(
            title: entry.name,
            sessionId: widget.sessionId,
            terminalId: widget.terminalId,
            command: client.execCommand(
              entry,
              "printf '\\033[?7l%s\\r\\033[K\\033[?7h' ${posixShellQuote(readyMarker)}; exec /bin/sh",
              tty: true,
            ),
            readyMarker: readyMarker,
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
            return query.run(client.execCommand(entry, command));
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
        await showAnimatedDialog<void>(
          context: context,
          builder: (_) => _ContainerReportDialog(
            title: '${entry.name} · ${maintenanceLabel(context, action)}',
            section: action == '日志' ? 'logs' : 'container_details',
            isCancelled: () => query.cancelled,
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
      if (mounted) {
        operationError = maintenanceContainerOperationError(context, error);
      }
    } finally {
      query.cancel();
      if (mounted) {
        setState(() {
          _overlay = false;
          _copyingCommand = false;
        });
        if (refreshNeeded) unawaited(refresh());
        if (mounted && operationError != null) {
          setState(() => _error = operationError!);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const resourceControlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(8)),
    );
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
      final desktop = !pods && (_client?.supportsRunCommand ?? false);
      final kubernetes = _runtime == MachineContainerRuntime.kubernetes;
      final hasNamespace =
          kubernetes || _runtime == MachineContainerRuntime.cri;
      final enabled = !_overlay && _client != null;
      final theme = Theme.of(context);
      OpenHandOperationalRankRow row(MachineContainerEntry entry) {
        final status = maintenanceContainerState(context, entry.state);
        final color = entry.running
            ? OpenHandStatusColors.success
            : entry.state.toLowerCase().contains('paused')
            ? OpenHandStatusColors.warning
            : entry.state.toLowerCase().contains('fail') ||
                  entry.state.toLowerCase().contains('backoff')
            ? OpenHandStatusColors.error
            : theme.colorScheme.onSurfaceVariant;
        final detail = _listDetails[entry.id];
        final idle = const {
          'exited',
          'created',
          'dead',
          'stopped',
          'configured',
          'paused',
        }.contains(entry.state.toLowerCase());
        final sample = _usageSamples[entry.id];
        final cpu = idle ? 0.0 : sample?.cpuPercent;
        final ports = entry.running && entry.ports.isNotEmpty
            ? entry.ports
            : detail?.ports.isNotEmpty == true
            ? detail!.ports
            : entry.ports;
        final displayPorts = ports
            .split(',')
            .map(
              (port) => port
                  .trim()
                  .replaceFirst(RegExp(r'^(?:0\.0\.0\.0|\[::\]):'), '')
                  .replaceAll('->', ':')
                  .replaceFirst(RegExp(r'/tcp$'), ''),
            )
            .toSet()
            .join(', ');
        final id = entry.id.length > 12 ? entry.id.substring(0, 12) : entry.id;
        final size = entry.metadata['Size'];
        final writable = size is Map
            ? size['rwSize'] ?? size['RwSize']
            : '$size'.split(' (').first;
        final rootSize = size is Map
            ? size['rootFsSize'] ?? size['RootFsSize']
            : RegExp(
                r'\(virtual\s+([^)]*)\)',
                caseSensitive: false,
              ).firstMatch('$size')?.group(1);
        final memoryPercent = sample?.memoryPercent;
        final health = machineContainerMetadataText(
          entry.metadata['HealthStatus'],
        );
        return OpenHandOperationalRankRow(
          rowKey: '${entry.id}/${entry.name}',
          value: 0,
          data: entry,
          cells: [
            entry.name,
            if (desktop) ...[
              id,
              entry.image,
              displayPorts,
              cpu == null ? '—' : '${cpu.toStringAsFixed(cpu == 0 ? 0 : 2)}%',
              machineMaintenanceTimestamp(
                    detail?.startedAt ?? '',
                    allowEpoch: true,
                  ) ??
                  '—',
              status,
              _containerCapacityText(context, sample?.memoryUsage),
              memoryPercent == null
                  ? '—'
                  : '${memoryPercent.toStringAsFixed(2)}%',
              _containerCapacityText(context, writable),
              _containerCapacityText(context, rootSize),
              _containerCapacityText(context, sample?.networkIO),
              _containerCapacityText(context, sample?.blockIO),
              sample?.processes?.toString() ?? '—',
              health.isEmpty
                  ? '—'
                  : maintenanceDetailValue(
                      context,
                      health,
                      field: 'HealthStatus',
                    ),
              machineContainerMetadataText(entry.metadata['Networks']),
              machineContainerMetadataText(entry.metadata['Mounts']),
              maintenanceDetailValue(
                context,
                entry.created,
                field: 'createdAt',
              ),
              machineContainerMetadataText(entry.metadata['Command']),
              machineContainerMetadataText(entry.metadata['Labels']),
            ] else ...[
              status,
              if (hasNamespace) '${entry.namespace} ${entry.pod}'.trim(),
              if (!pods || kubernetes) pods ? entry.node : entry.image,
              if (kubernetes) ...[
                maintenanceDetailValue(context, entry.ready),
                entry.restarts,
              ],
              maintenanceDetailValue(
                context,
                entry.created,
                field: 'createdAt',
              ),
              if (!pods && !kubernetes) entry.ports,
            ],
          ].map((value) => value.isEmpty ? '—' : value).toList(),
          cellSubtitles: desktop ? [status, entry.id, '', ports] : null,
          cellWidgets: desktop
              ? [
                  Semantics(
                    label: '${entry.name} · $status',
                    child: Row(
                      children: [
                        Icon(Icons.circle, size: 8, color: color),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            entry.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  InkWell(
                    onTap: entry.image.isNotEmpty
                        ? () => _open(entry, '查看镜像详情')
                        : null,
                    borderRadius: BorderRadius.circular(4),
                    child: Text(
                      entry.image.isEmpty ? '—' : entry.image,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  Text(
                    displayPorts.isEmpty ? '—' : displayPorts,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  _MaintenanceNumber(
                    raw: cpu == null ? '—' : '$cpu%',
                    readable: cpu == null
                        ? '—'
                        : '${cpu.toStringAsFixed(cpu == 0 ? 0 : 2)}%',
                  ),
                  null,
                  _MaintenanceStatus(label: status, color: color),
                  _MaintenanceNumber(
                    raw: sample?.memoryUsage ?? '—',
                    readable: _containerCapacityText(
                      context,
                      sample?.memoryUsage,
                    ),
                  ),
                  _MaintenanceNumber(
                    raw: memoryPercent == null ? '—' : '$memoryPercent%',
                    readable: memoryPercent == null
                        ? '—'
                        : '${memoryPercent.toStringAsFixed(2)}%',
                  ),
                  _MaintenanceNumber(
                    raw: machineContainerMetadataText(writable),
                    readable: _containerCapacityText(context, writable),
                  ),
                  _MaintenanceNumber(
                    raw: machineContainerMetadataText(rootSize),
                    readable: _containerCapacityText(context, rootSize),
                  ),
                  _MaintenanceNumber(
                    raw: sample?.networkIO ?? '—',
                    readable: _containerCapacityText(
                      context,
                      sample?.networkIO,
                    ),
                  ),
                  _MaintenanceNumber(
                    raw: sample?.blockIO ?? '—',
                    readable: _containerCapacityText(context, sample?.blockIO),
                  ),
                  _MaintenanceNumber(raw: sample?.processes?.toString() ?? '—'),
                ]
              : [
                  null,
                  Tooltip(
                    message: entry.state,
                    child: _MaintenanceStatus(label: status, color: color),
                  ),
                ],
        );
      }

      return _MaintenanceCard(
        key: ValueKey(('container-list', pods)),
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
                    (desktop
                            ? [
                                '名称',
                                '容器标识',
                                '镜像',
                                '端口',
                                'CPU (%)',
                                '最近启动时间',
                                '状态',
                                '内存用量 / 上限',
                                '内存使用率',
                                AppLocalizations.of(
                                  context,
                                )!.maintenanceResourceWritableSize,
                                AppLocalizations.of(
                                  context,
                                )!.maintenanceResourceRootSize,
                                '网络接收 / 发送',
                                '块 IO 读取 / 写入',
                                '进程数',
                                '健康检查',
                                '网络列表',
                                '挂载点',
                                '创建时间',
                                '命令',
                                '标签',
                              ]
                            : [
                                '名称',
                                '状态',
                                if (hasNamespace) pods ? '命名空间' : '命名空间 / Pod',
                                if (!pods || kubernetes) pods ? '节点' : '镜像',
                                if (kubernetes) ...['就绪', '重启次数'],
                                '创建时间',
                                if (!pods && !kubernetes) '端口',
                              ])
                        .map((label) => maintenanceDetailLabel(context, label))
                        .toList(),
                maxBodyHeight: 360,
                columnAlignments: desktop
                    ? const {
                        4: Alignment.centerRight,
                        7: Alignment.centerRight,
                        8: Alignment.centerRight,
                        9: Alignment.centerRight,
                        10: Alignment.centerRight,
                        11: Alignment.centerRight,
                        12: Alignment.centerRight,
                        13: Alignment.centerRight,
                      }
                    : const {},
                minimumColumnWidths: desktop
                    ? const {
                        7: 180,
                        9: 130,
                        10: 130,
                        11: 180,
                        12: 180,
                        16: 220,
                        18: 260,
                        19: 260,
                      }
                    : const {},
                rowActions: (row) => {
                  if (enabled)
                    for (final action
                        in _client?.actions(
                              row.data as MachineContainerEntry,
                            ) ??
                            <String>[])
                      if (action != '详情')
                        maintenanceLabel(context, action): () =>
                            _open(row.data as MachineContainerEntry, action),
                },
                onRowTap: enabled
                    ? (row) => _open(row.data as MachineContainerEntry, '详情')
                    : null,
                rows: values.map(row).toList(),
              ),
      );
    }

    return _MaintenanceAnimatedList(
      padding: _maintenancePanelPadding,
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
                  _resourceTab < 3 &&
                  (_runtime == MachineContainerRuntime.containerd ||
                      _runtime == MachineContainerRuntime.kubernetes ||
                      _runtime == MachineContainerRuntime.cri);
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
                    enabled: !_overlay,
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
                          enabled: !_overlay,
                          style: theme.textTheme.bodySmall,
                          decoration: decoration(scopeHint),
                          onSubmitted: (_) => refresh(applyScope: true),
                        ),
                      ),
                    ),
                  if (_resourceTab == 0)
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
                            child: _MaintenanceValue(
                              value: contextLabel,
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
                      : () => refresh(
                          applyScope: _scope.text.trim() != _appliedScope,
                        ),
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
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: LayoutBuilder(
              builder: (context, bounds) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in [
                    (3, '运行时概览', Icons.monitor_heart_outlined),
                    (0, '容器', Icons.inventory_2_outlined),
                    (1, '镜像', Icons.layers_outlined),
                    (2, '数据卷', Icons.storage_rounded),
                    (4, 'Kubernetes 概览', Icons.hub_outlined),
                  ])
                    SizedBox(
                      height: _maintenanceControlHeight,
                      child: ChoiceChip(
                        showCheckmark: false,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.standard,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        labelPadding: const EdgeInsets.only(left: 6),
                        avatarBoxConstraints: const BoxConstraints.tightFor(
                          width: 16,
                          height: 16,
                        ),
                        shape: resourceControlShape,
                        side: BorderSide(
                          color:
                              (_resourceTab == item.$1
                                      ? cs.primary
                                      : cs.outlineVariant)
                                  .withValues(alpha: .55),
                        ),
                        backgroundColor: cs.surface.withValues(alpha: .72),
                        selectedColor: cs.primaryContainer,
                        labelStyle: theme.textTheme.bodySmall?.copyWith(
                          color: _resourceTab == item.$1
                              ? cs.onPrimaryContainer
                              : cs.onSurface,
                        ),
                        iconTheme: IconThemeData(
                          color: _resourceTab == item.$1
                              ? cs.onPrimaryContainer
                              : cs.onSurfaceVariant,
                        ),
                        elevation: 0,
                        pressElevation: 0,
                        shadowColor: Colors.transparent,
                        selectedShadowColor: Colors.transparent,
                        surfaceTintColor: Colors.transparent,
                        avatar: Icon(item.$3, size: 16),
                        label: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: math.max(48, bounds.maxWidth - 72),
                          ),
                          child: Tooltip(
                            message: maintenanceLabel(context, item.$2),
                            child: Text(
                              item.$1 == 1
                                  ? AppLocalizations.of(
                                      context,
                                    )!.maintenanceImages
                                  : maintenanceLabel(context, item.$2),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        selected: _resourceTab == item.$1,
                        onSelected:
                            _overlay ||
                                _client == null &&
                                    const [1, 2].contains(item.$1)
                            ? null
                            : (_) {
                                if (_resourceTab == item.$1) return;
                                _query?.cancel();
                                setState(() {
                                  _busy = false;
                                  _resourceTab = item.$1;
                                });
                                if (_resourceTab == 0 ||
                                    _resourceTab == 3 && _client == null) {
                                  refresh();
                                }
                              },
                      ),
                    ),
                  if (_resourceTab == 0 &&
                      (_client?.supportsResources ?? false))
                    SizedBox(
                      height: _maintenanceControlHeight,
                      child: FilledButton.tonalIcon(
                        style: _maintenanceActionButtonStyle(context),
                        onPressed: _overlay ? null : _createContainer,
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: Text(
                          AppLocalizations.of(
                            context,
                          )!.maintenanceContainerCreate,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (_resourceTab >= 3)
          _ContainerTelemetryPanel(
            key: _telemetryKey,
            client: _client,
            kubernetes: _resourceTab == 4,
            windows: widget.windows,
            beginQuery: _beginQuery,
            connecting: _busy && _client == null,
            connectionError: _resourceTab == 3 && _client == null ? _error : '',
            onReconnect: refresh,
            onCancelConnection: () {
              _query?.cancel();
              setState(() => _busy = false);
            },
          ),
        if ((_resourceTab == 1 || _resourceTab == 2) && _client != null)
          _MachineContainerResources(
            key: _resourcesKey,
            client: _client!,
            beginQuery: _beginQuery,
            kind: _resourceTab == 1
                ? MachineContainerResourceKind.images
                : MachineContainerResourceKind.volumes,
            operate: widget.operate,
            pullImage: _pullImage,
            registryFactory: widget.registryFactory,
            timeout: widget.operationTimeout,
            onOverlayChanged: (value) {
              if (mounted) setState(() => _overlay = value);
            },
            onCreated: () {
              if (mounted) {
                setState(() => _resourceTab = 0);
                refresh();
              }
            },
          ),
        if (_busy && _resourceTab < 3 || _copyingCommand)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          ),
        if (_resourceTab < 3 && _error.isNotEmpty)
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
        if (_resourceTab < 3 && _collectionIssues.isNotEmpty) ...[
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
        if (_resourceTab == 0) ...[
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
      ],
    );
  }
}

class _ContainerTelemetryPanel extends StatefulWidget {
  const _ContainerTelemetryPanel({
    super.key,
    required this.client,
    required this.kubernetes,
    required this.windows,
    required this.beginQuery,
    this.connecting = false,
    this.connectionError = '',
    this.onReconnect,
    this.onCancelConnection,
  });
  final MachineContainerClient? client;
  final bool kubernetes, windows;
  final _ContainerQueryScope Function() beginQuery;
  final bool connecting;
  final String connectionError;
  final VoidCallback? onReconnect;
  final VoidCallback? onCancelConnection;

  @override
  State<_ContainerTelemetryPanel> createState() =>
      _ContainerTelemetryPanelState();
}

class _ContainerTelemetryPanelState extends State<_ContainerTelemetryPanel> {
  final _namespace = TextEditingController();
  final _reports = <String, MachineMaintenanceReadout>{};
  final _outputs = <String, String>{};
  final _issues = <String, String>{};
  final _updated = <String, DateTime>{};
  List<MachineContainerTelemetryQuery> _plan = [];
  _ContainerQueryScope? _query;
  MachineContainerClient? _client;
  String _error = '', _active = '';
  bool _busy = false, _cancelled = false;
  int _completed = 0, _total = 0;

  @override
  void initState() {
    super.initState();
    _namespace.text =
        widget.client?.runtime == MachineContainerRuntime.kubernetes
        ? widget.client!.scope
        : '';
    if (!widget.connecting && (widget.kubernetes || widget.client != null)) {
      refresh();
    }
  }

  @override
  void didUpdateWidget(covariant _ContainerTelemetryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kubernetes != widget.kubernetes ||
        oldWidget.client?.runtime != widget.client?.runtime ||
        oldWidget.client?.scope != widget.client?.scope ||
        oldWidget.client?.contextName != widget.client?.contextName) {
      _query?.cancel();
      _busy = false;
      _cancelled = false;
      _error = '';
      _completed = _total = 0;
      _clearReports();
      _plan = [];
      _client = null;
      if (widget.client?.runtime == MachineContainerRuntime.kubernetes) {
        _namespace.text = widget.client!.scope;
      }
      if (!widget.connecting && (widget.kubernetes || widget.client != null)) {
        refresh(replace: true);
      }
    }
  }

  @override
  void dispose() {
    _query?.cancel();
    _namespace.dispose();
    super.dispose();
  }

  void _clearReports() {
    _reports.clear();
    _outputs.clear();
    _issues.clear();
    _updated.clear();
  }

  Future<void> refresh({bool replace = false, String? only}) async {
    if (!mounted || widget.connecting || _busy && !replace) return;
    _query?.cancel();
    final query = _query = widget.beginQuery();
    final watch = Stopwatch()..start();
    bool stopped() => !mounted || query.cancelled;
    setState(() {
      _busy = true;
      _cancelled = false;
      _completed = _total = 0;
      _error = '';
      if (widget.kubernetes &&
          _client != null &&
          _client!.scope != _namespace.text.trim()) {
        _clearReports();
      }
    });
    Future<String> run(String command) {
      final remaining = machineContainerTelemetryBudget - watch.elapsed;
      if (remaining <= Duration.zero) throw TimeoutException('容器遥测采集总时限已到。');
      final limit = query.timeout < machineContainerTelemetryTimeout
          ? query.timeout
          : machineContainerTelemetryTimeout;
      return query.run(command, timeout: remaining < limit ? remaining : limit);
    }

    try {
      final inherited = widget.client;
      var client = widget.kubernetes
          ? inherited?.runtime == MachineContainerRuntime.kubernetes
                ? inherited!.copyWith(run: run, scope: _namespace.text.trim())
                : MachineContainerClient(
                    runtime: MachineContainerRuntime.kubernetes,
                    run: run,
                    scope: _namespace.text.trim(),
                    windows: widget.windows,
                  )
          : inherited?.copyWith(run: run);
      if (client == null) throw StateError('容器运行时尚未连接。');
      if (widget.kubernetes && client.contextName.isEmpty) {
        try {
          client = await client.resolveContext();
        } catch (error) {
          if (stopped() ||
              widget.windows ||
              inherited?.runtime == MachineContainerRuntime.kubernetes ||
              !RegExp(
                'command not found|not recognized|executable file not found|no such file or directory',
                caseSensitive: false,
              ).hasMatch('$error')) {
            rethrow;
          }
          client = await MachineContainerClient(
            runtime: MachineContainerRuntime.kubernetes,
            run: run,
            scope: _namespace.text.trim(),
            launcher: const ['k3s', 'kubectl'],
          ).resolveContext();
        }
      }
      if (stopped()) return;
      setState(() {
        if (_client != null &&
            (_client!.scope != client!.scope ||
                _client!.contextName != client.contextName)) {
          _clearReports();
        }
        _client = client;
        _plan = client!.telemetryQueries;
      });
      final selected = only == null
          ? _plan
          : _plan.where((item) => item.id == only).toList();
      setState(() => _total = selected.length);
      for (final item in selected) {
        if (stopped()) return;
        if (watch.elapsed >= machineContainerTelemetryBudget) {
          setState(() {
            for (final pending in selected.skipWhile(
              (entry) => entry.id != item.id,
            )) {
              _issues[pending.id] = 'TimeoutException: 容器遥测采集总时限已到。';
            }
          });
          break;
        }
        setState(() => _active = item.id);
        try {
          final output = await client.execute(item.arguments);
          final report = item.parse(output);
          if (stopped()) return;
          setState(() {
            _reports[item.id] = report;
            _outputs[item.id] = output;
            _updated[item.id] = DateTime.now();
            _issues.remove(item.id);
          });
        } catch (error) {
          if (stopped()) return;
          setState(() => _issues[item.id] = '$error');
        } finally {
          if (!stopped()) setState(() => _completed++);
        }
      }
    } catch (error) {
      if (!stopped()) {
        setState(() {
          _error = '$error';
          if (machineMaintenanceCollectionIssue(_error, 'containers') ==
              'kubernetes_context') {
            _clearReports();
            _client = null;
            _plan = [];
          }
        });
      }
    } finally {
      watch.stop();
      if (!stopped()) {
        setState(() {
          _busy = false;
          _active = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context)!;
    final client =
        _client ??
        (widget.kubernetes &&
                widget.client?.runtime != MachineContainerRuntime.kubernetes
            ? null
            : widget.client);
    final busy = widget.connecting || _busy;
    final error = widget.connectionError.isNotEmpty
        ? widget.connectionError
        : _error;
    final warning = error.isNotEmpty || _issues.isNotEmpty;
    final missingContext =
        machineMaintenanceCollectionIssue(error, 'containers') ==
        'kubernetes_context';
    final status = busy
        ? l.maintenanceCollecting
        : _cancelled
        ? l.maintenanceTelemetryCancelled
        : missingContext
        ? l.maintenanceKubernetesContextMissingStatus
        : warning
        ? (_reports.isEmpty
              ? l.maintenanceCollectionFailed
              : l.maintenanceTelemetryPartial)
        : _reports.isNotEmpty
        ? l.maintenanceCollected
        : l.maintenanceTelemetryPending;
    final tone = busy
        ? cs.primary
        : warning
        ? OpenHandStatusColors.warning
        : _reports.isNotEmpty && !_cancelled
        ? OpenHandStatusColors.success
        : cs.onSurfaceVariant;
    final controlHeight = _maintenanceActionHeightOf(context);
    final actionStyle = _maintenanceActionButtonStyle(context);
    final inputBorder = OutlineInputBorder(
      borderRadius: kOpenHandBorderRadius8,
      borderSide: BorderSide(color: cs.outlineVariant),
    );
    void reload() {
      if (!widget.kubernetes && widget.client == null) {
        widget.onReconnect?.call();
      } else {
        refresh(replace: true);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MaintenanceCard(
          key: const ValueKey('container-telemetry-summary'),
          title: widget.kubernetes
              ? l.maintenanceTelemetryKubernetesOverview
              : l.maintenanceTelemetryRuntimeOverview,
          icon: widget.kubernetes
              ? Icons.hub_outlined
              : Icons.monitor_heart_outlined,
          trailing: _MaintenanceStatus(label: status, color: tone),
          wrapHeader: true,
          scrollBody: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: _maintenanceGridGap,
            children: [
              Text(
                widget.kubernetes
                    ? l.maintenanceTelemetryKubernetesHelp
                    : l.maintenanceTelemetryRuntimeHelp,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              LayoutBuilder(
                builder: (context, bounds) {
                  final scale =
                      MediaQuery.textScalerOf(
                        context,
                      ).scale(_maintenanceFormFontSize) /
                      _maintenanceFormFontSize;
                  final width = bounds.maxWidth < 480 * scale
                      ? bounds.maxWidth
                      : (bounds.maxWidth - _maintenanceGridGap) / 2;
                  return Wrap(
                    spacing: _maintenanceGridGap,
                    runSpacing: _maintenanceGridGap,
                    children: [
                      for (final field in [
                        (
                          l.maintenanceContainerRuntime,
                          client?.runtime.label ??
                              (widget.kubernetes
                                  ? MachineContainerRuntime.kubernetes.label
                                  : '—'),
                          Icons.dns_outlined,
                        ),
                        (
                          l.maintenanceContainerContext,
                          client?.contextName.isNotEmpty == true
                              ? client!.contextName
                              : missingContext
                              ? l.maintenanceKubernetesContextMissingStatus
                              : l.maintenanceContainerNotConnected,
                          Icons.link_rounded,
                        ),
                      ])
                        SizedBox(
                          width: width,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerLow,
                              borderRadius: kOpenHandBorderRadius8,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Icon(field.$3, size: 18, color: cs.primary),
                                  kOpenHandHGap12,
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          field.$1,
                                          style: theme.textTheme.labelMedium
                                              ?.copyWith(
                                                color: cs.onSurfaceVariant,
                                              ),
                                        ),
                                        kOpenHandGap4,
                                        Tooltip(
                                          message: field.$2,
                                          child: Text(
                                            field.$2,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
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
                        ),
                    ],
                  );
                },
              ),
              LayoutBuilder(
                builder: (context, bounds) => Wrap(
                  spacing: _maintenanceGridGap,
                  runSpacing: _maintenanceGridGap,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (widget.kubernetes)
                      SizedBox(
                        width: math.min(bounds.maxWidth, 320),
                        height: controlHeight,
                        child: TextField(
                          controller: _namespace,
                          enabled: !widget.connecting,
                          style: theme.textTheme.bodySmall,
                          decoration: InputDecoration(
                            hintText: l.maintenanceContainerScopeAll,
                            isDense: false,
                            isCollapsed: false,
                            constraints: BoxConstraints.tightFor(
                              height: controlHeight,
                            ),
                            border: inputBorder,
                            enabledBorder: inputBorder,
                            focusedBorder: inputBorder.copyWith(
                              borderSide: BorderSide(
                                color: cs.primary,
                                width: 1.5,
                              ),
                            ),
                            filled: true,
                            fillColor: cs.surfaceContainerLow,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                            ),
                            prefixIconConstraints: const BoxConstraints(
                              minWidth: 36,
                            ),
                            prefixIcon: const Icon(
                              Icons.filter_alt_outlined,
                              size: 18,
                            ),
                          ),
                          onSubmitted: (_) => reload(),
                        ),
                      ),
                    FilledButton.tonalIcon(
                      key: const ValueKey('telemetry-refresh'),
                      style: actionStyle,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(l.maintenanceRefreshDetails),
                      onPressed: busy ? null : reload,
                    ),
                    if (busy)
                      FilledButton.tonalIcon(
                        key: const ValueKey('telemetry-cancel'),
                        style: actionStyle,
                        icon: const Icon(Icons.stop_rounded, size: 18),
                        label: Text(l.commonCancel),
                        onPressed: () {
                          if (widget.connecting) {
                            widget.onCancelConnection?.call();
                          } else {
                            _query?.cancel();
                          }
                          setState(() {
                            _busy = false;
                            _active = '';
                            _cancelled = true;
                          });
                        },
                      ),
                    if (!busy && _total > 0)
                      Text(
                        l.maintenanceTelemetryCompleted(_completed, _total),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (busy)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: kOpenHandBorderRadius8,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: _maintenanceGridGap,
                      children: [
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          spacing: _maintenanceGridGap,
                          runSpacing: 8,
                          children: [
                            Text(
                              widget.connecting
                                  ? l.maintenanceTelemetryConnecting
                                  : busy
                                  ? maintenanceLabel(
                                      context,
                                      _plan
                                              .where(
                                                (item) => item.id == _active,
                                              )
                                              .firstOrNull
                                              ?.label ??
                                          '正在连接',
                                    )
                                  : status,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: tone,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (_total > 0)
                              Text(
                                l.maintenanceTelemetryCompleted(
                                  _completed,
                                  _total,
                                ),
                                style: theme.textTheme.bodySmall,
                              ),
                          ],
                        ),
                        if (busy)
                          LinearProgressIndicator(
                            value: _total > 0 ? _completed / _total : null,
                            color: cs.primary,
                            backgroundColor: cs.surfaceContainerHighest,
                            borderRadius: kOpenHandBorderRadius8,
                            minHeight: 4,
                          ),
                      ],
                    ),
                  ),
                ),
              if (error.isNotEmpty) _ContainerTelemetryIssue(text: error),
            ],
          ),
        ),
        for (final item in _plan) ...[
          const SizedBox(height: _maintenanceGridGap),
          _MaintenanceSection(
            key: ValueKey('telemetry-${item.id}'),
            title: maintenanceLabel(context, item.label),
            icon: switch (item.id) {
              'metrics' ||
              'node_metrics' ||
              'pod_metrics' => Icons.monitor_heart_outlined,
              'disk' || 'storage' || 'storage_claims' => Icons.storage_rounded,
              'events' => Icons.warning_amber_rounded,
              'networks' || 'services' => Icons.hub_outlined,
              _ => Icons.dns_outlined,
            },
            initiallyExpanded: const {
              'metadata',
              'readiness',
              'nodes',
              'node_metrics',
              'metrics',
            }.contains(item.id),
            accent: _issues.containsKey(item.id)
                ? OpenHandStatusColors.warning
                : cs.primary,
            subtitle: [
              if (_updated[item.id] case final updated?)
                '${maintenanceLabel(context, '采样时间')} · ${MaterialLocalizations.of(context).formatShortDate(updated)} ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(updated), alwaysUse24HourFormat: true)}',
              if (_issues.containsKey(item.id) && _reports.containsKey(item.id))
                maintenanceLabel(context, '刷新失败，当前显示上次成功结果'),
            ].join(' · '),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: _maintenanceGridGap,
              children: [
                if (_issues[item.id] case final issue?)
                  if (const {'node_metrics', 'pod_metrics'}.contains(item.id) &&
                      RegExp(
                        'metrics API|metrics.k8s.io|metrics-server',
                        caseSensitive: false,
                      ).hasMatch(issue))
                    _MaintenanceEmptyHint(
                      message: AppLocalizations.of(
                        context,
                      )!.maintenanceTelemetryMetricsUnavailable,
                      icon: Icons.monitor_heart_outlined,
                    )
                  else
                    _ContainerTelemetryIssue(text: issue),
                if (_reports[item.id] case final report?)
                  if (item.id == 'readiness')
                    const _MaintenanceStatus(
                      label: '就绪',
                      color: OpenHandStatusColors.success,
                    )
                  else if (report.fields)
                    _MaintenanceTable(
                      headers: const ['名称', '数值'],
                      maxBodyHeight: 420,
                      paginate: report.rows.length > 20,
                      rows: [
                        for (final row in report.rows)
                          OpenHandOperationalRankRow(
                            rowKey: row.first,
                            value: 0,
                            cells: [
                              maintenanceDetailLabel(context, row.first),
                              _maintenanceReadoutValue(
                                context,
                                row.first,
                                row.last,
                              ),
                            ],
                          ),
                      ],
                    )
                  else
                    _MaintenanceReadout(
                      report: report,
                      section: 'container_metrics',
                    )
                else if (!_issues.containsKey(item.id))
                  _MaintenanceEmptyHint(
                    message: maintenanceLabel(context, '等待采样'),
                  ),
                if (_outputs.containsKey(item.id) ||
                    _issues.containsKey(item.id))
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: _maintenanceGridGap,
                    runSpacing: _maintenanceGridGap,
                    children: [
                      if (_outputs.containsKey(item.id))
                        FilledButton.tonalIcon(
                          style: _maintenanceActionButtonStyle(context),
                          icon: const Icon(Icons.data_object_rounded, size: 16),
                          label: Text(maintenanceLabel(context, '完整元数据')),
                          onPressed: () async {
                            final output = _outputs[item.id]!;
                            await showAnimatedDialog<void>(
                              context: context,
                              builder: (_) => _ContainerReportDialog(
                                title: maintenanceLabel(context, item.label),
                                section: 'container_metadata',
                                load: () async => output,
                              ),
                            );
                          },
                        ),
                      if (_issues.containsKey(item.id))
                        FilledButton.tonalIcon(
                          style: _maintenanceActionButtonStyle(context),
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: Text(
                            AppLocalizations.of(
                              context,
                            )!.maintenanceImageTagRetry,
                          ),
                          onPressed: _busy
                              ? null
                              : () => refresh(only: item.id),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ContainerTelemetryIssue extends StatelessWidget {
  const _ContainerTelemetryIssue({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context)!;
    final issue = text.contains('TimeoutException')
        ? 'timeout'
        : machineMaintenanceCollectionIssue(text, 'containers');
    final (title, help) = switch (issue) {
      'kubernetes_context' => (
        l.maintenanceKubernetesContextMissing,
        l.maintenanceKubernetesContextMissingHelp,
      ),
      'permission' => (
        l.maintenanceContainerPermissionTitle,
        l.maintenanceContainerPermissionHelp,
      ),
      'timeout' => (
        l.maintenanceContainerTimeoutTitle,
        l.maintenanceContainerTimeoutHelp,
      ),
      'missing' => (
        l.maintenanceContainerMissingTitle,
        l.maintenanceContainerMissingHelp,
      ),
      'connection' => (
        l.maintenanceContainerUnavailableTitle,
        l.maintenanceContainerRuntimeHelp,
      ),
      _ => (l.maintenanceContainerDataTitle, l.maintenanceContainerDataHelp),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: _maintenanceGridGap,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: kOpenHandBorderRadius8,
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 20,
                  color: OpenHandStatusColors.warning,
                ),
                kOpenHandHGap12,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      kOpenHandGap6,
                      Text(
                        help,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (issue != 'kubernetes_context')
          _MaintenanceSection(
            title: l.maintenanceDiagnosticItems,
            icon: Icons.manage_search_rounded,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: SingleChildScrollView(
                child: SelectableText(text, style: theme.textTheme.bodySmall),
              ),
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
    this.isCancelled,
  });
  final String section;
  final String title;
  final Future<String> Function() load;
  final bool Function()? isCancelled;
  @override
  State<_ContainerReportDialog> createState() => _ContainerReportDialogState();
}

class _ContainerReportDialogState extends State<_ContainerReportDialog> {
  final _logs = MachineLogBuffer();
  String _text = '', _error = '';
  bool _busy = false, _automatic = false, _loaded = false;
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
    if (_busy || !mounted || (widget.isCancelled?.call() ?? false)) return;
    _timer?.cancel();
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final text = await widget.load();
      if (mounted && !(widget.isCancelled?.call() ?? false)) {
        setState(() {
          _loaded = true;
          if (widget.section == 'logs') {
            _logs.append(text, plainText: true);
            _text = _logs.entries.map((entry) => entry.message).join('\n');
          } else {
            _text = text;
          }
        });
      }
    } catch (error) {
      if (mounted && !(widget.isCancelled?.call() ?? false)) {
        setState(() {
          _error = maintenanceContainerOperationError(context, error);
          _automatic = false;
        });
      }
    } finally {
      if (mounted && !(widget.isCancelled?.call() ?? false)) {
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
    maxHeight:
        MediaQuery.sizeOf(context).height *
        (widget.section == 'logs' ? _containerLogDialogHeightFraction : .85),
    child: SizedBox(
      width: math.min(1000, MediaQuery.sizeOf(context).width * .9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final actions = <Widget>[
                if (widget.section == 'logs')
                  _MachineTerminalIconButton(
                    tooltip: AppLocalizations.of(context)!.maintenanceLogClear,
                    icon: Icons.cleaning_services_rounded,
                    onPressed: _busy || _logs.entries.isEmpty
                        ? null
                        : () => setState(() {
                            _logs.clear();
                            _text = '';
                          }),
                  ),
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
              ];
              final compact =
                  constraints.maxWidth <
                  MediaQuery.textScalerOf(context).scale(440);
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MachineTerminalDialogHeader(
                    icon: Icons.inventory_2_outlined,
                    title: widget.title,
                    onClose: () => Navigator.pop(context),
                    trailingActions: compact ? const [] : actions,
                  ),
                  if (compact)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 12, 10),
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: actions,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          if (_busy) const LinearProgressIndicator(),
          if (widget.section == 'container_image' &&
              _loaded &&
              _error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: _MaintenanceNotice(message: _error, error: true),
            ),
          Flexible(
            child: _busy && !_loaded
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: _MaintenanceEmptyHint(
                        icon: Icons.downloading_rounded,
                        message: maintenanceLabel(context, '正在读取详情…'),
                      ),
                    ),
                  )
                : Padding(
                    padding: _maintenanceDetailPadding,
                    child: widget.section == 'logs' && _error.isEmpty
                        ? SizedBox(
                            height:
                                MediaQuery.sizeOf(context).height *
                                _containerLogBodyHeightFraction,
                            child: OpenHandConsoleFrame(
                              title: maintenanceLabel(context, '最近日志'),
                              expandBody: true,
                              child: _text.isEmpty
                                  ? OpenHandOperationalEmptyState(
                                      textColor: OpenHandConsolePalette.text,
                                      surfaceColor:
                                          OpenHandConsolePalette.deepSurface,
                                      icon: Icons.article_outlined,
                                      color: OpenHandConsolePalette.notice,
                                      message: AppLocalizations.of(
                                        context,
                                      )!.maintenanceLogEmpty,
                                    )
                                  : OpenHandConsoleText(
                                      title: maintenanceLabel(context, '最近日志'),
                                      text: _text,
                                      framed: false,
                                      maxHeight: double.infinity,
                                    ),
                            ),
                          )
                        : SingleChildScrollView(
                            child:
                                widget.section == 'container_image' &&
                                    (_error.isEmpty || _loaded)
                                ? _ContainerImageReadout(text: _text)
                                : _MaintenanceReadout(
                                    text: _error.isEmpty ? _text : _error,
                                    section: _error.isEmpty
                                        ? widget.section
                                        : 'containers',
                                    logMaxHeight:
                                        MediaQuery.sizeOf(context).height *
                                        _containerLogBodyHeightFraction,
                                  ),
                          ),
                  ),
          ),
        ],
      ),
    ),
  );
}

class _ContainerImageReadout extends StatelessWidget {
  const _ContainerImageReadout({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final report = jsonDecode(text) as Map<String, dynamic>;
    final image = report['image'] as Map<String, dynamic>;
    final details = image['status'] as Map? ?? image;
    final layers = (report['history'] as List? ?? const []).cast<Map>();
    final l = AppLocalizations.of(context)!;
    String value(dynamic raw) => raw is List ? raw.join(' · ') : '${raw ?? ''}';
    String sizeValue(dynamic raw) {
      final bytes = raw is num ? raw : num.tryParse(value(raw));
      return bytes == null
          ? value(raw)
          : formatLocalizedByteSizeOf(context, bytes);
    }

    final size = details['Size'] ?? details['size'];
    final created = value(details['Created'] ?? details['created']);
    return _MaintenanceAnimatedColumn(
      spacing: _maintenanceGridGap,
      children: [
        _MaintenanceCard(
          title: l.maintenanceImageMetadata,
          icon: Icons.layers_outlined,
          scrollBody: false,
          child: _ContainerImageFacts(
            values: {
              '镜像标识': value(
                details['Id'] ??
                    details['id'] ??
                    details['ImageID'] ??
                    report['reference'],
              ),
              '镜像标签': value(
                details['RepoTags'] ?? details['repoTags'] ?? details['Image'],
              ),
              if (details['RepoDigests'] != null ||
                  details['repoDigests'] != null)
                '镜像摘要': value(details['RepoDigests'] ?? details['repoDigests']),
              if (size != null) '镜像大小': sizeValue(size),
              if (created.isNotEmpty)
                '创建时间':
                    machineMaintenanceTimestamp(created, allowEpoch: true) ??
                    created,
              if (details['Os'] != null)
                '操作系统': _containerImageOs(context, details['Os']),
              if (details['Architecture'] != null)
                '架构': _containerImageArchitecture(
                  context,
                  details['Architecture'],
                ),
              if (details['nodeName'] != null) '节点': value(details['nodeName']),
              if (details['imagePullPolicy'] != null)
                '镜像拉取策略': value(details['imagePullPolicy']),
            },
          ),
        ),
        if (report['referenceOnly'] == true)
          _MaintenanceNotice(message: l.maintenanceImageReferenceOnly),
        if (report['historyError'] != null)
          _MaintenanceNotice(message: l.maintenanceImageHistoryUnavailable),
        if (report['historyLimited'] == true)
          _MaintenanceNotice(message: l.maintenanceImageHistoryLimited),
        if (report.containsKey('history'))
          _MaintenanceCard(
            title: l.maintenanceImageLayers,
            icon: Icons.account_tree_outlined,
            scrollBody: false,
            child: _MaintenanceTable(
              headers: const ['构建指令', '层大小', '创建时间'],
              maxBodyHeight: 360,
              rows: [
                for (var index = 0; index < layers.length; index++)
                  OpenHandOperationalRankRow(
                    rowKey: index,
                    value: 0,
                    data: layers[index],
                    cells: [
                      value(
                        layers[index]['CreatedBy'] ??
                            layers[index]['createdBy'],
                      ),
                      sizeValue(layers[index]['Size'] ?? layers[index]['size']),
                      value(
                        layers[index]['CreatedAt'] ??
                            layers[index]['Created'] ??
                            layers[index]['created'],
                      ),
                    ].map((v) => v.isEmpty ? '—' : v).toList(),
                  ),
              ],
              onRowTap: (row) => showAnimatedDialog<void>(
                context: context,
                builder: (_) => _ContainerReportDialog(
                  title: l.maintenanceImageLayers,
                  load: () async => jsonEncode(row.data),
                ),
              ),
            ),
          ),
        _MaintenanceSection(
          title: maintenanceLabel(context, '原始输出'),
          icon: Icons.data_object_rounded,
          child: _MaintenanceReadout(
            text: jsonEncode(image),
            section: 'container_image',
          ),
        ),
        if (report['historyError'] != null)
          _MaintenanceSection(
            title: maintenanceLabel(context, '诊断说明'),
            icon: Icons.info_outline_rounded,
            child: _MaintenanceReadout(
              text: '${report['historyError']}',
              section: 'containers',
            ),
          ),
      ],
    );
  }
}

class _ContainerInteractiveTerminal extends StatefulWidget {
  const _ContainerInteractiveTerminal({
    required this.title,
    required this.sessionId,
    required this.terminalId,
    required this.command,
    required this.readyMarker,
    required this.shell,
  });
  final String title, sessionId, terminalId, command, readyMarker;
  final MachineTerminalCommandShell shell;
  @override
  State<_ContainerInteractiveTerminal> createState() =>
      _ContainerInteractiveTerminalState();
}

enum _ContainerTerminalPhase { connecting, connected, closing, exited, failed }

class _ContainerInteractiveTerminalState
    extends State<_ContainerInteractiveTerminal> {
  final _controller = TerminalController();
  final _focusNode = FocusNode(debugLabel: '容器终端');
  MachineTerminalSession? _session;
  MachineTerminalService? _service;
  ({int columns, int rows})? _before;
  Future<void>? _connection;
  _ContainerTerminalPhase _phase = _ContainerTerminalPhase.connecting;
  bool _active = true, _cancelled = false, _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_cancelled) _connection = _connect();
    });
  }

  Future<void> _connect() async {
    final service = context.read<MachineTerminalService>();
    _service = service;
    final session = service.terminalFor(widget.sessionId, widget.terminalId);
    if (session == null) {
      setState(() {
        _active = false;
        _phase = _ContainerTerminalPhase.failed;
        _error = '原终端已关闭，请重新连接。';
      });
      return;
    }
    _before = (
      columns: session.terminal.viewWidth,
      rows: session.terminal.viewHeight,
    );
    setState(() => _session = session);
    try {
      final result = await service.executeCommand(
        sessionId: widget.sessionId,
        terminalId: widget.terminalId,
        command: widget.command,
        commandShell: widget.shell,
        timeout: _containerTerminalSessionTimeout,
        startIfNeeded: false,
        recordHistory: false,
        isCancelled: () => _cancelled,
        onOutput: (output) {
          // 容器内部握手后才开放输入，宿主回显和空提示符不参与就绪判断。
          if (mounted &&
              !_cancelled &&
              output.contains(widget.readyMarker) &&
              _phase == _ContainerTerminalPhase.connecting) {
            setState(() => _phase = _ContainerTerminalPhase.connected);
            _focusNode.requestFocus();
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _phase = result.succeeded
            ? _ContainerTerminalPhase.exited
            : _ContainerTerminalPhase.failed;
        _error = result.succeeded
            ? null
            : result.timedOut
            ? 'timeout'
            : result.error ?? '容器终端连接结束，请查看终端输出。';
      });
    } on MachineTerminalUploadCancelled {
      if (mounted) setState(() => _phase = _ContainerTerminalPhase.exited);
    } catch (error) {
      if (mounted) {
        setState(() {
          _phase = _ContainerTerminalPhase.failed;
          _error = '$error';
        });
      }
    } finally {
      _active = false;
    }
  }

  Future<void> _send(String data) async {
    if (!_active || _cancelled || _sending || _session == null) return;
    setState(() => _sending = true);
    try {
      await _service!.writeInput(
        sessionId: widget.sessionId,
        terminalId: widget.terminalId,
        data: data,
        startIfNeeded: false,
      );
      if (mounted) _focusNode.requestFocus();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _exit({bool closeDialog = true}) async {
    if (_phase == _ContainerTerminalPhase.closing) return;
    if (_connection == null) {
      _cancelled = true;
      _active = false;
    }
    if (!_active) {
      if (closeDialog) Navigator.pop(context);
      return;
    }
    final connecting = _phase == _ContainerTerminalPhase.connecting;
    setState(() {
      _phase = _ContainerTerminalPhase.closing;
      _error = null;
    });
    if (connecting) {
      _cancelled = true;
    } else {
      await _send('\x04');
    }
    try {
      await _connection?.timeout(_containerTerminalExitTimeout);
      if (mounted && closeDialog && !_active) Navigator.pop(context);
    } on TimeoutException {
      // 前台程序可能忽略 EOF；保留会话供用户中断，禁止继续发送控制字符到宿主 Shell。
      if (mounted) {
        setState(() {
          _phase = connecting
              ? _ContainerTerminalPhase.closing
              : _ContainerTerminalPhase.connected;
          _error = 'exitPending';
        });
      }
    }
  }

  @override
  void dispose() {
    _cancelled = true;
    _focusNode.dispose();
    _controller.dispose();
    final before = _before;
    final service = _service;
    if (before != null &&
        service != null &&
        identical(
          service.terminalFor(widget.sessionId, widget.terminalId),
          _session,
        )) {
      unawaited(
        service
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
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ready = _phase == _ContainerTerminalPhase.connected;
    final (status, tone) = switch (_phase) {
      _ContainerTerminalPhase.connecting => (
        l.maintenanceContainerConnecting,
        cs.tertiary,
      ),
      _ContainerTerminalPhase.connected => (
        l.maintenanceMetricConnected,
        OpenHandStatusColors.success,
      ),
      _ContainerTerminalPhase.closing => (
        l.maintenanceContainerDisconnecting,
        OpenHandStatusColors.warning,
      ),
      _ContainerTerminalPhase.exited => (
        l.maintenanceExited,
        cs.onSurfaceVariant,
      ),
      _ContainerTerminalPhase.failed => (
        l.maintenanceContainerTerminalFailed,
        cs.error,
      ),
    };
    final error = switch (_error) {
      null => '',
      'timeout' => l.maintenanceCommandTimedOut,
      'exitPending' => l.maintenanceContainerExitPending,
      _ => maintenanceLabel(context, _error!),
    };
    final buttonStyle = OutlinedButton.styleFrom(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: cs.surfaceContainerLow,
      foregroundColor: cs.onSurfaceVariant,
      side: BorderSide(color: cs.outlineVariant.withValues(alpha: .55)),
      shape: const RoundedRectangleBorder(borderRadius: kOpenHandBorderRadius8),
      textStyle: theme.textTheme.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      elevation: 0,
    ).copyWith(overlayColor: const WidgetStatePropertyAll(Colors.transparent));
    final toolbar = LayoutBuilder(
      builder: (context, bounds) {
        final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
        final compact = bounds.maxWidth < 560 * scale;
        return Row(
          children: [
            Expanded(
              child: Tooltip(
                message: status,
                child: _MaintenanceStatus(label: status, color: tone),
              ),
            ),
            const SizedBox(width: 12),
            for (final action in [
              (
                label: l.maintenanceContainerInterrupt,
                shortcut: 'Ctrl+C',
                icon: Icons.stop_circle_outlined,
                onPressed: () => _send('\x03'),
              ),
              (
                label: l.maintenanceContainerExit,
                shortcut: 'Ctrl+D',
                icon: Icons.logout_rounded,
                onPressed: () => _exit(closeDialog: false),
              ),
            ]) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: '${action.label} (${action.shortcut})',
                child: SizedBox(
                  width: compact
                      ? _maintenanceControlHeight
                      : _containerTerminalActionWidth * scale,
                  height: _maintenanceControlHeight,
                  child: OutlinedButton(
                    onPressed: ready && !_sending ? action.onPressed : null,
                    style: buttonStyle,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(action.icon, size: 17),
                        if (!compact) ...[
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              action.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
    final terminalPane = AnimatedContainer(
      duration: openHandMotionSettingsOf(
        context,
        OpenHandMotionSettingsScope.dialog,
      ).entranceDuration,
      curve: kOpenHandSwitchInCurve,
      decoration: BoxDecoration(
        color: _session == null && !_active
            ? cs.surfaceContainerLow
            : _machineTerminalBackground,
        borderRadius: kOpenHandBorderRadius14,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .55)),
      ),
      padding: const EdgeInsets.all(1),
      child: ClipRRect(
        borderRadius: kOpenHandBorderRadius14,
        child: _session == null
            ? Center(
                child: _active
                    ? const CircularProgressIndicator(
                        color: OpenHandConsolePalette.notice,
                      )
                    : _MaintenanceEmptyHint(
                        icon: Icons.link_off_rounded,
                        message: error.isEmpty ? status : error,
                      ),
              )
            : _MachineTerminalViewport(
                key: ValueKey(_session),
                session: _session!,
                controller: _controller,
                focusNode: _focusNode,
                readOnly: !ready,
                padding: const EdgeInsets.all(14),
              ),
      ),
    );
    final header = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MachineTerminalDialogHeader(
          icon: Icons.terminal_rounded,
          title: l.maintenanceContainerTerminal,
          subtitle: widget.title,
          onClose: () => unawaited(_exit()),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
          child: toolbar,
        ),
        _MaintenanceAnimatedSize(
          child: error.isEmpty || _session == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                  child: Tooltip(
                    message: error,
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 16, color: tone),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            error,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
    final viewport = MediaQuery.sizeOf(context);
    return PopScope(
      canPop: !_active,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_exit());
      },
      child: buildOpenHandDialog(
        backgroundColor: cs.surface,
        insetPadding: kOpenHandToolDialogInsetPadding,
        width: math.min(kOpenHandDialogWidthPanel, viewport.width * .92),
        height: math.min(kOpenHandDialogHeightFull, viewport.height * .86),
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * .48,
                ),
                child: SingleChildScrollView(child: header),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                  child: terminalPane,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
