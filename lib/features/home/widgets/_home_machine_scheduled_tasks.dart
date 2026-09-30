part of '../openhand_home_page.dart';

String _taskSchedulerLabel(BuildContext context, MachineTaskScheduler value) =>
    value == MachineTaskScheduler.windows
    ? AppLocalizations.of(context)!.maintenanceTaskWindows
    : value == MachineTaskScheduler.cron
    ? 'Cron'
    : value.name;

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
    'StartInterval' => l.maintenanceTaskInterval,
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
    return '${l.maintenanceTaskInterval}: $value';
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
          _MaintenanceValue(
            value: '${tasks.length}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          _MachineTerminalIconButton(
            tooltip: l.maintenanceRefreshSection,
            onPressed: !widget.enabled || _busy || _overlay ? null : _refresh,
            icon: Icons.refresh_rounded,
          ),
          OutlinedButton.icon(
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
                  centered: true,
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
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: math.min(320, constraints.maxWidth),
                    child: TextField(
                      controller: _search,
                      textAlignVertical: TextAlignVertical.center,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: l.maintenanceTaskSearch,
                        isDense: true,
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: math.min(250, constraints.maxWidth),
                    child: DropdownButtonFormField<MachineTaskScheduler?>(
                      initialValue: _filter,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: l.maintenanceTaskScheduler,
                        isDense: true,
                      ),
                      items: [
                        DropdownMenuItem(child: Text(l.maintenanceTaskAll)),
                        for (final scheduler in MachineTaskScheduler.values)
                          if (data.tasks.any(
                            (task) => task.scheduler == scheduler,
                          ))
                            DropdownMenuItem(
                              value: scheduler,
                              child: Text(
                                _taskSchedulerLabel(context, scheduler),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                      ],
                      onChanged: (value) => setState(() => _filter = value),
                    ),
                  ),
                ],
              ),
            ),
            _MaintenanceFields(
              rows: [
                [l.maintenanceTaskTotal, '${data.tasks.length}'],
                [
                  l.maintenanceTaskEnabled,
                  '${data.tasks.where((task) => task.enabled).length}',
                ],
                [
                  maintenanceLabel(context, '时区'),
                  data.timezone.isEmpty ? '—' : data.timezone,
                ],
                [
                  l.maintenanceTaskSampled,
                  data.collectedAt.isEmpty ? '—' : data.collectedAt,
                ],
              ],
            ),
            if (tasks.isEmpty)
              _MaintenanceEmptyHint(message: l.maintenanceTaskEmpty)
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
                        task.lastRun.isEmpty ? '—' : task.lastRun,
                        task.nextRun.isEmpty ? '—' : task.nextRun,
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
                        issue.key,
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
  }) => TextFormField(
    controller: controller,
    minLines: lines,
    maxLines: lines == 1 ? 1 : lines + 5,
    enabled: !_saving,
    decoration: InputDecoration(
      labelText: label,
      alignLabelWithHint: lines > 1,
    ),
    validator: (value) => required && (value ?? '').trim().isEmpty
        ? AppLocalizations.of(context)!.maintenanceTaskValidation
        : validate?.call(value ?? ''),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final task = _detail?.task ?? widget.task;
    return PopScope(
      canPop: !_saving,
      child: buildOpenHandDialog(
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
                  padding: _maintenanceDetailPadding,
                  child: Form(
                    key: _form,
                    child: _MaintenanceAnimatedColumn(
                      spacing: 12,
                      children: [
                        if (_busy && _detail == null)
                          SizedBox(
                            height: 180,
                            child: Center(
                              child: _MaintenanceEmptyHint(
                                centered: true,
                                message: l.maintenanceLoadingDetails,
                              ),
                            ),
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
                            OutlinedButton.icon(
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
                            OutlinedButton.icon(
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
                            SwitchListTile.adaptive(
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
                              SwitchListTile.adaptive(
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
                        if (!_busy && !_editing && task != null) ...[
                          _MaintenanceFields(
                            rows: [
                              [
                                l.maintenanceTaskScheduler,
                                _taskSchedulerLabel(context, task.scheduler),
                              ],
                              [
                                maintenanceLabel(context, '状态'),
                                _taskStateLabel(context, task.state),
                              ],
                              [
                                l.maintenanceTaskSchedule,
                                _taskScheduleLabel(context, task),
                              ],
                              [
                                maintenanceLabel(context, '用户'),
                                task.owner == 'user'
                                    ? widget.snapshot.user
                                    : task.owner,
                              ],
                              [maintenanceLabel(context, '配置文件'), task.source],
                              [
                                maintenanceLabel(context, '启动命令'),
                                task.command.isEmpty ? '—' : task.command,
                              ],
                              [
                                l.maintenanceTaskLast,
                                task.lastRun.isEmpty ? '—' : task.lastRun,
                              ],
                              [
                                l.maintenanceTaskNext,
                                task.nextRun.isEmpty ? '—' : task.nextRun,
                              ],
                              [
                                maintenanceLabel(context, '执行结果'),
                                task.result.isEmpty
                                    ? '—'
                                    : _taskStateLabel(context, task.result),
                              ],
                            ],
                          ),
                          if (!task.writable)
                            _MaintenanceNotice(
                              message: l.maintenanceTaskReadOnly,
                            ),
                          if (task.metadata.isNotEmpty)
                            _MaintenanceSection(
                              title: l.maintenanceTaskEnvironment,
                              child: _MaintenanceFields(
                                rows: [
                                  for (final field in task.metadata.entries)
                                    if (field.value.isNotEmpty)
                                      [
                                        task.scheduler ==
                                                MachineTaskScheduler.cron
                                            ? field.key
                                            : _taskFieldLabel(
                                                context,
                                                field.key,
                                              ),
                                        task.scheduler ==
                                                MachineTaskScheduler.cron
                                            ? field.value
                                            : _taskStateLabel(
                                                context,
                                                field.value,
                                              ),
                                      ],
                                ],
                              ),
                            ),
                          if (_detail?.status.isNotEmpty == true)
                            _MaintenanceSection(
                              title: maintenanceLabel(context, '状态详情'),
                              child: _MaintenanceReadout(
                                text: _detail!.status,
                                section: 'status',
                              ),
                            ),
                          _MaintenanceCard(
                            title: l.maintenanceTaskLogs,
                            icon: Icons.article_outlined,
                            scrollBody: false,
                            child: _detail?.logs.isNotEmpty == true
                                ? OpenHandConsoleText(
                                    title: l.maintenanceTaskLogs,
                                    text: _detail!.logs,
                                  )
                                : _MaintenanceEmptyHint(
                                    message: l.maintenanceTaskNoLogs,
                                  ),
                          ),
                          if (_detail?.issues.isNotEmpty == true)
                            _MaintenanceSection(
                              title: l.maintenanceCollectionError,
                              child: _MaintenanceFields(
                                rows: [
                                  for (final issue in _detail!.issues.entries)
                                    [
                                      issue.key == 'logs'
                                          ? l.maintenanceTaskLogs
                                          : issue.key == 'definition'
                                          ? l.maintenanceTaskNative
                                          : maintenanceLabel(context, '状态详情'),
                                      _taskError(
                                        context,
                                        MachineTaskException(issue.value),
                                      ),
                                    ],
                                ],
                              ),
                            ),
                          if (task.definition.isNotEmpty)
                            _MaintenanceSection(
                              title: l.maintenanceTaskNative,
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
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                child: OverflowBar(
                  spacing: 10,
                  overflowSpacing: 8,
                  alignment: MainAxisAlignment.end,
                  children: [
                    if (!_editing &&
                        task?.writable == true &&
                        !_busy &&
                        _error == null) ...[
                      TextButton(
                        onPressed: _saving ? null : () => _save(delete: true),
                        child: Text(l.commonDelete),
                      ),
                      OutlinedButton(
                        onPressed: () => setState(() => _editing = true),
                        child: Text(l.commonEdit),
                      ),
                    ],
                    TextButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: Text(l.commonClose),
                    ),
                    if (_editing)
                      FilledButton(
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
                        child: Text(l.commonSave),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
