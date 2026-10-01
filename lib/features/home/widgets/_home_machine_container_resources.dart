part of '../openhand_home_page.dart';

enum _ContainerResourceAction {
  pull,
  createContainer,
  createVolume,
  removeImage,
  removeVolume,
}

String _containerActionLabel(
  BuildContext context,
  _ContainerResourceAction action,
) {
  final l = AppLocalizations.of(context)!;
  return switch (action) {
    _ContainerResourceAction.pull => l.maintenanceImagePull,
    _ContainerResourceAction.createContainer => l.maintenanceContainerCreate,
    _ContainerResourceAction.createVolume => l.maintenanceVolumeCreate,
    _ContainerResourceAction.removeImage => l.maintenanceImageRemove,
    _ContainerResourceAction.removeVolume => l.maintenanceVolumeRemove,
  };
}

class _MachineContainerResources extends StatefulWidget {
  const _MachineContainerResources({
    super.key,
    required this.client,
    required this.beginQuery,
    required this.kind,
    required this.timeout,
    required this.onOverlayChanged,
    required this.onCreated,
    this.operate,
  });
  final MachineContainerClient client;
  final _ContainerQueryScope Function() beginQuery;
  final MachineContainerResourceKind kind;
  final MachineContainerOperationRunner? operate;
  final Duration timeout;
  final ValueChanged<bool> onOverlayChanged;
  final VoidCallback onCreated;
  @override
  State<_MachineContainerResources> createState() =>
      _MachineContainerResourcesState();
}

