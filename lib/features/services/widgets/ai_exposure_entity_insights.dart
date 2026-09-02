part of 'ai_exposure_monitoring_dialogs.dart';

void _showTaskEntityInsight(
  BuildContext context,
  AiExposureHistoryEntry task,
) => _showTaskEntityInsightById(
  context,
  taskId: task.id,
  legacySnapshot: task.id.isEmpty ? task : null,
);

void _showTaskEntityInsightById(
  BuildContext context, {
  required String taskId,
  AiExposureHistoryEntry? legacySnapshot,
}) {
  final text = openHandTextResolver(context);
  final task = taskId.isEmpty
      ? legacySnapshot
      : context
            .read<ServicesController>()
            .history
            .where((entry) => entry.id == taskId)
            .firstOrNull;
  showAnimatedDialog<void>(
    context: context,
    builder: (_) => _OperationsInsightDialog(
      icon: task == null ? Icons.work_history_outlined : _stageIcon(task.stage),
      title: task == null
          ? text(zh: '任务 $taskId', en: 'Task $taskId')
          : task.name.trim().isEmpty
          ? task.id
          : task.name.trim(),
      subtitle: '任务运行、产出与归档详情',
      entity: true,
      child: _TaskEntityInsightBody(
        taskId: taskId,
        legacySnapshot: legacySnapshot,
      ),
    ),
  );
}

void _showSourceEntityInsight(BuildContext context, AiExposureSource source) {
  showAnimatedDialog<void>(
    context: context,
    builder: (_) => _OperationsInsightDialog(
      icon: aiExposureSourceIcon(source),
      title: aiExposureSourceDisplayName(source),
      subtitle: '来源配置、配额与真实产出',
      entity: true,
      child: _SourceEntityInsightBody(source: source),
    ),
  );
}

void _showProxyEndpointEntityInsightById(
  BuildContext context,
  String endpointId,
) {
  final text = openHandTextResolver(context);
  final endpoint = context
      .read<ServicesController>()
      .proxyConfiguration
      .endpoints
      .where((entry) => entry.runtimeId == endpointId)
      .firstOrNull;
  showAnimatedDialog<void>(
    context: context,
    builder: (_) => _OperationsInsightDialog(
      icon: Icons.dns_outlined,
      title:
          endpoint?.displayName ??
          text(zh: '代理节点 $endpointId', en: 'Proxy node $endpointId'),
      subtitle: '代理节点健康与请求遥测',
      entity: true,
      child: _ProxyEndpointEntityInsightBody(endpointId: endpointId),
    ),
  );
}

class _TaskEntityInsightBody extends StatelessWidget {
  const _TaskEntityInsightBody({
    required this.taskId,
    required this.legacySnapshot,
  });

  final String taskId;
  final AiExposureHistoryEntry? legacySnapshot;

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    final controller = context.watch<ServicesController>();
    final task = taskId.isEmpty
        ? legacySnapshot
        : controller.history.where((entry) => entry.id == taskId).firstOrNull;
    if (task == null) return const _InsightEmpty(label: '该任务已不在当前历史记录中。');
    final colors = Theme.of(context).colorScheme;
    final measuredDuration = _taskMeasuredDurationMs(task);
    final terminalBoundary = task.effectiveFinishedAt;
    final recordedStartedAt = task.startedAt;
    final startedLabel = recordedStartedAt == null
        ? task.stage == 'queued'
              ? '尚未开始'
              : task.createdAtReported
              ? '未记录实测开始时间；创建于 ${_shortDateTime(task.createdAt)}'
              : '未记录实测开始时间；创建时间未上报'
        : '${_shortDateTime(recordedStartedAt)}（实测 startedAt）';
    final terminalBoundaryLabel = task.finishedAt != null
        ? '${_shortDateTime(task.finishedAt!)}（实测 finishedAt）'
        : task.cancelledAt != null
        ? '${_shortDateTime(task.cancelledAt!)}（取消边界）'
        : task.lastCheckpointAt != null
        ? '${_shortDateTime(task.lastCheckpointAt!)}（最后检查点）'
        : task.isTerminal && task.progress.updatedAtReported
        ? '${_shortDateTime(task.progress.updatedAt)}（终态进度观测）'
        : task.isTerminal
        ? '终态时间未上报'
        : '未结束';
    final results = task.id.isEmpty
        ? const <AiExposureResult>[]
        : controller.results
              .where((result) => result.jobId == task.id)
              .toList(growable: false);
    final highValueResults = results
        .where(
          (result) => result.category == AiExposureResultCategory.highValue,
        )
        .toList(growable: false);
    final logs = task.id.isEmpty
        ? <AiExposureLogEntry>[]
        : (controller.logs
              .where((entry) => entry.jobId == task.id)
              .toList(growable: false)
            ..sort((left, right) => right.at.compareTo(left.at)));
    const lifecycleStages = <String>[
      'queued',
      'discovering',
      'normalizing',
      'fingerprinting',
      'extracting',
      'validating',
      'persisting',
      'completed',
    ];
    final stages = <String>[
      ...lifecycleStages,
      if (task.stage == 'cancelled') 'cancelled',
      if (task.stage == 'failed') 'failed',
    ];
    return _metricInsightPage([
      _InsightKpiBand(
        title: '任务处理快照',
        icon: Icons.radar_rounded,
        items: [
          _InsightKpi(
            icon: Icons.radar_rounded,
            label: '已处理',
            value: '${task.progress.processed}',
            helper: '总量 ${task.progress.total}',
            color: colors.primary,
          ),
          _InsightKpi(
            icon: Icons.filter_alt_outlined,
            label: '候选',
            value: '${task.progress.candidates}',
            helper:
                '候选率 ${_chartRate(task.progress.candidates, task.progress.processed)}',
            color: OpenHandStatusColors.info,
          ),
          _InsightKpi(
            icon: Icons.fact_check_outlined,
            label: '有效',
            value: '${task.progress.valid}',
            helper: '已归档结果 ${results.length}',
            color: OpenHandStatusColors.success,
          ),
          _InsightKpi(
            icon: Icons.workspace_premium_outlined,
            label: '高价值',
            value: '${task.progress.highValue}',
            helper:
                '占有效 ${_chartRate(task.progress.highValue, task.progress.valid)}',
            color: colors.secondary,
            target: highValueResults.length == 1
                ? _ResultInsightTarget(highValueResults.single)
                : null,
          ),
        ],
      ),
      _InsightFunnelSection(
        title: '处理转化漏斗',
        icon: Icons.filter_alt_outlined,
        items: [
          _InsightFunnelItem(
            label: '发现',
            value: task.progress.discovered,
            color: colors.primary,
          ),
          _InsightFunnelItem(
            label: '处理',
            value: task.progress.processed,
            color: OpenHandStatusColors.info,
          ),
          _InsightFunnelItem(
            label: '候选',
            value: task.progress.candidates,
            color: colors.tertiary,
          ),
          _InsightFunnelItem(
            label: '有效',
            value: task.progress.valid,
            color: OpenHandStatusColors.success,
          ),
          _InsightFunnelItem(
            label: '高价值',
            value: task.progress.highValue,
            color: colors.secondary,
            target: highValueResults.length == 1
                ? _ResultInsightTarget(highValueResults.single)
                : null,
          ),
        ],
      ),
      _TaskStageGanttSection(task: task),
      _Section(
        title: text(zh: '任务生命周期流', en: 'Task lifecycle flow'),
        icon: Icons.alt_route_rounded,
        child: _InsightFlowLane(
          nodes: [
            (
              icon: Icons.add_task_rounded,
              label: text(zh: '创建', en: 'Created'),
              value: task.createdAtReported
                  ? _shortDateTime(task.createdAt)
                  : text(zh: '时间未上报', en: 'Time not reported'),
              color: colors.primary,
            ),
            (
              icon: task.isTerminal
                  ? Icons.check_circle_outline_rounded
                  : Icons.play_circle_outline_rounded,
              label: task.isTerminal
                  ? text(zh: '最近阶段', en: 'Latest stage')
                  : text(zh: '活动阶段', en: 'Active stage'),
              value: _stageName(task.stage),
              color: task.isTerminal
                  ? _entityTerminalStageColor(task.stage, colors)
                  : OpenHandStatusColors.info,
            ),
            (
              icon: task.stage == 'failed'
                  ? Icons.error_outline_rounded
                  : task.stage == 'cancelled'
                  ? Icons.cancel_outlined
                  : task.stage == 'completed'
                  ? Icons.flag_rounded
                  : Icons.pending_actions_rounded,
              label: task.isTerminal
                  ? text(zh: '终态', en: 'Terminal state')
                  : text(zh: '等待终态', en: 'Awaiting terminal state'),
              value: task.isTerminal
                  ? _stageName(task.stage)
                  : text(zh: '执行中', en: 'Running'),
              color: task.isTerminal
                  ? _entityTerminalStageColor(task.stage, colors)
                  : colors.outline,
            ),
          ],
        ),
      ),
      _Section(
        title: '任务定义与运行状态',
        icon: Icons.settings_outlined,
        child: _OpsKeyValueGrid(
          children: [
            _OpsKeyValue(label: '任务 ID', value: task.id),
            _OpsKeyValue(label: '当前阶段', value: _stageName(task.stage)),
            _OpsKeyValue(
              label: '扫描模式',
              value: task.mode == AiExposureScanMode.full ? '全量扫描' : '增量扫描',
            ),
            _OpsKeyValue(
              label: '数据来源',
              value: task.sources.isEmpty
                  ? '历史记录缺少来源'
                  : task.sources.map(aiExposureSourceDisplayName).join(' / '),
            ),
            _OpsKeyValue(
              label: '授权范围',
              value: task.authorizedScope.isEmpty
                  ? task.mode == AiExposureScanMode.full
                        ? '公开来源全量范围'
                        : '未设置授权域'
                  : task.authorizedScope.join(' / '),
              maxLines: 4,
            ),
            _OpsKeyValue(
              label: '创建时间',
              value: _reportedShortDateTime(
                task.createdAt,
                task.createdAtReported,
                unavailable: '创建时间未上报',
              ),
            ),
            _OpsKeyValue(label: '开始时间', value: startedLabel, maxLines: 3),
            _OpsKeyValue(
              label: '最近更新',
              value: _reportedIsoDateTime(
                task.progress.updatedAt,
                task.progress.updatedAtReported,
                unavailable: '最近更新未上报',
              ),
            ),
            _OpsKeyValue(
              label: '终态时间边界',
              value: terminalBoundaryLabel,
              maxLines: 3,
            ),
            _OpsKeyValue(
              label: '实测执行耗时',
              value: measuredDuration == null
                  ? terminalBoundary == null
                        ? '执行中'
                        : '不可用：缺少 startedAt 或 finishedAt'
                  : '$measuredDuration ms',
            ),
            _OpsKeyValue(
              label: '恢复能力',
              value: task.isResumable ? '可恢复' : '无需恢复',
            ),
            _OpsKeyValue(
              label: '任务并发',
              value: task.concurrency == null
                  ? '旧版任务未记录'
                  : '${task.concurrency}',
            ),
            _OpsKeyValue(
              label: '验证模式',
              value: switch (task.validationMode) {
                AiExposureValidationMode.passive => '被动验证',
                AiExposureValidationMode.authorizedActive => '授权主动验证',
                null => '旧版任务未记录',
              },
            ),
            _OpsKeyValue(
              label: '论坛抓取模式',
              value: switch (task.forumFetchMode) {
                AiExposureForumFetchMode.jinaFallback => 'Jina 回退',
                AiExposureForumFetchMode.playwright => 'Playwright',
                AiExposureForumFetchMode.cdp => 'Chrome CDP',
                null => '旧版任务未记录',
              },
            ),
            _OpsKeyValue(
              label: 'GPT 辅助',
              value: task.gptAssisted == null
                  ? '旧版任务未记录'
                  : task.gptAssisted!
                  ? '已启用'
                  : '未启用',
            ),
          ],
        ),
      ),
      _Section(
        title: task.stageTimings.isEmpty ? '阶段时间线 · 历史任务无阶段切片' : '阶段时间线',
        icon: Icons.account_tree_outlined,
        child: Column(
          children: stages.indexed
              .map((entry) {
                final timing = task.stageTimings
                    .where((timing) => timing.stage == entry.$2)
                    .firstOrNull;
                return _StageRow(
                  stage: entry.$2,
                  taskId: task.id,
                  timing: timing,
                  completed:
                      timing?.finishedAt != null || timing?.durationMs != null,
                  active: entry.$2 == task.stage && !task.isTerminal,
                );
              })
              .toList(growable: false),
        ),
      ),
      _InsightRecordPanel(
        icon: Icons.fact_check_outlined,
        title: '关联扫描结果',
        records: results.map(_resultInsightRecord).toList(growable: false),
        emptyLabel: task.id.isEmpty ? '旧版任务没有稳定 ID，未自动关联结果。' : '该任务暂无已归档结果。',
      ),
      _InsightRecordPanel(
        icon: Icons.receipt_long_outlined,
        title: '关联运行事件',
        records: logs.map(_logInsightRecord).toList(growable: false),
        emptyLabel: task.id.isEmpty
            ? '旧版任务没有稳定 ID，未自动关联运行事件。'
            : '当前日志缓冲中没有该任务的运行事件。',
      ),
      _Section(
        title: '错误与恢复',
        icon: Icons.restart_alt_rounded,
        child: Column(
          children: [
            _OpsKeyValue(
              label: '错误摘要',
              value: task.errorMessage?.trim().isNotEmpty == true
                  ? _entitySafeText(task.errorMessage)
                  : task.stage == 'failed'
                  ? '失败上下文未上报'
                  : '未发生',
              maxLines: 6,
            ),
            _OpsKeyValue(
              label: '失败阶段',
              value: task.failureStage == null
                  ? task.stage == 'failed'
                        ? '失败阶段未上报'
                        : '未发生'
                  : _stageName(task.failureStage!),
            ),
            _OpsKeyValue(
              label: '最后检查点',
              value: task.lastCheckpointAt != null
                  ? task.lastCheckpointAt!.toLocal().toIso8601String()
                  : _reportedIsoDateTime(
                      task.progress.updatedAt,
                      task.progress.updatedAtReported,
                      unavailable: '最后检查点未上报',
                    ),
            ),
            _OpsKeyValue(
              label: '已处理进度',
              value: '${task.progress.processed}/${task.progress.total}',
            ),
            _OpsKeyValue(
              label: '恢复能力',
              value: task.isResumable ? '服务标记为可恢复' : '无需恢复',
            ),
            _OpsKeyValue(
              label: '取消时间',
              value: task.cancelledAt?.toLocal().toIso8601String() ?? '未发生',
            ),
            _OpsKeyValue(
              label: '取消原因',
              value: _entitySafeText(task.cancelReason, unavailable: '未发生'),
            ),
            _OpsKeyValue(label: '重试次数', value: '${task.retryCount ?? 0}'),
          ],
        ),
      ),
    ]);
  }
}

