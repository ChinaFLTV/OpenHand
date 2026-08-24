part of 'ai_exposure_monitoring_dialogs.dart';

enum _OperationsView { overview, pipeline, storage }

typedef _OperationsControllerSnapshot = ({
  bool busy,
  bool running,
  bool ownsProcess,
  Object? health,
  Object? progress,
  Object history,
  Object results,
  Object rules,
  Object quotas,
  Object logs,
  Object? aiExtractorStatus,
  Object? dependencyStatus,
  Object? proxyStatus,
  Object proxyConfiguration,
  Object sourceStatus,
  int enabledSourcesMask,
  int defaultConcurrency,
  AiExposureProxyRoute proxyRoute,
});

enum _MetricInsightId {
  overviewTaskTotal,
  overviewResultTotal,
  overviewHighValue,
  overviewProcessed,
  overviewAverageDuration,
  overviewConfiguredSources,
  overviewEnabledRules,
  overviewProxyRouting,
  overviewProxyAverageLatency,
  overviewWarningLogs,
  overviewErrorLogs,
  overviewCancelledTasks,
  pipelineCurrentState,
  pipelineProcessed,
  pipelineCandidates,
  pipelineValid,
  pipelineHighValue,
  pipelineConcurrency,
  pipelineFullScan,
  pipelineResumable,
  storageSqlite,
  storageLastWrite,
}

enum _TrendInsightId {
  taskThroughput,
  taskDuration,
  pipelineFunnel,
  proxyLatency,
  archiveGrowth,
  writeLoad,
}

enum _DistributionInsightId {
  resultCategory,
  taskStage,
  scanMode,
  resultSource,
  taskSource,
  requestOutcome,
  httpStatus,
  nodeRequest,
  recordType,
  archiveStage,
  credentialState,
  proxyReliability,
  ruleVendor,
}

enum _DependencyInsightId {
  scannerCore,
  sqlite,
  credentialVault,
  postgresql,
  redis,
  playwright,
  gptExtractor,
  proxyRouting,
  proxyReliability,
  localBypass,
  rotationPolicy,
  sourceAdapters,
  fingerprintRules,
  activeValidator,
  taskEventStream,
  eventArchive,
}

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
    _timer = startNonOverlappingPeriodicTimer(
      _kOperationsRefreshInterval,
      (_) => _refresh(),
      onError: (error, stack) =>
          silentLog('service_operations', '执行定时状态刷新', error, stack),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool forcePluginRescan = false}) async {
    if (!mounted || _refreshing) return;
    final controller = context.read<ServicesController>();
    if (!controller.isRunning) return;
    setState(() => _refreshing = true);
    var accessible = false;
    int? bytes;
    DateTime? modifiedAt;
    try {
      if (forcePluginRescan) {
        // 手动刷新必须先重新扫描插件，再用最新插件状态同步托管依赖，
        // 最后读取服务数据，避免安装/启用插件后仍展示旧快照。
        await controller.refreshData(forcePluginRescan: true);
        await Future.wait<Object?>([
          controller.refreshDependencyDataOverview(),
          controller.refreshServiceLogs(force: true),
        ]);
      } else {
        await Future.wait<Object?>([
          controller.refreshServiceStatus(),
          controller.refreshDependencyDataOverview(),
        ]);
      }
      final path = controller.health?.databasePath.trim() ?? '';
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
    } catch (error, stack) {
      silentLog('service_operations', '刷新服务运维状态', error, stack);
    } finally {
      if (mounted) {
        setState(() {
          _databaseAccessible = accessible;
          _databaseBytes = bytes;
          _databaseModifiedAt = modifiedAt;
          _refreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = context
        .select<ServicesController, _OperationsControllerSnapshot>(
          (controller) => (
            busy: controller.busy,
            running: controller.isRunning,
            ownsProcess: controller.ownsProcess,
            health: controller.health,
            progress: controller.progress,
            history: controller.history,
            results: controller.results,
            rules: controller.rules,
            quotas: controller.quotas,
            logs: _view == _OperationsView.pipeline
                ? const <Never>[]
                : controller.logs,
            aiExtractorStatus: controller.aiExtractorStatus,
            dependencyStatus: controller.dependencyStatus,
            proxyStatus: controller.proxyStatus,
            proxyConfiguration: controller.proxyConfiguration,
            sourceStatus: controller.sourceStatus,
            enabledSourcesMask: controller.enabledSources.fold<int>(
              0,
              (mask, source) => mask | (1 << source.index),
            ),
            defaultConcurrency: controller.defaultConcurrency,
            proxyRoute: controller.proxyRoute,
          ),
        );
    final controller = context.read<ServicesController>();
    final text = openHandTextResolver(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final running = snapshot.running;
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Padding(
      padding: EdgeInsets.all(compact ? 14 : 22),
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
                    borderRadius: BorderRadius.circular(kOpenHandRadius8),
                    border: Border.all(
                      color: cs.primary.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Icon(
                    Icons.monitor_heart_rounded,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                kOpenHandHGap12,
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
                      OpenHandLiveValue(
                        'ai_jungler ${controller.health?.version ?? '--'} · ${snapshot.ownsProcess ? text(zh: '内嵌进程', en: 'Bundled') : text(zh: '外部服务', en: 'External')}',
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
                  tooltip: text(
                    zh: '刷新插件与运维数据',
                    en: 'Refresh plugins and operations',
                  ),
                  onPressed: running && !_refreshing
                      ? () => _refresh(forcePluginRescan: true)
                      : null,
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
                  onPressed: snapshot.busy
                      ? null
                      : running
                      ? controller.stopService
                      : () => startOrConfigureAiExposureService(
                          context,
                          controller,
                        ),
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
          kOpenHandGap12,
          _OperationsStrip(
            compact: compact,
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
                color: running ? OpenHandStatusColors.success : cs.outline,
                pulse: running,
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
          kOpenHandGap14,
          _OperationsStrip(
            compact: compact,
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
                value: _OperationsView.storage,
                selected: _view == _OperationsView.storage,
                icon: Icons.storage_rounded,
                label: text(zh: '存储与持久化', en: 'Storage'),
                onSelected: (value) => setState(() => _view = value),
              ),
            ],
          ),
          kOpenHandGap14,
          Expanded(
            child: AnimatedSwitcher(
              duration: openHandMotionDuration(context, kOpenHandMotion220),
              switchInCurve: kOpenHandSwitchInCurve,
              switchOutCurve: kOpenHandSwitchOutCurve,
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
                  _OperationsView.storage => _StoragePanel(
                    controller: controller,
                    databaseAccessible: _databaseAccessible,
                    databaseBytes: _databaseBytes,
                    databaseModifiedAt: _databaseModifiedAt,
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

class _OperationsStrip extends StatelessWidget {
  const _OperationsStrip({
    required this.compact,
    required this.spacing,
    required this.runSpacing,
    required this.children,
  });

  final bool compact;
  final double spacing;
  final double runSpacing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (!compact) {
      return Wrap(spacing: spacing, runSpacing: runSpacing, children: children);
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const ClampingScrollPhysics(),
      child: Row(
        children: children.indexed
            .expand(
              (entry) => [if (entry.$1 > 0) SizedBox(width: spacing), entry.$2],
            )
            .toList(growable: false),
      ),
    );
  }
}
