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
    var containerCreated = false;
    try {
      if (search) {
        final result = await showAnimatedDialog<bool>(
          context: context,
          builder: (_) => _ContainerRegistryDialog(
            client: client,
            operate: operate,
            timeout: widget.timeout,
            registryFactory: MachineImageRegistry.new,
            onChanged: () => changed = true,
            onCreated: () => containerCreated = true,
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
                registryFactory: MachineImageRegistry.new,
                imageReferences: _images
                    ? _resources.map((image) => image.reference).toList()
                    : const [],
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
      if (action == _ContainerResourceAction.createContainer ||
          containerCreated) {
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

const _containerResourceFontSize = 13.0;
const _containerResourceControlHeight = 40.0;

Widget _buildContainerResourceActions({
  required BuildContext context,
  required List<Widget> actions,
  EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(16, 8, 16, 12),
}) => Theme(
  // 底部操作沿用全局确认弹窗样式，避免继承表单内的紧凑按钮主题。
  data: Theme.of(context),
  child: buildOpenHandDialogActionsBar(actions: actions, padding: padding),
);

double _containerResourceControlHeightOf(BuildContext context) => math.max(
  _containerResourceControlHeight,
  MediaQuery.textScalerOf(context).scale(_containerResourceFontSize) * 1.4 + 16,
);

ButtonStyle _containerResourceTonalButtonStyle(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return FilledButton.styleFrom(
    backgroundColor: cs.secondaryContainer,
    foregroundColor: cs.onSecondaryContainer,
    minimumSize: Size(0, _containerResourceControlHeightOf(context)),
    padding: const EdgeInsets.symmetric(horizontal: 14),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.standard,
    textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
      fontSize: _containerResourceFontSize,
      fontWeight: FontWeight.w600,
    ),
    shape: const RoundedRectangleBorder(borderRadius: kOpenHandBorderRadius8),
    elevation: 0,
    shadowColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
  );
}

ThemeData _containerResourceDialogTheme(BuildContext context) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final actionStyle = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(
      Size(88, _containerResourceControlHeightOf(context)),
    ),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14)),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.standard,
    textStyle: WidgetStatePropertyAll(
      theme.textTheme.labelLarge?.copyWith(
        fontSize: _containerResourceFontSize,
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
  return theme.copyWith(
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: .7)),
      ),
    ),
    listTileTheme: theme.listTileTheme.copyWith(
      minTileHeight: _containerResourceControlHeightOf(context),
      minVerticalPadding: 4,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      titleTextStyle: theme.textTheme.bodyMedium?.copyWith(
        fontSize: _containerResourceFontSize,
        height: 1.4,
      ),
    ),
  );
}

class _ContainerRegistrySearchField extends StatelessWidget {
  const _ContainerRegistrySearchField({
    required this.controller,
    required this.hint,
    required this.onSearch,
    required this.searchLabel,
    this.enabled = true,
    this.onChanged,
  });
  final TextEditingController controller;
  final String hint;
  final VoidCallback? onSearch;
  final String searchLabel;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final searchHeight = _containerResourceControlHeightOf(context);
    final searchBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: .7)),
    );
    return TextField(
      controller: controller,
      enabled: enabled,
      textInputAction: TextInputAction.search,
      textAlignVertical: TextAlignVertical.center,
      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13, height: 1.4),
      onSubmitted: (_) => onSearch?.call(),
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: cs.surfaceContainerLowest,
        hoverColor: Colors.transparent,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        constraints: BoxConstraints.tightFor(height: searchHeight),
        border: searchBorder,
        enabledBorder: searchBorder,
        disabledBorder: searchBorder.copyWith(
          borderSide: BorderSide(
            color: cs.outlineVariant.withValues(alpha: .4),
          ),
        ),
        focusedBorder: searchBorder.copyWith(
          borderSide: BorderSide(color: cs.primary, width: 1.5),
        ),
        errorBorder: searchBorder.copyWith(
          borderSide: BorderSide(color: cs.error),
        ),
        focusedErrorBorder: searchBorder.copyWith(
          borderSide: BorderSide(color: cs.error, width: 1.5),
        ),
        suffixIconConstraints: BoxConstraints.tightFor(
          width: searchHeight,
          height: searchHeight,
        ),
        suffixIcon: IconButton(
          onPressed: enabled ? onSearch : null,
          tooltip: searchLabel,
          style:
              IconButton.styleFrom(
                backgroundColor: Colors.transparent,
                disabledBackgroundColor: Colors.transparent,
                side: BorderSide.none,
                foregroundColor: cs.onSurfaceVariant,
                disabledForegroundColor: cs.onSurface.withValues(alpha: .38),
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.standard,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ).copyWith(
                overlayColor: WidgetStateProperty.resolveWith(
                  (states) =>
                      states.contains(WidgetState.pressed) ||
                          states.contains(WidgetState.focused)
                      ? cs.primary.withValues(alpha: .1)
                      : Colors.transparent,
                ),
              ),
          icon: const Icon(Icons.search_rounded, size: 18),
        ),
      ),
    );
  }
}