class _TaskStageGanttSection extends StatelessWidget {
  const _TaskStageGanttSection({required this.task});

  final AiExposureHistoryEntry task;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final entries = task.stageTimings
        .where(
          (timing) =>
              timing.durationMs != null ||
              timing.startedAt != null && timing.finishedAt != null,
        )
        .map((timing) {
          final start = timing.startedAt;
          final recordedEnd = timing.finishedAt;
          final derivedEnd =
              recordedEnd == null && start != null && timing.durationMs != null;
          final end =
              recordedEnd ??
              (derivedEnd
                  ? start.add(Duration(milliseconds: timing.durationMs!))
                  : null);
          final duration =
              timing.durationMs ??
              (start != null && end != null && !end.isBefore(start)
                  ? end.difference(start).inMilliseconds
                  : null);
          return (
            timing: timing,
            start: start,
            end: end,
            duration: duration,
            derivedEnd: derivedEnd,
          );
        })
        .where((entry) => entry.duration != null && entry.duration! >= 0)
        .toList(growable: false);
    final dated = entries
        .where((entry) => entry.start != null && entry.end != null)
        .toList(growable: false);
    final earliest = dated.map((entry) => entry.start!).fold<DateTime?>(null, (
      value,
      item,
    ) {
      if (value == null || item.isBefore(value)) return item;
      return value;
    });
    final latest = dated.map((entry) => entry.end!).fold<DateTime?>(null, (
      value,
      item,
    ) {
      if (value == null || item.isAfter(value)) return item;
      return value;
    });
    final spanMs = earliest == null || latest == null
        ? 0
        : latest.difference(earliest).inMilliseconds;
    final maxDuration = entries.fold<int>(
      0,
      (value, entry) => entry.duration! > value ? entry.duration! : value,
    );
    return _Section(
      title: '阶段执行甘特 · ${entries.length} 个计时切片',
      icon: Icons.view_timeline_outlined,
      child: entries.isEmpty
          ? const _InsightEmpty(label: '该任务没有可绘制的阶段计时切片。')
          : Column(
              children: entries
                  .map((entry) {
                    final hasCalendarPosition =
                        spanMs > 0 && entry.start != null && entry.end != null;
                    final rawLeft = hasCalendarPosition
                        ? entry.start!.difference(earliest!).inMilliseconds /
                              spanMs
                        : 0.0;
                    final left = rawLeft.clamp(0.0, 1.0).toDouble();
                    final rawCalendarWidth = hasCalendarPosition
                        ? entry.end!.difference(entry.start!).inMilliseconds /
                              spanMs
                        : 0.0;
                    final availableWidth = (1.0 - left).clamp(0.0, 1.0);
                    final width = hasCalendarPosition
                        ? rawCalendarWidth <= 0
                              ? 0.0
                              : rawCalendarWidth
                                    .clamp(0.0, availableWidth)
                                    .toDouble()
                        : maxDuration <= 0
                        ? 0.04
                        : (entry.duration! / maxDuration).clamp(0.04, 1.0);
                    final target = _StageInsightTarget(
                      entry.timing.stage,
                      taskId: task.id,
                    );
                    return ServiceInteractiveSurface(
                      onTap: () => _openInsightTarget(context, target),
                      tooltip: '查看${_stageName(entry.timing.stage)}阶段详情',
                      showDetailsIcon: false,
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _stageName(entry.timing.stage),
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                              ),
                              Text(
                                '${entry.duration} ms${entry.derivedEnd ? ' · 结束时间由耗时推导' : ''}',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: colors.onSurfaceVariant),
                              ),
                            ],
                          ),
                          kOpenHandGap7,
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final safeWidth = constraints.maxWidth;
                              return SizedBox(
                                height: 18,
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: colors.surfaceContainerHighest,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      left: (safeWidth * left).clamp(
                                        0.0,
                                        (safeWidth - 2).clamp(0.0, safeWidth),
                                      ),
                                      top: 0,
                                      bottom: 0,
                                      width: width <= 0
                                          ? 2.0.clamp(0.0, safeWidth)
                                          : (safeWidth * width).clamp(
                                              2.0,
                                              safeWidth,
                                            ),
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: colors.primary.withValues(
                                            alpha: 0.8,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          if (!hasCalendarPosition) ...[
                            kOpenHandGap4,
                            Text(
                              '仅记录耗时，条形表示相对时长，不代表绝对开始时间。',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                    );
                  })
                  .toList(growable: false),
            ),
    );
  }
}

class _SourceEntityInsightBody extends StatelessWidget {
  const _SourceEntityInsightBody({required this.source});

  final AiExposureSource source;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ServicesController>();
    final colors = Theme.of(context).colorScheme;
    final requiresCredential = _sourceRequiresCredential(source);
    final configured = _sourceAccessConfigured(controller, source);
    final enabled = controller.enabledSources.contains(source);
    final quotaNotApplicable = source == AiExposureSource.manual;
    final quota = controller.quotas
        .where((entry) => entry.source == _sourceQuotaKey(source))
        .firstOrNull;
    final capacityFallback = quotaNotApplicable
        ? '不适用'
        : !configured
        ? '待配置后获取'
        : quota == null
        ? '等待状态刷新'
        : '接口未提供';
    final probeFallback = quotaNotApplicable
        ? '不适用'
        : !configured
        ? '待配置后探测'
        : quota == null
        ? '等待状态刷新'
        : '等待首次探测';
    final tasks = controller.history
        .where((task) => task.sources.contains(source))
        .toList(growable: false);
    final results = controller.results
        .where((result) => result.source == source)
        .toList(growable: false);
    final chronologicalTasks = [...tasks]
      ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
    final valuable = results
        .where(
          (result) =>
              result.category == AiExposureResultCategory.valid ||
              result.category == AiExposureResultCategory.highValue,
        )
        .length;
    return _metricInsightPage([
      _InsightKpiBand(
        title: '来源执行概览',
        icon: aiExposureSourceIcon(source),
        items: [
          _InsightKpi(
            icon: Icons.settings_outlined,
            label: '访问前置',
            value: configured ? '已满足' : '未满足',
            helper: requiresCredential ? '需要访问凭证' : '无需 API 凭证',
            color: configured
                ? OpenHandStatusColors.success
                : OpenHandStatusColors.warning,
          ),
          _InsightKpi(
            icon: Icons.toggle_on_rounded,
            label: '任务状态',
            value: enabled ? '已启用' : '未启用',
            helper: '${tasks.length} 个关联任务',
            color: enabled ? colors.primary : colors.outline,
          ),
          _InsightKpi(
            icon: Icons.data_usage_rounded,
            label: '配额状态',
            value: quotaNotApplicable
                ? '不适用'
                : !configured
                ? '待配置'
                : quota == null
                ? '待刷新'
                : quota.available
                ? '可用'
                : '异常',
            helper: quota?.remaining == null
                ? quota?.message.trim().isNotEmpty == true
                      ? _entitySafeText(quota!.message)
                      : capacityFallback
                : '剩余 ${quota!.remaining}/${quota.limit ?? '--'}',
            color: quota?.available == true
                ? OpenHandStatusColors.success
                : quota == null
                ? colors.outline
                : OpenHandStatusColors.warning,
          ),
          _InsightKpi(
            icon: Icons.fact_check_outlined,
            label: '有效产出',
            value: '$valuable',
            helper: '共 ${results.length} 条结果',
            color: OpenHandStatusColors.info,
          ),
        ],
      ),
      _InsightTrendSection(
        title: '来源任务处理表现 · 当前保留任务',
        icon: Icons.show_chart_rounded,
        series: [
          OpenHandChartSeries(
            label: '已处理',
            values: chronologicalTasks
                .map((task) => task.progress.processed.toDouble())
                .toList(growable: false),
            color: colors.primary,
          ),
          OpenHandChartSeries(
            label: '有效',
            values: chronologicalTasks
                .map((task) => task.progress.valid.toDouble())
                .toList(growable: false),
            color: OpenHandStatusColors.success,
          ),
        ],
        sampleLabels: chronologicalTasks
            .map(
              (task) => _reportedShortDateTime(
                task.createdAt,
                task.createdAtReported,
              ),
            )
            .toList(growable: false),
        suffix: ' 项',
        emptyLabel: '当前保留任务中没有该来源的处理样本。',
        targets: chronologicalTasks
            .map<_InsightTarget?>((task) => _TaskInsightTarget(task))
            .toList(growable: false),
      ),
      _InsightDonutSection(
        title: '来源产出质量 · 当前保留结果',
        icon: Icons.donut_large_rounded,
        items: [
          _DistributionItem(
            '有效',
            results
                .where(
                  (result) => result.category == AiExposureResultCategory.valid,
                )
                .length,
            OpenHandStatusColors.success,
            key: AiExposureResultCategory.valid,
          ),
          _DistributionItem(
            '高价值',
            results
                .where(
                  (result) =>
                      result.category == AiExposureResultCategory.highValue,
                )
                .length,
            colors.secondary,
            key: AiExposureResultCategory.highValue,
          ),
          _DistributionItem(
            '可疑',
            results
                .where(
                  (result) =>
                      result.category == AiExposureResultCategory.suspicious,
                )
                .length,
            OpenHandStatusColors.warning,
            key: AiExposureResultCategory.suspicious,
          ),
          _DistributionItem(
            '蜜罐',
            results
                .where(
                  (result) =>
                      result.category == AiExposureResultCategory.honeypot,
                )
                .length,
            OpenHandStatusColors.error,
            key: AiExposureResultCategory.honeypot,
          ),
        ],
        detailBuilder: (context, item) {
          final category = item.key! as AiExposureResultCategory;
          return _InsightRecordPanel(
            icon: Icons.fact_check_outlined,
            title: '${item.label}结果 · 当前保留集合',
            records: results
                .where((result) => result.category == category)
                .map(
                  (result) =>
                      _resultInsightRecord(result, _ResultRecordLens.source),
                )
                .toList(growable: false),
            emptyLabel: '当前保留结果中没有${item.label}记录。',
          );
        },
      ),
      _Section(
        title: '配额与来源状态 · 最近状态刷新快照',
        icon: Icons.rule_folder_outlined,
        child: _OpsKeyValueGrid(
          children: [
            _OpsKeyValue(label: '来源标识', value: source.id),
            _OpsKeyValue(
              label: '凭证要求',
              value: requiresCredential ? '需要' : '无需',
            ),
            _OpsKeyValue(label: '凭证配置', value: configured ? '已配置' : '待配置'),
            _OpsKeyValue(label: '任务启用', value: enabled ? '已启用' : '未启用'),
            _OpsKeyValue(
              label: '配额上限',
              value: quota?.limit == null
                  ? capacityFallback
                  : '${quota!.limit}',
            ),
            _OpsKeyValue(
              label: '剩余配额',
              value: quota?.remaining == null
                  ? capacityFallback
                  : '${quota!.remaining}',
            ),
            _OpsKeyValue(
              label: '配额重置',
              value: quota?.resetsAt == null
                  ? capacityFallback
                  : _shortDateTime(quota!.resetsAt!),
            ),
            _OpsKeyValue(
              label: '最近探测',
              value: quota?.checkedAt == null
                  ? probeFallback
                  : quota!.checkedAt!.toLocal().toIso8601String(),
            ),
            _OpsKeyValue(
              label: '探测耗时',
              value: quota?.latencyMs == null
                  ? probeFallback
                  : '${quota!.latencyMs} ms',
            ),
            _OpsKeyValue(
              label: 'HTTP 状态',
              value: quota?.httpStatus == null
                  ? quotaNotApplicable || !requiresCredential
                        ? '不适用'
                        : !configured
                        ? '未发起（凭证缺失）'
                        : quota == null
                        ? '等待状态刷新'
                        : '探测未返回状态码'
                  : '${quota!.httpStatus}',
            ),
            _OpsKeyValue(
              label: '错误码',
              value: quotaNotApplicable
                  ? '不适用'
                  : quota == null
                  ? probeFallback
                  : quota.available
                  ? '未发生'
                  : quota.errorCode ?? '未分类',
            ),
            _OpsKeyValue(
              label: '最近成功探测',
              value: quota?.lastSuccessAt == null
                  ? quota?.available == true
                        ? quota!.checkedAt?.toLocal().toIso8601String() ??
                              probeFallback
                        : '尚无成功探测'
                  : quota!.lastSuccessAt!.toLocal().toIso8601String(),
            ),
            _OpsKeyValue(
              label: '最近失败探测',
              value: quota?.lastFailureAt == null
                  ? quota?.available == true
                        ? '未发生'
                        : probeFallback
                  : quota!.lastFailureAt!.toLocal().toIso8601String(),
            ),
            _OpsKeyValue(
              label: '状态消息',
              value: quota?.message.trim().isNotEmpty == true
                  ? _entitySafeText(quota!.message)
                  : quotaNotApplicable
                  ? '手工目标不执行来源配额探测。'
                  : probeFallback,
              maxLines: 4,
            ),
          ],
        ),
      ),
      _InsightRecordPanel(
        icon: Icons.work_history_outlined,
        title: '来源关联任务',
        records: tasks
            .map((task) => _taskInsightRecord(task, _TaskRecordLens.scope))
            .toList(growable: false),
        emptyLabel: '该来源暂无关联任务。',
      ),
      _InsightRecordPanel(
        icon: Icons.fact_check_outlined,
        title: '来源产出结果',
        records: results
            .map(
              (result) =>
                  _resultInsightRecord(result, _ResultRecordLens.source),
            )
            .toList(growable: false),
        emptyLabel: '该来源暂无已归档结果。',
      ),
    ]);
  }
}

class _ProxyEndpointEntityInsightBody extends StatelessWidget {
  const _ProxyEndpointEntityInsightBody({required this.endpointId});

