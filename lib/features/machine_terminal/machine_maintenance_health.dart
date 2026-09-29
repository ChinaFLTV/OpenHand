const machineHealthSections = [
  'system',
  'sessions',
  'logins',
  'accounts',
  'password',
  'ssh',
  'temperature',
  'power',
  'clock',
  'sync',
  'ntp',
];

const machineHealthPosixPrelude = r'''
health() {
  key=$1; shift
  section "health_$key"
  "$@" 2>&1
  result=$?
  section "health_${key}_status"
  printf '%s\n' "$result"
}
''';

const machineHealthLinuxCollection =
    machineHealthPosixPrelude +
    r'''
health system sh -c 'uname -a; if [ -r /etc/os-release ]; then cat /etc/os-release; else sw_vers; fi'
health sessions who -u
health logins sh -c 'last -n 30 -F 2>/dev/null || last -n 30'
health accounts sh -c 'printf "@user\tuid\thome\tshell\n"; getent passwd | awk -F: "{print \$1 \"\t\" \$3 \"\t\" \$6 \"\t\" \$7}" | head -n 200'
health password sh -c 'passwd -S "$(id -un)" && chage -l "$(id -un)"'
health ssh sh -c 'bin=$(command -v sshd); [ -n "$bin" ] || bin=/usr/sbin/sshd; [ -x "$bin" ] || exit 127; data=$("$bin" -T 2>&1); result=$?; if [ "$result" != 0 ]; then printf "%s\n" "$data"; exit "$result"; fi; printf "%s\n" "$data" | awk "\$1 ~ /^(port|listenaddress|permitrootlogin|passwordauthentication|pubkeyauthentication|kbdinteractiveauthentication|permitemptypasswords|maxauthtries|maxsessions|logingracetime|clientaliveinterval|clientalivecountmax|allowusers|denyusers|allowgroups|denygroups|authenticationmethods|usepam)$/"'
health temperature sh -c 'printf "@sensor\tcelsius\n"; found=0; for f in /sys/class/thermal/thermal_zone*/temp /sys/class/hwmon/hwmon*/temp*_input; do [ -r "$f" ] || continue; found=1; awk -v name="$f" "{printf \"%s\t%.1f\n\", name, \$1/1000}" "$f"; done; [ "$found" = 1 ] || exit 125'
health power sh -c 'found=0; for d in /sys/class/power_supply/*; do [ -d "$d" ] || continue; found=1; printf "%s\n" "$d"; for f in type status capacity health cycle_count; do [ -r "$d/$f" ] && printf "%s: %s\n" "$f" "$(cat "$d/$f")"; done; done; [ "$found" = 1 ] || exit 125'
health clock sh -c 'date "+%Y-%m-%d %H:%M:%S %Z %z"; date -u "+%Y-%m-%d %H:%M:%S UTC"'
health sync timedatectl show --property=Timezone --property=NTPSynchronized --property=NTP --property=LocalRTC
health ntp sh -c 'if command -v systemctl >/dev/null 2>&1; then systemctl show chronyd.service chrony.service ntpd.service ntp.service systemd-timesyncd.service --property=Id --property=LoadState --property=ActiveState --property=SubState; fi; if command -v chronyc >/dev/null 2>&1; then chronyc -n tracking && chronyc -n sources; elif command -v ntpq >/dev/null 2>&1; then ntpq -pn; elif command -v timedatectl >/dev/null 2>&1; then timedatectl timesync-status; else exit 125; fi' 
section end
''';

const machineHealthMacCollection =
    machineHealthPosixPrelude +
    r'''
health system sh -c 'uname -a; if [ -r /etc/os-release ]; then cat /etc/os-release; else sw_vers; fi'
health sessions who -u
health logins last -n 30
health accounts sh -c 'printf "@user\tuid\n"; dscl . -list /Users UniqueID | awk "{print \$1 \"\t\" \$2}"'
health password pwpolicy -getaccountpolicies
health ssh sh -c 'data=$(/usr/sbin/sshd -T 2>&1); result=$?; if [ "$result" != 0 ]; then printf "%s\n" "$data"; exit "$result"; fi; printf "%s\n" "$data" | awk "\$1 ~ /^(port|listenaddress|permitrootlogin|passwordauthentication|pubkeyauthentication|kbdinteractiveauthentication|permitemptypasswords|maxauthtries|maxsessions|logingracetime|clientaliveinterval|clientalivecountmax|authenticationmethods)$/"'
health temperature pmset -g therm
health power pmset -g batt
health clock sh -c 'date "+%Y-%m-%d %H:%M:%S %Z %z"; date -u "+%Y-%m-%d %H:%M:%S UTC"'
health sync systemsetup -getusingnetworktime
health ntp systemsetup -getnetworktimeserver
section end
''';

const machineHealthWindowsCollection = r'''
function healthDescribe(items){var result=[];for(var i=0;i<items.length;i++)result.push(describe(items[i]));return result.join("\n\n");}
function healthQuery(key,query,limit){var n=warnings.length;emit("health_"+key,healthDescribe(rows(query,limit)));emit("health_"+key+"_status",warnings.length>n?"1":"0");}
healthQuery("system","SELECT Caption,Version,BuildNumber,OSArchitecture,CSName,LastBootUpTime FROM Win32_OperatingSystem",1);
healthQuery("sessions","SELECT LogonId,LogonType,StartTime FROM Win32_LogonSession",100);
healthQuery("accounts","SELECT Name,Disabled,Lockout,PasswordRequired,PasswordExpires,Status FROM Win32_UserAccount WHERE LocalAccount=True",100);
function healthCommand(key,text,limit){var p=new ActiveXObject("WScript.Shell").Exec("cmd.exe /d /c "+text),start=new Date().getTime();if(typeof ohTrack=="function")ohTrack(p.ProcessID);while(p.Status==0 && new Date().getTime()-start<4000)WScript.Sleep(20);if(p.Status==0){p.Terminate();emit("health_"+key+"_status","1");return;}emit("health_"+key,(p.StdOut.ReadAll()+p.StdErr.ReadAll()).substr(0,limit));emit("health_"+key+"_status",String(p.ExitCode));}
healthCommand("logins",'wevtutil qe Security /q:"*[System[(EventID=4624 or EventID=4625)]]" /rd:true /c:5 /f:text',10000);
healthCommand("password",'net accounts',4000);
healthCommand("ssh",'sc query sshd',2000);
emit("health_temperature_status","125");
healthQuery("power","SELECT Name,BatteryStatus,EstimatedChargeRemaining,EstimatedRunTime FROM Win32_Battery",10);
var clockWarnings=warnings.length;emit("health_clock",healthDescribe(rows("SELECT LocalDateTime,CurrentTimeZone FROM Win32_OperatingSystem",1))+"\n"+healthDescribe(rows("SELECT Caption,StandardName,DaylightName,Bias FROM Win32_TimeZone",1))+"\n"+"UTC\n"+healthDescribe(rows("SELECT Year,Month,Day,Hour,Minute,Second FROM Win32_UTCTime",1)));emit("health_clock_status",warnings.length>clockWarnings?"1":"0");
healthCommand("sync",'w32tm /query /status',4000);
healthCommand("ntp",'sc query w32time && w32tm /query /peers && w32tm /query /configuration',8000);
''';
