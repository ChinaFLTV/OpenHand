part of 'machine_scheduled_tasks.dart';

const _taskPosixPrelude = r'''
export LC_ALL=C LANG=C SYSTEMD_COLORS=0 SYSTEMD_PAGER=cat PAGER=cat
umask 077
oh_task_tmp=$(mktemp -d "${TMPDIR:-/tmp}/openhand-tasks.XXXXXXXX") || exit 1
oh_task_lock=''; oh_staged=''
task_cleanup() { [ -z "$oh_staged" ] || rm -f "$oh_staged"; rm -rf "$oh_task_tmp"; [ -z "$oh_task_lock" ] || rmdir "$oh_task_lock" 2>/dev/null; }
trap 'task_cleanup' EXIT
trap 'exit 130' HUP INT TERM
task_emit() {
  printf '__OH_TASK__\t%s' "$1"; shift
  for oh_value do printf '\t'; printf '%s' "$oh_value" | base64 | tr -d '\r\n'; done
  printf '\n'
}
task_fail() { task_emit error "$1" "${2:-}"; printf '__OH_TASK_END__\n'; exit 0; }
task_bounded() {
  if command -v timeout >/dev/null 2>&1; then timeout -k 1 6 "$@"
  elif command -v perl >/dev/null 2>&1; then perl -e 'alarm 6; exec @ARGV' -- "$@"
  else "$@"; fi
}
task_decode() {
  if [ "$(uname -s)" = Darwin ]; then base64 -D; else base64 -d; fi
}
task_read_cron() {
  if [ "$1" = "$(id -un)" ]; then task_bounded crontab -l > "$2" 2> "$oh_task_tmp/error"
  else task_bounded crontab -u "$1" -l > "$2" 2> "$oh_task_tmp/error"; fi
  oh_code=$?
  if [ "$oh_code" -ne 0 ]; then
    if [ "$oh_code" -eq 1 ] && grep -qi 'no crontab for' "$oh_task_tmp/error"; then : > "$2"
    else return "$oh_code"; fi
  fi
  [ "$(wc -c < "$2")" -le 131072 ] || return 65
}
task_file_emit() {
  if [ ! -r "$1" ]; then task_emit issue "$1" permission; return; fi
  if [ "$(wc -c < "$1")" -gt 131072 ]; then task_emit issue "$1" limit; return; fi
  oh_writable=0
  [ -w "$1" ] && [ ! -L "$1" ] && [ -w "${1%/*}" ] && oh_writable=1
  oh_content=$(cat "$1"; printf '.')
  task_emit cron "$1" root "${oh_content%.}" "$oh_writable"
}
task_emit meta "$(id -un)" "$(date +'%Z %z')" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
''';

const _taskCronCollect = r'''
if command -v crontab >/dev/null 2>&1; then
  if task_read_cron "$(id -un)" "$oh_task_tmp/cron"; then
    task_emit available cron
    oh_content=$(cat "$oh_task_tmp/cron"; printf '.')
    task_emit cron "user:$(id -un)" "$(id -un)" "${oh_content%.}" 1
  else task_emit issue crontab "$(cat "$oh_task_tmp/error")"; fi
else task_emit issue crontab unavailable; fi
if [ "$(uname -s)" = Linux ]; then
  [ ! -f /etc/crontab ] || task_file_emit /etc/crontab
  oh_count=0
  for oh_file in /etc/cron.d/*; do
    [ -f "$oh_file" ] || continue
    oh_count=$((oh_count + 1))
    if [ "$oh_count" -gt 128 ]; then task_emit issue cron.d limit; break; fi
    task_file_emit "$oh_file"
  done
  if [ "$(id -u)" = 0 ] && command -v crontab >/dev/null 2>&1; then
    oh_count=0
    for oh_file in /var/spool/cron/* /var/spool/cron/crontabs/*; do
      [ -f "$oh_file" ] && [ ! -L "$oh_file" ] || continue
      oh_user=${oh_file##*/}; [ "$oh_user" != "$(id -un)" ] || continue
      oh_count=$((oh_count + 1))
      if [ "$oh_count" -gt 64 ]; then task_emit issue crontabs limit; break; fi
      if task_read_cron "$oh_user" "$oh_task_tmp/cron"; then
        oh_content=$(cat "$oh_task_tmp/cron"; printf '.')
        task_emit cron "user:$oh_user" "$oh_user" "${oh_content%.}" 1
      else task_emit issue "user:$oh_user" "$(cat "$oh_task_tmp/error")"; fi
    done
  fi
fi
''';

