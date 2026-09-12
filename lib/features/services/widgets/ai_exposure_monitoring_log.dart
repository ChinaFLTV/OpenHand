part of 'ai_exposure_monitoring_dialogs.dart';

const Set<String> _kLogLevels = <String>{'info', 'warning', 'error', 'runtime'};

enum _LogScope { all, current, runtime, history }

class _LogMonitorDialog extends StatefulWidget {
  const _LogMonitorDialog();

  @override
  State<_LogMonitorDialog> createState() => _LogMonitorDialogState();
}

class _LogMonitorDialogState extends State<_LogMonitorDialog> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();
  final Set<String> _levels = <String>{..._kLogLevels};
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
    if (!mounted || _refreshing) return;
    setState(() => _refreshing = true);
    try {
      await context.read<ServicesController>().refreshServiceLogs(force: true);
    } catch (error, stack) {
      silentLog('service_log_monitor', '刷新服务日志', error, stack);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: openHandMotionDuration(context, kOpenHandMotion220),
        curve: kOpenHandSwitchInCurve,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ServicesController>();
    final theme = Theme.of(context);
    final text = openHandTextResolver(context);
    final logs = _filtered(controller);
    if (_autoFollow && controller.logs.length != _lastLogCount) {
      _lastLogCount = controller.logs.length;
      _scrollToLatest();
    }
    var infoCount = 0;
    var warningCount = 0;
    var errorCount = 0;
    var runtimeCount = 0;
    for (final item in logs) {
      switch (item.level) {
        case 'info':
          infoCount++;
        case 'warning':
          warningCount++;
        case 'error':
          errorCount++;
        case 'runtime':
          runtimeCount++;
      }
    }
    return OpenHandEditorDialogScaffold(
      title: text(zh: '服务日志监控', en: 'Service log monitor'),
      subtitle: text(
        zh: '历史 ${controller.history.length} 个任务 · 当前保留 ${controller.logs.length} 条',
        en: '${controller.history.length} jobs · ${controller.logs.length} retained',
      ),
      icon: Icons.manage_search_rounded,
      iconColor: OpenHandStatusColors.info,
      scrollBody: false,
      busy: _refreshing,
      maxWidth: kOpenHandDialogWidthPanel,
      headerActions: [
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
          onPressed: _refreshing || !controller.isRunning ? null : _refresh,
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
          onPressed: controller.logs.isEmpty ? null : controller.clearLogs,
          icon: const Icon(Icons.cleaning_services_outlined),
        ),
      ],
      actions: const <Widget>[],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: OpenHandDialogSectionCard(
              icon: Icons.filter_alt_outlined,
              title: text(zh: '筛选', en: 'Filters'),
              subtitle: text(
                zh: '按任务范围、级别和关键字收窄日志。',
                en: 'Narrow logs by job scope, level, and keyword.',
              ),
              accent: OpenHandStatusColors.info,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      labelText: text(zh: '搜索日志', en: 'Search logs'),
                    ),
                  ),
                  kOpenHandGap10,
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: _AnimatedLogScopeTabs(
                      value: _scope,
                      onChanged: (value) => setState(() => _scope = value),
                    ),
                  ),
                  kOpenHandGap10,
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final level in _kLogLevels)
                        ServiceFilterChip(
                          selected: _levels.contains(level),
                          icon: Icon(
                            _logIcon(level),
                            size: 16,
                            color: _logColor(level),
                          ),
                          label: Text(_logLevelName(context, level)),
                          accentColor: _logColor(level),
                          onSelected: (selected) => setState(() {
                            if (selected) {
                              _levels.add(level);
                            } else {
                              _levels.remove(level);
                            }
                          }),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _kAiExposureDarkSurface,
                borderRadius: kOpenHandBorderRadius20,
                border: Border.all(
                  color: OpenHandStatusColors.info.withValues(alpha: 0.28),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.terminal_rounded,
                          size: 18,
                          color: _kAiExposureConsoleSuccess,
                        ),
                        kOpenHandHGap8,
                        Expanded(
                          child: Text(
                            text(zh: '控制台', en: 'Console'),
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: _kAiExposureDarkOnSurface,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          text(
                            zh: '${logs.length} 条',
                            en: '${logs.length} lines',
                          ),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: _kAiExposureDarkMutedText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                  Expanded(
                    child: logs.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.manage_search_rounded,
                                  size: 36,
                                  color: _kAiExposureDarkMutedText.withValues(
                                    alpha: 0.85,
                                  ),
                                ),
                                kOpenHandGap10,
                                Text(
                                  text(zh: '没有符合条件的日志', en: 'No matching logs'),
                                  style: const TextStyle(
                                    color: _kAiExposureDarkOnSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                kOpenHandGap6,
                                Text(
                                  text(
                                    zh: '调整范围、级别或关键字后再试。',
                                    en: 'Adjust scope, level, or keyword and try again.',
                                  ),
                                  style: const TextStyle(
                                    color: _kAiExposureDarkMutedText,
                                  ),
                                ),
                              ],
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
                ],
              ),
            ),
          ),
          kOpenHandGap10,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OhPill(
                icon: Icons.info_outline_rounded,
                label: text(zh: '信息 $infoCount', en: 'INFO $infoCount'),
                foregroundColor: OpenHandStatusColors.info,
              ),
              OhPill(
                icon: Icons.warning_amber_rounded,
                label: text(zh: '警告 $warningCount', en: 'WARN $warningCount'),
                foregroundColor: OpenHandStatusColors.warning,
              ),
              OhPill(
                icon: Icons.error_outline_rounded,
                label: text(zh: '错误 $errorCount', en: 'ERROR $errorCount'),
                foregroundColor: OpenHandStatusColors.error,
              ),
              OhPill(
                icon: Icons.memory_rounded,
                label: text(
                  zh: '运行时 $runtimeCount',
                  en: 'RUNTIME $runtimeCount',
                ),
                foregroundColor: _kAiExposureLogRuntime,
              ),
            ],
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
    try {
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
              if (entry.atReported) 'at': entry.at.toUtc().toIso8601String(),
              'level': entry.level,
              'jobId': entry.jobId,
              'message': entry.message,
            }),
          )
          .join('\n');
      await writeFileAtomically(File(location.path), '$payload\n');
      if (mounted) showOpenHandSuccessSnack(context, '日志已保存。');
    } catch (error, stack) {
      silentLog('service_log_monitor', '保存服务日志', error, stack);
      if (mounted) {
        showOpenHandErrorSnack(context, '保存日志失败，请检查文件路径或磁盘空间。');
      }
    }
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});
  final AiExposureLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = _logColor(entry.level);
    final local = entry.at.toLocal();
    final time = entry.atReported ? formatMonthDayHms(local) : '时间未上报';
    return ServiceInteractiveSurface(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      showDetailsIcon: false,
      tooltip: openHandLocalizedText(
        context,
        zh: '查看日志详情',
        en: 'View log details',
      ),
      onTap: () => _showLogEntityInsight(context, entry),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              time,
              style: const TextStyle(
                color: _kAiExposureDarkTimestamp,
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
                kOpenHandHGap5,
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
                  color: _kAiExposureDarkJobId,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
          Expanded(
            child: SelectableText(
              entry.message,
              style: const TextStyle(
                color: _kAiExposureDarkOnSurface,
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
  'runtime' => _kAiExposureLogRuntime,
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
        animationDuration: openHandMotionDuration(context, kOpenHandMotion280),
      ),
    );
  }
}
