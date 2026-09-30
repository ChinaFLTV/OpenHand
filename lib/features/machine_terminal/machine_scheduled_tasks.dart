import 'dart:convert';

import 'package:xml/xml.dart';

import '../../shared/util/platform_shell.dart';

part 'machine_scheduled_tasks_commands.dart';

const machineScheduledTaskLimit = 512;
const machineScheduledTaskOutputLimit = 4 * 1024 * 1024;
const machineScheduledTaskDefinitionLimit = 128 * 1024;
const machineScheduledTaskTimeout = Duration(seconds: 45);

enum MachineTaskScheduler { cron, systemd, launchd, windows }

class MachineScheduledTask {
  const MachineScheduledTask({
    required this.scheduler,
    required this.id,
    required this.name,
    required this.source,
    required this.definition,
    this.schedule = '',
    this.command = '',
    this.owner = '',
    this.state = 'unknown',
    this.enabled = true,
    this.writable = false,
    this.line = -1,
    this.lastRun = '',
    this.nextRun = '',
    this.result = '',
    this.metadata = const {},
  });

  final MachineTaskScheduler scheduler;
  final String id, name, source, definition, schedule, command, owner, state;
  final String lastRun, nextRun, result;
  final bool enabled, writable;
  final int line;
  final Map<String, String> metadata;
}

class MachineTaskException implements Exception {
  const MachineTaskException(this.code, [this.detail = '']);
  final String code, detail;
  @override
  String toString() => detail.isEmpty ? code : '$code: $detail';
}