const _taskSystemdCollect = r'''
if command -v systemctl >/dev/null 2>&1; then
  for oh_scope in system user; do
    if ! task_bounded systemctl --"$oh_scope" list-unit-files --type=timer --no-legend --no-pager > "$oh_task_tmp/names" 2> "$oh_task_tmp/error"; then
      task_emit issue "systemd/$oh_scope" "$(cat "$oh_task_tmp/error")"; continue
    fi
    task_emit available systemd
    if task_bounded systemctl --"$oh_scope" list-units --all --type=timer --plain --no-legend --no-pager > "$oh_task_tmp/loaded" 2> "$oh_task_tmp/error"; then cat "$oh_task_tmp/loaded" >> "$oh_task_tmp/names"
    else task_emit issue "systemd/$oh_scope" "$(cat "$oh_task_tmp/error")"; fi
    awk '{if ($1 ~ /[.]timer$/) print $1}' "$oh_task_tmp/names" | sort -u > "$oh_task_tmp/sorted"
    if [ "$(wc -l < "$oh_task_tmp/sorted")" -gt 256 ]; then task_emit issue "systemd/$oh_scope" limit; fi
    set --
    while IFS= read -r oh_name; do set -- "$@" "$oh_name"; [ "$#" -lt 256 ] || break; done < "$oh_task_tmp/sorted"
    [ "$#" -gt 0 ] || continue
    if task_bounded systemctl --"$oh_scope" show --no-pager -p Id -p Description -p LoadState -p ActiveState -p SubState -p UnitFileState -p Unit -p FragmentPath -p DropInPaths -p NextElapseUSecRealtime -p NextElapseUSecMonotonic -p LastTriggerUSec -p TimersCalendar -p TimersMonotonic -p AccuracyUSec -p RandomizedDelayUSec -p Persistent -p Result -- "$@" > "$oh_task_tmp/timers" 2> "$oh_task_tmp/error"; then
      if [ "$(wc -c < "$oh_task_tmp/timers")" -le 1048576 ]; then task_emit systemd "$oh_scope" "$(cat "$oh_task_tmp/timers")"
      else task_emit issue "systemd/$oh_scope" limit; fi
    else task_emit issue "systemd/$oh_scope" "$(cat "$oh_task_tmp/error")"; fi
  done
fi
''';

const _taskLaunchdCollect = r'''
if command -v launchctl >/dev/null 2>&1 && command -v plutil >/dev/null 2>&1; then
  task_emit available launchd
  task_bounded launchctl list > "$oh_task_tmp/launch" 2> "$oh_task_tmp/error" || task_emit issue launchd "$(cat "$oh_task_tmp/error")"
  task_bounded launchctl print system > "$oh_task_tmp/launch-system" 2> "$oh_task_tmp/error" || task_emit issue launchd/system "$(cat "$oh_task_tmp/error")"
  oh_count=0
  for oh_file in "$HOME"/Library/LaunchAgents/*.plist /Library/LaunchAgents/*.plist /Library/LaunchDaemons/*.plist /System/Library/LaunchAgents/*.plist /System/Library/LaunchDaemons/*.plist; do
    [ -f "$oh_file" ] || continue
    if ! plutil -convert xml1 -o "$oh_task_tmp/plist" "$oh_file" 2> "$oh_task_tmp/error"; then task_emit issue "$oh_file" "$(cat "$oh_task_tmp/error")"; continue; fi
    grep -qE '<key>Start(Interval|CalendarInterval)</key>' "$oh_task_tmp/plist" || continue
    oh_count=$((oh_count + 1))
    if [ "$oh_count" -gt 256 ]; then task_emit issue launchd limit; break; fi
    [ "$(wc -c < "$oh_task_tmp/plist")" -le 131072 ] || { task_emit issue "$oh_file" limit; continue; }
    oh_label=$(/usr/libexec/PlistBuddy -c 'Print :Label' "$oh_file" 2>/dev/null)
    oh_owner=$(id -un); oh_table="$oh_task_tmp/launch"; oh_writable=0
    case "$oh_file" in */LaunchDaemons/*) oh_owner=system; oh_table="$oh_task_tmp/launch-system";; esac
    oh_state=$(awk -v name="$oh_label" '$3==name {print ($1=="-" || $1=="0" ? "loaded" : "running") "\t" ($2 ~ /^-?[0-9]+$/ ? $2 : "")}' "$oh_table")
    if [ -z "$oh_state" ]; then
      if [ -s "$oh_table" ]; then oh_state=$(printf 'inactive\t'); else oh_state=$(printf 'unknown\t'); fi
    fi
    case "$oh_file" in "$HOME"/Library/LaunchAgents/*) [ -w "$oh_file" ] && [ ! -L "$oh_file" ] && oh_writable=1;; esac
    task_emit launchd "$oh_file" "$(cat "$oh_task_tmp/plist")" "$oh_owner" "$(printf '%s\t%s' "$oh_state" "$oh_writable")"
  done
fi
''';