  final String endpointId;

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    final controller = context.watch<ServicesController>();
    final endpoint = controller.proxyConfiguration.endpoints
        .where((entry) => entry.runtimeId == endpointId)
        .firstOrNull;
    if (endpoint == null) return const _InsightEmpty(label: '该代理节点已不在当前配置中。');
    final colors = Theme.of(context).colorScheme;
    final statistics = _proxyEndpointStatistics(
      endpoint,
      _proxyRuntimeById(controller),
    );
    final sample = endpoint.latestSample;
    final identity = endpoint.identity;
    final recentLatencies = statistics.recentRequests
        .map((request) => request.responseTimeMs)
        .toList(growable: false);
    final p95 = _latencyPercentile([...recentLatencies], 0.95);
    final recentAverage = recentLatencies.isEmpty
        ? 0
        : recentLatencies.reduce((left, right) => left + right) ~/
              recentLatencies.length;
    final requests = [...statistics.recentRequests]
      ..sort((left, right) => right.at.compareTo(left.at));
    final chronologicalRequests = requests.reversed.toList(growable: false);
    var successfulSoFar = 0;
    final reliabilityValues = chronologicalRequests.indexed
        .map((entry) {
          if (entry.$2.succeeded) successfulSoFar++;
          return successfulSoFar * 100 / (entry.$1 + 1);
        })
        .toList(growable: false);
    final probes = [...endpoint.samples]
      ..sort((left, right) => right.checkedAt.compareTo(left.checkedAt));
    final successfulRequests = requests
        .where((request) => request.succeeded)
        .length;
    final timeoutRequests = requests
        .where((request) => request.timedOut)
        .length;
    final failedRequests =
        requests.length - successfulRequests - timeoutRequests;
    final reachableProbes = probes.where((probe) => probe.reachable).length;
    final failedProbes = probes.length - reachableProbes;
    return _metricInsightPage([
      _InsightKpiBand(
        title: '节点请求质量',
        icon: Icons.monitor_heart_outlined,
        items: [
          _InsightKpi(
            icon: Icons.swap_vert_rounded,
            label: '累计请求',
            value: '${statistics.requests}',
            helper: '执行中 ${statistics.inFlight}',
            color: colors.primary,
          ),
          _InsightKpi(
            icon: Icons.task_alt_rounded,
            label: '成功率',
            value: _chartRate(statistics.successes, statistics.completed),
            helper: '${statistics.successes}/${statistics.completed}',
            color: OpenHandStatusColors.success,
          ),
          _InsightKpi(
            icon: Icons.speed_rounded,
            label: '近期平均 / P95',
            value: recentLatencies.isEmpty
                ? '暂无请求样本'
                : '$recentAverage / $p95 ms',
            helper: '最近 ${recentLatencies.length} 条保留请求',
            color: colors.tertiary,
          ),
          _InsightKpi(
            icon: Icons.warning_amber_rounded,
            label: '异常请求',
            value: '${statistics.failures + statistics.timeouts}',
            helper: '连续失败 ${statistics.consecutiveFailures}',
            color: OpenHandStatusColors.warning,
          ),
        ],
      ),
      _InsightTrendSection(
        title: '近期请求时延 · 保留 ${chronologicalRequests.length} 条样本',
        icon: Icons.show_chart_rounded,
        series: [
          OpenHandChartSeries(
            label: '响应耗时',
            values: chronologicalRequests
                .map((request) => request.responseTimeMs.toDouble())
                .toList(growable: false),
            color: colors.tertiary,
          ),
        ],
        sampleLabels: chronologicalRequests
            .map(
              (request) =>
                  _reportedShortDateTime(request.at, request.atReported),
            )
            .toList(growable: false),
        suffix: ' ms',
        emptyLabel: '该节点没有近期请求时延样本。',
        interpolation: OpenHandChartInterpolation.smooth,
        targets: chronologicalRequests
            .map<_InsightTarget?>(
              (request) => _ProxyRequestInsightTarget(
                endpoint: endpoint,
                address: endpoint.maskedUrl,
                sample: request,
              ),
            )
            .toList(growable: false),
      ),
      _InsightTrendSection(
        title: text(
          zh: '近期请求可靠性 · 累计成功率',
          en: 'Recent request reliability · cumulative success rate',
        ),
        icon: Icons.monitor_heart_outlined,
        series: [
          OpenHandChartSeries(
            label: text(zh: '累计成功率', en: 'Cumulative success rate'),
            values: reliabilityValues,
            color: OpenHandStatusColors.success,
          ),
        ],
        sampleLabels: chronologicalRequests
            .map(
              (request) =>
                  _reportedShortDateTime(request.at, request.atReported),
            )
            .toList(growable: false),
        suffix: '%',
        emptyLabel: text(
          zh: '该节点没有近期请求可靠性样本。',
          en: 'This node has no recent request reliability samples.',
        ),
        targets: chronologicalRequests
            .map<_InsightTarget?>(
              (request) => _ProxyRequestInsightTarget(
                endpoint: endpoint,
                address: endpoint.maskedUrl,
                sample: request,
              ),
            )
            .toList(growable: false),
      ),
      _InsightDonutSection(
        title: '近期请求结果 · 当前保留窗口',
        icon: Icons.donut_large_rounded,
        items: [
          _DistributionItem(
            '成功',
            successfulRequests,
            OpenHandStatusColors.success,
          ),
          _DistributionItem('失败', failedRequests, OpenHandStatusColors.error),
          _DistributionItem(
            '超时',
            timeoutRequests,
            OpenHandStatusColors.warning,
          ),
        ],
        detailBuilder: (context, item) {
          final selected = requests.where((request) {
            if (item.label == '成功') return request.succeeded;
            if (item.label == '超时') return request.timedOut;
            return !request.succeeded && !request.timedOut;
          });
          return _InsightRecordPanel(
            icon: Icons.swap_vert_rounded,
            title: '${item.label}请求 · 当前保留窗口',
            records: selected
                .map((request) => _proxyRequestRecord(endpoint, request))
                .toList(growable: false),
            emptyLabel: '当前保留窗口中没有${item.label}请求。',
          );
        },
      ),
      _InsightDonutSection(
        title: '巡检可靠性 · 保留 ${probes.length} 条样本',
        icon: Icons.health_and_safety_outlined,
        items: [
          _DistributionItem(
            '可达',
            reachableProbes,
            OpenHandStatusColors.success,
          ),
          _DistributionItem('异常', failedProbes, OpenHandStatusColors.error),
        ],
        detailBuilder: (context, item) {
          final selected = probes.where(
            (probe) => item.label == '可达' ? probe.reachable : !probe.reachable,
          );
          return _InsightRecordPanel(
            icon: Icons.health_and_safety_outlined,
            title: '${item.label}巡检 · 当前保留窗口',
            records: selected
                .map((probe) => _proxyProbeRecord(endpoint, probe))
                .toList(growable: false),
            emptyLabel: '当前保留窗口中没有${item.label}巡检。',
          );
        },
      ),
      _Section(
        title: '节点配置与出口身份',
        icon: Icons.dns_outlined,
        child: _OpsKeyValueGrid(
          children: [
            _OpsKeyValue(label: '代理地址', value: endpoint.maskedUrl),
            _OpsKeyValue(
              label: '配置状态',
              value: endpoint.enabled ? '已启用' : '未启用',
            ),
            _OpsKeyValue(
              label: '最近巡检',
              value: sample == null
                  ? '等待首次巡检'
                  : _reportedShortDateTime(
                      sample.checkedAt,
                      sample.checkedAtReported,
                      unavailable: '巡检时间未上报',
                    ),
            ),
            _OpsKeyValue(
              label: '巡检结果',
              value: sample == null
                  ? '等待首次巡检'
                  : sample.reachable
                  ? '转发可用'
                  : sample.error?.trim().isNotEmpty == true
                  ? _entitySafeText(sample.error)
                  : '转发不可用',
              maxLines: 4,
            ),
            _OpsKeyValue(
              label: '出口 IP',
              value: identity?.exitIp.trim().isNotEmpty == true
                  ? identity!.exitIp
                  : '等待首次出口识别',
            ),
            _OpsKeyValue(
              label: '出口地域',
              value: identity?.location.isNotEmpty == true
                  ? identity!.location
                  : '等待首次出口识别',
            ),
            _OpsKeyValue(
              label: '网络组织',
              value: identity == null
                  ? '等待首次出口识别'
                  : [
                      identity.isp,
                      identity.organization,
                      identity.asn,
                    ].where((value) => value.trim().isNotEmpty).join(' / '),
            ),
          ],
        ),
      ),
      _InsightRecordPanel(
        icon: Icons.swap_vert_rounded,
        title: '节点请求时间线',
        records: requests
            .map((request) => _proxyRequestRecord(endpoint, request))
            .toList(growable: false),
        emptyLabel: '该节点暂无近期请求样本。',
      ),
      _InsightRecordPanel(
        icon: Icons.health_and_safety_outlined,
        title: '节点巡检时间线',
        records: probes
            .map((probe) => _proxyProbeRecord(endpoint, probe))
            .toList(growable: false),
        emptyLabel: '该节点暂无巡检样本。',
      ),
    ]);
  }
}

void _showResultEntityInsightById(
  BuildContext context, {
  required String resultId,
  AiExposureResult? legacySnapshot,
}) {
  final text = openHandTextResolver(context);
  final result = resultId.isEmpty
      ? legacySnapshot
      : context
            .read<ServicesController>()
            .results
            .where((entry) => entry.id == resultId)
            .firstOrNull;
  showAnimatedDialog<void>(
    context: context,
    builder: (_) => _OperationsInsightDialog(
      icon: Icons.fact_check_outlined,
      title: result == null
          ? text(zh: '结果 $resultId', en: 'Result $resultId')
          : _resultDisplayName(result),
      subtitle: '结果身份、风险与完整证据',
      color: result == null
          ? Theme.of(context).colorScheme.outline
          : _resultEntityColor(result.category),
      entity: true,
      child: _ResultEntityInsightBody(
        resultId: resultId,
        legacySnapshot: legacySnapshot,
      ),
    ),
  );
}

void _showLogEntityInsight(BuildContext context, AiExposureLogEntry entry) {
  showAnimatedDialog<void>(
    context: context,
    builder: (_) => _OperationsInsightDialog(
      icon: Icons.terminal_rounded,
      title: '日志事件',
      subtitle: '原始消息与任务上下文',
      color: _logColor(entry.level),
      entity: true,
      child: _LogEntityInsightBody(entry: entry),
    ),
  );
}

void _showRuleEntityInsightById(
  BuildContext context, {
  required String ruleId,
  AiExposureScanRule? legacySnapshot,
}) {
  final text = openHandTextResolver(context);
  final rule = ruleId.isEmpty
      ? legacySnapshot
      : context
            .read<ServicesController>()
            .rules
            .where((entry) => entry.id == ruleId)
            .firstOrNull;
  showAnimatedDialog<void>(
    context: context,
    builder: (_) => _OperationsInsightDialog(
      icon: Icons.rule_rounded,
      title: rule == null
          ? text(zh: '规则 $ruleId', en: 'Rule $ruleId')
          : rule.vendor.trim().isEmpty
          ? rule.id
          : rule.vendor.trim(),
      subtitle: '规则身份、识别模式与验证端点',
      color: rule?.enabled == true
          ? OpenHandStatusColors.success
          : Theme.of(context).colorScheme.outline,
      entity: true,
      child: _RuleEntityInsightBody(
        ruleId: ruleId,
        legacySnapshot: legacySnapshot,
      ),
    ),
  );
}

void _showProxyRequestEntityInsight(
  BuildContext context, {
  required AiExposureProxyEndpoint? endpoint,
  required String address,
  required AiExposureProxyRequestSample sample,
}) {
  showAnimatedDialog<void>(
    context: context,
    builder: (_) => _OperationsInsightDialog(
      icon: sample.succeeded
          ? Icons.check_circle_outline_rounded
          : sample.timedOut
          ? Icons.timer_off_outlined
          : Icons.error_outline_rounded,
      title: endpoint?.displayName ?? '代理请求样本',
      subtitle: '请求结果、时延与出口上下文',
      color: sample.succeeded
          ? OpenHandStatusColors.success
          : sample.timedOut
          ? OpenHandStatusColors.warning
          : OpenHandStatusColors.error,
      entity: true,
      child: _ProxyRequestEntityInsightBody(
        endpointId: endpoint?.runtimeId ?? sample.endpointId,
        address: address,
        sample: sample,
      ),
    ),
  );
}

void _showProxyProbeEntityInsight(
  BuildContext context, {
  required AiExposureProxyEndpoint endpoint,
  required AiExposureProxyProbeSample sample,
}) {
  showAnimatedDialog<void>(
    context: context,
    builder: (_) => _OperationsInsightDialog(
      icon: sample.reachable
          ? Icons.health_and_safety_outlined
          : Icons.report_problem_outlined,
      title: endpoint.displayName,
      subtitle: '代理巡检步骤与故障定位',
      color: sample.reachable
          ? OpenHandStatusColors.success
          : OpenHandStatusColors.error,
      entity: true,
      child: _ProxyProbeEntityInsightBody(
        endpointId: endpoint.runtimeId,
        sample: sample,
      ),
    ),
  );
}

void _showStageEntityInsight(
  BuildContext context, {
  required String stage,
  String? taskId,
}) {
  showAnimatedDialog<void>(
    context: context,
    builder: (_) => _OperationsInsightDialog(
      icon: Icons.route_rounded,
      title: _stageName(stage),
      subtitle: '阶段职责、输入输出与任务状态',
      entity: true,
      child: _StageEntityInsightBody(stage: stage, taskId: taskId),
    ),
  );
}

void _showDependencyEntityInsight(
  BuildContext context, {
  required _DependencyInsightId id,
  required String name,
  required bool? configured,
  required bool? connected,
  required String message,
}) {
  showAnimatedDialog<void>(
    context: context,
    builder: (_) => _OperationsInsightDialog(
      icon: Icons.account_tree_outlined,
      title: name,
      subtitle: '依赖配置、连接证据与影响',
      color: connected == true
          ? OpenHandStatusColors.success
          : configured == true
          ? OpenHandStatusColors.warning
          : Theme.of(context).colorScheme.outline,
      entity: true,
      child: _DependencyEntityInsightBody(
        id: id,
        name: name,
        configured: configured,
        connected: connected,
        message: message,
      ),
    ),
  );
}

class _ResultEntityInsightBody extends StatelessWidget {
  const _ResultEntityInsightBody({
    required this.resultId,
    required this.legacySnapshot,
  });

