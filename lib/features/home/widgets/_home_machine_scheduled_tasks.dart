part of '../openhand_home_page.dart';

String _taskSchedulerLabel(BuildContext context, MachineTaskScheduler value) {
  final l = AppLocalizations.of(context)!;
  return switch (value) {
    MachineTaskScheduler.cron => l.maintenanceTaskSchedulerCron,
    MachineTaskScheduler.systemd => l.maintenanceTaskSchedulerSystemd,
    MachineTaskScheduler.launchd => l.maintenanceTaskSchedulerLaunchd,
    MachineTaskScheduler.windows => l.maintenanceTaskWindows,
  };
}

String _taskIssueLabel(BuildContext context, String source) {
  final parts = source.split('/');
  final scheduler = MachineTaskScheduler.values
      .where((value) => value.name == parts.first)
      .firstOrNull;
  if (scheduler == null) {
    return source == 'limit'
        ? AppLocalizations.of(context)!.maintenanceTaskTotal
        : source;
  }
  final label = _taskSchedulerLabel(context, scheduler);
  return parts.length == 1
      ? label
      : '$label · ${maintenanceLabel(context, parts.last == 'user'
            ? '用户'
            : parts.last == 'system'
            ? '系统'
            : parts.last)}';
}

String _taskStateLabel(BuildContext context, String value) {
  final l = AppLocalizations.of(context)!;
  return switch (value.toLowerCase()) {
    'scheduled' => l.maintenanceTaskScheduled,
    'ready' || 'waiting' => l.maintenanceTaskReady,
    'queued' => l.maintenanceTaskQueued,
    'enabled' => l.maintenanceTaskEnabled,
    'disabled' => l.maintenanceTaskDisabled,
    'running' => maintenanceLabel(context, '运行中'),
    'active' => l.maintenanceTaskEnabled,
    'inactive' => maintenanceLabel(context, '未运行'),
    'failed' => maintenanceLabel(context, '异常'),
    'interactivetoken' => l.maintenanceTaskInteractive,
    'password' => l.maintenanceTaskPassword,
    's4u' => l.maintenanceTaskNoPassword,
    'interactivetokenorpassword' => l.maintenanceTaskMixedLogon,
    'serviceaccount' => maintenanceLabel(context, '服务账户'),
    'group' => maintenanceLabel(context, '用户组'),
    'ignorenew' => l.maintenanceTaskIgnoreNew,
    'parallel' => l.maintenanceTaskParallelRuns,
    'queue' => l.maintenanceTaskQueued,
    'stopexisting' => l.maintenanceTaskStopExisting,
    'leastprivilege' => l.maintenanceTaskLeastPrivilege,
    'highestavailable' => l.maintenanceTaskHighestPrivilege,
    _ => maintenanceDetailValue(context, value),
  };
}

String _taskError(BuildContext context, Object error) {
  final l = AppLocalizations.of(context)!;
  if (error is TimeoutException) return l.maintenanceCommandTimedOut;
  if (error is! MachineTaskException) {
    return '${l.maintenanceTaskSaveFailed}\n$error';
  }
  final message = switch (error.code) {
    'conflict' => l.maintenanceTaskConflict,
    'permission' => l.maintenanceTaskReadOnly,
    'validation' || 'format' => l.maintenanceTaskValidation,
    'busy' => l.maintenanceTaskBusy,
    'limit' => l.maintenanceTaskLimit,
    'unavailable' => l.maintenanceTaskUnavailable,
    'verify' || 'incomplete' => l.maintenanceTaskVerify,
    'rollback' => l.maintenanceTaskRollback,
    'credentials' => l.maintenanceTaskCredentials,
    'identity' => l.maintenanceTaskChangedTarget,
    'save' => l.maintenanceTaskSaveFailed,
    _ => '${l.maintenanceTaskUnavailable}\n${error.code}',
  };
  return error.detail.isEmpty ? message : '$message\n${error.detail}';
}

