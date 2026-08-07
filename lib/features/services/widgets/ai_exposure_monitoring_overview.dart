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
    final completed = history.where((item) => item.stage == 'completed').length;
    final failed = history.where((item) => item.stage == 'failed').length;
    final cancelled = history.where((item) => item.stage == 'cancelled').length;
    final processed = history.fold<int>(
      0,
      (sum, item) => sum + item.progress.processed,
    );
    final discovered = history.fold<int>(
      0,
      (sum, item) => sum + item.progress.discovered,
    );
    final valid = results
        .where((item) => item.category == AiExposureResultCategory.valid)
        .length;
    final highValue = results
        .where((item) => item.category == AiExposureResultCategory.highValue)
        .length;
    final warnings = controller.logs
        .where((item) => item.level == 'warning')
        .length;
    final errors = controller.logs
        .where((item) => item.level == 'error')
        .length;
    final durations = history
        .map(_taskMeasuredDurationMs)
        .whereType<int>()
        .map((duration) => duration.toDouble())
        .toList(growable: false);
    final averageDuration = durations.isEmpty
        ? 0
        : (durations.reduce((left, right) => left + right) / durations.length)
              .round();
    final historyTrend = history.reversed.take(24).toList(growable: false);
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
    final stageCounts = <String, int>{};
    for (final item in history) {
      stageCounts.update(item.stage, (count) => count + 1, ifAbsent: () => 1);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Console(controller: controller),
        const SizedBox(height: 14),
        _MetricGrid(
          title: '状态总览',
          metrics: [
            _Metric(
              _MetricInsightId.overviewTaskTotal,
              Icons.work_history_outlined,
              '当前任务窗口',
              '${history.length}',
              '完成 $completed · 失败 $failed',
              color: Theme.of(context).colorScheme.primary,
            ),
            _Metric(
              _MetricInsightId.overviewResultTotal,
              Icons.fact_check_outlined,
              '当前结果窗口',
              '${results.length}',
              '有效 $valid',
              color: OpenHandStatusColors.info,
            ),
            _Metric(
              _MetricInsightId.overviewHighValue,
              Icons.workspace_premium_outlined,
              '高价值',
              '$highValue',
              '优先处置',
              color: const Color(0xffa855f7),
            ),
            _Metric(
              _MetricInsightId.overviewProcessed,
              Icons.radar_rounded,
              '窗口累计处理',
              '$processed',
              '发现 $discovered',
              color: const Color(0xff0891b2),
            ),
            _Metric(
              _MetricInsightId.overviewAverageDuration,
              Icons.timer_outlined,
              '平均任务耗时',
              _duration((averageDuration / 1000).round()),
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
              '${controller.rules.where((item) => item.enabled).length}',
              '总计 ${controller.rules.length}',
              color: const Color(0xff0f766e),
            ),
            _Metric(
              _MetricInsightId.overviewProxyRouting,
              Icons.lan_outlined,
              '代理选路',
              '${proxy?.totalSelections ?? 0}',
              controller.proxyRoute == AiExposureProxyRoute.pool
                  ? '成功 ${proxy?.totalSuccesses ?? 0} · 超时 ${proxy?.totalTimeouts ?? 0}'
                  : serviceProxyRouteText(controller, text),
              color: OpenHandStatusColors.info,
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
            _Metric(
              _MetricInsightId.overviewWarningLogs,
              Icons.warning_amber_rounded,
              '警告日志',
              '$warnings',
              '保留 ${controller.logs.length}',
              color: OpenHandStatusColors.warning,
            ),
            _Metric(
              _MetricInsightId.overviewErrorLogs,
              Icons.error_outline_rounded,
              '错误日志',
              '$errors',
              errors == 0 ? '状态正常' : '需要检查',
              color: OpenHandStatusColors.error,
            ),
            _Metric(
              _MetricInsightId.overviewCancelledTasks,
              Icons.cancel_outlined,
              '已取消任务',
              '$cancelled',
              history.isEmpty
                  ? '--'
                  : '${((completed * 100) / history.length).toStringAsFixed(1)}% 完成率',
              color: Theme.of(context).colorScheme.outline,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _OpsPanelGrid(
          children: [
            _TrendPanel(
              id: _TrendInsightId.taskThroughput,
              interpolation: OpenHandChartInterpolation.linear,
              icon: Icons.show_chart_rounded,
              title: '任务处理趋势',
              subtitle: '最近 ${historyTrend.length} 个任务',
              sampleLabels: historyTrend
                  .map((item) => _shortDateTime(item.createdAt))
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
              sampleLabels: durationTrend
                  .map((item) => _shortDateTime(item.createdAt))
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
                _DistributionItem('高价值', highValue, const Color(0xffa855f7)),
                _DistributionItem(
                  '可疑',
                  results
                      .where(
                        (item) =>
                            item.category ==
                            AiExposureResultCategory.suspicious,
                      )
                      .length,
                  OpenHandStatusColors.warning,
                ),
                _DistributionItem(
                  '蜜罐',
                  results
                      .where(
                        (item) =>
                            item.category == AiExposureResultCategory.honeypot,
                      )
                      .length,
                  OpenHandStatusColors.error,
                ),
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
                  '取消',
                  stageCounts['cancelled'] ?? 0,
                  OpenHandStatusColors.warning,
                ),
                _DistributionItem(
                  '执行中',
                  history.length - completed - failed - cancelled,
                  OpenHandStatusColors.info,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
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
        color: const Color(0xff0b0e12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(
          color: Color(0xffd5dae3),
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

  Widget _consoleLine(String name, String value, bool healthy) => Text.rich(
    TextSpan(
      children: [
        const TextSpan(
          text: '→ ',
          style: TextStyle(color: Color(0xff28d17c)),
        ),
        TextSpan(
          text: '$name ',
          style: const TextStyle(color: Color(0xff6fa8ed)),
        ),
        TextSpan(
          text: value,
          style: TextStyle(
            color: healthy ? const Color(0xffd5dae3) : const Color(0xffffb14e),
          ),
        ),
      ],
    ),
  );
}