  final String resultId;
  final AiExposureResult? legacySnapshot;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ServicesController>();
    final result = resultId.isEmpty
        ? legacySnapshot
        : controller.results.where((entry) => entry.id == resultId).firstOrNull;
    if (result == null) return const _InsightEmpty(label: '该结果已不在当前结果集合中。');
    final colors = Theme.of(context).colorScheme;
    final task = controller.history
        .where((entry) => entry.id == result.jobId)
        .firstOrNull;
    final category = _resultEntityCategory(result.category);
    final fingerprint = result.responseFingerprint.trim();
    final related =
        fingerprint.isEmpty
              ? const <AiExposureResult>[]
              : controller.results
                    .where(
                      (entry) =>
                          entry.responseFingerprint.trim() == fingerprint,
                    )
                    .toList()
          ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return _metricInsightPage([
      _InsightKpiBand(
        title: '结果风险快照',
        icon: Icons.security_outlined,
        items: [
          _InsightKpi(
            icon: Icons.category_outlined,
            label: '结果类别',
            value: category,
            helper: '当前记录分类',
            color: _resultEntityColor(result.category),
          ),
          _InsightKpi(
            icon: Icons.fingerprint_rounded,
            label: '同指纹保留记录',
            value: fingerprint.isEmpty ? '不可用' : '${related.length}',
            helper: fingerprint.isEmpty ? '当前结果未上报指纹' : '当前结果集合，非全库关系',
            color: colors.primary,
          ),
          _InsightKpi(
            icon: Icons.model_training_outlined,
            label: '模型数',
            value: '${result.modelCount}',
            helper: '服务返回值',
            color: OpenHandStatusColors.info,
          ),
          _InsightKpi(
            icon: Icons.link_outlined,
            label: '证据数',
            value: '${result.evidence.length}',
            helper: result.evidence.isEmpty ? '当前记录未保留证据' : '按服务保存顺序展示',
            color: OpenHandStatusColors.success,
          ),
        ],
      ),
      _InsightMatrixSection(
        title: '同响应指纹保留关系矩阵',
        icon: Icons.grid_view_rounded,
        rows: related
            .map(
              (entry) => _InsightMatrixRow(
                icon: Icons.fact_check_outlined,
                title: _entitySafeText(_resultDisplayName(entry)),
                subtitle:
                    '结果 ${_entitySafeText(entry.id)} · ${_reportedShortDateTime(entry.createdAt, entry.createdAtReported, unavailable: '创建时间未上报')}',
                color: _resultEntityColor(entry.category),
                target: _ResultInsightTarget(entry),
                cells: [
                  _InsightMatrixCell(
                    label: entry.id == result.id ? '当前记录' : '同指纹',
                    color: entry.id == result.id
                        ? colors.primary
                        : OpenHandStatusColors.info,
                  ),
                  _InsightMatrixCell(
                    label: _resultEntityCategory(entry.category),
                    color: _resultEntityColor(entry.category),
                  ),
                  _InsightMatrixCell(
                    label:
                        '主机 ${_entitySafeText(entry.host, unavailable: '未记录')}',
                    color: colors.tertiary,
                  ),
                  _InsightMatrixCell(
                    label: '证据 ${entry.evidence.length}',
                    color: OpenHandStatusColors.success,
                  ),
                ],
              ),
            )
            .toList(growable: false),
        emptyLabel: fingerprint.isEmpty
            ? '当前结果未保留响应指纹，无法建立关系矩阵。'
            : '当前保留结果中没有同指纹记录。',
      ),
      _entityFacts(
        title: '身份与来源',
        icon: Icons.badge_outlined,
        fields: [
          ('结果 ID', _entitySafeText(result.id)),
          (
            '任务 ID',
            result.jobId.isEmpty ? '记录缺少关联任务' : _entitySafeText(result.jobId),
          ),
          (
            '创建时间',
            _reportedIsoDateTime(
              result.createdAt,
              result.createdAtReported,
              unavailable: '创建时间未上报',
            ),
          ),
          ('来源', aiExposureSourceDisplayName(result.source)),
          ('URL', _entitySafeUrl(result.url)),
          ('主机', _entitySafeText(result.host, unavailable: '记录字段缺失')),
          ('产品', _entitySafeText(result.product, unavailable: '未识别产品')),
          ('类别', category),
          ('凭证状态', aiExposureCredentialStateName(result.credentialState)),
          (
            '脱敏凭证',
            _entitySafeText(result.maskedCredential, unavailable: '无可展示凭证'),
          ),
          (
            '余额摘要',
            _entitySafeText(result.balanceSummary, unavailable: '服务未返回余额信息'),
          ),
        ],
      ),
      _entityFacts(
        title: '指纹与重复影响',
        icon: Icons.fingerprint_rounded,
        fields: [
          (
            '响应指纹',
            _entitySafeText(result.responseFingerprint, unavailable: '记录字段缺失'),
          ),
          ('重复响应主机', '${result.duplicateResponseHosts}'),
          ('重复凭证主机', '${result.duplicateKeyHosts}'),
          ('矩阵边界', fingerprint.isEmpty ? '未建立' : '仅当前结果集合 ${related.length} 条'),
        ],
      ),
      _entityTextList(
        title: '有序证据链（服务保存顺序）',
        icon: Icons.link_outlined,
        values: result.evidence.map(_entitySafeText).toList(growable: false),
        emptyLabel: '该结果没有保留证据记录。',
      ),
      _InsightRecordPanel(
        icon: Icons.radar_rounded,
        title: '关联任务',
        records: task == null
            ? const <_InsightRecord>[]
            : <_InsightRecord>[_taskInsightRecord(task)],
        emptyLabel: '关联任务不在当前任务历史中。',
        maxEntries: 1,
      ),
    ]);
  }
}

class _LogEntityInsightBody extends StatelessWidget {
  const _LogEntityInsightBody({required this.entry});

  final AiExposureLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    final controller = context.watch<ServicesController>();
    final colors = Theme.of(context).colorScheme;
    final task = controller.history
        .where((item) => item.id == entry.jobId)
        .firstOrNull;
    final traceId = entry.traceId?.trim() ?? '';
    final traceEntries =
        traceId.isEmpty
              ? <AiExposureLogEntry>[]
              : controller.logs
                    .where((item) => item.traceId?.trim() == traceId)
                    .toList()
          ..sort((left, right) => right.at.compareTo(left.at));
    final unspecifiedModule = text(zh: '未标明模块', en: 'Unspecified module');
    final unspecifiedEvent = text(zh: '未标明事件', en: 'Unspecified event');
    final aggregateCounts = <String, int>{};
    for (final item in controller.logs) {
      final module = item.module?.trim().isNotEmpty == true
          ? item.module!.trim()
          : unspecifiedModule;
      final eventCode = item.eventCode?.trim().isNotEmpty == true
          ? item.eventCode!.trim()
          : unspecifiedEvent;
      aggregateCounts.update(
        '$module / $eventCode',
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final traceRecords = traceEntries
        .map(
          (item) => _InsightRecord(
            icon: item.level == 'error'
                ? Icons.error_outline_rounded
                : item.level == 'warning'
                ? Icons.warning_amber_rounded
                : Icons.terminal_rounded,
            title:
                '${_entitySafeText(item.module, unavailable: unspecifiedModule)} · ${_entitySafeText(item.eventCode, unavailable: unspecifiedEvent)}',
            subtitle: _entitySafeText(item.message, unavailable: '日志消息为空'),
            tags: [
              _logLevelName(context, item.level),
              _reportedShortDateTime(item.at, item.atReported),
              if (item.jobId.isNotEmpty) '任务 ${_entitySafeText(item.jobId)}',
            ],
            color: _logColor(item.level),
            target: _LogInsightTarget(item),
          ),
        )
        .toList(growable: false);
    return _metricInsightPage([
      _InsightKpiBand(
        title: '日志事件快照',
        icon: Icons.terminal_rounded,
        items: [
          _InsightKpi(
            icon: Icons.flag_outlined,
            label: '级别',
            value: _logLevelName(context, entry.level),
            helper: '当前事件字段',
            color: _logColor(entry.level),
          ),
          _InsightKpi(
            icon: Icons.route_outlined,
            label: '同追踪保留事件',
            value: traceId.isEmpty ? '不可用' : '${traceEntries.length}',
            helper: traceId.isEmpty ? '当前事件未关联追踪 ID' : '当前日志缓冲，按时间倒序',
            color: colors.primary,
          ),
          _InsightKpi(
            icon: Icons.data_object_rounded,
            label: '元数据字段',
            value: '${entry.metadata.length}',
            helper: entry.metadata.isEmpty ? '当前事件未保留元数据' : '字段名已排序',
            color: OpenHandStatusColors.info,
          ),
          _InsightKpi(
            icon: Icons.work_outline_rounded,
            label: '任务关联',
            value: entry.jobId.isEmpty ? '系统日志' : '已关联',
            helper: entry.jobId.isEmpty ? '没有任务 ID' : '可打开关联任务',
            color: entry.jobId.isEmpty
                ? colors.outline
                : OpenHandStatusColors.success,
          ),
        ],
      ),
      _InsightTimelineSection(
        title: '同追踪保留时间线',
        icon: Icons.timeline_rounded,
        entries: traceEntries
            .where((item) => item.atReported)
            .map(
              (item) => _InsightTimelineEntry(
                at: item.at,
                title:
                    '${_entitySafeText(item.module, unavailable: '未标明模块')} · ${_entitySafeText(item.eventCode, unavailable: '未标明事件')}',
                detail: _entitySafeText(item.message, unavailable: '日志消息为空'),
                color: _logColor(item.level),
                tag: _logLevelName(context, item.level),
                target: _LogInsightTarget(item),
              ),
            )
            .toList(growable: false),
        emptyLabel: traceId.isEmpty
            ? '该日志未关联追踪 ID，无法建立同追踪时间线。'
            : '当前日志缓冲没有同追踪事件。',
      ),
      _InsightRankingSection(
        title: text(
          zh: '模块 / 事件码聚合 · 当前日志缓冲',
          en: 'Module / event-code aggregation · current log buffer',
        ),
        icon: Icons.leaderboard_outlined,
        items: aggregateCounts.entries
            .map(
              (aggregate) => _InsightRankItem(
                label: aggregate.key,
                value: aggregate.value.toDouble(),
                valueLabel: text(
                  zh: '${aggregate.value} 条',
                  en: '${aggregate.value} records',
                ),
                color: colors.primary,
                key: aggregate.key,
              ),
            )
            .toList(growable: false),
        emptyLabel: text(
          zh: '当前日志缓冲没有可聚合记录。',
          en: 'The current log buffer has no records to aggregate.',
        ),
        detailBuilder: (context, item) {
          final parts = '${item.key}'.split(' / ');
          final module = parts.first;
          final eventCode = parts.length > 1 ? parts[1] : unspecifiedEvent;
          final matches = controller.logs.where((log) {
            final logModule = log.module?.trim().isNotEmpty == true
                ? log.module!.trim()
                : unspecifiedModule;
            final logEvent = log.eventCode?.trim().isNotEmpty == true
                ? log.eventCode!.trim()
                : unspecifiedEvent;
            return logModule == module && logEvent == eventCode;
          });
          return _InsightRecordPanel(
            icon: Icons.receipt_long_outlined,
            title: text(zh: '${item.label} 日志', en: '${item.label} logs'),
            records: matches.map(_logInsightRecord).toList(growable: false),
            emptyLabel: text(
              zh: '当前日志缓冲没有对应记录。',
              en: 'The current log buffer has no matching records.',
            ),
            maxEntries: 50,
          );
        },
      ),
      _InsightRecordPanel(
        icon: Icons.list_alt_rounded,
        title: '同追踪模块 / 事件记录',
        records: traceRecords,
        emptyLabel: traceId.isEmpty ? '该日志未关联追踪 ID。' : '当前保留窗口没有同追踪记录。',
      ),
      _entityFacts(
        title: '事件字段',
        icon: Icons.receipt_long_outlined,
        fields: [
          (
            '时间',
            _reportedIsoDateTime(
              entry.at,
              entry.atReported,
              unavailable: '事件时间未上报',
            ),
          ),
          ('级别', _logLevelName(context, entry.level)),
          (
            '任务 ID',
            entry.jobId.isEmpty ? '系统日志' : _entitySafeText(entry.jobId),
          ),
          ('日志 ID', _entitySafeText(entry.id, unavailable: '旧版日志未记录')),
          ('模块', _entitySafeText(entry.module, unavailable: '旧版日志未记录')),
          ('事件码', _entitySafeText(entry.eventCode, unavailable: '旧版日志未记录')),
          ('追踪 ID', _entitySafeText(entry.traceId, unavailable: '未关联追踪')),
          (
            '异常类型',
            _entitySafeText(
              entry.exceptionType,
              unavailable: entry.level == 'error' ? '未分类异常' : '不适用',
            ),
          ),
          (
            '堆栈摘要',
            _entitySafeText(
              entry.stackSummary,
              unavailable: entry.level == 'error' ? '服务未返回堆栈摘要' : '不适用',
            ),
          ),
        ],
      ),
      _entityFacts(
        title: '事件元数据（按字段名排序）',
        icon: Icons.data_object_rounded,
        fields: _entitySortedFacts(entry.metadata, emptyLabel: '当前事件未保留元数据。'),
        selectable: true,
        copyable: true,
      ),
      _entityCode(
        context,
        title: '原始消息（敏感字段已脱敏）',
        icon: Icons.code_rounded,
        value: _entitySafeText(entry.message, unavailable: '日志消息为空'),
      ),
      _InsightRecordPanel(
        icon: Icons.radar_rounded,
        title: '关联任务',
        records: task == null
            ? const <_InsightRecord>[]
            : <_InsightRecord>[_taskInsightRecord(task)],
        emptyLabel: entry.jobId.isEmpty ? '该日志没有关联任务。' : '关联任务不在当前历史中。',
        maxEntries: 1,
      ),
    ]);
  }
}

class _RuleEntityInsightBody extends StatelessWidget {
  const _RuleEntityInsightBody({
    required this.ruleId,
    required this.legacySnapshot,
  });