/// 任务定义和状态分开保存；配置中的命令、路径与用户数据不作翻译。
class MachineScheduledTaskSnapshot {
  factory MachineScheduledTaskSnapshot.parse(String output) {
    final records = _taskRecords(output);
    final tasks = <MachineScheduledTask>[];
    final documents = <String, String>{};
    final available = <MachineTaskScheduler>{};
    final issues = <String, String>{};
    var user = '', timezone = '', collectedAt = '';
    for (final record in records) {
      if (tasks.length >= machineScheduledTaskLimit &&
          const {
            'cron',
            'systemd',
            'launchd',
            'windows',
          }.contains(record.first)) {
        if (record.first == 'cron') documents[record[1]] = record[3];
        issues['limit'] = 'limit';
        continue;
      }
      switch (record.first) {
        case 'meta':
          if (record.length != 4) throw const MachineTaskException('format');
          user = record[1];
          timezone = record[2];
          collectedAt = record[3];
        case 'available':
          final scheduler = MachineTaskScheduler.values
              .where((value) => value.name == record[1])
              .firstOrNull;
          if (scheduler != null) available.add(scheduler);
        case 'issue':
          issues[record[1]] = record[2];
        case 'cron':
          if (record.length != 5) throw const MachineTaskException('format');
          final source = record[1], owner = record[2], content = record[3];
          documents[source] = content;
          final lines = content.split('\n');
          final environment = <String, String>{};
          for (var index = 0; index < lines.length; index++) {
            if (tasks.length >= machineScheduledTaskLimit) {
              issues['limit'] = 'limit';
              break;
            }
            var text = lines[index].trim();
            final disabled = text.startsWith(_disabledCronPrefix);
            if (disabled) text = text.substring(_disabledCronPrefix.length);
            if (text.isEmpty || text.startsWith('#')) continue;
            final variable = RegExp(
              r'^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$',
            ).firstMatch(text);
            if (variable != null) {
              environment[variable[1]!] = variable[2]!;
              continue;
            }
            final parsed = _parseCronLine(text, system: source.startsWith('/'));
            if (parsed == null) {
              issues['$source:${index + 1}'] = 'format';
              continue;
            }
            tasks.add(
              MachineScheduledTask(
                scheduler: MachineTaskScheduler.cron,
                id: '$source:${index + 1}',
                name: parsed.command,
                source: source,
                definition: content,
                schedule: parsed.schedule,
                command: parsed.command,
                owner: parsed.owner.isEmpty ? owner : parsed.owner,
                state: disabled ? 'disabled' : 'scheduled',
                enabled: !disabled,
                writable: record[4] == '1',
                line: index,
                metadata: Map.unmodifiable(environment),
              ),
            );
          }
        case 'systemd':
          if (record.length != 3) throw const MachineTaskException('format');
          for (final block in record[2].split(RegExp(r'\n\s*\n'))) {
            if (tasks.length >= machineScheduledTaskLimit) {
              issues['limit'] = 'limit';
              break;
            }
            final values = _taskProperties(block);
            final name = values['Id'] ?? '';
            if (!name.endsWith('.timer')) continue;
            final state = values['ActiveState'] ?? 'unknown';
            final schedule = [
              values['TimersCalendar'],
              values['TimersMonotonic'],
            ].whereType<String>().where((value) => value.isNotEmpty).join('\n');
            tasks.add(
              MachineScheduledTask(
                scheduler: MachineTaskScheduler.systemd,
                id: '${record[1]}/$name',
                name: name,
                source: values['FragmentPath'] ?? '',
                definition: '',
                schedule: schedule,
                command: values['Unit'] ?? '',
                owner: record[1],
                state: state,
                enabled: state == 'active',
                // 发行版提供的定时器保持只读；自定义定义按需核对写入权限。
                writable:
                    (values['FragmentPath'] ?? '').startsWith(
                      '/etc/systemd/system/',
                    ) ||
                    (values['FragmentPath'] ?? '').contains(
                      '/.config/systemd/user/',
                    ),
                lastRun: values['LastTriggerUSec'] ?? '',
                nextRun: values['NextElapseUSecRealtime'] ?? '',
                result: values['Result'] ?? '',
                metadata: values,
              ),
            );
          }
        case 'launchd':
          if (record.length != 5) throw const MachineTaskException('format');
          final document = XmlDocument.parse(record[2]);
          final values = _plistValues(document.rootElement.getElement('dict'));
          if (!values.containsKey('StartInterval') &&
              !values.containsKey('StartCalendarInterval')) {
            continue;
          }
          final label = values['Label'] ?? '';
          if (label.isEmpty) continue;
          final launch = record[4].split('\t');
          tasks.add(
            MachineScheduledTask(
              scheduler: MachineTaskScheduler.launchd,
              id: record[1],
              source: record[1],
              name: label,
              definition: record[2],
              owner: record[3],
              schedule:
                  values['StartCalendarInterval'] ??
                  values['StartInterval'] ??
                  '',
              command: values['ProgramArguments'] ?? values['Program'] ?? '',
              state: switch (launch.firstOrNull) {
                'running' => 'running',
                'loaded' => 'scheduled',
                'inactive' => 'inactive',
                _ => 'unknown',
              },
              enabled: const ['running', 'loaded'].contains(launch.firstOrNull),
              writable: launch.length > 2 && launch[2] == '1',
              result: launch.length > 1 ? launch[1] : '',
              metadata: values,
            ),
          );
        case 'windows':
          if (record.length != 9) throw const MachineTaskException('format');
          final document = XmlDocument.parse(record[2]);
          final root = document.rootElement;
          final principal = root
              .getElement('Principals')
              ?.getElement('Principal');
          final triggers =
              root.getElement('Triggers')?.childElements.toList() ?? [];
          final actions =
              root.getElement('Actions')?.childElements.toList() ?? [];
          tasks.add(
            MachineScheduledTask(
              scheduler: MachineTaskScheduler.windows,
              id: record[1],
              source: record[1],
              name: record[1].split('\\').last,
              definition: record[2],
              schedule: triggers
                  .map(
                    (node) =>
                        '${node.name.local}: ${node.getElement('StartBoundary')?.innerText ?? ''}',
                  )
                  .join('\n'),
              command: actions
                  .map(
                    (node) => [
                      node.getElement('Command')?.innerText,
                      node.getElement('Arguments')?.innerText,
                    ].whereType<String>().join(' '),
                  )
                  .join('\n'),
              owner:
                  principal?.getElement('UserId')?.innerText ??
                  principal?.getElement('GroupId')?.innerText ??
                  '',
              state:
                  const {
                    '0': 'unknown',
                    '1': 'disabled',
                    '2': 'queued',
                    '3': 'ready',
                    '4': 'running',
                  }[record[3]] ??
                  'unknown',
              enabled: record[4] == '1',
              writable: true,
              lastRun: record[5],
              nextRun: record[6],
              result: record[7],
              metadata: {
                'missedRuns': record[8],
                'description':
                    root
                        .getElement('RegistrationInfo')
                        ?.getElement('Description')
                        ?.innerText ??
                    '',
                'RunLevel': principal?.getElement('RunLevel')?.innerText ?? '',
                'logonType':
                    principal?.getElement('LogonType')?.innerText ?? '',
                for (final item
                    in root.getElement('Settings')?.childElements ??
                        <XmlElement>[])
                  if (item.childElements.isEmpty)
                    item.name.local: item.innerText,
              },
            ),
          );
      }
    }
    return MachineScheduledTaskSnapshot(
      tasks: List.unmodifiable(tasks),
      documents: Map.unmodifiable(documents),
      available: Set.unmodifiable(available),
      user: user,
      timezone: timezone,
      collectedAt: collectedAt,
      issues: Map.unmodifiable(issues),
    );
  }
  MachineScheduledTaskSnapshot({
    required this.tasks,
    required this.documents,
    required this.available,
    required this.user,
    required this.timezone,
    required this.collectedAt,
    required this.issues,
  });

