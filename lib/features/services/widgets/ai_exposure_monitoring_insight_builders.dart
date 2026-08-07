part of 'ai_exposure_monitoring_dialogs.dart';

Widget _metricInsightPage(List<Widget> sections) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: sections.indexed
      .expand(
        (entry) => [if (entry.$1 > 0) const SizedBox(height: 14), entry.$2],
      )
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
  _MetricInsightId.sourceReady ||
  _MetricInsightId.sourceQuotaAvailable ||
  _MetricInsightId.sourceQuotaRemaining ||
  _MetricInsightId.sourceDiscoveryEnabled ||
  _MetricInsightId.sourceTaskCalls ||
  _MetricInsightId.sourceResults ||
  _MetricInsightId.sourceQuotaAnomalies ||
  _MetricInsightId.sourcePendingConfiguration => _buildSourceMetricInsight(
    context,
    id,
    controller,
  ),
  _MetricInsightId.networkRouteState ||
  _MetricInsightId.networkProxyNodes ||
  _MetricInsightId.networkReachableNodes ||
  _MetricInsightId.networkRequests ||
  _MetricInsightId.networkSuccesses ||
  _MetricInsightId.networkFailures ||
  _MetricInsightId.networkTimeouts ||
  _MetricInsightId.networkAverageLatency ||
  _MetricInsightId.networkP95Latency ||
  _MetricInsightId.networkHttp2xx ||
  _MetricInsightId.networkExitCountries ||
  _MetricInsightId.networkInspectionPlan => _buildNetworkMetricInsight(
    context,
    id,
    controller,
  ),
  _MetricInsightId.storageSqlite ||
  _MetricInsightId.storageLastWrite ||
  _MetricInsightId.storageVisibleRecords ||
  _MetricInsightId.storageTaskArchive ||
  _MetricInsightId.storageResultArchive ||
  _MetricInsightId.storageRuleSnapshots ||
  _MetricInsightId.storageLogBuffer ||
  _MetricInsightId.storageResumable ||
  _MetricInsightId.storagePostgresql ||
  _MetricInsightId.storageRedis ||
  _MetricInsightId.storageCredentialEncryption ||
  _MetricInsightId.storageIntegrity => _buildStorageMetricInsight(
    context,
    id,
    controller,
  ),
  _MetricInsightId.securityEnabledRules ||
  _MetricInsightId.securityCredentialPatterns ||
  _MetricInsightId.securityModelEndpoints ||
  _MetricInsightId.securityEncodings ||
  _MetricInsightId.securityProxyRequests ||
  _MetricInsightId.securityProxySuccess ||
  _MetricInsightId.securityProxyAnomalies ||
  _MetricInsightId.securityDependencies => _buildSecurityMetricInsight(
    context,
    id,
    controller,
  ),
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
}) => controller.history.take(limit).toList().reversed.toList(growable: false);

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
  int taskCount(String stage) =>
      history.where((entry) => entry.stage == stage).length;
  final active = history.where((entry) => !entry.isTerminal).length;

  switch (id) {
    case _MetricInsightId.overviewTaskTotal:
      final completed = taskCount('completed');
      final failed = taskCount('failed');
      final cancelled = taskCount('cancelled');
      final throughput = history.fold<int>(
        0,
        (sum, entry) => sum + entry.progress.processed,
      );
      return _metricInsightPage([
        const AiExposureTaskLedger(),
        _InsightKpiBand(
          title: '任务运行账本',
          icon: Icons.work_history_outlined,
          items: [
            _InsightKpi(
              icon: Icons.task_alt_rounded,
              label: '完成',
              value: '$completed',
              helper: history.isEmpty
                  ? '暂无任务'
                  : '${(completed * 100 / history.length).toStringAsFixed(1)}% 完成率',
              color: OpenHandStatusColors.success,
            ),
            _InsightKpi(
              icon: Icons.pending_actions_rounded,
              label: '运行中',
              value: '$active',
              helper: '服务当前活动任务',
              color: OpenHandStatusColors.info,
            ),
            _InsightKpi(
              icon: Icons.error_outline_rounded,
              label: '失败',
              value: '$failed',
              helper: '可进入恢复检查',
              color: OpenHandStatusColors.error,
            ),
            _InsightKpi(
              icon: Icons.radar_rounded,
              label: '累计处理',
              value: '$throughput',
              helper: '跨全部任务汇总',
              color: colors.primary,
            ),
          ],
        ),
        _InsightRankingSection(
          title: '任务终态规模',
          icon: Icons.account_tree_outlined,
          items: [
            _InsightRankItem(
              label: '完成',
              value: completed.toDouble(),
              valueLabel: '$completed',
              color: OpenHandStatusColors.success,
              target: completed == 0
                  ? null
                  : const _TaskCollectionInsightTarget(
                      status: 'completed',
                      title: '完成任务',
                    ),
            ),
            _InsightRankItem(
              label: '失败',
              value: failed.toDouble(),
              valueLabel: '$failed',
              color: OpenHandStatusColors.error,
              target: failed == 0
                  ? null
                  : const _TaskCollectionInsightTarget(
                      status: 'failed',
                      title: '失败任务',
                    ),
            ),
            _InsightRankItem(
              label: '取消',
              value: cancelled.toDouble(),
              valueLabel: '$cancelled',
              color: OpenHandStatusColors.warning,
              target: cancelled == 0
                  ? null
                  : const _TaskCollectionInsightTarget(
                      status: 'cancelled',
                      title: '取消任务',
                    ),
            ),
            _InsightRankItem(
              label: '运行中',
              value: active.toDouble(),
              valueLabel: '$active',
              color: OpenHandStatusColors.info,
              target: active == 0
                  ? null
                  : const _TaskCollectionInsightTarget(
                      status: 'running',
                      title: '运行中任务',
                    ),
            ),
          ],
          emptyLabel: '暂无任务状态数据。',
        ),
      ]);
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
                  label: _sourceName(entry.key),
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
                  color: const Color(0xffa855f7),
                  target: _ResultInsightTarget(result),
                  cells: [
                    _InsightMatrixCell(
                      label: _sourceName(result.source),
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
              color: const Color(0xffa855f7),
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
              .map((entry) => _shortDateTime(entry.createdAt))
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
              .map((entry) => _shortDateTime(entry.createdAt))
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
                  label: entry.name.trim().isEmpty ? entry.id : entry.name,
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
          .where((entry) => _taskDurationMs(entry) != null)
          .toList(growable: false);
      final durations =
          finished.map((entry) => _taskDurationMs(entry)!).toList()..sort();
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
            (left, right) =>
                _taskDurationMs(right)!.compareTo(_taskDurationMs(left)!),
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
              .map((sample) => _shortDateTime(sample.at))
              .toList(growable: false),
          suffix: ' ms',
          emptyLabel: '暂无代理请求时延样本',
          interpolation: OpenHandChartInterpolation.smooth,
          targets: _proxyTargetsForSamples(controller, samples),
        ),
        _proxyFleetLatencyPanel(context, controller),
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
                  : _shortDateTime(progress.updatedAt),
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
              .map((entry) => _shortDateTime(entry.createdAt))
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
                  label: entry.name.trim().isEmpty ? entry.id : entry.name,
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
              .map((entry) => _shortDateTime(entry.createdAt))
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
              color: const Color(0xffa855f7),
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
          maximum: 128,
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
              value: '1 - 128',
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
                  title: entry.name.trim().isEmpty ? entry.id : entry.name,
                  subtitle: entry.authorizedScope.isEmpty
                      ? '未记录授权范围'
                      : entry.authorizedScope.join(' · '),
                  color: const Color(0xff0891b2),
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
                  title: entry.name.trim().isEmpty ? entry.id : entry.name,
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
                      label: '检查点 ${_shortDateTime(entry.progress.updatedAt)}',
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
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    clusters.putIfAbsent(key, () => <AiExposureLogEntry>[]).add(entry);
  }
  final hourCounts = <String, int>{};
  for (final entry in entries) {
    final key =
        '${entry.at.month.toString().padLeft(2, '0')}-${entry.at.day.toString().padLeft(2, '0')} '
        '${entry.at.hour.toString().padLeft(2, '0')}:00';
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
                  '${entry.at.month.toString().padLeft(2, '0')}-${entry.at.day.toString().padLeft(2, '0')} '
                  '${entry.at.hour.toString().padLeft(2, '0')}:00';
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

class _SourceReadinessSection extends StatelessWidget {
  const _SourceReadinessSection({required this.states});

  final List<_SourceInsightState> states;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _Section(
      title: '来源执行依赖链',
      icon: Icons.schema_outlined,
      child: states.isEmpty
          ? const _InsightEmpty(label: '暂无来源就绪数据。')
          : Column(
              children: states.indexed
                  .map((entry) {
                    return Column(
                      children: [
                        if (entry.$1 > 0)
                          Divider(
                            height: 20,
                            color: colors.outlineVariant.withValues(alpha: 0.5),
                          ),
                        _SourceReadinessRow(state: entry.$2),
                      ],
                    );
                  })
                  .toList(growable: false),
            ),
    );
  }
}

class _SourceReadinessRow extends StatelessWidget {
  const _SourceReadinessRow({required this.state});

  final _SourceInsightState state;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final quotaReady = state.quota == null || state.quota!.available;
    final checkpoints = <(String, bool, String)>[
      ('访问前置', state.configured, state.requiresCredential ? '凭证' : '免凭证'),
      ('任务启用', state.enabled, state.enabled ? '启用' : '停用'),
      (
        '配额检查',
        quotaReady,
        state.quota == null
            ? '无需计量'
            : state.quota!.available
            ? '可用'
            : '异常',
      ),
    ];
    final identity = Row(
      children: [
        Icon(
          _sourceIcon(state.source),
          size: 19,
          color: _sourceColor(state.source, colors),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _sourceName(state.source),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        _StatusPill(
          icon: state.ready ? Icons.check_circle_rounded : Icons.block_rounded,
          label: state.ready ? '就绪' : '阻塞',
          color: state.ready
              ? OpenHandStatusColors.success
              : OpenHandStatusColors.warning,
        ),
      ],
    );
    final checkpointWidgets = checkpoints
        .map(
          (checkpoint) => Container(
            constraints: const BoxConstraints(minWidth: 108),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              color:
                  (checkpoint.$2
                          ? OpenHandStatusColors.success
                          : OpenHandStatusColors.warning)
                      .withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color:
                    (checkpoint.$2
                            ? OpenHandStatusColors.success
                            : OpenHandStatusColors.warning)
                        .withValues(alpha: 0.26),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  checkpoint.$1,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  checkpoint.$3,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: checkpoint.$2
                        ? OpenHandStatusColors.success
                        : OpenHandStatusColors.warning,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        )
        .toList(growable: false);
    final blocker = !state.ready
        ? Text(
            !state.configured
                ? '阻塞原因：访问凭证尚未配置。'
                : state.quota?.message.trim().isNotEmpty == true
                ? '阻塞原因：${state.quota!.message.trim()}'
                : '阻塞原因：实时配额检查未通过。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: OpenHandStatusColors.warning,
            ),
          )
        : null;
    return ServiceInteractiveSurface(
      padding: const EdgeInsets.all(4),
      tooltip: '查看来源依赖详情',
      onTap: () => _showSourceEntityInsight(context, state.source),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 720) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                const SizedBox(height: 9),
                Wrap(spacing: 6, runSpacing: 6, children: checkpointWidgets),
                if (blocker != null) ...[const SizedBox(height: 6), blocker],
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 190, child: identity),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: checkpointWidgets.indexed
                          .expand(
                            (entry) => [
                              if (entry.$1 > 0)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                  ),
                                  child: Icon(
                                    Icons.chevron_right_rounded,
                                    size: 18,
                                    color: colors.outline,
                                  ),
                                ),
                              Expanded(child: entry.$2),
                            ],
                          )
                          .toList(growable: false),
                    ),
                    if (blocker != null) ...[
                      const SizedBox(height: 6),
                      blocker,
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _QuotaCapacitySection extends StatelessWidget {
  const _QuotaCapacitySection({required this.title, required this.states});

  final String title;
  final List<_SourceInsightState> states;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _Section(
      title: title,
      icon: Icons.data_usage_rounded,
      child: states.isEmpty
          ? const _InsightEmpty(label: '暂无可计量配额数据。')
          : Column(
              children: states.indexed
                  .map((entry) {
                    final state = entry.$2;
                    final quota = state.quota!;
                    final remaining = quota.remaining;
                    final limit = quota.limit;
                    final fraction =
                        remaining == null || limit == null || limit <= 0
                        ? null
                        : (remaining / limit).clamp(0.0, 1.0);
                    final tone = !quota.available
                        ? OpenHandStatusColors.error
                        : fraction != null && fraction <= 0.15
                        ? OpenHandStatusColors.warning
                        : OpenHandStatusColors.success;
                    final identity = Row(
                      children: [
                        Icon(
                          _sourceIcon(state.source),
                          size: 20,
                          color: _sourceColor(state.source, colors),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            _sourceName(state.source),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        Text(
                          remaining == null
                              ? quota.available
                                    ? '可用'
                                    : '不可用'
                              : '$remaining${limit == null ? '' : ' / $limit'}',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: tone,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ],
                    );
                    final capacity = fraction == null
                        ? Text(
                            quota.available ? '配额可用，服务未返回计量上限' : '配额不可用',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colors.onSurfaceVariant),
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: ServiceAnimatedProgressBar(
                              value: fraction,
                              minHeight: 10,
                              color: tone,
                              backgroundColor: tone.withValues(alpha: 0.1),
                            ),
                          );
                    final resetLabel = quota.resetsAt == null
                        ? '重置时间 --'
                        : '重置 ${_shortDateTime(quota.resetsAt!)}';
                    return Column(
                      children: [
                        if (entry.$1 > 0)
                          Divider(
                            height: 20,
                            color: colors.outlineVariant.withValues(alpha: 0.5),
                          ),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final message = Text(
                              quota.message.trim().isEmpty
                                  ? '实时配额探测已完成'
                                  : quota.message.trim(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            );
                            if (constraints.maxWidth < 620) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  identity,
                                  const SizedBox(height: 8),
                                  capacity,
                                  const SizedBox(height: 6),
                                  message,
                                  const SizedBox(height: 3),
                                  Text(
                                    resetLabel,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                                ],
                              );
                            }
                            return Column(
                              children: [
                                Row(
                                  children: [
                                    SizedBox(width: 250, child: identity),
                                    const SizedBox(width: 12),
                                    Expanded(child: capacity),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Row(
                                  children: [
                                    const SizedBox(width: 262),
                                    Expanded(child: message),
                                    const SizedBox(width: 12),
                                    Text(
                                      resetLabel,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelSmall,
                                    ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    );
                  })
                  .toList(growable: false),
            ),
    );
  }
}

Widget _buildSourceConfigurationInsight(
  BuildContext context,
  ServicesController controller,
) {
  final colors = Theme.of(context).colorScheme;
  final states = _sourceInsightStates(controller);
  final credentialSources = states.where((state) => state.requiresCredential);
  final configured = credentialSources
      .where((state) => state.configured)
      .length;
  final gaps = credentialSources
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
              icon: _sourceIcon(state.source),
              title: _sourceName(state.source),
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
              title: _sourceName(state.source),
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

Widget _buildSourceMetricInsight(
  BuildContext context,
  _MetricInsightId id,
  ServicesController controller,
) {
  final colors = Theme.of(context).colorScheme;
  final states = _sourceInsightStates(controller);
  switch (id) {
    case _MetricInsightId.sourceReady:
      final blocked = states.where((state) => !state.ready).toList();
      return _metricInsightPage([
        _SourceReadinessSection(states: states),
        _InsightMatrixSection(
          title: '阻塞原因与处置',
          icon: Icons.report_problem_outlined,
          rows: blocked
              .map(
                (state) => _InsightMatrixRow(
                  icon: Icons.block_rounded,
                  title: _sourceName(state.source),
                  subtitle: !state.configured
                      ? '访问凭证未满足，来源无法进入执行链。'
                      : state.quota?.message.trim().isNotEmpty == true
                      ? state.quota!.message.trim()
                      : '实时配额检查未通过。',
                  color: OpenHandStatusColors.warning,
                  target: _SourceInsightTarget(state.source),
                  cells: [
                    if (!state.configured)
                      const _InsightMatrixCell(
                        label: '补齐凭证',
                        color: OpenHandStatusColors.warning,
                      ),
                    if (state.quota != null && !state.quota!.available)
                      const _InsightMatrixCell(
                        label: '检查配额或网络',
                        color: OpenHandStatusColors.error,
                      ),
                    _InsightMatrixCell(
                      label: state.enabled ? '任务已启用' : '任务未启用',
                      color: state.enabled ? colors.primary : colors.outline,
                    ),
                  ],
                ),
              )
              .toList(growable: false),
          emptyLabel: '全部来源执行前置均已就绪。',
        ),
      ]);
    case _MetricInsightId.sourceQuotaAvailable:
      final metered = states
          .where((state) => state.quota?.configured == true)
          .toList(growable: false);
      final resetEntries =
          metered
              .where((state) => state.quota?.resetsAt != null)
              .map(
                (state) => _InsightTimelineEntry(
                  at: state.quota!.resetsAt!,
                  title: '${_sourceName(state.source)} 配额重置',
                  detail:
                      '当前剩余 ${state.quota!.remaining ?? '--'}${state.quota!.limit == null ? '' : ' / ${state.quota!.limit}'}',
                  tag: state.quota!.available ? '可用' : '阻塞',
                  color: state.quota!.available
                      ? OpenHandStatusColors.success
                      : OpenHandStatusColors.error,
                  target: _SourceInsightTarget(state.source),
                ),
              )
              .toList(growable: false)
            ..sort((left, right) => left.at.compareTo(right.at));
      return _metricInsightPage([
        _QuotaCapacitySection(title: '实时配额容量', states: metered),
        _InsightRankingSection(
          title: '配额消耗风险排名',
          icon: Icons.low_priority_rounded,
          items: metered
              .map((state) {
                final quota = state.quota!;
                final remaining = quota.remaining;
                final limit = quota.limit;
                final consumed =
                    remaining == null || limit == null || limit <= 0
                    ? 0.0
                    : ((limit - remaining).clamp(0, limit) / limit);
                return _InsightRankItem(
                  label: _sourceName(state.source),
                  value: quota.available ? consumed : 1,
                  valueLabel: !quota.available
                      ? '不可用'
                      : remaining == null
                      ? '可用'
                      : '$remaining${limit == null ? '' : ' / $limit'}',
                  helper: quota.message.trim(),
                  color: !quota.available || consumed >= 0.85
                      ? OpenHandStatusColors.error
                      : consumed >= 0.65
                      ? OpenHandStatusColors.warning
                      : OpenHandStatusColors.success,
                  target: _SourceInsightTarget(state.source),
                );
              })
              .toList(growable: false),
          emptyLabel: '暂无实时配额探测结果。',
        ),
        _InsightTimelineSection(
          title: '配额重置日程',
          icon: Icons.event_repeat_rounded,
          entries: resetEntries,
          emptyLabel: '服务未返回配额重置时间。',
        ),
      ]);
    case _MetricInsightId.sourceQuotaRemaining:
      final metered = states
          .where((state) => state.quota?.remaining != null)
          .toList(growable: false);
      return _metricInsightPage([
        _QuotaCapacitySection(title: '来源剩余配额', states: metered),
        _InsightRankingSection(
          title: '绝对剩余额度排名',
          icon: Icons.leaderboard_outlined,
          items: metered
              .map(
                (state) => _InsightRankItem(
                  label: _sourceName(state.source),
                  value: state.quota!.remaining!.toDouble(),
                  valueLabel:
                      '${state.quota!.remaining}${state.quota!.limit == null ? '' : ' / ${state.quota!.limit}'}',
                  helper: state.quota!.resetsAt == null
                      ? '未返回重置时间'
                      : '重置 ${_shortDateTime(state.quota!.resetsAt!)}',
                  color: _sourceColor(state.source, colors),
                  target: _SourceInsightTarget(state.source),
                ),
              )
              .toList(growable: false),
          emptyLabel: '暂无剩余配额计量值。',
        ),
      ]);
    case _MetricInsightId.sourceDiscoveryEnabled:
      return _metricInsightPage([
        _InsightMatrixSection(
          title: '发现源启用矩阵',
          icon: Icons.travel_explore_rounded,
          rows: states
              .map(
                (state) => _InsightMatrixRow(
                  icon: _sourceIcon(state.source),
                  title: _sourceName(state.source),
                  subtitle: state.enabled ? '新建任务默认可选择该来源。' : '该来源未纳入当前默认发现范围。',
                  color: _sourceColor(state.source, colors),
                  target: _SourceInsightTarget(state.source),
                  cells: [
                    _InsightMatrixCell(
                      label: state.enabled ? '已启用' : '未启用',
                      color: state.enabled ? colors.primary : colors.outline,
                    ),
                    _InsightMatrixCell(
                      label: state.requiresCredential ? '凭证来源' : '公开来源',
                      color: state.requiresCredential
                          ? colors.tertiary
                          : OpenHandStatusColors.info,
                    ),
                    _InsightMatrixCell(
                      label: '历史调用 ${state.taskCount}',
                      color: state.taskCount > 0
                          ? OpenHandStatusColors.success
                          : colors.outline,
                    ),
                  ],
                ),
              )
              .toList(growable: false),
          emptyLabel: '暂无发现源配置。',
        ),
      ]);
    case _MetricInsightId.sourceTaskCalls:
      final called = states.where((state) => state.taskCount > 0).toList();
      return _metricInsightPage([
        _InsightRankingSection(
          title: '来源任务调用排名',
          icon: Icons.hub_outlined,
          items: called
              .map(
                (state) => _InsightRankItem(
                  label: _sourceName(state.source),
                  value: state.taskCount.toDouble(),
                  valueLabel: '${state.taskCount} 个任务',
                  helper: '产出 ${state.resultCount} 条结果',
                  color: _sourceColor(state.source, colors),
                  target: _SourceInsightTarget(state.source),
                ),
              )
              .toList(growable: false),
          emptyLabel: '暂无来源调用任务。',
        ),
        _metricTaskPanel(
          controller.history.where((entry) => entry.sources.isNotEmpty),
          title: '任务来源编排明细',
          emptyLabel: '暂无来源调用任务。',
          lens: _TaskRecordLens.scope,
        ),
      ]);
    case _MetricInsightId.sourceResults:
      final produced = states.where((state) => state.resultCount > 0).toList();
      return _metricInsightPage([
        _InsightRankingSection(
          title: '来源结果产出排名',
          icon: Icons.fact_check_outlined,
          items: produced
              .map(
                (state) => _InsightRankItem(
                  label: _sourceName(state.source),
                  value: state.resultCount.toDouble(),
                  valueLabel: '${state.resultCount} 条',
                  helper: state.taskCount <= 0
                      ? '无可关联的任务调用'
                      : '每任务 ${(state.resultCount / state.taskCount).toStringAsFixed(1)} 条',
                  color: _sourceColor(state.source, colors),
                  target: _SourceInsightTarget(state.source),
                ),
              )
              .toList(growable: false),
          emptyLabel: '暂无来源产出结果。',
        ),
        _metricResultPanel(
          controller.results,
          title: '来源产出证据明细',
          emptyLabel: '暂无来源产出结果。',
          lens: _ResultRecordLens.source,
        ),
      ]);
    case _MetricInsightId.sourceQuotaAnomalies:
      final abnormal = states
          .where(
            (state) =>
                state.quota?.configured == true &&
                state.quota?.available == false,
          )
          .toList(growable: false);
      return _metricInsightPage([
        _InsightMatrixSection(
          title: '配额异常诊断',
          icon: Icons.warning_amber_rounded,
          rows: abnormal
              .map(
                (state) => _InsightMatrixRow(
                  icon: Icons.report_gmailerrorred_rounded,
                  title: _sourceName(state.source),
                  subtitle: state.quota!.message.trim().isEmpty
                      ? '实时配额探测未通过，服务未返回详细原因。'
                      : state.quota!.message.trim(),
                  color: OpenHandStatusColors.error,
                  target: _SourceInsightTarget(state.source),
                  cells: [
                    _InsightMatrixCell(
                      label: state.configured ? '凭证已配置' : '凭证缺失',
                      color: state.configured
                          ? OpenHandStatusColors.success
                          : OpenHandStatusColors.warning,
                    ),
                    _InsightMatrixCell(
                      label: state.enabled ? '任务已启用' : '任务未启用',
                      color: state.enabled ? colors.primary : colors.outline,
                    ),
                    if (state.quota!.resetsAt != null)
                      _InsightMatrixCell(
                        label: '重置 ${_shortDateTime(state.quota!.resetsAt!)}',
                        color: colors.tertiary,
                      ),
                  ],
                ),
              )
              .toList(growable: false),
          emptyLabel: '实时配额探测未发现异常。',
        ),
      ]);
    case _MetricInsightId.sourcePendingConfiguration:
      final gaps = states
          .where((state) => state.requiresCredential && !state.configured)
          .toList(growable: false);
      return _metricInsightPage([
        _InsightKpiBand(
          title: '来源配置缺口',
          icon: Icons.key_off_outlined,
          items: [
            _InsightKpi(
              icon: Icons.key_off_outlined,
              label: '待配置',
              value: '${gaps.length}',
              helper: '需要补齐访问凭证',
              color: gaps.isEmpty
                  ? OpenHandStatusColors.success
                  : OpenHandStatusColors.warning,
            ),
            _InsightKpi(
              icon: Icons.power_settings_new_rounded,
              label: '已启用但缺失',
              value: '${gaps.where((state) => state.enabled).length}',
              helper: '会影响任务来源可用性',
              color: OpenHandStatusColors.error,
            ),
            _InsightKpi(
              icon: Icons.public_rounded,
              label: '公开来源',
              value:
                  '${states.where((state) => !state.requiresCredential).length}',
              helper: '无需配置 API 凭证',
              color: OpenHandStatusColors.info,
            ),
          ],
        ),
        _InsightMatrixSection(
          title: '凭证补齐清单',
          icon: Icons.playlist_add_check_circle_outlined,
          rows: gaps
              .map(
                (state) => _InsightMatrixRow(
                  icon: _sourceIcon(state.source),
                  title: _sourceName(state.source),
                  subtitle: '进入服务设置补齐该来源凭证，然后刷新服务状态与实时配额。',
                  color: OpenHandStatusColors.warning,
                  target: _SourceInsightTarget(state.source),
                  cells: [
                    const _InsightMatrixCell(
                      label: '凭证未配置',
                      color: OpenHandStatusColors.warning,
                    ),
                    _InsightMatrixCell(
                      label: state.enabled ? '优先处理' : '未启用',
                      color: state.enabled
                          ? OpenHandStatusColors.error
                          : colors.outline,
                    ),
                  ],
                ),
              )
              .toList(growable: false),
          emptyLabel: '所有需要凭证的来源均已配置。',
        ),
      ]);
    default:
      throw StateError('指标 ID 分派到了错误的运维分组：$id');
  }
}

Widget _buildNetworkMetricInsight(
  BuildContext context,
  _MetricInsightId id,
  ServicesController controller,
) {
  final colors = Theme.of(context).colorScheme;
  final endpoints = controller.proxyConfiguration.endpoints;
  final runtimeById = _proxyRuntimeById(controller);
  final statistics = {
    for (final endpoint in endpoints)
      endpoint: _proxyEndpointStatistics(endpoint, runtimeById),
  };
  int sum(int Function(AiExposureProxyUsageStatistics value) select) =>
      statistics.values.fold<int>(0, (total, value) => total + select(value));
  final requests = sum((value) => value.requests);
  final successes = sum((value) => value.successes);
  final failures = sum((value) => value.failures);
  final timeouts = sum((value) => value.timeouts);
  final completed = successes + failures + timeouts;
  final samples = _proxyRequestSamples(controller);
  final latencies = samples.map((sample) => sample.responseTimeMs).toList()
    ..sort();
  final average = completed <= 0
      ? 0
      : (sum((value) => value.totalResponseTimeMs) / completed).round();
  final p95 = _latencyPercentile(latencies, 0.95);

  switch (id) {
    case _MetricInsightId.networkRouteState:
      return _metricInsightPage([
        _proxyRouteReadinessPanel(context, controller),
        _proxyPolicySection(context, controller),
        _proxyRoutingDecisionPanel(context, controller),
      ]);
    case _MetricInsightId.networkProxyNodes:
      return _metricInsightPage([
        _proxyFleetWorkbench(context, controller),
        if (endpoints.isNotEmpty) _proxyRequestLoadPanel(context, controller),
      ]);
    case _MetricInsightId.networkReachableNodes:
      return _metricInsightPage([
        _proxyReachabilityWorkbench(context, controller),
        if (endpoints.isNotEmpty)
          _proxyInspectionEventPanel(context, controller),
      ]);
    case _MetricInsightId.networkRequests:
      return _metricInsightPage([
        _InsightKpiBand(
          title: '请求负载总览',
          icon: Icons.swap_vert_rounded,
          items: [
            _InsightKpi(
              icon: Icons.swap_vert_rounded,
              label: '累计请求',
              value: '$requests',
              helper: '全部代理节点汇总',
              color: colors.primary,
            ),
            _InsightKpi(
              icon: Icons.task_alt_rounded,
              label: '已完成',
              value: '$completed',
              helper: '成功、失败与超时',
              color: OpenHandStatusColors.info,
            ),
            _InsightKpi(
              icon: Icons.pending_actions_rounded,
              label: '执行中',
              value: '${controller.proxyStatus?.inFlight ?? 0}',
              helper: '服务运行时实测值',
              color: colors.tertiary,
            ),
          ],
        ),
        _InsightDonutSection(
          title: '请求结果构成',
          icon: Icons.donut_small_rounded,
          items: [
            _DistributionItem(
              '成功',
              successes,
              OpenHandStatusColors.success,
              key: _ProxyRequestLens.success,
            ),
            _DistributionItem(
              '失败',
              failures,
              OpenHandStatusColors.error,
              key: _ProxyRequestLens.failure,
            ),
            _DistributionItem(
              '超时',
              timeouts,
              OpenHandStatusColors.warning,
              key: _ProxyRequestLens.timeout,
            ),
          ],
          detailBuilder: (context, item) {
            final lens = item.key! as _ProxyRequestLens;
            return _proxyRequestInsightPanel(
              context,
              controller,
              lens,
              title: '${item.label}请求样本',
            );
          },
        ),
        _proxyRequestLoadPanel(context, controller),
      ]);
    case _MetricInsightId.networkSuccesses:
      final successSamples = samples
          .where((sample) => sample.succeeded)
          .toList(growable: false);
      return _metricInsightPage([
        _InsightKpiBand(
          title: '成功请求质量',
          icon: Icons.check_circle_outline_rounded,
          items: [
            _InsightKpi(
              icon: Icons.task_alt_rounded,
              label: '成功总数',
              value: '$successes',
              helper: completed <= 0
                  ? '暂无完成请求'
                  : '${(successes * 100 / completed).toStringAsFixed(1)}% 成功率',
              color: OpenHandStatusColors.success,
            ),
            _InsightKpi(
              icon: Icons.http_rounded,
              label: 'HTTP 2xx',
              value: '${sum((value) => value.status2xx)}',
              helper: '成功状态码累计',
              color: OpenHandStatusColors.info,
            ),
            _InsightKpi(
              icon: Icons.speed_rounded,
              label: '近期 p50',
              value:
                  '${_latencyPercentile(successSamples.map((entry) => entry.responseTimeMs).toList(), 0.5)} ms',
              helper: '${successSamples.length} 个成功样本',
              color: colors.primary,
            ),
          ],
        ),
        _InsightTrendSection(
          title: '成功请求响应曲线',
          icon: Icons.show_chart_rounded,
          series: [
            OpenHandChartSeries(
              label: '成功时延',
              values: successSamples
                  .map((entry) => entry.responseTimeMs.toDouble())
                  .toList(growable: false),
              color: OpenHandStatusColors.success,
            ),
          ],
          sampleLabels: successSamples
              .map((entry) => _shortDateTime(entry.at))
              .toList(growable: false),
          suffix: ' ms',
          emptyLabel: '暂无成功请求样本',
          interpolation: OpenHandChartInterpolation.smooth,
          targets: _proxyTargetsForSamples(controller, successSamples),
        ),
        _proxySuccessEndpointAuditPanel(context, controller),
      ]);
    case _MetricInsightId.networkFailures:
      return _metricInsightPage([
        _InsightRankingSection(
          title: '失败节点排名',
          icon: Icons.report_problem_outlined,
          items: endpoints
              .where((entry) => statistics[entry]!.failures > 0)
              .map(
                (entry) => _InsightRankItem(
                  label: entry.displayName,
                  value: statistics[entry]!.failures.toDouble(),
                  valueLabel: '${statistics[entry]!.failures} 次',
                  helper:
                      '连续失败 ${statistics[entry]!.consecutiveFailures} · 最近 ${statistics[entry]!.lastFailureAt == null ? '--' : _shortDateTime(statistics[entry]!.lastFailureAt!)}',
                  color: OpenHandStatusColors.error,
                  target: _ProxyEndpointInsightTarget(entry),
                ),
              )
              .toList(growable: false),
          emptyLabel: '暂无失败代理节点。',
        ),
        _proxyFailureEndpointPanel(context, controller),
        _proxyRequestInsightPanel(
          context,
          controller,
          _ProxyRequestLens.failure,
          title: '失败请求事件',
        ),
      ]);
    case _MetricInsightId.networkTimeouts:
      return _metricInsightPage([
        _InsightRankingSection(
          title: '节点超时压力',
          icon: Icons.timer_off_outlined,
          items: endpoints
              .where((entry) => statistics[entry]!.timeouts > 0)
              .map(
                (entry) => _InsightRankItem(
                  label: entry.displayName,
                  value: statistics[entry]!.timeouts.toDouble(),
                  valueLabel: '${statistics[entry]!.timeouts} 次',
                  helper:
                      '累计请求 ${statistics[entry]!.requests} · 最长 ${statistics[entry]!.maxResponseTimeMs} ms',
                  color: OpenHandStatusColors.warning,
                  target: _ProxyEndpointInsightTarget(entry),
                ),
              )
              .toList(growable: false),
          emptyLabel: '暂无超时节点。',
        ),
        _proxyRequestInsightPanel(
          context,
          controller,
          _ProxyRequestLens.timeout,
          title: '超时请求时间线',
        ),
      ]);
    case _MetricInsightId.networkAverageLatency:
      return _metricInsightPage([
        _InsightKpiBand(
          title: '响应时延统计',
          icon: Icons.speed_rounded,
          items: [
            _InsightKpi(
              icon: Icons.speed_rounded,
              label: '累计平均',
              value: '$average ms',
              helper: '$completed 个完成请求',
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
              icon: Icons.vertical_align_top_rounded,
              label: '近期峰值',
              value: '${latencies.isEmpty ? 0 : latencies.last} ms',
              helper: '有限请求窗口峰值',
              color: colors.tertiary,
            ),
          ],
        ),
        _InsightTrendSection(
          title: '响应时延曲线',
          icon: Icons.multiline_chart_rounded,
          series: [
            OpenHandChartSeries(
              label: '响应耗时',
              values: samples
                  .map((entry) => entry.responseTimeMs.toDouble())
                  .toList(growable: false),
              color: colors.secondary,
            ),
          ],
          sampleLabels: samples
              .map((entry) => _shortDateTime(entry.at))
              .toList(growable: false),
          suffix: ' ms',
          emptyLabel: '暂无请求时延样本',
          interpolation: OpenHandChartInterpolation.smooth,
          targets: _proxyTargetsForSamples(controller, samples),
        ),
        _proxyLatencyQualityPanel(context, controller),
      ]);
    case _MetricInsightId.networkP95Latency:
      final p50 = _latencyPercentile(latencies, 0.5);
      final peak = latencies.isEmpty ? 0 : latencies.last;
      return _metricInsightPage([
        _proxyLatencyRulerSection(
          context,
          sampleCount: samples.length,
          p50: p50,
          p95: p95,
          peak: peak,
        ),
        if (samples.isNotEmpty) ...[
          _InsightTrendSection(
            title: '长尾响应与 p95 基线',
            icon: Icons.stacked_line_chart_rounded,
            series: [
              OpenHandChartSeries(
                label: '响应耗时',
                values: samples
                    .map((entry) => entry.responseTimeMs.toDouble())
                    .toList(growable: false),
                color: colors.tertiary,
              ),
              OpenHandChartSeries(
                label: 'p95 基线',
                values: List<double>.filled(samples.length, p95.toDouble()),
                color: OpenHandStatusColors.warning,
              ),
            ],
            sampleLabels: samples
                .map((entry) => _shortDateTime(entry.at))
                .toList(growable: false),
            suffix: ' ms',
            emptyLabel: '暂无长尾响应样本',
            interpolation: OpenHandChartInterpolation.smooth,
            targets: _proxyTargetsForSamples(controller, samples),
          ),
          _proxyTailLatencyPanel(context, controller),
        ],
      ]);
    case _MetricInsightId.networkHttp2xx:
      final status2xx = sum((value) => value.status2xx);
      final status3xx = sum((value) => value.status3xx);
      final status4xx = sum((value) => value.status4xx);
      final status5xx = sum((value) => value.status5xx);
      return _metricInsightPage([
        _InsightDonutSection(
          title: 'HTTP 状态码族构成',
          icon: Icons.http_rounded,
          items: [
            _DistributionItem(
              '2xx',
              status2xx,
              OpenHandStatusColors.success,
              key: 2,
            ),
            _DistributionItem(
              '3xx',
              status3xx,
              OpenHandStatusColors.info,
              key: 3,
            ),
            _DistributionItem(
              '4xx',
              status4xx,
              OpenHandStatusColors.warning,
              key: 4,
            ),
            _DistributionItem(
              '5xx',
              status5xx,
              OpenHandStatusColors.error,
              key: 5,
            ),
          ],
          detailBuilder: (context, item) => _proxyRequestInsightPanel(
            context,
            controller,
            _ProxyRequestLens.http,
            title: '近期 ${item.label} 请求',
            filter: (_, _, sample) =>
                sample.statusCode != null &&
                sample.statusCode! ~/ 100 == item.key,
          ),
        ),
        _InsightMatrixSection(
          title: '节点 HTTP 响应矩阵',
          icon: Icons.grid_view_rounded,
          rows: endpoints
              .map(
                (entry) => _InsightMatrixRow(
                  icon: Icons.http_rounded,
                  title: entry.displayName,
                  subtitle: entry.maskedUrl,
                  color: _sourceColor(AiExposureSource.manual, colors),
                  target: _ProxyEndpointInsightTarget(entry),
                  cells: [
                    _InsightMatrixCell(
                      label: '2xx ${statistics[entry]!.status2xx}',
                      color: OpenHandStatusColors.success,
                    ),
                    _InsightMatrixCell(
                      label: '3xx ${statistics[entry]!.status3xx}',
                      color: OpenHandStatusColors.info,
                    ),
                    _InsightMatrixCell(
                      label: '4xx ${statistics[entry]!.status4xx}',
                      color: OpenHandStatusColors.warning,
                    ),
                    _InsightMatrixCell(
                      label: '5xx ${statistics[entry]!.status5xx}',
                      color: OpenHandStatusColors.error,
                    ),
                  ],
                ),
              )
              .toList(growable: false),
          emptyLabel: '暂无节点 HTTP 响应数据。',
        ),
        _proxyRequestInsightPanel(
          context,
          controller,
          _ProxyRequestLens.http,
          title: 'HTTP 请求样本',
        ),
      ]);
    case _MetricInsightId.networkExitCountries:
      final countryCounts = <String, int>{};
      for (final endpoint in endpoints) {
        final country = endpoint.identity?.country.trim() ?? '';
        if (country.isEmpty) continue;
        countryCounts.update(country, (value) => value + 1, ifAbsent: () => 1);
      }
      return _metricInsightPage([
        _InsightRankingSection(
          title: '代理出口地域排名',
          icon: Icons.public_rounded,
          items: countryCounts.entries
              .map(
                (entry) => _InsightRankItem(
                  label: entry.key,
                  value: entry.value.toDouble(),
                  valueLabel: '${entry.value} 个节点',
                  color: const Color(0xff0891b2),
                ),
              )
              .toList(growable: false),
          emptyLabel: '暂无已识别出口地域。',
        ),
        _proxyExitIdentityPanel(context, controller),
      ]);
    case _MetricInsightId.networkInspectionPlan:
      return _metricInsightPage([
        _proxyInspectionPolicySection(context, controller),
        _proxyInspectionEventPanel(context, controller),
        _proxyReachabilityWorkbench(context, controller),
      ]);
    default:
      throw StateError('指标 ID 分派到了错误的运维分组：$id');
  }
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
  final chronological = _chronologicalTasks(controller);
  final dependencies = controller.dependencyStatus;

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
        ...history.map(
          (entry) => (
            at: entry.effectiveFinishedAt ?? entry.createdAt,
            target: _TaskInsightTarget(entry) as _InsightTarget,
          ),
        ),
        ...results.map(
          (entry) => (
            at: entry.createdAt,
            target: _ResultInsightTarget(entry) as _InsightTarget,
          ),
        ),
        ...logs.map(
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
    case _MetricInsightId.storageVisibleRecords:
      return _metricInsightPage([
        _InsightDonutSection(
          title: '可见记录类型构成',
          icon: Icons.inventory_2_outlined,
          items: [
            _DistributionItem(
              '任务',
              history.length,
              colors.primary,
              key: _DistributionRecordType.task,
            ),
            _DistributionItem(
              '结果',
              results.length,
              OpenHandStatusColors.info,
              key: _DistributionRecordType.result,
            ),
            _DistributionItem(
              '规则',
              rules.length,
              colors.tertiary,
              key: _DistributionRecordType.rule,
            ),
            _DistributionItem(
              '日志',
              logs.length,
              colors.secondary,
              key: _DistributionRecordType.log,
            ),
          ],
          detailBuilder: (context, item) => switch (item.key) {
            _DistributionRecordType.task => _metricTaskPanel(
              history,
              title: '可见任务记录',
              emptyLabel: '暂无可见任务记录。',
            ),
            _DistributionRecordType.result => _metricResultPanel(
              results,
              title: '可见结果记录',
              emptyLabel: '暂无可见结果记录。',
            ),
            _DistributionRecordType.rule => _ruleInsightPanel(
              context,
              rules,
              title: '可见规则记录',
            ),
            _DistributionRecordType.log => _InsightRecordPanel(
              icon: Icons.receipt_long_outlined,
              title: '可见日志记录',
              records: logs.map(_logInsightRecord).toList(growable: false),
              emptyLabel: '暂无可见日志记录。',
              maxEntries: 50,
            ),
            _ => throw StateError('未知记录类型：${item.key}'),
          },
        ),
        _InsightTimelineSection(
          title: '最近可见记录时间线',
          icon: Icons.timeline_rounded,
          entries: [
            ...history.map(
              (entry) => _InsightTimelineEntry(
                at: entry.effectiveFinishedAt ?? entry.createdAt,
                title:
                    '任务 · ${entry.name.trim().isEmpty ? entry.id : entry.name}',
                detail:
                    '${_stageName(entry.stage)} · 处理 ${entry.progress.processed}',
                tag: '任务',
                color: colors.primary,
                target: _TaskInsightTarget(entry),
              ),
            ),
            ...results.map(
              (entry) => _InsightTimelineEntry(
                at: entry.createdAt,
                title:
                    '结果 · ${entry.product.isEmpty ? entry.host : entry.product}',
                detail:
                    '${_sourceName(entry.source)} · 证据 ${entry.evidence.length}',
                tag: '结果',
                color: OpenHandStatusColors.info,
                target: _ResultInsightTarget(entry),
              ),
            ),
            ...logs.map(
              (entry) => _InsightTimelineEntry(
                at: entry.at,
                title: '日志 · ${entry.message}',
                detail: entry.jobId.isEmpty ? '系统事件' : '任务 ${entry.jobId}',
                tag: '日志',
                color: entry.level == 'error'
                    ? OpenHandStatusColors.error
                    : entry.level == 'warning'
                    ? OpenHandStatusColors.warning
                    : colors.secondary,
                target: _LogInsightTarget(entry),
              ),
            ),
          ]..sort((left, right) => right.at.compareTo(left.at)),
          emptyLabel: '暂无可见记录。',
        ),
      ]);
    case _MetricInsightId.storageTaskArchive:
      final stageCounts = <String, int>{};
      for (final entry in history) {
        stageCounts.update(
          entry.stage,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
      return _metricInsightPage([
        _InsightRankingSection(
          title: '任务归档阶段构成',
          icon: Icons.work_history_outlined,
          items: stageCounts.entries
              .map(
                (entry) => _InsightRankItem(
                  label: _stageName(entry.key),
                  value: entry.value.toDouble(),
                  valueLabel: '${entry.value} 个',
                  key: entry.key,
                  color: entry.key == 'completed'
                      ? OpenHandStatusColors.success
                      : entry.key == 'failed'
                      ? OpenHandStatusColors.error
                      : OpenHandStatusColors.warning,
                ),
              )
              .toList(growable: false),
          emptyLabel: '暂无任务归档。',
          detailBuilder: (context, item) => _metricTaskPanel(
            history.where((task) => task.stage == item.key),
            title: '${item.label}归档任务',
            emptyLabel: '暂无${item.label}归档任务。',
            lens: _TaskRecordLens.archive,
          ),
        ),
        _InsightTrendSection(
          title: '归档任务处理规模',
          icon: Icons.stacked_line_chart_rounded,
          series: [
            OpenHandChartSeries(
              label: '处理',
              values: chronological
                  .map((entry) => entry.progress.processed.toDouble())
                  .toList(growable: false),
              color: colors.primary,
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
              .map((entry) => _shortDateTime(entry.createdAt))
              .toList(growable: false),
          suffix: ' 项',
          emptyLabel: '暂无归档任务样本',
          targets: chronological
              .map<_InsightTarget?>((task) => _TaskInsightTarget(task))
              .toList(growable: false),
        ),
        _metricTaskPanel(
          history,
          title: '任务归档索引',
          emptyLabel: '暂无任务归档。',
          lens: _TaskRecordLens.archive,
        ),
      ]);
    case _MetricInsightId.storageResultArchive:
      final withEvidence = results.where((entry) => entry.evidence.isNotEmpty);
      final jobIds = history.map((entry) => entry.id).toSet();
      return _metricInsightPage([
        _InsightKpiBand(
          title: '结果归档完整性',
          icon: Icons.fact_check_outlined,
          items: [
            _InsightKpi(
              icon: Icons.fact_check_outlined,
              label: '归档结果',
              value: '${results.length}',
              helper:
                  '${results.map((entry) => entry.jobId).toSet().length} 个关联任务',
              color: OpenHandStatusColors.info,
            ),
            _InsightKpi(
              icon: Icons.verified_outlined,
              label: '证据完整',
              value: '${withEvidence.length}',
              helper: '具有至少一条审计证据',
              color: OpenHandStatusColors.success,
            ),
            _InsightKpi(
              icon: Icons.warning_amber_rounded,
              label: '缺少证据',
              value: '${results.length - withEvidence.length}',
              helper: '需要完整性复核',
              color: OpenHandStatusColors.warning,
            ),
            _InsightKpi(
              icon: Icons.link_outlined,
              label: '当前窗口关联缺口',
              value:
                  '${results.where((entry) => !jobIds.contains(entry.jobId)).length}',
              helper: '任务可能位于未加载的历史窗口',
              color: colors.outline,
            ),
          ],
        ),
        _metricResultPanel(
          results,
          title: '结果归档索引',
          emptyLabel: '暂无结果归档。',
          lens: _ResultRecordLens.archive,
        ),
      ]);
    case _MetricInsightId.storageRuleSnapshots:
      final enabled = rules.where((entry) => entry.enabled).length;
      return _metricInsightPage([
        _InsightKpiBand(
          title: '规则快照版本面',
          icon: Icons.rule_folder_outlined,
          items: [
            _InsightKpi(
              icon: Icons.rule_folder_outlined,
              label: '规则总数',
              value: '${rules.length}',
              helper: '当前服务返回快照',
              color: colors.primary,
            ),
            _InsightKpi(
              icon: Icons.toggle_on_rounded,
              label: '已启用',
              value: '$enabled',
              helper: '参与扫描匹配',
              color: OpenHandStatusColors.success,
            ),
            _InsightKpi(
              icon: Icons.toggle_off_rounded,
              label: '未启用',
              value: '${rules.length - enabled}',
              helper: '保留但不参与扫描',
              color: colors.outline,
            ),
          ],
        ),
        _ruleInsightPanel(context, rules, title: '规则快照明细'),
      ]);
    case _MetricInsightId.storageLogBuffer:
      final info = logs.where((entry) => entry.level == 'info').length;
      final warnings = logs.where((entry) => entry.level == 'warning').length;
      final errors = logs.where((entry) => entry.level == 'error').length;
      return _metricInsightPage([
        _InsightDonutSection(
          title: '日志缓冲级别构成',
          icon: Icons.receipt_long_outlined,
          items: [
            _DistributionItem(
              '信息',
              info,
              OpenHandStatusColors.info,
              key: 'info',
            ),
            _DistributionItem(
              '警告',
              warnings,
              OpenHandStatusColors.warning,
              key: 'warning',
            ),
            _DistributionItem(
              '错误',
              errors,
              OpenHandStatusColors.error,
              key: 'error',
            ),
          ],
          detailBuilder: (context, item) {
            final selectedLevel = item.key! as String;
            return _InsightRecordPanel(
              icon: Icons.receipt_long_outlined,
              title: '${item.label}日志 · 当前缓冲',
              records: logs
                  .where((entry) => entry.level == selectedLevel)
                  .map(_logInsightRecord)
                  .toList(growable: false),
              emptyLabel: '当前日志缓冲中没有${item.label}记录。',
              maxEntries: 50,
            );
          },
        ),
        _InsightTimelineSection(
          title: '日志缓冲时间线',
          icon: Icons.history_rounded,
          entries: logs.reversed
              .map(
                (entry) => _InsightTimelineEntry(
                  at: entry.at,
                  title: entry.message,
                  detail: entry.jobId.isEmpty ? '系统日志' : '任务 ${entry.jobId}',
                  tag: _operationsLogLevelName(entry.level),
                  color: entry.level == 'error'
                      ? OpenHandStatusColors.error
                      : entry.level == 'warning'
                      ? OpenHandStatusColors.warning
                      : OpenHandStatusColors.info,
                  target: _LogInsightTarget(entry),
                ),
              )
              .toList(growable: false),
          emptyLabel: '日志缓冲为空。',
        ),
      ]);
    case _MetricInsightId.storageResumable:
      final resumable = history.where((entry) => entry.isResumable).toList();
      return _metricInsightPage([
        _InsightMatrixSection(
          title: '归档恢复检查点',
          icon: Icons.restart_alt_rounded,
          rows: resumable
              .map(
                (entry) => _InsightMatrixRow(
                  icon: Icons.restore_rounded,
                  title: entry.name.trim().isEmpty ? entry.id : entry.name,
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
                      label: '更新 ${_shortDateTime(entry.progress.updatedAt)}',
                      color: colors.primary,
                    ),
                    _InsightMatrixCell(
                      label: '授权范围 ${entry.authorizedScope.length}',
                      color: colors.tertiary,
                    ),
                  ],
                ),
              )
              .toList(growable: false),
          emptyLabel: '归档中没有需要恢复的任务。',
        ),
      ]);
    case _MetricInsightId.storagePostgresql:
      final status = dependencies?.postgresql;
      return _metricInsightPage([
        _InsightKpiBand(
          title: 'PostgreSQL 镜像链路',
          icon: Icons.cloud_sync_outlined,
          items: [
            _InsightKpi(
              icon: Icons.settings_outlined,
              label: '配置状态',
              value: status?.configured == true ? '已配置' : '未配置',
              helper: controller.postgresqlEnabled ? '偏好设置已启用' : '偏好设置未启用',
              color: status?.configured == true
                  ? colors.primary
                  : colors.outline,
            ),
            _InsightKpi(
              icon: Icons.link_rounded,
              label: '连接状态',
              value: status?.connected == true ? '在线' : '未连接',
              helper: status?.message ?? '服务未返回状态',
              color: status?.connected == true
                  ? OpenHandStatusColors.success
                  : OpenHandStatusColors.warning,
            ),
          ],
        ),
        _dependencyInsightPanel(context, controller, only: 'PostgreSQL 镜像'),
        _DependencyDataAccessPanel(controller: controller),
      ]);
    case _MetricInsightId.storageRedis:
      final status = dependencies?.redis;
      return _metricInsightPage([
        _InsightKpiBand(
          title: 'Redis 协调链路',
          icon: Icons.hub_outlined,
          items: [
            _InsightKpi(
              icon: Icons.settings_outlined,
              label: '配置状态',
              value: status?.configured == true ? '已配置' : '未配置',
              helper: controller.redisEnabled ? '偏好设置已启用' : '偏好设置未启用',
              color: status?.configured == true
                  ? colors.primary
                  : colors.outline,
            ),
            _InsightKpi(
              icon: Icons.link_rounded,
              label: '连接状态',
              value: status?.connected == true ? '在线' : '未连接',
              helper: status?.message ?? '服务未返回状态',
              color: status?.connected == true
                  ? OpenHandStatusColors.success
                  : OpenHandStatusColors.warning,
            ),
          ],
        ),
        _dependencyInsightPanel(context, controller, only: 'Redis 协调'),
        _DependencyDataAccessPanel(controller: controller),
      ]);
    case _MetricInsightId.storageCredentialEncryption:
      final protected = results
          .where((entry) => entry.maskedCredential?.trim().isNotEmpty == true)
          .toList(growable: false);
      final duplicateHosts = protected.fold<int>(
        0,
        (sum, entry) => sum + entry.duplicateKeyHosts,
      );
      return _metricInsightPage([
        _InsightKpiBand(
          title: '加密对象边界',
          icon: Icons.enhanced_encryption_outlined,
          items: [
            _InsightKpi(
              icon: Icons.lock_outline_rounded,
              label: '受保护结果',
              value: '${protected.length}',
              helper: '仅展示脱敏凭证',
              color: colors.tertiary,
            ),
            _InsightKpi(
              icon: Icons.copy_all_outlined,
              label: '重复凭证主机',
              value: '$duplicateHosts',
              helper: '凭证关联范围统计',
              color: OpenHandStatusColors.warning,
            ),
            _InsightKpi(
              icon: Icons.security_rounded,
              label: '加密证明',
              value: controller.ownsProcess ? 'AES-256-GCM' : '未上报',
              helper: controller.ownsProcess ? '内置引擎认证加密' : '外部服务未提供证明',
              color: controller.ownsProcess
                  ? OpenHandStatusColors.success
                  : colors.outline,
            ),
          ],
        ),
        _credentialEncryptionDetailSection(context, controller),
        _metricResultPanel(
          protected,
          title: '受保护凭证记录',
          emptyLabel: '暂无需要加密持久化的凭证记录。',
          lens: _ResultRecordLens.credentials,
        ),
      ]);
    case _MetricInsightId.storageIntegrity:
      final jobIds = history.map((entry) => entry.id).toSet();
      final missingHistoryLinks = results
          .where((entry) => !jobIds.contains(entry.jobId))
          .length;
      final missingEvidence = results
          .where((entry) => entry.evidence.isEmpty)
          .length;
      final unfinished = history
          .where(
            (entry) => !const {
              'completed',
              'failed',
              'cancelled',
            }.contains(entry.stage),
          )
          .length;
      return _metricInsightPage([
        _InsightKpiBand(
          title: '一致性审计结论',
          icon: Icons.verified_outlined,
          items: [
            _InsightKpi(
              icon: Icons.link_outlined,
              label: '当前窗口关联缺口',
              value: '$missingHistoryLinks',
              helper: '不等同于持久化层孤立结果',
              color: colors.outline,
            ),
            _InsightKpi(
              icon: Icons.find_in_page_outlined,
              label: '缺少证据',
              value: '$missingEvidence',
              helper: '结果没有审计证据',
              color: missingEvidence == 0
                  ? OpenHandStatusColors.success
                  : OpenHandStatusColors.warning,
            ),
            _InsightKpi(
              icon: Icons.pending_actions_outlined,
              label: '未结束归档',
              value: '$unfinished',
              helper: '任务尚未进入终态',
              color: unfinished == 0
                  ? OpenHandStatusColors.success
                  : colors.tertiary,
            ),
          ],
        ),
        _integrityInsightPanel(context, controller),
      ]);
    default:
      throw StateError('指标 ID 分派到了错误的运维分组：$id');
  }
}

Widget _buildSecurityMetricInsight(
  BuildContext context,
  _MetricInsightId id,
  ServicesController controller,
) {
  final colors = Theme.of(context).colorScheme;
  final enabledRules = controller.rules
      .where((entry) => entry.enabled)
      .toList(growable: false);
  final proxy = controller.proxyStatus;
  final samples = _proxyRequestSamples(controller);

  switch (id) {
    case _MetricInsightId.securityEnabledRules:
      final vendors = <String, int>{};
      for (final rule in enabledRules) {
        final vendor = rule.vendor.trim().isEmpty ? '未分类' : rule.vendor;
        vendors.update(vendor, (value) => value + 1, ifAbsent: () => 1);
      }
      return _metricInsightPage([
        _InsightRankingSection(
          title: '规则供应商覆盖排名',
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
            enabledRules.where(
              (rule) =>
                  (rule.vendor.trim().isEmpty ? '未分类' : rule.vendor) ==
                  item.key,
            ),
            title: '${item.label}启用规则',
          ),
        ),
        _InsightMatrixSection(
          title: '启用规则能力矩阵',
          icon: Icons.grid_view_rounded,
          rows: enabledRules
              .map(
                (rule) => _InsightMatrixRow(
                  icon: Icons.rule_rounded,
                  title: rule.vendor.trim().isEmpty ? rule.id : rule.vendor,
                  subtitle: rule.protocol.trim().isEmpty
                      ? '未声明协议'
                      : rule.protocol,
                  color: colors.primary,
                  target: _RuleInsightTarget(rule),
                  cells: [
                    _InsightMatrixCell(
                      label: '凭证模式 ${rule.credentialPatterns.length}',
                      color: const Color(0xff0f766e),
                    ),
                    _InsightMatrixCell(
                      label: '上下文词 ${rule.contextTerms.length}',
                      color: colors.tertiary,
                    ),
                    _InsightMatrixCell(
                      label: '模型端点 ${rule.modelPaths.length}',
                      color: OpenHandStatusColors.info,
                    ),
                    _InsightMatrixCell(
                      label: '编码 ${rule.contentEncodings.length}',
                      color: const Color(0xff0891b2),
                    ),
                  ],
                ),
              )
              .toList(growable: false),
          emptyLabel: '暂无启用规则。',
        ),
      ]);
    case _MetricInsightId.securityCredentialPatterns:
      final ruleItems = enabledRules
          .where((rule) => rule.credentialPatterns.isNotEmpty)
          .toList(growable: false);
      return _metricInsightPage([
        _InsightRankingSection(
          title: '凭证模式复杂度排名',
          icon: Icons.fingerprint_rounded,
          items: ruleItems
              .map(
                (rule) => _InsightRankItem(
                  label: rule.vendor.trim().isEmpty ? rule.id : rule.vendor,
                  value: rule.credentialPatterns.length.toDouble(),
                  valueLabel: '${rule.credentialPatterns.length} 个模式',
                  helper:
                      '${rule.contextTerms.length} 个上下文词 · ${rule.protocol.trim().isEmpty ? '未声明协议' : rule.protocol}',
                  color: const Color(0xff0f766e),
                  target: _RuleInsightTarget(rule),
                ),
              )
              .toList(growable: false),
          emptyLabel: '暂无启用凭证识别规则。',
        ),
        _ruleInsightPanel(
          context,
          ruleItems,
          title: '凭证模式与上下文约束',
          lens: _RuleDetailLens.credentials,
        ),
      ]);
    case _MetricInsightId.securityModelEndpoints:
      final ruleItems = enabledRules
          .where(
            (rule) =>
                rule.modelPaths.isNotEmpty || rule.balancePaths.isNotEmpty,
          )
          .toList(growable: false);
      return _metricInsightPage([
        _InsightMatrixSection(
          title: '主动验证端点矩阵',
          icon: Icons.api_rounded,
          rows: ruleItems
              .map(
                (rule) => _InsightMatrixRow(
                  icon: Icons.api_rounded,
                  title: rule.vendor.trim().isEmpty ? rule.id : rule.vendor,
                  subtitle: rule.protocol.trim().isEmpty
                      ? '未声明验证协议'
                      : rule.protocol,
                  color: OpenHandStatusColors.info,
                  target: _RuleInsightTarget(rule),
                  cells: [
                    _InsightMatrixCell(
                      label: '模型端点 ${rule.modelPaths.length}',
                      color: OpenHandStatusColors.info,
                    ),
                    _InsightMatrixCell(
                      label: '余额端点 ${rule.balancePaths.length}',
                      color: colors.tertiary,
                    ),
                    _InsightMatrixCell(
                      label: '凭证模式 ${rule.credentialPatterns.length}',
                      color: colors.primary,
                    ),
                  ],
                ),
              )
              .toList(growable: false),
          emptyLabel: '暂无主动验证端点。',
        ),
        _ruleInsightPanel(
          context,
          ruleItems,
          title: '模型与余额端点路径',
          lens: _RuleDetailLens.endpoints,
        ),
      ]);
    case _MetricInsightId.securityEncodings:
      final encodingCounts = <AiExposureContentEncoding, int>{};
      for (final rule in enabledRules) {
        for (final encoding in rule.contentEncodings) {
          encodingCounts.update(
            encoding,
            (value) => value + 1,
            ifAbsent: () => 1,
          );
        }
      }
      return _metricInsightPage([
        _InsightRankingSection(
          title: '内容编码覆盖',
          icon: Icons.code_rounded,
          items: AiExposureContentEncoding.values
              .map(
                (encoding) => _InsightRankItem(
                  label: encoding.id,
                  value: (encodingCounts[encoding] ?? 0).toDouble(),
                  valueLabel: '${encodingCounts[encoding] ?? 0} 条规则',
                  color: _distributionColor(encoding.index, colors),
                  key: encoding,
                ),
              )
              .toList(growable: false),
          emptyLabel: '暂无内容编码识别配置。',
          detailBuilder: (context, item) => _ruleInsightPanel(
            context,
            enabledRules.where(
              (rule) => rule.contentEncodings.contains(item.key),
            ),
            title: '${item.label}编码规则',
            lens: _RuleDetailLens.encodings,
          ),
        ),
        _ruleInsightPanel(
          context,
          enabledRules.where((rule) => rule.contentEncodings.isNotEmpty),
          title: '编码识别规则明细',
          lens: _RuleDetailLens.encodings,
        ),
      ]);
    case _MetricInsightId.securityProxyRequests:
      return _metricInsightPage([
        _proxySecurityBoundaryPanel(context, controller),
        _InsightDonutSection(
          title: '验证出口请求构成',
          icon: Icons.lan_outlined,
          items: [
            _DistributionItem(
              '成功',
              proxy?.totalSuccesses ?? 0,
              OpenHandStatusColors.success,
              key: _ProxyRequestLens.success,
            ),
            _DistributionItem(
              '失败',
              proxy?.totalFailures ?? 0,
              OpenHandStatusColors.error,
              key: _ProxyRequestLens.failure,
            ),
            _DistributionItem(
              '超时',
              proxy?.totalTimeouts ?? 0,
              OpenHandStatusColors.warning,
              key: _ProxyRequestLens.timeout,
            ),
          ],
          detailBuilder: (context, item) {
            final lens = item.key! as _ProxyRequestLens;
            return _proxyRequestInsightPanel(
              context,
              controller,
              lens,
              title: '${item.label}验证出口请求',
            );
          },
        ),
        _proxyRequestInsightPanel(
          context,
          controller,
          _ProxyRequestLens.abnormal,
          title: '近期出口异常审计',
        ),
      ]);
    case _MetricInsightId.securityProxySuccess:
      final successSamples = samples
          .where((entry) => entry.succeeded)
          .toList(growable: false);
      return _metricInsightPage([
        _InsightKpiBand(
          title: '验证出口成功质量',
          icon: Icons.task_alt_rounded,
          items: [
            _InsightKpi(
              icon: Icons.task_alt_rounded,
              label: '累计成功',
              value: '${proxy?.totalSuccesses ?? 0}',
              helper: '运行时累计值',
              color: OpenHandStatusColors.success,
            ),
            _InsightKpi(
              icon: Icons.speed_rounded,
              label: '平均响应',
              value: '${proxy?.averageResponseTimeMs ?? 0} ms',
              helper: '全量完成请求',
              color: colors.primary,
            ),
            _InsightKpi(
              icon: Icons.multiline_chart_rounded,
              label: '近期 p95',
              value:
                  '${_latencyPercentile(successSamples.map((entry) => entry.responseTimeMs).toList(), 0.95)} ms',
              helper: '${successSamples.length} 个成功样本',
              color: colors.tertiary,
            ),
          ],
        ),
        _InsightTrendSection(
          title: '验证成功响应曲线',
          icon: Icons.show_chart_rounded,
          series: [
            OpenHandChartSeries(
              label: '验证成功',
              values: successSamples
                  .map((entry) => entry.responseTimeMs.toDouble())
                  .toList(growable: false),
              color: OpenHandStatusColors.success,
            ),
          ],
          sampleLabels: successSamples
              .map((entry) => _shortDateTime(entry.at))
              .toList(growable: false),
          suffix: ' ms',
          emptyLabel: '暂无验证成功请求样本',
          interpolation: OpenHandChartInterpolation.smooth,
          targets: _proxyTargetsForSamples(controller, successSamples),
        ),
        _proxySuccessEndpointAuditPanel(context, controller),
      ]);
    case _MetricInsightId.securityProxyAnomalies:
      final abnormal = samples
          .where((entry) => !entry.succeeded)
          .toList(growable: false);
      return _metricInsightPage([
        _InsightKpiBand(
          title: '验证出口异常态势',
          icon: Icons.report_gmailerrorred_rounded,
          items: [
            _InsightKpi(
              icon: Icons.error_outline_rounded,
              label: '失败',
              value: '${proxy?.totalFailures ?? 0}',
              helper: '非超时请求异常',
              color: OpenHandStatusColors.error,
            ),
            _InsightKpi(
              icon: Icons.timer_off_outlined,
              label: '超时',
              value: '${proxy?.totalTimeouts ?? 0}',
              helper: '请求超过等待边界',
              color: OpenHandStatusColors.warning,
            ),
            _InsightKpi(
              icon: Icons.history_rounded,
              label: '近期异常样本',
              value: '${abnormal.length}',
              helper: '有限请求窗口',
              color: colors.tertiary,
            ),
          ],
        ),
        _proxyFailureEndpointPanel(context, controller, title: '验证出口异常节点'),
        _proxyRequestInsightPanel(
          context,
          controller,
          _ProxyRequestLens.abnormal,
          title: '异常验证请求',
        ),
      ]);
    case _MetricInsightId.securityDependencies:
      final dependencies = controller.dependencyStatus;
      final states =
          <
            ({
              _DependencyInsightId id,
              String name,
              IconData icon,
              bool configured,
              bool connected,
              String message,
            })
          >[
            (
              id: _DependencyInsightId.scannerCore,
              name: '扫描核心',
              icon: Icons.memory_rounded,
              configured: true,
              connected: controller.isRunning,
              message: 'ai_jungler ${controller.health?.version ?? '--'}',
            ),
            (
              id: _DependencyInsightId.postgresql,
              name: 'PostgreSQL 镜像',
              icon: Icons.cloud_sync_outlined,
              configured: dependencies?.postgresql.configured ?? false,
              connected: dependencies?.postgresql.connected ?? false,
              message: dependencies?.postgresql.message ?? '未启用',
            ),
            (
              id: _DependencyInsightId.redis,
              name: 'Redis 协调',
              icon: Icons.hub_outlined,
              configured: dependencies?.redis.configured ?? false,
              connected: dependencies?.redis.connected ?? false,
              message: dependencies?.redis.message ?? '未启用',
            ),
            (
              id: _DependencyInsightId.playwright,
              name: 'Playwright 浏览器',
              icon: Icons.web_outlined,
              configured: dependencies?.playwright.configured ?? false,
              connected: dependencies?.playwright.connected ?? false,
              message: dependencies?.playwright.message ?? '未启用',
            ),
            (
              id: _DependencyInsightId.gptExtractor,
              name: 'GPT 辅助提取',
              icon: Icons.auto_awesome_outlined,
              configured: controller.aiExtractorStatus?.configured ?? false,
              connected: controller.aiExtractorStatus?.configured ?? false,
              message: controller.aiExtractorStatus?.model ?? '未启用',
            ),
          ];
      return _metricInsightPage([
        _InsightKpiBand(
          title: '依赖就绪摘要',
          icon: Icons.hub_outlined,
          items: [
            _InsightKpi(
              icon: Icons.task_alt_rounded,
              label: '已就绪',
              value: '${states.where((entry) => entry.connected).length}',
              helper: '${states.length} 个运行组件',
              color: OpenHandStatusColors.success,
            ),
            _InsightKpi(
              icon: Icons.settings_outlined,
              label: '已配置',
              value: '${states.where((entry) => entry.configured).length}',
              helper: '满足配置前置',
              color: colors.primary,
            ),
            _InsightKpi(
              icon: Icons.link_off_rounded,
              label: '未连接',
              value:
                  '${states.where((entry) => entry.configured && !entry.connected).length}',
              helper: '已配置但当前不可用',
              color: OpenHandStatusColors.warning,
            ),
          ],
        ),
        _InsightMatrixSection(
          title: '运行依赖拓扑',
          icon: Icons.account_tree_outlined,
          rows: states
              .map(
                (entry) => _InsightMatrixRow(
                  icon: entry.icon,
                  title: entry.name,
                  subtitle: entry.message,
                  color: entry.connected
                      ? OpenHandStatusColors.success
                      : entry.configured
                      ? OpenHandStatusColors.warning
                      : colors.outline,
                  target: _DependencyInsightTarget(
                    id: entry.id,
                    name: entry.name,
                    configured: entry.configured,
                    connected: entry.connected,
                    message: entry.message,
                  ),
                  cells: [
                    _InsightMatrixCell(
                      label: entry.configured ? '已配置' : '未配置',
                      color: entry.configured ? colors.primary : colors.outline,
                    ),
                    _InsightMatrixCell(
                      label: entry.connected ? '已就绪' : '未就绪',
                      color: entry.connected
                          ? OpenHandStatusColors.success
                          : OpenHandStatusColors.warning,
                    ),
                  ],
                ),
              )
              .toList(growable: false),
          emptyLabel: '暂无运行依赖状态。',
        ),
        _DependencyDataAccessPanel(controller: controller),
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
  const Color(0xffa855f7),
  const Color(0xff0f766e),
  const Color(0xff0891b2),
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
  final durationMs = _taskDurationMs(entry);
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
      '更新 ${_shortDateTime(progress.updatedAt)}',
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
      '耗时 ${duration == null ? '--' : _duration(duration.inSeconds.clamp(0, 86400))}',
      '开始 ${_shortDateTime(entry.effectiveStartedAt)}',
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
      '检查点 ${_shortDateTime(progress.updatedAt)}',
      '任务 ${entry.id}',
    ],
    _TaskRecordLens.archive => [
      '任务 ${entry.id}',
      _stageName(entry.stage),
      '创建 ${_shortDateTime(entry.createdAt)}',
      if (finishedAt != null) '归档 ${_shortDateTime(finishedAt)}',
    ],
    _TaskRecordLens.overview => [
      _stageName(entry.stage),
      entry.mode == AiExposureScanMode.full ? '全量扫描' : '增量扫描',
      '处理 ${progress.processed}/${progress.total}',
      '候选 ${progress.candidates}',
      '有效 ${progress.valid}',
      if (duration != null)
        '耗时 ${_duration(duration.inSeconds.clamp(0, 86400))}',
      if (entry.sources.isNotEmpty)
        entry.sources.map(_sourceName).take(3).join(' / '),
      _shortDateTime(finishedAt ?? entry.createdAt),
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
      '扫描来源：${entry.sources.map(_sourceName).join(' / ')}',
    _ =>
      entry.errorMessage?.trim().isNotEmpty == true
          ? entry.errorMessage!.trim()
          : progress.message,
  };
  return _InsightRecord(
    icon: _stageIcon(entry.stage),
    title: entry.name.trim().isEmpty ? entry.id : entry.name,
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
    AiExposureResultCategory.highValue => const Color(0xffa855f7),
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
      _shortDateTime(entry.createdAt),
    ],
    _ResultRecordLens.credentials => [
      '状态 ${aiExposureCredentialStateName(entry.credentialState)}',
      if (entry.maskedCredential?.trim().isNotEmpty == true)
        entry.maskedCredential!.trim(),
      '模型 ${entry.modelCount}',
      _shortDateTime(entry.createdAt),
    ],
    _ResultRecordLens.source => [
      _sourceName(entry.source),
      '任务 ${entry.jobId}',
      category,
      _shortDateTime(entry.createdAt),
    ],
    _ResultRecordLens.archive => [
      '结果 ${entry.id}',
      '任务 ${entry.jobId}',
      category,
      '证据 ${entry.evidence.length}',
      _shortDateTime(entry.createdAt),
    ],
    _ResultRecordLens.overview => [
      category,
      _sourceName(entry.source),
      '凭证 ${aiExposureCredentialStateName(entry.credentialState)}',
      '模型 ${entry.modelCount}',
      if (entry.duplicateResponseHosts > 0)
        '重复响应 ${entry.duplicateResponseHosts}',
      if (entry.duplicateKeyHosts > 0) '重复凭证 ${entry.duplicateKeyHosts}',
      _shortDateTime(entry.createdAt),
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
    tags: [_operationsLogLevelName(entry.level), _shortDateTime(entry.at)],
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
      _shortDateTime(request.at),
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
      _shortDateTime(probe.checkedAt),
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

Widget _proxyFleetLatencyPanel(
  BuildContext context,
  ServicesController controller,
) {
  final samples = _proxyRequestSamples(controller);
  final completed = samples
      .where((sample) => sample.responseTimeMs > 0)
      .toList();
  final average = completed.isEmpty
      ? 0
      : (completed.fold<int>(0, (sum, sample) => sum + sample.responseTimeMs) /
                completed.length)
            .round();
  final sorted = completed.map((sample) => sample.responseTimeMs).toList()
    ..sort();
  final median = _latencyPercentile(sorted, 0.5);
  final p95 = _latencyPercentile(sorted, 0.95);
  final records = <_InsightRecord>[
    _InsightRecord(
      icon: Icons.av_timer_rounded,
      title: '近期响应中心值',
      subtitle: '仅基于最近 ${completed.length} 个真实代理请求样本。',
      tags: ['平均 $average ms', '中位数 $median ms', 'p95 $p95 ms'],
      color: completed.isEmpty
          ? Theme.of(context).colorScheme.outline
          : Theme.of(context).colorScheme.primary,
    ),
    _InsightRecord(
      icon: Icons.compare_arrows_rounded,
      title: '累计与近期口径差异',
      subtitle: '累计值来自服务运行时计数，近期值来自有限请求窗口。',
      tags: [
        '累计平均 ${controller.proxyStatus?.averageResponseTimeMs ?? 0} ms',
        '近期平均 $average ms',
        '窗口 ${completed.length}',
      ],
      color: Theme.of(context).colorScheme.secondary,
    ),
  ];
  return _InsightRecordPanel(
    icon: Icons.speed_rounded,
    title: '代理池响应质量摘要',
    records: records,
    emptyLabel: '暂无代理响应质量数据。',
  );
}

Widget _proxySecurityBoundaryPanel(
  BuildContext context,
  ServicesController controller,
) {
  final config = controller.proxyConfiguration;
  final authenticated = config.endpoints
      .where((endpoint) => Uri.parse(endpoint.url).userInfo.isNotEmpty)
      .length;
  final masked = config.endpoints.where((endpoint) {
    final authenticated = Uri.parse(endpoint.url).userInfo.isNotEmpty;
    return !authenticated || endpoint.maskedUrl.contains(':******@');
  }).length;
  final records = <_InsightRecord>[
    _InsightRecord(
      icon: Icons.visibility_off_outlined,
      title: '代理凭证展示边界',
      subtitle: '代理池界面与运维详情只使用脱敏地址。',
      tags: [
        '凭证节点 $authenticated',
        '已脱敏 $masked/${config.endpoints.length}',
        '不展示密码',
      ],
      color: masked == config.endpoints.length
          ? OpenHandStatusColors.success
          : OpenHandStatusColors.error,
    ),
    _InsightRecord(
      icon: Icons.home_work_outlined,
      title: '本地网络旁路边界',
      subtitle: config.bypassLocal ? '回环、本机与本地网络目标按配置绕过代理。' : '本地目标也会进入当前代理路由。',
      tags: [config.bypassLocal ? '旁路开启' : '旁路关闭'],
      color: config.bypassLocal
          ? OpenHandStatusColors.success
          : OpenHandStatusColors.warning,
    ),
    _InsightRecord(
      icon: Icons.sync_lock_outlined,
      title: '运行时传输范围',
      subtitle: '仅启用节点进入服务运行时配置，停用节点不参与出口请求。',
      tags: [
        '启用 ${config.activeEndpoints.length}',
        '停用 ${config.endpoints.length - config.activeEndpoints.length}',
        'HTTP/HTTPS 代理',
      ],
      color: Theme.of(context).colorScheme.primary,
    ),
  ];
  return _InsightRecordPanel(
    icon: Icons.security_rounded,
    title: '代理出口安全边界',
    records: records,
    emptyLabel: '暂无代理出口安全配置。',
  );
}

Widget _proxySuccessEndpointAuditPanel(
  BuildContext context,
  ServicesController controller,
) {
  final runtimeById = _proxyRuntimeById(controller);
  final records = controller.proxyConfiguration.endpoints
      .where(
        (endpoint) =>
            _proxyEndpointStatistics(endpoint, runtimeById).successes > 0,
      )
      .map((endpoint) {
        final statistics = _proxyEndpointStatistics(endpoint, runtimeById);
        return _InsightRecord(
          icon: Icons.verified_user_outlined,
          title: endpoint.displayName,
          subtitle: '该出口节点已产生成功请求，可用于验证链路健康度审计。',
          tags: [
            '成功 ${statistics.successes}',
            '成功率 ${(statistics.successRate * 100).toStringAsFixed(1)}%',
            '最后成功 ${statistics.lastSuccessAt == null ? '--' : _shortDateTime(statistics.lastSuccessAt!)}',
            '平均 ${statistics.averageResponseTimeMs} ms',
            'HTTP 2xx ${statistics.status2xx}',
          ],
          color: OpenHandStatusColors.success,
          target: _ProxyEndpointInsightTarget(endpoint),
        );
      })
      .toList(growable: false);
  return _InsightRecordPanel(
    icon: Icons.verified_user_outlined,
    title: '成功验证出口审计',
    records: records,
    emptyLabel: '暂无已产生成功验证请求的出口节点。',
  );
}

Widget _proxyFleetWorkbench(
  BuildContext context,
  ServicesController controller,
) {
  final colors = Theme.of(context).colorScheme;
  final config = controller.proxyConfiguration;
  final endpoints = config.endpoints;
  final runtimeById = _proxyRuntimeById(controller);
  final enabled = endpoints.where((endpoint) => endpoint.enabled).length;
  final inspected = endpoints
      .where((endpoint) => endpoint.latestSample != null)
      .length;
  final records = endpoints
      .map((endpoint) {
        final uri = Uri.parse(endpoint.url);
        final runtime = runtimeById[endpoint.runtimeId];
        final statistics = _proxyEndpointStatistics(endpoint, runtimeById);
        return _InsightRecord(
          icon: Icons.dns_outlined,
          title: endpoint.displayName,
          subtitle: endpoint.maskedUrl,
          tags: [
            endpoint.enabled ? '已纳入调度' : '已停用',
            uri.scheme.toUpperCase(),
            uri.userInfo.isEmpty ? '无认证' : '凭证认证',
            runtime == null ? '无运行时实例' : '运行时已注册',
            '选路 ${runtime?.selections ?? 0}',
            '请求 ${statistics.requests}',
          ],
          color: endpoint.enabled ? OpenHandStatusColors.info : colors.outline,
          target: _ProxyEndpointInsightTarget(endpoint),
        );
      })
      .toList(growable: false);
  return _Section(
    icon: Icons.dns_outlined,
    title: '代理节点控制平面',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final coverage = SizedBox(
              width: 136,
              height: 122,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: ServiceAnimatedDonutChart(
                      values: [enabled, endpoints.length - enabled],
                      colors: [OpenHandStatusColors.success, colors.outline],
                      trackColor: colors.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$enabled/${endpoints.length}',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '调度覆盖',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
            final configuration = _OpsKeyValueGrid(
              children: [
                _OpsKeyValue(label: '节点资产', value: '${endpoints.length}'),
                _OpsKeyValue(label: '运行时注册', value: '${runtimeById.length}'),
                _OpsKeyValue(label: '最近已巡检', value: '$inspected'),
                _OpsKeyValue(
                  label: '调度策略',
                  value: _proxyStrategyName(config.strategy),
                ),
              ],
            );
            if (constraints.maxWidth < 600) {
              return Column(children: [coverage, configuration]);
            }
            return Row(
              children: [
                coverage,
                const SizedBox(width: 22),
                Expanded(child: configuration),
              ],
            );
          },
        ),
        Divider(height: 24, color: colors.outlineVariant),
        if (records.isEmpty)
          const _InsightEmpty(label: '代理池尚未配置节点。')
        else
          ...records.indexed.map(
            (entry) => Column(
              children: [
                if (entry.$1 > 0)
                  Divider(
                    height: 16,
                    color: colors.outlineVariant.withValues(alpha: 0.5),
                  ),
                _InsightRecordRow(record: entry.$2),
              ],
            ),
          ),
      ],
    ),
  );
}

Widget _proxyReachabilityWorkbench(
  BuildContext context,
  ServicesController controller,
) {
  final colors = Theme.of(context).colorScheme;
  final endpoints = controller.proxyConfiguration.endpoints;
  final inspected = endpoints
      .where((endpoint) => endpoint.latestSample != null)
      .length;
  final gatewayReachable = endpoints
      .where((endpoint) => endpoint.latestSample?.gatewayReachable == true)
      .length;
  final reachable = endpoints
      .where((endpoint) => endpoint.latestSample?.reachable == true)
      .length;
  final records = endpoints
      .map((endpoint) {
        final sample = endpoint.latestSample;
        final reachable = sample?.reachable == true;
        final tone = reachable
            ? OpenHandStatusColors.success
            : sample == null
            ? colors.outline
            : OpenHandStatusColors.error;
        final diagnosis = sample == null
            ? '等待首次巡检。'
            : sample.error?.trim().isNotEmpty == true
            ? sample.error!.trim()
            : reachable
            ? '代理网关与 HTTPS 转发链路均可用。'
            : sample.gatewayReachable
            ? '代理网关可达，但转发链路失败。'
            : '代理网关不可达。';
        return _InsightRecord(
          icon: reachable
              ? Icons.cloud_done_outlined
              : Icons.cloud_off_outlined,
          title: endpoint.displayName,
          subtitle: diagnosis,
          tags: [
            sample == null
                ? '未巡检'
                : sample.gatewayReachable
                ? '网关可达'
                : '网关不可达',
            sample == null
                ? '转发待检测'
                : reachable
                ? 'HTTPS 转发正常'
                : 'HTTPS 转发失败',
            if (sample?.latencyMs != null) '探测 ${sample!.latencyMs} ms',
            if (sample?.statusCode != null) 'HTTP ${sample!.statusCode}',
            if (sample != null) '巡检 ${_shortDateTime(sample.checkedAt)}',
          ],
          color: tone,
          target: _ProxyEndpointInsightTarget(endpoint),
        );
      })
      .toList(growable: false);
  return _Section(
    icon: Icons.cloud_done_outlined,
    title: '连通性诊断链路',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InsightFlowLane(
          nodes: [
            (
              icon: Icons.dns_outlined,
              label: '已配置节点',
              value: '${endpoints.length}',
              color: OpenHandStatusColors.info,
            ),
            (
              icon: Icons.router_outlined,
              label: '网关可达',
              value: '$gatewayReachable',
              color: colors.primary,
            ),
            (
              icon: Icons.cloud_done_outlined,
              label: '转发可用',
              value: '$reachable',
              color: OpenHandStatusColors.success,
            ),
            (
              icon: Icons.hourglass_empty_rounded,
              label: '等待巡检',
              value: '${endpoints.length - inspected}',
              color: colors.outline,
            ),
          ],
        ),
        Divider(height: 24, color: colors.outlineVariant),
        if (records.isEmpty)
          const _InsightEmpty(label: '配置代理节点后将自动生成网关与转发诊断。')
        else
          ...records.indexed.map(
            (entry) => Column(
              children: [
                if (entry.$1 > 0)
                  Divider(
                    height: 16,
                    color: colors.outlineVariant.withValues(alpha: 0.5),
                  ),
                _InsightRecordRow(record: entry.$2),
              ],
            ),
          ),
      ],
    ),
  );
}

Widget _proxyExitIdentityPanel(
  BuildContext context,
  ServicesController controller,
) {
  final colors = Theme.of(context).colorScheme;
  final records = controller.proxyConfiguration.endpoints
      .where((endpoint) => endpoint.identity != null)
      .map((endpoint) {
        final identity = endpoint.identity!;
        final autonomousSystem = [
          identity.asn,
          identity.asName,
        ].where((value) => value.trim().isNotEmpty).join(' · ');
        final networkFlags = [
          if (identity.proxy) '代理网络',
          if (identity.hosting) '托管网络',
          if (identity.mobile) '移动网络',
        ];
        return _InsightRecord(
          icon: Icons.public_rounded,
          title:
              '${identity.country.isEmpty ? '未知国家' : identity.country} · ${endpoint.displayName}',
          subtitle:
              '${identity.exitIp.isEmpty ? '--' : identity.exitIp} · ${identity.location.isEmpty ? '位置未识别' : identity.location}',
          tags: [
            '国家代码 ${identity.countryCode.isEmpty ? '--' : identity.countryCode}',
            'ISP ${identity.isp.isEmpty ? '--' : identity.isp}',
            'ASN ${autonomousSystem.isEmpty ? '--' : autonomousSystem}',
            '网络 ${identity.networkType}',
            'IP ${identity.ipType}',
            '纯净度 ${identity.cleanliness}',
            ...networkFlags,
            '识别 ${_shortDateTime(identity.observedAt)}',
          ],
          color: identity.cleanliness == 'high'
              ? OpenHandStatusColors.success
              : identity.cleanliness == 'low'
              ? OpenHandStatusColors.warning
              : colors.primary,
          target: _ProxyEndpointInsightTarget(endpoint),
        );
      })
      .toList(growable: false);
  return _InsightRecordPanel(
    icon: Icons.public_rounded,
    title: '出口网络与地理画像',
    records: records,
    emptyLabel: '暂无已识别的出口网络画像。',
  );
}

Widget _proxyInspectionPolicySection(
  BuildContext context,
  ServicesController controller,
) {
  final config = controller.proxyConfiguration;
  final enabled = config.endpoints
      .where((endpoint) => endpoint.enabled)
      .toList();
  final latestChecks =
      enabled
          .map((endpoint) => endpoint.latestSample?.checkedAt)
          .whereType<DateTime>()
          .toList()
        ..sort();
  final lastCheckedAt = latestChecks.lastOrNull;
  final nextCheckAt = config.inspectionEnabled && lastCheckedAt != null
      ? lastCheckedAt.add(Duration(minutes: config.inspectionIntervalMinutes))
      : null;
  final inspected = enabled
      .where((endpoint) => endpoint.latestSample != null)
      .length;
  return _Section(
    title: '自动巡检执行计划',
    icon: Icons.event_repeat_rounded,
    child: Column(
      children: [
        _OpsKeyValue(
          label: '计划状态',
          value: config.inspectionEnabled ? '运行中' : '已停用',
          color: config.inspectionEnabled
              ? OpenHandStatusColors.success
              : Theme.of(context).colorScheme.outline,
        ),
        _OpsKeyValue(
          label: '执行周期',
          value: '每 ${config.inspectionIntervalMinutes} 分钟',
        ),
        _OpsKeyValue(label: '最大并发', value: '${config.inspectionConcurrency}'),
        _OpsKeyValue(label: '本轮覆盖', value: '$inspected/${enabled.length} 节点'),
        _OpsKeyValue(
          label: '最近执行',
          value: lastCheckedAt == null ? '--' : _shortDateTime(lastCheckedAt),
        ),
        _OpsKeyValue(
          label: '预计下次',
          value: !config.inspectionEnabled
              ? '计划未启用'
              : nextCheckAt == null
              ? '等待首次调度'
              : _shortDateTime(nextCheckAt),
        ),
      ],
    ),
  );
}

Widget _proxyInspectionEventPanel(
  BuildContext context,
  ServicesController controller,
) {
  final events = <(AiExposureProxyEndpoint, AiExposureProxyProbeSample)>[];
  for (final endpoint in controller.proxyConfiguration.endpoints) {
    for (final sample in endpoint.samples) {
      events.add((endpoint, sample));
    }
  }
  events.sort((left, right) => right.$2.checkedAt.compareTo(left.$2.checkedAt));
  final records = events
      .map((event) {
        final endpoint = event.$1;
        final sample = event.$2;
        final tone = sample.reachable
            ? OpenHandStatusColors.success
            : OpenHandStatusColors.error;
        return _InsightRecord(
          icon: sample.reachable
              ? Icons.health_and_safety_outlined
              : Icons.report_problem_outlined,
          title: endpoint.displayName,
          subtitle: sample.error?.trim().isNotEmpty == true
              ? sample.error!.trim()
              : sample.reachable
              ? '巡检通过，代理转发链路可用。'
              : '巡检未通过，需检查网关或转发配置。',
          tags: [
            _shortDateTime(sample.checkedAt),
            sample.gatewayReachable ? '网关可达' : '网关不可达',
            sample.reachable ? '转发成功' : '转发失败',
            if (sample.latencyMs != null) '${sample.latencyMs} ms',
            if (sample.statusCode != null) 'HTTP ${sample.statusCode}',
            if (sample.failure != null)
              '故障 ${_proxyProbeFailureName(sample.failure!)}',
          ],
          color: tone,
          target: _ProxyProbeInsightTarget(endpoint: endpoint, sample: sample),
        );
      })
      .toList(growable: false);
  return _InsightRecordPanel(
    icon: Icons.monitor_heart_outlined,
    title: '最近巡检执行事件',
    records: records,
    emptyLabel: '巡检计划尚未产生执行样本。',
    maxEntries: 50,
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

Widget _proxyLatencyQualityPanel(
  BuildContext context,
  ServicesController controller,
) {
  final runtimeById = _proxyRuntimeById(controller);
  final records = controller.proxyConfiguration.endpoints
      .map((endpoint) {
        final statistics = _proxyEndpointStatistics(endpoint, runtimeById);
        final tone = statistics.averageResponseTimeMs == 0
            ? Theme.of(context).colorScheme.outline
            : statistics.averageResponseTimeMs <= 1000
            ? OpenHandStatusColors.success
            : statistics.averageResponseTimeMs <= 3000
            ? OpenHandStatusColors.warning
            : OpenHandStatusColors.error;
        return _InsightRecord(
          icon: Icons.av_timer_rounded,
          title: endpoint.displayName,
          subtitle: '按 ${statistics.completed} 次已完成请求计算，未以巡检延迟替代业务响应。',
          tags: [
            '平均 ${statistics.averageResponseTimeMs} ms',
            '最短 ${statistics.minResponseTimeMs} ms',
            '最长 ${statistics.maxResponseTimeMs} ms',
            '样本 ${statistics.recentRequests.length}',
          ],
          color: tone,
          target: _ProxyEndpointInsightTarget(endpoint),
        );
      })
      .toList(growable: false);
  return _InsightRecordPanel(
    icon: Icons.av_timer_rounded,
    title: '节点响应质量基线',
    records: records,
    emptyLabel: '暂无可评估的节点响应质量数据。',
  );
}

Widget _proxyLatencyRulerSection(
  BuildContext context, {
  required int sampleCount,
  required int p50,
  required int p95,
  required int peak,
}) {
  final colors = Theme.of(context).colorScheme;
  if (sampleCount == 0) {
    return _Section(
      title: '长尾基线生成流程',
      icon: Icons.stacked_line_chart_rounded,
      child: _InsightFlowLane(
        nodes: [
          (
            icon: Icons.swap_vert_rounded,
            label: '代理业务请求',
            value: '等待样本',
            color: colors.primary,
          ),
          (
            icon: Icons.dataset_outlined,
            label: '近期采样窗口',
            value: '0 条',
            color: OpenHandStatusColors.info,
          ),
          (
            icon: Icons.stacked_line_chart_rounded,
            label: 'p95 基线',
            value: '待生成',
            color: OpenHandStatusColors.warning,
          ),
        ],
      ),
    );
  }
  return _Section(
    title: '响应分位标尺 · $sampleCount 条近期样本',
    icon: Icons.stacked_line_chart_rounded,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InsightFlowLane(
          nodes: [
            (
              icon: Icons.horizontal_rule_rounded,
              label: '典型响应 p50',
              value: '$p50 ms',
              color: OpenHandStatusColors.info,
            ),
            (
              icon: Icons.multiline_chart_rounded,
              label: '长尾边界 p95',
              value: '$p95 ms',
              color: colors.tertiary,
            ),
            (
              icon: Icons.vertical_align_top_rounded,
              label: '窗口峰值',
              value: '$peak ms',
              color: OpenHandStatusColors.warning,
            ),
          ],
        ),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: ServiceAnimatedProgressBar(
            value: serviceProgressRatio(value: p95, maximum: peak),
            minHeight: 8,
            color: colors.tertiary,
            backgroundColor: colors.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text('0 ms', style: Theme.of(context).textTheme.labelSmall),
            const Spacer(),
            Text(
              'p95 占峰值 ${_chartRate(p95, peak)}',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const Spacer(),
            Text('$peak ms', style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ],
    ),
  );
}

Widget _proxyTailLatencyPanel(
  BuildContext context,
  ServicesController controller,
) {
  final runtimeById = _proxyRuntimeById(controller);
  final records = <_InsightRecord>[];
  for (final endpoint in controller.proxyConfiguration.endpoints) {
    final statistics = _proxyEndpointStatistics(endpoint, runtimeById);
    final latencies = statistics.recentRequests
        .map((sample) => sample.responseTimeMs)
        .toList(growable: false);
    final p95 = _latencyPercentile(latencies, 0.95);
    final aboveP95 = latencies
        .where((latency) => latency >= p95 && p95 > 0)
        .length;
    records.add(
      _InsightRecord(
        icon: Icons.stacked_line_chart_rounded,
        title: endpoint.displayName,
        subtitle: latencies.isEmpty
            ? '近期窗口暂无长尾响应样本。'
            : '近期窗口按 ${latencies.length} 个真实请求样本计算。',
        tags: [
          'p95 $p95 ms',
          '峰值 ${latencies.isEmpty ? 0 : latencies.reduce((a, b) => a > b ? a : b)} ms',
          '长尾样本 $aboveP95',
          '累计最长 ${statistics.maxResponseTimeMs} ms',
        ],
        color: p95 == 0
            ? Theme.of(context).colorScheme.outline
            : OpenHandStatusColors.warning,
        target: _ProxyEndpointInsightTarget(endpoint),
      ),
    );
  }
  return _InsightRecordPanel(
    icon: Icons.stacked_line_chart_rounded,
    title: '节点长尾响应剖面',
    records: records,
    emptyLabel: '暂无节点长尾响应数据。',
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
            _shortDateTime(sample.at),
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

String _maskProxyAddress(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || uri.host.isEmpty) return '代理地址不可用';
  final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
  final port = uri.hasPort ? ':${uri.port}' : '';
  if (uri.userInfo.isEmpty) return '${uri.scheme}://$host$port';
  final username = Uri.decodeComponent(uri.userInfo.split(':').first);
  return '${uri.scheme}://$username:******@$host$port';
}

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
  for (final job in controller.history) {
    events.add((
      job.createdAt,
      _InsightRecord(
        icon: Icons.note_add_outlined,
        title: '创建任务 · ${job.name.trim().isEmpty ? job.id : job.name}',
        subtitle: '任务 ${job.id} · ${job.sources.map(_sourceName).join(' / ')}',
        tags: [
          _shortDateTime(job.createdAt),
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
          title: '更新任务终态 · ${job.name.trim().isEmpty ? job.id : job.name}',
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
  for (final result in controller.results) {
    events.add((
      result.createdAt,
      _InsightRecord(
        icon: Icons.fact_check_outlined,
        title:
            '写入扫描结果 · ${result.product.isEmpty ? result.host : result.product}',
        subtitle: '结果 ${result.id} · 关联任务 ${result.jobId}',
        tags: [
          _shortDateTime(result.createdAt),
          _sourceName(result.source),
          '证据 ${result.evidence.length}',
          '凭证 ${aiExposureCredentialStateName(result.credentialState)}',
        ],
        color: OpenHandStatusColors.success,
        target: _ResultInsightTarget(result),
      ),
    ));
  }
  for (final log in controller.logs) {
    events.add((
      log.at,
      _InsightRecord(
        icon: Icons.receipt_long_outlined,
        title: '追加运行日志 · ${_operationsLogLevelName(log.level)}',
        subtitle: log.message,
        tags: [
          _shortDateTime(log.at),
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

Widget _credentialEncryptionDetailSection(
  BuildContext context,
  ServicesController controller,
) {
  final databasePath = controller.health?.databasePath.trim() ?? '';
  final slash = databasePath.lastIndexOf('/');
  final backslash = databasePath.lastIndexOf(r'\');
  final separator = slash > backslash ? slash : backslash;
  final keyPath = separator < 0
      ? ''
      : '${databasePath.substring(0, separator + 1)}credential.key';
  final protectedResults = controller.results
      .where((result) => result.maskedCredential?.trim().isNotEmpty == true)
      .toList(growable: false);
  final duplicateReferences = protectedResults.fold<int>(
    0,
    (total, result) => total + result.duplicateKeyHosts,
  );
  if (!controller.ownsProcess) {
    return _Section(
      title: '外部服务凭证保护边界',
      icon: Icons.enhanced_encryption_outlined,
      child: Column(
        children: [
          const _OpsKeyValue(label: '运行模式', value: '外部扫描服务'),
          const _OpsKeyValue(
            label: '加密证明',
            value: '后端未提供运行时算法、密钥隔离或静态加密证明',
            color: OpenHandStatusColors.warning,
            maxLines: 4,
          ),
          const _OpsKeyValue(label: 'API 返回边界', value: '界面仅接收并展示脱敏凭证'),
          _OpsKeyValue(label: '受保护结果', value: '${protectedResults.length}'),
          _OpsKeyValue(label: '重复凭证关联主机', value: '$duplicateReferences'),
        ],
      ),
    );
  }
  return _LocalFileStatsBuilder(
    paths: [keyPath],
    refreshKey: controller.health?.uptimeSeconds,
    builder: (context, stats) {
      final keyStat = stats[keyPath];
      return _Section(
        title: '凭证密文边界与密钥隔离',
        icon: Icons.enhanced_encryption_outlined,
        child: Column(
          children: [
            const _OpsKeyValue(label: '加密算法', value: 'AES-256-GCM'),
            const _OpsKeyValue(label: '随机数长度', value: '96 bit · 每条凭证独立生成'),
            const _OpsKeyValue(label: '完整性保护', value: 'GCM 认证标签'),
            const _OpsKeyValue(label: '密钥长度', value: '256 bit'),
            _OpsKeyValue(
              label: '独立密钥文件',
              value: keyStat == null
                  ? '不可访问或服务未初始化'
                  : '${formatByteSize(keyStat.size)} · ${keyStat.modeString()}',
              color: keyStat == null
                  ? OpenHandStatusColors.warning
                  : OpenHandStatusColors.success,
            ),
            const _OpsKeyValue(label: '明文暴露边界', value: '仅写入前短暂驻留 · API 不返回明文'),
            const _OpsKeyValue(label: '界面展示策略', value: '仅展示脱敏凭证'),
            _OpsKeyValue(label: '受保护结果', value: '${protectedResults.length}'),
            _OpsKeyValue(label: '重复凭证关联主机', value: '$duplicateReferences'),
          ],
        ),
      );
    },
  );
}

Widget _dependencyInsightPanel(
  BuildContext context,
  ServicesController controller, {
  String? only,
}) {
  final dependencies = controller.dependencyStatus;
  final colors = Theme.of(context).colorScheme;
  final records = <_InsightRecord>[];
  void add(
    _DependencyInsightId id,
    String name,
    IconData icon,
    bool configured,
    bool connected,
    String message,
  ) {
    if (only != null && !name.startsWith(only.split(' ').first)) return;
    records.add(
      _InsightRecord(
        icon: icon,
        title: name,
        subtitle: message,
        tags: [configured ? '已配置' : '未配置', connected ? '已连接' : '未连接'],
        color: connected
            ? OpenHandStatusColors.success
            : configured
            ? OpenHandStatusColors.warning
            : colors.outline,
        target: _DependencyInsightTarget(
          id: id,
          name: name,
          configured: configured,
          connected: connected,
          message: message,
        ),
      ),
    );
  }

  add(
    _DependencyInsightId.scannerCore,
    '扫描核心',
    Icons.memory_rounded,
    true,
    controller.isRunning,
    'ai_jungler ${controller.health?.version ?? '--'}',
  );
  add(
    _DependencyInsightId.postgresql,
    'PostgreSQL 镜像',
    Icons.cloud_sync_outlined,
    dependencies?.postgresql.configured ?? false,
    dependencies?.postgresql.connected ?? false,
    dependencies?.postgresql.message ?? '未启用',
  );
  add(
    _DependencyInsightId.redis,
    'Redis 协调',
    Icons.hub_outlined,
    dependencies?.redis.configured ?? false,
    dependencies?.redis.connected ?? false,
    dependencies?.redis.message ?? '未启用',
  );
  add(
    _DependencyInsightId.playwright,
    'Playwright 浏览器',
    Icons.web_outlined,
    dependencies?.playwright.configured ?? false,
    dependencies?.playwright.connected ?? false,
    dependencies?.playwright.message ?? '未启用',
  );
  add(
    _DependencyInsightId.gptExtractor,
    'GPT 辅助提取',
    Icons.auto_awesome_outlined,
    controller.aiExtractorStatus?.configured ?? false,
    controller.aiExtractorStatus?.configured ?? false,
    controller.aiExtractorStatus?.model ?? '未启用',
  );
  return _InsightRecordPanel(
    icon: Icons.hub_outlined,
    title: only ?? '运行依赖',
    records: records,
    emptyLabel: '暂无依赖状态。',
  );
}

Widget _integrityInsightPanel(
  BuildContext context,
  ServicesController controller,
) {
  final colors = Theme.of(context).colorScheme;
  final jobIds = controller.history.map((entry) => entry.id).toSet();
  final records = <_InsightRecord>[];
  for (final result in controller.results) {
    final missingHistoryLink = !jobIds.contains(result.jobId);
    final missingEvidence = result.evidence.isEmpty;
    if (!missingHistoryLink && !missingEvidence) continue;
    records.add(
      _InsightRecord(
        icon: Icons.fact_check_outlined,
        title: _resultDisplayName(result),
        subtitle: [
          if (missingHistoryLink) '当前任务窗口未加载关联任务',
          if (missingEvidence) '缺少审计证据',
        ].join(' · '),
        tags: [
          result.jobId,
          _sourceName(result.source),
          aiExposureCredentialStateName(result.credentialState),
        ],
        color: OpenHandStatusColors.warning,
        target: _ResultInsightTarget(result),
      ),
    );
  }
  for (final job in controller.history.where((entry) => !entry.isTerminal)) {
    records.add(
      _InsightRecord(
        icon: Icons.pending_actions_outlined,
        title: job.name.trim().isEmpty ? job.id : job.name,
        subtitle: '归档中仍处于 ${_stageName(job.stage)} 阶段。',
        tags: [job.id, _shortDateTime(job.createdAt)],
        color: colors.tertiary,
        target: _TaskInsightTarget(job),
      ),
    );
  }
  return _InsightRecordPanel(
    icon: Icons.rule_folder_outlined,
    title: '当前加载窗口一致性线索',
    records: records,
    emptyLabel: '当前加载窗口未发现关联缺口、缺少证据或未结束归档。',
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
  final finishedAt = task.finishedAt;
  if (startedAt == null ||
      finishedAt == null ||
      finishedAt.isBefore(startedAt)) {
    return null;
  }
  return finishedAt.difference(startedAt).inMilliseconds;
}

int? _taskDurationMs(AiExposureHistoryEntry task) {
  final finishedAt = task.effectiveFinishedAt;
  final startedAt = task.effectiveStartedAt;
  if (finishedAt == null || finishedAt.isBefore(startedAt)) return null;
  return finishedAt.difference(startedAt).inMilliseconds;
}

List<AiExposureHistoryEntry> _chronologicalJobs(
  ServicesController controller, {
  int limit = 24,
}) {
  final jobs = [...controller.history]
    ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
  return jobs.length <= limit ? jobs : jobs.sublist(jobs.length - limit);
}

List<_InsightTimelineEntry> _taskTimeline(
  Iterable<AiExposureHistoryEntry> jobs,
) {
  final sorted = [...jobs]
    ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
  return sorted
      .map(
        (task) => _InsightTimelineEntry(
          at: task.effectiveFinishedAt ?? task.createdAt,
          title: task.name.trim().isEmpty ? task.id : task.name,
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
      )
      .toList(growable: false);
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
  for (final result in controller.results) {
    sourceCounts.update(result.source, (value) => value + 1, ifAbsent: () => 1);
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
              label: _sourceName(entry.key),
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
      .where((task) => _taskDurationMs(task) != null)
      .toList(growable: false);
  final durations = finished.map((task) => _taskDurationMs(task)!).toList();
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
      (left, right) =>
          _taskDurationMs(right)!.compareTo(_taskDurationMs(left)!),
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
              label: task.name.trim().isEmpty ? task.id : task.name,
              value: _taskDurationMs(task)!.toDouble(),
              valueLabel: '${_taskDurationMs(task)} ms',
              helper:
                  '${_stageName(task.stage)} · 处理 ${task.progress.processed} · ${task.sources.map(_sourceName).join(' / ')}',
              color: _taskDurationMs(task)! >= p95 && p95 > 0
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
          .where((task) => p95 > 0 && _taskDurationMs(task)! >= p95)
          .map(
            (task) => _InsightTimelineEntry(
              at: task.effectiveFinishedAt!,
              title: task.name.trim().isEmpty ? task.id : task.name,
              detail: '耗时 ${_taskDurationMs(task)} ms · P95 阈值 $p95 ms',
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
          color: const Color(0xffa855f7),
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
              title: task.name.trim().isEmpty ? task.id : task.name,
              subtitle:
                  '${_stageName(task.stage)} · ${_shortDateTime(task.createdAt)}',
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
                  color: const Color(0xffa855f7),
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
  final resultTimes = controller.results.map((result) => result.createdAt);
  final jobTimes = controller.history.map((task) => task.createdAt);
  final logTimes = controller.logs.map((log) => log.at);
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
          title: '当前规则快照',
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
              label: task.name.trim().isEmpty ? task.id : task.name,
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
    ),
    _DistributionItem(
      '高价值',
      count(AiExposureResultCategory.highValue),
      const Color(0xffa855f7),
    ),
    _DistributionItem(
      '可疑',
      count(AiExposureResultCategory.suspicious),
      OpenHandStatusColors.warning,
    ),
    _DistributionItem(
      '蜜罐',
      count(AiExposureResultCategory.honeypot),
      OpenHandStatusColors.error,
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
          color: const Color(0xffa855f7),
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
              AiExposureResultCategory.highValue => const Color(0xffa855f7),
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
    final values = jobs.map(_taskDurationMs).whereType<int>().toList();
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
  final items = AiExposureSource.values
      .map(
        (source) => _DistributionItem(
          _sourceName(source),
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
          label: _sourceName(source),
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
        final quota = controller.quotas
            .where((quota) => quota.source == _sourceQuotaKey(source))
            .firstOrNull;
        final ready =
            controller.sourceStatus[_sourceCredentialKey(source)] == true;
        return _InsightMatrixRow(
          icon: _sourceIcon(source),
          title: _sourceName(source),
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
  return _metricInsightPage([
    _InsightDonutSection(
      title: '任务来源覆盖次数',
      icon: Icons.hub_outlined,
      items: AiExposureSource.values
          .map(
            (source) => _DistributionItem(
              _sourceName(source),
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
              icon: _sourceIcon(source),
              title: _sourceName(source),
              subtitle: controller.sourceStatus[source.id] == true
                  ? '来源已就绪'
                  : '来源未就绪',
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
                  label:
                      '单任务产出 ${taskCounts[source] == null || taskCounts[source] == 0 ? '不适用' : ((resultCounts[source] ?? 0) / taskCounts[source]!).toStringAsFixed(1)}',
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
            _ => const _InsightEmpty(label: '暂无记录。'),
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
  final resumable = controller.history
      .where((task) => task.isResumable)
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
      title: '归档与恢复能力',
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
          icon: Icons.restart_alt_rounded,
          label: '可恢复',
          value: '${resumable.length}',
          helper: '按任务恢复标记',
          color: OpenHandStatusColors.warning,
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
      icon: Icons.restart_alt_rounded,
      title: '恢复候选任务',
      records: resumable
          .map((task) => _taskInsightRecord(task, _TaskRecordLens.recovery))
          .toList(),
      emptyLabel: '暂无可恢复任务。',
    ),
    _InsightRecordPanel(
      icon: Icons.inventory_2_outlined,
      title: '任务归档明细',
      records: controller.history
          .map((task) => _taskInsightRecord(task, _TaskRecordLens.archive))
          .toList(),
      emptyLabel: '暂无任务归档记录。',
    ),
    _integrityInsightPanel(context, controller),
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
              label: _sourceName(entry.key),
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
