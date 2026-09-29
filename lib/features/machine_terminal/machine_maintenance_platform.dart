import 'dart:convert';

import '../../shared/util/platform_shell.dart';
import 'machine_maintenance.dart';
import 'machine_maintenance_parallel.dart';

/// 平台策略只生成目标命令，传输和终端协议由执行层统一处理。
abstract class MachineMaintenancePlatformAdapter {
  const MachineMaintenancePlatformAdapter();
  static MachineMaintenancePlatformAdapter forPlatform(String platform) =>
      switch (platform) {
        'Linux' => const _LinuxMaintenanceAdapter(),
        'Darwin' => const _MacMaintenanceAdapter(),
        'Windows' => const _WindowsMaintenanceAdapter(),
        _ => throw UnsupportedError('不支持该目标系统：$platform'),
      };
  bool get windowsScript => false;
  bool canInspectProcess(MachineMaintenanceProcess process) => process.pid >= 1;

  /// 指定并发数时启用受监管采集；省略时保留原始协议脚本。
  String collect(int section, {int offset = 0, int? workers});
  String process(MachineMaintenanceProcess process, {String? action});
  Map<String, String> processActions(MachineMaintenanceProcess process) =>
      process.pid <= 1
      ? const {}
      : const {'终止进程': 'TERM', '暂停进程': 'STOP', '恢复进程': 'CONT'};
  String bind(MachineMaintenanceSnapshot snapshot, String command);
  MachineMaintenanceServiceAdapter? servicesFor(String manager) =>
      MachineMaintenanceServiceAdapter.detect(manager);
}

class _LinuxMaintenanceAdapter extends MachineMaintenancePlatformAdapter {
  const _LinuxMaintenanceAdapter();
  @override
  String collect(int section, {int offset = 0, int? workers}) =>
      parallelMaintenanceCommand(
        switch (section) {
          0 => machineMaintenanceOverviewCommand,
          1 => machineMaintenanceProcessesCommand(offset: offset),
          2 => machineMaintenanceServicesCommand,
          4 => machineMaintenanceGpuCommand,
          5 => machineMaintenanceLogsCommand,
          6 => machineMaintenanceHealthCommand,
          _ => machineMaintenanceDiagnosticsCommand,
        },
        workers,
        section,
      );
  @override
  String process(MachineMaintenanceProcess process, {String? action}) =>
      machineMaintenanceProcessCommand(process, signal: action);
  @override
  String bind(MachineMaintenanceSnapshot snapshot, String command) =>
      machineMaintenanceBoundCommand(snapshot, command);
}

const _macPrelude = r'''
export LC_ALL=C LANG=C
section() { printf '\n__OH_OPS_%s__\n' "$1"; }
section platform
uname -s
[ "$(uname -s)" = Darwin ] || { section end; exit 0; }
section host
hostname
section boot
sysctl -n kern.boottime | awk '{gsub(/,/,"",$4); print $4}'
section uptime
sysctl -n kern.boottime | awk -v now="$(date +%s)" '{gsub(/,/,"",$4); print now-$4}'
''';

class _MacMaintenanceAdapter extends MachineMaintenancePlatformAdapter {
  const _MacMaintenanceAdapter();
  @override
  bool canInspectProcess(MachineMaintenanceProcess process) =>
      process.pid >= 1 && process.startToken != null;
  @override
  String collect(int section, {int offset = 0, int? workers}) {
    if (offset < 0) throw ArgumentError('进程偏移无效。');
    final command =
        _macPrelude +
        switch (section) {
          0 => _macOverview,
          1 =>
            _macProcesses
                .replaceAll('__OFFSET__', '$offset')
                .replaceAll('__LIMIT__', '$machineMaintenanceProcessLimit'),
          2 =>
            r'''
section manager
printf 'launchd\n'
section services
launchctl list | awk 'NR>1 {printf "%s\t%s\t%s\n",$3,$1,$2}' | head -c 50000
section service_processes
ps -axo pid=,user=,%cpu=,rss=,etime=,time=,comm= | awk '{printf "%s\t%s\t%s\t%s\t%s\t%s\t",$1,$2,$3,$4,$5,$6;for(i=7;i<=NF;i++)printf "%s%s",i>7?" ":"",$i;printf "\n"}' | head -c 160000
section startup
for d in /Library/LaunchDaemons /Library/LaunchAgents "$HOME/Library/LaunchAgents"; do
  [ -d "$d" ] || continue
  for f in "$d"/*.plist; do
    [ -f "$f" ] && printf '__OH_STARTUP__\t%s\n' "$f"
  done
done | head -c 12000
section end
''',
          4 => machineGpuMacCollection,
          5 => machineLogsMacCollection,
          6 => machineHealthMacCollection,
          _ =>
            r'''
section sockets
{ netstat -anv -f inet; netstat -anv -f inet6; } 2>&1 | head -c 48000
section routes
netstat -rn 2>&1 | head -c 48000
section addresses
ifconfig -a 2>&1 | head -c 24000
section neighbors
{ arp -an; ndp -an; } 2>&1 | head -c 24000
section network_stats
netstat -s 2>&1 | head -c 32000
section socket_details
lsof -nP -i 2>&1 | head -c 32000
section dns_status
{ scutil --nwi; scutil --proxy; } 2>&1 | head -c 16000
section dns
scutil --dns 2>&1 | head -c 10000
section logs
if [ -x /usr/bin/log ]; then /usr/bin/log show --last 2m --style compact 2>&1 | head -c 20000; else tail -n 80 /var/log/system.log 2>&1 | head -c 16000; fi
section users
who
section cron
crontab -l 2>&1 | head -c 8000
section firewall
{ /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate; /usr/libexec/ApplicationFirewall/socketfilterfw --getblockall; /usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode; } 2>&1 | head -c 8000
section firewall_rules
pfctl -vvsr 2>&1 | head -c 32000
section firewall_nat
pfctl -vvsn 2>&1 | head -c 24000
section firewall_states
pfctl -si 2>&1 | head -c 12000
section containers
if command -v docker >/dev/null 2>&1; then docker ps -a 2>&1 | head -c 10000; else printf '未安装 Docker。\n'; fi
section end
''',
        };
    return parallelMaintenanceCommand(command, workers, section);
  }

