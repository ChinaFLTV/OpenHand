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

  static const _formFontSize = 13.0;
  static const _formControlHeight = 40.0;

  bool get _editable => !_busy && !_completed && !_uncertain;
  double get _controlHeight => math.max(
    _formControlHeight,
    MediaQuery.textScalerOf(context).scale(_formFontSize) * 1.4 + 16,
  );

  InputDecoration _decoration({String? hint, int lines = 1}) {
    final cs = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: .7)),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: cs.onSurfaceVariant,
        fontSize: _formFontSize,
      ),
      filled: true,
      fillColor: cs.surfaceContainerLowest,
      hoverColor: Colors.transparent,
      isDense: true,
      constraints: BoxConstraints.tightFor(
        height: lines == 1 ? _controlHeight : _controlHeight * lines,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: border,
      enabledBorder: border,
      disabledBorder: border.copyWith(
        borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: .4)),
      ),
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: cs.primary, width: 1.5),
      ),
    );
  }

  Widget _labeled(String label, Widget child) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Tooltip(
        message: label,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 12,
            height: 1.3,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      const SizedBox(height: 6),
      Semantics(label: label, child: child),
    ],
  );

  Widget _field(String key, String label, {String? hint, int lines = 1}) =>
      _labeled(
        label,
        TextField(
          controller: _controller(key),
          enabled: _editable,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontSize: _formFontSize,
            height: 1.4,
          ),
          minLines: lines,
          maxLines: lines,
          decoration: _decoration(hint: hint, lines: lines),
        ),
      );

  Widget _select(
    String label,
    String value,
    Map<String, String> items,
    ValueChanged<String> onChanged,
  ) => _labeled(
    label,
    AnimatedDropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: value,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontSize: _formFontSize,
        height: 1.4,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      iconSize: 18,
      decoration: _decoration(),
      items: [
        for (final item in items.entries)
          DropdownMenuItem(
            value: item.key,
            child: Text(
              item.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: _editable ? (value) => onChanged(value!) : null,
    ),
  );

  Widget _rows(
    String title,
    List<Map<String, String>> rows,
    Map<String, String> fields, {
    bool ports = false,
    bool mounts = false,
  }) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return _MaintenanceSection(
      title: title,
      icon: mounts
          ? Icons.folder_open_rounded
          : ports
          ? Icons.lan_outlined
          : Icons.tune_rounded,
      accent: mounts
          ? cs.tertiary
          : ports
          ? cs.primary
          : cs.secondary,
      initiallyExpanded: rows.isNotEmpty,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final row in rows)
            Container(
              key: ObjectKey(row),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: .45),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _MaintenanceGrid(
                          minWidth: ports ? 140 : 180,
                          maxColumns: ports
                              ? 4
                              : mounts
                              ? 3
                              : 2,
                          children: [
                            for (final field in fields.entries)
                              _labeled(
                                field.value,
                                TextFormField(
                                  initialValue: row[field.key] ?? '',
                                  enabled: _editable,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        fontSize: _formFontSize,
                                        height: 1.4,
                                      ),
                                  onChanged: (value) => row[field.key] = value,
                                  decoration: _decoration(
                                    hint: ports && field.key == 'host'
                                        ? l.maintenancePortAutomatic
                                        : null,
                                  ),
                                ),
                              ),
                            if (ports)
                              _select(
                                l.maintenanceProtocol,
                                row['protocol'] ?? 'tcp',
                                const {
                                  'tcp': 'TCP',
                                  'udp': 'UDP',
                                  'sctp': 'SCTP',
                                },
                                (value) =>
                                    setState(() => row['protocol'] = value),
                              ),
                            if (mounts)
                              _select(
                                l.maintenanceType,
                                row['type'] ?? 'volume',
                                {
                                  'volume': l.maintenanceVolumes,
                                  'bind': l.maintenanceBindMount,
                                },
                                (value) => setState(() => row['type'] = value),
                              ),
                          ],
                        ),
                        if (mounts) ...[
                          const SizedBox(height: 8),
                          Material(
                            type: MaterialType.transparency,
                            child: SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: Text(
                                l.maintenanceReadOnlyMount,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(fontSize: _formFontSize),
                              ),
                              value: row['readonly'] == 'true',
                              onChanged: _editable
                                  ? (value) => setState(
                                      () => row['readonly'] = '$value',
                                    )
                                  : null,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: EdgeInsets.only(
                      top: MediaQuery.textScalerOf(context).scale(12) * 1.3 + 6,
                    ),
                    child: SizedBox.square(
                      dimension: _controlHeight,
                      child: IconButton(
                        onPressed: _editable
                            ? () => setState(() => rows.remove(row))
                            : null,
                        tooltip: l.commonDelete,
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed:
                  !_editable || rows.length >= machineContainerFormRowLimit
                  ? null
                  : () => setState(
                      () => rows.add({if (ports) 'address': '127.0.0.1'}),
                    ),
              icon: const Icon(Icons.add_rounded, size: 16),
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final create = widget.action == _ContainerResourceAction.createContainer;
    final actionStyle = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(0, _controlHeight)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 14),
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
      textStyle: WidgetStatePropertyAll(
        theme.textTheme.labelLarge?.copyWith(
          fontSize: _formFontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    );
    return Theme(
      data: theme.copyWith(
        hoverColor: Colors.transparent,
        shadowColor: Colors.transparent,
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: cs.primary,
            foregroundColor: cs.onPrimary,
          ).merge(actionStyle),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(style: actionStyle),
        textButtonTheme: TextButtonThemeData(style: actionStyle),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            padding: EdgeInsets.zero,
            backgroundColor: cs.surfaceContainerLowest,
            foregroundColor: cs.onSurfaceVariant,
            disabledForegroundColor: cs.onSurface.withValues(alpha: .38),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: .7)),
          ),
        ),
      ),
      child: PopScope(
        canPop: !_busy,
        child: buildOpenHandDialog(
          height: create
              ? math.min(
                  kOpenHandDialogHeightTall,
                  MediaQuery.sizeOf(context).height * .92,
                )
              : null,
          maxHeight: MediaQuery.sizeOf(context).height * .92,
          backgroundColor: cs.surfaceContainerLow,
          surfaceTintColor: Colors.transparent,
          child: SizedBox(
            width: create
                ? kOpenHandDialogWidthWide
                : widget.action == _ContainerResourceAction.createVolume
                ? kOpenHandDialogWidthStandard
                : kOpenHandDialogWidthCompact,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  subtitle:
                      '${l.maintenanceContainerContext} · ${widget.client.contextName.isEmpty ? widget.client.runtime.label : widget.client.contextName}${widget.client.scope.isEmpty ? '' : ' / ${widget.client.scope}'}',
                  onClose: () {
                    if (!_busy) {
                      Navigator.pop(context, _completed || _uncertain);
                    }
                  },
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: _maintenanceDetailPadding,
                    child: _MaintenanceAnimatedColumn(
                      spacing: 12,
                      children: [
                        if (_remove) ...[
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: cs.outlineVariant.withValues(alpha: .65),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _MaintenanceIconBadge(
                                  icon:
                                      widget.action ==
                                          _ContainerResourceAction.removeVolume
                                      ? Icons.storage_rounded
                                      : Icons.layers_outlined,
                                  color: cs.secondary,
                                  size: _formControlHeight,
                                  iconSize: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.action ==
                                                _ContainerResourceAction
                                                    .removeVolume
                                            ? l.maintenanceVolumes
                                            : l.maintenanceImages,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: cs.onSurfaceVariant,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      SelectableText(
                                        widget.resource!.reference,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              fontSize: _formFontSize,
                                              fontWeight: FontWeight.w600,
                                              height: 1.5,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!_completed)
                            _MaintenanceNotice(
                              message:
                                  widget.action ==
                                      _ContainerResourceAction.removeVolume
                                  ? l.maintenanceVolumeRemoveHelp
                                  : l.maintenanceImageRemoveHelp,
                              error: true,
                            ),
                        ],
                        if (widget.action == _ContainerResourceAction.pull) ...[
                          _field(
                            'image',
                            l.maintenanceImageReference,
                            hint: 'nginx:alpine',
                          ),
                          Text(
                            l.maintenanceImagePullHelp,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                        if (create) ...[
                          _MaintenanceSection(
                            title: l.maintenanceBasicInfo,
                            icon: Icons.widgets_outlined,
                            initiallyExpanded: true,
                            child: Column(
                              children: [
                                _MaintenanceGrid(
                                  minWidth: 240,
                                  maxColumns: 2,
                                  children: [
                                    _field(
                                      'image',
                                      l.maintenanceImageReference,
                                      hint: 'nginx:alpine',
                                    ),
                                    _field(
                                      'name',
                                      l.maintenanceContainerNameOptional,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                SwitchListTile.adaptive(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  title: Text(
                                    l.maintenanceContainerStartAfterCreate,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontSize: _formFontSize,
                                    ),
                                  ),
                                  value: _start,
                                  onChanged: _editable
                                      ? (value) =>
                                            setState(() => _start = value)
                                      : null,
                                ),
                              ],
                            ),
                          ),
                          _rows(maintenanceLabel(context, '端口'), _ports, {
                            'address': l.maintenanceHostAddress,
                            'host': l.maintenanceHostPort,
                            'container': l.maintenanceContainerPort,
                          }, ports: true),
                          _rows(
                            maintenanceLabel(context, '环境变量'),
                            _environment,
                            {
                              'key': maintenanceLabel(context, '名称'),
                              'value': maintenanceLabel(context, '数值'),
                            },
                          ),
                          _rows(l.maintenanceContainerMounts, _mounts, {
                            'source': l.maintenanceMountSource,
                            'target': l.maintenanceMountTarget,
                          }, mounts: true),
                          _MaintenanceSection(
                            title: l.maintenanceResourceAdvanced,
                            icon: Icons.tune_rounded,
                            accent: cs.secondary,
                            child: _MaintenanceAnimatedColumn(
                              spacing: 12,
                              children: [
                                _MaintenanceGrid(
                                  minWidth: 240,
                                  maxColumns: 2,
                                  children: [
                                    _select(
                                      l.maintenanceDetailRestartPolicy,
                                      _restart,
                                      {
                                        for (final value in [
                                          'no',
                                          'always',
                                          'unless-stopped',
                                          'on-failure',
                                        ])
                                          value: maintenanceDetailValue(
                                            context,
                                            value,
                                            field: 'RestartPolicy',
                                          ),
                                      },
                                      (value) =>
                                          setState(() => _restart = value),
                                    ),
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
                                  'entrypoint',
                                  l.maintenanceContainerEntrypoint,
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
                        ],
                        if (widget.action ==
                            _ContainerResourceAction.createVolume) ...[
                          _MaintenanceGrid(
                            minWidth: 240,
                            maxColumns: 2,
                            children: [
                              _field('name', maintenanceLabel(context, '名称')),
                              _field(
                                'driver',
                                l.maintenanceVolumeDriver,
                                hint: 'local',
                              ),
                            ],
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
                        if (_output.isNotEmpty)
                          _MaintenanceReadout(
                            text: _output,
                            section: 'logs',
                            logMaxHeight: 240,
                          ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLowest,
                    border: Border(
                      top: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: .65),
                      ),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_busy) ...[
                        const LinearProgressIndicator(minHeight: 2),
                        const SizedBox(height: 10),
                      ],
                      if (_error.isNotEmpty || _uncertain || _completed) ...[
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 120),
                          child: SingleChildScrollView(
                            child: _MaintenanceNotice(
                              message: [
                                if (_error.isNotEmpty) _error,
                                if (_uncertain) l.maintenanceResourceUncertain,
                                if (_completed) l.maintenanceResourceSuccess,
                              ].join('\n'),
                              error: _error.isNotEmpty,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      buildOpenHandDialogActionsBar(
                        padding: EdgeInsets.zero,
                        leading: Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            height: _controlHeight,
                            child: _MaintenanceToolbarMenu<int>(
                              label: maintenanceTimeoutLabel(context, _timeout),
                              tooltip: l.maintenanceOperationTimeout,
                              icon: Icons.timer_outlined,
                              value: _timeout,
                              enabled: _editable,
                              items: {
                                for (final seconds
                                    in machineMaintenanceTimeoutOptions)
                                  seconds: maintenanceTimeoutLabel(
                                    context,
                                    seconds,
                                  ),
                              },
                              onSelected: (value) =>
                                  setState(() => _timeout = value),
                            ),
                          ),
                        ),
                        actions: [
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
                                      backgroundColor: cs.error,
                                      foregroundColor: cs.onError,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
