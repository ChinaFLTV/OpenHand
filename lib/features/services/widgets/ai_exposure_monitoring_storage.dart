part of 'ai_exposure_monitoring_dialogs.dart';

class _StoragePanel extends StatelessWidget {
  const _StoragePanel({
    required this.controller,
    required this.databaseAccessible,
    required this.databaseBytes,
    required this.databaseModifiedAt,
  });

  final ServicesController controller;
  final bool databaseAccessible;
  final int? databaseBytes;
  final DateTime? databaseModifiedAt;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final history = controller.history;
    final results = controller.results;
    final logs = controller.logs;
    final rules = controller.rules;
    final recordCount =
        history.length + results.length + logs.length + rules.length;
    final chronological = history
        .where((entry) => entry.createdAtReported)
        .take(24)
        .toList(growable: false)
        .reversed
        .toList(growable: false);
    final chronologicalLabels = chronological
        .map(
          (entry) => _reportedShortDateTime(
            entry.createdAt,
            entry.createdAtReported,
          ),
        )
        .toList(growable: false);
    final resultsByJobId = <String, int>{};
    for (final result in results) {
      resultsByJobId.update(result.jobId, (v) => v + 1, ifAbsent: () => 1);
    }
    var cumulativeResults = 0;
    final cumulativeResultValues = <double>[];
    for (final entry in chronological) {
      cumulativeResults += resultsByJobId[entry.id] ?? 0;
      cumulativeResultValues.add(cumulativeResults.toDouble());
    }
    final credentialCounts = <String, int>{};
    for (final result in results) {
      credentialCounts.update(
        result.credentialState,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final stageCounts = <String, int>{};
    for (final entry in history) {
      stageCounts.update(entry.stage, (count) => count + 1, ifAbsent: () => 1);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MetricGrid(
          title: '存储与持久化',
          desktopColumns: 2,
          metrics: [
            _Metric(
              _MetricInsightId.storageSqlite,
              Icons.storage_rounded,
              'SQLite 数据库',
              databaseAccessible ? formatByteSize(databaseBytes ?? 0) : '--',
              databaseAccessible ? '数据库文件可访问' : '等待本地服务路径',
              color: databaseAccessible
                  ? OpenHandStatusColors.success
                  : colors.outline,
            ),
            _Metric(
              _MetricInsightId.storageLastWrite,
              Icons.edit_calendar_outlined,
              '最后写入',
              databaseModifiedAt == null
                  ? '--'
                  : _shortDateTime(databaseModifiedAt!),
              '数据库文件修改时间',
              color: colors.primary,
            ),
          ],
        ),
        kOpenHandGap12,
        _DependencyDataAccessPanel(controller: controller),
        kOpenHandGap12,
        _OpsPanelGrid(
          children: [
            _TrendPanel(
              id: _TrendInsightId.archiveGrowth,
              interpolation: OpenHandChartInterpolation.step,
              icon: Icons.stacked_line_chart_rounded,
              title: '归档增长趋势',
              subtitle: '最近 ${chronological.length} 个任务的累计结果',
              sampleTimes: chronological
                  .map((entry) => entry.createdAt)
                  .toList(growable: false),
              sampleLabels: chronologicalLabels,
              series: [
                OpenHandChartSeries(
                  label: '结果',
                  values: cumulativeResultValues,
                  color: colors.primary,
                ),
              ],
              suffix: ' 条',
            ),
            _TrendPanel(
              id: _TrendInsightId.writeLoad,
              interpolation: OpenHandChartInterpolation.linear,
              icon: Icons.data_saver_on_rounded,
              title: '任务写入负载',
              subtitle: '已处理与发现记录',
              sampleTimes: chronological
                  .map((entry) => entry.createdAt)
                  .toList(growable: false),
              sampleLabels: chronologicalLabels,
              series: [
                OpenHandChartSeries(
                  label: '处理',
                  values: chronological
                      .map((entry) => entry.progress.processed.toDouble())
                      .toList(growable: false),
                  color: OpenHandStatusColors.info,
                ),
                OpenHandChartSeries(
                  label: '发现',
                  values: chronological
                      .map((entry) => entry.progress.discovered.toDouble())
                      .toList(growable: false),
                  color: OpenHandStatusColors.success,
                ),
              ],
              suffix: ' 条',
            ),
            _DistributionPanel(
              id: _DistributionInsightId.recordType,
              icon: Icons.pie_chart_outline_rounded,
              title: '记录类型分布',
              centerValue: '$recordCount',
              items: [
                _DistributionItem('任务', history.length, colors.primary),
                _DistributionItem(
                  '结果',
                  results.length,
                  OpenHandStatusColors.info,
                ),
                _DistributionItem('规则', rules.length, colors.tertiary),
                _DistributionItem('日志', logs.length, colors.secondary),
              ],
            ),
            _DistributionPanel(
              id: _DistributionInsightId.archiveStage,
              icon: Icons.account_tree_outlined,
              title: '任务归档状态',
              centerValue: '${history.length}',
              items: stageCounts.entries
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
                    ),
                  )
                  .toList(growable: false),
            ),
            _DistributionPanel(
              id: _DistributionInsightId.credentialState,
              icon: Icons.key_outlined,
              title: '凭证状态分布',
              centerValue: '${results.length}',
              items: credentialCounts.entries
                  .map(
                    (entry) => _DistributionItem(
                      aiExposureCredentialStateName(entry.key),
                      entry.value,
                      _credentialStateColor(entry.key, colors),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
        kOpenHandGap12,
        _OpsPanelGrid(
          children: [
            _Section(
              title: '持久化子系统',
              icon: Icons.storage_rounded,
              child: Column(
                children: [
                  _DependencyLine(
                    id: _DependencyInsightId.sqlite,
                    name: 'SQLite',
                    ready: databaseAccessible,
                    configured: true,
                    detail: databaseAccessible
                        ? '数据库文件可访问 · ${formatByteSize(databaseBytes ?? 0)} · WAL/外键状态未从运行时验证'
                        : '等待本地数据库文件',
                  ),
                  _DependencyLine(
                    id: _DependencyInsightId.credentialVault,
                    name: '凭证密钥库',
                    ready: controller.isRunning,
                    detail: controller.ownsProcess
                        ? '内置引擎声明使用 AES-256-GCM · 当前运行时未提供加密证明字段'
                        : '外部服务未提供运行时加密证明',
                  ),
                  _DependencyLine(
                    id: _DependencyInsightId.eventArchive,
                    name: '任务事件归档',
                    ready: controller.isRunning,
                    detail: '${logs.length} 条运行事件 · ${history.length} 个任务快照',
                  ),
                ],
              ),
            ),
          ],
        ),
        kOpenHandGap12,
        _Section(
          title: '最近持久化任务',
          icon: Icons.history_rounded,
          child: history.isEmpty
              ? const Text('暂无任务归档。')
              : _InsightListViewport(
                  child: Column(
                    children: history.take(12).map((entry) {
                      final resultCount = resultsByJobId[entry.id] ?? 0;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        onTap: () => _showTaskEntityInsight(context, entry),
                        leading: Icon(_stageIcon(entry.stage)),
                        title: Text(
                          entry.name.trim().isEmpty
                              ? entry.id
                              : entry.name.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${entry.effectiveFinishedAt == null ? _reportedShortDateTime(entry.createdAt, entry.createdAtReported) : _shortDateTime(entry.effectiveFinishedAt!)} · 处理 ${entry.progress.processed} · 结果 $resultCount',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _StatusPill(
                              icon: _stageIcon(entry.stage),
                              label: _stageName(entry.stage),
                              color: entry.stage == 'completed'
                                  ? OpenHandStatusColors.success
                                  : entry.stage == 'failed'
                                  ? OpenHandStatusColors.error
                                  : OpenHandStatusColors.warning,
                            ),
                            kOpenHandHGap4,
                            const Icon(Icons.chevron_right_rounded, size: 19),
                          ],
                        ),
                      );
                    }).toList(growable: false),
                  ),
                ),
        ),
        if (controller.health?.databasePath.isNotEmpty == true) ...[
          kOpenHandGap12,
          _Section(
            title: '数据库位置',
            icon: Icons.folder_open_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SelectableText(
                  controller.health!.databasePath,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                kOpenHandGap10,
                Align(
                  alignment: Alignment.centerRight,
                  child: OpenHandDialogActionButton.secondary(
                    onPressed: () => copyOpenHandTextToClipboard(
                      context: context,
                      text: controller.health!.databasePath,
                      logTag: 'service_operations',
                      logAction: '复制数据库路径',
                      successMessage: '数据库路径已复制。',
                    ),
                    icon: Icons.copy_rounded,
                    label: '复制路径',
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