  final String ruleId;
  final AiExposureScanRule? legacySnapshot;

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    final rules = context.watch<ServicesController>().rules;
    final rule = ruleId.isEmpty
        ? legacySnapshot
        : rules.where((entry) => entry.id == ruleId).firstOrNull;
    if (rule == null) return const _InsightEmpty(label: '该规则已不在当前规则集合中。');
    final colors = Theme.of(context).colorScheme;
    final verificationEndpointCount =
        rule.modelPaths.length + rule.balancePaths.length;
    final provenance = <_InsightTimelineEntry>[
      if (rule.createdAt != null)
        _InsightTimelineEntry(
          at: rule.createdAt!,
          title: '当前规则记录创建',
          detail:
              '版本 ${_entitySafeText(rule.version, unavailable: '未记录')} · 来源 ${_entitySafeText(rule.changeSource, unavailable: '未记录')}',
          color: OpenHandStatusColors.info,
          tag: '当前记录',
          target: _RuleInsightTarget(rule),
        ),
      if (rule.updatedAt != null)
        _InsightTimelineEntry(
          at: rule.updatedAt!,
          title: '当前规则记录更新',
          detail:
              '快照 ${_entitySafeText(rule.snapshotId, unavailable: '未记录')} · 内容哈希 ${_entitySafeText(rule.contentHash, unavailable: '未记录')}',
          color: rule.enabled ? OpenHandStatusColors.success : colors.outline,
          tag: rule.enabled ? '已启用' : '未启用',
          target: _RuleInsightTarget(rule),
        ),
    ]..sort((left, right) => right.at.compareTo(left.at));
    return _metricInsightPage([
      _InsightKpiBand(
        title: '规则覆盖容量',
        icon: Icons.rule_rounded,
        items: [
          _InsightKpi(
            icon: rule.enabled
                ? Icons.check_circle_outline_rounded
                : Icons.pause_circle_outline_rounded,
            label: '启用状态',
            value: rule.enabled ? '已启用' : '未启用',
            helper: '当前规则配置',
            color: rule.enabled ? OpenHandStatusColors.success : colors.outline,
          ),
          _InsightKpi(
            icon: Icons.key_outlined,
            label: '识别模式容量',
            value: '${rule.credentialPatterns.length}',
            helper: '当前保留的凭证模式',
            color: colors.primary,
          ),
          _InsightKpi(
            icon: Icons.manage_search_rounded,
            label: '上下文约束容量',
            value: '${rule.contextTerms.length}',
            helper: '当前保留的约束词',
            color: OpenHandStatusColors.info,
          ),
          _InsightKpi(
            icon: Icons.hub_outlined,
            label: '验证端点容量',
            value: '$verificationEndpointCount',
            helper:
                '模型 ${rule.modelPaths.length} · 余额 ${rule.balancePaths.length}',
            color: colors.tertiary,
          ),
        ],
      ),
      _InsightRankingSection(
        title: text(zh: '规则复杂度五维', en: 'Five rule complexity dimensions'),
        icon: Icons.bar_chart_rounded,
        items: [
          _InsightRankItem(
            label: text(zh: '凭证正则', en: 'Credential patterns'),
            value: rule.credentialPatterns.length.toDouble(),
            valueLabel: text(
              zh: '${rule.credentialPatterns.length} 条',
              en: '${rule.credentialPatterns.length} patterns',
            ),
            color: colors.primary,
          ),
          _InsightRankItem(
            label: text(zh: '上下文词', en: 'Context terms'),
            value: rule.contextTerms.length.toDouble(),
            valueLabel: text(
              zh: '${rule.contextTerms.length} 条',
              en: '${rule.contextTerms.length} terms',
            ),
            color: OpenHandStatusColors.info,
          ),
          _InsightRankItem(
            label: text(zh: '编码', en: 'Encodings'),
            value: rule.contentEncodings.length.toDouble(),
            valueLabel: text(
              zh: '${rule.contentEncodings.length} 种',
              en: '${rule.contentEncodings.length} types',
            ),
            color: colors.secondary,
          ),
          _InsightRankItem(
            label: text(zh: '模型路径', en: 'Model paths'),
            value: rule.modelPaths.length.toDouble(),
            valueLabel: text(
              zh: '${rule.modelPaths.length} 条',
              en: '${rule.modelPaths.length} paths',
            ),
            color: colors.tertiary,
          ),
          _InsightRankItem(
            label: text(zh: '余额路径', en: 'Balance paths'),
            value: rule.balancePaths.length.toDouble(),
            valueLabel: text(
              zh: '${rule.balancePaths.length} 条',
              en: '${rule.balancePaths.length} paths',
            ),
            color: OpenHandStatusColors.warning,
          ),
        ],
        emptyLabel: text(
          zh: '该规则没有可视化的复杂度配置。',
          en: 'This rule has no complexity configuration to visualize.',
        ),
      ),
      _InsightTimelineSection(
        title: '当前规则记录溯源时间线',
        icon: Icons.history_rounded,
        entries: provenance,
        emptyLabel: '当前规则未保留创建或更新时间，不能补造历史变更。',
      ),
      _entityFacts(
        title: '规则身份与当前溯源',
        icon: Icons.badge_outlined,
        fields: [
          ('规则 ID', _entitySafeText(rule.id)),
          ('供应商', _entitySafeText(rule.vendor, unavailable: '规则字段缺失')),
          ('协议', _entitySafeText(rule.protocol, unavailable: '规则字段缺失')),
          ('启用状态', rule.enabled ? '已启用' : '未启用'),
          ('版本', _entitySafeText(rule.version, unavailable: '旧版规则未记录')),
          ('内容哈希', _entitySafeText(rule.contentHash, unavailable: '旧版规则未记录')),
          ('创建时间', rule.createdAt?.toLocal().toIso8601String() ?? '旧版规则未记录'),
          ('更新时间', rule.updatedAt?.toLocal().toIso8601String() ?? '旧版规则未记录'),
          ('快照 ID', _entitySafeText(rule.snapshotId, unavailable: '旧版规则未记录')),
          ('变更来源', _entitySafeText(rule.changeSource, unavailable: '旧版规则未记录')),
        ],
      ),
      _entityTextList(
        title: '凭证识别模式',
        icon: Icons.key_outlined,
        values: rule.credentialPatterns
            .map(_entitySafeText)
            .toList(growable: false),
        emptyLabel: '该规则未配置凭证模式。',
        monospace: true,
      ),
      _entityTextList(
        title: '上下文约束词',
        icon: Icons.manage_search_rounded,
        values: rule.contextTerms.map(_entitySafeText).toList(growable: false),
        emptyLabel: '该规则未配置上下文约束词。',
      ),
      _entityFacts(
        title: '编码覆盖',
        icon: Icons.code_rounded,
        fields: [
          (
            '编码类型',
            rule.contentEncodings.isEmpty
                ? '未配置'
                : rule.contentEncodings.map((entry) => entry.id).join(' / '),
          ),
        ],
      ),
      _entityTextList(
        title: '模型验证端点',
        icon: Icons.model_training_outlined,
        values: rule.modelPaths.map(_entitySafeText).toList(growable: false),
        emptyLabel: '该规则未配置模型验证端点。',
        monospace: true,
      ),
      _entityTextList(
        title: '余额验证端点',
        icon: Icons.account_balance_wallet_outlined,
        values: rule.balancePaths.map(_entitySafeText).toList(growable: false),
        emptyLabel: '该规则未配置余额验证端点。',
        monospace: true,
      ),
    ]);
  }
}

class _ProxyRequestEntityInsightBody extends StatelessWidget {
  const _ProxyRequestEntityInsightBody({
    required this.endpointId,
    required this.address,
    required this.sample,
  });

  final String? endpointId;
  final String address;
  final AiExposureProxyRequestSample sample;

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    final controller = context.watch<ServicesController>();
    final colors = Theme.of(context).colorScheme;
    final unavailable = text(zh: '不可用', en: 'Unavailable');
    final endpoint = endpointId == null
        ? null
        : controller.proxyConfiguration.endpoints
              .where((entry) => entry.runtimeId == endpointId)
              .firstOrNull;
    final identity = endpoint?.identity;
    final endpointSamples =
        endpoint?.statistics.recentRequests.toList(growable: false) ??
        const <AiExposureProxyRequestSample>[];
    final targetHost = sample.targetHost?.trim() ?? '';
    final sameHostRecords =
        targetHost.isEmpty
              ? <AiExposureProxyRequestSample>[]
              : endpointSamples
                    .where((entry) => entry.targetHost?.trim() == targetHost)
                    .toList()
          ..sort((left, right) => right.at.compareTo(left.at));
    final latencies = endpointSamples
        .map((entry) => entry.responseTimeMs)
        .toList(growable: false);
    final peak = latencies.fold<int>(
      0,
      (current, value) => value > current ? value : current,
    );
    final sampleTone = sample.succeeded
        ? OpenHandStatusColors.success
        : sample.timedOut
        ? OpenHandStatusColors.warning
        : OpenHandStatusColors.error;
    final timeoutHeadroom = sample.timeoutMs == null
        ? null
        : sample.timeoutMs! - sample.responseTimeMs;
    return _metricInsightPage([
      _InsightKpiBand(
        title: '请求样本与端点基准',
        icon: Icons.swap_vert_rounded,
        items: [
          _InsightKpi(
            icon: sample.succeeded
                ? Icons.check_circle_outline_rounded
                : sample.timedOut
                ? Icons.timer_off_outlined
                : Icons.error_outline_rounded,
            label: '当前结果',
            value: sample.succeeded
                ? '成功'
                : sample.timedOut
                ? '超时'
                : '失败',
            helper: '近期保留请求样本',
            color: sampleTone,
          ),
          _InsightKpi(
            icon: Icons.speed_rounded,
            label: '当前响应耗时',
            value: '${sample.responseTimeMs} ms',
            helper: '服务返回值',
            color: colors.primary,
          ),
          _InsightKpi(
            icon: Icons.horizontal_rule_rounded,
            label: '同端点 p50 / p95',
            value: latencies.isEmpty
                ? '不可用'
                : '${_latencyPercentile(latencies, 0.50)} / ${_latencyPercentile(latencies, 0.95)} ms',
            helper: endpoint == null
                ? '节点已不在当前配置中'
                : '保留 ${latencies.length} 个同端点样本',
            color: OpenHandStatusColors.info,
          ),
          _InsightKpi(
            icon: Icons.http_rounded,
            label: text(zh: 'HTTP 状态', en: 'HTTP status'),
            value: sample.statusCode == null
                ? unavailable
                : '${sample.statusCode}',
            helper: sample.statusCode == null
                ? text(
                    zh: '样本未上报状态码',
                    en: 'The sample did not report a status code',
                  )
                : text(zh: '当前请求响应', en: 'Current request response'),
            color: sample.statusCode == null ? colors.outline : colors.tertiary,
          ),
          _InsightKpi(
            icon: Icons.vertical_align_top_rounded,
            label: '同端点峰值',
            value: latencies.isEmpty ? '不可用' : '$peak ms',
            helper: endpoint == null ? '没有可用端点记录' : '有限保留窗口最大值',
            color: colors.tertiary,
          ),
          _InsightKpi(
            icon: Icons.timer_outlined,
            label: text(zh: '超时余量', en: 'Timeout headroom'),
            value: timeoutHeadroom == null
                ? unavailable
                : '$timeoutHeadroom ms',
            helper: sample.timeoutMs == null
                ? text(
                    zh: '客户端未设置显式阈值',
                    en: 'The client did not set an explicit threshold',
                  )
                : timeoutHeadroom! < 0
                ? text(zh: '已超过阈值', en: 'Threshold exceeded')
                : text(
                    zh: '阈值 ${sample.timeoutMs} ms',
                    en: 'Threshold ${sample.timeoutMs} ms',
                  ),
            color: timeoutHeadroom == null
                ? colors.outline
                : timeoutHeadroom < 0
                ? OpenHandStatusColors.error
                : OpenHandStatusColors.success,
          ),
        ],
      ),
      _Section(
        title: '本次请求选路流',
        icon: Icons.alt_route_rounded,
        child: _InsightFlowLane(
          nodes: [
            (
              icon: Icons.send_outlined,
              label: '请求',
              value: _entitySafeText(sample.method, unavailable: '方法未上报'),
              color: colors.primary,
            ),
            (
              icon: Icons.route_outlined,
              label: '选路',
              value: _entitySafeText(sample.routeMode, unavailable: '模式未上报'),
              color: colors.tertiary,
            ),
            (
              icon: Icons.psychology_alt_outlined,
              label: text(zh: '选路原因', en: 'Routing reason'),
              value: _entitySafeText(
                sample.selectionReason,
                unavailable: text(zh: '原因未上报', en: 'Reason not reported'),
              ),
              color: colors.tertiary,
            ),
            (
              icon: Icons.dns_outlined,
              label: '代理节点',
              value: _entitySafeText(
                endpoint?.displayName,
                unavailable: '运行时节点',
              ),
              color: OpenHandStatusColors.info,
            ),
            (
              icon: Icons.language_rounded,
              label: '目标主机',
              value: _entitySafeText(sample.targetHost, unavailable: '旧版样本未上报'),
              color: colors.secondary,
            ),
            (
              icon: sample.succeeded
                  ? Icons.check_circle_outline_rounded
                  : Icons.error_outline_rounded,
              label: '结果',
              value: sample.succeeded
                  ? '成功'
                  : sample.timedOut
                  ? '超时'
                  : '失败',
              color: sampleTone,
            ),
          ],
        ),
      ),
      _InsightRecordPanel(
        icon: Icons.history_rounded,
        title: targetHost.isEmpty ? '同目标主机保留请求' : '同目标主机保留请求 · $targetHost',
        records: sameHostRecords
            .map(
              (item) => _InsightRecord(
                icon: item.succeeded
                    ? Icons.check_circle_outline_rounded
                    : item.timedOut
                    ? Icons.timer_off_outlined
                    : Icons.error_outline_rounded,
                title: item.succeeded
                    ? '成功请求'
                    : item.timedOut
                    ? '超时请求'
                    : '失败请求',
                subtitle:
                    '${_entitySafeText(item.method, unavailable: '方法未上报')} · ${_entitySafeText(item.routeMode, unavailable: '选路模式未上报')}',
                tags: [
                  '${item.responseTimeMs} ms',
                  if (item.statusCode != null) 'HTTP ${item.statusCode}',
                  _reportedShortDateTime(item.at, item.atReported),
                ],
                color: item.succeeded
                    ? OpenHandStatusColors.success
                    : item.timedOut
                    ? OpenHandStatusColors.warning
                    : OpenHandStatusColors.error,
                target: _ProxyRequestInsightTarget(
                  endpoint: endpoint,
                  address: endpoint?.maskedUrl ?? _maskProxyAddress(address),
                  sample: item,
                ),
              ),
            )
            .toList(growable: false),
        emptyLabel: targetHost.isEmpty
            ? '当前请求未上报目标主机，无法筛选同主机记录。'
            : '当前同端点保留窗口没有同主机请求记录。',
      ),
      _entityFacts(
        title: '请求与选路事实',
        icon: Icons.receipt_long_outlined,
        fields: [
          (
            '请求时间',
            _reportedIsoDateTime(
              sample.at,
              sample.atReported,
              unavailable: '请求时间未上报',
            ),
          ),
          ('请求 ID', _entitySafeText(sample.id, unavailable: '旧版请求样本未记录')),
          ('节点', _entitySafeText(endpoint?.displayName, unavailable: '运行时节点')),
          ('代理地址', endpoint?.maskedUrl ?? _maskProxyAddress(address)),
          (
            '目标主机',
            _entitySafeText(sample.targetHost, unavailable: '旧版请求样本未记录'),
          ),
          (
            '源地址',
            aiExposureProxyClientEndpoint(sample.clientIp, sample.clientPort),
          ),
          ('请求方法', _entitySafeText(sample.method, unavailable: '旧版请求样本未记录')),
          (
            '超时阈值',
            sample.timeoutMs == null
                ? text(
                    zh: '客户端未设置显式阈值',
                    en: 'The client did not set an explicit threshold',
                  )
                : '${sample.timeoutMs} ms',
          ),
          ('选路模式', _entitySafeText(sample.routeMode, unavailable: '旧版请求样本未记录')),
          (
            '选路原因',
            _entitySafeText(sample.selectionReason, unavailable: '旧版请求样本未记录'),
          ),
          ('安全上下文', _entitySafeText(sample.context, unavailable: '旧版请求样本未记录')),
          (
            '错误类型',
            sample.succeeded
                ? '未发生'
                : _entitySafeText(sample.errorType, unavailable: '错误类型未分类'),
          ),
          (
            '错误消息',
            sample.succeeded
                ? '未发生'
                : _entitySafeText(sample.errorMessage, unavailable: '错误详情未上报'),
          ),
        ],
      ),
      _entityFacts(
        title: '出口身份',
        icon: Icons.public_rounded,
        fields: [
          ('出口 IP', _entitySafeText(identity?.exitIp, unavailable: '尚未完成出口识别')),
          ('国家', _entitySafeText(identity?.country, unavailable: '尚未完成出口识别')),
          ('ISP', _entitySafeText(identity?.isp, unavailable: '尚未完成出口识别')),
          ('ASN', _entitySafeText(identity?.asn, unavailable: '尚未完成出口识别')),
          (
            '身份采集时间',
            identity == null
                ? '尚未完成出口识别'
                : _reportedIsoDateTime(
                    identity.observedAt,
                    identity.observedAtReported,
                    unavailable: '身份采集时间未上报',
                  ),
          ),
        ],
      ),
    ]);
  }
}

