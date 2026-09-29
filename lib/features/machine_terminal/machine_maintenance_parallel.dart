import 'dart:convert';

import '../../shared/util/platform_shell.dart';

const machineMaintenanceMaxWorkers = 8;
const machineMaintenanceDefaultWorkers = 4;

/// 只拆分互不依赖的总览和诊断分区；进程与服务保留原有事务边界。
String parallelMaintenanceCommand(String command, int? workers, int tab) {
  if (workers == null) return command;
  if (workers < 1 || workers > machineMaintenanceMaxWorkers) {
    throw ArgumentError('采集并发数必须在 1–8 之间。');
  }
  final sections = RegExp(
    r'^section ([a-z_]+)\n',
    multiLine: true,
  ).allMatches(command).toList();
  final first = sections.indexWhere(
    (m) => !const ['platform', 'host', 'boot', 'uptime'].contains(m[1]),
  );
  if (first < 0) return command;
  final split = workers > 1 && (tab == 0 || tab == 3);
  final prefix = split ? command.substring(0, sections[first].start) : "";
  final functions = command.substring(0, sections.first.start);
  final jobs = <String>[];
  for (var i = first; i < sections.length; i++) {
    if (sections[i][1] == 'end') continue;
    jobs.add(
      functions +
          command.substring(
            sections[i].start,
            i + 1 < sections.length ? sections[i + 1].start : command.length,
          ),
    );
  }
  if (!split) {
    jobs
      ..clear()
      ..add(command);
  }
  // 独立进程组保证管道与孙进程一起回收；缺少系统能力时明确失败。
  final script =
      '''
$prefix
${_coordinatorPrelude.replaceAll('__WORKERS__', '${workers.clamp(1, jobs.length)}')}
${[for (var i = 0; i < jobs.length; i++) 'printf %s ${posixShellQuote("${jobs[i]}\n:")} > "\$oh_dir/$i.sh"'].join('\n')}
oh_next=0
while [ "\$oh_next" -lt ${jobs.length} ]; do
  oh_batch=""
  oh_slot=0
  while [ "\$oh_slot" -lt "\$oh_workers" ] && [ "\$oh_next" -lt ${jobs.length} ]; do
    oh_launch sh -c 'printf "%s\\n" "\$\$" > "\$1.pid"; exec sh "\$1.sh"' sh "\$oh_dir/\$oh_next" > "\$oh_dir/\$oh_next.out" 2>&1 &
    oh_batch="\$oh_batch \$!"
    oh_next=\$((oh_next + 1))
    oh_slot=\$((oh_slot + 1))
  done
  for oh_pid in \$oh_batch; do wait "\$oh_pid" || exit 1; done
  [ -d "\$oh_dir" ] && [ ! -f "\$oh_dir/expired" ] || exit 1
done
${[for (var i = 0; i < jobs.length; i++) 'cat "\$oh_dir/$i.out"'].join('\n')}
printf '\\n__OH_OPS_end__\\n'
''';
  return 'sh -c ${posixShellQuote(script)}';
}

const _coordinatorPrelude = r'''
oh_workers=__WORKERS__
if command -v setsid >/dev/null 2>&1; then
  oh_launch() { setsid "$@"; }
elif command -v perl >/dev/null 2>&1; then
  oh_launch() { perl -MPOSIX -e 'POSIX::setsid() >= 0 or die "无法隔离采集进程组"; exec @ARGV or die "无法启动采集进程";' -- "$@"; }
else
  printf '当前系统缺少安全隔离采集进程所需的 setsid 或 Perl。\n' >&2
  exit 1
fi
umask 077
oh_dir=$(mktemp -d "${TMPDIR:-/tmp}/openhand-ops.XXXXXXXX") || exit 1
oh_owner=$$
oh_ancestors="$$"
oh_parent=$$
oh_depth=0
while [ "$oh_depth" -lt 32 ]; do
  oh_parent=$(ps -o ppid= -p "$oh_parent" | tr -d " ")
  case "$oh_parent" in ""|0|1) break;; esac
  oh_ancestors="$oh_ancestors $oh_parent"
  oh_depth=$((oh_depth + 1))
done
oh_cleanup() {
  trap '' HUP INT TERM
  touch "$oh_dir/done" 2>/dev/null
  wait "$oh_guard" 2>/dev/null
  rm -rf "$oh_dir"
}
trap oh_cleanup EXIT
trap 'exit 130' HUP INT TERM
# 守护进程与终端分组隔离，父进程被强杀后仍能回收所有采集进程组。
oh_launch sh -c '
  oh_dir=$1; oh_owner=$2; oh_ancestors=$3; oh_tick=0
  while [ "$oh_tick" -lt 200 ] && [ ! -f "$oh_dir/done" ]; do
    for oh_ancestor in $oh_ancestors; do
      kill -0 "$oh_ancestor" 2>/dev/null || break 2
    done
    sleep 0.1
    oh_tick=$((oh_tick + 1))
  done
  [ -f "$oh_dir/done" ] || touch "$oh_dir/expired"
  for oh_file in "$oh_dir"/*.pid; do
    [ -f "$oh_file" ] || continue
    read oh_group < "$oh_file"
    case "$oh_group" in ""|*[!0-9]*) continue;; esac
    kill -TERM -- "-$oh_group" 2>/dev/null || :
  done
  sleep 0.05
  for oh_file in "$oh_dir"/*.pid; do
    [ -f "$oh_file" ] || continue
    read oh_group < "$oh_file"
    case "$oh_group" in ""|*[!0-9]*) continue;; esac
    kill -KILL -- "-$oh_group" 2>/dev/null || :
  done
  if ! kill -0 "$oh_owner" 2>/dev/null; then rm -rf "$oh_dir"; fi
' sh "$oh_dir" "$oh_owner" "$oh_ancestors" </dev/null >/dev/null 2>&1 &
oh_guard=$!
''';