String _taskCronWrite(String source, String original, String content) {
  final currentUser = source.startsWith('user:');
  if (!currentUser &&
      !RegExp(r'^/etc/(crontab|cron\.d/[A-Za-z0-9_-]+)$').hasMatch(source)) {
    throw const MachineTaskException('permission');
  }
  if (currentUser &&
      !RegExp(r'^[A-Za-z0-9_.-]+\$?$').hasMatch(source.substring(5))) {
    throw const MachineTaskException('validation');
  }
  final target = posixShellQuote(currentUser ? source.substring(5) : source);
  return '''$_taskPosixPrelude
oh_target=$target
oh_lock_path="\${TMPDIR:-/tmp}/openhand-crontab-\$(id -u).lock"
mkdir "\$oh_lock_path" 2>/dev/null || task_fail busy
oh_task_lock="\$oh_lock_path"
printf '%s' '${base64Encode(utf8.encode(original))}' | task_decode > "\$oh_task_tmp/expected" || task_fail validation
printf '%s' '${base64Encode(utf8.encode(content))}' | task_decode > "\$oh_task_tmp/replacement" || task_fail validation
${currentUser ? r'''
task_read_cron "$oh_target" "$oh_task_tmp/current" || task_fail permission "$(cat "$oh_task_tmp/error")"
cmp -s "$oh_task_tmp/current" "$oh_task_tmp/expected" || task_fail conflict
if [ "$oh_target" = "$(id -un)" ]; then task_bounded crontab "$oh_task_tmp/replacement" > "$oh_task_tmp/result" 2>&1
else task_bounded crontab -u "$oh_target" "$oh_task_tmp/replacement" > "$oh_task_tmp/result" 2>&1; fi
[ "$?" = 0 ] || task_fail save "$(cat "$oh_task_tmp/result")"
task_read_cron "$oh_target" "$oh_task_tmp/current" || task_fail verify
cmp -s "$oh_task_tmp/current" "$oh_task_tmp/replacement" || task_fail verify
''' : r'''
[ -f "$oh_target" ] && [ ! -L "$oh_target" ] && [ -w "$oh_target" ] || task_fail permission
cmp -s "$oh_target" "$oh_task_tmp/expected" || task_fail conflict
oh_staged=$(mktemp "${oh_target%/*}/.openhand-cron.XXXXXXXX") || task_fail permission
if ! cp -p "$oh_target" "$oh_staged" || ! cat "$oh_task_tmp/replacement" > "$oh_staged"; then rm -f "$oh_staged"; task_fail save; fi
if ! cmp -s "$oh_target" "$oh_task_tmp/expected"; then rm -f "$oh_staged"; task_fail conflict; fi
if ! mv -f "$oh_staged" "$oh_target"; then rm -f "$oh_staged"; task_fail save; fi
cmp -s "$oh_target" "$oh_task_tmp/replacement" || task_fail verify
'''}
task_emit saved; printf '__OH_TASK_END__\\n'
''';
}

