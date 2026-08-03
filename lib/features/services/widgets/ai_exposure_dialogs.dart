import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_form_fields.dart';
import '../../../shared/ui/openhand_ops_charts.dart';
import '../../../shared/ui/openhand_reveal_switcher.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/localized_text.dart';
import '../../../shared/util/timer_safety.dart';
import '../../plugin_service/index.dart';
import '../model/ai_exposure_models.dart';
import '../services_controller.dart';
import 'service_dialog_controls.dart';

const EdgeInsets _kDialogPadding = EdgeInsets.all(22);
const double _kSectionGap = 18;
const double _kItemGap = 12;
const double _kMetricBreakpoint = 720;
const Duration _kStatusRefreshInterval = Duration(seconds: 8);
const Duration _kStatusMetadataTimeout = Duration(seconds: 2);
const List<AiExposureSource> _kCredentialSources = <AiExposureSource>[
  AiExposureSource.github,
  AiExposureSource.gitee,
  AiExposureSource.gitcode,
  AiExposureSource.fofa,
  AiExposureSource.shodan,
];
const Set<AiExposureSource> _kForumSources = <AiExposureSource>{
  AiExposureSource.nodeseek,
  AiExposureSource.linuxDo,
  AiExposureSource.v2ex,
};
const List<String> _kVendors = <String>[
  'OpenAI Compatible',
  'Anthropic',
  'Gemini',
  'Azure OpenAI',
  'DeepSeek',
  'Qwen',
  '豆包',
  '可灵',
  'GLM',
  'Mimo',
  'MiniMax',
  'Kimi',
  'LongCat',
  'Grok',
  'Mistral',
];

Future<void> showAiExposureStatusDialog(BuildContext context) =>
    showAnimatedDialog<void>(
      context: context,
      builder: (_) => buildOpenHandDialog(
        maxWidth: kOpenHandDialogWidthWide,
        maxHeight: kOpenHandDialogHeightTall,
        child: const ServiceDialogInteractionTheme(child: _StatusDialog()),
      ),
    );

Future<void> showAiExposureNewHuntDialog(
  BuildContext context, {
  bool custom = false,
}) => showAnimatedDialog<void>(
  context: context,
  builder: (_) => buildOpenHandDialog(
    maxWidth: kOpenHandDialogWidthPanel,
    maxHeight: kOpenHandDialogHeightTall,
    child: ServiceDialogInteractionTheme(child: _NewHuntDialog(custom: custom)),
  ),
);

Future<void> showAiExposureProgressDialog(BuildContext context) =>
    showAnimatedDialog<void>(
      context: context,
      builder: (_) => buildOpenHandDialog(
        maxWidth: kOpenHandDialogWidthExtraWide,
        maxHeight: kOpenHandDialogHeightTall,
        child: const ServiceDialogInteractionTheme(child: _ProgressDialog()),
      ),
    );

Future<void> showAiExposureResultsDialog(BuildContext context) =>
    showAnimatedDialog<void>(
      context: context,
      builder: (_) => buildOpenHandDialog(
        maxWidth: kOpenHandDialogWidthPanel,
        maxHeight: kOpenHandDialogHeightTall,
        child: const ServiceDialogInteractionTheme(child: _ResultsDialog()),
      ),
    );

Future<void> showAiExposureHistoryDialog(BuildContext context) =>
    showAnimatedDialog<void>(
      context: context,
      builder: (_) => buildOpenHandDialog(
        maxWidth: kOpenHandDialogWidthExtraWide,
        maxHeight: kOpenHandDialogHeightTall,
        child: const ServiceDialogInteractionTheme(child: _HistoryDialog()),
      ),
    );

Future<void> showAiExposureToolsDialog(BuildContext context) =>
    showAnimatedDialog<void>(
      context: context,
      builder: (_) => buildOpenHandDialog(
        maxWidth: kOpenHandDialogWidthWide,
        maxHeight: kOpenHandDialogHeightTall,
        child: const ServiceDialogInteractionTheme(child: _ToolsDialog()),
      ),
    );

Future<void> showAiExposureRulesDialog(BuildContext context) =>
    showAnimatedDialog<void>(
      context: context,
      builder: (_) => buildOpenHandDialog(
        maxWidth: kOpenHandDialogWidthPanel,
        maxHeight: kOpenHandDialogHeightTall,
        child: const ServiceDialogInteractionTheme(child: _RulesDialog()),
      ),
    );

Future<void> showAiExposureSettingsDialog(BuildContext context) =>
    showAnimatedDialog<void>(
      context: context,
      builder: (_) => buildOpenHandDialog(
        maxWidth: kOpenHandDialogWidthWide,
        maxHeight: kOpenHandDialogHeightTall,
        child: const ServiceDialogInteractionTheme(child: _SettingsDialog()),
      ),
    );

class _StatusDialog extends StatefulWidget {
  const _StatusDialog();

  @override
  State<_StatusDialog> createState() => _StatusDialogState();
}

