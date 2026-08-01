import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_ops_charts.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/ui/openhand_trailing_toolbar.dart';
import '../../../shared/util/localized_text.dart';
import '../model/ai_exposure_models.dart';
import '../service/ai_exposure_proxy_probe.dart';
import '../services_controller.dart';
import 'service_dialog_controls.dart';

const int _kMaxProxyImportBytes = 4 * 1024 * 1024;
const int _kMaxProxyEndpoints = 10000;
const Duration _kProbeResultFlushDelay = Duration(milliseconds: 80);
const List<int> _kInspectionIntervals = <int>[5, 15, 30, 60, 180, 360];
const List<int> _kInspectionConcurrencyOptions = <int>[1, 2, 4, 8, 16, 32];

enum _ProxySort { nameAscending, latencyAscending, latencyDescending }

Future<void> showAiExposureProxyDialog(BuildContext context) =>
    showAnimatedDialog<void>(
      context: context,
      builder: (_) => buildOpenHandDialog(
        maxWidth: kOpenHandDialogWidthExtraWide,
        maxHeight: kOpenHandDialogHeightTall,
        child: const _ProxyDialog(),
      ),
    );

class _ProxyDialog extends StatefulWidget {
  const _ProxyDialog();

  @override
  State<_ProxyDialog> createState() => _ProxyDialogState();
}

class _ProxyDialogState extends State<_ProxyDialog> {
  final AiExposureProxyProbe _probe = const AiExposureProxyProbe();
  final Set<String> _testingUrls = <String>{};
  final Map<String, AiExposureProxyProbeSample> _pendingSamples =
      <String, AiExposureProxyProbeSample>{};
  late bool _enabled;
  late bool _bypassLocal;
  late bool _inspectionEnabled;
  late int _inspectionIntervalMinutes;
  late int _inspectionConcurrency;
  late AiExposureProxyStrategy _strategy;
  late double _rotationEvery;
  late List<AiExposureProxyEndpoint> _endpoints;
  _ProxySort _sort = _ProxySort.nameAscending;
  List<AiExposureProxyEndpoint>? _sortedEndpointCache;
  _ProxySort? _sortedEndpointCacheSort;
  Timer? _resultFlushTimer;
  bool _busy = false;
  bool _inspectionBusy = false;
  bool _inspectionRunning = false;
  int _inspectionCompleted = 0;
  int _inspectionTotal = 0;
  int _inspectionGeneration = 0;

  @override
  void initState() {
    super.initState();
    final configuration = context.read<ServicesController>().proxyConfiguration;
    _enabled = configuration.enabled;
    _bypassLocal = configuration.bypassLocal;
    _inspectionEnabled = configuration.inspectionEnabled;
    _inspectionIntervalMinutes = configuration.inspectionIntervalMinutes;
    _inspectionConcurrency = configuration.inspectionConcurrency;
    _strategy = configuration.strategy;
    _rotationEvery = configuration.rotationEvery.toDouble();
    _endpoints = List<AiExposureProxyEndpoint>.of(configuration.endpoints);
  }