class _ContainerRegistryDialog extends StatefulWidget {
  const _ContainerRegistryDialog({
    required this.client,
    this.onChanged,
    this.onCreated,
    required this.registryFactory,
    required this.timeout,
    this.operate,
  });
  final MachineContainerClient client;
  final VoidCallback? onChanged, onCreated;
  final MachineImageRegistry Function() registryFactory;
  final Duration timeout;
  final MachineContainerOperationRunner? operate;
  @override
  State<_ContainerRegistryDialog> createState() =>
      _ContainerRegistryDialogState();
}

class _ContainerRegistryDialogState extends State<_ContainerRegistryDialog> {
  final _query = TextEditingController();
  List<MachineContainerImageSearchResult> _results = [];
  late final _registry = widget.registryFactory();
  final _tags = <String, String>{};
  int _searchRevision = 0;
  bool _metadataFailed = false;
  String _error = '';
  bool _busy = false, _searched = false, _searching = false, _changed = false;
  @override
  void dispose() {
    _registry.dispose();
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_busy) return;
    final revision = ++_searchRevision;
    _registry.cancelPending();
    final query = _query.text.trim();
    setState(() {
      _metadataFailed = false;
      _busy = true;
      _searching = true;
      _error = '';
    });
    try {
      final rows = await widget.client.searchImages(query);
      if (mounted) {
        setState(() {
          _results = rows;
          _searched = true;
          _tags.removeWhere((name, _) => !rows.any((row) => row.name == name));
        });
        if (rows.any((row) => row.hubRepository != null)) {
          unawaited(_enrich(query, revision));
          unawaited(_enrich(query, revision, logos: true));
        }
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

  Future<void> _enrich(String query, int revision, {bool logos = false}) async {
    try {
      final metadata = await _registry.searchMetadata(query, logos: logos);
      if (!mounted || revision != _searchRevision) return;
      setState(
        () => _results = [
          for (final row in _results)
            if (metadata[row.hubRepository] case final entry?)
              row.withMetadata(entry)
            else
              row,
        ],
      );
    } on Exception {
      if (mounted && revision == _searchRevision) {
        setState(() => _metadataFailed = true);
      }
    }
  }

  String _reference(MachineContainerImageSearchResult row) =>
      '${row.name}:${_tags[row.name] ?? 'latest'}';

  Future<void> _selectTag(MachineContainerImageSearchResult row) async {
    if (_busy) return;
    setState(() => _busy = true);
    final tag = await showAnimatedDialog<String>(
      context: context,
      builder: (_) => _ContainerImageTagDialog(
        image: row,
        selected: _tags[row.name] ?? 'latest',
        registryFactory: widget.registryFactory,
      ),
    );
    if (mounted) {
      setState(() {
        if (tag != null) _tags[row.name] = tag;
        _busy = false;
      });
    }
  }

  Future<void> _openImage(
    String image, {
    _ContainerResourceAction action = _ContainerResourceAction.pull,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    final changed = await showAnimatedDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ContainerResourceFormDialog(
        client: widget.client,
        action: action,
        image: image,
        operate: widget.operate,
        timeout: widget.timeout,
        registryFactory: widget.registryFactory,
        imageReferences: _results.map(_reference).toList(),
      ),
    );
    if (changed == true) {
      widget.onChanged?.call();
      if (action == _ContainerResourceAction.createContainer) {
        widget.onCreated?.call();
      }
    }
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Theme(
      data: _containerResourceDialogTheme(context),
      child: PopScope(
        canPop: !_busy,
        child: buildOpenHandDialog(
          maxHeight: MediaQuery.sizeOf(context).height * .9,
          backgroundColor: cs.surfaceContainerLow,
          surfaceTintColor: Colors.transparent,
          child: SizedBox(
            width: kOpenHandDialogWidthWide,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MachineTerminalDialogHeader(
                  icon: Icons.travel_explore_rounded,
                  title: l.maintenanceImageSearch,
                  subtitle:
                      '${widget.client.runtime.label}${widget.client.contextName.isEmpty ? '' : ' · ${widget.client.contextName}'}${widget.client.scope.isEmpty ? '' : ' / ${widget.client.scope}'}',
                  onClose: () => Navigator.pop(context, _changed),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: _maintenanceDetailPadding,
                    child: _MaintenanceAnimatedColumn(
                      spacing: 12,
                      children: [
                        _MaintenanceCard(
                          title: l.maintenanceImageQuery,
                          icon: Icons.search_rounded,
                          scrollBody: false,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _ContainerRegistrySearchField(
                                controller: _query,
                                enabled: !_busy,
                                hint: l.maintenanceImageQuery,
                                searchLabel: l.maintenanceImageSearch,
                                onSearch: _search,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                l.maintenanceImageSearchHelp,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_searching)
                          const LinearProgressIndicator(minHeight: 2),
                        if (_error.isNotEmpty)
                          _MaintenanceNotice(message: _error, error: true),
                        if (_metadataFailed)
                          _MaintenanceNotice(
                            message: l.maintenanceImageMetadataUnavailable,
                          ),
                        if (_searched && _results.isEmpty)
                          _MaintenanceEmptyHint(
                            message: maintenanceLabel(context, '当前范围没有记录'),
                          ),
                        if (_results.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 2,
                            ),
                            child: Text(
                              l.maintenanceImageResults(_results.length),
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          _MaintenanceTable(
                            headers: [
                              '名称',
                              '描述',
                              l.maintenanceImageTag,
                              l.maintenanceImageStars,
                              l.maintenanceImageDownloads,
                              l.maintenanceImageOfficial,
                            ],
                            maxBodyHeight: 400,
                            minimumColumnWidths: {
                              2:
                                  160 *
                                  MediaQuery.textScalerOf(context).scale(13) /
                                  13,
                            },
                            rows: [
                              for (final row in _results)
                                OpenHandOperationalRankRow(
                                  value: 0,
                                  data: row,
                                  rowKey: row.name,
                                  cells: [
                                    row.name,
                                    row.description,
                                    _tags[row.name] ?? 'latest',
                                    '${row.stars ?? '—'}',
                                    '${row.pulls ?? '—'}',
                                    row.official == null
                                        ? '—'
                                        : row.official!
                                        ? l.maintenanceHealthParsedYes
                                        : l.maintenanceHealthParsedNo,
                                  ],
                                  cellWidgets: [
                                    Row(
                                      children: [
                                        if (row.iconUrl != null) ...[
                                          Image.network(
                                            row.iconUrl!,
                                            width: 20,
                                            height: 20,
                                            cacheWidth: 40,
                                            cacheHeight: 40,
                                            fit: BoxFit.contain,
                                            errorBuilder: (_, _, _) => Icon(
                                              Icons.layers_outlined,
                                              size: 18,
                                              color: cs.onSurfaceVariant,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        Expanded(
                                          child: Text(
                                            row.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      row.description,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w400,
                                            color: cs.onSurfaceVariant,
                                          ),
                                    ),
                                    TextButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _selectTag(row),
                                      style: TextButton.styleFrom(
                                        minimumSize: const Size(
                                          0,
                                          _maintenanceControlHeight,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                        backgroundColor:
                                            cs.surfaceContainerLowest,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          side: BorderSide(
                                            color: cs.outlineVariant,
                                          ),
                                        ),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              _tags[row.name] ?? 'latest',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          const Icon(
                                            Icons.expand_more_rounded,
                                            size: 16,
                                          ),
                                        ],
                                      ),
                                    ),
                                    for (final metric in [
                                      ('stars', row.stars),
                                      ('pulls', row.pulls),
                                    ])
                                      metric.$2 == null
                                          ? null
                                          : _MaintenanceNumber(
                                              key: ValueKey((
                                                row.name,
                                                metric.$1,
                                              )),
                                              raw: '${metric.$2}',
                                              readable:
                                                  openHandCompactCountLabel(
                                                    context,
                                                    metric.$2!,
                                                  ),
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            ),
                                    row.official == null
                                        ? null
                                        : _MaintenanceStatus(
                                            label: row.official!
                                                ? l.maintenanceHealthParsedYes
                                                : l.maintenanceHealthParsedNo,
                                            color: row.official!
                                                ? cs.primary
                                                : cs.onSurfaceVariant,
                                          ),
                                  ],
                                ),
                            ],
                            rowActions: (row) => {
                              if (!_busy) ...{
                                l.maintenanceImageSelectTag: () => _selectTag(
                                  row.data as MachineContainerImageSearchResult,
                                ),
                                l.maintenanceImagePullOnly: () => _openImage(
                                  _reference(
                                    row.data
                                        as MachineContainerImageSearchResult,
                                  ),
                                ),
                                l.maintenanceContainerCreate: () => _openImage(
                                  _reference(
                                    row.data
                                        as MachineContainerImageSearchResult,
                                  ),
                                  action:
                                      _ContainerResourceAction.createContainer,
                                ),
                              },
                            },
                          ),
                        ],
                      ],
                    ),
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

class _ContainerImageTagDialog extends StatefulWidget {
  const _ContainerImageTagDialog({
    required this.image,
    required this.selected,
    this.registryFactory,
  });
  final MachineContainerImageSearchResult image;
  final String selected;
  final MachineImageRegistry Function()? registryFactory;
  @override
  State<_ContainerImageTagDialog> createState() =>
      _ContainerImageTagDialogState();
}

class _ContainerImageTagDialogState extends State<_ContainerImageTagDialog> {
  late final _tag = TextEditingController(text: widget.selected);
  late final _registry =
      widget.registryFactory?.call() ?? MachineImageRegistry();
  final _tags = <String>[];
  bool _loading = false, _hasMore = false, _failed = false;
  int _page = 0;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    if (widget.image.hubRepository != null) unawaited(_load());
  }

  @override
  void dispose() {
    _registry.dispose();
    _tag.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading || widget.image.hubRepository == null) return;
    if (reset && _tag.text.trim().length > 128) return;
    setState(() {
      _loading = true;
      _failed = false;
      if (reset) {
        _page = 0;
        _filter = _tag.text.trim();
        _tags.clear();
        _hasMore = false;
      }
    });
    try {
      final result = await _registry.tags(
        widget.image.hubRepository!,
        filter: _filter,
        page: _page + 1,
      );
      if (!mounted) return;
      setState(() {
        _page++;
        _tags.addAll(result.tags.where((tag) => !_tags.contains(tag)));
        _hasMore = result.hasMore;
      });
    } on Exception {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final valid = machineContainerValidImageTag(_tag.text.trim());
    final supported = widget.image.hubRepository != null;
    return Theme(
      data: _containerResourceDialogTheme(context),
      child: buildOpenHandDialog(
        maxHeight: MediaQuery.sizeOf(context).height * .9,
        backgroundColor: cs.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        child: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MachineTerminalDialogHeader(
                icon: Icons.sell_outlined,
                title: l.maintenanceImageSelectTag,
                subtitle: widget.image.name,
                onClose: () => Navigator.pop(context),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: _maintenanceDetailPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l.maintenanceImageTagHelp,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      _ContainerRegistrySearchField(
                        controller: _tag,
                        hint: l.maintenanceImageTag,
                        searchLabel: l.maintenanceImageTagSearch,
                        onSearch: supported && !_loading
                            ? () => _load(reset: true)
                            : null,
                        onChanged: (_) => setState(() {}),
                      ),
                      if (!valid && _tag.text.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _MaintenanceNotice(
                          message: l.maintenanceImageTagInvalid,
                          error: true,
                        ),
                      ],
                      if (_failed || !supported) ...[
                        const SizedBox(height: 8),
                        _MaintenanceNotice(
                          message: l.maintenanceImageTagsUnavailable,
                        ),
                      ],
                      if (_loading) ...[
                        const SizedBox(height: 12),
                        const LinearProgressIndicator(minHeight: 2),
                      ],
                      if (_tags.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: cs.outlineVariant),
                          ),
                          constraints: const BoxConstraints(maxHeight: 260),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _tags.length,
                            itemBuilder: (context, index) {
                              final tag = _tags[index];
                              final selected = tag == _tag.text.trim();
                              return ListTile(
                                dense: true,
                                minTileHeight:
                                    _containerResourceControlHeightOf(context),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                selected: selected,
                                selectedTileColor: cs.primary.withValues(
                                  alpha: .08,
                                ),
                                title: Text(
                                  tag,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: selected
                                    ? Icon(
                                        Icons.check_rounded,
                                        size: 18,
                                        color: cs.primary,
                                      )
                                    : null,
                                onTap: () => setState(() => _tag.text = tag),
                              );
                            },
                          ),
                        ),
                      ],
                      if (!_loading && supported && (_hasMore || _failed)) ...[
                        kOpenHandGap12,
                        Center(
                          child: FilledButton.tonal(
                            style: _containerResourceTonalButtonStyle(context),
                            onPressed: _load,
                            child: Text(
                              _failed
                                  ? l.maintenanceImageTagRetry
                                  : l.maintenanceImageTagsMore,
                            ),
                          ),
                        ),
                      ],
                      if (!_loading && !_failed && supported && _tags.isEmpty)
                        _MaintenanceEmptyHint(
                          message: maintenanceLabel(context, '当前范围没有记录'),
                        ),
                    ],
                  ),
                ),
              ),
              _buildContainerResourceActions(
                context: context,
                actions: [
                  OpenHandDialogActionButton.secondary(
                    onPressed: () => Navigator.pop(context),
                    label: l.commonCancel,
                  ),
                  OpenHandDialogActionButton.primary(
                    onPressed: valid
                        ? () => Navigator.pop(context, _tag.text.trim())
                        : null,
                    label: l.commonConfirm,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _containerImageSuggestionLimit = 20;
const _containerImageSearchDebounce = Duration(milliseconds: 300);

class _ContainerImageReferenceField extends StatefulWidget {
  const _ContainerImageReferenceField({
    required this.controller,
    required this.decoration,
    required this.style,
    required this.enabled,
    required this.registryFactory,
    required this.references,
  });

  final TextEditingController controller;
  final InputDecoration decoration;
  final TextStyle? style;
  final bool enabled;
  final MachineImageRegistry Function()? registryFactory;
  final Iterable<String> references;

  @override
  State<_ContainerImageReferenceField> createState() =>
      _ContainerImageReferenceFieldState();
}

class _ContainerImageReferenceFieldState
    extends State<_ContainerImageReferenceField> {
  late final _registry =
      widget.registryFactory?.call() ?? MachineImageRegistry();
  final _focus = FocusNode();
  List<String> _suggestions = [];
  List<MachineContainerImageSearchResult> _images = [];
  String _repository = '', _error = '';
  TextEditingValue _lastInput = TextEditingValue.empty;
  Timer? _debounce;
  int _revision = 0;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _lastInput = widget.controller.value;
    _suggestions = widget.references
        .where((value) => value.isNotEmpty)
        .toSet()
        .take(_containerImageSuggestionLimit)
        .toList();
    widget.controller.addListener(_inputChanged);
    _focus.addListener(_scheduleSearch);
  }

  @override
  void didUpdateWidget(covariant _ContainerImageReferenceField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) _cancelSearch();
  }

  void _cancelSearch() {
    _revision++;
    _debounce?.cancel();
    _registry.cancelPending();
    _loading = false;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_inputChanged);
    _focus.removeListener(_scheduleSearch);
    _cancelSearch();
    _focus.dispose();
    _registry.dispose();
    super.dispose();
  }

  void _inputChanged() {
    final value = widget.controller.value;
    if (value.text == _lastInput.text &&
        value.composing == _lastInput.composing) {
      return;
    }
    _lastInput = value;
    // 选中候选时不重复查询，仓库名称的标签查询由选择回调触发。
    if (_suggestions.contains(value.text)) {
      _cancelSearch();
      return;
    }
    _scheduleSearch();
  }

  void _scheduleSearch() {
    if (!widget.enabled || !_focus.hasFocus) {
      _cancelSearch();
      return;
    }
    _cancelSearch();
    if (widget.controller.value.composing.isValid) return;
    final query = widget.controller.text.trim();
    final revision = _revision;
    final colon = query.lastIndexOf(':');
    final tagged = colon > query.lastIndexOf('/');
    final repository = tagged ? query.substring(0, colon) : query;
    final tag = tagged ? query.substring(colon + 1) : '';
    final canonical = machineDockerHubRepository(repository);
    final local = widget.references
        .where(
          (value) =>
              value.isNotEmpty &&
              value.toLowerCase().contains(query.toLowerCase()),
        )
        .toSet()
        .take(_containerImageSuggestionLimit)
        .toList();
    // 私有仓库和摘要引用只使用已有候选，避免错误查询公开仓库。
    final searchable =
        query.length <= 256 &&
        canonical != null &&
        tag.length <= 128 &&
        !query.contains('@');
    setState(() {
      _suggestions = local;
      _error = '';
      _loading = searchable;
    });
    if (!searchable) return;
    _debounce = startSafeTimer(_containerImageSearchDebounce, () {
      unawaited(_loadSuggestions(repository, canonical, tag, revision, local));
    });
  }

  Future<void> _loadSuggestions(
    String repository,
    String canonical,
    String tag,
    int revision,
    List<String> local,
  ) async {
    if (!mounted || revision != _revision) return;
    var searchFailed = false, tagsFailed = false;
    var tags = <String>[];
    await Future.wait<void>([
      if (tag.isEmpty && repository != _repository)
        () async {
          try {
            final metadata = await _registry.searchMetadata(repository);
            if (!mounted || revision != _revision) return;
            _repository = repository;
            _images = metadata.values.toList();
          } on Exception {
            if (!mounted || revision != _revision) return;
            _images = [];
            searchFailed = true;
          }
        }(),
      () async {
        try {
          tags = (await _registry.tags(canonical, filter: tag)).tags;
        } on Exception {
          tagsFailed = true;
        }
      }(),
    ]);
    if (!mounted || revision != _revision) return;
    final references = <String>{...local};
    if (tag.isEmpty) {
      references.addAll(_images.take(8).map((image) => image.name));
    }
    references.addAll(tags.map((value) => '$repository:$value'));
    setState(() {
      _suggestions = references.take(_containerImageSuggestionLimit).toList();
      _loading = false;
      _error = tagsFailed
          ? AppLocalizations.of(context)!.maintenanceImageTagsUnavailable
          : searchFailed
          ? AppLocalizations.of(context)!.maintenanceImageMetadataUnavailable
          : '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AnimatedEditableDropdown(
      controller: widget.controller,
      focusNode: _focus,
      decoration: widget.decoration,
      style: widget.style,
      enabled: widget.enabled,
      entries: [
        for (final reference in _suggestions)
          DropdownMenuEntry(value: reference, label: reference),
        if (_loading || _error.isNotEmpty || _suggestions.isEmpty)
          DropdownMenuEntry(
            value: '',
            label: _loading
                ? l.maintenanceLoadingDetails
                : _error.isNotEmpty
                ? _error
                : l.maintenanceContainerNoRecords,
            enabled: false,
          ),
      ],
      onSelected: (value) {
        if (value != null && !value.contains(':')) {
          _scheduleSearch();
        } else {
          setState(_cancelSearch);
        }
      },
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
    this.registryFactory,
    this.imageReferences = const [],
  });
  final MachineContainerClient client;
  final _ContainerResourceAction action;
  final Duration timeout;
  final MachineContainerOperationRunner? operate;
  final MachineContainerResource? resource;
  final String image;
  final MachineImageRegistry Function()? registryFactory;
  final List<String> imageReferences;
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

  static const _formFontSize = _containerResourceFontSize;
  static const _formControlHeight = _containerResourceControlHeight;

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

  Widget _field(
    String key,
    String label, {
    String? hint,
    int lines = 1,
    List<String> candidates = const [],
  }) => _labeled(
    label,
    candidates.isNotEmpty
        ? AnimatedEditableDropdown(
            controller: _controller(key),
            decoration: _decoration(hint: hint),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontSize: _formFontSize,
              height: 1.4,
            ),
            enabled: _editable,
            entries: [
              for (final candidate in candidates)
                DropdownMenuEntry(value: candidate, label: candidate),
            ],
          )
        : TextField(
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

  Widget _imageField(String label, {String? hint}) => _labeled(
    label,
    _ContainerImageReferenceField(
      controller: _controller('image'),
      decoration: _decoration(hint: hint),
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(fontSize: _formFontSize, height: 1.4),
      enabled: _editable,
      registryFactory: widget.registryFactory,
      references: {
        ...widget.imageReferences,
        if (widget.image.isNotEmpty) widget.image,
        if (widget.resource != null) widget.resource!.reference,
      },
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
                            child: SwitchListTile(
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
            child: FilledButton.tonalIcon(
              onPressed:
                  !_editable || rows.length >= machineContainerFormRowLimit
                  ? null
                  : () => setState(
                      () => rows.add({if (ports) 'address': '127.0.0.1'}),
                    ),
              style: _containerResourceTonalButtonStyle(context),
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
    return Theme(
      data: _containerResourceDialogTheme(context),
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
                          _MaintenanceCard(
                            title: l.maintenanceImages,
                            icon: Icons.layers_outlined,
                            scrollBody: false,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _imageField(
                                  l.maintenanceImageReference,
                                  hint: 'nginx:alpine',
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  l.maintenanceImagePullHelp,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
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
                                    _imageField(
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
                                SwitchListTile(
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
                                      candidates: const ['0.5', '1', '2', '4'],
                                    ),
                                    _field(
                                      'memory',
                                      l.maintenanceMemoryLimit,
                                      hint: '512m',
                                      candidates: const [
                                        '128m',
                                        '256m',
                                        '512m',
                                        '1g',
                                        '2g',
                                      ],
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
                                candidates: const ['local'],
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
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: cs.outlineVariant.withValues(alpha: .65),
                            ),
                          ),
                          child: Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              Text(
                                l.maintenanceOperationTimeout,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              _MaintenanceToolbarMenu<int>(
                                label: maintenanceTimeoutLabel(
                                  context,
                                  _timeout,
                                ),
                                tooltip: l.maintenanceOperationTimeout,
                                icon: Icons.timer_outlined,
                                value: _timeout,
                                enabled: _editable,
                                controlHeight: _controlHeight,
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
                            ],
                          ),
                        ),
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
                      _buildContainerResourceActions(
                        context: context,
                        padding: EdgeInsets.zero,
                        actions: [
                          if (_busy)
                            OpenHandDialogActionButton.secondary(
                              onPressed: _cancelled
                                  ? null
                                  : () => setState(() => _cancelled = true),
                              label: l.commonCancel,
                            )
                          else if (_completed || _uncertain)
                            OpenHandDialogActionButton.primary(
                              onPressed: () => Navigator.pop(context, true),
                              label: l.maintenanceResourceCloseRefresh,
                            )
                          else ...[
                            OpenHandDialogActionButton.secondary(
                              onPressed: () => Navigator.pop(context, false),
                              label: l.commonCancel,
                            ),
                            if (_remove)
                              OpenHandDialogActionButton.destructive(
                                onPressed: _submit,
                                label: _containerActionLabel(
                                  context,
                                  widget.action,
                                ),
                              )
                            else
                              OpenHandDialogActionButton.primary(
                                onPressed: _submit,
                                label: _containerActionLabel(
                                  context,
                                  widget.action,
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
