import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/list_removal_transition.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_ops_charts.dart';
import '../../../shared/ui/openhand_reveal_switcher.dart';
import '../../../shared/ui/openhand_safe_scrollbar.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/ui/openhand_tooltip_dismissal.dart';
import '../../../shared/ui/openhand_trailing_toolbar.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/localized_text.dart';
import '../../../shared/util/timer_safety.dart';
import '../model/ai_exposure_models.dart';
import '../service/ai_exposure_proxy_probe.dart';
import '../services_controller.dart';
import 'service_dialog_controls.dart';

const int _kMaxProxyImportBytes = 4 * 1024 * 1024;
const int _kMaxProxyImportRecords = 20000;
const int _kMaxProxyEndpoints = 10000;
const int _kProxyHighLatencyThresholdMs = 350;
const double _kProxyEndpointListMaxHeight = 420;
const Duration _kProbeResultFlushDelay = Duration(milliseconds: 80);
const List<int> _kInspectionIntervals = <int>[5, 15, 30, 60, 180, 360];
const List<int> _kInspectionConcurrencyOptions = <int>[1, 2, 4, 8, 16, 32];
const XTypeGroup _kProxyJsonFileType = XTypeGroup(
  label: 'JSON',
  extensions: <String>['json'],
);

enum _ProxySort { nameAscending, latencyAscending, latencyDescending }

enum _ProxyEndpointHealth {
  disabled,
  unchecked,
  unavailable,
  forwardingFailed,
  healthy,
  highLatency,
}

