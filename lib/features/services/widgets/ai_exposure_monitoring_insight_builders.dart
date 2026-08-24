part of 'ai_exposure_monitoring_dialogs.dart';

Widget _metricInsightPage(List<Widget> sections) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: sections.indexed
      .expand((entry) => [if (entry.$1 > 0) kOpenHandGap14, entry.$2])
      .toList(growable: false),
);

Widget _buildDistinctMetricInsight(
  BuildContext context, {
  required _MetricInsightId id,
  required ServicesController controller,
}) => switch (id) {
  _MetricInsightId.overviewTaskTotal ||
  _MetricInsightId.overviewResultTotal ||
  _MetricInsightId.overviewHighValue ||
  _MetricInsightId.overviewProcessed ||
  _MetricInsightId.overviewAverageDuration ||
  _MetricInsightId.overviewConfiguredSources ||
  _MetricInsightId.overviewEnabledRules ||
  _MetricInsightId.overviewProxyRouting ||
  _MetricInsightId.overviewProxyAverageLatency ||
  _MetricInsightId.overviewWarningLogs ||
  _MetricInsightId.overviewErrorLogs ||
  _MetricInsightId.overviewCancelledTasks => _buildOverviewMetricInsight(
    context,
    id,
    controller,
  ),
  _MetricInsightId.pipelineCurrentState ||
  _MetricInsightId.pipelineProcessed ||
  _MetricInsightId.pipelineCandidates ||
  _MetricInsightId.pipelineValid ||
  _MetricInsightId.pipelineHighValue ||
  _MetricInsightId.pipelineConcurrency ||
  _MetricInsightId.pipelineFullScan ||
  _MetricInsightId.pipelineResumable => _buildPipelineMetricInsight(
    context,
    id,
    controller,
  ),
  _MetricInsightId.storageSqlite || _MetricInsightId.storageLastWrite =>
    _buildStorageMetricInsight(context, id, controller),
};

_InsightRecordPanel _metricTaskPanel(
  Iterable<AiExposureHistoryEntry> entries, {
  required String title,
  required String emptyLabel,
  _TaskRecordLens lens = _TaskRecordLens.overview,
}) => _InsightRecordPanel(
  icon: Icons.work_history_outlined,
  title: title,
  records: entries
      .map((entry) => _taskInsightRecord(entry, lens))
      .toList(growable: false),
  emptyLabel: emptyLabel,
);

_InsightRecordPanel _metricResultPanel(
  Iterable<AiExposureResult> entries, {
  required String title,
  required String emptyLabel,
  _ResultRecordLens lens = _ResultRecordLens.overview,
}) => _InsightRecordPanel(
  icon: Icons.fact_check_outlined,
  title: title,
  records: entries
      .map((entry) => _resultInsightRecord(entry, lens))
      .toList(growable: false),
  emptyLabel: emptyLabel,
);

List<AiExposureHistoryEntry> _chronologicalTasks(
  ServicesController controller, {
  int limit = 24,
}) => controller.history
    .where((task) => task.createdAtReported)
    .take(limit)
    .toList()
    .reversed
    .toList(growable: false);

