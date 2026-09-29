import 'dart:convert';

import 'package:xml/xml.dart';

const machineLogSources = ['system', 'kernel', 'security'];
const machineLogLimit = 1000;

const machineLogsLinuxCollection = r'''
log_limit() { awk 'length($0) <= 16000 { total += length($0); if (total > 60000) exit; print }'; }
section log_system
if command -v journalctl >/dev/null 2>&1; then
  bounded journalctl -n 120 --no-pager -o json 2>&1 | log_limit
else
  tail -n 120 /var/log/syslog /var/log/messages 2>&1 | log_limit
fi
section log_kernel
if command -v journalctl >/dev/null 2>&1; then
  bounded journalctl -k -n 120 --no-pager -o json 2>&1 | log_limit
else
  bounded dmesg 2>&1 | tail -n 120 | log_limit
fi
section log_security
if [ -r /var/log/auth.log ]; then tail -n 100 /var/log/auth.log
elif [ -r /var/log/secure ]; then tail -n 100 /var/log/secure
elif command -v journalctl >/dev/null 2>&1; then bounded journalctl SYSLOG_FACILITY=4 SYSLOG_FACILITY=10 -n 100 --no-pager -o json 2>&1 | log_limit
else printf '__OH_LOG_UNAVAILABLE__\n'; fi
section log_rotation
for f in /var/lib/logrotate/status /var/lib/logrotate/logrotate.status /var/lib/logrotate.status; do
  [ -r "$f" ] && { printf '%s\n' "$f"; head -c 16000 "$f"; break; }
done
section log_config
for f in /etc/logrotate.conf /etc/logrotate.d/*; do
  [ -f "$f" ] && [ -r "$f" ] && { printf '\n%s\n' "$f"; head -c 2000 "$f"; }
done | head -c 24000
section log_storage
du -sk /var/log 2>/dev/null
section end
''';

const machineLogsMacCollection = r'''
log_limit() { awk 'length($0) <= 16000 { total += length($0); if (total > 60000) exit; print }'; }
section log_system
/usr/bin/log show --last 2m --style ndjson --info 2>&1 | tail -n 120 | log_limit
section log_kernel
/sbin/dmesg 2>&1 | tail -n 120 | log_limit
section log_security
/usr/bin/log show --last 5m --style ndjson --predicate '(process == "sshd") OR (process == "login") OR (process == "authorizationhost")' 2>&1 | tail -n 100 | log_limit
section log_rotation
ls -lT /var/log/*.gz /var/log/*.bz2 /var/log/*.0 2>/dev/null | head -c 16000
section log_config
for f in /etc/newsyslog.conf /etc/newsyslog.d/*.conf; do
  [ -f "$f" ] && [ -r "$f" ] && { printf '\n%s\n' "$f"; head -c 2000 "$f"; }
done | head -c 24000
section log_storage
du -sk /var/log 2>/dev/null
section end
''';

const machineLogsWindowsCollection = r'''
emit("log_system", command('wevtutil qe System /rd:true /c:10 /f:xml /e:Events', 18000));
emit("log_kernel", command("wevtutil qe System /q:\"*[System[Provider[@Name='Microsoft-Windows-Kernel-General'] or Provider[@Name='Microsoft-Windows-Kernel-Power'] or Provider[@Name='Microsoft-Windows-Kernel-Boot']]]\" /rd:true /c:10 /f:xml /e:Events", 18000));
emit("log_security", command('wevtutil qe Security /rd:true /c:10 /f:xml /e:Events', 18000));
emit("log_rotation", command('wevtutil gli System', 6000));
emit("log_config", command('wevtutil gl System', 6000));
''';

class MachineLogEntry {
  const MachineLogEntry(this.id, this.time, this.message, this.level);
  final String id, time, message;
  final int level;
  String get signature => '$time\u0000$level\u0000$message';
}

class MachineLogBuffer {
  final entries = <MachineLogEntry>[];
  List<String> _previous = [];
  String? error;
  int _sequence = 0;

