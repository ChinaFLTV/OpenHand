import 'dart:convert';
import 'dart:io';

import 'package:openhand/features/machine_terminal/machine_scheduled_tasks.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

String record(String kind, List<String> fields) =>
    '__OH_TASK__\t$kind\t${fields.map((value) => base64Encode(utf8.encode(value))).join('\t')}\n';
String sample(String content, {String source = 'user:tester'}) =>
    '${record('meta', ['tester', 'UTC +0000', '2026-09-30T00:00:00Z'])}${record('available', ['cron'])}${record('cron', [source, 'tester', content, '1'])}__OH_TASK_END__\n';

Future<void> rejects(Future<void> Function() action, String code) async {
  try {
    await action();
  } on MachineTaskException catch (error) {
    check(error.code == code, '预期 $code，实际 ${error.code}');
    return;
  }
  throw StateError('未拒绝 $code');
}

Future<void> main(List<String> arguments) async {
  const original =
      '# 保留注释\nSHELL=/bin/bash\nCRON_TZ=Asia/Shanghai\n*/5 * * * * echo first\n*/5 * * * * echo first\n@reboot /opt/启动\n# OPENHAND_DISABLED 0 1 * * * /opt/暂停\n';
  final snapshot = MachineScheduledTaskSnapshot.parse(sample(original));
  check(snapshot.tasks.length == 4, 'Cron 任务数量错误');
  check(snapshot.tasks[0].metadata['CRON_TZ'] == 'Asia/Shanghai', '丢失任务时区');
  check(snapshot.tasks[0].id != snapshot.tasks[1].id, '重复任务身份冲突');
  check(!snapshot.tasks.last.enabled, '未识别禁用任务');
  final replacement = machineTaskUpdateCron(
    original,
    snapshot.tasks[1],
    schedule: '0 12 * * MON-FRI',
    command: r'echo "中文"; printf "100\%"',
    enabled: false,
  );
  check(
    replacement.startsWith(
      '# 保留注释\nSHELL=/bin/bash\nCRON_TZ=Asia/Shanghai\n*/5 * * * * echo first\n',
    ),
    '误改其他任务',
  );
  check(replacement.contains('# OPENHAND_DISABLED 0 12 * * MON-FRI'), '编辑状态丢失');
  check(
    machineTaskUpdateCron(
          original,
          snapshot.tasks[0],
          delete: true,
        ).split('echo first').length ==
        2,
    '删除操作影响重复任务',
  );
  for (final expression in [
    '*/5 * * * *',
    '0 9 * JAN,MAR MON-FRI',
    '@reboot',
    '0 0 1-31/2 * 0,7',
  ]) {
    check(machineTaskCronValid(expression), '有效表达式被拒绝：$expression');
  }
  for (final expression in [
    '60 * * * *',
    '* * * *',
    '* * 0 * *',
    '* * * 13 *',
    '*/0 * * * *',
    '* * * * FUNDAY',
    '@whatever',
    '* * * * *\nX=1',
  ]) {
    check(!machineTaskCronValid(expression), '无效表达式被接受：$expression');
  }
  await rejects(
    () async => machineTaskUpdateCron(
      original,
      snapshot.tasks.first,
      schedule: '* * * * *',
      command: 'echo ok\n* * * * * injected',
    ),
    'validation',
  );
  await rejects(
    () async => MachineScheduledTaskSnapshot.parse(
      sample(original).replaceAll('__OH_TASK_END__', ''),
    ),
    'incomplete',
  );
  final systemCron = MachineScheduledTaskSnapshot.parse(
    sample('0 4 * * * root /opt/备份\n', source: '/etc/cron.d/backup'),
  ).tasks.single;
  check(
    systemCron.owner == 'root' && systemCron.command == '/opt/备份',
    '系统 Cron 用户字段错误',
  );
  check(
    machineTaskUpdateCron(
      systemCron.definition,
      systemCron,
      schedule: '0 5 * * *',
      command: '/opt/new',
    ).contains('root /opt/new'),
    '系统任务丢失所属用户',
  );
  const timerDefinition =
      '[Unit]\nDescription=保留\n[Timer]\nOnCalendar=daily\nPersistent=true\n[Install]\nWantedBy=timers.target\n';
  const timer = MachineScheduledTask(
    scheduler: MachineTaskScheduler.systemd,
    id: 'system/example.timer',
    name: 'example.timer',
    source: '/etc/systemd/system/example.timer',
    definition: timerDefinition,
    owner: 'system',
    writable: true,
    command: 'example.service',
  );
  final timerEdited = machineTaskApplyFields(timer, {
    'schedule': 'Mon..Fri 09:00',
  });
  check(
    timerEdited == timerDefinition.replaceAll('daily', 'Mon..Fri 09:00'),
    'systemd 结构化编辑误改高级配置',
  );
  const plist =
      '<?xml version="1.0"?><plist version="1.0"><dict><key>Label</key><string>com.example.backup</string><key>StartInterval</key><integer>3600</integer><key>ProgramArguments</key><array><string>/usr/bin/printf</string><string>中文</string></array><key>KeepAlive</key><false/></dict></plist>';
  final mac = MachineScheduledTaskSnapshot.parse(
    '${record('launchd', ['/tmp/task.plist', plist, 'tester', 'loaded\t0\t1'])}__OH_TASK_END__',
  ).tasks.single;
  check(
    mac.schedule == '3600' && mac.command.contains('中文') && mac.writable,
    'launchd 配置解析错误',
  );
  final macEdited = machineTaskApplyFields(mac, {'interval': '1800'});
  check(
    macEdited.contains('<integer>1800</integer>') &&
        macEdited.contains('<false/>') &&
        macEdited.contains('中文'),
    'launchd 编辑丢失原生属性',
  );
  const windowsXml =
      '<Task xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task"><Triggers><CalendarTrigger><StartBoundary>2026-09-30T09:00:00</StartBoundary><ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay><RandomDelay>PT5M</RandomDelay></CalendarTrigger></Triggers><Principals><Principal><UserId>domain\\tester</UserId><LogonType>InteractiveToken</LogonType></Principal></Principals><Settings><ExecutionTimeLimit>PT2H</ExecutionTimeLimit><Hidden>true</Hidden></Settings><Actions><Exec><Command>C:\\backup.exe</Command><Arguments>--safe</Arguments><WorkingDirectory>C:\\data</WorkingDirectory></Exec></Actions></Task>';
  final windowsSample =
      '${record('windows', [r'\备份', windowsXml, '3', '1', '2026-09-29 09:00:00', '2026-10-01 09:00:00', '0', '2'])}__OH_TASK_END__';
  final windows = MachineScheduledTaskSnapshot.parse(
    windowsSample,
  ).tasks.single;
  check(
    windows.state == 'ready' && windows.metadata['missedRuns'] == '2',
    'Windows 状态解析错误',
  );
  final windowsEdited = machineTaskApplyFields(windows, {
    'start': '2026-10-01T10:00:00',
    'days': '2',
    'command': r'C:\backup.exe',
    'arguments': '--safe & 中文',
    'directory': '',
  });
  check(
    windowsEdited.contains('PT5M') &&
        windowsEdited.contains('PT2H') &&
        windowsEdited.contains('<Hidden>true</Hidden>') &&
        windowsEdited.contains('--safe &amp; 中文') &&
        !windowsEdited.contains('WorkingDirectory'),
    'Windows 编辑丢失原生配置或 XML 转义错误',
  );

  final directory = await Directory.systemTemp.createTemp(
    'openhand-scheduled-check-',
  );
  try {
    final bin = await Directory('${directory.path}/bin').create();
    final store = File('${directory.path}/crontab');
    await store.writeAsString(original);
    final cronTool = File('${bin.path}/crontab');
    await cronTool.writeAsString(r'''#!/bin/sh
if [ "$TASK_DENY" = 1 ]; then printf '拒绝访问\n' >&2; exit 1; fi
if [ "$1" = -u ]; then shift 2; fi
if [ "$1" = -l ]; then
  if [ -f "$TASK_STORE" ]; then cat "$TASK_STORE"; else printf 'no crontab for tester\n' >&2; exit 1; fi
else
  [ "$TASK_REJECT" != 1 ] || { printf '配置无效\n' >&2; exit 1; }
  cp "$1" "$TASK_STORE"
fi
''');
    await Process.run('chmod', ['+x', cronTool.path]);
    final commands = <String>[];
    final environment = <String, String>{
      'PATH': '${bin.path}:${Platform.environment['PATH']}',
      'TASK_STORE': store.path,
    };
    Future<String> run(String command) async {
      commands.add(command);
      final result = await Process.run('/bin/sh', [
        '-c',
        command,
      ], environment: environment).timeout(const Duration(seconds: 30));
      check(result.exitCode == 0, '隔离脚本失败：${result.stderr}\n${result.stdout}');
      return result.stdout as String;
    }

    final client = MachineScheduledTaskClient(platform: 'Linux', run: run);
    await client.saveCron(
      snapshot,
      snapshot.tasks[1],
      schedule: '0 5 * * *',
      command: r'printf "中文; $(touch NEVER)"',
      enabled: true,
    );
    check(
      (await store.readAsString()).contains('printf "中文; \$(touch NEVER)"'),
      '命令内容未原样保存',
    );
    check(!File('NEVER').existsSync(), '保存任务时执行了任务命令');
    await rejects(() => client.delete(snapshot.tasks.first), 'conflict');
    var current = MachineScheduledTaskSnapshot.parse(
      sample(await store.readAsString()),
    );
    await client.delete(current.tasks.last);
    check(!(await store.readAsString()).contains('/opt/暂停'), '删除任务失败');
    current = MachineScheduledTaskSnapshot.parse(
      sample(await store.readAsString()),
    );
    await client.saveCron(
      current,
      null,
      schedule: '@hourly',
      command: 'echo new',
      enabled: false,
    );
    check(
      (await store.readAsString()).endsWith(
        '# OPENHAND_DISABLED @hourly echo new\n',
      ),
      '新增任务失败',
    );
    await store.delete();
    current = MachineScheduledTaskSnapshot.parse(sample(''));
    await client.saveCron(
      current,
      null,
      schedule: '0 1 * * *',
      command: 'echo first',
      enabled: true,
    );
    check(await store.readAsString() == '0 1 * * * echo first\n', '首次创建用户任务失败');
    environment['TASK_DENY'] = '1';
    await rejects(
      () => client.saveCron(
        current,
        null,
        schedule: '0 1 * * *',
        command: 'echo denied',
        enabled: true,
      ),
      'permission',
    );
    environment.remove('TASK_DENY');
    environment['TASK_REJECT'] = '1';
    current = MachineScheduledTaskSnapshot.parse(
      sample(await store.readAsString()),
    );
    await rejects(() => client.delete(current.tasks.first), 'save');
    check(await store.readAsString() == '0 1 * * * echo first\n', '失败操作破坏任务');
    environment.remove('TASK_REJECT');
    final large =
        '${List.filled(600, '# 较长配置中的注释').join('\n')}\n0 1 * * * echo large\n';
    await store.writeAsString(large);
    current = MachineScheduledTaskSnapshot.parse(sample(large));
    await client.saveCron(
      current,
      current.tasks.single,
      schedule: '0 2 * * *',
      command: 'echo large',
      enabled: true,
    );
    check(
      (await store.readAsString()).startsWith(
        large.substring(0, large.indexOf('0 1')),
      ),
      '大配置保存损坏其他内容',
    );
    for (final platform in ['Linux', 'Darwin']) {
      final collector = MachineScheduledTaskClient(
        platform: platform,
        run: run,
      ).collectionCommand;
      final syntax = await Process.run('/bin/sh', ['-n', '-c', collector]);
      check(syntax.exitCode == 0, '$platform 采集脚本语法无效：${syntax.stderr}');
    }
    // 所有原生写入均重定向到临时目录，并由模拟调度器验证状态恢复。
    final nativeCommands = <String>[];
    final native = MachineScheduledTaskClient(
      platform: 'Linux',
      run: (command) async {
        nativeCommands.add(command);
        return '__OH_TASK__\tsaved\n__OH_TASK_END__';
      },
    );
    await native.saveNative(timer, name: timer.name, definition: timerEdited);
    await native.delete(timer);
    await native.detail(timer);
    for (final command in nativeCommands) {
      final syntax = await Process.run('/bin/sh', ['-n', '-c', command]);
      check(syntax.exitCode == 0, '原生修改脚本语法无效：${syntax.stderr}');
    }
    final units = await Directory('${directory.path}/units').create();
    final unit = File('${units.path}/example.timer');
    final serviceLog = File('${directory.path}/systemctl.log');
    environment['TASK_UNIT'] = unit.path;
    environment['TASK_SERVICE_LOG'] = serviceLog.path;
    environment['TASK_RESTART_MARKER'] = '${directory.path}/restart-failed';
    final systemctl = File('${bin.path}/systemctl');
    await systemctl.writeAsString(r'''#!/bin/sh
printf '%s\n' "$*" >> "$TASK_SERVICE_LOG"
case "$1" in --user|--system) shift;; esac
case "$1" in
  is-active) exit 0;;
  is-enabled) printf 'enabled\n';;
  show) printf 'LoadState=loaded\n';;
  restart)
    if [ "$TASK_FAIL_RESTART" = 1 ] && [ ! -f "$TASK_RESTART_MARKER" ]; then
      touch "$TASK_RESTART_MARKER"; printf '模拟重新加载失败\n' >&2; exit 1
    fi;;
  daemon-reload|enable|disable) exit 0;;
  *) exit 1;;
esac
''');
    final verify = File('${bin.path}/systemd-analyze');
    await verify.writeAsString('#!/bin/sh\nexit 0\n');
    await Process.run('chmod', ['+x', systemctl.path, verify.path]);
    Future<String> runNative(String command) =>
        run(command.replaceAll('/etc/systemd/system/', '${units.path}/'));
    final isolated = MachineScheduledTaskClient(
      platform: 'Linux',
      run: runNative,
    );
    await unit.writeAsString(timerDefinition);
    await isolated.saveNative(timer, name: timer.name, definition: timerEdited);
    check(await unit.readAsString() == timerEdited, '原生定时器配置未更新');
    await rejects(
      () =>
          isolated.saveNative(timer, name: timer.name, definition: timerEdited),
      'conflict',
    );
    await unit.writeAsString(timerDefinition);
    environment['TASK_FAIL_RESTART'] = '1';
    await rejects(
      () =>
          isolated.saveNative(timer, name: timer.name, definition: timerEdited),
      'save',
    );
    check(await unit.readAsString() == timerDefinition, '重新加载失败后未恢复原始定义');
    check(
      (await serviceLog.readAsString()).split('restart --').length >= 4,
      '缺少恢复后的重新加载',
    );
    environment.remove('TASK_FAIL_RESTART');
    await isolated.delete(timer);
    check(!unit.existsSync(), '删除定时器未移除目标配置');
    check(
      (await serviceLog.readAsString()).contains(
        'disable --now -- example.timer',
      ),
      '删除任务未停止后续调度',
    );
    await unit.writeAsString(timerDefinition);
    final foreign = File('${directory.path}/foreign');
    await foreign.writeAsString('不可覆盖');
    await unit.delete();
    await Link(unit.path).create(foreign.path);
    await rejects(
      () =>
          isolated.saveNative(timer, name: timer.name, definition: timerEdited),
      'permission',
    );
    check(await foreign.readAsString() == '不可覆盖', '符号链接写入保护失败');
    if (Platform.isMacOS) {
      final agents = await Directory('${directory.path}/agents').create();
      final agent = File('${agents.path}/com.example.backup.plist');
      final loaded = File('${directory.path}/launch-loaded');
      final launchctl = File('${bin.path}/launchctl');
      environment['TASK_LAUNCH_LOADED'] = loaded.path;
      environment['TASK_LAUNCH_FAILURE'] = '${directory.path}/launch-failed';
      await launchctl.writeAsString(r'''#!/bin/sh
case "$1" in
  print) [ -f "$TASK_LAUNCH_LOADED" ] || exit 113; printf 'state = running\nlast exit code = 0\n';;
  bootout) rm -f "$TASK_LAUNCH_LOADED";;
  bootstrap)
    if [ "$TASK_FAIL_LAUNCH" = 1 ] && [ ! -f "$TASK_LAUNCH_FAILURE" ]; then
      touch "$TASK_LAUNCH_FAILURE"; printf '模拟加载失败\n' >&2; exit 1
    fi
    touch "$TASK_LAUNCH_LOADED";;
  *) exit 1;;
esac
''');
      await Process.run('chmod', ['+x', launchctl.path]);
      await agent.writeAsString(plist);
      await loaded.writeAsString('');
      final client = MachineScheduledTaskClient(
        platform: 'Darwin',
        run: (command) => run(
          command.replaceAll(
            r'"$HOME"/Library/LaunchAgents',
            '"${agents.path}"',
          ),
        ),
      );
      final listed = MachineScheduledTaskSnapshot.parse(
        '${record('launchd', [agent.path, plist, 'tester', 'loaded\t0\t1'])}__OH_TASK_END__',
      ).tasks.single;
      final refreshed = (await client.detail(listed)).task;
      check(
        refreshed.state == 'running' &&
            refreshed.result == '0' &&
            refreshed.writable,
        '原生任务详情状态或权限未刷新',
      );
      final changed = machineTaskApplyFields(refreshed, {'interval': '1800'});
      await client.saveNative(
        refreshed,
        name: refreshed.name,
        definition: changed,
      );
      check(
        (await client.detail(refreshed)).task.schedule == '1800',
        '详情刷新未读取最新原生定义',
      );
      await rejects(
        () => client.saveNative(
          refreshed,
          name: refreshed.name,
          definition: changed,
        ),
        'conflict',
      );
      await agent.writeAsString(refreshed.definition);
      environment['TASK_FAIL_LAUNCH'] = '1';
      await rejects(
        () => client.saveNative(
          refreshed,
          name: refreshed.name,
          definition: changed,
        ),
        'save',
      );
      check(
        await agent.readAsString() == refreshed.definition &&
            loaded.existsSync(),
        '原生任务加载失败未恢复配置和运行状态',
      );
      environment.remove('TASK_FAIL_LAUNCH');
      await client.delete(refreshed);
      check(!agent.existsSync() && !loaded.existsSync(), '删除原生任务未停止调度或清理配置');
      stdout.writeln('macOS 原生任务隔离编辑、删除、详情刷新与失败恢复通过。');
    }
    final windowsCommands = <String>[];
    final windowsClient = MachineScheduledTaskClient(
      platform: 'Windows',
      run: (command) async {
        windowsCommands.add(command);
        return '__OH_TASK_URI__\tsaved\n__OH_TASK_END__';
      },
    );
    windowsCommands.add(windowsClient.collectionCommand);
    await windowsClient.saveNative(
      windows,
      name: windows.name,
      definition: windowsEdited,
    );
    await windowsClient.delete(windows);
    await windowsClient.saveNative(null, name: '新任务', definition: windowsXml);
    await windowsClient.detail(windows);
    final js = File('${directory.path}/check.js');
    await js.writeAsString(
      '''const vm=require("node:vm"); const scripts=${jsonEncode(windowsCommands)}; for(const source of scripts)new vm.Script(source);
const original=${jsonEncode(windowsXml)}, replacement=${jsonEncode(windowsEdited)}, path=${jsonEncode(windows.id)};
const task={Path:path, Xml:original, State:3, Enabled:true, LastRunTime:new Date(), NextRunTime:new Date(), LastTaskResult:0, NumberOfMissedRuns:2};
const tasks={[path]:task}, calls=[], output=[];
const folder={Path:"\\\\", GetTasks:()=>({Count:Object.keys(tasks).length,Item:i=>Object.values(tasks)[i-1]}), GetFolders:()=>({Count:0}),
 GetTask:name=>{const item=tasks[name.startsWith("\\\\")?name:"\\\\"+name];if(!item)throw {number:2};return item;},
 RegisterTask:(name,xml,flags)=>{calls.push(flags);if(flags!==1)tasks["\\\\"+name]={...task,Xml:xml};},
 DeleteTask:name=>{delete tasks["\\\\"+name];}};
const service={Connect:()=>{},GetFolder:()=>folder,NewTask:()=>({Principal:{LogonType:3}})};
function Enumerator(items){this.index=0;this.atEnd=()=>this.index>=items.length;this.item=()=>items[this.index];this.moveNext=()=>this.index++;}
const sandbox={Enumerator,GetObject:()=>({ExecQuery:()=>[{CSName:"test",LastBootUpTime:"boot",LocalDateTime:"20260930090000.000000+480"}]}),
ActiveXObject:function(name){if(name=="Schedule.Service")return service;if(name=="WScript.Network")return {UserDomain:"domain",UserName:"tester"};throw Error(name);},
WScript:{Echo:value=>output.push(value),Quit:()=>{throw Error("意外退出");}}};
vm.runInNewContext(scripts[0],sandbox);
if(!output.some(value=>value.includes(encodeURIComponent(path))))throw Error("未采集任务");
vm.runInNewContext(scripts[1],sandbox);
if(tasks[path].Xml!==replacement || calls.join(",")!=="1,52")throw Error("更新或原生校验流程错误");
tasks[path].Xml=original;vm.runInNewContext(scripts[2],sandbox);
if(tasks[path])throw Error("删除失败");
vm.runInNewContext(scripts[3],sandbox);
if(!tasks["\\\\新任务"] || calls.join(",")!=="1,52,1,34")throw Error("新增任务错误");
console.log("Windows 调度器模拟采集、校验、增改删通过。");''',
    );
    final node = await Process.run('node', [js.path]);
    check(node.exitCode == 0, 'Windows 脚本语法无效：${node.stderr}');
    stdout.write(node.stdout);
  } finally {
    await directory.delete(recursive: true);
  }
  if (arguments.contains('--live') && Platform.isMacOS) {
    final live = MachineScheduledTaskClient(
      platform: 'Darwin',
      run: (command) async {
        final process = await Process.start('/bin/sh', ['-c', command]);
        final output = process.stdout.transform(utf8.decoder).join();
        final errors = process.stderr.transform(utf8.decoder).join();
        final code = await process.exitCode.timeout(
          machineScheduledTaskTimeout,
          onTimeout: () {
            process.kill(ProcessSignal.sigkill);
            throw StateError('只读采集超时');
          },
        );
        check(code == 0, 'macOS 只读采集失败：${await errors}');
        return output;
      },
    );
    final report = await live.collect();
    check(
      report.available.contains(MachineTaskScheduler.launchd),
      'macOS 未识别 launchd',
    );
    check(
      report.tasks.any(
        (task) => task.scheduler == MachineTaskScheduler.launchd,
      ),
      'macOS 未采集到原生定时任务',
    );
    final task = report.tasks.firstWhere(
      (value) => value.scheduler == MachineTaskScheduler.launchd,
    );
    final detail = await live.detail(task);
    check(
      detail.task.id == task.id && detail.task.definition.isNotEmpty,
      'macOS 实机详情未返回原生配置',
    );
    stdout.writeln(
      'macOS 实机只读采集通过：${report.tasks.length} 个任务，${report.issues.length} 项不可用来源。',
    );
  }
  stdout.writeln('定时任务解析、六类 Cron 边界、三平台原生配置保留、隔离增改删、并发冲突、权限与失败保护检查通过。');
}