  final List<MachineScheduledTask> tasks;
  final Map<String, String> documents;
  final Set<MachineTaskScheduler> available;
  final String user, timezone, collectedAt;
  final Map<String, String> issues;
}

const _disabledCronPrefix = '# OPENHAND_DISABLED ';

({String schedule, String owner, String command})? _parseCronLine(
  String line, {
  required bool system,
}) {
  final count = line.startsWith('@') ? 1 : 5;
  final prefix = List.filled(count + (system ? 1 : 0), r'(\S+)\s+').join();
  final pattern = RegExp(
    '^$prefix'
    r'(.+)$',
  );
  final match = pattern.firstMatch(line);
  if (match == null) return null;
  return (
    schedule: [for (var i = 1; i <= count; i++) match[i]!].join(' '),
    owner: system ? match[count + 1]! : '',
    command: match[match.groupCount]!,
  );
}

bool machineTaskCronValid(String value) {
  if (const {
    '@reboot',
    '@yearly',
    '@annually',
    '@monthly',
    '@weekly',
    '@daily',
    '@midnight',
    '@hourly',
  }.contains(value)) {
    return true;
  }
  final fields = value.trim().toUpperCase().split(RegExp(r'\s+'));
  if (fields.length != 5) return false;
  const ranges = [(0, 59), (0, 23), (1, 31), (1, 12), (0, 7)];
  for (var i = 0; i < fields.length; i++) {
    var field = fields[i];
    final names = i == 3
        ? [
            'JAN',
            'FEB',
            'MAR',
            'APR',
            'MAY',
            'JUN',
            'JUL',
            'AUG',
            'SEP',
            'OCT',
            'NOV',
            'DEC',
          ]
        : i == 4
        ? ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT']
        : <String>[];
    for (var n = 0; n < names.length; n++) {
      field = field.replaceAll(names[n], '${n + (i == 3 ? 1 : 0)}');
    }
    for (final part in field.split(',')) {
      final step = part.split('/');
      if (step.length > 2 ||
          (step.length == 2 && (int.tryParse(step[1]) ?? 0) < 1)) {
        return false;
      }
      if (step.first == '*') continue;
      final bounds = step.first.split('-');
      if (bounds.length > 2) return false;
      final first = int.tryParse(bounds.first),
          last = int.tryParse(bounds.last);
      if (first == null ||
          last == null ||
          first < ranges[i].$1 ||
          last > ranges[i].$2 ||
          first > last) {
        return false;
      }
    }
  }
  return true;
}

