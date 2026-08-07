part of 'ai_exposure_monitoring_dialogs.dart';

class _PipelinePanel extends StatelessWidget {
  const _PipelinePanel({required this.controller});
  final ServicesController controller;

  @override
  Widget build(BuildContext context) {
    final progress = controller.progress;
    const stages = <String>[
      'queued',
      'discovering',
      'normalizing',
      'fingerprinting',
      'extracting',
      'validating',
      'persisting',
      'completed',
    ];
    final activeIndex = progress == null ? -1 : stages.indexOf(progress.stage);
    final history = controller.history;
    final totalProcessed = history.fold<int>(
      0,
      (sum, item) => sum + item.progress.processed,
    );
    final totalCandidates = history.fold<int>(
      0,
      (sum, item) => sum + item.progress.candidates,
    );
    final totalValid = history.fold<int>(
      0,
      (sum, item) => sum + item.progress.valid,
    );
    final totalHighValue = history.fold<int>(
      0,
      (sum, item) => sum + item.progress.highValue,
    );
    final trend = history.reversed
        .where((item) => item.createdAtReported)
        .take(24)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MetricGrid(
          title: '任务管线',
          metrics: [
            _Metric(
              _MetricInsightId.pipelineCurrentState,
              Icons.play_circle_outline_rounded,
              '当前状态',
              progress?.isRunning == true ? '执行中' : '空闲',
              progress == null ? '等待任务' : _stageName(progress.stage),
              color: progress?.isRunning == true
                  ? OpenHandStatusColors.success
                  : Theme.of(context).colorScheme.outline,
            ),
            _Metric(
              _MetricInsightId.pipelineProcessed,
              Icons.checklist_rounded,
              '累计处理',
              '$totalProcessed',
              '${history.length} 个任务',
              color: Theme.of(context).colorScheme.primary,
            ),
            _Metric(
              _MetricInsightId.pipelineCandidates,
              Icons.filter_alt_outlined,
              '候选目标',
              '$totalCandidates',
              totalProcessed == 0
                  ? '--'
                  : '${(totalCandidates * 100 / totalProcessed).toStringAsFixed(1)}% 候选率',
              color: OpenHandStatusColors.info,
            ),
            _Metric(
              _MetricInsightId.pipelineValid,
              Icons.verified_outlined,
              '有效结果',
              '$totalValid',
              totalCandidates == 0
                  ? '--'
                  : '${(totalValid * 100 / totalCandidates).toStringAsFixed(1)}% 有效率',
              color: OpenHandStatusColors.success,
            ),
            _Metric(
              _MetricInsightId.pipelineHighValue,
              Icons.workspace_premium_outlined,
              '高价值结果',
              '$totalHighValue',
              totalValid == 0
                  ? '--'
                  : '${(totalHighValue * 100 / totalValid).toStringAsFixed(1)}% 占有效结果',
              color: const Color(0xffa855f7),
            ),
            _Metric(
              _MetricInsightId.pipelineConcurrency,
              Icons.speed_rounded,
              '任务并发',
              '${controller.defaultConcurrency}',
              '配置上限 128',
              color: Theme.of(context).colorScheme.tertiary,
            ),
            _Metric(
              _MetricInsightId.pipelineFullScan,
              Icons.layers_outlined,
              '全量扫描',
              '${history.where((item) => item.mode == AiExposureScanMode.full).length}',
              '其余为增量扫描',
              color: const Color(0xff0891b2),
            ),
            _Metric(
              _MetricInsightId.pipelineResumable,
              Icons.restart_alt_rounded,
              '可恢复任务',
              '${history.where((item) => item.isResumable).length}',
              '失败或中断任务',
              color: OpenHandStatusColors.warning,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _DependencyDataAccessPanel(controller: controller),
        const SizedBox(height: 12),
        _OpsPanelGrid(
          children: [
            _TrendPanel(
              id: _TrendInsightId.pipelineFunnel,
              interpolation: OpenHandChartInterpolation.linear,
              icon: Icons.multiline_chart_rounded,
              title: '处理漏斗趋势',
              subtitle: '处理 / 候选 / 有效',
              sampleLabels: trend
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
                  values: trend
                      .map((item) => item.progress.processed.toDouble())
                      .toList(growable: false),
                  color: Theme.of(context).colorScheme.primary,
                ),
                OpenHandChartSeries(
                  label: '候选',
                  values: trend
                      .map((item) => item.progress.candidates.toDouble())
                      .toList(growable: false),
                  color: OpenHandStatusColors.info,
                ),
                OpenHandChartSeries(
                  label: '有效',
                  values: trend
                      .map((item) => item.progress.valid.toDouble())
                      .toList(growable: false),
                  color: OpenHandStatusColors.success,
                ),
              ],
              suffix: ' 项',
            ),
            _DistributionPanel(
              id: _DistributionInsightId.scanMode,
              icon: Icons.schema_outlined,
              title: '扫描模式分布',
              centerValue: '${history.length}',
              items: [
                _DistributionItem(
                  '全量扫描',
                  history
                      .where((item) => item.mode == AiExposureScanMode.full)
                      .length,
                  Theme.of(context).colorScheme.primary,
                ),
                _DistributionItem(
                  '增量扫描',
                  history
                      .where(
                        (item) => item.mode == AiExposureScanMode.incremental,
                      )
                      .length,
                  OpenHandStatusColors.info,
                ),
                _DistributionItem(
                  '主动验证',
                  history
                      .where((item) => item.authorizedScope.isNotEmpty)
                      .length,
                  OpenHandStatusColors.warning,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Section(
          title: '当前任务',
          icon: Icons.radar_rounded,
          child: progress == null
              ? const Text('当前没有扫描任务。')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(progress.message),
                    const SizedBox(height: 10),
                    ServiceAnimatedProgressBar(
                      value: progress.total <= 0 ? null : progress.fraction,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '发现 ${progress.discovered} · 候选 ${progress.candidates} · 有效 ${progress.valid} · 高价值 ${progress.highValue} · 已处理 ${progress.processed}/${progress.total}',
                    ),
                    if (progress.isRunning) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: OpenHandDialogActionButton.destructive(
                          icon: Icons.stop_rounded,
                          onPressed: controller.stopScan,
                          label: '停止当前扫描',
                        ),
                      ),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 12),
        _Section(
          title: '处理阶段',
          icon: Icons.account_tree_outlined,
          child: Column(
            children: [
              for (var index = 0; index < stages.length; index++)
                _StageRow(
                  stage: stages[index],
                  taskId: progress?.jobId,
                  completed:
                      activeIndex >= 0 && index < activeIndex ||
                      progress?.stage == 'completed',
                  active:
                      index == activeIndex && progress?.stage != 'completed',
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Section(
          title: '最近任务',
          icon: Icons.history_rounded,
          child: Column(
            children: controller.history
                .take(12)
                .map((item) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () => _showTaskEntityInsight(context, item),
                    leading: Icon(_stageIcon(item.stage)),
                    title: Text(
                      item.name.trim().isEmpty ? item.id : item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${item.sources.map(_sourceName).join(' / ')} · ${item.progress.processed}/${item.progress.total}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_stageName(item.stage)),
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