class _MachineContainerResourcesState
    extends State<_MachineContainerResources> {
  final _search = TextEditingController();
  List<MachineContainerResource> _resources = [];
  bool _busy = false, _overlay = false, _loaded = false;
  _ContainerQueryScope? _query;
  String _error = '';
  bool get _images => widget.kind == MachineContainerResourceKind.images;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) refresh();
    });
  }

  @override
  void didUpdateWidget(covariant _MachineContainerResources oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind || oldWidget.client != widget.client) {
      _query?.cancel();
      _busy = false;
      _resources = [];
      _loaded = false;
      _error = '';
      _search.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) refresh();
      });
    }
  }

  @override
  void dispose() {
    _query?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    if (_busy || _overlay || !mounted || !widget.client.supportsResources) {
      return;
    }
    final query = _query = widget.beginQuery();
    final client = widget.client.copyWith(run: query.run);
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await for (final resources in client.resources(
        widget.kind,
        isCancelled: () => !mounted || query.cancelled,
      )) {
        if (!mounted || query.cancelled) return;
        setState(() {
          _resources = resources;
          _loaded = true;
        });
      }
    } catch (error) {
      if (mounted && !query.cancelled) {
        setState(
          () => _error = maintenanceContainerOperationError(context, error),
        );
      }
    } finally {
      if (mounted && !query.cancelled) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _open({
    _ContainerResourceAction? action,
    MachineContainerResource? resource,
    bool search = false,
  }) async {
    if (_overlay) return;
    final query = _query = widget.beginQuery();
    final client = widget.client.copyWith(run: query.run);
    Future<String> operate(
      String command, {
      required Duration timeout,
      void Function(String)? onOutput,
      bool Function()? isCancelled,
    }) => query.run(
      command,
      runner: widget.operate,
      timeout: timeout,
      onOutput: onOutput,
      isCancelled: isCancelled,
    );
    setState(() {
      _busy = false;
      _overlay = true;
    });
    widget.onOverlayChanged(true);
    var changed = false;
    try {
      if (search) {
        final result = await showAnimatedDialog<bool>(
          context: context,
          builder: (_) => _ContainerRegistryDialog(
            client: client,
            operate: operate,
            timeout: widget.timeout,
            onChanged: () => changed = true,
          ),
        );
        changed = changed || result == true;
      } else if (action != null) {
        changed =
            await showAnimatedDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (_) => _ContainerResourceFormDialog(
                client: client,
                action: action,
                resource: resource,
                operate: operate,
                timeout: widget.timeout,
              ),
            ) ==
            true;
      } else if (resource != null) {
        await showAnimatedDialog<void>(
          context: context,
          builder: (_) => _ContainerReportDialog(
            title: resource.reference,
            section: _images ? 'container_image' : 'container_details',
            isCancelled: () => query.cancelled,
            load: () => _images
                ? client.inspectImageReference(
                    resource.id,
                    isCancelled: () => !mounted || query.cancelled,
                  )
                : client.volumeDetails(resource.name),
          ),
        );
      }
    } finally {
      query.cancel();
      if (mounted) {
        setState(() => _overlay = false);
        widget.onOverlayChanged(false);
      }
    }
    if (mounted && changed) {
      if (action == _ContainerResourceAction.createContainer) {
        widget.onCreated();
      } else {
        await refresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (!widget.client.supportsResources) {
      return _MaintenanceEmptyHint(message: l.maintenanceResourceUnsupported);
    }
    final theme = Theme.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
    );
    final actionStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(
        Size(0, _maintenanceControlHeight),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
    final query = _search.text.toLowerCase();
    final rows = _resources
        .where(
          (row) => '${row.reference} ${row.id} ${row.driver}'
              .toLowerCase()
              .contains(query),
        )
        .toList();
    return _MaintenanceAnimatedColumn(
      spacing: 12,
      children: [
        _MaintenanceCard(
          title: _images ? l.maintenanceImages : l.maintenanceVolumes,
          icon: _images ? Icons.layers_outlined : Icons.storage_rounded,
          scrollBody: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    height: _maintenanceControlHeight,
                    width: math.min(
                      280,
                      MediaQuery.sizeOf(context).width * .65,
                    ),
                    child: TextField(
                      controller: _search,
                      style: theme.textTheme.bodySmall,
                      decoration: InputDecoration(
                        isDense: false,
                        constraints: const BoxConstraints.tightFor(
                          height: _maintenanceControlHeight,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                        ),
                        border: border,
                        enabledBorder: border,
                        focusedBorder: border.copyWith(
                          borderSide: BorderSide(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        prefixIcon: const Icon(Icons.search_rounded, size: 16),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 34,
                        ),
                        hintText: l.maintenanceResourceFilter,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  if (_images) ...[
                    OutlinedButton.icon(
                      style: actionStyle,
                      onPressed: _overlay || !widget.client.supportsImageSearch
                          ? null
                          : () => _open(search: true),
                      icon: const Icon(Icons.travel_explore_rounded, size: 18),
                      label: Text(l.maintenanceImageSearch),
                    ),
                    FilledButton.tonalIcon(
                      style: actionStyle,
                      onPressed: _overlay
                          ? null
                          : () => _open(action: _ContainerResourceAction.pull),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: Text(l.maintenanceImagePull),
                    ),
                  ] else
                    FilledButton.tonalIcon(
                      style: actionStyle,
                      onPressed: _overlay
                          ? null
                          : () => _open(
                              action: _ContainerResourceAction.createVolume,
                            ),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(l.maintenanceVolumeCreate),
                    ),
                ],
              ),
              if (_busy && !_loaded)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _MaintenanceNotice(message: _error, error: true),
                ),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                _MaintenanceEmptyHint(
                  message: maintenanceLabel(
                    context,
                    _busy && !_loaded
                        ? l.maintenanceLoadingDetails
                        : _error.isNotEmpty && !_loaded
                        ? '当前数据暂不可用'
                        : '当前范围没有记录',
                  ),
                )
              else
                _MaintenanceTable(
                  headers: _images
                      ? [
                          '名称',
                          l.maintenanceImageTag,
                          '镜像标识',
                          '创建时间',
                          '大小',
                          l.maintenanceResourceReferences,
                        ]
                      : [
                          '名称',
                          '创建时间',
                          '大小',
                          l.maintenanceVolumeDriver,
                          l.maintenanceResourceReferences,
                        ],
                  maxBodyHeight: 420,
                  rows: [
                    for (final row in rows)
                      OpenHandOperationalRankRow(
                        rowKey: '${row.id}/${row.reference}',
                        value: 0,
                        data: row,
                        cells: [
                          row.name.isEmpty ? '—' : row.name,
                          if (_images) ...[
                            row.tag.isEmpty ? '—' : row.tag,
                            row.id
                                .replaceFirst('sha256:', '')
                                .substring(
                                  0,
                                  math.min(
                                    12,
                                    row.id.replaceFirst('sha256:', '').length,
                                  ),
                                ),
                          ],
                          machineMaintenanceTimestamp(
                                row.created,
                                allowEpoch: true,
                              ) ??
                              (row.created.isEmpty ? '—' : row.created),
                          row.size.isEmpty ? '—' : row.size,
                          if (!_images) row.driver.isEmpty ? '—' : row.driver,
                          row.references?.toString() ?? '—',
                        ],
                      ),
                  ],
                  onRowTap: _overlay
                      ? null
                      : (row) => _open(
                          resource: row.data as MachineContainerResource,
                        ),
                  rowActions: (row) => {
                    if (!_overlay) ...{
                      if (_images)
                        l.maintenanceContainerCreate: () => _open(
                          action: _ContainerResourceAction.createContainer,
                          resource: row.data as MachineContainerResource,
                        ),
                      _containerActionLabel(
                        context,
                        _images
                            ? _ContainerResourceAction.removeImage
                            : _ContainerResourceAction.removeVolume,
                      ): () => _open(
                        action: _images
                            ? _ContainerResourceAction.removeImage
                            : _ContainerResourceAction.removeVolume,
                        resource: row.data as MachineContainerResource,
                      ),
                    },
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ContainerRegistryDialog extends StatefulWidget {
  const _ContainerRegistryDialog({
    required this.client,
    this.onChanged,
    required this.timeout,
    this.operate,
  });
  final MachineContainerClient client;
  final VoidCallback? onChanged;
  final Duration timeout;
  final MachineContainerOperationRunner? operate;
  @override
  State<_ContainerRegistryDialog> createState() =>
      _ContainerRegistryDialogState();
}

class _ContainerRegistryDialogState extends State<_ContainerRegistryDialog> {
  final _query = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  String _error = '';
  bool _busy = false, _searched = false, _searching = false, _changed = false;
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _searching = true;
      _error = '';
    });
    try {
      final rows = await widget.client.searchImages(_query.text);
      if (mounted) {
        setState(() {
          _results = rows;
          _searched = true;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = maintenanceContainerOperationError(context, error),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _searching = false;
        });
      }
    }
  }

  Future<void> _pull(String image) async {
    if (_busy) return;
    setState(() => _busy = true);
    final changed = await showAnimatedDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ContainerResourceFormDialog(
        client: widget.client,
        action: _ContainerResourceAction.pull,
        image: image,
        operate: widget.operate,
        timeout: widget.timeout,
      ),
    );
    if (changed == true) widget.onChanged?.call();
    if (mounted) {
      setState(() {
        _busy = false;
        _changed = _changed || changed == true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return PopScope(
      canPop: !_busy,
      child: buildOpenHandDialog(
        maxHeight: MediaQuery.sizeOf(context).height * .9,
        child: SizedBox(
          width: 920,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MachineTerminalDialogHeader(
                icon: Icons.travel_explore_rounded,
                title: l.maintenanceImageSearch,
                onClose: () => Navigator.pop(context, _changed),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: _maintenanceDetailPadding,
                  child: _MaintenanceAnimatedColumn(
                    spacing: 12,
                    children: [
                      Text(
                        l.maintenanceImageSearchHelp,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      TextField(
                        controller: _query,
                        enabled: !_busy,
                        onSubmitted: (_) => _search(),
                        decoration: InputDecoration(
                          labelText: l.maintenanceImageQuery,
                          suffixIcon: IconButton(
                            onPressed: _busy ? null : _search,
                            tooltip: l.maintenanceImageSearch,
                            icon: const Icon(Icons.search_rounded),
                          ),
                        ),
                      ),
                      if (_searching)
                        const LinearProgressIndicator(minHeight: 2),
                      if (_error.isNotEmpty)
                        _MaintenanceNotice(message: _error, error: true),
                      if (_searched && _results.isEmpty)
                        _MaintenanceEmptyHint(
                          message: maintenanceLabel(context, '当前范围没有记录'),
                        ),
                      if (_results.isNotEmpty)
                        _MaintenanceTable(
                          headers: [
                            '名称',
                            '描述',
                            l.maintenanceImageStars,
                            l.maintenanceImageOfficial,
                          ],
                          maxBodyHeight: 400,
                          rows: [
                            for (final row in _results)
                              OpenHandOperationalRankRow(
                                value: 0,
                                data: row,
                                rowKey: row['Name'] ?? row['name'],
                                cells: [
                                  '${row['Name'] ?? row['name'] ?? ''}',
                                  '${row['Description'] ?? row['description'] ?? ''}',
                                  '${row['StarCount'] ?? row['Stars'] ?? row['stars'] ?? '—'}',
                                  row['IsOfficial'] == true ||
                                          row['IsOfficial'] == '[OK]' ||
                                          row['Official'] == '[OK]' ||
                                          row['is_official'] == true
                                      ? l.maintenanceHealthParsedYes
                                      : '—',
                                ],
                              ),
                          ],
                          rowActions: (row) => {
                            if (!_busy)
                              l.maintenanceImagePull: () => _pull(
                                '${(row.data as Map)['Name'] ?? (row.data as Map)['name'] ?? ''}',
                              ),
                          },
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
  }
}

class _ContainerResourceFormDialog extends StatefulWidget {
  const _ContainerResourceFormDialog({
    required this.client,
    required this.action,
    required this.timeout,
    this.operate,
    this.resource,
    this.image = '',
  });
  final MachineContainerClient client;
  final _ContainerResourceAction action;
  final Duration timeout;
  final MachineContainerOperationRunner? operate;
  final MachineContainerResource? resource;
  final String image;
  @override
  State<_ContainerResourceFormDialog> createState() =>
      _ContainerResourceFormDialogState();
}

class _ContainerResourceFormDialogState
    extends State<_ContainerResourceFormDialog> {
  final _fields = <String, TextEditingController>{};
  final _ports = <Map<String, String>>[],
      _environment = <Map<String, String>>[],
      _mounts = <Map<String, String>>[],
      _options = <Map<String, String>>[],
      _labels = <Map<String, String>>[];
  bool _busy = false,
      _cancelled = false,
      _completed = false,
      _uncertain = false,
      _start = true;
  String _error = '', _output = '', _pendingOutput = '', _restart = 'no';
  late int _timeout;
  Timer? _outputTimer;
  bool get _remove =>
      widget.action == _ContainerResourceAction.removeImage ||
      widget.action == _ContainerResourceAction.removeVolume;
  TextEditingController _controller(String key) =>
      _fields.putIfAbsent(key, TextEditingController.new);
  String _value(String key) => _fields[key]?.text ?? '';
  @override
  void initState() {
    super.initState();
    _timeout = widget.timeout.inSeconds;
    _controller('image').text = widget.image.isNotEmpty
        ? widget.image
        : widget.resource?.reference ?? '';
  }

  @override
  void dispose() {
    _cancelled = true;
    _outputTimer?.cancel();
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Map<String, String> _pairs(List<Map<String, String>> rows) {
    final values = <String, String>{};
    for (final row in rows) {
      final key = (row['key'] ?? '').trim();
      if (key.isEmpty || values.containsKey(key)) {
        throw const MachineContainerConfigException('form', '参数');
      }
      values[key] = row['value'] ?? '';
    }
    return values;
  }

  void _receive(String text) {
    _pendingOutput = text.length > machineContainerOperationOutputLimit
        ? text.substring(text.length - machineContainerOperationOutputLimit)
        : text;
    _outputTimer ??= startSafeTimer(const Duration(milliseconds: 100), () {
      _outputTimer = null;
      if (mounted) setState(() => _output = _pendingOutput);
    });
  }

  Future<void> _submit() async {
    if (_busy || _completed || _uncertain) return;
    setState(() {
      _error = '';
      _output = '';
    });
    late List<String> args;
    try {
      args = switch (widget.action) {
        _ContainerResourceAction.pull => widget.client.pullArguments(
          _value('image'),
        ),
        _ContainerResourceAction.removeImage =>
          widget.client.removeResourceArguments(
            MachineContainerResourceKind.images,
            widget.resource!,
          ),
        _ContainerResourceAction.removeVolume =>
          widget.client.removeResourceArguments(
            MachineContainerResourceKind.volumes,
            widget.resource!,
          ),
        _ContainerResourceAction.createVolume =>
          widget.client.createVolumeArguments(
            _value('name'),
            driver: _value('driver'),
            labels: _pairs(_labels),
            options: _pairs(_options),
          ),
        _ContainerResourceAction.createContainer => MachineContainerCreateSpec(
          image: _value('image'),
          name: _value('name'),
          start: _start,
          ports: _ports,
          environment: _pairs(_environment),
          mounts: _mounts,
          restart: _restart,
          network: _value('network'),
          user: _value('user'),
          directory: _value('directory'),
          entrypoint: _value('entrypoint'),
          arguments: _value('arguments').isEmpty
              ? []
              : _value('arguments')
                    .split(RegExp(r'\r?\n'))
                    .where((value) => value.isNotEmpty)
                    .toList(),
          cpus: _value('cpus'),
          memory: _value('memory'),
        ).commandArguments(),
      };
    } catch (error) {
      setState(
        () => _error = maintenanceContainerOperationError(context, error),
      );
      return;
    }
    setState(() {
      _busy = true;
      _cancelled = false;
    });
    try {
      final result = widget.operate == null
          ? await widget.client.execute(args)
          : await widget.operate!(
              widget.client.command(args),
              timeout: Duration(seconds: _timeout),
              onOutput: _receive,
              isCancelled: () => !mounted || _cancelled,
            );
      if (!mounted) return;
      _outputTimer?.cancel();
      _outputTimer = null;
      setState(() {
        _output = result.length > machineContainerOperationOutputLimit
            ? result.substring(
                result.length - machineContainerOperationOutputLimit,
              )
            : result;
        _completed = !_cancelled;
        _uncertain = _cancelled;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _uncertain = true;
          _error = _cancelled
              ? ''
              : maintenanceContainerOperationError(context, error);
        });
      }
    } finally {
      _outputTimer?.cancel();
      _outputTimer = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _decoration(
    String label, {
    String? hint,
    bool multiline = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: cs.outlineVariant),
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      alignLabelWithHint: multiline,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: border,
      enabledBorder: border,
      disabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: cs.primary, width: 1.5),
      ),
    );
  }

  Widget _field(String key, String label, {String? hint, int lines = 1}) =>
      TextField(
        controller: _controller(key),
        enabled: !_busy && !_completed && !_uncertain,
        minLines: lines,
        maxLines: lines,
        decoration: _decoration(label, hint: hint, multiline: lines > 1),
      );

  Widget _rows(
    String title,
    List<Map<String, String>> rows,
    Map<String, String> fields, {
    bool ports = false,
    bool mounts = false,
  }) {
    final l = AppLocalizations.of(context)!;
    return _MaintenanceSection(
      title: title,
      icon: mounts
          ? Icons.folder_open_rounded
          : ports
          ? Icons.lan_outlined
          : Icons.tune_rounded,
      initiallyExpanded: rows.isNotEmpty,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final row in rows)
            Padding(
              key: ObjectKey(row),
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    _MaintenanceGrid(
                      minWidth: 180,
                      maxColumns: ports ? 3 : 2,
                      children: [
                        for (final field in fields.entries)
                          TextFormField(
                            initialValue: row[field.key] ?? '',
                            enabled: !_busy && !_completed && !_uncertain,
                            onChanged: (value) => row[field.key] = value,
                            decoration: _decoration(field.value),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (ports || mounts)
                          _MaintenanceToolbarMenu<String>(
                            label: ports
                                ? row['protocol'] ?? 'tcp'
                                : row['type'] == 'bind'
                                ? l.maintenanceBindMount
                                : l.maintenanceVolumes,
                            tooltip: ports ? '协议' : '类型',
                            enabled: !_busy && !_completed && !_uncertain,
                            value:
                                row[ports ? 'protocol' : 'type'] ??
                                (ports ? 'tcp' : 'volume'),
                            items: {
                              for (final type
                                  in ports
                                      ? ['tcp', 'udp', 'sctp']
                                      : ['volume', 'bind'])
                                type: ports
                                    ? type
                                    : type == 'volume'
                                    ? l.maintenanceVolumes
                                    : l.maintenanceBindMount,
                            },
                            onSelected: (value) => setState(
                              () => row[ports ? 'protocol' : 'type'] = value,
                            ),
                          ),
                        if (mounts)
                          FilterChip(
                            label: Text(l.maintenanceReadOnlyMount),
                            selected: row['readonly'] == 'true',
                            onSelected: _busy || _completed || _uncertain
                                ? null
                                : (value) => setState(
                                    () => row['readonly'] = '$value',
                                  ),
                          ),
                        IconButton(
                          onPressed: _busy || _completed || _uncertain
                              ? null
                              : () => setState(() => rows.remove(row)),
                          tooltip: l.commonDelete,
                          icon: const Icon(Icons.remove_circle_outline_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed:
                  _busy ||
                      _completed ||
                      _uncertain ||
                      rows.length >= machineContainerFormRowLimit
                  ? null
                  : () => setState(
                      () => rows.add({if (ports) 'address': '127.0.0.1'}),
                    ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(l.maintenanceResourceAddRow),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final create = widget.action == _ContainerResourceAction.createContainer;
    return PopScope(
      canPop: !_busy,
      child: buildOpenHandDialog(
        maxHeight: MediaQuery.sizeOf(context).height * .9,
        child: SizedBox(
          width: 820,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MachineTerminalDialogHeader(
                icon: _remove
                    ? Icons.delete_outline_rounded
                    : create
                    ? Icons.add_box_outlined
                    : widget.action == _ContainerResourceAction.pull
                    ? Icons.download_rounded
                    : Icons.storage_rounded,
                title: _containerActionLabel(context, widget.action),
                onClose: () {
                  if (!_busy) Navigator.pop(context, _completed || _uncertain);
                },
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: _maintenanceDetailPadding,
                  child: _MaintenanceAnimatedColumn(
                    spacing: 14,
                    children: [
                      Text(
                        '${maintenanceLabel(context, '连接上下文')} · ${widget.client.contextName.isEmpty ? widget.client.runtime.label : widget.client.contextName}${widget.client.scope.isEmpty ? '' : ' / ${widget.client.scope}'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (_remove)
                        _MaintenanceNotice(
                          message:
                              '${widget.resource!.reference}\n${widget.action == _ContainerResourceAction.removeVolume ? l.maintenanceVolumeRemoveHelp : l.maintenanceImageRemoveHelp}',
                          error: true,
                        ),
                      if (widget.action == _ContainerResourceAction.pull ||
                          create)
                        _field(
                          'image',
                          l.maintenanceImageReference,
                          hint: 'nginx:alpine',
                        ),
                      if (widget.action == _ContainerResourceAction.pull)
                        Text(
                          l.maintenanceImagePullHelp,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (create) ...[
                        _field('name', l.maintenanceContainerNameOptional),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: Text(l.maintenanceContainerStartAfterCreate),
                          value: _start,
                          onChanged: _busy || _completed || _uncertain
                              ? null
                              : (value) => setState(() => _start = value),
                        ),
                        _rows(maintenanceLabel(context, '端口'), _ports, {
                          'address': l.maintenanceHostAddress,
                          'host': l.maintenanceHostPort,
                          'container': l.maintenanceContainerPort,
                        }, ports: true),
                        _rows(maintenanceLabel(context, '环境变量'), _environment, {
                          'key': maintenanceLabel(context, '名称'),
                          'value': maintenanceLabel(context, '数值'),
                        }),
                        _rows(l.maintenanceContainerMounts, _mounts, {
                          'source': l.maintenanceMountSource,
                          'target': l.maintenanceMountTarget,
                        }, mounts: true),
                        _MaintenanceSection(
                          title: l.maintenanceResourceAdvanced,
                          icon: Icons.tune_rounded,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: _MaintenanceAnimatedColumn(
                              spacing: 14,
                              children: [
                                AnimatedDropdownButtonFormField<String>(
                                  isExpanded: true,
                                  initialValue: _restart,
                                  decoration: _decoration(
                                    l.maintenanceDetailRestartPolicy,
                                  ),
                                  items: [
                                    for (final value in [
                                      'no',
                                      'always',
                                      'unless-stopped',
                                      'on-failure',
                                    ])
                                      DropdownMenuItem(
                                        value: value,
                                        child: Text(
                                          maintenanceDetailValue(
                                            context,
                                            value,
                                            field: 'RestartPolicy',
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                  onChanged: _busy || _completed || _uncertain
                                      ? null
                                      : (value) =>
                                            setState(() => _restart = value!),
                                ),
                                _MaintenanceGrid(
                                  minWidth: 240,
                                  maxColumns: 2,
                                  children: [
                                    _field(
                                      'network',
                                      maintenanceLabel(context, '网络'),
                                    ),
                                    _field(
                                      'user',
                                      maintenanceLabel(context, '用户'),
                                    ),
                                    _field(
                                      'directory',
                                      l.maintenanceTaskWorkingDirectory,
                                    ),
                                    _field(
                                      'entrypoint',
                                      l.maintenanceContainerEntrypoint,
                                    ),
                                    _field(
                                      'cpus',
                                      l.maintenanceCpuLimit,
                                      hint: '1.5',
                                    ),
                                    _field(
                                      'memory',
                                      l.maintenanceMemoryLimit,
                                      hint: '512m',
                                    ),
                                  ],
                                ),
                                _field(
                                  'arguments',
                                  l.maintenanceContainerCommandArguments,
                                  hint: l.maintenanceArgumentsOnePerLine,
                                  lines: 3,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (widget.action ==
                          _ContainerResourceAction.createVolume) ...[
                        _field('name', maintenanceLabel(context, '名称')),
                        _field(
                          'driver',
                          l.maintenanceVolumeDriver,
                          hint: 'local',
                        ),
                        _rows(maintenanceLabel(context, '标签'), _labels, {
                          'key': maintenanceLabel(context, '名称'),
                          'value': maintenanceLabel(context, '数值'),
                        }),
                        _rows(l.maintenanceVolumeOptions, _options, {
                          'key': maintenanceLabel(context, '名称'),
                          'value': maintenanceLabel(context, '数值'),
                        }),
                      ],
                      _MaintenanceToolbarMenu<int>(
                        label: maintenanceTimeoutLabel(context, _timeout),
                        tooltip: l.maintenanceTimeout,
                        value: _timeout,
                        enabled: !_busy && !_completed && !_uncertain,
                        items: {
                          for (final seconds
                              in machineMaintenanceTimeoutOptions)
                            seconds: maintenanceTimeoutLabel(context, seconds),
                        },
                        onSelected: (value) => setState(() => _timeout = value),
                      ),
                      if (_busy) const LinearProgressIndicator(minHeight: 2),
                      if (_error.isNotEmpty)
                        _MaintenanceNotice(message: _error, error: true),
                      if (_uncertain)
                        _MaintenanceNotice(
                          message: l.maintenanceResourceUncertain,
                        ),
                      if (_completed)
                        _MaintenanceNotice(
                          message: l.maintenanceResourceSuccess,
                        ),
                      if (_output.isNotEmpty)
                        _MaintenanceReadout(
                          text: _output,
                          section: 'logs',
                          logMaxHeight: 240,
                        ),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          if (_busy)
                            OutlinedButton(
                              onPressed: _cancelled
                                  ? null
                                  : () => setState(() => _cancelled = true),
                              child: Text(l.commonCancel),
                            )
                          else if (_completed || _uncertain)
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: Text(l.maintenanceResourceCloseRefresh),
                            )
                          else ...[
                            OutlinedButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: Text(l.commonCancel),
                            ),
                            FilledButton(
                              onPressed: _submit,
                              style: _remove
                                  ? FilledButton.styleFrom(
                                      backgroundColor: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    )
                                  : null,
                              child: Text(
                                _containerActionLabel(context, widget.action),
                              ),
                            ),
                          ],
                        ],
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
  }
}