/// 仅替换选定行，完整保留其余任务、空行、注释和环境变量。
String machineTaskUpdateCron(
  String original,
  MachineScheduledTask? task, {
  String schedule = '',
  String command = '',
  bool enabled = true,
  bool delete = false,
}) {
  if (utf8.encode(original).length > machineScheduledTaskDefinitionLimit) {
    throw const MachineTaskException('limit');
  }
  if (!delete &&
      (!machineTaskCronValid(schedule) ||
          command.trim().isEmpty ||
          RegExp(r'[\r\n\x00]').hasMatch(command))) {
    throw const MachineTaskException('validation');
  }
  final lines = original.split('\n');
  if (task != null &&
      (task.definition != original ||
          task.line < 0 ||
          task.line >= lines.length)) {
    throw const MachineTaskException('conflict');
  }
  final line =
      '${enabled ? '' : _disabledCronPrefix}$schedule ${task != null && task.source.startsWith('/') ? '${task.owner} ' : ''}${command.trim()}';
  if (delete) {
    if (task == null) throw const MachineTaskException('validation');
    lines.removeAt(task.line);
  } else if (task == null) {
    if (lines.last.isEmpty) {
      lines.insert(lines.length - 1, line);
    } else {
      lines.add(line);
      lines.add('');
    }
  } else {
    lines[task.line] = line;
  }
  final result = lines.join('\n');
  return result.isNotEmpty && !result.endsWith('\n') ? '$result\n' : result;
}

Map<String, String> _taskProperties(String content) => {
  for (final line in content.split('\n'))
    if (line.indexOf('=') > 0)
      line.substring(0, line.indexOf('=')): line.substring(
        line.indexOf('=') + 1,
      ),
};

Map<String, String> _plistValues(XmlElement? dictionary) {
  if (dictionary == null) return {};
  final children = dictionary.childElements.toList();
  return {
    for (var i = 0; i + 1 < children.length; i += 2)
      children[i].innerText: switch (children[i + 1].name.local) {
        'true' => 'true',
        'false' => 'false',
        'dict' => _plistValues(
          children[i + 1],
        ).entries.map((e) => '${e.key}=${e.value}').join(', '),
        'array' =>
          children[i + 1].childElements
              .map(
                (e) => e.name.local == 'dict'
                    ? _plistValues(
                        e,
                      ).entries.map((v) => '${v.key}=${v.value}').join(', ')
                    : e.innerText,
              )
              .join('\n'),
        _ => children[i + 1].innerText,
      },
  };
}

List<List<String>> _taskRecords(String output) {
  if (output.length > machineScheduledTaskOutputLimit) {
    throw const MachineTaskException('limit');
  }
  final records = <List<String>>[];
  var complete = false;
  for (final line in output.replaceAll('\r', '').split('\n')) {
    if (line == '__OH_TASK_END__') {
      complete = true;
      continue;
    }
    if (!line.startsWith('__OH_TASK__\t') &&
        !line.startsWith('__OH_TASK_URI__\t')) {
      continue;
    }
    final fields = line.split('\t');
    final expected = const {
      'meta': 5,
      'available': 3,
      'issue': 4,
      'cron': 6,
      'systemd': 4,
      'launchd': 6,
      'windows': 10,
      'definition': 4,
      'status': 3,
      'logs': 3,
      'error': 4,
      'saved': 2,
    }[fields[1]];
    if (expected == null || fields.length != expected) {
      throw const MachineTaskException('format');
    }
    final uri = fields.first == '__OH_TASK_URI__';
    try {
      records.add([
        fields[1],
        ...fields
            .skip(2)
            .map(
              (field) => uri
                  ? Uri.decodeComponent(field)
                  : utf8.decode(base64Decode(field)),
            ),
      ]);
    } on FormatException {
      throw const MachineTaskException('format');
    }
  }
  if (!complete) throw const MachineTaskException('incomplete');
  final failure = records.reversed
      .where((row) => row.first == 'error')
      .firstOrNull;
  if (failure != null) {
    throw MachineTaskException(
      failure[1],
      failure.length > 2 ? failure[2] : '',
    );
  }
  return records;
}

class MachineTaskDetail {
  const MachineTaskDetail({
    required this.task,
    this.status = '',
    this.logs = '',
    this.issues = const {},
  });
  final MachineScheduledTask task;
  final String status, logs;
  final Map<String, String> issues;
}

