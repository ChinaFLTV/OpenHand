import 'dart:convert';
import 'dart:io';

import 'package:openhand/features/machine_terminal/machine_maintenance.dart';
import 'package:openhand/features/machine_terminal/machine_maintenance_platform.dart';
import 'package:openhand/features/machine_terminal/machine_terminal_command_protocol.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  for (final fixture in [
    ('Linux', MachineTerminalCommandShell.posix, 'Linux'),
    ('Darwin', MachineTerminalCommandShell.posix, 'Darwin'),
    (
      'PS> echo OH_PS_\$env:OS\r\nOH_PS_Windows_NT\r\nOH_CMD_%OS%',
      MachineTerminalCommandShell.powershell,
      'Windows',
    ),
    (
      'C:\\>echo OH_CMD_%OS%\r\nOH_CMD_Windows_NT\r\nOH_PS_\$env:OS',
      MachineTerminalCommandShell.cmd,
      'Windows',
    ),
  ]) {
    final value = parseMachineTerminalShellProbe(fixture.$1);
    check(
      value.shell == fixture.$2 && value.platform == fixture.$3,
      '目标 Shell 识别错误',
    );
  }
  for (final shell in MachineTerminalCommandShell.values) {
    final payload = machineTerminalCommandPayload(
      command: 'echo 42',
      beginMarker: '校验开始',
      endMarker: '校验结束',
      shell: shell,
    );
    check(payload.contains('校验开始') && payload.contains('校验结束'), '命令协议缺少边界');
    if (shell == MachineTerminalCommandShell.powershell ||
        shell == MachineTerminalCommandShell.cmd) {
      check(!payload.contains('stty'), 'Windows 协议混入 POSIX 命令');
    }
  }
  final markers = MachineTerminalCommandMarkers('__开始__', '__结束__');
  final echoed = markers.locate('C:\\>echo __开始__\r\nC:\\>echo __结束__:0\r\n');
  check(echoed.outputStart < 0 && echoed.endIndex < 0, 'CMD 回显被误认为命令完成');
  final partial = markers.locate(
    '__开始__\r\n真实输出\r\nPS> Write-Output \'__结束__:0\'\r\n',
  );
  check(
    partial.outputStart >= 0 && partial.endIndex < 0,
    'PowerShell 回显被误认为结束标记',
  );
  final complete = markers.locate('__开始__\r\n真实输出\r\n__结束__:0\r\n');
  check(complete.endIndex > complete.outputStart, '完整命令帧未被识别');
  for (final shell in [
    MachineTerminalCommandShell.cmd,
    MachineTerminalCommandShell.powershell,
  ]) {
    final transport = MachineTerminalWindowsScript(
      'WScript.Echo("测试% ! & | < > 中文");',
      'test-token',
      shell,
    );
    check(transport.commands.every((line) => line.length < 4096), '脚本分块超出安全行长');
    check(
      transport.execute.contains('//T:25') &&
          transport.cleanup.contains('openhand-ops-test-token.js'),
      '脚本超时或清理路径缺失',
    );
  }
  final macOverview = MachineMaintenancePlatformAdapter.forPlatform(
    'Darwin',
  ).collect(0);
  final awkStart = macOverview.indexOf("awk 'function counter") + 5;
  final awkEnd = macOverview.indexOf("'\n", awkStart);
  final diskReader = await Process.start('awk', [
    macOverview.substring(awkStart, awkEnd),
  ]);
  diskReader.stdin.writeln(
    '"Statistics" = {"Operations (Read)"=3,"Bytes (Read)"=1024,"Total Time (Read)"=2000000}',
  );
  diskReader.stdin.writeln(
    '"Statistics" = {"Operations (Read)"=1,"Bytes (Read)"=512}',
  );
  await diskReader.stdin.close();
  final diskRows = (await utf8.decoder.bind(diskReader.stdout).join())
      .trim()
      .split('\n');
  final diskError = await utf8.decoder.bind(diskReader.stderr).join();
  check(await diskReader.exitCode == 0, '磁盘采集脚本检查失败：$diskError');
  check(diskRows.last.split(' ')[4] == '-1', '磁盘缺失字段沿用了上一条记录');
  final windows = MachineMaintenancePlatformAdapter.forPlatform('Windows');
  const process = MachineMaintenanceProcess(
    42,
    1,
    '运行',
    0,
    3,
    8192,
    16384,
    50,
    0,
    '测试进程',
    startToken: '20260929100000.000000+000',
  );
  final service = windows.servicesFor('Windows SCM')!;
  final snapshot = MachineMaintenanceSnapshot({
    'platform': 'Windows',
    'host': '测试主机',
    'boot': '20260929080000.000000+000',
  });
  final scripts = [
    for (var i = 0; i < 4; i++) windows.collect(i),
    windows.process(process),
    windows.bind(snapshot, service.command('带 空格服务')),
    for (final action in service.actions.values)
      windows.bind(snapshot, service.command('带 空格服务', action)),
    windows.bind(snapshot, windows.process(process, action: 'TERM')),
  ];
  final directory = await Directory.systemTemp.createTemp('openhand-跨平台检查-');
  try {
    final input = await File(
      '${directory.path}/scripts.json',
    ).writeAsString(jsonEncode(scripts));
    final runner = await File(
      '${directory.path}/runner.cjs',
    ).writeAsString(_windowsHarness);
    final output = await Process.run('node', [runner.path, input.path]);
    check(output.exitCode == 0, 'Windows 脚本执行检查失败：${output.stderr}');
    final results = (jsonDecode(output.stdout as String) as List)
        .cast<String>();
    for (var i = 0; i < 6; i++) {
      final data = MachineMaintenanceSnapshot.parse(results[i]);
      check(
        data.text('host') == '测试主机' && data.text('platform') == 'Windows',
        'Windows Unicode 协议解码失败',
      );
      if (i == 0) {
        check(data.memory['MemTotal'] == 8388608 * 1024, 'Windows 内存单位错误');
        check(
          data
              .text('interfaces')
              .contains('测试网卡\tactive\taa:bb\t—\t10.0.0.2, fe80::1'),
          'Windows 网卡结构化采集失败',
        );
        check(
          data.text('blocks').contains('测试磁盘\t107374182400 B'),
          'Windows 磁盘结构化采集失败',
        );
      }
      if (i == 1) {
        check(
          data.processes.single.startToken == process.startToken,
          'Windows 进程启动标识丢失',
        );
      }
    }
    check(
      !service.accepts('恶意"服务') && !service.accepts('恶意\n服务'),
      'Windows 服务名称校验失败',
    );
    check(windows.processActions(process).length == 1, 'Windows 显示了不支持的进程动作');
    for (final platform in ['Linux', 'Darwin']) {
      final adapter = MachineMaintenancePlatformAdapter.forPlatform(platform);
      for (var i = 0; i < 4; i++) {
        final shell = await Process.start('/bin/sh', ['-n']);
        shell.stdin.write(adapter.collect(i));
        await shell.stdin.close();
        check(await shell.exitCode == 0, '平台采集脚本存在语法错误：$platform');
      }
    }
    if (Platform.isMacOS) {
      final adapter = MachineMaintenancePlatformAdapter.forPlatform('Darwin');
      for (var i = 0; i < 3; i++) {
        final result = await Process.run('/bin/sh', [
          '-c',
          adapter.collect(i),
        ]).timeout(const Duration(seconds: 30));
        check(result.exitCode == 0, 'macOS 原生采集失败：${result.stderr}');
        final data = MachineMaintenanceSnapshot.parse(result.stdout as String);
        check(
          data.text('platform') == 'Darwin' && (data.uptime ?? 0) > 0,
          'macOS 身份或运行时间错误',
        );
        if (i == 0) {
          check((data.memory['MemTotal'] ?? 0) > 0, 'macOS 内存采集失败');
          check(data.cpuUsage(null) != null, 'macOS CPU 采集失败');
        }
        if (i == 1) {
          check(
            data.processes.isNotEmpty &&
                data.processes.first.startToken != null,
            'macOS 进程采集失败',
          );
        }
        stdout.writeln('macOS 分区 $i 实机采集通过。');
      }
    }
  } finally {
    await directory.delete(recursive: true);
  }
  stdout.writeln('目标识别、三类 Shell 协议、Windows WMI 模拟与跨平台采集检查通过。');
}