enum _ProxyCleanup { unavailable, highLatency, abnormal }

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
  final ScrollController _endpointScrollController = ScrollController();
  final Set<String> _testingUrls = <String>{};
  final Set<String> _selectedUrls = <String>{};
  final Set<String> _removingUrls = <String>{};
  final Map<String, AiExposureProxyProbeSample> _pendingSamples =
      <String, AiExposureProxyProbeSample>{};
  late final ServicesController _servicesController;
  late bool _enabled;
  late bool _bypassLocal;
  late bool _inspectionEnabled;
  late int _inspectionIntervalMinutes;
  late int _inspectionConcurrency;
  late AiExposureProxyStrategy _strategy;
  late double _rotationEvery;
  late List<AiExposureProxyEndpoint> _endpoints;
  Map<String, int>? _endpointIndexCache;
  _ProxySort _sort = _ProxySort.nameAscending;
  List<AiExposureProxyEndpoint>? _sortedEndpointCache;
  _ProxySort? _sortedEndpointCacheSort;
  Timer? _resultFlushTimer;
  bool _pendingSamplesHandledByController = false;
  bool _busy = false;
  bool _inspectionBusy = false;
  bool _inspectionRunning = false;
  bool _selectionMode = false;
  int _inspectionCompleted = 0;
  int _inspectionTotal = 0;
  int _inspectionGeneration = 0;

  @override
  void initState() {
    super.initState();
    _servicesController = context.read<ServicesController>();
    final configuration = _servicesController.proxyConfiguration;
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
    if (_inspectionRunning) _servicesController.cancelProxyInspection();
    _resultFlushTimer?.cancel();
    _endpointScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = openHandTextResolver(context);
    final controller = context.watch<ServicesController>();
    final status = controller.proxyStatus;
    final controllerInspectionBusy = controller.proxyInspectionBusy;
    final activeCount = _endpoints.where((endpoint) => endpoint.enabled).length;
    final route = _enabled && activeCount > 0
        ? AiExposureProxyRoute.pool
        : controller.systemProxyAvailable
        ? AiExposureProxyRoute.system
        : AiExposureProxyRoute.direct;
    final statusStatistics = <String, AiExposureProxyUsageStatistics>{
      for (final item
          in status?.endpoints ?? const <AiExposureProxyEndpointStatus>[])
        item.id: item.statistics,
    };
    final visibleEndpoints = _sortedEndpoints();
    final visibleEndpointIndexByKey = <Key, int>{
      for (var index = 0; index < visibleEndpoints.length; index++)
        ValueKey<String>(visibleEndpoints[index].url): index,
    };
    final endpointTooltipsVisible =
        !_busy &&
        !_inspectionBusy &&
        !controllerInspectionBusy &&
        _testingUrls.isEmpty &&
        _removingUrls.isEmpty;
    return ServiceDialogInteractionTheme(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        child: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                physics: openHandDialogAwareScrollPhysics(context),
                slivers: [
                  SliverList.list(
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
                                    text(
                                      zh: '网络代理与代理池',
                                      en: 'Network proxy pool',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleLarge,
                                  ),
                                  Text(
                                    switch (route) {
                                      AiExposureProxyRoute.pool => text(
                                        zh: '$activeCount 个启用节点 · ${_strategyLabel(_strategy, text)}',
                                        en: '$activeCount active · ${_strategyLabel(_strategy, text)}',
                                      ),
                                      AiExposureProxyRoute.system => text(
                                        zh: '当前回退系统代理',
                                        en: 'Falling back to system proxy',
                                      ),
                                      AiExposureProxyRoute.direct => text(
                                        zh: '当前使用 DIRECT 直连',
                                        en: 'Using DIRECT connection',
                                      ),
                                    },
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
                        actions: ServiceDialogHeaderIconButton(
                          tooltip: MaterialLocalizations.of(
                            context,
                          ).closeButtonTooltip,
                          onPressed: _busy ? null : _closeDialog,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _ProxyPoolOverview(
                        endpoints: _endpoints,
                        statusStatistics: statusStatistics,
                        inFlight: status?.inFlight ?? 0,
                      ),
                      const SizedBox(height: 14),
                      _buildSettingsPanel(
                        context,
                        controllerInspectionBusy: controllerInspectionBusy,
                        activeCount: activeCount,
                        systemProxyAvailable: controller.systemProxyAvailable,
                      ),
                      const SizedBox(height: 14),
                      _buildEndpointToolbar(
                        context,
                        controllerInspectionBusy: controllerInspectionBusy,
                      ),
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
                    ],
                  ),
                  SliverToBoxAdapter(
                    child: _endpoints.isEmpty
                        ? SizedBox(
                            height: 160,
                            child: Center(
                              child: Text(
                                text(
                                  zh: '代理池为空，可手工添加或批量导入 TXT/JSON。',
                                  en: 'Add a proxy or import a TXT/JSON pool.',
                                ),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          )
                        : ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxHeight: _kProxyEndpointListMaxHeight,
                            ),
                            child: OpenHandSafeScrollbar(
                              controller: _endpointScrollController,
                              thumbVisibility: true,
                              thickness: 5,
                              radius: const Radius.circular(99),
                              interactive: true,
                              scrollbarOrientation: ScrollbarOrientation.right,
                              child: TooltipVisibility(
                                visible: endpointTooltipsVisible,
                                child: ListView.builder(
                                  controller: _endpointScrollController,
                                  primary: false,
                                  shrinkWrap: true,
                                  physics: openHandDialogAwareScrollPhysics(
                                    context,
                                  ),
                                  itemCount: visibleEndpoints.length,
                                  findChildIndexCallback: (key) =>
                                      visibleEndpointIndexByKey[key],
                                  itemBuilder: (context, index) {
                                    final endpoint = visibleEndpoints[index];
                                    return OpenHandListRemovalTransition(
                                      key: ValueKey<String>(endpoint.url),
                                      collapsed: _removingUrls.contains(
                                        endpoint.url,
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        child: _ProxyEndpointCard(
                                          endpoint: endpoint,
                                          statistics:
                                              statusStatistics[endpoint
                                                  .runtimeId] ??
                                              endpoint.statistics,
                                          testing: _testingUrls.contains(
                                            endpoint.url,
                                          ),
                                          busy:
                                              _busy ||
                                              _inspectionBusy ||
                                              _removingUrls.isNotEmpty,
                                          selectionMode: _selectionMode,
                                          selected: _selectedUrls.contains(
                                            endpoint.url,
                                          ),
                                          onSelectedChanged: (selected) =>
                                              setState(() {
                                                if (selected) {
                                                  _selectedUrls.add(
                                                    endpoint.url,
                                                  );
                                                } else {
                                                  _selectedUrls.remove(
                                                    endpoint.url,
                                                  );
                                                }
                                              }),
                                          onEnabledChanged: (enabled) =>
                                              unawaited(
                                                _setEndpointEnabled(
                                                  endpoint.url,
                                                  enabled,
                                                ),
                                              ),
                                          onTest: () =>
                                              _testEndpoint(endpoint.url),
                                          onDetails: () => _showEndpointDetails(
                                            endpoint,
                                            statusStatistics[endpoint
                                                    .runtimeId] ??
                                                endpoint.statistics,
                                          ),
                                          onExport: () => _exportOne(endpoint),
                                          onEdit: () => _editEndpoint(endpoint),
                                          onDelete: () => unawaited(
                                            _confirmDeleteEndpoints(<String>{
                                              endpoint.url,
                                            }),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 14),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.outlineVariant)),
              ),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: kOpenHandDialogActionSpacing,
                runSpacing: kOpenHandDialogActionSpacing,
                children: [
                  OpenHandDialogActionButton.secondary(
                    onPressed: _busy ? null : _closeDialog,
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
            ),
          ],
        ),
      ),
    );
  }

  void _closeDialog() {
    dismissOpenHandTooltipsSafely(debugLabel: '关闭代理池弹窗前收起工具提示');
    _cancelInspection();
    Navigator.of(context).maybePop();
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

  void _replaceEndpointLocally(String url, AiExposureProxyEndpoint updated) {
    final index = _endpoints.indexWhere((item) => item.url == url);
    if (index < 0) return;
    setState(() {
      _endpoints[index] = updated;
      if (url != updated.url) _endpointIndexCache = null;
      _invalidateEndpointSortCache();
    });
  }

  void _replaceEndpointsLocally(List<AiExposureProxyEndpoint> endpoints) {
    _endpoints = List<AiExposureProxyEndpoint>.of(endpoints);
    _endpointIndexCache = null;
    final urls = _endpoints.map((endpoint) => endpoint.url).toSet();
    _selectedUrls.retainAll(urls);
    _invalidateEndpointSortCache();
    if (!_endpoints.any((endpoint) => endpoint.enabled)) {
      _inspectionEnabled = false;
    }
    if (_selectedUrls.isEmpty) _selectionMode = false;
  }

  Future<bool> _persistEndpoints(
    List<AiExposureProxyEndpoint> endpoints,
  ) async {
    final controller = context.read<ServicesController>();
    final updated = await controller.updateProxyEndpoints(endpoints);
    if (mounted && !updated) {
      showOpenHandErrorSnack(context, controller.errorMessage ?? '保存代理节点失败。');
    }
    return updated;
  }

  Future<void> _setEndpointEnabled(String url, bool enabled) async {
    if (_busy) return;
    final index = _endpoints.indexWhere((endpoint) => endpoint.url == url);
    if (index < 0) return;
    final endpoints = List<AiExposureProxyEndpoint>.of(_endpoints);
    endpoints[index] = endpoints[index].copyWith(enabled: enabled);
    dismissOpenHandTooltipsSafely(debugLabel: '切换代理节点状态前收起工具提示');
    setState(() => _busy = true);
    final updated = await _persistEndpoints(endpoints);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (updated) _replaceEndpointsLocally(endpoints);
    });
  }

  Future<void> _confirmDeleteEndpoints(
    Set<String> urls, {
    bool clearAll = false,
    _ProxyCleanup? cleanup,
  }) async {
    if (urls.isEmpty ||
        _busy ||
        _inspectionBusy ||
        _testingUrls.isNotEmpty ||
        _removingUrls.isNotEmpty) {
      return;
    }
    final endpoints = _endpoints
        .where((endpoint) => urls.contains(endpoint.url))
        .toList(growable: false);
    if (endpoints.isEmpty) return;
    final text = openHandTextResolver(context);
    final count = endpoints.length;
    final clearsPool = clearAll || count == _endpoints.length;
    final cleanupTitle = switch (cleanup) {
      _ProxyCleanup.unavailable => text(
        zh: '删除全部不可用节点？',
        en: 'Delete all unavailable nodes?',
      ),
      _ProxyCleanup.highLatency => text(
        zh: '删除全部高延迟节点？',
        en: 'Delete all high-latency nodes?',
      ),
      _ProxyCleanup.abnormal => text(
        zh: '清理全部异常节点？',
        en: 'Delete all unhealthy nodes?',
      ),
      null => null,
    };
    final cleanupMessage = switch (cleanup) {
      _ProxyCleanup.unavailable => text(
        zh: '将立即删除并保存 $count 个最近探测不可用的代理节点${clearsPool ? '，并停用定时巡检' : ''}。',
        en: 'Immediately delete and save $count unavailable proxy nodes${clearsPool ? ', then disable scheduled inspection' : ''}.',
      ),
      _ProxyCleanup.highLatency => text(
        zh: '将立即删除并保存 $count 个延迟超过 $_kProxyHighLatencyThresholdMs ms 的代理节点${clearsPool ? '，并停用定时巡检' : ''}。',
        en: 'Immediately delete and save $count proxy nodes above $_kProxyHighLatencyThresholdMs ms${clearsPool ? ', then disable scheduled inspection' : ''}.',
      ),
      _ProxyCleanup.abnormal => text(
        zh: '将立即删除并保存 $count 个不可用或高延迟代理节点${clearsPool ? '，并停用定时巡检' : ''}。',
        en: 'Immediately delete and save $count unavailable or high-latency proxy nodes${clearsPool ? ', then disable scheduled inspection' : ''}.',
      ),
      null => null,
    };
    final cleanupConfirmLabel = switch (cleanup) {
      _ProxyCleanup.unavailable => text(zh: '删除不可用', en: 'Delete unavailable'),
      _ProxyCleanup.highLatency => text(zh: '删除高延迟', en: 'Delete high latency'),
      _ProxyCleanup.abnormal => text(zh: '清理异常', en: 'Clean unhealthy'),
      null => null,
    };
    final cleanupIcon = switch (cleanup) {
      _ProxyCleanup.unavailable => Icons.cloud_off_outlined,
      _ProxyCleanup.highLatency => Icons.warning_amber_rounded,
      _ProxyCleanup.abnormal => Icons.cleaning_services_outlined,
      null => Icons.delete_outline_rounded,
    };
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title:
          cleanupTitle ??
          (clearsPool
              ? text(zh: '清空代理池？', en: 'Clear proxy pool?')
              : count == 1
              ? text(zh: '删除代理节点？', en: 'Delete proxy node?')
              : text(
                  zh: '删除所选 $count 个节点？',
                  en: 'Delete $count selected nodes?',
                )),
      message:
          cleanupMessage ??
          (clearsPool
              ? text(
                  zh: '将立即移除并保存全部 $count 个代理节点；若定时巡检已启用，将同步停用。',
                  en: 'This immediately removes and saves all $count proxy nodes. Scheduled inspection will be disabled if active.',
                )
              : count == 1
              ? text(
                  zh: '将立即移除并保存“${endpoints.first.displayName}”。',
                  en: 'Immediately remove and save “${endpoints.first.displayName}”.',
                )
              : text(
                  zh: '将立即移除并保存所选 $count 个代理节点。',
                  en: 'Immediately remove and save the $count selected proxy nodes.',
                )),
      cancelLabel: text(zh: '取消', en: 'Cancel'),
      confirmLabel:
          cleanupConfirmLabel ??
          (clearsPool
              ? text(zh: '全部清空', en: 'Clear all')
              : text(zh: '删除', en: 'Delete')),
      icon: Icon(
        cleanup != null
            ? cleanupIcon
            : clearsPool
            ? Icons.delete_forever_outlined
            : Icons.delete_outline_rounded,
      ),
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    final removedUrls = endpoints.map((endpoint) => endpoint.url).toSet();
    final remaining = _endpoints
        .where((endpoint) => !removedUrls.contains(endpoint.url))
        .toList(growable: false);
    dismissOpenHandTooltipsSafely(debugLabel: '删除代理节点前收起工具提示');
    setState(() {
      _busy = true;
      _removingUrls.addAll(removedUrls);
    });
    await awaitOpenHandListRemoval(context);
    if (!mounted) return;
    final updated = await _persistEndpoints(remaining);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _removingUrls.removeAll(removedUrls);
      if (updated) {
        _replaceEndpointsLocally(remaining);
        _testingUrls.removeAll(removedUrls);
        _pendingSamples.removeWhere((url, _) => removedUrls.contains(url));
      }
    });
    if (!updated) return;
    showOpenHandSuccessSnack(
      context,
      text(
        zh: '已删除并保存 $count 个代理节点。',
        en: '$count proxy nodes removed and saved.',
      ),
    );
  }

  Widget _buildSettingsPanel(
    BuildContext context, {
    required bool controllerInspectionBusy,
    required int activeCount,
    required bool systemProxyAvailable,
  }) {
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
          AnimatedOpacity(
            duration: openHandMotionDuration(
              context,
              const Duration(milliseconds: 240),
            ),
            curve: Curves.easeOutCubic,
            opacity: _enabled ? 1 : .46,
            child: IgnorePointer(
              ignoring: !_enabled,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final strategy =
                          DropdownButtonFormField<AiExposureProxyStrategy>(
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
                              if (value != null) {
                                setState(() => _strategy = value);
                              }
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
                          children: [
                            strategy,
                            const SizedBox(height: 8),
                            bypass,
                          ],
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
                  Text(
                    text(
                      zh: '每 ${_rotationEvery.round()} 次请求轮换',
                      en: 'Rotate every ${_rotationEvery.round()} requests',
                    ),
                    style: theme.textTheme.labelLarge,
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
                ],
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: openHandMotionDuration(
              context,
              const Duration(milliseconds: 220),
            ),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: _enabled && activeCount == 0
                ? Padding(
                    key: const ValueKey<String>('empty-proxy-pool-hint'),
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      systemProxyAvailable
                          ? text(
                              zh: '代理池暂无启用节点，保存后请求将回退全局系统代理。',
                              en: 'No proxy pool node is enabled; requests will use the global system proxy.',
                            )
                          : text(
                              zh: '代理池暂无启用节点，保存后请求将使用 DIRECT 直连。',
                              en: 'No proxy pool node is enabled; requests will use a DIRECT connection.',
                            ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.tertiary,
                      ),
                    ),
                  )
                : const SizedBox.shrink(
                    key: ValueKey<String>('proxy-pool-hint-hidden'),
                  ),
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
                    : controllerInspectionBusy
                    ? null
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

  Widget _buildEndpointToolbar(
    BuildContext context, {
    required bool controllerInspectionBusy,
  }) {
    final colors = Theme.of(context).colorScheme;
    final text = openHandTextResolver(context);
    final locked =
        _busy ||
        _inspectionBusy ||
        controllerInspectionBusy ||
        _testingUrls.isNotEmpty ||
        _removingUrls.isNotEmpty;
    final allSelected =
        _endpoints.isNotEmpty &&
        _endpoints.every((endpoint) => _selectedUrls.contains(endpoint.url));
    final unavailableUrls = <String>{};
    final highLatencyUrls = <String>{};
    for (final endpoint in _endpoints) {
      switch (_proxyEndpointHealth(endpoint)) {
        case _ProxyEndpointHealth.unavailable:
        case _ProxyEndpointHealth.forwardingFailed:
          unavailableUrls.add(endpoint.url);
        case _ProxyEndpointHealth.highLatency:
          highLatencyUrls.add(endpoint.url);
        case _ProxyEndpointHealth.disabled:
        case _ProxyEndpointHealth.unchecked:
        case _ProxyEndpointHealth.healthy:
          break;
      }
    }
    final cleanupTargets = <_ProxyCleanup, Set<String>>{
      _ProxyCleanup.unavailable: unavailableUrls,
      _ProxyCleanup.highLatency: highLatencyUrls,
      _ProxyCleanup.abnormal: <String>{...unavailableUrls, ...highLatencyUrls},
    };
    final sortLabel = switch (_sort) {
      _ProxySort.nameAscending => text(zh: '按名称升序', en: 'name ascending'),
      _ProxySort.latencyAscending => text(zh: '按延迟升序', en: 'latency ascending'),
      _ProxySort.latencyDescending => text(
        zh: '按延迟降序',
        en: 'latency descending',
      ),
    };
    final summary = OpenHandContentStateSwitcher(
      stateKey: _selectionMode ? 'selection' : 'summary',
      alignment: AlignmentDirectional.centerStart,
      child: _selectionMode
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: allSelected
                      ? text(zh: '取消全选', en: 'Deselect all')
                      : text(zh: '全选节点', en: 'Select all'),
                  child: Checkbox(
                    value: allSelected
                        ? true
                        : _selectedUrls.isEmpty
                        ? false
                        : null,
                    tristate: true,
                    onChanged: locked
                        ? null
                        : (_) => setState(() {
                            if (allSelected) {
                              _selectedUrls.clear();
                            } else {
                              _selectedUrls.addAll(
                                _endpoints.map((endpoint) => endpoint.url),
                              );
                            }
                          }),
                  ),
                ),
                Flexible(
                  child: Text(
                    text(
                      zh: '已选择 ${_selectedUrls.length} / ${_endpoints.length} 个节点',
                      en: '${_selectedUrls.length} / ${_endpoints.length} selected',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            )
          : Text(
              text(
                zh: '${_endpoints.length} 个节点 · $sortLabel',
                en: '${_endpoints.length} nodes · $sortLabel',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge,
            ),
    );
    final actionChildren = <Widget>[
      IconButton.filledTonal(
        tooltip: text(zh: '添加代理', en: 'Add proxy'),
        onPressed: locked || _selectionMode ? null : _addEndpoint,
        icon: const Icon(Icons.add_rounded),
      ),
      IconButton.filledTonal(
        tooltip: text(zh: '批量导入', en: 'Bulk import'),
        onPressed: locked || _selectionMode ? null : _import,
        icon: const Icon(Icons.upload_file_rounded),
      ),
      IconButton.filledTonal(
        tooltip: text(zh: '导出代理池', en: 'Export pool'),
        onPressed: _endpoints.isEmpty || locked || _selectionMode
            ? null
            : _exportAll,
        icon: const Icon(Icons.download_rounded),
      ),
      IconButton(
        tooltip: _selectionMode
            ? text(zh: '退出多选', en: 'Exit selection')
            : text(zh: '多选节点', en: 'Select nodes'),
        onPressed: _endpoints.isEmpty || locked
            ? null
            : () => setState(() {
                _selectionMode = !_selectionMode;
                if (!_selectionMode) _selectedUrls.clear();
              }),
        style: IconButton.styleFrom(
          backgroundColor: _selectionMode
              ? colors.primary
              : colors.surfaceContainerHighest,
          foregroundColor: _selectionMode
              ? colors.onPrimary
              : colors.onSurfaceVariant,
        ),
        icon: Icon(
          _selectionMode
              ? Icons.check_box_rounded
              : Icons.checklist_rtl_rounded,
        ),
      ),
      OpenHandInlineRevealSwitcher(
        presentKey: const ValueKey<String>('delete-selected'),
        child: _selectionMode
            ? IconButton(
                tooltip: text(zh: '删除所选节点', en: 'Delete selected'),
                onPressed: _selectedUrls.isEmpty || locked
                    ? null
                    : () => unawaited(
                        _confirmDeleteEndpoints(
                          Set<String>.from(_selectedUrls),
                        ),
                      ),
                style: IconButton.styleFrom(foregroundColor: colors.error),
                icon: const Icon(Icons.delete_sweep_outlined),
              )
            : null,
      ),
      AnimatedPopupMenuButton<_ProxyCleanup>(
        tooltip: text(zh: '快捷清理异常节点', en: 'Clean unhealthy nodes'),
        enabled: !locked && !_selectionMode,
        onSelected: (cleanup) {
          final urls = cleanupTargets[cleanup] ?? const <String>{};
          if (urls.isEmpty) return;
          dismissOpenHandTooltipsSafely(debugLabel: '清理异常代理节点前收起工具提示');
          unawaited(
            _confirmDeleteEndpoints(Set<String>.from(urls), cleanup: cleanup),
          );
        },
        itemBuilder: (_) => [
          PopupMenuItem<_ProxyCleanup>(
            value: _ProxyCleanup.unavailable,
            enabled: unavailableUrls.isNotEmpty,
            child: _ProxyCleanupMenuItem(
              icon: Icons.cloud_off_outlined,
              label: text(zh: '删除全部不可用节点', en: 'Delete all unavailable nodes'),
              detail: text(zh: '最近一次探测不可达', en: 'Latest probe unreachable'),
              count: unavailableUrls.length,
            ),
          ),
          PopupMenuItem<_ProxyCleanup>(
            value: _ProxyCleanup.highLatency,
            enabled: highLatencyUrls.isNotEmpty,
            child: _ProxyCleanupMenuItem(
              icon: Icons.warning_amber_rounded,
              label: text(zh: '删除全部高延迟节点', en: 'Delete all high-latency nodes'),
              detail: text(
                zh: '延迟超过 $_kProxyHighLatencyThresholdMs ms',
                en: 'Latency above $_kProxyHighLatencyThresholdMs ms',
              ),
              count: highLatencyUrls.length,
            ),
          ),
          PopupMenuItem<_ProxyCleanup>(
            value: _ProxyCleanup.abnormal,
            enabled: cleanupTargets[_ProxyCleanup.abnormal]!.isNotEmpty,
            child: _ProxyCleanupMenuItem(
              icon: Icons.cleaning_services_outlined,
              label: text(zh: '清理全部异常节点', en: 'Delete all unhealthy nodes'),
              detail: text(
                zh: '不可用与高延迟节点',
                en: 'Unavailable and high-latency nodes',
              ),
              count: cleanupTargets[_ProxyCleanup.abnormal]!.length,
            ),
          ),
        ],
        icon: const Icon(Icons.cleaning_services_outlined),
      ),
      IconButton(
        tooltip: text(zh: '清空全部节点', en: 'Clear all nodes'),
        onPressed: _endpoints.isEmpty || locked
            ? null
            : () => unawaited(
                _confirmDeleteEndpoints(
                  _endpoints.map((endpoint) => endpoint.url).toSet(),
                  clearAll: true,
                ),
              ),
        style: IconButton.styleFrom(foregroundColor: colors.error),
        icon: const Icon(Icons.delete_forever_outlined),
      ),
      AnimatedPopupMenuButton<_ProxySort>(
        tooltip: text(zh: '排序节点', en: 'Sort nodes'),
        enabled: !locked && !_selectionMode,
        initialValue: _sort,
        onSelected: (value) {
          dismissOpenHandTooltipsSafely(debugLabel: '排序代理节点前收起工具提示');
          setState(() {
            _sort = value;
            _invalidateEndpointSortCache();
          });
        },
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
    ];
    final actions = OpenHandTrailingToolbar(children: actionChildren);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [summary, const SizedBox(height: 8), actions],
          );
        }
        return Row(
          children: [
            Expanded(child: summary),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: actions),
          ],
        );
      },
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
      final endpoints = <AiExposureProxyEndpoint>[..._endpoints, endpoint];
      dismissOpenHandTooltipsSafely(debugLabel: '新增代理节点前收起工具提示');
      setState(() => _busy = true);
      final updated = await _persistEndpoints(endpoints);
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (updated) _replaceEndpointsLocally(endpoints);
      });
      if (updated) {
        showOpenHandSuccessSnack(context, '代理节点已添加并保存。');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        showOpenHandErrorSnack(context, '$error');
      }
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
    final sameEndpoint = endpoint.url == updated.url;
    final index = _endpoints.indexWhere((item) => item.url == endpoint.url);
    if (index < 0) return;
    final endpoints = List<AiExposureProxyEndpoint>.of(_endpoints);
    endpoints[index] = updated.copyWith(
      enabled: endpoint.enabled,
      samples: sameEndpoint ? endpoint.samples : updated.samples,
      statistics: sameEndpoint ? endpoint.statistics : updated.statistics,
      identity: sameEndpoint ? endpoint.identity : updated.identity,
    );
    dismissOpenHandTooltipsSafely(debugLabel: '更新代理节点前收起工具提示');
    setState(() => _busy = true);
    final saved = await _persistEndpoints(endpoints);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (saved) _replaceEndpointsLocally(endpoints);
    });
    if (saved) showOpenHandSuccessSnack(context, '代理节点已更新并保存。');
  }

  Future<void> _showEndpointDetails(
    AiExposureProxyEndpoint endpoint,
    AiExposureProxyUsageStatistics statistics,
  ) => _showProxyEndpointDetails(
    context,
    endpoint: endpoint,
    statistics: statistics,
    onProbe: (sample) async {
      final current = _endpoints
          .where((item) => item.url == endpoint.url)
          .firstOrNull;
      if (current != null && mounted) {
        _replaceEndpointLocally(endpoint.url, current.withSample(sample));
      }
      await _servicesController.saveProxyProbeSamples({endpoint.url: sample});
    },
    onIdentity: (identity) async {
      final controller = context.read<ServicesController>();
      final saved = await controller.updateProxyIdentity(
        endpoint.url,
        identity,
      );
      if (!saved || !mounted) return saved;
      final current = _endpoints
          .where((item) => item.url == endpoint.url)
          .firstOrNull;
      if (current != null) {
        _replaceEndpointLocally(
          endpoint.url,
          current.copyWith(identity: identity),
        );
      }
      return true;
    },
  );

  Future<void> _testEndpoint(String url) async {
    if (_inspectionRunning ||
        _servicesController.proxyInspectionBusy ||
        _testingUrls.contains(url)) {
      return;
    }
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
    if (_inspectionBusy ||
        _inspectionRunning ||
        _servicesController.proxyInspectionBusy ||
        _testingUrls.isNotEmpty) {
      return;
    }
    final total = _endpoints.where((endpoint) => endpoint.enabled).length;
    if (total == 0) return;
    final generation = ++_inspectionGeneration;
    _inspectionRunning = true;
    _pendingSamplesHandledByController = true;
    setState(() {
      _inspectionBusy = true;
      _inspectionCompleted = 0;
      _inspectionTotal = total;
    });

    try {
      final started = await _servicesController.inspectAllProxies(
        concurrency: _normalizedInspectionConcurrency,
        onResult: (url, sample, completed, total) {
          if (!mounted || generation != _inspectionGeneration) return;
          _pendingSamples[url] = sample;
          _inspectionCompleted = completed;
          _inspectionTotal = total;
          _scheduleProbeResultFlush();
        },
      );
      if (!started || !mounted || generation != _inspectionGeneration) return;
      _resultFlushTimer?.cancel();
      _resultFlushTimer = null;
      _flushProbeResults();
    } finally {
      _inspectionRunning = false;
      _resultFlushTimer?.cancel();
      _resultFlushTimer = null;
      if (mounted) {
        _flushProbeResults();
        _pendingSamplesHandledByController = false;
        setState(() => _inspectionBusy = false);
      }
    }
  }

  void _scheduleProbeResultFlush() {
    if (_resultFlushTimer?.isActive == true) return;
    _resultFlushTimer = startSafeTimer(_kProbeResultFlushDelay, () {
      _resultFlushTimer = null;
      _flushProbeResults();
    });
  }

  void _cancelInspection() {
    if (!_inspectionBusy) return;
    _inspectionGeneration++;
    _servicesController.cancelProxyInspection();
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
    final indexes = _endpointIndexCache ??= <String, int>{
      for (var index = 0; index < _endpoints.length; index++)
        _endpoints[index].url: index,
    };
    if (_sort != _ProxySort.nameAscending) {
      dismissOpenHandTooltipsSafely(debugLabel: '重排代理节点前收起工具提示');
    }
    setState(() {
      _invalidateEndpointSortCache();
      for (final entry in samples.entries) {
        final index = indexes[entry.key];
        if (index != null) {
          _endpoints[index] = _endpoints[index].withSample(entry.value);
        }
      }
    });
    if (!_pendingSamplesHandledByController) {
      unawaited(
        context.read<ServicesController>().saveProxyProbeSamples(samples),
      );
    }
  }

  Future<void> _import() async {
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'Proxy', extensions: <String>['txt', 'json']),
      ],
    );
    if (file == null || !mounted) return;
    dismissOpenHandTooltipsSafely(debugLabel: '导入代理节点前收起工具提示');
    setState(() => _busy = true);
    try {
      final source = File(file.path);
      final imported = _proxyEndpoints(
        await readBoundedFileString(source, maxBytes: _kMaxProxyImportBytes),
      );
      final merged = <String, AiExposureProxyEndpoint>{
        for (final endpoint in _endpoints) endpoint.url: endpoint,
      };
      var accepted = 0;
      for (final endpoint in imported.endpoints) {
        if (merged.length >= _kMaxProxyEndpoints) break;
        final existing = merged[endpoint.url];
        if (existing == null) {
          accepted++;
          merged[endpoint.url] = endpoint;
        } else {
          merged[endpoint.url] = endpoint.copyWith(
            samples: existing.samples,
            statistics: existing.statistics,
            identity: existing.identity,
          );
        }
      }
      if (!mounted) return;
      final endpoints = merged.values.toList(growable: false);
      final updated = await _persistEndpoints(endpoints);
      if (!mounted || !updated) return;
      setState(() {
        _replaceEndpointsLocally(endpoints);
      });
      showOpenHandSuccessSnack(
        context,
        imported.invalid == 0
            ? '已新增并保存 $accepted 个代理。'
            : '已新增并保存 $accepted 个代理，忽略 ${imported.invalid} 条无效记录。',
      );
    } catch (error) {
      if (mounted) showOpenHandErrorSnack(context, '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportPayload({
    required String suggestedName,
    required String payload,
    required String successMessage,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final location = await getSaveLocation(
        suggestedName: suggestedName,
        acceptedTypeGroups: const <XTypeGroup>[_kProxyJsonFileType],
      );
      if (location == null) return;
      await writeFileAtomically(File(location.path), payload);
      if (mounted) showOpenHandSuccessSnack(context, successMessage);
    } catch (error) {
      if (mounted) showOpenHandErrorSnack(context, '导出代理配置失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportAll() {
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
    return _exportPayload(
      suggestedName: 'openhand-ai-exposure-proxies.json',
      payload: payload,
      successMessage: '代理池已导出。',
    );
  }

  Future<void> _exportOne(AiExposureProxyEndpoint endpoint) {
    final payload = const JsonEncoder.withIndent('  ').convert(
      <String, Object?>{
        'type': 'openhand_ai_exposure_proxy',
        'version': 2,
        ...endpoint.toJson(),
      },
    );
    return _exportPayload(
      suggestedName: 'openhand-ai-exposure-proxy.json',
      payload: payload,
      successMessage: '代理配置已导出。',
    );
  }

  Future<void> _save() async {
    final controller = context.read<ServicesController>();
    final endpoints = controller.proxyConfiguration.endpoints;
    final activeCount = endpoints.where((endpoint) => endpoint.enabled).length;
    if (_inspectionEnabled && activeCount == 0) {
      showOpenHandErrorSnack(context, '启用定时巡检前请至少启用一个代理节点。');
      return;
    }
    setState(() => _busy = true);
    final updated = await controller.updateProxyConfiguration(
      AiExposureProxyConfiguration(
        enabled: _enabled,
        strategy: _strategy,
        rotationEvery: _rotationEvery.round(),
        bypassLocal: _bypassLocal,
        endpoints: endpoints,
        inspectionEnabled: _inspectionEnabled,
        inspectionIntervalMinutes: _normalizedInspectionInterval,
        inspectionConcurrency: _normalizedInspectionConcurrency,
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (updated) _closeDialog();
  }
}

class _ProxyPoolOverview extends StatelessWidget {
  const _ProxyPoolOverview({
    required this.endpoints,
    required this.statusStatistics,
    required this.inFlight,
  });

  final List<AiExposureProxyEndpoint> endpoints;
  final Map<String, AiExposureProxyUsageStatistics> statusStatistics;
  final int inFlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = openHandTextResolver(context);
    final statistics = endpoints
        .map(
          (endpoint) =>
              statusStatistics[endpoint.runtimeId] ?? endpoint.statistics,
        )
        .toList(growable: false);
    final requests = statistics.fold<int>(
      0,
      (sum, item) => sum + item.requests,
    );
    final successes = statistics.fold<int>(
      0,
      (sum, item) => sum + item.successes,
    );
    final failures = statistics.fold<int>(
      0,
      (sum, item) => sum + item.failures,
    );
    final timeouts = statistics.fold<int>(
      0,
      (sum, item) => sum + item.timeouts,
    );
    final completed = successes + failures + timeouts;
    final responseTime = statistics.fold<int>(
      0,
      (sum, item) => sum + item.totalResponseTimeMs,
    );
    final requestSamples =
        statistics.expand((item) => item.recentRequests).toList()
          ..sort((left, right) => left.at.compareTo(right.at));
    final recent = requestSamples.length <= kAiExposureProxyRequestSampleLimit
        ? requestSamples
        : requestSamples.sublist(
            requestSamples.length - kAiExposureProxyRequestSampleLimit,
          );
    final sortedLatencies =
        requestSamples
            .map((item) => item.responseTimeMs)
            .toList(growable: false)
          ..sort();
    final p95 = sortedLatencies.isEmpty
        ? 0
        : sortedLatencies[((sortedLatencies.length - 1) * 0.95).round()];
    final healthy = endpoints
        .where((item) => item.enabled && item.latestSample?.reachable == true)
        .length;
    final identified = endpoints.where((item) => item.identity != null).length;
    final regions = endpoints
        .map((item) => item.identity?.countryCode.trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toSet()
        .length;
    final metrics = <_ProxyPoolMetricData>[
      _ProxyPoolMetricData(
        Icons.hub_outlined,
        text(zh: '节点总数', en: 'Nodes'),
        '${endpoints.length}',
        text(
          zh: '启用 ${endpoints.where((item) => item.enabled).length} · 健康 $healthy',
          en: '${endpoints.where((item) => item.enabled).length} active · $healthy healthy',
        ),
        colors.primary,
      ),
      _ProxyPoolMetricData(
        Icons.route_outlined,
        text(zh: '请求总数', en: 'Requests'),
        '$requests',
        text(zh: '执行中 $inFlight', en: '$inFlight in flight'),
        OpenHandStatusColors.info,
      ),
      _ProxyPoolMetricData(
        Icons.task_alt_rounded,
        text(zh: '成功数量', en: 'Succeeded'),
        '$successes',
        completed == 0
            ? '--'
            : '${(successes * 100 / completed).toStringAsFixed(1)}%',
        OpenHandStatusColors.success,
      ),
      _ProxyPoolMetricData(
        Icons.error_outline_rounded,
        text(zh: '失败数量', en: 'Failed'),
        '$failures',
        completed == 0
            ? '--'
            : '${(failures * 100 / completed).toStringAsFixed(1)}%',
        OpenHandStatusColors.error,
      ),
      _ProxyPoolMetricData(
        Icons.timer_off_outlined,
        text(zh: '超时数量', en: 'Timeouts'),
        '$timeouts',
        completed == 0
            ? '--'
            : '${(timeouts * 100 / completed).toStringAsFixed(1)}%',
        OpenHandStatusColors.warning,
      ),
      _ProxyPoolMetricData(
        Icons.av_timer_rounded,
        text(zh: '平均响应', en: 'Average'),
        '${completed == 0 ? 0 : (responseTime / completed).round()} ms',
        'P95 $p95 ms',
        colors.tertiary,
      ),
      _ProxyPoolMetricData(
        Icons.public_rounded,
        text(zh: '身份识别', en: 'Identified'),
        '$identified/${endpoints.length}',
        text(zh: '$regions 个国家/地区', en: '$regions regions'),
        const Color(0xff0891b2),
      ),
      _ProxyPoolMetricData(
        Icons.shield_outlined,
        text(zh: '高干净度', en: 'Clean exits'),
        '${endpoints.where((item) => item.identity?.cleanliness == 'high').length}',
        text(zh: '身份检测结果', en: 'Identity results'),
        const Color(0xff16a34a),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.28),
                ),
              ),
              child: Icon(
                Icons.monitor_heart_outlined,
                size: 19,
                color: colors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text(zh: '代理池实时运维', en: 'Proxy pool operations'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              text(zh: '最近 24 次请求样本', en: 'Latest 24 request samples'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 700) {
              return SizedBox(
                height: 82,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: openHandDialogAwareScrollPhysics(context),
                  itemCount: metrics.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) => SizedBox(
                    width: 154,
                    child: _ProxyPoolMetricTile(data: metrics[index]),
                  ),
                ),
              );
            }
            final columns = constraints.maxWidth >= 1050 ? 8 : 4;
            const gap = 8.0;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: metrics
                  .map(
                    (item) => SizedBox(
                      width: width,
                      child: _ProxyPoolMetricTile(data: item),
                    ),
                  )
                  .toList(growable: false),
            );
          },
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final latency = _ProxyPoolChartPanel(
              icon: Icons.show_chart_rounded,
              title: text(zh: '请求响应趋势', en: 'Response trend'),
              child: CustomPaint(
                painter: OpenHandSmoothLineChartPainter(
                  series: <OpenHandChartSeries>[
                    OpenHandChartSeries(
                      label: 'latency',
                      values: recent
                          .map((item) => item.responseTimeMs.toDouble())
                          .toList(growable: false),
                      color: colors.primary,
                    ),
                  ],
                  gridColor: colors.outlineVariant.withValues(alpha: 0.55),
                  labelColor: colors.onSurfaceVariant,
                  emptyLabel: text(zh: '暂无请求样本', en: 'No request samples'),
                  valueSuffix: ' ms',
                  textDirection: Directionality.of(context),
                ),
              ),
            );
            final distribution = _ProxyPoolChartPanel(
              icon: Icons.donut_large_rounded,
              title: text(zh: '请求结果分布', en: 'Outcome distribution'),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 74,
                    child: CustomPaint(
                      painter: OpenHandDonutChartPainter(
                        values: <int>[successes, failures, timeouts],
                        colors: const <Color>[
                          OpenHandStatusColors.success,
                          OpenHandStatusColors.error,
                          OpenHandStatusColors.warning,
                        ],
                        trackColor: colors.surfaceContainerHighest,
                      ),
                      child: Center(
                        child: Text(
                          '$completed',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        _ProxyLegend(
                          label: text(
                            zh: '成功 $successes',
                            en: 'Success $successes',
                          ),
                          color: OpenHandStatusColors.success,
                        ),
                        _ProxyLegend(
                          label: text(
                            zh: '失败 $failures',
                            en: 'Failed $failures',
                          ),
                          color: OpenHandStatusColors.error,
                        ),
                        _ProxyLegend(
                          label: text(
                            zh: '超时 $timeouts',
                            en: 'Timeout $timeouts',
                          ),
                          color: OpenHandStatusColors.warning,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
            if (constraints.maxWidth < 720) {
              final width = constraints.maxWidth < 340
                  ? 300.0
                  : constraints.maxWidth * 0.9;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: openHandDialogAwareScrollPhysics(context),
                child: Row(
                  children: [
                    SizedBox(width: width, child: latency),
                    const SizedBox(width: 8),
                    SizedBox(width: width, child: distribution),
                  ],
                ),
              );
            }
            return Row(
              children: [
                Expanded(child: latency),
                const SizedBox(width: 8),
                Expanded(child: distribution),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ProxyPoolMetricData {
  const _ProxyPoolMetricData(
    this.icon,
    this.label,
    this.value,
    this.detail,
    this.color,
  );

  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final Color color;
}

class _ProxyPoolMetricTile extends StatelessWidget {
  const _ProxyPoolMetricTile({required this.data});
  final _ProxyPoolMetricData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      height: 82,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: data.color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: data.color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(data.icon, size: 16, color: data.color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            data.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            data.detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(color: data.color),
          ),
        ],
      ),
    );
  }
}

class _ProxyPoolChartPanel extends StatelessWidget {
  const _ProxyPoolChartPanel({
    required this.icon,
    required this.title,
    required this.child,
    this.height = 118,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      height: height,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: colors.primary),
              const SizedBox(width: 6),
              Text(
                title,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _ProxyDetailTrendPoint {
  const _ProxyDetailTrendPoint({
    required this.at,
    required this.value,
    required this.status,
    required this.detail,
    required this.color,
    required this.icon,
  });

  final DateTime at;
  final int value;
  final String status;
  final String detail;
  final Color color;
  final IconData icon;
}

class _ProxyDetailTrendChart extends StatefulWidget {
  const _ProxyDetailTrendChart({
    required this.points,
    required this.lineColor,
    required this.emptyLabel,
    required this.seriesLabel,
  });

  final List<_ProxyDetailTrendPoint> points;
  final Color lineColor;
  final String emptyLabel;
  final String seriesLabel;

  @override
  State<_ProxyDetailTrendChart> createState() => _ProxyDetailTrendChartState();
}

class _ProxyDetailTrendChartState extends State<_ProxyDetailTrendChart> {
  static const double _chartInset = 8;
  static const double _bottomLabelHeight = 24;
  static const double _tooltipWidth = 224;
  int? _hoveredIndex;
  int _lastHoveredIndex = 0;

  void _updateHoveredPoint(PointerHoverEvent event, double width) {
    if (widget.points.isEmpty || width <= _chartInset * 2) return;
    final ratio =
        ((event.localPosition.dx - _chartInset) / (width - _chartInset * 2))
            .clamp(0.0, 1.0);
    final index = (ratio * (widget.points.length - 1)).round();
    if (index == _hoveredIndex) return;
    setState(() {
      _hoveredIndex = index;
      _lastHoveredIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final points = widget.points;
    final values = points
        .map((point) => point.value.toDouble())
        .toList(growable: false);
    final hoveredIndex = _hoveredIndex == null || points.isEmpty
        ? null
        : _hoveredIndex!.clamp(0, points.length - 1);
    final displayedIndex = points.isEmpty
        ? null
        : (hoveredIndex ?? _lastHoveredIndex.clamp(0, points.length - 1));
    final hoveredPoint = hoveredIndex == null ? null : points[hoveredIndex];
    final revision = points.isEmpty
        ? 0
        : Object.hash(
            points.length,
            points.last.at.microsecondsSinceEpoch,
            points.last.value,
          );
    final maxValue = values.fold<double>(0, (max, value) {
      return value > max ? value : max;
    });
    final normalizedMax = maxValue <= 1 ? 1.0 : maxValue * 1.14;

    return LayoutBuilder(
      builder: (context, constraints) {
        final pointX = displayedIndex == null || points.length <= 1
            ? _chartInset
            : _chartInset +
                  (constraints.maxWidth - _chartInset * 2) *
                      displayedIndex /
                      (points.length - 1);
        final chartHeight = (constraints.maxHeight - _bottomLabelHeight).clamp(
          0.0,
          double.infinity,
        );
        final pointValue = displayedIndex == null
            ? 0.0
            : values[displayedIndex];
        final pointY =
            _chartInset +
            chartHeight * (1 - (pointValue / normalizedMax).clamp(0.0, 1.0));
        final tooltipWidth = constraints.maxWidth < _tooltipWidth
            ? constraints.maxWidth
            : _tooltipWidth;
        final tooltipLeft = (pointX - tooltipWidth / 2).clamp(
          0.0,
          (constraints.maxWidth - tooltipWidth).clamp(0.0, double.infinity),
        );
        final motionDuration = openHandMotionDuration(
          context,
          const Duration(milliseconds: 190),
        );

        return MouseRegion(
          cursor: points.isEmpty
              ? MouseCursor.defer
              : SystemMouseCursors.precise,
          onHover: (event) => _updateHoveredPoint(event, constraints.maxWidth),
          onExit: (_) {
            if (_hoveredIndex != null) {
              setState(() => _hoveredIndex = null);
            }
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: TweenAnimationBuilder<double>(
                  key: ValueKey<int>(revision),
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: openHandMotionDuration(
                    context,
                    const Duration(milliseconds: 460),
                  ),
                  curve: Curves.easeOutCubic,
                  builder: (context, progress, _) => CustomPaint(
                    painter: OpenHandSmoothLineChartPainter(
                      series: <OpenHandChartSeries>[
                        OpenHandChartSeries(
                          label: widget.seriesLabel,
                          values: values
                              .map((value) => value * progress)
                              .toList(growable: false),
                          color: widget.lineColor,
                        ),
                      ],
                      gridColor: colors.outlineVariant.withValues(alpha: 0.55),
                      labelColor: colors.onSurfaceVariant,
                      emptyLabel: widget.emptyLabel,
                      valueSuffix: ' ms',
                      textDirection: Directionality.of(context),
                    ),
                    size: Size.infinite,
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: motionDuration,
                curve: Curves.easeOutCubic,
                left: pointX - 0.5,
                top: _chartInset,
                bottom: _bottomLabelHeight - _chartInset,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    duration: motionDuration,
                    opacity: hoveredPoint == null ? 0 : 1,
                    child: Container(
                      width: 1,
                      color: widget.lineColor.withValues(alpha: 0.42),
                    ),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: motionDuration,
                curve: Curves.easeOutCubic,
                left: pointX - 4,
                top: pointY - 4,
                child: IgnorePointer(
                  child: AnimatedScale(
                    duration: motionDuration,
                    curve: Curves.easeOutBack,
                    scale: hoveredPoint == null ? 0 : 1,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: hoveredPoint?.color ?? widget.lineColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: colors.surface, width: 2),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: widget.lineColor.withValues(alpha: 0.28),
                            blurRadius: 7,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: motionDuration,
                curve: Curves.easeOutCubic,
                left: tooltipLeft,
                top: 2,
                width: tooltipWidth,
                child: IgnorePointer(
                  child: AnimatedSwitcher(
                    duration: openHandMotionDuration(
                      context,
                      const Duration(milliseconds: 230),
                    ),
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        alignment: Alignment.bottomCenter,
                        scale: Tween<double>(
                          begin: .92,
                          end: 1,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: hoveredPoint == null
                        ? const SizedBox.shrink(
                            key: ValueKey<String>('detail-tooltip-empty'),
                          )
                        : _ProxyDetailTrendTooltip(
                            key: ValueKey<int>(hoveredIndex!),
                            point: hoveredPoint,
                            index: hoveredIndex + 1,
                            total: points.length,
                          ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProxyDetailTrendTooltip extends StatelessWidget {
  const _ProxyDetailTrendTooltip({
    super.key,
    required this.point,
    required this.index,
    required this.total,
  });

  final _ProxyDetailTrendPoint point;
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: point.color.withValues(alpha: .38)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: colors.shadow.withValues(alpha: .18),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: point.color.withValues(alpha: .13),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: Icon(point.icon, size: 14, color: point.color),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '${point.value} ms',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: point.color,
                    ),
                  ),
                ),
                Text(
                  '$index/$total',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              _dateTimeLabel(point.at),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            Text(
              '${point.status} · ${point.detail}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(color: point.color),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProxyLegend extends StatelessWidget {
  const _ProxyLegend({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
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

Future<void> _showProxyEndpointDetails(
  BuildContext context, {
  required AiExposureProxyEndpoint endpoint,
  required AiExposureProxyUsageStatistics statistics,
  required Future<void> Function(AiExposureProxyProbeSample sample) onProbe,
  required Future<bool> Function(AiExposureProxyIdentity identity) onIdentity,
}) => showAnimatedDialog<void>(
  context: context,
  builder: (_) => buildOpenHandDialog(
    maxWidth: kOpenHandDialogWidthStandard,
    maxHeight: kOpenHandDialogHeightTall,
    child: ServiceDialogInteractionTheme(
      child: _ProxyEndpointDetailsDialog(
        endpoint: endpoint.copyWith(statistics: statistics),
        onProbe: onProbe,
        onIdentity: onIdentity,
      ),
    ),
  ),
);

class _ProxyEndpointDetailsDialog extends StatefulWidget {
  const _ProxyEndpointDetailsDialog({
    required this.endpoint,
    required this.onProbe,
    required this.onIdentity,
  });

  final AiExposureProxyEndpoint endpoint;
  final Future<void> Function(AiExposureProxyProbeSample sample) onProbe;
  final Future<bool> Function(AiExposureProxyIdentity identity) onIdentity;

  @override
  State<_ProxyEndpointDetailsDialog> createState() =>
      _ProxyEndpointDetailsDialogState();
}

class _ProxyEndpointDetailsDialogState
    extends State<_ProxyEndpointDetailsDialog> {
  final AiExposureProxyProbe _probe = const AiExposureProxyProbe();
  late AiExposureProxyEndpoint _endpoint;
  bool _testingProbe = false;
  bool _loadingIdentity = false;
  String? _identityError;

  @override
  void initState() {
    super.initState();
    _endpoint = widget.endpoint;
    if (_endpoint.identity != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_endpoint.latestSample?.reachable == true) {
        _refreshIdentity();
      } else if (_endpoint.latestSample == null) {
        _refreshProbe(refreshIdentityOnSuccess: true);
      }
    });
  }

  Future<void> _refreshProbe({bool refreshIdentityOnSuccess = false}) async {
    if (_testingProbe || _loadingIdentity) return;
    setState(() => _testingProbe = true);
    final sample = await _probe.inspect(_endpoint);
    if (!mounted) return;
    setState(() {
      _endpoint = _endpoint.withSample(sample);
      _testingProbe = false;
      if (!sample.reachable) _identityError = null;
    });
    await widget.onProbe(sample);
    if (mounted && refreshIdentityOnSuccess && sample.reachable) {
      await _refreshIdentity();
    }
  }

  Future<void> _refreshIdentity() async {
    if (_loadingIdentity) return;
    setState(() {
      _loadingIdentity = true;
      _identityError = null;
    });
    try {
      final identity = await _probe.inspectIdentity(_endpoint);
      if (!mounted) return;
      if (!await widget.onIdentity(identity)) {
        if (mounted) setState(() => _identityError = '保存代理身份失败，请重试。');
        return;
      }
      if (mounted) {
        setState(() => _endpoint = _endpoint.copyWith(identity: identity));
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => _identityError = error.message);
    } catch (_) {
      if (mounted) setState(() => _identityError = '代理身份查询失败');
    } finally {
      if (mounted) setState(() => _loadingIdentity = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = openHandTextResolver(context);
    final proxyStatus = context.watch<ServicesController>().proxyStatus;
    AiExposureProxyUsageStatistics? runtimeStatistics;
    for (final item
        in proxyStatus?.endpoints ?? const <AiExposureProxyEndpointStatus>[]) {
      if (item.id == _endpoint.runtimeId) {
        runtimeStatistics = item.statistics;
        break;
      }
    }
    final statistics = runtimeStatistics ?? _endpoint.statistics;
    final completed = statistics.completed;
    final recentLatencies =
        statistics.recentRequests
            .map((item) => item.responseTimeMs)
            .toList(growable: false)
          ..sort();
    final p95 = recentLatencies.isEmpty
        ? 0
        : recentLatencies[((recentLatencies.length - 1) * 0.95).round()];
    final tone = _proxyHealthTone(context, _endpoint, false);
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OpenHandResponsiveHeaderLayout(
            compactBreakpoint: 560,
            identity: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: tone.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: tone.color.withValues(alpha: 0.32),
                    ),
                  ),
                  child: Icon(Icons.dns_outlined, color: tone.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text(zh: '代理节点详情', en: 'Proxy node details'),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${_endpoint.displayName} · ${_endpoint.maskedUrl}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: Wrap(
              spacing: 8,
              children: [
                ServiceDialogHeaderIconButton(
                  tooltip: text(zh: '重新检测代理转发', en: 'Retest proxy forwarding'),
                  onPressed: _testingProbe || _loadingIdentity
                      ? null
                      : () => _refreshProbe(
                          refreshIdentityOnSuccess: _endpoint.identity == null,
                        ),
                  icon: _testingProbe
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check_rounded),
                ),
                ServiceDialogHeaderIconButton(
                  tooltip: text(zh: '刷新出口身份', en: 'Refresh identity'),
                  onPressed:
                      _loadingIdentity ||
                          _testingProbe ||
                          _endpoint.latestSample?.reachable != true
                      ? null
                      : _refreshIdentity,
                  icon: _loadingIdentity
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.travel_explore_rounded),
                ),
                ServiceDialogHeaderIconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ProxyMetric(
                icon: tone.icon,
                label: tone.label,
                color: tone.color,
              ),
              _ProxyMetric(
                icon: Icons.security_rounded,
                label: _endpoint.identity != null
                    ? _cleanlinessLabel(_endpoint.identity!.cleanliness, text)
                    : _identityError != null
                    ? text(zh: '身份识别失败', en: 'Identity lookup failed')
                    : _endpoint.latestSample?.reachable == false
                    ? text(zh: '身份暂不可用', en: 'Identity unavailable')
                    : text(zh: '身份待识别', en: 'Identity pending'),
                color: _identityError != null
                    ? OpenHandStatusColors.warning
                    : _cleanlinessColor(
                        _endpoint.identity?.cleanliness,
                        colors,
                      ),
              ),
              _ProxyMetric(
                icon: Icons.public_rounded,
                label: _networkTypeLabel(_endpoint.identity?.networkType, text),
                color: colors.primary,
              ),
              if (statistics.lastUsedAt != null)
                _ProxyMetric(
                  icon: Icons.schedule_rounded,
                  label: text(
                    zh: '最近使用 ${_timeLabel(statistics.lastUsedAt!)}',
                    en: 'Used ${_timeLabel(statistics.lastUsedAt!)}',
                  ),
                  color: colors.onSurfaceVariant,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: SingleChildScrollView(
              physics: openHandDialogAwareScrollPhysics(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildProbeSection(context),
                  const SizedBox(height: 12),
                  _buildIdentitySection(context),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final metrics = <_ProxyPoolMetricData>[
                        _ProxyPoolMetricData(
                          Icons.route_outlined,
                          text(zh: '使用次数', en: 'Requests'),
                          '${statistics.requests}',
                          text(
                            zh: '执行中 ${statistics.inFlight}',
                            en: '${statistics.inFlight} in flight',
                          ),
                          OpenHandStatusColors.info,
                        ),
                        _ProxyPoolMetricData(
                          Icons.task_alt_rounded,
                          text(zh: '成功', en: 'Success'),
                          '${statistics.successes}',
                          completed == 0
                              ? '--'
                              : '${(statistics.successRate * 100).toStringAsFixed(1)}%',
                          OpenHandStatusColors.success,
                        ),
                        _ProxyPoolMetricData(
                          Icons.error_outline_rounded,
                          text(zh: '失败', en: 'Failed'),
                          '${statistics.failures}',
                          text(
                            zh: '连续 ${statistics.consecutiveFailures}',
                            en: '${statistics.consecutiveFailures} consecutive',
                          ),
                          OpenHandStatusColors.error,
                        ),
                        _ProxyPoolMetricData(
                          Icons.timer_off_outlined,
                          text(zh: '超时', en: 'Timeout'),
                          '${statistics.timeouts}',
                          completed == 0
                              ? '--'
                              : '${(statistics.timeouts * 100 / completed).toStringAsFixed(1)}%',
                          OpenHandStatusColors.warning,
                        ),
                        _ProxyPoolMetricData(
                          Icons.av_timer_rounded,
                          text(zh: '平均响应', en: 'Average'),
                          '${statistics.averageResponseTimeMs} ms',
                          'P95 $p95 ms',
                          colors.primary,
                        ),
                        _ProxyPoolMetricData(
                          Icons.vertical_align_bottom_rounded,
                          text(zh: '最短响应', en: 'Minimum'),
                          '${statistics.minResponseTimeMs} ms',
                          text(zh: '请求头响应', en: 'Header response'),
                          const Color(0xff0891b2),
                        ),
                        _ProxyPoolMetricData(
                          Icons.vertical_align_top_rounded,
                          text(zh: '最长响应', en: 'Maximum'),
                          '${statistics.maxResponseTimeMs} ms',
                          text(zh: '请求头响应', en: 'Header response'),
                          colors.tertiary,
                        ),
                        _ProxyPoolMetricData(
                          Icons.speed_rounded,
                          text(zh: '探测延迟', en: 'Probe latency'),
                          _endpoint.latestSample?.latencyMs == null
                              ? '--'
                              : '${_endpoint.latestSample!.latencyMs} ms',
                          '${_endpoint.samples.length} samples',
                          tone.color,
                        ),
                      ];
                      final columns = constraints.maxWidth >= 760 ? 4 : 2;
                      const gap = 8.0;
                      final width =
                          (constraints.maxWidth - gap * (columns - 1)) /
                          columns;
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: metrics
                            .map(
                              (item) => SizedBox(
                                width: width,
                                child: _ProxyPoolMetricTile(data: item),
                              ),
                            )
                            .toList(growable: false),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildCharts(context, statistics),
                  const SizedBox(height: 12),
                  _buildHttpDistribution(context, statistics),
                  const SizedBox(height: 12),
                  _buildRecentRequests(context, statistics),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProbeSection(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = openHandTextResolver(context);
    final sample = _endpoint.latestSample;
    final gatewayColor = sample == null
        ? colors.onSurfaceVariant
        : sample.gatewayReachable
        ? OpenHandStatusColors.success
        : OpenHandStatusColors.error;
    final forwardingColor = sample == null
        ? colors.onSurfaceVariant
        : sample.reachable
        ? OpenHandStatusColors.success
        : OpenHandStatusColors.error;
    return _ProxyDetailSection(
      icon: Icons.route_outlined,
      title: text(zh: '代理网关与转发诊断', en: 'Gateway and forwarding'),
      trailing: OpenHandInlineRevealSwitcher(
        presentKey: const ValueKey<String>('probe-loading'),
        child: _testingProbe
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
      ),
      child: OpenHandContentStateSwitcher(
        stateKey: _testingProbe
            ? 'probe-running'
            : sample == null
            ? 'probe-pending'
            : sample.reachable
            ? 'probe-ready'
            : sample.gatewayReachable
            ? 'probe-forwarding-failed'
            : 'probe-gateway-failed',
        alignment: AlignmentDirectional.topStart,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _ProxyMetric(
                  icon: sample?.gatewayReachable == true
                      ? Icons.dns_outlined
                      : Icons.portable_wifi_off_rounded,
                  label: sample == null
                      ? text(zh: '网关待检测', en: 'Gateway pending')
                      : sample.gatewayReachable
                      ? text(zh: '网关已连接', en: 'Gateway connected')
                      : text(zh: '网关不可达', en: 'Gateway unreachable'),
                  color: gatewayColor,
                ),
                _ProxyMetric(
                  icon: sample?.reachable == true
                      ? Icons.lock_open_rounded
                      : Icons.link_off_rounded,
                  label: sample == null
                      ? text(zh: '转发待检测', en: 'Forwarding pending')
                      : sample.reachable
                      ? text(zh: 'HTTPS 隧道可用', en: 'HTTPS tunnel ready')
                      : text(zh: '代理转发失败', en: 'Forwarding failed'),
                  color: forwardingColor,
                ),
                if (sample?.latencyMs != null)
                  _ProxyMetric(
                    icon: Icons.speed_rounded,
                    label: '${sample!.latencyMs} ms',
                    color: forwardingColor,
                  ),
                if (sample?.statusCode != null)
                  _ProxyMetric(
                    icon: Icons.http_rounded,
                    label: 'HTTP ${sample!.statusCode}',
                    color: forwardingColor,
                  ),
                if (sample != null)
                  _ProxyMetric(
                    icon: Icons.schedule_rounded,
                    label: _timeLabel(sample.checkedAt),
                    color: colors.onSurfaceVariant,
                  ),
              ],
            ),
            OpenHandVerticalRevealSwitcher(
              presentKey: const ValueKey<String>('probe-diagnostic'),
              child: sample?.error?.isNotEmpty == true
                  ? Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        sample!.error!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: OpenHandStatusColors.error,
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdentitySection(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = openHandTextResolver(context);
    final identity = _endpoint.identity;
    final blockedByProbe =
        identity == null &&
        _endpoint.latestSample?.reachable == false &&
        !_loadingIdentity &&
        _identityError == null;
    return _ProxyDetailSection(
      icon: Icons.badge_outlined,
      title: text(zh: '出口身份与地理归属', en: 'Exit identity and location'),
      trailing: OpenHandInlineRevealSwitcher(
        presentKey: const ValueKey<String>('identity-loading'),
        child: _loadingIdentity
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
      ),
      child: OpenHandContentStateSwitcher(
        stateKey: identity != null
            ? 'identity-ready'
            : _identityError != null
            ? 'identity-error'
            : blockedByProbe
            ? 'identity-blocked'
            : 'identity-loading',
        alignment: AlignmentDirectional.topStart,
        child: identity == null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    blockedByProbe
                        ? text(
                            zh: '代理转发尚未连通，出口身份识别未启动。',
                            en: 'Forwarding is unavailable, so identity lookup has not started.',
                          )
                        : _identityError ??
                              text(
                                zh: '正在通过该代理识别出口 IP 与网络归属。',
                                en: 'Resolving the exit identity through this proxy.',
                              ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: _identityError == null
                          ? colors.onSurfaceVariant
                          : OpenHandStatusColors.warning,
                    ),
                  ),
                  OpenHandVerticalRevealSwitcher(
                    presentKey: const ValueKey<String>('identity-retry'),
                    child: _identityError == null && !blockedByProbe
                        ? null
                        : Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: OpenHandDialogActionButton.secondary(
                                icon: Icons.refresh_rounded,
                                onPressed: _loadingIdentity || _testingProbe
                                    ? null
                                    : blockedByProbe
                                    ? () => _refreshProbe(
                                        refreshIdentityOnSuccess: true,
                                      )
                                    : _refreshIdentity,
                                label: blockedByProbe
                                    ? text(zh: '检测并识别', en: 'Test and identify')
                                    : text(zh: '重新识别', en: 'Retry'),
                              ),
                            ),
                          ),
                  ),
                ],
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final uri = Uri.parse(_endpoint.url);
                  final classificationKnown =
                      identity.networkType != 'unknown' &&
                      identity.cleanliness != 'unknown';
                  final fields = <({String label, String value, IconData icon})>[
                    (
                      label: text(zh: '出口 IP', en: 'Exit IP'),
                      value: identity.exitIp,
                      icon: Icons.language_rounded,
                    ),
                    (
                      label: text(zh: 'IP 类型', en: 'IP type'),
                      value: identity.ipType,
                      icon: Icons.device_hub_rounded,
                    ),
                    (
                      label: text(zh: '网络类型', en: 'Network type'),
                      value: _networkTypeLabel(identity.networkType, text),
                      icon: Icons.account_tree_outlined,
                    ),
                    (
                      label: text(zh: '干净度', en: 'Cleanliness'),
                      value: _cleanlinessLabel(identity.cleanliness, text),
                      icon: Icons.verified_user_outlined,
                    ),
                    (
                      label: text(zh: '地理位置', en: 'Location'),
                      value: identity.location.isEmpty
                          ? '--'
                          : identity.location,
                      icon: Icons.location_on_outlined,
                    ),
                    (
                      label: text(
                        zh: '洲 / 国家代码',
                        en: 'Continent / country code',
                      ),
                      value:
                          '${identity.continent.isEmpty ? '--' : identity.continent} · ${identity.countryCode.isEmpty ? '--' : identity.countryCode}',
                      icon: Icons.public_rounded,
                    ),
                    (
                      label: text(zh: '时区 / 币种', en: 'Timezone / currency'),
                      value:
                          '${identity.timezone.isEmpty ? '--' : identity.timezone} · ${identity.currency.isEmpty ? '--' : identity.currency}',
                      icon: Icons.schedule_rounded,
                    ),
                    (
                      label: text(zh: '邮政编码', en: 'Postal code'),
                      value: identity.postalCode.isEmpty
                          ? '--'
                          : identity.postalCode,
                      icon: Icons.local_post_office_outlined,
                    ),
                    (
                      label: text(zh: 'ISP', en: 'ISP'),
                      value: identity.isp.isEmpty ? '--' : identity.isp,
                      icon: Icons.cell_tower_rounded,
                    ),
                    (
                      label: text(zh: '组织', en: 'Organization'),
                      value: identity.organization.isEmpty
                          ? '--'
                          : identity.organization,
                      icon: Icons.business_outlined,
                    ),
                    (
                      label: text(zh: '自治系统', en: 'Autonomous system'),
                      value: <String>[
                        identity.asn,
                        identity.asName,
                      ].where((item) => item.trim().isNotEmpty).join(' · '),
                      icon: Icons.hub_outlined,
                    ),
                    (
                      label: text(zh: '坐标', en: 'Coordinates'),
                      value:
                          identity.latitude == null ||
                              identity.longitude == null
                          ? '--'
                          : '${identity.latitude!.toStringAsFixed(4)}, ${identity.longitude!.toStringAsFixed(4)}',
                      icon: Icons.my_location_rounded,
                    ),
                    (
                      label: text(zh: '代理协议', en: 'Proxy protocol'),
                      value:
                          '${uri.scheme.toUpperCase()} · ${uri.host}:${uri.port}',
                      icon: Icons.lock_outline_rounded,
                    ),
                    (
                      label: text(zh: '认证状态', en: 'Authentication'),
                      value: uri.userInfo.isEmpty
                          ? text(zh: '无认证', en: 'No authentication')
                          : text(zh: '用户名与密码', en: 'Username and password'),
                      icon: Icons.key_outlined,
                    ),
                  ];
                  final columns = constraints.maxWidth >= 680 ? 3 : 1;
                  const gap = 8.0;
                  final width =
                      (constraints.maxWidth - gap * (columns - 1)) / columns;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OpenHandVerticalRevealSwitcher(
                        presentKey: const ValueKey<String>(
                          'identity-refresh-error',
                        ),
                        child: _identityError == null
                            ? null
                            : Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Text(
                                  text(
                                    zh: '出口身份刷新失败：$_identityError。当前显示上次识别结果。',
                                    en: 'Identity refresh failed: $_identityError. Showing the last result.',
                                  ),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: OpenHandStatusColors.warning,
                                  ),
                                ),
                              ),
                      ),
                      Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: fields
                            .map(
                              (field) => SizedBox(
                                width: width,
                                child: _ProxyDetailField(
                                  icon: field.icon,
                                  label: field.label,
                                  value: field.value.isEmpty
                                      ? '--'
                                      : field.value,
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (classificationKnown) ...[
                            _ProxyMetric(
                              icon: Icons.phone_android_rounded,
                              label: identity.mobile
                                  ? text(zh: '移动网络', en: 'Mobile network')
                                  : text(zh: '非移动网络', en: 'Not mobile'),
                              color: identity.mobile
                                  ? OpenHandStatusColors.warning
                                  : colors.onSurfaceVariant,
                            ),
                            _ProxyMetric(
                              icon: Icons.vpn_lock_outlined,
                              label: identity.proxy
                                  ? text(zh: '代理特征已识别', en: 'Proxy detected')
                                  : text(zh: '未识别代理特征', en: 'No proxy flag'),
                              color: identity.proxy
                                  ? OpenHandStatusColors.warning
                                  : OpenHandStatusColors.success,
                            ),
                            _ProxyMetric(
                              icon: Icons.cloud_outlined,
                              label: identity.hosting
                                  ? text(zh: '数据中心托管', en: 'Hosting network')
                                  : text(zh: '非托管网络', en: 'Not hosting'),
                              color: identity.hosting
                                  ? OpenHandStatusColors.info
                                  : OpenHandStatusColors.success,
                            ),
                          ] else
                            _ProxyMetric(
                              icon: Icons.help_outline_rounded,
                              label: text(
                                zh: '风险特征数据不足',
                                en: 'Risk signals unavailable',
                              ),
                              color: colors.onSurfaceVariant,
                            ),
                          _ProxyMetric(
                            icon: Icons.update_rounded,
                            label: _timeLabel(identity.observedAt),
                            color: colors.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _buildCharts(
    BuildContext context,
    AiExposureProxyUsageStatistics statistics,
  ) {
    final colors = Theme.of(context).colorScheme;
    final text = openHandTextResolver(context);
    final requestPoints = statistics.recentRequests
        .map((item) {
          final color = item.succeeded
              ? OpenHandStatusColors.success
              : item.timedOut
              ? OpenHandStatusColors.warning
              : OpenHandStatusColors.error;
          return _ProxyDetailTrendPoint(
            at: item.at,
            value: item.responseTimeMs,
            status: item.succeeded
                ? text(zh: '请求成功', en: 'Succeeded')
                : item.timedOut
                ? text(zh: '请求超时', en: 'Timed out')
                : text(zh: '请求失败', en: 'Failed'),
            detail: item.statusCode == null
                ? text(zh: '无 HTTP 状态', en: 'No HTTP status')
                : 'HTTP ${item.statusCode}',
            color: color,
            icon: item.succeeded
                ? Icons.check_circle_outline_rounded
                : item.timedOut
                ? Icons.timer_off_outlined
                : Icons.error_outline_rounded,
          );
        })
        .toList(growable: false);
    final probePoints = _endpoint.samples
        .where((item) => item.reachable)
        .map(
          (item) => _ProxyDetailTrendPoint(
            at: item.checkedAt,
            value: item.latencyMs!,
            status: text(zh: '连接成功', en: 'Connection succeeded'),
            detail: item.statusCode == null
                ? text(zh: '代理连接可用', en: 'Proxy connection ready')
                : 'HTTP ${item.statusCode}',
            color: OpenHandStatusColors.success,
            icon: Icons.network_check_rounded,
          ),
        )
        .toList(growable: false);
    final requestChart = _ProxyPoolChartPanel(
      icon: Icons.show_chart_rounded,
      title: text(zh: '真实请求耗时', en: 'Request latency'),
      height: 156,
      child: _ProxyDetailTrendChart(
        points: requestPoints,
        lineColor: colors.primary,
        emptyLabel: text(zh: '暂无真实请求', en: 'No request samples'),
        seriesLabel: 'requests',
      ),
    );
    final probeChart = _ProxyPoolChartPanel(
      icon: Icons.network_ping_rounded,
      title: text(zh: '巡检连接延迟', en: 'Probe latency'),
      height: 156,
      child: _ProxyDetailTrendChart(
        points: probePoints,
        lineColor: OpenHandStatusColors.info,
        emptyLabel: text(zh: '暂无巡检样本', en: 'No probe samples'),
        seriesLabel: 'probe',
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 680) {
          return Column(
            children: [requestChart, const SizedBox(height: 8), probeChart],
          );
        }
        return Row(
          children: [
            Expanded(child: requestChart),
            const SizedBox(width: 8),
            Expanded(child: probeChart),
          ],
        );
      },
    );
  }

  Widget _buildHttpDistribution(
    BuildContext context,
    AiExposureProxyUsageStatistics statistics,
  ) {
    final values = <({String label, int value, Color color})>[
      (
        label: '2xx',
        value: statistics.status2xx,
        color: OpenHandStatusColors.success,
      ),
      (
        label: '3xx',
        value: statistics.status3xx,
        color: OpenHandStatusColors.info,
      ),
      (
        label: '4xx',
        value: statistics.status4xx,
        color: OpenHandStatusColors.warning,
      ),
      (
        label: '5xx',
        value: statistics.status5xx,
        color: OpenHandStatusColors.error,
      ),
    ];
    final maxValue = values.fold<int>(
      1,
      (max, item) => item.value > max ? item.value : max,
    );
    return _ProxyDetailSection(
      icon: Icons.http_rounded,
      title: openHandLocalizedText(
        context,
        zh: 'HTTP 状态码分布',
        en: 'HTTP status distribution',
      ),
      child: Column(
        children: values
            .map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    SizedBox(
                      width: 42,
                      child: Text(
                        item.label,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: item.value / maxValue,
                          minHeight: 8,
                          color: item.color,
                          backgroundColor: item.color.withValues(alpha: 0.1),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 48,
                      child: Text(
                        '${item.value}',
                        textAlign: TextAlign.end,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  Widget _buildRecentRequests(
    BuildContext context,
    AiExposureProxyUsageStatistics statistics,
  ) {
    final text = openHandTextResolver(context);
    final requests = statistics.recentRequests.reversed
        .take(12)
        .toList(growable: false);
    return _ProxyDetailSection(
      icon: Icons.history_rounded,
      title: text(zh: '最近请求记录', en: 'Recent requests'),
      trailing: Text(
        '${requests.length}/$kAiExposureProxyRequestSampleLimit',
        style: Theme.of(context).textTheme.labelMedium,
      ),
      child: requests.isEmpty
          ? Text(
              text(zh: '该节点尚无真实请求记录。', en: 'No request records yet.'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          : Column(
              children: requests
                  .map((item) {
                    final color = item.succeeded
                        ? OpenHandStatusColors.success
                        : item.timedOut
                        ? OpenHandStatusColors.warning
                        : OpenHandStatusColors.error;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Icon(
                            item.succeeded
                                ? Icons.check_circle_outline_rounded
                                : item.timedOut
                                ? Icons.timer_off_outlined
                                : Icons.error_outline_rounded,
                            size: 18,
                            color: color,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              item.succeeded
                                  ? text(zh: '请求成功', en: 'Succeeded')
                                  : item.timedOut
                                  ? text(zh: '请求超时', en: 'Timed out')
                                  : text(zh: '请求失败', en: 'Failed'),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          if (item.statusCode != null)
                            SizedBox(
                              width: 56,
                              child: Text(
                                'HTTP ${item.statusCode}',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ),
                          SizedBox(
                            width: 72,
                            child: Text(
                              '${item.responseTimeMs} ms',
                              textAlign: TextAlign.end,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 58,
                            child: Text(
                              _timeLabel(item.at),
                              textAlign: TextAlign.end,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                        ],
                      ),
                    );
                  })
                  .toList(growable: false),
            ),
    );
  }
}

class _ProxyDetailSection extends StatelessWidget {
  const _ProxyDetailSection({
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: colors.primary),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ProxyDetailField extends StatelessWidget {
  const _ProxyDetailField({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.75),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: colors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _networkTypeLabel(String? value, OpenHandLocalizedTextResolver text) =>
    switch (value) {
      'mobile' => text(zh: '移动网络', en: 'Mobile'),
      'datacenter' => text(zh: '数据中心', en: 'Datacenter'),
      'public_proxy' => text(zh: '公共代理', en: 'Public proxy'),
      'residential' => text(zh: '住宅/运营商', en: 'Residential / ISP'),
      'unknown' => text(zh: '类型未判定', en: 'Type not determined'),
      _ => text(zh: '待识别', en: 'Pending'),
    };

String _cleanlinessLabel(String? value, OpenHandLocalizedTextResolver text) =>
    switch (value) {
      'high' => text(zh: '高干净度', en: 'High cleanliness'),
      'medium' => text(zh: '中等干净度', en: 'Medium cleanliness'),
      'low' => text(zh: '低干净度', en: 'Low cleanliness'),
      'unknown' => text(zh: '数据不足', en: 'Insufficient data'),
      _ => text(zh: '干净度待识别', en: 'Cleanliness pending'),
    };

Color _cleanlinessColor(String? value, ColorScheme colors) => switch (value) {
  'high' => OpenHandStatusColors.success,
  'medium' => OpenHandStatusColors.warning,
  'low' => OpenHandStatusColors.error,
  'unknown' => colors.onSurfaceVariant,
  _ => colors.onSurfaceVariant,
};

class _ProxyInputSuffixButton extends StatelessWidget {
  const _ProxyInputSuffixButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: 48,
        child: InkResponse(
          onTap: onPressed,
          radius: 18,
          hoverColor: colors.onSurfaceVariant.withValues(alpha: 0.07),
          focusColor: colors.primary.withValues(alpha: 0.10),
          splashColor: colors.primary.withValues(alpha: 0.12),
          highlightColor: colors.primary.withValues(alpha: 0.07),
          mouseCursor: SystemMouseCursors.click,
          child: Center(
            child: IconTheme.merge(
              data: IconThemeData(size: 20, color: colors.onSurfaceVariant),
              child: icon,
            ),
          ),
        ),
      ),
    );
  }
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
  final _rawProxy = TextEditingController();
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _username;
  late final TextEditingController _password;
  String _scheme = 'http';
  String? _parsedProxyAddress;
  String? _proxyAddressError;
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
    _rawProxy.dispose();
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
    final proxyAddressParsed = _parsedProxyAddress == _rawProxy.text.trim();
    return Padding(
      padding: const EdgeInsets.all(22),
      child: SingleChildScrollView(
        physics: openHandDialogAwareScrollPhysics(context),
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
                  ServiceDialogHeaderIconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    onPressed: widget.onCancel,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (!editing) ...[
                TextFormField(
                  controller: _rawProxy,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: text(zh: '代理地址快速解析', en: 'Parse proxy address'),
                    hintText: 'host:port:username:password',
                    errorText: _proxyAddressError,
                    border: const OutlineInputBorder(),
                    suffixIcon: _ProxyInputSuffixButton(
                      tooltip: text(zh: '解析并填充表单', en: 'Parse and fill form'),
                      onPressed: () => _applyProxyAddress(reportInvalid: true),
                      icon: AnimatedSwitcher(
                        duration: openHandMotionDuration(
                          context,
                          const Duration(milliseconds: 220),
                        ),
                        child: Icon(
                          proxyAddressParsed
                              ? Icons.check_circle_outline_rounded
                              : Icons.auto_fix_high_rounded,
                          key: ValueKey<bool>(proxyAddressParsed),
                          color: proxyAddressParsed
                              ? OpenHandStatusColors.success
                              : null,
                        ),
                      ),
                    ),
                  ),
                  validator: (value) {
                    final raw = value?.trim() ?? '';
                    if (raw.isEmpty || raw == _parsedProxyAddress) return null;
                    return text(
                      zh: '请先解析有效的代理地址',
                      en: 'Parse a valid proxy address first',
                    );
                  },
                  onChanged: (value) {
                    final raw = value.trim();
                    if (_parsedProxyAddress != null ||
                        _proxyAddressError != null) {
                      setState(() {
                        _parsedProxyAddress = null;
                        _proxyAddressError = null;
                      });
                    }
                    final uri = raw.contains('://') ? Uri.tryParse(raw) : null;
                    if (uri?.hasPort == true ||
                        RegExp(
                          r'^(\[[^\]\s]+\]|[^:\s]+):\d+:[^:\s]+:.*$',
                        ).hasMatch(raw)) {
                      _applyProxyAddress();
                    }
                  },
                  onFieldSubmitted: (_) =>
                      _applyProxyAddress(reportInvalid: true),
                ),
                OpenHandVerticalRevealSwitcher(
                  presentKey: const ValueKey<String>('proxy-address-parsed'),
                  child: proxyAddressParsed
                      ? Padding(
                          padding: const EdgeInsets.only(top: 7),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.task_alt_rounded,
                                size: 16,
                                color: OpenHandStatusColors.success,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  text(
                                    zh: '已解析并填充结构化代理配置',
                                    en: 'Proxy settings parsed and filled',
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: OpenHandStatusColors.success,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 10),
              ],
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
              LayoutBuilder(
                builder: (context, constraints) {
                  final scheme = DropdownButtonFormField<String>(
                    initialValue: _scheme,
                    isExpanded: true,
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
                  );
                  final host = TextFormField(
                    controller: _host,
                    decoration: InputDecoration(
                      labelText: text(zh: '主机', en: 'Host'),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? text(zh: '请输入主机', en: 'Enter a host')
                        : null,
                  );
                  final port = TextFormField(
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
                  );
                  if (constraints.maxWidth < 420) {
                    return Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: scheme),
                            const SizedBox(width: 10),
                            Expanded(child: port),
                          ],
                        ),
                        const SizedBox(height: 10),
                        host,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      SizedBox(width: 118, child: scheme),
                      const SizedBox(width: 10),
                      Expanded(child: host),
                      const SizedBox(width: 10),
                      SizedBox(width: 110, child: port),
                    ],
                  );
                },
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
                  suffixIcon: _ProxyInputSuffixButton(
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
              Wrap(
                alignment: WrapAlignment.end,
                spacing: kOpenHandDialogActionSpacing,
                runSpacing: kOpenHandDialogActionSpacing,
                children: [
                  OpenHandDialogActionButton.secondary(
                    onPressed: widget.onCancel,
                    label: text(zh: '取消', en: 'Cancel'),
                  ),
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
      ),
    );
  }

  void _applyProxyAddress({bool reportInvalid = false}) {
    final raw = _rawProxy.text.trim();
    try {
      final endpoint = AiExposureProxyEndpoint.parse(raw);
      final uri = Uri.parse(endpoint.url);
      final separator = uri.userInfo.indexOf(':');
      final username = uri.userInfo.isEmpty
          ? ''
          : Uri.decodeComponent(
              separator < 0
                  ? uri.userInfo
                  : uri.userInfo.substring(0, separator),
            );
      final password = separator < 0
          ? ''
          : Uri.decodeComponent(uri.userInfo.substring(separator + 1));
      setState(() {
        _scheme = uri.scheme;
        _host.text = uri.host;
        _port.text = uri.port.toString();
        _username.text = username;
        _password.text = password;
        if (_name.text.trim().isEmpty) _name.text = endpoint.name;
        _parsedProxyAddress = raw;
        _proxyAddressError = null;
      });
    } on FormatException catch (error) {
      if (reportInvalid) {
        setState(() {
          _parsedProxyAddress = null;
          _proxyAddressError = error.message;
        });
      }
    }
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
    required this.endpoint,
    required this.statistics,
    required this.testing,
    required this.busy,
    required this.selectionMode,
    required this.selected,
    required this.onSelectedChanged,
    required this.onEnabledChanged,
    required this.onTest,
    required this.onDetails,
    required this.onExport,
    required this.onEdit,
    required this.onDelete,
  });

  final AiExposureProxyEndpoint endpoint;
  final AiExposureProxyUsageStatistics statistics;
  final bool testing;
  final bool busy;
  final bool selectionMode;
  final bool selected;
  final ValueChanged<bool> onSelectedChanged;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback onTest;
  final VoidCallback onDetails;
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
        OpenHandInlineRevealSwitcher(
          presentKey: const ValueKey<String>('proxy-selector'),
          child: selectionMode
              ? Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Tooltip(
                    message: selected
                        ? text(zh: '取消选择', en: 'Deselect node')
                        : text(zh: '选择节点', en: 'Select node'),
                    child: Checkbox(
                      value: selected,
                      onChanged: busy
                          ? null
                          : (value) => onSelectedChanged(value == true),
                    ),
                  ),
                )
              : null,
        ),
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
                  if (sample?.gatewayReachable == true &&
                      sample?.reachable != true)
                    _ProxyMetric(
                      icon: Icons.dns_outlined,
                      label: text(zh: '网关已连接', en: 'Gateway connected'),
                      color: OpenHandStatusColors.warning,
                    ),
                  OpenHandInlineRevealSwitcher(
                    presentKey: const ValueKey<String>('probe-latency'),
                    child: sample?.latencyMs == null
                        ? null
                        : _ProxyMetric(
                            icon: Icons.speed_rounded,
                            label: '${sample!.latencyMs} ms',
                            color: tone.color,
                          ),
                  ),
                  _ProxyMetric(
                    icon: Icons.route_outlined,
                    label: text(
                      zh: '请求 ${statistics.requests}',
                      en: '${statistics.requests} requests',
                    ),
                    color: colors.onSurfaceVariant,
                  ),
                  _ProxyMetric(
                    icon: Icons.check_circle_outline_rounded,
                    label: text(
                      zh: '成功 ${statistics.successes}',
                      en: '${statistics.successes} success',
                    ),
                    color: OpenHandStatusColors.success,
                  ),
                  _ProxyMetric(
                    icon: Icons.error_outline_rounded,
                    label: text(
                      zh: '失败 ${statistics.failures}',
                      en: '${statistics.failures} failed',
                    ),
                    color: OpenHandStatusColors.error,
                  ),
                  _ProxyMetric(
                    icon: Icons.timer_off_outlined,
                    label: text(
                      zh: '超时 ${statistics.timeouts}',
                      en: '${statistics.timeouts} timeout',
                    ),
                    color: OpenHandStatusColors.warning,
                  ),
                  _ProxyMetric(
                    icon: Icons.av_timer_rounded,
                    label: '${statistics.averageResponseTimeMs} ms',
                    color: colors.primary,
                  ),
                  OpenHandInlineRevealSwitcher(
                    presentKey: const ValueKey<String>('probe-time'),
                    child: sample == null
                        ? null
                        : _ProxyMetric(
                            icon: Icons.schedule_rounded,
                            label: _timeLabel(sample.checkedAt),
                            color: colors.onSurfaceVariant,
                          ),
                  ),
                ],
              ),
              OpenHandVerticalRevealSwitcher(
                presentKey: const ValueKey<String>('probe-error'),
                child: sample?.error?.isNotEmpty == true
                    ? Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          sample!.error!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: OpenHandStatusColors.error,
                          ),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
    final chart = _ProxyLatencyChart(endpoint: endpoint);
    final actionChildren = <Widget>[
      Tooltip(
        message: endpoint.enabled
            ? text(zh: '禁用此节点', en: 'Disable node')
            : text(zh: '启用此节点', en: 'Enable node'),
        child: Switch(
          value: endpoint.enabled,
          onChanged: busy || selectionMode ? null : onEnabledChanged,
        ),
      ),
      IconButton(
        tooltip: text(zh: '测试连通性与延迟', en: 'Test connectivity'),
        onPressed: busy || testing || selectionMode ? null : onTest,
        icon: testing
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.speed_rounded),
      ),
      IconButton(
        tooltip: text(zh: '查看代理详情', en: 'View proxy details'),
        onPressed: onDetails,
        icon: const Icon(Icons.manage_search_rounded),
      ),
      IconButton(
        tooltip: text(zh: '编辑代理配置', en: 'Edit proxy settings'),
        onPressed: busy || selectionMode ? null : onEdit,
        icon: const Icon(Icons.edit_outlined),
      ),
      IconButton(
        tooltip: text(zh: '导出此代理', en: 'Export proxy'),
        onPressed: busy ? null : onExport,
        icon: const Icon(Icons.file_download_outlined),
      ),
      IconButton(
        tooltip: text(zh: '移除代理', en: 'Remove proxy'),
        onPressed: busy || selectionMode ? null : onDelete,
        style: IconButton.styleFrom(foregroundColor: colors.error),
        icon: const Icon(Icons.delete_outline_rounded),
      ),
    ];
    final actions = ServiceDialogIconActions(children: actionChildren);
    return AnimatedContainer(
      duration: openHandMotionDuration(
        context,
        const Duration(milliseconds: 260),
      ),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: selected
            ? colors.primaryContainer.withValues(alpha: 0.32)
            : endpoint.enabled
            ? colors.surfaceContainerHighest.withValues(alpha: 0.26)
            : colors.surfaceContainerLow.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected
              ? colors.primary.withValues(alpha: 0.58)
              : sample != null
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
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: kServiceDialogItemActionGap,
                    runSpacing: 4,
                    children: actionChildren,
                  ),
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

class _ProxyLatencyChart extends StatefulWidget {
  const _ProxyLatencyChart({required this.endpoint});

  final AiExposureProxyEndpoint endpoint;

  @override
  State<_ProxyLatencyChart> createState() => _ProxyLatencyChartState();
}

class _ProxyLatencyChartState extends State<_ProxyLatencyChart> {
  static const double _tooltipWidth = 176;
  int? _hoveredIndex;

  void _updateHoveredSample(
    PointerHoverEvent event,
    double width,
    int sampleCount,
  ) {
    if (sampleCount == 0 || width <= 16) return;
    final ratio = ((event.localPosition.dx - 8) / (width - 16)).clamp(0.0, 1.0);
    final index = (ratio * (sampleCount - 1)).round();
    if (index != _hoveredIndex) setState(() => _hoveredIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final samples = widget.endpoint.samples
        .where((sample) => sample.reachable)
        .toList(growable: false);
    final values = samples
        .map((sample) => sample.latencyMs!.toDouble())
        .toList(growable: false);
    final revision =
        widget.endpoint.latestSample?.checkedAt.microsecondsSinceEpoch ?? 0;
    final hoveredIndex = _hoveredIndex == null || samples.isEmpty
        ? null
        : _hoveredIndex!.clamp(0, samples.length - 1);
    final hoveredSample = hoveredIndex == null ? null : samples[hoveredIndex];
    return SizedBox(
      height: 70,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pointX = hoveredIndex == null || samples.length <= 1
              ? 8.0
              : 8 +
                    (constraints.maxWidth - 16) *
                        hoveredIndex /
                        (samples.length - 1);
          final tooltipLeft = (pointX - _tooltipWidth / 2).clamp(
            0.0,
            (constraints.maxWidth - _tooltipWidth).clamp(0.0, double.infinity),
          );
          return MouseRegion(
            cursor: samples.isEmpty
                ? MouseCursor.defer
                : SystemMouseCursors.precise,
            onHover: (event) => _updateHoveredSample(
              event,
              constraints.maxWidth,
              samples.length,
            ),
            onExit: (_) {
              if (_hoveredIndex != null) setState(() => _hoveredIndex = null);
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
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
                              values: values
                                  .map((value) => value * scale)
                                  .toList(),
                              color: colors.primary,
                            ),
                          ],
                          gridColor: colors.outlineVariant.withValues(
                            alpha: 0.55,
                          ),
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
                ),
                if (hoveredSample != null)
                  Positioned(
                    left: pointX.clamp(0.0, constraints.maxWidth),
                    top: 8,
                    bottom: 16,
                    child: IgnorePointer(
                      child: Container(
                        width: 1,
                        color: colors.primary.withValues(alpha: 0.38),
                      ),
                    ),
                  ),
                AnimatedPositioned(
                  duration: openHandMotionDuration(
                    context,
                    const Duration(milliseconds: 180),
                  ),
                  curve: Curves.easeOutCubic,
                  left: tooltipLeft,
                  top: 2,
                  width: _tooltipWidth,
                  child: IgnorePointer(
                    child: AnimatedSwitcher(
                      duration: openHandMotionDuration(
                        context,
                        const Duration(milliseconds: 220),
                      ),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          alignment: Alignment.bottomCenter,
                          scale: Tween<double>(
                            begin: .92,
                            end: 1,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: hoveredSample == null
                          ? const SizedBox.shrink(
                              key: ValueKey<String>('latency-tooltip-empty'),
                            )
                          : _ProxyLatencyTooltip(
                              key: ValueKey<DateTime>(hoveredSample.checkedAt),
                              sample: hoveredSample,
                              index: hoveredIndex! + 1,
                              total: samples.length,
                            ),
                    ),
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

class _ProxyLatencyTooltip extends StatelessWidget {
  const _ProxyLatencyTooltip({
    super.key,
    required this.sample,
    required this.index,
    required this.total,
  });

  final AiExposureProxyProbeSample sample;
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.primary.withValues(alpha: .32)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: colors.shadow.withValues(alpha: .16),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.speed_rounded, size: 14, color: colors.primary),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    '${sample.latencyMs} ms',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: colors.primary,
                    ),
                  ),
                ),
                Text('$index/$total', style: theme.textTheme.labelSmall),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              _dateTimeLabel(sample.checkedAt),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            Text(
              sample.statusCode == null
                  ? openHandLocalizedText(
                      context,
                      zh: '连接成功',
                      en: 'Connection succeeded',
                    )
                  : 'HTTP ${sample.statusCode}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: OpenHandStatusColors.success,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProxyCleanupMenuItem extends StatelessWidget {
  const _ProxyCleanupMenuItem({
    required this.icon,
    required this.label,
    required this.detail,
    required this.count,
  });

  final IconData icon;
  final String label;
  final String detail;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = count > 0;
    final color = enabled
        ? theme.colorScheme.onSurfaceVariant
        : theme.disabledColor;
    return SizedBox(
      width: 280,
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: enabled ? null : theme.disabledColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: color),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$count',
            style: theme.textTheme.labelLarge?.copyWith(
              color: enabled ? theme.colorScheme.primary : theme.disabledColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
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

_ProxyEndpointHealth _proxyEndpointHealth(AiExposureProxyEndpoint endpoint) {
  if (!endpoint.enabled) return _ProxyEndpointHealth.disabled;
  final sample = endpoint.latestSample;
  if (sample == null) return _ProxyEndpointHealth.unchecked;
  if (!sample.reachable) {
    return sample.gatewayReachable
        ? _ProxyEndpointHealth.forwardingFailed
        : _ProxyEndpointHealth.unavailable;
  }
  return sample.latencyMs! <= _kProxyHighLatencyThresholdMs
      ? _ProxyEndpointHealth.healthy
      : _ProxyEndpointHealth.highLatency;
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
  return switch (_proxyEndpointHealth(endpoint)) {
    _ProxyEndpointHealth.disabled => (
      color: Theme.of(context).colorScheme.outline,
      icon: Icons.pause_circle_outline_rounded,
      label: text(zh: '已禁用', en: 'Disabled'),
    ),
    _ProxyEndpointHealth.unchecked => (
      color: Theme.of(context).colorScheme.outline,
      icon: Icons.help_outline_rounded,
      label: text(zh: '未检测', en: 'Unchecked'),
    ),
    _ProxyEndpointHealth.unavailable => (
      color: OpenHandStatusColors.error,
      icon: Icons.cloud_off_outlined,
      label: text(zh: '不可用', en: 'Unavailable'),
    ),
    _ProxyEndpointHealth.forwardingFailed => (
      color: OpenHandStatusColors.error,
      icon: Icons.link_off_rounded,
      label: text(zh: '转发失败', en: 'Forwarding failed'),
    ),
    _ProxyEndpointHealth.healthy => (
      color: OpenHandStatusColors.success,
      icon: Icons.check_circle_outline_rounded,
      label: text(zh: '畅通', en: 'Healthy'),
    ),
    _ProxyEndpointHealth.highLatency => (
      color: OpenHandStatusColors.warning,
      icon: Icons.warning_amber_rounded,
      label: text(zh: '高延迟', en: 'High latency'),
    ),
  };
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
    if (values.length > _kMaxProxyImportRecords) {
      throw const FormatException('代理文件记录不能超过 $_kMaxProxyImportRecords 条。');
    }
    for (final value in values) {
      AiExposureProxyEndpoint? endpoint;
      try {
        endpoint = AiExposureProxyEndpoint.fromJson(value);
      } on FormatException {
        invalid++;
      }
      if (endpoint == null) continue;
      if (endpoints.length >= _kMaxProxyEndpoints) {
        throw const FormatException('有效代理不能超过 $_kMaxProxyEndpoints 个。');
      }
      endpoints.add(endpoint);
    }
  } else {
    var records = 0;
    var lineStart = 0;
    for (var index = 0; index <= content.length; index++) {
      final atEnd = index == content.length;
      final codeUnit = atEnd ? -1 : content.codeUnitAt(index);
      if (!atEnd && codeUnit != 0x0A && codeUnit != 0x0D) continue;
      final value = content.substring(lineStart, index).trim();
      if (codeUnit == 0x0D &&
          index + 1 < content.length &&
          content.codeUnitAt(index + 1) == 0x0A) {
        index++;
      }
      lineStart = index + 1;
      if (value.isEmpty || value.startsWith('#')) continue;
      records++;
      if (records > _kMaxProxyImportRecords) {
        throw const FormatException('代理文件记录不能超过 $_kMaxProxyImportRecords 条。');
      }
      AiExposureProxyEndpoint? endpoint;
      try {
        endpoint = AiExposureProxyEndpoint.parse(value);
      } on FormatException {
        invalid++;
      }
      if (endpoint == null) continue;
      if (endpoints.length >= _kMaxProxyEndpoints) {
        throw const FormatException('有效代理不能超过 $_kMaxProxyEndpoints 个。');
      }
      endpoints.add(endpoint);
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

String _dateTimeLabel(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}