/// WSH 协调器与工作脚本分别输出，守护脚本按 PID 和创建时间校验后回收进程树。
String parallelWindowsMaintenanceCommand(
  String prelude,
  List<String> jobs,
  int workers,
) {
  if (workers < 1 || workers > machineMaintenanceMaxWorkers) {
    throw ArgumentError('采集并发数必须在 1–8 之间。');
  }
  final outputPrelude = prelude
      .replaceAll('WScript.Echo(', 'ohEcho(')
      .replaceAll(
        'var start=new Date().getTime();while(child.Status',
        'if(typeof ohTrack=="function")ohTrack(child.ProcessID);var start=new Date().getTime();while(child.Status',
      );
  final common =
      '$outputPrelude\n'
      'function ohEcho(text){if(typeof ohOut!="undefined")ohOut.WriteLine(text);else WScript.Echo(text);}';
  return '''
var ohPrelude=${jsonEncode(common)};
eval(ohPrelude);
var ohJobs=${jsonEncode(jobs)},ohLimit=$workers,ohGuardSource=${jsonEncode(_windowsGuard)},ohWorkerSource=${jsonEncode(_windowsWorkerPrelude)};
$_windowsCoordinator
''';
}

const _windowsWorkerPrelude = r'''
var ohFs=new ActiveXObject("Scripting.FileSystemObject"),ohOut=ohFs.CreateTextFile(WScript.Arguments(0),true,true);
function ohTrack(pid){var p=wmi.Get("Win32_Process.Handle='"+pid+"'");var f=ohFs.CreateTextFile(WScript.Arguments(1)+"\\"+pid+".pid",true,true);f.Write(pid+"|"+p.CreationDate);f.Close();}
try {
''';

