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
    final dependencies = controller.dependencyStatus;
    final historyIds = history.map((entry) => entry.id).toSet();
    final missingHistoryLinks = results
        .where((result) => !historyIds.contains(result.jobId))
        .length;
    final missingEvidence = results
        .where((result) => result.evidence.isEmpty)
        .length;
    final unfinished = history
        .where(
          (entry) => !const <String>{
            'completed',
            'failed',
            'cancelled',
          }.contains(entry.stage),
        )
        .length;
    final resumable = history.where((entry) => entry.isResumable).length;
    final failed = history.where((entry) => entry.stage == 'failed').length;
    final integrityIssues = missingEvidence;
    final recordCount =
        history.length + results.length + logs.length + rules.length;
    final chronological = history.take(24).toList().reversed.toList();
    var cumulativeResults = 0;
    final cumulativeResultValues = <double>[];
    for (final entry in chronological) {
      cumulativeResults += results
          .where((result) => result.jobId == entry.id)
          .length;
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
            _Metric(
              _MetricInsightId.storageVisibleRecords,
              Icons.inventory_2_outlined,
              '当前可见记录',
              '$recordCount',
              '任务、结果、规则与日志',
              color: OpenHandStatusColors.info,
            ),
            _Metric(
              _MetricInsightId.storageTaskArchive,
              Icons.work_history_outlined,
              '当前任务窗口',
              '${history.length}',
              '$unfinished 个未结束',
              color: colors.primary,
            ),
            _Metric(
              _MetricInsightId.storageResultArchive,
              Icons.fact_check_outlined,
              '当前结果窗口',
              '${results.length}',
              '$missingEvidence 条缺少证据',
              color: const Color(0xff0891b2),
            ),
            _Metric(
              _MetricInsightId.storageRuleSnapshots,
              Icons.rule_folder_outlined,
              '规则快照',
              '${rules.length}',
              '${rules.where((rule) => rule.enabled).length} 条启用',
              color: const Color(0xff0f766e),
            ),
            _Metric(
              _MetricInsightId.storageLogBuffer,
              Icons.receipt_long_outlined,
              '日志缓冲',
              '${logs.length}',
              '信息 ${logs.where((entry) => entry.level == 'info').length} · 错误 ${logs.where((entry) => entry.level == 'error').length}',
              color: colors.secondary,
            ),
            _Metric(
              _MetricInsightId.storageResumable,
              Icons.restart_alt_rounded,
              '可恢复任务',
              '$resumable',
              '失败 $failed · 未结束 $unfinished',
              color: OpenHandStatusColors.warning,
            ),
            _Metric(
              _MetricInsightId.storagePostgresql,
              Icons.cloud_sync_outlined,
              'PostgreSQL 镜像',
              dependencies?.postgresql.connected == true ? '在线' : '未连接',
              dependencies?.postgresql.message ?? '未启用',
              color: dependencies?.postgresql.connected == true
                  ? OpenHandStatusColors.success
                  : colors.outline,
            ),
            _Metric(
              _MetricInsightId.storageRedis,
              Icons.hub_outlined,
              'Redis 协调',
              dependencies?.redis.connected == true ? '在线' : '未连接',
              dependencies?.redis.message ?? '未启用',
              color: dependencies?.redis.connected == true
                  ? OpenHandStatusColors.success
                  : colors.outline,
            ),
            _Metric(
              _MetricInsightId.storageCredentialEncryption,
              Icons.enhanced_encryption_outlined,
              '凭证加密',
              controller.ownsProcess ? 'AES-256-GCM' : '后端未证明',
              controller.ownsProcess ? '内置引擎密钥文件独立保存' : '外部服务未提供运行时加密证明',
              color: colors.tertiary,
            ),
            _Metric(
              _MetricInsightId.storageIntegrity,
              integrityIssues == 0
                  ? Icons.verified_outlined
                  : Icons.warning_amber_rounded,
              '一致性审计',
              integrityIssues == 0 ? '通过' : '$integrityIssues 项',
              '当前窗口关联缺口 $missingHistoryLinks · 缺少证据 $missingEvidence',
              color: integrityIssues == 0
                  ? OpenHandStatusColors.success
                  : OpenHandStatusColors.warning,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _DependencyDataAccessPanel(controller: controller),
        const SizedBox(height: 12),
        _OpsPanelGrid(
          children: [
            _TrendPanel(
              id: _TrendInsightId.archiveGrowth,
              interpolation: OpenHandChartInterpolation.step,
              icon: Icons.stacked_line_chart_rounded,
              title: '归档增长趋势',
              subtitle: '最近 ${chronological.length} 个任务的累计结果',
              sampleLabels: chronological
                  .map((entry) => _shortDateTime(entry.createdAt))
                  .toList(growable: false),
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
              sampleLabels: chronological
                  .map((entry) => _shortDateTime(entry.createdAt))
                  .toList(growable: false),
              series: [
                OpenHandChartSeries(
                  label: '处理',
                  values: chronological
                      .map((entry) => entry.progress.processed.toDouble())
                      .toList(),
                  color: OpenHandStatusColors.info,
                ),
                OpenHandChartSeries(
                  label: '发现',
                  values: chronological
                      .map((entry) => entry.progress.discovered.toDouble())
                      .toList(),
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
                  .toList(),
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
                  .toList(),
            ),
          ],
        ),
        const SizedBox(height: 12),
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
                    id: _DependencyInsightId.postgresql,
                    name: 'PostgreSQL 镜像',
                    ready: dependencies?.postgresql.connected == true,
                    configured: dependencies?.postgresql.configured,
                    detail: dependencies?.postgresql.message ?? '未启用',
                  ),
                  _DependencyLine(
                    id: _DependencyInsightId.redis,
                    name: 'Redis 目标协调',
                    ready: dependencies?.redis.connected == true,
                    configured: dependencies?.redis.configured,
                    detail: dependencies?.redis.message ?? '未启用',
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
            _Section(
              title: '一致性与恢复能力',
              icon: Icons.rule_folder_outlined,
              child: Column(
                children: [
                  _OpsKeyValue(
                    label: '当前窗口关联缺口',
                    value: '$missingHistoryLinks',
                  ),
                  _OpsKeyValue(label: '缺少证据结果', value: '$missingEvidence'),
                  _OpsKeyValue(label: '未结束任务', value: '$unfinished'),
                  _OpsKeyValue(
                    label: '可恢复任务',
                    value: '$resumable',
                    onTap: resumable <= 0
                        ? null
                        : () => _showTaskCollectionInsight(
                            context,
                            status: 'resumable',
                            title: '可恢复任务',
                          ),
                  ),
                  _OpsKeyValue(
                    label: '失败任务',
                    value: '$failed',
                    onTap: failed <= 0
                        ? null
                        : () => _showTaskCollectionInsight(
                            context,
                            status: 'failed',
                            title: '失败任务',
                          ),
                  ),
                  _OpsKeyValue(
                    label: '审计结论',
                    value: integrityIssues == 0 ? '记录关系完整' : '存在待复核记录',
                    color: integrityIssues == 0
                        ? OpenHandStatusColors.success
                        : OpenHandStatusColors.warning,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Section(
          title: '最近持久化任务',
          icon: Icons.history_rounded,
          child: history.isEmpty
              ? const Text('暂无任务归档。')
              : Column(
                  children: history.take(12).map((entry) {
                    final resultCount = results
                        .where((result) => result.jobId == entry.id)
                        .length;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      onTap: () => _showTaskEntityInsight(context, entry),
                      leading: Icon(_stageIcon(entry.stage)),
                      title: Text(
                        entry.name.trim().isEmpty ? entry.id : entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${_shortDateTime(entry.effectiveFinishedAt ?? entry.createdAt)} · 处理 ${entry.progress.processed} · 结果 $resultCount',
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
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right_rounded, size: 19),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
        if (controller.health?.databasePath.isNotEmpty == true) ...[
          const SizedBox(height: 12),
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
                const SizedBox(height: 10),
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
