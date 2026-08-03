import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
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
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/localized_text.dart';
import '../../../shared/util/timer_safety.dart';
import '../model/ai_exposure_models.dart';
import '../services_controller.dart';
import 'service_dialog_controls.dart';

const Duration _kOperationsRefreshInterval = Duration(seconds: 8);
const Duration _kOperationsMetadataTimeout = Duration(seconds: 2);
const Duration _kOperationsCardMotionDuration = Duration(milliseconds: 150);

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

enum _OperationsView { overview, pipeline, sources, network, storage, security }

class _OperationsDialog extends StatefulWidget {
  const _OperationsDialog();

  @override
  State<_OperationsDialog> createState() => _OperationsDialogState();
}

class _OperationsDialogState extends State<_OperationsDialog> {
  _OperationsView _view = _OperationsView.overview;
  Timer? _timer;
  bool _refreshing = false;
  bool _databaseAccessible = false;
  int? _databaseBytes;
  DateTime? _databaseModifiedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _timer = startSafePeriodicTimer(
      _kOperationsRefreshInterval,
      (_) => _refresh(),
    );
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
    setState(() => _refreshing = true);
    await controller.refreshServiceStatus();
    final path = controller.health?.databasePath.trim() ?? '';
    var accessible = false;
    int? bytes;
    DateTime? modifiedAt;
    if (path.isNotEmpty) {
      try {
        final stat = await File(
          path,
        ).stat().timeout(_kOperationsMetadataTimeout);
        accessible = stat.type == FileSystemEntityType.file;
        if (accessible) {
          bytes = stat.size;
          modifiedAt = stat.modified;
        }
      } on FileSystemException {
        accessible = false;
      } on TimeoutException {
        accessible = false;
      } on UnsupportedError {
        accessible = false;
      }
    }
    if (!mounted) return;
    setState(() {
      _databaseAccessible = accessible;
      _databaseBytes = bytes;
      _databaseModifiedAt = modifiedAt;
      _refreshing = false;
    });
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
                          zh: 'AI 基础设施扫描服务状态与运维',
                          en: 'AI exposure scanner status and operations',
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
                ServiceDialogHeaderIconButton(
                  tooltip: text(zh: '刷新运维数据', en: 'Refresh operations'),
                  onPressed: running && !_refreshing ? _refresh : null,
                  icon: _refreshing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
                ServiceDialogHeaderIconButton(
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
                  tone: ServiceDialogHeaderActionTone.primary,
                ),
                ServiceDialogHeaderIconButton(
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
                label: serviceProxyRouteText(controller, text),
                color: controller.proxyRoute != AiExposureProxyRoute.direct
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _OperationsTab(
                value: _OperationsView.overview,
                selected: _view == _OperationsView.overview,
                icon: Icons.dashboard_outlined,
                label: text(zh: '状态总览', en: 'Status overview'),
                onSelected: (value) => setState(() => _view = value),
              ),
              _OperationsTab(
                value: _OperationsView.pipeline,
                selected: _view == _OperationsView.pipeline,
                icon: Icons.account_tree_outlined,
                label: text(zh: '任务管线', en: 'Pipeline'),
                onSelected: (value) => setState(() => _view = value),
              ),
              _OperationsTab(
                value: _OperationsView.sources,
                selected: _view == _OperationsView.sources,
                icon: Icons.travel_explore_rounded,
                label: text(zh: '数据源', en: 'Sources'),
                onSelected: (value) => setState(() => _view = value),
              ),
              _OperationsTab(
                value: _OperationsView.network,
                selected: _view == _OperationsView.network,
                icon: Icons.lan_outlined,
                label: text(zh: '网络遥测', en: 'Network'),
                onSelected: (value) => setState(() => _view = value),
              ),
              _OperationsTab(
                value: _OperationsView.storage,
                selected: _view == _OperationsView.storage,
                icon: Icons.storage_rounded,
                label: text(zh: '存储与持久化', en: 'Storage'),
                onSelected: (value) => setState(() => _view = value),
              ),
              _OperationsTab(
                value: _OperationsView.security,
                selected: _view == _OperationsView.security,
                icon: Icons.shield_outlined,
                label: text(zh: '安全与依赖', en: 'Security'),
                onSelected: (value) => setState(() => _view = value),
              ),
            ],
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
                  _OperationsView.network => _NetworkPanel(
                    controller: controller,
                  ),
                  _OperationsView.storage => _StoragePanel(
                    controller: controller,
                    databaseAccessible: _databaseAccessible,
                    databaseBytes: _databaseBytes,
                    databaseModifiedAt: _databaseModifiedAt,
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

class _OperationsTab extends StatelessWidget {
  const _OperationsTab({
    required this.value,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onSelected,
  });

  final _OperationsView value;
  final bool selected;
  final IconData icon;
  final String label;
  final ValueChanged<_OperationsView> onSelected;

  @override
  Widget build(BuildContext context) => ServiceFilterChip(
    selected: selected,
    icon: Icon(icon, size: 17),
    label: Text(label),
    onSelected: (_) => onSelected(value),
  );
}

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
          title: '状态总览',
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
              controller.proxyRoute == AiExposureProxyRoute.pool
                  ? '成功 ${proxy?.totalSuccesses ?? 0} · 超时 ${proxy?.totalTimeouts ?? 0}'
                  : serviceProxyRouteText(controller, text),
              color: OpenHandStatusColors.info,
            ),
            _Metric(
              Icons.speed_rounded,
              '代理平均响应',
              '${proxy?.averageResponseTimeMs ?? 0} ms',
              controller.proxyRoute == AiExposureProxyRoute.pool
                  ? '执行中 ${proxy?.inFlight ?? 0}'
                  : serviceProxyRouteText(controller, text),
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
              sampleLabels: historyTrend
                  .map((item) => _shortDateTime(item.createdAt))
                  .toList(growable: false),
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
              sampleLabels: historyTrend
                  .map((item) => _shortDateTime(item.createdAt))
                  .toList(growable: false),
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
          title: '任务管线',
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
              sampleLabels: trend
                  .map((item) => _shortDateTime(item.createdAt))
                  .toList(growable: false),
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
          title: '数据源',
          metrics: [
            _Metric(
              Icons.cloud_done_outlined,
              '已就绪来源',
              '$configured/${controller.discoverySourceCount}',
              '论坛来源无需 API 凭证',
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
                    AiExposureSource.nodeseek => 'nodeseek',
                    AiExposureSource.linuxDo => 'linuxDo',
                    AiExposureSource.v2ex => 'v2ex',
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

class _NetworkPanel extends StatelessWidget {
  const _NetworkPanel({required this.controller});

  final ServicesController controller;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = openHandTextResolver(context);
    final configuration = controller.proxyConfiguration;
    final endpoints = configuration.endpoints;
    final activeEndpoints = configuration.activeEndpoints;
    final inspected = endpoints
        .where((endpoint) => endpoint.latestSample != null)
        .length;
    final reachable = endpoints
        .where((endpoint) => endpoint.latestSample?.reachable == true)
        .length;
    final recentRequests =
        endpoints
            .expand((endpoint) => endpoint.statistics.recentRequests)
            .toList()
          ..sort((left, right) => left.at.compareTo(right.at));
    final visibleRequests = recentRequests.length <= 48
        ? recentRequests
        : recentRequests.sublist(recentRequests.length - 48);
    final requests = endpoints.fold<int>(
      0,
      (sum, endpoint) => sum + endpoint.statistics.requests,
    );
    final successes = endpoints.fold<int>(
      0,
      (sum, endpoint) => sum + endpoint.statistics.successes,
    );
    final failures = endpoints.fold<int>(
      0,
      (sum, endpoint) => sum + endpoint.statistics.failures,
    );
    final timeouts = endpoints.fold<int>(
      0,
      (sum, endpoint) => sum + endpoint.statistics.timeouts,
    );
    final totalResponseTime = endpoints.fold<int>(
      0,
      (sum, endpoint) => sum + endpoint.statistics.totalResponseTimeMs,
    );
    final completed = successes + failures + timeouts;
    final averageLatency = completed == 0
        ? 0
        : (totalResponseTime / completed).round();
    final p95Latency = _latencyPercentile(
      visibleRequests.map((sample) => sample.responseTimeMs).toList(),
      0.95,
    );
    final status2xx = endpoints.fold<int>(
      0,
      (sum, endpoint) => sum + endpoint.statistics.status2xx,
    );
    final status3xx = endpoints.fold<int>(
      0,
      (sum, endpoint) => sum + endpoint.statistics.status3xx,
    );
    final status4xx = endpoints.fold<int>(
      0,
      (sum, endpoint) => sum + endpoint.statistics.status4xx,
    );
    final status5xx = endpoints.fold<int>(
      0,
      (sum, endpoint) => sum + endpoint.statistics.status5xx,
    );
    final countryCounts = <String, int>{};
    for (final endpoint in endpoints) {
      final country = endpoint.identity?.country.trim();
      if (country?.isNotEmpty == true) {
        countryCounts.update(country!, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    final endpointItems =
        endpoints
            .map(
              (endpoint) => _DistributionItem(
                endpoint.displayName,
                endpoint.statistics.requests,
                endpoint.latestSample?.reachable == false
                    ? OpenHandStatusColors.error
                    : endpoint.enabled
                    ? colors.primary
                    : colors.outline,
              ),
            )
            .toList()
          ..sort((left, right) => right.value.compareTo(left.value));
    final successRate = completed == 0 ? 0 : successes * 100 / completed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MetricGrid(
          title: '网络遥测',
          metrics: [
            _Metric(
              Icons.route_outlined,
              '选路状态',
              serviceProxyRouteText(controller, text, includePoolCount: false),
              controller.proxyRoute == AiExposureProxyRoute.pool
                  ? _proxyStrategyName(configuration.strategy)
                  : serviceProxyRouteText(controller, text),
              color: controller.proxyRoute == AiExposureProxyRoute.direct
                  ? colors.outline
                  : controller.proxyRoute == AiExposureProxyRoute.pool
                  ? colors.primary
                  : colors.tertiary,
            ),
            _Metric(
              Icons.dns_outlined,
              '代理节点',
              '${activeEndpoints.length}/${endpoints.length}',
              '$inspected 个已巡检',
              color: OpenHandStatusColors.info,
            ),
            _Metric(
              Icons.cloud_done_outlined,
              '可连通节点',
              '$reachable',
              inspected == 0
                  ? '尚无巡检样本'
                  : '${(reachable * 100 / inspected).toStringAsFixed(1)}% 可用率',
              color: OpenHandStatusColors.success,
            ),
            _Metric(
              Icons.swap_vert_rounded,
              '累计请求',
              '$requests',
              '执行中 ${controller.proxyStatus?.inFlight ?? 0}',
              color: colors.primary,
            ),
            _Metric(
              Icons.check_circle_outline_rounded,
              '成功请求',
              '$successes',
              '${successRate.toStringAsFixed(1)}% 成功率',
              color: OpenHandStatusColors.success,
            ),
            _Metric(
              Icons.error_outline_rounded,
              '失败请求',
              '$failures',
              '连续失败 ${endpoints.fold<int>(0, (sum, endpoint) => sum + endpoint.statistics.consecutiveFailures)}',
              color: OpenHandStatusColors.error,
            ),
            _Metric(
              Icons.timer_off_outlined,
              '超时请求',
              '$timeouts',
              completed == 0
                  ? '--'
                  : '${(timeouts * 100 / completed).toStringAsFixed(1)}% 超时率',
              color: OpenHandStatusColors.warning,
            ),
            _Metric(
              Icons.speed_rounded,
              '平均响应',
              '$averageLatency ms',
              '全量完成请求',
              color: colors.secondary,
            ),
            _Metric(
              Icons.multiline_chart_rounded,
              'p95 响应',
              '$p95Latency ms',
              '最近 ${visibleRequests.length} 个样本',
              color: colors.tertiary,
            ),
            _Metric(
              Icons.http_rounded,
              'HTTP 2xx',
              '$status2xx',
              '3xx $status3xx · 4xx $status4xx · 5xx $status5xx',
              color: OpenHandStatusColors.success,
            ),
            _Metric(
              Icons.public_rounded,
              '出口国家',
              '${countryCounts.length}',
              '${endpoints.where((endpoint) => endpoint.identity != null).length} 个已识别出口',
              color: const Color(0xff0891b2),
            ),
            _Metric(
              Icons.health_and_safety_outlined,
              '巡检计划',
              configuration.inspectionEnabled ? '已启用' : '未启用',
              '${configuration.inspectionIntervalMinutes} 分钟 · 并发 ${configuration.inspectionConcurrency}',
              color: configuration.inspectionEnabled
                  ? OpenHandStatusColors.success
                  : colors.outline,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _OpsPanelGrid(
          children: [
            _TrendPanel(
              icon: Icons.query_stats_rounded,
              title: '代理响应耗时趋势',
              subtitle: '最近 ${visibleRequests.length} 个请求样本',
              sampleLabels: visibleRequests
                  .map((sample) => _shortDateTime(sample.at))
                  .toList(growable: false),
              series: [
                OpenHandChartSeries(
                  label: 'response',
                  values: visibleRequests
                      .map((sample) => sample.responseTimeMs.toDouble())
                      .toList(),
                  color: colors.primary,
                ),
              ],
              suffix: ' ms',
            ),
            _DistributionPanel(
              icon: Icons.donut_large_rounded,
              title: '请求结果分布',
              centerValue: '$completed',
              items: [
                _DistributionItem(
                  '成功',
                  successes,
                  OpenHandStatusColors.success,
                ),
                _DistributionItem('失败', failures, OpenHandStatusColors.error),
                _DistributionItem('超时', timeouts, OpenHandStatusColors.warning),
              ],
            ),
            _DistributionPanel(
              icon: Icons.http_rounded,
              title: 'HTTP 状态分布',
              centerValue: '${status2xx + status3xx + status4xx + status5xx}',
              items: [
                _DistributionItem(
                  '2xx',
                  status2xx,
                  OpenHandStatusColors.success,
                ),
                _DistributionItem('3xx', status3xx, OpenHandStatusColors.info),
                _DistributionItem(
                  '4xx',
                  status4xx,
                  OpenHandStatusColors.warning,
                ),
                _DistributionItem('5xx', status5xx, OpenHandStatusColors.error),
              ],
            ),
            _DistributionPanel(
              icon: Icons.account_tree_outlined,
              title: '节点请求分布',
              centerValue: '$requests',
              items: endpointItems,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _OpsPanelGrid(
          children: [
            _Section(
              title: '选路策略快照',
              icon: Icons.alt_route_rounded,
              child: Column(
                children: [
                  _OpsKeyValue(
                    label: '调度策略',
                    value: _proxyStrategyName(configuration.strategy),
                  ),
                  _OpsKeyValue(
                    label: '轮换频率',
                    value: '每 ${configuration.rotationEvery} 次请求',
                  ),
                  _OpsKeyValue(
                    label: '本地地址绕过',
                    value: configuration.bypassLocal ? '已启用' : '已停用',
                  ),
                  _OpsKeyValue(
                    label: '自动巡检',
                    value: configuration.inspectionEnabled
                        ? '${configuration.inspectionIntervalMinutes} 分钟一次'
                        : '未启用',
                  ),
                  _OpsKeyValue(
                    label: '巡检并发',
                    value: '${configuration.inspectionConcurrency}',
                  ),
                  _OpsKeyValue(
                    label: '持久化样本',
                    value: '${recentRequests.length} 条请求遥测',
                  ),
                ],
              ),
            ),
            _Section(
              title: '出口地域分布',
              icon: Icons.public_rounded,
              child: countryCounts.isEmpty
                  ? const Text('尚未采集代理出口身份。')
                  : Column(
                      children:
                          (countryCounts.entries.toList()..sort(
                                (left, right) =>
                                    right.value.compareTo(left.value),
                              ))
                              .map(
                                (entry) => _DistributionBar(
                                  label: entry.key,
                                  value: entry.value,
                                  maxValue: countryCounts.values.fold<int>(
                                    1,
                                    (max, value) => value > max ? value : max,
                                  ),
                                  color: colors.tertiary,
                                ),
                              )
                              .toList(),
                    ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Section(
          title: '代理端点健康明细',
          icon: Icons.dns_outlined,
          child: endpoints.isEmpty
              ? Text(
                  text(
                    zh: '代理池为空，当前请求使用 ${serviceProxyRouteText(controller, text)}。',
                    en: 'The proxy pool is empty. Requests currently use ${serviceProxyRouteText(controller, text)}.',
                  ),
                )
              : Column(
                  children: endpoints.take(20).map((endpoint) {
                    final sample = endpoint.latestSample;
                    final statistics = endpoint.statistics;
                    final color = !endpoint.enabled
                        ? colors.outline
                        : sample?.reachable == false
                        ? OpenHandStatusColors.error
                        : sample?.reachable == true
                        ? OpenHandStatusColors.success
                        : OpenHandStatusColors.warning;
                    final identity = endpoint.identity;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: color.withValues(alpha: 0.12),
                        child: Icon(Icons.lan_outlined, size: 18, color: color),
                      ),
                      title: Text(
                        endpoint.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${endpoint.maskedUrl} · ${identity?.exitIp.isNotEmpty == true ? identity!.exitIp : '出口待识别'} · ${identity?.location.isNotEmpty == true ? identity!.location : '地域待识别'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: _StatusPill(
                        icon: sample?.reachable == true
                            ? Icons.check_rounded
                            : sample?.reachable == false
                            ? Icons.close_rounded
                            : Icons.pending_outlined,
                        label:
                            '${sample?.latencyMs ?? 0} ms · ${statistics.requests} 次',
                        color: color,
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }
}

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
    final orphanResults = results
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
    final integrityIssues = orphanResults + missingEvidence;
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
              Icons.storage_rounded,
              'SQLite 数据库',
              databaseAccessible ? formatByteSize(databaseBytes ?? 0) : '--',
              databaseAccessible ? 'WAL 持久化可访问' : '等待本地服务路径',
              color: databaseAccessible
                  ? OpenHandStatusColors.success
                  : colors.outline,
            ),
            _Metric(
              Icons.edit_calendar_outlined,
              '最后写入',
              databaseModifiedAt == null
                  ? '--'
                  : _shortDateTime(databaseModifiedAt!),
              '数据库文件修改时间',
              color: colors.primary,
            ),
            _Metric(
              Icons.inventory_2_outlined,
              '可见记录',
              '$recordCount',
              '任务、结果、规则与日志',
              color: OpenHandStatusColors.info,
            ),
            _Metric(
              Icons.work_history_outlined,
              '任务归档',
              '${history.length}',
              '$unfinished 个未结束',
              color: colors.primary,
            ),
            _Metric(
              Icons.fact_check_outlined,
              '结果归档',
              '${results.length}',
              '$missingEvidence 条缺少证据',
              color: const Color(0xff0891b2),
            ),
            _Metric(
              Icons.rule_folder_outlined,
              '规则快照',
              '${rules.length}',
              '${rules.where((rule) => rule.enabled).length} 条启用',
              color: const Color(0xff0f766e),
            ),
            _Metric(
              Icons.receipt_long_outlined,
              '日志缓冲',
              '${logs.length}',
              '信息 ${logs.where((entry) => entry.level == 'info').length} · 错误 ${logs.where((entry) => entry.level == 'error').length}',
              color: colors.secondary,
            ),
            _Metric(
              Icons.restart_alt_rounded,
              '可恢复任务',
              '$resumable',
              '失败 $failed · 未结束 $unfinished',
              color: OpenHandStatusColors.warning,
            ),
            _Metric(
              Icons.cloud_sync_outlined,
              'PostgreSQL 镜像',
              dependencies?.postgresql.connected == true ? '在线' : '未连接',
              dependencies?.postgresql.message ?? '未启用',
              color: dependencies?.postgresql.connected == true
                  ? OpenHandStatusColors.success
                  : colors.outline,
            ),
            _Metric(
              Icons.hub_outlined,
              'Redis 协调',
              dependencies?.redis.connected == true ? '在线' : '未连接',
              dependencies?.redis.message ?? '未启用',
              color: dependencies?.redis.connected == true
                  ? OpenHandStatusColors.success
                  : colors.outline,
            ),
            _Metric(
              Icons.enhanced_encryption_outlined,
              '凭证加密',
              'AES-256-GCM',
              '密钥文件独立保存',
              color: colors.tertiary,
            ),
            _Metric(
              integrityIssues == 0
                  ? Icons.verified_outlined
                  : Icons.warning_amber_rounded,
              '一致性审计',
              integrityIssues == 0 ? '通过' : '$integrityIssues 项',
              '孤立结果 $orphanResults · 缺少证据 $missingEvidence',
              color: integrityIssues == 0
                  ? OpenHandStatusColors.success
                  : OpenHandStatusColors.warning,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _OpsPanelGrid(
          children: [
            _TrendPanel(
              icon: Icons.stacked_line_chart_rounded,
              title: '归档增长趋势',
              subtitle: '最近 ${chronological.length} 个任务的累计结果',
              sampleLabels: chronological
                  .map((entry) => _shortDateTime(entry.createdAt))
                  .toList(growable: false),
              series: [
                OpenHandChartSeries(
                  label: 'results',
                  values: cumulativeResultValues,
                  color: colors.primary,
                ),
              ],
              suffix: ' 条',
            ),
            _TrendPanel(
              icon: Icons.data_saver_on_rounded,
              title: '任务写入负载',
              subtitle: '已处理与发现记录',
              sampleLabels: chronological
                  .map((entry) => _shortDateTime(entry.createdAt))
                  .toList(growable: false),
              series: [
                OpenHandChartSeries(
                  label: 'processed',
                  values: chronological
                      .map((entry) => entry.progress.processed.toDouble())
                      .toList(),
                  color: OpenHandStatusColors.info,
                ),
                OpenHandChartSeries(
                  label: 'discovered',
                  values: chronological
                      .map((entry) => entry.progress.discovered.toDouble())
                      .toList(),
                  color: OpenHandStatusColors.success,
                ),
              ],
              suffix: ' 条',
            ),
            _DistributionPanel(
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
              icon: Icons.key_outlined,
              title: '凭证状态分布',
              centerValue: '${results.length}',
              items: credentialCounts.entries
                  .map(
                    (entry) => _DistributionItem(
                      entry.key,
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
                    name: 'SQLite',
                    ready: databaseAccessible,
                    detail: databaseAccessible
                        ? 'WAL 日志模式 · 外键约束开启 · ${formatByteSize(databaseBytes ?? 0)}'
                        : '等待本地数据库文件',
                  ),
                  _DependencyLine(
                    name: '凭证密钥库',
                    ready: controller.isRunning,
                    detail: 'AES-256-GCM · 数据库与密钥文件权限隔离',
                  ),
                  _DependencyLine(
                    name: 'PostgreSQL 镜像',
                    ready: dependencies?.postgresql.connected == true,
                    detail: dependencies?.postgresql.message ?? '未启用',
                  ),
                  _DependencyLine(
                    name: 'Redis 目标协调',
                    ready: dependencies?.redis.connected == true,
                    detail: dependencies?.redis.message ?? '未启用',
                  ),
                  _DependencyLine(
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
                  _OpsKeyValue(label: '孤立结果', value: '$orphanResults'),
                  _OpsKeyValue(label: '缺少证据结果', value: '$missingEvidence'),
                  _OpsKeyValue(label: '未结束任务', value: '$unfinished'),
                  _OpsKeyValue(label: '可恢复任务', value: '$resumable'),
                  _OpsKeyValue(label: '失败任务', value: '$failed'),
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
                      leading: Icon(_stageIcon(entry.stage)),
                      title: Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${_shortDateTime(entry.finishedAt ?? entry.createdAt)} · 处理 ${entry.progress.processed} · 结果 $resultCount',
                      ),
                      trailing: _StatusPill(
                        icon: _stageIcon(entry.stage),
                        label: _stageName(entry.stage),
                        color: entry.stage == 'completed'
                            ? OpenHandStatusColors.success
                            : entry.stage == 'failed'
                            ? OpenHandStatusColors.error
                            : OpenHandStatusColors.warning,
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
            child: SelectableText(
              controller.health!.databasePath,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ],
      ],
    );
  }
}

class _SecurityPanel extends StatelessWidget {
  const _SecurityPanel({required this.controller});
  final ServicesController controller;

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
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
          title: '安全与依赖',
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
              serviceProxyRouteText(controller, text),
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
                detail: controller.proxyRoute == AiExposureProxyRoute.pool
                    ? '代理池 ${proxy?.endpoints.length ?? 0} 个节点，累计 ${proxy?.totalSelections ?? 0} 次，执行中 ${proxy?.inFlight ?? 0}'
                    : serviceProxyRouteText(controller, text),
              ),
              _DependencyLine(
                name: '代理可靠性',
                ready:
                    controller.proxyRoute != AiExposureProxyRoute.pool ||
                    (proxy?.totalFailures ?? 0) + (proxy?.totalTimeouts ?? 0) ==
                        0,
                detail: controller.proxyRoute == AiExposureProxyRoute.pool
                    ? '成功 ${proxy?.totalSuccesses ?? 0} · 失败 ${proxy?.totalFailures ?? 0} · 超时 ${proxy?.totalTimeouts ?? 0} · 平均 ${proxy?.averageResponseTimeMs ?? 0}ms'
                    : '代理池当前未参与选路',
              ),
              _DependencyLine(
                name: '本地旁路',
                ready: proxy?.bypassLocal ?? true,
                detail: proxy?.bypassLocal == true
                    ? '回环、私网和链路本地地址绕过代理池，再按系统代理规则选路'
                    : '所有目标均按代理策略选路',
              ),
              _DependencyLine(
                name: '轮询规则',
                ready: controller.proxyRoute == AiExposureProxyRoute.pool,
                detail:
                    controller.proxyRoute == AiExposureProxyRoute.pool &&
                        proxy != null
                    ? '${proxy.strategy.id} · 每 ${proxy.rotationEvery} 次请求轮换'
                    : '代理池当前未参与选路',
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
                    '代码托管 / 测绘平台 / NodeSeek / LINUX DO / V2EX，已就绪 ${controller.sourceStatus.values.where((item) => item).length}/${controller.discoverySourceCount}',
              ),
              _DependencyLine(
                name: 'Playwright 浏览器通道',
                ready: dependencies?.playwright.connected == true,
                detail: dependencies?.playwright.message ?? '未接入浏览器降级通道',
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

class _MetricGrid extends StatefulWidget {
  const _MetricGrid({required this.title, required this.metrics});
  final String title;
  final List<_Metric> metrics;

  @override
  State<_MetricGrid> createState() => _MetricGridState();
}

class _MetricGridState extends State<_MetricGrid> {
  late final ValueNotifier<List<_Metric>> _liveMetrics = ValueNotifier(
    widget.metrics,
  );

  @override
  void didUpdateWidget(_MetricGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    _liveMetrics.value = widget.metrics;
  }

  @override
  void dispose() {
    _liveMetrics.dispose();
    super.dispose();
  }

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
        children: widget.metrics
            .map(
              (metric) => SizedBox(
                width: width,
                child: _MetricTile(
                  metric: metric,
                  onTap: () => _showMetricInsight(
                    context,
                    title: widget.title,
                    selected: metric,
                    metrics: _liveMetrics,
                  ),
                ),
              ),
            )
            .toList(growable: false),
      );
    },
  );
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.metric, this.onTap});
  final _Metric metric;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = metric.color ?? cs.primary;
    return _TappableOpsCard(
      onTap: onTap,
      color: color,
      child: Container(
        constraints: const BoxConstraints(minHeight: 112),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
            if (onTap != null) ...[
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: color.withValues(alpha: 0.72),
              ),
            ],
          ],
        ),
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

class _OpsKeyValue extends StatelessWidget {
  const _OpsKeyValue({
    required this.label,
    required this.value,
    this.color,
    this.maxLines = 2,
  });

  final String label;
  final String value;
  final Color? color;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: Text(
              value,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: theme.textTheme.labelLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DistributionBar extends StatelessWidget {
  const _DistributionBar({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.color,
  });

  final String label;
  final int value;
  final int maxValue;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: maxValue <= 0 ? 0 : value / maxValue,
              minHeight: 8,
              color: color,
              backgroundColor: color.withValues(alpha: 0.1),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 42,
          child: Text(
            '$value',
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
      ],
    ),
  );
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

class _TrendPanel extends StatefulWidget {
  const _TrendPanel({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.sampleLabels,
    required this.series,
    required this.suffix,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> sampleLabels;
  final List<OpenHandChartSeries> series;
  final String suffix;

  @override
  State<_TrendPanel> createState() => _TrendPanelState();
}

class _TrendPanelState extends State<_TrendPanel> {
  late final ValueNotifier<List<OpenHandChartSeries>> _liveSeries =
      ValueNotifier(widget.series);
  late final ValueNotifier<List<String>> _liveSampleLabels = ValueNotifier(
    widget.sampleLabels,
  );

  @override
  void didUpdateWidget(_TrendPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _liveSeries.value = widget.series;
    _liveSampleLabels.value = widget.sampleLabels;
  }

  @override
  void dispose() {
    _liveSeries.dispose();
    _liveSampleLabels.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return _TappableOpsCard(
      color: colors.primary,
      onTap: () => _showTrendInsight(
        context,
        icon: widget.icon,
        title: widget.title,
        subtitle: widget.subtitle,
        series: _liveSeries,
        sampleLabels: _liveSampleLabels,
        suffix: widget.suffix,
      ),
      child: Container(
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
                _OpsSectionIcon(icon: widget.icon),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        widget.subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.open_in_new_rounded,
                  size: 17,
                  color: colors.primary.withValues(alpha: 0.72),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: OpenHandSmoothLineChartPainter(
                    series: widget.series,
                    gridColor: colors.outlineVariant.withValues(alpha: 0.58),
                    labelColor: colors.onSurfaceVariant,
                    emptyLabel: '暂无趋势数据',
                    valueSuffix: widget.suffix,
                    textDirection: Directionality.of(context),
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: widget.series
                  .map(
                    (item) => _OpsLegend(label: item.label, color: item.color),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
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

class _DistributionPanel extends StatefulWidget {
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
  State<_DistributionPanel> createState() => _DistributionPanelState();
}

class _DistributionPanelState extends State<_DistributionPanel> {
  late final ValueNotifier<List<_DistributionItem>> _liveItems = ValueNotifier(
    widget.items,
  );

  @override
  void didUpdateWidget(_DistributionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _liveItems.value = widget.items;
  }

  @override
  void dispose() {
    _liveItems.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final visible = widget.items
        .where((item) => item.value > 0)
        .take(8)
        .toList();
    final maxValue = visible.fold<int>(
      1,
      (max, item) => item.value > max ? item.value : max,
    );
    return _TappableOpsCard(
      color: colors.primary,
      onTap: () => _showDistributionInsight(
        context,
        icon: widget.icon,
        title: widget.title,
        centerValue: widget.centerValue,
        items: _liveItems,
      ),
      child: Container(
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
                _OpsSectionIcon(icon: widget.icon),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    widget.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Icon(
                  Icons.open_in_new_rounded,
                  size: 17,
                  color: colors.primary.withValues(alpha: 0.72),
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
                          widget.centerValue,
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
      ),
    );
  }
}

class _TappableOpsCard extends StatefulWidget {
  const _TappableOpsCard({
    required this.child,
    required this.color,
    this.onTap,
  });

  final Widget child;
  final Color color;
  final VoidCallback? onTap;

  @override
  State<_TappableOpsCard> createState() => _TappableOpsCardState();
}

class _TappableOpsCardState extends State<_TappableOpsCard> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.child;
    final duration = openHandMotionDuration(
      context,
      _kOperationsCardMotionDuration,
    );
    return Semantics(
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _pressed ? 0.975 : 1,
            duration: duration,
            curve: Curves.easeOutCubic,
            child: Stack(
              children: [
                widget.child,
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedContainer(
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      decoration: BoxDecoration(
                        color: widget.color.withValues(
                          alpha: _pressed
                              ? 0.09
                              : _hovered
                              ? 0.045
                              : 0,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _hovered || _pressed
                              ? widget.color.withValues(alpha: 0.38)
                              : Colors.transparent,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void _showMetricInsight(
  BuildContext context, {
  required String title,
  required _Metric selected,
  required ValueListenable<List<_Metric>> metrics,
}) {
  final selectedIndex = metrics.value.indexOf(selected);
  showAnimatedDialog<void>(
    context: context,
    builder: (_) => _OperationsInsightDialog(
      icon: selected.icon,
      title: selected.label,
      subtitle: '$title · 指标详情',
      color: selected.color,
      child: ValueListenableBuilder<List<_Metric>>(
        valueListenable: metrics,
        builder: (context, values, _) {
          final liveSelected =
              selectedIndex >= 0 && selectedIndex < values.length
              ? values[selectedIndex]
              : selected;
          return _MetricInsightBody(
            sectionTitle: title,
            selected: liveSelected,
          );
        },
      ),
    ),
  );
}

void _showTrendInsight(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String subtitle,
  required ValueListenable<List<OpenHandChartSeries>> series,
  required ValueListenable<List<String>> sampleLabels,
  required String suffix,
}) {
  showAnimatedDialog<void>(
    context: context,
    builder: (_) => _OperationsInsightDialog(
      icon: icon,
      title: title,
      subtitle: subtitle,
      child: AnimatedBuilder(
        animation: Listenable.merge([series, sampleLabels]),
        builder: (context, _) => _TrendInsightBody(
          title: title,
          series: series.value,
          sampleLabels: sampleLabels.value,
          suffix: suffix,
        ),
      ),
    ),
  );
}

void _showDistributionInsight(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String centerValue,
  required ValueListenable<List<_DistributionItem>> items,
}) {
  showAnimatedDialog<void>(
    context: context,
    builder: (_) => _OperationsInsightDialog(
      icon: icon,
      title: title,
      subtitle: '完整分布 · 总计 $centerValue',
      child: ValueListenableBuilder<List<_DistributionItem>>(
        valueListenable: items,
        builder: (context, values, _) =>
            _DistributionInsightBody(title: title, items: values),
      ),
    ),
  );
}

class _OperationsInsightDialog extends StatelessWidget {
  const _OperationsInsightDialog({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tone = color ?? colors.primary;
    return OpenHandEscapeDismissScope(
      child: buildOpenHandResponsiveDialogShell(
        context: context,
        maxWidth: kOpenHandDialogWidthWide,
        maxHeight: kOpenHandDialogHeightTall,
        maxWidthFraction: 0.92,
        maxHeightFraction: 0.9,
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ServiceDialogInteractionTheme(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: tone.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: tone.withValues(alpha: 0.28)),
                      ),
                      child: Icon(icon, color: tone),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ServiceDialogHeaderIconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Divider(height: 1, color: colors.outlineVariant),
                const SizedBox(height: 14),
                Expanded(
                  child: SingleChildScrollView(
                    physics: openHandDialogAwareScrollPhysics(context),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricInsightBody extends StatelessWidget {
  const _MetricInsightBody({
    required this.sectionTitle,
    required this.selected,
  });

  final String sectionTitle;
  final _Metric selected;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ServicesController>();
    final analysis = _serviceMetricAnalysisSections(
      context,
      section: sectionTitle,
      label: selected.label,
      controller: controller,
    );
    final details = _serviceMetricDetailSections(
      context,
      section: sectionTitle,
      label: selected.label,
      controller: controller,
    );
    final sections = [...analysis, ...details];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final section in sections.indexed) ...[
          if (section.$1 > 0) const SizedBox(height: 14),
          section.$2,
        ],
      ],
    );
  }
}

class _TrendInsightBody extends StatelessWidget {
  const _TrendInsightBody({
    required this.title,
    required this.series,
    required this.sampleLabels,
    required this.suffix,
  });
  final String title;
  final List<OpenHandChartSeries> series;
  final List<String> sampleLabels;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final spec = _trendInsightSpec(title);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Section(
          title: spec.chartTitle,
          icon: Icons.multiline_chart_rounded,
          child: SizedBox(
            height: 300,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: OpenHandSmoothLineChartPainter(
                  series: series,
                  gridColor: colors.outlineVariant.withValues(alpha: 0.58),
                  labelColor: colors.onSurfaceVariant,
                  emptyLabel: '暂无趋势样本',
                  valueSuffix: suffix,
                  textDirection: Directionality.of(context),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _Section(
          title: '${spec.statisticsTitle} · 逐样本明细',
          icon: Icons.query_stats_rounded,
          child: _TrendSampleTable(
            series: series,
            sampleLabels: sampleLabels,
            suffix: suffix,
          ),
        ),
      ],
    );
  }
}

class _DistributionInsightBody extends StatelessWidget {
  const _DistributionInsightBody({required this.title, required this.items});
  final String title;
  final List<_DistributionItem> items;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ServicesController>();
    final sorted = List<_DistributionItem>.of(items)
      ..sort((left, right) => right.value.compareTo(left.value));
    final total = sorted.fold<int>(0, (sum, item) => sum + item.value);
    final spec = _distributionInsightSpec(title);
    final entitySection = _distributionEntitySection(
      context,
      title: title,
      controller: controller,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Section(
          title: spec.breakdownTitle,
          icon: Icons.donut_small_rounded,
          child: sorted.isEmpty || total == 0
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('暂无有效分布样本。'),
                  ),
                )
              : Column(
                  children: sorted
                      .map(
                        (item) =>
                            _DistributionDetailRow(item: item, total: total),
                      )
                      .toList(growable: false),
                ),
        ),
        if (entitySection != null) ...[
          const SizedBox(height: 14),
          entitySection,
        ],
      ],
    );
  }
}

class _DistributionDetailRow extends StatelessWidget {
  const _DistributionDetailRow({required this.item, required this.total});
  final _DistributionItem item;
  final int total;

  @override
  Widget build(BuildContext context) {
    final share = total <= 0 ? 0.0 : item.value / total;
    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: LinearProgressIndicator(
        value: share,
        minHeight: 9,
        color: item.color,
        backgroundColor: item.color.withValues(alpha: 0.1),
      ),
    );
    final label = Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: item.color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 10),
        Text(
          '${item.value} · ${(share * 100).toStringAsFixed(1)}%',
          textAlign: TextAlign.end,
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 440) {
            return Column(children: [label, const SizedBox(height: 8), bar]);
          }
          return Row(
            children: [
              SizedBox(width: 238, child: label),
              const SizedBox(width: 12),
              Expanded(child: bar),
            ],
          );
        },
      ),
    );
  }
}

String _formatChartValue(double value) => value == value.roundToDouble()
    ? '${value.round()}'
    : value.toStringAsFixed(1);

class _InsightRecord {
  const _InsightRecord({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tags,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> tags;
  final Color color;
}

class _InsightRecordPanel extends StatelessWidget {
  const _InsightRecordPanel({
    required this.icon,
    required this.title,
    required this.records,
    required this.emptyLabel,
    this.maxEntries = 30,
  });

  final IconData icon;
  final String title;
  final List<_InsightRecord> records;
  final String emptyLabel;
  final int maxEntries;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final shown = records.take(maxEntries).toList(growable: false);
    return _Section(
      title: records.isEmpty ? title : '$title · ${records.length}',
      icon: icon,
      child: shown.isEmpty
          ? _InsightEmpty(label: emptyLabel)
          : Column(
              children: shown.indexed
                  .map(
                    (entry) => Column(
                      children: [
                        if (entry.$1 > 0)
                          Divider(
                            height: 18,
                            color: colors.outlineVariant.withValues(alpha: 0.5),
                          ),
                        _InsightRecordRow(record: entry.$2),
                      ],
                    ),
                  )
                  .toList(growable: false),
            ),
    );
  }
}

class _InsightRecordRow extends StatelessWidget {
  const _InsightRecordRow({required this.record});
  final _InsightRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4,
          height: 48,
          margin: const EdgeInsets.only(top: 2, right: 10),
          decoration: BoxDecoration(
            color: record.color,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: record.color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(record.icon, size: 18, color: record.color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                record.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (record.tags.isNotEmpty) ...[
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: record.tags
                      .where((tag) => tag.trim().isNotEmpty)
                      .map((tag) => _InsightMiniTag(label: tag))
                      .toList(growable: false),
                ),
              ],
              if (record.subtitle.trim().isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  record.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _InsightMiniTag extends StatelessWidget {
  const _InsightMiniTag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colors.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InsightEmpty extends StatelessWidget {
  const _InsightEmpty({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(
            Icons.inbox_outlined,
            color: colors.onSurfaceVariant.withValues(alpha: 0.65),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _TrendSampleTable extends StatelessWidget {
  const _TrendSampleTable({
    required this.series,
    required this.sampleLabels,
    required this.suffix,
  });
  final List<OpenHandChartSeries> series;
  final List<String> sampleLabels;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final maxSamples = series.fold<int>(
      0,
      (count, item) => item.values.length > count ? item.values.length : count,
    );
    if (maxSamples == 0) return const _InsightEmpty(label: '暂无趋势样本。');
    final indexes = List<int>.generate(
      maxSamples,
      (index) => index,
    ).reversed.take(30);
    return Column(
      children: indexes
          .map(
            (index) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 116,
                    child: Text(
                      index < sampleLabels.length
                          ? sampleLabels[index]
                          : '样本 ${index + 1}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      alignment: WrapAlignment.end,
                      children: series
                          .map(
                            (item) => _StatusPill(
                              icon: Icons.circle,
                              label:
                                  '${item.label} ${index < item.values.length ? _formatChartValue(item.values[index]) : '--'}$suffix',
                              color: item.color,
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _InsightTrendSection extends StatelessWidget {
  const _InsightTrendSection({
    required this.title,
    required this.icon,
    required this.series,
    required this.sampleLabels,
    required this.suffix,
    required this.emptyLabel,
  });

  final String title;
  final IconData icon;
  final List<OpenHandChartSeries> series;
  final List<String> sampleLabels;
  final String suffix;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _Section(
      title: title,
      icon: icon,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 250,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: OpenHandSmoothLineChartPainter(
                  series: series,
                  gridColor: colors.outlineVariant.withValues(alpha: 0.58),
                  labelColor: colors.onSurfaceVariant,
                  emptyLabel: emptyLabel,
                  valueSuffix: suffix,
                  textDirection: Directionality.of(context),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: series
                .map((item) => _OpsLegend(label: item.label, color: item.color))
                .toList(growable: false),
          ),
          const SizedBox(height: 10),
          _TrendSampleTable(
            series: series,
            sampleLabels: sampleLabels,
            suffix: suffix,
          ),
        ],
      ),
    );
  }
}

class _InsightDonutSection extends StatelessWidget {
  const _InsightDonutSection({
    required this.title,
    required this.icon,
    required this.items,
    this.centerLabel,
  });

  final String title;
  final IconData icon;
  final List<_DistributionItem> items;
  final String? centerLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final total = items.fold<int>(0, (sum, item) => sum + item.value);
    return _Section(
      title: title,
      icon: icon,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final donut = SizedBox.square(
            dimension: 138,
            child: CustomPaint(
              painter: OpenHandDonutChartPainter(
                values: items.map((item) => item.value).toList(growable: false),
                colors: items.map((item) => item.color).toList(growable: false),
                trackColor: colors.surfaceContainerHighest,
              ),
              child: Center(
                child: Text(
                  centerLabel ?? '$total',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          );
          final rows = Column(
            children: items
                .map((item) => _DistributionDetailRow(item: item, total: total))
                .toList(growable: false),
          );
          if (constraints.maxWidth < 560) {
            return Column(children: [donut, const SizedBox(height: 12), rows]);
          }
          return Row(
            children: [
              donut,
              const SizedBox(width: 22),
              Expanded(child: rows),
            ],
          );
        },
      ),
    );
  }
}

List<Widget> _serviceMetricAnalysisSections(
  BuildContext context, {
  required String section,
  required String label,
  required ServicesController controller,
}) {
  final colors = Theme.of(context).colorScheme;
  final history = controller.history;
  final chronological = history.take(24).toList().reversed.toList();
  final results = controller.results;
  final rules = controller.rules;
  final logs = controller.logs;
  final proxy = controller.proxyStatus;
  final endpoints = controller.proxyConfiguration.endpoints;
  final requestSamples = _proxyRequestSamples(controller);
  final taskLabels = chronological
      .map((entry) => _shortDateTime(entry.createdAt))
      .toList(growable: false);
  final requestLabels = requestSamples
      .map((sample) => _shortDateTime(sample.at))
      .toList(growable: false);
  final sources = AiExposureSource.values
      .where((source) => source != AiExposureSource.githubArtifact)
      .toList(growable: false);
  final discoverySources = sources
      .where((source) => source != AiExposureSource.manual)
      .toList(growable: false);

  _InsightDonutSection donut(
    String title,
    IconData icon,
    List<_DistributionItem> items, {
    String? centerLabel,
  }) => _InsightDonutSection(
    title: title,
    icon: icon,
    items: items,
    centerLabel: centerLabel,
  );

  _InsightTrendSection taskTrend(
    String title,
    IconData icon,
    List<OpenHandChartSeries> series, {
    String suffix = ' 项',
    String emptyLabel = '暂无任务趋势样本',
  }) => _InsightTrendSection(
    title: title,
    icon: icon,
    series: series,
    sampleLabels: taskLabels,
    suffix: suffix,
    emptyLabel: emptyLabel,
  );

  _InsightTrendSection requestTrend(
    String title,
    List<AiExposureProxyRequestSample> samples,
    List<OpenHandChartSeries> series, {
    String suffix = ' ms',
    String emptyLabel = '暂无请求时延样本',
  }) => _InsightTrendSection(
    title: title,
    icon: Icons.multiline_chart_rounded,
    series: series,
    sampleLabels: samples
        .map((sample) => _shortDateTime(sample.at))
        .toList(growable: false),
    suffix: suffix,
    emptyLabel: emptyLabel,
  );

  List<_DistributionItem> taskStages() {
    int count(String stage) =>
        history.where((entry) => entry.stage == stage).length;
    const terminal = {'completed', 'failed', 'cancelled'};
    return [
      _DistributionItem('完成', count('completed'), OpenHandStatusColors.success),
      _DistributionItem('失败', count('failed'), OpenHandStatusColors.error),
      _DistributionItem('取消', count('cancelled'), OpenHandStatusColors.warning),
      _DistributionItem(
        '运行中',
        history.where((entry) => !terminal.contains(entry.stage)).length,
        OpenHandStatusColors.info,
      ),
    ];
  }

  List<_DistributionItem> requestOutcomes() => [
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
    _DistributionItem('执行中', proxy?.inFlight ?? 0, OpenHandStatusColors.info),
  ];

  final sourceConfigured = <AiExposureSource, bool>{
    for (final source in discoverySources)
      source: controller.sourceStatus[_sourceCredentialKey(source)] == true,
  };
  final quotaBySource = {
    for (final quota in controller.quotas) quota.source: quota,
  };
  final sourceJobCounts = <AiExposureSource, int>{};
  for (final entry in history) {
    for (final source in entry.sources) {
      sourceJobCounts.update(source, (value) => value + 1, ifAbsent: () => 1);
    }
  }
  final sourceResultCounts = <AiExposureSource, int>{};
  for (final result in results) {
    sourceResultCounts.update(
      result.source,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
  }

  switch ('$section/$label') {
    case '状态总览/任务总数':
      return [donut('任务终态构成', Icons.account_tree_outlined, taskStages())];
    case '状态总览/结果总数':
      int category(AiExposureResultCategory value) =>
          results.where((entry) => entry.category == value).length;
      return [
        donut('结果质量构成', Icons.fact_check_outlined, [
          _DistributionItem(
            '有效',
            category(AiExposureResultCategory.valid),
            OpenHandStatusColors.success,
          ),
          _DistributionItem(
            '高价值',
            category(AiExposureResultCategory.highValue),
            const Color(0xffa855f7),
          ),
          _DistributionItem(
            '可疑',
            category(AiExposureResultCategory.suspicious),
            OpenHandStatusColors.warning,
          ),
          _DistributionItem(
            '蜜罐',
            category(AiExposureResultCategory.honeypot),
            OpenHandStatusColors.error,
          ),
        ]),
      ];
    case '状态总览/高价值':
      return [
        taskTrend('高价值结果产出趋势', Icons.workspace_premium_outlined, [
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
        ], emptyLabel: '暂无高价值结果趋势'),
      ];
    case '状态总览/累计处理':
      return [
        taskTrend('累计处理吞吐', Icons.radar_rounded, [
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
        ], emptyLabel: '暂无处理吞吐样本'),
      ];
    case '状态总览/平均任务耗时':
      return [
        taskTrend(
          '任务端到端耗时',
          Icons.timer_outlined,
          [
            OpenHandChartSeries(
              label: '耗时',
              values: chronological
                  .map(
                    (entry) =>
                        (entry.finishedAt
                                    ?.difference(entry.createdAt)
                                    .inMilliseconds ??
                                0)
                            .clamp(0, 86400000)
                            .toDouble(),
                  )
                  .toList(growable: false),
              color: colors.tertiary,
            ),
          ],
          suffix: ' ms',
          emptyLabel: '暂无已结束任务耗时样本',
        ),
      ];
    case '状态总览/已配置源':
      final configured = sourceConfigured.values.where((value) => value).length;
      return [
        donut('数据源配置覆盖', Icons.travel_explore_rounded, [
          _DistributionItem('已配置', configured, OpenHandStatusColors.success),
          _DistributionItem(
            '待配置',
            discoverySources.length - configured,
            colors.outline,
          ),
        ]),
      ];
    case '状态总览/启用规则':
      final enabled = rules.where((rule) => rule.enabled).length;
      return [
        donut('规则启用覆盖', Icons.rule_rounded, [
          _DistributionItem('已启用', enabled, OpenHandStatusColors.success),
          _DistributionItem('未启用', rules.length - enabled, colors.outline),
        ]),
      ];
    case '状态总览/代理选路':
      return [donut('代理请求结果构成', Icons.alt_route_rounded, requestOutcomes())];
    case '状态总览/代理平均响应':
      return [
        requestTrend('代理端到端响应趋势', requestSamples, [
          OpenHandChartSeries(
            label: '响应耗时',
            values: requestSamples
                .map((sample) => sample.responseTimeMs.toDouble())
                .toList(growable: false),
            color: colors.secondary,
          ),
        ]),
      ];
    case '状态总览/警告日志':
      final warnings = logs.where((entry) => entry.level == 'warning').toList();
      return [
        donut('警告归属构成', Icons.warning_amber_rounded, [
          _DistributionItem(
            '任务警告',
            warnings.where((entry) => entry.jobId.isNotEmpty).length,
            OpenHandStatusColors.warning,
          ),
          _DistributionItem(
            '系统警告',
            warnings.where((entry) => entry.jobId.isEmpty).length,
            colors.tertiary,
          ),
        ]),
      ];
    case '状态总览/错误日志':
      final errors = logs.where((entry) => entry.level == 'error').toList();
      return [
        donut('错误归属构成', Icons.error_outline_rounded, [
          _DistributionItem(
            '任务错误',
            errors.where((entry) => entry.jobId.isNotEmpty).length,
            OpenHandStatusColors.error,
          ),
          _DistributionItem(
            '系统错误',
            errors.where((entry) => entry.jobId.isEmpty).length,
            colors.tertiary,
          ),
        ]),
      ];
    case '状态总览/已取消任务':
      final cancelled = chronological
          .where((entry) => entry.stage == 'cancelled')
          .toList(growable: false);
      return [
        _InsightTrendSection(
          title: '取消任务处理量与候选量',
          icon: Icons.cancel_outlined,
          series: [
            OpenHandChartSeries(
              label: '处理',
              values: cancelled
                  .map((entry) => entry.progress.processed.toDouble())
                  .toList(growable: false),
              color: colors.primary,
            ),
            OpenHandChartSeries(
              label: '候选',
              values: cancelled
                  .map((entry) => entry.progress.candidates.toDouble())
                  .toList(growable: false),
              color: OpenHandStatusColors.warning,
            ),
          ],
          sampleLabels: cancelled
              .map((entry) => _shortDateTime(entry.createdAt))
              .toList(growable: false),
          suffix: ' 项',
          emptyLabel: '暂无取消任务样本',
        ),
      ];
    case '任务管线/当前状态':
      final progress = controller.progress;
      final processed = progress?.processed ?? 0;
      final total = progress?.total ?? 0;
      return [
        donut(
          '当前任务进度构成',
          Icons.play_circle_outline_rounded,
          [
            _DistributionItem('已处理', processed, OpenHandStatusColors.success),
            _DistributionItem(
              '待处理',
              (total - processed).clamp(0, total),
              colors.outline,
            ),
          ],
          centerLabel: progress == null ? '空闲' : _stageName(progress.stage),
        ),
      ];
    case '任务管线/累计处理':
      return [
        taskTrend('逐任务处理吞吐', Icons.checklist_rounded, [
          OpenHandChartSeries(
            label: '处理',
            values: chronological
                .map((entry) => entry.progress.processed.toDouble())
                .toList(growable: false),
            color: colors.primary,
          ),
        ], emptyLabel: '暂无任务处理样本'),
      ];
    case '任务管线/候选目标':
      final processed = history.fold<int>(
        0,
        (sum, entry) => sum + entry.progress.processed,
      );
      final candidates = history.fold<int>(
        0,
        (sum, entry) => sum + entry.progress.candidates,
      );
      return [
        donut('候选转化构成', Icons.filter_alt_outlined, [
          _DistributionItem('候选目标', candidates, OpenHandStatusColors.info),
          _DistributionItem(
            '未转候选',
            (processed - candidates).clamp(0, processed),
            colors.outline,
          ),
        ]),
      ];
    case '任务管线/有效结果':
      final candidates = history.fold<int>(
        0,
        (sum, entry) => sum + entry.progress.candidates,
      );
      final valid = history.fold<int>(
        0,
        (sum, entry) => sum + entry.progress.valid,
      );
      return [
        donut('有效转化构成', Icons.verified_outlined, [
          _DistributionItem('有效结果', valid, OpenHandStatusColors.success),
          _DistributionItem(
            '未通过验证',
            (candidates - valid).clamp(0, candidates),
            OpenHandStatusColors.warning,
          ),
        ]),
      ];
    case '任务管线/高价值结果':
      final valid = history.fold<int>(
        0,
        (sum, entry) => sum + entry.progress.valid,
      );
      final high = history.fold<int>(
        0,
        (sum, entry) => sum + entry.progress.highValue,
      );
      return [
        donut('高价值占有效结果构成', Icons.workspace_premium_outlined, [
          _DistributionItem('高价值', high, const Color(0xffa855f7)),
          _DistributionItem(
            '普通有效',
            (valid - high).clamp(0, valid),
            OpenHandStatusColors.success,
          ),
        ]),
      ];
    case '任务管线/任务并发':
      final active = history.where((entry) => entry.progress.isRunning).length;
      final limit = controller.defaultConcurrency;
      return [
        donut('并发槽占用', Icons.speed_rounded, [
          _DistributionItem('活动任务', active, OpenHandStatusColors.info),
          _DistributionItem(
            '空闲槽位',
            (limit - active).clamp(0, limit),
            colors.outline,
          ),
        ], centerLabel: '$active/$limit'),
      ];
    case '任务管线/全量扫描':
      final full = history
          .where((entry) => entry.mode == AiExposureScanMode.full)
          .length;
      return [
        donut('扫描模式构成', Icons.layers_outlined, [
          _DistributionItem('全量扫描', full, OpenHandStatusColors.info),
          _DistributionItem('增量扫描', history.length - full, colors.tertiary),
        ]),
      ];
    case '任务管线/可恢复任务':
      final resumable = history.where((entry) => entry.isResumable).length;
      return [
        donut('恢复状态构成', Icons.restart_alt_rounded, [
          _DistributionItem('可恢复', resumable, OpenHandStatusColors.warning),
          _DistributionItem(
            '已完成',
            history.length - resumable,
            OpenHandStatusColors.success,
          ),
        ]),
      ];
    case '数据源/已就绪来源':
      final ready = discoverySources.where((source) {
        final quota = quotaBySource[source];
        return sourceConfigured[source] == true &&
            (quota == null || quota.available);
      }).length;
      return [
        donut('来源就绪覆盖', Icons.cloud_done_outlined, [
          _DistributionItem('已就绪', ready, OpenHandStatusColors.success),
          _DistributionItem(
            '未就绪',
            discoverySources.length - ready,
            colors.outline,
          ),
        ]),
      ];
    case '数据源/配额可用源':
      final metered = controller.quotas
          .where((quota) => quota.configured)
          .length;
      final available = controller.quotas
          .where((quota) => quota.configured && quota.available)
          .length;
      return [
        donut('实时配额探测结果', Icons.data_usage_rounded, [
          _DistributionItem('配额可用', available, OpenHandStatusColors.success),
          _DistributionItem(
            '配额不可用',
            metered - available,
            OpenHandStatusColors.error,
          ),
        ]),
      ];
    case '数据源/剩余配额':
      final quotas = controller.quotas
          .where((quota) => quota.remaining != null)
          .toList(growable: false);
      return [
        _InsightTrendSection(
          title: '各来源剩余配额',
          icon: Icons.data_saver_on_outlined,
          series: [
            OpenHandChartSeries(
              label: '剩余',
              values: quotas
                  .map((quota) => quota.remaining!.toDouble())
                  .toList(growable: false),
              color: colors.primary,
            ),
          ],
          sampleLabels: quotas
              .map((quota) => _sourceName(quota.source))
              .toList(growable: false),
          suffix: '',
          emptyLabel: '暂无可计量配额样本',
        ),
      ];
    case '数据源/启用发现源':
      final enabled = sources.where(controller.enabledSources.contains).length;
      return [
        donut('发现来源启用覆盖', Icons.travel_explore_rounded, [
          _DistributionItem('已启用', enabled, OpenHandStatusColors.info),
          _DistributionItem('未启用', sources.length - enabled, colors.outline),
        ]),
      ];
    case '数据源/来源调用任务':
      return [
        donut(
          '任务来源调用构成',
          Icons.hub_outlined,
          sources
              .map(
                (source) => _DistributionItem(
                  _sourceName(source),
                  sourceJobCounts[source] ?? 0,
                  _sourceColor(source, colors),
                ),
              )
              .toList(growable: false),
        ),
      ];
    case '数据源/来源产出结果':
      return [
        donut(
          '来源结果产出构成',
          Icons.fact_check_outlined,
          sources
              .map(
                (source) => _DistributionItem(
                  _sourceName(source),
                  sourceResultCounts[source] ?? 0,
                  _sourceColor(source, colors),
                ),
              )
              .toList(growable: false),
        ),
      ];
    case '数据源/配额异常':
      final configured = controller.quotas
          .where((quota) => quota.configured)
          .toList(growable: false);
      return [
        donut('配额健康构成', Icons.warning_amber_rounded, [
          _DistributionItem(
            '正常',
            configured.where((quota) => quota.available).length,
            OpenHandStatusColors.success,
          ),
          _DistributionItem(
            '异常',
            configured.where((quota) => !quota.available).length,
            OpenHandStatusColors.error,
          ),
        ]),
      ];
    case '数据源/待配置来源':
      final configured = sourceConfigured.values.where((value) => value).length;
      return [
        donut('来源配置缺口', Icons.key_off_outlined, [
          _DistributionItem(
            '待配置',
            discoverySources.length - configured,
            OpenHandStatusColors.warning,
          ),
          _DistributionItem('已配置', configured, OpenHandStatusColors.success),
        ]),
      ];
    case '网络遥测/选路状态':
      final route = controller.proxyRoute;
      return [
        donut(
          '当前网络出口模式',
          Icons.route_outlined,
          [
            _DistributionItem(
              '直接连接',
              route == AiExposureProxyRoute.direct ? 1 : 0,
              colors.outline,
            ),
            _DistributionItem(
              '系统代理',
              route == AiExposureProxyRoute.system ? 1 : 0,
              colors.tertiary,
            ),
            _DistributionItem(
              '代理池',
              route == AiExposureProxyRoute.pool ? 1 : 0,
              colors.primary,
            ),
          ],
          centerLabel: serviceProxyRouteText(
            controller,
            openHandTextResolver(context),
            includePoolCount: false,
          ),
        ),
      ];
    case '网络遥测/代理节点':
      final enabled = endpoints.where((endpoint) => endpoint.enabled).length;
      return [
        donut('代理节点启用构成', Icons.dns_outlined, [
          _DistributionItem('已启用', enabled, OpenHandStatusColors.info),
          _DistributionItem('已停用', endpoints.length - enabled, colors.outline),
        ]),
      ];
    case '网络遥测/可连通节点':
      final reachable = endpoints
          .where((endpoint) => endpoint.latestSample?.reachable == true)
          .length;
      final unreachable = endpoints
          .where((endpoint) => endpoint.latestSample?.reachable == false)
          .length;
      return [
        donut('节点巡检可用性', Icons.cloud_done_outlined, [
          _DistributionItem('可连通', reachable, OpenHandStatusColors.success),
          _DistributionItem('不可连通', unreachable, OpenHandStatusColors.error),
          _DistributionItem(
            '未巡检',
            endpoints.length - reachable - unreachable,
            colors.outline,
          ),
        ]),
      ];
    case '网络遥测/累计请求':
      return [donut('代理请求全景构成', Icons.swap_vert_rounded, requestOutcomes())];
    case '网络遥测/成功请求':
      final success = requestSamples
          .where((sample) => sample.succeeded)
          .toList(growable: false);
      return [
        requestTrend('成功请求响应时延', success, [
          OpenHandChartSeries(
            label: '成功时延',
            values: success
                .map((sample) => sample.responseTimeMs.toDouble())
                .toList(growable: false),
            color: OpenHandStatusColors.success,
          ),
        ], emptyLabel: '暂无成功请求时延样本'),
      ];
    case '网络遥测/失败请求':
      final failures = requestSamples
          .where((sample) => !sample.succeeded && !sample.timedOut)
          .toList(growable: false);
      return [
        donut('失败与超时异常构成', Icons.error_outline_rounded, [
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
        ]),
        requestTrend('失败请求响应时延', failures, [
          OpenHandChartSeries(
            label: '失败时延',
            values: failures
                .map((sample) => sample.responseTimeMs.toDouble())
                .toList(growable: false),
            color: OpenHandStatusColors.error,
          ),
        ], emptyLabel: '暂无失败请求时延样本'),
      ];
    case '网络遥测/超时请求':
      final timeouts = requestSamples
          .where((sample) => sample.timedOut)
          .toList(growable: false);
      return [
        requestTrend('超时请求耗时样本', timeouts, [
          OpenHandChartSeries(
            label: '超时耗时',
            values: timeouts
                .map((sample) => sample.responseTimeMs.toDouble())
                .toList(growable: false),
            color: OpenHandStatusColors.warning,
          ),
        ], emptyLabel: '暂无超时请求耗时样本'),
      ];
    case '网络遥测/平均响应':
      return [
        requestTrend('全量请求响应时延', requestSamples, [
          OpenHandChartSeries(
            label: '响应耗时',
            values: requestSamples
                .map((sample) => sample.responseTimeMs.toDouble())
                .toList(growable: false),
            color: colors.secondary,
          ),
        ]),
      ];
    case '网络遥测/p95 响应':
      final p95 = _latencyPercentile(
        requestSamples.map((sample) => sample.responseTimeMs).toList(),
        0.95,
      );
      return [
        _InsightTrendSection(
          title: '长尾响应与 p95 基线',
          icon: Icons.multiline_chart_rounded,
          series: [
            OpenHandChartSeries(
              label: '响应耗时',
              values: requestSamples
                  .map((sample) => sample.responseTimeMs.toDouble())
                  .toList(growable: false),
              color: colors.tertiary,
            ),
            OpenHandChartSeries(
              label: 'p95 基线',
              values: List<double>.filled(
                requestSamples.length,
                p95.toDouble(),
              ),
              color: OpenHandStatusColors.warning,
            ),
          ],
          sampleLabels: requestLabels,
          suffix: ' ms',
          emptyLabel: '暂无 p95 响应样本',
        ),
      ];
    case '网络遥测/HTTP 2xx':
      int statuses(int min, int max) => requestSamples
          .where(
            (sample) =>
                sample.statusCode != null &&
                sample.statusCode! >= min &&
                sample.statusCode! <= max,
          )
          .length;
      return [
        donut('HTTP 状态码族构成', Icons.http_rounded, [
          _DistributionItem(
            '2xx',
            statuses(200, 299),
            OpenHandStatusColors.success,
          ),
          _DistributionItem(
            '3xx',
            statuses(300, 399),
            OpenHandStatusColors.info,
          ),
          _DistributionItem(
            '4xx',
            statuses(400, 499),
            OpenHandStatusColors.warning,
          ),
          _DistributionItem(
            '5xx',
            statuses(500, 599),
            OpenHandStatusColors.error,
          ),
        ]),
      ];
    case '网络遥测/出口国家':
      final countries = <String, int>{};
      for (final endpoint in endpoints) {
        final country = endpoint.identity?.country.trim() ?? '';
        if (country.isEmpty) continue;
        countries.update(country, (value) => value + 1, ifAbsent: () => 1);
      }
      return [
        donut(
          '代理出口地域构成',
          Icons.public_rounded,
          countries.entries
              .map(
                (entry) => _DistributionItem(
                  entry.key,
                  entry.value,
                  _distributionColor(
                    countries.keys.toList().indexOf(entry.key),
                    colors,
                  ),
                ),
              )
              .toList(growable: false),
        ),
      ];
    case '网络遥测/巡检计划':
      final inspected = endpoints
          .where((endpoint) => endpoint.latestSample != null)
          .length;
      return [
        donut('巡检覆盖状态', Icons.health_and_safety_outlined, [
          _DistributionItem('已巡检', inspected, OpenHandStatusColors.success),
          _DistributionItem(
            '待巡检',
            endpoints.length - inspected,
            colors.outline,
          ),
        ]),
      ];
    case '存储与持久化/SQLite 数据库':
      return [
        donut('本地持久化完整性', Icons.storage_rounded, [
          _DistributionItem('任务', history.length, colors.primary),
          _DistributionItem('结果', results.length, OpenHandStatusColors.info),
          _DistributionItem('规则', rules.length, colors.tertiary),
          _DistributionItem('日志', logs.length, colors.secondary),
        ]),
      ];
    case '存储与持久化/最后写入':
      final events = <DateTime>[
        ...history.map((entry) => entry.finishedAt ?? entry.createdAt),
        ...results.map((entry) => entry.createdAt),
        ...logs.map((entry) => entry.at),
      ]..sort();
      final recent = events.reversed.take(24).toList().reversed.toList();
      return [
        _InsightTrendSection(
          title: '最近持久化活动序列',
          icon: Icons.edit_calendar_outlined,
          series: [
            OpenHandChartSeries(
              label: '累计写入',
              values: List<double>.generate(
                recent.length,
                (index) => (index + 1).toDouble(),
              ),
              color: colors.primary,
            ),
          ],
          sampleLabels: recent.map(_shortDateTime).toList(growable: false),
          suffix: ' 条',
          emptyLabel: '暂无持久化活动时间样本',
        ),
      ];
    case '存储与持久化/可见记录':
      return [
        donut('可见记录类型构成', Icons.inventory_2_outlined, [
          _DistributionItem('任务', history.length, colors.primary),
          _DistributionItem('结果', results.length, OpenHandStatusColors.info),
          _DistributionItem('规则', rules.length, colors.tertiary),
          _DistributionItem('日志', logs.length, colors.secondary),
        ]),
      ];
    case '存储与持久化/任务归档':
      return [donut('归档任务阶段构成', Icons.work_history_outlined, taskStages())];
    case '存储与持久化/结果归档':
      final evidence = results
          .where((result) => result.evidence.isNotEmpty)
          .length;
      return [
        donut('结果证据完整性', Icons.fact_check_outlined, [
          _DistributionItem('证据完整', evidence, OpenHandStatusColors.success),
          _DistributionItem(
            '缺少证据',
            results.length - evidence,
            OpenHandStatusColors.warning,
          ),
        ]),
      ];
    case '存储与持久化/规则快照':
      final enabled = rules.where((rule) => rule.enabled).length;
      return [
        donut('规则快照启用构成', Icons.rule_folder_outlined, [
          _DistributionItem('已启用', enabled, OpenHandStatusColors.success),
          _DistributionItem('未启用', rules.length - enabled, colors.outline),
        ]),
      ];
    case '存储与持久化/日志缓冲':
      int level(String value) =>
          logs.where((entry) => entry.level == value).length;
      return [
        donut('日志级别构成', Icons.receipt_long_outlined, [
          _DistributionItem('信息', level('info'), OpenHandStatusColors.info),
          _DistributionItem(
            '警告',
            level('warning'),
            OpenHandStatusColors.warning,
          ),
          _DistributionItem('错误', level('error'), OpenHandStatusColors.error),
        ]),
      ];
    case '存储与持久化/可恢复任务':
      final resumable = history.where((entry) => entry.isResumable).length;
      return [
        donut('归档恢复能力', Icons.restart_alt_rounded, [
          _DistributionItem('可恢复', resumable, OpenHandStatusColors.warning),
          _DistributionItem(
            '无需恢复',
            history.length - resumable,
            OpenHandStatusColors.success,
          ),
        ]),
      ];
    case '存储与持久化/PostgreSQL 镜像':
      final status = controller.dependencyStatus?.postgresql;
      return [
        donut('PostgreSQL 镜像状态', Icons.cloud_sync_outlined, [
          _DistributionItem(
            '已连接',
            status?.connected == true ? 1 : 0,
            OpenHandStatusColors.success,
          ),
          _DistributionItem(
            '已配置未连接',
            status?.configured == true && status?.connected != true ? 1 : 0,
            OpenHandStatusColors.warning,
          ),
          _DistributionItem(
            '未配置',
            status?.configured == true ? 0 : 1,
            colors.outline,
          ),
        ]),
      ];
    case '存储与持久化/Redis 协调':
      final status = controller.dependencyStatus?.redis;
      return [
        donut('Redis 协调状态', Icons.hub_outlined, [
          _DistributionItem(
            '已连接',
            status?.connected == true ? 1 : 0,
            OpenHandStatusColors.success,
          ),
          _DistributionItem(
            '已配置未连接',
            status?.configured == true && status?.connected != true ? 1 : 0,
            OpenHandStatusColors.warning,
          ),
          _DistributionItem(
            '未配置',
            status?.configured == true ? 0 : 1,
            colors.outline,
          ),
        ]),
      ];
    case '存储与持久化/凭证加密':
      return [
        donut('加密存储对象构成', Icons.enhanced_encryption_outlined, [
          _DistributionItem(
            '含凭证结果',
            results
                .where(
                  (result) =>
                      result.maskedCredential?.trim().isNotEmpty == true,
                )
                .length,
            colors.tertiary,
          ),
          _DistributionItem(
            '无凭证结果',
            results
                .where(
                  (result) =>
                      result.maskedCredential?.trim().isNotEmpty != true,
                )
                .length,
            colors.outline,
          ),
        ]),
      ];
    case '存储与持久化/一致性审计':
      final ids = history.map((entry) => entry.id).toSet();
      final orphan = results
          .where((result) => !ids.contains(result.jobId))
          .length;
      final noEvidence = results
          .where((result) => result.evidence.isEmpty)
          .length;
      final complete = results
          .where(
            (result) =>
                ids.contains(result.jobId) && result.evidence.isNotEmpty,
          )
          .length;
      return [
        donut('一致性问题构成', Icons.verified_outlined, [
          _DistributionItem('孤立结果', orphan, OpenHandStatusColors.error),
          _DistributionItem('缺少证据', noEvidence, OpenHandStatusColors.warning),
          _DistributionItem('完整记录', complete, OpenHandStatusColors.success),
        ]),
      ];
    case '安全与依赖/启用规则':
      final vendorCounts = <String, int>{};
      for (final rule in rules.where((rule) => rule.enabled)) {
        final vendor = rule.vendor.trim().isEmpty ? '未分类' : rule.vendor;
        vendorCounts.update(vendor, (value) => value + 1, ifAbsent: () => 1);
      }
      return [
        donut(
          '启用规则供应商覆盖',
          Icons.category_outlined,
          vendorCounts.entries
              .map(
                (entry) => _DistributionItem(
                  entry.key,
                  entry.value,
                  _distributionColor(
                    vendorCounts.keys.toList().indexOf(entry.key),
                    colors,
                  ),
                ),
              )
              .toList(growable: false),
        ),
      ];
    case '安全与依赖/凭证模式':
      final enabled = rules
          .where((rule) => rule.enabled)
          .toList(growable: false);
      return [
        _InsightTrendSection(
          title: '规则凭证模式与上下文约束',
          icon: Icons.fingerprint_rounded,
          series: [
            OpenHandChartSeries(
              label: '凭证模式',
              values: enabled
                  .map((rule) => rule.credentialPatterns.length.toDouble())
                  .toList(growable: false),
              color: colors.primary,
            ),
            OpenHandChartSeries(
              label: '上下文词',
              values: enabled
                  .map((rule) => rule.contextTerms.length.toDouble())
                  .toList(growable: false),
              color: colors.tertiary,
            ),
          ],
          sampleLabels: enabled
              .map((rule) => rule.vendor.trim().isEmpty ? rule.id : rule.vendor)
              .toList(growable: false),
          suffix: ' 个',
          emptyLabel: '暂无启用凭证识别规则',
        ),
      ];
    case '安全与依赖/模型端点':
      final modelPaths = rules.fold<int>(
        0,
        (sum, rule) => sum + (rule.enabled ? rule.modelPaths.length : 0),
      );
      final balancePaths = rules.fold<int>(
        0,
        (sum, rule) => sum + (rule.enabled ? rule.balancePaths.length : 0),
      );
      return [
        donut('主动验证端点构成', Icons.api_rounded, [
          _DistributionItem('模型端点', modelPaths, OpenHandStatusColors.info),
          _DistributionItem('余额端点', balancePaths, colors.tertiary),
        ]),
      ];
    case '安全与依赖/编码识别':
      final counts = <AiExposureContentEncoding, int>{};
      for (final rule in rules.where((rule) => rule.enabled)) {
        for (final encoding in rule.contentEncodings) {
          counts.update(encoding, (value) => value + 1, ifAbsent: () => 1);
        }
      }
      return [
        donut(
          '内容编码规则覆盖',
          Icons.code_rounded,
          AiExposureContentEncoding.values
              .map(
                (encoding) => _DistributionItem(
                  encoding.id,
                  counts[encoding] ?? 0,
                  _distributionColor(encoding.index, colors),
                ),
              )
              .toList(growable: false),
        ),
      ];
    case '安全与依赖/代理请求':
      return [donut('验证出口请求构成', Icons.lan_outlined, requestOutcomes())];
    case '安全与依赖/代理成功':
      final success = requestSamples
          .where((sample) => sample.succeeded)
          .toList(growable: false);
      return [
        requestTrend('验证成功请求时延', success, [
          OpenHandChartSeries(
            label: '验证成功',
            values: success
                .map((sample) => sample.responseTimeMs.toDouble())
                .toList(growable: false),
            color: OpenHandStatusColors.success,
          ),
        ], emptyLabel: '暂无验证成功请求样本'),
      ];
    case '安全与依赖/代理异常':
      return [
        donut('验证网络异常构成', Icons.report_gmailerrorred_rounded, [
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
        ]),
      ];
    case '安全与依赖/依赖就绪':
      final dependencies = controller.dependencyStatus;
      final states = [
        controller.isRunning,
        dependencies?.postgresql.connected == true,
        dependencies?.redis.connected == true,
        controller.aiExtractorStatus?.configured == true,
      ];
      final ready = states.where((value) => value).length;
      return [
        donut('验证依赖就绪构成', Icons.hub_outlined, [
          _DistributionItem('已就绪', ready, OpenHandStatusColors.success),
          _DistributionItem('未就绪', states.length - ready, colors.outline),
        ], centerLabel: '$ready/${states.length}'),
      ];
  }
  return const [];
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

List<Widget> _serviceMetricDetailSections(
  BuildContext context, {
  required String section,
  required String label,
  required ServicesController controller,
}) {
  final histories = controller.history;
  final results = controller.results;
  final rules = controller.rules;
  final logs = controller.logs.reversed.toList(growable: false);

  _InsightRecordPanel taskPanel(
    Iterable<AiExposureHistoryEntry> entries, {
    String title = '任务明细',
    String emptyLabel = '暂无符合条件的任务。',
    _TaskRecordLens lens = _TaskRecordLens.overview,
  }) => _InsightRecordPanel(
    icon: Icons.work_history_outlined,
    title: title,
    records: entries.map((entry) => _taskInsightRecord(entry, lens)).toList(),
    emptyLabel: emptyLabel,
  );

  _InsightRecordPanel resultPanel(
    Iterable<AiExposureResult> entries, {
    String title = '结果明细',
    String emptyLabel = '暂无符合条件的结果。',
    _ResultRecordLens lens = _ResultRecordLens.overview,
  }) => _InsightRecordPanel(
    icon: Icons.fact_check_outlined,
    title: title,
    records: entries.map((entry) => _resultInsightRecord(entry, lens)).toList(),
    emptyLabel: emptyLabel,
  );

  _InsightRecordPanel logPanel(
    Iterable<AiExposureLogEntry> entries, {
    String title = '运行事件',
    String emptyLabel = '暂无符合条件的运行事件。',
  }) => _InsightRecordPanel(
    icon: Icons.receipt_long_outlined,
    title: title,
    records: entries.map(_logInsightRecord).toList(),
    emptyLabel: emptyLabel,
  );

  switch ('$section/$label') {
    case '状态总览/任务总数':
      return [taskPanel(histories, title: '最近任务')];
    case '状态总览/结果总数':
      return [resultPanel(results, title: '最近扫描结果')];
    case '状态总览/高价值':
      return [
        resultPanel(
          results.where(
            (entry) => entry.category == AiExposureResultCategory.highValue,
          ),
          title: '高价值结果',
          emptyLabel: '暂无高价值结果。',
          lens: _ResultRecordLens.risk,
        ),
      ];
    case '状态总览/累计处理':
      return [
        taskPanel(
          histories.where((entry) => entry.progress.processed > 0),
          title: '处理量最高任务',
          lens: _TaskRecordLens.throughput,
        ),
      ];
    case '状态总览/平均任务耗时':
      final finished =
          histories.where((entry) => entry.finishedAt != null).toList()..sort(
            (a, b) => b.finishedAt!
                .difference(b.createdAt)
                .compareTo(a.finishedAt!.difference(a.createdAt)),
          );
      return [
        taskPanel(finished, title: '任务耗时明细', lens: _TaskRecordLens.duration),
      ];
    case '状态总览/已配置源':
      return [_sourceInsightPanel(context, controller, _SourceLens.configured)];
    case '状态总览/启用规则':
      return [_ruleInsightPanel(context, rules.where((rule) => rule.enabled))];
    case '状态总览/代理选路':
      return [_proxyRouteReadinessPanel(context, controller)];
    case '状态总览/代理平均响应':
      return [_proxyFleetLatencyPanel(context, controller)];
    case '状态总览/警告日志':
      return [
        logPanel(
          logs.where((entry) => entry.level == 'warning'),
          title: '警告事件',
          emptyLabel: '暂无警告事件。',
        ),
      ];
    case '状态总览/错误日志':
      return [
        logPanel(
          logs.where((entry) => entry.level == 'error'),
          title: '错误事件',
          emptyLabel: '暂无错误事件。',
        ),
      ];
    case '状态总览/已取消任务':
      return [
        taskPanel(
          histories.where((entry) => entry.stage == 'cancelled'),
          title: '已取消任务',
          emptyLabel: '暂无已取消任务。',
        ),
      ];
    case '任务管线/当前状态':
      final active = histories.where((entry) => entry.progress.isRunning);
      return [
        taskPanel(
          active,
          title: '活动任务',
          emptyLabel: '当前没有活动任务。',
          lens: _TaskRecordLens.runtime,
        ),
        logPanel(logs.take(20), title: '最近管线事件'),
      ];
    case '任务管线/累计处理':
    case '任务管线/候选目标':
    case '任务管线/有效结果':
    case '任务管线/高价值结果':
      final sorted = [...histories]
        ..sort((a, b) {
          int value(AiExposureHistoryEntry entry) => switch (label) {
            '候选目标' => entry.progress.candidates,
            '有效结果' => entry.progress.valid,
            '高价值结果' => entry.progress.highValue,
            _ => entry.progress.processed,
          };
          return value(b).compareTo(value(a));
        });
      final lens = switch (label) {
        '候选目标' => _TaskRecordLens.candidates,
        '有效结果' => _TaskRecordLens.valid,
        '高价值结果' => _TaskRecordLens.highValue,
        _ => _TaskRecordLens.throughput,
      };
      return [taskPanel(sorted, title: '$label任务明细', lens: lens)];
    case '任务管线/任务并发':
      return [
        _Section(
          title: '并发配置',
          icon: Icons.speed_rounded,
          child: Column(
            children: [
              _OpsKeyValue(
                label: '当前并发',
                value: '${controller.defaultConcurrency}',
              ),
              const _OpsKeyValue(label: '配置上限', value: '128'),
              _OpsKeyValue(
                label: '活动任务',
                value:
                    '${histories.where((entry) => entry.progress.isRunning).length}',
              ),
              _OpsKeyValue(
                label: '代理在途请求',
                value: '${controller.proxyStatus?.inFlight ?? 0}',
              ),
            ],
          ),
        ),
        taskPanel(
          histories.where((entry) => entry.progress.isRunning),
          title: '并发中的任务',
          emptyLabel: '当前没有并发任务。',
          lens: _TaskRecordLens.runtime,
        ),
      ];
    case '任务管线/全量扫描':
      return [
        taskPanel(
          histories.where((entry) => entry.mode == AiExposureScanMode.full),
          title: '全量扫描任务',
          emptyLabel: '暂无全量扫描任务。',
          lens: _TaskRecordLens.scope,
        ),
      ];
    case '任务管线/可恢复任务':
      return [
        taskPanel(
          histories.where((entry) => entry.isResumable),
          title: '可恢复任务',
          emptyLabel: '暂无可恢复任务。',
          lens: _TaskRecordLens.recovery,
        ),
      ];
    case '数据源/已就绪来源':
      return [_sourceInsightPanel(context, controller, _SourceLens.ready)];
    case '数据源/配额可用源':
      return [
        _sourceInsightPanel(context, controller, _SourceLens.quotaAvailable),
      ];
    case '数据源/剩余配额':
      return [_sourceInsightPanel(context, controller, _SourceLens.metered)];
    case '数据源/启用发现源':
      return [_sourceInsightPanel(context, controller, _SourceLens.enabled)];
    case '数据源/来源调用任务':
      return [
        _sourceInsightPanel(context, controller, _SourceLens.invoked),
        taskPanel(
          histories.where((entry) => entry.sources.isNotEmpty),
          title: '来源调用任务',
        ),
      ];
    case '数据源/来源产出结果':
      return [
        _sourceInsightPanel(context, controller, _SourceLens.produced),
        resultPanel(results, title: '来源产出结果'),
      ];
    case '数据源/配额异常':
      return [
        _sourceInsightPanel(context, controller, _SourceLens.quotaFailed),
      ];
    case '数据源/待配置来源':
      return [
        _sourceInsightPanel(context, controller, _SourceLens.unconfigured),
      ];
    case '网络遥测/选路状态':
      return [
        _proxyPolicySection(context, controller),
        _proxyRoutingDecisionPanel(context, controller),
      ];
    case '网络遥测/代理节点':
      return [_proxyNodeInventoryPanel(context, controller)];
    case '网络遥测/可连通节点':
      return [_proxyReachabilityPanel(context, controller)];
    case '网络遥测/出口国家':
      return [_proxyExitIdentityPanel(context, controller)];
    case '网络遥测/巡检计划':
      return [
        _proxyInspectionPolicySection(context, controller),
        _proxyInspectionEventPanel(context, controller),
      ];
    case '网络遥测/累计请求':
      return [
        _proxyRequestInsightPanel(
          context,
          controller,
          _ProxyRequestLens.all,
          title: '近期代理请求',
        ),
        _proxyRequestLoadPanel(context, controller),
      ];
    case '网络遥测/成功请求':
      return [
        _proxyRequestInsightPanel(
          context,
          controller,
          _ProxyRequestLens.success,
          title: '成功请求',
        ),
      ];
    case '网络遥测/失败请求':
      return [
        _proxyRequestInsightPanel(
          context,
          controller,
          _ProxyRequestLens.failure,
          title: '失败请求',
        ),
        _proxyFailureEndpointPanel(context, controller),
      ];
    case '网络遥测/超时请求':
      return [
        _proxyRequestInsightPanel(
          context,
          controller,
          _ProxyRequestLens.timeout,
          title: '超时请求',
        ),
      ];
    case '网络遥测/平均响应':
      return [
        _proxyRequestInsightPanel(
          context,
          controller,
          _ProxyRequestLens.all,
          title: '近期响应时序',
        ),
        _proxyLatencyQualityPanel(context, controller),
      ];
    case '网络遥测/p95 响应':
      return [
        _proxyRequestInsightPanel(
          context,
          controller,
          _ProxyRequestLens.all,
          title: '长尾响应样本',
          sortByLatency: true,
        ),
        _proxyTailLatencyPanel(context, controller),
      ];
    case '网络遥测/HTTP 2xx':
      return [
        _proxyRequestInsightPanel(
          context,
          controller,
          _ProxyRequestLens.http,
          title: 'HTTP 响应样本',
        ),
      ];
    case '存储与持久化/SQLite 数据库':
      return [_sqliteDatabaseDetailSection(context, controller)];
    case '存储与持久化/最后写入':
      return [_persistenceWriteEventPanel(context, controller)];
    case '存储与持久化/凭证加密':
      return [
        _credentialEncryptionDetailSection(context, controller),
        resultPanel(
          results.where(
            (result) => result.maskedCredential?.trim().isNotEmpty == true,
          ),
          title: '受保护凭证记录',
          emptyLabel: '暂无需要加密持久化的凭证记录。',
          lens: _ResultRecordLens.credentials,
        ),
      ];
    case '存储与持久化/可见记录':
      return [
        taskPanel(
          histories.take(8),
          title: '最近任务记录',
          lens: _TaskRecordLens.archive,
        ),
        resultPanel(
          results.take(8),
          title: '最近结果记录',
          lens: _ResultRecordLens.archive,
        ),
        logPanel(logs.take(8), title: '最近日志记录'),
      ];
    case '存储与持久化/任务归档':
      return [
        taskPanel(histories, title: '任务归档', lens: _TaskRecordLens.archive),
      ];
    case '存储与持久化/结果归档':
      return [
        resultPanel(results, title: '结果归档', lens: _ResultRecordLens.archive),
      ];
    case '存储与持久化/规则快照':
      return [_ruleInsightPanel(context, rules, title: '规则快照')];
    case '存储与持久化/日志缓冲':
      return [logPanel(logs, title: '日志缓冲', emptyLabel: '日志缓冲为空。')];
    case '存储与持久化/可恢复任务':
      return [
        taskPanel(
          histories.where((entry) => entry.isResumable),
          title: '可恢复任务归档',
          lens: _TaskRecordLens.recovery,
        ),
      ];
    case '存储与持久化/PostgreSQL 镜像':
    case '存储与持久化/Redis 协调':
      return [_dependencyInsightPanel(context, controller, only: label)];
    case '存储与持久化/一致性审计':
      return [_integrityInsightPanel(context, controller)];
    case '安全与依赖/启用规则':
      return [_ruleInsightPanel(context, rules.where((rule) => rule.enabled))];
    case '安全与依赖/凭证模式':
      return [
        _ruleInsightPanel(
          context,
          rules.where(
            (rule) => rule.enabled && rule.credentialPatterns.isNotEmpty,
          ),
          title: '凭证识别规则',
          lens: _RuleDetailLens.credentials,
        ),
      ];
    case '安全与依赖/模型端点':
      return [
        _ruleInsightPanel(
          context,
          rules.where(
            (rule) =>
                rule.enabled &&
                (rule.modelPaths.isNotEmpty || rule.balancePaths.isNotEmpty),
          ),
          title: '主动验证端点',
          lens: _RuleDetailLens.endpoints,
        ),
      ];
    case '安全与依赖/编码识别':
      return [
        _ruleInsightPanel(
          context,
          rules.where(
            (rule) => rule.enabled && rule.contentEncodings.isNotEmpty,
          ),
          title: '内容解码规则',
          lens: _RuleDetailLens.encodings,
        ),
      ];
    case '安全与依赖/代理请求':
      return [
        _proxySecurityBoundaryPanel(context, controller),
        _proxyRequestInsightPanel(
          context,
          controller,
          _ProxyRequestLens.abnormal,
          title: '近期出口异常审计',
        ),
      ];
    case '安全与依赖/代理成功':
      return [_proxySuccessEndpointAuditPanel(context, controller)];
    case '安全与依赖/代理异常':
      return [
        _proxyRequestInsightPanel(
          context,
          controller,
          _ProxyRequestLens.abnormal,
          title: '异常验证请求',
        ),
        _proxyFailureEndpointPanel(context, controller, title: '验证出口异常节点'),
      ];
    case '安全与依赖/依赖就绪':
      return [_dependencyInsightPanel(context, controller)];
  }
  return [logPanel(logs.take(20), title: '最近相关事件')];
}

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
  final duration = entry.finishedAt?.difference(entry.createdAt);
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
      '开始 ${_shortDateTime(entry.createdAt)}',
      if (entry.finishedAt != null) '结束 ${_shortDateTime(entry.finishedAt!)}',
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
      if (entry.finishedAt != null) '归档 ${_shortDateTime(entry.finishedAt!)}',
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
      _shortDateTime(entry.finishedAt ?? entry.createdAt),
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
  );
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
  final title = entry.product.trim().isNotEmpty
      ? '${entry.product} · ${entry.host}'
      : entry.host.isNotEmpty
      ? entry.host
      : entry.url;
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
      '状态 ${entry.credentialState}',
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
      '凭证 ${entry.credentialState}',
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
  );
}

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
    tags: [entry.level.toUpperCase(), _shortDateTime(entry.at)],
    color: tone,
  );
}

enum _SourceLens {
  configured,
  ready,
  quotaAvailable,
  metered,
  enabled,
  invoked,
  produced,
  quotaFailed,
  unconfigured,
}

Widget _sourceInsightPanel(
  BuildContext context,
  ServicesController controller,
  _SourceLens lens,
) {
  final colors = Theme.of(context).colorScheme;
  final jobCounts = <AiExposureSource, int>{};
  for (final job in controller.history) {
    for (final source in job.sources) {
      jobCounts.update(source, (value) => value + 1, ifAbsent: () => 1);
    }
  }
  final resultCounts = <AiExposureSource, int>{};
  for (final result in controller.results) {
    resultCounts.update(result.source, (value) => value + 1, ifAbsent: () => 1);
  }
  final quotaBySource = {
    for (final quota in controller.quotas) quota.source: quota,
  };
  final records = <_InsightRecord>[];
  for (final source in AiExposureSource.values) {
    if (source == AiExposureSource.githubArtifact) continue;
    final credentialScoped = switch (lens) {
      _SourceLens.configured ||
      _SourceLens.ready ||
      _SourceLens.quotaAvailable ||
      _SourceLens.metered ||
      _SourceLens.quotaFailed ||
      _SourceLens.unconfigured => true,
      _SourceLens.enabled ||
      _SourceLens.invoked ||
      _SourceLens.produced => false,
    };
    if (credentialScoped && source == AiExposureSource.manual) continue;
    final key = _sourceCredentialKey(source);
    final configured =
        source == AiExposureSource.manual ||
        controller.sourceStatus[key] == true;
    final quota = quotaBySource[source];
    final enabled = controller.enabledSources.contains(source);
    final calls = jobCounts[source] ?? 0;
    final produced = resultCounts[source] ?? 0;
    final include = switch (lens) {
      _SourceLens.configured => configured,
      _SourceLens.ready => configured && (quota == null || quota.available),
      _SourceLens.quotaAvailable => quota?.available == true,
      _SourceLens.metered => quota?.remaining != null || quota?.limit != null,
      _SourceLens.enabled => enabled,
      _SourceLens.invoked => calls > 0,
      _SourceLens.produced => produced > 0,
      _SourceLens.quotaFailed => quota?.configured == true && !quota!.available,
      _SourceLens.unconfigured => !configured,
    };
    if (!include) continue;
    final tone = quota?.available == true || (configured && quota == null)
        ? OpenHandStatusColors.success
        : configured
        ? OpenHandStatusColors.warning
        : colors.outline;
    records.add(
      _InsightRecord(
        icon: _sourceIcon(source),
        title: _sourceName(source),
        subtitle: quota?.message.trim().isNotEmpty == true
            ? quota!.message.trim()
            : configured
            ? '凭证条件已满足，等待或无需配额探测。'
            : '尚未配置访问凭证。',
        tags: [
          enabled ? '已启用' : '未启用',
          configured ? '已配置' : '待配置',
          if (quota != null) quota.available ? '配额可用' : '配额不可用',
          if (quota?.remaining != null)
            '剩余 ${quota!.remaining}${quota.limit == null ? '' : '/${quota.limit}'}',
          '调用任务 $calls',
          '产出结果 $produced',
          if (quota?.resetsAt != null) '重置 ${_shortDateTime(quota!.resetsAt!)}',
        ],
        color: tone,
      ),
    );
  }
  final title = switch (lens) {
    _SourceLens.configured => '已配置来源',
    _SourceLens.ready => '就绪来源',
    _SourceLens.quotaAvailable => '配额可用来源',
    _SourceLens.metered => '可计量配额来源',
    _SourceLens.enabled => '启用发现来源',
    _SourceLens.invoked => '已调用来源',
    _SourceLens.produced => '有产出来源',
    _SourceLens.quotaFailed => '配额异常来源',
    _SourceLens.unconfigured => '待配置来源',
  };
  return _InsightRecordPanel(
    icon: Icons.travel_explore_rounded,
    title: title,
    records: records,
    emptyLabel: '暂无$title。',
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

Widget _proxyNodeInventoryPanel(
  BuildContext context,
  ServicesController controller,
) {
  final colors = Theme.of(context).colorScheme;
  final runtimeById = _proxyRuntimeById(controller);
  final records = controller.proxyConfiguration.endpoints
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
        );
      })
      .toList(growable: false);
  return _InsightRecordPanel(
    icon: Icons.dns_outlined,
    title: '节点资产与调度配置',
    records: records,
    emptyLabel: '代理池尚未配置节点。',
  );
}

Widget _proxyReachabilityPanel(
  BuildContext context,
  ServicesController controller,
) {
  final colors = Theme.of(context).colorScheme;
  final records = controller.proxyConfiguration.endpoints
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
        );
      })
      .toList(growable: false);
  return _InsightRecordPanel(
    icon: Icons.cloud_done_outlined,
    title: '网关与转发链路诊断',
    records: records,
    emptyLabel: '暂无可执行连通性诊断的代理节点。',
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

FileStat? _localFileStat(String path) {
  if (kIsWeb || path.trim().isEmpty) return null;
  try {
    final stat = File(path).statSync();
    return stat.type == FileSystemEntityType.file ? stat : null;
  } on FileSystemException {
    return null;
  }
}

Widget _sqliteDatabaseDetailSection(
  BuildContext context,
  ServicesController controller,
) {
  final path = controller.health?.databasePath.trim() ?? '';
  final database = _localFileStat(path);
  final wal = _localFileStat(path.isEmpty ? '' : '$path-wal');
  final sharedMemory = _localFileStat(path.isEmpty ? '' : '$path-shm');
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
              : '写入阶段 ${job.stage} 与最终进度快照。',
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
          '凭证 ${result.credentialState}',
        ],
        color: OpenHandStatusColors.success,
      ),
    ));
  }
  for (final log in controller.logs) {
    events.add((
      log.at,
      _InsightRecord(
        icon: Icons.receipt_long_outlined,
        title: '追加运行日志 · ${log.level.toUpperCase()}',
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
  final keyStat = _localFileStat(keyPath);
  final protectedResults = controller.results
      .where((result) => result.maskedCredential?.trim().isNotEmpty == true)
      .toList(growable: false);
  final duplicateReferences = protectedResults.fold<int>(
    0,
    (total, result) => total + result.duplicateKeyHosts,
  );
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
      ),
    );
  }

  add(
    '扫描核心',
    Icons.memory_rounded,
    true,
    controller.isRunning,
    'ai_jungler ${controller.health?.version ?? '--'}',
  );
  add(
    'PostgreSQL 镜像',
    Icons.cloud_sync_outlined,
    dependencies?.postgresql.configured ?? false,
    dependencies?.postgresql.connected ?? false,
    dependencies?.postgresql.message ?? '未启用',
  );
  add(
    'Redis 协调',
    Icons.hub_outlined,
    dependencies?.redis.configured ?? false,
    dependencies?.redis.connected ?? false,
    dependencies?.redis.message ?? '未启用',
  );
  add(
    'Playwright 浏览器',
    Icons.web_outlined,
    dependencies?.playwright.configured ?? false,
    dependencies?.playwright.connected ?? false,
    dependencies?.playwright.message ?? '未启用',
  );
  add(
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
    final orphan = !jobIds.contains(result.jobId);
    final missingEvidence = result.evidence.isEmpty;
    if (!orphan && !missingEvidence) continue;
    records.add(
      _InsightRecord(
        icon: Icons.fact_check_outlined,
        title: result.host.isEmpty ? result.url : result.host,
        subtitle: [
          if (orphan) '关联任务不存在',
          if (missingEvidence) '缺少审计证据',
        ].join(' · '),
        tags: [
          result.jobId,
          _sourceName(result.source),
          result.credentialState,
        ],
        color: OpenHandStatusColors.warning,
      ),
    );
  }
  for (final job in controller.history.where(
    (entry) =>
        !const {'completed', 'failed', 'cancelled'}.contains(entry.stage),
  )) {
    records.add(
      _InsightRecord(
        icon: Icons.pending_actions_outlined,
        title: job.name,
        subtitle: '归档中仍处于 ${_stageName(job.stage)} 阶段。',
        tags: [job.id, _shortDateTime(job.createdAt)],
        color: colors.tertiary,
      ),
    );
  }
  return _InsightRecordPanel(
    icon: Icons.rule_folder_outlined,
    title: '一致性问题',
    records: records,
    emptyLabel: '未发现孤立结果、缺少证据或未结束归档。',
  );
}

Widget? _distributionEntitySection(
  BuildContext context, {
  required String title,
  required ServicesController controller,
}) {
  switch (title) {
    case '结果分类分布':
      return _InsightRecordPanel(
        icon: Icons.fact_check_outlined,
        title: '分类结果明细',
        records: controller.results.map(_resultInsightRecord).toList(),
        emptyLabel: '暂无结果记录。',
      );
    case '凭证状态分布':
      return _InsightRecordPanel(
        icon: Icons.key_outlined,
        title: '凭证验证明细',
        records: controller.results
            .map(
              (entry) =>
                  _resultInsightRecord(entry, _ResultRecordLens.credentials),
            )
            .toList(),
        emptyLabel: '暂无凭证验证记录。',
      );
    case '结果来源分布':
      return _InsightRecordPanel(
        icon: Icons.travel_explore_outlined,
        title: '来源产出明细',
        records: controller.results
            .map(
              (entry) => _resultInsightRecord(entry, _ResultRecordLens.source),
            )
            .toList(),
        emptyLabel: '暂无来源产出记录。',
      );
    case '任务状态分布':
      return _InsightRecordPanel(
        icon: Icons.work_history_outlined,
        title: '任务状态明细',
        records: controller.history.map(_taskInsightRecord).toList(),
        emptyLabel: '暂无任务记录。',
      );
    case '扫描模式分布':
    case '任务来源覆盖':
      return _InsightRecordPanel(
        icon: Icons.schema_outlined,
        title: title == '扫描模式分布' ? '扫描模式明细' : '任务来源明细',
        records: controller.history
            .map((entry) => _taskInsightRecord(entry, _TaskRecordLens.scope))
            .toList(),
        emptyLabel: '暂无任务范围记录。',
      );
    case '任务归档状态':
      return _InsightRecordPanel(
        icon: Icons.inventory_2_outlined,
        title: '任务归档明细',
        records: controller.history
            .map((entry) => _taskInsightRecord(entry, _TaskRecordLens.archive))
            .toList(),
        emptyLabel: '暂无任务归档记录。',
      );
    case '请求结果分布':
    case 'HTTP 状态分布':
    case '代理可靠性分布':
      return _proxyRequestInsightPanel(
        context,
        controller,
        title == 'HTTP 状态分布' ? _ProxyRequestLens.http : _ProxyRequestLens.all,
        title: '对应请求样本',
      );
    case '节点请求分布':
      return _proxyRequestLoadPanel(context, controller);
    case '记录类型分布':
      return _InsightRecordPanel(
        icon: Icons.receipt_long_outlined,
        title: '最近持久化记录',
        records: [
          ...controller.history.take(8).map(_taskInsightRecord),
          ...controller.results
              .take(8)
              .map(
                (entry) =>
                    _resultInsightRecord(entry, _ResultRecordLens.archive),
              ),
          ...controller.logs.reversed.take(8).map(_logInsightRecord),
        ],
        emptyLabel: '暂无持久化记录。',
      );
    case '启用规则供应商分布':
      return _ruleInsightPanel(
        context,
        controller.rules.where((rule) => rule.enabled),
      );
  }
  return null;
}

class _ChartInsightSpec {
  const _ChartInsightSpec({
    required this.chartTitle,
    required this.statisticsTitle,
    this.breakdownTitle = '完整分布明细',
  });

  final String chartTitle;
  final String statisticsTitle;
  final String breakdownTitle;
}

_ChartInsightSpec _trendInsightSpec(String title) => switch (title) {
  '任务处理趋势' => const _ChartInsightSpec(
    chartTitle: '任务级处理与有效产出',
    statisticsTitle: '任务吞吐',
  ),
  '任务耗时趋势' => const _ChartInsightSpec(
    chartTitle: '已结束任务耗时',
    statisticsTitle: '任务耗时',
  ),
  '处理漏斗趋势' => const _ChartInsightSpec(
    chartTitle: '处理、候选与有效转化',
    statisticsTitle: '漏斗层级',
  ),
  '代理响应耗时趋势' => const _ChartInsightSpec(
    chartTitle: '近期代理响应样本',
    statisticsTitle: '响应时延',
  ),
  '归档增长趋势' => const _ChartInsightSpec(
    chartTitle: '累计结果归档',
    statisticsTitle: '归档增长',
  ),
  '任务写入负载' => const _ChartInsightSpec(
    chartTitle: '任务处理与发现写入量',
    statisticsTitle: '写入负载',
  ),
  _ => _ChartInsightSpec(chartTitle: title, statisticsTitle: '序列样本'),
};

_ChartInsightSpec _distributionInsightSpec(String title) => _ChartInsightSpec(
  chartTitle: title,
  statisticsTitle: '分类统计',
  breakdownTitle: switch (title) {
    '结果分类分布' => '完整结果分类',
    '任务状态分布' => '完整任务状态',
    '扫描模式分布' => '完整扫描模式',
    '结果来源分布' => '完整结果来源',
    '任务来源覆盖' => '完整来源覆盖',
    '请求结果分布' => '完整请求结果',
    'HTTP 状态分布' => '完整 HTTP 状态族',
    '节点请求分布' => '完整节点负载',
    '记录类型分布' => '完整记录构成',
    '任务归档状态' => '完整归档状态',
    '凭证状态分布' => '完整凭证状态',
    '代理可靠性分布' => '完整代理结果',
    '启用规则供应商分布' => '完整供应商覆盖',
    _ => '完整分布明细',
  },
);

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
      AiExposureSource.nodeseek => const Color(0xff7c3aed),
      AiExposureSource.linuxDo => const Color(0xff16a34a),
      AiExposureSource.v2ex => const Color(0xff64748b),
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

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: openHandMotionDuration(
          context,
          const Duration(milliseconds: 220),
        ),
        curve: Curves.easeOutCubic,
      );
    });
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
      _scrollToLatest();
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
                ServiceDialogHeaderIconButton(
                  tooltip: _autoFollow
                      ? text(zh: '关闭自动跟随', en: 'Disable auto follow')
                      : text(zh: '开启自动跟随', en: 'Enable auto follow'),
                  onPressed: () {
                    setState(() => _autoFollow = !_autoFollow);
                    if (_autoFollow) _scrollToLatest();
                  },
                  icon: const Icon(Icons.vertical_align_bottom_rounded),
                  tone: _autoFollow
                      ? ServiceDialogHeaderActionTone.primary
                      : ServiceDialogHeaderActionTone.neutral,
                ),
                ServiceDialogHeaderIconButton(
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
                ServiceDialogHeaderIconButton(
                  tooltip: text(zh: '保存日志', en: 'Save logs'),
                  onPressed: logs.isEmpty ? null : () => _saveLogs(logs),
                  icon: const Icon(Icons.save_alt_rounded),
                ),
                ServiceDialogHeaderIconButton(
                  tooltip: text(zh: '清屏', en: 'Clear'),
                  onPressed: controller.logs.isEmpty
                      ? null
                      : controller.clearLogs,
                  icon: const Icon(Icons.cleaning_services_outlined),
                ),
                ServiceDialogHeaderIconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded),
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
                  final color = _logColor(level);
                  return ServiceFilterChip(
                    selected: _levels.contains(level),
                    icon: Icon(_logIcon(level), size: 16, color: color),
                    label: Text(_logLevelName(context, level)),
                    accentColor: color,
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
    final color = _logColor(entry.level);
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

Color _logColor(String level) => switch (level) {
  'error' => OpenHandStatusColors.error,
  'warning' => OpenHandStatusColors.warning,
  'runtime' => const Color(0xff14b8a6),
  _ => OpenHandStatusColors.info,
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
      showSelectedIcon: false,
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(104, 40)),
        animationDuration: openHandMotionDuration(
          context,
          const Duration(milliseconds: 280),
        ),
      ),
    );
  }
}

int _latencyPercentile(List<int> values, double percentile) {
  if (values.isEmpty) return 0;
  values.sort();
  final index = ((values.length - 1) * percentile.clamp(0, 1)).round();
  return values[index];
}

String _proxyStrategyName(AiExposureProxyStrategy strategy) =>
    switch (strategy) {
      AiExposureProxyStrategy.fixed => '固定节点',
      AiExposureProxyStrategy.roundRobin => '轮询调度',
      AiExposureProxyStrategy.random => '随机调度',
      AiExposureProxyStrategy.stickyHost => '目标粘滞',
    };

Color _credentialStateColor(String state, ColorScheme colors) =>
    switch (state) {
      'valid' => OpenHandStatusColors.success,
      'candidate' => OpenHandStatusColors.info,
      'rate_limited' => OpenHandStatusColors.warning,
      'invalid' || 'unauthorized' => OpenHandStatusColors.error,
      'unreachable' => colors.tertiary,
      'duplicate' => colors.secondary,
      _ => colors.outline,
    };

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
  AiExposureSource.nodeseek => 'NodeSeek',
  AiExposureSource.linuxDo => 'LINUX DO',
  AiExposureSource.v2ex => 'V2EX',
};

IconData _sourceIcon(AiExposureSource source) => switch (source) {
  AiExposureSource.manual => Icons.edit_location_alt_outlined,
  AiExposureSource.github => Icons.code_rounded,
  AiExposureSource.githubArtifact => Icons.inventory_2_outlined,
  AiExposureSource.gitee => Icons.code_rounded,
  AiExposureSource.gitcode => Icons.account_tree_outlined,
  AiExposureSource.fofa => Icons.public_rounded,
  AiExposureSource.shodan => Icons.radar_rounded,
  AiExposureSource.nodeseek => Icons.forum_outlined,
  AiExposureSource.linuxDo => Icons.terminal_rounded,
  AiExposureSource.v2ex => Icons.explore_outlined,
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