class _ProxyProbeEntityInsightBody extends StatelessWidget {
  const _ProxyProbeEntityInsightBody({
    required this.endpointId,
    required this.sample,
  });

  final String endpointId;
  final AiExposureProxyProbeSample sample;

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    final endpoint = context
        .watch<ServicesController>()
        .proxyConfiguration
        .endpoints
        .where((entry) => entry.runtimeId == endpointId)
        .firstOrNull;
    final colors = Theme.of(context).colorScheme;
    final samples = <AiExposureProxyProbeSample>[...?endpoint?.samples]
      ..sort((left, right) => left.checkedAt.compareTo(right.checkedAt));
    final latencySamples = samples
        .where((entry) => entry.latencyMs != null)
        .toList(growable: false);
    final timedSteps = sample.stepResults
        .where((entry) => entry.durationMs != null)
        .toList(growable: false);
    final queueMs =
        sample.scheduledAt != null &&
            sample.startedAt != null &&
            !sample.startedAt!.isBefore(sample.scheduledAt!)
        ? sample.startedAt!.difference(sample.scheduledAt!).inMilliseconds
        : null;
    final inferredSteps = <String>[
      '代理网关：${sample.gatewayReachable ? '通过' : '失败'}',
      '身份认证：${_probeStepState(sample, AiExposureProxyProbeFailure.authentication)}',
      '访问控制：${_probeStepState(sample, AiExposureProxyProbeFailure.access)}',
      '代理转发：${_probeStepState(sample, AiExposureProxyProbeFailure.forwarding)}',
      '协议响应：${_probeStepState(sample, AiExposureProxyProbeFailure.protocol)}',
      '最终结果：${sample.reachable ? '通过' : '失败'}',
    ];
    final failureCounts = <AiExposureProxyProbeFailure, int>{};
    for (final entry in samples.where((entry) => entry.failure != null)) {
      failureCounts.update(
        entry.failure!,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final reachable = samples.where((entry) => entry.reachable).length;
    final unclassifiedFailures = samples
        .where((entry) => !entry.reachable && entry.failure == null)
        .length;
    return _metricInsightPage([
      _InsightKpiBand(
        title: '巡检样本快照',
        icon: Icons.health_and_safety_outlined,
        items: [
          _InsightKpi(
            icon: sample.reachable
                ? Icons.check_circle_outline_rounded
                : Icons.report_problem_outlined,
            label: '当前巡检',
            value: sample.reachable ? '通过' : '失败',
            helper: '当前保留巡检样本',
            color: sample.reachable
                ? OpenHandStatusColors.success
                : OpenHandStatusColors.error,
          ),
          _InsightKpi(
            icon: Icons.speed_rounded,
            label: '响应耗时',
            value: sample.latencyMs == null ? '不可用' : '${sample.latencyMs} ms',
            helper: sample.latencyMs == null ? '未形成可计时响应' : '服务实测值',
            color: colors.primary,
          ),
          if (queueMs != null)
            _InsightKpi(
              icon: Icons.schedule_rounded,
              label: '排队等待',
              value: '$queueMs ms',
              helper: '计划到开始时间均有效',
              color: colors.tertiary,
            ),
          _InsightKpi(
            icon: Icons.timer_outlined,
            label: '实测计时步骤',
            value: '${timedSteps.length}',
            helper: sample.stepResults.isEmpty
                ? '旧版样本没有步骤记录'
                : '仅含 durationMs 的真实步骤',
            color: OpenHandStatusColors.info,
          ),
        ],
      ),
      _entityProbeWaterfall(
        context,
        timedSteps: timedSteps,
        emptyLabel: sample.stepResults.isEmpty
            ? '该样本没有服务上报的步骤记录。'
            : '服务上报了步骤，但没有可用的真实计时值。',
      ),
      _InsightTrendSection(
        title: '端点保留响应时延趋势',
        icon: Icons.show_chart_rounded,
        series: [
          OpenHandChartSeries(
            label: '巡检时延',
            values: latencySamples
                .map((entry) => entry.latencyMs!.toDouble())
                .toList(growable: false),
            color: colors.primary,
          ),
        ],
        sampleLabels: latencySamples
            .map(
              (entry) => _reportedShortDateTime(
                entry.checkedAt,
                entry.checkedAtReported,
              ),
            )
            .toList(growable: false),
        suffix: ' ms',
        emptyLabel: endpoint == null
            ? '节点已不在当前配置中，无法读取保留时延。'
            : '该端点没有保留的可计时巡检样本。',
        interpolation: OpenHandChartInterpolation.smooth,
        targets: latencySamples
            .map<_InsightTarget?>(
              (entry) => endpoint == null
                  ? null
                  : _ProxyProbeInsightTarget(endpoint: endpoint, sample: entry),
            )
            .toList(growable: false),
      ),
      _InsightDonutSection(
        title: '端点保留巡检失败构成',
        icon: Icons.donut_small_rounded,
        items: [
          _DistributionItem('通过', reachable, OpenHandStatusColors.success),
          ...AiExposureProxyProbeFailure.values.map(
            (failure) => _DistributionItem(
              _proxyProbeFailureName(failure),
              failureCounts[failure] ?? 0,
              _distributionColor(failure.index + 1, colors),
              key: failure,
            ),
          ),
          _DistributionItem(
            '未分类失败',
            unclassifiedFailures,
            OpenHandStatusColors.warning,
          ),
        ],
      ),
      if (sample.stepResults.isEmpty)
        _Section(
          title: '旧版推断诊断路径（非计时采样）',
          icon: Icons.auto_fix_high_outlined,
          child: _InsightFlowLane(
            nodes: [
              for (final entry in inferredSteps.indexed)
                (
                  icon: entry.$2.endsWith('通过')
                      ? Icons.check_circle_outline_rounded
                      : entry.$2.endsWith('失败')
                      ? Icons.error_outline_rounded
                      : Icons.pending_outlined,
                  label: text(
                    zh: '步骤 ${entry.$1 + 1}',
                    en: 'Step ${entry.$1 + 1}',
                  ),
                  value: entry.$2,
                  color: entry.$2.endsWith('通过')
                      ? OpenHandStatusColors.success
                      : entry.$2.endsWith('失败')
                      ? OpenHandStatusColors.error
                      : colors.outline,
                ),
            ],
          ),
        ),
      _entityFacts(
        title: '巡检身份与失败事实',
        icon: Icons.badge_outlined,
        fields: [
          (
            '巡检时间',
            _reportedIsoDateTime(
              sample.checkedAt,
              sample.checkedAtReported,
              unavailable: '巡检时间未上报',
            ),
          ),
          ('巡检 ID', _entitySafeText(sample.id, unavailable: '旧版巡检样本未记录')),
          (
            '巡检轮次 ID',
            _entitySafeText(sample.inspectionRunId, unavailable: '旧版巡检样本未记录'),
          ),
          (
            '计划时间',
            sample.scheduledAt?.toLocal().toIso8601String() ?? '旧版巡检样本未记录',
          ),
          (
            '开始时间',
            sample.startedAt?.toLocal().toIso8601String() ?? '旧版巡检样本未记录',
          ),
          (
            '结束时间',
            sample.finishedAt?.toLocal().toIso8601String() ?? '旧版巡检样本未记录',
          ),
          (
            '节点',
            _entitySafeText(endpoint?.displayName, unavailable: endpointId),
          ),
          ('代理地址', endpoint?.maskedUrl ?? '节点已从当前配置移除'),
          ('最终结果', sample.reachable ? '通过' : '失败'),
          ('响应耗时', sample.latencyMs == null ? '不可用' : '${sample.latencyMs} ms'),
          (
            'HTTP 状态',
            sample.statusCode == null ? '不可用' : '${sample.statusCode}',
          ),
          (
            '失败阶段',
            sample.failure == null
                ? sample.reachable
                      ? '未发生'
                      : '故障阶段未分类'
                : _proxyProbeFailureName(sample.failure!),
          ),
          (
            '错误原文（已脱敏）',
            sample.reachable
                ? '未发生'
                : _entitySafeText(sample.error, unavailable: '故障详情未上报'),
          ),
        ],
      ),
    ]);
  }
}

class _StageEntityInsightBody extends StatelessWidget {
  const _StageEntityInsightBody({required this.stage, this.taskId});

  final String stage;
  final String? taskId;

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    final controller = context.watch<ServicesController>();
    final colors = Theme.of(context).colorScheme;
    final task = taskId == null
        ? null
        : controller.history.where((entry) => entry.id == taskId).firstOrNull;
    final definition = _stageDefinition(stage);
    final timing = task == null ? null : _entityStageTiming(task, stage);
    final durationTasks =
        controller.history
            .where(
              (entry) => _entityStageTiming(entry, stage)?.durationMs != null,
            )
            .toList()
          ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
    final visibleDurationTasks = durationTasks.length <= 24
        ? durationTasks
        : durationTasks.sublist(durationTasks.length - 24);
    final timingFallback = task == null
        ? '未关联任务'
        : task.isTerminal
        ? '任务已进入${_stageName(task.stage)}终态'
        : stage == 'extracting' || stage == 'validating'
        ? '并入目标指纹与验证流水线'
        : task.stageTimings.isEmpty
        ? '历史任务无阶段切片'
        : '阶段尚未开始';
    final taskState = _entityStageTaskState(task, stage);
    final canShowFunnel =
        timing?.inputCount != null && timing?.outputCount != null;
    return _metricInsightPage([
      _InsightKpiBand(
        title: '阶段执行快照',
        icon: Icons.route_rounded,
        items: [
          _InsightKpi(
            icon: task?.isTerminal == true
                ? Icons.flag_rounded
                : taskState == '进行中'
                ? Icons.play_circle_outline_rounded
                : Icons.pause_circle_outline_rounded,
            label: '当前任务阶段状态',
            value: taskState,
            helper: task == null ? '未关联任务' : '任务当前阶段 ${_stageName(task.stage)}',
            color: task?.isTerminal == true
                ? _entityTerminalStageColor(task!.stage, colors)
                : taskState == '进行中'
                ? OpenHandStatusColors.info
                : colors.outline,
          ),
          _InsightKpi(
            icon: Icons.timer_outlined,
            label: '当前阶段耗时',
            value: timing?.durationMs == null
                ? '不可用'
                : '${timing!.durationMs} ms',
            helper: timing?.durationMs == null ? timingFallback : '当前任务实测切片',
            color: colors.primary,
          ),
          _InsightKpi(
            icon: Icons.analytics_outlined,
            label: '跨任务时长样本',
            value: '${durationTasks.length}',
            helper: '同阶段、仅含真实 durationMs',
            color: OpenHandStatusColors.info,
          ),
          _InsightKpi(
            icon: Icons.filter_alt_outlined,
            label: '当前输入 / 输出',
            value: canShowFunnel
                ? '${timing!.inputCount} / ${timing.outputCount}'
                : '不可用',
            helper: canShowFunnel ? '当前任务阶段切片' : '需要同时上报输入与输出',
            color: colors.tertiary,
          ),
        ],
      ),
      _InsightTrendSection(
        title: '跨任务阶段耗时趋势',
        icon: Icons.show_chart_rounded,
        series: [
          OpenHandChartSeries(
            label: _stageName(stage),
            values: visibleDurationTasks
                .map(
                  (entry) =>
                      _entityStageTiming(entry, stage)!.durationMs!.toDouble(),
                )
                .toList(growable: false),
            color: colors.primary,
          ),
        ],
        sampleLabels: visibleDurationTasks
            .map(
              (entry) => _reportedShortDateTime(
                entry.createdAt,
                entry.createdAtReported,
              ),
            )
            .toList(growable: false),
        suffix: ' ms',
        emptyLabel: '当前任务历史没有该阶段的真实时长切片。',
        interpolation: OpenHandChartInterpolation.smooth,
        targets: visibleDurationTasks
            .map<_InsightTarget?>(
              (entry) => _StageInsightTarget(stage, taskId: entry.id),
            )
            .toList(growable: false),
      ),
      if (canShowFunnel)
        _InsightFunnelSection(
          title: '当前任务输入到输出漏斗',
          icon: Icons.filter_alt_outlined,
          items: [
            _InsightFunnelItem(
              label: '输入',
              value: timing!.inputCount!,
              color: colors.primary,
            ),
            _InsightFunnelItem(
              label: '输出',
              value: timing.outputCount!,
              color: OpenHandStatusColors.success,
            ),
          ],
        ),
      _Section(
        title: '阶段处理流',
        icon: Icons.account_tree_outlined,
        child: _InsightFlowLane(
          nodes: [
            (
              icon: Icons.skip_previous_rounded,
              label: text(zh: '前置阶段', en: 'Previous stage'),
              value: _entitySafeText(definition.$4),
              color: colors.primary,
            ),
            (
              icon: Icons.route_rounded,
              label: '当前阶段',
              value: _stageName(stage),
              color: OpenHandStatusColors.info,
            ),
            (
              icon: Icons.skip_next_rounded,
              label: text(zh: '下一阶段', en: 'Next stage'),
              value: _entitySafeText(definition.$5),
              color: OpenHandStatusColors.success,
            ),
            (
              icon: task?.isTerminal == true
                  ? Icons.flag_rounded
                  : Icons.arrow_forward_rounded,
              label: '任务状态',
              value: taskState,
              color: task?.isTerminal == true
                  ? _entityTerminalStageColor(task!.stage, colors)
                  : colors.tertiary,
            ),
          ],
        ),
      ),
      _entityFacts(
        title: '阶段职责与当前任务事实',
        icon: Icons.receipt_long_outlined,
        fields: [
          ('内部标识', _entitySafeText(stage)),
          ('阶段名称', _stageName(stage)),
          ('业务职责', _entitySafeText(definition.$1)),
          ('输入', _entitySafeText(definition.$2)),
          ('输出', _entitySafeText(definition.$3)),
          ('前置阶段', _entitySafeText(definition.$4)),
          ('下一阶段', _entitySafeText(definition.$5)),
          (
            '关联任务',
            task == null
                ? '未关联'
                : _entitySafeText(task.name, unavailable: task.id),
          ),
          ('任务 ID', task == null ? '未关联' : _entitySafeText(task.id)),
          ('阶段状态', taskState),
          (
            '阶段消息',
            timing?.message?.trim().isNotEmpty == true
                ? _entitySafeText(timing!.message)
                : task?.stage == stage &&
                      task?.progress.message.trim().isNotEmpty == true
                ? _entitySafeText(task!.progress.message)
                : timingFallback,
          ),
          (
            '阶段开始时间',
            timing?.startedAt?.toLocal().toIso8601String() ?? timingFallback,
          ),
          (
            '阶段结束时间',
            timing?.finishedAt?.toLocal().toIso8601String() ?? timingFallback,
          ),
          (
            '阶段耗时',
            timing?.durationMs == null
                ? '不可用：$timingFallback'
                : '${timing!.durationMs} ms',
          ),
          (
            '输入数量',
            timing?.inputCount == null
                ? '不可用：$timingFallback'
                : '${timing!.inputCount}',
          ),
          (
            '输出数量',
            timing?.outputCount == null
                ? '不可用：$timingFallback'
                : '${timing!.outputCount}',
          ),
          ('已处理数量', task == null ? '未关联任务' : '${task.progress.processed}'),
        ],
      ),
      if (task != null)
        _InsightRecordPanel(
          icon: Icons.radar_rounded,
          title: '关联任务',
          records: <_InsightRecord>[_taskInsightRecord(task)],
          emptyLabel: '未关联任务。',
          maxEntries: 1,
        ),
    ]);
  }
}

