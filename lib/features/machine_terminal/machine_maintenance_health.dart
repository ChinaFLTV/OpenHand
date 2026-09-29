import 'package:xml/xml.dart';

import 'machine_maintenance_logs.dart';
import 'machine_maintenance_readout.dart';

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
health system sh -c 'printf "Kernel: %s\nHostname: %s\nKernelRelease: %s\nArchitecture: %s\n" "$(uname -s)" "$(uname -n)" "$(uname -r)" "$(uname -m)"; if [ -r /etc/os-release ]; then cat /etc/os-release; else sw_vers; fi'
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
health system sh -c 'printf "Kernel: %s\nHostname: %s\nKernelRelease: %s\nArchitecture: %s\n" "$(uname -s)" "$(uname -n)" "$(uname -r)" "$(uname -m)"; if [ -r /etc/os-release ]; then cat /etc/os-release; else sw_vers; fi'
health sessions who -u
health logins last -n 30
health accounts dscl . -readall /Users UniqueID PrimaryGroupID NFSHomeDirectory UserShell
health password pwpolicy -getaccountpolicies
health ssh sh -c 'data=$(/usr/sbin/sshd -T 2>&1); result=$?; if [ "$result" != 0 ]; then printf "%s\n" "$data"; exit "$result"; fi; printf "%s\n" "$data" | awk "\$1 ~ /^(port|listenaddress|permitrootlogin|passwordauthentication|pubkeyauthentication|kbdinteractiveauthentication|permitemptypasswords|maxauthtries|maxsessions|logingracetime|clientaliveinterval|clientalivecountmax|authenticationmethods)$/"'
health temperature pmset -g therm
health power sh -c 'pmset -g batt; ioreg -r -c AppleSmartBattery -w0 | sed -n -E "s/.*\"(CycleCount|DesignCapacity|Voltage)\" = ([0-9]+).*/\1: \2/p"'
health clock sh -c 'date "+%Y-%m-%d %H:%M:%S %Z %z"; date -u "+%Y-%m-%d %H:%M:%S UTC"'
health sync sh -c 'out=$(systemsetup -getusingnetworktime 2>&1); code=$?; case "$out" in *"administrator access"*) printf "%s\n" "$out"; exit 1;; *) printf "%s\n" "$out"; exit "$code";; esac'
health ntp sh -c 'if [ -r /etc/ntp.conf ]; then printf "configured: /etc/ntp.conf\n"; awk "\$1 == \"server\" || \$1 == \"pool\" {print \"Network Time Server: \" \$2}" /etc/ntp.conf; else systemsetup -getnetworktimeserver; fi'
section end
''';

const machineHealthWindowsCollection = r'''
function healthDescribe(items){var result=[];for(var i=0;i<items.length;i++)result.push(describe(items[i]));return result.join("\n\n");}
function healthQuery(key,query,limit){var n=warnings.length,items=rows(query,limit),out=healthDescribe(items);if(key=="sessions" || key=="accounts" || key=="power"){var names=query.substring(7,query.indexOf(" FROM")).split(","),lines=["@"+names.join("\t")];for(var i=0;i<items.length;i++){var values=[];for(var j=0;j<names.length;j++)values.push(clean(field(items[i],names[j])));lines.push(values.join("\t"));}out=lines.join("\n");}emit("health_"+key,out);emit("health_"+key+"_status",warnings.length>n?"1":"0");}
healthQuery("system","SELECT Caption,Version,BuildNumber,OSArchitecture,CSName,LastBootUpTime FROM Win32_OperatingSystem",1);
healthQuery("sessions","SELECT LogonId,LogonType,StartTime FROM Win32_LogonSession",100);
healthQuery("accounts","SELECT Name,Disabled,Lockout,PasswordRequired,PasswordExpires,Status FROM Win32_UserAccount WHERE LocalAccount=True",100);
function healthCommand(key,text,limit){var p=new ActiveXObject("WScript.Shell").Exec("cmd.exe /d /c "+text),start=new Date().getTime();if(typeof ohTrack=="function")ohTrack(p.ProcessID);while(p.Status==0 && new Date().getTime()-start<4000)WScript.Sleep(20);if(p.Status==0){p.Terminate();emit("health_"+key+"_status","1");return;}emit("health_"+key,(p.StdOut.ReadAll()+p.StdErr.ReadAll()).substr(0,limit));emit("health_"+key+"_status",String(p.ExitCode));}
healthCommand("logins",'wevtutil qe Security /q:"*[System[(EventID=4624 or EventID=4625)]]" /rd:true /c:20 /f:xml /e:Events',24000);
healthCommand("password",'net accounts',4000);
healthCommand("ssh",'sc query sshd',2000);
emit("health_temperature_status","125");
healthQuery("power","SELECT Name,BatteryStatus,EstimatedChargeRemaining,EstimatedRunTime FROM Win32_Battery",10);
var clockWarnings=warnings.length;emit("health_clock",healthDescribe(rows("SELECT LocalDateTime,CurrentTimeZone FROM Win32_OperatingSystem",1))+"\n"+healthDescribe(rows("SELECT Caption,StandardName,DaylightName,Bias FROM Win32_TimeZone",1))+"\n"+"UTC\n"+healthDescribe(rows("SELECT Year,Month,Day,Hour,Minute,Second FROM Win32_UTCTime",1)));emit("health_clock_status",warnings.length>clockWarnings?"1":"0");
healthCommand("sync",'w32tm /query /status',4000);
healthCommand("ntp",'sc query w32time && w32tm /query /peers && w32tm /query /configuration',8000);
''';

/// 不把工具退出成功等同于数据可用，保留无法识别的样本供诊断。
class MachineHealthReport {
  factory MachineHealthReport.parse(
    String key,
    String raw,
    String status, {
    String locale = 'en',
  }) {
    final text = raw.trim();
    final lines = text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    const empty = MachineMaintenanceReadout([], []);
    if (status == '125') {
      return const MachineHealthReport(empty, issue: 'unsupported');
    }
    if (status == '127' ||
        RegExp(
          'command not found|not recognized',
          caseSensitive: false,
        ).hasMatch(text)) {
      return const MachineHealthReport(empty, issue: 'missing');
    }
    if (RegExp(
      'permission denied|operation not permitted|administrator access|access is denied|access denied',
      caseSensitive: false,
    ).hasMatch(text)) {
      return const MachineHealthReport(empty, issue: 'permission');
    }
    if (text.contains('no hostkeys available')) {
      return const MachineHealthReport(empty, issue: 'hostkeys');
    }
    if (status.isEmpty) {
      return const MachineHealthReport(empty, issue: 'pending');
    }
    if (text.isEmpty) {
      return MachineHealthReport(
        empty,
        issue: status == '0' ? 'empty' : 'failed',
      );
    }
    if (lines.first.startsWith('@')) {
      final headers = lines.first.substring(1).split('\t');
      final rows = lines
          .skip(1)
          .map((s) => s.split('\t'))
          .where((r) => r.length == headers.length)
          .toList();
      return MachineHealthReport(
        MachineMaintenanceReadout(headers, rows),
        issue: status != '0'
            ? 'failed'
            : rows.isEmpty
            ? (lines.length > 1 ? 'format' : 'empty')
            : null,
        unparsed: lines.length - 1 - rows.length,
      );
    }
    final rows = <List<String>>[];
    var skipped = 0;
    var headers = <String>['名称', '数值'];
    var fields = true;
    void add(String name, String value) {
      if (value.trim().isNotEmpty) rows.add([name, value.trim()]);
    }

    if (key == 'password' && text.contains('<plist')) {
      try {
        final doc = XmlDocument.parse(
          text.substring(
            text.contains('<?xml')
                ? text.indexOf('<?xml')
                : text.indexOf('<plist'),
          ),
        );
        for (final dict in doc.findAllElements('dict')) {
          final nodes = dict.childElements.toList();
          for (var i = 0; i + 1 < nodes.length; i++) {
            if (nodes[i].name.local != 'key') continue;
            final name = nodes[i].innerText;
            if (name == 'policyIdentifier') add(name, nodes[i + 1].innerText);
            if (name == 'policyContentDescription') {
              final descriptions = nodes[i + 1].childElements.toList();
              final translated = <String, String>{
                for (var n = 0; n + 1 < descriptions.length; n += 2)
                  descriptions[n].innerText.replaceAll('_', '-'):
                      descriptions[n + 1].innerText,
              };
              final baseLanguage = locale.split('-').first;
              final chineseVariant =
                  locale.contains('Hant') ||
                      locale.endsWith('TW') ||
                      locale.endsWith('HK')
                  ? 'TW'
                  : 'CN';
              final language =
                  translated[locale] ??
                  translated[baseLanguage] ??
                  (baseLanguage == 'zh'
                      ? translated['zh-$chineseVariant'] ??
                            translated[chineseVariant == 'TW'
                                ? 'zh-Hant'
                                : 'zh-Hans']
                      : null) ??
                  translated['en'];
              if (language != null) add('描述', language);
            }
            if (name == 'policyContent') {
              final expression = nodes[i + 1].innerText;
              final minimum = RegExp(r"\.\{(\d+),\}").firstMatch(expression);
              if (minimum != null) {
                add('最少字符数', minimum[1]!);
              } else {
                add(name, expression);
              }
            }
            if (name == 'policyParameters') {
              final params = nodes[i + 1].childElements.toList();
              for (var n = 0; n + 1 < params.length; n += 2) {
                add(params[n].innerText, params[n + 1].innerText);
              }
            }
          }
        }
      } on XmlException {
        return const MachineHealthReport(empty, issue: 'format');
      }
    } else if (key == 'accounts' && text.contains('RecordName:')) {
      fields = false;
      headers = ['user', 'uid', 'GID', 'home', 'shell'];
      var record = <String, String>{};
      for (final line in [...lines, '-']) {
        if (line == '-') {
          if (record.isNotEmpty) {
            rows.add([
              for (final name in [
                'RecordName',
                'UniqueID',
                'PrimaryGroupID',
                'NFSHomeDirectory',
                'UserShell',
              ])
                record[name] ?? '—',
            ]);
          }
          record = {};
        } else {
          final split = line.indexOf(':');
          if (split > 0) {
            record[line.substring(0, split)] = line.substring(split + 1).trim();
          }
        }
      }
    } else if (key == 'logins' && text.startsWith('<')) {
      final buffer = MachineLogBuffer()..append(text, eventLog: true);
      if (buffer.error != null) {
        return const MachineHealthReport(empty, issue: 'format');
      }
      fields = false;
      headers = ['时间', '级别', '消息'];
      rows.addAll(
        buffer.entries.map(
          (e) => [
            e.time,
            ['错误', '警告', '信息'][e.level],
            e.message,
          ],
        ),
      );
    } else if (key == 'sessions' && !text.contains('LogonId')) {
      fields = false;
      headers = ['user', '终端', '登录时间', '空闲时间', 'PID', '来源'];
      for (final line in lines) {
        final m = RegExp(
          r'^(\S+)\s+(\S+)\s+((?:\w{3}\s+\d+|\d{4}-\d\d-\d\d)\s+\d\d:\d\d)\s+(\S+)\s+(\d+)(?:\s+(.*))?$',
        ).firstMatch(line);
        if (m != null) {
          rows.add([for (var i = 1; i <= 6; i++) m[i] ?? '—']);
        } else {
          skipped++;
        }
      }
    } else if (key == 'logins' && !text.contains('Event[')) {
      fields = false;
      headers = ['user', '终端', '来源', '登录时间', '状态'];
      for (final line in lines) {
        if (RegExp('^(wtmp|btmp|utmp) begins').hasMatch(line)) continue;
        final m = RegExp(
          r'^(\S+)\s+(\S+)\s+(.*?)\s*((?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s+\w+\s+\d+\s+[\d:]+(?:\s+\d{4})?)(.*)$',
        ).firstMatch(line);
        if (m != null) {
          rows.add([
            m[1]!,
            m[2]!,
            m[3]!.trim().isEmpty ? '—' : m[3]!.trim(),
            m[4]!,
            m[5]!.trim(),
          ]);
        } else {
          skipped++;
        }
      }
    } else if (key == 'clock' && RegExp(r'^\d{4}-\d\d-\d\d').hasMatch(text)) {
      for (var i = 0; i < lines.length; i++) {
        final m = RegExp(
          r'^(\d{4}-\d\d-\d\d) (\d\d:\d\d:\d\d) (\S+)(?: ([-+]\d{4}))?$',
        ).firstMatch(lines[i]);
        if (m == null) {
          skipped++;
          continue;
        }
        add(i == 0 ? '本地时间' : 'UTC', '${m[1]} ${m[2]}');
        if (i == 0) add('时区', '${m[3]}${m[4] == null ? '' : ' ${m[4]}'}');
      }
    } else if (key == 'power' && text.contains('Now drawing from')) {
      final source = RegExp("Now drawing from '([^']+)'").firstMatch(text);
      if (source != null) add('供电来源', source[1]!);
      for (final line in lines.skip(1)) {
        final m = RegExp(
          r'^(.+?)\s+\(id=(\d+)\)\s+(\d+)%;\s*(.*)$',
        ).firstMatch(line);
        if (m == null) {
          final field = RegExp(r'^([A-Za-z]+):\s*(\d+)$').firstMatch(line);
          if (field != null) {
            add(field[1]!, field[2]!);
          } else {
            skipped++;
          }
          continue;
        }
        add('设备', m[1]!);
        add('ID', m[2]!);
        add('电量', '${m[3]}%');
        for (final part in m[4]!.split(';')) {
          final states = part.split(' present:');
          final text = states.first.trim();
          add(
            RegExp('charg', caseSensitive: false).hasMatch(text)
                ? '充电状态'
                : '状态',
            text,
          );
          if (states.length > 1) add('present', states.last);
        }
      }
    } else if (key == 'temperature' && text.contains('No thermal warning')) {
      for (final line in lines) {
        if (line.contains('No thermal warning')) {
          add('温度告警', '无告警记录');
        } else if (line.contains('No performance warning')) {
          add('性能告警', '无告警记录');
        } else if (line.contains('No CPU power status')) {
          add('CPU 电源状态', '未记录');
        } else {
          final m = RegExp(r'^([^=]+)\s*=\s*(.*)$').firstMatch(line);
          if (m != null) {
            add(m[1]!, m[2]!);
          } else {
            skipped++;
          }
        }
      }
    } else {
      for (final line in lines) {
        if (line.startsWith('#') || line.startsWith('===')) continue;
        if (key == 'system' && RegExp(r'^(Darwin|Linux)\s').hasMatch(line)) {
          final parts = line.split(RegExp(r'\s+'));
          add('操作系统', parts[0]);
          if (parts.length > 2) {
            add('主机名', parts[1]);
            add('内核版本', parts[2]);
            add('架构', parts.last);
          }
          continue;
        }
        final m = RegExp(r'^([^:=]+?)\s*[:=]\s*(.+)$').firstMatch(line);
        if (m != null) {
          add(m[1]!, m[2]!.replaceAll(RegExp(r'^"|"$'), ''));
          continue;
        }
        if (key == 'ssh') {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 2) {
            add(parts.first, parts.skip(1).join(' '));
            continue;
          }
        }
        if (key == 'ntp') {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 6 &&
              RegExp(r'^[\^=#~*+?ox-]').hasMatch(parts.first)) {
            add('来源', parts[0]);
            if (parts.length >= 7 && RegExp(r'^[\^=#~]').hasMatch(parts[0])) {
              for (var i = 1; i <= 5; i++) {
                add(
                  ['', '名称', 'stratum', 'poll', 'reach', 'lastRx'][i],
                  parts[i],
                );
              }
              add('offset', parts.skip(6).join(' '));
            } else if (parts.length >= 10) {
              for (var i = 1; i < parts.length; i++) {
                add(
                  [
                    '来源',
                    '参考源',
                    'stratum',
                    '类型',
                    'lastRx',
                    'poll',
                    'reach',
                    '延迟',
                    'offset',
                    '抖动',
                  ][i.clamp(0, 9)],
                  parts[i],
                );
              }
            }
            continue;
          }
        }
        if (key == 'password') {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 7 &&
              const ['P', 'L', 'NP', 'PS', 'LK'].contains(parts[1])) {
            for (var i = 0; i < 7; i++) {
              add(
                [
                  'user',
                  '密码状态',
                  '最近修改',
                  '最短使用天数',
                  '最长使用天数',
                  '到期预警天数',
                  '失效天数',
                ][i],
                parts[i],
              );
            }
            continue;
          }
        }
        skipped++;
      }
    }
    return MachineHealthReport(
      MachineMaintenanceReadout(headers, rows, fields: fields),
      issue: status != '0'
          ? 'failed'
          : rows.isEmpty
          ? 'format'
          : null,
      unparsed: skipped,
    );
  }
  const MachineHealthReport(this.data, {this.issue, this.unparsed = 0});
  final MachineMaintenanceReadout data;
  final String? issue;
  final int unparsed;
}