  @override
  String process(MachineMaintenanceProcess process, {String? action}) {
    if (process.pid < 1 || process.startToken == null) {
      throw ArgumentError('缺少进程启动标识，请刷新。');
    }
    if (action != null && !processActions(process).containsValue(action)) {
      throw ArgumentError('不支持该操作。');
    }
    final guard =
        '[ "\$(LC_ALL=C ps -p ${process.pid} -o lstart= | xargs)" = ${posixShellQuote(process.startToken!)} ] || { printf "进程已退出或标识已重用。\\n"; exit 1; }\n';
    if (action != null) return '$guard kill -$action ${process.pid}';
    return '''$_macPrelude$guard
section status
ps -p ${process.pid} -o pid,ppid,user,state,ni,%cpu,%mem,rss,vsz,time,lstart,command
section descriptors
lsof -nP -p ${process.pid} 2>&1 | head -c 20000
section memory
vmmap -summary ${process.pid} 2>&1 | head -c 16000
section end
''';
  }

  @override
  String bind(MachineMaintenanceSnapshot snapshot, String command) =>
      '[ "\$(hostname)" = ${posixShellQuote(snapshot.text('host'))} ] && '
      '[ "\$(sysctl -n kern.boottime | awk \'{gsub(/,/,"",\$4); print \$4}\')" = ${posixShellQuote(snapshot.text('boot'))} ] || '
      '{ printf "终端目标已经变化，请重新打开面板。\\n"; exit 1; }\n$command';
  @override
  MachineMaintenanceServiceAdapter? servicesFor(String manager) =>
      manager == 'launchd' ? const _LaunchdMaintenanceAdapter() : null;
}

const _macOverview = r'''
section system
sw_vers
uname -a
section processor
sysctl -n machdep.cpu.brand_string 2>/dev/null || uname -m
section core_count
sysctl -n hw.logicalcpu
section load
sysctl -n vm.loadavg | tr -d '{}'
section cpu_percent
top -l 2 -s 1 -n 0 | awk '/CPU usage:/ {idle=$NF; for(i=1;i<=NF;i++) if($i=="idle")idle=$(i-1); gsub(/%/,"",idle); value=(100-idle)*100} END {if(value!="")printf "cpu %.0f\n",value}'
section memory
printf 'MemTotal: %s\n' "$(sysctl -n hw.memsize)"
vm_stat | awk 'NR==1 {page=$8;gsub(/[^0-9]/,"",page)} /Pages free:|Pages inactive:|Pages speculative:/ {value=$NF;gsub(/\./,"",value);free+=value} END {printf "MemAvailable: %.0f\n",free*page}'
sysctl -n vm.swapusage | awk '{for(i=1;i<=NF;i++){if($i=="total")total=$(i+2);if($i=="free")free=$(i+2)} gsub(/M/,"",total);gsub(/M/,"",free);printf "SwapTotal: %.0f\nSwapFree: %.0f\n",total*1048576,free*1048576}'
section memory_note
printf 'macOS 可用内存按空闲、非活跃与推测页估算；每核计数未由通用命令提供。\n'
section vm
vm_stat | awk 'NR==1 {p=$8;gsub(/[^0-9]/,"",p)} /Pageins:|Pageouts:|Swapins:|Swapouts:/ {v=$NF;gsub(/\./,"",v); k=$1;gsub(/:/,"",k); if(k=="Pageins")printf "pgpgin %.0f\n",v*p/1024;if(k=="Pageouts")printf "pgpgout %.0f\n",v*p/1024;if(k=="Swapins")print "pswpin",v;if(k=="Swapouts")print "pswpout",v}'
section disks
ioreg -r -c IOBlockStorageDriver -l -w0 | awk 'function counter(k,s) {return k in v?v[k]/s:-1} /"Statistics" =/ {for(k in v)delete v[k];n++;line=$0;sub(/^.*= \{/,"",line);gsub(/[{}"]/,"",line);c=split(line,a,",");for(i=1;i<=c;i++){split(a[i],b,"=");v[b[1]]=b[2]} printf "存储驱动%d %.0f 0 %.0f %.0f %.0f 0 %.0f %.0f\n",n,counter("Operations (Read)",1),counter("Bytes (Read)",512),counter("Total Time (Read)",1000000),counter("Operations (Write)",1),counter("Bytes (Write)",512),counter("Total Time (Write)",1000000)}'
section network
netstat -ibn | awk '/<Link#/ {n=NF; printf "%s: %.0f %.0f %.0f 0 0 0 0 0 %.0f %.0f %.0f 0 0 0 0 0\n",$1,$(n-4),$(n-6),$(n-5),$(n-1),$(n-3),$(n-2)}'
section filesystems
df -Pk | head -c 12000
section inodes
df -Pi | head -c 12000
section interfaces
ifconfig -a | head -c 12000
section pressure
memory_pressure -Q 2>&1
section blocks
diskutil list 2>&1 | head -c 10000
section kernel
sysctl kern.osrelease kern.maxproc kern.maxfiles kern.num_taskthreads 2>&1
section capabilities
printf 'macOS 原生命令：sysctl、top、vm_stat、ioreg、netstat、launchctl；权限不足的字段不作推断。\n'
section end
''';

