part of 'ai_exposure_monitoring_dialogs.dart';

class _NetworkPanel extends StatelessWidget {
  const _NetworkPanel({required this.controller});

  final ServicesController controller;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = openHandTextResolver(context);
    final configuration = controller.proxyConfiguration;
    final endpoints = configuration.endpoints;
    final activeEndpoints = configuration.activeEndpoints;
    final inspected = endpoints
        .where((endpoint) => endpoint.latestSample != null)
        .length;
    final reachable = endpoints
        .where((endpoint) => endpoint.latestSample?.reachable == true)
        .length;
    final recentRequests =
        endpoints
            .expand((endpoint) => endpoint.statistics.recentRequests)
            .toList()
          ..sort((left, right) => left.at.compareTo(right.at));
    final visibleRequests = recentRequests.length <= 48
        ? recentRequests
        : recentRequests.sublist(recentRequests.length - 48);
    final requests = endpoints.fold<int>(
      0,
      (sum, endpoint) => sum + endpoint.statistics.requests,
    );
    final successes = endpoints.fold<int>(
      0,
      (sum, endpoint) => sum + endpoint.statistics.successes,
    );
    final failures = endpoints.fold<int>(
      0,
      (sum, endpoint) => sum + endpoint.statistics.failures,
    );
    final timeouts = endpoints.fold<int>(
      0,
      (sum, endpoint) => sum + endpoint.statistics.timeouts,
    );
    final totalResponseTime = endpoints.fold<int>(
      0,
      (sum, endpoint) => sum + endpoint.statistics.totalResponseTimeMs,
    );
    final completed = successes + failures + timeouts;
    final averageLatency = completed == 0
        ? 0
        : (totalResponseTime / completed).round();
    final p95Latency = _latencyPercentile(
      visibleRequests.map((sample) => sample.responseTimeMs).toList(),
      0.95,
    );
    final status2xx = endpoints.fold<int>(
      0,
      (sum, endpoint) => sum + endpoint.statistics.status2xx,
    );
    final status3xx = endpoints.fold<int>(
      0,
      (sum, endpoint) => sum + endpoint.statistics.status3xx,
    );
    final status4xx = endpoints.fold<int>(
      0,
      (sum, endpoint) => sum + endpoint.statistics.status4xx,
    );
    final status5xx = endpoints.fold<int>(
      0,
      (sum, endpoint) => sum + endpoint.statistics.status5xx,
    );
    final countryCounts = <String, int>{};
    for (final endpoint in endpoints) {
      final country = endpoint.identity?.country.trim();
      if (country?.isNotEmpty == true) {
        countryCounts.update(country!, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    final endpointItems =
        endpoints
            .map(
              (endpoint) => _DistributionItem(
                endpoint.displayName,
                endpoint.statistics.requests,
                endpoint.latestSample?.reachable == false
                    ? OpenHandStatusColors.error
                    : endpoint.enabled
                    ? colors.primary
                    : colors.outline,
              ),
            )
            .toList()
          ..sort((left, right) => right.value.compareTo(left.value));
    final successRate = completed == 0 ? 0 : successes * 100 / completed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MetricGrid(
          title: '网络遥测',
          metrics: [
            _Metric(
              _MetricInsightId.networkRouteState,
              Icons.route_outlined,
              '选路状态',
              serviceProxyRouteText(controller, text, includePoolCount: false),
              controller.proxyRoute == AiExposureProxyRoute.pool
                  ? _proxyStrategyName(configuration.strategy)
                  : serviceProxyRouteText(controller, text),
              color: controller.proxyRoute == AiExposureProxyRoute.direct
                  ? colors.outline
                  : controller.proxyRoute == AiExposureProxyRoute.pool
                  ? colors.primary
                  : colors.tertiary,
            ),
            _Metric(
              _MetricInsightId.networkProxyNodes,
              Icons.dns_outlined,
              '代理节点',
              '${activeEndpoints.length}/${endpoints.length}',
              '$inspected 个已巡检',
              color: OpenHandStatusColors.info,
            ),
            _Metric(
              _MetricInsightId.networkReachableNodes,
              Icons.cloud_done_outlined,
              '可连通节点',
              '$reachable',
              inspected == 0
                  ? '尚无巡检样本'
                  : '${(reachable * 100 / inspected).toStringAsFixed(1)}% 可用率',
              color: OpenHandStatusColors.success,
            ),
            _Metric(
              _MetricInsightId.networkRequests,
              Icons.swap_vert_rounded,
              '累计请求',
              '$requests',
              '执行中 ${controller.proxyStatus?.inFlight ?? 0}',
              color: colors.primary,
            ),
            _Metric(
              _MetricInsightId.networkSuccesses,
              Icons.check_circle_outline_rounded,
              '成功请求',
              '$successes',
              '${successRate.toStringAsFixed(1)}% 成功率',
              color: OpenHandStatusColors.success,
            ),
            _Metric(
              _MetricInsightId.networkFailures,
              Icons.error_outline_rounded,
              '失败请求',
              '$failures',
              '连续失败 ${endpoints.fold<int>(0, (sum, endpoint) => sum + endpoint.statistics.consecutiveFailures)}',
              color: OpenHandStatusColors.error,
            ),
            _Metric(
              _MetricInsightId.networkTimeouts,
              Icons.timer_off_outlined,
              '超时请求',
              '$timeouts',
              completed == 0
                  ? '--'
                  : '${(timeouts * 100 / completed).toStringAsFixed(1)}% 超时率',
              color: OpenHandStatusColors.warning,
            ),
            _Metric(
              _MetricInsightId.networkAverageLatency,
              Icons.speed_rounded,
              '平均响应',
              '$averageLatency ms',
              '全量完成请求',
              color: colors.secondary,
            ),
            _Metric(
              _MetricInsightId.networkP95Latency,
              Icons.multiline_chart_rounded,
              'p95 响应',
              '$p95Latency ms',
              '最近 ${visibleRequests.length} 个样本',
              color: colors.tertiary,
            ),
            _Metric(
              _MetricInsightId.networkHttp2xx,
              Icons.http_rounded,
              'HTTP 2xx',
              '$status2xx',
              '3xx $status3xx · 4xx $status4xx · 5xx $status5xx',
              color: OpenHandStatusColors.success,
            ),
            _Metric(
              _MetricInsightId.networkExitCountries,
              Icons.public_rounded,
              '出口国家',
              '${countryCounts.length}',
              '${endpoints.where((endpoint) => endpoint.identity != null).length} 个已识别出口',
              color: const Color(0xff0891b2),
            ),
            _Metric(
              _MetricInsightId.networkInspectionPlan,
              Icons.health_and_safety_outlined,
              '巡检计划',
              configuration.inspectionEnabled ? '已启用' : '未启用',
              '${configuration.inspectionIntervalMinutes} 分钟 · 并发 ${configuration.inspectionConcurrency}',
              color: configuration.inspectionEnabled
                  ? OpenHandStatusColors.success
                  : colors.outline,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _OpsPanelGrid(
          children: [
            _TrendPanel(
              id: _TrendInsightId.proxyLatency,
              interpolation: OpenHandChartInterpolation.smooth,
              icon: Icons.query_stats_rounded,
              title: '代理响应耗时趋势',
              subtitle: '最近 ${visibleRequests.length} 个请求样本',
              sampleLabels: visibleRequests
                  .map((sample) => _shortDateTime(sample.at))
                  .toList(growable: false),
              series: [
                OpenHandChartSeries(
                  label: '响应耗时',
                  values: visibleRequests
                      .map((sample) => sample.responseTimeMs.toDouble())
                      .toList(),
                  color: colors.primary,
                ),
              ],
              suffix: ' ms',
            ),
            _DistributionPanel(
              id: _DistributionInsightId.requestOutcome,
              icon: Icons.donut_large_rounded,
              title: '请求结果分布',
              centerValue: '$completed',
              items: [
                _DistributionItem(
                  '成功',
                  successes,
                  OpenHandStatusColors.success,
                ),
                _DistributionItem('失败', failures, OpenHandStatusColors.error),
                _DistributionItem('超时', timeouts, OpenHandStatusColors.warning),
              ],
            ),
            _DistributionPanel(
              id: _DistributionInsightId.httpStatus,
              icon: Icons.http_rounded,
              title: 'HTTP 状态分布',
              centerValue: '${status2xx + status3xx + status4xx + status5xx}',
              items: [
                _DistributionItem(
                  '2xx',
                  status2xx,
                  OpenHandStatusColors.success,
                ),
                _DistributionItem('3xx', status3xx, OpenHandStatusColors.info),
                _DistributionItem(
                  '4xx',
                  status4xx,
                  OpenHandStatusColors.warning,
                ),
                _DistributionItem('5xx', status5xx, OpenHandStatusColors.error),
              ],
            ),
            _DistributionPanel(
              id: _DistributionInsightId.nodeRequest,
              icon: Icons.account_tree_outlined,
              title: '节点请求分布',
              centerValue: '$requests',
              items: endpointItems,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _OpsPanelGrid(
          children: [
            _Section(
              title: '选路策略快照',
              icon: Icons.alt_route_rounded,
              child: Column(
                children: [
                  _OpsKeyValue(
                    label: '调度策略',
                    value: _proxyStrategyName(configuration.strategy),
                    onTap: () => _showDependencyEntityInsight(
                      context,
                      id: _DependencyInsightId.proxyRouting,
                      name: '请求出口',
                      configured: true,
                      connected:
                          controller.proxyRoute == AiExposureProxyRoute.pool,
                      message: serviceProxyRouteText(controller, text),
                    ),
                  ),
                  _OpsKeyValue(
                    label: '轮换频率',
                    value: '每 ${configuration.rotationEvery} 次请求',
                  ),
                  _OpsKeyValue(
                    label: '本地地址绕过',
                    value: configuration.bypassLocal ? '已启用' : '已停用',
                  ),
                  _OpsKeyValue(
                    label: '自动巡检',
                    value: configuration.inspectionEnabled
                        ? '${configuration.inspectionIntervalMinutes} 分钟一次'
                        : '未启用',
                  ),
                  _OpsKeyValue(
                    label: '巡检并发',
                    value: '${configuration.inspectionConcurrency}',
                  ),
                  _OpsKeyValue(
                    label: '持久化样本',
                    value: '${recentRequests.length} 条请求遥测',
                  ),
                ],
              ),
            ),
            _Section(
              title: '出口地域分布',
              icon: Icons.public_rounded,
              child: countryCounts.isEmpty
                  ? const Text('等待代理节点完成首次出口识别。')
                  : Column(
                      children:
                          (countryCounts.entries.toList()..sort(
                                (left, right) =>
                                    right.value.compareTo(left.value),
                              ))
                              .map(
                                (entry) => _DistributionBar(
                                  label: entry.key,
                                  value: entry.value,
                                  maxValue: countryCounts.values.fold<int>(
                                    1,
                                    (max, value) => value > max ? value : max,
                                  ),
                                  color: colors.tertiary,
                                  onTap: () => _showProxyRegionInsight(
                                    context,
                                    country: entry.key,
                                    endpoints: endpoints.where(
                                      (endpoint) =>
                                          endpoint.identity?.country ==
                                          entry.key,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                    ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Section(
          title: '代理端点健康明细',
          icon: Icons.dns_outlined,
          child: endpoints.isEmpty
              ? Text(
                  text(
                    zh: '代理池为空，当前请求使用 ${serviceProxyRouteText(controller, text)}。',
                    en: 'The proxy pool is empty. Requests currently use ${serviceProxyRouteText(controller, text)}.',
                  ),
                )
              : Column(
                  children: endpoints.take(20).map((endpoint) {
                    final sample = endpoint.latestSample;
                    final statistics = endpoint.statistics;
                    final color = !endpoint.enabled
                        ? colors.outline
                        : sample?.reachable == false
                        ? OpenHandStatusColors.error
                        : sample?.reachable == true
                        ? OpenHandStatusColors.success
                        : OpenHandStatusColors.warning;
                    final identity = endpoint.identity;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      onTap: () =>
                          _showProxyEndpointEntityInsight(context, endpoint),
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: color.withValues(alpha: 0.12),
                        child: Icon(Icons.lan_outlined, size: 18, color: color),
                      ),
                      title: Text(
                        endpoint.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${endpoint.maskedUrl} · ${identity?.exitIp.isNotEmpty == true ? identity!.exitIp : '出口待识别'} · ${identity?.location.isNotEmpty == true ? identity!.location : '地域待识别'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _StatusPill(
                            icon: sample?.reachable == true
                                ? Icons.check_rounded
                                : sample?.reachable == false
                                ? Icons.close_rounded
                                : Icons.pending_outlined,
                            label:
                                '${sample?.latencyMs ?? 0} ms · ${statistics.requests} 次',
                            color: color,
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right_rounded, size: 19),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }
}