/// 常见触发器提供结构化编辑，其他节点仍保留在原生定义中。
Map<String, String> machineTaskEditableFields(MachineScheduledTask task) {
  if (task.scheduler == MachineTaskScheduler.systemd) {
    final matches = RegExp(
      r'^OnCalendar=(.*)$',
      multiLine: true,
    ).allMatches(task.definition).toList();
    return matches.length == 1 ? {'schedule': matches.single[1]!} : {};
  }
  if (task.scheduler == MachineTaskScheduler.cron) return {};
  final root = XmlDocument.parse(task.definition).rootElement;
  if (task.scheduler == MachineTaskScheduler.launchd) {
    final value = _plistValues(root.getElement('dict'))['StartInterval'];
    return value != null && int.tryParse(value) != null
        ? {'interval': value}
        : {};
  }
  final triggers = root.getElement('Triggers')?.childElements.toList() ?? [];
  final actions = root.getElement('Actions')?.childElements.toList() ?? [];
  if (triggers.length != 1 ||
      actions.length != 1 ||
      triggers.single.name.local != 'CalendarTrigger' ||
      actions.single.name.local != 'Exec') {
    return {};
  }
  final days = triggers.single
      .getElement('ScheduleByDay')
      ?.getElement('DaysInterval')
      ?.innerText;
  if (days == null) return {};
  return {
    'start': triggers.single.getElement('StartBoundary')?.innerText ?? '',
    'days': days,
    'command': actions.single.getElement('Command')?.innerText ?? '',
    'arguments': actions.single.getElement('Arguments')?.innerText ?? '',
    'directory': actions.single.getElement('WorkingDirectory')?.innerText ?? '',
  };
}

String machineTaskApplyFields(
  MachineScheduledTask task,
  Map<String, String> fields,
) {
  if (machineTaskEditableFields(task).isEmpty) {
    throw const MachineTaskException('validation');
  }
  if (task.scheduler == MachineTaskScheduler.systemd) {
    final schedule = fields['schedule'] ?? '';
    if (schedule.trim().isEmpty || RegExp(r'[\r\n\x00]').hasMatch(schedule)) {
      throw const MachineTaskException('validation');
    }
    return task.definition.replaceFirst(
      RegExp(r'^OnCalendar=.*$', multiLine: true),
      'OnCalendar=$schedule',
    );
  }
  final document = XmlDocument.parse(task.definition);
  void replace(XmlElement parent, String name, String text) {
    final element = parent.getElement(name) ?? XmlElement(XmlName.parts(name));
    if (element.parent == null) parent.children.add(element);
    element.children
      ..clear()
      ..add(XmlText(text));
  }

  if (task.scheduler == MachineTaskScheduler.launchd) {
    final interval = int.tryParse(fields['interval'] ?? '') ?? 0;
    if (interval < 1 || interval > 2147483647) {
      throw const MachineTaskException('validation');
    }
    final elements = document.rootElement
        .getElement('dict')!
        .childElements
        .toList();
    final index = elements.indexWhere(
      (element) =>
          element.name.local == 'key' && element.innerText == 'StartInterval',
    );
    elements[index + 1].children
      ..clear()
      ..add(XmlText('$interval'));
  } else {
    final trigger = document.rootElement
        .getElement('Triggers')!
        .childElements
        .single;
    final action = document.rootElement
        .getElement('Actions')!
        .childElements
        .single;
    final days = int.tryParse(fields['days'] ?? '') ?? 0;
    if (days < 1 ||
        days > 365 ||
        DateTime.tryParse(fields['start'] ?? '') == null ||
        (fields['command'] ?? '').trim().isEmpty) {
      throw const MachineTaskException('validation');
    }
    replace(trigger, 'StartBoundary', fields['start']!);
    replace(trigger.getElement('ScheduleByDay')!, 'DaysInterval', '$days');
    replace(action, 'Command', fields['command']!);
    replace(action, 'Arguments', fields['arguments'] ?? '');
    if ((fields['directory'] ?? '').isNotEmpty) {
      replace(action, 'WorkingDirectory', fields['directory']!);
    } else {
      action.getElement('WorkingDirectory')?.remove();
    }
  }
  return document.toXmlString();
}

/// 调度器策略只生成命令，超时、取消和目标机器校验由现有终端通道处理。
class MachineScheduledTaskClient {
  const MachineScheduledTaskClient({required this.platform, required this.run});
  final String platform;
  final Future<String> Function(String) run;

  String get collectionCommand => platform == 'Windows'
      ? _taskWindowsPrelude + _taskWindowsCollect
      : '$_taskPosixPrelude$_taskCronCollect${platform == 'Darwin' ? _taskLaunchdCollect : _taskSystemdCollect}\nprintf "__OH_TASK_END__\\n"\n';
  Future<MachineScheduledTaskSnapshot> collect() async =>
      MachineScheduledTaskSnapshot.parse(await run(collectionCommand));