  void append(String raw, {bool eventLog = false}) {
    final text = raw.trim();
    if (text.isEmpty || text == '-- No entries --') {
      error = null;
      return;
    }
    if (eventLog && !text.startsWith('<')) {
      error = text.substring(0, text.length.clamp(0, 500));
      return;
    }
    final incoming = <MachineLogEntry>[];
    try {
      if (text.startsWith('<Events') || text.startsWith('<?xml')) {
        final document = XmlDocument.parse(text);
        for (final event in document.findAllElements('Event')) {
          String field(String name) =>
              event.findAllElements(name).firstOrNull?.innerText ?? '';
          final timestamp =
              event
                  .findAllElements('TimeCreated')
                  .firstOrNull
                  ?.getAttribute('SystemTime') ??
              '';
          final message = field('Message');
          final details = event
              .findAllElements('Data')
              .map((d) => '${d.getAttribute('Name') ?? ''}: ${d.innerText}')
              .join('\n');
          final provider =
              event
                  .findAllElements('Provider')
                  .firstOrNull
                  ?.getAttribute('Name') ??
              '';

          incoming.add(
            MachineLogEntry(
              '${field('Channel')}:${field('EventRecordID')}',
              timestamp,
              message.isNotEmpty
                  ? message
                  : details.isNotEmpty
                  ? details
                  : '$provider ${field('EventID')}',
              switch (field('Level')) {
                '1' || '2' => 0,
                '3' => 1,
                _ => 2,
              },
            ),
          );
        }
        incoming.sort((a, b) => a.time.compareTo(b.time));
      } else {
        for (final line in const LineSplitter().convert(text).take(240)) {
          if (line.startsWith('{')) {
            final value = jsonDecode(line);
            if (value is! Map) continue;
            final message = value['MESSAGE'] ?? value['eventMessage'];
            if (message == null) continue;
            final micros = int.tryParse('${value['__REALTIME_TIMESTAMP']}');
            final time = micros == null
                ? '${value['timestamp'] ?? ''}'
                : DateTime.fromMicrosecondsSinceEpoch(
                    micros,
                    isUtc: true,
                  ).toIso8601String();
            final priority = int.tryParse('${value['PRIORITY']}');
            incoming.add(
              MachineLogEntry(
                '${value['__CURSOR'] ?? '$time:${value['processID']}:${value['threadID']}:$message'}',
                time,
                '$message',
                priority != null
                    ? (priority <= 3
                          ? 0
                          : priority == 4
                          ? 1
                          : 2)
                    : _level('$message'),
              ),
            );
          } else if (RegExp(
            '^(__OH_LOG_UNAVAILABLE__|dmesg:|log:|tail:|wevtutil:|Failed to open|Access is denied|No journal files|Hint:|查询超时|Failed to read|The specified channel)',
            caseSensitive: false,
          ).hasMatch(line)) {
            error = line;
            return;
          } else if (line.isNotEmpty && !line.startsWith('==>')) {
            incoming.add(MachineLogEntry('', '', line, _level(line)));
          }
        }
      }
    } on FormatException {
      error = text.substring(0, text.length.clamp(0, 500));
      return;
    }
    error = null;
    final signatures = incoming
        .map((e) => e.id.isEmpty ? e.signature : e.id)
        .toList();
    var overlap = 0;
    for (
      var n = _previous.length < signatures.length
          ? _previous.length
          : signatures.length;
      n > 0;
      n--
    ) {
      var matches = true;
      for (var i = 0; i < n; i++) {
        if (_previous[_previous.length - n + i] != signatures[i]) {
          matches = false;
          break;
        }
      }
      if (matches) {
        overlap = n;
        break;
      }
    }
    final ids = entries.map((e) => e.id).toSet();
    for (final entry in incoming.skip(overlap)) {
      if (entry.id.isNotEmpty && !ids.add(entry.id)) continue;
      final message = entry.message.length > 8000
          ? '${entry.message.substring(0, 8000)}…'
          : entry.message;
      entries.add(
        MachineLogEntry(
          entry.id.isEmpty ? 'local:${_sequence++}' : entry.id,
          entry.time,
          message,
          entry.level,
        ),
      );
    }
    if (entries.length > machineLogLimit) {
      entries.removeRange(0, entries.length - machineLogLimit);
    }
    _previous = signatures;
  }

  static int _level(String message) {
    if (RegExp(
      r'\b(error|fatal|panic|critical|failed)\b',
      caseSensitive: false,
    ).hasMatch(message)) {
      return 0;
    }
    if (RegExp(r'\b(warn|warning)\b', caseSensitive: false).hasMatch(message)) {
      return 1;
    }
    return 2;
  }
}

/// 轮转状态与规则独立解析，脚本正文不作为日志事件展示。
class MachineLogMetadata {
  static List<List<String>> parse(String text, String kind) {
    final rows = <List<String>>[];
    var source = '';
    var target = '';
    var script = false;
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trim();
      if (line.isEmpty ||
          line.startsWith('#') ||
          line.startsWith('logrotate state')) {
        continue;
      }
      if (kind == 'storage') {
        final m = RegExp(r'^(\d+)\s+(.+)$').firstMatch(line);
        if (m != null) rows.add([m[2]!, 'KiB', m[1]!]);
        continue;
      }
      if (line.startsWith('/') && !line.contains(RegExp(r'\s'))) {
        source = line;
        continue;
      }
      if (kind == 'rotation') {
        final state = RegExp(r'^"(.+)"\s+(.+)$').firstMatch(line);
        if (state != null) {
          rows.add([state[1]!, '最近轮转', state[2]!]);
          continue;
        }
        final archive = RegExp(
          r'^\S+\s+\d+\s+\S+\s+\S+\s+(\d+)\s+(\w+\s+\d+\s+[\d:]+\s+\d+)\s+(.+)$',
        ).firstMatch(line);
        if (archive != null) {
          rows.add([archive[3]!, '字节', archive[1]!]);
          rows.add([archive[3]!, '修改时间', archive[2]!]);
          continue;
        }
      }
      if (kind == 'config') {
        if (line == 'endscript') {
          script = false;
          continue;
        }
        if (RegExp(
          r'^(postrotate|prerotate|firstaction|lastaction|preremove)\b',
        ).hasMatch(line)) {
          rows.add([target.isEmpty ? source : target, line, '已配置']);
          script = true;
          continue;
        }
        if (script) continue;
        if (line.contains('{')) {
          target = line.split('{').first.trim();
          continue;
        }
        if (line == '}') {
          target = '';
          continue;
        }
        final parts = line.split(RegExp(r'\s+'));
        if (parts.first.startsWith('/') && parts.length >= 6) {
          final owner = parts[1].contains(':');
          final names = owner
              ? ['名称', '属主', '权限', '保留份数', '大小阈值', '轮转时间', '选项', 'PID 文件', '信号']
              : ['名称', '权限', '保留份数', '大小阈值', '轮转时间', '选项', 'PID 文件', '信号'];
          for (var i = 1; i < parts.length && i < names.length; i++) {
            rows.add([parts.first, names[i], parts[i]]);
          }
          continue;
        }
        rows.add([
          target.isEmpty ? source : target,
          parts.first,
          parts.skip(1).join(' ').isEmpty ? '已配置' : parts.skip(1).join(' '),
        ]);
        continue;
      }
      final field = RegExp(r'^([^:]+):\s*(.*)$').firstMatch(line);
      if (field != null) rows.add([source, field[1]!, field[2]!]);
    }
    return rows;
  }
}