  @override
  void dispose() {
    _inspectionGeneration++;
    _resultFlushTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = openHandTextResolver(context);
    final status = context.watch<ServicesController>().proxyStatus;
    final activeCount = _endpoints.where((endpoint) => endpoint.enabled).length;
    final statusSelections = <String, int>{
      for (final item
          in status?.endpoints ?? const <AiExposureProxyEndpointStatus>[])
        item.address: item.selections,
    };
    final visibleEndpoints = _sortedEndpoints();
    return ServiceDialogInteractionTheme(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OpenHandResponsiveHeaderLayout(
              compactBreakpoint: 620,
              identity: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.lan_outlined,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          text(zh: '网络代理与代理池', en: 'Network proxy pool'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge,
                        ),
                        Text(
                          _enabled
                              ? text(
                                  zh: '$activeCount 个启用节点 · ${_strategyLabel(_strategy, text)}',
                                  en: '$activeCount active · ${_strategyLabel(_strategy, text)}',
                                )
                              : text(zh: '当前使用直接连接', en: 'Direct connection'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: _busy
                    ? null
                    : () {
                        _cancelInspection();
                        Navigator.of(context).maybePop();
                      },
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            const SizedBox(height: 16),
            _buildSettingsPanel(context),
            const SizedBox(height: 14),
            _buildEndpointToolbar(context),
            if (_inspectionBusy) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: _inspectionTotal == 0
                            ? null
                            : _inspectionCompleted / _inspectionTotal,
                        minHeight: 6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '$_inspectionCompleted/$_inspectionTotal',
                    style: theme.textTheme.labelMedium,
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: _endpoints.isEmpty
                  ? Center(
                      child: Text(
                        text(
                          zh: '代理池为空，可手工添加或批量导入 TXT/JSON。',
                          en: 'Add a proxy or import a TXT/JSON pool.',
                        ),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      cacheExtent: 480,
                      itemCount: visibleEndpoints.length,
                      padding: const EdgeInsets.only(bottom: 4),
                      itemBuilder: (context, index) {
                        final endpoint = visibleEndpoints[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _ProxyEndpointCard(
                            key: ValueKey<String>(endpoint.url),
                            endpoint: endpoint,
                            selections: statusSelections[endpoint.maskedUrl],
                            testing: _testingUrls.contains(endpoint.url),
                            busy: _busy || _inspectionBusy,
                            onEnabledChanged: (enabled) => _updateEndpoint(
                              endpoint.url,
                              endpoint.copyWith(enabled: enabled),
                            ),
                            onTest: () => _testEndpoint(endpoint.url),
                            onExport: () => _exportOne(endpoint),
                            onEdit: () => _editEndpoint(endpoint),
                            onDelete: () => setState(() {
                              _endpoints.removeWhere(
                                (item) => item.url == endpoint.url,
                              );
                              _invalidateEndpointSortCache();
                            }),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: kOpenHandDialogActionSpacing,
              runSpacing: kOpenHandDialogActionSpacing,
              children: [
                OpenHandDialogActionButton.secondary(
                  onPressed: _busy
                      ? null
                      : () {
                          _cancelInspection();
                          Navigator.of(context).maybePop();
                        },
                  label: text(zh: '取消', en: 'Cancel'),
                ),
                OpenHandDialogActionButton.primary(
                  icon: Icons.save_rounded,
                  busy: _busy,
                  onPressed: _busy || _inspectionBusy ? null : _save,
                  label: text(zh: '应用代理设置', en: 'Apply proxy settings'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<AiExposureProxyEndpoint> _sortedEndpoints() {
    if (_sortedEndpointCache != null && _sortedEndpointCacheSort == _sort) {
      return _sortedEndpointCache!;
    }
    final sorted = List<AiExposureProxyEndpoint>.of(_endpoints);
    sorted.sort((left, right) {
      switch (_sort) {
        case _ProxySort.nameAscending:
          return _compareEndpointNames(left, right);
        case _ProxySort.latencyAscending:
        case _ProxySort.latencyDescending:
          final leftLatency = left.latestSample?.latencyMs;
          final rightLatency = right.latestSample?.latencyMs;
          if (leftLatency == null && rightLatency == null) {
            return _compareEndpointNames(left, right);
          }
          if (leftLatency == null) return 1;
          if (rightLatency == null) return -1;
          final result = leftLatency.compareTo(rightLatency);
          if (result != 0) {
            return _sort == _ProxySort.latencyDescending ? -result : result;
          }
          return _compareEndpointNames(left, right);
      }
    });
    _sortedEndpointCache = List<AiExposureProxyEndpoint>.unmodifiable(sorted);
    _sortedEndpointCacheSort = _sort;
    return _sortedEndpointCache!;
  }

  int _compareEndpointNames(
    AiExposureProxyEndpoint left,
    AiExposureProxyEndpoint right,
  ) {
    final result = left.displayName.toLowerCase().compareTo(
      right.displayName.toLowerCase(),
    );
    return result == 0 ? left.url.compareTo(right.url) : result;
  }

  void _invalidateEndpointSortCache() {
    _sortedEndpointCache = null;
    _sortedEndpointCacheSort = null;
  }

  void _updateEndpoint(String url, AiExposureProxyEndpoint updated) {
    final index = _endpoints.indexWhere((item) => item.url == url);
    if (index < 0) return;
    setState(() {
      _endpoints[index] = updated;
      _invalidateEndpointSortCache();
    });
  }

  Widget _buildSettingsPanel(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = openHandTextResolver(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                _enabled ? Icons.vpn_lock_rounded : Icons.public_rounded,
                color: _enabled ? colors.primary : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text(zh: '代理底层网络请求', en: 'Proxy network requests'),
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      text(
                        zh: '覆盖资产发现、目标探测、主动验证和 GPT 辅助请求。',
                        en: 'Covers discovery, probing, validation, and assisted requests.',
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Switch(
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final strategy = DropdownButtonFormField<AiExposureProxyStrategy>(
                initialValue: _strategy,
                decoration: InputDecoration(
                  labelText: text(zh: '代理策略', en: 'Proxy strategy'),
                  border: const OutlineInputBorder(),
                ),
                items: AiExposureProxyStrategy.values
                    .map(
                      (item) => DropdownMenuItem(
                        value: item,
                        child: Text(_strategyLabel(item, text)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) setState(() => _strategy = value);
                },
              );
              final bypass = Row(
                children: [
                  Checkbox(
                    value: _bypassLocal,
                    onChanged: (value) =>
                        setState(() => _bypassLocal = value == true),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      text(zh: '本地与私网直连', en: 'Bypass local networks'),
                    ),
                  ),
                ],
              );
              if (constraints.maxWidth < 680) {
                return Column(
                  children: [strategy, const SizedBox(height: 8), bypass],
                );
              }
              return Row(
                children: [
                  Expanded(child: strategy),
                  const SizedBox(width: 14),
                  Expanded(child: bypass),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  text(
                    zh: '每 ${_rotationEvery.round()} 次请求轮换',
                    en: 'Rotate every ${_rotationEvery.round()} requests',
                  ),
                  style: theme.textTheme.labelLarge,
                ),
              ),
              Text('${_rotationEvery.round()}'),
            ],
          ),
          Slider(
            value: _rotationEvery,
            min: 1,
            max: 100,
            divisions: 99,
            label: '${_rotationEvery.round()}',
            onChanged: _strategy == AiExposureProxyStrategy.roundRobin
                ? (value) => setState(() => _rotationEvery = value)
                : null,
          ),
          Divider(height: 20, color: colors.outlineVariant),
          LayoutBuilder(
            builder: (context, constraints) {
              final toggle = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: _inspectionEnabled,
                    onChanged: (value) =>
                        setState(() => _inspectionEnabled = value),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          text(zh: '定时巡检', en: 'Scheduled inspection'),
                          style: theme.textTheme.labelLarge,
                        ),
                        Text(
                          text(
                            zh: '自动更新节点连通性与延迟趋势',
                            en: 'Refresh connectivity and latency trends',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
              final interval = SizedBox(
                width: 180,
                child: DropdownButtonFormField<int>(
                  initialValue: _normalizedInspectionInterval,
                  decoration: InputDecoration(
                    labelText: text(zh: '巡检周期', en: 'Interval'),
                    border: const OutlineInputBorder(),
                  ),
                  items: _kInspectionIntervals
                      .map(
                        (minutes) => DropdownMenuItem<int>(
                          value: minutes,
                          child: Text(_intervalLabel(minutes, text)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: _inspectionEnabled
                      ? (value) {
                          if (value != null) {
                            setState(() => _inspectionIntervalMinutes = value);
                          }
                        }
                      : null,
                ),
              );
              final concurrency = SizedBox(
                width: 180,
                child: DropdownButtonFormField<int>(
                  initialValue: _normalizedInspectionConcurrency,
                  decoration: InputDecoration(
                    labelText: text(zh: '测试线程', en: 'Test threads'),
                    border: const OutlineInputBorder(),
                  ),
                  items: _kInspectionConcurrencyOptions
                      .map(
                        (value) => DropdownMenuItem<int>(
                          value: value,
                          child: Text('$value'),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: _inspectionEnabled
                      ? (value) {
                          if (value != null) {
                            setState(() => _inspectionConcurrency = value);
                          }
                        }
                      : null,
                ),
              );
              final inspect = FilledButton.tonalIcon(
                onPressed: _inspectionBusy
                    ? _cancelInspection
                    : !_endpoints.any((item) => item.enabled)
                    ? null
                    : _inspectAll,
                icon: _inspectionBusy
                    ? const Icon(Icons.stop_rounded)
                    : const Icon(Icons.network_check_rounded),
                label: Text(
                  _inspectionBusy
                      ? text(zh: '停止巡检', en: 'Stop inspection')
                      : text(zh: '一键巡检', en: 'Inspect all'),
                ),
              );
              if (constraints.maxWidth < 760) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    toggle,
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [interval, concurrency, inspect],
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: toggle),
                  const SizedBox(width: 12),
                  interval,
                  const SizedBox(width: 10),
                  concurrency,
                  const SizedBox(width: 10),
                  inspect,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEndpointToolbar(BuildContext context) {
    final text = openHandTextResolver(context);
    final actions = ServiceDialogIconActions(
      children: [
        IconButton.filledTonal(
          tooltip: text(zh: '添加代理', en: 'Add proxy'),
          onPressed: _busy || _inspectionBusy ? null : _addEndpoint,
          icon: const Icon(Icons.add_rounded),
        ),
        IconButton.filledTonal(
          tooltip: text(zh: '批量导入', en: 'Bulk import'),
          onPressed: _busy || _inspectionBusy ? null : _import,
          icon: const Icon(Icons.upload_file_rounded),
        ),
        IconButton.filledTonal(
          tooltip: text(zh: '导出代理池', en: 'Export pool'),
          onPressed: _endpoints.isEmpty || _busy || _inspectionBusy
              ? null
              : _exportAll,
          icon: const Icon(Icons.download_rounded),
        ),
        PopupMenuButton<_ProxySort>(
          tooltip: text(zh: '排序节点', en: 'Sort nodes'),
          enabled: !_busy && !_inspectionBusy,
          initialValue: _sort,
          onSelected: (value) => setState(() {
            _sort = value;
            _invalidateEndpointSortCache();
          }),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: _ProxySort.nameAscending,
              child: Text(text(zh: '按名称升序', en: 'Name ascending')),
            ),
            PopupMenuItem(
              value: _ProxySort.latencyAscending,
              child: Text(text(zh: '按延迟升序', en: 'Latency ascending')),
            ),
            PopupMenuItem(
              value: _ProxySort.latencyDescending,
              child: Text(text(zh: '按延迟降序', en: 'Latency descending')),
            ),
          ],
          icon: const Icon(Icons.sort_rounded),
        ),
      ],
    );
    return Row(
      children: [
        Expanded(
          child: Text(
            text(
              zh: '${_endpoints.length} 个节点 · 默认按名称排序',
              en: '${_endpoints.length} nodes · sorted by name',
            ),
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        actions,
      ],
    );
  }

  int get _normalizedInspectionInterval =>
      _kInspectionIntervals.contains(_inspectionIntervalMinutes)
      ? _inspectionIntervalMinutes
      : 30;

  int get _normalizedInspectionConcurrency =>
      _kInspectionConcurrencyOptions.contains(_inspectionConcurrency)
      ? _inspectionConcurrency
      : 8;

  Future<void> _addEndpoint() async {
    try {
      final endpoint = await _showEndpointEditor(context);
      if (endpoint == null || !mounted) return;
      if (_endpoints.any((item) => item.url == endpoint.url)) {
        throw const FormatException('该代理已存在。');
      }
      if (_endpoints.length >= _kMaxProxyEndpoints) {
        throw const FormatException('代理池已达到 10000 条上限。');
      }
      setState(() {
        _endpoints.add(endpoint);
        _invalidateEndpointSortCache();
      });
    } catch (error) {
      showOpenHandErrorSnack(context, '$error');
    }
  }

  Future<void> _editEndpoint(AiExposureProxyEndpoint endpoint) async {
    final updated = await _showEndpointEditor(context, initial: endpoint);
    if (updated == null || !mounted) return;
    if (_endpoints.any(
      (item) => item.url == updated.url && item.url != endpoint.url,
    )) {
      showOpenHandErrorSnack(context, '该代理已存在。');
      return;
    }
    _updateEndpoint(
      endpoint.url,
      updated.copyWith(enabled: endpoint.enabled, samples: endpoint.samples),
    );
  }

  Future<void> _testEndpoint(String url) async {
    if (_inspectionRunning || _testingUrls.contains(url)) return;
    final endpoint = _endpoints.where((item) => item.url == url).firstOrNull;
    if (endpoint == null) return;
    setState(() => _testingUrls.add(url));
    final sample = await _probe.inspect(endpoint);
    if (!mounted) return;
    _pendingSamples[url] = sample;
    _testingUrls.remove(url);
    _flushProbeResults();
  }

  Future<void> _inspectAll() async {
    if (_inspectionBusy || _inspectionRunning || _testingUrls.isNotEmpty) {
      return;
    }
    final endpoints = _endpoints
        .where((endpoint) => endpoint.enabled)
        .toList(growable: false);
    if (endpoints.isEmpty) return;
    final generation = ++_inspectionGeneration;
    _inspectionRunning = true;
    setState(() {
      _inspectionBusy = true;
      _inspectionCompleted = 0;
      _inspectionTotal = endpoints.length;
      _testingUrls.addAll(endpoints.map((endpoint) => endpoint.url));
    });
    var cursor = 0;
    Future<void> worker() async {
      while (mounted && generation == _inspectionGeneration) {
        final index = cursor++;
        if (index >= endpoints.length) return;
        final endpoint = endpoints[index];
        final sample = await _probe.inspect(endpoint);
        if (!mounted || generation != _inspectionGeneration) return;
        _pendingSamples[endpoint.url] = sample;
        _testingUrls.remove(endpoint.url);
        _inspectionCompleted++;
        _scheduleProbeResultFlush();
      }
    }

    try {
      await Future.wait<void>(
        List<Future<void>>.generate(
          endpoints.length < _normalizedInspectionConcurrency
              ? endpoints.length
              : _normalizedInspectionConcurrency,
          (_) => worker(),
        ),
      );
      if (!mounted || generation != _inspectionGeneration) return;
      _resultFlushTimer?.cancel();
      _resultFlushTimer = null;
      _flushProbeResults();
      setState(() => _inspectionBusy = false);
    } finally {
      _inspectionRunning = false;
      if (mounted && generation != _inspectionGeneration) {
        setState(() => _inspectionBusy = false);
      }
    }
  }

  void _scheduleProbeResultFlush() {
    if (_resultFlushTimer?.isActive == true) return;
    _resultFlushTimer = Timer(_kProbeResultFlushDelay, () {
      _resultFlushTimer = null;
      _flushProbeResults();
    });
  }

  void _cancelInspection() {
    if (!_inspectionBusy) return;
    _inspectionGeneration++;
    _resultFlushTimer?.cancel();
    _resultFlushTimer = null;
    _flushProbeResults();
    if (!mounted) return;
    setState(() => _testingUrls.clear());
  }

  void _flushProbeResults() {
    if (!mounted || _pendingSamples.isEmpty) return;
    final samples = Map<String, AiExposureProxyProbeSample>.of(_pendingSamples);
    _pendingSamples.clear();
    final indexes = <String, int>{
      for (var index = 0; index < _endpoints.length; index++)
        _endpoints[index].url: index,
    };
    setState(() {
      _invalidateEndpointSortCache();
      for (final entry in samples.entries) {
        final index = indexes[entry.key];
        if (index != null) {
          _endpoints[index] = _endpoints[index].withSample(entry.value);
        }
      }
    });
  }

  Future<void> _import() async {
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'Proxy', extensions: <String>['txt', 'json']),
      ],
    );
    if (file == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final source = File(file.path);
      if (await source.length() > _kMaxProxyImportBytes) {
        throw const FormatException('代理文件不能超过 4 MB。');
      }
      final imported = _proxyEndpoints(await source.readAsString());
      final merged = <String, AiExposureProxyEndpoint>{
        for (final endpoint in _endpoints) endpoint.url: endpoint,
      };
      var accepted = 0;
      for (final endpoint in imported.endpoints) {
        if (merged.length >= _kMaxProxyEndpoints) break;
        if (!merged.containsKey(endpoint.url)) accepted++;
        merged[endpoint.url] = endpoint;
      }
      if (!mounted) return;
      setState(() {
        _endpoints = merged.values.toList(growable: true);
        _invalidateEndpointSortCache();
      });
      showOpenHandSuccessSnack(
        context,
        imported.invalid == 0
            ? '已新增 $accepted 个代理。'
            : '已新增 $accepted 个代理，忽略 ${imported.invalid} 条无效记录。',
      );
    } catch (error) {
      if (mounted) showOpenHandErrorSnack(context, '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportAll() async {
    final location = await getSaveLocation(
      suggestedName: 'openhand-ai-exposure-proxies.json',
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'JSON', extensions: <String>['json']),
      ],
    );
    if (location == null) return;
    final payload = const JsonEncoder.withIndent('  ')
        .convert(<String, Object?>{
          'type': 'openhand_ai_exposure_proxy_pool',
          'version': 2,
          'enabled': _enabled,
          'strategy': _strategy.id,
          'rotationEvery': _rotationEvery.round(),
          'bypassLocal': _bypassLocal,
          'inspectionEnabled': _inspectionEnabled,
          'inspectionIntervalMinutes': _normalizedInspectionInterval,
          'inspectionConcurrency': _normalizedInspectionConcurrency,
          'endpoints': _endpoints
              .map((endpoint) => endpoint.toJson())
              .toList(growable: false),
        });
    await writeFileAtomically(File(location.path), payload);
    if (mounted) showOpenHandSuccessSnack(context, '代理池已导出。');
  }

  Future<void> _exportOne(AiExposureProxyEndpoint endpoint) async {
    final location = await getSaveLocation(
      suggestedName: 'openhand-ai-exposure-proxy.json',
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'JSON', extensions: <String>['json']),
      ],
    );
    if (location == null) return;
    final payload = const JsonEncoder.withIndent('  ').convert(
      <String, Object?>{
        'type': 'openhand_ai_exposure_proxy',
        'version': 2,
        ...endpoint.toJson(),
      },
    );
    await writeFileAtomically(File(location.path), payload);
    if (mounted) showOpenHandSuccessSnack(context, '代理配置已导出。');
  }

  Future<void> _save() async {
    final activeCount = _endpoints.where((endpoint) => endpoint.enabled).length;
    if ((_enabled || _inspectionEnabled) && activeCount == 0) {
      showOpenHandErrorSnack(context, '请至少启用一个代理节点。');
      return;
    }
    setState(() => _busy = true);
    final updated = await context
        .read<ServicesController>()
        .updateProxyConfiguration(
          AiExposureProxyConfiguration(
            enabled: _enabled,
            strategy: _strategy,
            rotationEvery: _rotationEvery.round(),
            bypassLocal: _bypassLocal,
            endpoints: List<AiExposureProxyEndpoint>.unmodifiable(_endpoints),
            inspectionEnabled: _inspectionEnabled,
            inspectionIntervalMinutes: _normalizedInspectionInterval,
            inspectionConcurrency: _normalizedInspectionConcurrency,
          ),
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (updated) Navigator.of(context).maybePop();
  }
}

Future<AiExposureProxyEndpoint?> _showEndpointEditor(
  BuildContext context, {
  AiExposureProxyEndpoint? initial,
}) {
  return showAnimatedDialog<AiExposureProxyEndpoint>(
    context: context,
    builder: (dialogContext) => buildOpenHandDialog(
      maxWidth: kOpenHandDialogWidthCompact,
      child: _ProxyEndpointEditor(
        initial: initial,
        onSubmit: (endpoint) => Navigator.of(dialogContext).pop(endpoint),
        onCancel: () => Navigator.of(dialogContext).maybePop(),
      ),
    ),
  );
}

class _ProxyEndpointEditor extends StatefulWidget {
  const _ProxyEndpointEditor({
    required this.initial,
    required this.onSubmit,
    required this.onCancel,
  });

  final AiExposureProxyEndpoint? initial;
  final ValueChanged<AiExposureProxyEndpoint> onSubmit;
  final VoidCallback onCancel;

  @override
  State<_ProxyEndpointEditor> createState() => _ProxyEndpointEditorState();
}

class _ProxyEndpointEditorState extends State<_ProxyEndpointEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _username;
  late final TextEditingController _password;
  String _scheme = 'http';
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    final uri = initial == null ? null : Uri.parse(initial.url);
    _name = TextEditingController(text: initial?.name ?? '');
    _host = TextEditingController(text: uri?.host ?? '');
    _port = TextEditingController(text: uri?.port.toString() ?? '8080');
    _username = TextEditingController(
      text: uri == null || uri.userInfo.isEmpty
          ? ''
          : Uri.decodeComponent(uri.userInfo.split(':').first),
    );
    _password = TextEditingController(
      text: uri == null || !uri.userInfo.contains(':')
          ? ''
          : Uri.decodeComponent(
              uri.userInfo.substring(uri.userInfo.indexOf(':') + 1),
            ),
    );
    _scheme = uri?.scheme ?? 'http';
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    final editing = widget.initial != null;
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    editing
                        ? text(zh: '编辑代理节点', en: 'Edit proxy node')
                        : text(zh: '新增代理节点', en: 'Add proxy node'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: widget.onCancel,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              decoration: InputDecoration(
                labelText: text(zh: '节点名称', en: 'Node name'),
                hintText: text(zh: '例如：香港线路 1', en: 'e.g. Hong Kong 1'),
                border: const OutlineInputBorder(),
              ),
              maxLength: 80,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                SizedBox(
                  width: 118,
                  child: DropdownButtonFormField<String>(
                    initialValue: _scheme,
                    decoration: InputDecoration(
                      labelText: text(zh: '协议', en: 'Scheme'),
                      border: const OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'http', child: Text('HTTP')),
                      DropdownMenuItem(value: 'https', child: Text('HTTPS')),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _scheme = value);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _host,
                    decoration: InputDecoration(
                      labelText: text(zh: '主机', en: 'Host'),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? text(zh: '请输入主机', en: 'Enter a host')
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 110,
                  child: TextFormField(
                    controller: _port,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: text(zh: '端口', en: 'Port'),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final port = int.tryParse(value?.trim() ?? '');
                      return port == null || port < 1 || port > 65535
                          ? text(zh: '端口无效', en: 'Invalid port')
                          : null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _username,
              decoration: InputDecoration(
                labelText: text(zh: '用户名（可选）', en: 'Username (optional)'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _password,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: text(zh: '密码（可选）', en: 'Password (optional)'),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _obscurePassword
                      ? text(zh: '显示密码', en: 'Show password')
                      : text(zh: '隐藏密码', en: 'Hide password'),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OpenHandDialogActionButton.secondary(
                  onPressed: widget.onCancel,
                  label: text(zh: '取消', en: 'Cancel'),
                ),
                const SizedBox(width: 8),
                OpenHandDialogActionButton.primary(
                  icon: Icons.check_rounded,
                  onPressed: _submit,
                  label: editing
                      ? text(zh: '保存修改', en: 'Save changes')
                      : text(zh: '添加节点', en: 'Add node'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final username = _username.text.trim();
    final password = _password.text;
    final userInfo = username.isEmpty
        ? ''
        : '${Uri.encodeComponent(username)}:${Uri.encodeComponent(password)}@';
    final rawHost = _host.text.trim();
    final host = rawHost.contains(':') && !rawHost.startsWith('[')
        ? '[$rawHost]'
        : rawHost;
    try {
      final endpoint = AiExposureProxyEndpoint.parse(
        '$_scheme://$userInfo$host:${_port.text.trim()}',
      ).copyWith(name: _name.text.trim());
      widget.onSubmit(endpoint);
    } on FormatException catch (error) {
      showOpenHandErrorSnack(context, error.message);
    }
  }
}

class _ProxyEndpointCard extends StatelessWidget {
  const _ProxyEndpointCard({
    super.key,
    required this.endpoint,
    required this.selections,
    required this.testing,
    required this.busy,
    required this.onEnabledChanged,
    required this.onTest,
    required this.onExport,
    required this.onEdit,
    required this.onDelete,
  });

  final AiExposureProxyEndpoint endpoint;
  final int? selections;
  final bool testing;
  final bool busy;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback onTest;
  final VoidCallback onExport;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = openHandTextResolver(context);
    final sample = endpoint.latestSample;
    final tone = _proxyHealthTone(context, endpoint, testing);
    final details = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          duration: openHandMotionDuration(
            context,
            const Duration(milliseconds: 260),
          ),
          curve: Curves.easeOutBack,
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: tone.color.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: AnimatedSwitcher(
            duration: openHandMotionDuration(
              context,
              const Duration(milliseconds: 220),
            ),
            child: testing
                ? SizedBox.square(
                    key: const ValueKey<String>('testing'),
                    dimension: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: tone.color,
                    ),
                  )
                : Icon(
                    tone.icon,
                    key: ValueKey<IconData>(tone.icon),
                    size: 19,
                    color: tone.color,
                  ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                endpoint.name.trim().isEmpty
                    ? endpoint.maskedUrl
                    : '${endpoint.name} · ${endpoint.maskedUrl}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 7,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _ProxyMetric(
                    icon: tone.icon,
                    label: tone.label,
                    color: tone.color,
                  ),
                  if (sample?.latencyMs != null)
                    _ProxyMetric(
                      icon: Icons.speed_rounded,
                      label: '${sample!.latencyMs} ms',
                      color: tone.color,
                    ),
                  if (selections != null)
                    _ProxyMetric(
                      icon: Icons.route_outlined,
                      label: text(
                        zh: '请求 $selections',
                        en: '$selections requests',
                      ),
                      color: colors.onSurfaceVariant,
                    ),
                  if (sample != null)
                    _ProxyMetric(
                      icon: Icons.schedule_rounded,
                      label: _timeLabel(sample.checkedAt),
                      color: colors.onSurfaceVariant,
                    ),
                ],
              ),
              if (sample?.error?.isNotEmpty == true) ...[
                const SizedBox(height: 6),
                Text(
                  sample!.error!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: OpenHandStatusColors.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
    final chart = _ProxyLatencyChart(endpoint: endpoint);
    final actions = ServiceDialogIconActions(
      children: [
        Tooltip(
          message: endpoint.enabled
              ? text(zh: '禁用此节点', en: 'Disable node')
              : text(zh: '启用此节点', en: 'Enable node'),
          child: Switch(
            value: endpoint.enabled,
            onChanged: busy ? null : onEnabledChanged,
          ),
        ),
        IconButton(
          tooltip: text(zh: '测试连通性与延迟', en: 'Test connectivity'),
          onPressed: busy || testing ? null : onTest,
          icon: testing
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.speed_rounded),
        ),
        IconButton(
          tooltip: text(zh: '编辑代理配置', en: 'Edit proxy settings'),
          onPressed: busy ? null : onEdit,
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: text(zh: '导出此代理', en: 'Export proxy'),
          onPressed: busy ? null : onExport,
          icon: const Icon(Icons.file_download_outlined),
        ),
        IconButton(
          tooltip: text(zh: '移除代理', en: 'Remove proxy'),
          onPressed: busy ? null : onDelete,
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
    );
    return AnimatedContainer(
      duration: openHandMotionDuration(
        context,
        const Duration(milliseconds: 260),
      ),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: endpoint.enabled
            ? colors.surfaceContainerHighest.withValues(alpha: 0.26)
            : colors.surfaceContainerLow.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: sample?.reachable == true
              ? tone.color.withValues(alpha: 0.36)
              : colors.outlineVariant,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 820) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                details,
                const SizedBox(height: 10),
                chart,
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: actions,
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: details),
              const SizedBox(width: 14),
              SizedBox(width: 190, child: chart),
              const SizedBox(width: 12),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _ProxyLatencyChart extends StatelessWidget {
  const _ProxyLatencyChart({required this.endpoint});

  final AiExposureProxyEndpoint endpoint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final values = endpoint.samples
        .where((sample) => sample.reachable)
        .map((sample) => sample.latencyMs!.toDouble())
        .toList(growable: false);
    final revision =
        endpoint.latestSample?.checkedAt.microsecondsSinceEpoch ?? 0;
    return SizedBox(
      height: 70,
      child: TweenAnimationBuilder<double>(
        key: ValueKey<int>(revision),
        tween: Tween<double>(begin: 0, end: 1),
        duration: openHandMotionDuration(
          context,
          const Duration(milliseconds: 460),
        ),
        curve: Curves.easeOutBack,
        builder: (context, progress, _) {
          final scale = progress.clamp(0.0, 1.0);
          return CustomPaint(
            painter: OpenHandSmoothLineChartPainter(
              series: <OpenHandChartSeries>[
                OpenHandChartSeries(
                  label: 'latency',
                  values: values.map((value) => value * scale).toList(),
                  color: colors.primary,
                ),
              ],
              gridColor: colors.outlineVariant.withValues(alpha: 0.55),
              labelColor: colors.onSurfaceVariant,
              emptyLabel: openHandLocalizedText(
                context,
                zh: '暂无延迟样本',
                en: 'No latency samples',
              ),
              valueSuffix: ' ms',
              textDirection: Directionality.of(context),
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _ProxyMetric extends StatelessWidget {
  const _ProxyMetric({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 4),
      Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    ],
  );
}

({Color color, IconData icon, String label}) _proxyHealthTone(
  BuildContext context,
  AiExposureProxyEndpoint endpoint,
  bool testing,
) {
  final text = openHandTextResolver(context);
  if (testing) {
    return (
      color: OpenHandStatusColors.info,
      icon: Icons.sync_rounded,
      label: text(zh: '检测中', en: 'Testing'),
    );
  }
  if (!endpoint.enabled) {
    return (
      color: Theme.of(context).colorScheme.outline,
      icon: Icons.pause_circle_outline_rounded,
      label: text(zh: '已禁用', en: 'Disabled'),
    );
  }
  final sample = endpoint.latestSample;
  if (sample == null) {
    return (
      color: Theme.of(context).colorScheme.outline,
      icon: Icons.help_outline_rounded,
      label: text(zh: '未检测', en: 'Unchecked'),
    );
  }
  if (!sample.reachable) {
    return (
      color: OpenHandStatusColors.error,
      icon: Icons.cloud_off_outlined,
      label: text(zh: '不可用', en: 'Unavailable'),
    );
  }
  if (sample.latencyMs! <= 350) {
    return (
      color: OpenHandStatusColors.success,
      icon: Icons.check_circle_outline_rounded,
      label: text(zh: '畅通', en: 'Healthy'),
    );
  }
  return (
    color: OpenHandStatusColors.warning,
    icon: Icons.warning_amber_rounded,
    label: text(zh: '高延迟', en: 'High latency'),
  );
}

({List<AiExposureProxyEndpoint> endpoints, int invalid}) _proxyEndpoints(
  String content,
) {
  final trimmed = content.trim();
  final endpoints = <AiExposureProxyEndpoint>[];
  var invalid = 0;
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    final decoded = jsonDecode(trimmed);
    final values = decoded is Map
        ? decoded['endpoints'] is List
              ? decoded['endpoints'] as List
              : <Object?>[decoded]
        : decoded is List
        ? decoded
        : const <Object?>[];
    if (values.isEmpty) throw const FormatException('代理 JSON 配置无效。');
    for (final value in values) {
      try {
        endpoints.add(AiExposureProxyEndpoint.fromJson(value));
      } on FormatException {
        invalid++;
      }
    }
  } else {
    for (final line in const LineSplitter().convert(content)) {
      final value = line.trim();
      if (value.isEmpty || value.startsWith('#')) continue;
      try {
        endpoints.add(AiExposureProxyEndpoint.parse(value));
      } on FormatException {
        invalid++;
      }
    }
  }
  if (endpoints.isEmpty && invalid > 0) {
    throw const FormatException('未找到有效的代理地址。');
  }
  return (endpoints: endpoints, invalid: invalid);
}

String _strategyLabel(
  AiExposureProxyStrategy strategy,
  String Function({required String zh, required String en}) text,
) => switch (strategy) {
  AiExposureProxyStrategy.fixed => text(zh: '固定首选', en: 'Fixed'),
  AiExposureProxyStrategy.roundRobin => text(zh: '顺序轮询', en: 'Round robin'),
  AiExposureProxyStrategy.random => text(zh: '均衡随机', en: 'Random'),
  AiExposureProxyStrategy.stickyHost => text(zh: '目标粘性', en: 'Sticky host'),
};

String _intervalLabel(
  int minutes,
  String Function({required String zh, required String en}) text,
) => minutes < 60
    ? text(zh: '$minutes 分钟', en: '$minutes min')
    : text(zh: '${minutes ~/ 60} 小时', en: '${minutes ~/ 60} hr');

String _timeLabel(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}