Widget _buildOverviewMetricInsight(
  BuildContext context,
  _MetricInsightId id,
  ServicesController controller,
) {
  final colors = Theme.of(context).colorScheme;
  final history = controller.history;
  final chronological = _chronologicalTasks(controller);
  final results = controller.results;
  final logs = controller.logs;

  switch (id) {
    case _MetricInsightId.overviewTaskTotal:
      return const _TaskTelemetryInsight();
    case _MetricInsightId.overviewResultTotal:
      int category(AiExposureResultCategory value) =>
          results.where((entry) => entry.category == value).length;
      final sourceCounts = <AiExposureSource, int>{};
      for (final result in results) {
        sourceCounts.update(
          result.source,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
      return _metricInsightPage([
        _metricResultPanel(results, title: '结果证据队列', emptyLabel: '暂无扫描结果。'),
        _InsightDonutSection(
          title: '结果质量构成',
          icon: Icons.fact_check_outlined,
          items: [
            _DistributionItem(
              '有效',
              category(AiExposureResultCategory.valid),
              OpenHandStatusColors.success,
              key: AiExposureResultCategory.valid,
            ),
            _DistributionItem(
              '高价值',
              category(AiExposureResultCategory.highValue),
              colors.secondary,
              key: AiExposureResultCategory.highValue,
            ),
            _DistributionItem(
              '可疑',
              category(AiExposureResultCategory.suspicious),
              OpenHandStatusColors.warning,
              key: AiExposureResultCategory.suspicious,
            ),
            _DistributionItem(
              '蜜罐',
              category(AiExposureResultCategory.honeypot),
              OpenHandStatusColors.error,
              key: AiExposureResultCategory.honeypot,
            ),
          ],
          detailBuilder: (context, item) {
            final selectedCategory = item.key! as AiExposureResultCategory;
            return _metricResultPanel(
              results.where((result) => result.category == selectedCategory),
              title: '${item.label}结果证据',
              emptyLabel: '暂无${item.label}结果。',
              lens: _ResultRecordLens.risk,
            );
          },
        ),
        _InsightRankingSection(
          title: '来源产出排名',
          icon: Icons.travel_explore_rounded,
          items: sourceCounts.entries
              .map(
                (entry) => _InsightRankItem(
                  label: aiExposureSourceDisplayName(entry.key),
                  value: entry.value.toDouble(),
                  valueLabel: '${entry.value} 条',
                  color: _sourceColor(entry.key, colors),
                  target: _SourceInsightTarget(entry.key),
                ),
              )
              .toList(growable: false),
          emptyLabel: '暂无来源产出。',
        ),
      ]);
    case _MetricInsightId.overviewHighValue:
      final highValue = results
          .where(
            (entry) => entry.category == AiExposureResultCategory.highValue,
          )
          .toList(growable: false);
      return _metricInsightPage([
        _InsightMatrixSection(
          title: '高价值处置队列',
          icon: Icons.security_rounded,
          rows: highValue
              .map(
                (result) => _InsightMatrixRow(
                  icon: Icons.workspace_premium_outlined,
                  title: result.product.trim().isEmpty
                      ? result.host
                      : '${result.product} · ${result.host}',
                  subtitle: result.url,
                  color: _kAiExposureColorHighValue,
                  target: _ResultInsightTarget(result),
                  cells: [
                    _InsightMatrixCell(
                      label: aiExposureSourceDisplayName(result.source),
                      color: _sourceColor(result.source, colors),
                    ),
                    _InsightMatrixCell(
                      label: '证据 ${result.evidence.length}',
                      color: colors.primary,
                    ),
                    _InsightMatrixCell(
                      label: '模型 ${result.modelCount}',
                      color: colors.tertiary,
                    ),
                    if (result.duplicateKeyHosts > 0)
                      _InsightMatrixCell(
                        label: '同凭证 ${result.duplicateKeyHosts}',
                        color: OpenHandStatusColors.warning,
                      ),
                  ],
                ),
              )
              .toList(growable: false),
          emptyLabel: '暂无高价值结果。',
        ),
        _InsightTrendSection(
          title: '逐任务高价值产出',
          icon: Icons.workspace_premium_outlined,
          series: [
            OpenHandChartSeries(
              label: '高价值',
              values: chronological
                  .map((entry) => entry.progress.highValue.toDouble())
                  .toList(growable: false),
              color: _kAiExposureColorHighValue,
            ),
            OpenHandChartSeries(
              label: '有效',
              values: chronological
                  .map((entry) => entry.progress.valid.toDouble())
                  .toList(growable: false),
              color: OpenHandStatusColors.success,
            ),
          ],
          sampleLabels: chronological
              .map(
                (entry) => _reportedShortDateTime(
                  entry.createdAt,
                  entry.createdAtReported,
                ),
              )
              .toList(growable: false),
          suffix: ' 条',
          emptyLabel: '暂无任务产出样本',
          targets: chronological
              .map<_InsightTarget?>((task) => _TaskInsightTarget(task))
              .toList(growable: false),
        ),
      ]);
    case _MetricInsightId.overviewProcessed:
      final ranked = [...history]
        ..sort(
          (left, right) =>
              right.progress.processed.compareTo(left.progress.processed),
        );
      return _metricInsightPage([
        _metricTaskPanel(
          ranked,
          title: '任务吞吐账本',
          emptyLabel: '暂无任务处理样本。',
          lens: _TaskRecordLens.throughput,
        ),
        _InsightTrendSection(
          title: '任务处理吞吐曲线',
          icon: Icons.radar_rounded,
          series: [
            OpenHandChartSeries(
              label: '处理',
              values: chronological
                  .map((entry) => entry.progress.processed.toDouble())
                  .toList(growable: false),
              color: colors.primary,
            ),
            OpenHandChartSeries(
              label: '发现',
              values: chronological
                  .map((entry) => entry.progress.discovered.toDouble())
                  .toList(growable: false),
              color: colors.tertiary,
            ),
          ],
          sampleLabels: chronological
              .map(
                (entry) => _reportedShortDateTime(
                  entry.createdAt,
                  entry.createdAtReported,
                ),
              )
              .toList(growable: false),
          suffix: ' 项',
          emptyLabel: '暂无处理吞吐样本',
          targets: chronological
              .map<_InsightTarget?>((task) => _TaskInsightTarget(task))
              .toList(growable: false),
        ),
        _InsightRankingSection(
          title: '任务处理量排名',
          icon: Icons.leaderboard_outlined,
          items: ranked
              .map(
                (entry) => _InsightRankItem(
                  label: entry.name.trim().isEmpty
                      ? entry.id
                      : entry.name.trim(),
                  value: entry.progress.processed.toDouble(),
                  valueLabel: '${entry.progress.processed}',
                  helper:
                      '发现 ${entry.progress.discovered} · 总量 ${entry.progress.total}',
                  color: colors.primary,
                  target: _TaskInsightTarget(entry),
                ),
              )
              .toList(growable: false),
          emptyLabel: '暂无任务处理样本。',
        ),
      ]);
    case _MetricInsightId.overviewAverageDuration:
      final finished = history
          .where((entry) => _taskMeasuredDurationMs(entry) != null)
          .toList(growable: false);
      final durations =
          finished.map((entry) => _taskMeasuredDurationMs(entry)!).toList()
            ..sort();
      final average = durations.isEmpty
          ? 0
          : (durations.fold<int>(0, (sum, value) => sum + value) /
                    durations.length)
                .round();
      return _metricInsightPage([
        _InsightKpiBand(
          title: '任务耗时分位',
          icon: Icons.timer_outlined,
          items: [
            _InsightKpi(
              icon: Icons.av_timer_rounded,
              label: '平均',
              value: '$average ms',
              helper: '${durations.length} 个已结束任务',
              color: colors.primary,
            ),
            _InsightKpi(
              icon: Icons.horizontal_rule_rounded,
              label: 'p50',
              value: '${_latencyPercentile(durations, 0.5)} ms',
              helper: '中位任务耗时',
              color: OpenHandStatusColors.info,
            ),
            _InsightKpi(
              icon: Icons.trending_up_rounded,
              label: 'p95',
              value: '${_latencyPercentile(durations, 0.95)} ms',
              helper: '尾部任务耗时',
              color: OpenHandStatusColors.warning,
            ),
            _InsightKpi(
              icon: Icons.vertical_align_top_rounded,
              label: '最大',
              value: '${durations.isEmpty ? 0 : durations.last} ms',
              helper: '最慢任务样本',
              color: colors.tertiary,
            ),
          ],
        ),
        _metricTaskPanel(
          finished..sort(
            (left, right) => _taskMeasuredDurationMs(
              right,
            )!.compareTo(_taskMeasuredDurationMs(left)!),
          ),
          title: '最慢任务清单',
          emptyLabel: '暂无已结束任务耗时样本。',
          lens: _TaskRecordLens.duration,
        ),
      ]);
    case _MetricInsightId.overviewConfiguredSources:
      return _buildSourceConfigurationInsight(context, controller);
    case _MetricInsightId.overviewEnabledRules:
      final enabled = controller.rules.where((rule) => rule.enabled).toList();
      final vendors = <String, int>{};
      for (final rule in enabled) {
        final vendor = rule.vendor.trim().isEmpty ? '未分类' : rule.vendor;
        vendors.update(vendor, (value) => value + 1, ifAbsent: () => 1);
      }
      return _metricInsightPage([
        _ruleInsightPanel(context, enabled),
        _InsightRankingSection(
          title: '规则供应商覆盖',
          icon: Icons.category_outlined,
          items: vendors.entries
              .map(
                (entry) => _InsightRankItem(
                  label: entry.key,
                  value: entry.value.toDouble(),
                  valueLabel: '${entry.value} 条',
                  color: colors.primary,
                  key: entry.key,
                ),
              )
              .toList(growable: false),
          emptyLabel: '暂无启用规则。',
          detailBuilder: (context, item) => _ruleInsightPanel(
            context,
            enabled.where(
              (rule) =>
                  (rule.vendor.trim().isEmpty ? '未分类' : rule.vendor) ==
                  item.key,
            ),
            title: '${item.label}启用规则',
          ),
        ),
      ]);
    case _MetricInsightId.overviewProxyRouting:
      return _metricInsightPage([
        _proxyRouteReadinessPanel(context, controller),
        _proxyPolicySection(context, controller),
        _proxyRoutingDecisionPanel(context, controller),
      ]);
    case _MetricInsightId.overviewProxyAverageLatency:
      final samples = _proxyRequestSamples(controller);
      final latencies = samples.map((sample) => sample.responseTimeMs).toList()
        ..sort();
      return _metricInsightPage([
        _proxyRequestInsightPanel(
          context,
          controller,
          _ProxyRequestLens.all,
          title: '近期请求时延样本',
        ),
        _InsightKpiBand(
          title: '代理响应分位',
          icon: Icons.speed_rounded,
          items: [
            _InsightKpi(
              icon: Icons.speed_rounded,
              label: '累计平均',
              value: '${controller.proxyStatus?.averageResponseTimeMs ?? 0} ms',
              helper: '服务运行时累计口径',
              color: colors.secondary,
            ),
            _InsightKpi(
              icon: Icons.horizontal_rule_rounded,
              label: '近期 p50',
              value: '${_latencyPercentile(latencies, 0.5)} ms',
              helper: '${samples.length} 个近期样本',
              color: OpenHandStatusColors.info,
            ),
            _InsightKpi(
              icon: Icons.multiline_chart_rounded,
              label: '近期 p95',
              value: '${_latencyPercentile(latencies, 0.95)} ms',
              helper: '长尾响应边界',
              color: colors.tertiary,
            ),
          ],
        ),
        _InsightTrendSection(
          title: '代理响应时序',
          icon: Icons.multiline_chart_rounded,
          series: [
            OpenHandChartSeries(
              label: '响应耗时',
              values: samples
                  .map((sample) => sample.responseTimeMs.toDouble())
                  .toList(growable: false),
              color: colors.secondary,
            ),
          ],
          sampleLabels: samples
              .map(
                (sample) =>
                    _reportedShortDateTime(sample.at, sample.atReported),
              )
              .toList(growable: false),
          suffix: ' ms',
          emptyLabel: '暂无代理请求时延样本',
          interpolation: OpenHandChartInterpolation.smooth,
          targets: _proxyTargetsForSamples(controller, samples),
        ),
      ]);
    case _MetricInsightId.overviewWarningLogs:
      return _buildLogMetricInsight(
        context,
        logs.where((entry) => entry.level == 'warning'),
        levelLabel: '警告',
        color: OpenHandStatusColors.warning,
      );
    case _MetricInsightId.overviewErrorLogs:
      return _buildLogMetricInsight(
        context,
        logs.where((entry) => entry.level == 'error'),
        levelLabel: '错误',
        color: OpenHandStatusColors.error,
      );
    case _MetricInsightId.overviewCancelledTasks:
      final cancelled = history
          .where((entry) => entry.stage == 'cancelled')
          .toList(growable: false);
      final processed = cancelled.fold<int>(
        0,
        (sum, entry) => sum + entry.progress.processed,
      );
      final candidates = cancelled.fold<int>(
        0,
        (sum, entry) => sum + entry.progress.candidates,
      );
      return _metricInsightPage([
        _metricTaskPanel(
          cancelled,
          title: '取消任务检查点',
          emptyLabel: '暂无已取消任务。',
          lens: _TaskRecordLens.recovery,
        ),
        _InsightKpiBand(
          title: '取消任务影响',
          icon: Icons.cancel_outlined,
          items: [
            _InsightKpi(
              icon: Icons.cancel_outlined,
              label: '取消任务',
              value: '${cancelled.length}',
              helper: '未进入完成终态',
              color: OpenHandStatusColors.warning,
            ),
            _InsightKpi(
              icon: Icons.radar_rounded,
              label: '已处理',
              value: '$processed',
              helper: '取消前累计处理量',
              color: colors.primary,
            ),
            _InsightKpi(
              icon: Icons.filter_alt_outlined,
              label: '候选',
              value: '$candidates',
              helper: '取消前已发现候选',
              color: OpenHandStatusColors.info,
            ),
          ],
        ),
      ]);
    default:
      throw StateError('指标 ID 分派到了错误的运维分组：$id');
  }
}

Widget _buildPipelineMetricInsight(
  BuildContext context,
  _MetricInsightId id,
  ServicesController controller,
) {
  final colors = Theme.of(context).colorScheme;
  final history = controller.history;
  final chronological = _chronologicalTasks(controller);
  final progress = controller.progress;
  int total(int Function(AiExposureProgress value) select) =>
      history.fold<int>(0, (sum, entry) => sum + select(entry.progress));
  final processed = total((value) => value.processed);
  final candidates = total((value) => value.candidates);
  final valid = total((value) => value.valid);
  final highValue = total((value) => value.highValue);

  switch (id) {
    case _MetricInsightId.pipelineCurrentState:
      const stages = [
        'queued',
        'discovering',
        'normalizing',
        'fingerprinting',
        'extracting',
        'validating',
        'persisting',
        'completed',
      ];
      final activeIndex = progress == null
          ? -1
          : stages.indexOf(progress.stage);
      return _metricInsightPage([
        _Section(
          title: '当前执行链',
          icon: Icons.account_tree_outlined,
          child: Column(
            children: stages.indexed
                .map(
                  (entry) => _StageRow(
                    stage: entry.$2,
                    taskId: progress?.jobId,
                    completed: activeIndex >= 0 && entry.$1 < activeIndex,
                    active: entry.$1 == activeIndex,
                  ),
                )
                .toList(growable: false),
          ),
        ),
        _InsightKpiBand(
          title: '活动任务快照',
          icon: Icons.pending_actions_rounded,
          items: [
            _InsightKpi(
              icon: Icons.play_circle_outline_rounded,
              label: '阶段',
              value: progress == null ? '空闲' : _stageName(progress.stage),
              helper: progress?.message.trim().isNotEmpty == true
                  ? progress!.message.trim()
                  : '等待扫描任务',
              color: progress?.isRunning == true
                  ? OpenHandStatusColors.success
                  : colors.outline,
            ),
            _InsightKpi(
              icon: Icons.radar_rounded,
              label: '处理进度',
              value: '${progress?.processed ?? 0}/${progress?.total ?? 0}',
              helper:
                  '${((progress?.fraction ?? 0) * 100).toStringAsFixed(1)}%',
              color: colors.primary,
            ),
            _InsightKpi(
              icon: Icons.update_rounded,
              label: '最近更新',
              value: progress == null
                  ? '--'
                  : _reportedShortDateTime(
                      progress.updatedAt,
                      progress.updatedAtReported,
                    ),
              helper: progress?.jobId.isEmpty == false
                  ? '任务 ${progress!.jobId}'
                  : '无活动任务',
              color: colors.tertiary,
            ),
          ],
        ),
        _metricTaskPanel(
          history.where((entry) => entry.progress.isRunning),
          title: '活动任务运行上下文',
          emptyLabel: '当前没有活动任务。',
          lens: _TaskRecordLens.runtime,
        ),
      ]);
    case _MetricInsightId.pipelineProcessed:
      return _metricInsightPage([
        _InsightTrendSection(
          title: '逐任务处理量',
          icon: Icons.checklist_rounded,
          series: [
            OpenHandChartSeries(
              label: '处理',
              values: chronological
                  .map((entry) => entry.progress.processed.toDouble())
                  .toList(growable: false),
              color: colors.primary,
            ),
            OpenHandChartSeries(
              label: '总量',
              values: chronological
                  .map((entry) => entry.progress.total.toDouble())
                  .toList(growable: false),
              color: colors.outline,
            ),
          ],
          sampleLabels: chronological
              .map(
                (entry) => _reportedShortDateTime(
                  entry.createdAt,
                  entry.createdAtReported,
                ),
              )
              .toList(growable: false),
          suffix: ' 项',
          emptyLabel: '暂无任务处理样本',
          targets: chronological
              .map<_InsightTarget?>((task) => _TaskInsightTarget(task))
              .toList(growable: false),
        ),
        _metricTaskPanel(
          [...history]..sort(
            (left, right) =>
                right.progress.processed.compareTo(left.progress.processed),
          ),
          title: '处理吞吐任务明细',
          emptyLabel: '暂无任务处理记录。',
          lens: _TaskRecordLens.throughput,
        ),
      ]);
    case _MetricInsightId.pipelineCandidates:
      return _metricInsightPage([
        _InsightFunnelSection(
          title: '候选提取漏斗',
          icon: Icons.filter_alt_outlined,
          items: [
            _InsightFunnelItem(
              label: '已处理目标',
              value: processed,
              color: colors.primary,
            ),
            _InsightFunnelItem(
              label: '候选目标',
              value: candidates,
              color: OpenHandStatusColors.info,
            ),
          ],
        ),
        _InsightRankingSection(
          title: '任务候选率排名',
          icon: Icons.filter_list_rounded,
          items: history
              .map((entry) {
                final rate = entry.progress.processed <= 0
                    ? 0.0
                    : entry.progress.candidates / entry.progress.processed;
                return _InsightRankItem(
                  label: entry.name.trim().isEmpty
                      ? entry.id
                      : entry.name.trim(),
                  value: rate,
                  valueLabel: '${(rate * 100).toStringAsFixed(1)}%',
                  helper:
                      '${entry.progress.candidates}/${entry.progress.processed} 个目标进入候选',
                  color: OpenHandStatusColors.info,
                  target: _TaskInsightTarget(entry),
                );
              })
              .toList(growable: false),
          emptyLabel: '暂无候选转化样本。',
        ),
      ]);
    case _MetricInsightId.pipelineValid:
      return _metricInsightPage([
        _InsightFunnelSection(
          title: '验证转化漏斗',
          icon: Icons.verified_outlined,
          items: [
            _InsightFunnelItem(
              label: '候选目标',
              value: candidates,
              color: OpenHandStatusColors.info,
            ),
            _InsightFunnelItem(
              label: '有效结果',
              value: valid,
              color: OpenHandStatusColors.success,
            ),
          ],
        ),
        _InsightTrendSection(
          title: '逐任务验证产出',
          icon: Icons.query_stats_rounded,
          series: [
            OpenHandChartSeries(
              label: '候选',
              values: chronological
                  .map((entry) => entry.progress.candidates.toDouble())
                  .toList(growable: false),
              color: OpenHandStatusColors.info,
            ),
            OpenHandChartSeries(
              label: '有效',
              values: chronological
                  .map((entry) => entry.progress.valid.toDouble())
                  .toList(growable: false),
              color: OpenHandStatusColors.success,
            ),
          ],
          sampleLabels: chronological
              .map(
                (entry) => _reportedShortDateTime(
                  entry.createdAt,
                  entry.createdAtReported,
                ),
              )
              .toList(growable: false),
          suffix: ' 条',
          emptyLabel: '暂无验证产出样本',
          targets: chronological
              .map<_InsightTarget?>((task) => _TaskInsightTarget(task))
              .toList(growable: false),
        ),
        _metricTaskPanel(
          [...history]..sort(
            (left, right) =>
                right.progress.valid.compareTo(left.progress.valid),
          ),
          title: '有效产出任务',
          emptyLabel: '暂无有效产出任务。',
          lens: _TaskRecordLens.valid,
        ),
      ]);
    case _MetricInsightId.pipelineHighValue:
      return _metricInsightPage([
        _InsightFunnelSection(
          title: '高价值筛选漏斗',
          icon: Icons.workspace_premium_outlined,
          items: [
            _InsightFunnelItem(
              label: '有效结果',
              value: valid,
              color: OpenHandStatusColors.success,
            ),
            _InsightFunnelItem(
              label: '高价值结果',
              value: highValue,
              color: _kAiExposureColorHighValue,
            ),
          ],
        ),
        _metricTaskPanel(
          history.where((entry) => entry.progress.highValue > 0),
          title: '高价值任务贡献',
          emptyLabel: '暂无高价值任务产出。',
          lens: _TaskRecordLens.highValue,
        ),
        _metricResultPanel(
          controller.results.where(
            (entry) => entry.category == AiExposureResultCategory.highValue,
          ),
          title: '高价值结果证据',
          emptyLabel: '暂无高价值结果。',
          lens: _ResultRecordLens.risk,
        ),
      ]);
    case _MetricInsightId.pipelineConcurrency:
      final activeTasks = history
          .where((entry) => entry.progress.isRunning)
          .toList(growable: false);
      return _metricInsightPage([
        _InsightCapacitySection(
          title: '任务工作并发容量',
          icon: Icons.speed_rounded,
          configured: controller.defaultConcurrency,
          maximum: kAiExposureMaxScanConcurrency,
          color: colors.tertiary,
        ),
        _InsightKpiBand(
          title: '实时调度压力',
          icon: Icons.schema_outlined,
          items: [
            _InsightKpi(
              icon: Icons.pending_actions_rounded,
              label: '活动扫描任务',
              value: '${activeTasks.length}',
              helper: activeTasks.isEmpty ? '当前队列空闲' : '单任务扫描执行中',
              color: OpenHandStatusColors.info,
            ),
            _InsightKpi(
              icon: Icons.swap_horiz_rounded,
              label: '代理在途请求',
              value: '${controller.proxyStatus?.inFlight ?? 0}',
              helper: '代理运行时实测值',
              color: colors.primary,
            ),
            _InsightKpi(
              icon: Icons.tune_rounded,
              label: '配置边界',
              value: '1 - $kAiExposureMaxScanConcurrency',
              helper: '新建任务时执行范围',
              color: colors.outline,
            ),
          ],
        ),
        _metricTaskPanel(
          activeTasks,
          title: '活动任务调度表',
          emptyLabel: '当前没有活动扫描任务，调度队列为空。',
          lens: _TaskRecordLens.runtime,
        ),
      ]);
    case _MetricInsightId.pipelineFullScan:
      final full = history
          .where((entry) => entry.mode == AiExposureScanMode.full)
          .toList(growable: false);
      return _metricInsightPage([
        _InsightMatrixSection(
          title: '全量扫描范围覆盖',
          icon: Icons.layers_outlined,
          rows: full
              .map(
                (entry) => _InsightMatrixRow(
                  icon: Icons.layers_outlined,
                  title: entry.name.trim().isEmpty
                      ? entry.id
                      : entry.name.trim(),
                  subtitle: entry.authorizedScope.isEmpty
                      ? '未记录授权范围'
                      : entry.authorizedScope.join(' · '),
                  color: _kAiExposureColorCyan,
                  target: _TaskInsightTarget(entry),
                  cells: [
                    _InsightMatrixCell(
                      label: _stageName(entry.stage),
                      color: entry.stage == 'completed'
                          ? OpenHandStatusColors.success
                          : OpenHandStatusColors.info,
                    ),
                    _InsightMatrixCell(
                      label: '来源 ${entry.sources.length}',
                      color: colors.primary,
                    ),
                    _InsightMatrixCell(
                      label: '处理 ${entry.progress.processed}',
                      color: colors.tertiary,
                    ),
                  ],
                ),
              )
              .toList(growable: false),
          emptyLabel: '暂无全量扫描任务。',
        ),
        _metricTaskPanel(
          full,
          title: '全量任务授权明细',
          emptyLabel: '暂无全量扫描任务。',
          lens: _TaskRecordLens.scope,
        ),
      ]);
    case _MetricInsightId.pipelineResumable:
      final resumable = history
          .where((entry) => entry.isResumable)
          .toList(growable: false);
      return _metricInsightPage([
        _InsightMatrixSection(
          title: '恢复就绪检查',
          icon: Icons.restart_alt_rounded,
          rows: resumable
              .map(
                (entry) => _InsightMatrixRow(
                  icon: Icons.restore_rounded,
                  title: entry.name.trim().isEmpty
                      ? entry.id
                      : entry.name.trim(),
                  subtitle: entry.errorMessage?.trim().isNotEmpty == true
                      ? entry.errorMessage!.trim()
                      : entry.progress.message,
                  color: OpenHandStatusColors.warning,
                  target: _TaskInsightTarget(entry),
                  cells: [
                    _InsightMatrixCell(
                      label: _stageName(entry.stage),
                      color: entry.stage == 'failed'
                          ? OpenHandStatusColors.error
                          : OpenHandStatusColors.warning,
                    ),
                    _InsightMatrixCell(
                      label:
                          '检查点 ${_reportedShortDateTime(entry.progress.updatedAt, entry.progress.updatedAtReported)}',
                      color: colors.primary,
                    ),
                    _InsightMatrixCell(
                      label: '范围 ${entry.authorizedScope.length}',
                      color: colors.tertiary,
                    ),
                  ],
                ),
              )
              .toList(growable: false),
          emptyLabel: '当前没有需要恢复的任务。',
        ),
        _metricTaskPanel(
          resumable,
          title: '恢复上下文',
          emptyLabel: '当前没有需要恢复的任务。',
          lens: _TaskRecordLens.recovery,
        ),
      ]);
    default:
      throw StateError('指标 ID 分派到了错误的运维分组：$id');
  }
}

Widget _buildLogMetricInsight(
  BuildContext context,
  Iterable<AiExposureLogEntry> source, {
  required String levelLabel,
  required Color color,
}) {
  final entries = source.toList()
    ..sort((left, right) => right.at.compareTo(left.at));
  final now = DateTime.now();
  final recent = entries
      .where((entry) => now.difference(entry.at).inMinutes <= 60)
      .length;
  final jobRelated = entries.where((entry) => entry.jobId.isNotEmpty).length;
  final clusters = <String, List<AiExposureLogEntry>>{};
  for (final entry in entries) {
    final key = entry.message
        .replaceAll(RegExp(r'\d+'), '#')
        .replaceAll(kInlineWhitespacePattern, ' ')
        .trim();
    clusters.putIfAbsent(key, () => <AiExposureLogEntry>[]).add(entry);
  }
  final hourCounts = <String, int>{};
  for (final entry in entries) {
    final key = '${formatMonthDay(entry.at)} ${twoDigit(entry.at.hour)}:00';
    hourCounts.update(key, (value) => value + 1, ifAbsent: () => 1);
  }
  final colors = Theme.of(context).colorScheme;
  return _metricInsightPage([
    _InsightTimelineSection(
      title: '最近$levelLabel事件流',
      icon: Icons.timeline_rounded,
      entries: entries
          .map(
            (entry) => _InsightTimelineEntry(
              at: entry.at,
              title: entry.message,
              detail: entry.jobId.isEmpty ? '系统运行事件' : '任务 ${entry.jobId}',
              tag: entry.jobId.isEmpty ? '系统' : '任务',
              color: color,
              target: _LogInsightTarget(entry),
            ),
          )
          .toList(growable: false),
      emptyLabel: '暂无$levelLabel事件。',
    ),
    _InsightKpiBand(
      title: '$levelLabel日志态势',
      icon: levelLabel == '警告'
          ? Icons.warning_amber_rounded
          : Icons.error_outline_rounded,
      items: [
        _InsightKpi(
          icon: Icons.receipt_long_outlined,
          label: '事件总数',
          value: '${entries.length}',
          helper: '当前日志保留窗口',
          color: color,
        ),
        _InsightKpi(
          icon: Icons.schedule_rounded,
          label: '最近 60 分钟',
          value: '$recent',
          helper: '按事件时间实时统计',
          color: recent > 0 ? color : colors.outline,
        ),
        _InsightKpi(
          icon: Icons.work_history_outlined,
          label: '任务关联',
          value: '$jobRelated',
          helper: '其余 ${entries.length - jobRelated} 条为系统事件',
          color: colors.primary,
        ),
        _InsightKpi(
          icon: Icons.hub_outlined,
          label: '消息聚类',
          value: '${clusters.length}',
          helper: '忽略消息中的动态数字',
          color: colors.tertiary,
        ),
      ],
    ),
    _InsightRankingSection(
      title: '$levelLabel时间分布',
      icon: Icons.bar_chart_rounded,
      items: hourCounts.entries
          .map(
            (entry) => _InsightRankItem(
              label: entry.key,
              value: entry.value.toDouble(),
              valueLabel: '${entry.value} 条',
              color: color,
              key: entry.key,
            ),
          )
          .toList(growable: false),
      emptyLabel: '暂无$levelLabel时间样本。',
      detailBuilder: (context, item) => _InsightRecordPanel(
        icon: Icons.receipt_long_outlined,
        title: '${item.label} $levelLabel日志',
        records: entries
            .where((entry) {
              final key =
                  '${formatMonthDay(entry.at)} ${twoDigit(entry.at.hour)}:00';
              return key == item.key;
            })
            .map(_logInsightRecord)
            .toList(growable: false),
        emptyLabel: '该时间段暂无$levelLabel日志。',
      ),
    ),
    _InsightRankingSection(
      title: '$levelLabel消息聚类',
      icon: Icons.account_tree_outlined,
      items: clusters.entries
          .map(
            (entry) => _InsightRankItem(
              label: entry.key.isEmpty ? '空消息' : entry.key,
              value: entry.value.length.toDouble(),
              valueLabel: '${entry.value.length} 次',
              helper:
                  '最近 ${_shortDateTime(entry.value.first.at)} · 关联任务 ${entry.value.where((item) => item.jobId.isNotEmpty).map((item) => item.jobId).toSet().length}',
              color: color,
              key: entry.key,
            ),
          )
          .toList(growable: false),
      emptyLabel: '暂无$levelLabel消息聚类。',
      detailBuilder: (context, item) => _InsightRecordPanel(
        icon: Icons.account_tree_outlined,
        title: '${item.label}日志集合',
        records: (clusters[item.key] ?? const <AiExposureLogEntry>[])
            .map(_logInsightRecord)
            .toList(growable: false),
        emptyLabel: '该消息簇暂无$levelLabel日志。',
      ),
    ),
  ]);
}

class _SourceInsightState {
  const _SourceInsightState({
    required this.source,
    required this.requiresCredential,
    required this.configured,
    required this.enabled,
    required this.quota,
    required this.taskCount,
    required this.resultCount,
  });

  final AiExposureSource source;
  final bool requiresCredential;
  final bool configured;
  final bool enabled;
  final AiExposureQuota? quota;
  final int taskCount;
  final int resultCount;

  bool get ready => configured && (quota?.available ?? !requiresCredential);
}

bool _sourceRequiresCredential(AiExposureSource source) => switch (source) {
  AiExposureSource.github ||
  AiExposureSource.githubArtifact ||
  AiExposureSource.gitee ||
  AiExposureSource.gitcode ||
  AiExposureSource.fofa ||
  AiExposureSource.shodan => true,
  _ => false,
};

AiExposureSource _sourceQuotaKey(AiExposureSource source) =>
    source == AiExposureSource.githubArtifact
    ? AiExposureSource.github
    : source;

List<_SourceInsightState> _sourceInsightStates(
  ServicesController controller, {
  bool includeManual = true,
  bool includeArtifact = true,
}) {
  final quotas = {for (final quota in controller.quotas) quota.source: quota};
  final tasks = <AiExposureSource, int>{};
  for (final entry in controller.history) {
    for (final source in entry.sources.toSet()) {
      tasks.update(source, (value) => value + 1, ifAbsent: () => 1);
    }
  }
  final results = <AiExposureSource, int>{};
  for (final entry in controller.results) {
    results.update(entry.source, (value) => value + 1, ifAbsent: () => 1);
  }
  return AiExposureSource.values
      .where(
        (source) =>
            (includeArtifact || source != AiExposureSource.githubArtifact) &&
            (includeManual || source != AiExposureSource.manual),
      )
      .map((source) {
        final requiresCredential = _sourceRequiresCredential(source);
        final configured = _sourceAccessConfigured(controller, source);
        return _SourceInsightState(
          source: source,
          requiresCredential: requiresCredential,
          configured: configured,
          enabled: controller.enabledSources.contains(source),
          quota: quotas[_sourceQuotaKey(source)],
          taskCount: tasks[source] ?? 0,
          resultCount: results[source] ?? 0,
        );
      })
      .toList(growable: false);
}

Widget _buildSourceConfigurationInsight(
  BuildContext context,
  ServicesController controller,
) {
  final colors = Theme.of(context).colorScheme;
  final states = _sourceInsightStates(controller);
  final credentialStates = <String, _SourceInsightState>{};
  for (final state in states.where((state) => state.requiresCredential)) {
    credentialStates.putIfAbsent(
      _sourceCredentialKey(state.source),
      () => state,
    );
  }
  final credentialSources = credentialStates.values;
  final configured = credentialStates.values
      .where((state) => state.configured)
      .length;
  final gaps = credentialStates.values
      .where((state) => !state.configured)
      .toList(growable: false);
  return _metricInsightPage([
    _InsightKpiBand(
      title: '访问前置覆盖',
      icon: Icons.key_rounded,
      items: [
        _InsightKpi(
          icon: Icons.key_rounded,
          label: '需要凭证',
          value: '${credentialSources.length}',
          helper: 'API 与搜索服务来源',
          color: colors.primary,
        ),
        _InsightKpi(
          icon: Icons.verified_user_outlined,
          label: '已配置凭证',
          value: '$configured',
          helper: '满足访问前置条件',
          color: OpenHandStatusColors.success,
        ),
        _InsightKpi(
          icon: Icons.public_rounded,
          label: '无需凭证',
          value: '${states.where((state) => !state.requiresCredential).length}',
          helper: '论坛与公开抓取来源',
          color: OpenHandStatusColors.info,
        ),
        _InsightKpi(
          icon: Icons.key_off_outlined,
          label: '配置缺口',
          value: '${gaps.length}',
          helper: gaps.isEmpty ? '凭证前置完整' : '需要在服务设置中补齐',
          color: gaps.isEmpty
              ? OpenHandStatusColors.success
              : OpenHandStatusColors.warning,
        ),
      ],
    ),
    _InsightMatrixSection(
      title: '来源能力与配置矩阵',
      icon: Icons.grid_view_rounded,
      rows: states
          .map(
            (state) => _InsightMatrixRow(
              icon: aiExposureSourceIcon(state.source),
              title: aiExposureSourceDisplayName(state.source),
              subtitle: state.requiresCredential
                  ? '使用服务访问凭证进行发现'
                  : '公开来源，无需 API 凭证',
              color: _sourceColor(state.source, colors),
              target: _SourceInsightTarget(state.source),
              cells: [
                _InsightMatrixCell(
                  label: state.requiresCredential
                      ? state.configured
                            ? '凭证已配置'
                            : '凭证缺失'
                      : '无需凭证',
                  color: state.configured
                      ? OpenHandStatusColors.success
                      : OpenHandStatusColors.warning,
                ),
                _InsightMatrixCell(
                  label: state.enabled ? '任务已启用' : '任务未启用',
                  color: state.enabled ? colors.primary : colors.outline,
                ),
                _InsightMatrixCell(
                  label: state.quota == null
                      ? '无需计量'
                      : state.quota!.available
                      ? '配额可用'
                      : '配额异常',
                  color: state.quota == null || state.quota!.available
                      ? OpenHandStatusColors.success
                      : OpenHandStatusColors.error,
                ),
              ],
            ),
          )
          .toList(growable: false),
      emptyLabel: '暂无来源配置数据。',
    ),
    _InsightMatrixSection(
      title: '配置缺口操作清单',
      icon: Icons.rule_folder_outlined,
      rows: gaps
          .map(
            (state) => _InsightMatrixRow(
              icon: Icons.key_off_outlined,
              title: aiExposureSourceDisplayName(state.source),
              subtitle: '在服务设置中配置访问凭证后，重新刷新服务状态与配额。',
              color: OpenHandStatusColors.warning,
              target: _SourceInsightTarget(state.source),
              cells: [
                const _InsightMatrixCell(
                  label: '凭证待配置',
                  color: OpenHandStatusColors.warning,
                ),
                _InsightMatrixCell(
                  label: state.enabled ? '任务已启用' : '任务未启用',
                  color: state.enabled ? colors.primary : colors.outline,
                ),
              ],
            ),
          )
          .toList(growable: false),
      emptyLabel: '访问凭证配置完整，无待处理缺口。',
    ),
  ]);
}

Widget _buildStorageMetricInsight(
  BuildContext context,
  _MetricInsightId id,
  ServicesController controller,
) {
  final colors = Theme.of(context).colorScheme;
  final history = controller.history;
  final results = controller.results;
  final rules = controller.rules;
  final logs = controller.logs;

  switch (id) {
    case _MetricInsightId.storageSqlite:
      final path = controller.health?.databasePath.trim() ?? '';
      final walPath = path.isEmpty ? '' : '$path-wal';
      final sharedMemoryPath = path.isEmpty ? '' : '$path-shm';
      return _LocalFileStatsBuilder(
        paths: [path, walPath, sharedMemoryPath],
        refreshKey: controller.health?.uptimeSeconds,
        builder: (context, stats) {
          final database = stats[path];
          final wal = stats[walPath];
          final sharedMemory = stats[sharedMemoryPath];
          return _metricInsightPage([
            _InsightKpiBand(
              title: 'SQLite 文件组成',
              icon: Icons.storage_rounded,
              items: [
                _InsightKpi(
                  icon: Icons.storage_rounded,
                  label: '主数据库',
                  value: formatByteSize(database?.size ?? 0),
                  helper: database == null ? '文件不可访问' : database.modeString(),
                  color: database == null
                      ? OpenHandStatusColors.warning
                      : OpenHandStatusColors.success,
                ),
                _InsightKpi(
                  icon: Icons.edit_note_rounded,
                  label: 'WAL 日志',
                  value: formatByteSize(wal?.size ?? 0),
                  helper: wal == null ? '当前无 WAL 文件' : '事务预写日志',
                  color: colors.primary,
                ),
                _InsightKpi(
                  icon: Icons.memory_rounded,
                  label: '共享内存',
                  value: formatByteSize(sharedMemory?.size ?? 0),
                  helper: sharedMemory == null ? '当前无 SHM 文件' : 'WAL 索引共享内存',
                  color: colors.tertiary,
                ),
                _InsightKpi(
                  icon: Icons.inventory_2_outlined,
                  label: '实体记录',
                  value:
                      '${history.length + results.length + rules.length + logs.length}',
                  helper: '任务、结果、规则与日志',
                  color: OpenHandStatusColors.info,
                ),
              ],
            ),
            _InsightRankingSection(
              title: '数据库文件占用',
              icon: Icons.bar_chart_rounded,
              items: [
                _InsightRankItem(
                  label: '主数据库',
                  value: (database?.size ?? 0).toDouble(),
                  valueLabel: formatByteSize(database?.size ?? 0),
                  color: OpenHandStatusColors.success,
                ),
                _InsightRankItem(
                  label: 'WAL 日志',
                  value: (wal?.size ?? 0).toDouble(),
                  valueLabel: formatByteSize(wal?.size ?? 0),
                  color: colors.primary,
                ),
                _InsightRankItem(
                  label: '共享内存',
                  value: (sharedMemory?.size ?? 0).toDouble(),
                  valueLabel: formatByteSize(sharedMemory?.size ?? 0),
                  color: colors.tertiary,
                ),
              ],
              emptyLabel: '暂无 SQLite 文件占用数据。',
            ),
            _sqliteDatabaseDetailSection(controller, path, stats),
          ]);
        },
      );
    case _MetricInsightId.storageLastWrite:
      final events = <({DateTime at, _InsightTarget target})>[
        ...history.expand(
          (entry) => entry.effectiveFinishedAt != null
              ? [
                  (
                    at: entry.effectiveFinishedAt!,
                    target: _TaskInsightTarget(entry) as _InsightTarget,
                  ),
                ]
              : entry.createdAtReported
              ? [
                  (
                    at: entry.createdAt,
                    target: _TaskInsightTarget(entry) as _InsightTarget,
                  ),
                ]
              : const <({DateTime at, _InsightTarget target})>[],
        ),
        ...results
            .where((entry) => entry.createdAtReported)
            .map(
              (entry) => (
                at: entry.createdAt,
                target: _ResultInsightTarget(entry) as _InsightTarget,
              ),
            ),
        ...logs
            .where((entry) => entry.atReported)
            .map(
              (entry) => (
                at: entry.at,
                target: _LogInsightTarget(entry) as _InsightTarget,
              ),
            ),
      ]..sort((left, right) => left.at.compareTo(right.at));
      final recent = events.length <= 24
          ? events
          : events.sublist(events.length - 24);
      return _metricInsightPage([
        _InsightTrendSection(
          title: '最近持久化活动节奏',
          icon: Icons.edit_calendar_outlined,
          series: [
            OpenHandChartSeries(
              label: '累计写入事件',
              values: List<double>.generate(
                recent.length,
                (index) => (index + 1).toDouble(),
              ),
              color: colors.primary,
            ),
          ],
          sampleLabels: recent
              .map((event) => _shortDateTime(event.at))
              .toList(growable: false),
          suffix: ' 条',
          emptyLabel: '暂无持久化活动时间样本',
          interpolation: OpenHandChartInterpolation.step,
          targets: recent
              .map<_InsightTarget?>((event) => event.target)
              .toList(growable: false),
        ),
        _persistenceWriteEventPanel(context, controller),
      ]);
    default:
      throw StateError('指标 ID 分派到了错误的运维分组：$id');
  }
}

List<AiExposureProxyRequestSample> _proxyRequestSamples(
  ServicesController controller,
) {
  final runtimeEndpoints = controller.proxyStatus?.endpoints;
  final samples = runtimeEndpoints != null && runtimeEndpoints.isNotEmpty
      ? runtimeEndpoints
            .expand((endpoint) => endpoint.statistics.recentRequests)
            .toList()
      : controller.proxyConfiguration.endpoints
            .expand((endpoint) => endpoint.statistics.recentRequests)
            .toList();
  samples.sort((left, right) => left.at.compareTo(right.at));
  return samples.length <= 48 ? samples : samples.sublist(samples.length - 48);
}

List<_InsightTarget?> _proxyRequestSampleTargets(
  ServicesController controller,
) {
  final configuredById = {
    for (final endpoint in controller.proxyConfiguration.endpoints)
      endpoint.runtimeId: endpoint,
  };
  final entries = <_ProxyRequestInsightTarget>[];
  final runtimeEndpoints = controller.proxyStatus?.endpoints;
  if (runtimeEndpoints != null && runtimeEndpoints.isNotEmpty) {
    for (final runtime in runtimeEndpoints) {
      for (final sample in runtime.statistics.recentRequests) {
        entries.add(
          _ProxyRequestInsightTarget(
            endpoint: configuredById[runtime.id],
            address: runtime.address,
            sample: sample,
          ),
        );
      }
    }
  } else {
    for (final endpoint in controller.proxyConfiguration.endpoints) {
      for (final sample in endpoint.statistics.recentRequests) {
        entries.add(
          _ProxyRequestInsightTarget(
            endpoint: endpoint,
            address: endpoint.maskedUrl,
            sample: sample,
          ),
        );
      }
    }
  }
  entries.sort((left, right) => left.sample.at.compareTo(right.sample.at));
  final visible = entries.length <= 48
      ? entries
      : entries.sublist(entries.length - 48);
  return visible.cast<_InsightTarget?>();
}

List<_InsightTarget?> _proxyTargetsForSamples(
  ServicesController controller,
  List<AiExposureProxyRequestSample> samples,
) {
  final available = _proxyRequestSampleTargets(
    controller,
  ).whereType<_ProxyRequestInsightTarget>().toList(growable: false);
  return samples
      .map<_InsightTarget?>(
        (sample) => available
            .where((target) => identical(target.sample, sample))
            .firstOrNull,
      )
      .toList(growable: false);
}

Color _distributionColor(int index, ColorScheme colors) => <Color>[
  colors.primary,
  colors.tertiary,
  OpenHandStatusColors.info,
  OpenHandStatusColors.success,
  OpenHandStatusColors.warning,
  _kAiExposureColorHighValue,
  _kAiExposureColorTeal,
  _kAiExposureColorCyan,
][index % 8];

enum _TaskRecordLens {
  overview,
  runtime,
  throughput,
  candidates,
  valid,
  highValue,
  duration,
  scope,
  recovery,
  archive,
}

_InsightRecord _taskInsightRecord(
  AiExposureHistoryEntry entry, [
  _TaskRecordLens lens = _TaskRecordLens.overview,
]) {
  final tone = switch (entry.stage) {
    'completed' => OpenHandStatusColors.success,
    'failed' => OpenHandStatusColors.error,
    'cancelled' => OpenHandStatusColors.warning,
    _ => OpenHandStatusColors.info,
  };
  final finishedAt = entry.effectiveFinishedAt;
  final durationMs = _taskMeasuredDurationMs(entry);
  final duration = durationMs == null
      ? null
      : Duration(milliseconds: durationMs);
  final progress = entry.progress;
  String rate(int value, int total) =>
      total <= 0 ? '--' : '${(value * 100 / total).toStringAsFixed(1)}%';
  final tags = switch (lens) {
    _TaskRecordLens.runtime => [
      _stageName(entry.stage),
      '处理 ${progress.processed}/${progress.total}',
      '进度 ${rate(progress.processed, progress.total)}',
      '更新 ${_reportedShortDateTime(progress.updatedAt, progress.updatedAtReported)}',
    ],
    _TaskRecordLens.throughput => [
      '处理 ${progress.processed}',
      '发现 ${progress.discovered}',
      '总量 ${progress.total}',
      '完成 ${rate(progress.processed, progress.total)}',
    ],
    _TaskRecordLens.candidates => [
      '候选 ${progress.candidates}',
      '处理 ${progress.processed}',
      '候选率 ${rate(progress.candidates, progress.processed)}',
      '授权范围 ${entry.authorizedScope.length}',
    ],
    _TaskRecordLens.valid => [
      '有效 ${progress.valid}',
      '候选 ${progress.candidates}',
      '有效率 ${rate(progress.valid, progress.candidates)}',
      '来源 ${entry.sources.length}',
    ],
    _TaskRecordLens.highValue => [
      '高价值 ${progress.highValue}',
      '有效 ${progress.valid}',
      '占有效 ${rate(progress.highValue, progress.valid)}',
      _stageName(entry.stage),
    ],
    _TaskRecordLens.duration => [
      '耗时 ${duration == null ? '--' : _duration(duration.inSeconds.clamp(0, Duration.secondsPerDay))}',
      '开始 ${entry.effectiveStartedAt == null ? '时间未上报' : _shortDateTime(entry.effectiveStartedAt!)}',
      if (finishedAt != null) '结束 ${_shortDateTime(finishedAt)}',
      '处理 ${progress.processed}',
    ],
    _TaskRecordLens.scope => [
      entry.mode == AiExposureScanMode.full ? '全量扫描' : '增量扫描',
      '来源 ${entry.sources.length}',
      '授权范围 ${entry.authorizedScope.length}',
      _stageName(entry.stage),
    ],
    _TaskRecordLens.recovery => [
      _stageName(entry.stage),
      entry.isResumable ? '允许恢复' : '不可恢复',
      '检查点 ${_reportedShortDateTime(progress.updatedAt, progress.updatedAtReported)}',
      '任务 ${entry.id}',
    ],
    _TaskRecordLens.archive => [
      '任务 ${entry.id}',
      _stageName(entry.stage),
      '创建 ${_reportedShortDateTime(entry.createdAt, entry.createdAtReported)}',
      if (finishedAt != null) '归档 ${_shortDateTime(finishedAt)}',
    ],
    _TaskRecordLens.overview => [
      _stageName(entry.stage),
      entry.mode == AiExposureScanMode.full ? '全量扫描' : '增量扫描',
      '处理 ${progress.processed}/${progress.total}',
      '候选 ${progress.candidates}',
      '有效 ${progress.valid}',
      if (duration != null)
        '耗时 ${_duration(duration.inSeconds.clamp(0, Duration.secondsPerDay))}',
      if (entry.sources.isNotEmpty)
        entry.sources.map(aiExposureSourceDisplayName).take(3).join(' / '),
      finishedAt == null
          ? _reportedShortDateTime(entry.createdAt, entry.createdAtReported)
          : _shortDateTime(finishedAt),
    ],
  };
  final scope = entry.authorizedScope.take(3).join(', ');
  final subtitle = switch (lens) {
    _TaskRecordLens.scope => scope.isEmpty ? '未记录授权范围。' : '授权：$scope',
    _TaskRecordLens.recovery =>
      entry.errorMessage?.trim().isNotEmpty == true
          ? entry.errorMessage!.trim()
          : progress.message,
    _TaskRecordLens.archive =>
      '扫描来源：${entry.sources.map(aiExposureSourceDisplayName).join(' / ')}',
    _ =>
      entry.errorMessage?.trim().isNotEmpty == true
          ? entry.errorMessage!.trim()
          : progress.message,
  };
  return _InsightRecord(
    icon: _stageIcon(entry.stage),
    title: entry.name.trim().isEmpty ? entry.id : entry.name.trim(),
    subtitle: subtitle,
    tags: tags,
    color: tone,
    target: _TaskInsightTarget(entry),
  );
}

String _resultDisplayName(AiExposureResult entry) {
  final product = entry.product.trim();
  final host = entry.host.trim();
  final url = entry.url.trim();
  if (product.isNotEmpty && host.isNotEmpty) return '$product · $host';
  if (product.isNotEmpty) return product;
  if (host.isNotEmpty) return host;
  if (url.isNotEmpty) return url;
  return entry.id;
}

enum _ResultRecordLens { overview, risk, credentials, source, archive }

_InsightRecord _resultInsightRecord(
  AiExposureResult entry, [
  _ResultRecordLens lens = _ResultRecordLens.overview,
]) {
  final tone = switch (entry.category) {
    AiExposureResultCategory.valid => OpenHandStatusColors.success,
    AiExposureResultCategory.highValue => _kAiExposureColorHighValue,
    AiExposureResultCategory.honeypot => OpenHandStatusColors.error,
    AiExposureResultCategory.suspicious => OpenHandStatusColors.warning,
  };
  final category = switch (entry.category) {
    AiExposureResultCategory.valid => '有效',
    AiExposureResultCategory.highValue => '高价值',
    AiExposureResultCategory.honeypot => '蜜罐',
    AiExposureResultCategory.suspicious => '可疑',
  };
  final title = _resultDisplayName(entry);
  final tags = switch (lens) {
    _ResultRecordLens.risk => [
      category,
      '证据 ${entry.evidence.length}',
      '模型 ${entry.modelCount}',
      if (entry.duplicateResponseHosts > 0)
        '重复响应 ${entry.duplicateResponseHosts}',
      if (entry.duplicateKeyHosts > 0) '重复凭证 ${entry.duplicateKeyHosts}',
      _reportedShortDateTime(entry.createdAt, entry.createdAtReported),
    ],
    _ResultRecordLens.credentials => [
      '状态 ${aiExposureCredentialStateName(entry.credentialState)}',
      if (entry.maskedCredential?.trim().isNotEmpty == true)
        entry.maskedCredential!.trim(),
      '模型 ${entry.modelCount}',
      _reportedShortDateTime(entry.createdAt, entry.createdAtReported),
    ],
    _ResultRecordLens.source => [
      aiExposureSourceDisplayName(entry.source),
      '任务 ${entry.jobId}',
      category,
      _reportedShortDateTime(entry.createdAt, entry.createdAtReported),
    ],
    _ResultRecordLens.archive => [
      '结果 ${entry.id}',
      '任务 ${entry.jobId}',
      category,
      '证据 ${entry.evidence.length}',
      _reportedShortDateTime(entry.createdAt, entry.createdAtReported),
    ],
    _ResultRecordLens.overview => [
      category,
      aiExposureSourceDisplayName(entry.source),
      '凭证 ${aiExposureCredentialStateName(entry.credentialState)}',
      '模型 ${entry.modelCount}',
      if (entry.duplicateResponseHosts > 0)
        '重复响应 ${entry.duplicateResponseHosts}',
      if (entry.duplicateKeyHosts > 0) '重复凭证 ${entry.duplicateKeyHosts}',
      _reportedShortDateTime(entry.createdAt, entry.createdAtReported),
    ],
  };
  final subtitle = switch (lens) {
    _ResultRecordLens.credentials =>
      entry.balanceSummary?.trim().isNotEmpty == true
          ? entry.balanceSummary!.trim()
          : '未记录余额摘要。',
    _ResultRecordLens.source => '关联任务 ${entry.jobId}',
    _ResultRecordLens.archive =>
      entry.responseFingerprint.isEmpty
          ? '未记录响应指纹。'
          : '响应指纹 ${entry.responseFingerprint}',
    _ =>
      entry.evidence.isEmpty ? '暂无证据摘要。' : entry.evidence.take(2).join(' · '),
  };
  return _InsightRecord(
    icon: Icons.fact_check_outlined,
    title: title,
    subtitle: subtitle,
    tags: tags,
    color: tone,
    target: _ResultInsightTarget(entry),
  );
}

String _operationsLogLevelName(String level) => switch (level) {
  'error' => '错误',
  'warning' => '警告',
  'runtime' => '运行时',
  _ => '信息',
};

_InsightRecord _logInsightRecord(AiExposureLogEntry entry) {
  final tone = switch (entry.level) {
    'error' => OpenHandStatusColors.error,
    'warning' => OpenHandStatusColors.warning,
    _ => OpenHandStatusColors.info,
  };
  return _InsightRecord(
    icon: entry.level == 'error'
        ? Icons.error_outline_rounded
        : entry.level == 'warning'
        ? Icons.warning_amber_rounded
        : Icons.info_outline_rounded,
    title: entry.message,
    subtitle: entry.jobId.isEmpty ? '' : '关联任务 ${entry.jobId}',
    tags: [
      _operationsLogLevelName(entry.level),
      _reportedShortDateTime(entry.at, entry.atReported),
    ],
    color: tone,
    target: _LogInsightTarget(entry),
  );
}

_InsightRecord _proxyRequestRecord(
  AiExposureProxyEndpoint endpoint,
  AiExposureProxyRequestSample request,
) {
  final tone = request.succeeded
      ? OpenHandStatusColors.success
      : request.timedOut
      ? OpenHandStatusColors.warning
      : OpenHandStatusColors.error;
  return _InsightRecord(
    icon: request.succeeded
        ? Icons.check_circle_outline_rounded
        : request.timedOut
        ? Icons.timer_off_outlined
        : Icons.error_outline_rounded,
    title: request.succeeded
        ? '请求成功'
        : request.timedOut
        ? '请求超时'
        : '请求失败',
    subtitle: endpoint.maskedUrl,
    tags: [
      '${request.responseTimeMs} ms',
      if (request.statusCode != null) 'HTTP ${request.statusCode}',
      _reportedShortDateTime(request.at, request.atReported),
    ],
    color: tone,
    target: _ProxyRequestInsightTarget(
      endpoint: endpoint,
      address: endpoint.maskedUrl,
      sample: request,
    ),
  );
}

_InsightRecord _proxyProbeRecord(
  AiExposureProxyEndpoint endpoint,
  AiExposureProxyProbeSample probe,
) {
  final tone = probe.reachable
      ? OpenHandStatusColors.success
      : OpenHandStatusColors.error;
  return _InsightRecord(
    icon: probe.reachable
        ? Icons.health_and_safety_outlined
        : Icons.report_problem_outlined,
    title: probe.reachable ? '巡检通过' : '巡检异常',
    subtitle: probe.error?.trim().isNotEmpty == true
        ? probe.error!.trim()
        : endpoint.maskedUrl,
    tags: [
      probe.gatewayReachable ? '网关可达' : '网关不可达',
      if (probe.latencyMs != null) '${probe.latencyMs} ms',
      if (probe.statusCode != null) 'HTTP ${probe.statusCode}',
      if (probe.failure != null) _proxyProbeFailureName(probe.failure!),
      _reportedShortDateTime(probe.checkedAt, probe.checkedAtReported),
    ],
    color: tone,
    target: _ProxyProbeInsightTarget(endpoint: endpoint, sample: probe),
  );
}

String _sourceCredentialKey(AiExposureSource source) => switch (source) {
  AiExposureSource.github || AiExposureSource.githubArtifact => 'github',
  AiExposureSource.gitee => 'gitee',
  AiExposureSource.gitcode => 'gitcode',
  AiExposureSource.fofa => 'fofa',
  AiExposureSource.shodan => 'shodan',
  AiExposureSource.nodeseek => 'nodeseek',
  AiExposureSource.linuxDo => 'linuxDo',
  AiExposureSource.v2ex => 'v2ex',
  AiExposureSource.manual => 'manual',
};

bool _sourceAccessConfigured(
  ServicesController controller,
  AiExposureSource source,
) =>
    !_sourceRequiresCredential(source) ||
    controller.sourceStatus[_sourceCredentialKey(source)] == true;

Widget _ruleInsightPanel(
  BuildContext context,
  Iterable<AiExposureScanRule> rules, {
  String title = '启用规则',
  _RuleDetailLens lens = _RuleDetailLens.overview,
}) {
  final records = rules
      .map(
        (rule) => _InsightRecord(
          icon: Icons.rule_rounded,
          title: rule.vendor.trim().isEmpty ? rule.id : rule.vendor,
          subtitle: switch (lens) {
            _RuleDetailLens.credentials => rule.credentialPatterns.join('\n'),
            _RuleDetailLens.endpoints => [
              ...rule.modelPaths.map((path) => '模型 $path'),
              ...rule.balancePaths.map((path) => '余额 $path'),
            ].join('\n'),
            _RuleDetailLens.encodings =>
              rule.contextTerms.isEmpty
                  ? '未配置上下文约束。'
                  : '上下文：${rule.contextTerms.join(' / ')}',
            _RuleDetailLens.overview => rule.id,
          },
          tags: switch (lens) {
            _RuleDetailLens.credentials => [
              rule.enabled ? '已启用' : '未启用',
              if (rule.protocol.trim().isNotEmpty) rule.protocol,
              '凭证模式 ${rule.credentialPatterns.length}',
              '上下文词 ${rule.contextTerms.length}',
            ],
            _RuleDetailLens.endpoints => [
              rule.enabled ? '已启用' : '未启用',
              '模型端点 ${rule.modelPaths.length}',
              '余额端点 ${rule.balancePaths.length}',
            ],
            _RuleDetailLens.encodings => [
              rule.enabled ? '已启用' : '未启用',
              ...rule.contentEncodings.map((encoding) => encoding.id),
            ],
            _RuleDetailLens.overview => [
              rule.enabled ? '已启用' : '未启用',
              if (rule.protocol.trim().isNotEmpty) rule.protocol,
              '凭证模式 ${rule.credentialPatterns.length}',
              '上下文词 ${rule.contextTerms.length}',
              '模型端点 ${rule.modelPaths.length}',
              '余额端点 ${rule.balancePaths.length}',
              if (rule.contentEncodings.isNotEmpty)
                rule.contentEncodings
                    .map((encoding) => encoding.id)
                    .join(' / '),
            ],
          },
          color: rule.enabled
              ? OpenHandStatusColors.success
              : Theme.of(context).colorScheme.outline,
          target: _RuleInsightTarget(rule),
        ),
      )
      .toList(growable: false);
  return _InsightRecordPanel(
    icon: Icons.rule_folder_outlined,
    title: title,
    records: records,
    emptyLabel: '暂无$title。',
  );
}

enum _RuleDetailLens { overview, credentials, endpoints, encodings }

Widget _proxyPolicySection(
  BuildContext context,
  ServicesController controller,
) {
  final config = controller.proxyConfiguration;
  final text = openHandTextResolver(context);
  return _Section(
    title: '选路与巡检策略',
    icon: Icons.alt_route_rounded,
    child: Column(
      children: [
        _OpsKeyValue(
          label: '当前路由',
          value: serviceProxyRouteText(controller, text),
        ),
        _OpsKeyValue(label: '调度策略', value: _proxyStrategyName(config.strategy)),
        _OpsKeyValue(label: '轮换频率', value: '每 ${config.rotationEvery} 次请求'),
        _OpsKeyValue(label: '本地地址绕过', value: config.bypassLocal ? '开启' : '关闭'),
        _OpsKeyValue(
          label: '自动巡检',
          value: config.inspectionEnabled
              ? '${config.inspectionIntervalMinutes} 分钟 · 并发 ${config.inspectionConcurrency}'
              : '未启用',
        ),
        _OpsKeyValue(
          label: '节点规模',
          value:
              '${config.activeEndpoints.length}/${config.endpoints.length} 启用',
        ),
      ],
    ),
  );
}

Map<String, AiExposureProxyEndpointStatus> _proxyRuntimeById(
  ServicesController controller,
) => {
  for (final endpoint
      in controller.proxyStatus?.endpoints ??
          const <AiExposureProxyEndpointStatus>[])
    endpoint.id: endpoint,
};

AiExposureProxyUsageStatistics _proxyEndpointStatistics(
  AiExposureProxyEndpoint endpoint,
  Map<String, AiExposureProxyEndpointStatus> runtimeById,
) => runtimeById[endpoint.runtimeId]?.statistics ?? endpoint.statistics;

Widget _proxyRoutingDecisionPanel(
  BuildContext context,
  ServicesController controller,
) {
  final colors = Theme.of(context).colorScheme;
  final runtimeById = _proxyRuntimeById(controller);
  final totalSelections = controller.proxyStatus?.totalSelections ?? 0;
  final endpoints =
      controller.proxyConfiguration.endpoints
          .where((endpoint) => endpoint.enabled)
          .toList(growable: false)
        ..sort(
          (left, right) => (runtimeById[right.runtimeId]?.selections ?? 0)
              .compareTo(runtimeById[left.runtimeId]?.selections ?? 0),
        );
  final records = endpoints
      .map((endpoint) {
        final runtime = runtimeById[endpoint.runtimeId];
        final selections = runtime?.selections ?? 0;
        final share = totalSelections <= 0
            ? '--'
            : '${(selections * 100 / totalSelections).toStringAsFixed(1)}%';
        final statistics = _proxyEndpointStatistics(endpoint, runtimeById);
        return _InsightRecord(
          icon: Icons.alt_route_rounded,
          title: endpoint.displayName,
          subtitle:
              '${endpoint.maskedUrl} · 最近使用 ${statistics.lastUsedAt == null ? '--' : _shortDateTime(statistics.lastUsedAt!)}',
          tags: [
            '选路 $selections',
            '流量占比 $share',
            '轮换每 ${controller.proxyConfiguration.rotationEvery} 次',
            '在途 ${statistics.inFlight}',
          ],
          color: selections > 0 ? colors.primary : colors.outline,
          target: _ProxyEndpointInsightTarget(endpoint),
        );
      })
      .toList(growable: false);
  return _InsightRecordPanel(
    icon: Icons.alt_route_rounded,
    title: '节点选路决策',
    records: records,
    emptyLabel: '当前路由未启用代理池节点。',
  );
}

Widget _proxyRouteReadinessPanel(
  BuildContext context,
  ServicesController controller,
) {
  final colors = Theme.of(context).colorScheme;
  final config = controller.proxyConfiguration;
  final active = config.activeEndpoints;
  final runtime = controller.proxyStatus;
  final route = controller.proxyRoute;
  final checks = <_InsightRecord>[
    _InsightRecord(
      icon: Icons.route_outlined,
      title: '当前出口模式',
      subtitle: serviceProxyRouteText(
        controller,
        openHandTextResolver(context),
      ),
      tags: [
        route == AiExposureProxyRoute.pool ? '代理池选路' : '不经过代理池',
        config.bypassLocal ? '本地地址绕过' : '本地地址不绕过',
      ],
      color: route == AiExposureProxyRoute.pool
          ? colors.primary
          : colors.outline,
    ),
    _InsightRecord(
      icon: Icons.dns_outlined,
      title: '代理池就绪条件',
      subtitle: active.isEmpty ? '没有可供调度的启用节点。' : '已启用节点可进入代理池调度。',
      tags: [
        '配置 ${config.endpoints.length}',
        '启用 ${active.length}',
        '运行时 ${runtime?.endpoints.length ?? 0}',
      ],
      color: active.isEmpty
          ? OpenHandStatusColors.warning
          : OpenHandStatusColors.success,
    ),
    _InsightRecord(
      icon: Icons.settings_input_component_outlined,
      title: '运行时路由一致性',
      subtitle: runtime == null
          ? '服务尚未返回代理运行时状态。'
          : runtime.strategy == config.strategy &&
                runtime.rotationEvery == config.rotationEvery
          ? '本地配置与服务运行时策略一致。'
          : '本地配置与服务运行时策略存在差异。',
      tags: [
        '本地 ${_proxyStrategyName(config.strategy)}',
        '运行时 ${runtime == null ? '--' : _proxyStrategyName(runtime.strategy)}',
        '轮换 ${runtime?.rotationEvery ?? config.rotationEvery}',
      ],
      color: runtime == null
          ? colors.outline
          : runtime.strategy == config.strategy &&
                runtime.rotationEvery == config.rotationEvery
          ? OpenHandStatusColors.success
          : OpenHandStatusColors.warning,
    ),
  ];
  return _InsightRecordPanel(
    icon: Icons.route_outlined,
    title: '出口路由就绪检查',
    records: checks,
    emptyLabel: '暂无出口路由状态。',
  );
}

String _proxyProbeFailureName(AiExposureProxyProbeFailure failure) =>
    switch (failure) {
      AiExposureProxyProbeFailure.gateway => '代理网关',
      AiExposureProxyProbeFailure.authentication => '身份认证',
      AiExposureProxyProbeFailure.access => '网关访问',
      AiExposureProxyProbeFailure.forwarding => '代理转发',
      AiExposureProxyProbeFailure.protocol => '协议响应',
      AiExposureProxyProbeFailure.timeout => '连接超时',
    };

Widget _proxyRequestLoadPanel(
  BuildContext context,
  ServicesController controller,
) {
  final runtimeById = _proxyRuntimeById(controller);
  final endpoints = [...controller.proxyConfiguration.endpoints]
    ..sort(
      (left, right) => _proxyEndpointStatistics(right, runtimeById).requests
          .compareTo(_proxyEndpointStatistics(left, runtimeById).requests),
    );
  final records = endpoints
      .map((endpoint) {
        final statistics = _proxyEndpointStatistics(endpoint, runtimeById);
        final completed = statistics.completed;
        return _InsightRecord(
          icon: Icons.data_usage_rounded,
          title: endpoint.displayName,
          subtitle:
              '最近使用 ${statistics.lastUsedAt == null ? '--' : _shortDateTime(statistics.lastUsedAt!)}',
          tags: [
            '请求 ${statistics.requests}',
            '完成 $completed',
            '在途 ${statistics.inFlight}',
            '成功率 ${completed == 0 ? '--' : '${(statistics.successRate * 100).toStringAsFixed(1)}%'}',
            '累计耗时 ${statistics.totalResponseTimeMs} ms',
          ],
          color: statistics.requests > 0
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outline,
          target: _ProxyEndpointInsightTarget(endpoint),
        );
      })
      .toList(growable: false);
  return _InsightRecordPanel(
    icon: Icons.data_usage_rounded,
    title: '节点请求负载排名',
    records: records,
    emptyLabel: '暂无节点请求负载数据。',
  );
}

Widget _proxyFailureEndpointPanel(
  BuildContext context,
  ServicesController controller, {
  String title = '失败关联节点诊断',
}) {
  final runtimeById = _proxyRuntimeById(controller);
  final records = <_InsightRecord>[];
  for (final endpoint in controller.proxyConfiguration.endpoints) {
    final statistics = _proxyEndpointStatistics(endpoint, runtimeById);
    if (statistics.failures == 0 &&
        statistics.timeouts == 0 &&
        statistics.consecutiveFailures == 0 &&
        statistics.lastError.isEmpty) {
      continue;
    }
    records.add(
      _InsightRecord(
        icon: Icons.report_gmailerrorred_outlined,
        title: endpoint.displayName,
        subtitle: statistics.lastError.isEmpty
            ? '节点存在失败或超时请求。'
            : statistics.lastError,
        tags: [
          '失败 ${statistics.failures}',
          '超时 ${statistics.timeouts}',
          '连续失败 ${statistics.consecutiveFailures}',
          '最后失败 ${statistics.lastFailureAt == null ? '--' : _shortDateTime(statistics.lastFailureAt!)}',
          '最长 ${statistics.maxResponseTimeMs} ms',
        ],
        color: OpenHandStatusColors.error,
        target: _ProxyEndpointInsightTarget(endpoint),
      ),
    );
  }
  return _InsightRecordPanel(
    icon: Icons.report_gmailerrorred_outlined,
    title: title,
    records: records,
    emptyLabel: '暂无关联失败或超时的代理节点。',
  );
}

enum _ProxyRequestLens { all, success, failure, timeout, abnormal, http }

Widget _proxyRequestInsightPanel(
  BuildContext context,
  ServicesController controller,
  _ProxyRequestLens lens, {
  required String title,
  bool sortByLatency = false,
  bool Function(
    AiExposureProxyEndpoint? endpoint,
    String address,
    AiExposureProxyRequestSample sample,
  )?
  filter,
}) {
  final entries =
      <(AiExposureProxyEndpoint?, String, AiExposureProxyRequestSample)>[];
  final configuredById = {
    for (final endpoint in controller.proxyConfiguration.endpoints)
      endpoint.runtimeId: endpoint,
  };
  final runtimeEndpoints = controller.proxyStatus?.endpoints;
  if (runtimeEndpoints != null && runtimeEndpoints.isNotEmpty) {
    for (final runtime in runtimeEndpoints) {
      final endpoint = configuredById[runtime.id];
      for (final sample in runtime.statistics.recentRequests) {
        entries.add((endpoint, runtime.address, sample));
      }
    }
  } else {
    for (final endpoint in controller.proxyConfiguration.endpoints) {
      for (final sample in endpoint.statistics.recentRequests) {
        entries.add((endpoint, endpoint.maskedUrl, sample));
      }
    }
  }
  entries.removeWhere(
    (entry) => switch (lens) {
      _ProxyRequestLens.all => false,
      _ProxyRequestLens.success => !entry.$3.succeeded,
      _ProxyRequestLens.failure => entry.$3.succeeded || entry.$3.timedOut,
      _ProxyRequestLens.timeout => !entry.$3.timedOut,
      _ProxyRequestLens.abnormal => entry.$3.succeeded,
      _ProxyRequestLens.http => entry.$3.statusCode == null,
    },
  );
  if (filter != null) {
    entries.removeWhere((entry) => !filter(entry.$1, entry.$2, entry.$3));
  }
  if (sortByLatency) {
    entries.sort((a, b) => b.$3.responseTimeMs.compareTo(a.$3.responseTimeMs));
  } else {
    entries.sort((a, b) => b.$3.at.compareTo(a.$3.at));
  }
  final records = entries
      .map((entry) {
        final endpoint = entry.$1;
        final address = entry.$2;
        final sample = entry.$3;
        final tone = sample.succeeded
            ? OpenHandStatusColors.success
            : sample.timedOut
            ? OpenHandStatusColors.warning
            : OpenHandStatusColors.error;
        return _InsightRecord(
          icon: sample.succeeded
              ? Icons.check_circle_outline_rounded
              : sample.timedOut
              ? Icons.timer_off_outlined
              : Icons.error_outline_rounded,
          title: endpoint?.displayName ?? '运行时节点',
          subtitle: endpoint?.maskedUrl ?? _maskProxyAddress(address),
          tags: [
            sample.succeeded
                ? '成功'
                : sample.timedOut
                ? '超时'
                : '失败',
            '${sample.responseTimeMs} ms',
            if (sample.statusCode != null) 'HTTP ${sample.statusCode}',
            _reportedShortDateTime(sample.at, sample.atReported),
          ],
          color: tone,
          target: _ProxyRequestInsightTarget(
            endpoint: endpoint,
            address: address,
            sample: sample,
          ),
        );
      })
      .toList(growable: false);
  return _InsightRecordPanel(
    icon: Icons.swap_vert_rounded,
    title: title,
    records: records,
    emptyLabel: '暂无$title样本。',
    maxEntries: 50,
  );
}

String _maskProxyAddress(String value) =>
    maskAiExposureProxyUrl(value, fallback: '代理地址不可用');

class _LocalFileStatsBuilder extends StatefulWidget {
  const _LocalFileStatsBuilder({
    required this.paths,
    required this.refreshKey,
    required this.builder,
  });

  final List<String> paths;
  final Object? refreshKey;
  final Widget Function(BuildContext context, Map<String, FileStat> stats)
  builder;

  @override
  State<_LocalFileStatsBuilder> createState() => _LocalFileStatsBuilderState();
}

class _LocalFileStatsBuilderState extends State<_LocalFileStatsBuilder> {
  late Future<Map<String, FileStat>> _stats;

  @override
  void initState() {
    super.initState();
    _stats = _loadLocalFileStats(widget.paths);
  }

  @override
  void didUpdateWidget(covariant _LocalFileStatsBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.paths, widget.paths) ||
        oldWidget.refreshKey != widget.refreshKey) {
      _stats = _loadLocalFileStats(widget.paths);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, FileStat>>(
    future: _stats,
    initialData: const <String, FileStat>{},
    builder: (context, snapshot) =>
        widget.builder(context, snapshot.data ?? const <String, FileStat>{}),
  );
}

Future<Map<String, FileStat>> _loadLocalFileStats(List<String> paths) async {
  if (kIsWeb) return const <String, FileStat>{};
  final uniquePaths = paths
      .map((path) => path.trim())
      .where((path) => path.isNotEmpty)
      .toSet();
  final entries = await Future.wait(
    uniquePaths.map((path) async {
      try {
        final stat = await File(
          path,
        ).stat().timeout(_kOperationsMetadataTimeout);
        return stat.type == FileSystemEntityType.file
            ? MapEntry<String, FileStat>(path, stat)
            : null;
      } on FileSystemException {
        return null;
      } on TimeoutException {
        return null;
      } on UnsupportedError {
        return null;
      }
    }),
  );
  return Map<String, FileStat>.unmodifiable({
    for (final entry in entries.whereType<MapEntry<String, FileStat>>())
      entry.key: entry.value,
  });
}

Widget _sqliteDatabaseDetailSection(
  ServicesController controller,
  String path,
  Map<String, FileStat> stats,
) {
  final database = stats[path];
  final wal = stats[path.isEmpty ? '' : '$path-wal'];
  final sharedMemory = stats[path.isEmpty ? '' : '$path-shm'];
  final totalBytes = [
    database,
    wal,
    sharedMemory,
  ].fold<int>(0, (total, stat) => total + (stat?.size ?? 0));
  return _Section(
    title: 'SQLite 文件与事务状态',
    icon: Icons.storage_rounded,
    child: Column(
      children: [
        _OpsKeyValue(
          label: '数据库路径',
          value: path.isEmpty ? '--' : path,
          maxLines: 3,
        ),
        _OpsKeyValue(
          label: '主数据库',
          value: database == null
              ? '不可访问'
              : '${formatByteSize(database.size)} · ${database.modeString()}',
          color: database == null
              ? OpenHandStatusColors.warning
              : OpenHandStatusColors.success,
        ),
        _OpsKeyValue(
          label: 'WAL 日志',
          value: wal == null ? '当前无 WAL 文件' : formatByteSize(wal.size),
        ),
        _OpsKeyValue(
          label: '共享内存',
          value: sharedMemory == null
              ? '当前无 SHM 文件'
              : formatByteSize(sharedMemory.size),
        ),
        _OpsKeyValue(label: '文件占用合计', value: formatByteSize(totalBytes)),
        _OpsKeyValue(
          label: '主库修改时间',
          value: database == null ? '--' : _shortDateTime(database.modified),
        ),
        const _OpsKeyValue(label: '事务日志模式', value: 'WAL'),
        const _OpsKeyValue(label: '外键约束', value: '开启'),
        const _OpsKeyValue(label: '锁等待上限', value: '5000 ms'),
        _OpsKeyValue(
          label: '实体记录总量',
          value:
              '${controller.history.length + controller.results.length + controller.rules.length + controller.logs.length}',
        ),
      ],
    ),
  );
}

Widget _persistenceWriteEventPanel(
  BuildContext context,
  ServicesController controller,
) {
  final events = <(DateTime, _InsightRecord)>[];
  for (final job in controller.history.where(
    (entry) => entry.createdAtReported,
  )) {
    events.add((
      job.createdAt,
      _InsightRecord(
        icon: Icons.note_add_outlined,
        title: '创建任务 · ${job.name.trim().isEmpty ? job.id : job.name.trim()}',
        subtitle:
            '任务 ${job.id} · ${job.sources.map(aiExposureSourceDisplayName).join(' / ')}',
        tags: [
          _reportedShortDateTime(job.createdAt, job.createdAtReported),
          job.mode == AiExposureScanMode.full ? '全量扫描' : '增量扫描',
          '授权范围 ${job.authorizedScope.length}',
        ],
        color: OpenHandStatusColors.info,
        target: _TaskInsightTarget(job),
      ),
    ));
    if (job.finishedAt != null) {
      events.add((
        job.finishedAt!,
        _InsightRecord(
          icon: _stageIcon(job.stage),
          title:
              '更新任务终态 · ${job.name.trim().isEmpty ? job.id : job.name.trim()}',
          subtitle: job.errorMessage?.trim().isNotEmpty == true
              ? job.errorMessage!.trim()
              : '写入阶段 ${_stageName(job.stage)} 与最终进度快照。',
          tags: [
            _shortDateTime(job.finishedAt!),
            _stageName(job.stage),
            '处理 ${job.progress.processed}',
            '有效 ${job.progress.valid}',
          ],
          color: job.stage == 'completed'
              ? OpenHandStatusColors.success
              : job.stage == 'failed'
              ? OpenHandStatusColors.error
              : OpenHandStatusColors.warning,
          target: _TaskInsightTarget(job),
        ),
      ));
    }
  }
  for (final result in controller.results.where(
    (entry) => entry.createdAtReported,
  )) {
    events.add((
      result.createdAt,
      _InsightRecord(
        icon: Icons.fact_check_outlined,
        title:
            '写入扫描结果 · ${result.product.isEmpty ? result.host : result.product}',
        subtitle: '结果 ${result.id} · 关联任务 ${result.jobId}',
        tags: [
          _reportedShortDateTime(result.createdAt, result.createdAtReported),
          aiExposureSourceDisplayName(result.source),
          '证据 ${result.evidence.length}',
          '凭证 ${aiExposureCredentialStateName(result.credentialState)}',
        ],
        color: OpenHandStatusColors.success,
        target: _ResultInsightTarget(result),
      ),
    ));
  }
  for (final log in controller.logs.where((entry) => entry.atReported)) {
    events.add((
      log.at,
      _InsightRecord(
        icon: Icons.receipt_long_outlined,
        title: '追加运行日志 · ${_operationsLogLevelName(log.level)}',
        subtitle: log.message,
        tags: [
          _reportedShortDateTime(log.at, log.atReported),
          if (log.jobId.isNotEmpty) '任务 ${log.jobId}',
        ],
        color: log.level == 'error'
            ? OpenHandStatusColors.error
            : log.level == 'warning'
            ? OpenHandStatusColors.warning
            : OpenHandStatusColors.info,
        target: _LogInsightTarget(log),
      ),
    ));
  }
  events.sort((left, right) => right.$1.compareTo(left.$1));
  return _InsightRecordPanel(
    icon: Icons.edit_calendar_outlined,
    title: '持久化写入事件时间线',
    records: events.map((event) => event.$2).toList(growable: false),
    emptyLabel: '暂无任务、结果或日志写入事件。',
    maxEntries: 50,
  );
}

Widget _buildTrendInsight(
  BuildContext context, {
  required _TrendInsightId id,
  required String title,
  required ServicesController controller,
  required List<OpenHandChartSeries> series,
  required List<String> sampleLabels,
  required String suffix,
}) => switch (id) {
  _TrendInsightId.taskThroughput => _taskThroughputTrendInsight(
    context,
    controller,
    series,
    sampleLabels,
    suffix,
  ),
  _TrendInsightId.taskDuration => _taskDurationTrendInsight(
    context,
    controller,
    series,
    sampleLabels,
    suffix,
  ),
  _TrendInsightId.pipelineFunnel => _pipelineFunnelTrendInsight(
    context,
    controller,
    series,
    sampleLabels,
    suffix,
  ),
  _TrendInsightId.proxyLatency => _proxyLatencyTrendInsight(
    context,
    controller,
    series,
    sampleLabels,
    suffix,
  ),
  _TrendInsightId.archiveGrowth => _archiveGrowthTrendInsight(
    context,
    controller,
    series,
    sampleLabels,
    suffix,
  ),
  _TrendInsightId.writeLoad => _writeLoadTrendInsight(
    context,
    controller,
    series,
    sampleLabels,
    suffix,
  ),
};

Widget _buildDistributionInsight(
  BuildContext context, {
  required _DistributionInsightId id,
  required String title,
  required ServicesController controller,
  required List<_DistributionItem> items,
}) => switch (id) {
  _DistributionInsightId.resultCategory => _resultCategoryDistributionInsight(
    context,
    controller,
  ),
  _DistributionInsightId.taskStage => _taskStageDistributionInsight(
    context,
    controller,
  ),
  _DistributionInsightId.scanMode => _scanModeDistributionInsight(
    context,
    controller,
  ),
  _DistributionInsightId.resultSource => _resultSourceDistributionInsight(
    context,
    controller,
  ),
  _DistributionInsightId.taskSource => _taskSourceDistributionInsight(
    context,
    controller,
  ),
  _DistributionInsightId.requestOutcome => _requestOutcomeDistributionInsight(
    context,
    controller,
  ),
  _DistributionInsightId.httpStatus => _httpStatusDistributionInsight(
    context,
    controller,
  ),
  _DistributionInsightId.nodeRequest => _nodeRequestDistributionInsight(
    context,
    controller,
  ),
  _DistributionInsightId.recordType => _recordTypeDistributionInsight(
    context,
    controller,
  ),
  _DistributionInsightId.archiveStage => _archiveStageDistributionInsight(
    context,
    controller,
  ),
  _DistributionInsightId.credentialState => _credentialDistributionInsight(
    context,
    controller,
  ),
  _DistributionInsightId.proxyReliability =>
    _proxyReliabilityDistributionInsight(context, controller),
  _DistributionInsightId.ruleVendor => _ruleVendorDistributionInsight(
    context,
    controller,
  ),
};

String _chartRate(int value, int total) =>
    total <= 0 ? '不适用' : '${(value * 100 / total).toStringAsFixed(1)}%';

int? _taskMeasuredDurationMs(AiExposureHistoryEntry task) {
  final startedAt = task.startedAt;
  final finishedAt = task.effectiveFinishedAt;
  if (startedAt == null ||
      finishedAt == null ||
      finishedAt.isBefore(startedAt)) {
    return null;
  }
  return finishedAt.difference(startedAt).inMilliseconds;
}

List<AiExposureHistoryEntry> _chronologicalJobs(
  ServicesController controller, {
  int limit = 24,
}) {
  final jobs =
      controller.history.where((task) => task.createdAtReported).toList()
        ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
  return jobs.length <= limit ? jobs : jobs.sublist(jobs.length - limit);
}

List<_InsightTimelineEntry> _taskTimeline(
  Iterable<AiExposureHistoryEntry> jobs,
) {
  final entries =
      jobs
          .expand((task) {
            final at = task.effectiveFinishedAt ?? task.reportedCreatedAt;
            return at == null
                ? const <_InsightTimelineEntry>[]
                : <_InsightTimelineEntry>[
                    _InsightTimelineEntry(
                      at: at,
                      title: task.name.trim().isEmpty
                          ? task.id
                          : task.name.trim(),
                      detail:
                          '处理 ${task.progress.processed} · 候选 ${task.progress.candidates} · 有效 ${task.progress.valid} · 高价值 ${task.progress.highValue}',
                      color: switch (task.stage) {
                        'completed' => OpenHandStatusColors.success,
                        'failed' => OpenHandStatusColors.error,
                        'cancelled' => OpenHandStatusColors.warning,
                        _ => OpenHandStatusColors.info,
                      },
                      tag: _stageName(task.stage),
                      target: _TaskInsightTarget(task),
                    ),
                  ];
          })
          .toList(growable: false)
        ..sort((left, right) => right.at.compareTo(left.at));
  return entries;
}

Widget _taskThroughputTrendInsight(
  BuildContext context,
  ServicesController controller,
  List<OpenHandChartSeries> series,
  List<String> sampleLabels,
  String suffix,
) {
  final colors = Theme.of(context).colorScheme;
  final jobs = _chronologicalJobs(controller);
  final processed = jobs.fold<int>(
    0,
    (sum, task) => sum + task.progress.processed,
  );
  final valid = jobs.fold<int>(0, (sum, task) => sum + task.progress.valid);
  final abnormal = jobs
      .where((task) => task.stage == 'failed' || task.stage == 'cancelled')
      .length;
  final sourceCounts = <AiExposureSource, int>{};
  final sourceHighValueCounts = <AiExposureSource, int>{};
  final sourceValidCounts = <AiExposureSource, int>{};
  for (final result in controller.results) {
    sourceCounts.update(result.source, (value) => value + 1, ifAbsent: () => 1);
    if (result.category == AiExposureResultCategory.highValue) {
      sourceHighValueCounts.update(
        result.source,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    } else if (result.category == AiExposureResultCategory.valid) {
      sourceValidCounts.update(
        result.source,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
  }
  return _metricInsightPage([
    _InsightKpiBand(
      title: '吞吐与有效转化',
      icon: Icons.speed_rounded,
      items: [
        _InsightKpi(
          icon: Icons.radar_rounded,
          label: '处理总量',
          value: '$processed',
          helper: '最近 ${jobs.length} 个任务',
          color: colors.primary,
        ),
        _InsightKpi(
          icon: Icons.fact_check_outlined,
          label: '有效产出',
          value: '$valid',
          helper: '有效转化 ${_chartRate(valid, processed)}',
          color: OpenHandStatusColors.success,
        ),
        _InsightKpi(
          icon: Icons.warning_amber_rounded,
          label: '异常任务',
          value: '$abnormal',
          helper: '失败或取消',
          color: OpenHandStatusColors.warning,
        ),
        _InsightKpi(
          icon: Icons.travel_explore_rounded,
          label: '产出来源',
          value: '${sourceCounts.length}',
          helper: '基于已归档结果',
          color: colors.tertiary,
        ),
      ],
    ),
    _InsightTrendSection(
      title: '任务级处理与有效产出',
      icon: Icons.show_chart_rounded,
      series: series,
      sampleLabels: sampleLabels,
      sampleTimes: jobs.map((task) => task.createdAt).toList(growable: false),
      suffix: suffix,
      emptyLabel: '暂无任务吞吐样本。',
      targets: jobs
          .map<_InsightTarget?>((task) => _TaskInsightTarget(task))
          .toList(),
    ),
    _InsightRankingSection(
      title: '来源贡献排名',
      icon: Icons.leaderboard_outlined,
      items: sourceCounts.entries
          .map(
            (entry) => _InsightRankItem(
              label: aiExposureSourceDisplayName(entry.key),
              value: entry.value.toDouble(),
              valueLabel: '${entry.value} 条',
              helper:
                  '高价值 ${controller.results.where((result) => result.source == entry.key && result.category == AiExposureResultCategory.highValue).length} · 有效 ${controller.results.where((result) => result.source == entry.key && result.category == AiExposureResultCategory.valid).length}',
              color: _distributionColor(entry.key.index, colors),
              target: _SourceInsightTarget(entry.key),
            ),
          )
          .toList(growable: false),
      emptyLabel: '暂无来源产出记录。',
    ),
    _InsightTimelineSection(
      title: '任务时间线',
      icon: Icons.history_rounded,
      entries: _taskTimeline(jobs),
      emptyLabel: '暂无任务事件。',
    ),
  ]);
}

Widget _taskDurationTrendInsight(
  BuildContext context,
  ServicesController controller,
  List<OpenHandChartSeries> series,
  List<String> sampleLabels,
  String suffix,
) {
  final colors = Theme.of(context).colorScheme;
  final finished = controller.history
      .where((task) => _taskMeasuredDurationMs(task) != null)
      .toList(growable: false);
  final durations = finished
      .map((task) => _taskMeasuredDurationMs(task)!)
      .toList();
  final p50 = _latencyPercentile([...durations], 0.50);
  final p90 = _latencyPercentile([...durations], 0.90);
  final p95 = _latencyPercentile([...durations], 0.95);
  final p99 = _latencyPercentile([...durations], 0.99);
  final stageDurations = <String, List<int>>{};
  for (final task in finished) {
    for (final timing in task.stageTimings) {
      final duration = timing.durationMs;
      if (duration == null) continue;
      stageDurations.putIfAbsent(timing.stage, () => []).add(duration);
    }
  }
  String stageDurationLabel(Set<String> stages) {
    final values = stages
        .expand((stage) => stageDurations[stage] ?? const <int>[])
        .toList(growable: false);
    if (values.isEmpty) return '暂无阶段样本';
    final average =
        values.reduce((left, right) => left + right) ~/ values.length;
    return '平均 $average ms · ${values.length} 个样本';
  }

  final slowest = [...finished]
    ..sort(
      (left, right) => _taskMeasuredDurationMs(
        right,
      )!.compareTo(_taskMeasuredDurationMs(left)!),
    );
  final chartTasks = finished.reversed
      .take(sampleLabels.length)
      .toList(growable: false);
  return _metricInsightPage([
    _InsightKpiBand(
      title: '任务耗时分位',
      icon: Icons.percent_rounded,
      items: [
        _InsightKpi(
          icon: Icons.timer_outlined,
          label: 'P50',
          value: durations.isEmpty ? '暂无样本' : '$p50 ms',
          helper: '${durations.length} 个已结束任务',
          color: OpenHandStatusColors.success,
        ),
        _InsightKpi(
          icon: Icons.timelapse_rounded,
          label: 'P90',
          value: durations.isEmpty ? '暂无样本' : '$p90 ms',
          helper: '尾部耗时基线',
          color: colors.primary,
        ),
        _InsightKpi(
          icon: Icons.multiline_chart_rounded,
          label: 'P95',
          value: durations.isEmpty ? '暂无样本' : '$p95 ms',
          helper: '慢任务阈值',
          color: OpenHandStatusColors.warning,
        ),
        _InsightKpi(
          icon: Icons.warning_amber_rounded,
          label: 'P99',
          value: durations.isEmpty ? '暂无样本' : '$p99 ms',
          helper: '极端长尾',
          color: OpenHandStatusColors.error,
        ),
      ],
    ),
    _InsightTrendSection(
      title: '已结束任务耗时走势',
      icon: Icons.query_stats_rounded,
      series: series,
      sampleLabels: sampleLabels,
      sampleTimes: chartTasks
          .map((task) => task.createdAt)
          .toList(growable: false),
      suffix: suffix,
      emptyLabel: '暂无已结束任务耗时。',
      targets: chartTasks
          .map<_InsightTarget?>((task) => _TaskInsightTarget(task))
          .toList(growable: false),
    ),
    _Section(
      title: '阶段耗时采集口径',
      icon: Icons.account_tree_outlined,
      child: _OpsKeyValueGrid(
        children: [
          _OpsKeyValue(label: '任务总耗时', value: '${durations.length} 个已结束任务'),
          _OpsKeyValue(
            label: '发现阶段',
            value: stageDurationLabel(const {'discovering'}),
          ),
          _OpsKeyValue(
            label: '规范化阶段',
            value: stageDurationLabel(const {'normalizing'}),
          ),
          _OpsKeyValue(
            label: '指纹与提取',
            value: stageDurationLabel(const {'fingerprinting', 'extracting'}),
          ),
          _OpsKeyValue(
            label: '验证与持久化',
            value: stageDurationLabel(const {'validating', 'persisting'}),
          ),
        ],
      ),
    ),
    _InsightRankingSection(
      title: '慢任务排名',
      icon: Icons.trending_down_rounded,
      items: slowest
          .take(20)
          .map(
            (task) => _InsightRankItem(
              label: task.name.trim().isEmpty ? task.id : task.name.trim(),
              value: _taskMeasuredDurationMs(task)!.toDouble(),
              valueLabel: '${_taskMeasuredDurationMs(task)} ms',
              helper:
                  '${_stageName(task.stage)} · 处理 ${task.progress.processed} · ${task.sources.map(aiExposureSourceDisplayName).join(' / ')}',
              color: _taskMeasuredDurationMs(task)! >= p95 && p95 > 0
                  ? OpenHandStatusColors.warning
                  : colors.primary,
              target: _TaskInsightTarget(task),
            ),
          )
          .toList(growable: false),
      emptyLabel: '暂无可排名的任务耗时。',
    ),
    _InsightTimelineSection(
      title: '耗时异常',
      icon: Icons.notification_important_outlined,
      entries: slowest
          .where((task) => p95 > 0 && _taskMeasuredDurationMs(task)! >= p95)
          .map(
            (task) => _InsightTimelineEntry(
              at: task.effectiveFinishedAt!,
              title: task.name.trim().isEmpty ? task.id : task.name.trim(),
              detail: '耗时 ${_taskMeasuredDurationMs(task)} ms · P95 阈值 $p95 ms',
              color: OpenHandStatusColors.warning,
              tag: _stageName(task.stage),
              target: _TaskInsightTarget(task),
            ),
          )
          .toList(growable: false),
      emptyLabel: '暂无超过 P95 的任务。',
    ),
  ]);
}

Widget _pipelineFunnelTrendInsight(
  BuildContext context,
  ServicesController controller,
  List<OpenHandChartSeries> series,
  List<String> sampleLabels,
  String suffix,
) {
  final colors = Theme.of(context).colorScheme;
  final jobs = _chronologicalJobs(controller);
  final processed = jobs.fold<int>(
    0,
    (sum, task) => sum + task.progress.processed,
  );
  final candidates = jobs.fold<int>(
    0,
    (sum, task) => sum + task.progress.candidates,
  );
  final valid = jobs.fold<int>(0, (sum, task) => sum + task.progress.valid);
  final highValue = jobs.fold<int>(
    0,
    (sum, task) => sum + task.progress.highValue,
  );
  return _metricInsightPage([
    _InsightFunnelSection(
      title: '处理到高价值转化漏斗',
      icon: Icons.filter_alt_outlined,
      items: [
        _InsightFunnelItem(
          label: '已处理',
          value: processed,
          color: colors.primary,
        ),
        _InsightFunnelItem(
          label: '候选目标',
          value: candidates,
          color: OpenHandStatusColors.info,
        ),
        _InsightFunnelItem(
          label: '有效结果',
          value: valid,
          color: OpenHandStatusColors.success,
        ),
        _InsightFunnelItem(
          label: '高价值',
          value: highValue,
          color: _kAiExposureColorHighValue,
        ),
      ],
    ),
    _InsightKpiBand(
      title: '转化与流失',
      icon: Icons.compare_arrows_rounded,
      items: [
        _InsightKpi(
          icon: Icons.filter_1_outlined,
          label: '处理→候选',
          value: _chartRate(candidates, processed),
          helper: '流失 ${processed > candidates ? processed - candidates : 0}',
          color: colors.primary,
        ),
        _InsightKpi(
          icon: Icons.filter_2_outlined,
          label: '候选→有效',
          value: _chartRate(valid, candidates),
          helper: '流失 ${candidates > valid ? candidates - valid : 0}',
          color: OpenHandStatusColors.info,
        ),
        _InsightKpi(
          icon: Icons.filter_3_outlined,
          label: '有效→高价值',
          value: _chartRate(highValue, valid),
          helper: '普通有效 ${valid > highValue ? valid - highValue : 0}',
          color: OpenHandStatusColors.success,
        ),
      ],
    ),
    _InsightTrendSection(
      title: '任务漏斗走势',
      icon: Icons.multiline_chart_rounded,
      series: series,
      sampleLabels: sampleLabels,
      suffix: suffix,
      emptyLabel: '暂无漏斗趋势样本。',
      targets: jobs
          .map<_InsightTarget?>((task) => _TaskInsightTarget(task))
          .toList(growable: false),
    ),
    _InsightMatrixSection(
      title: '任务漏斗对比',
      icon: Icons.view_list_outlined,
      rows: jobs.reversed
          .map(
            (task) => _InsightMatrixRow(
              icon: _stageIcon(task.stage),
              title: task.name.trim().isEmpty ? task.id : task.name.trim(),
              subtitle:
                  '${_stageName(task.stage)} · ${_reportedShortDateTime(task.createdAt, task.createdAtReported)}',
              color: task.stage == 'failed'
                  ? OpenHandStatusColors.error
                  : colors.primary,
              target: _TaskInsightTarget(task),
              cells: [
                _InsightMatrixCell(
                  label: '处理 ${task.progress.processed}',
                  color: colors.primary,
                ),
                _InsightMatrixCell(
                  label: '候选 ${task.progress.candidates}',
                  color: OpenHandStatusColors.info,
                ),
                _InsightMatrixCell(
                  label: '有效 ${task.progress.valid}',
                  color: OpenHandStatusColors.success,
                ),
                _InsightMatrixCell(
                  label: '高价值 ${task.progress.highValue}',
                  color: _kAiExposureColorHighValue,
                ),
              ],
            ),
          )
          .toList(growable: false),
      emptyLabel: '暂无任务漏斗数据。',
    ),
  ]);
}

Widget _proxyLatencyTrendInsight(
  BuildContext context,
  ServicesController controller,
  List<OpenHandChartSeries> series,
  List<String> sampleLabels,
  String suffix,
) {
  final colors = Theme.of(context).colorScheme;
  final samples = _proxyRequestSamples(controller);
  final latencies = samples.map((sample) => sample.responseTimeMs).toList();
  final p50 = _latencyPercentile([...latencies], 0.50);
  final p90 = _latencyPercentile([...latencies], 0.90);
  final p95 = _latencyPercentile([...latencies], 0.95);
  final p99 = _latencyPercentile([...latencies], 0.99);
  var jitter = 0;
  if (latencies.length > 1) {
    var totalDelta = 0;
    for (var index = 1; index < latencies.length; index++) {
      totalDelta += (latencies[index] - latencies[index - 1]).abs();
    }
    jitter = (totalDelta / (latencies.length - 1)).round();
  }
  final runtimeById = _proxyRuntimeById(controller);
  final requestTargets = _proxyRequestSampleTargets(controller);
  return _metricInsightPage([
    _InsightKpiBand(
      title: '延迟分位与抖动',
      icon: Icons.speed_rounded,
      items: [
        _InsightKpi(
          icon: Icons.timer_outlined,
          label: 'P50',
          value: latencies.isEmpty ? '暂无样本' : '$p50 ms',
          helper: '${latencies.length} 个请求样本',
          color: OpenHandStatusColors.success,
        ),
        _InsightKpi(
          icon: Icons.timelapse_rounded,
          label: 'P90',
          value: latencies.isEmpty ? '暂无样本' : '$p90 ms',
          helper: '近期尾延迟',
          color: colors.primary,
        ),
        _InsightKpi(
          icon: Icons.multiline_chart_rounded,
          label: 'P95 / P99',
          value: latencies.isEmpty ? '暂无样本' : '$p95 / $p99 ms',
          helper: '长尾边界',
          color: OpenHandStatusColors.warning,
        ),
        _InsightKpi(
          icon: Icons.graphic_eq_rounded,
          label: '平均抖动',
          value: latencies.length < 2 ? '样本不足' : '$jitter ms',
          helper: '相邻样本绝对差',
          color: colors.tertiary,
        ),
      ],
    ),
    _InsightTrendSection(
      title: '代理响应与长尾走势',
      icon: Icons.query_stats_rounded,
      series: series,
      sampleLabels: sampleLabels,
      suffix: suffix,
      emptyLabel: '暂无代理响应样本。',
      interpolation: OpenHandChartInterpolation.smooth,
      targets: requestTargets,
    ),
    _InsightRankingSection(
      title: '慢节点排名',
      icon: Icons.dns_outlined,
      items: controller.proxyConfiguration.endpoints
          .map((endpoint) {
            final stats = _proxyEndpointStatistics(endpoint, runtimeById);
            return _InsightRankItem(
              label: endpoint.displayName,
              value: stats.averageResponseTimeMs.toDouble(),
              valueLabel: stats.completed == 0
                  ? '暂无样本'
                  : '${stats.averageResponseTimeMs} ms',
              helper:
                  'P95 ${_latencyPercentile(stats.recentRequests.map((sample) => sample.responseTimeMs).toList(), 0.95)} ms · 超时 ${stats.timeouts} · 请求 ${stats.requests}',
              color: stats.timeouts > 0
                  ? OpenHandStatusColors.warning
                  : colors.primary,
              target: _ProxyEndpointInsightTarget(endpoint),
            );
          })
          .toList(growable: false),
      emptyLabel: '暂无代理节点。',
    ),
    _proxyRequestInsightPanel(
      context,
      controller,
      _ProxyRequestLens.all,
      title: '最慢请求样本',
      sortByLatency: true,
    ),
    _proxyRequestInsightPanel(
      context,
      controller,
      _ProxyRequestLens.timeout,
      title: '超时事件时间线',
    ),
  ]);
}

Widget _archiveGrowthTrendInsight(
  BuildContext context,
  ServicesController controller,
  List<OpenHandChartSeries> series,
  List<String> sampleLabels,
  String suffix,
) {
  final colors = Theme.of(context).colorScheme;
  final now = DateTime.now();
  final dayAgo = now.subtract(const Duration(hours: 24));
  final twoDaysAgo = now.subtract(const Duration(hours: 48));
  int recentCount(Iterable<DateTime> values) =>
      values.where((at) => !at.isBefore(dayAgo)).length;
  int previousCount(Iterable<DateTime> values) => values
      .where((at) => !at.isBefore(twoDaysAgo) && at.isBefore(dayAgo))
      .length;
  final resultTimes = controller.results
      .where((result) => result.createdAtReported)
      .map((result) => result.createdAt)
      .toList(growable: false);
  final jobTimes = controller.history
      .where((task) => task.createdAtReported)
      .map((task) => task.createdAt)
      .toList(growable: false);
  final logTimes = controller.logs
      .where((log) => log.atReported)
      .map((log) => log.at)
      .toList(growable: false);
  final recentResults = recentCount(resultTimes);
  final previousResults = previousCount(resultTimes);
  final lastWrite = <DateTime>[...resultTimes, ...jobTimes, ...logTimes]
    ..sort();
  final chartTasks = controller.history
      .take(sampleLabels.length)
      .toList()
      .reversed
      .toList(growable: false);
  return _metricInsightPage([
    _InsightKpiBand(
      title: '归档增长速度',
      icon: Icons.trending_up_rounded,
      items: [
        _InsightKpi(
          icon: Icons.work_history_outlined,
          label: '任务 / 24h',
          value: '${recentCount(jobTimes)}',
          helper: '前 24h ${previousCount(jobTimes)}',
          color: colors.primary,
        ),
        _InsightKpi(
          icon: Icons.fact_check_outlined,
          label: '结果 / 24h',
          value: '$recentResults',
          helper: '前 24h $previousResults',
          color: OpenHandStatusColors.info,
        ),
        _InsightKpi(
          icon: Icons.receipt_long_outlined,
          label: '日志 / 24h',
          value: '${recentCount(logTimes)}',
          helper: '前 24h ${previousCount(logTimes)}',
          color: colors.secondary,
        ),
        _InsightKpi(
          icon: Icons.pause_circle_outline_rounded,
          label: '最后写入',
          value: lastWrite.isEmpty ? '暂无写入' : _shortDateTime(lastWrite.last),
          helper: lastWrite.isEmpty ? '暂无归档事件' : '以任务、结果、日志时间戳计算',
          color: lastWrite.isEmpty
              ? colors.outline
              : OpenHandStatusColors.success,
        ),
      ],
    ),
    _InsightTrendSection(
      title: '累计结果归档曲线',
      icon: Icons.stacked_line_chart_rounded,
      series: series,
      sampleLabels: sampleLabels,
      sampleTimes: chartTasks
          .map((task) => task.createdAt)
          .toList(growable: false),
      suffix: suffix,
      emptyLabel: '暂无归档增长样本。',
      interpolation: OpenHandChartInterpolation.step,
      targets: chartTasks
          .map<_InsightTarget?>((task) => _TaskInsightTarget(task))
          .toList(growable: false),
    ),
    _InsightDonutSection(
      title: '当前归档记录构成',
      icon: Icons.pie_chart_outline_rounded,
      items: [
        _DistributionItem(
          '任务',
          controller.history.length,
          colors.primary,
          key: _DistributionRecordType.task,
        ),
        _DistributionItem(
          '结果',
          controller.results.length,
          OpenHandStatusColors.info,
          key: _DistributionRecordType.result,
        ),
        _DistributionItem(
          '规则',
          controller.rules.length,
          colors.tertiary,
          key: _DistributionRecordType.rule,
        ),
        _DistributionItem(
          '日志',
          controller.logs.length,
          colors.secondary,
          key: _DistributionRecordType.log,
        ),
      ],
      detailBuilder: (context, item) => switch (item.key) {
        _DistributionRecordType.task => _metricTaskPanel(
          controller.history,
          title: '当前归档任务',
          emptyLabel: '暂无归档任务。',
        ),
        _DistributionRecordType.result => _metricResultPanel(
          controller.results,
          title: '当前归档结果',
          emptyLabel: '暂无归档结果。',
          lens: _ResultRecordLens.archive,
        ),
        _DistributionRecordType.rule => _ruleInsightPanel(
          context,
          controller.rules,
          title: '当前规则记录',
        ),
        _DistributionRecordType.log => _InsightRecordPanel(
          icon: Icons.receipt_long_outlined,
          title: '当前归档日志',
          records: controller.logs
              .map(_logInsightRecord)
              .toList(growable: false),
          emptyLabel: '暂无归档日志。',
          maxEntries: 50,
        ),
        _ => throw StateError('未知归档记录类型：${item.key}'),
      },
    ),
    _persistenceWriteEventPanel(context, controller),
    _Section(
      title: '增长停滞判定',
      icon: Icons.rule_folder_outlined,
      child: Column(
        children: [
          _OpsKeyValue(label: '近 24h 结果增长', value: '$recentResults 条'),
          _OpsKeyValue(label: '前 24h 结果增长', value: '$previousResults 条'),
          _OpsKeyValue(
            label: '环比',
            value: previousResults == 0
                ? '无前序基数'
                : '${((recentResults - previousResults) * 100 / previousResults).toStringAsFixed(1)}%',
          ),
          _OpsKeyValue(
            label: '停滞状态',
            value: controller.history.isEmpty
                ? '无任务样本'
                : recentResults == 0
                ? '近 24h 无结果写入'
                : '持续写入',
            color: controller.history.isNotEmpty && recentResults == 0
                ? OpenHandStatusColors.warning
                : OpenHandStatusColors.success,
          ),
        ],
      ),
    ),
  ]);
}

Widget _writeLoadTrendInsight(
  BuildContext context,
  ServicesController controller,
  List<OpenHandChartSeries> series,
  List<String> sampleLabels,
  String suffix,
) {
  final colors = Theme.of(context).colorScheme;
  final jobs = _chronologicalJobs(controller);
  final resultCounts = <String, int>{};
  for (final result in controller.results) {
    resultCounts.update(result.jobId, (value) => value + 1, ifAbsent: () => 1);
  }
  final processed = jobs.fold<int>(
    0,
    (sum, task) => sum + task.progress.processed,
  );
  final discovered = jobs.fold<int>(
    0,
    (sum, task) => sum + task.progress.discovered,
  );
  final results = jobs.fold<int>(
    0,
    (sum, task) => sum + (resultCounts[task.id] ?? 0),
  );
  final pressure = jobs.isEmpty
      ? 0
      : ((processed + discovered + results) / jobs.length).round();
  return _metricInsightPage([
    _InsightKpiBand(
      title: '写入负载口径',
      icon: Icons.data_saver_on_rounded,
      items: [
        _InsightKpi(
          icon: Icons.radar_rounded,
          label: '处理快照',
          value: '$processed',
          helper: '最近 ${jobs.length} 个任务',
          color: colors.primary,
        ),
        _InsightKpi(
          icon: Icons.travel_explore_rounded,
          label: '发现快照',
          value: '$discovered',
          helper: '任务进度累计',
          color: OpenHandStatusColors.success,
        ),
        _InsightKpi(
          icon: Icons.fact_check_outlined,
          label: '结果写入',
          value: '$results',
          helper: '按任务 ID 关联',
          color: OpenHandStatusColors.info,
        ),
        _InsightKpi(
          icon: Icons.compress_rounded,
          label: '单位任务压力',
          value: jobs.isEmpty ? '暂无任务' : '$pressure 条',
          helper: '处理+发现+结果 / 任务',
          color: colors.tertiary,
        ),
      ],
    ),
    _InsightTrendSection(
      title: '任务处理与发现写入量',
      icon: Icons.multiline_chart_rounded,
      series: series,
      sampleLabels: sampleLabels,
      sampleTimes: jobs.map((task) => task.createdAt).toList(growable: false),
      suffix: suffix,
      emptyLabel: '暂无任务写入负载样本。',
      targets: jobs
          .map<_InsightTarget?>((task) => _TaskInsightTarget(task))
          .toList(growable: false),
    ),
    _InsightRankingSection(
      title: '高写入压力任务',
      icon: Icons.leaderboard_outlined,
      items: jobs
          .map((task) {
            final count =
                task.progress.processed +
                task.progress.discovered +
                (resultCounts[task.id] ?? 0);
            return _InsightRankItem(
              label: task.name.trim().isEmpty ? task.id : task.name.trim(),
              value: count.toDouble(),
              valueLabel: '$count 条',
              helper:
                  '处理 ${task.progress.processed} · 发现 ${task.progress.discovered} · 结果 ${resultCounts[task.id] ?? 0}',
              color: colors.primary,
              target: _TaskInsightTarget(task),
            );
          })
          .toList(growable: false),
      emptyLabel: '暂无任务写入负载。',
    ),
    _persistenceWriteEventPanel(context, controller),
  ]);
}

Widget _resultCategoryDistributionInsight(
  BuildContext context,
  ServicesController controller,
) {
  final colors = Theme.of(context).colorScheme;
  int count(AiExposureResultCategory category) =>
      controller.results.where((result) => result.category == category).length;
  final items = <_DistributionItem>[
    _DistributionItem(
      '有效',
      count(AiExposureResultCategory.valid),
      OpenHandStatusColors.success,
      key: AiExposureResultCategory.valid,
    ),
    _DistributionItem(
      '高价值',
      count(AiExposureResultCategory.highValue),
      _kAiExposureColorHighValue,
      key: AiExposureResultCategory.highValue,
    ),
    _DistributionItem(
      '可疑',
      count(AiExposureResultCategory.suspicious),
      OpenHandStatusColors.warning,
      key: AiExposureResultCategory.suspicious,
    ),
    _DistributionItem(
      '蜜罐',
      count(AiExposureResultCategory.honeypot),
      OpenHandStatusColors.error,
      key: AiExposureResultCategory.honeypot,
    ),
  ];
  final actionable = items[0].value + items[1].value;
  return _metricInsightPage([
    _InsightKpiBand(
      title: '结果质量概览',
      icon: Icons.fact_check_outlined,
      items: [
        _InsightKpi(
          icon: Icons.inventory_2_outlined,
          label: '结果总数',
          value: '${controller.results.length}',
          helper: '当前可见归档',
          color: colors.primary,
        ),
        _InsightKpi(
          icon: Icons.task_alt_rounded,
          label: '可处置结果',
          value: '$actionable',
          helper: '占比 ${_chartRate(actionable, controller.results.length)}',
          color: OpenHandStatusColors.success,
        ),
        _InsightKpi(
          icon: Icons.workspace_premium_outlined,
          label: '高价值',
          value: '${items[1].value}',
          helper: '优先处置',
          color: _kAiExposureColorHighValue,
        ),
        _InsightKpi(
          icon: Icons.gpp_maybe_outlined,
          label: '可疑与蜜罐',
          value: '${items[2].value + items[3].value}',
          helper: '需复核或隔离',
          color: OpenHandStatusColors.warning,
        ),
      ],
    ),
    _InsightDonutSection(
      title: '结果分类占比',
      icon: Icons.donut_large_rounded,
      items: items,
      detailBuilder: (context, item) {
        final category = item.key! as AiExposureResultCategory;
        return _metricResultPanel(
          controller.results.where((result) => result.category == category),
          title: '${item.label}结果',
          emptyLabel: '暂无${item.label}结果。',
          lens: _ResultRecordLens.risk,
        );
      },
    ),
    _InsightMatrixSection(
      title: '分类诊断矩阵',
      icon: Icons.grid_view_rounded,
      rows: AiExposureResultCategory.values
          .map((category) {
            final matching = controller.results
                .where((result) => result.category == category)
                .toList();
            final label = switch (category) {
              AiExposureResultCategory.valid => '有效',
              AiExposureResultCategory.highValue => '高价值',
              AiExposureResultCategory.suspicious => '可疑',
              AiExposureResultCategory.honeypot => '蜜罐',
            };
            final tone = switch (category) {
              AiExposureResultCategory.valid => OpenHandStatusColors.success,
              AiExposureResultCategory.highValue => _kAiExposureColorHighValue,
              AiExposureResultCategory.suspicious =>
                OpenHandStatusColors.warning,
              AiExposureResultCategory.honeypot => OpenHandStatusColors.error,
            };
            return _InsightMatrixRow(
              icon: Icons.fact_check_outlined,
              title: label,
              subtitle: '${matching.length} 条结果',
              color: tone,
              cells: [
                _InsightMatrixCell(
                  label:
                      '有证据 ${matching.where((result) => result.evidence.isNotEmpty).length}',
                  color: tone,
                ),
                _InsightMatrixCell(
                  label:
                      '有凭证 ${matching.where((result) => result.maskedCredential?.trim().isNotEmpty == true).length}',
                  color: colors.primary,
                ),
                _InsightMatrixCell(
                  label:
                      '重复 ${matching.where((result) => result.duplicateKeyHosts > 0 || result.duplicateResponseHosts > 0).length}',
                  color: colors.tertiary,
                ),
              ],
            );
          })
          .toList(growable: false),
      emptyLabel: '暂无分类结果。',
    ),
    _InsightRecordPanel(
      icon: Icons.manage_search_rounded,
      title: '分类结果明细',
      records: controller.results.map(_resultInsightRecord).toList(),
      emptyLabel: '暂无结果记录。',
    ),
  ]);
}

Widget _taskStageDistributionInsight(
  BuildContext context,
  ServicesController controller,
) {
  final colors = Theme.of(context).colorScheme;
  final counts = <String, int>{};
  for (final task in controller.history) {
    counts.update(task.stage, (value) => value + 1, ifAbsent: () => 1);
  }
  final completed = counts['completed'] ?? 0;
  final failed = counts['failed'] ?? 0;
  final cancelled = counts['cancelled'] ?? 0;
  final active = controller.history.length - completed - failed - cancelled;
  final items = [
    _DistributionItem(
      '完成',
      completed,
      OpenHandStatusColors.success,
      key: 'completed',
    ),
    _DistributionItem('执行中', active, OpenHandStatusColors.info, key: 'running'),
    _DistributionItem('失败', failed, OpenHandStatusColors.error, key: 'failed'),
    _DistributionItem(
      '取消',
      cancelled,
      OpenHandStatusColors.warning,
      key: 'cancelled',
    ),
  ];
  return _metricInsightPage([
    _InsightKpiBand(
      title: '任务状态健康度',
      icon: Icons.monitor_heart_outlined,
      items: [
        _InsightKpi(
          icon: Icons.task_alt_rounded,
          label: '完成率',
          value: _chartRate(completed, controller.history.length),
          helper: '$completed/${controller.history.length} 个任务',
          color: OpenHandStatusColors.success,
        ),
        _InsightKpi(
          icon: Icons.pending_actions_outlined,
          label: '执行中',
          value: '$active',
          helper: controller.hasActiveScan ? '当前存在活动扫描' : '当前无活动扫描',
          color: OpenHandStatusColors.info,
        ),
        _InsightKpi(
          icon: Icons.error_outline_rounded,
          label: '失败率',
          value: _chartRate(failed, controller.history.length),
          helper: '$failed 个失败任务',
          color: OpenHandStatusColors.error,
        ),
        _InsightKpi(
          icon: Icons.restart_alt_rounded,
          label: '可恢复',
          value:
              '${controller.history.where((task) => task.isResumable).length}',
          helper: '按现有任务恢复标记',
          color: colors.tertiary,
        ),
      ],
    ),
    _InsightDonutSection(
      title: '任务终态与运行态',
      icon: Icons.account_tree_outlined,
      items: items,
      detailBuilder: (context, item) {
        final status = item.key! as String;
        return _metricTaskPanel(
          controller.history.where(
            (task) =>
                status == 'running' ? !task.isTerminal : task.stage == status,
          ),
          title: '${item.label}任务',
          emptyLabel: '暂无${item.label}任务。',
          lens: _TaskRecordLens.runtime,
        );
      },
    ),
    _InsightFunnelSection(
      title: '任务生命周期存量',
      icon: Icons.route_outlined,
      items: [
        _InsightFunnelItem(
          label: '全部任务',
          value: controller.history.length,
          color: colors.primary,
        ),
        _InsightFunnelItem(
          label: '已结束',
          value: completed + failed + cancelled,
          color: colors.tertiary,
        ),
        _InsightFunnelItem(
          label: '已完成',
          value: completed,
          color: OpenHandStatusColors.success,
        ),
      ],
    ),
    _InsightRecordPanel(
      icon: Icons.work_history_outlined,
      title: '任务状态明细',
      records: controller.history.map(_taskInsightRecord).toList(),
      emptyLabel: '暂无任务记录。',
    ),
  ]);
}

Widget _scanModeDistributionInsight(
  BuildContext context,
  ServicesController controller,
) {
  final colors = Theme.of(context).colorScheme;
  final full = controller.history
      .where((task) => task.mode == AiExposureScanMode.full)
      .toList();
  final incremental = controller.history
      .where((task) => task.mode == AiExposureScanMode.incremental)
      .toList();
  final modes = <(String, List<AiExposureHistoryEntry>, Color)>[
    ('全量扫描', full, colors.primary),
    ('增量扫描', incremental, OpenHandStatusColors.info),
  ];
  int output(Iterable<AiExposureHistoryEntry> jobs) =>
      jobs.fold(0, (sum, task) => sum + task.progress.valid);
  int failures(Iterable<AiExposureHistoryEntry> jobs) =>
      jobs.where((task) => task.stage == 'failed').length;
  int averageDuration(Iterable<AiExposureHistoryEntry> jobs) {
    final values = jobs.map(_taskMeasuredDurationMs).whereType<int>().toList();
    return values.isEmpty
        ? 0
        : (values.reduce((a, b) => a + b) / values.length).round();
  }

  final activeValidation = controller.history
      .where((task) => task.authorizedScope.isNotEmpty)
      .length;
  return _metricInsightPage([
    _InsightDonutSection(
      title: '全量与增量任务量',
      icon: Icons.schema_outlined,
      items: modes
          .map(
            (mode) => _DistributionItem(
              mode.$1,
              mode.$2.length,
              mode.$3,
              key: mode.$1 == '全量扫描'
                  ? AiExposureScanMode.full
                  : AiExposureScanMode.incremental,
            ),
          )
          .toList(),
      detailBuilder: (context, item) {
        final mode = item.key! as AiExposureScanMode;
        return _metricTaskPanel(
          controller.history.where((task) => task.mode == mode),
          title: '${item.label}任务',
          emptyLabel: '暂无${item.label}任务。',
          lens: _TaskRecordLens.scope,
        );
      },
    ),
    _InsightKpiBand(
      title: '扫描策略概览',
      icon: Icons.tune_rounded,
      items: [
        _InsightKpi(
          icon: Icons.refresh_rounded,
          label: '全量任务',
          value: '${full.length}',
          helper: '产出 ${output(full)}',
          color: colors.primary,
        ),
        _InsightKpi(
          icon: Icons.update_rounded,
          label: '增量任务',
          value: '${incremental.length}',
          helper: '产出 ${output(incremental)}',
          color: OpenHandStatusColors.info,
        ),
        _InsightKpi(
          icon: Icons.verified_user_outlined,
          label: '主动验证',
          value: '$activeValidation',
          helper: '依据授权范围记录',
          color: OpenHandStatusColors.warning,
        ),
        _InsightKpi(
          icon: Icons.fact_check_outlined,
          label: '总有效产出',
          value: '${output(controller.history)}',
          helper: '任务进度快照累计',
          color: OpenHandStatusColors.success,
        ),
      ],
    ),
    _InsightMatrixSection(
      title: '模式产出、耗时与失败率',
      icon: Icons.view_list_outlined,
      rows: modes.map((mode) {
        final duration = averageDuration(mode.$2);
        return _InsightMatrixRow(
          icon: mode.$1 == '全量扫描'
              ? Icons.refresh_rounded
              : Icons.update_rounded,
          title: mode.$1,
          subtitle: '${mode.$2.length} 个任务',
          color: mode.$3,
          cells: [
            _InsightMatrixCell(
              label: '产出 ${output(mode.$2)}',
              color: OpenHandStatusColors.success,
            ),
            _InsightMatrixCell(
              label: duration == 0 ? '暂无已结束任务' : '平均 $duration ms',
              color: colors.tertiary,
            ),
            _InsightMatrixCell(
              label: '失败率 ${_chartRate(failures(mode.$2), mode.$2.length)}',
              color: failures(mode.$2) > 0
                  ? OpenHandStatusColors.error
                  : OpenHandStatusColors.success,
            ),
          ],
        );
      }).toList(),
      emptyLabel: '暂无扫描模式数据。',
    ),
    _InsightRecordPanel(
      icon: Icons.schema_outlined,
      title: '扫描模式任务',
      records: controller.history
          .map((task) => _taskInsightRecord(task, _TaskRecordLens.scope))
          .toList(),
      emptyLabel: '暂无任务范围记录。',
    ),
  ]);
}

Widget _resultSourceDistributionInsight(
  BuildContext context,
  ServicesController controller,
) {
  final colors = Theme.of(context).colorScheme;
  final counts = <AiExposureSource, int>{};
  for (final result in controller.results) {
    counts.update(result.source, (value) => value + 1, ifAbsent: () => 1);
  }
  final sourceStates = {
    for (final state in _sourceInsightStates(controller)) state.source: state,
  };
  final items = AiExposureSource.values
      .map(
        (source) => _DistributionItem(
          aiExposureSourceDisplayName(source),
          counts[source] ?? 0,
          _distributionColor(source.index, colors),
          key: source,
        ),
      )
      .toList();
  return _metricInsightPage([
    _InsightDonutSection(
      title: '结果来源贡献',
      icon: Icons.travel_explore_outlined,
      items: items,
      detailBuilder: (context, item) {
        final source = item.key! as AiExposureSource;
        return _metricResultPanel(
          controller.results.where((result) => result.source == source),
          title: '${item.label}结果',
          emptyLabel: '${item.label}暂无结果。',
          lens: _ResultRecordLens.source,
        );
      },
    ),
    _InsightRankingSection(
      title: '来源产出质量',
      icon: Icons.leaderboard_outlined,
      items: AiExposureSource.values.map((source) {
        final sourceResults = controller.results
            .where((result) => result.source == source)
            .toList();
        final valuable = sourceResults
            .where(
              (result) =>
                  result.category == AiExposureResultCategory.valid ||
                  result.category == AiExposureResultCategory.highValue,
            )
            .length;
        return _InsightRankItem(
          label: aiExposureSourceDisplayName(source),
          value: sourceResults.length.toDouble(),
          valueLabel: '${sourceResults.length} 条',
          helper:
              '可处置 $valuable · 高价值 ${sourceResults.where((result) => result.category == AiExposureResultCategory.highValue).length} · 质量 ${_chartRate(valuable, sourceResults.length)}',
          color: _distributionColor(source.index, colors),
          target: _SourceInsightTarget(source),
        );
      }).toList(),
      emptyLabel: '暂无来源产出数据。',
    ),
    _InsightMatrixSection(
      title: '来源配置与产出',
      icon: Icons.hub_outlined,
      rows: AiExposureSource.values.map((source) {
        final state = sourceStates[source]!;
        final quota = state.quota;
        final ready = state.ready;
        return _InsightMatrixRow(
          icon: aiExposureSourceIcon(source),
          title: aiExposureSourceDisplayName(source),
          subtitle: '结果 ${counts[source] ?? 0}',
          color: ready ? OpenHandStatusColors.success : colors.outline,
          target: _SourceInsightTarget(source),
          cells: [
            _InsightMatrixCell(
              label: ready ? '已就绪' : '未就绪',
              color: ready ? OpenHandStatusColors.success : colors.outline,
            ),
            _InsightMatrixCell(
              label: quota == null
                  ? source == AiExposureSource.manual
                        ? '不适用'
                        : '等待配额刷新'
                  : quota.available
                  ? '配额可用'
                  : '配额异常',
              color: quota?.available == true
                  ? OpenHandStatusColors.success
                  : OpenHandStatusColors.warning,
            ),
          ],
        );
      }).toList(),
      emptyLabel: '暂无来源状态。',
    ),
    _InsightRecordPanel(
      icon: Icons.fact_check_outlined,
      title: '来源产出明细',
      records: controller.results
          .map(
            (result) => _resultInsightRecord(result, _ResultRecordLens.source),
          )
          .toList(),
      emptyLabel: '暂无来源产出记录。',
    ),
  ]);
}

Widget _taskSourceDistributionInsight(
  BuildContext context,
  ServicesController controller,
) {
  final colors = Theme.of(context).colorScheme;
  final taskCounts = <AiExposureSource, int>{};
  final resultCounts = <AiExposureSource, int>{};
  for (final task in controller.history) {
    for (final source in task.sources.toSet()) {
      taskCounts.update(source, (value) => value + 1, ifAbsent: () => 1);
    }
  }
  for (final result in controller.results) {
    resultCounts.update(result.source, (value) => value + 1, ifAbsent: () => 1);
  }
  final sourceStates = {
    for (final state in _sourceInsightStates(controller)) state.source: state,
  };
  return _metricInsightPage([
    _InsightDonutSection(
      title: '任务来源覆盖次数',
      icon: Icons.hub_outlined,
      items: AiExposureSource.values
          .map(
            (source) => _DistributionItem(
              aiExposureSourceDisplayName(source),
              taskCounts[source] ?? 0,
              _distributionColor(source.index, colors),
              key: source,
            ),
          )
          .toList(),
      detailBuilder: (context, item) {
        final source = item.key! as AiExposureSource;
        return _metricTaskPanel(
          controller.history.where((task) => task.sources.contains(source)),
          title: '${item.label}任务',
          emptyLabel: '${item.label}暂无任务。',
          lens: _TaskRecordLens.scope,
        );
      },
    ),
    _InsightKpiBand(
      title: '覆盖广度',
      icon: Icons.radar_rounded,
      items: [
        _InsightKpi(
          icon: Icons.travel_explore_outlined,
          label: '已覆盖来源',
          value: '${taskCounts.values.where((count) => count > 0).length}',
          helper: '共 ${AiExposureSource.values.length} 类来源',
          color: colors.primary,
        ),
        _InsightKpi(
          icon: Icons.work_history_outlined,
          label: '来源调用',
          value:
              '${taskCounts.values.fold<int>(0, (sum, value) => sum + value)}',
          helper: '单任务可覆盖多个来源',
          color: OpenHandStatusColors.info,
        ),
        _InsightKpi(
          icon: Icons.fact_check_outlined,
          label: '来源产出',
          value:
              '${resultCounts.values.fold<int>(0, (sum, value) => sum + value)}',
          helper: '已归档结果',
          color: OpenHandStatusColors.success,
        ),
        _InsightKpi(
          icon: Icons.link_off_rounded,
          label: '无产出来源',
          value:
              '${taskCounts.keys.where((source) => (resultCounts[source] ?? 0) == 0).length}',
          helper: '已调用但暂无结果',
          color: OpenHandStatusColors.warning,
        ),
      ],
    ),
    _InsightMatrixSection(
      title: '来源任务与结果矩阵',
      icon: Icons.grid_view_rounded,
      rows: AiExposureSource.values
          .map(
            (source) => _InsightMatrixRow(
              icon: aiExposureSourceIcon(source),
              title: aiExposureSourceDisplayName(source),
              subtitle: sourceStates[source]!.ready ? '来源已就绪' : '来源未就绪',
              color: _distributionColor(source.index, colors),
              target: _SourceInsightTarget(source),
              cells: [
                _InsightMatrixCell(
                  label: '任务 ${taskCounts[source] ?? 0}',
                  color: colors.primary,
                ),
                _InsightMatrixCell(
                  label: '结果 ${resultCounts[source] ?? 0}',
                  color: OpenHandStatusColors.success,
                ),
                _InsightMatrixCell(
                  label: () {
                    final taskCount = taskCounts[source] ?? 0;
                    final resultCount = resultCounts[source] ?? 0;
                    return taskCount == 0
                        ? '单任务产出 不适用'
                        : '单任务产出 ${(resultCount / taskCount).toStringAsFixed(1)}';
                  }(),
                  color: colors.tertiary,
                ),
              ],
            ),
          )
          .toList(),
      emptyLabel: '暂无来源覆盖数据。',
    ),
    _InsightRecordPanel(
      icon: Icons.schema_outlined,
      title: '任务来源与授权范围',
      records: controller.history
          .map((task) => _taskInsightRecord(task, _TaskRecordLens.scope))
          .toList(),
      emptyLabel: '暂无任务来源记录。',
    ),
  ]);
}

List<_DistributionItem> _proxyOutcomeItems(ServicesController controller) {
  final endpoints = controller.proxyConfiguration.endpoints;
  return [
    _DistributionItem(
      '成功',
      endpoints.fold(0, (sum, endpoint) => sum + endpoint.statistics.successes),
      OpenHandStatusColors.success,
      key: 'success',
    ),
    _DistributionItem(
      '失败',
      endpoints.fold(0, (sum, endpoint) => sum + endpoint.statistics.failures),
      OpenHandStatusColors.error,
      key: 'failure',
    ),
    _DistributionItem(
      '超时',
      endpoints.fold(0, (sum, endpoint) => sum + endpoint.statistics.timeouts),
      OpenHandStatusColors.warning,
      key: 'timeout',
    ),
  ];
}

Widget _requestOutcomeDistributionInsight(
  BuildContext context,
  ServicesController controller,
) {
  final colors = Theme.of(context).colorScheme;
  final items = _proxyOutcomeItems(controller);
  final completed = items.fold<int>(0, (sum, item) => sum + item.value);
  final successful = items.first.value;
  final abnormal = items[1].value + items[2].value;
  return _metricInsightPage([
    _InsightKpiBand(
      title: '请求可靠性',
      icon: Icons.security_rounded,
      items: [
        _InsightKpi(
          icon: Icons.swap_vert_rounded,
          label: '已完成请求',
          value: '$completed',
          helper: '不包含执行中请求',
          color: colors.primary,
        ),
        _InsightKpi(
          icon: Icons.task_alt_rounded,
          label: '成功率',
          value: _chartRate(successful, completed),
          helper: '$successful 个成功请求',
          color: OpenHandStatusColors.success,
        ),
        _InsightKpi(
          icon: Icons.warning_amber_rounded,
          label: '异常率',
          value: _chartRate(abnormal, completed),
          helper: '$abnormal 个失败或超时',
          color: OpenHandStatusColors.warning,
        ),
        _InsightKpi(
          icon: Icons.pending_outlined,
          label: '执行中',
          value: '${controller.proxyStatus?.inFlight ?? 0}',
          helper: '运行时上报',
          color: OpenHandStatusColors.info,
        ),
      ],
    ),
    _InsightDonutSection(
      title: '请求结果占比',
      icon: Icons.donut_large_rounded,
      items: items,
      detailBuilder: (context, item) => _proxyRequestInsightPanel(
        context,
        controller,
        _ProxyRequestLens.all,
        title: '近期${item.label}请求',
        filter: (_, _, sample) => sample.result == item.key,
      ),
    ),
    _proxyRequestLoadPanel(context, controller),
    _proxyFailureEndpointPanel(context, controller, title: '失败与超时节点'),
    _proxyRequestInsightPanel(
      context,
      controller,
      _ProxyRequestLens.abnormal,
      title: '近期异常请求',
    ),
  ]);
}

Widget _httpStatusDistributionInsight(
  BuildContext context,
  ServicesController controller,
) {
  final colors = Theme.of(context).colorScheme;
  final endpoints = controller.proxyConfiguration.endpoints;
  final families = [
    _DistributionItem(
      '2xx',
      endpoints.fold(0, (sum, endpoint) => sum + endpoint.statistics.status2xx),
      OpenHandStatusColors.success,
      key: 2,
    ),
    _DistributionItem(
      '3xx',
      endpoints.fold(0, (sum, endpoint) => sum + endpoint.statistics.status3xx),
      OpenHandStatusColors.info,
      key: 3,
    ),
    _DistributionItem(
      '4xx',
      endpoints.fold(0, (sum, endpoint) => sum + endpoint.statistics.status4xx),
      OpenHandStatusColors.warning,
      key: 4,
    ),
    _DistributionItem(
      '5xx',
      endpoints.fold(0, (sum, endpoint) => sum + endpoint.statistics.status5xx),
      OpenHandStatusColors.error,
      key: 5,
    ),
  ];
  final exactCodes = <int, int>{};
  for (final sample in _proxyRequestSamples(controller)) {
    final code = sample.statusCode;
    if (code != null) {
      exactCodes.update(code, (value) => value + 1, ifAbsent: () => 1);
    }
  }
  final runtimeById = _proxyRuntimeById(controller);
  return _metricInsightPage([
    _InsightDonutSection(
      title: 'HTTP 状态码族',
      icon: Icons.http_rounded,
      items: families,
      detailBuilder: (context, item) => _proxyRequestInsightPanel(
        context,
        controller,
        _ProxyRequestLens.http,
        title: '近期 ${item.label} 请求',
        filter: (_, _, sample) =>
            sample.statusCode != null && sample.statusCode! ~/ 100 == item.key,
      ),
    ),
    _InsightRankingSection(
      title: '近期具体状态码',
      icon: Icons.numbers_rounded,
      items: exactCodes.entries
          .map(
            (entry) => _InsightRankItem(
              label: 'HTTP ${entry.key}',
              value: entry.value.toDouble(),
              valueLabel: '${entry.value} 次',
              helper: '来自近期保留请求样本',
              color: entry.key < 300
                  ? OpenHandStatusColors.success
                  : entry.key < 400
                  ? OpenHandStatusColors.info
                  : entry.key < 500
                  ? OpenHandStatusColors.warning
                  : OpenHandStatusColors.error,
              key: entry.key,
            ),
          )
          .toList(),
      emptyLabel: '近期请求尚未形成具体 HTTP 状态码；状态码族累计值仍可用。',
      detailBuilder: (context, item) => _proxyRequestInsightPanel(
        context,
        controller,
        _ProxyRequestLens.http,
        title: '${item.label} 请求样本',
        filter: (_, _, sample) => sample.statusCode == item.key,
      ),
    ),
    _InsightMatrixSection(
      title: '节点 HTTP 状态矩阵',
      icon: Icons.grid_view_rounded,
      rows: controller.proxyConfiguration.endpoints.map((endpoint) {
        final stats = _proxyEndpointStatistics(endpoint, runtimeById);
        return _InsightMatrixRow(
          icon: Icons.dns_outlined,
          title: endpoint.displayName,
          subtitle:
              '请求 ${stats.requests} · 成功率 ${_chartRate(stats.successes, stats.completed)}',
          color: stats.status5xx > 0
              ? OpenHandStatusColors.error
              : colors.primary,
          target: _ProxyEndpointInsightTarget(endpoint),
          cells: [
            _InsightMatrixCell(
              label: '2xx ${stats.status2xx}',
              color: OpenHandStatusColors.success,
            ),
            _InsightMatrixCell(
              label: '3xx ${stats.status3xx}',
              color: OpenHandStatusColors.info,
            ),
            _InsightMatrixCell(
              label: '4xx ${stats.status4xx}',
              color: OpenHandStatusColors.warning,
            ),
            _InsightMatrixCell(
              label: '5xx ${stats.status5xx}',
              color: OpenHandStatusColors.error,
            ),
          ],
        );
      }).toList(),
      emptyLabel: '暂无节点 HTTP 遥测。',
    ),
    _proxyRequestInsightPanel(
      context,
      controller,
      _ProxyRequestLens.http,
      title: '近期 HTTP 请求样本',
    ),
    _proxyRequestInsightPanel(
      context,
      controller,
      _ProxyRequestLens.abnormal,
      title: '近期失败样本',
    ),
  ]);
}

Widget _nodeRequestDistributionInsight(
  BuildContext context,
  ServicesController controller,
) {
  final colors = Theme.of(context).colorScheme;
  final runtimeById = _proxyRuntimeById(controller);
  final endpoints = controller.proxyConfiguration.endpoints;
  final totalRequests = endpoints.fold<int>(
    0,
    (sum, endpoint) =>
        sum + _proxyEndpointStatistics(endpoint, runtimeById).requests,
  );
  return _metricInsightPage([
    _InsightDonutSection(
      title: '节点负载占比',
      icon: Icons.account_tree_outlined,
      items: endpoints.indexed
          .map(
            (entry) => _DistributionItem(
              entry.$2.displayName,
              _proxyEndpointStatistics(entry.$2, runtimeById).requests,
              _distributionColor(entry.$1, colors),
              key: entry.$2,
            ),
          )
          .toList(),
      detailBuilder: (context, item) {
        final endpoint = item.key! as AiExposureProxyEndpoint;
        return _proxyRequestInsightPanel(
          context,
          controller,
          _ProxyRequestLens.all,
          title: '${endpoint.displayName}近期请求',
          filter: (candidate, _, _) =>
              candidate?.runtimeId == endpoint.runtimeId,
        );
      },
    ),
    _InsightRankingSection(
      title: '节点请求与健康排名',
      icon: Icons.leaderboard_outlined,
      items: endpoints.map((endpoint) {
        final stats = _proxyEndpointStatistics(endpoint, runtimeById);
        return _InsightRankItem(
          label: endpoint.displayName,
          value: stats.requests.toDouble(),
          valueLabel: '${stats.requests} 次',
          helper:
              '负载 ${_chartRate(stats.requests, totalRequests)} · 成功率 ${_chartRate(stats.successes, stats.completed)} · 平均 ${stats.completed == 0 ? '暂无样本' : '${stats.averageResponseTimeMs} ms'}',
          color: stats.consecutiveFailures > 0
              ? OpenHandStatusColors.error
              : colors.primary,
          target: _ProxyEndpointInsightTarget(endpoint),
        );
      }).toList(),
      emptyLabel: '暂无节点负载。',
    ),
    _InsightMatrixSection(
      title: '节点可靠性矩阵',
      icon: Icons.grid_view_rounded,
      rows: endpoints.map((endpoint) {
        final stats = _proxyEndpointStatistics(endpoint, runtimeById);
        return _InsightMatrixRow(
          icon: Icons.dns_outlined,
          title: endpoint.displayName,
          subtitle: endpoint.maskedUrl,
          color: stats.consecutiveFailures > 0
              ? OpenHandStatusColors.error
              : endpoint.enabled
              ? OpenHandStatusColors.success
              : colors.outline,
          target: _ProxyEndpointInsightTarget(endpoint),
          cells: [
            _InsightMatrixCell(
              label: '成功 ${stats.successes}',
              color: OpenHandStatusColors.success,
            ),
            _InsightMatrixCell(
              label: '失败 ${stats.failures}',
              color: OpenHandStatusColors.error,
            ),
            _InsightMatrixCell(
              label: '超时 ${stats.timeouts}',
              color: OpenHandStatusColors.warning,
            ),
            _InsightMatrixCell(
              label: '连续失败 ${stats.consecutiveFailures}',
              color: stats.consecutiveFailures > 0
                  ? OpenHandStatusColors.error
                  : colors.outline,
            ),
          ],
        );
      }).toList(),
      emptyLabel: '暂无代理节点。',
    ),
    _proxyFailureEndpointPanel(context, controller),
    _proxyRequestInsightPanel(
      context,
      controller,
      _ProxyRequestLens.all,
      title: '节点请求时间线',
    ),
  ]);
}

Widget _recordTypeDistributionInsight(
  BuildContext context,
  ServicesController controller,
) {
  final colors = Theme.of(context).colorScheme;
  final path = controller.health?.databasePath.trim() ?? '';
  final total =
      controller.history.length +
      controller.results.length +
      controller.rules.length +
      controller.logs.length;
  return _LocalFileStatsBuilder(
    paths: [
      path,
      if (path.isNotEmpty) ...['$path-wal', '$path-shm'],
    ],
    refreshKey: controller.health?.uptimeSeconds,
    builder: (context, stats) {
      final database = stats[path];
      return _metricInsightPage([
        _InsightKpiBand(
          title: '持久化记录概览',
          icon: Icons.storage_rounded,
          items: [
            _InsightKpi(
              icon: Icons.receipt_long_outlined,
              label: '可见记录',
              value: '$total',
              helper: '任务、结果、规则、日志',
              color: colors.primary,
            ),
            _InsightKpi(
              icon: Icons.work_history_outlined,
              label: '任务',
              value: '${controller.history.length}',
              helper: '任务归档',
              color: colors.tertiary,
            ),
            _InsightKpi(
              icon: Icons.fact_check_outlined,
              label: '结果',
              value: '${controller.results.length}',
              helper: '扫描结果归档',
              color: OpenHandStatusColors.info,
            ),
            _InsightKpi(
              icon: Icons.storage_rounded,
              label: '数据库文件',
              value: database == null
                  ? path.isEmpty
                        ? '数据库路径未上报'
                        : '等待文件元数据刷新'
                  : formatByteSize(database.size),
              helper: path.isEmpty ? '路径未上报' : path,
              color: database == null
                  ? colors.outline
                  : OpenHandStatusColors.success,
            ),
          ],
        ),
        _InsightDonutSection(
          title: '记录类型构成',
          icon: Icons.pie_chart_outline_rounded,
          items: [
            _DistributionItem(
              '任务',
              controller.history.length,
              colors.primary,
              key: _DistributionRecordType.task,
            ),
            _DistributionItem(
              '结果',
              controller.results.length,
              OpenHandStatusColors.info,
              key: _DistributionRecordType.result,
            ),
            _DistributionItem(
              '规则',
              controller.rules.length,
              colors.tertiary,
              key: _DistributionRecordType.rule,
            ),
            _DistributionItem(
              '日志',
              controller.logs.length,
              colors.secondary,
              key: _DistributionRecordType.log,
            ),
          ],
          detailBuilder: (context, item) => switch (item.key) {
            _DistributionRecordType.task => _metricTaskPanel(
              controller.history,
              title: '任务记录',
              emptyLabel: '暂无任务记录。',
              lens: _TaskRecordLens.archive,
            ),
            _DistributionRecordType.result => _metricResultPanel(
              controller.results,
              title: '结果记录',
              emptyLabel: '暂无结果记录。',
              lens: _ResultRecordLens.archive,
            ),
            _DistributionRecordType.rule => _ruleInsightPanel(
              context,
              controller.rules,
              title: '规则记录',
            ),
            _DistributionRecordType.log => _InsightRecordPanel(
              icon: Icons.receipt_long_outlined,
              title: '日志记录',
              records: controller.logs.map(_logInsightRecord).toList(),
              emptyLabel: '暂无日志记录。',
            ),
            _ => throw StateError('未知记录类型：${item.key}'),
          },
        ),
        _sqliteDatabaseDetailSection(controller, path, stats),
        _persistenceWriteEventPanel(context, controller),
      ]);
    },
  );
}

Widget _archiveStageDistributionInsight(
  BuildContext context,
  ServicesController controller,
) {
  final colors = Theme.of(context).colorScheme;
  final counts = <String, int>{};
  for (final task in controller.history) {
    counts.update(task.stage, (value) => value + 1, ifAbsent: () => 1);
  }
  final items = counts.entries
      .map(
        (entry) => _DistributionItem(
          _stageName(entry.key),
          entry.value,
          switch (entry.key) {
            'completed' => OpenHandStatusColors.success,
            'failed' => OpenHandStatusColors.error,
            'cancelled' => OpenHandStatusColors.warning,
            _ => OpenHandStatusColors.info,
          },
          key: entry.key,
        ),
      )
      .toList();
  return _metricInsightPage([
    _InsightDonutSection(
      title: '任务归档状态',
      icon: Icons.inventory_2_outlined,
      items: items,
      detailBuilder: (context, item) {
        final stage = item.key! as String;
        return _metricTaskPanel(
          controller.history.where((task) => task.stage == stage),
          title: '${item.label}归档任务',
          emptyLabel: '暂无${item.label}归档任务。',
          lens: _TaskRecordLens.archive,
        );
      },
    ),
    _InsightKpiBand(
      title: '任务归档概览',
      icon: Icons.restore_rounded,
      items: [
        _InsightKpi(
          icon: Icons.inventory_2_outlined,
          label: '已归档任务',
          value: '${controller.history.length}',
          helper: '当前可见任务记录',
          color: colors.primary,
        ),
        _InsightKpi(
          icon: Icons.task_alt_rounded,
          label: '完整终态',
          value: '${counts['completed'] ?? 0}',
          helper: '已完成任务',
          color: OpenHandStatusColors.success,
        ),
        _InsightKpi(
          icon: Icons.error_outline_rounded,
          label: '失败归档',
          value: '${counts['failed'] ?? 0}',
          helper: '需检查错误信息',
          color: OpenHandStatusColors.error,
        ),
      ],
    ),
    _InsightRecordPanel(
      icon: Icons.inventory_2_outlined,
      title: '任务归档明细',
      records: controller.history
          .map((task) => _taskInsightRecord(task, _TaskRecordLens.archive))
          .toList(),
      emptyLabel: '暂无任务归档记录。',
    ),
  ]);
}

Widget _credentialDistributionInsight(
  BuildContext context,
  ServicesController controller,
) {
  final colors = Theme.of(context).colorScheme;
  final stateCounts = <String, int>{};
  final vendorCounts = <String, int>{};
  final sourceCounts = <AiExposureSource, int>{};
  for (final result in controller.results) {
    stateCounts.update(
      result.credentialState,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    final vendor = result.product.trim().isEmpty
        ? '未识别供应商'
        : result.product.trim();
    vendorCounts.update(vendor, (value) => value + 1, ifAbsent: () => 1);
    sourceCounts.update(result.source, (value) => value + 1, ifAbsent: () => 1);
  }
  final duplicates = controller.results
      .where((result) => result.duplicateKeyHosts > 0)
      .length;
  final evidence = controller.results
      .where((result) => result.evidence.isNotEmpty)
      .length;
  return _metricInsightPage([
    _InsightKpiBand(
      title: '凭证质量概览',
      icon: Icons.key_outlined,
      items: [
        _InsightKpi(
          icon: Icons.key_outlined,
          label: '凭证结果',
          value: '${controller.results.length}',
          helper: '${stateCounts.length} 类验证状态',
          color: colors.primary,
        ),
        _InsightKpi(
          icon: Icons.copy_all_outlined,
          label: '重复凭证',
          value: '$duplicates',
          helper: '存在重复主机引用',
          color: colors.tertiary,
        ),
        _InsightKpi(
          icon: Icons.fact_check_outlined,
          label: '证据完整',
          value: '$evidence',
          helper: '完整率 ${_chartRate(evidence, controller.results.length)}',
          color: OpenHandStatusColors.success,
        ),
        _InsightKpi(
          icon: Icons.business_outlined,
          label: '供应商',
          value: '${vendorCounts.length}',
          helper: '依据结果产品字段',
          color: OpenHandStatusColors.info,
        ),
      ],
    ),
    _InsightDonutSection(
      title: '凭证验证状态',
      icon: Icons.verified_user_outlined,
      items: stateCounts.entries.indexed
          .map(
            (entry) => _DistributionItem(
              aiExposureCredentialStateName(entry.$2.key),
              entry.$2.value,
              _credentialStateColor(entry.$2.key, colors),
              key: entry.$2.key,
            ),
          )
          .toList(),
      detailBuilder: (context, item) => _metricResultPanel(
        controller.results.where(
          (result) => result.credentialState == item.key,
        ),
        title: '${item.label}凭证结果',
        emptyLabel: '暂无${item.label}凭证结果。',
        lens: _ResultRecordLens.credentials,
      ),
    ),
    _InsightRankingSection(
      title: '供应商凭证产出',
      icon: Icons.business_outlined,
      items: vendorCounts.entries.indexed
          .map(
            (entry) => _InsightRankItem(
              label: entry.$2.key,
              value: entry.$2.value.toDouble(),
              valueLabel: '${entry.$2.value} 条',
              helper: '基于真实结果产品字段',
              color: _distributionColor(entry.$1, colors),
              key: entry.$2.key,
            ),
          )
          .toList(),
      emptyLabel: '暂无可归类的供应商结果。',
      detailBuilder: (context, item) => _metricResultPanel(
        controller.results.where((result) {
          final vendor = result.product.trim().isEmpty
              ? '未识别供应商'
              : result.product.trim();
          return vendor == item.key;
        }),
        title: '${item.label}凭证结果',
        emptyLabel: '该供应商暂无凭证结果。',
        lens: _ResultRecordLens.credentials,
      ),
    ),
    _InsightRankingSection(
      title: '来源凭证产出',
      icon: Icons.travel_explore_outlined,
      items: sourceCounts.entries
          .map(
            (entry) => _InsightRankItem(
              label: aiExposureSourceDisplayName(entry.key),
              value: entry.value.toDouble(),
              valueLabel: '${entry.value} 条',
              helper:
                  '占比 ${_chartRate(entry.value, controller.results.length)}',
              color: _distributionColor(entry.key.index, colors),
              target: _SourceInsightTarget(entry.key),
            ),
          )
          .toList(),
      emptyLabel: '暂无凭证来源。',
    ),
    _InsightRecordPanel(
      icon: Icons.manage_search_rounded,
      title: '凭证证据与重复明细',
      records: controller.results
          .map(
            (result) =>
                _resultInsightRecord(result, _ResultRecordLens.credentials),
          )
          .toList(),
      emptyLabel: '暂无凭证验证记录。',
    ),
  ]);
}

Widget _proxyReliabilityDistributionInsight(
  BuildContext context,
  ServicesController controller,
) {
  final colors = Theme.of(context).colorScheme;
  final outcomes = _proxyOutcomeItems(controller);
  final runtimeById = _proxyRuntimeById(controller);
  final completed = outcomes.fold<int>(0, (sum, item) => sum + item.value);
  return _metricInsightPage([
    _InsightKpiBand(
      title: '代理可靠性概览',
      icon: Icons.security_rounded,
      items: [
        _InsightKpi(
          icon: Icons.task_alt_rounded,
          label: '成功率',
          value: _chartRate(outcomes[0].value, completed),
          helper: '${outcomes[0].value}/$completed',
          color: OpenHandStatusColors.success,
        ),
        _InsightKpi(
          icon: Icons.error_outline_rounded,
          label: '失败',
          value: '${outcomes[1].value}',
          helper: '业务请求失败',
          color: OpenHandStatusColors.error,
        ),
        _InsightKpi(
          icon: Icons.timer_off_outlined,
          label: '超时',
          value: '${outcomes[2].value}',
          helper: '业务请求超时',
          color: OpenHandStatusColors.warning,
        ),
        _InsightKpi(
          icon: Icons.pending_outlined,
          label: '执行中',
          value: '${controller.proxyStatus?.inFlight ?? 0}',
          helper: '运行时瞬时值',
          color: OpenHandStatusColors.info,
        ),
      ],
    ),
    _InsightDonutSection(
      title: '已完成请求可靠性',
      icon: Icons.donut_large_rounded,
      items: outcomes,
      detailBuilder: (context, item) => _proxyRequestInsightPanel(
        context,
        controller,
        _ProxyRequestLens.all,
        title: '近期${item.label}请求',
        filter: (_, _, sample) => sample.result == item.key,
      ),
    ),
    _InsightRankingSection(
      title: '节点可靠性排名',
      icon: Icons.leaderboard_outlined,
      items: controller.proxyConfiguration.endpoints.map((endpoint) {
        final stats = _proxyEndpointStatistics(endpoint, runtimeById);
        return _InsightRankItem(
          label: endpoint.displayName,
          value: stats.successRate * 100,
          valueLabel: stats.completed == 0
              ? '暂无样本'
              : '${(stats.successRate * 100).toStringAsFixed(1)}%',
          helper:
              '成功 ${stats.successes} · 失败 ${stats.failures} · 超时 ${stats.timeouts} · 连续失败 ${stats.consecutiveFailures}',
          color: stats.consecutiveFailures > 0
              ? OpenHandStatusColors.error
              : stats.completed == 0
              ? colors.outline
              : OpenHandStatusColors.success,
          target: _ProxyEndpointInsightTarget(endpoint),
        );
      }).toList(),
      emptyLabel: '暂无节点可靠性数据。',
    ),
    _proxyFailureEndpointPanel(context, controller, title: '节点异常诊断'),
    _proxyRequestInsightPanel(
      context,
      controller,
      _ProxyRequestLens.abnormal,
      title: '异常请求样本',
    ),
  ]);
}

Widget _ruleVendorDistributionInsight(
  BuildContext context,
  ServicesController controller,
) {
  final colors = Theme.of(context).colorScheme;
  final enabled = controller.rules.where((rule) => rule.enabled).toList();
  final grouped = <String, List<AiExposureScanRule>>{};
  for (final rule in enabled) {
    final vendor = rule.vendor.trim().isEmpty ? '未标记供应商' : rule.vendor.trim();
    grouped.putIfAbsent(vendor, () => []).add(rule);
  }
  final credentials = enabled.fold<int>(
    0,
    (sum, rule) => sum + rule.credentialPatterns.length,
  );
  final endpoints = enabled.fold<int>(
    0,
    (sum, rule) => sum + rule.modelPaths.length + rule.balancePaths.length,
  );
  final encodings = enabled.expand((rule) => rule.contentEncodings).toSet();
  return _metricInsightPage([
    _InsightKpiBand(
      title: '规则供应商覆盖',
      icon: Icons.rule_folder_outlined,
      items: [
        _InsightKpi(
          icon: Icons.rule_rounded,
          label: '启用规则',
          value: '${enabled.length}',
          helper: '总计 ${controller.rules.length}',
          color: colors.primary,
        ),
        _InsightKpi(
          icon: Icons.business_outlined,
          label: '供应商',
          value: '${grouped.length}',
          helper: '启用规则覆盖',
          color: OpenHandStatusColors.info,
        ),
        _InsightKpi(
          icon: Icons.key_outlined,
          label: '凭证模式',
          value: '$credentials',
          helper: '启用规则累计',
          color: OpenHandStatusColors.success,
        ),
        _InsightKpi(
          icon: Icons.api_outlined,
          label: '验证端点',
          value: '$endpoints',
          helper: '模型与余额端点',
          color: colors.tertiary,
        ),
      ],
    ),
    _InsightDonutSection(
      title: '启用规则供应商占比',
      icon: Icons.category_outlined,
      items: grouped.entries.indexed
          .map(
            (entry) => _DistributionItem(
              entry.$2.key,
              entry.$2.value.length,
              _distributionColor(entry.$1, colors),
              key: entry.$2.key,
            ),
          )
          .toList(),
      detailBuilder: (context, item) => _ruleInsightPanel(
        context,
        grouped[item.key] ?? const <AiExposureScanRule>[],
        title: '${item.label}启用规则',
      ),
    ),
    _InsightMatrixSection(
      title: '供应商规则能力矩阵',
      icon: Icons.grid_view_rounded,
      rows: grouped.entries.indexed.map((entry) {
        final rules = entry.$2.value;
        final patterns = rules.fold<int>(
          0,
          (sum, rule) => sum + rule.credentialPatterns.length,
        );
        final modelPaths = rules.fold<int>(
          0,
          (sum, rule) => sum + rule.modelPaths.length,
        );
        final balancePaths = rules.fold<int>(
          0,
          (sum, rule) => sum + rule.balancePaths.length,
        );
        final vendorEncodings = rules
            .expand((rule) => rule.contentEncodings)
            .toSet();
        return _InsightMatrixRow(
          icon: Icons.business_outlined,
          title: entry.$2.key,
          subtitle: '${rules.length} 条启用规则',
          color: _distributionColor(entry.$1, colors),
          cells: [
            _InsightMatrixCell(
              label: '凭证模式 $patterns',
              color: OpenHandStatusColors.success,
            ),
            _InsightMatrixCell(
              label: '模型端点 $modelPaths',
              color: colors.primary,
            ),
            _InsightMatrixCell(
              label: '余额端点 $balancePaths',
              color: colors.tertiary,
            ),
            _InsightMatrixCell(
              label: vendorEncodings.isEmpty
                  ? '编码未配置'
                  : '编码 ${vendorEncodings.map((encoding) => encoding.id).join(' / ')}',
              color: vendorEncodings.isEmpty
                  ? colors.outline
                  : OpenHandStatusColors.info,
            ),
          ],
        );
      }).toList(),
      emptyLabel: '暂无启用规则。',
    ),
    _Section(
      title: '编码覆盖口径',
      icon: Icons.code_rounded,
      child: Column(
        children: [
          _OpsKeyValue(
            label: '编码类型',
            value: encodings.isEmpty
                ? '启用规则未声明编码'
                : encodings.map((encoding) => encoding.id).join(' / '),
          ),
          _OpsKeyValue(
            label: '协议类型',
            value: enabled
                .map((rule) => rule.protocol)
                .where((protocol) => protocol.trim().isNotEmpty)
                .toSet()
                .join(' / '),
          ),
          _OpsKeyValue(
            label: '上下文词',
            value:
                '${enabled.fold<int>(0, (sum, rule) => sum + rule.contextTerms.length)} 条',
          ),
        ],
      ),
    ),
    _ruleInsightPanel(context, enabled, title: '启用规则能力明细'),
  ]);
}
