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
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/localized_text.dart';
import '../../../shared/util/timer_safety.dart';
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
        final stat = await File(path).stat();
        accessible = stat.type == FileSystemEntityType.file;
        if (accessible) {
          bytes = stat.size;
          modifiedAt = stat.modified;
        }
      } on FileSystemException {
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _OperationsTab(
                value: _OperationsView.overview,
                selected: _view == _OperationsView.overview,
                icon: Icons.dashboard_outlined,
                label: text(zh: '运维总览', en: 'Overview'),
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

class _NetworkPanel extends StatelessWidget {
  const _NetworkPanel({required this.controller});

  final ServicesController controller;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
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
          metrics: [
            _Metric(
              Icons.route_outlined,
              '选路状态',
              configuration.enabled ? '代理池' : '直接连接',
              configuration.enabled
                  ? _proxyStrategyName(configuration.strategy)
                  : '本机网络出口',
              color: configuration.enabled ? colors.primary : colors.outline,
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
              ? const Text('代理池为空，当前所有请求使用直接连接。')
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

class _OpsKeyValue extends StatelessWidget {
  const _OpsKeyValue({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

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
              maxLines: 2,
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
