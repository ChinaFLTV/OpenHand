part of 'ai_exposure_monitoring_dialogs.dart';

class _OverviewPanel extends StatelessWidget {
  const _OverviewPanel({required this.controller});
  final ServicesController controller;

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    final history = controller.history;
    final results = controller.results;
    final proxy = controller.proxyStatus;
    // 单次遍历统计任务状态，避免多次 .where().length 的 O(n) 重复扫描。
    var completed = 0;
    var failed = 0;
    var timeout = 0;
    var cancelled = 0;
    var running = 0;
    final stageCounts = <String, int>{};
    for (final item in history) {
      final status = _taskStatusId(item);
      stageCounts.update(status, (count) => count + 1, ifAbsent: () => 1);
      switch (item.stage) {
        case 'completed':
          completed++;
        case 'cancelled':
          cancelled++;
        case 'failed':
          if (_isTimeoutTask(item)) {
            timeout++;
          } else {
            failed++;
          }
        default:
          if (_taskStatusId(item) == 'running') running++;
      }
    }
    // 单次遍历统计结果分类。
    var valid = 0;
    var highValue = 0;
    var suspicious = 0;
    var honeypot = 0;
    for (final item in results) {
      switch (item.category) {
        case AiExposureResultCategory.valid:
          valid++;
        case AiExposureResultCategory.highValue:
          highValue++;
        case AiExposureResultCategory.suspicious:
          suspicious++;
        case AiExposureResultCategory.honeypot:
          honeypot++;
      }
    }
    final durations = history
        .map(_taskMeasuredDurationMs)
        .whereType<int>()
        .map((duration) => duration.toDouble())
        .toList(growable: false);
    final historyTrend = history.reversed
        .where((item) => item.createdAtReported)
        .take(24)
        .toList(growable: false);
    final durationTrend = historyTrend
        .where((item) => _taskMeasuredDurationMs(item) != null)
        .toList(growable: false);
    final sourceStates = _sourceInsightStates(controller);
    final configuredSources = sourceStates
        .where((state) => state.configured)
        .length;
    final credentialSourceCount = AiExposureSource.values
        .where(_sourceRequiresCredential)
        .map(_sourceCredentialKey)
        .toSet()
        .length;
    final enabledRuleCount = controller.rules
        .where((rule) => rule.enabled)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Console(controller: controller),
        kOpenHandGap14,
        _MetricGrid(
          title: '状态总览',
          desktopColumns: 3,
          metrics: [
            _Metric(
              _MetricInsightId.overviewTaskTotal,
              Icons.work_history_outlined,
              '任务数量',
              '${history.length}',
              '完成 $completed · 运行中 $running · 失败 $failed · 超时 $timeout · 取消 $cancelled',
              color: Theme.of(context).colorScheme.primary,
            ),
            _Metric(
              null,
              Icons.fact_check_outlined,
              '任务结果',
              '${results.length}',
              '有效 $valid · 最近持久化结果',
              color: OpenHandStatusColors.info,
              onTap: () =>
                  showAiExposureScanWorkspaceDialog(context, showResults: true),
            ),
            _Metric(
              null,
              Icons.timer_outlined,
              '平均任务耗时',
              _duration(
                durations.isEmpty
                    ? 0
                    : (durations.reduce((a, b) => a + b) /
                              durations.length /
                              1000)
                          .round(),
              ),
              '${durations.length} 个实测完成任务',
              color: Theme.of(context).colorScheme.tertiary,
            ),
            _Metric(
              _MetricInsightId.overviewConfiguredSources,
              Icons.travel_explore_rounded,
              '已配置源',
              '$configuredSources/${sourceStates.length}',
              '$credentialSourceCount 个独立凭证组',
              color: OpenHandStatusColors.success,
            ),
            _Metric(
              _MetricInsightId.overviewEnabledRules,
              Icons.rule_rounded,
              '启用规则',
              '$enabledRuleCount',
              '总计 ${controller.rules.length}',
              color: _kAiExposureColorTeal,
            ),
            _Metric(
              _MetricInsightId.overviewProxyAverageLatency,
              Icons.speed_rounded,
              '代理平均响应',
              '${proxy?.averageResponseTimeMs ?? 0} ms',
              controller.proxyRoute == AiExposureProxyRoute.pool
                  ? '执行中 ${proxy?.inFlight ?? 0}'
                  : serviceProxyRouteText(controller, text),
              color: Theme.of(context).colorScheme.secondary,
            ),
          ],
        ),
        kOpenHandGap14,
        _OpsPanelGrid(
          children: [
            _TrendPanel(
              id: _TrendInsightId.taskThroughput,
              interpolation: OpenHandChartInterpolation.linear,
              icon: Icons.show_chart_rounded,
              title: '任务处理趋势',
              subtitle: '最近 ${historyTrend.length} 个任务',
              sampleTimes: historyTrend
                  .map((item) => item.createdAt)
                  .toList(growable: false),
              sampleLabels: historyTrend
                  .map(
                    (item) => _reportedShortDateTime(
                      item.createdAt,
                      item.createdAtReported,
                    ),
                  )
                  .toList(growable: false),
              series: <OpenHandChartSeries>[
                OpenHandChartSeries(
                  label: '处理',
                  values: historyTrend
                      .map((item) => item.progress.processed.toDouble())
                      .toList(growable: false),
                  color: Theme.of(context).colorScheme.primary,
                ),
                OpenHandChartSeries(
                  label: '有效',
                  values: historyTrend
                      .map((item) => item.progress.valid.toDouble())
                      .toList(growable: false),
                  color: OpenHandStatusColors.success,
                ),
              ],
              suffix: ' 项',
            ),
            _TrendPanel(
              id: _TrendInsightId.taskDuration,
              interpolation: OpenHandChartInterpolation.smooth,
              icon: Icons.timelapse_rounded,
              title: '任务耗时趋势',
              subtitle: '最近 ${durationTrend.length} 个已结束任务',
              sampleTimes: durationTrend
                  .map((item) => item.createdAt)
                  .toList(growable: false),
              sampleLabels: durationTrend
                  .map(
                    (item) => _reportedShortDateTime(
                      item.createdAt,
                      item.createdAtReported,
                    ),
                  )
                  .toList(growable: false),
              series: <OpenHandChartSeries>[
                OpenHandChartSeries(
                  label: '耗时',
                  values: durationTrend
                      .map((item) => _taskMeasuredDurationMs(item)!.toDouble())
                      .toList(growable: false),
                  color: Theme.of(context).colorScheme.tertiary,
                ),
              ],
              suffix: ' ms',
            ),
            _DistributionPanel(
              id: _DistributionInsightId.resultCategory,
              icon: Icons.donut_large_rounded,
              title: '结果分类分布',
              centerValue: '${results.length}',
              items: [
                _DistributionItem('有效', valid, OpenHandStatusColors.success),
                _DistributionItem('高价值', highValue, _kAiExposureColorHighValue),
                _DistributionItem(
                  '可疑',
                  suspicious,
                  OpenHandStatusColors.warning,
                ),
                _DistributionItem('蜜罐', honeypot, OpenHandStatusColors.error),
              ],
            ),
            _DistributionPanel(
              id: _DistributionInsightId.taskStage,
              icon: Icons.account_tree_outlined,
              title: '任务状态分布',
              centerValue: '${history.length}',
              items: [
                _DistributionItem(
                  '完成',
                  stageCounts['completed'] ?? 0,
                  OpenHandStatusColors.success,
                ),
                _DistributionItem(
                  '失败',
                  stageCounts['failed'] ?? 0,
                  OpenHandStatusColors.error,
                ),
                _DistributionItem(
                  '超时',
                  stageCounts['timeout'] ?? 0,
                  OpenHandStatusColors.warning,
                ),
                _DistributionItem(
                  '取消',
                  stageCounts['cancelled'] ?? 0,
                  OpenHandStatusColors.warning,
                ),
                _DistributionItem(
                  '执行中',
                  stageCounts['running'] ?? 0,
                  OpenHandStatusColors.info,
                ),
              ],
            ),
          ],
        ),
        kOpenHandGap14,
        _RecentActivityPanel(
          entries: controller.logs.reversed.take(8).toList(growable: false),
        ),
      ],
    );
  }
}