const _macProcesses = r'''
section page_size
printf '1\n'
section clock_ticks
printf '100\n'
section processes
ps -axo pid=,ppid=,state=,nice=,rss=,vsz=,time=,lstart=,comm= | awk '
{count++; if(count<=__OFFSET__ || count>__OFFSET__+__LIMIT__)next
n=split($7,t,":"); ticks=0; for(i=1;i<=n;i++)ticks=ticks*60+t[i]; start=$8" "$9" "$10" "$11" "$12; name=$13;for(i=14;i<=NF;i++)name=name" "$i
printf "%s\t%s\t%s\t%s\t-1\t%.0f\t%.0f\t%.0f\t0\t%s\t%s\n",$1,$2,$3,$4,$5*1024,$6*1024,ticks*100,name,start}
END{printf "__COUNT__\t%d\n",count}'
section end
''';

class _LaunchdMaintenanceAdapter extends MachineMaintenanceServiceAdapter {
  const _LaunchdMaintenanceAdapter();
  @override
  String invoke(String name, String action) => action == 'restart'
      ? 'launchctl stop ${posixShellQuote(name)} && launchctl start ${posixShellQuote(name)}'
      : 'launchctl $action ${posixShellQuote(name)}';
  @override
  String detail(String name) =>
      _macPrelude +
      r'''
name=__NAME__
section status
info=""
for domain in "gui/$(id -u)" "user/$(id -u)" system; do
  if info=$(launchctl print "$domain/$name" 2>/dev/null); then
    printf '目标 = %s/%s\n' "$domain" "$name"
    printf '%s\n' "$info" | sed '1d;$d' | head -c 60000
    break
  fi
done
if [ -z "$info" ]; then launchctl list "$name" 2>&1; fi
section process
pid=$(printf '%s\n' "$info" | awk '$1=="pid" && $2=="=" {print $3;exit}')
case "$pid" in ''|*[!0-9]*) ;; *) ps -p "$pid" -o pid=,ppid=,user=,%cpu=,rss=,vsz=,etime=,time=,command= | awk '{printf "PID = %s\nPPID = %s\nUser = %s\nCPU = %s %%\nRSS = %s KiB\nVSZ = %s KiB\nElapsed = %s\nCPUTime = %s\nCommand = ",$1,$2,$3,$4,$5,$6,$7,$8;for(i=9;i<=NF;i++)printf "%s%s",i>9?" ":"",$i;printf "\n"}' | head -c 16000 ;; esac
section logs
program=$(printf '%s\n' "$info" | sed -n 's/^[[:space:]]*program = //p' | head -n 1)
base=${program##*/}
escaped=$(printf '%s' "$base" | sed 's/\\/\\\\/g;s/"/\\"/g')
predicate="subsystem == \"$name\""
[ -z "$escaped" ] || predicate="$predicate OR process == \"$escaped\""
if command -v perl >/dev/null 2>&1; then
  { perl -e 'alarm 6; exec @ARGV' /usr/bin/log show --last 15m --style compact --info --predicate "$predicate" 2>&1
    code=$?; [ "$code" -eq 0 ] || printf '\n日志查询未完成（退出码 %s），可手动重试。\n' "$code"
  } | tail -n 120 | head -c 48000
else
  printf '缺少有界日志查询所需的 Perl。\n'
fi
for key in 'stdout path' 'stderr path'; do
  file=$(printf '%s\n' "$info" | sed -n "s/^[[:space:]]*$key = //p" | head -n 1)
  [ -n "$file" ] || continue
  printf '\n%s: %s\n' "$key" "$file"
  if [ -f "$file" ] && [ -r "$file" ]; then tail -n 120 "$file" | head -c 16000
  else printf '日志文件不存在或当前账户不可读取。\n'; fi
done
section end
'''
          .replaceAll('__NAME__', posixShellQuote(name));
}

