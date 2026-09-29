import 'dart:convert';
import 'dart:io';

import 'package:openhand/features/machine_terminal/machine_maintenance.dart';
import 'package:openhand/features/machine_terminal/machine_maintenance_parallel.dart';
import 'package:openhand/features/machine_terminal/machine_maintenance_readout.dart';
import 'package:openhand/features/machine_terminal/machine_maintenance_platform.dart';
import 'package:openhand/features/machine_terminal/machine_terminal_command_protocol.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  for (final sample in [
    ('OH_SHELL_zsh 5.9\r\n', MachineTerminalCommandShell.posix, 'zsh 5.9'),
    (
      'OH_SHELL_bash 5.2.15(1)-release',
      MachineTerminalCommandShell.posix,
      'bash 5.2.15(1)-release',
    ),
    (
      'OH_SHELL_PowerShell 7.4.6',
      MachineTerminalCommandShell.powershell,
      'PowerShell 7.4.6',
    ),
    (
      'Microsoft Windows [版本 10.0.26100.1]',
      MachineTerminalCommandShell.cmd,
      'CMD 10.0.26100.1',
    ),
  ]) {
    check(
      parseMachineTerminalShellDetails(sample.$1, sample.$2) == sample.$3,
      'Shell 版本解析错误',
    );
  }
  check(
    parseMachineTerminalShellDetails(
          'echo OH_SHELL_fake',
          MachineTerminalCommandShell.posix,
        ) ==
        null,
    '不能把回显当作 Shell 信息',
  );
  if (!Platform.isWindows) {
    final probe = await Process.run('/bin/bash', [
      '-c',
      machineTerminalShellDetailsCommand(MachineTerminalCommandShell.posix),
    ]);
    check(
      parseMachineTerminalShellDetails(
            probe.stdout as String,
            MachineTerminalCommandShell.posix,
          )?.startsWith('bash ') ??
          false,
      '真实 Bash 版本读取失败',
    );
  }

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
  for (final output in [
    "echo '__READY__'\n",
    "stty -echo; printf '__READY__'\n",
    '__READY__',
    '__READY__\r',
    'PS> __READY__\n',
  ]) {
    check(
      !machineTerminalHasOutputMarker(output, '__READY__'),
      '命令回显或不完整标记被误判为就绪',
    );
  }
  for (final output in ['__READY__\n', '前置输出\r\n__READY__\r\n']) {
    check(machineTerminalHasOutputMarker(output, '__READY__'), '完整就绪标记未被识别');
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
  for (final platform in ['Linux', 'Darwin', 'Windows']) {
    for (var tab = 0; tab < 7; tab++) {
      final command = MachineMaintenancePlatformAdapter.forPlatform(
        platform,
      ).collect(tab, workers: 8);
      check(
        utf8.encode(command).length <= 16 * 1024,
        '并行脚本超出终端传输上限：$platform / $tab',
      );
    }
  }
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
    for (var i = 0; i < 7; i++) windows.collect(i),
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
    check(
      MachineMaintenanceSnapshot.parse(results[4]).text('gpu_details').length >
          120000,
      'Windows 大 XML 未完整读取',
    );
    for (var i = 0; i < 7; i++) {
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
    final parallelInput = await File('${directory.path}/parallel.json')
        .writeAsString(
          jsonEncode([
            for (var i = 0; i < 7; i++) windows.collect(i, workers: 4),
            parallelWindowsMaintenanceCommand(
              r'''var wmi=GetObject("winmgmts:!\\\\.\\root\\cimv2");
function fail(message){throw Error(message);}
function emit(key,value){ohEcho("__OH_OPS_"+key+"__\n"+value);}''',
              [for (var i = 0; i < 8; i++) 'ohOut.Write("文件记录$i\\n");'],
              8,
              rawOutput: true,
            ),
          ]),
        );
    final parallelRunner = await File('${directory.path}/parallel.cjs')
        .writeAsString(
          _windowsHarness.substring(
                0,
                _windowsHarness.indexOf('const results=[];'),
              ) +
              _windowsParallelHarness,
        );
    final parallelOutput = await Process.run('node', [
      parallelRunner.path,
      parallelInput.path,
    ]);
    check(
      parallelOutput.exitCode == 0,
      'Windows 并行采集模拟失败：${parallelOutput.stderr}',
    );
    final parallelResults =
        (jsonDecode(parallelOutput.stdout as String) as List).cast<String>();
    check(
      !parallelResults.last.contains('__OH_OPS_') &&
          parallelResults.last.contains('文件记录7'),
      'Windows 文件读取协议混入运维标记或遗漏分片',
    );
    for (var i = 0; i < 7; i++) {
      final parallel = MachineMaintenanceSnapshot.parse(parallelResults[i]);
      final serial = MachineMaintenanceSnapshot.parse(results[i]);
      check(
        parallel.sections.keys.toSet().containsAll(serial.sections.keys),
        'Windows 并行采集遗漏数据段',
      );
      for (final key in serial.sections.keys) {
        check(
          parallel.text(key) == serial.text(key),
          'Windows 并行采集结果不一致：$i / $key',
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
      for (var i = 0; i < 7; i++) {
        final shell = await Process.start('/bin/sh', ['-n']);
        shell.stdin.write(adapter.collect(i));
        await shell.stdin.close();
        check(await shell.exitCode == 0, '平台采集脚本存在语法错误：$platform');
      }
    }
    if (Platform.isMacOS) {
      final adapter = MachineMaintenancePlatformAdapter.forPlatform('Darwin');
      for (final i in [0, 1, 2, 3, 4, 5, 6]) {
        final result = await Process.run('/bin/sh', [
          '-c',
          adapter.collect(i, workers: i == 3 ? 4 : null),
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
        if (i == 3) {
          final routes = MachineMaintenanceReadout.parse(
            data.text('routes'),
            'routes',
          );
          check(
            !routes.raw &&
                routes.rows.isNotEmpty &&
                routes.headers.contains('网关'),
            'macOS 实机路由未正确结构化',
          );
          for (final key in [
            'routes',
            'addresses',
            'neighbors',
            'network_stats',
            'socket_details',
            'dns_status',
            'firewall',
            'firewall_rules',
            'firewall_nat',
            'firewall_states',
          ]) {
            check(data.sections.containsKey(key), '网络诊断缺少采集分区：$key');
          }
        }
        if (i == 6) {
          for (final key in machineHealthSections) {
            check(
              int.tryParse(data.text('health_${key}_status').trim()) != null,
              '健康采集缺少明确状态：$key',
            );
          }
        }
        if (i == 4) {
          final gpu = MachineGpuSnapshot.parse(data.sections);
          check(gpu.devices.isNotEmpty, 'macOS GPU 设备解析失败');
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
let output=[];const tempFiles=new Map();
const context={
VBArray:function(value){this.toArray=()=>value;},
Enumerator:function(items){let i=0;this.atEnd=()=>i>=items.length;this.moveNext=()=>i++;this.item=()=>items[i];},
GetObject:()=>({ExecQuery:(q)=>datasets[(q.match(/FROM\s+(\w+)/i)||[])[1]]||[],Get:()=>datasets.Win32_Service[0]}),
ActiveXObject:function(name){
  if(name==='Scripting.FileSystemObject'){
    this.GetSpecialFolder=()=>'/tmp';this.GetTempName=()=>String(tempFiles.size)+'.tmp';this.BuildPath=(a,b)=>a+'/'+b;
    this.FileExists=p=>tempFiles.has(p);this.DeleteFile=p=>tempFiles.delete(p);
    this.OpenTextFile=p=>({AtEndOfStream:false,Read(n){const value=tempFiles.get(p)||'';this.AtEndOfStream=value.length<=n;return value.slice(0,n);},Close:()=>{}});
  }else{
    this.Environment=()=>()=>"";
    this.Exec=text=>{const path=(text.match(/>"([^"]+)"/)||[])[1];if(path)tempFiles.set(path,text.includes('nvidia-smi -q -x')?'<nvidia_smi_log><gpu><uuid>GPU-LARGE</uuid><info>'+ 'x'.repeat(130000)+'</info></gpu></nvidia_smi_log>':'');return {Status:1,ExitCode:0,StdOut:{ReadAll:()=>''},StdErr:{ReadAll:()=>''},Terminate:()=>{}};};
  }
},
WScript:{Echo:s=>output.push(String(s)),Quit:n=>{throw Error('脚本异常退出：'+n+' '+output.join('\n'));},Sleep:()=>{}}
};
new vm.Script(script).runInNewContext(context,{timeout:2000});if(tempFiles.size)throw Error('GPU 临时文件未清理');results.push(output.join('\n'));
}
process.stdout.write(JSON.stringify(results));
''';

const _windowsParallelHarness = r'''
const results=[];
for(const script of scripts){
  const files=new Map(),processes=new Map(),pending=[];
  const killed=[];let nextPid=200,tick=0,peak=0,guard=null,guardSource=null,failGuard=false;
  const owner={ProcessId:100,ParentProcessId:90,CreationDate:birth,CommandLine:'cscript C:\\ops.js'};
  processes.set(100,owner);processes.set(90,{ProcessId:90,ParentProcessId:0,CreationDate:'20260929090000.000000+000'});
  const normalize=p=>String(p).replace(/\\+/g,'\\');
  function filesystem(){return {
    BuildPath:(a,b)=>a+'\\'+b,GetSpecialFolder:()=> 'C:\\临时目录',GetTempName:()=> '私有采集',CreateFolder:()=>{},
    CreateTextFile:(path,overwrite,unicode)=>{path=normalize(path);let value='';files.set(path,{value,unicode});return {Write:s=>{value+=s;files.set(path,{value,unicode});},WriteLine:s=>{value+=s+'\r\n';files.set(path,{value,unicode});},Close:()=>{}};},
    OpenTextFile:(path,mode,create,format)=>{const entry=files.get(normalize(path));if(!entry)throw Error('文件不存在：'+path);if(format==-1 && !entry.unicode)throw Error('Unicode 文件编码不匹配');return {AtEndOfStream:!entry.value.length,Read(n){this.AtEndOfStream=entry.value.length<=n;return entry.value.slice(0,n);},ReadAll:()=>entry.value,Close:()=>{}};},
    FileExists:path=>files.has(normalize(path)),
    DeleteFile:path=>files.delete(normalize(path)),
    GetFolder:dir=>({Files:[...files.keys()].filter(p=>p.startsWith(normalize(dir)+'\\')).map(Path=>({Path}))}),
    DeleteFolder:dir=>{for(const key of files.keys())if(key.startsWith(normalize(dir)+'\\'))files.delete(key);},
  };}
  function wmi(path){
    if(!path.includes('\\\\.\\root\\cimv2'))throw Error('WMI 命名空间转义错误：'+JSON.stringify(path));
    return {
      ExecQuery:q=>q.includes("Name='cscript.exe'") ? [owner] : datasets[(q.match(/FROM\s+(\w+)/i)||[])[1]]||[],
      Get:q=>{const id=Number((q.match(/Handle='(\d+)'/)||[])[1]);const p=processes.get(id);if(!p)throw Error('进程已退出');return p;},
    };
  }
  function run(code,path,args=[]){
    const output=[];
    function Clock(){this.getTime=()=>tick;}Clock.UTC=Date.UTC;
    const context={
      JSON:undefined,
      Date:Clock,
      VBArray:function(value){this.toArray=()=>value;},
      Enumerator:function(items){let i=0;this.atEnd=()=>i>=items.length;this.moveNext=()=>i++;this.item=()=>items[i];},
      GetObject:wmi,
      ActiveXObject:function(name){return name=='Scripting.FileSystemObject'?filesystem():{Exec:exec,Environment:function(){return function(){return "";};}};},
      WScript:{StdOut:{Write:s=>output.push(String(s))},ScriptFullName:path,Arguments:i=>args[i],Echo:s=>output.push(String(s)),Quit:n=>{throw Error('退出：'+n+' '+output.join('\n'));},Sleep:n=>{
        tick+=n;
        for(const p of pending.splice(0)){p.Status=1;processes.delete(p.ProcessID);}
        if(guard && files.has('C:\\临时目录\\私有采集\\done')){const g=guard;guard=null;run(g.code,g.path);g.process.Status=1;}
      }},
    };
    new vm.Script(code).runInNewContext(context,{timeout:2000});return output.join('\n');
  }
  function exec(command){
    if(command.startsWith('taskkill.exe')){const pid=Number(command.match(/PID (\d+)/)[1]);killed.push(pid);processes.delete(pid);return {Status:1};}
    const paths=[...command.matchAll(/"([^"]+)"/g)].map(m=>normalize(m[1]));
    const pid=nextPid++,proc={ProcessID:pid,Status:0,ExitCode:0,StdOut:{ReadAll:()=>''},StdErr:{ReadAll:()=>''},Terminate:()=>{proc.Status=1;processes.delete(pid);}};
    processes.set(pid,{ProcessId:pid,ParentProcessId:100,CreationDate:birth});
    if(command.includes('guard.js')){
      if(failGuard)throw Error('模拟守护进程启动失败');
      const code=files.get(paths[0]).value;new vm.Script(code);guardSource=code;guard={code,path:paths[0],process:proc};return proc;
    }
    if(command.startsWith('cscript.exe')){
      run(files.get(paths[0]).value,paths[0],paths.slice(1));pending.push(proc);peak=Math.max(peak,pending.length);return proc;
    }
    const redirected=(command.match(/>"([^"]+)"/)||[])[1];
    if(redirected)files.set(normalize(redirected),{value:command.includes('nvidia-smi -q -x')?'<nvidia_smi_log><gpu><uuid>GPU-LARGE</uuid><info>'+ 'x'.repeat(130000)+'</info></gpu></nvidia_smi_log>':'',unicode:false});
    proc.Status=1;return proc;
  }
  const output=run(script,'C:\\ops.js');
  if(files.size)throw Error('采集目录未清理');
  if(peak>Number(script.match(/ohLimit=(\d+)/)[1]) || peak<1)throw Error('并发上限错误：'+peak);
  results.push(output);
  for(const expired of [false,true]){
    if(!expired)processes.delete(100);else processes.set(100,owner);
    const root='C:\\临时目录\\私有采集';
    processes.set(888,{ProcessId:888,CreationDate:birth});
    processes.set(999,{ProcessId:999,CreationDate:'新的创建时间'});
    files.set(root+'\\888.pid',{value:'888|'+birth,unicode:true});
    files.set(root+'\\999.pid',{value:'999|'+birth,unicode:true});
    run(guardSource,root+'\\guard.js');
    if(!killed.includes(888) || killed.includes(999))throw Error('父进程退出或超时回收错误，或误杀复用 PID');
    if(files.size)throw Error('异常结束后采集目录未清理');
  }
  failGuard=true;
  let rejected=false;try{run(script,'C:\\ops.js');}catch(e){rejected=true;}
  if(!rejected || files.size)throw Error('守护进程启动失败没有收尾');
}
process.stdout.write(JSON.stringify(results));
''';
