part of 'ai_exposure_monitoring_dialogs.dart';

class _SourcesPanel extends StatelessWidget {
  const _SourcesPanel({required this.controller});
  final ServicesController controller;

  @override
  Widget build(BuildContext context) {
    final resultCounts = <AiExposureSource, int>{};
    final jobCounts = <AiExposureSource, int>{};
    for (final result in controller.results) {
      resultCounts.update(
        result.source,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    for (final job in controller.history) {
      for (final source in job.sources.toSet()) {
        jobCounts.update(source, (value) => value + 1, ifAbsent: () => 1);
      }
    }
    final configured = controller.sourceStatus.values
        .where((item) => item)
        .length;
    final available = controller.quotas.where((item) => item.available).length;
    final remaining = controller.quotas.fold<int>(
      0,
      (sum, item) => sum + (item.remaining ?? 0),
    );
    final sourceItems = AiExposureSource.values
        .where((item) => item != AiExposureSource.githubArtifact)
        .map(
          (source) => _DistributionItem(
            _sourceName(source),
            resultCounts[source] ?? 0,
            _sourceColor(source, Theme.of(context).colorScheme),
          ),
        )
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MetricGrid(
          title: '数据源',
          metrics: [
            _Metric(
              _MetricInsightId.sourceReady,
              Icons.cloud_done_outlined,
              '已就绪来源',
              '$configured/${controller.discoverySourceCount}',
              '论坛来源无需 API 凭证',
              color: OpenHandStatusColors.success,
            ),
            _Metric(
              _MetricInsightId.sourceQuotaAvailable,
              Icons.cloud_done_outlined,
              '配额可用源',
              '$available',
              '已完成实时配额探测',
              color: OpenHandStatusColors.info,
            ),
            _Metric(
              _MetricInsightId.sourceQuotaRemaining,
              Icons.data_usage_rounded,
              '剩余配额',
              '$remaining',
              '仅汇总可计数来源',
              color: Theme.of(context).colorScheme.primary,
            ),
            _Metric(
              _MetricInsightId.sourceDiscoveryEnabled,
              Icons.travel_explore_rounded,
              '启用发现源',
              '${controller.enabledSources.length}',
              '共 ${AiExposureSource.values.length} 类',
              color: const Color(0xff0891b2),
            ),
            _Metric(
              _MetricInsightId.sourceTaskCalls,
              Icons.work_history_outlined,
              '来源调用任务',
              '${jobCounts.values.fold<int>(0, (sum, item) => sum + item)}',
              '一个任务可包含多个来源',
              color: Theme.of(context).colorScheme.tertiary,
            ),
            _Metric(
              _MetricInsightId.sourceResults,
              Icons.fact_check_outlined,
              '来源产出结果',
              '${controller.results.length}',
              '${resultCounts.length} 个来源有产出',
              color: const Color(0xff0f766e),
            ),
            _Metric(
              _MetricInsightId.sourceQuotaAnomalies,
              Icons.warning_amber_rounded,
              '配额异常',
              '${controller.quotas.where((item) => item.configured && !item.available).length}',
              '需检查凭证或网络',
              color: OpenHandStatusColors.warning,
            ),
            _Metric(
              _MetricInsightId.sourcePendingConfiguration,
              Icons.key_off_outlined,
              '待配置来源',
              '${controller.discoverySourceCount - configured}',
              '可在服务设置中补齐',
              color: Theme.of(context).colorScheme.outline,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _OpsPanelGrid(
          children: [
            _DistributionPanel(
              id: _DistributionInsightId.resultSource,
              icon: Icons.pie_chart_outline_rounded,
              title: '结果来源分布',
              centerValue: '${controller.results.length}',
              items: sourceItems,
            ),
            _DistributionPanel(
              id: _DistributionInsightId.taskSource,
              icon: Icons.hub_outlined,
              title: '任务来源覆盖',
              centerValue:
                  '${jobCounts.values.fold<int>(0, (sum, item) => sum + item)}',
              items: AiExposureSource.values
                  .where((item) => item != AiExposureSource.githubArtifact)
                  .map(
                    (source) => _DistributionItem(
                      _sourceName(source),
                      jobCounts[source] ?? 0,
                      _sourceColor(source, Theme.of(context).colorScheme),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Section(
          title: '资产发现数据源',
          icon: Icons.travel_explore_rounded,
          child: Column(
            children: AiExposureSource.values
                .map((source) {
                  final requiresCredential = _sourceRequiresCredential(source);
                  final isConfigured = _sourceAccessConfigured(
                    controller,
                    source,
                  );
                  final quota = controller.quotas
                      .where((item) => item.source == source)
                      .firstOrNull;
                  final isAvailable =
                      isConfigured && (quota?.available ?? !requiresCredential);
                  final quotaText = quota?.limit == null
                      ? quota?.message
                      : '${quota!.remaining ?? 0}/${quota.limit} · ${quota.message}';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () => _showSourceEntityInsight(context, source),
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundColor: _sourceColor(
                        source,
                        Theme.of(context).colorScheme,
                      ).withValues(alpha: 0.12),
                      child: Icon(
                        _sourceIcon(source),
                        size: 18,
                        color: _sourceColor(
                          source,
                          Theme.of(context).colorScheme,
                        ),
                      ),
                    ),
                    title: Text(_sourceName(source)),
                    subtitle: Text(
                      quotaText ??
                          (!isConfigured
                              ? '尚未配置访问凭证。'
                              : requiresCredential
                              ? '凭证已配置，等待配额检查。'
                              : '无需访问凭证。'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _StatusPill(
                          icon: isAvailable
                              ? Icons.check_rounded
                              : isConfigured
                              ? Icons.warning_amber_rounded
                              : Icons.key_off_outlined,
                          label: isAvailable
                              ? '可用'
                              : isConfigured
                              ? '待检查'
                              : '待配置',
                          color: isAvailable
                              ? OpenHandStatusColors.success
                              : isConfigured
                              ? OpenHandStatusColors.warning
                              : Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right_rounded, size: 19),
                      ],
                    ),
                  );
                })
                .toList(growable: false),
          ),
        ),
      ],
    );
  }
}