class _DependencyEntityInsightBody extends StatelessWidget {
  const _DependencyEntityInsightBody({
    required this.id,
    required this.name,
    required this.configured,
    required this.connected,
    required this.message,
  });

  final _DependencyInsightId id;
  final String name;
  final bool? configured;
  final bool? connected;
  final String message;

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    final controller = context.watch<ServicesController>();
    final colors = Theme.of(context).colorScheme;
    final status = controller.dependencyStatus;
    final componentKey = switch (id) {
      _DependencyInsightId.postgresql => 'postgresql',
      _DependencyInsightId.redis => 'redis',
      _DependencyInsightId.playwright => 'playwright',
      _ => null,
    };
    final component = switch (id) {
      _DependencyInsightId.postgresql => status?.postgresql,
      _DependencyInsightId.redis => status?.redis,
      _DependencyInsightId.playwright => status?.playwright,
      _ => null,
    };
    final overview = controller.dependencyDataOverview;
    final componentOverview = componentKey == null
        ? const <String, Object?>{}
        : _entityObjectMap(overview[componentKey]);
    final nestedOverviewTelemetry = _entityObjectMap(
      componentOverview['telemetry'],
    );
    final currentTelemetry = nestedOverviewTelemetry.isNotEmpty
        ? nestedOverviewTelemetry
        : componentOverview.isNotEmpty
        ? componentOverview
        : component?.telemetry ?? const <String, Object?>{};
    final impact = switch (id) {
      _DependencyInsightId.postgresql => '结果镜像与跨端数据访问',
      _DependencyInsightId.redis => '分布式协调与缓存',
      _DependencyInsightId.playwright => '浏览器自动化与动态页面访问',
      _DependencyInsightId.sqlite => '本地任务、结果、规则与日志归档',
      _DependencyInsightId.gptExtractor => 'AI 辅助提取',
      _DependencyInsightId.credentialVault => '脱敏凭证与加密持久化边界',
      _DependencyInsightId.proxyRouting ||
      _DependencyInsightId.proxyReliability ||
      _DependencyInsightId.localBypass ||
      _DependencyInsightId.rotationPolicy => '代理请求选路与网络边界',
      _DependencyInsightId.sourceAdapters => '资产发现来源适配链路',
      _DependencyInsightId.fingerprintRules => '产品指纹、凭证模式与编码识别',
      _DependencyInsightId.activeValidator => '授权验证端点与结果确认',
      _DependencyInsightId.taskEventStream ||
      _DependencyInsightId.eventArchive => '任务、结果与日志事件归档',
      _DependencyInsightId.scannerCore => '扫描服务运行链路',
    };
    final historyTrend = componentKey == null
        ? null
        : _entityDependencyHistoryTrend(
            controller,
            componentKey,
            currentTelemetry,
          );
    final connectedColor = connected == true
        ? OpenHandStatusColors.success
        : connected == false
        ? OpenHandStatusColors.error
        : colors.outline;
    final configuredColor = configured == true
        ? OpenHandStatusColors.success
        : configured == false
        ? OpenHandStatusColors.warning
        : colors.outline;
    final meter = _entityDependencyMeter(id, currentTelemetry, colors, text);
    return _metricInsightPage([
      _InsightKpiBand(
        title: '依赖状态快照',
        icon: Icons.account_tree_outlined,
        items: [
          _InsightKpi(
            icon: configured == true
                ? Icons.settings_suggest_outlined
                : configured == false
                ? Icons.settings_outlined
                : Icons.help_outline_rounded,
            label: '配置状态',
            value: _entityNullableBoolLabel(
              configured,
              trueLabel: '已配置',
              falseLabel: '未配置',
            ),
            helper: configured == null ? '状态源未上报，未按未配置处理' : '调用方保留状态',
            color: configuredColor,
          ),
          _InsightKpi(
            icon: connected == true
                ? Icons.link_rounded
                : connected == false
                ? Icons.link_off_rounded
                : Icons.help_outline_rounded,
            label: '连接状态',
            value: _entityNullableBoolLabel(
              connected,
              trueLabel: '已连接',
              falseLabel: '未连接',
            ),
            helper: connected == null ? '状态源未上报，未按未连接处理' : '调用方保留状态',
            color: connectedColor,
          ),
          _InsightKpi(
            icon: Icons.timer_outlined,
            label: '检查耗时',
            value: component?.latencyMs == null
                ? '不可用'
                : '${component!.latencyMs} ms',
            helper: component?.checkedAt == null
                ? '当前组件未上报检查时间'
                : _shortDateTime(component!.checkedAt!),
            color: colors.primary,
          ),
          _InsightKpi(
            icon: Icons.query_stats_rounded,
            label: '24 小时实测趋势',
            value: historyTrend == null
                ? '不可用'
                : '${historyTrend.points.length} 点',
            helper: historyTrend == null
                ? componentKey == null
                      ? '该依赖没有可映射的历史遥测域'
                      : '未保留该组件的实测数值'
                : '字段 ${historyTrend.metric} · 应用内保留窗口',
            color: historyTrend == null
                ? colors.outline
                : OpenHandStatusColors.info,
          ),
        ],
      ),
      if (meter != null)
        _Section(
          title: meter.label,
          icon: Icons.speed_rounded,
          child: OpenHandOperationalMeter(
            label: meter.label,
            value: meter.value,
            maximum: meter.maximum,
            color: meter.color,
            valueLabel: meter.valueLabel,
            helper: meter.helper,
          ),
        ),
      historyTrend == null
          ? const _Section(
              title: '24 小时依赖遥测趋势',
              icon: Icons.show_chart_rounded,
              child: _InsightEmpty(label: '没有可用的真实数值历史；缺失值不会按零绘制。'),
            )
          : _InsightTrendSection(
              title: '24 小时依赖遥测趋势（应用内保留）',
              icon: Icons.show_chart_rounded,
              series: [
                OpenHandChartSeries(
                  label: historyTrend.metric,
                  values: historyTrend.points
                      .map((point) => point.$2)
                      .toList(growable: false),
                  color: OpenHandStatusColors.info,
                ),
              ],
              sampleLabels: historyTrend.points
                  .map((point) => _shortDateTime(point.$1))
                  .toList(growable: false),
              suffix: '',
              emptyLabel: '没有可用的真实数值历史。',
              interpolation: OpenHandChartInterpolation.smooth,
            ),
      _entityFacts(
        title: '组件状态证据',
        icon: Icons.monitor_heart_outlined,
        fields: [
          ('组件', _entitySafeText(name)),
          (
            '配置状态',
            _entityNullableBoolLabel(
              configured,
              trueLabel: '已配置',
              falseLabel: '未配置',
            ),
          ),
          (
            '连接状态',
            _entityNullableBoolLabel(
              connected,
              trueLabel: '已连接',
              falseLabel: '未连接',
            ),
          ),
          ('状态消息（已脱敏）', _entitySafeText(message, unavailable: '服务未返回状态消息')),
          ('影响范围', impact),
          ('版本', _entitySafeText(component?.version, unavailable: '组件未上报版本')),
          ('最近检查', component?.checkedAt?.toLocal().toIso8601String() ?? '不可用'),
          (
            '检查耗时',
            component?.latencyMs == null ? '不可用' : '${component!.latencyMs} ms',
          ),
          (
            '脱敏端点',
            _entitySafeText(component?.endpointMasked, unavailable: '未配置远程端点'),
          ),
          (
            '错误码',
            connected == true ? '未发生' : _entitySafeText(component?.errorCode),
          ),
        ],
      ),
      _entityFacts(
        title: '当前结构化遥测（字段名已排序）',
        icon: Icons.data_object_rounded,
        fields: currentTelemetry.isEmpty
            ? <(String, String)>[
                (
                  text(zh: '遥测状态', en: 'Telemetry status'),
                  text(
                    zh: '组件未提供扩展遥测',
                    en: 'The component did not provide extended telemetry',
                  ),
                ),
              ]
            : _entitySortedFacts(
                currentTelemetry,
                emptyLabel: text(
                  zh: '组件未提供扩展遥测。',
                  en: 'The component did not provide extended telemetry.',
                ),
              ),
      ),
    ]);
  }
}

Widget _entityFacts({
  required String title,
  required IconData icon,
  required List<(String, String)> fields,
  bool selectable = false,
  bool copyable = false,
}) => _Section(
  title: title,
  icon: icon,
  child: Column(
    children: fields
        .map(
          (field) => _OpsKeyValue(
            label: field.$1,
            value: field.$2,
            maxLines: 6,
            selectable: selectable,
            copyable: copyable,
          ),
        )
        .toList(growable: false),
  ),
);

Widget _entityTextList({
  required String title,
  required IconData icon,
  required List<String> values,
  required String emptyLabel,
  bool monospace = false,
}) {
  return _Section(
    title: values.isEmpty ? title : '$title · ${values.length}',
    icon: icon,
    child: values.isEmpty
        ? _InsightEmpty(label: emptyLabel)
        : OpenHandClientPager<String>(
            items: values,
            builder: (context, pageItems) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...pageItems.indexed.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: SelectableText(
                      '${entry.$1 + 1}. ${entry.$2}',
                      style: TextStyle(
                        fontFamily: monospace ? 'monospace' : null,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
  );
}

Widget _entityCode(
  BuildContext context, {
  required String title,
  required IconData icon,
  required String value,
}) {
  final colors = Theme.of(context).colorScheme;
  return _Section(
    title: title,
    icon: icon,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(kOpenHandRadius8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: SelectableText(
        value,
        style: TextStyle(
          color: colors.onSurface,
          fontFamily: 'monospace',
          fontSize: 12.5,
          height: 1.5,
        ),
      ),
    ),
  );
}

Widget _entityProbeWaterfall(
  BuildContext context, {
  required List<AiExposureProxyProbeStepResult> timedSteps,
  required String emptyLabel,
}) {
  final colors = Theme.of(context).colorScheme;
  final maximum = timedSteps.fold<int>(
    0,
    (current, step) => step.durationMs! > current ? step.durationMs! : current,
  );
  return _Section(
    title: '实测步骤瀑布（服务上报计时）',
    icon: Icons.waterfall_chart_rounded,
    child: timedSteps.isEmpty
        ? _InsightEmpty(label: emptyLabel)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: timedSteps.indexed
                .map((entry) {
                  final step = entry.$2;
                  final color = step.succeeded
                      ? OpenHandStatusColors.success
                      : OpenHandStatusColors.error;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${entry.$1 + 1}. ${_entitySafeText(step.step, unavailable: '未命名步骤')}',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                            ),
                            kOpenHandHGap12,
                            Text(
                              '${step.durationMs} ms · ${step.succeeded ? '通过' : '失败'}',
                              style: Theme.of(
                                context,
                              ).textTheme.labelLarge?.copyWith(color: color),
                            ),
                          ],
                        ),
                        kOpenHandGap6,
                        ClipRRect(
                          borderRadius: kOpenHandPillBorderRadius,
                          child: ServiceAnimatedProgressBar(
                            value: maximum <= 0
                                ? 0
                                : step.durationMs! / maximum,
                            minHeight: 10,
                            color: color,
                            backgroundColor: color.withValues(alpha: 0.1),
                          ),
                        ),
                        if (step.message?.trim().isNotEmpty == true) ...[
                          kOpenHandGap5,
                          Text(
                            _entitySafeText(step.message),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  );
                })
                .toList(growable: false),
          ),
  );
}

String _entitySafeText(Object? value, {String unavailable = '不可用'}) {
  final text = '${value ?? ''}'.trim();
  if (text.isEmpty) return unavailable;
  final redacted = _entityRedactText(text);
  return redacted.length <= 600
      ? redacted
      : '${redacted.substring(0, 600)}…（已截断）';
}

String _entitySafeUrl(String value) {
  final text = value.trim();
  if (text.isEmpty) return '记录字段缺失';
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) return _entitySafeText(text);
  final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
  final port = uri.hasPort ? ':${uri.port}' : '';
  final path = uri.path.isEmpty ? '/' : uri.path;
  return _entitySafeText('${uri.scheme}://$host$port$path');
}