const _windowsCoordinator = r'''
var ohFs=new ActiveXObject("Scripting.FileSystemObject"),ohShell=new ActiveXObject("WScript.Shell");
var ohDir=ohFs.BuildPath(ohFs.GetSpecialFolder(2),ohFs.GetTempName());
function ohWrite(path,text){var f=ohFs.CreateTextFile(path,true,true);f.Write(text);f.Close();}
function ohRead(path){var f=ohFs.OpenTextFile(path,1,false,-1);var text=f.ReadAll();f.Close();return text;}
function ohIdentity(id){try{var p=wmi.Get("Win32_Process.Handle='"+id+"'");return [Number(p.ProcessId),String(p.CreationDate),Number(p.ParentProcessId)];}catch(e){return null;}}
var ohOwner=null,ohParent=null,ohSelf=new Enumerator(wmi.ExecQuery("SELECT ProcessId,ParentProcessId,CreationDate,CommandLine FROM Win32_Process WHERE Name='cscript.exe'"));
for(;!ohSelf.atEnd();ohSelf.moveNext()){var p=ohSelf.item();if(String(p.CommandLine).toLowerCase().indexOf(WScript.ScriptFullName.toLowerCase())>=0){ohOwner=[Number(p.ProcessId),String(p.CreationDate)];ohParent=ohIdentity(p.ParentProcessId);break;}}
if(!ohOwner || !ohParent){fail("无法确认采集父进程，已停止本次采集。");}
function ohQuote(s){return '"'+String(s).replace(/\\/g,'\\\\').replace(/"/g,'\\"')+'"';}
var ohAncestors=[ohOwner],ohAncestor=ohParent;
for(var depth=0;ohAncestor && depth<32;depth++){
  ohAncestors.push(ohAncestor);
  if(ohAncestor[2]<=0 || ohAncestor[2]==ohAncestor[0])break;
  var next=ohIdentity(ohAncestor[2]);
  if(next && next[1]>ohAncestor[1])break;
  ohAncestor=next;
}
var ohAncestorText=[];
for(var i=0;i<ohAncestors.length;i++)ohAncestorText.push('['+ohAncestors[i][0]+','+ohQuote(ohAncestors[i][1])+']');
var ohGuardText='var dir='+ohQuote(ohDir)+',ancestors=['+ohAncestorText.join(',')+'];\n'+ohGuardSource;
ohFs.CreateFolder(ohDir);
var ohGuard=null,ohActive=[],ohNext=0,ohDone=0,ohStart=new Date().getTime();
try {
  ohWrite(ohDir+"\\guard.js",ohGuardText);
  ohGuard=ohShell.Exec('cscript.exe //nologo //T:35 "'+ohDir+'\\guard.js"');
  while(ohDone<ohJobs.length){
    if(ohGuard.Status!=0 || new Date().getTime()-ohStart>20000 || ohFs.FileExists(ohDir+"\\expired"))throw Error("并行采集超时或父进程已退出。");
    while(ohNext<ohJobs.length && ohActive.length<ohLimit){
      var path=ohDir+"\\"+ohNext,script=path+".js";ohWrite(script,ohWorkerSource+ohPrelude+"\n"+ohJobs[ohNext]+"\nemit(\"end\",\"\");\n}finally{ohOut.Close();}");
      var child=ohShell.Exec('cscript.exe //nologo //T:20 "'+script+'" "'+path+'.out" "'+ohDir+'"');
      var identity=ohIdentity(child.ProcessID);if(identity)ohWrite(ohDir+"\\"+identity[0]+".pid",identity.join("|"));
      ohActive.push({process:child,index:ohNext++});
    }
    for(var i=ohActive.length-1;i>=0;i--){if(ohActive[i].process.Status!=0){if(ohActive[i].process.ExitCode!=0)throw Error("采集子进程失败。");ohActive.splice(i,1);ohDone++;}}
    if(ohDone<ohJobs.length)WScript.Sleep(30);
  }
  for(var i=0;i<ohJobs.length;i++){
    var output=ohRead(ohDir+"\\"+i+".out");if(output.indexOf("__OH_OPS_end__")<0)throw Error("采集子进程结果不完整。");
    var parts=output.split(/__OH_OPS_([a-z_]+)__\r?\n/);
    for(var j=1;j+1<parts.length;j+=2){var key=parts[j];if(/^(platform|host|boot|uptime|encoding|end)$/.test(key))continue;if(key=="notice"){warnings.push(decodeURIComponent(parts[j+1].replace(/\s+$/, "")));continue;}var block="__OH_OPS_"+key+"__\n"+parts[j+1];if(emitted+block.length>100000){truncated=true;continue;}WScript.Echo(block);emitted+=block.length;}
  }
  emit("end","");
} catch(e){WScript.Echo("并行采集失败："+e.message);throw e;}
finally {
  if(ohGuard){
    ohWrite(ohDir+"\\done","");var until=new Date().getTime()+4000;
    while(ohGuard.Status==0 && new Date().getTime()<until)WScript.Sleep(30);
  }
  if(!ohGuard || ohGuard.Status!=0){try{ohFs.DeleteFolder(ohDir,true);}catch(e){}}
}
''';

const _windowsGuard = r'''
var fs=new ActiveXObject("Scripting.FileSystemObject"),shell=new ActiveXObject("WScript.Shell"),wmi=GetObject("winmgmts:!\\\\.\\root\\cimv2");
function alive(p){try{return String(wmi.Get("Win32_Process.Handle='"+p[0]+"'").CreationDate)==p[1];}catch(e){return false;}}
function parentsAlive(){for(var i=0;i<ancestors.length;i++)if(!alive(ancestors[i]))return false;return true;}
var start=new Date().getTime();
while(new Date().getTime()-start<22000 && parentsAlive() && !fs.FileExists(dir+"\\done"))WScript.Sleep(100);
if(!fs.FileExists(dir+"\\done")){var f=fs.CreateTextFile(dir+"\\expired",true);f.Close();}
var files=new Enumerator(fs.GetFolder(dir).Files),killers=[];
for(;!files.atEnd();files.moveNext()){
  var path=String(files.item().Path);
  if(!/\.pid$/.test(path))continue;
  try{
    var f=fs.OpenTextFile(path,1,false,-1),p=f.ReadAll().split("|");f.Close();
    if(alive(p))killers.push(shell.Exec("taskkill.exe /PID "+Number(p[0])+" /T /F"));
  }catch(e){}
}
var until=new Date().getTime()+2500;
for(var i=0;i<killers.length;i++){
  while(killers[i].Status==0 && new Date().getTime()<until)WScript.Sleep(30);
  if(killers[i].Status==0)killers[i].Terminate();
}
try{fs.DeleteFolder(dir,true);}catch(e){}
''';