  Future<MachineTaskDetail> detail(MachineScheduledTask task) async {
    final output = await run(_taskDetailCommand(task, platform));
    final records = _taskRecords(output);
    final fresh = MachineScheduledTaskSnapshot.parse(
      output,
    ).tasks.where((value) => value.id == task.id).firstOrNull;
    if (fresh != null) task = fresh;
    var definition = task.definition,
        status = '',
        logs = '',
        writable = task.writable;
    final issues = <String, String>{};
    for (final row in records) {
      if (row.first == 'definition') {
        definition = row[1];
        writable = row[2] == '1';
      }
      if (row.first == 'status') status = row[1];
      if (row.first == 'logs') {
        logs = [logs, row[1]].where((value) => value.isNotEmpty).join('\n');
      }
      if (row.first == 'issue') issues[row[1]] = row[2];
    }
    return MachineTaskDetail(
      task: MachineScheduledTask(
        scheduler: task.scheduler,
        id: task.id,
        name: task.name,
        source: task.source,
        definition: definition,
        schedule: task.schedule,
        command: task.command,
        owner: task.owner,
        state: task.state,
        enabled: task.enabled,
        writable: writable,
        line: task.line,
        lastRun: task.lastRun,
        nextRun: task.nextRun,
        result: task.result,
        metadata: task.metadata,
      ),
      status: status,
      logs: logs,
      issues: issues,
    );
  }

  Future<void> saveCron(
    MachineScheduledTaskSnapshot snapshot,
    MachineScheduledTask? task, {
    required String schedule,
    required String command,
    required bool enabled,
  }) async {
    final source = task?.source ?? 'user:${snapshot.user}';
    final original = task?.definition ?? snapshot.documents[source];
    if (original == null || task != null && !task.writable) {
      throw const MachineTaskException('permission');
    }
    final content = machineTaskUpdateCron(
      original,
      task,
      schedule: schedule,
      command: command,
      enabled: enabled,
    );
    await _mutate(_taskCronWrite(source, original, content));
  }

  Future<void> saveNative(
    MachineScheduledTask? task, {
    required String name,
    required String definition,
  }) async {
    if (utf8.encode(definition).length > machineScheduledTaskDefinitionLimit ||
        definition.trim().isEmpty) {
      throw const MachineTaskException('validation');
    }
    if (task != null && !task.writable) {
      throw const MachineTaskException('permission');
    }
    if (task?.scheduler == MachineTaskScheduler.systemd) {
      if (!RegExp(r'^\[Timer\]\s*$', multiLine: true).hasMatch(definition)) {
        throw const MachineTaskException('validation');
      }
    } else {
      try {
        final document = XmlDocument.parse(definition);
        if (platform == 'Windows' &&
            document.rootElement.name.local != 'Task') {
          throw const FormatException();
        }
        if (platform == 'Darwin') {
          final values = _plistValues(document.rootElement.getElement('dict'));
          if (values['Label'] != name ||
              (!values.containsKey('StartInterval') &&
                  !values.containsKey('StartCalendarInterval'))) {
            throw const FormatException();
          }
        }
      } on XmlParserException {
        throw const MachineTaskException('validation');
      } on FormatException {
        throw const MachineTaskException('validation');
      }
    }
    await _mutate(
      _taskNativeWrite(
        task,
        platform: platform,
        name: name,
        definition: definition,
      ),
    );
  }

  Future<void> delete(MachineScheduledTask task) async {
    if (!task.writable) throw const MachineTaskException('permission');
    await _mutate(
      task.scheduler == MachineTaskScheduler.cron
          ? _taskCronWrite(
              task.source,
              task.definition,
              machineTaskUpdateCron(task.definition, task, delete: true),
            )
          : _taskNativeWrite(
              task,
              platform: platform,
              name: task.name,
              definition: '',
              delete: true,
            ),
    );
  }

  Future<void> _mutate(String command) async {
    final rows = _taskRecords(await run(command));
    if (!rows.any((row) => row.first == 'saved')) {
      throw const MachineTaskException('incomplete');
    }
  }
}