String _entityRedactText(String value) {
  var redacted = value.replaceAll(_kRedactPrivateKey, '[私钥已隐藏]');
  redacted = redacted.replaceAllMapped(
    _kRedactAuthHeader,
    (match) => '${match.group(1)}[已隐藏]',
  );
  redacted = redacted.replaceAllMapped(
    _kRedactSecretAssignment,
    (match) => '${match.group(1)}[已隐藏]',
  );
  redacted = redacted.replaceAllMapped(
    _kRedactSecretJson,
    (match) => '${match.group(1)}[已隐藏]',
  );
  redacted = redacted.replaceAllMapped(
    _kRedactUrlCredentials,
    (match) => '${match.group(1)}******${match.group(3)}',
  );
  redacted = redacted.replaceAllMapped(
    _kRedactSecretQuery,
    (match) => '${match.group(1)}[已隐藏]',
  );
  return redacted.replaceAllMapped(
    _kRedactBearerToken,
    (match) => '${match.group(1)}[已隐藏]',
  );
}

Object? _entityRedactStructuredValue(Object? value, {String? key}) {
  if (key != null && isSensitiveDataKey(key)) return '[已隐藏]';
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        '${entry.key}': _entityRedactStructuredValue(
          entry.value,
          key: '${entry.key}',
        ),
    };
  }
  if (value is Iterable) {
    return value
        .map((item) => _entityRedactStructuredValue(item))
        .toList(growable: false);
  }
  return value is String ? _entityRedactText(value) : value;
}

String _entitySafeStructuredValue(Object? value) {
  final safeValue = _entityRedactStructuredValue(value);
  if (safeValue is! Map && safeValue is! Iterable) {
    return _entitySafeText(safeValue);
  }
  try {
    return _entitySafeText(const JsonEncoder().convert(safeValue));
  } on JsonUnsupportedObjectError {
    return _entitySafeText('$safeValue');
  }
}

List<(String, String)> _entitySortedFacts(
  Map<String, Object?> values, {
  required String emptyLabel,
}) {
  if (values.isEmpty) return <(String, String)>[('状态', emptyLabel)];
  final entries = values.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  return entries
      .map((entry) => (entry.key, _entitySafeStructuredValue(entry.value)))
      .toList(growable: false);
}

AiExposureStageTiming? _entityStageTiming(
  AiExposureHistoryEntry task,
  String stage,
) => task.stageTimings.where((entry) => entry.stage == stage).firstOrNull;

String _entityStageTaskState(AiExposureHistoryEntry? task, String stage) {
  if (task == null) return '未关联任务';
  if (task.isTerminal) {
    return task.stage == stage
        ? '已进入${_stageName(task.stage)}终态'
        : '任务已${_stageName(task.stage)}终态';
  }
  if (task.stage == stage) return '进行中';
  final currentOrder = _stageOrder(task.stage);
  final targetOrder = _stageOrder(stage);
  if (currentOrder < 0 || targetOrder < 0) return '状态未映射';
  return currentOrder > targetOrder ? '已完成' : '等待中';
}

Color _entityTerminalStageColor(String stage, ColorScheme colors) =>
    switch (stage) {
      'completed' => OpenHandStatusColors.success,
      'failed' => OpenHandStatusColors.error,
      'cancelled' => OpenHandStatusColors.warning,
      _ => colors.outline,
    };

String _entityNullableBoolLabel(
  bool? value, {
  required String trueLabel,
  required String falseLabel,
}) => value == null
    ? '未上报'
    : value
    ? trueLabel
    : falseLabel;

Map<String, Object?> _entityObjectMap(Object? value) => value is Map
    ? <String, Object?>{
        for (final entry in value.entries) '${entry.key}': entry.value,
      }
    : const <String, Object?>{};

({
  String label,
  double value,
  double maximum,
  String valueLabel,
  String helper,
  Color color,
})?
_entityDependencyMeter(
  _DependencyInsightId id,
  Map<String, Object?> telemetry,
  ColorScheme colors,
  OpenHandLocalizedTextResolver text,
) {
  num? number(String key) {
    final value = telemetry[key];
    if (value is num && value.isFinite && value >= 0) return value;
    return num.tryParse('${value ?? ''}');
  }

  return switch (id) {
    _DependencyInsightId.redis => () {
      final used = number('usedMemoryBytes');
      final capacity = number('maxMemoryBytes');
      if (used == null || capacity == null || capacity <= 0) return null;
      final ratio = dependencySafeRatio(used, capacity).clamp(0.0, 1.0);
      return (
        label: text(zh: 'Redis 内存水位', en: 'Redis memory utilization'),
        value: used.toDouble(),
        maximum: capacity.toDouble(),
        valueLabel: '${(ratio * 100).toStringAsFixed(1)}%',
        helper:
            '${formatByteSize(used.toInt())} / ${formatByteSize(capacity.toInt())}',
        color: ratio >= 0.9
            ? OpenHandStatusColors.error
            : ratio >= 0.75
            ? OpenHandStatusColors.warning
            : OpenHandStatusColors.success,
      );
    }(),
    _DependencyInsightId.postgresql => () {
      final active = number('activeConnections');
      final capacity = number('maxConnections');
      if (active == null || capacity == null || capacity <= 0) return null;
      final ratio = dependencySafeRatio(active, capacity).clamp(0.0, 1.0);
      return (
        label: text(
          zh: 'PostgreSQL 连接水位',
          en: 'PostgreSQL connection utilization',
        ),
        value: active.toDouble(),
        maximum: capacity.toDouble(),
        valueLabel: '${(ratio * 100).toStringAsFixed(1)}%',
        helper: text(
          zh: '${active.toInt()} / ${capacity.toInt()} 个连接',
          en: '${active.toInt()} / ${capacity.toInt()} connections',
        ),
        color: ratio >= 0.9
            ? OpenHandStatusColors.error
            : ratio >= 0.75
            ? OpenHandStatusColors.warning
            : colors.primary,
      );
    }(),
    _ => null,
  };
}

const Map<String, List<String>> _entityDependencyTrendMetrics = {
  'postgresql': [
    'databaseSizeBytes',
    'activeConnections',
    'maxConnections',
    'bloatRatio',
    'sharedBuffersUsedBytes',
    'transactionsCommitted',
    'transactionsRolledBack',
    'deadlocks',
    'conflicts',
  ],
  'redis': [
    'usedMemoryBytes',
    'maxMemoryBytes',
    'memoryFragmentationRatio',
    'keyCount',
    'operationsPerSecond',
    'keyspaceHits',
    'keyspaceMisses',
  ],
  'playwright': ['latencyMs'],
};

const Map<String, Set<String>> _entityDependencyCounterMetrics = {
  'postgresql': {
    'transactionsCommitted',
    'transactionsRolledBack',
    'deadlocks',
    'conflicts',
  },
  'redis': {'keyspaceHits', 'keyspaceMisses'},
};

const int _kEntityDependencyTrendMaxPoints = 720;

List<(DateTime, double)> _entityDownsampleTrend(
  List<(DateTime, double)> points,
) {
  if (points.length <= _kEntityDependencyTrendMaxPoints) return points;
  final sampled = <(DateTime, double)>[];
  final lastIndex = points.length - 1;
  for (var index = 0; index < _kEntityDependencyTrendMaxPoints; index++) {
    final sourceIndex =
        (index * lastIndex / (_kEntityDependencyTrendMaxPoints - 1)).round();
    final point = points[sourceIndex];
    if (sampled.isEmpty || sampled.last.$1 != point.$1) sampled.add(point);
  }
  return sampled;
}

({String metric, List<(DateTime, double)> points})?
_entityDependencyHistoryTrend(
  ServicesController controller,
  String componentKey,
  Map<String, Object?> currentTelemetry,
) {
  final allowedMetrics = _entityDependencyTrendMetrics[componentKey];
  if (allowedMetrics == null || allowedMetrics.isEmpty) return null;
  final cutoff = DateTime.now().subtract(const Duration(hours: 24));
  final samples = controller.dependencyTelemetryHistory
      .where((sample) => !sample.capturedAt.isBefore(cutoff))
      .toList(growable: false);
  final candidates = <String, List<(DateTime, double)>>{};
  for (final metric in allowedMetrics) {
    final metricSamples = <DependencyTelemetrySample>[];
    final rawPoints = <(DateTime, double)>[];
    for (final sample in samples) {
      final component = _entityObjectMap(sample.overview[componentKey]);
      final nested = _entityObjectMap(component['telemetry']);
      final telemetry = nested.isEmpty ? component : nested;
      final value = telemetry[metric];
      if (value is! num || !value.isFinite || value < 0) continue;
      metricSamples.add(
        DependencyTelemetrySample(
          capturedAt: sample.capturedAt,
          overview: <String, Object?>{'value': value},
        ),
      );
      rawPoints.add((sample.capturedAt, value.toDouble()));
    }
    if (rawPoints.isEmpty) continue;
    if (_entityDependencyCounterMetrics[componentKey]?.contains(metric) ==
            true &&
        metricSamples.length >= 2) {
      final rates = dependencyCounterRates(
        metricSamples,
        (sample) => sample.overview['value'] as num,
      );
      candidates[metric] = [
        for (var index = 0; index < metricSamples.length; index++)
          (metricSamples[index].capturedAt, rates[index]),
      ];
    } else {
      candidates[metric] = rawPoints;
    }
  }
  if (candidates.isEmpty) return null;
  final currentKeys = allowedMetrics
      .where(
        (key) => currentTelemetry[key] is num && candidates.containsKey(key),
      )
      .toList(growable: false);
  final metric = currentKeys.firstOrNull ?? candidates.keys.first;
  final points = _entityDownsampleTrend(candidates[metric]!);
  return (metric: metric, points: points);
}

Color _resultEntityColor(AiExposureResultCategory category) =>
    switch (category) {
      AiExposureResultCategory.valid => OpenHandStatusColors.success,
      AiExposureResultCategory.highValue => _kAiExposureColorHighValue,
      AiExposureResultCategory.suspicious => OpenHandStatusColors.warning,
      AiExposureResultCategory.honeypot => OpenHandStatusColors.error,
    };

String _resultEntityCategory(AiExposureResultCategory category) =>
    switch (category) {
      AiExposureResultCategory.valid => '有效',
      AiExposureResultCategory.highValue => '高价值',
      AiExposureResultCategory.suspicious => '可疑',
      AiExposureResultCategory.honeypot => '蜜罐',
    };

String aiExposureCredentialStateName(String state) => switch (state) {
  'valid' => '有效',
  'candidate' => '候选',
  'rate_limited' => '受限',
  'invalid' => '无效',
  'unauthorized' => '未授权',
  'unreachable' => '不可达',
  'duplicate' => '重复',
  'not_found' => '未发现',
  _ => state.trim().isEmpty ? '状态未分类' : state,
};

String _probeStepState(
  AiExposureProxyProbeSample sample,
  AiExposureProxyProbeFailure failure,
) {
  if (sample.reachable) return '通过';
  final actual = sample.failure;
  if (actual == null) return '未执行';
  if (failure == actual) return '失败';
  final completed = switch (actual) {
    AiExposureProxyProbeFailure.gateway =>
      const <AiExposureProxyProbeFailure>{},
    AiExposureProxyProbeFailure.authentication => const {
      AiExposureProxyProbeFailure.gateway,
    },
    AiExposureProxyProbeFailure.access => const {
      AiExposureProxyProbeFailure.gateway,
      AiExposureProxyProbeFailure.authentication,
    },
    AiExposureProxyProbeFailure.forwarding => const {
      AiExposureProxyProbeFailure.gateway,
      AiExposureProxyProbeFailure.authentication,
      AiExposureProxyProbeFailure.access,
    },
    AiExposureProxyProbeFailure.protocol => const {
      AiExposureProxyProbeFailure.gateway,
    },
    AiExposureProxyProbeFailure.timeout =>
      sample.gatewayReachable
          ? const <AiExposureProxyProbeFailure>{
              AiExposureProxyProbeFailure.gateway,
            }
          : const <AiExposureProxyProbeFailure>{},
  };
  return completed.contains(failure) ? '通过' : '未执行';
}

(String, String, String, String, String) _stageDefinition(String stage) =>
    switch (stage) {
      'queued' => ('等待调度与资源分配', '扫描请求', '可执行任务', '无', '资产发现'),
      'discovering' => ('从已启用来源发现目标', '来源配置与查询', '原始目标集合', '排队', '目标规范化'),
      'normalizing' => ('统一目标格式并去除无效输入', '原始目标集合', '规范目标集合', '资产发现', '产品指纹'),
      'fingerprinting' => ('识别目标产品与协议特征', '规范目标集合', '产品指纹', '目标规范化', '凭证提取'),
      'extracting' => ('按规则提取候选凭证与上下文', '响应内容与规则', '候选结果', '产品指纹', '授权验证'),
      'validating' => ('在授权边界内验证候选结果', '候选结果与授权范围', '有效性结论', '凭证提取', '关联归档'),
      'persisting' => ('写入任务、结果、证据与日志', '验证结论与证据', '持久化记录', '授权验证', '完成'),
      'completed' => ('确认任务终态并汇总产出', '持久化结果', '完成任务', '关联归档', '无'),
      'cancelled' => ('记录取消终态与已完成进度', '取消请求与当前进度', '取消任务', '任意运行阶段', '无'),
      'failed' => ('记录失败终态与错误上下文', '运行错误与当前进度', '失败任务', '任意运行阶段', '无'),
      _ => ('未知阶段职责', '未知输入', '未知输出', '未知前置阶段', '未知后续阶段'),
    };

int _stageOrder(String stage) => const <String>[
  'queued',
  'discovering',
  'normalizing',
  'fingerprinting',
  'extracting',
  'validating',
  'persisting',
  'completed',
].indexOf(stage);
