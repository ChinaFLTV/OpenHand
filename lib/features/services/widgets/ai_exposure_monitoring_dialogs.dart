import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_ops_charts.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/ui/openhand_trailing_toolbar.dart';
import '../../../shared/util/localized_text.dart';
import '../model/ai_exposure_models.dart';
import '../services_controller.dart';
import 'service_dialog_controls.dart';

const Duration _kOperationsRefreshInterval = Duration(seconds: 8);

Future<void> showAiExposureOperationsDialog(BuildContext context) =>
    showAnimatedDialog<void>(
      context: context,
      builder: (_) => buildOpenHandDialog(
        maxWidth: kOpenHandDialogWidthFull,
        maxHeight: kOpenHandDialogHeightFull,
        child: const ServiceDialogInteractionTheme(child: _OperationsDialog()),
      ),
    );

Future<void> showAiExposureLogMonitorDialog(BuildContext context) =>
    showAnimatedDialog<void>(
      context: context,
      builder: (_) => buildOpenHandDialog(
        maxWidth: kOpenHandDialogWidthPanel,
        maxHeight: kOpenHandDialogHeightTall,
        child: const ServiceDialogInteractionTheme(child: _LogMonitorDialog()),
      ),
    );

enum _OperationsView { overview, pipeline, sources, security }

class _OperationsDialog extends StatefulWidget {
  const _OperationsDialog();

  @override
  State<_OperationsDialog> createState() => _OperationsDialogState();
}