String _taskDetailCommand(MachineScheduledTask task, String platform) {
  if (platform == 'Windows') {
    return '''$_taskWindowsPrelude
var task=taskService.GetFolder("\\\\").GetTask(${jsonEncode(task.id)});
emit("windows",task.Path,task.Xml,task.State,task.Enabled?"1":"0",date(task.LastRunTime),date(task.NextRunTime),task.LastTaskResult,task.NumberOfMissedRuns);
emit("definition", task.Xml, "1");
emit("status", "State="+task.State+"\\nLastTaskResult="+task.LastTaskResult+"\\nNumberOfMissedRuns="+task.NumberOfMissedRuns);
var taskPath=${jsonEncode(task.id)};
var fso=new ActiveXObject("Scripting.FileSystemObject"), shell=new ActiveXObject("WScript.Shell");
var temporary=fso.GetSpecialFolder(2)+"\\\\"+fso.GetTempName(), queryFile=temporary+".xml", outputFile=temporary+".out", errorFile=temporary+".err";
try {
  var filter="*[System[TimeCreated[timediff(@SystemTime) <= 604800000]]]";
  if(taskPath.indexOf("'")<0)filter="*[System[TimeCreated[timediff(@SystemTime) <= 604800000]] and EventData[Data[@Name='TaskName'] = '"+taskPath+"']]";
  var queryXml='<QueryList><Query Id="0" Path="Microsoft-Windows-TaskScheduler/Operational"><Select Path="Microsoft-Windows-TaskScheduler/Operational">'+filter.replace(/&/g,"&amp;").replace(/</g,"&lt;")+'</Select></Query></QueryList>';
  var file=fso.CreateTextFile(queryFile,true,true);file.Write(queryXml);file.Close();
  var executable=shell.ExpandEnvironmentStrings("%SystemRoot%")+"\\\\System32\\\\wevtutil.exe";
  var process=shell.Exec('cmd.exe /d /s /c ""'+executable+'" qe "'+queryFile+'" /sq:true /rd:true /c:120 /f:xml /uni:true > "'+outputFile+'" 2> "'+errorFile+'""');
  var started=new Date().getTime();
  while(process.Status==0 && new Date().getTime()-started<6500)WScript.Sleep(40);
  if(process.Status==0) {
    shell.Run('taskkill.exe /PID '+process.ProcessID+' /T /F',0,false);process.Terminate();emit("issue","logs","timeout");
  } else if(process.ExitCode!=0) { emit("issue","logs","unavailable"); }
  else if(fso.GetFile(outputFile).Size>1048576) {emit("issue","logs","limit");}
  else {
    var reader=fso.OpenTextFile(outputFile,1,false,-1), xml=reader.ReadAll();reader.Close();
    var document=new ActiveXObject("Msxml2.DOMDocument.6.0"); document.async=false;
    xml=xml.replace(/^\\uFEFF/,"").replace(/<\\?xml[^>]*\\?>/g,"");
    if(!document.loadXML('<Events>'+xml+'</Events>')) { emit("issue","logs","unavailable"); }
    else {
      document.setProperty("SelectionLanguage","XPath");
      var events=document.selectNodes("/*[local-name()='Events']/*[local-name()='Event']"), logs=[];
      for(var i=0;i<events.length;i++) {
        var data=events[i].selectNodes("*[local-name()='EventData']/*[local-name()='Data']"),match=false;
        for(var j=0;j<data.length;j++) if(data[j].getAttribute("Name")=="TaskName" && data[j].text==taskPath)match=true;
        if(match) logs.push(events[i].xml);
      }
      emit("logs", logs.join("\\n"));
    }
  }
} catch(e) { emit("issue","logs", e.message); }
finally { for(var i=0;i<3;i++) {var path=[queryFile,outputFile,errorFile][i];try {if(fso.FileExists(path))fso.DeleteFile(path,true);}catch(e){emit("issue","logs",e.message);}} }
WScript.Echo("__OH_TASK_END__");
''';
  }
  const prefix = '$_taskPosixPrelude\n';
  if (task.scheduler == MachineTaskScheduler.systemd) {
    final scope = task.owner == 'user' ? '--user' : '--system';
    final name = posixShellQuote(task.name),
        path = posixShellQuote(task.source);
    return '''$prefix
oh_target=$path
oh_writable=0
case "\$oh_target" in /etc/systemd/system/*.timer|"\$HOME"/.config/systemd/user/*.timer)
  [ -f "\$oh_target" ] && [ ! -L "\$oh_target" ] && [ -w "\$oh_target" ] && [ -w "\${oh_target%/*}" ] && oh_writable=1;; esac
if [ -r "\$oh_target" ] && [ "\$(wc -c < "\$oh_target")" -le 131072 ]; then
  oh_content=\$(cat "\$oh_target"; printf '.'); task_emit definition "\${oh_content%.}" "\$oh_writable"
else task_emit issue definition permission; task_emit definition '' 0; fi
if task_bounded systemctl $scope show --no-pager -p Id -p Description -p ActiveState -p SubState -p LoadState -p UnitFileState -p Unit -p FragmentPath -p DropInPaths -p LastTriggerUSec -p NextElapseUSecRealtime -p TimersCalendar -p TimersMonotonic -p AccuracyUSec -p RandomizedDelayUSec -p Persistent -p MainPID -p MemoryCurrent -p CPUUsageNSec -p TasksCurrent -p NRestarts -p ExecMainStatus -p ExecMainStartTimestamp -p ExecMainExitTimestamp -p Result -- $name ${posixShellQuote(task.command)} > "\$oh_task_tmp/status" 2> "\$oh_task_tmp/error"; then
  task_emit systemd ${posixShellQuote(task.owner)} "\$(head -c 64000 "\$oh_task_tmp/status")"
  task_emit status "\$(head -c 64000 "\$oh_task_tmp/status")"
else task_emit issue status "\$(cat "\$oh_task_tmp/error")"; fi
if task_bounded journalctl ${task.owner == 'user' ? '--user' : ''} -u $name -u ${posixShellQuote(task.command)} --since '7 days ago' -n 120 --no-pager -o short-iso > "\$oh_task_tmp/logs" 2> "\$oh_task_tmp/error"; then
  task_emit logs "\$(tail -c 64000 "\$oh_task_tmp/logs")"
else task_emit issue logs "\$(cat "\$oh_task_tmp/error")"; fi
printf '__OH_TASK_END__\\n'
''';
  }
  if (task.scheduler == MachineTaskScheduler.launchd) {
    final domain = task.owner == 'system' ? 'system' : r'gui/$(id -u)';
    return '''$prefix
oh_target=${posixShellQuote(task.source)}
oh_state=unknown; oh_result=''; oh_writable=0
if task_bounded launchctl print "$domain/"${posixShellQuote(task.name)} > "\$oh_task_tmp/status" 2> "\$oh_task_tmp/error"; then
  task_emit status "\$(head -c 64000 "\$oh_task_tmp/status")"
  oh_state=loaded
  grep -Eq '^[[:space:]]*state = running[[:space:]]*\$' "\$oh_task_tmp/status" && oh_state=running
  oh_result=\$(awk '/^[ \\t]*last exit code =/ {print \$5; exit}' "\$oh_task_tmp/status")
else task_emit issue status "\$(cat "\$oh_task_tmp/error")"; fi
case "\$oh_target" in "\$HOME"/Library/LaunchAgents/*.plist)
  [ -f "\$oh_target" ] && [ ! -L "\$oh_target" ] && [ -w "\$oh_target" ] && [ -w "\${oh_target%/*}" ] && oh_writable=1;; esac
if [ -f "\$oh_target" ] && plutil -convert xml1 -o "\$oh_task_tmp/plist" "\$oh_target" 2> "\$oh_task_tmp/error"; then
  if [ "\$(wc -c < "\$oh_task_tmp/plist")" -le 131072 ]; then
    task_emit launchd "\$oh_target" "\$(cat "\$oh_task_tmp/plist")" ${posixShellQuote(task.owner)} "\$(printf '%s\\t%s\\t%s' "\$oh_state" "\$oh_result" "\$oh_writable")"
  else task_emit issue definition limit; task_emit definition '' 0; fi
else task_emit issue definition "\$(cat "\$oh_task_tmp/error")"; task_emit definition '' 0; fi
oh_previous_log=''
for oh_key in StandardOutPath StandardErrorPath; do
  oh_log=\$(/usr/libexec/PlistBuddy -c "Print :\$oh_key" "\$oh_target" 2>/dev/null) || continue
  case "\$oh_log" in /*) ;; *) continue;; esac
  [ "\$oh_log" != "\$oh_previous_log" ] || continue
  oh_previous_log=\$oh_log
  if [ -f "\$oh_log" ] && [ -r "\$oh_log" ]; then task_emit logs "\$(tail -n 120 "\$oh_log" | tail -c 32000)"
  else task_emit issue logs permission; fi
done
printf '__OH_TASK_END__\\n'
''';
  }
  return '''$prefix
${platform == 'Darwin' ? '''
if task_bounded log show --last 1d --style syslog --predicate 'process == "cron"' > "\$oh_task_tmp/logs" 2> "\$oh_task_tmp/error"; then
  task_emit logs "\$(grep -F -- ${posixShellQuote(task.command)} "\$oh_task_tmp/logs" | tail -n 120 | tail -c 64000)"
else task_emit issue logs "\$(cat "\$oh_task_tmp/error")"; fi
''' : '''
if task_bounded journalctl -u cron -u crond --since '7 days ago' -n 500 --no-pager -o short-iso > "\$oh_task_tmp/logs" 2> "\$oh_task_tmp/error"; then
  task_emit logs "\$(grep -F -- ${posixShellQuote('(${task.owner})')} "\$oh_task_tmp/logs" | grep -F -- ${posixShellQuote(task.command)} | tail -n 120 | tail -c 64000)"
elif [ -r /var/log/cron ]; then
  task_emit logs "\$(tail -n 2000 /var/log/cron | grep -F -- ${posixShellQuote('(${task.owner})')} | grep -F -- ${posixShellQuote(task.command)} | tail -n 120 | tail -c 64000)"
else task_emit issue logs "\$(cat "\$oh_task_tmp/error")"; fi
'''}
printf '__OH_TASK_END__\\n'
''';
}