class _Console extends StatelessWidget {
  const _Console({required this.controller});
  final ServicesController controller;

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    final progress = controller.progress;
    final dependencies = controller.dependencyStatus;
    final proxy = controller.proxyStatus;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kAiExposureDarkSurface,
        borderRadius: kOpenHandBorderRadius8,
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(
          color: _kAiExposureDarkOnSurface,
          fontFamily: 'monospace',
          fontSize: 13,
          height: 1.55,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _consoleLine(
              'service',
              controller.isRunning ? 'READY' : 'STOPPED',
              controller.isRunning,
            ),
            _consoleLine(
              'engine',
              'ai_jungler ${controller.health?.version ?? '--'} · uptime=${_duration(controller.health?.uptimeSeconds ?? 0)}',
              controller.isRunning,
            ),
            _consoleLine(
              'job',
              progress == null
                  ? 'idle'
                  : '${progress.stage} ${progress.processed}/${progress.total}',
              progress?.isRunning == true,
            ),
            _consoleLine(
              'sources',
              '${controller.sourceStatus.values.where((item) => item).length}/${controller.discoverySourceCount} configured',
              controller.sourceStatus.values.any((item) => item),
            ),
            _consoleLine(
              'proxy',
              controller.proxyRoute == AiExposureProxyRoute.pool &&
                      proxy != null
                  ? '${proxy.endpoints.length} endpoints · total=${proxy.totalSelections} ok=${proxy.totalSuccesses} failed=${proxy.totalFailures} timeout=${proxy.totalTimeouts} avg=${proxy.averageResponseTimeMs}ms'
                  : serviceProxyRouteText(controller, text),
              true,
            ),
            _consoleLine(
              'workload',
              'jobs=${controller.history.length} results=${controller.results.length} logs=${controller.logs.length}',
              true,
            ),
            _consoleLine(
              'storage',
              'SQLite · PostgreSQL=${dependencies?.postgresql.connected == true ? 'ready' : 'off'} · Redis=${dependencies?.redis.connected == true ? 'ready' : 'off'}',
              true,
            ),
            _consoleLine(
              'database',
              controller.health?.databasePath ?? '--',
              controller.health?.databasePath.isNotEmpty == true,
            ),
            _consoleLine(
              'extractor',
              controller.aiExtractorStatus?.configured == true
                  ? controller.aiExtractorStatus?.model ?? 'configured'
                  : 'deterministic rules',
              true,
            ),
            _consoleLine(
              'policy',
              'rules=${controller.rules.where((item) => item.enabled).length}/${controller.rules.length} concurrency=${controller.defaultConcurrency}',
              controller.rules.any((item) => item.enabled),
            ),
          ],
        ),
      ),
    );
  }

  Widget _consoleLine(String name, String value, bool healthy) {
    return OpenHandLiveConsoleLine(
      marker: kOpenHandLiveConsoleArrowMarker,
      prompt: name,
      command: value,
      markerColor: _kAiExposureConsoleSuccess,
      promptColor: _kAiExposureDarkJobId,
      commandColor: healthy
          ? _kAiExposureDarkOnSurface
          : _kAiExposureConsoleWarning,
    );
  }
}