const _windowsHarness = r'''
const vm=require('node:vm'),fs=require('node:fs');
const scripts=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const birth='20260929100000.000000+000';
function item(values){values.Properties_=Object.keys(values).map(Name=>({Name,Value:values[Name]}));return values;}
const datasets={
Win32_OperatingSystem:[item({CSName:'测试主机',LastBootUpTime:'20260929080000.000000+000',LocalDateTime:'20260929120000.000000+000',TotalVisibleMemorySize:8388608,FreePhysicalMemory:4194304,Caption:'Windows 测试'})],
Win32_NetworkAdapterConfiguration:[item({Description:'测试网卡',IPEnabled:true,MACAddress:'aa:bb',IPAddress:['10.0.0.2','fe80::1'],DefaultIPGateway:['10.0.0.1']})],
Win32_DiskDrive:[item({DeviceID:'disk0',MediaType:'Fixed',Model:'测试磁盘',Size:'107374182400',InterfaceType:'SCSI'})],
Win32_Processor:[item({Name:'测试 CPU',NumberOfLogicalProcessors:4})],
Win32_PerfRawData_PerfOS_System:[item({SystemUpTime:0,Timestamp_Object:14400,Frequency_Object:1})],
Win32_PerfRawData_PerfOS_Processor:[item({Name:'_Total',PercentProcessorTime:100000000,Timestamp_Sys100NS:200000000})],
Win32_PageFileUsage:[item({AllocatedBaseSize:1024,CurrentUsage:512})],
Win32_LogicalDisk:[item({DeviceID:'C:',Size:107374182400,FreeSpace:53687091200})],
Win32_Process:[item({ProcessId:42,ParentProcessId:1,Name:'测试进程',Priority:8,ThreadCount:3,WorkingSetSize:8192,VirtualSize:16384,KernelModeTime:50,UserModeTime:60,CreationDate:birth,Terminate:()=>0})],
Win32_Service:[item({Name:'带 空格服务',DisplayName:'测试服务',State:'Stopped',StartMode:'Manual',StartService:()=>0,StopService:()=>0,ChangeStartMode:()=>0})]
};
const results=[];
for(const script of scripts){
let output=[];
const context={
VBArray:function(value){this.toArray=()=>value;},
Enumerator:function(items){let i=0;this.atEnd=()=>i>=items.length;this.moveNext=()=>i++;this.item=()=>items[i];},
GetObject:()=>({ExecQuery:(q)=>datasets[(q.match(/FROM\s+(\w+)/i)||[])[1]]||[],Get:()=>datasets.Win32_Service[0]}),
ActiveXObject:function(){this.Exec=()=>({Status:1,StdOut:{ReadAll:()=>''},StdErr:{ReadAll:()=>''},Terminate:()=>{}});},
WScript:{Echo:s=>output.push(String(s)),Quit:n=>{throw Error('脚本异常退出：'+n+' '+output.join('\n'));},Sleep:()=>{}}
};
new vm.Script(script).runInNewContext(context,{timeout:2000});results.push(output.join('\n'));
}
process.stdout.write(JSON.stringify(results));
''';