/// WSH/JScript 使用系统 WMI，兼容没有 PowerShell 的旧 Windows；不依赖 WMIC。
class _WindowsMaintenanceAdapter extends MachineMaintenancePlatformAdapter {
  const _WindowsMaintenanceAdapter();
  @override
  bool canInspectProcess(MachineMaintenanceProcess process) =>
      process.pid >= 1 && process.startToken != null;
  @override
  bool get windowsScript => true;
  @override
  String collect(int section, {int offset = 0, int? workers}) {
    if (offset < 0) throw ArgumentError('进程偏移无效。');
    final body = switch (section) {
      0 => _windowsOverview,
      1 =>
        _windowsProcesses
            .replaceAll('__OFFSET__', '$offset')
            .replaceAll('__LIMIT__', '$machineMaintenanceProcessLimit'),
      2 => _windowsServices,
      4 =>
        _windowsGpu
            .replaceAll('__GPU_QUERY__', machineGpuQuery)
            .replaceAll('__GPU_DETAIL_LIMIT__', '$machineGpuDetailOutputLimit'),
      5 => machineLogsWindowsCollection,
      6 => machineHealthWindowsCollection,
      _ => _windowsDiagnostics,
    };
    if (workers != null) {
      final boundaries = section == 0
          ? RegExp(
              '^(?:var warningCount=|var drives=|var nets=|var mem=|var adapters=)',
              multiLine: true,
            )
          : RegExp(
              r'^(?:emit\("(?:routes|addresses|neighbors|network_stats|socket_details|dns_status|firewall_rules)"|emit\("dns"|var sessions=|emit\("cron"|var logs=|emit\("firewall"|emit\("containers")',
              multiLine: true,
            );
      final starts = [
        0,
        if (workers > 1 && (section == 0 || section == 3))
          ...boundaries.allMatches(body).map((m) => m.start),
        body.length,
      ];
      return parallelWindowsMaintenanceCommand(
        _windowsPrelude,
        [
          for (var i = 0; i + 1 < starts.length; i++)
            body.substring(starts[i], starts[i + 1]),
        ],
        workers,
        maxOutputCharacters: switch (section) {
          4 => 4000000,
          3 => 1000000,
          _ => 100000,
        },
      );
    }
    return '$_windowsPrelude$body\nemit("end", "");';
  }

  @override
  Map<String, String> processActions(MachineMaintenanceProcess process) =>
      process.pid <= 4 || process.startToken == null
      ? const {}
      : const {'终止进程': 'TERM'};
  @override
  String process(MachineMaintenanceProcess process, {String? action}) {
    if (process.pid < 1 || process.startToken == null) {
      throw ArgumentError('缺少进程启动标识，请刷新。');
    }
    if (action != null && !processActions(process).containsValue(action)) {
      throw ArgumentError('该系统不支持此操作。');
    }
    return '''$_windowsPrelude
var p=rows("SELECT * FROM Win32_Process WHERE ProcessId=${process.pid}")[0];
if(!p || String(p.CreationDate)!==${jsonEncode(process.startToken)})fail("进程已经退出或标识已重用。");
${action != null ? 'var result=p.Terminate(1);if(result!==0)fail("终止进程失败，返回码："+result);' : 'emit("status", describe(p));emit("command", p.CommandLine);'}
emit("end", "");
''';
  }

  @override
  String bind(MachineMaintenanceSnapshot snapshot, String command) =>
      '''
var ohExpectedHost=${jsonEncode(snapshot.text('host'))};
var ohExpectedBoot=${jsonEncode(snapshot.text('boot'))};
$command
''';
  @override
  MachineMaintenanceServiceAdapter? servicesFor(String manager) =>
      manager == 'Windows SCM'
      ? const _WindowsServiceMaintenanceAdapter()
      : null;
}