class _OperationsDialogState extends State<_OperationsDialog> {
  _OperationsView _view = _OperationsView.overview;
  Timer? _timer;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _timer = Timer.periodic(_kOperationsRefreshInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted || _refreshing) return;
    final controller = context.read<ServicesController>();
    if (!controller.isRunning) return;
    _refreshing = true;
    await controller.refreshServiceStatus();
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ServicesController>();
    final text = openHandTextResolver(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final running = controller.isRunning;
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OpenHandResponsiveHeaderLayout(
            compactBreakpoint: 700,
            identity: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: cs.primary.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Icon(
                    Icons.monitor_heart_rounded,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text(
                          zh: 'AI 基础设施扫描服务运维',
                          en: 'AI exposure scanner operations',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge,
                      ),
                      Text(
                        'ai_jungler ${controller.health?.version ?? '--'} · ${controller.ownsProcess ? text(zh: '内嵌进程', en: 'Bundled') : text(zh: '外部服务', en: 'External')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                IconButton.filledTonal(
                  tooltip: text(zh: '刷新运维数据', en: 'Refresh operations'),
                  onPressed: running && !_refreshing ? _refresh : null,
                  icon: _refreshing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
                IconButton.filledTonal(
                  tooltip: running
                      ? text(zh: '停止服务', en: 'Stop service')
                      : text(zh: '启动服务', en: 'Start service'),
                  onPressed: controller.busy
                      ? null
                      : running
                      ? controller.stopService
                      : controller.startService,
                  icon: Icon(
                    running ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusPill(
                icon: running
                    ? Icons.circle
                    : Icons.pause_circle_outline_rounded,
                label: running
                    ? text(zh: '运行中', en: 'Running')
                    : text(zh: '已停止', en: 'Stopped'),
                color: running ? Colors.green : cs.outline,
              ),
              _StatusPill(
                icon: Icons.schedule_rounded,
                label: _duration(controller.health?.uptimeSeconds ?? 0),
                color: cs.primary,
              ),
              _StatusPill(
                icon: Icons.lan_outlined,
                label: controller.proxyStatus?.enabled == true
                    ? text(
                        zh: '代理 ${controller.proxyStatus!.endpoints.length}',
                        en: '${controller.proxyStatus!.endpoints.length} proxies',
                      )
                    : text(zh: '直接连接', en: 'Direct'),
                color: controller.proxyStatus?.enabled == true
                    ? cs.tertiary
                    : cs.onSurfaceVariant,
              ),
              _StatusPill(
                icon: Icons.rule_rounded,
                label: text(
                  zh: '${controller.rules.where((rule) => rule.enabled).length} 条规则',
                  en: '${controller.rules.where((rule) => rule.enabled).length} rules',
                ),
                color: cs.secondary,
              ),
            ],
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<_OperationsView>(
              segments: [
                ButtonSegment(
                  value: _OperationsView.overview,
                  icon: const Icon(Icons.dashboard_outlined),
                  label: Text(text(zh: '运维总览', en: 'Overview')),
                ),
                ButtonSegment(
                  value: _OperationsView.pipeline,
                  icon: const Icon(Icons.account_tree_outlined),
                  label: Text(text(zh: '任务管线', en: 'Pipeline')),
                ),
                ButtonSegment(
                  value: _OperationsView.sources,
                  icon: const Icon(Icons.travel_explore_rounded),
                  label: Text(text(zh: '数据源', en: 'Sources')),
                ),
                ButtonSegment(
                  value: _OperationsView.security,
                  icon: const Icon(Icons.shield_outlined),
                  label: Text(text(zh: '安全与依赖', en: 'Security')),
                ),
              ],
              selected: <_OperationsView>{_view},
              onSelectionChanged: (value) =>
                  setState(() => _view = value.first),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: AnimatedSwitcher(
              duration: openHandMotionDuration(
                context,
                const Duration(milliseconds: 220),
              ),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: SingleChildScrollView(
                key: ValueKey<_OperationsView>(_view),
                physics: openHandDialogAwareScrollPhysics(context),
                child: switch (_view) {
                  _OperationsView.overview => _OverviewPanel(
                    controller: controller,
                  ),
                  _OperationsView.pipeline => _PipelinePanel(
                    controller: controller,
                  ),
                  _OperationsView.sources => _SourcesPanel(
                    controller: controller,
                  ),
                  _OperationsView.security => _SecurityPanel(
                    controller: controller,
                  ),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewPanel extends StatelessWidget {
  const _OverviewPanel({required this.controller});
  final ServicesController controller;

  @override
  Widget build(BuildContext context) {
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
        .where((item) => item.finishedAt != null)
        .map(
          (item) => item.finishedAt!
              .difference(item.createdAt)
              .inMilliseconds
              .clamp(0, 86400000)
              .toDouble(),
        )
        .toList(growable: false);
    final averageDuration = durations.isEmpty
        ? 0
        : (durations.reduce((left, right) => left + right) / durations.length)
              .round();
    final historyTrend = history.reversed.take(24).toList(growable: false);
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
          metrics: [
            _Metric(
              Icons.work_history_outlined,
              '任务总数',
              '${history.length}',
              '完成 $completed · 失败 $failed',
              color: Theme.of(context).colorScheme.primary,
            ),
            _Metric(
              Icons.fact_check_outlined,
              '结果总数',
              '${results.length}',
              '有效 $valid',
              color: OpenHandStatusColors.info,
            ),
            _Metric(
              Icons.workspace_premium_outlined,
              '高价值',
              '$highValue',
              '优先处置',
              color: const Color(0xffa855f7),
            ),
            _Metric(
              Icons.radar_rounded,
              '累计处理',
              '$processed',
              '发现 $discovered',
              color: const Color(0xff0891b2),
            ),
            _Metric(
              Icons.timer_outlined,
              '平均任务耗时',
              _duration((averageDuration / 1000).round()),
              '已完成 ${durations.length} 项',
              color: Theme.of(context).colorScheme.tertiary,
            ),
            _Metric(
              Icons.travel_explore_rounded,
              '已配置源',
              '${controller.sourceStatus.values.where((item) => item).length}',
              '共 5 个凭证源',
              color: OpenHandStatusColors.success,
            ),
            _Metric(
              Icons.rule_rounded,
              '启用规则',
              '${controller.rules.where((item) => item.enabled).length}',
              '总计 ${controller.rules.length}',
              color: const Color(0xff0f766e),
            ),
            _Metric(
              Icons.lan_outlined,
              '代理选路',
              '${proxy?.totalSelections ?? 0}',
              proxy?.enabled == true
                  ? '成功 ${proxy!.totalSuccesses} · 超时 ${proxy.totalTimeouts}'
                  : '直接连接',
              color: OpenHandStatusColors.info,
            ),
            _Metric(
              Icons.speed_rounded,
              '代理平均响应',
              '${proxy?.averageResponseTimeMs ?? 0} ms',
              proxy?.enabled == true ? '执行中 ${proxy!.inFlight}' : '代理未启用',
              color: Theme.of(context).colorScheme.secondary,
            ),
            _Metric(
              Icons.warning_amber_rounded,
              '警告日志',
              '$warnings',
              '保留 ${controller.logs.length}',
              color: OpenHandStatusColors.warning,
            ),
            _Metric(
              Icons.error_outline_rounded,
              '错误日志',
              '$errors',
              errors == 0 ? '状态正常' : '需要检查',
              color: OpenHandStatusColors.error,
            ),
            _Metric(
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
              icon: Icons.show_chart_rounded,
              title: '任务处理趋势',
              subtitle: '最近 ${historyTrend.length} 个任务',
              series: <OpenHandChartSeries>[
                OpenHandChartSeries(
                  label: 'processed',
                  values: historyTrend
                      .map((item) => item.progress.processed.toDouble())
                      .toList(growable: false),
                  color: Theme.of(context).colorScheme.primary,
                ),
                OpenHandChartSeries(
                  label: 'valid',
                  values: historyTrend
                      .map((item) => item.progress.valid.toDouble())
                      .toList(growable: false),
                  color: OpenHandStatusColors.success,
                ),
              ],
              suffix: ' 项',
            ),
            _TrendPanel(
              icon: Icons.timelapse_rounded,
              title: '任务耗时趋势',
              subtitle: '仅统计已结束任务',
              series: <OpenHandChartSeries>[
                OpenHandChartSeries(
                  label: 'duration',
                  values: historyTrend
                      .map(
                        (item) =>
                            (item.finishedAt
                                        ?.difference(item.createdAt)
                                        .inMilliseconds ??
                                    0)
                                .clamp(0, 86400000)
                                .toDouble(),
                      )
                      .toList(growable: false),
                  color: Theme.of(context).colorScheme.tertiary,
                ),
              ],
              suffix: ' ms',
            ),
            _DistributionPanel(
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
              '${controller.sourceStatus.values.where((item) => item).length}/5 configured',
              controller.sourceStatus.values.any((item) => item),
            ),
            _consoleLine(
              'proxy',
              proxy?.enabled == true
                  ? '${proxy!.endpoints.length} endpoints · total=${proxy.totalSelections} ok=${proxy.totalSuccesses} failed=${proxy.totalFailures} timeout=${proxy.totalTimeouts} avg=${proxy.averageResponseTimeMs}ms'
                  : 'direct',
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

class _PipelinePanel extends StatelessWidget {
  const _PipelinePanel({required this.controller});
  final ServicesController controller;

  @override
  Widget build(BuildContext context) {
    final progress = controller.progress;
    const stages = <String>[
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
    final trend = history.reversed.take(24).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MetricGrid(
          metrics: [
            _Metric(
              Icons.play_circle_outline_rounded,
              '当前状态',
              progress?.isRunning == true ? '执行中' : '空闲',
              progress == null ? '等待任务' : _stageName(progress.stage),
              color: progress?.isRunning == true
                  ? OpenHandStatusColors.success
                  : Theme.of(context).colorScheme.outline,
            ),
            _Metric(
              Icons.checklist_rounded,
              '累计处理',
              '$totalProcessed',
              '${history.length} 个任务',
              color: Theme.of(context).colorScheme.primary,
            ),
            _Metric(
              Icons.filter_alt_outlined,
              '候选目标',
              '$totalCandidates',
              totalProcessed == 0
                  ? '--'
                  : '${(totalCandidates * 100 / totalProcessed).toStringAsFixed(1)}% 候选率',
              color: OpenHandStatusColors.info,
            ),
            _Metric(
              Icons.verified_outlined,
              '有效结果',
              '$totalValid',
              totalCandidates == 0
                  ? '--'
                  : '${(totalValid * 100 / totalCandidates).toStringAsFixed(1)}% 有效率',
              color: OpenHandStatusColors.success,
            ),
            _Metric(
              Icons.workspace_premium_outlined,
              '高价值结果',
              '$totalHighValue',
              totalValid == 0
                  ? '--'
                  : '${(totalHighValue * 100 / totalValid).toStringAsFixed(1)}% 占有效结果',
              color: const Color(0xffa855f7),
            ),
            _Metric(
              Icons.speed_rounded,
              '任务并发',
              '${controller.defaultConcurrency}',
              '配置上限 128',
              color: Theme.of(context).colorScheme.tertiary,
            ),
            _Metric(
              Icons.layers_outlined,
              '全量扫描',
              '${history.where((item) => item.mode == AiExposureScanMode.full).length}',
              '其余为增量扫描',
              color: const Color(0xff0891b2),
            ),
            _Metric(
              Icons.restart_alt_rounded,
              '可恢复任务',
              '${history.where((item) => item.isResumable).length}',
              '失败或中断任务',
              color: OpenHandStatusColors.warning,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _OpsPanelGrid(
          children: [
            _TrendPanel(
              icon: Icons.multiline_chart_rounded,
              title: '处理漏斗趋势',
              subtitle: '处理 / 候选 / 有效',
              series: <OpenHandChartSeries>[
                OpenHandChartSeries(
                  label: 'processed',
                  values: trend
                      .map((item) => item.progress.processed.toDouble())
                      .toList(growable: false),
                  color: Theme.of(context).colorScheme.primary,
                ),
                OpenHandChartSeries(
                  label: 'candidates',
                  values: trend
                      .map((item) => item.progress.candidates.toDouble())
                      .toList(growable: false),
                  color: OpenHandStatusColors.info,
                ),
                OpenHandChartSeries(
                  label: 'valid',
                  values: trend
                      .map((item) => item.progress.valid.toDouble())
                      .toList(growable: false),
                  color: OpenHandStatusColors.success,
                ),
              ],
              suffix: ' 项',
            ),
            _DistributionPanel(
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
                    LinearProgressIndicator(
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
                    leading: Icon(_stageIcon(item.stage)),
                    title: Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${item.sources.map(_sourceName).join(' / ')} · ${item.progress.processed}/${item.progress.total}',
                    ),
                    trailing: Text(_stageName(item.stage)),
                  );
                })
                .toList(growable: false),
          ),
        ),
      ],
    );
  }
}

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
          metrics: [
            _Metric(
              Icons.key_rounded,
              '已配置凭证源',
              '$configured/5',
              '手工目标无需凭证',
              color: OpenHandStatusColors.success,
            ),
            _Metric(
              Icons.cloud_done_outlined,
              '配额可用源',
              '$available',
              '已完成实时配额探测',
              color: OpenHandStatusColors.info,
            ),
            _Metric(
              Icons.data_usage_rounded,
              '剩余配额',
              '$remaining',
              '仅汇总可计数来源',
              color: Theme.of(context).colorScheme.primary,
            ),
            _Metric(
              Icons.travel_explore_rounded,
              '启用发现源',
              '${controller.enabledSources.length}',
              '共 ${AiExposureSource.values.length} 类',
              color: const Color(0xff0891b2),
            ),
            _Metric(
              Icons.work_history_outlined,
              '来源调用任务',
              '${jobCounts.values.fold<int>(0, (sum, item) => sum + item)}',
              '一个任务可包含多个来源',
              color: Theme.of(context).colorScheme.tertiary,
            ),
            _Metric(
              Icons.fact_check_outlined,
              '来源产出结果',
              '${controller.results.length}',
              '${resultCounts.length} 个来源有产出',
              color: const Color(0xff0f766e),
            ),
            _Metric(
              Icons.warning_amber_rounded,
              '配额异常',
              '${controller.quotas.where((item) => item.configured && !item.available).length}',
              '需检查凭证或网络',
              color: OpenHandStatusColors.warning,
            ),
            _Metric(
              Icons.key_off_outlined,
              '待配置来源',
              '${5 - configured}',
              '可在服务设置中补齐',
              color: Theme.of(context).colorScheme.outline,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _OpsPanelGrid(
          children: [
            _DistributionPanel(
              icon: Icons.pie_chart_outline_rounded,
              title: '结果来源分布',
              centerValue: '${controller.results.length}',
              items: sourceItems,
            ),
            _DistributionPanel(
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
                  final credentialKey = switch (source) {
                    AiExposureSource.github ||
                    AiExposureSource.githubArtifact => 'github',
                    AiExposureSource.gitee => 'gitee',
                    AiExposureSource.gitcode => 'gitcode',
                    AiExposureSource.fofa => 'fofa',
                    AiExposureSource.shodan => 'shodan',
                    AiExposureSource.manual => 'manual',
                  };
                  final isConfigured =
                      source == AiExposureSource.manual ||
                      controller.sourceStatus[credentialKey] == true;
                  final quota = controller.quotas
                      .where((item) => item.source == source)
                      .firstOrNull;
                  final quotaText = quota?.limit == null
                      ? quota?.message
                      : '${quota!.remaining ?? 0}/${quota.limit} · ${quota.message}';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
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
                          (isConfigured ? '凭证已配置，等待配额检查。' : '尚未配置访问凭证。'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: _StatusPill(
                      icon:
                          quota?.available == true ||
                              source == AiExposureSource.manual
                          ? Icons.check_rounded
                          : isConfigured
                          ? Icons.warning_amber_rounded
                          : Icons.key_off_outlined,
                      label:
                          quota?.available == true ||
                              source == AiExposureSource.manual
                          ? '可用'
                          : isConfigured
                          ? '待检查'
                          : '待配置',
                      color:
                          quota?.available == true ||
                              source == AiExposureSource.manual
                          ? OpenHandStatusColors.success
                          : isConfigured
                          ? OpenHandStatusColors.warning
                          : Theme.of(context).colorScheme.outline,
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

class _SecurityPanel extends StatelessWidget {
  const _SecurityPanel({required this.controller});
  final ServicesController controller;

  @override
  Widget build(BuildContext context) {
    final dependencies = controller.dependencyStatus;
    final proxy = controller.proxyStatus;
    final encodings = controller.rules
        .where((rule) => rule.enabled)
        .expand((rule) => rule.contentEncodings)
        .toSet();
    final enabledRules = controller.rules
        .where((rule) => rule.enabled)
        .toList();
    final patterns = enabledRules.fold<int>(
      0,
      (sum, rule) => sum + rule.credentialPatterns.length,
    );
    final contextTerms = enabledRules.fold<int>(
      0,
      (sum, rule) => sum + rule.contextTerms.length,
    );
    final modelPaths = enabledRules.fold<int>(
      0,
      (sum, rule) => sum + rule.modelPaths.length,
    );
    final balancePaths = enabledRules.fold<int>(
      0,
      (sum, rule) => sum + rule.balancePaths.length,
    );
    final vendorCounts = <String, int>{};
    for (final rule in enabledRules) {
      vendorCounts.update(rule.vendor, (value) => value + 1, ifAbsent: () => 1);
    }
    final dependencyReady = <bool>[
      controller.isRunning,
      dependencies?.postgresql.connected == true,
      dependencies?.redis.connected == true,
      controller.aiExtractorStatus?.configured == true,
    ].where((item) => item).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MetricGrid(
          metrics: [
            _Metric(
              Icons.rule_rounded,
              '启用规则',
              '${enabledRules.length}/${controller.rules.length}',
              '${vendorCounts.length} 个供应商',
              color: Theme.of(context).colorScheme.primary,
            ),
            _Metric(
              Icons.fingerprint_rounded,
              '凭证模式',
              '$patterns',
              '$contextTerms 个上下文词',
              color: const Color(0xff0f766e),
            ),
            _Metric(
              Icons.api_rounded,
              '模型端点',
              '$modelPaths',
              '$balancePaths 个余额端点',
              color: OpenHandStatusColors.info,
            ),
            _Metric(
              Icons.code_rounded,
              '编码识别',
              '${encodings.length}/4',
              '多层内容解码',
              color: const Color(0xff0891b2),
            ),
            _Metric(
              Icons.lan_outlined,
              '代理请求',
              '${proxy?.totalSelections ?? 0}',
              proxy?.enabled == true
                  ? '${proxy!.endpoints.length} 个节点'
                  : '直接连接',
              color: Theme.of(context).colorScheme.secondary,
            ),
            _Metric(
              Icons.task_alt_rounded,
              '代理成功',
              '${proxy?.totalSuccesses ?? 0}',
              '${proxy?.averageResponseTimeMs ?? 0} ms 平均响应',
              color: OpenHandStatusColors.success,
            ),
            _Metric(
              Icons.report_gmailerrorred_rounded,
              '代理异常',
              '${(proxy?.totalFailures ?? 0) + (proxy?.totalTimeouts ?? 0)}',
              '失败 ${proxy?.totalFailures ?? 0} · 超时 ${proxy?.totalTimeouts ?? 0}',
              color: OpenHandStatusColors.error,
            ),
            _Metric(
              Icons.hub_outlined,
              '依赖就绪',
              '$dependencyReady/4',
              '核心 / PostgreSQL / Redis / GPT',
              color: dependencyReady >= 1
                  ? OpenHandStatusColors.success
                  : OpenHandStatusColors.warning,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _OpsPanelGrid(
          children: [
            _DistributionPanel(
              icon: Icons.security_rounded,
              title: '代理可靠性分布',
              centerValue: '${proxy?.totalSelections ?? 0}',
              items: [
                _DistributionItem(
                  '成功',
                  proxy?.totalSuccesses ?? 0,
                  OpenHandStatusColors.success,
                ),
                _DistributionItem(
                  '失败',
                  proxy?.totalFailures ?? 0,
                  OpenHandStatusColors.error,
                ),
                _DistributionItem(
                  '超时',
                  proxy?.totalTimeouts ?? 0,
                  OpenHandStatusColors.warning,
                ),
                _DistributionItem(
                  '执行中',
                  proxy?.inFlight ?? 0,
                  OpenHandStatusColors.info,
                ),
              ],
            ),
            _DistributionPanel(
              icon: Icons.category_outlined,
              title: '启用规则供应商分布',
              centerValue: '${enabledRules.length}',
              items: vendorCounts.entries
                  .take(8)
                  .toList(growable: false)
                  .asMap()
                  .entries
                  .map(
                    (entry) => _DistributionItem(
                      entry.value.key,
                      entry.value.value,
                      _chartColor(entry.key, Theme.of(context).colorScheme),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Section(
          title: '扫描规则与编码识别',
          icon: Icons.rule_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '启用 ${controller.rules.where((rule) => rule.enabled).length}/${controller.rules.length} 条规则 · 凭证正则 ${controller.rules.expand((rule) => rule.credentialPatterns).length} 条',
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AiExposureContentEncoding.values
                    .map((encoding) {
                      final enabled = encodings.contains(encoding);
                      return _StatusPill(
                        icon: enabled
                            ? Icons.check_rounded
                            : Icons.remove_rounded,
                        label: switch (encoding) {
                          AiExposureContentEncoding.base64 => 'Base64',
                          AiExposureContentEncoding.base64Url => 'Base64URL',
                          AiExposureContentEncoding.url => 'URL Encoding',
                          AiExposureContentEncoding.hex => 'Hex',
                        },
                        color: enabled
                            ? Colors.green
                            : Theme.of(context).colorScheme.outline,
                      );
                    })
                    .toList(growable: false),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Section(
          title: '网络与代理',
          icon: Icons.lan_outlined,
          child: Column(
            children: [
              _DependencyLine(
                name: '请求出口',
                ready: true,
                detail: proxy?.enabled == true
                    ? '代理池 ${proxy!.endpoints.length} 个节点，累计 ${proxy.totalSelections} 次，执行中 ${proxy.inFlight}'
                    : '直接连接',
              ),
              _DependencyLine(
                name: '代理可靠性',
                ready:
                    proxy?.enabled != true ||
                    (proxy!.totalFailures + proxy.totalTimeouts) == 0,
                detail: proxy?.enabled == true
                    ? '成功 ${proxy!.totalSuccesses} · 失败 ${proxy.totalFailures} · 超时 ${proxy.totalTimeouts} · 平均 ${proxy.averageResponseTimeMs}ms'
                    : '未启用代理统计',
              ),
              _DependencyLine(
                name: '本地旁路',
                ready: proxy?.bypassLocal ?? true,
                detail: proxy?.bypassLocal == true
                    ? '回环、私网和链路本地地址不经过代理'
                    : '所有目标均按代理策略选路',
              ),
              _DependencyLine(
                name: '轮询规则',
                ready: proxy?.enabled == true,
                detail: proxy == null
                    ? '未连接服务'
                    : '${proxy.strategy.id} · 每 ${proxy.rotationEvery} 次请求轮换',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Section(
          title: '运行依赖与子服务',
          icon: Icons.hub_outlined,
          child: Column(
            children: [
              _DependencyLine(
                name: 'ai_jungler',
                ready: controller.isRunning,
                detail: controller.health?.databasePath ?? '自研 Rust 扫描引擎',
              ),
              _DependencyLine(
                name: 'SQLite',
                ready: controller.isRunning,
                detail: '本地任务、规则、结果与日志存储',
              ),
              _DependencyLine(
                name: '资产发现适配器',
                ready: controller.sourceStatus.values.any((item) => item),
                detail:
                    'Manual / GitHub / Gitee / GitCode / FOFA / Shodan，已配置 ${controller.sourceStatus.values.where((item) => item).length}/5',
              ),
              _DependencyLine(
                name: '指纹与规则引擎',
                ready: enabledRules.isNotEmpty,
                detail:
                    '${enabledRules.length} 条启用规则 · $patterns 条凭证模式 · ${encodings.length} 类编码',
              ),
              _DependencyLine(
                name: '主动验证器',
                ready: modelPaths > 0,
                detail: '$modelPaths 个模型端点 · $balancePaths 个余额端点',
              ),
              _DependencyLine(
                name: '任务事件流',
                ready: controller.isRunning,
                detail: controller.hasActiveScan
                    ? '实时推送进度、日志与结果事件'
                    : '已就绪，当前无活动任务',
              ),
              _DependencyLine(
                name: 'PostgreSQL',
                ready: dependencies?.postgresql.connected == true,
                detail: dependencies?.postgresql.message ?? '未启用',
              ),
              _DependencyLine(
                name: 'Redis',
                ready: dependencies?.redis.connected == true,
                detail: dependencies?.redis.message ?? '未启用',
              ),
              _DependencyLine(
                name: 'GPT 辅助提取',
                ready: controller.aiExtractorStatus?.configured == true,
                detail: controller.aiExtractorStatus?.model ?? '未启用',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Metric {
  const _Metric(this.icon, this.label, this.value, this.detail, {this.color});
  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final Color? color;
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics});
  final List<_Metric> metrics;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 1000
          ? 4
          : constraints.maxWidth >= 620
          ? 2
          : 1;
      const gap = 10.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: metrics
            .map(
              (metric) => SizedBox(
                width: width,
                child: _MetricTile(metric: metric),
              ),
            )
            .toList(growable: false),
      );
    },
  );
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.metric});
  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = metric.color ?? cs.primary;
    return Container(
      height: 112,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(metric.icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  metric.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                Text(
                  metric.value,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  metric.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.child,
  });
  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _OpsPanelGrid extends StatelessWidget {
  const _OpsPanelGrid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 820 ? 2 : 1;
      const gap = 12.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: children
            .map((child) => SizedBox(width: width, child: child))
            .toList(growable: false),
      );
    },
  );
}

class _TrendPanel extends StatelessWidget {
  const _TrendPanel({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.series,
    required this.suffix,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<OpenHandChartSeries> series;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      height: 260,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _OpsSectionIcon(icon: icon),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: CustomPaint(
              painter: OpenHandSmoothLineChartPainter(
                series: series,
                gridColor: colors.outlineVariant.withValues(alpha: 0.58),
                labelColor: colors.onSurfaceVariant,
                emptyLabel: '暂无趋势数据',
                valueSuffix: suffix,
                textDirection: Directionality.of(context),
              ),
              size: Size.infinite,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: series
                .map((item) => _OpsLegend(label: item.label, color: item.color))
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _DistributionItem {
  const _DistributionItem(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;
}

class _DistributionPanel extends StatelessWidget {
  const _DistributionPanel({
    required this.icon,
    required this.title,
    required this.centerValue,
    required this.items,
  });

  final IconData icon;
  final String title;
  final String centerValue;
  final List<_DistributionItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final visible = items.where((item) => item.value > 0).take(8).toList();
    final maxValue = visible.fold<int>(
      1,
      (max, item) => item.value > max ? item.value : max,
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 260),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _OpsSectionIcon(icon: icon),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (visible.isEmpty)
            SizedBox(
              height: 174,
              child: Center(
                child: Text(
                  '暂无分布数据',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final donut = SizedBox.square(
                  dimension: 112,
                  child: CustomPaint(
                    painter: OpenHandDonutChartPainter(
                      values: visible.map((item) => item.value).toList(),
                      colors: visible.map((item) => item.color).toList(),
                      trackColor: colors.surfaceContainerHighest,
                    ),
                    child: Center(
                      child: Text(
                        centerValue,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                );
                final rows = Column(
                  children: visible
                      .map(
                        (item) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: item.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 7),
                              SizedBox(
                                width: 74,
                                child: Text(
                                  item.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelMedium,
                                ),
                              ),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(99),
                                  child: LinearProgressIndicator(
                                    value: item.value / maxValue,
                                    minHeight: 7,
                                    color: item.color,
                                    backgroundColor: item.color.withValues(
                                      alpha: 0.1,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 42,
                                child: Text(
                                  '${item.value}',
                                  textAlign: TextAlign.end,
                                  style: theme.textTheme.labelLarge,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(growable: false),
                );
                if (constraints.maxWidth < 430) {
                  return Column(
                    children: [donut, const SizedBox(height: 12), rows],
                  );
                }
                return Row(
                  children: [
                    donut,
                    const SizedBox(width: 18),
                    Expanded(child: rows),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _RecentActivityPanel extends StatelessWidget {
  const _RecentActivityPanel({required this.entries});
  final List<AiExposureLogEntry> entries;

  @override
  Widget build(BuildContext context) => _Section(
    title: '最近运行事件',
    icon: Icons.receipt_long_outlined,
    child: entries.isEmpty
        ? const Text('暂无运行事件。')
        : Column(
            children: entries
                .map((entry) {
                  final color = switch (entry.level) {
                    'error' => OpenHandStatusColors.error,
                    'warning' => OpenHandStatusColors.warning,
                    _ => OpenHandStatusColors.info,
                  };
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 34,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            entry.message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _shortDateTime(entry.at),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  );
                })
                .toList(growable: false),
          ),
  );
}

class _OpsSectionIcon extends StatelessWidget {
  const _OpsSectionIcon({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.primary.withValues(alpha: 0.24)),
      ),
      child: Icon(icon, size: 19, color: colors.primary),
    );
  }
}

class _OpsLegend extends StatelessWidget {
  const _OpsLegend({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}

Color _chartColor(int index, ColorScheme colors) => <Color>[
  colors.primary,
  OpenHandStatusColors.success,
  OpenHandStatusColors.info,
  OpenHandStatusColors.warning,
  const Color(0xffa855f7),
  const Color(0xff0891b2),
  colors.tertiary,
  OpenHandStatusColors.error,
][index % 8];

Color _sourceColor(AiExposureSource source, ColorScheme colors) =>
    switch (source) {
      AiExposureSource.manual => colors.primary,
      AiExposureSource.github => const Color(0xff475569),
      AiExposureSource.githubArtifact => const Color(0xff64748b),
      AiExposureSource.gitee => OpenHandStatusColors.error,
      AiExposureSource.gitcode => const Color(0xff2563eb),
      AiExposureSource.fofa => const Color(0xff0891b2),
      AiExposureSource.shodan => OpenHandStatusColors.warning,
    };

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.11),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.stage,
    required this.completed,
    required this.active,
  });
  final String stage;
  final bool completed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = completed || active ? cs.primary : cs.outline;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        completed
            ? Icons.check_circle_rounded
            : active
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_unchecked_rounded,
        color: color,
      ),
      title: Text(_stageName(stage)),
      trailing: active
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
    );
  }
}

class _DependencyLine extends StatelessWidget {
  const _DependencyLine({
    required this.name,
    required this.ready,
    required this.detail,
  });
  final String name;
  final bool ready;
  final String detail;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(
      ready ? Icons.check_circle_outline_rounded : Icons.circle_outlined,
      color: ready ? Colors.green : Theme.of(context).colorScheme.outline,
    ),
    title: Text(name),
    subtitle: Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis),
    trailing: Text(ready ? '正常' : '未启用'),
  );
}

enum _LogScope { all, current, runtime, history }

class _LogMonitorDialog extends StatefulWidget {
  const _LogMonitorDialog();

  @override
  State<_LogMonitorDialog> createState() => _LogMonitorDialogState();
}

class _LogMonitorDialogState extends State<_LogMonitorDialog> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();
  final Set<String> _levels = <String>{'info', 'warning', 'error', 'runtime'};
  _LogScope _scope = _LogScope.all;
  bool _autoFollow = true;
  bool _refreshing = false;
  int _lastLogCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    await context.read<ServicesController>().refreshServiceLogs();
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ServicesController>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final text = openHandTextResolver(context);
    final logs = _filtered(controller);
    if (_autoFollow && controller.logs.length != _lastLogCount) {
      _lastLogCount = controller.logs.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: openHandMotionDuration(
              context,
              const Duration(milliseconds: 220),
            ),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OpenHandResponsiveHeaderLayout(
            compactBreakpoint: 740,
            identity: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.manage_search_rounded,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text(zh: '服务日志监控', en: 'Service log monitor'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        text(
                          zh: '历史 ${controller.history.length} 个任务 · 当前保留 ${controller.logs.length} 条',
                          en: '${controller.history.length} jobs · ${controller.logs.length} retained',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                IconButton.filledTonal(
                  tooltip: text(zh: '刷新历史日志', en: 'Refresh history'),
                  onPressed: _refreshing || !controller.isRunning
                      ? null
                      : _refresh,
                  icon: _refreshing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
                IconButton.filledTonal(
                  tooltip: text(zh: '保存日志', en: 'Save logs'),
                  onPressed: logs.isEmpty ? null : () => _saveLogs(logs),
                  icon: const Icon(Icons.save_alt_rounded),
                ),
                IconButton.filledTonal(
                  tooltip: text(zh: '清屏', en: 'Clear'),
                  onPressed: controller.logs.isEmpty
                      ? null
                      : controller.clearLogs,
                  icon: const Icon(Icons.cleaning_services_outlined),
                ),
                IconButton.filledTonal(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.vertical_align_bottom_rounded, size: 18),
                    const SizedBox(width: 6),
                    Text(text(zh: '自动跟随', en: 'Auto follow')),
                    const SizedBox(width: 6),
                    Switch(
                      value: _autoFollow,
                      onChanged: (value) => setState(() => _autoFollow = value),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final search = TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  labelText: text(zh: '搜索日志', en: 'Search logs'),
                  border: const OutlineInputBorder(),
                ),
              );
              return search;
            },
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _AnimatedLogScopeTabs(
              value: _scope,
              onChanged: (value) => setState(() => _scope = value),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <String>['info', 'warning', 'error', 'runtime']
                .map((level) {
                  final color = _logColor(level, cs);
                  return ServiceFilterChip(
                    selected: _levels.contains(level),
                    icon: Icon(_logIcon(level), size: 16, color: color),
                    label: Text(_logLevelName(context, level)),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _levels.add(level);
                      } else {
                        _levels.remove(level);
                      }
                    }),
                  );
                })
                .toList(growable: false),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xff0b0e12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: logs.isEmpty
                  ? const Center(
                      child: Text(
                        '没有符合条件的日志。',
                        style: TextStyle(color: Color(0xff9aa4b2)),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: logs.length,
                      itemBuilder: (context, index) =>
                          _LogRow(entry: logs[index]),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            text(
              zh: '显示 ${logs.length} 条 · 信息 ${logs.where((item) => item.level == 'info').length} · 警告 ${logs.where((item) => item.level == 'warning').length} · 错误 ${logs.where((item) => item.level == 'error').length}',
              en: 'Showing ${logs.length} · INFO ${logs.where((item) => item.level == 'info').length} · WARN ${logs.where((item) => item.level == 'warning').length} · ERROR ${logs.where((item) => item.level == 'error').length}',
            ),
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  List<AiExposureLogEntry> _filtered(ServicesController controller) {
    final currentJobId = controller.progress?.jobId ?? '';
    final query = _search.text.trim().toLowerCase();
    return controller.logs
        .where((entry) {
          if (!_levels.contains(entry.level)) return false;
          final inScope = switch (_scope) {
            _LogScope.all => true,
            _LogScope.current =>
              currentJobId.isNotEmpty && entry.jobId == currentJobId,
            _LogScope.runtime =>
              entry.level == 'runtime' || entry.jobId.isEmpty,
            _LogScope.history =>
              entry.jobId.isNotEmpty && entry.jobId != currentJobId,
          };
          return inScope &&
              (query.isEmpty ||
                  entry.message.toLowerCase().contains(query) ||
                  entry.jobId.toLowerCase().contains(query));
        })
        .toList(growable: false);
  }

  Future<void> _saveLogs(List<AiExposureLogEntry> logs) async {
    final location = await getSaveLocation(
      suggestedName:
          'openhand-ai-exposure-${DateTime.now().toIso8601String().replaceAll(':', '-')}.jsonl',
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'JSONL', extensions: <String>['jsonl']),
      ],
    );
    if (location == null) return;
    final payload = logs
        .map(
          (entry) => jsonEncode(<String, Object?>{
            'at': entry.at.toUtc().toIso8601String(),
            'level': entry.level,
            'jobId': entry.jobId,
            'message': entry.message,
          }),
        )
        .join('\n');
    await writeFileAtomically(File(location.path), '$payload\n');
    if (mounted) showOpenHandSuccessSnack(context, '日志已保存。');
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});
  final AiExposureLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = _logColor(entry.level, Theme.of(context).colorScheme);
    final local = entry.at.toLocal();
    final time =
        '${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              time,
              style: const TextStyle(
                color: Color(0xff7e8998),
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
          SizedBox(
            width: 86,
            child: Row(
              children: [
                Icon(_logIcon(entry.level), size: 14, color: color),
                const SizedBox(width: 5),
                Text(
                  _logLevelName(context, entry.level),
                  style: TextStyle(
                    color: color,
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (entry.jobId.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                entry.jobId.substring(0, entry.jobId.length.clamp(0, 8)),
                style: const TextStyle(
                  color: Color(0xff6fa8ed),
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
          Expanded(
            child: SelectableText(
              entry.message,
              style: const TextStyle(
                color: Color(0xffd5dae3),
                fontFamily: 'monospace',
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Color _logColor(String level, ColorScheme cs) => switch (level) {
  'error' => const Color(0xffff5c6c),
  'warning' => const Color(0xffffb14e),
  'runtime' => const Color(0xff6fa8ed),
  _ => const Color(0xff28d17c),
};

IconData _logIcon(String level) => switch (level) {
  'error' => Icons.error_outline_rounded,
  'warning' => Icons.warning_amber_rounded,
  'runtime' => Icons.memory_rounded,
  _ => Icons.info_outline_rounded,
};

String _logLevelName(BuildContext context, String level) {
  final text = openHandTextResolver(context);
  return switch (level) {
    'error' => text(zh: '错误', en: 'ERROR'),
    'warning' => text(zh: '警告', en: 'WARN'),
    'runtime' => text(zh: '运行时', en: 'RUNTIME'),
    _ => text(zh: '信息', en: 'INFO'),
  };
}

class _AnimatedLogScopeTabs extends StatelessWidget {
  const _AnimatedLogScopeTabs({required this.value, required this.onChanged});

  final _LogScope value;
  final ValueChanged<_LogScope> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    final items = <(_LogScope, String)>[
      (_LogScope.all, text(zh: '全部', en: 'All')),
      (_LogScope.current, text(zh: '当前任务', en: 'Current task')),
      (_LogScope.runtime, text(zh: '运行时', en: 'Runtime')),
      (_LogScope.history, text(zh: '历史任务', en: 'History')),
    ];
    return SegmentedButton<_LogScope>(
      segments: [
        for (final item in items)
          ButtonSegment(value: item.$1, label: Text(item.$2)),
      ],
      selected: <_LogScope>{value},
      onSelectionChanged: (next) => onChanged(next.first),
      style: ButtonStyle(
        animationDuration: openHandMotionDuration(
          context,
          const Duration(milliseconds: 280),
        ),
      ),
    );
  }
}

String _duration(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final hours = seconds ~/ 3600;
  final minutes = seconds % 3600 ~/ 60;
  return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
}

String _shortDateTime(DateTime value) =>
    '${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} '
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

String _sourceName(AiExposureSource source) => switch (source) {
  AiExposureSource.manual => '手工目标',
  AiExposureSource.github => 'GitHub',
  AiExposureSource.githubArtifact => 'GitHub Artifact',
  AiExposureSource.gitee => 'Gitee',
  AiExposureSource.gitcode => 'GitCode',
  AiExposureSource.fofa => 'FOFA',
  AiExposureSource.shodan => 'Shodan',
};

IconData _sourceIcon(AiExposureSource source) => switch (source) {
  AiExposureSource.manual => Icons.edit_location_alt_outlined,
  AiExposureSource.github => Icons.code_rounded,
  AiExposureSource.githubArtifact => Icons.inventory_2_outlined,
  AiExposureSource.gitee => Icons.code_rounded,
  AiExposureSource.gitcode => Icons.account_tree_outlined,
  AiExposureSource.fofa => Icons.public_rounded,
  AiExposureSource.shodan => Icons.radar_rounded,
};

String _stageName(String stage) => switch (stage) {
  'queued' => '排队',
  'discovering' => '资产发现',
  'normalizing' => '目标规范化',
  'fingerprinting' => '产品指纹',
  'extracting' => '凭证提取',
  'validating' => '授权验证',
  'persisting' => '关联归档',
  'completed' => '已完成',
  'cancelled' => '已取消',
  'failed' => '失败',
  _ => stage,
};

IconData _stageIcon(String stage) => switch (stage) {
  'completed' => Icons.check_circle_outline_rounded,
  'failed' => Icons.error_outline_rounded,
  'cancelled' => Icons.cancel_outlined,
  _ => Icons.pending_outlined,
};