String _taskFieldLabel(BuildContext context, String key) {
  final l = AppLocalizations.of(context)!;
  return switch (key) {
    'SHELL' => l.maintenanceShell,
    'PATH' => l.maintenanceTaskExecutablePaths,
    'HOME' => l.maintenanceHealthHome,
    'CRON_TZ' || 'TZ' => l.maintenanceEgressTimezone,
    'MAILTO' => l.maintenanceTaskMailTo,
    'MAILFROM' => l.maintenanceTaskMailFrom,
    'LOGNAME' => maintenanceLabel(context, '用户'),
    'RANDOM_DELAY' => l.maintenanceTaskRandomDelay,
    'Id' || 'Label' => maintenanceLabel(context, '名称'),
    'Description' || 'description' => maintenanceLabel(context, '描述'),
    'ActiveState' || 'State' => maintenanceLabel(context, '状态'),
    'LoadState' => maintenanceLabel(context, '加载状态'),
    'SubState' => maintenanceLabel(context, '子状态'),
    'UnitFileState' => maintenanceLabel(context, '启动方式'),
    'Unit' => maintenanceLabel(context, '系统服务'),
    'FragmentPath' => maintenanceLabel(context, '配置文件'),
    'DropInPaths' => l.maintenanceTaskOverrides,
    'TimersCalendar' || 'StartCalendarInterval' => l.maintenanceTaskCalendar,
    'TimersMonotonic' ||
    'NextElapseUSecMonotonic' => l.maintenanceTaskMonotonic,
    'NextElapseUSecRealtime' => l.maintenanceTaskNext,
    'LastTriggerUSec' => l.maintenanceTaskLast,
    'AccuracyUSec' => l.maintenanceTaskAccuracy,
    'RandomizedDelayUSec' => l.maintenanceTaskRandomDelay,
    'Persistent' || 'StartWhenAvailable' => l.maintenanceTaskPersistent,
    'Result' || 'LastTaskResult' => maintenanceLabel(context, '执行结果'),
    'missedRuns' || 'NumberOfMissedRuns' => l.maintenanceTaskMissed,
    'logonType' => l.maintenanceTaskLogon,
    'RunLevel' => l.maintenanceTaskRunLevel,
    'StartInterval' => l.maintenanceTaskIntervalLabel,
    'Program' => maintenanceLabel(context, '启动命令'),
    'ProgramArguments' => l.maintenanceTaskArguments,
    'WorkingDirectory' => l.maintenanceTaskWorkingDirectory,
    'StandardOutPath' => l.maintenanceTaskStdout,
    'StandardErrorPath' => l.maintenanceTaskStderr,
    'RunAtLoad' => l.maintenanceTaskRunAtLoad,
    'KeepAlive' => l.maintenanceTaskKeepAlive,
    'UserName' => maintenanceLabel(context, '用户'),
    'GroupName' => maintenanceLabel(context, '用户组'),
    'Disabled' => l.maintenanceTaskDisabled,
    'Enabled' => l.maintenanceTaskEnabled,
    'EnvironmentVariables' => l.maintenanceTaskEnvironment,
    'ExecutionTimeLimit' => l.maintenanceTaskExecutionLimit,
    'MultipleInstancesPolicy' => l.maintenanceTaskParallel,
    'DisallowStartIfOnBatteries' => l.maintenanceTaskBatteryStart,
    'StopIfGoingOnBatteries' => l.maintenanceTaskBatteryStop,
    'WakeToRun' => l.maintenanceTaskWake,
    'AllowStartOnDemand' => l.maintenanceTaskDemand,
    'Hidden' => l.maintenanceTaskHidden,
    'RunOnlyIfNetworkAvailable' => l.maintenanceTaskNetworkRequired,
    'RunOnlyIfIdle' => l.maintenanceTaskIdle,
    'AllowHardTerminate' => l.maintenanceTaskHardTerminate,
    _ => maintenanceDetailLabel(context, key),
  };
}

String _taskFieldValue(BuildContext context, String key, String raw) {
  if (raw.isEmpty) return AppLocalizations.of(context)!.maintenanceUnavailable;
  if (machineMaintenanceIsTimestampField(key)) {
    return maintenanceDetailValue(context, raw, field: key);
  }
  final locale = Localizations.localeOf(context);
  final duration =
      const {
        'StartInterval',
        'AccuracyUSec',
        'RandomizedDelayUSec',
      }.contains(key)
      ? machineMaintenanceReadableDuration(
          key == 'StartInterval' ? '$raw s' : raw,
          field: key,
          languageCode: locale.languageCode,
          scriptCode: locale.scriptCode,
        )
      : null;
  return duration ?? _taskStateLabel(context, raw);
}

String _taskScheduleLabel(BuildContext context, MachineScheduledTask task) {
  final l = AppLocalizations.of(context)!;
  var value = task.schedule;
  if (task.scheduler == MachineTaskScheduler.windows) {
    for (final entry in {
      'CalendarTrigger': l.maintenanceTaskCalendar,
      'TimeTrigger': l.maintenanceTaskTriggerTime,
      'BootTrigger': l.maintenanceTaskTriggerBoot,
      'LogonTrigger': l.maintenanceTaskTriggerLogon,
      'EventTrigger': l.maintenanceTaskTriggerEvent,
      'SessionStateChangeTrigger': l.maintenanceTaskTriggerSession,
      'IdleTrigger': l.maintenanceTaskIdle,
      'RegistrationTrigger': l.maintenanceTaskRunAtLoad,
    }.entries) {
      value = value.replaceAll('${entry.key}:', '${entry.value}:');
    }
  }
  if (task.scheduler == MachineTaskScheduler.launchd &&
      task.metadata.containsKey('StartInterval')) {
    final interval = task.metadata['StartInterval']!;
    final seconds = double.tryParse(interval);
    if (task.metadata['StartCalendarInterval']?.isNotEmpty != true &&
        seconds != null &&
        seconds.isFinite &&
        seconds > 0) {
      return l.maintenanceTaskEvery(
        _taskFieldValue(context, 'StartInterval', interval),
      );
    }
  }
  if (task.scheduler == MachineTaskScheduler.systemd) {
    value = value.replaceAllMapped(
      RegExp(r'\{\s*([^;]+);\s*next_elapse=[^}]+\}'),
      (match) => match[1]!.trim(),
    );
    for (final entry in {
      'OnCalendar': l.maintenanceTaskCalendar,
      'OnBootUSec': l.maintenanceTaskAfterBoot,
      'OnActiveUSec': l.maintenanceTaskAfterActive,
      'OnStartupUSec': l.maintenanceTaskAfterStartup,
      'OnUnitActiveUSec': l.maintenanceTaskAfterUnitActive,
      'OnUnitInactiveUSec': l.maintenanceTaskAfterUnitInactive,
    }.entries) {
      value = value.replaceAll('${entry.key}=', '${entry.value}: ');
    }
  }
  if (task.scheduler == MachineTaskScheduler.launchd) {
    for (final entry in {
      'Minute': l.cronParserFieldMinute,
      'Hour': l.cronParserFieldHour,
      'Day': l.cronParserFieldDayOfMonth,
      'Month': l.cronParserFieldMonth,
      'Weekday': l.cronParserFieldDayOfWeek,
    }.entries) {
      value = value.replaceAll('${entry.key}=', '${entry.value}: ');
    }
  }
  return value.isEmpty ? '—' : value;
}