const _windowsPrelude = r'''
var emitted=0,truncated=false,outputLimit=100000;
function emit(key,value){var text=value==null?"":String(value),encoded=encodeURIComponent(text),limit=Math.max(0,outputLimit-emitted);while(encoded.length>limit){truncated=true;text=text.substr(0,Math.floor(text.length*0.8));if(/[\uD800-\uDBFF]$/.test(text))text=text.substr(0,text.length-1);encoded=encodeURIComponent(text);}if(key=="end" && (truncated || warnings.length)){WScript.Echo("__OH_OPS_notice__");WScript.Echo(encodeURIComponent((truncated?"输出达到上限，部分内容已截断。\n":"")+warnings.join("\n").substr(0,4000)));}WScript.Echo("__OH_OPS_"+key+"__");WScript.Echo(encoded);emitted+=encoded.length+key.length+20;}
function fail(message){WScript.Echo(message);WScript.Quit(1);}
function clean(value){return value==null?"":String(value).replace(/[\r\n\t]/g," ");}
function number(value){return value==null?null:Number(value);}
function fixed(value){return Math.round(value).toFixed(0);}
function counter(value){return value==null?"-1":fixed(Number(value));}
function field(item,key){try{return item[key];}catch(e){return null;}}
var warnings=[];
var wmi;
try {wmi=GetObject("winmgmts:{impersonationLevel=impersonate}!\\\\.\\root\\cimv2");}catch(e){fail("WMI 不可用或被策略禁用。 "+e.message);}
function rows(query,limit){var result=[];limit=limit||16384;try{var items=new Enumerator(wmi.ExecQuery(query,"WQL",48));for(;!items.atEnd() && result.length<limit;items.moveNext())result.push(items.item());if(!items.atEnd())warnings.push("查询达到条目上限："+query);}catch(e){warnings.push(query+"："+e.message);}return result;}
function describe(item){var lines=[];if(!item)return "无数据或权限不足。";var p=new Enumerator(item.Properties_);for(;!p.atEnd();p.moveNext()){var field=p.item();try{lines.push(field.Name+": "+clean(field.Value));}catch(e){}}return lines.join("\n");}
function time(value){if(!value)return NaN;var s=String(value);return Date.UTC(+s.substr(0,4),+s.substr(4,2)-1,+s.substr(6,2),+s.substr(8,2),+s.substr(10,2),+s.substr(12,2),+s.substr(15,3))-(s.charAt(21)=="-"?-1:1)*Number(s.substr(22,3))*60000;}
function command(text,limit){var out="",child;try{child=new ActiveXObject("WScript.Shell").Exec("cmd.exe /d /c "+text);var start=new Date().getTime();while(child.Status==0){if(new Date().getTime()-start>4000){child.Terminate();return "查询超时。";}WScript.Sleep(40);}out=child.StdOut.ReadAll()+child.StdErr.ReadAll();}catch(e){out=e.message;}return out.substr(0,limit);}
var os=rows("SELECT * FROM Win32_OperatingSystem")[0];
if(!os)fail("无法读取系统身份，请检查 WMI 服务与权限。");
var host=String(os.CSName),boot=String(os.LastBootUpTime);
if(typeof ohExpectedHost!="undefined" && (ohExpectedHost!==host || ohExpectedBoot!==boot))fail("终端目标已变化，请重新打开面板。");
WScript.Echo("__OH_OPS_encoding__");WScript.Echo("uri");
emit("platform","Windows");emit("host",host);emit("boot",boot);
var up=rows("SELECT SystemUpTime,Timestamp_Object,Frequency_Object FROM Win32_PerfRawData_PerfOS_System")[0];
var uptime=up && Number(up.Frequency_Object)>0?(Number(up.Timestamp_Object)-Number(up.SystemUpTime))/Number(up.Frequency_Object):(time(os.LocalDateTime)-time(os.LastBootUpTime))/1000;
emit("uptime",fixed(uptime));
''';