String _taskNativeWrite(
  MachineScheduledTask? task, {
  required String platform,
  required String name,
  required String definition,
  bool delete = false,
}) {
  if (platform == 'Windows') {
    final path = task?.id ?? '\\$name';
    if (path.length > 238 ||
        !path.startsWith('\\') ||
        RegExp(r'[\r\n\x00"<>|?*]').hasMatch(path) ||
        path.endsWith('\\')) {
      throw const MachineTaskException('validation');
    }
    final parent = path.lastIndexOf('\\') == 0
        ? '\\'
        : path.substring(0, path.lastIndexOf('\\'));
    return '''$_taskWindowsPrelude
try {
  var folder=taskService.GetFolder(${jsonEncode(parent)}), name=${jsonEncode(path.split('\\').last)};
  var current=null; try {current=folder.GetTask(name);} catch(e) {if((e.number & 65535)!=2 && (e.number & 65535)!=3)throw e;}
  ${task == null ? 'if(current)fail("conflict");' : 'if(!current || current.Xml!==${jsonEncode(task.definition)})fail("conflict");'}
  ${delete ? 'folder.DeleteTask(name,0);' : '''
  var xml=${jsonEncode(definition)}, validation=taskService.NewTask(0); validation.XmlText=xml;
  var principal=validation.Principal;
  if(principal.LogonType==1 || principal.LogonType==6)fail("credentials");
  folder.RegisterTask(name,xml,1,null,null,principal.LogonType,null);
  ${task == null ? 'try {folder.GetTask(name); fail("conflict");} catch(e) {if((e.number & 65535)!=2 && (e.number & 65535)!=3)throw e;}' : 'if(folder.GetTask(name).Xml!==${jsonEncode(task.definition)})fail("conflict");'}
  folder.RegisterTask(name,xml,${task == null ? 34 : 52},null,null,principal.LogonType,null);
  folder.GetTask(name);
  '''}
  emit("saved"); WScript.Echo("__OH_TASK_END__");
} catch(e) {fail("save",e.message);}
''';
  }
  if (task == null) throw const MachineTaskException('validation');
  final launchd = task.scheduler == MachineTaskScheduler.launchd;
  final scope = task.owner == 'user' ? '--user' : '--system';
  final path = posixShellQuote(task.source);
  final timer = posixShellQuote(task.name);
  return '''$_taskPosixPrelude
oh_target=$path
${launchd ? r'''case "$oh_target" in "$HOME"/Library/LaunchAgents/*.plist) ;; *) task_fail permission;; esac''' : r'''case "$oh_target" in /etc/systemd/system/*.timer|"$HOME"/.config/systemd/user/*.timer) ;; *) task_fail permission;; esac'''}
[ -f "\$oh_target" ] && [ ! -L "\$oh_target" ] && [ -w "\$oh_target" ] || task_fail permission
oh_lock_path="\${TMPDIR:-/tmp}/openhand-tasks-\$(id -u).lock"
mkdir "\$oh_lock_path" 2>/dev/null || task_fail busy
oh_task_lock="\$oh_lock_path"
printf '%s' '${base64Encode(utf8.encode(task.definition))}' | task_decode > "\$oh_task_tmp/expected" || task_fail validation
task_compare() {
  [ ! -L "\$oh_target" ] || return 1
  ${launchd ? r'''plutil -convert xml1 -o "$oh_task_tmp/current" "$oh_target" >/dev/null 2>&1 || return 1
  [ "$(cat "$oh_task_tmp/current")" = "$(cat "$oh_task_tmp/expected")" ]''' : r'''cmp -s "$oh_target" "$oh_task_tmp/expected"'''}
}
task_compare || task_fail conflict
cp -p "\$oh_target" "\$oh_task_tmp/backup" || task_fail save
oh_changed=0; oh_active=0; oh_enabled=''; oh_domain="gui/\$(id -u)"
${launchd ? 'launchctl print "\$oh_domain/"$timer >/dev/null 2>&1 && oh_active=1' : '''systemctl $scope is-active --quiet -- $timer && oh_active=1
oh_enabled=\$(systemctl $scope is-enabled -- $timer 2>/dev/null)'''}
task_restore() {
  cp -p "\$oh_task_tmp/backup" "\$oh_target" || return 1
  ${launchd ? '''if [ "\$oh_active" = 1 ]; then
    launchctl print "\$oh_domain/"$timer >/dev/null 2>&1 && task_bounded launchctl bootout "\$oh_domain/"$timer >/dev/null 2>&1
    task_bounded launchctl bootstrap "\$oh_domain" "\$oh_target" >/dev/null 2>&1 || return 1
  fi''' : '''task_bounded systemctl $scope daemon-reload >/dev/null 2>&1 || return 1
  ${delete ? '''case "\$oh_enabled" in
    enabled) task_bounded systemctl $scope enable -- $timer >/dev/null 2>&1 || return 1;;
    enabled-runtime) task_bounded systemctl $scope enable --runtime -- $timer >/dev/null 2>&1 || return 1;;
  esac''' : ''}
  [ "\$oh_active" = 0 ] || task_bounded systemctl $scope restart -- $timer >/dev/null 2>&1 || return 1'''}
  return 0
}
task_finish() {
  if [ "\$oh_changed" = 1 ] && ! task_restore; then task_emit error rollback ''; printf '__OH_TASK_END__\\n'; fi
  task_cleanup
}
trap 'task_finish' EXIT
${delete ? '' : '''
printf '%s' '${base64Encode(utf8.encode(definition))}' | task_decode > "\$oh_task_tmp/replacement" || task_fail validation
${launchd ? r'''plutil -lint "$oh_task_tmp/replacement" > "$oh_task_tmp/result" 2>&1 || task_fail validation "$(cat "$oh_task_tmp/result")"''' : '''if command -v systemd-analyze >/dev/null 2>&1; then
  cp "\$oh_task_tmp/replacement" "\$oh_task_tmp/"$timer || task_fail validation
  task_bounded systemd-analyze $scope verify "\$oh_task_tmp/"$timer > "\$oh_task_tmp/result" 2>&1 || task_fail validation "\$(cat "\$oh_task_tmp/result")"
fi'''}
oh_staged=\$(mktemp "\${oh_target%/*}/.openhand-task.XXXXXXXX") || task_fail permission
cp -p "\$oh_target" "\$oh_staged" && cat "\$oh_task_tmp/replacement" > "\$oh_staged" || task_fail save
'''}
task_compare || task_fail conflict
oh_changed=1
${launchd
      ? '''if [ "\$oh_active" = 1 ]; then task_bounded launchctl bootout "\$oh_domain/"$timer > "\$oh_task_tmp/result" 2>&1 || task_fail save "\$(cat "\$oh_task_tmp/result")"; fi'''
      : delete
      ? 'task_bounded systemctl $scope disable --now -- $timer > "\$oh_task_tmp/result" 2>&1 || task_fail save "\$(cat "\$oh_task_tmp/result")"'
      : ''}
${delete ? r'''rm -- "$oh_target" || task_fail save''' : r'''mv -f "$oh_staged" "$oh_target" || task_fail save
cmp -s "$oh_target" "$oh_task_tmp/replacement" || task_fail verify'''}
${launchd
      ? delete
            ? ''
            : '''if [ "\$oh_active" = 1 ]; then task_bounded launchctl bootstrap "\$oh_domain" "\$oh_target" > "\$oh_task_tmp/result" 2>&1 || task_fail save "\$(cat "\$oh_task_tmp/result")"; fi'''
      : '''task_bounded systemctl $scope daemon-reload > "\$oh_task_tmp/result" 2>&1 || task_fail save "\$(cat "\$oh_task_tmp/result")"
${delete ? '' : '''oh_load=\$(task_bounded systemctl $scope show -p LoadState -- $timer)
[ "\$oh_load" = 'LoadState=loaded' ] || task_fail validation "\$oh_load"
if [ "\$oh_active" = 1 ]; then task_bounded systemctl $scope restart -- $timer > "\$oh_task_tmp/result" 2>&1 || task_fail save "\$(cat "\$oh_task_tmp/result")"; fi'''}
'''}
oh_changed=0
task_emit saved; printf '__OH_TASK_END__\\n'
''';
}

const _taskWindowsPrelude = r'''
var emitted=0, truncated=false;
function emit(kind) { var values=["__OH_TASK_URI__",kind]; for(var i=1;i<arguments.length;i++)values.push(encodeURIComponent(arguments[i]==null?"":String(arguments[i]))); var line=values.join("\t"); if(emitted+line.length>3800000 && kind!="issue" && kind!="error"){truncated=true;return;} emitted+=line.length+1; WScript.Echo(line); }
function fail(code,detail) { emit("error",code,detail||""); WScript.Echo("__OH_TASK_END__"); WScript.Quit(0); }
function date(value) { var d=new Date(value); if(isNaN(d.getTime()) || d.getFullYear()<1971)return ""; function pad(n){return n<10?"0"+n:String(n);} return d.getFullYear()+"-"+pad(d.getMonth()+1)+"-"+pad(d.getDate())+" "+pad(d.getHours())+":"+pad(d.getMinutes())+":"+pad(d.getSeconds()); }
var wmi=GetObject("winmgmts:{impersonationLevel=impersonate}!\\\\.\\root\\cimv2"), osItems=new Enumerator(wmi.ExecQuery("SELECT CSName,LastBootUpTime,LocalDateTime FROM Win32_OperatingSystem"));
if(osItems.atEnd())fail("identity");
var os=osItems.item();
if(typeof ohExpectedHost!="undefined" && (String(os.CSName)!==ohExpectedHost || String(os.LastBootUpTime)!==ohExpectedBoot))fail("identity");
var network=new ActiveXObject("WScript.Network"), taskService;
try {taskService=new ActiveXObject("Schedule.Service");taskService.Connect();}catch(e){fail("unavailable",e.message);}
emit("meta",network.UserDomain+"\\"+network.UserName,"UTC"+String(os.LocalDateTime).substr(21,1)+Math.floor(Number(String(os.LocalDateTime).substr(22,3))/60)+":"+("0"+(Number(String(os.LocalDateTime).substr(22,3))%60)).slice(-2),date(new Date()));
emit("available","windows");
''';

const _taskWindowsCollect = r'''
var folders=[taskService.GetFolder("\\")], visited=0, count=0;
while(folders.length && visited<256 && count<512 && !truncated) {
  var folder=folders.shift(); visited++;
  try {
    var tasks=folder.GetTasks(1);
    for(var i=1;i<=tasks.Count && count<512 && !truncated;i++) {
      var task=tasks.Item(i); count++;
      try {
        var xml=String(task.Xml);
        if(xml.length>131072) {emit("issue",task.Path,"limit");continue;}
        emit("windows",task.Path,xml,task.State,task.Enabled?"1":"0",date(task.LastRunTime),date(task.NextRunTime),task.LastTaskResult,task.NumberOfMissedRuns);
      } catch(e) {emit("issue",task.Path,e.message);}
    }
    var children=folder.GetFolders(0);
    for(var i=1;i<=children.Count && folders.length<256;i++)folders.push(children.Item(i));
  } catch(e) {emit("issue",folder.Path,e.message);}
}
if(folders.length || count>=512 || truncated)emit("issue","limit","limit");
WScript.Echo("__OH_TASK_END__");
''';