class _StatusDialogState extends State<_StatusDialog> {
  Timer? _timer;
  bool _refreshing = false;
  bool _databaseAccessible = false;
  int? _databaseBytes;
  DateTime? _databaseModifiedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _timer = startSafePeriodicTimer(_kStatusRefreshInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted || _refreshing) return;
    final controller = context.read<ServicesController>();
    setState(() => _refreshing = true);
    if (controller.isRunning) await controller.refreshServiceStatus();
    final path = controller.health?.databasePath.trim() ?? '';
    var accessible = false;
    int? bytes;
    DateTime? modifiedAt;
    if (path.isNotEmpty) {
      try {
        final stat = await File(path).stat().timeout(_kStatusMetadataTimeout);
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
    final text = openHandTextResolver(context);
    return Consumer<ServicesController>(
      builder: (context, controller, _) {
        final theme = Theme.of(context);
        final health = controller.health;
        final running = controller.isRunning;
        final progress = controller.progress;
        final dependencies = controller.dependencyStatus;
        final proxy = controller.proxyStatus;
        final proxySuccesses = proxy?.totalSuccesses ?? 0;
        final proxyTimeouts = proxy?.totalTimeouts ?? 0;
        final history = controller.history;
        final results = controller.results;
        final configuredSources = controller.sourceStatus.values
            .where((configured) => configured)
            .length;
        final enabledRules = controller.rules
            .where((rule) => rule.enabled)
            .length;
        final completedJobs = history
            .where((entry) => entry.stage == 'completed')
            .length;
        final failedJobs = history
            .where((entry) => entry.stage == 'failed')
            .length;
        final highValue = results
            .where(
              (result) => result.category == AiExposureResultCategory.highValue,
            )
            .length;
        final warnings = controller.logs
            .where((entry) => entry.level == 'warning')
            .length;
        final errors = controller.logs
            .where((entry) => entry.level == 'error')
            .length;
        final recentHistory = history.take(18).toList().reversed.toList();
        final lifecycleLabel = switch (controller.lifecycle) {
          AiExposureServiceLifecycle.starting => text(
            zh: '启动中',
            en: 'Starting',
          ),
          AiExposureServiceLifecycle.running => text(zh: '运行中', en: 'Running'),
          AiExposureServiceLifecycle.stopping => text(
            zh: '停止中',
            en: 'Stopping',
          ),
          AiExposureServiceLifecycle.error => text(zh: '异常', en: 'Error'),
          AiExposureServiceLifecycle.stopped => text(zh: '已停止', en: 'Stopped'),
        };
        return _DialogFrame(
          icon: Icons.monitor_heart_outlined,
          title: text(zh: '服务状态', en: 'Service status'),
          subtitle: text(
            zh: 'ai_jungler 运行健康、工作负载、附属服务与持久化状态',
            en: 'ai_jungler health, workload, dependencies, and persistence',
          ),
          footer: _DialogActions(
            actions: [
              OpenHandDialogActionButton.secondary(
                icon: Icons.refresh_rounded,
                onPressed: running && !_refreshing ? _refresh : null,
                label: text(zh: '刷新状态', en: 'Refresh status'),
              ),
              OpenHandDialogActionButton.primary(
                icon: running ? Icons.stop_rounded : Icons.play_arrow_rounded,
                onPressed: controller.busy
                    ? null
                    : running
                    ? controller.stopService
                    : controller.startService,
                label: running
                    ? text(zh: '停止服务', en: 'Stop service')
                    : text(zh: '启动服务', en: 'Start service'),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ServiceTelemetryConsole(controller: controller),
              const SizedBox(height: 14),
              _MetricGrid(
                items: [
                  _MetricData(
                    icon: running
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off_outlined,
                    label: text(zh: '连接状态', en: 'Connection'),
                    value: running
                        ? text(zh: '已连接', en: 'Connected')
                        : text(zh: '未连接', en: 'Disconnected'),
                    detail: controller.ownsProcess
                        ? text(zh: 'OpenHand 托管进程', en: 'Managed process')
                        : text(zh: '外部服务连接', en: 'External service'),
                    color: running
                        ? OpenHandStatusColors.success
                        : theme.colorScheme.outline,
                  ),
                  _MetricData(
                    icon: Icons.monitor_heart_rounded,
                    label: text(zh: '生命周期', en: 'Lifecycle'),
                    value: lifecycleLabel,
                    detail: controller.busy
                        ? text(zh: '状态切换中', en: 'Transitioning')
                        : text(zh: '控制面已就绪', en: 'Control plane ready'),
                    color: running
                        ? OpenHandStatusColors.success
                        : controller.lifecycle ==
                              AiExposureServiceLifecycle.error
                        ? OpenHandStatusColors.error
                        : theme.colorScheme.outline,
                  ),
                  _MetricData(
                    icon: Icons.memory_rounded,
                    label: text(zh: '后端版本', en: 'Backend version'),
                    value: health?.version.isNotEmpty == true
                        ? health!.version
                        : '--',
                    detail: 'ai_jungler',
                    color: theme.colorScheme.tertiary,
                  ),
                  _MetricData(
                    icon: Icons.schedule_rounded,
                    label: text(zh: '连续运行', en: 'Uptime'),
                    value: _serviceDuration(health?.uptimeSeconds ?? 0),
                    detail: text(zh: '当前进程周期', en: 'Current process cycle'),
                    color: theme.colorScheme.primary,
                  ),
                  _MetricData(
                    icon: Icons.radar_rounded,
                    label: text(zh: '当前任务', en: 'Current job'),
                    value: progress?.isRunning == true
                        ? _stageLabel(context, progress!.stage)
                        : text(zh: '空闲', en: 'Idle'),
                    detail: progress == null
                        ? text(zh: '等待扫描任务', en: 'Awaiting scan')
                        : '${progress.processed}/${progress.total}',
                    color: progress?.isRunning == true
                        ? OpenHandStatusColors.info
                        : theme.colorScheme.outline,
                  ),
                  _MetricData(
                    icon: Icons.work_history_outlined,
                    label: text(zh: '任务归档', en: 'Job archive'),
                    value: '${history.length}',
                    detail: text(
                      zh: '完成 $completedJobs · 失败 $failedJobs',
                      en: '$completedJobs completed · $failedJobs failed',
                    ),
                    color: theme.colorScheme.primary,
                  ),
                  _MetricData(
                    icon: Icons.fact_check_outlined,
                    label: text(zh: '结果库存', en: 'Result inventory'),
                    value: '${results.length}',
                    detail: text(
                      zh: '高价值 $highValue',
                      en: '$highValue high value',
                    ),
                    color: OpenHandStatusColors.info,
                  ),
                  _MetricData(
                    icon: Icons.travel_explore_rounded,
                    label: text(zh: '就绪数据源', en: 'Ready sources'),
                    value:
                        '$configuredSources/${controller.discoverySourceCount}',
                    detail: text(
                      zh: '启用 ${controller.enabledSources.length} 类来源',
                      en: '${controller.enabledSources.length} source types enabled',
                    ),
                    color: OpenHandStatusColors.success,
                  ),
                  _MetricData(
                    icon: Icons.rule_rounded,
                    label: text(zh: '规则覆盖', en: 'Rule coverage'),
                    value: '$enabledRules/${controller.rules.length}',
                    detail: text(
                      zh: '并发 ${controller.defaultConcurrency}',
                      en: 'Concurrency ${controller.defaultConcurrency}',
                    ),
                    color: const Color(0xff0f766e),
                  ),
                  _MetricData(
                    icon: Icons.lan_outlined,
                    label: text(zh: '代理请求', en: 'Proxy requests'),
                    value: '${proxy?.totalSelections ?? 0}',
                    detail: proxy?.enabled == true
                        ? text(
                            zh: '成功 $proxySuccesses · 超时 $proxyTimeouts',
                            en: '$proxySuccesses ok · $proxyTimeouts timeout',
                          )
                        : text(zh: '直接连接', en: 'Direct connection'),
                    color: const Color(0xff0891b2),
                  ),
                  _MetricData(
                    icon: Icons.speed_rounded,
                    label: text(zh: '代理平均响应', en: 'Proxy latency'),
                    value: '${proxy?.averageResponseTimeMs ?? 0} ms',
                    detail: text(
                      zh: '执行中 ${proxy?.inFlight ?? 0}',
                      en: '${proxy?.inFlight ?? 0} in flight',
                    ),
                    color: theme.colorScheme.secondary,
                  ),
                  _MetricData(
                    icon: errors > 0
                        ? Icons.error_outline_rounded
                        : Icons.verified_outlined,
                    label: text(zh: '运行事件', en: 'Runtime events'),
                    value: '${controller.logs.length}',
                    detail: text(
                      zh: '警告 $warnings · 错误 $errors',
                      en: '$warnings warnings · $errors errors',
                    ),
                    color: errors > 0
                        ? OpenHandStatusColors.error
                        : warnings > 0
                        ? OpenHandStatusColors.warning
                        : OpenHandStatusColors.success,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _StatusPanelGrid(
                children: [
                  _StatusTrendPanel(
                    title: text(zh: '任务处理趋势', en: 'Processing trend'),
                    subtitle: text(
                      zh: '最近 ${recentHistory.length} 个任务',
                      en: 'Latest ${recentHistory.length} jobs',
                    ),
                    series: [
                      OpenHandChartSeries(
                        label: text(zh: '处理', en: 'Processed'),
                        values: recentHistory
                            .map((entry) => entry.progress.processed.toDouble())
                            .toList(),
                        color: theme.colorScheme.primary,
                      ),
                      OpenHandChartSeries(
                        label: text(zh: '发现', en: 'Discovered'),
                        values: recentHistory
                            .map(
                              (entry) => entry.progress.discovered.toDouble(),
                            )
                            .toList(),
                        color: OpenHandStatusColors.info,
                      ),
                      OpenHandChartSeries(
                        label: text(zh: '有效', en: 'Valid'),
                        values: recentHistory
                            .map((entry) => entry.progress.valid.toDouble())
                            .toList(),
                        color: OpenHandStatusColors.success,
                      ),
                    ],
                  ),
                  _StatusDistributionPanel(
                    title: text(zh: '结果分类分布', en: 'Result distribution'),
                    centerValue: '${results.length}',
                    items: [
                      _StatusDistributionItem(
                        text(zh: '有效', en: 'Valid'),
                        results
                            .where(
                              (item) =>
                                  item.category ==
                                  AiExposureResultCategory.valid,
                            )
                            .length,
                        OpenHandStatusColors.success,
                      ),
                      _StatusDistributionItem(
                        text(zh: '高价值', en: 'High value'),
                        highValue,
                        const Color(0xffa855f7),
                      ),
                      _StatusDistributionItem(
                        text(zh: '可疑', en: 'Suspicious'),
                        results
                            .where(
                              (item) =>
                                  item.category ==
                                  AiExposureResultCategory.suspicious,
                            )
                            .length,
                        OpenHandStatusColors.warning,
                      ),
                      _StatusDistributionItem(
                        text(zh: '蜜罐', en: 'Honeypot'),
                        results
                            .where(
                              (item) =>
                                  item.category ==
                                  AiExposureResultCategory.honeypot,
                            )
                            .length,
                        OpenHandStatusColors.error,
                      ),
                    ],
                  ),
                ],
              ),
              OpenHandVerticalRevealSwitcher(
                presentKey: progress == null
                    ? null
                    : ValueKey<String>(
                        '${progress.jobId}-${progress.stage}-${progress.updatedAt.microsecondsSinceEpoch}',
                      ),
                child: progress == null
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: _StatusSectionCard(
                          icon: Icons.radar_rounded,
                          title: text(
                            zh: '当前任务实时遥测',
                            en: 'Current job telemetry',
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(progress.message),
                              const SizedBox(height: 10),
                              LinearProgressIndicator(
                                value: progress.total > 0
                                    ? progress.fraction
                                    : null,
                                minHeight: 8,
                                borderRadius: BorderRadius.circular(99),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                text(
                                  zh: '发现 ${progress.discovered} · 候选 ${progress.candidates} · 有效 ${progress.valid} · 高价值 ${progress.highValue} · 已处理 ${progress.processed}/${progress.total}',
                                  en: 'Discovered ${progress.discovered} · candidates ${progress.candidates} · valid ${progress.valid} · high value ${progress.highValue} · processed ${progress.processed}/${progress.total}',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 14),
              _StatusPanelGrid(
                children: [
                  _StatusSectionCard(
                    icon: Icons.hub_outlined,
                    title: text(zh: '运行依赖矩阵', en: 'Dependency matrix'),
                    child: Column(
                      children: [
                        _DependencyRow(
                          name: 'ai_jungler',
                          detail: text(
                            zh: 'OpenHand 自研 Rust 扫描引擎',
                            en: 'OpenHand Rust scanner',
                          ),
                          ready: running,
                          required: true,
                        ),
                        const SizedBox(height: 10),
                        _DependencyRow(
                          name: 'SQLite WAL',
                          detail: text(
                            zh: '任务、规则、结果与日志本地持久化',
                            en: 'Local jobs, rules, results, and logs',
                          ),
                          ready: _databaseAccessible,
                          required: true,
                        ),
                        const SizedBox(height: 10),
                        _DependencyRow(
                          name: 'PostgreSQL',
                          detail:
                              dependencies?.postgresql.message ??
                              text(zh: '未启用远程镜像', en: 'Remote mirror off'),
                          ready: dependencies?.postgresql.connected == true,
                          required: false,
                        ),
                        const SizedBox(height: 10),
                        _DependencyRow(
                          name: 'Redis',
                          detail:
                              dependencies?.redis.message ??
                              text(
                                zh: '未启用跨实例协调',
                                en: 'Cross-instance coordination off',
                              ),
                          ready: dependencies?.redis.connected == true,
                          required: false,
                        ),
                        const SizedBox(height: 10),
                        _DependencyRow(
                          name: 'Playwright',
                          detail:
                              dependencies?.playwright.message ??
                              text(
                                zh: '浏览器降级通道未接入',
                                en: 'Browser fallback is not connected',
                              ),
                          ready: dependencies?.playwright.connected == true,
                          required: false,
                        ),
                        const SizedBox(height: 10),
                        _DependencyRow(
                          name: text(zh: 'GPT 辅助提取', en: 'GPT extraction'),
                          detail:
                              controller.aiExtractorStatus?.model ??
                              text(zh: '使用确定性规则', en: 'Deterministic rules'),
                          ready:
                              controller.aiExtractorStatus?.configured == true,
                          required: false,
                        ),
                      ],
                    ),
                  ),
                  _StatusSectionCard(
                    icon: Icons.storage_rounded,
                    title: text(zh: '持久化与完整性', en: 'Persistence integrity'),
                    child: Column(
                      children: [
                        _StatusKeyValue(
                          label: text(zh: '数据库文件', en: 'Database file'),
                          value: _databaseAccessible
                              ? formatByteSize(_databaseBytes ?? 0)
                              : text(zh: '当前不可访问', en: 'Not accessible'),
                        ),
                        _StatusKeyValue(
                          label: text(zh: '最后写入', en: 'Last write'),
                          value: _databaseModifiedAt == null
                              ? '--'
                              : _dateTime(_databaseModifiedAt!),
                        ),
                        _StatusKeyValue(
                          label: text(zh: '持久化记录', en: 'Persisted records'),
                          value: text(
                            zh: '任务 ${history.length} · 结果 ${results.length} · 规则 ${controller.rules.length}',
                            en: '${history.length} jobs · ${results.length} results · ${controller.rules.length} rules',
                          ),
                        ),
                        _StatusKeyValue(
                          label: text(zh: '凭证保护', en: 'Credential protection'),
                          value: 'AES-256-GCM',
                        ),
                        _StatusKeyValue(
                          label: text(zh: '日志缓冲', en: 'Log buffer'),
                          value: text(
                            zh: '${controller.logs.length} 条',
                            en: '${controller.logs.length} entries',
                          ),
                        ),
                        OpenHandVerticalRevealSwitcher(
                          presentKey: const ValueKey<String>(
                            'status-database-path',
                          ),
                          child: health?.databasePath.isNotEmpty != true
                              ? null
                              : Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    child: SelectableText(
                                      health!.databasePath,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                            fontFamily: 'monospace',
                                          ),
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _StatusPanelGrid(
                children: [
                  _StatusSectionCard(
                    icon: Icons.data_usage_rounded,
                    title: text(zh: '数据源配额与健康', en: 'Source quota health'),
                    child: controller.quotas.isEmpty
                        ? _EmptyLine(
                            text: running
                                ? text(
                                    zh: '正在等待代码托管、测绘平台与论坛数据源健康响应。',
                                    en: 'Waiting for source quota responses.',
                                  )
                                : text(
                                    zh: '启动服务后可查询数据源配额。',
                                    en: 'Start the service to query quotas.',
                                  ),
                          )
                        : Column(
                            children: [
                              for (
                                var index = 0;
                                index < controller.quotas.length;
                                index++
                              ) ...[
                                _QuotaRow(quota: controller.quotas[index]),
                                if (index < controller.quotas.length - 1)
                                  const SizedBox(height: 10),
                              ],
                            ],
                          ),
                  ),
                  _StatusSectionCard(
                    icon: Icons.tune_rounded,
                    title: text(zh: '运行配置快照', en: 'Runtime configuration'),
                    child: Column(
                      children: [
                        _StatusKeyValue(
                          label: text(zh: '引擎模式', en: 'Engine mode'),
                          value: controller.useBundledEngine
                              ? text(zh: 'OpenHand 托管', en: 'OpenHand managed')
                              : text(zh: '外部服务', en: 'External service'),
                        ),
                        _StatusKeyValue(
                          label: text(zh: '默认并发', en: 'Concurrency'),
                          value: '${controller.defaultConcurrency}/128',
                        ),
                        _StatusKeyValue(
                          label: text(zh: '验证策略', en: 'Validation'),
                          value:
                              controller.defaultValidationMode ==
                                  AiExposureValidationMode.authorizedActive
                              ? text(zh: '授权主动验证', en: 'Authorized active')
                              : text(zh: '被动验证', en: 'Passive'),
                        ),
                        _StatusKeyValue(
                          label: text(zh: '代理选路', en: 'Proxy routing'),
                          value: proxy?.enabled == true
                              ? '${proxy!.strategy.name} · ${proxy.endpoints.length}'
                              : text(zh: '直接连接', en: 'Direct'),
                        ),
                        _StatusKeyValue(
                          label: text(zh: '论坛读取', en: 'Forum reader'),
                          value:
                              controller.forumFetchMode ==
                                  AiExposureForumFetchMode.jinaFallback
                              ? text(
                                  zh: 'Jina 优先 · Playwright 降级',
                                  en: 'Jina first · Playwright fallback',
                                )
                              : text(
                                  zh: 'Playwright 直读',
                                  en: 'Playwright direct',
                                ),
                        ),
                        _StatusKeyValue(
                          label: text(
                            zh: 'PostgreSQL 镜像',
                            en: 'PostgreSQL mirror',
                          ),
                          value: controller.postgresqlEnabled
                              ? text(zh: '已选择', en: 'Selected')
                              : text(zh: '未选择', en: 'Not selected'),
                        ),
                        _StatusKeyValue(
                          label: text(zh: 'Redis 协调', en: 'Redis coordination'),
                          value: controller.redisEnabled
                              ? text(zh: '已选择', en: 'Selected')
                              : text(zh: '未选择', en: 'Not selected'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NewHuntDialog extends StatefulWidget {
  const _NewHuntDialog({required this.custom});
  final bool custom;

  @override
  State<_NewHuntDialog> createState() => _NewHuntDialogState();
}

class _NewHuntDialogState extends State<_NewHuntDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.custom ? '自定义暴露面狩猎' : 'AI 基础设施暴露面扫描',
  );
  final TextEditingController _scope = TextEditingController();
  final TextEditingController _targets = TextEditingController();
  final TextEditingController _fofaQuery = TextEditingController();
  final TextEditingController _shodanQuery = TextEditingController();
  final TextEditingController _githubQuery = TextEditingController();
  final TextEditingController _giteeQuery = TextEditingController();
  final TextEditingController _gitcodeQuery = TextEditingController();
  final TextEditingController _nodeseekQuery = TextEditingController();
  final TextEditingController _linuxDoQuery = TextEditingController();
  final TextEditingController _v2exQuery = TextEditingController();
  late Set<AiExposureSource> _sources;
  final Set<String> _vendors = Set<String>.of(_kVendors);
  AiExposureScanMode _mode = AiExposureScanMode.incremental;
  late AiExposureValidationMode _validationMode;
  late AiExposureForumFetchMode _forumFetchMode;
  late bool _gptAssisted;
  late double _concurrency;
  bool _confirmed = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final controller = context.read<ServicesController>();
    _sources = widget.custom
        ? <AiExposureSource>{AiExposureSource.manual}
        : Set<AiExposureSource>.of(controller.enabledSources);
    _validationMode = controller.defaultValidationMode;
    _forumFetchMode = controller.forumFetchMode;
    _gptAssisted = controller.defaultGptAssisted;
    _concurrency = controller.defaultConcurrency.toDouble();
  }

  @override
  void dispose() {
    _name.dispose();
    _scope.dispose();
    _targets.dispose();
    _fofaQuery.dispose();
    _shodanQuery.dispose();
    _githubQuery.dispose();
    _giteeQuery.dispose();
    _gitcodeQuery.dispose();
    _nodeseekQuery.dispose();
    _linuxDoQuery.dispose();
    _v2exQuery.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    final controller = context.watch<ServicesController>();
    return _DialogFrame(
      icon: widget.custom ? Icons.tune_rounded : Icons.add_rounded,
      title: widget.custom
          ? text(zh: '自定义狩猎', en: 'Custom hunt')
          : text(zh: '新建狩猎', en: 'New hunt'),
      footer: _DialogActions(
        actions: [
          OpenHandDialogActionButton.secondary(
            onPressed: () => Navigator.of(context).maybePop(),
            label: openHandCancelLabel(context),
          ),
          OpenHandDialogActionButton.primary(
            icon: Icons.play_arrow_rounded,
            onPressed: controller.isRunning && !_submitting ? _submit : null,
            label: text(zh: '开始扫描', en: 'Start scan'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OpenHandVerticalRevealSwitcher(
            presentKey: const ValueKey<String>('service-stopped-notice'),
            child: controller.isRunning
                ? null
                : Padding(
                    padding: const EdgeInsets.only(bottom: _kSectionGap),
                    child: _InlineNotice(
                      icon: Icons.power_settings_new_rounded,
                      text: text(
                        zh: '扫描服务尚未启动。请先返回服务卡启动服务。',
                        en: 'The scanner service is stopped. Start it from the service card first.',
                      ),
                    ),
                  ),
          ),
          TextField(
            controller: _name,
            maxLength: 120,
            buildCounter: openHandHiddenTextFieldCounter,
            decoration: InputDecoration(
              labelText: text(zh: '任务名称', en: 'Job name'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: _kSectionGap),
          _SectionTitle(
            icon: Icons.travel_explore_rounded,
            title: text(zh: '数据源', en: 'Sources'),
          ),
          const SizedBox(height: _kItemGap),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: AiExposureSource.values
                .map((source) {
                  return ServiceFilterChip(
                    selected: _sources.contains(source),
                    icon: Icon(_sourceIcon(source), size: 17),
                    label: Text(_sourceLabel(context, source)),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _sources.add(source);
                      } else {
                        _sources.remove(source);
                      }
                    }),
                  );
                })
                .toList(growable: false),
          ),
          OpenHandVerticalRevealSwitcher(
            presentKey: const ValueKey<String>('forum-fetch-mode'),
            slideBeginOffsetY: -.03,
            child: !_sources.any(_kForumSources.contains)
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: _kSectionGap),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SectionTitle(
                          icon: Icons.alt_route_rounded,
                          title: text(zh: '论坛读取通道', en: 'Forum reader route'),
                        ),
                        const SizedBox(height: _kItemGap),
                        SegmentedButton<AiExposureForumFetchMode>(
                          segments: [
                            ButtonSegment(
                              value: AiExposureForumFetchMode.jinaFallback,
                              icon: const Icon(Icons.auto_awesome_rounded),
                              label: Text(
                                text(zh: 'Jina 优先降级', en: 'Jina with fallback'),
                              ),
                            ),
                            ButtonSegment(
                              value: AiExposureForumFetchMode.playwright,
                              icon: const Icon(Icons.language_rounded),
                              label: Text(
                                text(
                                  zh: 'Playwright 直读',
                                  en: 'Playwright direct',
                                ),
                              ),
                            ),
                          ],
                          selected: <AiExposureForumFetchMode>{_forumFetchMode},
                          onSelectionChanged: (selection) =>
                              setState(() => _forumFetchMode = selection.first),
                        ),
                        const SizedBox(height: 8),
                        _InlineNotice(
                          icon:
                              controller
                                      .dependencyStatus
                                      ?.playwright
                                      .connected ==
                                  true
                              ? Icons.check_circle_outline_rounded
                              : Icons.info_outline_rounded,
                          text:
                              controller
                                      .dependencyStatus
                                      ?.playwright
                                      .connected ==
                                  true
                              ? text(
                                  zh: 'Jina 请求与浏览器读取都会复用当前网络代理和代理池。Jina 失败时将记录原因并自动切换浏览器。',
                                  en: 'Jina and browser requests reuse the configured proxy pool. Jina failures are logged before browser fallback.',
                                )
                              : text(
                                  zh: '当前未接入 Playwright，Jina 失败时会明确记录失败原因；可在服务设置中安装浏览器依赖。',
                                  en: 'Playwright is unavailable; Jina failures will be reported clearly. Install the browser dependency in service settings.',
                                ),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: _kSectionGap),
          _SectionTitle(
            icon: Icons.sync_alt_rounded,
            title: text(zh: '扫描模式', en: 'Scan mode'),
          ),
          const SizedBox(height: _kItemGap),
          SegmentedButton<AiExposureScanMode>(
            segments: [
              ButtonSegment(
                value: AiExposureScanMode.incremental,
                icon: const Icon(Icons.update_rounded),
                label: Text(text(zh: '增量', en: 'Incremental')),
              ),
              ButtonSegment(
                value: AiExposureScanMode.full,
                icon: const Icon(Icons.restart_alt_rounded),
                label: Text(text(zh: '全量', en: 'Full')),
              ),
            ],
            selected: <AiExposureScanMode>{_mode},
            onSelectionChanged: (selection) =>
                setState(() => _mode = selection.first),
          ),
          const SizedBox(height: _kSectionGap),
          TextField(
            controller: _scope,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: text(zh: '授权目标范围', en: 'Authorized scope'),
              hintText: 'example.com\n10.10.0.0/16',
              border: const OutlineInputBorder(),
            ),
          ),
          OpenHandVerticalRevealSwitcher(
            presentKey: const ValueKey<String>('manual-targets'),
            slideBeginOffsetY: -.03,
            child: !_sources.contains(AiExposureSource.manual)
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: _kItemGap),
                    child: TextField(
                      controller: _targets,
                      minLines: 3,
                      maxLines: 7,
                      decoration: InputDecoration(
                        labelText: text(zh: '手工目标', en: 'Manual targets'),
                        hintText: 'https://api.example.com\n10.10.2.8:8080',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
          ),
          if (widget.custom) ...[
            const SizedBox(height: _kSectionGap),
            _SectionTitle(
              icon: Icons.manage_search_rounded,
              title: text(zh: '补充发现查询', en: 'Supplemental queries'),
            ),
            const SizedBox(height: _kItemGap),
            _QueryFields(
              fofa: _fofaQuery,
              shodan: _shodanQuery,
              github: _githubQuery,
              gitee: _giteeQuery,
              gitcode: _gitcodeQuery,
              nodeseek: _nodeseekQuery,
              linuxDo: _linuxDoQuery,
              v2ex: _v2exQuery,
            ),
          ],
          const SizedBox(height: _kSectionGap),
          _SectionTitle(
            icon: Icons.hub_outlined,
            title: text(zh: 'AI 厂商协议', en: 'AI providers'),
          ),
          const SizedBox(height: _kItemGap),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: _kVendors
                .map((vendor) {
                  return ServiceFilterChip(
                    selected: _vendors.contains(vendor),
                    label: Text(vendor),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _vendors.add(vendor);
                      } else {
                        _vendors.remove(vendor);
                      }
                    }),
                  );
                })
                .toList(growable: false),
          ),
          const SizedBox(height: _kSectionGap),
          OpenHandAnimatedSwitchTile(
            icon: Icons.verified_user_outlined,
            disabledIcon: Icons.visibility_outlined,
            title: text(zh: '授权主动验证', en: 'Authorized active validation'),
            description: text(
              zh: _validationMode == AiExposureValidationMode.authorizedActive
                  ? '查询同一授权主机的模型列表以确认凭证状态。'
                  : '仅做被动识别，不发送发现的原始凭证。',
              en: _validationMode == AiExposureValidationMode.authorizedActive
                  ? 'Query the model list on the same authorized host.'
                  : 'Passive detection only; discovered credentials are not sent.',
            ),
            value: _validationMode == AiExposureValidationMode.authorizedActive,
            onChanged: (enabled) => setState(() {
              _validationMode = enabled
                  ? AiExposureValidationMode.authorizedActive
                  : AiExposureValidationMode.passive;
            }),
          ),
          const SizedBox(height: _kItemGap),
          OpenHandAnimatedSwitchTile(
            icon: Icons.auto_awesome_rounded,
            disabledIcon: Icons.auto_awesome_outlined,
            title: text(zh: 'GPT 辅助提取', en: 'GPT-assisted extraction'),
            description: controller.selectedAiExtractorModelLabel == null
                ? text(
                    zh: '需先在全局设置中选择 OpenAI Compatible 模型。',
                    en: 'Select an OpenAI-compatible model in global settings first.',
                  )
                : text(
                    zh: '确定性规则未命中时使用 ${controller.selectedAiExtractorModelLabel} 辅助分析。',
                    en: 'Use ${controller.selectedAiExtractorModelLabel} when deterministic rules find nothing.',
                  ),
            value: _gptAssisted,
            onChanged: (enabled) {
              if (enabled && controller.selectedAiExtractorModelLabel == null) {
                showOpenHandErrorSnack(
                  context,
                  text(
                    zh: '当前没有可用于辅助提取的 OpenAI Compatible 模型。',
                    en: 'No OpenAI-compatible model is available for assisted extraction.',
                  ),
                );
                return;
              }
              setState(() => _gptAssisted = enabled);
            },
          ),
          const SizedBox(height: _kSectionGap),
          Row(
            children: [
              Expanded(
                child: OpenHandFormLabel(text(zh: '并发数', en: 'Concurrency')),
              ),
              Text('${_concurrency.round()}'),
            ],
          ),
          Slider(
            value: _concurrency,
            min: 1,
            max: 128,
            divisions: 127,
            label: '${_concurrency.round()}',
            onChanged: (value) => setState(() => _concurrency = value),
          ),
          CheckboxListTile(
            key: const ValueKey<String>('hunt-authorization-confirmation'),
            contentPadding: EdgeInsets.zero,
            hoverColor: Colors.transparent,
            overlayColor: const WidgetStatePropertyAll<Color>(
              Colors.transparent,
            ),
            value: _confirmed,
            onChanged: (value) => setState(() => _confirmed = value == true),
            title: Text(
              text(
                zh: '我确认已获得上述目标范围的安全评估授权',
                en: 'I confirm authorization to assess the declared scope',
              ),
            ),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final text = openHandTextResolver(context);
    final scope = _lines(_scope.text);
    final targets = _lines(_targets.text);
    if (_name.text.trim().isEmpty || scope.isEmpty || _sources.isEmpty) {
      showOpenHandErrorSnack(
        context,
        text(
          zh: '请填写任务名称、授权范围并选择数据源。',
          en: 'Enter a name, scope, and at least one source.',
        ),
      );
      return;
    }
    if (_sources.contains(AiExposureSource.manual) && targets.isEmpty) {
      showOpenHandErrorSnack(
        context,
        text(zh: '启用手工目标时至少填写一个目标。', en: 'Add at least one manual target.'),
      );
      return;
    }
    if (!_confirmed) {
      showOpenHandErrorSnack(
        context,
        text(
          zh: '开始扫描前必须确认目标授权。',
          en: 'Confirm target authorization before scanning.',
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    final controller = context.read<ServicesController>();
    final preferencesUpdated = await controller.updateScanPreferences(
      enabledSources: _sources,
      concurrency: _concurrency.round(),
      validationMode: _validationMode,
      forumFetchMode: _forumFetchMode,
      gptAssisted: _gptAssisted,
    );
    if (!preferencesUpdated) {
      if (mounted) {
        setState(() => _submitting = false);
        showOpenHandErrorSnack(
          context,
          controller.errorMessage ??
              text(zh: '保存扫描参数失败。', en: 'Failed to save scan settings.'),
        );
      }
      return;
    }
    await controller.startScan(
      AiExposureScanRequest(
        name: _name.text.trim(),
        sources: _sources,
        mode: _mode,
        authorizedScope: scope,
        authorizationConfirmed: true,
        targets: targets,
        vendors: _vendors.toList(growable: false),
        validationMode: _validationMode,
        forumFetchMode: _forumFetchMode,
        concurrency: _concurrency.round(),
        gptAssisted: _gptAssisted,
        sourceQueries: <String, String>{
          if (_fofaQuery.text.trim().isNotEmpty) 'fofa': _fofaQuery.text.trim(),
          if (_shodanQuery.text.trim().isNotEmpty)
            'shodan': _shodanQuery.text.trim(),
          if (_githubQuery.text.trim().isNotEmpty)
            'github': _githubQuery.text.trim(),
          if (_giteeQuery.text.trim().isNotEmpty)
            'gitee': _giteeQuery.text.trim(),
          if (_gitcodeQuery.text.trim().isNotEmpty)
            'gitcode': _gitcodeQuery.text.trim(),
          if (_nodeseekQuery.text.trim().isNotEmpty)
            'nodeseek': _nodeseekQuery.text.trim(),
          if (_linuxDoQuery.text.trim().isNotEmpty)
            'linux_do': _linuxDoQuery.text.trim(),
          if (_v2exQuery.text.trim().isNotEmpty) 'v2ex': _v2exQuery.text.trim(),
        },
      ),
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (controller.errorMessage == null) Navigator.of(context).pop();
  }
}

class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog();

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    return Consumer<ServicesController>(
      builder: (context, controller, _) {
        final progress = controller.progress;
        return _DialogFrame(
          icon: Icons.track_changes_rounded,
          title: text(zh: '实时扫描', en: 'Live scan'),
          scrollable: false,
          footer: _DialogActions(
            actions: [
              if (progress == null || !progress.isRunning)
                OpenHandDialogActionButton.primary(
                  icon: Icons.add_rounded,
                  onPressed: controller.isRunning
                      ? () => showAiExposureNewHuntDialog(context)
                      : null,
                  label: text(zh: '新建狩猎', en: 'New hunt'),
                )
              else
                OpenHandDialogActionButton.destructive(
                  icon: Icons.stop_rounded,
                  onPressed: controller.stopScan,
                  label: text(zh: '停止扫描', en: 'Stop scan'),
                ),
            ],
          ),
          child: progress == null
              ? Center(
                  child: _EmptyState(
                    icon: Icons.radar_outlined,
                    title: text(zh: '暂无实时任务', en: 'No active scan'),
                    body: text(
                      zh: '创建狩猎任务后，这里会显示阶段、计数和 SSE 日志。',
                      en: 'Create a hunt to view stages, counters, and SSE logs.',
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _MetricGrid(
                      items: [
                        _MetricData(
                          icon: Icons.route_outlined,
                          label: text(zh: '阶段', en: 'Stage'),
                          value: _stageLabel(context, progress.stage),
                        ),
                        _MetricData(
                          icon: Icons.ads_click_rounded,
                          label: text(zh: '命中数', en: 'Discovered'),
                          value: '${progress.discovered}',
                        ),
                        _MetricData(
                          icon: Icons.filter_alt_outlined,
                          label: text(zh: '候选数', en: 'Candidates'),
                          value: '${progress.candidates}',
                        ),
                        _MetricData(
                          icon: Icons.verified_outlined,
                          label: text(zh: '有效数', en: 'Valid'),
                          value: '${progress.valid}',
                        ),
                        _MetricData(
                          icon: Icons.workspace_premium_outlined,
                          label: text(zh: '高价值数', en: 'High value'),
                          value: '${progress.highValue}',
                        ),
                      ],
                    ),
                    const SizedBox(height: _kSectionGap),
                    Text(progress.message),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: kOpenHandPillBorderRadius,
                      child: LinearProgressIndicator(
                        value: progress.total <= 0 ? null : progress.fraction,
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: _kSectionGap),
                    _SectionTitle(
                      icon: Icons.terminal_rounded,
                      title: text(zh: 'SSE 日志', en: 'SSE logs'),
                    ),
                    const SizedBox(height: _kItemGap),
                    Expanded(child: _LogList(logs: controller.logs)),
                  ],
                ),
        );
      },
    );
  }
}

class _ResultsDialog extends StatefulWidget {
  const _ResultsDialog();

  @override
  State<_ResultsDialog> createState() => _ResultsDialogState();
}

class _ResultsDialogState extends State<_ResultsDialog> {
  AiExposureResultCategory? _category;

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    return Consumer<ServicesController>(
      builder: (context, controller, _) {
        final results = controller.results
            .where(
              (result) => _category == null || result.category == _category,
            )
            .toList(growable: false);
        final filters = <Widget>[
          _CategoryChip(
            label: text(zh: '全部', en: 'All'),
            count: controller.results.length,
            selected: _category == null,
            onSelected: () => setState(() => _category = null),
          ),
          for (final category in AiExposureResultCategory.values)
            _CategoryChip(
              label: _categoryLabel(context, category),
              count: controller.results
                  .where((result) => result.category == category)
                  .length,
              selected: _category == category,
              onSelected: () => setState(() => _category = category),
            ),
        ];
        return _DialogFrame(
          icon: Icons.fact_check_outlined,
          title: text(zh: '结果中心', en: 'Results'),
          scrollable: false,
          footer: _DialogActions(
            actions: [
              OpenHandDialogActionButton.secondary(
                icon: Icons.refresh_rounded,
                onPressed: controller.isRunning ? controller.refreshData : null,
                label: text(zh: '刷新', en: 'Refresh'),
              ),
              OpenHandDialogActionButton.primary(
                icon: Icons.download_rounded,
                onPressed: results.isEmpty
                    ? null
                    : () => _exportResults(context, results),
                label: text(zh: '导出', en: 'Export'),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: openHandDialogAwareScrollPhysics(context),
                child: Row(
                  children: [
                    for (var index = 0; index < filters.length; index++) ...[
                      if (index > 0) const SizedBox(width: 8),
                      filters[index],
                    ],
                  ],
                ),
              ),
              const SizedBox(height: _kSectionGap),
              Expanded(
                child: results.isEmpty
                    ? _EmptyState(
                        icon: Icons.search_off_rounded,
                        title: text(zh: '暂无结果', en: 'No results'),
                        body: text(
                          zh: '当前分类还没有扫描结果。',
                          en: 'No scan results in this category.',
                        ),
                      )
                    : ListView.separated(
                        itemCount: results.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) =>
                            _ResultTile(result: results[index]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HistoryDialog extends StatelessWidget {
  const _HistoryDialog();

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    return Consumer<ServicesController>(
      builder: (context, controller, _) => _DialogFrame(
        icon: Icons.history_rounded,
        title: text(zh: '扫描历史', en: 'Scan history'),
        scrollable: false,
        footer: _DialogActions(
          actions: [
            OpenHandDialogActionButton.secondary(
              icon: Icons.refresh_rounded,
              onPressed: controller.isRunning ? controller.refreshData : null,
              label: text(zh: '刷新', en: 'Refresh'),
            ),
          ],
        ),
        child: controller.history.isEmpty
            ? _EmptyState(
                icon: Icons.history_toggle_off_rounded,
                title: text(zh: '暂无历史', en: 'No history'),
                body: text(
                  zh: '完成或中断的扫描任务会保存在这里。',
                  en: 'Completed and interrupted scans appear here.',
                ),
              )
            : ListView.separated(
                itemCount: controller.history.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final entry = controller.history[index];
                  return _HistoryTile(
                    entry: entry,
                    onResume:
                        entry.isResumable &&
                            controller.isRunning &&
                            !controller.scanBusy &&
                            !controller.hasActiveScan
                        ? () => controller.resumeHistory(entry.id)
                        : null,
                    onDelete: () =>
                        _confirmDeleteHistory(context, controller, entry),
                    onLogs: () => _showHistoryLogs(context, entry),
                    onExport: () => _exportResults(
                      context,
                      controller.results
                          .where((result) => result.jobId == entry.id)
                          .toList(growable: false),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _ToolsDialog extends StatefulWidget {
  const _ToolsDialog();

  @override
  State<_ToolsDialog> createState() => _ToolsDialogState();
}

class _ToolsDialogState extends State<_ToolsDialog> {
  final TextEditingController _githubToken = TextEditingController();
  final TextEditingController _giteeToken = TextEditingController();
  final TextEditingController _gitcodeToken = TextEditingController();
  final TextEditingController _fofaEmail = TextEditingController();
  final TextEditingController _fofaKey = TextEditingController();
  final TextEditingController _shodanKey = TextEditingController();
  late Set<AiExposureSource> _enabledSources;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _enabledSources = Set.of(context.read<ServicesController>().enabledSources);
  }

  @override
  void dispose() {
    _githubToken.dispose();
    _giteeToken.dispose();
    _gitcodeToken.dispose();
    _fofaEmail.dispose();
    _fofaKey.dispose();
    _shodanKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    final controller = context.watch<ServicesController>();
    return _DialogFrame(
      icon: Icons.construction_rounded,
      title: text(zh: '扫描工具管理', en: 'Scanner tools'),
      footer: _DialogActions(
        actions: [
          OpenHandDialogActionButton.secondary(
            icon: Icons.data_usage_rounded,
            onPressed: controller.isRunning
                ? controller.refreshServiceStatus
                : null,
            label: text(zh: '检查配额', en: 'Check quotas'),
          ),
          OpenHandDialogActionButton.primary(
            icon: Icons.save_rounded,
            onPressed: controller.isRunning && !_saving ? _save : null,
            label: openHandSaveLabel(context),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final source in AiExposureSource.values) ...[
            _SourceSwitch(
              source: source,
              enabled: _enabledSources.contains(source),
              configured:
                  source == AiExposureSource.manual ||
                  controller.sourceStatus[_sourceStatusKey(source)] == true,
              onChanged: (enabled) => setState(() {
                if (enabled) {
                  _enabledSources.add(source);
                } else {
                  _enabledSources.remove(source);
                }
              }),
            ),
            if (source != AiExposureSource.values.last)
              const SizedBox(height: 8),
          ],
          const SizedBox(height: _kSectionGap),
          _SectionTitle(
            icon: Icons.key_outlined,
            title: text(zh: 'BYOK 凭证', en: 'BYOK credentials'),
          ),
          const SizedBox(height: _kItemGap),
          TextField(
            controller: _githubToken,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'GitHub Token',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _giteeToken,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Gitee Access Token',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _gitcodeToken,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'GitCode Access Token',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _fofaEmail,
            decoration: const InputDecoration(
              labelText: 'FOFA Email',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _fofaKey,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'FOFA API Key',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _shodanKey,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Shodan API Key',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: _kSectionGap),
          _InlineNotice(
            icon: Icons.security_rounded,
            text: text(
              zh: '凭证只写入当前 ai_jungler 进程内存，不进入日志；服务停止后自动清除。',
              en: 'Credentials stay in ai_jungler process memory, never enter logs, and are cleared when it stops.',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final controller = context.read<ServicesController>();
    final preferencesUpdated = await controller.updateScanPreferences(
      enabledSources: _enabledSources,
      concurrency: controller.defaultConcurrency,
      validationMode: controller.defaultValidationMode,
      forumFetchMode: controller.forumFetchMode,
      gptAssisted: controller.defaultGptAssisted,
    );
    if (!preferencesUpdated) {
      if (mounted) {
        setState(() => _saving = false);
        showOpenHandErrorSnack(
          context,
          controller.errorMessage ?? '保存扫描工具设置失败。',
        );
      }
      return;
    }
    await controller.updateSourceCredentials(
      githubToken: _githubToken.text,
      giteeToken: _giteeToken.text,
      gitcodeToken: _gitcodeToken.text,
      fofaEmail: _fofaEmail.text,
      fofaKey: _fofaKey.text,
      shodanKey: _shodanKey.text,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (controller.errorMessage == null) {
      showOpenHandSuccessSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '扫描工具设置已更新。',
          en: 'Scanner tool settings updated.',
        ),
      );
    }
  }
}

class _RulesDialog extends StatefulWidget {
  const _RulesDialog();

  @override
  State<_RulesDialog> createState() => _RulesDialogState();
}

class _RulesDialogState extends State<_RulesDialog> {
  late List<AiExposureScanRule> _rules;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _rules = List.of(context.read<ServicesController>().rules);
  }

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    final controller = context.watch<ServicesController>();
    return _DialogFrame(
      icon: Icons.rule_rounded,
      title: text(zh: '扫描规则管理', en: 'Scan rules'),
      scrollable: false,
      footer: _DialogActions(
        actions: [
          OpenHandDialogActionButton.secondary(
            icon: Icons.add_rounded,
            onPressed: () => _editRule(null),
            label: text(zh: '新增规则', en: 'Add rule'),
          ),
          OpenHandDialogActionButton.primary(
            icon: Icons.save_rounded,
            onPressed: controller.isRunning && !_saving ? _save : null,
            label: openHandSaveLabel(context),
          ),
        ],
      ),
      child: _rules.isEmpty
          ? _EmptyState(
              icon: Icons.rule_folder_outlined,
              title: text(zh: '暂无规则', en: 'No rules'),
              body: text(
                zh: '新增凭证正则和上下文规则后再开始扫描。',
                en: 'Add credential and context rules before scanning.',
              ),
            )
          : ListView.separated(
              itemCount: _rules.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final rule = _rules[index];
                return _RuleTile(
                  rule: rule,
                  onToggle: (enabled) => setState(() {
                    _rules[index] = rule.copyWith(enabled: enabled);
                  }),
                  onEdit: () => _editRule(index),
                  onDelete: () => setState(() => _rules.removeAt(index)),
                );
              },
            ),
    );
  }

  Future<void> _editRule(int? index) async {
    final updated = await _showRuleEditor(
      context,
      initial: index == null ? null : _rules[index],
    );
    if (!mounted || updated == null) return;
    setState(() {
      if (index == null) {
        _rules.add(updated);
      } else {
        _rules[index] = updated;
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final controller = context.read<ServicesController>();
    await controller.saveRules(_rules);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _rules = List.of(controller.rules);
    });
  }
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog();

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final TextEditingController _address;
  final TextEditingController _token = TextEditingController();
  late bool _bundled;
  late bool _postgresqlEnabled;
  late bool _redisEnabled;
  late double _concurrency;
  late bool _activeValidation;
  late AiExposureForumFetchMode _forumFetchMode;
  late bool _gptAssisted;
  bool _applying = false;
  String? _dependencyOperationId;

  @override
  void initState() {
    super.initState();
    final controller = context.read<ServicesController>();
    _address = TextEditingController(text: controller.externalAddress);
    _bundled = controller.useBundledEngine;
    _postgresqlEnabled = controller.postgresqlEnabled;
    _redisEnabled = controller.redisEnabled;
    _concurrency = controller.defaultConcurrency.toDouble();
    _activeValidation =
        controller.defaultValidationMode ==
        AiExposureValidationMode.authorizedActive;
    _forumFetchMode = controller.forumFetchMode;
    _gptAssisted = controller.defaultGptAssisted;
  }

  @override
  void dispose() {
    _address.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    final controller = context.watch<ServicesController>();
    final pluginController = context.watch<PluginServiceController>();
    return _DialogFrame(
      icon: Icons.settings_outlined,
      title: text(zh: '服务设置', en: 'Service settings'),
      footer: _DialogActions(
        actions: [
          OpenHandDialogActionButton.secondary(
            icon: Icons.refresh_rounded,
            onPressed: controller.isRunning && !_applying
                ? controller.refreshServiceStatus
                : null,
            label: text(zh: '刷新 API 状态', en: 'Refresh API status'),
          ),
          OpenHandDialogActionButton.primary(
            icon: Icons.link_rounded,
            onPressed: controller.busy || _applying ? null : _apply,
            label: text(zh: '应用设置', en: 'Apply settings'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: true,
                icon: const Icon(Icons.inventory_2_outlined),
                label: Text(text(zh: '内嵌引擎', en: 'Bundled engine')),
              ),
              ButtonSegment(
                value: false,
                icon: const Icon(Icons.dns_outlined),
                label: Text(text(zh: '外部服务', en: 'External service')),
              ),
            ],
            selected: <bool>{_bundled},
            onSelectionChanged: (selection) =>
                setState(() => _bundled = selection.first),
          ),
          OpenHandVerticalRevealSwitcher(
            presentKey: const ValueKey<String>('external-service-fields'),
            slideBeginOffsetY: -.03,
            child: _bundled
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: _kSectionGap),
                    child: Column(
                      children: [
                        TextField(
                          controller: _address,
                          decoration: InputDecoration(
                            labelText: text(zh: '服务地址', en: 'Service address'),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _token,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: text(zh: '访问令牌', en: 'Access token'),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: _kSectionGap),
          _SectionTitle(
            icon: Icons.api_rounded,
            title: text(zh: '源 API 状态', en: 'Source API status'),
          ),
          const SizedBox(height: _kItemGap),
          for (final source in _kCredentialSources) ...[
            _SourceApiStatusRow(
              source: source,
              configured:
                  controller.sourceStatus[_sourceStatusKey(source)] == true,
              quota: _sourceQuota(controller.quotas, source),
            ),
            if (source != _kCredentialSources.last) const SizedBox(height: 8),
          ],
          const SizedBox(height: _kSectionGap),
          _SectionTitle(
            icon: Icons.language_rounded,
            title: text(zh: '论坛读取通道', en: 'Forum reader route'),
          ),
          const SizedBox(height: _kItemGap),
          SegmentedButton<AiExposureForumFetchMode>(
            segments: [
              ButtonSegment(
                value: AiExposureForumFetchMode.jinaFallback,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: Text(text(zh: 'Jina 优先降级', en: 'Jina with fallback')),
              ),
              ButtonSegment(
                value: AiExposureForumFetchMode.playwright,
                icon: const Icon(Icons.language_rounded),
                label: Text(text(zh: 'Playwright 直读', en: 'Playwright direct')),
              ),
            ],
            selected: <AiExposureForumFetchMode>{_forumFetchMode},
            onSelectionChanged: (selection) =>
                setState(() => _forumFetchMode = selection.first),
          ),
          const SizedBox(height: _kItemGap),
          _PlaywrightDependencyTile(
            plugin: pluginController.pluginById(PluginCatalogIds.playwright),
            runtimeStatus: controller.dependencyStatus?.playwright,
            operating: _dependencyOperationId == PluginCatalogIds.playwright,
            onAction: _runPlaywrightAction,
          ),
          const SizedBox(height: 8),
          _InlineNotice(
            icon: Icons.lan_outlined,
            text: text(
              zh: 'Jina Reader 与 Playwright 均遵循网络代理和代理池配置，浏览器并发与页面等待均有硬上限。',
              en: 'Jina Reader and Playwright both follow the proxy pool, with bounded browser concurrency and page timeouts.',
            ),
          ),
          const SizedBox(height: _kSectionGap),
          _SectionTitle(
            icon: Icons.extension_outlined,
            title: text(zh: '可选运行依赖', en: 'Optional dependencies'),
          ),
          const SizedBox(height: _kItemGap),
          _ManagedDependencyTile(
            plugin: pluginController.pluginById(PluginCatalogIds.postgresql),
            icon: Icons.storage_rounded,
            title: 'PostgreSQL',
            purpose: text(
              zh: '持久化任务、结果、日志和增量目标。',
              en: 'Persist jobs, results, logs, and incremental targets.',
            ),
            selected: _postgresqlEnabled,
            operating: _dependencyOperationId == PluginCatalogIds.postgresql,
            onSelected: (value) => setState(() => _postgresqlEnabled = value),
            onAction: (action) =>
                _runDependencyAction(PluginCatalogIds.postgresql, action),
          ),
          const SizedBox(height: _kItemGap),
          _ManagedDependencyTile(
            plugin: pluginController.pluginById(PluginCatalogIds.redis),
            icon: Icons.hub_rounded,
            title: 'Redis',
            purpose: text(
              zh: '协调多实例目标租约并减少重复扫描。',
              en: 'Coordinate target leases across scanner instances.',
            ),
            selected: _redisEnabled,
            operating: _dependencyOperationId == PluginCatalogIds.redis,
            onSelected: (value) => setState(() => _redisEnabled = value),
            onAction: (action) =>
                _runDependencyAction(PluginCatalogIds.redis, action),
          ),
          const SizedBox(height: _kSectionGap),
          _SectionTitle(
            icon: Icons.speed_rounded,
            title: text(zh: '并发与安全策略', en: 'Concurrency and safety'),
          ),
          const SizedBox(height: _kItemGap),
          Row(
            children: [
              Expanded(
                child: Text(text(zh: '默认并发数', en: 'Default concurrency')),
              ),
              Text('${_concurrency.round()}'),
            ],
          ),
          Slider(
            value: _concurrency,
            min: 1,
            max: 128,
            divisions: 127,
            onChanged: (value) => setState(() => _concurrency = value),
          ),
          OpenHandAnimatedSwitchTile(
            icon: Icons.verified_user_outlined,
            disabledIcon: Icons.visibility_outlined,
            title: text(
              zh: '默认启用授权主动验证',
              en: 'Default to authorized validation',
            ),
            description: text(
              zh: '关闭时仅做被动探测；每次新建任务仍可单独调整。',
              en: 'Off uses passive probing; each hunt can override this setting.',
            ),
            value: _activeValidation,
            onChanged: (value) => setState(() => _activeValidation = value),
          ),
          const SizedBox(height: _kItemGap),
          OpenHandAnimatedSwitchTile(
            icon: Icons.auto_awesome_rounded,
            disabledIcon: Icons.auto_awesome_outlined,
            title: text(
              zh: '默认启用 GPT 辅助提取',
              en: 'Default to GPT-assisted extraction',
            ),
            description: controller.selectedAiExtractorModelLabel == null
                ? text(
                    zh: '全局设置中尚未选择 OpenAI Compatible 模型。',
                    en: 'No OpenAI-compatible model is selected globally.',
                  )
                : controller.selectedAiExtractorModelLabel!,
            value: _gptAssisted,
            onChanged: (value) {
              if (value && controller.selectedAiExtractorModelLabel == null) {
                showOpenHandErrorSnack(
                  context,
                  text(
                    zh: '请先配置 OpenAI Compatible 模型。',
                    en: 'Configure an OpenAI-compatible model first.',
                  ),
                );
                return;
              }
              setState(() => _gptAssisted = value);
            },
          ),
          const SizedBox(height: _kSectionGap),
          _InlineNotice(
            icon: Icons.lock_outline_rounded,
            text: text(
              zh: '服务仅接受声明授权范围内的 HTTP/HTTPS 目标；原始凭证加密保存且界面始终打码。',
              en: 'Only declared HTTP/HTTPS targets are accepted; raw credentials are encrypted and always masked in the UI.',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _apply() async {
    setState(() => _applying = true);
    final text = openHandTextResolver(context);
    final controller = context.read<ServicesController>();
    final pluginController = context.read<PluginServiceController>();
    try {
      final scanPreferencesUpdated = await controller.updateScanPreferences(
        enabledSources: controller.enabledSources,
        concurrency: _concurrency.round(),
        validationMode: _activeValidation
            ? AiExposureValidationMode.authorizedActive
            : AiExposureValidationMode.passive,
        forumFetchMode: _forumFetchMode,
        gptAssisted: _gptAssisted,
      );
      if (!scanPreferencesUpdated) {
        if (mounted) {
          showOpenHandErrorSnack(
            context,
            controller.errorMessage ??
                text(zh: '保存扫描参数失败。', en: 'Failed to save scan settings.'),
          );
        }
        return;
      }
      if (_bundled) {
        final runtimePreferencesUpdated = await controller
            .updateRuntimePreferences(
              useBundledEngine: true,
              externalAddress: _address.text,
            );
        if (!runtimePreferencesUpdated) {
          if (mounted) {
            showOpenHandErrorSnack(
              context,
              controller.errorMessage ??
                  text(
                    zh: '保存扫描运行模式失败。',
                    en: 'Failed to save scanner runtime mode.',
                  ),
            );
          }
          return;
        }
        if (!controller.isRunning || !controller.ownsProcess) {
          if (controller.isRunning) await controller.stopService();
          await controller.startService();
        }
        if (!controller.isRunning || !controller.ownsProcess) {
          if (mounted) {
            showOpenHandErrorSnack(
              context,
              controller.errorMessage ??
                  text(
                    zh: '内嵌扫描引擎启动失败。',
                    en: 'Bundled scanner failed to start.',
                  ),
            );
          }
          return;
        }
      } else {
        final reconnect =
            !controller.isRunning ||
            controller.ownsProcess ||
            !controller.isConnectedToExternalAddress(_address.text) ||
            _token.text.trim().isNotEmpty;
        if (reconnect) {
          final connected = await controller.connectExternal(
            address: _address.text,
            accessToken: _token.text,
          );
          if (!connected ||
              !controller.isConnectedToExternalAddress(_address.text)) {
            if (mounted) {
              showOpenHandErrorSnack(
                context,
                controller.errorMessage ??
                    text(
                      zh: '外部扫描服务连接失败。',
                      en: 'External scanner connection failed.',
                    ),
              );
            }
            return;
          }
        }
        final runtimePreferencesUpdated = await controller
            .updateRuntimePreferences(
              useBundledEngine: false,
              externalAddress: _address.text,
            );
        if (!runtimePreferencesUpdated) {
          if (mounted) {
            showOpenHandErrorSnack(
              context,
              controller.errorMessage ??
                  text(
                    zh: '保存扫描运行模式失败。',
                    en: 'Failed to save scanner runtime mode.',
                  ),
            );
          }
          return;
        }
      }

      if (_postgresqlEnabled) {
        await _ensureManagedDependency(
          pluginController,
          PluginCatalogIds.postgresql,
        );
      }
      if (_redisEnabled) {
        await _ensureManagedDependency(
          pluginController,
          PluginCatalogIds.redis,
        );
      }
      final updated = await controller.updateManagedDependencyPreferences(
        postgresqlEnabled: _postgresqlEnabled,
        redisEnabled: _redisEnabled,
      );
      if (!updated) {
        if (mounted) {
          showOpenHandErrorSnack(
            context,
            controller.errorMessage ??
                text(zh: '运行依赖更新失败。', en: 'Dependency update failed.'),
          );
        }
        return;
      }
      if (!mounted) return;
      Navigator.of(context).maybePop();
    } catch (error) {
      if (mounted) showOpenHandErrorSnack(context, '$error');
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<void> _ensureManagedDependency(
    PluginServiceController pluginController,
    String pluginId,
  ) async {
    final plugin = pluginController.pluginById(pluginId);
    final name = plugin?.name ?? pluginId;
    if (plugin == null) {
      throw StateError('$name 状态尚未加载，请稍后重试。');
    }
    if (!plugin.supportsInstall) {
      throw StateError('$name 是外部实例，无法作为 OpenHand 托管运行依赖。');
    }
    if (!plugin.isInstalled) {
      final installed = await pluginController.installPlugin(pluginId);
      if (!installed) {
        throw StateError(pluginController.errorMessage ?? '$name 安装失败。');
      }
    }
    final refreshed = pluginController.pluginById(pluginId);
    if (refreshed?.enabled == true) return;
    final started = await pluginController.toggleManagedRuntime(
      pluginId,
      enabled: true,
    );
    if (!started) {
      throw StateError(pluginController.errorMessage ?? '$name 启动失败。');
    }
  }

  Future<void> _runPlaywrightAction() async {
    if (_applying || _dependencyOperationId != null) return;
    final pluginController = context.read<PluginServiceController>();
    final playwright = pluginController.pluginById(PluginCatalogIds.playwright);
    if (playwright == null) return;
    setState(() => _dependencyOperationId = PluginCatalogIds.playwright);
    var success = true;
    final node = pluginController.pluginById(PluginCatalogIds.nodejs);
    if (node?.isInstalled != true) {
      success = await pluginController.installPlugin(PluginCatalogIds.nodejs);
    }
    if (success) {
      if (playwright.isInstalled) {
        if (playwright.hasUpdate) {
          success = await pluginController.updatePlugin(
            PluginCatalogIds.playwright,
          );
        }
      } else {
        success = await pluginController.installPlugin(
          PluginCatalogIds.playwright,
        );
      }
    }
    if (!mounted) return;
    flashOpenHandSnack(
      context,
      success
          ? 'Playwright 浏览器通道已就绪'
          : pluginController.errorMessage ?? 'Playwright 浏览器通道准备失败',
      kind: success ? OpenHandSnackKind.success : OpenHandSnackKind.error,
    );
    setState(() => _dependencyOperationId = null);
  }

  Future<void> _runDependencyAction(
    String pluginId,
    _ManagedDependencyAction action,
  ) async {
    if (_applying || _dependencyOperationId != null) return;
    final pluginController = context.read<PluginServiceController>();
    final plugin = pluginController.pluginById(pluginId);
    if (plugin == null) return;
    if (action == _ManagedDependencyAction.uninstall) {
      final confirmed = await showOpenHandConfirmDialog(
        context: context,
        title: '卸载 ${plugin.name}',
        message: '将移除 OpenHand 托管容器并保留数据目录。',
        cancelLabel: '取消',
        confirmLabel: '卸载',
        destructive: true,
      );
      if (!confirmed || !mounted) return;
    }
    setState(() => _dependencyOperationId = pluginId);
    var success = switch (action) {
      _ManagedDependencyAction.install => await pluginController.installPlugin(
        pluginId,
      ),
      _ManagedDependencyAction.start =>
        await pluginController.toggleManagedRuntime(pluginId, enabled: true),
      _ManagedDependencyAction.stop =>
        await pluginController.toggleManagedRuntime(pluginId, enabled: false),
      _ManagedDependencyAction.update => await pluginController.updatePlugin(
        pluginId,
      ),
      _ManagedDependencyAction.uninstall =>
        await pluginController.uninstallPlugin(pluginId),
    };
    if (!mounted) return;
    String? preferenceError;
    if (success &&
        (action == _ManagedDependencyAction.stop ||
            action == _ManagedDependencyAction.uninstall)) {
      setState(() {
        if (pluginId == PluginCatalogIds.postgresql) {
          _postgresqlEnabled = false;
        } else {
          _redisEnabled = false;
        }
      });
      final servicesController = context.read<ServicesController>();
      final updated = await servicesController
          .updateManagedDependencyPreferences(
            postgresqlEnabled: _postgresqlEnabled,
            redisEnabled: _redisEnabled,
          );
      if (!updated) {
        success = false;
        preferenceError = servicesController.errorMessage;
        if (mounted) {
          setState(() {
            if (pluginId == PluginCatalogIds.postgresql) {
              _postgresqlEnabled = true;
            } else {
              _redisEnabled = true;
            }
          });
        }
      }
    }
    if (!mounted) return;
    flashOpenHandSnack(
      context,
      success
          ? '${action.label} ${plugin.name}成功'
          : preferenceError ??
                pluginController.errorMessage ??
                '${action.label} ${plugin.name}失败',
      kind: success ? OpenHandSnackKind.success : OpenHandSnackKind.error,
    );
    setState(() => _dependencyOperationId = null);
  }
}

enum _ManagedDependencyAction { install, start, stop, update, uninstall }

extension on _ManagedDependencyAction {
  String get label => switch (this) {
    _ManagedDependencyAction.install => '安装',
    _ManagedDependencyAction.start => '启动',
    _ManagedDependencyAction.stop => '停止',
    _ManagedDependencyAction.update => '升级',
    _ManagedDependencyAction.uninstall => '卸载',
  };
}

class _PlaywrightDependencyTile extends StatelessWidget {
  const _PlaywrightDependencyTile({
    required this.plugin,
    required this.runtimeStatus,
    required this.operating,
    required this.onAction,
  });

  final PluginInfo? plugin;
  final AiExposureDependencyComponentStatus? runtimeStatus;
  final bool operating;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final installed = plugin?.isInstalled == true;
    final ready = runtimeStatus?.connected == true;
    final canAct =
        !operating && plugin != null && (!installed || plugin!.hasUpdate);
    final tone = ready
        ? OpenHandStatusColors.success
        : installed
        ? OpenHandStatusColors.warning
        : colors.outline;
    final detail = operating
        ? '正在准备 Playwright 浏览器通道…'
        : runtimeStatus?.message.trim().isNotEmpty == true
        ? runtimeStatus!.message
        : installed
        ? 'Playwright 已安装，启动内嵌引擎后自动接入。'
        : '未安装 Playwright 浏览器依赖。';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .65)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.language_rounded, color: tone, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Playwright',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          IconButton.filledTonal(
            tooltip: installed ? '更新 Playwright' : '安装 Playwright',
            onPressed: canAct ? onAction : null,
            icon: operating
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    installed
                        ? Icons.system_update_alt_rounded
                        : Icons.download_rounded,
                    size: 19,
                  ),
          ),
        ],
      ),
    );
  }
}

class _ManagedDependencyTile extends StatelessWidget {
  const _ManagedDependencyTile({
    required this.plugin,
    required this.icon,
    required this.title,
    required this.purpose,
    required this.selected,
    required this.operating,
    required this.onSelected,
    required this.onAction,
  });

  final PluginInfo? plugin;
  final IconData icon;
  final String title;
  final String purpose;
  final bool selected;
  final bool operating;
  final ValueChanged<bool> onSelected;
  final ValueChanged<_ManagedDependencyAction> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isBusy = operating || plugin?.isBusy == true;
    final installed = plugin?.isInstalled == true;
    final running = installed && plugin!.enabled;
    final statusColor = isBusy
        ? colors.tertiary
        : running
        ? const Color(0xff2e7d5b)
        : installed
        ? const Color(0xffb26a00)
        : plugin?.status == PluginStatus.error
        ? colors.error
        : colors.onSurfaceVariant;
    final statusText = isBusy
        ? '正在执行依赖操作…'
        : plugin == null
        ? '正在同步插件状态…'
        : running
        ? 'OpenHand 托管实例已安装并运行'
        : installed
        ? 'OpenHand 托管实例已安装，当前已停止'
        : plugin!.status == PluginStatus.error
        ? plugin!.errorMessage ?? '依赖状态异常'
        : '未安装，启用后将按预置参数自动安装';

    Widget actionButton(
      _ManagedDependencyAction action,
      IconData actionIcon, {
      bool destructive = false,
    }) {
      return IconButton.filledTonal(
        tooltip: '${action.label} $title',
        onPressed: isBusy ? null : () => onAction(action),
        style: destructive
            ? IconButton.styleFrom(foregroundColor: colors.error)
            : null,
        icon: Icon(actionIcon, size: 18),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: colors.onPrimaryContainer, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      purpose,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Switch(value: selected, onChanged: isBusy ? null : onSelected),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.circle, size: 9, color: statusColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  statusText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: statusColor,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              if (isBusy)
                const SizedBox.square(
                  dimension: 34,
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    if (plugin?.status == PluginStatus.notInstalled &&
                        plugin?.supportsInstall == true)
                      actionButton(
                        _ManagedDependencyAction.install,
                        Icons.download_rounded,
                      ),
                    if (installed &&
                        plugin!.metadata['runtime_managed'] == true)
                      actionButton(
                        running
                            ? _ManagedDependencyAction.stop
                            : _ManagedDependencyAction.start,
                        running
                            ? Icons.stop_circle_outlined
                            : Icons.play_circle_outline_rounded,
                      ),
                    if (installed &&
                        plugin!.supportsInstall &&
                        plugin!.hasUpdate)
                      actionButton(
                        _ManagedDependencyAction.update,
                        Icons.system_update_alt_rounded,
                      ),
                    if (installed && plugin!.supportsUninstall)
                      actionButton(
                        _ManagedDependencyAction.uninstall,
                        Icons.delete_outline_rounded,
                        destructive: true,
                      ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DialogFrame extends StatelessWidget {
  const _DialogFrame({
    required this.icon,
    required this.title,
    required this.child,
    this.subtitle,
    this.footer,
    this.scrollable = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? footer;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: _kDialogPadding,
      child: Column(
        mainAxisSize: scrollable ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
                ),
                child: Icon(icon, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (subtitle?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ServiceDialogHeaderIconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 1,
            color: cs.outlineVariant.withValues(alpha: 0.75),
          ),
          const SizedBox(height: _kSectionGap),
          Flexible(
            child: scrollable
                ? SingleChildScrollView(
                    physics: openHandDialogAwareScrollPhysics(context),
                    child: child,
                  )
                : child,
          ),
          if (footer != null) ...[
            const SizedBox(height: _kSectionGap),
            footer!,
          ],
        ],
      ),
    );
  }
}

class _DialogActions extends StatelessWidget {
  const _DialogActions({required this.actions});
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    spacing: kOpenHandDialogActionSpacing,
    runSpacing: kOpenHandDialogActionSpacing,
    children: actions,
  );
}

class _MetricData {
  const _MetricData({
    required this.icon,
    required this.label,
    required this.value,
    this.detail,
    this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final String? detail;
  final Color? color;
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.items});
  final List<_MetricData> items;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 1020
          ? 4
          : constraints.maxWidth >= _kMetricBreakpoint
          ? 3
          : constraints.maxWidth >= 420
          ? 2
          : 1;
      final width =
          (constraints.maxWidth - _kItemGap * (columns - 1)) / columns;
      return Wrap(
        spacing: _kItemGap,
        runSpacing: _kItemGap,
        children: items
            .map(
              (item) => SizedBox(
                width: width,
                child: _MetricTile(data: item),
              ),
            )
            .toList(growable: false),
      );
    },
  );
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.data});
  final _MetricData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tone = data.color ?? _serviceMetricTone(data.icon, cs);
    return Container(
      constraints: const BoxConstraints(minHeight: 106),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tone.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(data.icon, size: 19, color: tone),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  data.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  data.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (data.detail?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 2),
                  Text(
                    data.detail!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: tone),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceTelemetryConsole extends StatelessWidget {
  const _ServiceTelemetryConsole({required this.controller});

  final ServicesController controller;

  @override
  Widget build(BuildContext context) {
    final proxy = controller.proxyStatus;
    final dependencies = controller.dependencyStatus;
    final progress = controller.progress;
    final configuredSources = controller.sourceStatus.values
        .where((configured) => configured)
        .length;
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
            _line(
              'service',
              controller.isRunning ? 'READY' : 'STOPPED',
              controller.isRunning,
            ),
            _line(
              'engine',
              'ai_jungler ${controller.health?.version ?? '--'} · uptime=${_serviceDuration(controller.health?.uptimeSeconds ?? 0)}',
              controller.isRunning,
            ),
            _line(
              'job',
              progress == null
                  ? 'idle'
                  : '${progress.stage} ${progress.processed}/${progress.total}',
              progress?.isRunning == true,
            ),
            _line(
              'sources',
              '$configuredSources/${controller.discoverySourceCount} configured · enabled=${controller.enabledSources.length}',
              configuredSources > 0,
            ),
            _line(
              'proxy',
              proxy?.enabled == true
                  ? 'endpoints=${proxy!.endpoints.length} selections=${proxy.totalSelections} ok=${proxy.totalSuccesses} failed=${proxy.totalFailures} timeout=${proxy.totalTimeouts} avg=${proxy.averageResponseTimeMs}ms'
                  : 'direct connection',
              proxy?.enabled != true || proxy!.totalFailures == 0,
            ),
            _line(
              'storage',
              'SQLite WAL · PostgreSQL=${dependencies?.postgresql.connected == true ? 'ready' : 'off'} · Redis=${dependencies?.redis.connected == true ? 'ready' : 'off'}',
              controller.isRunning,
            ),
            _line(
              'workload',
              'jobs=${controller.history.length} results=${controller.results.length} rules=${controller.rules.where((rule) => rule.enabled).length}/${controller.rules.length} logs=${controller.logs.length}',
              true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(String name, String value, bool healthy) => Text.rich(
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

class _StatusPanelGrid extends StatelessWidget {
  const _StatusPanelGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 760 ? 2 : 1;
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

class _StatusTrendPanel extends StatelessWidget {
  const _StatusTrendPanel({
    required this.title,
    required this.subtitle,
    required this.series,
  });

  final String title;
  final String subtitle;
  final List<OpenHandChartSeries> series;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      height: 258,
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
              const _StatusSectionIcon(icon: Icons.show_chart_rounded),
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
                valueSuffix: ' 项',
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
                .map(
                  (item) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: item.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(item.label, style: theme.textTheme.labelSmall),
                    ],
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _StatusDistributionItem {
  const _StatusDistributionItem(this.label, this.value, this.color);

  final String label;
  final int value;
  final Color color;
}

class _StatusDistributionPanel extends StatelessWidget {
  const _StatusDistributionPanel({
    required this.title,
    required this.centerValue,
    required this.items,
  });

  final String title;
  final String centerValue;
  final List<_StatusDistributionItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final visible = items.where((item) => item.value > 0).toList();
    final max = visible.fold<int>(
      1,
      (value, item) => item.value > value ? item.value : value,
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 258),
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
              const _StatusSectionIcon(icon: Icons.donut_large_rounded),
              const SizedBox(width: 9),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
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
                  dimension: 110,
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
                                width: 58,
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
                                    value: item.value / max,
                                    minHeight: 7,
                                    color: item.color,
                                    backgroundColor: item.color.withValues(
                                      alpha: 0.1,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${item.value}',
                                style: theme.textTheme.labelLarge,
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(growable: false),
                );
                return constraints.maxWidth < 440
                    ? Column(
                        children: [donut, const SizedBox(height: 12), rows],
                      )
                    : Row(
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

class _StatusSectionCard extends StatelessWidget {
  const _StatusSectionCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
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
              _StatusSectionIcon(icon: icon),
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
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _StatusSectionIcon extends StatelessWidget {
  const _StatusSectionIcon({required this.icon});

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

class _StatusKeyValue extends StatelessWidget {
  const _StatusKeyValue({required this.label, required this.value});

  final String label;
  final String value;

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
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.11),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cs.primary.withValues(alpha: 0.24)),
          ),
          child: Icon(icon, size: 18, color: cs.primary),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

Color _serviceMetricTone(IconData icon, ColorScheme colors) {
  if (icon == Icons.cloud_done_outlined ||
      icon == Icons.check_circle_outline_rounded ||
      icon == Icons.verified_outlined ||
      icon == Icons.fact_check_outlined) {
    return const Color(0xff16a34a);
  }
  if (icon == Icons.error_outline_rounded ||
      icon == Icons.cloud_off_outlined ||
      icon == Icons.warning_amber_rounded) {
    return const Color(0xffdc2626);
  }
  if (icon == Icons.storage_rounded || icon == Icons.dns_outlined) {
    return const Color(0xff0891b2);
  }
  if (icon == Icons.memory_rounded || icon == Icons.speed_rounded) {
    return colors.tertiary;
  }
  return colors.primary;
}

class _DependencyRow extends StatelessWidget {
  const _DependencyRow({
    required this.name,
    required this.detail,
    required this.ready,
    required this.required,
    this.statusLabel,
  });
  final String name;
  final String detail;
  final bool ready;
  final bool required;
  final String? statusLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      children: [
        Icon(
          ready ? Icons.check_circle_outline_rounded : Icons.circle_outlined,
          color: ready ? cs.primary : cs.outline,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: theme.textTheme.titleSmall),
              Text(
                detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Text(
          statusLabel ??
              (required
                  ? openHandLocalizedText(context, zh: '核心', en: 'Core')
                  : openHandLocalizedText(context, zh: '可选', en: 'Optional')),
          style: theme.textTheme.labelMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _QuotaRow extends StatelessWidget {
  const _QuotaRow({required this.quota});
  final AiExposureQuota quota;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = quota.available
        ? cs.primary
        : quota.configured
        ? cs.error
        : cs.outline;
    final value = !quota.configured
        ? openHandLocalizedText(context, zh: '未配置', en: 'Not configured')
        : !quota.available
        ? openHandLocalizedText(context, zh: '异常', en: 'Unavailable')
        : quota.remaining == null
        ? openHandLocalizedText(context, zh: '可用', en: 'Available')
        : quota.limit == null
        ? '${quota.remaining}'
        : '${quota.remaining}/${quota.limit}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(_sourceIcon(quota.source), size: 19, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_sourceLabel(context, quota.source)),
              if (quota.message.trim().isNotEmpty)
                Text(
                  quota.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(value, style: theme.textTheme.labelLarge?.copyWith(color: color)),
      ],
    );
  }
}

class _SourceApiStatusRow extends StatelessWidget {
  const _SourceApiStatusRow({
    required this.source,
    required this.configured,
    required this.quota,
  });

  final AiExposureSource source;
  final bool configured;
  final AiExposureQuota? quota;

  @override
  Widget build(BuildContext context) {
    final available = quota?.available == true;
    final status = !configured
        ? openHandLocalizedText(context, zh: '未配置', en: 'Not configured')
        : quota == null
        ? openHandLocalizedText(context, zh: '待检查', en: 'Not checked')
        : available
        ? openHandLocalizedText(context, zh: '在线', en: 'Online')
        : openHandLocalizedText(context, zh: '异常', en: 'Unavailable');
    final detail = quota?.message.trim();
    return _DependencyRow(
      name: _sourceLabel(context, source),
      detail: detail?.isNotEmpty == true
          ? detail!
          : configured
          ? openHandLocalizedText(
              context,
              zh: '凭证已配置，刷新后检查 API。',
              en: 'Credentials configured; refresh to check the API.',
            )
          : openHandLocalizedText(
              context,
              zh: '尚未配置 BYOK 凭证。',
              en: 'BYOK credentials are not configured.',
            ),
      ready: available,
      required: false,
      statusLabel: status,
    );
  }
}

class _QueryFields extends StatelessWidget {
  const _QueryFields({
    required this.fofa,
    required this.shodan,
    required this.github,
    required this.gitee,
    required this.gitcode,
    required this.nodeseek,
    required this.linuxDo,
    required this.v2ex,
  });
  final TextEditingController fofa;
  final TextEditingController shodan;
  final TextEditingController github;
  final TextEditingController gitee;
  final TextEditingController gitcode;
  final TextEditingController nodeseek;
  final TextEditingController linuxDo;
  final TextEditingController v2ex;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextField(
        controller: fofa,
        decoration: const InputDecoration(
          labelText: 'FOFA Query',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: shodan,
        decoration: const InputDecoration(
          labelText: 'Shodan Query',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: github,
        decoration: const InputDecoration(
          labelText: 'GitHub Code Search Query',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: gitee,
        decoration: const InputDecoration(
          labelText: 'Gitee Code Search Query',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: gitcode,
        decoration: const InputDecoration(
          labelText: 'GitCode Code Search Query',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: nodeseek,
        decoration: const InputDecoration(
          labelText: 'NodeSeek 入口 URL',
          hintText: 'https://www.nodeseek.com/',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: linuxDo,
        decoration: const InputDecoration(
          labelText: 'LINUX DO 入口 URL',
          hintText: 'https://linux.do/c/welfare/36',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: v2ex,
        decoration: const InputDecoration(
          labelText: 'V2EX 入口 URL',
          hintText: 'https://www.v2ex.com/go/openai',
          border: OutlineInputBorder(),
        ),
      ),
    ],
  );
}

class _LogList extends StatelessWidget {
  const _LogList({required this.logs});
  final List<AiExposureLogEntry> logs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (logs.isEmpty) {
      return _EmptyLine(
        text: openHandLocalizedText(
          context,
          zh: '等待扫描事件。',
          en: 'Waiting for scan events.',
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: logs.length,
        itemBuilder: (context, index) {
          final log = logs[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '${_time(log.at)}  ${log.message}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: log.level == 'error' ? cs.error : cs.onSurfaceVariant,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onSelected,
  });
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => ServiceFilterChip(
    selected: selected,
    label: Text('$label $count'),
    onSelected: (_) => onSelected(),
  );
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result});
  final AiExposureResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = _categoryColor(cs, result.category);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Icon(_categoryIcon(result.category), size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      result.product,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      _categoryLabel(context, result.category),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  result.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    Text(result.maskedCredential ?? '--'),
                    Text('Models ${result.modelCount}'),
                    if (result.balanceSummary?.isNotEmpty == true)
                      Text(result.balanceSummary!),
                    if (result.duplicateKeyHosts > 0)
                      Text(
                        openHandLocalizedText(
                          context,
                          zh: '跨主机重复 Key ${result.duplicateKeyHosts}',
                          en: 'Duplicate key hosts ${result.duplicateKeyHosts}',
                        ),
                      ),
                    if (result.duplicateResponseHosts > 0)
                      Text(
                        openHandLocalizedText(
                          context,
                          zh: '重复响应 ${result.duplicateResponseHosts}',
                          en: 'Duplicate responses ${result.duplicateResponseHosts}',
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.entry,
    required this.onResume,
    required this.onDelete,
    required this.onLogs,
    required this.onExport,
  });
  final AiExposureHistoryEntry entry;
  final VoidCallback? onResume;
  final VoidCallback onDelete;
  final VoidCallback onLogs;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.history_rounded, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_stageLabel(context, entry.stage)} · ${_dateTime(entry.createdAt)} · ${entry.progress.processed}/${entry.progress.total}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          ServiceDialogIconActions(
            children: [
              Tooltip(
                message: openHandLocalizedText(
                  context,
                  zh: '恢复任务',
                  en: 'Resume',
                ),
                child: IconButton(
                  onPressed: onResume,
                  icon: const Icon(Icons.restore_rounded),
                ),
              ),
              Tooltip(
                message: openHandLocalizedText(context, zh: '任务日志', en: 'Logs'),
                child: IconButton(
                  onPressed: onLogs,
                  icon: const Icon(Icons.terminal_rounded),
                ),
              ),
              Tooltip(
                message: openHandLocalizedText(context, zh: '导出', en: 'Export'),
                child: IconButton(
                  onPressed: onExport,
                  icon: const Icon(Icons.download_outlined),
                ),
              ),
              Tooltip(
                message: openHandDeleteLabel(context),
                child: IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _showHistoryLogs(
  BuildContext context,
  AiExposureHistoryEntry entry,
) => showAnimatedDialog<void>(
  context: context,
  builder: (_) => buildOpenHandDialog(
    maxWidth: kOpenHandDialogWidthWide,
    maxHeight: kOpenHandDialogHeightStandard,
    child: ServiceDialogInteractionTheme(
      child: _HistoryLogDialog(entry: entry),
    ),
  ),
);

class _HistoryLogDialog extends StatefulWidget {
  const _HistoryLogDialog({required this.entry});
  final AiExposureHistoryEntry entry;

  @override
  State<_HistoryLogDialog> createState() => _HistoryLogDialogState();
}

class _HistoryLogDialogState extends State<_HistoryLogDialog> {
  late final Future<List<AiExposureLogEntry>> _logs = context
      .read<ServicesController>()
      .loadHistoryLogs(widget.entry.id);

  @override
  Widget build(BuildContext context) => _DialogFrame(
    icon: Icons.terminal_rounded,
    title: widget.entry.name,
    scrollable: false,
    child: FutureBuilder<List<AiExposureLogEntry>>(
      future: _logs,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        return _LogList(logs: snapshot.data ?? const <AiExposureLogEntry>[]);
      },
    ),
  );
}

class _SourceSwitch extends StatelessWidget {
  const _SourceSwitch({
    required this.source,
    required this.enabled,
    required this.configured,
    required this.onChanged,
  });
  final AiExposureSource source;
  final bool enabled;
  final bool configured;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      children: [
        Icon(_sourceIcon(source), color: cs.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _sourceLabel(context, source),
                style: theme.textTheme.titleSmall,
              ),
              Text(
                configured
                    ? openHandLocalizedText(context, zh: '已就绪', en: 'Ready')
                    : openHandLocalizedText(
                        context,
                        zh: '未配置凭证',
                        en: 'Credentials not configured',
                      ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: configured ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Switch(value: enabled, onChanged: onChanged),
      ],
    );
  }
}

class _RuleTile extends StatelessWidget {
  const _RuleTile({
    required this.rule,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });
  final AiExposureScanRule rule;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Switch(value: rule.enabled, onChanged: onToggle),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rule.vendor, style: theme.textTheme.titleSmall),
                Text(
                  '${rule.protocol} · Regex ${rule.credentialPatterns.length} · 编码 ${rule.contentEncodings.length}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          ServiceDialogIconActions(
            key: ValueKey<String>('rule-actions-${rule.id}'),
            children: [
              IconButton(
                tooltip: openHandLocalizedText(context, zh: '编辑', en: 'Edit'),
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: openHandDeleteLabel(context),
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: cs.outline),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

Future<AiExposureScanRule?> _showRuleEditor(
  BuildContext context, {
  AiExposureScanRule? initial,
}) => showAnimatedDialog<AiExposureScanRule>(
  context: context,
  builder: (_) => buildOpenHandDialog(
    maxWidth: kOpenHandDialogWidthStandard,
    maxHeight: kOpenHandDialogHeightStandard,
    child: ServiceDialogInteractionTheme(child: _RuleEditor(initial: initial)),
  ),
);

class _RuleEditor extends StatefulWidget {
  const _RuleEditor({this.initial});
  final AiExposureScanRule? initial;

  @override
  State<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<_RuleEditor> {
  late final Set<AiExposureContentEncoding> _encodings = widget.initial == null
      ? Set<AiExposureContentEncoding>.of(AiExposureContentEncoding.values)
      : Set<AiExposureContentEncoding>.of(widget.initial!.contentEncodings);
  late final TextEditingController _vendor = TextEditingController(
    text: widget.initial?.vendor,
  );
  late final TextEditingController _protocol = TextEditingController(
    text: widget.initial?.protocol,
  );
  late final TextEditingController _patterns = TextEditingController(
    text: widget.initial?.credentialPatterns.join('\n'),
  );
  late final TextEditingController _contexts = TextEditingController(
    text: widget.initial?.contextTerms.join('\n'),
  );
  late final TextEditingController _modelPaths = TextEditingController(
    text: widget.initial?.modelPaths.join('\n'),
  );
  late final TextEditingController _balancePaths = TextEditingController(
    text: widget.initial?.balancePaths.join('\n'),
  );

  @override
  void dispose() {
    _vendor.dispose();
    _protocol.dispose();
    _patterns.dispose();
    _contexts.dispose();
    _modelPaths.dispose();
    _balancePaths.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    return _DialogFrame(
      icon: Icons.edit_note_rounded,
      title: widget.initial == null
          ? text(zh: '新增规则', en: 'Add rule')
          : text(zh: '编辑规则', en: 'Edit rule'),
      footer: _DialogActions(
        actions: [
          OpenHandDialogActionButton.secondary(
            onPressed: () => Navigator.of(context).pop(),
            label: openHandCancelLabel(context),
          ),
          OpenHandDialogActionButton.primary(
            icon: Icons.check_rounded,
            onPressed: _submit,
            label: openHandSaveLabel(context),
          ),
        ],
      ),
      child: Column(
        children: [
          TextField(
            controller: _vendor,
            decoration: InputDecoration(
              labelText: text(zh: '厂商', en: 'Provider'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _protocol,
            decoration: InputDecoration(
              labelText: text(zh: '协议', en: 'Protocol'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _patterns,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: text(
                zh: '凭证正则（每行一条）',
                en: 'Credential regex (one per line)',
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _contexts,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: text(
                zh: '上下文词（每行一条）',
                en: 'Context terms (one per line)',
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AiExposureContentEncoding.values
                  .map(
                    (encoding) => ServiceFilterChip(
                      selected: _encodings.contains(encoding),
                      icon: const Icon(Icons.data_object_rounded, size: 17),
                      label: Text(_encodingLabel(encoding)),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _encodings.add(encoding);
                        } else {
                          _encodings.remove(encoding);
                        }
                      }),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _modelPaths,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: text(
                zh: '模型列表路径（每行一条）',
                en: 'Model paths (one per line)',
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _balancePaths,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: text(
                zh: '余额查询路径（每行一条，可选）',
                en: 'Balance paths (one per line, optional)',
              ),
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  void _submit() {
    final vendor = _vendor.text.trim();
    final patterns = _lines(_patterns.text);
    if (vendor.isEmpty || patterns.isEmpty) {
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '厂商和凭证正则不能为空。',
          en: 'Provider and credential regex are required.',
        ),
      );
      return;
    }
    Navigator.of(context).pop(
      AiExposureScanRule(
        id:
            widget.initial?.id ??
            '${vendor.toLowerCase().replaceAll(' ', '_')}_${DateTime.now().microsecondsSinceEpoch}',
        vendor: vendor,
        protocol: _protocol.text.trim().isEmpty
            ? vendor
            : _protocol.text.trim(),
        enabled: widget.initial?.enabled ?? true,
        credentialPatterns: patterns,
        contextTerms: _lines(_contexts.text),
        contentEncodings: _encodings.toList(growable: false),
        modelPaths: _lines(_modelPaths.text),
        balancePaths: _lines(_balancePaths.text),
      ),
    );
  }
}

String _encodingLabel(AiExposureContentEncoding encoding) => switch (encoding) {
  AiExposureContentEncoding.base64 => 'Base64',
  AiExposureContentEncoding.base64Url => 'Base64URL',
  AiExposureContentEncoding.url => 'URL Encoding',
  AiExposureContentEncoding.hex => 'Hex',
};

Future<void> _confirmDeleteHistory(
  BuildContext context,
  ServicesController controller,
  AiExposureHistoryEntry entry,
) async {
  final confirmed = await showOpenHandConfirmDialog(
    context: context,
    title: openHandLocalizedText(
      context,
      zh: '删除扫描历史？',
      en: 'Delete scan history?',
    ),
    message: entry.name,
    confirmLabel: openHandDeleteLabel(context),
    destructive: true,
  );
  if (confirmed) await controller.deleteHistory(entry.id);
}

Future<void> _exportResults(
  BuildContext context,
  List<AiExposureResult> results,
) async {
  if (results.isEmpty) {
    showOpenHandInfoSnack(
      context,
      openHandLocalizedText(
        context,
        zh: '没有可导出的结果。',
        en: 'No results to export.',
      ),
    );
    return;
  }
  final format = await showAnimatedDialog<_ExposureExportFormat>(
    context: context,
    builder: (_) => buildOpenHandDialog(
      maxWidth: kOpenHandDialogWidthCompact,
      maxHeight: kOpenHandDialogHeightCompact,
      child: ServiceDialogInteractionTheme(
        child: _ExportFormatDialog(count: results.length),
      ),
    ),
  );
  if (format == null || !context.mounted) return;
  try {
    final extension = format == _ExposureExportFormat.json ? 'json' : 'csv';
    final location = await getSaveLocation(
      suggestedName:
          'openhand-ai-exposure-${DateTime.now().toIso8601String().replaceAll(':', '-')}.$extension',
      acceptedTypeGroups: <XTypeGroup>[
        XTypeGroup(
          label: extension.toUpperCase(),
          extensions: <String>[extension],
        ),
      ],
    );
    if (location == null) return;
    final payload = format == _ExposureExportFormat.json
        ? const JsonEncoder.withIndent(
            '  ',
          ).convert(results.map(_resultJson).toList(growable: false))
        : _resultsCsv(results);
    await writeFileAtomically(File(location.path), payload);
    if (!context.mounted) return;
    showOpenHandSuccessSnack(
      context,
      openHandLocalizedText(
        context,
        zh: '已导出 ${results.length} 条打码结果。',
        en: 'Exported ${results.length} masked results.',
      ),
    );
  } catch (error) {
    if (!context.mounted) return;
    showOpenHandErrorSnack(
      context,
      openHandLocalizedText(
        context,
        zh: '导出失败：$error',
        en: 'Export failed: $error',
      ),
    );
  }
}

Map<String, Object?> _resultJson(AiExposureResult result) => <String, Object?>{
  'id': result.id,
  'jobId': result.jobId,
  'source': result.source.id,
  'url': result.url,
  'host': result.host,
  'product': result.product,
  'category': result.category.name,
  'credentialState': result.credentialState,
  'maskedCredential': result.maskedCredential,
  'responseFingerprint': result.responseFingerprint,
  'duplicateResponseHosts': result.duplicateResponseHosts,
  'duplicateKeyHosts': result.duplicateKeyHosts,
  'modelCount': result.modelCount,
  'balanceSummary': result.balanceSummary,
  'evidence': result.evidence,
  'createdAt': result.createdAt.toIso8601String(),
};

enum _ExposureExportFormat { json, csv }

class _ExportFormatDialog extends StatelessWidget {
  const _ExportFormatDialog({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => _DialogFrame(
    icon: Icons.download_rounded,
    title: openHandLocalizedText(
      context,
      zh: '导出 $count 条结果',
      en: 'Export $count results',
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OpenHandDialogActionButton.primary(
          icon: Icons.data_object_rounded,
          onPressed: () =>
              Navigator.of(context).pop(_ExposureExportFormat.json),
          label: 'JSON',
        ),
        const SizedBox(height: 10),
        OpenHandDialogActionButton.secondary(
          icon: Icons.table_rows_outlined,
          onPressed: () => Navigator.of(context).pop(_ExposureExportFormat.csv),
          label: 'CSV',
        ),
      ],
    ),
  );
}

String _resultsCsv(List<AiExposureResult> results) {
  final rows = <List<Object?>>[
    <Object?>[
      'id',
      'jobId',
      'source',
      'url',
      'host',
      'product',
      'category',
      'credentialState',
      'maskedCredential',
      'duplicateResponseHosts',
      'duplicateKeyHosts',
      'modelCount',
      'balanceSummary',
      'evidence',
      'createdAt',
    ],
    for (final result in results)
      <Object?>[
        result.id,
        result.jobId,
        result.source.id,
        result.url,
        result.host,
        result.product,
        result.category.name,
        result.credentialState,
        result.maskedCredential,
        result.duplicateResponseHosts,
        result.duplicateKeyHosts,
        result.modelCount,
        result.balanceSummary,
        result.evidence.join(' | '),
        result.createdAt.toIso8601String(),
      ],
  ];
  return rows.map((row) => row.map(_csvCell).join(',')).join('\r\n');
}

String _csvCell(Object? value) {
  var text = value?.toString() ?? '';
  if (text.isNotEmpty && const <String>{'=', '+', '-', '@'}.contains(text[0])) {
    text = "'$text";
  }
  return '"${text.replaceAll('"', '""')}"';
}

List<String> _lines(String value) => value
    .split(RegExp(r'[\r\n]+'))
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty)
    .toSet()
    .toList(growable: false);

String _sourceLabel(BuildContext context, AiExposureSource source) =>
    switch (source) {
      AiExposureSource.manual => openHandLocalizedText(
        context,
        zh: '手工目标',
        en: 'Manual',
      ),
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

String _sourceStatusKey(AiExposureSource source) => switch (source) {
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

AiExposureQuota? _sourceQuota(
  List<AiExposureQuota> quotas,
  AiExposureSource source,
) {
  for (final quota in quotas) {
    if (quota.source == source) return quota;
  }
  return null;
}

String _stageLabel(BuildContext context, String stage) {
  final zh = switch (stage) {
    'queued' => '排队中',
    'discovering' => '发现资产',
    'normalizing' => '规范化',
    'fingerprinting' => '指纹识别',
    'extracting' => '提取凭证',
    'validating' => '并发验证',
    'persisting' => '关联归档',
    'completed' => '已完成',
    'cancelled' => '已停止',
    'failed' => '失败',
    _ => stage,
  };
  return openHandLocalizedText(context, zh: zh, en: stage.replaceAll('_', ' '));
}

String _categoryLabel(
  BuildContext context,
  AiExposureResultCategory category,
) => switch (category) {
  AiExposureResultCategory.valid => openHandLocalizedText(
    context,
    zh: '有效',
    en: 'Valid',
  ),
  AiExposureResultCategory.suspicious => openHandLocalizedText(
    context,
    zh: '可疑',
    en: 'Suspicious',
  ),
  AiExposureResultCategory.highValue => openHandLocalizedText(
    context,
    zh: '高价值',
    en: 'High value',
  ),
  AiExposureResultCategory.honeypot => openHandLocalizedText(
    context,
    zh: '蜜罐',
    en: 'Honeypot',
  ),
};

Color _categoryColor(ColorScheme cs, AiExposureResultCategory category) =>
    switch (category) {
      AiExposureResultCategory.valid => cs.primary,
      AiExposureResultCategory.suspicious => cs.secondary,
      AiExposureResultCategory.highValue => cs.tertiary,
      AiExposureResultCategory.honeypot => cs.error,
    };

IconData _categoryIcon(AiExposureResultCategory category) => switch (category) {
  AiExposureResultCategory.valid => Icons.verified_outlined,
  AiExposureResultCategory.suspicious => Icons.help_outline_rounded,
  AiExposureResultCategory.highValue => Icons.workspace_premium_outlined,
  AiExposureResultCategory.honeypot => Icons.warning_amber_rounded,
};

String _time(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}:${value.second.toString().padLeft(2, '0')}';

String _dateTime(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} ${_time(value)}';

String _serviceDuration(int seconds) {
  final normalized = seconds < 0 ? 0 : seconds;
  if (normalized < 60) return '${normalized}s';
  final hours = normalized ~/ Duration.secondsPerHour;
  final minutes =
      normalized % Duration.secondsPerHour ~/ Duration.secondsPerMinute;
  return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
}