const _windowsOverview = r'''
emit("system",describe(os));
var processors=rows("SELECT * FROM Win32_Processor"),names=[],cores=0;
for(var i=0;i<processors.length;i++){names.push(clean(processors[i].Name));cores+=Number(field(processors[i],"NumberOfLogicalProcessors"))||0;}
emit("processor",names.join("\n"));
var cpus=rows("SELECT Name,PercentProcessorTime,Timestamp_Sys100NS FROM Win32_PerfRawData_PerfOS_Processor"),lines=[];
for(var i=0;i<cpus.length;i++){var c=cpus[i];var label=c.Name=="_Total"?"cpu":"cpu"+c.Name;if(!/^cpu[0-9]*$/.test(label))continue;var idle=number(c.PercentProcessorTime),total=number(c.Timestamp_Sys100NS);if(idle!=null && total!=null)lines.push(label+" "+fixed(total-idle)+" 0 0 "+fixed(idle)+" 0 0 0 0");}emit("cpu",lines.join("\n"));emit("core_count",cores>0?cores:(lines.length>1?lines.length-1:""));
var warningCount=warnings.length,pages=rows("SELECT AllocatedBaseSize,CurrentUsage FROM Win32_PageFileUsage"),swap=0,used=0;
for(var i=0;i<pages.length;i++){swap+=Number(pages[i].AllocatedBaseSize)*1048576;used+=Number(pages[i].CurrentUsage)*1048576;}
emit("memory","MemTotal: "+os.TotalVisibleMemorySize+" kB\nMemAvailable: "+os.FreePhysicalMemory+" kB"+(warnings.length==warningCount?"\nSwapTotal: "+fixed(swap)+"\nSwapFree: "+fixed(swap-used):""));
var drives=rows("SELECT DeviceID,Size,FreeSpace,FileSystem,DriveType FROM Win32_LogicalDisk WHERE DriveType=3"),lines=["设备 容量 已用 可用 使用率 挂载点"];
for(var i=0;i<drives.length;i++){var d=drives[i],total=Number(d.Size),free=Number(d.FreeSpace);if(total>0)lines.push(d.DeviceID+" "+fixed(total/1024)+" "+fixed((total-free)/1024)+" "+fixed(free/1024)+" "+fixed((total-free)/total*100)+"% "+d.DeviceID);}emit("filesystems",lines.join("\n"));
var disks=rows("SELECT * FROM Win32_PerfRawData_PerfDisk_PhysicalDisk"),lines=[];
for(var i=0;i<disks.length;i++){var d=disks[i];if(d.Name=="_Total")continue;if(d.DiskReadBytesPersec==null || d.DiskWriteBytesPersec==null)continue;lines.push(encodeURIComponent(clean(d.Name))+" "+counter(d.DiskReadsPersec)+" 0 "+fixed(Number(d.DiskReadBytesPersec)/512)+" 0 "+counter(d.DiskWritesPersec)+" 0 "+fixed(Number(d.DiskWriteBytesPersec)/512)+" 0");}emit("disks",lines.join("\n"));
var nets=rows("SELECT * FROM Win32_PerfRawData_Tcpip_NetworkInterface"),lines=[];
for(var i=0;i<nets.length;i++){var n=nets[i];if(n.BytesReceivedPersec==null || n.BytesSentPersec==null)continue;lines.push(encodeURIComponent(clean(n.Name))+": "+fixed(Number(n.BytesReceivedPersec))+" "+counter(n.PacketsReceivedPersec)+" "+counter(n.PacketsReceivedErrors)+" "+counter(n.PacketsReceivedDiscarded)+" 0 0 0 0 "+fixed(Number(n.BytesSentPersec))+" "+counter(n.PacketsSentPersec)+" "+counter(n.PacketsOutboundErrors)+" "+counter(n.PacketsOutboundDiscarded)+" 0 0 0 0");}emit("network",lines.join("\n"));
var mem=rows("SELECT * FROM Win32_PerfRawData_PerfOS_Memory")[0];emit("memory_details",describe(mem));
var system=rows("SELECT * FROM Win32_PerfRawData_PerfOS_System")[0];emit("pressure",describe(system));
var adapters=rows("SELECT Description,IPEnabled,MACAddress,IPAddress,DefaultIPGateway FROM Win32_NetworkAdapterConfiguration"),lines=[];
function arrayText(value){if(value==null)return "—";try{return new VBArray(value).toArray().join(", ");}catch(e){return clean(value);}}
for(var i=0;i<adapters.length;i++){var a=adapters[i];lines.push([clean(a.Description),a.IPEnabled==null?"—":a.IPEnabled?"active":"inactive",clean(a.MACAddress)||"—","—",arrayText(a.IPAddress),arrayText(a.DefaultIPGateway)].join("\t"));}emit("interfaces",lines.join("\n"));
var physical=rows("SELECT DeviceID,MediaType,Model,Size,InterfaceType FROM Win32_DiskDrive"),lines=[];
for(var i=0;i<physical.length;i++){var d=physical[i];lines.push([clean(d.DeviceID),clean(d.MediaType)||"—",clean(d.Model),d.Size==null?"—":clean(d.Size)+" B",clean(d.InterfaceType)||"—"].join("\t"));}emit("blocks",lines.join("\n"));
emit("capabilities","Windows WMI / WSH JScript；性能计数器取决于系统提供程序，缺失字段不作估算。\n"+warnings.join("\n"));
''';

const _windowsProcesses = r'''
emit("page_size","1");emit("clock_ticks","10000000");
var processes=rows("SELECT ProcessId,ParentProcessId,Name,Priority,ThreadCount,WorkingSetSize,VirtualSize,KernelModeTime,UserModeTime,CreationDate FROM Win32_Process"),lines=[];
processes.sort(function(a,b){return Number(a.ProcessId)-Number(b.ProcessId);});
for(var i=__OFFSET__;i<processes.length && i<__OFFSET__+__LIMIT__;i++){var p=processes[i];var born=time(p.CreationDate);lines.push([p.ProcessId,p.ParentProcessId,"运行",counter(p.Priority),counter(p.ThreadCount),counter(p.WorkingSetSize),counter(p.VirtualSize),p.KernelModeTime==null || p.UserModeTime==null?"-1":fixed(Number(p.KernelModeTime)+Number(p.UserModeTime)),isNaN(born)?0:fixed(born),clean(p.Name),p.CreationDate==null?"":String(p.CreationDate)].join("\t"));}
lines.push("__COUNT__\t"+processes.length);emit("processes",lines.join("\n"));emit("capabilities",warnings.join("\n"));
''';