class _MachineScheduledTaskPanel extends StatefulWidget {
  const _MachineScheduledTaskPanel({
    super.key,
    required this.platform,
    required this.refreshToken,
    required this.run,
    required this.onBusy,
    this.onFailure,
    this.enabled = true,
  });
  final String platform;
  final Object? refreshToken;
  final bool enabled;
  final Future<String> Function(String, bool Function()) run;
  final ValueChanged<bool> onBusy;
  final VoidCallback? onFailure;
  @override
  State<_MachineScheduledTaskPanel> createState() =>
      _MachineScheduledTaskPanelState();
}

class _MachineScheduledTaskPanelState extends State<_MachineScheduledTaskPanel>
    with AutomaticKeepAliveClientMixin {
  final _search = TextEditingController();
  MachineScheduledTaskSnapshot? _data;
  MachineTaskScheduler? _filter;
  Object? _error;
  bool _busy = false, _overlay = false;
  @override
  bool get wantKeepAlive => true;
  MachineScheduledTaskClient get _client => MachineScheduledTaskClient(
    platform: widget.platform,
    run: (command) => widget.run(command, () => !mounted),
  );

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant _MachineScheduledTaskPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshToken != oldWidget.refreshToken ||
        widget.enabled && !oldWidget.enabled) {
      _refresh();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!widget.enabled ||
        widget.refreshToken == null ||
        _busy ||
        _overlay ||
        !mounted) {
      return;
    }
    widget.onBusy(true);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await _client.collect();
      if (mounted) setState(() => _data = data);
    } on MachineTerminalUploadCancelled {
      // 离开板块时取消采集，避免将主动关闭显示为故障。
    } catch (error) {
      if (mounted) {
        setState(() => _error = error);
        widget.onFailure?.call();
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
      widget.onBusy(false);
    }
  }

  Future<void> _open(
    MachineScheduledTask? task, {
    bool edit = false,
    bool delete = false,
  }) async {
    if (!widget.enabled ||
        _busy ||
        _overlay ||
        _error != null ||
        _data == null) {
      return;
    }
    setState(() => _overlay = true);
    widget.onBusy(true);
    var changed = false;
    var active = true;
    Future<void>? pending;
    try {
      final client = MachineScheduledTaskClient(
        platform: widget.platform,
        run: (command) async {
          final completed = Completer<void>();
          pending = completed.future;
          try {
            return await widget.run(command, () => !mounted || !active);
          } finally {
            completed.complete();
          }
        },
      );
      if (delete && task != null) {
        final confirmed = await showOpenHandConfirmDialog(
          context: context,
          title: '${AppLocalizations.of(context)!.commonDelete} · ${task.name}',
          message:
              '${AppLocalizations.of(context)!.maintenanceTaskDeleteConfirm}\n\n${task.source}\n${task.command}',
          confirmLabel: AppLocalizations.of(context)!.commonDelete,
          destructive: true,
        );
        if (confirmed != true || !mounted) return;
        await client.delete(task);
        changed = true;
      } else {
        changed =
            await showAnimatedDialog<bool>(
              context: context,
              builder: (_) => _MachineTaskDialog(
                platform: widget.platform,
                snapshot: _data!,
                task: task,
                edit: edit || task == null,
                client: client,
              ),
            ) ??
            false;
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      active = false;
      // 详情关闭后仍等待已发出的终端请求收尾，避免与下一次采集重叠。
      await pending;
      widget.onBusy(false);
      if (mounted) {
        setState(() => _overlay = false);
        if (changed) await _refresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l = AppLocalizations.of(context)!;
    final data = _data;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final controlHeight = _maintenanceFormControlHeightOf(context);
    final actionHeight = math.max(
      _maintenanceControlHeight,
      MediaQuery.textScalerOf(context).scale(_maintenanceFormFontSize) * 1.4 +
          12,
    );
    final actionStyle = _maintenanceTonalButtonStyle(context).copyWith(
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? cs.onSurface.withValues(alpha: .12)
            : cs.surface.withValues(alpha: .72),
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? cs.onSurface.withValues(alpha: .38)
            : cs.onSurfaceVariant,
      ),
      minimumSize: WidgetStatePropertyAll(Size(0, actionHeight)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 10),
      ),
      side: WidgetStatePropertyAll(
        BorderSide(color: cs.outlineVariant.withValues(alpha: .55)),
      ),
    );
    final blocked = !widget.enabled || _busy || _overlay || _error != null;
    final query = _search.text.trim().toLowerCase();
    final tasks =
        data?.tasks
            .where(
              (task) =>
                  (_filter == null || task.scheduler == _filter) &&
                  '${task.name} ${task.command} ${task.owner} ${task.source}'
                      .toLowerCase()
                      .contains(query),
            )
            .toList() ??
        [];
    return _MaintenanceCard(
      title: l.maintenanceTaskTitle,
      icon: Icons.event_repeat_rounded,
      accent: OpenHandStatusColors.info,
      scrollBody: false,
      wrapHeader: true,
      trailing: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox.square(
            dimension: actionHeight,
            child: IconButton(
              style: actionStyle.copyWith(
                minimumSize: WidgetStatePropertyAll(Size.square(actionHeight)),
                padding: const WidgetStatePropertyAll(EdgeInsets.zero),
              ),
              tooltip: l.maintenanceRefreshSection,
              onPressed: !widget.enabled || _busy || _overlay ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded, size: 18),
            ),
          ),
          FilledButton.icon(
            style: actionStyle,
            onPressed:
                blocked ||
                    data == null ||
                    !data.available.contains(
                      widget.platform == 'Windows'
                          ? MachineTaskScheduler.windows
                          : MachineTaskScheduler.cron,
                    )
                ? null
                : () => _open(null),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: Text(l.maintenanceTaskAdd),
          ),
        ],
      ),
      child: _MaintenanceAnimatedColumn(
        spacing: 12,
        children: [
          if ((_busy || !widget.enabled) && data == null)
            SizedBox(
              height: 180,
              child: Center(
                child: _MaintenanceEmptyHint(
                  icon: Icons.downloading_rounded,
                  message: l.maintenanceLoadingDetails,
                ),
              ),
            ),
          if (_busy && data != null)
            const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            _MaintenanceNotice(
              error: true,
              message:
                  '${data == null ? '' : '${l.maintenanceTaskStale}\n'}${_taskError(context, _error!)}',
            ),
          if (data != null) ...[
            _MaintenanceGrid(
              key: const ValueKey('scheduled-task-summary'),
              minWidth: 200,
              maxColumns: 4,
              balanceColumns: true,
              children: [
                for (final metric in [
                  (
                    label: l.maintenanceTaskTotal,
                    value: '${data.tasks.length}',
                    icon: Icons.event_note_rounded,
                    tone: cs.primary,
                  ),
                  (
                    label: l.maintenanceTaskEnabled,
                    value: '${data.tasks.where((task) => task.enabled).length}',
                    icon: Icons.check_circle_outline_rounded,
                    tone: OpenHandStatusColors.success,
                  ),
                  (
                    label: l.maintenanceEgressTimezone,
                    value: data.timezone.isEmpty ? '—' : data.timezone,
                    icon: Icons.public_rounded,
                    tone: cs.tertiary,
                  ),
                  (
                    label: l.maintenanceTaskSampled,
                    value: data.collectedAt.isEmpty
                        ? '—'
                        : maintenanceDetailValue(
                            context,
                            data.collectedAt,
                            field: 'collectedAt',
                          ),
                    icon: Icons.schedule_rounded,
                    tone: OpenHandStatusColors.info,
                  ),
                ])
                  Container(
                    key: ValueKey(metric.label),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: kOpenHandBorderRadius12,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _MaintenanceIconBadge(
                          icon: metric.icon,
                          color: metric.tone,
                          size: 32,
                          iconSize: 17,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                metric.label,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 6),
                              _MaintenanceValue(
                                value: metric.value,
                                maxLines: null,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final scale =
                    MediaQuery.textScalerOf(
                      context,
                    ).scale(_maintenanceFormFontSize) /
                    _maintenanceFormFontSize;
                final stacked = constraints.maxWidth < 580 * scale;
                final menuWidth = stacked
                    ? constraints.maxWidth
                    : math.min(320 * scale, constraints.maxWidth * .4);
                final border = OutlineInputBorder(
                  borderRadius: kOpenHandBorderRadius8,
                  borderSide: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: .65),
                  ),
                );
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: stacked
                          ? constraints.maxWidth
                          : constraints.maxWidth - menuWidth - 12,
                      child: TextField(
                        controller: _search,
                        textAlignVertical: TextAlignVertical.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: _maintenanceFormFontSize,
                          height: 1.4,
                        ),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: l.maintenanceTaskSearch,
                          isDense: true,
                          filled: true,
                          fillColor: cs.surfaceContainerLow,
                          hoverColor: Colors.transparent,
                          constraints: BoxConstraints.tightFor(
                            height: controlHeight,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          border: border,
                          enabledBorder: border,
                          focusedBorder: border.copyWith(
                            borderSide: BorderSide(
                              color: cs.primary,
                              width: 1.5,
                            ),
                          ),
                          prefixIconConstraints: BoxConstraints.tightFor(
                            width: controlHeight,
                            height: controlHeight,
                          ),
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            size: 18,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: menuWidth,
                      child: _MaintenanceToolbarMenu<String>(
                        label: _filter == null
                            ? l.maintenanceTaskAll
                            : _taskSchedulerLabel(context, _filter!),
                        tooltip: l.maintenanceTaskScheduler,
                        icon: Icons.filter_list_rounded,
                        controlHeight: controlHeight,
                        value: _filter?.name ?? '',
                        items: {
                          '': l.maintenanceTaskAll,
                          for (final scheduler in MachineTaskScheduler.values)
                            if (data.available.contains(scheduler) ||
                                _filter == scheduler ||
                                data.tasks.any(
                                  (task) => task.scheduler == scheduler,
                                ))
                              scheduler.name: _taskSchedulerLabel(
                                context,
                                scheduler,
                              ),
                        },
                        onSelected: (value) => setState(
                          () => _filter = MachineTaskScheduler.values
                              .where((scheduler) => scheduler.name == value)
                              .firstOrNull,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            if (tasks.isEmpty)
              _MaintenanceEmptyHint(
                message: query.isNotEmpty || _filter != null
                    ? l.maintenanceTaskNoMatches
                    : l.maintenanceTaskEmpty,
              )
            else
              _MaintenanceTable(
                maxBodyHeight: 360,
                headers: [
                  maintenanceLabel(context, '名称'),
                  l.maintenanceTaskScheduler,
                  maintenanceLabel(context, '状态'),
                  l.maintenanceTaskSchedule,
                  maintenanceLabel(context, '用户'),
                  l.maintenanceTaskLast,
                  l.maintenanceTaskNext,
                  maintenanceLabel(context, '执行结果'),
                  maintenanceLabel(context, '启动命令'),
                ],
                rows: [
                  for (final task in tasks)
                    OpenHandOperationalRankRow(
                      rowKey: task.id,
                      data: task,
                      value: 0,
                      cells: [
                        task.name,
                        _taskSchedulerLabel(context, task.scheduler),
                        _taskStateLabel(context, task.state),
                        _taskScheduleLabel(context, task),
                        task.owner == 'system'
                            ? maintenanceLabel(context, '系统')
                            : task.owner == 'user'
                            ? data.user
                            : task.owner,
                        task.lastRun.isEmpty
                            ? '—'
                            : maintenanceDetailValue(
                                context,
                                task.lastRun,
                                field: 'lastRun',
                              ),
                        task.nextRun.isEmpty
                            ? '—'
                            : maintenanceDetailValue(
                                context,
                                task.nextRun,
                                field: 'nextRun',
                              ),
                        task.result.isEmpty
                            ? '—'
                            : _taskStateLabel(context, task.result),
                        task.command,
                      ],
                      cellWidgets: [
                        null,
                        null,
                        _MaintenanceStatus(
                          label: _taskStateLabel(context, task.state),
                          color: task.state == 'failed'
                              ? OpenHandStatusColors.error
                              : task.enabled
                              ? OpenHandStatusColors.success
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                ],
                onRowTap: blocked
                    ? null
                    : (row) => _open(row.data! as MachineScheduledTask),
                rowActions: blocked
                    ? null
                    : (row) {
                        final task = row.data! as MachineScheduledTask;
                        return {
                          l.commonDetails: () => _open(task),
                          if (task.writable)
                            l.commonEdit: () => _open(task, edit: true),
                          if (task.writable &&
                              task.scheduler != MachineTaskScheduler.systemd)
                            l.commonDelete: () => _open(task, delete: true),
                        };
                      },
              ),
            if (data.issues.isNotEmpty)
              _MaintenanceSection(
                title: l.maintenanceCollectionError,
                icon: Icons.info_outline_rounded,
                child: _MaintenanceFields(
                  rows: [
                    for (final issue in data.issues.entries)
                      [
                        _taskIssueLabel(context, issue.key),
                        _taskError(context, MachineTaskException(issue.value)),
                      ],
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _MachineTaskDialog extends StatefulWidget {
  const _MachineTaskDialog({
    required this.platform,
    required this.snapshot,
    required this.task,
    required this.client,
    required this.edit,
  });
  final String platform;
  final MachineScheduledTaskSnapshot snapshot;
  final MachineScheduledTask? task;
  final MachineScheduledTaskClient client;
  final bool edit;
  @override
  State<_MachineTaskDialog> createState() => _MachineTaskDialogState();
}

class _MachineTaskDialogState extends State<_MachineTaskDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _schedule = TextEditingController(),
      _command = TextEditingController();
  final _definition = TextEditingController(),
      _arguments = TextEditingController(),
      _directory = TextEditingController();
  final _start = TextEditingController(),
      _days = TextEditingController(text: '1');
  MachineTaskDetail? _detail;
  Object? _error;
  bool _editing = false,
      _busy = false,
      _saving = false,
      _enabled = true,
      _native = false;
  bool _structured = false;
  bool get _cron =>
      (widget.task?.scheduler ??
          (widget.platform == 'Windows'
              ? MachineTaskScheduler.windows
              : MachineTaskScheduler.cron)) ==
      MachineTaskScheduler.cron;

  @override
  void initState() {
    super.initState();
    _editing = widget.edit;
    final task = widget.task;
    _name.text = task?.name ?? '';
    _schedule.text = task?.schedule ?? '0 9 * * *';
    _command.text = task?.command ?? '';
    _enabled = task?.enabled ?? true;
    _definition.text = task?.definition ?? '';
    _native = !_cron && task != null;
    final now =
        (DateTime.tryParse(widget.snapshot.collectedAt) ?? DateTime.now()).add(
          const Duration(days: 1),
        );
    _start.text =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}T09:00:00';
    if (task != null) _load();
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _schedule,
      _command,
      _definition,
      _arguments,
      _directory,
      _start,
      _days,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy || _saving) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final detail = await widget.client.detail(widget.task!);
      if (mounted) {
        setState(() {
          _detail = detail;
          _definition.text = detail.task.definition;
          final fields = detail.task.definition.isEmpty
              ? <String, String>{}
              : machineTaskEditableFields(detail.task);
          _structured = fields.isNotEmpty;
          _native = !_cron && !_structured;
          _schedule.text =
              fields['schedule'] ?? fields['interval'] ?? _schedule.text;
          _command.text = fields['command'] ?? _command.text;
          _arguments.text = fields['arguments'] ?? '';
          _directory.text = fields['directory'] ?? '';
          _start.text = fields['start'] ?? _start.text;
          _days.text = fields['days'] ?? '1';
          if (!detail.task.writable) _editing = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _editing = false;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save({bool delete = false}) async {
    if (_busy ||
        _saving ||
        (!delete && !(_form.currentState?.validate() ?? false))) {
      return;
    }
    final task = _detail?.task ?? widget.task;
    final l = AppLocalizations.of(context)!;
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: delete ? l.commonDelete : l.commonSave,
      message:
          '${delete ? l.maintenanceTaskDeleteConfirm : l.maintenanceTaskSaveConfirm}\n\n${task?.source ?? widget.snapshot.user}\n${_cron ? '${_schedule.text} ${_command.text}' : _name.text}',
      confirmLabel: delete ? l.commonDelete : l.commonSave,
      destructive: delete,
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (delete) {
        await widget.client.delete(task!);
      } else if (_cron) {
        await widget.client.saveCron(
          widget.snapshot,
          task,
          schedule: _schedule.text.trim(),
          command: _command.text,
          enabled: _enabled,
        );
      } else {
        final definition = _native
            ? _definition.text
            : task == null
            ? _windowsDefinition()
            : _structuredDefinition(task);
        await widget.client.saveNative(
          task,
          name: _name.text.trim(),
          definition: definition,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _structuredDefinition(MachineScheduledTask task) =>
      machineTaskApplyFields(task, {
        'schedule': _schedule.text.trim(),
        'interval': _schedule.text.trim(),
        'command': _command.text.trim(),
        'arguments': _arguments.text,
        'directory': _directory.text.trim(),
        'start': _start.text.trim(),
        'days': _days.text.trim(),
      });

  String _windowsDefinition() {
    String escape(String value) => xml.XmlText(value).toXmlString();
    return '''<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers><CalendarTrigger><StartBoundary>${escape(_start.text.trim())}</StartBoundary><Enabled>true</Enabled><ScheduleByDay><DaysInterval>${_days.text.trim()}</DaysInterval></ScheduleByDay></CalendarTrigger></Triggers>
  <Principals><Principal id="Author"><UserId>${escape(widget.snapshot.user)}</UserId><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals>
  <Settings><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy><DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false</StopIfGoingOnBatteries><StartWhenAvailable>true</StartWhenAvailable><Enabled>$_enabled</Enabled><ExecutionTimeLimit>PT1H</ExecutionTimeLimit></Settings>
  <Actions Context="Author"><Exec><Command>${escape(_command.text.trim())}</Command><Arguments>${escape(_arguments.text)}</Arguments>${_directory.text.trim().isEmpty ? '' : '<WorkingDirectory>${escape(_directory.text.trim())}</WorkingDirectory>'}</Exec></Actions>
</Task>''';
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int lines = 1,
    String? Function(String)? validate,
    bool required = true,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final border = OutlineInputBorder(
      borderRadius: kOpenHandBorderRadius8,
      borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: .65)),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Semantics(
          label: label,
          child: TextFormField(
            controller: controller,
            minLines: lines,
            maxLines: lines == 1 ? 1 : lines + 5,
            enabled: !_saving,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: _maintenanceFormFontSize,
              height: 1.4,
            ),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: cs.surfaceContainerLow,
              hoverColor: Colors.transparent,
              constraints: BoxConstraints(
                minHeight: _maintenanceFormControlHeightOf(context),
              ),
              contentPadding: const EdgeInsets.all(10),
              border: border,
              enabledBorder: border,
              disabledBorder: border,
              focusedBorder: border.copyWith(
                borderSide: BorderSide(color: cs.primary, width: 1.5),
              ),
              errorBorder: border.copyWith(
                borderSide: BorderSide(color: cs.error),
              ),
              focusedErrorBorder: border.copyWith(
                borderSide: BorderSide(color: cs.error, width: 1.5),
              ),
            ),
            validator: (value) => required && (value ?? '').trim().isEmpty
                ? AppLocalizations.of(context)!.maintenanceTaskValidation
                : validate?.call(value ?? ''),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final task = _detail?.task ?? widget.task;
    return PopScope(
      canPop: !_saving,
      child: buildOpenHandDialog(
        backgroundColor: cs.surfaceContainerLow,
        maxHeight: MediaQuery.sizeOf(context).height * .88,
        child: SizedBox(
          width: math.min(960, MediaQuery.sizeOf(context).width * .92),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MachineTerminalDialogHeader(
                icon: Icons.event_repeat_rounded,
                title: task == null
                    ? l.maintenanceTaskAdd
                    : _editing
                    ? l.maintenanceTaskEdit
                    : task.name,
                onClose: _saving ? () {} : () => Navigator.pop(context),
                trailingActions: [
                  if (task != null && !_editing)
                    _MachineTerminalIconButton(
                      tooltip: l.maintenanceRefreshDetails,
                      onPressed: _busy ? null : _load,
                      icon: Icons.refresh_rounded,
                    ),
                ],
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
                  child: Form(
                    key: _form,
                    child: _MaintenanceAnimatedColumn(
                      spacing: 12,
                      children: [
                        if (_busy && _detail == null)
                          _MaintenanceEmptyHint(
                            compact: true,
                            icon: Icons.downloading_rounded,
                            message: l.maintenanceLoadingDetails,
                          ),
                        if (_busy && _detail != null || _saving)
                          const LinearProgressIndicator(minHeight: 2),
                        if (_error != null)
                          _MaintenanceNotice(
                            error: true,
                            message: _taskError(context, _error!),
                          ),
                        if (!_busy && _editing) ...[
                          if (!_cron && task == null)
                            _field(_name, maintenanceLabel(context, '名称')),
                          if (!_cron && task == null && !_native)
                            FilledButton.icon(
                              style: _maintenanceTonalButtonStyle(context),
                              onPressed: _saving
                                  ? null
                                  : () => setState(() {
                                      _definition.text = _windowsDefinition();
                                      _native = true;
                                    }),
                              icon: const Icon(Icons.code_rounded, size: 16),
                              label: Text(l.maintenanceTaskNative),
                            ),
                          if (!_cron && task != null && _structured)
                            FilledButton.icon(
                              style: _maintenanceTonalButtonStyle(context),
                              onPressed: _saving
                                  ? null
                                  : () {
                                      if (!_native) {
                                        try {
                                          _definition.text =
                                              _structuredDefinition(task);
                                        } catch (error) {
                                          setState(() => _error = error);
                                          return;
                                        }
                                      }
                                      setState(() {
                                        _native = true;
                                        _structured = false;
                                      });
                                    },
                              icon: const Icon(Icons.code_rounded, size: 16),
                              label: Text(l.maintenanceTaskNative),
                            ),
                          if (_cron) ...[
                            _field(
                              _schedule,
                              l.maintenanceTaskCron,
                              validate: (value) =>
                                  machineTaskCronValid(value.trim())
                                  ? null
                                  : l.maintenanceTaskValidation,
                            ),
                            _field(
                              _command,
                              maintenanceLabel(context, '启动命令'),
                              lines: 3,
                              validate: (value) =>
                                  RegExp(r'[\r\n\x00]').hasMatch(value)
                                  ? l.maintenanceTaskValidation
                                  : null,
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(l.maintenanceTaskEnabled),
                              value: _enabled,
                              onChanged: _saving
                                  ? null
                                  : (value) => setState(() => _enabled = value),
                            ),
                          ] else if (!_native &&
                              task != null &&
                              task.scheduler !=
                                  MachineTaskScheduler.windows) ...[
                            _field(
                              _schedule,
                              task.scheduler == MachineTaskScheduler.launchd
                                  ? l.maintenanceTaskInterval
                                  : l.maintenanceTaskCalendar,
                            ),
                          ] else if (!_native) ...[
                            _field(_command, maintenanceLabel(context, '启动命令')),
                            _field(
                              _arguments,
                              l.maintenanceTaskArguments,
                              required: false,
                            ),
                            _field(
                              _directory,
                              l.maintenanceTaskWorkingDirectory,
                              required: false,
                            ),
                            _MaintenanceGrid(
                              maxColumns: 2,
                              minWidth: 280,
                              children: [
                                _field(
                                  _start,
                                  l.maintenanceTaskStart,
                                  validate: (value) =>
                                      DateTime.tryParse(value) == null
                                      ? l.maintenanceTaskValidation
                                      : null,
                                ),
                                _field(
                                  _days,
                                  l.maintenanceTaskDays,
                                  validate: (value) =>
                                      (int.tryParse(value) ?? 0) < 1 ||
                                          (int.tryParse(value) ?? 0) > 365
                                      ? l.maintenanceTaskValidation
                                      : null,
                                ),
                              ],
                            ),
                            if (task == null)
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(l.maintenanceTaskEnabled),
                                value: _enabled,
                                onChanged: _saving
                                    ? null
                                    : (value) =>
                                          setState(() => _enabled = value),
                              ),
                          ] else
                            _field(
                              _definition,
                              l.maintenanceTaskNative,
                              lines: 14,
                            ),
                        ],
                        if (!_editing && task != null) ...[
                          _MaintenanceCard(
                            key: const ValueKey('task-overview'),
                            title: l.maintenanceTaskOverview,
                            icon: Icons.event_repeat_rounded,
                            scrollBody: false,
                            wrapHeader: true,
                            trailing: _MaintenanceStatus(
                              label: _taskStateLabel(context, task.state),
                              color: task.state == 'failed'
                                  ? OpenHandStatusColors.error
                                  : task.enabled
                                  ? OpenHandStatusColors.success
                                  : cs.onSurfaceVariant,
                            ),
                            child: _MaintenanceFacts(
                              maxColumns: 1,
                              values: {
                                maintenanceLabel(context, '名称'): task.name,
                                l.maintenanceTaskScheduler: _taskSchedulerLabel(
                                  context,
                                  task.scheduler,
                                ),
                                l.maintenanceTaskSchedule: _taskScheduleLabel(
                                  context,
                                  task,
                                ),
                              },
                            ),
                          ),
                          _MaintenanceCard(
                            key: const ValueKey('task-execution'),
                            title: l.maintenanceTaskExecution,
                            icon: Icons.terminal_rounded,
                            accent: cs.tertiary,
                            scrollBody: false,
                            wrapHeader: true,
                            trailing: !task.writable
                                ? Tooltip(
                                    message: l.maintenanceTaskReadOnly,
                                    child: Icon(
                                      Icons.lock_outline_rounded,
                                      size: 18,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  )
                                : null,
                            child: _MaintenanceAnimatedColumn(
                              spacing: 12,
                              children: [
                                _MaintenanceFacts(
                                  maxColumns: 1,
                                  values: {
                                    maintenanceLabel(
                                      context,
                                      '用户',
                                    ): task.owner == 'user'
                                        ? widget.snapshot.user
                                        : task.owner == 'system'
                                        ? maintenanceLabel(context, '系统')
                                        : task.owner,
                                    maintenanceLabel(context, '配置文件'):
                                        task.source,
                                    maintenanceLabel(context, '启动命令'):
                                        task.command,
                                  },
                                ),
                                if (!task.writable)
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.info_outline_rounded,
                                        size: 16,
                                        color: cs.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          l.maintenanceTaskReadOnly,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: cs.onSurfaceVariant,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                          _MaintenanceSection(
                            key: const ValueKey('task-history'),
                            title: l.maintenanceTaskHistory,
                            icon: Icons.history_rounded,
                            accent: OpenHandStatusColors.info,
                            initiallyExpanded:
                                task.lastRun.isNotEmpty ||
                                task.nextRun.isNotEmpty ||
                                task.result.isNotEmpty,
                            subtitle:
                                task.lastRun.isEmpty &&
                                    task.nextRun.isEmpty &&
                                    task.result.isEmpty
                                ? l.maintenanceTaskHistoryUnavailable
                                : null,
                            child: _MaintenanceFacts(
                              values: {
                                l.maintenanceTaskLast: _taskFieldValue(
                                  context,
                                  'lastRun',
                                  task.lastRun,
                                ),
                                l.maintenanceTaskNext: _taskFieldValue(
                                  context,
                                  'nextRun',
                                  task.nextRun,
                                ),
                                maintenanceLabel(
                                  context,
                                  '执行结果',
                                ): _taskFieldValue(
                                  context,
                                  'Result',
                                  task.result,
                                ),
                              },
                            ),
                          ),
                          if (task.metadata.isNotEmpty)
                            _MaintenanceSection(
                              title: l.maintenanceTaskEnvironment,
                              icon: Icons.tune_rounded,
                              accent: cs.tertiary,
                              child: _MaintenanceFacts(
                                maxColumns: 1,
                                values: {
                                  for (final field in task.metadata.entries)
                                    if (field.value.isNotEmpty)
                                      _taskFieldLabel(context, field.key):
                                          task.scheduler ==
                                              MachineTaskScheduler.cron
                                          ? field.value
                                          : _taskFieldValue(
                                              context,
                                              field.key,
                                              field.value,
                                            ),
                                },
                              ),
                            ),
                          if (_detail?.status.isNotEmpty == true)
                            _MaintenanceSection(
                              title: maintenanceLabel(context, '状态详情'),
                              icon: Icons.monitor_heart_outlined,
                              accent: OpenHandStatusColors.info,
                              child: _MaintenanceReadout(
                                text: _detail!.status,
                                section: 'status',
                              ),
                            ),
                          _MaintenanceSection(
                            title: l.maintenanceTaskLogs,
                            icon: Icons.article_outlined,
                            subtitle: _detail?.logs.isNotEmpty == true
                                ? null
                                : _busy && _detail == null
                                ? l.maintenanceLoadingDetails
                                : l.maintenanceTaskNoLogs,
                            child: _detail?.logs.isNotEmpty == true
                                ? OpenHandConsoleText(
                                    title: l.maintenanceTaskLogs,
                                    text: _detail!.logs,
                                  )
                                : _MaintenanceEmptyHint(
                                    compact: true,
                                    message: l.maintenanceTaskNoLogs,
                                  ),
                          ),
                          if (_detail?.issues.isNotEmpty == true)
                            _MaintenanceSection(
                              title: l.maintenanceCollectionError,
                              icon: Icons.warning_amber_rounded,
                              accent: cs.error,
                              initiallyExpanded: true,
                              child: _MaintenanceFacts(
                                maxColumns: 1,
                                values: {
                                  for (final issue in _detail!.issues.entries)
                                    issue.key == 'logs'
                                        ? l.maintenanceTaskLogs
                                        : issue.key == 'definition'
                                        ? l.maintenanceTaskNative
                                        : maintenanceLabel(
                                            context,
                                            '状态详情',
                                          ): _taskError(
                                      context,
                                      MachineTaskException(issue.value),
                                    ),
                                },
                              ),
                            ),
                          if (task.definition.isNotEmpty)
                            _MaintenanceSection(
                              title: l.maintenanceTaskNative,
                              icon: Icons.code_rounded,
                              accent: cs.secondary,
                              child: SelectableText(
                                task.definition,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  height: 1.5,
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              buildOpenHandDialogActionsBar(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                actions: [
                  if (!_editing &&
                      task?.writable == true &&
                      !_busy &&
                      _error == null) ...[
                    if (task!.scheduler != MachineTaskScheduler.systemd)
                      OpenHandDialogActionButton.destructive(
                        onPressed: _saving ? null : () => _save(delete: true),
                        label: l.commonDelete,
                      ),
                    OpenHandDialogActionButton.primary(
                      onPressed: _saving
                          ? null
                          : () => setState(() => _editing = true),
                      label: l.commonEdit,
                    ),
                  ],
                  OpenHandDialogActionButton.secondary(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    label: l.commonClose,
                  ),
                  if (_editing)
                    OpenHandDialogActionButton.primary(
                      busy: _saving,
                      onPressed:
                          _busy ||
                              _saving ||
                              (_error is MachineTaskException &&
                                  const {
                                    'conflict',
                                    'verify',
                                    'rollback',
                                  }.contains(
                                    (_error as MachineTaskException).code,
                                  ))
                          ? null
                          : _save,
                      label: l.commonSave,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