const _windowsServices = r'''
emit("manager","Windows SCM");
var services=rows("SELECT Name,DisplayName,State,StartMode,ProcessId,StartName,ExitCode,PathName,ServiceType,AcceptStop,AcceptPause,ServiceSpecificExitCode FROM Win32_Service"),lines=[],startup=[];
for(var i=0;i<services.length;i++){var s=services[i];lines.push([clean(s.Name),clean(s.State),clean(s.DisplayName),clean(s.ProcessId),clean(s.StartName),clean(s.ExitCode),clean(s.PathName),clean(s.ServiceType),clean(s.AcceptStop),clean(s.AcceptPause),clean(s.ServiceSpecificExitCode)].join("\t"));startup.push(clean(s.Name)+"\t"+clean(s.StartMode));}
emit("services",lines.join("\n").substr(0,50000));emit("startup",startup.join("\n").substr(0,16000));
var dependencies=rows("SELECT Antecedent,Dependent FROM Win32_DependentService"),links=[];
for(var i=0;i<dependencies.length;i++){var d=dependencies[i],a=String(d.Antecedent).match(/Name="([^"]+)"/i),b=String(d.Dependent).match(/Name="([^"]+)"/i);if(a&&b)links.push(clean(b[1])+"\t"+clean(a[1]));}
emit("service_dependencies",links.join("\n").substr(0,50000));
emit("timers",command("schtasks /query /fo LIST",12000));
''';

const _windowsDiagnostics = r'''
emit("sockets",command("netstat -ano",18000));
emit("routes",command("route print",32000));
emit("addresses",command("ipconfig /all",24000));
emit("neighbors",command("netsh interface ipv4 show neighbors",16000)+"\n"+command("netsh interface ipv6 show neighbors",16000));
emit("network_stats",command("netstat -s",24000));
emit("socket_details",command("netstat -ano",32000));
emit("dns_status",command("netsh winhttp show proxy",8000));
emit("dns",command("ipconfig /all",12000));
var sessions=rows("SELECT LogonId,LogonType,StartTime FROM Win32_LogonSession",64),sessionLines=[];for(var i=0;i<sessions.length;i++)sessionLines.push(describe(sessions[i]));emit("users",sessionLines.join("\n\n").substr(0,10000));
emit("cron",command("schtasks /query /fo LIST",12000));
var logs=rows("SELECT TimeGenerated,SourceName,Message FROM Win32_NTLogEvent WHERE Logfile='System' AND EventType=1",40),lines=[];
for(var i=0;i<logs.length && i<40;i++)lines.push(clean(logs[i].TimeGenerated)+" "+clean(logs[i].SourceName)+" "+clean(logs[i].Message));emit("logs",lines.join("\n").substr(0,16000));
emit("firewall",command(parseInt(String(os.Version),10)<6?"netsh firewall show state":"netsh advfirewall show allprofiles",10000));
emit("firewall_rules",command("netsh advfirewall firewall show rule name=all verbose",48000));
emit("containers",command("docker ps -a",10000));
''';

class _WindowsServiceMaintenanceAdapter
    extends MachineMaintenanceServiceAdapter {
  const _WindowsServiceMaintenanceAdapter();
  @override
  bool accepts(String name) =>
      name.isNotEmpty &&
      name.length <= 256 &&
      !RegExp(r'[\x00-\x1f\u2028\u2029"\\/]').hasMatch(name);
  @override
  Map<String, String> get actions => const {
    '启动服务': 'StartService',
    '停止服务': 'StopService',
    '重启服务': 'RestartService',
    '自动启动': 'Automatic',
    '手动启动': 'Manual',
    '禁用服务': 'Disabled',
  };
  @override
  String invoke(String name, String action) {
    final object = jsonEncode(
      'Win32_Service.Name="${name.replaceAll('"', '\\"')}"',
    );
    if (action == 'RestartService') {
      return '$_windowsPrelude\nvar path=$object;var s=wmi.Get(path);var code=s.StopService();'
          'if(code!==0 && code!==6)fail("停止服务失败，返回码："+code);'
          'var deadline=new Date().getTime()+10000;'
          'while(String(wmi.Get(path).State)!=="Stopped"){if(new Date().getTime()>deadline)fail("服务停止等待超时。");WScript.Sleep(200);}'
          'code=wmi.Get(path).StartService();if(code!==0 && code!==10)fail("启动服务失败，返回码："+code);';
    }
    final operation = const ['Automatic', 'Manual', 'Disabled'].contains(action)
        ? 's.ChangeStartMode(${jsonEncode(action)})'
        : 's.$action()';
    return '$_windowsPrelude\nvar s=wmi.Get($object);var code=$operation;if(code!==0)fail("服务操作失败，返回码："+code);';
  }

  @override
  String detail(String name) =>
      '''$_windowsPrelude
var service=wmi.Get(${jsonEncode('Win32_Service.Name="$name"')});
emit("status",describe(service));
var cutoff=new Date(new Date().getTime()-86400000);
function two(n){return n<10?"0"+n:String(n);}
var since=String(cutoff.getUTCFullYear())+two(cutoff.getUTCMonth()+1)+two(cutoff.getUTCDate())+two(cutoff.getUTCHours())+two(cutoff.getUTCMinutes())+two(cutoff.getUTCSeconds())+".000000+000";
var events=rows("SELECT TimeGenerated,SourceName,EventCode,Message FROM Win32_NTLogEvent WHERE Logfile='System' AND SourceName='Service Control Manager' AND TimeGenerated >= '"+since+"'",500),messages=["最近 24 小时内与服务名称匹配的 SCM 事件（不包含应用自有日志）。"];

for(var i=0;i<events.length;i++){var e=events[i],message=String(e.Message||"");if(message.indexOf(String(service.Name))<0 && (!service.DisplayName || message.indexOf(String(service.DisplayName))<0))continue;messages.push(clean(e.TimeGenerated)+" "+clean(e.SourceName)+" ["+clean(e.EventCode)+"] "+String(e.Message||""));}
emit("logs",messages.join("\\n").substr(0,48000));emit("end","");
''';
}

const _windowsGpu = r'''
outputLimit=4000000;
function gpuCommand(text,limit){
  var fs,shell,path,child,reader,out="";
  try{
    fs=new ActiveXObject("Scripting.FileSystemObject");shell=new ActiveXObject("WScript.Shell");path=fs.BuildPath(fs.GetSpecialFolder(2),fs.GetTempName());
    child=shell.Exec('cmd.exe /d /c '+text+' >"'+path+'" 2>&1');
    if(typeof ohTrack=="function")ohTrack(child.ProcessID);
    var start=new Date().getTime();
    while(child.Status==0){
      if(new Date().getTime()-start>2000){shell.Run('taskkill /PID '+child.ProcessID+' /T /F',0,true);return "查询超时。";}
      WScript.Sleep(40);
    }
    if(fs.FileExists(path)){reader=fs.OpenTextFile(path,1);if(!reader.AtEndOfStream)out=reader.Read(limit);if(!reader.AtEndOfStream)out+="\n__GPU_OUTPUT_TRUNCATED__";reader.Close();reader=null;}
    if(child.ExitCode!=0)out+="\n__GPU_PROBE_EXIT_"+child.ExitCode+"__";
  }catch(e){out+="\n查询失败："+e.message;}
  finally{if(reader)try{reader.Close();}catch(e){}try{if(fs && path && fs.FileExists(path))fs.DeleteFile(path,true);}catch(e){}}
  return out;
}

var cards=rows("SELECT DeviceID,Name,AdapterCompatibility,DriverVersion,Status,PNPDeviceID FROM Win32_VideoController"),gpu=[];
for(var i=0;i<cards.length;i++){var c=cards[i];gpu.push([clean(c.DeviceID),clean(c.Name),clean(c.AdapterCompatibility),clean(c.DriverVersion),clean(c.Status),clean(c.PNPDeviceID)].join("\t"));}
emit("gpu_windows",gpu.join("\n").substr(0,16000));
emit("gpu_nvidia",gpuCommand("nvidia-smi --query-gpu=__GPU_QUERY__ --format=csv,noheader,nounits",40000));
emit("gpu_processes",gpuCommand("nvidia-smi --query-compute-apps=gpu_uuid,pid,process_name,used_gpu_memory --format=csv,noheader,nounits",20000));
emit("gpu_details",gpuCommand("nvidia-smi -q -x",__GPU_DETAIL_LIMIT__));
emit("gpu_links",gpuCommand("nvidia-smi nvlink --status",8000));
emit("gpu_link_errors",gpuCommand("nvidia-smi nvlink --errorcounters",8000));
emit("gpu_topology",gpuCommand("nvidia-smi topo -m",24000));
emit("gpu_mig",gpuCommand("nvidia-smi -L",24000));
var toolkit=gpuCommand("nvcc --version",2000),stack=[];
var release=toolkit.match(/release[^\r\n]+/);
if(release)stack.push("CUDA Toolkit\tversion\t"+release[0]);
var env=new ActiveXObject("WScript.Shell").Environment("PROCESS");
var cuda=env("CUDA_PATH");
if(cuda)stack.push("CUDA Toolkit\tpath\t"+clean(cuda));

if(cuda){
  try {
    var fs=new ActiveXObject("Scripting.FileSystemObject"),header=cuda+"\\include\\cudnn_version.h";
    if(fs.FileExists(header)){
      var file=fs.OpenTextFile(header,1),content=file.Read(16000);file.Close();
      var re=/#define\s+(CUDNN_MAJOR|CUDNN_MINOR|CUDNN_PATCHLEVEL)\s+(\d+)/g,match;
      stack.push("cuDNN header\tpath\t"+clean(header));
      while((match=re.exec(content))!==null)stack.push("cuDNN header\t"+match[1]+"\t"+match[2]);
    }
  }catch(e){stack.push("cuDNN header\tstatus\t"+clean(e.message));}
}
emit("gpu_stack",stack.join("\n"));

''';
